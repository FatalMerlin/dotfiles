param([string]$Repo = "https://github.com/FatalMerlin/dotfiles.git")
$ErrorActionPreference = "Stop"
$Src = "$HOME\.local\share\chezmoi"

if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
  winget install -e --id twpayne.chezmoi --accept-source-agreements --accept-package-agreements
  # Refresh PATH so the just-installed chezmoi resolves in THIS session.
  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}
if (-not (Get-Command gitleaks -ErrorAction SilentlyContinue)) {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install -e --id gitleaks.gitleaks --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "gitleaks install failed - the pre-commit leak guardrail will be INACTIVE locally (CI still scans on push). Install gitleaks manually."
    }
  }
  else {
    Write-Warning "winget not found - cannot install gitleaks; the pre-commit leak guardrail will be INACTIVE locally (CI still scans on push). Install gitleaks manually."
  }
}

# chezmoi is the apply-engine only; clone the repo ourselves (three sources, not one root).
if (Test-Path "$Src\.git") { git -C "$Src" pull --ff-only } else { git clone $Repo "$Src" }
git -C "$Src" config core.hooksPath hooks

# Supply your private [data] first: point ~\.config\chezmoi\chezmoi.toml at your private repo.
chezmoi apply -S "$Src\shared"
chezmoi apply -S "$Src\windows"
Write-Host "Bootstrap complete. Daily: 'dfa' (apply) / 'dfu' (pull+apply)."
