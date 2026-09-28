#!/usr/bin/env bash
# model-lib.sh -- STAND-IN helpers for decisions-replay_engine_test.sh.
#
# The stand-in scripts beside this file keep a small model of one
# coordinator's Decisions section in "$DEC_ST/<session>.json" and follow the
# DESIGN's rules for it (docs/designs/DESIGN-coordinate-decisions.md, the mode
# table and the owed rules). They are not the real scripts: Issue 10 of the
# coordinate-decisions plan deletes this directory and runs the harness against
# record-decision.sh, decision-next.sh, decision-render.sh and
# report-questions.sh.
#
# The model:
#   {next, entries: [{id, round, question, options, state, source, verdict,
#     rec, reason, target, owed, redirect, evidence: [{src, text, withdrawal}],
#     outcome, decided_by}], current}
#
# Sourced; needs SESSION set and DEC_ST exported by the harness.

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MODEL="$DEC_ST/$SESSION.json"
[ -f "$MODEL" ] || printf '{"next":1,"entries":[],"current":null}\n' > "$MODEL"

# m <jq program> [jq args...]: read the model.
m() { jq -c "$@" "$MODEL"; }
# m_set <jq program> [jq args...]: change the model.
m_set() {
    jq -c "$@" "$MODEL" > "$MODEL.tmp" && mv "$MODEL.tmp" "$MODEL"
}
# seal <state> <token>: the real seal, so routing goes through real gates.
seal() { bash "$HERE/coord-log.sh" seal --session "$SESSION" --state "$1" --token "$2"; }
# target: the run's escalation target, from the run's REPORTS_TO variable.
target() {
    local rt
    rt=$(bash "$HERE/coord-log.sh" vars --session "$SESSION" | jq -r '.REPORTS_TO // ""')
    if [ -n "$rt" ]; then printf 'coordinator %s' "$rt"; else printf 'a person'; fi
}
# log_file: the session's koto log.
log_file() { printf '%s/koto-%s.state.jsonl' "$(koto session dir "$SESSION")" "$SESSION"; }
