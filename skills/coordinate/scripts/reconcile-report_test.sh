#!/usr/bin/env bash
# reconcile-report_test.sh -- reconcile-report.sh builds the reconcile report
# from a facts document and renders it, with no I/O but stdin and stdout.
#
# Each case builds a facts document with jq and checks the report JSON or its
# rendering: the section order, the change entries, the seven next-line cases
# and the waiting list, the grades, the phase mark and its flag, the line
# bound, and that no raw read output, absolute path, session id or instance
# name reaches the report. One case runs the script with a PATH holding only
# jq. Needs bash and jq only.
#
# Usage: bash skills/coordinate/scripts/reconcile-report_test.sh
# Exit codes: 0 all pass; 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/reconcile-report.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n%s\n' "$1" "${2-}"; }

W=2026-09-26T10:00:00Z
NOW=2026-09-27T10:00:00Z
VH=1111111111111111111111111111111111111111
LH=2222222222222222222222222222222222222222

# facts <holdings-json> [side-effects-json] [deferrals-json] [reasoning-json] [unparseable-json] [kind]
facts() {
    jq -nc --argjson h "$1" --argjson s "${2:-[]}" --argjson d "${3:-[]}" \
        --argjson r "${4:-null}" --argjson u "${5:-[]}" --arg k "${6:-roadmap}" \
        --arg w "$W" --arg now "$NOW" '
      {schema: "coordinate-reconcile-facts/v1",
       scope: {kind: $k, name: "demo", repo: "acme/widgets"},
       record: {written: $w, source: (if $k == "discipline" then "handoff" else "record" end),
                handoff_date: (if $k == "discipline" then "2026-09-20" else null end)},
       reconciled_at: $now, holdings: $h, side_effects: $s, deferrals: $d,
       reasoning: $r, unparseable: $u}'
}

# holding <topic> <facts-json> [row-overrides-json]
holding() {
    # bash 3.2 expands "${3:-{\}}" differently from bash 4+, so the default
    # object is spelled out.
    local o=${3-}
    [ -n "$o" ] || o='{}'
    jq -nc --arg t "$1" --argjson f "$2" --argjson o "$o" --arg vh "$VH" '
      {row: ({unit: ("unit " + $t), entry_point: "/shirabe:deliver", mode: "--auto", phase: "",
              dispatch_status: "dispatched", return_path: "message", worker: $t,
              repo: "acme/widgets", branch: ("feat/" + $t), verified_head: $vh,
              dispatched: "2026-09-25", pull_request: "#1"} + $o),
       refused: null, facts: $f}'
}

pr()    { jq -nc --arg s "$1" --arg h "$2" --argjson d "${3:-false}" '{kind: "pr", status: "ok", state: $s, head: $h, draft: $d, read_at: "2026-09-27T09:59:00Z"}'; }
board() { jq -nc --arg v "$1" --arg at "$2" --arg d "${3:-}" '{kind: "board", status: "ok", at: $at, verdict: $v, detail: $d, read_at: "2026-09-27T09:59:10Z"}'; }
host()  { jq -nc --arg s "$1" '{kind: "host", status: "ok", state: $s, reads: 2, instance: ("cfg+t-" + ("d" * 8)), session_name: ("t-" + ("d" * 8)), read_at: "2026-09-27T09:58:00Z"}'; }

report() { "$BASH" "$S" json; }
render() { "$BASH" "$S" md; }

echo "== schema =="
grep -q 'coordinate-reconcile-facts/v1' "$S" && grep -q 'coordinate-reconcile-report/v1' "$S" \
  && grep -q 'verified_head, dispatched, pull_request' "$S" \
  && ok "the header documents both schemas and the row keys" \
  || bad "the header documents both schemas and the row keys"

echo '{"schema":"other"}' | bash "$S" json >/dev/null 2>&1; rc=$?
[ "$rc" = 65 ] && ok "a non-facts document exits 65" || bad "a non-facts document exits 65" "rc=$rc"
bash "$S" 2>/dev/null </dev/null; rc=$?
[ "$rc" = 64 ] && ok "no subcommand exits 64" || bad "no subcommand exits 64" "rc=$rc"

echo "== sections =="
EMPTY=$(facts '[]' '[]' '[]' '"absent"' '[]' discipline)
out=$(echo "$EMPTY" | render)
order=$(printf '%s\n' "$out" | grep '^## ' | tr '\n' '|')
want='## Changed since then|## Where things stand|## Exists nowhere else|## Side effects|## Undisposed deferrals|## Predecessor'"'"'s reasoning|## Not verified|'
[ "$order" = "$want" ] && ok "sections render in R16's order" || bad "sections render in R16's order" "$order"
nones=$(printf '%s\n' "$out" | grep -c '^None\.$')
[ "$nones" = 5 ] && ok "every empty section reads None." || bad "every empty section reads None." "count=$nones"
printf '%s\n' "$out" | grep -q 'No reasoning was received' && ok "absent reasoning says none was received" || bad "absent reasoning says none was received"
out=$(facts '[]' | render)
printf '%s\n' "$out" | grep -q "Predecessor" && bad "roadmap scope has no reasoning section" || ok "roadmap scope has no reasoning section"

echo "== changes =="
H=$(holding merged "[$(pr MERGED "$VH")]")
out=$(facts "[$H]" | report)
c=$(printf '%s' "$out" | jq -c '.changes[0]')
if printf '%s' "$c" | jq -e --arg w "$W" '.topic == "merged" and .recorded == "open" and .live == "merged" and .written == $w' >/dev/null; then
    ok "a change names the holding, both values and the Written time"
else bad "a change names the holding, both values and the Written time" "$c"; fi
line=$(facts "[$H]" | render | grep '^- `merged`: pull request')
case "$line" in *"record said open, now merged (written $W"*) ok "the rendered change carries all four" ;; *) bad "the rendered change carries all four" "$line" ;; esac

H=$(holding moved "[$(pr OPEN "$LH")]")
out=$(facts "[$H]" | report)
printf '%s' "$out" | jq -e --arg vh "$VH" --arg lh "$LH" '.changes | any(.what == "head moved" and .recorded == $vh and .live == $lh)' >/dev/null \
  && ok "a moved head is a change with both shas" || bad "a moved head is a change with both shas" "$out"

H=$(holding parked "[$(pr OPEN "$VH" true)]")
facts "[$H]" | report | jq -e '.changes | any(.what == "draft")' >/dev/null \
  && ok "a parked holding back in draft is a change" || bad "a parked holding back in draft is a change"

# The pass's settle: a row left dispatching, its worker live, now dispatched.
SETTLED='{"kind":"settle","status":"ok","settled":true,"reason":"","read_at":"2026-09-27T09:58:30Z"}'
H=$(holding stuck "[$(host found), $SETTLED]" '{"dispatch_status": "dispatching", "pull_request": "", "verified_head": ""}')
out=$(facts "[$H]" | report)
printf '%s' "$out" | jq -e '.changes | any(.what == "dispatch status" and .recorded == "dispatching" and .live == "dispatched" and .grade == "measured")' >/dev/null \
  && ok "a settled holding is a change, measured" || bad "a settled holding is a change, measured" "$out"
printf '%s' "$out" | "$BASH" "$S" md | sed -n '/^## Changed since then/,/^## /p' | grep -q '`stuck`: settled: record said dispatching, the worker is live, and the record now says dispatched' \
  && ok "the rendered report says the row was settled" || bad "the rendered report says the row was settled" "$(printf '%s' "$out" | "$BASH" "$S" md)"
H=$(holding stuck "[$(host found), $(jq -nc '{kind: "settle", status: "ok", settled: false, reason: "the holding is dispatched now", read_at: "t"}')]" '{"dispatch_status": "dispatching", "pull_request": ""}')
facts "[$H]" | report | jq -e '.changes | any(.what == "dispatch status") | not' >/dev/null \
  && ok "a settle that found nothing to write is no change" || bad "a settle that found nothing to write is no change"
# An earlier pass in this visit wrote the row but was stopped before its fact
# was kept: the row already says dispatched, and that is still the change.
H=$(holding stuck "[$(host found), $(jq -nc '{kind: "settle", status: "ok", settled: false, now: "dispatched", reason: "the holding is dispatched now", read_at: "t"}')]" '{"dispatch_status": "dispatching", "pull_request": ""}')
facts "[$H]" | report | jq -e '.changes | any(.what == "dispatch status")' >/dev/null \
  && ok "a row already dispatched by an earlier pass is still reported as changed" || bad "a row already dispatched by an earlier pass is still reported as changed"
H=$(holding stuck "[$(host found), $(jq -nc '{kind: "settle", status: "ok", settled: false, now: "dispatch-failed", reason: "the holding is dispatch-failed now", read_at: "t"}')]" '{"dispatch_status": "dispatching", "pull_request": ""}')
facts "[$H]" | report | jq -e '.changes | any(.what == "dispatch status") | not' >/dev/null \
  && ok "a row now at another status is not reported as settled" || bad "a row now at another status is not reported as settled"
H=$(holding stuck "[$(host found), $(jq -nc '{kind: "settle", status: "not_verified", reason: "the record refused the write", read_at: "t"}')]" '{"dispatch_status": "dispatching", "pull_request": ""}')
facts "[$H]" | report | jq -e '(.changes | any(.what == "dispatch status") | not) and (.not_verified | any(.what == "stuck: settle" and .reason == "the record refused the write"))' >/dev/null \
  && ok "a failed settle is not verified, and no change" || bad "a failed settle is not verified, and no change" "$(facts "[$H]" | report | jq -c '.not_verified')"

echo "== next lines and waiting =="
nx() { facts "[$1]" | report | jq -r '.holdings[0].next'; }
check_next() { local got; got=$(nx "$2"); [ "$got" = "$3" ] && ok "$1" || bad "$1" "want '$3' got '$got'"; }
check_next "merged -> drop"              "$(holding a "[$(pr MERGED "$VH")]")" "drop from holdings"
check_next "closed -> the coordinator's call" "$(holding a "[$(pr CLOSED "$VH")]")" "with me: re-dispatch or drop"
check_next "failing board -> worker fixes CI" "$(holding a "[$(pr OPEN "$VH"),$(board fails "$VH" "build: no runner")]")" "worker fixes CI"
check_next "holding board at verified head -> ready to land" "$(holding a "[$(pr OPEN "$VH"),$(board holds "$VH")]")" "ready to land"
check_next "a pending board at the verified head -> wait, not land" "$(holding a "[$(pr OPEN "$VH"),$(board pending "$VH")]")" "wait on worker"
check_next "open otherwise -> wait on worker" "$(holding a "[$(pr OPEN "$LH"),$(board holds "$LH")]")" "wait on worker"
check_next "no PR, found -> wait on worker" "$(holding a "[$(host found)]" '{"pull_request":"none yet"}')" "wait on worker"
check_next "no PR, not found -> read again" "$(holding a "[$(host missed)]" '{"pull_request":"none yet"}')" "read again, then decide"

MIX="[$(holding ready "[$(pr OPEN "$VH"),$(board holds "$VH")]"),$(holding closed "[$(pr CLOSED "$VH")]"),$(holding busy "[$(pr OPEN "$LH")]")]"
SE='[{"row":{"action":"merge","target":"acme/widgets#7","verified_head":"'$VH'","attempted":"2026-09-26T09:00Z"},"fact":{"kind":"merge","verdict":"not_confirmed","reason":"file differs","status":"ok"}},{"row":{"action":"merge","target":"acme/widgets#8"},"fact":{"kind":"merge","verdict":"confirmed","status":"ok"}}]'
w=$(facts "$MIX" "$SE" | report | jq -c '[.waiting[] | .topic] | sort')
[ "$w" = '["acme/widgets#7","ready"]' ] && ok "waiting lists ready-to-land and unconfirmed merges only, not a closed pull request" || bad "waiting lists ready-to-land and unconfirmed merges only" "$w"

echo "== grades =="
out=$(facts "$MIX" "$SE" '[{"row":{"deferral":"d1","reason":"r","raised":"2026-09-20"},"disposed":false}]' | report)
printf '%s' "$out" | jq -e '
  (.holdings | all(.grade.state == "measured" and (.grade.board == "verified by reading" or (.board == null and .grade.board == null)) and .grade.phase == "inferred" and .grade.next == "inferred"))
  and (.waiting | all(.grade == "inferred"))
  and (.deferrals | all(.grade == "verified by reading"))
  and (.changes | all(.grade == "measured"))
  and (.side_effects | all(.grade == "verified by reading"))' >/dev/null \
  && ok "each claim kind carries its grade" || bad "each claim kind carries its grade" "$out"
facts '[]' '[{"row":{"action":"reboot","target":"x"},"fact":{"kind":"other","verdict":"not_rechecked","status":"ok"}}]' | report \
  | jq -e '.side_effects[0].verdict == "not rechecked" and .side_effects[0].grade == "inferred"' >/dev/null \
  && ok "an unknown side effect is not re-checked and inferred" || bad "an unknown side effect is not re-checked and inferred"

echo "== phase =="
ph() { facts "[$1]" | report | jq -r '.holdings[0] | "\(.phase)|\(.phase_flag)"'; }
got=$(ph "$(holding a "[]" '{"phase":"scoping","entry_point":"/shirabe:deliver"}')")
[ "$got" = "scoping ahead|false" ] && ok "the phase key wins over the entry point" || bad "the phase key wins over the entry point" "$got"
got=$(ph "$(holding a "[]" '{"phase":"executing","entry_point":"/shirabe:scope"}')")
[ "$got" = "executing|false" ] && ok "an executing phase key wins over a scoping entry point" || bad "an executing phase key wins over a scoping entry point" "$got"
got=$(ph "$(holding a "[]" '{"phase":"","entry_point":"/shirabe:scope"}')")
[ "$got" = "scoping ahead|false" ] && ok "no phase key falls back to the entry point" || bad "no phase key falls back to the entry point" "$got"
got=$(ph "$(holding a "[]" '{"phase":"","mode":"--auto --intent=stop"}')")
[ "$got" = "scoping ahead|false" ] && ok "no phase key falls back to a scoping mode" || bad "no phase key falls back to a scoping mode" "$got"
got=$(ph "$(holding a '[{"kind":"files","status":"ok","paths":["docs/x/y.md","src/x"]}]' '{"phase":"scoping"}')")
[ "$got" = "scoping ahead|true" ] && ok "a scoping holding changing src/x is flagged" || bad "a scoping holding changing src/x is flagged" "$got"
got=$(ph "$(holding a '[{"kind":"files","status":"ok","paths":["docs/x/y.md","docs/plans/PLAN-a.md"]}]' '{"phase":"scoping"}')")
[ "$got" = "scoping ahead|false" ] && ok "a scoping holding changing only docs/ is not flagged" || bad "a scoping holding changing only docs/ is not flagged" "$got"
out=$(facts "[$(holding tr '[{"kind":"files","status":"ok","paths":["docs/a.md"],"truncated":true}]' '{"phase":"scoping"}')]" | report)
printf '%s' "$out" | jq -e '.holdings[0].phase_flag == false and (.not_verified | any(.what == "holding tr: files"))' >/dev/null \
  && ok "a truncated all-docs list is unsettled, not consistent" || bad "a truncated all-docs list is unsettled, not consistent" "$out"
got=$(ph "$(holding a '[{"kind":"files","status":"ok","paths":["docsx/a"]}]' '{"phase":"scoping"}')")
[ "$got" = "scoping ahead|true" ] && ok "docsx/a is outside docs/" || bad "docsx/a is outside docs/" "$got"
got=$(ph "$(holding a '[{"kind":"files","status":"ok","paths":["src/x"]}]' '{"phase":"executing"}')")
[ "$got" = "executing|false" ] && ok "an executing holding is never flagged" || bad "an executing holding is never flagged" "$got"
got=$(ph "$(holding a "[]" '{"phase":"Scoping-Ahead"}')")
[ "$got" = "scoping ahead|false" ] && ok "phase values match whole, ignoring case" || bad "phase values match whole, ignoring case" "$got"
out=$(facts "[$(holding a "[]" '{"phase":"scoped"}')]" | report)
printf '%s' "$out" | jq -e '.holdings[0].phase == "executing" and (.not_verified | any(.what == "holding a: phase"))' >/dev/null \
  && ok "an unrecognised phase value is marked executing and listed as not verified" || bad "an unrecognised phase value is marked executing and listed as not verified" "$out"
got=$(ph "$(holding a "[]" '{"phase":"","mode":"--auto --intent stop"}')")
[ "$got" = "scoping ahead|false" ] && ok "the mode fallback accepts --intent stop" || bad "the mode fallback accepts --intent stop" "$got"
got=$(ph "$(holding a "[]" '{"phase":"","mode":"--intent=stopper"}')")
[ "$got" = "executing|false" ] && ok "the mode fallback doesn't match --intent=stopper" || bad "the mode fallback doesn't match --intent=stopper" "$got"

echo "== grades follow the read =="
out=$(facts "[$(holding a '[{"kind":"pr","status":"not_verified","reason":"timeout"}]')]" | report)
printf '%s' "$out" | jq -e '.holdings[0].grade.state == "not verified" and .holdings[0].grade.board == null' >/dev/null \
  && ok "a failed pull request read is graded not verified, with no board grade" || bad "a failed pull request read is graded not verified, with no board grade" "$out"
out=$(facts "[$(holding a "[$(pr OPEN "$VH")]")]" | render)
printf '%s\n' "$out" | grep -q 'open (measured)' && ok "the rendered holding shows its state grade" || bad "the rendered holding shows its state grade" "$out"

echo "== merge state and legs =="
P=$(jq -nc --arg h "$VH" '{kind: "pr", status: "ok", state: "OPEN", head: $h, draft: false, merge_state: "BLOCKED", read_at: "2026-09-27T09:59:00Z"}')
L='{"kind":"leg","status":"ok","disposition":"resolved","result":"merged","read_at":"2026-09-27T09:58:30Z"}'
out=$(facts "[$(holding a "[$P,$L]" '{"return_path":"leg req1:deliver"}')]" | render)
printf '%s\n' "$out" | grep -q 'open (measured), merge state BLOCKED; leg resolved: merged (measured)' \
  && ok "the holding line carries the merge state and the leg's result beside the pull request state" || bad "merge state and leg beside the pull request state" "$out"
# A leg spent before its worker reported, with the worker found and no pull
# request: recoverable by replacing the leg, never a worker gone (shirabe#506).
HF='{"kind":"host","status":"ok","state":"found","reads":1,"read_at":"2026-09-27T09:58:00Z"}'
for spent in '{"kind":"leg","status":"ok","disposition":"resolved","source":"refused","result":"refused:private-repo","read_at":"t"}' \
             '{"kind":"leg","status":"ok","disposition":"resolved","source":"explicit","result":"cancelled","read_at":"t"}' \
             '{"kind":"leg","status":"ok","disposition":"abandoned","source":null,"result":"","read_at":"t"}'; do
    SP=$(facts "[$(holding sp "[$HF,$spent]" '{"return_path":"leg req1:deliver","pull_request":"","verified_head":""}')]" | report)
    printf '%s' "$SP" | jq -e '.holdings[0].next_code == "replace_leg" and ([.table[] | select(.session == "sp") | .kind] == ["Ongoing"])' >/dev/null \
      && ok "a leg spent early ($(printf '%s' "$spent" | jq -r '.source // .disposition')) is recoverable: replace the leg" \
      || bad "a leg spent early is recoverable" "$(printf '%s' "$SP" | jq -c '.holdings[0]')"
done
PROM='{"kind":"leg","status":"ok","disposition":"resolved","source":"promoted","result":"blocked","read_at":"t"}'
facts "[$(holding pm "[$HF,$PROM]" '{"return_path":"leg req1:deliver","pull_request":"","verified_head":""}')]" | report \
  | jq -e '.holdings[0].next_code == "wait"' >/dev/null && ok "a promoted result is the worker's report, not a leg spent early" || bad "a promoted result is not a leg spent early"
HM='{"kind":"host","status":"ok","state":"missed","reads":2,"read_at":"2026-09-27T09:58:00Z"}'
facts "[$(holding gone "[$HM,$(printf '%s' "$PROM" | jq -c '.source = "refused"')]" '{"return_path":"leg req1:deliver","pull_request":"","verified_head":""}')]" | report \
  | jq -e '.holdings[0].next_code == "read_again"' >/dev/null && ok "a spent leg whose worker wasn't found is read again, not replaced" || bad "a spent leg with no worker found"
LBAD='{"kind":"leg","status":"not_verified","reason":"request store not on this host"}'
out=$(facts "[$(holding a "[$P,$LBAD]")]" | report)
printf '%s' "$out" | jq -e '.holdings[0].leg == null and (.not_verified | any(.what == "a: leg" and .reason == "request store not on this host"))' >/dev/null \
  && ok "an unreadable leg is not verified" || bad "an unreadable leg is not verified" "$out"

echo "== deferrals =="
D='[{"row":{"deferral":"d1","reason":"r1","raised":"2026-09-20"},"disposed":false,"status":"ok"},{"row":{"deferral":"d2","reason":"r2","raised":"2026-09-21"},"disposed":true,"how":"filed #5","status":"ok"},{"row":{"deferral":"d3","reason":"r3","raised":"2026-09-22"},"status":"not_verified","reason":"issue read timed out"}]'
out=$(facts '[]' '[]' "$D" | report)
printf '%s' "$out" | jq -e '([.deferrals[].deferral] == ["d1"]) and (.not_verified | any(.what == "deferral d3" and .reason == "issue read timed out"))' >/dev/null \
  && ok "a deferral whose check failed is not verified, not disposed or undisposed" || bad "deferral disposal failures" "$out"

echo "== bound, raw output, identifiers =="
HS=""
for i in 0 1 2 3 4 5 6 7 8 9; do
    f="[$(pr OPEN "$LH"),$(board fails "$LH" "job $i"),$(host found),{\"kind\":\"inventory\",\"status\":\"ok\",\"taken\":true,\"items\":[{\"clone\":\"repo\",\"kind\":\"file\",\"path\":\"/home/u/ws/cfg+t$i-deadbeef/repo/x.go\"}],\"stdout\":\"RAW-GH-OUTPUT\"}]"
    HS="$HS${HS:+,}$(holding "t$i" "$f")"
done
out=$(facts "[$HS]" | render)
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
[ "$lines" -le 100 ] && ok "10 holdings render within 40 + 6 per holding ($lines lines)" || bad "10 holdings render within the bound" "$lines"
SES=$(jq -nc '[range(10) | {row: {action: "merge", target: "acme/widgets#\(.)"}, fact: {kind: "merge", verdict: "not_confirmed", reason: "file differs", status: "ok"}}]')
DES=$(jq -nc '[range(10) | {row: {deferral: "d\(.)", reason: "later", raised: "2026-09-20"}, disposed: false, status: "ok"}]')
lines=$(facts "[$HS]" "$SES" "$DES" | render | wc -l | tr -d ' ')
[ "$lines" -le 220 ] && ok "10 holdings, 10 side effects and 10 deferrals render within the bound ($lines lines)" || bad "30 items render within the bound" "$lines"
printf '%s' "$out" | grep -q 'RAW-GH-OUTPUT' && bad "raw read output never reaches the report" || ok "raw read output never reaches the report"
printf '%s' "$out" | grep -qE '/home/|deadbeef|cfg\+' && bad "no absolute path, session id or instance name reaches the report" "$(printf '%s' "$out" | grep -E '/home/|deadbeef|cfg\+')" \
  || ok "no absolute path, session id or instance name reaches the report"
printf '%s' "$out" | grep -q '(absolute path withheld)' && ok "an absolute inventory path is withheld" || bad "an absolute inventory path is withheld"

echo "== not verified, refused, nowhere else =="
U='[{"raw":"| a | b | c","reason":"too few cells"}]'
R=$(jq -nc --argjson h "$(holding outside '[]')" '$h + {refused: "pull request outside the scope repositories", facts: []}')
out=$(facts "[$R]" '[]' '[]' null "$U" | render)
printf '%s\n' "$out" | grep -q '```' && printf '%s\n' "$out" | grep -q '| a | b | c' \
  && ok "an unparseable row is fenced under Not verified" || bad "an unparseable row is fenced under Not verified" "$out"
printf '%s\n' "$out" | grep -q 'holding `outside`: refused: pull request outside' \
  && ok "a refused holding is reported, not re-checked" || bad "a refused holding is reported, not re-checked" "$out"
H=$(holding w1 "[$(host missed),{\"kind\":\"inventory\",\"status\":\"not_verified\",\"reason\":\"instance not found\"}]" '{"pull_request":"none yet"}')
out=$(facts "[$H]" | render)
printf '%s\n' "$out" | grep -q '`w1`: no pull request; worker not found on this read; inventory could not be taken' \
  && ok "a missing worker is not found on this read, with no inventory" || bad "a missing worker is not found on this read, with no inventory" "$out"
printf '%s\n' "$out" | grep -qiE '\b(gone|dead|lost)\b[^:]' && bad "no gone/dead/lost wording about the worker" "$(printf '%s\n' "$out" | grep -iE 'gone|dead')" \
  || ok "no gone/dead/lost wording about the worker"

echo "== review fixes =="
H=$(holding t1 '[{"kind":"pr","status":"not_verified","reason":"timeout"}]')
out=$(facts "[$H]" | report)
printf '%s' "$out" | jq -e '(.nowhere_else | length) == 0 and (.not_verified | any(.what == "t1: pr"))' >/dev/null \
  && ok "a pull request whose read failed is not reported as having none" || bad "a pull request whose read failed is not reported as having none" "$out"
H=$(holding t2 "[$(host ambiguous)]" '{"pull_request":"none yet"}')
facts "[$H]" | render | grep -q '`t2`: no pull request; worker ambiguous in the listing' \
  && ok "an ambiguous listing is worded as ambiguous" || bad "an ambiguous listing is worded as ambiguous"
SEF='[{"row":{"action":"merge","target":"acme/widgets#9"},"fact":{"kind":"merge","verdict":"not_confirmed","status":"not_verified","reason":"contents read timed out"}}]'
out=$(facts '[]' "$SEF" | report)
printf '%s' "$out" | jq -e '.side_effects[0].code == "not_verified" and .side_effects[0].grade == "not verified" and (.waiting | length) == 0' >/dev/null \
  && ok "a failed side-effect re-check keeps no success grade and waits on nobody" || bad "a failed side-effect re-check" "$out"
out=$(facts "$MIX" | report)
printf '%s' "$out" | jq -e '[.holdings[].next_code] == ["land","decide","wait"]' >/dev/null \
  && ok "every holding carries a next_code token" || bad "every holding carries a next_code token" "$(printf '%s' "$out" | jq -c '[.holdings[].next_code]')"
# A held holding (the record feature's `held` phase, 3891bf4): verified, with
# the merge withheld by the human's direction. It waits on the human, not on
# its worker, and it is neither executing nor stale.
HELD=$(holding th "[$(pr OPEN "$VH"),$(board holds "$VH")]" '{"phase":"held"}')
out=$(facts "[$HELD]" | report)
printf '%s' "$out" | jq -e '.holdings[0].phase == "held" and .holdings[0].next_code == "held" and ([.waiting[].topic] == ["th"]) and ([.not_verified[] | select(.what | test("phase"))] | length) == 0' >/dev/null \
  && ok "a held holding is verified and waits on the human, not on its worker" || bad "a held holding is verified and waits on the human" "$out"
facts "[$HELD]" | render | grep -q "| Ready to merge | unit th | \`th\` | \\[#1\\](https://github.com/acme/widgets/pull/1) | held; .*| verified; merge withheld by the human's direction, waiting on them" \
  && ok "the held line says the merge is withheld by the human's direction" || bad "the held line says the merge is withheld" "$(facts "[$HELD]" | render | grep th)"
HELDM=$(holding tm "[$(pr MERGED "$VH")]" '{"phase":"held"}')
facts "[$HELDM]" | report | jq -e '.holdings[0].next_code == "drop" and (.waiting | length) == 0' >/dev/null \
  && ok "a held holding whose pull request merged since is dropped, not waited on" || bad "a held holding whose pull request merged since is dropped"
HELDF=$(holding tf "[$(pr OPEN "$VH"),$(board fails "$VH" "job lint")]" '{"phase":"HELD"}')
facts "[$HELDF]" | report | jq -e '.holdings[0].next_code == "held"' >/dev/null \
  && ok "held is matched ignoring case, and the human's hold stands over the board" || bad "held is matched ignoring case"
echo "== the one table =="
# Holdings given out of order: the table puts ready-to-merge first (in the
# record's order), then what's blocked on the person, then what's ongoing,
# then the waiting-to-be-assigned row; a merged holding has no row.
T1=$(holding tw "[$(pr OPEN "$VH")]")
T2=$(holding tl1 "[$(pr OPEN "$VH"),$(board holds "$VH")]")
T3=$(holding td "[$(pr CLOSED "$VH")]")
T4=$(holding th2 "[$(pr OPEN "$VH")]" '{"phase":"held"}')
T5=$(holding tm2 "[$(pr MERGED "$VH")]")
T6=$(holding tl2 "[$(pr OPEN "$VH"),$(board holds "$VH")]")
tbl=$(facts "[$T1,$T2,$T3,$T4,$T5,$T6]" | render | sed -n '/^## Where things stand$/,/^$/p')
kinds=$(printf '%s\n' "$tbl" | awk -F' [|] ' '/^[|] [A-Z]/ && !/^[|] Kind/ {sub(/^[|] /, "", $1); print $1 ":" $3}' | tr '\n' ',')
[ "$kinds" = 'Ready to merge:`tl1`,Ready to merge:`th2`,Ready to merge:`tl2`,Ongoing:`tw`,Ongoing:`td`,Waiting to be assigned:N/A,' ] \
  && ok "one table: ready to merge in record order, then ongoing (a closed pull request included), waiting to be assigned" || bad "one table in the four kinds' order" "$kinds"
printf '%s\n' "$tbl" | grep -q '^| Kind | Unit | Session | PR | Status | Next or needs |$' && ok "the table's columns are Kind, Unit, Session, PR, Status, Next or needs" || bad "the table's columns" "$tbl"
printf '%s\n' "$tbl" | grep -q 'tm2' && bad "a merged holding has no row" "$tbl" || ok "a merged holding has no row"
[ "$(printf '%s\n' "$tbl" | grep -c '^[|]')" = 8 ] && ok "every row is a table row, header and separator included" || bad "every row is a table row" "$tbl"
NY=$(holding tn "[$(host found)]" '{"pull_request":"none yet"}')
facts "[$NY]" | render | grep -q '^| Ongoing | unit tn | `tn` | none yet | ' && ok "a holding with no pull request yet reads none yet, not N/A" || bad "a holding with no pull request yet reads none yet" "$(facts "[$NY]" | render | grep tn)"
printf '%s\n' "$tbl" | grep -q '^| Waiting to be assigned | N/A | N/A | N/A | ' && ok "N/A is kept for cells that cannot apply" || bad "N/A is kept for cells that cannot apply" "$tbl"
PIPE=$(holding tp "[$(pr OPEN "$VH")]" '{"unit":"a | b"}')
facts "[$PIPE]" | render | grep -q '| a \\| b |' && ok "a pipe inside a cell is escaped" || bad "a pipe inside a cell is escaped" "$(facts "[$PIPE]" | render | grep tp)"

# Blocked on you holds only escalated decision entries and reserved steps.
DEC='[{"decision":"4","question":"Ship without the arm64 build?","recommendation":"wait","reason":"the release requires it","target":"a person"},
      {"decision":"5","question":"Adopt the new schema?","recommendation":"adopt","reason":"r","target":"coordinator schema-rr"}]'
dt=$(facts "[$(holding tc "[$(pr CLOSED "$VH")]")]" | jq -c --argjson d "$DEC" '.decisions = $d' | render | sed -n '/^## Where things stand$/,/^$/p')
printf '%s\n' "$dt" | grep -qF '| Blocked on you | Ship without the arm64 build? | N/A | N/A | decide | recommended: wait, because the release requires it |' \
  && ok "an escalation to a person is a Blocked on you row with its recommendation and reason" || bad "an escalation to a person is a Blocked on you row" "$dt"
printf '%s\n' "$dt" | grep -qF '| Ongoing | Adopt the new schema? | N/A | N/A | with `schema-rr` for a decision |' \
  && ok "an escalation to a coordinator is Ongoing" || bad "an escalation to a coordinator is Ongoing" "$dt"
printf '%s\n' "$dt" | grep -q '^| Ongoing | .* | `tc` | .* | with me: re-dispatch or drop |' \
  && ok "a closed pull request's holding is Ongoing, with me: re-dispatch or drop" || bad "a closed pull request's holding is Ongoing" "$dt"
[ "$(printf '%s\n' "$dt" | grep -c '^| Blocked on you |')" = 1 ] \
  && ok "Blocked on you holds only the escalation to a person" || bad "Blocked on you holds only the escalation to a person" "$dt"

echo "== what the human reads =="
# A pull request is a link, a worker is inline code, and no commit hash
# appears anywhere in the rendered report.
LNK='[#7](https://github.com/acme/widgets/pull/7)'
UX1=$(holding ux-open "[$(pr OPEN "$LH"),$(board holds "$VH")]" "{\"pull_request\":\"$LNK\"}")
UX2=$(holding ux-new '[{"kind":"appeared","status":"ok","prs":[{"number":9,"url":"https://github.com/acme/widgets/pull/9","state":"OPEN"}],"read_at":"t"}]' '{"pull_request":"none yet"}')
UXSE='[{"row":{"action":"merge","target":"#7"},"fact":{"kind":"merge","verdict":"not_confirmed","status":"ok","reason":"src/a.go differs"}},{"row":{"action":"close","target":"acme/other#3"},"fact":{"kind":"close","verdict":"confirmed","status":"ok","reason":""}}]'
UXU="[{\"raw\":\"| u | /x | --auto | executing | dispatched | message | w | acme/widgets | feat/w | $VH | 2026-09-25 | #7 |\",\"reason\":\"Holdings: worker: not a dispatch topic\"}]"
uxout=$(facts "[$UX1,$UX2]" "$UXSE" '[]' null "$UXU" | jq -c '.scope.repo = "acme/widgets"' | render)
printf '%s\n' "$uxout" | grep -Eq '[0-9a-f]{40}' && bad "no commit hash appears in the rendered report" "$(printf '%s\n' "$uxout" | grep -E '[0-9a-f]{40}')" || ok "no commit hash appears in the rendered report"
bare=$(printf '%s\n' "$uxout" | grep -v '^  ' | grep -E '(^|[^[])#[0-9]+' || true)
[ -z "$bare" ] && ok "every pull request reference outside a quoted record row is a link" || bad "every pull request reference outside a quoted record row is a link" "$bare"
printf '%s\n' "$uxout" | grep -q -- '| Ongoing | unit ux-open | `ux-open` | \[#7\](https://github.com/acme/widgets/pull/7) |' && ok "a holding shows its worker as code and its pull request as a link" || bad "a holding shows its worker as code and its pull request as a link" "$uxout"
printf '%s\n' "$uxout" | grep -q 'now \[#9\](https://github.com/acme/widgets/pull/9)' && ok "an appeared pull request is a link" || bad "an appeared pull request is a link" "$uxout"
printf '%s\n' "$uxout" | grep -q -- '- merge \[#7\](https://github.com/acme/widgets/pull/7): not confirmed' && printf '%s\n' "$uxout" | grep -q -- '- close \[#3\](https://github.com/acme/other/issues/3): confirmed' \
  && ok "side-effect targets are links, in their own repository" || bad "side-effect targets are links, in their own repository" "$uxout"
printf '%s\n' "$uxout" | grep -q '`ux-open`: head moved past the verified head' && ok "a moved head is named without either hash" || bad "a moved head is named without either hash" "$uxout"
printf '%s\n' "$uxout" | grep -q 'merge not confirmed' && printf '%s\n' "$uxout" | grep -q -- '| Blocked on you | N/A | N/A | \[#7\](https://github.com/acme/widgets/pull/7) | merge not confirmed | confirm the merge: src/a.go differs |' \
  && ok "a waiting line names its pull request as a link" || bad "a waiting line names its pull request as a link" "$uxout"
printf '%s\n' "$uxout" | grep -q '<commit>' && ok "a hash inside a quoted record row is replaced" || bad "a hash inside a quoted record row is replaced" "$uxout"

F=$(facts "$MIX" "$SE")
a=$(printf '%s' "$F" | render)
b=$(printf '%s' "$F" | report | render)
[ "$a" = "$b" ] && ok "md renders a report document exactly as it renders the facts" || bad "md renders a report document exactly as it renders the facts"
printf '%s' "$F" | report | bash "$S" json >/dev/null 2>&1; rc=$?
[ "$rc" = 65 ] && ok "json refuses a report document" || bad "json refuses a report document" "rc=$rc"
HH=$(jq -nc --argjson h "$(holding t3 "[$(pr OPEN "$VH")]")" '$h + {source: "handoff"}')
facts "[$HH]" | render | grep -q 'row as written by the previous rotation' \
  && ok "a handoff row is labelled as the previous rotation's" || bad "a handoff row is labelled as the previous rotation's"
INV='{"kind":"inventory","status":"ok","taken":true,"items":[{"clone":"/home/u/ws/cfg+t-dddd/repo","kind":"commit","path":"abc"}]}'
out=$(facts "[$(holding t4 "[$INV]")]" | render)
printf '%s' "$out" | grep -qE '/home/|cfg\+t-dddd' && bad "an absolute clone path is withheld" "$out" || ok "an absolute clone path is withheld"
out=$(facts '[]' '[]' '[]' '"present"' '[]' discipline | render)
printf '%s\n' "$out" | grep -q 'reasoning is in reconcile/reasoning.md' && ok "present reasoning points at its key" || bad "present reasoning points at its key" "$out"

echo "== has a pull request, one test =="
H=$(holding t5 "[{\"kind\":\"pr\",\"status\":\"not_verified\",\"reason\":\"timeout\"},$(host found)]")
out=$(facts "[$H]" | report)
printf '%s' "$out" | jq -e '.holdings[0].state == "pull request not verified" and .holdings[0].grade.state == "not verified" and .holdings[0].next_code == "read_again" and (.nowhere_else | length) == 0' >/dev/null \
  && ok "a recorded pull request whose read failed is not verified in state, next and nowhere-else alike" || bad "failed pr read beside a found worker" "$out"
H=$(holding t6 "[$(host found),{\"kind\":\"appeared\",\"status\":\"not_verified\",\"reason\":\"list failed\"}]" '{"pull_request":"none yet"}')
out=$(facts "[$H]" | report)
printf '%s' "$out" | jq -e '.holdings[0].state == "pull request not verified" and (.nowhere_else | length) == 0' >/dev/null \
  && ok "a failed appeared read never becomes 'no pull request'" || bad "failed appeared read" "$out"
out=$(printf '{"schema":"coordinate-reconcile-report/v1","header":1}' | bash "$S" md 2>/dev/null); rc=$?
[ "$rc" = 65 ] && ok "md refuses a malformed report with 65" || bad "md refuses a malformed report with 65" "rc=$rc"

echo "== inventory not taken, missing facts =="
INV='{"kind":"inventory","status":"ok","taken":false,"reason":"instance directory unreadable"}'
out=$(facts "[$(holding t7 "[$INV]" '{"pull_request":"none yet"}')]")
printf '%s' "$out" | render | grep -q 'inventory could not be taken (instance directory unreadable)' \
  && ok "an inventory not taken carries its reason" || bad "an inventory not taken carries its reason" "$(printf '%s' "$out" | render)"
printf '%s' "$out" | report | jq -e '.not_verified | any(.what == "t7: inventory" and .reason == "instance directory unreadable")' >/dev/null \
  && ok "an inventory not taken is listed as not verified" || bad "an inventory not taken is listed as not verified"
facts '[]' '[{"row":{"action":"merge","target":"acme/widgets#3"}}]' | report | jq -e '.side_effects[0].code == "not_rechecked" and .side_effects[0].grade == "inferred"' >/dev/null \
  && ok "a side effect with no fact is not re-checked" || bad "a side effect with no fact is not re-checked"
check_next "a lowercase merged state still drops" "$(holding a "[$(pr merged "$VH")]")" "drop from holdings"

echo "== purity =="
EMPTYBIN=$(mktemp -d)
ln -s "$(command -v jq)" "$EMPTYBIN/jq"
got=$(facts "[$(holding a "[$(pr MERGED "$VH")]")]" | env -i PATH="$EMPTYBIN" "$(command -v bash)" "$S" json 2>&1)
rm -rf "$EMPTYBIN"
printf '%s' "$got" | jq -e '.schema == "coordinate-reconcile-report/v1"' >/dev/null 2>&1 \
  && ok "runs with a PATH holding only jq" || bad "runs with a PATH holding only jq" "$got"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
