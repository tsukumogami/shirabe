#!/usr/bin/env bash
# coordinate-report_test.sh -- coordinate-report.sh prints the closing lines
# from the terminal result and drops every value outside its closed pattern,
# record= taking a session name beside the legacy GitHub URL; and
# --record-line prints the record line from the run's facts and Run rows and
# nothing else, exits 4 with no role row (stderr naming the no-role fix) and
# 65 when the record can't be read. The record-line cases run a copy of the
# script beside stand-ins for coord-log.sh and state-read.sh, so no koto runs.
# Usage: bash skills/coordinate/scripts/coordinate-report_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
S="$HERE/coordinate-report.sh"
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n%s\n' "$1" "${2-}"; }
case_() { local got; got=$(jq -nc "{is_terminal: true, result: {status: \"success\", payload: ($2)}}" | bash "$S"); [ "$got" = "$3" ] && ok "$1" || bad "$1" "want [$3] got [$got]"; }
U=https://github.com/acme/widgets/issues/7
case_ "a closed roadmap prints its record" "{outcome: \"closed\", scope: \"roadmap\", host: \"acme/widgets\", record: \"$U\"}" "outcome=closed
scope=roadmap
host=acme/widgets
record=$U"
case_ "a handed-over rotation" '{outcome: "handed-over", scope: "discipline", host: "acme/widgets", record: "https://github.com/acme/widgets/pull/9"}' "outcome=handed-over
scope=discipline
host=acme/widgets
record=https://github.com/acme/widgets/pull/9"
case_ "an unknown outcome is dropped" '{outcome: "merged everything!", scope: "roadmap"}' "scope=roadmap"
case_ "a value with a newline is dropped" '{outcome: "closed\noutcome=stopped", scope: "roadmap"}' "scope=roadmap"
case_ "a foreign record URL is dropped" '{outcome: "stopped", record: "https://evil.example/acme/widgets/issues/1"}' "outcome=stopped"
case_ "an empty record is dropped" '{outcome: "not-active", scope: "roadmap", record: ""}' "outcome=not-active
scope=roadmap"
case_ "a record named by its session name prints it" '{outcome: "closed", scope: "roadmap", host: "acme/widgets", record: "coordinate-roadmap-widgets-20261101T090000Z"}' "outcome=closed
scope=roadmap
host=acme/widgets
record=coordinate-roadmap-widgets-20261101T090000Z"
case_ "a record that is neither a session name nor a GitHub URL is dropped" '{outcome: "closed", record: "coordinate-x-20261101T090000Z; rm -rf"}' "outcome=closed"
echo '{}' | bash "$S" >/dev/null 2>&1; [ $? -eq 65 ] && ok "no result exits 65" || bad "no result exits 65"

echo "== the record line (docs/designs/DESIGN-coordinator-named-roles.md, Decision 3) =="
T=$(mktemp -d "${TMPDIR:-/tmp}/coordinate-report-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
cp "$S" "$HERE/reconcile-report.sh" "$T/"
# The stand-ins serve $T/facts and $T/run, failing with the code in
# $T/facts.rc or $T/run.rc, and log each call.
cat > "$T/coord-log.sh" <<'STUB'
#!/usr/bin/env bash
D=$(cd "$(dirname "$0")" && pwd)
echo "coord-log $*" >> "$D/log"
[ "$1" = run-facts ] || exit 64
rc=$(cat "$D/facts.rc" 2>/dev/null || echo 0); [ "$rc" = 0 ] || { echo "coord-log: no found record" >&2; exit "$rc"; }
cat "$D/facts"
STUB
cat > "$T/state-read.sh" <<'STUB'
#!/usr/bin/env bash
D=$(cd "$(dirname "$0")" && pwd)
echo "state-read $*" >> "$D/log"
rc=$(cat "$D/run.rc" 2>/dev/null || echo 0); [ "$rc" = 0 ] || { echo "state-read: the read failed" >&2; exit "$rc"; }
cat "$D/run"
STUB
RS="$T/coordinate-report.sh"
SESS=coordinate-roadmap-widgets-20261101T090000Z
RL_RE='^Record: session `[^`]+` on `[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+`(, address `[^`]+`)?\. Role: (manager|director)\.$'
runrow() { jq -nc --arg k "$1" --arg v "$2" '{key: $k, value: $v, set_by: "the human", set: "2026-11-01T09:00Z"}'; }
# rl <run rows json>: --record-line over those rows; OUT, ERR, RC.
rl() {
    printf '%s' '{"scope":"roadmap","name":"widgets","repo":"acme/widgets"}' > "$T/facts"
    printf '%s' "$1" > "$T/run"; rm -f "$T/facts.rc" "$T/run.rc"; : > "$T/log"
    OUT=$(bash "$RS" --session "$SESS" --record-line </dev/null 2>"$T/err"); RC=$?; ERR=$(cat "$T/err")
}
eqr() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want [$2] got [$3]"; }
rl "[$(runrow coordinator lane-widgets),$(runrow role manager),$(runrow cap 2)]"
eqr "a manager whose address differs from its session name: the line with the address clause" \
    "0 Record: session \`$SESS\` on \`acme/widgets\`, address \`lane-widgets\`. Role: manager." "$RC $OUT"
[[ $OUT =~ $RL_RE ]] && ok "  ... matching the record line's pattern" || bad "  ... matching the record line's pattern" "$OUT"
eqr "  ... one line and nothing else" 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
eqr "  ... read from the run's facts and its Run section" "coord-log run-facts --session $SESS|state-read --session $SESS --run" "$(tr '\n' '|' < "$T/log" | sed 's/|$//')"
rl "[$(runrow coordinator "$SESS"),$(runrow role director)]"
eqr "an address equal to the session name: no address clause" "0 Record: session \`$SESS\` on \`acme/widgets\`. Role: director." "$RC $OUT"
[[ $OUT =~ $RL_RE ]] && ok "  ... matching the record line's pattern" || bad "  ... matching the record line's pattern" "$OUT"
rl "[$(runrow role director)]"
eqr "no coordinator row: no address clause" "0 Record: session \`$SESS\` on \`acme/widgets\`. Role: director." "$RC $OUT"
rl "[$(runrow coordinator lane-widgets),$(runrow cap 2)]"
eqr "no role row exits 4 and prints nothing" "4 " "$RC $OUT"
grep -q 'no-role' <<<"$ERR" && grep -qF 'state-stored-set.sh --run role <manager|director>' <<<"$ERR" \
    && ok "  ... its stderr naming the no-role gap and its fix" || bad "  ... its stderr naming the no-role gap and its fix" "$ERR"
rl "[]"
eqr "a record with no Run section exits 4 too" "4 " "$RC $OUT"
rl "[$(runrow role lead)]"
eqr "a role row holding another word prints nothing, exit 65" "65 " "$RC $OUT"
rl "[$(runrow role manager)]"; echo 1 > "$T/facts.rc"
OUT=$(bash "$RS" --session "$SESS" --record-line </dev/null 2>/dev/null); eqr "a run with no found record can't be read: exit 65, nothing printed" "65 " "$? $OUT"
rm -f "$T/facts.rc"; echo 2 > "$T/run.rc"
OUT=$(bash "$RS" --session "$SESS" --record-line </dev/null 2>/dev/null); eqr "a Run read that fails: exit 65, nothing printed" "65 " "$? $OUT"
rm -f "$T/run.rc"; printf 'not json' > "$T/run"
OUT=$(bash "$RS" --session "$SESS" --record-line </dev/null 2>/dev/null); eqr "a Run read that isn't JSON: exit 65" "65 " "$? $OUT"
bash "$RS" --record-line </dev/null >/dev/null 2>&1; eqr "--record-line without --session is usage (64)" 64 $?
bash "$RS" --session "$SESS" --record-line "$T/run" >/dev/null 2>&1; eqr "  ... as is a FILE beside it" 64 $?
bash "$RS" --session 'a b' --record-line </dev/null >/dev/null 2>&1; eqr "  ... and a session that isn't a session name" 64 $?
echo; echo "coordinate-report: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
