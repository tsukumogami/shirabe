#!/usr/bin/env bash
# coordinate_4_engine_test.sh -- part 4 of 4 of the coordinate engine cases: the
# shipped coordinate.md driven through real koto, from sessions
# coordinate-open.sh opens, against the testdata/gh stand-in. The four parts
# share their setup and helpers (testdata/coordinate-engine-lib.sh) and run side
# by side under scripts/check-skill.sh; the cases are split in file order, so a
# case that reuses an earlier case's fixtures stays in that case's part.
#
# Proves, one line per case:
#  16. a unit's tag in place of its dispatch topic (shirabe#492): pick's
#      dispatch with unit "Feature 1" comes back to pick through
#      dispatch_check, never entering dispatch, with a refusal naming the
#      field and the value; the same pick with the topic goes on to dispatch.
#  20. a unit waiting on a person (shirabe#549): pick's await_decision goes to
#      decision_raise, which holds until record-state.sh parks the unit on the
#      entry it opened; escalated and sent, the run is back at pick with the
#      unit awaiting and no slot taken, so under a cap of one another unit is
#      dispatched beside it; a dispatch of the parked unit submitted paused
#      goes back to wait (dispatch-worker_test.sh proves the exit 10 refusal
#      that sends it there); the answer settles the entry, pick lists the unit
#      answered, and its dispatch goes through, its holding row taking over
#      the decision row.
#  21. a feature whose deliverable is its scoping (shirabe#550): pick's scope
#      dispatches /shirabe:scope through dispatch-worker.sh at Phase scoping,
#      its brief saying the execution is a later unit; when a scoping holding's
#      merge is confirmed, record holds until a follow-up Work row records its
#      execution, pick then lists the unit's follow-up, and roadmap-status.sh
#      refuses to write it Done.
#  23. on a roadmap/v2 roadmap, land's check puts the holding's milestone and
#      its numbered Evidence in coord/land.json, and a pull request judged
#      `fits` with `clauses: advances none` still reaches land_merge.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/coordinate_4_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"

# ---- 16. a unit that isn't a topic is refused where it is read ----------------
echo "== 16. a unit's tag in place of its topic goes back to be submitted again =="
if to_pick untopic "$(record_json roadmap untopic | jq -c --argjson h "$(unit_row feat-1)" '.holdings = [$h]')" 960; then
    # pick's unit is a dispatch topic, never the unit's tag (shirabe#492).
    eq "16: dispatch with unit \"Feature 1\" comes back to pick" pick "$(at --with-data '{"choice":"dispatch","unit":"Feature 1"}')"
    from_to dispatch_check pick_facts && ok "16: the route was dispatch_check -> pick_facts" || bad "16: the route was dispatch_check -> pick_facts"
    eq "16: dispatch is never entered" 0 "$(entered dispatch)"
    case "$(cd "$WD" && koto context get "$S" coord/dispatch_check.json 2>/dev/null | jq -r .reason)" in
        "pick's unit [Feature 1] is not a dispatch topic"*) ok "16: the refusal names the field and the value" ;;
        *) bad "16: the refusal names the field and the value" "$(cd "$WD" && koto context get "$S" coord/dispatch_check.json 2>&1)" ;;
    esac
    eq "16: the same pick with its topic goes on to dispatch" dispatch "$(at --with-data '{"choice":"dispatch","unit":"feat-2"}')"
else
    bad "16: reach pick" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
if to_pick unmerged "$(record_json roadmap unmerged | jq -c --argjson h "$(unit_row feat-1)" '.holdings = [$h]')" 961 \
    && [ "$(at --with-data '{"choice":"hold"}')" = wait ]; then
    # A merged event naming the unit's title rather than its topic (shirabe#547).
    eq "16: merged with a unit's title comes back to wait" wait "$(at --with-data '{"event":"merged","unit":"Feature 16: example"}')"
    from_to merged_facts wait && ok "16: the route was merged_facts -> wait" || bad "16: the route was merged_facts -> wait"
    case "$(cd "$WD" && koto context get "$S" coord/merged_facts.json 2>/dev/null | jq -r .reason)" in
        "the merged event's unit [Feature 16: example] is not a topic; unit takes the dispatch topic of a holding"*)
            ok "16: the refusal names the field, the value and what it takes" ;;
        *) bad "16: the refusal names the field, the value and what it takes" "$(cd "$WD" && koto context get "$S" coord/merged_facts.json 2>&1)" ;;
    esac
    tick --with-data '{"event":"quiet"}' >/dev/null
    from_to wait quiet_check && ok "16: back at wait, the next event is taken" || bad "16: back at wait, the next event is taken" "$(now_at)"
else
    bad "16: reach wait" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 20. a unit waiting on a person is parked, and the slot stays free --------
echo "== 20. a unit waiting on a person is parked on a decision entry, the slot stays free, and the answer frees it =="
# niwa, for the dispatches this case and the next make: `list --json` names
# the sessions launched so far, `dispatch --name <topic>` launches one.
mkdir -p "$T/niwa-bin"
printf '[]\n' > "$T/niwa-sessions.json"
cat > "$T/niwa-bin/niwa" <<EOF
#!/usr/bin/env bash
case "\$1 \${2-}" in
    "list --json") cat "$T/niwa-sessions.json" ;;
    "dispatch --help") : ;;
    dispatch*) shift; t=; while [ \$# -gt 0 ]; do [ "\$1" = --name ] && t=\$2; shift; done
        n="\$(printf '%s' "\$t" | tr '-' '_')-1a2b3c4d"
        jq -c --arg n "\$n" '. + [{name: "w", path: "/w", session_name: \$n}]' "$T/niwa-sessions.json" > "$T/niwa-s.tmp" && mv "$T/niwa-s.tmp" "$T/niwa-sessions.json"
        printf 'Dispatched\n  session name: %s\n' "\$n" ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$T/niwa-bin/niwa"
three_features parked
seed_record parked 200
if open_run parked && [ "$(at)" = reconcile ] && [ "$(at --with-data '{"reconciled":"reported"}')" = pick ]; then
    # One slot: the human sets the cap to one.
    write_as_agent record-state.sh --run cap 1 --by "the human"
    [ "$(at --with-data '{"choice":"hold"}')" = wait ] && [ "$(at --with-data '{"event":"resume"}')" = pick ] \
        && eq "20: the cap is one" 1 "$(pickf | jq -r .cap)" || bad "20: back at pick with the cap at one" "$(cat "$T/tick.err")"
    eq "20: await_decision with no unit stays at pick" pick "$(at --with-data '{"choice":"await_decision","rationale":"the framing is the human'"'"'s"}')"
    eq "20: await_decision on Feature 1 goes to decision_raise" decision_raise \
        "$(at --with-data '{"choice":"await_decision","unit":"Feature 1","rationale":"its framing is the human'"'"'s call"}')"
    write_as_agent record-decision.sh --open --question "Feature 1: keep its command-line surface, or fold it into the API?" \
        --option "keep -- two front ends to maintain" --option "fold -- one front end, a breaking change" --source self
    eq "20: the question opens as an entry" 0 $?
    eq "20: raised before the unit is parked comes back to decision_raise" decision_raise "$(at --with-data '{"raised":"raised"}')"
    write_as_agent record-state.sh --work "Feature 1" --kind decision --who "decision 1" --next "dispatch it with the answer"
    eq "20: record-state.sh parks Feature 1 on decision 1" 0 $?
    eq "20: once parked, the entry is taken up" decision_take "$(at --with-data '{"raised":"raised"}')"
    write_as_agent record-decision.sh --take
    eq "20: and comes up for a verdict" decision_verdict "$(at --with-data '{"taken":"taken"}')"
    write_as_agent record-decision.sh --escalate --recommendation keep --reason "the API's users asked for the command line" \
        --context "Feature 1 can't be scoped until its surface is chosen." --problem "It changes the feature's scope, which is the human's." \
        --grounds scope --option "keep -- two front ends to maintain" --option "fold -- one front end, a breaking change"
    eq "20: escalated to the person" 0 $?
    eq "20: the escalation renders" escalate_send "$(at --with-data '{"verdict":"escalate","rationale":"a scope call"}')"
    write_as_agent record-decision.sh --sent --route message
    eq "20: sent, the loop goes back to pick" pick "$(at --with-data '{"sent":"sent"}')"
    eq "20: pick lists Feature 1 awaiting decision 1, holding no slot" "1 0" "$(pickf | jq -r '"\(.units[0].awaiting) \(.active)"')"
    # The one slot is still free: Feature 2 is dispatched into it.
    eq "20: with the cap at one, Feature 2 is dispatched beside the parked unit" dispatch "$(at --with-data '{"choice":"dispatch","unit":"feat-2"}')"
    dispatch_as_agent "$(brief feat-2 "Feature 2" deliver feat-2 executing)"
    eq "20: dispatch-worker.sh launches it" 0 "$DW_RC"
    eq "20: record waits for its Work row" record "$(at --with-data '{"dispatched":"sent","topic":"feat-2"}')"
    write_as_agent record-state.sh --work "Feature 2" --kind holding --who feat-2 --next "report at its first checkpoint"
    eq "20: then the loop goes back to pick" pick "$(at)"
    # The parked unit can't be dispatched while its entry is open.
    write_as_agent record-state.sh --run cap 2 --by "the human"
    at --with-data '{"choice":"hold"}' >/dev/null
    eq "20: a second slot" pick "$(at --with-data '{"event":"resume"}')"
    eq "20: dispatching the parked unit passes the check" dispatch "$(at --with-data '{"choice":"dispatch","unit":"feat-1"}')"
    # dispatch-worker.sh refuses it with exit 10 and writes nothing
    # (dispatch-worker_test.sh's "park:" cases); paused takes the run back.
    eq "20: submitted paused, back to wait" wait "$(at --with-data '{"dispatched":"paused","topic":"feat-1"}')"
    # The answer lands.
    eq "20: the person's answer reaches decision_answer" decision_answer "$(at --with-data '{"event":"answer","decision":"1","round":"1"}')"
    write_as_agent record-decision.sh --answer --outcome keep
    eq "20: recorded, the loop goes back to pick" pick "$(at --with-data '{"answered":"recorded"}')"
    eq "20: pick lists Feature 1 answered, no longer awaiting" 'null 1 keep' "$(pickf | jq -r '.units[0] | "\(.awaiting) \(.answered.decision) \(.answered.outcome | split(";")[0])"')"
    eq "20: now it is dispatched" dispatch "$(at --with-data '{"choice":"dispatch","unit":"feat-1"}')"
    dispatch_as_agent "$(brief feat-1 "Feature 1" deliver feat-1 executing)"
    eq "20: dispatch-worker.sh launches it" 0 "$DW_RC"
    eq "20: record waits for its Work row" record "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')"
    write_as_agent record-state.sh --work "Feature 1" --kind holding --who feat-1 --next "report at its first checkpoint"
    eq "20: then back to pick" pick "$(at)"
    eq "20: its holding row took over the decision row" "Feature 2:holding:feat-2 Feature 1:holding:feat-1" "$(work_rows 200)"
else
    bad "20: reach pick" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 21. a feature whose deliverable is its scoping ---------------------------
echo "== 21. a scope dispatches the scoping alone, and its merge records the execution as a follow-up =="
three_features scoped
seed_record scoped 210
if open_run scoped && [ "$(at)" = reconcile ] && [ "$(at --with-data '{"reconciled":"reported"}')" = pick ]; then
    eq "21: scope goes through the dispatch check like a dispatch" dispatch "$(at --with-data '{"choice":"scope","unit":"feat-3"}')"
    dispatch_as_agent "$(brief feat-3 "Feature 3" scope feat-3 scoping)"
    eq "21: dispatch-worker.sh launches the scoping" 0 "$DW_RC"
    live_body 210 | jq -e '.holdings[] | select(.worker == "feat-3") | .phase == "scoping" and .entry_point == "scope"' >/dev/null \
        && ok "21: the holding is the scoping alone, at Phase scoping" || bad "21: the holding is the scoping alone, at Phase scoping" "$(live_body 210 | jq -c .holdings)"
    grep -q "the execution is a later unit" "$T/work/.niwa/dispatch-briefs/feat-3.md" 2>/dev/null \
        && ok "21: its brief says the documents are the deliverable" || bad "21: its brief says the documents are the deliverable" "$(ls "$T/work/.niwa/dispatch-briefs" 2>&1)"
else
    bad "21: reach pick" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
if LAND_PHASE=scoping land_run scopemerge 211; then
    LAND_PHASE=scoping record_verified
    if [ "$(at)" = goal_fit ] && [ "$(at --with-data '{"fit":"fits","rationale":"the scoping documents land"}')" = land_merge ]; then
        bt_merged MERGED; bt_reach behind
        eq "21: the merge is confirmed" record "$(at --with-data '{"merge":"attempted"}')"
        rm -rf "$GH_BOARD_DIR" && mkdir -p "$GH_BOARD_DIR"
        (cd "$WD" && bash "$PS/record-holding.sh" --session "$S" --topic feat-1 --read) | jq -c '.pull_request = ""' > "$T/row.json"
        write_as_agent record-holding.sh --topic feat-1 --row-file "$T/row.json"
        eq "21: with the cell cleared, record still holds" record "$(at)"
        case "$(cd "$WD" && koto context get "$S" coord/record_confirm.json 2>/dev/null | jq -r .expectation)" in
            *"a follow-up Work row for Feature 1"*) ok "21: for the follow-up, the unit's execution" ;;
            *) bad "21: for the follow-up, the unit's execution" "$(cd "$WD" && koto context get "$S" coord/record_confirm.json 2>&1)" ;;
        esac
        write_as_agent record-state.sh --work "Feature 1" --kind follow-up --who "acme/widgets#12" --next "/shirabe:execute docs/plans/PLAN-feat-1.md"
        eq "21: record-state.sh writes the follow-up" 0 $?
        eq "21: then the merge confirms and the loop goes on to pick" pick "$(at)"
        eq "21: pick lists the follow-up beside the merged holding" "acme/widgets#12 /shirabe:execute docs/plans/PLAN-feat-1.md" \
            "$(pickf | jq -r '.units[] | select(.unit == "Feature 1") | "\(.follow_up.after) \(.follow_up.next)"')"
        write_as_agent roadmap-status.sh --unit "Feature 1" --outcome "acme/widgets#12"
        eq "21: the roadmap can't be told the feature is Done" 65 $?
        grep -q "its execution is a follow-up still to dispatch" "$T/w.err" && ok "21:   ... since its execution is still to come" || bad "21:   ... since its execution is still to come" "$(cat "$T/w.err")"
    else
        bad "21: reach land_merge" "$(cat "$T/tick.err" 2>/dev/null)"
    fi
else
    bad "21: reach verified_confirm" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
rm -rf "$GH_BOARD_DIR" && mkdir -p "$GH_BOARD_DIR"

# ---- 23. goal fit on a milestone roadmap --------------------------------------
echo "== 23. on a milestone roadmap, a pull request judged advances none still lands =="
# The run's roadmap on the default branch is a roadmap/v2 one, and the
# holding is on its milestone MV1. The land check reads MV1's Evidence into
# coord/land.json; this pull request, a second one for MV1 (the first one's
# goal-fit entry is milestone-verdicts_test.sh's), moves no clause, and fits.
ROADMAP_TEXT=$(printf -- '---\nschema: roadmap/v2\nstatus: Active\n---\n\n# ROADMAP: mvland\n\n## Features\n\n### MV1: the plugin list\n\n**Outcome:** A maintainer lists the plugins they installed.\n\n**Evidence:**\n- A reviewer runs `widgets list` and sees the three sample plugins.\n- The same reviewer removes one manifest and sees it named as skipped.\n\n**Left open:** None\n\n**Dependencies:** None\n**Status:** In progress\n')
LAND_UNIT=MV1
if land_run mvland 113; then
    record_verified
    eq "23: land reads the round and permits, to goal_fit" goal_fit "$(at)"
    eq "23: coord/land.json carries MV1's numbered Evidence" "MV1 2" \
        "$(cd "$WD" && koto context get "$S" coord/land.json 2>/dev/null | jq -r '"\(.milestone.tag) \(.milestone.evidence | length)"')"
    eq "23: fits, advancing none of it, reaches land_merge" land_merge \
        "$(at --with-data '{"fit":"fits","clauses":"advances none","rationale":"a refactor of the loader the list builds on; it moves no clause"}')"
else
    bad "23: reach verified_confirm" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
ROADMAP_TEXT= LAND_UNIT=
rm -rf "$GH_BOARD_DIR" && mkdir -p "$GH_BOARD_DIR"

echo
echo "coordinate_engine part 4: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
