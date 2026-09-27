#!/usr/bin/env bash
# progress-view_test.sh -- the progress table: four kinds of row in a fixed
# order (Ready to merge in merge order, Blocked on you, Ongoing, Waiting to be
# assigned in assignment order), a pull request as a clickable link, a session as inline
# code, and no commit hash.
# Usage: bash skills/coordinate/scripts/progress-view_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
V="$HERE/progress-view.sh"
F="$HERE/testdata/progress/pick.json"
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n%s\n' "$1" "${2-}"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/progress-view-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
kinds() { printf '%s\n' "$1" | tail -n +3 | awk -F' \\| ' '{print $1}' | sed 's/^| //' | tr '\n' ','; }
col() { printf '%s\n' "$1" | tail -n +3 | awk -F' \\| ' -v c="$2" '{print $c}' | tr '\n' ','; }

# A blocked session: plugin-cli, with a second ongoing one beside it.
jq '.holdings += [{worker: "plugin-docs", unit: "Feature 7: Guides", phase: "scoping-ahead", dispatch_status: "dispatched", parked: false, pull_request: "[#15](https://github.com/acme/widgets/pull/15)"}]' "$F" > "$T/pick.json"
OUT=$(bash "$V" --merge-order plugin-sandbox,plugin-manifest --blocked plugin-cli="a product call: which config format" "$T/pick.json" 2> "$T/err"); RC=$?
[ "$RC" = 0 ] && ok "the facts render" || bad "the facts render" "exit $RC: $(cat "$T/err")"
[ "$(printf '%s\n' "$OUT" | head -1)" = "| Kind | Unit | Session | PR | Status | Next or needs |" ] \
    && ok "the header names the six columns" || bad "the header names the six columns" "$OUT"
[ "$(kinds "$OUT")" = "Ready to merge,Ready to merge,Blocked on you,Ongoing,Waiting to be assigned,Waiting to be assigned," ] \
    && ok "the four kinds come in order: ready, blocked, ongoing, queued" || bad "the four kinds come in order" "$(kinds "$OUT")"
[ "$(col "$OUT" 3)" = '`plugin-sandbox`,`plugin-manifest`,`plugin-cli`,`plugin-docs`,N/A,N/A,' ] \
    && ok "ready rows follow the merge order, and a session is inline code" || bad "ready rows follow the merge order" "$(col "$OUT" 3)"
printf '%s\n' "$OUT" | grep -qF '| [#14](https://github.com/acme/widgets/pull/14) |' \
    && ok "a pull request is a clickable link" || bad "a pull request is a clickable link" "$OUT"
printf '%s\n' "$OUT" | grep -qF '| merge 1 of 2 |' && ok "a ready row says its merge position" || bad "a ready row says its merge position" "$OUT"
printf '%s\n' "$OUT" | grep -qF '| blocked | a product call: which config format |' \
    && ok "a blocked row says what it needs" || bad "a blocked row says what it needs" "$OUT"
printf '%s\n' "$OUT" | grep -qF '| `plugin-docs` | [#15](https://github.com/acme/widgets/pull/15) | scoping ahead |' \
    && ok "an ongoing row carries its link and status" || bad "an ongoing row carries its link and status" "$OUT"
[ "$(col "$OUT" 2)" = "Feature 4: Plugin sandbox,Feature 1: Plugin manifest,Feature 6: CLI,Feature 7: Guides,Feature 3: Plugin registry,Feature 2: Plugin loader," ] \
    && ok "the queue is unblocked first, then blocked, and done or held units are left out" || bad "the queue order" "$(col "$OUT" 2)"
printf '%s\n' "$OUT" | grep -qF '| Waiting to be assigned | Feature 2: Plugin loader | N/A | N/A | waits on feature 1 | assigned as the cap frees, 2 of 2 in line |' \
    && ok "a queued row reads N/A for session and PR, and its place in line" || bad "a queued row" "$OUT"
if printf '%s\n' "$OUT" | grep -qE '(^|[^0-9A-Za-z])[0-9a-f]{7,40}([^0-9A-Za-z]|$)'; then bad "no commit hash is shown" "$OUT"; else ok "no commit hash is shown"; fi
if printf '%s\n' "$OUT" | grep -qE '(^|[^[])#1[0-9]([^]]|$)'; then bad "no bare pull request number" "$OUT"; else ok "no bare pull request number"; fi

OUT=$(bash "$V" --merge-order plugin-sandbox,plugin-manifest --next plugin-cli="open its draft" --next "Feature 3=held for the 1.4 release" "$F")
printf '%s\n' "$OUT" | grep -qF '| `plugin-cli` | none yet | executing | open its draft |' && ok "--next sets a session's next step" || bad "--next for a session" "$OUT"
printf '%s\n' "$OUT" | grep -qF '| ready to assign | held for the 1.4 release |' && ok "--next sets a queued unit's next step" || bad "--next for a unit" "$OUT"
jq '.holdings[0].phase = "held" | .holdings = [.holdings[0]]' "$F" > "$T/one.json"
OUT=$(bash "$V" "$T/one.json")
printf '%s\n' "$OUT" | grep -qF '| verified; merge held by your direction | merge 1 of 1 |' \
    && ok "one ready row needs no merge order, and a held one says so" || bad "a single held ready row" "$OUT"

refused() { # refused <label> <stderr substring> <args...>
    local label=$1 want=$2 out rc; shift 2
    out=$(bash "$V" "$@" 2> "$T/err"); rc=$?
    if [ "$rc" = 65 ] && [ -z "$out" ] && grep -qF -- "$want" "$T/err"; then ok "$label"
    else bad "$label" "exit $rc, stdout [$out], stderr [$(cat "$T/err")]"; fi
}
refused "two ready without a merge order is refused" "--merge-order is required" "$F"
refused "a merge order missing a ready session is refused" "exactly once" --merge-order plugin-sandbox "$F"
refused "a merge order naming a session twice is refused" "exactly once" --merge-order plugin-sandbox,plugin-sandbox,plugin-manifest "$F"
refused "a merge order naming an ongoing session is refused" "exactly once" --merge-order plugin-sandbox,plugin-manifest,plugin-cli "$F"
refused "--blocked on a session with no holding is refused" "no holding" --merge-order plugin-sandbox,plugin-manifest --blocked nobody=x "$F"
refused "--blocked on a ready session is refused" "a ready session" --merge-order plugin-sandbox,plugin-manifest --blocked plugin-sandbox=x "$F"
jq '.holdings[2].pull_request = "#16"' "$F" > "$T/bare.json"
refused "a bare pull request number is refused, never shown" "plugin-cli: the pull request cell is not a link" --merge-order plugin-sandbox,plugin-manifest "$T/bare.json"
jq '.holdings[2].pull_request = "[#17](https://github.com/acme/widgets/pull/16)"' "$F" > "$T/mismatch.json"
refused "a link whose two numbers differ is refused" "not a link" --merge-order plugin-sandbox,plugin-manifest "$T/mismatch.json"
refused "a hash in a next step is refused" "a commit hash" --merge-order plugin-sandbox,plugin-manifest --next "plugin-cli=rebase onto 0123abcd" "$F"
jq '.units[2].title = "Registry at 0123456789abcdef0123456789abcdef01234567"' "$F" > "$T/hash.json"
refused "a hash in a unit's title is refused" "a commit hash" --merge-order plugin-sandbox,plugin-manifest "$T/hash.json"
echo '[]' > "$T/arr.json"
refused "input that isn't the pick facts is refused" "not the pick facts" "$T/arr.json"
bash "$V" --blocked nope "$F" > /dev/null 2>&1; [ $? = 64 ] && ok "a flag without = is a usage error" || bad "a flag without = is a usage error"

OUT=$(bash "$V" --merge-order plugin-sandbox,plugin-manifest --next "plugin-cli=a | b" "$F")
printf '%s\n' "$OUT" | grep -qF '| a \| b |' && ok "a pipe in a cell is escaped" || bad "a pipe in a cell is escaped" "$OUT"

echo
echo "progress-view: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
