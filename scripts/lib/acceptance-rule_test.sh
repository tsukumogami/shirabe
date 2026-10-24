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
#                           decline-limit; a coordinator's acceptance counts
#                           only while its session is in the sessions file,
#                           so a session cleaned up since stops it counting,
#                           while its decline or overrule stays in force
#   person lines            count only with a tag that checks under the key;
#                           an untagged, re-edited or wrongly tagged line, or
#                           any line without the key, never counts
#   overrules               a coordinator over a reviewer holds the item as
#                           overruled; one at the same authority, naming no
#                           acceptance, or naming a later one never counts;
#                           afterwards an acceptance below the overruling's
#                           authority leaves it held and one at or above it
#                           counts again
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
printf 'c\n' > "$W/sessions"
eq "a coordinator line naming a session that exists now counts" counted "$(acceptance_rule_live "$W/l" "$W/cur" "$W/sessions")"
: > "$W/nosessions"
eq "a coordinator line whose session is gone never counts, whatever it stores" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur" "$W/nosessions")"
eq "without a sessions file no coordinator line counts" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur")"
printf 'run\n' > "$W/runsession"
{ hdr; printf '%s\n' '{"event":"accept","identity":"agent:run","kind":"agent","authority":"coordinator","files":[{"path":"t.sh","digest":"D1"}]}'; } > "$W/l"
eq "the run's own session as a coordinator never counts" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur" "$W/runsession")"

echo "--- person lines and their tag"
printf 'k3y-for-tests\n' > "$W/key"
# person_line <event> <id> <authority> <digest> <tag|good|none>
person_line() {
    local base tag
    base=$(jq -nc --arg ev "$1" --arg id "$2" --arg a "$3" --arg d "$4" \
        '{event: $ev, id: $id, identity: "person:pat", kind: "person", authority: $a, files: [{path: "t.sh", digest: $d}], terminal: true}')
    case "$5" in
        good) tag=$(printf '%s' "$base" | jq -cS 'del(.tag)' | acceptance_rule_tag "$W/key") ;;
        none) printf '%s\n' "$base"; return ;;
        *) tag="$5" ;;
    esac
    printf '%s' "$base" | jq -c --arg t "$tag" '. + {tag: $t}'
}
{ hdr; person_line accept accept-2 owner D1 good; } > "$W/l"
eq "a person line whose tag checks counts" counted "$(acceptance_rule_live "$W/l" "$W/cur" "" "$W/key")"
eq "without the key no person line counts" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur")"
{ hdr; person_line accept accept-2 owner D1 good | jq -c '.authority = "reviewer"'; } > "$W/l"
eq "a person line edited after tagging never counts" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur" "" "$W/key")"
{ hdr; person_line accept accept-2 owner D1 none; } > "$W/l"
eq "an untagged person line never counts, its stored terminal flag ignored" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur" "" "$W/key")"
{ hdr; person_line accept accept-2 owner D1 0000; } > "$W/l"
eq "a person line with a wrong tag never counts" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur" "" "$W/key")"
eq "acceptance_rule_tag is stable for one text and key" "$(printf 'x' | acceptance_rule_tag "$W/key")" "$(printf 'x' | acceptance_rule_tag "$W/key")"
hasnt "acceptance_rule_tag depends on the key" "$(printf 'x' | acceptance_rule_tag "$W/key")" "$(printf 'other\n' > "$W/key2"; printf 'x' | acceptance_rule_tag "$W/key2")"

echo "--- overrules"
seated_accept() { seat "$1"; printf '{"event":"accept","id":"%s","identity":"%s","kind":"agent","authority":"reviewer","files":[{"path":"t.sh","digest":"%s"}]}\n' "$2" "$1" "$3"; }
coord() { printf '{"event":"%s","id":"%s","identity":"agent:c","kind":"agent","authority":"coordinator","target":"%s","files":[{"path":"t.sh","digest":"%s"}]}\n' "$1" "$2" "${3:-}" "${4:-D1}"; }
{ hdr; seated_accept agent:run/accept-1 accept-3 D1; coord overrule overrule-4 accept-3; } > "$W/l"
eq "a coordinator's overrule of a reviewer's acceptance holds it as overruled" "held	overruled t.sh by agent:c" "$(acceptance_rule_live "$W/l" "$W/cur" "$W/sessions")"
eq "the same overrule whose session is gone stays in force" "held	overruled t.sh by agent:c" "$(acceptance_rule_live "$W/l" "$W/cur" "$W/nosessions")"
eq "and without a sessions file it stays in force too" "held	overruled t.sh by agent:c" "$(acceptance_rule_live "$W/l" "$W/cur")"
{ hdr; seated_accept agent:run/accept-1 accept-3 D1
  printf '%s\n' '{"event":"overrule","id":"overrule-4","identity":"agent:run/accept-2","kind":"agent","authority":"coordinator","target":"accept-3","files":[]}'; } > "$W/l"
eq "a seat's name passed off as a coordinator's overrule never counts" counted "$(acceptance_rule_live "$W/l" "$W/cur" "$W/nosessions")"
{ hdr; coord decline decline-2 "" D1; } > "$W/l"
eq "a coordinator's decline whose session is gone stays in force" "held	declined t.sh by agent:c" "$(acceptance_rule_live "$W/l" "$W/cur" "$W/nosessions")"
{ hdr; for n in 1 2 3; do coord decline "decline-$n" "" "D$n"; done; } > "$W/l"
has "a gone coordinator's declines still count toward decline-limit" "held	decline-limit t.sh" "$(acceptance_rule_live "$W/l" "$W/none" "$W/nosessions")"
{ hdr; printf '%s\n' '{"event":"decline","identity":"agent:run","kind":"agent","authority":"coordinator","files":[{"path":"t.sh","digest":"D1"}]}'; } > "$W/l"
eq "the run's own session declining as a coordinator never counts" "held	unaccepted t.sh" "$(acceptance_rule_live "$W/l" "$W/cur" "$W/nosessions")"
{ hdr; seated_accept agent:run/accept-1 accept-3 D1; seat agent:run/accept-2
  printf '%s\n' '{"event":"overrule","id":"overrule-5","identity":"agent:run/accept-2","kind":"agent","authority":"reviewer","target":"accept-3","files":[]}'; } > "$W/l"
eq "an overrule at the same authority never counts" counted "$(acceptance_rule_live "$W/l" "$W/cur" "$W/sessions")"
{ hdr; seated_accept agent:run/accept-1 accept-3 D1; coord overrule overrule-4 accept-9; } > "$W/l"
eq "an overrule naming no earlier acceptance never counts" counted "$(acceptance_rule_live "$W/l" "$W/cur" "$W/sessions")"
{ hdr; coord overrule overrule-2 accept-3; seated_accept agent:run/accept-1 accept-3 D1; } > "$W/l"
eq "an overrule of an acceptance written after it never counts" counted "$(acceptance_rule_live "$W/l" "$W/cur" "$W/sessions")"
{ hdr; seated_accept agent:run/accept-1 accept-3 D1; coord overrule overrule-4 accept-3; seated_accept agent:run/accept-2 accept-6 D1; } > "$W/l"
eq "after an overrule, an acceptance below its authority leaves the unit held" "held	overruled t.sh by agent:c" "$(acceptance_rule_live "$W/l" "$W/cur" "$W/sessions")"
{ hdr; seated_accept agent:run/accept-1 accept-3 D1; coord overrule overrule-4 accept-3; coord accept accept-5; } > "$W/l"
eq "after an overrule, an acceptance at its authority counts again" counted "$(acceptance_rule_live "$W/l" "$W/cur" "$W/sessions")"
{ hdr; seated_accept agent:run/accept-1 accept-3 D1; coord overrule overrule-4 accept-3; person_line accept accept-5 owner D1 good; } > "$W/l"
eq "after an overrule, a person at owner counts again" counted "$(acceptance_rule_live "$W/l" "$W/cur" "$W/sessions" "$W/key")"
eq "a person may overrule a coordinator" allow "$(rule person:pat person owner overrule "$A" false true false false coordinator)"
eq "a person at reviewer can't overrule a reviewer" not-higher "$(rule person:pat person reviewer overrule "$A" false true false false reviewer)"
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
