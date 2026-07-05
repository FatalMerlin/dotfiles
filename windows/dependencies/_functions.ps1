# Dependency helpers — PowerShell mirror of linux/.functions.zsh ifcmd/ifalias/ifpkg.
# Tracks tools that aren't installed and prints install commands on request.

$script:Missing = [ordered]@{}

# Returns the install command for a missing tool, given its source and package id.
function buildInstallCmd {
    param([string] $source, [string] $package)
    switch ($source) {
        'winget'  { return "winget install -s winget -e --id $package" }
        'cargo'   { return "cargo install $package" }
        'npm'     { return "npm install -g $package" }
        'custom'  { return $package }  # `package` is the literal install command
        default   { return "echo 'unknown source: $source for package: $package'" }
    }
}

# Tests for a command on PATH. Records the install recipe if absent.
# Usage: ifcmd <name> <source> <package>
#   ifcmd cache-fix-proxy npm claude-code-cache-fix
function ifcmd {
    param([string] $name, [string] $source, [string] $package)
    if (Get-Command $name -ErrorAction SilentlyContinue) { return $true }
    $script:Missing[$name] = @{ Source = $source; Package = $package }
    return $false
}

# Cache the winget package list once — Get-WinGetPackage is ~3.7s per call.
$script:WinGetPackages = $null
function _ensureWinGetPackages {
    if ($null -ne $script:WinGetPackages) { return }
    if (-not (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue)) {
        $script:WinGetPackages = @{}
        return
    }
    $script:WinGetPackages = @{}
    foreach ($pkg in (Get-WinGetPackage)) {
        $script:WinGetPackages[$pkg.Id] = $true
    }
}

# Tests for a winget-installed package by Id. Records the install recipe if absent.
# Usage: ifpkg <wingetId>
#   ifpkg Microsoft.VisualStudioCode
function ifpkg {
    param([string] $id)
    _ensureWinGetPackages
    if ($script:WinGetPackages.ContainsKey($id)) { return $true }
    $script:Missing[$id] = @{ Source = 'winget'; Package = $id }
    return $false
}

# Defines an alias if the underlying command is installed.
# Usage: ifalias <aliasName> <cmd> <source> [<package>] [<execName>]
#   ifalias k kubectl winget Kubernetes.kubectl
function ifalias {
    param(
        [string] $aliasName,
        [string] $cmd,
        [string] $source,
        [string] $package = $null,
        [string] $execName = $null
    )
    if (-not $package)  { $package  = $cmd }
    if (-not $execName) { $execName = $cmd }

    if (ifcmd $execName $source $package) {
        if ($aliasName -ne $cmd) {
            Set-Item -Path "function:global:$aliasName" -Value { & $cmd @args }.GetNewClosure()
        }
        return $true
    }
    return $false
}

# Prints a short summary of missing tools.
function reportMissing {
    if ($script:Missing.Count -eq 0) { return }
    Write-Host "$($script:Missing.Count) missing tools detected" -ForegroundColor Yellow
    Write-Host "> listMissing (lm)" -ForegroundColor DarkGray
}

# Lists missing tools with their install commands.
function listMissing {
    param([switch] $NoInstallHelp)
    if ($script:Missing.Count -eq 0) {
        Write-Host "No missing tools." -ForegroundColor Green
        return
    }
    Write-Host "Missing tools:" -ForegroundColor Yellow
    foreach ($name in $script:Missing.Keys) {
        $entry = $script:Missing[$name]
        $cmd = buildInstallCmd $entry.Source $entry.Package
        Write-Host "  $name" -ForegroundColor Cyan
        Write-Host "    $cmd" -ForegroundColor DarkGray
    }
    if (-not $NoInstallHelp) {
        Write-Host ""
        Write-Host "Run 'installMissing' to install all of them." -ForegroundColor DarkGray
    }
}
Set-Alias lm listMissing

# Installs everything currently in $Missing.
function installMissing {
    if ($script:Missing.Count -eq 0) {
        Write-Host "Nothing to install." -ForegroundColor Green
        return
    }
    foreach ($name in @($script:Missing.Keys)) {
        $entry = $script:Missing[$name]
        $cmd = buildInstallCmd $entry.Source $entry.Package
        Write-Host "Installing $name ..." -ForegroundColor Cyan
        Write-Host "  > $cmd" -ForegroundColor DarkGray
        Invoke-Expression $cmd
    }
}
Set-Alias im installMissing
