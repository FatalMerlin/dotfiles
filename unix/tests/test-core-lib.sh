#!/usr/bin/env bash
# Test for lib/core.sh — the POSIX core library sourced by interactive shells,
# the apply-time resolver, the provisioner, and standalone scripts.
#
# Split into a bash-only section and a zsh-only section (each independently
# runnable/reportable): CI or a dev machine may lack zsh, so `run_bash_tests`
# and `run_zsh_tests` can be invoked separately. `main` runs both when present.
#
# Mechanics note: `$?` is captured into a variable *immediately* after the
# command that sets it, never read after a helper/function call (which would
# reset it) — see `rc=$?` idiom below. `check()` takes a pre-computed truthy
# result (0/1), not an `eval`'d expression string.
set -eEuo pipefail
LIB="$(cd "$(dirname "$0")/../dot_config/dotfiles/lib" && pwd)/core.sh"

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

run_bash_tests() {
  echo "--- bash section ---"

  # Source-clean under bash: sourcing must not exit the shell, and have(sh) is true.
  bash -c ". '$LIB'; have sh"
  rc=$?
  check "bash: sources + have(sh) true" "$rc"

  # have() is false for a bogus command. (`|| rc=$?` so our own `set -e`
  # doesn't abort on this intentionally-nonzero probe; rc is captured
  # immediately, before any helper call can reset $?.)
  rc=0
  bash -c ". '$LIB'; have __definitely_not_a_cmd__" || rc=$?
  check "have(nope) false" "$([ "$rc" -ne 0 ]; echo $?)"

  # ifpath_append only adds existing dirs, and is idempotent.
  out=$(bash -c ". '$LIB'; PATH=/usr/bin; ifpath_append /usr/bin; ifpath_append /nope; echo \"\$PATH\"")
  check "ifpath idempotent + guards missing" "$([ "$out" = "/usr/bin" ]; echo $?)"

  # ifpath_prepend puts the dir first, and is idempotent too. (Uses /usr/bin
  # itself as the guaranteed-existing probe dir since /usr/local/bin doesn't
  # exist in every environment, e.g. git-bash on Windows.)
  out=$(bash -c ". '$LIB'; PATH=/tmp; ifpath_prepend /usr/bin; ifpath_prepend /usr/bin; echo \"\$PATH\"")
  check "ifpath_prepend idempotent + prepends" "$([ "$out" = "/usr/bin:/tmp" ]; echo $?)"

  # ifpath (the ifpath_append alias) is a no-op for a missing dir.
  out=$(bash -c ". '$LIB'; PATH=/usr/bin; ifpath /nope; echo \"\$PATH\"")
  check "ifpath no-ops on missing dir" "$([ "$out" = "/usr/bin" ]; echo $?)"

  # missing tally: count + space-joined list.
  out=$(bash -c ". '$LIB'; dep_reset_missing; dep_mark_missing foo; dep_mark_missing bar; echo \"\$_DEP_MISSING_COUNT:\$_DEP_MISSING_LIST\"")
  check "tally counts + lists" "$([ "$out" = "2:foo bar" ]; echo $?)"

  # dep_report_missing is silent when nothing is missing.
  out=$(bash -c ". '$LIB'; dep_reset_missing; dep_report_missing" 2>&1)
  check "dep_report_missing silent when clean" "$([ -z "$out" ]; echo $?)"

  # dep_report_missing reports a count + the list when something is missing.
  out=$(bash -c ". '$LIB'; dep_reset_missing; dep_mark_missing foo; dep_report_missing" 2>&1)
  case "$out" in
    *"1 declared tool(s) missing"*"foo"*) check "dep_report_missing reports missing" 0 ;;
    *) check "dep_report_missing reports missing" 1 ;;
  esac

  # Sourcing does NOT enable set -e (interactive-safe): a failing cmd after
  # source must not kill the shell.
  out=$(bash -c ". '$LIB'; false; echo survived")
  check "no set -e leak (bash)" "$([ "$out" = "survived" ]; echo $?)"

  # NO_COLOR is honoured: no escape sequences leak into log output.
  out=$(bash -c "NO_COLOR=1 . '$LIB'; info hi" 2>&1)
  case "$out" in
    *$'\033'*) check "NO_COLOR suppresses escapes" 1 ;;
    *) check "NO_COLOR suppresses escapes" 0 ;;
  esac
}

run_zsh_tests() {
  echo "--- zsh section ---"

  if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: zsh not found on this machine — cannot verify zsh source-clean cases here"
    return 0
  fi

  zsh -c ". '$LIB'; have sh"
  rc=$?
  check "zsh: sources + have(sh) true" "$rc"

  out=$(zsh -c ". '$LIB'; false; echo survived")
  check "no set -e leak (zsh)" "$([ "$out" = "survived" ]; echo $?)"
}

main() {
  run_bash_tests
  run_zsh_tests
  exit "$fail"
}

main "$@"
