#!/usr/bin/env bash
# record-append.sh -- append an entry to the coordinator record, or list the
# entries. Agent-run; the one way an entry is written
# (docs/designs/DESIGN-coordinate-record-container.md, Decision 2).
#
# The record's body holds its state and is rewritten whole by the write core;
# its entries, the dated account of what happened, are comments on the same
# container (the issue at roadmap scope, the rotation's pull request at
# discipline scope). An entry is never edited by this script and never grows,
# so the record needs no archive.
#
# Usage:
#   record-append.sh --session S --text-file F [--kind K]
#   record-append.sh --scope roadmap|discipline --name N --repo O/R --ref N
#                    --text-file F [--kind K]
#   record-append.sh (--session S | --scope ... --ref N) --list
#
# The session gives the scope, name, host and record number (coord-log.sh
# vars and run-facts). The addressed form names them instead, for a writer
# that isn't a run: a migration, or an entry written after a run ended. It
# needs no session check, because an entry changes nothing a check reads.
#
# Before posting, a fresh read must show the target open and carrying the
# scope's declaration line (exit 10). The entry is stamped from the host clock
# in UTC to the second and posted as one comment:
#
#   <!-- coordinator-record-entry v1 kind=<kind> -->
#   **<YYYY-MM-DDTHH:MM:SSZ>** (host clock) <kind>
#
#   <the text>
#
# K is entry (the default), or one of the kinds the stored set's writer
# appends: run, told, pause, go-ahead, approval, answer, end, work,
# roadmap-status. The text may not be empty, may hold no control character
# but a line break or a tab, and the whole comment may not exceed 60,000 bytes
# (exit 65). On a public host the text may not name a private or unreadable
# repository (as owner/repo#n or a github.com link), a home-directory path or
# a token-shaped string (exit 65), the checks the Decisions section's text
# columns get. `@` is written as `&#64;`, so an entry never mentions anyone.
#
# --list prints the entries as a JSON array, oldest first: {id, created,
# stamp, author, kind, text, edited}. Only comments carrying the marker whose
# author has write access to the host count, since anyone can comment on a
# public repository; `edited` is true when GitHub says the comment changed
# after it was posted. The text comes back as written, `@` decoded.
#
# Exit codes: 0 posted (prints the comment's URL) or listed; 2 a read failed;
# 10 refused (not an open record of this scope, or no found record); 11 the
# post failed; 64 usage; 65 the entry was refused (the reason on stderr).
#
# GitHub calls:
#   reads:  gh issue view N --repo R --json state,body,url
#           gh pr view N --repo R --json state,body,url
#           gh api --method GET repos/<repo> --jq .private   (the host, then each repository the text names)
#           gh api --method GET repos/R/issues/N/comments?per_page=100 --paginate
#           gh api --method GET repos/R/collaborators/<login>/permission --jq .permission
#   writes: gh api --method POST repos/R/issues/N/comments --input <json>
set -uo pipefail

PROG=record-append
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= TEXTFILE= KIND=entry
MODE=append

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --text-file) [ $# -ge 2 ] || usage; TEXTFILE=$2; shift 2 ;;
        --kind) [ $# -ge 2 ] || usage; KIND=$2; shift 2 ;;
        --list) MODE=list; shift ;;
        *) usage ;;
    esac
done
ENTRY_KINDS=" entry run told pause go-ahead approval answer end work roadmap-status "
case "$MODE" in
    append)
        [ -r "$TEXTFILE" ] || usage
        case "$ENTRY_KINDS" in *" $KIND "*) ;; *) echo "$PROG: --kind is not one of:$ENTRY_KINDS" >&2; exit 64 ;; esac
        ;;
    list) [ -z "$TEXTFILE" ] || usage ;;
esac
# ENTRY_MARKER_PREFIX is the entry's first line up to its kind; the one
# definition the writer and the reader share.
ENTRY_MARKER_PREFIX='<!-- coordinator-record-entry v1 kind='
ENTRY_BUDGET=60000

. "$HERE/record-common.sh"
lib_facts
if [ "$OVERRIDE" = 1 ]; then
    [[ $REF =~ $RE_NUM ]] || { echo "$PROG: the addressed form needs --ref N" >&2; exit 64; }
else
    [ -z "$REF" ] || usage
    FACTS=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION")
    case $? in
        0) REF=$(printf '%s' "$FACTS" | jq -r '.ref') ;;
        1) echo "$PROG: refused: the run has no found record" >&2; exit 10 ;;
        *) lib_die2 "cannot read the run's facts" ;;
    esac
    [[ $REF =~ $RE_NUM ]] || lib_die2 "the run's record number is not a number"
fi

WD=$(mktemp -d "${TMPDIR:-/tmp}/record-append.XXXXXX")
trap 'rm -rf "$WD"' EXIT

# The target, re-read now: open, and this scope's record.
if [ "$SCOPE" = roadmap ]; then
    gh issue view "$REF" --repo "$REPO" --json state,body,url > "$WD/target.json" 2> "$WD/r.err" < /dev/null || lib_die2 "cannot read issue #$REF: $(lib_scrub < "$WD/r.err")"
else
    gh pr view "$REF" --repo "$REPO" --json state,body,url > "$WD/target.json" 2> "$WD/r.err" < /dev/null || lib_die2 "cannot read pull request #$REF: $(lib_scrub < "$WD/r.err")"
fi
jq -r '.body // ""' "$WD/target.json" | tr -d '\r' > "$WD/live.md" || lib_die2 "the target read is not JSON"
STATE=$(jq -r '.state' "$WD/target.json")
grep -xF -- "$DECL" "$WD/live.md" > /dev/null || { echo "$PROG: refused: #$REF does not carry this scope's declaration line" >&2; exit 10; }

if [ "$MODE" = list ]; then
    gh api --method GET "repos/$REPO/issues/$REF/comments?per_page=100" --paginate \
        --jq '.[] | {id, created_at, updated_at, user: (.user.login // ""), body: (.body // "")}' \
        > "$WD/comments.jsonl" 2> "$WD/c.err" < /dev/null || lib_die2 "cannot read #$REF's comments: $(lib_scrub < "$WD/c.err")"
    jq -c --arg m "$ENTRY_MARKER_PREFIX" 'select(.body | gsub("\r"; "") | startswith($m))' "$WD/comments.jsonl" > "$WD/marked.jsonl" \
        || lib_die2 "the comments read is not JSON"
    # Write access per author, read once each; a failed read lists nothing.
    : > "$WD/writers"
    for login in $(jq -r '.user' "$WD/marked.jsonl" | sort -u); do
        [[ $login =~ $RE_LOGIN ]] || continue
        perm=$(gh api --method GET "repos/$REPO/collaborators/$login/permission" --jq .permission < /dev/null 2> "$WD/p.err") \
            || lib_die2 "cannot read $login's access to $REPO: $(lib_scrub < "$WD/p.err")"
        case "$perm" in admin|maintain|write) printf '%s\n' "$login" >> "$WD/writers" ;; esac
    done
    jq -s -c --rawfile w "$WD/writers" --arg m "$ENTRY_MARKER_PREFIX" '
        ($w | split("\n") | map(select(. != ""))) as $writers
        | map(select(.user as $u | $writers | index($u)))
        | map((.body | gsub("\r"; "")) as $b
            | ($b | split("\n")) as $l
            | {id, created: .created_at,
               stamp: ($l[1] // "" | capture("^\\*\\*(?<s>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)\\*\\*").s // ""),
               author: .user,
               kind: ($l[0] | ltrimstr($m) | sub(" -->$"; "")),
               text: ($l[3:] | join("\n") | gsub("&#64;"; "@")),
               edited: (.updated_at != .created_at)})' "$WD/marked.jsonl" || lib_die2 "jq failed"
    exit 0
fi

[ "$STATE" = OPEN ] || { echo "$PROG: refused: #$REF is $STATE, not an open record" >&2; exit 10; }

# The text, as the coordinator wrote it, line endings normalised.
tr -d '\r' < "$TEXTFILE" > "$WD/text"
TEXT=$(cat "$WD/text"; printf x); TEXT=${TEXT%x}
# Leading and trailing blank lines carry nothing.
TEXT=$(printf '%s' "$TEXT" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
[ -n "$(printf '%s' "$TEXT" | tr -d ' \t\n')" ] || { echo "$PROG: refused: the entry is empty" >&2; exit 65; }
if printf '%s' "$TEXT" | LC_ALL=C grep -q '[[:cntrl:]]' 2>/dev/null \
    && printf '%s' "$TEXT" | LC_ALL=C tr -d '\n\t' | LC_ALL=C grep -q '[[:cntrl:]]'; then
    echo "$PROG: refused: the entry holds a control character" >&2; exit 65
fi

# On a public host, the repositories the text names unambiguously (a
# github.com link, owner/repo#n), each read for visibility; the codec decides
# whether the text names one that isn't public, as it does for the Decisions
# columns.
PRIVATE=
HOST_PRIVATE=$(gh api --method GET "repos/$REPO" --jq .private 2> /dev/null < /dev/null) || lib_die2 "cannot read $REPO's visibility"
if [ "$HOST_PRIVATE" = false ]; then
    printf '%s' "$TEXT" | jq -R -s -r -L "$HERE" 'include "record-codec"; text_named_repos | .[]' > "$WD/named" || lib_die2 "jq failed"
    while IFS= read -r r; do
        [ "$r" = "$REPO" ] && continue
        [[ $r =~ $RE_REPO ]] || continue
        if ! P=$(gh api --method GET "repos/$r" --jq .private 2> "$WD/v.err" < /dev/null); then
            grep -q 'HTTP 404' "$WD/v.err" || lib_die2 "cannot read $r's visibility"
            P=unreadable
        fi
        [ "$P" = false ] || PRIVATE="$PRIVATE${PRIVATE:+,}$r"
    done < "$WD/named"
    printf '%s' "$TEXT" | jq -R -s -r -L "$HERE" --arg p "$PRIVATE" \
        'include "record-codec"; text_problem($p | split(",") | map(select(. != ""))) // empty' > "$WD/problem" \
        || lib_die2 "jq failed"
    if [ -s "$WD/problem" ]; then
        echo "$PROG: refused: the entry $(cat "$WD/problem")" >&2; exit 65
    fi
fi

STAMP=$(lib_now)
{
    printf '%s%s -->\n' "$ENTRY_MARKER_PREFIX" "$KIND"
    printf '**%s** (host clock) %s\n\n' "$STAMP" "$KIND"
    printf '%s\n' "$TEXT" | sed 's/@/\&#64;/g'
} > "$WD/comment.md"
SIZE=$(wc -c < "$WD/comment.md" | tr -d ' ')
if [ "$SIZE" -gt "$ENTRY_BUDGET" ]; then
    echo "$PROG: refused: the entry is $SIZE bytes, over the $ENTRY_BUDGET-byte budget; split it" >&2; exit 65
fi
jq -n --rawfile b "$WD/comment.md" '{body: $b}' > "$WD/post.json" || lib_die2 "jq failed"
gh api --method POST "repos/$REPO/issues/$REF/comments" --input "$WD/post.json" --jq .html_url > "$WD/url" 2> "$WD/w.err" < /dev/null \
    || { echo "$PROG: the post failed: $(lib_scrub < "$WD/w.err")" >&2; exit 11; }
cat "$WD/url"
