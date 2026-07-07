#!/usr/bin/env bash
# Test for run_onchange_resolve-deps.sh.tmpl — the aliases: extension (Task 10).
#
# Renders the resolver against fixture manifests via tests/lib/render-resolver.sh
# (a REAL sandboxed `chezmoi apply` — see that script's header for why) and
# asserts:
#   - an `aliases:` map emits `alias NAME="<resolved>"` lines *inside* the
#     tool's have-guard (not before/after it), mirroring how test-resolver-env
#     asserts `export` placement for `env:` and test-resolver-path asserts
#     `ifpath_append` placement for `path:`
#   - the emitted deps.sh is syntax-clean under bash (and zsh, where available)
#   - the Task 7/8/9 bare-`{}` case still emits a plain `if have NAME; then`
#     guard (no regression from the aliases-aware rewrite)
#
# Split into a bash-only section and a zsh-only section, mirroring
# tests/test-core-lib.sh and tests/test-resolver-env.sh/-path.sh: zsh is
# unavailable in git-bash on this machine, so run_zsh_tests SKIPs there
# instead of failing; the controller runs this same script under WSL to
# exercise the zsh -n leg.
#
# Mechanics note: every grep-based assertion uses the crash-proof pattern
# `rc=0; grep -q ... || rc=$?; check "name" "$rc"` rather than
# `grep -q ...; check "$?"` — under `set -e`, a failing `grep -q` inside the
# condition of `||` is safe, but a bare failing command as its own statement
# would abort the script before `check` ever runs and reports FAIL. This way
# a regression reports FAIL instead of silently crashing the test run.
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

render_fixture() {
  # $1 = KYAML content for .chezmoidata/packages.yaml
  fixture="$(mktemp)"
  printf '%s\n' "$1" > "$fixture"
  bash "$HERE/lib/render-resolver.sh" "$fixture"
}

run_bash_tests() {
  echo "--- bash section ---"

  # --- aliases: fixture: two literal aliases under a single tool ---
  deps_aliases="$(render_fixture '{ packages: { brew: { dstask: { aliases: { task: "dstask", t: "dstask" } } } } }')"

  rc=0
  grep -q 'alias task="dstask"' "$deps_aliases" || rc=$?
  check "aliases: literal value emitted as alias task=" "$rc"

  rc=0
  grep -q 'alias t="dstask"' "$deps_aliases" || rc=$?
  check "aliases: literal value emitted as alias t=" "$rc"

  # Both must sit INSIDE the have-guard for dstask, not before/after it (same
  # awk state-machine test-resolver-env/-path use for export/ifpath_append
  # placement).
  rc=0
  awk '/if have dstask/{g=1} g&&/alias task="dstask"/{f=1} /^else /{g=0} END{exit f?0:1}' "$deps_aliases" || rc=$?
  check "aliases: alias task= sits inside the have-guard" "$rc"

  rc=0
  awk '/if have dstask/{g=1} g&&/alias t="dstask"/{f=1} /^else /{g=0} END{exit f?0:1}' "$deps_aliases" || rc=$?
  check "aliases: alias t= sits inside the have-guard" "$rc"

  rc=0
  bash -n "$deps_aliases" || rc=$?
  check "aliases fixture: bash -n clean" "$rc"

  # --- Task 7/8/9 regression: bare `{}` still emits a plain have-guard ---
  deps_bare="$(render_fixture '{ packages: { brew: { jq: {} } } }')"

  rc=0
  grep -q 'if have jq; then' "$deps_bare" || rc=$?
  check "bare {} still emits plain have-guard (no regression)" "$rc"

  rc=0
  grep -q 'alias ' "$deps_bare" && rc=1 || rc=0
  check "bare {} emits no alias lines" "$rc"

  rc=0
  bash -n "$deps_bare" || rc=$?
  check "bare fixture: bash -n clean" "$rc"

  # Stash paths for the zsh section.
  DEPS_ALIASES_PATH="$deps_aliases"
  DEPS_BARE_PATH="$deps_bare"
}

run_zsh_tests() {
  echo "--- zsh section ---"

  if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: zsh not found on this machine — cannot verify zsh -n here" \
      "(controller runs this script under WSL to exercise this leg)"
    return 0
  fi

  for pair in "aliases:$DEPS_ALIASES_PATH" "bare:$DEPS_BARE_PATH"; do
    name="${pair%%:*}"
    path="${pair#*:}"
    rc=0
    zsh -n "$path" || rc=$?
    check "zsh -n clean ($name)" "$rc"
  done
}

main() {
  run_bash_tests
  run_zsh_tests
  exit "$fail"
}

main "$@"
