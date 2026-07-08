#!/usr/bin/env bash
# Test for prototype/tests/kyaml-lint.sh — exercises the four acceptance
# boundaries: valid flow YAML (accept), block mapping (reject), trailing
# comma in a flow collection (reject), and invalid YAML (reject).
# Requires `yq` (Mike Farah's Go yq) on PATH — run under WSL/Linux where the
# lint's own dependency is installed; not runnable from plain git-bash on
# Windows (no yq there).
set -eEuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/kyaml-lint.sh"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

printf '{ packages: { brew: { jq: {} } } }\n' > "$WORKDIR/_good.yaml"
printf 'packages:\n  brew:\n    jq: {}\n'      > "$WORKDIR/_block.yaml"   # block mapping
printf '{ a: [ 1, 2, ] }\n'                     > "$WORKDIR/_tc.yaml"      # trailing comma
printf '{ a: 1\n'                               > "$WORKDIR/_bad.yaml"     # invalid YAML
printf '{\n  a: {\n    b: ""\n  }\n}\n'          > "$WORKDIR/_empty_string.yaml"  # empty-string flow value

fail=0

if bash "$LINT" "$WORKDIR/_good.yaml"; then
  echo "ok: good flow YAML accepted"
else
  echo "FAIL: good flow YAML rejected"; fail=1
fi

if bash "$LINT" "$WORKDIR/_block.yaml"; then
  echo "FAIL: block mapping accepted"; fail=1
else
  echo "ok: block mapping rejected"
fi

if bash "$LINT" "$WORKDIR/_tc.yaml"; then
  echo "FAIL: trailing comma accepted"; fail=1
else
  echo "ok: trailing comma rejected"
fi

if bash "$LINT" "$WORKDIR/_bad.yaml"; then
  echo "FAIL: invalid YAML accepted"; fail=1
else
  echo "ok: invalid YAML rejected"
fi

# Regression: a multi-line flow mapping whose last-on-its-line value is an
# empty string (`b: ""`) must NOT be misread as a bare block-mapping key
# (`b:`). See strip_strings in kyaml-lint.sh — quoted spans are replaced by a
# sentinel, not blanked, so this stays a valid flow-style value.
if bash "$LINT" "$WORKDIR/_empty_string.yaml"; then
  echo "ok: empty-string flow value accepted"
else
  echo "FAIL: empty-string flow value rejected"; fail=1
fi

# Workflow-exception path must be skipped even if it contains block YAML.
mkdir -p "$WORKDIR/.github/workflows"
printf 'on:\n  push:\n' > "$WORKDIR/.github/workflows/ci.yml"
if bash "$LINT" "$WORKDIR/.github/workflows/ci.yml"; then
  echo "ok: workflow YAML skipped"
else
  echo "FAIL: workflow YAML was linted and rejected"; fail=1
fi

exit "$fail"
