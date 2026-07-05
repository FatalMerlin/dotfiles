# ifcmd nvim custom updateNeovim
ifalias nano nvim custom updateNeovim

# Source: https://github.com/astral-sh/uv
# Python UV package manager
if ifcmd uv custom 'curl -LsSf https://astral.sh/uv/install.sh | sh'; then
    # todo: update detection / auto update
    # https://docs.astral.sh/uv/getting-started/installation/#shell-autocompletion
    debug_measure_start "custom: uv completions"
    cache_completion uv uv generate-shell-completion zsh
    cache_completion uvx uvx --generate-shell-completion zsh
    debug_measure_end
fi

ifcmd az custom 'curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash'

ifcmd dotnet-install.sh custom 'mkdir -p "$HOME/.local/bin" && curl -L https://dot.net/v1/dotnet-install.sh -o "$HOME/.local/bin/dotnet-install.sh" && chmod +x "$HOME/.local/bin/dotnet-install.sh"'

ZSH_AUTOSUGGESTIONS="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
if ! [ -d "${ZSH_AUTOSUGGESTIONS}" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_AUTOSUGGESTIONS}"
fi

POWERLEVEL_10K="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if ! [ -d "${POWERLEVEL_10K}" ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${POWERLEVEL_10K}"
fi

if ! (( IS_WSL )); then
    if command -v uname >/dev/null; then
        current_arch="$(uname -m)"
    elif command -v arch >/dev/null; then
        current_arch="$(arch)"
    fi

    if [ "$current_arch" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$current_arch" = "aarch64" ]; then
        ARCH="arm64"
    fi

    # https://github.com/TheAssassin/AppImageLauncher
    ifcmd ail-cli custom "curl -sSLf \"\$(get-latest-release.sh TheAssassin/AppImageLauncher '*${ARCH}.deb')\" -o /tmp/appimagelauncher.deb && sudo apt install /tmp/appimagelauncher.deb && rm /tmp/appimagelauncher.deb"
fi

ifcmd helmfmt custom "go install github.com/digitalstudium/helmfmt@latest"

if ifcmd cache-fix-proxy custom "npm install -g claude-code-cache-fix"; then
    if ! [ -f "$HOME/.config/systemd/user/cache-fix-proxy.service" ]; then
        cache-fix-proxy install-service --force >/dev/null 2>&1
        systemctl --user daemon-reload
        systemctl --user enable --now cache-fix-proxy
        systemctl --user enable --now cache-fix-proxy-healthcheck.timer   # auto-recovery — see below
    fi
    if ! loginctl show-user "$USER" --property=Linger | grep -q 'yes'; then
        sudo loginctl enable-linger "$USER"   # optional: start on boot, not just on login
    fi

    export ANTHROPIC_BASE_URL="http://127.0.0.1:9801"
fi
