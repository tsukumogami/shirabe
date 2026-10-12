#!/usr/bin/env bash
# record-move.sh -- move a roadmap coordinator record from GitHub onto the
# session store. Agent-run, from the directive of state record_move; never a
# default action. The owner having
# written its `store session` Run row with record-state.sh
# (docs/designs/DESIGN-coordinator-session-record.md, Decision 11; PRD R3).
#
# Three steps, each skipped when a re-run finds it done, so a crash between
# them resumes at the first step not done:
#   1. copy: when this run's session holds no record/meta, the GitHub record's
#      state is written into it, every section through the write core with the
#      move's own flags (SESSION_SEED, MOVE_WRITER). When another session of
#      this scope on this host holds record/meta instead, or the GitHub body is
#      already in the moved shape with no state in this run's session, the move
#      can't go on: `move-refused`, a stop for the person.
#   2. post: a `moved` entry on the GitHub record naming this run's stamp,
#      unless the record's entries (through record-append.sh's author filter)
#      already hold one naming it.
#   3. rewrite: the GitHub body to the moved shape (every section empty, the Run
#      section only the `store session` row), through the write core, unless it
#      already is.
#
# It prints `move=done`, or `move=refused` with the reason on stderr, and each
# step's outcome (`step=<copy|post|rewrite> <written|done-before>`) as it goes.
#
# Usage:
#   record-move.sh --session S
#   record-move.sh --scope roadmap --name N --repo O/R --ref N
#                  --skip-session-checks                    (tests; the session
#                  store is RS_SESSION's)
#
# Before anything is read, the session must pass `coord-log.sh provenance`, be
# the scope's live run and show no directed transition, as every writer's must.
#
# Exit codes: 0 moved; 65 refused (the reason on stderr), a stop for the person;
# 11 a write failed part way (running it again finishes the move); 2 a read
# failed; 64 usage.
#
# GitHub calls: the reads and writes of record-source.sh's rs_record, the write
# core (record-write-core.sh) and record-append.sh; nothing else.
# koto calls: context exists (record/meta), session list, and the write core's.
set -uo pipefail

PROG=record-move
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF=
SKIP_CHECKS=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/record-common.sh"
lib_facts
[ "$SCOPE" = roadmap ] || { echo "$PROG: the session store is for roadmap scope" >&2; exit 64; }
lib_run_ref || { echo "$PROG: the run has no found record" >&2; exit 64; }
lib_write_guard
# The session the record moves into, and the run stamp its moved entry names.
MS=${RS_SESSION:-$SESSION}
[ -n "$MS" ] || { echo "$PROG: the move needs the run's session" >&2; exit 64; }
STAMP=${MS##*-}
[[ $STAMP =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || lib_die2 "the session's name carries no run stamp: $MS"

W=$(mktemp -d "${TMPDIR:-/tmp}/record-move.XXXXXX")
trap 'rm -rf "$W"' EXIT
step() { printf 'step=%s %s\n' "$1" "$2"; }
verdict() { # verdict <move-done|move-refused> <reason>
    if [ "$1" = move-done ]; then
        echo "move=done"
        exit 0
    fi
    echo "move=refused"
    echo "$PROG: refused: $2" >&2
    exit 65
}
# ghread: the GitHub record, read through the seam from the GitHub store.
ghread() {
    RS_READ_STORE=github rs_record "$W/gh" json --json state,body,url
    case $? in
        0) ;;
        2) lib_die2 "cannot read issue #$REF" ;;
        *) verdict move-refused "#$REF is not a canonical roadmap record for $NAME: $(lib_scrub < "$W/gh.err" | head -1)" ;;
    esac
    [ "$(jq -r '.state' "$W/gh.raw")" = OPEN ] || verdict move-refused "#$REF is not open"
}
# core_in <store> <body-file> [seed]: one write through the core, in a subshell
# (the core takes over the EXIT trap and exits on a refusal). Prints nothing;
# returns the core's status.
core_in() {
    ( BODY=$2 END= CLOSE=0
      . "$HERE/record-write-core.sh"
      MOVE_WRITER=1 CORE_STORE=$1
      [ "${3:-}" = seed ] && SESSION_SEED=1
      core_write > /dev/null )
}

ghread
jq -e 'any((.run // [])[]; .key == "store" and .value == "session")' "$W/gh" > /dev/null \
    || verdict move-refused "#$REF's Run section doesn't read store session; only the owner's row moves a record"

# 1. copy.
if "$KOTO" context exists "$MS" record/meta < /dev/null > /dev/null 2> "$W/k.err"; then
    step copy done-before
else
    HOLDERS=$(rs_scope_sessions "$SCOPE" "$NAME") || lib_die2 "cannot list this host's sessions"
    OTHER=$(printf '%s\n' "$HOLDERS" | grep -vxF -- "$MS" | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')
    [ -z "$OTHER" ] || verdict move-refused "session $OTHER on this host holds this scope's state, not this run's session $MS"
    rs_moved "$W/gh" && verdict move-refused "#$REF is already in the moved shape and no session here holds its state"
    cp "$W/gh.md" "$W/state.md"
    core_in session "$W/state.md" seed; rc=$?
    case $rc in
        0) step copy written ;;
        11) echo "$PROG: the copy into $MS failed part way; tick again to finish the move" >&2; exit 11 ;;
        *) verdict move-refused "the copy into $MS was refused (exit $rc)" ;;
    esac
fi

# 2. post.
RS_SOURCE=github bash "$HERE/record-append.sh" --scope "$SCOPE" --name "$NAME" --repo "$REPO" --ref "$REF" --list \
    > "$W/entries.json" 2> "$W/a.err" || lib_die2 "cannot read #$REF's entries: $(lib_scrub < "$W/a.err")"
if jq -e --arg s "$STAMP" 'any(.[]; .kind == "moved" and (.text | contains("run " + $s)))' "$W/entries.json" > /dev/null; then
    step post done-before
else
    printf 'Moved to the session store by run %s: the record'"'"'s state now lives in that run'"'"'s session, and this body keeps only its store row.\n' "$STAMP" > "$W/moved.txt"
    RS_SOURCE=github bash "$HERE/record-append.sh" --scope "$SCOPE" --name "$NAME" --repo "$REPO" --ref "$REF" \
        --kind moved --text-file "$W/moved.txt" > /dev/null 2> "$W/a.err" \
        || { echo "$PROG: the moved entry wasn't posted: $(lib_scrub < "$W/a.err"); tick again to finish the move" >&2; exit 11; }
    step post written
fi

# 3. rewrite.
ghread
if rs_moved "$W/gh"; then
    step rewrite done-before
else
    jq -c '{scope, holdings: [], deferrals: [], side_effects: [], reversals: [],
            run: [(.run // [])[] | select(.key == "store")]}' "$W/gh" \
        | bash "$HERE/record-render.sh" --container issue --written "$(jq -r '.written' "$W/gh")" > "$W/moved.md" 2> "$W/r.err" \
        || lib_die2 "the moved shape didn't render: $(lib_scrub < "$W/r.err")"
    core_in github "$W/moved.md"; rc=$?
    case $rc in
        0) step rewrite written ;;
        12) echo "$PROG: #$REF changed while the move rewrote it; tick again to finish the move" >&2; exit 11 ;;
        11) echo "$PROG: the rewrite of #$REF failed; tick again to finish the move" >&2; exit 11 ;;
        *) verdict move-refused "the rewrite of #$REF was refused (exit $rc)" ;;
    esac
fi
verdict move-done "#$REF moved onto session $MS"
