# Shell-framework plugins (oh-my-zsh ecosystem, not tracked CLI tools) — kept
# bespoke: the manifest covers installable tools, not zsh plugins. The custom
# TOOLS (uv/az/dotnet/helmfmt/ail-cli/nvim/cache-fix-proxy) migrated to
# .chezmoidata/packages.yaml (custom group).
ZSH_AUTOSUGGESTIONS="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
if ! [ -d "${ZSH_AUTOSUGGESTIONS}" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_AUTOSUGGESTIONS}"
fi

POWERLEVEL_10K="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if ! [ -d "${POWERLEVEL_10K}" ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${POWERLEVEL_10K}"
fi
