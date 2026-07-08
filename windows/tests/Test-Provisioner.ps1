#!/usr/bin/env pwsh
# prototype/windows/tests/Test-Provisioner.ps1
# Plain-pwsh assertion suite for Provisioner.psm1 (no Pester dependency).
#
# Mirrors the intent of the unix tests/test-provisioner.sh: exercise the
# on-demand provisioner (`im`/`lm`) against a REAL resolver-rendered
# install-plan.ps1, driving it deterministically via DRY_RUN so nothing is
# actually installed or prompted for.
#
# Determinism strategy
# --------------------
# `_dep_install_candidate` skips any tool that is actually present on the box
# (`have`). To keep assertions deterministic regardless of what's installed on
# the test machine, the strict install-plan assertions target tools that are
# (a) present in the manifest/plan so a command can be resolved, and (b) very
# unlikely to be installed here: `helm` (winget) and `git-prism` (cargo). If
# one of those DID happen to be present, `_dep_install_candidate` would
# correctly skip it and the corresponding assertion would (legitimately) not
# find its line — so each such strict assertion is guarded by a live `have`
# check and SKIPPED (not failed) when the tool is actually present. This keeps
# the suite honest on any box: it asserts the real behaviour, softening only
# when the environment makes the assertion inapplicable.
#
# `helm needs kubectl` in the manifest, so the resolver's topo sort places
# kubectl before helm in the plan — used to assert plan ordering. The legacy
# rustup recipe (a manager bootstrap not in the manifest) must be emitted
# BEFORE any install-plan row.

$ErrorActionPreference = 'Stop'

# --- tiny assertion harness -------------------------------------------------
$script:Pass = 0
$script:Fail = 0
$script:Skip = 0

function Assert {
    param([bool] $Cond, [string] $Msg)
    if ($Cond) {
        $script:Pass++
        Write-Host "PASS: $Msg" -ForegroundColor Green
    }
    else {
        $script:Fail++
        Write-Host "FAIL: $Msg" -ForegroundColor Red
    }
}

function Skip {
    param([string] $Msg)
    $script:Skip++
    Write-Host "SKIP: $Msg" -ForegroundColor Yellow
}

# --- import the modules under test ------------------------------------------
$libDir = Join-Path $PSScriptRoot '..' 'Documents' 'PowerShell' 'dotfiles' 'lib'
$corePath = (Resolve-Path -LiteralPath (Join-Path $libDir 'Core.psm1')).Path
$provPath = (Resolve-Path -LiteralPath (Join-Path $libDir 'Provisioner.psm1')).Path
Import-Module $corePath -Force
Import-Module $provPath -Force
Write-Host "Imported: $corePath"
Write-Host "Imported: $provPath"

# Track env we mutate so the finally block can restore/clear it.
$savedDepsOutDir = $env:DEPS_OUT_DIR
$savedDryRun = $env:DRY_RUN

try {
    # --- buildInstallCmd shapes (module-internal, invoked via the module) ---
    # buildInstallCmd is not exported; call it inside the module's scope.
    $provModule = Get-Module Provisioner
    $bicWinget = & $provModule { buildInstallCmd 'winget' 'Some.Id' }
    $bicCargo  = & $provModule { buildInstallCmd 'cargo' 'ripgrep' }
    $bicNpm    = & $provModule { buildInstallCmd 'npm' 'some-pkg' }
    $bicCustom = & $provModule { buildInstallCmd 'custom' 'echo hi | cat' }
    $bicDefault = & $provModule { buildInstallCmd 'weird' 'thing' }

    Assert ($bicWinget -eq 'winget install -s winget -e --id Some.Id') "buildInstallCmd winget shape"
    Assert ($bicCargo  -eq 'cargo install ripgrep') "buildInstallCmd cargo shape"
    Assert ($bicNpm    -eq 'npm install -g some-pkg') "buildInstallCmd npm shape"
    Assert ($bicCustom -eq 'echo hi | cat') "buildInstallCmd custom shape (literal command, pipe intact)"
    Assert ($bicDefault -eq "echo 'unknown manager: weird for thing'") "buildInstallCmd default shape"

    # --- render a real install-plan.ps1 via the resolver harness ------------
    $renderScript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'lib' 'render-resolver.ps1')).Path
    $fixture = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '.chezmoidata' 'packages.yaml')).Path
    $outDir = (& $renderScript -Fixture $fixture | Select-Object -Last 1).Trim()
    Assert (Test-Path -LiteralPath (Join-Path $outDir 'install-plan.ps1')) "render-resolver produced an install-plan.ps1"

    # Point _dep_plan_path at the rendered plan.
    $env:DEPS_OUT_DIR = $outDir

    # --- lm on an empty tally prints nothing about missing ------------------
    dep_reset_missing
    $lmEmpty = (lm *>&1 | Out-String)
    Assert (-not ($lmEmpty -match 'missing')) "lm on empty tally prints nothing about missing packages"

    # --- im on an empty tally is a no-op ------------------------------------
    $imEmpty = (im *>&1 | Out-String)
    Assert ([string]::IsNullOrWhiteSpace($imEmpty)) "im on empty tally is a no-op (no output)"

    # === DETERMINISTIC block: synthetic install-plan with GUARANTEED-ABSENT ==
    # tool names ============================================================
    # Every real manifest tool may be installed on the dev box (they are on
    # this one), which makes `_dep_install_candidate`'s live-presence recheck
    # correctly suppress their install lines — so the real-manifest block below
    # can only SKIP the ordering/resolution assertions there. This synthetic
    # block stands in a hand-written install-plan.ps1 whose tool names are
    # bogus (never on PATH), so the FULL ordering/filtering/resolution path of
    # `im` is exercised deterministically on ANY box. Mirrors the unix
    # test-provisioner.sh driver1 fixture (b-before-a topo order + a custom
    # row whose SRC embeds a pipe).
    $synthDir = Join-Path ([System.IO.Path]::GetTempPath()) ("prov-synth-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $synthDir | Out-Null
    try {
        $synthPlan = Join-Path $synthDir 'install-plan.ps1'
        $planRows = @(
            '# GENERATED by run_onchange_resolve-deps — do not edit. Read by the provisioner.'
            "# format: <name>`t<manager>`t<source-or-install-command>   (topological order)"
            "dep-bogus-b`twinget`tArkanis.BogusB"
            "dep-bogus-a`twinget`tArkanis.BogusA"
            "dep-bogus-foo`tcustom`techo hi | cat"
        )
        Set-Content -LiteralPath $synthPlan -Value $planRows -Encoding utf8

        $env:DEPS_OUT_DIR = $synthDir

        dep_reset_missing
        dep_mark_missing 'dep-bogus-b'
        dep_mark_missing 'dep-bogus-a'
        dep_mark_missing 'dep-bogus-foo'
        dep_mark_missing 'dep-bogus-legacy'
        # 'dep-bogus-present' is deliberately NOT marked and NOT in the plan —
        # it stands in for a tool that is not missing at all, so it must never
        # appear in DRY_RUN output.
        # Register a legacy bootstrap (a manager NOT in the plan) directly in
        # the recipe map — Add-DepRecipe would also mark it missing, but it is
        # already marked above, so we invoke it for the recipe record.
        Add-DepRecipe 'dep-bogus-legacy' 'custom' 'echo legacy-install'

        $env:DRY_RUN = '1'
        $synthOut = (im *>&1 | Out-String)
        $synthLines = @($synthOut -split "`r?`n")

        function firstIdx {
            param([string[]] $Lines, [string] $Needle)
            for ($i = 0; $i -lt $Lines.Count; $i++) {
                if ($Lines[$i].Contains($Needle)) { return $i }
            }
            return -1
        }

        $legacyIdx = firstIdx $synthLines '> echo legacy-install'
        $bIdx      = firstIdx $synthLines '> winget install -s winget -e --id Arkanis.BogusB'
        $aIdx      = firstIdx $synthLines '> winget install -s winget -e --id Arkanis.BogusA'
        $fooIdx    = firstIdx $synthLines '> echo hi | cat'

        Assert ($legacyIdx -ge 0) "DRY_RUN im (synthetic): legacy recipe resolved + printed"
        Assert ($bIdx -ge 0) "DRY_RUN im (synthetic): install-plan row b resolved + printed"
        Assert ($aIdx -ge 0) "DRY_RUN im (synthetic): install-plan row a resolved + printed"
        Assert ($fooIdx -ge 0) "DRY_RUN im (synthetic): custom row printed verbatim, pipe intact"

        Assert ($legacyIdx -ge 0 -and $bIdx -ge 0 -and $legacyIdx -lt $bIdx) "order (synthetic): legacy bootstrap before install-plan rows"
        Assert ($bIdx -ge 0 -and $aIdx -ge 0 -and $bIdx -lt $aIdx) "order (synthetic): plan row b before a (topo order preserved from file)"

        Assert (-not ($synthOut -match 'dep-bogus-present')) "DRY_RUN im (synthetic): a tool never marked missing is never printed"
        Assert (-not ($synthOut -match 'Do you want to install')) "DRY_RUN im (synthetic): does not prompt"

        $synthLm = (lm noHint *>&1 | Out-String)
        foreach ($n in @('dep-bogus-b', 'dep-bogus-a', 'dep-bogus-foo', 'dep-bogus-legacy')) {
            Assert ($synthLm -match "(?m)^> $([regex]::Escape($n))\r?$") "lm (synthetic) lists '$n' as missing"
        }
    }
    finally {
        Remove-Item -LiteralPath $synthDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\DRY_RUN -ErrorAction SilentlyContinue
        $env:DEPS_OUT_DIR = $outDir
    }
    # === end deterministic synthetic block ==================================

    # --- seed a missing set: two topo-related manifest tools + legacy rustup -
    dep_reset_missing
    dep_mark_missing 'kubectl'
    dep_mark_missing 'helm'
    dep_mark_missing 'git-prism'
    # Legacy manager bootstrap: rustup (only marks cargo missing if cargo is
    # absent — the tally seeding above is independent of that).
    Add-DepRecipe 'cargo' 'winget' 'Rustlang.Rustup'

    # --- lm lists exactly the marked names ----------------------------------
    $lmOut = (lm noHint *>&1 | Out-String)
    $expectedNames = @('kubectl', 'helm', 'git-prism')
    foreach ($n in $expectedNames) {
        Assert ($lmOut -match "(?m)^> $([regex]::Escape($n))\r?$") "lm lists '$n' as missing"
    }
    # cargo appears only if Add-DepRecipe found it absent.
    $cargoPresent = have 'cargo'
    if ($cargoPresent) {
        Skip "cargo is present on this box — Add-DepRecipe did not mark it missing (correct)"
    }
    else {
        Assert ($lmOut -match "(?m)^> cargo\r?$") "lm lists 'cargo' as missing (Add-DepRecipe marked it, cargo absent)"
    }

    # --- DRY_RUN im: capture the ordered install output ---------------------
    $env:DRY_RUN = '1'
    $imOut = (im *>&1 | Out-String)
    $imLines = @($imOut -split "`r?`n")

    # Helper: index of the first line matching a substring, or -1.
    function firstIndexContaining {
        param([string[]] $Lines, [string] $Needle)
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            if ($Lines[$i].Contains($Needle)) { return $i }
        }
        return -1
    }

    # (a) legacy rustup recipe line — only when cargo was actually marked.
    $rustupIdx = firstIndexContaining $imLines '> winget install -s winget -e --id Rustlang.Rustup'
    if ($cargoPresent) {
        Skip "cargo present — rustup bootstrap not offered (correct); ordering asserted among plan rows only"
    }
    else {
        Assert ($rustupIdx -ge 0) "DRY_RUN im: legacy rustup bootstrap resolved + printed"
    }

    # (b) per marked-and-absent manifest tool: its expected buildInstallCmd
    #     line appears (skip if the tool happens to be installed on this box).
    $kubectlLine = '> winget install -s winget -e --id Kubernetes.kubectl'
    $helmLine    = '> winget install -s winget -e --id Helm.Helm'
    $gitPrismLine = '> cargo install git-prism'

    $kubectlIdx = firstIndexContaining $imLines $kubectlLine
    $helmIdx    = firstIndexContaining $imLines $helmLine
    $gitPrismIdx = firstIndexContaining $imLines $gitPrismLine

    if (have 'kubectl') { Skip "kubectl present on box — install line correctly suppressed" }
    else { Assert ($kubectlIdx -ge 0) "DRY_RUN im: kubectl install-plan row resolved + printed" }

    if (have 'helm') { Skip "helm present on box — install line correctly suppressed" }
    else { Assert ($helmIdx -ge 0) "DRY_RUN im: helm install-plan row resolved + printed" }

    if (have 'git-prism') { Skip "git-prism present on box — install line correctly suppressed" }
    else { Assert ($gitPrismIdx -ge 0) "DRY_RUN im: git-prism (cargo) install-plan row resolved + printed" }

    # (c) legacy recipe (rustup) emitted BEFORE any install-plan row. Compare
    #     against the earliest plan-row index we actually observed.
    if (-not $cargoPresent -and $rustupIdx -ge 0) {
        $planIdxs = @($kubectlIdx, $helmIdx, $gitPrismIdx) | Where-Object { $_ -ge 0 }
        if ($planIdxs.Count -gt 0) {
            $firstPlanIdx = ($planIdxs | Measure-Object -Minimum).Minimum
            Assert ($rustupIdx -lt $firstPlanIdx) "DRY_RUN im: legacy rustup bootstrap ($rustupIdx) precedes first install-plan row ($firstPlanIdx)"
        }
        else {
            Skip "all marked plan tools present on box — cannot assert rustup-before-plan ordering"
        }
    }

    # (d) topo ordering within the plan: kubectl precedes helm (helm needs
    #     kubectl). Only assert when both lines are present.
    if ($kubectlIdx -ge 0 -and $helmIdx -ge 0) {
        Assert ($kubectlIdx -lt $helmIdx) "DRY_RUN im: kubectl precedes helm in the plan (topo: helm needs kubectl)"
    }
    else {
        Skip "kubectl and/or helm present on box — cannot assert kubectl-before-helm plan ordering"
    }

    # (e) DRY_RUN im does not prompt.
    Assert (-not ($imOut -match 'Do you want to install')) "DRY_RUN im: does not prompt for confirmation"

    # (f) DRY_RUN im omits the 'Installation completed.' line (mirrors unix).
    Assert (-not ($imOut -match 'Installation completed')) "DRY_RUN im: omits 'Installation completed.' line"
    Assert ($imOut -match 'Reload the shell') "DRY_RUN im: still prints the reload hint"
}
finally {
    if ($null -eq $savedDepsOutDir) { Remove-Item Env:\DEPS_OUT_DIR -ErrorAction SilentlyContinue }
    else { $env:DEPS_OUT_DIR = $savedDepsOutDir }
    if ($null -eq $savedDryRun) { Remove-Item Env:\DRY_RUN -ErrorAction SilentlyContinue }
    else { $env:DRY_RUN = $savedDryRun }
}

# --- tally ------------------------------------------------------------------
Write-Host ""
Write-Host ("PASS: {0}  FAIL: {1}  SKIP: {2}" -f $script:Pass, $script:Fail, $script:Skip)
if ($script:Fail -gt 0) { exit 1 }
exit 0
