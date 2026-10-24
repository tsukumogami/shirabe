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
#   merged (home outside)   the coordination PR in acme/repo-a, every node in
#                           acme/repo-b: coord_setup reaches coord_loop and the
#                           run ends merged with repos=acme/repo-b
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
#                           step=execute:coord_setup; a typed setup stop
#                           (store-mismatch) assigns its code as the reason
#   the body at each terminal  coord_verdict's default action renders the
#                           coordination PR's body: ready_awaiting_merge,
#                           paused_awaiting_merges, done_blocked (DIRTY) and
#                           done_blocked (error) each post it once, in their
#                           own case, with body=posted in the result; merged
#                           posts nothing (body=unchanged); a setup stop
#                           (done_error) posts nothing
#   a render refusal        a record naming a private repository under a
#                           public coordination PR ends at done_blocked with
#                           step=execute:visibility and nothing posted
#   a coordination body that couldn't be posted   coordination:body-stale in
#                           the attempts, the coordination PR a draft: the run
#                           ends ready_awaiting_merge with
#                           reason=merge-refused:body-stale
#   the record across a pause  a run at paused_awaiting_merges re-invoked
#                           through execute-open.sh is replaced with its run/
#                           keys carried byte-equal, the same run_id, and no
#                           merge_attempts; a carry that fails after the
#                           replacement keeps its snapshot, and the next open
#                           carries from it; with the PLAN deleted before the
#                           re-invocation, the opener still picks
#                           execute-coordinated.md and setup reads repos from
#                           run/setup into coord_loop
#   recovery                no record, a carried run_id, store session:
#                           done_error with reason=session-absent and no body
#                           edit; no record on github, the rendered run line
#                           matching the node PR's marker: setup recovers,
#                           the run pauses with recovered=<coordination PR>
#                           in the result, and print-exit.sh prints it; no
#                           record, no carried run_id, a body with no index
#                           line, and an owned PR on a node branch (ixmiss):
#                           done_error with reason=coordination-index-missing,
#                           nothing posted, commented on, or merged
#   follow-ups             a --follow-up on a new run: setup stops
#                           follow-up-node, done_error with that reason,
#                           nothing posted, no run/setup; a follow-up closed
#                           unmerged against a node GitHub reports MERGED:
#                           ready_awaiting_merge with
#                           reason=follow-up-closed:<url>, the follow-up
#                           waiting, no merge; an open one without --merge:
#                           reason=merge-not-requested, the follow-up waiting
#   overrides              koto refuses `koto overrides record` on
#                           coord_verdict's and coord_merge_confirm's gates,
#                           with and without --with-data
#   retention               a terminal reached with --no-cleanup keeps the
#                           session's context; a control without it loses it
#   --koto-leg              the execute leg's promoted payload carries outcome,
#                           pr, repos, resume, and waiting, and the leg names
#                           execute-coordinated.md as the template
#
# A new run's setup runs the real record-coord-setup.sh, which seals the run
# record before any node PR exists, as in a real run; the node PRs a case
# added with ct_pr reach the gh model only after it (open_run), and the case
# then seeds the heads the run recorded up to its moment through the test
# helper (run-record.sh itself, on the real koto). The case's fixed run_id is
# written after setup: one written before it would be a carried id, which
# makes the start a recovery. Follow-up PRs are held back the same way. The
# recovery cases (open_recovering) leave their node PRs in the model before
# setup: there they mean a started run. Setup and node-push.sh also write the
# run's trail and its per-PR index sessions (scripts/run-trail.sh) through the
# real koto.
#
# The real koto runs under the helpers' scratch HOME with every
# KOTO_SESSION_* variable, KOTO_SESSIONS_BASE and KOTO_TICK_SESSION cleared,
# and the suite stops before its first koto command unless `koto session dir`
# resolves under the scratch directory (ct_real_koto_guard).
#
# In a checkout whose path koto's --var allowlist refuses (a `+` in a
# directory name), the cases run a copy of the template with this checkout's
# path written in for {{PLUGIN_ROOT}}, as terminal-retention_test.sh does.
#
# A tick a case needs to get past a default action goes through tick(), which
# ticks again when koto stopped the action at its 30-second limit, as the
# state's fallback says to, and fails naming the state when the limit outlasts
# its retries: a loaded host can pass that limit with nothing wrong in the
# action. The cases that hold a run at a failing action tick koto directly.
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
# The real engine, not the helpers' context stub, kept in the helpers'
# scratch HOME: the guard stops the suite before any koto command otherwise.
rm -f "$CT_BIN/koto"
ct_real_koto_guard

# koto's recorded command environment hides this harness's stand-in variables
# from the commands koto runs; the knob keeps the old environment where the
# koto accepts it (scripts/lib/koto-legacy-env.sh; temporary, #483).
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable

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

# fixture <slug> [two-repo|remote] -- a coordination checkout for one case, on CT_CB,
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

# open_run <slug> <merge> [extra init args] -- init, record the setup, open
# the case's node PRs, and tick into coord_loop.
open_run() {
    local s="execute-$1" st seed="$EVAL_SCENARIO_DIR/gh/db.json" live="$GH_CALL_LOG.d/db.json" held rc
    shift
    local merge="$1"
    shift
    # $KOTO_LEGACY_ENV_ARG: #483.
    k init "$s" $KOTO_LEGACY_ENV_ARG --template "$TPL" --var PLAN_DOC="docs/plans/PLAN-$CT_SLUG.md" --var PLAN_SLUG="$CT_SLUG" \
        --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" --var MERGE="$merge" "$@" >"$CASE/init.out" 2>&1 \
        || { fail "koto init $s: $(cat "$CASE/init.out")"; return 1; }
    # The node PRs the case added (ct_pr, on impl/ branches) reach the model
    # only once setup has sealed the record, as in a real run, where
    # node-push.sh opens them after setup: an owned PR on a node branch at
    # setup means a run had started, and setup would stop or recover rather
    # than seal a new one. Follow-up PRs (ct_follow_up_pr, on fix/ branches)
    # are held back the same way, since a run's follow-ups are opened after
    # its nodes. They are held out of the seed the shim's first call
    # (setup's) copies, then added to the model it built, with the
    # remote_url the shim gives a seeded PR in default_repo.
    held=$(jq -c '[.prs[] | select(.headRefName | startswith("impl/") or startswith("fix/"))]' "$seed")
    cp "$seed" "$seed.full"
    jq '.prs |= map(select(.headRefName | (startswith("impl/") or startswith("fix/")) | not))' "$seed.full" > "$seed"
    (cd "$REPO" && bash "$SCRIPT_DIR/record-coord-setup.sh" --session "$s" --plan "docs/plans/PLAN-$CT_SLUG.md" \
        >/dev/null 2>"$CASE/setup.err")
    rc=$?
    mv "$seed.full" "$seed"
    if [ -f "$live" ]; then
        jq --argjson h "$held" --arg u "$(git -C "$REPO" remote get-url --push origin 2>/dev/null)" \
            '.default_repo as $home | .prs += ($h | map(if $u != "" and .repo == $home then . + {remote_url: $u} else . end))' \
            "$live" > "$live.tmp" && mv "$live.tmp" "$live"
    fi
    [ "$rc" -eq 0 ] || { fail "record-coord-setup.sh: $(cat "$CASE/setup.err")"; return 1; }
    # The case's fixed run identity, written over the one setup minted: one
    # written before setup would be a carried id, which makes the start a
    # recovery rather than a new run.
    printf '00112233445566778899aabbccddeeff' | k context add "$s" run_id >/dev/null 2>&1
    k next "$s" --no-cleanup >/dev/null 2>&1
    st=$(k status "$s" | jq -r '.current_state')
    [ "$st" = coord_loop ] || { fail "$s stopped at $st, not coord_loop"; return 1; }
}

# action_timed_out -- the last tick's output ($CASE/next.json) shows a default
# action koto stopped at its time limit; prints "<state>: <koto's message>".
action_timed_out() {
    jq -Rer 'fromjson? | .blocking_conditions // [] | .[]
        | select(.type == "action" and .status == "timed_out")
        | "\(.output.state // "?"): \(.output.stderr // "timed out")"' "$CASE/next.json" 2>/dev/null
}

# tick <session> [koto next args...] -- one `koto next` into $CASE/next.json.
# koto runs a default action under a fixed 30-second limit that a template
# can't raise, and on a loaded host coord_verdict's and coord_merge_confirm's
# actions can pass it (#1062), which leaves the run at that state. Both
# states' fallbacks say to tick again, which re-runs the action, so tick does
# that up to TICK_RETRIES times. A timeout that outlasts them fails here,
# naming the state, so the case reports the cause rather than a terminal or a
# leg payload that never arrived. Three retries: an action that takes past
# 30 seconds four times running is stuck, not slow, and each retry can cost
# the suite another 30.
TICK_RETRIES=3
tick() {
    local s="$1" n=0 why flag=""
    shift
    case " $* " in *" --no-cleanup "*) flag=--no-cleanup ;; esac
    k next "$s" "$@" >"$CASE/next.json" 2>&1
    while why=$(action_timed_out); do
        if [ "$n" -ge "$TICK_RETRIES" ]; then
            fail "$s: koto stopped the default action at $why, on $((n + 1)) ticks"
            return 1
        fi
        n=$((n + 1))
        echo "  note: $s: koto stopped the default action at $why; ticking again ($n of $TICK_RETRIES)"
        # No --with-data: the first tick's evidence moved the run already, and
        # a tick with none re-runs the state's action.
        k next "$s" ${flag:+"$flag"} >"$CASE/next.json" 2>&1
    done
}

# finish <slug> <loop_line> [--bare] -- submit the loop's stopping line.
finish() {
    local s="execute-$1" line="$2" exit_kind flag="--no-cleanup"
    case "$line" in done:*) exit_kind=done ;; pause) exit_kind=pause ;; *) exit_kind=error ;; esac
    [ "${3:-}" = --bare ] && flag=""
    tick "$s" --with-data "{\"loop_exit\":\"$exit_kind\",\"loop_line\":\"$line\"}" ${flag:+"$flag"}
}

# record <slug> <helper> [args...] -- seed the run record of execute-<slug>
# through the test helper (run-record.sh on the real koto), after setup sealed
# it: the node PRs and heads the run recorded up to the case's moment.
record() {
    local slug="$1"
    shift
    (cd "$REPO" && CT_RECORD_SESSION="execute-$slug" && "$@") \
        || fail "seeding execute-$slug's run record: $*"
}

state_of() { k status "execute-$1" 2>/dev/null | jq -r '.current_state // "gone"'; }
payload() { k status "execute-$1" 2>/dev/null | jq -r --arg k "$2" '.result.payload[$k] // ""'; }

# body_posts <slug> <count> -- the case made <count> posts of the coordination
# PR's body (pr edit 10), and the result's body says what the last render did.
body_posts() {
    local n
    n=$(ct_calls | grep -c '^pr edit 10 ')
    if [ "$n" = "$2" ]; then
        pass "$1: the coordination PR's body was posted $2 time(s), result body=$(payload "$1" body)"
    else
        fail "$1: $n posts of the coordination PR's body, expected $2 (result body=[$(payload "$1" body)])"
    fi
}

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
expect_terminal merged merged outcome=merged "pr=$COORD_URL" "repos=acme/repo-a,acme/repo-b" body=unchanged
body_posts merged 0
if ct_calls | grep -q -- '--head docs/t --state all' && ! ct_calls | grep -q 'acme/repo-a,acme/repo-b'; then
    pass "the confirm read looked up the coordination branch in home_repo, never the comma-joined repos"
else
    fail "the confirm read's lookups: $(ct_calls | grep 'pr list')"
fi

# The coordination PR in acme/repo-a over a PLAN whose nodes are all in
# acme/repo-b: coord_setup's gates pass, and the verdict reads the run whole.
ct_case home-outside
fixture homeout remote
CT_COORD_STATE=MERGED
ct_write_db
open_run homeout true && finish homeout "done:merged"
expect_terminal homeout merged outcome=merged "pr=$COORD_URL" "repos=acme/repo-b"
if [ "$(k context get execute-homeout home_repo 2>/dev/null)" = acme/repo-a ]; then
    pass "home outside the write set: home_repo=acme/repo-a is recorded beside repos=acme/repo-b"
else
    fail "home outside the write set: home_repo [$(k context get execute-homeout home_repo 2>/dev/null)]"
fi

# --- ready_awaiting_merge ---------------------------------------------------------

ct_case ready
fixture ready two-repo
ct_pr acme/repo-a 11 impl/ready-pr-repo-a-default
ct_pr acme/repo-b 21 impl/ready-pr-repo-b-default
ct_write_db
if open_run ready false; then
    record ready ct_record_node pr-repo-a-default acme/repo-a 11
    record ready ct_record_node pr-repo-b-default acme/repo-b 21
    finish ready "done:ready-awaiting-merge"
fi
expect_terminal ready ready_awaiting_merge outcome=ready-awaiting-merge "pr=$COORD_URL" waiting=+ \
    reason=merge-not-requested "repos=acme/repo-a,acme/repo-b" body=posted
body_posts ready 1
if ct_calls | grep -q '^pr merge'; then fail "a run without --merge called pr merge"; else pass "no pr merge without --merge"; fi

# --- paused_awaiting_merges -------------------------------------------------------

ct_case paused
fixture paused
ct_pr "$CT_REPO" 11 "impl/paused-$CT_CORE"
ct_write_db
if open_run paused false; then
    record paused ct_record_node "$CT_CORE" "$CT_REPO" 11
    finish paused "pause"
fi
expect_terminal paused paused_awaiting_merges outcome=paused-awaiting-merges "pr=$COORD_URL" waiting=+ \
    "resume=/execute docs/plans/PLAN-paused.md" reason=merge-not-requested body=posted
body_posts paused 1
if ct_calls | grep -Eq '^pr (close|create)'; then fail "the pause closed or opened a PR"; else pass "the pause leaves the coordination PR open and opens nothing"; fi

ct_case paused-merge
fixture pausedm
ct_pr "$CT_REPO" 11 "impl/pausedm-$CT_CORE" 'merge="stays-open"'
ct_write_db
if open_run pausedm true; then
    record pausedm ct_record_node "$CT_CORE" "$CT_REPO" 11
    printf '%s' "$CT_CORE:merge-not-observed" | k context add execute-pausedm merge_attempts
    finish pausedm "pause"
fi
expect_terminal pausedm paused_awaiting_merges outcome=paused-awaiting-merges \
    "resume=/execute docs/plans/PLAN-pausedm.md --merge" reason=merge-not-observed
OUT=$(k status execute-pausedm | bash "$SCRIPT_DIR/print-exit.sh")
if grep -qx "pr=https://github.com/acme/repo-a/pull/11 waiting=human reason=merge-not-observed" <<<"$OUT" \
    && grep -qx "resume=/execute docs/plans/PLAN-pausedm.md --merge" <<<"$OUT" \
    && grep -qx "outcome=paused-awaiting-merges" <<<"$OUT" && grep -qx "repos=acme/repo-a" <<<"$OUT"; then
    pass "print-exit.sh renders the pause: one pr= line per unmerged PR, repos=, and resume= with --merge"
else
    fail "the pause's exit lines: [$OUT]"
fi

# --- done_blocked -----------------------------------------------------------------

ct_case dirty
fixture dirty
ct_pr "$CT_REPO" 11 "impl/dirty-$CT_CORE" 'mergeStateStatus="DIRTY"'
ct_write_db
if open_run dirty true; then
    record dirty ct_record_node "$CT_CORE" "$CT_REPO" 11
    finish dirty "pause"
fi
expect_terminal dirty done_blocked outcome=ready-awaiting-merge reason=merge-state:DIRTY "pr=$COORD_URL" body=posted
body_posts dirty 1

ct_case error
fixture error
ct_pr "$CT_REPO" 11 "impl/error-$CT_CORE" 'author="someone-else"'
ct_write_db
if open_run error true; then
    record error ct_record_node "$CT_CORE" "$CT_REPO" 11
    finish error "error:execute:pr-adopt"
fi
expect_terminal error done_blocked outcome=error step=execute:pr-adopt body=posted
body_posts error 1
OUT=$(k status execute-error | bash "$SCRIPT_DIR/print-exit.sh")
if grep -qx 'outcome=error' <<<"$OUT" && grep -qx 'step=execute:pr-adopt' <<<"$OUT"; then
    pass "print-exit.sh renders outcome=error with its step= line"
else
    fail "the error's exit lines: [$OUT]"
fi

# --- the coordination merge not observed -------------------------------------------

ct_case coord-not-observed
fixture cno
ct_pr "$CT_REPO" 11 "impl/cno-$CT_CORE" 'state="MERGED"'
ct_pr "$CT_REPO" 12 "impl/cno-$CT_CLI" 'state="MERGED"'
CT_COORD_DRAFT=false
CT_COORD_MERGE=stays-open
ct_write_db
if open_run cno true; then
    # The cascade ran (the PLAN is gone, its pushed head recorded), and this
    # run's merge call on the coordination PR was accepted without landing.
    record cno ct_record_node "$CT_CORE" "$CT_REPO" 11
    record cno ct_record_node "$CT_CLI" "$CT_REPO" 12
    record cno ct_record_cascade pushed "$CT_HEAD"
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
if grep -q 'outcome=merged' <<<"$OUT"; then
    fail "outcome=merged printed for a merge that was not observed"
elif grep -q '^note=the PR may still be queued' <<<"$OUT"; then
    pass "no outcome=merged anywhere, and the may-still-be-queued line is printed"
else
    fail "the exit lines lack the may-still-be-queued note: [$OUT]"
fi

# --- a render refusal, and a body that couldn't be posted -------------------------

ct_case render-refused
fixture refused two-repo
ct_pr acme/repo-a 11 impl/refused-pr-repo-a-default
ct_pr acme/repo-b 21 impl/refused-pr-repo-b-default
CT_VIS_B=private
ct_write_db
CT_VIS_B=public
if open_run refused false; then
    record refused ct_record_node pr-repo-a-default acme/repo-a 11
    record refused ct_record_node pr-repo-b-default acme/repo-b 21
    finish refused "done:ready-awaiting-merge"
fi
expect_terminal refused done_blocked outcome=error step=execute:visibility body=refused:execute:visibility
body_posts refused 0

ct_case body-stale
fixture bstale
ct_pr "$CT_REPO" 11 "impl/bstale-$CT_CORE" 'state="MERGED"'
ct_pr "$CT_REPO" 12 "impl/bstale-$CT_CLI" 'state="MERGED"'
ct_write_db
if open_run bstale true; then
    record bstale ct_record_node "$CT_CORE" "$CT_REPO" 11
    record bstale ct_record_node "$CT_CLI" "$CT_REPO" 12
    record bstale ct_record_cascade pushed "$CT_HEAD"
    (cd "$REPO" && git rm -q "docs/plans/PLAN-bstale.md" && git commit -q -m "chore: cascade")
    # The render before evaluate-coordination couldn't post, and recorded it.
    printf '%s' "coordination:body-stale" | k context add execute-bstale merge_attempts
    finish bstale "done:ready-awaiting-merge"
fi
expect_terminal bstale ready_awaiting_merge outcome=ready-awaiting-merge reason=merge-refused:body-stale \
    "pr=$COORD_URL" waiting=+

# --- done_error -------------------------------------------------------------------

ct_case setup-blocked
fixture blocked
ct_write_db
# $KOTO_LEGACY_ENV_ARG: #483.
k init execute-blocked $KOTO_LEGACY_ENV_ARG --template "$TPL" --var PLAN_DOC=docs/plans/PLAN-blocked.md --var PLAN_SLUG=blocked \
    --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" --var MERGE=false >"$CASE/init.out" 2>&1 \
    || fail "koto init execute-blocked: $(cat "$CASE/init.out")"
k next execute-blocked --with-data '{"setup_status":"blocked","detail":"probe"}' --no-cleanup >"$CASE/next.json" 2>&1
expect_terminal blocked done_error outcome=error step=execute:coord_setup
body_posts blocked 0

# A typed setup stop ends at done_error with its code as the literal reason.
ct_case setup-stop
fixture stop
ct_write_db
# $KOTO_LEGACY_ENV_ARG: #483.
k init execute-stop $KOTO_LEGACY_ENV_ARG --template "$TPL" --var PLAN_DOC=docs/plans/PLAN-stop.md --var PLAN_SLUG=stop \
    --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" --var MERGE=false >"$CASE/init.out" 2>&1 \
    || fail "koto init execute-stop: $(cat "$CASE/init.out")"
k next execute-stop --with-data '{"setup_status":"store-mismatch","detail":"probe"}' --no-cleanup >"$CASE/next.json" 2>&1
expect_terminal stop done_error outcome=error step=execute:coord_setup reason=store-mismatch
body_posts stop 0
OUT=$(k status execute-stop | bash "$SCRIPT_DIR/print-exit.sh")
grep -qx 'reason=store-mismatch' <<<"$OUT" && pass "print-exit.sh renders the setup stop's reason" \
    || fail "the setup stop's exit lines: [$OUT]"

# --- follow-ups -------------------------------------------------------------------
#
# A --follow-up on a new run names no recorded node PR: setup stops
# follow-up-node, seals nothing, and the run ends at done_error naming it.
ct_case fu-stop
fixture fustop
# No follow-up PR in the model: the stop comes before any read of it.
ct_write_db
# FOLLOW_UP carries `<node> <url>`, as execute-open.sh builds it from
# --follow-up <node>=<url> (koto's own value allowlist has no `=`), and the
# directive hands it to setup verbatim.
FU_VAL="$CT_CORE https://github.com/acme/repo-a/pull/21"
# $KOTO_LEGACY_ENV_ARG: #483.
k init execute-fustop $KOTO_LEGACY_ENV_ARG --template "$TPL" --var PLAN_DOC=docs/plans/PLAN-fustop.md --var PLAN_SLUG=fustop \
    --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" --var MERGE=false --var FOLLOW_UP="$FU_VAL" >"$CASE/init.out" 2>&1 \
    || fail "koto init execute-fustop: $(cat "$CASE/init.out")"
FU_SETUP=$(cd "$REPO" && bash "$SCRIPT_DIR/record-coord-setup.sh" --session execute-fustop --plan docs/plans/PLAN-fustop.md \
    --follow-up "$FU_VAL" 2>"$CASE/setup.err"); FU_RC=$?
if [ "$FU_RC" -eq 71 ] && [ "$FU_SETUP" = stop=follow-up-node ]; then
    pass "a --follow-up on a new run stops setup follow-up-node"
    k next execute-fustop --with-data '{"setup_status":"follow-up-node","detail":"probe"}' --no-cleanup >"$CASE/next.json" 2>&1
else
    fail "fu-stop setup: exit $FU_RC, out [$FU_SETUP]; $(cat "$CASE/setup.err")"
fi
expect_terminal fustop done_error outcome=error step=execute:coord_setup reason=follow-up-node
body_posts fustop 0
if k context exists execute-fustop run/setup >/dev/null 2>&1; then
    fail "fu-stop: setup sealed run/setup"
else
    pass "fu-stop: no run/setup was sealed"
fi

# fu_run <slug> <merge> <follow-up key=json ...> -- both nodes recorded and
# MERGED, and follow-up #21 recorded against core, reaching the model (like
# the node PRs) only after setup sealed the record.
fu_run() {
    local slug="$1" merge="$2"
    shift 2
    fixture "$slug"
    ct_pr "$CT_REPO" 11 "impl/$slug-$CT_CORE" 'state="MERGED"'
    ct_pr "$CT_REPO" 12 "impl/$slug-$CT_CLI" 'state="MERGED"'
    ct_follow_up_pr "$CT_REPO" 21 "$@"
    ct_write_db
    if open_run "$slug" "$merge"; then
        record "$slug" ct_record_node "$CT_CORE" "$CT_REPO" 11
        record "$slug" ct_record_node "$CT_CLI" "$CT_REPO" 12
        record "$slug" ct_record_follow_up "$CT_CORE" "$CT_REPO" 21
        finish "$slug" "done:ready-awaiting-merge"
    fi
}
FU21_URL="https://github.com/acme/repo-a/pull/21"

# A follow-up closed unmerged holds the coordination PR, and the run ends
# ready naming it.
ct_case fu-closed
fu_run fuclosed true 'state="CLOSED"'
expect_terminal fuclosed ready_awaiting_merge outcome=ready-awaiting-merge "reason=follow-up-closed:$FU21_URL"
case "$(payload fuclosed waiting)" in
    *"$FU21_URL:human"*) pass "fu-closed: the closed follow-up waits on a human" ;;
    *) fail "fu-closed: waiting [$(payload fuclosed waiting)]" ;;
esac
if ct_calls | grep -q '^pr merge'; then fail "fu-closed: a merge was called"; else pass "fu-closed: no merge while the follow-up is closed"; fi

# An open one, without --merge, waits on the merge being asked for.
ct_case fu-open
fu_run fuopen false
expect_terminal fuopen ready_awaiting_merge outcome=ready-awaiting-merge reason=merge-not-requested
case "$(payload fuopen waiting)" in
    *"$FU21_URL:human"*) pass "fu-open: the open follow-up is among the waiting PRs" ;;
    *) fail "fu-open: waiting [$(payload fuopen waiting)]" ;;
esac

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
#
# The walk takes the edge through its real input. verdict_merged is
# overridable: false, and from koto 0.14 (koto#257) a directed hop across it is
# refused unless the gate's current result satisfies the edge, so the verdict
# the record script would have written, `merged`, goes into coord_verdict
# first. A plain tick can't stand in for the hop: it re-runs the record script,
# which clears the key before failing on the missing home_repo.
ct_case confirm-overrides
fixture cov2
CT_COORD_STATE=MERGED
ct_write_db
if open_run cov2 true; then
    k context remove execute-cov2 home_repo >/dev/null 2>&1
    finish cov2 "done:merged"
    printf 'merged' | k context add execute-cov2 coord_verdict >/dev/null 2>&1
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
    tick execute-cov2 --with-data '{"confirm_status":"unreadable"}' --no-cleanup
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
# From koto 0.24.0 record_keep pins the root on the way to `merged`, and a
# pinned session outlives a bare terminal tick too; below it nothing is
# pinned and the bare tick disposes of the session. Either way the bare tick
# alone keeps nothing: a session that survives it holds the pin.
if ! k context get execute-drop repos >/dev/null 2>&1; then
    pass "a terminal reached without --no-cleanup loses its context (control: nothing pinned it)"
elif k context exists execute-drop koto/links/pin >/dev/null 2>&1; then
    pass "a terminal reached without --no-cleanup is kept only by record_keep's pin"
else
    fail "a terminal reached without --no-cleanup kept its context with no pin -- the control did not fire"
fi

# --- the record across a pause --------------------------------------------------------
#
# A run paused at paused_awaiting_merges, re-invoked through execute-open.sh:
# koto replaces the finished session, and the opener carries its run/ keys and
# run_id into the replacement. A second run's carry is made to fail after the
# replacement (a koto wrapper refusing every `context add` of a run/ key), and
# the next open carries it from the snapshot the first one kept.

# shellcheck source=run-record-lib.sh
. "$SCRIPT_DIR/run-record-lib.sh"
REAL_KOTO=$(command -v koto)
STATE_ROOT="$CT_WORK/state"
# opener <slug> [bin dir] -- execute-open.sh in the case's checkout, with the
# PLAN as its one token. Sets OUT and RC.
opener() {
    local d
    d=$(cd "$REPO" && bash "$REPO_ROOT/scripts/koto-open.sh" --alloc-dir) || { OUT=""; RC=99; return; }
    jq -nc --arg p "docs/plans/PLAN-$1.md" '[$p]' > "$d/tokens.json"
    OUT=$(cd "$REPO" && env PATH="${2:+$2:}$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT_VAR" SHIRABE_STATE_DIR="$STATE_ROOT" \
        bash "$SCRIPT_DIR/execute-open.sh" "$d/tokens.json" 2>"$CASE/open.err")
    RC=$?
}
record_of() { (cd "$REPO" && rr_record "execute-$1" 2>/dev/null); }
# paused_run <slug> -- a run whose core node is recorded and awaiting a human,
# ended at paused_awaiting_merges with a merge attempt recorded.
paused_run() {
    ct_pr "$CT_REPO" 11 "impl/$1-$CT_CORE"
    ct_write_db
    open_run "$1" false || return 1
    record "$1" ct_record_node "$CT_CORE" "$CT_REPO" 11
    printf '%s' "$CT_CORE:merge-not-observed" | k context add "execute-$1" merge_attempts >/dev/null 2>&1
    finish "$1" "pause"
    [ "$(state_of "$1")" = paused_awaiting_merges ]
}

ct_case carry
fixture pcarry
if paused_run pcarry; then
    BEFORE=$(record_of pcarry)
    ID_BEFORE=$(k context get execute-pcarry run_id 2>/dev/null)
    opener pcarry
    AFTER=$(record_of pcarry)
    if [ "$RC" -eq 0 ] && grep -qx 'opened=replaced' <<<"$OUT" && grep -qx 'carried=2' <<<"$OUT" \
        && [ "$(state_of pcarry)" = coord_setup ]; then
        pass "a paused run re-invoked: replaced, and its two run/ keys carried (carried=2)"
    else
        fail "carry: exit $RC, out [$OUT], state $(state_of pcarry); $(cat "$CASE/open.err")"
    fi
    if [ -n "$BEFORE" ] && [ "$BEFORE" != "{}" ] && [ "$AFTER" = "$BEFORE" ]; then
        pass "every run/ key in the replacement is byte-equal to the paused session's"
    else
        fail "the carried record differs: before [$BEFORE], after [$AFTER]"
    fi
    [ "$(k context get execute-pcarry run_id 2>/dev/null)" = "$ID_BEFORE" ] \
        && pass "the replacement continues with the same run_id" \
        || fail "run_id after the carry: [$(k context get execute-pcarry run_id 2>/dev/null)], was [$ID_BEFORE]"
    if k context exists execute-pcarry merge_attempts >/dev/null 2>&1; then
        fail "the replacement still holds merge_attempts"
    else
        pass "the replacement's merge attempts are empty"
    fi
    [ ! -e "$STATE_ROOT/execute-carry/execute-pcarry" ] && pass "the snapshot is removed once the carry succeeds" \
        || fail "the snapshot was left behind after a successful carry"
    if grep -q 'execute-carry' <<<"$OUT"; then fail "a report line names the snapshot's path"; else pass "no report line names a local path"; fi
else
    fail "could not end a run at paused_awaiting_merges (at $(state_of pcarry)): $(head -c 600 "$CASE/next.json")"
fi

ct_case carry-crash
fixture pcrash
if paused_run pcrash; then
    BEFORE=$(record_of pcrash)
    ID_BEFORE=$(k context get execute-pcrash run_id 2>/dev/null)
    CRASH_BIN="$CASE/crash-bin"
    mkdir -p "$CRASH_BIN"
    cat > "$CRASH_BIN/koto" <<STUB
#!/usr/bin/env bash
case "\$1 \$2 \$4" in "context add run/"*) exit 1 ;; esac
exec "$REAL_KOTO" "\$@"
STUB
    chmod +x "$CRASH_BIN/koto"
    opener pcrash "$CRASH_BIN"
    if [ "$RC" -eq 70 ] && grep -qx 'opened=replaced' <<<"$OUT" && grep -qx 'carry=pending' <<<"$OUT" \
        && grep -qx 'failed=carry' <<<"$OUT" && [ -f "$STATE_ROOT/execute-carry/execute-pcrash/record.json" ] \
        && ! k context exists execute-pcrash run/setup >/dev/null 2>&1; then
        pass "a carry that fails after the replacement: failed=carry, exit 70, the snapshot kept, no run/setup"
    else
        fail "crash: exit $RC, out [$OUT], snapshot $(ls "$STATE_ROOT/execute-carry" 2>&1); $(cat "$CASE/open.err")"
    fi
    opener pcrash
    if [ "$RC" -eq 0 ] && grep -qx 'carried=2' <<<"$OUT" && [ "$(record_of pcrash)" = "$BEFORE" ] \
        && [ ! -e "$STATE_ROOT/execute-carry/execute-pcrash" ] \
        && [ "$(k context get execute-pcrash run_id 2>/dev/null)" = "$ID_BEFORE" ]; then
        pass "the next open carries the record from the kept snapshot and removes it"
    else
        fail "after the crash: exit $RC, out [$OUT], record [$(record_of pcrash)]; $(cat "$CASE/open.err")"
    fi
else
    fail "could not end a run at paused_awaiting_merges (at $(state_of pcrash)): $(head -c 600 "$CASE/next.json")"
fi

# The same pause, with the cascade having deleted the PLAN before the
# re-invocation: the opener reads the mode from the record, and setup reads
# repos from run/setup.
ct_case carry-plan-gone
fixture pgone
if paused_run pgone; then
    BEFORE=$(record_of pgone)
    (cd "$REPO" && git rm -q "docs/plans/PLAN-pgone.md" && git commit -q -m "chore: cascade")
    opener pgone
    if [ "$RC" -eq 0 ] && grep -qx 'opened=replaced' <<<"$OUT" && grep -qx 'carried=2' <<<"$OUT" \
        && [ "$(state_of pgone)" = coord_setup ] && [ "$(record_of pgone)" = "$BEFORE" ]; then
        pass "a paused run whose PLAN is gone re-invokes on the coordinated template, its record carried"
    else
        fail "plan gone: exit $RC, out [$OUT], state $(state_of pgone); $(cat "$CASE/open.err")"
    fi
    SOUT=$(cd "$REPO" && bash "$SCRIPT_DIR/record-coord-setup.sh" --session execute-pgone --plan docs/plans/PLAN-pgone.md 2>"$CASE/setup.err")
    SRC=$?
    k next execute-pgone --no-cleanup >/dev/null 2>&1
    if [ "$SRC" -eq 0 ] && grep -qx record=existing <<<"$SOUT" && grep -qx repos=acme/repo-a <<<"$SOUT" \
        && [ "$(state_of pgone)" = coord_loop ]; then
        pass "setup over the carried record with the PLAN gone reads repos from run/setup and reaches coord_loop"
    else
        fail "setup with the PLAN gone: exit $SRC, out [$SOUT], state $(state_of pgone); $(cat "$CASE/setup.err")"
    fi
else
    fail "could not end a run at paused_awaiting_merges (at $(state_of pgone)): $(head -c 600 "$CASE/next.json")"
fi

# --- recovery ----------------------------------------------------------------------------
#
# A session with no record. open_recovering inits the session, runs setup with
# no run_id written by the harness, and ticks; setup's own stdout is kept in
# $CASE/setup.out and its exit in SETUP_RC.
open_recovering() { # open_recovering <slug> <merge> [extra init args]
    local s="execute-$1"
    shift
    local merge="$1"
    shift
    # $KOTO_LEGACY_ENV_ARG: #483.
    k init "$s" $KOTO_LEGACY_ENV_ARG --template "$TPL" --var PLAN_DOC="docs/plans/PLAN-$CT_SLUG.md" --var PLAN_SLUG="$CT_SLUG" \
        --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" --var MERGE="$merge" "$@" >"$CASE/init.out" 2>&1 \
        || { fail "koto init $s: $(cat "$CASE/init.out")"; return 1; }
    [ -n "${CARRIED_ID:-}" ] && printf '%s' "$CARRIED_ID" | k context add "$s" run_id >/dev/null 2>&1
    (cd "$REPO" && bash "$SCRIPT_DIR/record-coord-setup.sh" --session "$s" --plan "docs/plans/PLAN-$CT_SLUG.md" \
        ${STORE_FLAG:+--store "$STORE_FLAG"} >"$CASE/setup.out" 2>"$CASE/setup.err")
    SETUP_RC=$?
    return 0
}
REC_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# On session, a start with no record and a carried run_id stops session-absent
# and ends at done_error naming it, with no body edit.
ct_case session-absent
fixture sabs
ct_write_db
CARRIED_ID="$REC_ID" STORE_FLAG=session open_recovering sabs false --var STORE=session
if [ "$SETUP_RC" -eq 71 ] && [ "$(cat "$CASE/setup.out")" = stop=session-absent ]; then
    k next execute-sabs --with-data '{"setup_status":"session-absent","detail":"probe"}' --no-cleanup >"$CASE/next.json" 2>&1
fi
expect_terminal sabs done_error outcome=error step=execute:coord_setup reason=session-absent
if ct_calls | grep -q '^pr edit '; then fail "session-absent: a body was edited"; else pass "session-absent: no gh pr edit"; fi

# On github, a rendered run line every node PR's marker matches recovers; the
# run continues with the live head, and the result says it recovered.
ct_case recovered
fixture rec
ct_pr "$CT_REPO" 11 "impl/rec-$CT_CORE" "index=\"$REC_ID\""
ct_rendered_body "$CASE/body.md" "$REC_ID" github "$CT_CORE=11"
ct_write_db "$CASE/body.md"
open_recovering rec false
if [ "$SETUP_RC" -eq 0 ] && grep -qx "recovered=$COORD_URL" "$CASE/setup.out"; then
    pass "setup recovers the run from its rendering (recovered=$COORD_URL)"
    k next execute-rec --no-cleanup >/dev/null 2>&1
    finish rec "pause"
else
    fail "recovery setup: exit $SETUP_RC, out [$(cat "$CASE/setup.out")]; $(cat "$CASE/setup.err")"
fi
expect_terminal rec paused_awaiting_merges outcome=paused-awaiting-merges "recovered=$COORD_URL"
[ "$(k context get execute-rec run_id 2>/dev/null)" = "$REC_ID" ] && pass "the recovered run's run_id is the run line's" \
    || fail "recovered run_id: [$(k context get execute-rec run_id 2>/dev/null)]"
OUT=$(k status execute-rec | bash "$SCRIPT_DIR/print-exit.sh")
grep -qx "recovered=$COORD_URL" <<<"$OUT" && pass "print-exit.sh prints recovered=" || fail "recovered exit lines: [$OUT]"

# On github, a start with no record, no carried run_id, and a body with no
# index line, beside an owned PR on a PLAN node's branch, is a run that started
# and left nothing to rebuild it from: setup stops coordination-index-missing,
# writes nothing, and the run ends at done_error naming it.
ct_case index-missing
fixture ixmiss
ct_pr "$CT_REPO" 11 "impl/ixmiss-$CT_CORE"
ct_write_db
open_recovering ixmiss false
if [ "$SETUP_RC" -eq 71 ] && [ "$(cat "$CASE/setup.out")" = stop=coordination-index-missing ]; then
    pass "an owned node PR beside a body with no index line stops setup coordination-index-missing"
    k next execute-ixmiss --with-data '{"setup_status":"coordination-index-missing","detail":"probe"}' --no-cleanup >"$CASE/next.json" 2>&1
else
    fail "index missing: setup exit $SETUP_RC, out [$(cat "$CASE/setup.out")]; $(cat "$CASE/setup.err")"
fi
expect_terminal ixmiss done_error outcome=error step=execute:coord_setup reason=coordination-index-missing
body_posts ixmiss 0
if ct_calls | grep -Eq '^(pr (edit|comment|merge|ready|create|close)|issue |api .*comments)'; then
    fail "index missing: a write reached GitHub: $(ct_calls | grep -E '^(pr (edit|comment|merge|ready|create|close)|issue |api .*comments)')"
else
    pass "index missing: no body post, comment, or merge"
fi
if k context exists execute-ixmiss run/setup >/dev/null 2>&1; then
    fail "index missing: setup sealed run/setup"
else
    pass "index missing: no run/setup was sealed"
fi

# --- --koto-leg -----------------------------------------------------------------------

ct_case leg
fixture leg
ct_pr "$CT_REPO" 11 "impl/leg-$CT_CORE"
ct_write_db
REQ=$(k request create --with-data '{"legs":[{"name":"execute","role":"execute","template":["execute.md","execute-coordinated.md"],"inputs":{}}]}' \
    --requested-by coord-engine-test --coordinator-of-record coord-engine-test 2>/dev/null \
    | jq -r 'if type == "object" then (.id // .request_id // .request // "") else . end' 2>/dev/null)
if [ -z "$REQ" ] || [ "$REQ" = null ]; then
    fail "koto request create printed no request id"
else
    if open_run leg false --koto-leg "$REQ:execute"; then
        record leg ct_record_node "$CT_CORE" "$CT_REPO" 11
        finish leg "pause"
    fi
    # The leg holds a result only once the run reached its terminal, so a run
    # that stopped short is reported as that, not as an empty payload.
    if [ "$(state_of leg)" != paused_awaiting_merges ]; then
        fail "the leg's run stopped at $(state_of leg), not paused_awaiting_merges, so nothing reached the leg: $(head -c 600 "$CASE/next.json")"
    else
        LEG=$(k request get "$REQ" 2>/dev/null | jq -c '[.. | objects | select(has("name") and .name == "execute")][0] // {}')
        P=$(printf '%s' "$LEG" | jq -c '[.. | objects | select(has("outcome") and has("repos"))][0] // {}')
        if [ "$(printf '%s' "$P" | jq -r '.outcome')" = paused-awaiting-merges ] \
            && [ -n "$(printf '%s' "$P" | jq -r '.pr // ""')" ] && [ -n "$(printf '%s' "$P" | jq -r '.repos // ""')" ] \
            && [ -n "$(printf '%s' "$P" | jq -r '.resume // ""')" ] && [ -n "$(printf '%s' "$P" | jq -r '.waiting // ""')" ]; then
            pass "the execute leg's promoted payload carries outcome, pr, repos, resume, and waiting"
        else
            fail "the leg's payload: $P; leg: $(head -c 800 <<<"$LEG")"
        fi
        if grep -q '"execute-coordinated.md"' <<<"$LEG" && grep -q '"promoted"' <<<"$LEG"; then
            pass "the leg was promoted from a session built from execute-coordinated.md"
        else
            fail "the leg's template or source: $(head -c 800 <<<"$LEG")"
        fi
    fi
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
