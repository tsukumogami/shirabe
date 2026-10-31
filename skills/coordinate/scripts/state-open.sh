#!/usr/bin/env bash
# state-open.sh -- open this scope's coordinator record, exactly once, in the
# run's own koto session. Agent-run, from the directive of state record_open;
# never a default action.
#
# The record lives in the coordinator's session
# (docs/designs/current/DESIGN-coordinator-record-teardown.md): record/meta and
# one key per section, written through the write core's seeding write. A new
# record is the scope's empty record (its four sections empty, no other
# section), which this script builds itself. A session that already holds a
# record is refused (exit 10), so a record is never opened twice; a seed cut
# short left record/meta pending with no written time, and opening again
# finishes it.
#
# Roadmap scope: the empty record is seeded into the session. Nothing is
# written on GitHub. It prints record=<session>.
#
# Discipline scope, after the find sealed `first`: the empty record of the
# discipline is seeded the same way, then state-stored-set.sh --rotation writes
# record/rotation, {start, end, host_repo, predecessor: null}. It prints
# record=<session>.
#
# --carry is predecessor_carry's step, agent-run like every write, after the
# find sealed `predecessor <session>`. It builds this rotation's first state
# from the predecessor's session: Holdings, Deferrals, Side effects,
# Reversals, Holds, Run, Standing, Work, the unsettled Decisions entries and
# the next decision number. The state is seeded through the write core like
# any write (its checks, its JSON validation), and record/rotation names the
# predecessor, the window today to today plus ROTATION_DAYS less one. The carry
# report, the predecessor and the holds and Standing rows it carried, goes to
# coord/predecessor_carry.json and stdout, then `carried=<predecessor>` (exit
# 0), or `refused` with the reason on stderr and in the report (exit 65). A
# carry run again after it landed reads as carried; one cut short is seeded
# again.
#
# After each seed it makes (a roadmap's record, a first rotation, a carry),
# it writes the Run section's `rules` digests of the files this session
# loaded as rules: rule-files.sh lists them from this plugin's root and the
# working directory, and state-stored-set.sh --rule-files writes them --by the
# run's session name, as coordinate-open.sh does at a start that finds a
# record. A failed digest write never fails the seed: it prints
# `warning=rules-unrecorded` after record= (or carried=), the reason on
# stderr, and the next start writes them. With the test override flags it
# writes none.
#
# Usage:
#   state-open.sh --session S [--start YYYY-MM-DD --end YYYY-MM-DD]
#   state-open.sh --session S --carry
#   state-open.sh --scope roadmap|discipline --name N --repo O/R
#                  --skip-session-checks [...]                        (tests)
#
# --start and --end are required at discipline scope and refused at roadmap
# scope. Before any read, the session must pass `coord-log.sh provenance` and
# show no directed transition in the run.
#
# Exit codes: 0 opened (prints record=<session>); 10 refused (the session holds
# a record already, provenance, or a directed transition); 2 a read failed; 64
# usage; 65 refused (an end before the start); a failed seed exits with the
# write core's code (10, 11, 12 or 65), and a failed window write with
# state-stored-set.sh's. --carry exits 0 carried, 65 refused, 2 a read failed.
#
# It makes no GitHub call of its own; the write core reads repository
# visibility.
set -uo pipefail

PROG=state-open
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= START= END=
SKIP_CHECKS=0 CARRY=0 NO_SEAL=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --start) [ $# -ge 2 ] || usage; START=$2; shift 2 ;;
        --end) [ $# -ge 2 ] || usage; END=$2; shift 2 ;;
        --carry) CARRY=1; shift ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
if [ "$CARRY" = 1 ]; then
    [ -n "$SESSION" ] && [ -z "$START$END$SCOPE$NAME$REPO" ] || usage
fi
. "$HERE/state-common.sh"
lib_facts
[ "$CARRY" = 0 ] || [ "$SCOPE" = discipline ] || usage

# rules_record: the Run rules digests of the files this session loaded as
# rules, written into the run's session once a seed has given it a record. A
# failure prints warning=rules-unrecorded, the reason on stderr, and returns 0.
rules_record() {
    local d
    [ "$OVERRIDE" = 1 ] && return 0
    d=$(mktemp -d "${TMPDIR:-/tmp}/state-open-rules.XXXXXX") || {
        echo "warning=rules-unrecorded"; echo "$PROG: $SESSION's rules digests weren't written: no scratch directory; the next start writes them" >&2
        return 0
    }
    if ! bash "$HERE/rule-files.sh" --plugin-root "$HERE/../../.." < /dev/null > "$d/files"; then
        echo "warning=rules-unrecorded"
        echo "$PROG: $SESSION's rules digests weren't written: the rule files couldn't be listed; the next start writes them" >&2
    elif ! bash "$HERE/state-stored-set.sh" --session "$SESSION" --rule-files "$d/files" --by "$SESSION" < /dev/null > /dev/null 2> "$d/err"; then
        echo "warning=rules-unrecorded"
        echo "$PROG: $SESSION's rules digests weren't written: $(tr -s '\t\n' '  ' < "$d/err" | head -c 400); the next start writes them" >&2
    fi
    rm -rf "$d"
}

# rotation_write <start> <end> <predecessor-or-empty>: record/rotation for this
# run's rotation, through state-stored-set.sh (its writer). Exits with its code on a
# refusal.
rotation_write() {
    jq -n -c --arg s "$1" --arg e "$2" --arg h "$REPO" --arg p "$3" \
        '{start: $s, end: $e, host_repo: $h, predecessor: (if $p == "" then null else $p end)}' > "$T/rotation.json" \
        || lib_die2 "jq failed"
    bash "$HERE/state-stored-set.sh" --session "$SESSION" --rotation "$T/rotation.json" > /dev/null
}

if [ "$CARRY" = 1 ]; then
    T=$(mktemp -d "${TMPDIR:-/tmp}/state-open.XXXXXX") || lib_die2 "cannot make a temporary directory"
    trap 'rm -rf "$T"' EXIT
    TOKEN=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name RECORD_FIND --state record_find --any-visit 2>/dev/null) \
        || lib_die2 "the run's find sealed no verdict"
    PRED=${TOKEN% sealed:*}
    case "$PRED" in "predecessor "*) PRED=${PRED#predecessor } ;; *) lib_die2 "the run's find sealed no predecessor: ${TOKEN% sealed:*}" ;; esac
    lib_slug
    # carry_report <verdict> <reason> [<state-file>]: the report into
    # coord/predecessor_carry.json and on stdout, then carried=<predecessor>
    # (exit 0) or refused (exit 65, the reason on stderr).
    carry_report() {
        local st=${3:-}
        [ -n "$st" ] || { echo '{}' > "$T/empty.json"; st="$T/empty.json"; }
        jq -c --arg v "$1" --arg r "$2" --arg p "$PRED" '{verdict: $v, predecessor: $p, reason: $r,
            holds: [(.holds // [])[] | {hold, on, until, set_by}],
            standing: [(.standing // [])[] | {standing, kind, owner}]}' "$st" > "$T/report.json" || lib_die2 "jq failed"
        "$KOTO" context add "$SESSION" coord/predecessor_carry.json --from-file "$T/report.json" < /dev/null > /dev/null 2> "$T/k.err" \
            || lib_die2 "koto context add coord/predecessor_carry.json failed: $(lib_scrub < "$T/k.err")"
        cat "$T/report.json"
        if [ "$1" = carried ]; then
            echo "carried=$PRED"
            [ "${SEEDED:-0}" = 0 ] || rules_record
            exit 0
        fi
        echo "refused"
        echo "$PROG: refused: $2" >&2
        exit 65
    }
    # A carry that already landed: this run holds the rotation, naming PRED.
    if rs_rotation "$SESSION" "$T/mine" 2> /dev/null; then
        if [ "$(jq -r '.predecessor // ""' "$T/mine")" = "$PRED" ]; then
            rs_session_state "$SESSION" "$T/landed" > /dev/null 2>&1 || lib_die2 "cannot read this run's rotation"
            carry_report carried "the carry had landed" "$T/landed"
        fi
        carry_report refused "this run already holds a rotation that names another predecessor"
    fi
    # The predecessor's state, as JSON.
    [[ $PRED =~ ^coordinate-${SLUG}-[0-9]{8}T[0-9]{6}Z$ ]] \
        || carry_report refused "the predecessor $PRED is not a session of this discipline"
    rs_session_state "$PRED" "$T/pred"
    case $? in
        0) ;;
        4|12) carry_report refused "$PRED holds no readable record: $(lib_scrub < "$T/pred.err" | head -1)" ;;
        *) lib_die2 "cannot read $PRED's record: $(lib_scrub < "$T/pred.err")" ;;
    esac
    jq -e --arg n "$NAME" '.scope == {kind: "discipline", name: $n}' "$T/pred" > /dev/null \
        || carry_report refused "$PRED's record is not this discipline's"
    # This rotation's first state: the predecessor's sections and its unsettled
    # decisions under the same next number.
    jq -c --arg n "$NAME" '{scope: {kind: "discipline", name: $n},
            holdings: (.holdings // []), deferrals: (.deferrals // []),
            side_effects: (.side_effects // []), reversals: (.reversals // [])}
        + (if (.holds // []) == [] then {} else {holds: .holds} end)
        + (if (.run // []) == [] then {} else {run: .run} end)
        + (if (.standing // []) == [] then {} else {standing: .standing} end)
        + (if (.work // []) == [] then {} else {work: .work} end)
        + (if .decisions == null then {}
           else {decisions: {next: .decisions.next, entries: [(.decisions.entries // [])[] | select(.state != "settled")]}} end)
        | .holdings |= map(del(.pushed_head))' "$T/pred" > "$T/next.json" || lib_die2 "jq failed"
    chmod 600 "$T/next.json" || lib_die2 "cannot make the state file private"
    lib_write_guard
    # The core takes over T and its EXIT trap, so it runs in a subshell: its
    # refusal, a state that breaks a rule among them, becomes this carry's
    # `refused`, sealed below.
    if ! ( STATE_FILE="$T/next.json"
           . "$HERE/state-write-core.sh"
           SESSION_SEED=1
           core_write > /dev/null ) 2> "$T/seed.err"; then
        carry_report refused "the carry's write was refused: $(lib_scrub < "$T/seed.err" | head -2 | tr '\n' ' ')" "$T/next.json"
    fi
    TODAY=$(date -u +%Y-%m-%d)
    DAYS=$(bash "$HERE/coord-log.sh" vars --session "$SESSION" | jq -r '.ROTATION_DAYS // "7"')
    [[ $DAYS =~ ^[1-9][0-9]{0,2}$ ]] || DAYS=7
    ENDD=$(jq -rn --arg d "$TODAY" --argjson n "$DAYS" '$d | strptime("%Y-%m-%d") | mktime + (($n - 1) * 86400) | strftime("%Y-%m-%d")') \
        || lib_die2 "cannot compute the rotation's end"
    if ! rotation_write "$TODAY" "$ENDD" "$PRED" 2> "$T/rot.err"; then
        carry_report refused "the rotation's window wasn't written: $(lib_scrub < "$T/rot.err" | head -1)" "$T/next.json"
    fi
    SEEDED=1
    carry_report carried "carried from $PRED" "$T/next.json"
fi

if [ "$SCOPE" = discipline ]; then
    lib_valid_date "$START" && lib_valid_date "$END" || usage
    if [ "$END" \< "$START" ]; then echo "$PROG: refused: the end date $END is before the start $START" >&2; exit 65; fi
else
    [ -z "$START$END" ] || usage
fi
lib_write_guard

T=$(mktemp -d "${TMPDIR:-/tmp}/state-open.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT

# The scope's empty record. It opens with no Decisions section: entries are
# written, and a predecessor's are carried in, only by state-decision.sh,
# which checks each one.
jq -nc --arg k "$SCOPE" --arg n "$NAME" '{scope: {kind: $k, name: $n}, holdings: [], deferrals: [], side_effects: [], reversals: []}' \
    > "$T/seed.json" || lib_die2 "jq failed"
chmod 600 "$T/seed.json" || lib_die2 "cannot make the state file private"

# Exactly once: a session holding a record is refused, unless all it holds is
# the pending record/meta of a seed cut short, which seeding again finishes.
OPEN_S=${RS_SESSION:-$SESSION}
[ -n "$OPEN_S" ] || lib_die2 "the record needs the run's session"
rs_key "$OPEN_S" record/meta "$T/meta"
case $? in
    1) ;;
    0) jq -e '.pending == true and .written == ""' "$T/meta" > /dev/null \
           || { echo "$PROG: refused: session $OPEN_S already holds a record" >&2; exit 10; } ;;
    *) lib_die2 "cannot read session $OPEN_S's record/meta: $(lib_scrub < "$T/meta.err")" ;;
esac

# The record is seeded into this run's session through the write core. The
# core takes over T and its EXIT trap; it removes this script's own scratch
# directory as CORE_CLEANUP, so a discipline rotation's window is written from
# a directory of its own.
ROT_T=$(mktemp -d "${TMPDIR:-/tmp}/state-open-rot.XXXXXX") || lib_die2 "cannot make a temporary directory"
( STATE_FILE="$T/seed.json" CORE_CLEANUP=$T
  . "$HERE/state-write-core.sh"
  SESSION_SEED=1
  core_write > /dev/null ) || { RC=$?; rm -rf "$ROT_T"; exit $RC; }
T=$ROT_T
trap 'rm -rf "$T"' EXIT
if [ "$SCOPE" = discipline ]; then
    rotation_write "$START" "$END" "" || exit $?
fi
echo "record=$OPEN_S"
rules_record
exit 0
