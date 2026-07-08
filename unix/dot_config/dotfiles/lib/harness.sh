# prototype/unix/dot_config/dotfiles/lib/harness.sh
# Script harness — sourced by a strict-mode script AFTER its strict-mode shebang
# (#!/usr/bin/env -S bash -eEuo pipefail, or zsh -euo pipefail). NOT sourced by
# the interactive shell. Adds the non-option pieces the shebang can't: a
# diagnostics fd, an ERR trap, and the usage/arg-validation scaffold.
#
# Strict mode via the shebang: applied on direct execution, ignored when a file
# is sourced — so libraries and the shell profile reuse functions without
# inheriting `set -e` (which would kill an interactive shell).

# fd 8 = diagnostics channel, kept distinct from a command's real stderr so log
# output survives 2>redirects. (exec 8>&2 convention.)
exec 8>&2

_harness_on_err() {
  _rc=$?
  # shellcheck disable=SC2016  # printf format is intentionally single-quoted; values pass as args
  printf '%s ERROR at line %s: `%s` exited %s\n' "$(date '+%H:%M:%S')" "$1" "$2" "$_rc" >&8
  exit "$_rc"
}
# bash reports the failing command via $BASH_COMMAND; zsh's ERR trap does not
# populate an equivalent (no $ZSH_DEBUG_CMD), so it falls back to "?" below —
# line number and exit code are still accurate under both shells.
if [ -n "${ZSH_VERSION:-}" ]; then
  trap '_harness_on_err "$LINENO" "${ZSH_DEBUG_CMD:-?}"' ERR
else
  trap '_harness_on_err "$LINENO" "$BASH_COMMAND"' ERR
fi

usage() { printf 'Usage: %s\n' "${_USAGE:-$0 [args]}" >&8; }
die()   { printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >&8; usage; exit "${2:-1}"; }
require_args() { [ "$2" -ge "$1" ] || die "expected at least $1 argument(s), got $2"; }
