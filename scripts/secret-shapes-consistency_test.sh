#!/usr/bin/env bash
# secret-shapes-consistency_test.sh -- the secret shapes `shirabe question
# raise` refuses are the ones the public-content check refuses.
#
# scripts/lib/secret-shapes.ere is the list built into the binary.
# scripts/ablation/check-public-content.sh keeps its own copy as one
# alternation in its `secret` pattern class, since a normal run's files and
# the ablation harness change in separate pull requests. A shape added to one
# and not the other is the failure this exists for: one check would pass
# content the other refuses.
#
# Cases:
#   the public-content check's `secret` class is found, once
#   it equals the .ere file's patterns, in order, joined with `|`
#   the comparison fails on a planted extra shape (the control, so a green
#     run is not a comparison that always agrees)
#
# Usage: bash scripts/secret-shapes-consistency_test.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERE="$ROOT/scripts/lib/secret-shapes.ere"
CHECK="$ROOT/scripts/ablation/check-public-content.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "ok   $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL $1"; }

# The .ere file's patterns joined into one alternation.
joined() {
    local out="" shape
    while IFS= read -r shape || [ -n "$shape" ]; do
        case "$shape" in ''|'#'*) continue ;; esac
        out="${out:+$out|}$shape"
    done < "$1"
    printf '%s' "$out"
}

# The alternation in the check's `'secret|secret shape|...'` line.
in_check() {
    local line rest found=0 out=""
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *"'secret|secret shape|"*"'")
                rest="${line#*\'secret|secret shape|}"
                out="${rest%\'}"
                found=$((found + 1))
                ;;
        esac
    done < "$1"
    [ "$found" -eq 1 ] || return 1
    printf '%s' "$out"
}

if have=$(in_check "$CHECK"); then
    pass "the public-content check's secret class is found once"
else
    fail "the public-content check has no single 'secret|secret shape|...' class"
    have=""
fi

want=$(joined "$ERE")
if [ -n "$want" ] && [ "$have" = "$want" ]; then
    pass "the check's secret class equals scripts/lib/secret-shapes.ere"
else
    fail "the check's secret class differs from scripts/lib/secret-shapes.ere: check [$have], file [$want]"
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cp "$ERE" "$T/planted.ere"
printf '%s\n' 'PLANTED[0-9]{8}' >> "$T/planted.ere"
if [ "$(joined "$T/planted.ere")" != "$have" ]; then
    pass "a planted extra shape makes them differ"
else
    fail "a planted extra shape still compares equal"
fi

echo "secret-shapes-consistency_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
