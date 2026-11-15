# pgpartix

![GitHub Release](https://img.shields.io/github/v/release/bolajiwahab/pgpartix)
[![CI](https://github.com/bolajiwahab/pgpartix/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/bolajiwahab/pgpartix/actions/workflows/ci.yaml)
[![release](https://github.com/bolajiwahab/pgpartix/actions/workflows/release.yaml/badge.svg)](https://github.com/bolajiwahab/pgpartix/actions/workflows/release.yaml)
![GitHub License](https://img.shields.io/github/license/bolajiwahab/pgpartix)
![GitHub Container Registry](https://ghcr-badge.egpl.dev/bolajiwahab/pgpartix/tags?color=%2344cc11&ignore=latest&n=5&label=image+tags&trim=)
[![Trivy](https://img.shields.io/badge/Trivy-Container%20Security-1904DA?logo=trivy&logoColor=white)](https://trivy.dev/)
[![Hadolint](https://img.shields.io/badge/Hadolint-Dockerfile%20Linting-0D597F?logo=docker&logoColor=white)](https://github.com/hadolint/hadolint)

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

`latest` contains the newest pgpartix release and highest stable PostgreSQL major. For reproducible runs, pin both versions with a tag such as `0.11.0-pg18`. The only database setup input in this example is the initialization directory. It can contain `.sql`, `.sql.gz`, and `.sh` files, including scripts that invoke the application's existing schema or migration tooling. `--workdir /repository` is required because the image otherwise runs from `/src`, while the configuration and output paths are relative to the mounted repository. Generated SQL is written to `examples/quick-start/migrations/pgpartix_output.sql`; apply generated lifecycle migrations only through the application's normal migration process.

See [Getting started](docs/docs/getting-started.md) for prerequisites, external database mode, and output validation.

## Included commands

| Command | Purpose |
| --- | --- |
| `pgp-start` | Start the bundled PostgreSQL cluster and apply schema initialization files. |
| `pgp-run-lifecycle` | Generate migrations for missing desired partitions, then detach/drop migrations for expired ones. |
| `pgp-setup-infrastructure` | Install the SQL functions used to inspect and render lifecycle DDL. |
| `pgp-get-migration-filename` | Resolve migration filename templates. |
| `pgp-gh-create-pr` | Optionally create or update a GitHub partition-lifecycle PR. |

Use the [CLI reference](docs/docs/cli-reference.md) for syntax and operational behavior.

## Contributing and support

See the [contributing guide](docs/docs/contributing.md). Use [GitHub issues](https://github.com/bolajiwahab/pgpartix/issues) for bugs, features, and usage questions.

## License

MIT
