# prototype/windows/Documents/PowerShell/dotfiles/hooks/SetupHooks.psm1
# Named `setup:` hooks for the declarative dependency resolver — PowerShell mirror
# of the POSIX `setup-hooks.sh`.
#
# The manifest is declarative — gate/check/env/path/aliases/completion cover the
# general shape of "how to wire up a tool once it's present". Some tools need
# genuinely irreducible bespoke logic (a one-off bootstrap, a config the tool
# insists on, etc.) that doesn't fit any declarative field. `setup:` is the escape
# hatch: a manifest entry names a hook (`setup: "<hook>"`), and the resolver emits
# a bare call to the correspondingly-named function here, inside the tool's
# presence-guard. Keep this file as the LAST resort — a growing hook count is a
# signal a new declarative field is missing, not that this file should grow.
#
# IMPORTED (best-effort) by the generated deps.ps1 preamble via
# `Import-Module -Force`. Like Core.psm1 it must be safe to import repeatedly and
# free of process-killing strict-mode / error-preference side effects: a failing
# hook must not tear down the shell that imported it. It therefore contains ONLY
# function definitions (no top-level execution) and never sets
# `$ErrorActionPreference = 'Stop'` at module scope.
#
# Shipped hooks: git_prism_mcp, cache_fix_proxy_wrapper.
#
# NB: there is deliberately NO zoxide `cd`-rebind hook. The default PowerShell
# `cd` is an AllScope alias to Set-Location that CANNOT be removed or overridden
# from a module function's scope (even via SessionState.InvokeScript into global
# — "The AllScope option cannot be removed from the alias 'cd'"). Only top-level
# code can rebind it. So the manifest instead runs `zoxide init powershell
# --cmd cd`, whose emitted init (dot-sourced at deps.ps1 TOP level) makes zoxide
# define `cd` itself — the idiomatic zoxide setup. Trade-off vs the old profile
# (`zoxide init` + manual `Set-Alias cd z`): `--cmd cd` renames the short `z`
# command to `cd`/`cdi`, so the bare `z` name is gone; `cd` (the primary
# interface) is preserved and now zoxide-backed.

# ---- git_prism_mcp ----------------------------------------------------------
# Mirror of the unix `git_prism_mcp` (cargo git-prism block): register git-prism
# as a Claude Code MCP server. Silent + best-effort — a harmless re-add if it is
# already present, and a non-zero exit must not surface as a terminating error.
function git_prism_mcp {
    & claude mcp add git-prism -- git-prism serve 2>&1 | Out-Null
}

# ---- cache_fix_proxy_wrapper ------------------------------------------------
# Port of dependencies/custom.ps1's cache-fix-proxy lifecycle + `claude` wrapper.
# The Linux setup runs claude-code-cache-fix as a systemd user service; on
# Windows it is lazily started by the `claude` wrapper defined here.
#
# Everything is defined in GLOBAL scope on purpose. This hook is itself a module
# function invoked from the generated deps.ps1: any `$script:`-scoped state (vars
# or functions) would be scoped to THIS module and vanish / misresolve once the
# hook returns, so the `claude` wrapper the user actually calls at the prompt
# would be gone. Declaring the four functions and their shared config vars as
# `$global:` makes them persist in the session after the hook call, matching what
# custom.ps1 achieved by defining them at file scope in a dot-sourced file.
#
# The scriptblocks reference `$global:CacheFixProxyPort` / `$global:CacheFixProxyUrl`
# directly (not closures) so they resolve the shared config at CALL time.
function cache_fix_proxy_wrapper {
    $global:CacheFixProxyPort = 9801
    $global:CacheFixProxyUrl  = "http://127.0.0.1:$($global:CacheFixProxyPort)"

    Set-Item -Path function:global:Test-CacheFixProxyUp -Value {
        try {
            $null = Invoke-WebRequest -Uri "$($global:CacheFixProxyUrl)/health" `
                -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
            return $true
        } catch {
            return $false
        }
    }

    Set-Item -Path function:global:Start-CacheFixProxy -Value {
        if (Test-CacheFixProxyUp) { return }

        # Prefer the .ps1 shim. Start-Process with -Redirect* forces CreateProcess,
        # which only accepts PE binaries — so we wrap the shim via pwsh.exe -File.
        $proxyPath = (Get-Command 'cache-fix-proxy.ps1' -ErrorAction SilentlyContinue).Source
        if (-not $proxyPath) {
            $proxyPath = (Get-Command cache-fix-proxy -ErrorAction SilentlyContinue).Source
        }
        if (-not $proxyPath) {
            Write-Warning "cache-fix-proxy not installed; cannot start proxy."
            return
        }

        $logDir = "$env:LOCALAPPDATA\cache-fix-proxy"
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

        Start-Process -FilePath 'pwsh.exe' `
            -ArgumentList '-NoProfile', '-NonInteractive', '-File', $proxyPath, 'server' `
            -WindowStyle Hidden `
            -RedirectStandardOutput "$logDir\proxy.log" `
            -RedirectStandardError  "$logDir\proxy.err.log" | Out-Null

        # Poll up to ~3s for readiness.
        for ($i = 0; $i -lt 15 -and -not (Test-CacheFixProxyUp); $i++) {
            Start-Sleep -Milliseconds 200
        }
        if (-not (Test-CacheFixProxyUp)) {
            Write-Warning "cache-fix-proxy did not become ready within 3s. Check $logDir\proxy.err.log."
        }
    }

    Set-Item -Path function:global:Stop-CacheFixProxy -Value {
        $conn = Get-NetTCPConnection -LocalPort $global:CacheFixProxyPort `
            -State Listen -ErrorAction SilentlyContinue
        if (-not $conn) {
            Write-Host "cache-fix-proxy is not running." -ForegroundColor DarkGray
            return
        }
        Stop-Process -Id $conn.OwningProcess -Force
        Write-Host "Stopped cache-fix-proxy (PID $($conn.OwningProcess))." -ForegroundColor Green
    }

    Set-Item -Path function:global:claude -Value {
        $claudeExe = (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue).Source
        if (-not $claudeExe) {
            Write-Error "claude not found on PATH. Install via: npm install -g @anthropic-ai/claude-code"
            return
        }
        if (Get-Command cache-fix-proxy -ErrorAction SilentlyContinue) {
            Start-CacheFixProxy
            $env:ANTHROPIC_BASE_URL = $global:CacheFixProxyUrl
        }
        & $claudeExe @args
    }
}

Export-ModuleMember -Function git_prism_mcp, cache_fix_proxy_wrapper
