#!/usr/bin/env bash
# need-check_test.sh -- need-check.sh over prepared session logs: each need
# kind accepted and worded, every other need refused (a free-text decision
# above all), the need read only from the latest surface evidence, and the
# stored need checked against its seal.
#
# Usage: bash skills/coordinate/scripts/need-check_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
CL="$HERE/coord-log.sh"
N=0
# check <need>: a session whose latest surface evidence names it, then the check
check() {
    N=$((N + 1))
    S="coordinate-roadmap-feat-n$N-20260926T080000Z"
    log_new "$S" "$(roadmap_vars feat)"
    log_to "$S" start surface
    log_evidence "$S" surface "$(jq -nc --arg n "$1" '{surfaced: "blocker", need: $n}')"
    log_to "$S" surface surface_check
    OUT=$(bash "$HERE/need-check.sh" --session "$S" 2>"$T/err"); RC=$?
    seen "$OUT" >/dev/null
}
w() { printf '%s' "$OUT" | cut -d' ' -f1-2; }
cell() { koto context get "$S" coord/need.json | jq -r .cell; }

check "credential NPM_TOKEN"
eq "a credential is accepted" "0 accepted credential" "$RC $(w)"
eq "a credential's cell" "credential: NPM_TOKEN" "$(cell)"
eq "the stored need checks against its seal" "$(koto context get "$S" coord/need.json)" \
    "$(bash "$CL" check --session "$S" --state surface_check --sealed "$(printf '%s' "$OUT" | tr ' ' '\n' | sed -n 's/^keyseal:/sealed:/p')" --key coord/need.json)"
check "reserved-step release https://github.com/acme/widgets/issues/40"
eq "a reserved step on an issue link is accepted" "accepted reserved-step" "$(w)"
eq "a reserved step's cell" "release https://github.com/acme/widgets/issues/40, reserved for a person" "$(cell)"
check "reserved-step merge acme/widgets#12"
eq "a reserved step on owner/repo#n is accepted" "accepted reserved-step" "$(w)"
check "access acme/secret"
eq "access to a repository is accepted" "accepted access" "$(w)"

for bad in "decide whether to ship" "please decide whether to ship" "credential" "credential two words" \
    "reserved-step deploy #12" "reserved-step merge somewhere" "access not-a-repo" "access acme/widgets extra" \
    "your call on the pin" "" "reserved-step release"; do
    check "$bad"
    eq "refused: [$bad]" "0 refused" "$RC $(w | cut -d' ' -f1)"
done
check "$(printf 'credential A\nB')"
eq "refused: a need over two lines" "refused" "$(w | cut -d' ' -f1)"

# Only the latest surface evidence counts.
N=$((N + 1)); S="coordinate-roadmap-feat-n$N-20260926T080000Z"
log_new "$S" "$(roadmap_vars feat)"
log_to "$S" start surface
log_evidence "$S" surface '{"surfaced":"blocker","need":"credential OLD"}'
log_evidence "$S" surface '{"surfaced":"blocker","need":"decide whether to ship"}'
log_to "$S" surface surface_check
OUT=$(bash "$HERE/need-check.sh" --session "$S" 2>/dev/null)
eq "the latest surface evidence is the one read" "refused" "$(w | cut -d' ' -f1)"
bash "$HERE/need-check.sh" >/dev/null 2>&1; eq "no session is usage" 64 "$?"

tokens_ok need-check
done_tests need-check
