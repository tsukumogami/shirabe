#!/usr/bin/env bash
# check-closing-keyword.sh -- does the pull request close an issue that lives
# in another repository? For a pull request that leaves its issue open, does
# it refer to the issue without closing it? And did this pass come out of an
# approved deferral?
# Part of the work-on skill
#
# pr_creation's closing_keyword gate runs this only when the run recorded
# ISSUE_REPO, the repository a cross-repository issue lives in. With
# ISSUE_REPO empty the gate keeps its own inline expression and never starts
# this script, so a same-repository run is checked exactly as it was before
# ISSUE_REPO existed.
#
# Three modes:
#
#   --issue N --repo R
#       Closing mode: does the pull request close issue N of R? Described
#       from here down to "Non-closing mode".
#   --issue N --non-closing [--repo R]
#       Non-closing mode, for a pull request that delivers part of its issue
#       or follows an approved deferral: it must refer to issue N without
#       closing it. Without --repo the issue is in the pull request's own
#       repository.
#   --approved-pass <log>
#       The log probe: did this pass reach pre_pr_evidence through an
#       approved deferral? Reads the run's koto state log and nothing else.
#
# GitHub closes an issue in another repository only through a qualified
# reference, `Fixes owner/repo#N`. A bare `Fixes #N` in this pull request
# names this repository's issue N, which is either missing or a different
# issue, and merging would close that one. So:
#
#   - `<keyword> <ISSUE_REPO>#N` passes, and for an issue elsewhere so does
#     a markdown link with that text pointing at that issue,
#     `<keyword> [<ISSUE_REPO>#N](https://<host>/<ISSUE_REPO>/issues/N)`.
#     The plain reference is read wherever it stands, inside a link's text,
#     a code span or a comment included, as it was before;
#   - when ISSUE_REPO is the pull request's own repository (read from the URL
#     `gh pr view` reports), a bare `<keyword> #N` passes too;
#   - when the issue is elsewhere, a closing reference to issue N of the pull
#     request's own repository fails the gate, even next to the qualified
#     one, because merging would still close that issue. The forms are the
#     ones measured to close: a bare `#N`, `<PR repo>#N` and
#     `https://<host>/<PR repo>/issues/N` (#1041), `GH-N`, and the markdown
#     link `[#N](https://<host>/<PR repo>/issues/N)`, whose text may be any of
#     the first three spellings (#1044). So a pull request can't close issue
#     N in both repositories at once; close the local one by hand;
#   - so does `<owner>/<name>#N`, its issue URL, or that link, when that
#     name is an old one of the pull request's repository, which GitHub
#     still resolves after a rename (below);
#   - a qualified reference to any other repository doesn't count.
#
# GitHub closed the issue on each of `Fixes GH-N`, `Fixes [#N](<this
# repository's issue URL>)` and `Fixes <owner>/<old name>#N`, measured on a
# scratch repository (#1044). A refusal blocks a pull request, so only forms
# measured to close are refused. Other spellings GitHub renders as this
# repository's issue (owner shorthand `<owner>#N`, issue paths without a
# scheme or host, a link with other text or no keyword, emphasis around the
# reference) aren't known to close and pass; #1065 measures them. Code
# blocks and HTML aren't read specially, as before.
#
# GitHub keeps no list of a repository's old names, but it redirects an old
# name to the repository, and `gh api repos/<owner>/<name>` follows that
# redirect (measured: `gh api repos/mozilla/rust --jq .full_name` prints
# `rust-lang/rust`). So every other `<owner>/<name>` the body closes issue N
# in, in those forms, is looked up, and one that resolves to the pull
# request's repository fails.
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
# Non-closing mode (--non-closing) serves a pull request that delivers part
# of its issue, a planned split declared when the run started, or one that
# follows an approved deferral, whose criterion stays open on the issue
# (#1736, #1550). Issue N stays open, so:
#
#   - nothing in the pull request may close it. The body, the title and each
#     commit's message (its headline and body) are read with their lines
#     joined, with the wider separator and no word-start anchor, as closing
#     mode's refusal side reads the body. In a same-repository run (no
#     --repo, or --repo naming the pull request's own repository in any
#     case) every form measured to close the issue fails: a bare `#N`,
#     `GH-N`, `<PR repo>#N`, the issue URL and the markdown link to it.
#     Closing mode's inline expression doesn't take `GH-N` or the URL as
#     closing a same-repository issue, but GitHub closed it on each (#1044),
#     so here they are refused: a deliberate reversal. For an issue elsewhere
#     those same forms fail too, since they close issue N of the pull
#     request's repository, as in closing mode, and so do `<ISSUE_REPO>#N`,
#     its issue URL and a markdown link to it, which close the issue itself;
#   - every other `<owner>/<name>` the pull request closes or links to issue
#     N in is looked up, as in closing mode, and one that resolves to the
#     issue's repository or the pull request's fails. The names come from the
#     body, the title and the commits together, each spelling once, under the
#     one MAX_LOOKUPS cap and the one LOOKUP_SECS deadline;
#   - the body must refer to the issue with `Ref`, `Refs` or `Part of`, in
#     any case, the word starting a word, then an optional colon and
#     whitespace: `<word> #N` or `<word> <PR repo>#N` in a same-repository
#     run, `<word> <ISSUE_REPO>#N` or
#     `<word> [<ISSUE_REPO>#N](https://<host>/<ISSUE_REPO>/issues/N)` for an
#     issue elsewhere, where a bare `#N` names the pull request's own
#     repository's issue. These are closing mode's pass shapes with the word
#     swapped, read a line at a time, and `#N` must not run into more digits.
#     A reference only in the title or a commit doesn't count. `See #N`, a
#     bare `#N` or an issue URL doesn't either, though none is refused;
#   - closing keywords for other issues pass, as in closing mode.
#
# The pull request is read once, `gh pr view --json url,title,body,commits`,
# and parsed with jq. Every local finding is reported together: each closing
# form, quoting only the phrase that matched and naming where it stands
# (`body`, `title` or `commit <short SHA>`), and a missing reference, with the
# line to write instead. Then the script exits 1 without any lookup; the
# lookups run only when the local checks found nothing. The script isn't told
# why the run leaves its issue open, so its message names both reasons.
#
# The log probe (--approved-pass <log>) reads the run's state log and makes
# no gh call. The pass is approved when the last `transitioned` or
# `directed_transition` event into pre_pr_evidence is a `transitioned` event
# from deferral_approval, the engine's own record of the approval, and no
# event after it in the file of type `transitioned`, `directed_transition` or
# `rewound` goes to finalization or deferral_approval: a recount that went
# back through finalization drops the approval. A directed arrival never
# counts, and a `rewound` event is never an arrival. Lines with no `type`,
# the log's header among them, are skipped. Every line is parsed in one jq
# run, so a single line that isn't JSON fails the whole read and nothing is
# half-decided.
#
# Usage: check-closing-keyword.sh --issue <N> --repo <owner/repo>
#        check-closing-keyword.sh --issue <N> --non-closing [--repo <owner/repo>]
#        check-closing-keyword.sh --approved-pass <state log>
#
# Exit codes. The first two modes' are the gate's, which it routes on:
#   --issue N --repo R
#     0  the body closes the issue
#     1  it doesn't, it also closes issue N of the pull request's own
#        repository (for an issue elsewhere, under an old name too), it
#        closes issue N in more than MAX_LOOKUPS other repositories, or the
#        pull request or its repository couldn't be read. Fail-closed, like
#        the inline expression: pr_creation routes 1 to done_blocked. The
#        reason goes to stderr.
#     2  usage: a missing, unknown or malformed argument; no edge routes it,
#        so pr_creation holds
#     3  a repository lookup failed other than with a 404, or ran out of
#        time; no edge routes it either, so pr_creation holds. The reason
#        goes to stderr.
#   --issue N --non-closing [--repo R]
#     0  the body refers to the issue and nothing in the pull request closes
#        it
#     1  a closing form of the issue in the body, the title or a commit, no
#        reference in the body, issue N closed or linked in more than
#        MAX_LOOKUPS other repositories, or the pull request or its
#        repository couldn't be read. Routed to done_blocked; every finding
#        goes to stderr.
#     2  usage, as above, or jq is missing; pr_creation holds
#     3  as above
#   --approved-pass <log>
#     The command that calls the probe maps these itself, so none of them
#     reaches the gate's routes, and 1 is an answer, not a refusal.
#     0  this pass came out of an approved deferral
#     1  it didn't: no file at the path, an empty file, or no qualifying
#        arrival
#     2  the file exists but can't be read, a line isn't JSON, jq is
#        missing, or usage
#
# Needs gh, authenticated, run from the repository the pull request is in,
# and jq for the non-closing mode and the log probe. One gh call, plus one
# per other repository the pull request closes issue N in (usually none, at
# most MAX_LOOKUPS); the log probe makes none. Bash 3.2: no associative
# arrays, no mapfile.
set -u

usage() {
    cat >&2 <<'EOF'
usage: check-closing-keyword.sh --issue <N> --repo <owner/repo>
       check-closing-keyword.sh --issue <N> --non-closing [--repo <owner/repo>]
       check-closing-keyword.sh --approved-pass <state log>

--issue N --repo R:                 exit 0 closes R#N, 1 refused, 2 usage, 3 a lookup failed.
--issue N --non-closing [--repo R]: exit 0 refers to N without closing it, 1 refused, 2 usage, 3 a lookup failed.
--approved-pass <log>:              exit 0 an approved deferral, 1 not, 2 an unreadable log or usage.
EOF
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
LOG=""
SEEN_ISSUE=0
SEEN_REPO=0
SEEN_LOG=0
NON_CLOSING=0
# `--non-closing` takes no value, so a word after it reads as an unknown
# argument.
while [ $# -gt 0 ]; do
    case "$1" in
        --issue|--repo|--approved-pass)
            [ $# -ge 2 ] || usage
            case "$1" in
                --issue) ISSUE="$2"; SEEN_ISSUE=1 ;;
                --repo) REPO="$2"; SEEN_REPO=1 ;;
                *) LOG="$2"; SEEN_LOG=1 ;;
            esac
            shift 2
            ;;
        --non-closing) NON_CLOSING=1; shift ;;
        *) usage ;;
    esac
done

need_jq() {
    command -v jq >/dev/null || {
        echo "check-closing-keyword: jq is not on PATH" >&2
        exit 2
    }
}

# The log probe's rule (see the header). Lines that aren't objects with a
# string `type` are skipped; `payload` is read only when it is an object.
# shellcheck disable=SC2016
APPROVED_PASS='
def dest: if (.payload | type) == "object" then .payload.to else null end;
def src: if (.payload | type) == "object" then .payload.from else null end;
def moved: .type == "transitioned" or .type == "directed_transition";
[inputs | select(type == "object" and (.type | type) == "string")] as $ev
| [range(0; $ev | length) | select($ev[.] | moved and dest == "pre_pr_evidence")] as $arrivals
| if ($arrivals | length) == 0 then "none"
  else $arrivals[-1] as $i
  | if ($ev[$i] | .type == "transitioned" and src == "deferral_approval")
       and ([$ev[$i + 1:][]
             | select((moved or .type == "rewound")
                      and (dest == "finalization" or dest == "deferral_approval"))]
            | length) == 0
    then "approved"
    else "not approved"
    end
  end
'

approved_pass() {
    need_jq
    # No log is an answer here, not an error: no approved pass.
    [ -e "$LOG" ] || exit 1
    [ -f "$LOG" ] && [ -r "$LOG" ] || {
        echo "check-closing-keyword: cannot read the state log [$LOG]" >&2
        exit 2
    }
    [ -s "$LOG" ] || exit 1
    local answer
    # Every line is read before anything is decided, so a line jq can't
    # parse fails the whole read.
    answer=$(jq -rn "$APPROVED_PASS" <"$LOG") || {
        echo "check-closing-keyword: cannot parse the state log [$LOG]" >&2
        exit 2
    }
    [ "$answer" = approved ] && exit 0
    exit 1
}

if [ "$SEEN_LOG" = 1 ]; then
    [ "$SEEN_ISSUE$SEEN_REPO$NON_CLOSING" = 000 ] || usage
    [ -n "$LOG" ] || usage
    approved_pass
fi

# Digits with no leading zero, as the issue number koto substituted.
case "$ISSUE" in
    ''|*[!0-9]*|0*) usage ;;
esac
# The template variable's own pattern, checked again here because the value
# reaches a regular expression. [[ =~ ]] anchors on the whole string, so a
# value with a newline in it can't pass on its first line alone. Only
# non-closing mode may leave the repository out: the issue is then in the
# pull request's own repository.
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
if [ "$NON_CLOSING" = 0 ] || [ -n "$REPO" ]; then
    [[ $REPO =~ $RE_REPO ]] || usage
fi

NL='
'
TAB=$(printf '\t')
if [ "$NON_CLOSING" = 1 ]; then
    need_jq
    # One read, so the body, the title and the commits come from the same
    # snapshot. gh's own error, and jq's, go to stderr ahead of the refusal.
    OUT=$(gh pr view --json url,title,body,commits) \
        || refuse "could not read the pull request with gh pr view"
    URL=$(jq -r '.url | strings' <<<"$OUT") \
        || refuse "could not parse what gh pr view answered"
    TITLE=$(jq -r '(.title // "") | strings' <<<"$OUT") \
        || refuse "could not parse the pull request's title"
    BODY=$(jq -r '(.body // "") | strings' <<<"$OUT") \
        || refuse "could not parse the pull request's body"
    # One line a commit: its short SHA, a tab, then its headline and body
    # with their lines joined. Only hex digits are kept from the SHA, so the
    # tab can only be the separator.
    # shellcheck disable=SC2016
    COMMITS=$(jq -r '(.commits // [])[]
        | ((.oid // "") | tostring | gsub("[^0-9A-Fa-f]"; "") | .[0:7])
          + "\t"
          + (((.messageHeadline // "") + "\n" + (.messageBody // "")) | gsub("\n"; " "))' <<<"$OUT") \
        || refuse "could not parse the pull request's commits"
else
    # One read: the URL on the first line, the body after it. An empty body
    # leaves the URL alone, with no newline to split on. gh's own error goes
    # to stderr ahead of the refusal, which is where the gate's reader finds
    # it.
    OUT=$(gh pr view --json url,body --jq '.url, .body') \
        || refuse "could not read the pull request with gh pr view"
    URL=${OUT%%"$NL"*}
    case "$OUT" in
        *"$NL"*) BODY=${OUT#*"$NL"} ;;
        *)       BODY="" ;;
    esac
fi

# https://<host>/<owner>/<repo>/pull/<n> -> <host> <owner>/<repo>
read -r PR_HOST PR_REPO \
    <<<"$(printf '%s\n' "${URL#*://}" | awk -F/ 'NF == 5 && $4 == "pull" { print $1 " " $2 "/" $3 }')"
# Both reach an expression below, so each must be the plain name it should be.
RE_HOST='^[A-Za-z0-9.-]+(:[0-9]+)?$'
[[ $PR_REPO =~ $RE_REPO ]] && [[ $PR_HOST =~ $RE_HOST ]] \
    || refuse "could not read the pull request's repository from [$URL]"
# Non-closing mode with no --repo: the issue is in this repository.
[ -n "$REPO" ] || REPO=$PR_REPO

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
HOST_RE=$(literal "$PR_HOST")
# The passing shapes are built for a word list, $1: the closing keywords
# here, and non-closing mode's reference words below.
qualified() {
    printf '%s' "(^|[^[:alnum:]_])${1}${SEP_PASS}$(literal "$REPO")#${ISSUE}${END}"
}
qualified_link() {
    printf '%s' "(^|[^[:alnum:]_])${1}${SEP_PASS}\\[$(literal "$REPO")#${ISSUE}\\]\\(https?://(www\\.)?${HOST_RE}/$(literal "$REPO")/issues/${ISSUE}\\)"
}
BARE="${KW}${SEP_PASS}#${ISSUE}${END}"
QUALIFIED=$(qualified "$KW")
# For an issue elsewhere, the qualified reference may also be a markdown
# link's text, but only when the link points at that same issue: whether
# GitHub closes the issue a link's text names or the one it points at isn't
# known, and with both naming ISSUE_REPO#N either reading closes it. The
# same-repository case keeps QUALIFIED as it was.
QUALIFIED_LINK=$(qualified_link "$KW")
# Issue N's URL in the repository whose name expression is $1, up to N.
issue_url() { printf '%s' "https?://(www\\.)?${HOST_RE}/${1}/issues/"; }
# Issue N of the pull request's own repository, in each form measured to
# close it (see the header). Deliberately wider than BARE and QUALIFIED, and
# not anchored to a word start: this side refuses, so it errs toward matching.
# Along the same line it also takes a `www.` host and leading zeros on N, as
# #1041 did, and `gh-N` in lower case.
PR_REPO_RE=$(literal "$PR_REPO")
OWN="${KW}${SEP_FAIL}(#|gh-|${PR_REPO_RE}#|$(issue_url "$PR_REPO_RE"))0*${ISSUE}${END}"
# The markdown link GitHub closed it on: a reference to it as the link's
# text and its URL as the target.
OWN_LINK="${KW}${SEP_FAIL}\\[(#|gh-|${PR_REPO_RE}#|$(issue_url "$PR_REPO_RE"))0*${ISSUE}\\]\\($(issue_url "$PR_REPO_RE")0*${ISSUE}${END}"
# An owner is letters, digits, `-` and `_` (an enterprise's managed users),
# starting with a letter or digit; a repository may also hold `.`.
NAME_RE='[A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9_.-]+'

# The body with its lines joined, made once.
JOINED=$(printf '%s' "$BODY" | tr '\n' ' ')
# A here-string rather than a pipe: grep -q stops at the first match, and a
# writer still filling the pipe would then fail.
has() { grep -qiE "$1" <<<"$BODY"; }
# The refusal also reads the body with its lines joined, so a keyword on one
# line and this repository's reference on the next still fails: grep reads a
# line at a time, and whether GitHub joins them isn't documented. The pass
# side keeps to single lines.
has_joined() { grep -qiE "$1" <<<"$JOINED"; }

# Every other repository the text $1 closes issue N in, one `owner/name` a line,
# each spelling once. $1 is a text with its lines joined: the body, or in
# non-closing mode also the title or a commit's message. One pass over it
# finds each closing reference in the forms above (the link's text and target
# both name one); the names inside it are then cut out, all in one pipeline
# whatever the text's length, so only what follows a keyword costs anything.
#
# grep -o's matches don't overlap, and END takes the character after N, which
# can be where the next reference starts (`#42<https://...`). So the pass
# reads the joined text with a space put after every N first, for END to take
# instead. The name is cut out lower-cased (GitHub's names are), with the
# scheme and host dropped first: the two path segments in front of
# `/issues/` or `#`, whatever the case of `/issues/` or the repository's name.
REF_NAMED="(#|gh-|${NAME_RE}#|$(issue_url "$NAME_RE"))0*${ISSUE}"
# The space the pass puts after N may stand before the link text's `]`.
NAMED="${KW}${SEP_FAIL}(${NAME_RE}#|$(issue_url "$NAME_RE"))0*${ISSUE}${END}|${KW}${SEP_FAIL}\\[${REF_NAMED} ?\\]\\($(issue_url "$NAME_RE")0*${ISSUE}${END}"
NAME_REF="$(issue_url "$NAME_RE")0*${ISSUE}${END}|${NAME_RE}#0*${ISSUE}${END}"
HOST_LOWER_RE=$(literal "$(lower "$PR_HOST")")
other_names() {
    local spaced
    spaced=$(sed -E "s/(#|\\/[Ii][Ss][Ss][Uu][Ee][Ss]\\/)(0*${ISSUE})([^0-9])/\\1\\2 \\3/g" <<<"$1 ")
    # A repository named `.` or `..` isn't one GitHub could have, and
    # `repos/../x` is another path: dropped here, so the loop below reads at
    # most a handful of names whatever the body holds.
    grep -oiE "$NAMED" <<<"$spaced" | grep -oiE "$NAME_REF" | tr '[:upper:]' '[:lower:]' \
        | sed -E -e 's|^[a-z]+://||' -e "s|^(www\\.)?${HOST_LOWER_RE}/||" -e 's|^([^/#]+/[^/#]+)[/#].*$|\1|' \
        | grep -vE '/\.\.?$' | sort -u
}

# One lookup, given the seconds it may take: gh runs in the background and is
# polled, so nothing is left running when this returns. Prints gh's answer,
# and after a failure its error too, and returns gh's status, or 124 when
# the time ran out. The error is kept apart from the answer, so a warning gh
# writes on a lookup that worked can't change the name it answered.
lookup() {
    local out err pid st end
    end=$((SECONDS + $2))
    out=$(mktemp) || return 125
    err=$(mktemp) || { rm -f "$out"; return 125; }
    # </dev/null: the caller's loop reads the list of names on stdin.
    gh api --hostname "$PR_HOST" "repos/$1" --jq .full_name >"$out" 2>"$err" </dev/null &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$SECONDS" -ge "$end" ]; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            rm -f "$out" "$err"
            return 124
        fi
        sleep 0.1
    done
    wait "$pid"
    st=$?
    if [ "$st" -eq 0 ]; then cat "$out"; else cat "$out" "$err"; fi
    rm -f "$out" "$err"
    return "$st"
}

# --- non-closing mode (see the header) ---------------------------------------
if [ "$NON_CLOSING" = 1 ]; then
    REPO_RE=$(literal "$REPO")
    # Every form measured to close issue N of this repository.
    CLOSES_OWN="${OWN}|${OWN_LINK}"
    REF='(ref|refs|part[[:space:]]+of)'
    if [ "$(lower "$REPO")" = "$(lower "$PR_REPO")" ]; then
        SAME_REPO=1
        ISSUE_REF="#$ISSUE"
        CLOSES="$CLOSES_OWN"
        # The pass shapes with the reference words: bare or qualified.
        REFERS="(^|[^[:alnum:]_])${REF}${SEP_PASS}#${ISSUE}${END}|$(qualified "$REF")"
    else
        SAME_REPO=0
        ISSUE_REF="$REPO#$ISSUE"
        # Issue N of this repository still closes on merge, as in closing
        # mode, and the issue itself closes on its qualified reference, its
        # URL, and a markdown link to it, the one closing mode accepts
        # included.
        CLOSES="${CLOSES_OWN}|${KW}${SEP_FAIL}(${REPO_RE}#|$(issue_url "$REPO_RE"))0*${ISSUE}${END}|${KW}${SEP_FAIL}\\[(#|gh-|${REPO_RE}#|$(issue_url "$REPO_RE"))0*${ISSUE}\\]\\($(issue_url "$REPO_RE")0*${ISSUE}${END}"
        # A bare `#N` names this repository's issue, so it isn't the
        # reference: qualified or linked only.
        REFERS="$(qualified "$REF")|$(qualified_link "$REF")"
    fi
    # The repositories an old name must not resolve to, for the messages.
    if [ "$SAME_REPO" = 1 ]; then OWNERS="$PR_REPO"; else OWNERS="$REPO or $PR_REPO"; fi
    WRITE="Part of $ISSUE_REF"
    WHY="this run leaves $ISSUE_REF open, because it declared a partial delivery or came from an approved deferral, so its pull request must refer to the issue without closing it: write $WRITE in the body, not Fixes $ISSUE_REF"

    FINDINGS=""
    finding() { FINDINGS="$FINDINGS$1$NL"; }
    # Every finding, the reason first, then exit 1.
    refuse_all() {
        {
            echo "check-closing-keyword: $WHY"
            printf '%s' "$FINDINGS" | sed 's/^/check-closing-keyword: /'
        } >&2
        exit 1
    }
    instead() {
        case "$1" in
            body) echo "write $WRITE in its place" ;;
            title) echo "take it out of the title and write $WRITE in the body" ;;
            *) echo "reword the commit so it closes nothing, and write $WRITE in the body" ;;
        esac
    }
    # Each phrase in $2 that closes an issue this run must leave alone,
    # quoting only the phrase. END's character is dropped from the quote,
    # unless it is the `)` that ends a link.
    check_source() {
        local phrase target
        case "$2" in *"$ISSUE"*) ;; *) return 0 ;; esac
        grep -qiE "$CLOSES" <<<"$2" || return 0
        while IFS= read -r phrase; do
            [ -n "$phrase" ] || continue
            target="$ISSUE_REF"
            if [ "$SAME_REPO" = 0 ] && grep -qiE "$CLOSES_OWN" <<<"$phrase "; then
                target="$PR_REPO#$ISSUE"
            fi
            finding "$1: \"$phrase\" closes $target on merge: $(instead "$1")"
        done <<<"$(grep -oiE "$CLOSES" <<<"$2" \
            | sed -E -e '/\]\(/!s/[^0-9]$//' -e '/\]\(/s/[^0-9)]$//' \
            | awk '!seen[tolower($0)]++')"
    }
    # The names each source closes or links to issue N under, as
    # `<name><tab><source>` lines, for the lookups below.
    NAMED_IN=""
    add_names() {
        local name
        case "$2" in *"$ISSUE"*) ;; *) return 0 ;; esac
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            NAMED_IN="$NAMED_IN$name$TAB$1$NL"
        done <<<"$(other_names "$2")"
    }
    sources_of() {
        printf '%s' "$NAMED_IN" | awk -F'\t' -v n="$1" \
            '$1 == n && !seen[$2]++ { out = out (out == "" ? "" : ", ") $2 } END { print out }'
    }

    check_source body "$JOINED"
    add_names body "$JOINED"
    TITLE_JOINED=$(printf '%s' "$TITLE" | tr '\n' ' ')
    check_source title "$TITLE_JOINED"
    add_names title "$TITLE_JOINED"
    while IFS= read -r LINE; do
        [ -n "$LINE" ] || continue
        check_source "commit ${LINE%%"$TAB"*}" "${LINE#*"$TAB"}"
        add_names "commit ${LINE%%"$TAB"*}" "${LINE#*"$TAB"}"
    done <<<"$COMMITS"

    # The reference: in the body only, a line at a time.
    if ! has "$REFERS"; then
        if [ "$SAME_REPO" = 1 ]; then
            finding "body: no Ref, Refs or Part of reference to $ISSUE_REF: add the line $WRITE"
        else
            finding "body: no Ref, Refs or Part of reference to $ISSUE_REF (a bare #$ISSUE names $PR_REPO#$ISSUE): add the line $WRITE"
        fi
    fi
    # Every local finding is reported before any lookup.
    [ -z "$FINDINGS" ] || refuse_all

    # The other names, pooled from every source, each spelling once, under
    # the one cap. Counted first, so a pull request over it makes no call.
    LOOKUP_NAMES=""
    LOOKUPS=0
    while read -r NAME; do
        [ -n "$NAME" ] || continue
        case "$(lower "$NAME")" in
            "$(lower "$REPO")"|"$(lower "$PR_REPO")") continue ;;
        esac
        LOOKUP_NAMES="$LOOKUP_NAMES$NAME$NL"
        LOOKUPS=$((LOOKUPS + 1))
        if [ "$LOOKUPS" -gt "$MAX_LOOKUPS" ]; then
            finding "the body, title and commits together close or link to issue $ISSUE in more than $MAX_LOOKUPS other repositories, the most this gate looks up to rule out an old name of $OWNERS: turn them into plain text"
            refuse_all
        fi
    done <<<"$(printf '%s' "$NAMED_IN" | cut -f1 | sort -u)"

    # SECONDS counts from the script's start, so the pull request read and
    # the local checks spend the time too.
    while read -r NAME; do
        [ -n "$NAME" ] || continue
        LEFT=$((LOOKUP_SECS - SECONDS))
        [ "$LEFT" -gt 0 ] \
            || undecided "ran out of the ${LOOKUP_SECS}s for looking up repositories before $NAME: tick again"
        FULL=$(lookup "$NAME" "$LEFT")
        case $? in
            0) ;;
            124) undecided "looking up $NAME, to rule out an old name of $OWNERS, took longer than the ${LOOKUP_SECS}s it had: tick again" ;;
            *)
                case "$FULL" in *"(HTTP 404)"*) continue ;; esac
                undecided "could not check whether $NAME is an old name of $OWNERS, which would make $NAME#$ISSUE ($(sources_of "$NAME")) close an issue: $FULL (tick again once GitHub answers; if it keeps failing, turn the closing reference or the link to $NAME#$ISSUE into plain text)"
                ;;
        esac
        FULL=${FULL%%"$NL"*}
        case "$(lower "$FULL")" in
            "$(lower "$REPO")"|"$(lower "$PR_REPO")")
                finding "$(sources_of "$NAME"): $NAME is an old name of $FULL, so a closing reference or a link to $NAME#$ISSUE closes $FULL#$ISSUE on merge: turn it into plain text"
                refuse_all
                ;;
        esac
    done <<<"$LOOKUP_NAMES"
    exit 0
fi

# --- closing mode -------------------------------------------------------------
if [ "$(lower "$REPO")" = "$(lower "$PR_REPO")" ]; then
    # The issue is in this repository after all: either form closes it.
    if has "$BARE" || has "$QUALIFIED"; then
        exit 0
    fi
    refuse "the body has no closing keyword for #$ISSUE: add Fixes #$ISSUE"
fi

if has_joined "$OWN" || has_joined "$OWN_LINK"; then
    refuse "a closing reference to #$ISSUE, GH-$ISSUE, $PR_REPO#$ISSUE or its issue URL (a markdown link to it included) closes $PR_REPO#$ISSUE, not $REPO#$ISSUE: write Fixes $REPO#$ISSUE and drop the other one (if $PR_REPO#$ISSUE should close too, close it by hand)"
fi
# Without the right reference the answer is no whatever the lookups below
# would say, so it is given before any of them.
has "$QUALIFIED" || has "$QUALIFIED_LINK" \
    || refuse "the body has no closing keyword for $REPO#$ISSUE: add Fixes $REPO#$ISSUE"

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
    LOOKUP_NAMES="$LOOKUP_NAMES$NAME$NL"
    LOOKUPS=$((LOOKUPS + 1))
    # Stop at the first name past the limit, so a long body costs no more.
    [ "$LOOKUPS" -le "$MAX_LOOKUPS" ] \
        || refuse "the body closes or links to issue $ISSUE in more than $MAX_LOOKUPS repositories besides $REPO, the most this gate looks up to rule out an old name of $PR_REPO: keep Fixes $REPO#$ISSUE and turn the others into plain text"
done <<<"$(other_names "$JOINED")"

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
            undecided "could not check whether $NAME is an old name of $PR_REPO, which would make $NAME#$ISSUE close $PR_REPO#$ISSUE: $FULL (tick again once GitHub answers; if it keeps failing, turn the closing reference or the link to $NAME#$ISSUE into plain text and close that issue by hand)"
            ;;
    esac
    FULL=${FULL%%"$NL"*}
    if [ "$(lower "$FULL")" = "$(lower "$PR_REPO")" ]; then
        refuse "$NAME is an old name of $PR_REPO, so a closing reference or a link to $NAME#$ISSUE closes $PR_REPO#$ISSUE, not $REPO#$ISSUE: write Fixes $REPO#$ISSUE and drop the other one (if $PR_REPO#$ISSUE should close too, close it by hand)"
    fi
done <<<"$LOOKUP_NAMES"

exit 0
