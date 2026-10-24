#!/usr/bin/env bash
# record-append.sh -- append an entry to the coordinator record, or list the
# entries. Agent-run; the one way an entry is written
# (docs/designs/current/DESIGN-coordinate-record-container.md, Decision 2).
#
# The record's body holds its state and is rewritten whole by the write core;
# its entries, the dated account of what happened, are comments on the same
# container (the issue at roadmap scope, the rotation's pull request at
# discipline scope on GitHub). An entry is never edited by this script and
# never grows, so the record needs no archive.
#
# On the session store (a roadmap record, or a discipline rotation with no
# pull request; docs/designs/DESIGN-coordinator-session-record.md, Decision 5)
# each entry is instead the key record/entries/<n> in the coordinator's
# session, <n> a six-digit sequence one above the highest key there, holding
# {n, stamp, kind, text}. A number another writer took moves to
# the next, at most three times (entry-exists, exit 65, after that). The outward
# kinds (cost, milestone-verdict, goal-fit, milestone-failure), which readers
# outside the coordinator read from GitHub, are then also posted as the comment
# below, and the comment's URL kept in record/posted/<n>. On the session
# store every outward kind but cost (whose placement unit-cost.sh decides) is
# posted only when the repository the comment would land on opts in to
# workflow content on its pull requests and issues (`## PR Workflow Content:
# include`, read by repo-pr-content.sh); otherwise the entry stays in the
# session, its key printed, and a --repost of it is refused (65). That covers
# a verdict or failure entry too, which roadmap-status.sh posts through
# --repost after writing it here with --on none.
#
# --on puts an outward entry on the item it concerns instead
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 2),
# on the session store only; without it a run posts as above. <owner/repo#n>
# is a pull request or an issue in the host repository or a holding's (its
# Repo, or its pull request's repository), compared without case; `none`
# writes the session entry and posts it nowhere. A cost entry takes either; a
# goal-fit entry takes the pull request its first line names (`Goal fit:
# <owner/repo#n> -- `) and nothing else; a milestone-verdict or
# milestone-failure entry is written with `--on none` and reaches its roadmap
# pull request only through roadmap-status.sh, whose `--repost N --on` is
# admitted when record/side-effects holds the roadmap edit row naming that
# pull request and `(entry N)`. With --on the record issue isn't read, and the
# text is scanned when it is posted, against the destination's visibility read
# then: a destination whose visibility can't be read counts as public, and a
# repository the text names whose visibility can't be read counts as private.
# A scan that refuses leaves the session entry where it is (exit 65, naming
# it). A retry with --on posts nothing when record/posted/N names a comment on
# the item, or when the item holds a comment of the same kind and text, by the
# login `gh api user` answers (compared without case), created at or after the
# entry's stamp and not kept as another entry's post; when that login can't be
# read it exits 2 and posts nothing.
#
# Usage:
#   record-append.sh --session S --text-file F [--kind K] [--on <owner/repo#n>|none]
#   record-append.sh --scope roadmap|discipline --name N --repo O/R --ref N
#                    --text-file F [--kind K] [--on <owner/repo#n>|none]
#   record-append.sh (--session S | --scope ... --ref N) --list
#   record-append.sh (--session S | --scope ... --ref N) --repost N [--on <owner/repo#n>]
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
# pause, go-ahead, approval, answer, assignment, end, work, roadmap-status,
# hold (a hold added or lifted on the session store, record-hold.sh), moved
# (the record moved onto the session store, posted on GitHub by record-move.sh),
# milestone-verdict (a checked verdict on a milestone, milestone.sh
# check-verdict; docs/designs/DESIGN-milestone-verdicts.md), goal-fit (a
# landed pull request judged against its milestone's Evidence, milestone.sh
# check-goal-fit), milestone-failure (a failure reported against a Done
# milestone, milestone.sh check-failure), decisions (settled Decisions rows
# moved out of the body verbatim, record-decision.sh --archive, which reads
# them back to restore one),
# and cost, the teardown pass's unit-cost summary (unit-cost.sh). The text may not be empty, may hold no control character
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
# On the session store the list is the record/entries/ keys in sequence order,
# in the same shape: id the sequence number, created the stamp, author the
# address the record's `coordinator` Run row names (empty when it names none),
# edited always false.
#
# On the session store an append prints the entry's key, record/entries/<n>, or,
# for an outward kind, the comment's URL. A post that fails keeps the session
# entry and exits 14; --repost N posts that entry's comment once, later, and
# posts nothing when record/posted/N exists or when the record's entries,
# through the author filter above, already hold one of the same kind and text
# created at or after the entry's stamp (a post that landed before a crash).
# An identical comment created before the stamp, or by an author without write
# access, never stands in for the entry. A posted URL must be a comment on this
# record (exit 65 otherwise).
#
# Exit codes: 0 posted (prints the comment's URL), written or listed; 2 a read
# failed; 10 refused (not an open record of this scope, or no found record); 11
# a write failed (the post on GitHub; on the session store, the entry's key, or
# record/posted/<n> after its comment was posted); 14 the session entry was
# written but its post failed (`--repost <n>` finishes it); 64 usage; 65 the
# entry was refused (the reason on stderr).
#
# GitHub calls:
#   reads:  gh issue view N --repo R --json state,body,url
#           gh pr view N --repo R --json state,body,url
#           gh api --method GET repos/<repo> --jq .private   (the host, then each repository the text names)
#           gh api --method GET repos/R/issues/N/comments?per_page=100 --paginate
#           gh api --method GET repos/R/collaborators/<login>/permission --jq .permission
#           gh api --method GET repos/<item repo> --jq .private, and each repository the text names (--on)
#           gh api user --jq .login, gh api --method GET repos/<item repo>/issues/<n>/comments (--repost --on)
#           the destination's CLAUDE.md, through repo-pr-content.sh (session store)
#   writes: gh api --method POST repos/R/issues/N/comments --input <json>
#           (with --on, repos/<item repo>/issues/<n>/comments)
# koto calls (session store): context list --prefix record/entries/ and
#   record/posted/, context list --prefix for each key the seam's rs_key reads,
#   context get, context add (record/entries/<n>, record/posted/<n>); with
#   --on, record/holdings and record/side-effects through the seam's rs_key.
set -uo pipefail

PROG=record-append
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= TEXTFILE= KIND=entry REPOST= ON=
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
        --repost) [ $# -ge 2 ] || usage; MODE=repost; REPOST=$2; shift 2 ;;
        --on) [ $# -ge 2 ] || usage; ON=$2; shift 2 ;;
        *) usage ;;
    esac
done
ENTRY_KINDS=" entry run told pause go-ahead approval answer assignment end work roadmap-status hold moved cost milestone-verdict milestone-failure goal-fit decisions "
# The kinds a reader outside the coordinator reads from GitHub.
OUTWARD_KINDS=" cost milestone-verdict goal-fit milestone-failure "
# opt_in_kind <kind>: 0 for an outward kind posted only where the repository
# opts in: every one but cost, whose placement unit-cost.sh decides.
opt_in_kind() { case "$OUTWARD_KINDS" in *" $1 "*) [ "$1" != cost ] ;; *) return 1 ;; esac; }
case "$MODE" in
    append)
        [ -r "$TEXTFILE" ] || usage
        case "$ENTRY_KINDS" in *" $KIND "*) ;; *) echo "$PROG: --kind is not one of:$ENTRY_KINDS" >&2; exit 64 ;; esac
        ;;
    list) [ -z "$TEXTFILE" ] || usage ;;
    repost) [ -z "$TEXTFILE" ] && [[ $REPOST =~ ^[0-9]{1,6}$ ]] || usage ;;
esac
# The item --on names, checked against its fixed pattern before it reaches gh.
ON_REPO= ON_NUM=
if [ -n "$ON" ]; then
    [ "$MODE" != list ] || usage
    if [ "$ON" = none ]; then
        [ "$MODE" = append ] || { echo "$PROG: --repost posts on an item: --on owner/repo#n" >&2; exit 64; }
    else
        [[ $ON =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*$ ]] || { echo "$PROG: --on is owner/repo#n or none" >&2; exit 64; }
        ON_REPO=${ON%#*} ON_NUM=${ON##*#}
    fi
    [ "$MODE" = repost ] || case "$OUTWARD_KINDS" in *" $KIND "*) ;; *) echo "$PROG: --on is for an outward kind:$OUTWARD_KINDS" >&2; exit 64 ;; esac
fi
# The largest entry posted, in bytes: the record body's own budget.
ENTRY_BUDGET=60000

. "$HERE/record-common.sh"
lib_facts
lib_run_ref || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }

WD=$(mktemp -d "${TMPDIR:-/tmp}/record-append.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$WD"' EXIT

# The store this record's entries are on, and the session that holds them.
STORE=$(rs_source)
ES=${RS_SESSION:-$SESSION}
if [ "$STORE" = session ]; then
    [ "$SCOPE" = roadmap ] || lib_session_rotation || { echo "$PROG: refused: the session store is for a roadmap record or a discipline rotation with no record number" >&2; exit 65; }
    [ -n "$ES" ] || { echo "$PROG: refused: the session store needs the run's session" >&2; exit 10; }
fi
# A discipline rotation on the session store has no record to post on: its
# outward entries go on an item (--on owner/repo#n) or stay in the session
# (--on none).
if [ -z "$REF" ] && [ -z "$ON" ] && [ "$MODE" != list ]; then
    if [ "$MODE" = repost ]; then
        echo "$PROG: refused: a session rotation has no record to post on: --repost takes --on owner/repo#n" >&2; exit 65
    fi
    case "$OUTWARD_KINDS" in
        *" $KIND "*) echo "$PROG: refused: a session rotation has no record to post a $KIND entry on: --on owner/repo#n, or --on none" >&2; exit 65 ;;
    esac
fi
[ "$MODE" != repost ] || [ "$STORE" = session ] || { echo "$PROG: --repost is for a record on the session store" >&2; exit 64; }
[ -z "$ON" ] || [ "$STORE" = session ] || { echo "$PROG: --on is for a record on the session store; a GitHub record's entries are posted on it" >&2; exit 64; }

# Where a comment goes: the record, or the item --on names.
PREPO=$REPO PNUM=$REF
[ -z "$ON_REPO" ] || PREPO=$ON_REPO PNUM=$ON_NUM

# The target, re-read now: open, and this scope's record. An entry bound for
# an item (--on) doesn't go on the record, so the record isn't read for it.
STATE=OPEN
if [ -z "$ON" ] && [ -n "$REF" ]; then
    if [ "$SCOPE" = roadmap ]; then
        gh issue view "$REF" --repo "$REPO" --json state,body,url > "$WD/target.json" 2> "$WD/r.err" < /dev/null || lib_die2 "cannot read issue #$REF: $(lib_scrub < "$WD/r.err")"
    else
        gh pr view "$REF" --repo "$REPO" --json state,body,url > "$WD/target.json" 2> "$WD/r.err" < /dev/null || lib_die2 "cannot read pull request #$REF: $(lib_scrub < "$WD/r.err")"
    fi
    jq -r '.body // ""' "$WD/target.json" | tr -d '\r' > "$WD/live.md" || lib_die2 "the target read is not JSON"
    STATE=$(jq -r '.state' "$WD/target.json")
    grep -xF -- "$DECL" "$WD/live.md" > /dev/null || { echo "$PROG: refused: #$REF does not carry this scope's declaration line" >&2; exit 10; }
fi

# gh_marked <out>: the record's entry comments, as JSON lines {id, html_url,
# created_at, updated_at, user, body}, from authors with write access only.
gh_marked() {
    gh api --method GET "repos/$REPO/issues/$REF/comments?per_page=100" --paginate \
        --jq '.[] | {id, html_url, created_at, updated_at, user: (.user.login // ""), body: (.body // "")}' \
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
    jq -c --rawfile w "$WD/writers" '
        ($w | split("\n") | map(select(. != ""))) as $writers
        | select(.user as $u | $writers | index($u))' "$WD/marked.jsonl" > "$1" || lib_die2 "jq failed"
}
# gh_entries <marked-jsonl>: the entries those comments carry, in the list's shape.
gh_entries() {
    jq -s -c --arg m "$ENTRY_MARKER_PREFIX" '
        map((.body | gsub("\r"; "")) as $b
            | ($b | split("\n")) as $l
            | {id, created: .created_at,
               stamp: ($l[1] // "" | capture("^\\*\\*(?<s>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)\\*\\*").s // ""),
               author: .user,
               kind: ($l[0] | ltrimstr($m) | sub(" -->$"; "")),
               text: ($l[3:] | join("\n") | rtrimstr("\n") | gsub("&#64;"; "@") | gsub("&amp;"; "&")),
               edited: (.updated_at != .created_at)})' "$1" || lib_die2 "jq failed"
}
# comment_md <stamp> <kind> <text-file>: the comment an entry is posted as.
comment_md() {
    printf '%s%s -->\n' "$ENTRY_MARKER_PREFIX" "$2"
    printf '**%s** (host clock) %s\n\n' "$1" "$2"
    # `&` first, so the reader's decoding gives back exactly what was written.
    sed -e 's/&/\&amp;/g' -e 's/@/\&#64;/g' "$3"
}
# post_comment <comment-file>: posts it on the record, or on the --on item;
# prints the comment's URL. Returns 1 when the post failed, the reason in
# $WD/w.err.
post_comment() {
    jq -n --rawfile b "$1" '{body: $b}' > "$WD/post.json" || lib_die2 "jq failed"
    gh api --method POST "repos/$PREPO/issues/$PNUM/comments" --input "$WD/post.json" --jq .html_url 2> "$WD/w.err" < /dev/null
}
# lc <text>: lower case, for the comparisons GitHub makes without case
# (repository names, logins).
lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
# on_url_ok <url>: 0 when URL is a comment on the --on item, an issue's or a
# pull request's (GitHub answers /pull/ for a pull request's conversation).
on_url_ok() {
    [[ $(lc "$1") =~ ^https://github\.com/([a-z0-9_.-]+/[a-z0-9_.-]+)/(issues|pull)/([1-9][0-9]*)#issuecomment-[0-9]+$ ]] \
        && [ "${BASH_REMATCH[1]}" = "$(lc "$ON_REPO")" ] && [ "${BASH_REMATCH[3]}" = "$ON_NUM" ]
}
# kept_unless_opted_in <kind> <repo>: 0 when a KIND entry bound for REPO's
# item stays in the session instead, because REPO doesn't opt in to workflow
# content on its items; the reason goes to stderr.
kept_unless_opted_in() {
    opt_in_kind "$1" || return 1
    [ "$(bash "$HERE/repo-pr-content.sh" "$2" 2> "$WD/pc.err")" = include ] && return 1
    echo "$PROG: $2 doesn't opt in to workflow content on its pull requests and issues (## PR Workflow Content: include), so the $1 entry stays in the session" >&2
}
# on_admitted: refuses (65) an --on item outside the run's repositories: the
# host, or a holding's Repo or pull request repository.
on_admitted() {
    [ "$(lc "$ON_REPO")" = "$(lc "$REPO")" ] && return 0
    rs_key "$ES" record/holdings "$WD/holdings.json"
    case $? in
        0) jq -e -L "$HERE" --arg r "$(lc "$ON_REPO")" 'include "record-codec";
               [.[] | (.repo // ""), ((.pull_request // "") | pr_link | .repo)] | map(ascii_downcase) | index($r) != null' \
               "$WD/holdings.json" > /dev/null && return 0 ;;
        1) ;;
        *) lib_die2 "cannot read record/holdings: $(lib_scrub < "$WD/holdings.json.err")" ;;
    esac
    echo "$PROG: refused: $ON_REPO is neither the host, $REPO, nor a holding's repository" >&2; exit 65
}
# goal_fit_names <text-file>: the owner/repo#n a goal-fit entry's first line
# names (`Goal fit: <owner/repo#n> -- <tag>`), or nothing.
goal_fit_names() {
    head -1 "$1" | sed -n 's|^Goal fit: \([A-Za-z0-9_.-]*/[A-Za-z0-9_.-]*#[1-9][0-9]*\) -- .*$|\1|p'
}
# goal_fit_check <text-file>: refuses (65) a goal-fit entry whose first line
# names no pull request, or one other than the --on item.
goal_fit_check() {
    local named
    named=$(goal_fit_names "$1")
    [ -n "$named" ] || { echo "$PROG: refused: the goal-fit entry names no pull request (its first line is \`Goal fit: <owner/repo#n> -- <tag>\`)" >&2; exit 65; }
    [ "$(lc "$named")" = "$(lc "$ON")" ] || { echo "$PROG: refused: the goal-fit entry names $named, not $ON" >&2; exit 65; }
}
# dest_problem <text-file>: why TEXT can't be posted on the --on item, or
# nothing. The destination's visibility is read now, at post time; one that
# can't be read counts as public. On a public destination each repository the
# text names is read too, and one that can't be read counts as private; the
# codec decides, as it does for the record's own text columns.
dest_problem() {
    local p r priv=
    p=$(gh api --method GET "repos/$ON_REPO" --jq .private 2> /dev/null < /dev/null) || p=unreadable
    [ "$p" = true ] && return 0
    jq -R -s -r -L "$HERE" 'include "record-codec"; text_named_repos | .[]' < "$1" > "$WD/named" || lib_die2 "jq failed"
    while IFS= read -r r; do
        [ "$(lc "$r")" = "$(lc "$ON_REPO")" ] && continue
        [[ $r =~ $RE_REPO ]] || continue
        p=$(gh api --method GET "repos/$r" --jq .private 2> /dev/null < /dev/null) || p=unreadable
        [ "$p" = false ] || priv="$priv${priv:+,}$r"
    done < "$WD/named"
    jq -R -s -r -L "$HERE" --arg p "$priv" \
        'include "record-codec"; text_problem($p | split(",") | map(select(. != ""))) // empty' < "$1" || lib_die2 "jq failed"
}
# roadmap_row_check <n> <kind>: refuses (65) a milestone-verdict or
# milestone-failure entry's post unless roadmap-status.sh opened its roadmap
# pull request: record/side-effects holds that edit's row, its Target the --on
# pull request on the host and its How to confirm ending `(entry <n>)`.
roadmap_row_check() {
    local acts
    case "$2" in milestone-verdict) acts="milestone-done milestone-verdict" ;; *) acts=milestone-reopen ;; esac
    if [ "$(lc "$ON_REPO")" = "$(lc "$REPO")" ] && rs_key "$ES" record/side-effects "$WD/se.json"; then
        jq -e --arg a "$acts" --arg t "(https://github.com/$(lc "$REPO")/pull/$ON_NUM)" --arg num "[#$ON_NUM]" --arg h "(entry $1)" '
            ($a | split(" ")) as $acts
            | any(.[]; (.action as $x | $acts | index($x)) != null
                and ((.target // "" | ascii_downcase) | endswith(" " + $num + $t))
                and ((.how_to_confirm // "") | endswith($h)))' "$WD/se.json" > /dev/null && return 0
    fi
    echo "$PROG: refused: a $2 entry is posted on the roadmap pull request roadmap-status.sh opens for it (--verdict or --reopen with --entry $1), not by hand" >&2
    exit 65
}
# s_entries <out>: the session's entries, one key per line, in sequence order.
s_entries() {
    "$KOTO" context list --prefix record/entries/ "$ES" < /dev/null > "$WD/keys.json" 2> "$WD/k.err" \
        || lib_die2 "cannot list $ES's entries: $(lib_scrub < "$WD/k.err")"
    jq -r '.[] | select(test("^record/entries/[0-9]{6}$"))' "$WD/keys.json" | LC_ALL=C sort > "$1" || lib_die2 "the key list is not JSON"
}
# s_record_posted <n> <url>: keeps an outward entry's comment URL, which must be
# a comment on this record, or with --on on its item.
s_record_posted() {
    if [ -n "$ON_REPO" ]; then
        on_url_ok "$2" || { echo "$PROG: refused: $2 is not a comment on $ON" >&2; exit 65; }
    else
        [[ $2 =~ ^https://github\.com/${REPO}/issues/${REF}#issuecomment-[0-9]+$ ]] \
            || { echo "$PROG: refused: $2 is not a comment on #$REF in $REPO" >&2; exit 65; }
    fi
    printf '%s\n' "$2" > "$WD/posted"
    "$KOTO" context add "$ES" "record/posted/$1" --from-file "$WD/posted" < /dev/null > /dev/null 2> "$WD/k.err" \
        || { echo "$PROG: the comment was posted ($2) but record/posted/$1 wasn't written: $(lib_scrub < "$WD/k.err")" >&2; exit 11; }
}

if [ "$MODE" = list ]; then
    if [ "$STORE" = session ]; then
        s_entries "$WD/keys"
        : > "$WD/entries.jsonl"
        while IFS= read -r k; do
            "$KOTO" context get "$ES" "$k" < /dev/null >> "$WD/entries.jsonl" 2> "$WD/k.err" || lib_die2 "cannot read $k: $(lib_scrub < "$WD/k.err")"
            printf '\n' >> "$WD/entries.jsonl"
        done < "$WD/keys"
        if rs_key "$ES" record/run "$WD/run.json"; then
            AUTHOR=$(jq -r '[.[] | select(.key == "coordinator") | .value][0] // ""' "$WD/run.json") || lib_die2 "record/run is not JSON"
        else
            AUTHOR=
        fi
        jq -s -c --arg a "$AUTHOR" 'map({id: .n, created: .stamp, stamp, author: $a, kind, text, edited: false})' "$WD/entries.jsonl" \
            || lib_die2 "an entry key is not JSON"
        exit 0
    fi
    gh_marked "$WD/writers.jsonl"
    gh_entries "$WD/writers.jsonl"
    exit 0
fi

[ "$STATE" = OPEN ] || { echo "$PROG: refused: #$REF is $STATE, not an open record" >&2; exit 10; }

if [ "$MODE" = repost ]; then
    N=$(printf '%06d' "$((10#$REPOST))")
    rs_key "$ES" "record/entries/$N" "$WD/entry.json"
    case $? in 0) ;; 1) echo "$PROG: refused: no entry $N" >&2; exit 65 ;; *) lib_die2 "cannot read record/entries/$N" ;; esac
    EKIND=$(jq -r '.kind' "$WD/entry.json") || lib_die2 "record/entries/$N is not JSON"
    case "$OUTWARD_KINDS" in *" $EKIND "*) ;; *) echo "$PROG: refused: entry $N is a $EKIND entry, which stays in the session" >&2; exit 65 ;; esac
    jq -r '.text' "$WD/entry.json" > "$WD/text"
    if [ -n "$ON" ]; then
        on_admitted
        case "$EKIND" in
            goal-fit) goal_fit_check "$WD/text" ;;
            milestone-*) roadmap_row_check "$((10#$N))" "$EKIND" ;;
        esac
    fi
    if rs_key "$ES" "record/posted/$N" "$WD/posted.now"; then
        if [ -n "$ON" ] && ! on_url_ok "$(head -1 "$WD/posted.now")"; then
            echo "$PROG: refused: entry $N is already posted at $(head -1 "$WD/posted.now"), not on $ON" >&2; exit 65
        fi
        cat "$WD/posted.now"
        exit 0
    fi
    kept_unless_opted_in "$EKIND" "$PREPO" && { echo "$PROG: refused: entry $N is not posted" >&2; exit 65; }
    ESTAMP=$(jq -r '.stamp' "$WD/entry.json")
    # A post that landed before a crash: the same kind and text, by a writer,
    # created at or after the entry's stamp, and not already kept as another
    # entry's post (two identical entries, a verdict repeated after a reopen,
    # each have their own comment). On the record a writer is an author with
    # write access; on an --on item, anyone may comment, so it is the login
    # this run posts as, and only that login.
    if [ -n "$ON" ]; then
        LOGIN=$(gh api user --jq .login 2> "$WD/u.err" < /dev/null) && [[ $LOGIN =~ $RE_LOGIN ]] \
            || { echo "$PROG: cannot read the login this run posts as, so whether entry $N already landed on $ON can't be told; nothing posted: $(lib_scrub < "$WD/u.err")" >&2; exit 2; }
        gh api --method GET "repos/$ON_REPO/issues/$ON_NUM/comments?per_page=100" --paginate \
            --jq '.[] | {id, html_url, created_at, updated_at, user: (.user.login // ""), body: (.body // "")}' \
            > "$WD/comments.jsonl" 2> "$WD/c.err" < /dev/null || lib_die2 "cannot read $ON's comments: $(lib_scrub < "$WD/c.err")"
        jq -c --arg m "$ENTRY_MARKER_PREFIX" --arg l "$(lc "$LOGIN")" \
            'select((.body | gsub("\r"; "") | startswith($m)) and ((.user | ascii_downcase) == $l))' \
            "$WD/comments.jsonl" > "$WD/writers.jsonl" || lib_die2 "the comments read is not JSON"
    else
        gh_marked "$WD/writers.jsonl"
    fi
    gh_entries "$WD/writers.jsonl" > "$WD/gh-entries.json"
    "$KOTO" context list --prefix record/posted/ "$ES" < /dev/null > "$WD/posted-keys.json" 2> "$WD/k.err" \
        || lib_die2 "cannot list $ES's posted entries: $(lib_scrub < "$WD/k.err")"
    : > "$WD/claimed"
    for k in $(jq -r '.[]' "$WD/posted-keys.json"); do
        "$KOTO" context get "$ES" "$k" < /dev/null >> "$WD/claimed" 2> "$WD/k.err" || lib_die2 "cannot read $k: $(lib_scrub < "$WD/k.err")"
    done
    HIT=$(jq -r --arg k "$EKIND" --rawfile t "$WD/text" --arg s "$ESTAMP" --rawfile c "$WD/claimed" \
            --slurpfile m <(jq -s . "$WD/writers.jsonl") '
        ($c | split("\n") | map(select(. != ""))) as $claimed
        | [.[] | select(.kind == $k and .text == ($t | rtrimstr("\n")) and .created >= $s) | .id] as $ids
        | [$m[0][] | select(.id as $i | $ids | index($i)) | .html_url | select(. as $u | $claimed | index($u) | not)][0] // ""' \
        "$WD/gh-entries.json") || lib_die2 "jq failed"
    if [ -n "$HIT" ]; then
        s_record_posted "$N" "$HIT"
        printf '%s\n' "$HIT"
        exit 0
    fi
    if [ -n "$ON" ]; then
        dest_problem "$WD/text" > "$WD/problem"
        [ ! -s "$WD/problem" ] || { echo "$PROG: refused: entry $N stays in the session; it can't be posted on $ON: it $(cat "$WD/problem")" >&2; exit 65; }
    fi
    comment_md "$ESTAMP" "$EKIND" "$WD/text" > "$WD/comment.md"
    URL=$(post_comment "$WD/comment.md") || { echo "$PROG: the post failed: $(lib_scrub < "$WD/w.err")" >&2; exit 14; }
    s_record_posted "$N" "$URL"
    printf '%s\n' "$URL"
    exit 0
fi

# The text, as the coordinator wrote it, line endings normalised.
tr -d '\r' < "$TEXTFILE" > "$WD/text"
# Leading and trailing lines that hold nothing but blanks carry nothing.
TEXT=$(awk '{ l[NR] = $0 } END { s = 1; while (s <= NR && l[s] ~ /^[ \t]*$/) s++
    e = NR; while (e >= s && l[e] ~ /^[ \t]*$/) e--; for (i = s; i <= e; i++) print l[i] }' "$WD/text")
[ -n "$(printf '%s' "$TEXT" | tr -d ' \t\n')" ] || { echo "$PROG: refused: the entry is empty" >&2; exit 65; }
if LC_ALL=C grep -q '[[:cntrl:]]' <<<"$TEXT" 2>/dev/null \
    && LC_ALL=C grep -q '[[:cntrl:]]' <<<"$(LC_ALL=C tr -d '\n\t' <<<"$TEXT")"; then
    echo "$PROG: refused: the entry holds a control character" >&2; exit 65
fi

# On a public host, the repositories the text names unambiguously (a
# github.com link, owner/repo#n), each read for visibility; the codec decides
# whether the text names one that isn't public, as it does for the Decisions
# columns.
# An entry bound for an item (--on) is scanned against the item's visibility
# when it is posted, below, instead.
PRIVATE=
HOST_PRIVATE=
[ -n "$ON" ] || { HOST_PRIVATE=$(gh api --method GET "repos/$REPO" --jq .private 2> /dev/null < /dev/null) || lib_die2 "cannot read $REPO's visibility"; }
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
printf '%s\n' "$TEXT" > "$WD/text.clean"
comment_md "$STAMP" "$KIND" "$WD/text.clean" > "$WD/comment.md"
SIZE=$(wc -c < "$WD/comment.md" | tr -d ' ')
if [ "$SIZE" -gt "$ENTRY_BUDGET" ]; then
    echo "$PROG: refused: the entry is $SIZE bytes, over the $ENTRY_BUDGET-byte budget; split it" >&2; exit 65
fi
# Which item an entry may go on, checked before anything is written.
if [ "$ON" = none ]; then
    [ "$KIND" != goal-fit ] || { echo "$PROG: refused: a goal-fit entry goes on the pull request it names: --on owner/repo#n" >&2; exit 65; }
elif [ -n "$ON" ]; then
    case "$KIND" in
        milestone-verdict|milestone-failure)
            echo "$PROG: refused: a $KIND entry is written with --on none and posted on its roadmap pull request by roadmap-status.sh (--verdict or --reopen with --entry), not by hand" >&2; exit 65 ;;
        goal-fit) goal_fit_check "$WD/text.clean" ;;
    esac
    on_admitted
fi

if [ "$STORE" = session ]; then
    # The next sequence number, one above the highest key; a key another writer
    # took in between moves this entry to the next, at most three times.
    s_entries "$WD/keys"
    LAST=$(tail -1 "$WD/keys" | sed 's|^record/entries/||')
    NEXT=$(( ${LAST:+10#$LAST} + 1 ))
    WRITTEN=
    for try in 1 2 3 4; do
        N=$(printf '%06d' "$NEXT")
        if rs_key "$ES" "record/entries/$N" "$WD/taken"; then
            [ "$try" -lt 4 ] || break
            NEXT=$((NEXT + 1))
            continue
        fi
        jq -n -c --argjson n "$NEXT" --arg s "$STAMP" --arg k "$KIND" --arg t "$TEXT" '{n: $n, stamp: $s, kind: $k, text: $t}' > "$WD/entry.json"
        "$KOTO" context add "$ES" "record/entries/$N" --from-file "$WD/entry.json" < /dev/null > /dev/null 2> "$WD/k.err" \
            || { echo "$PROG: the entry write failed: $(lib_scrub < "$WD/k.err")" >&2; exit 11; }
        WRITTEN=$N
        break
    done
    [ -n "$WRITTEN" ] || { echo "$PROG: refused: entry-exists: record/entries/$N and the numbers before it were taken; list the entries and try again" >&2; exit 65; }
    if [ "$ON" = none ] || kept_unless_opted_in "$KIND" "$PREPO"; then
        printf 'record/entries/%s\n' "$WRITTEN"
        exit 0
    fi
    if [ -n "$ON" ]; then
        dest_problem "$WD/text.clean" > "$WD/problem"
        [ ! -s "$WD/problem" ] || { echo "$PROG: refused: the entry was written as record/entries/$WRITTEN and stays in the session; it can't be posted on $ON: it $(cat "$WD/problem")" >&2; exit 65; }
    fi
    case "$OUTWARD_KINDS" in
        *" $KIND "*)
            URL=$(post_comment "$WD/comment.md") \
                || { echo "$PROG: the entry was written as record/entries/$WRITTEN, but its post failed: $(lib_scrub < "$WD/w.err"); post it later with record-append.sh --repost $((10#$WRITTEN))${ON:+ --on $ON}" >&2; exit 14; }
            s_record_posted "$WRITTEN" "$URL"
            printf '%s\n' "$URL"
            ;;
        *) printf 'record/entries/%s\n' "$WRITTEN" ;;
    esac
    exit 0
fi

URL=$(post_comment "$WD/comment.md") || { echo "$PROG: the post failed: $(lib_scrub < "$WD/w.err")" >&2; exit 11; }
printf '%s\n' "$URL"
