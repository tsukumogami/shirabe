#!/usr/bin/env bash
# macos-floor-watchdog_test.sh -- test harness for
# scripts/macos-floor-watchdog.sh.
#
# Usage: bash scripts/macos-floor-watchdog_test.sh
#
# Each case runs the script against a stub gh, first on PATH, that serves the
# floor runs and the open issues a case writes, and records every dispatch,
# comment, close and new issue. The clock is fixed with WATCHDOG_NOW, and each
# run is written by its age in hours, so the cases read as the gap they test.
# Requires jq, like the script.
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/macos-floor-watchdog.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/macos-floor-watchdog-test.XXXXXX") || exit 1
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

mkdir "$T/bin" || exit 1
cat >"$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
# The stub gh: answers the calls macos-floor-watchdog.sh makes from the files
# under $STUB_DIR, and records each write. --jq is applied with the real jq.
printf '%s\n' "$*" >>"$STUB_DIR/calls"
jqf=""
body=""
prev=""
for a in "$@"; do
    [ "$prev" = "--jq" ] && jqf=$a
    case "$a" in body=@*) body=${a#body=@} ;; esac
    prev=$a
done
out() { if [ -n "$jqf" ]; then jq -r "$jqf"; else cat; fi; }
fails() { # fails <key>: refuse the call when the case asked for it
    if [ -f "$STUB_DIR/fail-$1" ]; then echo "gh: stub refusal (HTTP 500)" >&2; exit 1; fi
}
case "$*" in
    *"/actions/workflows/macos-floor.yml/runs"*)
        fails list
        jq -s '{workflow_runs: .}' "$STUB_DIR/runs" | out ;;
    *"/actions/workflows/macos-floor.yml/dispatches"*)
        fails dispatch
        echo dispatched >>"$STUB_DIR/dispatched" ;;
    *"-X GET repos/"*"/issues "*)
        fails issues
        jq -s '.' "$STUB_DIR/issues" | out ;;
    *"-X POST repos/"*"/issues/"*"/comments"*)
        fails comment
        cat "$body" >>"$STUB_DIR/commented" ;;
    *"/issues/"*"/comments"*)
        fails comments
        jq -s '.' "$STUB_DIR/comments" | out ;;
    *"-X PATCH repos/"*"/issues/"*)
        fails close
        echo "$*" >>"$STUB_DIR/closed" ;;
    *"-X POST repos/"*"/issues "*|*"-X POST repos/"*"/issues")
        fails create
        cat "$body" >>"$STUB_DIR/created"
        echo "https://github.com/owner/repo/issues/50" ;;
    *"repos/"*"/issues/"*)
        jq -n --arg b "$(cat "$STUB_DIR/issue-body" 2>/dev/null)" '{body: $b}' | out ;;
    *) echo "gh stub: unhandled: $*" >&2; exit 1 ;;
esac
exit 0
EOF
chmod +x "$T/bin/gh" || exit 1

# A fixed clock: 2026-10-22T12:00:00Z.
NOW=1792670400

iso() { # iso <hours ago>: the time that many hours before NOW
    jq -n -r --argjson s $((NOW - $1 * 3600)) '$s | todate'
}

N=0
CASE=""
fresh() { # a new stub directory in $CASE, with no runs and no issues
    N=$((N + 1))
    CASE="$T/case$N"
    mkdir "$CASE" && : >"$CASE/runs" && : >"$CASE/issues" && : >"$CASE/comments"
}

# add <id> <created hours ago> [key=value...]: one floor run as the API lists
# it, by default a scheduled run on main that succeeded an hour after it was
# created. finished=<hours ago> sets when it finished.
add() {
    local id=$1 created=$2; shift 2
    local status=completed conclusion=success title="macOS floor on main"
    local finished=$((created - 1)) kv
    [ "$finished" -lt 0 ] && finished=0
    for kv in "$@"; do
        case "$kv" in
            status=*) status=${kv#status=} ;;
            conclusion=*) conclusion=${kv#conclusion=} ;;
            title=*) title=${kv#title=} ;;
            finished=*) finished=${kv#finished=} ;;
        esac
    done
    [ "$status" = completed ] || conclusion=null
    jq -n -c --argjson id "$id" --arg status "$status" --arg conclusion "$conclusion" \
        --arg title "$title" --arg created "$(iso "$created")" --arg updated "$(iso "$finished")" \
        '{id: $id, status: $status, conclusion: (if $conclusion == "null" then null else $conclusion end),
          display_title: $title, created_at: $created, updated_at: $updated,
          html_url: "https://github.com/owner/repo/actions/runs/\($id)"}' >>"$CASE/runs"
}

issue() { # issue <number> [title] [pr]: an open issue the listing returns;
    # a third argument makes it a pull request, as the issues API lists them
    jq -n -c --argjson n "$1" --arg t "${2:-CI: the macOS floor run is missing}" --arg pr "${3:-}" \
        '{number: $n, title: $t} + (if $pr == "" then {} else {pull_request: {url: "x"}} end)' >>"$CASE/issues"
}

comment() { # comment <body>: a comment on the open issue
    jq -n -c --arg b "$1" '{body: $b}' >>"$CASE/comments"
}

RC=0
OUT=""
run() { # run [VAR=value...]: the script over $CASE
    RC=0
    OUT=$(env PATH="$T/bin:$PATH" STUB_DIR="$CASE" GITHUB_REPOSITORY=owner/repo \
        WATCHDOG_NOW=$NOW "$@" bash "$SCRIPT" 2>&1) || RC=$?
}
has() { grep -qF -- "$1" <<<"$OUT"; }
did() { [ -f "$CASE/$1" ]; }
none() { # none <file...>: none of the writes happened
    local f
    for f in "$@"; do [ -f "$CASE/$f" ] && return 1; done
    return 0
}

fresh
add 1 11
run
if [ "$RC" -eq 0 ] && has "The floor is current" && none dispatched created commented closed; then
    pass "a run that completed 10h ago is current: nothing dispatched, nothing filed"
else
    fail "current (rc=$RC): $OUT"
fi

fresh
add 1 11 conclusion=failure
run
if [ "$RC" -eq 0 ] && has "The floor is current" && none dispatched created commented; then
    pass "a red run is a verdict too: the red-run issue covers it, the watchdog stays quiet"
else
    fail "red run current (rc=$RC): $OUT"
fi

fresh
add 1 41 finished=40
run
if [ "$RC" -eq 0 ] && did dispatched && did created && none commented \
    && grep -qF "last-completed=1 -->" "$CASE/created" && grep -qF "Dispatched a floor run" "$CASE/created" \
    && grep -q "dispatches -f ref=main -f inputs\[ref\]=main" "$CASE/calls"; then
    pass "a run that completed 40h ago: one floor run dispatched on main and the issue filed"
else
    fail "stale, dispatch (rc=$RC): $OUT"
fi

fresh
add 1 36 finished=35
run
if [ "$RC" -eq 0 ] && has "The floor is current" && none dispatched created; then
    pass "35h since the last completed run is still current under the 36h default"
else
    fail "35h boundary (rc=$RC): $OUT"
fi

fresh
add 1 38 finished=37
run
if [ "$RC" -eq 0 ] && did dispatched && did created; then
    pass "37h since the last completed run is a missed day"
else
    fail "37h boundary (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
add 2 3 status=queued
run
if [ "$RC" -eq 0 ] && none dispatched && did created \
    && has "Not dispatching: a floor run on main is queued or running" \
    && grep -qF "runs/2" "$CASE/created"; then
    pass "never dispatches while a floor run is queued, and the issue names the queued run"
else
    fail "queued guard (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
add 2 3 status=in_progress
run
if [ "$RC" -eq 0 ] && none dispatched && did created; then
    pass "never dispatches while a floor run is in progress"
else
    fail "in-progress guard (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
add 2 20 conclusion=cancelled
run
if [ "$RC" -eq 0 ] && none dispatched && did created \
    && has "Not dispatching: a floor run on main was created in the last 24 hours"; then
    pass "dispatches at most once in 24h: a run created 20h ago and cancelled is not replaced yet"
else
    fail "24h guard (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
add 2 25 conclusion=cancelled
run
if [ "$RC" -eq 0 ] && did dispatched; then
    pass "a cancelled run created 25h ago no longer holds the dispatch back"
else
    fail "24h guard expiry (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
add 2 30 conclusion=cancelled
add 3 29 conclusion=timed_out
add 4 28 conclusion=startup_failure
run
if [ "$RC" -eq 0 ] && did dispatched && grep -qF "last-completed=1 -->" "$CASE/created"; then
    pass "cancelled, timed-out and never-started runs are not a completed floor run"
else
    fail "non-verdicts (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
add 2 30 title="macOS floor on feature/x"
run
if [ "$RC" -eq 0 ] && did created && grep -qF "last-completed=1 -->" "$CASE/created"; then
    pass "a run titled for another ref is not a run on main"
else
    fail "other title (rc=$RC): $OUT"
fi

fresh
run
if [ "$RC" -eq 0 ] && did dispatched && did created && grep -qF "last-completed=none -->" "$CASE/created" \
    && has "Last completed floor run on main: none found"; then
    pass "no floor run at all: dispatched and filed"
else
    fail "no runs (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
add 2 3 status=queued
issue 12
comment "an earlier note"
run
if [ "$RC" -eq 0 ] && did commented && none created dispatched && grep -qF "last-completed=1 -->" "$CASE/commented"; then
    pass "with the issue open, a new gap comments on it rather than filing another"
else
    fail "comment on open (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
add 2 3 status=queued
issue 12
comment "No macOS floor run ... <!-- macos-floor-watchdog: last-completed=1 -->"
run
if [ "$RC" -eq 0 ] && none commented created dispatched && has "#12 already flags this gap"; then
    pass "a gap already flagged on the open issue is not flagged again on the next fire"
else
    fail "dedupe (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
issue 12
printf '%s' "<!-- macos-floor-watchdog: last-completed=1 -->" >"$CASE/issue-body"
run
if [ "$RC" -eq 0 ] && did dispatched && did commented && none created; then
    pass "a dispatch is always reported, even on a gap already flagged"
else
    fail "dispatch comment (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
add 2 3 status=queued
issue 12
printf '%s' "<!-- macos-floor-watchdog: last-completed=1 -->" >"$CASE/issue-body"
run
if [ "$RC" -eq 0 ] && none commented created; then
    pass "the marker in the issue body counts as flagged"
else
    fail "marker in body (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
issue 13 "CI: the macOS floor run is missing again"
run
if [ "$RC" -eq 0 ] && did created && none commented; then
    pass "an open issue with a longer title is not the tracking issue"
else
    fail "title match (rc=$RC): $OUT"
fi

fresh
add 1 5
issue 12
run
if [ "$RC" -eq 0 ] && did commented && did closed && none dispatched created \
    && grep -qF "runs/1" "$CASE/commented" && grep -q "state=closed" "$CASE/closed"; then
    pass "once a floor run on main completes, the open issue gets a comment naming it and is closed"
else
    fail "close on recovery (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
run WATCHDOG_DRY_RUN=1
if [ "$RC" -eq 0 ] && none dispatched created commented closed \
    && has "Dry run: would dispatch" && has "Dry run: would file"; then
    pass "a dry run dispatches nothing and files nothing"
else
    fail "dry run stale (rc=$RC): $OUT"
fi

fresh
add 1 5
issue 12
run WATCHDOG_DRY_RUN=1
if [ "$RC" -eq 0 ] && none commented closed && has "Dry run: would comment on #12 and close it"; then
    pass "a dry run on a current floor closes nothing"
else
    fail "dry run current (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
run STALE_HOURS=60
if [ "$RC" -eq 0 ] && has "The floor is current" && none dispatched created; then
    pass "STALE_HOURS moves the threshold"
else
    fail "STALE_HOURS (rc=$RC): $OUT"
fi

fresh
: >"$CASE/fail-list"
run
if [ "$RC" -eq 1 ] && has "could not list the macos-floor.yml runs" && none dispatched created; then
    pass "a failed run listing exits 1 and writes nothing"
else
    fail "list failure (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
: >"$CASE/fail-issues"
run
if [ "$RC" -eq 1 ] && has "could not list the open issues" && none dispatched created; then
    pass "a failed issue listing exits 1 before any write"
else
    fail "issue listing failure (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
run
if [ "$RC" -eq 0 ] && grep -q -- "--paginate -X GET repos/owner/repo/issues -f state=open" "$CASE/calls" \
    && ! grep -q "search/" "$CASE/calls"; then
    pass "the tracking issue is found by listing open issues, paginated, not through the lagging search"
else
    fail "issue listing (rc=$RC, calls: $(cat "$CASE/calls")): $OUT"
fi

fresh
add 1 50 finished=49
add 2 3 status=queued
issue 14 "CI: the macOS floor run is missing" pr
run
if [ "$RC" -eq 0 ] && did created && none commented; then
    pass "an open pull request with the tracking title is not the tracking issue"
else
    fail "pull request title (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
: >"$CASE/fail-dispatch"
run
if [ "$RC" -eq 1 ] && has "could not dispatch" && none created; then
    pass "a failed dispatch exits 1"
else
    fail "dispatch failure (rc=$RC): $OUT"
fi

fresh
add 1 50 finished=49
: >"$CASE/fail-create"
run
if [ "$RC" -eq 1 ] && has "could not file"; then
    pass "a failed issue creation exits 1"
else
    fail "create failure (rc=$RC): $OUT"
fi

fresh
run GITHUB_REPOSITORY=
if [ "$RC" -eq 2 ] && has "GITHUB_REPOSITORY is not set" && [ ! -f "$CASE/calls" ]; then
    pass "an incomplete environment exits 2 before any API call"
else
    fail "missing env (rc=$RC): $OUT"
fi

fresh
run STALE_HOURS=abc
if [ "$RC" -eq 2 ] && [ ! -f "$CASE/calls" ]; then
    pass "a STALE_HOURS that isn't a number exits 2 before any API call"
else
    fail "bad STALE_HOURS (rc=$RC): $OUT"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
