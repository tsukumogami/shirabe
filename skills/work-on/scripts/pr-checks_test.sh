#!/usr/bin/env bash
# pr-checks_test.sh -- does pr-checks.sh read a pull request's checks the way
# `gh pr checks` does, from the Actions runs and the commit's statuses when
# GitHub refuses the check read, and never read a check it can't see as green
# (#1132)?
#
# Three parts:
#
#   allowed   the check read answers: gh's stdout, stderr and exit status pass
#             through unchanged, and nothing else is read
#   refused   the check read answers 403: the list built from the runs, jobs
#             and statuses, its buckets, the required checks nothing answers,
#             the adversarial shapes (a run for another head, a later run of
#             a workflow, a renamed job, a re-run's earlier attempt, a pinned
#             app, a ruleset rule whose checks only the rollup names), no
#             checks, and a fallback read that fails
#   wiring    work-on.md's ci_passing and execute.md's owned_ci_passing
#             EXTRACTED FROM THE TEMPLATES, with {{PLUGIN_ROOT}},
#             {{SESSION_NAME}} and {{PLAN_SLUG}} substituted as koto would,
#             under a refused check read: green, red, pending and unreadable;
#             and execute's coord-common.sh and execute-coordinated.md read
#             checks through pr-checks.sh, never directly
#
# gh and koto are stubs on PATH, so no case reaches GitHub or a real session.
# The gh stub answers `pr checks` from a fixture, or with the refusal GitHub
# gives a fine-grained token ("GraphQL: Resource not accessible by personal
# access token") when the case refuses it, and answers the REST reads the
# fallback makes from per-case lists. --jq is applied with jq, as gh does.
#
# Usage: pr-checks_test.sh
# Exit codes: 0 all pass, 1 any failed.
#
# Bash 3.2: no associative arrays, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
WORK_ON="$REPO_ROOT/skills/work-on/koto-templates/work-on.md"
EXECUTE="$REPO_ROOT/skills/execute/koto-templates/execute.md"
SCRIPT="$SCRIPT_DIR/pr-checks.sh"

# shellcheck source=../../../scripts/lib/koto-gates.sh
. "$REPO_ROOT/scripts/lib/koto-gates.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

command -v jq >/dev/null || { echo "pr-checks_test: jq is required" >&2; exit 1; }
command -v git >/dev/null || { echo "pr-checks_test: git is required" >&2; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/pr-checks-test.XXXXXX") || exit 1
cleanup() { rm -rf "$T"; return 0; }
ktg_on_exit cleanup

R=acme/widgets
ME=octo
MINE=0123456789abcdef0123456789abcdef
BRANCH=impl/x
H=1111111111111111111111111111111111111111
OTHER_SHA=2222222222222222222222222222222222222222
FIX="$T/fixture"
REFUSAL="GraphQL: Resource not accessible by personal access token (node.statusCheckRollup.nodes.0.commit.statusCheckRollup.contexts.nodes.0)"

# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

mkdir -p "$T/bin" || exit 1

# gh:
#   pr checks ...                  $FIX/refuse: the refusal on stderr, exit 1;
#                                  else $FIX/checks.err (stderr, exit 1) or
#                                  $FIX/checks.json, with --jq applied
#   pr view ...                    $FIX/view.json, with --jq applied
#   pr list ...                    $FIX/prs.json, by --state as gh filters
#   api user                       {"login": $ME}
#   api repos/<r>/contents/...     404: no hosted-CI declaration
#   api repos/<r>                  {"default_branch": "main"}
#   api --method GET <path> ...    the fallback's reads, from the case's lists:
#     .../actions/runs             runs.list (one run per line)
#     .../actions/runs/<id>/jobs   jobs-<id>.list
#     .../commits/<sha>/status     statuses.list
#     .../branches/<b>             branch.json, else {"protected": false}
#     .../rules/branches/<b>       rules.list (one rule per line)
#                                  each answers <key>.fail instead (its text on
#                                  stderr, exit 1) when the case has one
# Every call is logged to $FIX/gh.log, one line each.
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
FIX="${GH_FIXTURE:?}"
echo "$*" >> "$FIX/gh.log"
echo "${GH_TOKEN-unset}" >> "$FIX/token.log"
jqf=""
state=open
prev=""
for a in "$@"; do
    [ "$prev" = "--jq" ] && jqf="$a"
    [ "$prev" = "--state" ] && state="$a"
    prev="$a"
done
out() { if [ -n "$jqf" ]; then jq -r "$jqf"; else cat; fi; }
serve() { # serve <key> <jq builder> <list file>...
    local key="$1" f="$2"
    shift 2
    if [ -f "$FIX/$key.fail" ]; then cat "$FIX/$key.fail" >&2; exit 1; fi
    cat "$@" 2>/dev/null | jq -s "$f"
}
case "$1 ${2:-}" in
    "pr checks")
        if [ -f "$FIX/refuse" ]; then echo "$(cat "$FIX/refuse")" >&2; exit 1; fi
        if [ -f "$FIX/checks.err" ]; then cat "$FIX/checks.err" >&2; exit "$(cat "$FIX/checks.rc" 2>/dev/null || echo 1)"; fi
        out < "$FIX/checks.json"
        ;;
    "pr view") out < "$FIX/view.json" ;;
    "pr list")
        jq --arg s "$state" '[.[] | select($s == "all" or ($s == "open" and .state == "OPEN")
            or ($s == "merged" and .state == "MERGED"))]' "$FIX/prs.json" | out
        ;;
    "api user") echo '{"login": "octo"}' | out ;;
    "api --method")
        path="${4%%\?*}"
        case "$path" in
            repos/*/*/actions/runs) serve runs '{total_count: length, workflow_runs: .}' "$FIX/runs.list" ;;
            repos/*/*/actions/runs/*/jobs)
                id="${path%/jobs}"; id="${id##*/}"
                serve "jobs-$id" '{total_count: length, jobs: .}' "$FIX/jobs-$id.list" ;;
            repos/*/*/commits/*/status) serve status '{state: "pending", total_count: length, statuses: .}' "$FIX/statuses.list" ;;
            repos/*/*/rules/branches/*) serve rules '.' "$FIX/rules.list" ;;
            repos/*/*/branches/*)
                if [ -f "$FIX/branch.fail" ]; then cat "$FIX/branch.fail" >&2; exit 1; fi
                if [ -f "$FIX/branch.json" ]; then cat "$FIX/branch.json"; else echo '{"protected": false}'; fi ;;
            *) echo "gh stub: unexpected path: $*" >&2; exit 1 ;;
        esac
        ;;
    "api repos/"*/contents/*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    "api repos/"*) echo '{"default_branch": "main"}' | out ;;
    *) echo "gh stub: unexpected call: $*" >&2; exit 1 ;;
esac
STUB

# koto: `context get|exists <session> <key>` read $FIX/ctx-<key>; `context add`
# stores stdin there.
cat > "$T/bin/koto" <<'STUB'
#!/usr/bin/env bash
FIX="${GH_FIXTURE:?}"
case "$1 ${2:-}" in
    "context get") [ -f "$FIX/ctx-$4" ] || exit 1; cat "$FIX/ctx-$4" ;;
    "context exists") [ -f "$FIX/ctx-$4" ] ;;
    "context add") cat > "$FIX/ctx-$4" ;;
    *) echo "koto stub: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$T/bin/gh" "$T/bin/koto" || exit 1

# A repository on the run's branch, with no macOS floor script.
REPO="$T/repo"
mkdir -p "$REPO" || exit 1
git -C "$REPO" init -q || exit 1
git -C "$REPO" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init || exit 1
git -C "$REPO" checkout -q -b "$BRANCH" || exit 1

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# fixture [host]: pull request #7 on the run's branch, open, owned by this
# run, at head $H, on github.com unless a host is given; nothing refused.
fixture() {
    local host="${1:-github.com}"
    rm -rf "$FIX" && mkdir -p "$FIX" || return 1
    jq -n --arg u "https://$host/$R/pull/7" --arg h "$H" --arg b "$BRANCH" \
        '{number: 7, state: "OPEN", url: $u, headRefOid: $h, headRefName: $b, baseRefName: "main", body: "Fixes #1."}' \
        > "$FIX/view.json"
    jq -n --arg u "https://$host/$R/pull/7" --arg b "$BRANCH" --arg me "$ME" --arg m "$MINE" \
        '[{number: 7, url: $u, state: "OPEN", isCrossRepository: false, author: {login: $me},
           baseRefName: "main", headRefName: $b, body: "Fixes #1.\n\n<!-- shirabe-run: \($m) -->\n"}]' \
        > "$FIX/prs.json"
    printf '%s' "$R" > "$FIX/ctx-repos"
    printf '%s' "$BRANCH" > "$FIX/ctx-settled_branch"
    printf '%s' "$MINE" > "$FIX/ctx-run_id"
    : > "$FIX/gh.log"
}
refuse() { printf '%s\n' "$REFUSAL" > "$FIX/refuse"; }

# run_ <id> <workflow> <status> <conclusion|null> [head] [created_at] [event]
# Runs of one workflow name share a workflow_id, as one workflow file's do.
run_() {
    jq -nc --argjson id "$1" --arg n "$2" --arg s "$3" --arg c "$4" --arg h "${5:-$H}" \
        --arg at "${6:-2026-10-21T07:00:00Z}" --arg e "${7:-pull_request}" --arg r "$R" \
        '{id: $id, name: $n, workflow_id: ($n | explode | add), event: $e, head_sha: $h, status: $s,
          conclusion: (if $c == "null" then null else $c end), run_attempt: 1, created_at: $at,
          run_started_at: $at, html_url: "https://github.com/\($r)/actions/runs/\($id)"}' >> "$FIX/runs.list"
}
# job_ <run> <id> <name> <status> <conclusion|null> [started_at]
job_() {
    jq -nc --argjson run "$1" --argjson id "$2" --arg n "$3" --arg s "$4" --arg c "$5" \
        --arg at "${6:-2026-10-21T07:01:00Z}" --arg r "$R" \
        '{id: $id, run_id: $run, name: $n, status: $s, conclusion: (if $c == "null" then null else $c end),
          started_at: (if $at == "null" then null else $at end), completed_at: null, run_attempt: 1,
          steps: (if $s == "completed" and $c != "skipped" then [{name: "step", conclusion: $c}] else [] end),
          html_url: "https://github.com/\($r)/actions/runs/\($run)/job/\($id)"}' >> "$FIX/jobs-$1.list"
}
# status_ <context> <state>
status_() {
    jq -nc --arg c "$1" --arg s "$2" \
        '{context: $c, state: $s, target_url: "https://ci.example.com/\($c)", description: "", created_at: "2026-10-21T07:02:00Z"}' \
        >> "$FIX/statuses.list"
}
# protect <name> [app_id]: a classic required check.
protect() {
    [ -f "$FIX/branch.json" ] || echo '{"protected": true, "protection": {"enabled": true, "required_status_checks": {"enforcement_level": "non_admins", "contexts": [], "checks": []}}}' > "$FIX/branch.json"
    jq --arg n "$1" --arg a "${2:-}" '.protection.required_status_checks.checks += [{context: $n, app_id: (if $a == "" then null else ($a | tonumber) end)}]' \
        "$FIX/branch.json" > "$FIX/branch.new" && mv "$FIX/branch.new" "$FIX/branch.json"
}
# rule_check <name> [integration_id]: a ruleset's required check.
rule_check() {
    jq -nc --arg n "$1" --arg a "${2:-}" '{type: "required_status_checks", ruleset_source_type: "Organization",
        parameters: {required_status_checks: [{context: $n, integration_id: (if $a == "" then null else ($a | tonumber) end)}]}}' >> "$FIX/rules.list"
}
rule_type() { jq -nc --arg t "$1" '{type: $t, ruleset_source_type: "Repository", parameters: {}}' >> "$FIX/rules.list"; }

# green: one workflow with two passing jobs and a passing status, `test`
# required by protection.
green() {
    run_ 100 CI completed success
    job_ 100 1001 test completed success
    job_ 100 1002 lint completed success
    status_ "ci/legacy" success
    protect test
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

# pc [args...]: the script in the repository, with the stubs on PATH. Sets GOT,
# OUT and ERR.
pc() {
    (cd "$REPO" && env PATH="$T/bin:$PATH" GH_FIXTURE="$FIX" "$SCRIPT" "$@") >"$T/out" 2>"$T/err"
    GOT=$?
    OUT=$(cat "$T/out")
    ERR=$(cat "$T/err")
}
expect_exit() {
    if [ "$GOT" = "$2" ]; then pass "$1 (exit $GOT)"
    else fail "$1: expected exit $2, got $GOT; stdout: $OUT; stderr: $ERR"; fi
}
expect_out() {
    if [ "$OUT" = "$2" ]; then pass "$1"
    else fail "$1: expected [$2], got [$OUT]; stderr: $ERR"; fi
}
expect_stderr() {
    case "$ERR" in *"$2"*) pass "$1" ;; *) fail "$1: stderr lacks [$2]: $ERR" ;; esac
}
# expect_list <label> <jq filter that must be true of the printed list>
expect_list() {
    if printf '%s' "$OUT" | jq -e "$2" >/dev/null 2>&1; then pass "$1"
    else fail "$1: [$2] is not true of $OUT; stderr: $ERR"; fi
}
calls() { grep -c -- "$1" "$FIX/gh.log"; }

# The gate filter work-on.md and execute.md apply, read from the template so
# it can't drift: green is true.
GATE_JQ=$(koto_unquote_scalar "$(koto_gate_command "$WORK_ON" ci_passing)" | grep -oE "\-\-jq '[^']*'" | tail -1 | sed "s/^--jq '//; s/'$//")
[ -n "$GATE_JQ" ] || { echo "pr-checks_test: could not read ci_passing's filter" >&2; exit 1; }
green_by_gate() { printf '%s' "$OUT" | jq -r "$GATE_JQ" 2>/dev/null; }

# ---------------------------------------------------------------------------
# Allowed: gh pr checks answers
# ---------------------------------------------------------------------------

fixture
echo '[{"bucket":"pass","name":"test"},{"bucket":"fail","name":"lint"}]' > "$FIX/checks.json"
pc 7 --json bucket,name --jq '.[] | .name'
expect_exit "allowed: gh's answer passes through" 0
expect_out "allowed: stdout is gh's, --jq applied by gh" "$(printf 'test\nlint')"
if [ "$(calls 'api ')" = 0 ] && [ "$(calls 'pr view')" = 0 ]; then pass "allowed: nothing but the check read"
else fail "allowed: other reads were made: $(cat "$FIX/gh.log")"; fi
if [ "$(head -n 1 "$FIX/gh.log")" = "pr checks 7 --json bucket,name --jq .[] | .name" ]; then pass "allowed: gh pr checks gets the arguments as given"
else fail "allowed: gh pr checks was called as [$(head -n 1 "$FIX/gh.log")]"; fi

fixture
echo "no checks reported on the '$BRANCH' branch" > "$FIX/checks.err"
pc 7 --json bucket
expect_exit "allowed: gh's failure exit passes through" 1
expect_out "allowed: no stdout on gh's failure" ""
if [ "$ERR" = "no checks reported on the '$BRANCH' branch" ]; then pass "allowed: gh's stderr passes through unchanged"
else fail "allowed: stderr was [$ERR]"; fi

fixture
echo "some pending" > "$FIX/checks.err"
echo 8 > "$FIX/checks.rc"
pc 7
expect_exit "allowed: gh's pending exit 8 passes through" 8

fixture
echo '[{"bucket":"pass","name":"test"}]' > "$FIX/checks.json"
pc 7 --required --json bucket
expect_exit "allowed: a flag the fallback can't serve still reaches gh" 0
if [ "$(head -n 1 "$FIX/gh.log")" = "pr checks 7 --required --json bucket" ]; then pass "allowed: gh gets the flag as given"
else fail "allowed: gh was called as [$(head -n 1 "$FIX/gh.log")]"; fi

fixture
echo "gh: API rate limit exceeded for user (HTTP 403)" > "$FIX/checks.err"
green
pc 7 --json bucket
expect_exit "allowed: a 403 that isn't a refusal of the check read passes through" 1
if [ "$(calls 'api ')" = 0 ]; then pass "allowed: a rate-limit 403 reads nothing more"
else fail "allowed: a rate-limit 403 fell back: $(cat "$FIX/gh.log")"; fi

fixture; refuse; green
pc 7 --required --json bucket
expect_exit "refused: a flag the fallback can't serve is a usage error there" 2
expect_stderr "refused: and names the flag" "--required"

fixture
echo "gh: Not Found (HTTP 404)" > "$FIX/checks.err"
green
pc 7 --json bucket
expect_exit "allowed: a failure that isn't a refusal is not a fallback" 1
if [ "$(calls 'api ')" = 0 ]; then pass "allowed: a 404 reads nothing more"
else fail "allowed: a 404 fell back: $(cat "$FIX/gh.log")"; fi

# ---------------------------------------------------------------------------
# Refused: the fallback
# ---------------------------------------------------------------------------

fixture; refuse; green
pc 7 --json name,bucket,workflow,link
expect_exit "refused: green reads" 0
expect_stderr "refused: the fallback says so on stderr" "the check read was refused"
expect_list "refused: two jobs, their run and a status, all pass" \
    'length == 4 and all(.[]; .bucket == "pass") and ([.[].name] | sort) == ["CI", "ci/legacy", "lint", "test"]'
expect_list "refused: a job carries its workflow and its link" \
    'any(.[]; .name == "test" and .workflow == "CI" and .link == "https://github.com/acme/widgets/actions/runs/100/job/1001")'
eq_green=$(green_by_gate)
[ "$eq_green" = true ] && pass "refused: the gate filter reads it green" || fail "refused: the gate filter read [$eq_green]"
if grep -q -- '--hostname github.com' "$FIX/gh.log" && ! grep 'api ' "$FIX/gh.log" | grep -qv -- '--method GET'; then
    pass "refused: every fallback read is a GET on the pull request's host"
else fail "refused: reads were $(cat "$FIX/gh.log")"; fi
if grep -q 'filter=all' "$FIX/gh.log"; then fail "refused: jobs read every attempt"; else pass "refused: jobs are the latest attempt's (no filter=all)"; fi
if grep -q "actions/runs?head_sha=$H" "$FIX/gh.log"; then pass "refused: runs are read by the head sha"
else fail "refused: runs not read by head sha: $(cat "$FIX/gh.log")"; fi

fixture; refuse; green
pc 7
expect_exit "refused: without --json, a line per check" 0
case "$OUT" in *"test	pass	CI	"*) pass "refused: the text form names the check, bucket and workflow" ;; *) fail "refused: text form was [$OUT]" ;; esac

fixture; refuse; green
pc 7 --json bucket --jq 'length'
expect_out "refused: --jq applies to the list" 4

fixture; refuse; green
pc 7 --json bucket,conclusion
expect_exit "refused: a field the fallback can't give is refused" 1
expect_stderr "refused: names the field" "conclusion"

# Fail, pending, cancel, skipped.
fixture; refuse; green
job_ 100 1003 build completed failure
pc 7 --json name,bucket
expect_list "refused: a failed job is fail" 'any(.[]; .name == "build" and .bucket == "fail")'
[ "$(green_by_gate)" = false ] && pass "refused: a failed job is not green" || fail "refused: a failed job read green: $OUT"

fixture; refuse; green
job_ 100 1003 build in_progress null
pc 7 --json name,bucket
expect_list "refused: a running job is pending" 'any(.[]; .name == "build" and .bucket == "pending")'
[ "$(green_by_gate)" = false ] && pass "refused: a running job is not green" || fail "refused: a running job read green"

fixture; refuse; green
run_ 200 Lint queued null
pc 7 --json name,bucket
expect_list "refused: a queued run with no job yet is listed pending" 'any(.[]; .name == "Lint" and .bucket == "pending")'
[ "$(green_by_gate)" = false ] && pass "refused: a queued run is not green" || fail "refused: a queued run read green"

fixture; refuse; green
job_ 100 1003 build completed cancelled
job_ 100 1004 optional completed skipped
job_ 100 1005 neutral completed neutral
pc 7 --json name,bucket
expect_list "refused: cancelled is cancel, skipped and neutral are skipping" \
    'any(.[]; .name == "build" and .bucket == "cancel") and any(.[]; .name == "optional" and .bucket == "skipping") and any(.[]; .name == "neutral" and .bucket == "skipping")'

fixture; refuse; green
status_ "ci/other" pending
pc 7 --json name,bucket
expect_list "refused: a pending status is pending" 'any(.[]; .name == "ci/other" and .bucket == "pending")'

fixture; refuse; green
status_ "ci/other" failure
status_ "ci/err" error
pc 7 --json name,bucket
expect_list "refused: failure and error statuses are fail" 'any(.[]; .name == "ci/other" and .bucket == "fail") and any(.[]; .name == "ci/err" and .bucket == "fail")'

# Required checks the fallback can't see.
fixture; refuse; green
protect codecov
pc 7 --json name,bucket
expect_exit "refused: an unseen required check still lists" 0
expect_list "refused: a required check no job or status answers is unreadable" 'any(.[]; .name == "codecov" and .bucket == "unreadable")'
[ "$(green_by_gate)" = false ] && pass "refused: an unreadable required check is never green" || fail "refused: an unreadable required check read green: $OUT"

fixture; refuse; green
rule_check codecov
pc 7 --json name,bucket
expect_list "refused: an organisation ruleset's unseen required check is unreadable" 'any(.[]; .name == "codecov" and .bucket == "unreadable")'

fixture; refuse; green
protect test 9999
pc 7 --json name,bucket
expect_list "refused: a required check pinned to another app is unreadable, even with a job of its name" \
    'any(.[]; .name == "test" and .bucket == "unreadable")'
[ "$(green_by_gate)" = false ] && pass "refused: a pinned check is never green" || fail "refused: a pinned check read green"

fixture; refuse; green
protect test 15368
pc 7 --json name,bucket
expect_list "refused: a check pinned to GitHub Actions is answered by its job" 'all(.[]; .bucket == "pass")'

fixture; refuse; green
protect "ci/legacy"
pc 7 --json name,bucket
expect_list "refused: a required status with no job is answered by the status" 'all(.[]; .bucket == "pass")'

fixture; refuse; green
protect "ci/legacy" 15368
pc 7 --json name,bucket
expect_list "refused: a status can't answer a check pinned to an app" 'any(.[]; .name == "ci/legacy" and .bucket == "unreadable")'

fixture; refuse; green
rule_type workflows
rule_type code_scanning
pc 7 --json name,bucket
expect_list "refused: a workflows or code_scanning rule is unreadable" \
    '([.[] | select(.bucket == "unreadable") | .name] | sort) == ["the ruleset rule code_scanning", "the ruleset rule workflows"]'

fixture; refuse
run_ 200 Lint queued null
protect lint
pc 7 --json name,bucket,state
expect_list "refused: a required check whose run hasn't started is pending (EXPECTED) beside the pending run" \
    'any(.[]; .name == "Lint" and .bucket == "pending") and any(.[]; .name == "lint" and .bucket == "pending" and .state == "EXPECTED")'

fixture; refuse
run_ 200 Lint queued null
protect lint 9999
pc 7 --json name,bucket
expect_list "refused: a check pinned to another app is unreadable at once, even while a run goes" \
    'any(.[]; .name == "lint" and .bucket == "unreadable")'

# The token: the session's, unchanged, on every call.
fixture; refuse; green
(cd "$REPO" && env PATH="$T/bin:$PATH" GH_FIXTURE="$FIX" GH_TOKEN=test-session-token "$SCRIPT" 7 --json bucket) >/dev/null 2>&1
if [ "$(sort -u "$FIX/token.log")" = test-session-token ] && [ "$(grep -c . "$FIX/token.log")" -gt 5 ]; then
    pass "refused: every call, the fallback's included, runs on the caller's GH_TOKEN unchanged"
else fail "refused: the token seen by gh calls was [$(sort -u "$FIX/token.log" | tr '\n' ' ')]"; fi
if grep -q -E 'GH_TOKEN|GH_CONFIG_DIR|gh auth' "$SCRIPT"; then fail "pr-checks.sh names the token, a config dir or gh auth"
else pass "pr-checks.sh never names the token, a config dir or gh auth"; fi

# Adversarial shapes.
fixture; refuse; green
run_ 300 CI completed failure "$OTHER_SHA"
job_ 300 3001 test completed failure
pc 7 --json name,bucket
expect_list "refused: a run for another head is never read" 'all(.[]; .bucket == "pass") and length == 4'
if grep -q 'runs/300/jobs' "$FIX/gh.log"; then fail "refused: another head's jobs were read"; else pass "refused: another head's jobs aren't read"; fi

fixture; refuse
run_ 100 CI completed failure "$H" "2026-10-21T07:00:00Z"
job_ 100 1001 test completed failure "2026-10-21T07:01:00Z"
run_ 101 CI completed success "$H" "2026-10-21T08:00:00Z"
job_ 101 1011 test completed success "2026-10-21T08:01:00Z"
pc 7 --json name,bucket
expect_list "refused: a later run of a workflow on the same event answers for the earlier one" \
    'length == 2 and all(.[]; .bucket == "pass") and ([.[].name] | sort) == ["CI", "test"]'

fixture; refuse
run_ 100 CI completed success "$H" "2026-10-21T07:00:00Z"
job_ 100 1001 test completed success "2026-10-21T07:01:00Z"
run_ 101 CI completed failure "$H" "2026-10-21T08:00:00Z"
job_ 101 1011 test completed failure "2026-10-21T08:01:00Z"
pc 7 --json name,bucket
expect_list "refused: an earlier green never hides a later red" 'length == 2 and all(.[]; .bucket == "fail")'

fixture; refuse
run_ 100 CI completed failure "$H" "2026-10-21T07:00:00Z" pull_request
job_ 100 1001 test completed failure "2026-10-21T07:01:00Z"
run_ 101 CI completed success "$H" "2026-10-21T08:00:00Z" workflow_dispatch
job_ 101 1011 test completed success "2026-10-21T08:01:00Z"
pc 7 --json name,bucket
expect_list "refused: a later run on another event doesn't hide a red run" \
    'any(.[]; .name == "test" and .bucket == "fail") and any(.[]; .name == "CI" and .bucket == "fail")'
[ "$(green_by_gate)" = false ] && pass "refused: a red run on another event is not green" || fail "refused: a red run on another event read green"

# The run's own state, whatever its listed jobs say.
fixture; refuse
run_ 100 CI in_progress null
job_ 100 1001 test completed success
pc 7 --json name,bucket
expect_list "refused: a run still going with only green jobs listed so far is pending" \
    'any(.[]; .name == "CI" and .bucket == "pending")'
[ "$(green_by_gate)" = false ] && pass "refused: a run still going is not green, whatever its listed jobs" || fail "refused: a running run with green jobs read green"

for c in cancelled failure; do
    fixture; refuse
    run_ 100 CI completed "$c"
    job_ 100 1001 test completed success
    pc 7 --json name,bucket
    [ "$(green_by_gate)" = false ] && pass "refused: a $c run with every listed job green is not green" \
        || fail "refused: a $c run with green jobs read green: $OUT"
done

fixture; refuse
run_ 100 CI completed success "$H" "2026-10-21T07:00:00Z"
job_ 100 1001 test completed success "2026-10-21T07:01:00Z"
run_ 101 CI queued null "$H" "2026-10-21T08:00:00Z"
job_ 101 1011 test queued null null
pc 7 --json name,bucket
expect_list "refused: a newer run still queued wins over an older green one" \
    'any(.[]; .name == "test" and .bucket == "pending") and any(.[]; .name == "CI" and .bucket == "pending")'

# Supersession only by a later job that ran, as coordinate's board reads it.
for c in skipped neutral; do
    fixture; refuse
    run_ 100 CI completed failure "$H" "2026-10-21T07:00:00Z"
    job_ 100 1001 build completed failure "2026-10-21T07:01:00Z"
    run_ 101 CI completed success "$H" "2026-10-21T08:00:00Z"
    job_ 101 1011 build completed "$c" "2026-10-21T08:01:00Z"
    pc 7 --json name,bucket
    expect_list "refused: a later $c job doesn't supersede an earlier red one of its name" \
        'any(.[]; .name == "build" and .bucket == "fail")'
    [ "$(green_by_gate)" = false ] && pass "refused: an earlier red job behind a later $c one is not green" \
        || fail "refused: a later $c job hid an earlier red one: $OUT"
done

fixture; refuse
run_ 100 CI completed failure "$H" "2026-10-21T07:00:00Z"
job_ 100 1001 test completed success "2026-10-21T07:01:00Z"
run_ 101 CI completed skipped "$H" "2026-10-21T08:00:00Z"
pc 7 --json name,bucket
expect_list "refused: a later skipped run supersedes nothing, so a run that failed stays red" \
    'any(.[]; .name == "CI" and .bucket == "fail")'
[ "$(green_by_gate)" = false ] && pass "refused: a failed run behind a later skipped one is not green" \
    || fail "refused: a later skipped run hid a failed one: $OUT"

for s in queued in_progress; do
    fixture; refuse
    run_ 100 CI "$s" null "$H" "2026-10-21T07:00:00Z"
    run_ 101 CI completed success "$H" "2026-10-21T08:00:00Z"
    job_ 101 1011 test completed success "2026-10-21T08:01:00Z"
    pc 7 --json name,bucket
    expect_list "refused: an earlier run still $s is never superseded by a later green one" \
        'any(.[]; .name == "CI" and .bucket == "pending")'
    [ "$(green_by_gate)" = false ] && pass "refused: an earlier run still $s keeps the list from green" \
        || fail "refused: a later green run hid an earlier $s one: $OUT"
done

fixture; refuse
run_ 100 CI completed failure "$H" "2026-10-21T07:00:00Z"
job_ 100 1001 test completed failure "2026-10-21T07:01:00Z"
job_ 100 1002 lint completed failure "2026-10-21T07:01:00Z"
run_ 101 CI completed success "$H" "2026-10-21T08:00:00Z"
job_ 101 1011 test completed success "2026-10-21T08:01:00Z"
pc 7 --json name,bucket
expect_list "refused: a run keeps its entry while one of its jobs isn't superseded" \
    'any(.[]; .name == "lint" and .bucket == "fail") and ([.[] | select(.name == "CI" and .bucket == "fail")] | length) == 1'

for c in neutral cancelled; do
    fixture; refuse
    run_ 10 W completed failure "$H" "2026-10-21T07:00:00Z"
    run_ 11 W completed "$c" "$H" "2026-10-21T08:00:00Z"
    pc 7 --json name,bucket
    expect_list "refused: a failed run with no jobs isn't superseded by a later $c run" \
        'any(.[]; .name == "W" and .bucket == "fail")'
    [ "$(green_by_gate)" = false ] && pass "refused: a failed run with no jobs behind a later $c one is not green" \
        || fail "refused: a later $c run hid a failed run with no jobs: $OUT"
done

fixture; refuse
run_ 10 W completed failure "$H" "2026-10-21T07:00:00Z"
run_ 11 W completed success "$H" "2026-10-21T08:00:00Z"
job_ 11 1101 build completed success "2026-10-21T08:01:00Z"
pc 7 --json name,bucket
expect_list "refused: a later run that finished success answers for a failed run with no jobs" \
    'all(.[]; .bucket == "pass")'

fixture; refuse; green
jq -c 'del(.workflow_id)' "$FIX/runs.list" > "$FIX/runs.new" && mv "$FIX/runs.new" "$FIX/runs.list"
pc 7 --json bucket
expect_exit "refused: a run without a workflow id can't be keyed, so the read fails" 1

fixture; refuse
run_ 100 CI completed failure "$H" "2026-10-21T07:00:00Z"
job_ 100 1001 test completed failure "2026-10-21T07:01:00Z"
run_ 101 CI completed success "$H" "2026-10-21T08:00:00Z"
job_ 101 1011 tests completed success "2026-10-21T08:01:00Z"
pc 7 --json name,bucket
expect_list "refused: a renamed job doesn't hide the red job of the old name" \
    'any(.[]; .name == "test" and .bucket == "fail") and any(.[]; .name == "tests" and .bucket == "pass")'
[ "$(green_by_gate)" = false ] && pass "refused: a rename is not green" || fail "refused: a rename read green"

fixture; refuse
run_ 100 Other completed failure "$H" "2026-10-21T07:00:00Z"
job_ 100 1001 test completed failure "2026-10-21T07:01:00Z"
run_ 101 CI completed success "$H" "2026-10-21T08:00:00Z"
job_ 101 1011 test completed success "2026-10-21T08:01:00Z"
pc 7 --json name,bucket
expect_list "refused: a job of the same name in another workflow doesn't hide a red one" \
    '([.[] | select(.name == "test")] | length) == 2 and any(.[]; .name == "test" and .bucket == "fail")'

# No checks, and reads that fail.
fixture; refuse
pc 7 --json bucket
expect_exit "refused: nothing at the head is gh's no-checks answer" 1
expect_stderr "refused: no checks reported, as gh words it" "no checks reported on the '$BRANCH' branch"
expect_out "refused: no checks prints nothing" ""

for key in runs jobs-100 status branch rules; do
    fixture; refuse; green
    echo "gh: Server Error (HTTP 500)" > "$FIX/$key.fail"
    pc 7 --json bucket
    expect_exit "refused: a failed $key read fails the read" 1
    expect_out "refused: a failed $key read prints no list" ""
done

fixture; refuse; green
echo "gh: Resource not accessible by personal access token (HTTP 403)" > "$FIX/status.fail"
pc 7 --json bucket
expect_exit "refused: a refused status read fails the read, never drops the statuses" 1

fixture; refuse; green
echo "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)" > "$FIX/rules.fail"
pc 7 --json name,bucket
expect_exit "refused: a plan without rulesets reads as no rules" 0
expect_list "refused: with no rules, protection alone is the required set" 'all(.[]; .bucket == "pass")'

fixture; refuse; green
echo '{"protected": true}' > "$FIX/branch.json"
pc 7 --json bucket
expect_exit "refused: protection that can't be read fails the read" 1

fixture ghe.example.com; refuse; green
pc 7 --json bucket
expect_exit "refused: an enterprise pull request reads" 0
if grep 'api --method' "$FIX/gh.log" | grep -qv -- '--hostname ghe.example.com'; then
    fail "refused: a read went to another host: $(cat "$FIX/gh.log")"
else pass "refused: every read goes to the pull request's host"; fi

# ---------------------------------------------------------------------------
# Wiring: the gates as the templates ship them, under a refused check read
# ---------------------------------------------------------------------------

gate_command() {
    local raw
    raw=$(koto_gate_command "$1" "$2") || return 1
    [ -n "$raw" ] || return 1
    koto_unquote_scalar "$raw"
}
run_gate() {
    local cmd="$1"
    cmd="${cmd//\{\{PLUGIN_ROOT\}\}/$REPO_ROOT}"
    cmd="${cmd//\{\{SESSION_NAME\}\}/sess}"
    cmd="${cmd//\{\{PLAN_SLUG\}\}/x}"
    (cd "$REPO" && env PATH="$T/bin:$PATH" GH_FIXTURE="$FIX" sh -c "$cmd") >/dev/null 2>"$T/err"
    GOT=$?
    ERR=$(cat "$T/err")
}

for entry in "$WORK_ON:ci_passing" "$EXECUTE:owned_ci_passing"; do
    template="${entry%:*}"
    gate="${entry##*:}"
    CMD=$(gate_command "$template" "$gate")
    [ -n "$CMD" ] || { fail "could not read $gate from $template"; continue; }
    case "$CMD" in
        *'/skills/work-on/scripts/pr-checks.sh" '*) pass "$gate reads the checks through pr-checks.sh" ;;
        *) fail "$gate does not read through pr-checks.sh: $CMD" ;;
    esac
    case "$CMD" in
        *'gh pr checks'*) fail "$gate still calls gh pr checks directly" ;;
        *) pass "$gate makes no direct gh pr checks call" ;;
    esac

    fixture; refuse; green
    run_gate "$CMD"
    expect_exit "$gate: refused, every job and status green: green" 0

    fixture; refuse; green
    job_ 100 1003 build completed failure
    run_gate "$CMD"
    expect_exit "$gate: refused, a failed job: not green" 1

    fixture; refuse; green
    job_ 100 1003 build in_progress null
    run_gate "$CMD"
    expect_exit "$gate: refused, a running job: not green" 1

    fixture; refuse; green
    status_ "ci/other" failure
    run_gate "$CMD"
    expect_exit "$gate: refused, a failed status-API check with no job: not green" 1

    fixture; refuse; green
    protect codecov
    run_gate "$CMD"
    expect_exit "$gate: refused, a required check only a check run could answer: not green" 1

    fixture; refuse
    run_gate "$CMD"
    expect_exit "$gate: refused, no checks at all: not green" 1

    fixture
    echo '[{"bucket":"pass"},{"bucket":"skipping"}]' > "$FIX/checks.json"
    run_gate "$CMD"
    expect_exit "$gate: allowed, green as before" 0
    fixture
    echo '[{"bucket":"pass"},{"bucket":"pending"}]' > "$FIX/checks.json"
    run_gate "$CMD"
    expect_exit "$gate: allowed, pending as before" 1
done

# The coordinated loop reads checks by the same rule (#752): coord-common.sh's
# draft-node read and execute-coordinated.md's evaluate actions name
# pr-checks.sh and make no direct `pr checks` call, through gh or through
# coord_gh_read. Comment lines in the script don't count.
for f in "$REPO_ROOT/skills/execute/scripts/coord-common.sh" \
         "$REPO_ROOT/skills/execute/koto-templates/execute-coordinated.md"; do
    name="${f#"$REPO_ROOT"/}"
    case "$f" in
        *.sh) direct=$(grep -nE '(^|[^-])pr checks' "$f" | grep -vE '^[0-9]+:[[:space:]]*#') ;;
        *) direct=$(grep -nE '(^|[^-])pr checks' "$f") ;;
    esac
    if [ -n "$direct" ]; then
        fail "$name still reads checks directly: $(printf '%s' "$direct" | head -n 1)"
    else
        pass "$name makes no direct pr checks call"
    fi
    if grep -q 'work-on/scripts/pr-checks\.sh' "$f"; then
        pass "$name reads checks through pr-checks.sh"
    else
        fail "$name does not name pr-checks.sh"
    fi
done

echo
echo "pr-checks_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" = 0 ]
