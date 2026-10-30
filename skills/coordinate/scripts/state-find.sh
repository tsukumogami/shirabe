#!/usr/bin/env bash
# state-find.sh -- the check action of state record_find: find this scope's
# coordinator record and say whether the run may adopt it.
#
# The record lives in the coordinator's own koto session on this host
# (docs/designs/current/DESIGN-coordinator-record-teardown.md). The find reads
# the run's session first: when it holds record/meta (a resume, a carry or an
# import the opener made, or the record record_open or predecessor_carry just
# put there) and that record reads back as this scope's, it is `found`; one
# that doesn't read back is `malformed`. With no record in the run's session:
#   roadmap     `none`, so record_open opens one; but when another session of
#               this scope on this host holds a record, the opener's resume or
#               carry didn't reach this run, and the find stops at `malformed`
#               (session-absent) rather than open a second record
#   discipline  the rotation's predecessor (session_find below): `predecessor
#               <session>`, `first` or `unreadable <session>`
# The find reads nothing on GitHub.
#
# On `found`, `predecessor` and `first`, the run's session name goes to context
# key record_url, which the terminal results name as `record`.
#
# Verdict tokens (the first word is what coord-verdict.sh routes on):
#   roadmap:    found | none | malformed
#   discipline: found | predecessor <session> | first | unreadable <session>
#               | malformed
#
# Usage:
#   state-find.sh --session S
#   state-find.sh [--session S] --scope roadmap|discipline --name N --repo O/R
#                  [--today YYYY-MM-DD] [--no-seal]          (tests)
#
# The detail goes to context key coord/record_find.json as data:
#   {verdict, session, reason, rotation:{start,end}, store}
# and the run's store, always the session, with the reason, to
# coord/source.json: {source: "session", reason}. The resume candidate
# (state-read.sh rs_resume_candidate) resumes or carries only a run whose
# coord/source.json reads session.
# The token, sealed to this visit of record_find, is the only stdout line;
# under --no-seal it is printed bare and no context is written.
#
# Exit codes: 0 a verdict was printed; 2 a read failed (koto re-runs the
# action); 64 usage.
set -uo pipefail

PROG=state-find
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
. "$HERE/state-common.sh"
lib_facts
if [ -n "$TODAY" ]; then lib_valid_date "$TODAY" || usage; else TODAY=$(date -u +%Y-%m-%d); fi

T=$(mktemp -d "${TMPDIR:-/tmp}/state-find.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT

VERDICT= ARG= URL= REASON= ROT_START= ROT_END=

finish() {
    # Under --no-seal (a test's direct call) the reason is told on stderr, as the
    # sealed detail would carry it.
    [ "$NO_SEAL" != 1 ] || [ -z "$REASON" ] || echo "$PROG: $REASON" >&2
    local token=$VERDICT
    [ -n "$ARG" ] && token="$VERDICT $ARG"
    jq -n --arg v "$VERDICT" --arg s "$ARG" --arg reason "$REASON" --arg rs "$ROT_START" --arg re "$ROT_END" \
        '{verdict: $v, session: $s, reason: $reason, rotation: {start: $rs, end: $re}, store: "session"}' > "$T/detail.json"
    if [ "$NO_SEAL" != 1 ]; then
        # The record is this run's session, the one it resumes, carries a
        # predecessor into, or opens; the terminal results name it.
        case "$VERDICT" in
            found|predecessor|first)
                printf '%s' "$SESSION" > "$T/record_url"
                "$KOTO" context add "$SESSION" record_url --from-file "$T/record_url" >/dev/null || lib_die2 "koto context add record_url failed" ;;
        esac
        # The run's store, for a person to read and for the resume candidate.
        jq -n --arg r "$VERDICT: $REASON" '{source: "session", reason: $r}' > "$T/source.json"
        "$KOTO" context add "$SESSION" coord/source.json --from-file "$T/source.json" >/dev/null || lib_die2 "koto context add coord/source.json failed"
    fi
    lib_emit record_find "$token" coord/record_find.json "$T/detail.json"
}

# rotation_dates <session>: the rotation's window into ROT_START and ROT_END,
# for the find's detail; blank when the session holds none.
rotation_dates() {
    if rs_rotation "$1" "$T/rot" 2> /dev/null; then
        ROT_START=$(jq -r .start "$T/rot") ROT_END=$(jq -r .end "$T/rot")
    fi
}

# The run's own session holds the record: a resume, a carry, an import, or the
# record this run just opened or carried in.
SELF=${SESSION:-${RS_SESSION:-}}
if [ -n "$SELF" ]; then
    rs_list "$SELF" record/meta "$T/self-keys" || lib_die2 "cannot list this run's keys: $(lib_scrub < "$T/self-keys.err")"
    if jq -e 'index("record/meta") != null' "$T/self-keys" > /dev/null; then
        rs_session_read "$T/self" "$SELF" "$SCOPE" "$NAME"
        case $? in
            0) ;;
            2) lib_die2 "cannot read this run's record: $(lib_scrub < "$T/self.err")" ;;
            *) VERDICT=malformed; REASON="this run's record doesn't read back as this $SCOPE's: $(lib_scrub < "$T/self.err" | head -1)"; finish ;;
        esac
        [ "$SCOPE" = discipline ] && rotation_dates "$SELF"
        VERDICT=found; REASON="this run's session holds the record"; finish
    fi
fi

# session_find: a discipline rotation whose run holds no record yet
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 3). It
# seals one of:
#   predecessor <session>    the latest earlier rotation of the discipline,
#                            which predecessor_carry carries
#   first                    no earlier rotation: record_open opens it
#   unreadable <session>     the latest earlier rotation fails a rule below;
#                            the run stops at record_conflict and carries nothing
# The latest earlier rotation is the session named coordinate-<slug>-<stamp>
# (any root session starting coordinate-<slug>- whose next sixteen characters
# are a stamp earlier than this run's), holding record/meta, with the latest
# stamp. It is the predecessor only when its name is coordinate-<slug>-<stamp>
# whole, it passes coord-log.sh provenance, its DISCIPLINE and HOST_REPO
# variables are this run's, its rotation has ended by the window rule (the
# opener never sends an open one here), no later session of the discipline
# already names it as its predecessor, and its record reads back (record/meta
# and every section through state-schema.jq's checks). Two at one stamp are
# unreadable too.
session_find() {
    local self=$SELF stamp slug prefix c cands other p top
    slug=$(bash "$HERE/coord-log.sh" slug --scope "$SCOPE" --name "$NAME") || lib_die2 "cannot derive the scope's slug"
    prefix="coordinate-$slug-"
    if [ -n "$self" ]; then
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
    # Read newest first, stopping past the stamp of the first holder: an older
    # session can't change the verdict, and koto may not be able to read it from
    # here at all (an old session it can't locate). A session that could, newer
    # than any holder or at the holder's stamp, still stops the find unread.
    : > "$T/holders"
    top=
    while read -r s id; do
        [ -n "$top" ] && [ "$s" != "$top" ] && break
        : > "$T/k.err"
        rs_list "$id" record/meta "$T/k" || lib_die2 "cannot list $id's keys: $(lib_scrub < "$T/k.err")"
        # A rotation imported to another host holds no record here, as
        # rs_scope_sessions has it, though koto 0.32.0 and later still read it.
        if jq -e 'index("record/meta") != null' "$T/k" > /dev/null && ! rs_migrated "$id"; then
            printf '%s %s\n' "$s" "$id" >> "$T/holders"
            top=$s
        fi
    done < "$T/earlier"
    if [ ! -s "$T/holders" ]; then
        VERDICT=first; REASON="no earlier rotation of the discipline"; finish
    fi
    stamp=$(head -1 "$T/holders" | cut -d' ' -f1)
    cands=$(awk -v s="$stamp" '$1 == s { print $2 }' "$T/holders" | LC_ALL=C sort)
    c=${cands%%$'\n'*}
    ARG=$c
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
    # One predecessor is never carried twice: no later rotation of the
    # discipline names it. Only a session whose find would have counted $c as
    # earlier, the rest of its name after the prefix above $c's stamp, can have
    # carried it, so an older one is not read.
    jq -r --arg p "$prefix" --arg c "$c" --arg st "$stamp" '.[] | select(.parent_workflow == null) | .id
        | select(startswith($p) and . != $c) | select(ltrimstr($p) > $st)' \
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
    # a section that fails state-schema.jq's checks, a key that isn't JSON)
    # stops for the person: nothing is carried from a record that can't be read.
    if ! rs_session_read "$T/pred" "$c" "$SCOPE" "$NAME"; then
        VERDICT=unreadable; REASON="$c's record doesn't read back as this discipline's: $(lib_scrub < "$T/pred.err" | head -1)"; finish
    fi
    rotation_dates "$c"
    VERDICT=predecessor; REASON="the latest earlier rotation, $c, ended"; finish
}

if [ "$SCOPE" = discipline ]; then
    session_find
fi

# Roadmap scope with no record in the run's session. A record another session
# of this scope holds here is one the opener should have resumed or carried
# into this run; the find stops for the person rather than open a second one.
HOLDERS=$(rs_scope_sessions "$SCOPE" "$NAME") || lib_die2 "cannot list this host's sessions"
HOLDERS=$(printf '%s\n' "$HOLDERS" | grep -vxF -- "$SELF" | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')
if [ -n "$HOLDERS" ]; then
    VERDICT=malformed
    REASON="session-absent: session $HOLDERS on this host holds this scope's record and this run's session $SELF doesn't; start the coordinator again, which carries it into a new run"
    finish
fi
VERDICT=none; REASON="no session on this host holds this scope's record"; finish
