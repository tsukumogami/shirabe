#!/usr/bin/env bash
# coordinate-report_test.sh -- coordinate-report.sh prints the closing lines
# from the terminal result and drops every value outside its closed pattern.
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
echo '{}' | bash "$S" >/dev/null 2>&1; [ $? -eq 65 ] && ok "no result exits 65" || bad "no result exits 65"
echo; echo "coordinate-report: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
