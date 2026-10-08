#!/usr/bin/env bash
# pick-facts_test.sh -- pick-facts.sh, the facts pick decides on.
#
# Covers: `pick` with coord/pick.json for two executing holdings, one parked
# worker and one local agent (which has no holding) reading active 2 and
# parked 1; each unit's blocked, blocked_by and blocker_landed flags as the
# fixture roadmap's Dependencies and Status lines say, in the roadmap's
# order, with the holding that covers it; the prefix heading form; the
# roadmap read from the host's default branch; `scope-complete` when every
# feature reads Done or Dropped, and not for a roadmap with no features; a
# missing roadmap (2); discipline units from the host's open issues with the
# discipline's label in issue-number order (never a search); `rotation-over`
# only after the title's end date; CAP and PARKED_BOUND from the session; the
# sealed token; every token in koto's capture alphabet; pick.json's host; every
# Unit cell form dispatch-common.sh dc_unit_forms lists from pick.json is one
# this script reads as covering its unit, and the old template's form isn't;
# units a person assigned (Standing assignment rows: issues read in their own
# repositories, a closed one done, a release open until its row ends) listed
# after the roadmap's, covered by a holding, their forms the dispatch path
# takes, and an open one keeping the roadmap from completing.
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
ITITLE="Coordinator record: ROADMAP-plugin-system"
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
seed() { # seed <record-json>
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' \
        --arg t "$ITITLE" --arg b "$(render "$1" issue)"
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
session() { # session <vars-json> <ref>: a run at pick_facts
    N=$((N + 1))
    S="coordinate-$3-20260926T08$(printf %02d "$N")00Z"
    found_session "$S" "$1" "$2"
    log_to "$S" reconcile pick_facts
}
facts() { cat "$KOTO_STORE/context/$S/coord/pick.json"; }

echo "== roadmap: pick =="
seed "$REC"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' Dropped)"
# The local agent is a subagent in the coordinator's own session: it never has
# a Holdings row, so the fixture's local agent is visible only as its absence.
session "$(roadmap_vars plugin-system)" 7 roadmap-plugin-system
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
eq "Feature 5 depends on a feature not Done: blocked" "true [4]" "$(facts | jq -c -r '.units[4] | "\(.blocked) \(.blocked_by | tojson)"')"
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
session "$(roadmap_vars plugin-system)" 7 roadmap-plugin-system
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
    session "$(roadmap_vars plugin-system)" 7 roadmap-plugin-system
    OUT=$(bash "$PF" --session "$S" 2>"$T/err")
    eq "$label" "$want" "${OUT% sealed:*}"
}
RMTEXT=$(roadmap Done 'In progress' 'Not started' 'Not started' Dropped)
# An unrecorded write: a visit to decision_raise that left no entry stamped for it.
seed "$REC"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$RMTEXT"
session "$(roadmap_vars plugin-system)" 7 roadmap-plugin-system
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
session "$(roadmap_vars plugin-system)" 7 roadmap-plugin-system
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
grep -q "issue view 591 --repo acme/widgets" "$GH_DB.calls" && grep -q "issue view 592 --repo acme/widgets" "$GH_DB.calls" \
    && ok "each assigned issue is read in its own repository" || bad "each assigned issue is read in its own repository" "$(calls)"
seed "$(record_json roadmap plugin-system | jq -c --argjson s "$(printf '%s' "$STAND" | jq -c '[.[1]]')" '.standing = $s')"
db '.issues += [{repo: "acme/widgets", number: 592, title: "a second fix", body: "", state: "closed", author: "alice", editor: null}]'
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done Done Done Dropped)"
session "$(roadmap_vars plugin-system)" 7 roadmap-plugin-system
OUT=$(bash "$PF" --session "$S" 2>"$T/err")
eq "with every assigned unit done, the roadmap completes" scope-complete "${OUT% sealed:*}"

echo "== roadmap: a landed unit, its roadmap pull request pending =="
RS='{"action":"roadmap-status","target":"Feature 4 [#30](https://github.com/acme/widgets/pull/30)","verified_head":"","attempted":"2026-09-26T09:00Z","how_to_confirm":"the roadmap on main reads Feature 4 Done"}'
seed "$(printf '%s' "$REC" | jq -c --argjson r "$RS" '.side_effects = [$r]')"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' 'Not started')"
session "$(roadmap_vars plugin-system)" 7 roadmap-plugin-system
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

echo "== roadmap: pauses =="
pause_row() { # pause_row <id> <kind> <on> <until>
    jq -nc --arg s "$1" --arg k "$2" --arg o "$3" --arg u "$4" \
        '{standing: $s, kind: $k, on: $o, until: $u, what: "x", owner: "the human", relayed_by: "", set: "2026-10-01T19:37Z"}'
}
seed "$(printf '%s' "$REC" | jq -c --argjson a "$(pause_row s1 pause "Feature 2" lifted)" '.standing = [$a]')"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' 'Not started')"
session "$(roadmap_vars plugin-system)" 7 roadmap-plugin-system
bash "$PF" --session "$S" >/dev/null 2>"$T/err"; eq "the facts are read with a pause standing" 0 $?
eq "a unit's pause marks that unit and the holding covering it, and nothing else" "s1 s1 null null" \
    "$(facts | jq -r '[(.units[] | select(.unit == "Feature 2") | .paused), (.holdings[] | select(.worker == "alpha") | .paused), (.units[] | select(.unit == "Feature 4") | .paused), (.holdings[] | select(.worker == "beta") | .paused)] | map(tostring) | join(" ")')"
eq "  ... the facts list it in force, and the whole coordinator isn't paused" "s1 in-force null" "$(facts | jq -r '"\(.pauses[0].standing) \(.pauses[0].state) \(.paused_all)"')"
seed "$(printf '%s' "$REC" | jq -c --argjson a "$(pause_row s1 pause all "time 2099-01-01T00:00Z")" --argjson g "$(pause_row s2 go-ahead "Feature 4" "")" '.standing = [$a, $g]')"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' 'Not started')"
session "$(roadmap_vars plugin-system)" 7 roadmap-plugin-system
bash "$PF" --session "$S" >/dev/null 2>"$T/err"
eq "an all pause holds the coordinator and every unit but the one a go-ahead names" "s1 s1 null s2" \
    "$(facts | jq -r '[.paused_all, (.units[] | select(.unit == "Feature 3") | .paused), (.units[] | select(.unit == "Feature 4") | .paused), .go_aheads[0].standing] | map(tostring) | join(" ")')"
seed "$(printf '%s' "$REC" | jq -c --argjson a "$(pause_row s1 pause all "time 2000-01-01T00:00Z")" '.standing = [$a]')"; pr 21 OPEN true; pr 23 OPEN false
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' 'Not started')"
session "$(roadmap_vars plugin-system)" 7 roadmap-plugin-system
bash "$PF" --session "$S" >/dev/null 2>"$T/err"
eq "a pause whose minute has passed is met and holds nothing" "met null null" \
    "$(facts | jq -r '[.pauses[0].state, .paused_all, (.units[] | select(.unit == "Feature 3") | .paused)] | map(tostring) | join(" ")')"

echo "== roadmap: scope-complete =="
RM=(--scope roadmap --name plugin-system --repo "$REPO" --ref 7 --no-seal)
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done. Dropped Done Dropped)"
OUT=$(bash "$PF" "${RM[@]}" 2>"$T/err"); eq "every feature Done or Dropped is scope-complete" scope-complete "$OUT"
tok_shape "scope-complete is in koto's capture alphabet" "$OUT"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done Dropped Done 'Done (mostly)')"
eq "one feature not quite Done is pick" pick "$(bash "$PF" "${RM[@]}" 2>/dev/null)"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(printf '# ROADMAP\n\n## Features\n\nTBD.\n')"
eq "a roadmap with no features is not complete" pick "$(bash "$PF" "${RM[@]}" 2>/dev/null)"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(printf '## Features\n\n### ED1: Loader\n**Status:** Done\n\n### ED2: Registry\n**Dependencies:** F1\n**Status:** Dropped\n')"
eq "the prefix heading form reads the same" scope-complete "$(bash "$PF" "${RM[@]}" 2>/dev/null)"
db '.files["acme/widgets"] |= del(.["main:" + $p])' --arg p "$RP"
bash "$PF" "${RM[@]}" >/dev/null 2>&1; eq "a roadmap missing from the default branch exits 2" 2 $?
db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done Done Done Done Done)"
db '.fail = [{match: "pr view 23", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
bash "$PF" "${RM[@]}" >/dev/null 2>&1; eq "a failed holding read exits 2" 2 $?

echo "== discipline =="
BR=coordinate/discipline-ci-health
dseed() { # dseed <title>
    db_init
    db '.branches["acme/widgets"][$br] = $s | .prs += [{repo: "acme/widgets", number: 22, title: $t, body: $b, state: "OPEN", isDraft: true,
        isCrossRepository: false, baseRefName: "main", headRefName: $br, headRefOid: $s, author: "alice", editor: null}]
        | .issues += [{repo: "acme/widgets", number: 5, title: "flaky lint", body: "", state: "open", labels: ["ci-health"], author: "a"},
                      {repo: "acme/widgets", number: 3, title: "slow cache", body: "", state: "open", labels: ["ci-health", "perf"], author: "a"},
                      {repo: "acme/widgets", number: 9, title: "unrelated", body: "", state: "open", labels: ["docs"], author: "a"},
                      {repo: "acme/widgets", number: 4, title: "done already", body: "", state: "closed", labels: ["ci-health"], author: "a"}]' \
        --arg br "$BR" --arg s "$SHA_HEAD" --arg t "$1" \
        --arg b "$(render "$(record_json discipline ci-health | jq -c --argjson h "$(holding alpha '{"unit": "#5", "pull_request": ""}')" '.holdings = [$h]')" pr)"
}
dseed "docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-29"
session "$(discipline_vars ci-health | jq -c '.CAP = "4" | .PARKED_BOUND = "2"')" 22 discipline-ci-health
OUT=$(bash "$PF" --session "$S" --today 2026-09-29 2>"$T/err")
eq "on the title's end date the rotation goes on" pick "${OUT% sealed:*}"
eq "units are the open labelled issues in number order" "#3 #5" "$(facts | jq -r '[.units[].unit] | join(" ")')"
eq "the issue a holding covers carries it" "null alpha" "$(facts | jq -r '[.units[] | .holding.worker // "null"] | join(" ")')"
eq "the session's CAP and PARKED_BOUND" "4 2" "$(facts | jq -r '"\(.cap) \(.parked_bound)"')"
grep -q '^issue list --repo acme/widgets --state open --label ci-health --json number,title --limit 200$' "$GH_DB.calls" \
    && ok "issues are listed by label, never searched" || bad "issues are listed by label, never searched" "$(calls)"
OUT=$(bash "$PF" --scope discipline --name ci-health --repo "$REPO" --ref 22 --today 2026-09-30 --no-seal 2>"$T/err")
eq "after the title's end date it is rotation-over" rotation-over "$OUT"
tok_shape "rotation-over is in koto's capture alphabet" "$OUT"
dseed "docs(coordinate): ci-health rotation 2026-09-22 to soon"
bash "$PF" --scope discipline --name ci-health --repo "$REPO" --ref 22 --no-seal >/dev/null 2>&1; eq "a record title that isn't a rotation title exits 2" 2 $?
# A carry: the previous rotation's handoff holds an unsettled entry this
# record doesn't carry yet, before the run's first dispatch.
dseed "docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-29"
record_json discipline ci-health | jq -c --argjson e "[$(dentry 5 escalated "$ESC")]" '. + {decisions: {next: 9, entries: $e},
    rotation: {start: "2026-09-15", end: "2026-09-22", date: "2026-09-22", host_repo: "acme/widgets", record_url: "https://github.com/acme/widgets/pull/20"},
    reasoning: "Lint is flaky."}' | bash "$HERE/record-render.sh" --format handoff > "$T/prev.md"
db '.files["acme/widgets"]["main:docs/disciplines/ci-health.md"] = $t' --arg t "$(cat "$T/prev.md")"
session "$(discipline_vars ci-health)" 22 discipline-ci-health
OUT=$(bash "$PF" --session "$S" --today 2026-09-29 2>"$T/err")
eq "a carry owed is decisions" "decisions carry" "${OUT% sealed:*}"

echo "== the dispatch path's unit forms are the ones pick reads =="
# dispatch-common.sh dc_unit_forms lists, from coord/pick.json, the Unit cells
# the dispatch path accepts for a brief. Each must be one this script reads as
# covering its unit, and a form it doesn't list must not be, or the two rules
# have drifted and a holding can go invisible to pick (#493).
. "$HERE/dispatch-common.sh"
covered_by() { # covered_by <scope> <unit-cell>: the unit pick reads the one holding as covering, or none
    if [ "$1" = roadmap ]; then
        seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding solo "$(jq -nc --arg u "$2" '{unit: $u, pull_request: ""}')")" '.holdings = [$h]')"
        db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --arg t "$(roadmap Done 'In progress' 'Not started' 'Not started' Dropped)"
        session "$(roadmap_vars plugin-system)" 7 roadmap-plugin-system
        bash "$PF" --session "$S" > /dev/null 2>&1
    else
        dseed "docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-29"
        db '.prs[0].body = $b' --arg b "$(render "$(record_json discipline ci-health | jq -c --argjson h "$(holding solo "$(jq -nc --arg u "$2" '{unit: $u, pull_request: ""}')")" '.holdings = [$h]')" pr)"
        session "$(discipline_vars ci-health)" 22 discipline-ci-health
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

done_tests pick-facts
