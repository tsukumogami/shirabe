# park-lib.sh -- the reads park.sh and parked-state.sh share. Sourced, never
# run. Each function prints on stdout and returns non-zero when koto could not
# answer; koto's and jq's own messages reach stderr unchanged.
#
# A parked step is a PLAN step held on the identity of an open question,
# recorded in the /execute run's context as parked/<step>, where <step> is the
# task name plan-to-tasks.sh gives it (`step-<N>` for a step plan) and the
# value is the question's identity, `<session id>/<decision id>`.

# pk_tasks <plan>: the PLAN's tasks as plan-to-tasks.sh emits them, one JSON
# object a line.
pk_tasks() {
    local self out
    self=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || return 2
    out=$(bash "$self/../../plan/scripts/plan-to-tasks.sh" "$1") || return 2
    printf '%s\n' "$out" | jq -c '.[]'
}

# pk_ctx <session> <key>: the value, empty when the key is absent; non-zero
# when koto could not say.
pk_ctx() {
    local rc=0 v
    koto context exists "$1" "$2" > /dev/null || rc=$?
    case "$rc" in
        0)
            # An edge clears a key by assigning the literal none.
            v=$(koto context get "$1" "$2") || return 2
            [ "$v" = none ] || printf '%s' "$v"
            ;;
        1) return 0 ;;
        *) return 2 ;;
    esac
}

# pk_parked <session>: `<step> <identity>` for every parked/<step> key.
pk_parked() {
    local keys names k v
    keys=$(koto context list "$1") || return 2
    # Read into a variable first: a jq that fails inside the for list would
    # leave the list empty and read as "nothing parked".
    names=$(printf '%s\n' "$keys" | jq -r '.[] | select(startswith("parked/"))') || return 2
    for k in $names; do
        v=$(koto context get "$1" "$k") || return 2
        printf '%s %s\n' "${k#parked/}" "$v"
    done
}

# pk_history <identity>: koto's history of the question.
pk_history() {
    koto decisions history -- "$1"
}

# pk_raw_answer <history>: `<session>:<id>` of whatever answer the closed
# question carries, empty when it was withdrawn without one.
pk_raw_answer() {
    printf '%s\n' "$1" | jq -r '.answer | select(. != null) | "\(.session):\(.id)"'
}

# pk_answer <run> <identity>: `<session>:<id>` of the answer in effect when
# it carries authority over the run, empty otherwise. The rule is /work-on's
# decide-first-gate.sh --answer (a verified person's answer, a session answer
# from the run's dispatcher linked before the raise, or a settle whose basis
# holds a verified person's answer; never one from the run's own lineage,
# and for a step's question never the run itself); it is called, not copied.
# Non-zero when the record can't be read.
pk_answer() {
    local self
    self=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || return 2
    bash "$self/../../work-on/scripts/decide-first-gate.sh" --answer "$1" "$2"
}

# pk_children <session>: `<task> <state> <terminal> <failure>` for each
# child koto lists, the task being the child's name after `<session>.`.
pk_children() {
    local list names name st
    list=$(koto workflows --children "$1") || return 2
    names=$(printf '%s\n' "$list" | jq -r '.[].name') || return 2
    for name in $names; do
        st=$(koto status "$name") || return 2
        printf '%s\n' "$st" | jq -r --arg t "${name#"$1".}" \
            '"\($t) \(.current_state) \(.is_terminal) \(.result.status // "none")"' || return 2
    done
}

# pk_child_question <child>: the question a child at done_waiting names in
# its result, empty when it names none.
pk_child_question() {
    local st
    st=$(koto status "$1") || return 2
    printf '%s\n' "$st" | jq -r '.result.payload.question // ""'
}

# pk_cites <session> <answer>: 0 when a decision recorded in the session names
# <answer> (`<session>:<id>`) in its basis, 1 when none does, 2 unreadable.
pk_cites() {
    local list
    list=$(koto decisions list "$1" --format v1) || return 2
    printf '%s\n' "$list" | jq -e --arg a "$2" \
        '[.decisions[]? | .decision.basis[]? | "\(.session):\(.id)"] | index($a) != null' > /dev/null && return 0
    return 1
}

# pk_open_questions <session>: each open question the run's steps are parked
# on, from parked/<step> keys and from children at done_waiting, once each,
# separated by a space.
pk_open_questions() {
    local parked children q h out="" step
    parked=$(pk_parked "$1") || return 2
    children=$(pk_children "$1") || return 2
    for q in $(printf '%s\n' "$parked" | awk 'NF == 2 { print $2 }'); do
        h=$(pk_history "$q") || return 2
        printf '%s\n' "$h" | jq -e '.open == true' > /dev/null || continue
        case " $out " in *" $q "*) ;; *) out="${out:+$out }$q" ;; esac
    done
    for step in $(printf '%s\n' "$children" | awk '$2 == "done_waiting" { print $1 }'); do
        q=$(pk_child_question "$1.$step") || return 2
        [ -n "$q" ] || continue
        h=$(pk_history "$q") || return 2
        printf '%s\n' "$h" | jq -e '.open == true' > /dev/null || continue
        case " $out " in *" $q "*) ;; *) out="${out:+$out }$q" ;; esac
    done
    printf '%s\n' "$out"
}
