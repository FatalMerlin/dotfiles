#!/usr/bin/env -S bash -eEuo pipefail
# `set -eEuo pipefail` is restated explicitly below (not just left to the
# shebang): every caller in this test suite invokes this file as
# `bash lib/render-resolver.sh ...` rather than executing it directly, and
# `bash <file>` never parses/honours the file's own shebang line (shebang
# dispatch is a kernel execve() feature) — so without this line the flags
# were silently inert and a failing `chezmoi apply` (Task 20a's cycle-error
# case) would NOT abort the script before it echoed a stale deps.sh path.
set -eEuo pipefail
# prototype/unix/tests/lib/render-resolver.sh <fixture-packages.yaml>
#
# Seed a temp chezmoi source dir with the fixture manifest + the real
# .chezmoitemplates, run a REAL `chezmoi apply` against a throwaway HOME (so
# the run_onchange_resolve-deps.sh.tmpl script actually executes the way it
# would on a real machine), and echo the path to the produced deps.sh.
#
# NB: this script's source root is derived from its own location ($0), not
# `git rev-parse --show-toplevel`. This worktree's .git file points at a
# Windows D:/ path that WSL cannot resolve, so `git` fails with "not a git
# repository" when this harness runs under WSL/zsh at test time. Deriving the
# root from $0 sidesteps git entirely. This script lives at
# prototype/unix/tests/lib/render-resolver.sh, so the unix source root
# (prototype/unix) is two levels up from its directory.
#
# Faithfulness note: an earlier version of this harness rendered the resolver
# via `chezmoi execute-template` with the two template files concatenated by
# hand. That was unfaithful to production — it masked a real bug where
# `{{ template "resolveRef" ... }}` (a `{{ define }}`'d sub-template) is
# invisible to `real chezmoi apply`, because a define'd sub-template is only
# visible within the SAME template execution, and run_onchange templates are
# each their own execution; `.chezmoitemplates/*.tmpl` files are only
# auto-loaded as callable named templates via `includeTemplate`, not
# `{{ template }}`. A real `chezmoi apply` is the only way to catch that
# class of bug, so this harness now does a real apply into a sandboxed HOME.
#
# Windows-test-only interpreter shim: real deployments run this resolver on
# actual Linux/WSL, where the kernel execs `run_onchange_*.sh` directly via
# its shebang. The native-Windows chezmoi binary used to run these tests in
# git-bash has no such kernel shebang support — chezmoi ships built-in
# Windows interpreter defaults for .pl/.py/.ps1/.rb/.nu but NOT .sh, so it
# falls through to a raw CreateProcess call and dies with "%1 is not a valid
# Win32 application". A throwaway per-sandbox chezmoi.toml mapping the `sh`
# extension to `bash` (via [interpreters.sh]) routes execution through
# git-bash's bash.exe instead. This is purely a test-environment
# accommodation for this platform/test-runner combination, not a product
# behavior change.
fixture="$1"
root="$(cd "$(dirname "$0")/../.." && pwd)"

resolver_tmpl="$root/run_onchange_resolve-deps.sh.tmpl"
if [ ! -f "$resolver_tmpl" ]; then
  echo "render-resolver.sh: $resolver_tmpl does not exist yet" \
    "(created in Task 7 — this harness cannot run end-to-end until then)" >&2
  exit 1
fi

sb=$(mktemp -d)
home="$sb/home"
src="$sb/src"
# $out (created below) holds the produced deps.sh copied out of the sandbox
# HOME; it must survive past this script's exit for the caller to read, so it
# is deliberately NOT included in this trap. Only the sandbox ($sb, covering
# both the throwaway HOME and the throwaway chezmoi source) is cleaned here.
trap 'rm -rf "$sb"' EXIT

mkdir -p "$home" "$src/.chezmoidata" "$src/.chezmoitemplates"
cp "$fixture" "$src/.chezmoidata/packages.yaml"
cp "$root/.chezmoidata/defaults.yaml" "$src/.chezmoidata/defaults.yaml"
cp "$root/.chezmoitemplates/"* "$src/.chezmoitemplates/"
cp "$resolver_tmpl" "$src/"

cfg="$sb/chezmoi.toml"
cat > "$cfg" <<'EOF'
[interpreters.sh]
    command = "bash"
EOF

# Real apply into the sandbox HOME. With an empty [data] table, @-refs in the
# manifest resolve against .chezmoidata/defaults.yaml (merged in automatically
# by chezmoi as template data). The run_onchange script this renders to
# executes as part of apply, writing deps.sh under $HOME/.config/dotfiles.
HOME="$home" chezmoi apply --source "$src" --config "$cfg" --no-tty >&2

out=$(mktemp -d)
cp "$home/.config/dotfiles/deps.sh" "$out/deps.sh"
# install-plan.sh is a sibling output of the same resolver run (Task 20a) —
# copy it out alongside deps.sh when present so callers can derive its path
# via `$(dirname "$deps")/install-plan.sh` without a second apply.
[ -f "$home/.config/dotfiles/install-plan.sh" ] && cp "$home/.config/dotfiles/install-plan.sh" "$out/install-plan.sh"

echo "$out/deps.sh"
