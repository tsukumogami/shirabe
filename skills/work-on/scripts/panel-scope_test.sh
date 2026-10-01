#!/usr/bin/env bash
# panel-scope_test.sh -- sticky panel verdicts: which seats a retry re-runs
# Part of the work-on skill
#
# A blocking finding used to send a run back through all seven review seats.
# panel-scope.sh now keeps each seat's verdict in a ledger and decides, from
# git, which seats a retry actually needs. This suite pins both halves.
#
#   script cases -- panel-scope.sh against git fixtures, writing through a koto
#     stand-in on PATH that stores each key as a file. They need git and jq and
#     no engine, so they also run on the macOS bash 3.2 floor leg.
#
#   engine cases -- the shipped work-on.md driven through real koto sessions:
#     a QA retry whose fix touches nothing scrutiny or review cited walks
#     straight through both panels to a QA re-check, with no evidence submitted
#     at either; a fix that does touch their citations stops at scrutiny for a
#     re-run; and koto's state log records every panel visit in both. The QA
#     retry runs the clearing block extracted from phase-4c-qa.md, so the
#     shipped text is what's under test. Skipped with a note when koto is
#     absent, the way the other engine-backed suites skip.
#
# Every run isolates HOME and builds its own git fixtures under a temp
# directory.
#
# Usage: panel-scope_test.sh
#
# Exit codes:
#   0 -- all cases pass (engine cases may have been skipped without koto)
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/panel-scope.sh"
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
QA_PHASE="$SKILL_DIR/references/phases/phase-4c-qa.md"
PLUGIN_ROOT=$(cd "$SKILL_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }
command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT is missing or not executable" >&2; exit 1; }

WORKDIR=$(mktemp -d)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

export HOME="$WORKDIR/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main

# koto refuses a --var value outside ^[a-zA-Z0-9._/:@+ \-]*$; reach the
# checkout through a symlink when its own path falls outside that.
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@+\ -]*)
        ln -s "$PLUGIN_ROOT" "$WORKDIR/plugin"
        PLUGIN_ROOT="$WORKDIR/plugin"
        ;;
esac

# --- the koto stand-in ---------------------------------------------------------
#
# `koto context add|get|exists|remove <session> <key>` against
# $SHIM_STORE/<session>/<key>. `get` and `exists` exit 1 for an absent key, as
# koto does. A session named `fail-*` refuses writes, which is how exit 66 is
# reached.

SHIM_BIN="$WORKDIR/shim-bin"
SHIM_STORE="$WORKDIR/shim-store"
mkdir -p "$SHIM_BIN" "$SHIM_STORE"
cat > "$SHIM_BIN/koto" <<'SHIM'
#!/usr/bin/env bash
[ "$1" = context ] || { echo "koto shim: unsupported: $*" >&2; exit 2; }
f="$SHIM_STORE/$3/$4"
case "$2" in
    add)
        case "$3" in fail-*) echo "koto shim: refusing session $3" >&2; exit 9 ;; esac
        mkdir -p "$SHIM_STORE/$3"
        cat > "$f"
        ;;
    get)    [ -f "$f" ] || { echo "koto shim: no key $4" >&2; exit 1; }; cat "$f" ;;
    exists) [ -f "$f" ] ;;
    remove) rm -f "$f" ;;
    *) echo "koto shim: unsupported: $*" >&2; exit 2 ;;
esac
SHIM
chmod +x "$SHIM_BIN/koto"
export SHIM_STORE

# --- fixtures -----------------------------------------------------------------
#
# fixture <name>: a repository whose main holds src/a.sh and src/b.sh (lines
# "1".."40" each) and docs/c.md, with impl_base recorded at main's commit and
# one implementation commit on top that appends lines 41-50 to src/a.sh. The
# session is the fixture's name. SESSION and FX are set for the case.

FX=""
SESSION=""
fixture() {
    FX="$WORKDIR/fx-$1"
    SESSION="$1"
    mkdir -p "$FX/repo"
    (
        cd "$FX/repo" || exit 1
        git init -q -b main .
        mkdir -p src docs
        seq 1 40 > src/a.sh
        seq 1 40 > src/b.sh
        printf 'doc\n' > docs/c.md
        git add -A && git commit -q -m init
        git checkout -q -b "impl/$1"
        seq 1 50 > src/a.sh
        git commit -q -am "feat: impl"
    ) >/dev/null 2>&1
    mkdir -p "$SHIM_STORE/$SESSION"
    (cd "$FX/repo" && git rev-parse main) > "$SHIM_STORE/$SESSION/impl_base"
    printf 'AC: the issue body\n' > "$SHIM_STORE/$SESSION/context.md"
}

# edit <path> <line> <text>: replaces one line of a file and commits.
edit() {
    (cd "$FX/repo" && awk -v n="$2" -v t="$3" 'NR == n { print t; next } { print }' "$1" > "$1.new" \
        && mv "$1.new" "$1" && git commit -q -am "fix: $1:$2") >/dev/null 2>&1
}

RC=0
OUT=""
run() {
    OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" "$@" 2>"$WORKDIR/stderr")
    RC=$?
}

# record <panel> <json>: records one round through --record.
record() {
    printf '%s\n' "$2" > "$WORKDIR/round.json"
    run --record "$1" "$SESSION" "$WORKDIR/round.json"
    [ "$RC" -eq 0 ] || fail "setup: --record $1 exited $RC: $(cat "$WORKDIR/stderr")"
}

# decision <panel> <seat>: the seat's decision in the stored scope.
decision() {
    jq -r --arg s "$2" '.decisions[] | select(.seat == $s) | .decision' "$SHIM_STORE/$SESSION/$1_scope.json" 2>/dev/null
}
reason() {
    jq -r --arg s "$2" '.decisions[] | select(.seat == $s) | .reason' "$SHIM_STORE/$SESSION/$1_scope.json" 2>/dev/null
}

expect_decision() {
    # $1 label, $2 panel, $3 seat, $4 expected
    local got
    got=$(decision "$2" "$3")
    if [ "$got" = "$4" ]; then pass "$1: $3 is $4"; else fail "$1: $3 is [$got], expected $4 ($(reason "$2" "$3"))"; fi
}

expect_rc() {
    # $1 label, $2 expected
    if [ "$RC" -eq "$2" ]; then pass "$1: exit $2"; else fail "$1: exit $RC, expected $2 ($(cat "$WORKDIR/stderr"))"; fi
}

ALL_PASS='[{"seat":"completeness","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
           {"seat":"justification","blocking_count":0,"cited":[{"path":"src/a.sh"}]},
           {"seat":"intent","blocking_count":0}]'

echo "--- script: first round"

fixture first
run --plan scrutiny "$SESSION"
expect_rc "first --plan" 0
for s in completeness justification intent; do expect_decision "first round" scrutiny "$s" full; done
run --carried scrutiny "$SESSION"
expect_rc "first --carried (nothing carried)" 1
[ ! -f "$SHIM_STORE/$SESSION/scrutiny_results.json" ] \
    && pass "first round writes no results" || fail "first round wrote scrutiny_results.json"

echo "--- script: a fix away from every citation keeps passed seats and re-checks the finding"

fixture recheck
record scrutiny '[{"seat":"completeness","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
                  {"seat":"justification","blocking_count":0},
                  {"seat":"intent","blocking_count":1,"findings":[{"summary":"b.sh line 5 is wrong","path":"src/b.sh","lines":"5"}]}]'
JUDGED=$(cd "$FX/repo" && git rev-parse HEAD)
edit src/b.sh 5 five
run --plan scrutiny "$SESSION"
expect_decision "fix in b.sh" scrutiny completeness keep
# justification cited nothing: its scope is the diff it judged, src/a.sh only.
expect_decision "fix in b.sh" scrutiny justification keep
expect_decision "fix in b.sh" scrutiny intent recheck
GOT=$(jq -r '.decisions[] | select(.seat == "intent") | "\(.findings[0].summary)|\(.fix_diff_from)"' "$SHIM_STORE/$SESSION/scrutiny_scope.json")
[ "$GOT" = "b.sh line 5 is wrong|$JUDGED" ] \
    && pass "a re-check carries its finding and the fix diff's base" \
    || fail "re-check input is [$GOT], expected the finding and $JUDGED"
case "$(reason scrutiny justification)" in
    *"the diff it judged"*) pass "a seat that cited nothing is judged on the diff it reviewed" ;;
    *) fail "justification's reason does not say it fell back to the diff it judged: $(reason scrutiny justification)" ;;
esac
run --carried scrutiny "$SESSION"
expect_rc "--carried with a re-check pending" 1

echo "--- script: re-check passes; every seat then carries"

record scrutiny '[{"seat":"intent","blocking_count":0}]'
run --plan scrutiny "$SESSION"
for s in completeness justification intent; do expect_decision "after re-check" scrutiny "$s" keep; done
run --carried scrutiny "$SESSION"
expect_rc "--carried with every seat kept" 0
jq -e '.passed == true and .carried == true and (.seats | length == 3)' \
    "$SHIM_STORE/$SESSION/scrutiny_results.json" >/dev/null 2>&1 \
    && pass "carried results record each seat's reason" \
    || fail "scrutiny_results.json is not a carried verdict: $(cat "$SHIM_STORE/$SESSION/scrutiny_results.json" 2>/dev/null)"
# The re-check seat keeps the location of the finding it raised. The fix
# changed src/b.sh after line 5 was cited, so the range is carried as the bare
# path: its numbers no longer name the same code.
jq -e '.seats["scrutiny/intent"].finding_locations == [{"path": "src/b.sh"}]
       and .seats["scrutiny/intent"].cited == []' \
    "$SHIM_STORE/$SESSION/verdict_ledger.json" >/dev/null 2>&1 \
    && pass "a fixed finding's location stays with the seat, as a path once the file moved" \
    || fail "intent's ledger entry is $(jq -c '.seats["scrutiny/intent"] | {cited, finding_locations}' "$SHIM_STORE/$SESSION/verdict_ledger.json")"
edit docs/c.md 1 changed
run --carried scrutiny "$SESSION"
expect_rc "--carried after HEAD moves, before a new --plan" 1

echo "--- script: what counts as touching"

fixture lines
record scrutiny "$ALL_PASS"
edit src/a.sh 45 forty-five
run --plan scrutiny "$SESSION"
expect_decision "fix inside a cited range" scrutiny completeness rerun
expect_decision "fix in a cited path with no range" scrutiny justification rerun
expect_decision "fix in the diff a citeless seat judged" scrutiny intent rerun

fixture outside
record scrutiny "$ALL_PASS"
edit src/a.sh 3 three
run --plan scrutiny "$SESSION"
expect_decision "fix outside the cited range" scrutiny completeness keep
expect_decision "fix in a cited path with no range" scrutiny justification rerun

fixture insert
record scrutiny '[{"seat":"completeness","blocking_count":0,"cited":[{"path":"src/b.sh","lines":"10-12"}]}]'
(cd "$FX/repo" && awk 'NR == 12 { print; print "new"; next } { print }' src/b.sh > x && mv x src/b.sh && git commit -q -am ins) >/dev/null 2>&1
run --plan scrutiny "$SESSION"
expect_decision "insertion after the last cited line" scrutiny completeness rerun

fixture rename
record scrutiny '[{"seat":"completeness","blocking_count":0,"cited":[{"path":"src/b.sh","lines":"1-2"}]}]'
(cd "$FX/repo" && git mv src/b.sh src/moved.sh && git commit -q -m mv) >/dev/null 2>&1
run --plan scrutiny "$SESSION"
expect_decision "a renamed cited file" scrutiny completeness rerun

fixture ac
record scrutiny "$ALL_PASS"
printf 'AC: the issue body, amended\n' > "$SHIM_STORE/$SESSION/context.md"
run --plan scrutiny "$SESSION"
expect_decision "acceptance criteria changed, nothing committed" scrutiny completeness rerun

fixture big
record scrutiny "$ALL_PASS"
(cd "$FX/repo" && seq 1 300 > docs/c.md && git commit -q -am big) >/dev/null 2>&1
run --plan scrutiny "$SESSION"
expect_decision "fix over the line threshold, away from citations" scrutiny completeness rerun

fixture rewritten
record scrutiny "$ALL_PASS"
(cd "$FX/repo" && git reset -q --hard HEAD~1 && seq 1 50 > src/a.sh && echo x >> docs/c.md && git commit -q -am redo) >/dev/null 2>&1
run --plan scrutiny "$SESSION"
expect_decision "the judged commit was rewritten away" scrutiny completeness rerun

fixture nochange
record qa '[{"seat":"tester","blocking_count":0}]'
run --plan qa "$SESSION"
expect_decision "nothing committed since the verdict" qa tester keep

echo "--- script: a carried scope stays safe across a re-check"

# A range cited before a re-check is numbered against the old commit. A fix
# that shifts lines above it must not leave the stored range pointing at other
# code: an edit to the originally judged lines still re-runs the seat.
fixture shifted
record scrutiny '[{"seat":"completeness","blocking_count":1,"cited":[{"path":"src/b.sh","lines":"30-35"}],
                   "findings":[{"summary":"x","path":"src/a.sh","lines":"45"}]}]'
(cd "$FX/repo" && { seq 1 10 | sed 's/^/pre/'; cat src/b.sh; } > x && mv x src/b.sh \
    && awk 'NR == 45 { print "fixed"; next } { print }' src/a.sh > y && mv y src/a.sh \
    && git commit -q -am "fix: a.sh, shifting b.sh") >/dev/null 2>&1
record scrutiny '[{"seat":"completeness","blocking_count":0}]'
edit src/b.sh 42 changed     # the old line 32, inside the range first cited
run --plan scrutiny "$SESSION"
expect_decision "an edit to code cited before lines shifted" scrutiny completeness rerun

# A seat that cited nothing and blocked once still falls back to the whole diff
# it judged, rather than to its finding's location alone.
fixture citeless
record scrutiny '[{"seat":"intent","blocking_count":1,"findings":[{"summary":"x","path":"src/a.sh","lines":"41"}]}]'
edit src/a.sh 41 fixed
record scrutiny '[{"seat":"intent","blocking_count":0}]'
edit src/a.sh 2 elsewhere
run --plan scrutiny "$SESSION"
expect_decision "a once-blocked seat that cited nothing, fix elsewhere in its diff" scrutiny intent rerun

fixture dirty
record scrutiny "$ALL_PASS"
(cd "$FX/repo" && echo uncommitted >> docs/c.md)
run --plan scrutiny "$SESSION"
expect_decision "an uncommitted fix" scrutiny completeness rerun
(cd "$FX/repo" && git checkout -q docs/c.md)
record scrutiny "$ALL_PASS"
run --plan scrutiny "$SESSION"
(cd "$FX/repo" && echo uncommitted >> docs/c.md)
run --carried scrutiny "$SESSION"
expect_rc "--carried on a dirty tree, even with every seat kept" 1

fixture nocommits
(cd "$FX/repo" && git rev-parse HEAD) > "$SHIM_STORE/$SESSION/impl_base"
record scrutiny "$ALL_PASS"
run --plan scrutiny "$SESSION"
expect_decision "no commits since impl_base" scrutiny completeness rerun

fixture nobase
record scrutiny "$ALL_PASS"
rm -f "$SHIM_STORE/$SESSION/impl_base"
edit docs/c.md 1 changed
run --plan scrutiny "$SESSION"
expect_decision "impl_base unrecorded, where has_commits fails" scrutiny completeness rerun

fixture nofindings
record review '[{"seat":"architect","blocking_count":1}]'
edit docs/c.md 1 fixed
run --plan review "$SESSION"
expect_decision "a blocking seat that recorded no findings" review architect rerun

fixture plan
printf 'plan v1\n' > "$SHIM_STORE/$SESSION/plan.md"
record scrutiny "$ALL_PASS"
printf 'plan v2, scope expanded\n' > "$SHIM_STORE/$SESSION/plan.md"
run --plan scrutiny "$SESSION"
expect_decision "the plan was rewritten" scrutiny completeness rerun

echo "--- script: a blocking seat faces the same invalidation as a passed one"

fixture blockac
record scrutiny '[{"seat":"intent","blocking_count":1,"findings":[{"summary":"x","path":"src/a.sh","lines":"41"}]}]'
printf 'AC: amended\n' > "$SHIM_STORE/$SESSION/context.md"
edit src/a.sh 41 fixed
run --plan scrutiny "$SESSION"
expect_decision "a blocking seat after the criteria changed" scrutiny intent rerun

fixture blockbig
record scrutiny '[{"seat":"intent","blocking_count":1,"findings":[{"summary":"x","path":"src/a.sh","lines":"41"}]}]'
(cd "$FX/repo" && seq 1 300 > docs/c.md && git commit -q -am big) >/dev/null 2>&1
run --plan scrutiny "$SESSION"
expect_decision "a blocking seat whose fix crosses the threshold" scrutiny intent rerun

fixture blockdirty
record scrutiny '[{"seat":"intent","blocking_count":1,"findings":[{"summary":"x","path":"src/a.sh","lines":"41"}]}]'
(cd "$FX/repo" && echo uncommitted >> src/a.sh)
run --plan scrutiny "$SESSION"
expect_decision "a blocking seat with an uncommitted fix" scrutiny intent rerun

echo "--- script: --recorded holds a round whose record was skipped"

fixture recorded
run --plan scrutiny "$SESSION"
run --recorded scrutiny "$SESSION"
expect_rc "--recorded on a first round with no ledger" 0
record scrutiny '[{"seat":"intent","blocking_count":1,"findings":[{"summary":"x","path":"src/a.sh","lines":"41"}]},
                  {"seat":"completeness","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
                  {"seat":"justification","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]}]'
run --recorded scrutiny "$SESSION"
expect_rc "--recorded once the round is recorded" 0
edit src/a.sh 41 fixed
run --plan scrutiny "$SESSION"
run --recorded scrutiny "$SESSION"
expect_rc "--recorded before the re-check round is recorded" 1
grep -q "intent" "$WORKDIR/stderr" && pass "--recorded names the unrecorded seat" || fail "--recorded stderr: $(cat "$WORKDIR/stderr")"
record scrutiny '[{"seat":"intent","blocking_count":0},{"seat":"completeness","blocking_count":0},{"seat":"justification","blocking_count":0}]'
run --recorded scrutiny "$SESSION"
expect_rc "--recorded after the re-check round is recorded" 0
run --recorded bogus "$SESSION"
expect_rc "--recorded never exits outside 0/1 (bad panel)" 1
# A commit made while the panel is open is one no seat saw.
edit docs/c.md 1 mid-round
run --recorded scrutiny "$SESSION"
expect_rc "--recorded after HEAD moved since the scope was planned" 1
printf '[{"seat":"intent","blocking_count":0}]\n' > "$WORKDIR/round.json"
run --record scrutiny "$SESSION" "$WORKDIR/round.json"
expect_rc "--record refuses to stamp a commit the round never saw" 68

echo "--- script: the history counts rounds, not ticks"

fixture history
run --plan review "$SESSION"
run --plan review "$SESSION"
N=$(jq '[.history[] | select(.panel == "review")] | length' "$SHIM_STORE/$SESSION/verdict_ledger.json")
[ "$N" = 1 ] && pass "two ticks at one HEAD are one round" || fail "two ticks at one HEAD made $N history entries"
record review '[{"seat":"pragmatic","blocking_count":1,"findings":[{"summary":"x","path":"docs/c.md"}]},
                {"seat":"architect","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
                {"seat":"maintainer","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]}]'
edit docs/c.md 1 fixed
run --plan review "$SESSION"
GOT=$(jq -c '[.history[] | select(.panel == "review") | [.round, .spawned]]' "$SHIM_STORE/$SESSION/verdict_ledger.json")
[ "$GOT" = '[[1,3],[2,1]]' ] && pass "history records each round's spawn count" || fail "history is $GOT, expected [[1,3],[2,1]]"
jq -e '.history[-1].decisions | all(.reason | length > 0)' "$SHIM_STORE/$SESSION/verdict_ledger.json" >/dev/null 2>&1 \
    && pass "every decision in the history has a reason" || fail "a history decision has no reason"

echo "--- script: refusals"

fixture refusals
run --plan "" "$SESSION";            expect_rc "--plan with no panel" 67
run --plan bogus "$SESSION";         expect_rc "--plan with an unknown panel" 67
run --plan scrutiny;                 expect_rc "--plan with no session" 67
run --carried bogus "$SESSION";      expect_rc "--carried never exits outside 0/1 (bad panel)" 1
run --carried scrutiny;              expect_rc "--carried never exits outside 0/1 (no session)" 1
run --record scrutiny "$SESSION";    expect_rc "--record with no round file" 67
run --record scrutiny "$SESSION" "$WORKDIR/absent.json"; expect_rc "--record with a missing round file" 65
printf '{"seat":"intent"}\n' > "$WORKDIR/obj.json"
run --record scrutiny "$SESSION" "$WORKDIR/obj.json";    expect_rc "--record with a non-array round file" 65
printf '[{"seat":"pragmatic","blocking_count":0}]\n' > "$WORKDIR/wrong.json"
run --record scrutiny "$SESSION" "$WORKDIR/wrong.json";  expect_rc "--record with another panel's seat" 65
FAILSESSION=fail-write
mkdir -p "$SHIM_STORE/$FAILSESSION"
OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" --plan scrutiny "$FAILSESSION" 2>"$WORKDIR/stderr"); RC=$?
expect_rc "--plan when the context write fails" 66
OUT=$(cd "$WORKDIR" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" --plan scrutiny "$SESSION" 2>"$WORKDIR/stderr"); RC=$?
expect_rc "--plan outside a git repository" 64

# --- engine cases -------------------------------------------------------------

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- engine cases did not run"
    echo
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
fi

# Print the first ```bash fenced block in $1 that contains the substring $2.
extract_block() {
    awk -v marker="$2" '
        /^```bash$/  { inblk = 1; buf = ""; next }
        /^```$/ && inblk {
            if (index(buf, marker) > 0) { printf "%s", buf; exit }
            inblk = 0; buf = ""; next
        }
        inblk { buf = buf $0 "\n" }
    ' "$1"
}
QA_BLOCK=$(extract_block "$QA_PHASE" "koto context remove")
[ -n "$QA_BLOCK" ] || { fail "could not extract the retry block from phase-4c-qa.md"; }

NEXT_STATE=""
submit() {
    NEXT_STATE=$(koto next "$1" --with-data "$2" --no-cleanup 2>/dev/null \
        | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
}

# engine_to_qa_retry <session>: a fresh repository and session, walked to
# qa_validation with every scrutiny and review seat passing on src/a.sh:41-50,
# then a QA failure on a missing test, retried through the shipped block.
# Leaves the session at implementation, in $FX/repo.
engine_to_qa_retry() {
    local s="$1"
    fixture "$s"
    rm -rf "$SHIM_STORE/$s"
    cd "$FX/repo" || return 1
    koto init "$s" --template "$TEMPLATE" --var ARTIFACT_PREFIX=issue_42 --var ISSUE_NUMBER=42 \
        --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1 || { fail "$s: koto init failed"; return 1; }
    submit "$s" '{"mode":"issue_backed","issue_number":"42"}'
    submit "$s" '{"status":"override"}'
    submit "$s" '{"status":"override"}'
    submit "$s" '{"staleness_signal":"override"}'
    printf 'plan\n' | koto context add "$s" plan.md >/dev/null 2>&1
    printf 'AC: the issue body\n' | koto context add "$s" context.md >/dev/null 2>&1
    submit "$s" '{"plan_outcome":"plan_ready"}'
    git rev-parse main | koto context add "$s" impl_base >/dev/null 2>&1
    submit "$s" '{"implementation_status":"complete"}'
    [ "$NEXT_STATE" = issue_type_routing ] && submit "$s" '{"issue_type":"code"}'
    [ "$NEXT_STATE" = scrutiny ] || { fail "$s: walk stopped at [$NEXT_STATE] before scrutiny"; return 1; }

    printf '%s\n' '[{"seat":"completeness","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
        {"seat":"justification","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
        {"seat":"intent","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]}]' > "$WORKDIR/r.json"
    "$SCRIPT" --record scrutiny "$s" "$WORKDIR/r.json" || fail "$s: --record scrutiny failed"
    printf '{"passed": true, "round": 1}\n' | koto context add "$s" scrutiny_results.json >/dev/null 2>&1
    submit "$s" '{"scrutiny_outcome":"passed"}'
    [ "$NEXT_STATE" = review ] || { fail "$s: scrutiny went to [$NEXT_STATE], not review"; return 1; }

    printf '%s\n' '[{"seat":"pragmatic","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
        {"seat":"architect","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
        {"seat":"maintainer","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]}]' > "$WORKDIR/r.json"
    "$SCRIPT" --record review "$s" "$WORKDIR/r.json" || fail "$s: --record review failed"
    printf '{"passed": true, "round": 1}\n' | koto context add "$s" review_results.json >/dev/null 2>&1
    submit "$s" '{"review_outcome":"passed"}'
    [ "$NEXT_STATE" = qa_validation ] || { fail "$s: review went to [$NEXT_STATE], not qa_validation"; return 1; }

    printf '%s\n' '[{"seat":"tester","blocking_count":1,"cited":[{"path":"src/a.sh","lines":"41-50"}],
        "findings":[{"summary":"no test covers lines 41-50","path":"tests/a_test.sh"}]}]' > "$WORKDIR/r.json"
    "$SCRIPT" --record qa "$s" "$WORKDIR/r.json" || fail "$s: --record qa failed"
    printf '%s\n' "$QA_BLOCK" | sed "s|<WF>|$s|g" | sed 's/koto next \(.*\) --no-cleanup$/koto next \1 --no-cleanup >\/dev\/null 2>\&1/' | bash
    NEXT_STATE=$(koto status "$s" 2>/dev/null | jq -r '.current_state // empty')
    [ "$NEXT_STATE" = implementation ] || { fail "$s: the QA retry block left the run at [$NEXT_STATE]"; return 1; }
    return 0
}

visits() {
    # $1 session, $2 state: transitions into the state in koto's own log
    jq -s --arg st "$2" '[.[] | select(.type == "transitioned" and .payload.to == $st)] | length' \
        "$HOME/.koto/sessions/$1/koto-$1.state.jsonl" 2>/dev/null
}

echo "--- engine: a QA retry away from every citation skips scrutiny and review"

S=qa-narrow
if engine_to_qa_retry "$S"; then
    mkdir -p tests && printf 'test\n' > tests/a_test.sh && git add tests && git commit -q -m "test: cover a.sh"
    submit "$S" '{"implementation_status":"complete"}'
    [ "$NEXT_STATE" = issue_type_routing ] && submit "$S" '{"issue_type":"code"}'
    if [ "$NEXT_STATE" = qa_validation ]; then
        pass "the run went from issue_type_routing to qa_validation with no panel evidence"
    else
        fail "the run stopped at [$NEXT_STATE], expected qa_validation"
    fi
    for k in scrutiny review; do
        koto context get "$S" "${k}_results.json" 2>/dev/null | jq -e '.carried == true' >/dev/null 2>&1 \
            && pass "$k carried its verdict" || fail "$k has no carried ${k}_results.json"
    done
    GOT=$(koto context get "$S" qa_scope.json 2>/dev/null | jq -r '.decisions[0] | "\(.decision)|\(.findings[0].summary)"')
    [ "$GOT" = "recheck|no test covers lines 41-50" ] \
        && pass "QA re-checks its finding" || fail "qa_scope.json is [$GOT]"
    GOT=$(koto context get "$S" verdict_ledger.json 2>/dev/null \
        | jq -c '[.history[] | select(.round == 2) | [.panel, .spawned]]')
    [ "$GOT" = '[["scrutiny",0],["review",0],["qa",1]]' ] \
        && pass "round 2 spawned one seat: the QA re-check" || fail "round 2 history is $GOT"
    for st in scrutiny review qa_validation; do
        N=$(visits "$S" "$st")
        [ "$N" = 2 ] && pass "koto's log records both $st rounds" || fail "koto's log has $N transitions into $st, expected 2"
    done
    # The re-check passes, but its verdict isn't recorded: qa_recorded holds.
    printf '{"passed": true, "round": 2}\n' | koto context add "$S" qa_results.json >/dev/null 2>&1
    submit "$S" '{"qa_outcome":"passed"}'
    [ "$NEXT_STATE" = qa_validation ] \
        && pass "an unrecorded re-check holds qa_validation" \
        || fail "an unrecorded re-check advanced to [$NEXT_STATE]"
    printf '[{"seat":"tester","blocking_count":0}]\n' > "$WORKDIR/r.json"
    "$SCRIPT" --record qa "$S" "$WORKDIR/r.json" || fail "$S: --record qa failed"
    submit "$S" '{"qa_outcome":"passed"}'
    [ "$NEXT_STATE" = verification ] \
        && pass "the recorded re-check advances to verification" \
        || fail "the recorded re-check went to [$NEXT_STATE]"
fi

echo "--- engine: a fix on cited lines re-runs the panels"

S=qa-wide
if engine_to_qa_retry "$S"; then
    awk 'NR == 45 { print "forty-five"; next } { print }' src/a.sh > x && mv x src/a.sh && git commit -q -am "fix: a.sh"
    submit "$S" '{"implementation_status":"complete"}'
    [ "$NEXT_STATE" = issue_type_routing ] && submit "$S" '{"issue_type":"code"}'
    [ "$NEXT_STATE" = scrutiny ] && pass "the run stops at scrutiny" || fail "the run went to [$NEXT_STATE], expected scrutiny"
    GOT=$(koto context get "$S" scrutiny_scope.json 2>/dev/null | jq -r '[.decisions[].decision] | unique | join(",")')
    [ "$GOT" = rerun ] && pass "every scrutiny seat re-runs" || fail "scrutiny decisions are [$GOT]"
    koto context exists "$S" scrutiny_results.json 2>/dev/null \
        && fail "a scrutiny verdict is in place while seats must re-run" \
        || pass "no scrutiny verdict stands in for the re-run"
fi
cd "$WORKDIR" || exit 1

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
