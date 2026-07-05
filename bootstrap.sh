#!/usr/bin/env sh
set -e
REPO="${1:-https://github.com/FatalMerlin/dotfiles.git}"
SRC="$HOME/.local/share/chezmoi"

if ! command -v chezmoi >/dev/null 2>&1; then
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v gitleaks >/dev/null 2>&1 || echo "note: install gitleaks for the pre-commit guardrail"

# chezmoi is the apply-engine only; clone the repo ourselves (three sources, not one root).
if [ -d "$SRC/.git" ]; then git -C "$SRC" pull --ff-only; else git clone "$REPO" "$SRC"; fi
git -C "$SRC" config core.hooksPath hooks

# Supply your private [data] first: point ~/.config/chezmoi/chezmoi.toml at your private repo.
# unix/ serves both Linux and darwin (macOS).
chezmoi apply -S "$SRC/shared"
chezmoi apply -S "$SRC/unix"
echo "Bootstrap complete. Daily: 'dfa' (apply) / 'dfu' (pull+apply)."
