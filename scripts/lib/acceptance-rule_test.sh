#!/usr/bin/env bash
# acceptance-rule_test.sh -- the interim acceptance rule, called directly.
#
# Covers:
#   acceptance_rule_decide  allows a minted seat at reviewer, a coordinator
#                           naming an existing session, and a person at owner
#                           from a terminal; refuses with each rule id in turn
#                           (author, authority-kind, person-required,
#                           unminted-seat, unknown-session, no-terminal,
#                           not-higher), and an attempt that breaks several
#                           rules by the first in the documented order
#   acceptance_rule_live    no header holds; nothing to accept counts; an
#                           item with no judgment is unaccepted; an accept of
#                           the current digest counts and of an older one is
#                           changed since acceptance; a decline holds naming
#                           its identity; a hand-written accept the rule
#                           refuses (an unminted reviewer, the author, a seat
#                           used twice, a person line) never counts; the third
#                           decline of one sorted path set prints
#                           decline-limit
#
# Usage: bash scripts/lib/acceptance-rule_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
# shellcheck source=acceptance-rule.sh
. "$HERE/acceptance-rule.sh"

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "[$3] lacks [$2]" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "[$3] holds [$2]" ;; *) ok "$1" ;; esac; }

W=$(mktemp -d) || { echo "FAIL: could not create a temporary directory"; exit 1; }
trap 'rm -rf "$W"' EXIT

A=agent:run
# rule <args...>: the rule id a decision names, or allow.
rule() { acceptance_rule_decide "$@" | awk '{ print ($1 == "allow") ? "allow" : $2 }'; }

echo "--- acceptance_rule_decide"
eq "a minted seat at reviewer" allow "$(rule agent:run/accept-1 agent reviewer accept "$A" false false true false)"
eq "a coordinator naming an existing session" allow "$(rule agent:coord agent coordinator accept "$A" false false false true)"
eq "a person at owner from a terminal" allow "$(rule person:pat person owner accept "$A" false true false false)"
eq "a minted seat may decline" allow "$(rule agent:run/accept-1 agent reviewer decline "$A" false false true false)"
eq "the author accepting" author "$(rule "$A" agent reviewer accept "$A" false false true true)"
eq "the author overruling" author "$(rule "$A" agent coordinator overrule "$A" false false false true reviewer)"
eq "an agent at owner" authority-kind "$(rule agent:x agent owner accept "$A" false false true true)"
eq "a person at coordinator" authority-kind "$(rule person:p person coordinator accept "$A" false true false false)"
eq "an unknown authority" authority-kind "$(rule agent:x agent boss accept "$A" false false true true)"
eq "an agent where a person is required" person-required "$(rule agent:run/accept-1 agent reviewer accept "$A" true false true false)"
eq "an unminted agent at reviewer" unminted-seat "$(rule agent:other agent reviewer accept "$A" false false false false)"
eq "an agent at coordinator naming no session" unknown-session "$(rule agent:none agent coordinator accept "$A" false false false false)"
eq "a person without a terminal" no-terminal "$(rule person:p person owner accept "$A" false false false false)"
eq "an overrule at the same authority" not-higher "$(rule agent:run/accept-2 agent reviewer overrule "$A" false false true false reviewer)"
eq "an overrule by a coordinator over a reviewer" allow "$(rule agent:coord agent coordinator overrule "$A" false false false true reviewer)"
# Several rules broken: the first in order refuses.
eq "the author at owner: author first" author "$(rule "$A" agent owner accept "$A" true false false false)"
eq "an agent at owner where a person is required: authority-kind first" authority-kind "$(rule agent:x agent owner accept "$A" true false false false)"
eq "an unminted agent where a person is required: person-required first" person-required "$(rule agent:x agent reviewer accept "$A" true false false false)"
has "a refusal carries a reason" "refuse unminted-seat an agent at reviewer" "$(acceptance_rule_decide agent:o agent reviewer accept "$A" false false false false)"

echo "--- acceptance_rule_live"
hdr() { printf '{"event":"header","author":"%s","person_required":false}\n' "$A"; }
seat() { printf '{"event":"seat","identity":"%s"}\n' "$1"; }
judge() { printf '{"event":"%s","identity":"%s","kind":"%s","authority":"%s","files":[{"path":"%s","digest":"%s"}]}\n' "$1" "$2" "${2%%:*}" "$3" "$4" "$5"; }
printf 't.sh\tD1\n' > "$W/cur"
: > "$W/none"

printf '{"event":"note"}\n' > "$W/l"
eq "no header holds" "held	no header" "$(acceptance_rule_live "$W/l" "$W/cur" | cut -c 1-14)"
hdr > "$W/l"
eq "nothing to accept counts" counted "$(acceptance_rule_live "$W/l" "$W/none")"
eq "no judgment: unaccepted" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur")"
{ hdr; seat agent:run/accept-1; judge accept agent:run/accept-1 reviewer t.sh D1; } > "$W/l"
eq "an accept of the current digest counts" counted "$(acceptance_rule_live "$W/l" "$W/cur")"
printf 't.sh\tD2\n' > "$W/cur2"
eq "an accept of an older digest" "held	changed since acceptance t.sh" "$(acceptance_rule_live "$W/l" "$W/cur2")"
{ hdr; seat agent:run/accept-1; judge decline agent:run/accept-1 reviewer t.sh D1; } > "$W/l"
eq "a decline holds naming its identity" "held	declined t.sh by agent:run/accept-1" "$(acceptance_rule_live "$W/l" "$W/cur")"
eq "a decline of an older digest: unaccepted" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur2")"
{ hdr; judge accept agent:other reviewer t.sh D1; } > "$W/l"
eq "a hand-written accept by an unminted reviewer never counts" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur")"
{ hdr; judge accept "$A" reviewer t.sh D1; } > "$W/l"
eq "a hand-written accept by the author never counts" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur")"
{ hdr; seat agent:run/accept-1; judge accept agent:run/accept-1 reviewer t.sh D0; judge accept agent:run/accept-1 reviewer t.sh D1; } > "$W/l"
eq "a seat used twice: its second accept never counts" "held	changed since acceptance t.sh" "$(acceptance_rule_live "$W/l" "$W/cur")"
{ hdr; judge accept person:pat owner t.sh D1; } > "$W/l"
eq "a person line never counts without a verified terminal" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur")"
printf '%s\n' '{"event":"accept","identity":"agent:c","kind":"agent","authority":"coordinator","session_exists":true,"files":[{"path":"t.sh","digest":"D1"}]}' > "$W/c"
{ hdr; cat "$W/c"; } > "$W/l"
eq "a coordinator line naming an existing session counts" counted "$(acceptance_rule_live "$W/l" "$W/cur")"
{ hdr; for n in 1 2 3; do seat "agent:run/accept-$n"; judge decline "agent:run/accept-$n" reviewer t.sh "D$n"; done; } > "$W/l"
has "the third decline of one path set: decline-limit" "held	decline-limit t.sh" "$(acceptance_rule_live "$W/l" "$W/none")"
{ hdr; for n in 1 2; do seat "agent:run/accept-$n"; judge decline "agent:run/accept-$n" reviewer t.sh "D$n"; done; } > "$W/l"
hasnt "two declines: no decline-limit" "decline-limit" "$(acceptance_rule_live "$W/l" "$W/none")"
printf 'a.sh\tA1\nb.sh\tB1\n' > "$W/two"
{ hdr; seat agent:run/accept-1
  printf '%s\n' '{"event":"accept","identity":"agent:run/accept-1","kind":"agent","authority":"reviewer","files":[{"path":"a.sh","digest":"A1"},{"path":"b.sh","digest":"B1"}]}'; } > "$W/l"
eq "one accept covering two files counts both" counted "$(acceptance_rule_live "$W/l" "$W/two")"

echo
echo "acceptance-rule: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
