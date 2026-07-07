#!/usr/bin/env bash
# Test for run_onchange_resolve-deps.sh.tmpl — the apply-time resolver skeleton.
#
# Renders the resolver against a fixture manifest ({ packages: { brew: { jq: {} } } })
# via tests/lib/render-resolver.sh (chezmoi execute-template + run), then asserts
# the emitted deps.sh has the expected shape: GENERATED banner, dep_reset_missing,
# and a per-tool `have`-guard that dep_mark_missing's on absence. deps.sh must NOT
# contain a dep_report_missing call — that report moved to dot_zshrc.tmpl (fired
# once, after ALL sourcing, so it covers both the manifest guards below AND the
# legacy dependencies/*.zsh bootstraps that run after deps.sh is sourced). Also
# checks the emitted file is syntax-clean under both bash and zsh.
#
# Split into a bash-only section (content assertions + bash -n) and a zsh-only
# section (zsh -n), mirroring tests/test-core-lib.sh: zsh is unavailable in
# git-bash on this machine, so run_zsh_tests SKIPs there instead of failing;
# the controller runs this same script under WSL to exercise the zsh -n leg.
set -eEuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

fail=0
# check NAME RESULT — RESULT is 0 (pass) or nonzero (fail); no re-evaluation.
check() {
  if [ "$2" -eq 0 ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1"
    fail=1
  fi
}

render() {
  fixture="$(mktemp)"
  printf '{ packages: { brew: { jq: {} } } }\n' > "$fixture"
  bash "$HERE/lib/render-resolver.sh" "$fixture"
}

run_bash_tests() {
  echo "--- bash section ---"

  deps="$(render)"

  grep -q 'GENERATED' "$deps"
  check "banner present" "$?"

  grep -q 'dep_reset_missing' "$deps"
  check "dep_reset_missing present" "$?"

  grep -q 'if have jq; then' "$deps"
  check "have-guard for jq" "$?"

  grep -q 'dep_mark_missing jq' "$deps"
  check "dep_mark_missing jq on the else branch" "$?"

  rc=0
  grep -q 'dep_report_missing' "$deps" && rc=1
  check "deps.sh does NOT contain dep_report_missing (report moved to startup)" "$rc"

  bash -n "$deps"
  check "bash -n clean" "$?"

  # Stash the rendered path for the zsh section (same file, no re-render needed).
  DEPS_PATH="$deps"
}

run_zsh_tests() {
  echo "--- zsh section ---"

  if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: zsh not found on this machine — cannot verify zsh -n here" \
      "(controller runs this script under WSL to exercise this leg)"
    return 0
  fi

  zsh -n "$DEPS_PATH"
  check "zsh -n clean" "$?"
}

main() {
  run_bash_tests
  run_zsh_tests
  exit "$fail"
}

main "$@"
