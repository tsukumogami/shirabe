#!/usr/bin/env bash
# predecessor-handoff_test.sh -- predecessor-handoff.sh renders a previous
# rotation's handoff from its record body as it stands.
#
# Covers: `rendered <n>` sealed to predecessor_handoff; the file written to the
# session directory and its path to coord/predecessor_handoff_path; the
# predecessor's tables copied unchanged under the not-re-checked line with its
# Written time; the fixed reasoning sentence and no reasoning of its own; the
# header date being the title's end date; `unparseable` for a non-canonical
# body, another discipline's record and a title that isn't a rotation title;
# exit 2 when the run's find isn't a predecessor verdict or the read fails;
# the --out override; only reads; every token in koto's capture alphabet.
#
# Usage: bash skills/coordinate/scripts/predecessor-handoff_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
PH="$HERE/predecessor-handoff.sh"
CL="$HERE/coord-log.sh"
BR=coordinate/discipline-ci-health
TITLE="docs(coordinate): ci-health rotation 2026-09-15 to 2026-09-22"
tok_shape() { # tok_shape <name> <token>: koto's capture alphabet
    local re='^[A-Za-z0-9 :/_.@-]*$'
    if [[ ${2% sealed:*} =~ $re ]]; then ok "$1"; else bad "$1" "[$2]"; fi
}
DEFERRALS='[{"deferral":"flaky lint job","reason":"needs a runner","raised":"2026-09-16T10:00Z","disposition":""},
            {"deferral":"retry budget","reason":"wait on infra","raised":"2026-09-17T10:00Z","disposition":"carried 2026-09-20T09:00Z: still waiting"}]'
PRED_JSON=$(record_json discipline ci-health | jq -c --argjson d "$DEFERRALS" --argjson h "$(holding alpha)" '.deferrals = $d | .holdings = [$h]')
seed() { # seed [body] [title]
    db_init
    db '.branches["acme/widgets"][$br] = $s | .prs += [{repo: "acme/widgets", number: 22, title: $t, body: $b, state: "OPEN",
        isDraft: true, isCrossRepository: false, baseRefName: "main", headRefName: $br, headRefOid: $s, author: "alice", editor: null}]' \
        --arg br "$BR" --arg s "$SHA_HEAD" --arg t "${2:-$TITLE}" --arg b "${1:-$(render "$PRED_JSON" pr 2026-09-22T17:00:00Z)}"
}
N=0
session() { # session <find-token>: a run whose find read <find-token>, now at predecessor_handoff
    N=$((N + 1))
    S="coordinate-ci-health-20260926T08000${N}Z"
    log_new "$S" "$(discipline_vars ci-health)"
    log_to "$S" start_posture record_find 2026-09-26T08:01:00.000Z
    log_capture "$S" RECORD_FIND "$(bash "$CL" seal --session "$S" --state record_find --token "$1")" 2026-09-26T08:01:00.000Z
    log_to "$S" record_find predecessor_handoff 2026-09-26T08:01:00.000Z
}

echo "== rendered =="
seed; session "predecessor 22"; reset_calls
OUT=$(bash "$PH" --session "$S" 2>"$T/err"); rc=$?
eq "a canonical predecessor body renders" "0 rendered 22" "$rc ${OUT% sealed:*}"
tok_shape "rendered is in koto's capture alphabet" "$OUT"
bash "$CL" check --session "$S" --state predecessor_handoff --sealed "$OUT" && ok "the token is sealed to predecessor_handoff" || bad "the token is sealed to predecessor_handoff"
F="$KOTO_STORE/sessions/$S/predecessor-handoff.md"
eq "the path goes to coord/predecessor_handoff_path" "$F" "$(cat "$KOTO_STORE/context/$S/coord/predecessor_handoff_path")"
[ -f "$F" ] && ok "the file is in the session directory, outside any repository" || bad "the file is in the session directory" "$(ls "$KOTO_STORE/sessions/$S")"
grep -qx 'As written by the previous rotation at 2026-09-22T17:00:00Z; not re-checked.' "$F" && ok "the tables sit under the not-re-checked line with the body's Written time" || bad "the not-re-checked line" "$(cat "$F")"
eq "the reasoning is the fixed sentence" "The outgoing rotation's reasoning was not recorded." "$(tail -1 "$F")"
eq "the header date is the title's end date" "# ci-health handoff, 2026-09-22" "$(head -1 "$F")"
P=$(bash "$HERE/record-parse.sh" --format handoff "$F")
eq "the file is a canonical handoff and a predecessor copy" '{"written":"2026-09-22T17:00:00Z"}' "$(printf '%s' "$P" | jq -c .predecessor_copy)"
eq "no reasoning is written on the predecessor's behalf" null "$(printf '%s' "$P" | jq -c .reasoning)"
eq "the tables are the predecessor's, unchanged" "$(printf '%s' "$PRED_JSON" | jq -S -c '{holdings, deferrals, side_effects, reversals}')" \
    "$(printf '%s' "$P" | jq -S -c '{holdings, deferrals, side_effects, reversals}')"
eq "the rotation line carries the title's dates and the record" "2026-09-15 2026-09-22 acme/widgets https://github.com/acme/widgets/pull/22" \
    "$(printf '%s' "$P" | jq -r '.rotation | "\(.start) \(.end) \(.host_repo) \(.record_url)"')"
eq "it only reads GitHub" "pr view 22 --repo acme/widgets --json title,body,headRefOid" "$(calls)"

echo "== unparseable =="
seed "$(render "$PRED_JSON" pr 2026-09-22T17:00:00Z)
stray note"; session "predecessor 22"
OUT=$(bash "$PH" --session "$S" 2>"$T/err")
eq "a non-canonical body is unparseable" "unparseable 22" "${OUT% sealed:*}"
tok_shape "unparseable is in koto's capture alphabet" "$OUT"
[ ! -e "$KOTO_STORE/context/$S/coord/predecessor_handoff_path" ] && ok "no path is recorded for an unparseable body" || bad "no path is recorded for an unparseable body"
seed "$(render "$(record_json discipline other)" pr)"; session "predecessor 22"
eq "another discipline's record is unparseable" "unparseable 22" "$(bash "$PH" --session "$S" 2>/dev/null | sed 's/ sealed:.*//')"
seed "" "docs(coordinate): ci-health rotation 2026-09-15 to soon"; session "predecessor 22"
eq "a title that isn't a rotation title is unparseable" "unparseable 22" "$(bash "$PH" --session "$S" 2>/dev/null | sed 's/ sealed:.*//')"

echo "== refusals =="
seed; session "found 22"
bash "$PH" --session "$S" >/dev/null 2>&1; eq "a find that isn't a predecessor verdict exits 2" 2 $?
seed; session "predecessor 22"; db '.fail = [{match: "pr view", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
bash "$PH" --session "$S" >/dev/null 2>&1; eq "a failed read exits 2" 2 $?
bash "$PH" --scope discipline --name ci-health --repo "$REPO" --no-seal >/dev/null 2>&1; eq "overrides without --ref are a usage error" 64 $?
bash "$PH" --scope roadmap --name x --repo "$REPO" --ref 7 --out "$T/x" --no-seal >/dev/null 2>&1; eq "roadmap scope is a usage error" 64 $?

echo "== the override =="
seed
eq "--out renders without a session" "rendered 22" "$(bash "$PH" --scope discipline --name ci-health --repo "$REPO" --ref 22 --out "$T/h.md" --no-seal)"
cmp -s "$T/h.md" "$F" && ok "the same bytes as the session's render" || bad "the same bytes as the session's render" "$(diff "$T/h.md" "$F")"

done_tests predecessor-handoff
