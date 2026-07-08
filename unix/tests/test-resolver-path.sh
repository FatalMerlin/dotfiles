#!/usr/bin/env bash
# Test for run_onchange_resolve-deps.sh.tmpl — the path: extension (Task 9).
#
# Renders the resolver against fixture manifests via tests/lib/render-resolver.sh
# (a REAL sandboxed `chezmoi apply` — see that script's header for why) and
# asserts:
#   - a `path:` list emits `ifpath_append "<dir>"` per entry *inside* the
#     tool's have-guard (not before/after it), mirroring how test-resolver-env
#     asserts `export` placement for `env:`
#   - the emitted deps.sh is syntax-clean under bash (and zsh, where available)
#   - **open-Q5**: the emitted deps.sh, when actually SOURCED (not just
#     syntax-checked) with core.sh available and the tool faked present on
#     PATH, is source-clean and actually applies the `ifpath_append` under
#     BOTH bash and zsh — i.e. the flat guarded-code artifact (no assoc
#     arrays) behaves identically in both shells. This is the direct proof
#     requested by open-Q5 in the design doc.
#
# Split into a bash-only section and a zsh-only section, mirroring
# tests/test-core-lib.sh and tests/test-resolver-env.sh: zsh is unavailable in
# git-bash on this machine, so run_zsh_tests SKIPs there instead of failing;
# the controller runs this same script under WSL to exercise the zsh legs.
#
# Mechanics note: every grep-based assertion uses the crash-proof pattern
# `rc=0; grep -q ... || rc=$?; check "name" "$rc"` rather than
# `grep -q ...; check "$?"` — under `set -e`, a failing `grep -q` inside the
# condition of `||` is safe, but a bare failing command as its own statement
# would abort the script before `check` ever runs and reports FAIL. This way
# a regression reports FAIL instead of silently crashing the test run.
set -eEuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE_LIB="$(cd "$HERE/../dot_config/dotfiles/lib" && pwd)/core.sh"

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

# source_clean_leg SHELL DEPS_PATH FAKEBIN_DIR
# Sources the emitted deps.sh (with core.sh staged at the HOME it expects,
# and a fake `go` binary on PATH so `have go` is true) under the given shell,
# and echoes ":$PATH:" from that shell so the caller can assert both (a) exit
# 0 (source-clean — no unset-var/strict-mode blowups) and (b) the ifpath_append
# actually landed the directory in PATH.
source_clean_leg() {
  sh_bin="$1"; deps_path="$2"; fakebin="$3"
  h="$(mktemp -d)"
  mkdir -p "$h/.config/dotfiles/lib"
  cp "$CORE_LIB" "$h/.config/dotfiles/lib/core.sh"
  HOME="$h" PATH="$fakebin:$PATH" "$sh_bin" -c '. "'"$deps_path"'"; printf ":%s:" "$PATH"'
}

run_bash_tests() {
  echo "--- bash section ---"

  # --- path: fixture: a single literal dir under path: ---
  deps_path="$(render_fixture '{ packages: { brew: { go: { path: ["$HOME/go/bin"] } } } }')"

  rc=0
  grep -q 'ifpath_append "$HOME/go/bin"' "$deps_path" || rc=$?
  check "path: literal dir emitted as ifpath_append" "$rc"

  # Must sit INSIDE the have-guard for go, not before/after it (same
  # awk state-machine test-resolver-env uses for env: placement).
  rc=0
  awk '/if have go/{g=1} g&&/ifpath_append "\$HOME\/go\/bin"/{f=1} /^else /{g=0} END{exit f?0:1}' "$deps_path" || rc=$?
  check "path: ifpath_append sits inside the have-guard" "$rc"

  rc=0
  bash -n "$deps_path" || rc=$?
  check "path fixture: bash -n clean" "$rc"

  # --- Task 7/8 regression: bare `{}` still emits a plain have-guard ---
  deps_bare="$(render_fixture '{ packages: { brew: { jq: {} } } }')"

  rc=0
  grep -q 'if have jq; then' "$deps_bare" || rc=$?
  check "bare {} still emits plain have-guard (no regression)" "$rc"

  rc=0
  bash -n "$deps_bare" || rc=$?
  check "bare fixture: bash -n clean" "$rc"

  # --- open-Q5: fixture whose path dir REALLY EXISTS (/tmp), so sourcing the
  # emitted deps.sh under a real shell, with `go` faked present on PATH,
  # proves the guard fires AND ifpath_append actually mutates PATH. ---
  deps_q5="$(render_fixture '{ packages: { brew: { go: { path: ["/tmp"] } } } }')"

  rc=0
  grep -q 'ifpath_append "/tmp"' "$deps_q5" || rc=$?
  check "Q5 fixture: ifpath_append /tmp emitted" "$rc"

  fakebin="$(mktemp -d)"
  cat > "$fakebin/go" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod +x "$fakebin/go"

  rc=0
  out="$(source_clean_leg bash "$deps_q5" "$fakebin")" || rc=$?
  check "Q5: bash source-clean (exit 0)" "$rc"
  rc=0
  case "$out" in *":/tmp:"*) ;; *) rc=1 ;; esac
  check "Q5: bash sourcing actually applied ifpath_append (/tmp in PATH)" "$rc"

  # Stash paths for the zsh section.
  DEPS_PATH_PATH="$deps_path"
  DEPS_BARE_PATH="$deps_bare"
  DEPS_Q5_PATH="$deps_q5"
  FAKEBIN_PATH="$fakebin"
}

run_zsh_tests() {
  echo "--- zsh section ---"

  if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: zsh not found on this machine — cannot verify zsh -n / zsh" \
      "source-clean here (controller runs this script under WSL to exercise" \
      "this leg)"
    return 0
  fi

  for pair in "path:$DEPS_PATH_PATH" "bare:$DEPS_BARE_PATH" "q5:$DEPS_Q5_PATH"; do
    name="${pair%%:*}"
    path="${pair#*:}"
    rc=0
    zsh -n "$path" || rc=$?
    check "zsh -n clean ($name)" "$rc"
  done

  rc=0
  out="$(source_clean_leg zsh "$DEPS_Q5_PATH" "$FAKEBIN_PATH")" || rc=$?
  check "Q5: zsh source-clean (exit 0)" "$rc"
  rc=0
  case "$out" in *":/tmp:"*) ;; *) rc=1 ;; esac
  check "Q5: zsh sourcing actually applied ifpath_append (/tmp in PATH)" "$rc"
}

main() {
  run_bash_tests
  run_zsh_tests
  exit "$fail"
}

main "$@"
