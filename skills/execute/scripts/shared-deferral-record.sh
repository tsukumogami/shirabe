#!/usr/bin/env bash
# shared-deferral-record.sh -- does /execute's shared PR record every
# verification deferral its run carries?
# Part of the execute skill
#
# A gate script: pr_finalization's deferral_recorded gate runs it, and koto
# routes on its exit status. A /work-on child on the shared branch opens no PR
# of its own, so its pr_creation never runs the verification_deferral_recorded
# gate a standalone run passes; this is that gate for the PR the children
# share.
#
# Usage: shared-deferral-record.sh --session <execute session>
#            --verification <local|hosted-ci|""> [--reason <reason>]
#            -- <owned-pr.sh arguments>
#
# The reasons the PR must carry, each once:
#
#   - the run's own, when --verification is hosted-ci: the reason execute.md's
#     VERIFICATION_DEFERRAL_REASON holds and spawn_and_await gave every child.
#     It counts even when a child's session is gone.
#   - every child's `verification_deferral` context key, which /work-on's
#     verification_deferred writes when a child defers. The children are the
#     ones `koto workflows --children <session>` lists; a child without the
#     key didn't defer. This catches a child that deferred without the run's
#     variable (a task built by hand).
#
# With no reason the script exits 0 having read nothing from GitHub, so a run
# that deferred nothing passes as it did before the gate existed. Otherwise it
# runs /work-on's check-pr-output.sh --deferral-record over the owned PR, one
# --reason per reason, so the PR body is checked against the same three parts,
# in the same words, as a standalone run's: a line saying local verification
# did not run, each reason verbatim, and a line saying hosted CI is the build
# of record (skills/work-on/references/phases/phase-6-pr.md).
#
# Exit codes (the gate scripts' shared convention):
#   0  no deferral, or the PR body records every reason
#   1  the PR body misses a part (stderr names each)
#   2  could not decide: a usage error, hosted-ci with no reason, a koto read
#      that failed, a child's key that is empty, or check-pr-output.sh's own 2
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
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --verification) [ $# -ge 2 ] || usage; VERIFICATION=$2; SAW_VERIFICATION=1; shift 2 ;;
        --reason) [ $# -ge 2 ] || usage; RUN_REASON=$2; shift 2 ;;
        --) shift; break ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] && [ "$SAW_VERIFICATION" = 1 ] && [ $# -gt 0 ] || usage
case "$VERIFICATION" in
    ""|local|hosted-ci) ;;
    *) undecided "--verification must be local or hosted-ci, got [$VERIFICATION]" ;;
esac
command -v jq >/dev/null 2>&1 || undecided "jq is not on PATH"
command -v koto >/dev/null 2>&1 || undecided "koto is not on PATH"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/shared-deferral-record.XXXXXX") || undecided "cannot create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

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

koto workflows --children "$SESSION" > "$WORK/children.json" 2> "$WORK/koto.err" < /dev/null \
    || undecided "koto workflows --children $SESSION failed: $(tail -n 1 "$WORK/koto.err")"
jq -e 'type == "array" and all(.[]; (.name | type) == "string")' "$WORK/children.json" >/dev/null \
    || undecided "koto workflows --children $SESSION did not answer a list of sessions"
jq -r '.[].name' "$WORK/children.json" > "$WORK/children.txt"

while IFS= read -r child; do
    [ -n "$child" ] || continue
    koto context exists "$child" verification_deferral > /dev/null 2> "$WORK/koto.err" < /dev/null
    rc=$?
    case "$rc" in
        0) ;;
        1) continue ;;
        *) undecided "koto context exists $child verification_deferral failed (exit $rc): $(tail -n 1 "$WORK/koto.err")" ;;
    esac
    koto context get "$child" verification_deferral > "$WORK/reason" 2> "$WORK/koto.err" < /dev/null \
        || undecided "koto context get $child verification_deferral failed: $(tail -n 1 "$WORK/koto.err")"
    reason=$(cat "$WORK/reason")
    [ -n "$reason" ] || undecided "$child recorded an empty verification_deferral"
    add_reason "$reason"
done < "$WORK/children.txt"

if [ "${#REASONS[@]}" -eq 0 ]; then
    echo "shared-deferral-record: no deferral in this run; nothing to record" >&2
    exit 0
fi

[ -x "$CHECK_PR_OUTPUT" ] || undecided "check-pr-output.sh not found at $CHECK_PR_OUTPUT"
ARGS=()
for r in "${REASONS[@]}"; do
    ARGS+=(--reason "$r")
done
"$CHECK_PR_OUTPUT" --deferral-record "${ARGS[@]}" --owned "$@" < /dev/null
exit $?
