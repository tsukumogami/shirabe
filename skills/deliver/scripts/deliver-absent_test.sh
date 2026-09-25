#!/usr/bin/env bash
# deliver-absent_test.sh -- scope_absent's and execute_absent's default action
# against a real koto request store (under a private HOME).
#
# Cases: an open, unbound leg is resolved with exactly the fixed
# {outcome: error, step: deliver:child-absent} record (source explicit); a leg
# a root session bound in the meantime is left bound and open (koto refuses
# the resolve, the script reports moved-on and exits 0); an already-resolved
# leg keeps its result; an abandoned request is left as it is; a request that
# doesn't exist exits 1; usage errors make no koto call.
#
# Usage: bash skills/deliver/scripts/deliver-absent_test.sh
# Exit codes: 0 all pass (SKIP when koto or jq is absent); 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/deliver-absent.sh"

for bin in koto jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- no case ran"; exit 0; }
done
if ! koto init --help 2>/dev/null | grep -q -- '--koto-leg'; then
    echo "SKIP: this koto predates --koto-leg -- no case ran"
    exit 0
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/deliver-absent-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME" "$T/tpl" "$T/work"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

# A throwaway child named scope.md, so it can bind the scope leg.
cat >"$T/tpl/scope.md" <<'TPL'
---
name: scope
version: "1.0"
description: a stand-in child for deliver-absent_test.sh
initial_state: work
variables:
  TOPIC:
    required: true
  INTENT_FLAG:
    default: ""
states:
  work:
    accepts:
      finish:
        type: enum
        values: [go]
        required: true
    transitions:
      - target: done
        when:
          finish: go
  done:
    terminal: true
---
## work
Working.
## done
Done.
TPL

new_request() {
    koto request create --with-data '{"legs":[{"name":"scope","role":"scope","template":"scope.md","inputs":{"TOPIC":"t1"}},{"name":"execute","role":"execute","template":["execute.md","execute-coordinated.md"],"inputs":{}}]}' \
        --requested-by deliver-t1 --coordinator-of-record deliver-t1 | jq -r '.request_id'
}
leg() { koto request get "$1" | jq -c --arg l "$2" ".legs[\$l] | $3"; }

RC=0; OUT=""
run() { OUT=$(bash "$S" "$@" 2>"$T/err"); RC=$?; }

echo "== an open, unbound leg =="
REQ=$(new_request)
run --request "$REQ" --leg scope
eq "exit 0" 0 "$RC"
eq "prints absent=resolved" "absent=resolved" "$OUT"
eq "the leg is resolved" '"resolved"' "$(leg "$REQ" scope '.disposition')"
eq "source explicit" '"explicit"' "$(leg "$REQ" scope '.result_source')"
eq "exactly the fixed payload" '{"outcome":"error","step":"deliver:child-absent"}' "$(leg "$REQ" scope '.result.payload')"
eq "status failure" '"failure"' "$(leg "$REQ" scope '.result.status')"
eq "the other leg is untouched" '"open"' "$(leg "$REQ" execute '.disposition')"

run --request "$REQ" --leg execute
eq "the execute leg resolves the same way" '{"outcome":"error","step":"deliver:child-absent"}' "$(leg "$REQ" execute '.result.payload')"

echo "== a leg the child bound in the meantime =="
REQ=$(new_request)
(cd "$T/work" && koto init scope-t1 --template "$T/tpl/scope.md" --var TOPIC=t1 --var INTENT_FLAG=continue --koto-leg "$REQ:scope" >/dev/null 2>"$T/init.err") \
    || bad "the stand-in child attaches" "$(cat "$T/init.err")"
eq "precondition: the leg is bound" '"open"' "$(leg "$REQ" scope '.disposition')"
run --request "$REQ" --leg scope
eq "exit 0: the leg moved on" 0 "$RC"
eq "prints moved-on:bound" "absent=moved-on:bound" "$OUT"
eq "the leg is still open" '"open"' "$(leg "$REQ" scope '.disposition')"
eq "and still bound" "true" "$(leg "$REQ" scope '.bound_child != null')"
eq "no result was written" 'null' "$(leg "$REQ" scope '.result')"
(cd "$T/work" && koto next scope-t1 --with-data '{"finish":"go"}' --no-cleanup >/dev/null 2>&1)
eq "the child's own terminal result still promotes" '"promoted"' "$(leg "$REQ" scope '.result_source')"

echo "== a leg already resolved =="
REQ=$(new_request)
koto request resolve "$REQ" scope --with-data '{"status":"success","summary":"x","payload":{"outcome":"scoped"}}' >/dev/null
run --request "$REQ" --leg scope
eq "exit 0" 0 "$RC"
eq "prints moved-on:resolved" "absent=moved-on:resolved" "$OUT"
eq "the earlier result is kept" '{"outcome":"scoped"}' "$(leg "$REQ" scope '.result.payload')"

echo "== an abandoned request =="
REQ=$(new_request)
koto request abandon-request "$REQ" --rationale test >/dev/null
run --request "$REQ" --leg scope
eq "exit 0" 0 "$RC"
case "$OUT" in absent=moved-on:*) ok "prints moved-on" ;; *) bad "prints moved-on" "$OUT" ;; esac
eq "the leg stays abandoned" '"abandoned"' "$(leg "$REQ" scope '.disposition')"

echo "== failures and usage =="
run --request req-does-not-exist --leg scope
eq "a request that doesn't exist exits 1" 1 "$RC"

BIN="$T/bin"
mkdir -p "$BIN"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/koto.calls"\nexec koto "$@"\n' "$T" >"$BIN/koto-log"
chmod +x "$BIN/koto-log"
for args in "" "--request" "--request req-1" "--leg scope" "--request req-1 --leg other" "--request -x --leg scope" \
    "--request req-1 --leg scope --leg scope" "--request req-1 --leg scope extra"; do
    : >"$T/koto.calls"
    # shellcheck disable=SC2086
    KOTO_BIN="$BIN/koto-log" bash "$S" $args >/dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 64 ] && [ ! -s "$T/koto.calls" ]; then ok "usage error, no koto call: [$args]"; else bad "usage [$args]" "rc=$rc"; fi
done

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
