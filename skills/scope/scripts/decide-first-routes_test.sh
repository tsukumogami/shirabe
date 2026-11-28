#!/usr/bin/env bash
# decide-first-routes_test.sh -- do /scope's unsettled exits pass through
# decide_first, and is everything else in scope.md as it was?
# Part of the scope skill
#
# Usage: bash skills/scope/scripts/decide-first-routes_test.sh
#
# The shipped scope.md is compiled with koto and read with jq:
#
#   the table   exactly five edges outside the decide states enter
#               decide_first: each hop's bail (hop_brief, hop_prd,
#               hop_design, hop_plan) and full_run_blocked's abandon, each
#               assigning its own decide_origin and no decide_fresh (the gate
#               counts arrivals from the decide_origin writes).
#   the routes  decide_first's raised edge goes to waiting_record on an
#               undecided attempt (exit 3); a decided resume needs a
#               deciding attempt (exit 0), the origin's code (30-34) and
#               decide_laps 0, and goes back to the origin; a decided stop
#               needs the attempt and the code, and goes to bail from a hop
#               and to exit_abandonment from full_run_blocked. Its three
#               gates cannot be overridden and each has a timeout.
#               (A context-exists gate runs no command and takes none.)
#   the wait    waiting_record records the question with --record-question
#               and goes to done_waiting on --recorded's 0, and back to
#               decide_first on 1, writing no decide_origin, so the state has
#               a way out that is not a new arrival; done_waiting is a failure terminal whose
#               result carries outcome and question.
#   as before   against the merge-base with the base branch (DECIDE_FIRST_BASE,
#               else origin/$GITHUB_BASE_REF, else origin/main): each of the
#               five origin states differs only in its one edge, which went
#               to bail (or exit_abandonment) and now goes to decide_first;
#               every other state but the three new ones is identical; the
#               result maps of the terminals are unchanged. When the clone
#               holds no merge-base, or the base already holds /scope's
#               decide_first, the comparison is pinned to history: the commit
#               that added decide_first to scope.md against its parent. With
#               neither it is skipped with a reason, and under CI
#               (GITHUB_ACTIONS) it fails.
#   one script  the attempt_recorded gates of work-on.md, execute.md and
#               scope.md run the same script path.
#   earlier     a session opened on the merge-base's scope.md, with the
#               branch's skill files as its plugin root, still reaches bail
#               on a hop's `outcome: bail`. Read from the same commit as the
#               comparison, and skipped or failed with it.
#   the walk    real sessions, opened through scope-open.sh in a scratch koto
#               store, with a stand-in `manager` session linked as the
#               dispatcher before anything is raised:
#                 from hop_design, `outcome: bail`, an undecided attempt, the
#                 raised question and `raised` end at done_waiting with
#                 outcome waiting and the question; the work tree and HEAD
#                 are as before the bail, no forced_artifact is recorded,
#                 and no document carries the abandonment marker. The
#                 open's one rewind lands at waiting_record, and the next
#                 tick at decide_first, so the run never stood at bail.
#                 A second open while the question is open prints waiting=
#                 and exit 3, and the session stays at done_waiting.
#                 Once manager answers, the open prints continued=waiting
#                 and no replacement, the first tick takes the session to
#                 decide_first and carries `questions`, and `decided` is held
#                 until an attempt citing the answer is recorded. Then
#                 `resume` delivers hop_design's own directive again, and in
#                 a second topic `stop` reaches bail.
#                 The same pair from full_run_blocked on `next_move:
#                 abandon`: resume back to full_run_blocked, stop to
#                 exit_abandonment.
#               The walk needs a shirabe with `question precedent` (SHIRABE_BIN,
#               else target/release/shirabe, else PATH): without one it is
#               skipped with a reason, and under CI (GITHUB_ACTIONS) it fails.
#               It also needs a path koto admits in a --var for the plugin
#               root, the checkout or a symlink under TMPDIR; without one it
#               is skipped with a reason. The answer comes from the stand-in
#               session with `koto decisions answer --by=session`, a recorded
#               value, not a person.
#
# Exit codes: 0 all cases pass (or koto or jq is absent, every case skipped);
# 1 a case failed.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
unset KOTO_RUN_MODE CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID
unset KOTO_DECIDER KOTO_DECIDER_API_KEY KOTO_DECIDER_ENDPOINT
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
ktg_on_exit 'rm -rf "$WORK"'

JSON=$("$REAL_KOTO" template compile "$SKILL_DIR/koto-templates/scope.md" 2> "$WORK/compile.err" | tail -1)
if [ -z "$JSON" ] || [ ! -f "$JSON" ]; then
    echo "FAIL: scope.md does not compile: $JSON $(tail -3 "$WORK/compile.err")"
    exit 1
fi
holds() { if jq -e "$2" "$JSON" > /dev/null; then pass "$1"; else fail "$1"; fi; }

# --- the table ------------------------------------------------------------------

want='[{"origin":"full_run_blocked","when":{"next_move":"abandon"}},{"origin":"hop_brief","when":{"outcome":"bail"}},{"origin":"hop_design","when":{"outcome":"bail"}},{"origin":"hop_plan","when":{"outcome":"bail"}},{"origin":"hop_prd","when":{"outcome":"bail"}}]'
got=$(jq -c '[.states | to_entries[] | select(.key != "waiting_record") | .key as $s | .value.transitions[]? | select(.target == "decide_first")
    | {origin: $s, when: (.when // {})}] | sort_by(.origin)' "$JSON")
echo "edges into decide_first: $got"
eq "exactly the five unsettled exits enter decide_first, besides waiting_record's way back" "$want" "$got"
holds "each edge into decide_first assigns its own origin and no decide_fresh" \
    '[.states | to_entries[] | select(.key != "waiting_record") | .key as $s | .value.transitions[]? | select(.target == "decide_first")
      | .context_assignments.decide_origin == $s and (.context_assignments | has("decide_fresh") | not)] | length == 5 and all'

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

holds "waiting_record records the question with --record-question" \
    '.states.waiting_record.default_action.command | test("decide-first-gate\\.sh\" --record-question ")'
holds "waiting_record goes to done_waiting on --recorded's 0, setting outcome waiting" \
    '[.states.waiting_record.transitions[] | select(.target == "done_waiting")]
     | length == 1 and .[0].when == {"gates.question_recorded.exit_code": 0}
       and .[0].context_assignments.outcome == "waiting"'
holds "waiting_record's way out goes back to decide_first on 1, writing no decide_origin" \
    '[.states.waiting_record.transitions[] | select(.target != "done_waiting")]
     | length == 1 and .[0].target == "decide_first" and .[0].when == {"gates.question_recorded.exit_code": 1}
       and ((.[0].context_assignments // {}) | has("decide_origin") | not)'
holds "waiting_record's one gate is --recorded, not overridable, with a timeout" \
    '[.states.waiting_record.gates[]] | length == 1 and all(.[]; .overridable == false and (.timeout // 0) > 0)
       and (.[0].command | test("decide-first-gate\\.sh\" --recorded "))'
holds "done_waiting is a failure terminal carrying outcome and question" \
    '.states.done_waiting | .terminal == true and .failure == true
       and .result.outcome == "${context.outcome}" and .result.question == "${context.decide_question}"'
holds "done_waiting's directive prints the exit through print-scope-exit.sh" \
    '.states.done_waiting.directive | test("print-scope-exit\\.sh\" --topic ")'

# --- as before ------------------------------------------------------------------

BASE_REF="${DECIDE_FIRST_BASE:-}"
[ -n "$BASE_REF" ] || { [ -n "${GITHUB_BASE_REF:-}" ] && BASE_REF="origin/$GITHUB_BASE_REF"; }
[ -n "$BASE_REF" ] || BASE_REF=origin/main
# Under CI the checkout is one commit deep, which has no merge-base with
# anything. The suite fetches the one ref it compares against, with the
# history a merge-base needs, before looking; nowhere else does it fetch.
if [ "${GITHUB_ACTIONS:-}" = true ] && [ -z "${DECIDE_FIRST_BASE:-}" ] && command -v git > /dev/null \
    && ! git -C "$SRC_ROOT" merge-base HEAD "$BASE_REF" > /dev/null 2>&1; then
    FETCH_REF="${BASE_REF#origin/}"
    if [ "$(git -C "$SRC_ROOT" rev-parse --is-shallow-repository 2> /dev/null)" = true ]; then
        git -C "$SRC_ROOT" fetch --no-tags --unshallow origin "+refs/heads/$FETCH_REF:refs/remotes/origin/$FETCH_REF" > "$WORK/fetch.out" 2>&1
    else
        git -C "$SRC_ROOT" fetch --no-tags origin "+refs/heads/$FETCH_REF:refs/remotes/origin/$FETCH_REF" > "$WORK/fetch.out" 2>&1
    fi || echo "note: fetching $BASE_REF failed: $(tail -2 "$WORK/fetch.out")"
fi
BASE_WHY=""
mkdir -p "$WORK/base"
if ! command -v git > /dev/null; then
    BASE_WHY="git is not on PATH"
elif ! BASE_SHA=$(git -C "$SRC_ROOT" merge-base HEAD "$BASE_REF" 2> "$WORK/base.err"); then
    BASE_WHY="no merge-base with $BASE_REF in this clone: $(cat "$WORK/base.err")"
elif ! git -C "$SRC_ROOT" show "$BASE_SHA:skills/scope/koto-templates/scope.md" > "$WORK/base/scope.md" 2> "$WORK/base.err"; then
    BASE_WHY="scope.md is not readable at $BASE_SHA: $(cat "$WORK/base.err")"
elif grep -q '^  decide_first:' "$WORK/base/scope.md"; then
    BASE_WHY="the base $BASE_REF already holds /scope's decide_first"
fi
CMP_JSON="$JSON"
CMP_WHAT="the merge-base with $BASE_REF"

# With no merge-base to read, or one that already holds decide_first, the
# comparison is pinned to history, as /work-on's and /execute's routes suites
# do: the commit that added decide_first to scope.md, against its parent.
if [ -n "$BASE_WHY" ] && command -v git > /dev/null; then
    if git -C "$SRC_ROOT" log --format=%H -S'  decide_first:' -- skills/scope/koto-templates/scope.md > "$WORK/pin.log" 2> "$WORK/pin.err"; then
        PIN_SHA=$(sed -n '$p' "$WORK/pin.log")
        if [ -z "$PIN_SHA" ]; then
            BASE_WHY="$BASE_WHY, and no commit in this clone adds decide_first to scope.md"
        elif ! git -C "$SRC_ROOT" show "$PIN_SHA^:skills/scope/koto-templates/scope.md" > "$WORK/base/scope.md" 2> "$WORK/pin.err"; then
            BASE_WHY="$BASE_WHY, and scope.md is not readable at $PIN_SHA^: $(cat "$WORK/pin.err")"
        elif ! git -C "$SRC_ROOT" show "$PIN_SHA:skills/scope/koto-templates/scope.md" > "$WORK/pin-scope.md" 2> "$WORK/pin.err"; then
            BASE_WHY="$BASE_WHY, and scope.md is not readable at $PIN_SHA: $(cat "$WORK/pin.err")"
        else
            CMP_JSON=$("$REAL_KOTO" template compile "$WORK/pin-scope.md" 2> "$WORK/pin.err" | tail -1)
            if [ -z "$CMP_JSON" ] || [ ! -f "$CMP_JSON" ]; then
                BASE_WHY="$BASE_WHY, and scope.md at $PIN_SHA does not compile: $CMP_JSON $(tail -3 "$WORK/pin.err")"
            else
                BASE_SHA="$PIN_SHA^"
                CMP_WHAT="the parent of $PIN_SHA, the commit that added decide_first"
                BASE_WHY=""
            fi
        fi
    else
        BASE_WHY="$BASE_WHY, and git log failed: $(cat "$WORK/pin.err")"
    fi
fi
# skip_or_fail <what>: a comparison that could not run skips, and fails under CI.
skip_or_fail() {
    if [ "${GITHUB_ACTIONS:-}" = true ]; then fail "$1 can't run under CI: $BASE_WHY"; else echo "SKIP: $1: $BASE_WHY"; fi
}

if [ -n "$BASE_WHY" ]; then
    skip_or_fail "as before"
else
    echo "as before: against $CMP_WHAT"
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
                "$(jq -cS --arg s "$st" --arg f "$f" --arg v "$v" "$drop" "$CMP_JSON")"
        done
        NAMED='["decide_first","waiting_record","done_waiting","hop_brief","hop_prd","hop_design","hop_plan","full_run_blocked"]'
        jq -S --argjson n "$NAMED" '.states | with_entries(select(.key as $k | $n | index($k) | not))' "$CMP_JSON" > "$WORK/states-branch.json"
        jq -S --argjson n "$NAMED" '.states | with_entries(select(.key as $k | $n | index($k) | not))' "$BASE_JSON" > "$WORK/states-base.json"
        if diff "$WORK/states-base.json" "$WORK/states-branch.json" > "$WORK/states.diff"; then
            pass "every state but the named ones is identical to the merge-base's"
        else
            fail "a state outside the named ones changed: $(sed -n 1,40p "$WORK/states.diff")"
        fi
        for t in $(jq -r '.states | to_entries[] | select(.value.terminal == true) | .key' "$BASE_JSON"); do
            eq "the result map of $t is unchanged" "$(jq -cS --arg t "$t" '.states[$t].result' "$BASE_JSON")" "$(jq -cS --arg t "$t" '.states[$t].result' "$CMP_JSON")"
        done
    fi
fi

# --- one script -----------------------------------------------------------------

gate_script() { # gate_script <template> -- attempt_recorded's script path
    local j
    j=$("$REAL_KOTO" template compile "$1" 2>> "$WORK/compile.err" | tail -1)
    [ -n "$j" ] && [ -f "$j" ] || return 1
    jq -r '.states.decide_first.gates.attempt_recorded.command' "$j" \
        | grep -o '{{PLUGIN_ROOT}}/[A-Za-z0-9_./-]*\.sh' | sort -u
}
G_SCOPE=$(gate_script "$SKILL_DIR/koto-templates/scope.md")
G_EXEC=$(gate_script "$SRC_ROOT/skills/execute/koto-templates/execute.md")
G_WORK=$(gate_script "$SRC_ROOT/skills/work-on/koto-templates/work-on.md")
eq "scope.md's attempt_recorded runs /work-on's decide-first-gate.sh" \
    "{{PLUGIN_ROOT}}/skills/work-on/scripts/decide-first-gate.sh" "$G_SCOPE"
eq "execute.md's attempt_recorded runs the same script" "$G_SCOPE" "$G_EXEC"
eq "work-on.md's attempt_recorded runs the same script" "$G_SCOPE" "$G_WORK"

# --- the walk: setup ------------------------------------------------------------

clean() { case "$1" in *[!a-zA-Z0-9._/:@\ -]*) return 1 ;; esac; return 0; }

WALK_WHY=""
SHIRABE=""
if [ -n "${SHIRABE_BIN:-}" ] && [ -x "$SHIRABE_BIN" ]; then
    SHIRABE=$SHIRABE_BIN
elif [ -x "$SRC_ROOT/target/release/shirabe" ]; then
    SHIRABE="$SRC_ROOT/target/release/shirabe"
else
    SHIRABE=$(command -v shirabe || true)
fi
case "$SHIRABE" in /*) ;; *) SHIRABE="" ;; esac
if [ -z "$SHIRABE" ] || ! "$SHIRABE" question precedent --help > /dev/null 2>&1; then
    WALK_WHY="no shirabe with \`question precedent\` (SHIRABE_BIN, target/release/shirabe or PATH); build the branch's with cargo build --release -p shirabe"
fi
PLUGIN=""
if clean "$SRC_ROOT"; then
    PLUGIN="$SRC_ROOT"
elif clean "$WORK"; then
    ln -s "$SRC_ROOT" "$WORK/plugin" && PLUGIN="$WORK/plugin"
fi
[ -n "$PLUGIN" ] || WALK_WHY="${WALK_WHY:+$WALK_WHY; }neither the checkout nor TMPDIR is a path koto admits in a --var"
command -v git > /dev/null || WALK_WHY="${WALK_WHY:+$WALK_WHY; }git is not on PATH"

# A scratch git identity, so the fixtures commit with no caller config.
W="$WORK/walk"
mkdir -p "$W/bin" || exit 1
export GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$W"
git config --global user.email t@example.invalid
git config --global user.name t
git config --global init.defaultBranch main

# repo <tag> -- a work tree on a named branch (branch_check needs one).
repo() {
    local r="$W/r-$1"
    mkdir -p "$r/docs" && git -C "$r" init -q && git -C "$r" commit -q --allow-empty -m fixture \
        && git -C "$r" checkout -q -b scope-fixture
}

# --- earlier --------------------------------------------------------------------

if [ -n "$BASE_WHY" ]; then
    skip_or_fail "earlier"
elif [ -z "$PLUGIN" ]; then
    echo "SKIP: earlier: neither the checkout nor TMPDIR is a path koto admits in a --var"
else
    repo old
    OLD_STATE=$(cd "$W/r-old" && {
        "$REAL_KOTO" init scope-old --template "$WORK/base/scope.md" --var TOPIC=old --var PLUGIN_ROOT="$PLUGIN" \
            --var PLUGIN_ROOT_PLACEMENT=outside --var EXEC_MODE=auto > /dev/null 2> "$WORK/old.err" || exit 0
        "$REAL_KOTO" next scope-old --no-cleanup > /dev/null 2>> "$WORK/old.err"
        for ev in '{"setup_result":"ready"}' '{"discovery_result":"proposed"}' '{"author_decision":"proceed"}' \
                '{"outcome":"skipped"}' '{"outcome":"skipped"}' '{"outcome":"bail","detail":"an upstream change alters the intent"}'; do
            "$REAL_KOTO" next scope-old --no-cleanup --with-data "$ev" > /dev/null 2>> "$WORK/old.err"
        done
        "$REAL_KOTO" status scope-old 2>> "$WORK/old.err" | jq -r '.current_state // ""'
    })
    eq "a session on the merge-base's scope.md, ticked with the branch's files, reaches bail on a hop's bail" \
        "bail" "$OLD_STATE"
    [ "$OLD_STATE" = bail ] || echo "  koto: $(tail -3 "$WORK/old.err")"
fi

# --- the walk -------------------------------------------------------------------

if [ -n "$WALK_WHY" ]; then
    if [ "${GITHUB_ACTIONS:-}" = true ]; then
        fail "the walk can't run under CI: $WALK_WHY"
    else
        echo "SKIP: the walk: $WALK_WHY"
    fi
else
    ln -s "$SHIRABE" "$W/bin/shirabe"
    PATH="$W/bin:$PATH"
    export PATH

    # The dispatcher every walk session is linked to before it raises.
    cat > "$W/manager.md" <<'EOF'
---
name: manager
version: "1.0"
initial_state: wait
states:
  wait:
    accepts:
      done:
        type: enum
        values: [yes]
        required: true
    transitions:
      - target: end
        when:
          done: yes
  end:
    terminal: true
---

## wait

Wait.

## end

Done.
EOF
    (cd "$W" && "$REAL_KOTO" init manager --template "$W/manager.md" > "$W/init.out" 2> "$W/init.err") \
        || fail "koto init manager: $(cat "$W/init.out" "$W/init.err")"

    jq -n '{
        context: "The PRD names one export format, and an upstream change now names two.",
        problem: "The design can carry one format or both, and the two differ in what ships first.",
        question: "Which export formats does the first release carry?",
        options: [
            {label: "CSV only", reason: "What the PRD named; the second format waits."},
            {label: "CSV and JSON", reason: "What the upstream change names; the design grows."}
        ],
        ground: "The choice changes the feature the PRD describes.",
        waiting: [],
        label: "export formats"
    }' > "$W/q.json"

    STATE=""
    RESP=""
    # open_scope <tag> -- scope-open.sh as the skill runs it, from the tag's
    # work tree; OPEN_OUT, OPEN_RC.
    open_scope() {
        local d
        d=$(bash "$SRC_ROOT/scripts/koto-open.sh" --alloc-dir) || { fail "$1: koto-open.sh --alloc-dir"; return 1; }
        printf '["%s","--auto"]' "$1" > "$d/args.json"
        OPEN_OUT=$(cd "$W/r-$1" && bash "$SCRIPT_DIR/scope-open.sh" --plugin-root "$PLUGIN" "$d/args.json" 2> "$W/open.err")
        OPEN_RC=$?
    }
    tick() { # tick <tag> [json] -- RESP, STATE
        if [ -n "${2:-}" ]; then
            RESP=$(cd "$W/r-$1" && "$REAL_KOTO" next "scope-$1" --no-cleanup --with-data "$2" 2> "$W/tick.err")
        else
            RESP=$(cd "$W/r-$1" && "$REAL_KOTO" next "scope-$1" --no-cleanup 2> "$W/tick.err")
        fi
        STATE=$(cd "$W/r-$1" && "$REAL_KOTO" status "scope-$1" 2>> "$W/tick.err" | jq -r '.current_state // ""')
    }
    at() { # at <label> <want>
        if [ "$STATE" = "$2" ]; then pass "$1: at $2"; else
            fail "$1: at [$STATE], want $2: $(printf '%s' "$RESP" | jq -c '{error, blocking_conditions}' 2> /dev/null | cut -c1-500) $(tail -2 "$W/tick.err")"
        fi
    }
    ctx() { (cd "$W/r-$1" && "$REAL_KOTO" context get "scope-$1" "$2" 2> "$W/ctx.err") || fail "$1: koto context get $2: $(cat "$W/ctx.err")"; }
    # reach <tag> <hop_design|full_run_blocked> -- open, link the dispatcher,
    # walk to the origin.
    reach() {
        repo "$1" || { fail "$1: the fixture repository"; return 1; }
        open_scope "$1"
        [ "$OPEN_RC" -eq 0 ] || { fail "$1: scope-open.sh exited $OPEN_RC: $OPEN_OUT $(cat "$W/open.err")"; return 1; }
        (cd "$W/r-$1" && "$REAL_KOTO" session link "scope-$1" --dispatched-by manager > /dev/null 2> "$W/link.err") \
            || { fail "$1: koto session link: $(cat "$W/link.err")"; return 1; }
        tick "$1"
        tick "$1" '{"setup_result":"ready"}'
        tick "$1" '{"discovery_result":"proposed"}'
        tick "$1" '{"author_decision":"proceed"}'
        tick "$1" '{"outcome":"skipped"}'
        tick "$1" '{"outcome":"skipped"}'
        if [ "$2" = full_run_blocked ]; then
            tick "$1" '{"outcome":"skipped"}'
            tick "$1" '{"outcome":"skipped"}'
            tick "$1" '{"exit":"full-run"}'
            tick "$1" '{"exit_artifacts":"present","plan_execution_mode":"single-pr"}'
        fi
        at "$1: reach" "$2"
        [ "$STATE" = "$2" ]
    }
    # wait_on <tag> <bail json> -- bail, attempt, raise, `raised`; Q, ARRIVAL.
    wait_on() {
        local t=$1 a head0
        head0=$(git -C "$W/r-$t" rev-parse HEAD)
        tick "$t" "$2"
        at "$t: the bail" decide_first
        ARRIVAL=$(ctx "$t" decide_arrival)
        a=$(cd "$W/r-$t" && shirabe question attempt --in "scope-$t" --what "export formats" --result undecided --state "$ARRIVAL" 2> "$W/att.err" | jq -r '.id // empty')
        [ -n "$a" ] || fail "$t: shirabe question attempt: $(cat "$W/att.err")"
        Q=$(cd "$W/r-$t" && shirabe question raise --in "scope-$t" --content "$W/q.json" --attempt "$a" --state "$ARRIVAL" 2> "$W/raise.err" | jq -r '.identity // empty')
        [ -n "$Q" ] || fail "$t: shirabe question raise: $(cat "$W/raise.err")"
        tick "$t" '{"decide_outcome":"raised"}'
        at "$t: raised" done_waiting
        local st
        st=$(cd "$W/r-$t" && "$REAL_KOTO" status "scope-$t" 2> "$W/status.err") || fail "$t: koto status: $(cat "$W/status.err")"
        eq "$t: the result's outcome is waiting" waiting "$(printf '%s' "$st" | jq -r '.result.payload.outcome // ""')"
        eq "$t: the result's question is the one raised" "$Q" "$(printf '%s' "$st" | jq -r '.result.payload.question // ""')"
        eq "$t: the work tree is as it was" "" "$(git -C "$W/r-$t" status --porcelain)"
        eq "$t: HEAD is as it was" "$head0" "$(git -C "$W/r-$t" rev-parse HEAD)"
        (cd "$W/r-$t" && "$REAL_KOTO" context exists "scope-$t" forced_artifact > /dev/null 2> "$W/exists.err")
        case $? in
            0) fail "$t: forced_artifact is recorded" ;;
            1) pass "$t: no forced_artifact is recorded" ;;
            *) fail "$t: koto context exists forced_artifact: $(cat "$W/exists.err")" ;;
        esac
        if grep -rl 'scope-status-block: abandonment' "$W/r-$t/docs" > /dev/null 2>&1; then
            fail "$t: a document carries the abandonment marker"
        else
            pass "$t: no document carries the abandonment marker"
        fi
    }
    answer() { # answer <tag> -- manager answers Q; ANS
        local id
        id=$(cd "$W" && "$REAL_KOTO" decisions answer --in=manager --text="CSV only" --by=session -- "scope-$1" "${Q##*/}" 2> "$W/ans.err" \
            | jq -r '.decision.id // .id // empty')
        [ -n "$id" ] || fail "$1: manager could not answer $Q: $(cat "$W/ans.err")"
        ANS="manager:$id"
    }
    # continue_run <tag> -- the open after the answer, then the held tick and
    # the citing attempt.
    continue_run() {
        local t=$1
        open_scope "$t"
        eq "$t: the open continues the run" continued=waiting "${OPEN_OUT%%$'\n'*}"
        case "$OPEN_OUT" in
            *replaced*|*moved_to=*) fail "$t: the open replaced the session: $OPEN_OUT" ;;
            *) pass "$t: the open replaced nothing" ;;
        esac
        tick "$t"
        at "$t: continued" decide_first
        if printf '%s' "$RESP" | jq -e '.questions | type == "array" and length > 0' > /dev/null 2>&1; then
            pass "$t: the first tick carries questions"
        else
            fail "$t: the first tick carries no questions: $(printf '%s' "$RESP" | jq -c 'del(.directive, .details)' | cut -c1-400)"
        fi
        ARRIVAL=$(ctx "$t" decide_arrival)
        tick "$t" '{"decide_outcome":"decided","decided_next":"resume"}'
        at "$t: decided with no citing attempt is held" decide_first
        (cd "$W/r-$t" && shirabe question attempt --in "scope-$t" --what "export formats" --result decided --chosen "CSV only" \
            --basis "$ANS" --state "$ARRIVAL") > "$W/att.out" 2> "$W/att.err" \
            || fail "$t: the citing attempt: $(cat "$W/att.out" "$W/att.err")"
    }

    echo "--- from hop_design: wait, then resume"
    if reach dsr hop_design; then
        DESIGN_DIRECTIVE=$(printf '%s' "$RESP" | jq -r '.directive // ""')
        wait_on dsr '{"outcome":"bail","detail":"an upstream change alters the PRD intent"}'
        open_scope dsr
        eq "dsr: an open while the question is open exits 3" 3 "$OPEN_RC"
        eq "dsr: and prints waiting= and session=" "waiting=$Q
session=scope-dsr" "$OPEN_OUT"
        STATE=$(cd "$W/r-dsr" && "$REAL_KOTO" status scope-dsr 2> "$W/status.err" | jq -r '.current_state // ""')
        [ -n "$STATE" ] || fail "dsr: koto status: $(cat "$W/status.err")"
        at "dsr: still waiting" done_waiting
        answer dsr
        continue_run dsr
        tick dsr '{"decide_outcome":"decided","decided_next":"resume"}'
        at "dsr: resume" hop_design
        eq "dsr: hop_design's own directive is delivered again" "$DESIGN_DIRECTIVE" "$(printf '%s' "$RESP" | jq -r '.directive // ""')"
    fi

    echo "--- from hop_design: wait, then stop"
    if reach dss hop_design; then
        wait_on dss '{"outcome":"bail","detail":"an upstream change alters the PRD intent"}'
        answer dss
        continue_run dss
        tick dss '{"decide_outcome":"decided","decided_next":"stop"}'
        at "dss: stop" bail
    fi

    echo "--- from full_run_blocked: wait, then resume"
    if reach fbr full_run_blocked; then
        wait_on fbr '{"next_move":"abandon","detail":"the chain cannot complete without the owner"}'
        answer fbr
        continue_run fbr
        tick fbr '{"decide_outcome":"decided","decided_next":"resume"}'
        at "fbr: resume" full_run_blocked
    fi

    echo "--- from full_run_blocked: wait, then stop"
    if reach fbs full_run_blocked; then
        wait_on fbs '{"next_move":"abandon","detail":"the chain cannot complete without the owner"}'
        answer fbs
        continue_run fbs
        tick fbs '{"decide_outcome":"decided","decided_next":"stop"}'
        at "fbs: stop" exit_abandonment
    fi
fi

echo
echo "passed: $PASS_COUNT   failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
