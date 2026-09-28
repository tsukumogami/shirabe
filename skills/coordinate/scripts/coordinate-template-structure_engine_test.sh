#!/usr/bin/env bash
# coordinate-template-structure_engine_test.sh -- guarantees over coordinate.md,
# checked on the compiled template (koto template compile) and its source.
#
# Proves the check-state contract holds for every state with a default action:
# no accepts block (evidence can't skip the read), no polling or confirmation,
# every gate overridable: false, the only command gate is coord-verdict.sh over
# the state's own capture, and a context gate appears only as a decider input
# (context-exists). Also: the state set is the design's; no write script
# (record-open, record-write, record-holding, rotation-close, land-merge,
# merge-exec) appears in any default action or gate; no directive names
# merge-exec.sh; no check script calls `gh api` without --method GET (GraphQL
# queries aside) or sends a GraphQL mutation; nothing says the human merges;
# every reference file is named by a state; the two deciders are declared
# with their inputs gated.
#
# Needs koto (to compile) and jq; SKIPs without koto, which
# run-tests.sh --engine turns into a failure.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TPL="$HERE/../koto-templates/coordinate.md"
for b in koto jq; do command -v "$b" >/dev/null 2>&1 || { echo "SKIP: $b not on PATH"; exit 0; }; done
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/coord-structure.XXXXXX"); trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
J=$(koto template compile "$TPL" 2>/dev/null) || { echo "FAIL: coordinate.md does not compile"; exit 1; }

WANT="ask_up classify_report decision_apply deferral_dispose dispatch dispatch_check done done_handed_over done_not_active done_stopped failure land land_merge merge_confirm merged_facts pick pick_facts posture_ask predecessor_close predecessor_done predecessor_handed_over predecessor_handoff predecessor_step quiet_check rebrief reconcile reconcile_pass record record_conflict record_find record_open report_facts roadmap_blocked roadmap_close roadmap_close_step rotation_close rotation_done rotation_step start start_posture status_message surface teardown verified_confirm verify verify_board wait"
GOT=$(jq -r '.states | keys[]' "$J" | sort | tr '\n' ' ' | sed 's/ $//')
[ "$GOT" = "$WANT" ] && pass "the state set is the design's" || fail "the state set is the design's" "$(diff <(echo "$WANT" | tr ' ' '\n') <(echo "$GOT" | tr ' ' '\n'))"

BADCHECK=$(jq -r '.states | to_entries[] | select(.value.default_action != null) | .key as $s | .value as $v
  | [ (if $v.accepts != null then "\($s): has accepts" else empty end),
      (if ($v.default_action.polling // null) != null then "\($s): polls" else empty end),
      (if ($v.default_action.requires_confirmation // false) then "\($s): requires confirmation" else empty end),
      (($v.default_action.capture_stdout_as // "") as $cap
        | ($v.gates // {}) | to_entries[]
        | if .value.overridable != false then "\($s).\(.key): overridable"
          elif .value.type == "command" and ((.value.command | test("coord-verdict\\.sh\" --session \"\\{\\{SESSION_NAME\\}\\}\" --state " + $s + " --capture \"\\{\\{" + $cap + "\\}\\}\"")) | not) then "\($s).\(.key): not coord-verdict over its own capture"
          elif .value.type == "context-matches" then "\($s).\(.key): a context-matches gate"
          elif .value.type == "context-exists" and ((.value.key | test("^coord/(pick|report)\\.json$")) | not) then "\($s).\(.key): a context gate that is not a decider input"
          else empty end) ] | .[]' "$J")
[ -z "$BADCHECK" ] && pass "every check state keeps the contract" || fail "every check state keeps the contract" "$BADCHECK"

NONOVR=$(jq -r '.states | to_entries[] | .key as $s | (.value.gates // {}) | to_entries[] | select(.value.overridable != false) | "\($s).\(.key)"' "$J")
[ -z "$NONOVR" ] && pass "every gate in the template is overridable: false" || fail "every gate in the template is overridable: false" "$NONOVR"

WRITES=$(jq -r '.states | to_entries[] | .key as $s | [(.value.default_action.command // ""), ((.value.gates // {}) | to_entries[] | .value.command // "")] | .[] | select(test("record-open|record-write|record-holding|rotation-close|land-merge|merge-exec")) | $s' "$J")
[ -z "$WRITES" ] && pass "no write script runs as an action or a gate" || fail "no write script runs as an action or a gate" "$WRITES"

MEXEC=$(jq -r '.states | to_entries[] | select(((.value.directive // "") + (.value.details // "")) | test("merge-exec")) | .key' "$J")
[ -z "$MEXEC" ] && pass "no directive names merge-exec.sh" || fail "no directive names merge-exec.sh" "$MEXEC"

CHECKS=$(jq -r '.states[] | .default_action.command // empty' "$J" | sed -n 's#.*/skills/coordinate/scripts/\([a-z-]*\.sh\).*#\1#p' | sort -u)
for c in $CHECKS; do
    f="$HERE/$c"
    [ -f "$f" ] || { fail "check script $c exists"; continue; }
    # Every `gh api` call in a check script is a GET, or a GraphQL query.
    bad=$(grep -n 'gh api' "$f" | grep -v -- '--method GET' | grep -v 'gh api graphql' | grep -v '^[0-9]*:[[:space:]]*#' || true)
    [ -z "$bad" ] && pass "$c: every gh api call is a GET or a GraphQL query" || fail "$c: every gh api call is a GET or a GraphQL query" "$bad"
    grep -qi 'mutation' "$f" && fail "$c: sends no GraphQL mutation" || pass "$c: sends no GraphQL mutation"
done

grep -qiE 'the human merges|a person merges' "$TPL" "$HERE/../SKILL.md" && fail "nothing says the human merges" || pass "nothing says the human merges"
for r in loop.md brief-template.md verification-checklist.md record-template.md; do
    n=$(jq -r --arg r "$r" '[.states[] | select(((.directive // "") + (.details // "")) | contains("references/" + $r))] | length' "$J")
    [ "$n" -gt 0 ] && pass "a state names references/$r" || fail "a state names references/$r"
done
for d in pick.choice classify_report.classification; do
    st=${d%%.*}; fld=${d#*.}
    jq -e --arg s "$st" --arg f "$fld" '.states[$s].accepts[$f].decider != null' "$J" >/dev/null && pass "$d carries a decider" || fail "$d carries a decider"
    [ -f "$HERE/../koto-templates/coordinate.$d.decider.jsonl" ] && pass "$d has fixtures" || fail "$d has fixtures"
done
TERMS=$(jq -r '.states | to_entries[] | select(.value.terminal == true) | .key' "$J" | sort | tr '\n' ' ')
[ "$TERMS" = "done done_handed_over done_not_active done_stopped " ] && pass "the terminals are the four the report names" || fail "the terminals are the four the report names" "$TERMS"
RK=$(jq -r '[.states[] | select(.terminal == true) | (.result // {} | keys | sort | join(","))] | unique | join(";")' "$J")
[ "$RK" = "host,outcome,record,scope" ] && pass "every terminal's result carries outcome, scope, host, record" || fail "every terminal's result carries outcome, scope, host, record" "$RK"
echo; echo "coordinate template structure: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
