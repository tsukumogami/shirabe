#!/usr/bin/env bash
# find-reads_test.sh -- the reads record-find.sh makes at discipline scope when
# the rotation is on the session store (shirabe#1141), counted through the gh
# and koto stand-ins.
#
# Covers: the bridge (no earlier session rotation, a committed handoff file),
# a discipline's first rotation, a predecessor session and this run's own
# rotation each make a fixed set of gh reads; the bridge and the first
# rotation read the repository once, and they alone read the default branch's
# head and the handoff file, each once; the bridge lists the sessions once and
# makes the same koto reads each time it runs.
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

echo "== the bridge: the committed handoff file =="
# The find only checks that the file is there; the carry, a later step, reads it.
db '.files["acme/widgets"]["main:docs/disciplines/bridge.md"] = "a handoff\n"'
eq "the find seals the handoff" "predecessor handoff:$SHA_MAIN" "$(find_token coordinate-discipline-bridge-20261005T100000Z bridge)"
eq "  ... in five gh reads" 5 "$(gh_reads)"
eq "  ... reading the repository once" 1 "$(calls | grep -c '^api --method GET repos/acme/widgets --jq')"
eq "  ... the default branch's head once" 1 "$(gh_count 'git/ref/heads/main')"
eq "  ... and the handoff file once" 1 "$(gh_count 'contents/docs/disciplines/bridge.md')"
BRIDGE_KOTO=$(koto_reads)

echo "== a discipline's first rotation =="
eq "the find seals first" first "$(find_token coordinate-discipline-fresh-20261005T100000Z fresh)"
eq "  ... in five gh reads" 5 "$(gh_reads)"
eq "  ... reading the repository once" 1 "$(calls | grep -c '^api --method GET repos/acme/widgets --jq')"
eq "  ... the default branch's head once" 1 "$(gh_count 'git/ref/heads/main')"
eq "  ... and looking for the handoff file once" 1 "$(gh_count 'contents/docs/disciplines/fresh.md')"

echo "== a predecessor session =="
P=coordinate-discipline-relay-20261001T100000Z
rotation "$P" relay "$WEEK_AGO" "$YESTERDAY"
touch "$KOTO_STORE/sessions/$P/.terminal"
eq "the find seals the predecessor" "predecessor $P" "$(find_token coordinate-discipline-relay-20261008T100000Z relay)"
eq "  ... in three gh reads" 3 "$(gh_reads)"
eq "  ... with no read of the default branch's head" 0 "$(gh_count 'git/ref/heads')"
eq "  ... nor of a handoff file" 0 "$(gh_count 'contents/')"

echo "== this run's own rotation =="
S=coordinate-discipline-own-20261005T100000Z
rotation "$S" own "$TODAY" "$TOMORROW"
eq "the find seals found" found "$(find_token "$S" own)"
eq "  ... in three gh reads" 3 "$(gh_reads)"

echo "== the koto reads =="
# The bridge lists the run's sessions once and reads no earlier rotation; its
# koto reads are the probe's, the session listing and the find's own record.
# Run it again, and count the second run's calls.
find_token coordinate-discipline-bridge-20261005T100000Z bridge > /dev/null
eq "the bridge lists the sessions once" 1 "$(grep -c '^session list' "$KOTO_STORE/calls")"
eq "  ... and makes the same koto reads each time ($BRIDGE_KOTO)" "$BRIDGE_KOTO" "$(koto_reads)"

done_tests find-reads_test
