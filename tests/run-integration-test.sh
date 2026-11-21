#!/bin/bash

set -euo pipefail

compose_file="tests/docker-compose-integration.yaml"

cleanup() {
    docker compose -f "${compose_file}" down -v --remove-orphans
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ${PGP_SKIP_BUILD:-false} != "true" ]]; then
    if [[ ${PGP_NO_CACHE:-false} == "true" ]]; then
        docker compose -f "${compose_file}" build --no-cache
    else
        docker compose -f "${compose_file}" build
    fi
fi

cleanup

# An external database.
docker compose -f "${compose_file}" up \
    --force-recreate \
    --abort-on-container-exit \
    --exit-code-from pgpartix \
    --quiet-pull \
    --remove-orphans \
    postgres pgpartix

# An ephemeral cluster, started from a container running as root.
docker compose -f "${compose_file}" run --rm pgpartix-ephemeral
