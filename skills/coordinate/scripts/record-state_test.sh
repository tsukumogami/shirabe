#!/usr/bin/env bash
# record-state_test.sh -- record-state.sh, the one way the stored set's
# sections (Run, Standing, Work) change, and record-handover.sh, which reads
# them and names the gaps.
#
# Covers: --list on a record with none of the sections; Run's keys, a cap and
# arguments, a new coordinator clearing every told row; --run store refused
# as no Run key (65); --told needing a coordinator and refusing a second time;
# a Standing row with owner and relayer, its id, --end removing it, an id never
# reused, and an unreadable entry stream refusing a new id; a person's event
# relayed, owner and relayer named; Work rows for a holding (which also
# records its worker as told on its first row only, not on a later update
# after an address change) and for a local agent, upserted, --done, and a
# holding's row dropped once its holding is gone; a decision row parking a
# unit on an open entry and a follow-up row naming a scoping's pull request,
# their refusals, and a new holding taking both over while the scoping holding
# doesn't; each change told as an
# entry after the write; refusals (a holding row for no holding, a malformed
# cap, a session-shaped address, a private repository on a public host); the
# one-writer rule (record-write.sh changing a section refused); a failed entry
# post after a written state (14); a temporary file that can't be made (2,
# nothing written, the caller's .one left); an assignment (an issue or a release a
# person assigned) and its refusals; a verdict-owed row (a milestone's
# verdict owed) listed and kept by every write, --done leaving it and
# --done --kind verdict-owed and --work --kind verdict-owed refused; a rework
# row kept by other writes, --work --kind rework refused, record-write.sh
# changing or removing it refused, --done --kind rework removing it;
# record-handover.sh's report and gaps (a holding with no next step among
# them); the crash set's rows written in a fresh session with no store row, and
# --host. Every record is the session's; nothing is written on GitHub.
#
# Usage: bash skills/coordinate/scripts/record-state_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RS="$HERE/record-state.sh"
RH="$HERE/record-handover.sh"
RA="$HERE/record-append.sh"

SR=coordinate-roadmap-plugin-system-20260926T070000Z
export RS_SESSION=$SR
RM=(--scope roadmap --name plugin-system --repo "$REPO")
W=("${RM[@]}" --skip-session-checks)
seed() { db_init; seed_session "$SR" "$1"; } # seed <record-json>
live() { session_state "$SR"; }
entries() { bash "$RA" "${RM[@]}" --list; }
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit)|comment|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }
TWO=$(record_json roadmap plugin-system | jq -c --argjson a "$(holding worker-f2)" \
    --argjson b "$(holding worker-f3 '{"unit": "Feature 3", "pull_request": ""}')" '.holdings = [$a, $b]')

echo "== list =="
seed "$TWO"
eq "--list with none of the sections" '{"run":[],"standing":[],"work":[]}' "$(bash "$RS" "${RM[@]}" --list 2>&1)"
eq "a read writes nothing, and reads nothing on GitHub" "" "$(calls)"

echo "== Run =="
bash "$RS" "${W[@]}" --run arguments "--roadmap docs/roadmaps/ROADMAP-plugin-system.md --cap 2" --by "the human" >/dev/null 2>"$T/err"
eq "arguments are set" 0 $?
bash "$RS" "${W[@]}" --run cap 2 --by "the human" >/dev/null 2>"$T/err"; eq "a cap is set" 0 $?
bash "$RS" "${W[@]}" --run cap 1 --by "the human, via the process owner" >/dev/null 2>"$T/err"; eq "a cap is changed" 0 $?
cap_rows=$(live | jq -r '[.run[] | select(.key == "cap")] | "\(.[0].value) \(.[0].set_by)", length')
eq "  ... one cap row, the new one" "1 the human, via the process owner" "${cap_rows%%$'\n'*}"
eq "  ... and only one" 1 "$(live | jq '[.run[] | select(.key == "cap")] | length')"
bash "$RS" "${W[@]}" --run cap two --by x >/dev/null 2>"$T/err"; eq "a cap that isn't a number is refused" 65 $?
bash "$RS" "${W[@]}" --run told worker-f2 --by x >/dev/null 2>"$T/err"; eq "--run doesn't take told" 64 $?
SNAP=$(session_snapshot "$SR")
bash "$RS" "${W[@]}" --run store session --by "the human" >/dev/null 2>"$T/err"; eq "--run store session is refused as no Run key" 65 $?
grep -q 'store is not a Run key' "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
bash "$RS" "${W[@]}" --run store github --by "the human" >/dev/null 2>"$T/err"; eq "  ... and store github" 65 $?
bash "$RS" "${W[@]}" --run store session >/dev/null 2>"$T/err"; eq "  ... even without --by" 65 $?
eq "  ... writing nothing" "$SNAP" "$(session_snapshot "$SR")"
bash "$RS" "${W[@]}" --told worker-f2 --by lane-v1 >/dev/null 2>"$T/err"; eq "--told without a coordinator address is refused" 65 $?
bash "$RS" "${W[@]}" --run coordinator lane-v1 --by lane-v1 >/dev/null 2>"$T/err"; eq "a coordinator address is set" 0 $?
bash "$RS" "${W[@]}" --run coordinator session_0123abcd --by lane-v1 >/dev/null 2>"$T/err"; eq "a session-shaped address is refused" 65 $?
bash "$RS" "${W[@]}" --told worker-f2 --by lane-v1 >/dev/null 2>"$T/err"; eq "a worker is told" 0 $?
bash "$RS" "${W[@]}" --told worker-f2 --by lane-v1 >/dev/null 2>"$T/err"; eq "  ... not twice" 65 $?
bash "$RS" "${W[@]}" --run coordinator lane-v2 --by lane-v2 >/dev/null 2>"$T/err"; eq "a new address is set" 0 $?
eq "  ... and clears every told row" 0 "$(live | jq '[.run[] | select(.key == "told")] | length')"

echo "== Standing =="
bash "$RS" "${W[@]}" --standing answer --what "panels at the head are the cost to cut" --owner "the human" --relayed-by "the process owner" >/dev/null 2>"$T/err"
eq "a standing answer is recorded" 0 $?
eq "  ... with its id, owner and relayer" "s1 answer the human the process owner" \
    "$(live | jq -r '.standing[0] | "\(.standing) \(.kind) \(.owner) \(.relayed_by)"')"
bash "$RS" "${W[@]}" --standing pause --on all --until lifted --what "all lanes, until a resume" --owner "the human" >/dev/null 2>"$T/err"
eq "a pause told directly has no relayer" "s2 []" "$(live | jq -r '.standing[1] | "\(.standing) [\(.relayed_by)]"')"
eq "  ... and keeps its scope and condition" "all lifted" "$(live | jq -r '.standing[1] | "\(.on) \(.until)"')"
bash "$RS" "${W[@]}" --standing pause --what x --owner y >/dev/null 2>"$T/err"; eq "a pause with no --on or --until is usage" 64 $?
bash "$RS" "${W[@]}" --standing pause --on everything --until lifted --what x --owner y >/dev/null 2>"$T/err"; eq "a scope that is no unit is refused by the codec" 65 $?
bash "$RS" "${W[@]}" --standing pause --on all --until "tomorrow at ten" --what x --owner y >/dev/null 2>"$T/err"; eq "a condition outside the grammar is refused by the codec" 65 $?
bash "$RS" "${W[@]}" --standing pause --on "acme/secret#4" --until lifted --what x --owner y >/dev/null 2>"$T/err"; eq "a scope naming a private repository is refused" 65 $?
bash "$RS" "${W[@]}" --standing go-ahead --on "Feature 2" --until lifted --what x --owner y >/dev/null 2>"$T/err"; eq "a go-ahead with an --until is usage" 64 $?
bash "$RS" "${W[@]}" --standing answer --on "Feature 2" --what x --owner y >/dev/null 2>"$T/err"; eq "an answer with an --on is usage" 64 $?
bash "$RS" "${W[@]}" --standing rumour --what x --owner y >/dev/null 2>"$T/err"; eq "an unknown kind is refused" 64 $?
bash "$RS" "${W[@]}" --end s2 --by "the human" >/dev/null 2>"$T/err"; eq "a resume ends the pause" 0 $?
eq "  ... the row is gone" "s1" "$(live | jq -r '[.standing[].standing] | join(" ")')"
bash "$RS" "${W[@]}" --standing go-ahead --what "release v0.25.0" --owner "the human" --relayed-by "the process owner" >/dev/null 2>"$T/err"
eq "an ended id is never reused" "s1 s3" "$(live | jq -r '[.standing[].standing] | join(" ")')"
bash "$RS" "${W[@]}" --end s9 --by x >/dev/null 2>"$T/err"; eq "ending an unknown row is refused" 65 $?
# The entries are read to choose the next id; a koto that can't list them by
# prefix refuses (2) rather than risk reusing one.
KOTO_NO_LIST_PREFIX=1 bash "$RS" "${W[@]}" --standing approval --what x --owner y >/dev/null 2>"$T/err"; eq "an unreadable entry stream refuses a new Standing id (2) rather than risk reusing one" 2 $?
eq "  ... and writes nothing" "s1 s3" "$(live | jq -r '[.standing[].standing] | join(" ")')"

echo "== the relay duty: a person's event, relayed =="
bash "$RS" "${W[@]}" --standing answer --what "hold the koto release until the other lane lands" --owner alice --relayed-by lane-v2 >/dev/null 2>"$T/err"
eq "the coordinator relays it, the person as owner and itself as relayer" "answer alice lane-v2" \
    "$(live | jq -r '.standing[-1] | "\(.kind) \(.owner) \(.relayed_by)"')"
entries | jq -e 'any(.[]; .kind == "answer" and (.text | test("Owner: alice\\. Relayed by lane-v2\\.")))' >/dev/null \
    && ok "  ... and its entry says so" || bad "  ... and its entry says so" "$(entries | jq -c 'map(.text)')"

echo "== Work =="
bash "$RS" "${W[@]}" --work "Feature 2" --kind holding --who worker-f2 --next "waiting on the panel at the head" >/dev/null 2>"$T/err"
eq "a holding's next step is recorded" 0 $?
eq "  ... and its worker is recorded as told the current address" "worker-f2 lane-v2" \
    "$(live | jq -r '.run[] | select(.key == "told") | "\(.value) \(.set_by)"')"
bash "$RS" "${W[@]}" --work "Feature 9" --kind holding --who worker-f9 --next x >/dev/null 2>"$T/err"; eq "a holding row for no holding is refused" 65 $?
bash "$RS" "${W[@]}" --work "fix for the ablation check" --kind local-agent --who "local agent" --next "ready report, then the merge" >/dev/null 2>"$T/err"
eq "local-agent work gets a row" 0 $?
bash "$RS" "${W[@]}" --work "Feature 2" --kind holding --who worker-f2 --next "fix round on the panel's finding" >/dev/null 2>"$T/err"
eq "a next step is replaced, not added" "fix round on the panel's finding 2" "$(live | jq -r '"\(.work[] | select(.item == "Feature 2") | .next) \(.work | length)"')"
bash "$RS" "${W[@]}" --done "fix for the ablation check" >/dev/null 2>"$T/err"; eq "--done removes a row" 1 "$(live | jq '.work | length')"
bash "$RS" "${W[@]}" --done nothing >/dev/null 2>"$T/err"; eq "--done on no row is refused" 65 $?
# The holding goes (a teardown, through the holdings writer); the next write drops its row.
live > "$T/now.json"
jq -c 'del(.written) | .holdings = [.holdings[] | select(.worker != "worker-f2")]' "$T/now.json" > "$T/gone.json"
state_json "$(cat "$T/gone.json")" "$(jq -r .written "$T/now.json")" > "$T/gone.state"
bash "$HERE/record-write.sh" "${W[@]}" --state-file "$T/gone.state" >/dev/null 2>"$T/err"; eq "the holding is torn down" 0 $?
bash "$RS" "${W[@]}" --run cap 2 --by "the human" >/dev/null 2>"$T/err"
eq "  ... and the next write drops its Work row" 0 "$(live | jq '(.work // []) | length')"

echo "== entries =="
eq "every change was told as an entry, kinds in order, a torn-down holding's final count last" "run run run run told run answer pause end go-ahead answer work work work work run work" \
    "$(entries | jq -r 'map(.kind) | join(" ")')"
entries | jq -e 'any(.[]; .kind == "pause" and (.text | test("^s2 \\(pause on all, until lifted\\): all lanes")))' >/dev/null \
    && ok "  ... a pause's entry names its scope and condition" || bad "  ... a pause's entry names its scope and condition" "$(entries | jq -c 'map(.text)')"
entries | jq -e '.[0].text | test("^Run arguments set to --roadmap .* by the human\\.$")' >/dev/null && ok "  ... each naming who" || bad "  ... each naming who" "$(entries | jq -r '.[0].text')"
eq "  ... the holding's row left Work with its count" "Feature 2 (worker-f2) left Work after 0 wakes." "$(entries | jq -r '.[-1].text')"
eq "  ... and a holding's row carries a Wakes count, a local agent's 0" "0" "$(live | jq -r '[(.work // [])[] | .wakes] | unique | join(",") | if . == "" then "0" else . end')"

echo "== a unit parked on a decision, and a follow-up =="
# Entry 4 is open, entry 5 settled; Feature 3 is held by worker-f3.
OPEN4=$(jq -nc '{decision: "4", round: "1", question: "Feature 4: keep the registry?",
    options: "keep -- the sandbox needs it\ndrop -- a static list will do", state: "escalated", verdict: "escalate",
    recommendation: "keep", reason: "the sandbox design assumes it", context: "The context.", problem: "The problem.",
    grounds: "scope", target: "a person", asked: "2026-09-26T07:30Z",
    source: "self [20260925T080000Z raise 3]", updated: "2026-09-26T07:00Z"}')
DONE5=$(jq -nc '{decision: "5", round: "1", question: "Feature 5: in scope?", options: "yes\nno", state: "settled",
    outcome: "yes; reason: the human said so", decided_by: "a person", source: "self [20260925T080000Z raise 4]", updated: "2026-09-26T07:00Z"}')
seed "$(printf '%s' "$TWO" | jq -c --argjson a "$OPEN4" --argjson b "$DONE5" '.decisions = {next: 6, entries: [$a, $b]} | .holdings[1].phase = "scoping"')"
bash "$RS" "${W[@]}" --work "Feature 4" --kind decision --who "decision 4" --next "dispatch once decided" >/dev/null 2>"$T/err"
eq "a unit is parked on an open entry" 0 $?
eq "  ... as a decision row" "Feature 4 decision decision 4" "$(live | jq -r '.work[] | "\(.item) \(.kind) \(.who)"')"
bash "$RS" "${W[@]}" --work "Feature 5" --kind decision --who "decision 5" --next x >/dev/null 2>"$T/err"; eq "a park on a settled entry is refused" 65 $?
bash "$RS" "${W[@]}" --work "Feature 6" --kind decision --who "decision 9" --next x >/dev/null 2>"$T/err"; eq "a park on no entry is refused" 65 $?
bash "$RS" "${W[@]}" --work "release acme/widgets v0.25.0" --kind decision --who "decision 4" --next "cut it once decided" >/dev/null 2>"$T/err"
eq "an assigned release can be parked too" 0 $?
bash "$RS" "${W[@]}" --done "release acme/widgets v0.25.0" --kind decision >/dev/null 2>"$T/err"; eq "  ... and its park removed" 0 $?
bash "$RS" "${W[@]}" --work "Feature 6" --kind decision --who "worker-f6" --next x >/dev/null 2>"$T/err"; eq "a decision row's Who that isn't decision <n> is refused" 65 $?
bash "$RS" "${W[@]}" --work "the registry" --kind decision --who "decision 4" --next x >/dev/null 2>"$T/err"; eq "a decision row whose Item isn't a unit is refused" 65 $?
bash "$RS" "${W[@]}" --work "Feature 3" --kind follow-up --who "acme/widgets#41" --next "/shirabe:execute docs/plans/PLAN-sandbox.md" >/dev/null 2>"$T/err"
eq "a follow-up row sits beside its unit's holding row" 0 $?
bash "$RS" "${W[@]}" --work "Feature 3" --kind holding --who worker-f3 --next "teardown after its scoping merged" >/dev/null 2>"$T/err"
eq "  ... and the unit's holding row doesn't replace it while the holding is the scoping's" "follow-up holding" \
    "$(live | jq -r '[.work[] | select(.item == "Feature 3") | .kind] | sort | join(" ")')"
bash "$RS" "${W[@]}" --work "Feature 3" --kind follow-up --who "#41" --next x >/dev/null 2>"$T/err"; eq "a follow-up's Who that isn't owner/repo#n is refused" 65 $?
bash "$RS" "${W[@]}" --done "Feature 3" --kind holding >/dev/null 2>"$T/err"
eq "--done --kind removes only that kind's row" "follow-up" "$(live | jq -r '[.work[] | select(.item == "Feature 3") | .kind] | join(" ")')"
# Its execution, dispatched as a new holding, takes the follow-up over.
live > "$T/now.json"
jq -c 'del(.written) | .holdings[1] |= (.worker = "worker-f3x" | .phase = "executing")' "$T/now.json" > "$T/f3.json"
state_json "$(cat "$T/f3.json")" "$(jq -r .written "$T/now.json")" > "$T/f3.state"
bash "$HERE/record-write.sh" "${W[@]}" --state-file "$T/f3.state" >/dev/null 2>"$T/err"; eq "the follow-up's execution is dispatched" 0 $?
bash "$RS" "${W[@]}" --work "Feature 3" --kind holding --who worker-f3x --next "executing the plan" >/dev/null 2>"$T/err"
eq "  ... and its holding row replaces the follow-up row" "holding worker-f3x" "$(live | jq -r '[.work[] | select(.item == "Feature 3") | "\(.kind) \(.who)"] | join(",")')"
# A new holding for a parked unit takes over its decision row.
live > "$T/now.json"
jq -c --argjson h "$(holding worker-f4 '{"unit": "Feature 4", "pull_request": ""}')" 'del(.written) | .holdings += [$h]' "$T/now.json" > "$T/f4.json"
state_json "$(cat "$T/f4.json")" "$(jq -r .written "$T/now.json")" > "$T/f4.state"
bash "$HERE/record-write.sh" "${W[@]}" --state-file "$T/f4.state" >/dev/null 2>"$T/err"; eq "the parked unit is dispatched" 0 $?
bash "$RS" "${W[@]}" --work "Feature 4" --kind holding --who worker-f4 --next "report at its first checkpoint" >/dev/null 2>"$T/err"
eq "  ... and its holding row replaces the decision row" "holding worker-f4" "$(live | jq -r '[.work[] | select(.item == "Feature 4") | "\(.kind) \(.who)"] | join(",")')"
# A holding whose Unit cell is `<tag>: <title>` takes over the rows its tag names.
bash "$RS" "${W[@]}" --work "Feature 6" --kind follow-up --who "acme/widgets#60" --next "/shirabe:execute docs/plans/PLAN-six.md" >/dev/null 2>"$T/err"
live > "$T/now.json"
jq -c --argjson h "$(holding worker-f6 '{"unit": "Feature 6: the exporter", "pull_request": ""}')" 'del(.written) | .holdings += [$h]' "$T/now.json" > "$T/f6.json"
state_json "$(cat "$T/f6.json")" "$(jq -r .written "$T/now.json")" > "$T/f6.state"
bash "$HERE/record-write.sh" "${W[@]}" --state-file "$T/f6.state" >/dev/null 2>"$T/err"
bash "$RS" "${W[@]}" --work "Feature 6: the exporter" --kind holding --who worker-f6 --next "executing" >/dev/null 2>"$T/err"
eq "a titled holding row takes over its tag's follow-up row" "Feature 6: the exporter:holding" \
    "$(live | jq -r '[.work[] | select(.item | startswith("Feature 6")) | "\(.item):\(.kind)"] | join(",")')"
eq "  ... and the handover reads the holding's own next step" "executing" \
    "$(bash "$RH" "${RM[@]}" | jq -r '.workers[] | select(.worker == "worker-f6") | .next')"

echo "== a verdict-owed row is roadmap-status.sh's =="
# A milestone whose verdict is owed (docs/designs/DESIGN-milestone-verdicts.md):
# listed and kept by every write here, written and removed only by
# roadmap-status.sh.
OWED=$(jq -nc '{item: "Feature 2", kind: "verdict-owed", who: "worker-f2", next: "verdict owed since 2026-09-26", wakes: "0", updated: "2026-09-26T07:00Z"}')
seed "$(printf '%s' "$TWO" | jq -c --argjson o "$OWED" '.work = [$o]')"
eq "--list shows it" "Feature 2 verdict-owed worker-f2" "$(bash "$RS" "${RM[@]}" --list | jq -r '.work[] | "\(.item) \(.kind) \(.who)"')"
bash "$RS" "${W[@]}" --work "Feature 2" --kind holding --who worker-f2 --next "teardown" >/dev/null 2>"$T/err"; eq "a holding row is written beside it" 0 $?
eq "  ... and it stays" "holding verdict-owed" "$(live | jq -r '[.work[] | select(.item == "Feature 2") | .kind] | sort | join(" ")')"
bash "$RS" "${W[@]}" --done "Feature 2" >/dev/null 2>"$T/err"; eq "--done for the unit removes its other rows" 0 $?
eq "  ... and leaves the verdict-owed row" "verdict-owed" "$(live | jq -r '[.work[] | select(.item == "Feature 2") | .kind] | join(" ")')"
bash "$RS" "${W[@]}" --done "Feature 2" >/dev/null 2>"$T/err"; eq "  ... which alone is no row --done can remove" 65 $?
bash "$RS" "${W[@]}" --done "Feature 2" --kind verdict-owed >/dev/null 2>"$T/err"; eq "--done --kind verdict-owed is refused" 65 $?
grep -q 'roadmap-status.sh --confirm' "$T/err" && ok "  ... naming what clears it" || bad "  ... naming what clears it" "$(cat "$T/err")"
bash "$RS" "${W[@]}" --work "Feature 3" --kind verdict-owed --who worker-f3 --next "verdict owed since 2026-09-26" >/dev/null 2>"$T/err"; eq "--work --kind verdict-owed is a usage error" 64 $?
live > "$T/now.json"
jq -c 'del(.written) | .work = [.work[] | select(.kind != "verdict-owed")] | if (.work | length) == 0 then del(.work) else . end' "$T/now.json" > "$T/edit.json"
state_json "$(cat "$T/edit.json")" "$(jq -r .written "$T/now.json")" > "$T/edit.state"
bash "$HERE/record-write.sh" "${W[@]}" --state-file "$T/edit.state" >/dev/null 2>"$T/err"; eq "record-write.sh removing it is refused" 65 $?
grep -q 'only through roadmap-status.sh' "$T/err" && ok "  ... naming its one writer" || bad "  ... naming its one writer" "$(cat "$T/err")"

echo "== a rework row: roadmap-status.sh writes it, --done removes it =="
REWORK=$(jq -nc '{item: "Feature 2", kind: "rework", who: "verdict 1001", next: "Evidence clauses not held: 2. Changes needed: name the skipped plugin", wakes: "0", updated: "2026-09-26T07:00Z"}')
seed "$(printf '%s' "$TWO" | jq -c --argjson r "$REWORK" '.work = [$r]')"
eq "--list shows it" "Feature 2 rework verdict 1001" "$(bash "$RS" "${RM[@]}" --list | jq -r '.work[] | "\(.item) \(.kind) \(.who)"')"
bash "$RS" "${W[@]}" --work "Feature 3" --kind local-agent --who "a local agent" --next "check the docs" >/dev/null 2>"$T/err"; eq "another row is written beside it" 0 $?
eq "  ... and it stays" "rework" "$(live | jq -r '[.work[] | select(.item == "Feature 2") | .kind] | join(" ")')"
bash "$RS" "${W[@]}" --work "Feature 2" --kind rework --who "verdict 1001" --next "Changes needed: x" >/dev/null 2>"$T/err"; eq "--work --kind rework is a usage error" 64 $?
grep -q 'roadmap-status.sh --confirm' "$T/err" && ok "  ... naming its one writer" || bad "  ... naming its one writer" "$(cat "$T/err")"
live > "$T/now.json"
jq -c 'del(.written) | .work = [.work[] | if .kind == "rework" then .next = "Changes needed: nothing" else . end]' "$T/now.json" > "$T/edit.json"
state_json "$(cat "$T/edit.json")" "$(jq -r .written "$T/now.json")" > "$T/edit.state"
bash "$HERE/record-write.sh" "${W[@]}" --state-file "$T/edit.state" >/dev/null 2>"$T/err"; eq "record-write.sh changing its text is refused" 65 $?
grep -q 'written only by roadmap-status.sh --confirm' "$T/err" && ok "  ... naming its one writer" || bad "  ... naming its one writer" "$(cat "$T/err")"
jq -c 'del(.written) | .work = [.work[] | select(.kind != "rework")]' "$T/now.json" > "$T/edit.json"
state_json "$(cat "$T/edit.json")" "$(jq -r .written "$T/now.json")" > "$T/edit.state"
bash "$HERE/record-write.sh" "${W[@]}" --state-file "$T/edit.state" >/dev/null 2>"$T/err"; eq "record-write.sh removing it is refused" 65 $?
bash "$RS" "${W[@]}" --done "Feature 2" --kind rework >/dev/null 2>"$T/err"; eq "--done --kind rework removes it" 0 $?
eq "  ... and only it" "Feature 3 local-agent" "$(live | jq -r '[.work[] | "\(.item) \(.kind)"] | join(",")')"

echo "== one writer =="
seed "$TWO"
bash "$RS" "${W[@]}" --run cap 2 --by "the human" >/dev/null 2>&1
live > "$T/now.json"
jq -c 'del(.written) | .run[0].value = "5"' "$T/now.json" > "$T/edit.json"
state_json "$(cat "$T/edit.json")" "$(jq -r .written "$T/now.json")" > "$T/edit.state"
bash "$HERE/record-write.sh" "${W[@]}" --state-file "$T/edit.state" >/dev/null 2>"$T/err"; eq "another writer changing Run is refused" 65 $?
grep -q 'only through record-state.sh' "$T/err" && ok "  ... naming the one writer" || bad "  ... naming the one writer" "$(cat "$T/err")"

echo "== a public host =="
bash "$RS" "${W[@]}" --standing answer --what "wait for acme/secret#5" --owner "the human" >/dev/null 2>"$T/err"; eq "a private repository in a Standing row is refused" 65 $?
bash "$RS" "${W[@]}" --standing answer --what "wait for acme/gadgets#5" --owner "the human" >/dev/null 2>"$T/err"; eq "a public one is fine" 0 $?

echo "== the entry fails after the write =="
NEXT_ENTRY=$(printf 'record/entries/%06d' $(( $(entries | jq length) + 1 )))
KOTO_FAIL_ADD=$NEXT_ENTRY bash "$RS" "${W[@]}" --run cap 3 --by "the human" >/dev/null 2>"$T/err"; eq "a failed entry write is 14" 14 $?
eq "  ... after the record was written" 3 "$(live | jq -r '.run[] | select(.key == "cap") | .value')"
grep -q 'Run cap set to 3 by the human' "$T/err" && ok "  ... naming the entry to post" || bad "  ... naming the entry to post" "$(cat "$T/err")"

echo "== a temporary file that can't be made (the #922 shape, found in #924's sweep) =="
# The leaving lines' file is the last one made before the write. Unchecked,
# its name was empty: the record was written anyway and the closing
# `rm -f "$LEAVING_FILE" "$LEAVING_FILE.one"` removed .one from the caller's
# directory.
mkdir -p "$T/mkt-bin" "$T/mkt-cwd"
printf '#!/bin/sh\ncase "$*" in *record-state-leaving*) exit 1 ;; esac\nexec "%s" "$@"\n' "$(command -v mktemp)" > "$T/mkt-bin/mktemp"
chmod +x "$T/mkt-bin/mktemp"
printf 'keep\n' > "$T/mkt-cwd/.one"
BEFORE=$(live | jq -c '.run')
(cd "$T/mkt-cwd" && PATH="$T/mkt-bin:$PATH" bash "$RS" "${W[@]}" --run cap 4 --by "the human" >/dev/null 2>"$T/err")
eq "a temporary file that can't be made is a failed read (2)" 2 $?
eq "  ... before the state is written" "$BEFORE" "$(live | jq -c '.run')"
eq "  ... and the caller's .one is left" keep "$(cat "$T/mkt-cwd/.one" 2>/dev/null)"

echo "== a session name as the address (shirabe#610) =="
seed "$TWO"
bash "$RS" "${W[@]}" --run coordinator lane_owner --by "the human" >/dev/null 2>"$T/err"
eq "an underscored session name is the coordinator's address" 0 $?
bash "$RS" "${W[@]}" --told plugin_api-worker --by lane_owner >/dev/null 2>"$T/err"
eq "  ... and an underscored party is told it" 0 $?
bash "$RS" "${W[@]}" --work "Feature 2" --kind holding --who worker-f2 --next "report at its first checkpoint" >/dev/null 2>"$T/err"
eq "  ... a worker topic's first Work row is still recorded as told" "lane_owner|plugin_api-worker worker-f2" \
    "$(live | jq -r '([.run[] | select(.key == "coordinator") | .value] | join(" ")) + "|" + ([.run[] | select(.key == "told") | .value] | join(" "))')"
bash "$RH" "${RM[@]}" | jq -e '[.gaps[].gap] | index("not-told worker-f2") == null' >/dev/null \
    && ok "  ... and the handover read matches it as told" || bad "  ... and the handover read matches it as told" "$(bash "$RH" "${RM[@]}")"
bash "$RS" "${W[@]}" --run coordinator session_0123abcd --by x >/dev/null 2>"$T/err"; eq "  ... a session_ id is still refused" 65 $?

echo "== an assignment: work a person assigns outside the scope (shirabe#607) =="
seed "$TWO"
bash "$RS" "${W[@]}" --standing assignment --on "acme/widgets#591" --what "pick the review level up front" --owner "the human" >/dev/null 2>"$T/err"
eq "an assigned issue is recorded" 0 $?
eq "  ... with its unit in On" "assignment acme/widgets#591" "$(live | jq -r '.standing[-1] | "\(.kind) \(.on)"')"
bash "$RS" "${W[@]}" --standing assignment --on "release acme/widgets v0.25.0" --what "cut v0.25.0" --owner "the human" >/dev/null 2>"$T/err"
eq "an assigned release is recorded" 0 $?
entries | jq -e 'any(.[]; .kind == "assignment" and (.text | test("\\(assignment on release acme/widgets v0.25.0\\)")))' >/dev/null \
    && ok "  ... and told as an assignment entry" || bad "  ... and told as an assignment entry" "$(entries | jq -c 'map(.text)')"
bash "$RS" "${W[@]}" --standing assignment --what x --owner y >/dev/null 2>"$T/err"; eq "an assignment with no --on is usage" 64 $?
bash "$RS" "${W[@]}" --standing assignment --on "#12" --until lifted --what x --owner y >/dev/null 2>"$T/err"; eq "an assignment with an --until is usage" 64 $?
bash "$RS" "${W[@]}" --standing assignment --on "Feature 2" --what x --owner y >/dev/null 2>"$T/err"; eq "a roadmap feature isn't assigned work: refused by the codec" 65 $?
bash "$RS" "${W[@]}" --standing assignment --on "acme/secret#4" --what x --owner y >/dev/null 2>"$T/err"; eq "an assignment naming a private repository is refused" 65 $?

echo "== the handover read =="
seed "$TWO"
H=$(bash "$RH" "${RM[@]}" 2>"$T/err"); eq "the read prints" 0 $?
eq "an old record has every gap" "no-arguments no-cap no-coordinator no-reports-to no-next-step Feature 2 no-next-step Feature 3" \
    "$(printf '%s' "$H" | jq -r '[.gaps[].gap] | join(" ")')"
eq "  ... a holding with no next step named with its fix" 'record-state.sh --work "Feature 2" --kind holding --who worker-f2 --next "<what happens next>"' \
    "$(printf '%s' "$H" | jq -r '.gaps[] | select(.gap == "no-next-step Feature 2") | .fix')"
bash "$RH" "${RM[@]}" --check >/dev/null 2>"$T/err"; eq "--check fails on gaps" 1 $?
grep -q 'record-state.sh --run cap' "$T/err" && ok "  ... naming the fix" || bad "  ... naming the fix" "$(cat "$T/err")"
bash "$RS" "${W[@]}" --run arguments "--roadmap x --cap 2" --by "the human" >/dev/null 2>&1
bash "$RS" "${W[@]}" --run cap 2 --by "the human" >/dev/null 2>&1
bash "$RS" "${W[@]}" --run reports-to "the human" --by "the human" >/dev/null 2>&1
bash "$RS" "${W[@]}" --work "Feature 2" --kind holding --who worker-f2 --next x >/dev/null 2>&1
bash "$RS" "${W[@]}" --run coordinator lane-v2 --by lane-v2 >/dev/null 2>&1
eq "a new address leaves every live worker untold" "no-next-step Feature 3 not-told worker-f2 not-told worker-f3" \
    "$(bash "$RH" "${RM[@]}" | jq -r '[.gaps[].gap] | join(" ")')"
bash "$RS" "${W[@]}" --work "Feature 2" --kind holding --who worker-f2 --next "an update after the new address" >/dev/null 2>&1
eq "a later Work update doesn't mark its worker told the new address" "no-next-step Feature 3 not-told worker-f2 not-told worker-f3" \
    "$(bash "$RH" "${RM[@]}" | jq -r '[.gaps[].gap] | join(" ")')"
bash "$RS" "${W[@]}" --work "Feature 3" --kind holding --who worker-f3 --next y >/dev/null 2>&1
eq "a holding's first Work row does, since its dispatch brief named the address" "not-told worker-f2" \
    "$(bash "$RH" "${RM[@]}" | jq -r '[.gaps[].gap] | join(" ")')"
bash "$RS" "${W[@]}" --told worker-f2 --by lane-v2 >/dev/null 2>&1
bash "$RH" "${RM[@]}" --check >/dev/null 2>"$T/err"; eq "no gaps once each is told and has a next step" 0 $?
# A merged holding (a Verified head, its Pull request cleared) is exempt.
seed "$(printf '%s' "$TWO" | jq -c --arg s "$SHA_HEAD" '.holdings[1].verified_head = $s')"
eq "a merged holding needs no next step" "no-arguments no-cap no-coordinator no-reports-to no-next-step Feature 2" \
    "$(bash "$RH" "${RM[@]}" | jq -r '[.gaps[].gap] | join(" ")')"
# PRD R15: a live holding whose leg names a request this host's store doesn't
# hold (the run was imported here) holds the gate until its leg has an end.
seed "$(printf '%s' "$TWO" | jq -c '.holdings[0].return_path = "leg req_1:deliver" | .holdings[1].return_path = "leg req_2:deliver"')"
mkdir -p "$KOTO_STORE/requests"
: > "$KOTO_STORE/requests/req_1.gone"
echo '{"request_id":"req_2","legs":{"deliver":{"disposition":"open"}}}' > "$KOTO_STORE/requests/req_2.json"
eq "a leg whose request isn't here is leg-unclassified; one held here isn't" "leg-unclassified worker-f2" \
    "$(bash "$RH" "${RM[@]}" | jq -r '[.gaps[].gap | select(startswith("leg-"))] | join(" ")')"
fix=$(bash "$RH" "${RM[@]}" | jq -r '.gaps[] | select(.gap == "leg-unclassified worker-f2") | .fix')
grep -q 'reconcile-legs.sh --session <this run> --topic worker-f2 --return-path "leg req_1:deliver"' <<<"$fix" \
    && ok "  ... naming the fix" || bad "  ... naming the fix" "$(bash "$RH" "${RM[@]}" | jq -c .gaps)"
rm -f "$KOTO_STORE/requests/req_1.gone" "$KOTO_STORE/requests/req_2.json"
bash "$RH" "${RM[@]}" >/dev/null 2>&1; eq "a leg whose request can't be read fails the read" 2 $?
rm -rf "$KOTO_STORE/requests"

# A fresh session, as the opener seeds one now: no Run section and no store
# row. Its stored set is read from the run's record/ keys.
SD=coordinate-roadmap-plugin-system-20260926T170000Z
SEN=(env RS_SESSION="$SD")
db_init; seed_session "$SD" "$TWO"
eq "the session holds no store row" "" "$(koto context get "$SD" record/run 2>/dev/null)"
eq "the handover read lists the keys' gaps" "no-arguments no-cap no-coordinator no-reports-to no-next-step Feature 2 no-next-step Feature 3" \
    "$("${SEN[@]}" bash "$RH" "${RM[@]}" | jq -r '[.gaps[].gap] | join(" ")')"
"${SEN[@]}" bash "$RS" "${W[@]}" --run arguments "--roadmap x --cap 2" --by "the human" >/dev/null 2>&1
"${SEN[@]}" bash "$RS" "${W[@]}" --run cap 2 --by "the human" >/dev/null 2>&1
"${SEN[@]}" bash "$RS" "${W[@]}" --run coordinator lane-v2 --by lane-v2 >/dev/null 2>&1
"${SEN[@]}" bash "$RS" "${W[@]}" --run reports-to "the lane's dispatcher at ws-lead" --by "the human" >/dev/null 2>"$T/err"
eq "a reports-to row is written with no store row" 0 $?
"${SEN[@]}" bash "$RS" "${W[@]}" --work "Feature 2" --kind holding --who worker-f2 --next x >/dev/null 2>&1
"${SEN[@]}" bash "$RS" "${W[@]}" --work "Feature 3" --kind holding --who worker-f3 --next y >/dev/null 2>&1
"${SEN[@]}" bash "$RS" "${W[@]}" --told worker-f2 --by lane-v2 >/dev/null 2>&1
"${SEN[@]}" bash "$RH" "${RM[@]}" --check >/dev/null 2>"$T/err" && ok "  ... and the gaps close as record-state.sh writes the keys" \
    || bad "  ... and the gaps close as record-state.sh writes the keys" "$(cat "$T/err")"
"${SEN[@]}" bash "$RS" "${W[@]}" --standing answer --what "panels at the head" --owner "the human" --relayed-by lane-v2 >/dev/null 2>"$T/err"
eq "a Standing row is written" 0 $?
eq "  ... into record/standing" "answer|the human" "$(koto context get "$SD" record/standing | jq -r '.[0] | "\(.kind)|\(.owner)"')"
eq "  ... and read back through the seam" "panels at the head" "$("${SEN[@]}" bash "$RH" "${RM[@]}" | jq -r '.standing[0].what')"

echo "== the crash set (PRD R17) =="
SHA=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
SHB=fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
"${SEN[@]}" bash "$RS" "${W[@]}" --run rules "skill-rules sha256:$SHA" --by coord >/dev/null 2>"$T/err"; eq "a rules row is written" 0 $?
"${SEN[@]}" bash "$RS" "${W[@]}" --run rules "lane-rules sha256:$SHA" --by coord >/dev/null 2>"$T/err"
"${SEN[@]}" bash "$RS" "${W[@]}" --run rules "skill-rules sha256:$SHB" --by coord >/dev/null 2>"$T/err"
eq "  ... one row per label, a new digest replacing its label's" "lane-rules sha256:$SHA|skill-rules sha256:$SHB" \
    "$("${SEN[@]}" bash "$RH" "${RM[@]}" | jq -r '.rules | sort | join("|")')"
"${SEN[@]}" bash "$RS" "${W[@]}" --run briefs "brief-1 sha256:$SHA" --by coord >/dev/null 2>"$T/err"; eq "a briefs row is written" 0 $?
"${SEN[@]}" bash "$RS" "${W[@]}" --run friction friction-log --by coord >/dev/null 2>"$T/err"; eq "a friction row is written" 0 $?
eq "  ... and the handover read names them" "lane's dispatcher at ws-lead|brief-1 sha256:$SHA|friction-log" \
    "$("${SEN[@]}" bash "$RH" "${RM[@]}" | jq -r '"\(.reports_to | sub("^the "; ""))|\(.briefs[0])|\(.friction)"')"
"${SEN[@]}" bash "$RS" "${W[@]}" --run rules "skill-rules sha256:abc" --by coord >/dev/null 2>"$T/err"; eq "a malformed digest is refused" 65 $?
SNAP=$(session_snapshot "$SD")
"${SEN[@]}" bash "$RS" "${W[@]}" --host source_workspace /srv/ws/a --host template_hash "$SHA" --host rules:skill-rules /srv/ws/a/RULES.md > "$T/out" 2>"$T/err"
eq "--host merges into record/host" "0 /srv/ws/a|$SHA|/srv/ws/a/RULES.md" \
    "$? $(koto context get "$SD" record/host | jq -r '"\(.source_workspace)|\(.template_hash)|\(.["rules:skill-rules"])"')"
"${SEN[@]}" bash "$RS" "${W[@]}" --host source_session coordinate-roadmap-plugin-system-20260926T170000Z > /dev/null 2>"$T/err"
eq "  ... keeping what was there" "/srv/ws/a coordinate-roadmap-plugin-system-20260926T170000Z" \
    "$(koto context get "$SD" record/host | jq -r '"\(.source_workspace) \(.source_session)"')"
eq "  ... changing no other key" "$(printf '%s' "$SNAP" | grep -v '^\./host ')" "$(session_snapshot "$SD" | grep -v '^\./host ')"
eq "  ... and the handover read carries it" "/srv/ws/a" "$("${SEN[@]}" bash "$RH" "${RM[@]}" | jq -r '.host.source_workspace')"
eq "  ... and record-source.sh --host prints it" "/srv/ws/a/RULES.md" \
    "$("${SEN[@]}" bash "$HERE/record-source.sh" "${RM[@]}" --host | jq -r '.["rules:skill-rules"]')"
READ=$( ( RS_SESSION=$SD PROG=reader SCOPE=roadmap NAME=plugin-system
    . "$HERE/record-common.sh"; . "$HERE/record-source.sh"; RS_RETRY_PAUSE=0
    rs_record "$T/reader" > /dev/null 2>&1 && jq -cS . "$T/reader" ) )
eq "  ... which the record a reader is handed never holds" "read|" "$([ -n "$READ" ] && echo read)|$(printf '%s' "$READ" | grep -F /srv/ws/a)"
"${SEN[@]}" bash "$RS" "${W[@]}" --host source_workspace relative/path >/dev/null 2>"$T/err"; eq "--host refuses a relative path" 65 $?
"${SEN[@]}" bash "$RS" "${W[@]}" --host template_hash abc >/dev/null 2>"$T/err"; eq "--host refuses a template hash that isn't 64 hex" 65 $?
"${SEN[@]}" bash "$RS" "${W[@]}" --host friction "/srv/gh""p_aaaaaaaaaaaaaaaaaaaaaaaa" >/dev/null 2>"$T/err"; eq "--host refuses a token-shaped string" 65 $?
grep -q 'token-shaped' "$T/err" && ok "  ... naming it" || bad "  ... naming it" "$(cat "$T/err")"
"${SEN[@]}" bash "$RS" "${W[@]}" --host colour blue >/dev/null 2>"$T/err"; eq "--host refuses a key it doesn't know" 64 $?
"${SEN[@]}" bash "$HERE/record-holding.sh" "${W[@]}" --topic worker-f2 --pushed-head "${SHA:0:40}" >/dev/null 2>"$T/err"
eq "the handover read carries a worker's pushed head" "${SHA:0:40}|null" \
    "$("${SEN[@]}" bash "$RH" "${RM[@]}" | jq -r '[.workers[] | .pushed_head | tostring] | join("|")')"
eq "the crash set's rows sit in a Run section with no store row" "" \
    "$(koto context get "$SD" record/run | jq -r '[.[] | select(.key == "store")] | map(.value) | join(" ")')"
eq "no write in this suite reached GitHub" "" "$(gh_writes)"

done_tests record-state_test
