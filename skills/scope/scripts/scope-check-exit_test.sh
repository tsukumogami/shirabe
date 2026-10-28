#!/usr/bin/env bash
# scope-check-exit_test.sh -- does a /scope document gate escalate a rule that
# keeps failing, and does its named exit end the run where the template says?
# Part of the scope skill
#
# The escalation ladder (scripts/lib/rule-findings.sh) reads koto's own count
# of how often a gate has failed on a rule in the current state. In each of
# /scope's five gated states (hop_brief, hop_prd, hop_design, hop_plan, fold)
# a real session against the shipped scope.md fails its document gate three
# times on one rule, and the gate's standard error, which koto returns in the
# blocking condition, must carry:
#
#   failure 1  the finding's summary only: no `::shirabe-rule::` block
#   failure 2  the rule's full text between `::shirabe-rule::` and
#              `::shirabe-rule-end::`
#   failure 3  one `::shirabe-check-exit::` line naming the rule, count 3, the
#              state, the evidence that takes the exit, and
#              `"ends_at":"exit_abandonment"`
#
# Then, in the same session: an evaluation the gate couldn't decide (exit 2, a
# symlink at the topic path) prints neither the text nor the exit line, and
# `check_unsatisfiable` submitted after it, or after a pass, is refused with
# the state unchanged. Submitted after a failure, it goes through check_exit
# to exit_abandonment with every committed document on disk and the reason in
# the session's context, and nothing else in the store holds the reason.
#
# Further sessions take the exit at the first failure, run fail, pass, fail
# in hop_plan with a second rule joining at its first failure, and show a
# rule's hop_plan failures don't count in the fold. The cases below them run
# the gate script directly against a written koto log: a rule at warn, an
# anchor `release` refuses, and the gate with and without the ladder's
# context.
#
# The rules are existing block rules with releasable anchors:
# docs/upstream-direction (a document naming its own type as its upstream)
# in the hop states and the fold, plan/issues-table-shape (a legacy issues
# table) in hop_plan.
#
# Needs koto, shirabe, git and jq; skips with a message naming the one that is
# missing. Store isolation comes from koto-test-guard.sh.
#
# Usage: scope-check-exit_test.sh
# Exit codes: 0 all pass (or skipped), 1 any failed, 2 the harness could not run.
#
# Written for the bash 3.2 floor: no associative arrays, no mapfile.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
TEMPLATE="$REPO/skills/scope/koto-templates/scope.md"
CHECK="$HERE/check-hop-document.sh"

for bin in koto shirabe git jq; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "SKIP: $bin is not on PATH; this suite drives real sessions and cannot run without it"
        exit 0
    fi
done
[ -f "$TEMPLATE" ] && [ -x "$CHECK" ] || { echo "FAIL: no template or gate script under $REPO" >&2; exit 2; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
# rule-findings-testlib.sh reports through pass and fail.
pass() { ok "$1"; }
fail() { bad "$1" "${2-}"; }

W="$KOTO_TEST_GUARD_DIR/w"
mkdir -p "$W" || exit 2
export GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$W"
git config --global user.email t@example.invalid
git config --global user.name t
git config --global init.defaultBranch main

# shellcheck source=testdata/hop-document-fixtures.sh
. "$HERE/testdata/hop-document-fixtures.sh"
# shellcheck source=../../../scripts/lib/rule-findings-testlib.sh
. "$REPO/scripts/lib/rule-findings-testlib.sh"
rf_test_setup "$W" || exit 2
# The findings this suite's sessions print are koto's to record; the log is
# only for the direct runs' copies, which pass their own.
unset SHIRABE_FINDINGS_LOG

# koto checks a --var value against ^[a-zA-Z0-9._/:@ \-]*$. A checkout whose
# path holds anything else runs through a symlink in the scratch directory,
# or, when that is refused too, a copy of scope.md with the path written in
# (scope-substrate_test.sh explains the same choice).
PLUGIN_ROOT_VAR="$REPO"
case "$REPO" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$REPO" "$W/plugin"
        PLUGIN_ROOT_VAR="$W/plugin"
        case "$PLUGIN_ROOT_VAR" in
            *[!a-zA-Z0-9._/:@\ -]*)
                sed "s#{{PLUGIN_ROOT}}#$REPO#g" "$TEMPLATE" > "$W/scope.md"
                TEMPLATE="$W/scope.md"
                PLUGIN_ROOT_VAR=/koto-probe ;;
        esac ;;
esac

PFX=scx
EXIT_TABLE='hop_brief:outcome hop_prd:outcome hop_design:outcome hop_plan:outcome fold:verdict'

# --- sessions -----------------------------------------------------------------

# open_run <tag>: a git tree at $W/<tag> on a named branch (branch_check needs
# one), and a session in it for topic <tag>, ticked to setup. koto binds a
# session to the directory it was opened in, so every tick runs from there.
open_run() {
    local t="$W/$1"
    mkdir -p "$t/docs" || return 1
    git -C "$t" init -q && git -C "$t" commit -q --allow-empty -m fixture \
        && git -C "$t" checkout -q -b scope-fixture || return 1
    ( cd "$t" && koto init "$PFX-$1" --template "$TEMPLATE" --var TOPIC="$1" \
        --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" --var PLUGIN_ROOT_PLACEMENT=outside >/dev/null 2>&1 \
        && koto next "$PFX-$1" --no-cleanup >/dev/null 2>&1 )
}

# tick <tag> <json>: submit evidence; the response is in $W/<tag>.resp.
tick() {
    ( cd "$W/$1" && koto next "$PFX-$1" --no-cleanup --with-data "$2" ) > "$W/$1.resp" 2>/dev/null
}

state_of() {
    ( cd "$W/$1" && koto status "$PFX-$1" 2>/dev/null ) | jq -r '.current_state // ""' 2>/dev/null
}

# gate_err <tag> <gate>: the gate's standard error from the last response.
gate_err() {
    jq -r --arg g "$2" '.blocking_conditions[]? | select(.name == $g) | .failure.captured.stderr // ""' \
        "$W/$1.resp" 2>/dev/null
}

# gate_rc <tag> <gate>: the gate's exit code in the last response, or "pass"
# when it is not among the blocking conditions.
gate_rc() {
    local rc
    rc=$(jq -r --arg g "$2" '[.blocking_conditions[]? | select(.name == $g) | .output.exit_code][0] // "pass"' \
        "$W/$1.resp" 2>/dev/null)
    printf '%s' "${rc:-pass}"
}

# finding_ids <tag> <gate>: the rule ids of the gate's findings, sorted.
finding_ids() {
    jq -r --arg g "$2" '.blocking_conditions[]? | select(.name == $g) | .failure.findings[]? | .rule_id' \
        "$W/$1.resp" 2>/dev/null | sort -u | tr '\n' ' '
}

# put <tag> <path>: stdin to <path> in the tree, committed.
put() {
    mkdir -p "$(dirname "$W/$1/$2")" && cat > "$W/$1/$2" || return 1
    git -C "$W/$1" add -A docs && git -C "$W/$1" commit -q -m "docs: $2"
}

# walk <tag> <state>: from setup to <state>, skipping the hops before it; the
# fold is reached by landing a valid PRD.
walk() {
    local tag=$1 st=$2 n=0 i
    tick "$tag" '{"setup_result":"ready"}'
    tick "$tag" '{"discovery_result":"proposed"}'
    tick "$tag" '{"author_decision":"proceed"}'
    case "$st" in
        hop_brief) n=0 ;;
        hop_prd) n=1 ;;
        hop_design) n=2 ;;
        hop_plan) n=3 ;;
        fold) n=1 ;;
    esac
    i=0
    while [ "$i" -lt "$n" ]; do
        tick "$tag" '{"outcome":"skipped"}'
        i=$((i + 1))
    done
    if [ "$st" = fold ]; then
        fx_prd "$tag" | put "$tag" "docs/prds/PRD-$tag.md"
        tick "$tag" '{"outcome":"landed"}'
    fi
}

# <tag> <gate>: counts of the gate's standard error lines that start a rule
# block, end one, or carry the exit notice; exit_notice prints the notice.
rule_blocks() { gate_err "$1" "$2" | grep -c '^::shirabe-rule::' ; }
rule_ends()   { gate_err "$1" "$2" | grep -c '^::shirabe-rule-end::' ; }
exit_lines()  { gate_err "$1" "$2" | grep -c '^::shirabe-check-exit::' ; }
exit_notice() { gate_err "$1" "$2" | sed -n 's/^::shirabe-check-exit:://p' ; }

# the_doc <state> <tag>: the topic path the state's gate checks in the case.
the_doc() {
    case "$1" in
        hop_brief) printf 'docs/briefs/BRIEF-%s.md' "$2" ;;
        hop_prd|fold) printf 'docs/prds/PRD-%s.md' "$2" ;;
        hop_design) printf 'docs/designs/DESIGN-%s.md' "$2" ;;
        hop_plan) printf 'docs/plans/PLAN-%s.md' "$2" ;;
    esac
}

# break_doc <state> <tag>: commit a topic document that fails one block rule
# (docs/upstream-direction: it names a sibling of its own type as its
# upstream; in hop_plan, plan/issues-table-shape: a legacy issues table) and
# print the rule's id.
break_doc() {
    local st=$1 tag=$2
    case "$st" in
        hop_brief)
            fx_brief other | put "$tag" docs/briefs/BRIEF-other.md
            fx_brief "$tag" | sed 's#^status: Draft$#status: Draft\nupstream: docs/briefs/BRIEF-other.md#' \
                | put "$tag" "$(the_doc "$st" "$tag")"
            printf 'docs/upstream-direction' ;;
        hop_prd|fold)
            fx_prd other | put "$tag" docs/prds/PRD-other.md
            fx_prd "$tag" docs/prds/PRD-other.md | put "$tag" "$(the_doc "$st" "$tag")"
            printf 'docs/upstream-direction' ;;
        hop_design)
            fx_design other | put "$tag" docs/designs/DESIGN-other.md
            fx_design "$tag" | sed 's#^rationale: |$#upstream: docs/designs/DESIGN-other.md\nrationale: |#' \
                | put "$tag" "$(the_doc "$st" "$tag")"
            printf 'docs/upstream-direction' ;;
        hop_plan)
            legacy_plan "$tag" | put "$tag" "$(the_doc "$st" "$tag")"
            printf 'plan/issues-table-shape' ;;
    esac
}

# legacy_plan <topic>: a valid PLAN plus an issues table in the legacy
# four-column shape, which the validator reports as FC05.
legacy_plan() {
    fx_plan "$1" | sed 's/^## Implementation Sequence$/## Implementation Issues\n\n| Issue | Title | Dependencies | Complexity |\n|---|---|---|---|\n| #1 | print | None | simple |\n\n## Implementation Sequence/'
}

# landed_json <state>: the evidence a landing submits in the state;
# exit_json <state> <reason>: the evidence that takes the named exit.
landed_json() {
    case "$1" in
        fold) printf '{"verdict":"keep"}' ;;
        *) printf '{"outcome":"landed"}' ;;
    esac
}
exit_json() { # <state> <reason>
    local f=outcome
    [ "$1" = fold ] && f=verdict
    jq -cn --arg f "$f" --arg r "$2" '{($f): "check_unsatisfiable", check_exit_reason: $r}'
}

# reason_elsewhere <tag> <reason>: files in the scratch store that hold the
# reason, other than the session's own event log and its context key.
reason_elsewhere() {
    grep -rlF -- "$2" "$KOTO_TEST_GUARD_DIR/home" 2>/dev/null \
        | grep -v "/koto-$PFX-$1\.state\.jsonl\$" | grep -v '/ctx/check_exit_reason' || true
}

# transitions <tag>: the states the session entered, in order.
transitions() {
    local dir
    dir=$( cd "$W/$1" && koto session dir "$PFX-$1" 2>/dev/null )
    jq -r 'select(.type == "transitioned") | .payload.to' "$dir/koto-$PFX-$1.state.jsonl" 2>/dev/null | tr '\n' ' '
}

# --- the ladder and the exit in each gated state ------------------------------

for spec in hop_brief:brief_document hop_prd:prd_document hop_design:design_document \
            hop_plan:plan_document fold:fold_documents; do
    st=${spec%%:*}; g=${spec#*:}
    tag=$(printf '%s' "$st" | tr '_' '-')
    echo "== $st"
    open_run "$tag" || { bad "$st: could not open a session" ""; continue; }
    walk "$tag" "$st"
    if [ "$(state_of "$tag")" != "$st" ]; then
        bad "$st: the walk did not reach the state" "state=$(state_of "$tag")"
        continue
    fi

    # Before any document fails, the gate passes and the exit is refused.
    tick "$tag" "$(exit_json "$st" "nothing fails yet")"
    [ "$(state_of "$tag")" = "$st" ] \
        && ok "$st: check_unsatisfiable after a passing evaluation is refused, the state unchanged" \
        || bad "$st: check_unsatisfiable after a pass moved the run" "state=$(state_of "$tag")"

    rule=$(break_doc "$st" "$tag")
    doc=$(the_doc "$st" "$tag")

    tick "$tag" "$(landed_json "$st")"
    if [ "$(state_of "$tag")" = "$st" ] && [ "$(finding_ids "$tag" "$g")" = "$rule " ] \
        && [ "$(rule_blocks "$tag" "$g")" -eq 0 ] && [ "$(exit_lines "$tag" "$g")" -eq 0 ]; then
        ok "$st: failure 1 holds on $rule with its summary, no rule text and no exit line"
    else
        bad "$st: failure 1" "state=$(state_of "$tag") ids=[$(finding_ids "$tag" "$g")] stderr=[$(gate_err "$tag" "$g" | head -c 600)]"
    fi

    tick "$tag" "$(landed_json "$st")"
    if [ "$(gate_err "$tag" "$g" | grep -c "^::shirabe-rule::{\"rule_id\":\"$rule\"")" -eq 1 ] \
        && [ "$(rule_ends "$tag" "$g")" -eq 1 ] && [ "$(exit_lines "$tag" "$g")" -eq 0 ]; then
        ok "$st: failure 2 prints $rule's full text between the rule markers, and no exit line"
    else
        bad "$st: failure 2" "stderr=[$(gate_err "$tag" "$g" | head -c 600)]"
    fi

    tick "$tag" "$(landed_json "$st")"
    field=outcome
    [ "$st" = fold ] && field=verdict
    notice=$(exit_notice "$tag" "$g")
    want=$(jq -cn --arg id "$rule" --arg st "$st" --arg f "$field" \
        '{rule_id: $id, count: 3, state: $st, submit: $f, ends_at: "exit_abandonment"}')
    got=$(printf '%s' "$notice" | jq -c --arg f "$field" \
        '{rule_id, count, state, submit: (.submit | to_entries[] | select(.value == "check_unsatisfiable") | .key), ends_at}' 2>/dev/null)
    if [ "$(exit_lines "$tag" "$g")" -eq 1 ] && [ "$got" = "$want" ] \
        && printf '%s' "$notice" | jq -e '.submit | has("check_exit_reason")' >/dev/null 2>&1; then
        ok "$st: failure 3 prints one exit line: $rule, count 3, $st, $field check_unsatisfiable, ends at exit_abandonment"
    else
        bad "$st: failure 3's exit line" "got=[$got] want=[$want] notice=[$notice]"
    fi

    # An evaluation the gate couldn't decide: a symlink at the topic path.
    ( cd "$W/$tag" && rm -f "$doc" && ln -s "$(basename "$doc" | sed "s/-$tag\.md\$/-other.md/")" "$doc" )
    tick "$tag" "$(landed_json "$st")"
    if [ "$(gate_rc "$tag" "$g")" = 2 ] && [ "$(rule_blocks "$tag" "$g")" -eq 0 ] \
        && [ "$(exit_lines "$tag" "$g")" -eq 0 ]; then
        ok "$st: an exit-2 evaluation after three failures prints neither the rule text nor the exit line"
    else
        bad "$st: exit 2 after three failures" "rc=$(gate_rc "$tag" "$g") stderr=[$(gate_err "$tag" "$g" | head -c 600)]"
    fi
    tick "$tag" "$(exit_json "$st" "the gate could not decide")"
    [ "$(state_of "$tag")" = "$st" ] \
        && ok "$st: check_unsatisfiable after an exit-2 evaluation is refused, the state unchanged" \
        || bad "$st: check_unsatisfiable after exit 2 moved the run" "state=$(state_of "$tag")"
    ( cd "$W/$tag" && rm -f "$doc" && git checkout -q -- "$doc" )

    reason="the $st rule cannot be met here zq$tag"
    tick "$tag" "$(exit_json "$st" "$reason")"
    ctx=$( cd "$W/$tag" && koto context get "$PFX-$tag" check_exit_reason 2>/dev/null )
    seen=$(transitions "$tag")
    if [ "$(state_of "$tag")" = exit_abandonment ] \
        && case "$seen" in *"$st check_exit exit_abandonment "*) true ;; *) false ;; esac; then
        ok "$st: check_unsatisfiable after a failure enters check_exit, then exit_abandonment"
    else
        bad "$st: the named exit" "state=$(state_of "$tag") transitions=[$seen] resp=[$(head -c 400 "$W/$tag.resp")]"
    fi
    if [ -f "$W/$tag/$doc" ] && [ -z "$(git -C "$W/$tag" status --porcelain -- docs)" ]; then
        ok "$st: every committed document is on disk, unchanged, after the exit"
    else
        bad "$st: the documents after the exit" "$(git -C "$W/$tag" status --porcelain -- docs)"
    fi
    [ "$ctx" = "$reason" ] \
        && ok "$st: the reason is in the session's context as check_exit_reason" \
        || bad "$st: check_exit_reason in context" "got=[$ctx]"
    leaked=$(reason_elsewhere "$tag" "$reason")
    [ -z "$leaked" ] \
        && ok "$st: no file in the store but the session's log and its context key holds the reason" \
        || bad "$st: the reason was written elsewhere" "$leaked"
done

# --- the exit at the first failure ----------------------------------------------

echo "== the first failure"
if open_run early; then
    walk early hop_brief
    break_doc hop_brief early > /dev/null
    tick early '{"outcome":"landed"}'
    tick early "$(exit_json hop_brief "taken at once")"
    [ "$(state_of early)" = exit_abandonment ] \
        && ok "check_unsatisfiable at failure 1 is accepted and ends at exit_abandonment" \
        || bad "the exit at failure 1" "state=$(state_of early)"
else
    bad "could not open the first-failure session" ""
fi

# --- fail, pass, fail in hop_plan, and a second rule -------------------------------

echo "== fail, pass, fail"
if open_run plan-seq; then
    walk plan-seq hop_plan
    legacy_plan plan-seq | put plan-seq docs/plans/PLAN-plan-seq.md
    tick plan-seq '{"outcome":"landed"}'
    [ "$(rule_blocks plan-seq plan_document)" -eq 0 ] \
        && ok "hop_plan: the first failure prints the summary only" \
        || bad "hop_plan: first failure" "stderr=[$(gate_err plan-seq plan_document | head -c 400)]"
    fx_plan plan-seq | put plan-seq docs/plans/PLAN-plan-seq.md
    tick plan-seq "$(exit_json hop_plan "nothing fails")"
    if [ "$(state_of plan-seq)" = hop_plan ] && [ "$(gate_rc plan-seq plan_document)" = pass ]; then
        ok "hop_plan: the fixed PLAN passes the gate, and the exit is refused"
    else
        bad "hop_plan: the pass" "state=$(state_of plan-seq) rc=$(gate_rc plan-seq plan_document)"
    fi
    legacy_plan plan-seq | put plan-seq docs/plans/PLAN-plan-seq.md
    tick plan-seq '{"outcome":"landed"}'
    if [ "$(gate_err plan-seq plan_document | grep -c '^::shirabe-rule::{"rule_id":"plan/issues-table-shape"')" -eq 1 ] \
        && [ "$(exit_lines plan-seq plan_document)" -eq 0 ]; then
        ok "hop_plan: fail, pass, fail prints the full text on the second failure"
    else
        bad "hop_plan: fail, pass, fail" "stderr=[$(gate_err plan-seq plan_document | head -c 600)]"
    fi
    # A second rule at its first failure, beside the first at its third.
    fx_plan other | put plan-seq docs/plans/PLAN-other.md
    legacy_plan plan-seq | sed 's#^execution_mode: single-pr$#execution_mode: single-pr\nupstream: docs/plans/PLAN-other.md#' \
        | put plan-seq docs/plans/PLAN-plan-seq.md
    tick plan-seq '{"outcome":"landed"}'
    ids=$(finding_ids plan-seq plan_document)
    second=$(printf '%s\n' $ids | grep -vxF plan/issues-table-shape | head -n 1)
    if [ "$(printf '%s\n' $ids | grep -cxF plan/issues-table-shape)" -eq 1 ] && [ -n "$second" ] \
        && [ "$(gate_err plan-seq plan_document | grep -c "^::shirabe-rule::{\"rule_id\":\"$second\"")" -eq 0 ]; then
        ok "hop_plan: a second rule ($second) failing for the first time prints only its summary"
    else
        bad "hop_plan: the second rule" "ids=[$ids] stderr=[$(gate_err plan-seq plan_document | head -c 600)]"
    fi
    if [ "$(exit_lines plan-seq plan_document)" -eq 1 ] \
        && [ "$(exit_notice plan-seq plan_document | jq -r '"\(.rule_id) \(.count)"' 2>/dev/null)" = "plan/issues-table-shape 3" ]; then
        ok "hop_plan: rules at counts 3 and 1 produce one exit line, naming the first"
    else
        bad "hop_plan: the exit line with two rules" "notice=[$(exit_notice plan-seq plan_document)]"
    fi
else
    bad "could not open the fail, pass, fail session" ""
fi

# --- counts are per state: hop_plan's failures don't count in the fold ----------

echo "== hop_plan, then the fold"
if open_run plan-fold; then
    walk plan-fold hop_plan
    legacy_plan plan-fold | put plan-fold docs/plans/PLAN-plan-fold.md
    tick plan-fold '{"outcome":"landed"}'
    tick plan-fold '{"outcome":"landed"}'
    fx_plan plan-fold | put plan-fold docs/plans/PLAN-plan-fold.md
    tick plan-fold '{"outcome":"landed"}'
    if [ "$(state_of plan-fold)" = fold ]; then
        legacy_plan plan-fold | put plan-fold docs/plans/PLAN-plan-fold.md
        tick plan-fold '{"verdict":"keep"}'
        if [ "$(finding_ids plan-fold fold_documents)" = "plan/issues-table-shape " ] \
            && [ "$(rule_blocks plan-fold fold_documents)" -eq 0 ] && [ "$(exit_lines plan-fold fold_documents)" -eq 0 ]; then
            ok "fold: a rule that failed twice in hop_plan is at its first failure in the fold"
        else
            bad "fold: the count after hop_plan" "ids=[$(finding_ids plan-fold fold_documents)] stderr=[$(gate_err plan-fold fold_documents | head -c 600)]"
        fi
    else
        bad "the fixed PLAN did not land into the fold" "state=$(state_of plan-fold) resp=[$(head -c 600 "$W/plan-fold.resp")]"
    fi
else
    bad "could not open the hop_plan-then-fold session" ""
fi

# --- the gate run directly against a written koto log ------------------------------

echo "== direct runs"
D="$W/direct"
mkdir -p "$D/docs/prds" && git -C "$D" init -q || exit 2
fx_prd other > "$D/docs/prds/PRD-other.md"
fx_prd t docs/prds/PRD-other.md > "$D/docs/prds/PRD-t.md"
git -C "$D" add -A && git -C "$D" commit -q -m fixture || exit 2
LOG="$W/direct.jsonl"
ERR="$W/direct.err"

# run_gate <script> [ladder]: the gate for --hop prd from the tree, with the
# template's four variables when the second argument is given.
run_gate() {
    if [ -n "${2-}" ]; then
        ( cd "$D" && SHIRABE_GATE_LOG="$LOG" SHIRABE_GATE_NAME=prd_document SHIRABE_GATE_EXITS="$EXIT_TABLE" \
            SHIRABE_GATE_EXIT_END=exit_abandonment "$1" --topic t --hop prd ) 2> "$ERR"
    else
        ( cd "$D" && "$1" --topic t --hop prd ) 2> "$ERR"
    fi
}

# A rule at warn, checked three times, passes the gate and never escalates.
COPY="$RF_TEST_DIR/warn"
if rf_test_stage_copy "$COPY" docs/upstream-direction warn \
    skills/scope/scripts/check-hop-document.sh skills/writing-style/rules.yaml 2> "$ERR"; then
    for n in 0 1 2; do
        if [ "$n" -eq 0 ]; then rf_test_ladder_log "$LOG" hop_prd prd_document
        else rf_test_ladder_log "$LOG" hop_prd prd_document docs/upstream-direction "$n"; fi
        out=$(SHIRABE_FINDINGS_LOG="" run_gate "$COPY/skills/scope/scripts/check-hop-document.sh" ladder)
        rc=$?
        if [ "$rc" -eq 0 ] && ! grep -q '^::shirabe-rule::' "$ERR" && ! grep -q '^::shirabe-check-exit::' "$ERR" \
            && ! grep -qF 'full text is at' "$ERR" \
            && [ "$(printf '%s\n' "$out" | sed -n 's/^::koto-finding:://p' | jq -r '.level' 2>/dev/null)" = warning ]; then
            ok "a rule at warn, check $((n + 1)): exit 0, a warning, no rule text and no exit line"
        else
            bad "a rule at warn, check $((n + 1))" "rc=$rc out=[$out] stderr=[$(head -c 400 "$ERR")]"
        fi
    done
else
    bad "could not make a plugin copy with docs/upstream-direction at warn" "$(cat "$ERR")"
fi
rm -rf "$COPY"

# An anchor release refuses: the second failure prints the refusal and the
# rule's reference instead of its text. The copy points the rule's text at a
# file outside the paths release prints.
COPY="$RF_TEST_DIR/refuse"
if rf_test_stage_copy "$COPY" docs/upstream-direction block \
    skills/scope/scripts/check-hop-document.sh skills/writing-style/rules.yaml 2> "$ERR"; then
    reg="$COPY/references/rule-registry.json"
    jq '(.rules[] | select(.id == "docs/required-sections") | .text) as $t
        | .rules |= map(if .id == "docs/upstream-direction" then .text = $t else . end)' \
        "$reg" > "$reg.tmp" && mv "$reg.tmp" "$reg"
    ref=$("$COPY/scripts/rule-registry.sh" resolve docs/upstream-direction 2>/dev/null | cut -f1)
    rf_test_ladder_log "$LOG" hop_prd prd_document docs/upstream-direction 1
    out=$(SHIRABE_FINDINGS_LOG="" run_gate "$COPY/skills/scope/scripts/check-hop-document.sh" ladder)
    rc=$?
    if [ "$rc" -eq 1 ] && [ -n "$ref" ] && grep -q '^rule-registry: could not release docs/upstream-direction' "$ERR" \
        && grep -qxF "rule-findings: docs/upstream-direction's full text is at $ref" "$ERR" \
        && ! grep -q '^::shirabe-rule::' "$ERR"; then
        ok "a release that refuses: the second failure prints the refusal line and the rule's reference"
    else
        bad "a refused release" "rc=$rc ref=[$ref] stderr=[$(head -c 600 "$ERR")]"
    fi
else
    bad "could not make a plugin copy for the refused release" "$(cat "$ERR")"
fi
rm -rf "$COPY"

# Without the four variables the gate exits and prints on standard output what
# it prints with them, apart from the delivery markers: on a failing PRD at
# counts 1, 2 and 3, on a passing one, and on one it can't decide.
same() { # <label> <exit>
    local plain plain_rc laddered laddered_rc
    run_gate "$CHECK" > "$W/plain.out"; plain_rc=$?
    run_gate "$CHECK" ladder > "$W/ladder.out"; laddered_rc=$?
    plain=$(grep -v '^::koto-rule-delivered::' "$W/plain.out")
    laddered=$(grep -v '^::koto-rule-delivered::' "$W/ladder.out")
    if [ "$plain_rc" -eq "$2" ] && [ "$plain_rc" -eq "$laddered_rc" ] && [ "$plain" = "$laddered" ]; then
        ok "without the ladder's variables, $1: the same exit ($plain_rc) and standard output"
    else
        bad "with and without the ladder's variables, $1" "rc $plain_rc vs $laddered_rc; [$plain] vs [$laddered]"
    fi
}
for n in 0 1 2; do
    if [ "$n" -eq 0 ]; then rf_test_ladder_log "$LOG" hop_prd prd_document
    else rf_test_ladder_log "$LOG" hop_prd prd_document docs/upstream-direction "$n"; fi
    same "a failing PRD at count $((n + 1))" 1
done
fx_prd t > "$D/docs/prds/PRD-t.md"
git -C "$D" commit -q -am "docs: fix" || true
same "a passing PRD" 0
rm -f "$D/docs/prds/PRD-t.md" && ln -s PRD-other.md "$D/docs/prds/PRD-t.md"
same "a symlinked PRD the gate can't decide" 2

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
