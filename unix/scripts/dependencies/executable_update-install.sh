#!/usr/bin/env -S zsh -l
set -eEuo pipefail

UPDATE_CACHE_FILE="$HOME/.cache/dotfiles_updates.count"
SCRIPT_DIR=$(readlink -f "${0%/*}")

on_err() {
    local rc=$?            # must be first
    local line=$1 cmd=$2
    echo "ERROR at line ${line}: '${cmd}' exited with ${rc}" >&2
}
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR

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
echo "Checking for updates..."
"$SCRIPT_DIR"/update-check.sh >/dev/null

pending_update_sources=("${(z)$(<"$UPDATE_CACHE_FILE")}")

if [ -z "$pending_update_sources" ]; then
    echo "No updates available"
    exit 0
fi

for source in "${pending_update_sources[@]}"; do
    echo "$source: installing updates..."
    "update_$source"
done

echo "Checking for updates..."
"$SCRIPT_DIR"/update-check.sh >/dev/null