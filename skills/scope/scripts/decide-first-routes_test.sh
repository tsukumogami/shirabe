#!/usr/bin/env bash
# decide-first-routes_test.sh -- do /scope's unsettled exits pass through
# decide_first, and is everything else in scope.md as it was?
# Part of the scope skill
#
# Usage: bash skills/scope/scripts/decide-first-routes_test.sh
#
# The shipped scope.md is compiled with koto and read with jq:
#
#   the table   exactly five edges enter decide_first: each hop's bail
#               (hop_brief, hop_prd, hop_design, hop_plan) and
#               full_run_blocked's abandon, each assigning its own
#               decide_origin and decide_fresh "yes".
#   the routes  decide_first's raised edge goes to waiting_record on an
#               undecided attempt (exit 3); a decided resume needs a
#               deciding attempt (exit 0), the origin's code (30-34) and
#               decide_laps 0, and goes back to the origin; a decided stop
#               needs the attempt and the code, and goes to bail from a hop
#               and to exit_abandonment from full_run_blocked. Its three
#               gates cannot be overridden and each has a timeout.
#               (A context-exists gate runs no command and takes none.)
#   the wait    waiting_record goes to done_waiting once the question is in
#               context, and back to the origin when it is not, so the state
#               has a way out; done_waiting is a failure terminal whose
#               result carries outcome and question.
#   as before   against the merge-base with the base branch (DECIDE_FIRST_BASE,
#               else origin/$GITHUB_BASE_REF, else origin/main): each of the
#               five origin states differs only in its one edge, which went
#               to bail (or exit_abandonment) and now goes to decide_first;
#               every other state but the three new ones is identical; the
#               result maps of the terminals are unchanged. Skipped with a
#               reason when the clone holds no merge-base, or when the base
#               already holds /scope's decide_first.
#
# The run itself (arrive, raise, continue) is decide-first-gate.sh's and
# scope-open.sh's; their suites cover it.
#
# Exit codes: 0 all cases pass (or koto or jq is absent, every case skipped);
# 1 a case failed.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SRC_ROOT=$(cd "$SKILL_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: want [$2], got [$3]"; fi; }

command -v jq > /dev/null || { echo "SKIP: jq is not on PATH -- no case ran"; exit 0; }
REAL_KOTO=$(command -v koto || true)
[ -n "$REAL_KOTO" ] || { echo "SKIP: koto is not on PATH -- no case ran"; exit 0; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/scope-decide-first.XXXXXX") || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

JSON=$("$REAL_KOTO" template compile "$SKILL_DIR/koto-templates/scope.md" 2> "$WORK/compile.err" | tail -1)
if [ -z "$JSON" ] || [ ! -f "$JSON" ]; then
    echo "FAIL: scope.md does not compile: $(tail -3 "$WORK/compile.err")"
    exit 1
fi
holds() { if jq -e "$2" "$JSON" > /dev/null; then pass "$1"; else fail "$1"; fi; }

# --- the table ------------------------------------------------------------------

want='[{"origin":"full_run_blocked","when":{"next_move":"abandon"}},{"origin":"hop_brief","when":{"outcome":"bail"}},{"origin":"hop_design","when":{"outcome":"bail"}},{"origin":"hop_plan","when":{"outcome":"bail"}},{"origin":"hop_prd","when":{"outcome":"bail"}}]'
got=$(jq -c '[.states | to_entries[] | .key as $s | .value.transitions[]? | select(.target == "decide_first")
    | {origin: $s, when: (.when // {})}] | sort_by(.origin)' "$JSON")
echo "edges into decide_first: $got"
eq "exactly the five unsettled exits enter decide_first" "$want" "$got"
holds "each edge into decide_first assigns its own origin and decide_fresh yes" \
    '[.states | to_entries[] | .key as $s | .value.transitions[]? | select(.target == "decide_first")
      | .context_assignments.decide_origin == $s and .context_assignments.decide_fresh == "yes"] | length == 5 and all'

# --- the routes -----------------------------------------------------------------

holds "decide_first: raised goes to waiting_record on attempt_recorded 3, and only there" \
    '[.states.decide_first.transitions[] | select(.when.decide_outcome == "raised")]
     | length == 1 and .[0].target == "waiting_record" and .[0].when["gates.attempt_recorded.exit_code"] == 3'
holds "decide_first: a decided resume goes back to the origin its code names, with decide_laps 0" \
    '[.states.decide_first.transitions[] | select(.when.decided_next == "resume")]
     | length == 5
       and all(.[]; .when.decide_outcome == "decided" and .when["gates.attempt_recorded.exit_code"] == 0
                    and .when["gates.decide_laps.exit_code"] == 0)
       and (map({(.when["gates.decide_from.exit_code"] | tostring): .target}) | add)
           == {"30": "hop_brief", "31": "hop_prd", "32": "hop_design", "33": "hop_plan", "34": "full_run_blocked"}'
holds "decide_first: a decided stop goes to bail from a hop and to exit_abandonment from full_run_blocked" \
    '[.states.decide_first.transitions[] | select(.when.decided_next == "stop")]
     | length == 5
       and all(.[]; .when.decide_outcome == "decided" and .when["gates.attempt_recorded.exit_code"] == 0
                    and .when["gates.decide_laps.exit_code"] == null)
       and (map({(.when["gates.decide_from.exit_code"] | tostring): .target}) | add)
           == {"30": "bail", "31": "bail", "32": "bail", "33": "bail", "34": "exit_abandonment"}'
holds "decide_first has no edge but raised, resume and stop" \
    '.states.decide_first.transitions | length == 11'
holds "decide_first's three gates cannot be overridden and each has a timeout" \
    '[.states.decide_first.gates[]] | length == 3 and all(.[]; .overridable == false and (.timeout // 0) > 0)'
holds "decide_first arrives through decide-first-gate.sh" \
    '.states.decide_first.default_action.command | test("decide-first-gate\\.sh\" --arrive ")'

# --- the wait -------------------------------------------------------------------

holds "waiting_record goes to done_waiting once the question is recorded, setting outcome waiting" \
    '[.states.waiting_record.transitions[] | select(.target == "done_waiting")]
     | length == 1 and .[0].when == {"gates.question_recorded.exists": true}
       and .[0].context_assignments.outcome == "waiting"'
holds "waiting_record's way out goes back to the origin when no question is recorded" \
    '[.states.waiting_record.transitions[] | select(.when["gates.question_recorded.exists"] == false)]
     | (map({(.when["gates.decide_from.exit_code"] | tostring): .target}) | add)
       == {"30": "hop_brief", "31": "hop_prd", "32": "hop_design", "33": "hop_plan", "34": "full_run_blocked"}'
holds "waiting_record's gates cannot be overridden, and its command gate has a timeout" \
    '[.states.waiting_record.gates[]] | length == 2 and all(.[]; .overridable == false)
       and all(.[] | select(.type == "command"); (.timeout // 0) > 0)'
holds "done_waiting is a failure terminal carrying outcome and question" \
    '.states.done_waiting | .terminal == true and .failure == true
       and .result.outcome == "${context.outcome}" and .result.question == "${context.decide_question}"'
holds "done_waiting's directive prints the exit through print-scope-exit.sh" \
    '.states.done_waiting.directive | test("print-scope-exit\\.sh\" --topic ")'

# --- as before ------------------------------------------------------------------

BASE_REF="${DECIDE_FIRST_BASE:-}"
[ -n "$BASE_REF" ] || { [ -n "${GITHUB_BASE_REF:-}" ] && BASE_REF="origin/$GITHUB_BASE_REF"; }
[ -n "$BASE_REF" ] || BASE_REF=origin/main
BASE_WHY=""
mkdir -p "$WORK/base"
if ! command -v git > /dev/null; then
    BASE_WHY="git is not on PATH"
elif ! BASE_SHA=$(git -C "$SRC_ROOT" merge-base HEAD "$BASE_REF" 2> "$WORK/base.err"); then
    BASE_WHY="no merge-base with $BASE_REF in this clone: $(cat "$WORK/base.err")"
elif ! git -C "$SRC_ROOT" show "$BASE_SHA:skills/scope/koto-templates/scope.md" > "$WORK/base/scope.md" 2> "$WORK/base.err"; then
    BASE_WHY="scope.md is not readable at $BASE_SHA: $(cat "$WORK/base.err")"
elif grep -q '^  decide_first:' "$WORK/base/scope.md"; then
    BASE_WHY="the base $BASE_REF already holds /scope's decide_first; the comparison belongs to the pull request that introduced it"
fi

if [ -n "$BASE_WHY" ]; then
    echo "SKIP: as before: $BASE_WHY"
else
    BASE_JSON=$("$REAL_KOTO" template compile "$WORK/base/scope.md" 2> "$WORK/base-compile.err" | tail -1)
    if [ -z "$BASE_JSON" ] || [ ! -f "$BASE_JSON" ]; then
        fail "scope.md at $BASE_SHA does not compile: $(tail -3 "$WORK/base-compile.err")"
    else
        # Each origin differs by its one edge: drop it on both sides and compare.
        for spec in hop_brief:outcome:bail:bail hop_prd:outcome:bail:bail hop_design:outcome:bail:bail \
                hop_plan:outcome:bail:bail full_run_blocked:next_move:abandon:exit_abandonment; do
            st=${spec%%:*}; rest=${spec#*:}; f=${rest%%:*}; rest=${rest#*:}; v=${rest%%:*}; old=${rest#*:}
            eq "$st: its $f=$v edge went to $old at the merge-base" "$old" \
                "$(jq -r --arg s "$st" --arg f "$f" --arg v "$v" '[.states[$s].transitions[] | select(.when[$f] == $v)] | map(.target) | join(",")' "$BASE_JSON")"
            drop='.states[$s] | .transitions |= map(select(.when[$f] != $v))'
            eq "$st differs from the merge-base only in its $f=$v edge" \
                "$(jq -cS --arg s "$st" --arg f "$f" --arg v "$v" "$drop" "$BASE_JSON")" \
                "$(jq -cS --arg s "$st" --arg f "$f" --arg v "$v" "$drop" "$JSON")"
        done
        NAMED='["decide_first","waiting_record","done_waiting","hop_brief","hop_prd","hop_design","hop_plan","full_run_blocked"]'
        jq -S --argjson n "$NAMED" '.states | with_entries(select(.key as $k | $n | index($k) | not))' "$JSON" > "$WORK/states-branch.json"
        jq -S --argjson n "$NAMED" '.states | with_entries(select(.key as $k | $n | index($k) | not))' "$BASE_JSON" > "$WORK/states-base.json"
        if diff "$WORK/states-base.json" "$WORK/states-branch.json" > "$WORK/states.diff"; then
            pass "every state but the named ones is identical to the merge-base's"
        else
            fail "a state outside the named ones changed: $(sed -n 1,40p "$WORK/states.diff")"
        fi
        for t in $(jq -r '.states | to_entries[] | select(.value.terminal == true) | .key' "$BASE_JSON"); do
            eq "the result map of $t is unchanged" "$(jq -cS --arg t "$t" '.states[$t].result' "$BASE_JSON")" "$(jq -cS --arg t "$t" '.states[$t].result' "$JSON")"
        done
    fi
fi

echo
echo "passed: $PASS_COUNT   failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
