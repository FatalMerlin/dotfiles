# prototype/unix/dot_config/dotfiles/hooks/setup-hooks.sh
# Named `setup:` hooks for the declarative dependency resolver (spec §5.2).
#
# The manifest is declarative — gate/check/env/path/aliases/completion cover
# the general shape of "how to wire up a tool once it's present". Some tools
# need genuinely irreducible bespoke logic (a one-off bootstrap sequence, a
# config file the tool insists on, etc.) that doesn't fit any declarative
# field and would be a net loss to force into one. `setup:` is the escape
# hatch for exactly that: a manifest entry names a hook (`setup: "<hook>"`),
# and the resolver emits a call to the correspondingly-named function here,
# inside the tool's `have`-guard. Keep this file as the LAST resort — if a
# hook count grows large or hooks start looking similar, that's a signal a
# new declarative field (e.g. `service:`/`plugin:`) is missing, not that this
# file should keep growing.
#
# SOURCED unconditionally by the generated deps.sh preamble (cheap: this file
# contains ONLY function definitions, no top-level execution). It must stay
# POSIX-portable — sourced under both zsh (interactive shell) and bash (the
# apply-time resolver) — and strict-mode-SAFE: no `set -e`/`-u`/`pipefail`,
# no traps. A failing hook must not tear down the shell that sourced it.

# ---- kubectl_krew -----------------------------------------------------------
# Ported from prototype/unix/dependencies/brew.zsh.tmpl (kubectl guard, krew
# bootstrap + oidc-login/view-secret/node-shell plugin installs). The zsh
# `export PATH=...krew/bin:$PATH` line from the original is deliberately NOT
# included here — that's now handled by the manifest's `path:` field
# (migration), not this hook. This hook only does the bespoke part: install
# krew itself if absent, then install the three plugins if their receipts
# are absent.
#
# POSIX conversions from the zsh original:
#   - `[[ ... ]]` -> `[ ... ]`
#   - zsh `local` scoping for _krew_receipts dropped (POSIX sh has no `local`);
#     the variable is `unset` at the end of the function instead, mirroring
#     the original's explicit `unset _krew_receipts`.
#   - `debug_measure_start`/`debug_measure_end` (interactive zsh timing UI, not
#     part of core.sh) dropped — this hook runs under the apply-time resolver
#     (bash) too, where that UI does not exist.
kubectl_krew() {
  _krew_receipts="${KREW_ROOT:-$HOME/.krew}/receipts"
  if [ ! -d "$_krew_receipts" ]; then
    echo "'kubectl krew' was missing, installing..."
    (
      set -x
      cd "$(mktemp -d)" &&
        OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
        ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
        KREW="krew-${OS}_${ARCH}" &&
        curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
        tar zxvf "${KREW}.tar.gz" &&
        ./"${KREW}" install krew
    )
  else
    [ -f "$_krew_receipts/oidc-login.yaml" ]  || kubectl krew install oidc-login
    [ -f "$_krew_receipts/view-secret.yaml" ] || kubectl krew install view-secret
    [ -f "$_krew_receipts/node-shell.yaml" ]  || kubectl krew install node-shell
  fi
  unset _krew_receipts
}

# ---- fnm_lts ----------------------------------------------------------------
# Ported from brew.zsh.tmpl (fnm block): ensure the latest LTS Node is installed
# and used. Idempotent + quiet; fnm no-ops if the LTS is already the active one.
fnm_lts() {
  fnm install --use --lts >/dev/null 2>&1
}

# ---- git_prism_mcp ----------------------------------------------------------
# Ported from cargo.zsh (git-prism block): register git-prism as a Claude Code
# MCP server. Silent + best-effort (no-ops / harmless re-add if already present).
git_prism_mcp() {
  claude mcp add git-prism -- git-prism serve >/dev/null 2>&1
}

# ---- cache_fix_proxy_service -----------------------------------------------
# Ported from custom.zsh (cache-fix-proxy block): install + enable the user
# systemd service (once) and enable linger so it survives logout. Idempotent
# via the service-file / linger-status guards. sudo prompt matches legacy.
cache_fix_proxy_service() {
  if ! [ -f "$HOME/.config/systemd/user/cache-fix-proxy.service" ]; then
    cache-fix-proxy install-service --force >/dev/null 2>&1
    systemctl --user daemon-reload
    systemctl --user enable --now cache-fix-proxy
    systemctl --user enable --now cache-fix-proxy-healthcheck.timer
  fi
  if ! loginctl show-user "$USER" --property=Linger | grep -q 'yes'; then
    sudo loginctl enable-linger "$USER"
  fi
}
