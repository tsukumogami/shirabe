#!/usr/bin/env bash
# report-facts_test.sh -- report-facts.sh finds the reporting worker's
# holding by topic and checks its pull request before anything verifies it.
#
# Covers: a holding found by the `wait` evidence's unit (only a `report`
# event counts) and coord/report.json with the pull request's state, draft,
# head and merge state and the holding, and no worker text; a pull request in
# another holding's repository accepted; refusals for a repository outside the
# host and the holdings, a fork head, a head branch that differs from the
# Branch cell, and a link whose two numbers differ; the comparison skipped
# while Branch is empty; `holding none` when Branch and Pull request are both
# empty; `unknown` for a topic with no row and `unknown -` for evidence naming
# no dispatch topic; a failed read (2); the sealed token; every token in
# koto's capture alphabet.
#
# Usage: bash skills/coordinate/scripts/report-facts_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RF="$HERE/report-facts.sh"
CL="$HERE/coord-log.sh"
tok_shape() {
    local re='^[A-Za-z0-9 :/_.@-]*$'
    if [[ ${2% sealed:*} =~ $re ]]; then ok "$1"; else bad "$1" "[$2]"; fi
}
ITITLE="Coordinator record: ROADMAP-plugin-system"
h() { # h <worker> <repo> <branch> <pull_request cell>
    holding "$1" "$(jq -nc --arg r "$2" --arg b "$3" --arg p "$4" '{repo: $r, branch: $b, pull_request: $p}')"
}
HOLDINGS=$(jq -nc \
    --argjson a "$(h alpha acme/widgets feat/alpha '[#12](https://github.com/acme/widgets/pull/12)')" \
    --argjson b "$(h beta acme/gadgets feat/beta '[#5](https://github.com/acme/gadgets/pull/5)')" \
    --argjson c "$(h gamma acme/widgets feat/gamma '[#3](https://github.com/acme/other/pull/3)')" \
    --argjson d "$(h delta acme/widgets feat/delta '[#14](https://github.com/acme/widgets/pull/14)')" \
    --argjson e "$(h eps acme/widgets feat/eps '[#15](https://github.com/acme/widgets/pull/15)')" \
    --argjson f "$(h zeta acme/widgets '' '')" \
    --argjson g "$(h eta acme/widgets '' '[#16](https://github.com/acme/widgets/pull/16)')" \
    --argjson i "$(h iota acme/widgets feat/iota '[#12](https://github.com/acme/widgets/pull/17)')" \
    --argjson j "$(h theta acme/widgets feat/theta '[#18](https://github.com/acme/widgets/pull/18)' | jq -c '.return_path = "leg req-1:execute"')" \
    '[$a, $b, $c, $d, $e, $f, $g, $i, $j]')
pr() { # pr <repo> <n> <headRefName> [cross]
    db '.prs += [{repo: $r, number: $n, title: "w", body: "", state: "OPEN", isDraft: false, isCrossRepository: ($x == "true"),
        baseRefName: "main", headRefName: $b, headRefOid: $h, author: "alice", editor: null, mergeStateStatus: "CLEAN"}]' \
        --arg r "$1" --argjson n "$2" --arg b "$3" --arg x "${4:-false}" --arg h "$SHA_HEAD"
}
seed() {
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' \
        --arg t "$ITITLE" --arg b "$(render "$(record_json roadmap plugin-system | jq -c --argjson h "$HOLDINGS" '.holdings = $h')" issue)"
    pr acme/widgets 12 feat/alpha; pr acme/gadgets 5 feat/beta; pr acme/widgets 14 feat/delta true
    pr acme/widgets 15 feat/other; pr acme/widgets 16 anything; pr acme/widgets 17 feat/iota; pr acme/widgets 18 feat/theta
    db '.repos["acme/other"] = {private: false, default_branch: "main"}'; pr acme/other 3 feat/gamma
}
S=coordinate-roadmap-plugin-system-20260926T080000Z
seed
found_session "$S" "$(roadmap_vars plugin-system)" 7
log_to "$S" reconcile wait
report() { # report <fields-json>: the coordinator ticks wait with a report
    log_evidence "$S" wait "$1"
    log_to "$S" wait report_facts
    OUT=$(bash "$RF" --session "$S" 2>"$T/err")
    RC=$?
    log_to "$S" report_facts wait
}
facts() { cat "$KOTO_STORE/context/$S/coord/report.json"; }

echo "== found =="
report '{"event":"report","unit":"alpha"}'
eq "the reporting worker's holding is found by topic" "holding 12 alpha" "${OUT% sealed:*}"
tok_shape "holding is in koto's capture alphabet" "$OUT"
log_to "$S" wait report_facts
bash "$CL" check --session "$S" --state report_facts --sealed "$OUT" --any-visit && ok "the token is sealed to report_facts" || bad "the token is sealed to report_facts"
log_to "$S" report_facts wait
eq "report.json carries the pull request's facts" '{"unit":"alpha","pull_request":{"repo":"acme/widgets","number":12,"url":"https://github.com/acme/widgets/pull/12"},"state":"OPEN","draft":false,"head":"2222222222222222222222222222222222222222","merge_state":"CLEAN"}' \
    "$(facts | jq -c 'del(.holding)')"
eq "and the holding" "alpha feat/alpha" "$(facts | jq -r '"\(.holding.worker) \(.holding.branch)"')"
eq "and no worker text" '["draft","head","holding","merge_state","pull_request","state","unit"]' "$(facts | jq -c 'keys')"
report '{"event":"report","unit":"beta"}'
eq "a pull request in another holding's repository is in scope" "holding 5 beta" "${OUT% sealed:*}"
report '{"event":"report","unit":"eta"}'
eq "with Branch empty the head branch isn't compared" "holding 16 eta" "${OUT% sealed:*}"
report '{"event":"report","unit":"zeta"}'
eq "with Branch and Pull request empty there is nothing to read" "holding none zeta" "${OUT% sealed:*}"
eq "report.json says so" "null zeta" "$(facts | jq -r '"\(.pull_request) \(.holding.worker)"')"

echo "== refused =="
report '{"event":"report","unit":"gamma"}'
eq "a repository outside the host and the holdings is refused" "refused gamma out-of-scope-repo" "${OUT% sealed:*}"
tok_shape "refused is in koto's capture alphabet" "$OUT"
grep -q 'pr view 3 --repo acme/other' "$GH_DB.calls" && bad "an out-of-scope pull request is never read" || ok "an out-of-scope pull request is never read"
report '{"event":"report","unit":"delta"}'
eq "a fork head is refused" "refused delta fork-head" "${OUT% sealed:*}"
report '{"event":"report","unit":"eps"}'
eq "a head branch other than the Branch cell is refused" "refused eps branch-mismatch" "${OUT% sealed:*}"
report '{"event":"report","unit":"iota"}'
eq "a link whose numbers differ is refused" "refused iota bad-link" "${OUT% sealed:*}"

echo "== the leg path =="
leg_report() { # leg_report <request-id> <leg>: a report arriving on a koto request leg
    log_evidence "$S" wait '{"event":"leg"}'
    log_to "$S" wait leg_pick
    log_capture "$S" WAIT_REQ "$1"
    log_to "$S" leg_pick wait_leg
    log_capture "$S" WAIT_LEG "$2"
    log_to "$S" wait_leg take_report
    log_to "$S" take_report report_facts
    OUT=$(bash "$RF" --session "$S" 2>"$T/err")
    RC=$?
    log_to "$S" report_facts wait
}
report '{"event":"report","unit":"alpha"}'
leg_report req-1 execute
eq "a leg report finds the holding whose Return path is that leg, not the last message's unit" "holding 18 theta" "${OUT% sealed:*}"
leg_report req-9 execute
eq "a leg no holding carries is unknown" "unknown -" "${OUT% sealed:*}"
report '{"event":"report","unit":"alpha"}'
eq "after a leg report, a message report reads the hub's unit again" "holding 12 alpha" "${OUT% sealed:*}"

echo "== unknown =="
report '{"event":"report","unit":"nobody"}'
eq "a topic with no holding is unknown" "unknown nobody" "${OUT% sealed:*}"
tok_shape "unknown is in koto's capture alphabet" "$OUT"
report '{"event":"report"}'
eq "a report naming no unit is unknown -" "unknown -" "${OUT% sealed:*}"
report '{"event":"report","unit":"a/b; rm -rf"}'
eq "a unit outside the topic grammar never reaches the token" "unknown -" "${OUT% sealed:*}"
log_evidence "$S" wait '{"event":"report","unit":"alpha"}'
log_to "$S" wait quiet_check; log_to "$S" quiet_check wait
report '{"event":"quiet","unit":"beta"}'
eq "only a report event names the reporting unit" "holding 12 alpha" "${OUT% sealed:*}"

echo "== failures =="
db '.fail = [{match: "pr view 12", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
report '{"event":"report","unit":"alpha"}'
eq "a failed pull request read exits 2" 2 "$RC"
db '.fail = [{match: "issue view 7", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
report '{"event":"report","unit":"alpha"}'
eq "a failed record read exits 2" 2 "$RC"
db '.fail = []'
bash "$RF" --scope roadmap --name plugin-system --repo "$REPO" --ref 7 --no-seal >/dev/null 2>&1; eq "no session is a usage error" 64 $?
OUT=$(bash "$RF" --session "$S" --scope roadmap --name plugin-system --repo "$REPO" --ref 7 --no-seal 2>/dev/null)
eq "the override flags read the same record" "holding 12 alpha" "$OUT"

done_tests report-facts
