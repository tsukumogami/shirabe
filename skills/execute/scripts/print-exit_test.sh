#!/usr/bin/env bash
# print-exit_test.sh — every row of the outcome-versus-exit table, rendered
# Part of the execute skill
#
# print-exit.sh turns a terminal result into /execute's exit lines. Each case
# feeds it a result payload shaped like the one the template's result maps
# produce for that stop point, and asserts the exact lines. The rows are the
# stop-point-to-exit mapping print-exit.sh applies (SKILL.md Exit Paths):
#
#   merged terminal                                  full-run      merged
#   ready_awaiting_merge terminal, and legacy done   full-run      ready-awaiting-merge
#   paused_for_review                                (unset)       paused-for-review
#   done_blocked via DIRTY                           abandonment-forced  ready-awaiting-merge
#   done_blocked via a verdict error / a blocker     abandonment-forced  error + step
#   re-evaluation                                    re-evaluation error, execute:re-evaluation
#   coordinated: merged / nothing left / a node waits on a predecessor / a
#     coord_setup stop (its reason on a line of its own) / a body the last
#     render couldn't post (body=stale, body=full) / the merge refusals /
#     a render refusal (execute:visibility) / a recovery's stops and the
#     five follow-up stops / a follow-up closed unmerged
#     (follow-up-closed:<url>, dropped without a URL), and a recovered run's
#     recovered=<url> line (dropped outside the URL pattern)
#
# plus the refused case (outcome=error, step=execute:refused), the
# merge-not-observed note, the three input shapes, and values that fail their
# pattern being dropped.
#
# Usage: print-exit_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PRINT="$SCRIPT_DIR/print-exit.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

URL="https://github.com/o/r/pull/7"
URL2="https://github.com/o/s/pull/9"

# result <status> <jq object for the payload> — a `koto next` terminal response.
result() {
    jq -nc --arg status "$1" "{action: \"done\", state: \"x\", result: {status: \$status, summary: \"s\", payload: ($2)}}"
}

# check <label> <json> <expected lines>
check() {
    local label="$1" json="$2" want="$3" got
    got=$(printf '%s' "$json" | bash "$PRINT")
    if [ "$got" = "$want" ]; then
        pass "$label"
    else
        fail "$label
--- want
$want
--- got
$got"
    fi
}

# --- the single-pr rows -------------------------------------------------------

check "merged terminal" \
    "$(result success '{outcome: "merged", step: "", reason: "", pr: "https://github.com/o/r/pull/7", repos: "o/r", resume: "", waiting: ""}')" \
"outcome=merged
exit=full-run
repos=o/r
pr=$URL"

check "ready_awaiting_merge terminal (merge not requested)" \
    "$(result success '{outcome: "ready-awaiting-merge", step: "", reason: "merge-not-requested", pr: "https://github.com/o/r/pull/7", repos: "o/r", resume: "", waiting: "https://github.com/o/r/pull/7:human"}')" \
"outcome=ready-awaiting-merge
exit=full-run
repos=o/r
pr=$URL waiting=human reason=merge-not-requested"

check "ready_awaiting_merge terminal (review required)" \
    "$(result success '{outcome: "ready-awaiting-merge", reason: "merge-state:BLOCKED:review=REVIEW_REQUIRED", pr: "https://github.com/o/r/pull/7", repos: "o/r", waiting: "https://github.com/o/r/pull/7:human"}')" \
"outcome=ready-awaiting-merge
exit=full-run
repos=o/r
pr=$URL waiting=human reason=merge-state:BLOCKED:review=REVIEW_REQUIRED"

check "legacy done terminal (outcome literal, nothing else recorded)" \
    "$(result success '{outcome: "ready-awaiting-merge", step: "", reason: "", pr: "", repos: "", resume: "", waiting: "", missing: ["step","reason","pr","repos","resume","waiting"]}')" \
"outcome=ready-awaiting-merge
exit=full-run"

check "paused_for_review" \
    "$(result success '{outcome: "paused-for-review", pr: "https://github.com/o/r/pull/7", repos: "o/r", resume: "/execute docs/plans/PLAN-topic.md", waiting: "https://github.com/o/r/pull/7:human"}')" \
"outcome=paused-for-review
repos=o/r
pr=$URL waiting=human
resume=/execute docs/plans/PLAN-topic.md"

check "done_blocked via DIRTY" \
    "$(result failure '{outcome: "ready-awaiting-merge", step: "", reason: "merge-state:DIRTY", pr: "https://github.com/o/r/pull/7", repos: "o/r", waiting: "https://github.com/o/r/pull/7:human"}')" \
"outcome=ready-awaiting-merge
exit=abandonment-forced
repos=o/r
pr=$URL waiting=human reason=merge-state:DIRTY"

check "done_blocked via a verdict error (ci-timeout)" \
    "$(result failure '{outcome: "error", step: "execute:ci-timeout", reason: "", pr: "https://github.com/o/r/pull/7", repos: "o/r", waiting: "https://github.com/o/r/pull/7:human"}')" \
"outcome=error
step=execute:ci-timeout
exit=abandonment-forced
repos=o/r
pr=$URL waiting=human"

check "done_blocked via another blocker (ci unresolvable)" \
    "$(result failure '{outcome: "error", step: "execute:ci", pr: "https://github.com/o/r/pull/7", repos: "o/r", waiting: "https://github.com/o/r/pull/7:human"}')" \
"outcome=error
step=execute:ci
exit=abandonment-forced
repos=o/r
pr=$URL waiting=human"

check "done_blocked before any PR (a state name as the step)" \
    "$(result failure '{outcome: "error", step: "execute:settled_branch_record", repos: "o/r"}')" \
"outcome=error
step=execute:settled_branch_record
exit=abandonment-forced
repos=o/r"

check "re-evaluation" \
    "$(result failure '{outcome: "error", step: "execute:re-evaluation", pr: "https://github.com/o/r/pull/7", repos: "o/r", waiting: "https://github.com/o/r/pull/7:human"}')" \
"outcome=error
step=execute:re-evaluation
exit=re-evaluation
repos=o/r
pr=$URL waiting=human"

check "merge call failed" \
    "$(result success '{outcome: "ready-awaiting-merge", reason: "merge-call-failed", pr: "https://github.com/o/r/pull/7", repos: "o/r", waiting: "https://github.com/o/r/pull/7:human"}')" \
"outcome=ready-awaiting-merge
exit=full-run
repos=o/r
pr=$URL waiting=human reason=merge-call-failed"

check "merge not observed carries the may-still-be-queued line" \
    "$(result success '{outcome: "ready-awaiting-merge", reason: "merge-not-observed", pr: "https://github.com/o/r/pull/7", repos: "o/r", waiting: "https://github.com/o/r/pull/7:human"}')" \
"outcome=ready-awaiting-merge
exit=full-run
repos=o/r
pr=$URL waiting=human reason=merge-not-observed
note=the PR may still be queued and may merge later"

# --- the coordinated rows (same payload shape) --------------------------------

check "coordinated: the coordination PR merged" \
    "$(result success '{outcome: "merged", pr: "https://github.com/o/r/pull/7", repos: "o/r,o/s", waiting: ""}')" \
"outcome=merged
exit=full-run
repos=o/r,o/s
pr=$URL"

check "coordinated: nothing left to start, something unmerged" \
    "$(result success '{outcome: "ready-awaiting-merge", reason: "review", pr: "https://github.com/o/r/pull/7", repos: "o/r,o/s", waiting: "https://github.com/o/r/pull/7:human,https://github.com/o/s/pull/9:human"}')" \
"outcome=ready-awaiting-merge
exit=full-run
repos=o/r,o/s
pr=$URL waiting=human reason=review
pr=$URL2 waiting=human reason=review"

check "coordinated: a node waits on an unmerged predecessor" \
    "$(result success '{outcome: "paused-awaiting-merges", repos: "o/r,o/s", resume: "/execute docs/plans/PLAN-topic.md", waiting: "https://github.com/o/s/pull/9:predecessor"}')" \
"outcome=paused-awaiting-merges
repos=o/r,o/s
pr=$URL2 waiting=predecessor
resume=/execute docs/plans/PLAN-topic.md"

check "coordinated: a pause naming its condition, resumed with --merge" \
    "$(result success '{outcome: "paused-awaiting-merges", repos: "o/r", reason: "merge-not-observed", resume: "/execute docs/plans/PLAN-topic.md --merge", waiting: "https://github.com/o/r/pull/7:human,https://github.com/o/s/pull/9:predecessor", pr: "https://github.com/o/s/pull/9"}')" \
"outcome=paused-awaiting-merges
repos=o/r
pr=$URL waiting=human reason=merge-not-observed
pr=$URL2 waiting=predecessor reason=merge-not-observed
resume=/execute docs/plans/PLAN-topic.md --merge
note=the PR may still be queued and may merge later"

check "coordinated: a pause whose only condition is the pause itself" \
    "$(result success '{outcome: "paused-awaiting-merges", repos: "o/r", reason: "predecessor-unmerged", resume: "/execute docs/plans/PLAN-topic.md", waiting: "https://github.com/o/s/pull/9:predecessor"}')" \
"outcome=paused-awaiting-merges
repos=o/r
pr=$URL2 waiting=predecessor reason=predecessor-unmerged
resume=/execute docs/plans/PLAN-topic.md"

# --- the coordination body's render, and the merge refusals ---------------------
#
# The coordinated terminals carry `body`, the last render's token: a body that
# could not be posted (stale) or was over the cap (full) gets its own line,
# after the PR lines; posted, unchanged and an absent token print nothing.

check "coordinated: a body the render could not post prints body=stale" \
    "$(result success '{outcome: "ready-awaiting-merge", reason: "merge-refused:body-stale", repos: "o/r", waiting: "https://github.com/o/r/pull/7:human", body: "stale"}')" \
"outcome=ready-awaiting-merge
exit=full-run
repos=o/r
pr=$URL waiting=human reason=merge-refused:body-stale
body=stale"

check "coordinated: a body over the cap prints body=full" \
    "$(result success '{outcome: "ready-awaiting-merge", reason: "merge-refused:body-full", repos: "o/r", waiting: "https://github.com/o/r/pull/7:human", body: "full"}')" \
"outcome=ready-awaiting-merge
exit=full-run
repos=o/r
pr=$URL waiting=human reason=merge-refused:body-full
body=full"

for b in posted unchanged "" "refused:execute:visibility" "bogus"; do
    P=$(jq -nc --arg u "$URL" --arg b "$b" '{outcome: "merged", pr: $u, repos: "o/r", waiting: "", body: $b}')
    check "coordinated: body [$b] prints no body line" "$(result success "$P")" \
"outcome=merged
exit=full-run
repos=o/r
pr=$URL"
done

for r in merge-refused merge-refused:squash-message; do
    P=$(jq -nc --arg u "$URL" --arg r "$r" '{outcome: "ready-awaiting-merge", reason: $r, pr: $u, repos: "o/r", waiting: ($u + ":human")}')
    check "a merge refusal reason is kept: $r" "$(result success "$P")" \
"outcome=ready-awaiting-merge
exit=full-run
repos=o/r
pr=$URL waiting=human reason=$r"
done

check "a render refusal ends at done_blocked naming execute:visibility" \
    "$(result failure '{outcome: "error", step: "execute:visibility", repos: "o/r", pr: "https://github.com/o/r/pull/7", waiting: "", body: "refused:execute:visibility"}')" \
"outcome=error
step=execute:visibility
exit=abandonment-forced
repos=o/r
pr=$URL waiting=human"

# --- coordinated setup stops ----------------------------------------------------
#
# coord_setup's typed stops end at done_error with a literal reason and no PR:
# the reason is printed on a line of its own.

for r in store-mismatch coordination-pr-missing coordination-pr-ambiguous coordination-pr-mismatch coordination-pr-closed \
    session-absent recovery-unproven recovery-plan-gone coordination-index-missing coordination-body-full adopt-run-refused \
    follow-up-node follow-up-repo follow-up-base follow-up-author follow-up-closed worktree-isolated; do
    STOP=$(jq -nc --arg r "$r" '{action: "done", state: "done_error", result: {status: "failure", summary: "s",
        payload: {outcome: "error", step: "execute:coord_setup", reason: $r, pr: "", repos: "", waiting: "", recovered: ""}}}')
    check "a coord_setup stop: $r" "$STOP" \
"outcome=error
step=execute:coord_setup
exit=abandonment-forced
reason=$r"
done

# --- a follow-up closed unmerged ------------------------------------------------
#
# The loop's reason for one carries its URL; a value that isn't a URL is
# dropped from the PR line.

FU_URL="https://github.com/o/r/pull/21"
P=$(jq -nc --arg u "$FU_URL" '{outcome: "ready-awaiting-merge", reason: ("follow-up-closed:" + $u), pr: "https://github.com/o/r/pull/10", repos: "o/r", waiting: ($u + ":human,https://github.com/o/r/pull/10:predecessor")}')
check "a follow-up closed unmerged: reason=follow-up-closed:<url>" "$(result success "$P")" \
"outcome=ready-awaiting-merge
exit=full-run
repos=o/r
pr=$FU_URL waiting=human reason=follow-up-closed:$FU_URL
pr=https://github.com/o/r/pull/10 waiting=predecessor reason=follow-up-closed:$FU_URL"
P=$(jq -nc --arg u "$FU_URL" '{outcome: "ready-awaiting-merge", reason: "follow-up-closed:not-a-url", pr: "https://github.com/o/r/pull/10", repos: "o/r", waiting: ($u + ":human")}')
check "follow-up-closed: with no URL is dropped" "$(result success "$P")" \
"outcome=ready-awaiting-merge
exit=full-run
repos=o/r
pr=$FU_URL waiting=human"

# --- a recovered run ------------------------------------------------------------
#
# A run whose setup rebuilt its record in this invocation says so with the
# coordination PR's URL, after the PR lines; anything outside the URL pattern
# prints nothing.

check "coordinated: a recovered run prints recovered=<url>" \
    "$(result success '{outcome: "paused-awaiting-merges", reason: "predecessor-unmerged", repos: "o/r", waiting: "https://github.com/o/r/pull/7:human", resume: "/execute docs/plans/PLAN-t.md", recovered: "https://github.com/o/r/pull/10"}')" \
"outcome=paused-awaiting-merges
repos=o/r
pr=$URL waiting=human reason=predecessor-unmerged
recovered=https://github.com/o/r/pull/10
resume=/execute docs/plans/PLAN-t.md"
for v in "" "not a url" "https://github.com/o/r/pull/10
x"; do
    P=$(jq -nc --arg u "$URL" --arg v "$v" '{outcome: "merged", pr: $u, repos: "o/r", waiting: "", recovered: $v}')
    check "coordinated: recovered [$(printf '%s' "$v" | tr '\n' ' ')] prints no recovered line" "$(result success "$P")" \
"outcome=merged
exit=full-run
repos=o/r
pr=$URL"
done

# --- refusals -----------------------------------------------------------------

got=$(bash "$PRINT" --refused)
if [ "$got" = "outcome=error
step=execute:refused" ]; then
    pass "--refused prints outcome=error and step=execute:refused"
else
    fail "--refused printed [$got]"
fi

check "a refused payload (a leg's refusal record) is printed as error, never as refused" \
    "$(jq -nc '{status: "failure", summary: "refused", payload: {outcome: "refused", reason: "template-mismatch"}}')" \
"outcome=error
step=execute:refused"

# --- input shapes -------------------------------------------------------------

STATUS_JSON=$(jq -nc '{name: "execute-t", current_state: "merged", is_terminal: true,
    result: {status: "success", summary: "s", payload: {outcome: "merged", pr: "https://github.com/o/r/pull/7", repos: "o/r"}}}')
check "koto status on a retained terminal" "$STATUS_JSON" \
"outcome=merged
exit=full-run
repos=o/r
pr=$URL"

BARE=$(jq -nc '{status: "success", summary: "s", payload: {outcome: "merged", pr: "https://github.com/o/r/pull/7", repos: "o/r"}}')
check "a bare result object" "$BARE" \
"outcome=merged
exit=full-run
repos=o/r
pr=$URL"

FILE="${TMPDIR:-/tmp}/print-exit-test.$$.json"
printf '%s' "$BARE" > "$FILE"
got=$(bash "$PRINT" "$FILE")
rm -f "$FILE"
[ "$(head -1 <<<"$got")" = "outcome=merged" ] && pass "reads a file argument" || fail "file argument: [$got]"

# --- values that fail their pattern are dropped -------------------------------

check "an injected PR URL, repos list, reason, and resume are dropped" \
    "$(result success '{outcome: "ready-awaiting-merge", reason: "review; rm -rf /", pr: "https://github.com/o/r/pull/7 && curl x", repos: "o/r;x", resume: "/execute x.md; rm", waiting: "javascript:alert(1):human,https://github.com/o/r/pull/7:owner"}')" \
"outcome=ready-awaiting-merge
exit=full-run"

check "a multi-line value is dropped" \
    "$(result success '{outcome: "merged", pr: "https://github.com/o/r/pull/7\nevil=1", repos: "o/r"}')" \
"outcome=merged
exit=full-run
repos=o/r"

check "an unknown outcome is an error the run could not read" \
    "$(result success '{outcome: "shipped", repos: "o/r"}')" \
"outcome=error
step=execute:status-read
exit=abandonment-forced
repos=o/r"

check "no outcome at all (an old session's evidence payload)" \
    "$(result success '{failure_reason: "x"}')" \
"outcome=error
step=execute:status-read
exit=abandonment-forced"

check "error with a malformed step falls back to status-read" \
    "$(result failure '{outcome: "error", step: "Execute:CI"}')" \
"outcome=error
step=execute:status-read
exit=abandonment-forced"

got=$(printf 'not json' | bash "$PRINT" 2>/dev/null)
rc=$?
if [ "$rc" -eq 65 ] && [ -z "$got" ]; then
    pass "input that is not JSON: exit 65, nothing printed"
else
    fail "not JSON: exit $rc, [$got]"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
