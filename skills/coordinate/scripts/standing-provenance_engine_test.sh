#!/usr/bin/env bash
# standing-provenance_engine_test.sh -- standing-provenance.sh, the read of
# one cited koto decision's facts, on real koto sessions in a scratch store
# and against fake kotos (KOTO_BIN)
# (docs/designs/DESIGN-coordinator-standing-rule-provenance.md).
#
# The sessions are made here on a one-state template: p1 holds a person
# judgment and a session judgment; pred is superseded by succ, which reverses
# pred's session decision through the fence; w1, dispatched by dir1, has its
# decision reversed from dir1 with no supersede hop; director (no
# dispatcher), manager (dispatched by director) and wk (dispatched by
# manager) hold the questions and answers of criterion 4; cc holds text with
# control characters. Prints one line per criterion:
#   1. a person judgment and a session judgment read as the objects held
#      below, koto's time in each (jq -S), reading null, question null and
#      standing false;
#   2. pred's session decision, reversed by succ through the fence, reads
#      reversed with hop true and one fence step equal to koto's marker;
#   3. w1's decision, reversed from dir1 by its dispatched-by link, reads hop
#      false and fence [];
#   4. the evidence a rule row's class is read from, `reading` and
#      `standing`, and the class state-schema.jq's rule_class gives it: the
#      owner's verified answer to a question marked standing (given in
#      director) and to one whose chosen option is marked (given in the
#      worker wk) read owner-said; the owner's verified answer to an unmarked
#      question (given in manager), one choosing an option other than the
#      marked one, the marked answer read from a copy of the store under
#      another KOTO_HOME (a remote session's answer), and a person judgment
#      recorded in director, which has no dispatcher, read inferred; a
#      session's decision recorded by `shirabe question settle --owner-note`
#      reads unreadable, never owner-said; and with the harness records
#      unreadable the owner's answers still read verified, so no read opens
#      one;
#   5. a reason, subject field, link and handle with control characters and
#      over 200 characters come out under quoted with neither;
#   6. a missing decision, a missing session, five fake kotos (a non-zero
#      exit, text, JSON with no status, status unreadable, a sleep past the
#      deadline, back within 7 s), two fake kotos showing an owner's answer
#      whose question's content read fails or isn't JSON, a bad id and a
#      session name starting with `-` (no koto call) read unreadable with a
#      why and exit 0, none of them changing the store's files, and no read
#      in this suite changing any but koto's own journal of context reads;
#   7. a logging koto shows `decisions show <session> <id>` as separate
#      arguments, `decisions content read <identity>` for an owner's answer
#      and for nothing else, and no koto command but those two reads;
#   8. scripts/check-template-compat.sh passes against the base branch's
#      coordinate.compat.json, compat unchanged: no gate runs the helper.
#
# Every koto call runs on a store under this suite's scratch directory: the
# guard (scripts/lib/koto-test-guard.sh) unsets every KOTO_SESSION_* variable
# and KOTO_SESSIONS_BASE, HOME and KOTO_HOME are set under the scratch
# directory, and `koto session dir` must name a directory there before the
# first koto command, or the suite stops.
#
# A koto without `decisions show`, `decisions chain`, `decisions reverse` and
# `decisions content`, or without `init --supersede` (the entry floor among
# them), runs criteria 6 and 8 alone and names the others it left out.
#
# An owner's answer comes from a recorded harness session, never a live
# prompt, as scripts/question-commands_test.sh records one: a record built
# from scripts/fixtures/question-commands/accepted.jsonl with the rendered
# question in it, in a folder of its own under .claude/projects/ in the
# account's home as the user database gives it (koto reads it there), removed
# at exit.
#
# Needs koto, jq, git and, for criterion 4, a shirabe with `question answer`
# (SHIRABE_BIN, else the tree's target/release/shirabe, else PATH; criterion
# 4 fails without one); SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/standing-provenance_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

# The suite stands in for an attended harness session: a run mode inherited
# from the session running it would refuse every answer before koto checks it.
unset KOTO_RUN_MODE CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CONFIG_DIR

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
REAL_KOTO=$(command -v koto)
ORIG_PATH=$PATH
# test-lib.sh makes the scratch directory T and the ok/bad counters. It puts
# testdata/ (the koto stand-in) first on PATH; this suite needs the real
# koto, so PATH is put back.
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P) || exit 1
# The harness records of criterion 4 sit where koto reads them, in the
# account's home; they go at exit with the scratch directory.
ACCOUNT_HOME=$(eval echo "~$(id -un)")
RECORDS=
ktg_on_exit '[ -z "$RECORDS" ] || { chmod -R u+rwx "$RECORDS"; rm -rf "$RECORDS"; }; case "$T" in */coordinate-test.*) rm -rf "$T" ;; esac'
SHIRABE=
if [ -n "${SHIRABE_BIN:-}" ] && [ -x "$SHIRABE_BIN" ]; then SHIRABE=$SHIRABE_BIN
elif [ -x "$REPO_ROOT/target/release/shirabe" ]; then SHIRABE="$REPO_ROOT/target/release/shirabe"
else SHIRABE=$(command -v shirabe); fi
unset KOTO_STORE KOTO_COMPILED_HASH KOTO_BIN
export HOME="$T/home" KOTO_HOME="$T/home/.koto" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME" "$T/bin" "$T/out"
PATH=$ORIG_PATH
export PATH
SP="$HERE/standing-provenance.sh"

d=$(koto session dir probe 2>&1) || { echo "FAIL: koto session dir failed: [$d]; no case ran"; exit 1; }
case "$d" in
    "$T"/*) ;;
    *) echo "FAIL: koto's session directory is not under $T: [$d]; no case ran"; exit 1 ;;
esac

# Whether this koto records, shows, chains and reverses decisions and fences
# a predecessor; without them criteria 1-5 and 7 are left out.
DEC=1
case "$(koto decisions --help 2>&1)" in *show*) ;; *) DEC=0 ;; esac
case "$(koto decisions --help 2>&1)" in *chain*) ;; *) DEC=0 ;; esac
case "$(koto decisions --help 2>&1)" in *reverse*) ;; *) DEC=0 ;; esac
case "$(koto decisions --help 2>&1)" in *content*) ;; *) DEC=0 ;; esac
case "$(koto init --help 2>&1)" in *--supersede*) ;; *) DEC=0 ;; esac

# One line per criterion: need records what failed, crit keeps the line under
# its number and report prints them, 1 to 8.
WHY=
need() { [ "$2" = "$3" ] || WHY="$WHY; $1: want [$2], got [$3]"; }
needf() { WHY="$WHY; $1"; }
crit() { local n=${1%%.*}; printf -v "CM_$n" '%s' "$1"; printf -v "CW_$n" '%s' "$WHY"; WHY=; }
LEFT=" "
report() {
    local n m w
    for n in 1 2 3 4 5 6 7 8; do
        case "$LEFT" in *" $n "*) echo "left out $n: this koto has no decisions show, chain, reverse or content, or no init --supersede"; continue ;; esac
        m="CM_$n" w="CW_$n"
        [ -n "${!m-}" ] || { bad "criterion $n" "no case reached it"; continue; }
        if [ -z "${!w}" ]; then ok "${!m}"; else bad "${!m}" "${!w#; }"; fi
    done
}

# ---- helpers ---------------------------------------------------------------
cat > "$T/t.md" <<'EOF'
---
name: provenance-probe
version: "1.0"
initial_state: open
states:
  open:
    transitions:
      - target: done
  done:
    terminal: true
---
## open
Open.
## done
Done.
EOF
new_session() { koto init "$1" --template "$T/t.md" "${@:2}" > /dev/null 2> "$T/init.err" || needf "koto init $1 failed: $(cat "$T/init.err")"; }
# record <session> <args>...: koto decisions record; its output in $T/rec.
record() { local s=$1; shift; koto decisions record "$s" --kind judgment --outcome settled "$@" > "$T/rec" 2> "$T/rec.err" || needf "koto decisions record $s failed: $(cat "$T/rec" "$T/rec.err")"; }
# The store's files; a read that writes shows here or in what's newer than
# the stamp.
snap() { find "$KOTO_HOME" | LC_ALL=C sort; }
# koto keeps its own journal of context reads (context-reads.jsonl) in the
# session it reads, so a read that asks `context exists` adds to that one
# file. Criterion 6's reads hold no file at all still; every other read may
# touch nothing but that journal.
WROTE=
WROTE_ELSE=
# sp <name> <args>...: the helper, its stdout in $T/out/<name>, its exit in
# SPRC; any change it made to the store goes in WROTE, and one to anything
# but koto's read journal in WROTE_ELSE too.
sp() {
    local n=$1 newer
    shift
    snap > "$T/snap.before"
    : > "$T/stamp"
    bash "$SP" "$@" > "$T/out/$n" 2> "$T/out/$n.err"
    SPRC=$?
    snap > "$T/snap.after"
    newer=$(find "$KOTO_HOME" -newer "$T/stamp" -type f)
    cmp -s "$T/snap.before" "$T/snap.after" || WROTE="$WROTE; $n: the store's listing changed"
    [ -z "$newer" ] || WROTE="$WROTE; $n: a file in the store changed"
    diff "$T/snap.before" "$T/snap.after" | grep '^[<>]' | grep -v '/context-reads\.jsonl$' > "$T/snap.diff"
    [ -s "$T/snap.diff" ] && WROTE_ELSE="$WROTE_ELSE; $n: the store's listing changed: $(tr '\n' ' ' < "$T/snap.diff")"
    newer=$(printf '%s\n' "$newer" | grep -v '/context-reads\.jsonl$' | grep .)
    [ -z "$newer" ] || WROTE_ELSE="$WROTE_ELSE; $n: changed $newer"
}
# expect <label> <name> <want-json>: the helper's object is want, by jq -S.
expect() {
    need "$1" "$(printf '%s' "$3" | jq -cS . 2>&1)" "$(jq -cS . "$T/out/$2" 2>&1)"
    need "$1: exits 0, one line" "0 1" "$SPRC $(wc -l < "$T/out/$2" | tr -d ' ')"
}
# fake <name> <body>: a fake koto, logging each call's arguments (<a><b>...)
# one line per call to $FAKE_LOG, then running body.
# shellcheck disable=SC2016 # the body is the fake's own code, expanded when it runs
fake() {
    { printf '#!/usr/bin/env bash\n'
      printf 'printf "<%%s>" "$@" >> "${FAKE_LOG:?}"; echo >> "$FAKE_LOG"\n'
      printf '%s\n' "$2"; } > "$T/bin/$1"
    chmod +x "$T/bin/$1"
}
fake koto-logged "exec \"$REAL_KOTO\" \"\$@\""
URL='https://github.com/acme/widgets/issues/1#issuecomment-1'
NOPROMPT='"reading": null, "question": null, "standing": false'

if [ "$DEC" = 1 ]; then
# ---- 1 ----------------------------------------------------------------------
new_session p1
record p1 --by person:bob --surface relay --link "$URL" --reason "go ahead" --subject what=go
t1=$(jq -r '.decision.time' "$T/rec")
record p1 --by session --reason "hold the line" --subject what=hold
t2=$(jq -r '.decision.time' "$T/rec")
sp p1-person p1 000000000001
expect "the person judgment" p1-person '{"session": "p1", "id": "000000000001", "status": "in-effect",
    "decider": {"kind": "person", "entering": "p1", "surface": "relay"}, "time": "'"$t1"'", '"$NOPROMPT"',
    "reversal": null,
    "quoted": {"subject": {"what": "go"}, "reason": "go ahead", "link": "'"$URL"'", "handle": "bob", "reversal_reason": null}}'
sp p1-session p1 000000000002
expect "the session judgment" p1-session '{"session": "p1", "id": "000000000002", "status": "in-effect",
    "decider": {"kind": "session", "session": "p1"}, "time": "'"$t2"'", '"$NOPROMPT"',
    "reversal": null,
    "quoted": {"subject": {"what": "hold"}, "reason": "hold the line", "link": null, "handle": null, "reversal_reason": null}}'
crit "1. a person judgment reads in-effect, its handle, surface, link, entering session and koto's time; a session judgment reads its session; neither has a prompt or a mark"

# ---- 2 ----------------------------------------------------------------------
new_session pred
record pred --by session --reason "ship it" --subject what=ship
new_session succ --continues pred --supersede
koto decisions chain pred > "$T/marker" 2> "$T/marker.err" || needf "koto decisions chain pred failed: $(cat "$T/marker.err")"
koto decisions reverse pred 000000000001 --in succ --by session --reason "not yet" > "$T/rev" 2> "$T/rev.err" \
    || needf "the reversal through the fence failed: $(cat "$T/rev" "$T/rev.err")"
need "the marker's successor is succ's session id" "$(jq -r '.decision.session.id' "$T/rev")" "$(jq -r '.marker.successor.id' "$T/marker")"
sp pred pred 000000000001
need "pred's decision reads reversed, exit 0" "reversed 0" "$(jq -r .status "$T/out/pred") $SPRC"
need "the reversal" "$(jq -cS --slurpfile r "$T/rev" '.marker as $m | {session: "succ", id: $r[0].id, time: $r[0].decision.time,
        decider: {kind: "session", session: "succ"}, standing: "verified", hop: true,
        fence: [{session: "pred", to: "succ", successor_id: $m.successor.id, actor: $m.actor, time: $m.time}]}' "$T/marker")" \
    "$(jq -cS .reversal "$T/out/pred")"
need "the reversal's reason, quoted" "not yet" "$(jq -r .quoted.reversal_reason "$T/out/pred")"
crit "2. a decision reversed through a supersede fence reads reversed, standing verified, hop true, one fence step equal to koto's marker"

# ---- 3 ----------------------------------------------------------------------
new_session dir1
new_session w1
koto session link w1 --dispatched-by dir1 > /dev/null 2> "$T/link.err" || needf "koto session link w1 failed: $(cat "$T/link.err")"
record w1 --by session --reason "use the cache" --subject what=cache
koto decisions reverse w1 000000000001 --in dir1 --by session --reason "drop the cache" > "$T/rev" 2> "$T/rev.err" \
    || needf "the reversal from above failed: $(cat "$T/rev" "$T/rev.err")"
need "koto's path is the link, no supersede step" '[{"session":"w1","to":"dir1","via":"link"}]' "$(jq -cS .decision.path "$T/rev")"
sp w1 w1 000000000001
need "w1's decision reads reversed by dir1, hop false, fence []" "reversed|dir1|$(jq -r .id "$T/rev")|verified|false|[]" \
    "$(jq -r '"\(.status)|\(.reversal.session)|\(.reversal.id)|\(.reversal.standing)|\(.reversal.hop)|\(.reversal.fence | tojson)"' "$T/out/w1")"
crit "3. a reversal from a dispatching session, with no supersede hop, reads hop false and fence []"

# ---- 4 ----------------------------------------------------------------------
# The owner's answers come from recorded harness sessions (see the header).
# director has no dispatcher, manager is dispatched by director and wk by
# manager; every question is raised in wk.
cls() { # cls <name>: the class rule_class gives a decision row citing $T/out/<name>
    jq -r -L "$HERE" 'include "state-schema"; {source: "decision \(.session) \(.id)", cited: .} | rule_class' "$T/out/$1" 2>&1
}
facts() { jq -c '[.status, .decider.kind, .reading, .standing, (.question != null)]' "$T/out/$1" 2>&1; }
# qcontent <file> <label> <question-mark> <option-mark>: the question's content;
# <question-mark> true marks the question, <option-mark> the label of the one
# option marked, or "".
qcontent() {
    jq -n --arg l "$2" --argjson q "$3" --arg o "$4" '{
        context: "Two lanes merged on a Friday evening last month.",
        problem: "Nothing says when a merge may land.",
        question: "From now on, merge nothing after Friday noon?",
        options: [
            ({label: "Yes", reason: "Merges wait for Monday."} + (if $o == "Yes" then {standing: true} else {} end)),
            ({label: "No", reason: "Merges land whenever checks pass."} + (if $o == "No" then {standing: true} else {} end))
        ],
        ground: "It binds every lane.",
        waiting: [],
        label: $l
    } + (if $q then {standing: true} else {} end)' > "$1"
}
# oraise <label> <question-mark> <option-mark> [more raise args...]: a question
# raised in wk on an undecided attempt; its identity in QID.
oraise() {
    local l=$1 q=$2 o=$3 a
    shift 3
    QID=
    qcontent "$T/q.json" "$l" "$q" "$o"
    "$SHIRABE" question attempt --in wk --what "when a merge may land" --result undecided > "$T/att.out" 2> "$T/att.err" \
        || { needf "an attempt in wk: $(cat "$T/att.out" "$T/att.err")"; return 1; }
    a=$(jq -r '.id // empty' "$T/att.out")
    "$SHIRABE" question raise --in wk --content "$T/q.json" --attempt "$a" "$@" > "$T/raise.out" 2> "$T/raise.err" \
        || { needf "raise $l in wk: $(cat "$T/raise.out" "$T/raise.err")"; return 1; }
    QID=$(jq -r '.identity // empty' "$T/raise.out")
}
harness_id() {
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' \
        | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/'
}
# oanswer <identity> <label picked> <session>: the owner's answer from a
# recorded harness session, given in <session>; ANS_S and ANS_ID name it.
oanswer() {
    local h now
    ANS_S= ANS_ID=
    if [ -z "$RECORDS" ]; then
        mkdir -p "$ACCOUNT_HOME/.claude/projects" || { needf "cannot make $ACCOUNT_HOME/.claude/projects"; return 1; }
        RECORDS=$(mktemp -d "$ACCOUNT_HOME/.claude/projects/shirabe-standing-provenance-test.XXXXXX") \
            || { RECORDS=; needf "mktemp under the account's .claude/projects failed"; return 1; }
    fi
    "$SHIRABE" question render "$1" > "$T/render.out" 2> "$T/render.err" || { needf "render $1: $(cat "$T/render.err")"; return 1; }
    # The call must come no earlier than the question was raised.
    sleep 1
    h=$(harness_id)
    now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    jq -c --slurpfile r "$T/render.out" --arg h "$h" --arg pick "$2" --arg now "$now" '
        ($r[0].prompts[0].questions) as $qs
        | if .type == "assistant" then
              .message.content[0].input.questions = $qs
              | .wireToolInputs["toolu_ZQXMARKERcall000000000001"].questions = $qs
          else
              .toolUseResult.questions = $qs
              | .toolUseResult.answers = {($qs[0].question): $pick}
          end
        | .timestamp = $now | .session_id = $h | .sessionId = $h' "$FIXTURE" > "$RECORDS/$h.jsonl" \
        || { needf "cannot write the harness record"; return 1; }
    CLAUDE_CODE_SESSION_ID="$h" "$SHIRABE" question answer "$1" --in "$3" > "$T/answer.out" 2> "$T/answer.err" \
        || { needf "answer $1 in $3: $(cat "$T/answer.out" "$T/answer.err")"; return 1; }
    ANS_S=$(jq -r '.session // empty' "$T/answer.out")
    ANS_ID=$(jq -r '.id // empty' "$T/answer.out")
}
FIXTURE="$REPO_ROOT/scripts/fixtures/question-commands/accepted.jsonl"
if [ -z "$SHIRABE" ] || ! "$SHIRABE" question answer --help > /dev/null 2> "$T/probe.err"; then
    needf "no shirabe with \`question answer\` (SHIRABE_BIN, target/release/shirabe or PATH); build the branch's (cargo build --release): $(head -n 2 "$T/probe.err")"
else
    new_session director
    new_session manager
    koto session link manager --dispatched-by director > /dev/null 2> "$T/link.err" || needf "koto session link manager failed: $(cat "$T/link.err")"
    new_session wk
    koto session link wk --dispatched-by manager > /dev/null 2> "$T/link.err" || needf "koto session link wk failed: $(cat "$T/link.err")"
    # owner-said: the question marked, answered in director.
    if oraise marked true "" --to person:owner && oanswer "$QID" Yes director; then
        OS_Q=$ANS_S OS_QID=$ANS_ID MARKED_QID=$QID
        sp os-question "$ANS_S" "$ANS_ID"
        need "the marked question's answer, given in director: in effect, the owner's, verified, marked, its question named" \
            '["in-effect","person","verified",true,true]' "$(facts os-question)"
        need "  ... its question the one raised" "$QID" "$(jq -r .question "$T/out/os-question")"
        need "  ... and it reads owner-said" owner-said "$(cls os-question)"
    fi
    # owner-said: the option chosen is the marked one, answered in the worker.
    if oraise option-chosen false Yes --to person:owner && oanswer "$QID" Yes wk; then
        sp os-option "$ANS_S" "$ANS_ID"
        need "the answer choosing the marked option, given in wk: verified and marked" \
            '["in-effect","person","verified",true,true]' "$(facts os-option)"
        need "  ... and it reads owner-said" owner-said "$(cls os-option)"
    fi
    # inferred: verified, no mark, answered in manager.
    if oraise unmarked false "" --to person:owner && oanswer "$QID" Yes manager; then
        sp in-unmarked "$ANS_S" "$ANS_ID"
        need "the owner's verified answer to an unmarked question, given in manager: verified, not marked" \
            '["in-effect","person","verified",false,true]' "$(facts in-unmarked)"
        need "  ... and it reads inferred" inferred "$(cls in-unmarked)"
    fi
    # inferred: an option is marked, but not the one the owner chose.
    if oraise option-other false Yes --to person:owner && oanswer "$QID" No director; then
        sp in-other "$ANS_S" "$ANS_ID"
        need "the answer choosing the unmarked option: verified, not marked" \
            '["in-effect","person","verified",false,true]' "$(facts in-other)"
        need "  ... and it reads inferred" inferred "$(cls in-other)"
    fi
    # inferred: the marked answer read from a copy of the sessions under
    # another KOTO_HOME, which holds no host identity of its own.
    if [ -n "${OS_QID:-}" ]; then
        SDIR=$(dirname "$(koto session dir director)")
        case "$SDIR" in
            "$KOTO_HOME"/*)
                REMOTE_HOME="$T/remote/.koto"
                mkdir -p "$REMOTE_HOME/$(dirname "${SDIR#"$KOTO_HOME"/}")"
                cp -R "$SDIR" "$REMOTE_HOME/${SDIR#"$KOTO_HOME"/}" || needf "cannot copy the sessions"
                KOTO_HOME="$REMOTE_HOME" sp in-remote "$OS_Q" "$OS_QID"
                need "the marked answer read from a copied store: a remote session's answer, still marked" \
                    "[\"in-effect\",\"person\",\"a remote session's answer\",true,true]" "$(facts in-remote)"
                need "  ... and it reads inferred" inferred "$(cls in-remote)"
                ;;
            *) needf "koto's session directory [$SDIR] is not under KOTO_HOME, so no copy can be made" ;;
        esac
    fi
    # inferred: a person judgment in director, which has no dispatcher, with no
    # answered prompt behind it (the coordinator writing down what it heard).
    record director --by person:owner --surface terminal --reason "merge nothing after Friday noon" --subject what=merge-window
    sp in-judgment director "$(jq -r .id "$T/rec")"
    need "a person judgment in a coordinator with no dispatcher: the owner's, no reading, no mark" \
        '["in-effect","person",null,false,false]' "$(facts in-judgment)"
    need "  ... and it reads inferred, not owner-said" inferred "$(cls in-judgment)"
    # a session's decision noting the owner: settle --owner-note in manager on
    # a question waiting on manager.
    if oraise relayed true ""; then
        if "$SHIRABE" question settle "$QID" --in manager --chosen Yes --reason "relayed in chat" \
                --owner-note "the owner said so in chat" > "$T/settle.out" 2> "$T/settle.err"; then
            sp un-relayed "$(jq -r .session "$T/settle.out")" "$(jq -r .id "$T/settle.out")"
            need "a session's decision noting the owner: manager's, no reading, no mark" \
                '["in-effect","session",null,false,false]' "$(facts un-relayed)"
            need "  ... and it reads unreadable, as a session's decision did before, never owner-said" unreadable "$(cls un-relayed)"
        else
            needf "settle --owner-note in manager: $(cat "$T/settle.out" "$T/settle.err")"
        fi
    fi
    # No read opens a harness record: with them unreadable, the owner's
    # answer still reads verified and marked.
    if [ -n "$RECORDS" ] && [ -n "${OS_QID:-}" ]; then
        chmod -R a-rwx "$RECORDS"
        sp os-norecord "$OS_Q" "$OS_QID"
        chmod -R u+rwx "$RECORDS"
        need "with the harness records unreadable, the marked answer reads as before" "$(jq -cS . "$T/out/os-question")" "$(jq -cS . "$T/out/os-norecord")"
    fi
fi
crit "4. a row reads owner-said only from a verified standing answer: the owner's verified answer to a marked question or with its marked option chosen, given in director or a worker, reads owner-said; an unmarked question, an unchosen marked option, a remote session's answer and a person judgment at a coordinator with no dispatcher read inferred; a settle --owner-note decision reads unreadable; no read opens a harness record"

# ---- 5 ----------------------------------------------------------------------
LONG=$(printf '%0300d' 0 | tr 0 x)
CTRL=$(printf 'a\001b\033[31mc\td\ne\177f\302\205g')
new_session cc
# koto refuses a control character in a handle or a link, so those two are
# long here and get theirs from the fake below.
record cc --by "person:bob${LONG:0:240}" --surface relay --link "$URL${LONG:0:150}" --reason "r${CTRL}$LONG" --subject "what=s${CTRL}$LONG"
sp cc cc 000000000001
koto decisions show cc 000000000001 > "$T/cc.body" 2> /dev/null
jq -c --arg c "$CTRL" --arg l "$LONG" '.decision.decider.handle.value = "bob\($c)\($l)" | .decision.decider.link = "https://x/\($c)\($l)"' \
    "$T/cc.body" > "$T/cc.fake"
fake koto-body "case \"\$1 \$2\" in \"decisions show\") cat \"$T/cc.fake\" ;; \"context list\") echo '[]' ;; *) exit 1 ;; esac"
FAKE_LOG="$T/body.log" KOTO_BIN="$T/bin/koto-body" sp cc-fake cc 000000000001
# clean_ok <name>: every quoted string has no control character and at most
# 200 characters, and the four fields are there.
clean_ok() {
    need "$1: in-effect, exit 0" "in-effect 0" "$(jq -r .status "$T/out/$1") $SPRC"
    need "$1: no quoted string holds a control character or runs past 200" "" \
        "$(jq -r '[.quoted | .. | strings | select(length > 200 or (explode | any(. < 32 or (. >= 127 and . <= 159))))] | .[]' "$T/out/$1")"
    need "$1: reason, subject, link and handle are quoted, cut to 200" "200 200 200 200" \
        "$(jq -r '[.quoted.reason, .quoted.subject.what, .quoted.link, .quoted.handle] | map(length) | join(" ")' "$T/out/$1")"
}
clean_ok cc
need "cc: the reason keeps its text" "rab[31mcdefgxxx" "$(jq -r '.quoted.reason[0:15]' "$T/out/cc")"
clean_ok cc-fake
need "cc-fake: the handle and link keep their text" "bobab[31mcdefgx|https://x/ab[31mcdefgx" \
    "$(jq -r '"\(.quoted.handle[0:15])|\(.quoted.link[0:22])"' "$T/out/cc-fake")"
crit "5. a reason, subject field, link and handle holding control characters and over 200 characters come out under quoted with none and at most 200"
else
    LEFT=" 1 2 3 4 5 7 "
    new_session p1
fi

# ---- 6 ----------------------------------------------------------------------
# unread_ok <name> <session> <id>: unreadable, a why, exit 0, the four keys.
unread_ok() {
    need "$1: unreadable with a why, exit 0" "unreadable true 0" \
        "$(jq -r '"\(.status) \(.why | type == "string" and length > 0)"' "$T/out/$1" 2>&1) $SPRC"
    need "$1: the four keys, its session and id" "$(jq -cn --arg s "$2" --arg i "$3" '{session: $s, id: $i, status: "unreadable"}')" \
        "$(jq -c '{session, id, status}' "$T/out/$1" 2>&1)"
    need "$1: one line and nothing else" "1 id,session,status,why" "$(wc -l < "$T/out/$1" | tr -d ' ') $(jq -r 'keys | join(",")' "$T/out/$1" 2>&1)"
}
WROTE=
sp no-decision p1 000000000099
unread_ok no-decision p1 000000000099
sp no-session ghost 000000000001
unread_ok no-session ghost 000000000001
fake koto-exit 'exit 3'
fake koto-text 'echo "this is not json"'
# shellcheck disable=SC2016
fake koto-nostatus 'printf "%s\n" "{\"v\":1,\"session\":\"$3\",\"id\":\"$4\",\"decision\":{}}"'
# shellcheck disable=SC2016
fake koto-unreadable 'printf "%s\n" "{\"v\":1,\"session\":\"$3\",\"id\":\"$4\",\"status\":\"unreadable\"}"'
fake koto-sleep 'sleep 30'
for f in exit text nostatus unreadable; do
    FAKE_LOG="$T/$f.log" KOTO_BIN="$T/bin/koto-$f" sp "fake-$f" p1 000000000001
    unread_ok "fake-$f" p1 000000000001
    need "fake-$f: koto was asked" "<decisions><show><p1><000000000001>" "$(head -1 "$T/$f.log" 2>&1)"
done
# An owner's answer whose question's content can't be read, or isn't JSON.
OWNER_SHOW="$HERE/testdata/standing-rules/cited/show/director-a_000000000004.json"
fake koto-nocontent "case \"\$1 \$2\" in \"decisions show\") cat \"$OWNER_SHOW\" ;; *) exit 3 ;; esac"
fake koto-badcontent "case \"\$1 \$2\" in \"decisions show\") cat \"$OWNER_SHOW\" ;; *) echo 'not json' ;; esac"
for f in nocontent badcontent; do
    FAKE_LOG="$T/$f.log" KOTO_BIN="$T/bin/koto-$f" sp "fake-$f" director-a 000000000004
    unread_ok "fake-$f" director-a 000000000004
    need "fake-$f: the question's content was asked for" "<decisions><content><read><11111111-1111-4111-8111-111111111111/000000000002>" \
        "$(sed -n 2p "$T/$f.log" 2>&1)"
done
start=$(date +%s)
FAKE_LOG="$T/sleep.log" KOTO_BIN="$T/bin/koto-sleep" sp fake-sleep p1 000000000001
took=$(($(date +%s) - start))
unread_ok fake-sleep p1 000000000001
[ "$took" -le 7 ] || needf "the sleeping koto took the read ${took}s, past 7"
need "fake-sleep: the why names the deadline" "true" "$(jq -r '.why | test("within")' "$T/out/fake-sleep")"
for c in "bad-id p1 12345" "bad-id-letters p1 00000000000a" "bad-session -p1 000000000001"; do
    # shellcheck disable=SC2086 # split on purpose: the case's words
    set -- $c
    : > "$T/none.log"
    FAKE_LOG="$T/none.log" KOTO_BIN="$T/bin/koto-logged" sp "$1" "$2" "$3"
    unread_ok "$1" "$2" "$3"
    need "$1: no koto call" "" "$(cat "$T/none.log")"
done
need "none of these reads changed the store" "" "${WROTE#; }"
need "no read in this suite changed anything in the store but koto's read journal" "" "${WROTE_ELSE#; }"
crit "6. a missing decision or session, a failing, wordy, statusless, unreadable or sleeping koto, an owner's answer whose question's content fails or isn't JSON, a bad id and a '-' session read unreadable with a why, exit 0, nothing written"

# ---- 7 ----------------------------------------------------------------------
if [ "$DEC" = 1 ]; then
    : > "$T/calls.log"
    L7="p1-person p1 000000000001|pred pred 000000000001"
    [ -n "${OS_QID:-}" ] && L7="$L7|os-question $OS_Q $OS_QID"
    printf '%s\n' "$L7" | tr '|' '\n' > "$T/l7"
    while read -r n s i; do
        FAKE_LOG="$T/calls.log" KOTO_BIN="$T/bin/koto-logged" sp "logged-$n" "$s" "$i"
        need "logged-$n: the logged read matches the plain one" "$(jq -cS . "$T/out/$n")" "$(jq -cS . "$T/out/logged-$n")"
    done < "$T/l7"
    grep -qx '<decisions><show><p1><000000000001>' "$T/calls.log" || needf "no call reads decisions show p1 000000000001 as four arguments: $(head -3 "$T/calls.log")"
    if [ -n "${OS_QID:-}" ]; then
        need "the one content read is the owner's answer's question, as four arguments" "<decisions><content><read><$MARKED_QID>" \
            "$(grep '^<decisions><content>' "$T/calls.log")"
    else
        needf "no owner's answer was recorded (criterion 4), so no content read could be logged"
    fi
    need "no koto decisions command but show and content read" "" "$(grep '^<decisions>' "$T/calls.log" | grep -vE '^<decisions><(show|content><read)>')"
    need "no koto command but decisions show and decisions content read" "" \
        "$(grep -vE '^<decisions><(show|content><read)>' "$T/calls.log")"
    crit "7. the call log shows decisions show <session> <id> as separate arguments, decisions content read of the owner's answer's question alone, and no koto command but those two reads"
fi

# ---- 8 ----------------------------------------------------------------------
# The base branch's table, origin/main's (or main's). A checkout holding
# neither (a shallow clone) still checks that the table records this
# template's structure and gate scripts digest, and says it had no base.
BASE=$(git -C "$REPO_ROOT" rev-parse --verify -q origin/main 2>/dev/null) || BASE=$(git -C "$REPO_ROOT" rev-parse --verify -q main 2>/dev/null) || BASE=
CARGS=(--template skills/coordinate/koto-templates/coordinate.md)
if [ -n "$BASE" ]; then
    git -C "$REPO_ROOT" show "$BASE:skills/coordinate/koto-templates/coordinate.compat.json" > "$T/base.compat.json" 2> "$T/base.err" \
        || needf "the base's coordinate.compat.json can't be read: $(cat "$T/base.err")"
    CARGS+=(--base-table "$T/base.compat.json")
    # compat stays the base's only while the template keeps the structure the
    # base lists at its compat; a structure the base doesn't list there is a
    # change's own raise, and check-template-compat.sh decides whether it holds.
    FP=$(cd "$REPO_ROOT" && bash scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md --print 2>/dev/null | jq -r '.fingerprint // empty')
    [ -n "$FP" ] || needf "check-template-compat.sh printed no fingerprint"
    if jq -e --arg f "$FP" '.fingerprints[$f] == .compat' "$T/base.compat.json" >/dev/null; then
        need "  ... compat unchanged from the base's over the base's own structure" "$(jq -c .compat "$T/base.compat.json" 2>/dev/null)" \
            "$(jq -c .compat "$REPO_ROOT/skills/coordinate/koto-templates/coordinate.compat.json")"
    fi
else
    echo "     (no origin/main or main in this checkout: the compat check runs without a base table)"
fi
(cd "$REPO_ROOT" && bash scripts/check-template-compat.sh "${CARGS[@]}") > "$T/compat.out" 2>&1
rc=$?
[ "$rc" = 0 ] || needf "scripts/check-template-compat.sh exits $rc: $(cat "$T/compat.out")"
crit "8. scripts/check-template-compat.sh passes against the base branch's coordinate.compat.json, compat the base's over the base's own structure: no gate runs the helper"

report
done_tests standing-provenance-engine
