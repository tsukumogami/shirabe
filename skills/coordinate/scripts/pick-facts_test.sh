#!/usr/bin/env bash
# pick-facts_test.sh -- pick-facts.sh, the facts pick decides on.
#
# Covers: `pick` with coord/pick.json for two executing holdings, one parked
# worker and one local agent (which has no holding) reading active 2 and
# parked 1; each unit's blocked, blocked_by and blocker_landed flags as the
# fixture roadmap's Dependencies and Status lines say, in the roadmap's
# order, with the holding that covers it; the prefix heading form; the
# roadmap read from the host's default branch; `scope-complete` when every
# feature is done (a Status opening Done or Dropped, a note after it
# allowed), and not for `Doneness` or a roadmap with no features; a
# missing roadmap (2); discipline units from the host's open issues with the
# discipline's label in issue-number order (never a search); `rotation-over`
# only after record/rotation's end date, or once the rotation's reasoning is
# written, a session with no record/rotation refused (2), and no carry owed
# (a rotation carries its predecessor's decisions when it opens); CAP and PARKED_BOUND from the session; the
# sealed token; every token in koto's capture alphabet; pick.json's host; every
# Unit cell form dispatch-common.sh dc_unit_forms lists from pick.json is one
# this script reads as covering its unit, and the old template's form isn't;
# units a person assigned (Standing assignment rows: issues or pull requests
# read in their own repositories in one GraphQL read, a closed or merged one
# done, a failed, partial or unknown-state answer refused; a release open
# until its row ends) listed
# after the roadmap's, covered by a holding, their forms the dispatch path
# takes, and an open one keeping the roadmap from completing; a unit's
# awaiting, answered and follow_up from the record's Work rows and Decisions
# entries, none of them holding a slot; a unit's verdict_owed from a
# verdict-owed Work row, with and without its holding, and no brief form for
# it; a unit's rework text from a rework Work row, the unit offered and
# briefable. On a roadmap/v3 roadmap (`## Milestones`, `### Milestone N:`)
# the facts are the v2 roadmap's (units, dependencies, blocked flags and
# statuses, holdings, landed and Work rows), the Dependencies prose still
# saying `Feature N` naming the item tagged `Milestone N`; holdings, a landed
# row and verdict-owed and follow-up rows written under `Feature N` cover
# `Milestone N`, a holding naming `Milestone 2` covers a v2 `Feature 2`, and
# `Milestone 03`, `feature 2` and `#2` cover nothing; a pause written on
# `Feature 3` marks the v3 unit `Milestone 3` paused and no other, a go-ahead
# on `Feature 4` lets `Milestone 4` through a pause on all, and a pause on
# `Milestone 2` holds a v2 `Feature 2`. The decider's slice,
# coord/pick_slice.json: on a roadmap of 200 Done features and 3 open ones the
# facts are over the 12,000-byte cap and the slice under it, the Done units
# collapsed to a done list, a blocker named by its tag, null, false and
# empty-list fields left out of units and holdings, the counts, bounds,
# pauses and decisions the facts', and its key set pinned; a done unit owed a verdict, with rework or
# covered by a holding keeps its row; a second visit rewrites the slice; every
# coordinate.pick.choice fixture's input is a slice, and some carry a long
# done list. The record is the run's session's; no record issue or pull request
# is read.
#
# Usage: bash skills/coordinate/scripts/pick-facts_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
PF="$HERE/pick-facts.sh"
CL="$HERE/coord-log.sh"
tok_shape() {
    local re='^[A-Za-z0-9 :/_.@-]*$'
    if [[ ${2% sealed:*} =~ $re ]]; then ok "$1"; else bad "$1" "[$2]"; fi
}
RP=docs/roadmaps/ROADMAP-plugin-system.md
roadmap() { # roadmap <s1> <s2> <s3> <s4> <s5>
    printf -- '---\nstatus: Active\n---\n\n# ROADMAP\n\n## Features\n\n'
    printf '### Feature 1: Loader\n**Dependencies:** None\n**Status:** %s\n\n' "$1"
    printf '### Feature 2: Registry\n**Needs:** `needs-design`\n**Dependencies:** Feature 1\n**Status:** %s\n\n' "$2"
    printf '### Feature 3: Sandbox\n**Dependencies:** Features 1 and 2\n**Status:** %s\n\n' "$3"
    printf '### Feature 4: Docs\n**Dependencies:** None\n**Status:** %s\n\n' "$4"
    printf '### Feature 5: Telemetry\n**Dependencies:** Feature 4\n**Status:** %s\n\n' "$5"
    printf '## Sequencing Rationale\n\nNone.\n'
}
pr() { # pr <n> <state> <draft>
    db '.prs += [{repo: "acme/widgets", number: $n, title: "w", body: "", state: $s, isDraft: ($d == "true"), isCrossRepository: false,
        baseRefName: "main", headRefName: "feat/\($n)", headRefOid: $h, author: "alice", editor: null}]' \
        --argjson n "$1" --arg s "$2" --arg d "$3" --arg h "$SHA_HEAD"
}
link() { printf '[#%s](https://github.com/acme/widgets/pull/%s)' "$1" "$1"; }
seed() { # seed <record-json>: the record the next session() holds
    db_init
    SEED=$1 ROT=
}
# Built with --arg: bash 3.2 misreads escaped quotes nested in "$(...)".
X_A=$(jq -nc --arg p "$(link 21)" '{unit: "Feature 2", pull_request: $p}')
X_C=$(jq -nc --arg p "$(link 23)" --arg h "$SHA_HEAD" '{unit: "Feature 3: Sandbox", phase: "scoping-ahead", pull_request: $p, verified_head: $h}')
HOLDINGS=$(jq -nc --argjson a "$(holding alpha "$X_A")" \
    --argjson b "$(holding beta '{"unit": "Feature 4", "pull_request": ""}')" \
    --argjson c "$(holding gamma "$X_C")" \
    '[$a, $b, $c]')
REC=$(record_json roadmap plugin-system | jq -c --argjson h "$HOLDINGS" '.holdings = $h')
N=0
session() { # session <vars-json> <name>: a run at pick_facts, holding the seeded record (and a rotation's window)
    N=$((N + 1))
    S="coordinate-$2-20260926T08$(printf %02d "$N")00Z"
    found_session "$S" "$1"
    seed_session "$S" "$SEED"
    [ -z "$ROT" ] || printf '%s' "$ROT" | koto context add "$S" record/rotation
    log_to "$S" reconcile pick_facts
}
facts() { cat "$KOTO_STORE/context/$S/coord/pick.json"; }

echo "== roadmap: pick =="
seed "$REC"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' Dropped)"
# The local agent is a subagent in the coordinator's own session: it never has
# a Holdings row, so the fixture's local agent is visible only as its absence.
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
OUT=$(bash "$PF" --session "$S" 2>"$T/err")
eq "features left to do is pick" "pick" "${OUT% sealed:*}"
tok_shape "pick is in koto's capture alphabet" "$OUT"
bash "$CL" check --session "$S" --state pick_facts --sealed "$OUT" && ok "the token is sealed to pick_facts" || bad "the token is sealed to pick_facts"
eq "two executing holdings, one parked worker and a local agent read active 2 and parked 1" "2 1" "$(facts | jq -r '"\(.active) \(.parked)"')"
eq "the cap and parked bound are the session's" "5 3" "$(facts | jq -r '"\(.cap) \(.parked_bound)"')"
eq "units come in the roadmap's order" "Feature 1,Feature 2,Feature 3,Feature 4,Feature 5" "$(facts | jq -r '[.units[].unit] | join(",")')"
eq "Feature 2 depends on a Done feature: unblocked, blocker landed" "false [] true" "$(facts | jq -c -r '.units[1] | "\(.blocked) \(.blocked_by | tojson) \(.blocker_landed)"')"
eq "Feature 3 waits on Feature 2: blocked by 2, blocker not landed" "true [2] false" "$(facts | jq -c -r '.units[2] | "\(.blocked) \(.blocked_by | tojson) \(.blocker_landed)"')"
eq "Feature 4 has no dependency: unblocked, nothing to land" "false [] false" "$(facts | jq -c -r '.units[3] | "\(.blocked) \(.blocked_by | tojson) \(.blocker_landed)"')"
eq "Feature 5 is Dropped: never blocked, though its dependency isn't Done" "false []" "$(facts | jq -c -r '.units[4] | "\(.blocked) \(.blocked_by | tojson)"')"
eq "Done and Dropped read done" "true true false" "$(facts | jq -r '[.units[0].done, .units[4].done, .units[1].done] | map(tostring) | join(" ")')"
eq "each unit carries the holding that covers it" '{"worker":"alpha","phase":"executing"}|{"worker":"gamma","phase":"scoping-ahead"}|{"worker":"beta","phase":"executing"}|null' \
    "$(facts | jq -c -r '[.units[1].holding, .units[2].holding, .units[3].holding, .units[0].holding] | map(tojson) | join("|")')"
eq "the holdings list which is parked" "alpha:false beta:false gamma:true" "$(facts | jq -r '[.holdings[] | "\(.worker):\(.parked)"] | join(" ")')"
eq "no holding is merged" "alpha:false beta:false gamma:false" "$(facts | jq -r '[.holdings[] | "\(.worker):\(.merged)"] | join(" ")')"
grep -q "contents/$RP?ref=main" "$GH_DB.calls" && ok "the roadmap is read from the default branch" || bad "the roadmap is read from the default branch" "$(calls)"
# A confirmed merge clears a row's Pull request cell and keeps its Verified
# head until teardown: the row is merged and holds no slot under the cap.
X_M=$(jq -nc --arg h "$SHA_HEAD" '{unit: "Feature 2", pull_request: "", verified_head: $h}')
seed "$(record_json roadmap plugin-system | jq -c --argjson m "$(holding alpha "$X_M")" --argjson b "$(holding beta '{"unit": "Feature 4", "pull_request": ""}')" '.holdings = [$m, $b]')"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' Dropped)"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
bash "$PF" --session "$S" >/dev/null 2>"$T/err"
eq "a merged row reads merged, neither active nor parked" "alpha:true:false 1 0" "$(facts | jq -r '([.holdings[] | select(.worker == "alpha") | "\(.worker):\(.merged):\(.parked)"] | join(" ")) + " \(.active) \(.parked)"')"
grep -qE 'search|PUT|POST|DELETE|edit|ready' "$GH_DB.calls" && bad "it only reads" "$(calls)" || ok "it only reads"

echo "== roadmap: owed decision work, the DESIGN's blocking table's third column =="
ESC='"round": "1", "verdict": "escalate", "recommendation": "wait", "reason": "r", "context": "c", "problem": "p", "grounds": "scope", "target": "a person"'
dentry() { # dentry <n> <state> [extra JSON members]
    printf '{"decision": "%s", "round": "0", "question": "Q%s?", "options": "ship -- now\\nwait -- later", "state": "%s", "source": "self [20260925T080000Z raise %s]", "updated": "2026-09-26T07:00Z"%s}' \
        "$1" "$1" "$2" "$1" "${3:+, $3}"
}
# picked <label> <verdict> <entries...>: the record with those entries, then pick_facts
picked() {
    local label=$1 want=$2; shift 2
    seed "$(printf '%s' "$REC" | jq -c --argjson e "[$(IFS=,; echo "$*")]" '.decisions = {next: 20, entries: $e}')"; pr 21 OPEN true; pr 23 OPEN false
    db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$RMTEXT"
    session "$(roadmap_vars plugin-system)" roadmap-plugin-system
    OUT=$(bash "$PF" --session "$S" 2>"$T/err")
    eq "$label" "$want" "${OUT% sealed:*}"
}
RMTEXT=$(roadmap Done 'In progress' 'Not started' 'Not started' Dropped)
# An unrecorded write: a visit to decision_raise that left no entry stamped for it.
seed "$REC"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$RMTEXT"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
log_to "$S" pick_facts decision_raise; log_to "$S" decision_raise decision_next; log_to "$S" decision_next pick_facts
OUT=$(bash "$PF" --session "$S" 2>"$T/err")
eq "an unrecorded write is decisions" "decisions unrecorded-raise" "${OUT% sealed:*}"
picked "an owed withdrawal is decisions" "decisions withdraw" "$(dentry 2 coordinator-verdict '"owed": "withdrawal"')"
picked "an owed reply is decisions" "decisions reply" \
    "$(dentry 3 settled '"owed": "reply", "outcome": "wait; reason: r", "decided_by": "a person", "source": "worker w1 [20260925T080000Z report 1.1]"')"
picked "an owed escalation is decisions" "decisions escalate" "$(dentry 5 escalated "$ESC, \"owed\": \"escalation\"")"
picked "a proposed entry is decisions" "decisions take" "$(dentry 6 proposed)"
tok_shape "decisions is in koto's capture alphabet" "$OUT"
picked "an unjudged entry is decisions" "decisions verdict" "$(dentry 7 coordinator-verdict)"
picked "a held entry is not" "pick" "$(dentry 7 coordinator-verdict '"verdict": "hold", "reason": "waits on the benchmark"')"
picked "an escalated entry that owes nothing is not" "pick" "$(dentry 5 escalated "$ESC")" "$(dentry 8 settled '"outcome": "ship; reason: r", "decided_by": "the coordinator"')"
eq "pick.json carries the unsettled entries, not the settled one" "5:escalated:wait:a person" \
    "$(facts | jq -r '[.decisions[] | "\(.decision):\(.state):\(.recommendation):\(.target)"] | join(" ")')"
RMTEXT=$(roadmap Done Done Dropped Done Dropped)
picked "owed decision work comes before scope-complete" "decisions take" "$(dentry 6 proposed)"
picked "an escalation that owes nothing lets the scope complete, for the close to report" "scope-complete" "$(dentry 5 escalated "$ESC")"

echo "== roadmap: units a person assigned outside the roadmap (shirabe#607) =="
STAND=$(jq -nc '[{standing: "s3", kind: "assignment", on: "acme/widgets#591", until: "", what: "pick the review level up front", owner: "the human", relayed_by: "", set: "2026-10-06T15:00Z"},
    {standing: "s4", kind: "assignment", on: "#592", until: "", what: "a second fix", owner: "the human", relayed_by: "", set: "2026-10-06T15:00Z"},
    {standing: "s5", kind: "assignment", on: "release acme/widgets v0.25.0", until: "", what: "cut v0.25.0 once #591 lands", owner: "the human", relayed_by: "", set: "2026-10-06T15:00Z"}]')
seed "$(record_json roadmap plugin-system | jq -c --argjson s "$STAND" --argjson h "$(holding w591 '{"unit": "acme/widgets#591", "pull_request": ""}')" '.standing = $s | .holdings = [$h]')"
db '.issues += [{repo: "acme/widgets", number: 591, title: "pick the review level up front", body: "", state: "open", author: "alice", editor: null},
    {repo: "acme/widgets", number: 592, title: "a second fix", body: "", state: "closed", author: "alice", editor: null}]'
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done Done Done Dropped)"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
reset_calls
OUT=$(bash "$PF" --session "$S" 2>"$T/err")
eq "an open assigned unit keeps the roadmap from completing" pick "${OUT% sealed:*}"
eq "the assigned units follow the roadmap's, each with its row" "acme/widgets#591:s3 #592:s4 release acme/widgets v0.25.0:s5" \
    "$(facts | jq -r '[.units[] | select(.assigned != null) | "\(.unit):\(.assigned)"] | join(" ")')"
eq "an issue is read for its title and state; a closed one is done" "pick the review level up front:false a second fix:true" \
    "$(facts | jq -r '[.units[] | select(.number == 591 or .number == 592) | "\(.title):\(.done)"] | join(" ")')"
eq "a release is open until its row ends" "to release false" "$(facts | jq -r '.units[] | select(.unit | startswith("release")) | "\(.status) \(.done)"')"
eq "a holding covers an assigned unit by its id" '{"worker":"w591","phase":"executing"}' "$(facts | jq -c '.units[] | select(.unit == "acme/widgets#591") | .holding')"
facts > "$T/assigned-pick.json"
eq "the dispatch path takes the assigned units' ids, and host#n for #n" "acme/widgets#591 #592 acme/widgets#592 release acme/widgets v0.25.0" \
    "$(. "$HERE/dispatch-common.sh"; dc_unit_forms "$T/assigned-pick.json" | grep -v '^Feature' | tr '\n' ' ' | sed 's/ $//')"
eq "every assigned issue comes from one GraphQL read, none from gh issue view (shirabe#840)" "1 0" \
    "$(grep -c 'query pickAssigned(' "$GH_DB.calls") $(grep -c 'issue view 59[12]' "$GH_DB.calls")"
grep -q -- "-f o0=acme -f r0=widgets -F n0=591 -f o1=acme -f r1=widgets -F n1=592" "$GH_DB.calls" \
    && ok "each assigned issue is read in its own repository" || bad "each assigned issue is read in its own repository" "$(calls)"
eq "the record is read from the session, never from GitHub" 0 "$(grep -cE '^(issue|pr) view 7 ' "$GH_DB.calls")"
eq "the holdings are record-holding.sh --list's" "$(bash "$HERE/record-holding.sh" --list --session "$S" | jq -c '[.[].worker]')" \
    "$(facts | jq -c '[.holdings[].worker]')"
# refused <label> <db change>: the assigned issues' read fails or comes back
# short, and pick-facts fails the read (exit 2) rather than drop the unit or
# read it closed, writing no facts.
refused() {
    seed "$(record_json roadmap plugin-system | jq -c --argjson s "$STAND" '.standing = $s')"
    db '.issues += [{repo: "acme/widgets", number: 591, title: "t", body: "", state: "open", author: "alice", editor: null},
        {repo: "acme/widgets", number: 592, title: "a second fix", body: "", state: "closed", author: "alice", editor: null}]'
    db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done Done Done Dropped)"
    db "$2"
    session "$(roadmap_vars plugin-system)" roadmap-plugin-system
    bash "$PF" --session "$S" > /dev/null 2> "$T/err"
    eq "$1: exit 2" 2 $?
    grep -q "cannot read the assigned units" "$T/err" && ok "$1: and says the assigned units couldn't be read" || bad "$1: and says the assigned units couldn't be read" "$(cat "$T/err")"
    if [ -e "$KOTO_STORE/context/$S/coord/pick.json" ]; then bad "$1: no facts are written" "$(facts)"; else ok "$1: no facts are written"; fi
}
refused "a failed read (rate limited)" '.graphql_fail = true'
refused "a partial answer, the last issue null with no error" '.graphql_partial = true'
refused "an issue GitHub can't resolve" '.issues |= map(select(.number != 592))'
refused "a state other than OPEN, CLOSED or MERGED" '(.issues[] | select(.number == 592)).state = "op"'
# A row may name a pull request: it reads like an issue, open while OPEN and
# done once MERGED (or CLOSED).
PRSTAND=$(jq -nc '[{standing: "s6", kind: "assignment", on: "#30", until: "", what: "land the fix", owner: "the human", relayed_by: "", set: "2026-10-06T15:00Z"},
    {standing: "s7", kind: "assignment", on: "#31", until: "", what: "land the next", owner: "the human", relayed_by: "", set: "2026-10-06T15:00Z"}]')
seed "$(record_json roadmap plugin-system | jq -c --argjson s "$PRSTAND" '.standing = $s')"
pr 30 MERGED false; pr 31 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done Done Done Dropped)"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
OUT=$(bash "$PF" --session "$S" 2>"$T/err"); rc=$?
eq "a pull request named by an assignment reads: exit 0" 0 "$rc"
eq "  ... merged is done, open isn't" "#30:merged:true #31:open:false" \
    "$(facts | jq -r '[.units[] | select(.assigned != null) | "\(.unit):\(.status):\(.done)"] | join(" ")')"
eq "  ... and the open one keeps the roadmap from completing" pick "${OUT% sealed:*}"
seed "$(record_json roadmap plugin-system | jq -c --argjson s "$(printf '%s' "$STAND" | jq -c '[.[1]]')" '.standing = $s')"
db '.issues += [{repo: "acme/widgets", number: 592, title: "a second fix", body: "", state: "closed", author: "alice", editor: null}]'
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done Done Done Dropped)"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
OUT=$(bash "$PF" --session "$S" 2>"$T/err")
eq "with every assigned unit done, the roadmap completes" scope-complete "${OUT% sealed:*}"
echo "== roadmap: a unit parked on a decision, one answered, and a follow-up =="
WORK=$(jq -nc '[{item: "Feature 2", kind: "decision", who: "decision 5", next: "dispatch once decided", wakes: "0", updated: "2026-09-26T07:00Z"},
    {item: "Feature 4", kind: "decision", who: "decision 8", next: "dispatch once decided", wakes: "0", updated: "2026-09-26T07:00Z"},
    {item: "Feature 3", kind: "decision", who: "decision 9", next: "an entry no longer in the record", wakes: "0", updated: "2026-09-26T07:00Z"},
    {item: "Feature 5", kind: "follow-up", who: "acme/widgets#41", next: "/shirabe:execute docs/plans/PLAN-telemetry.md", wakes: "0", updated: "2026-09-26T07:00Z"}]')
seed "$(record_json roadmap plugin-system | jq -c --argjson w "$WORK" --argjson a "$(dentry 5 escalated "$ESC")" \
    --argjson b "$(dentry 8 settled '"outcome": "keep it; reason: the sandbox needs it", "decided_by": "a person"')" \
    '.work = $w | .decisions = {next: 20, entries: [$a, $b]}')"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'Not started' 'Not started' 'Not started' 'Not started')"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
OUT=$(bash "$PF" --session "$S" 2>"$T/err")
eq "an escalated entry that owes nothing doesn't stop pick" pick "${OUT% sealed:*}"
eq "a unit parked on an open entry is awaiting it" "5 null" "$(facts | jq -r '.units[] | select(.unit == "Feature 2") | "\(.awaiting) \(.answered)"')"
eq "one whose entry is settled is answered, with the outcome" 'null {"decision":"8","outcome":"keep it; reason: the sandbox needs it"}' \
    "$(facts | jq -c -r '.units[] | select(.unit == "Feature 4") | "\(.awaiting) \(.answered | tojson)"')"
eq "one whose entry is gone is answered with no outcome" 'null {"decision":"9","outcome":""}' \
    "$(facts | jq -c -r '.units[] | select(.unit == "Feature 3") | "\(.awaiting) \(.answered | tojson)"')"
eq "a follow-up names its scoping pull request and its execution" '{"after":"acme/widgets#41","next":"/shirabe:execute docs/plans/PLAN-telemetry.md"}' \
    "$(facts | jq -c '.units[] | select(.unit == "Feature 5") | .follow_up')"
eq "a unit with no such row carries none of the three" "null null null" "$(facts | jq -r '.units[0] | "\(.awaiting) \(.answered) \(.follow_up)"')"
eq "none of them holds a slot" "0 0" "$(facts | jq -r '"\(.active) \(.parked)"')"

echo "== roadmap: a landed unit, its roadmap pull request pending =="
RS='{"action":"roadmap-status","target":"Feature 4 [#30](https://github.com/acme/widgets/pull/30)","verified_head":"","attempted":"2026-09-26T09:00Z","how_to_confirm":"the roadmap on main reads Feature 4 Done"}'
seed "$(printf '%s' "$REC" | jq -c --argjson r "$RS" '.side_effects = [$r]')"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' 'Not started')"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
bash "$PF" --session "$S" >/dev/null 2>"$T/err"; eq "the facts are read" 0 $?
eq "the unit the record holds a roadmap pull request for is landed, with its link" "[#30](https://github.com/acme/widgets/pull/30)" \
    "$(facts | jq -r '.units[] | select(.unit == "Feature 4") | .landed')"
eq "  ... no other unit is" "null null null null" "$(facts | jq -r '[.units[] | select(.unit != "Feature 4") | .landed | tostring] | join(" ")')"
eq "  ... and it isn't Done for its dependent until the roadmap says so" "true [4]" \
    "$(facts | jq -r '.units[] | select(.unit == "Feature 5") | "\(.blocked) \(.blocked_by | tostring)"')"
. "$HERE/dispatch-common.sh"
facts > "$T/pick.json"
dc_unit_forms "$T/pick.json" | grep -qx 'Feature 4' && bad "  ... and the dispatch path renders no brief for it" "$(dc_unit_forms "$T/pick.json")" \
    || ok "  ... and the dispatch path renders no brief for it"
dc_unit_forms "$T/pick.json" | grep -qx 'Feature 5' && ok "  ... while other units keep their forms" || bad "  ... while other units keep their forms"

echo "== roadmap: a milestone whose verdict is owed =="
# A verdict-owed Work row (docs/designs/DESIGN-milestone-verdicts.md) marks
# its unit with and without the holding that did the work.
OWED=$(jq -nc '[{item: "Feature 2", kind: "verdict-owed", who: "alpha", next: "verdict owed since 2026-09-26", wakes: "0", updated: "2026-09-26T07:00Z"},
    {item: "Feature 5", kind: "verdict-owed", who: "none", next: "verdict owed since 2026-09-26", wakes: "0", updated: "2026-09-26T07:00Z"}]')
seed "$(printf '%s' "$REC" | jq -c --argjson w "$OWED" '.work = $w')"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'In progress' 'Not started' 'Not started')"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
bash "$PF" --session "$S" >/dev/null 2>"$T/err"; eq "the facts are read with verdicts owed" 0 $?
eq "a unit with a verdict-owed row and its holding reads verdict_owed" "true alpha" \
    "$(facts | jq -r '.units[] | select(.unit == "Feature 2") | "\(.verdict_owed) \(.holding.worker)"')"
eq "  ... and one whose holding is gone too" "true null" \
    "$(facts | jq -r '.units[] | select(.unit == "Feature 5") | "\(.verdict_owed) \(.holding)"')"
eq "  ... no other unit does" "false false false" "$(facts | jq -r '[.units[] | select(.unit != "Feature 2" and .unit != "Feature 5") | .verdict_owed | tostring] | join(" ")')"
facts > "$T/owed-pick.json"
dc_unit_forms "$T/owed-pick.json" | grep -qx 'Feature 5' && bad "  ... and the dispatch path renders no brief for it" "$(dc_unit_forms "$T/owed-pick.json")" \
    || ok "  ... and the dispatch path renders no brief for it"

echo "== roadmap: a milestone a changes-needed verdict sent back =="
# A rework row (roadmap-status.sh --confirm of a changes-needed verdict)
# carries its text to the unit, which is offered like any other.
REWORK=$(jq -nc '[{item: "Feature 5", kind: "rework", who: "verdict 1001", next: "Evidence clauses not held: 2. Changes needed: name the skipped plugin", wakes: "0", updated: "2026-09-26T07:00Z"}]')
seed "$(printf '%s' "$REC" | jq -c --argjson w "$REWORK" '.work = $w')"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'In progress' 'Not started' 'In progress')"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
bash "$PF" --session "$S" >/dev/null 2>"$T/err"; eq "the facts are read with a rework row" 0 $?
eq "the unit carries its rework text, not verdict_owed, no holding, not done" \
    "Evidence clauses not held: 2. Changes needed: name the skipped plugin|false|null|false" \
    "$(facts | jq -r '.units[] | select(.unit == "Feature 5") | "\(.rework)|\(.verdict_owed)|\(.holding)|\(.done)"')"
eq "  ... no other unit carries one" "null null null null" "$(facts | jq -r '[.units[] | select(.unit != "Feature 5") | .rework | tostring] | join(" ")')"
facts > "$T/rework-pick.json"
dc_unit_forms "$T/rework-pick.json" | grep -qx 'Feature 5' && ok "  ... and the dispatch path can brief it" || bad "  ... and the dispatch path can brief it" "$(dc_unit_forms "$T/rework-pick.json")"

echo "== roadmap: pauses =="
pause_row() { # pause_row <id> <kind> <on> <until>
    jq -nc --arg s "$1" --arg k "$2" --arg o "$3" --arg u "$4" \
        '{standing: $s, kind: $k, on: $o, until: $u, what: "x", owner: "the human", relayed_by: "", set: "2026-10-01T19:37Z"}'
}
seed "$(printf '%s' "$REC" | jq -c --argjson a "$(pause_row s1 pause "Feature 2" lifted)" '.standing = [$a]')"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' 'Not started')"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
bash "$PF" --session "$S" >/dev/null 2>"$T/err"; eq "the facts are read with a pause standing" 0 $?
eq "a unit's pause marks that unit and the holding covering it, and nothing else" "s1 s1 null null" \
    "$(facts | jq -r '[(.units[] | select(.unit == "Feature 2") | .paused), (.holdings[] | select(.worker == "alpha") | .paused), (.units[] | select(.unit == "Feature 4") | .paused), (.holdings[] | select(.worker == "beta") | .paused)] | map(tostring) | join(" ")')"
eq "  ... the facts list it in force, and the whole coordinator isn't paused" "s1 in-force null" "$(facts | jq -r '"\(.pauses[0].standing) \(.pauses[0].state) \(.paused_all)"')"
seed "$(printf '%s' "$REC" | jq -c --argjson a "$(pause_row s1 pause all "time 2099-01-01T00:00Z")" --argjson g "$(pause_row s2 go-ahead "Feature 4" "")" '.standing = [$a, $g]')"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' 'Not started')"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
bash "$PF" --session "$S" >/dev/null 2>"$T/err"
eq "an all pause holds the coordinator and every unit but the one a go-ahead names" "s1 s1 null s2" \
    "$(facts | jq -r '[.paused_all, (.units[] | select(.unit == "Feature 3") | .paused), (.units[] | select(.unit == "Feature 4") | .paused), .go_aheads[0].standing] | map(tostring) | join(" ")')"
seed "$(printf '%s' "$REC" | jq -c --argjson a "$(pause_row s1 pause all "time 2000-01-01T00:00Z")" '.standing = [$a]')"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' 'Not started')"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
bash "$PF" --session "$S" >/dev/null 2>"$T/err"
eq "a pause whose minute has passed is met and holds nothing" "met null null" \
    "$(facts | jq -r '[.pauses[0].state, .paused_all, (.units[] | select(.unit == "Feature 3") | .paused)] | map(tostring) | join(" ")')"

echo "== roadmap: scope-complete =="
RM=(--scope roadmap --name plugin-system --repo "$REPO" --no-seal)
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done. Dropped Done Dropped)"
OUT=$(RS_SESSION="$S" bash "$PF" "${RM[@]}" 2>"$T/err"); eq "every feature Done or Dropped is scope-complete" scope-complete "$OUT"
tok_shape "scope-complete is in koto's capture alphabet" "$OUT"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done Dropped Done 'Done (mostly)')"
eq "a Status opening Done and a note reads done" scope-complete "$(RS_SESSION="$S" bash "$PF" "${RM[@]}" 2>/dev/null)"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done Dropped Done Doneness)"
eq "one feature not quite Done is pick" pick "$(RS_SESSION="$S" bash "$PF" "${RM[@]}" 2>/dev/null)"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(printf '# ROADMAP\n\n## Features\n\nTBD.\n')"
eq "a roadmap with no features is not complete" pick "$(RS_SESSION="$S" bash "$PF" "${RM[@]}" 2>/dev/null)"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(printf '## Features\n\n### ED1: Loader\n**Status:** Done\n\n### ED2: Registry\n**Dependencies:** F1\n**Status:** Dropped\n')"
eq "the prefix heading form reads the same" scope-complete "$(RS_SESSION="$S" bash "$PF" "${RM[@]}" 2>/dev/null)"
db '.files["acme/widgets"] |= del(.["main:" + $p])' --arg p "$RP"
RS_SESSION="$S" bash "$PF" "${RM[@]}" >/dev/null 2>&1; eq "a roadmap missing from the default branch exits 2" 2 $?
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done Done Done Done)"
db '.fail = [{match: "pr view 23", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
RS_SESSION="$S" bash "$PF" "${RM[@]}" >/dev/null 2>&1; eq "a failed holding read exits 2" 2 $?

echo "== discipline =="
# dseed [end]: the labelled issues, and the rotation's record and window,
# 2026-09-22 to END (2026-09-29 by default), in its record/rotation.
dseed() {
    db_init
    db '.issues += [{repo: "acme/widgets", number: 5, title: "flaky lint", body: "", state: "open", labels: ["ci-health"], author: "a"},
                    {repo: "acme/widgets", number: 3, title: "slow cache", body: "", state: "open", labels: ["ci-health", "perf"], author: "a"},
                    {repo: "acme/widgets", number: 9, title: "unrelated", body: "", state: "open", labels: ["docs"], author: "a"},
                    {repo: "acme/widgets", number: 4, title: "done already", body: "", state: "closed", labels: ["ci-health"], author: "a"}]'
    SEED=$(record_json discipline ci-health | jq -c --argjson h "$(holding alpha '{"unit": "#5", "pull_request": ""}')" '.holdings = [$h]')
    ROT=$(jq -nc --arg e "${1:-2026-09-29}" '{start: "2026-09-22", end: $e, host_repo: "acme/widgets"}')
}
dseed
session "$(discipline_vars ci-health | jq -c '.CAP = "4" | .PARKED_BOUND = "2"')" discipline-ci-health
reset_calls
OUT=$(bash "$PF" --session "$S" --today 2026-09-29 2>"$T/err")
eq "on record/rotation's end date the rotation goes on" pick "${OUT% sealed:*}"
eq "units are the open labelled issues in number order" "#3 #5" "$(facts | jq -r '[.units[].unit] | join(" ")')"
eq "the issue a holding covers carries it" "null alpha" "$(facts | jq -r '[.units[] | .holding.worker // "null"] | join(" ")')"
eq "the session's CAP and PARKED_BOUND" "4 2" "$(facts | jq -r '"\(.cap) \(.parked_bound)"')"
grep -q '^issue list --repo acme/widgets --state open --label ci-health --json number,title --limit 200$' "$GH_DB.calls" \
    && ok "issues are listed by label, never searched" || bad "issues are listed by label, never searched" "$(calls)"
eq "no record pull request or issue is read" 0 "$(grep -cE '^(pr|issue) view' "$GH_DB.calls")"
OUT=$(RS_SESSION="$S" bash "$PF" --scope discipline --name ci-health --repo "$REPO" --today 2026-09-30 --no-seal 2>"$T/err")
eq "after the end date it is rotation-over" rotation-over "$OUT"
tok_shape "rotation-over is in koto's capture alphabet" "$OUT"
printf '"Lint is flaky."' | koto context add "$S" record/reasoning
eq "with the rotation's reasoning written it is rotation-over before the end date" rotation-over \
    "$(RS_SESSION="$S" bash "$PF" --scope discipline --name ci-health --repo "$REPO" --today 2026-09-25 --no-seal 2>/dev/null)"
rm -f "$KOTO_STORE/context/$S/record/rotation"
RS_SESSION="$S" bash "$PF" --scope discipline --name ci-health --repo "$REPO" --no-seal >/dev/null 2>&1; eq "a session with no record/rotation exits 2" 2 $?
# The predecessor's unsettled decision: carried when the rotation opened, so
# no carry is owed here.
PRED=coordinate-discipline-ci-health-20260919T080000Z
seed_session "$PRED" "$(record_json discipline ci-health | jq -c --argjson e "[$(dentry 5 escalated "$ESC")]" '.decisions = {next: 9, entries: $e}')"
dseed
ROT=$(printf '%s' "$ROT" | jq -c --arg p "$PRED" '.predecessor = $p')
session "$(discipline_vars ci-health)" discipline-ci-health
OUT=$(bash "$PF" --session "$S" --today 2026-09-29 2>"$T/err")
eq "a predecessor's unsettled decision owes no carry" "pick" "${OUT% sealed:*}"

echo "== roadmap/v3: the same facts as v2, the record under Feature N =="
# rmv <schema> <statuses...>: roadmap()'s text with that schema, and on v3
# its items under `## Milestones` headed `### Milestone N:`; the Dependencies
# prose (`Feature 1`, `Features 1 and 2`, `Feature 4`) is left as it is.
rmv() {
    local sch=$1; shift
    roadmap "$@" | awk -v s="$sch" 'NR == 1 { print; print "schema: " s; next } { print }' \
        | if [ "$sch" = roadmap/v3 ]; then sed -e 's/^## Features$/## Milestones/' -e 's/^### Feature \([0-9]\)/### Milestone \1/'; else cat; fi
}
RS4='{"action":"roadmap-status","target":"Feature 4 [#30](https://github.com/acme/widgets/pull/30)","verified_head":"","attempted":"2026-09-26T09:00Z","how_to_confirm":"the roadmap on main reads Feature 4 Done"}'
ROWS=$(jq -nc '[{item: "Feature 5", kind: "verdict-owed", who: "none", next: "verdict owed since 2026-09-26", wakes: "0", updated: "2026-09-26T07:00Z"},
    {item: "Feature 1", kind: "follow-up", who: "acme/widgets#41", next: "/shirabe:execute docs/plans/PLAN-loader.md", wakes: "0", updated: "2026-09-26T07:00Z"}]')
for v in v2 v3; do
    seed "$(printf '%s' "$REC" | jq -c --argjson r "$RS4" --argjson w "$ROWS" '.side_effects = [$r] | .work = $w')"; pr 21 OPEN true; pr 23 OPEN false
    db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(rmv roadmap/$v Done 'In progress' 'Not started' 'Not started' 'In progress')"
    session "$(roadmap_vars plugin-system)" roadmap-plugin-system
    OUT=$(bash "$PF" --session "$S" 2>"$T/err"); eq "$v: the facts are read" "0 pick" "$? ${OUT% sealed:*}"
    facts > "$T/parity-$v.json"
done
eq "v3 units are the Milestone N headings, in order" "Milestone 1,Milestone 2,Milestone 3,Milestone 4,Milestone 5" "$(jq -r '[.units[].unit] | join(",")' "$T/parity-v3.json")"
eq "v2 and v3 give the same facts, a unit read Milestone N for Feature N" \
    "$(jq -c '.units' "$T/parity-v2.json")" "$(jq -c '.units | map(.unit |= sub("^Milestone "; "Feature "))' "$T/parity-v3.json")"
eq "  ... and the same holdings, counts and decisions" "$(jq -c 'del(.units)' "$T/parity-v2.json")" "$(jq -c 'del(.units)' "$T/parity-v3.json")"
eq "v3: Feature 1 in prose blocks Milestone 2 on Milestone 1; Features 1 and 2 block Milestone 3 on Milestone 2" "false [] true|true [2] false" \
    "$(jq -r '[.units[1], .units[2]] | map("\(.blocked) \(.blocked_by | tojson) \(.blocker_landed)") | join("|")' "$T/parity-v3.json")"
eq "v3: holdings naming Feature 2, Feature 4 and Feature 3: Sandbox cover Milestones 2, 4 and 3" "alpha beta gamma" \
    "$(jq -r '[.units[1].holding.worker, .units[3].holding.worker, .units[2].holding.worker] | join(" ")' "$T/parity-v3.json")"
eq "v3: the landed row for Feature 4 marks Milestone 4 landed" "[#30](https://github.com/acme/widgets/pull/30)" "$(jq -r '.units[3].landed' "$T/parity-v3.json")"
eq "v3: the verdict-owed row for Feature 5 and the follow-up row for Feature 1 mark Milestones 5 and 1" "true acme/widgets#41" \
    "$(jq -r '"\(.units[4].verdict_owed) \(.units[0].follow_up.after)"' "$T/parity-v3.json")"
# covered_in <schema> <unit-cell>: the unit pick reads one holding as covering, or none.
covered_in() {
    seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding solo "$(jq -nc --arg u "$2" '{unit: $u, pull_request: ""}')")" '.holdings = [$h]')"
    db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(rmv "$1" Done 'In progress' 'Not started' 'Not started' Dropped)"
    session "$(roadmap_vars plugin-system)" roadmap-plugin-system
    bash "$PF" --session "$S" > /dev/null 2>&1
    facts | jq -r '[.units[] | select(.holding.worker == "solo") | .unit][0] // "none"'
}
eq "v2: a holding naming Milestone 2 covers Feature 2" "Feature 2" "$(covered_in roadmap/v2 "Milestone 2")"
eq "v2: one naming Milestone 3: Sandbox covers Feature 3" "Feature 3" "$(covered_in roadmap/v2 "Milestone 3: Sandbox")"
eq "v3: one naming Feature 3: Registry, another title, covers nothing" none "$(covered_in roadmap/v3 "Feature 3: Registry")"
eq "v3: one naming Feature 03 covers nothing" none "$(covered_in roadmap/v3 "Feature 03")"
eq "v3: one naming feature 2 covers nothing" none "$(covered_in roadmap/v3 "feature 2")"
eq "v3: one naming #2, an issue, covers nothing" none "$(covered_in roadmap/v3 "#2")"
# paused_in <schema> <standing-rows-json>: the facts with those Standing rows
# over the fixture's holdings, on a roadmap of that schema.
paused_in() {
    seed "$(printf '%s' "$REC" | jq -c --argjson s "$2" '.standing = $s')"; pr 21 OPEN true; pr 23 OPEN false
    db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(rmv "$1" Done 'In progress' 'Not started' 'Not started' 'Not started')"
    session "$(roadmap_vars plugin-system)" roadmap-plugin-system
    bash "$PF" --session "$S" > /dev/null 2>&1
}
paused_in roadmap/v3 "[$(pause_row s1 pause "Feature 3" lifted)]"
eq "v3: a pause written on Feature 3 holds Milestone 3, and not Milestones 2 or 4" "s1 null null" \
    "$(facts | jq -r '. as $f | ["Milestone 3", "Milestone 2", "Milestone 4"] | map(. as $u | $f.units[] | select(.unit == $u) | .paused | tostring) | join(" ")')"
eq "  ... nor the holdings under Feature 2 and Feature 4" "null null" \
    "$(facts | jq -r '[.holdings[] | select(.worker == "alpha" or .worker == "beta") | .paused] | map(tostring) | join(" ")')"
paused_in roadmap/v3 "[$(pause_row s1 pause all "time 2099-01-01T00:00Z"), $(pause_row s2 go-ahead "Feature 4" "")]"
eq "v3: a go-ahead written on Feature 4 lets Milestone 4 through an all pause; Milestone 3 stays held" "null s1" \
    "$(facts | jq -r '[(.units[] | select(.unit == "Milestone 4") | .paused), (.units[] | select(.unit == "Milestone 3") | .paused)] | map(tostring) | join(" ")')"
paused_in roadmap/v2 "[$(pause_row s1 pause "Milestone 2" lifted)]"
eq "v2: a pause on Milestone 2 holds Feature 2 and the holding under it" "s1 s1" \
    "$(facts | jq -r '[(.units[] | select(.unit == "Feature 2") | .paused), (.holdings[] | select(.worker == "alpha") | .paused)] | map(tostring) | join(" ")')"

echo "== the dispatch path's unit forms are the ones pick reads =="
# dispatch-common.sh dc_unit_forms lists, from coord/pick.json, the Unit cells
# the dispatch path accepts for a brief. Each must be one this script reads as
# covering its unit, or the two rules have drifted and a holding can go
# invisible to pick (#493). The converse isn't required: this script also
# reads a unit's Feature/Milestone twin (above), which dispatch never offers
# for a new holding.
. "$HERE/dispatch-common.sh"
covered_by() { # covered_by <scope> <unit-cell>: the unit pick reads the one holding as covering, or none
    if [ "$1" = roadmap ]; then
        seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding solo "$(jq -nc --arg u "$2" '{unit: $u, pull_request: ""}')")" '.holdings = [$h]')"
        db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' Dropped)"
        session "$(roadmap_vars plugin-system)" roadmap-plugin-system
        bash "$PF" --session "$S" > /dev/null 2>&1
    else
        dseed
        SEED=$(record_json discipline ci-health | jq -c --argjson h "$(holding solo "$(jq -nc --arg u "$2" '{unit: $u, pull_request: ""}')")" '.holdings = [$h]')
        session "$(discipline_vars ci-health)" discipline-ci-health
        bash "$PF" --session "$S" --today 2026-09-29 > /dev/null 2>&1
    fi
    facts | jq -r '[.units[] | select(.holding.worker == "solo") | .unit][0] // "none"'
}
for scope in roadmap discipline; do
    covered_by "$scope" "nothing" > /dev/null
    facts > "$T/forms-pick.json"
    [ "$scope" = discipline ] && eq "discipline: pick.json records the host" acme/widgets "$(jq -r '.host' "$T/forms-pick.json")"
    dc_unit_forms "$T/forms-pick.json" > "$T/forms"
    [ -s "$T/forms" ] && ok "$scope: the dispatch path lists forms" || bad "$scope: the dispatch path lists forms"
    while IFS= read -r form; do
        got=$(covered_by "$scope" "$form")
        [ "$got" != none ] && ok "$scope: pick reads [$form] as covering $got" || bad "$scope: pick reads [$form] as covering a unit"
    done < "$T/forms"
done
eq "roadmap: the old template example covers nothing" none "$(covered_by roadmap "Feature 2 of ROADMAP-plugin-system")"
eq "discipline: another repository's #n covers nothing" none "$(covered_by discipline "acme/gadgets#5")"

echo "== the decider's slice, coord/pick_slice.json (shirabe#1076) =="
slice() { cat "$KOTO_STORE/context/$S/coord/pick_slice.json"; }
# big_roadmap <done>: <done> Done features, then Feature <done+1> Not started,
# Feature <done+2> In progress waiting on it, and Feature <done+3> Not started
# waiting on Feature <done>.
big_roadmap() {
    local i
    printf -- '---\nstatus: Active\n---\n\n# ROADMAP\n\n## Features\n\n'
    for ((i = 1; i <= $1; i++)); do
        printf '### Feature %d: Finished piece %d of the plugin system\n**Dependencies:** None\n**Status:** Done\n\n' "$i" "$i"
    done
    printf '### Feature %d: Open\n**Dependencies:** None\n**Status:** Not started\n\n' $(($1 + 1))
    printf '### Feature %d: Waiting\n**Dependencies:** Feature %d\n**Status:** In progress\n\n' $(($1 + 2)) $(($1 + 1))
    printf '### Feature %d: Landed blocker\n**Dependencies:** Feature %d\n**Status:** Not started\n\n' $(($1 + 3)) "$1"
    printf '## Sequencing Rationale\n\nNone.\n'
}
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding w202 '{"unit": "Feature 202", "pull_request": ""}')" '.holdings = [$h]')"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(big_roadmap 200)"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
OUT=$(bash "$PF" --session "$S" 2>"$T/err")
eq "200 Done units and 3 open: pick" pick "${OUT% sealed:*}"
FULL=$(facts | wc -c | tr -d ' ') SLICE=$(slice | wc -c | tr -d ' ')
[ "$FULL" -gt 12000 ] && ok "  ... the full facts are over the decider's 12,000-byte cap ($FULL)" || bad "  ... the full facts are over the decider's 12,000-byte cap" "$FULL"
[ "$SLICE" -lt 12000 ] && ok "  ... the slice is under it ($SLICE)" || bad "  ... the slice is under it" "$SLICE"
eq "  ... the done list is the 200 Done units, in order" "200 Feature 1 Feature 200" "$(slice | jq -r '"\(.done | length) \(.done[0]) \(.done[-1])"')"
eq "  ... the 3 open units keep their rows" "Feature 201,Feature 202,Feature 203" "$(slice | jq -r '[.units[].unit] | join(",")')"
eq "  ... a blocker is named by its tag, not its position" '["Feature 201"]' "$(slice | jq -c '.units[] | select(.unit == "Feature 202") | .blocked_by')"
eq "  ... null, false and empty-list fields are left out of units" 'number,status,title,unit|blocker_landed,number,status,title,unit' \
    "$(slice | jq -r '[.units[] | select(.unit == "Feature 203" or .unit == "Feature 201") | keys | join(",")] | join("|")')"
eq "  ... and out of holdings" 'dispatch_status,phase,pull_request,unit,worker' "$(slice | jq -r '.holdings[0] | keys | join(",")')"
eq "  ... the counts, bounds, pauses and decisions are the facts'" "$(facts | jq -c '[.scope, .name, .host, .cap, .active, .parked, .parked_bound, .paused_all, .pauses, .go_aheads, .decisions]')" \
    "$(slice | jq -c '[.scope, .name, .host, .cap, .active, .parked, .parked_bound, .paused_all, .pauses, .go_aheads, .decisions]')"
# A key added to the facts fails here until pick-slice.jq says whether the
# decider sees it.
eq "  ... the slice has every key of the facts, and done" \
    "active,cap,decisions,go_aheads,holdings,host,name,parked,parked_bound,paused_all,pauses,scope,units|active,cap,decisions,done,go_aheads,holdings,host,name,parked,parked_bound,paused_all,pauses,scope,units" \
    "$(facts | jq -r 'keys | join(",")')|$(slice | jq -r 'keys | join(",")')"
eq "  ... the slice is pick-slice.jq's of the facts this visit wrote" "$(facts | jq -c -L "$HERE" 'include "pick-slice"; pick_slice')" "$(slice)"

# A done unit keeps its row while a verdict is owed on it, a rework row names
# it, or a holding covers it; one with none of them is collapsed.
KEEP=$(jq -nc '[{item: "Feature 2", kind: "verdict-owed", who: "none", next: "verdict owed since 2026-09-26", wakes: "0", updated: "2026-09-26T07:00Z"},
    {item: "Feature 3", kind: "rework", who: "verdict 1001", next: "Changes needed: name the skipped plugin", wakes: "0", updated: "2026-09-26T07:00Z"}]')
seed "$(record_json roadmap plugin-system | jq -c --argjson w "$KEEP" --argjson h "$(holding delta '{"unit": "Feature 4", "pull_request": ""}')" '.work = $w | .holdings = [$h]')"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done Done Done Dropped)"
session "$(roadmap_vars plugin-system)" roadmap-plugin-system
bash "$PF" --session "$S" >/dev/null 2>"$T/err"; eq "the facts are read with done units owed a verdict, reworked and held" 0 $?
eq "  ... only the done units with none of them are collapsed" "Feature 1,Feature 5" "$(slice | jq -r '.done | join(",")')"
eq "  ... a done unit owed a verdict keeps its row" "true true" "$(slice | jq -r '.units[] | select(.unit == "Feature 2") | "\(.done) \(.verdict_owed)"')"
eq "  ... a done unit with rework keeps its row" "true Changes needed: name the skipped plugin" "$(slice | jq -r '.units[] | select(.unit == "Feature 3") | "\(.done) \(.rework)"')"
eq "  ... a done unit a holding covers keeps its row" 'true {"worker":"delta","phase":"executing"}' "$(slice | jq -c -r '.units[] | select(.unit == "Feature 4") | "\(.done) \(.holding | tojson)"')"
# The slice is rewritten on every visit, from that visit's facts.
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done Done Done 'Not started')"
log_to "$S" pick_facts pick; log_to "$S" pick pick_facts
bash "$PF" --session "$S" >/dev/null 2>"$T/err"; eq "a second visit is read" 0 $?
eq "  ... and its slice is that visit's" "Feature 1" "$(slice | jq -r '.done | join(",")')"
eq "  ... with the facts beside it" "Feature 5 false" "$(facts | jq -r '.units[4] | "\(.unit) \(.done)"')"

# The decider's fixtures are slices: each pick_facts input is what
# pick-slice.jq prints for it, and some carry a long done list.
FX="$HERE/../koto-templates/coordinate.pick.choice.decider.jsonl"
eq "every pick fixture's input is a slice" 0 \
    "$(jq -L "$HERE" 'include "pick-slice"; .inputs.pick_facts | fromjson | select(pick_slice != .) | 1' "$FX" | wc -l | tr -d ' ')"
eq "no pick fixture keeps a Done row pick-facts.sh would have collapsed" 0 \
    "$(jq -r '.inputs.pick_facts | fromjson | .units[] | select(.status == "Done" and .done != true and .holding == null) | .unit' "$FX" | wc -l | tr -d ' ')"
eq "every blocker a pick fixture names is a unit it lists or a done one" 0 \
    "$(jq -r '.inputs.pick_facts | fromjson | ([.units[].unit] + .done) as $k | .units[] | select((.blocked_by | type) == "array") | .blocked_by[] | select(IN($k[]) | not)' "$FX" | wc -l | tr -d ' ')"
eq "fixtures cover a slice with a long done list, for every value but scope and await_decision" "ask_up,dispatch,hold,scope_ahead,send_execution" \
    "$(jq -rs '[.[] | select((.inputs.pick_facts | fromjson | .done | length) >= 150) | .expected] | sort | join(",")' "$FX")"

done_tests pick-facts
