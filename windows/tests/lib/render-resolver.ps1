# prototype/windows/tests/lib/render-resolver.ps1
#
# PowerShell mirror of tests/lib/render-resolver.sh. Seeds a temp chezmoi source
# dir with a fixture manifest + the real .chezmoidata/defaults.yaml and
# .chezmoitemplates, runs a REAL `chezmoi apply` against a throwaway HOME (so the
# run_onchange_resolve-deps.ps1.tmpl script actually executes the way it would on
# a real machine), and OUTPUTS (Write-Output) the path to a temp dir holding the
# produced deps.ps1 (+ install-plan.ps1 when present).
#
# A real apply — not `chezmoi execute-template` — is used deliberately:
# `.chezmoitemplates/*.tmpl` files are only auto-loaded as callable named
# templates via `includeTemplate` during a real apply; a hand-concatenated
# execute-template render would mask that class of bug.
#
# Windows-test-only interpreter shim: the native-Windows chezmoi binary ships
# built-in interpreter defaults for .ps1 (pwsh), but the test pins -NoProfile via
# a throwaway chezmoi.toml so the resolver runs in a clean pwsh. Output is pointed
# at a sandbox dir via $env:DEPS_OUT_DIR (the resolver honours it), sidestepping
# $HOME differences inside the interpreter child.
#
# Source root is derived from $PSScriptRoot (this file lives at
# prototype/windows/tests/lib/render-resolver.ps1, so the windows source root is
# two levels up from its directory), NOT from git — this worktree's .git file
# points at a path git may not resolve at test time.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Fixture
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# windows source root = two levels up from this file's directory (tests/lib/..).
$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

$resolverTmpl = Join-Path $root 'run_onchange_resolve-deps.ps1.tmpl'
if (-not (Test-Path -LiteralPath $resolverTmpl)) {
    Write-Error "render-resolver.ps1: $resolverTmpl does not exist"
    exit 1
}

# Per-run sandbox (chezmoi source + throwaway HOME). Cleaned at the end; the
# copied-out artifacts live in a SEPARATE dir that outlives this script.
$sb = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-render-" + [System.Guid]::NewGuid().ToString('N'))
$srcDir = Join-Path $sb 'src'
$homeDir = Join-Path $sb 'home'

try {
    New-Item -ItemType Directory -Force -Path $homeDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $srcDir '.chezmoidata') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $srcDir '.chezmoitemplates') | Out-Null

    Copy-Item -LiteralPath $Fixture -Destination (Join-Path $srcDir '.chezmoidata/packages.yaml') -Force
    Copy-Item -LiteralPath (Join-Path $root '.chezmoidata/defaults.yaml') -Destination (Join-Path $srcDir '.chezmoidata/defaults.yaml') -Force
    Copy-Item -Path (Join-Path $root '.chezmoitemplates/*') -Destination (Join-Path $srcDir '.chezmoitemplates/') -Force
    Copy-Item -LiteralPath $resolverTmpl -Destination (Join-Path $srcDir 'run_onchange_resolve-deps.ps1.tmpl') -Force

    # Throwaway chezmoi config: run .ps1 interpreters via pwsh -NoProfile.
    $cfg = Join-Path $sb 'chezmoi.toml'
    Set-Content -LiteralPath $cfg -Encoding utf8 -Value @'
[interpreters.ps1]
    command = "pwsh"
    args = ["-NoProfile"]
'@

    # Point resolver output at the sandbox out dir; also seed HOME/USERPROFILE
    # to the sandbox home for good measure.
    $outSandbox = Join-Path $sb 'out'
    $env:DEPS_OUT_DIR = $outSandbox
    $env:HOME = $homeDir
    $env:USERPROFILE = $homeDir

    # Real apply. The run_onchange script this renders to executes as part of
    # apply, writing deps.ps1 (+ install-plan.ps1) under $env:DEPS_OUT_DIR.
    $applyOut = & chezmoi apply --source "$srcDir" --config "$cfg" --no-tty --destination "$homeDir" 2>&1
    $applyExit = $LASTEXITCODE

    $depsPath = Join-Path $outSandbox 'deps.ps1'
    if ($applyExit -ne 0 -or -not (Test-Path -LiteralPath $depsPath)) {
        Write-Error ("render-resolver.ps1: chezmoi apply failed (exit $applyExit)`n" + ($applyOut | Out-String))
        exit 1
    }

    # Copy artifacts into a dir that OUTLIVES this script (caller reads them).
    $outCopy = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-out-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $outCopy | Out-Null
    Copy-Item -LiteralPath $depsPath -Destination (Join-Path $outCopy 'deps.ps1') -Force
    $planPath = Join-Path $outSandbox 'install-plan.ps1'
    if (Test-Path -LiteralPath $planPath) {
        Copy-Item -LiteralPath $planPath -Destination (Join-Path $outCopy 'install-plan.ps1') -Force
    }

    Write-Output $outCopy
}
finally {
    Remove-Item -LiteralPath $sb -Recurse -Force -ErrorAction SilentlyContinue
}
