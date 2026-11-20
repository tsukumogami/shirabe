#!/usr/bin/env bash
# shared-rerun-record.sh -- does /execute's shared PR record every
# verification re-run its children carry?
# Part of the execute skill
#
# A gate script: pr_finalization's rerun_recorded gate runs it, and koto
# routes on its exit status. A /work-on child on the shared branch opens no PR
# of its own, so its pr_creation never runs the verification_rerun_recorded
# gate a standalone run passes; this is that gate for the PR the children
# share, run after the finalization edit, so it checks the body a reviewer
# reads. It is modelled on shared-deferral-record.sh, which does the same for
# verification deferrals. A coordinated run's node PR is the same kind of PR,
# shared by the node's work items: node-push.sh runs this with --lines to
# record the node's re-run lines and write them into a new node PR's body, and
# to check an adopted one before it pushes, and coordinated-next.sh (through
# coord-common.sh) runs it with --recorded before a node PR is evaluated or
# merged.
#
# Usage: shared-rerun-record.sh --session <execute session>
#            [--child <session>]... [--child-dir <dir>] [--recorded <line>]...
#            [--list | --lines | -- <owned-pr.sh arguments>]
#
# The children whose re-runs the PR must carry: each child with a
# `verification_attempts` context key holding at least one line (the ledger
# /work-on's run-verification.sh --archive writes, one JSON line per archived
# attempt). Without --child the children are the ones
# `koto workflows --children <session>` lists (a single-pr run's, which koto
# materializes). With --child they are exactly the sessions named, in order:
# a coordinated node's work items, which step agents open as root sessions,
# so no child listing finds them. A child without the key, or with an empty
# one, didn't re-run. A key koto can't read is no answer (2), never an empty
# ledger.
#
# --child-dir is the directory the --child sessions' koto reads run from: the
# node worktree a coordinated node's step agents opened them in. Under koto's
# cloud backend a session answers only in the directory it was opened in. The
# check-pr-output.sh run that follows reads the same sessions' ledgers again,
# so it runs from that directory too; it reads the owned PR through
# owned-pr.sh's --repo and the URL it answers, which don't depend on the
# directory. It is one directory for every --child in the call. Without it
# every read runs here. It needs --child.
#
# With --list the script prints the children that re-ran, one per line in the
# order above, and exits 0 without reading GitHub; nothing after --list is
# read.
#
# With --lines it prints the re-run lines the children's ledgers ask for, one
# per line, the children in the order above and each child's attempts in its
# ledger's order, the same line once, and exits 0 without reading GitHub;
# nothing after --lines is read. They are check-pr-output.sh --rerun-record
# --print's lines, in phase-6-pr.md's shape with each part the attempt has
# (12 hex of the head, the failed ids, the reason, the next attempt's
# result), so a body carrying them passes the check below. With no child that
# re-ran it prints nothing.
#
# --recorded <line>, once per line, gives the re-run lines as the run record
# holds them (run/node/<node>'s reruns, which node-push.sh wrote from --lines
# at push time), in place of reading the children: with it the script reads
# no child session at all, so coordinated-next.sh, which runs in the
# coordination checkout, never reads a work item's session from a directory
# koto's cloud backend refuses. The PR body is then checked with
# check-pr-output.sh --rerun-record --line, one per line, the same line once.
# It can't be given with --child, --child-dir or --list; with --lines it
# prints the recorded lines.
#
# Otherwise, with no child that re-ran the script exits 0 having read nothing
# from GitHub, so a run that never re-ran passes as it did before the gate
# existed. With one or more it runs /work-on's check-pr-output.sh
# --rerun-record over the owned PR, one --session per child that re-ran, so
# the PR body is checked against the same re-run lines, in the same shape, as
# a standalone run's (skills/work-on/references/phases/phase-6-pr.md):
#
#   Re-run attempt <n> at `<head>`: `<id>` failed; reason `<reason>`; attempt <n+1> passed.
#
# Unlike the deferral record, the workflow-content setting doesn't change
# this: under omit as under include the lines must be there.
#
# Time. koto stops a gate command at 30 seconds, and a stop is no answer, so
# the script answers 2 on its own first. It ends TOTAL_SECS (25) after it
# started:
#   - the child reads (the listing and up to two koto reads per child) run as
#     one polled job that must end LOOP_SECS (8) after the start. A run that
#     doesn't fit, or a koto that hangs, is exit 2, tick again;
#   - check-pr-output.sh then runs polled until TOTAL_SECS, and its own limit
#     on owned-pr.sh is cut from 20 seconds to what is left less 5, the 5 for
#     its own ledger reads and the gh read of the body after them.
# Each job is killed when its time is up. --list is bounded by LOOP_SECS
# alone; --lines, whose check-pr-output.sh --print reads the ledgers again,
# by TOTAL_SECS. With --recorded there are no child reads. The tests set SHARED_RERUN_RECORD_SECS and
# SHARED_RERUN_RECORD_LOOP_SECS to shorten the times; koto's cleared
# environment never passes them to a gate.
#
# Exit codes (the gate scripts' shared convention):
#   0  no child re-ran, or the PR body records every re-run (--list, --lines:
#      printed)
#   1  the PR body misses a re-run line or has a wrong one (stderr names each)
#   2  could not decide: a usage error, a koto read that failed, a recorded
#      line that spans lines, the child reads or the PR check running out of
#      time, or check-pr-output.sh's own 2 (a recorded line it can't read
#      among them)
#
# check-pr-output.sh is always /work-on's copy under the same plugin root,
# never one found on PATH. koto is the one on PATH, as for every gate.
#
# Requires: bash 3.2+, jq, koto. Written without `set -e`.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
CHECK_PR_OUTPUT="$HERE/../../work-on/scripts/check-pr-output.sh"

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

undecided() {
    echo "shared-rerun-record: $*" >&2
    exit 2
}

SESSION=""
LIST=0
LINES=0
CHILDREN=()
CHILD_DIR=""
RECORDED=()
SAW_RECORDED=0
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] && [ -n "$2" ] || usage; SESSION=$2; shift 2 ;;
        --child) [ $# -ge 2 ] && [ -n "$2" ] || usage; CHILDREN+=("$2"); shift 2 ;;
        --child-dir) [ $# -ge 2 ] && [ -n "$2" ] || usage; CHILD_DIR=$2; shift 2 ;;
        --recorded) [ $# -ge 2 ] && [ -n "$2" ] || usage; RECORDED+=("$2"); SAW_RECORDED=1; shift 2 ;;
        --list) LIST=1; shift; break ;;
        --lines) LINES=1; shift; break ;;
        --) shift; break ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
[ "$LIST" = 1 ] || [ "$LINES" = 1 ] || [ $# -gt 0 ] || usage
[ -z "$CHILD_DIR" ] || [ "${#CHILDREN[@]}" -gt 0 ] || usage
[ "$SAW_RECORDED" = 0 ] || { [ "${#CHILDREN[@]}" -eq 0 ] && [ -z "$CHILD_DIR" ] && [ "$LIST" = 0 ]; } || usage
[ -z "$CHILD_DIR" ] || [ -d "$CHILD_DIR" ] || undecided "--child-dir [$CHILD_DIR] is not a directory"
TOTAL_SECS=${SHARED_RERUN_RECORD_SECS:-25}
LOOP_SECS=${SHARED_RERUN_RECORD_LOOP_SECS:-8}
case "$TOTAL_SECS" in ''|*[!0-9]*|0) usage ;; esac
case "$LOOP_SECS" in ''|*[!0-9]*|0) usage ;; esac
[ "$LOOP_SECS" -lt "$TOTAL_SECS" ] || usage
command -v jq >/dev/null || undecided "jq is not on PATH"
# --recorded makes no koto call.
[ "$SAW_RECORDED" = 1 ] || command -v koto >/dev/null || undecided "koto is not on PATH"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/shared-rerun-record.XXXXXX") || undecided "cannot create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

# poll <pid> <end>: waits for the job <pid> until SECONDS reaches <end>, then
# kills it. Returns the job's status, or 124 when the time ran out. Job
# control and a sleep loop rather than GNU timeout, which the macOS floor
# lacks.
poll() {
    while kill -0 "$1" 2>/dev/null; do
        if [ "$SECONDS" -ge "$2" ]; then
            kill "$1" 2>/dev/null
            wait "$1" 2>/dev/null
            return 124
        fi
        sleep 0.1
    done
    wait "$1"
}

# collect_children: run as a background job. Prints the name of each child
# whose verification_attempts holds a line, one per line, in the children's
# order; a koto read that fails is undecided's message on stderr and exit 2.
# Both are the job's own (a subshell's exit ends only the job, and it doesn't
# inherit the EXIT trap), and the caller relays them. Each koto call runs in
# the background and is waited on, so the TERM poll sends when the time is up
# ends a hung call too.
collect_children() {
    local child rc first kpid=""
    trap '[ -z "$kpid" ] || kill "$kpid" 2>/dev/null; exit 143' TERM
    # koto_call <out> <koto arguments>...: one koto call, its stdout to <out>
    # and its stderr to koto.err, run in --child-dir when one was given (only
    # with --child, so the listing below never runs there). Returns koto's
    # status.
    koto_call() {
        local out=$1 st
        shift
        if [ -n "$CHILD_DIR" ]; then
            (CDPATH='' cd -- "$CHILD_DIR" && exec koto "$@") > "$out" 2> "$WORK/koto.err" < /dev/null &
        else
            koto "$@" > "$out" 2> "$WORK/koto.err" < /dev/null &
        fi
        kpid=$!
        wait "$kpid"
        st=$?
        kpid=""
        return "$st"
    }
    # koto_err: the last line koto wrote to stderr on the call just made.
    koto_err() { tail -n 1 "$WORK/koto.err"; }

    if [ "${#CHILDREN[@]}" -gt 0 ]; then
        printf '%s\n' "${CHILDREN[@]}" > "$WORK/children.txt"
    else
        koto_call "$WORK/children.json" workflows --children "$SESSION" \
            || undecided "koto workflows --children $SESSION failed: $(koto_err)"
        jq -e 'type == "array" and all(.[]; (.name | type) == "string")' "$WORK/children.json" >/dev/null \
            || undecided "koto workflows --children $SESSION did not answer a list of sessions"
        jq -r '.[].name' "$WORK/children.json" > "$WORK/children.txt"
    fi

    while IFS= read -r child; do
        [ -n "$child" ] || continue
        # A missing key is `koto context exists` exiting 1 with nothing on
        # stdout, as check-pr-output.sh reads it; anything else is no answer.
        koto_call "$WORK/exists" context exists "$child" verification_attempts
        rc=$?
        case "$rc" in
            0) ;;
            1) first=$(head -n 1 "$WORK/exists")
               [ ! -s "$WORK/exists" ] || undecided "koto context exists $child verification_attempts answered 1 with output: $first"
               continue ;;
            *) undecided "koto context exists $child verification_attempts failed (exit $rc): $(koto_err)" ;;
        esac
        koto_call "$WORK/ledger" context get "$child" verification_attempts \
            || undecided "koto context get $child verification_attempts failed: $(koto_err)"
        grep -q . "$WORK/ledger" || continue
        printf '%s\n' "$child"
    done < "$WORK/children.txt"
}

ARGS=()
if [ "$SAW_RECORDED" = 1 ]; then
    # The run record's lines stand in for the children: no koto read.
    LINES_SEEN=()
    for line in "${RECORDED[@]}"; do
        case "$line" in
            *$'\n'*|*$'\r'*) undecided "a recorded re-run line spans more than one line" ;;
        esac
        dup=0
        for l in ${LINES_SEEN[@]+"${LINES_SEEN[@]}"}; do
            [ "$l" != "$line" ] || { dup=1; break; }
        done
        [ "$dup" = 1 ] && continue
        LINES_SEEN+=("$line")
        ARGS+=(--line "$line")
    done
    if [ "$LINES" = 1 ]; then
        printf '%s\n' "${LINES_SEEN[@]}"
        exit 0
    fi
else
    collect_children > "$WORK/collected" 2> "$WORK/collect.err" < /dev/null &
    poll $! "$LOOP_SECS"
    case $? in
        0) ;;
        124) undecided "reading the children's verification_attempts took longer than the ${LOOP_SECS}s it had; tick again" ;;
        *) cat "$WORK/collect.err" >&2; exit 2 ;;
    esac
    RERAN=()
    while IFS= read -r child; do
        [ -n "$child" ] || continue
        RERAN+=("$child")
    done < "$WORK/collected"

    if [ "$LIST" = 1 ]; then
        [ "${#RERAN[@]}" -eq 0 ] || printf '%s\n' "${RERAN[@]}"
        exit 0
    fi

    if [ "${#RERAN[@]}" -eq 0 ]; then
        [ "$LINES" = 1 ] && exit 0
        echo "shared-rerun-record: no child re-ran verification in this run; nothing to record" >&2
        exit 0
    fi
    for c in "${RERAN[@]}"; do
        ARGS+=(--session "$c")
    done
fi

[ -x "$CHECK_PR_OUTPUT" ] || undecided "check-pr-output.sh not found at $CHECK_PR_OUTPUT"
# --lines has check-pr-output.sh print the children's lines; otherwise it
# checks the owned PR's body.
if [ "$LINES" = 1 ]; then
    ARGS+=(--print)
else
    ARGS+=(--owned "$@")
fi
# SECONDS counts from the script's start, so the child reads are spent too.
OWNED_SECS=$((TOTAL_SECS - SECONDS - 5))
[ "$OWNED_SECS" -le 20 ] || OWNED_SECS=20
[ "$OWNED_SECS" -ge 1 ] \
    || undecided "no time left of the ${TOTAL_SECS}s to run check-pr-output.sh after reading the children; tick again"
# With --child-dir, check-pr-output.sh's own ledger reads run in that
# directory too, so it is started from there.
if [ -n "$CHILD_DIR" ]; then
    (CDPATH='' cd -- "$CHILD_DIR" && export CHECK_PR_OUTPUT_OWNED_TIMEOUT=$OWNED_SECS \
        && exec "$CHECK_PR_OUTPUT" --rerun-record "${ARGS[@]}") \
        > "$WORK/check.out" 2> "$WORK/check.err" < /dev/null &
else
    CHECK_PR_OUTPUT_OWNED_TIMEOUT=$OWNED_SECS \
        "$CHECK_PR_OUTPUT" --rerun-record "${ARGS[@]}" \
        > "$WORK/check.out" 2> "$WORK/check.err" < /dev/null &
fi
poll $! "$TOTAL_SECS"
rc=$?
cat "$WORK/check.out"
cat "$WORK/check.err" >&2
[ "$rc" -ne 124 ] || undecided "check-pr-output.sh did not answer within the ${TOTAL_SECS}s this check has; tick again"
exit "$rc"
