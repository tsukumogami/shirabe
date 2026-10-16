# panel-round-testlib.sh -- for the work-on suites that record panel rounds
# through panel-scope.sh --record. Sourced, never run.
#
#   panel_round_runs <session> <panel> <round-file>
#       gives every entry of the round file that names a seat and no run the
#       run its decision in <panel>_scope.json names (panel-scope.sh --plan
#       mints one per spawned seat), or, when the scope names none, a fresh
#       test run id. --record refuses an entry without a run, and one whose run
#       isn't the one its decision minted, so a suite that only wants a round
#       recorded calls this before --record. Reads the scope through `koto
#       context get`, so it works against real koto and the suites' stand-ins.
#
# Needs jq. Written for the bash 3.2 floor.

PANEL_ROUND_SEQ=0

panel_round_runs() {
    local session=$1 panel=$2 file=$3 scope
    scope=$(koto context get "$session" "${panel}_scope.json" 2>/dev/null) || scope=""
    printf '%s' "$scope" | jq -e 'type == "object"' >/dev/null 2>&1 || scope='{}'
    PANEL_ROUND_SEQ=$((PANEL_ROUND_SEQ + 1))
    jq --argjson s "$scope" --arg n "$$-$PANEL_ROUND_SEQ" '
        map(. as $e
            | if type == "object" and has("seat") and (has("run") | not) then
                .run = ([($s.decisions // [])[] | select(.seat == $e.seat) | .run // empty][0]
                        // ("test-" + $n + "-" + $e.seat))
              else . end)' "$file" > "$file.runs" && mv "$file.runs" "$file"
}
