# dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## What this is

A public dotfiles repository. It contains shell configuration, editor settings, and other
tool configuration for a development environment. Personal and sensitive values (tokens,
email addresses, work-specific data) are never stored here — they are sourced at apply-time
from a private channel (e.g. a secrets manager or a private chezmoi `data` overlay).

## One-command bootstrap

### Windows (PowerShell)

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
irm https://raw.githubusercontent.com/FatalMerlin/dotfiles/main/bootstrap.ps1 | iex
```

Or clone first and run directly:

```powershell
.\bootstrap.ps1
# Optional: pass a different repo URL
.\bootstrap.ps1 -Repo https://github.com/your-fork/dotfiles.git
```

The script:
1. Installs `chezmoi` via winget if not already present.
2. Installs `gitleaks` via winget (used by the pre-commit guardrail — see below).
3. Runs `chezmoi init --apply` to clone and apply the dotfiles.
4. Sets `core.hooksPath hooks` in the chezmoi source repo so the guardrail is active immediately.

### Linux / macOS (sh)

```sh
sh -c "$(curl -fsLS https://raw.githubusercontent.com/FatalMerlin/dotfiles/main/bootstrap.sh)"
# Optional: pass a different repo URL as argument
sh bootstrap.sh https://github.com/your-fork/dotfiles.git
```

The script:
1. Installs `chezmoi` to `~/.local/bin` via the official installer if not already present.
2. Notes if `gitleaks` is missing (install separately for the pre-commit guardrail).
3. Runs `chezmoi init --apply` to clone and apply the dotfiles.
4. Sets `core.hooksPath hooks` in the chezmoi source repo.

## Leak guardrail

A `pre-commit` hook powered by [gitleaks](https://github.com/gitleaks/gitleaks) is enforced
in the chezmoi source repository. It blocks commits that contain secrets or personally
identifying data. Install gitleaks before committing changes to ensure the guardrail is
active.

## Personal data

This repository contains no personal data, hostnames, work-specific identifiers, or private
credentials. All such values are injected at apply-time from a private data source (not
committed here). If you fork this repo, configure your own private data channel before
running `chezmoi apply`.
