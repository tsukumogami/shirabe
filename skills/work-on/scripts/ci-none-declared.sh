#!/usr/bin/env bash
# ci-none-declared.sh -- for /work-on and /execute: may a pull request with no
# checks at all count as green, because its repository says it has no hosted
# CI?
# Part of the work-on skill
#
# ci_passing (work-on.md) and owned_ci_passing (execute.md) read a pull
# request with zero checks as not green (#1018): no checks yet is the window
# just after a push, before Actions creates the check suites, and a list that
# stays empty is CI that never ran. Neither is a pass. The one exception is a
# repository that genuinely has no hosted CI, and that is never inferred from
# an empty list. The repository states it, on its default branch, in
#
#   .claude/shirabe-extensions/hosted-ci.json
#   {"hosted_ci": "none", "reason": "<one line saying why>"}
#
# The file is read from the default branch through the GitHub API, never from
# the working tree or the pull request's head, so a pull request can't declare
# itself out of CI: the declaration is a change someone reviewed and merged.
#
# koto runs this as the last fallback of both gates, reached only when the
# gate's own filter says not green and ci-cancel-after-merge.sh didn't pass;
# the agent never runs it. It passes only when every one of these holds:
#
#   - the default branch carries the file, and it says "hosted_ci": "none"
#     with a non-empty, one-line "reason". It is read first, so a repository
#     without one (nearly all of them) costs one API call and exits 1
#     quietly. A file that names hosted_ci but says anything else is a
#     diagnostic and exit 1.
#   - the pull request has zero checks: gh's `no checks reported` error,
#     which is what gh prints for an empty check rollup (cli/cli
#     pkg/cmd/pr/checks/checks.go, v2.76.2 through v2.103.0), or an empty
#     JSON list. A pull request with any check is the gate filter's to judge.
#   - the pull request body records the exception: a line saying the
#     repository declares no hosted CI, and the declaration's reason verbatim.
#
# Which pull request depends on the caller, as in ci-cancel-after-merge.sh:
#   /work-on (no --owned): the current branch's, found the way the gate finds
#   it (`gh pr list --head`, else gh's own current-branch lookup), in the
#   repository the working tree's remote names.
#   /execute (--owned <owned-pr.sh arguments>): the one owned-pr.sh resolves
#   with those arguments, in the repository their --repo names.
#
# On a pass it records `ci_none_declared.txt` in koto context, naming the pull
# request, its head and the reason. A failed write is exit 1, so a pass is
# never unrecorded.
#
# Nothing on stdout. Diagnostics go to stderr, and only once the repository
# has declared: a malformed declaration, a body that doesn't record it, a
# read that failed.
#
# Usage: ci-none-declared.sh <koto-session-name> [--owned <owned-pr.sh arguments>...]
#
# Exit codes:
#   0 -- no checks, declared on the default branch, recorded in the body; the
#        note is recorded
#   1 -- anything else, including a missing session argument or a malformed
#        --owned. The gates' edges match exit 0 and 1 only, so this script
#        never exits otherwise.
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

DECLARATION=.claude/shirabe-extensions/hosted-ci.json

no() {
    [ -z "${1:-}" ] || echo "ci-none-declared: $1" >&2
    exit 1
}

USAGE="usage: ci-none-declared.sh <koto-session-name> [--owned <owned-pr.sh arguments>...]"
SESSION="${1:-}"
[ -n "$SESSION" ] || no "$USAGE"
shift
OWNED=0
REPO='{owner}/{repo}'
if [ $# -gt 0 ]; then
    [ "$1" = --owned ] && [ $# -gt 1 ] || no "$USAGE"
    OWNED=1
    shift
    # owned-pr.sh's --repo names the repository the run recorded, the one its
    # pull request lives in, so the declaration is read from there.
    REPO=""
    prev=""
    for a in "$@"; do
        [ "$prev" = --repo ] && REPO="$a"
        prev="$a"
    done
    [ -n "$REPO" ] || no "$USAGE"
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ci-none-declared.XXXXXX") || no
trap 'rm -rf "$TMP"' EXIT

# The declaration, from the default branch: the contents API with no ref reads
# it there. Without --owned, gh fills {owner}/{repo} from the working tree's
# remote, the same repository the gate's own `gh pr checks` reads.
gh api "repos/$REPO/contents/$DECLARATION" -H 'Accept: application/vnd.github.raw' \
    </dev/null >"$TMP/decl" 2>/dev/null || no
jq -e 'type == "object" and has("hosted_ci")' "$TMP/decl" >/dev/null 2>&1 || no
REASON=$(jq -r 'select(.hosted_ci == "none" and (.reason | type) == "string"
        and (.reason | test("\\S")) and (.reason | test("[\\r\\n]") | not)) | .reason' \
    "$TMP/decl" 2>/dev/null)
[ -n "$REASON" ] || no "$DECLARATION on the default branch must say \"hosted_ci\": \"none\" and give a non-empty, one-line \"reason\""

if [ "$OWNED" = 1 ]; then
    # The rest of the arguments are owned-pr.sh's, passed as given. Its answer
    # is one URL or nothing, and its own diagnostics pass through.
    HERE=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || no
    OWNED_PR="$HERE/../../execute/scripts/owned-pr.sh"
    [ -x "$OWNED_PR" ] || no "owned-pr.sh not found at $OWNED_PR"
    SELECTOR=$("$OWNED_PR" "$@" </dev/null) || no
    [ -n "$SELECTOR" ] || no
else
    # The gate's own lookup: the open pull request on this branch, and when
    # there is none, an empty selector leaves gh to resolve the branch.
    BRANCH=$(git rev-parse --abbrev-ref HEAD) || no
    SELECTOR=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number // empty' </dev/null) || no
fi

# Zero checks. gh answers an empty rollup with an error, not with `[]`; an
# empty list is read the same way in case a gh release starts printing one.
if gh pr checks ${SELECTOR:+"$SELECTOR"} --json bucket </dev/null >"$TMP/checks" 2>"$TMP/err"; then
    COUNT=$(jq 'if type == "array" then length else error("not a list") end' "$TMP/checks" 2>/dev/null) \
        || no "could not read the pull request's checks"
else
    grep -q 'no checks reported' "$TMP/err" || no "could not read the pull request's checks: $(head -n 1 "$TMP/err")"
    COUNT=0
fi
[ "$COUNT" = 0 ] || no

gh pr view ${SELECTOR:+"$SELECTOR"} --json number,url,headRefOid,body </dev/null >"$TMP/pr" 2>/dev/null \
    || no "could not read the pull request"
NUMBER=$(jq -r '.number // empty' "$TMP/pr" 2>/dev/null)
URL=$(jq -r '.url // empty' "$TMP/pr" 2>/dev/null)
HEAD=$(jq -r '.headRefOid // empty' "$TMP/pr" 2>/dev/null)
[ -n "$NUMBER" ] && [ -n "$URL" ] && [ -n "$HEAD" ] || no "could not read the pull request's number, URL and head"
jq -r '.body // ""' "$TMP/pr" >"$TMP/body" 2>/dev/null || no "could not read the pull request's body"

if ! grep -qi 'declares no hosted CI' "$TMP/body" || ! grep -qF -- "$REASON" "$TMP/body"; then
    no "#$NUMBER has no checks and the repository declares no hosted CI, but the pull request body doesn't record it: add a line saying the repository declares no hosted CI, and the reason verbatim: $REASON"
fi

{
    echo "#$NUMBER ($URL) has no checks on head $HEAD; its repository declares no hosted CI in $DECLARATION on the default branch:"
    echo "$REASON"
} | koto context add "$SESSION" ci_none_declared.txt >/dev/null \
    || no "could not record ci_none_declared.txt in koto context"

exit 0
