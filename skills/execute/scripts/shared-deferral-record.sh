#!/usr/bin/env bash
# shared-deferral-record.sh -- does /execute's shared PR, or a coordinated
# node PR, record every verification deferral its children carry?
# Part of the execute skill
#
# A gate script: pr_finalization's deferral_recorded gate runs it, and koto
# routes on its exit status. A /work-on child on the shared branch opens no PR
# of its own, so its pr_creation never runs the verification_deferral_recorded
# gate a standalone run passes; this is that gate for the PR the children
# share. A coordinated run's node PR is the same kind of PR, shared by the
# node's work items: node-push.sh runs this with --list to write the record
# into a new node PR's body and to check an adopted one before it pushes, and
# coordinated-next.sh (through coord-common.sh) runs it before a node PR is
# evaluated or merged.
#
# Usage: shared-deferral-record.sh --session <execute session>
#            --verification <local|hosted-ci|""> [--reason <reason>]
#            [--child <session>]... [--list | -- <owned-pr.sh arguments>]
#
# The reasons the PR must carry, each once:
#
#   - the run's own, when --verification is hosted-ci: the reason the run's
#     VERIFICATION_DEFERRAL_REASON holds and every child was given. It counts
#     even when a child's session is gone.
#   - every child's `verification_deferral` context key, which /work-on's
#     verification_deferred writes when a child defers. Without --child the
#     children are the ones `koto workflows --children <session>` lists (a
#     single-pr run's, which koto materializes). With --child they are exactly
#     the sessions named, in order: a coordinated node's work items, which
#     step agents open as root sessions, so no child listing finds them. A
#     child without the key, or a named session that doesn't exist, didn't
#     defer. This catches a child that deferred without the run's variable (a
#     task built by hand).
#
# With --list the script prints the reasons, one per line in the order above,
# and exits 0 without reading GitHub; nothing after --list is read. koto's
# value allowlist keeps a reason to one line.
#
# Otherwise, with no reason the script exits 0 having read nothing from
# GitHub, so a run that deferred nothing passes as it did before the gate
# existed. With one or more it runs /work-on's check-pr-output.sh
# --deferral-record over the owned PR, one --reason per reason, so the PR body
# is checked against the same three parts, in the same words, as a standalone
# run's: a line saying local verification did not run, a line reading exactly
# `Reason: <reason>` for each reason, and a line saying hosted CI is the build
# of record (skills/work-on/references/phases/phase-6-pr.md). That check
# reads the switch this run recorded at its open (check-pr-output.sh
# --session <session>, scripts/pr-workflow-content.sh --session): under
# omit, the default, it passes without reading GitHub, and the children's
# context keys are the record. A coordinated node PR is read the same way.
#
# Time. koto stops a gate command at 30 seconds, and a stop is no answer, so
# the script answers 2 on its own first. It ends TOTAL_SECS (25) after it
# started, leaving the rest of koto's 30 for the koto and run-id.sh reads the
# gate command makes before it starts:
#   - the child reads (the listing and two koto reads per child) run as one
#     polled job that must end LOOP_SECS (8) after the start. One koto read
#     measured about 0.07 s on an idle development host, which would fit
#     some fifty children; a loaded host fits fewer. A run that doesn't fit,
#     or a koto that hangs, is exit 2, tick again;
#   - check-pr-output.sh then runs polled until TOTAL_SECS, and its own limit
#     on owned-pr.sh is cut from 20 seconds to what is left less 5, the 5 for
#     the gh read of the body after it.
# Each job is killed when its time is up, the child reads' hung koto call
# with it. A check-pr-output.sh killed this way can leave its own gh or
# owned-pr.sh call to end by itself, as koto's stop of the gate did before;
# that call writes only to check-pr-output.sh's own temporary files, so it
# holds none of this script's output open. --list is bounded by LOOP_SECS
# alone. The limits hold for every caller, not only the gate: node-push.sh
# (its --list and its check of an adopted node PR) and coord-common.sh get
# the same exit 2 where they used to wait on a stuck koto or GitHub read. The tests set SHARED_DEFERRAL_RECORD_SECS and
# SHARED_DEFERRAL_RECORD_LOOP_SECS to shorten the times; koto's cleared
# environment never passes them to a gate.
#
# Exit codes (the gate scripts' shared convention):
#   0  no deferral, or the PR body records every reason (--list: listed)
#   1  the PR body misses a part (stderr names each)
#   2  could not decide: a usage error, hosted-ci with no reason, a koto read
#      that failed, a child's key that is empty or spans lines, the child
#      reads or the PR check running out of time, or check-pr-output.sh's own 2
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
    echo "shared-deferral-record: $*" >&2
    exit 2
}

SESSION=""
VERIFICATION=""
RUN_REASON=""
SAW_VERIFICATION=0
LIST=0
CHILDREN=()
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --verification) [ $# -ge 2 ] || usage; VERIFICATION=$2; SAW_VERIFICATION=1; shift 2 ;;
        --reason) [ $# -ge 2 ] || usage; RUN_REASON=$2; shift 2 ;;
        --child) [ $# -ge 2 ] && [ -n "$2" ] || usage; CHILDREN+=("$2"); shift 2 ;;
        --list) LIST=1; shift; break ;;
        --) shift; break ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] && [ "$SAW_VERIFICATION" = 1 ] || usage
[ "$LIST" = 1 ] || [ $# -gt 0 ] || usage
case "$VERIFICATION" in
    ""|local|hosted-ci) ;;
    *) undecided "--verification must be local or hosted-ci, got [$VERIFICATION]" ;;
esac
TOTAL_SECS=${SHARED_DEFERRAL_RECORD_SECS:-25}
LOOP_SECS=${SHARED_DEFERRAL_RECORD_LOOP_SECS:-8}
case "$TOTAL_SECS" in ''|*[!0-9]*|0) usage ;; esac
case "$LOOP_SECS" in ''|*[!0-9]*|0) usage ;; esac
[ "$LOOP_SECS" -lt "$TOTAL_SECS" ] || usage
command -v jq >/dev/null || undecided "jq is not on PATH"
command -v koto >/dev/null || undecided "koto is not on PATH"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/shared-deferral-record.XXXXXX") || undecided "cannot create a temporary directory"
trap 'rm -rf "$WORK"' EXIT
NL='
'

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

# collect_children: run as a background job. Prints the reason of each child
# that deferred, one per line, in the children's order; a koto read that
# fails, or a key that is empty or spans lines, is undecided's message on
# stderr and exit 2. Both are the job's own (a subshell's exit ends only the
# job, and it doesn't inherit the EXIT trap), and the caller relays them.
# --list never reaches check-pr-output.sh's one-line check, so a key that
# spans lines is refused here. Each koto call runs in the background and is
# waited on, so the TERM poll sends when the time is up ends a hung call too,
# rather than leaving it running after this job is gone (bash runs a trap
# during `wait`, but only after a foreground child exits).
collect_children() {
    local child rc reason kpid=""
    trap '[ -z "$kpid" ] || kill "$kpid" 2>/dev/null; exit 143' TERM
    # koto_call <out> <koto arguments>...: one koto call, its stdout to <out>
    # and its stderr to koto.err. Returns koto's status. kpid is cleared once
    # the call ends, so the trap never kills a PID that may have been reused.
    koto_call() {
        local out=$1 st
        shift
        koto "$@" > "$out" 2> "$WORK/koto.err" < /dev/null &
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
        koto_call /dev/null context exists "$child" verification_deferral
        rc=$?
        case "$rc" in
            0) ;;
            1) continue ;;
            *) undecided "koto context exists $child verification_deferral failed (exit $rc): $(koto_err)" ;;
        esac
        koto_call "$WORK/reason" context get "$child" verification_deferral \
            || undecided "koto context get $child verification_deferral failed: $(koto_err)"
        reason=$(cat "$WORK/reason")
        [ -n "$reason" ] || undecided "$child recorded an empty verification_deferral"
        case "$reason" in
            *"$NL"*|*$'\r'*) undecided "$child recorded a verification_deferral over more than one line" ;;
        esac
        printf '%s\n' "$reason"
    done < "$WORK/children.txt"
}

REASONS=()
# add_reason <reason>: keeps the first occurrence of each reason.
add_reason() {
    local r
    for r in ${REASONS[@]+"${REASONS[@]}"}; do
        [ "$r" != "$1" ] || return 0
    done
    REASONS+=("$1")
}

if [ "$VERIFICATION" = hosted-ci ]; then
    [ -n "$RUN_REASON" ] || undecided "the run defers verification to hosted CI with no reason; nothing to check the PR body against"
    add_reason "$RUN_REASON"
fi

collect_children > "$WORK/collected" 2> "$WORK/collect.err" < /dev/null &
poll $! "$LOOP_SECS"
case $? in
    0) ;;
    124) undecided "reading the children's verification_deferral took longer than the ${LOOP_SECS}s it had; tick again" ;;
    *) cat "$WORK/collect.err" >&2; exit 2 ;;
esac
while IFS= read -r reason; do
    add_reason "$reason"
done < "$WORK/collected"

if [ "$LIST" = 1 ]; then
    [ "${#REASONS[@]}" -eq 0 ] || printf '%s\n' "${REASONS[@]}"
    exit 0
fi

if [ "${#REASONS[@]}" -eq 0 ]; then
    echo "shared-deferral-record: no deferral in this run; nothing to record" >&2
    exit 0
fi

[ -x "$CHECK_PR_OUTPUT" ] || undecided "check-pr-output.sh not found at $CHECK_PR_OUTPUT"
ARGS=()
for r in "${REASONS[@]}"; do
    ARGS+=(--reason "$r")
done
# SECONDS counts from the script's start, so the child reads are spent too.
OWNED_SECS=$((TOTAL_SECS - SECONDS - 5))
[ "$OWNED_SECS" -le 20 ] || OWNED_SECS=20
[ "$OWNED_SECS" -ge 1 ] \
    || undecided "no time left of the ${TOTAL_SECS}s to check the PR body after reading the children; tick again"
CHECK_PR_OUTPUT_OWNED_TIMEOUT=$OWNED_SECS \
    "$CHECK_PR_OUTPUT" --deferral-record --session "$SESSION" "${ARGS[@]}" --owned "$@" \
    > "$WORK/check.out" 2> "$WORK/check.err" < /dev/null &
poll $! "$TOTAL_SECS"
rc=$?
cat "$WORK/check.out"
cat "$WORK/check.err" >&2
[ "$rc" -ne 124 ] || undecided "check-pr-output.sh did not answer within the ${TOTAL_SECS}s this check has; tick again"
exit "$rc"
