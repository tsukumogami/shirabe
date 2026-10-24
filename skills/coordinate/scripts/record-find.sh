#!/usr/bin/env bash
# record-find.sh -- the check action of state record_find: find this scope's
# coordinator record on GitHub and say whether the run may adopt it.
#
# Roadmap scope: every open issue in the host, read through the paginated REST
# listing (never a search, whose index lags a new issue and whose phrase match
# takes a -v2 title), matched on the exact title
# "Coordinator record: ROADMAP-<name>". Discipline scope: the record branch
# coordinate/discipline-<name> and its same-repository pull requests into the
# default branch; a fork's or another branch's pull request is never looked at.
# With none open, a discipline rotation is on the session store and the find
# reads this host's sessions of the discipline instead (session_find below).
#
# One candidate is judged in this order: the declaration line (else
# `foreign`), then authority (its author and last editor each have admin,
# maintain or write access to the host, else `unauthorized`; a failed
# permission read exits 2 so nothing is adopted), then a canonical body for
# this scope (else `malformed`), then, at discipline scope, the rotation
# title's dates (unparseable: `ambiguous`; ended before today UTC:
# `predecessor`).
#
# On `found`, the record's URL also goes to context key record_url, which the
# terminal results name as `record`.
#
# Verdict tokens (the first word is what coord-verdict.sh routes on):
#   roadmap:    found <n> | found <n> session | move <n> | none
#               | ambiguous <n> <m> [...] | foreign <n> | malformed <n> | unauthorized <n>
#   discipline: found <n> | predecessor <n> | foreign <n> | ambiguous <n> [...]
#               | malformed <n> | unauthorized <n>   (a rotation still on GitHub)
#               | found | predecessor <session> | predecessor handoff:<sha>
#               | first | unreadable <session> | malformed
#                                                    (a rotation on the session
#                                                    store: session_find below)
# At discipline scope a rotation with an open pull request on the record branch
# is still on GitHub and keeps that machinery until it ends; with none open, the
# rotation is on the session store and session_find decides. The invocation's
# --store decides nothing there.
#
# Usage:
#   record-find.sh --session S
#   record-find.sh [--session S] --scope roadmap|discipline --name N --repo O/R
#                  [--today YYYY-MM-DD] [--no-seal]          (tests)
#
# The detail goes to context key coord/record_find.json as data:
#   {verdict, ref, url, reason, candidates, default_branch, rotation:{start,end}, store}
# and the run's store to coord/source.json: {source, reason, probe}. For a
# discipline rotation on the session store `ref` is empty and `url` (and
# record_url) is the session's name: such a rotation has no pull request. A found
# record's store is its `store` Run row (`github` without one;
# docs/designs/DESIGN-coordinator-session-record.md, Decisions 2, 10 and 11):
#   - `session` on a record in the moved shape (every section empty, the Run
#     section only that row): `found <n> session`, the run reads the session
#     store, which this run's session must hold (record/meta), else `malformed`
#     with `session-absent`;
#   - `session` on a record still holding its state tables: a move, `move <n>`,
#     once the record's entries (through the author filter) hold the `run`
#     entry record-state.sh posted with the row, else `malformed` with
#     `store-unverified`;
#   - `github`, or no row, while a session of this scope on this host holds
#     record/meta: `malformed` with `store-conflict`, a stop for the person,
#     never a switch back to the GitHub state.
# A run on the session store needs koto's `context list --prefix` and `session
# import`; without them it is `malformed` with `store-unsupported`, naming what
# is missing, before anything is written (PRD R2). A malformed or doubled
# `store` row is `malformed` with `store-malformed`. At discipline scope a
# rotation on GitHub has no store row: a `store` row on one is `malformed` with
# `store-discipline`. The invocation's
# `session` on a roadmap scope with no record makes the record that
# record-open.sh opens a session-store one.
# The token, sealed to this visit of record_find, is the only stdout line;
# under --no-seal it is printed bare and no context is written.
#
# Exit codes: 0 a verdict was printed; 2 a read failed (koto re-runs the
# action); 64 usage.
#
# GitHub reads (all reads; no search form anywhere):
#   gh api --method GET "repos/R/issues?state=open&per_page=100" --paginate
#   gh api --method GET repos/R  --jq .default_branch
#   gh api --method GET repos/R/branches/coordinate%2Fdiscipline-<name>
#   gh pr list --repo R --head coordinate/discipline-<name> --state all --limit 100 --json ...
#   gh api graphql (a query: the candidate's author and editor logins)
#   gh api --method GET repos/R/collaborators/<login>/permission --jq .permission
#   gh api --method GET repos/R/git/ref/heads/<default branch> --jq .object.sha
#   gh api --method GET "repos/R/contents/docs/disciplines/<name>.md?ref=<sha>" --jq .content
# A discipline rotation on the session store makes the second, third and fourth
# of these, each once; with no earlier session rotation it adds the last two,
# each once (find-reads_test.sh counts them).
set -uo pipefail

PROG=record-find
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= TODAY=
NO_SEAL=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --today) [ $# -ge 2 ] || usage; TODAY=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/record-common.sh"
lib_facts
if [ -n "$TODAY" ]; then lib_valid_date "$TODAY" || usage; else TODAY=$(date -u +%Y-%m-%d); fi

T=$(mktemp -d "${TMPDIR:-/tmp}/record-find.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT

VERDICT= NUM= URL= REASON= CANDS='[]' DEFAULT_BRANCH= ROT_START= ROT_END= RECORD_STORE= FLAG_REFUSED= SESSION_STOP= SESSION_FIND=
# The invocation's --store (the STORE variable), read once. It decides only a
# new roadmap scope's store; at discipline scope neither coordinate-open.sh nor
# the find refuses it, and it decides nothing (store_flag_guard). A session
# whose variables can't be read stops here, rather than being taken as one with
# no --store.
FLAG=
if [ -n "$SESSION" ]; then
    FLAG=$(bash "$HERE/coord-log.sh" vars --session "$SESSION" | jq -r '.STORE // ""') \
        || lib_die2 "the session's variables couldn't be read"
fi

# store_flag_guard: the invocation's store, where it decides: a new roadmap
# scope opened on the session store needs koto's session-store features, and
# without them the run stops at record_conflict, before any record is opened,
# as malformed with the reason named.
store_flag_guard() {
    [ -n "$FLAG" ] || return 0
    # A new discipline rotation opens on the session store whatever the
    # invocation's --store says, and one still on GitHub stays there; the flag
    # decides nothing at discipline scope (write_source reports it ignored).
    [ "$SCOPE" = discipline ] && return 0
    case "$VERDICT" in
        none|stale-branch|unopened)
            [ "$FLAG" = session ] && ! store_probe && NUM= ;;
    esac
}

# store_probe: the session store's koto features; without them the run stops,
# naming what is missing, and never falls back to GitHub (PRD R2).
store_probe() {
    local missing
    missing=$(rs_probe_missing) || lib_die2 "the koto feature probe failed"
    [ -z "$missing" ] && return 0
    VERDICT=malformed; SESSION_STOP=1
    REASON="store-unsupported: this koto lacks $missing, which the session store needs; install a koto that has it"
    return 1
}

finish() {
    store_flag_guard
    # Under --no-seal (a test's direct call) the reason is told on stderr, as the
    # sealed detail would carry it.
    [ "$NO_SEAL" != 1 ] || [ -z "$REASON" ] || echo "$PROG: $REASON" >&2
    local token=$VERDICT
    [ -n "$NUM" ] && token="$VERDICT $NUM"
    [ "$VERDICT" = found ] && [ "$RECORD_STORE" = session ] && token="$token session"
    jq -n --arg v "$VERDICT" --arg ref "$NUM" --arg url "$URL" --arg reason "$REASON" \
        --argjson c "$CANDS" --arg db "$DEFAULT_BRANCH" --arg s "$ROT_START" --arg e "$ROT_END" \
        '{verdict: $v, ref: $ref, url: $url, reason: $reason, candidates: $c, default_branch: $db,
          rotation: {start: $s, end: $e}}' > "$T/detail.json"
    # The found record's URL, for the terminal results' `record` field
    # (${context.record_url}): written here, by the engine's own read, so the
    # closing report names the record the run actually found.
    if [ "$NO_SEAL" != 1 ] && { [ "$VERDICT" = found ] || [ "$VERDICT" = move ]; } \
        && [[ $URL =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(issues|pull)/[0-9]+$ ]]; then
        printf '%s' "$URL" > "$T/record_url"
        "$KOTO" context add "$SESSION" record_url --from-file "$T/record_url" >/dev/null || lib_die2 "koto context add record_url failed"
    fi
    # A rotation on the session store has no pull request: its record is this
    # run's session, the one it resumes, carries a predecessor into, or opens.
    if [ "$NO_SEAL" != 1 ] && [ -n "$SESSION_FIND" ] && [ -z "$SESSION_STOP" ]; then
        case "$VERDICT" in
            found|predecessor|first)
                printf '%s' "$SESSION" > "$T/record_url"
                "$KOTO" context add "$SESSION" record_url --from-file "$T/record_url" >/dev/null || lib_die2 "koto context add record_url failed" ;;
        esac
    fi
    write_source
    lib_emit record_find "$token" coord/record_find.json "$T/detail.json"
}

# write_source: the run's store, decided here and nowhere else
# (docs/designs/DESIGN-coordinator-session-record.md, Decision 2), with the
# probe's reading of koto, into coord/source.json for a person to read. A found
# record's store is its own `store` Run row, `github` without one; the
# invocation's --store (the STORE variable) decides only for a scope with no
# record, and is reported ignored otherwise. A stop on the session store's own
# account (store-unsupported, session-absent) records the session store and its
# reason; any other refusal records the GitHub store and its own reason, and so
# does a candidate the find rejected (malformed, store-malformed among them,
# ambiguous, foreign, unauthorized, predecessor): there is a
# record, it just wasn't adopted. The file records the store the run reads, not
# the one asked for. The run's readers take the store from coord-log.sh
# run-store, which reads it from this find's token.
write_source() {
    [ "$NO_SEAL" = 1 ] && return 0
    local flag=$FLAG store reason probe
    if [ -n "$SESSION_STOP" ]; then
        store=session; reason=$REASON
    elif [ -n "$SESSION_FIND" ]; then
        # A discipline rotation with no open pull request is on the session
        # store, whatever the find decided about it.
        store=session; reason="a discipline rotation on the session store: $VERDICT: $REASON"
        [ -z "$flag" ] || reason="$reason; the invocation's --store $flag is ignored: a new rotation opens on the session store"
    elif [ -n "$FLAG_REFUSED" ]; then
        store=github; reason=$REASON
    elif [ "$VERDICT" = move ]; then
        store=session
        reason="the record's store row reads session and it still holds its state tables: this run moves it from GitHub to the session store"
    elif [ "$VERDICT" = found ]; then
        store=${RECORD_STORE:-github}
        reason="the record's store"
        [ -n "$RECORD_STORE" ] || reason="the record has no store row"
        [ -z "$flag" ] || reason="$reason; the run's store setting ($flag) is ignored: the record decides"
    elif [ "$VERDICT" = none ] || [ "$VERDICT" = unopened ]; then
        # The opener sets STORE=session for a new roadmap scope unless --store
        # github was given; a session opened some other way may carry none.
        store=${flag:-github}
        reason="no record found: the run's store setting"
        [ -n "$flag" ] || reason="no record found and no store setting"
    else
        store=github
        reason="no record adopted: $VERDICT: $REASON"
    fi
    probe=$(rs_probe)
    jq -n --arg s "$store" --arg r "$reason" --argjson p "$probe" '{source: $s, reason: $r, probe: $p}' > "$T/source.json"
    "$KOTO" context add "$SESSION" coord/source.json --from-file "$T/source.json" >/dev/null || lib_die2 "koto context add coord/source.json failed"
    jq --arg s "$store" '. + {store: $s}' "$T/detail.json" > "$T/detail.json.t" && mv "$T/detail.json.t" "$T/detail.json"
}

# record_store: the found record's `store` Run row, into RECORD_STORE, and what
# it means for this run (the header's list). Returns 1 with VERDICT and REASON
# set when the run doesn't go on to reconcile from here.
record_store() {
    local sessions holders
    RECORD_STORE=$(jq -r '[(.run // [])[] | select(.key == "store") | .value][0] // ""' "$T/parsed.json")
    if [ "$SCOPE" = discipline ]; then
        [ -z "$RECORD_STORE" ] && return 0
        VERDICT=malformed; FLAG_REFUSED=1
        REASON="store-discipline: a discipline rotation's record has no store row; this one reads $RECORD_STORE"
        return 1
    fi
    if [ "$RECORD_STORE" = session ]; then
        store_probe || return 1
        if rs_moved "$T/parsed.json"; then
            # The state is in the session store; this run's session must hold it.
            if [ -n "$SESSION" ] && ! { rs_list "$SESSION" record/meta "$T/meta-keys" && jq -e 'index("record/meta") != null' "$T/meta-keys" > /dev/null; }; then
                VERDICT=malformed; SESSION_STOP=1
                REASON="session-absent: #$NUM's state is on the session store, and this run's session $SESSION doesn't hold it; bring it to this host with coordinate-open.sh --import <session> --from <workspace>, both named in the last host's reports"
                return 1
            fi
            return 0
        fi
        # Still holding its tables: a move, once the row is shown to be the
        # owner's, by the `run` entry record-state.sh posts with it.
        if ! store_row_entry; then
            VERDICT=malformed; FLAG_REFUSED=1
            REASON="store-unverified: #$NUM's Run section reads store session, but its entries hold no run entry recording it; set it with record-state.sh --run store session --by <who>"
            return 1
        fi
        VERDICT=move; REASON="moving the record onto the session store"
        return 1
    fi
    # GitHub: never while a session of this scope here holds the record's state.
    holders=$(rs_scope_sessions "$SCOPE" "$NAME") || lib_die2 "cannot list this host's sessions"
    if [ -n "$holders" ]; then
        sessions=$(printf '%s' "$holders" | tr '\n' ' ' | sed 's/ $//')
        local reads="no store row"
        [ -n "$RECORD_STORE" ] && reads="store $RECORD_STORE"
        VERDICT=malformed; FLAG_REFUSED=1
        REASON="store-conflict: #$NUM reads $reads, but session $sessions on this host holds this scope's state; the person decides which is the record"
        return 1
    fi
    return 0
}

# store_row_entry: 0 when the record's entries, through record-append.sh's
# author filter, hold the `run` entry record-state.sh posts with a store session
# row.
store_row_entry() {
    RS_SOURCE=github bash "$HERE/record-append.sh" --scope "$SCOPE" --name "$NAME" --repo "$REPO" --ref "$NUM" --list \
        > "$T/entries.json" 2> "$T/entries.err" || lib_die2 "cannot read #$NUM's entries: $(lib_scrub < "$T/entries.err")"
    jq -e 'any(.[]; .kind == "run" and (.text | test("^Run store set to session by .+\\.$")))' "$T/entries.json" > /dev/null
}

# judge <kind> <number> <body-file>: declaration, authority, canonical body.
# Sets VERDICT and REASON when the candidate fails one; returns 1 then.
judge() {
    if ! lib_has_declaration "$3"; then
        VERDICT=foreign; REASON="the candidate has no declaration line"; return 1
    fi
    lib_authority "$1" "$2"
    case $? in
        0) ;;
        1) VERDICT=unauthorized; REASON=$AUTH_REASON; return 1 ;;
        *) lib_die2 "the author-authority read failed for #$2; nothing adopted" ;;
    esac
    lib_parse "$3" "$T/parsed.json"
    case $? in
        0) ;;
        3|65) VERDICT=malformed; REASON=$(lib_scrub < "$T/parsed.json.err" | head -1); return 1 ;;
        *) lib_die2 "record-parse.sh failed" ;;
    esac
    return 0
}

# session_find: a discipline rotation on the session store
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 3), once
# GitHub holds no open record pull request. It seals one of:
#   found                    this run's own session holds the rotation (a
#                            resume, or the rotation record_open or
#                            predecessor_carry just put there)
#   predecessor <session>    the latest earlier rotation of the discipline,
#                            which predecessor_carry carries
#   predecessor handoff:<sha>  no earlier rotation on the session, but the
#                            discipline's last rotation ran on GitHub and
#                            committed docs/disciplines/<name>.md, read at the
#                            host's default branch at <sha>: carried once
#   first                    no earlier rotation anywhere: record_open opens it
#   unreadable <session>     the latest earlier rotation fails a rule below;
#                            the run stops at record_conflict and carries nothing
#   malformed                this run's own session holds a rotation that
#                            doesn't read back as this discipline's
# The latest earlier rotation is the session named coordinate-<slug>-<stamp>
# (any root session starting coordinate-<slug>- whose next sixteen characters
# are a stamp earlier than this run's), holding record/meta, with the latest
# stamp. It is the predecessor only when its name is coordinate-<slug>-<stamp>
# whole, it passes coord-log.sh provenance, its DISCIPLINE and HOST_REPO
# variables are this run's, its rotation has ended by the window rule (the
# opener never sends an open one here), no other session of the discipline
# already names it as its predecessor, and its record reads back (record/meta
# and every section through the codec's checks). Two at one stamp are
# unreadable too.
session_find() {
    local self=${SESSION:-} stamp slug prefix c cands rc other p
    SESSION_FIND=1
    # The session store needs koto's features; without them the run stops
    # here, naming what is missing (PRD R2).
    store_probe || finish
    slug=$(bash "$HERE/coord-log.sh" slug --scope "$SCOPE" --name "$NAME") || lib_die2 "cannot derive the scope's slug"
    prefix="coordinate-$slug-"
    if [ -n "$self" ]; then
        rs_list "$self" record/meta "$T/self-keys" || lib_die2 "cannot list this run's keys"
        if jq -e 'index("record/meta") != null' "$T/self-keys" > /dev/null; then
            rs_session_read "$T/self" body "$self" "$SCOPE" "$NAME" "$REPO" ""; rc=$?
            case $rc in
                0) ;;
                2|5) lib_die2 "cannot read this run's rotation: $(lib_scrub < "$T/self.err")" ;;
                *) VERDICT=malformed; NUM=; REASON="this run's rotation doesn't read back as this discipline's: $(lib_scrub < "$T/self.err" | head -1)"; finish ;;
            esac
            rotation_dates "$self"
            VERDICT=found; NUM=; URL=$self; REASON="this run's rotation, on the session store"; finish
        fi
        stamp=${self#"$prefix"}
    else
        stamp=$(date -u +%Y%m%dT%H%M%SZ)
    fi
    "$KOTO" session list < /dev/null > "$T/sessions.json" 2> "$T/sessions.err" || lib_die2 "koto session list failed: $(lib_scrub < "$T/sessions.err")"
    # Every earlier root session of the discipline holding record/meta, as
    # `<stamp> <name>`, newest first.
    jq -r --arg p "$prefix" --arg me "$self" --arg st "$stamp" '.[] | select(.parent_workflow == null) | .id
        | select(startswith($p) and . != $me) | . as $id | ($id | ltrimstr($p) | .[0:16]) as $s
        | select(($s | test("^[0-9]{8}T[0-9]{6}Z$")) and $s < $st) | "\($s) \($id)"' "$T/sessions.json" \
        | LC_ALL=C sort -r > "$T/earlier" || lib_die2 "jq failed"
    : > "$T/holders"
    while read -r s id; do
        rs_list "$id" record/meta "$T/k" || lib_die2 "cannot list $id's keys"
        jq -e 'index("record/meta") != null' "$T/k" > /dev/null && printf '%s %s\n' "$s" "$id" >> "$T/holders"
    done < "$T/earlier"
    if [ ! -s "$T/holders" ]; then
        bridge_or_first
    fi
    stamp=$(head -1 "$T/holders" | cut -d' ' -f1)
    cands=$(awk -v s="$stamp" '$1 == s { print $2 }' "$T/holders" | LC_ALL=C sort)
    c=${cands%%$'\n'*}
    NUM=$c
    if [ "$(printf '%s\n' "$cands" | grep -c .)" -gt 1 ]; then
        VERDICT=unreadable; REASON="two earlier rotations share the stamp $stamp: $(printf '%s' "$cands" | tr '\n' ' ' | sed 's/ $//')"; finish
    fi
    if ! [[ $c =~ ^coordinate-${slug}-[0-9]{8}T[0-9]{6}Z$ ]]; then
        VERDICT=unreadable; REASON="$c is not named coordinate-$slug-<YYYYMMDDTHHMMSSZ>"; finish
    fi
    if ! bash "$HERE/coord-log.sh" provenance --session "$c" > /dev/null 2>&1; then
        VERDICT=unreadable; REASON="$c fails provenance: it wasn't opened from this plugin's coordinate template"; finish
    fi
    bash "$HERE/coord-log.sh" vars --session "$c" > "$T/cvars.json" 2> /dev/null || { VERDICT=unreadable; REASON="$c's variables can't be read"; finish; }
    if [ "$(jq -r '.DISCIPLINE // ""' "$T/cvars.json")" != "$NAME" ]; then
        VERDICT=unreadable; REASON="$c is a rotation of another discipline, $(jq -r '.DISCIPLINE // "none"' "$T/cvars.json")"; finish
    fi
    if [ "$(jq -r '.HOST_REPO // "" | ascii_downcase' "$T/cvars.json")" != "$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')" ]; then
        VERDICT=unreadable; REASON="$c's host is $(jq -r '.HOST_REPO // "none"' "$T/cvars.json"), not $REPO"; finish
    fi
    rs_rotation_open "$c" "$TODAY"
    case $? in
        0) VERDICT=unreadable; REASON="$c's rotation is still open"; finish ;;
        1) ;;
        3) VERDICT=unreadable; REASON="$c holds no record/rotation"; finish ;;
        *) VERDICT=unreadable; REASON="$c's record/rotation can't be read"; finish ;;
    esac
    # One predecessor is never carried twice: no other rotation of the
    # discipline, earlier or later, names it.
    jq -r --arg p "$prefix" --arg c "$c" '.[] | select(.parent_workflow == null) | .id | select(startswith($p) and . != $c)' \
        "$T/sessions.json" > "$T/others" || lib_die2 "jq failed"
    while read -r other; do
        rs_rotation "$other" "$T/orot"
        case $? in
            0) p=$(jq -r '.predecessor // ""' "$T/orot")
               if [ "$p" = "$c" ]; then VERDICT=unreadable; REASON="$c is already carried by $other"; finish; fi ;;
            1) ;;
            *) VERDICT=unreadable; REASON="$other's record/rotation can't be read, so whether it carried $c can't be told"; finish ;;
        esac
    done < "$T/others"
    # Any failure to read the predecessor back (a record/meta of the wrong shape,
    # a section that fails the codec's checks, a key that isn't JSON) stops for
    # the person: nothing is carried from a record that can't be read.
    rs_session_read "$T/pred" body "$c" "$SCOPE" "$NAME" "$REPO" ""; rc=$?
    if [ $rc -ne 0 ]; then
        VERDICT=unreadable; REASON="$c's record doesn't read back as this discipline's: $(lib_scrub < "$T/pred.err" | head -1)"; finish
    fi
    rotation_dates "$c"
    VERDICT=predecessor; URL=$c; REASON="the latest earlier rotation, $c, ended"; finish
}

# rotation_dates <session>: the rotation's window into ROT_START and ROT_END,
# for the find's detail; blank when the session holds none.
rotation_dates() {
    if rs_rotation "$1" "$T/rot" 2> /dev/null; then
        ROT_START=$(jq -r .start "$T/rot") ROT_END=$(jq -r .end "$T/rot")
    fi
}

# bridge_or_first: no earlier rotation on the session store. A discipline whose
# last rotation ran on GitHub committed docs/disciplines/<name>.md; the first
# session rotation carries it once, read at the default branch's head
# (`predecessor handoff:<sha>`). With no file it is the discipline's first
# rotation.
bridge_or_first() {
    local head
    # The discipline read already holds the default branch; read it again only
    # without one.
    [ -n "$DEFAULT_BRANCH" ] || lib_default_branch || lib_die2 "cannot read $REPO's default branch"
    head=$(gh api --method GET "repos/$REPO/git/ref/heads/$DEFAULT_BRANCH" --jq .object.sha 2> "$T/head.err" < /dev/null) \
        || lib_die2 "cannot read the head of $DEFAULT_BRANCH: $(lib_scrub < "$T/head.err")"
    [[ $head =~ $RE_SHA ]] || lib_die2 "the head of $DEFAULT_BRANCH is not a sha"
    lib_file_at "docs/disciplines/$NAME.md" "$head" "$T/handoff.md"
    case $? in
        0) VERDICT=predecessor; NUM="handoff:$head"
           REASON="no earlier rotation on the session store; the last rotation on GitHub committed docs/disciplines/$NAME.md, carried once" ;;
        1) VERDICT=first; NUM=; REASON="no earlier rotation of the discipline" ;;
        *) lib_die2 "cannot read docs/disciplines/$NAME.md: $(lib_scrub < "$T/handoff.md.err")" ;;
    esac
    finish
}

if [ "$SCOPE" = roadmap ]; then
    lib_open_issues "$T/issues.json" || lib_die2 "the open-issue listing failed: $(lib_scrub < "$T/issues.json.raw.err")"
    CANDS=$(jq -c 'map({number, url, title})' "$T/issues.json")
    COUNT=$(jq length "$T/issues.json")
    if [ "$COUNT" -eq 0 ]; then
        VERDICT=none; REASON="no open issue titled $ISSUE_TITLE"; finish
    fi
    if [ "$COUNT" -gt 1 ]; then
        VERDICT=ambiguous; NUM=$(jq -r 'map(.number | tostring) | join(" ")' "$T/issues.json")
        REASON="$COUNT open issues carry the record's title"; finish
    fi
    NUM=$(jq -r '.[0].number' "$T/issues.json")
    URL=$(jq -r '.[0].url' "$T/issues.json")
    [[ $NUM =~ $RE_NUM ]] || lib_die2 "the listing returned an unusable issue number"
    jq -r '.[0].body' "$T/issues.json" > "$T/body.md"
    judge issue "$NUM" "$T/body.md" || finish
    record_store || finish
    VERDICT=found; REASON="one open record"
    [ "$RECORD_STORE" = session ] && REASON="one open record, on the session store"
    finish
fi

# Discipline scope. A rotation still on GitHub (an open pull request on the
# record branch) keeps its machinery until it ends: `found <n>` while it runs,
# `predecessor <n>` once it has ended. With none open, the rotation is on the
# session store (session_find).
# A candidate on GitHub is a pull request body, whatever store an earlier visit
# sealed for this run.
CONTAINER=pr
lib_discipline_read "$T" || lib_die2 "a discipline read failed: $(cat "$T"/*.err 2>/dev/null | lib_scrub)"
CANDS=$(jq -c 'map({number, url, title, state})' "$T/prs.json")
if [ "$BRANCH_EXISTS" = 0 ]; then
    session_find
fi
jq '[.[] | select(.state == "OPEN")]' "$T/prs.json" > "$T/open.json"
OPEN=$(jq length "$T/open.json")
if [ "$OPEN" -eq 0 ]; then
    session_find
fi
if [ "$OPEN" -gt 1 ]; then
    VERDICT=ambiguous; NUM=$(jq -r 'map(.number | tostring) | join(" ")' "$T/open.json")
    REASON="$OPEN open pull requests on $BRANCH"; finish
fi
NUM=$(jq -r '.[0].number' "$T/open.json")
URL=$(jq -r '.[0].url' "$T/open.json")
[[ $NUM =~ $RE_NUM ]] || lib_die2 "the listing returned an unusable pull request number"
jq -r '.[0].body // ""' "$T/open.json" > "$T/body.md"
judge pullRequest "$NUM" "$T/body.md" || finish
record_store || finish
TITLE=$(jq -r '.[0].title' "$T/open.json")
if ! lib_rotation_dates "$TITLE"; then
    VERDICT=ambiguous; REASON="the record's title is not a rotation title with real dates"; finish
fi
if [ "$ROT_END" \< "$TODAY" ]; then
    VERDICT=predecessor; REASON="the rotation ended $ROT_END"; finish
fi
VERDICT=found; REASON="the rotation runs to $ROT_END"; finish
