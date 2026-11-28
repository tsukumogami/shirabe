#!/usr/bin/env bash
# decide-first-routes_test.sh -- /execute's covered exit and its parked steps: the shape of
# execute.md's decide_first, park_own, spawn_and_await's parked edges,
# waiting_record and done_waiting, read from the compiled template; and
# park.sh and parked-state.sh run against a koto stand-in serving recorded
# records.
#
# The scripts run from a copy of their own layout under a scratch directory,
# beside a plan-to-tasks.sh that prints fixtures/park/tasks.json: three steps,
# step-3 waiting on step-1. The koto stand-in (fixtures/park/koto) answers from
# files each case writes; every question's history, content and decision list
# is a recorded fixture, never a live answer.
#
# Cases:
#   the table      fixtures/park/exits.json, /execute's one covered exit, is
#                  exactly the set of edges into decide_first
#   as before      every edge into escalate_upstream_drift and done_blocked
#                  other than decide_first's stop and spawn_and_await's
#                  parked stop is as it was at the merge-base, with its
#                  source, condition and assignments; every state but the
#                  named ones is identical to the merge-base's, the result
#                  maps of merged, ready_awaiting_merge, paused_for_review,
#                  done and done_blocked are equal, and execute-coordinated.md
#                  compiles to the same JSON
#   the template   the intent-changing edge out of worktree_discipline_check
#                  goes to decide_first, keeping failure_reason and assigning
#                  decide_origin and no decide_fresh; decide_first's three edges
#                  (raised to park_own on attempt_recorded 3 and waiting_steps
#                  0, decided resume and stop on decide_from 20) and its
#                  non-overridable gates, resume held by decide_laps;
#                  park_own records the question, then parks, and goes back
#                  to worktree_discipline_check when it closed first;
#                  escalate_parked has no gate; spawn_and_await's pr_finalization
#                  and escalate edges need parked_state 0, its parked edges
#                  route 1 to escalate_parked, 3 to waiting_record, a cited
#                  stop on 4 to escalate_upstream_drift; waiting_record goes
#                  to done_waiting or, on `none`, back to spawn_and_await;
#                  done_waiting is a failure terminal whose result is outcome
#                  waiting and the questions; decide-first-gate.sh maps
#                  worktree_discipline_check to 20
#   parked-state   0 with nothing ever parked, without reading the PLAN; 3
#                  when every step not landed is parked or waits on one, with
#                  a question= line; 1 with a step still running; 1 with a
#                  child failed outright; 4 with a closed question still
#                  parked; 3 for an unmarked child at done_waiting; after a
#                  clear, 1 until every step has a child, then 0
#   decide-first   --from maps worktree_discipline_check to 20; --laps
#                  refuses the fourth arrival from it
#   park.sh        mark --own parks the steps `waiting` names, or every step;
#                  mark --child refuses a child not at done_waiting and parks
#                  one that is; clear refuses an open question and an
#                  uncited answer, clears once the child cites it, and clears
#                  a withdrawn one at once; questions writes the identities,
#                  or `none`; reason appends once; cited answers 0 and 1;
#                  check refuses a step the PLAN does not hold
#
# Usage: bash skills/execute/scripts/decide-first-routes_test.sh
#   The merge-base is taken with DECIDE_FIRST_BASE, else origin/$GITHUB_BASE_REF,
#   else origin/main; the comparisons are skipped, saying so, when it or
#   execute.md at it can't be read.
#
# Exit codes: 0 all cases pass (or jq is absent, every case skipped); 1 a
# case failed.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SRC_ROOT=$(cd "$SKILL_DIR/../.." && pwd)
FIX="$SCRIPT_DIR/fixtures/park"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: want [$2], got [$3]"; fi; }

command -v jq > /dev/null || { echo "SKIP: jq is not on PATH -- no case ran"; exit 0; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/park-test.XXXXXX") || { echo "FAIL: mktemp"; exit 1; }
ktg_on_exit 'rm -rf "$WORK"'

# The merge-base's templates, read before any case runs.
BASE_REF="${DECIDE_FIRST_BASE:-}"
[ -n "$BASE_REF" ] || { [ -n "${GITHUB_BASE_REF:-}" ] && BASE_REF="origin/$GITHUB_BASE_REF"; }
[ -n "$BASE_REF" ] || BASE_REF=origin/main
BASE_DIR="$WORK/base"
BASE_WHY=""
if ! command -v git > /dev/null; then
    BASE_WHY="git is not on PATH"
elif ! BASE_SHA=$(git -C "$SRC_ROOT" merge-base HEAD "$BASE_REF" 2> "$WORK/base.err"); then
    BASE_WHY="no merge-base with $BASE_REF in this clone: $(cat "$WORK/base.err")"
else
    for t in execute/koto-templates/execute.md execute/koto-templates/execute-coordinated.md work-on/koto-templates/work-on.md; do
        mkdir -p "$BASE_DIR/skills/$(dirname "$t")"
        if ! git -C "$SRC_ROOT" show "$BASE_SHA:skills/$t" > "$BASE_DIR/skills/$t" 2> "$WORK/base.err"; then
            BASE_WHY="skills/$t is not readable at $BASE_SHA: $(cat "$WORK/base.err")"
            break
        fi
    done
    [ -z "$BASE_WHY" ] && grep -q '^  decide_first:' "$BASE_DIR/skills/execute/koto-templates/execute.md" \
        && BASE_WHY="the base $BASE_REF already holds /execute's decide_first; the comparison belongs to the pull request that introduced it"
fi

# --- the template --------------------------------------------------------------------

REAL_KOTO=$(command -v koto || true)
if [ -n "$REAL_KOTO" ]; then
    JSON=$("$REAL_KOTO" template compile "$SKILL_DIR/koto-templates/execute.md" 2> "$WORK/compile.err" | tail -1)
    if [ -z "$JSON" ] || [ ! -f "$JSON" ]; then
        fail "execute.md does not compile: $(tail -3 "$WORK/compile.err")"
    else
        holds() { if jq -e "$2" "$JSON" > /dev/null; then pass "$1"; else fail "$1"; fi; }
        # The table: exactly the committed covered exits enter decide_first.
        got=$(jq -c '[.states | to_entries[] | .key as $s | .value.transitions[]? | select(.target == "decide_first")
            | {origin: $s, when: (.when // {})}] | sort_by(.origin)' "$JSON")
        want=$(jq -c '[.[] | {origin, when: {(.field): .value}}] | sort_by(.origin)' "$FIX/exits.json")
        echo "edges into decide_first: $got"
        eq "the edges into decide_first are exactly fixtures/park/exits.json" "$want" "$got"

        # As before: the edges into the two exits, and every untouched state.
        stop_edges() {
            jq -r '.states | to_entries[] | .key as $s | .value.transitions[]?
                | select(.target == "escalate_upstream_drift" or .target == "done_blocked")
                | select($s != "decide_first")
                | select(($s == "spawn_and_await" and .when["gates.parked_stop.exit_code"] != null) | not)
                | "\(.target) <- \($s)|\(.when // {} | tojson)|\(.context_assignments // {} | tojson)"' "$1" | sort
        }
        if [ -n "$BASE_WHY" ]; then
            echo "SKIP: as before: $BASE_WHY"
        else
            BASE_JSON=$("$REAL_KOTO" template compile "$BASE_DIR/skills/execute/koto-templates/execute.md" 2> "$WORK/base-compile.err" | tail -1)
            if [ -z "$BASE_JSON" ] || [ ! -f "$BASE_JSON" ]; then
                fail "execute.md at $BASE_SHA does not compile: $(tail -3 "$WORK/base-compile.err")"
            else
                stop_edges "$JSON" > "$WORK/edges-branch.txt"
                stop_edges "$BASE_JSON" | grep -v '^escalate_upstream_drift <- worktree_discipline_check|' > "$WORK/edges-base.txt"
                echo "edges into escalate_upstream_drift and done_blocked, the new ones left out:"
                sed 's/^/  /' "$WORK/edges-branch.txt"
                echo "the same at $BASE_REF's merge-base, the covered exit left out:"
                sed 's/^/  /' "$WORK/edges-base.txt"
                if diff "$WORK/edges-base.txt" "$WORK/edges-branch.txt" > "$WORK/edges.diff"; then
                    pass "every other edge into escalate_upstream_drift and done_blocked is as it was at the merge-base"
                else
                    fail "the edges into the two exits changed: $(cat "$WORK/edges.diff")"
                fi
                NAMED='["decide_first","park_own","escalate_parked","waiting_record","done_waiting","worktree_discipline_check","spawn_and_await"]'
                jq -S --argjson n "$NAMED" '.states | with_entries(select(.key as $k | $n | index($k) | not))' "$JSON" > "$WORK/states-branch.json"
                jq -S --argjson n "$NAMED" '.states | with_entries(select(.key as $k | $n | index($k) | not))' "$BASE_JSON" > "$WORK/states-base.json"
                if diff "$WORK/states-base.json" "$WORK/states-branch.json" > "$WORK/states.diff"; then
                    pass "every state but the named ones is identical to the merge-base's"
                else
                    fail "a state outside the named ones changed: $(sed -n 1,40p "$WORK/states.diff")"
                fi
                for t in merged ready_awaiting_merge paused_for_review done done_blocked; do
                    eq "the result map of $t is unchanged" "$(jq -cS --arg t "$t" '.states[$t].result' "$BASE_JSON")" "$(jq -cS --arg t "$t" '.states[$t].result' "$JSON")"
                done
                # worktree_discipline_check differs by its one retargeted edge.
                retarget='.states.worktree_discipline_check | .transitions |= map(select(.when.impact != "intent-changing"))'
                eq "worktree_discipline_check differs only in its intent-changing edge" \
                    "$(jq -cS "$retarget" "$BASE_JSON")" "$(jq -cS "$retarget" "$JSON")"
                C_HEAD=$("$REAL_KOTO" template compile "$SKILL_DIR/koto-templates/execute-coordinated.md" 2> "$WORK/c.err" | tail -1)
                C_BASE=$("$REAL_KOTO" template compile "$BASE_DIR/skills/execute/koto-templates/execute-coordinated.md" 2>> "$WORK/c.err" | tail -1)
                if [ -f "$C_HEAD" ] && [ -f "$C_BASE" ] && cmp -s "$C_HEAD" "$C_BASE"; then
                    pass "execute-coordinated.md compiles to the same JSON as at the merge-base"
                else
                    fail "execute-coordinated.md's compiled JSON differs from the merge-base's: $(tail -3 "$WORK/c.err")"
                fi
            fi
        fi

        holds "the intent-changing edge goes to decide_first, keeping failure_reason and assigning the origin" \
            '[.states.worktree_discipline_check.transitions[] | select(.when.impact == "intent-changing")]
             | length == 1 and .[0].target == "decide_first"
               and .[0].context_assignments.decide_origin == "worktree_discipline_check"
               and (.[0].context_assignments | has("decide_fresh") | not)
               and (.[0].context_assignments.failure_reason | startswith("worktree_discipline_check: upstream-drift detected (intent-changing): "))'
        holds "nothing else enters escalate_upstream_drift from worktree_discipline_check" \
            '[.states.worktree_discipline_check.transitions[] | select(.target == "escalate_upstream_drift")] | length == 0'
        holds "decide_first: raised goes to park_own on attempt_recorded 3 and waiting_steps 0" \
            '[.states.decide_first.transitions[] | select(.when.decide_outcome == "raised")]
             | length == 1 and .[0].target == "park_own"
               and .[0].when["gates.attempt_recorded.exit_code"] == 3 and .[0].when["gates.waiting_steps.exit_code"] == 0'
        holds "decide_first: decided resume and stop need attempt_recorded 0 and decide_from 20" \
            '[.states.decide_first.transitions[] | select(.when.decide_outcome == "decided")]
             | length == 2
               and (map({(.when.decided_next): .target}) | add) == {"resume": "worktree_discipline_check", "stop": "escalate_upstream_drift"}
               and all(.[]; .when["gates.attempt_recorded.exit_code"] == 0 and .when["gates.decide_from.exit_code"] == 20)'
        holds "decide_first: resume needs decide_laps 0, stop does not" \
            '[.states.decide_first.transitions[] | select(.when.decide_outcome == "decided")] | map({(.when.decided_next): .when["gates.decide_laps.exit_code"]}) | add
             == {"resume": 0, "stop": null}'
        holds "decide_first's four gates cannot be overridden" \
            '[.states.decide_first.gates[] | .overridable] | length == 4 and all(. == false)'
        holds "park_own goes on once the question is recorded and the steps parked, and back to the check when the question closed first" \
            '(.states.park_own.transitions | map({(.target): .when}) | add) as $p
             | $p.spawn_and_await == {"gates.question_recorded.exists": true, "gates.own_parked.exists": true}
               and $p.worktree_discipline_check == {"gates.question_recorded.exists": false}'
        holds "escalate_parked escalates whether or not the questions could be read" \
            '.states.escalate_parked.transitions == [{"target": "escalate"}] or (.states.escalate_parked.transitions | length == 1 and .[0].target == "escalate" and ((.[0].when // {}) == {}))'
        holds "park_own records the question before it parks" \
            '.states.park_own.default_action.command | test("decide-first-gate.sh\" --record-question .*&& .*park.sh\" mark ")'
        holds "spawn_and_await: pr_finalization and escalate need parked_state 0" \
            '[.states.spawn_and_await.transitions[] | select(.target == "pr_finalization" or .target == "escalate")]
             | length >= 2 and all(.[]; .when["gates.parked_state.exit_code"] == 0)'
        holds "spawn_and_await: 1 with a failed child to escalate_parked, 3 to waiting_record" \
            '[.states.spawn_and_await.transitions[] | select(.when["gates.parked_state.exit_code"] != null) | {t: .target, c: .when["gates.parked_state.exit_code"]}]
             | (map(select(.t == "escalate_parked")) | .[0].c == 1) and (map(select(.t == "waiting_record")) | .[0].c == 3)'
        holds "spawn_and_await: a cited stop on 4 takes escalate_upstream_drift" \
            '[.states.spawn_and_await.transitions[] | select(.target == "escalate_upstream_drift")]
             | length == 1 and .[0].when.parked_next == "stop" and .[0].when["gates.parked_stop.exit_code"] == 0
               and .[0].when["gates.parked_state.exit_code"] == 4'
        holds "waiting_record: questions to done_waiting, none back to spawn_and_await" \
            '(.states.waiting_record.transitions | map({(.target): .when}) | add) as $w
             | $w.done_waiting["gates.none_open.matches"] == false and $w.done_waiting["gates.questions_written.exists"] == true
               and $w.spawn_and_await["gates.none_open.matches"] == true'
        holds "done_waiting is a failure terminal whose result is outcome waiting and the questions" \
            '.states.done_waiting.terminal == true and .states.done_waiting.failure == true
             and .states.done_waiting.result.question == "${context.waiting_questions}"
             and ([.states.waiting_record.transitions[] | select(.target == "done_waiting") | .context_assignments.outcome] == ["waiting"])'
        holds "no state but waiting_record enters done_waiting" \
            '[.states | to_entries[] | select(any(.value.transitions[]?; .target == "done_waiting")) | .key] == ["waiting_record"]'
    fi
else
    echo "SKIP: koto is not on PATH -- the template cases did not run"
fi

# --- the scripts, against the stand-in -----------------------------------------------

mkdir -p "$WORK/tree/skills/execute/scripts" "$WORK/tree/skills/plan/scripts" "$WORK/tree/skills/work-on/scripts" "$WORK/bin"
for f in park.sh park-lib.sh parked-state.sh; do cp "$SCRIPT_DIR/$f" "$WORK/tree/skills/execute/scripts/"; done
cp "$SRC_ROOT/skills/work-on/scripts/decide-first-gate.sh" "$WORK/tree/skills/work-on/scripts/"
printf '#!/usr/bin/env bash\ncat "%s"\n' "$FIX/tasks.json" > "$WORK/tree/skills/plan/scripts/plan-to-tasks.sh"
cp "$FIX/koto" "$WORK/bin/koto"
printf '#!/usr/bin/env bash\necho "shirabe stand-in: not called by these cases" >&2\nexit 70\n' > "$WORK/bin/shirabe"
chmod +x "$WORK/bin/koto" "$WORK/bin/shirabe" "$WORK/tree/skills/plan/scripts/plan-to-tasks.sh"
PATH="$WORK/bin:$PATH"
export KOTO_STUB_DIR="$WORK/k" KOTO_STUB_LOG="$WORK/koto.log"
PARK="$WORK/tree/skills/execute/scripts/park.sh"
STATE="$WORK/tree/skills/execute/scripts/parked-state.sh"
PLAN="$WORK/PLAN-park.md"
printf 'stand-in PLAN; plan-to-tasks.sh is the fixture\n' > "$PLAN"
RUN=execute-park
Q1=11111111-aaaa/000000000001
Q2=22222222-bbbb/000000000002
enc() { printf '%s' "$1" | sed 's|/|%2F|g'; }

reset() { rm -rf "$KOTO_STUB_DIR"; mkdir -p "$KOTO_STUB_DIR"/{ctx,children,status,history,content,list,attempts}; : > "$KOTO_STUB_LOG"; }
key() { mkdir -p "$KOTO_STUB_DIR/ctx/$1"; printf '%s' "$3" > "$KOTO_STUB_DIR/ctx/$1/$(enc "$2")"; }
has_key() { [ -f "$KOTO_STUB_DIR/ctx/$1/$(enc "$2")" ]; }
getkey() { cat "$KOTO_STUB_DIR/ctx/$1/$(enc "$2")"; }
# question <id> open|answered|withdrawn [<answer session:id>]
question() {
    local h
    case "$2" in
        open) h='{"open":true,"question":{"state":"worktree_discipline_check:1"},"answer":null}' ;;
        answered) h=$(jq -cn --arg s "${3%%:*}" --arg i "${3##*:}" '{open:false,question:{state:"worktree_discipline_check:1"},answer:{session:$s,id:$i,outcome:"answered"}}') ;;
        withdrawn) h='{"open":false,"question":{"state":"worktree_discipline_check:1"},"answer":null}' ;;
    esac
    printf '%s\n' "$h" > "$KOTO_STUB_DIR/history/$(enc "$1").json"
}
# children <step>=<state>:<terminal>:<status>[:<question>] ...
children() {
    local c name st term rs q list="[]"
    for c in "$@"; do
        name="$RUN.${c%%=*}"
        IFS=: read -r st term rs q <<EOF
${c#*=}
EOF
        list=$(printf '%s' "$list" | jq -c --arg n "$name" '. + [{name: $n}]')
        jq -cn --arg s "$st" --argjson t "$term" --arg r "$rs" --arg q "${q:-}" \
            '{current_state: $s, is_terminal: $t}
             + (if $r == "none" then {} else {result: ({status: $r} + (if $q == "" then {} else {payload: {outcome: "waiting", question: $q}} end))} end)' \
            > "$KOTO_STUB_DIR/status/$name.json"
    done
    printf '%s\n' "$list" > "$KOTO_STUB_DIR/children/$RUN.json"
}
cites() { # cites <session> <answer session:id>
    jq -cn --arg s "${2%%:*}" --arg i "${2##*:}" '{decisions: [{decision: {basis: [{session: $s, id: $i}]}}]}' \
        > "$KOTO_STUB_DIR/list/$1.json"
}
run_state() { OUT=$(bash "$STATE" "$RUN" "$PLAN" 2> "$WORK/err"); RC=$?; }

# 0: nothing ever parked, and the PLAN is never read.
reset
children step-1=done:true:success
run_state
eq "parked-state: nothing parked exits 0" 0 "$RC"
rm -f "$PLAN"
run_state
eq "parked-state: nothing parked exits 0 without reading the PLAN" 0 "$RC"
printf 'stand-in PLAN\n' > "$PLAN"

# 3: step-1 parked on an open question, step-2 landed, step-3 waits on step-1.
reset
key "$RUN" parked/step-1 "$Q1"; key "$RUN" parked_ever yes
question "$Q1" open
children step-1=initial:false:none step-2=done:true:success
run_state
eq "parked-state: every step not landed is parked or waits on one: 3" 3 "$RC"
eq "parked-state: names the open question" "question=$Q1" "$OUT"

# 1: step-2 still running.
children step-1=initial:false:none step-2=implementation:false:none
run_state
eq "parked-state: a step still running: 1" 1 "$RC"

# 1: step-2 failed outright.
children step-1=initial:false:none step-2=done_blocked:true:failure
run_state
eq "parked-state: a child failed outright: 1" 1 "$RC"

# 4: the question closed, the key not cleared.
children step-1=initial:false:none step-2=done:true:success
question "$Q1" answered manager:000000000009
run_state
eq "parked-state: a closed question still parked holds at 4" 4 "$RC"

# 3: an unmarked child at done_waiting.
reset
question "$Q2" open
children step-1=done_waiting:true:failure:"$Q2" step-2=done:true:success
run_state
eq "parked-state: an unmarked child at done_waiting: 3" 3 "$RC"

# After a clear: 1 until every step has a child, then 0.
reset
key "$RUN" parked_ever yes
children step-1=done:true:success step-2=done:true:success
run_state
eq "parked-state: cleared, a step with no child yet: 1" 1 "$RC"
children step-1=done:true:success step-2=done:true:success step-3=done:true:success
run_state
eq "parked-state: cleared, every step has a child: 0" 0 "$RC"

# park.sh mark --own.
reset
key "$RUN" decide_question "$Q1"
printf '{"waiting":["step-1"]}\n' > "$KOTO_STUB_DIR/content/$(enc "$Q1").json"
bash "$PARK" mark "$RUN" --own --plan "$PLAN" > /dev/null; RC=$?
eq "park.sh mark --own exits 0" 0 "$RC"
if has_key "$RUN" parked/step-1 && ! has_key "$RUN" parked/step-2 && [ "$(getkey "$RUN" parked_ever)" = yes ]; then
    pass "park.sh mark --own parks only the step waiting names"
else
    fail "park.sh mark --own parks only the step waiting names"
fi
reset
key "$RUN" decide_question "$Q1"
printf '{"waiting":[]}\n' > "$KOTO_STUB_DIR/content/$(enc "$Q1").json"
bash "$PARK" mark "$RUN" --own --plan "$PLAN" > /dev/null
if has_key "$RUN" parked/step-1 && has_key "$RUN" parked/step-2 && has_key "$RUN" parked/step-3; then
    pass "park.sh mark --own with no waiting parks every step"
else
    fail "park.sh mark --own with no waiting parks every step"
fi

# park.sh mark --child.
reset
question "$Q2" open
children step-2=implementation:false:none
bash "$PARK" mark "$RUN" --child "$RUN.step-2" > /dev/null 2>> "$WORK/err"; RC=$?
eq "park.sh mark --child refuses a child not at done_waiting" 1 "$RC"
has_key "$RUN" parked/step-2 && fail "park.sh mark --child wrote a key it refused" || pass "park.sh mark --child writes nothing on a refusal"
children step-2=done_waiting:true:failure:"$Q2"
OUT=$(bash "$PARK" mark "$RUN" --child "$RUN.step-2"); RC=$?
eq "park.sh mark --child parks a waiting child and prints its question" "0 $Q2" "$RC $OUT"

# park.sh clear.
reset
key "$RUN" parked/step-2 "$Q2"
question "$Q2" open
children step-2=done_waiting:true:failure:"$Q2"
bash "$PARK" clear "$RUN" step-2 2>> "$WORK/err"; RC=$?
eq "park.sh clear refuses while the question is open" 1 "$RC"
question "$Q2" answered manager:000000000007
bash "$PARK" clear "$RUN" step-2 2>> "$WORK/err"; RC=$?
eq "park.sh clear refuses an answer nothing cites" 1 "$RC"
has_key "$RUN" parked/step-2 && pass "park.sh clear keeps the key on a refusal" || fail "park.sh clear keeps the key on a refusal"
cites "$RUN.step-2" manager:000000000007
bash "$PARK" clear "$RUN" step-2; RC=$?
eq "park.sh clear clears once the child cites the answer" 0 "$RC"
has_key "$RUN" parked/step-2 && fail "park.sh clear left the key" || pass "park.sh clear removed the key"
key "$RUN" parked/step-2 "$Q2"
question "$Q2" withdrawn
OUT=$(bash "$PARK" clear "$RUN" step-2); RC=$?
eq "park.sh clear clears a withdrawn question at once" "0 withdrawn" "$RC $OUT"

# park.sh questions, reason, cited.
reset
key "$RUN" parked/step-1 "$Q1"
question "$Q1" open
bash "$PARK" questions "$RUN"; RC=$?
eq "park.sh questions writes the open identities" "0 $Q1" "$RC $(getkey "$RUN" waiting_questions)"
question "$Q1" answered manager:000000000003
bash "$PARK" questions "$RUN"
eq "park.sh questions writes none when nothing is open" none "$(getkey "$RUN" waiting_questions)"
question "$Q1" open
key "$RUN" failure_reason "spawn_and_await: 1 failed"
bash "$PARK" reason "$RUN"; bash "$PARK" reason "$RUN"
eq "park.sh reason appends the open questions once" "spawn_and_await: 1 failed; open questions: $Q1" "$(getkey "$RUN" failure_reason)"
question "$Q1" answered manager:000000000003
bash "$PARK" cited "$RUN"; RC=$?
eq "park.sh cited: 1 before the run cites the answer" 1 "$RC"
cites "$RUN" manager:000000000003
bash "$PARK" cited "$RUN"; RC=$?
eq "park.sh cited: 0 once the run cites it" 0 "$RC"

# park.sh check.
reset
key "$RUN" decide_arrival worktree_discipline_check:1
question "$Q1" open
jq -cn --arg s "$RUN" --arg q "$Q1" '{attempts: [{session: $s, status: "in-effect", state: "worktree_discipline_check:1", result: "undecided", questions: [$q]}]}' \
    > "$KOTO_STUB_DIR/attempts/$RUN.json"
printf '{"waiting":["step-9"]}\n' > "$KOTO_STUB_DIR/content/$(enc "$Q1").json"
OUT=$(bash "$PARK" check "$RUN" --plan "$PLAN"); RC=$?
eq "park.sh check refuses a step the PLAN does not hold" 1 "$RC"
case "$OUT" in *'"rule_id":"execute/park"'*step-9*) pass "park.sh check's finding names the step" ;; *) fail "park.sh check's finding: [$OUT]" ;; esac
printf '{"waiting":["step-3"]}\n' > "$KOTO_STUB_DIR/content/$(enc "$Q1").json"
bash "$PARK" check "$RUN" --plan "$PLAN" > /dev/null; RC=$?
eq "park.sh check passes a step the PLAN holds" 0 "$RC"

# decide-first-gate.sh --from knows /execute's covered exit.
reset
key "$RUN" decide_origin worktree_discipline_check
bash "$WORK/tree/skills/work-on/scripts/decide-first-gate.sh" --from "$RUN" > /dev/null; RC=$?
eq "decide-first-gate.sh --from maps worktree_discipline_check to 20" 20 "$RC"
key "$RUN" decide_laps_worktree_discipline_check 3
bash "$WORK/tree/skills/work-on/scripts/decide-first-gate.sh" --laps "$RUN" > /dev/null; RC=$?
eq "decide-first-gate.sh --laps allows the third arrival" 0 "$RC"
key "$RUN" decide_laps_worktree_discipline_check 4
OUT=$(bash "$WORK/tree/skills/work-on/scripts/decide-first-gate.sh" --laps "$RUN"); RC=$?
eq "decide-first-gate.sh --laps refuses the fourth arrival" 1 "$RC"
case "$OUT" in *'"rule_id":"work-on/decide-first"'*'past the cap'*) pass "--laps's finding names the cap" ;; *) fail "--laps's finding: [$OUT]" ;; esac

echo
echo "park_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
