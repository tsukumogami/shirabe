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
#   - `<keyword> <ISSUE_REPO>#N` passes, and for an issue elsewhere so does
#     the same reference as a markdown link's text,
#     `<keyword> [<ISSUE_REPO>#N](...)`;
#   - when ISSUE_REPO is the pull request's own repository (read from the URL
#     `gh pr view` reports), a bare `<keyword> #N` passes too;
#   - when the issue is elsewhere, any closing reference to issue N of the
#     pull request's own repository fails the gate, even next to the
#     qualified one, because merging would still close that issue: a bare
#     `#N`, `GH-N`, `<PR repo>#N`, and `https://<host>/<PR repo>/issues/N`,
#     each also as a markdown link's text (`[#N](...)`, whatever the link
#     points at) or inside `<...>`, and the issue URL as a link's target
#     (`[...](https://<host>/<PR repo>/issues/N)`). So a pull request can't
#     close issue N in both repositories at once; close the local one by
#     hand;
#   - so does `<owner>/<name>#N`, or its issue URL, when that name is an old
#     one of the pull request's repository, which GitHub still resolves after
#     a rename (below);
#   - a qualified reference to any other repository doesn't count.
#
# GitHub closed the issue on each of `Fixes GH-N`, `Fixes [#N](<this
# repository's issue URL>)` and `Fixes <owner>/<old name>#N`, measured on a
# scratch repository (#1044). Whether a markdown link closes the issue its
# text names or the one it points at isn't known, so a link whose text is a
# bare `#N` fails wherever it points. The other spellings that fail here (a
# link to this repository's issue with other text, `<...>`) weren't measured;
# they fail on the refusing side's rule, since refusing one too many costs a
# reworded line.
#
# GitHub keeps no list of a repository's old names, but it redirects an old
# name to the repository, and `gh api repos/<owner>/<name>` follows that
# redirect (measured: `gh api repos/mozilla/rust --jq .full_name` prints
# `rust-lang/rust`). So every other `<owner>/<name>` the body closes issue N in is
# looked up, and one that resolves to the pull request's repository fails.
# The limit is GitHub's own: an old name that another repository has since
# taken resolves to that repository, here and when GitHub reads the body
# alike.
#
# The lookup reads the network, so what it does when that goes wrong is
# chosen case by case:
#
#   - a 404, which is also what GitHub answers for a private repository the
#     token can't read, doesn't count: the token just read this pull request,
#     so it can read this repository, and an old name of this repository
#     redirects for it. A name it can't see isn't one of its old names;
#   - any other failure (a rate limit, a network error, a 5xx) and a lookup
#     still running when the lookups' time is up decide nothing, so the gate
#     neither passes nor refuses: exit 3, which no pr_creation edge routes,
#     so the state holds and the next tick looks again, rather than a
#     passing gate that never checked or a run stopped at done_blocked by a
#     blip. Fail-closed: the pull request can't move on. A failure that
#     doesn't clear (a 403 from an organization's SSO, say) ends when the
#     body stops closing issue N in that repository: its message names it;
#   - the lookups must end LOOKUP_SECS seconds (20) after the script
#     started, the pull request read included, inside koto's 30-second gate
#     default. Each is polled, so no stray timer outlives the script. The
#     read itself has no bound of its own; koto's kill covers it, as before;
#   - at most MAX_LOOKUPS repositories (5) are looked up. A body that closes
#     issue N in more fails the gate, so its size can't turn into calls.
#
# The tests set CHECK_CLOSING_KEYWORD_LOOKUP_SECS to shorten the time.
#
# The keywords are the gate's own: close, closes, closed, fix, fixes, fixed,
# resolve, resolves, resolved, in any case. GitHub's documentation also lets
# a colon follow the keyword (`Closes: #10`), so every form here takes one.
#
# The two sides read the space after the keyword differently, on purpose. A
# reference that passes needs whitespace after the optional colon, the forms
# GitHub documents. A reference that fails needs only a colon or whitespace
# (`Fixes:#42` counts), because missing one of those closes the wrong issue
# while refusing one too many costs a reworded line. Whether GitHub closes on
# `Fixes:#42`, with no space, isn't documented; refusing it is the safe side
# either way.
#
# The repository is matched literally: its `.` is escaped before it reaches
# the expression (`.github` must not match `xgithub`), the separator after the
# keyword holds no other character, so nothing can stand in front of the
# owner, and `#N` must not run into more digits (`#12` is not `#123`). The
# qualified form that passes also needs the keyword to start a word, so
# `prefixes owner/repo#N` doesn't count; the forms that fail don't, so
# `prefixes #N` fails too, erring toward refusing as above.
#
# Usage: check-closing-keyword.sh --issue <N> --repo <owner/repo>
#
# Exit codes, which the gate routes on:
#   0  the body closes the issue
#   1  it doesn't, it also closes issue N of the pull request's own
#      repository (for an issue elsewhere, under an old name too), it closes
#      issue N in more than MAX_LOOKUPS other repositories, or the pull
#      request or its repository couldn't be read. Fail-closed, like the
#      inline expression: pr_creation routes 1 to done_blocked. The reason
#      goes to stderr.
#   2  usage: a missing, unknown or malformed argument; no edge routes it,
#      so pr_creation holds
#   3  a repository lookup failed other than with a 404, or ran out of time;
#      no edge routes it either, so pr_creation holds. The reason goes to
#      stderr.
#
# Needs gh, authenticated, run from the repository the pull request is in.
# One gh call, plus one per other repository the body closes issue N in
# (usually none, at most MAX_LOOKUPS). Bash 3.2: no associative arrays, no
# mapfile.
set -u

usage() {
    echo "usage: check-closing-keyword.sh --issue <N> --repo <owner/repo>" >&2
    exit 2
}

refuse() {
    echo "check-closing-keyword: $1" >&2
    exit 1
}

undecided() {
    echo "check-closing-keyword: $1" >&2
    exit 3
}

MAX_LOOKUPS=5
LOOKUP_SECS=${CHECK_CLOSING_KEYWORD_LOOKUP_SECS:-20}
case "$LOOKUP_SECS" in
    ''|*[!0-9]*|0) usage ;;
esac

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

# https://<host>/<owner>/<repo>/pull/<n> -> <host> <owner>/<repo>
read -r PR_HOST PR_REPO \
    <<<"$(printf '%s\n' "${URL#*://}" | awk -F/ 'NF == 5 && $4 == "pull" { print $1 " " $2 "/" $3 }')"
# Both reach an expression below, so each must be the plain name it should be.
RE_HOST='^[A-Za-z0-9.-]+(:[0-9]+)?$'
[[ $PR_REPO =~ $RE_REPO ]] && [[ $PR_HOST =~ $RE_HOST ]] \
    || refuse "could not read the pull request's repository from [$URL]"

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# `.` is the one character a host or the repository pattern allows that means
# something in an extended expression. sed rather than ${REPO//./...}, whose
# backslash handling in the replacement differs between bash 3.2 and 5.2.
literal() { printf '%s' "$1" | sed 's/\./\\./g'; }

KW='(close[sd]?|fix(es|ed)?|resolve[sd]?)'
# After the keyword: what a passing reference needs, and the wider separator
# that makes a reference to the wrong issue fail (see the header).
SEP_PASS=':?[[:space:]]+'
SEP_FAIL='(:[[:space:]]*|[[:space:]]+)'
END="([^0-9]|\$)"
BARE="${KW}${SEP_PASS}#${ISSUE}${END}"
QUALIFIED="(^|[^[:alnum:]_])${KW}${SEP_PASS}$(literal "$REPO")#${ISSUE}${END}"
# For an issue elsewhere, the qualified reference may also be a markdown
# link's text. The same-repository case keeps QUALIFIED as it was.
QUALIFIED_LINK="(^|[^[:alnum:]_])${KW}${SEP_PASS}\\[?$(literal "$REPO")#${ISSUE}${END}"
# What may stand between the separator and a reference that fails: `[` or
# `<` in front of it, or a whole markdown link's text in front of its target.
OPEN='(\[|<|\[[^]]*\]\()?'
HOST_RE=$(literal "$PR_HOST")
# A reference to issue N that names a repository, given as the expression for
# that repository's name: `<name>#N` or its issue URL.
named() { printf '%s' "(${1}#|https?://(www\\.)?${HOST_RE}/${1}/issues/)"; }
# Issue N of the pull request's own repository, in each form that closes it.
# Deliberately wider than BARE and QUALIFIED, and not anchored to a word
# start: this side refuses, so it errs toward matching (see the header). Along
# the same line it also takes a `www.` host and leading zeros on N, spellings
# GitHub doesn't document either way, and `gh-N` in lower case.
PR_REPO_RE=$(literal "$PR_REPO")
OWN="${KW}${SEP_FAIL}${OPEN}(#|gh-|$(named "$PR_REPO_RE"))0*${ISSUE}${END}"
# The same for a repository other than the pull request's, named by $1.
closes_in() { printf '%s' "${KW}${SEP_FAIL}${OPEN}$(named "$(literal "$1")")0*${ISSUE}${END}"; }
NAME_RE='[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+'

# A here-string rather than a pipe: grep -q stops at the first match, and a
# writer still filling the pipe would then fail.
has() { grep -qiE "$1" <<<"$BODY"; }
# The refusal also reads the body with its lines joined, so a keyword on one
# line and this repository's reference on the next still fails: grep reads a
# line at a time, and whether GitHub joins them isn't documented. The pass
# side keeps to single lines.
has_joined() { grep -qiE "$1" <<<"$(printf '%s' "$BODY" | tr '\n' ' ')"; }

if [ "$(lower "$REPO")" = "$(lower "$PR_REPO")" ]; then
    # The issue is in this repository after all: either form closes it.
    if has "$BARE" || has "$QUALIFIED"; then
        exit 0
    fi
    refuse "the body has no closing keyword for #$ISSUE: add Fixes #$ISSUE"
fi

if has_joined "$OWN"; then
    refuse "a closing reference to #$ISSUE, GH-$ISSUE, $PR_REPO#$ISSUE or its issue URL (a markdown link's text or target included) closes $PR_REPO#$ISSUE, not $REPO#$ISSUE: write Fixes $REPO#$ISSUE and drop the other one (if $PR_REPO#$ISSUE should close too, close it by hand)"
fi

# Every other repository the body names issue N in, one `owner/name` a line,
# each spelling once.
other_names() {
    {
        grep -oE "${NAME_RE}#0*${ISSUE}${END}" <<<"$BODY" | sed -E 's/#.*$//'
        grep -oiE "https?://(www\\.)?${HOST_RE}/${NAME_RE}/issues/0*${ISSUE}${END}" <<<"$BODY" \
            | sed -E -e 's|^[A-Za-z]+://[^/]+/||' -e 's|/issues/.*$||'
    } | sort -fu
}

# One lookup, given the seconds it may take: gh runs in the background and is
# polled, so nothing is left running when this returns. Prints gh's output
# and returns gh's status, or 124 when the time ran out.
lookup() {
    local out pid st end
    end=$((SECONDS + $2))
    out=$(mktemp) || return 125
    # </dev/null: the caller's loop reads the list of names on stdin.
    gh api --hostname "$PR_HOST" "repos/$1" --jq .full_name >"$out" 2>&1 </dev/null &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$SECONDS" -ge "$end" ]; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            rm -f "$out"
            return 124
        fi
        sleep 0.1
    done
    wait "$pid"
    st=$?
    cat "$out"
    rm -f "$out"
    return "$st"
}

# An old name of this repository still closes its issue N (see the header),
# so each name the body closes issue N in is looked up, unless it is
# ISSUE_REPO or this repository by its current name. The names are collected
# and counted first, so a body over the limit makes no call at all.
LOOKUP_NAMES=""
LOOKUPS=0
while read -r NAME; do
    [ -n "$NAME" ] || continue
    case "$(lower "$NAME")" in
        "$(lower "$REPO")"|"$(lower "$PR_REPO")") continue ;;
    esac
    # Not a repository GitHub could have, and `repos/../x` is another path.
    case "/$NAME/" in */./*|*/../*) continue ;; esac
    has_joined "$(closes_in "$NAME")" || continue
    LOOKUP_NAMES="$LOOKUP_NAMES$NAME$NL"
    LOOKUPS=$((LOOKUPS + 1))
    # Stop at the first name past the limit, so a long body costs no more.
    [ "$LOOKUPS" -le "$MAX_LOOKUPS" ] \
        || refuse "the body closes issue $ISSUE in more than $MAX_LOOKUPS repositories besides $REPO, the most this gate looks up to rule out an old name of $PR_REPO: keep Fixes $REPO#$ISSUE and drop the others"
done <<<"$(other_names)"

# SECONDS counts from the script's start, so the time the pull request read
# took is spent too.
DEADLINE=$LOOKUP_SECS
while read -r NAME; do
    [ -n "$NAME" ] || continue
    LEFT=$((DEADLINE - SECONDS))
    [ "$LEFT" -gt 0 ] \
        || undecided "ran out of the ${LOOKUP_SECS}s for looking up repositories before $NAME: tick again"
    FULL=$(lookup "$NAME" "$LEFT")
    case $? in
        0) ;;
        124) undecided "looking up $NAME, to rule out an old name of $PR_REPO, took longer than the ${LOOKUP_SECS}s it had: tick again" ;;
        *)
            case "$FULL" in *"(HTTP 404)"*) continue ;; esac
            undecided "could not check whether $NAME is an old name of $PR_REPO, which would make $NAME#$ISSUE close $PR_REPO#$ISSUE: $FULL (tick again once GitHub answers; if it keeps failing, drop the closing keyword in front of $NAME#$ISSUE)"
            ;;
    esac
    if [ "$(lower "$FULL")" = "$(lower "$PR_REPO")" ]; then
        refuse "$NAME is an old name of $PR_REPO, so a closing reference to $NAME#$ISSUE closes $PR_REPO#$ISSUE, not $REPO#$ISSUE: write Fixes $REPO#$ISSUE and drop the other one (if $PR_REPO#$ISSUE should close too, close it by hand)"
    fi
done <<<"$LOOKUP_NAMES"

has "$QUALIFIED_LINK" && exit 0
refuse "the body has no closing keyword for $REPO#$ISSUE: add Fixes $REPO#$ISSUE"
