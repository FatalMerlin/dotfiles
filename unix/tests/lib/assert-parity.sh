#!/usr/bin/env -S bash -eEuo pipefail
# prototype/unix/tests/lib/assert-parity.sh <old-snapshot> <new-snapshot>
#
# Diff two capture-wiring.sh snapshots. FAILS (exit 1) if any wiring present
# in OLD is missing from NEW — that's a regression, the new (generated)
# artifact must reproduce every wiring effect the old shell had.
#
# Extra lines present only in NEW are reported as warnings, not failures: the
# resolver-generated deps.sh may legitimately consolidate or restate wiring
# (e.g. a single guarded PATH append vs. several old fragments) without that
# being a parity break.
old="$1"
new="$2"

missing=$(comm -23 <(sort -u "$old") <(sort -u "$new") || true)
extra=$(  comm -13 <(sort -u "$old") <(sort -u "$new") || true)

if [ -n "$extra" ]; then
  echo "WARN: new-only wiring:"
  echo "$extra"
fi

if [ -n "$missing" ]; then
  echo "FAIL: wiring lost vs old:"
  echo "$missing"
  exit 1
fi

echo "parity OK"
