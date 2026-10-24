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
#     with a non-empty, one-line "reason". It is read before the checks, so a
#     repository without one (nearly all of them) exits 1 quietly after the
#     pull request lookup and one API call. A file that names hosted_ci but
#     says anything else is a diagnostic and exit 1.
#   - the pull request has zero checks: gh's `no checks reported` error,
#     which is what gh prints for an empty check rollup (cli/cli
#     pkg/cmd/pr/checks/checks.go, v2.76.2 through v2.103.0), or an empty
#     JSON list. A pull request with any check is the gate filter's to judge.
#   - the pull request body records the exception: a line saying the
#     repository declares no hosted CI, and the line `Reason: <reason>` with
#     the declaration's reason verbatim.
#
# Which pull request depends on the caller, as in ci-cancel-after-merge.sh:
#   /work-on (no --owned): the current branch's, found the way the gate finds
#   it (`gh pr list --head`, else gh's own current-branch lookup). It is
#   looked up first, by URL, and the declaration is read from the host and
#   repository that URL names (pr-url.sh parses it), so the declaration and
#   the pull request come from one repository even in a fork clone, where gh
#   api's {owner}/{repo} would name the first remote's (#1036), and from one
#   server even when gh's default host isn't the pull request's (#1051).
#   /execute (--owned <owned-pr.sh arguments>): the one owned-pr.sh resolves
#   with those arguments, in the repository their --repo names. --repo is
#   owner/repo with no host, and owned-pr.sh looks it up on gh's default
#   host, so the declaration is read from that host too, before the lookup,
#   which keeps a repository without one at a single call.
#
# On a pass it records `ci_none_declared.txt` in koto context, naming the pull
# request, its head and the reason. A failed write is exit 1, so a pass is
# never unrecorded.
#
# Nothing on stdout. Diagnostics go to stderr: a declaration read that failed
# other than with a 404, a malformed declaration, a body that doesn't record
# it, a later read that failed. No diagnostic is discarded: gh's stderr goes to
# a file whose first line the message quotes, and jq parses with `try`.
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
REPO=""
# Empty under --owned: gh api then uses gh's default host, the one owned-pr.sh
# searches.
HOST=""
if [ $# -gt 0 ]; then
    [ "$1" = --owned ] && [ $# -gt 1 ] || no "$USAGE"
    OWNED=1
    shift
    # owned-pr.sh's --repo names the repository the run recorded, the one its
    # pull request lives in, so the declaration is read from there.
    prev=""
    for a in "$@"; do
        [ "$prev" = --repo ] && REPO="$a"
        prev="$a"
    done
    [ -n "$REPO" ] || no "$USAGE"
fi

HERE=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || no
# shellcheck source=pr-url.sh
. "$HERE/pr-url.sh" || no "pr-url.sh not found at $HERE/pr-url.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ci-none-declared.XXXXXX") || no
trap 'rm -rf "$TMP"' EXIT

if [ "$OWNED" = 0 ]; then
    # The gate's own lookup, by URL: the open pull request on this branch, and
    # when there is none, gh's current-branch lookup, the one the gate's
    # `gh pr checks` falls back to. gh api fills {owner}/{repo} from the first
    # git remote and ignores `gh repo set-default`, while gh pr resolves the
    # repository the way the gate does, so the host and repository are taken
    # from the URL, as ci-cancel-after-merge.sh does, and never from the
    # placeholders or gh's default host.
    BRANCH=$(git rev-parse --abbrev-ref HEAD) || no
    SELECTOR=$(gh pr list --head "$BRANCH" --json url --jq '.[0].url // empty' </dev/null) || no
    if [ -z "$SELECTOR" ]; then
        SELECTOR=$(gh pr view --json url --jq .url </dev/null) || no
    fi
    pr_url_parse "$SELECTOR" || no "could not read the pull request's URL: gh answered [$SELECTOR]"
    HOST="$PR_HOST"
    REPO="$PR_OWNER/$PR_REPO"
fi

# The declaration, from the default branch: the contents API with no ref reads
# it there. A 404 is the common answer, a repository with no declaration, and
# exits quietly; any other failed read is named. --hostname comes after the
# endpoint: gh reads a flag anywhere, and the gh stand-ins in this skill's
# suites and the evals' fixtures take the endpoint from the argument after
# `api`.
if ! gh api "repos/$REPO/contents/$DECLARATION" ${HOST:+--hostname "$HOST"} \
    -H 'Accept: application/vnd.github.raw' </dev/null >"$TMP/decl" 2>"$TMP/err"; then
    grep -q -e '404' -e 'Not Found' "$TMP/err" && no
    no "could not read $DECLARATION from the default branch: $(head -n 1 "$TMP/err")"
fi
# The file is parsed with `try`, so text that isn't JSON is no declaration
# rather than a jq error. A file that names hosted_ci is a declaration, and one
# that says anything but "none" with a usable reason is named.
DECL=$(jq -R -s -r '(try fromjson catch null) as $d
    | if ($d | type) != "object" then "absent"
      elif ($d | has("hosted_ci") | not) then "absent"
      elif $d.hosted_ci != "none" then "malformed"
      elif ($d.reason | type) != "string" then "malformed"
      elif ($d.reason | test("\\S") | not) then "malformed"
      elif ($d.reason | test("[\\r\\n]")) then "malformed"
      else "reason:" + $d.reason end' "$TMP/decl") || no "could not parse $DECLARATION"
case "$DECL" in
    absent) no ;;
    reason:*) REASON="${DECL#reason:}" ;;
    *) no "$DECLARATION on the default branch must say \"hosted_ci\": \"none\" and give a non-empty, one-line \"reason\"" ;;
esac

if [ "$OWNED" = 1 ]; then
    # The rest of the arguments are owned-pr.sh's, passed as given. Its answer
    # is one URL or nothing, and its own diagnostics pass through.
    OWNED_PR="$HERE/../../execute/scripts/owned-pr.sh"
    [ -x "$OWNED_PR" ] || no "owned-pr.sh not found at $OWNED_PR"
    SELECTOR=$("$OWNED_PR" "$@" </dev/null) || no
    [ -n "$SELECTOR" ] || no
fi

# Zero checks. gh answers an empty rollup with an error, not with `[]`; an
# empty list is read the same way in case a gh release starts printing one.
# Both modes read the pull request by its URL from here on. pr-checks.sh is
# `gh pr checks` wherever the token can read checks, and answers the same way
# from the Actions runs and statuses where GitHub refuses the read (#1132).
if "$HERE/pr-checks.sh" "$SELECTOR" --json bucket </dev/null >"$TMP/checks" 2>"$TMP/err"; then
    COUNT=$(jq -R -s -r '(try fromjson catch null)
        | if type == "array" then length else "unreadable" end' "$TMP/checks") || COUNT=unreadable
    case "$COUNT" in
        ''|*[!0-9]*) no "could not read the pull request's checks: gh printed no JSON list" ;;
    esac
else
    grep -q 'no checks reported' "$TMP/err" || no "could not read the pull request's checks: $(head -n 1 "$TMP/err")"
    COUNT=0
fi
[ "$COUNT" = 0 ] || no

gh pr view "$SELECTOR" --json number,url,headRefOid,body </dev/null >"$TMP/pr" 2>"$TMP/err" \
    || no "could not read the pull request: $(head -n 1 "$TMP/err")"
PR=$(jq -R -s -r '(try fromjson catch null)
    | if type == "object" then [.number, .url, .headRefOid] | map(. // "" | tostring) | @tsv
      else "" end' "$TMP/pr") || PR=""
IFS=$'\t' read -r NUMBER URL HEAD <<<"$PR"
[ -n "$NUMBER" ] && [ -n "$URL" ] && [ -n "$HEAD" ] || no "could not read the pull request's number, URL and head"
# The body as lines, carriage returns dropped: a body edited on the web ends
# its lines in CRLF.
jq -R -s -r '(try fromjson catch null) | if type == "object" then (.body // "" | tostring) else "" end
    | gsub("\r"; "")' "$TMP/pr" >"$TMP/body" || no "could not read the pull request's body"

# The reason must be a whole line, `Reason: <reason>`, not just appear
# somewhere: a short reason would otherwise match almost any body.
if ! grep -qi 'declares no hosted CI' "$TMP/body" || ! grep -qxF -- "Reason: $REASON" "$TMP/body"; then
    no "#$NUMBER has no checks and the repository declares no hosted CI, but the pull request body doesn't record it: add a line saying the repository declares no hosted CI, and the line: Reason: $REASON"
fi

{
    echo "#$NUMBER ($URL) has no checks on head $HEAD; its repository declares no hosted CI in $DECLARATION on the default branch:"
    echo "$REASON"
} | koto context add "$SESSION" ci_none_declared.txt >/dev/null \
    || no "could not record ci_none_declared.txt in koto context"

exit 0
