#!/usr/bin/env bash
# holding-link_test.sh -- holding-link.sh writes the pull request a report
# names, and its head branch, onto a holding that links none yet.
#
# Covers: a message report's pull_request written with the headRefName GitHub
# reports as Branch, never text from the report; a leg result's pr the same,
# read from koto's record of the leg; a Branch cell already set that agrees,
# kept; running it again once linked, the link's repository in any case
# (exit 0, nothing written); a failed write (11); refusals before any write:
# the report's pull request in no readable form or outside the scope (65),
# the run not at report_link or
# report_facts' verdict not `link` (10), the latest report now another
# worker's or naming another number (10), a holding already linking another
# pull request, one another holding links, a fork head that appeared since
# report_facts read it, a Branch cell that disagrees (65); a failed pull
# request read (2).
#
# Usage: bash skills/coordinate/scripts/holding-link_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
HL="$HERE/holding-link.sh"
RF="$HERE/report-facts.sh"
W_RM=(--scope roadmap --name plugin-system --repo "$REPO" --ref 7 --skip-session-checks)
TITLE="Coordinator record: ROADMAP-plugin-system"
h() { # h <worker> <branch> <pull_request cell> [return path]
    holding "$1" "$(jq -nc --arg b "$2" --arg p "$3" --arg r "${4:-message}" '{branch: $b, pull_request: $p, return_path: $r}')"
}
pr() { # pr <n> <headRefName> [cross]
    db '.prs += [{repo: "acme/widgets", number: $n, title: "w", body: "", state: "OPEN", isDraft: false, isCrossRepository: ($x == "true"),
        baseRefName: "main", headRefName: $b, headRefOid: $h, author: "alice", editor: null, mergeStateStatus: "CLEAN"}]' \
        --argjson n "$1" --arg b "$2" --arg x "${3:-false}" --arg h "$SHA_HEAD"
}
seed() { # seed <holdings-json>
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' \
        --arg t "$TITLE" --arg b "$(render "$(record_json roadmap plugin-system | jq -c --argjson h "$1" '.holdings = $h')" issue)"
    pr 12 feat/alpha; pr 20 feat/zeta-work; pr 21 feat/kappa-work
}
row() { jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB" | bash "$HERE/record-parse.sh" | jq -c --arg t "$1" '.holdings[] | select(.worker == $t) | {branch, pull_request}'; }
N=0
session() { # a fresh run at wait
    N=$((N + 1))
    S="coordinate-roadmap-plugin-system-20260926T0800$(printf '%02d' "$N")Z"
    found_session "$S" "$(roadmap_vars plugin-system)" 7
    log_to "$S" reconcile wait
}
facts() { # facts: report_facts reads the arrival and seals its verdict; the run moves to report_link
    log_to "$S" wait report_facts
    CAP=$(bash "$RF" --session "$S" 2>"$T/rf.err")
    log_capture "$S" REPORT "$CAP"
    log_to "$S" report_facts report_link
}
link() { OUT=$(bash "$HL" --session "$S" "${W_RM[@]}" 2>"$T/err"); RC=$?; }
message() { # message <unit> <pull_request>: a message report, read by report_facts
    session
    log_evidence "$S" wait "$(jq -nc --arg u "$1" --arg p "$2" '{event: "report", unit: $u, report: "PR is up", pull_request: $p}')"
    facts
}
HOLD=$(jq -nc --argjson a "$(h alpha feat/alpha '[#12](https://github.com/acme/widgets/pull/12)')" \
    --argjson z "$(h zeta '' '')" --argjson l "$(h lambda feat/lambda '')" \
    --argjson k "$(h kappa '' '' 'leg req-2:deliver')" '[$a, $z, $l, $k]')

echo "== the message path =="
seed "$HOLD"
message zeta "https://github.com/acme/widgets/pull/20"
eq "report_facts sealed link" "link 20 zeta" "${CAP% sealed:*}"
reset_calls
link
eq "the pull request is written" "0 https://github.com/acme/widgets/issues/7" "$RC $OUT"
eq "Branch is the pull request's headRefName, Pull request its link" \
    '{"branch":"feat/zeta-work","pull_request":"[#20](https://github.com/acme/widgets/pull/20)"}' "$(row zeta)"
grep -q 'pr view 20 --repo acme/widgets' "$GH_DB.calls" && ok "the head branch is read from GitHub" || bad "the head branch is read from GitHub" "$(calls)"
eq "the other holdings are unchanged" '{"branch":"feat/alpha","pull_request":"[#12](https://github.com/acme/widgets/pull/12)"}' "$(row alpha)"
reset_calls
link
eq "run again once linked: nothing to do" "0 already linked" "$RC $OUT"
grep -q 'issue edit' "$GH_DB.calls" && bad "and nothing is written" "$(calls)" || ok "and nothing is written"
log_to "$S" report_link report_facts
AGAIN=$(bash "$RF" --session "$S" 2>/dev/null)
eq "report_facts now reads the holding's own pull request" "holding 20 zeta" "${AGAIN% sealed:*}"

echo "== the leg path =="
seed "$HOLD"
mkdir -p "$KOTO_STORE/requests"
jq -nc '{request: {legs: {deliver: {disposition: "resolved", result_source: "promoted", result_final_state: "done",
    result: {status: "ok", payload: {outcome: "ready", pr: "https://github.com/acme/widgets/pull/21"}}}}}}' > "$KOTO_STORE/requests/req-2.json"
session
log_evidence "$S" wait '{"event":"leg"}'
log_to "$S" wait leg_pick; log_capture "$S" WAIT_REQ req-2
log_to "$S" leg_pick wait_leg; log_capture "$S" WAIT_LEG deliver
log_to "$S" wait_leg take_report
log_to "$S" take_report report_facts
CAP=$(bash "$RF" --session "$S" 2>"$T/rf.err"); log_capture "$S" REPORT "$CAP"; log_to "$S" report_facts report_link
eq "report_facts sealed link for the leg's pull request" "link 21 kappa" "${CAP% sealed:*}"
link
eq "the leg's pull request is written" 0 "$RC"
eq "with its head branch" '{"branch":"feat/kappa-work","pull_request":"[#21](https://github.com/acme/widgets/pull/21)"}' "$(row kappa)"

echo "== a Branch cell already set =="
seed "$(printf '%s' "$HOLD" | jq -c 'map(if .worker == "lambda" then .branch = "feat/zeta-work" else . end)')"
message lambda "acme/widgets#20"
link
eq "a Branch that agrees with the head branch: written, Branch kept" \
    '0 {"branch":"feat/zeta-work","pull_request":"[#20](https://github.com/acme/widgets/pull/20)"}' "$RC $(row lambda)"
seed "$HOLD"
message zeta "acme/widgets#20"
seed "$(printf '%s' "$HOLD" | jq -c 'map(if .worker == "zeta" then .pull_request = "[#20](https://github.com/ACME/Widgets/pull/20)" else . end)')"
link
eq "already linked, the repository in another case: nothing to do" "0 already linked" "$RC $OUT"

echo "== the repository as GitHub spells it =="
# The stand-in matches a repository in any case, as GitHub does, and spells
# it back as GitHub does: the link takes GitHub's spelling, not the report's.
seed "$HOLD"
message zeta "ACME/Widgets#20"
link
eq "a report naming the repository in another case: written with GitHub's spelling" \
    '0 {"branch":"feat/zeta-work","pull_request":"[#20](https://github.com/acme/widgets/pull/20)"}' "$RC $(row zeta)"
grep -q -- '--repo ACME/Widgets' "$GH_DB.calls"; eq "and the pull request was read under the report's spelling" 0 $?

echo "== refusals =="
seed "$HOLD"
message zeta "acme/widgets#20"
log_to "$S" report_link surface
link; eq "not at report_link: refused" 10 "$RC"
session
log_evidence "$S" wait '{"event":"report","unit":"zeta","pull_request":"acme/widgets#20"}'
log_to "$S" wait report_link
link; eq "no sealed link verdict: refused" 10 "$RC"
message zeta "acme/widgets#20"
log_evidence "$S" wait '{"event":"report","unit":"lambda","pull_request":"acme/widgets#20"}'
link; eq "the latest report is another worker's: refused" 10 "$RC"
message zeta "acme/widgets#20"
log_evidence "$S" wait '{"event":"report","unit":"zeta","pull_request":"acme/widgets#21"}'
link; eq "the report now names another number: refused" 10 "$RC"
message zeta "acme/widgets#20"
seed "$(printf '%s' "$HOLD" | jq -c 'map(if .worker == "zeta" then .pull_request = "[#21](https://github.com/acme/widgets/pull/21)" else . end)')"
link; eq "a holding that links another pull request: refused" 65 "$RC"
seed "$HOLD"
message zeta "acme/widgets#20"
seed "$(printf '%s' "$HOLD" | jq -c 'map(if .worker == "alpha" then .pull_request = "[#20](https://github.com/acme/widgets/pull/20)" else . end)')"
link; eq "a pull request another holding links by now: refused" 65 "$RC"
seed "$HOLD"
message zeta "acme/widgets#20"
db '.prs |= map(if .number == 20 then .isCrossRepository = true else . end)'
link; eq "a fork head: refused" 65 "$RC"
seed "$HOLD"
message zeta "acme/widgets#20"
seed "$(printf '%s' "$HOLD" | jq -c 'map(if .worker == "zeta" then .branch = "feat/other" else . end)')"
link; eq "a Branch cell that disagrees with the head branch: refused" 65 "$RC"
eq "nothing refused was written" '{"branch":"feat/other","pull_request":""}' "$(row zeta)"
# The log's own report now names its pull request in a form that isn't one,
# or one outside the scope: each is checked again here, not taken from the seal.
seed "$HOLD"
message zeta "acme/widgets#20"
log_evidence "$S" wait '{"event":"report","unit":"zeta","pull_request":"PR 20"}'
link; eq "the report's pull request in no form a repository can be read from: refused" 65 "$RC"
message zeta "acme/widgets#20"
db '.repos["acme/other"] = {private: false, default_branch: "main"}'
log_evidence "$S" wait '{"event":"report","unit":"zeta","pull_request":"acme/other#20"}'
link; eq "a pull request outside the scope's repositories: refused" 65 "$RC"
eq "and nothing was written" '{"branch":"","pull_request":""}' "$(row zeta)"
seed "$HOLD"
message zeta "acme/widgets#20"
db '.fail = [{match: "issue edit", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
link; eq "a write that fails is record-holding.sh's 11, to run again" 11 "$RC"
db '.fail = []'
seed "$HOLD"
message zeta "acme/widgets#20"
db '.fail = [{match: "pr view 20", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
link; eq "a failed pull request read exits 2" 2 "$RC"
db '.fail = []'
bash "$HL" "${W_RM[@]}" >/dev/null 2>&1; eq "no session is a usage error" 64 $?

done_tests holding-link
