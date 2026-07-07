#!/usr/bin/env bash
# Test for run_onchange_resolve-deps.sh.tmpl — FEATURE-gated env vars.
#
# An `env` value may be either a plain string (always exported) or a map
# { value, feature }. The map form is a per-host feature toggle: the export is
# emitted ONLY when `.features.<feature>` is true for this host (resolved at
# apply-time from chezmoi data). The tool itself stays tracked everywhere
# (its `have`-guard is always emitted) — only the work-specific env var toggles
# per host. Feature flags default false in the public defaults.yaml and are
# flipped true per host from the private [data] channel. This is the backlog-#1
# env-gating cleanup: work vars are gated uniformly by an explicit per-host
# feature, not by fragile hostname-suffix matching.
#
# The OFF case renders via tests/lib/render-resolver.sh (uses the repo's real
# defaults.yaml, where features.work is false). The ON case can't use that
# harness (it would need to mutate the shared default), so it does its own
# sandboxed `chezmoi apply` with a throwaway defaults.yaml that sets
# features.work: true. Both are real applies (see render-resolver.sh's header
# for why execute-template is unfaithful here).
#
# zsh -n legs SKIP when zsh is absent (git-bash) — the controller runs them in WSL.
#
# shellcheck disable=SC2016  # grep patterns are intentionally single-quoted literals.
set -eEuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
U="$(cd "$HERE/.." && pwd)"
CHEZMOI="$(command -v chezmoi)"

fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

render_default() {  # OFF case: real defaults.yaml (features.work=false)
  fx="$(mktemp)"; printf '%s\n' "$1" > "$fx"
  bash "$HERE/lib/render-resolver.sh" "$fx"; rm -f "$fx"
}

# render_with_feature_on <packages-yaml>  — sandbox apply with features.work: true.
render_with_feature_on() {
  sb="$(mktemp -d)"; home="$sb/home"; src="$sb/src"
  mkdir -p "$home" "$src/.chezmoitemplates" "$src/.chezmoidata"
  cp "$U/.chezmoitemplates/"* "$src/.chezmoitemplates/"
  cp "$U/run_onchange_resolve-deps.sh.tmpl" "$src/"
  printf '%s\n' "$1" > "$src/.chezmoidata/packages.yaml"
  # defaults.yaml identical to repo's but with features.work flipped true.
  printf '%s\n' '{ features: { work: true, linux: { tmux: true, yakuake: false } }, linux: { work: { gitlabHost: "gl.work.example" } } }' \
    > "$src/.chezmoidata/defaults.yaml"
  cfg="$sb/chezmoi.toml"; printf '[interpreters.sh]\n    command = "bash"\n' > "$cfg"
  HOME="$home" "$CHEZMOI" apply --source "$src" --config "$cfg" --no-tty >&2
  out="$(mktemp -d)"; cp "$home/.config/dotfiles/deps.sh" "$out/deps.sh"
  rm -rf "$sb"
  echo "$out/deps.sh"
}

GLAB_FIXTURE='{ packages: { brew: { glab: { env: { GITLAB_HOST: { value: "@linux.work.gitlabHost", feature: "work" } } } } } }'

run_bash_tests() {
  echo "--- bash section ---"

  # OFF: glab tracked (have-guard present) but GITLAB_HOST NOT exported.
  deps_off="$(render_default "$GLAB_FIXTURE")"
  rc=0; grep -q 'if have glab; then' "$deps_off" || rc=$?
  check "feature OFF: glab still tracked (have-guard present)" "$rc"
  rc=0; if grep -q 'export GITLAB_HOST=' "$deps_off"; then rc=1; fi
  check "feature OFF: GITLAB_HOST NOT exported" "$rc"
  rc=0; grep -q 'else dep_mark_missing glab; fi' "$deps_off" || rc=$?
  check "feature OFF: glab has no outer gate wrapper (tracked, not host-gated)" "$rc"

  # ON: glab tracked AND GITLAB_HOST exported inside the guard.
  deps_on="$(render_with_feature_on "$GLAB_FIXTURE")"
  rc=0; grep -q 'if have glab; then' "$deps_on" || rc=$?
  check "feature ON: glab tracked" "$rc"
  rc=0
  awk '/if have glab/{g=1} g&&/export GITLAB_HOST="gl.work.example"/{print "in"} /else dep_mark_missing glab/{g=0}' "$deps_on" | grep -q in || rc=$?
  check "feature ON: GITLAB_HOST exported (resolved value) inside the guard" "$rc"

  # Plain string env still unconditional (k9s).
  deps_plain="$(render_default '{ packages: { brew: { k9s: { env: { K9S_FEATURE_GATE_NODE_SHELL: "true" } } } } }')"
  rc=0
  awk '/if have k9s/{g=1} g&&/export K9S_FEATURE_GATE_NODE_SHELL="true"/{print "in"} /else dep_mark_missing k9s/{g=0}' "$deps_plain" | grep -q in || rc=$?
  check "plain string env still exported unconditionally" "$rc"

  rc=0; bash -n "$deps_off" || rc=$?; check "OFF fixture: bash -n clean" "$rc"
  rc=0; bash -n "$deps_on" || rc=$?; check "ON fixture: bash -n clean" "$rc"

  DEPS_OFF="$deps_off"; DEPS_ON="$deps_on"
}

run_zsh_tests() {
  echo "--- zsh section ---"
  if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: zsh absent — controller runs zsh -n in WSL"; return 0
  fi
  rc=0; zsh -n "$DEPS_OFF" || rc=$?; check "zsh -n clean (OFF)" "$rc"
  rc=0; zsh -n "$DEPS_ON" || rc=$?; check "zsh -n clean (ON)" "$rc"
}

main() { run_bash_tests; run_zsh_tests; exit "$fail"; }
main "$@"
