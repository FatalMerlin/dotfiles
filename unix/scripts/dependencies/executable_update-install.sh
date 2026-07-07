#!/usr/bin/env -S zsh -leuo pipefail
# Strict mode (-euo pipefail) applies on direct execution; ignored when sourced.
. "$HOME/.config/dotfiles/lib/core.sh"
. "$HOME/.config/dotfiles/lib/harness.sh"

UPDATE_CACHE_FILE="$HOME/.cache/dotfiles_updates.count"
SCRIPT_DIR=$(readlink -f "${0%/*}")

function update_apt() {
    sudo apt upgrade -y
}

function update_brew() {
    brew upgrade -y
}

function update_cargo() {
    cargo install-update -a
}

# Check first to catch eventual additional updates
info "Checking for updates..."
"$SCRIPT_DIR"/update-check.sh >/dev/null

pending_update_sources=("${(z)$(<"$UPDATE_CACHE_FILE")}")

if [ -z "$pending_update_sources" ]; then
    info "No updates available"
    exit 0
fi

for source in "${pending_update_sources[@]}"; do
    info "$source: installing updates..."
    "update_$source"
done

info "Checking for updates..."
"$SCRIPT_DIR"/update-check.sh >/dev/null
