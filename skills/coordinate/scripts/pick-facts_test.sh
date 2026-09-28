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
# sealed token; every token in koto's capture alphabet.
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
grep -q "contents/$RP?ref=main" "$GH_DB.calls" && ok "the roadmap is read from the default branch" || bad "the roadmap is read from the default branch" "$(calls)"
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

done_tests pick-facts
