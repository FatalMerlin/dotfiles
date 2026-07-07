#!/usr/bin/env -S bash -eEuo pipefail
# prototype/tests/feature-lint.sh <packages.yaml>...
# Strict mode via the shebang: applied on direct execution, ignored when sourced.
#
# Assert every `feature:` referenced in a dependency manifest exists as a key
# under `.features` in the manifest's sibling `defaults.yaml`. Why: a gated env
# entry is emitted only when its feature resolves true at apply-time
# (`@features.<feature>`), and a TYPO in the feature name (e.g. `feature:
# "wrok"`) resolves to nothing — so the gated wiring is silently, permanently
# omitted with no error. That silent-closed failure is exactly what this lint
# catches. Runs in the pre-commit hook + CI, mirroring the KYAML gate.
#
# A feature key may be nested (dotted), e.g. `linux.tmux` -> `.features.linux.tmux`,
# matching how the resolver expands `@features.<feature>`. Existence is checked
# by path: a missing path yields yq `null`; a present flag yields its boolean
# value (`false`/`true`) — so `null` (and only `null`) means "not defined".

rc=0
for pkg in "$@"; do
  if [ ! -f "$pkg" ]; then
    echo "feature-lint: $pkg — not a regular file"; rc=1; continue
  fi
  defaults="$(dirname "$pkg")/defaults.yaml"
  if [ ! -f "$defaults" ]; then
    echo "feature-lint: $defaults — missing (expected sibling of $pkg)"; rc=1; continue
  fi

  # Every `feature:` value anywhere in the manifest (env maps carry it as
  # `{ value, feature }`); recursive descent finds them regardless of nesting.
  while IFS= read -r feat; do
    [ -n "$feat" ] || continue
    if [ "$(yq ".features.$feat" "$defaults" 2>/dev/null)" = "null" ]; then
      echo "feature-lint: $pkg references feature '$feat' not defined under .features in $defaults"
      rc=1
    fi
  done < <(yq '[.. | select(tag == "!!map" and has("feature")) | .feature] | .[]' "$pkg" 2>/dev/null | sort -u)
done

exit $rc
