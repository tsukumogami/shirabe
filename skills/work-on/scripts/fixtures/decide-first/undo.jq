# undo.jq -- the compiled work-on.md with the decide_first change taken out,
# for decide-first-routes_test.sh to compare with the template it was made
# from. $exits is exits.json beside it, the table of covered exits: one
# object per exit, whose `old` is the state the exit went to before (null for
# deferral_approval's needs_answer, which is new).
#
# What it undoes, and nothing else:
#   - the states decide_first and done_waiting;
#   - each edge into decide_first goes back to its old target, without the
#     decide_origin and decide_fresh assignments;
#   - entry's decide_resume gate, its exit_code 0 condition on the mode edges
#     and skip_if, and the edges that route on its other codes;
#   - deferral_approval's answer_cited gate and its conditions, the
#     needs_answer value and edge, and its directive, whose text names
#     needs_answer (the suite drops the earlier template's directive there
#     too).
# Anything else that differs from the earlier template is a change this step
# did not name, and the comparison reports it.

def drop_keys($ks): with_entries(select(.key as $k | $ks | index($k) | not));
def tidy: if (.context_assignments // {}) == {} then del(.context_assignments) else . end;

def old_target($s):
    if .target != "decide_first" then .
    else
        (to_entries | map(select(.key == "when")) | .[0].value) as $w
        | ([$exits[] | select(.origin == $s and ($w[.field] == .value))] | .[0].old) as $old
        | if $old == null then error("no covered exit in the table for \($s) \($w)")
          else .target = $old
               | .context_assignments |= ((. // {}) | drop_keys(["decide_origin", "decide_fresh"]))
               | tidy
          end
    end;

.states |= (
    del(.decide_first, .done_waiting)
    | .entry |= (
        del(.gates.decide_resume)
        | (if (.gates // {}) == {} then del(.gates) else . end)
        | .transitions |= (map(select((.when // {}) | (has("gates.decide_resume.exit_code") and .["gates.decide_resume.exit_code"] != 0) | not))
                           | map(.when |= del(.["gates.decide_resume.exit_code"])))
        | (if has("skip_if") then .skip_if |= del(.["gates.decide_resume.exit_code"]) else . end))
    | .deferral_approval |= (
        del(.gates.answer_cited, .directive)
        | (if (.gates // {}) == {} then del(.gates) else . end)
        | .accepts.approval_decision.values |= map(select(. != "needs_answer"))
        | .transitions |= (map(select(.when.approval_decision != "needs_answer"))
                           | map(.when |= del(.["gates.answer_cited.exit_code"]))))
    | with_entries(.key as $s | .value |= (
        if has("transitions") then .transitions |= map(old_target($s)) else . end))
)
