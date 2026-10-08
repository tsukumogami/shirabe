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
# holding's row dropped once its holding is gone; each change told as an
# entry after the body; refusals (a holding row for no holding, a malformed
# cap, a session-shaped address, a private repository on a public host); the
# one-writer rule (record-write.sh changing a section refused); a failed entry
# post after a written body (14); an assignment (an issue or a release a
# person assigned) and its refusals; and record-handover.sh's report and gaps.
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
