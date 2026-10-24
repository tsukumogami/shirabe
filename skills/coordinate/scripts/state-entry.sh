#!/usr/bin/env bash
# state-entry.sh -- append an entry to the coordinator record, or list the
# entries. Agent-run; the one way an entry is written
# (docs/designs/current/DESIGN-coordinate-record-container.md, Decision 2).
#
# The record's tables hold its state and are rewritten whole by the write core;
# its entries, the dated account of what happened, live beside them in the
# coordinator's koto session (docs/designs/DESIGN-coordinator-session-record.md,
# Decision 5): each is the key record/entries/<n>, <n> a six-digit sequence one
# above the highest key there, holding {n, stamp, kind, text}. A number another
# writer took moves to the next, at most three times (entry-exists, exit 65,
# after that). An entry is never edited by this script and never grows.
#
# The outward kinds (cost, milestone-verdict, goal-fit, milestone-failure),
# which readers outside the coordinator read from GitHub, are also posted as
# the comment below on the item they concern
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 2), and
# the comment's URL kept in record/posted/<n>. --on <owner/repo#n> names the
# item, a pull request or an issue in the host repository or a holding's (its
# Repo, or its pull request's repository), compared without case; `--on none`
# writes the session entry and posts it nowhere, and an outward kind takes one
# or the other (exit 65 without). A cost entry takes either; a goal-fit entry
# takes the pull request its first line names (`Goal fit: <owner/repo#n> -- `)
# and nothing else; a milestone-verdict or milestone-failure entry is written
# with `--on none` and reaches its roadmap pull request only through
# roadmap-status.sh, whose `--repost N --on` is admitted when
# record/side-effects holds the roadmap edit row naming that pull request and
# `(entry N)`.
#
# An item gets a comment only when its repository, public or private, opts
# in with `## PR Workflow Content: include` in the CLAUDE.md on its default
# branch (read through scripts/pr-workflow-content.sh). Otherwise an append keeps the
# session entry, posts nothing and prints its key, as `--on none` does
# (exit 0, the reason on stderr), and --repost is refused (exit 65), the
# entry staying in the session.
#
# The text is scanned when it is posted, against the destination's
# visibility read then: a destination whose visibility can't be read counts
# as public, and a repository the text names (a github.com link, owner/repo#n
# or a JSON "repo" field) whose visibility can't be read counts as private. A
# bare owner/repo is read too: refused when private, and when unreadable
# under the destination's, the host's or a named repository's owner; more
# than 40 bare names are refused unread. A scan that refuses leaves the
# session entry where it is (exit 65, naming it). A retry with --on posts nothing when
# record/posted/N names a comment on the item, or when the item holds a
# comment of the same kind and text, by the login `gh api user` answers
# (compared without case), created at or after the entry's stamp and not kept
# as another entry's post; when that login can't be read it exits 2 and posts
# nothing.
#
# Usage:
#   state-entry.sh --session S --text-file F [--kind K] [--on <owner/repo#n>|none]
#   state-entry.sh --session S --list
#   state-entry.sh --session S --repost N --on <owner/repo#n>
#   state-entry.sh --scope roadmap|discipline --name N --repo O/R [...]
#                    (tests: RS_SESSION names the session holding the record)
#
# The session gives the scope, name and host (coord-log.sh vars), and must
# have a found record (coord-log.sh run-facts). An entry needs no other session
# check, because an entry changes nothing a check reads.
#
# The entry is stamped from the host clock in UTC to the second; an outward
# entry is posted as one comment:
#
#   <!-- coordinator-record-entry v1 kind=<kind> -->
#   **<YYYY-MM-DDTHH:MM:SSZ>** (host clock) <kind>
#
#   <the text>
#
# K is entry (the default), or one of the kinds the record's other writers
# append for what they change (the design's Decisions 3 and 4): run, told,
# pause, go-ahead, approval, answer, assignment, end, work, roadmap-status,
# hold (a hold added or lifted, state-hold.sh), moved (found in a record an
# earlier release moved onto its session; only the legacy importer still posts
# one, on the GitHub record it imports),
# milestone-verdict (a checked verdict on a milestone, milestone.sh
# check-verdict; docs/designs/DESIGN-milestone-verdicts.md), goal-fit (a
# landed pull request judged against its milestone's Evidence, milestone.sh
# check-goal-fit), milestone-failure (a failure reported against a Done
# milestone, milestone.sh check-failure), decisions (settled Decisions rows
# moved out of the body verbatim, state-decision.sh --archive, which reads
# them back to restore one),
# and cost, the teardown pass's unit-cost summary (unit-cost.sh). The text may not be empty, may hold no control character
# but a line break or a tab, and the whole comment may not exceed 60,000 bytes
# (exit 65). On a public host an entry kept in the session may not name a
# private or unreadable repository (as owner/repo#n or a github.com link), a
# home-directory path or a token-shaped string (exit 65), the checks the
# Decisions section's text columns get. In a comment `@` is written as
# `&#64;`, so an entry never mentions anyone, and `&` as `&amp;`, so the
# reader gives the text back exactly.
#
# --list prints the entries as a JSON array, the record/entries/ keys in
# sequence order: {id, created, stamp, author, kind, text, edited}, id the
# sequence number, created the stamp, author the address the record's
# `coordinator` Run row names (empty when it names none), edited always false.
#
# An append prints the entry's key, record/entries/<n>, or, for an outward
# kind posted on an item, the comment's URL. A post that fails keeps the
# session entry and exits 14; --repost N --on posts that entry's comment once,
# later, and posts nothing when record/posted/N exists or the item already
# holds it (above). A posted URL must be a comment on the --on item (exit 65
# otherwise).
#
# Exit codes: 0 posted (prints the comment's URL), written or listed; 2 a read
# failed; 10 refused (no found record, or no session); 11 a write failed (the
# entry's key, or record/posted/<n> after its comment was posted); 14 the
# session entry was written but its post failed (`--repost <n> --on` finishes
# it); 64 usage; 65 the entry was refused (the reason on stderr).
#
# GitHub calls:
#   reads:  gh api --method GET repos/<repo> --jq .private   (the host, then each repository the text names)
#           gh api --method GET repos/<item repo> --jq .private, and each repository the text names (--on)
#           gh api --method GET repos/<item repo>/contents/CLAUDE.md --jq .content (--on, the opt-in)
#           gh api user --jq .login, gh api --method GET repos/<item repo>/issues/<n>/comments (--repost --on)
#   writes: gh api --method POST repos/<item repo>/issues/<n>/comments --input <json> (--on)
# koto calls: context list --prefix record/entries/ and record/posted/,
#   context list --prefix for each key the seam's rs_key reads, context get,
#   context add (record/entries/<n>, record/posted/<n>); with --on,
#   record/holdings and record/side-effects through the seam's rs_key.
set -uo pipefail

PROG=state-entry
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= TEXTFILE= KIND=entry REPOST= ON=
MODE=append

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
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

. "$HERE/state-common.sh"
lib_facts
lib_run_found || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }

WD=$(mktemp -d "${TMPDIR:-/tmp}/state-entry.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$WD"' EXIT

# The session that holds the entries.
ES=${RS_SESSION:-$SESSION}
[ -n "$ES" ] || { echo "$PROG: refused: the entries need the run's session" >&2; exit 10; }
# The record has no comment stream: an outward entry goes on an item (--on
# owner/repo#n) or stays in the session (--on none).
if [ -z "$ON" ] && [ "$MODE" != list ]; then
    if [ "$MODE" = repost ]; then
        echo "$PROG: refused: --repost posts on an item: --on owner/repo#n" >&2; exit 65
    fi
    case "$OUTWARD_KINDS" in
        *" $KIND "*) echo "$PROG: refused: a $KIND entry is posted on the item it concerns: --on owner/repo#n, or --on none" >&2; exit 65 ;;
    esac
fi

# gh_entries <marked-jsonl>: the entries the item's marked comments carry, in
# the list's shape.
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
# post_comment <comment-file>: posts it on the --on item; prints the comment's
# URL. Returns 1 when the post failed, the reason in $WD/w.err.
post_comment() {
    jq -n --rawfile b "$1" '{body: $b}' > "$WD/post.json" || lib_die2 "jq failed"
    gh api --method POST "repos/$ON_REPO/issues/$ON_NUM/comments" --input "$WD/post.json" --jq .html_url 2> "$WD/w.err" < /dev/null
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
# on_admitted: refuses (65) an --on item outside the run's repositories: the
# host, or a holding's Repo or pull request repository.
on_admitted() {
    [ "$(lc "$ON_REPO")" = "$(lc "$REPO")" ] && return 0
    rs_key "$ES" record/holdings "$WD/holdings.json"
    case $? in
        0) jq -e -L "$HERE" --arg r "$(lc "$ON_REPO")" 'include "state-schema";
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
# dest_withheld: writes why an entry stays off the --on item to
# $WD/withheld, and returns 0, when the item's repository, public or private,
# doesn't opt in to workflow content on its pull requests and issues; returns
# 1 when it may be posted. The opt-in is `## PR Workflow Content: include`,
# read by scripts/pr-workflow-content.sh (STATE_ENTRY_PR_CONTENT_READER
# overrides its path, for tests) over the repository's CLAUDE.md as GitHub
# serves it from the default branch, since the item's repository may have no
# checkout here. A CLAUDE.md that can't be read, a missing reader, a reader
# that exits non-zero (whatever it printed), or any answer but `include` is
# omit.
dest_withheld() {
    local reader=${STATE_ENTRY_PR_CONTENT_READER:-$HERE/../../../scripts/pr-workflow-content.sh} d="$WD/pr-content" out=
    rm -rf "$d" && mkdir -p "$d" || lib_die2 "cannot make a temporary directory"
    if gh api --method GET "repos/$ON_REPO/contents/CLAUDE.md" --jq '.content // ""' > "$WD/claude-md.b64" 2> /dev/null < /dev/null; then
        lib_b64d "$WD/claude-md.b64" "$d/CLAUDE.md" || rm -f "$d/CLAUDE.md"
    fi
    [ -f "$reader" ] && out=$(bash "$reader" "$d" 2> /dev/null < /dev/null) || out=
    [ "${out%%$'\n'*}" = include ] && return 1
    echo "$ON_REPO doesn't opt in to workflow content (## PR Workflow Content: include)" > "$WD/withheld"
}
# The most bare owner/repo names one outward scan reads; text naming more is
# refused rather than read without bound.
BARE_CAP=40
# dest_problem <text-file>: why TEXT can't be posted on the --on item, or
# nothing. The destination's visibility is read now, at post time; one that
# can't be read counts as public. On a public destination each repository the
# text names is read too, in any form. A github.com link, owner/repo#n (the
# schema's text_named_repos) or a JSON "repo" field's value that can't be read
# counts as private. Any other whole owner/repo token, outside a URL and not
# part of a longer path, is a bare name: one GitHub reads as private is
# refused, and one that can't be read is refused when its owner is the
# destination's, the host's or a named repository's, since elsewhere a bare
# a/b is as often prose (and/or) or a schema name (unit-cost/1) as a
# repository. state-schema.jq decides, as it does for the record's own text fields.
dest_problem() {
    local p r priv= owners
    p=$(gh api --method GET "repos/$ON_REPO" --jq .private 2> /dev/null < /dev/null) || p=unreadable
    [ "$p" = true ] && return 0
    jq -R -s -r -L "$HERE" 'include "state-schema";
        def clean: sub("\\.git$"; "") | sub("\\.+$"; "");
        def named: select(test("^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$") and (split("/")[1] | test("^\\.*$") | not));
        ((text_named_repos + [scan("\"repo\"\\s*:\\s*\"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)\"") | .[0] | clean])
         | map(select(. != "")) | unique) as $sure
        | ($sure | map(ascii_downcase)) as $lsure
        | (gsub("[A-Za-z][A-Za-z0-9+.-]*://[^\\s)\\]>]*"; " ")
           | [scan("(?:^|[^A-Za-z0-9_./-])([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)(?=$|[^A-Za-z0-9_/#-])") | .[0] | clean | named]
           | unique | map(select(ascii_downcase as $b | $lsure | index($b) | not))) as $bare
        | ($sure[] | "sure \(.)"), ($bare[] | "bare \(.)")' < "$1" > "$WD/named" || lib_die2 "jq failed"
    if [ "$(grep -c '^bare ' "$WD/named")" -gt "$BARE_CAP" ]; then
        echo "names more than $BARE_CAP owner/repo names, more than are read before a post"
        return 0
    fi
    owners=" $(lc "${ON_REPO%%/*}") $(lc "${REPO%%/*}") $(sed -n 's|^sure \([^/]*\)/.*|\1|p' "$WD/named" | tr 'A-Z\n' 'a-z ')"
    while read -r form r; do
        [ "$(lc "$r")" = "$(lc "$ON_REPO")" ] && continue
        [[ $r =~ $RE_REPO ]] || continue
        p=$(gh api --method GET "repos/$r" --jq .private 2> /dev/null < /dev/null) || p=unreadable
        [ "$p" = false ] && continue
        if [ "$form" = bare ] && [ "$p" != true ]; then
            case "$owners " in *" $(lc "${r%%/*}") "*) ;; *) continue ;; esac
        fi
        priv="$priv${priv:+,}$r"
    done < "$WD/named"
    jq -R -s -r -L "$HERE" --arg p "$priv" \
        'include "state-schema"; text_problem($p | split(",") | map(select(. != ""))) // empty' < "$1" || lib_die2 "jq failed"
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
# a comment on its --on item.
s_record_posted() {
    on_url_ok "$2" || { echo "$PROG: refused: $2 is not a comment on $ON" >&2; exit 65; }
    printf '%s\n' "$2" > "$WD/posted"
    "$KOTO" context add "$ES" "record/posted/$1" --from-file "$WD/posted" < /dev/null > /dev/null 2> "$WD/k.err" \
        || { echo "$PROG: the comment was posted ($2) but record/posted/$1 wasn't written: $(lib_scrub < "$WD/k.err")" >&2; exit 11; }
}

if [ "$MODE" = list ]; then
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

if [ "$MODE" = repost ]; then
    N=$(printf '%06d' "$((10#$REPOST))")
    rs_key "$ES" "record/entries/$N" "$WD/entry.json"
    case $? in 0) ;; 1) echo "$PROG: refused: no entry $N" >&2; exit 65 ;; *) lib_die2 "cannot read record/entries/$N" ;; esac
    EKIND=$(jq -r '.kind' "$WD/entry.json") || lib_die2 "record/entries/$N is not JSON"
    case "$OUTWARD_KINDS" in *" $EKIND "*) ;; *) echo "$PROG: refused: entry $N is a $EKIND entry, which stays in the session" >&2; exit 65 ;; esac
    jq -r '.text' "$WD/entry.json" > "$WD/text"
    on_admitted
    case "$EKIND" in
        goal-fit) goal_fit_check "$WD/text" ;;
        milestone-*) roadmap_row_check "$((10#$N))" "$EKIND" ;;
    esac
    if rs_key "$ES" "record/posted/$N" "$WD/posted.now"; then
        if ! on_url_ok "$(head -1 "$WD/posted.now")"; then
            echo "$PROG: refused: entry $N is already posted at $(head -1 "$WD/posted.now"), not on $ON" >&2; exit 65
        fi
        cat "$WD/posted.now"
        exit 0
    fi
    ESTAMP=$(jq -r '.stamp' "$WD/entry.json")
    # A post that landed before a crash: the same kind and text, by this run's
    # login, created at or after the entry's stamp, and not already kept as
    # another entry's post (two identical entries, a verdict repeated after a
    # reopen, each have their own comment). Anyone may comment on the item, so
    # only the login this run posts as counts.
    LOGIN=$(gh api user --jq .login 2> "$WD/u.err" < /dev/null) && [[ $LOGIN =~ $RE_LOGIN ]] \
        || { echo "$PROG: cannot read the login this run posts as, so whether entry $N already landed on $ON can't be told; nothing posted: $(lib_scrub < "$WD/u.err")" >&2; exit 2; }
    gh api --method GET "repos/$ON_REPO/issues/$ON_NUM/comments?per_page=100" --paginate \
        --jq '.[] | {id, html_url, created_at, updated_at, user: (.user.login // ""), body: (.body // "")}' \
        > "$WD/comments.jsonl" 2> "$WD/c.err" < /dev/null || lib_die2 "cannot read $ON's comments: $(lib_scrub < "$WD/c.err")"
    jq -c --arg m "$ENTRY_MARKER_PREFIX" --arg l "$(lc "$LOGIN")" \
        'select((.body | gsub("\r"; "") | startswith($m)) and ((.user | ascii_downcase) == $l))' \
        "$WD/comments.jsonl" > "$WD/writers.jsonl" || lib_die2 "the comments read is not JSON"
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
    if dest_withheld; then
        echo "$PROG: refused: entry $N stays in the session; it isn't posted on $ON: $(cat "$WD/withheld")" >&2; exit 65
    fi
    dest_problem "$WD/text" > "$WD/problem"
    [ ! -s "$WD/problem" ] || { echo "$PROG: refused: entry $N stays in the session; it can't be posted on $ON: it $(cat "$WD/problem")" >&2; exit 65; }
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
# github.com link, owner/repo#n), each read for visibility; state-schema.jq decides
# whether the text names one that isn't public, as it does for the Decisions
# fields.
# An entry bound for an item (--on) is scanned against the item's visibility
# when it is posted, below, instead.
PRIVATE=
HOST_PRIVATE=
[ -n "$ON" ] || { HOST_PRIVATE=$(gh api --method GET "repos/$REPO" --jq .private 2> /dev/null < /dev/null) || lib_die2 "cannot read $REPO's visibility"; }
if [ "$HOST_PRIVATE" = false ]; then
    printf '%s' "$TEXT" | jq -R -s -r -L "$HERE" 'include "state-schema"; text_named_repos | .[]' > "$WD/named" || lib_die2 "jq failed"
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
        'include "state-schema"; text_problem($p | split(",") | map(select(. != ""))) // empty' > "$WD/problem" \
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
if [ -z "$ON" ] || [ "$ON" = none ]; then
    printf 'record/entries/%s\n' "$WRITTEN"
    exit 0
fi
if dest_withheld; then
    echo "$PROG: kept the entry in the session as record/entries/$WRITTEN, posted nowhere: $(cat "$WD/withheld")" >&2
    printf 'record/entries/%s\n' "$WRITTEN"
    exit 0
fi
dest_problem "$WD/text.clean" > "$WD/problem"
[ ! -s "$WD/problem" ] || { echo "$PROG: refused: the entry was written as record/entries/$WRITTEN and stays in the session; it can't be posted on $ON: it $(cat "$WD/problem")" >&2; exit 65; }
URL=$(post_comment "$WD/comment.md") \
    || { echo "$PROG: the entry was written as record/entries/$WRITTEN, but its post failed: $(lib_scrub < "$WD/w.err"); post it later with state-entry.sh --repost $((10#$WRITTEN)) --on $ON" >&2; exit 14; }
s_record_posted "$WRITTEN" "$URL"
printf '%s\n' "$URL"
