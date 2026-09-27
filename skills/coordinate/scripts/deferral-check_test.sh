#!/usr/bin/env bash
# deferral-check_test.sh -- deferral-check.sh, the check in front of every
# dispatch, and its row mode.
#
# Covers, row mode: `filed #12`, `closed: <reason>` and a carry at or after
# the run start disposed; an earlier carry time, `filed` without a number, an
# empty Disposition and a row that isn't JSON undisposed (exit 1); an
# undisposed row raised this run (exit 0). Check mode: a `None.` section and
# every disposed form passing with the pick's topic; an earlier carry, an
# empty Disposition before the run start, `filed #<n>` naming no issue or a
# pull request, each deferral-open; a row raised this run exempt; a discipline
# predecessor's handoff deferral (read from the host's default branch) missing
# from the record or left without a disposition, compared only until the run's
# first `ok`; record-changed for a closed, missing or non-canonical record and
# a run without a found record; at-cap at the cap and at the parked bound, with
# send_execution adding no active worker, and CAP from the session; a failed
# read (2); the sealed token and its detail; every token in koto's capture
# alphabet.
#
# Usage: bash skills/coordinate/scripts/deferral-check_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
DC="$HERE/deferral-check.sh"
CL="$HERE/coord-log.sh"
tok_shape() {
    local re='^[A-Za-z0-9 :/_.@-]*$'
    if [[ ${2% sealed:*} =~ $re ]]; then ok "$1"; else bad "$1" "[$2]"; fi
}
RS=2026-09-26T08:00:00.000Z   # test-lib's run start

echo "== row mode =="
row() { # row <disposition> [raised]: judge one row
    jq -nc --arg d "$1" --arg r "${2:-2026-09-25T10:00Z}" '{deferral: "x", reason: "r", raised: $r, disposition: $d}' > "$T/row.json"
    bash "$DC" --row-file "$T/row.json" --run-start "$RS"
}
OUT=$(row 'filed #12'); eq "filed #12 is disposed" "0 disposed filed 12" "$? $OUT"
OUT=$(row 'closed: moot now'); eq "closed: <reason> is disposed" "0 disposed closed" "$? $OUT"
OUT=$(row 'carried 2026-09-26T08:30Z: waits on infra'); eq "a carry after the run start is disposed" "0 disposed carried 2026-09-26T08:30Z" "$? $OUT"
OUT=$(row 'carried 2026-09-26T08:00Z: same minute'); eq "a carry in the run start's minute is disposed" "0 disposed carried 2026-09-26T08:00Z" "$? $OUT"
OUT=$(row 'carried 2026-09-25T08:30Z: last run'); eq "an earlier carry time is refused" "1 undisposed carried-before-run-start" "$? $OUT"
OUT=$(row 'filed'); eq "filed without a number is refused" "1 undisposed malformed" "$? $OUT"
OUT=$(row 'filed #abc'); eq "filed with a non-number is refused" "1 undisposed malformed" "$? $OUT"
OUT=$(row 'carried soon: later'); eq "a carry without a time is refused" "1 undisposed malformed" "$? $OUT"
OUT=$(row ''); eq "an empty Disposition is refused" "1 undisposed empty" "$? $OUT"
OUT=$(row '' 2026-09-26T09:00Z); eq "an undisposed row raised this run isn't the predecessor's" "0 undisposed raised-this-run" "$? $OUT"
OUT=$(row 'carried 2026-09-25T08:30Z: x' 2026-09-26T09:00Z); eq "a bad carry on a row raised this run is exempt too" "0 undisposed raised-this-run" "$? $OUT"
printf 'not json' > "$T/row.json"
OUT=$(bash "$DC" --row-file "$T/row.json" --run-start "$RS" 2>/dev/null); eq "a row that isn't JSON is malformed" "1 undisposed malformed" "$? $OUT"
bash "$DC" --row-file "$T/row.json" >/dev/null 2>&1; eq "row mode without --run-start is a usage error" 64 $?
bash "$DC" --row-file "$T/row.json" --run-start yesterday >/dev/null 2>&1; eq "a run start that isn't a time is a usage error" 64 $?

echo "== check mode: deferrals =="
ITITLE="Coordinator record: ROADMAP-plugin-system"
seed() { # seed <record-json> [state]: the record issue #7, issue #12 and pull request #13
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: ($s // "open"), author: "alice", editor: null},
                    {repo: "acme/widgets", number: 12, title: "a filed deferral", body: "", state: "open", author: "alice", editor: null}]
        | .prs += [{repo: "acme/widgets", number: 13, title: "a pull request", body: "", state: "OPEN", isDraft: false,
                    isCrossRepository: false, baseRefName: "main", headRefName: "feat/x", headRefOid: $h, author: "alice", editor: null}]' \
        --arg t "$ITITLE" --arg b "$(render "$1" issue)" --arg s "${2:-open}" --arg h "$SHA_HEAD"
}
def() { # def <disposition> [raised]
    jq -nc --arg d "$1" --arg r "${2:-2026-09-25T10:00Z}" --arg t "d-$RANDOM" '{deferral: $t, reason: "r", raised: $r, disposition: $d}'
}
with_deferrals() { record_json roadmap plugin-system | jq -c --argjson d "[$(IFS=,; echo "$*")]" '.deferrals = $d'; }
N=0
session() { # session <vars-json> <ref> [choice] [unit]: a run at dispatch_check after a pick
    N=$((N + 1))
    S="coordinate-roadmap-plugin-system-20260926T0800${N}Z"
    found_session "$S" "$1" "$2"
    log_to "$S" reconcile pick_facts; log_to "$S" pick_facts pick
    log_evidence "$S" pick "$(jq -nc --arg c "${3:-dispatch}" --arg u "${4:-beta}" '{choice: $c, unit: $u}')"
    log_to "$S" pick dispatch_check
}
check() { bash "$DC" --session "$S" 2>"$T/err" | sed 's/ sealed:.*//'; }
seed "$(record_json roadmap plugin-system)"; session "$(roadmap_vars plugin-system)" 7
OUT=$(bash "$DC" --session "$S" 2>"$T/err")
eq "a None. section passes with the pick's topic" "ok beta" "${OUT% sealed:*}"
tok_shape "ok is in koto's capture alphabet" "$OUT"
bash "$CL" check --session "$S" --state dispatch_check --sealed "$OUT" && ok "the token is sealed to dispatch_check" || bad "the token is sealed to dispatch_check"
eq "the detail goes to coord/dispatch_check.json" "ok 0 0 5 3" "$(jq -r '"\(.verdict) \(.active) \(.parked) \(.cap) \(.parked_bound)"' "$KOTO_STORE/context/$S/coord/dispatch_check.json")"
seed "$(with_deferrals "$(def 'filed #12')" "$(def 'closed: moot')" "$(def 'carried 2026-09-26T08:30Z: later')")"
eq "filed (an existing issue), closed and a carry after the run start pass" "ok beta" "$(check)"
grep -q '^api --method GET repos/acme/widgets/issues/12$' "$GH_DB.calls" && ok "the filed issue is read in the host" || bad "the filed issue is read in the host" "$(calls)"
seed "$(with_deferrals "$(def 'filed #99')")"
OUT=$(check); eq "filed #<n> naming no issue is open" "deferral-open 1" "$OUT"
tok_shape "deferral-open is in koto's capture alphabet" "$OUT"
seed "$(with_deferrals "$(def 'filed #13')")"
eq "filed #<n> naming a pull request is open" "deferral-open 1" "$(check)"
seed "$(with_deferrals "$(def 'filed #0')")"
eq "filed #0 is open" "deferral-open 1" "$(check)"
seed "$(with_deferrals "$(def 'carried 2026-09-25T08:30Z: last run')" "$(def '')")"
eq "an earlier carry and an empty Disposition are two open" "deferral-open 2" "$(check)"
seed "$(with_deferrals "$(def '' 2026-09-26T09:00Z)")"
eq "a deferral raised this run may stay open" "ok beta" "$(check)"
seed "$(with_deferrals "$(def 'filed #12')")"; db '.fail = [{match: "issues/12", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
check >/dev/null; eq "a failed issue read exits 2" 2 ${PIPESTATUS[0]}

echo "== check mode: the record =="
seed "$(record_json roadmap plugin-system)" closed
OUT=$(check); eq "a closed record is record-changed" "record-changed" "$OUT"
tok_shape "record-changed is in koto's capture alphabet" "$OUT"
seed "$(record_json roadmap plugin-system)"; db '.issues |= map(select(.number != 7))'
eq "a missing record is record-changed" "record-changed" "$(check)"
seed "$(record_json roadmap plugin-system)"; db '(.issues[] | select(.number == 7)).body += "\nstray"'
eq "a record no longer canonical is record-changed" "record-changed" "$(check)"
seed "$(record_json roadmap other)"
eq "another scope's record under the number is record-changed" "record-changed" "$(check)"
seed "$(record_json roadmap plugin-system)"; db '.fail = [{match: "issue view", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
check >/dev/null; eq "a failed record read exits 2" 2 ${PIPESTATUS[0]}
N=$((N + 1)); S="coordinate-roadmap-plugin-system-20260926T0800${N}Z"
log_new "$S" "$(roadmap_vars plugin-system)"; log_to "$S" pick dispatch_check
seed "$(record_json roadmap plugin-system)"
eq "a run without a found record is record-changed" "record-changed" "$(check)"

echo "== check mode: a topic already held =="
pr_dup() { db '.prs += [{repo: "acme/widgets", number: 41, title: "w", body: "", state: "OPEN", isDraft: true, isCrossRepository: false,
    baseRefName: "main", headRefName: "feat/41", headRefOid: $h, author: "alice", editor: null}]' --arg h "$SHA_HEAD"; }
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding beta '{"pull_request": "[#41](https://github.com/acme/widgets/pull/41)"}')" '.holdings = [$h]')"
pr_dup
session "$(roadmap_vars plugin-system)" 7
OUT=$(check); eq "dispatching a topic a Holdings row already names is refused" "duplicate-topic beta" "$OUT"
tok_shape "duplicate-topic is in koto's capture alphabet" "$OUT"
session "$(roadmap_vars plugin-system)" 7 scope_ahead beta
eq "scope_ahead on a held topic is refused too" "duplicate-topic beta" "$(check)"
session "$(roadmap_vars plugin-system)" 7 dispatch gamma
eq "another topic is clear" "ok gamma" "$(check)"

echo "== check mode: the topic is the one this visit's path chose =="
# A pick from an earlier visit of pick is not the one checked: a later visit
# whose evidence names another unit is.
session "$(roadmap_vars plugin-system)" 7 dispatch gamma
log_to "$S" dispatch_check dispatch; log_evidence "$S" dispatch '{"dispatched":"failed","topic":"gamma"}'
log_to "$S" dispatch failure; log_evidence "$S" failure '{"move":"escalate"}'; log_to "$S" failure wait
log_to "$S" wait pick_facts; log_to "$S" pick_facts pick
log_evidence "$S" pick '{"choice":"dispatch","unit":"delta"}'; log_to "$S" pick dispatch_check
eq "the pick after the latest entry into pick is checked, not an earlier one" "ok delta" "$(check)"
session "$(roadmap_vars plugin-system)" 7 dispatch gamma
log_to "$S" dispatch_check deferral_dispose; log_evidence "$S" deferral_dispose '{"rewritten":"rewritten"}'
log_to "$S" deferral_dispose dispatch_check
eq "back from deferral_dispose, the same pick is checked" "ok gamma" "$(check)"
# A redispatch after a failed dispatch checks the unit this state sealed before.
session "$(roadmap_vars plugin-system)" 7 dispatch gamma
log_capture "$S" DISPATCH_CHECK "$(bash "$CL" seal --session "$S" --state dispatch_check --token "ok gamma")"
log_to "$S" dispatch_check dispatch; log_evidence "$S" dispatch '{"dispatched":"failed","topic":"gamma"}'
log_to "$S" dispatch failure; log_evidence "$S" failure '{"move":"redispatch"}'; log_to "$S" failure dispatch_check
eq "a redispatch after a failed dispatch checks the unit that failed" "ok gamma" "$(check)"
# A redispatch of a held unit (a dead worker, via wait) is not a duplicate.
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding beta '{"pull_request": "[#41](https://github.com/acme/widgets/pull/41)"}')" '.holdings = [$h]')"
session "$(roadmap_vars plugin-system)" 7 dispatch gamma
log_to "$S" dispatch_check dispatch; log_to "$S" dispatch record; log_to "$S" record wait
log_evidence "$S" wait '{"event":"failed","unit":"beta"}'; log_to "$S" wait failure
log_evidence "$S" failure '{"move":"redispatch"}'; log_to "$S" failure dispatch_check
eq "a redispatch of a held unit is checked on that unit and isn't a duplicate" "ok beta" "$(check)"

echo "== check mode: a redispatch on the leg path =="
# The unit that failed arrived on a koto request leg: its wait evidence names
# no unit, so the unit is the holding whose Return path is the captured leg
# (lib_unit, as report-facts.sh resolves it), never `-`.
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding theta '{"return_path": "leg req-1:execute", "pull_request": "[#41](https://github.com/acme/widgets/pull/41)"}')" '.holdings = [$h]')"
session "$(roadmap_vars plugin-system)" 7 dispatch gamma
log_to "$S" dispatch_check dispatch; log_to "$S" dispatch record; log_to "$S" record wait
log_evidence "$S" wait '{"event":"leg"}'; log_to "$S" wait leg_pick
log_capture "$S" WAIT_REQ req-1; log_to "$S" leg_pick wait_leg
log_capture "$S" WAIT_LEG execute; log_to "$S" wait_leg take_report
log_to "$S" take_report failure
log_evidence "$S" failure '{"move":"redispatch"}'; log_to "$S" failure dispatch_check
eq "a redispatch after a leg arrival checks the holding the leg names" "ok theta" "$(check)"
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding theta '{"return_path": "leg req-9:execute"}')" '.holdings = [$h]')"
eq "a leg no holding carries resolves to no unit, not a guess" "ok -" "$(check)"

echo "== check mode: the cap and the parked bound =="
pr() { # pr <n> <state> <draft>
    db '.prs += [{repo: "acme/widgets", number: $n, title: "w", body: "", state: $s, isDraft: ($d == "true"), isCrossRepository: false,
        baseRefName: "main", headRefName: "feat/\($n)", headRefOid: $h, author: "alice", editor: null}]' \
        --argjson n "$1" --arg s "$2" --arg d "$3" --arg h "$SHA_HEAD"
}
active() { holding "$1" "{\"pull_request\": \"[#$2](https://github.com/acme/widgets/pull/$2)\"}"; }
parked() { holding "$1" "{\"pull_request\": \"[#$2](https://github.com/acme/widgets/pull/$2)\", \"verified_head\": \"$SHA_HEAD\"}"; }
with_holdings() { record_json roadmap plugin-system | jq -c --argjson h "[$(IFS=,; echo "$*")]" '.holdings = $h'; }
seed "$(with_holdings "$(active a1 21)" "$(active a2 22)" "$(active a3 23)" "$(active a4 24)" "$(active a5 25)")"
for n in 21 22 23 24 25; do pr $n OPEN true; done
session "$(roadmap_vars plugin-system)" 7
OUT=$(check); eq "five active workers under a cap of five is at-cap" "at-cap 5/5 0/3" "$OUT"
tok_shape "at-cap is in koto's capture alphabet" "$OUT"
scoping() { holding "$1" "{\"pull_request\": \"[#$2](https://github.com/acme/widgets/pull/$2)\", \"phase\": \"scoping-ahead\"}"; }
seed "$(with_holdings "$(active a1 21)" "$(active a2 22)" "$(active a3 23)" "$(active a4 24)" "$(scoping a5 25)")"
session "$(roadmap_vars plugin-system)" 7 send_execution a5
eq "send_execution to a scoping-ahead holding adds no active worker" "ok a5" "$(check)"
session "$(roadmap_vars plugin-system)" 7 send_execution a4
eq "send_execution to a holding that isn't scoping ahead is judged as a dispatch" "at-cap 5/5 0/3" "$(check)"
session "$(roadmap_vars plugin-system)" 7 send_execution nobody
eq "send_execution to a unit with no holding is judged as a dispatch" "at-cap 5/5 0/3" "$(check)"
session "$(roadmap_vars plugin-system | jq -c '.CAP = "6"')" 7
eq "the cap comes from the session's CAP" "ok beta" "$(check)"
seed "$(with_holdings "$(parked p1 31)" "$(parked p2 32)" "$(parked p3 33)")"
for n in 31 32 33; do pr $n OPEN false; done
session "$(roadmap_vars plugin-system)" 7
eq "three parked workers is at the parked bound" "at-cap 0/5 3/3" "$(check)"
seed "$(with_holdings "$(parked p1 31)" "$(parked p2 32)" "$(parked p3 33)" "$(scoping s1 34)")"
for n in 31 32 33; do pr $n OPEN false; done; pr 34 OPEN true
session "$(roadmap_vars plugin-system)" 7 send_execution s1
eq "send_execution dispatches nothing new, so the parked bound doesn't stop it" "ok s1" "$(check)"
seed "$(with_holdings "$(parked p1 31)" "$(parked p2 32)" "$(parked p3 33)")"
pr 31 OPEN false; pr 32 OPEN true; pr 33 MERGED false
session "$(roadmap_vars plugin-system)" 7
eq "a verified draft and a merged pull request aren't parked" "ok beta" "$(check)"
eq "they count as active" "2 1" "$(jq -r '"\(.active) \(.parked)"' "$KOTO_STORE/context/$S/coord/dispatch_check.json")"

echo "== check mode: the predecessor's handoff (discipline) =="
BR=coordinate/discipline-ci-health
HP=docs/disciplines/ci-health.md
PREV='{"deferral":"flaky lint job","reason":"needs a runner","raised":"2026-09-16T10:00Z","disposition":""}'
dseed() { # dseed <record-json> [handoff-on-main: yes|no]
    db_init
    db '.branches["acme/widgets"][$br] = $s | .prs += [{repo: "acme/widgets", number: 22, title: "docs(coordinate): ci-health rotation 2026-09-26 to 2026-10-03",
        body: $b, state: "OPEN", isDraft: true, isCrossRepository: false, baseRefName: "main", headRefName: $br, headRefOid: $s, author: "alice", editor: null}]' \
        --arg br "$BR" --arg s "$SHA_HEAD" --arg b "$(render "$1" pr)"
    if [ "${2:-yes}" = yes ]; then
        record_json discipline ci-health | jq -c --argjson d "$PREV" '. + {deferrals: [$d], rotation: {start: "2026-09-19", end: "2026-09-26", date: "2026-09-26",
            host_repo: "acme/widgets", record_url: "https://github.com/acme/widgets/pull/20"}, reasoning: "Lint is flaky."}' \
            | bash "$HERE/record-render.sh" --format handoff > "$T/prev.md"
        db '.files["acme/widgets"][$k] = $t' --arg k "main:$HP" --arg t "$(cat "$T/prev.md")"
    fi
}
dsession() {
    N=$((N + 1))
    S="coordinate-discipline-ci-health-20260926T0800${N}Z"
    found_session "$S" "$(discipline_vars ci-health)" 22
    log_to "$S" reconcile pick_facts; log_to "$S" pick_facts pick
    log_evidence "$S" pick '{"choice":"dispatch","unit":"beta"}'
    log_to "$S" pick dispatch_check
}
mine() { record_json discipline ci-health | jq -c --argjson d "[$(IFS=,; echo "$*")]" '.deferrals = $d'; }
dseed "$(record_json discipline ci-health)"; dsession
eq "a handoff deferral missing from the record is open" "deferral-open 1" "$(check)"
grep -q "contents/$HP?ref=main" "$GH_DB.calls" && ok "the handoff is read from the host's default branch" || bad "the handoff is read from the host's default branch" "$(calls)"
dseed "$(mine '{"deferral":"flaky lint job","reason":"needs a runner","raised":"2026-09-26T08:10Z","disposition":""}')"
eq "carried into the record without a disposition is still open" "deferral-open 1" "$(check)"
dseed "$(mine '{"deferral":"flaky lint job","reason":"needs a runner","raised":"2026-09-16T10:00Z","disposition":"carried 2026-09-26T08:10Z: infra owns it"}')"
eq "carried into the record with a disposition passes" "ok beta" "$(check)"
dseed "$(mine '{"deferral":"flaky lint job","reason":"needs a runner","raised":"2026-09-16T10:00Z","disposition":"filed #12"}')"
db '.issues += [{repo: "acme/widgets", number: 12, title: "lint", body: "", state: "open", author: "alice", editor: null}]'
eq "filed into the record passes" "ok beta" "$(check)"
dseed "$(record_json discipline ci-health)" no
eq "no handoff file on the default branch is no deferral" "ok beta" "$(check)"
echo "-- after the first pass --"
dseed "$(mine '{"deferral":"flaky lint job","reason":"needs a runner","raised":"2026-09-16T10:00Z","disposition":"closed: fixed upstream"}')"
dsession
OK1=$(bash "$DC" --session "$S" 2>/dev/null)
eq "the first pass" "ok beta" "${OK1% sealed:*}"
log_capture "$S" DISPATCH_CHECK "$OK1"
log_to "$S" dispatch_check dispatch; log_to "$S" dispatch record; log_to "$S" record pick_facts; log_to "$S" pick_facts pick
log_evidence "$S" pick '{"choice":"dispatch","unit":"gamma"}'
log_to "$S" pick dispatch_check
dseed "$(record_json discipline ci-health)"
reset_calls
eq "after the run's first ok the handoff isn't compared again" "ok gamma" "$(check)"
grep -q "contents/$HP" "$GH_DB.calls" && bad "the handoff isn't read after the first pass" "$(calls)" || ok "the handoff isn't read after the first pass"
dsession
log_capture "$S" DISPATCH_CHECK "ok beta sealed:3:0000000000000000000000000000000000000000000000000000000000000000"
eq "a DISPATCH_CHECK capture whose seal fails doesn't count as a pass" "deferral-open 1" "$(check)"

done_tests deferral-check
