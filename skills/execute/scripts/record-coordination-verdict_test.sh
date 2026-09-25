#!/usr/bin/env bash
# record-coordination-verdict_test.sh — what coord_verdict records
# Part of the execute skill
#
# record-coordination-verdict.sh is the default action behind
# execute-coordinated.md's coord_verdict. It clears its six keys, runs
# coordination-verdict.sh, checks every field against its closed pattern, and
# writes them only when all pass. The harness runs it with the koto stub from
# coord-test-helpers.sh (a directory context store) and:
#
#   one case end to end, with the real coordination-verdict.sh over the eval
#   gh shim's repository model;
#   the other cases on a COPY of the script beside a stub
#   coordination-verdict.sh that prints chosen lines and logs its arguments.
#   The script runs its sibling from its own directory, never from PATH, so a
#   copy is how a case controls the verdict without a test hook in the script.
#
# Cases:
#   a normal write (real)                       keys written, coord_verdict last
#   stale coord_verdict, pr, waiting, resume, reason, step   each cleared
#   a failing coordination-verdict.sh           nothing written
#   a field failing its pattern (verdict, pr, waiting, resume, reason, step,
#     an error verdict with no step)            nothing written
#   the written reason; the written step
#   merge_attempts and loop_line from context reach the verdict as arguments
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
KEYS="coord_verdict pr waiting resume reason step"
COORD_URL="https://github.com/acme/repo-a/pull/10"
U11="https://github.com/acme/repo-a/pull/11"

PLANDIR="$CT_WORK/plan"
ct_plan "$PLANDIR"

STUBDIR="$CT_WORK/stub-scripts"
mkdir -p "$STUBDIR"
cp "$RECORD" "$STUBDIR/record-coordination-verdict.sh"
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

# --- the normal write, end to end ------------------------------------------------

setup_case normal
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
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
if ct_calls | grep -Eq '^pr (create|edit|ready|merge|close)'; then
    fail "the record made a GitHub write"
else
    pass "the record makes no GitHub write"
fi

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

good() { # good <verdict> <waiting> <resume> <reason> <step>
    printf 'coord_verdict=%s\npr=%s\nwaiting=%s\nresume=%s\nreason=%s\nstep=%s' \
        "$1" "$COORD_URL" "$2" "$3" "$4" "$5"
}
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
