#!/usr/bin/env bash
# Test for run_onchange_resolve-deps.sh.tmpl — the setup: extension (Task 13).
#
# `setup:` is the named escape hatch for irreducible bespoke logic (spec
# §5.2): a manifest entry names a hook function defined in the new
# dot_config/dotfiles/hooks/setup-hooks.sh, and the resolver emits a call to
# it inside the tool's have-guard.
#
# Renders the resolver against fixture manifests via tests/lib/render-resolver.sh
# (a REAL sandboxed `chezmoi apply` — see that script's header for why) and
# asserts:
#   - the generated deps.sh unconditionally sources
#     hooks/setup-hooks.sh in its preamble, regardless of whether any entry
#     uses setup: (cheap because that file is function-defs only)
#   - `setup: "kubectl_krew"` emits a call to `kubectl_krew` *inside* the
#     tool's have-guard (not before/after it), mirroring how
#     test-resolver-completion asserts `cache_completion` placement
#   - the Task 7-12 bare-`{}` case still emits no hook call (no regression),
#     while still sourcing setup-hooks.sh in the preamble
#   - the emitted deps.sh is syntax-clean under bash (and zsh, where available)
#   - setup-hooks.sh itself is syntax-clean under bash (and zsh, where available)
#
# Split into a bash-only section and a zsh-only section, mirroring
# tests/test-resolver-completion.sh: zsh is unavailable in git-bash on this
# machine, so run_zsh_tests SKIPs there instead of failing; the controller
# runs this same script under WSL to exercise the zsh -n leg. shellcheck on
# setup-hooks.sh is deferred to the controller too.
#
# Mechanics note: every grep-based assertion uses the crash-proof pattern
# `rc=0; grep -q ... || rc=$?; check "name" "$rc"` rather than
# `grep -q ...; check "$?"` — under `set -e`, a failing `grep -q` inside the
# condition of `||` is safe, but a bare failing command as its own statement
# would abort the script before `check` ever runs and reports FAIL. This way
# a regression reports FAIL instead of silently crashing the test run.
set -eEuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOKS_FILE="$(cd "$HERE/../dot_config/dotfiles/hooks" && pwd)/setup-hooks.sh"

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

  # --- setup: fixture: kubectl -> kubectl_krew ---
  deps_kubectl="$(render_fixture '{ packages: { brew: { kubectl: { setup: "kubectl_krew" } } } }')"

  rc=0
  grep -q 'hooks/setup-hooks.sh' "$deps_kubectl" || rc=$?
  check "setup: preamble sources hooks/setup-hooks.sh" "$rc"

  rc=0
  grep -q '^  kubectl_krew$' "$deps_kubectl" || rc=$?
  check "setup: 'kubectl_krew' emitted as a call" "$rc"

  # Must sit INSIDE the have-guard for kubectl, not before/after it.
  rc=0
  awk '/if have kubectl/{g=1} g&&/^  kubectl_krew$/{f=1} /^else /{g=0} END{exit f?0:1}' "$deps_kubectl" || rc=$?
  check "setup: kubectl_krew call sits inside the have-guard" "$rc"

  rc=0
  bash -n "$deps_kubectl" || rc=$?
  check "kubectl fixture: bash -n clean" "$rc"

  # --- Task 7-12 regression: bare `{}` still emits no hook call, but the
  # preamble still unconditionally sources setup-hooks.sh ---
  deps_bare="$(render_fixture '{ packages: { brew: { jq: {} } } }')"

  rc=0
  grep -q 'hooks/setup-hooks.sh' "$deps_bare" || rc=$?
  check "bare {}: preamble still sources hooks/setup-hooks.sh (unconditional)" "$rc"

  rc=0
  grep -q 'if have jq; then' "$deps_bare" || rc=$?
  check "bare {} still emits plain have-guard (no regression)" "$rc"

  rc=0
  awk '/if have jq/{g=1} g&&/kubectl_krew/{f=1} /^else /{g=0} END{exit f?0:1}' "$deps_bare" && rc=1 || rc=0
  check "bare {} jq guard emits no hook call" "$rc"

  rc=0
  bash -n "$deps_bare" || rc=$?
  check "bare fixture: bash -n clean" "$rc"

  # --- setup-hooks.sh itself ---
  rc=0
  [ -f "$HOOKS_FILE" ] || rc=$?
  check "setup-hooks.sh exists" "$rc"

  rc=0
  bash -n "$HOOKS_FILE" || rc=$?
  check "setup-hooks.sh: bash -n clean" "$rc"

  # Stash paths for the zsh section.
  DEPS_KUBECTL_PATH="$deps_kubectl"
  DEPS_BARE_PATH="$deps_bare"
}

run_zsh_tests() {
  echo "--- zsh section ---"

  if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: zsh not found on this machine — cannot verify zsh -n here" \
      "(controller runs this script under WSL to exercise this leg)"
    return 0
  fi

  for pair in "kubectl:$DEPS_KUBECTL_PATH" "bare:$DEPS_BARE_PATH"; do
    name="${pair%%:*}"
    path="${pair#*:}"
    rc=0
    zsh -n "$path" || rc=$?
    check "zsh -n clean ($name)" "$rc"
  done

  rc=0
  zsh -n "$HOOKS_FILE" || rc=$?
  check "setup-hooks.sh: zsh -n clean" "$rc"
}

main() {
  run_bash_tests
  run_zsh_tests
  exit "$fail"
}

main "$@"
