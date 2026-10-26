#!/usr/bin/env bash
# render-result_engine_test.sh -- a message-path worker's link and result,
# link-dispatcher.sh then render-result.sh, against real koto in a scratch
# home.
#
# Proves: link-dispatcher.sh writes the dispatched-by link in the worker's own
# session and prints nothing; a link that fails once (koto behind a shim) is
# retried and recorded with no warning; one that fails twice prints
# warning=link-failed, records it in session/link-warning, writes no link and
# exits 0; a malformed or self-naming dispatcher, a missing --dispatched-by
# and a session that isn't here are refused before any link. render-result.sh
# then renders the result block: with a warning recorded it carries
# `warning=link-failed dispatched_by=<name>`, one line per dispatcher the key
# names, and without one it carries none; each --pr is a line; a review round
# review-round.sh recorded is one `review_round=` line of compact JSON that
# panel-evidence.sh --round reads as ok, and a stored round that isn't JSON
# is refused; a session that isn't here, a missing --session and a --pr that
# isn't an https URL are refused with nothing printed.
#
# Needs koto and jq; SKIPs (exit 0) without one, which run-tests.sh --engine
# turns into a failure.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
for b in koto jq; do command -v "$b" >/dev/null 2>&1 || { echo "SKIP: $b not on PATH"; exit 0; }; done
T=$(mktemp -d "${TMPDIR:-/tmp}/render-result-engine.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
trap 'case "$T" in */render-result-engine.*) rm -rf "$T" ;; esac' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }
LINK="$HERE/link-dispatcher.sh"
RESULT="$HERE/render-result.sh"

mkdir "$T/work" && cd "$T/work" || exit 1
printf -- '---\nname: plain\nversion: "1.0"\ndescription: One state.\ninitial_state: work\nstates:\n  work:\n    accepts:\n      status:\n        type: enum\n        values: [ok]\n        required: true\n    transitions:\n      - target: done\n        when:\n          status: ok\n  done:\n    terminal: true\n---\n\n## work\n\nSubmit `status: ok`.\n\n## done\n\nTerminal.\n' > plain.md
# koto behind a shim that logs each `session link` and fails the first
# LINK_FAILS of them.
REAL_KOTO=$(command -v koto)
cat > "$T/shim" <<EOF
#!/bin/sh
if [ "\$1 \$2" = "session link" ]; then
    printf '%s\n' "\$*" >> "$T/links"
    n=\$(wc -l < "$T/links")
    [ "\$n" -le "\${LINK_FAILS:-0}" ] && exit 1
fi
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/shim"
worker() { koto init "$1" --template plain.md > /dev/null 2>&1; }
link() { # link <fails> <args...>: link-dispatcher.sh behind the shim; output in $OUT, exit in $RC
    local f=$1; shift
    : > "$T/links"
    OUT=$(LINK_FAILS=$f KOTO_BIN="$T/shim" bash "$LINK" "$@" 2>"$T/err"); RC=$?
}
links() { koto context list "$1" --prefix koto/links/dispatched-by/ 2>/dev/null | jq -r '.[]' | tr '\n' ' ' | sed 's/ $//'; }
result() { OUT=$(bash "$RESULT" "$@" 2>"$T/err"); RC=$?; }

echo "== link-dispatcher.sh =="
worker task_w1
link 0 task_w1 --dispatched-by coordinate-roadmap-x-20261024T000000Z
eq "a link exits 0 and prints nothing" "0 " "$RC $OUT"
eq "  ... written in the worker's own session" "koto/links/dispatched-by/coordinate-roadmap-x-20261024T000000Z" "$(links task_w1)"
eq "  ... by one link call" 1 "$(wc -l < "$T/links" | tr -d ' ')"
worker task_w2
link 1 task_w2 --dispatched-by coord-a
eq "a link that fails once exits 0 and prints nothing" "0 " "$RC $OUT"
eq "  ... run twice" 2 "$(wc -l < "$T/links" | tr -d ' ')"
eq "  ... and recorded" "koto/links/dispatched-by/coord-a" "$(links task_w2)"
koto context exists task_w2 session/link-warning; eq "  ... with no warning key" 1 $?
worker task_w3
link 2 task_w3 --dispatched-by coord-a
eq "a link that fails twice exits 0 with the warning" "0 warning=link-failed dispatched_by=coord-a" "$RC $OUT"
eq "  ... recorded in the worker's own session" "warning=link-failed
dispatched_by=coord-a" "$(koto context get task_w3 session/link-warning)"
eq "  ... no link written" "" "$(links task_w3)"
for args in "task_w1 --dispatched-by ../x" "task_w1 --dispatched-by task_w1" "task_w1" "task_w1 --dispatched-by a --dispatched-by b" "--dispatched-by coord-a"; do
    # shellcheck disable=SC2086
    link 0 $args
    if [ "$RC" -eq 64 ] && [ ! -s "$T/links" ]; then pass "usage, no link: $args"; else fail "usage, no link: $args" "rc=$RC $(cat "$T/err")"; fi
done
link 0 task_nosuch --dispatched-by coord-a
if [ "$RC" -eq 2 ] && [ ! -s "$T/links" ]; then pass "a session that isn't here is refused before any link"; else fail "a session that isn't here is refused before any link" "rc=$RC $OUT $(cat "$T/err")"; fi

echo "== render-result.sh =="
result --session task_w1 --pr https://github.com/acme/widgets/pull/7
eq "a result with no warning recorded carries none" "=== RESULT ===
session=task_w1
pr=https://github.com/acme/widgets/pull/7
=== END RESULT ===" "$OUT"
eq "  ... exit 0" 0 "$RC"
result --session task_w3 --pr https://github.com/acme/widgets/pull/8 --pr https://github.com/acme/widgets/pull/9
eq "a result after a failed link carries the warning" "=== RESULT ===
session=task_w3
pr=https://github.com/acme/widgets/pull/8
pr=https://github.com/acme/widgets/pull/9
warning=link-failed dispatched_by=coord-a
=== END RESULT ===" "$OUT"
# A second dispatcher whose link failed too: one warning line each.
link 2 task_w3 --dispatched-by coord-b
result --session task_w3
eq "a warning for each dispatcher the key names" "=== RESULT ===
session=task_w3
warning=link-failed dispatched_by=coord-a
warning=link-failed dispatched_by=coord-b
=== END RESULT ===" "$OUT"
# The link works later: its line goes, and with the last one the warning.
link 0 task_w3 --dispatched-by coord-a
link 0 task_w3 --dispatched-by coord-b
result --session task_w3
eq "once every link has worked the result carries no warning" "=== RESULT ===
session=task_w3
=== END RESULT ===" "$OUT"
# The worker's review round, recorded with review-round.sh: one line, the
# round as compact JSON, after the pull requests and before any warning.
H=0123456789abcdef0123456789abcdef01234567
ROUND=$(jq -nc --arg h "$H" '{reviewed_head: $h, seats: [
    {seat: "architect", model: "sonnet", run: "agent-r1", verdict: "pass"},
    {seat: "maintainer", model: "sonnet", run: "agent-r2", verdict: "pass"},
    {seat: "pragmatic", model: "sonnet", run: "agent-r3", verdict: "pass"}]}')
printf '%s\n' "$ROUND" | jq . > "$T/round.json"
bash "$HERE/review-round.sh" record --session task_w1 "$T/round.json" > /dev/null 2>&1
eq "review-round.sh records the round in the worker's session" 0 $?
result --session task_w1 --pr https://github.com/acme/widgets/pull/7
eq "a result carries the recorded round on one line" "=== RESULT ===
session=task_w1
pr=https://github.com/acme/widgets/pull/7
review_round=$ROUND
=== END RESULT ===" "$OUT"
eq "  ... exit 0" 0 "$RC"
link 2 task_w1 --dispatched-by coord-c
result --session task_w1
eq "  ... before a warning line" "=== RESULT ===
session=task_w1
review_round=$ROUND
warning=link-failed dispatched_by=coord-c
=== END RESULT ===" "$OUT"
LINE=$(printf '%s\n' "$OUT" | sed -n 's/^review_round=//p')
printf '%s' "$LINE" > "$T/carried.json"
eq "  ... and the carried round is one the land step reads as ok" ok \
    "$(bash "$HERE/panel-evidence.sh" --round "$T/carried.json" | jq -r .status)"
worker task_w4
printf 'not json\n' > "$T/bad"
koto context add task_w4 review_round.json --from-file "$T/bad" > /dev/null 2>&1
result --session task_w4
eq "a round that isn't JSON: exit 2, nothing printed" "2 " "$RC $OUT"
result --session task_nosuch
eq "a session that isn't here: exit 2, nothing printed" "2 " "$RC $OUT"
result --pr https://github.com/acme/widgets/pull/7
eq "no --session: usage" "64 " "$RC $OUT"
result --session task_w1 --pr "acme/widgets#7"
eq "a --pr that isn't an https URL: usage" "64 " "$RC $OUT"

echo; echo "render-result engine: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
