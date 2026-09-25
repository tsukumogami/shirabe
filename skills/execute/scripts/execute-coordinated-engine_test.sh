#!/usr/bin/env bash
# execute-coordinated-engine_test.sh — the coordinated envelope on a real koto
# Part of the execute skill
#
# Drives execute-coordinated.md to each of its terminals under the real koto,
# with --no-cleanup on every tick, the way /execute drives it, and asserts that
# the session is retained and that `koto status` shows the declared result
# keys. The default actions (record-coordination-verdict.sh and
# record-merge-verdict.sh --confirm) run for real; GitHub is the eval gh shim's
# repository model (see coord-test-helpers.sh), which koto hands to the actions
# on its PATH.
#
# Cases:
#   merged                  two repositories, the coordination PR MERGED: the
#                           result has outcome=merged, pr naming the
#                           coordination PR, and repos listing both
#   ready_awaiting_merge    two independent roots without --merge: pr,
#                           waiting, reason=merge-not-requested
#   paused_awaiting_merges  a root awaiting a human, its successor waiting:
#                           pr, waiting, resume, reason; resume carries --merge
#                           exactly when MERGE is true
#   done_blocked (DIRTY)    outcome=ready-awaiting-merge, reason=merge-state:DIRTY
#   done_blocked (error)    outcome=error, step=execute:pr-adopt
#   coordination merge not observed   the coordination PR still OPEN after its
#                           recorded merge call: coord_merge_confirm routes to
#                           ready_awaiting_merge with reason=merge-not-observed,
#                           never merged
#   done_error              coord_setup blocked: outcome=error,
#                           step=execute:coord_setup
#   overrides               koto refuses `koto overrides record` on
#                           coord_verdict's and coord_merge_confirm's gates,
#                           with and without --with-data
#   retention               a terminal reached with --no-cleanup keeps the
#                           session's context; a control without it loses it
#   --koto-leg              the execute leg's promoted payload carries outcome,
#                           pr, repos, resume, and waiting, and the leg names
#                           execute-coordinated.md as the template
#
# In a checkout whose path koto's --var allowlist refuses (a `+` in a
# directory name), the cases run a copy of the template with this checkout's
# path written in for {{PLUGIN_ROOT}}, as terminal-retention_test.sh does.
#
# Usage: execute-coordinated-engine_test.sh
# Exit codes: 0 all pass, or koto absent (a loud SKIP); 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(CDPATH='' cd "$SKILL_DIR/../.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/execute-coordinated.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- the engine-backed cases did not run"
    exit 0
fi
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"
# The real engine, not the helpers' context stub.
rm -f "$CT_BIN/koto"

KOTO_ALLOW='^[a-zA-Z0-9._/:@ -]*$'
TPL="$TEMPLATE"
if [[ $REPO_ROOT =~ $KOTO_ALLOW ]]; then
    PLUGIN_ROOT_VAR="$REPO_ROOT"
else
    ln -s "$REPO_ROOT" "$CT_WORK/plugin"
    if [[ $CT_WORK/plugin =~ $KOTO_ALLOW ]]; then
        PLUGIN_ROOT_VAR="$CT_WORK/plugin"
    else
        mkdir -p "$CT_WORK/derived/skills/execute/koto-templates"
        TPL="$CT_WORK/derived/skills/execute/koto-templates/execute-coordinated.md"
        sed "s#{{PLUGIN_ROOT}}#$REPO_ROOT#g" "$TEMPLATE" > "$TPL"
        PLUGIN_ROOT_VAR=/koto-probe
        echo "  note: this checkout's path is outside koto's --var allowlist, so these cases run a"
        echo "        copy of execute-coordinated.md with the path written in for {{PLUGIN_ROOT}}"
    fi
fi

COORD_URL="https://github.com/acme/repo-a/pull/10"

# fixture <slug> [two-repo] -- a coordination checkout for one case, on CT_CB,
# with docs/plans/PLAN-<slug>.md committed. Sets REPO and CT_SLUG.
fixture() {
    CT_SLUG="$1"
    REPO="$CT_WORK/repo-$1"
    ct_repo "$REPO"
    ct_plan "$REPO" "${2:-}"
    mv "$REPO/docs/plans/PLAN-t.md" "$REPO/docs/plans/PLAN-$1.md"
    (cd "$REPO" && git add docs && git commit -q -m "docs: plan")
}
k() { (cd "$REPO" && koto "$@"); }

# open_run <slug> <merge> [extra init args] -- init, record the setup, and
# tick into coord_loop.
open_run() {
    local s="execute-$1" st
    shift
    local merge="$1"
    shift
    k init "$s" --template "$TPL" --var PLAN_DOC="docs/plans/PLAN-$CT_SLUG.md" --var PLAN_SLUG="$CT_SLUG" \
        --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" --var MERGE="$merge" "$@" >/dev/null 2>"$CASE/init.err" \
        || { fail "koto init $s: $(cat "$CASE/init.err")"; return 1; }
    (cd "$REPO" && bash "$SCRIPT_DIR/record-coord-setup.sh" --session "$s" --plan "docs/plans/PLAN-$CT_SLUG.md" \
        >/dev/null 2>"$CASE/setup.err") || { fail "record-coord-setup.sh: $(cat "$CASE/setup.err")"; return 1; }
    k next "$s" --no-cleanup >/dev/null 2>&1
    st=$(k status "$s" | jq -r '.current_state')
    [ "$st" = coord_loop ] || { fail "$s stopped at $st, not coord_loop"; return 1; }
}

# finish <slug> <loop_line> [--bare] -- submit the loop's stopping line.
finish() {
    local s="execute-$1" line="$2" exit_kind flag="--no-cleanup"
    case "$line" in done:*) exit_kind=done ;; pause) exit_kind=pause ;; *) exit_kind=error ;; esac
    [ "${3:-}" = --bare ] && flag=""
    # shellcheck disable=SC2086
    k next "$s" --with-data "{\"loop_exit\":\"$exit_kind\",\"loop_line\":\"$line\"}" $flag >"$CASE/next.json" 2>&1
}

state_of() { k status "execute-$1" 2>/dev/null | jq -r '.current_state // "gone"'; }
payload() { k status "execute-$1" 2>/dev/null | jq -r --arg k "$2" '.result.payload[$k] // ""'; }

# expect_terminal <slug> <state> <key=value>... -- the session is retained at
# <state> and its result payload holds each value (a value of `+` means
# "non-empty").
expect_terminal() {
    local slug="$1" want="$2" kv key val got ok=1
    shift 2
    if [ "$(state_of "$slug")" != "$want" ]; then
        fail "$slug: stopped at $(state_of "$slug"), not $want"
        head -c 800 "$CASE/next.json"; echo
        return
    fi
    for kv in "$@"; do
        key="${kv%%=*}"; val="${kv#*=}"
        got=$(payload "$slug" "$key")
        if [ "$val" = "+" ]; then
            [ -n "$got" ] || { fail "$slug: result $key is empty"; ok=0; }
        elif [ "$got" != "$val" ]; then
            fail "$slug: result $key expected [$val], got [$got]"; ok=0
        fi
    done
    [ "$ok" -eq 1 ] && pass "$slug reaches $want, retained, with result $*"
}

# --- merged -----------------------------------------------------------------------

ct_case merged
fixture merged two-repo
CT_COORD_STATE=MERGED
ct_write_db
open_run merged true && finish merged "done:merged"
expect_terminal merged merged outcome=merged "pr=$COORD_URL" "repos=acme/repo-a,acme/repo-b"
if ct_calls | grep -q -- '--head docs/t --state all' && ! ct_calls | grep -q 'acme/repo-a,acme/repo-b'; then
    pass "the confirm read looked up the coordination branch in home_repo, never the comma-joined repos"
else
    fail "the confirm read's lookups: $(ct_calls | grep 'pr list')"
fi

# --- ready_awaiting_merge ---------------------------------------------------------

ct_case ready
fixture ready two-repo
ct_index_line pr-repo-a-default acme/repo-a 11 "$CT_HEAD"
ct_index_line pr-repo-b-default acme/repo-b 21 "$CT_HEAD"
ct_pr acme/repo-a 11 impl/ready-pr-repo-a-default
ct_pr acme/repo-b 21 impl/ready-pr-repo-b-default
ct_write_db
open_run ready false && finish ready "done:ready-awaiting-merge"
expect_terminal ready ready_awaiting_merge outcome=ready-awaiting-merge "pr=$COORD_URL" waiting=+ \
    reason=merge-not-requested "repos=acme/repo-a,acme/repo-b"
if ct_calls | grep -q '^pr merge'; then fail "a run without --merge called pr merge"; else pass "no pr merge without --merge"; fi

# --- paused_awaiting_merges -------------------------------------------------------

ct_case paused
fixture paused
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/paused-$CT_CORE"
ct_write_db
open_run paused false && finish paused "pause"
expect_terminal paused paused_awaiting_merges outcome=paused-awaiting-merges "pr=$COORD_URL" waiting=+ \
    "resume=/execute docs/plans/PLAN-paused.md" reason=merge-not-requested
if ct_calls | grep -Eq '^pr (close|create)'; then fail "the pause closed or opened a PR"; else pass "the pause leaves the coordination PR open and opens nothing"; fi

ct_case paused-merge
fixture pausedm
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/pausedm-$CT_CORE" 'merge="stays-open"'
ct_write_db
if open_run pausedm true; then
    printf '%s' "$CT_CORE:merge-not-observed" | k context add execute-pausedm merge_attempts
    finish pausedm "pause"
fi
expect_terminal pausedm paused_awaiting_merges outcome=paused-awaiting-merges \
    "resume=/execute docs/plans/PLAN-pausedm.md --merge" reason=merge-not-observed
OUT=$(k status execute-pausedm | bash "$SCRIPT_DIR/print-exit.sh")
if printf '%s\n' "$OUT" | grep -qx "pr=https://github.com/acme/repo-a/pull/11 waiting=human reason=merge-not-observed" \
    && printf '%s\n' "$OUT" | grep -qx "resume=/execute docs/plans/PLAN-pausedm.md --merge" \
    && printf '%s\n' "$OUT" | grep -qx "outcome=paused-awaiting-merges" && printf '%s\n' "$OUT" | grep -qx "repos=acme/repo-a"; then
    pass "print-exit.sh renders the pause: one pr= line per unmerged PR, repos=, and resume= with --merge"
else
    fail "the pause's exit lines: [$OUT]"
fi

# --- done_blocked -----------------------------------------------------------------

ct_case dirty
fixture dirty
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/dirty-$CT_CORE" 'mergeStateStatus="DIRTY"'
ct_write_db
open_run dirty true && finish dirty "pause"
expect_terminal dirty done_blocked outcome=ready-awaiting-merge reason=merge-state:DIRTY "pr=$COORD_URL"

ct_case error
fixture error
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/error-$CT_CORE" 'author="someone-else"'
ct_write_db
open_run error true && finish error "error:execute:pr-adopt"
expect_terminal error done_blocked outcome=error step=execute:pr-adopt
OUT=$(k status execute-error | bash "$SCRIPT_DIR/print-exit.sh")
if printf '%s\n' "$OUT" | grep -qx 'outcome=error' && printf '%s\n' "$OUT" | grep -qx 'step=execute:pr-adopt'; then
    pass "print-exit.sh renders outcome=error with its step= line"
else
    fail "the error's exit lines: [$OUT]"
fi

# --- the coordination merge not observed -------------------------------------------

ct_case coord-not-observed
fixture cno
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_index_line "$CT_CLI" "$CT_REPO" 12 "$CT_HEAD"
ct_index_line coordination "$CT_REPO" 10 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/cno-$CT_CORE" 'state="MERGED"'
ct_pr "$CT_REPO" 12 "impl/cno-$CT_CLI" 'state="MERGED"'
CT_COORD_DRAFT=false
CT_COORD_MERGE=stays-open
ct_write_db
if open_run cno true; then
    # The cascade ran (the PLAN is gone), and this run's merge call on the
    # coordination PR was accepted without landing.
    (cd "$REPO" && git rm -q "docs/plans/PLAN-cno.md" && git commit -q -m "chore: cascade")
    printf '%s' "coordination:merge-not-observed" | k context add execute-cno merge_attempts
    finish cno "done:ready-awaiting-merge"
fi
expect_terminal cno ready_awaiting_merge outcome=ready-awaiting-merge reason=merge-not-observed "pr=$COORD_URL" waiting=+
if grep -q '"coord_merge_confirm"' "$(k session dir execute-cno)"/*.state.jsonl 2>/dev/null; then
    pass "the coordination PR's merge was confirmed by coord_merge_confirm's live read, which saw it OPEN"
else
    fail "the run did not pass through coord_merge_confirm"
fi
OUT=$(k status execute-cno | bash "$SCRIPT_DIR/print-exit.sh")
if printf '%s\n' "$OUT" | grep -q 'outcome=merged'; then
    fail "outcome=merged printed for a merge that was not observed"
elif printf '%s\n' "$OUT" | grep -q '^note=the PR may still be queued'; then
    pass "no outcome=merged anywhere, and the may-still-be-queued line is printed"
else
    fail "the exit lines lack the may-still-be-queued note: [$OUT]"
fi

# --- done_error -------------------------------------------------------------------

ct_case setup-blocked
fixture blocked
ct_write_db
k init execute-blocked --template "$TPL" --var PLAN_DOC=docs/plans/PLAN-blocked.md --var PLAN_SLUG=blocked \
    --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" --var MERGE=false >/dev/null 2>&1
k next execute-blocked --with-data '{"setup_status":"blocked","detail":"probe"}' --no-cleanup >"$CASE/next.json" 2>&1
expect_terminal blocked done_error outcome=error step=execute:coord_setup

# --- overrides are refused --------------------------------------------------------

ct_case overrides
fixture ovr
ct_write_db
if open_run ovr true; then
    # Hold the run at coord_verdict: with home_repo gone the record script
    # exits 64, which stops the tick at the state.
    k context remove execute-ovr home_repo >/dev/null 2>&1
    finish ovr "done:merged"
fi
if [ "$(state_of ovr)" = coord_verdict ]; then
    for g in verdict_merged verdict_ready verdict_paused verdict_dirty verdict_error; do
        k overrides record execute-ovr --gate "$g" --rationale probe >/dev/null 2>"$CASE/ov.err"; r1=$?
        k overrides record execute-ovr --gate "$g" --rationale probe --with-data '{"matches":true}' >/dev/null 2>&1; r2=$?
        if [ "$r1" -ne 0 ] && [ "$r2" -ne 0 ]; then
            pass "an override on coord_verdict's $g is refused, with and without --with-data"
        else
            fail "an override on $g was accepted (rc $r1 / $r2)"
        fi
    done
    k next execute-ovr --no-cleanup >/dev/null 2>&1
    [ "$(state_of ovr)" = coord_verdict ] && pass "after the refused overrides the run is still at coord_verdict" \
        || fail "the run moved to $(state_of ovr)"
else
    fail "could not hold a run at coord_verdict (at $(state_of ovr))"
fi

# Hold a run at coord_merge_confirm: held first at coord_verdict (home_repo
# gone, so the verdict's record script exits 64), then walked along the
# declared edge into coord_merge_confirm, whose confirm read exits 64 for the
# same reason and stops the tick there.
ct_case confirm-overrides
fixture cov2
CT_COORD_STATE=MERGED
ct_write_db
if open_run cov2 true; then
    k context remove execute-cov2 home_repo >/dev/null 2>&1
    finish cov2 "done:merged"
    k next execute-cov2 --to coord_merge_confirm --rationale probe --no-cleanup >"$CASE/next.json" 2>&1
fi
if [ "$(state_of cov2)" = coord_merge_confirm ]; then
    k overrides record execute-cov2 --gate confirmed_merged --rationale probe >/dev/null 2>&1; r1=$?
    k overrides record execute-cov2 --gate confirmed_merged --rationale probe --with-data '{"matches":true}' >/dev/null 2>&1; r2=$?
    if [ "$r1" -ne 0 ] && [ "$r2" -ne 0 ]; then
        pass "an override on coord_merge_confirm's confirmed_merged is refused, with and without --with-data"
    else
        fail "an override on confirmed_merged was accepted (rc $r1 / $r2)"
    fi
    k next execute-cov2 --with-data '{"confirm_status":"unreadable"}' --no-cleanup >/dev/null 2>&1
    if [ "$(state_of cov2)" = ready_awaiting_merge ] && [ "$(payload cov2 reason)" = merge-not-observed ]; then
        pass "with the confirm read unreadable the run ends ready-awaiting-merge (merge-not-observed), never merged"
    else
        fail "after the refused overrides: at $(state_of cov2), reason [$(payload cov2 reason)]"
    fi
else
    fail "could not hold a run at coord_merge_confirm (at $(state_of cov2)): $(head -c 600 "$CASE/next.json")"
fi

# --- retention ----------------------------------------------------------------------

ct_case retention
fixture keep
CT_COORD_STATE=MERGED
ct_write_db
open_run keep true && finish keep "done:merged"
if [ "$(k context get execute-keep repos 2>/dev/null)" = acme/repo-a ]; then
    pass "a terminal reached with --no-cleanup keeps the session's context"
else
    fail "the --no-cleanup terminal lost its context"
fi
fixture drop
open_run drop true && finish drop "done:merged" --bare
if k context get execute-drop repos >/dev/null 2>&1; then
    fail "a terminal reached without --no-cleanup kept its context -- the control did not fire"
else
    pass "a terminal reached without --no-cleanup loses its context (control)"
fi

# --- --koto-leg -----------------------------------------------------------------------

ct_case leg
fixture leg
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/leg-$CT_CORE"
ct_write_db
REQ=$(k request create --with-data '{"legs":[{"name":"execute","role":"execute","template":["execute.md","execute-coordinated.md"],"inputs":{}}]}' \
    --requested-by coord-engine-test --coordinator-of-record coord-engine-test 2>/dev/null \
    | jq -r 'if type == "object" then (.id // .request_id // .request // "") else . end' 2>/dev/null)
if [ -z "$REQ" ] || [ "$REQ" = null ]; then
    fail "koto request create printed no request id"
else
    open_run leg false --koto-leg "$REQ:execute" && finish leg "pause"
    LEG=$(k request get "$REQ" 2>/dev/null | jq -c '[.. | objects | select(has("name") and .name == "execute")][0] // {}')
    P=$(printf '%s' "$LEG" | jq -c '[.. | objects | select(has("outcome") and has("repos"))][0] // {}')
    if [ "$(printf '%s' "$P" | jq -r '.outcome')" = paused-awaiting-merges ] \
        && [ -n "$(printf '%s' "$P" | jq -r '.pr // ""')" ] && [ -n "$(printf '%s' "$P" | jq -r '.repos // ""')" ] \
        && [ -n "$(printf '%s' "$P" | jq -r '.resume // ""')" ] && [ -n "$(printf '%s' "$P" | jq -r '.waiting // ""')" ]; then
        pass "the execute leg's promoted payload carries outcome, pr, repos, resume, and waiting"
    else
        fail "the leg's payload: $P; leg: $(printf '%s' "$LEG" | head -c 800)"
    fi
    if printf '%s' "$LEG" | grep -q '"execute-coordinated.md"' && printf '%s' "$LEG" | grep -q '"promoted"'; then
        pass "the leg was promoted from a session built from execute-coordinated.md"
    else
        fail "the leg's template or source: $(printf '%s' "$LEG" | head -c 800)"
    fi
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
