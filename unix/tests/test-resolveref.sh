#!/usr/bin/env bash
# Test for the resolveRef body-file template (.chezmoitemplates/resolveRef.tmpl).
#
# resolveRef resolves "@a.b.c" manifest references against a chezmoi data
# tree via nested `index` lookups, and passes non-"@" strings through
# unchanged. It is a BODY-ONLY template (no `{{ define }}` wrapper) called via
# `{{ includeTemplate "resolveRef.tmpl" (dict "ref" ... "data" $) }}`.
#
# `includeTemplate` only loads from a real chezmoi source directory's
# `.chezmoitemplates/` during a real `chezmoi apply` — not via
# `chezmoi execute-template` with inline strings. So this test builds a
# throwaway chezmoi source (real .chezmoitemplates/resolveRef.tmpl + a probe
# run_onchange script that calls it) and does a real sandboxed `chezmoi apply`,
# then asserts on the probe's output. This is the same faithful-apply pattern
# tests/lib/render-resolver.sh uses for the full resolver.
#
# Same Windows-test-only interpreter shim as tests/lib/render-resolver.sh: a
# throwaway per-sandbox chezmoi.toml routes .sh execution through bash, since
# the native-Windows chezmoi binary used here has no built-in `sh` interpreter
# default (unlike real Linux/WSL deployments, where the kernel execs the
# shebang directly). Test-environment accommodation only.
set -eEuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/../.chezmoitemplates" && pwd)/resolveRef.tmpl"

fail=0
# check NAME ACTUAL EXPECTED — fails loudly with the actual value on mismatch.
check() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — expected '$3', got '$2'"
    fail=1
  fi
}

sb=$(mktemp -d)
home="$sb/home"
src="$sb/src"
trap 'rm -rf "$sb"' EXIT

mkdir -p "$home" "$src/.chezmoidata" "$src/.chezmoitemplates"
cp "$TPL" "$src/.chezmoitemplates/resolveRef.tmpl"

# Known value for the @-ref to resolve against, via .chezmoidata/defaults.yaml
# (merged into template data by chezmoi automatically — no [data] needed).
cat > "$src/.chezmoidata/defaults.yaml" <<'EOF'
{
  linux: { work: { gitlabHost: "gl.example.com" } }
}
EOF

# Probe run_onchange script: writes two lines to a known path — one via the
# @-ref, one via a literal passthrough — so the test can assert on both in a
# single real apply.
cat > "$src/run_onchange_probe.sh.tmpl" <<'EOF'
#!/usr/bin/env -S bash -eEuo pipefail
OUT="${PROBE_OUT_DIR:-$HOME/.config/dotfiles}/probe.txt"
mkdir -p "$(dirname "$OUT")"
{
  printf '%s\n' '{{ includeTemplate "resolveRef.tmpl" (dict "ref" "@linux.work.gitlabHost" "data" $) }}'
  printf '%s\n' '{{ includeTemplate "resolveRef.tmpl" (dict "ref" "literal-x" "data" $) }}'
} > "$OUT"
EOF

cfg="$sb/chezmoi.toml"
cat > "$cfg" <<'EOF'
[interpreters.sh]
    command = "bash"
EOF

HOME="$home" chezmoi apply --source "$src" --config "$cfg" --no-tty >&2

probe="$home/.config/dotfiles/probe.txt"
line1="$(sed -n '1p' "$probe")"
line2="$(sed -n '2p' "$probe")"

check "@-ref nested lookup (real apply)" "$line1" "gl.example.com"
check "literal passthrough (real apply)" "$line2" "literal-x"

exit "$fail"
