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
# empty and the report names no pull request; `link` when it names one, by
# the message's `pull_request` (URL or o/r#n) or the promoted leg result's
# `pr` read from koto, never worker_report, refused as bad-report-pr in any
# other form, pr-held when another row links it, and by the scope, fork and
# Branch rules; `unknown` for a topic with no row and `unknown -` for evidence naming
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
    --argjson k "$(h kappa acme/widgets '' '' | jq -c '.return_path = "leg req-2:deliver"')" \
    --argjson l "$(h lambda acme/widgets feat/lambda '')" \
    '[$a, $b, $c, $d, $e, $f, $g, $i, $j, $k, $l]')
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
    pr acme/widgets 20 feat/zeta; pr acme/widgets 21 feat/kappa; pr acme/widgets 22 feat/forked true
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
eq "report.json carries the pull request's facts" '{"unit":"alpha","pull_request":{"repo":"acme/widgets","number":12,"url":"https://github.com/acme/widgets/pull/12"},"state":"OPEN","draft":false,"head":"2222222222222222222222222222222222222222","merge_state":"CLEAN","progress":false,"refused":null}' \
    "$(facts | jq -c 'del(.holding)')"
eq "and the holding" "alpha feat/alpha" "$(facts | jq -r '"\(.holding.worker) \(.holding.branch)"')"
eq "and no worker text" '["draft","head","holding","merge_state","progress","pull_request","refused","state","unit"]' "$(facts | jq -c 'keys')"
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

echo "== a report naming the pull request its holding lacks =="
report '{"event":"report","unit":"zeta","pull_request":"https://github.com/acme/widgets/pull/20"}'
eq "a message naming a pull request by URL, for a holding with none: link" "link 20 zeta" "${OUT% sealed:*}"
tok_shape "link is in koto's capture alphabet" "$OUT"
eq "report.json carries the named pull request" "20 acme/widgets OPEN" "$(facts | jq -r '"\(.pull_request.number) \(.pull_request.repo) \(.state)"')"
report '{"event":"report","unit":"zeta","pull_request":" acme/widgets#20 "}'
eq "owner/repo#number names it too, blanks aside" "link 20 zeta" "${OUT% sealed:*}"
report '{"event":"report","unit":"zeta","pull_request":"https://github.com/acme/widgets/pull/20/"}'
eq "a trailing slash on the URL is allowed" "link 20 zeta" "${OUT% sealed:*}"
report '{"event":"report","unit":"zeta","pull_request":"PR #20"}'
eq "a pull request named in no form that says its repository is refused" "refused zeta bad-report-pr" "${OUT% sealed:*}"
report '{"event":"report","unit":"zeta","pull_request":"acme/widgets#20 acme/widgets#21"}'
eq "two pull requests are refused" "refused zeta bad-report-pr" "${OUT% sealed:*}"
report '{"event":"report","unit":"zeta","pull_request":"acme/widgets#12"}'
eq "a pull request another holding links is refused, not adopted" "refused zeta pr-held" "${OUT% sealed:*}"
report '{"event":"report","unit":"zeta","pull_request":"acme/other#3"}'
eq "a pull request outside the scope's repositories is refused" "refused zeta out-of-scope-repo" "${OUT% sealed:*}"
report '{"event":"report","unit":"zeta","pull_request":"acme/widgets#22"}'
eq "a pull request from a fork is refused" "refused zeta fork-head" "${OUT% sealed:*}"
report '{"event":"report","unit":"lambda","pull_request":"acme/widgets#20"}'
eq "a head branch other than a Branch cell already set is refused" "refused lambda branch-mismatch" "${OUT% sealed:*}"
report '{"event":"report","unit":"alpha","pull_request":"acme/widgets#20"}'
eq "a holding that links a pull request keeps it; the report's is not read" "holding 12 alpha" "${OUT% sealed:*}"
report '{"event":"report","unit":"zeta","pull_request":""}'
eq "an empty pull_request names none" "holding none zeta" "${OUT% sealed:*}"
mkdir -p "$KOTO_STORE/requests"
leg_result() { # leg_result <pr-json>: req-2's deliver leg, resolved with a promoted result
    jq -nc --argjson p "$1" '{request: {legs: {deliver: {disposition: "resolved", result_source: "promoted",
        result_final_state: "done", result: {status: "ok", payload: {outcome: "ready", pr: $p}}}}}}' > "$KOTO_STORE/requests/req-2.json"
}
leg_result '"https://github.com/acme/widgets/pull/21"'
printf 'leg result: pull request https://github.com/acme/widgets/pull/20' > "$KOTO_STORE/context/$S/worker_report"
leg_report req-2 deliver
eq "a leg result's pr, read from koto's record of the leg, for a holding with none: link" "link 21 kappa" "${OUT% sealed:*}"
leg_result '""'
leg_report req-2 deliver
eq "a leg result with no pr names none" "holding none kappa" "${OUT% sealed:*}"
leg_result '21'
leg_report req-2 deliver
eq "a leg result whose pr is not a string is refused, not read as none" "refused kappa bad-report-pr" "${OUT% sealed:*}"
jq -nc '{request: {legs: {deliver: {disposition: "resolved", result_source: "explicit", result: {payload: {pr: "acme/widgets#21"}}}}}}' \
    > "$KOTO_STORE/requests/req-2.json"
leg_report req-2 deliver
eq "a result the worker's session didn't promote names none" "holding none kappa" "${OUT% sealed:*}"
rm -f "$KOTO_STORE/requests/req-2.json"
leg_report req-2 deliver
eq "a request koto can't read exits 2" 2 "$RC"

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

echo "== progress (a checkpoint report, shirabe#491) =="
report '{"event":"progress","unit":"alpha","report":"checkpoint 1 reached"}'
eq "progress for a linked holding goes back to the hub" "progress 12 alpha" "${OUT% sealed:*}"
tok_shape "progress is in koto's capture alphabet" "$OUT"
eq "report.json marks it progress" "true null" "$(facts | jq -r '"\(.progress) \(.refused)"')"
report '{"event":"progress","unit":"zeta","report":"checkpoint 1 reached"}'
eq "progress naming no pull request goes back to the hub" "progress none zeta" "${OUT% sealed:*}"
report '{"event":"progress","unit":"zeta","report":"PR is up","pull_request":"acme/widgets#20"}'
eq "progress naming a pull request its holding lacks is linked first" "link 20 zeta" "${OUT% sealed:*}"
report '{"event":"progress","unit":"zeta","report":"PR is up","pull_request":"acme/other#3"}'
eq "progress naming a pull request out of scope still goes back to the hub" "progress none zeta" "${OUT% sealed:*}"
eq "and keeps the refusal in report.json" "true out-of-scope-repo" "$(facts | jq -r '"\(.progress) \(.refused)"')"
report '{"event":"report","unit":"alpha"}'
eq "a report after progress is classified as before" "holding 12 alpha" "${OUT% sealed:*}"

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
