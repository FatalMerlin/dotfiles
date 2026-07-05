# Winget-installed tools referenced by the PowerShell profile.
# These declarations exist so `listMissing` accurately reports what's needed.

# NOTE: Several of these tools are invoked unconditionally in the profile BEFORE
# this file is sourced (e.g. `oh-my-posh init`, `op completion`, `zoxide init`,
# `gh completion`, `kubectl completion`). If the tool is missing, the profile
# will error before reaching the dependency loader. The declarations below still
# document the dependency for `listMissing`; gating the actual invocations would
# require either reordering the profile or adding inline guards.

# cmd -> @{ Id = <winget id>; Why = <one-line note> }
$wingetTools = [ordered]@{
    'oh-my-posh' = @{ Id = 'JanDeDobbeleer.OhMyPosh';     Why = 'prompt theme; `oh-my-posh init` at top of profile' }
    'op'         = @{ Id = 'AgileBits.1Password.CLI';     Why = '1Password CLI; `op completion` + `tl` ThinLinc wrapper' }
    'zoxide'     = @{ Id = 'ajeetdsouza.zoxide';          Why = 'smarter cd; `zoxide init` at bottom of profile' }
    'gh'         = @{ Id = 'GitHub.cli';                  Why = 'GitHub CLI; `gh completion`' }
    'kubectl'    = @{ Id = 'Kubernetes.kubectl';          Why = 'k8s CLI; `kubectl completion` + `k` / `ktx` aliases' }
    'code'       = @{ Id = 'Microsoft.VisualStudioCode';  Why = 'VS Code; used by `cc` and `$env:KUBE_EDITOR`' }
    'fzf'        = @{ Id = 'junegunn.fzf';                Why = 'fuzzy finder; used by `wgsi` (already guarded inline)' }
    'magick'     = @{ Id = 'ImageMagick.ImageMagick';     Why = 'ImageMagick; used by `Get-ImageDimension` and `square`' }
    'ffmpeg'     = @{ Id = 'BtbN.FFmpeg.LGPL.Shared';     Why = 'used by `mp4towebm`' }
    'sccache'    = @{ Id = 'Mozilla.sccache';             Why = 'compiler cache; wired in via `$env:RUSTC_WRAPPER` when present' }
    'helm'       = @{ Id = 'Helm.Helm';                   Why = 'k8s package manager; `helm completion` + `h` alias' }
    'python'     = @{ Id = 'Python.Python.3.14';          Why = 'Python 3.14; used by various scripts and tools' }
}

foreach ($cmd in $wingetTools.Keys) {
    ifcmd $cmd winget $wingetTools[$cmd].Id | Out-Null
}
