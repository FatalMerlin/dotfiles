# cargo/rust MANAGER bootstrap (installs rustup + rust-analyzer, sets up ~/.zfunc
# for rustup completions). Kept bespoke like the brew bootstrap — the cargo-installed
# TOOLS were migrated to .chezmoidata/packages.yaml (cargo group). The fpath+=~/.zfunc
# and cc/ct/cr/cu aliases stay here (zsh-specific manager wiring, cargo-gated).
if ifalias c cargo custom "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile default --component rust-analyzer -y && mkdir -p ~/.zfunc && rustup completions zsh > ~/.zfunc/_rustup"; then
    # alias c='cargo'
    alias cc='cargo check'
    alias ct='cargo test'
    alias cr='cargo run'
    alias cu='cargo update'

    fpath+=~/.zfunc
fi
