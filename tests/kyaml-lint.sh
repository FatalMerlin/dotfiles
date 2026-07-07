#!/usr/bin/env -S bash -eEuo pipefail
# prototype/tests/kyaml-lint.sh — enforce KYAML (flow-style YAML) on our data files.
# Strict mode via the shebang: applied on direct execution, ignored when sourced.
#
# Checks per file:
#   (1) must parse as valid YAML (`yq -e '.'`)
#   (2) must be flow-style — reject block mappings (`key:` at line-end), block
#       sequences (`- ` entries), and trailing commas in flow collections.
# Comments (`# ...`) and double-quoted string spans are neutralized before the
# flow-style check (quoted spans replaced by a sentinel, not blanked — see
# strip_strings), so `#`, `:`, `-`, or `,` inside a comment or a quoted value
# never trip a false positive, including an empty-string value (`key: ""`).
# Skips `*/.github/workflows/*.yml|*.yaml` — GitHub Actions workflow YAML is
# the one allowed block-YAML exception (tooling/ecosystem convention there).
# Rationale: no mature standalone KYAML formatter exists (open Q3) — lint only.

rc=0

# strip_strings: replaces double-quoted spans with a sentinel `_` (not a blank)
# so `:`/`-`/`,` inside string values can't be mistaken for block/flow syntax
# markers. Substituting rather than blanking matters for empty-string values:
# `key: ""` must strip to `key: _` (still has a value token, correctly passes
# the flow check), not `key: ` (which would look like a bare block-mapping key
# and false-positive against the `key:$` pattern below). A genuine block value
# (`key:` with nothing after it, block style) has no quotes to strip and still
# correctly trips the check.
strip_strings() { sed -E 's/"([^"\\]|\\.)*"/_/g'; }

for f in "$@"; do
  case "$f" in
    */.github/workflows/*.yml|*/.github/workflows/*.yaml) continue ;;
  esac

  if [ ! -f "$f" ]; then
    echo "kyaml: $f — not a regular file"; rc=1; continue
  fi

  # (1) must parse as YAML
  if ! yq -e '.' "$f" >/dev/null 2>&1; then
    echo "kyaml: $f — not valid YAML"; rc=1; continue
  fi

  # (2) flow-style: no block constructs / trailing commas (ignore comments and
  # quoted strings). The first grep -n prefixes each non-comment line with its
  # original "N:" line number; that prefix rides through strip_strings, so the
  # second grep's patterns anchor past "^[0-9]+:" rather than "^" directly.
  bad=$(grep -nv '^[[:space:]]*#' "$f" | strip_strings | grep -E \
      -e '^[0-9]+:[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*$' \
      -e '^[0-9]+:[[:space:]]*-[[:space:]]' \
      -e ',[[:space:]]*[]}]' || true)
  if [ -n "$bad" ]; then
    echo "kyaml: $f — block construct or trailing comma:"
    echo "$bad"
    rc=1
  fi
done

exit $rc
