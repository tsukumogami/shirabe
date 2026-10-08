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
OUT=$(bash "$V" --merge-order plugin-sandbox,plugin-manifest --blocked plugin-cli="credential NPM_TOKEN" "$T/pick.json" 2> "$T/err"); RC=$?
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
printf '%s\n' "$OUT" | grep -qF '| blocked | credential: NPM_TOKEN |' \
    && ok "a blocked row says what it needs" || bad "a blocked row says what it needs" "$OUT"
printf '%s\n' "$OUT" | grep -qF '| `plugin-docs` | [#15](https://github.com/acme/widgets/pull/15) | scoping ahead |' \
    && ok "an ongoing row carries its link and status" || bad "an ongoing row carries its link and status" "$OUT"
# A merged row waiting for teardown: ongoing, merged, its worker torn down next.
jq '.holdings += [{worker: "plugin-done", unit: "Feature 8: Hooks", phase: "executing", dispatch_status: "dispatched", parked: false, merged: true, pull_request: ""}]' "$F" > "$T/pick-merged.json"
MOUT=$(bash "$V" --merge-order plugin-sandbox,plugin-manifest "$T/pick-merged.json" 2> "$T/err")
printf '%s\n' "$MOUT" | grep -qF '| Ongoing | Feature 8: Hooks | `plugin-done` | none yet | merged | tear down its worker |' \
    && ok "a merged row reads merged, its worker to tear down" || bad "a merged row reads merged, its worker to tear down" "$MOUT $(cat "$T/err")"
[ "$(col "$OUT" 2)" = "Feature 4: Plugin sandbox,Feature 1: Plugin manifest,Feature 6: CLI,Feature 7: Guides,Feature 3: Plugin registry,Feature 2: Plugin loader," ] \
    && ok "the queue is unblocked first, then blocked, and done or held units are left out" || bad "the queue order" "$(col "$OUT" 2)"
printf '%s\n' "$OUT" | grep -qF '| Waiting to be assigned | Feature 2: Plugin loader | N/A | N/A | waits on feature 1 | assigned as the cap frees, 2 of 2 in line |' \
    && ok "a queued row reads N/A for session and PR, and its place in line" || bad "a queued row" "$OUT"
if printf '%s\n' "$OUT" | grep -qE '(^|[^0-9A-Za-z])[0-9a-f]{7,40}([^0-9A-Za-z]|$)'; then bad "no commit hash is shown" "$OUT"; else ok "no commit hash is shown"; fi
if printf '%s\n' "$OUT" | grep -qE '(^|[^[])#1[0-9]([^]]|$)'; then bad "no bare pull request number" "$OUT"; else ok "no bare pull request number"; fi

# A unit parked on a decision, one whose scoping alone landed, and a holding
# scoping alone: their rows say so.
jq '(.units[] | select(.unit == "Feature 3")).awaiting = "4"
    | .units += [{unit: "Feature 9", title: "Definitions", status: "Not started", done: false, blocked: false, blocked_by: [], holding: null,
                  follow_up: {after: "acme/widgets#41", next: "/shirabe:execute docs/plans/PLAN-definitions.md"}}]
    | .holdings += [{worker: "plugin-spec", unit: "Feature 10: Spec", phase: "scoping", dispatch_status: "dispatched", parked: false, pull_request: ""}]' "$F" > "$T/pick-routes.json"
ROUT=$(bash "$V" --merge-order plugin-sandbox,plugin-manifest "$T/pick-routes.json" 2> "$T/err")
printf '%s\n' "$ROUT" | grep -qF '| Waiting to be assigned | Feature 3: Plugin registry | N/A | N/A | waits on decision 4 | parked until the decision is settled |' \
    && ok "a parked unit waits on its decision" || bad "a parked unit waits on its decision" "$ROUT $(cat "$T/err")"
printf '%s\n' "$ROUT" | grep -qF '| Waiting to be assigned | Feature 9: Definitions | N/A | N/A | scoping landed in acme/widgets#41 | its execution: /shirabe:execute docs/plans/PLAN-definitions.md |' \
    && ok "a follow-up names its scoping and its execution" || bad "a follow-up names its scoping and its execution" "$ROUT"
printf '%s\n' "$ROUT" | grep -qF '| Ongoing | Feature 10: Spec | `plugin-spec` | none yet | scoping |' \
    && ok "a holding scoping alone reads scoping" || bad "a holding scoping alone reads scoping" "$ROUT"

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
refused "--blocked on a session with no holding is refused" "no holding" --merge-order plugin-sandbox,plugin-manifest --blocked nobody="credential X" "$F"
refused "--blocked on a ready session is refused" "a ready session" --merge-order plugin-sandbox,plugin-manifest --blocked plugin-sandbox="credential X" "$F"
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

echo "== need kinds =="
MO=(--merge-order plugin-sandbox,plugin-manifest)
needcell() { bash "$V" "${MO[@]}" --blocked "plugin-cli=$1" "$F" 2> "$T/err" | grep -F '| Blocked on you |' | awk -F' \\| ' '{print $6}' | sed 's/ |$//'; }
eq_() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3] $(cat "$T/err")"; fi; }
eq_ "a credential is worded for its cell" "credential: NPM_TOKEN" "$(needcell 'credential NPM_TOKEN')"
eq_ "a reserved step is worded for its cell" "merge https://github.com/acme/widgets/pull/14, reserved for a person" \
    "$(needcell 'reserved-step merge https://github.com/acme/widgets/pull/14')"
eq_ "access is worded for its cell" "access to acme/secret" "$(needcell 'access acme/secret')"
for need in "decide whether to ship" "a product call: which config format" "credential" "credential two words" \
    "reserved-step deploy #12" "reserved-step merge somewhere" "access not-a-repo" "your call on the pin" \
    "credential decide-whether-to-ship" "access ../.."; do
    refused "--blocked refuses a need outside the kinds: [$need]" "refused" "${MO[@]}" --blocked "plugin-cli=$need" "$F"
done

echo "== --next against the phrasing list =="
while IFS= read -r p || [ -n "$p" ]; do
    [ -n "$p" ] || continue
    refused "--next refuses [$p]" "reads as a decision" "${MO[@]}" --next "plugin-cli=$p" "$F"
done < "$HERE/testdata/decision-phrasings/decision.txt"
while IFS= read -r p || [ -n "$p" ]; do
    [ -n "$p" ] || continue
    bash "$V" "${MO[@]}" --next "plugin-cli=$p" "$F" > /dev/null 2> "$T/err" && ok "--next accepts [$p]" || bad "--next accepts [$p]" "$(cat "$T/err")"
done < "$HERE/testdata/decision-phrasings/no-match.txt"

echo "== decision rows =="
ESC='{"decision": "4", "round": "1", "question": "Ship without the arm64 build?", "state": "escalated", "verdict": "escalate", "recommendation": "wait", "reason": "the release requires it", "target": "a person", "owed": ""}'
jq --argjson e "$ESC" '.decisions = [$e,
    ($e + {decision: "5", question: "Adopt the new schema?", target: "coordinator schema-rr"}),
    {decision: "6", round: "0", question: "Which helper?", state: "proposed", verdict: "", reason: "", recommendation: "", target: "", owed: ""},
    {decision: "7", round: "0", question: "Before or after the rebuild?", state: "coordinator-verdict", verdict: "hold", reason: "the lock benchmark", recommendation: "", target: "", owed: ""}]' \
    "$F" > "$T/dec.json"
OUT=$(bash "$V" "${MO[@]}" "$T/dec.json" 2> "$T/err")
printf '%s\n' "$OUT" | grep -qF '| Blocked on you | Ship without the arm64 build? | N/A | N/A | decide | recommended: wait, because the release requires it |' \
    && ok "an escalation to a person is a Blocked on you row with its recommendation and reason" || bad "an escalation to a person is a Blocked on you row" "$OUT $(cat "$T/err")"
printf '%s\n' "$OUT" | grep -qF '| Ongoing | Adopt the new schema? | N/A | N/A | with `schema-rr` for a decision | N/A |' \
    && ok "an escalation to a coordinator is Ongoing, asking the reader nothing" || bad "an escalation to a coordinator is Ongoing" "$OUT"
printf '%s\n' "$OUT" | grep -qF '| Ongoing | Which helper? | N/A | N/A | with me for a verdict | N/A |' \
    && ok "a proposed entry is with me for a verdict" || bad "a proposed entry is with me for a verdict" "$OUT"
printf '%s\n' "$OUT" | grep -qF '| Ongoing | Before or after the rebuild? | N/A | N/A | with me for a verdict, waiting on the lock benchmark | N/A |' \
    && ok "a held entry says what it waits on" || bad "a held entry says what it waits on" "$OUT"
[ "$(printf '%s\n' "$OUT" | grep -c '| Blocked on you |')" = 1 ] \
    && ok "only the escalation to a person asks the reader" || bad "only the escalation to a person asks the reader" "$OUT"
jq '.decisions[0].reason = " "' "$T/dec.json" > "$T/dec-noreason.json"
refused "a decision row without its reason is refused" "recommendation and reason" "${MO[@]}" "$T/dec-noreason.json"
jq '.decisions[0].recommendation = ""' "$T/dec.json" > "$T/dec-norec.json"
refused "a decision row without its recommendation is refused" "recommendation and reason" "${MO[@]}" "$T/dec-norec.json"

# Pauses: a line above the table, the paused rows saying so, the table unchanged.
jq '.pauses = [{standing: "s4", kind: "pause", on: "all", until: "time 2026-10-07T14:00Z", what: "x", owner: "the human", relayed_by: "the process owner", set: "2026-10-01T19:37Z", state: "in-force"},
               {standing: "s5", kind: "pause", on: "Feature 9", until: "lifted", what: "y", owner: "the human", relayed_by: "", set: "2026-10-02T13:10Z", state: "met"}]
    | .paused_all = "s4" | (.holdings[] | select(.worker == "plugin-sandbox" or .worker == "plugin-cli")).paused = "s4"
    | (.units[] | select(.unit == "Feature 2")).paused = "s4"' "$F" > "$T/pick-paused.json"
POUT=$(bash "$V" --merge-order plugin-sandbox,plugin-manifest "$T/pick-paused.json" 2> "$T/err"); RC=$?
[ "$RC" = 0 ] && ok "paused facts render" || bad "paused facts render" "exit $RC: $(cat "$T/err")"
[ "$(printf '%s\n' "$POUT" | head -1)" = "Paused: s4 on all, since 2026-10-01 19:37 UTC, until 2026-10-07 14:00 UTC (the human, relayed by the process owner); s5 on Feature 9, since 2026-10-02 13:10 UTC, until a person resumes it (the human), met, to end" ] \
    && ok "one line above the table names every pause, since when, until what and who" || bad "the pause line" "$(printf '%s\n' "$POUT" | head -1)"
[ "$(printf '%s\n' "$POUT" | sed -n 3p)" = "| Kind | Unit | Session | PR | Status | Next or needs |" ] \
    && ok "  ... and the table follows it with its six columns" || bad "  ... and the table follows it" "$POUT"
printf '%s\n' "$POUT" | grep -qF '| `plugin-sandbox` | [#14](https://github.com/acme/widgets/pull/14) | verified; held by pause s4 |' \
    && ok "a ready pull request a pause holds says so" || bad "a ready pull request a pause holds says so" "$POUT"
printf '%s\n' "$POUT" | grep -qF '| `plugin-cli` |' && printf '%s\n' "$POUT" | grep -F '| `plugin-cli` |' | grep -qF '| paused (s4) |' \
    && ok "an ongoing holding a pause holds reads paused" || bad "an ongoing holding a pause holds reads paused" "$POUT"
printf '%s\n' "$POUT" | grep -F '| Feature 2' | grep -qF '| held by pause s4 |' \
    && ok "a queued unit a pause holds says so in its next cell" || bad "a queued unit a pause holds says so" "$POUT"
NOUT=$(bash "$V" --merge-order plugin-sandbox,plugin-manifest "$F" 2> "$T/err")
[ "$(printf '%s\n' "$NOUT" | head -1)" = "| Kind | Unit | Session | PR | Status | Next or needs |" ] \
    && ok "with no pause the table starts at its header" || bad "with no pause the table starts at its header" "$NOUT"

echo
echo "progress-view: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
