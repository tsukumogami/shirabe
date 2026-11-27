#!/usr/bin/env bash
# undecided-result_test.sh -- a decision that ends undecided, against the real
# koto: `shirabe question attempt`, check-undecided.sh, the hand-off to
# `shirabe question raise`, and the passages that must name the third result.
#
# The Rust suite (crates/shirabe/tests/question_attempt.rs) drives `attempt`
# against a koto stand-in. This one runs it against the koto on PATH, so what
# koto stores and reads back is exercised: the subject, the reason, the run
# mode, the attempts read by result, state and review, and that a provisional
# decision is listed for review and never as a question.
#
# Sessions: `solo` and `manager` with nothing above them, and `worker`
# dispatched by `manager`. A call made "in an unattended session" sets
# KOTO_RUN_MODE=unattended for that call, and one made in an attended session
# sets KOTO_RUN_MODE=attended: shirabe and koto read the run mode per call
# from the environment, the way `answer` reads it.
#
# Cases:
#   attempt: an undecided attempt with a state, read back by result and
#     state; one without a state reads back with a null state and is not
#     returned by the state filter; each refused input exits 1 (a missing
#     result 2) and leaves every session directory byte-identical, lock
#     files aside; decided needs --chosen and keeps its basis
#   provisional: accepted in the unattended worker with --undo cheap, listed
#     for review at manager and in worker, never by `decisions open`;
#     refused with --undo costly and in an attended session; an unattended
#     undecided attempt needs the undo test, and a cheap one needs a ground
#   raise takes the undecided attempt and refuses the decided and the
#     provisional one
#   check-undecided.sh on the testdata/undecided fixture loaded into worker:
#     exit 0; exit 1 naming the part for each edited copy; exit 3 on a
#     settled report
#   the hand-off as /design and /explore are told to make it: the check, then
#     `koto context get <session> <question_key>` into `shirabe question raise
#     --content - --attempt <id>`; the stored question holds the decider's
#     context, problem, question and options unchanged, and the research keys
#     are still readable after it
#   every consumer that branches on a decision's status names the third one,
#     and no other file under skills/ or references/ names the settled status
#     without it
#   the three phrases this step removed stay gone
#
# Usage: bash skills/decision/scripts/undecided-result_test.sh [<caller>]
#   <caller> (decision, design or explore) adds the hand-off from that
#   caller's own session, `<caller>-licence`, which nothing dispatched, so the
#   question goes to person:owner. scripts/cases/decision-handoff.sh passes it.
#   shirabe from SHIRABE_BIN, else the tree's target/release/shirabe, else
#   PATH; it must have `question attempt`. koto 0.42.0 or later on PATH; jq.
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed, or a tool is missing
#   2 -- usage
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
unset KOTO_RUN_MODE CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CONFIG_DIR

CALLER=""
case "$#" in
    0) ;;
    1)
        case "$1" in
            decision|design|explore) CALLER=$1 ;;
            *) echo "usage: undecided-result_test.sh [decision|design|explore]"; exit 2 ;;
        esac
        ;;
    *) echo "usage: undecided-result_test.sh [decision|design|explore]"; exit 2 ;;
esac

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/../../.." && pwd)
FIX="$SCRIPT_DIR/testdata/undecided"
CHECK="$SCRIPT_DIR/check-undecided.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
finish() {
    echo
    echo "undecided-result_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
}

# --- documents: consumers and removed phrases (no tools needed) --------------

CONSUMERS="skills/decision/SKILL.md
skills/decision/references/phases/phase-2-alternatives.md
skills/decision/references/phases/phase-6-synthesis.md
references/decision-report-format.md
references/decision-block-format.md
references/decision-protocol.md
skills/design/SKILL.md
skills/design/references/phases/phase-2-execution.md
skills/design/references/phases/phase-3-cross-validation.md
skills/explore/references/phases/phase-5-produce-decision.md
docs/specs/decisions-file-format.md
docs/specs/review-surface.md"

cons_ok=1
for f in $CONSUMERS; do
    if [ ! -f "$REPO/$f" ]; then
        fail "consumer $f is missing"
        cons_ok=0
    elif ! grep -qiE 'undecided' "$REPO/$f"; then
        fail "consumer $f does not name the undecided result"
        cons_ok=0
    fi
done
[ "$cons_ok" -eq 1 ] && pass "every listed consumer of a decision's status names the undecided result"

# The settled status, named as a decision status, anywhere else under skills/
# or references/ must come with the third one.
other_ok=1
grep -rlE 'status: *"?COMPLETE"?' "$REPO/skills" "$REPO/references" --include='*.md' > "${TMPDIR:-/tmp}/undecided-consumers.$$" 2>/dev/null
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! grep -q 'UNDECIDED' "$f"; then
        fail "${f#"$REPO"/} names the settled decision status and not UNDECIDED"
        other_ok=0
    fi
done < "${TMPDIR:-/tmp}/undecided-consumers.$$"
rm -f "${TMPDIR:-/tmp}/undecided-consumers.$$"
[ "$other_ok" -eq 1 ] && pass "no file under skills/ or references/ names the settled status without UNDECIDED"

phrase_ok=1
if grep -n "Continue without waiting" "$REPO/references/decision-protocol.md"; then
    fail "references/decision-protocol.md still says: Continue without waiting"; phrase_ok=0
fi
if grep -n "rather than hard-stopping" "$REPO/references/workflow-principles.md"; then
    fail "references/workflow-principles.md still says: rather than hard-stopping"; phrase_ok=0
fi
if grep -rn "follow the recommendation" "$REPO/skills/decision/references/phases/"; then
    fail "a decision phase file still says: follow the recommendation"; phrase_ok=0
fi
[ "$phrase_ok" -eq 1 ] && pass "the three removed phrases are gone"

if grep -q 'shirabe question attempt' "$REPO/references/question-procedure.md"; then
    pass "the question procedure names shirabe question attempt"
else
    fail "references/question-procedure.md does not name shirabe question attempt"
fi

# --- tools --------------------------------------------------------------------

SHIRABE=""
if [ -n "${SHIRABE_BIN:-}" ] && [ -x "$SHIRABE_BIN" ]; then
    SHIRABE=$SHIRABE_BIN
elif [ -x "$REPO/target/release/shirabe" ]; then
    SHIRABE="$REPO/target/release/shirabe"
else
    SHIRABE=$(command -v shirabe 2>/dev/null)
fi
if [ -z "$SHIRABE" ] || ! "$SHIRABE" question attempt --help >/dev/null 2>&1; then
    fail "no shirabe with \`question attempt\` (SHIRABE_BIN, target/release/shirabe or PATH); build the branch's (cargo build --release -p shirabe)"
    finish
fi
for tool in koto jq; do
    command -v "$tool" >/dev/null 2>&1 || { fail "$tool is not on PATH"; finish; }
done

T=$(mktemp -d "${TMPDIR:-/tmp}/undecided-result-test.XXXXXX") || { fail "mktemp failed"; finish; }
cleanup() {
    [ -n "${T:-}" ] && rm -rf "$T"
    return 0
}
ktg_on_exit cleanup
cd "$T" || { fail "cd $T"; finish; }

cat > "$T/two.md" <<'EOF'
---
name: two
version: "1.0"
initial_state: work
states:
  work:
    accepts:
      done:
        type: enum
        values: [yes]
        required: true
    transitions:
      - target: end
        when:
          done: yes
  end:
    terminal: true
---

## work

Do the work.

## end

Done.
EOF
for s in manager solo; do
    koto init "$s" --template "$T/two.md" >/dev/null 2>"$T/init.err" || { fail "koto init $s: $(cat "$T/init.err")"; finish; }
done
koto init worker --template "$T/two.md" --dispatched-by manager >/dev/null 2>"$T/init.err" \
    || { fail "koto init worker: $(cat "$T/init.err")"; finish; }

# att <mode|-> <args...> -> stdout in $T/att.out, exit in $RC
att() {
    local mode=$1
    shift
    if [ "$mode" = "-" ]; then
        "$SHIRABE" question attempt "$@" >"$T/att.out" 2>"$T/att.err"
    else
        KOTO_RUN_MODE=$mode "$SHIRABE" question attempt "$@" >"$T/att.out" 2>"$T/att.err"
    fi
    RC=$?
}
out() { cat "$T/att.out" "$T/att.err"; }

# snap -> one line per file in every session directory, lock files aside
snap() {
    local s d
    for s in manager solo worker; do
        d=$(koto session dir "$s" 2>/dev/null) || continue
        [ -d "$d" ] || continue
        find "$d" -type f ! -name '*.lock' ! -name '.lock*' | sort | while IFS= read -r f; do
            cksum "$f"
        done
    done
}

# --- attempt: undecided, with and without a state ------------------------------

att - --in solo --what "cache store" --result undecided --state implement:1
ID_STATE=$(jq -r '.id // empty' "$T/att.out" 2>/dev/null)
if [ "$RC" -eq 0 ] && [ -n "$ID_STATE" ] \
    && [ "$(jq -r '.session' "$T/att.out")" = "solo" ] \
    && [ "$(jq -r '.result' "$T/att.out")" = "undecided" ] \
    && [ "$(jq -r '.state' "$T/att.out")" = "implement:1" ]; then
    pass "an undecided attempt with a state exits 0 and prints its id, session, result and state"
else
    fail "undecided attempt with a state exited $RC: $(out)"
    finish
fi

koto decisions attempts --in solo --result undecided --state implement:1 >"$T/a.json" 2>>"$T/koto.err"
if [ "$(jq -r '[.attempts[] | .id] | join(",")' "$T/a.json" 2>/dev/null)" = "$ID_STATE" ]; then
    pass "koto's attempts read by result and state returns exactly that entry"
else
    fail "attempts --result undecided --state implement:1: $(cat "$T/a.json")"
fi
koto decisions show solo "$ID_STATE" >"$T/show.txt" 2>>"$T/koto.err"
if grep -q 'undecided' "$T/show.txt" && grep -q 'implement:1' "$T/show.txt" && grep -q 'cache store' "$T/show.txt"; then
    pass "koto decisions show prints the result, the state and what was decided"
else
    fail "show solo $ID_STATE: $(cat "$T/show.txt")"
fi

att - --in solo --what "table layout" --result undecided
ID_NOSTATE=$(jq -r '.id // empty' "$T/att.out" 2>/dev/null)
koto decisions attempts --in solo >"$T/a.json" 2>>"$T/koto.err"
st=$(jq -r --arg id "$ID_NOSTATE" '.attempts[] | select(.id == $id) | .state' "$T/a.json" 2>/dev/null)
koto decisions attempts --in solo --state implement:1 >"$T/b.json" 2>>"$T/koto.err"
if [ "$RC" -eq 0 ] && [ "$st" = "null" ] \
    && ! jq -e --arg id "$ID_NOSTATE" '.attempts[] | select(.id == $id)' "$T/b.json" >/dev/null 2>&1; then
    pass "an attempt without --state reads back with a null state and the state filter leaves it out"
else
    fail "attempt without a state: rc $RC, state [$st]: $(cat "$T/a.json" "$T/b.json")"
fi

# --- attempt: refusals write nothing ------------------------------------------

before=$(snap)
ref_ok=1
refuse() {
    local want=$1
    shift
    att - "$@"
    if [ "$RC" -ne "$want" ]; then
        fail "attempt $* exited $RC, not $want: $(out)"
        ref_ok=0
    fi
}
refuse 2 --in solo --what "cache store"
refuse 1 --in solo --what "cache store" --result maybe
refuse 1 --in solo --what "cache store" --result ""
refuse 1 --in solo --what "cache store" --result undecided --state implement
refuse 1 --in solo --what "cache store" --result undecided --state implement:0
refuse 1 --in solo --what "cache store" --result undecided --state :1
refuse 1 --in solo --what "" --result undecided
refuse 1 --in solo --what "cache store" --result decided
after=$(snap)
if [ "$ref_ok" -eq 1 ] && [ "$before" = "$after" ]; then
    pass "each refused input exits 1 (a missing result 2) and every session directory is byte-identical"
elif [ "$ref_ok" -eq 1 ]; then
    fail "a refused attempt changed a session directory"
fi

# --- attempt: decided with its basis -------------------------------------------

att - --in solo --what "cache store" --result decided --chosen SQLite --basis "solo:$ID_STATE"
ID_DECIDED=$(jq -r '.id // empty' "$T/att.out" 2>/dev/null)
koto decisions show solo "$ID_DECIDED" >"$T/show.txt" 2>>"$T/koto.err"
if [ "$RC" -eq 0 ] && grep -q 'decided' "$T/show.txt" && grep -q 'SQLite' "$T/show.txt" && grep -q "$ID_STATE" "$T/show.txt"; then
    pass "a decided attempt holds the chosen option and reads back its basis"
else
    fail "decided attempt: rc $RC: $(out) $(cat "$T/show.txt")"
fi

# --- provisional --------------------------------------------------------------

att unattended --in worker --what "table name" --result provisional --undo cheap \
    --undo-reason "only this branch's migration names it" --chosen cache_entries
ID_PROV=$(jq -r '.id // empty' "$T/att.out" 2>/dev/null)
echo "point 4: $(out)"
if [ "$RC" -eq 0 ] && [ -n "$ID_PROV" ]; then
    pass "a provisional decision in the unattended worker is recorded ($ID_PROV)"
else
    fail "provisional in worker exited $RC: $(out)"
fi
koto decisions attempts --at manager --result provisional --awaiting-review >"$T/at.json" 2>>"$T/koto.err"
echo "point 4: $(cat "$T/at.json")"
koto decisions attempts --in worker --result provisional --awaiting-review >"$T/in.json" 2>>"$T/koto.err"
koto decisions open --at manager >"$T/open-at.json" 2>>"$T/koto.err"
koto decisions open --person owner >"$T/open-owner.json" 2>>"$T/koto.err"
echo "point 4: open --at manager: $(cat "$T/open-at.json")"
if [ "$(jq -r --arg id "$ID_PROV" '[.attempts[] | select(.id == $id) | .review.state] | join(",")' "$T/at.json" 2>/dev/null)" = "awaiting" ] \
    && [ "$(jq -r --arg id "$ID_PROV" '[.attempts[] | select(.id == $id) | .review.state] | join(",")' "$T/in.json" 2>/dev/null)" = "awaiting" ]; then
    pass "the provisional decision is listed for review, awaiting, in worker and from manager above it"
else
    fail "provisional review listing: $(cat "$T/at.json" "$T/in.json")"
fi
if [ "$(jq -r '.questions | length' "$T/open-at.json" 2>/dev/null)" = "0" ] \
    && ! grep -q "$ID_PROV" "$T/open-owner.json"; then
    pass "neither open --at manager nor open --person owner returns the provisional decision"
else
    fail "a provisional decision was listed as a question: $(cat "$T/open-at.json" "$T/open-owner.json")"
fi
koto decisions show worker "$ID_PROV" >"$T/show.txt" 2>>"$T/koto.err"
if grep -q 'cache_entries' "$T/show.txt" && grep -q 'cheap' "$T/show.txt" \
    && grep -q "only this branch's migration names it" "$T/show.txt" && grep -q 'unattended' "$T/show.txt"; then
    pass "the provisional entry shows the chosen option, cheap, the reason and the unattended run mode"
else
    fail "show worker $ID_PROV: $(cat "$T/show.txt")"
fi

att unattended --in worker --what "table name" --result provisional --undo costly \
    --undo-reason "only this branch's migration names it" --chosen cache_entries
rc_costly=$RC
msg_costly=$(jq -r '.error.message // empty' "$T/att.out" 2>/dev/null)
echo "point 5: costly: exit $rc_costly: $(out)"
att attended --in solo --what "table name" --result provisional --undo cheap \
    --undo-reason "only this branch's migration names it" --chosen cache_entries
rc_att=$RC
msg_att=$(jq -r '.error.message // empty' "$T/att.out" 2>/dev/null)
echo "point 5: attended solo: exit $rc_att: $(out)"
koto decisions attempts --at manager --result provisional --awaiting-review >"$T/at.json" 2>>"$T/koto.err"
n_prov=$(jq -r '.attempts | length' "$T/at.json" 2>/dev/null)
echo "point 5: listing holds $n_prov"
case "$msg_costly" in *"a costly choice is raised, not decided"*) c1=1 ;; *) c1=0 ;; esac
case "$msg_att" in *"an attended run asks"*) c2=1 ;; *) c2=0 ;; esac
if [ "$rc_costly" -eq 1 ] && [ "$c1" -eq 1 ] && [ "$rc_att" -eq 1 ] && [ "$c2" -eq 1 ] && [ "$n_prov" = "1" ]; then
    pass "provisional is refused when costly and when attended, and the listing still holds one entry"
else
    fail "provisional refusals: costly $rc_costly [$msg_costly], attended $rc_att [$msg_att], listing $n_prov"
fi

# --- unattended undecided: the undo test ---------------------------------------

att unattended --in worker --what "cache store" --result undecided --state implement:1
rc_none=$RC
att unattended --in worker --what "cache store" --result undecided --undo cheap --undo-reason "local only"
rc_cheap=$RC
msg_cheap=$(jq -r '.error.message // empty' "$T/att.out" 2>/dev/null)
att unattended --in worker --what "cache store" --result undecided --state implement:1 \
    --undo costly --undo-reason "the choice is published in the release notes"
ID_UNDEC=$(jq -r '.id // empty' "$T/att.out" 2>/dev/null)
echo "point 6: $(out)"
koto decisions show worker "$ID_UNDEC" >"$T/show.txt" 2>>"$T/koto.err"
echo "point 6: $(cat "$T/show.txt")"
case "$msg_cheap" in *"a cheap choice is decided provisionally"*) c3=1 ;; *) c3=0 ;; esac
if [ "$rc_none" -eq 1 ] && [ "$rc_cheap" -eq 1 ] && [ "$c3" -eq 1 ] && [ -n "$ID_UNDEC" ] \
    && grep -q 'undecided' "$T/show.txt" && grep -q 'implement:1' "$T/show.txt" \
    && grep -q 'costly' "$T/show.txt" && grep -q 'the choice is published in the release notes' "$T/show.txt"; then
    pass "an unattended undecided attempt records the undo test: none refused, cheap without a ground refused, costly kept"
else
    fail "unattended undecided: none $rc_none, cheap $rc_cheap [$msg_cheap], costly id [$ID_UNDEC]: $(cat "$T/show.txt")"
fi
att unattended --in worker --what "cache store" --result undecided \
    --undo cheap --undo-reason "local only" --ground reserved-step
ID_GROUND=$(jq -r '.id // empty' "$T/att.out" 2>/dev/null)
koto decisions show worker "$ID_GROUND" >"$T/show.txt" 2>>"$T/koto.err"
if [ "$RC" -eq 0 ] && grep -q 'reserved-step' "$T/show.txt"; then
    pass "a cheap undecided attempt with a ground is accepted and shows the ground"
else
    fail "cheap with ground: rc $RC: $(out) $(cat "$T/show.txt")"
fi

# --- raise rests only on an undecided attempt ---------------------------------

jq -n '{
    context: "The build cache is lost on every runner restart.",
    problem: "Two stores fit, and they differ in what an operator has to run.",
    question: "Which store should the build cache use?",
    options: [
        {label: "SQLite", reason: "One file beside the runner, no server to run."},
        {label: "Postgres", reason: "Shared across runners, but a server to keep up."}
    ],
    ground: "Picking a server changes what the team operates.",
    waiting: [],
    label: "build cache store"
}' > "$T/good.json"
"$SHIRABE" question raise --in solo --content "$T/good.json" --attempt "$ID_DECIDED" >"$T/r1" 2>&1
r_dec=$?
"$SHIRABE" question raise --in worker --content "$T/good.json" --attempt "$ID_PROV" >"$T/r2" 2>&1
r_prov=$?
"$SHIRABE" question raise --in solo --content "$T/good.json" --attempt "$ID_STATE" >"$T/r3" 2>&1
r_und=$?
if [ "$r_dec" -eq 1 ] && [ "$r_prov" -eq 1 ] && [ "$r_und" -eq 0 ]; then
    pass "raise takes the undecided attempt and refuses the decided and the provisional one"
else
    fail "raise on attempts: decided $r_dec, provisional $r_prov, undecided $r_und: $(cat "$T/r1" "$T/r2" "$T/r3")"
fi

# --- check-undecided.sh on the fixture ------------------------------------------

# load <session> <report_key> <key_dir> [<dir>]: the fixture's files as keys
load() {
    local s=$1 rk=$2 kd=$3 d=${4:-$FIX} k
    koto context add "$s" "$rk" --from-file "$d/report.md" >/dev/null 2>&1 || return 1
    for k in question.json context.md research.md alternatives.md; do
        [ -f "$d/$k" ] || continue
        koto context add "$s" "$kd/$k" --from-file "$d/$k" >/dev/null 2>&1 || return 1
    done
}
# chk <session> <report_key> -> output in $T/chk.out, exit in $RC
chk() {
    bash "$CHECK" "$1" "$2" >"$T/chk.out" 2>&1
    RC=$?
}

load worker work/decision_1_report.md work/decision-1 || { fail "could not load the fixture into worker"; finish; }
chk worker work/decision_1_report.md
echo "point 7: check: exit $RC: $(cat "$T/chk.out")"
if [ "$RC" -eq 0 ]; then
    pass "check-undecided.sh passes the undecided fixture"
else
    fail "check-undecided.sh on the fixture exited $RC: $(cat "$T/chk.out")"
fi

# Edited copies, each in its own session.
n=0
edited() {
    # edited <name> <part> <edit command on $E>
    local name=$1 part=$2 s
    n=$((n + 1))
    s="edit$n"
    E="$T/$s"
    rm -rf "$E"
    cp -R "$FIX" "$E"
    eval "$3"
    koto init "$s" --template "$T/two.md" >/dev/null 2>&1 || { fail "koto init $s"; return; }
    load "$s" work/decision_1_report.md work/decision-1 "$E" || { fail "load $s"; return; }
    if [ "$name" = "research removed" ]; then
        koto context remove "$s" work/decision-1/research.md >/dev/null 2>&1
    fi
    chk "$s" work/decision_1_report.md
    [ "$name" = "What Would Settle It removed" ] && echo "point 8: exit $RC: $(cat "$T/chk.out")"
    if [ "$RC" -eq 1 ] && grep -q "missing: $part" "$T/chk.out"; then
        pass "check-undecided.sh exits 1 naming $part: $name"
    else
        fail "check-undecided.sh on $name exited $RC: $(cat "$T/chk.out")"
    fi
}
edited "What Would Settle It removed" "What Would Settle It" \
    'awk "/^[*][*]What Would Settle It[*][*]/{skip=1} /^<!-- decision:end -->/{skip=0} !skip" "$E/report.md" > "$E/r" && mv "$E/r" "$E/report.md"'
edited "What Would Settle It empty" "What Would Settle It" \
    'awk "/^[*][*]What Would Settle It[*][*]/{print; skip=1; next} /^<!-- decision:end -->/{skip=0} !skip" "$E/report.md" > "$E/r" && mv "$E/r" "$E/report.md"'
edited "a Chosen section added" "chosen" \
    'awk "/^[*][*]What Would Settle It[*][*]/{print \"**Chosen: MIT**\"; print \"Picked anyway.\"; print \"\"} {print}" "$E/report.md" > "$E/r" && mv "$E/r" "$E/report.md"'
edited "a status other than undecided" "status" \
    'sed "s/status=\"undecided\"/status=\"escalated\"/" "$E/report.md" > "$E/r" && mv "$E/r" "$E/report.md"'
edited "a question with one option" "question" \
    'jq ".options = [.options[0]]" "$E/question.json" > "$E/q" && mv "$E/q" "$E/question.json"'
edited "an option with no reason" "question" \
    'jq ".options[1].reason = \"\"" "$E/question.json" > "$E/q" && mv "$E/q" "$E/question.json"'
edited "research removed" "research" ':'

# A settled report.
koto init settled --template "$T/two.md" >/dev/null 2>&1
cat > "$T/settled.md" <<'EOF'
<!-- decision:start id="package-licence" status="confirmed" -->
### Decision: Package licence

**Context**
The package wraps two MIT-licensed libraries.

**Assumptions**
- The owner wants no patent grant.

**Chosen: MIT**
The MIT licence.

**Rationale**
Matches the wrapped libraries.

**Alternatives Considered**
- **Apache-2.0**: permissive with a patent grant. Rejected because the owner wants none.

**Consequences**
One licence across the stack.
<!-- decision:end -->
EOF
koto context add settled work/report.md --from-file "$T/settled.md" >/dev/null 2>&1
chk settled work/report.md
if [ "$RC" -eq 3 ] && grep -q '^complete:' "$T/chk.out"; then
    pass "check-undecided.sh exits 3 on a settled report, saying the decision is complete"
else
    fail "check-undecided.sh on a settled report exited $RC: $(cat "$T/chk.out")"
fi

# --- the hand-off to raise --------------------------------------------------------

# handoff <session> <report_key> <question_key> <attempt id> <want recipient>
handoff() {
    local s=$1 rk=$2 qk=$3 id=$4 want=$5 identity got
    chk "$s" "$rk"
    if [ "$RC" -ne 0 ]; then
        fail "hand-off in $s: the check exited $RC: $(cat "$T/chk.out")"
        return
    fi
    koto context get "$s" "$qk" > "$T/q.json" 2>"$T/q.err" || { fail "hand-off in $s: koto context get $qk"; return; }
    "$SHIRABE" question raise --in "$s" --content - --attempt "$id" < "$T/q.json" >"$T/raise.out" 2>"$T/raise.err"
    RC=$?
    echo "hand-off from $s: exit $RC: $(cat "$T/raise.out" "$T/raise.err")"
    identity=$(jq -r '.identity // empty' "$T/raise.out" 2>/dev/null)
    got=$(jq -r '.recipient // empty' "$T/raise.out" 2>/dev/null)
    if [ "$RC" -ne 0 ] || [ -z "$identity" ] || [ "$got" != "$want" ]; then
        fail "hand-off in $s: raise exited $RC to [$got], wanted $want: $(cat "$T/raise.out" "$T/raise.err")"
        return
    fi
    # The stored form keeps the raiser's question as `ask` and composes
    # `question` from context, problem and ask (docs/guides/question-commands.md).
    koto decisions content read "$identity" > "$T/stored.json" 2>"$T/stored.err"
    echo "hand-off from $s: stored: $(cat "$T/stored.json")"
    if jq -e --slurpfile d "$FIX/question.json" '
            .context == $d[0].context and .problem == $d[0].problem
            and .ask == $d[0].question and .options == $d[0].options
            and .options[0].label == "MIT"
            and all(.options[]; (.reason | length) > 0)' "$T/stored.json" >/dev/null 2>&1; then
        pass "hand-off in $s: raised to $want, the stored question holds the decider's context, problem, question and options, the recommendation first"
    else
        fail "hand-off in $s: the stored question differs from the decider's: $(cat "$T/stored.json" "$T/stored.err")"
    fi
    keys_ok=1
    for k in context.md research.md alternatives.md; do
        kd=${qk%/question.json}
        koto context get "$s" "$kd/$k" >/dev/null 2>&1 || keys_ok=0
    done
    if [ "$keys_ok" -eq 1 ]; then
        pass "hand-off in $s: context.md, research.md and alternatives.md are still readable"
    else
        fail "hand-off in $s: a research key is gone"
    fi
}

handoff worker work/decision_1_report.md work/decision-1/question.json "$ID_UNDEC" session:manager
koto context get worker work/decision-1/research.md >"$T/research.out" 2>&1
echo "point 7: research: $(cat "$T/research.out")"

if [ -n "$CALLER" ]; then
    # The caller's own session: nothing dispatched it, so the question goes
    # to person:owner. A direct /decision keeps its report at work/report.md.
    CS="$CALLER-licence"
    koto init "$CS" --template "$T/two.md" >/dev/null 2>"$T/init.err" || { fail "koto init $CS: $(cat "$T/init.err")"; finish; }
    if [ "$CALLER" = "decision" ]; then
        RK=work/report.md KD=work
    else
        RK=work/decision_1_report.md KD=work/decision-1
    fi
    load "$CS" "$RK" "$KD" || { fail "could not load the fixture into $CS"; finish; }
    att unattended --in "$CS" --what "package licence" --result undecided \
        --undo costly --undo-reason "a published version's licence cannot be taken back"
    CID=$(jq -r '.id // empty' "$T/att.out" 2>/dev/null)
    [ -n "$CID" ] || { fail "attempt in $CS exited $RC: $(out)"; finish; }
    handoff "$CS" "$RK" "$KD/question.json" "$CID" person:owner
fi

finish
