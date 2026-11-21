#!/bin/bash

set -euo pipefail

echo "INFO: Setting up mock timestamp"

printf '%s\n' \
    "mock.now = 'disabled'" \
    "search_path = 'mock, pg_catalog, public'" \
    >>"${PGDATA}/postgresql.conf"

# The test cluster is thrown away after each run, so nothing needs to survive a crash.
echo "INFO: Turning off durability"

printf '%s\n' \
    "fsync = off" \
    "synchronous_commit = off" \
    "full_page_writes = off" \
    >>"${PGDATA}/postgresql.conf"

pg_ctl reload

echo "INFO: Creating test tablespace directories"
mkdir -p /var/lib/pgpartix/tablespaces/pgpartix
mkdir -p /var/lib/pgpartix/tablespaces/pgpartix_fast

echo "INFO: Setting up infrastructure"
pgp-setup-infrastructure
