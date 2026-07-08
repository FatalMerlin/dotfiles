#!/usr/bin/env bash
# Test for feature-lint.sh — every manifest `feature:` must exist under .features.
set -eEuo pipefail
LINT="$(cd "$(dirname "$0")" && pwd)/feature-lint.sh"

fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

# A defaults.yaml with a `work` feature (flat) and a nested `linux.tmux` feature.
mkdir_manifest() {
  d="$(mktemp -d)"
  printf '%s\n' '{ features: { work: false, linux: { tmux: true } } }' > "$d/defaults.yaml"
  printf '%s\n' "$1" > "$d/packages.yaml"
  echo "$d"
}

# 1. valid: feature "work" exists -> pass (exit 0)
d=$(mkdir_manifest '{ packages: { brew: { glab: { env: { GITLAB_HOST: { value: "x", feature: "work" } } } } } }')
rc=0; bash "$LINT" "$d/packages.yaml" || rc=$?
check "valid feature 'work' passes" "$rc"
rm -rf "$d"

# 2. valid nested: feature "linux.tmux" exists -> pass
d=$(mkdir_manifest '{ packages: { brew: { t: { env: { T: { value: "x", feature: "linux.tmux" } } } } } }')
rc=0; bash "$LINT" "$d/packages.yaml" || rc=$?
check "valid nested feature 'linux.tmux' passes" "$rc"
rm -rf "$d"

# 3. typo: feature "wrok" not defined -> fail (exit non-zero), message names it
d=$(mkdir_manifest '{ packages: { brew: { glab: { env: { GITLAB_HOST: { value: "x", feature: "wrok" } } } } } }')
rc=0; out=$(bash "$LINT" "$d/packages.yaml" 2>&1) || rc=$?
check "typo feature 'wrok' fails" "$([ "$rc" -ne 0 ]; echo $?)"
printf '%s' "$out" | grep -q 'wrok' && check "error names the offending feature 'wrok'" 0 || check "error names the offending feature 'wrok'" 1
rm -rf "$d"

# 4. no features referenced -> pass (empty manifest section)
d=$(mkdir_manifest '{ packages: { brew: { jq: {} } } }')
rc=0; bash "$LINT" "$d/packages.yaml" || rc=$?
check "manifest with no feature refs passes" "$rc"
rm -rf "$d"

exit $fail
