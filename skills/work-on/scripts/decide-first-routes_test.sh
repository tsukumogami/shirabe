#!/usr/bin/env bash
# decide-first-routes_test.sh -- a /work-on run about to stop at a covered exit
# records an attempt first, and a run that raised a question ends waiting on
# it; routed through the shipped work-on.md by a real koto and the branch's
# shirabe.
#
# decide-first-gate_test.sh runs scripts/decide-first-gate.sh on its own. This
# suite drives the template: every record is made with `shirabe question
# attempt` and `raise`, an answer to a worker comes from `manager`, the session
# that dispatched it (`koto decisions answer --by session`), and an owner's
# answer from a recorded harness session built from
# scripts/fixtures/question-commands/accepted.jsonl, never a live prompt. gh is a
# stand-in serving the fixture's issues.
#
# Cases:
#   the table       fixtures/decide-first/exits.json, the ten covered exits,
#                   is exactly the set of edges into decide_first, each
#                   assigning decide_origin; decide_first
#                   resumes to each of the seven covered states on its
#                   decide_from code, stops to done_blocked (10 to 12) or
#                   validation_exit (13 to 15), has no stop from
#                   deferral_approval, goes to waiting_record only on raised
#                   with attempt_recorded 3, and resumes only on decide_laps
#                   0; waiting_record records decide_question and ends at
#                   done_waiting only when its gate reads it open, and goes
#                   back to decide_first otherwise; every edge out of
#                   decide_first carries attempt_recorded; its gates,
#                   question_recorded, answer_cited and decide_resume cannot
#                   be overridden, and each command gate has a timeout;
#                   finalization's deferral_requested clears decide_arrival
#                   and decide_question; done_waiting is a failure terminal
#                   whose result is the question; entry reads decide_question
#                   with a context-exists gate, runs its mode edges only
#                   without it and goes to resume_waiting with it, which
#                   resumes on decide_resume 10 to 16
#   as before       fixtures/decide-first/undo.jq takes exactly the named
#                   changes out of the compiled template, and what is left
#                   equals the template at the merge-base with the pull
#                   request's base (DECIDE_FIRST_BASE, else GITHUB_BASE_REF,
#                   else origin/main). Once that base holds decide_first, the
#                   merge-base has nothing to compare, and the comparison is
#                   pinned to history instead: the commit that added
#                   decide_first, undone with that commit's own undo.jq and
#                   exits.json, equals its parent. Skipped, saying so, only
#                   when neither is in the clone
#   the ten exits   each covered exit, driven from its state, arrives at
#                   decide_first as <origin>:1, with a directive saying where
#                   the arrival is read, the procedure and each command, and the exit's
#                   failure_reason where it had one; with no attempt the
#                   submission is held, naming what is missing
#   resume and stop each origin: a decided attempt and decided_next: resume
#                   goes back to the origin; the next arrival is <origin>:2;
#                   a decided attempt for it and stop takes the old exit, with
#                   the old failure_reason; an attempt for :1 does not let :2
#                   leave
#   deferral        approved and rejected are held by answer_cited until an
#                   answer is cited; needs_answer goes to decide_first
#   stale approval  an answer cited for one deferral approves nothing once the
#                   run comes back to finalization and defers again
#   open question   a deciding attempt beside the arrival's open question is
#                   held; withdrawing the question lets it go on
#   lap cap         the fourth arrival from one state cannot resume; it stops
#   waiting         raised with no question is held; an undecided attempt and
#                   its open question pass waiting_record, which records the
#                   question, and end at done_waiting, a retained failure
#                   whose result names the question, which `koto decisions
#                   open` lists; `koto session cleanup` refuses it while the
#                   question is open
#   continuing      work-on-open.sh --continue-waiting: exit 3 while the
#                   question is open; once answered, a successor that waits
#                   at resume_waiting until an attempt cites the answer, then goes
#                   back to the origin (analysis, and deferral_approval, whose
#                   rejected then passes answer_cited); the next arrival goes
#                   on counting; refused=not_waiting on a run that is not
#                   waiting, and refused=dispatcher_differs when the
#                   continuing run names another dispatcher
#   withdrawn       a withdrawn question: --continue-waiting refuses it
#                   (refused=withdrawn), and cleanup then succeeds
#   attended        an owner question presented from a recorded prompt:
#                   raised is held once it is answered, decided goes on once
#                   an attempt cites the answer
#   precedent       a later arrival in that run reads the answer with
#                   `shirabe question precedent --label` and records a
#                   deciding attempt citing it, with no question raised
#   no covered exit a change run to finalization makes no `shirabe question`
#                   call and never enters decide_first; the same submissions
#                   to the merge-base template and to the branch's land in
#                   the same state at every tick
#   an old session  a session started from the earlier template still stops
#                   at done_blocked (when the base is readable)
#   words           the new directives never say escalate
#
# Usage: bash skills/work-on/scripts/decide-first-routes_test.sh
#   shirabe from SHIRABE_BIN, else the tree's target/release/shirabe, else
#   PATH; it must have `question precedent`. koto 0.42.0 or later, jq, git.
#
# Exit codes:
#   0 -- all cases pass
#   0 -- also when koto or jq is absent, every case skipped
#   1 -- one or more cases failed, or shirabe has no `question precedent`
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
unset KOTO_RUN_MODE CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID
unset KOTO_DECIDER KOTO_DECIDER_API_KEY KOTO_DECIDER_ENDPOINT

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SRC_ROOT=$(cd "$SKILL_DIR/../.." && pwd)
FIX="$SCRIPT_DIR/fixtures/decide-first"
PROMPT_FIXTURE="$SRC_ROOT/scripts/fixtures/question-commands/accepted.jsonl"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
finish() {
    echo
    echo "decide-first-routes_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
}

# The engine cases are all of it: without koto or jq nothing runs, as on the
# macOS floor runner, which has no koto.
for tool in koto jq git; do
    command -v "$tool" > /dev/null || { echo "SKIP: $tool is not on PATH -- no case ran"; exit 0; }
done
SHIRABE=""
if [ -n "${SHIRABE_BIN:-}" ] && [ -x "$SHIRABE_BIN" ]; then
    SHIRABE=$SHIRABE_BIN
elif [ -x "$SRC_ROOT/target/release/shirabe" ]; then
    SHIRABE="$SRC_ROOT/target/release/shirabe"
else
    SHIRABE=$(command -v shirabe)
fi
case "$SHIRABE" in /*) ;; *) SHIRABE="" ;; esac
if [ -z "$SHIRABE" ] || ! "$SHIRABE" question precedent --help > /dev/null; then
    fail "no shirabe with \`question precedent\` (SHIRABE_BIN, target/release/shirabe or PATH); build the branch's (cargo build --release -p shirabe)"
    finish
fi

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/decide-first-routes.XXXXXX") || { fail "mktemp failed"; finish; }
ACCOUNT_HOME=$(eval echo "~$(id -un)")
RECORDS=""
cleanup() {
    [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"
    [ -n "$RECORDS" ] && rm -rf "$RECORDS"
    return 0
}
ktg_on_exit cleanup

# The base template is read from this checkout before HOME moves. Its copy is
# named work-on.md, as the branch's is: fix-kind.sh attaches to the session
# from work-on.md, and koto refuses an attach from a template of another name.
BASE_REF="${DECIDE_FIRST_BASE:-}"
[ -n "$BASE_REF" ] || { [ -n "${GITHUB_BASE_REF:-}" ] && BASE_REF="origin/$GITHUB_BASE_REF"; }
[ -n "$BASE_REF" ] || BASE_REF=origin/main
BASE_TEMPLATE=""
BASE_WHY=""
mkdir -p "$WORKDIR/base"
if BASE_SHA=$(git -C "$SRC_ROOT" merge-base HEAD "$BASE_REF" 2>"$WORKDIR/base.err"); then
    if git -C "$SRC_ROOT" show "$BASE_SHA:skills/work-on/koto-templates/work-on.md" > "$WORKDIR/base/work-on.md" 2>"$WORKDIR/base.err"; then
        if grep -q '^  decide_first:' "$WORKDIR/base/work-on.md"; then
            BASE_WHY="the base $BASE_REF already holds decide_first; the comparison is the pull request's that introduced it"
        else
            BASE_TEMPLATE="$WORKDIR/base/work-on.md"
        fi
    else
        BASE_WHY="work-on.md is not readable at $BASE_SHA: $(cat "$WORKDIR/base.err")"
    fi
else
    BASE_WHY="no merge-base with $BASE_REF in this clone: $(cat "$WORKDIR/base.err")"
fi

# Once the base holds decide_first, the comparison is pinned to the commit
# that added it: that commit's template, undo.jq and exits.json, against its
# parent's template.
PIN_SHA=""
PIN_WHY=""
PIN="$WORKDIR/pin"
if [ -z "$BASE_TEMPLATE" ]; then
    mkdir -p "$PIN"
    if git -C "$SRC_ROOT" log --format=%H -S'  decide_first:' -- skills/work-on/koto-templates/work-on.md > "$PIN/log" 2>"$PIN/err"; then
        PIN_SHA=$(sed -n '$p' "$PIN/log")
        if [ -z "$PIN_SHA" ]; then
            PIN_WHY="no commit in this clone adds decide_first to work-on.md"
        elif git -C "$SRC_ROOT" show "$PIN_SHA^:skills/work-on/koto-templates/work-on.md" > "$PIN/pre.md" 2>"$PIN/err" \
                && git -C "$SRC_ROOT" show "$PIN_SHA:skills/work-on/koto-templates/work-on.md" > "$PIN/post.md" 2>"$PIN/err" \
                && git -C "$SRC_ROOT" show "$PIN_SHA:skills/work-on/scripts/fixtures/decide-first/undo.jq" > "$PIN/undo.jq" 2>"$PIN/err" \
                && git -C "$SRC_ROOT" show "$PIN_SHA:skills/work-on/scripts/fixtures/decide-first/exits.json" > "$PIN/exits.json" 2>"$PIN/err"; then
            :
        else
            PIN_WHY="the commit that added decide_first, $PIN_SHA, or its parent is not readable: $(cat "$PIN/err")"
        fi
    else
        PIN_WHY="git log failed: $(cat "$PIN/err")"
    fi
fi

export HOME="$WORKDIR/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t

# koto validates a variable value against ^[a-zA-Z0-9._/:@+ \-]*$; a checkout
# under a directory outside it is reached through a symlink.
PLUGIN_ROOT=$SRC_ROOT
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@+\ -]*)
        ln -s "$PLUGIN_ROOT" "$WORKDIR/plugin"
        PLUGIN_ROOT="$WORKDIR/plugin"
        ;;
esac
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
TEMPLATE="$PLUGIN_ROOT/skills/work-on/koto-templates/work-on.md"
OPEN="$PLUGIN_ROOT/skills/work-on/scripts/work-on-open.sh"
KOTO_OPEN="$PLUGIN_ROOT/scripts/koto-open.sh"

# gh: `issue view <n> ...` prints <issues>/<n>.json. shirabe: the branch's
# binary, every call logged, so a case can say which `shirabe question` calls
# a run made. Both are found on PATH, the way koto's gate commands find them;
# the paths are written in, since koto passes a command only an allowlisted
# environment.
mkdir -p "$WORKDIR/bin" "$WORKDIR/issues"
{
    echo '#!/usr/bin/env bash'
    echo '[ "$1 $2" = "issue view" ] || { echo "gh stand-in: unsupported $*" >&2; exit 1; }'
    printf 'f="%s/$3.json"\n' "$WORKDIR/issues"
    echo '[ -f "$f" ] || { echo "gh stand-in: no issue $3" >&2; exit 1; }'
    echo 'cat "$f"'
} > "$WORKDIR/bin/gh"
{
    echo '#!/usr/bin/env bash'
    printf 'printf "%%s\\n" "$*" >> "%s/shirabe.log"\n' "$WORKDIR"
    printf 'exec "%s" "$@"\n' "$SHIRABE"
} > "$WORKDIR/bin/shirabe"
chmod +x "$WORKDIR/bin/gh" "$WORKDIR/bin/shirabe"
export PATH="$WORKDIR/bin:$PATH"
: > "$WORKDIR/shirabe.log"

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OLD=$(date -u -d '-60 days' +%Y-%m-%dT%H:%M:%SZ 2>"$WORKDIR/date.err" || date -u -v-60d +%Y-%m-%dT%H:%M:%SZ)
jq -n --arg c "$NOW" '{number: 2, title: "shout", createdAt: $c, body: "Add a --shout flag.", milestone: null, labels: [{name: "enhancement"}]}' > "$WORKDIR/issues/2.json"
jq -n --arg c "$OLD" '{number: 4, title: "old", createdAt: $c, body: "Add a --quiet flag.", milestone: null, labels: [{name: "enhancement"}]}' > "$WORKDIR/issues/4.json"

cat > "$WORKDIR/manager.md" <<'EOF'
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
koto init manager --template "$WORKDIR/manager.md" > /dev/null 2>"$WORKDIR/init.err" \
    || { fail "koto init manager: $(cat "$WORKDIR/init.err")"; finish; }

# ==============================================================================
echo "--- the table"

COMPILED=$(koto template compile "$TEMPLATE" 2>"$WORKDIR/compile.err" | tail -n 1)
[ -f "$COMPILED" ] && pass "work-on.md compiles" || { fail "work-on.md does not compile: $(cat "$WORKDIR/compile.err")"; finish; }
q() { jq -r "$1" "$COMPILED"; }

want=$(jq -r '[.[] | "\(.origin)|\(.field)=\(.value)|\(.origin)"] | sort | join(",")' "$FIX/exits.json")
have=$(q '[.states | to_entries[] | select(.key != "waiting_record") | .key as $s | .value.transitions[]? | select(.target == "decide_first")
    | "\($s)|\(.when | to_entries | map("\(.key)=\(.value)") | join("+"))|\(.context_assignments.decide_origin)"] | sort | join(",")')
[ "$have" = "$want" ] && pass "the edges into decide_first are exactly the ten covered exits, each assigning its origin" \
    || fail "edges into decide_first: [$have], want [$want]"

[ "$(q '[.states.decide_first.transitions[] | select(.when.decided_next == "resume") | "\(.when["gates.decide_from.exit_code"])>\(.target)"] | sort | join(",")')" \
    = "10>analysis,11>implementation,12>introspection,13>task_validation,14>post_research_validation,15>plan_validation,16>deferral_approval" ] \
    && pass "decide_first resumes to each covered state on its decide_from code" \
    || fail "resume edges: [$(q '[.states.decide_first.transitions[] | select(.when.decided_next == "resume")]')]"
[ "$(q '[.states.decide_first.transitions[] | select(.when.decided_next == "stop") | "\(.when["gates.decide_from.exit_code"])>\(.target)"] | sort | join(",")')" \
    = "10>done_blocked,11>done_blocked,12>done_blocked,13>validation_exit,14>validation_exit,15>validation_exit" ] \
    && pass "decide_first stops at the old exit for 10 to 15, and has no stop from deferral_approval" \
    || fail "stop edges: [$(q '[.states.decide_first.transitions[] | select(.when.decided_next == "stop")]')]"
[ "$(q '[.states.decide_first.transitions[] | select(.target == "waiting_record") | .when | to_entries | map("\(.key)=\(.value)") | join("+")] | join(",")')" \
    = "decide_outcome=raised+gates.attempt_recorded.exit_code=3" ] \
    && [ "$(q '[.states.decide_first.transitions[] | select(.target == "done_waiting")] | length')" = 0 ] \
    && pass "decide_first goes to waiting_record only on raised with attempt_recorded 3, and never straight to done_waiting" \
    || fail "raised edges: [$(q '[.states.decide_first.transitions[] | select(.when.decide_outcome == "raised")]')]"
[ "$(q '[.states.waiting_record.transitions[] | "\(.target)|\(.when | to_entries | map("\(.key)=\(.value)") | join("+"))"] | join(",")')" \
    = "done_waiting|gates.question_recorded.exit_code=0,decide_first|gates.question_recorded.exit_code=1" ] \
    && [ "$(q '.states.waiting_record.transitions[] | select(.target == "decide_first") | .context_assignments // {} | length')" = 0 ] \
    && case "$(q '.states.waiting_record.gates.question_recorded.command')" in *'decide-first-gate.sh" --recorded "{{SESSION_NAME}}"'*) true ;; *) false ;; esac \
    && pass "waiting_record ends at done_waiting on --recorded 0, and goes back to decide_first on 1 with no assignment" \
    || fail "waiting_record is [$(q '.states.waiting_record | del(.directive)')]"
case "$(q '.states.waiting_record.default_action.command')" in
    *'decide-first-gate.sh" --record-question "{{SESSION_NAME}}"'*) pass "waiting_record's action is decide-first-gate.sh --record-question" ;;
    *) fail "waiting_record's action is [$(q '.states.waiting_record.default_action')]" ;;
esac
[ "$(q '.states.decide_first.default_action | has("capture_stdout_as")')" = false ] \
    && pass "decide_first's action captures nothing; the script writes decide_arrival itself" \
    || fail "decide_first's action captures [$(q '.states.decide_first.default_action.capture_stdout_as')]"
[ "$(q '[.states.decide_first.transitions[] | select(.when.decided_next == "resume") | .when["gates.decide_laps.exit_code"] | tostring] | unique | join(",")')" = 0 ] \
    && [ "$(q '[.states.decide_first.transitions[] | select(.when.decided_next != "resume") | select(.when | has("gates.decide_laps.exit_code"))] | length')" = 0 ] \
    && pass "every resume edge needs decide_laps 0, and no other edge tests it" \
    || fail "decide_laps on decide_first's edges: [$(q '[.states.decide_first.transitions[] | {target, laps: .when["gates.decide_laps.exit_code"]}]')]"
[ "$(q '[.states.decide_first.gates[], .states.waiting_record.gates[], .states.deferral_approval.gates.answer_cited, .states.resume_waiting.gates.decide_resume] | map(.timeout | tostring) | unique | join(",")')" = 60 ] \
    && pass "each command gate this step adds has a 60-second timeout" \
    || fail "timeouts: [$(q '[.states.decide_first.gates[], .states.deferral_approval.gates.answer_cited, .states.resume_waiting.gates.decide_resume] | map(.timeout)')]"
[ "$(q '[.states.finalization.transitions[] | select(.when.finalization_status == "deferral_requested") | "\(.target)|\(.context_assignments.decide_arrival)|\(.context_assignments.decide_question)"] | join(",")')" \
    = "deferral_approval|none|none" ] \
    && pass "a new deferral clears decide_arrival and decide_question, so an earlier answer approves nothing" \
    || fail "finalization's deferral edge: [$(q '[.states.finalization.transitions[] | select(.when.finalization_status == "deferral_requested")]')]"
[ "$(q '[.states.decide_first.transitions[] | select(.when | has("gates.attempt_recorded.exit_code") | not)] | length')" = 0 ] \
    && [ "$(q '[.states.decide_first.transitions[] | select(.when.decide_outcome == "decided" and .when["gates.attempt_recorded.exit_code"] != 0)] | length')" = 0 ] \
    && pass "every edge out of decide_first carries attempt_recorded, 0 for decided" \
    || fail "an edge out of decide_first leaves without attempt_recorded"
[ "$(q '[.states.decide_first.gates.attempt_recorded.overridable, .states.decide_first.gates.decide_from.overridable, .states.decide_first.gates.decide_laps.overridable, .states.waiting_record.gates.question_recorded.overridable, .states.deferral_approval.gates.answer_cited.overridable, .states.resume_waiting.gates.decide_resume.overridable] | map(tostring) | join(",")')" \
    = "false,false,false,false,false,false" ] && pass "attempt_recorded, decide_from, decide_laps, question_recorded, answer_cited and decide_resume cannot be overridden" \
    || fail "overridable: [$(q '[.states.decide_first.gates, .states.waiting_record.gates, .states.deferral_approval.gates.answer_cited, .states.resume_waiting.gates.decide_resume] | map(del(.command)?)')]"
case "$(q '.states.decide_first.default_action.command')" in
    *'decide-first-gate.sh" --arrive "{{SESSION_NAME}}"'*) pass "decide_first's action is decide-first-gate.sh --arrive" ;;
    *) fail "decide_first's action is [$(q '.states.decide_first.default_action')]" ;;
esac
[ "$(q '.states.done_waiting | "\(.terminal)|\(.failure)|\(.result.question)"')" = 'true|true|${context.decide_question}' ] \
    && pass "done_waiting is a failure terminal whose result is the question" || fail "done_waiting is [$(q '.states.done_waiting | del(.directive)')]"
[ "$(q '.states.done_waiting.result | has("pr")')" = false ] && pass "done_waiting carries no pr, so a parent reads it as a run that did not land" \
    || fail "done_waiting carries a pr"
[ "$(q '.states.entry.gates | to_entries | map("\(.key)|\(.value.type)|\(.value.key)|\(.value.overridable)") | join(",")')" = "continues_waiting|context-exists|decide_question|false" ] \
    && pass "entry's one gate reads decide_question with no command, so a fresh run starts as before" \
    || fail "entry's gates: [$(q '.states.entry.gates')]"
[ "$(q '[.states.entry.transitions[] | select(.when.mode != null) | .when["gates.continues_waiting.exists"]] | map(tostring) | unique | join(",")')" = false ] \
    && [ "$(q '.states.entry.skip_if["gates.continues_waiting.exists"] | tostring')" = false ] \
    && [ "$(q '[.states.entry.transitions[] | select(.when.mode == null) | "\(.target)|\(.when | to_entries | map("\(.key)=\(.value)") | join("+"))"] | join(",")')" = "resume_waiting|gates.continues_waiting.exists=true" ] \
    && pass "entry's mode edges and skip_if need no decide_question, and its one other edge goes to resume_waiting with it" \
    || fail "entry's edges: [$(q '.states.entry | {skip_if, transitions}')]"
[ "$(q '[.states.resume_waiting.transitions[] | "\(.when["gates.decide_resume.exit_code"])>\(.target)"] | sort | join(",")')" \
    = "10>analysis,11>implementation,12>introspection,13>task_validation,14>post_research_validation,15>plan_validation,16>deferral_approval" ] \
    && [ "$(q '.states.resume_waiting | has("accepts")')" = false ] \
    && pass "resume_waiting resumes a continued run on decide_resume 10 to 16, and accepts nothing" \
    || fail "resume_waiting: [$(q '.states.resume_waiting | del(.directive)')]"
case "$(q '.states.resume_waiting.gates.decide_resume.command')" in
    *'decide-first-gate.sh" || exit 2;'*'--resume "{{SESSION_NAME}}"'*) pass "resume_waiting's gate is decide-first-gate.sh --resume, and a missing script holds the run" ;;
    *) fail "resume_waiting's gate is [$(q '.states.resume_waiting.gates.decide_resume.command')]" ;;
esac

# ==============================================================================
echo "--- as before"

if [ -n "$BASE_TEMPLATE" ]; then
    BASE_COMPILED=$(koto template compile "$BASE_TEMPLATE" 2>"$WORKDIR/base-compile.err" | tail -n 1)
    if [ -f "$BASE_COMPILED" ]; then
        jq -S '.states.deferral_approval |= del(.directive)' "$BASE_COMPILED" > "$WORKDIR/base.json"
        if jq -S --argjson exits "$(cat "$FIX/exits.json")" --from-file "$FIX/undo.jq" "$COMPILED" > "$WORKDIR/undone.json" 2>"$WORKDIR/undo.err"; then
            if diff "$WORKDIR/base.json" "$WORKDIR/undone.json" > "$WORKDIR/undo.diff"; then
                pass "with the named changes taken out, work-on.md equals the template at $BASE_REF's merge-base"
            else
                fail "work-on.md differs from $BASE_REF's merge-base beyond the named changes: $(sed -n 1,40p "$WORKDIR/undo.diff")"
            fi
        else
            fail "undo.jq failed: $(cat "$WORKDIR/undo.err")"
        fi
    else
        fail "the base template does not compile: $(cat "$WORKDIR/base-compile.err")"
    fi
elif [ -n "$PIN_SHA" ] && [ -z "$PIN_WHY" ]; then
    PRE_COMPILED=$(koto template compile "$PIN/pre.md" 2>"$PIN/pre.err" | tail -n 1)
    POST_COMPILED=$(koto template compile "$PIN/post.md" 2>"$PIN/post.err" | tail -n 1)
    if [ -f "$PRE_COMPILED" ] && [ -f "$POST_COMPILED" ]; then
        jq -S '.states.deferral_approval |= del(.directive)' "$PRE_COMPILED" > "$PIN/base.json"
        if jq -S --argjson exits "$(cat "$PIN/exits.json")" --from-file "$PIN/undo.jq" "$POST_COMPILED" > "$PIN/undone.json" 2>"$PIN/undo.err"; then
            if diff "$PIN/base.json" "$PIN/undone.json" > "$PIN/undo.diff"; then
                pass "with the named changes taken out, work-on.md at $PIN_SHA, the commit that added decide_first, equals its parent ($BASE_WHY)"
            else
                fail "work-on.md at $PIN_SHA differs from its parent beyond the named changes: $(sed -n 1,40p "$PIN/undo.diff")"
            fi
        else
            fail "undo.jq at $PIN_SHA failed: $(cat "$PIN/undo.err")"
        fi
    else
        fail "the templates at $PIN_SHA and its parent do not compile: $(cat "$PIN/pre.err" "$PIN/post.err")"
    fi
else
    echo "SKIP: as before: $BASE_WHY; $PIN_WHY"
fi

# Every edge into done_blocked and validation_exit, as <source>|<when>|<context
# assignments>; on the branch, the ones decide_first adds are left out, and at
# the base the ten covered pairs are, so the two lists must be equal.
terminal_edges() {
    jq -r --argjson exits "$(cat "$FIX/exits.json")" --arg drop "$2" '
        [$exits[] | "\(.origin)|\(.field)=\(.value)"] as $covered
        | .states | to_entries[] | .key as $s | .value.transitions[]?
        | select(.target == "done_blocked" or .target == "validation_exit")
        | ((.when // {}) | to_entries
            | map(select($s != "deferral_approval" or .key != "gates.answer_cited.exit_code"))
            | map("\(.key)=\(.value)") | join("+")) as $w
        | select(if $drop == "branch" then $s != "decide_first" else ([$covered[] | . == "\($s)|\($w)"] | any | not) end)
        | "\(.target) <- \($s)|\($w)|\(.context_assignments // {} | tojson)"' "$1" | sort
}
terminal_edges "$COMPILED" branch > "$WORKDIR/edges-branch.txt"
echo "edges into done_blocked and validation_exit, decide_first's left out:"
sed 's/^/  /' "$WORKDIR/edges-branch.txt"
if [ -n "$BASE_TEMPLATE" ] && [ -f "${BASE_COMPILED:-}" ]; then
    terminal_edges "$BASE_COMPILED" base > "$WORKDIR/edges-base.txt"
    echo "the same at $BASE_REF's merge-base, the ten covered pairs left out:"
    sed 's/^/  /' "$WORKDIR/edges-base.txt"
    if diff "$WORKDIR/edges-base.txt" "$WORKDIR/edges-branch.txt" > "$WORKDIR/edges.diff"; then
        pass "every other edge into the two terminals is as it was at the merge-base"
    else
        fail "the edges into the two terminals changed: $(cat "$WORKDIR/edges.diff")"
    fi
fi
grep -q 'decide_first' "$WORKDIR/edges-branch.txt" && fail "an edge from decide_first is listed" || :
for row in $(jq -r '.[] | "\(.origin)|\(.field)=\(.value)"' "$FIX/exits.json"); do
    if grep -qF " <- $row|" "$WORKDIR/edges-branch.txt"; then
        fail "$row still reaches a terminal without passing decide_first"
    fi
done
pass "none of the covered pairs reaches done_blocked or validation_exit directly"

# ==============================================================================
# The repository.
REPO="$WORKDIR/repo"
mkdir -p "$REPO/tests" "$REPO/.claude/shirabe-extensions"
cd "$REPO" || { fail "cd $REPO"; finish; }
git init -q -b main .
printf '#!/bin/sh\necho "Hello, $1!"\n' > greet.sh
printf '#!/bin/sh\nexit 0\n' > tests/run.sh
printf '# greet\n\n## Repo Visibility: Private\n' > CLAUDE.md
printf '%s\n' '{"schema":"shirabe-verification-map/v1","commands":{"tests":{"run":["sh","tests/run.sh"]}},"entries":[],"default":["tests"]}' \
    > .claude/shirabe-extensions/verification-map.json
chmod +x greet.sh tests/run.sh
git add -A
git commit -q -m init

RESP=""
STATE=""
# tick <session> [<evidence>]
tick() {
    if [ -n "${2:-}" ]; then
        RESP=$(koto next "$1" --with-data "$2" --no-cleanup 2>"$WORKDIR/tick.err")
    else
        RESP=$(koto next "$1" --no-cleanup 2>"$WORKDIR/tick.err")
    fi
    STATE=$(koto status "$1" 2>"$WORKDIR/status.err" | jq -r '.current_state // empty')
}
expect_state() { [ "$STATE" = "$2" ] && pass "$1: at $2" || fail "$1: at [$STATE], want $2: $(printf '%s' "$RESP" | jq -c '{error, blocking_conditions}' | cut -c1-600)"; }
gate_stdout() {
    printf '%s' "$RESP" | jq -r --arg g "$1" '.blocking_conditions[]? | select(.name == $g) | .failure.captured.stdout // ""'
}
ctx() { koto context get "$1" "$2" 2>"$WORKDIR/ctx.err"; }
toks() {
    local d
    d=$(bash "$KOTO_OPEN" --alloc-dir) || { fail "koto-open.sh --alloc-dir failed"; return 1; }
    printf '%s' "$1" > "$d/t.json"
    TOKS="$d/t.json"
}
# open_run <session> <issue|-> [work-on-open.sh args...]: a branch off main and
# a run opened as SKILL.md opens one, dispatched by manager.
open_run() {
    local s=$1 n=$2
    shift 2
    git checkout -q main
    git checkout -q -b "case-$s"
    toks '["x"]' || return 1
    if [ "$n" = - ]; then
        bash "$OPEN" --workflow "$s" --var ARTIFACT_PREFIX="$s" --dispatched-by manager "$@" "$TOKS" > "$WORKDIR/open.out" 2>"$WORKDIR/open.err"
    else
        bash "$OPEN" --workflow "$s" --var ISSUE_NUMBER="$n" --var ARTIFACT_PREFIX="issue_$n" --dispatched-by manager "$@" "$TOKS" > "$WORKDIR/open.out" 2>"$WORKDIR/open.err"
    fi || { fail "$s: work-on-open.sh failed: $(cat "$WORKDIR/open.out" "$WORKDIR/open.err")"; return 1; }
}
issue_walk() {
    tick "$1" "{\"mode\":\"issue_backed\",\"issue_number\":\"$2\"}"
    tick "$1" '{"status":"override"}'
    tick "$1" '{"status":"override"}'
    printf '# Issue %s\n\n## Acceptance Criteria\n\n- [ ] it works\n' "$2" | koto context add "$1" context.md > /dev/null
    printf 'plan\n' | koto context add "$1" plan.md > /dev/null
}
# reach <session> <origin>: a run opened and walked to the covered state.
reach() {
    local s=$1
    case "$2" in
        analysis)
            open_run "$s" 2 --var ISSUE_TYPE=task || return 1
            issue_walk "$s" 2 ;;
        implementation)
            open_run "$s" 2 --var ISSUE_TYPE=task || return 1
            issue_walk "$s" 2
            tick "$s" '{"plan_outcome":"plan_ready"}' ;;
        introspection)
            open_run "$s" 4 --var ISSUE_TYPE=task || return 1
            issue_walk "$s" 4 ;;
        task_validation)
            open_run "$s" - || return 1
            tick "$s" '{"mode":"free_form","task_description":"add a shout flag"}' ;;
        post_research_validation)
            open_run "$s" - || return 1
            tick "$s" '{"mode":"free_form","task_description":"add a shout flag"}'
            tick "$s" '{"verdict":"proceed","rationale":"the task is clear"}' ;;
        plan_validation)
            open_run "$s" - || return 1
            tick "$s" '{"mode":"plan_backed"}'
            printf '# Step\n' | koto context add "$s" context.md > /dev/null
            tick "$s" '{"status":"completed","issue_source":"plan_outline"}' ;;
        deferral_approval)
            open_run "$s" 2 --var ISSUE_TYPE=task --var VERIFICATION=hosted-ci \
                --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI" || return 1
            issue_walk "$s" 2
            tick "$s" '{"plan_outcome":"plan_ready"}'
            printf 'shout\n' > "SHOUT-$s.md"
            git add "SHOUT-$s.md"
            git commit -q -m "feat: shout"
            tick "$s" '{"implementation_status":"complete"}'
            tick "$s" '{"issue_type":"task"}'
            tick "$s" '{"finalization_status":"deferral_requested"}' ;;
    esac
    [ "$STATE" = "$2" ] || { fail "$s: walked to [$STATE], not $2: $(printf '%s' "$RESP" | jq -c . | cut -c1-400)"; return 1; }
}

# attempt <session> <args...> -> id in $A
attempt() {
    local s=$1
    shift
    shirabe question attempt --in "$s" --what "cache store" "$@" > "$WORKDIR/att.out" 2>"$WORKDIR/att.err"
    A=$(jq -r '.id // empty' "$WORKDIR/att.out")
    [ -n "$A" ] || fail "shirabe question attempt --in $s $*: $(cat "$WORKDIR/att.out" "$WORKDIR/att.err")"
}
content() {
    jq -n --arg label "$2" '{
        context: "The build cache is lost on every runner restart.",
        problem: "Two stores fit, and they differ in what an operator has to run.",
        question: "Which store should the build cache use?",
        options: [
            {label: "SQLite", reason: "One file beside the runner, no server to run."},
            {label: "Postgres", reason: "Shared across runners, but a server to keep up."}
        ],
        ground: "Picking a server changes what the team operates.",
        waiting: ["issue-2"],
        label: $label
    }' > "$1"
}
content "$WORKDIR/q.json" "build cache store"
# raise <session> <args...> -> identity in $Q
raise() {
    local s=$1
    shift
    shirabe question raise --in "$s" --content "$WORKDIR/q.json" "$@" > "$WORKDIR/raise.out" 2>"$WORKDIR/raise.err"
    Q=$(jq -r '.identity // empty' "$WORKDIR/raise.out")
    [ -n "$Q" ] || fail "shirabe question raise --in $s $*: $(cat "$WORKDIR/raise.out" "$WORKDIR/raise.err")"
}
# manager_answers <raiser> <identity> -> manager:<id> in $ANS
manager_answers() {
    local id
    id=$(koto decisions answer --in=manager --text=SQLite --by=session -- "$1" "${2##*/}" 2>"$WORKDIR/ans.err" | jq -r '.decision.id // .id // empty')
    [ -n "$id" ] || fail "manager could not answer $2: $(cat "$WORKDIR/ans.err")"
    ANS="manager:$id"
}

# ==============================================================================
echo "--- the ten exits, and resume and stop from each origin"

i=0
n=$(jq length "$FIX/exits.json")
while [ "$i" -lt "$n" ]; do
    row=$(jq -c ".[$i]" "$FIX/exits.json")
    i=$((i + 1))
    origin=$(printf '%s' "$row" | jq -r .origin)
    ev=$(printf '%s' "$row" | jq -c .evidence)
    reason=$(printf '%s' "$row" | jq -r '.reason // empty')
    old=$(printf '%s' "$row" | jq -r '.old // empty')
    label="$origin $(printf '%s' "$row" | jq -r '"\(.field)=\(.value)"')"
    S="x$i"
    reach "$S" "$origin" || continue
    tick "$S" "$ev"
    expect_state "$label" decide_first
    [ "$(ctx "$S" decide_arrival)" = "$origin:1" ] && pass "$label: the arrival is $origin:1" || fail "$label: decide_arrival is [$(ctx "$S" decide_arrival)]"
    dir=$(printf '%s' "$RESP" | jq -r '.directive // ""')
    miss=""
    for want in "koto context get $S decide_arrival" "references/question-procedure.md" "shirabe question precedent --in $S" \
            "shirabe question attempt --in $S --state <arrival>" "shirabe question raise --in $S" "open no prompt and submit \`raised\`"; do
        case "$dir" in *"$want"*) ;; *) miss="$miss [$want]" ;; esac
    done
    [ -z "$miss" ] && pass "$label: the directive says where the arrival is read, the procedure and each command" || fail "$label: the directive lacks$miss"
    if [ -n "$reason" ]; then
        [ "$(ctx "$S" failure_reason)" = "$reason" ] && pass "$label: the exit's failure_reason is kept" || fail "$label: failure_reason is [$(ctx "$S" failure_reason)]"
    fi
    tick "$S" '{"decide_outcome":"decided","decided_next":"resume"}'
    expect_state "$label: decided with no attempt is held" decide_first
    case "$(gate_stdout attempt_recorded)" in *"no attempt is recorded for $origin:1"*) pass "$label: attempt_recorded names what is missing" ;;
        *) fail "$label: attempt_recorded printed [$(gate_stdout attempt_recorded)]" ;; esac
    tick "$S" '{"decide_outcome":"raised"}'
    expect_state "$label: raised with no attempt is held" decide_first

    # Two exits share each origin but analysis, implementation and
    # post_research_validation; the second of each pair only arrives.
    case "$label" in
        "analysis plan_outcome=blocked_missing_context"|"implementation implementation_status=partial_tests_failing_escalate"|"post_research_validation verdict=exit") continue ;;
    esac
    attempt "$S" --result decided --chosen SQLite --state "$origin:1"
    tick "$S" '{"decide_outcome":"decided","decided_next":"resume"}'
    expect_state "$label: decided and resume goes back" "$origin"
    [ "$origin" = deferral_approval ] && continue
    tick "$S" "$ev"
    [ "$(ctx "$S" decide_arrival)" = "$origin:2" ] && pass "$label: the next arrival is $origin:2" || fail "$label: the second arrival is [$(ctx "$S" decide_arrival)]"
    tick "$S" '{"decide_outcome":"decided","decided_next":"stop"}'
    expect_state "$label: an attempt for :1 does not let :2 leave" decide_first
    attempt "$S" --result decided --chosen "stop here" --state "$origin:2"
    tick "$S" '{"decide_outcome":"decided","decided_next":"stop"}'
    expect_state "$label: decided and stop takes the old exit" "$old"
    if [ -n "$reason" ]; then
        [ "$(ctx "$S" failure_reason)" = "$reason" ] && pass "$label: done_blocked keeps the exit's failure_reason" || fail "$label: failure_reason at the stop is [$(ctx "$S" failure_reason)]"
    fi
done

# ==============================================================================
echo "--- deferral: answer_cited holds approved and rejected"

S=dfr
if reach "$S" deferral_approval; then
    tick "$S" '{"approval_decision":"approved","cleanup_done":"none_found","design_diagram":"not_applicable"}'
    expect_state "approved with no answer is held" deferral_approval
    case "$(gate_stdout answer_cited)" in *needs_answer*) pass "answer_cited says to submit needs_answer" ;; *) fail "answer_cited printed [$(gate_stdout answer_cited)]" ;; esac
    tick "$S" '{"approval_decision":"rejected"}'
    expect_state "rejected with no answer is held" deferral_approval
fi

# ==============================================================================
echo "--- waiting, and continuing from deferral_approval"

S=dfw
if reach "$S" deferral_approval; then
    tick "$S" '{"approval_decision":"needs_answer"}'
    expect_state "needs_answer" decide_first
    attempt "$S" --result undecided --state deferral_approval:1
    tick "$S" '{"decide_outcome":"raised"}'
    expect_state "raised with no question is held" decide_first
    raise "$S" --attempt "$A" --state deferral_approval:1
    QD=$Q
    tick "$S" '{"decide_outcome":"raised"}'
    expect_state "an undecided attempt and its open question" done_waiting
    koto decisions list "$S" --format v1 --kind escalate > "$WORKDIR/esc.out" 2>"$WORKDIR/esc.err"
    [ "$(jq -r --arg a "$A" '[.decisions[]?] | "\(length)|\(.[0].decision.subject.state)|\([.[0].decision.basis[]?.id] | index($a) != null)"' "$WORKDIR/esc.out")" \
        = "1|deferral_approval:1|true" ] && pass "one question on the record, for the arrival, resting on the undecided attempt" \
        || fail "the run's escalate entries: $(cat "$WORKDIR/esc.out" "$WORKDIR/esc.err")"
    [ "$(ctx "$S" decide_question)" = "$QD" ] && pass "waiting_record recorded the question in decide_question" \
        || fail "decide_question is [$(ctx "$S" decide_question)], want $QD"
    # koto keeps a failure terminal as failure_terminal before it asks about
    # open questions, so the tick's retention says the session is kept without
    # naming the question; the open-question reads below are what name it.
    koto decisions open --at manager > "$WORKDIR/open-q.out" 2>"$WORKDIR/open-q.err"
    grep -qF "${QD##*/}" "$WORKDIR/open-q.out" && pass "koto decisions open --at manager returns the question" \
        || fail "koto decisions open --at manager: $(cat "$WORKDIR/open-q.out" "$WORKDIR/open-q.err")"
    [ "$(ctx "$S" plan.md)" = plan ] && pass "the waiting session still holds plan.md" || fail "plan.md after done_waiting: [$(ctx "$S" plan.md)]"
    [ "$(printf '%s' "$RESP" | jq -r '"\(.result.payload.question // .result.question)|\(.retention.retained)"')" = "$QD|true" ] \
        && pass "the terminal response names the question and the session is retained" \
        || fail "the terminal response is [$(printf '%s' "$RESP" | jq -c '{result, retention}')]"
    [ "$(koto status "$S" 2>"$WORKDIR/status.err" | jq -r '.result.payload.question // empty')" = "$QD" ] \
        && pass "koto status reads the question from done_waiting's result" || fail "koto status: $(koto status "$S" | jq -c .result)"
    koto decisions open --at "$S" > "$WORKDIR/open-q.out" 2>"$WORKDIR/open-q.err"
    grep -q "${QD##*/}" "$WORKDIR/open-q.out" && pass "koto decisions open lists the question" \
        || fail "koto decisions open --at $S: $(cat "$WORKDIR/open-q.out" "$WORKDIR/open-q.err")"
    koto session cleanup "$S" > "$WORKDIR/cleanup.out" 2>"$WORKDIR/cleanup.err"
    RC=$?
    [ "$RC" -ne 0 ] && grep -q holds_question "$WORKDIR/cleanup.out" "$WORKDIR/cleanup.err" \
        && pass "cleanup refuses a session whose question is open" || fail "cleanup exited $RC: $(cat "$WORKDIR/cleanup.out" "$WORKDIR/cleanup.err")"

    toks '["x"]'
    bash "$OPEN" --workflow "$S" --var ISSUE_NUMBER=2 --var ARTIFACT_PREFIX=issue_2 --var ISSUE_TYPE=task --var VERIFICATION=hosted-ci \
        --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI" --dispatched-by manager --continue-waiting "$TOKS" > "$WORKDIR/cont.out" 2>"$WORKDIR/cont.err"
    RC=$?
    [ "$RC" = 3 ] && grep -qx "waiting=$QD" "$WORKDIR/cont.out" && pass "--continue-waiting exits 3 naming the open question" \
        || fail "--continue-waiting while open exited $RC: $(cat "$WORKDIR/cont.out" "$WORKDIR/cont.err")"

    manager_answers "$S" "$QD"
    toks '["x"]'
    bash "$OPEN" --workflow "$S" --var ISSUE_NUMBER=2 --var ARTIFACT_PREFIX=issue_2 --var ISSUE_TYPE=task --var VERIFICATION=hosted-ci \
        --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI" --dispatched-by scratch --continue-waiting "$TOKS" > "$WORKDIR/cont.out" 2>"$WORKDIR/cont.err"
    RC=$?
    [ "$RC" = 2 ] && grep -qx refused=dispatcher_differs "$WORKDIR/cont.out" && grep -qx dispatcher=manager "$WORKDIR/cont.out" \
        && ! koto status "$S-r2" > /dev/null 2>"$WORKDIR/status.err" \
        && pass "--continue-waiting under a different dispatcher is refused and opens no successor" \
        || fail "--continue-waiting --dispatched-by scratch exited $RC: $(cat "$WORKDIR/cont.out" "$WORKDIR/cont.err")"
    toks '["x"]'
    bash "$OPEN" --workflow "$S" --var ISSUE_NUMBER=2 --var ARTIFACT_PREFIX=issue_2 --var ISSUE_TYPE=task --var VERIFICATION=hosted-ci \
        --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI" --dispatched-by manager --continue-waiting "$TOKS" > "$WORKDIR/cont.out" 2>"$WORKDIR/cont.err"
    RC=$?
    SUCC=$(sed -n 's/^session=//p' "$WORKDIR/cont.out")
    [ "$RC" = 0 ] && grep -qx "opened=continued" "$WORKDIR/cont.out" && [ "$SUCC" = "$S-r2" ] \
        && pass "once answered, --continue-waiting opens $S-r2" || fail "--continue-waiting exited $RC: $(cat "$WORKDIR/cont.out" "$WORKDIR/cont.err")"
    tick "$SUCC"
    expect_state "the successor waits at resume_waiting until the answer is cited" resume_waiting
    case "$(gate_stdout decide_resume)" in *"is not cited yet"*) pass "decide_resume names the answer to cite" ;; *) fail "decide_resume printed [$(gate_stdout decide_resume)]" ;; esac
    attempt "$SUCC" --result decided --chosen "defer the criterion" --basis "$ANS"
    tick "$SUCC"
    expect_state "an attempt citing the answer resumes the run" deferral_approval
    tick "$SUCC" '{"approval_decision":"rejected"}'
    expect_state "rejected passes answer_cited in the continuing session" done_blocked
    koto session cleanup "$S" > "$WORKDIR/cleanup.out" 2>"$WORKDIR/cleanup.err" \
        && pass "the answered predecessor cleans up" || fail "cleanup of $S: $(cat "$WORKDIR/cleanup.out" "$WORKDIR/cleanup.err")"
fi

# ==============================================================================
echo "--- continuing from analysis, and a run that is not waiting"

S=anw
if reach "$S" analysis; then
    tick "$S" '{"plan_outcome":"blocked_missing_context","approach_summary":"no cache store is named"}'
    attempt "$S" --result undecided --state analysis:1
    raise "$S" --attempt "$A" --state analysis:1
    QA=$Q
    tick "$S" '{"decide_outcome":"raised"}'
    expect_state "analysis raised" done_waiting
    manager_answers "$S" "$QA"
    toks '["x"]'
    bash "$OPEN" --workflow "$S" --var ISSUE_NUMBER=2 --var ARTIFACT_PREFIX=issue_2 --var ISSUE_TYPE=task --dispatched-by manager \
        --continue-waiting "$TOKS" > "$WORKDIR/cont.out" 2>"$WORKDIR/cont.err"
    SUCC=$(sed -n 's/^session=//p' "$WORKDIR/cont.out")
    attempt "$SUCC" --result decided --chosen SQLite --basis "$ANS"
    tick "$SUCC"
    expect_state "the continued analysis run resumes" analysis
    tick "$SUCC" '{"plan_outcome":"blocked_missing_context","approach_summary":"still no store"}'
    [ "$(ctx "$SUCC" decide_arrival)" = analysis:2 ] && pass "the successor's next arrival goes on counting: analysis:2" \
        || fail "the successor's arrival is [$(ctx "$SUCC" decide_arrival)]"
    attempt "$SUCC" --result decided --chosen SQLite --state analysis:1
    tick "$SUCC" '{"decide_outcome":"decided","decided_next":"stop"}'
    expect_state "an attempt for the predecessor's arrival name does not count" decide_first
    toks '["x"]'
    bash "$OPEN" --workflow "$SUCC" --var ISSUE_NUMBER=2 --var ARTIFACT_PREFIX=issue_2 --var ISSUE_TYPE=task --continue-waiting "$TOKS" \
        > "$WORKDIR/cont.out" 2>"$WORKDIR/cont.err"
    RC=$?
    [ "$RC" = 2 ] && grep -qx refused=not_waiting "$WORKDIR/cont.out" && pass "--continue-waiting refuses a run that is not waiting" \
        || fail "--continue-waiting on a live run exited $RC: $(cat "$WORKDIR/cont.out" "$WORKDIR/cont.err")"
fi

# ==============================================================================
echo "--- continuing a leg-bound run"

# A run opened under a koto request's leg ends at done_waiting, which resolves
# that leg. koto's succession can't take a leg, so --continue-waiting under a
# new request's leg rewinds the waiting session to waiting_record and attaches
# it under the new leg.
newreq() {
    koto request create \
        --with-data '{"legs":[{"name":"work-on","role":"work-on","template":"work-on.md","inputs":{}}]}' \
        --requested-by manager --coordinator-of-record manager > "$WORKDIR/req.out" 2>"$WORKDIR/req.err"
    REQ=$(jq -r '.request_id // empty' "$WORKDIR/req.out" 2>>"$WORKDIR/req.err")
    [ -n "$REQ" ] || fail "koto request create: $(head -c 300 "$WORKDIR/req.out") $(head -c 300 "$WORKDIR/req.err")"
}
# legof <request> <jq filter>: koto's JSON (an error included) goes to a file
# first, so a refusal printed on stdout shows in the case that reads it.
legof() {
    koto request get "$1" > "$WORKDIR/leg.out" 2>"$WORKDIR/leg.err"
    jq -r "(.request // .) | .legs[\"work-on\"] | $2" "$WORKDIR/leg.out" 2>>"$WORKDIR/leg.err" \
        || printf 'unreadable: %s %s' "$(head -c 200 "$WORKDIR/leg.out")" "$(head -c 200 "$WORKDIR/leg.err")"
}
# cont_leg <session> <request> <dispatcher>: --continue-waiting under the leg.
cont_leg() {
    toks "[\"x\",\"--koto-leg\",\"$2:work-on\"]"
    bash "$OPEN" --workflow "$1" --var ISSUE_NUMBER=2 --var ARTIFACT_PREFIX=issue_2 --var ISSUE_TYPE=task --dispatched-by "$3" \
        --continue-waiting "$TOKS" > "$WORKDIR/cont.out" 2>"$WORKDIR/cont.err"
    RC=$?
}
cur() { koto status "$1" 2>"$WORKDIR/status.err" | jq -r '.current_state // empty'; }

S=lgw
if ! koto init --help 2>"$WORKDIR/help.err" | grep -q -- '--koto-leg'; then
    fail "koto init has no --koto-leg: the leg-bound continuation was not exercised"
else
    newreq; R1=$REQ
    git checkout -q main
    git checkout -q -b "case-$S"
    toks "[\"x\",\"--koto-leg\",\"$R1:work-on\"]"
    bash "$OPEN" --workflow "$S" --var ISSUE_NUMBER=2 --var ARTIFACT_PREFIX=issue_2 --var ISSUE_TYPE=task --dispatched-by manager \
        "$TOKS" > "$WORKDIR/open.out" 2>"$WORKDIR/open.err" \
        || fail "$S: work-on-open.sh under the leg failed: $(cat "$WORKDIR/open.out" "$WORKDIR/open.err")"
    issue_walk "$S" 2
    tick "$S" '{"plan_outcome":"blocked_missing_context","approach_summary":"no cache store is named"}'
    attempt "$S" --result undecided --state analysis:1
    raise "$S" --attempt "$A" --state analysis:1
    QL=$Q
    tick "$S" '{"decide_outcome":"raised"}'
    expect_state "the leg-bound run raised" done_waiting
    [ "$(legof "$R1" '"\(.disposition)|\(.bound_child)|\(.result.payload.question)"')" = "resolved|$S|$QL" ] \
        && pass "done_waiting resolved the first leg with the question" || fail "the first leg: $(legof "$R1" . | cut -c1-400)"

    newreq; R2=$REQ
    cont_leg "$S" "$R2" manager
    [ "$RC" = 3 ] && grep -qx "waiting=$QL" "$WORKDIR/cont.out" && [ "$(cur "$S")" = done_waiting ] \
        && [ "$(legof "$R2" '"\(.disposition)|\(.bound_child)"')" = "open|null" ] \
        && pass "under a leg, an open question is reported (exit 3) and nothing is rewound or attached" \
        || fail "--continue-waiting under a leg while open exited $RC: $(cat "$WORKDIR/cont.out" "$WORKDIR/cont.err")"

    manager_answers "$S" "$QL"
    cont_leg "$S" "$R2" scratch
    [ "$RC" = 2 ] && grep -qx refused=dispatcher_differs "$WORKDIR/cont.out" && [ "$(cur "$S")" = done_waiting ] \
        && pass "under a leg, a different dispatcher is refused with nothing rewound" \
        || fail "--continue-waiting under a leg --dispatched-by scratch exited $RC: $(cat "$WORKDIR/cont.out" "$WORKDIR/cont.err")"

    # The first request is still open, so the session still answers a live
    # leg and koto refuses the attach; the session goes back to done_waiting.
    cont_leg "$S" "$R2" manager
    [ "$RC" != 0 ] && grep -qx restored=done_waiting "$WORKDIR/cont.out" && [ "$(cur "$S")" = done_waiting ] \
        && [ "$(legof "$R2" '.result_source')" = refused ] \
        && pass "an attach refused while the first request is open restores done_waiting and resolves the new leg as refused" \
        || fail "--continue-waiting with the first request open exited $RC: $(cat "$WORKDIR/cont.out" "$WORKDIR/cont.err") leg: $(legof "$R2" . | cut -c1-300)"

    koto request close "$R1" > "$WORKDIR/close.out" 2>"$WORKDIR/close.err" \
        || fail "koto request close $R1: $(cat "$WORKDIR/close.out" "$WORKDIR/close.err")"
    newreq; R3=$REQ
    cont_leg "$S" "$R3" manager
    [ "$RC" = 0 ] && grep -qx continued=waiting "$WORKDIR/cont.out" && grep -qx opened=attached "$WORKDIR/cont.out" \
        && grep -qx "session=$S" "$WORKDIR/cont.out" && [ "$(cur "$S")" = waiting_record ] \
        && [ "$(legof "$R3" '"\(.disposition)|\(.bound_child)"')" = "open|$S" ] \
        && pass "once the first request is closed, the session is rewound to waiting_record and attached under the new leg" \
        || fail "--continue-waiting under a new leg exited $RC: $(cat "$WORKDIR/cont.out" "$WORKDIR/cont.err") leg: $(legof "$R3" . | cut -c1-300)"
    tick "$S"
    expect_state "waiting_record sends the answered run back" decide_first
    [ "$(ctx "$S" decide_question)" = "$QL" ] && pass "decide_question still names the question the run waited on" \
        || fail "decide_question is [$(ctx "$S" decide_question)], want $QL"
    attempt "$S" --result decided --chosen SQLite --state analysis:1
    tick "$S" '{"decide_outcome":"decided","decided_next":"resume"}'
    expect_state "a deciding attempt that does not cite the answer is held" decide_first
    case "$(gate_stdout attempt_recorded)" in *"was answered"*) pass "attempt_recorded names the answer to cite" ;;
        *) fail "attempt_recorded printed [$(gate_stdout attempt_recorded)]" ;; esac
    attempt "$S" --result decided --chosen SQLite --basis "$ANS" --state analysis:1
    tick "$S" '{"decide_outcome":"decided","decided_next":"resume"}'
    expect_state "citing the answer resumes the run under the new leg" analysis
    [ "$(legof "$R1" '"\(.disposition)|\(.result.payload.question)"')" = "resolved|$QL" ] \
        && pass "the first leg keeps its waiting result" || fail "the first leg: $(legof "$R1" . | cut -c1-400)"

    # An answer with no authority over the run (its own) is refused before
    # anything is rewound.
    S=lgx
    if reach "$S" analysis; then
        tick "$S" '{"plan_outcome":"blocked_missing_context","approach_summary":"no cache store is named"}'
        attempt "$S" --result undecided --state analysis:1
        raise "$S" --attempt "$A" --state analysis:1
        QX=$Q
        tick "$S" '{"decide_outcome":"raised"}'
        expect_state "the second run raised" done_waiting
        answers "$S" "$S" "$QX"
        newreq
        cont_leg "$S" "$REQ" manager
        [ "$RC" = 2 ] && grep -qx refused=answer_without_authority "$WORKDIR/cont.out" && [ "$(cur "$S")" = done_waiting ] \
            && [ "$(legof "$REQ" '"\(.disposition)|\(.bound_child)"')" = "open|null" ] \
            && pass "under a leg, an answer without authority is refused with nothing rewound" \
            || fail "--continue-waiting on a self-answered question exited $RC: $(cat "$WORKDIR/cont.out" "$WORKDIR/cont.err")"
    fi
fi

# ==============================================================================
echo "--- stale approval"

# An answer cited for one deferral, then the run back at finalization (as
# pr_precheck's recount brings it, through pass_counting; koto rewind stands
# for that walk here) deferring again: the earlier answer approves nothing.
S=stl
if reach "$S" deferral_approval; then
    tick "$S" '{"approval_decision":"needs_answer"}'
    attempt "$S" --result undecided --state deferral_approval:1
    raise "$S" --attempt "$A" --state deferral_approval:1
    manager_answers "$S" "$Q"
    attempt "$S" --result decided --chosen "defer the criterion" --state deferral_approval:1 --basis "$ANS"
    tick "$S" '{"decide_outcome":"decided","decided_next":"resume"}'
    expect_state "stale: the cited answer resumes the first deferral" deferral_approval
    n=0
    while [ "$STATE" != finalization ] && [ "$n" -lt 12 ]; do
        koto rewind "$S" --rationale "the run comes back to finalization" > "$WORKDIR/rewind.out" 2>"$WORKDIR/rewind.err" \
            || { fail "koto rewind $S: $(cat "$WORKDIR/rewind.out" "$WORKDIR/rewind.err")"; break; }
        STATE=$(koto status "$S" 2>"$WORKDIR/status.err" | jq -r '.current_state // empty')
        n=$((n + 1))
    done
    expect_state "stale: back at finalization" finalization
    tick "$S" '{"finalization_status":"deferral_requested"}'
    expect_state "stale: a second deferral" deferral_approval
    [ "$(ctx "$S" decide_arrival)|$(ctx "$S" decide_question)" = "none|none" ] \
        && pass "stale: the second deferral cleared decide_arrival and decide_question" \
        || fail "stale: decide_arrival [$(ctx "$S" decide_arrival)], decide_question [$(ctx "$S" decide_question)]"
    tick "$S" '{"approval_decision":"approved","cleanup_done":"none_found","design_diagram":"not_applicable"}'
    expect_state "stale: the first deferral's answer does not approve the second" deferral_approval
    case "$(gate_stdout answer_cited)" in *needs_answer*) pass "stale: answer_cited asks for needs_answer again" ;;
        *) fail "stale: answer_cited printed [$(gate_stdout answer_cited)]" ;; esac
fi

# ==============================================================================
echo "--- a deciding attempt beside an open question"

S=dec
if reach "$S" task_validation; then
    tick "$S" '{"verdict":"exit","rationale":"the task names no outcome"}'
    attempt "$S" --result undecided --state task_validation:1
    raise "$S" --attempt "$A" --state task_validation:1
    attempt "$S" --result decided --chosen "carry on" --state task_validation:1
    tick "$S" '{"decide_outcome":"decided","decided_next":"resume"}'
    expect_state "a deciding attempt beside the arrival's open question is held" decide_first
    case "$(gate_stdout attempt_recorded)" in *"is still open"*) pass "attempt_recorded says the question is still open" ;;
        *) fail "attempt_recorded printed [$(gate_stdout attempt_recorded)]" ;; esac
    shirabe question withdraw "$Q" --in "$S" --reason "the run settled it" > "$WORKDIR/wd.out" 2>"$WORKDIR/wd.err" \
        || fail "withdraw: $(cat "$WORKDIR/wd.out" "$WORKDIR/wd.err")"
    tick "$S" '{"decide_outcome":"decided","decided_next":"resume"}'
    expect_state "once the question is withdrawn, the deciding attempt resumes" task_validation
fi

# ==============================================================================
echo "--- lap cap"

S=lap
if reach "$S" task_validation; then
    k=1
    while [ "$k" -le 3 ]; do
        tick "$S" '{"verdict":"exit","rationale":"the task names no outcome"}'
        attempt "$S" --result decided --chosen "carry on" --state "task_validation:$k"
        tick "$S" '{"decide_outcome":"decided","decided_next":"resume"}'
        expect_state "lap $k resumes" task_validation
        k=$((k + 1))
    done
    tick "$S" '{"verdict":"exit","rationale":"the task names no outcome"}'
    attempt "$S" --result decided --chosen "carry on" --state task_validation:4
    tick "$S" '{"decide_outcome":"decided","decided_next":"resume"}'
    expect_state "the fourth arrival from task_validation cannot resume" decide_first
    case "$(gate_stdout decide_laps)" in *"resume is refused"*) pass "decide_laps says resume is refused" ;;
        *) fail "decide_laps printed [$(gate_stdout decide_laps)]" ;; esac
    tick "$S" '{"decide_outcome":"decided","decided_next":"stop"}'
    expect_state "the fourth arrival stops at the old exit" validation_exit
fi

# ==============================================================================
echo "--- withdrawn"

S=wdr
if reach "$S" implementation; then
    tick "$S" '{"implementation_status":"blocked","rationale":"no cache store is chosen"}'
    attempt "$S" --result undecided --state implementation:1
    raise "$S" --attempt "$A" --state implementation:1
    tick "$S" '{"decide_outcome":"raised"}'
    expect_state "implementation raised" done_waiting
    shirabe question withdraw "$Q" --in "$S" --reason "the store was chosen elsewhere" > "$WORKDIR/wd.out" 2>"$WORKDIR/wd.err" \
        || fail "withdraw: $(cat "$WORKDIR/wd.out" "$WORKDIR/wd.err")"
    toks '["x"]'
    bash "$OPEN" --workflow "$S" --var ISSUE_NUMBER=2 --var ARTIFACT_PREFIX=issue_2 --var ISSUE_TYPE=task --dispatched-by manager \
        --continue-waiting "$TOKS" > "$WORKDIR/cont.out" 2>"$WORKDIR/cont.err"
    RC=$?
    [ "$RC" = 2 ] && grep -qx refused=withdrawn "$WORKDIR/cont.out" && ! koto status "$S-r2" > /dev/null 2>"$WORKDIR/status.err" \
        && pass "--continue-waiting refuses a withdrawn question and opens no successor" \
        || fail "--continue-waiting after withdraw exited $RC: $(cat "$WORKDIR/cont.out" "$WORKDIR/cont.err")"
    koto session cleanup "$S" > "$WORKDIR/cleanup.out" 2>"$WORKDIR/cleanup.err" \
        && pass "a waiting session whose question was withdrawn cleans up" || fail "cleanup after withdraw: $(cat "$WORKDIR/cleanup.out" "$WORKDIR/cleanup.err")"
fi

# ==============================================================================
echo "--- attended, then precedent"

mkdir -p "$ACCOUNT_HOME/.claude/projects" || { fail "cannot make $ACCOUNT_HOME/.claude/projects"; finish; }
RECORDS=$(mktemp -d "$ACCOUNT_HOME/.claude/projects/shirabe-decide-first-routes-test.XXXXXX") \
    || { fail "mktemp under the account's .claude/projects failed"; finish; }
harness_id() {
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' \
        | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/'
}
record() {
    jq -c --slurpfile r "$1" --arg h "$2" --arg pick "$3" \
        --arg now "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" '
        ($r[0].prompts[0].questions) as $qs
        | if .type == "assistant" then
              .message.content[0].input.questions = $qs
              | .wireToolInputs["toolu_ZQXMARKERcall000000000001"].questions = $qs
          else
              .toolUseResult.questions = $qs
              | .toolUseResult.answers = {($qs[0].question): $pick}
          end
        | .timestamp = $now | .session_id = $h | .sessionId = $h' "$PROMPT_FIXTURE" > "$RECORDS/$2.jsonl"
}

# A run nothing dispatched asks the owner.
S=att
git checkout -q main
git checkout -q -b "case-$S"
toks '["x"]'
if bash "$OPEN" --workflow "$S" --var ISSUE_NUMBER=2 --var ARTIFACT_PREFIX=issue_2 --var ISSUE_TYPE=task "$TOKS" > "$WORKDIR/open.out" 2>"$WORKDIR/open.err"; then
    issue_walk "$S" 2
    tick "$S" '{"plan_outcome":"plan_ready"}'
    tick "$S" '{"implementation_status":"blocked","rationale":"no cache store is chosen"}'
    attempt "$S" --result undecided --state implementation:1
    raise "$S" --attempt "$A" --state implementation:1
    QO=$Q
    shirabe question render "$QO" > "$WORKDIR/render.out" 2>"$WORKDIR/render.err" || fail "render: $(cat "$WORKDIR/render.err")"
    sleep 1
    H=$(harness_id)
    record "$WORKDIR/render.out" "$H" SQLite
    # koto records an answer in the session the prompt was opened from, never
    # in the one that raised the question; att-prompt stands for that session.
    koto init att-prompt --template "$WORKDIR/manager.md" > /dev/null 2>"$WORKDIR/init.err" \
        || fail "koto init att-prompt: $(cat "$WORKDIR/init.err")"
    CLAUDE_CODE_SESSION_ID="$H" shirabe question answer "$QO" --in att-prompt > "$WORKDIR/answer.out" 2>"$WORKDIR/answer.err"
    OWNER="$(jq -r '.session // empty' "$WORKDIR/answer.out"):$(jq -r '.id // empty' "$WORKDIR/answer.out")"
    [ "$(jq -r '.reading // empty' "$WORKDIR/answer.out")" = verified ] && pass "attended: the recorded prompt's answer reads verified" \
        || fail "attended: answer: $(cat "$WORKDIR/answer.out" "$WORKDIR/answer.err")"
    tick "$S" '{"decide_outcome":"raised"}'
    expect_state "attended: raised is held once the question is answered" decide_first
    attempt "$S" --result decided --chosen SQLite --basis "$OWNER" --state implementation:1
    tick "$S" '{"decide_outcome":"decided","decided_next":"resume"}'
    expect_state "attended: decided goes on once an attempt cites the answer" implementation

    tick "$S" '{"implementation_status":"blocked","rationale":"the store needs a path"}'
    shirabe question precedent --in "$S" --label "build cache store" > "$WORKDIR/prec.out" 2>"$WORKDIR/prec.err"
    PREC=$(jq -r '.answers[0] | "\(.session):\(.id)"' "$WORKDIR/prec.out")
    [ "$PREC" = "$OWNER" ] && pass "precedent: the run reads the owner's answer under its label" \
        || fail "precedent: [$PREC], want $OWNER: $(cat "$WORKDIR/prec.out" "$WORKDIR/prec.err")"
    raised_before=$(grep -c '^question raise' "$WORKDIR/shirabe.log")
    attempt "$S" --result decided --chosen SQLite --basis "$PREC" --state implementation:2
    tick "$S" '{"decide_outcome":"decided","decided_next":"stop"}'
    expect_state "precedent: a deciding attempt citing the earlier answer takes the exit" done_blocked
    [ "$(grep -c '^question raise' "$WORKDIR/shirabe.log")" = "$raised_before" ] && pass "precedent: no question was raised for implementation:2" \
        || fail "precedent: a question was raised"
else
    fail "$S: work-on-open.sh failed: $(cat "$WORKDIR/open.out" "$WORKDIR/open.err")"
fi

# ==============================================================================
echo "--- no covered exit"

# A change run from entry to finalization: entry's continues_waiting gate
# finds no decide_question, and the run never enters resume_waiting.
S=plain
: > "$WORKDIR/shirabe.log"
if open_run "$S" 2 --var ISSUE_TYPE=task --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI"; then
    issue_walk "$S" 2
    tick "$S" '{"plan_outcome":"plan_ready"}'
    printf 'shout\n' > "SHOUT-$S.md"
    git add "SHOUT-$S.md"
    git commit -q -m "feat: shout"
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"task"}'
    expect_state "a change run" finalization
    [ "$(grep -c '^question' "$WORKDIR/shirabe.log")" = 0 ] && pass "a run to finalization makes no shirabe question call" \
        || fail "shirabe question calls: $(grep '^question' "$WORKDIR/shirabe.log")"
    koto context exists "$S" decide_arrival > /dev/null && fail "the run arrived at decide_first" || pass "and never arrives at decide_first"
fi

# The same submissions, from koto init, to the merge-base template and to the
# branch's: the state each tick lands in must be the same throughout.
# seq_walk <session> <template> -> the states in $SEQ
seq_walk() {
    local s=$1
    SEQ=""
    git checkout -q main
    git checkout -q -b "case-$s"
    koto init "$s" --template "$2" --var ISSUE_NUMBER=2 --var ARTIFACT_PREFIX=issue_2 --var ISSUE_TYPE=task \
        --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI" \
        --var PLUGIN_ROOT="$PLUGIN_ROOT" > /dev/null 2>"$WORKDIR/init.err" \
        || { fail "koto init $s: $(cat "$WORKDIR/init.err")"; return 1; }
    tick "$s"; SEQ="$SEQ $STATE"
    tick "$s" '{"mode":"issue_backed","issue_number":"2"}'; SEQ="$SEQ $STATE"
    tick "$s" '{"status":"override"}'; SEQ="$SEQ $STATE"
    tick "$s" '{"status":"override"}'; SEQ="$SEQ $STATE"
    printf '# Issue 2\n\n## Acceptance Criteria\n\n- [ ] it works\n' | koto context add "$s" context.md > /dev/null
    printf 'plan\n' | koto context add "$s" plan.md > /dev/null
    tick "$s" '{"plan_outcome":"plan_ready"}'; SEQ="$SEQ $STATE"
    printf 'shout\n' > "SHOUT-$s.md"
    git add "SHOUT-$s.md"
    git commit -q -m "feat: shout"
    tick "$s" '{"implementation_status":"complete"}'; SEQ="$SEQ $STATE"
    tick "$s" '{"issue_type":"task"}'; SEQ="$SEQ $STATE"
    tick "$s" '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'; SEQ="$SEQ $STATE"
    # What held the last tick, so a difference names its gate.
    SEQ_HELD=$(printf '%s' "$RESP" | jq -c '[.blocking_conditions[]? | {name, stdout: .failure.captured.stdout, stderr: .failure.captured.stderr}]' | cut -c1-800)
}
if [ -n "$BASE_TEMPLATE" ]; then
    if seq_walk seqo "$BASE_TEMPLATE"; then
        SEQ_OLD=$SEQ
        HELD_OLD=$SEQ_HELD
        if seq_walk seqb "$TEMPLATE"; then
            echo "states, tick by tick:$SEQ_OLD"
            [ "$SEQ" = "$SEQ_OLD" ] && pass "a run with no covered exit lands in the same state at every tick on both templates" \
                || fail "the branch's states [$SEQ], the merge-base's [$SEQ_OLD]; last held on the branch by $SEQ_HELD, on the merge-base by $HELD_OLD"
            koto context exists seqb decide_arrival > /dev/null && fail "the branch's run arrived at decide_first" || :
        fi
    fi
else
    echo "SKIP: the state sequence: $BASE_WHY"
fi

# ==============================================================================
echo "--- an old session"

if [ -n "$BASE_TEMPLATE" ]; then
    S=old
    git checkout -q main
    git checkout -q -b "case-$S"
    if koto init "$S" --template "$BASE_TEMPLATE" --var ISSUE_NUMBER=2 --var ARTIFACT_PREFIX=issue_2 --var ISSUE_TYPE=task \
            --var PLUGIN_ROOT="$PLUGIN_ROOT" > /dev/null 2>"$WORKDIR/init.err"; then
        issue_walk "$S" 2
        tick "$S" '{"plan_outcome":"blocked_missing_context","approach_summary":"no cache store is named"}'
        expect_state "a session from the earlier template stops where it did" done_blocked
    else
        fail "koto init $S from the base template: $(cat "$WORKDIR/init.err")"
    fi
else
    echo "SKIP: an old session: $BASE_WHY"
fi

# ==============================================================================
echo "--- a parent from execute.md"

# The parent is execute.md's own spawn_and_await, read from the file, with
# its child template pointed at the branch's work-on.md and its two ways out
# made terminals. Child a waits on a question; b, which waits on a, must not
# be released.
EXEC="$SRC_ROOT/skills/execute/koto-templates/execute.md"
{
    printf '%s\n' '---' 'name: execute-parent' 'version: "1.0"' 'initial_state: spawn_and_await' \
        'variables:' '  PLUGIN_ROOT:' '    required: true' 'states:'
    awk '/^  spawn_and_await:$/ { f = 1 } /^  pr_finalization:$/ { f = 0 } f' "$EXEC" \
        | sed "s|default_template: .*|default_template: $TEMPLATE|"
    printf '%s\n' '  pr_finalization:' '    terminal: true' '  escalate:' '    terminal: true' '    failure: true' '---' '' \
        '## spawn_and_await' '' 'Submit tasks.' '' '## pr_finalization' '' 'Done.' '' '## escalate' '' 'Stopped.'
} > "$WORKDIR/parent.md"
git checkout -q main
git checkout -q -b case-parent
if grep -q 'failure_policy: skip_dependents' "$WORKDIR/parent.md" \
        && koto init par --template "$WORKDIR/parent.md" --var PLUGIN_ROOT="$PLUGIN_ROOT" > /dev/null 2>"$WORKDIR/init.err"; then
    jq -cn --arg r "$PLUGIN_ROOT" '{tasks: [
        {name: "a", description: "a", vars: {PLUGIN_ROOT: $r, ARTIFACT_PREFIX: "par_a"}},
        {name: "b", description: "b", vars: {PLUGIN_ROOT: $r, ARTIFACT_PREFIX: "par_b"}, waits_on: ["a"]}]}' > "$WORKDIR/tasks.json"
    tick par "@$WORKDIR/tasks.json"
    C=par.a
    tick "$C" '{"mode":"free_form","task_description":"add a shout flag"}'
    tick "$C" '{"verdict":"exit","rationale":"which flag name is open"}'
    attempt "$C" --result undecided --state task_validation:1
    raise "$C" --attempt "$A" --state task_validation:1
    tick "$C" '{"decide_outcome":"raised"}'
    expect_state "the child" done_waiting
    tick par
    expect_state "a parent from execute.md, its child waiting" escalate
    case "$(ctx par failure_reason)" in
        *"1 failed, 1 skipped"*) pass "the waiting child counts as failed and b, which depends on it, is skipped" ;;
        *) fail "the parent's failure_reason is [$(ctx par failure_reason)]" ;;
    esac
    koto status par > "$WORKDIR/par.out" 2>"$WORKDIR/par.err"
    [ "$(jq -r '[.batch.tasks[]? | select(.task_name == "b") | .outcome] | join(",")' "$WORKDIR/par.out")" = skipped ] \
        && pass "the batch view has b skipped, not released" \
        || fail "b in the batch view: $(cat "$WORKDIR/par.out" "$WORKDIR/par.err")"
else
    fail "the parent from execute.md: $(cat "$WORKDIR/init.err")"
fi

# ==============================================================================
echo "--- words"

for st in decide_first done_waiting; do
    text=$(q ".states.$st.directive" | tr 'A-Z' 'a-z')
    case "$text" in
        *escalat*) fail "$st's directive says escalate" ;;
        *) pass "$st's directive never says escalate" ;;
    esac
done

finish
