#!/usr/bin/env bash
# reconcile-owe_test.sh -- reconcile-owe.sh and roadmap-status.sh
# --owe-completed, the reconcile pass's write that owes the verdict of every
# Completed milestone on a roadmap/v4 roadmap.
#
# Covers: a run started over a roadmap/v4 roadmap whose Milestone 3 reads
# Completed, with an empty record, holds a verdict-owed row for Milestone 3
# (Who none, no holding naming it) after the write, and the picker reads
# Milestone 3 owed its verdict; Verified, Dropped, In progress and Not started
# milestones get no row; run again, it writes no second row and reports
# nothing owed; a milestone already owed (its row under Feature 3, matched by
# tag key) gets none; a holding covering the milestone is the row's Who. The
# same roadmap declared roadmap/v3, where Completed is no status, writes
# nothing and makes no record write. A record the write core refuses is
# reported not verified, with nothing written; --owe-completed takes no tag.
#
# Usage: bash skills/coordinate/scripts/reconcile-owe_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
EMPTY_CLAUDE_HOME="$T/claude-empty"
mkdir -p "$EMPTY_CLAUDE_HOME/jobs"
export DC_CLAUDE_HOME="$EMPTY_CLAUDE_HOME"
RO="$HERE/reconcile-owe.sh"
RS="$HERE/roadmap-status.sh"
PF="$HERE/pick-facts.sh"
RP=docs/roadmaps/ROADMAP-statuses.md

# roadmap <schema>: Milestone 1 Verified, 2 In progress (on 1), 3 Completed,
# 4 Dropped, 5 Not started (on 3).
roadmap() {
    printf -- '---\nschema: %s\nstatus: Active\n---\n\n# ROADMAP: statuses\n\n## Milestones\n\n' "$1"
    printf '### Milestone 1: Loader\n**Dependencies:** None\n**Status:** Verified\n\n'
    printf '### Milestone 2: Registry\n**Dependencies:** Milestone 1\n**Status:** In progress\n\n'
    printf '### Milestone 3: Search\n**Dependencies:** None\n**Status:** Completed\n\n'
    printf '### Milestone 4: Old index\n**Dependencies:** None\n**Status:** Dropped\n\n'
    printf '### Milestone 5: Ranking\n**Dependencies:** Milestone 3\n**Status:** Not started\n\n'
    printf '## Sequencing Rationale\n\nIn order.\n'
}
N=0
# started <schema> <record-json>: a run at reconcile_pass over that roadmap
# on the default branch, holding that record; S its session.
started() {
    [ -z "${S:-}" ] || log_end "$S"   # one live run for the scope at a time
    N=$((N + 1))
    S="coordinate-roadmap-statuses-20260926T08$(printf %02d "$N")00Z"
    db_init
    db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap "$1")"
    found_session "$S" "$(roadmap_vars statuses)"
    seed_session "$S" "$2"
    log_to "$S" record_find reconcile_pass
}
owed_rows() { session_state "$S" | jq -r '[(.work // [])[] | select(.kind == "verdict-owed") | "\(.item):\(.who)"] | join(" ")'; }
fact() { bash "$RO" --session "$S" 2>"$T/err"; }
EMPTY=$(record_json roadmap statuses)

echo "== roadmap/v4: a Completed milestone with no row =="
started roadmap/v4 "$EMPTY"
OUT=$(fact); RC=$?
eq "the write reports Milestone 3 owed" '0 ok ["Milestone 3"]' "$RC $(printf '%s' "$OUT" | jq -r .status) $(printf '%s' "$OUT" | jq -c .owed)"
eq "  ... the record holds one verdict-owed row, for Milestone 3, Who none" "Milestone 3:none" "$(owed_rows)"
bash "$PF" --session "$S" > /dev/null 2> "$T/pf.err"
PICK="$KOTO_STORE/context/$S/coord/pick.json"
eq "  ... the picker reads Milestone 3 owed its verdict, and no other" "Milestone 3" \
    "$(jq -r '[.units[] | select(.verdict_owed) | .unit] | join(",")' "$PICK" 2>/dev/null)"
eq "  ... and Milestone 5, which depends on it, is free" "false" \
    "$(jq -r '.units[] | select(.unit == "Milestone 5") | .blocked' "$PICK" 2>/dev/null)"
OUT=$(fact)
eq "run again, it owes nothing more" '[]' "$(printf '%s' "$OUT" | jq -c .owed)"
eq "  ... and the record still holds the one row" "Milestone 3:none" "$(owed_rows)"

echo "== roadmap/v4: a milestone already owed, and one a holding covers =="
started roadmap/v4 "$(printf '%s' "$EMPTY" | jq -c '.work = [{item: "Feature 3", kind: "verdict-owed", who: "w3", next: "verdict owed since 2026-09-26", wakes: "0", updated: "2026-09-26T07:00Z"}]')"
OUT=$(fact)
eq "a row under Feature 3 already owes Milestone 3: nothing written" '[] Feature 3:w3' "$(printf '%s' "$OUT" | jq -c .owed) $(owed_rows)"
started roadmap/v4 "$(printf '%s' "$EMPTY" | jq -c --argjson h "$(holding w3 '{"unit": "Milestone 3: Search", "pull_request": ""}')" '.holdings = [$h]')"
fact > /dev/null
eq "the holding that covers Milestone 3 is the row's Who" "Milestone 3:w3" "$(owed_rows)"

echo "== roadmap/v3: no Completed status, no row =="
started roadmap/v3 "$EMPTY"
BEFORE=$(session_state "$S" | jq -c .)
OUT=$(fact); RC=$?
eq "the same start on roadmap/v3 owes nothing" '0 ok []' "$RC $(printf '%s' "$OUT" | jq -r .status) $(printf '%s' "$OUT" | jq -c .owed)"
eq "  ... and writes nothing" "$BEFORE" "$(session_state "$S" | jq -c .)"

echo "== refusals =="
started roadmap/v4 "$EMPTY"
# A second live session for the same scope: the write guard refuses.
S2=coordinate-roadmap-statuses-20260926T090000Z
found_session "$S2" "$(roadmap_vars statuses)"
log_to "$S2" record_find reconcile_pass
OUT=$(fact)
case "$(printf '%s' "$OUT" | jq -r .status)" in
    not_verified) ok "a write the record refuses is not verified" ;;
    *) bad "a write the record refuses is not verified" "$OUT $(cat "$T/err")" ;;
esac
eq "  ... and nothing is written" "" "$(owed_rows)"
bash "$RS" --session "$S" --owe-completed --unit "Milestone 3" > /dev/null 2>&1; eq "--owe-completed takes no tag" 64 $?
bash "$RO" > /dev/null 2>&1; eq "reconcile-owe.sh without --session is a usage error" 64 $?

done_tests reconcile-owe
