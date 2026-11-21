# Contributing

Bug reports, feature requests, code changes, and documentation improvements are welcome through GitHub issues and pull requests.

## Development

**pgpartix** is packaged as a Docker image and developed with **Bash** and **SQL**.
Install **Docker** and a local [**uv**](https://docs.astral.sh/uv/getting-started/installation/)
to bootstrap the development environment. Run these commands from the repository root.

1. Create the development environment, including the pinned uv, pre-commit, and documentation tools:

    ```console
    uv sync --locked --group tooling --group docs
    ```

2. Activate the development environment:

    ```console
    source .venv/bin/activate
    ```

3. Install the Git hooks:

    ```console
    pre-commit install
    ```

## Project structure

```text
.
├── src
│   ├── bin                       # Binaries (pgp-*)
│   ├── sql                       # Database functions, numbered by load order
│   ├── schema.json               # JSON Schema for lifecycle configuration files
├── docs                          # Schema doc tooling (schema_doc_generator.sh, schema_doc.yaml)
│   └── docs                      # Published guides (index.md is the index),
│                                    plus the generated schema.html — this is the GitHub Pages root
├── examples                      # End-to-end configuration examples
├── tests                         # Bats integration tests and fixtures
│   ├── fixtures
│   │   ├── expire_partitions
│   │   ├── make_partitions
│   │   └── initdir               # SQL applied once when the test cluster starts
│   ├── test_make_partitions.sh
│   ├── test_expire_partitions.sh
│   ├── test_get_migration_filename.sh
│   ├── test_setup_infrastructure.sh
│   ├── test_pgp_start.sh
│   ├── run-tests.sh              # Runs the Bats suite in Docker
│   ├── coverage.sh               # Runs Bats under kcov and enforces MIN_COVERAGE
│   └── docker-compose-test.yaml
├── tools                         # Repo lifecycle scripts (schema doc freshness check)
└── config.sample.yaml            # Complete annotated configuration reference
```

## Architecture

pgpartix has two main components:

1. **The Binaries:** The `src/bin` commands orchestrate lifecycle generation.
2. **The Database Functions:** Functions in `src/sql` inspect PostgreSQL and render the DDL for lifecycle generation

## Testing

Tests are Bats integration tests driven through the public CLI, run inside the project's Docker image against a disposable PostgreSQL cluster. There is no unit-test layer or pgTAP suite; every SQL function is exercised only through the CLI commands that call it.

Each `test_*.sh` file under `tests/` covers one binary. `test_make_partitions.sh` and `test_expire_partitions.sh` additionally auto-discover every fixture directory under `tests/fixtures/{make_partitions,expire_partitions}/` and run it as its own test case, so adding coverage for a new option is usually just adding a fixture.

A fixture directory can contain:

| File | Purpose |
| --- | --- |
| `setup.sql` | Optional. Applied before the command runs (schema, tables, template objects, `ALTER SYSTEM SET mock.now = ...`). Requires a matching `teardown.sql`. |
| `teardown.sql` | Drops what `setup.sql` created. Required whenever `setup.sql` is present. |
| `config.yaml` | The lifecycle configuration passed to `-c`. Fixtures with multiple config files (e.g. one per scenario) each get their own `*.expected.sql`, matched by stripping the `.yaml`/`.yml` extension. |
| `config.expected.sql` (or `<name>.expected.sql`) | The exact output the command must produce, including `pgrubic format`'s formatting. |

The test runner diffs the generated file against `*.expected.sql` and then applies the generated SQL to a throwaway database to confirm it is valid, executable DDL - not just textually correct.

`COVERAGE=true tests/run-tests.sh` runs the test suite with coverage using the default PostgreSQL version.

To check coverage, use:

```bash
COVERAGE=true tests/run-tests.sh
```

To run the tests for a specific PostgreSQL version:

```bash
PG_MAJOR_VERSION=<POSTGRES_MAJOR_VERSION> tests/run-tests.sh
```

## Documentation

The schema reference is generated with [json-schema-for-humans](https://pypi.org/project/json-schema-for-humans/). After changing `src/schema.json`, run:

```bash
docs/schema_doc_generator.sh
```

Preview `docs/docs/schema.html` in a browser.

To build the documentation site after activating the development environment:

```bash
cd docs
uv run --locked --group tooling --group docs zensical build --clean
```

To preview changes to the documentation, from the parent directory, use:

```bash
zensical serve --config-file docs/mkdocs.yml --dev-addr 127.0.0.1:8000
```

## Release

The project uses [commitizen](https://commitizen-tools.github.io/commitizen/) to manage releases. To create a new release, run

```bash
tools/release.sh
```

The script switches to the default branch and pulls it, then runs `cz bump` to choose the next version from the commit messages, update the changelog, commit it, and tag the commit. It then pushes the release commit and its tag together, which triggers the release workflow.

The script refuses to run while tracked files have uncommitted changes. Pushing directly to the default branch requires permission to bypass its branch protection.

To see the version, tag, and changelog entry the next release would create from your current checkout, without changing anything, run

```bash
tools/release_preview.sh
```

or run the **Release preview** workflow from the Actions tab, which previews the default branch.
