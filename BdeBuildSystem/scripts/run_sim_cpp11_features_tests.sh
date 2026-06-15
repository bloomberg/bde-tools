#!/bin/bash
# Test script to compare Perl and Python versions of sim_cpp11_features
# Tests both test case files and CLI option combinations

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PYTHON3=""
for py in python3 python; do
    if $py -V 2>&1 | grep -qE '^Python 3\.(9|[1-9][0-9])\.'; then
        PYTHON3=$py
        break
    fi
done
if [ -z "$PYTHON3" ]; then
    printf "No appropriate python interpreter found (3.9+ required).\n"
    exit 1
fi

TEST_DIR="$SCRIPT_DIR/test_cases_sim_cpp11_features"
WORK_DIR="$SCRIPT_DIR/run_sim_cpp11_features_tests_output"

# Script paths
PERL_SCRIPT="$SCRIPT_DIR/sim_cpp11_features.pl"
PYTHON_SCRIPT="$SCRIPT_DIR/sim_cpp11_features.py"

# Work subdirectories
PERL_DIR="$WORK_DIR/perl"
PYTHON_DIR="$WORK_DIR/python"
CLI_DIR="$WORK_DIR/cli"

rm -rf "$WORK_DIR"
mkdir -p "$PERL_DIR" "$PYTHON_DIR" "$CLI_DIR"

PASSED=0
FAILED=0

# Normalize output: replace timestamps and script names
normalize() {
    sed -E \
        -e 's/Generated on .*/Generated on TIMESTAMP/' \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\+[0-9]{2}:[0-9]{2}|Z)?/TIMESTAMP/g' \
        -e 's/sim_cpp11_features\.pl/sim_cpp11_features.SCRIPT/g' \
        -e 's/sim_cpp11_features\.py/sim_cpp11_features.SCRIPT/g'
}

# Normalize debug output (same as normalize for now - all trace calls match)
normalize_debug() {
    normalize
}

# Compare two files after normalization
compare_files() {
    local test_name="$1"
    local perl_out="$2"
    local python_out="$3"

    if [ ! -f "$perl_out" ]; then
        echo "  SKIPPED: $test_name (perl output not found)"
        return 1
    fi
    if [ ! -f "$python_out" ]; then
        echo "  SKIPPED: $test_name (python output not found)"
        return 1
    fi

    normalize < "$perl_out" > "$perl_out.norm"
    normalize < "$python_out" > "$python_out.norm"

    if diff -q "$perl_out.norm" "$python_out.norm" > /dev/null 2>&1; then
        return 0
    else
        echo "    Diff ($test_name):"
        diff "$perl_out.norm" "$python_out.norm" | head -20
        return 1
    fi
}

# Compare debug output files
compare_debug_files() {
    local test_name="$1"
    local perl_out="$2"
    local python_out="$3"

    if [ ! -f "$perl_out" ]; then
        echo "  SKIPPED: $test_name (perl output not found)"
        return 1
    fi
    if [ ! -f "$python_out" ]; then
        echo "  SKIPPED: $test_name (python output not found)"
        return 1
    fi

    normalize_debug < "$perl_out" > "$perl_out.norm"
    normalize_debug < "$python_out" > "$python_out.norm"

    if diff -q "$perl_out.norm" "$python_out.norm" > /dev/null 2>&1; then
        return 0
    else
        echo "    Diff ($test_name):"
        diff "$perl_out.norm" "$python_out.norm" | head -20
        return 1
    fi
}

echo "========================================"
echo "sim_cpp11_features Perl / Python comparison tests"
echo "========================================"
echo ""
echo "Part 1: Test case files"
echo "----------------------------------------"

for test_file in "$TEST_DIR"/*.h; do
    [ -f "$test_file" ] || continue

    base=$(basename "$test_file" .h)
    echo -n "Testing $base... "

    # Copy files to work directories
    cp "$test_file" "$PERL_DIR/${base}.h"
    cp "$test_file" "$PYTHON_DIR/${base}.h"

    # Run Perl (from work directory so generated files stay there)
    (cd "$PERL_DIR" && perl "$PERL_SCRIPT" "${base}.h" 2>"${base}.err")
    perl_rc=$?

    # Run Python (from work directory so generated files stay there)
    (cd "$PYTHON_DIR" && $PYTHON3 "$PYTHON_SCRIPT" "${base}.h" 2>"${base}.err")
    python_rc=$?

    # Check exit codes
    if [ $perl_rc -ne $python_rc ]; then
        echo "FAILED (exit: perl=$perl_rc python=$python_rc)"
        cat "$PYTHON_DIR/${base}.err"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Compare main .h file
    if ! compare_files "main .h" "$PERL_DIR/${base}.h" "$PYTHON_DIR/${base}.h"; then
        echo "FAILED (main .h differs)"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Compare _cpp03.h file if it exists
    cpp03_perl="$PERL_DIR/${base}_cpp03.h"
    cpp03_python="$PYTHON_DIR/${base}_cpp03.h"

    if [ -f "$cpp03_perl" ] && [ -f "$cpp03_python" ]; then
        if ! compare_files "_cpp03.h" "$cpp03_perl" "$cpp03_python"; then
            echo "FAILED (_cpp03.h differs)"
            FAILED=$((FAILED + 1))
            continue
        fi
    elif [ -f "$cpp03_perl" ] || [ -f "$cpp03_python" ]; then
        echo "FAILED (_cpp03.h exists in one but not other)"
        FAILED=$((FAILED + 1))
        continue
    fi

    echo "PASSED"
    PASSED=$((PASSED + 1))
done

echo ""
echo "Part 2: CLI option combinations"
echo "----------------------------------------"

# Use the comprehensive test file for CLI tests - covers many cases
CLI_TEST_FILE="$CLI_DIR/test_comprehensive.h"
cp "$TEST_DIR/test_comprehensive.h" "$CLI_TEST_FILE"

run_cli_test() {
    local test_name="$1"
    local perl_out="$2"
    local python_out="$3"

    echo -n "Testing $test_name... "

    if compare_files "$test_name" "$perl_out" "$python_out"; then
        echo "PASSED"
        PASSED=$((PASSED + 1))
    else
        echo "FAILED"
        FAILED=$((FAILED + 1))
    fi
}

run_debug_test() {
    local test_name="$1"
    local perl_out="$2"
    local python_out="$3"

    echo -n "Testing $test_name... "

    if compare_debug_files "$test_name" "$perl_out" "$python_out"; then
        echo "PASSED"
        PASSED=$((PASSED + 1))
    else
        echo "FAILED"
        FAILED=$((FAILED + 1))
    fi
}

# Test: stdin to stdout (error case)
cat "$CLI_TEST_FILE" | perl "$PERL_SCRIPT" - > "$CLI_DIR/perl_stdin.out" 2>&1 || true
cat "$CLI_TEST_FILE" | $PYTHON3 "$PYTHON_SCRIPT" - > "$CLI_DIR/python_stdin.out" 2>&1 || true
run_cli_test "stdin error" "$CLI_DIR/perl_stdin.out" "$CLI_DIR/python_stdin.out"

# Test: file to stdout (default)
perl "$PERL_SCRIPT" "$CLI_TEST_FILE" > "$CLI_DIR/perl_file.out" 2>&1 || true
$PYTHON3 "$PYTHON_SCRIPT" "$CLI_TEST_FILE" > "$CLI_DIR/python_file.out" 2>&1 || true
run_cli_test "file to stdout" "$CLI_DIR/perl_file.out" "$CLI_DIR/python_file.out"

# Test: --var-args with different values
for var_args in 1 2 3 5 10; do
    perl "$PERL_SCRIPT" --var-args=$var_args "$CLI_TEST_FILE" > "$CLI_DIR/perl_varargs_$var_args.out" 2>&1 || true
    $PYTHON3 "$PYTHON_SCRIPT" --var-args=$var_args "$CLI_TEST_FILE" > "$CLI_DIR/python_varargs_$var_args.out" 2>&1 || true
    run_cli_test "--var-args=$var_args" "$CLI_DIR/perl_varargs_$var_args.out" "$CLI_DIR/python_varargs_$var_args.out"
done

# Test: --inplace option (use work dir copy)
cp "$CLI_TEST_FILE" "$CLI_DIR/inplace_test.h"
perl "$PERL_SCRIPT" --inplace "$CLI_DIR/inplace_test.h" 2>&1 || true
cp "$CLI_DIR/inplace_test.h" "$CLI_DIR/perl_inplace.out"
cp "$CLI_TEST_FILE" "$CLI_DIR/inplace_test.h"
$PYTHON3 "$PYTHON_SCRIPT" --inplace "$CLI_DIR/inplace_test.h" 2>&1 || true
cp "$CLI_DIR/inplace_test.h" "$CLI_DIR/python_inplace.out"
run_cli_test "--inplace" "$CLI_DIR/perl_inplace.out" "$CLI_DIR/python_inplace.out"

# Test: --no-inplace option
perl "$PERL_SCRIPT" --no-inplace "$CLI_TEST_FILE" > "$CLI_DIR/perl_noinplace.out" 2>&1 || true
$PYTHON3 "$PYTHON_SCRIPT" --no-inplace "$CLI_TEST_FILE" > "$CLI_DIR/python_noinplace.out" 2>&1 || true
run_cli_test "--no-inplace" "$CLI_DIR/perl_noinplace.out" "$CLI_DIR/python_noinplace.out"

# Test: --clean option
cp "$CLI_TEST_FILE" "$CLI_DIR/clean_test.h"
perl "$PERL_SCRIPT" --inplace "$CLI_DIR/clean_test.h" 2>&1 || true
cp "$CLI_DIR/clean_test.h" "$CLI_DIR/generated.h"
# Clean with Perl
cp "$CLI_DIR/generated.h" "$CLI_DIR/clean_test.h"
perl "$PERL_SCRIPT" --clean --inplace "$CLI_DIR/clean_test.h" 2>&1 || true
cp "$CLI_DIR/clean_test.h" "$CLI_DIR/perl_clean.out"
# Clean with Python
cp "$CLI_DIR/generated.h" "$CLI_DIR/clean_test.h"
$PYTHON3 "$PYTHON_SCRIPT" --clean --inplace "$CLI_DIR/clean_test.h" 2>&1 || true
cp "$CLI_DIR/clean_test.h" "$CLI_DIR/python_clean.out"
run_cli_test "--clean" "$CLI_DIR/perl_clean.out" "$CLI_DIR/python_clean.out"

# Test: --verify-no-change on already-processed file
cp "$CLI_DIR/generated.h" "$CLI_DIR/verify_test.h"
perl "$PERL_SCRIPT" --verify-no-change "$CLI_DIR/verify_test.h" > "$CLI_DIR/perl_verify.out" 2>&1 || true
$PYTHON3 "$PYTHON_SCRIPT" --verify-no-change "$CLI_DIR/verify_test.h" > "$CLI_DIR/python_verify.out" 2>&1 || true
run_cli_test "--verify-no-change" "$CLI_DIR/perl_verify.out" "$CLI_DIR/python_verify.out"

# Test: --test option (built-in test data - note: both fail due to missing copyright in test data)
perl "$PERL_SCRIPT" --test > "$CLI_DIR/perl_test.out" 2>&1 || true
$PYTHON3 "$PYTHON_SCRIPT" --test > "$CLI_DIR/python_test.out" 2>&1 || true
run_cli_test "--test" "$CLI_DIR/perl_test.out" "$CLI_DIR/python_test.out"

echo ""
echo "Part 3: Debug output levels"
echo "----------------------------------------"

# Test --debug=0 (no debug output)
cp "$TEST_DIR/test_comprehensive.h" "$CLI_TEST_FILE"
(cd "$CLI_DIR" && perl "$PERL_SCRIPT" --debug=0 "test_comprehensive.h") > "$CLI_DIR/perl_d0.out" 2>&1 || true
cp "$TEST_DIR/test_comprehensive.h" "$CLI_TEST_FILE"
(cd "$CLI_DIR" && $PYTHON3 "$PYTHON_SCRIPT" --debug=0 "test_comprehensive.h") > "$CLI_DIR/python_d0.out" 2>&1 || true
run_cli_test "--debug=0" "$CLI_DIR/perl_d0.out" "$CLI_DIR/python_d0.out"

# Test --debug=1 (level 1 tracing)
cp "$TEST_DIR/test_comprehensive.h" "$CLI_TEST_FILE"
(cd "$CLI_DIR" && perl "$PERL_SCRIPT" --debug=1 "test_comprehensive.h") > "$CLI_DIR/perl_d1.out" 2>&1 || true
cp "$TEST_DIR/test_comprehensive.h" "$CLI_TEST_FILE"
(cd "$CLI_DIR" && $PYTHON3 "$PYTHON_SCRIPT" --debug=1 "test_comprehensive.h") > "$CLI_DIR/python_d1.out" 2>&1 || true
run_debug_test "--debug=1" "$CLI_DIR/perl_d1.out" "$CLI_DIR/python_d1.out"

# Test --debug=2 (level 2 tracing)
cp "$TEST_DIR/test_comprehensive.h" "$CLI_TEST_FILE"
(cd "$CLI_DIR" && perl "$PERL_SCRIPT" --debug=2 "test_comprehensive.h") > "$CLI_DIR/perl_d2.out" 2>&1 || true
cp "$TEST_DIR/test_comprehensive.h" "$CLI_TEST_FILE"
(cd "$CLI_DIR" && $PYTHON3 "$PYTHON_SCRIPT" --debug=2 "test_comprehensive.h") > "$CLI_DIR/python_d2.out" 2>&1 || true
run_debug_test "--debug=2" "$CLI_DIR/perl_d2.out" "$CLI_DIR/python_d2.out"

echo ""
echo "========================================"
echo "Results: $PASSED passed, $FAILED failed"
echo "========================================"

[ $FAILED -eq 0 ] && rm -rf "$WORK_DIR"
exit $FAILED
