# Custom-install tools and wrappers that don't fit a single package manager.

#region cache-fix-proxy lifecycle + claude wrapper
$script:CacheFixProxyPort = 9801
$script:CacheFixProxyUrl  = "http://127.0.0.1:$($script:CacheFixProxyPort)"

function Test-CacheFixProxyUp {
    try {
        $null = Invoke-WebRequest -Uri "$($script:CacheFixProxyUrl)/health" `
            -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Start-CacheFixProxy {
    if (Test-CacheFixProxyUp) { return }

    # Prefer the .ps1 shim. Start-Process with -Redirect* forces CreateProcess, which
    # only accepts PE binaries — so we wrap the shim via pwsh.exe -File.
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

function Stop-CacheFixProxy {
    $conn = Get-NetTCPConnection -LocalPort $script:CacheFixProxyPort `
        -State Listen -ErrorAction SilentlyContinue
    if (-not $conn) {
        Write-Host "cache-fix-proxy is not running." -ForegroundColor DarkGray
        return
    }
    Stop-Process -Id $conn.OwningProcess -Force
    Write-Host "Stopped cache-fix-proxy (PID $($conn.OwningProcess))." -ForegroundColor Green
}

function claude {
    $claudeExe = (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue).Source
    if (-not $claudeExe) {
        Write-Error "claude not found on PATH. Install via: npm install -g @anthropic-ai/claude-code"
        return
    }
    if (Get-Command cache-fix-proxy -ErrorAction SilentlyContinue) {
        Start-CacheFixProxy
        $env:ANTHROPIC_BASE_URL = $script:CacheFixProxyUrl
    }
    & $claudeExe @args
}
#endregion
