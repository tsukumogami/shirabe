#!/usr/bin/env bash
# record-merge-verdict_test.sh — what merge_readiness and merge_confirm record
# Part of the execute skill
#
# record-merge-verdict.sh is the default action behind merge_readiness (and,
# with --confirm, merge_confirm). It clears its keys, resolves the owned PR,
# runs merge-verdict.sh, and records the verdict plus the reason or step derived
# from it. The harness runs it with:
#
#   a `koto` stub whose context store is a directory, so reads, clears, and
#   writes are observable and no workflow engine is needed;
#   a `gh` stub serving per-case fixtures for owned-pr.sh's reads;
#   for most cases, a COPY of the script beside the real owned-pr.sh and a
#   stub merge-verdict.sh that prints a chosen line and logs its arguments.
#   The script runs its siblings from its own directory, never from PATH, so a
#   copy is how a case controls the verdict without a test hook in the script.
#   One case runs the real merge-verdict.sh end to end.
#
# Cases (the issue's list, plus the lookup and confirm arms):
#   a normal write (real merge-verdict.sh)          keys written, verdict last
#   stale merge_verdict, home_pr, reason, step      each cleared
#   a failing merge-verdict.sh                      nothing written
#   a missing expected_head                         `--expected-head none`
#   reason for awaiting:merge-state:BLOCKED:review=REVIEW_REQUIRED
#   reason for awaiting:head-moved; step for error:execute:ci-timeout
#   a condition outside the closed set              nothing written
#   comma-joined --repo, missing --head-branch, each invalid argument
#                                                   usage exit, nothing written
#   owned-pr.sh zero / several / read failure       pr-adopt / pr-adopt / status-read
#   --confirm: merged, not observed, stale key, an ungrammatical line
#   never reads the `repos` key; makes no GitHub write
#
# Usage: record-merge-verdict_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
RECORD="$SCRIPT_DIR/record-merge-verdict.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
[ -f "$RECORD" ] || { echo "FAIL: $RECORD not found" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/record-merge-verdict-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN"

HEAD=1111111111111111111111111111111111111111
URL="https://github.com/o/r/pull/7"
S=execute-topic

# --- stubs --------------------------------------------------------------------

cat > "$BIN/koto" <<'STUB'
#!/usr/bin/env bash
store="${KOTO_STORE:?}"
printf '%s\n' "$*" >> "$store/calls.log"
[ "$1" = context ] || { echo "koto stub: only context is served" >&2; exit 9; }
d="$store/ctx/$3"
mkdir -p "$d"
case "$2" in
    add) [ "${KOTO_FAIL_ADD:-}" = "$4" ] && exit 3; cat > "$d/$4" ;;
    get) [ -f "$d/$4" ] || exit 3; cat "$d/$4" ;;
    remove) rm -f "$d/$4" ;;
    exists) [ -f "$d/$4" ] ;;
    *) exit 9 ;;
esac
STUB
chmod +x "$BIN/koto"

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
fix="${GH_FIX:?}"
printf '%s\n' "$*" >> "$fix/gh.log"
key=unknown
case "$1 ${2:-}" in
    "api user") key=user ;;
    "pr list") key=list ;;
    "pr view")
        case " $* " in *" --json state "*) key=confirm ;; *) key=view ;; esac ;;
    "pr checks") key=checks ;;
    "api "*)
        case "$2" in
            repos/*/*/rules/branches/*) key=rules ;;
            repos/*/*/pulls/*/files) key=files ;;
            repos/*/*/commits/*) key=commit ;;
            repos/*/*/branches/*) key=branch ;;
            repos/*/*) key=repo ;;
        esac ;;
esac
[ -f "$fix/$key.out" ] || [ -f "$fix/$key.rc" ] || { echo "gh stub: no fixture for [$key]" >&2; exit 1; }
[ -f "$fix/$key.out" ] && cat "$fix/$key.out"
rc=0; [ -f "$fix/$key.rc" ] && rc=$(cat "$fix/$key.rc")
exit "$rc"
STUB
chmod +x "$BIN/gh"

# A copy of the script beside the real owned-pr.sh and a stub merge-verdict.sh.
STUBDIR="$WORK/scripts"
mkdir -p "$STUBDIR"
cp "$RECORD" "$STUBDIR/record-merge-verdict.sh"
cp "$SCRIPT_DIR/owned-pr.sh" "$STUBDIR/owned-pr.sh"
cat > "$STUBDIR/merge-verdict.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${VERDICT_ARGS_LOG:?}"
[ -n "${VERDICT_RC:-}" ] && exit "$VERDICT_RC"
printf '%s\n' "${VERDICT_LINE:?}"
STUB

# --- fixtures -----------------------------------------------------------------

new_case() {
    CASE="$WORK/cases/$1"
    rm -rf "$CASE"; mkdir -p "$CASE/ctx/$S"
    : > "$CASE/calls.log"; : > "$CASE/gh.log"; : > "$CASE/verdict-args.log"
    echo '{"login":"octo"}' > "$CASE/user.out"
    echo '{"default_branch":"main","allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":true}' > "$CASE/repo.out"
    jq -nc --arg url "$URL" '[{url: $url, state: "OPEN", isCrossRepository: false,
        author: {login: "octo"}, baseRefName: "main", headRefName: "impl/topic"}]' > "$CASE/list.out"
    # merge-verdict.sh's reads, for the end-to-end case: a PR mergeable by squash.
    jq -n --arg head "$HEAD" '{
        state: "OPEN", isDraft: false, mergeStateStatus: "CLEAN",
        reviewDecision: "", headRefOid: $head, baseRefName: "main",
        changedFiles: 1,
        commits: [{oid: $head, committedDate: ((now - 600) | todate)}]
    }' > "$CASE/view.out"
    echo '[{"name":"build","bucket":"pass"}]' > "$CASE/checks.out"
    echo '{"name":"main","protected":false}' > "$CASE/branch.out"
    echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"build"}]}}]' > "$CASE/rules.out"
    echo '[{"filename":"src/main.go"}]' > "$CASE/files.out"
    echo '{"state":"MERGED"}' > "$CASE/confirm.out"
}

ctx_set() { printf '%s' "$2" > "$CASE/ctx/$S/$1"; }
ctx() { cat "$CASE/ctx/$S/$1" 2>/dev/null; }
has() { [ -f "$CASE/ctx/$S/$1" ]; }

# run <script> [args...] — defaults to the verdict-mode arguments.
run_script() {
    local script="$1"
    shift
    if [ $# -eq 0 ]; then set -- --repo o/r --head-branch impl/topic --merge true --session "$S"; fi
    OUT=$(env KOTO_STORE="$CASE" GH_FIX="$CASE" VERDICT_ARGS_LOG="$CASE/verdict-args.log" \
        PATH="$BIN:$PATH" bash "$script" "$@" </dev/null 2>"$CASE/stderr")
    RC=$?
    ERR=$(cat "$CASE/stderr")
}
run_real() { run_script "$RECORD" "$@"; }
run_stub() { run_script "$STUBDIR/record-merge-verdict.sh" "$@"; }

nothing_written_after_clear() {
    ! grep -q '^context add' "$CASE/calls.log"
}

# --- a normal write, end to end -----------------------------------------------

new_case normal
ctx_set expected_head "$HEAD"
run_real
if [ "$RC" -eq 0 ] && [ "$(ctx merge_verdict)" = "mergeable:squash:$HEAD" ] \
    && [ "$(ctx home_pr)" = "$URL" ] && [ "$(ctx waiting)" = "$URL:human" ] \
    && ! has reason && ! has step; then
    pass "normal write: verdict, home_pr, and waiting recorded (real merge-verdict.sh)"
else
    fail "normal write: exit $RC, verdict [$(ctx merge_verdict)], home_pr [$(ctx home_pr)], waiting [$(ctx waiting)]; $ERR"
fi
if [ "$(grep '^context add' "$CASE/calls.log" | tail -1)" = "context add $S merge_verdict" ]; then
    pass "normal write: merge_verdict is written last"
else
    fail "normal write: last write was [$(grep '^context add' "$CASE/calls.log" | tail -1)]"
fi
if grep -Eq '^(pr (merge|edit|ready|create|close|comment|review)|api .*(-X|--method))' "$CASE/gh.log"; then
    fail "the script wrote to GitHub: $(cat "$CASE/gh.log")"
else
    pass "no GitHub write: every gh call is a read"
fi
if grep -q " repos$" "$CASE/calls.log"; then
    fail "the script read the repos context key"
else
    pass "the repos context key is never read"
fi

# --- stale keys cleared -------------------------------------------------------

new_case stale
ctx_set expected_head "$HEAD"
ctx_set merge_verdict "awaiting:review"; ctx_set home_pr "https://github.com/o/r/pull/1"
ctx_set reason "review"; ctx_set step "execute:ci"; ctx_set waiting "https://github.com/o/r/pull/1:human"
VERDICT_LINE="mergeable:squash:$HEAD" run_stub
if [ "$RC" -eq 0 ] && [ "$(ctx merge_verdict)" = "mergeable:squash:$HEAD" ] && [ "$(ctx home_pr)" = "$URL" ] \
    && ! has reason && ! has step; then
    pass "stale merge_verdict, home_pr, reason, and step are each cleared or replaced"
else
    fail "stale keys: verdict [$(ctx merge_verdict)], home_pr [$(ctx home_pr)], reason [$(ctx reason)], step [$(ctx step)]"
fi
for k in merge_verdict home_pr reason step; do
    if grep -q "^context remove $S $k$" "$CASE/calls.log"; then
        pass "stale $k: explicitly cleared before recomputing"
    else
        fail "stale $k: no clear call"
    fi
done

# --- a failing merge-verdict.sh -----------------------------------------------

new_case verdict-fails
ctx_set expected_head "$HEAD"
ctx_set merge_verdict "mergeable:squash:$HEAD"; ctx_set home_pr "$URL"
VERDICT_RC=1 VERDICT_LINE=x run_stub
if [ "$RC" -ne 0 ] && nothing_written_after_clear && ! has merge_verdict && ! has home_pr; then
    pass "a failing merge-verdict.sh: non-zero, nothing written, stale verdict gone"
else
    fail "a failing merge-verdict.sh: exit $RC, verdict [$(ctx merge_verdict)], calls: $(cat "$CASE/calls.log")"
fi

new_case verdict-two-lines
VERDICT_LINE=$'merged\nmerged' run_stub
if [ "$RC" -ne 0 ] && nothing_written_after_clear; then
    pass "two lines from merge-verdict.sh: nothing written"
else
    fail "two lines: exit $RC, verdict [$(ctx merge_verdict)]"
fi

# --- expected_head ------------------------------------------------------------

new_case no-expected
VERDICT_LINE="awaiting:head-moved" run_stub
if grep -q -- '--expected-head none' "$CASE/verdict-args.log"; then
    pass "a missing expected_head passes --expected-head none"
else
    fail "missing expected_head: merge-verdict.sh got [$(cat "$CASE/verdict-args.log")]"
fi

new_case bad-expected
ctx_set expected_head "not-a-sha"
VERDICT_LINE="awaiting:head-moved" run_stub
if grep -q -- '--expected-head none' "$CASE/verdict-args.log"; then
    pass "a malformed expected_head passes --expected-head none"
else
    fail "malformed expected_head: merge-verdict.sh got [$(cat "$CASE/verdict-args.log")]"
fi

new_case passes-expected
ctx_set expected_head "$HEAD"
VERDICT_LINE="awaiting:merge-not-requested" run_stub --repo o/r --head-branch impl/topic --merge false --session "$S"
if grep -q -- "--repo o/r --pr 7 --merge false --expected-head $HEAD" "$CASE/verdict-args.log"; then
    pass "merge-verdict.sh receives the owned PR's number, --merge, and the recorded head"
else
    fail "merge-verdict.sh args: [$(cat "$CASE/verdict-args.log")]"
fi

# --- reason and step ----------------------------------------------------------

expect_key() { # expect_key <label> <verdict line> <key> <value>
    new_case "key-$3"
    VERDICT_LINE="$2" run_stub
    if [ "$RC" -eq 0 ] && [ "$(ctx "$3")" = "$4" ] && [ "$(ctx merge_verdict)" = "$2" ]; then
        pass "$1: $3=$4"
    else
        fail "$1: exit $RC, $3 [$(ctx "$3")], verdict [$(ctx merge_verdict)]; $ERR"
    fi
}
expect_key "review required" "awaiting:merge-state:BLOCKED:review=REVIEW_REQUIRED" reason "merge-state:BLOCKED:review=REVIEW_REQUIRED"
expect_key "head moved" "awaiting:head-moved" reason "head-moved"
expect_key "ci timeout" "error:execute:ci-timeout" step "execute:ci-timeout"
expect_key "DIRTY" "awaiting:merge-state:DIRTY" reason "merge-state:DIRTY"

new_case merged-no-waiting
VERDICT_LINE="merged" run_stub
if [ "$(ctx merge_verdict)" = merged ] && ! has waiting && ! has reason && ! has step; then
    pass "a merged verdict writes no waiting, reason, or step"
else
    fail "merged: waiting [$(ctx waiting)]"
fi

for bad in "awaiting:bogus" "awaiting:merge-state:dirty" "error:execute:deploy" "mergeable:squash:abc" "maybe"; do
    new_case outside
    VERDICT_LINE="$bad" run_stub
    if [ "$RC" -ne 0 ] && nothing_written_after_clear; then
        pass "[$bad] is outside the grammar or closed set: nothing written"
    else
        fail "[$bad]: exit $RC, verdict [$(ctx merge_verdict)], reason [$(ctx reason)]"
    fi
done

# --- the lookup ---------------------------------------------------------------

new_case lookup-zero
echo '[]' > "$CASE/list.out"
VERDICT_LINE=merged run_stub
if [ "$RC" -eq 0 ] && [ "$(ctx step)" = "execute:pr-adopt" ] && [ "$(ctx merge_verdict)" = "error:execute:pr-adopt" ] \
    && ! has home_pr && [ ! -s "$CASE/verdict-args.log" ]; then
    pass "zero owned PRs: step execute:pr-adopt, no home_pr, merge-verdict.sh not run"
else
    fail "zero owned PRs: exit $RC, step [$(ctx step)], verdict [$(ctx merge_verdict)]"
fi

new_case lookup-foreign
jq -nc --arg url "$URL" '[{url: $url, state: "OPEN", isCrossRepository: true,
    author: {login: "octo"}, baseRefName: "main", headRefName: "impl/topic"}]' > "$CASE/list.out"
VERDICT_LINE=merged run_stub
if [ "$(ctx step)" = "execute:pr-adopt" ] && ! has home_pr; then
    pass "a fork PR only: execute:pr-adopt, the fork PR is not recorded"
else
    fail "fork only: step [$(ctx step)], home_pr [$(ctx home_pr)]"
fi

new_case lookup-several
jq -nc '[1,2] | map({url: ("https://github.com/o/r/pull/" + tostring), state: "OPEN", isCrossRepository: false,
    author: {login: "octo"}, baseRefName: "main", headRefName: "impl/topic"})' > "$CASE/list.out"
VERDICT_LINE=merged run_stub
if [ "$(ctx step)" = "execute:pr-adopt" ] && [ "$(ctx merge_verdict)" = "error:execute:pr-adopt" ]; then
    pass "several owned PRs: execute:pr-adopt"
else
    fail "several: step [$(ctx step)]"
fi

new_case lookup-read-fails
rm -f "$CASE/list.out"; echo 1 > "$CASE/list.rc"
VERDICT_LINE=merged run_stub
if [ "$(ctx step)" = "execute:status-read" ] && [ "$(ctx merge_verdict)" = "error:execute:status-read" ]; then
    pass "a failed lookup read: execute:status-read"
else
    fail "read failure: step [$(ctx step)]"
fi

new_case merged-pr-found
jq -nc --arg url "$URL" '[{url: $url, state: "MERGED", isCrossRepository: false,
    author: {login: "octo"}, baseRefName: "main", headRefName: "impl/topic"}]' > "$CASE/list.out"
VERDICT_LINE=merged run_stub
if [ "$(ctx home_pr)" = "$URL" ] && [ "$(ctx merge_verdict)" = merged ] && grep -q -- '--state all' "$CASE/gh.log"; then
    pass "an already-merged PR is found (--state all) and recorded"
else
    fail "merged PR: home_pr [$(ctx home_pr)], gh: $(cat "$CASE/gh.log")"
fi

# --- usage --------------------------------------------------------------------

expect_usage() {
    local label="$1"
    shift
    new_case usage
    ctx_set merge_verdict "merged"
    VERDICT_LINE=merged run_stub "$@"
    if [ "$RC" -eq 64 ] && [ ! -s "$CASE/calls.log" ] && [ ! -s "$CASE/gh.log" ] && [ "$(ctx merge_verdict)" = merged ]; then
        pass "usage: $label (exit 64, nothing read or written)"
    else
        fail "usage: $label: exit $RC, koto calls [$(cat "$CASE/calls.log")]"
    fi
}
expect_usage "comma-joined --repo" --repo o/r,o/s --head-branch impl/topic --session "$S"
expect_usage "missing --head-branch" --repo o/r --session "$S"
expect_usage "missing --repo" --head-branch impl/topic --session "$S"
expect_usage "invalid --repo" --repo 'o/r;x' --head-branch impl/topic --session "$S"
expect_usage "dot --repo" --repo o/.. --head-branch impl/topic --session "$S"
expect_usage "--head-branch with .." --repo o/r --head-branch 'a..b' --session "$S"
expect_usage "--head-branch with a leading dash" --repo o/r --head-branch '-x' --session "$S"
expect_usage "empty --head-branch" --repo o/r --head-branch '' --session "$S"
expect_usage "invalid --merge" --repo o/r --head-branch impl/topic --merge yes --session "$S"
expect_usage "invalid --session" --repo o/r --head-branch impl/topic --session 'a b'
expect_usage "no session at all" --repo o/r --head-branch impl/topic
expect_usage "repeated --repo" --repo o/r --repo o/r --head-branch impl/topic --session "$S"

new_case tick-session
OUT=$(env KOTO_TICK_SESSION="$S" KOTO_STORE="$CASE" GH_FIX="$CASE" VERDICT_ARGS_LOG="$CASE/verdict-args.log" \
    VERDICT_LINE="awaiting:review" PATH="$BIN:$PATH" bash "$STUBDIR/record-merge-verdict.sh" \
    --repo o/r --head-branch impl/topic </dev/null 2>/dev/null)
if [ "$(ctx merge_verdict)" = "awaiting:review" ]; then
    pass "the session defaults to KOTO_TICK_SESSION, which koto sets for its commands"
else
    fail "KOTO_TICK_SESSION default: verdict [$(ctx merge_verdict)]"
fi

# --- confirm mode -------------------------------------------------------------

new_case confirm-merged
ctx_set merge_verdict "mergeable:squash:$HEAD"
run_real --confirm --repo o/r --head-branch impl/topic --session "$S"
if [ "$RC" -eq 0 ] && [ "$(ctx confirm_verdict)" = merged ] && [ "$(ctx merge_verdict)" = "mergeable:squash:$HEAD" ]; then
    pass "--confirm: a MERGED read records confirm_verdict=merged and touches nothing else"
else
    fail "--confirm merged: exit $RC, confirm [$(ctx confirm_verdict)]; $ERR"
fi

new_case confirm-open
echo '{"state":"OPEN"}' > "$CASE/confirm.out"
OUT=$(env MERGE_CONFIRM_WAIT_SECS=0 KOTO_STORE="$CASE" GH_FIX="$CASE" PATH="$BIN:$PATH" \
    bash "$RECORD" --confirm --repo o/r --head-branch impl/topic --session "$S" </dev/null 2>/dev/null)
if [ "$(ctx confirm_verdict)" = "not-merged:merge-not-observed" ]; then
    pass "--confirm: a PR still OPEN records not-merged:merge-not-observed"
else
    fail "--confirm open: confirm [$(ctx confirm_verdict)]"
fi

new_case confirm-stale
ctx_set confirm_verdict merged
VERDICT_LINE="maybe" run_stub --confirm --repo o/r --head-branch impl/topic --session "$S"
if [ "$RC" -ne 0 ] && ! has confirm_verdict; then
    pass "--confirm: a stale confirm_verdict is cleared, and an ungrammatical line is not written"
else
    fail "--confirm stale: exit $RC, confirm [$(ctx confirm_verdict)]"
fi

new_case confirm-lookup
ctx_set confirm_verdict merged
echo '[]' > "$CASE/list.out"
VERDICT_LINE=merged run_stub --confirm --repo o/r --head-branch impl/topic --session "$S"
if [ "$RC" -ne 0 ] && ! has confirm_verdict && [ ! -s "$CASE/verdict-args.log" ]; then
    pass "--confirm: no owned PR, nothing confirmed and the stale key is gone"
else
    fail "--confirm lookup: exit $RC, confirm [$(ctx confirm_verdict)]"
fi

new_case confirm-args
VERDICT_LINE=merged run_stub --confirm --repo o/r --head-branch impl/topic --session "$S"
if grep -q -- '--pr 7 .*--confirm' "$CASE/verdict-args.log"; then
    pass "--confirm runs merge-verdict.sh --confirm on the PR it resolved itself"
else
    fail "--confirm args: [$(cat "$CASE/verdict-args.log")]"
fi

# --- a failing context write --------------------------------------------------

new_case write-fails
ctx_set expected_head "$HEAD"
KOTO_FAIL_ADD=merge_verdict VERDICT_LINE="awaiting:review" run_stub
if [ "$RC" -eq 70 ]; then
    pass "a failing context write exits 70"
else
    fail "write failure: exit $RC"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
