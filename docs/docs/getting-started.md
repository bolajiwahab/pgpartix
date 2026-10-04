# Getting started

pgpartix inspects a PostgreSQL database and writes migration files for missing and expired partitions. Review and deploy them through the application's existing migration process; pgpartix does not apply them.

## Requirements

- PostgreSQL 14 or newer.
- A single-column `RANGE`-partitioned parent table.
- A supported partition key: `date`, `timestamp`, `timestamptz`, `integer`, `bigint`, or UUIDv7-compatible `uuid`.
- An existing directory for generated migration files.
- A database containing the parent tables and any configured schemas, tablespaces, or template tables.

The packaged image includes PostgreSQL setup utilities, the pgpartix CLIs, pgrubic, Git, and GitHub CLI.

## Persisting migration files onto the host filesystem

To persist migration files generated inside the container onto the host filesystem, a bind mount is used. The bind-mounted directory must be writable so that `pgpartix` can create and persist the generated migration files on the host.

## Running pgpartix as root

`pgpartix` uses `initdb` when creating an ephemeral PostgreSQL cluster. PostgreSQL does not allow `initdb` to run as `root`.

If the container or execution environment runs as `root`, run `pgp-start` as the unprivileged `pgpuser` user instead:

```bash
runuser -u pgpuser -- pgp-start
```

The `pgpartix` container runs as `pgpuser` by default, so this is only required when the container user is overridden to `root` or the execution environment runs the container as `root`.

## Install the image

```bash
docker pull ghcr.io/bolajiwahab/pgpartix:latest
```

`latest` contains the newest pgpartix release and highest stable PostgreSQL major. Pin both versions for reproducible runs, for example:

```bash
docker pull ghcr.io/bolajiwahab/pgpartix:0.11.0-pg18
```

The container starts as an unprivileged user except otherwise overridden with `--user root`, [see](https://docs.docker.com/engine/containers/run/#user).

PostgreSQL is already installed, and `pgp-start` creates the disposable local cluster without root privileges.

## Run the checked-in example

The repository contains a complete runnable example:

```text
examples/quick-start
├── initdir
│   ├── 01_init.sql
│   └── migrations # a symlink to the actual migration folder; this allows applying current migrations to the ephemeral cluster
├── migrations
│   └── .gitignore
└── partition-lifecycle.yaml
```

From the repository root, run:

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

`pgp-start` uses the PostgreSQL major bundled in the selected image and supplies the local cluster connection settings. `PGP_INIT_DIR` is the only database setup input here and loads the example schema. `--workdir /repository` makes repository-relative configuration and output paths resolve inside the mounted host directory. The generated migration files appear at `examples/quick-start/migrations/` on the host.

To adapt the example, copy its configuration and initialization layout into the application repository. Change `lifecycle.directory`, the configured tables, and the initialization SQL or scripts to match the application's schema migration setup. The output directory must already exist. For all available options, inheritance rules, and naming placeholders, use the [configuration reference](https://pgpartix.azellar.com/configuration) and [annotated sample](https://pgpartix.azellar.com/config.sample.yaml).

## Choose a database source

pgpartix needs an accurate PostgreSQL database. It supports two practical approaches.

### Ephemeral PostgreSQL from repository migrations

This is the recommended mode for local evaluation and automated environments. Provide an initialization directory that recreates the schema pgpartix should inspect.

`pgp-start -i` processes files in natural order:

- executable or sourceable `.sh` scripts;
- `.sql` files;
- `.sql.gz` files.

Use the initialization directory to recreate the application's schema. Scripts may invoke the application's existing migration tool, so no local-cluster connection settings are needed.

Example repository layout:

```text
.
├── initdir
│   ├── 01_init.sql
│   └── migrations # a symlink to the actual migration folder; this allows applying current migrations to the ephemeral cluster
├── migrations
└── partition-lifecycle.yaml
```

For an application repository, the equivalent command is:

```bash
docker run --rm \
  --volume "$PWD:/repository" \
  --workdir /repository \
  --env PGP_INIT_DIR=initdir \
  ghcr.io/bolajiwahab/pgpartix:latest \
  bash -lc '
    pgp-start &&
    pgp-run-lifecycle -c partition-lifecycle.yaml
  '
```

The generated migration files appear in the `migrations` folder on the host.

### Existing external database

Use an existing non-production database when it is the authoritative representation of the schema. Select the image variant matching the target PostgreSQL major, then supply connection settings:

```bash
docker run --rm \
  --volume "$PWD:/repository" \
  --workdir /repository \
  --env PGP_USER="$PGP_USER" \
  --env PGP_PASSWORD="$PGP_PASSWORD" \
  --env PGP_HOST="$PGP_HOST" \
  --env PGP_PORT="$PGP_PORT" \
  --env PGP_DATABASE="$PGP_DATABASE" \
  ghcr.io/bolajiwahab/pgpartix:0.11.0-pg18 \
  pgp-run-lifecycle -c partition-lifecycle.yaml
```

The connection role must be able to inspect the application catalog, creates a dedicated schema `pgpartix` for the helper objects, and create or replace helper objects in the `pgpartix` schema. Prefer a non-production database and restrict network and credential access appropriately.

## Review the output

`pgp-run-lifecycle` produces DDL for missing desired ranges, then detach and/or drop DDL for ranges outside the retention period.

Before applying generated migrations:

1. Review partition bounds and names.
2. Review every detach or drop operation.
3. Run the repository's SQL formatter and linter if additional rules apply.
4. Execute migrations against a disposable database.
5. Deploy them through the existing migration process.

pgpartix formats each table independently. If one table fails, valid output from other tables is retained, the failed table's partial output is removed, and the command exits nonzero.

## Choose how to publish the result

Generated migrations are ordinary repository files. Publish them by:

- run locally, review the files, then use the normal `git add`, `git commit`, and `git push` workflow;
- invoke the lifecycle commands from an existing GitHub, GitLab, Jenkins, or other CI/CD pipeline;
- schedule a script with cron, a systemd timer, or an infrastructure scheduler on a VM or runner, then commit and push using that environment's credentials;
- use the bundled GitHub helper to maintain a dedicated pull request automatically.

Preserve the generator exit status: it can produce valid files for successful tables while returning nonzero for another table. Keep the run visibly failed even if you publish the successful output.

## Optional GitHub automation

The [GitHub Actions guide](github-actions.md) shows how to schedule generation and create or refresh a PR with a least-privileged GitHub App.

For command syntax and environment variables, see the [CLI reference](cli-reference.md).
