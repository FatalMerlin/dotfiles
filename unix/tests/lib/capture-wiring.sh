#!/usr/bin/env -S bash -eEuo pipefail
# prototype/unix/tests/lib/capture-wiring.sh <file>
#
# Snapshot the env/alias/PATH/completion effects of sourcing <file>, normalized
# and sorted, so two snapshots (old shell vs. new generated artifact) can be
# diffed for wiring parity (spec §8, Task 6).
#
# The actual sourcing happens inside a clean `zsh -f` (no rcfiles) so only
# <file>'s own effects show up in the delta — not whatever the ambient shell
# already had wired. Output lines are one of:
#   ENV <name>=<val>      — an env var <file> added or changed
#   ALIAS <name>=<val>    — an alias defined by <file>
#   PATH <dir>             — a directory present in $PATH after sourcing
#   COMPL <name>           — a cached-completion file <file> touched
#
# NB: this script itself must stay bash (git-bash/CI can `bash -n` it); only
# the inner sourcing runs under zsh, which is required because the dotfiles
# being tested are zsh scripts (aliases, zsh-specific PATH/completion wiring).
f="$1"

snap=$(zsh -f -c '
  emulate -L zsh
  # Snapshot env before sourcing.
  typeset -A _b
  for kv in ${(f)"$(env)"}; do _b[${kv%%=*}]=${kv#*=}; done

  # Snapshot completion cache dir contents before, if it exists.
  # Watches the output dir used by the cache_completion helper in core.sh, so
  # cached completions written by the file under test are actually detected.
  # (No apostrophes in this block — it lives inside a single-quoted zsh -c string.)
  compdir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions"
  typeset -a _compl_before
  _compl_before=()
  [[ -d "$compdir" ]] && _compl_before=("$compdir"/*(N))

  source "'"$f"'" >/dev/null 2>&1 || true

  # Env deltas: anything added or changed vs. the snapshot above.
  for kv in ${(f)"$(env)"}; do
    n=${kv%%=*}; val=${kv#*=}
    [[ $n == PATH ]] && continue   # PATH is captured separately as `PATH <dir>` lines
    [[ ${_b[$n]-__unset__} == "$val" ]] || print -r -- "ENV $n=$val"
  done

  # Aliases defined in the sourced shell.
  alias | sed "s/^/ALIAS /"

  # PATH entries (split on :, one per line).
  print -rl -- ${(s.:.)PATH} | sed "s#^#PATH #"

  # Completion files touched by sourcing (new entries in the cache dir).
  typeset -a _compl_after
  _compl_after=()
  [[ -d "$compdir" ]] && _compl_after=("$compdir"/*(N))
  for c in "${_compl_after[@]}"; do
    [[ " ${_compl_before[*]-} " == *" $c "* ]] || print -r -- "COMPL ${c:t}"
  done
' | sort -u)

printf '%s\n' "$snap"
