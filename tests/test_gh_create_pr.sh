#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # each @test runs in its own subshell; env changes are intentionally local to it

bats_require_minimum_version 1.5.0

# shellcheck source=tests/conftest.sh
source "${BATS_TEST_DIRNAME}/conftest.sh"

function init_repo() {
    local repo="$1"

    mkdir -p "${repo}"
    (
        cd "${repo}" || exit 1
        git init --quiet
        git config user.email "test@example.com"
        git config user.name "test"
        echo "content" >README.md
        git add README.md
        git commit --quiet -m "init"
    )
}

# Sets up a local bare repository as "origin" so the full fetch/checkout/push
# flow can run for real, without touching an actual GitHub remote.
function init_repo_with_origin() {
    local origin="$1"
    local repo="$2"

    git init --quiet --bare "${origin}"
    git clone --quiet "${origin}" "${repo}"
    (
        cd "${repo}" || exit 1
        git config user.email "test@example.com"
        git config user.name "test"
        echo "content" >README.md
        git add README.md
        git commit --quiet -m "init"
        git push --quiet origin HEAD
    )
}

# Installs a fake `gh` on PATH so `pr list`/`pr create`/`pr edit` can be
# exercised for real without a network call or a GitHub token. Invocations
# are logged to GH_MOCK_LOG; `gh pr list` responds with GH_MOCK_PR_LIST_URL.
function install_fake_gh() {
    local fake_bin="$1"

    mkdir -p "${fake_bin}"
    cat >"${fake_bin}/gh" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "${GH_MOCK_LOG}"
case "$1 $2" in
    "pr list")
        printf '%s' "${GH_MOCK_PR_LIST_URL:-}"
        ;;
    "pr create")
        echo "https://github.example/owner/repo/pull/1"
        ;;
    "pr edit")
        ;;
esac
MOCK
    chmod +x "${fake_bin}/gh"
}

# Runs pgp-gh-create-pr against $1 via its -C flag rather than an external
# cd: kcov only attributes bash-coverage correctly when the traced process's
# own cwd matches the cwd kcov started tracing in, so the target directory
# is instead passed as an argument and cd'd into internally by the script.
function run_gh_create_pr_in() {
    local dir="$1"
    shift
    run pgp-gh-create-pr -C "${dir}" "$@"
}

@test "pgp-gh-create-pr shows help" {
    run pgp-gh-create-pr -h

    [[ ${status} -eq 0 ]]
    grep -Fq "Creates or updates a pull request on github." <<<"${output}"
}

@test "pgp-gh-create-pr rejects unknown options" {
    run pgp-gh-create-pr -z

    [[ ${status} -eq 2 ]]
    grep -Fq "Creates or updates a pull request on github." <<<"${output}"
}

@test "pgp-gh-create-pr fails when no git committer identity is configured" {
    local origin="${BATS_TEST_TMPDIR}/origin.git"
    local repo="${BATS_TEST_TMPDIR}/repo"

    init_repo_with_origin "${origin}" "${repo}"
    git -C "${repo}" config --unset user.email
    git -C "${repo}" config --unset user.name
    echo "new migration" >"${repo}/new_migration.sql"

    run_gh_create_pr_in "${repo}"

    [[ ${status} -ne 0 ]]
    grep -Fq "ERROR: Git committer identity is not configured." <<<"${output}"
}

@test "pgp-gh-create-pr reports no changes for a clean repository" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    init_repo "${repo}"

    run_gh_create_pr_in "${repo}"

    [[ ${status} -eq 0 ]]
    grep -Fq "No changes detected" <<<"${output}"
}

@test "pgp-gh-create-pr ignores an untracked .pgrubic_cache directory" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    init_repo "${repo}"
    mkdir -p "${repo}/.pgrubic_cache/1.3.0"
    echo "cache" >"${repo}/.pgrubic_cache/1.3.0/some_rule.json"

    run_gh_create_pr_in "${repo}"

    [[ ${status} -eq 0 ]]
    grep -Fq "No changes detected" <<<"${output}"
}

@test "pgp-gh-create-pr detects a real untracked file as a change" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    init_repo "${repo}"
    echo "new" >"${repo}/new_migration.sql"

    # No origin remote is configured, so the run cannot proceed to push or
    # create a PR. This only proves the untracked file was not mistaken for
    # "no changes" the way .pgrubic_cache is.
    run_gh_create_pr_in "${repo}"

    [[ ${status} -ne 0 ]]
    run ! grep -Fq "No changes detected" <<<"${output}"
}

@test "pgp-gh-create-pr creates a PR when none exists" {
    local origin="${BATS_TEST_TMPDIR}/origin.git"
    local repo="${BATS_TEST_TMPDIR}/repo"
    local fake_bin="${BATS_TEST_TMPDIR}/bin"
    local gh_log="${BATS_TEST_TMPDIR}/gh.log"

    init_repo_with_origin "${origin}" "${repo}"
    install_fake_gh "${fake_bin}"
    touch /src/partition_lifecycle.log
    echo "new migration" >"${repo}/new_migration.sql"

    export PATH="${fake_bin}:${PATH}"
    export GH_MOCK_LOG="${gh_log}"
    export GH_MOCK_PR_LIST_URL=""

    run_gh_create_pr_in "${repo}"

    [[ ${status} -eq 0 ]]
    grep -Fq "INFO: Creating PR..." <<<"${output}"
    grep -Fq "INFO: PR #1 created: https://github.example/owner/repo/pull/1" <<<"${output}"
    grep -Fq "pr create" "${gh_log}"
    run ! grep -Fq "pr edit" "${gh_log}"
    git -C "${origin}" branch --list "pgpartix/partition-lifecycle" | grep -Fq "pgpartix/partition-lifecycle"
}

@test "pgp-gh-create-pr updates the body of an existing PR" {
    local origin="${BATS_TEST_TMPDIR}/origin.git"
    local repo="${BATS_TEST_TMPDIR}/repo"
    local fake_bin="${BATS_TEST_TMPDIR}/bin"
    local gh_log="${BATS_TEST_TMPDIR}/gh.log"

    init_repo_with_origin "${origin}" "${repo}"
    install_fake_gh "${fake_bin}"
    touch /src/partition_lifecycle.log
    echo "another migration" >"${repo}/another_migration.sql"

    export PATH="${fake_bin}:${PATH}"
    export GH_MOCK_LOG="${gh_log}"
    export GH_MOCK_PR_LIST_URL="https://github.example/owner/repo/pull/1"

    run_gh_create_pr_in "${repo}" -b other-branch -t "custom title" -m "custom commit" \
        -n "custom-bot[bot]" -e "custom-bot[bot]@users.noreply.github.com"

    [[ ${status} -eq 0 ]]
    grep -Fq "INFO: PR already exists: https://github.example/owner/repo/pull/1" <<<"${output}"
    grep -Fq "INFO: Editing the body of https://github.example/owner/repo/pull/1" <<<"${output}"
    grep -Fq "pr edit https://github.example/owner/repo/pull/1" "${gh_log}"
    run ! grep -Fq "pr create" "${gh_log}"
    git -C "${origin}" branch --list "pgpartix/other-branch" | grep -Fq "pgpartix/other-branch"
    [[ "$(git -C "${origin}" log -1 --format='%an <%ae>' pgpartix/other-branch)" == "custom-bot[bot] <custom-bot[bot]@users.noreply.github.com>" ]]
}
