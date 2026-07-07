#!/usr/bin/env -S bash -eEuo pipefail
# Strict mode (-eEuo pipefail) applies on direct execution; ignored when sourced.
. "$HOME/.config/dotfiles/lib/core.sh"
. "$HOME/.config/dotfiles/lib/harness.sh"

# https://api.github.com/repos/owner/repo/releases

_USAGE='<owner>/<repo> <filter>   e.g. TheAssassin/AppImageLauncher "*amd64.deb"'

have jq || die "missing: jq"
have curl || die "missing: curl"

require_args 2 "$#"

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
