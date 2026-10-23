#!/usr/bin/env bash
# normalize_test.sh -- state-schema.jq's normalize_state hands readers, and
# stores for writers, the very state a write through the markdown body did: the
# state rendered and parsed back.
#
# Each case is a state with one section in one shape. Its expected normal form
# is committed under testdata/normalize/<case>.json. Each was made by
# rendering the state to the record's markdown body and parsing the body back,
# with the renderer and the parser this skill had before its record moved
# wholly into the session, and normalize_state was checked against that round
# trip, case by case, in the change that removed them. The golden files hold
# it to that round trip from then on.
#
# Covers, for each optional section (Holds, Run, Standing, Work, Decisions):
# absent, present with nothing in it, and present with rows; for Decisions, no
# entries at a later Next decision, entries, and archived identifiers; for the
# four sections, empty and with rows, optional columns left empty, and a blank
# Wakes read as 0.
#
# Usage: bash skills/coordinate/scripts/normalize_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
G=$HERE/testdata/normalize
W=2026-10-01T09:00:00Z
SHA=0123456789abcdef0123456789abcdef01234567

base() {
    jq -nc --arg w "$W" '{scope: {kind: "roadmap", name: "plugin-system"}, written: $w,
      holdings: [], deferrals: [], side_effects: [], reversals: []}'
}
HOLDING=$(jq -nc --arg sha "$SHA" '{unit: "Feature 2", entry_point: "/shirabe:deliver", mode: "--auto", phase: "executing",
  dispatch_status: "dispatched", return_path: "message", worker: "plugin-registry", repo: "acme/widgets",
  branch: "feat/x", verified_head: $sha, dispatched: "2026-09-26",
  pull_request: "[#12](https://github.com/acme/widgets/pull/12)"}')
BARE=$(jq -nc '{unit: "Feature 3", entry_point: "/shirabe:deliver", mode: "", phase: "scoping",
  dispatch_status: "dispatching", return_path: "message", worker: "plugin-loader", repo: "acme/widgets",
  branch: "", verified_head: "", dispatched: "2026-09-27", pull_request: ""}')
HOLD='{"hold":"after-346","on":"acme/widgets#12","until":"merged acme/gadgets#346","set_by":"the workspace coordinator","set":"2026-09-26T09:00Z","lifted":""}'
RUNROW='{"key":"friction","value":"friction-log","set_by":"alice","set":"2026-10-13T10:00Z"}'
STROW='{"standing":"s1","kind":"pause","on":"all","until":"time 2026-10-14T00:00Z","what":"hold the merges","owner":"the human","relayed_by":"","set":"2026-10-13T10:00Z"}'
WKROW='{"item":"Milestone 3","kind":"decision","who":"decision 1","next":"go","wakes":"","updated":"2026-10-09T10:00Z"}'
ENTRY=$(jq -nc '{decision: "8", round: "1", question: "Ship with the mixed check result?",
  options: "keep option d and ship -- d stands\nswitch to option c -- versions pin", state: "escalated",
  source: "worker ci-pin [20260927T233505Z report 40.1]", verdict: "escalate", recommendation: "keep option d and ship",
  reason: "the flip did not happen", context: "Option d was approved.", problem: "Dropping it changes the scope.",
  grounds: "scope", target: "a person", owed: "escalation", asked: "", evidence: "", outcome: "", decided_by: "",
  updated: "2026-09-27T23:40Z"}')

# The cases, by name; build <name> prints the case's state.
CASES="four-empty four-rows holds-empty holds-rows run-empty run-rows standing-empty standing-rows
work-empty work-rows-blank-wakes decisions-none decisions-later-next decisions-entries decisions-archived
all-optional-empty"
build() {
    case "$1" in
        four-empty) base ;;
        four-rows) base | jq -c --argjson h "[$HOLDING, $BARE]" --arg sha "$SHA" '.holdings = $h
            | .deferrals = [{deferral: "flaky test | with a pipe", reason: "not now", raised: "2026-09-25T10:00Z", disposition: ""}]
            | .side_effects = [{action: "merge", target: "#12", verified_head: $sha, attempted: "2026-09-26T11:02Z", how_to_confirm: "compare blobs on main"}]
            | .reversals = [{date: "2026-09-26T09:15Z", reversed: "merge on green", now: "hold for release", reason: "release freeze", from: "the human"}]' ;;
        holds-empty) base | jq -c '.holds = []' ;;
        holds-rows) base | jq -c --argjson r "$HOLD" '.holds = [$r]' ;;
        run-empty) base | jq -c '.run = []' ;;
        run-rows) base | jq -c --argjson r "$RUNROW" '.run = [$r]' ;;
        standing-empty) base | jq -c '.standing = []' ;;
        standing-rows) base | jq -c --argjson r "$STROW" '.standing = [$r]' ;;
        work-empty) base | jq -c '.work = []' ;;
        work-rows-blank-wakes) base | jq -c --argjson r "$WKROW" '.work = [$r]' ;;
        decisions-none) base | jq -c '.decisions = {next: 1, entries: []}' ;;
        decisions-later-next) base | jq -c '.decisions = {next: 5, entries: []}' ;;
        decisions-entries) base | jq -c --argjson e "$ENTRY" '.decisions = {next: 9, entries: [$e]}' ;;
        decisions-archived) base | jq -c --argjson e "$ENTRY" '.decisions = {next: 9, entries: [$e], archived: [1, 2, 3, 5]}' ;;
        all-optional-empty) base | jq -c '.holds = [] | .run = [] | .standing = [] | .work = [] | .decisions = {next: 1, entries: []}' ;;
    esac
}

echo "== normalize_state against the round trip's golden forms =="
for name in $CASES; do
    build "$name" > "$T/in.json" 2> "$T/in.err" && [ -s "$T/in.json" ] || { bad "$name: the case builds" "$(cat "$T/in.err")"; continue; }
    got=$(jq -cS -L "$HERE" 'include "state-schema"; normalize_state([])' "$T/in.json" 2>&1)
    eq "$name: normalize_state gives the golden form" "$(jq -cS . "$G/$name.json" 2>/dev/null)" "$got"
done
# Every golden file is a case's: none is left over from a case since removed.
for f in "$G"/*.json; do
    n=$(basename "$f" .json)
    printf '%s\n' $CASES | grep -qxF "$n" || bad "testdata/normalize/$n.json belongs to a case" "no case is named $n"
done

done_tests normalize_test
