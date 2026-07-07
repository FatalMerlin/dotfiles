# prototype/tests/PSScriptAnalyzerSettings.psd1
# PSScriptAnalyzer settings for the Windows PowerShell dependency engine
# (prototype/windows/Documents/PowerShell/dotfiles/**). Consumed explicitly:
#   Invoke-ScriptAnalyzer -Path <file> -Settings prototype/tests/PSScriptAnalyzerSettings.psd1
# (kept in tests/ — a repo-tooling dir OUTSIDE the chezmoi sources — so it is
# never deployed into $HOME.)
#
# Each excluded rule below is OFF by deliberate design, not laziness. With these
# four suppressed, the PS lib/engine is analyzer-clean; anything else PSSA flags
# is a real finding. The Task-23 static-check step wires this in.
@{
    ExcludeRules = @(
        # Write-Host is the repo's chosen mechanism for colored, user-facing
        # console output (the pre-migration profile used it for reportMissing /
        # listMissing; Core.psm1's log/info/warn/etc. and the provisioner's
        # im/lm listings continue it). These are UI, not data on the pipeline.
        'PSAvoidUsingWriteHost',

        # cache_fix_proxy_wrapper (SetupHooks.psm1) intentionally defines
        # $global:CacheFixProxyPort / $global:CacheFixProxyUrl. The wrapper is a
        # module-scoped setup hook whose emitted global functions (claude /
        # Start-/Stop-/Test-CacheFixProxy) must share that config at call time;
        # $global: is how they persist past the hook and resolve across the
        # session, mirroring the old dot-sourced custom.ps1. By design.
        'PSAvoidGlobalVars',

        # installMissing (Provisioner.psm1) runs the resolved install command
        # for each missing tool via Invoke-Expression — the command text comes
        # from our own install-plan / recipe map, not untrusted input. This is
        # the faithful port of the old _functions.ps1 installMissing behavior.
        'PSAvoidUsingInvokeExpression',

        # The modules are authored/committed as UTF-8 WITHOUT a BOM (only
        # non-ASCII content is em-dashes in comments). This matches the unix
        # engine and the generated deps.ps1 (which is asserted BOM-free); PS 7
        # reads UTF-8-no-BOM natively. A BOM would diverge from that standard.
        'PSUseBOMForUnicodeEncodedFile'
    )
}
