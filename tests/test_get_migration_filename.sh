#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# shellcheck source=tests/conftest.sh
source "${BATS_TEST_DIRNAME}/conftest.sh"

@test "pgp-get-migration-filename supports padded integer templates" {
    touch "${BATS_TEST_TMPDIR}/V001__existing.sql"

    run pgp-get-migration-filename \
        -t 'V{integer:3}__{description}.sql' \
        -d "${BATS_TEST_TMPDIR}" \
        -m 'Add Transactions'

    [[ "${status}" -eq 0 ]]
    [[ "${output}" == 'V002__add_transactions.sql' ]]
}

@test "pgp-get-migration-filename supports unpadded integer templates" {
    touch "${BATS_TEST_TMPDIR}/V1__existing.sql"

    run pgp-get-migration-filename \
        -t 'V{integer}__{description}.sql' \
        -d "${BATS_TEST_TMPDIR}" \
        -m 'Add Transactions'

    [[ "${status}" -eq 0 ]]
    [[ "${output}" == 'V2__add_transactions.sql' ]]
}

@test "pgp-get-migration-filename supports time placeholders" {
    run pgp-get-migration-filename \
        -t '{date}_{year}_{month}_{day}_{hour}_{direction}_{description}.sql' \
        -d "${BATS_TEST_TMPDIR}" \
        -m 'Add Transactions'

    [[ "${status}" -eq 0 ]]
    grep -Fq "_up_add_transactions.sql" <<< "${output}"
}

@test "pgp-get-migration-filename validates required arguments" {
    run pgp-get-migration-filename -t '{description}.sql'

    [[ "${status}" -eq 1 ]]
    grep -Fq "Helper to generate a migration filename." <<< "${output}"
}

@test "pgp-get-migration-filename shows help" {
    run pgp-get-migration-filename -h

    [[ "${status}" -eq 0 ]]
    grep -Fq "Helper to generate a migration filename." <<< "${output}"
}

@test "pgp-get-migration-filename rejects unknown options" {
    run pgp-get-migration-filename -z

    [[ "${status}" -eq 2 ]]
    grep -Fq "Helper to generate a migration filename." <<< "${output}"
}
