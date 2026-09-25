#!/usr/bin/env bash
# deliver-open-request_test.sh -- open_request's default action against a real
# koto request store (under a private HOME).
#
# Cases: a first run creates one request with the scope and execute legs
# (role, template, inputs) under coordinator deliver-<topic> and prints only
# its id; a second run abandons the first and opens another; another topic's
# open /deliver request, and a request under an unrelated coordinator, are
# left open with their legs unchanged; a failing koto exits 1; usage errors
# make no koto call.
#
# Usage: bash skills/deliver/scripts/deliver-open-request_test.sh
# Exit codes: 0 all pass (SKIP when koto or jq is absent); 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/deliver-open-request.sh"

for bin in koto jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- no case ran"; exit 0; }
done
if ! koto request --help >/dev/null 2>&1; then
    echo "SKIP: this koto has no request verbs -- no case ran"
    exit 0
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/deliver-open-request-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

get() { koto request get "$1" | jq -c "$2"; }
create_for() { # create_for <coordinator> -- an open two-leg request
    koto request create --with-data '{"legs":[{"name":"scope","role":"scope","template":"scope.md","inputs":{}},{"name":"execute","role":"execute","template":"execute.md","inputs":{}}]}' \
        --requested-by "$1" --coordinator-of-record "$1" | jq -r '.request_id'
}

echo "== a first run =="
OTHER_TOPIC=$(create_for deliver-other)
UNRELATED=$(create_for scope-open-test)
OTHER_LEGS=$(get "$OTHER_TOPIC" '.legs')
UNRELATED_LEGS=$(get "$UNRELATED" '.legs')

OUT=$(bash "$S" --topic t1)
RC=$?
eq "exit 0" 0 "$RC"
eq "stdout is the id alone" 1 "$(printf '%s\n' "$OUT" | grep -c .)"
REQ1="$OUT"
if [[ $REQ1 =~ ^[a-z0-9_][a-z0-9_-]{0,63}$ ]]; then ok "the id matches koto's request-id grammar"; else bad "id grammar" "$REQ1"; fi
eq "coordinator of record" '"deliver-t1"' "$(get "$REQ1" '.coordinator_of_record')"
eq "requested by" '"deliver-t1"' "$(get "$REQ1" '.requested_by')"
eq "the request is open" '"open"' "$(get "$REQ1" '.request_state')"
eq "scope leg: role, template, inputs" '{"role":"scope","template":"scope.md","inputs":{"INTENT_FLAG":"continue","TOPIC":"t1"}}' \
    "$(get "$REQ1" '.legs.scope.declaration | {role, template, inputs}')"
eq "execute leg: role, both templates, inputs" '{"role":"execute","template":["execute.md","execute-coordinated.md"],"inputs":{"PLAN_SLUG":"t1"}}' \
    "$(get "$REQ1" '.legs.execute.declaration | {role, template, inputs}')"
eq "both legs open and unbound" '[["open",null],["open",null]]' "$(get "$REQ1" '[.legs.scope, .legs.execute | [.disposition, .bound_child]]')"

echo "== a second run supersedes the first =="
REQ2=$(bash "$S" --topic t1)
eq "exit 0" 0 "$?"
if [ "$REQ2" != "$REQ1" ] && [ -n "$REQ2" ]; then ok "a new request id"; else bad "a new request id" "$REQ1 / $REQ2"; fi
eq "the earlier request is closed" '"closed"' "$(get "$REQ1" '.request_state')"
eq "its legs are abandoned" '["abandoned","abandoned"]' "$(get "$REQ1" '[.legs.scope.disposition, .legs.execute.disposition]')"
eq "the new request is open" '"open"' "$(get "$REQ2" '.request_state')"
eq "exactly one open request for deliver-t1" 1 \
    "$(koto request list --coordinator-of-record deliver-t1 --state open | jq '.requests | length')"

echo "== other coordinators are untouched =="
eq "another topic's /deliver request is still open" '"open"' "$(get "$OTHER_TOPIC" '.request_state')"
eq "... with its legs unchanged" "$OTHER_LEGS" "$(get "$OTHER_TOPIC" '.legs')"
eq "an unrelated coordinator's request is still open" '"open"' "$(get "$UNRELATED" '.request_state')"
eq "... with its legs unchanged" "$UNRELATED_LEGS" "$(get "$UNRELATED" '.legs')"

echo "== failures =="
BIN="$T/bin"
mkdir -p "$BIN"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/koto.calls"\nexit 1\n' "$T" >"$BIN/koto-fail"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/koto.calls"\nexec koto "$@"\n' "$T" >"$BIN/koto-log"
chmod +x "$BIN/koto-fail" "$BIN/koto-log"

: >"$T/koto.calls"
KOTO_BIN="$BIN/koto-fail" bash "$S" --topic t1 >/dev/null 2>&1
eq "a failing koto exits 1" 1 "$?"

for args in "" "--topic" "--topic -x" "--topic T1" "--topic t1 --topic t1" "--topic t1 extra"; do
    : >"$T/koto.calls"
    # shellcheck disable=SC2086
    out=$(KOTO_BIN="$BIN/koto-log" bash "$S" $args 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 64 ] && [ -z "$out" ] && [ ! -s "$T/koto.calls" ]; then ok "usage error, no koto call: [$args]"; else bad "usage [$args]" "rc=$rc calls=$(cat "$T/koto.calls")"; fi
done

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
