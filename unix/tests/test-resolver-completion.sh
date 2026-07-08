#!/usr/bin/env bash
# Test for run_onchange_resolve-deps.sh.tmpl — the completion: extension (Task 11).
#
# Renders the resolver against fixture manifests via tests/lib/render-resolver.sh
# (a REAL sandboxed `chezmoi apply` — see that script's header for why) and
# asserts:
#   - a `completion: "<cmd> [args...]"` scalar emits a
#     `cache_completion <name> <cmd> [args...]` line *inside* the tool's
#     have-guard (not before/after it), mirroring how test-resolver-aliases
#     asserts `alias` placement for `aliases:`
#   - a multi-word completion command word-splits correctly at emit time
#     (the emitted words are unquoted so the shell does the splitting)
#   - the emitted deps.sh is syntax-clean under bash (and zsh, where available)
#   - the Task 7/8/9/10 bare-`{}` case still emits no `cache_completion` line
#     (no regression from the completion-aware rewrite)
#
# Split into a bash-only section and a zsh-only section, mirroring
# tests/test-resolver-aliases.sh: zsh is unavailable in git-bash on this
# machine, so run_zsh_tests SKIPs there instead of failing; the controller
# runs this same script under WSL to exercise the zsh -n leg.
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

  # --- completion: fixture: single-flag command (name == first word) ---
  deps_fzf="$(render_fixture '{ packages: { brew: { fzf: { completion: "fzf --zsh" } } } }')"

  rc=0
  grep -q 'cache_completion fzf fzf --zsh' "$deps_fzf" || rc=$?
  check "completion: 'fzf --zsh' emitted as cache_completion fzf fzf --zsh" "$rc"

  # Must sit INSIDE the have-guard for fzf, not before/after it (same awk
  # state-machine test-resolver-env/-path/-aliases use for placement).
  rc=0
  awk '/if have fzf/{g=1} g&&/cache_completion fzf fzf --zsh/{f=1} /^else /{g=0} END{exit f?0:1}' "$deps_fzf" || rc=$?
  check "completion: cache_completion line sits inside the have-guard" "$rc"

  rc=0
  bash -n "$deps_fzf" || rc=$?
  check "fzf fixture: bash -n clean" "$rc"

  # --- multi-word fixture: name differs from... well here name == first word
  # too, but the command has more args than the fzf case (three words) ---
  deps_k9s="$(render_fixture '{ packages: { brew: { k9s: { completion: "k9s completion zsh" } } } }')"

  rc=0
  grep -q 'cache_completion k9s k9s completion zsh' "$deps_k9s" || rc=$?
  check "completion: 'k9s completion zsh' emitted as cache_completion k9s k9s completion zsh" "$rc"

  rc=0
  awk '/if have k9s/{g=1} g&&/cache_completion k9s k9s completion zsh/{f=1} /^else /{g=0} END{exit f?0:1}' "$deps_k9s" || rc=$?
  check "completion: multi-word cache_completion line sits inside the have-guard" "$rc"

  rc=0
  bash -n "$deps_k9s" || rc=$?
  check "k9s fixture: bash -n clean" "$rc"

  # --- Task 7/8/9/10 regression: bare `{}` still emits no completion line ---
  deps_bare="$(render_fixture '{ packages: { brew: { jq: {} } } }')"

  rc=0
  grep -q 'if have jq; then' "$deps_bare" || rc=$?
  check "bare {} still emits plain have-guard (no regression)" "$rc"

  rc=0
  grep -q 'cache_completion' "$deps_bare" && rc=1 || rc=0
  check "bare {} emits no cache_completion lines" "$rc"

  rc=0
  bash -n "$deps_bare" || rc=$?
  check "bare fixture: bash -n clean" "$rc"

  # Stash paths for the zsh section.
  DEPS_FZF_PATH="$deps_fzf"
  DEPS_K9S_PATH="$deps_k9s"
  DEPS_BARE_PATH="$deps_bare"
}

run_zsh_tests() {
  echo "--- zsh section ---"

  if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: zsh not found on this machine — cannot verify zsh -n here" \
      "(controller runs this script under WSL to exercise this leg)"
    return 0
  fi

  for pair in "fzf:$DEPS_FZF_PATH" "k9s:$DEPS_K9S_PATH" "bare:$DEPS_BARE_PATH"; do
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
