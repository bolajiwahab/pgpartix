#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# shellcheck source=tests/conftest.sh
source "${BATS_TEST_DIRNAME}/conftest.sh"

shopt -s globstar nullglob

function cleanup() {
    local teardown_file="${1}"
    local test_db="${2:-}"
    local result="${3}"

    echo "INFO: Cleaning up after error" >&2

    if [[ -f "${teardown_file}" ]]; then
        psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${teardown_file}"
    fi

    if [[ -n "${test_db}" ]]; then
        dropdb --if-exists "${test_db}"
    fi

    rm -f "${result}"
}

function run_config_file() {
    local config_file="$1"
    local config_file_name
    local config_file_directory
    local expected
    local result
    local setup_file
    local teardown_file
    local test_db="pgpartix_test_$$"

    config_file_directory="$(dirname "${config_file}")"
    config_file_name="${config_file%.yaml}"
    config_file_name="${config_file_name%.yml}"

    expected="${config_file_name}.expected.sql"
    result="${config_file_directory}/pgpartix_output.sql"

    setup_file="${config_file_directory}/setup.sql"
    teardown_file="${config_file_directory}/teardown.sql"

    trap 'cleanup ${teardown_file} ${test_db} ${result}' ERR INT TERM

    if [[ -f "${setup_file}" && ! -f "${teardown_file}" ]]; then
        echo "Missing ${teardown_file} for ${setup_file}" >&2
        exit 1
    fi

    if [[ -f "${setup_file}" ]]; then
        psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${setup_file}"
        pg_ctl reload
    fi

    pgp-run-lifecycle -c "${config_file}"

    diff -u "${expected}" "${result}"

    # Validate generated SQL by executing it against a test database.
    createdb --template="${PGP_DATABASE}" "${test_db}"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --dbname "${test_db}" --file "${result}"

    dropdb "${test_db}"

    if [[ -f "${teardown_file}" ]]; then
        psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${teardown_file}"
    fi

    rm -f "${result}"
}

function run_config_directory() {
    local fixture="${1}"
    local expected
    local result
    local test_db="pgpartix_expire_test_$$"

    expected="${fixture}/pgpartix_output.expected.sql"
    result="${fixture}/pgpartix_output.sql"

    trap 'cleanup "${fixture}" "${test_db} ${result}"' ERR INT TERM

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"

    pg_ctl reload

    pgp-run-lifecycle -c "${fixture}/configs"

    diff -u "${expected}" "${result}"

    createdb --template="${PGP_DATABASE}" "${test_db}"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --dbname "${test_db}" --file "${result}"

    dropdb "${test_db}"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"

    rm -f "${result}"
}

@test "pgp-run-lifecycle shows help" {
    run pgp-run-lifecycle -h

    [ "${status}" -eq 0 ]
    grep -Fq "Run the full partition lifecycle" <<< "${output}"
}

@test "pgp-run-lifecycle rejects unknown options" {
    run pgp-run-lifecycle -z

    [ "${status}" -eq 2 ]
    grep -Fq "Run the full partition lifecycle" <<< "${output}"
}

@test "pgp-run-lifecycle uses local connection defaults and silences successful formatting" {
    local fixture="tests/fixtures/make_partitions/defaults"
    local result="${fixture}/pgpartix_output.sql"

    rm -f "${result}"
    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    pg_ctl reload

    run env \
        -u PGP_USER \
        -u PGP_PASSWORD \
        -u PGP_DATABASE \
        -u PGP_HOST \
        -u PGP_PORT \
        pgp-run-lifecycle -c "${fixture}/config.yaml"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"

    [ "${status}" -eq 0 ]
    run ! grep -Fq "file(s) reformatted" <<< "${output}"
    diff -u "${fixture}/config.expected.sql" "${result}"
    rm -f "${result}"
}

@test "pgp-run-lifecycle rejects a missing config path" {
    run pgp-run-lifecycle -c "${BATS_TEST_TMPDIR}/missing.yaml"

    [ "${status}" -eq 1 ]
    grep -Fq "does not exist" <<< "${output}"
}

@test "pgp-run-lifecycle rejects invalid config" {
    run pgp-run-lifecycle -c tests/fixtures/run_lifecycle/invalid.yaml

    [ "${status}" -eq 1 ]
    grep -Fq "is invalid" <<< "${output}"
}

@test "pgp-run-lifecycle rejects a negative past partition count" {
    run pgp-run-lifecycle -c tests/fixtures/run_lifecycle/negative_past.yaml

    [ "${status}" -eq 1 ]
    grep -Fq "is invalid" <<< "${output}"
    grep -Fq "past" <<< "${output}"
}

@test "pgp-run-lifecycle rejects a negative future partition count" {
    run pgp-run-lifecycle -c tests/fixtures/run_lifecycle/negative_future.yaml

    [ "${status}" -eq 1 ]
    grep -Fq "is invalid" <<< "${output}"
    grep -Fq "future" <<< "${output}"
}

@test "pgp-run-lifecycle requires a partition naming template when an interval is specified" {
    local fixture="tests/fixtures/run_lifecycle"
    local result="${fixture}/pgpartix_output.sql"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    run pgp-run-lifecycle -c "${fixture}/missing_name_template.yaml"
    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"

    [ "${status}" -eq 1 ]
    grep -Fq "making partitions failed for 1 table(s)" <<< "${output}"
    grep -Fq "partition name template is required when partition interval is specified" <<< "${output}"
    [ ! -e "${result}" ]
}

@test "pgp-run-lifecycle skips generation when no partition interval is configured" {
    local fixture="tests/fixtures/run_lifecycle"
    local result="${fixture}/pgpartix_output.sql"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    run pgp-run-lifecycle -c "${fixture}/missing_interval.yaml"
    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"

    [ "${status}" -eq 0 ]
    grep -Fq "No partitions made for test.transactions" <<< "${output}"
    [ ! -e "${result}" ]
}

@test "pgp-run-lifecycle rejects a missing template table" {
    local fixture="tests/fixtures/run_lifecycle"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    run pgp-run-lifecycle -c "${fixture}/missing_template_table.yaml"
    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"

    [ "${status}" -eq 1 ]
    grep -Fq "Template table test.missing_template does not exist" <<< "${output}"
}

@test "pgp-run-lifecycle reports make generation failures" {
    local fixture="tests/fixtures/run_lifecycle"
    local result="${fixture}/pgpartix_output.sql"

    run pgp-run-lifecycle -c "${fixture}/missing_parent_table.yaml"

    [ "${status}" -eq 1 ]
    # The missing table is invalid input to both phases, so both report it.
    grep -Fq "making partitions failed for 1 table(s)" <<< "${output}"
    grep -Fq "expiring partitions failed for 1 table(s)" <<< "${output}"
    grep -Fq 'table "test"."missing_parent" does not exist' <<< "${output}"
    run ! grep -Fq "Traceback" <<< "${output}"
    [ ! -e "${result}" ]
}

@test "pgp-run-lifecycle reports SQL validation failures through the CLI" {
    local fixture="tests/fixtures/make_partitions/sql_failures"
    local expected="${fixture}/pgpartix_output.expected.sql"
    local result="${fixture}/pgpartix_output.sql"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    pg_ctl reload

    run pgp-run-lifecycle -c "${fixture}/config.yaml"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"

    [ "${status}" -eq 1 ]
    grep -Fq "making partitions failed for 8 table(s)" <<< "${output}"
    grep -Fq 'is not partitioned' <<< "${output}"
    grep -Fq '"LIST" partitioning is not supported' <<< "${output}"
    grep -Fq 'multi column partitioned tables are not supported' <<< "${output}"
    grep -Fq 'partitioning on data type "text" is not supported' <<< "${output}"
    grep -Fq 'partition schema "missing_schema" does not exist' <<< "${output}"
    grep -Fq 'partition tablespace "missing_tablespace" does not exist' <<< "${output}"
    grep -Fq 'index tablespace "missing_tablespace" does not exist' <<< "${output}"
    grep -Fq 'interval cannot be zero' <<< "${output}"
    run ! grep -Fq "Traceback" <<< "${output}"
    diff -u "${expected}" "${result}"
    rm -f "${result}"
}

@test "pgp-run-lifecycle writes unformatted SQL when the make formatter fails" {
    local fixture="tests/fixtures/make_partitions/defaults"
    local fake_bin="${BATS_TEST_TMPDIR}/bin"
    local result="${fixture}/pgpartix_output.sql"

    rm -f "${result}"
    mkdir -p "${fake_bin}"
    printf '%s\n' '#!/bin/bash' 'echo "formatter internals" >&2' 'exit 1' > "${fake_bin}/pgrubic"
    chmod +x "${fake_bin}/pgrubic"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    pg_ctl reload

    run env PATH="${fake_bin}:${PATH}" pgp-run-lifecycle -c "${fixture}/config.yaml"

    [ "${status}" -eq 0 ]
    grep -Fq "WARNING: failed to format generated SQL" <<< "${output}"
    grep -Fq "formatter internals" <<< "${output}"
    run ! grep -Fq "failed for" <<< "${output}"
    run ! grep -Fq "Traceback" <<< "${output}"
    [ -s "${result}" ]

    # The unformatted SQL must still be valid and applicable.
    createdb --template="${PGP_DATABASE}" pgpartix_test_$$
    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --dbname pgpartix_test_$$ --file "${result}"
    dropdb pgpartix_test_$$

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"

    rm -f "${result}"
}

@test "pgp-run-lifecycle writes unformatted SQL when the expire formatter fails" {
    local fixture="tests/fixtures/expire_partitions/defaults"
    local fake_bin="${BATS_TEST_TMPDIR}/bin"
    local result="${fixture}/pgpartix_output.sql"

    rm -f "${result}"
    mkdir -p "${fake_bin}"
    printf '%s\n' '#!/bin/bash' 'echo "formatter internals" >&2' 'exit 1' > "${fake_bin}/pgrubic"
    chmod +x "${fake_bin}/pgrubic"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    pg_ctl reload

    run env PATH="${fake_bin}:${PATH}" pgp-run-lifecycle -c "${fixture}/config.yaml"

    [ "${status}" -eq 0 ]
    grep -Fq "WARNING: failed to format generated SQL" <<< "${output}"
    grep -Fq "formatter internals" <<< "${output}"
    run ! grep -Fq "failed for" <<< "${output}"
    run ! grep -Fq "Traceback" <<< "${output}"
    [ -s "${result}" ]

    # The unformatted SQL must still be valid and applicable.
    createdb --template="${PGP_DATABASE}" pgpartix_test_$$
    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --dbname pgpartix_test_$$ --file "${result}"
    dropdb pgpartix_test_$$

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"

    rm -f "${result}"
}

@test "pgp-run-lifecycle processes a config directory" {
    local fixture="tests/fixtures/expire_partitions/config_directory"

    run run_config_directory "${fixture}"

    [ "${status}" -eq 0 ]
    grep -Fq "Applied configs from ${fixture}/configs" <<< "${output}"
}

@test "pgp-run-lifecycle applies global expire config and table overrides" {
    local fixture="tests/fixtures/expire_partitions/global_config"
    local inherited_result="${fixture}/expire_global_test_inherited_events.sql"
    local overridden_result="${fixture}/detach_override_test_overridden_events.sql"
    local test_db="pgpartix_expire_global_test_$$"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    pg_ctl reload

    pgp-run-lifecycle -c "${fixture}/config.yaml"

    diff -u "${fixture}/expire_global_test_inherited_events.expected.sql" "${inherited_result}"
    diff -u "${fixture}/detach_override_test_overridden_events.expected.sql" "${overridden_result}"

    createdb --template="${PGP_DATABASE}" "${test_db}"
    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --dbname "${test_db}" --file "${inherited_result}"
    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --dbname "${test_db}" --file "${overridden_result}"
    dropdb "${test_db}"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"
    rm -f "${inherited_result}" "${overridden_result}"
}

@test "pgp-run-lifecycle handles an empty make result" {
    local fixture="tests/fixtures/make_partitions/defaults"
    local result="${fixture}/pgpartix_output.sql"
    local run_status

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    pg_ctl reload

    pgp-run-lifecycle -c "${fixture}/config.yaml"
    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${result}"
    rm -f "${result}"

    run pgp-run-lifecycle -c "${fixture}/config.yaml"
    run_status="${status}"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"

    [ "${run_status}" -eq 0 ]
    [ ! -e "${result}" ]
}

@test "pgp-run-lifecycle handles an empty expire result" {
    local fixture="tests/fixtures/expire_partitions/empty_result"
    local result="${fixture}/pgpartix_output.sql"
    local run_status

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    pg_ctl reload

    run pgp-run-lifecycle -c "${fixture}/config.yaml"
    run_status="${status}"

    cleanup "${fixture}/teardown.sql" "" "${result}"

    [ "${run_status}" -eq 0 ]
    [ ! -e "${result}" ]
}

@test "pgp-run-lifecycle reports make database failures" {
    local fixture="tests/fixtures/expire_partitions/database_failure"
    local expected="${fixture}/pgpartix_output.expected.sql"
    local result="${fixture}/pgpartix_output.sql"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"

    run pgp-run-lifecycle -c "${fixture}/config.yaml"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"

    [ "${status}" -eq 1 ]
    # Neither table exists as a valid partitioned parent, which the make phase
    # checks before ever looking at partition.interval, so both fail there too.
    grep -Fq "making partitions failed for 2 table(s)" <<< "${output}"
    grep -Fq 'table "test"."missing_notifications" does not exist' <<< "${output}"
    grep -Fq 'table "test"."notifications" is not partitioned' <<< "${output}"
    run ! grep -Fq "Traceback" <<< "${output}"
    diff -u "${expected}" "${result}"
    rm -f "${result}"
}

@test "pgp-run-lifecycle reports expire database failures" {
    local fixture="tests/fixtures/expire_partitions/database_failure"
    local expected="${fixture}/pgpartix_output.expected.sql"
    local result="${fixture}/pgpartix_output.sql"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"

    run pgp-run-lifecycle -c "${fixture}/config.yaml"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"

    [ "${status}" -eq 1 ]
    grep -Fq "expiring partitions failed for 2 table(s)" <<< "${output}"
    grep -Fq 'table "test"."missing_notifications" does not exist' <<< "${output}"
    grep -Fq 'table "test"."notifications" is not partitioned' <<< "${output}"
    run ! grep -Fq "Traceback" <<< "${output}"
    diff -u "${expected}" "${result}"
    rm -f "${result}"
}

@test "pgp-run-lifecycle honours NOW when no latest partition exists" {
    local fixture="tests/fixtures/make_partitions/start_timestamp"
    local result="${fixture}/pgpartix_output.sql"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    pg_ctl reload

    run pgp-run-lifecycle -c "${fixture}/now.yaml"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"
    rm -f "${result}"

    [ "${status}" -eq 0 ]
    grep -Fq "INFO: Using current timestamp for partition start timestamp" <<< "${output}"
}

@test "pgp-run-lifecycle prefers an existing latest partition over NOW" {
    local fixture="tests/fixtures/make_partitions/start_timestamp_with_existing_partitions"
    local result="${fixture}/pgpartix_output.sql"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    pg_ctl reload

    run pgp-run-lifecycle -c "${fixture}/now.yaml"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"
    rm -f "${result}"

    [ "${status}" -eq 0 ]
    grep -Fq "already has partitions; using the latest partition's upper bound" <<< "${output}"
}

@test "pgp-run-lifecycle honours an explicit start timestamp when no latest partition exists" {
    local fixture="tests/fixtures/make_partitions/start_timestamp"
    local result="${fixture}/pgpartix_output.sql"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    pg_ctl reload

    run pgp-run-lifecycle -c "${fixture}/value.yaml"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"
    rm -f "${result}"

    [ "${status}" -eq 0 ]
    grep -Fq "INFO: No existing partition for table test.transactions; using the provided start timestamp (2025-03-01T00:00:00+00:00)" <<< "${output}"
}

@test "pgp-run-lifecycle prefers an existing latest partition over an explicit start timestamp" {
    local fixture="tests/fixtures/make_partitions/start_timestamp_with_existing_partitions"
    local result="${fixture}/pgpartix_output.sql"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    pg_ctl reload

    run pgp-run-lifecycle -c "${fixture}/value.yaml"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"
    rm -f "${result}"

    [ "${status}" -eq 0 ]
    grep -Fq "already has partitions; using the latest partition's upper bound (2025-04-01 00:00:00+00) instead of 2025-03-01T00:00:00+00:00" <<< "${output}"
}

@test "pgp-run-lifecycle reports a clear error when LATEST_PARTITION has no latest partition" {
    local fixture="tests/fixtures/run_lifecycle"
    local result="${fixture}/pgpartix_output.sql"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/setup.sql"
    pg_ctl reload

    run pgp-run-lifecycle -c "${fixture}/missing_latest_partition.yaml"

    psql --no-psqlrc --quiet --variable ON_ERROR_STOP=1 --file "${fixture}/teardown.sql"

    [ "${status}" -eq 1 ]
    grep -Fq "No latest partition exists for table test.transactions" <<< "${output}"
    [ ! -e "${result}" ]
}

for fixture in tests/fixtures/make_partitions/**/*.{yaml,yml}; do
    [[ "${fixture}" == */sql_failures/* ]] && continue
    directory="$(basename "$(dirname "${fixture}")")"
    bats_test_function \
        --description "pgp-run-lifecycle: ${directory} with $(basename "${fixture}")" \
        -- run_config_file "${fixture}"
done

for fixture in tests/fixtures/expire_partitions/**/*.{yaml,yml}; do
    fixture_name="${fixture%.yaml}"
    fixture_name="${fixture_name%.yml}"
    expected="${fixture_name}.expected.sql"
    if [[ -f "${expected}" ]]; then
        directory="$(basename "$(dirname "${fixture}")")"
        bats_test_function \
            --description "pgp-run-lifecycle: ${directory} with $(basename "${fixture}")" \
            -- run_config_file "${fixture}"
    fi
done
