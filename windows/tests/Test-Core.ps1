#!/usr/bin/env pwsh
# prototype/windows/tests/Test-Core.ps1
# Plain-pwsh assertion suite for Core.psm1 (no Pester dependency).
#
# Mirrors the intent of the unix tests/test-core-lib.sh: verify the presence
# primitive, PATH helpers, missing-report tally, completion cache, debug gating
# and NO_COLOR handling of the PS core library. Prints a PASS/FAIL tally and
# `exit 1` on any failure.

$ErrorActionPreference = 'Stop'

# --- tiny assertion harness -------------------------------------------------
$script:Pass = 0
$script:Fail = 0

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

# --- import the module under test -------------------------------------------
$modulePath = Join-Path $PSScriptRoot '..' 'Documents' 'PowerShell' 'dotfiles' 'lib' 'Core.psm1'
$modulePath = (Resolve-Path -LiteralPath $modulePath).Path
Import-Module $modulePath -Force
Write-Host "Imported: $modulePath"

# --- have -------------------------------------------------------------------
# pwsh is guaranteed present (we're running under it).
Assert (have 'pwsh') "have returns true for a real command (pwsh)"
Assert (-not (have 'definitely-not-a-real-cmd-xyz123')) "have returns false for a bogus command"
Assert ((have 'pwsh') -is [bool]) "have returns a real [bool]"

# --- ifpath_append (idempotent, dir-guarded) --------------------------------
$savedPath = $env:PATH
try {
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dep-core-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    ifpath_append $tmpDir
    $countAfterFirst = ($env:PATH -split ';' | Where-Object { $_ -ieq $tmpDir }).Count
    Assert ($countAfterFirst -eq 1) "ifpath_append adds a real temp dir once"
    Assert ($env:PATH.TrimEnd(';').EndsWith($tmpDir)) "ifpath_append appends at the end"

    ifpath_append $tmpDir
    $countAfterSecond = ($env:PATH -split ';' | Where-Object { $_ -ieq $tmpDir }).Count
    Assert ($countAfterSecond -eq 1) "ifpath_append is idempotent (no duplicate)"

    # case-insensitive dedup: an upper-cased variant must not be re-added
    ifpath_append ($tmpDir.ToUpper())
    $countAfterCase = ($env:PATH -split ';' | Where-Object { $_ -ieq $tmpDir }).Count
    Assert ($countAfterCase -eq 1) "ifpath_append dedups case-insensitively"

    # non-existent dir is a no-op
    $bogusDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dep-core-nope-" + [guid]::NewGuid().ToString('N'))
    $before = $env:PATH
    ifpath_append $bogusDir
    Assert ($env:PATH -eq $before) "ifpath_append no-ops for a non-existent dir"

    # --- ifpath_prepend -----------------------------------------------------
    $env:PATH = $savedPath
    $prependDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dep-core-pre-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $prependDir -Force | Out-Null
    ifpath_prepend $prependDir
    Assert ($env:PATH.StartsWith("$prependDir;")) "ifpath_prepend prepends at the front"
    ifpath_prepend $prependDir
    $preCount = ($env:PATH -split ';' | Where-Object { $_ -ieq $prependDir }).Count
    Assert ($preCount -eq 1) "ifpath_prepend is idempotent"

    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $prependDir -Recurse -Force -ErrorAction SilentlyContinue
}
finally {
    $env:PATH = $savedPath
}

# --- missing tally ----------------------------------------------------------
dep_reset_missing
Assert ((Get-DepMissingCount) -eq 0) "dep_reset_missing yields count 0"

dep_mark_missing 'alpha'
dep_mark_missing 'beta'
Assert ((Get-DepMissingCount) -eq 2) "dep_mark_missing twice yields count 2"
$missing = Get-DepMissing
Assert ($missing -contains 'alpha') "missing list contains 'alpha'"
Assert ($missing -contains 'beta') "missing list contains 'beta'"

$reportThrew = $false
try { dep_report_missing } catch { $reportThrew = $true }
Assert (-not $reportThrew) "dep_report_missing runs without throwing (non-empty)"

dep_reset_missing
$reportEmptyThrew = $false
try { dep_report_missing } catch { $reportEmptyThrew = $true }
Assert (-not $reportEmptyThrew) "dep_report_missing runs without throwing (empty)"

# --- cache_completion -------------------------------------------------------
# bogus tool -> $null
$bogusCache = cache_completion 'definitely-not-a-real-cmd-xyz123' 'definitely-not-a-real-cmd-xyz123' '--version'
Assert ($null -eq $bogusCache) "cache_completion returns null for a bogus tool"

# real tool: emit a marker the cache file must contain. Use pwsh to print 'ok'.
$realCache = cache_completion 'pwsh' 'pwsh' '-NoProfile' '-Command' "'ok'"
Assert ($null -ne $realCache) "cache_completion returns a path for a real tool"
Assert (Test-Path -LiteralPath $realCache -PathType Leaf) "cache_completion cache file exists"
$content = Get-Content -LiteralPath $realCache -Raw
Assert ($content -match 'ok') "cache_completion cache content contains 'ok'"

# second call within the same mtime must not error and returns the same path
$secondCallThrew = $false
$realCache2 = $null
try { $realCache2 = cache_completion 'pwsh' 'pwsh' '-NoProfile' '-Command' "'ok'" } catch { $secondCallThrew = $true }
Assert (-not $secondCallThrew) "cache_completion second call does not error"
Assert ($realCache2 -eq $realCache) "cache_completion second call returns the same path"

# cleanup the temp cache dir we created
$cacheDir = Join-Path $env:LOCALAPPDATA 'dotfiles/completions'
$cacheFile = Join-Path $cacheDir 'pwsh.ps1'
Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue

# --- log_debug gating -------------------------------------------------------
$savedDebug = $env:DOTFILES_DEBUG
try {
    Remove-Item Env:DOTFILES_DEBUG -ErrorAction SilentlyContinue
    $dbgOffThrew = $false
    try { log_debug 'should be silent' } catch { $dbgOffThrew = $true }
    Assert (-not $dbgOffThrew) "log_debug does not error when DOTFILES_DEBUG unset"

    $env:DOTFILES_DEBUG = 'true'
    $dbgOnThrew = $false
    try { log_debug 'should print' } catch { $dbgOnThrew = $true }
    Assert (-not $dbgOnThrew) "log_debug does not error when DOTFILES_DEBUG=true"
}
finally {
    if ($null -eq $savedDebug) {
        Remove-Item Env:DOTFILES_DEBUG -ErrorAction SilentlyContinue
    }
    else {
        $env:DOTFILES_DEBUG = $savedDebug
    }
}

# --- NO_COLOR ---------------------------------------------------------------
# Re-import with NO_COLOR set so the module-load-time $script:DepNoColor picks
# it up, then assert the colour-off path in info doesn't throw.
$savedNoColor = $env:NO_COLOR
try {
    $env:NO_COLOR = '1'
    Import-Module $modulePath -Force
    $infoThrew = $false
    try { info 'x' } catch { $infoThrew = $true }
    Assert (-not $infoThrew) "info runs without throwing under NO_COLOR"
}
finally {
    if ($null -eq $savedNoColor) {
        Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue
    }
    else {
        $env:NO_COLOR = $savedNoColor
    }
    Import-Module $modulePath -Force
}

# --- tally ------------------------------------------------------------------
Write-Host ""
Write-Host ("Results: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
