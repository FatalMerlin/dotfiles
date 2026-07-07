# prototype/windows/Documents/PowerShell/dotfiles/lib/Core.psm1
# PowerShell mirror of the POSIX `core.sh` for the dotfiles dependency engine.
#
# IMPORTED BY: the generated `deps.ps1` startup artifact, the PowerShell profile,
# and the apply-time resolver-run. Because the interactive profile imports it,
# it must be:
#   - Safe to import REPEATEDLY (`Import-Module -Force` re-runs the body; every
#     definition here is idempotent — re-assigning module-scoped state and
#     re-declaring functions has no harmful side effects).
#   - Free of process-killing strict-mode / error-preference side effects (it
#     never sets `$ErrorActionPreference = 'Stop'` at module scope, never throws
#     at import time), mirroring core.sh's strict-mode-safety contract.
#
# Naming: the lowercase_underscore function names (`have`, `ifpath_append`,
# `cache_completion`, `dep_mark_missing`, `log_debug`, ...) are intentional, for
# line-level parity with the unix `deps.sh`. PSScriptAnalyzer's approved-verb
# rule (PSUseApprovedVerbs) only fires on `Verb-Noun` names, so these lowercase
# names do not trip it. The two cross-boundary accessors (`Get-DepMissing`,
# `Get-DepMissingCount`) use the approved `Get` verb.

# ---- color / NO_COLOR ------------------------------------------------------
# Honour NO_COLOR (https://no-color.org): any non-empty value disables colour.
# No TTY detection needed — Write-Host handles redirection; when colour is off
# the log helpers simply omit -ForegroundColor.
$script:DepNoColor = [bool]$env:NO_COLOR

# ---- logging (-> console) --------------------------------------------------
# Mirrors core.sh, which logs to stderr for human visibility. Here we use
# Write-Host (the repo profile already uses Write-Host for reportMissing /
# listMissing; the analyzer gate excludes PSAvoidUsingWriteHost).
#
# NB: the debug-level logger is `log_debug`, NOT `debug` — matching core.sh's
# contract that `debug`/`debug_measure_*` are the interactive timing UI and must
# not be clobbered.

# log <msg> — prints "HH:mm:ss <msg>".
function log {
    param([Parameter(ValueFromRemainingArguments = $true)] $Message)
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host ("{0} {1}" -f $ts, ($Message -join ' '))
}

# Internal: emit a "<timestamp> <tag> <msg>" line, colouring only the tag and
# only when colour is enabled. Mirrors the unix `log "<color>[tag]<reset> $*"`.
function _dep_log_tagged {
    param(
        [string] $Tag,
        [string] $Color,
        [Parameter(ValueFromRemainingArguments = $true)] $Message
    )
    $ts = Get-Date -Format 'HH:mm:ss'
    $msg = ($Message -join ' ')
    if ($script:DepNoColor) {
        Write-Host ("{0} {1} {2}" -f $ts, $Tag, $msg)
    }
    else {
        Write-Host ("{0} " -f $ts) -NoNewline
        Write-Host $Tag -ForegroundColor $Color -NoNewline
        Write-Host (" {0}" -f $msg)
    }
}

# Tags mirror core.sh EXACTLY: [info] [warn] [fail] [ ok ] [dbg ].
function info    { param([Parameter(ValueFromRemainingArguments = $true)] $Message) _dep_log_tagged '[info]' 'Blue'   $Message }
function warn    { param([Parameter(ValueFromRemainingArguments = $true)] $Message) _dep_log_tagged '[warn]' 'Yellow' $Message }
function error   { param([Parameter(ValueFromRemainingArguments = $true)] $Message) _dep_log_tagged '[fail]' 'Red'    $Message }
function success { param([Parameter(ValueFromRemainingArguments = $true)] $Message) _dep_log_tagged '[ ok ]' 'Green'  $Message }

# log_debug <msg> — prints only when $env:DOTFILES_DEBUG -eq 'true'; always
# returns without error otherwise (mirrors core.sh `... ; return 0`).
function log_debug {
    param([Parameter(ValueFromRemainingArguments = $true)] $Message)
    if ($env:DOTFILES_DEBUG -eq 'true') {
        _dep_log_tagged '[dbg ]' 'DarkGray' $Message
    }
    return
}

# ---- presence --------------------------------------------------------------
# The single presence primitive the generated deps.ps1 self-guards with.
function have {
    param([string] $Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# ---- PATH helpers (dir-guarded, case-insensitive dedup, idempotent) --------
# Operate on $env:PATH (';'-separated). $env:PATH is process-global, so mutating
# it from module scope affects the whole process — matching the unix export.

# Internal: is $Dir already present in $env:PATH (case-insensitive)?
function _dep_path_contains {
    param([string] $Dir)
    $entries = $env:PATH -split ';'
    foreach ($e in $entries) {
        if ($e -and ($e -ieq $Dir)) { return $true }
    }
    return $false
}

# ifpath_prepend <dir> — prepend $Dir to PATH if it's an existing directory and
# not already present. No-op otherwise.
function ifpath_prepend {
    param([string] $Dir)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return }
    if (_dep_path_contains $Dir) { return }
    $env:PATH = "$Dir;" + $env:PATH
}

# ifpath_append <dir> — append $Dir to PATH if it's an existing directory and
# not already present. No-op otherwise.
function ifpath_append {
    param([string] $Dir)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return }
    if (_dep_path_contains $Dir) { return }
    $env:PATH = $env:PATH + ";$Dir"
}

# ifpath <dir> — alias for append (mirrors core.sh `ifpath` == `ifpath_append`).
function ifpath {
    param([string] $Dir)
    ifpath_append $Dir
}

# ---- completion cache ------------------------------------------------------
# PS DEVIATION from unix `cache_completion`: the unix version dot-sources the
# cache internally. A PowerShell module function cannot dot-source into the
# caller's / global scope (dot-sourcing inside a function scopes to that
# function). So this function instead CACHES and RETURNS the fresh cache-file
# path ([string]); the RESOLVER (a later chunk) does the global dot-source, e.g.:
#     $__c = cache_completion op op completion powershell; if ($__c) { . $__c }
# so the dot-source runs at deps.ps1 top level (global scope).
#
# Behaviour mirror of core.sh: resolve the binary via Get-Command .Source;
# regenerate the cache when it is missing OR the binary is newer than the cache;
# on generation failure remove the cache and return $null.
function cache_completion {
    param(
        [string] $Name,
        [Parameter(ValueFromRemainingArguments = $true)] $CmdArgs
    )
    $bin = (Get-Command $Name -ErrorAction SilentlyContinue).Source
    if (-not $bin) { return $null }

    $cacheDir = Join-Path $env:LOCALAPPDATA 'dotfiles/completions'
    $cache = Join-Path $cacheDir "$Name.ps1"

    $needsRegen = $true
    if (Test-Path -LiteralPath $cache -PathType Leaf) {
        $binTime = (Get-Item -LiteralPath $bin).LastWriteTime
        $cacheTime = (Get-Item -LiteralPath $cache).LastWriteTime
        # Regenerate only when the binary is strictly newer than the cache.
        $needsRegen = ($binTime -gt $cacheTime)
    }

    if ($needsRegen) {
        try {
            if (-not (Test-Path -LiteralPath $cacheDir -PathType Container)) {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            }
            $exe = $CmdArgs[0]
            $rest = @()
            if ($CmdArgs.Count -gt 1) {
                $rest = $CmdArgs[1..($CmdArgs.Count - 1)]
            }
            & $exe @rest | Out-String | Set-Content -LiteralPath $cache -Encoding utf8
        }
        catch {
            Remove-Item -LiteralPath $cache -ErrorAction SilentlyContinue
            return $null
        }
    }

    return $cache
}

# ---- missing-report primitives ---------------------------------------------
# Mirror dep_reset_missing / dep_mark_missing / dep_report_missing. The backing
# store is module-scoped so the later provisioner chunk's `lm`/`im` in the
# profile can read it across the module boundary via Get-DepMissing.
$script:DepMissing = [System.Collections.Generic.List[string]]::new()

# dep_reset_missing — clear the tally.
function dep_reset_missing {
    $script:DepMissing.Clear()
}

# dep_mark_missing <name> — record a missing declared tool.
function dep_mark_missing {
    param([string] $Name)
    $script:DepMissing.Add($Name)
}

# dep_report_missing — if any tools are missing, warn a line mirroring core.sh.
# Returns nothing when the tally is empty.
function dep_report_missing {
    if ($script:DepMissing.Count -le 0) { return }
    $list = ($script:DepMissing -join ' ')
    warn ("{0} declared tool(s) missing: {1} — run 'im' to install" -f $script:DepMissing.Count, $list)
}

# Get-DepMissing — return the current missing-tool list (cross-boundary reader).
function Get-DepMissing {
    return $script:DepMissing
}

# Get-DepMissingCount — return the current missing-tool count.
function Get-DepMissingCount {
    return $script:DepMissing.Count
}

Export-ModuleMember -Function `
    log, info, warn, error, success, log_debug, `
    have, `
    ifpath_prepend, ifpath_append, ifpath, `
    cache_completion, `
    dep_reset_missing, dep_mark_missing, dep_report_missing, `
    Get-DepMissing, Get-DepMissingCount
