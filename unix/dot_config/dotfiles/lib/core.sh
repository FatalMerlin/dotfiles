# prototype/unix/dot_config/dotfiles/lib/core.sh
# POSIX core library for the dotfiles dependency engine.
# SOURCED by: the interactive shell (zsh), the apply-time resolver (bash), the
# provisioner, and standalone scripts. Because interactive shells source it, it
# is strict-mode-SAFE: it never runs `set -e`/`set -u`/`pipefail` and never
# installs an ERR trap (any of which would kill an interactive shell). POSIX sh
# only — verified source-clean under both zsh and bash (tests/test-core-lib.sh).

# ---- color / NO_COLOR (fd-aware) ------------------------------------------
# Honour NO_COLOR (https://no-color.org); only colourise a real terminal on fd 1.
if [ -n "${NO_COLOR:-}" ] || ! [ -t 1 ] || ! command -v tput >/dev/null 2>&1; then
  _c_reset='' _c_red='' _c_grn='' _c_ylw='' _c_blu='' _c_gry=''
else
  _c_reset="$(tput sgr0   2>/dev/null || printf '')"
  _c_red="$(  tput setaf 1 2>/dev/null || printf '')"
  _c_grn="$(  tput setaf 2 2>/dev/null || printf '')"
  _c_ylw="$(  tput setaf 3 2>/dev/null || printf '')"
  _c_blu="$(  tput setaf 4 2>/dev/null || printf '')"
  _c_gry="$(  tput setaf 8 2>/dev/null || tput setaf 7 2>/dev/null || printf '')"
fi

# ---- logging (→ stderr) ----------------------------------------------------
# NB: the debug-level logger is `log_debug`, NOT `debug` — `debug`/`debug_measure_*`
# in dot_zshrc.tmpl are the interactive timing UI and must not be clobbered.
log()       { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
info()      { log "${_c_blu}[info]${_c_reset} $*"; }
warn()      { log "${_c_ylw}[warn]${_c_reset} $*"; }
error()     { log "${_c_red}[fail]${_c_reset} $*"; }
success()   { log "${_c_grn}[ ok ]${_c_reset} $*"; }
log_debug() { [ "${DOTFILES_DEBUG:-false}" = "true" ] && log "${_c_gry}[dbg ]${_c_reset} $*"; return 0; }

# ---- presence --------------------------------------------------------------
# The single presence primitive the generated startup artifact self-guards with.
have() { command -v "$1" >/dev/null 2>&1; }

# ---- PATH helpers (dir-guarded, dedup, idempotent) -------------------------
ifpath_prepend() { [ -d "$1" ] || return 0; case ":$PATH:" in *":$1:"*) ;; *) PATH="$1:$PATH"; export PATH ;; esac; }
ifpath_append()  { [ -d "$1" ] || return 0; case ":$PATH:" in *":$1:"*) ;; *) PATH="$PATH:$1"; export PATH ;; esac; }
ifpath() { ifpath_append "$1"; }

# ---- completion cache (POSIX port of the zsh cache_completion) -------------
# Cache stdout of a completion/alias-generating command; regenerate when the
# binary is newer than the cache; then source it. Uses `command -v` + `dirname`
# instead of zsh ${commands[]} / ${x:h}. (`-nt` is honoured by bash + zsh.)
cache_completion() {
  _cc_name="$1"; shift
  _cc_bin="$(command -v "$_cc_name" 2>/dev/null)" || return 1
  [ -n "$_cc_bin" ] || return 1
  _cc_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions/$_cc_name"
  if [ ! -f "$_cc_cache" ] || [ "$_cc_bin" -nt "$_cc_cache" ]; then
    mkdir -p "$(dirname "$_cc_cache")"
    "$@" > "$_cc_cache" 2>/dev/null || { rm -f "$_cc_cache"; return 1; }
  fi
  # shellcheck disable=SC1090
  . "$_cc_cache"
}

# ---- missing-report primitives --------------------------------------------
dep_reset_missing() { _DEP_MISSING_COUNT=0; _DEP_MISSING_LIST=''; }
dep_mark_missing()  {
  _DEP_MISSING_COUNT=$(( ${_DEP_MISSING_COUNT:-0} + 1 ))
  _DEP_MISSING_LIST="${_DEP_MISSING_LIST:+$_DEP_MISSING_LIST }$1"
}
dep_report_missing() {
  [ "${_DEP_MISSING_COUNT:-0}" -gt 0 ] || return 0
  warn "${_DEP_MISSING_COUNT} declared tool(s) missing:${_DEP_MISSING_LIST:+ $_DEP_MISSING_LIST} — run 'im' to install"
}
