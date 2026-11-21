#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# shellcheck source=tests/conftest.sh
source "${BATS_TEST_DIRNAME}/conftest.sh"

@test "pgp-setup-infrastructure shows help" {
    run pgp-setup-infrastructure -h

    [[ ${status} -eq 0 ]]
    grep -Fq "Set up infrastructure." <<<"${output}"
}

@test "pgp-setup-infrastructure rejects unknown options" {
    run pgp-setup-infrastructure -z

    [[ ${status} -eq 2 ]]
    grep -Fq "Set up infrastructure." <<<"${output}"
}
