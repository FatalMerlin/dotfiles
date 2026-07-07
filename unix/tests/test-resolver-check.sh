#!/usr/bin/env bash
# Test for run_onchange_resolve-deps.sh.tmpl — the `check:` presence-detection
# variants (Task 12).
#
# `check` selects the guard PREDICATE substituted for the historically
# hardcoded `have <name>`: default/"command" -> `have <name>`; "dpkg" ->
# `dpkg -s <package|name> >/dev/null 2>&1`; "file:<path>" -> `[ -e "<path>" ]`;
# "custom:<hook>" -> `<hook>` verbatim (a function from setup-hooks.sh,
# expected to return 0/1). The predicate is computed once and substituted
# into ALL FOUR gate branches (hostSuffix / !wsl / wsl / else), so gate and
# check compose. `source`/`package` are consumed by the install plan (a later
# task) and must not leak into the emitted deps.sh — `package` is used ONLY
# to build the dpkg predicate here, never emitted verbatim.
#
# Renders the resolver against fixture manifests via tests/lib/render-resolver.sh
# (real `chezmoi apply` into a sandboxed HOME — see that file's header for why).
#
# Split into a bash-only section (content assertions + bash -n) and a zsh-only
# section (zsh -n), mirroring tests/test-resolver-skeleton.sh and
# tests/test-resolver-env.sh: zsh is unavailable in git-bash on this machine,
# so run_zsh_tests SKIPs there instead of failing; the controller runs this
# same script under WSL to exercise the zsh -n leg.
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

  # --- 1. default (no check) -> plain have-guard (Task 7 regression) ---
  deps_default="$(render_fixture '{ packages: { brew: { jq: {} } } }')"

  rc=0
  grep -q 'if have jq; then' "$deps_default" || rc=$?
  check "default (no check): plain have-guard" "$rc"

  rc=0
  bash -n "$deps_default" || rc=$?
  check "default fixture: bash -n clean" "$rc"

  # --- 2. check: "dpkg" (no package override -> uses name) ---
  deps_dpkg="$(render_fixture '{ packages: { apt: { "build-essential": { check: "dpkg" } } } }')"

  rc=0
  grep -q 'if dpkg -s build-essential >/dev/null 2>&1; then' "$deps_dpkg" || rc=$?
  check "check: dpkg emits dpkg -s guard" "$rc"

  rc=0
  bash -n "$deps_dpkg" || rc=$?
  check "check: dpkg fixture: bash -n clean" "$rc"

  # --- 3. check: "dpkg" + package override ---
  deps_dpkg_pkg="$(render_fixture '{ packages: { apt: { column: { check: "dpkg", package: "bsdextrautils" } } } }')"

  rc=0
  grep -q 'if dpkg -s bsdextrautils >/dev/null 2>&1; then' "$deps_dpkg_pkg" || rc=$?
  check "check: dpkg + package uses package override in predicate" "$rc"

  rc=0
  grep -q 'dpkg -s column' "$deps_dpkg_pkg" && rc=1 || rc=0
  check "check: dpkg + package: tool name NOT used as dpkg package" "$rc"

  # dep_mark_missing must still be keyed on the tool NAME, not the package.
  rc=0
  grep -q 'dep_mark_missing column' "$deps_dpkg_pkg" || rc=$?
  check "check: dpkg + package: dep_mark_missing keyed on tool name" "$rc"

  rc=0
  bash -n "$deps_dpkg_pkg" || rc=$?
  check "check: dpkg + package fixture: bash -n clean" "$rc"

  # --- 4. check: "file:<path>" ---
  deps_file="$(render_fixture '{ packages: { brew: { fooTool: { check: "file:/opt/foo/bin/foo" } } } }')"

  rc=0
  grep -q 'if \[ -e "/opt/foo/bin/foo" \]; then' "$deps_file" || rc=$?
  check "check: file emits [ -e \"<path>\" ] guard" "$rc"

  rc=0
  bash -n "$deps_file" || rc=$?
  check "check: file fixture: bash -n clean" "$rc"

  # --- 5. check: "custom:<hook>" ---
  deps_custom="$(render_fixture '{ packages: { brew: { hookedTool: { check: "custom:my_hook" } } } }')"

  rc=0
  grep -q 'if my_hook; then' "$deps_custom" || rc=$?
  check "check: custom emits hook function call verbatim" "$rc"

  rc=0
  bash -n "$deps_custom" || rc=$?
  check "check: custom fixture: bash -n clean" "$rc"

  # --- 6. check + gate compose: gate "!wsl" + check "dpkg" ---
  deps_compose="$(render_fixture '{ packages: { apt: { "binfmt-support": { gate: "!wsl", check: "dpkg" } } } }')"

  rc=0
  grep -q '\[ "\${IS_WSL:-0}" != "1" \]' "$deps_compose" || rc=$?
  check "gate+check compose: IS_WSL != 1 test present" "$rc"

  rc=0
  grep -q 'dpkg -s binfmt-support >/dev/null 2>&1' "$deps_compose" || rc=$?
  check "gate+check compose: dpkg predicate present" "$rc"

  # Gate is an OUTER skip-wrapper: the IS_WSL test and the dpkg predicate are on
  # SEPARATE lines (outer `if <gate>; then` wrapping inner `if <pred>; then`), so a
  # gated-out tool is skipped rather than marked missing.
  rc=0
  grep -q '\[ "\${IS_WSL:-0}" != "1" \]; then' "$deps_compose" || rc=$?
  check "gate+check compose: gate emitted as outer wrapper" "$rc"

  rc=0
  bash -n "$deps_compose" || rc=$?
  check "gate+check compose fixture: bash -n clean" "$rc"

  # --- 7. source/package don't leak into deps.sh ---
  deps_source="$(render_fixture '{ packages: { brew: { op: { source: "1password-cli" } } } }')"

  rc=0
  grep -q '1password-cli' "$deps_source" && rc=1 || rc=0
  check "source: field value does not leak into deps.sh" "$rc"

  # NB: the resolver's own generated-file banner legitimately contains the
  # word "Source" ("do not edit. Source only."), so this asserts the *field
  # name/key* `source:` never appears verbatim, not the substring "source"
  # anywhere in the file.
  rc=0
  grep -q '^source:' "$deps_source" && rc=1 || rc=0
  check "the source: field key does not leak into deps.sh" "$rc"

  rc=0
  grep -q 'if have op; then' "$deps_source" || rc=$?
  check "source-only fixture still emits plain have-guard" "$rc"

  rc=0
  bash -n "$deps_source" || rc=$?
  check "source fixture: bash -n clean" "$rc"

  # --- 8. regression: env/path/alias/completion still work with default check ---
  deps_regress="$(render_fixture '{ packages: { brew: { k9s: { env: { K9S_FEATURE_GATE_NODE_SHELL: "true" } } } } }')"

  rc=0
  grep -q 'export K9S_FEATURE_GATE_NODE_SHELL="true"' "$deps_regress" || rc=$?
  check "regression: env: export still emitted with default check" "$rc"

  rc=0
  grep -q 'if have k9s; then' "$deps_regress" || rc=$?
  check "regression: default check still plain have-guard alongside env:" "$rc"

  rc=0
  bash -n "$deps_regress" || rc=$?
  check "regression fixture: bash -n clean" "$rc"

  # Stash paths for the zsh section.
  DEPS_DEFAULT_PATH="$deps_default"
  DEPS_DPKG_PATH="$deps_dpkg"
  DEPS_DPKG_PKG_PATH="$deps_dpkg_pkg"
  DEPS_FILE_PATH="$deps_file"
  DEPS_CUSTOM_PATH="$deps_custom"
  DEPS_COMPOSE_PATH="$deps_compose"
  DEPS_SOURCE_PATH="$deps_source"
  DEPS_REGRESS_PATH="$deps_regress"
}

run_zsh_tests() {
  echo "--- zsh section ---"

  if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: zsh not found on this machine — cannot verify zsh -n here" \
      "(controller runs this script under WSL to exercise this leg)"
    return 0
  fi

  for pair in \
    "default:$DEPS_DEFAULT_PATH" \
    "dpkg:$DEPS_DPKG_PATH" \
    "dpkg_pkg:$DEPS_DPKG_PKG_PATH" \
    "file:$DEPS_FILE_PATH" \
    "custom:$DEPS_CUSTOM_PATH" \
    "compose:$DEPS_COMPOSE_PATH" \
    "source:$DEPS_SOURCE_PATH" \
    "regress:$DEPS_REGRESS_PATH"; do
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
