#!/usr/bin/env bash
# parked-state.sh -- spawn_and_await's parked_state gate: whether the batch
# has steps held on a question, and whether anything else can still move.
#
# Usage: parked-state.sh <run> <PLAN>
#
# A step is parked when parked/<step> in the run's context names an open
# question (park.sh writes it), or when its child stands at done_waiting and
# the question in the child's result is open, marked or not. A step waits on
# a parked one when its waits_on reaches a parked step, directly or through
# other steps. The PLAN's steps and their waits_on come from plan-to-tasks.sh,
# the same entries the directive submits as tasks.
#
# Exits:
#   0  nothing is parked. A run that never parked a step (no parked/ key, no
#      parked_ever, no child at done_waiting) exits here before reading the
#      PLAN or calling shirabe. A run that parked one and has since cleared
#      every key exits 0 only once every PLAN step has a child: after a
#      waiting run is rewound, the tasks are submitted again before the batch
#      can finish.
#   3  every step not at a success terminal is parked on an open question or
#      waits on a step that is, and no child failed outright: the run ends at
#      done_waiting.
#   4  a parked step's question is closed (answered or withdrawn) and the step
#      is not taken up yet: park.sh clear, or the child's rewind, comes next.
#      No edge matches, so the batch holds rather than failing.
#   1  anything else: a step still running or not yet started, a cleared run
#      whose tasks are not submitted again, or a child that failed outright
#      (any failure terminal other than done_waiting). With every child
#      complete and one failed, the batch routes to escalate as before, and
#      the reason also names the open questions.
#   2  koto, jq, shirabe or the PLAN could not be read; no edge is taken.
#
# Each open question the run holds is printed on stdout, one
# `question=<identity>` line each, for the reader of the gate's output.
set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 2
. "$SELF_DIR/park-lib.sh"

unreadable() {
    echo "parked-state: $*" >&2
    exit 2
}

RUN="${1:-}"
PLAN="${2:-}"
[ -n "$RUN" ] && [ "$#" -eq 2 ] || unreadable "usage: parked-state.sh <run> <PLAN>"
command -v koto > /dev/null || unreadable "koto is not on PATH"
command -v jq > /dev/null || unreadable "jq is not on PATH"

PARKED=$(pk_parked "$RUN") || unreadable "could not read the parked steps of $RUN"
EVER=$(pk_ctx "$RUN" parked_ever) || unreadable "could not read parked_ever"
CHILDREN=$(pk_children "$RUN") || unreadable "could not list the children of $RUN"
WAITING_CHILDREN=$(printf '%s\n' "$CHILDREN" | awk '$2 == "done_waiting" { print $1 }')

if [ -z "$PARKED" ] && [ -z "$EVER" ] && [ -z "$WAITING_CHILDREN" ]; then
    exit 0
fi

command -v shirabe > /dev/null || unreadable "shirabe is not on PATH"
[ -f "$PLAN" ] || unreadable "no PLAN at $PLAN"
TASKS=$(pk_tasks "$PLAN") || unreadable "plan-to-tasks.sh could not read $PLAN"
TASKS_JSON=$(printf '%s\n' "$TASKS" | jq -s -c '.') || unreadable "could not read the PLAN's tasks"

open_steps=""
closed_steps=""
open_questions=""
note() {
    case " $open_questions " in
        *" $1 "*) ;;
        *) open_questions="$open_questions $1" ;;
    esac
}
classify() {
    local step="$1" q="$2" h
    if [ -z "$q" ]; then
        closed_steps="$closed_steps $step"
        return 0
    fi
    h=$(pk_history "$q") || unreadable "koto decisions history $q failed"
    if printf '%s\n' "$h" | jq -e '.open == true' > /dev/null; then
        open_steps="$open_steps $step"
        note "$q"
    else
        closed_steps="$closed_steps $step"
    fi
}

while read -r step q; do
    [ -n "$step" ] || continue
    classify "$step" "$q"
done <<EOF
$PARKED
EOF
for step in $WAITING_CHILDREN; do
    case " $open_steps $closed_steps " in *" $step "*) continue ;; esac
    q=$(pk_child_question "$RUN.$step") || unreadable "could not read the result of $RUN.$step"
    classify "$step" "$q"
done

for q in $open_questions; do
    printf 'question=%s\n' "$q"
done

# A child at a failure terminal other than done_waiting failed outright.
failed=$(printf '%s\n' "$CHILDREN" | awk '$3 == "true" && $4 == "failure" && $2 != "done_waiting" { print $1 }')
[ -z "$failed" ] || exit 1

[ -z "$closed_steps" ] || exit 4

to_json() {
    printf '%s\n' "$@" | jq -R -s -c 'split("\n") | map(select(. != ""))'
}
OK_JSON=$(to_json $(printf '%s\n' "$CHILDREN" | awk '$3 == "true" && $4 == "success" { print $1 }'))
HAVE_JSON=$(to_json $(printf '%s\n' "$CHILDREN" | awk '{ print $1 }'))
OPEN_JSON=$(to_json $open_steps)

if [ -z "$open_steps" ]; then
    printf '%s\n' "$TASKS_JSON" | jq -e --argjson have "$HAVE_JSON" \
        'all(.[]; .name as $t | $have | index($t) != null)' > /dev/null && exit 0
    exit 1
fi

printf '%s\n' "$TASKS_JSON" | jq -e --argjson ok "$OK_JSON" --argjson p "$OPEN_JSON" '
    . as $tasks
    | (reduce $tasks[] as $t ({}; .[$t.name] = ($t.waits_on // []))) as $g
    | def close($s):
        ([$g | to_entries[] | select(.value | any(. as $w | $s | index($w) != null)) | .key] + $s | unique) as $n
        | if ($n | length) == ($s | length) then $s else close($n) end;
      close($p) as $held
    | all($tasks[]; .name as $t | ($ok | index($t)) != null or ($held | index($t)) != null)' > /dev/null && exit 3
exit 1
