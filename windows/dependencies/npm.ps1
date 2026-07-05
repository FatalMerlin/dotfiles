# claude-code-cache-fix — local proxy that mitigates Claude Code prompt-cache regressions.
# The Linux setup runs it as a systemd user service; on Windows we lazily start it from the
# `claude` wrapper in custom.ps1 instead.
ifcmd cache-fix-proxy npm claude-code-cache-fix | Out-Null
