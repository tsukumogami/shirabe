#!/usr/bin/env bash
# ci-none-declared_test.sh -- do ci_passing and owned_ci_passing read a pull
# request with no checks as not green, and pass one only when its repository
# states, on its default branch, that it has no hosted CI (#1018)?
#
# Two parts:
#
#   script   ci-none-declared.sh, with and without --owned (against the real
#            owned-pr.sh), in a throwaway git repository, and without --owned
#            in a fork clone whose first remote isn't the PR's repository,
#            with the gh calls each path costs
#   wiring   work-on.md's ci_passing and execute.md's owned_ci_passing
#            EXTRACTED FROM THE TEMPLATES, with {{PLUGIN_ROOT}},
#            {{SESSION_NAME}} and {{PLAN_SLUG}} substituted as koto would, so
#            what ships is what runs: zero checks, the post-push window, the
#            green cases that must stay green, and the declared exception
#
# gh and koto are stubs on PATH, so no case reaches GitHub or a real session.
# The gh stub applies `--jq` with jq, as gh does, so the gates' own filters
# decide. What it stands in for was read from gh's source (cli/cli
# pkg/cmd/pr/checks/checks.go, the same at v2.76.2 and v2.103.0): a pull
# request whose head has no check contexts gets no JSON at all, only
# `no checks reported on the '<branch>' branch` on stderr and exit 1. That is
# also the window just after a push, before Actions creates the check suites.
# A `checks-<n>.err` fixture serves exactly that; an empty `[]` fixture covers a
# gh that would print an empty list instead.
#
# Usage: ci-none-declared_test.sh
# Exit codes: 0 all pass, 1 any failed.
#
# Bash 3.2: no associative arrays, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
WORK_ON="$REPO_ROOT/skills/work-on/koto-templates/work-on.md"
EXECUTE="$REPO_ROOT/skills/execute/koto-templates/execute.md"
SCRIPT="$SCRIPT_DIR/ci-none-declared.sh"

# shellcheck source=../../../scripts/lib/koto-gates.sh
. "$REPO_ROOT/scripts/lib/koto-gates.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

command -v jq >/dev/null || { echo "ci-none-declared_test: jq is required" >&2; exit 1; }
command -v git >/dev/null || { echo "ci-none-declared_test: git is required" >&2; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/ci-none-declared-test.XXXXXX") || exit 1
# The trailing `return 0` keeps the trap's status from replacing the script's.
cleanup() { rm -rf "$T"; return 0; }
trap cleanup EXIT

R=acme/widgets
REPO_URL="https://github.com/$R"
RUN="$REPO_URL/actions/runs"
ME=octo
MINE=0123456789abcdef0123456789abcdef
OTHER=fedcba9876543210fedcba9876543210
BRANCH=impl/x
HEAD_SHA=1111111111111111111111111111111111111111
FIX="$T/fixture"
DECL_PATH=.claude/shirabe-extensions/hosted-ci.json
REASON="Documents only: nothing in this repository builds or tests."
RECORD="## Hosted CI

This repository declares no hosted CI.
Reason: $REASON"

# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

mkdir -p "$T/bin" || exit 1

# gh:
#   api user                           {"login": $ME}
#   api repos/<r>/contents/<path>      $FIX/decl when <r> is the repository
#                                      named in $FIX/decl-repo and the call
#                                      goes to the host in $FIX/decl-host
#                                      (github.com without it), else a 404.
#                                      The host is the call's --hostname, or
#                                      gh's default, github.com, when it has
#                                      none. {owner}/{repo} is filled from the
#                                      first git remote, as gh api does,
#                                      ignoring `gh repo set-default`. The
#                                      path as asked is logged to
#                                      $FIX/contents.log
#   api repos/<r>                      its default branch, main
#   pr list --state <s>                $FIX/prs.json, filtered by state as gh
#                                      does (open by default)
#   pr checks [<sel>] / pr view [<sel>]
#                                      $FIX/checks-<n>.json / view-<n>.json for
#                                      the PR a number or URL names, or with no
#                                      selector the current branch's
#                                      ($FIX/current). A checks-<n>.err is gh's
#                                      answer for no checks: its text on
#                                      stderr, exit 1, no JSON.
# --jq is applied with jq. Every call is logged to $FIX/gh.log.
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
FIX="${GH_FIXTURE:?}"
echo "$*" >> "$FIX/gh.log"
jqf=""
state=open
host=github.com
prev=""
for a in "$@"; do
    [ "$prev" = "--jq" ] && jqf="$a"
    [ "$prev" = "--state" ] && state="$a"
    [ "$prev" = "--hostname" ] && host="$a"
    prev="$a"
done
out() {
    if [ -n "$jqf" ]; then jq -r "$jqf"; else cat; fi
}
pr_number() {
    case "${1:-}" in
        ''|-*)
            [ -f "$FIX/current" ] || { echo "no pull requests found for branch" >&2; return 1; }
            cat "$FIX/current"
            ;;
        *) echo "${1##*/}" ;;
    esac
}
case "$1 ${2:-}" in
    "api user") echo '{"login": "octo"}' | out ;;
    "api repos/"*/contents/*)
        echo "$2" >> "$FIX/contents.log"
        path="$2"
        placeholders='repos/{owner}/{repo}/'
        case "$path" in
            "$placeholders"*)
                remote=$(git remote | head -n 1)
                url=$(git remote get-url "$remote" 2>/dev/null) \
                    || { echo "gh: unable to determine base repository" >&2; exit 1; }
                url="${url%.git}"
                path="repos/${url#*://*/}/${path#"$placeholders"}"
                ;;
        esac
        served=github.com
        [ -f "$FIX/decl-host" ] && served=$(cat "$FIX/decl-host")
        [ "$host" = "$served" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
        case "$path" in
            "repos/$(cat "$FIX/decl-repo" 2>/dev/null)/contents/"*) cat "$FIX/decl" ;;
            *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
        esac
        ;;
    "api repos/"*) echo '{"default_branch": "main"}' | out ;;
    "pr list")
        jq --arg s "$state" '[.[] | select($s == "all"
            or ($s == "open" and .state == "OPEN")
            or ($s == "merged" and .state == "MERGED")
            or ($s == "closed" and .state == "CLOSED"))]' "$FIX/prs.json" | out
        ;;
    "pr checks")
        n=$(pr_number "${3:-}") || exit 1
        if [ -f "$FIX/checks-$n.err" ]; then cat "$FIX/checks-$n.err" >&2; exit 1; fi
        [ -f "$FIX/checks-$n.json" ] || { echo "gh stub: no checks fixture for #$n" >&2; exit 1; }
        out < "$FIX/checks-$n.json"
        ;;
    "pr view")
        n=$(pr_number "${3:-}") || exit 1
        [ -f "$FIX/view-$n.json" ] || { echo "gh stub: no view fixture for #$n" >&2; exit 1; }
        out < "$FIX/view-$n.json"
        ;;
    *) echo "gh stub: unexpected call: $*" >&2; exit 1 ;;
esac
STUB

# koto: `context get|exists <session> <key>` read $FIX/ctx-<key>, and
# `context add <session> <key>` stores stdin there, or fails under
# KOTO_FAIL=1. Every write is logged to $FIX/added as `<session> <key>`.
cat > "$T/bin/koto" <<'STUB'
#!/usr/bin/env bash
FIX="${GH_FIXTURE:?}"
echo "$*" >> "$FIX/koto.log"
case "$1 ${2:-}" in
    # A PR's index session (pr.<owner>.<repo>.<n>): its run/<id> entries are
    # the files of $FIX/idx-<session>, the read owned-pr.sh decides by.
    "context list")
        (cd "$FIX/idx-$3" 2>/dev/null && ls) | sed 's#^#run/#' | jq -Rsc 'split("\n") | map(select(length > 0 and . != "run/"))' ;;
    "context get")
        case "$4" in
            run/*) [ -f "$FIX/idx-$3/${4#run/}" ] || exit 1; cat "$FIX/idx-$3/${4#run/}" ;;
            *) [ -f "$FIX/ctx-$4" ] || exit 1; cat "$FIX/ctx-$4" ;;
        esac ;;
    "context exists") [ -f "$FIX/ctx-$4" ] ;;
    "context add")
        [ "${KOTO_FAIL:-0}" = 1 ] && { echo "koto: context write failed" >&2; exit 1; }
        cat > "$FIX/ctx-$4"
        echo "$3 $4" >> "$FIX/added"
        ;;
    *) echo "koto stub: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$T/bin/gh" "$T/bin/koto" || exit 1
# The PRs' index sessions sit at a shared address of this suite's own.
export SHIRABE_RUN_RECORD_TEST_ROOT="$T/shared-record"

# A repository on the run's branch. It has no macOS floor script, so
# ci-cancel-after-merge.sh, the fallback before this one, exits 1 quietly.
REPO="$T/repo"
mkdir -p "$REPO" || exit 1
git -C "$REPO" init -q || exit 1
git -C "$REPO" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init || exit 1
git -C "$REPO" checkout -q -b "$BRANCH" || exit 1

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# check <bucket> <name>: one `gh pr checks` entry.
check() {
    jq -cn --arg b "$1" --arg n "$2" --arg l "$RUN/100/job/1" \
        '{bucket: $b, name: $n, workflow: "Check things", link: $l}'
}
PASS_CHECK=$(check pass "test (ubuntu-latest)")
SKIP_CHECK=$(check skipping "optional")
FAIL_CHECK=$(check fail "test (ubuntu-latest)")
PENDING_CHECK=$(check pending "test (ubuntu-latest)")

# fixture: a fresh fixture with no PRs and no declaration, the run's context
# recorded.
fixture() {
    rm -rf "$FIX" "$SHIRABE_RUN_RECORD_TEST_ROOT" && mkdir -p "$FIX" "$SHIRABE_RUN_RECORD_TEST_ROOT/acme" || return 1
    echo '[]' > "$FIX/prs.json"
    printf '%s' "$R" > "$FIX/ctx-repos"
    printf '%s' "$BRANCH" > "$FIX/ctx-settled_branch"
    printf '%s' "$MINE" > "$FIX/ctx-run_id"
    : > "$FIX/gh.log"
    : > "$FIX/koto.log"
}

# declare_ci <json>: the default branch's hosted-ci.json, as the API serves it
# for the pull requests' repository. declare_ci_in <repo> <json>: the same file,
# held by <repo> only. declare_ci_on <host> <repo> <json>: held by <repo> on
# <host> only; the other two hold it on github.com.
declare_ci_in() { printf '%s' "$1" > "$FIX/decl-repo" && printf '%s\n' "$2" > "$FIX/decl"; }
declare_ci() { declare_ci_in "$R" "$1"; }
declare_ci_on() { printf '%s' "$1" > "$FIX/decl-host" && declare_ci_in "$2" "$3"; }
DECLARED=$(jq -cn --arg r "$REASON" '{hosted_ci: "none", reason: $r}')

# pr <n> <state> <run-id> <body> -- [none | <check-json>...]: one PR on the
# run's branch, owned by $ME and recorded in its index by <run-id>, with its
# view and its checks. `none` is gh's answer for no checks (stderr, exit 1); no check
# arguments at all is an empty JSON list. An OPEN PR is the current branch's.
# Its URL is under $PR_BASE, the repository's URL on github.com unless a case
# moves it to another host.
PR_BASE="$REPO_URL"
pr() {
    local n="$1" state="$2" mark="$3" text="$4" body
    shift 4
    [ "${1:-}" = -- ] && shift
    body="$text
"
    mkdir -p "$FIX/idx-pr.acme.widgets.$n" || return 1
    printf '{"workspace":"/w","session":"execute-x","session_id":"sid-1","mode":"single-pr","topic":"x","written_at":"2026-01-01T00:00:00Z"}' \
        > "$FIX/idx-pr.acme.widgets.$n/$mark" || return 1
    jq --argjson n "$n" --arg u "$PR_BASE/pull/$n" --arg s "$state" --arg me "$ME" \
        --arg b "$body" --arg h "$BRANCH" '. + [{number: $n, url: $u, state: $s,
            isCrossRepository: false, author: {login: $me}, baseRefName: "main",
            headRefName: $h, body: $b}]' \
        "$FIX/prs.json" > "$FIX/prs.new" && mv "$FIX/prs.new" "$FIX/prs.json" || return 1
    jq -n --argjson n "$n" --arg s "$state" --arg u "$PR_BASE/pull/$n" --arg b "$body" \
        --arg h "$HEAD_SHA" '{number: $n, state: $s, url: $u, headRefOid: $h, body: $b}' \
        > "$FIX/view-$n.json" || return 1
    if [ "${1:-}" = none ]; then
        echo "no checks reported on the '$BRANCH' branch" > "$FIX/checks-$n.err"
    elif [ $# -gt 0 ]; then
        printf '%s\n' "$@" | jq -s . > "$FIX/checks-$n.json"
    else
        echo '[]' > "$FIX/checks-$n.json"
    fi
    [ "$state" = OPEN ] && printf '%s\n' "$n" > "$FIX/current"
    return 0
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

LOOKUP=(--repo "$R" --head "$BRANCH" --state open-else-merged --run-id "$MINE")

# run_script [env assignments...] -- [args...]: the script, in $CLONE (the
# repository unless a case says otherwise), with the stubs on PATH. Sets GOT,
# OUT and ERR.
CLONE="$REPO"
run_script() {
    local envs=()
    while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
    [ "${1:-}" = -- ] && shift
    (cd "$CLONE" && env PATH="$T/bin:$PATH" GH_FIXTURE="$FIX" ${envs[@]+"${envs[@]}"} \
        "$SCRIPT" "$@") >"$T/out" 2>"$T/err"
    GOT=$?
    OUT=$(cat "$T/out")
    ERR=$(cat "$T/err")
}

expect_exit() {
    local label="$1" want="$2"
    if [ "$GOT" = "$want" ]; then pass "$label (exit $GOT)"
    else fail "$label: expected exit $want, got $GOT; stderr: $ERR"; fi
}
expect_quiet() {
    if [ -z "$OUT" ] && [ -z "$ERR" ]; then pass "$1: nothing on stdout or stderr"
    else fail "$1: stdout [$OUT] stderr [$ERR]"; fi
}
expect_stderr() {
    case "$ERR" in
        *"$2"*) pass "$1" ;;
        *) fail "$1: stderr lacks [$2]: $ERR" ;;
    esac
}
NOTE="$FIX/ctx-ci_none_declared.txt"
expect_note() {
    if [ -f "$NOTE" ]; then pass "$1"
    else fail "$1: ci_none_declared.txt was not recorded"; fi
}
expect_no_note() {
    if [ -f "$NOTE" ]; then fail "$1: a note was recorded: $(cat "$NOTE")"
    else pass "$1"; fi
}
gh_calls() { grep -c -- "$1" "$FIX/gh.log"; }

# ---------------------------------------------------------------------------
# The script, for /work-on (no --owned)
# ---------------------------------------------------------------------------

# --- no declaration: the PR lookup and one API call, quiet, not green ---------
# The lookup is the gate's own `gh pr list --head`, which the script made
# before #1036 too, only after the declaration; it now comes first so the
# declaration can be read from the pull request's repository.
fixture
pr 7 OPEN "$MINE" "Fixes #1." -- none
run_script -- sess
expect_exit "no declaration, no checks: not green" 1
expect_quiet "no declaration"
expect_no_note "no declaration records no note"
if [ "$(grep -c . "$FIX/gh.log")" = 2 ] && [ "$(gh_calls "^pr list --head $BRANCH ")" = 1 ] \
    && [ "$(gh_calls "^api repos/")" = 1 ]; then
    pass "a repository without the file costs the PR lookup and one API call"
else
    fail "unexpected gh calls without a declaration: $(cat "$FIX/gh.log")"
fi
if [ "$(gh_calls "^pr checks")" = 0 ] && [ "$(gh_calls "^pr view")" = 0 ]; then
    pass "a repository without the file never reads the PR's checks or body"
else
    fail "the PR's checks or body were read without a declaration: $(cat "$FIX/gh.log")"
fi
if grep -qx "repos/$R/contents/$DECL_PATH" "$FIX/contents.log" 2>/dev/null; then
    pass "the declaration is read from the PR's repository, with no ref (the default branch)"
else
    fail "the declaration was read from: $(cat "$FIX/contents.log" 2>/dev/null)"
fi
if grep -qF '{owner}' "$FIX/contents.log" 2>/dev/null; then
    fail "the declaration read leaves the repository to gh api: $(cat "$FIX/contents.log")"
else
    pass "the declaration read never leaves the repository to gh api's {owner}/{repo}"
fi
if grep -q -e 'ref=' -e '--ref' "$FIX/gh.log"; then
    fail "the declaration read names a ref: $(cat "$FIX/gh.log")"
else
    pass "the declaration read names no ref, so a branch can't supply it"
fi

# --- declared, no checks (gh's error), recorded in the body: green -----------
fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "Fixes #1.

$RECORD" -- none
run_script -- sess
expect_exit "declared, no checks (gh's error), recorded in the body: green" 0
if [ -z "$OUT" ]; then pass "a pass prints nothing on stdout"; else fail "stdout: $OUT"; fi
expect_note "the pass records ci_none_declared.txt"
if grep -qF "#7 ($REPO_URL/pull/7) has no checks on head $HEAD_SHA" "$NOTE" 2>/dev/null \
    && grep -qxF -- "$REASON" "$NOTE"; then
    pass "the note names the PR, its head and the reason"
else
    fail "unexpected note: $(cat "$NOTE" 2>/dev/null)"
fi
if grep -qx "sess ci_none_declared.txt" "$FIX/added" 2>/dev/null; then
    pass "the note goes to the session named on the command line"
else
    fail "unexpected context writes: $(cat "$FIX/added" 2>/dev/null)"
fi
# On github.com the declaration is read from github.com, named outright.
if [ "$(gh_calls "^api repos/$R/contents/$DECL_PATH --hostname github.com ")" = 1 ]; then
    pass "a github.com PR's declaration is read from github.com"
else
    fail "the declaration read did not name github.com: $(grep '^api' "$FIX/gh.log")"
fi

# --- declared, an empty JSON list: green the same way -------------------------
fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "$RECORD" --
run_script -- sess
expect_exit "declared, an empty check list, recorded: green" 0

# --- declared, the body doesn't record it: not green --------------------------
fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "Fixes #1." -- none
run_script -- sess
expect_exit "declared, no checks, nothing in the body: not green" 1
expect_no_note "an unrecorded exception records no note"
expect_stderr "stderr says what the body is missing" "doesn't record it"
expect_stderr "stderr gives the reason to copy" "$REASON"

fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "This repository declares no hosted CI." -- none
run_script -- sess
expect_exit "declared, the body has the line but not the reason: not green" 1

fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "Reason: $REASON" -- none
run_script -- sess
expect_exit "declared, the body has the reason but not the line: not green" 1

fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "THIS REPOSITORY DECLARES NO HOSTED CI.
Reason: $REASON" -- none
run_script -- sess
expect_exit "the line is matched without regard to case" 0

# The reason must be its own `Reason:` line: a short reason would otherwise
# match almost any body.
fixture
declare_ci '{"hosted_ci": "none", "reason": "docs"}'
pr 7 OPEN "$MINE" "This repository declares no hosted CI. See the docs folder." -- none
run_script -- sess
expect_exit "a reason that only appears inside another line is not a record" 1

fixture
declare_ci '{"hosted_ci": "none", "reason": "docs"}'
pr 7 OPEN "$MINE" "This repository declares no hosted CI.
Reason: docs and more" -- none
run_script -- sess
expect_exit "a Reason line must carry the reason exactly" 1

# A body edited on the web ends its lines in CRLF.
fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "This repository declares no hosted CI."$'\r'"
Reason: $REASON"$'\r'"
" -- none
run_script -- sess
expect_exit "a CRLF body still records the exception" 0

# --- declared, but the PR has checks: the gate filter's answer, not this one's --
fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "$RECORD" -- "$FAIL_CHECK"
run_script -- sess
expect_exit "declared, a failed check: not green" 1
expect_no_note "a PR with checks records no note"
expect_quiet "declared, with checks"
# The PR lookup, the declaration and the checks: the three calls it cost
# before #1036, in another order. The repository with no declaration above
# costs less than this.
if [ "$(grep -c . "$FIX/gh.log")" = 3 ] && [ "$(gh_calls "^pr checks $REPO_URL/pull/7 ")" = 1 ]; then
    pass "declared, a failed check: the PR lookup, the declaration and the checks, by URL"
else
    fail "unexpected gh calls for a declared PR with a failed check: $(cat "$FIX/gh.log")"
fi

fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "$RECORD" -- "$PENDING_CHECK"
run_script -- sess
expect_exit "declared, a pending check: not green" 1

# --- malformed declarations: never green ------------------------------------
for bad in \
    '{"hosted_ci": "github-actions", "reason": "x"}' \
    '{"hosted_ci": "none"}' \
    '{"hosted_ci": "none", "reason": ""}' \
    '{"hosted_ci": "none", "reason": "   "}' \
    '{"hosted_ci": "none", "reason": 7}' \
    '{"hosted_ci": "none", "reason": "two\nlines"}' \
    '{"hosted_ci": false, "reason": "x"}'; do
    fixture
    declare_ci "$bad"
    pr 7 OPEN "$MINE" "$RECORD
two
lines
x" -- none
    run_script -- sess
    expect_exit "a malformed declaration is not green: $bad" 1
    expect_stderr "a malformed declaration is named: $bad" "must say"
    expect_no_note "a malformed declaration records no note: $bad"
done

for unrelated in 'not json at all' '{"default_branch": "main"}' '["none"]'; do
    fixture
    declare_ci "$unrelated"
    pr 7 OPEN "$MINE" "$RECORD" -- none
    run_script -- sess
    expect_exit "a file that names no hosted_ci is no declaration: $unrelated" 1
    expect_quiet "no hosted_ci: $unrelated"
done

# --- reads that fail ---------------------------------------------------------------
fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "$RECORD" -- none
echo "HTTP 502: Bad Gateway" > "$FIX/checks-7.err"
run_script -- sess
expect_exit "a checks read that fails for another reason is not green" 1
expect_stderr "the failed read is named" "could not read the pull request's checks"

fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "$RECORD" -- none
run_script KOTO_FAIL=1 -- sess
expect_exit "a failed context write is not green" 1

# --- no open PR on the branch: gh's current-branch lookup names it ------------
fixture
declare_ci "$DECLARED"
pr 7 MERGED "$MINE" "$RECORD" -- none
printf '7\n' > "$FIX/current"
run_script -- sess
expect_exit "no open PR, declared, no checks, recorded: green through the current-branch lookup" 0
if [ "$(gh_calls "^pr view --json url ")" = 1 ] && grep -qx "repos/$R/contents/$DECL_PATH" "$FIX/contents.log" 2>/dev/null; then
    pass "no open PR: the URL comes from gh's current-branch lookup, and the declaration from its repository"
else
    fail "no open PR: unexpected reads: $(cat "$FIX/gh.log")"
fi

fixture
pr 7 MERGED "$MINE" "$RECORD" -- none
printf '7\n' > "$FIX/current"
run_script -- sess
expect_exit "no open PR, no declaration: not green" 1
expect_quiet "no open PR, no declaration"
if [ "$(grep -c . "$FIX/gh.log")" = 3 ]; then
    pass "no open PR, no declaration: two lookups and one API call"
else
    fail "no open PR, no declaration: unexpected gh calls: $(cat "$FIX/gh.log")"
fi

fixture
declare_ci "$DECLARED"
run_script -- sess
expect_exit "no pull request at all: not green" 1
expect_stderr "no pull request at all: gh's answer passes through" "no pull requests found"
if [ "$(gh_calls "^api repos/")" = 0 ]; then pass "no pull request at all: no declaration read"
else fail "no pull request at all: the declaration was read: $(cat "$FIX/gh.log")"; fi

# --- a fork clone: the first remote is not the PR's repository (#1036) --------
# origin is the fork and upstream the parent, where the pull request lives.
# gh api would fill {owner}/{repo} from origin, the first remote; gh pr, which
# the gate uses, resolves the parent. The stub serves the pull request as gh pr
# does and fills the placeholders as gh api does, so a declaration read through
# {owner}/{repo} would reach the fork.
FORK="$T/fork"
mkdir -p "$FORK" || exit 1
git -C "$FORK" init -q || exit 1
git -C "$FORK" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init || exit 1
git -C "$FORK" checkout -q -b "$BRANCH" || exit 1
git -C "$FORK" remote add origin "https://github.com/$ME/widgets.git" || exit 1
git -C "$FORK" remote add upstream "$REPO_URL.git" || exit 1
CLONE="$FORK"

# The stub itself: a placeholder read reaches the fork, as gh api's would.
fixture
declare_ci_in "$ME/widgets" "$DECLARED"
if (cd "$FORK" && env PATH="$T/bin:$PATH" GH_FIXTURE="$FIX" \
    gh api "repos/{owner}/{repo}/contents/$DECL_PATH") >/dev/null 2>&1; then
    pass "fork clone: the stub fills {owner}/{repo} from the first remote, the fork"
else
    fail "fork clone: the stub did not fill {owner}/{repo} from the fork"
fi

fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "$RECORD" -- none
run_script -- sess
expect_exit "fork clone: the parent declares no hosted CI, recorded in the PR: green" 0
expect_note "fork clone: the pass records the note"
if [ "$(cat "$FIX/contents.log" 2>/dev/null)" = "repos/$R/contents/$DECL_PATH" ]; then
    pass "fork clone: the declaration is read from the PR's repository, not the first remote's"
else
    fail "fork clone: the declaration was read from: $(cat "$FIX/contents.log" 2>/dev/null)"
fi

fixture
declare_ci_in "$ME/widgets" "$DECLARED"
pr 7 OPEN "$MINE" "$RECORD" -- none
run_script -- sess
expect_exit "fork clone: a declaration only the fork carries is not the PR's: not green" 1
expect_quiet "fork clone, declared only on the fork"
expect_no_note "fork clone: the fork's declaration records no note"
CLONE="$REPO"

# --- a pull request on a host that isn't gh's default (#1051) --------------------
# The declaration is served only from ghe.example.com. Before #1051 the read
# went to gh's default host and got a 404, so this case was not green.
GHE_URL="https://ghe.example.com/$R"
PR_BASE="$GHE_URL"
fixture
declare_ci_on ghe.example.com "$R" "$DECLARED"
pr 7 OPEN "$MINE" "$RECORD" -- none
run_script -- sess
expect_exit "an enterprise PR, declared on its own host, recorded: green" 0
expect_note "an enterprise PR's pass records the note"
if grep -qF "#7 ($GHE_URL/pull/7) has no checks" "$NOTE" 2>/dev/null; then
    pass "the note names the enterprise PR's URL"
else
    fail "unexpected note: $(cat "$NOTE" 2>/dev/null)"
fi
if [ "$(gh_calls "^api repos/$R/contents/$DECL_PATH --hostname ghe.example.com ")" = 1 ]; then
    pass "an enterprise PR's declaration is read from its own host"
else
    fail "the declaration read did not go to ghe.example.com: $(grep '^api' "$FIX/gh.log")"
fi
if [ "$(gh_calls "^pr checks $GHE_URL/pull/7 ")" = 1 ] && [ "$(gh_calls "^pr view $GHE_URL/pull/7 ")" = 1 ]; then
    pass "an enterprise PR's checks and body are read by its URL"
else
    fail "an enterprise PR was not read by its URL: $(cat "$FIX/gh.log")"
fi

# The same repository's declaration on github.com is another server's file.
fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "$RECORD" -- none
run_script -- sess
expect_exit "an enterprise PR, declared only on github.com: not green" 1
expect_quiet "an enterprise PR, declared only on github.com"
expect_no_note "github.com's declaration records no note for an enterprise PR"

# A port is part of the host.
PR_BASE="https://ghe.example.com:8443/$R"
fixture
declare_ci_on ghe.example.com:8443 "$R" "$DECLARED"
pr 7 OPEN "$MINE" "$RECORD" -- none
run_script -- sess
expect_exit "a PR on a host with a port, declared there: green" 0
if [ "$(gh_calls "^api .* --hostname ghe.example.com:8443 ")" = 1 ]; then
    pass "a host's port is kept in the declaration read"
else
    fail "the declaration read did not keep the port: $(grep '^api' "$FIX/gh.log")"
fi
PR_BASE="$REPO_URL"

# --- a lookup that answers something other than a pull request URL ------------
for bad in "https://github.com/$R/issues/7" \
    "https://ghe.example.com/prefix/$R/pull/7" \
    "https://github.com/$R/pull/7x" \
    "not a url"; do
    fixture
    declare_ci "$DECLARED"
    jq -n --arg u "$bad" '[{number: 7, url: $u, state: "OPEN"}]' > "$FIX/prs.json" || exit 1
    run_script -- sess
    expect_exit "a lookup that answers [$bad] is not green" 1
    expect_stderr "the answer is named on stderr [$bad]" "could not read the pull request's URL: gh answered [$bad]"
    if [ "$(gh_calls "^api")" = 0 ] && [ "$(gh_calls "^pr checks")" = 0 ]; then
        pass "nothing more is read after [$bad]"
    else
        fail "reads went on after [$bad]: $(cat "$FIX/gh.log")"
    fi
done

# --- usage ------------------------------------------------------------------------
fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "$RECORD" -- none
run_script --
expect_exit "a missing session argument is exit 1" 1
run_script -- sess --owned
expect_exit "--owned with no lookup arguments is exit 1" 1
run_script -- sess --owned --head "$BRANCH"
expect_exit "--owned with no --repo is exit 1" 1
run_script -- sess --bogus x
expect_exit "an unknown flag is exit 1" 1

# ---------------------------------------------------------------------------
# The script, for /execute (--owned)
# ---------------------------------------------------------------------------

fixture
declare_ci "$DECLARED"
pr 7 OPEN "$MINE" "$RECORD" -- none
run_script -- execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: declared, no checks, recorded: green" 0
expect_note "--owned: the pass records the note"
if grep -qx "execute-x ci_none_declared.txt" "$FIX/added" 2>/dev/null; then
    pass "--owned: the note goes to the run's session"
else
    fail "--owned: unexpected context writes: $(cat "$FIX/added" 2>/dev/null)"
fi
if grep -qx "repos/$R/contents/$DECL_PATH" "$FIX/contents.log" 2>/dev/null; then
    pass "--owned: the declaration is read from the repository --repo names"
else
    fail "--owned: the declaration was read from: $(cat "$FIX/contents.log" 2>/dev/null)"
fi
# --repo carries no host, and owned-pr.sh looks it up on gh's default host, so
# the declaration read leaves the host to gh too.
if [ "$(gh_calls "^api repos/$R/contents/")" = 1 ] && [ "$(gh_calls "^api .*--hostname")" = 0 ]; then
    pass "--owned: the declaration is read from gh's default host, the one owned-pr.sh searches"
else
    fail "--owned: unexpected declaration read: $(grep '^api' "$FIX/gh.log")"
fi
if grep -qF "pr checks $REPO_URL/pull/7 " "$FIX/gh.log" && grep -qF "pr view $REPO_URL/pull/7 " "$FIX/gh.log"; then
    pass "--owned: the PR is read by the URL the lookup answered"
else
    fail "--owned: the PR was not read by its URL: $(cat "$FIX/gh.log")"
fi

fixture
declare_ci "$DECLARED"
pr 7 OPEN "$OTHER" "$RECORD" -- none
run_script -- execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: another run's PR is never the one judged" 1
if [ "$(gh_calls "pr checks")" = 0 ]; then pass "--owned: another run's PR's checks are never read"
else fail "--owned: another run's PR's checks were read: $(cat "$FIX/gh.log")"; fi

fixture
pr 7 OPEN "$MINE" "$RECORD" -- none
run_script -- execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: no declaration is not green" 1
if [ "$(grep -c . "$FIX/gh.log")" = 1 ]; then pass "--owned: no declaration costs one API call"
else fail "--owned: unexpected gh calls: $(cat "$FIX/gh.log")"; fi

# ---------------------------------------------------------------------------
# Wiring: the gates as the templates ship them
# ---------------------------------------------------------------------------

# gate_command <template> <gate>: the gate's command, unquoted.
gate_command() {
    local raw
    raw=$(koto_gate_command "$1" "$2") || return 1
    [ -n "$raw" ] || return 1
    koto_unquote_scalar "$raw"
}

# run_gate <command> [plugin-root]: a gate as koto runs it, from the repository.
run_gate() {
    local cmd="$1" root="${2:-$REPO_ROOT}"
    cmd="${cmd//\{\{PLUGIN_ROOT\}\}/$root}"
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
    if [ -z "$CMD" ]; then
        fail "could not read $gate from $template"
        continue
    fi
    case "$gate" in
        ci_passing)
            case "$CMD" in
                *'ci-cancel-after-merge.sh" "{{SESSION_NAME}}" || "{{PLUGIN_ROOT}}/skills/work-on/scripts/ci-none-declared.sh" "{{SESSION_NAME}}" || exit 1')
                    pass "$gate falls back to ci-none-declared.sh last, and ends in || exit 1" ;;
                *) fail "$gate does not end in the ci-none-declared.sh fallback: $CMD" ;;
            esac
            ;;
        owned_ci_passing)
            case "$CMD" in
                *'|| "{{PLUGIN_ROOT}}/skills/work-on/scripts/ci-none-declared.sh" execute-{{PLAN_SLUG}} --owned --repo '*'--state open-else-merged --run-id '*'|| exit 1')
                    pass "$gate falls back to ci-none-declared.sh --owned last, and ends in || exit 1" ;;
                *) fail "$gate does not end in the ci-none-declared.sh --owned fallback: $CMD" ;;
            esac
            ;;
    esac

    # Zero checks, the post-push window: gh's answer is an error, not JSON.
    fixture
    pr 7 OPEN "$MINE" "Fixes #1." -- none
    run_gate "$CMD"
    expect_exit "$gate: no checks reported (the window after a push) is not green" 1
    expect_no_note "$gate: no checks records no note"

    # Zero checks as an empty list, if a gh release prints one.
    fixture
    pr 7 OPEN "$MINE" "Fixes #1." --
    run_gate "$CMD"
    expect_exit "$gate: an empty check list is not green" 1

    # What passes today still passes.
    fixture
    pr 7 OPEN "$MINE" "Fixes #1." -- "$PASS_CHECK" "$PASS_CHECK"
    run_gate "$CMD"
    expect_exit "$gate: every check passing is green" 0
    if [ "$(gh_calls "contents")" = 0 ]; then pass "$gate: a green PR never reaches the fallback"
    else fail "$gate: a green PR reached the fallback: $(cat "$FIX/gh.log")"; fi

    fixture
    pr 7 OPEN "$MINE" "Fixes #1." -- "$PASS_CHECK" "$SKIP_CHECK"
    run_gate "$CMD"
    expect_exit "$gate: passing and skipped checks are green" 0

    fixture
    pr 7 OPEN "$MINE" "Fixes #1." -- "$SKIP_CHECK" "$SKIP_CHECK"
    run_gate "$CMD"
    expect_exit "$gate: every check skipped is green" 0

    # What fails today still fails.
    fixture
    pr 7 OPEN "$MINE" "Fixes #1." -- "$PASS_CHECK" "$FAIL_CHECK"
    run_gate "$CMD"
    expect_exit "$gate: a failed check is not green" 1

    fixture
    pr 7 OPEN "$MINE" "Fixes #1." -- "$PASS_CHECK" "$PENDING_CHECK"
    run_gate "$CMD"
    expect_exit "$gate: a pending check is not green" 1

    # The stated exception.
    fixture
    declare_ci "$DECLARED"
    pr 7 OPEN "$MINE" "$RECORD" -- none
    run_gate "$CMD"
    expect_exit "$gate: declared no hosted CI, no checks, recorded in the body: green" 0
    expect_note "$gate: the declared pass records ci_none_declared.txt"

    fixture
    declare_ci "$DECLARED"
    pr 7 OPEN "$MINE" "Fixes #1." -- none
    run_gate "$CMD"
    expect_exit "$gate: declared, but the body doesn't record it: not green" 1

    fixture
    declare_ci "$DECLARED"
    pr 7 OPEN "$MINE" "$RECORD" -- "$FAIL_CHECK"
    run_gate "$CMD"
    expect_exit "$gate: declared, with a failed check: not green" 1

    # Nothing the gate calls can run: still exactly 1.
    mkdir -p "$T/empty-plugin" || exit 1
    fixture
    declare_ci "$DECLARED"
    pr 7 OPEN "$MINE" "$RECORD" -- none
    run_gate "$CMD" "$T/empty-plugin"
    expect_exit "$gate: exits exactly 1 when neither fallback can run" 1
done

echo
echo "ci-none-declared_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
