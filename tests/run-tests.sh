#!/bin/bash

set -euo pipefail

compose_file="tests/docker-compose-test.yaml"

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

docker compose -f "${compose_file}" up \
    --force-recreate \
    --abort-on-container-exit \
    --quiet-pull \
    --remove-orphans \
    test
