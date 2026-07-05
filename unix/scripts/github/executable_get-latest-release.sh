#!/usr/bin/env bash
set -eEuo pipefail

# https://api.github.com/repos/owner/repo/releases

function ensure_command {
    if ! command -v "$1" >/dev/null; then
        echo "Missing '$1'"
        exit 1
    fi
}

function usage {
    echo "Usage  : $0 <owner>/<repo> <filter>"
    echo "Example: $0 TheAssassin/AppImageLauncher '*amd64.deb'"
}

ensure_command jq
ensure_command curl

if [ -z "$1" ]; then
    echo "Missing repo: <owner>/<repo>"
    usage
    exit 1
fi

if [ -z "$2" ]; then
    echo "Missing filter: <filter>"
    usage
    exit 1
fi

latest_assets=$(
    curl -sSLf "https://api.github.com/repos/$1/releases/latest" \
        | jq -r '.assets[].browser_download_url'
)

for asset in $latest_assets; do
    # intentional glob matching :)
    # shellcheck disable=SC2053
    if [[ "$asset" == $2 ]]; then
        echo "$asset"
    fi
done