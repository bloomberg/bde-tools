#!/bin/bash

if [[ $1 == "-h" || $1 == "--help" ]]; then
    echo "Usage: [-c]"
    echo "-c: Run tests with coverage.py"
    exit 1
fi

if [[ $1 == "-c" ]]; then
    # We care only about the coverage of the meta sub-package for now.
    test_runner="coverage run --source=bdebld/meta,bdebld/setenv,bdebld/common -a"
    coverage erase
else
    test_runner="python"
fi

# Run all test drivers.  This script must be run in the directory in which it
# resides.

tests=(
    tests.bdebld.meta.test_buildconfigfactory
    tests.bdebld.meta.test_graphutil
    tests.bdebld.meta.test_optionsevaluator
    tests.bdebld.meta.test_optionsparser
    tests.bdebld.meta.test_optionsutil
    tests.bdebld.meta.test_repocontextloader
    tests.bdebld.meta.test_repolayoututil
    tests.bdebld.meta.test_repoloadutil
    tests.bdebld.setenv.test_compilerinfo
    tests.bdebld.common.test_sysutils
)

for t in "${tests[@]}"; do
    echo "==== Running $t ===="
    $test_runner -m "$t"
done
