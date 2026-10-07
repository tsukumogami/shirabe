#!/usr/bin/env bash
# record-confirm_test.sh -- record-confirm.sh reads the source step from the
# session log and confirms the change it implies with a newer Written: time.
#
# Covers, with a passing and a failing fixture each: dispatch (the topic's
# row), surface (the unit's Verified head), merge_confirm and merged_facts
# (merged: the unit's row kept with its Pull request cell cleared; unconfirmed: a
# Side effects row naming owner/repo#n at the sha), teardown (done and kept),
# decision_apply (reversal and deferral), posture_ask, and --verified
# (confirmed, waiting, moved). A multi-repository record where acme/widgets#12
# and acme/gadgets#12 are both held: the unit is found by its Worker from the
# log, links are matched by their full URL, and the live head is read from
# the unit's own repository; a bare #12 never confirms. The natural order:
# for decision_apply (reversal and deferral) and surface(merge_table), a
# record written after the run reached the hub but before the evidence that
# leaves the step confirms with no rewrite, and one written before the hub
# waits. posture_ask asked again mid-run, through record_find after the run
# had been at the hub, doesn't accept an answer from before this ask.
# teardown, which writes after its evidence, still compares with the
# evidence's time. Also: an older
# Written: time waits even when the rows match; a missing or non-canonical
# body is a conflict; a directed transition is `directed`; a capture with a
# broken seal is a conflict; the sealed token and its context detail.
#
# Usage: bash skills/coordinate/scripts/record-confirm_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
C="$HERE/record-confirm.sh"
CL="$HERE/coord-log.sh"

TITLE="Coordinator record: ROADMAP-plugin-system"
EVT=2026-09-26T10:00:00.000Z
AFTER=2026-09-26T10:05:00Z
BEFORE=2026-09-26T09:55:00Z
N=0

# body <record-json> [written]: make issue #7's body this record.
body() {
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]
        | .prs += [{repo: "acme/widgets", number: 12, title: "feat", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
                    baseRefName: "main", headRefName: "feat/x", headRefOid: $h, author: "alice", editor: null},
                   {repo: "acme/gadgets", number: 12, title: "feat", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
                    baseRefName: "main", headRefName: "feat/y", headRefOid: $o, author: "alice", editor: null}]' \
        --arg t "$TITLE" --arg b "$(render "$1" issue "${2:-$AFTER}")" --arg h "$SHA_HEAD" --arg o "$SHA_OTHER"
}
rec() { record_json roadmap plugin-system; }
# session: a fresh run with a found record #7; prints its name.
session() {
    N=$((N + 1))
    S=coordinate-plugin-system-20260926T0800$(printf '%02d' "$N")Z
    found_session "$S" "$(roadmap_vars plugin-system)" 7
}
confirm() { local o rc; o=$(bash "$C" --session "$S" --no-seal "$@" 2>"$T/err"); rc=$?; [ -z "$o" ] || seen "$o"; return $rc; }
sealed_capture() { # sealed_capture <state> <KEY> <token> [timestamp]
    log_to "$S" wait "$1"
    log_capture "$S" "$2" "$(bash "$CL" seal --session "$S" --state "$1" --token "$3")" "${4:-$EVT}"
}

# checked <topic>: the run passed dispatch_check on <topic>, sealed, then dispatched.
checked() {
    log_to "$S" pick dispatch_check
    log_capture "$S" DISPATCH_CHECK "$(bash "$HERE/coord-log.sh" seal --session "$S" --state dispatch_check --token "ok $1")"
    log_to "$S" dispatch_check dispatch
}
echo "== dispatch =="
session
checked alpha
log_evidence "$S" dispatch '{"outcome":"sent","topic":"alpha"}' "$EVT"
log_to "$S" dispatch record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
eq "dispatch: the topic's row with a newer Written: confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding beta)" '.holdings = [$h]')"
eq "dispatch: another topic's row waits" waiting "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')" "$BEFORE"
eq "dispatch: an older Written: time waits even with the row" waiting "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')" 2026-09-26T10:00:00Z
eq "dispatch: a Written: time in the event's own second waits" waiting "$(confirm)"
session
checked alpha
log_evidence "$S" dispatch '{"outcome":"sent","topic":"beta"}' "$EVT"
log_to "$S" dispatch record "$EVT"
body "$(rec | jq -c --argjson h "$(holding beta)" '.holdings = [$h]')"
eq "dispatch: a topic other than the one dispatch_check passed is a conflict" conflict "$(confirm)"
session
log_evidence "$S" dispatch '{"outcome":"sent","topic":"alpha"}' "$EVT"
log_to "$S" dispatch record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
eq "dispatch: a topic named only in the evidence, with no dispatch_check pass, is a conflict" conflict "$(confirm)"

echo "== dispatch after send_execution (shirabe#553) =="
send_exec() { # a run that picked send_execution for alpha, passed dispatch_check and dispatched it
    session
    log_to "$S" pick_facts pick 2026-09-26T09:50:00.000Z
    log_evidence "$S" pick '{"choice":"send_execution","unit":"alpha"}' 2026-09-26T09:51:00.000Z
    checked alpha
    log_evidence "$S" dispatch '{"dispatched":"sent","topic":"alpha"}' "$EVT"
    log_to "$S" dispatch record "$EVT"
}
send_exec
body "$(rec | jq -c --argjson h "$(holding alpha '{"phase":"executing","entry_point":"/shirabe:execute"}')" '.holdings = [$h]')"
eq "send_execution: the row moved to executing confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha '{"phase":"scoping-ahead","entry_point":"/shirabe:scope"}')" '.holdings = [$h]')"
eq "send_execution: a row still scoping ahead never confirms" waiting "$(confirm)"
bash "$C" --session "$S" >/dev/null 2>&1
jq -r '.expectation' "$KOTO_STORE/context/$S/coord/record_confirm.json" 2>/dev/null | grep -q 'means no execution was sent' \
    && ok "send_execution: the expectation says no execution was sent" || bad "send_execution: the expectation says no execution was sent" "$(cat "$KOTO_STORE/context/$S/coord/record_confirm.json" 2>/dev/null)"
session
log_to "$S" pick_facts pick 2026-09-26T09:50:00.000Z
log_evidence "$S" pick '{"choice":"dispatch","unit":"alpha"}' 2026-09-26T09:51:00.000Z
checked alpha
log_evidence "$S" dispatch '{"dispatched":"sent","topic":"alpha"}' "$EVT"
log_to "$S" dispatch record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha '{"phase":"scoping-ahead","entry_point":"/shirabe:scope"}')" '.holdings = [$h]')"
eq "a plain dispatch of a scoping-ahead row confirms as before" confirmed "$(confirm)"

echo "== leg_spent: a spent leg replaced (shirabe#506) =="
LS_REPLACED='{"move":"replaced","topic":"alpha"}'
leg_spent_run() { # leg_spent_run <evidence>: the wait read leg req-1:scope for alpha, spent; leg_spent replaced it
    session
    log_to "$S" wait leg_pick 2026-09-26T09:50:00.000Z
    log_capture "$S" WAIT_REQ req-1 2026-09-26T09:50:00.000Z
    log_to "$S" leg_pick wait_leg 2026-09-26T09:50:00.000Z
    log_capture "$S" WAIT_LEG scope 2026-09-26T09:50:00.000Z
    log_to "$S" wait_leg leg_spent 2026-09-26T09:50:00.000Z
    log_evidence "$S" leg_spent "$1" "$EVT"
    log_to "$S" leg_spent record "$EVT"
}
leg_spent_run "$LS_REPLACED"
body "$(rec | jq -c --argjson h "$(holding alpha '{"return_path":"leg req-2:scope"}')" '.holdings = [$h]')"
eq "leg_spent: the topic's row on a new leg confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha '{"return_path":"leg req-1:scope"}')" '.holdings = [$h]')"
eq "leg_spent: the row still on the spent leg waits" waiting "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha '{"return_path":"message"}')" '.holdings = [$h]')"
eq "leg_spent: a row moved to the message path isn't a replaced leg" waiting "$(confirm)"
body "$(rec | jq -c --argjson a "$(holding alpha '{"return_path":"leg req-2:scope"}')" --argjson b "$(holding beta '{"return_path":"leg req-1:scope"}')" '.holdings = [$a, $b]')"
eq "leg_spent: another row still on the spent leg waits" waiting "$(confirm)"
leg_spent_run '{"move":"replaced"}'
body "$(rec | jq -c --argjson h "$(holding alpha '{"return_path":"leg req-2:scope"}')" '.holdings = [$h]')"
eq "leg_spent: replaced with no topic is a conflict" conflict "$(confirm)"

echo "== surface =="
session
log_evidence "$S" wait '{"event":"report","unit":"alpha"}' 2026-09-26T09:50:00.000Z
log_to "$S" wait report_facts; log_to "$S" report_facts classify_report
log_to "$S" classify_report surface
log_evidence "$S" surface '{"surfaced":"merge_table"}' "$EVT"
log_to "$S" surface record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha "{\"verified_head\":\"$SHA_HEAD\"}")" '.holdings = [$h]')"
eq "surface: the unit's row with a Verified head confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
eq "surface: the unit's row without a Verified head waits" waiting "$(confirm)"

echo "== surface after a hold the land check read =="
session
log_evidence "$S" wait '{"event":"report","unit":"alpha"}' 2026-09-26T09:50:00.000Z
log_to "$S" wait report_facts; log_to "$S" report_facts classify_report
log_to "$S" classify_report verify; log_to "$S" verify land
log_capture "$S" LAND "$(bash "$CL" seal --session "$S" --state land --token "held 12 $SHA_HEAD")" "$EVT"
log_to "$S" land surface "$EVT"
log_evidence "$S" surface '{"surfaced":"merge_table"}' "$EVT"
log_to "$S" surface record "$EVT"
HELD_X=$(jq -nc --arg s "$SHA_HEAD" '{verified_head: $s, phase: "held"}')
body "$(rec | jq -c --argjson h "$(holding alpha "$HELD_X")" '.holdings = [$h]')"
eq "held: a Verified head and a held Phase confirms" confirmed "$(confirm)"
EXEC_X=$(jq -nc --arg s "$SHA_HEAD" '{verified_head: $s, phase: "executing"}')
body "$(rec | jq -c --argjson h "$(holding alpha "$EXEC_X")" '.holdings = [$h]')"
eq "held: a Verified head with Phase executing waits" waiting "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha "{\"phase\":\"held\"}")" '.holdings = [$h]')"
eq "held: a held Phase without a Verified head waits" waiting "$(confirm)"
# A reserved merge reaches surface from goal_fit, not land: no hold, no Phase.
session
log_evidence "$S" wait '{"event":"report","unit":"alpha"}' 2026-09-26T09:50:00.000Z
log_to "$S" wait report_facts; log_to "$S" report_facts classify_report
log_to "$S" classify_report verify; log_to "$S" verify land
log_capture "$S" LAND "$(bash "$CL" seal --session "$S" --state land --token "deny 12 $SHA_HEAD")" "$EVT"
log_to "$S" land goal_fit; log_evidence "$S" goal_fit '{"fit":"fits","rationale":"r"}' "$EVT"
log_to "$S" goal_fit surface "$EVT"
log_evidence "$S" surface '{"surfaced":"merge_table"}' "$EVT"
log_to "$S" surface record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha "$EXEC_X")" '.holdings = [$h]')"
eq "a reserved merge from goal_fit confirms with Phase executing" confirmed "$(confirm)"

GADGETS12='{"repo":"acme/gadgets","branch":"feat/y","pull_request":"[#12](https://github.com/acme/gadgets/pull/12)"}'

echo "== merge_confirm and merged_facts =="
for src in merge_confirm merged_facts; do
    KEY=MERGE_CONFIRM; [ "$src" = merged_facts ] && KEY=MERGED_FACTS
    session
    log_evidence "$S" wait '{"event":"merged","unit":"alpha"}' 2026-09-26T09:50:00.000Z
    sealed_capture "$src" "$KEY" "merged 12 $SHA_HEAD"
    log_to "$S" "$src" record "$EVT"
    # A confirmed merge clears the unit's Pull request cell and keeps its row
    # until teardown (the shirabe#490 comment of 2026-09-28).
    body "$(rec | jq -c --argjson h "$(holding alpha '{"pull_request":""}')" '.holdings = [$h]')"
    eq "$src merged: the unit's row kept with its Pull request cell cleared confirms" confirmed "$(confirm)"
    body "$(rec | jq -c --argjson h "$(holding beta '{"pull_request":"[#13](https://github.com/acme/widgets/pull/13)"}')" '.holdings = [$h]')"
    eq "$src merged: the unit's row gone waits, since the row stays until teardown" waiting "$(confirm)"
    body "$(rec | jq -c --argjson h "$(holding alpha '{"pull_request":"[#14](https://github.com/acme/widgets/pull/14)"}')" '.holdings = [$h]')"
    eq "$src merged: the unit's row linking another pull request waits" waiting "$(confirm)"
    body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
    eq "$src merged: a row still linking #12 waits" waiting "$(confirm)"
    # Two units hold #12, in two repositories.
    body "$(rec | jq -c --argjson a "$(holding alpha)" --argjson g "$(holding gamma "$GADGETS12")" '.holdings = [$g, $a]')"
    eq "$src merged: the unit's widgets#12 row still there waits beside gadgets#12" waiting "$(confirm)"
    body "$(rec | jq -c --argjson a "$(holding alpha '{"pull_request":""}')" --argjson g "$(holding gamma "$GADGETS12")" '.holdings = [$g, $a]')"
    eq "$src merged: widgets#12's cell cleared confirms though gadgets#12's row stays" confirmed "$(confirm)"
    session
    log_evidence "$S" wait '{"event":"merged","unit":"alpha"}' 2026-09-26T09:50:00.000Z
    sealed_capture "$src" "$KEY" "unconfirmed 12 $SHA_HEAD"
    log_to "$S" "$src" record "$EVT"
    SE=$(jq -nc --arg s "$SHA_HEAD" '[{action: "merge", target: "acme/widgets#12", verified_head: $s, attempted: "2026-09-26T09:58Z", how_to_confirm: "compare blobs"}]')
    HA=$(holding alpha)
    body "$(rec | jq -c --argjson se "$SE" --argjson a "$HA" '.side_effects = $se | .holdings = [$a]')"
    eq "$src unconfirmed: a Side effects row at the sha confirms" confirmed "$(confirm)"
    body "$(rec | jq -c --argjson se "$SE" --argjson a "$HA" '.side_effects = $se | .holdings = [$a] | .side_effects[0].target = "merge of https://github.com/acme/widgets/pull/12"')"
    eq "$src unconfirmed: the pull request's URL in Target confirms" confirmed "$(confirm)"
    body "$(rec | jq -c --argjson se "$SE" --argjson a "$HA" --arg o "$SHA_OTHER" '.side_effects = $se | .holdings = [$a] | .side_effects[0].verified_head = $o')"
    eq "$src unconfirmed: a Side effects row at another sha waits" waiting "$(confirm)"
    body "$(rec | jq -c --argjson se "$SE" --argjson a "$HA" '.side_effects = $se | .holdings = [$a] | .side_effects[0].target = "acme/widgets#123"')"
    eq "$src unconfirmed: #123 does not name #12" waiting "$(confirm)"
    body "$(rec | jq -c --argjson se "$SE" --argjson a "$HA" '.side_effects = $se | .holdings = [$a] | .side_effects[0].target = "#12"')"
    eq "$src unconfirmed: a bare #12 never confirms" waiting "$(confirm)"
    body "$(rec | jq -c --argjson se "$SE" --argjson a "$HA" --argjson g "$(holding gamma "$GADGETS12")" '.side_effects = $se | .holdings = [$g, $a] | .side_effects[0].target = "acme/gadgets#12"')"
    eq "$src unconfirmed: gadgets#12 in Target does not confirm widgets#12" waiting "$(confirm)"
    body "$(rec | jq -c --argjson se "$SE" '.side_effects = $se')"
    eq "$src unconfirmed: without the unit's row the repository can't be told, so it waits" waiting "$(confirm)"
done

echo "== a merge made while a hold stood =="
# hold <name> <until> [lifted]: a hold on acme/widgets#12.
hold() { jq -nc --arg h "$1" --arg u "$2" --arg l "${3-}" \
    '{hold: $h, on: "acme/widgets#12", until: $u, set_by: "the workspace coordinator", set: "2026-09-26T09:00Z", lifted: $l}'; }
CLEARED=$(holding alpha '{"pull_request":""}')
WHILE_HELD='{"date":"2026-09-26T10:05Z","reversed":"hold go-signal on acme/widgets#12","now":"merged while held, by someone","reason":"merged outside the run","from":"the coordinator"}'
session
log_evidence "$S" wait '{"event":"merged","unit":"alpha"}' 2026-09-26T09:50:00.000Z
sealed_capture merged_facts MERGED_FACTS "merged 12 $SHA_HEAD"
log_to "$S" merged_facts record "$EVT"
body "$(rec | jq -c --argjson a "$CLEARED" --argjson h "$(hold go-signal lifted)" '.holdings = [$a] | .holds = [$h]')"
eq "a standing hold with no Reversals row for it waits" waiting "$(confirm)"
body "$(rec | jq -c --argjson a "$CLEARED" --argjson h "$(hold go-signal lifted)" --argjson r "$WHILE_HELD" '.holdings = [$a] | .holds = [$h] | .reversals = [$r]')"
eq "with a Reversals row saying it merged while held, it confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson a "$CLEARED" --argjson h "$(hold go-signal lifted '2026-09-26T09:30Z by the human')" '.holdings = [$a] | .holds = [$h]')"
eq "a hold lifted before the merge needs no row" confirmed "$(confirm)"
body "$(rec | jq -c --argjson a "$CLEARED" --argjson h "$(hold after-y 'merged acme/gadgets#12')" '.holdings = [$a] | .holds = [$h]')"
eq "a hold until another pull request merges, still open, needs its row" waiting "$(confirm)"
body "$(rec | jq -c --argjson a "$CLEARED" --argjson h "$(hold other lifted | jq -c '.on = "acme/widgets#13"')" '.holdings = [$a] | .holds = [$h]')"
eq "a hold on another pull request doesn't apply" confirmed "$(confirm)"
body "$(rec | jq -c --argjson a "$CLEARED" --argjson h "$(hold go lifted)" --argjson r "$WHILE_HELD" '.holdings = [$a] | .holds = [$h] | .reversals = [$r]')"
eq "a row for hold go-signal doesn't stand for a hold named go" waiting "$(confirm)"

session
log_to "$S" wait merge_confirm
log_capture "$S" MERGE_CONFIRM "merged 12 $SHA_HEAD sealed:99:abc" "$EVT"
log_to "$S" merge_confirm record "$EVT"
body "$(rec)"
eq "a capture with a broken seal is a conflict" conflict "$(confirm)"

echo "== teardown =="
session
log_evidence "$S" wait '{"event":"retire","unit":"alpha"}' 2026-09-26T09:50:00.000Z
log_to "$S" wait teardown
log_evidence "$S" teardown '{"outcome":"done"}' "$EVT"
log_to "$S" teardown record "$EVT"
body "$(rec | jq -c --argjson h "$(holding beta)" '.holdings = [$h]')"
eq "teardown done: no row for the unit confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
eq "teardown done: the unit's row still there waits" waiting "$(confirm)"
session
log_evidence "$S" wait '{"event":"retire","unit":"alpha"}' 2026-09-26T09:50:00.000Z
log_to "$S" wait teardown
log_evidence "$S" teardown '{"outcome":"kept"}' "$EVT"
log_to "$S" teardown record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
eq "teardown kept: a newer Written: confirms with the row kept" confirmed "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')" "$BEFORE"
eq "teardown kept: an older Written: waits" waiting "$(confirm)"
# teardown writes the record after its evidence, so it keeps the evidence's
# time: a body written after the hub but before `kept` doesn't count.
session
log_to "$S" pick_facts wait 2026-09-26T09:50:00.000Z
log_evidence "$S" wait '{"event":"retire","unit":"alpha"}' 2026-09-26T09:50:00.000Z
log_to "$S" wait teardown 2026-09-26T09:50:00.000Z
log_evidence "$S" teardown '{"outcome":"kept"}' "$EVT"
log_to "$S" teardown record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')" "$BEFORE"
eq "teardown kept: a body written after the hub but before the evidence still waits" waiting "$(confirm)"

echo "== destroy (the dispatch path's teardown) =="
destroy_run() { # destroy_run <outcome> <sealed topic>
    session
    log_evidence "$S" wait '{"event":"retire","unit":"alpha"}' 2026-09-26T09:50:00.000Z
    log_to "$S" wait teardown
    log_to "$S" teardown teardown_inventory
    printf 'topic %s\ninstance /x/instances/alpha\n' "$2" > "$T/inv"
    log_capture "$S" TEARDOWN_SEAL "$(bash "$HERE/coord-log.sh" seal --session "$S" --state teardown_inventory --file "$T/inv" --key teardown_verdict)"
    log_to "$S" teardown_inventory destroy
    log_evidence "$S" destroy "{\"outcome\":\"$1\"}" "$EVT"
    log_to "$S" destroy record "$EVT"
}
destroy_run destroyed alpha
body "$(rec | jq -c --argjson h "$(holding beta)" '.holdings = [$h]')"
eq "destroy destroyed: no row for the sealed topic confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
eq "destroy destroyed: the topic's row still there waits" waiting "$(confirm)"
destroy_run handed_over alpha
SEH='[{"action":"destroy","target":"instance of alpha","verified_head":"","attempted":"2026-09-26T09:58Z","how_to_confirm":"the instance is gone"}]'
body "$(rec | jq -c --argjson se "$SEH" '.side_effects = $se')"
eq "destroy handed_over: a Side effects row naming the topic confirms" confirmed "$(confirm)"
body "$(rec)"
eq "destroy handed_over: without the Side effects row it waits" waiting "$(confirm)"
destroy_run handed_over alpha
body "$(rec | jq -c '.side_effects = [{"action":"destroy","target":"instance of alpha-2","verified_head":"","attempted":"2026-09-26T09:58Z","how_to_confirm":"gone"}]')"
eq "destroy handed_over: a row naming alpha-2 does not name alpha" waiting "$(confirm)"
destroy_run destroyed alpha
printf 'topic beta\ninstance /x\n' > "$KOTO_STORE/context/$S/teardown_verdict"
body "$(rec)"
eq "destroy: an inventory edited after sealing is a conflict" conflict "$(confirm)"

echo "== decision_apply =="
REV='{"date":"2026-09-26T10:00Z","reversed":"merge on green","now":"hold","reason":"freeze","from":"the human"}'
session
log_to "$S" pick_facts wait "$EVT"; log_to "$S" wait decision_apply "$EVT"
log_evidence "$S" decision_apply '{"applied":"reversal"}' "$EVT"
log_to "$S" decision_apply record "$EVT"
body "$(rec | jq -c --argjson r "$REV" '.reversals = [$r]')"
eq "decision_apply reversal: a row dated at the event confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson r "$REV" '.reversals = [$r | .date = "2026-09-26T09:59Z"]')"
eq "decision_apply reversal: only an earlier row waits" waiting "$(confirm)"
session
log_to "$S" pick_facts wait "$EVT"; log_to "$S" wait decision_apply "$EVT"
log_evidence "$S" decision_apply '{"applied":"deferral"}' "$EVT"
log_to "$S" decision_apply record "$EVT"
DEF='{"deferral":"flaky","reason":"later","raised":"2026-09-26T10:01Z","disposition":""}'
body "$(rec | jq -c --argjson d "$DEF" '.deferrals = [$d]')"
eq "decision_apply deferral: a row raised after the event confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson d "$DEF" '.deferrals = [$d | .raised = "2026-09-25T10:01Z"]')"
eq "decision_apply deferral: only an older deferral waits" waiting "$(confirm)"

echo "== the natural order: written before the evidence that leaves the step =="
# decision_apply: the coordinator reached the hub at 09:50, the human's
# reversal arrived, it was recorded at 09:55:30, and only then was the
# decision ticked (09:56) and `change` submitted (10:00).
session
log_to "$S" pick_facts wait 2026-09-26T09:50:00.000Z
log_evidence "$S" wait '{"event":"decision"}' 2026-09-26T09:56:00.000Z
log_to "$S" wait decision_apply 2026-09-26T09:56:00.000Z
log_evidence "$S" decision_apply '{"change":"reversal"}' "$EVT"
log_to "$S" decision_apply record "$EVT"
body "$(rec | jq -c --argjson r "$REV" '.reversals = [$r | .date = "2026-09-26T09:55Z"]')" 2026-09-26T09:55:30Z
eq "decision_apply: a reversal recorded before the tick, since the hub, confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson r "$REV" '.reversals = [$r | .date = "2026-09-26T09:55Z"]')" 2026-09-26T09:49:00Z
eq "decision_apply: a body written before the run reached the hub waits" waiting "$(confirm)"
body "$(rec | jq -c --argjson r "$REV" '.reversals = [$r | .date = "2026-09-26T09:40Z"]')" 2026-09-26T09:55:30Z
eq "decision_apply: only a reversal dated before the hub waits" waiting "$(confirm)"
session
log_to "$S" pick_facts wait 2026-09-26T09:50:00.000Z
log_to "$S" wait decision_apply 2026-09-26T09:56:00.000Z
log_evidence "$S" decision_apply '{"change":"deferral"}' "$EVT"
log_to "$S" decision_apply record "$EVT"
body "$(rec | jq -c --argjson d "$DEF" '.deferrals = [$d | .raised = "2026-09-26T09:55Z"]')" 2026-09-26T09:55:30Z
eq "decision_apply: a deferral recorded before the tick, since the hub, confirms" confirmed "$(confirm)"
# surface(merge_table): the Verified head was written and confirmed at
# verified_confirm (09:52), before land and surface; nothing is left to write.
session
log_to "$S" pick_facts wait 2026-09-26T09:50:00.000Z
log_evidence "$S" wait '{"event":"report","unit":"alpha"}' 2026-09-26T09:50:10.000Z
log_to "$S" wait take_report 2026-09-26T09:50:10.000Z; log_to "$S" take_report report_facts; log_to "$S" report_facts classify_report
log_to "$S" classify_report verify; log_to "$S" verify verify_board; log_to "$S" verify_board verified_confirm
log_to "$S" verified_confirm land; log_to "$S" land surface
log_evidence "$S" surface '{"surfaced":"merge_table"}' "$EVT"
log_to "$S" surface record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha "{\"verified_head\":\"$SHA_HEAD\"}")" '.holdings = [$h]')" 2026-09-26T09:52:00Z
eq "surface: the Verified head written at verified_confirm confirms with no rewrite" confirmed "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha "{\"verified_head\":\"$SHA_HEAD\"}")" '.holdings = [$h]')" 2026-09-26T09:45:00Z
eq "surface: a body written before the run reached the hub waits" waiting "$(confirm)"
bash "$C" --session "$S" > /dev/null 2>&1
eq "and the detail names the hub arrival as the point" "2026-09-26T09:50:00.000Z" "$(jq -r .event_time "$KOTO_STORE/context/$S/coord/record_confirm.json" 2>/dev/null)"

# posture_ask asked again mid-run: dispatch_check found the record changed, the
# run went back through record_find (09:05) to posture_ask (09:06) after it had
# been at the hub (09:00). A posture answer from before this ask doesn't count.
PREV_OLD='{"date":"2026-09-26T09:03Z","reversed":"posture unread","now":"coordinator holds merge","reason":"asked once","from":"the human"}'
session
log_to "$S" pick_facts wait 2026-09-26T09:00:00.000Z
log_to "$S" dispatch_check record_find 2026-09-26T09:05:00.000Z
log_to "$S" record_find reconcile_pass 2026-09-26T09:05:10.000Z; log_to "$S" reconcile_pass reconcile 2026-09-26T09:05:20.000Z
log_to "$S" reconcile posture_ask 2026-09-26T09:06:00.000Z
log_evidence "$S" posture_ask '{"merge":"permitted","close":"reserved","teardown":"reserved"}' "$EVT"
log_to "$S" posture_ask record "$EVT"
body "$(rec | jq -c --argjson r "$PREV_OLD" '.reversals = [$r]')" 2026-09-26T09:07:00Z
eq "posture_ask mid-run: an answer dated before this ask's record_find waits" waiting "$(confirm)"
body "$(rec | jq -c --argjson r "$PREV_OLD" '.reversals = [$r | .date = "2026-09-26T09:08Z"]')" 2026-09-26T09:08:30Z
eq "posture_ask mid-run: the answer to this ask confirms" confirmed "$(confirm)"

echo "== posture_ask =="
session
log_to "$S" reconcile posture_ask "$EVT"
log_evidence "$S" posture_ask '{"merge":"permitted","close":"reserved","teardown":"reserved"}' "$EVT"
log_to "$S" posture_ask record "$EVT"
PREV='{"date":"2026-09-26T10:02Z","reversed":"posture unread","now":"coordinator holds merge","reason":"asked once","from":"the human"}'
body "$(rec | jq -c --argjson r "$PREV" '.reversals = [$r]')"
eq "posture_ask: the human's posture answer confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson r "$PREV" '.reversals = [$r | .from = "the coordinator"]')"
eq "posture_ask: a row not from the human waits" waiting "$(confirm)"
body "$(rec | jq -c --argjson r "$PREV" '.reversals = [$r | .reversed = "merge order" | .now = "hold"]')"
eq "posture_ask: a row not about the posture waits" waiting "$(confirm)"

echo "== --verified =="
session
log_evidence "$S" wait '{"event":"done","unit":"alpha"}' 2026-09-26T09:50:00.000Z
log_to "$S" wait verify
log_to "$S" verify verify_board
log_capture "$S" VERIFIED "$(bash "$CL" seal --session "$S" --state verify_board --token "verified 12 $SHA_HEAD")" "$EVT"
log_to "$S" verify_board verified_confirm "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha "{\"verified_head\":\"$SHA_HEAD\"}")" '.holdings = [$h]')"
eq "--verified: the row's Verified head equal to the capture confirms" confirmed "$(confirm --verified)"
grep -q "pr view 12 --repo acme/widgets --json headRefOid" "$GH_DB.calls" && ok "--verified re-reads the live head" || bad "--verified re-reads the live head" "$(calls)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
eq "--verified: no head written yet waits" waiting "$(confirm --verified)"
body "$(rec | jq -c --argjson h "$(holding alpha "{\"verified_head\":\"$SHA_OTHER\"}")" '.holdings = [$h]')"
eq "--verified: another head in the row waits" waiting "$(confirm --verified)"
body "$(rec | jq -c --argjson h "$(holding alpha "{\"verified_head\":\"$SHA_HEAD\"}")" '.holdings = [$h]')"
db '.prs[0].headRefOid = $o' --arg o "$SHA_OTHER"
eq "--verified: a moved live head is moved" moved "$(confirm --verified)"
db '.fail = [{match: "headRefOid", rc: 1}]'
confirm --verified >/dev/null; eq "--verified: a failed head read exits 2" 2 $?
# Two units hold #12: gamma's gadgets#12 (head SHA_OTHER) is listed first.
body "$(rec | jq -c --argjson a "$(holding alpha "{\"verified_head\":\"$SHA_HEAD\"}")" --argjson g "$(holding gamma "$GADGETS12")" '.holdings = [$g, $a]')"
eq "--verified: the unit's widgets#12 row confirms beside gadgets#12" confirmed "$(confirm --verified)"
grep -q "pr view 12 --repo acme/widgets --json headRefOid" "$GH_DB.calls" && ok "--verified reads the head from the unit's repository" || bad "--verified reads the head from the unit's repository" "$(calls)"
grep -q "pr view 12 --repo acme/gadgets" "$GH_DB.calls" && bad "--verified never reads the other unit's #12" "$(calls)" || ok "--verified never reads the other unit's #12"
body "$(rec | jq -c --argjson g "$(holding gamma "$GADGETS12" | jq -c --arg h "$SHA_HEAD" '.verified_head = $h')" '.holdings = [$g]')"
eq "--verified: only another unit's #12 row waits" waiting "$(confirm --verified)"
body "$(rec | jq -c --argjson a "$(holding alpha '{"pull_request":"[#13](https://github.com/acme/widgets/pull/13)"}')" '.holdings = [$a]')"
eq "--verified: the unit's row linking another pull request is a conflict" conflict "$(confirm --verified)"
body "$(rec | jq -c --argjson h "$(holding alpha "{\"verified_head\":\"$SHA_HEAD\"}")" '.holdings = [$h]')"
log_ev "$S" directed_transition '{"from":"verify","to":"verified_confirm"}'
eq "--verified: a directed transition in the run is directed" directed "$(confirm --verified)"

echo "== the leg path =="
# A report arriving on a koto request leg: the hub's wait evidence names no
# unit, so the unit is the holding whose Return path is the captured leg, as
# report-facts.sh finds it. alpha's earlier message report, and its own #12 in
# acme/gadgets, must not stand in for it.
leg_arrival() { # leg_arrival <request-id> <leg>
    log_evidence "$S" wait '{"event":"report","unit":"alpha"}' 2026-09-26T09:40:00.000Z
    log_to "$S" wait report_facts; log_to "$S" report_facts wait
    log_evidence "$S" wait '{"event":"leg"}' 2026-09-26T09:50:00.000Z
    log_to "$S" wait leg_pick
    log_capture "$S" WAIT_REQ "$1"
    log_to "$S" leg_pick wait_leg
    log_capture "$S" WAIT_LEG "$2"
    log_to "$S" wait_leg take_report
    log_to "$S" take_report report_facts
}
THETA_X=$(jq -nc --arg s "$SHA_HEAD" '{return_path: "leg req-1:execute", verified_head: $s}')
session
leg_arrival req-1 execute
log_to "$S" report_facts verify
log_to "$S" verify verify_board
log_capture "$S" VERIFIED "$(bash "$CL" seal --session "$S" --state verify_board --token "verified 12 $SHA_HEAD")" "$EVT"
log_to "$S" verify_board verified_confirm "$EVT"
reset_calls
body "$(rec | jq -c --argjson a "$(holding alpha "$GADGETS12")" --argjson t "$(holding theta "$THETA_X")" '.holdings = [$a, $t]')"
eq "leg --verified: the leg's holding confirms, not the last message's unit" confirmed "$(confirm --verified)"
grep -q "pr view 12 --repo acme/widgets --json headRefOid" "$GH_DB.calls" && ok "leg --verified: the head is read from the leg holding's repository" || bad "leg --verified: the head is read from the leg holding's repository" "$(calls)"
body "$(rec | jq -c --argjson a "$(holding alpha "$GADGETS12")" '.holdings = [$a]')"
eq "leg --verified: a leg no holding carries waits, as a unit with no row does" waiting "$(confirm --verified)"
TWO_X='{"return_path":"leg req-1:execute"}'
body "$(rec | jq -c --argjson a "$(holding alpha "$TWO_X")" --argjson t "$(holding theta "$THETA_X")" '.holdings = [$a, $t]')"
eq "leg --verified: a leg two holdings carry is a conflict" conflict "$(confirm --verified)"
session
leg_arrival req-1 execute
sealed_capture merge_confirm MERGE_CONFIRM "merged 12 $SHA_HEAD"
log_to "$S" merge_confirm record "$EVT"
body "$(rec | jq -c --argjson a "$(holding alpha "$GADGETS12")" --argjson t "$(holding theta "$(printf '%s' "$THETA_X" | jq -c '.pull_request = ""')")" '.holdings = [$a, $t]')"
eq "leg merge_confirm: the leg's unit with its cell cleared confirms though alpha links gadgets#12" confirmed "$(confirm)"
body "$(rec | jq -c --argjson a "$(holding alpha "$GADGETS12")" '.holdings = [$a]')"
eq "leg merge_confirm: the leg's unit gone waits" waiting "$(confirm)"
body "$(rec | jq -c --argjson a "$(holding alpha "$GADGETS12")" --argjson t "$(holding theta "$THETA_X")" '.holdings = [$a, $t]')"
eq "leg merge_confirm: the leg's holding still linking #12 waits" waiting "$(confirm)"

echo "== conflicts and refusals =="
session
checked alpha
log_evidence "$S" dispatch '{"outcome":"sent","topic":"alpha"}' "$EVT"
log_to "$S" dispatch record "$EVT"
body "$(rec)"; db '.issues[0].body = "gone"'
eq "a body that isn't a record is a conflict" conflict "$(confirm)"
db '.issues[0].body = ""'
eq "an empty body is a conflict" conflict "$(confirm)"
body "$(rec)"; db '.fail = [{match: "issue view", rc: 1}]'
confirm >/dev/null; eq "a failed body read exits 2" 2 $?
log_ev "$S" directed_transition '{"from":"record","to":"pick_facts"}'
body "$(rec)"
eq "a directed transition in the run is directed" directed "$(confirm)"
session
log_to "$S" reconcile record "$EVT"
body "$(rec)"
eq "an entry from a state with nothing to confirm is a conflict" conflict "$(confirm)"

echo "== sealing =="
session
checked alpha
log_evidence "$S" dispatch '{"outcome":"sent","topic":"alpha"}' "$EVT"
log_to "$S" dispatch record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
OUT=$(bash "$C" --session "$S" 2>"$T/err")
seen "$OUT" > /dev/null
case "$OUT" in "confirmed sealed:"*) ok "the verdict is sealed to the record visit" ;; *) bad "the verdict is sealed to the record visit" "$OUT $(cat "$T/err")" ;; esac
bash "$CL" check --session "$S" --state record --sealed "$OUT" && ok "the seal checks" || bad "the seal checks"
eq "the detail names the source" dispatch "$(jq -r .source "$KOTO_STORE/context/$S/coord/record_confirm.json")"
bash "$C" --no-seal >/dev/null 2>&1; eq "no session is a usage error" 64 $?

tokens_ok record-confirm
done_tests record-confirm
