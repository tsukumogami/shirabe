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
# request read (2); no session, and the override flags, a usage error (64);
# the head GitHub reports kept as the holding's pushed head. The record is the
# run's session's, record/holdings; nothing is written on GitHub.
#
# Usage: bash skills/coordinate/scripts/holding-link_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
HL="$HERE/holding-link.sh"
RF="$HERE/report-facts.sh"
h() { # h <worker> <branch> <pull_request cell> [return path]
    holding "$1" "$(jq -nc --arg b "$2" --arg p "$3" --arg r "${4:-message}" '{branch: $b, pull_request: $p, return_path: $r}')"
}
pr() { # pr <n> <headRefName> [cross]
    db '.prs += [{repo: "acme/widgets", number: $n, title: "w", body: "", state: "OPEN", isDraft: false, isCrossRepository: ($x == "true"),
        baseRefName: "main", headRefName: $b, headRefOid: $h, author: "alice", editor: null, mergeStateStatus: "CLEAN"}]' \
        --argjson n "$1" --arg b "$2" --arg x "${3:-false}" --arg h "$SHA_HEAD"
}
# seed <holdings-json>: the pull requests, and the record holding them, written
# into the current run's session (S) and each one session() opens after.
seed() {
    db_init
    pr 12 feat/alpha; pr 20 feat/zeta-work; pr 21 feat/kappa-work
    REC=$(record_json roadmap plugin-system | jq -c --argjson h "$1" '.holdings = $h')
    [ -z "${S:-}" ] || seed_session "$S" "$REC"
}
row() { session_state "$S" | jq -c --arg t "$1" '.holdings[] | select(.worker == $t) | {branch, pull_request}'; }
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit)|comment|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }
N=0
session() { # a fresh run at wait, holding the seeded record; the run before it ended
    [ -z "${S:-}" ] || log_end "$S"
    N=$((N + 1))
    S="coordinate-roadmap-plugin-system-20260926T0800$(printf '%02d' "$N")Z"
    found_session "$S" "$(roadmap_vars plugin-system)"
    seed_session "$S" "$REC"
    log_to "$S" reconcile wait
}
facts() { # facts: report_facts reads the arrival and seals its verdict; the run moves to report_link
    log_to "$S" wait report_facts
    CAP=$(bash "$RF" --session "$S" 2>"$T/rf.err")
    log_capture "$S" REPORT "$CAP"
    log_to "$S" report_facts report_link
}
link() { OUT=$(bash "$HL" --session "$S" 2>"$T/err"); RC=$?; }
message() { # message <unit> <pull_request> [event]: a message report, read by report_facts
    session
    log_evidence "$S" wait "$(jq -nc --arg u "$1" --arg p "$2" --arg e "${3:-report}" '{event: $e, unit: $u, report: "PR is up", pull_request: $p}')"
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
eq "the pull request is written" "0 $S" "$RC $OUT"
eq "  ... into the session's record/holdings" "[#20](https://github.com/acme/widgets/pull/20)" \
    "$(koto context get "$S" record/holdings | jq -r '.[] | select(.worker == "zeta") | .pull_request')"
eq "  ... with nothing written on GitHub" "" "$(gh_writes)"
eq "Branch is the pull request's headRefName, Pull request its link" \
    '{"branch":"feat/zeta-work","pull_request":"[#20](https://github.com/acme/widgets/pull/20)"}' "$(row zeta)"
grep -q 'pr view 20 --repo acme/widgets' "$GH_DB.calls" && ok "the head branch is read from GitHub" || bad "the head branch is read from GitHub" "$(calls)"
eq "the other holdings are unchanged" '{"branch":"feat/alpha","pull_request":"[#12](https://github.com/acme/widgets/pull/12)"}' "$(row alpha)"
reset_calls
link
eq "run again once linked: nothing to do" "0 already linked" "$RC $OUT"
SNAP=$(session_snapshot "$S")
link
eq "and nothing is written" "$SNAP" "$(session_snapshot "$S")"
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

echo "== a progress report's pull request (shirabe#491) =="
seed "$HOLD"
message zeta "acme/widgets#20" progress
eq "report_facts sealed link for a progress report's pull request" "link 20 zeta" "${CAP% sealed:*}"
link
eq "a progress report's pull request is written" \
    '0 {"branch":"feat/zeta-work","pull_request":"[#20](https://github.com/acme/widgets/pull/20)"}' "$RC $(row zeta)"

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
export KOTO_FAIL_ADD=record/holdings
link; eq "a write that fails is state-holding.sh's 11, to run again" 11 "$RC"
unset KOTO_FAIL_ADD
seed "$HOLD"
message zeta "acme/widgets#20"
db '.fail = [{match: "pr view 20", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
link; eq "a failed pull request read exits 2" 2 "$RC"
db '.fail = []'
bash "$HL" >/dev/null 2>&1; eq "no session is a usage error" 64 $?
bash "$HL" --session "$S" --scope roadmap --name plugin-system --repo "$REPO" >/dev/null 2>&1; eq "the override flags are a usage error" 64 $?
bash "$HL" --session "$S" --ref 7 >/dev/null 2>&1; eq "--ref is a usage error" 64 $?

echo "== the pushed head (PRD R17) =="
seed "$HOLD"
reset_calls
message zeta "https://github.com/acme/widgets/pull/20"
link
eq "a link is written" 0 "$RC"
eq "  ... into the session's holding, with the head GitHub reports" "feat/zeta-work $SHA_HEAD" \
    "$(koto context get "$S" record/holdings | jq -r '.[] | select(.worker == "zeta") | "\(.branch) \(.pushed_head)"')"
eq "  ... and nothing written on GitHub" "" "$(gh_writes)"
# A later report on the linked pull request: report-facts.sh keeps the head it
# reads when it moved. Its write goes through state-holding.sh, so a refused
# write (here: another run of the scope is live) changes no verdict.
OTHER=coordinate-roadmap-plugin-system-20260926T090000Z
found_session "$OTHER" "$(roadmap_vars plugin-system)"
NEWH=3333333333333333333333333333333333333333
db '(.prs[] | select(.number == 20)).headRefOid = $h' --arg h "$NEWH"
log_to "$S" report_link wait
log_evidence "$S" wait "$(jq -nc '{event: "report", unit: "zeta", report: "pushed again", pull_request: ""}')"
log_to "$S" wait report_facts
CAP=$(bash "$RF" --session "$S" 2>"$T/rf.err")
eq "report_facts reads the holding's pull request" "holding 20 zeta" "${CAP% sealed:*}"
grep -q "pushed head $NEWH wasn't kept" "$T/rf.err" && ok "  ... a refused head write is named on stderr, the verdict unchanged" \
    || bad "  ... a refused head write is named on stderr, the verdict unchanged" "$(cat "$T/rf.err")"
for d in "$KOTO_STORE"/sessions/*/; do o=$(basename "$d"); [ "$o" = "$S" ] || log_end "$o"; done
CAP=$(bash "$RF" --session "$S" 2>"$T/rf.err")
eq "  ... and with this run the live one, the head it read is kept" "holding 20 zeta|$NEWH" \
    "${CAP% sealed:*}|$(koto context get "$S" record/holdings | jq -r '.[] | select(.worker == "zeta") | .pushed_head')"
eq "  ... and still nothing written on GitHub" "" "$(gh_writes)"

done_tests holding-link
