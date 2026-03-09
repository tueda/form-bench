#!/bin/sh
""":" .

exec python3 "$0" "$@"
"""

from __future__ import annotations

__doc__ = """Summarize benchmark results."""

import argparse
import itertools
import json
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, assert_never
from warnings import warn

import jsonschema
import numpy as np
import scipy.stats
from tabulate import tabulate

if TYPE_CHECKING:
    from collections.abc import Callable, Iterable, Sequence
    from typing import Any, Literal

    import numpy.typing as npt

if sys.version_info >= (3, 12):
    from itertools import batched
else:
    from typing import TypeVar

    T = TypeVar("T")

    def batched(iterable: Iterable[T], n: int) -> Iterable[tuple[T, ...]]:  # noqa: D103
        if n < 1:
            msg = f"n must be at least one, got n={n}"
            raise ValueError(msg)
        it = iter(iterable)
        while batch := tuple(itertools.islice(it, n)):
            yield batch


def int_to_letter(n: int) -> str:
    """Convert an integer in [0, 25] to 'A'..'Z'."""
    if not (0 <= n < 26):  # noqa: PLR2004
        msg = f"n must be in [0, 25], but got {n}"
        raise ValueError(msg)

    return chr(ord("A") + n)


def letter_to_int(s: str) -> int:
    """Convert 'A'..'Z' to an integer in [0, 25]."""
    s = s.upper()
    if len(s) != 1 or not ("A" <= s <= "Z"):
        msg = f"s must be a single letter in 'A'..'Z', but got {s!r}"
        raise ValueError(msg)
    return ord(s) - ord("A")


def ratio_ci(  # noqa: C901, PLR0913
    x: npt.ArrayLike,
    y: npt.ArrayLike,
    *,
    statistic: Literal["mean", "gmean", "median"] = "mean",
    n_resamples: int = 10000,
    paired: bool = False,
    confidence_level: float = 0.95,
    method: Literal["percentile", "basic", "BCa"] = "BCa",
    rng: None | int | np.random.Generator = None,
) -> tuple[float, tuple[float, float]]:
    """Estimate the ratio and bootstrap CI."""
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)

    if x.size == 0 or y.size == 0:
        msg = "x and y must be non-empty"
        raise ValueError(msg)

    if statistic == "gmean" and (np.any(x <= 0) or np.any(y <= 0)):
        msg = "gmean requires all values to be positive"
        raise ValueError(msg)

    if n_resamples < 1:
        msg = f"n_resamples must be positive, but got {n_resamples}"
        raise ValueError(msg)

    if paired and len(x) != len(y):
        msg = f"paired bootstrap requires len(x) == len(y), but {len(x)} != {len(y)}"
        raise ValueError(msg)

    if not (0.0 < confidence_level < 1.0):
        msg = f"confidence_level must be between 0 and 1, but got {confidence_level}"
        raise ValueError(msg)

    f: Callable[..., npt.NDArray[np.float64]]
    match statistic:
        case "mean":
            f = np.mean
        case "gmean":
            f = scipy.stats.gmean  # type: ignore[assignment]
        case "median":
            f = np.median
        case _:
            assert_never(statistic)

    def statistic_func(
        a: npt.NDArray[np.float64], b: npt.NDArray[np.float64], axis: int = -1
    ) -> npt.NDArray[np.float64]:
        return f(a, axis=axis) / f(b, axis=axis)

    ratio = float(statistic_func(x, y))
    if not np.isfinite(ratio):
        msg = f"ratio is not finite: {ratio}"
        raise ValueError(msg)

    result = scipy.stats.bootstrap(
        (x, y),
        statistic=statistic_func,
        n_resamples=n_resamples,
        vectorized=True,
        paired=paired,
        confidence_level=confidence_level,
        method=method,
        rng=rng,
    )

    ci = (float(result.confidence_interval.low), float(result.confidence_interval.high))

    return ratio, ci


@dataclass(frozen=True, slots=True)
class Options:
    """Program options."""

    ratio: Literal["mean", "gmean", "median"]
    compare: tuple[int, int]
    confidence_level: float
    precision: int


@dataclass(frozen=True, slots=True)
class BenchmarkResults:
    """Benchmark results."""

    names: tuple[str, ...]
    commands: tuple[str, ...]
    times: tuple[float, ...]
    memory_usage: tuple[int, ...]
    exit_codes: tuple[int, ...]

    def __post_init__(self) -> None:
        """Validate field lengths."""
        lengths = [
            len(self.names),
            len(self.commands),
            len(self.times),
            len(self.memory_usage),
            len(self.exit_codes),
        ]
        if len(set(lengths)) > 1:
            msg = f"all fields must have the same length, but got: {lengths}"
            raise ValueError(msg)

    def __len__(self) -> int:
        """Return the number of runs."""
        return len(self.names)

    def __add__(self, other: BenchmarkResults) -> BenchmarkResults:
        """Concatenate two BenchmarkResults."""
        if not isinstance(other, BenchmarkResults):
            return NotImplemented
        return BenchmarkResults(
            self.names + other.names,
            self.commands + other.commands,
            self.times + other.times,
            self.memory_usage + other.memory_usage,
            self.exit_codes + other.exit_codes,
        )

    @property
    def unique_names(self) -> tuple[str, ...]:
        """Benchmark names with duplicates removed."""
        return tuple(dict.fromkeys(self.names))

    @property
    def unique_commands(self) -> tuple[str, ...]:
        """Benchmarked command names with duplicates removed."""
        return tuple(dict.fromkeys(self.commands))

    @property
    def blocked(self) -> bool:
        """Return True if commands appear in consecutive complete blocks."""
        command_set = set(self.unique_commands)
        n_commands = len(command_set)
        if n_commands < 2:  # noqa: PLR2004
            return False
        if len(self.commands) % n_commands != 0:
            return False
        for batch in batched(self.commands, n_commands):
            if set(batch) != command_set:
                return False
        return True

    def query(
        self,
        *,
        name: str | None = None,
        command: str | None = None,
        succeeded: bool | None = None,
    ) -> BenchmarkResults:
        """Filter results by name, command and/or success status."""
        indices = [
            i
            for i, (n, c, e) in enumerate(
                zip(self.names, self.commands, self.exit_codes, strict=True)
            )
            if (name is None or n == name)
            and (command is None or c == command)
            and (succeeded is None or (e == 0 if succeeded else e != 0))
        ]
        return BenchmarkResults(
            tuple(self.names[i] for i in indices),
            tuple(self.commands[i] for i in indices),
            tuple(self.times[i] for i in indices),
            tuple(self.memory_usage[i] for i in indices),
            tuple(self.exit_codes[i] for i in indices),
        )


def _get_result_file_schema() -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "type": "object",
        "required": ["results"],
        "properties": {
            "results": {
                "type": "array",
                "items": {
                    "type": "object",
                    "required": [
                        "command",
                        "times",
                        "exit_codes",
                    ],
                    "properties": {
                        "command": {"type": "string"},
                        "times": {
                            "type": "array",
                            "items": {"type": "number"},
                        },
                        "memory_usage_byte": {
                            "type": "array",
                            "items": {"type": "integer"},
                        },
                        "exit_codes": {
                            "type": "array",
                            "items": {"type": "integer"},
                        },
                    },
                },
            },
        },
    }


def read_result(file: Path) -> BenchmarkResults:
    """Read a benchmark result file."""
    m = re.match(r"^results-(.+)\.json$", file.name)
    if not m:
        msg = f'invalid filename: {file} (expected "results-*.json")'
        raise ValueError(msg)
    name = m.group(1)

    with file.open(encoding="utf-8") as f:
        data = json.load(f)

    jsonschema.validate(data, _get_result_file_schema())

    all_commands = []
    all_times = []
    all_memory_usage = []
    all_exit_codes = []

    for i, result in enumerate(data["results"]):
        command: str = result["command"]
        times: list[float] = result["times"]
        exit_codes: list[int] = result["exit_codes"]
        if "memory_usage_byte" in result:
            memory_usage_byte: list[int] = result["memory_usage_byte"]
        else:
            memory_usage_byte = [0] * len(times)

        if len({len(times), len(memory_usage_byte), len(exit_codes)}) != 1:
            msg = (
                f"length mismatch in {file} (command #{i + 1}: {command}): "
                f"times({len(times)}), "
                f"memory_usage_byte({len(memory_usage_byte)}), "
                f"exit_codes({len(exit_codes)})"
            )
            raise ValueError(msg)

        all_commands.extend([command] * len(times))
        all_times.extend(times)
        all_memory_usage.extend(memory_usage_byte)
        all_exit_codes.extend(exit_codes)

    return BenchmarkResults(
        (name,) * len(all_commands),
        tuple(all_commands),
        tuple(all_times),
        tuple(all_memory_usage),
        tuple(all_exit_codes),
    )


def summarize_results(results: BenchmarkResults, options: Options) -> str:
    """Summarize a benchmark result."""
    items = [_summarize_commands(results)]
    unique_commands = results.unique_commands
    if len(unique_commands) >= 2:  # noqa: PLR2004
        items.append(_summarize_results_2(results, options))
    return "\n\n".join(items)


def _summarize_commands(results: BenchmarkResults) -> str:
    tab = tabulate(
        [[int_to_letter(i), f"`{c}`"] for i, c in enumerate(results.unique_commands)],
        headers=["", "Command"],
        tablefmt="github",
    )

    items = [tab]

    for i, c in enumerate(results.unique_commands):
        try:
            argv = shlex.split(c)
            if not argv:
                continue
            # Print verbose version information for FORM.
            cmd = argv[0]
            if not re.search(r"(?:\b|_)(?:t?[fv]orm|par[fv]orm)(?:\b|_)", cmd):
                continue
            p = subprocess.run(  # noqa: S603
                [cmd, "-vv"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=False,
                text=True,
                timeout=1,
            )
            if p.returncode == 0:
                items.append(f"**{int_to_letter(i)}:**\n```\n{p.stdout.strip()}\n```")
        except (OSError, ValueError):
            pass

    return "\n\n".join(items)


def _stabilize_ratio_ci(  # noqa: PLR0913
    x: npt.ArrayLike,
    y: npt.ArrayLike,
    *,
    statistic: Literal["mean", "gmean", "median"],
    n_resamples: int,
    paired: bool,
    confidence_level: float,
    method: Literal["percentile", "basic", "BCa"],
    precision: int,
    max_iteration: int,
    max_resamples: int,
    name: str,
) -> tuple[float, tuple[float, float]]:
    prev = None
    stable = 0
    n = n_resamples

    # Use the same random stream for each iteration so that bootstrap resamples
    # generated with larger n_resamples extend those generated with smaller n_resamples.
    # See the implementation of bootstrap() in scipy/stats/_resampling.py.
    # This behavior is present at least in SciPy 1.17 and can be verified by
    # inspecting res.bootstrap_distribution.
    seed = np.random.SeedSequence().entropy

    for it in range(max_iteration):
        last_n = n
        r, ci = ratio_ci(
            x,
            y,
            statistic=statistic,
            n_resamples=n,
            paired=paired,
            confidence_level=confidence_level,
            method=method,
            rng=np.random.default_rng(seed),
        )
        rounded = (round(ci[0], precision), round(ci[1], precision))
        if prev is not None and rounded == prev:
            stable += 1
            if stable >= 2:  # noqa: PLR2004
                break
        else:
            stable = 0
            prev = rounded
        n *= 2
        if n > max_resamples:
            msg = (
                f"failed to stabilize CI for {name} after {it + 1} iterations "
                f"(n_resamples={last_n})"
            )
            warn(msg, stacklevel=2)
            break
    else:
        msg = (
            f"failed to stabilize CI for {name} after {max_iteration} iterations "
            f"(n_resamples={last_n})"
        )
        warn(msg, stacklevel=2)

    return r, ci


def _summarize_results_2(results: BenchmarkResults, options: Options) -> str:
    unique_commands = results.unique_commands
    unique_names = results.unique_names

    index1, index2 = options.compare
    letter1 = int_to_letter(index1)
    letter2 = int_to_letter(index2)

    if not (0 <= index1 < len(unique_commands) and 0 <= index2 < len(unique_commands)):
        msg = (
            f"unavailable commands: "
            f"{int_to_letter(index2)}/{int_to_letter(index1)}; "
            f"only A..{int_to_letter(len(unique_commands) - 1)} are available"
        )
        raise ValueError(msg)

    items = []

    match options.ratio:
        case "gmean":
            time_of = "geometric mean"
        case _:
            time_of = options.ratio
    time_of += " time of"
    eq = (
        f"**Speedup of {letter2} over {letter1} ({options.ratio}) = "
        f"({time_of} {letter1}) / ({time_of} {letter2})**"
    )

    items.append(eq)

    statistic: Literal["mean", "gmean", "median"] = options.ratio
    confidence_level = options.confidence_level
    method: Literal["BCa"] = "BCa"
    precision = options.precision
    n_resamples = min(10 ** (precision + 1), 500_000)
    max_iteration = 10
    max_resamples = 2_000_000

    failed = results.query(succeeded=False)
    if failed:
        msg = (
            f"non-zero exit codes found: "
            f"{len(failed)} out of {len(results)}; "
            "these runs are ignored"
        )
        warn(msg, stacklevel=2)

    rows = []
    records = []

    for name in sorted(unique_names):
        failed = results.query(name=name, succeeded=False)
        r1 = results.query(name=name, command=unique_commands[index1], succeeded=True)
        r2 = results.query(name=name, command=unique_commands[index2], succeeded=True)

        if len(r1) == 0 or len(r2) == 0:
            continue

        # Use paired bootstrap only if we are sure that all the runs are interleaved
        # or blocked.
        paired = not failed and results.query(name=name, succeeded=True).blocked

        r, ci = _stabilize_ratio_ci(
            r1.times,
            r2.times,
            statistic=statistic,
            n_resamples=n_resamples,
            paired=paired,
            confidence_level=confidence_level,
            method=method,
            precision=precision,
            max_iteration=max_iteration,
            max_resamples=max_resamples,
            name=name,
        )

        rows.append(
            (
                name,
                f"{r:.{precision}f}",
                f"[{ci[0]:.{precision}f}, {ci[1]:.{precision}f}]",
            )
        )

        records.append((name, len(r1), len(r2), paired))

    if rows:
        tab = tabulate(
            rows,
            headers=[
                "Benchmark",
                "Speedup",
                f"{confidence_level * 100:g}% bootstrap CI",
            ],
            tablefmt="github",
            floatfmt=f".{precision}f",
        )
        items.append(tab)

        if (
            all(r[3] for r in records)
            and len({r[1] for r in records} | {r[2] for r in records}) == 1
        ):
            items.append(f"Paired runs with n = {records[0][1]} per benchmark.")
        else:
            tab = tabulate(
                records,
                headers=["Benchmark", f"n({letter1})", f"n({letter2})", "paired"],
                tablefmt="github",
            )
            items.append(tab)

    return "\n\n".join(items)


def filter_files(files: Iterable[Path]) -> list[Path]:
    """Filter result files."""
    return [f for f in files if f.is_file() and re.match(r"^results-.*\.json$", f.name)]


def process_files(files: Sequence[Path], options: Options) -> None:
    """Process result files."""
    files = sorted(filter_files(files))
    results: BenchmarkResults | None = None
    for f in files:
        r = read_result(f)
        if results is None:
            results = r
        else:
            results += r
    if results:
        print(summarize_results(results, options))  # noqa: T201


def collect_result_files(paths: Iterable[Path]) -> list[Path]:
    """Collect result files from the given paths."""
    files = set()
    for path in paths:
        if path.is_file():
            new_files = filter_files([path])
        elif path.is_dir():
            new_files = filter_files(path.iterdir())
            if not new_files:
                subdir = path / "results"
                if subdir.is_dir():
                    new_files = collect_result_files([subdir])
        else:
            msg = f"not a file or directory: {path}"
            raise ValueError(msg)
        files |= set(new_files)
    return sorted(files)


def main(args: Sequence[str] | None = None) -> None:
    """Entry point."""
    if args is None:
        args = sys.argv[1:]

    parser = argparse.ArgumentParser(
        usage="%(prog)s [options] path...",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--ratio",
        choices=["mean", "gmean", "median"],
        default="mean",
        help="statistic used in the ratio",
    )
    parser.add_argument(
        "--compare",
        default="B/A",
        help="specify the comparison in the form B/A",
        metavar="B/A",
    )
    parser.add_argument(
        "--confidence-level",
        type=float,
        default=0.95,
        help="confidence level for the CI",
        metavar="CL",
    )
    parser.add_argument(
        "--precision",
        type=int,
        default=2,
        help="number of decimal places in output",
        metavar="N",
    )
    parser.add_argument("path", nargs="+", help=argparse.SUPPRESS)

    parsed_args = parser.parse_args(args)

    a = parsed_args.compare.split("/")
    if len(a) != 2:  # noqa: PLR2004
        parser.error("--compare must be in the form B/A")
    try:
        index1 = letter_to_int(a[1])
        index2 = letter_to_int(a[0])
    except ValueError:
        parser.error("--compare must be in the form B/A where A and B are letters")
    if index1 == index2:
        parser.error(
            "--compare must be in the form B/A where A and B are different letters"
        )

    if not (0.0 < parsed_args.confidence_level < 1.0):
        parser.error("--confidence-level must be between 0 and 1")

    if parsed_args.precision <= 0:
        parser.error("--precision must be positive")

    files = collect_result_files(Path(f) for f in parsed_args.path)

    if not files:
        msg = "no result files found"
        raise ValueError(msg)

    options = Options(
        ratio=parsed_args.ratio,
        compare=(index1, index2),
        confidence_level=parsed_args.confidence_level,
        precision=parsed_args.precision,
    )

    process_files(files, options)


if __name__ == "__main__":
    main()
