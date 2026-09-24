#!/usr/bin/env bash
# merge-verdict_test.sh — the merge decision table, one case per row
# Part of the execute skill
#
# merge-verdict.sh reads one snapshot of a PR and its base branch and prints one
# verdict. This harness drives it through a test-local `gh` stub on PATH that
# serves per-case JSON fixtures and appends every invocation to a call log, so
# no case touches GitHub. Cases are table-driven: each one starts from a
# mergeable fixture, changes the fields its row is about, and asserts the exact
# verdict string.
#
# It asserts:
#
#   argument handling and the closed patterns     (usage cases)
#   the bounded environment knobs                 (limit and confirm cases)
#   rows 1-16 of the decision table               (row cases)
#   bounded retries on a failing read             (retry cases)
#   confirm mode, rows 17 and 19                  (confirm cases)
#   no stdin, no workflow-engine dependency       (isolation cases)
#   every verdict produced matches the grammar in the script's header
#
# Timestamps are generated from the harness's own clock through jq (`now`,
# `todate`), and the script does its date arithmetic in jq too, so no case
# depends on wall time or on a platform `date`.
#
# Usage: merge-verdict_test.sh
#
# Exit codes:
#   0 — all cases pass
#   1 — one or more cases failed, or jq is missing

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
VERDICT="$SCRIPT_DIR/merge-verdict.sh"
EXEC="$SCRIPT_DIR/merge-exec.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
[ -f "$VERDICT" ] || { echo "FAIL: $VERDICT not found" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"
mkdir -p "$BIN" "$WORK/cases"
VERDICT_LOG="$WORK/verdicts.log"
: > "$VERDICT_LOG"

HEAD=1111111111111111111111111111111111111111
OTHER=2222222222222222222222222222222222222222

# ---------------------------------------------------------------------------
# The gh stub
# ---------------------------------------------------------------------------
#
# Routes each invocation to a fixture key, logs the arguments, and serves
# $GH_FIX/<key>.out / .err / .rc. A numbered file (<key>.out.2) wins for the
# Nth call to that key, which is how a sequence of reads is served. A key with
# neither an .out nor an .rc file fails like a read error.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
fix="${GH_FIX:?GH_FIX is not set}"
printf '%s\n' "$*" >> "$fix/calls.log"
key=unknown
case "$1 ${2:-}" in
    "pr view")
        case " $* " in
            *" --json state "*) key=confirm ;;
            *) key=view ;;
        esac
        ;;
    "pr checks") key=checks ;;
    "pr merge") key=merge ;;
    "api "*)
        case "$2" in
            repos/*/*/rules/branches/*) key=rules ;;
            repos/*/*/pulls/*/files) key=files ;;
            repos/*/*/commits/*) key=commit ;;
            repos/*/*/branches/*) key=branch ;;
            repos/*/*) key=repo ;;
        esac
        ;;
esac
n=0
[ -f "$fix/$key.count" ] && n=$(cat "$fix/$key.count")
n=$((n + 1))
echo "$n" > "$fix/$key.count"
pick() {
    if [ -f "$fix/$key.$1.$n" ]; then echo "$fix/$key.$1.$n"; else echo "$fix/$key.$1"; fi
}
out=$(pick out); err=$(pick err); rcf=$(pick rc)
if [ ! -f "$out" ] && [ ! -f "$rcf" ]; then
    echo "gh stub: no fixture for [$key] ($*)" >&2
    exit 1
fi
[ -f "$out" ] && cat "$out"
[ -f "$err" ] && cat "$err" >&2
rc=0
[ -f "$rcf" ] && rc=$(cat "$rcf")
exit "$rc"
STUB
chmod +x "$BIN/gh"

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# new_case <name> — a fresh fixture directory holding a PR that is mergeable
# with squash: open, clean, one passing required check, a base whose ruleset
# requires that check, one ordinary changed file, every method allowed.
new_case() {
    CASE="$WORK/cases/$1"
    rm -rf "$CASE"
    mkdir -p "$CASE"
    : > "$CASE/calls.log"
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
    echo '{"allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":true}' > "$CASE/repo.out"
    echo '{"state":"MERGED"}' > "$CASE/confirm.out"
    : > "$CASE/merge.out"
}

# view <jq filter> — edit the PR snapshot fixture.
view() {
    jq "$1" "$CASE/view.out" > "$CASE/view.tmp" && mv "$CASE/view.tmp" "$CASE/view.out"
}

# age <seconds> — set the head commit's committedDate that many seconds ago.
age() {
    view ".commits[0].committedDate = ((now - $1) | todate)"
}

# fixture <key> <json> — replace one fixture's stdout.
fixture() {
    printf '%s\n' "$2" > "$CASE/$1.out"
}

# failing <key> [stderr] — make every read of <key> fail.
failing() {
    rm -f "$CASE/$1.out"
    echo 1 > "$CASE/$1.rc"
    printf '%s\n' "${2:-HTTP 502: Bad Gateway}" > "$CASE/$1.err"
}

calls() {
    grep -c -e "$1" "$CASE/calls.log"
}

# ---------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------

EXTRA_ENV=""

# run_verdict [args...] — runs the script against $CASE, stdin closed. With no
# arguments it passes the default merge-requested invocation.
run_verdict() {
    if [ $# -eq 0 ]; then
        set -- --repo o/r --pr 7 --merge true --expected-head "$HEAD"
    fi
    # shellcheck disable=SC2086
    OUT=$(env $EXTRA_ENV GH_FIX="$CASE" PATH="$BIN:$PATH" bash "$VERDICT" "$@" </dev/null 2>"$CASE/stderr")
    RC=$?
    ERR=$(cat "$CASE/stderr")
    [ -n "$OUT" ] && printf '%s\n' "$OUT" >> "$VERDICT_LOG"
    return 0
}

# expect <label> <verdict> [args...]
expect() {
    local label="$1" want="$2"
    shift 2
    run_verdict "$@"
    if [ "$RC" -eq 0 ] && [ "$OUT" = "$want" ]; then
        pass "$label -> $want"
    else
        fail "$label: want [$want] exit 0, got [$OUT] exit $RC; stderr: $ERR"
    fi
}

# expect_usage <label> [args...] — non-zero, empty stdout, usage on stderr,
# no gh call.
expect_usage() {
    local label="$1"
    shift
    new_case "usage"
    run_verdict "$@"
    if [ "$RC" -ne 0 ] && [ -z "$OUT" ] && [ ! -s "$CASE/calls.log" ] \
        && printf '%s' "$ERR" | grep -q 'usage:'; then
        pass "usage: $label"
    else
        fail "usage: $label: exit $RC, stdout [$OUT], calls [$(cat "$CASE/calls.log")], stderr [$ERR]"
    fi
}

# ---------------------------------------------------------------------------
# Usage and closed patterns
# ---------------------------------------------------------------------------

M=(--merge true --expected-head "$HEAD")
expect_usage "only --confirm" --confirm
expect_usage "missing --repo" --pr 7 "${M[@]}"
expect_usage "missing --pr" --repo o/r "${M[@]}"
expect_usage "missing --merge" --repo o/r --pr 7 --expected-head "$HEAD"
expect_usage "missing --expected-head" --repo o/r --pr 7 --merge true
expect_usage "unknown flag" --repo o/r --pr 7 "${M[@]}" --admin
expect_usage "flag=value form" --repo=o/r --pr 7 "${M[@]}"
expect_usage "repeated --pr" --repo o/r --pr 7 --pr 8 "${M[@]}"
expect_usage "repeated --confirm" --repo o/r --pr 7 "${M[@]}" --confirm --confirm
expect_usage "flag without a value" --repo o/r "${M[@]}" --pr
expect_usage "pr 0" --repo o/r --pr 0 "${M[@]}"
expect_usage "pr 012" --repo o/r --pr 012 "${M[@]}"
expect_usage "pr 1;rm" --repo o/r --pr '1;rm' "${M[@]}"
expect_usage "39-character sha" --repo o/r --pr 7 --merge true --expected-head "${HEAD%1}"
expect_usage "uppercase sha" --repo o/r --pr 7 --merge true --expected-head ABCDEF1111111111111111111111111111111111
expect_usage "repo owner/repo/extra" --repo o/r/extra --pr 7 "${M[@]}"
expect_usage "repo without owner" --repo r --pr 7 "${M[@]}"
expect_usage "repo dot segment" --repo ../r --pr 7 "${M[@]}"
expect_usage "merge yes" --repo o/r --pr 7 --merge yes --expected-head "$HEAD"
expect_usage "merge TRUE" --repo o/r --pr 7 --merge TRUE --expected-head "$HEAD"

new_case "any-order"
expect "flags in any order" "mergeable:squash:$HEAD" --expected-head "$HEAD" --merge true --pr 7 --repo o/r

# ---------------------------------------------------------------------------
# Decision table
# ---------------------------------------------------------------------------

new_case r1; view '.state = "MERGED"'
expect "row 1 MERGED" "merged"

new_case r2; view '.state = "CLOSED"'
expect "row 2 CLOSED" "error:execute:pr-closed"

new_case r3; view '.isDraft = true'
expect "row 3 draft" "error:execute:ready"

new_case r4; view '.mergeStateStatus = "DIRTY"'; fixture checks '[{"name":"build","bucket":"fail"}]'
expect "row 4 DIRTY outranks a failing check" "awaiting:merge-state:DIRTY"

new_case r5; fixture checks '[{"name":"build","bucket":"fail"}]'
expect "row 5 fail, merge true" "error:execute:ci"
expect "row 5 fail, merge false" "error:execute:ci" --repo o/r --pr 7 --merge false --expected-head "$HEAD"
new_case r5c; fixture checks '[{"name":"build","bucket":"pass"},{"name":"lint","bucket":"cancel"}]'
expect "row 5 cancel" "error:execute:ci"

new_case r6-pass-skip; fixture checks '[{"name":"build","bucket":"pass"},{"name":"docs","bucket":"skipping"}]'
expect "row 6 pass and skipping count as succeeded" "mergeable:squash:$HEAD"
new_case r6-pending; fixture checks '[{"name":"build","bucket":"pass"},{"name":"lint","bucket":"pending"}]'
expect "row 6 pending check" "pending:checks"
new_case r6-weird; fixture checks '[{"name":"build","bucket":"pass"},{"name":"lint","bucket":"weird"}]'
expect "row 6 unrecognized bucket is pending" "pending:checks"
new_case r6-missing-bucket; fixture checks '[{"name":"build","bucket":"pass"},{"name":"lint"}]'
expect "row 6 missing bucket is pending" "pending:checks"

new_case r6-required; fixture checks '[{"name":"lint","bucket":"pass"}]'
expect "row 6 required check not yet reported" "pending:checks"

new_case r6-grace; fixture checks '[]'; fixture rules '[]'; age 60
expect "row 6 zero checks inside the grace window" "pending:checks"

new_case r6-deadline; fixture checks '[{"name":"build","bucket":"pending"}]'; age 2000
expect "row 6 pending past the default deadline" "error:execute:ci-timeout"
new_case r6-limit-400; fixture checks '[{"name":"build","bucket":"pending"}]'; age 400
EXTRA_ENV="EXECUTE_CI_WAIT_LIMIT_SECS=300"
expect "row 6 limit 300, head 400 s old" "error:execute:ci-timeout"
new_case r6-limit-200; fixture checks '[{"name":"build","bucket":"pending"}]'; age 200
expect "row 6 limit 300, head 200 s old" "pending:checks"
EXTRA_ENV=""

new_case r7
expect "row 7 merge not requested" "awaiting:merge-not-requested" --repo o/r --pr 7 --merge false --expected-head "$HEAD"
if [ "$(calls 'branches/')" -eq 0 ] && [ "$(grep -cE '^api repos/o/r($| )' "$CASE/calls.log")" -eq 0 ]; then
    pass "row 7 reads no protection, rules, or merge methods"
else
    fail "row 7 read protection or methods: $(cat "$CASE/calls.log")"
fi

new_case r8-none
expect "row 8 expected head none" "awaiting:head-moved" --repo o/r --pr 7 --merge true --expected-head none
new_case r8-differs
expect "row 8 expected head differs" "awaiting:head-moved" --repo o/r --pr 7 --merge true --expected-head "$OTHER"

new_case r9; fixture checks '[]'; fixture rules '[]'; age 600
expect "row 9 no checks after the grace window" "awaiting:no-checks"

new_case r10; view '.mergeStateStatus = "UNKNOWN"'
expect "row 10 UNKNOWN within the deadline" "pending:merge-state"
new_case r10-late; view '.mergeStateStatus = "UNKNOWN"'; age 2000
expect "row 10 UNKNOWN past the deadline" "awaiting:merge-state:UNKNOWN"

for S in BLOCKED BEHIND UNSTABLE HAS_HOOKS; do
    new_case "r11-$S"; view ".mergeStateStatus = \"$S\""
    expect "row 11 $S" "awaiting:merge-state:$S"
done
new_case r11-rr; view '.mergeStateStatus = "BLOCKED" | .reviewDecision = "REVIEW_REQUIRED"'
expect "row 11 BLOCKED with review required" "awaiting:merge-state:BLOCKED:review=REVIEW_REQUIRED"
new_case r11-cr; view '.reviewDecision = "CHANGES_REQUESTED"'
expect "row 11 CLEAN with changes requested" "awaiting:merge-state:CLEAN:review=CHANGES_REQUESTED"

new_case r12-empty; fixture rules '[]'
expect "row 12 both sources empty" "awaiting:base-unprotected"
new_case r12-unreadable; failing branch "gh: Not Found (HTTP 404)"; failing rules
expect "row 12 classic 404 and rules failing" "awaiting:base-unprotected"

CLASSIC='{"name":"main","protected":true,"protection":{"enabled":true,"required_status_checks":{"enforcement_level":"everyone","contexts":["build"],"checks":[{"context":"build","app_id":null}]}}}'
new_case r12-classic; fixture rules '[]'; fixture branch "$CLASSIC"
expect "row 12 classic protection alone" "mergeable:squash:$HEAD"
new_case r12-classic-off; fixture rules '[]'; fixture branch "$(printf '%s' "$CLASSIC" | jq -c '.protected = false')"
expect "row 12 classic list but protected false" "awaiting:base-unprotected"
new_case r12-rules
expect "row 12 ruleset checks alone, classic protected false" "mergeable:squash:$HEAD"
new_case r12-rules-404; failing branch "gh: Not Found (HTTP 404)"
expect "row 12 ruleset checks alone, classic 404" "mergeable:squash:$HEAD"
new_case r12-rules-empty; fixture rules '[]'
expect "row 12 ruleset empty" "awaiting:base-unprotected"
new_case r12-rules-empty-list; fixture rules '[{"type":"required_status_checks","parameters":{"required_status_checks":[]}}]'
expect "row 12 ruleset check rule with an empty list" "awaiting:base-unprotected"

REVIEW_RULE='{"type":"pull_request","parameters":{"required_approving_review_count":1}}'
new_case r13; fixture rules "[$REVIEW_RULE]"
expect "row 13 rules require a review, none given" "awaiting:review"
new_case r13-approved; fixture rules "[$REVIEW_RULE]"; view '.reviewDecision = "APPROVED"'
expect "row 13 rules require a review, approved" "mergeable:squash:$HEAD"
new_case r13-zero; fixture rules '[{"type":"pull_request","parameters":{"required_approving_review_count":0}}]'
expect "row 13 a zero-review rule is no requirement" "awaiting:base-unprotected"

for P in .github/workflows/ci.yml .github/actions/setup/action.yml CODEOWNERS .github/CODEOWNERS docs/CODEOWNERS; do
    new_case "r14-$(printf '%s' "$P" | tr '/.' '__')"; fixture files "[{\"filename\":\"$P\"}]"
    expect "row 14 touches $P" "awaiting:workflow-change"
    view '.reviewDecision = "APPROVED"'
    expect "row 14 touches $P, approved" "mergeable:squash:$HEAD"
done
new_case r14-rename; fixture files '[{"filename":"old-ci.yml","previous_filename":".github/workflows/ci.yml"}]'
expect "row 14 renames a workflow away" "awaiting:workflow-change"

new_case r14-paged; view '.changedFiles = 101'
jq -nc '[range(0; 100) | {filename: "src/f\(.).go"}]' > "$CASE/files.out"
echo '[{"filename":".github/workflows/release.yml"}]' >> "$CASE/files.out"
expect "row 14 the 101st file, on the second page" "awaiting:workflow-change"
if grep -q '^api repos/o/r/pulls/7/files --paginate$' "$CASE/calls.log"; then
    pass "row 14 reads the paginated files endpoint"
else
    fail "row 14 did not read the paginated files endpoint: $(cat "$CASE/calls.log")"
fi
new_case r14-failing; failing files
expect "row 14 files read fails" "error:execute:status-read"
new_case r14-short; view '.changedFiles = 3'; fixture files '[{"filename":"a"},{"filename":"b"}]'
expect "row 14 list shorter than changedFiles" "error:execute:status-read"

new_case r15-failing; failing repo
expect "row 15 methods unreadable" "awaiting:merge-method-unresolved"
new_case r15-none; fixture repo '{"allow_squash_merge":false,"allow_merge_commit":false,"allow_rebase_merge":false}'
expect "row 15 no method allowed" "awaiting:merge-method-unresolved"

new_case r16-rebase; fixture repo '{"allow_squash_merge":false,"allow_merge_commit":false,"allow_rebase_merge":true}'
expect "row 16 rebase only" "mergeable:rebase:$HEAD"
new_case r16-merge; fixture repo '{"allow_squash_merge":false,"allow_merge_commit":true,"allow_rebase_merge":false}'
expect "row 16 merge only" "mergeable:merge:$HEAD"
new_case r16-squash-merge; fixture repo '{"allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":false}'
expect "row 16 squash and merge" "mergeable:squash:$HEAD"
new_case r16-merge-rebase; fixture repo '{"allow_squash_merge":false,"allow_merge_commit":true,"allow_rebase_merge":true}'
expect "row 16 merge and rebase" "mergeable:merge:$HEAD"

new_case head-date-fallback; view '.commits = []'
jq -n '{commit: {committer: {date: ((now - 600) | todate)}}}' > "$CASE/commit.out"
expect "head date read from the commit when the snapshot lacks it" "mergeable:squash:$HEAD"

# ---------------------------------------------------------------------------
# Reads: failures, retries, and gh pr checks exit codes
# ---------------------------------------------------------------------------

new_case view-failing; failing view
START=$SECONDS
expect "PR view fails on every attempt" "error:execute:status-read"
ELAPSED=$((SECONDS - START))
if [ "$(calls '^pr view')" -eq 3 ] && [ "$ELAPSED" -lt 10 ]; then
    pass "PR view retried exactly 3 times inside the budget (${ELAPSED}s)"
else
    fail "PR view: $(calls '^pr view') attempts in ${ELAPSED}s, want 3 in under 10s"
fi

new_case checks-failing; failing checks
START=$SECONDS
expect "checks read fails on every attempt" "error:execute:status-read"
ELAPSED=$((SECONDS - START))
if [ "$(calls '^pr checks')" -eq 3 ] && [ "$ELAPSED" -lt 10 ]; then
    pass "checks read retried exactly 3 times inside the budget (${ELAPSED}s)"
else
    fail "checks read: $(calls '^pr checks') attempts in ${ELAPSED}s, want 3 in under 10s"
fi

new_case checks-recover; echo 1 > "$CASE/checks.rc.1"; echo 'HTTP 502' > "$CASE/checks.err.1"; echo 0 > "$CASE/checks.rc"
rm -f "$CASE/checks.out.1"; : > "$CASE/checks.out.1"
expect "checks read recovers on a retry" "mergeable:squash:$HEAD"

new_case checks-none; failing checks "no checks reported on the 'impl/x' branch"; fixture rules '[]'
expect "no-checks exit read as zero checks" "awaiting:no-checks"
if [ "$(calls '^pr checks')" -eq 1 ]; then
    pass "no-checks exit is not retried"
else
    fail "no-checks exit was retried: $(calls '^pr checks') calls"
fi

new_case checks-exit8; echo 8 > "$CASE/checks.rc"; fixture checks '[{"name":"build","bucket":"pending"}]'
expect "pending exit 8 with JSON read as the JSON says" "pending:checks"
if [ "$(calls '^pr checks')" -eq 1 ]; then
    pass "pending exit 8 is not treated as a read failure"
else
    fail "pending exit 8 was retried: $(calls '^pr checks') calls"
fi
new_case checks-exit1-json; echo 1 > "$CASE/checks.rc"; fixture checks '[{"name":"build","bucket":"fail"}]'
expect "failing-checks exit with JSON read as the JSON says" "error:execute:ci"

new_case view-garbage; fixture view 'not json'
expect "unparseable PR view" "error:execute:status-read"
new_case view-bad-head; view '.headRefOid = "HEAD"'
expect "headRefOid outside its pattern" "error:execute:status-read"
new_case view-bad-base; view '.baseRefName = "main;rm"'
expect "baseRefName outside its pattern" "error:execute:status-read"

# ---------------------------------------------------------------------------
# EXECUTE_CI_WAIT_LIMIT_SECS fallbacks
# ---------------------------------------------------------------------------
#
# A pending check on a head 1000 s old is still waiting under the 1800 s
# fallback and one 1900 s old has timed out, so each bad value shows up as
# exactly 1800: not 0 or -5 (which would time out at 1000 s) and not the huge
# value (which would still be waiting at 1900 s).

for BAD in "" abc -5 0 99999999; do
    EXTRA_ENV="EXECUTE_CI_WAIT_LIMIT_SECS=$BAD"
    new_case "limit-fallback-1000"; fixture checks '[{"name":"build","bucket":"pending"}]'; age 1000
    expect "limit [$BAD] falls back to 1800 (1000 s old)" "pending:checks"
    new_case "limit-fallback-1900"; fixture checks '[{"name":"build","bucket":"pending"}]'; age 1900
    expect "limit [$BAD] falls back to 1800 (1900 s old)" "error:execute:ci-timeout"
done
EXTRA_ENV=""

# ---------------------------------------------------------------------------
# Confirm mode
# ---------------------------------------------------------------------------

CONFIRM_ARGS=(--repo o/r --pr 7 --merge true --expected-head "$HEAD" --confirm)

new_case confirm-late
echo '{"state":"OPEN"}' > "$CASE/confirm.out.1"
echo '{"state":"OPEN"}' > "$CASE/confirm.out.2"
EXTRA_ENV="MERGE_CONFIRM_WAIT_SECS=10"
expect "confirm: OPEN, OPEN, then MERGED" "merged" "${CONFIRM_ARGS[@]}"
if [ "$(calls '^pr view')" -eq 3 ] && [ "$(wc -l < "$CASE/calls.log" | tr -d ' ')" -eq 3 ]; then
    pass "confirm made three state reads and nothing else"
else
    fail "confirm calls: $(cat "$CASE/calls.log")"
fi

new_case confirm-never; fixture confirm '{"state":"OPEN"}'
EXTRA_ENV="MERGE_CONFIRM_WAIT_SECS=2"
expect "confirm: OPEN throughout" "not-merged:merge-not-observed" "${CONFIRM_ARGS[@]}"
if grep -qv -- '--json state$' "$CASE/calls.log"; then
    fail "confirm evaluated another row: $(cat "$CASE/calls.log")"
else
    pass "confirm read only the PR state"
fi

new_case confirm-zero; fixture confirm '{"state":"OPEN"}'
EXTRA_ENV="MERGE_CONFIRM_WAIT_SECS=0"
expect "confirm: window 0 reads once" "not-merged:merge-not-observed" "${CONFIRM_ARGS[@]}"
[ "$(calls '^pr view')" -eq 1 ] && pass "confirm window 0 made one read" \
    || fail "confirm window 0 made $(calls '^pr view') reads"

new_case confirm-first
EXTRA_ENV=""
expect "confirm: MERGED on the first read" "merged" "${CONFIRM_ARGS[@]}"
[ "$(wc -l < "$CASE/calls.log" | tr -d ' ')" -eq 1 ] && pass "confirm on an already-merged PR made exactly one read" \
    || fail "confirm on an already-merged PR made: $(cat "$CASE/calls.log")"

new_case confirm-wide
EXTRA_ENV="MERGE_CONFIRM_WAIT_SECS=25"
expect "confirm: a wider window is ignored" "merged" "${CONFIRM_ARGS[@]}"
printf '%s' "$ERR" | grep -q 'ignoring MERGE_CONFIRM_WAIT_SECS' && pass "confirm window 25 refused with a diagnostic" \
    || fail "confirm window 25 was not refused: $ERR"
EXTRA_ENV=""

new_case confirm-merge-false
expect "confirm with --merge false" "merged" --repo o/r --pr 7 --merge false --expected-head none --confirm

# ---------------------------------------------------------------------------
# Isolation: no stdin, no workflow engine
# ---------------------------------------------------------------------------

TOOLS="$WORK/tools"
mkdir -p "$TOOLS"
ln -s "$(command -v jq)" "$TOOLS/jq"
ln -s "$(command -v bash)" "$TOOLS/bash"
BARE_PATH="$TOOLS:/usr/bin:/bin"
if PATH="$BARE_PATH" command -v koto >/dev/null 2>&1; then
    fail "isolation: koto is reachable from $BARE_PATH, so the absence case proves nothing"
else
    for C in r1 r6-pending r12-empty r14-paged r16-merge; do
        CASE="$WORK/cases/$C"
        rm -f "$CASE"/*.count
        : > "$CASE/calls.log"
        WANT=$(printf 'merge\nyes\n' | GH_FIX="$CASE" PATH="$BIN:$PATH" bash "$VERDICT" --repo o/r --pr 7 --merge true --expected-head "$HEAD" 2>/dev/null)
        rm -f "$CASE"/*.count
        GOT=$(GH_FIX="$CASE" PATH="$BIN:$BARE_PATH" bash "$VERDICT" --repo o/r --pr 7 --merge true --expected-head "$HEAD" </dev/null 2>/dev/null)
        if [ -n "$WANT" ] && [ "$WANT" = "$GOT" ]; then
            pass "isolation: [$C] same verdict with stdin closed and no koto on PATH ($GOT)"
        else
            fail "isolation: [$C] normal [$WANT] vs isolated [$GOT]"
        fi
    done
fi

# ---------------------------------------------------------------------------
# Static checks over both scripts
# ---------------------------------------------------------------------------

non_comment() {
    grep -v -E '^[[:space:]]*#' "$1"
}

for S in "$VERDICT" "$EXEC"; do
    NAME=$(basename "$S")
    HITS=$(non_comment "$S" | grep -nE 'koto|wip/|/dev/stdin')
    if [ -z "$HITS" ]; then
        pass "static: $NAME names no workflow engine, wip/, or /dev/stdin"
    else
        fail "static: $NAME: $HITS"
    fi
done

# bare_reads <file> — prints every non-comment `read` that takes its input from
# neither a here-string, a redirect, nor the redirect on its enclosing loop's
# `done`. A `while ... read` line is resolved by the next `done` line.
bare_reads() {
    awk '
        /^[[:space:]]*#/ { next }
        {
            line = $0
            if (pending != "" && line ~ /^[[:space:]]*done([[:space:]]|;|$)/) {
                if (line !~ /done[[:space:]]*<(<<)?/) print pending
                pending = ""
            }
            if (line ~ /(^|[;&|({[:space:]])read([[:space:]]|$)/) {
                rest = line
                sub(/.*(^|[;&|({[:space:]])read([[:space:]]|$)/, "", rest)
                if (rest ~ /</) next
                if (line ~ /while[[:space:]]/) {
                    if (line ~ /done[[:space:]]*</) next
                    pending = FILENAME ":" NR ": " line
                    next
                }
                print FILENAME ":" NR ": " line
            }
        }
        END { if (pending != "") print pending }
    ' "$1"
}

SAMPLE_OK="$WORK/read-ok.sh"
SAMPLE_BAD="$WORK/read-bad.sh"
cat > "$SAMPLE_OK" <<'EOF'
while IFS= read -r line; do
    echo "$line"
done <<<"$files"
read -r first <<<"$files"
read -r second < "$somefile"
EOF
cat > "$SAMPLE_BAD" <<'EOF'
read -r answer
EOF
if [ -z "$(bare_reads "$SAMPLE_OK")" ] && [ -n "$(bare_reads "$SAMPLE_BAD")" ]; then
    pass "static: the read check passes redirected reads and flags a bare one"
else
    fail "static: the read check misjudged its samples: ok [$(bare_reads "$SAMPLE_OK")] bad [$(bare_reads "$SAMPLE_BAD")]"
fi
for S in "$VERDICT" "$EXEC"; do
    BARE=$(bare_reads "$S")
    if [ -z "$BARE" ]; then
        pass "static: $(basename "$S") has no read from the terminal or caller's stdin"
    else
        fail "static: bare read: $BARE"
    fi
done

for S in "$VERDICT" "$EXEC"; do
    if grep -q '^set -uo pipefail$' "$S" \
        && ! non_comment "$S" | grep -qE 'declare -A|mapfile|readarray|\$\{[A-Za-z_]+,,\}|\$\{[A-Za-z_]+\^\^\}|\|&'; then
        pass "static: $(basename "$S") uses set -uo pipefail and no bash 4 feature"
    else
        fail "static: $(basename "$S") misses set -uo pipefail or uses a bash 4 feature"
    fi
    if non_comment "$S" | grep -qE 'date -[dj]|date --date'; then
        fail "static: $(basename "$S") uses platform date arithmetic"
    else
        pass "static: $(basename "$S") does no platform date arithmetic"
    fi
done

# ---------------------------------------------------------------------------
# Grammar: every verdict any case produced matches the header's list
# ---------------------------------------------------------------------------

GRAMMAR="$WORK/grammar"
sed -n 's/^#   \(\^.*\$\)$/\1/p' "$VERDICT" > "$GRAMMAR"
if [ "$(wc -l < "$GRAMMAR" | tr -d ' ')" -ge 7 ]; then
    pass "grammar: the header lists $(wc -l < "$GRAMMAR" | tr -d ' ') anchored patterns"
else
    fail "grammar: the header lists too few anchored patterns: $(cat "$GRAMMAR")"
fi
UNMATCHED=$(sort -u "$VERDICT_LOG" | grep -v -E -f "$GRAMMAR")
if [ -s "$VERDICT_LOG" ] && [ -z "$UNMATCHED" ]; then
    pass "grammar: all $(sort -u "$VERDICT_LOG" | wc -l | tr -d ' ') distinct verdicts match the header"
else
    fail "grammar: verdicts outside the header grammar: $UNMATCHED"
fi

echo ""
echo "merge-verdict_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
