#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# shellcheck source=tests/conftest.sh
source "${BATS_TEST_DIRNAME}/conftest.sh"

function create_postgres_stubs() {
    local directory="${1}"

    mkdir -p "${directory}"
    printf '#!/bin/bash\nexit 0\n' > "${directory}/initdb"
    printf '#!/bin/bash\nexit 0\n' > "${directory}/pg_ctl"
    printf '#!/bin/bash\ncat >/dev/null\n' > "${directory}/psql"
    chmod +x "${directory}/initdb" "${directory}/pg_ctl" "${directory}/psql"
}

@test "pgp-start shows help" {
    run pgp-start -h

    [[ "${status}" -eq 0 ]]
    grep -Fq "Starts the bundled PostgreSQL version" <<< "${output}"
}

@test "pgp-start rejects unknown options" {
    run pgp-start -z

    [[ "${status}" -eq 2 ]]
    grep -Fq "Starts the bundled PostgreSQL version" <<< "${output}"
}

@test "pgp-start rejects a missing init directory" {
    run pgp-start -i "${BATS_TEST_TMPDIR}/missing"

    [[ "${status}" -eq 1 ]]
    grep -Fq "does not exist or is not a directory" <<< "${output}"
}

@test "pgp-start rejects an initialized data directory" {
    run pgp-start

    [[ "${status}" -eq 1 ]]
    grep -Fq "already contains a PostgreSQL cluster" <<< "${output}"
}

@test "pgp-start applies supported init scripts" {
    local stub_directory="${BATS_TEST_TMPDIR}/bin"
    local init_directory="${BATS_TEST_TMPDIR}/init"
    local executable_marker="${BATS_TEST_TMPDIR}/executable.marker"
    local sourced_marker="${BATS_TEST_TMPDIR}/sourced.marker"

    create_postgres_stubs "${stub_directory}"
    mkdir -p "${init_directory}"

    printf "#!/bin/bash\ntouch \"\${EXECUTABLE_MARKER}\"\n" > "${init_directory}/01__executable.sh"
    printf "touch \"\${SOURCED_MARKER}\"\n" > "${init_directory}/02__sourced.sh"
    printf 'SELECT 1;\n' > "${init_directory}/03__plain.sql"
    printf 'SELECT 1;\n' | gzip > "${init_directory}/04__compressed.sql.gz"
    chmod +x "${init_directory}/01__executable.sh"

    run env \
        PATH="${stub_directory}:${PATH}" \
        PGDATA="${BATS_TEST_TMPDIR}/data" \
        EXECUTABLE_MARKER="${executable_marker}" \
        SOURCED_MARKER="${sourced_marker}" \
        pgp-start -i "${init_directory}"

    [[ "${status}" -eq 0 ]]
    [[ -e "${executable_marker}" ]]
    [[ -e "${sourced_marker}" ]]
}

@test "pgp-start finds PostgreSQL binaries through pg_config" {
    local stub_directory="${BATS_TEST_TMPDIR}/postgres/bin"
    local path_directory="${BATS_TEST_TMPDIR}/path"

    create_postgres_stubs "${stub_directory}"
    mkdir -p "${path_directory}"
    printf '%s\n' '#!/bin/bash' "printf %s \"\${POSTGRES_BIN_DIR}\"" > "${path_directory}/pg_config"
    chmod +x "${path_directory}/pg_config"

    run env \
        PATH="${path_directory}:/usr/bin:/bin" \
        POSTGRES_BIN_DIR="${stub_directory}" \
        PGDATA="${BATS_TEST_TMPDIR}/data" \
        PGP_INIT_DIR="" \
        /usr/local/bin/pgp-start

    [[ "${status}" -eq 0 ]]
}
