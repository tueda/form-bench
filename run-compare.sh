#!/bin/bash
set -eE
trap 'echo Cleaning up ; rm -rf "$TESTDIR" "$ORIGDIR/output/$RUN_ID-$LABEL-$TIMESTAMP"' ERR


###############################################################################

# Compare multiple FORM binaries over the range of benchmarks. This is useful
# for testing performance optimizations of the code or checking for regressions.
# Parallel scaling can be checked by using the same binary with multiple worker
# counts.


# Configurable parameters: set their default values and then re-set with user args

# The output directory will be called $RUN_ID-$LABEL-$TIMESTAMP
LABEL="scaling-test"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)

# The tests will be run from here. Using a tmpfs (eg, /dev/shm or perhaps /tmp)
# removes disk-access performance effects from the timings.
TESTDIRBASE="${TMPDIR:-/tmp}"

# Negative nice can lead to more consistent timings, if the user has permission.
NICE=0

# Comma-separated list of FORM commands to test:
FORM_CMDS="\
tform-5.0.0 -w8\
,tform-master -w8\
"

# All current tests
TESTS="chromatic color fmft forcer forcer-exp hyperform mbox1l minceex mincer mzv-dm sort-disk sort-large sort-small trace"

# Number of times to run test batches. Running more times leads to more reliable
# timing statistics, but increases total test run time.
N=1

# Run a harder version of the tests? Not all tests are affected by this.
DIFFICULTY=1


error() {
	echo "error: $*" >&2
	exit 1
}

is_int() {
	[[ $1 =~ ^-?[1-9][0-9]*$ ]]
}

is_positive_int() {
	[[ $1 =~ ^[1-9][0-9]*$ ]]
}

require_arg() {
	[[ $# -ge 2 ]] || error "$1 requires an argument"
}

require_int_arg() {
	require_arg "$@"
	is_int "$2" || error "$1 must be an integer"
}

require_positive_int_arg() {
	require_arg "$@"
	is_positive_int "$2" || error "$1 must be a positive integer"
}

cmd_n=
cmd_min_n=
cmd_max_n=
cmd_interleave=
cmd_form_tmp=
cmd_form_tmp_sort=
cmd_tests=()
cmd_args=()


# Now check for non-default options from the user:
while [[ $# -gt 0 ]]; do
	case $1 in
		-n)
			require_positive_int_arg "$@"
			cmd_n=$2
			shift 2
			;;
		--min-n)
			require_positive_int_arg "$@"
			cmd_min_n=$2
			shift 2
			;;
		--max-n)
			require_positive_int_arg "$@"
			cmd_max_n=$2
			shift 2
			;;
		-i|--interleave)
			cmd_interleave=1
			shift
			;;
		--runs)
			require_positive_int_arg "$@"
			N=$2
			shift 2
			;;
		--difficulty)
			require_positive_int_arg "$@"
			DIFFICULTY=$2
			shift 2
			;;
		--label)
			require_arg "$@"
			LABEL=$2
			shift 2
			;;
		--timestamp)
			require_arg "$@"
			TIMESTAMP=$2
			shift 2
			;;
		--nice)
			require_int_arg "$@"
			NICE=$2
			shift 2
			;;
		--testdir|--test-dir-base)
			require_arg "$@"
			TESTDIRBASE=$2
			shift 2
			;;
		--form-tmp)
			require_arg "$@"
			cmd_form_tmp=$2
			shift 2
			;;
		--form-tmp-sort)
			require_arg "$@"
			cmd_form_tmp_sort=$2
			shift 2
			;;
		-v|--verbose)
			# for compatibility
			shift
			;;
		--form_cmds)
			require_arg "$@"
			FORM_CMDS=$2
			shift 2
			;;
		-t|--test)
			require_arg "$@"
			IFS=, read -r -a tmp_tests <<<"$2"
			for tmp_test in "${tmp_tests[@]}"; do
				if [[ -n $tmp_test ]]; then
					cmd_tests+=("$tmp_test")
				fi
			done
			shift 2
			;;
		--)
			shift
			cmd_args+=("$@")
			break
			;;
		-*)
			error "invalid option: $1"
			;;
		*)
			cmd_args+=("$1")
			shift
			;;
	esac
done

if (( ${#cmd_tests[@]} > 0 )); then
	TESTS="${cmd_tests[*]}"
fi

if (( ${#cmd_args[@]} > 0 )); then
	FORM_CMDS=$(IFS=','; echo "${cmd_args[*]}")
fi

# This variable needs to be available within form scripts:
export DIFFICULTY

echo "form-bench: $(git rev-parse HEAD)"
echo "	LABEL      = $LABEL"
echo "	TESTDIR    = $TESTDIRBASE"
echo "	TIMESTAMP  = $TIMESTAMP"
echo "	NICE       = $NICE"
echo "	N          = $N"
echo "	DIFFICULTY = $DIFFICULTY"

# Load test run and warmup counts:
tests_list=()
runs_list=()
warmup_list=()
for test in $TESTS; do
	if [ ! -d "tests/$test" ]; then
		error "invalid test: $test"
	fi

	source "tests/$test/conf.sh"
	tests_list+=("$test")
	runs_list+=("$((N * runs))")
	warmup_list+=("$warmup")
done

if [[ -n $cmd_n ]]; then
	for i in "${!runs_list[@]}"; do
		runs_list[$i]=$cmd_n
	done
fi

if [[ -n $cmd_min_n ]]; then
	for i in "${!runs_list[@]}"; do
		if (( ${runs_list[$i]} < cmd_min_n )); then
			runs_list[$i]=$cmd_min_n
		fi
	done
fi

if [[ -n $cmd_max_n ]]; then
	for i in "${!runs_list[@]}"; do
		if (( ${runs_list[$i]} > cmd_max_n )); then
			runs_list[$i]=$cmd_max_n
		fi
	done
fi

if (( ${#cmd_args[@]} > 0 )); then
	FORM_CMDS=$(IFS=','; echo "${cmd_args[*]}")
fi

if [[ -n $cmd_interleave ]]; then
	[[ -n $cmd_n ]] || error "--interleave option requires -n"
	for i in "${!runs_list[@]}"; do
		runs_list[$i]=1
	done
	tmp_form_cmds=$FORM_CMDS
	for ((i=1; i<cmd_n; i++)); do
		FORM_CMDS+="${FORM_CMDS:+,}$tmp_form_cmds"
	done
fi

for t in $TESTS; do
	echo "Test: $t: ${runs_list[$t]} runs (warmup: ${warmup_list[$t]})"
done
(
	IFS=,
	for c in $FORM_CMDS; do
		echo "Command: $c"
	done
)

# Check for python3 and hyperfine:
for bin in hyperfine python3; do
	if ! command -v "$bin" &> /dev/null; then
		error "script requires $bin"
	fi
done

# Check for the specified FORM binaries:
for form in $(echo "$FORM_CMDS" | sed -E -e 's/ -w[0-9]+//g' -e 's/,/ /g'); do
	if ! command -v "$form" &> /dev/null; then
		error "script requires $form"
	fi
done

ORIGDIR=$(pwd)

RUN_NUMBER=1
while :; do
	RUN_ID=$(printf "%04d" "$RUN_NUMBER")
	if ! compgen -G "$ORIGDIR/output/$RUN_ID-*" >/dev/null; then
		break
	fi
	RUN_NUMBER=$((RUN_NUMBER + 1))
done

RESULTSDIR="$ORIGDIR/output/$RUN_ID-$LABEL-$TIMESTAMP/results/"
echo "Results: $RESULTSDIR"
LOGDIR="$ORIGDIR/output/$RUN_ID-$LABEL-$TIMESTAMP/logs/"
mkdir -p "$RESULTSDIR"
mkdir -p "$LOGDIR"

TESTDIR="$TESTDIRBASE/form-bench-$TIMESTAMP/"
mkdir -p "$TESTDIR"

TMPDIR=$TESTDIR/formtmp
mkdir "$TMPDIR"
export FORMTMP=$TMPDIR

if [[ -n $cmd_form_tmp ]]; then
	export FORMTMP=$cmd_form_tmp
fi
if [[ -n $cmd_form_tmp_sort ]]; then
	export FORMTMPSORT=$cmd_form_tmp_sort
fi

cp -r "$ORIGDIR"/tests/* "$TESTDIR"
cd "$TESTDIR"

# Save the version information for each binary.
(
	declare -A bins
	i=1
	IFS=','
	for form in $FORM_CMDS; do
		# shellcheck disable=SC2001
		form=$(echo "$form" | sed -e 's/ \+-w[0-9]\+//')
		if command -v "$form" &>/dev/null; then
			bin="$(command -v "$form")"
			if [[ -z ${bins[$bin]} ]]; then
				bins["$bin"]=1
				{
					echo "$bin"
					"$bin" -vv
				} >"$RESULTSDIR/version-$i.txt"
				((i++))
			fi
		fi
	done
)

for i in "${!tests_list[@]}"; do
	test="${tests_list[$i]}"
	run_count="${runs_list[$i]}"
	warmup_count="${warmup_list[$i]}"
	(
	cd "$test"
	echo ""
	echo ""
	echo Running "$test"
	hyperfine \
		--warmup "$warmup_count" \
		--runs "$run_count" \
		--export-json "$RESULTSDIR/results-$test.json" \
		--export-markdown "$RESULTSDIR/table-$test.md" \
		--parameter-list form "$FORM_CMDS" \
		--command-name "{form}" \
		"nice -n $NICE {form} $test.frm > $LOGDIR/$test.log"
	)
done

# Skip plot-compare in interleaved mode because it fails for results generated
# with --runs 1.
if [[ -z $cmd_interleave ]]; then
	python3 "$ORIGDIR/scripts/plot-compare.py" "$RESULTSDIR"
fi

# Clean up
cd "$ORIGDIR"
rm -rf "$TESTDIR"

