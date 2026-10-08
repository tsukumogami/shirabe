#!/usr/bin/env bash
# record-append.sh -- append an entry to the coordinator record, or list the
# entries. Agent-run; the one way an entry is written
# (docs/designs/current/DESIGN-coordinate-record-container.md, Decision 2).
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
# scope's declaration line (exit 10). --list needs only the declaration line,
# so a closed record's entries stay readable after its run ended. The entry is stamped from the host clock
# in UTC to the second and posted as one comment:
#
#   <!-- coordinator-record-entry v1 kind=<kind> -->
#   **<YYYY-MM-DDTHH:MM:SSZ>** (host clock) <kind>
#
#   <the text>
#
# K is entry (the default), or one of the kinds the record's other writers
# append for what they change (the design's Decisions 3 and 4): run, told,
# pause, go-ahead, approval, answer, assignment, end, work, roadmap-status. The text may not be empty, may hold no control character
# but a line break or a tab, and the whole comment may not exceed 60,000 bytes
# (exit 65). On a public host the text may not name a private or unreadable
# repository (as owner/repo#n or a github.com link), a home-directory path or
# a token-shaped string (exit 65), the checks the Decisions section's text
# columns get. `@` is written as `&#64;`, so an entry never mentions anyone,
# and `&` as `&amp;`, so the reader gives the text back exactly.
#
# --list prints the entries as a JSON array, oldest first: {id, created,
# stamp, author, kind, text, edited}. Only comments carrying the marker whose
# author has write access to the host count, since anyone can comment on a
# public repository (a login GitHub doesn't know as a collaborator is left
# out; a failed access read lists nothing, exit 2); `edited` is true when
# GitHub says the comment changed after it was posted. The text comes back as written, `@` decoded.
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
ENTRY_KINDS=" entry run told pause go-ahead approval answer assignment end work roadmap-status "
case "$MODE" in
    append)
        [ -r "$TEXTFILE" ] || usage
        case "$ENTRY_KINDS" in *" $KIND "*) ;; *) echo "$PROG: --kind is not one of:$ENTRY_KINDS" >&2; exit 64 ;; esac
        ;;
    list) [ -z "$TEXTFILE" ] || usage ;;
esac
# The largest entry posted, in bytes: the record body's own budget.
ENTRY_BUDGET=60000

. "$HERE/record-common.sh"
lib_facts
lib_run_ref || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }

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
        lib_has_write_access "$login"
        case $? in
            0) printf '%s\n' "$login" >> "$WD/writers" ;;
            1) ;;
            *) lib_die2 "cannot read $login's access to $REPO" ;;
        esac
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
               text: ($l[3:] | join("\n") | rtrimstr("\n") | gsub("&#64;"; "@") | gsub("&amp;"; "&")),
               edited: (.updated_at != .created_at)})' "$WD/marked.jsonl" || lib_die2 "jq failed"
    exit 0
fi

[ "$STATE" = OPEN ] || { echo "$PROG: refused: #$REF is $STATE, not an open record" >&2; exit 10; }

# The text, as the coordinator wrote it, line endings normalised.
tr -d '\r' < "$TEXTFILE" > "$WD/text"
# Leading and trailing lines that hold nothing but blanks carry nothing.
TEXT=$(awk '{ l[NR] = $0 } END { s = 1; while (s <= NR && l[s] ~ /^[ \t]*$/) s++
    e = NR; while (e >= s && l[e] ~ /^[ \t]*$/) e--; for (i = s; i <= e; i++) print l[i] }' "$WD/text")
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
    # `&` first, so the reader's decoding gives back exactly what was written.
    printf '%s\n' "$TEXT" | sed -e 's/&/\&amp;/g' -e 's/@/\&#64;/g'
} > "$WD/comment.md"
SIZE=$(wc -c < "$WD/comment.md" | tr -d ' ')
if [ "$SIZE" -gt "$ENTRY_BUDGET" ]; then
    echo "$PROG: refused: the entry is $SIZE bytes, over the $ENTRY_BUDGET-byte budget; split it" >&2; exit 65
fi
jq -n --rawfile b "$WD/comment.md" '{body: $b}' > "$WD/post.json" || lib_die2 "jq failed"
gh api --method POST "repos/$REPO/issues/$REF/comments" --input "$WD/post.json" --jq .html_url > "$WD/url" 2> "$WD/w.err" < /dev/null \
    || { echo "$PROG: the post failed: $(lib_scrub < "$WD/w.err")" >&2; exit 11; }
cat "$WD/url"
