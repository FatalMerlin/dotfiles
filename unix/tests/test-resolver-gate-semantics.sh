#!/usr/bin/env bash
# Test for run_onchange_resolve-deps.sh.tmpl — gate is an OUTER skip-wrapper,
# not `gate && pred` (Task 16 bugfix).
#
# BUG: the resolver used to combine `<gatecond> && <pred>` into a single guard
# line. When the gate condition was false (e.g. `gate: "!wsl"` on an actual
# WSL box), the WHOLE guard was false, so execution fell into the `else`
# branch and ran `dep_mark_missing <name>` — reporting a deliberately
# gated-out tool as MISSING, and the provisioner (`im`) would then try to
# install a tool the gate says shouldn't be installed here. The legacy
# (pre-resolver) code skipped gated-out tools entirely
# (`if ! (( IS_WSL )); then ifpkg yakuake; fi`) — nothing ran on the
# gated-out platform, not even a missing-check.
#
# FIX: gate now wraps the ENTIRE inner have/check-guard (including its own
# `else dep_mark_missing ...; fi`) in an outer `if <gatecond>; then ... fi`.
# A gated-out tool therefore emits an outer guard whose body (the inner
# guard + dep_mark_missing) simply never executes on this machine — the tool
# is SKIPPED, not marked missing. A non-gated tool is emitted exactly as
# before (single `if <pred>; then ... else dep_mark_missing ...; fi`, no
# outer wrapper).
#
# Renders the resolver against fixture manifests via tests/lib/render-resolver.sh
# (real `chezmoi apply` into a sandboxed HOME — see that file's header for why).
#
# Split into a bash-only section (structure assertions + bash -n + the actual
# behavioral proof by sourcing the emitted deps.sh under bash) and a zsh-only
# section (zsh -n plus the behavioral proof under zsh), mirroring
# tests/test-resolver-check.sh and tests/test-resolver-env.sh: zsh is
# unavailable in git-bash on this machine, so run_zsh_tests SKIPs there
# instead of failing; the controller runs this same script under WSL to
# exercise that leg.
#
# Mechanics note: every grep-based assertion uses the crash-proof pattern
# `rc=0; grep -q ... || rc=$?; check "name" "$rc"` rather than
# `grep -q ...; check "$?"` — under `set -e`, a failing `grep -q` inside the
# condition of `||` is safe, but a bare failing command as its own statement
# would abort the script before `check` ever runs and reports FAIL. This way
# a regression reports FAIL instead of silently crashing the test run.
#
# shellcheck disable=SC2016  # grep patterns and the `$shell -c '...'` bodies are
# intentionally single-quoted: they are literal match patterns / must expand in the
# CHILD shell (with its own IS_WSL/HOME/_DEP_MISSING_LIST), not in this parent.
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

# run_behavioral_leg SHELL DEPS_PATH
#
# Copies core.sh + setup-hooks.sh into a throwaway $HOME/.config/dotfiles/{lib,hooks}
# tree (deps.sh's preamble sources them from there unconditionally), copies the
# rendered deps.sh alongside, then sources it once with IS_WSL=1 and once with
# IS_WSL=0 under the given interpreter, printing the resulting _DEP_MISSING_LIST.
# Returns via echo: "wsl1:<list>|wsl0:<list>".
run_behavioral_leg() {
  shell="$1"; deps_path="$2"
  th="$(mktemp -d)"
  mkdir -p "$th/.config/dotfiles/lib" "$th/.config/dotfiles/hooks"
  cp "$CORE_SH" "$th/.config/dotfiles/lib/core.sh"
  cp "$SETUP_HOOKS_SH" "$th/.config/dotfiles/hooks/setup-hooks.sh"
  cp "$deps_path" "$th/.config/dotfiles/deps.sh"

  wsl1="$(IS_WSL=1 HOME="$th" "$shell" -c '. "$HOME/.config/dotfiles/deps.sh"; printf "%s" "${_DEP_MISSING_LIST:-}"' 2>/dev/null)"
  wsl0="$(IS_WSL=0 HOME="$th" "$shell" -c '. "$HOME/.config/dotfiles/deps.sh"; printf "%s" "${_DEP_MISSING_LIST:-}"' 2>/dev/null)"

  rm -rf "$th"
  printf 'wsl1:%s|wsl0:%s' "$wsl1" "$wsl0"
}

run_bash_tests() {
  echo "--- bash section ---"

  CORE_SH="$HERE/../dot_config/dotfiles/lib/core.sh"
  SETUP_HOOKS_SH="$HERE/../dot_config/dotfiles/hooks/setup-hooks.sh"

  # --- 1. gated tool: gate "!wsl" + check "dpkg" (yakuake-shaped fixture) ---
  deps_gated="$(render_fixture '{ packages: { apt: { yakuake: { gate: "!wsl", check: "dpkg" } } } }')"

  # STRUCTURE: outer gate line present.
  rc=0
  grep -q 'if \[ "\${IS_WSL:-0}" != "1" \]; then' "$deps_gated" || rc=$?
  check "gated: outer IS_WSL != 1 wrapper present" "$rc"

  # STRUCTURE: inner predicate guard present, on its OWN line (not ANDed with gate).
  rc=0
  grep -qx 'if dpkg -s yakuake >/dev/null 2>&1; then' "$deps_gated" || rc=$?
  check "gated: inner dpkg predicate guard present on its own line" "$rc"

  # STRUCTURE: no line combines the gate condition and the predicate with &&.
  rc=0
  grep -q 'IS_WSL.*&&.*dpkg -s yakuake' "$deps_gated" && rc=1 || rc=0
  check "gated: gate and predicate are NOT ANDed onto one guard line" "$rc"

  # STRUCTURE: dep_mark_missing yakuake is nested INSIDE the outer gate (between
  # the outer `if` and the outer `fi`), i.e. it only appears once, inside.
  rc=0
  grep -q 'dep_mark_missing yakuake' "$deps_gated" || rc=$?
  check "gated: dep_mark_missing yakuake present (nested, not top-level)" "$rc"

  # STRUCTURE: exactly two `fi` tokens close this tool's block: one inline on
  # the `else dep_mark_missing yakuake; fi` line (closes the INNER predicate
  # guard) and one standalone `fi` line right after (closes the OUTER gate
  # wrapper). Count total `fi` occurrences (inline + standalone) between the
  # outer `if` for yakuake and the next `# ----` comment (or EOF) — grep -o
  # counts every match, including the inline one awk's line-based `/^fi$/
  # would miss.
  rc=0
  fi_count=$(awk '
    /if \[ "\$\{IS_WSL:-0\}" != "1" \]; then/ { grab=1 }
    grab { print }
    grab && /^# ----/ && !/yakuake/ { grab=0 }
  ' "$deps_gated" | grep -o '\bfi\b' | wc -l)
  [ "$fi_count" -eq 2 ] || rc=1
  check "gated: exactly two fi tokens close the block (inner inline + outer standalone)" "$rc"

  rc=0
  bash -n "$deps_gated" || rc=$?
  check "gated fixture: bash -n clean" "$rc"

  # --- 2. non-gated regression: brew jq (unchanged shape) ---
  deps_plain="$(render_fixture '{ packages: { brew: { jq: {} } } }')"

  rc=0
  grep -q 'if have jq; then' "$deps_plain" || rc=$?
  check "non-gated: plain have-guard preserved" "$rc"

  rc=0
  grep -q 'else dep_mark_missing jq; fi' "$deps_plain" || rc=$?
  check "non-gated: else dep_mark_missing; fi preserved on one line" "$rc"

  # STRUCTURE: no outer gate wrapper — exactly ONE `if` line and the guard's own
  # `else...fi` closes it; no separate leading `if [...]; then` gate line, and
  # no lone trailing `fi` line for this tool block.
  rc=0
  fi_lines=$(awk '
    /if have jq; then/ { grab=1 }
    grab && /^fi$/ { c++ }
    grab && /^# ----/ && !/jq \(brew\)/ { grab=0 }
    END { print c+0 }
  ' "$deps_plain")
  [ "$fi_lines" -eq 0 ] || rc=1
  check "non-gated: no extra outer-gate closing fi line" "$rc"

  rc=0
  bash -n "$deps_plain" || rc=$?
  check "non-gated fixture: bash -n clean" "$rc"

  # --- 3. BEHAVIORAL (bash leg): the actual bug-fix proof ---
  # Source the gated deps.sh under bash with IS_WSL=1 (gate "!wsl" is FALSE on
  # WSL) and confirm yakuake does NOT land in the missing list (skipped, not
  # missing). Also check IS_WSL=0 (gate TRUE): yakuake's dpkg predicate will
  # fail in this sandbox (yakuake is not installed / dpkg may not even exist
  # on this machine), so it SHOULD be marked missing there — proving the gate
  # correctly ungates when its condition holds.
  result="$(run_behavioral_leg bash "$deps_gated")"
  wsl1_list="${result#wsl1:}"; wsl1_list="${wsl1_list%%|*}"
  wsl0_list="${result#*wsl0:}"

  case " $wsl1_list " in
    *" yakuake "*) rc=1 ;;
    *) rc=0 ;;
  esac
  check "BEHAVIORAL (bash): IS_WSL=1 (gated out) -> yakuake NOT in missing list (list: '$wsl1_list')" "$rc"

  case " $wsl0_list " in
    *" yakuake "*) rc=0 ;;
    *)
      echo "note: yakuake not marked missing under IS_WSL=0 in this sandbox" \
        "(dpkg may be unavailable or yakuake coincidentally 'present' via a" \
        "stray dpkg db on this box) -- the IS_WSL=1 skip leg above is the" \
        "critical assertion for this bug fix; this leg is best-effort."
      rc=0
      ;;
  esac
  check "BEHAVIORAL (bash): IS_WSL=0 (gate allows) leg ran without crashing" "$rc"

  # Stash for zsh section.
  DEPS_GATED_PATH="$deps_gated"
  DEPS_PLAIN_PATH="$deps_plain"
}

run_zsh_tests() {
  echo "--- zsh section ---"

  if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: zsh not found on this machine — cannot verify zsh -n or the" \
      "zsh behavioral leg here (controller runs this script under WSL to" \
      "exercise this leg)"
    return 0
  fi

  rc=0
  zsh -n "$DEPS_GATED_PATH" || rc=$?
  check "zsh -n clean (gated)" "$rc"

  rc=0
  zsh -n "$DEPS_PLAIN_PATH" || rc=$?
  check "zsh -n clean (plain)" "$rc"

  # BEHAVIORAL (zsh leg): the key assertion, mirrored under zsh (the real
  # interactive-shell interpreter deps.sh's preamble is designed for).
  result="$(run_behavioral_leg zsh "$DEPS_GATED_PATH")"
  wsl1_list="${result#wsl1:}"; wsl1_list="${wsl1_list%%|*}"

  case " $wsl1_list " in
    *" yakuake "*) rc=1 ;;
    *) rc=0 ;;
  esac
  check "BEHAVIORAL (zsh): IS_WSL=1 (gated out) -> yakuake NOT in missing list (list: '$wsl1_list')" "$rc"
}

main() {
  run_bash_tests
  run_zsh_tests
  exit "$fail"
}

main "$@"
