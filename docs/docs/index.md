# pgpartix

[![GitHub Release](https://img.shields.io/github/v/release/bolajiwahab/pgpartix)](https://github.com/bolajiwahab/pgpartix/releases)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14%20%7C%2015%20%7C%2016%20%7C%2017%20%7C%2018-4169E1?logo=postgresql&logoColor=white)](https://github.com/bolajiwahab/pgpartix/pkgs/container/pgpartix)
[![Image tags](https://ghcr-badge.egpl.dev/bolajiwahab/pgpartix/tags?color=%2344cc11&ignore=latest&n=5&label=image+tags&trim=)](https://github.com/bolajiwahab/pgpartix/pkgs/container/pgpartix)
[![GitHub License](https://img.shields.io/github/license/bolajiwahab/pgpartix)](https://github.com/bolajiwahab/pgpartix/blob/main/LICENSE)
[![CI](https://github.com/bolajiwahab/pgpartix/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/bolajiwahab/pgpartix/actions/workflows/ci.yaml)
[![Trivy Security Scan](https://github.com/bolajiwahab/pgpartix/actions/workflows/trivy.yaml/badge.svg?branch=main)](https://github.com/bolajiwahab/pgpartix/actions/workflows/trivy.yaml)

pgpartix generates reviewable PostgreSQL partition-lifecycle migrations. Users can commit them locally, integrate them with any CI/CD or scheduling environment, or use the optional GitHub pull-request helper.

## Start here

1. [Getting started](getting-started.md) - run the container, prepare a schema catalog, and generate the first migrations.
2. [Configuration reference](configuration.md) - configure partition creation, expiration, naming, templates, storage, and table overrides.
3. [Optional GitHub Actions automation](github-actions.md) - run reconciliation on a GitHub schedule and create PRs through a dedicated GitHub App.

## Reference

- [CLI reference](cli-reference.md) - commands, environment variables, exit behavior, and examples.
- [Annotated configuration sample](config.sample.yaml) - a complete configuration using the current schema.
- [Schema reference](schema.html) - current schema.
- [Contributing](contributing.md) - development environment, testing, and contribution workflow.
