#!/usr/bin/env bash
# ci-passing-timeout_test.sh -- does ci_passing read green on a passing pull
# request whose check reads take pr-checks.sh's REST fallback and run longer
# than koto's 30-second command-gate default (#1809)?
#
# A command gate with no `timeout:` of its own runs under koto's 30 s
# default, and koto reads a gate it killed as exit -1, which no ci_monitor
# edge matches: the run holds at ci_monitor however green its checks are.
# The REST fallback (GitHub refusing the check read, #1132) is several reads
# in a row, and on a loaded host one pass took about 28 s, so the gate's whole
# command didn't fit.
#
# Two parts:
#
#   declared  koto's own compile of work-on.md and execute.md gives ci_passing
#             and owned_ci_passing a timeout of at least MIN_TIMEOUT seconds.
#             Read from the compiled template, so it is the value koto runs.
#   slow      the SHIPPED ci_monitor block, with ci_passing's command and
#             timeout unchanged (merge_state_clean and probe_value_absent
#             stubbed to pass, ci_pass_counting a stub terminal), run under
#             real koto against a stub gh that refuses the check read and
#             answers the fallback green, slowly. One tick must reach
#             ci_pass_counting.
#
# Why the slow case sleeps: the only way to show the gate no longer runs
# under the 30 s default is to make its command take longer than that. The
# stub sleeps SLEEP_PER_READ seconds on each of the fallback's five REST
# reads, about 35 s in all, so this file takes that long. It is one case on
# purpose. skills/work-on/scripts/pr-checks_test.sh covers what the fallback
# lists and how the gate filter reads it; this file covers only the time limit.
#
# Usage: ci-passing-timeout_test.sh
# Exit codes: 0 all pass, 1 any failed, 0 with a skip notice when koto is absent.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
WORK_ON="$REPO_ROOT/skills/work-on/koto-templates/work-on.md"
EXECUTE="$REPO_ROOT/skills/execute/koto-templates/execute.md"

# The fallback's reads took about 28 s by hand on a loaded host, and the
# not-green path can make up to three of them; a limit under 120 s leaves too
# little room for even two.
MIN_TIMEOUT=120
SLEEP_PER_READ=7

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { echo "SKIP: $*"; }

command -v jq >/dev/null || { echo "ci-passing-timeout_test: jq is required" >&2; exit 1; }
command -v git >/dev/null || { echo "ci-passing-timeout_test: git is required" >&2; exit 1; }
if ! command -v koto >/dev/null 2>&1; then
    skip "koto not on PATH; the gate's time limit can't be read or run without the engine"
    exit 0
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/ci-passing-timeout-test.XXXXXX") || exit 1
cleanup() { rm -rf "$T"; return 0; }
ktg_on_exit cleanup

# ---------------------------------------------------------------------------
# Declared: the limit koto compiles for each CI-green gate
# ---------------------------------------------------------------------------

# compiled_timeout <template> <gate>: the gate's timeout in koto's compiled
# template, in whichever state carries it; 0 when it sets none (koto's
# default), empty when the template doesn't compile or has no such gate.
compiled_timeout() {
    local json
    json=$(koto template compile "$1" 2>/dev/null | tail -n 1) || return 1
    [ -f "$json" ] || return 1
    jq -r --arg g "$2" '[.states[] | .gates[$g]? // empty | .timeout // 0] | first // empty' "$json"
}

for entry in "$WORK_ON:ci_passing" "$EXECUTE:owned_ci_passing"; do
    template="${entry%:*}"
    gate="${entry##*:}"
    got=$(compiled_timeout "$template" "$gate")
    if [ -z "$got" ]; then
        fail "$gate: could not read its compiled timeout from $(basename "$template")"
    elif [ "$got" -ge "$MIN_TIMEOUT" ]; then
        pass "$gate declares a timeout of $got s (at least $MIN_TIMEOUT)"
    else
        fail "$gate declares a timeout of $got s; 0 is koto's 30 s default, and it needs at least $MIN_TIMEOUT"
    fi
done

# ---------------------------------------------------------------------------
# Slow: the shipped ci_monitor, a passing pull request, the fallback past 30 s
# ---------------------------------------------------------------------------

R=acme/widgets
BRANCH=impl/x
H=1111111111111111111111111111111111111111
FIX="$T/fixture"
mkdir -p "$T/bin" "$FIX" || exit 1

# gh, as GitHub answers a fine-grained token that can't read check runs:
#   pr list ...            pull request 7 on the branch
#   pr checks ...          the refusal, exit 1
#   pr view ...            pull request 7 at head $H, base main
#   api --method GET ...   the fallback's five reads: one passing run with one
#                          passing job, no statuses, an unprotected base and no
#                          rules; each sleeps SLEEP_PER_READ seconds first
# koto runs the gate in a cleared environment, so the stub finds its fixture
# beside itself rather than through a variable.
cat > "$T/bin/gh" <<STUB
#!/usr/bin/env bash
FIX="$FIX"
H="$H"
R="$R"
BRANCH="$BRANCH"
SLEEP_PER_READ="$SLEEP_PER_READ"
STUB
cat >> "$T/bin/gh" <<'STUB'
echo "$*" >> "$FIX/gh.log"
jqf=""
prev=""
for a in "$@"; do
    [ "$prev" = "--jq" ] && jqf="$a"
    prev="$a"
done
out() { if [ -n "$jqf" ]; then jq -r "$jqf"; else cat; fi; }
case "$1 ${2:-}" in
    "pr list") echo '[{"number": 7}]' | out ;;
    "pr checks")
        echo "GraphQL: Resource not accessible by personal access token (node.statusCheckRollup)" >&2
        exit 1 ;;
    "pr view")
        jq -n --arg u "https://github.com/$R/pull/7" --arg h "$H" --arg b "$BRANCH" \
            '{url: $u, headRefOid: $h, headRefName: $b, baseRefName: "main"}' | out ;;
    "api --method")
        sleep "$SLEEP_PER_READ"
        path="${4%%\?*}"
        case "$path" in
            repos/*/*/actions/runs)
                jq -n --arg h "$H" --arg r "$R" '{total_count: 1, workflow_runs: [{id: 100, name: "CI",
                    workflow_id: 5, event: "pull_request", head_sha: $h, status: "completed",
                    conclusion: "success", run_attempt: 1, created_at: "2026-11-13T07:00:00Z",
                    run_started_at: "2026-11-13T07:00:00Z", html_url: "https://github.com/\($r)/actions/runs/100"}]}' ;;
            repos/*/*/actions/runs/100/jobs)
                jq -n --arg r "$R" '{total_count: 1, jobs: [{id: 1001, run_id: 100, name: "test",
                    status: "completed", conclusion: "success", started_at: "2026-11-13T07:01:00Z",
                    completed_at: "2026-11-13T07:02:00Z", run_attempt: 1,
                    steps: [{name: "step", conclusion: "success"}],
                    html_url: "https://github.com/\($r)/actions/runs/100/job/1001"}]}' ;;
            repos/*/*/commits/*/status) echo '{"state": "pending", "total_count": 0, "statuses": []}' ;;
            repos/*/*/rules/branches/*) echo '[]' ;;
            repos/*/*/branches/*) echo '{"protected": false}' ;;
            *) echo "gh stub: unexpected path: $*" >&2; exit 1 ;;
        esac ;;
    *) echo "gh stub: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$T/bin/gh" || exit 1

# The repository the gate runs in, on the pull request's branch.
REPO="$T/repo"
mkdir -p "$REPO" || exit 1
git -C "$REPO" init -q || exit 1
git -C "$REPO" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init || exit 1
git -C "$REPO" checkout -q -b "$BRANCH" || exit 1

# The shipped ci_monitor block, as ci-monitor-role_test.sh reads it.
CI_MONITOR=$(awk '
    $0 == "  ci_monitor:" { found = 1; print; next }
    found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
    found { print }
' "$WORK_ON")
[ -n "$CI_MONITOR" ] || { echo "ci-passing-timeout_test: ci_monitor not found in $WORK_ON" >&2; exit 1; }

# Every gate but ci_passing passes, so the tick routes on ci_passing alone.
STUBBED=$(printf '%s\n' "$CI_MONITOR" | awk '
    /^      [a-z_]+:$/ { gate = $1; sub(/:$/, "", gate) }
    /^        command:/ && gate != "ci_passing" { print "        command: \"exit 0\""; next }
    { print }
')

cat > "$T/fixture.md" <<FIXTURE
---
name: ci-passing-timeout-fixture
version: "1.0"
description: Fixture running the shipped ci_passing gate past koto's default time limit.
initial_state: start
variables:
  PLUGIN_ROOT:
    description: Plugin root ci_passing reaches pr-checks.sh through
    required: false
states:
  start:
    transitions:
      - target: ci_monitor
$STUBBED
  ci_pass_counting:
    terminal: true
  done_blocked:
    terminal: true
    failure: true
    accepts:
      failure_reason:
        type: string
---

## start
Stand-in for pr_creation.

## ci_monitor
Green CI routes on the gates.

## ci_pass_counting
Stand-in terminal: green CI reached it.

## done_blocked
Blocked.
FIXTURE

SESSION="ci-timeout-$$"
STARTED=$(date +%s)
RESP=$(cd "$REPO" && env PATH="$T/bin:$PATH" koto init "$SESSION" --template "$T/fixture.md" \
    --var PLUGIN_ROOT="$REPO_ROOT" >/dev/null 2>"$T/init.err" \
    && env PATH="$T/bin:$PATH" koto next "$SESSION" --no-cleanup 2>"$T/next.err")
TOOK=$(( $(date +%s) - STARTED ))
STATE=$(printf '%s' "$RESP" | jq -r '.state // empty' 2>/dev/null)

if [ "$TOOK" -le 30 ]; then
    fail "slow: the tick took $TOOK s; the stub's reads must run past 30 s for this case to mean anything (gh calls: $(wc -l < "$FIX/gh.log" 2>/dev/null))"
elif [ "$STATE" = "ci_pass_counting" ]; then
    pass "slow: a passing pull request read through the fallback in $TOOK s reaches ci_pass_counting"
else
    # The gate's own finding, which on a 30 s limit says the command timed out.
    why=$(printf '%s' "$RESP" | jq -r '[.blocking_conditions[]? | select(.name == "ci_passing") | .failure.findings[]?.message] | join("; ")' 2>/dev/null)
    fail "slow: after $TOOK s the run is at [${STATE:-no state}], not ci_pass_counting: ${why:-$(head -c 400 "$T/init.err" "$T/next.err" 2>/dev/null)}"
fi

echo
echo "ci-passing-timeout_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" = 0 ]
