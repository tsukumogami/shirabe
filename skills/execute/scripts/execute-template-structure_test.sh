#!/usr/bin/env bash
# execute-template-structure_test.sh — the merge step's shape, read from the
# compiled template
# Part of the execute skill
#
# The guarantees of /execute's merge step are properties of execute.md's graph,
# so this reads the graph itself: `koto template compile` turns the template into
# JSON, and each assertion is a jq query over it. No field is parsed out of YAML
# by hand, so a comment or a reflowed line can't fool it.
#
# It asserts, on the shipped template:
#
#   merge_attempt has no default_action and carries the merge_intent gate,
#     `test "{{MERGE}}" = true`, overridable: false, whose failure edge
#     (exit_code 1) targets ready_awaiting_merge and whose other edges all
#     require it to pass; its merge_exec enum adds squash-message, whose edge
#     (gated on merge_intent 0) ends ready_awaiting_merge with the literal
#     reason merge-refused:squash-message; its directive builds the message
#     with merge-message.sh and passes it as merge-exec.sh's fourth argument
#   every merge_route and merge_confirm gate is a context-matches gate declared
#     overridable: false, and merge_confirm has no command gate
#   no transition targets the legacy `done`
#   merged's only incoming edge is from merge_confirm
#   no context_assignments block writes home_pr
#   escalate_dirty_merge_state still routes to done_blocked, ci_monitor's
#     DIRTY edge (owned_merge_state_clean failing) targets it, and ci_monitor's
#     green edge (no evidence) and failing_fixed edge target merge_readiness
#   ci_monitor's one edge with owned_pr_merged at 0 targets merge_readiness on
#     that gate and the lookup alone, every other edge with the lookup at 0
#     needs owned_pr_merged at 1, and the gate is overridable: false (#917)
#   no default_action command holds `${context.` (koto never substitutes it)
#   every edge into a terminal assigns `outcome` as a literal, no assignment
#     reads `${context.`, and a `step` or `reason` assignment is a literal
#   every terminal declares the result map, with step and reason read from
#     context
#   MERGE and PAUSE_BEFORE_FINALIZE are values [true, false], default false,
#     rebind: true; PLUGIN_ROOT carries the absolute-path pattern; PLAN_DOC and
#     PLAN_SLUG are not rebindable
#   worktree_sync merges origin/main in, nothing runs `git rebase`, and its
#     gate tests ancestry with no merge in progress, through
#     check-branch-output.sh --synced
#   ci_monitor caps CI repair at 3 fix pushes and doesn't load phase-6-pr.md;
#     pr_finalization points at pr-body-conformance.md rather than restating it
#   no directive names current-context.md, and spawn_and_await carries earlier
#     children's summaries through `koto context get <child> summary.md`, one
#     read per child, saying why the count is small; no skills/execute file
#     outside evals names current-context.md
#   settled_branch_record's own prose names SETTLED_BRANCH without braces and
#     says why (a braced mention there stops the failure-path tick with
#     capture_unset)
#   REVIEW_FLOOR and REVIEW_CEILING are optional, carry the level pattern
#     ^(light|standard|full)?$ and are rebind, as MERGE is
#   the spawn's jq, taken from spawn_and_await's directive with the
#     variables written in as koto renders them, builds tasks that each carry
#     the run's PLAN_DOC, and REVIEW_FLOOR and REVIEW_CEILING when they are
#     set, and exactly the tasks it built before (SHARED_BRANCH, PLUGIN_ROOT
#     and PLAN_DOC added, nothing else) when they are empty; one set and one
#     empty adds only the set one
#   VERIFICATION (local by default, or hosted-ci) and
#     VERIFICATION_DEFERRAL_REASON are optional and not rebind, as in
#     work-on.md; the spawn gives every child task both when VERIFICATION is
#     hosted-ci and neither when it is local; pr_finalization's two forward
#     edges need deferral_recorded at 0, and its command passes both
#     variables to shared-deferral-record.sh
#
# and, so the checks are known to bite, that each fails on a mutated copy: an
# assignment writing home_pr, an overridable merge_intent gate, an overridable
# owned_pr_merged gate, a merged edge that also needs green CI, an edge into
# `done`, a second edge into `merged`, and a `${context.` in a default action.
#
# HANDOFF_ROUTE=work-on runs only the sections on the hand-off to /work-on:
# the tasks spawn_and_await builds for its work-on.md children, and the
# carry-forward check on their summaries. The template is compiled either
# way. With HANDOFF_ROUTE unset every section runs. scripts/check-handoff.sh
# sets it for its routes check.
#
# Usage: [HANDOFF_ROUTE=work-on] execute-template-structure_test.sh
# Exit codes: 0 all pass (or koto absent: a loud SKIP), 1 a failure, or a
# HANDOFF_ROUTE this suite has no sections for

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

ROUTE=${HANDOFF_ROUTE:-}
case "$ROUTE" in
    ''|work-on) ;;
    *) echo "FAIL: HANDOFF_ROUTE=$ROUTE: this suite's only route is work-on"; exit 1 ;;
esac
# runs <route>: true when a section on <route> (empty for one on no hand-off)
# runs under HANDOFF_ROUTE.
runs() { [ -z "$ROUTE" ] || [ "$ROUTE" = "$1" ]; }

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/execute.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- the template was not compiled, so nothing was checked"
    exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/execute-structure-test.XXXXXX") || exit 1
ktg_on_exit 'rm -rf "$WORK"'
export HOME="$WORK/home"
mkdir -p "$HOME"

compile() { # compile <template> -> prints the compiled JSON path, or nothing
    koto template compile "$1" 2>/dev/null | tail -1
}

PLUGIN_ROOT_PATTERN='^/([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+|\.)?(/([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+|\.)?)*$'

# holds <compiled json> <jq filter that is true when the property holds>
holds() { jq -e "$2" "$1" >/dev/null 2>&1; }

# The named checks. Each is a jq expression over the compiled template.
CHECKS=(
"merge_attempt has no default_action|.states.merge_attempt.default_action == null"
"merge_attempt carries the non-overridable merge_intent gate|.states.merge_attempt.gates.merge_intent == {type: \"command\", command: \"test \\\"{{MERGE}}\\\" = true\", overridable: false}"
"merge_intent's failure edge targets ready_awaiting_merge|[.states.merge_attempt.transitions[] | select(.when == {\"gates.merge_intent.exit_code\": 1})] | length == 1 and .[0].target == \"ready_awaiting_merge\""
"every other merge_attempt edge requires merge_intent to pass|[.states.merge_attempt.transitions[] | select(.when != {\"gates.merge_intent.exit_code\": 1}) | .when[\"gates.merge_intent.exit_code\"] == 0] | length > 0 and all"
"merge_attempt's squash-message edge, gated on merge_intent 0, ends ready_awaiting_merge with the literal reason|[.states.merge_attempt.transitions[] | select(.when == {\"gates.merge_intent.exit_code\": 0, \"merge_exec\": \"squash-message\"})] | length == 1 and .[0].target == \"ready_awaiting_merge\" and .[0].context_assignments.reason == \"merge-refused:squash-message\" and .[0].context_assignments.outcome == \"ready-awaiting-merge\""
"merge_exec accepts called, refused and squash-message|.states.merge_attempt.accepts.merge_exec.values == [\"called\",\"refused\",\"squash-message\"]"
"merge_attempt's directive builds the message with merge-message.sh and passes it as merge-exec.sh's fourth argument|.states.merge_attempt.directive | (contains(\"scripts/merge-message.sh \\\"\$REPO\\\" \\\"\${HOME_PR##*/}\\\"\") and contains(\"scripts/merge-exec.sh \\\"\$REPO\\\" \\\"\${HOME_PR##*/}\\\" \\\"\$EXPECTED\\\" \\\"\$MSG\\\"\") and contains(\"LINE=merge-refused:squash-message\"))"
"every merge_route gate is a non-overridable context-matches gate|[.states.merge_route.gates[] | (.type == \"context-matches\" and .overridable == false)] | length > 0 and all"
"every merge_confirm gate is a non-overridable context-matches gate|[.states.merge_confirm.gates[] | (.type == \"context-matches\" and .overridable == false)] | length > 0 and all"
"merge_confirm has no command gate|[.states.merge_confirm.gates[] | select(.type == \"command\")] | length == 0"
"merge_confirm's confirm read is a default action running record-merge-verdict.sh --confirm|(.states.merge_confirm.default_action.command // \"\") | test(\"record-merge-verdict\\\\.sh --confirm \")"
"merge_readiness's default action runs record-merge-verdict.sh with {{MERGE}}|(.states.merge_readiness.default_action.command // \"\") | (test(\"record-merge-verdict\\\\.sh \") and test(\"--merge \\\"\\\\{\\\\{MERGE\\\\}\\\\}\\\"\"))"
"no transition targets done|[.states[] | (.transitions // [])[] | select(.target == \"done\")] | length == 0"
"merged's only incoming edge is from merge_confirm|[.states | to_entries[] | .key as \$s | (.value.transitions // [])[] | select(.target == \"merged\") | \$s] | . == [\"merge_confirm\"]"
"no context_assignments block writes home_pr|[.states[] | (.transitions // [])[] | (.context_assignments // {}) | has(\"home_pr\")] | any | not"
"escalate_dirty_merge_state routes to done_blocked|[.states.escalate_dirty_merge_state.transitions[].target] == [\"done_blocked\"]"
"ci_monitor's DIRTY edge still targets escalate_dirty_merge_state|[.states.ci_monitor.transitions[] | select(.when[\"gates.owned_merge_state_clean.exit_code\"] == 1) | .target] == [\"escalate_dirty_merge_state\"]"
"ci_monitor's green and failing_fixed edges target merge_readiness|[.states.ci_monitor.transitions[] | select((.when.ci_outcome == null and .when[\"gates.owned_ci_passing.exit_code\"] == 0) or .when.ci_outcome == \"failing_fixed\") | .target] | length == 2 and all(. == \"merge_readiness\")"
"ci_monitor routes a MERGED owned PR to merge_readiness on the lookup and owned_pr_merged alone|[.states.ci_monitor.transitions[] | select(.when[\"gates.owned_pr_merged.exit_code\"] == 0)] | length == 1 and .[0].target == \"merge_readiness\" and .[0].when == {\"gates.monitor_owned_pr.exit_code\": 0, \"gates.owned_pr_merged.exit_code\": 0}"
"every other ci_monitor edge with the lookup at 0 needs owned_pr_merged at 1|[.states.ci_monitor.transitions[] | select(.when[\"gates.monitor_owned_pr.exit_code\"] == 0 and .when[\"gates.owned_pr_merged.exit_code\"] != 0) | .when[\"gates.owned_pr_merged.exit_code\"] == 1] | length > 0 and all"
"owned_pr_merged is a non-overridable command gate|.states.ci_monitor.gates.owned_pr_merged | (.type == \"command\" and .overridable == false)"
"no default_action command holds \${context.|[.states[] | (.default_action.command // \"\") | contains(\"\${context.\")] | any | not"
"every edge into a terminal assigns a literal outcome|[.states as \$all | .states[] | (.transitions // [])[] | select(\$all[.target].terminal == true) | ((.context_assignments.outcome // \"\") | (length > 0 and (contains(\"\${\") | not) and (contains(\"{{\") | not)))] | length > 0 and all"
"no assignment reads \${context.|[.states[] | (.transitions // [])[] | (.context_assignments // {}) | .[] | contains(\"\${context.\")] | any | not"
"step and reason are assigned only as literals|[.states[] | (.transitions // [])[] | (.context_assignments // {}) | to_entries[] | select(.key == \"step\" or .key == \"reason\") | .value | (contains(\"\${\") or contains(\"{{\"))] | any | not"
"every terminal declares the full result map|[.states[] | select(.terminal == true) | (.result // {}) | keys == [\"outcome\",\"pr\",\"reason\",\"repos\",\"resume\",\"step\",\"waiting\"]] | length >= 5 and all"
"every terminal reads step and reason from context|[.states[] | select(.terminal == true) | .result.step == \"\${context.step}\" and .result.reason == \"\${context.reason}\"] | all"
"the legacy done terminal's outcome is ready-awaiting-merge|.states.done.result.outcome == \"ready-awaiting-merge\""
"MERGE is values [true, false], default false, rebind|.variables.MERGE | (.values == [\"true\",\"false\"] and .default == \"false\" and .rebind == true)"
"PAUSE_BEFORE_FINALIZE is values [true, false], rebind|.variables.PAUSE_BEFORE_FINALIZE | (.values == [\"true\",\"false\"] and .rebind == true)"
"PLAN_DOC and PLAN_SLUG are not rebindable|(.variables.PLAN_DOC.rebind // false) == false and (.variables.PLAN_SLUG.rebind // false) == false"
"PLAN_SLUG carries ^[a-z0-9-]+\$|.variables.PLAN_SLUG.pattern == \"^[a-z0-9-]+\$\""
"REVIEW_FLOOR and REVIEW_CEILING are optional, the level pattern, rebind|[.variables.REVIEW_FLOOR, .variables.REVIEW_CEILING] | all((.required // false) == false and .pattern == \"^(light|standard|full)?\$\" and .rebind == true)"
"VERIFICATION is optional, local by default, values [local, hosted-ci], not rebind|.variables.VERIFICATION | ((.required // false) == false and .default == \"local\" and .values == [\"local\",\"hosted-ci\"] and (.rebind // false) == false)"
"VERIFICATION_DEFERRAL_REASON is optional, starts with a letter or digit, not rebind|.variables.VERIFICATION_DEFERRAL_REASON | ((.required // false) == false and .pattern == \"^([a-zA-Z0-9].*)?\$\" and (.rebind // false) == false)"
"pr_finalization's two forward edges need deferral_recorded at 0|[.states.pr_finalization.transitions[] | select(.target == \"paused_for_review\" or .target == \"plan_completion\") | .when[\"gates.deferral_recorded.exit_code\"] == 0] | (length == 2 and all)"
"deferral_recorded runs shared-deferral-record.sh with the run's two variables|(.states.pr_finalization.gates.deferral_recorded.command // \"\") | (contains(\"/skills/execute/scripts/shared-deferral-record.sh\\\" --session execute-\") and contains(\"--verification \\\"\") and contains(\"--reason \\\"\"))"
"worktree_sync merges origin/main in|.states.worktree_sync.default_action.command == \"git merge --no-edit origin/main\""
"no default action or gate runs git rebase|[.states[] | ((.default_action.command // \"\"), ((.gates // {})[] | (.command // \"\"))) | contains(\"git rebase\")] | any | not"
"worktree_sync's gate tests ancestry with no merge in progress|(.states.worktree_sync.gates.current_with_main.command // \"\") | (contains(\"/skills/work-on/scripts/check-branch-output.sh\\\" --synced\") and (contains(\"--base-ref\") | not))"
"ci_monitor caps CI repair at 3 fix pushes, then failing_unresolvable|.states.ci_monitor.directive | (contains(\"capped at 3 fix pushes\") and contains(\"failing_unresolvable\") and contains(\"Never stop to ask the user\"))"
"ci_monitor does not load /work-on's phase-6-pr.md|.states.ci_monitor.directive | contains(\"phase-6-pr.md\") | not"
"pr_finalization points at pr-body-conformance.md instead of restating it|.states.pr_finalization.directive | (contains(\"references/pr-body-conformance.md\") and (contains(\"exactly one \`---\` separator\") | not))"
"no directive tells the agent to build current-context.md|[.states[] | (.directive // \"\") | contains(\"current-context\")] | any | not"
"spawn_and_await carries earlier summaries through koto context get, read once per child|.states.spawn_and_await.directive | (contains(\"koto context get <child> summary.md\") and contains(\"once per child\") and contains(\"logged and uploaded as an event\"))"
"settled_branch_record's prose names SETTLED_BRANCH without braces|.states.settled_branch_record | (((.directive // \"\") + (.details // \"\")) | (contains(\"SETTLED_BRANCH\") and contains(\"without braces here on purpose\") and (contains(\"{{SETTLED_BRANCH}}\") | not)))"
)

run_checks() { # run_checks <compiled json> -> prints the labels that fail
    local json="$1" entry label filter
    for entry in "${CHECKS[@]}"; do
        label="${entry%%|*}"
        filter="${entry#*|}"
        holds "$json" "$filter" || printf '%s\n' "$label"
    done
    # The PLUGIN_ROOT pattern is compared as a string, outside jq's escaping.
    if [ "$(jq -r '.variables.PLUGIN_ROOT.pattern // ""' "$json")" != "$PLUGIN_ROOT_PATTERN" ]; then
        printf '%s\n' "PLUGIN_ROOT carries the absolute-path pattern"
    fi
}

# --- the shipped template ------------------------------------------------------
#
# Compiled under every route; its checks are on no hand-off, so they run only
# with HANDOFF_ROUTE unset.

SHIPPED=$(compile "$TEMPLATE")
if [ -z "$SHIPPED" ] || [ ! -f "$SHIPPED" ]; then
    fail "execute.md does not compile"
    koto template compile "$TEMPLATE" 2>&1 | tail -3
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    exit 1
fi
if runs ""; then
    FAILED=$(run_checks "$SHIPPED")
    for entry in "${CHECKS[@]}" "PLUGIN_ROOT carries the absolute-path pattern|"; do
        label="${entry%%|*}"
        if grep -qxF "$label" <<<"$FAILED"; then
            fail "$label"
        else
            pass "$label"
        fi
    done
fi

# --- the tasks the spawn builds --------------------------------------------------
#
# The spawn's jq line is read from the compiled directive, the PLAN path and
# the bound variables are written in the way koto renders {{VAR}} (empty when
# unset), and the line is run on a task array of plan-to-tasks.sh's shape.
# These are the tasks of the work-on.md children: they run under
# HANDOFF_ROUTE=work-on too.

SPAWN_LINE=$(jq -r '.states.spawn_and_await.directive' "$SHIPPED" | grep '^TASKS_WITH_BRANCH=')
if [ "$(printf '%s\n' "$SPAWN_LINE" | grep -c .)" -ne 1 ]; then
    fail "spawn_and_await's directive has one TASKS_WITH_BRANCH line (found: [$SPAWN_LINE])"
else
    pass "spawn_and_await's directive has one TASKS_WITH_BRANCH line"
fi
FIXTURE_TASKS='[{"name":"a","vars":{"ISSUE_SOURCE":"plan_outline","ARTIFACT_PREFIX":"a","ISSUE_TYPE":"code"},"waits_on":[]},{"name":"b","vars":{"ISSUE_SOURCE":"plan_outline","ARTIFACT_PREFIX":"b","ISSUE_TYPE":"docs"},"waits_on":["a"]}]'
# spawn_tasks <floor> <ceiling> [<verification> <reason>] -> the task array the
# rendered line builds. VERIFICATION renders as its default, local, when not
# given, as koto renders an unset variable with a default.
spawn_tasks() {
    local line
    line=$(printf '%s' "$SPAWN_LINE" | sed -e "s|{{PLAN_DOC}}|docs/plans/PLAN-x.md|g" \
        -e "s/{{REVIEW_FLOOR}}/$1/g" -e "s/{{REVIEW_CEILING}}/$2/g" \
        -e "s/{{VERIFICATION}}/${3:-local}/g" -e "s/{{VERIFICATION_DEFERRAL_REASON}}/${4:-}/g")
    TASKS="$FIXTURE_TASKS" SETTLED_BRANCH=impl/x CLAUDE_PLUGIN_ROOT=/plugin \
        bash -c "$line"' && printf "%s" "$TASKS_WITH_BRANCH"'
}
spawn_eq() { # spawn_eq <label> <want> <got>
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: want [$2], got [$3]"; fi
}
# Every child's plan_validation reads its step from PLAN_DOC, and step_detail
# refuses a child without one (#1160), so every task carries the run's path.
GOT=$(spawn_tasks "" "" | jq -c '[.[] | .vars.PLAN_DOC]')
spawn_eq "every child task carries the run's PLAN_DOC" '["docs/plans/PLAN-x.md","docs/plans/PLAN-x.md"]' "$GOT"
GOT=$(spawn_tasks standard full | jq -c '[.[] | [.vars.REVIEW_FLOOR, .vars.REVIEW_CEILING]]')
spawn_eq "a bound run: every child task carries REVIEW_FLOOR and REVIEW_CEILING" \
    '[["standard","full"],["standard","full"]]' "$GOT"
GOT=$(spawn_tasks "" "" | jq -c '.')
WANT=$(printf '%s' "$FIXTURE_TASKS" | jq -c '[.[] | .vars.SHARED_BRANCH = "impl/x" | .vars.PLUGIN_ROOT = "/plugin" | .vars.PLAN_DOC = "docs/plans/PLAN-x.md"]')
spawn_eq "an unbounded run: the tasks are exactly the ones built before the bound existed" "$WANT" "$GOT"
GOT=$(spawn_tasks light "" | jq -c '[.[] | .vars | [has("REVIEW_FLOOR"), has("REVIEW_CEILING"), .REVIEW_FLOOR]]')
spawn_eq "a floor without a ceiling: only REVIEW_FLOOR is set" '[[true,false,"light"],[true,false,"light"]]' "$GOT"
GOT=$(spawn_tasks "" full | jq -c '[.[] | .vars | [has("REVIEW_FLOOR"), .REVIEW_CEILING]]')
spawn_eq "a ceiling without a floor: only REVIEW_CEILING is set" '[[false,"full"],[false,"full"]]' "$GOT"
# The verification deferral (#1017): hosted-ci gives every child both
# variables; local, the default, gives none, so the tasks are the old ones.
GOT=$(spawn_tasks "" "" hosted-ci "host is in a measurement window until 02:40Z" \
    | jq -c '[.[] | [.vars.VERIFICATION, .vars.VERIFICATION_DEFERRAL_REASON]]')
spawn_eq "a deferred run: every child task carries VERIFICATION=hosted-ci and the reason" \
    '[["hosted-ci","host is in a measurement window until 02:40Z"],["hosted-ci","host is in a measurement window until 02:40Z"]]' "$GOT"
GOT=$(spawn_tasks "" "" local "" | jq -c '.')
spawn_eq "a run with VERIFICATION=local: the tasks are exactly the ones built before the deferral existed" "$WANT" "$GOT"
GOT=$(spawn_tasks standard "" hosted-ci "CI only" | jq -c '[.[] | .vars | [.REVIEW_FLOOR, .VERIFICATION, .VERIFICATION_DEFERRAL_REASON, .SHARED_BRANCH]]')
spawn_eq "a bound and a deferral together: each child carries both" \
    '[["standard","hosted-ci","CI only","impl/x"],["standard","hosted-ci","CI only","impl/x"]]' "$GOT"

# --- each check bites -----------------------------------------------------------
#
# A copy of the template, changed in one place, must fail the check that is
# about that place. The copy sits beside a link to /work-on so its relative
# child-template path still resolves. On no hand-off: only with HANDOFF_ROUTE
# unset.

if runs ""; then
    MUT_DIR="$WORK/mut/skills/execute/koto-templates"
    mkdir -p "$MUT_DIR"
    ln -s "$SKILL_DIR/../work-on" "$WORK/mut/skills/work-on"

    mutate() { # mutate <label> <expected failing check> <perl substitution>
        local label="$1" want="$2" sub="$3" json failed
        perl -0pe "$sub" "$TEMPLATE" > "$MUT_DIR/execute.md"
        if cmp -s "$TEMPLATE" "$MUT_DIR/execute.md"; then
            fail "mutation [$label] did not change the template; the substitution no longer matches"
            return
        fi
        # --allow-legacy-gates skips only koto's reachability check, which an
        # overridable merge_intent gate would fail on its own; the mutation is
        # about what this suite catches, not what the compiler does.
        json=$(koto template compile --allow-legacy-gates "$MUT_DIR/execute.md" 2>/dev/null | tail -1)
        if [ -z "$json" ] || [ ! -f "$json" ]; then
            fail "mutation [$label] does not compile, so it proves nothing"
            koto template compile "$MUT_DIR/execute.md" 2>&1 | tail -2
            return
        fi
        failed=$(run_checks "$json")
        if grep -qxF "$want" <<<"$failed"; then
            pass "the check fails on a copy with $label"
        else
            fail "a copy with $label passed [$want]"
        fi
    }

    mutate "an assignment writing home_pr from evidence" \
        "no context_assignments block writes home_pr" \
        's/(          merge_exec: refused\n        context_assignments:\n)/$1          home_pr: "\${evidence.merge_line}"\n/'
    mutate "an overridable merge_intent gate" \
        "merge_attempt carries the non-overridable merge_intent gate" \
        's/(command: .test "\{\{MERGE\}\}" = true.\n        overridable: )false/${1}true/'
    mutate "ci_monitor's green edge back on done" \
        "no transition targets done" \
        's/(      - target: )merge_readiness(\n        when:\n          gates.monitor_owned_pr.exit_code: 0\n          gates.owned_ci_passing.exit_code: 0)/${1}done$2/'
    mutate "an overridable owned_pr_merged gate" \
        "owned_pr_merged is a non-overridable command gate" \
        's/(      owned_pr_merged:\n        type: command\n        overridable: )false/${1}true/'
    mutate "ci_monitor's merged edge needing green CI" \
        "ci_monitor routes a MERGED owned PR to merge_readiness on the lookup and owned_pr_merged alone" \
        's/(          gates.monitor_owned_pr.exit_code: 0\n          gates.owned_pr_merged.exit_code: 0\n)/$1          gates.owned_ci_passing.exit_code: 0\n/'
    mutate "a second edge into merged" \
        "merged's only incoming edge is from merge_confirm" \
        's/(      - target: )ready_awaiting_merge(\n        when:\n          gates.merge_intent.exit_code: 0\n          merge_exec: refused)/${1}merged$2/'
    mutate "a \${context. in a default action" \
        "no default_action command holds \${context." \
        's/--head-branch "\$\(koto context get execute-\{\{PLAN_SLUG\}\} settled_branch\)"(.\n      fallback: >-\n        koto could not record the merge verdict)/--head-branch "\${context.settled_branch}"$1/'
    mutate "worktree_sync rebasing again" \
        "no default action or gate runs git rebase" \
        's/command: git merge --no-edit origin\/main/command: git rebase origin\/main/'
    mutate "the phase-6-pr.md pointer back in ci_monitor" \
        "ci_monitor does not load /work-on's phase-6-pr.md" \
        's/(Monitor CI on the shared branch until all checks pass AND merge state is clean\.\n)/$1\nRead phase-6-pr.md for CI monitoring guidance.\n/'
    mutate "ci_monitor's CI cap removed" \
        "ci_monitor caps CI repair at 3 fix pushes, then failing_unresolvable" \
        's/\*\*CI repair is capped at 3 fix pushes, all within this one visit to `ci_monitor`\.\*\*/**CI repair is not capped.**/'
    mutate "worktree_sync's gate reduced to the merge exit code" \
        "worktree_sync's gate tests ancestry with no merge in progress" \
        's/command: .test -x "\{\{PLUGIN_ROOT\}\}\/skills\/work-on\/scripts\/check-branch-output.sh" \|\| exit 2; "\{\{PLUGIN_ROOT\}\}\/skills\/work-on\/scripts\/check-branch-output.sh" --synced.\n/command: true\n/'
    mutate "a braced SETTLED_BRANCH in settled_branch_record" \
        "settled_branch_record's prose names SETTLED_BRANCH without braces" \
        's/delivered to `spawn_and_await` under the name\n`SETTLED_BRANCH`/delivered to `spawn_and_await` under the name\n`{{SETTLED_BRANCH}}`/'
    mutate "the no-braces reason dropped from settled_branch_record" \
        "settled_branch_record's prose names SETTLED_BRANCH without braces" \
        's/That name is written without braces here on purpose: /That name is written this way: /'
    mutate "the current-context.md step back in spawn_and_await" \
        "no directive tells the agent to build current-context.md" \
        's/(it builds no context file)/write current-context.md into the next child; $1/'
fi

# No file under skills/execute outside its evals tells the agent to build
# current-context.md: carry-forward between the work-on.md children is koto
# calls, not a file. Runs under HANDOFF_ROUTE=work-on too.
BUILDERS=$(grep -rln 'current-context' "$SKILL_DIR" --exclude-dir=evals --exclude="$(basename "$0")" 2>/dev/null || true)
[ -z "$BUILDERS" ] && pass "no skills/execute file outside evals names current-context.md" \
    || fail "current-context.md is still named in: $BUILDERS"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
