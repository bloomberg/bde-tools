#!/bin/bash

if [[ $1 == "-h" || $1 == "--help" ]]; then
    echo "Usage: [-c]"
    echo "-c: Run tests with coverage.py"
    exit 1
fi

if [[ $1 == "-c" ]]; then
    # We care only about the coverage of the meta sub-package for now.
    test_runner="coverage run --source=bdebld/meta -a"
    coverage erase
else
    test_runner="python"
fi

# Run all test drivers.  This script must be run in the directory in which it
# resides.

tests=(
    tests.meta.test_buildconfigfactory
    tests.meta.test_graphutil
    tests.meta.test_optionsevaluator
    tests.meta.test_optionsparser
    tests.meta.test_optionsutil
    tests.meta.test_repocontextloader
    tests.meta.test_repolayoututil
    tests.meta.test_repoloadutil
    tests.meta.test_sysutils
)

for t in "${tests[@]}"; do
    echo "==== Running $t ===="
    $test_runner -m "$t"
done
