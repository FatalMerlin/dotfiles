#!/usr/bin/env -S zsh -leuo pipefail
# Strict mode (-euo pipefail) applies on direct execution; ignored when sourced.
. "$HOME/.config/dotfiles/lib/core.sh"

UPDATE_CACHE_FILE="$HOME/.cache/dotfiles_updates.count"

# Bespoke ERR trap (not harness.sh's): the ERROR sentinel written to
# $UPDATE_CACHE_FILE is load-bearing — the shell-startup drift check and the
# update-check timer both read it — and harness.sh's ERR trap doesn't write
# it. Uses $ZSH_DEBUG_CMD (the zsh-correct failing-command variable; this
# script runs under zsh, so $BASH_COMMAND is never populated).
on_err() {
    local rc=$?            # must be first
    local line=$1 cmd=$2
    error "ERROR at line ${line}: '${cmd}' exited with ${rc}"
    echo "ERROR" > "$UPDATE_CACHE_FILE"
    exit "$rc"
}
trap 'on_err "$LINENO" "${ZSH_DEBUG_CMD:-?}"' ERR

function check_apt {
    COUNT=$(apt-get -s upgrade 2>/dev/null | awk '/^Inst / {c++} END {print c+0}')
    echo "$COUNT"
}

function check_brew {
    HOMEBREW_NO_ENV_HINTS=1 brew update --quiet >/dev/null 2>&1 || true
    HOMEBREW_NO_ENV_HINTS=1 brew outdated --quiet --greedy | wc -l | tr -d " "
}

function check_cargo {
    COUNT=$(cargo install-update -l | grep -c 'Yes' | tr -d " ")
    echo "$COUNT"
}

# Array of function names
update_check_functions=(
    check_apt
    check_brew
    check_cargo
)

updates_sources_with_pending_updates=()

for update_checker in "${update_check_functions[@]}"; do
    friendly_name=${update_checker#check_}
    info "$friendly_name: checking for updates"

    if ! command -v "$friendly_name" >/dev/null; then
        info "$friendly_name: not found, skipping"
        continue
    fi

    # invoke function by name
    set +o pipefail
    update_count="$("$update_checker")"
    set -o pipefail

    info "$friendly_name: $update_count updates available"
    [[ "$update_count" -gt 0 ]] || continue
    updates_sources_with_pending_updates+=("$friendly_name")
done

echo -n "${updates_sources_with_pending_updates[@]}" > "$UPDATE_CACHE_FILE"

# chezmoi config-drift count (best-effort, non-fatal). Surfaced at shell startup
# (the .zshrc drift check) and by the update-check timer.
CHEZMOI_DRIFT_FILE="$HOME/.cache/dotfiles_chezmoi_drift"
if command -v chezmoi >/dev/null 2>&1; then
    # chezmoi drift across the two applied sources (apply-engine model).
    # This script only runs on unix (it lives in unix/scripts), so the sources are always shared + unix.
    DOTFILES_SRC="${DOTFILES_SRC:-$HOME/.local/share/chezmoi}"
    cz_drift=0
    for _src in shared unix; do
      if [ -d "$DOTFILES_SRC/$_src" ]; then
        # non-fatal: a chezmoi error must not trip set -e / the ERR trap (best-effort drift count)
        _n=$(chezmoi status -S "$DOTFILES_SRC/$_src" 2>/dev/null | wc -l) || _n=0
        cz_drift=$(( cz_drift + _n ))
      fi
    done
    echo "$cz_drift" > "$CHEZMOI_DRIFT_FILE" || true
fi
