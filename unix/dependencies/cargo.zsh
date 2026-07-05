if ifalias c cargo custom "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile default --component rust-analyzer -y && mkdir -p ~/.zfunc && rustup completions zsh > ~/.zfunc/_rustup"; then
    # alias c='cargo'
    alias cc='cargo check'
    alias ct='cargo test'
    alias cr='cargo run'
    alias cu='cargo update'

    fpath+=~/.zfunc

    if ifpkg libssl-dev && ifpkg pkg-config && ifcmd sccache cargo sccache; then
        if ifcmd cargo-install-update cargo cargo-update; then
            alias ciu="cargo install-update -a"
        fi

        export RUSTC_WRAPPER=sccache
        alias ci='RUSTC_WRAPPER=sccache cargo install --locked'
        alias cb='RUSTC_WRAPPER=sccache cargo build'
        alias cbr='RUSTC_WRAPPER=sccache cargo build --release'
        # else
        # alias ci='cargo install --locked'
        # alias cb='cargo build'
        # alias cbr='cargo build --release'

        ifcmd bat cargo bat
        if ifcmd zoxide cargo zoxide; then
            debug_measure_start "cargo: zoxide init"
            cache_completion zoxide zoxide init zsh
            debug_measure_end
        fi
        ifalias ls exa cargo
        ifalias du dust cargo du-dust
        # ifalias grep rg cargo ripgrep
        ifcmd rg cargo ripgrep  # ! don't overwrite system defaults
        # ifalias ps procs cargo
        ifcmd procs cargo procs # ! don't overwrite system defaults
        # TODO: find way to automatically warn about overwriting built-in and system default commands
        # TODO: find way to still remind about using and adopting new tools! Detect when using system default with alternative present in interactive sessions?
        ifalias bench hyperfine cargo
        if ifcmd broot cargo broot; then
            debug_measure_start "cargo: broot init"
            cache_completion broot broot --print-shell-function zsh
            # broot --set-install-state installed
            debug_measure_end
        fi

        if ifcmd cmake brew cmake; then
            # ifcmd gitui cargo gitui
        fi

        ifcmd fd cargo fd-find

        # git-prism (Agent-optimized git data for LLM agents.)
        if ifcmd git-prism cargo git-prism; then
            claude mcp add git-prism -- git-prism serve >/dev/null 2>&1
            # git-prism hooks install --scope user --force
            # TODO: switch to "git-prism shim install"
        fi
    fi
fi
