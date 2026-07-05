# Cargo-installed tools.

if (-not (ifcmd cargo winget Rustlang.Rustup)) { return }

#region git-prism — agent-optimized git data for LLM agents
# `git-prism hooks install` is deliberately skipped on Windows: it writes a deprecated
# settings.json schema (clobbering the file each run) and the deployed bash hook doesn't
# run correctly under Claude Code on native Windows. We register the MCP server only
# — that's the bigger win and works independently of the hook integration.
if (ifcmd git-prism cargo git-prism) {
    # Idempotent: claude mcp add errors loudly on duplicate names; swallow that noise.
    & claude mcp add git-prism -- git-prism serve 2>&1 | Out-Null
}
#endregion
