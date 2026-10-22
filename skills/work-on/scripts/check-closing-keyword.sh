#!/usr/bin/env bash
# check-closing-keyword.sh -- does the pull request close an issue that lives
# in another repository?
# Part of the work-on skill
#
# pr_creation's closing_keyword gate runs this only when the run recorded
# ISSUE_REPO, the repository a cross-repository issue lives in. With
# ISSUE_REPO empty the gate keeps its own inline expression and never starts
# this script, so a same-repository run is checked exactly as it was before
# ISSUE_REPO existed.
#
# GitHub closes an issue in another repository only through a qualified
# reference, `Fixes owner/repo#N`. A bare `Fixes #N` in this pull request
# names this repository's issue N, which is either missing or a different
# issue, and merging would close that one. So:
#
#   - `<keyword> <ISSUE_REPO>#N` passes;
#   - a bare `<keyword> #N` passes only when ISSUE_REPO is the pull request's
#     own repository (read from the URL `gh pr view` reports); when the issue
#     is elsewhere a bare reference fails the gate, even next to the
#     qualified one, because it would still close the wrong issue;
#   - a qualified reference to any other repository doesn't count.
#
# The keywords are the gate's own: close, closes, closed, fix, fixes, fixed,
# resolve, resolves, resolved, in any case. The repository is matched
# literally: its `.` is escaped before it reaches the expression (`.github`
# must not match `xgithub`), the keyword and the reference are separated by
# whitespace only, so nothing can stand in front of the owner, and `#N` must
# not run into more digits (`#12` is not `#123`). The qualified form also
# needs the keyword to start a word, so `prefixes owner/repo#N` doesn't count;
# the bare form is kept exactly as the gate's inline expression has it.
#
# Usage: check-closing-keyword.sh --issue <N> --repo <owner/repo>
#
# Exit codes, which the gate routes on:
#   0  the body closes the issue
#   1  it doesn't, a bare reference names the wrong issue, or the pull request
#      or its repository couldn't be read. Fail-closed, like the inline
#      expression: pr_creation routes 1 to done_blocked. The reason goes to
#      stderr.
#   2  usage: a missing, unknown or malformed argument; no edge routes it,
#      so pr_creation holds
#
# Needs gh, authenticated, run from the repository the pull request is in.
# One gh call. Bash 3.2: no associative arrays, no mapfile.
set -u

usage() {
    echo "usage: check-closing-keyword.sh --issue <N> --repo <owner/repo>" >&2
    exit 2
}

refuse() {
    echo "check-closing-keyword: $1" >&2
    exit 1
}

ISSUE=""
REPO=""
while [ $# -gt 0 ]; do
    case "$1" in
        --issue|--repo)
            [ $# -ge 2 ] || usage
            if [ "$1" = --issue ]; then ISSUE="$2"; else REPO="$2"; fi
            shift 2
            ;;
        *) usage ;;
    esac
done

# Digits with no leading zero, as the issue number koto substituted.
case "$ISSUE" in
    ''|*[!0-9]*|0*) usage ;;
esac
# The template variable's own pattern, checked again here because the value
# reaches a regular expression. [[ =~ ]] anchors on the whole string, so a
# value with a newline in it can't pass on its first line alone.
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
[[ $REPO =~ $RE_REPO ]] || usage

NL='
'
# One read: the URL on the first line, the body after it. An empty body
# leaves the URL alone, with no newline to split on. gh's own error goes to
# stderr ahead of the refusal, which is where the gate's reader finds it.
OUT=$(gh pr view --json url,body --jq '.url, .body') \
    || refuse "could not read the pull request with gh pr view"
URL=${OUT%%"$NL"*}
case "$OUT" in
    *"$NL"*) BODY=${OUT#*"$NL"} ;;
    *)       BODY="" ;;
esac

# https://<host>/<owner>/<repo>/pull/<n> -> <owner>/<repo>
PR_REPO=$(printf '%s\n' "${URL#*://}" | awk -F/ 'NF == 5 && $4 == "pull" { print $2 "/" $3 }')
[ -n "$PR_REPO" ] || refuse "could not read the pull request's repository from [$URL]"

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

KW='(close[sd]?|fix(es|ed)?|resolve[sd]?)'
# `.` is the one character the repository pattern allows that means something
# in an extended expression. sed rather than ${REPO//./...}, whose backslash
# handling in the replacement differs between bash 3.2 and 5.2.
REPO_RE=$(printf '%s' "$REPO" | sed 's/\./\\./g')
BARE="${KW}[[:space:]]+#${ISSUE}([^0-9]|\$)"
QUALIFIED="(^|[^[:alnum:]_])${KW}[[:space:]]+${REPO_RE}#${ISSUE}([^0-9]|\$)"

# A here-string rather than a pipe: grep -q stops at the first match, and a
# writer still filling the pipe would then fail.
has() { grep -qiE "$1" <<<"$BODY"; }

if [ "$(lower "$REPO")" = "$(lower "$PR_REPO")" ]; then
    # The issue is in this repository after all: either form closes it.
    if has "$BARE" || has "$QUALIFIED"; then
        exit 0
    fi
    refuse "the body has no closing keyword for #$ISSUE: add Fixes #$ISSUE"
fi

if has "$BARE"; then
    refuse "a bare closing reference to #$ISSUE closes $PR_REPO#$ISSUE, not $REPO#$ISSUE: write Fixes $REPO#$ISSUE and drop the bare one"
fi
has "$QUALIFIED" && exit 0
refuse "the body has no closing keyword for $REPO#$ISSUE: add Fixes $REPO#$ISSUE"
