#!/usr/bin/env bash
set -eEuo pipefail
DIR="$(cd "$(dirname "$0")/../dot_config/dotfiles/lib" && pwd)"

# A strict bash script that sources the harness and then fails must:
#  (a) exit non-zero, (b) print an ERROR line naming the failing command to stderr.
cat > /tmp/_h_probe.sh <<EOF
#!/usr/bin/env -S bash -eEuo pipefail
. "$DIR/core.sh"; . "$DIR/harness.sh"
false
echo "should not reach here"
EOF
chmod +x /tmp/_h_probe.sh
if out=$(/tmp/_h_probe.sh 2>&1); then echo "FAIL: probe should have failed"; exit 1; fi
echo "$out" | grep -q 'ERROR at line' || { echo "FAIL: no ERROR line: $out"; exit 1; }
echo "$out" | grep -q 'should not reach here' && { echo "FAIL: continued past failure"; exit 1; }

# require_args dies when too few args.
cat > /tmp/_h_args.sh <<EOF
#!/usr/bin/env -S bash -eEuo pipefail
. "$DIR/core.sh"; . "$DIR/harness.sh"
_USAGE="\$0 <a> <b>"; require_args 2 "\$#"
echo ok
EOF
chmod +x /tmp/_h_args.sh
# NB: capture via command substitution rather than piping into grep — under
# `set -o pipefail` (in effect for this test script itself), a pipeline's exit
# status is non-zero whenever ANY stage (here, the intentionally-failing
# /tmp/_h_args.sh) exits non-zero, regardless of whether `grep -q` matched.
# That trips this script's own `set -e` before the `||` fallback can run.
args_out=$(/tmp/_h_args.sh one 2>&1) || true
echo "$args_out" | grep -q 'expected at least 2' || { echo "FAIL: require_args: $args_out"; exit 1; }
args_ok=$(/tmp/_h_args.sh one two)
echo "$args_ok" | grep -q '^ok$' || { echo "FAIL: require_args happy path: $args_ok"; exit 1; }
echo "all ok"
