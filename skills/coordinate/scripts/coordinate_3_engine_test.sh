#!/usr/bin/env bash
# coordinate_3_engine_test.sh -- part 3 of 4 of the coordinate engine cases: the
# shipped coordinate.md driven through real koto, from sessions
# coordinate-open.sh opens, against the testdata/gh stand-in. The four parts
# share their setup and helpers (testdata/coordinate-engine-lib.sh) and run side
# by side under scripts/check-skill.sh; the cases are split in file order, so a
# case that reuses an earlier case's fixtures stays in that case's part. Case
# 16's later message-path runs load the run its first one drove to wait
# (snap_save, snap_load), rather than driving the same prefix again.
#
# Proves, one line per case:
#  12. a restart takes over every decision entry before its first dispatch:
#      the unsent escalation rendered once, the proposed one taken up, the
#      unjudged one judged, a sent escalation and a held entry left alone;
#  13. an answer that reverses a supplied decision passes decision_apply as a
#      reversal, and record confirms the Reversals row;
#  14. a close with every feature done and an escalation still out reaches
#      roadmap_blocked, then wait;
#  15. escalate_send to a person, both routes: the question tool's answer comes
#      back from escalate_send, a message's from wait, each to decision_answer.
#  16. from a holding with Branch and Pull request empty, a message report
#      naming its pull request and a leg result carrying `pr` each go through
#      report_link, where holding-link.sh writes the pull request and its
#      headRefName, and on to verify_board reading that pull request with no
#      hand write, including a /work-on leg whose done result map reads the
#      pull request from context, which never reaches rebrief; once that run
#      is cancelled, the next start carries its record into a new run whose
#      reconcile reports the pull request open; `done` for a
#      report naming none goes back to wait, never to verify, and the next
#      report naming one gets through; blocked and needs_fix still route with
#      no pull request, and a leg-bound worker whose result names none takes
#      needs_fix to rebrief, the directive's route once its leg is spent.
#      verify_board's no-pr arm is unreachable here by design (the gate above
#      keeps such a report out of verify), so its sealed verdict is
#      board-record_test.sh's and its arm the structure test's.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/coordinate_3_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"

# ---- 16. a report's pull request reaches the holding --------------------------
echo "== 16. a report's pull request reaches an empty holding; done with none doesn't stick =="
LINKED='{"branch":"feat/w-head","pull_request":"[#12](https://github.com/acme/widgets/pull/12)"}'
# The message-path runs below start from this one, saved at wait.
if empty_run linkmsg; then
    snap_save empty-wait
    eq "16 message: a report naming its pull request goes to report_link" report_link \
        "$(at --with-data '{"event":"report","unit":"feat-1","report":"PR is ready","pull_request":"https://github.com/acme/widgets/pull/12"}')"
    link_through message
    # A restart reads the pull request off the holding: reconcile reports its
    # state, not "no pull request". A live run would be resumed where it
    # stands, so this one is cancelled first: the next start carries its
    # record into a new run, whose find and reconcile read it again.
    OLD=$S
    (cd "$WD" && koto cancel "$S" > /dev/null 2>&1)
    sleep 1
    if open_run linkmsg && [ "$S" != "$OLD" ] && grep -qx "carried=$OLD" <<< "$OPEN_OUT" && [ "$(at)" = reconcile ]; then
        koto context get "$S" reconcile/report.md > "$T/rec.md" 2>/dev/null
        grep -q '| `feat-1` | \[#12\](https://github.com/acme/widgets/pull/12) | executing; open (measured)' "$T/rec.md" && ok "16 message: a restart's reconcile reports the pull request open" \
            || bad "16 message: a restart's reconcile reports the pull request open" "$(cat "$T/rec.md")"
        grep -q 'no pull request' "$T/rec.md" && bad "16 message: and never says no pull request" "$(cat "$T/rec.md")" \
            || ok "16 message: and never says no pull request"
    else
        bad "16 message: the restart reaches reconcile" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
    fi
else
    bad "16 message: reach wait with an empty holding" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# The leg path: a stand-in worker template whose result names #12.
mkdir -p "$T/tpl"
cat > "$T/tpl/deliver.md" <<'EOF'
---
name: deliver
version: "1.0"
description: a stand-in worker for coordinate_3_engine_test.sh
initial_state: work
states:
  work:
    accepts:
      finish:
        type: enum
        values: [go]
        required: true
    transitions:
      - target: done
        when:
          finish: go
  done:
    terminal: true
    result:
      outcome: ready
      pr: https://github.com/acme/widgets/pull/12
---
## work
Stand-in.
## done
Done.
EOF
LREQ=$(cd "$T/work" && koto request create --role deliver --template deliver.md --inputs '{}' \
    --requested-by coord --coordinator-of-record coordinate-linkleg | jq -r .request_id)
if [ -n "$LREQ" ] && empty_run linkleg "leg $LREQ:deliver"; then
    (cd "$T" && koto init deliver-feat-1 --template "$T/tpl/deliver.md" --koto-leg "$LREQ:deliver" > /dev/null 2> "$T/child.err" \
        && koto next deliver-feat-1 --with-data '{"finish":"go"}' > /dev/null 2>&1) \
        || bad "16 leg: the stand-in worker promotes its result" "$(cat "$T/child.err")"
    eq "16 leg: a leg result carrying pr goes to report_link" report_link "$(at --with-data '{"event":"leg"}')"
    link_through leg
else
    bad "16 leg: reach wait with a leg-bound empty holding" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# A /work-on worker's leg (shirabe#995): its pull request reaches the leg the
# way work-on.md carries it, written into context on the created edge and read
# back by done's result map, and the run goes on to verify with no re-brief.
cat > "$T/tpl/work-on.md" <<'EOF'
---
name: work-on
version: "1.0"
description: a stand-in /work-on worker for coordinate_3_engine_test.sh
initial_state: pr_creation
states:
  pr_creation:
    accepts:
      pr_status:
        type: enum
        values: [created]
        required: true
      pr_url:
        type: string
    transitions:
      - target: done
        when:
          pr_status: created
        context_assignments:
          pr_url: "${evidence.pr_url}"
  done:
    terminal: true
    result:
      pr: "${context.pr_url}"
---
## pr_creation
Stand-in.
## done
Done.
EOF
WREQ=$(cd "$T/work" && koto request create --role work-on --template work-on.md --inputs '{}' \
    --requested-by coord --coordinator-of-record coordinate-linkworkon | jq -r .request_id)
if [ -n "$WREQ" ] && empty_run linkworkon "leg $WREQ:work-on"; then
    (cd "$T" && koto init work-on-feat-1 --template "$T/tpl/work-on.md" --koto-leg "$WREQ:work-on" > /dev/null 2> "$T/child.err" \
        && koto next work-on-feat-1 --no-cleanup --with-data '{"pr_status":"created","pr_url":"https://github.com/acme/widgets/pull/12"}' > /dev/null 2>&1) \
        || bad "16 work-on leg: the stand-in worker promotes its result" "$(cat "$T/child.err")"
    eq "16 work-on leg: a done result carrying pr goes to report_link" report_link "$(at --with-data '{"event":"leg"}')"
    link_through "work-on leg"
    eq "16 work-on leg: rebrief is never entered" 0 "$(entered rebrief)"
else
    bad "16 work-on leg: reach wait with a leg-bound empty holding" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# done for a report naming no pull request goes back to the hub, never to a
# verify_board that can't leave; the next report naming one gets through.
if snap_load empty-wait; then
    eq "16 none: a report naming no pull request reaches classify_report" classify_report \
        "$(at --with-data '{"event":"report","unit":"feat-1","report":"all done"}')"
    eq "16 none: done with no pull request goes back to wait" wait "$(at --with-data '{"classification":"done"}')"
    eq "16 none: verify is never entered" 0 "$(entered verify)"
    eq "16 none: verify_board is never entered" 0 "$(entered verify_board)"
    eq "16 none: the worker's next report, naming it, reaches report_link" report_link \
        "$(at --with-data '{"event":"report","unit":"feat-1","report":"PR is up","pull_request":"acme/widgets#12"}')"
    link_through none
else
    bad "16 none: reach wait with an empty holding" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
# A leg-bound worker whose result names no pull request: its leg is spent once
# read, so `done` back at the hub has no way on, and the directive's route is
# needs_fix, which reaches rebrief and moves the worker to the message path.
sed -e 's/^name: deliver$/name: deliver-nopr/' -e '/^      pr: /d' "$T/tpl/deliver.md" > "$T/tpl/deliver-nopr.md"
NREQ=$(cd "$T/work" && koto request create --role deliver --template deliver-nopr.md --inputs '{}' \
    --requested-by coord --coordinator-of-record coordinate-linklegnone | jq -r .request_id)
if [ -n "$NREQ" ] && empty_run linklegnone "leg $NREQ:deliver"; then
    (cd "$T" && koto init deliver-nopr-feat-1 --template "$T/tpl/deliver-nopr.md" --koto-leg "$NREQ:deliver" > /dev/null 2> "$T/child.err" \
        && koto next deliver-nopr-feat-1 --with-data '{"finish":"go"}' > /dev/null 2>&1) \
        || bad "16 leg, no pr: the stand-in worker promotes its result" "$(cat "$T/child.err")"
    eq "16 leg, no pr: a result naming no pull request reaches classify_report" classify_report "$(at --with-data '{"event":"leg"}')"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name REPORT)" in
        "holding none feat-1 "*) ok "16 leg, no pr: report_facts reads holding none" ;;
        *) bad "16 leg, no pr: report_facts reads holding none" ;;
    esac
    eq "16 leg, no pr: needs_fix, the directive's route, reaches rebrief" rebrief "$(at --with-data '{"classification":"needs_fix"}')"
    eq "16 leg, no pr: verify is never entered" 0 "$(entered verify)"
else
    bad "16 leg, no pr: reach wait with a leg-bound empty holding" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
# blocked and needs_fix don't route on report_pr, so a holding with no pull
# request still takes them.
for c in "blocked surface" "needs_fix rebrief"; do
    set -- $c
    if snap_load empty-wait; then
        at --with-data '{"event":"report","unit":"feat-1","report":"stuck before any PR"}' > /dev/null
        eq "16 none: $1 with no pull request reaches $2" "$2" "$(at --with-data "{\"classification\":\"$1\"}")"
    else
        bad "16 none: reach wait for $1" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
    fi
done
rm -rf "$GH_BOARD_DIR" && mkdir -p "$GH_BOARD_DIR"

# ---- 12 to 15. the decision loop ----------------------------------------------
ESCF='{"round": "1", "verdict": "escalate", "recommendation": "wait", "reason": "the registry lands Friday", "context": "The loader is done.", "problem": "The registry depends on it.", "grounds": "scope", "target": "a person"}'
SENT=$(jq -nc --argjson e "$ESCF" '$e + {asked: "2026-09-26T07:30Z"}')
UNSENT=$(jq -nc --argjson e "$ESCF" '$e + {owed: "escalation"}')

echo "== 12. a restart takes over every entry before its first dispatch =="
E12=$(jq -nc --argjson a "$(dent 1 proposed)" --argjson b "$(dent 2 coordinator-verdict)" \
    --argjson c "$(dent 3 escalated "$SENT")" --argjson d "$(dent 4 coordinator-verdict '{"verdict": "hold", "reason": "waits on the benchmark"}')" \
    --argjson e "$(dent 5 escalated "$UNSENT")" '[$a, $b, $c, $d, $e]')
to_reconciled takeover "$(with_decisions takeover "$E12")"
if [ "$REACHED" = escalate_send ]; then
    ok "12: the unsent escalation is rendered first, before any dispatch"
    eq "12: the render names entry 5" "message escalation 5 1" "$(bash "$PS/coord-log.sh" capture --session "$S" --name ESCALATE_MESSAGE | cut -d' ' -f1-4)"
    write_as_agent record-decision.sh --sent --route message
    eq "12: --sent (agent-run) marks it" 0 $?
    eq "12: then the proposed entry is taken up" decision_take "$(at --with-data '{"sent":"sent"}')"
    write_as_agent record-decision.sh --take
    eq "12: then the unjudged one is routed for a verdict" decision_verdict "$(at --with-data '{"taken":"taken"}')"
    eq "12: its entry is in coord/decision.json" 1 "$(koto context get "$S" coord/decision.json | jq -r .decision)"
    write_as_agent record-decision.sh --settle --outcome ship --reason "the loader is ready"
    eq "12: then entry 2" decision_verdict "$(at --with-data '{"verdict":"settle","rationale":"ready"}')"
    write_as_agent record-decision.sh --settle --outcome wait --reason "the registry needs it"
    eq "12: with nothing owed the run reaches pick" pick "$(at --with-data '{"verdict":"settle","rationale":"needed"}')"
    eq "12: the escalation was rendered once" 1 "$(entered escalate)"
    eq "12: nothing was dispatched first" 0 "$(entered dispatch_check)"
    eq "12: the sent escalation and the held entry are left alone" "escalated 2026-09-26T07:30Z|coordinator-verdict hold" \
        "$(entry_of 3 | jq -r '"\(.state) \(.asked)"')|$(entry_of 4 | jq -r '"\(.state) \(.verdict)"')"
else
    bad "12: reach escalate_send" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

echo "== 13. an answer that reverses a supplied decision is a reversal =="
E13=$(jq -nc --argjson a "$(dent 1 escalated "$SENT")" '[$a | .source = "dispatcher [20260925T080000Z raise 1]"]')
to_reconciled reversal "$(with_decisions reversal "$E13")"
if [ "$REACHED" = pick ] \
    && [ "$(at --with-data '{"choice":"hold"}')" = wait ]; then
    eq "13: the answer reaches decision_answer" decision_answer "$(at --with-data '{"event":"answer","decision":"1","round":"1"}')"
    write_as_agent record-decision.sh --answer --outcome ship
    eq "13: --answer (agent-run) settles the entry" "settled|ship; reason: the loader is ready|a person" \
        "$(entry_of 1 | jq -r '"\(.state)|\(.outcome)|\(.decided_by)"')"
    eq "13: a reversal goes to decision_apply" decision_apply "$(at --with-data '{"answered":"reversal"}')"
    # The evidence comes first: record waits until the record is written after it.
    eq "13: the reversal holds at record until the record is written" record "$(at --with-data '{"change":"reversal"}')"
    sleep 1
    live_body | jq -c '.reversals += [{date: $d, reversed: "wait for the registry", now: "ship the loader first", reason: "the answer to decision 1", from: "a person"}]' \
        --arg d "$(date -u +%Y-%m-%dT%H:%MZ)" > "$T/rev.json"
    # Edited from the live body, so it carries the live written time.
    jq 'del(.written)' "$T/rev.json" > "$T/rev.next.json"
    bash "$PS/record-render.sh" --container issue --written "$(jq -r .written "$T/rev.json")" "$T/rev.next.json" > "$T/rev.md"
    write_as_agent record-write.sh --body-file "$T/rev.md"
    eq "13: record-write.sh (agent-run) adds the Reversals row" 0 $?
    # The entry came from the dispatcher, so its settle owes it a reply, which
    # the loop renders before it goes on.
    eq "13: record confirms the Reversals row, and the reply to the dispatcher is rendered" decision_reply_send "$(at)"
    write_as_agent record-decision.sh --sent
    eq "13: with the reply sent the run goes on" pick "$(at --with-data '{"sent":"sent"}')"
    eq "13: the Reversals row is on the record" 1 "$(live_body | jq '.reversals | length')"
else
    bad "13: reach wait" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

echo "== 14. a close with an escalation still out reports it and waits =="
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-closing.md"] = $t' --arg t "$(roadmap_text Active | sed 's/\*\*Status:\*\* Planned/**Status:** Done/')"
seed_record closing "$(with_decisions closing "$(jq -nc --argjson a "$(dent 1 escalated "$SENT")" '[$a]')")"
if open_run closing && [ "$(at)" = reconcile ]; then
    eq "14: every feature done and an escalation sent reaches roadmap_blocked" roadmap_blocked "$(at --with-data '{"reconciled":"reported"}')"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name ROADMAP_CLOSE)" in
        "decisions "*) ok "14: the close is blocked on decisions" ;; *) bad "14: the close is blocked on decisions" ;;
    esac
    eq "14: noted returns to wait, where the answer arrives" wait "$(at --with-data '{"noted":"noted"}')"
else
    bad "14: reach reconcile" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

echo "== 15. escalate_send's two routes to a person =="
for route in tool message; do
    to_reconciled "route-$route" "$(with_decisions "route-$route" "$(jq -nc --argjson a "$(dent 1 escalated "$UNSENT")" '[$a]')")"
    if [ "$REACHED" = escalate_send ]; then
        write_as_agent record-decision.sh --sent --route "$route"
        case "$(entry_of 1 | jq -r .evidence)" in
            *"asked by $route"*) ok "15 $route: the route is recorded on the entry" ;; *) bad "15 $route: the route is recorded on the entry" "$(cat "$T/w.err") $(entry_of 1)" ;;
        esac
        if [ "$route" = tool ]; then
            eq "15 tool: the answer comes back from escalate_send" decision_answer "$(at --with-data '{"sent":"answered","decision":"1","round":"1"}')"
        else
            eq "15 message: sent goes on, and nothing is owed" pick "$(at --with-data '{"sent":"sent"}')"
            eq "15 message: the loop goes on to wait" wait "$(at --with-data '{"choice":"hold"}')"
            eq "15 message: an answer naming no round doesn't leave wait" wait "$(at --with-data '{"event":"answer","decision":"1"}')"
            eq "15 message: the answer comes back from wait" decision_answer "$(at --with-data '{"event":"answer","decision":"1","round":"1"}')"
        fi
        write_as_agent record-decision.sh --answer --outcome wait
        eq "15 $route: --answer settles the entry" "settled a person" "$(entry_of 1 | jq -r '"\(.state) \(.decided_by)"')"
        eq "15 $route: recorded goes back through decision_next to pick" pick "$(at --with-data '{"answered":"recorded"}')"
        if [ "$route" = message ]; then
            # A later answer naming nothing isn't carried by the earlier visit's fields.
            eq "15 message: back at wait" wait "$(at --with-data '{"choice":"hold"}')"
            eq "15 message: a later answer naming no decision doesn't leave wait" wait "$(at --with-data '{"event":"answer"}')"
        fi
    else
        bad "15 $route: reach escalate_send" "$(cat "$T/open.err" "$T/tick.err" "$T/w.err" 2>/dev/null)"
    fi
done

echo
echo "coordinate_engine part 3: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
