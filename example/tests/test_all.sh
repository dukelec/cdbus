#!/bin/bash

shopt -s nullglob

if [ "$1" != "" ]; then
    LIST="$1"
else
    LIST="test_*.py"
fi

for test_file in $LIST; do
    test_case=$(echo "$test_file" | cut -f 1 -d '.')
    test_wrapper="cdctl_spi_wrapper"
    [[ "$test_case" =~ "qspi" ]] && test_wrapper="cdctl_qspi_wrapper"
    echo -e "\nTest ${test_case}, wrapper: ${test_wrapper}\n"
    rm -f .exit_ok
    rm -rf ./sim_build
    TEST_CASE="$test_case" TEST_WRAPPER="$test_wrapper" make
    [ ! -f .exit_ok ] && { echo -e "\nError!"; exit 1; }
done

echo -e "\nPass all."
rm -f .exit_ok

