# testlib.sh -- sourced by a suite that drives work-on.md through a covered
# exit or past deferral_approval. A covered exit now goes to decide_first,
# which lets the run leave only with an attempt for the arrival, and
# deferral_approval's answer_cited gate holds approved and rejected until a
# deciding attempt for the deferral cites an answer in effect.
#
#   df_setup <dir>     finds the shirabe with `question precedent`
#                      (SHIRABE_BIN, the tree's target/release/shirabe, PATH),
#                      links it into <dir>/df-bin and puts that first on PATH,
#                      so the gate finds it; returns 1, saying why, when none
#                      is found
#   cite_deferral <s>  takes session <s>, at deferral_approval, through
#                      needs_answer to decide_first, has a question answered by
#                      a manager session (<s>-mgr answering <s>-aux, which it
#                      dispatched), records a decided attempt for the arrival
#                      citing that answer, and resumes: <s> is back at
#                      deferral_approval, where approved and rejected pass
#                      answer_cited. Returns 1, saying why, otherwise.
#   decided_stop <s>   takes session <s>, at decide_first, to the exit it was
#                      about to take: records a decided attempt for the arrival
#                      and submits decided with decided_next: stop. Returns 1,
#                      saying why, when the attempt is not recorded or the tick
#                      fails.
#
# The suite's own HOME and koto state are used; nothing is written outside
# them but <dir>/df-bin and <dir>/df-*. No tool's stderr is discarded.
#
# bash 3.2 floor.

DF_DIR=""

df_setup() {
    local dir=$1 root s
    root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)
    s=""
    if [ -n "${SHIRABE_BIN:-}" ] && [ -x "$SHIRABE_BIN" ]; then
        s=$SHIRABE_BIN
    elif [ -x "$root/target/release/shirabe" ]; then
        s="$root/target/release/shirabe"
    else
        s=$(command -v shirabe) || s=""
    fi
    if [ -z "$s" ] || ! "$s" question precedent --help > /dev/null; then
        echo "decide-first testlib: no shirabe with \`question precedent\` (SHIRABE_BIN, target/release/shirabe or PATH)"
        return 1
    fi
    mkdir -p "$dir/df-bin" || return 1
    ln -sf "$s" "$dir/df-bin/shirabe" || return 1
    PATH="$dir/df-bin:$PATH"
    export PATH
    printf -- '---\nname: df-toy\nversion: "1.0"\ninitial_state: a\nstates:\n  a:\n    accepts:\n      done:\n        type: enum\n        values: [yes]\n        required: true\n    transitions:\n      - target: b\n        when:\n          done: yes\n  b:\n    terminal: true\n---\n\n## a\n\nWait.\n\n## b\n\nDone.\n' \
        > "$dir/df-toy.md"
    jq -n '{
        context: "One acceptance criterion cannot be met in this change.",
        problem: "Shipping without it leaves the issue open.",
        question: "Should the change ship with the criterion deferred?",
        options: [
            {label: "Defer", reason: "The rest of the change stands on its own."},
            {label: "Hold", reason: "The criterion is the point of the issue."}
        ],
        ground: "Deferring a criterion is the owner of the issue to decide.",
        waiting: ["the pull request"],
        label: "deferral"
    }' > "$dir/df-q.json" || return 1
    DF_DIR=$dir
}

cite_deferral() {
    local s=$1 out arrival a q id
    [ -n "$DF_DIR" ] || { echo "decide-first testlib: df_setup did not succeed"; return 1; }
    out=$(koto next "$s" --with-data '{"approval_decision":"needs_answer"}' --no-cleanup) \
        || { echo "decide-first testlib: needs_answer on $s: $out"; return 1; }
    arrival=$(koto context get "$s" decide_arrival) || { echo "decide-first testlib: $s has no decide_arrival"; return 1; }
    case "$arrival" in
        deferral_approval:*) ;;
        *) echo "decide-first testlib: $s arrived as [$arrival], not from deferral_approval"; return 1 ;;
    esac
    koto init "$s-mgr" --template "$DF_DIR/df-toy.md" > "$DF_DIR/df-init.out" \
        && koto init "$s-aux" --template "$DF_DIR/df-toy.md" --dispatched-by "$s-mgr" > "$DF_DIR/df-init.out" \
        || { echo "decide-first testlib: koto init: $(cat "$DF_DIR/df-init.out")"; return 1; }
    a=$(shirabe question attempt --in "$s-aux" --what "the deferral" --result undecided \
        --undo costly --undo-reason "a shipped deferral is the issue owner's to take back" | jq -r '.id // empty')
    [ -n "$a" ] || { echo "decide-first testlib: the undecided attempt in $s-aux was not recorded"; return 1; }
    q=$(shirabe question raise --in "$s-aux" --content "$DF_DIR/df-q.json" --attempt "$a" | jq -r '.identity // empty')
    [ -n "$q" ] || { echo "decide-first testlib: the question in $s-aux was not raised"; return 1; }
    id=$(koto decisions answer --in="$s-mgr" --text=Defer --by=session -- "$s-aux" "${q##*/}" | jq -r '.decision.id // .id // empty')
    [ -n "$id" ] || { echo "decide-first testlib: $s-mgr did not answer $q"; return 1; }
    a=$(shirabe question attempt --in "$s" --what "the deferral" --result decided --chosen Defer \
        --state "$arrival" --basis "$s-mgr:$id" | jq -r '.id // empty')
    [ -n "$a" ] || { echo "decide-first testlib: the decided attempt in $s was not recorded"; return 1; }
    out=$(koto next "$s" --with-data '{"decide_outcome":"decided","decided_next":"resume"}' --no-cleanup) \
        || { echo "decide-first testlib: resume on $s: $out"; return 1; }
    [ "$(koto status "$s" | jq -r '.current_state // empty')" = deferral_approval ] \
        || { echo "decide-first testlib: $s did not resume to deferral_approval: $out"; return 1; }
}

decided_stop() {
    local s=$1 arrival a out
    [ -n "$DF_DIR" ] || { echo "decide-first testlib: df_setup did not succeed"; return 1; }
    arrival=$(koto context get "$s" decide_arrival) \
        || { echo "decide-first testlib: $s has no decide_arrival (decide_first's default action did not record one)"; return 1; }
    a=$(shirabe question attempt --in "$s" --what "whether to stop" --result decided --chosen stop \
        --state "$arrival" | jq -r '.id // empty')
    [ -n "$a" ] || { echo "decide-first testlib: the decided attempt in $s was not recorded"; return 1; }
    out=$(koto next "$s" --with-data '{"decide_outcome":"decided","decided_next":"stop"}' --no-cleanup) \
        || { echo "decide-first testlib: stop on $s: $out"; return 1; }
}
