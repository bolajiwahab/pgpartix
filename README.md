# pgpartix

[![GitHub Release](https://img.shields.io/github/v/release/bolajiwahab/pgpartix)](https://github.com/bolajiwahab/pgpartix/releases)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14%20%7C%2015%20%7C%2016%20%7C%2017%20%7C%2018-4169E1?logo=postgresql&logoColor=white)](https://github.com/bolajiwahab/pgpartix/pkgs/container/pgpartix)
[![Image tags](https://ghcr-badge.egpl.dev/bolajiwahab/pgpartix/tags?color=%2344cc11&ignore=latest&n=5&label=image+tags&trim=)](https://github.com/bolajiwahab/pgpartix/pkgs/container/pgpartix)
[![GitHub License](https://img.shields.io/github/license/bolajiwahab/pgpartix)](https://github.com/bolajiwahab/pgpartix/blob/main/LICENSE)
[![CI](https://github.com/bolajiwahab/pgpartix/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/bolajiwahab/pgpartix/actions/workflows/ci.yaml)
[![Trivy Security Scan](https://github.com/bolajiwahab/pgpartix/actions/workflows/trivy.yaml/badge.svg?branch=main)](https://github.com/bolajiwahab/pgpartix/actions/workflows/trivy.yaml)

pgpartix is a PostgreSQL partition-lifecycle migration generator. It inspects a PostgreSQL database and writes migrations for partitions that should be created or expired.

Run it:

- locally, with generated migration files reviewed and committed by the developer;
- from an existing CI/CD system;
- from a scheduled process on any machine that can reach the database and repository.

The optional GitHub helper provides a Dependabot- or Renovate-like pull-request workflow. pgpartix writes migrations but never applies them.

## What it provides

- Creation and expiration DDL from one declarative YAML configuration.
- Configurable future horizons and retention windows.
- Deterministic partition, index, and constraint naming.
- Replication of constraints, indexes, triggers, and storage settings from template tables or existing partitions.
- PostgreSQL date, timestamp, integer epoch, bigint epoch-millisecond, and UUIDv7 partitioning.
- Formatted migration files with [pgrubic](https://bolajiwahab.github.io/pgrubic/), suitable for normal review and deployment.
- Per-table failure isolation: valid output is retained while the command reports failures and exits nonzero.
- Optional GitHub PR reconciliation through the bundled `gh` CLI.
- Support for dedicated, least-privileged GitHub App authentication when that integration is used.
- PostgreSQL 14 and newer.

## Getting Started

For more, see the [documentation](https://pgpartix.azellar.com).

## How it works

```text
  PostgreSQL schema + lifecycle YAML
                    |
                    v
         pgpartix reconciliation
          /                    \
missing future partitions   expired partitions
           \               /
                    v
          formatted migration files
            /       |       \
           v        v        v
      local Git   CI/CD   scheduled host
            \       |       /
                    v
            review and deploy
```

## Quick start

Pull the image:

```bash
docker pull ghcr.io/bolajiwahab/pgpartix:latest
```

Then run the checked-in [quick-start example](examples/quick-start), which creates an ephemeral PostgreSQL cluster, loads a partitioned table, and generates both creation and expiration migrations:

```bash
docker run --rm \
  --volume "$PWD:/repository" \
  --workdir /repository \
  --env PGP_INIT_DIR=examples/quick-start/initdir \
  ghcr.io/bolajiwahab/pgpartix:latest \
  bash -lc '
    pgp-start &&
    pgp-run-lifecycle -c examples/quick-start/partition-lifecycle.yaml
  '
```

- `latest` contains the newest pgpartix release and highest stable PostgreSQL major.
- For reproducible runs, pin both versions with a tag such as `ghcr.io/bolajiwahab/pgpartix:0.16.2-pg18`.
- The only database setup input in this example is the initialization directory. It can contain `.sql`, `.sql.gz`, and `.sh` files, including scripts that invoke the application's existing schema or migration tooling.
- `--workdir /repository` is required because the image otherwise runs from `/src`, while the configuration and output paths are relative to the mounted repository.
- Generated SQL is written to `examples/quick-start/migrations/pgpartix_output.sql`; apply generated lifecycle migrations through the application's normal migration process.

See [Getting started](docs/docs/getting-started.md) for prerequisites, external database mode, and output validation.

## GitHub Actions

Call the reusable workflow on a schedule to open or update a pull request with the generated migrations:

```yaml
jobs:
  partition-lifecycle:
    permissions:
      contents: read
      packages: read
    uses: bolajiwahab/pgpartix/.github/workflows/partition-lifecycle.yaml@0.16.2
    with:
      config: partition-lifecycle.yaml
      image: "ghcr.io/bolajiwahab/pgpartix:0.16.2-pg18"
      init_dir: migrations/initdir
      app_client_id: ${{ vars.PGPARTIX_APP_CLIENT_ID }}
    secrets:
      app_private_key: ${{ secrets.PGPARTIX_APP_PRIVATE_KEY }}
```

See [GitHub Actions automation](docs/docs/github-actions.md#calling-the-reusable-workflow-directly) for the GitHub App setup, the schedule and every input.

## Included commands

| Command | Purpose |
| --- | --- |
| `pgp-start` | Start the bundled PostgreSQL cluster and apply schema initialization files. |
| `pgp-run-lifecycle` | Generate migrations for missing desired partitions, then detach/drop migrations for expired ones. |
| `pgp-gh-create-pr` | Optionally create or update a GitHub partition-lifecycle PR. |

Use the [CLI reference](docs/docs/cli-reference.md) for syntax and operational behavior.

## Contributing and support

See the [contributing guide](docs/docs/contributing.md). Use [GitHub issues](https://github.com/bolajiwahab/pgpartix/issues) for bugs, features, and usage questions.

## License

MIT
