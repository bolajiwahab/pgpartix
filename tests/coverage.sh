#!/bin/bash

set -euo pipefail

MIN_COVERAGE="${MIN_COVERAGE:-100}"
COVERAGE_DIR="${COVERAGE_DIR:-coverage}"

kcov \
  --clean \
  --dump-summary \
  --limits=50,100 \
  --exclude-line="if ! psql,done < <(yq,gunzip -c,body=\$(cat <<EOF,PR_URL=\"\$(gh pr list \\,PR_URL=\"\$(gh pr create \\" \
  --exclude-region='KCOV_EXCL_START:KCOV_EXCL_STOP' \
  --include-pattern=pgp- \
  --include-path=/usr/local/bin/ \
  "${COVERAGE_DIR}" \
  bats tests/test_*.sh

coverage_file=$(find "${COVERAGE_DIR}" -name coverage.json -print -quit)
coverage_xml=$(find "${COVERAGE_DIR}" -name cobertura.xml -print -quit)

if [[ -z "${coverage_file}" ]]; then
  echo "coverage.json not found"
  exit 1
fi

if [[ -z "${coverage_xml}" ]]; then
  echo "cobertura.xml not found"
  exit 1
fi

coverage=$(yq -r '.percent_covered' "${coverage_file}")

if [[ -z "${coverage}" || "${coverage}" == "null" ]]; then
  echo "Could not determine coverage percentage"
  exit 1
fi

printf 'Coverage: %.2f%%\n' "${coverage}"

uncovered_lines=$(yq -p=xml -oy -r "
  .coverage.packages.package.classes.class[]
  | select(.[\"+@line-rate\"] != \"1.000\")
  | .[\"+@filename\"] as \$file
  | [.lines.line[] | select(.[\"+@hits\"] == \"0\") | .[\"+@number\"]] as \$lines
  | \$file + \": \" + (\$lines | join(\", \"))
" "${coverage_xml}")

if [[ -n "${uncovered_lines}" ]]; then
  printf '\nUncovered lines:\n%s\n' "${uncovered_lines}"
fi

awk -v c="${coverage}" -v min="${MIN_COVERAGE}" '
BEGIN {
  if (c < min) {
    printf "Coverage %.2f%% is below required %.0f%%\n", c, min
    exit 1
  }
}'
