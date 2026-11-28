#!/usr/bin/env bash
# deliver-execute-leg_test.sh -- /deliver's handover, lost-leg and waiting
# reads, against a koto stand-in (context get/add/exists from testdata/koto,
# `koto status` answered from a file per session, `koto decisions history`
# from a file per question) and the real scripts/plan-mode.sh over fixture
# PLANs.
#
# Covered:
#
#   handover  a coordinated PLAN prints `--coordination-pr <checked_pr>`, with
#             ` --store <value>` when --store is given; a single-pr, a
#             multi-pr, and a PLAN with no mode (or none at all) print `none`
#             and read no context; on a coordinated PLAN a checked_pr that is
#             absent or outside the PR-URL pattern exits 66 with nothing
#             printed, and a failed context read exits 66; the session from
#             KOTO_TICK_SESSION when koto set it
#   lost      a live execute session's state written as execute_state and
#             printed; a session koto removed at its terminal still reports
#             its state; koto's not-found answer is `absent`; garbage, a state
#             outside the pattern, and any other failure are `unreadable`; a
#             failed context add exits 66
#   waiting   a session at done_waiting with outcome waiting and a question
#             still open writes execute_waiting=yes and the open questions
#             (closed ones left out) and prints them; every question closed,
#             another state, no session, a question outside the identity
#             pattern, garbage from koto status and a failed history read
#             each write no (with no question key); an earlier yes is cleared
#             first, so a failed write leaves the key absent and exits 66
#   usage     a bad mode, topic, session or store, --store on lost or
#             waiting, and a repeated flag each exit 64 with no koto call
#
# Usage: bash skills/deliver/scripts/deliver-execute-leg_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs bash and jq.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/deliver-execute-leg.sh"
STUBS="$HERE/testdata"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/deliver-execute-leg-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
ktg_on_exit 'case "$T" in */deliver-execute-leg-test.*) rm -rf "$T" ;; esac'

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

BIN="$T/bin"
mkdir -p "$BIN"
cp "$STUBS/koto" "$BIN/koto-context"
chmod +x "$BIN/koto-context"
# The stand-in: `koto status <name>` from $STATUS_ANSWERS/<name> (first line
# the exit code, the rest stdout); a name with no file answers as koto does
# for one that never existed. Every other call is the context stand-in's.
cat >"$BIN/koto" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = status ]; then
    printf '%s\n' "$*" >>"$KOTO_STORE/calls"
    f="$STATUS_ANSWERS/${2:-}"
    if [ -f "$f" ]; then
        rc=$(sed -n 1p "$f")
        sed -n '2,$p' "$f"
        exit "$rc"
    fi
    printf '{"command":"status","error":"workflow '"'"'%s'"'"' not found"}\n' "${2:-}"
    exit 2
fi
if [ "${1:-} ${2:-}" = "decisions history" ]; then
    printf '%s\n' "$*" >>"$KOTO_STORE/calls"
    f="$HISTORY_ANSWERS/$(printf '%s' "${4:-}" | tr / _)"
    [ -f "$f" ] || { echo "no such question" >&2; exit 2; }
    cat "$f"
    exit 0
fi
if [ "${1:-} ${2:-}" = "context exists" ] && [ -n "${KOTO_FAIL_EXISTS:-}" ]; then
    printf '%s\n' "$*" >>"$KOTO_STORE/calls"
    exit 3
fi
exec "$(dirname "$0")/koto-context" "$@"
STUB
chmod +x "$BIN/koto"
export KOTO_STORE="$T/store"
export STATUS_ANSWERS="$T/status"
export HISTORY_ANSWERS="$T/history"
mkdir -p "$KOTO_STORE" "$STATUS_ANSWERS" "$HISTORY_ANSWERS"

TOPIC=t1
SESS=deliver-t1
URL=https://github.com/acme/widgets/pull/42
R="$T/repo"
mkdir -p "$R/docs/plans"

plan() { # plan <mode|none|absent>
    rm -f "$R/docs/plans/PLAN-$TOPIC.md"
    case "$1" in
        absent) ;;
        none) printf -- '---\nstatus: Active\n---\n# PLAN\n' >"$R/docs/plans/PLAN-$TOPIC.md" ;;
        *) printf -- '---\nstatus: Active\nexecution_mode: %s\n---\n# PLAN\n' "$1" >"$R/docs/plans/PLAN-$TOPIC.md" ;;
    esac
}
key() { cat "$KOTO_STORE/$SESS/$1" 2>/dev/null; }
seed() { mkdir -p "$KOTO_STORE/$SESS"; printf '%s' "$2" >"$KOTO_STORE/$SESS/$1"; }
reset() { rm -rf "${KOTO_STORE:?}/$SESS" "${STATUS_ANSWERS:?}"/* "${HISTORY_ANSWERS:?}"/*; mkdir -p "$KOTO_STORE/$SESS"; : >"$KOTO_STORE/calls"; }
history_answer() { printf '%s\n' "$2" >"$HISTORY_ANSWERS/$(printf '%s' "$1" | tr / _)"; }
status_answer() { printf '%s\n%s\n' "$2" "$3" >"$STATUS_ANSWERS/$1"; }

RC=0; OUT=""
run() { # run <args...> -- the script from inside the repository
    OUT=$(cd "$R" && PATH="$BIN:$PATH" KOTO_TICK_SESSION= bash "$S" "$@" 2>"$T/err")
    RC=$?
}

echo "== handover =="

reset; plan coordinated; seed checked_pr "$URL"
run handover --topic "$TOPIC" --session "$SESS" --store ""
eq "coordinated, no store: exit 0" 0 "$RC"
eq "coordinated, no store: --coordination-pr <checked_pr>" "--coordination-pr $URL" "$OUT"

reset; plan coordinated; seed checked_pr "$URL"
run handover --topic "$TOPIC" --session "$SESS" --store session
eq "coordinated, --store session: both flags" "--coordination-pr $URL --store session" "$OUT"
run handover --topic "$TOPIC" --session "$SESS" --store github
eq "coordinated, --store github: both flags" "--coordination-pr $URL --store github" "$OUT"
run handover --topic "$TOPIC" --session "$SESS"
eq "coordinated, --store left out: the PR alone" "--coordination-pr $URL" "$OUT"

for mode in single-pr multi-pr none absent; do
    reset; plan "$mode"; seed checked_pr "$URL"
    run handover --topic "$TOPIC" --session "$SESS" --store session
    eq "$mode PLAN: exit 0" 0 "$RC"
    eq "$mode PLAN: prints none" none "$OUT"
    if [ -s "$KOTO_STORE/calls" ]; then bad "$mode PLAN: no koto call" "$(cat "$KOTO_STORE/calls")"; else ok "$mode PLAN: no koto call"; fi
done

reset; plan coordinated
run handover --topic "$TOPIC" --session "$SESS" --store session
eq "coordinated, no checked_pr: exit 66" 66 "$RC"
eq "coordinated, no checked_pr: nothing printed" "" "$OUT"

reset; plan coordinated; seed checked_pr "https://github.com/acme/widgets/pull/42 --merge"
run handover --topic "$TOPIC" --session "$SESS"
eq "coordinated, a forged checked_pr: exit 66" 66 "$RC"
eq "coordinated, a forged checked_pr: nothing printed" "" "$OUT"

reset; plan coordinated; seed checked_pr "$URL"
OUT=$(cd "$R" && PATH="$BIN:$PATH" KOTO_TICK_SESSION= KOTO_FAIL_EXISTS=1 bash "$S" handover --topic "$TOPIC" --session "$SESS" 2>/dev/null)
eq "coordinated, a failed context read: exit 66" 66 "$?"
eq "coordinated, a failed context read: nothing printed" "" "$OUT"

reset; plan coordinated; seed checked_pr "$URL"
OUT=$(cd "$R" && PATH="$BIN:$PATH" KOTO_TICK_SESSION="$SESS" bash "$S" handover --topic "$TOPIC" --session other-session 2>/dev/null)
eq "the session comes from KOTO_TICK_SESSION when koto set it" "--coordination-pr $URL" "$OUT"

echo "== lost =="

reset
status_answer execute-t1 0 '{"name":"execute-t1","current_state":"coord_loop","is_terminal":false}'
run lost --topic "$TOPIC" --session "$SESS"
eq "a live execute session: exit 0" 0 "$RC"
eq "a live execute session: execute_state is its state" coord_loop "$(key execute_state)"
eq "a live execute session: printed" "execute_state=coord_loop" "$OUT"
if grep -qx "status execute-t1" "$KOTO_STORE/calls"; then ok "lost reads koto status execute-<topic>"; else bad "lost: status call" "$(cat "$KOTO_STORE/calls")"; fi
if grep -Eq '^(next|init|context (add|remove) execute-)' "$KOTO_STORE/calls"; then
    bad "lost writes nothing to the execute session" "$(cat "$KOTO_STORE/calls")"
else
    ok "lost writes nothing to the execute session"
fi

reset
status_answer execute-t1 0 '{"name":"execute-t1","current_state":"merged","is_terminal":true,"removed":true}'
run lost --topic "$TOPIC" --session "$SESS"
eq "a session koto removed at its terminal still reports its state" merged "$(key execute_state)"

reset
run lost --topic "$TOPIC" --session "$SESS"
eq "no execute session here: exit 0" 0 "$RC"
eq "no execute session here: absent" absent "$(key execute_state)"
eq "no execute session here: printed" "execute_state=absent" "$OUT"

reset
status_answer execute-t1 0 'not json'
run lost --topic "$TOPIC" --session "$SESS"
eq "garbage from koto status: unreadable" unreadable "$(key execute_state)"

reset
status_answer execute-t1 0 '{"current_state":"Coord Loop; rm -rf /"}'
run lost --topic "$TOPIC" --session "$SESS"
eq "a state outside the pattern: unreadable" unreadable "$(key execute_state)"

reset
status_answer execute-t1 1 '{"error":"something else broke"}'
run lost --topic "$TOPIC" --session "$SESS"
eq "another koto failure: unreadable" unreadable "$(key execute_state)"

reset
status_answer execute-t1 2 '{"error":"permission denied"}'
run lost --topic "$TOPIC" --session "$SESS"
eq "an exit 2 that is not koto's not-found: unreadable" unreadable "$(key execute_state)"

reset
OUT=$(cd "$R" && PATH="$BIN:$PATH" KOTO_TICK_SESSION= KOTO_FAIL_ADD=1 bash "$S" lost --topic "$TOPIC" --session "$SESS" 2>/dev/null)
eq "a failed context add: exit 66" 66 "$?"

echo "== waiting =="

Q1=q1-aaaa/000000000001
Q2=q2-bbbb/000000000002
waiting_status() { status_answer execute-t1 0 "{\"name\":\"execute-t1\",\"current_state\":\"$1\",\"is_terminal\":true,\"result\":{\"status\":\"failure\",\"payload\":{\"outcome\":\"waiting\",\"question\":\"$2\"}}}"; }

reset
waiting_status done_waiting "$Q1 $Q2"
history_answer "$Q1" '{"open":true}'
history_answer "$Q2" '{"open":false}'
run waiting --topic "$TOPIC" --session "$SESS"
eq "a question still open: exit 0" 0 "$RC"
eq "a question still open: execute_waiting is yes" yes "$(key execute_waiting)"
eq "a question still open: only the open ones are written" "$Q1" "$(key question)"
eq "a question still open: printed" "execute_waiting=yes
question=$Q1" "$OUT"
if grep -Eq '^(next|init|context (add|remove) execute-)' "$KOTO_STORE/calls"; then
    bad "waiting writes nothing to the execute session" "$(cat "$KOTO_STORE/calls")"
else
    ok "waiting writes nothing to the execute session"
fi

reset
waiting_status done_waiting "$Q1"
history_answer "$Q1" '{"open":false}'
run waiting --topic "$TOPIC" --session "$SESS"
eq "every question closed: no" no "$(key execute_waiting)"
eq "every question closed: no question key" "" "$(key question)"

reset
status_answer execute-t1 0 '{"name":"execute-t1","current_state":"spawn_and_await","is_terminal":false}'
run waiting --topic "$TOPIC" --session "$SESS"
eq "a session at another state: no" no "$(key execute_waiting)"
if grep -q "^decisions history" "$KOTO_STORE/calls"; then bad "another state: no history read" "$(cat "$KOTO_STORE/calls")"; else ok "another state: no history read"; fi

reset
run waiting --topic "$TOPIC" --session "$SESS"
eq "no execute session here: no" no "$(key execute_waiting)"

reset
waiting_status done_waiting "$Q1 not-an-id"
history_answer "$Q1" '{"open":true}'
run waiting --topic "$TOPIC" --session "$SESS"
eq "a question outside the identity pattern: no" no "$(key execute_waiting)"
eq "a question outside the identity pattern: no question key" "" "$(key question)"

reset
status_answer execute-t1 0 'not json'
run waiting --topic "$TOPIC" --session "$SESS"
eq "garbage from koto status: no" no "$(key execute_waiting)"

reset
waiting_status done_waiting "$Q1"
run waiting --topic "$TOPIC" --session "$SESS"
eq "a failed history read: no" no "$(key execute_waiting)"

reset
seed execute_waiting yes
run waiting --topic "$TOPIC" --session "$SESS"
eq "an earlier yes is replaced" no "$(key execute_waiting)"

reset
seed execute_waiting yes
OUT=$(cd "$R" && PATH="$BIN:$PATH" KOTO_TICK_SESSION= KOTO_FAIL_ADD=1 bash "$S" waiting --topic "$TOPIC" --session "$SESS" 2>"$T/err")
eq "a failed context add: exit 66" 66 "$?"
eq "a failed context add leaves execute_waiting absent, not the earlier yes" "" "$(key execute_waiting)"

echo "== usage =="
plan coordinated
for args in "bogus --topic t1 --session s" "handover --session s" "handover --topic -x --session s" \
    "handover --topic t1 --session bad/name" "handover --topic t1 --session s --store bogus" \
    "lost --topic t1 --session s --store session" "waiting --topic t1 --session s --store session" \
    "handover --topic t1 --topic t1 --session s" \
    "lost --topic t1 --extra x"; do
    : >"$KOTO_STORE/calls"
    # shellcheck disable=SC2086
    (cd "$R" && PATH="$BIN:$PATH" KOTO_TICK_SESSION= bash "$S" $args >/dev/null 2>&1)
    rc=$?
    if [ "$rc" -eq 64 ] && [ ! -s "$KOTO_STORE/calls" ]; then ok "usage error, no koto call: $args"; else bad "usage: $args" "rc=$rc calls=$(cat "$KOTO_STORE/calls")"; fi
done

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
