#!/bin/bash
set -eE
trap 'echo Cleaning up ; rm -rf $TESTDIR $ORIGDIR/output/$TIMESTAMP' ERR


###############################################################################

# Compare multiple FORM binaries over the range of benchmarks. This is useful
# for testing performance optimizations of the code or checking for regressions.
# Parallel scaling can be checked by using the same binary with multiple worker
# counts.


# Configurable parameters: set their default values and then re-set with user args

# The output directory will be called $LABEL-$TIMESTAMP
LABEL="run-label"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)

# The tests will be run from here. Using a tmpfs (eg, /dev/shm or perhaps /tmp)
# removes disk-access performance effects from the timings.
TESTDIRBASE="$TMP"

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


# Now check for non-default options from the user:

options=$(getopt -o "" -l "label:,testdir:,timestamp:,nice:,form_cmds:,tests:,runs:,difficulty:" -- "$@")
if [ $? -ne 0 ]; then
	echo "Error, invalid argument in $@"
fi
eval set -- $options
while :
do
	case "$1" in
		--label)      LABEL="$2"; shift 2 ;;
		--testdir)    TESTDIRBASE="$2"; shift 2 ;;
		--timestamp)  TIMESTAMP="$2"; shift 2 ;;
		--nice)       NICE="$2"; shift 2 ;;
		--form_cmds)  FORM_CMDS="$2"; shift 2 ;;
		--tests)      TESTS=$(echo "$2" | sed 's/,/ /g'); shift 2 ;;
		--runs)       N="$2"; shift 2 ;;
		--difficulty) DIFFICULTY="$2"; shift 2 ;;
		--) shift; break ;;
		*) echo "Error, invalid option: $1" ;;
	esac
done
# This variable needs to be available within form scripts:
export DIFFICULTY

echo "form-bench: $(git rev-parse HEAD)"
echo "	LABEL      = $LABEL"
echo "	TESTDIR    = $TESTDIRBASE"
echo "	TIMESTAMP  = $TIMESTAMP"
echo "	NICE       = $NICE"
echo "	FORM_CMDS  = $FORM_CMDS"
echo "	TESTS      = $TESTS"
echo "	N          = $N"
echo "	DIFFICULTY = $DIFFICULTY"


###############################################################################

# Load test run and warmup counts:
declare -A runs
declare -A warmup
for test in $TESTS; do
	if [ ! -d tests/$test ]; then
		echo "Error, invalid test: $test"
		exit 1
	fi
	source tests/$test/conf.sh
done

# Check for python and hyperfine:
for bin in hyperfine python; do
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
RESULTSDIR=$ORIGDIR/output/$LABEL-$TIMESTAMP/results/
echo "Results: $RESULTSDIR"
LOGDIR=$ORIGDIR/output/$LABEL-$TIMESTAMP/logs/
mkdir -p "$RESULTSDIR"
mkdir -p "$LOGDIR"

TESTDIR="$TESTDIRBASE/form-bench-$TIMESTAMP/"
mkdir -p "$TESTDIR"

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
python "$ORIGDIR/scripts/plot-compare.py" "$RESULTSDIR"

# Clean up
cd "$ORIGDIR"
rm -rf "$TESTDIR"

