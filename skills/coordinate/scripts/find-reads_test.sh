#!/usr/bin/env bash
# find-reads_test.sh -- the reads record-find.sh makes at discipline scope
# (shirabe#1141), counted through the gh and koto stand-ins.
#
# Covers: a discipline's first rotation, a predecessor session and this run's
# own rotation each make no GitHub read, the record being the session's alone;
# a first rotation lists the sessions once and makes the same koto reads each
# time it runs.
#
# Usage: bash skills/coordinate/scripts/find-reads_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
# The session store's koto features, for the find's probe.
export KOTO_FEATURES=1
db_init

day() { jq -rn --argjson n "$1" 'now + ($n * 86400) | strftime("%Y-%m-%d")'; }
TODAY=$(date -u +%Y-%m-%d)
YESTERDAY=$(day -1)
WEEK_AGO=$(day -7)
TOMORROW=$(day 1)

empty_record() { record_json discipline "$1" | jq -c '. + {written: "2026-09-26T09:00:00Z"}'; }
sealed() {
    log_to "$1" start_posture record_find 2026-09-26T08:01:00.000Z
    log_capture "$1" RECORD_FIND "$(bash "$HERE/coord-log.sh" seal --session "$1" --state record_find --token "$2")" 2026-09-26T08:01:00.000Z
}
# rotation <session> <discipline> <start> <end>: a rotation on the session store.
rotation() {
    log_new "$1" "$(discipline_vars "$2")"
    sealed "$1" found
    empty_record "$2" > "$T/rs.json"
    session_keys "$1" "$T/rs.json"
    jq -nc --arg s "$3" --arg e "$4" '{start: $s, end: $e, host_repo: "acme/widgets", predecessor: null}' \
        | koto context add "$1" record/rotation
}
# find_token <session> <discipline>: the find's bare token for the run of
# <session>, opened first when it doesn't exist yet, with the gh and koto call
# logs emptied before the find runs.
find_token() {
    [ -d "$KOTO_STORE/sessions/$1" ] || log_new "$1" "$(discipline_vars "$2")"
    reset_calls; : > "$KOTO_STORE/calls"
    bash "$HERE/record-find.sh" --session "$1" --no-seal 2> "$T/find.err"
}
# gh_reads: the gh calls since find_token, one per line, as the stand-in logs
# them; gh_count <pattern>: how many of them match.
gh_reads() { calls | grep -c .; }
gh_count() { calls | grep -c -- "$1"; }
koto_reads() { grep -c . "$KOTO_STORE/calls"; }

echo "== a discipline's first rotation =="
eq "the find seals first" first "$(find_token coordinate-discipline-fresh-20261005T100000Z fresh)"
eq "  ... with no GitHub read" 0 "$(gh_reads)"
FIRST_KOTO=$(koto_reads)

echo "== a predecessor session =="
P=coordinate-discipline-relay-20261001T100000Z
rotation "$P" relay "$WEEK_AGO" "$YESTERDAY"
touch "$KOTO_STORE/sessions/$P/.terminal"
eq "the find seals the predecessor" "predecessor $P" "$(find_token coordinate-discipline-relay-20261008T100000Z relay)"
eq "  ... with no GitHub read" 0 "$(gh_reads)"

echo "== this run's own rotation =="
S=coordinate-discipline-own-20261005T100000Z
rotation "$S" own "$TODAY" "$TOMORROW"
eq "the find seals found" found "$(find_token "$S" own)"
eq "  ... with no GitHub read" 0 "$(gh_reads)"

echo "== the koto reads =="
# A first rotation lists the run's sessions once and reads no earlier rotation;
# its koto reads are the session listing and the find's own record. Run it
# again, and count the second run's calls.
find_token coordinate-discipline-fresh-20261005T100000Z fresh > /dev/null
eq "a first rotation lists the sessions once" 1 "$(grep -c '^session list' "$KOTO_STORE/calls")"
eq "  ... and makes the same koto reads each time ($FIRST_KOTO)" "$FIRST_KOTO" "$(koto_reads)"

done_tests find-reads_test
