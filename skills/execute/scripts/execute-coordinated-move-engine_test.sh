#!/usr/bin/env bash
# execute-coordinated-move-engine_test.sh -- a coordinated run stopped after
# its first node's merge, imported into a second workspace on the same host,
# and resumed there to its merge (PRD R12), on real koto over koto's cloud
# backend (skills/coordinate/scripts/testdata/cloud-hosts.sh over its
# fake-s3.py), with the shipped execute-coordinated.md and the real scripts
# the loop runs (execute-open.sh, record-coord-setup.sh, coordinated-next.sh,
# coord-merge.sh, coord-render.sh, run-record.sh) against the eval gh shim's
# repository model (coord-test-helpers.sh).
#
# Layout: one simulated host h with two workspaces, A (`work`) and B (`b`),
# each a clone of one bare origin on docs/move holding PLAN-move.md (node
# pr-repo-a-core, then pr-repo-a-cli waiting on it). One gh model serves both.
# A second host, h2, holds only the session the refused import meets.
# The coordination PR is #10, and a hook (CT_GH_HOOK) puts back the same body
# before every gh call -- a Part 1 and the declaration marker, no index line
# and no run= or store= line -- so every read the run makes is served a body
# that records nothing of the run, and the run can only go on from its record.
# The hook also keeps each body the run posts.
#
# In A: execute-open.sh opens a new run and setup seals its record; node
# core's PR #11 is opened and recorded; its merge is accepted by a queue but
# not seen landing; the loop pauses, and the run stops at
# paused_awaiting_merges. The queue then lands #11.
#
# The move: an import onto a live execute-move session is refused with koto's
# code and leaves both sessions as they were; then `skill-session.sh import
# execute move --from <A>` in B imports the run, and a tick in A answers
# session_migrated.
#
# The refused import runs on a second host, h2. koto keeps sessions by name
# per machine ($HOME/.koto/sessions/<name>), so on one host B can't hold a
# live execute-move of its own while A's exists: `koto init` there answers
# "already exists", and an import in B moves A's own session rather than
# colliding with another. A taken name (koto's import_name_taken) needs a
# store that holds a different session under it, which is another host's.
#
# In B: follow-up #21 is opened against core; execute-open.sh replaces the
# imported terminal session and carries its record (same run_id, no recovery
# marker); setup records the follow-up; and the loop runs coordinated-next.sh
# to the end: the follow-up's merge, cli's dispatch (#12) and merge, the
# cascade, and the coordination PR's merge, gated on the body it just
# rendered. The run ends merged.
#
# Asserted: the final state merged with the first workspace's run_id and no
# run/recovered; the live body still holds no index or run line; the last body
# posted indexes core, its follow-up and cli, in that order, each merged at the
# shim's merge commit, with no line for #10; the import refusal's code and the
# untouched sessions; the source's session_migrated.
#
# On one host the koto cache is shared, so the import in B finds the templates
# A compiled; skill-session_test.sh is what shows the import compiles them
# first. Like every engine test here, it adds node PRs to the stub's model only
# after setup has sealed the record, as node-push.sh does in a real run, so
# setup never reads them as a started run. When neither this checkout's path nor a link under TMPDIR passes
# koto's --var allowlist, execute-open.sh can't name a PLUGIN_ROOT koto admits,
# and the suite SKIPs.
#
# Needs koto (with `session import`), jq, git and python3; SKIPs (exit 0)
# without one. With CI set, a koto without `session import` or a path koto
# won't admit fails instead, so the move criterion never passes unexercised.
# Usage: execute-coordinated-move-engine_test.sh
# Exit codes: 0 all pass (or SKIP); 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(CDPATH='' cd "$SKILL_DIR/../.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/execute-coordinated.md"
SS="$REPO_ROOT/scripts/skill-session.sh"
KOTO_OPEN="$REPO_ROOT/scripts/koto-open.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
results() {
    echo
    echo "execute-coordinated-move: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
}

for bin in koto jq git python3; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine-backed cases did not run"; exit 0; }
done
if ! koto session import --help >/dev/null 2>&1; then
    # On CI a koto without the import would let the move criterion pass
    # untested, so it fails there; a local run skips.
    if [ -n "${CI:-}" ]; then
        echo "FAIL: this koto has no session import -- the move cases cannot run on CI"
        exit 1
    fi
    echo "SKIP: this koto has no session import -- no case ran"
    exit 0
fi
# koto's recorded command environment hides this harness's stand-in variables
# from the commands koto runs; the knob keeps the old environment where the
# koto accepts it (scripts/lib/koto-legacy-env.sh; temporary, #483).
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"
# The real engine, not the helpers' context stub.
rm -f "$CT_BIN/koto"

KOTO_ALLOW='^[a-zA-Z0-9._/:@ -]*$'
if [[ $REPO_ROOT =~ $KOTO_ALLOW ]]; then
    PLUGIN_ROOT_VAR="$REPO_ROOT"
else
    ln -s "$REPO_ROOT" "$CT_WORK/plugin"
    if [[ $CT_WORK/plugin =~ $KOTO_ALLOW ]]; then
        PLUGIN_ROOT_VAR="$CT_WORK/plugin"
    else
        echo "SKIP: neither this checkout's path nor a link under TMPDIR passes koto's --var allowlist,"
        echo "      so execute-open.sh can name no PLUGIN_ROOT koto admits -- no case ran"
        [ -z "${CI:-}" ] || { echo "FAIL: a skip on CI would leave the move criterion untested"; exit 1; }
        exit 0
    fi
fi
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT_VAR"

T=$(cd -P "$CT_WORK" && pwd -P) || exit 1
CLOUD_HOSTS_S3="$REPO_ROOT/skills/coordinate/scripts/testdata/fake-s3.py"
# shellcheck source=../../coordinate/scripts/testdata/cloud-hosts.sh
. "$REPO_ROOT/skills/coordinate/scripts/testdata/cloud-hosts.sh"
trap 's3_stop; rm -rf "$CT_WORK"' EXIT
if ! s3_start; then
    fail "the fake S3 server starts: $(cat "$T/s3/log" 2>&1)"
    results
    exit 1
fi
host_make h
ws_make h b
host_make h2
WS_A=$(ws_path h work)
WS_B=$(ws_path h b)
# The suite's git identity, for the host's HOME; one carry root for the host.
cp "$CT_WORK/home/.gitconfig" "$T/hosts/h/userhome/.gitconfig"
export SHIRABE_STATE_DIR="$T/hosts/h/state"

S=execute-move
PLAN=docs/plans/PLAN-move.md
HOME_REPO=acme/repo-a
COORD_URL="https://github.com/acme/repo-a/pull/10"
FU_URL="https://github.com/acme/repo-a/pull/21"
merge_sha_of() { printf 'merge %s#%s' "$1" "$2" | git hash-object --stdin; }

# --- the two workspaces --------------------------------------------------------------

ct_case move
CT_SLUG=move
CT_CB=docs/move
CT_COORD_DRAFT=false
CT_INDEX=""
ct_repo "$WS_A"
ct_plan "$WS_A"
mv "$WS_A/docs/plans/PLAN-t.md" "$WS_A/$PLAN"
git -C "$WS_A" add docs
git -C "$WS_A" commit -q -m "docs: plan"
git -C "$WS_A" push -q origin "$CT_CB"
ORIGIN="$WS_A.origin.git"
git -C "$WS_B" init -q -b main
git -C "$WS_B" remote add origin "$ORIGIN"
git -C "$WS_B" fetch -q origin
git -C "$WS_B" checkout -q -b "$CT_CB" "origin/$CT_CB"
for w in "$WS_A" "$WS_B"; do printf '.koto/\n' >> "$w/.git/info/exclude"; done
# Both workspaces opt in to PR workflow content: the index this case checks
# across the move is rendered only under include, which each open records
# from its checkout's CLAUDE.local.md (pr-workflow-content.sh --record).
for w in "$WS_A" "$WS_B"; do
    printf '## PR Workflow Content: include\n' > "$w/CLAUDE.local.md"
    printf 'CLAUDE.local.md\n' >> "$w/.git/info/exclude"
done

# The body every gh call is served: a Part 1 (the coordination merge's squash
# message is built from it) and the declaration marker, and nothing of the run.
FIXED="$CASE/fixed-body.md"
printf 'Coordination pull request for move.\n\n---\n\n> This is a **coordination PR** for a coordinated effort.\n' > "$FIXED"
ct_write_db "$FIXED"
export EVAL_COORDINATION_CHECKOUT="$WS_A"
export MOVE_POSTED="$CASE/posted" MOVE_FIXED_BODY="$FIXED"
mkdir -p "$MOVE_POSTED"
cat > "$CASE/hook.sh" <<'HOOK'
# Keep the body a `pr edit` posts, then put back the fixed body: every call,
# reads included, is served the body that records nothing of the run.
db="$GH_CALL_LOG.d/db.json"
if [ "${1:-} ${2:-}" = "pr edit" ]; then
    prev=""
    for a in "$@"; do
        if [ "$prev" = --body-file ]; then
            n=$(find "$MOVE_POSTED" -type f | wc -l | tr -d ' ')
            cp "$a" "$MOVE_POSTED/$(printf '%03d' $((n + 1))).md"
        fi
        prev="$a"
    done
fi
[ -f "$db" ] || exit 0
jq --rawfile b "$MOVE_FIXED_BODY" '(.prs[] | select(.number == 10) | .body) = $b' "$db" > "$db.reset" \
    && mv "$db.reset" "$db"
HOOK
export CT_GH_HOOK="$CASE/hook.sh"

A() { ws_on h work "$@"; }
B() { ws_on h b "$@"; }
C() { ws_on h2 work "$@"; }
LIVE="$GH_CALL_LOG.d/db.json"
# model_pr <ct_pr args...> | model_follow_up <repo> <n> -- one PR added to the
# live model the shim built, as a run's own push or a person would open it.
model_add() {
    jq --argjson o "$(printf '%s' "$CT_PRS" | jq -c '.[0]')" '.prs += [$o]' "$LIVE" > "$LIVE.tmp" && mv "$LIVE.tmp" "$LIVE"
}
model_pr() { local saved="$CT_PRS"; CT_PRS='[]'; ct_pr "$@"; model_add; CT_PRS="$saved"; }
model_follow_up() { local saved="$CT_PRS"; CT_PRS='[]'; ct_follow_up_pr "$@"; model_add; CT_PRS="$saved"; }
# rr <runner> <verb> <json> -- one run-record.sh write in a workspace, as
# node-push.sh makes it.
rr() {
    local on="$1"
    printf '%s' "$3" > "$CASE/rr.json"
    "$on" bash "$SCRIPT_DIR/run-record.sh" "$2" --session "$S" --json "$CASE/rr.json" >/dev/null </dev/null 2>"$CASE/rr.err" \
        || fail "run-record.sh $2 in the workspace: $(cat "$CASE/rr.err")"
}
rr_node() { rr "$1" push "$(jq -cn --arg k "run/node/$2" --arg r "$HOME_REPO" --argjson p "$3" --arg h "$CT_HEAD" '{($k): {repo: $r, pr: $p, head: $h}}')"; }
render() { "$1" bash "$SCRIPT_DIR/coord-render.sh" --session "$S" --slug move --home-repo "$HOME_REPO" --coord-branch "$CT_CB" </dev/null 2>>"$CASE/render.err"; }
merge() { "$1" bash "$SCRIPT_DIR/coord-merge.sh" --session "$S" --slug move --home-repo "$HOME_REPO" --coord-branch "$CT_CB" --node "$2" </dev/null 2>>"$CASE/merge.err"; }
# attempts <runner> -- the session's merge_attempts, empty when it holds none.
attempts() {
    if "$1" koto context exists "$S" merge_attempts >/dev/null 2>&1; then
        "$1" koto context get "$S" merge_attempts 2>/dev/null
    fi
    return 0
}
next_line() {
    "$1" bash "$SCRIPT_DIR/coordinated-next.sh" --session "$S" --plan "$PLAN" --slug move --repos "$HOME_REPO" \
        --home-repo "$HOME_REPO" --coord-branch "$CT_CB" --merge true --attempts "$(attempts "$1")" --run-id "$ID_A" </dev/null 2>>"$CASE/next.err"
}
state_in() { "$1" koto status "$S" 2>/dev/null | jq -r '.current_state // "gone"'; }
payload_in() { "$1" koto status "$S" 2>/dev/null | jq -r --arg k "$2" '.result.payload[$k] // ""'; }
# record_of <runner> -- every run/ key of the session and its value, and run_id.
record_of() {
    local k
    for k in $("$1" koto context list "$S" --prefix run/ 2>/dev/null | jq -r '.[]') run_id; do
        printf '%s=' "$k"
        "$1" koto context get "$S" "$k" 2>/dev/null
        printf '\n'
    done
}
# open_execute <runner> <tokens-json> -- execute-open.sh as SKILL.md runs it,
# with the tokens in a private directory outside the work tree.
open_execute() {
    local d
    d=$("$1" bash "$KOTO_OPEN" --alloc-dir) || { fail "koto-open.sh --alloc-dir"; return 1; }
    printf '%s' "$2" > "$d/tokens.json"
    OPEN_OUT=$("$1" bash "$SCRIPT_DIR/execute-open.sh" "$d/tokens.json" 2>"$CASE/open.err")
    OPEN_RC=$?
}

# --- workspace A: the run, paused after its first merge call ------------------------------

echo "== workspace A =="
open_execute A '["docs/plans/PLAN-move.md","--merge"]'
if [ "$OPEN_RC" -eq 0 ] && grep -qx opened=new <<<"$OPEN_OUT" && grep -qx "session=$S" <<<"$OPEN_OUT"; then
    pass "A: execute-open.sh opens a new coordinated run"
else
    fail "A: execute-open.sh: rc=$OPEN_RC out=[$OPEN_OUT] stderr=[$(cat "$CASE/open.err")]"
fi
SETUP=$(A bash "$SCRIPT_DIR/record-coord-setup.sh" --session "$S" --plan "$PLAN" </dev/null 2>"$CASE/setup.err")
grep -qx record=new <<<"$SETUP" && pass "A: setup seals a new run record" \
    || fail "A: setup: [$SETUP] stderr=[$(cat "$CASE/setup.err")]"
A koto next "$S" --no-cleanup >/dev/null 2>"$CASE/tick.err"
[ "$(state_in A)" = coord_loop ] && pass "A: the run enters coord_loop" || fail "A: at $(state_in A): $(cat "$CASE/tick.err")"
ID_A=$(A koto context get "$S" run_id 2>/dev/null)
[[ $ID_A =~ ^[0-9a-f]{32}$ ]] && pass "A: setup minted the run's identity" || fail "A: run_id [$ID_A]"

# Node core's PR, which a merge queue accepts and lands only later.
model_pr "$HOME_REPO" 11 "impl/move-$CT_CORE" 'merge="stays-open"'
rr_node A "$CT_CORE" 11
render A > "$CASE/render.out"
grep -qx body=posted "$CASE/render.out" && pass "A: the body is posted after core's push" || fail "A: render [$(cat "$CASE/render.out")]"
LINE=$(next_line A)
[ "$LINE" = "merge:$CT_CORE" ] && pass "A: the loop's next action is core's merge" || fail "A: next [$LINE] $(tail -2 "$CASE/next.err")"
MOUT=$(merge A "$CT_CORE")
if grep -q '^merge-called:' <<<"$MOUT" && grep -qx not-merged:merge-not-observed <<<"$MOUT"; then
    pass "A: core's merge is called and not seen landing (a queue accepted it)"
else
    fail "A: core's merge [$MOUT] $(tail -2 "$CASE/merge.err")"
fi
LINE=$(next_line A)
[ "$LINE" = pause ] && pass "A: with the merge attempted, the loop pauses" || fail "A: next after the attempt [$LINE]"
A koto next "$S" --with-data '{"loop_exit":"pause","loop_line":"pause"}' --no-cleanup >"$CASE/next.json" 2>&1
if [ "$(state_in A)" = paused_awaiting_merges ] \
    && [ "$(payload_in A resume)" = "/execute docs/plans/PLAN-move.md --merge" ]; then
    pass "A: the run stops at paused_awaiting_merges, resume=/execute docs/plans/PLAN-move.md --merge"
else
    fail "A: stopped at $(state_in A) resume=[$(payload_in A resume)]: $(head -c 600 "$CASE/next.json")"
fi
# The queue lands core's PR.
gh shim-mark-merged "$HOME_REPO" 11

# --- the move ------------------------------------------------------------------------------

echo "== the import =="
# A live execute-move on h2, whose store holds its own session under the
# name: the import is refused, and both sessions stay. $KOTO_LEGACY_ENV_ARG: #483.
C koto init "$S" $KOTO_LEGACY_ENV_ARG --template "$TEMPLATE" --var PLAN_DOC="$PLAN" --var PLAN_SLUG=move \
    --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" --var MERGE=false >"$CASE/init.out" 2>&1 \
    || fail "h2: koto init of a live $S: $(cat "$CASE/init.out")"
REC_A=$(record_of A)
CTX_C=$(C koto context list "$S" 2>/dev/null)
IMP=$(C bash "$SS" import execute move --from "$WS_A" 2>"$CASE/import.err")
IMP_RC=$?
CODE=$(sed -n "s/^failed=$S code=//p" <<<"$IMP")
if [ "$IMP_RC" -eq 1 ] && [[ $CODE =~ ^[a-z_]+$ ]] && [ "$CODE" != unparseable ]; then
    pass "h2: an import onto a live $S is refused with koto's code ($CODE)"
else
    fail "h2: the import onto a live session: rc=$IMP_RC out=[$IMP] stderr=[$(cat "$CASE/import.err")]"
fi
[ "$(state_in A)" = paused_awaiting_merges ] && [ "$(record_of A)" = "$REC_A" ] \
    && pass "A: the refused import leaves A's session and record as they were" \
    || fail "A: after the refused import: at $(state_in A)"
if A koto status "$S" > "$CASE/status-a.json" 2>&1 && ! grep -q session_migrated "$CASE/status-a.json" \
    && jq -e '(.migrated // false) != true' "$CASE/status-a.json" >/dev/null 2>&1; then
    pass "A: the session is not marked migrated"
else
    fail "A: status after the refused import: $(head -c 300 "$CASE/status-a.json")"
fi
[ "$(state_in C)" = coord_setup ] && [ "$(C koto context list "$S" 2>/dev/null)" = "$CTX_C" ] \
    && pass "h2: the live session is unchanged, at coord_setup with the same context" \
    || fail "h2: the live session after the refused import: at $(state_in C)"

IMP=$(B bash "$SS" import execute move --from "$WS_A" 2>"$CASE/import.err")
IMP_RC=$?
[ "$IMP_RC" -eq 0 ] && [ "$IMP" = "imported=$S" ] && pass "B: skill-session.sh import execute imports the run under its own name" \
    || fail "B: the import: rc=$IMP_RC out=[$IMP] stderr=[$(cat "$CASE/import.err")]"
SRC=$(A koto next "$S" --no-cleanup 2>&1)
SRC_RC=$?
if [ "$SRC_RC" -ne 0 ] && grep -q session_migrated <<<"$SRC"; then
    pass "A: the source's tick answers session_migrated"
else
    fail "A: the source's tick: rc=$SRC_RC [${SRC:0:300}]"
fi

# --- workspace B: the run resumed to its merge --------------------------------------------

echo "== workspace B =="
model_follow_up "$HOME_REPO" 21
open_execute B '["docs/plans/PLAN-move.md","--merge","--follow-up","pr-repo-a-core=https://github.com/acme/repo-a/pull/21"]'
if [ "$OPEN_RC" -eq 0 ] && grep -qx opened=replaced <<<"$OPEN_OUT" && grep -q '^carried=[1-9]' <<<"$OPEN_OUT" \
    && grep -qx "session=$S" <<<"$OPEN_OUT"; then
    pass "B: execute-open.sh replaces the imported terminal session and carries its record"
else
    fail "B: execute-open.sh: rc=$OPEN_RC out=[$OPEN_OUT] stderr=[$(cat "$CASE/open.err")]"
fi
[ "$(B koto context get "$S" run_id 2>/dev/null)" = "$ID_A" ] && pass "B: the run keeps A's run_id" \
    || fail "B: run_id [$(B koto context get "$S" run_id 2>/dev/null)], A's [$ID_A]"
if B koto context exists "$S" recovered >/dev/null 2>&1; then fail "B: the open left a recovered key"; else pass "B: no recovered key"; fi
[ -z "$(find "$SHIRABE_STATE_DIR" -path "*/execute-carry/$S/*" -type f 2>/dev/null)" ] \
    && pass "B: the carry's snapshot is gone after it" || fail "B: a snapshot remains under the carry root"

SETUP=$(B bash "$SCRIPT_DIR/record-coord-setup.sh" --session "$S" --plan "$PLAN" \
    --follow-up "$CT_CORE $FU_URL" </dev/null 2>"$CASE/setup.err")
if grep -qx record=existing <<<"$SETUP" && grep -qx "follow-up=recorded:$FU_URL" <<<"$SETUP" \
    && ! grep -q '^recovered=' <<<"$SETUP"; then
    pass "B: setup finds the record, records the follow-up, and recovers nothing"
else
    fail "B: setup: [$SETUP] stderr=[$(cat "$CASE/setup.err")]"
fi
if B koto context exists "$S" run/recovered >/dev/null 2>&1; then fail "B: run/recovered was written"; else pass "B: no run/recovered"; fi
B koto next "$S" --no-cleanup >/dev/null 2>"$CASE/tick.err"
[ "$(state_in B)" = coord_loop ] && pass "B: the run enters coord_loop" || fail "B: at $(state_in B): $(cat "$CASE/tick.err")"

STEPS=0
ACTIONS=""
while :; do
    STEPS=$((STEPS + 1))
    if [ "$STEPS" -gt 12 ]; then fail "B: the loop did not finish in 12 steps: [$ACTIONS]"; break; fi
    LINE=$(next_line B)
    ACTIONS="$ACTIONS $LINE"
    case "$LINE" in
        done:merged) break ;;
        "merge:$CT_CORE/follow-up-21"|"merge:$CT_CLI")
            OUT=$(merge B "${LINE#merge:}")
            grep -qx merged <<<"$OUT" || { fail "B: $LINE did not merge: [$OUT] $(tail -2 "$CASE/merge.err")"; break; } ;;
        "dispatch:$CT_CLI")
            model_pr "$HOME_REPO" 12 "impl/move-$CT_CLI"
            rr_node B "$CT_CLI" 12
            render B >/dev/null ;;
        cascade)
            git -C "$WS_B" rm -q "$PLAN"
            git -C "$WS_B" commit -q -m "chore: cascade"
            git -C "$WS_B" push -q origin "$CT_CB"
            rr B cascade "$(jq -cn --arg h "$(git -C "$WS_B" rev-parse HEAD)" '{"run/cascade": {verdict: "pushed", head: $h}}')"
            render B >/dev/null ;;
        merge-coordination)
            OUT=$(merge B coordination)
            grep -qx merged <<<"$OUT" || { fail "B: the coordination merge: [$OUT] $(tail -3 "$CASE/merge.err")"; break; } ;;
        *) fail "B: an action this run should not need: [$LINE] after [$ACTIONS] $(tail -2 "$CASE/next.err")"; break ;;
    esac
done
case "$ACTIONS" in
    *"merge:$CT_CORE/follow-up-21"*"merge:$CT_CLI"*cascade*merge-coordination*done:merged)
        pass "B: the loop merges the follow-up and cli, cascades, and merges the coordination PR:$ACTIONS" ;;
    *) fail "B: the loop's actions [$ACTIONS]" ;;
esac
B koto next "$S" --with-data '{"loop_exit":"done","loop_line":"done:merged"}' --no-cleanup >"$CASE/next.json" 2>&1
if [ "$(state_in B)" = merged ] && [ "$(payload_in B outcome)" = merged ] && [ "$(payload_in B pr)" = "$COORD_URL" ]; then
    pass "B: the run ends merged"
else
    fail "B: ended at $(state_in B) outcome=[$(payload_in B outcome)]: $(head -c 600 "$CASE/next.json")"
fi
[ "$(B koto context get "$S" run_id 2>/dev/null)" = "$ID_A" ] && pass "B: the merged run's run_id is A's" || fail "B: the final run_id"
if B koto context exists "$S" run/recovered >/dev/null 2>&1; then fail "B: the run holds run/recovered"; else pass "B: the run never recovered"; fi

# --- the bodies -----------------------------------------------------------------------------

LIVE_BODY=$(B gh pr view 10 --repo "$HOME_REPO" --json body 2>/dev/null | jq -r '.body // ""')
if [ -n "$LIVE_BODY" ] && ! grep -q '^- ' <<<"$LIVE_BODY" && ! grep -q 'run=' <<<"$LIVE_BODY"; then
    pass "every read of #10 was served a body with no index line and no run= line"
else
    fail "the live body: [$LIVE_BODY]"
fi
LAST=$(find "$MOVE_POSTED" -type f | LC_ALL=C sort | tail -1)
WANT="- $CT_CORE | $HOME_REPO:docs/plans/PLAN-move.md#11 | merged | head=$(merge_sha_of "$HOME_REPO" 11)
- $CT_CORE/follow-up-21 | $HOME_REPO:docs/plans/PLAN-move.md#21 | merged | head=$(merge_sha_of "$HOME_REPO" 21)
- $CT_CLI | $HOME_REPO:docs/plans/PLAN-move.md#12 | merged | head=$(merge_sha_of "$HOME_REPO" 12)"
GOT=$(grep '^- ' "$LAST" 2>/dev/null)
if [ -n "$LAST" ] && [ "$GOT" = "$WANT" ]; then
    pass "the last body posted shows both nodes and the follow-up merged at the shim's merge commits, in order"
else
    fail "the last body posted ($LAST) indexes [$GOT], want [$WANT]"
fi
if [ -n "$LAST" ] && grep -Eq '#10([^0-9]|$)' "$LAST"; then fail "the last body names #10"; else pass "the last body has no self row"; fi

results
