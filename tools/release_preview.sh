#!/bin/bash

set -euo pipefail

# tools/release_preview.sh
#
# Shows the version, tag and changelog entry the next release would create from the
# current checkout, without changing anything.

cd -- "$(dirname -- "$0")/.."

# commitizen exits with 21 when there is nothing to release, which is not a failure
# for a preview.
uv run --locked --no-build --only-group release cz --no-raise 21 bump --dry-run --yes
