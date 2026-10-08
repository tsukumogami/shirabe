#!/usr/bin/env bash
# record-state_test.sh -- record-state.sh, the one way the stored set's
# sections (Run, Standing, Work) change, and record-handover.sh, which reads
# them and names the gaps.
#
# Covers: --list on a record with none of the sections; Run's keys, a cap and
# arguments, a new coordinator clearing every told row; --told needing a
# coordinator and refusing a second time; a Standing row with owner and
# relayer, its id, --end removing it, an id never reused, and an unreadable
# entry stream refusing a new id; a person's
# event relayed from an unmarked comment; Work rows for a holding (which also
# records its worker as told on its first row only, not on a later update
# after an address change) and for a local agent, upserted, --done, and a
# holding's row dropped once its holding is gone; a decision row parking a
# unit on an open entry and a follow-up row naming a scoping's pull request,
# their refusals, and a new holding taking both over while the scoping holding
# doesn't; each change told as an
# entry after the body; refusals (a holding row for no holding, a malformed
# cap, a session-shaped address, a private repository on a public host); the
# one-writer rule (record-write.sh changing a section refused); a failed entry
# post after a written body (14); and record-handover.sh's report and gaps.
#
# Usage: bash skills/coordinate/scripts/record-state_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RS="$HERE/record-state.sh"
RH="$HERE/record-handover.sh"
RA="$HERE/record-append.sh"

TITLE="Coordinator record: ROADMAP-plugin-system"
RM=(--scope roadmap --name plugin-system --repo "$REPO" --ref 7)
W=("${RM[@]}" --skip-session-checks)
seed() { # seed <record-json>
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' \
        --arg t "$TITLE" --arg b "$(render "$1" issue 2026-09-26T08:00:00Z)"
}
live() { jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB" | bash "$HERE/record-parse.sh"; }
entries() { bash "$RA" "${RM[@]}" --list; }
TWO=$(record_json roadmap plugin-system | jq -c --argjson a "$(holding worker-f2)" \
    --argjson b "$(holding worker-f3 '{"unit": "Feature 3", "pull_request": ""}')" '.holdings = [$a, $b]')

echo "== list =="
seed "$TWO"
eq "--list with none of the sections" '{"run":[],"standing":[],"work":[]}' "$(bash "$RS" "${RM[@]}" --list 2>&1)"
grep -qE 'edit|comments' "$GH_DB.calls" && bad "a read writes nothing" "$(calls)" || ok "a read writes nothing"

echo "== Run =="
bash "$RS" "${W[@]}" --run arguments "--roadmap docs/roadmaps/ROADMAP-plugin-system.md --cap 2" --by "the human" >/dev/null 2>"$T/err"
eq "arguments are set" 0 $?
bash "$RS" "${W[@]}" --run cap 2 --by "the human" >/dev/null 2>"$T/err"; eq "a cap is set" 0 $?
bash "$RS" "${W[@]}" --run cap 1 --by "the human, via the process owner" >/dev/null 2>"$T/err"; eq "a cap is changed" 0 $?
eq "  ... one cap row, the new one" "1 the human, via the process owner" "$(live | jq -r '[.run[] | select(.key == "cap")] | "\(.[0].value) \(.[0].set_by)", length' | head -1)"
eq "  ... and only one" 1 "$(live | jq '[.run[] | select(.key == "cap")] | length')"
bash "$RS" "${W[@]}" --run cap two --by x >/dev/null 2>"$T/err"; eq "a cap that isn't a number is refused" 65 $?
bash "$RS" "${W[@]}" --run told worker-f2 --by x >/dev/null 2>"$T/err"; eq "--run doesn't take told" 64 $?
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
db '.fail = [{match: "comments?per_page", rc: 1, stderr: "gh: boom"}]'
bash "$RS" "${W[@]}" --standing approval --what x --owner y >/dev/null 2>"$T/err"; eq "an unreadable entry stream refuses a new Standing id (2) rather than risk reusing one" 2 $?
eq "  ... and writes nothing" "s1 s3" "$(live | jq -r '[.standing[].standing] | join(" ")')"
db '.fail = []'

echo "== the relay duty: a person's unmarked comment =="
db '.comments = ((.comments // []) + [{repo: "acme/widgets", number: 7, id: 3001, body: "Hold the koto release until the other lane lands.",
    user: "alice", created_at: "2026-10-07T20:00:00Z", updated_at: "2026-10-07T20:00:00Z"}])'
entries | jq -e 'all(.[]; .id != 3001)' >/dev/null && ok "the reader drops a person's unmarked comment" || bad "the reader drops a person's unmarked comment" "$(entries)"
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
bash "$HERE/record-render.sh" --written "$(jq -r .written "$T/now.json")" "$T/gone.json" > "$T/gone.md"
bash "$HERE/record-write.sh" "${W[@]}" --body-file "$T/gone.md" >/dev/null 2>"$T/err"; eq "the holding is torn down" 0 $?
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
bash "$HERE/record-render.sh" --written "$(jq -r .written "$T/now.json")" "$T/f3.json" > "$T/f3.md"
bash "$HERE/record-write.sh" "${W[@]}" --body-file "$T/f3.md" >/dev/null 2>"$T/err"; eq "the follow-up's execution is dispatched" 0 $?
bash "$RS" "${W[@]}" --work "Feature 3" --kind holding --who worker-f3x --next "executing the plan" >/dev/null 2>"$T/err"
eq "  ... and its holding row replaces the follow-up row" "holding worker-f3x" "$(live | jq -r '[.work[] | select(.item == "Feature 3") | "\(.kind) \(.who)"] | join(",")')"
# A new holding for a parked unit takes over its decision row.
live > "$T/now.json"
jq -c --argjson h "$(holding worker-f4 '{"unit": "Feature 4", "pull_request": ""}')" 'del(.written) | .holdings += [$h]' "$T/now.json" > "$T/f4.json"
bash "$HERE/record-render.sh" --written "$(jq -r .written "$T/now.json")" "$T/f4.json" > "$T/f4.md"
bash "$HERE/record-write.sh" "${W[@]}" --body-file "$T/f4.md" >/dev/null 2>"$T/err"; eq "the parked unit is dispatched" 0 $?
bash "$RS" "${W[@]}" --work "Feature 4" --kind holding --who worker-f4 --next "report at its first checkpoint" >/dev/null 2>"$T/err"
eq "  ... and its holding row replaces the decision row" "holding worker-f4" "$(live | jq -r '[.work[] | select(.item == "Feature 4") | "\(.kind) \(.who)"] | join(",")')"
# A holding whose Unit cell is `<tag>: <title>` takes over the rows its tag names.
bash "$RS" "${W[@]}" --work "Feature 6" --kind follow-up --who "acme/widgets#60" --next "/shirabe:execute docs/plans/PLAN-six.md" >/dev/null 2>"$T/err"
live > "$T/now.json"
jq -c --argjson h "$(holding worker-f6 '{"unit": "Feature 6: the exporter", "pull_request": ""}')" 'del(.written) | .holdings += [$h]' "$T/now.json" > "$T/f6.json"
bash "$HERE/record-render.sh" --written "$(jq -r .written "$T/now.json")" "$T/f6.json" > "$T/f6.md"
bash "$HERE/record-write.sh" "${W[@]}" --body-file "$T/f6.md" >/dev/null 2>"$T/err"
bash "$RS" "${W[@]}" --work "Feature 6: the exporter" --kind holding --who worker-f6 --next "executing" >/dev/null 2>"$T/err"
eq "a titled holding row takes over its tag's follow-up row" "Feature 6: the exporter:holding" \
    "$(live | jq -r '[.work[] | select(.item | startswith("Feature 6")) | "\(.item):\(.kind)"] | join(",")')"
eq "  ... and the handover reads the holding's own next step" "executing" \
    "$(bash "$RH" "${RM[@]}" | jq -r '.workers[] | select(.worker == "worker-f6") | .next')"

echo "== one writer =="
seed "$TWO"
bash "$RS" "${W[@]}" --run cap 2 --by "the human" >/dev/null 2>&1
live > "$T/now.json"
jq -c 'del(.written) | .run[0].value = "5"' "$T/now.json" > "$T/edit.json"
bash "$HERE/record-render.sh" --written "$(jq -r .written "$T/now.json")" "$T/edit.json" > "$T/edit.md"
bash "$HERE/record-write.sh" "${W[@]}" --body-file "$T/edit.md" >/dev/null 2>"$T/err"; eq "another writer changing Run is refused" 65 $?
grep -q 'only through record-state.sh' "$T/err" && ok "  ... naming the one writer" || bad "  ... naming the one writer" "$(cat "$T/err")"

echo "== a public host =="
bash "$RS" "${W[@]}" --standing answer --what "wait for acme/secret#5" --owner "the human" >/dev/null 2>"$T/err"; eq "a private repository in a Standing row is refused" 65 $?
bash "$RS" "${W[@]}" --standing answer --what "wait for acme/gadgets#5" --owner "the human" >/dev/null 2>"$T/err"; eq "a public one is fine" 0 $?

echo "== the entry fails after the body =="
db '.fail = [{match: "comments --input", rc: 1, stderr: "gh: You have exceeded a secondary rate limit (HTTP 403)"}]'
bash "$RS" "${W[@]}" --run cap 3 --by "the human" >/dev/null 2>"$T/err"; eq "a failed entry post is 14" 14 $?
eq "  ... after the body was written" 3 "$(live | jq -r '.run[] | select(.key == "cap") | .value')"
grep -q 'Run cap set to 3 by the human' "$T/err" && ok "  ... naming the entry to post" || bad "  ... naming the entry to post" "$(cat "$T/err")"
db '.fail = []'

echo "== the handover read =="
seed "$TWO"
H=$(bash "$RH" "${RM[@]}" 2>"$T/err"); eq "the read prints" 0 $?
eq "an old record has every gap" "no-arguments no-cap no-coordinator no-next-step Feature 2 no-next-step Feature 3" \
    "$(printf '%s' "$H" | jq -r '[.gaps[].gap] | join(" ")')"
bash "$RH" "${RM[@]}" --check >/dev/null 2>"$T/err"; eq "--check fails on gaps" 1 $?
grep -q 'record-state.sh --run cap' "$T/err" && ok "  ... naming the fix" || bad "  ... naming the fix" "$(cat "$T/err")"
bash "$RS" "${W[@]}" --run arguments "--roadmap x --cap 2" --by "the human" >/dev/null 2>&1
bash "$RS" "${W[@]}" --run cap 2 --by "the human" >/dev/null 2>&1
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
eq "a merged holding needs no next step" "no-arguments no-cap no-coordinator no-next-step Feature 2" \
    "$(bash "$RH" "${RM[@]}" | jq -r '[.gaps[].gap] | join(" ")')"

done_tests record-state_test
