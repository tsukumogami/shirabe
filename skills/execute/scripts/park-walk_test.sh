#!/usr/bin/env bash
# park-walk_test.sh -- a parked step walked end to end through real koto.
#
# The parent is execute.md's own batch states, cut from the template as they
# are committed (spawn_and_await, escalate_parked, waiting_record and
# done_waiting), with terminal stand-ins for the states they leave to. Its
# children run a small template holding /work-on's own decide_first,
# waiting_record, resume_waiting and entry gate, cut from work-on.md, around
# one implementation state. Every gate runs the branch's scripts: park.sh,
# parked-state.sh and decide-first-gate.sh. plan-to-tasks.sh and step-group.sh
# are stand-ins (the tasks below; every step landed).
#
# Cases:
#   the walk        tasks a, b and c, c waiting on a. a raises a question and
#                   parks; b runs to done; c is not started. The batch ends
#                   at done_waiting naming a's question. The owner answers it
#                   (a verified answer, from a recorded prompt). The run is
#                   rewound, as execute-open.sh does on re-invocation, and
#                   lands at waiting_record; one tick takes it to
#                   spawn_and_await, where the batch holds (parked_state 4).
#                   retry_failed with include_skipped, then the same tasks
#                   again, takes a back to entry and c's skip marker away.
#                   a goes to resume_waiting and holds there until its
#                   attempt cites the answer; park.sh clear refuses until
#                   then. a goes back to implementation and finishes; clear
#                   removes the key; c runs and finishes; the batch reaches
#                   pr_finalization.
#   the refusals    a second run with independent steps x and y, each parked.
#                   x's question answered by the run itself and y's by an
#                   unrelated session: park.sh list names each unauthorized,
#                   clear refuses each and cited answers 1, and the batch
#                   holds. Where koto itself refuses one of those answers,
#                   the case says so and passes on koto's refusal.
#   no covered exit execute.md's states from worktree_discipline_check to
#                   pr_finalization, cut from the template before decide_first
#                   was added and from the branch's, each driven the same way
#                   (informational, two independent steps, both done): the
#                   state after every tick is the same on both, and a
#                   shirabe that logs its calls, first on PATH, logs no
#                   `question` call
#   an old session  a session opened on the earlier cut reaches done_blocked
#                   on intent-changing, with step execute:re-evaluation, run
#                   against the branch's scripts
#   The earlier template is the parent of the commit that added decide_first
#   to execute.md (git log -S). With no such commit in the clone these two
#   cases skip, saying so, and under CI (GITHUB_ACTIONS) they fail instead.
#
# Usage: bash skills/execute/scripts/park-walk_test.sh
#   shirabe from SHIRABE_BIN, else the tree's target/release/shirabe, else
#   PATH; it must have `question precedent`. koto on PATH; jq.
#
# Exit codes:
#   0 -- all cases pass, or koto or jq is absent and every case skipped
#   1 -- a case failed, or shirabe has no `question precedent`
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
unset KOTO_RUN_MODE CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID
unset KOTO_DECIDER KOTO_DECIDER_API_KEY KOTO_DECIDER_ENDPOINT

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO=$(cd "$SCRIPT_DIR/../../.." && pwd -P)
FIXTURE="$REPO/scripts/fixtures/question-commands/accepted.jsonl"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
finish() {
    echo
    echo "park-walk_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
}
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: want [$2], got [$3]"; fi; }

for tool in koto jq; do
    command -v "$tool" > /dev/null || { echo "SKIP: $tool is not on PATH -- no case ran"; exit 0; }
done
SHIRABE=""
if [ -n "${SHIRABE_BIN:-}" ] && [ -x "$SHIRABE_BIN" ]; then
    SHIRABE=$SHIRABE_BIN
elif [ -x "$REPO/target/release/shirabe" ]; then
    SHIRABE="$REPO/target/release/shirabe"
else
    SHIRABE=$(command -v shirabe)
fi
case "$SHIRABE" in /*) ;; *) SHIRABE="" ;; esac
if [ -z "$SHIRABE" ] || ! "$SHIRABE" question precedent --help > /dev/null; then
    fail "no shirabe with \`question precedent\` (SHIRABE_BIN, target/release/shirabe or PATH); build the branch's (cargo build --release -p shirabe)"
    finish
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/park-walk-test.XXXXXX") || { fail "mktemp failed"; finish; }
ACCOUNT_HOME=$(eval echo "~$(id -un)")
RECORDS=""
cleanup() {
    [ -n "${T:-}" ] && rm -rf "$T"
    [ -n "$RECORDS" ] && rm -rf "$RECORDS"
    return 0
}
ktg_on_exit cleanup
cd "$T" || { fail "cd $T"; finish; }

mkdir -p "$T/bin"
ln -s "$SHIRABE" "$T/bin/shirabe"
export PATH="$T/bin:$PATH"

# --- the plugin tree: the branch's scripts, and two stand-ins ---------------------

P="$T/plugin"
mkdir -p "$P/skills/execute/scripts" "$P/skills/work-on/scripts" "$P/skills/plan/scripts"
for f in park.sh park-lib.sh parked-state.sh; do
    ln -s "$REPO/skills/execute/scripts/$f" "$P/skills/execute/scripts/$f"
done
ln -s "$REPO/skills/work-on/scripts/decide-first-gate.sh" "$P/skills/work-on/scripts/decide-first-gate.sh"
ln -s "$REPO/scripts" "$P/scripts"
# plan-to-tasks.sh prints the tasks file named beside the PLAN.
cat > "$P/skills/plan/scripts/plan-to-tasks.sh" <<'EOF'
#!/usr/bin/env bash
cat "$1.tasks"
EOF
cat > "$P/skills/execute/scripts/step-group.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$P/skills/plan/scripts/plan-to-tasks.sh" "$P/skills/execute/scripts/step-group.sh"

# --- the templates ------------------------------------------------------------------

# cut <template> <first state> <state after the last>: the frontmatter lines
# from the first state up to the next, as committed.
cut_states() {
    awk -v a="  $2:" -v b="  $3:" '$0 == a { f = 1 } $0 == b { f = 0 } f' "$1"
}
EXEC_MD="$REPO/skills/execute/koto-templates/execute.md"
WORKON_MD="$REPO/skills/work-on/koto-templates/work-on.md"
cut_states "$EXEC_MD" spawn_and_await pr_finalization > "$T/parent-states.yaml"
grep -q '^  done_waiting:' "$T/parent-states.yaml" || { fail "execute.md's batch states could not be cut from $EXEC_MD"; finish; }
grep -q 'default_template: ../../work-on/koto-templates/work-on.md' "$T/parent-states.yaml" \
    || { fail "spawn_and_await's default_template is not work-on.md: the walk would not stand in for it"; finish; }
sed 's|default_template: ../../work-on/koto-templates/work-on.md|default_template: child.md|' "$T/parent-states.yaml" > "$T/parent-states.cut"
{
    cat <<'EOF'
---
name: execute
version: "1.0"
initial_state: spawn_and_await
variables:
  PLAN_DOC:
    required: true
  PLAN_SLUG:
    required: true
  PLUGIN_ROOT:
    required: true
states:
EOF
    cat "$T/parent-states.cut"
    cat <<'EOF'
  pr_finalization:
    terminal: true
  escalate:
    terminal: true
    failure: true
  escalate_upstream_drift:
    terminal: true
    failure: true
---
EOF
    for s in spawn_and_await escalate_parked waiting_record done_waiting pr_finalization escalate escalate_upstream_drift; do
        printf '\n## %s\n\nThe %s state.\n' "$s" "$s"
    done
} > "$T/execute.md"

# The child: work-on.md's decide_first, waiting_record and resume_waiting as
# committed, with the edges to states this child lacks taken out and the
# plugin root written in (a batch child gets no variables here), around one
# implementation state; its entry routes on work-on.md's continues_waiting
# gate as work-on.md's entry does.
for s in decide_first:waiting_record waiting_record:done_waiting resume_waiting:context_injection; do
    cut_states "$WORKON_MD" "${s%%:*}" "${s#*:}"
done > "$T/child-cut.yaml"
for s in decide_first waiting_record resume_waiting; do
    grep -q "^  $s:" "$T/child-cut.yaml" || { fail "work-on.md's $s could not be cut from $WORKON_MD"; finish; }
done
# Keep, of each transition list, the edges whose target the child holds.
awk '
    /^      - target: / { keep = ($3 == "implementation" || $3 == "waiting_record" || $3 == "done_waiting" || $3 == "decide_first") }
    /^  [a-z_]+:$/ { keep = 1 }
    /^    [a-z_]+:/ { keep = 1 }
    keep
' "$T/child-cut.yaml" > "$T/child-states.yaml"
{
    cat <<'EOF'
---
name: child
version: "1.0"
initial_state: entry
states:
  entry:
    gates:
      continues_waiting:
        type: context-exists
        key: decide_question
        overridable: false
    transitions:
      - target: implementation
        when:
          gates.continues_waiting.exists: false
      - target: resume_waiting
        when:
          gates.continues_waiting.exists: true
  implementation:
    accepts:
      impl:
        type: enum
        values: [done, ask]
        required: true
    transitions:
      - target: done
        when:
          impl: done
      - target: decide_first
        when:
          impl: ask
        context_assignments:
          decide_origin: implementation
EOF
    cat "$T/child-states.yaml"
    cat <<'EOF'
  done_waiting:
    terminal: true
    failure: true
    result:
      question: "${context.decide_question}"
  done:
    terminal: true
  skipped_due_to_dep_failure:
    terminal: true
    skipped_marker: true
---
EOF
    for s in entry implementation decide_first waiting_record resume_waiting done_waiting done skipped_due_to_dep_failure; do
        printf '\n## %s\n\nThe %s state.\n' "$s" "$s"
    done
} | sed "s|{{PLUGIN_ROOT}}|$P|g" > "$T/child.md"
for t in execute.md child.md; do
    koto template compile "$T/$t" > /dev/null 2> "$T/compile.err" \
        || { fail "the walk's $t does not compile: $(cat "$T/compile.err")"; finish; }
done

# --- helpers ------------------------------------------------------------------------

# state <session>
state() { koto status "$1" 2> "$T/status.err" | jq -r '.current_state // empty'; }
# tick <session> [evidence file]
tick() {
    if [ -n "${2:-}" ]; then
        koto next "$1" --no-cleanup --with-data "@$2" > "$T/tick.out" 2> "$T/tick.err"
    else
        koto next "$1" --no-cleanup > "$T/tick.out" 2> "$T/tick.err"
    fi
    TICK_RC=$?
}
# submit <session> <json>
submit() {
    printf '%s\n' "$2" > "$T/ev.json"
    tick "$1" "$T/ev.json"
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
        label: $label
    }' > "$1"
}
content "$T/q.json" "build cache store"
# ask <child>: the child reaches decide_first from implementation, records an
# undecided attempt, raises its question and submits raised; the question's
# identity lands in $Q.
ask() {
    submit "$1" '{"impl":"ask"}'
    [ "$(state "$1")" = decide_first ] || { fail "$1 did not reach decide_first: $(cat "$T/tick.out" "$T/tick.err")"; return 1; }
    "$SHIRABE" question attempt --in "$1" --what "cache store" --result undecided --state implementation:1 > "$T/att.out" 2> "$T/att.err" \
        || { fail "attempt in $1: $(cat "$T/att.out" "$T/att.err")"; return 1; }
    "$SHIRABE" question raise --in "$1" --content "$T/q.json" --attempt "$(jq -r '.id' "$T/att.out")" --state implementation:1 > "$T/raise.out" 2> "$T/raise.err" \
        || { fail "raise in $1: $(cat "$T/raise.out" "$T/raise.err")"; return 1; }
    Q=$(jq -r '.identity // empty' "$T/raise.out")
    submit "$1" '{"decide_outcome":"raised"}'
    eq "$1 waits at done_waiting on its question" done_waiting "$(state "$1")"
}
# finish_child <child>: the child at implementation submits done.
finish_child() {
    submit "$1" '{"impl":"done"}'
    eq "$1 finishes" done "$(state "$1")"
}

# The owner's verified answer, from a recorded prompt, as the gate's suite
# makes one.
mkdir -p "$ACCOUNT_HOME/.claude/projects" || { fail "cannot make $ACCOUNT_HOME/.claude/projects"; finish; }
RECORDS=$(mktemp -d "$ACCOUNT_HOME/.claude/projects/shirabe-park-walk-test.XXXXXX") \
    || { fail "mktemp under the account's .claude/projects failed"; finish; }
harness_id() {
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' \
        | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/'
}
# owner_answers <identity>: the owner's answer to it, in $OWNER_ANS.
owner_answers() {
    local h
    "$SHIRABE" question render "$1" > "$T/render.out" 2> "$T/render.err" || { fail "render $1: $(cat "$T/render.err")"; return 1; }
    sleep 1
    h=$(harness_id)
    jq -c --slurpfile r "$T/render.out" --arg h "$h" --arg pick SQLite \
        --arg now "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" '
        ($r[0].prompts[0].questions) as $qs
        | if .type == "assistant" then
              .message.content[0].input.questions = $qs
              | .wireToolInputs["toolu_ZQXMARKERcall000000000001"].questions = $qs
          else
              .toolUseResult.questions = $qs
              | .toolUseResult.answers = {($qs[0].question): $pick}
          end
        | .timestamp = $now | .session_id = $h | .sessionId = $h' "$FIXTURE" > "$RECORDS/$h.jsonl"
    CLAUDE_CODE_SESSION_ID="$h" "$SHIRABE" question answer "$1" --in desk > "$T/answer.out" 2> "$T/answer.err"
    OWNER_ANS="$(jq -r '.session // empty' "$T/answer.out"):$(jq -r '.id // empty' "$T/answer.out")"
    [ "$(jq -r '.reading // empty' "$T/answer.out")" = verified ] || fail "the owner's answer to $1 does not read verified: $(cat "$T/answer.out" "$T/answer.err")"
}
park() { bash "$P/skills/execute/scripts/park.sh" "$@" > "$T/park.out" 2> "$T/park.err"; PARK_RC=$?; }

cat > "$T/desk.md" <<'EOF'
---
name: desk
version: "1.0"
initial_state: open
states:
  open:
    terminal: true
---

## open

The owner's desk.
EOF
koto init desk --template "$T/desk.md" > /dev/null 2> "$T/init.err" || { fail "koto init desk: $(cat "$T/init.err")"; finish; }
koto init stranger --template "$T/desk.md" > /dev/null 2> "$T/init.err" || { fail "koto init stranger: $(cat "$T/init.err")"; finish; }

# --- runs that reach no covered exit ---------------------------------------------------

# wd_template <execute.md> <out>: its states from worktree_discipline_check up
# to pr_finalization, as committed, children on child.md, the states it
# leaves to as terminal stand-ins. A first state, facts, gates on the two keys
# worktree_discipline_check's decider reads, as drift_facts does in the
# template, which koto requires of a decider's inputs.
wd_template() {
    cut_states "$1" worktree_discipline_check pr_finalization \
        | sed 's|default_template: ../../work-on/koto-templates/work-on.md|default_template: child.md|' > "$2.states"
    {
        printf '%s\n' '---' 'name: execute' 'version: "1.0"' 'initial_state: facts' 'variables:' \
            '  PLAN_DOC:' '    required: true' '  PLAN_SLUG:' '    required: true' '  PLUGIN_ROOT:' '    required: true' 'states:' \
            '  facts:' '    gates:' '      drift:' '        type: context-exists' '        key: drift_facts.json' \
            '      intent:' '        type: context-exists' '        key: plan_intent.md' '    transitions:' \
            '      - target: worktree_discipline_check' '        when:' '          gates.drift.exists: true' \
            '          gates.intent.exists: true'
        cat "$2.states"
        printf '%s\n' '  pr_finalization:' '    terminal: true' '  escalate:' '    terminal: true' '    failure: true' \
            '  done_blocked:' '    terminal: true' '    failure: true' '    result:' '      outcome: "${context.outcome}"' \
            '      step: "${context.step}"' '---'
        for s in facts $(sed -n 's/^  \([a-z_]*\):$/\1/p' "$2.states") pr_finalization escalate done_blocked; do
            printf '\n## %s\n\nThe %s state.\n' "$s" "$s"
        done
    } > "$2"
}
PRE_WHY=""
if ! command -v git > /dev/null; then
    PRE_WHY="git is not on PATH"
elif ! git -C "$REPO" log --format=%H -S'  decide_first:' -- skills/execute/koto-templates/execute.md > "$T/pin.log" 2> "$T/pin.err"; then
    PRE_WHY="git log failed: $(cat "$T/pin.err")"
elif [ -z "$(sed -n '$p' "$T/pin.log")" ]; then
    PRE_WHY="no commit in this clone adds decide_first to execute.md"
elif ! git -C "$REPO" show "$(sed -n '$p' "$T/pin.log")^:skills/execute/koto-templates/execute.md" > "$T/execute-pre.md" 2> "$T/pin.err"; then
    PRE_WHY="execute.md before decide_first is not readable: $(cat "$T/pin.err")"
elif grep -q '^  decide_first:' "$T/execute-pre.md"; then
    PRE_WHY="the template before the commit that added decide_first already holds it"
fi

if [ -n "$PRE_WHY" ]; then
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        fail "no covered exit and an old session: $PRE_WHY"
    else
        echo "SKIP: no covered exit and an old session: $PRE_WHY"
    fi
else
    wd_template "$T/execute-pre.md" "$T/wd-pre.md"
    wd_template "$EXEC_MD" "$T/wd-head.md"
    for t in wd-pre.md wd-head.md; do
        koto template compile "$T/$t" > /dev/null 2> "$T/compile.err" || fail "$t does not compile: $(cat "$T/compile.err")"
    done
    # A shirabe that logs each call, first on PATH for these runs only.
    mkdir -p "$T/logbin"
    printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' \"\$*\" >> \"$T/shirabe.log\"" "exec \"$SHIRABE\" \"\$@\"" > "$T/logbin/shirabe"
    chmod +x "$T/logbin/shirabe"
    : > "$T/shirabe.log"
    SAVED_PATH=$PATH
    export PATH="$T/logbin:$PATH"
    printf '%s\n' '[{"name":"a","waits_on":[]},{"name":"b","waits_on":[]}]' > "$T/PLAN-seq.md.tasks"
    : > "$T/PLAN-seq.md"
    jq -n --slurpfile t "$T/PLAN-seq.md.tasks" '{tasks: $t[0]}' > "$T/seq-tasks.json"
    # facts <session>: the two keys drift_facts writes in the template.
    facts() {
        printf '{"changed":["src/api.go"]}\n' | koto context add "$1" drift_facts.json > /dev/null 2> "$T/ctx.err" \
            && printf 'Build the cache on the existing API.\n' | koto context add "$1" plan_intent.md > /dev/null 2> "$T/ctx.err" \
            || fail "koto context add in $1: $(cat "$T/ctx.err")"
    }
    # seq_walk <session> <template>: the state after each tick, in $SEQ.
    seq_walk() {
        SEQ=""
        koto init "$1" --template "$2" --var "PLAN_DOC=$T/PLAN-seq.md" --var PLAN_SLUG=seq --var "PLUGIN_ROOT=$P" > /dev/null 2> "$T/init.err" \
            || { fail "koto init $1: $(cat "$T/init.err")"; return 1; }
        facts "$1"
        tick "$1"; SEQ="$SEQ $(state "$1")"
        submit "$1" '{"impact":"informational"}'; SEQ="$SEQ $(state "$1")"
        tick "$1" "$T/seq-tasks.json"; SEQ="$SEQ $(state "$1")"
        for c in a b; do
            tick "$1.$c"; SEQ="$SEQ $c:$(state "$1.$c")"
            submit "$1.$c" '{"impl":"done"}'; SEQ="$SEQ $c:$(state "$1.$c")"
        done
        tick "$1"; SEQ="$SEQ $(state "$1")"
    }
    if seq_walk seq-pre "$T/wd-pre.md"; then
        SEQ_PRE=$SEQ
        if seq_walk seq-head "$T/wd-head.md"; then
            echo "states, tick by tick:$SEQ_PRE"
            eq "a run with no covered exit lands in the same state at every tick before and after decide_first" "$SEQ_PRE" "$SEQ"
            case "$SEQ" in *" pr_finalization") pass "and reaches pr_finalization" ;; *) fail "the walk ended at [$SEQ]" ;; esac
        fi
    fi
    if grep -q '^question' "$T/shirabe.log"; then
        fail "a run with no covered exit called shirabe question: $(grep '^question' "$T/shirabe.log")"
    else
        pass "a run with no covered exit makes no shirabe question call"
    fi

    # An old session: opened on the earlier template, ticked with the
    # branch's scripts, it stops where it did.
    if koto init old --template "$T/wd-pre.md" --var "PLAN_DOC=$T/PLAN-seq.md" --var PLAN_SLUG=seq --var "PLUGIN_ROOT=$P" > /dev/null 2> "$T/init.err"; then
        facts old
        tick old
        submit old '{"impact":"intent-changing","rationale":"main removed the interface the PLAN builds on"}'
        eq "a session on the earlier template reaches done_blocked on intent-changing" done_blocked "$(state old)"
        eq "with step execute:re-evaluation" execute:re-evaluation "$(koto context get old step 2> "$T/ctx.err")"
        koto context exists old decide_origin > /dev/null 2>&1 && fail "the old session arrived at decide_first" || pass "and never arrives at decide_first"
    else
        fail "koto init old from the earlier template: $(cat "$T/init.err")"
    fi
    export PATH=$SAVED_PATH
fi

# --- the walk -------------------------------------------------------------------------

RUN=execute-walk
printf '%s\n' '[{"name":"a","waits_on":[]},{"name":"b","waits_on":[]},{"name":"c","waits_on":["a"]}]' > "$T/PLAN-walk.md.tasks"
: > "$T/PLAN-walk.md"
jq -n --slurpfile t "$T/PLAN-walk.md.tasks" '{tasks: $t[0]}' > "$T/walk-tasks.json"
koto init "$RUN" --template "$T/execute.md" --var "PLAN_DOC=$T/PLAN-walk.md" --var PLAN_SLUG=walk --var "PLUGIN_ROOT=$P" > /dev/null 2> "$T/init.err" \
    || { fail "koto init $RUN: $(cat "$T/init.err")"; finish; }
tick "$RUN" "$T/walk-tasks.json"
eq "the batch is spawned and waits on its children" spawn_and_await "$(state "$RUN")"

tick "$RUN.a"
eq "a starts at implementation" implementation "$(state "$RUN.a")"
ask "$RUN.a"
QA=$Q
tick "$RUN.b"
finish_child "$RUN.b"
park mark "$RUN" --child "$RUN.a"
eq "park.sh mark parks a's step on its question" "0:$QA" "$PARK_RC:$(cat "$T/park.out")"

tick "$RUN"
eq "with a parked and c waiting on it, the run ends at done_waiting" done_waiting "$(state "$RUN")"
eq "done_waiting's result names a's question" "$QA" "$(koto status "$RUN" | jq -r '.result.payload.question // empty')"
c_state=$(state "$RUN.c")
case "$c_state" in
    ''|skipped_due_to_dep_failure) pass "c never started while a was parked ($c_state)" ;;
    *) fail "c stands at $c_state while a is parked" ;;
esac

owner_answers "$QA"

# Re-invocation: execute-open.sh rewinds a run at done_waiting once its
# questions are closed.
koto rewind "$RUN" > "$T/rewind.out" 2> "$T/rewind.err" || fail "koto rewind $RUN: $(cat "$T/rewind.out" "$T/rewind.err")"
eq "the rewind lands at waiting_record, the state the last tick chained through" waiting_record "$(state "$RUN")"
tick "$RUN"
eq "waiting_record finds no open question and returns to spawn_and_await" spawn_and_await "$(state "$RUN")"
eq "waiting_questions reads none" none "$(koto context get "$RUN" waiting_questions)"
eq "the batch holds while a's key stands on an answered question" spawn_and_await "$(state "$RUN")"

park clear "$RUN" a
[ "$PARK_RC" -eq 1 ] && pass "park.sh clear refuses before any decision cites the answer" \
    || fail "park.sh clear before a citation: exit $PARK_RC: $(cat "$T/park.out" "$T/park.err")"

jq -n '{retry_failed: {children: ["a"], include_skipped: true}}' > "$T/retry.json"
tick "$RUN" "$T/retry.json"
[ "$TICK_RC" -eq 0 ] && pass "retry_failed with include_skipped is accepted at the batch" \
    || fail "retry_failed: exit $TICK_RC: $(cat "$T/tick.out" "$T/tick.err")"
tick "$RUN" "$T/walk-tasks.json"
[ "$TICK_RC" -eq 0 ] && pass "the same tasks are submitted again" \
    || fail "the tasks again: exit $TICK_RC: $(cat "$T/tick.out" "$T/tick.err")"
eq "a is back at its first state" entry "$(state "$RUN.a")"
eq "a keeps its decide_question" "$QA" "$(koto context get "$RUN.a" decide_question)"

tick "$RUN.a"
eq "a resumes at resume_waiting and holds until its attempt cites the answer" resume_waiting "$(state "$RUN.a")"
"$SHIRABE" question attempt --in "$RUN.a" --what "cache store" --result decided --chosen SQLite --basis "$OWNER_ANS" --state implementation:1 > "$T/att.out" 2> "$T/att.err" \
    || fail "a's deciding attempt: $(cat "$T/att.out" "$T/att.err")"
tick "$RUN.a"
eq "once cited, a goes back to implementation" implementation "$(state "$RUN.a")"
finish_child "$RUN.a"

park clear "$RUN" a
eq "park.sh clear removes a's key once a cites the answer" 0 "$PARK_RC"
koto context exists "$RUN" parked/a > /dev/null 2>&1
eq "parked/a is gone" 1 "$?"

tick "$RUN"
tick "$RUN.c"
eq "c starts once a is done" implementation "$(state "$RUN.c")"
finish_child "$RUN.c"
tick "$RUN"
eq "every step landed: the batch reaches pr_finalization" pr_finalization "$(state "$RUN")"

# --- the refusals ---------------------------------------------------------------------

RUN=execute-refuse
printf '%s\n' '[{"name":"x","waits_on":[]},{"name":"y","waits_on":[]}]' > "$T/PLAN-refuse.md.tasks"
: > "$T/PLAN-refuse.md"
jq -n --slurpfile t "$T/PLAN-refuse.md.tasks" '{tasks: $t[0]}' > "$T/refuse-tasks.json"
koto init "$RUN" --template "$T/execute.md" --var "PLAN_DOC=$T/PLAN-refuse.md" --var PLAN_SLUG=refuse --var "PLUGIN_ROOT=$P" > /dev/null 2> "$T/init.err" \
    || { fail "koto init $RUN: $(cat "$T/init.err")"; finish; }
tick "$RUN" "$T/refuse-tasks.json"
for s in x y; do
    tick "$RUN.$s"
    ask "$RUN.$s"
    eval "Q_$s=\$Q"
    park mark "$RUN" --child "$RUN.$s"
done
tick "$RUN"
eq "with both parked, the run ends at done_waiting" done_waiting "$(state "$RUN")"

# answered_by <answerer> <child> <identity> <label>
answered_by() {
    koto decisions answer --in="$1" --text=SQLite --by=session -- "$2" "${3##*/}" > "$T/ans.out" 2> "$T/ans.err"
    if [ "$?" -ne 0 ]; then
        pass "$4: koto refuses the answer itself ($(head -c 200 "$T/ans.err"))"
        return 1
    fi
    return 0
}
REFUSED=""
answered_by "$RUN" "$RUN.x" "$Q_x" "the run's own answer to its step's question" || REFUSED="$REFUSED x"
answered_by stranger "$RUN.y" "$Q_y" "an unrelated session's answer" || REFUSED="$REFUSED y"

koto rewind "$RUN" > /dev/null 2> "$T/rewind.err" || fail "koto rewind $RUN: $(cat "$T/rewind.err")"
tick "$RUN"
for s in x y; do
    case " $REFUSED " in *" $s "*) continue ;; esac
    park list "$RUN"
    grep -q "^$s .* unauthorized " "$T/park.out" && pass "park.sh list names $s's answer unauthorized" \
        || fail "park.sh list: $(cat "$T/park.out" "$T/park.err")"
    park clear "$RUN" "$s"
    if [ "$PARK_RC" -eq 1 ] && grep -q "carries no authority" "$T/park.err" "$T/park.out"; then
        pass "park.sh clear refuses $s's answer: no authority"
    else
        fail "park.sh clear $s: exit $PARK_RC: $(cat "$T/park.out" "$T/park.err")"
    fi
done
case "$REFUSED" in
    *x*y*) ;;
    *)
        park cited "$RUN"
        eq "park.sh cited finds no answer with authority" 1 "$PARK_RC"
        ;;
esac
eq "the batch holds on answers without authority" spawn_and_await "$(state "$RUN")"

finish
