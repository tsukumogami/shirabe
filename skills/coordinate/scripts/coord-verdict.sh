#!/usr/bin/env bash
# coord-verdict.sh -- the gate every /coordinate check state routes on.
#
# A check state's default action prints one sealed verdict token, which the
# engine captures; its one gate runs this script over the substituted capture.
# The script checks the seal against the session log (the token must come
# from the latest entry into this state) and exits with the verdict word's
# code from the fixed table below. Each code has its own `when` arm in
# coordinate.md; a code with no arm leaves the state gate-blocked.
#
# Usage: coord-verdict.sh --session S --state ST --capture "<token> sealed:<seq>:<hash>"
# Exit codes: the verdict's code (10 and up); 1 the seal is invalid or stale;
# 2 the log can't be read; 3 an unknown verdict word; 64 usage.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= STATE= CAPTURE=
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || exit 64; SESSION=$2; shift 2 ;;
        --state) [ $# -ge 2 ] || exit 64; STATE=$2; shift 2 ;;
        --capture) [ $# -ge 2 ] || exit 64; CAPTURE=$2; shift 2 ;;
        *) exit 64 ;;
    esac
done
[ -n "$SESSION" ] && [ -n "$STATE" ] && [ -n "$CAPTURE" ] || exit 64

bash "$HERE/coord-log.sh" check --session "$SESSION" --state "$STATE" --sealed "$CAPTURE" >/dev/null
rc=$?
[ $rc -eq 0 ] || exit $(( rc == 2 ? 2 : 1 ))

WORD=${CAPTURE%% *}
case "$WORD" in
    # record_find
    found) exit 10 ;; none) exit 11 ;; stale-branch) exit 12 ;; unopened) exit 13 ;;
    foreign) exit 14 ;; ambiguous) exit 15 ;; malformed) exit 16 ;; unauthorized) exit 17 ;;
    predecessor) exit 18 ;;
    # start, start_posture
    active) exit 20 ;; discipline) exit 21 ;; not-active) exit 22 ;;
    readable) exit 25 ;; unread) exit 26 ;;
    # pick_facts
    pick) exit 30 ;; scope-complete) exit 31 ;; rotation-over) exit 32 ;;
    # dispatch_check
    ok) exit 40 ;; deferral-open) exit 41 ;; record-changed) exit 42 ;; at-cap) exit 43 ;;
    # record, verified_confirm ("waiting" has no code: the state stays blocked)
    confirmed) exit 50 ;; conflict) exit 52 ;; moved) exit 53 ;; directed) exit 54 ;;
    # report_facts
    holding) exit 60 ;; unknown) exit 61 ;; refused) exit 62 ;;
    # verify_board
    verified) exit 70 ;; unverified) exit 71 ;; pending) exit 72 ;;
    # land
    permit) exit 80 ;; deny) exit 81 ;; confirm) exit 82 ;; dirty) exit 84 ;;
    # merge_confirm, merged_facts
    merged) exit 90 ;; unconfirmed) exit 91 ;; not-merged) exit 92 ;;
    # quiet_check
    quiet-none) exit 100 ;; first-silence) exit 101 ;; second-silence) exit 102 ;;
    # predecessor_handoff
    rendered) exit 110 ;; unparseable) exit 111 ;;
    # rotation_close, predecessor_close
    handoff-missing) exit 120 ;; title-stale) exit 121 ;; land) exit 122 ;;
    handed-over) exit 124 ;; closed-unmerged) exit 125 ;;
    # roadmap_close
    ready) exit 130 ;; features-open) exit 131 ;; holdings) exit 132 ;;
    side-effects) exit 133 ;; deferrals) exit 134 ;; closed) exit 135 ;;
    # reconcile (reserved for the reconcile feature's sealed pass)
    reconciled) exit 140 ;;
    *) exit 3 ;;
esac
