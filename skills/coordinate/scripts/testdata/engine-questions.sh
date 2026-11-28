# engine-questions.sh -- questions in koto for the suites that drive the
# decision states through real koto (coordinate-engine-lib.sh's suites and
# decisions-replay_engine_test.sh): the branch's shirabe for `shirabe
# question`, a session's undecided attempt, a session's own decision question,
# and an owner's answer from a recorded harness session. Not shipped
# behaviour.
#
# Sourced after scripts/lib/koto-test-guard.sh and testdata/test-lib.sh, with
# REPO_ROOT (the repository) and T (the suite's scratch directory) set.
#
# shirabe: SHIRABE_BIN when it is executable (scripts/check-skill.sh exports
# the tree's build), else the tree's target/release/shirabe; it is exported as
# SHIRABE_BIN, empty when there is neither. The scripts under test run plain
# `shirabe`, which these suites put on PATH as testdata/board/stand-in-shirabe;
# that stand-in hands every `shirabe question ...` call to SHIRABE_BIN and,
# without one, fails it with exit 9 naming what is missing. q_have says
# whether one is at hand.
#
# The suites stand in for an attended session: a run mode inherited from the
# session running them would refuse the question tool's route and every
# owner's answer, so it is dropped here.
#
# An owner's answer comes from a recorded harness session, never a live
# prompt, the way scripts/question-commands_test.sh records one: a record
# built from scripts/fixtures/question-commands/accepted.jsonl with the
# rendered question in it, in a folder of its own under .claude/projects/ in
# the account's home as the user database gives it (koto reads it there, not
# under the suite's HOME), removed at exit.
#
# Every helper returns non-zero on a failed step, with the step's stderr in
# $T/q.err.

unset KOTO_RUN_MODE CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CONFIG_DIR

if [ -z "${SHIRABE_BIN:-}" ] || [ ! -x "${SHIRABE_BIN:-}" ]; then
    SHIRABE_BIN=
    [ -x "$REPO_ROOT/target/release/shirabe" ] && SHIRABE_BIN="$REPO_ROOT/target/release/shirabe"
fi
export SHIRABE_BIN

Q_FIXTURE="$REPO_ROOT/scripts/fixtures/question-commands/accepted.jsonl"
Q_RECORDS=

# q_have: a shirabe with the question ladder's subcommands is at hand.
q_have() {
    [ -n "$SHIRABE_BIN" ] && "$SHIRABE_BIN" question pass-up --help > /dev/null 2> "$T/q.err"
}

# q_session <dir> <name> [koto init flags...]: a session of a two-state
# template started in <dir>, for a question's raiser or for the session an
# owner's answer is given in.
q_session() {
    local d=$1 n=$2
    shift 2
    [ -f "$T/q-two.md" ] || printf '%s\n' '---' 'name: two' 'version: "1.0"' 'initial_state: work' 'states:' \
        '  work:' '    accepts:' '      done:' '        type: enum' '        values: [yes]' '        required: true' \
        '    transitions:' '      - target: end' '        when:' '          done: yes' '  end:' '    terminal: true' '---' '' \
        '## work' '' 'Do the work.' '' '## end' '' 'Done.' > "$T/q-two.md"
    (cd "$d" && koto init "$n" --template "$T/q-two.md" "$@" > /dev/null 2> "$T/q.err")
}

# q_content <file> <question> <label> <option>...: a decision question's
# content file. Each option is `<label> -- <reason>` (the record's own form)
# or a bare label.
q_content() {
    local f=$1 q=$2 l=$3
    shift 3
    printf '%s\n' "$@" | jq -R -s --arg q "$q" --arg l "$l" '
        split("\n") | map(select(length > 0) | . as $o | (index(" -- ")) as $i
          | if $i == null then {label: $o, reason: "as the option reads"}
            else {label: $o[:$i], reason: $o[($i + 4):]} end)
        | {context: "The coordinator holds this question for its run.",
           problem: "The options differ in what the run delivers.",
           question: $q, options: ., ground: "It changes what the effort delivers.",
           waiting: [], label: $l}' > "$f" 2> "$T/q.err"
}

# q_attempt <dir> <session> [identity]: an undecided attempt recorded in
# <session> (from <dir>); with an identity, its basis names that question,
# which ties the attempt to it in koto decisions attempts. Sets QA, its id.
q_attempt() {
    local d=$1 s=$2 id=${3-}
    QA=
    set -- --kind judgment --outcome settled --subject "what=the question in hand" --subject result=undecided --by session
    if [ -n "$id" ]; then
        (cd "$d" && koto decisions history "$id" > "$T/q-history.json" 2> "$T/q.err") || return 1
        set -- "$@" --basis "$(jq -r '.raiser.name' "$T/q-history.json"):${id##*/}"
    fi
    (cd "$d" && koto decisions record "$s" "$@" > "$T/q-attempt.json" 2> "$T/q.err") || return 1
    QA=$(jq -r '.id // empty' "$T/q-attempt.json")
    [ -n "$QA" ]
}

# q_raise <dir> <session> <recipient> <question> <label> <option>...: a
# decision question raised in <session> with shirabe question raise, on an
# undecided attempt of <session>'s own, addressed to <recipient>. Sets QI, its
# identity, and QA, the attempt.
q_raise() {
    local d=$1 s=$2 to=$3 q=$4 l=$5
    shift 5
    QI=
    q_attempt "$d" "$s" || return 1
    q_content "$T/q-content.json" "$q" "$l" "$@" || return 1
    (cd "$d" && "$SHIRABE_BIN" question raise --in "$s" --content "$T/q-content.json" --attempt "$QA" --to "$to" \
        > "$T/q-raise.json" 2> "$T/q.err") || return 1
    QI=$(jq -r '.identity // empty' "$T/q-raise.json")
    [ -n "$QI" ]
}

# q_own <dir> <session> <question> <label> <option>...: the session's own
# decision question, as q_raise, addressed to the session itself. A raise
# with no --to addresses a session nothing dispatched to person:owner, and
# koto refuses a pass-up to the person a question already waits on, so the
# run's own question is held at the run until its escalation passes it up.
q_own() {
    local d=$1 s=$2
    shift 2
    q_raise "$d" "$s" "session:$s" "$@"
}

# q_records: the folder the harness records go in, made once.
q_records() {
    local home
    [ -n "$Q_RECORDS" ] && return 0
    home=$(eval echo "~$(id -un)")
    mkdir -p "$home/.claude/projects" 2> "$T/q.err" || return 1
    Q_RECORDS=$(mktemp -d "$home/.claude/projects/shirabe-engine-questions.XXXXXX" 2> "$T/q.err") || { Q_RECORDS=; return 1; }
    if [ -n "${KEEP_T-}" ]; then
        ktg_on_exit '[ -z "$Q_RECORDS" ] || rm -rf "$Q_RECORDS"'
    else
        ktg_on_exit 'case "$T" in */coordinate-test.*) rm -rf "$T" ;; esac; [ -z "$Q_RECORDS" ] || rm -rf "$Q_RECORDS"'
    fi
}

# q_answer <dir> <identity> <label> <session>: the owner's answer to the
# question, <label> picked from its rendered prompt, recorded with shirabe
# question answer --in <session>. koto records an answer in the session it is
# given in and never in the asker's, so <session> is not the one that raised
# the question.
q_answer() {
    local d=$1 id=$2 pick=$3 s=$4 h now
    q_records || return 1
    (cd "$d" && "$SHIRABE_BIN" question render "$id" > "$T/q-render.json" 2> "$T/q.err") || return 1
    # The call must come no earlier than the question was raised.
    sleep 1
    h=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n' \
        | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/')
    now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    jq -c --slurpfile r "$T/q-render.json" --arg h "$h" --arg pick "$pick" --arg now "$now" '
        ($r[0].prompts[0].questions) as $qs
        | if .type == "assistant" then
              .message.content[0].input.questions = $qs
              | .wireToolInputs["toolu_ZQXMARKERcall000000000001"].questions = $qs
          else
              .toolUseResult.questions = $qs
              | .toolUseResult.answers = {($qs[0].question): $pick}
          end
        | .timestamp = $now | .session_id = $h | .sessionId = $h' "$Q_FIXTURE" > "$Q_RECORDS/$h.jsonl" 2> "$T/q.err" || return 1
    (cd "$d" && CLAUDE_CODE_SESSION_ID=$h "$SHIRABE_BIN" question answer "$id" --in "$s" > "$T/q-answer.json" 2> "$T/q.err")
}

# q_open <dir> <identity>: koto shows the question open (true or false).
q_open() {
    (cd "$1" && koto decisions history "$2" > "$T/q-history.json" 2> "$T/q.err") || return 1
    jq -r '.open' "$T/q-history.json"
}
