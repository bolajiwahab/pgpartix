# CLI reference

The pgpartix image contains commands for preparing PostgreSQL and generating lifecycle migrations. It also includes an optional GitHub pull-request helper.

## Database environment

`pgp-run-lifecycle` and `pgp-setup-infrastructure` read these connection variables:

| Variable | Default | Description |
| --- | --- | --- |
| `PGP_USER` | `postgres` | PostgreSQL user. |
| `PGP_PASSWORD` | `postgres` | PostgreSQL password. |
| `PGP_HOST` | `localhost` | PostgreSQL host. |
| `PGP_PORT` | `5432` | PostgreSQL port. |
| `PGP_DATABASE` | `postgres` | Database containing the partitioned schema. |

These defaults target the disposable local cluster created by `pgp-start`, so local-cluster users do not need to provide credentials or endpoints. They are not recommended credentials for external databases. When connecting to an external database, override all five explicitly.

External database example:

```bash
export PGP_USER=partition_catalog_reader
export PGP_PASSWORD='...'
export PGP_HOST=postgres.example.internal
export PGP_PORT=5432
export PGP_DATABASE=application_catalog
```

## `pgp-start`

Creates and starts a local PostgreSQL cluster and optionally applies an initialization directory. When using an external database, there is no need to invoke `pgp-start`; invoke the lifecycle command directly with the [database environment](#database-environment) variables.

```text
OPTIONS:
  -i  Initialization directory (optional; supports .sh, .sql, .sql.gz)
  -h  Show help
```

The equivalent environment variables are:

| Variable | Default | Description |
| --- | --- | --- |
| `PGP_INIT_DIR` | None | Initialization directory used when `-i` is omitted. |

Examples:

```bash
pgp-start -i migrations/initdir
```

Initialization files are processed in sorted order. Executable `.sh` files are run, non-executable `.sh` files are sourced, `.sql` files are passed to `psql`, and `.sql.gz` files are decompressed into `psql`.

## `pgp-run-lifecycle`

Runs the full partition lifecycle for every configured table: inspects parent and template tables and generates DDL for missing partitions and replicated objects, then generates detach and/or drop DDL for partitions whose upper bounds are outside the configured retention period. Both phases always run against every table in the config, regardless of per-table failures in either phase.

```text
OPTIONS:
  -c  Configuration file or directory (default: .)
  -h  Show help
```

Examples:

```bash
pgp-run-lifecycle -c partition-lifecycle.yaml
pgp-run-lifecycle -c config/partitions
```

When a directory is supplied, `.yaml` and `.yml` files are processed in sorted path order.

Expiration behavior is controlled by `retention`, `detach_only`, `detach_first`, `detach_concurrently`, and `idempotent`. See [Expiration options](configuration.md#expiration-options).

## `pgp-setup-infrastructure`

Installs or refreshes pgpartix's SQL helper functions in the configured database. The lifecycle commands call it automatically.

```text
OPTIONS:
  -h  Show help
```

It uses the same connection defaults and optional `PGP_*` overrides as the lifecycle commands.

## `pgp-gh-create-pr`

Optionally creates or updates a GitHub pull request containing generated repository changes. It is designed to run inside a CI job (for example, the reusable GitHub Actions workflow) against a repository already checked out at the desired base branch - it branches from the current `HEAD` rather than fetching or resetting to a remote ref itself, so it is not intended for ad hoc local invocation. Migration generation itself does not depend on this command; users may commit and push locally, or publish through another CI/CD system or scheduler instead.

```text
OPTIONS:
  -C  Repository directory to operate in (default: .)
  -b  Branch suffix (default: partition-lifecycle)
  -t  Pull-request title (default: chore: partition lifecycle)
  -m  Commit message (default: pull-request title)
  -n  Committer name (default: the already-configured git identity)
  -e  Committer email (default: the already-configured git identity)
  -h  Show help
```

`GH_TOKEN` must authenticate an identity allowed to push branches and read/write pull requests. A short-lived dedicated GitHub App token is recommended. A Git committer identity must already be configured, either via `-n`/`-e` or by the calling environment; the command exits with an error otherwise.

```bash
GH_TOKEN="..." pgp-gh-create-pr \
  -b database-partitions \
  -t "chore(db): maintain partitions" \
  -m "chore(db): regenerate partition lifecycle migrations" \
  -n "some-bot[bot]" \
  -e "some-bot[bot]@users.noreply.github.com"
```

Behavior:

- exits successfully without Git operations when no tracked or untracked file changed;
- requires a configured Git committer identity, failing fast otherwise;
- creates or resets `pgpartix/<branch>` from the repository state already checked out in the job;
- commits all repository changes;
- force-updates the dedicated branch;
- determines the remote default branch and creates a PR against it when none is open;
- updates the body of the existing PR on later runs.

Do not add human commits to the automation branch; change the declarative configuration and rerun reconciliation instead.

See [Automating lifecycle PRs with GitHub Actions](github-actions.md) for App creation and a complete workflow.

## Exit and publication behavior

The lifecycle generator uses a staging directory and handles tables independently, in both the make and expire phases.

| Situation | Result |
| --- | --- |
| Every table succeeds | Successful migrations are published; exit `0`. |
| No lifecycle change is needed | No empty migration is published; exit `0`. |
| Some tables succeed and some fail | Successful migrations are published, failures are summarized; exit `1`. |
| A table's SQL generation fails, in either phase | Its partial file is removed; other tables continue, and the other phase still runs. |
| A table's formatting fails | Its unformatted file is removed; other tables continue. |
| Configuration is invalid | No table processing occurs; exit `1`. |

Multiple successful tables may share one output filename, including across the make and expire phases. Their formatted SQL is merged in configuration order. Failed table output is never appended.

Any automation should record the generation exit status separately from publication so successful table output can be retained without hiding failures. In GitHub Actions, use `continue-on-error` on the generation step, create or update the PR with successful output, then explicitly fail the job based on the recorded step outcome. The [GitHub Actions guide](github-actions.md#why-generation-uses-continue-on-error) includes this pattern.
