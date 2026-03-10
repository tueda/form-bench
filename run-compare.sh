#!/bin/bash
set -eE
trap 'echo Cleaning up ; rm -rf $TESTDIR $ORIGDIR/output/$TIMESTAMP' ERR


###############################################################################

# Compare multiple FORM binaries over the range of benchmarks. This is useful
# for testing performance optimizations of the code or checking for regressions.
# Parallel scaling can be checked by using the same binary with multiple worker
# counts.

# Configurable parameters:

LABEL="scaling-test-"
TESTDIRBASE="/dev/shm/"
# Negative nice can lead to more consistent timings.
NICE=-10

FORM_CMDS="\
form-test,\
tform-test -w1,\
tform-test -w2,\
tform-test -w4,\
tform-test -w6,\
tform-test -w8,\
tform-test -w10,\
tform-test -w12,\
tform-test -w16,\
tform-test -w20,\
tform-test -w24\
"

#TESTS="trace mincer minceex mass-fact forcer forcer-exp fmft mbox1l color chromatic sort-small sort-large sort-disk"
TESTS="trace mincer minceex forcer forcer-exp fmft mbox1l color chromatic sort-small sort-large sort-disk"

# Number of times to run test batches:
N=1

# Run a harder version of the tests? Not all tests are affected by this.
DIFFICULTY=1

###############################################################################


# For reference, a 7900X with tform -w24 takes about N*30m to run through all
# DIFFICULTY=1 tests with two binaries, and form takes about N*6hr.
# This is quite a long time, but we want tests that are representative of
# real-world use.
declare -A runs
runs["trace"]=$((     N * 30 ))
runs["mincer"]=$((    N * 2  ))
runs["minceex"]=$((   N * 3  ))
runs["mass-fact"]=$(( N * 2  ))
runs["forcer"]=$((    N * 2  ))
runs["forcer-exp"]=$((N * 2  ))
runs["fmft"]=$((      N * 3  ))
runs["mbox1l"]=$((    N * 8  ))
runs["color"]=$((     N * 8  ))
runs["chromatic"]=$(( N * 2  ))
runs["sort-large"]=$((N * 2  ))
runs["sort-small"]=$((N * 15 ))
runs["sort-disk"]=$(( N * 2 ))

# A warmup run helps to get stable times from very short-running tests.
declare -A warmup
warmup["trace"]=1
warmup["mincer"]=0
warmup["minceex"]=0
warmup["mass-fact"]=0
warmup["forcer"]=0
warmup["forcer-exp"]=0
warmup["fmft"]=0
warmup["mbox1l"]=0
warmup["color"]=0
warmup["chromatic"]=0
warmup["sort-large"]=0
warmup["sort-small"]=1
warmup["sort-disk"]=0

###############################################################################

# If command-line arguments are passed, parse them and override the settings.

error() {
	echo "error: $*" >&2
	exit 1
}

is_positive_int() {
	[[ $1 =~ ^[1-9][0-9]*$ ]]
}

require_arg() {
	[[ $# -ge 2 ]] || error "$1 requires an argument"
}

require_positive_int_arg() {
	require_arg "$@"
	is_positive_int "$2" || error "$1 must be a positive integer"
}

cmd_n=
cmd_min_n=
cmd_max_n=
cmd_interleave=
cmd_verbose=
cmd_tests=()
cmd_args=()

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
		-v|--verbose)
			cmd_verbose=1
			shift
			;;
		-t|--test)
			require_arg "$@"
			cmd_tests+=("$2")
			shift 2
			;;
		-*)
			error "unknown option: $1"
			;;
		*)
			cmd_args+=("$1")
			shift
			;;
	esac
done

if [[ -n $cmd_n ]]; then
	for i in "${!runs[@]}"; do
		runs[$i]=$cmd_n
	done
fi

if [[ -n $cmd_min_n ]]; then
	for i in "${!runs[@]}"; do
		if (( ${runs[$i]} < cmd_min_n )); then
			runs[$i]=$cmd_min_n
		fi
	done
fi

if [[ -n $cmd_max_n ]]; then
	for i in "${!runs[@]}"; do
		if (( ${runs[$i]} > cmd_max_n )); then
			runs[$i]=$cmd_max_n
		fi
	done
fi

if (( ${#cmd_tests[@]} > 0 )); then
	TESTS="${cmd_tests[*]}"
fi

if (( ${#cmd_args[@]} > 0 )); then
	FORM_CMDS=$(IFS=','; echo "${cmd_args[*]}")
fi

if [[ -n $cmd_interleave ]]; then
	[[ -n $cmd_n ]] || error "--interleave option requires -n"
	for i in "${!runs[@]}"; do
		runs[$i]=1
	done
	tmp_form_cmds=$FORM_CMDS
	for ((i=1; i<cmd_n; i++)); do
		FORM_CMDS+="${FORM_CMDS:+,}$tmp_form_cmds"
	done
fi

if [[ -n $cmd_verbose ]]; then
	for t in $TESTS; do
		echo "Test: $t: ${runs[$t]} runs (warmup: ${warmup[$t]})"
	done

	(
		IFS=,
		for c in $FORM_CMDS; do
			echo "Command: $c"
		done
	)
fi

# Check for python and hyperfine:
for bin in hyperfine python3; do
	if ! command -v "$bin" &> /dev/null; then
		echo "Error, script requires $bin"
		exit 1
	fi
done

# Check for the specified FORM binaries:
for form in $(echo "$FORM_CMDS" | sed -e 's/ -w[0-9]\+//g' -e's/,/ /g'); do
	if ! command -v "$form" &> /dev/null; then
		echo "Error, script requires $form"
		exit 1
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

TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)
RESULTSDIR="$ORIGDIR/output/$RUN_ID-$LABEL$TIMESTAMP/results/"
echo "Results: $RESULTSDIR"
LOGDIR="$ORIGDIR/output/$RUN_ID-$LABEL$TIMESTAMP/logs/"
mkdir -p "$RESULTSDIR"
mkdir -p "$LOGDIR"

TESTDIR="$TESTDIRBASE/form-bench-$TIMESTAMP/"
mkdir "$TESTDIR"

TMPDIR=$TESTDIR/formtmp
mkdir "$TMPDIR"
export FORMTMP=$TMPDIR

cp -r "$ORIGDIR"/tests/* "$TESTDIR"
cd "$TESTDIR"


for test in $TESTS; do
	(
	cd "$test"
	echo ""
	echo ""
	echo Running "$test"
	hyperfine --warmup "${warmup[$test]}" --runs "${runs[$test]}" \
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

