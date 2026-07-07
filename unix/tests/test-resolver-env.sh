#!/usr/bin/env bash
# Test for run_onchange_resolve-deps.sh.tmpl — the env: + gate: extension
# (Task 8, backlog #1).
#
# Renders the resolver against fixture manifests via tests/lib/render-resolver.sh
# (chezmoi execute-template + run) and asserts:
#   - an `env:` map emits `export NAME="<resolved>"` lines *inside* the tool's
#     have-guard (not before/after it)
#   - `gate: "!wsl"` / `gate: "wsl"` wrap the guard in the matching IS_WSL test
#   - `gate: { hostSuffix: "@..." }` wraps the guard in a `hostname -f` test,
#     with the @-ref resolved (mechanism only — the resolved value comes from
#     the temp source's empty-string defaults, so we don't assert on it)
#   - the Task 7 bare-`{}` case still emits a plain `if have NAME; then` guard
#     (no regression from the gate/env-aware rewrite)
#   - the emitted deps.sh is syntax-clean under bash (and zsh, where available)
#
# Split into a bash-only section and a zsh-only section, mirroring
# tests/test-core-lib.sh and tests/test-resolver-skeleton.sh: zsh is
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

  # --- env: fixture: a plain literal value under env: ---
  deps_env="$(render_fixture '{ packages: { brew: { k9s: { env: { K9S_FEATURE_GATE_NODE_SHELL: "true" } } } } }')"

  rc=0
  grep -q 'export K9S_FEATURE_GATE_NODE_SHELL="true"' "$deps_env" || rc=$?
  check "env: literal value emitted as export" "$rc"

  # Must sit INSIDE the have-guard for k9s, not before/after it.
  rc=0
  awk '/if have k9s/{g=1} g&&/K9S_FEATURE_GATE_NODE_SHELL/{f=1} /^else /{g=0} END{exit f?0:1}' "$deps_env" || rc=$?
  check "env: export sits inside the have-guard" "$rc"

  bash -n "$deps_env"
  rc=0
  bash -n "$deps_env" || rc=$?
  check "env fixture: bash -n clean" "$rc"

  # --- gate: "!wsl" fixture ---
  deps_notwsl="$(render_fixture '{ packages: { brew: { onlyLinux: { gate: "!wsl" } } } }')"

  rc=0
  # Gate is an OUTER skip-wrapper: `if <gate>; then` on its own line (not `gate && have`).
  grep -q '\[ "\${IS_WSL:-0}" != "1" \]; then' "$deps_notwsl" || rc=$?
  check "gate !wsl emits IS_WSL != 1 outer guard" "$rc"

  rc=0
  bash -n "$deps_notwsl" || rc=$?
  check "gate !wsl fixture: bash -n clean" "$rc"

  # --- gate: "wsl" fixture ---
  deps_wsl="$(render_fixture '{ packages: { brew: { onlyWsl: { gate: "wsl" } } } }')"

  rc=0
  grep -q '\[ "\${IS_WSL:-0}" = "1" \]; then' "$deps_wsl" || rc=$?
  check "gate wsl emits IS_WSL = 1 outer guard" "$rc"

  rc=0
  bash -n "$deps_wsl" || rc=$?
  check "gate wsl fixture: bash -n clean" "$rc"

  # --- gate: { hostSuffix: "@..." } fixture ---
  deps_host="$(render_fixture '{ packages: { brew: { gitlabTool: { gate: { hostSuffix: "@linux.work.host" } } } } }')"

  rc=0
  grep -q 'hostname -f' "$deps_host" || rc=$?
  check "gate hostSuffix emits hostname -f check" "$rc"

  rc=0
  grep -q '==' "$deps_host" || rc=$?
  check "gate hostSuffix emits == comparison" "$rc"

  rc=0
  grep -q 'have gitlabTool' "$deps_host" || rc=$?
  check "gate hostSuffix guard still checks have" "$rc"

  rc=0
  bash -n "$deps_host" || rc=$?
  check "gate hostSuffix fixture: bash -n clean" "$rc"

  # --- Task 7 regression: bare `{}` still emits a plain have-guard ---
  deps_bare="$(render_fixture '{ packages: { brew: { jq: {} } } }')"

  rc=0
  grep -q 'if have jq; then' "$deps_bare" || rc=$?
  check "bare {} still emits plain have-guard (no regression)" "$rc"

  rc=0
  bash -n "$deps_bare" || rc=$?
  check "bare fixture: bash -n clean" "$rc"

  # Stash paths for the zsh section.
  DEPS_ENV_PATH="$deps_env"
  DEPS_NOTWSL_PATH="$deps_notwsl"
  DEPS_WSL_PATH="$deps_wsl"
  DEPS_HOST_PATH="$deps_host"
  DEPS_BARE_PATH="$deps_bare"
}

run_zsh_tests() {
  echo "--- zsh section ---"

  if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: zsh not found on this machine — cannot verify zsh -n here" \
      "(controller runs this script under WSL to exercise this leg)"
    return 0
  fi

  for pair in "env:$DEPS_ENV_PATH" "notwsl:$DEPS_NOTWSL_PATH" "wsl:$DEPS_WSL_PATH" "host:$DEPS_HOST_PATH" "bare:$DEPS_BARE_PATH"; do
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
