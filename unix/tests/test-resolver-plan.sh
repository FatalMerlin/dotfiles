#!/usr/bin/env bash
# Test for run_onchange_resolve-deps.sh.tmpl — install-plan.sh emission (Task 20a).
#
# The resolver's rendered bash writes a SECOND output file alongside deps.sh:
# install-plan.sh, a flat topologically-sorted (needs-before-dependent) table of
# every manifest tool: `<name>\t<manager>\t<source-or-install-command>`. It is
# consumed later by the on-demand provisioner (`im`, a separate later task) —
# this test only proves the resolver emits it correctly.
#
# The topo-sort (Kahn's algorithm) runs in the EMITTED bash at apply-time, not
# at chezmoi-template-render time, because `needs:` edges can cross manager
# boundaries (e.g. brew's `helm` needs brew's `kubectl`; cargo's `sccache`
# needs apt's `libssl-dev`/`pkg-config`) and the sort has to see the whole
# manifest graph as one flat node set regardless of which manager map a key
# lives under.
#
# Renders the resolver against fixture manifests via tests/lib/render-resolver.sh
# (real `chezmoi apply` into a sandboxed HOME — see that file's header for why).
# install-plan.sh is a sibling of the returned deps.sh path.
#
# Mechanics note: every grep-based assertion uses the crash-proof pattern
# `rc=0; cmd || rc=$?; check "name" "$rc"` rather than `cmd; check "$?"` —
# under `set -e`, a failing command as its own statement would abort this
# script before `check` ever runs and reports FAIL; guarding it behind `||`
# keeps the failure visible as a reported FAIL instead of a silent crash.
#
# A cyclic manifest (a needs b, b needs a) is an author bug: the resolver must
# hard-fail (non-zero exit) at apply-time, naming the offending keys on
# stderr. NOTE: this fatality is scoped to plan emission / cycle detection
# only — actual package INSTALLATION (added later, in the `im` provisioner
# task) is non-fatal per-tool by design; that is a separate concern.
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
  # Echoes the deps.sh path; install-plan.sh is a sibling (same dir).
  fixture="$(mktemp)"
  printf '%s\n' "$1" > "$fixture"
  bash "$HERE/lib/render-resolver.sh" "$fixture"
}

run_bash_tests() {
  echo "--- bash section ---"

  # --- 1. topo order: a needs b -> b's row precedes a's row ---
  deps1="$(render_fixture '{ packages: { brew: { a: { needs: ["b"] }, b: {} } } }')"
  plan1="$(dirname "$deps1")/install-plan.sh"

  rc=0
  [ -f "$plan1" ] || rc=1
  check "install-plan.sh written as a sibling of deps.sh" "$rc"

  rc=0
  grep -q $'^b\tbrew\tb$' "$plan1" || rc=$?
  check "topo: row for b present (name=b mgr=brew src=b, default source=name)" "$rc"

  rc=0
  grep -q $'^a\tbrew\ta$' "$plan1" || rc=$?
  check "topo: row for a present (name=a mgr=brew src=a, default source=name)" "$rc"

  b_line=$(grep -n $'^b\tbrew\tb$' "$plan1" | head -1 | cut -d: -f1)
  a_line=$(grep -n $'^a\tbrew\ta$' "$plan1" | head -1 | cut -d: -f1)
  rc=0
  [ -n "$b_line" ] && [ -n "$a_line" ] && [ "$b_line" -lt "$a_line" ] || rc=1
  check "topo: b's line ($b_line) precedes a's line ($a_line) — needs-before-dependent" "$rc"

  rc=0
  bash -n "$deps1" || rc=$?
  check "topo fixture: rendered resolver bash -n clean" "$rc"

  # --- 2. cross-manager + multi-need determinism: x needs [y,z] ---
  multi_manifest='{ packages: { brew: { x: { needs: ["y", "z"] } }, cargo: { y: {}, z: {} } } }'
  deps2a="$(render_fixture "$multi_manifest")"
  plan2a="$(dirname "$deps2a")/install-plan.sh"

  x_line=$(grep -n $'^x\tbrew\tx$' "$plan2a" | head -1 | cut -d: -f1)
  y_line=$(grep -n $'^y\tcargo\ty$' "$plan2a" | head -1 | cut -d: -f1)
  z_line=$(grep -n $'^z\tcargo\tz$' "$plan2a" | head -1 | cut -d: -f1)

  rc=0
  [ -n "$x_line" ] && [ -n "$y_line" ] && [ -n "$z_line" ] || rc=1
  check "multi-need: rows for x, y, z all present" "$rc"

  rc=0
  [ "$y_line" -lt "$x_line" ] && [ "$z_line" -lt "$x_line" ] || rc=1
  check "multi-need: both y and z precede x (cross-manager edges honoured)" "$rc"

  # Determinism: render again from a fresh fixture file with identical content;
  # the two install-plan.sh outputs must be byte-identical (stable node-name
  # sort within a topo level -> run_onchange doesn't needlessly re-fire).
  deps2b="$(render_fixture "$multi_manifest")"
  plan2b="$(dirname "$deps2b")/install-plan.sh"

  rc=0
  diff -q "$plan2a" "$plan2b" >/dev/null || rc=$?
  check "multi-need: install-plan.sh is byte-stable across repeated renders" "$rc"

  # --- 3. row format: brew `source:` override + custom install command verbatim ---
  row_manifest='{ packages: { brew: { http: { source: "httpie" } }, custom: { foo: { source: "custom", install: "echo hi | cat" } } } }'
  deps3="$(render_fixture "$row_manifest")"
  plan3="$(dirname "$deps3")/install-plan.sh"

  rc=0
  grep -q $'^http\tbrew\thttpie$' "$plan3" || rc=$?
  check "row format: http row uses source: override (http, brew, httpie)" "$rc"

  rc=0
  grep -q $'^foo\tcustom\techo hi | cat$' "$plan3" || rc=$?
  check "row format: custom foo row preserves install command verbatim, incl. pipe (foo, custom, echo hi | cat)" "$rc"

  rc=0
  grep -q '^# GENERATED' "$plan3" || rc=$?
  check "install-plan.sh has a GENERATED banner" "$rc"

  rc=0
  grep -q '^# format:' "$plan3" || rc=$?
  check "install-plan.sh documents its column format" "$rc"

  rc=0
  bash -n "$deps3" || rc=$?
  check "row-format fixture: rendered resolver bash -n clean" "$rc"

  # --- 4. cycle -> hard error naming both offending keys ---
  # render_fixture/render-resolver.sh runs `chezmoi apply` under `set -e`
  # (render-resolver.sh's own shebang), so a resolver exit 1 makes the
  # render-resolver.sh invocation itself fail non-zero. Capture that via
  # command substitution + `if`, mirroring the crash-proof capture pattern
  # used elsewhere in this test suite (test-harness.sh's require_args probe).
  cycle_fixture="$(mktemp)"
  printf '%s\n' '{ packages: { brew: { a: { needs: ["b"] }, b: { needs: ["a"] } } } }' > "$cycle_fixture"

  rc=0
  if out=$(bash "$HERE/lib/render-resolver.sh" "$cycle_fixture" 2>&1); then
    rc=1
    echo "note: expected render-resolver.sh to fail non-zero on a cyclic manifest, but it succeeded. Output: $out"
  fi
  check "cycle: render-resolver.sh (chezmoi apply) exits non-zero on a cyclic manifest" "$rc"

  rc=0
  printf '%s' "${out:-}" | grep -q '\ba\b' || rc=1
  check "cycle: error output names 'a'" "$rc"

  rc=0
  printf '%s' "${out:-}" | grep -q '\bb\b' || rc=1
  check "cycle: error output names 'b'" "$rc"

  # --- 5. deps.sh is unaffected by this additive change (regression) ---
  # dep_report_missing is NOT emitted into deps.sh (Task 20b moved the report
  # to dot_zshrc.tmpl, firing once after ALL sourcing — manifest deps.sh AND
  # the legacy dependencies/*.zsh bootstraps, which add to the same tally).
  # This assertion only proves install-plan.sh emission (this file's actual
  # subject) didn't reintroduce or otherwise disturb that removal.
  rc=0
  grep -q 'dep_report_missing' "$deps1" && rc=1
  check "regression: deps.sh does NOT contain dep_report_missing (report moved to startup)" "$rc"
}

main() {
  run_bash_tests
  exit "$fail"
}

main "$@"
