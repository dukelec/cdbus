#!/bin/bash

shopt -s nullglob

if [ "$1" != "" ]; then
    LIST="$1"
else
    LIST="test_*.py"
fi

for test_file in $LIST; do
    test_case=$(echo "$test_file" | cut -f 1 -d '.')
    test_wrapper="cdbus_wrapper_dft"
    [[ "$test_case" =~ "full_duplex" ]] && test_wrapper="cdbus_wrapper_fduplex"
    echo -e "\nTest ${test_case}, wrapper: ${test_wrapper}\n"
    rm -f .exit_ok
    rm -rf ./sim_build
    TEST_CASE="$test_case" TEST_WRAPPER="$test_wrapper" make
    [ ! -f .exit_ok ] && { echo -e "\nError!"; exit 1; }
done

echo -e "\nPass all."
rm -f .exit_ok

