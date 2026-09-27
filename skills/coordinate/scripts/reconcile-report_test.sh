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
    jq -nc --arg t "$1" --argjson f "$2" --argjson o "${3:-{\}}" --arg vh "$VH" '
      {row: ({unit: ("unit " + $t), entry_point: "/shirabe:deliver", mode: "--auto", phase: "",
              dispatch_status: "dispatched", return_path: "message", worker: $t,
              repo: "acme/widgets", branch: ("feat/" + $t), verified_head: $vh,
              dispatched: "2026-09-25", pull_request: "#1"} + $o),
       refused: null, facts: $f}'
}

pr()    { jq -nc --arg s "$1" --arg h "$2" --argjson d "${3:-false}" '{kind: "pr", status: "ok", state: $s, head: $h, draft: $d, read_at: "2026-09-27T09:59:00Z"}'; }
board() { jq -nc --arg v "$1" --arg at "$2" --arg d "${3:-}" '{kind: "board", status: "ok", at: $at, verdict: $v, detail: $d, read_at: "2026-09-27T09:59:10Z"}'; }
host()  { jq -nc --arg s "$1" '{kind: "host", status: "ok", state: $s, reads: 2, instance: "cfg+t-deadbeef", session_name: "t-deadbeef", read_at: "2026-09-27T09:58:00Z"}'; }

report() { bash "$S" json; }
render() { bash "$S" md; }

echo "== schema =="
grep -q 'coordinate-reconcile-facts/v1' "$S" && grep -q 'coordinate-reconcile-report/v1' "$S" \
  && grep -q 'verified_head, dispatched, pull_request' "$S" \
  && ok "the header documents both schemas and the row keys" \
  || bad "the header documents both schemas and the row keys"

got=$(echo '{"schema":"other"}' | bash "$S" json 2>/dev/null); rc=$?
[ "$rc" = 65 ] && ok "a non-facts document exits 65" || bad "a non-facts document exits 65" "rc=$rc"
bash "$S" 2>/dev/null </dev/null; rc=$?
[ "$rc" = 64 ] && ok "no subcommand exits 64" || bad "no subcommand exits 64" "rc=$rc"

echo "== sections =="
EMPTY=$(facts '[]' '[]' '[]' '"absent"' '[]' discipline)
out=$(echo "$EMPTY" | render)
order=$(printf '%s\n' "$out" | grep '^## ' | tr '\n' '|')
want='## Changed since then|## Holding|## Waiting on a person|## Exists nowhere else|## Side effects|## Undisposed deferrals|## Predecessor'"'"'s reasoning|## Not verified|'
[ "$order" = "$want" ] && ok "sections render in R16's order" || bad "sections render in R16's order" "$order"
nones=$(printf '%s\n' "$out" | grep -c '^None\.$')
[ "$nones" = 7 ] && ok "every empty section reads None." || bad "every empty section reads None." "count=$nones"
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
line=$(facts "[$H]" | render | grep '^- merged: pull request')
case "$line" in *"record said open, now merged (written $W"*) ok "the rendered change carries all four" ;; *) bad "the rendered change carries all four" "$line" ;; esac

H=$(holding moved "[$(pr OPEN "$LH")]")
out=$(facts "[$H]" | report)
printf '%s' "$out" | jq -e --arg vh "$VH" --arg lh "$LH" '.changes | any(.what == "head moved" and .recorded == $vh and .live == $lh)' >/dev/null \
  && ok "a moved head is a change with both shas" || bad "a moved head is a change with both shas" "$out"

H=$(holding parked "[$(pr OPEN "$VH" true)]")
facts "[$H]" | report | jq -e '.changes | any(.what == "draft")' >/dev/null \
  && ok "a parked holding back in draft is a change" || bad "a parked holding back in draft is a change"

echo "== next lines and waiting =="
nx() { facts "[$1]" | report | jq -r '.holdings[0].next'; }
check_next() { local got; got=$(nx "$2"); [ "$got" = "$3" ] && ok "$1" || bad "$1" "want '$3' got '$got'"; }
check_next "merged -> drop"              "$(holding a "[$(pr MERGED "$VH")]")" "drop from holdings"
check_next "closed -> decide"            "$(holding a "[$(pr CLOSED "$VH")]")" "decide: re-dispatch or drop"
check_next "failing board -> worker fixes CI" "$(holding a "[$(pr OPEN "$VH"),$(board fails "$VH" "build: no runner")]")" "worker fixes CI"
check_next "holding board at verified head -> ready to land" "$(holding a "[$(pr OPEN "$VH"),$(board holds "$VH")]")" "ready to land"
check_next "open otherwise -> wait on worker" "$(holding a "[$(pr OPEN "$LH"),$(board holds "$LH")]")" "wait on worker"
check_next "no PR, found -> wait on worker" "$(holding a "[$(host found)]" '{"pull_request":"none yet"}')" "wait on worker"
check_next "no PR, not found -> read again" "$(holding a "[$(host missed)]" '{"pull_request":"none yet"}')" "read again, then decide"

MIX="[$(holding ready "[$(pr OPEN "$VH"),$(board holds "$VH")]"),$(holding closed "[$(pr CLOSED "$VH")]"),$(holding busy "[$(pr OPEN "$LH")]")]"
SE='[{"row":{"action":"merge","target":"acme/widgets#7","verified_head":"'$VH'","attempted":"2026-09-26T09:00Z"},"fact":{"kind":"merge","verdict":"not_confirmed","reason":"file differs","status":"ok"}},{"row":{"action":"merge","target":"acme/widgets#8"},"fact":{"kind":"merge","verdict":"confirmed","status":"ok"}}]'
w=$(facts "$MIX" "$SE" | report | jq -c '[.waiting[] | .topic] | sort')
[ "$w" = '["acme/widgets#7","closed","ready"]' ] && ok "waiting lists ready-to-land, decide, and unconfirmed merges only" || bad "waiting lists ready-to-land, decide, and unconfirmed merges only" "$w"

echo "== grades =="
out=$(facts "$MIX" "$SE" '[{"row":{"deferral":"d1","reason":"r","raised":"2026-09-20"},"disposed":false}]' | report)
printf '%s' "$out" | jq -e '
  (.holdings | all(.grade.state == "measured" and .grade.board == "verified by reading" and .grade.phase == "inferred" and .grade.next == "inferred"))
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
got=$(ph "$(holding a '[{"kind":"files","status":"ok","outside_docs":true}]' '{"phase":"scoping"}')")
[ "$got" = "scoping ahead|true" ] && ok "a scoping holding changing paths outside docs/ is flagged" || bad "a scoping holding changing paths outside docs/ is flagged" "$got"
got=$(ph "$(holding a '[{"kind":"files","status":"ok","outside_docs":false}]' '{"phase":"scoping"}')")
[ "$got" = "scoping ahead|false" ] && ok "a scoping holding changing only docs/ is not flagged" || bad "a scoping holding changing only docs/ is not flagged" "$got"

echo "== bound, raw output, identifiers =="
HS=""
for i in 0 1 2 3 4 5 6 7 8 9; do
    f="[$(pr OPEN "$LH"),$(board fails "$LH" "job $i"),$(host found),{\"kind\":\"inventory\",\"status\":\"ok\",\"taken\":true,\"items\":[{\"clone\":\"repo\",\"kind\":\"file\",\"path\":\"/home/u/ws/cfg+t$i-deadbeef/repo/x.go\"}],\"stdout\":\"RAW-GH-OUTPUT\"}]"
    HS="$HS${HS:+,}$(holding "t$i" "$f")"
done
out=$(facts "[$HS]" | render)
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
[ "$lines" -le 100 ] && ok "10 holdings render within 40 + 6 per holding ($lines lines)" || bad "10 holdings render within the bound" "$lines"
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
printf '%s\n' "$out" | grep -q 'holding outside: refused: pull request outside' \
  && ok "a refused holding is reported, not re-checked" || bad "a refused holding is reported, not re-checked" "$out"
H=$(holding w1 "[$(host missed),{\"kind\":\"inventory\",\"status\":\"not_verified\",\"reason\":\"instance not found\"}]" '{"pull_request":"none yet"}')
out=$(facts "[$H]" | render)
printf '%s\n' "$out" | grep -q 'w1: no pull request; worker not found on this read; inventory could not be taken' \
  && ok "a missing worker is not found on this read, with no inventory" || bad "a missing worker is not found on this read, with no inventory" "$out"
printf '%s\n' "$out" | grep -qiE '\b(gone|dead|lost)\b[^:]' && bad "no gone/dead/lost wording about the worker" "$(printf '%s\n' "$out" | grep -iE 'gone|dead')" \
  || ok "no gone/dead/lost wording about the worker"

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
