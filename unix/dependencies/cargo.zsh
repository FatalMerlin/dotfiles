# cargo/rust MANAGER bootstrap (installs rustup + rust-analyzer, sets up ~/.zfunc
# for rustup completions). Kept bespoke like the brew bootstrap — the cargo-installed
# TOOLS were migrated to .chezmoidata/packages.yaml (cargo group). The fpath+=~/.zfunc
# and cc/ct/cr/cu aliases stay here (zsh-specific manager wiring, cargo-gated).
#
# The recipe sources ~/.cargo/env immediately after rustup-init: `im` eval's this
# recipe in the running shell, and rustup only writes the PATH export to ~/.zshenv
# (picked up on the NEXT shell), not the current one. Without the source, cargo is
# still off-PATH for the rest of the same `im` run, so every cargo-manager tool
# (install-plan step 2) — and this recipe's own trailing `rustup completions` — dies
# with `command not found: cargo`. Sourcing here puts ~/.cargo/bin on PATH in-session.
if ifalias c cargo custom "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile default --component rust-analyzer -y && . ~/.cargo/env && mkdir -p ~/.zfunc && rustup completions zsh > ~/.zfunc/_rustup"; then
    # alias c='cargo'
    alias cc='cargo check'
    alias ct='cargo test'
    alias cr='cargo run'
    alias cu='cargo update'

    fpath+=~/.zfunc
fi
