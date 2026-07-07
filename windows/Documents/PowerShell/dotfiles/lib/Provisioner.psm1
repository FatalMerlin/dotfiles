# prototype/windows/Documents/PowerShell/dotfiles/lib/Provisioner.psm1
# PowerShell mirror of the unix Approach-A on-demand provisioner
# (dot_functions.zsh's listMissing/installMissing/_dep_install_candidate/
# _dep_plan_path + the legacy _DEP_RECIPE map). Provides the interactive
# `im`/`lm` commands.
#
# IMPORTED BY: the PowerShell profile, AFTER deps.ps1 has imported Core.psm1
# (so Core's tally + presence primitives already exist in the session). This
# module deliberately does NOT `Import-Module Core` at load time: it must not
# hard-fail if Core is absent, and it relies on Core's functions being resolved
# at CALL time (PowerShell late-binds function names). The profile guarantees
# Core is imported first via deps.ps1.
#
# Core functions consumed by name (resolved at call time, not import time):
#   Get-DepMissing       — the [List[string]] of currently-missing tool names.
#   Get-DepMissingCount  — its count.
#   have <name>          — presence test (Get-Command wrapper).
#   dep_mark_missing     — used by Add-DepRecipe to fold a legacy tool into the
#                          shared tally when it's absent.
#
# Naming: lowercase_underscore names (installMissing, listMissing,
# _dep_install_candidate, _dep_plan_path) mirror the unix functions for
# line-level parity. Add-DepRecipe uses the approved `Add` verb.

# ---- install-command shapes ------------------------------------------------
# Mirror of the old _functions.ps1 buildInstallCmd + the unix
# getInstallInstructions: map (manager, source) -> the shell command that
# installs it. `custom` carries the literal install command in $Src.
function buildInstallCmd {
    param([string] $Manager, [string] $Src)
    switch ($Manager) {
        'winget' { return "winget install -s winget -e --id $Src" }
        'cargo'  { return "cargo install $Src" }
        'npm'    { return "npm install -g $Src" }
        'custom' { return $Src }  # $Src is the literal install command
        default  { return "echo 'unknown manager: $Manager for $Src'" }
    }
}

# ---- install-plan location -------------------------------------------------
# Path to the resolver-emitted install-plan.ps1 (topo-sorted
# `<name>\t<manager>\t<source-or-install-command>` rows). Honours the same
# DEPS_OUT_DIR knob the resolver writes with
# (run_onchange_resolve-deps.ps1.tmpl), so tests (and any alt-HOME run) can
# redirect both sides consistently. Mirrors unix `_dep_plan_path`.
function _dep_plan_path {
    $dir = if ($env:DEPS_OUT_DIR) { $env:DEPS_OUT_DIR } else { Join-Path $HOME '.config/dotfiles' }
    return Join-Path $dir 'install-plan.ps1'
}

# ---- legacy recipe map -----------------------------------------------------
# Legacy MANAGER bootstraps that are NOT in the manifest (so absent from
# install-plan.ps1). On Windows this is rustup, the bootstrap for the `cargo`
# manager: cargo-managed manifest tools (e.g. git-prism) can't install before
# cargo itself exists. Mirrors the unix _DEP_RECIPE (brew/rustup/jiratui).
# Keyed by tool name -> @{ Manager; Package }.
$script:DepRecipe = @{}

# Add-DepRecipe <name> <manager> <package> — record a legacy install recipe
# AND, if the tool is currently absent, mark it missing so it joins the shared
# tally (mirrors the unix re-plumbed `ifcmd cargo winget Rustlang.Rustup`,
# which both records the recipe and dep_mark_missing-es cargo when absent).
# The profile calls e.g. `Add-DepRecipe cargo winget Rustlang.Rustup` after
# sourcing deps.ps1.
function Add-DepRecipe {
    param([string] $Name, [string] $Manager, [string] $Package)
    $script:DepRecipe[$Name] = @{ Manager = $Manager; Package = $Package }
    if (-not (have $Name)) {
        dep_mark_missing $Name
    }
}

# ---- listMissing / lm ------------------------------------------------------
# Mirror of unix listMissing: print the missing-tool names (one `> <name>` per
# line) from the shared tally. Any argument suppresses the install hint (used
# by installMissing to avoid double-printing the hint).
function listMissing {
    param([Parameter(ValueFromRemainingArguments = $true)] $RestArgs)
    if ((Get-DepMissingCount) -gt 0) {
        Write-Host "The following packages are missing from your system:"
        foreach ($cmd in (Get-DepMissing)) {
            Write-Host "> $cmd"
        }

        if ($RestArgs) {
            return
        }

        Write-Host ""
        Write-Host "Run the following command to install them:"
        Write-Host "> installMissing (im)"
    }
}
Set-Alias lm listMissing

# ---- _dep_install_candidate (internal) -------------------------------------
# Install (or DRY_RUN-print) ONE candidate, but only if it is still in the
# missing tally AND still absent — a prior install in this same `im` run may
# have satisfied it as a side effect. Mirrors unix _dep_install_candidate;
# there is no dpkg equivalent on Windows, so `have` (Get-Command) is the sole
# presence test for every manager.
function _dep_install_candidate {
    param([string] $Name, [string] $Manager, [string] $Src)

    # Case-sensitively match the stored names in the tally.
    if (-not ((Get-DepMissing) -ccontains $Name)) { return }

    # Live presence re-check: a prior install this run may have satisfied it.
    if (have $Name) { return }

    $cmd = buildInstallCmd $Manager $Src

    if ($env:DRY_RUN) {
        Write-Host "> $cmd"
    }
    else {
        Write-Host "> $cmd"
        Invoke-Expression $cmd
    }
}

# ---- installMissing / im ---------------------------------------------------
# Mirror of unix installMissing, Approach-A ordering:
#   1. no-op if nothing is missing.
#   2. list the missing set (hint suppressed).
#   3. unless DRY_RUN, prompt for confirmation; abort on anything but y/Y.
#   4. legacy manager bootstraps (DepRecipe) FIRST — rustup before cargo tools.
#   5. install-plan.ps1 rows in topo order.
#   6. completion / reload hint.
function installMissing {
    if ((Get-DepMissingCount) -eq 0) {
        return
    }

    listMissing noCmdInfo

    if (-not $env:DRY_RUN) {
        Write-Host ""
        $reply = Read-Host "Do you want to install the missing packages? [y/N]"
        if ($reply -notmatch '^[Yy]') {
            Write-Host "Aborting."
            return
        }
    }

    # -- 1. legacy manager bootstraps (rustup) first --
    foreach ($name in $script:DepRecipe.Keys) {
        $rec = $script:DepRecipe[$name]
        _dep_install_candidate $name $rec.Manager $rec.Package
    }

    # -- 2. manifest install-plan.ps1, topo order --
    $plan = _dep_plan_path
    if (Test-Path -LiteralPath $plan) {
        foreach ($line in (Get-Content -LiteralPath $plan)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line.StartsWith('#')) { continue }
            $parts = $line -split "`t", 3
            if ($parts.Count -lt 3) { continue }
            _dep_install_candidate $parts[0] $parts[1] $parts[2]
        }
    }

    Write-Host ""
    if (-not $env:DRY_RUN) {
        Write-Host "Installation completed."
    }
    Write-Host "Reload the shell to see the changes."
}
Set-Alias im installMissing

Export-ModuleMember -Function installMissing, listMissing, Add-DepRecipe -Alias im, lm
