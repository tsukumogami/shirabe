#!/usr/bin/env bash
# record-coordination-verdict_test.sh — what coord_verdict records
# Part of the execute skill
#
# record-coordination-verdict.sh is the default action behind
# execute-coordinated.md's coord_verdict. It clears its seven keys, runs
# coordination-verdict.sh, checks every field against its closed pattern,
# renders the coordination PR's body (coord-render.sh), and writes the fields
# only when all pass. The harness runs it with the koto stub from
# coord-test-helpers.sh (a directory context store) and:
#
#   two cases end to end, with the real coordination-verdict.sh over the eval
#   gh shim's repository model;
#   the other cases on a COPY of the script, in a copy of the plugin's tree
#   with the real coord-render.sh and its codec, beside a stub
#   coordination-verdict.sh that prints chosen lines and logs its arguments.
#   The script runs its sibling from its own directory, never from PATH, so a
#   copy is how a case controls the verdict without a test hook in the script.
#
# Cases:
#   a normal write (real)                       keys written, coord_verdict last;
#                                               the body behind the record is
#                                               posted once, and a second run
#                                               (the body current) posts nothing;
#                                               body=posted, then unchanged
#   a render refusal (a private node under a public home)
#                                               coord_verdict=error,
#                                               step=execute:visibility, no post
#   a failed post                               body=stale, the verdict kept
#   the new reasons (merge-refused and its causes, follow-up-closed:<url>,
#     merge-state:DRAFT) pass the pattern; follow-up-closed: with no URL
#     does not
#   a follow-up closed unmerged (real)          reason=follow-up-closed:<url>
#   an attempts record with a follow-up id      reaches the verdict whole
#   stale coord_verdict, pr, waiting, resume, reason, step   each cleared
#   a failing coordination-verdict.sh           nothing written
#   a field failing its pattern (verdict, pr, waiting, resume, reason, step,
#     an error verdict with no step)            nothing written
#   the written reason; the written step
#   merge_attempts and loop_line from context reach the verdict as arguments,
#     and --session does
#   cascade=failed                              run/cascade becomes failed with
#                                               the step, before coord_verdict;
#                                               the body is posted after that
#                                               write (the request log)
#   no cascade line                             run/cascade untouched
#   a failed cascade the record refuses         exit 70, nothing written
#   a cascade value other than failed           nothing written
#   a missing coord_setup record                exit 64, nothing written
#   usage errors                                exit 64, no koto call
#   no GitHub write
#
# Usage: record-coordination-verdict_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
RECORD="$SCRIPT_DIR/record-coordination-verdict.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

S=execute-t
KEYS="coord_verdict pr waiting resume reason step body"
COORD_URL="https://github.com/acme/repo-a/pull/10"
U11="https://github.com/acme/repo-a/pull/11"

PLANDIR="$CT_WORK/plan"
ct_plan "$PLANDIR"

STUBDIR="$CT_WORK/tree/skills/execute/scripts"
mkdir -p "$STUBDIR" "$CT_WORK/tree/scripts/lib"
cp "$RECORD" "$STUBDIR/record-coordination-verdict.sh"
cp "$SCRIPT_DIR/run-id.sh" "$STUBDIR/run-id.sh"
cp "$SCRIPT_DIR/run-record.sh" "$SCRIPT_DIR/run-record-lib.sh" "$SCRIPT_DIR/coord-common.sh" \
    "$SCRIPT_DIR/coord-render.sh" "$STUBDIR/"
cp "$SCRIPT_DIR/../../../scripts/lib/coordination-body.sh" "$CT_WORK/tree/scripts/lib/"
# The render reads the run's recorded PR content switch through the tree's
# own pr-workflow-content.sh; without it the read fails, which reads omit.
cp "$SCRIPT_DIR/../../../scripts/pr-workflow-content.sh" "$CT_WORK/tree/scripts/"
cp "$SCRIPT_DIR/../../../scripts/lib/record-store.sh" "$CT_WORK/tree/scripts/lib/"
cat > "$STUBDIR/coordination-verdict.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${VERDICT_ARGS_LOG:?}"
[ -n "${VERDICT_RC:-}" ] && exit "$VERDICT_RC"
printf '%s\n' "${VERDICT_OUT:?}"
STUB

ctx() { printf '%s' "$2" > "$CASE/ctx/$S/$1"; }
ctx_has() { [ -f "$CASE/ctx/$S/$1" ]; }
ctx_val() { cat "$CASE/ctx/$S/$1" 2>/dev/null; }

setup_case() { # setup_case <name> -- a case with coord_setup recorded
    ct_case "$1"
    mkdir -p "$CASE/ctx/$S"
    ctx repos "acme/repo-a,acme/repo-b"
    ctx home_repo "$CT_REPO"
    ctx coord_branch "$CT_CB"
    export VERDICT_ARGS_LOG="$CASE/verdict-args.log"
    : > "$VERDICT_ARGS_LOG"
    unset VERDICT_RC VERDICT_OUT
}

run_stub() {
    (cd "$PLANDIR" && bash "$STUBDIR/record-coordination-verdict.sh" --session "$S" --merge true \
        --plan docs/plans/PLAN-t.md --slug t 2>"$CASE/stderr")
    RC=$?
}

nothing_written() { # nothing_written <label>
    local k any=""
    for k in $KEYS; do ctx_has "$k" && any="$any $k"; done
    if [ -z "$any" ]; then pass "$1: nothing written"; else fail "$1: wrote$any"; fi
}

good() { # good <verdict> <waiting> <resume> <reason> <step>
    printf 'coord_verdict=%s\npr=%s\nwaiting=%s\nresume=%s\nreason=%s\nstep=%s' \
        "$1" "$COORD_URL" "$2" "$3" "$4" "$5"
}

# --- the normal write, end to end ------------------------------------------------

setup_case normal
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
(cd "$PLANDIR" && bash "$RECORD" --session "$S" --merge false --plan docs/plans/PLAN-t.md --slug t 2>"$CASE/stderr")
RC=$?
if [ "$RC" -eq 0 ] && [ "$(ctx_val coord_verdict)" = paused ] && [ "$(ctx_val pr)" = "$COORD_URL" ] \
    && [ "$(ctx_val waiting)" = "$U11:human,$COORD_URL:predecessor" ] \
    && [ "$(ctx_val resume)" = "/execute docs/plans/PLAN-t.md" ] \
    && [ "$(ctx_val reason)" = merge-not-requested ] && ! ctx_has step; then
    pass "a normal write records the verdict and its fields"
else
    fail "a normal write: rc=$RC verdict=[$(ctx_val coord_verdict)] pr=[$(ctx_val pr)] waiting=[$(ctx_val waiting)] resume=[$(ctx_val resume)] reason=[$(ctx_val reason)]"
    tail -3 "$CASE/stderr"
fi
LAST_ADD=$(grep '^context add' "$CASE/koto-calls.log" | tail -1)
if [ "$LAST_ADD" = "context add $S coord_verdict" ]; then
    pass "coord_verdict is written last"
else
    fail "the last write was [$LAST_ADD], not coord_verdict"
fi
if [ "$(ctx_val body)" = posted ] && [ "$(ct_calls | grep -c '^pr edit 10 ')" = 1 ]; then
    pass "a body behind the record is posted once, and body=posted recorded"
else
    fail "the first render: body=[$(ctx_val body)], $(ct_calls | grep -c '^pr edit 10 ') edits"
fi
if ct_calls | grep -Eq '^pr (create|ready|merge|close)|^pr edit 1[1-9]'; then
    fail "the record made a GitHub write other than the body"
else
    pass "the record makes no GitHub write but the coordination body's"
fi
(cd "$PLANDIR" && bash "$RECORD" --session "$S" --merge false --plan docs/plans/PLAN-t.md --slug t 2>"$CASE/stderr")
RC=$?
if [ "$RC" -eq 0 ] && [ "$(ctx_val body)" = unchanged ] && [ "$(ct_calls | grep -c '^pr edit 10 ')" = 1 ] \
    && [ "$(ctx_val coord_verdict)" = paused ]; then
    pass "a second verdict over a current body posts nothing (body=unchanged)"
else
    fail "the second render: rc=$RC body=[$(ctx_val body)], $(ct_calls | grep -c '^pr edit 10 ') edits"
fi
ADDS=$(grep '^context add' "$CASE/koto-calls.log" | awk '{print $4}' | tr '\n' ' ')
case "$ADDS" in
    *"body coord_verdict "*) pass "body is written just before coord_verdict" ;;
    *) fail "the write order was [$ADDS]" ;;
esac

# --- a render refusal, end to end -----------------------------------------------------

setup_case render-refused
CT_RECORD_REPOS="acme/repo-a,acme/repo-b" ct_record_setup github 10 \
    '[{"name":"pr-repo-a-core","kind":"pr","repo":"acme/repo-a","waits_on":[]},{"name":"pr-repo-b-cli","kind":"pr","repo":"acme/repo-b","waits_on":["pr-repo-a-core"]}]'
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_record_node pr-repo-b-cli acme/repo-b 5 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_pr acme/repo-b 5 impl/t-pr-repo-b-cli
CT_VIS_B=private
ct_write_db
export VERDICT_OUT="$(good paused "$U11:human" "/execute docs/plans/PLAN-t.md --merge" merge-not-requested "")"
run_stub
if [ "$RC" -eq 0 ] && [ "$(ctx_val coord_verdict)" = error ] && [ "$(ctx_val step)" = execute:visibility ] \
    && [ "$(ctx_val body)" = refused:execute:visibility ] && ! ctx_has reason && ! ctx_has resume \
    && [ "$(ct_calls | grep -c '^pr edit ')" = 0 ]; then
    pass "a render refusal records coord_verdict=error with step=execute:visibility and posts nothing"
else
    fail "a render refusal: rc=$RC verdict=[$(ctx_val coord_verdict)] step=[$(ctx_val step)] body=[$(ctx_val body)]"
fi
CT_VIS_B=public

setup_case render-stale
ct_record_setup
ct_write_db
export VERDICT_OUT="$(good ready "$U11:human" "" merge-not-requested "")"
GH_SHIM_FAIL='^pr edit ' run_stub
if [ "$RC" -eq 0 ] && [ "$(ctx_val body)" = stale ] && [ "$(ctx_val coord_verdict)" = ready ] \
    && [ "$(ctx_val reason)" = merge-not-requested ]; then
    pass "a post that fails records body=stale and leaves the verdict as it was"
else
    fail "a failed post: rc=$RC body=[$(ctx_val body)] verdict=[$(ctx_val coord_verdict)]"
fi

for r in merge-refused merge-refused:body-stale merge-refused:body-full merge-refused:squash-message \
    "follow-up-closed:https://github.com/acme/repo-a/pull/21" merge-state:DRAFT; do
    setup_case "reason-$(printf '%s' "$r" | tr ':' '-')"
    export VERDICT_OUT="$(good ready "$U11:human" "" "$r" "")"
    run_stub
    if [ "$RC" -eq 0 ] && [ "$(ctx_val reason)" = "$r" ]; then
        pass "the reason $r passes the closed set"
    else
        fail "the reason $r: rc=$RC reason=[$(ctx_val reason)]"
    fi
done

# --- stale keys cleared -----------------------------------------------------------

for k in $KEYS; do
    setup_case "stale-$k"
    ctx "$k" "stale-value"
    export VERDICT_RC=1
    run_stub
    if [ "$RC" -eq 1 ] && ! ctx_has "$k"; then
        pass "a stale $k is cleared before the verdict runs"
    else
        fail "a stale $k: rc=$RC, still [$(ctx_val "$k")]"
    fi
done

# --- a failing verdict ------------------------------------------------------------

setup_case failing
export VERDICT_RC=2
run_stub
[ "$RC" -eq 1 ] && pass "a failing coordination-verdict.sh exits 1" || fail "a failing verdict: rc=$RC"
nothing_written "a failing coordination-verdict.sh"

# --- fields failing their patterns ------------------------------------------------

bad_case() { # bad_case <label> <output>
    setup_case "bad-$1"
    export VERDICT_OUT="$2"
    run_stub
    if [ "$RC" -eq 1 ]; then pass "$1: refused (exit 1)"; else fail "$1: rc=$RC"; fi
    nothing_written "$1"
}
bad_case "a verdict outside the set" "$(good merged-ish "" "" "" "")"
bad_case "a pr that is not a PR URL" "$(good ready "" "" review "" | sed 's#^pr=.*#pr=https://evil.example/x#')"
bad_case "a waiting entry with a bad role" "$(good ready "$U11:someone" "" review "")"
bad_case "a resume that is not an /execute command" "$(good paused "$U11:human" "/deliver x.md" review "")"
bad_case "a reason outside the condition set" "$(good ready "$U11:human" "" "because" "")"
bad_case "a follow-up-closed reason that is not a URL" "$(good ready "$U11:human" "" "follow-up-closed:not-a-url" "")"
bad_case "a step outside the step set" "$(good error "" "" "" "execute:whatever")"
bad_case "an error verdict with no step" "$(good error "" "" "" "")"

# --- the written reason and step ----------------------------------------------------

setup_case reason
export VERDICT_OUT="$(good dirty "$U11:human" "" "merge-state:DIRTY" "")"
run_stub
if [ "$RC" -eq 0 ] && [ "$(ctx_val reason)" = "merge-state:DIRTY" ] && [ "$(ctx_val coord_verdict)" = dirty ]; then
    pass "the written reason is the verdict's condition (merge-state:DIRTY)"
else
    fail "the written reason: rc=$RC reason=[$(ctx_val reason)]"
fi

setup_case step
export VERDICT_OUT="$(good error "" "" "" "execute:write-set")"
run_stub
if [ "$RC" -eq 0 ] && [ "$(ctx_val step)" = "execute:write-set" ] && [ "$(ctx_val coord_verdict)" = error ] && ! ctx_has reason; then
    pass "the written step is the verdict's step (execute:write-set)"
else
    fail "the written step: rc=$RC step=[$(ctx_val step)]"
fi

# --- the loop's record reaches the verdict ------------------------------------------

setup_case loop-record
ctx merge_attempts "$CT_CORE:merge-not-observed"
ctx loop_line "error:execute:dispatch"
export VERDICT_OUT="$(good error "" "" "" "execute:dispatch")"
run_stub
ARGS=$(cat "$VERDICT_ARGS_LOG")
case "$ARGS" in
    *"--attempts $CT_CORE:merge-not-observed"*"--loop-line error:execute:dispatch"*)
        pass "merge_attempts and loop_line reach coordination-verdict.sh" ;;
    *) fail "the verdict's arguments were [$ARGS]" ;;
esac
case "$ARGS" in
    *"--repos acme/repo-a,acme/repo-b --home-repo $CT_REPO --coord-branch $CT_CB --merge true"*)
        pass "the recorded write set, home repo, and coordination branch reach it" ;;
    *) fail "the verdict's arguments were [$ARGS]" ;;
esac
case "$ARGS" in
    "--session $S "*) pass "--session reaches coordination-verdict.sh" ;;
    *) fail "no --session in the verdict's arguments [$ARGS]" ;;
esac

# A follow-up's recorded refusal survives the attempts pattern: dropped, the
# verdict would recompute its merge and end the run in a coord-loop error.
setup_case loop-record-follow-up
ctx merge_attempts "$CT_CORE:merge-not-observed,$CT_CORE/follow-up-21:merge-refused"
export VERDICT_OUT="$(good ready "$U11:human" "" merge-refused "")"
run_stub
case "$(cat "$VERDICT_ARGS_LOG")" in
    *"--attempts $CT_CORE:merge-not-observed,$CT_CORE/follow-up-21:merge-refused"*)
        pass "an attempts record holding a follow-up id reaches coordination-verdict.sh whole" ;;
    *) fail "the follow-up attempts were dropped: [$(cat "$VERDICT_ARGS_LOG")]" ;;
esac

# End to end: a follow-up closed unmerged is the reason recorded.
setup_case follow-up-closed
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_record_node "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_pr "$CT_REPO" 12 "impl/t-$CT_CLI" 'state="MERGED"'
ct_follow_up_pr "$CT_REPO" 21 'state="CLOSED"'
ct_write_db
(cd "$PLANDIR" && bash "$RECORD" --session "$S" --merge true --plan docs/plans/PLAN-t.md --slug t 2>"$CASE/stderr")
RC=$?
if [ "$RC" -eq 0 ] && [ "$(ctx_val coord_verdict)" = ready ] \
    && [ "$(ctx_val reason)" = "follow-up-closed:https://github.com/acme/repo-a/pull/21" ] \
    && [ "$(ctx_val waiting)" = "https://github.com/acme/repo-a/pull/21:human,$COORD_URL:predecessor" ]; then
    pass "a follow-up closed unmerged: coord_verdict=ready, reason=follow-up-closed:<url>, the follow-up waiting"
else
    fail "follow-up closed: rc=$RC verdict=[$(ctx_val coord_verdict)] reason=[$(ctx_val reason)] waiting=[$(ctx_val waiting)]"
    tail -3 "$CASE/stderr"
fi

# --- a failed cascade, in the run record --------------------------------------------

setup_case cascade-failed
ct_record_setup
export VERDICT_OUT="$(good error "" "" "" "execute:cascade")
cascade=failed"
run_stub
if [ "$RC" -eq 0 ] && [ "$(ctx_val run/cascade)" = '{"step":"execute:cascade","verdict":"failed"}' ] \
    && [ "$(ctx_val coord_verdict)" = error ]; then
    pass "cascade=failed records run/cascade {verdict: failed, step}"
else
    fail "cascade=failed: rc=$RC run/cascade=[$(ctx_val run/cascade)] stderr=[$(tail -1 "$CASE/stderr")]"
fi
ORDER=$(grep '^context add' "$CASE/koto-calls.log" | awk '{print $4}' | grep -v '^run/setup$' | tr '\n' ' ')
case "$ORDER" in
    "run/cascade "*"coord_verdict ") pass "run/cascade is written before any verdict key" ;;
    *) fail "the write order was [$ORDER]" ;;
esac

# The cascade-failed transition posts a body in its own case: the body is
# behind the record (/scope's), and its post follows the run/cascade write.
setup_case cascade-failed-posts
ct_record_setup
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
export VERDICT_OUT="$(good error "" "" "" "execute:cascade")
cascade=failed"
run_stub
CASCADE_AT=$(awk -v k="koto context add $S run/cascade" '$0 == k && !n { n = NR } END { print n }' "$CASE/order.log")
EDIT_AT=$(awk '/^gh pr edit 10 / && !n { n = NR } END { print n }' "$CASE/order.log")
if [ "$RC" -eq 0 ] && [ "$(ctx_val body)" = posted ] && [ -n "$CASCADE_AT" ] && [ -n "$EDIT_AT" ] \
    && [ "$CASCADE_AT" -lt "$EDIT_AT" ]; then
    pass "a failed cascade posts the body after the run/cascade write"
else
    fail "cascade-failed post: rc=$RC body=[$(ctx_val body)] cascade at [$CASCADE_AT] edit at [$EDIT_AT]"
fi

setup_case cascade-untouched
ct_record_setup
ct_record_cascade pushed "$CT_HEAD"
export VERDICT_OUT="$(good error "" "" "" "execute:coord-loop")"
run_stub
if [ "$RC" -eq 0 ] && [ "$(ctx_val run/cascade)" = "{\"head\":\"$CT_HEAD\",\"verdict\":\"pushed\"}" ]; then
    pass "without a cascade line run/cascade is left as it was"
else
    fail "cascade-untouched: rc=$RC run/cascade=[$(ctx_val run/cascade)]"
fi

setup_case cascade-refused
# No run/setup: the record refuses the cascade write.
export VERDICT_OUT="$(good error "" "" "" "execute:cascade")
cascade=failed"
run_stub
[ "$RC" -eq 70 ] && ! ctx_has run/cascade && pass "a failed cascade the record refuses exits 70" \
    || fail "cascade-refused: rc=$RC run/cascade=[$(ctx_val run/cascade)]"
nothing_written "a failed cascade the record refuses"

bad_case "a cascade value other than failed" "$(good error "" "" "" "execute:cascade")
cascade=pushed"
bad_case "a failed cascade on a verdict that is not an error" "$(good ready "$U11:human" "" review "")
cascade=failed"

# --- a missing coord_setup record ---------------------------------------------------

setup_case no-setup
rm -f "$CASE/ctx/$S/home_repo"
ctx coord_verdict "merged"
export VERDICT_OUT="$(good merged "" "" "" "")"
run_stub
if [ "$RC" -eq 64 ] && [ ! -s "$VERDICT_ARGS_LOG" ]; then
    pass "a missing home_repo record exits 64 without running the verdict"
else
    fail "a missing home_repo: rc=$RC"
fi
nothing_written "a missing home_repo record"

# --- usage --------------------------------------------------------------------------

setup_case usage
for args in "--merge true --plan p.md --slug t" "--session $S --merge yes --plan p.md --slug t" \
            "--session $S --merge true --plan p.md --slug T" "--session -x --merge true --plan p.md --slug t"; do
    # shellcheck disable=SC2086
    (cd "$PLANDIR" && bash "$RECORD" $args 2>/dev/null)
    rc=$?
    [ "$rc" -eq 64 ] && pass "usage [$args] exits 64" || fail "usage [$args]: rc=$rc"
done
[ -s "$CASE/koto-calls.log" ] && fail "a usage error called koto" || pass "no usage error called koto"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
