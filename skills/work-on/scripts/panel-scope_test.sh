#!/usr/bin/env bash
# panel-scope_test.sh -- the findings ledger: what a retry re-verifies
# Part of the work-on skill
#
# A blocking finding used to send a run back through all seven review seats.
# panel-scope.sh now keeps every finding in a ledger with the records written
# about it, plans a retry over the findings a fix made due, and passes a panel
# only on closing records. This suite pins all three.
#
#   script cases -- panel-scope.sh against git fixtures, writing through a koto
#     stand-in on PATH that stores each key as a file. They need git and jq and
#     no engine, so they also run on the macOS bash 3.2 floor leg.
#
#   engine cases -- the shipped work-on.md driven through real koto sessions:
#     a QA retry stops at scrutiny for one fix-diff review, carries review, and
#     re-verifies QA's finding by id; a fix on cited lines still stops at
#     scrutiny for one run, not a re-run of its seats; and koto's state log
#     records every panel visit. The QA
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
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

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

WORKDIR=$(mktemp -d) || exit 1
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
ktg_on_exit cleanup

# Every finding --verdict prints is logged and verified against the rule
# registry at the end.
# shellcheck source=../../../scripts/lib/rule-findings-testlib.sh
. "$SCRIPT_DIR/../../../scripts/lib/rule-findings-testlib.sh"
# shellcheck source=../../../scripts/lib/panel-round-testlib.sh
. "$SCRIPT_DIR/../../../scripts/lib/panel-round-testlib.sh"
rf_test_setup "$WORKDIR"

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
# `koto session dir <s>` names a directory a case may hold a fixture log in; a
# session named `sdfail-*` makes it fail, as a session-store error would.
if [ "$1" = session ] && [ "$2" = dir ]; then
    case "$3" in sdfail-*) echo "koto shim: the session store is unavailable" >&2; exit 3 ;; esac
    echo "$SHIM_STORE/$3/sessiondir"; exit 0
fi
# review-level.sh report asks for a session's overrides; none here.
if [ "$1" = overrides ] && [ "$2" = list ]; then echo '{}'; exit 0; fi
[ "$1" = context ] || { echo "koto shim: unsupported: $*" >&2; exit 2; }
f="$SHIM_STORE/$3/$4"
# SHIM_RACE: every read of the ledger after the first returns it one revision
# on, as if another write had landed in between.
if [ -n "${SHIM_RACE:-}" ] && [ "$2" = get ] && [ "$4" = verdict_ledger.json ] && [ -f "$f" ]; then
    if [ -f "$SHIM_STORE/$3/.raced" ]; then jq '.rev += 1' "$f"; exit 0; fi
    : > "$SHIM_STORE/$3/.raced"
fi
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
# Every run in a round file names its run id. --plan mints one per decision it
# spawns; run() gives each seat entry that has none the run its decision in the
# stored scope names, or a fresh one when the scope names none, so the cases
# about which seats run and what a verdict carries don't each have to.
# NO_AUTORUN=1 turns it off for the cases about the run ids themselves.
RUNSEQ=0
autorun() {
    # $1 round file, $2 panel (optional): the scope to take minted runs from
    local scope='{}'
    RUNSEQ=$((RUNSEQ + 1))
    if [ -n "${2:-}" ] && [ -f "$SHIM_STORE/$SESSION/$2_scope.json" ]; then
        scope=$(cat "$SHIM_STORE/$SESSION/$2_scope.json")
        printf '%s' "$scope" | jq -e 'type == "object"' >/dev/null 2>&1 || scope='{}'
    fi
    jq --arg n "$RUNSEQ" --argjson s "$scope" 'if type == "array" then map(. as $e
        | if type == "object" and has("seat") and (has("run") | not)
          then .run = ([($s.decisions // [])[] | select(.seat == $e.seat) | .run // empty][0] // "test-\($n)-\(.seat)")
          else . end) else . end' "$1" > "$1.runs" 2>/dev/null \
        && mv "$1.runs" "$1"
}
run() {
    if [ "${1:-}" = --record ] && [ -f "${4:-}" ] && [ -z "${NO_AUTORUN:-}" ]; then
        autorun "$4" "$2"
    fi
    OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" "$@" 2>"$WORKDIR/stderr")
    RC=$?
}

# same_laddered <label> --verdict <panel> <session>: the run with the escalation ladder's context
# (a session log where koto recorded <panel>_verdict failing once on
# panel/open-finding) exits and prints on standard output exactly what the run
# without it does, and adds no ::shirabe- line to stderr when it printed no
# finding.
same_laddered() {
    local label=$1 plain_out plain_rc log="$WORKDIR/ladder-same.jsonl"
    shift
    run "$@"; plain_out=$OUT; plain_rc=$RC
    rf_test_ladder_log "$log" "$2" "${2}_verdict" panel/open-finding 1
    OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" SHIRABE_GATE_LOG="$log" SHIRABE_GATE_NAME="${2}_verdict" \
        SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" \
        "$SCRIPT" "$@" 2>"$WORKDIR/stderr")
    RC=$?
    if [ "$RC" -eq "$plain_rc" ] && [ "$OUT" = "$plain_out" ] \
        && { case "$OUT" in *::koto-finding::*) true ;; *) ! grep -q '^::shirabe-' "$WORKDIR/stderr" ;; esac; }; then
        pass "$label: exits and prints the same with the ladder's context"
    else
        fail "$label: differs with the ladder's context: rc $RC vs $plain_rc, stderr $(cat "$WORKDIR/stderr")"
    fi
}

# packet <args>: runs review-packet.sh in the fixture, against the same koto
# stand-in, with the packet in a private scratch directory as a run's own.
# Sets POUT (the packet path) and PRC.
PACKET_SH="$PLUGIN_ROOT/scripts/review-packet.sh"
PRC=0
POUT=""
mkdir -p "$WORKDIR/ptmp"
mkdir -m 700 "$WORKDIR/pscratch"
packet() {
    POUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" TMPDIR="$WORKDIR/ptmp" "$PACKET_SH" "$@" --scratch "$WORKDIR/pscratch" 2>"$WORKDIR/pstderr")
    PRC=$?
}

# record <panel> <json>: records one round through --record.
record() {
    printf '%s\n' "$2" > "$WORKDIR/round.json"
    run --record "$1" "$SESSION" "$WORKDIR/round.json"
    [ "$RC" -eq 0 ] || fail "setup: --record $1 exited $RC: $(cat "$WORKDIR/stderr")"
}
# plan_record <panel> <json>: plans the round, then records it.
plan_record() {
    run --plan "$1" "$SESSION"
    [ "$RC" -eq 0 ] || fail "setup: --plan $1 exited $RC: $(cat "$WORKDIR/stderr")"
    record "$1" "$2"
}

# fid <panel> <seat>: the id of the first unclosed finding the seat raised.
fid() {
    jq -r --arg k "$1/$2" '.seats[$k].findings[0].id // empty' "$SHIM_STORE/$SESSION/verdict_ledger.json"
}
# sid <summary>: the id of the finding with that summary.
sid() {
    jq -r --arg s "$1" '[.findings[] | select(.summary == $s)][0].id // empty' "$SHIM_STORE/$SESSION/verdict_ledger.json"
}
# reverify <panel> <id> <reason>: the panel's re-verifier closes a finding.
reverify() {
    record "$1" "[{\"seat\":\"reverifier\",\"answers\":[{\"id\":\"$2\",\"record\":\"reverified\",\"reason\":\"$3\"}]}]"
}

# decision <panel> <seat>: the seat's decision in the stored scope.
decision() {
    jq -r --arg s "$2" '.decisions[] | select(.seat == $s) | .decision' "$SHIM_STORE/$SESSION/$1_scope.json" 2>/dev/null
}
reason() {
    jq -r --arg s "$2" '.decisions[] | select(.seat == $s) | .reason' "$SHIM_STORE/$SESSION/$1_scope.json" 2>/dev/null
}
# due <panel>: the ids the re-verifier was given, space-separated, sorted.
due() {
    jq -r '[.decisions[] | select(.seat == "reverifier") | .findings[].id] | sort | join(" ")' \
        "$SHIM_STORE/$SESSION/$1_scope.json" 2>/dev/null
}
# spawned <panel>: the runs the stored scope plans.
spawned() {
    jq -r '[.decisions[] | select(.decision != "keep")] | length' "$SHIM_STORE/$SESSION/$1_scope.json" 2>/dev/null
}
# scope_full <panel>: whether the stored scope is a full round, and why.
scope_full() {
    jq -r '"\(.full)|\(.reason)"' "$SHIM_STORE/$SESSION/$1_scope.json" 2>/dev/null
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

# expect_full <label> <panel> <reason substring>: the stored scope is a full
# round for that reason, with every real seat full and no fix-diff review.
expect_full() {
    local got
    got=$(scope_full "$2")
    case "$got" in
        "true|"*"$3"*) pass "$1: a full round ($3)" ;;
        *) fail "$1: scope is [$got], expected a full round for [$3]" ;;
    esac
    jq -e 'all(.decisions[]; .seat == "reverifier" or .decision == "full")
           and all(.decisions[]; (.fix_review // false) == false)' \
        "$SHIM_STORE/$SESSION/$2_scope.json" >/dev/null 2>&1 \
        && pass "$1: every seat is full, and no fix-diff review is planned" \
        || fail "$1: decisions $(jq -c '[.decisions[] | {seat, decision, fix_review}]' "$SHIM_STORE/$SESSION/$2_scope.json")"
}
expect_not_full() {
    local got
    got=$(scope_full "$2")
    case "$got" in
        "false|"*) pass "$1: not a full round" ;;
        *) fail "$1: scope is [$got], expected a round that is not full" ;;
    esac
}

ALL_PASS='[{"seat":"completeness","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
           {"seat":"justification","blocking_count":0,"cited":[{"path":"src/a.sh"}]},
           {"seat":"intent","blocking_count":0}]'
REVIEW_PASS='[{"seat":"pragmatic"},{"seat":"architect"},{"seat":"maintainer"}]'

echo "--- script: first round"

fixture first
run --plan scrutiny "$SESSION"
expect_rc "first --plan" 0
for s in completeness justification intent; do expect_decision "first round" scrutiny "$s" full; done
expect_full "first round" scrutiny "first round"
GOT=$(jq -r '[.decisions[].run] | join(",")' "$SHIM_STORE/$SESSION/scrutiny_scope.json")
[ "$GOT" = "scrutiny-r1-completeness,scrutiny-r1-justification,scrutiny-r1-intent" ] \
    && pass "every run of the round is minted" || fail "minted runs are [$GOT]"
run --carried scrutiny "$SESSION"
expect_rc "first --carried (nothing carried)" 1
[ ! -f "$SHIM_STORE/$SESSION/scrutiny_results.json" ] \
    && pass "first round writes no results" || fail "first round wrote scrutiny_results.json"
for p in review qa light; do
    run --plan "$p" "$SESSION"
    jq -e 'all(.decisions[]; .decision == "full") and .full' "$SHIM_STORE/$SESSION/${p}_scope.json" >/dev/null 2>&1 \
        && pass "the $p panel's first round plans every seat full" || fail "$p first round: $(cat "$SHIM_STORE/$SESSION/${p}_scope.json")"
done

echo "--- script: a fix re-verifies only the finding it touched, in one run"

fixture recheck
plan_record scrutiny '[{"seat":"completeness","cited":[{"path":"src/a.sh","lines":"41-50"}]},
                       {"seat":"justification"},
                       {"seat":"intent","findings":[{"severity":"blocking","summary":"b.sh line 5 is wrong","path":"src/b.sh","lines":"5"}]}]'
JUDGED=$(cd "$FX/repo" && git rev-parse HEAD)
INTENT_F=$(fid scrutiny intent)
edit src/b.sh 5 five
run --plan scrutiny "$SESSION"
expect_not_full "fix in b.sh" scrutiny
for s in completeness justification intent; do expect_decision "fix in b.sh" scrutiny "$s" keep; done
GOT=$(jq -r '.decisions[] | select(.seat == "reverifier")
    | "\(.decision)|\([.findings[].id] | join(","))|\(.findings[0].summary)|\(.fix_diff_from)|\(.fix_review)|\(.review_from)|\(.run)"' \
    "$SHIM_STORE/$SESSION/scrutiny_scope.json")
[ "$GOT" = "recheck|$INTENT_F|b.sh line 5 is wrong|$JUDGED|true|$JUDGED|scrutiny-r2-reverifier" ] \
    && pass "one re-verifier run carries the touched finding by id, the fix diff's base and the fix-diff review" \
    || fail "re-verifier decision is [$GOT]"
[ "$(spawned scrutiny)" = 1 ] && pass "the retry round plans one run" || fail "the retry round plans $(spawned scrutiny) runs"
run --carried scrutiny "$SESSION"
expect_rc "--carried with a re-verification pending" 1

echo "--- script: the re-verifier's packet is its finding and the fix diff"

packet recheck --session "$SESSION" --panel scrutiny --seat reverifier
if [ "$PRC" -eq 0 ] && [ -f "$POUT" ]; then
    grep -q "^fix diff from: $JUDGED (fix_diff_from)\$" "$POUT" \
        && pass "the packet's diff starts where the finding was judged" \
        || fail "the packet's diff base is $(grep '^fix diff from:' "$POUT")"
    grep -q '"summary": "b.sh line 5 is wrong"' "$POUT" \
        && pass "the packet carries the finding the scope planned" || fail "the packet has no finding"
    grep -q "\"id\": \"$INTENT_F\"" "$POUT" \
        && pass "the packet names the finding by id" || fail "the packet does not name $INTENT_F"
    grep -q '^M	src/b.sh$' "$POUT" && grep -q '^+five$' "$POUT" && ! grep -q 'src/a.sh' "$POUT" \
        && pass "the packet's diff is the fix alone, not the implementation" \
        || fail "the packet's diff is not the fix diff"
    ! grep -q '^AC: the issue body$' "$POUT" \
        && pass "the packet leaves out the criteria the seats judged last round" \
        || fail "the packet carries the acceptance criteria"
    rm -f "$POUT"
else
    fail "review-packet.sh recheck exited $PRC: $(cat "$WORKDIR/pstderr")"
fi
packet recheck --session "$SESSION" --panel scrutiny --seat completeness
[ "$PRC" -eq 64 ] && pass "a kept seat gets no re-check packet: exit 64" \
    || fail "a kept seat's re-check packet exited $PRC"

# A scope with no fix_diff_from: the packet still carries the fix, from
# impl_base, and says so.
cp "$SHIM_STORE/$SESSION/scrutiny_scope.json" "$WORKDIR/scope.keep"
jq '(.decisions[] | select(.seat == "reverifier")) |= del(.fix_diff_from)' \
    "$WORKDIR/scope.keep" > "$SHIM_STORE/$SESSION/scrutiny_scope.json"
packet recheck --session "$SESSION" --panel scrutiny --seat reverifier
if [ "$PRC" -eq 0 ] && grep -q '^fix diff from: .*(fallback: the scope has no fix_diff_from; impl_base)$' "$POUT" \
    && grep -q '^+five$' "$POUT"; then
    pass "a scope with no fix_diff_from falls back to impl_base and still carries the fix"
else
    fail "no fix_diff_from: exit $PRC: $(cat "$WORKDIR/pstderr")"
fi
[ "$PRC" -eq 0 ] && rm -f "$POUT"
cp "$WORKDIR/scope.keep" "$SHIM_STORE/$SESSION/scrutiny_scope.json"

echo "--- script: the re-verifier closes the finding, and the round stands"

reverify scrutiny "$INTENT_F" "line 5 now reads five"
jq -e --arg id "$INTENT_F" '.findings[$id].records[-1].kind == "reverified"
       and .seats["scrutiny/intent"].verdict == "passed"' "$SHIM_STORE/$SESSION/verdict_ledger.json" >/dev/null 2>&1 \
    && pass "a reverified answer closes the finding, and its seat passes" \
    || fail "after the re-check: $(jq -c --arg id "$INTENT_F" '.findings[$id].records' "$SHIM_STORE/$SESSION/verdict_ledger.json")"
cp "$SHIM_STORE/$SESSION/scrutiny_scope.json" "$WORKDIR/scope.before"
run --plan scrutiny "$SESSION"
cmp -s "$WORKDIR/scope.before" "$SHIM_STORE/$SESSION/scrutiny_scope.json" \
    && pass "a recorded round at the same HEAD stands on a re-plan" || fail "the recorded round was re-planned"
run --recorded scrutiny "$SESSION"
expect_rc "--recorded once the re-verifier is recorded" 0
run --verdict scrutiny "$SESSION"
expect_rc "--verdict once the only blocking finding is closed" 0
same_laddered "--verdict, laddered, on a passing panel" --verdict scrutiny "$SESSION"

echo "--- script: a panel carries only when nothing is due, no fix-diff review lands, and nothing is open"

fixture carry
plan_record scrutiny "$ALL_PASS"
plan_record review "$REVIEW_PASS"
edit src/a.sh 45 forty-five
run --plan scrutiny "$SESSION"
[ "$(due scrutiny)" = "" ] && [ "$(spawned scrutiny)" = 1 ] \
    && jq -e '.decisions[] | select(.seat == "reverifier") | .fix_review == true' "$SHIM_STORE/$SESSION/scrutiny_scope.json" >/dev/null \
    && pass "with nothing due, the first panel entered still plans the fix-diff review" \
    || fail "scrutiny scope: $(cat "$SHIM_STORE/$SESSION/scrutiny_scope.json")"
expect_decision "a passed seat whose cited lines the fix touched" scrutiny completeness keep
expect_decision "a passed seat whose cited file the fix touched" scrutiny justification keep
record scrutiny '[{"seat":"reverifier"}]'
run --plan review "$SESSION"
[ "$(spawned review)" = 0 ] && pass "the next panel in the retry plans no run: the fix-diff review was recorded" \
    || fail "review scope: $(cat "$SHIM_STORE/$SESSION/review_scope.json")"
run --carried review "$SESSION"
expect_rc "--carried with nothing due and nothing open" 0
jq -e '.passed == true and .carried == true and (.seats | length == 3)' \
    "$SHIM_STORE/$SESSION/review_results.json" >/dev/null 2>&1 \
    && pass "carried results record each seat's reason" \
    || fail "review_results.json is not a carried verdict: $(cat "$SHIM_STORE/$SESSION/review_results.json" 2>/dev/null)"
run --verdict review "$SESSION"
expect_rc "--verdict on a carried round" 0
edit docs/c.md 1 changed
run --carried review "$SESSION"
expect_rc "--carried after HEAD moves, before a new --plan" 1

echo "--- script: an untouched open finding plans no run and still blocks"

fixture untouched
plan_record scrutiny "$ALL_PASS"
plan_record review '[{"seat":"pragmatic","findings":[{"severity":"blocking","summary":"c.md says too little","path":"docs/c.md"}]},
                     {"seat":"architect"},{"seat":"maintainer"}]'
edit src/a.sh 45 forty-five
run --plan scrutiny "$SESSION"
record scrutiny '[{"seat":"reverifier"}]'
run --plan review "$SESSION"
[ "$(spawned review)" = 0 ] && pass "an untouched open finding costs no run" \
    || fail "review scope: $(cat "$SHIM_STORE/$SESSION/review_scope.json")"
run --carried review "$SESSION"
expect_rc "--carried with an untouched open finding" 1
run --recorded review "$SESSION"
expect_rc "--recorded with no run planned" 0
run --verdict review "$SESSION"
expect_rc "--verdict with an untouched open finding and no run" 1
# The escalation ladder: koto already recorded review_verdict failing once on
# the finding's rule, so the template's context releases that rule's text,
# adds its full delivery marker on stdout, and changes nothing else about the
# verdict.
PLAIN_OUT=$OUT; PLAIN_RC=$RC
LADDER_RULE=$(printf '%s\n' "$OUT" | sed -n 's/^::koto-finding:://p' | jq -r '.rule_id')
LADDER_RULE=${LADDER_RULE%%$'\n'*}
LADDER_LOG="$WORKDIR/ladder.jsonl"
rf_test_ladder_log "$LADDER_LOG" review review_verdict "$LADDER_RULE" 1
OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" SHIRABE_GATE_LOG="$LADDER_LOG" SHIRABE_GATE_NAME=review_verdict \
    SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" \
    "$SCRIPT" --verdict review "$SESSION" 2>"$WORKDIR/stderr")
RC=$?
WANT_OUT="$PLAIN_OUT
::koto-rule-delivered::{\"rule_id\":\"$LADDER_RULE\",\"extent\":\"full\",\"delivery\":\"printed\"}"
if [ -n "$LADDER_RULE" ] && [ "$RC" -eq "$PLAIN_RC" ] && [ "$OUT" = "$WANT_OUT" ] \
    && [ "$(grep -c "^::shirabe-rule::{\"rule_id\":\"$LADDER_RULE\"" "$WORKDIR/stderr")" -eq 1 ]; then
    pass "--verdict, laddered: a second failure releases $LADDER_RULE's text and changes nothing else"
else
    fail "--verdict, laddered: rule [$LADDER_RULE] rc $RC, stderr $(cat "$WORKDIR/stderr")"
fi
if [ -f "$SHIM_STORE/$SESSION/review_results.json" ] \
    && [ "$(jq -r '.head' "$SHIM_STORE/$SESSION/review_results.json")" = "$(cd "$FX/repo" && git rev-parse HEAD)" ]; then
    fail "carried results written for a panel with an open finding: $(cat "$SHIM_STORE/$SESSION/review_results.json")"
else
    pass "no carried results are written for a panel with an open finding"
fi

echo "--- script: two due findings, one run"

fixture twodue
plan_record scrutiny '[{"seat":"completeness","findings":[{"severity":"blocking","summary":"one","path":"src/b.sh","lines":"5"}]},
                       {"seat":"justification","findings":[{"severity":"blocking","summary":"two","path":"src/b.sh","lines":"20"}]},
                       {"seat":"intent"}]'
(cd "$FX/repo" && awk 'NR == 5 || NR == 20 { print "fixed"; next } { print }' src/b.sh > x && mv x src/b.sh \
    && git commit -q -am "fix: both") >/dev/null 2>&1
run --plan scrutiny "$SESSION"
WANT=$(printf '%s\n%s\n' "$(sid one)" "$(sid two)" | sort | tr '\n' ' ' | sed 's/ $//')
[ "$(spawned scrutiny)" = 1 ] && [ "$(due scrutiny)" = "$WANT" ] \
    && pass "two due findings are planned as one run carrying both ids" \
    || fail "spawned $(spawned scrutiny), due [$(due scrutiny)], want [$WANT]"

echo "--- script: the saving, on three seats each blocking in its own file"

fixture saving
plan_record scrutiny '[{"seat":"completeness","findings":[{"severity":"blocking","summary":"a.sh is wrong","path":"src/a.sh","lines":"45"}]},
                       {"seat":"justification","findings":[{"severity":"blocking","summary":"b.sh is wrong","path":"src/b.sh","lines":"5"}]},
                       {"seat":"intent","findings":[{"severity":"blocking","summary":"c.md is wrong","path":"docs/c.md"}]}]'
# The rule this replaces re-checked every blocking seat: the seats the round-1
# ledger records as blocking are the runs it would have spawned.
OLD=$(jq '[.seats[] | select(.panel == "scrutiny" and .verdict == "blocking")] | length' "$SHIM_STORE/$SESSION/verdict_ledger.json")
edit src/b.sh 5 five
run --plan scrutiny "$SESSION"
GOT=$(jq -c '[.history[] | select(.panel == "scrutiny")] | last | [.round, .spawned, [.decisions[] | select(.decision != "keep") | .findings]]' \
    "$SHIM_STORE/$SESSION/verdict_ledger.json")
[ "$GOT" = "[2,1,[[\"$(sid 'b.sh is wrong')\"]]]" ] \
    && pass "round two records spawned 1, and its one decision lists exactly the touched finding" \
    || fail "round two history is $GOT"
[ "$OLD" = 3 ] && pass "the seat-level rule would have spawned 3 on the same fixture" || fail "the seat-level count is $OLD"

echo "--- script: what counts as touching a finding's location"

# touch_case <label> <finding json> <fix command> <due|not-due>
TC=0
touch_case() {
    TC=$((TC + 1))
    fixture "touch-$TC"
    plan_record scrutiny "[{\"seat\":\"completeness\",\"findings\":[$2]},{\"seat\":\"justification\"},{\"seat\":\"intent\"}]"
    local id
    id=$(fid scrutiny completeness)
    (cd "$FX/repo" && eval "$3" && git commit -q -am "fix") >/dev/null 2>&1
    run --plan scrutiny "$SESSION"
    case "$4:$(due scrutiny)" in
        "due:$id"|"not-due:") pass "$1: $4" ;;
        *) fail "$1: due is [$(due scrutiny)], expected $4 ($id)" ;;
    esac
}
touch_case "a lines finding, a fix inside its range" \
    '{"severity":"blocking","summary":"x","path":"src/b.sh","lines":"10-12"}' \
    "awk 'NR == 11 { print \"eleven\"; next } { print }' src/b.sh > x && mv x src/b.sh" due
touch_case "a lines finding, a fix elsewhere in the same file" \
    '{"severity":"blocking","summary":"x","path":"src/b.sh","lines":"10-12"}' \
    "awk 'NR == 40 { print \"forty\"; next } { print }' src/b.sh > x && mv x src/b.sh" not-due
touch_case "a lines finding, an insertion right after its range" \
    '{"severity":"blocking","summary":"x","path":"src/b.sh","lines":"10-12"}' \
    "awk 'NR == 12 { print; print \"new\"; next } { print }' src/b.sh > x && mv x src/b.sh" due
touch_case "a file finding, a fix anywhere in the file" \
    '{"severity":"blocking","summary":"x","path":"src/b.sh"}' \
    "awk 'NR == 40 { print \"forty\"; next } { print }' src/b.sh > x && mv x src/b.sh" due
touch_case "a finding on a renamed file" \
    '{"severity":"blocking","summary":"x","path":"src/b.sh","lines":"1-2"}' \
    "git mv src/b.sh src/moved.sh" due

# A range is in the numbering of the commit the location was recorded at.
# Once the file changed between that commit and the finding's latest judging,
# the range no longer names the same code and the location is judged as the
# file: a fix far from the old range still makes it due.
fixture renumbered
plan_record scrutiny '[{"seat":"completeness","findings":[{"severity":"blocking","summary":"x","path":"src/a.sh","lines":"45"}]},
                       {"seat":"justification"},{"seat":"intent"}]'
RID=$(fid scrutiny completeness)
(cd "$FX/repo" && { seq 1 10 | sed 's/^/pre/'; cat src/a.sh; } > x && mv x src/a.sh && git commit -q -am "shift a.sh") >/dev/null 2>&1
run --mark-fixed scrutiny "$SESSION" "$RID"
run --plan scrutiny "$SESSION"
record scrutiny "[{\"seat\":\"reverifier\",\"answers\":[{\"id\":\"$RID\",\"record\":\"holds\"}]}]"
edit src/a.sh 3 three
run --plan scrutiny "$SESSION"
[ "$(due scrutiny)" = "$RID" ] && pass "a finding whose file changed since its location was recorded is judged as the file" \
    || fail "due is [$(due scrutiny)], expected $RID"

echo "--- script: the due table, one case per cell"

# due_cell <status> <column> <expected: due|not-due>
#   status: open, fixed, unverified, closed
#   column: touched, untouched, none
due_cell() {
    local st="$1" col="$2" want="$3" f id run c1 fix
    fixture "cell-$st-$col"
    case "$col" in
        none) f='{"severity":"blocking","summary":"cell"}' ;;
        *)    f='{"severity":"blocking","summary":"cell","path":"src/b.sh","lines":"5"}' ;;
    esac
    plan_record scrutiny "[{\"seat\":\"completeness\",\"findings\":[$f]},{\"seat\":\"justification\"},{\"seat\":\"intent\"}]"
    id=$(fid scrutiny completeness)
    run=$(jq -r --arg id "$id" '.findings[$id].run' "$SHIM_STORE/$SESSION/verdict_ledger.json")
    c1=$(cd "$FX/repo" && git rev-parse HEAD)
    case "$st" in
        unverified)
            jq --arg id "$id" --arg c "$c1" '.findings[$id].records += [{kind: "unverified",
                writer: {kind: "decider", name: "scrutiny_decider/rs-007", run: "decider-x"}, round: 1, commit: $c, rev: .rev}]' \
                "$SHIM_STORE/$SESSION/verdict_ledger.json" > "$WORKDIR/l" && mv "$WORKDIR/l" "$SHIM_STORE/$SESSION/verdict_ledger.json" ;;
        closed)
            jq --arg id "$id" --arg c "$c1" --arg run "$run" '.findings[$id].records += [{kind: "reverified",
                writer: {kind: "reviewer", name: "completeness", run: $run}, round: 1, commit: $c, rev: .rev}]' \
                "$SHIM_STORE/$SESSION/verdict_ledger.json" > "$WORKDIR/l" && mv "$WORKDIR/l" "$SHIM_STORE/$SESSION/verdict_ledger.json" ;;
    esac
    case "$col" in
        touched) fix="awk 'NR == 5 { print \"five\"; next } { print }' src/b.sh > x && mv x src/b.sh" ;;
        *)       fix="awk 'NR == 30 { print \"thirty\"; next } { print }' src/b.sh > x && mv x src/b.sh" ;;
    esac
    (cd "$FX/repo" && eval "$fix" && git commit -q -am "fix") >/dev/null 2>&1
    [ "$st" = fixed ] && run --mark-fixed scrutiny "$SESSION" "$id"
    run --plan scrutiny "$SESSION"
    case "$want:$(due scrutiny)" in
        "due:$id"|"not-due:") pass "due table: $st, location $col: $want" ;;
        *) fail "due table: $st, location $col: due is [$(due scrutiny)], expected $want" ;;
    esac
}
due_cell open touched due
due_cell open untouched not-due
due_cell open none due
due_cell fixed touched due
due_cell fixed untouched due
due_cell fixed none due
due_cell unverified touched due
due_cell unverified untouched due
due_cell unverified none due
due_cell closed touched due
due_cell closed untouched not-due
due_cell closed none not-due

# An unresolvable location (its commit is gone) is due while unclosed.
fixture unresolvable
plan_record scrutiny '[{"seat":"completeness","findings":[{"severity":"blocking","summary":"x","path":"src/b.sh","lines":"5"}]},
                       {"seat":"justification"},{"seat":"intent"}]'
UID_=$(fid scrutiny completeness)
jq --arg id "$UID_" '.findings[$id].location.at = "0123456789012345678901234567890123456789"' \
    "$SHIM_STORE/$SESSION/verdict_ledger.json" > "$WORKDIR/l" && mv "$WORKDIR/l" "$SHIM_STORE/$SESSION/verdict_ledger.json"
edit src/b.sh 30 thirty
run --plan scrutiny "$SESSION"
[ "$(due scrutiny)" = "$UID_" ] && pass "an open finding whose location can't be resolved is due" \
    || fail "due is [$(due scrutiny)]"

# A finding judged at HEAD is not due unless a later fixed record asks for it.
fixture atHead
plan_record scrutiny '[{"seat":"completeness","findings":[{"severity":"blocking","summary":"x"}]},{"seat":"justification"},{"seat":"intent"}]'
HID=$(fid scrutiny completeness)
# A plan at the recorded HEAD stands; drop the stored scope to plan anew.
rm -f "$SHIM_STORE/$SESSION/scrutiny_scope.json"
run --plan scrutiny "$SESSION"
[ "$(due scrutiny)" = "" ] && pass "an open finding judged at HEAD is not due" || fail "due is [$(due scrutiny)]"
run --mark-fixed scrutiny "$SESSION" "$HID"
run --plan scrutiny "$SESSION"
[ "$(due scrutiny)" = "$HID" ] && pass "a fixed record at HEAD makes it due, and re-plans the round" || fail "due is [$(due scrutiny)]"

# A regression check that answers holds re-opens the finding.
fixture regression
plan_record scrutiny '[{"seat":"completeness","findings":[{"severity":"blocking","summary":"x","path":"src/b.sh","lines":"5"}]},
                       {"seat":"justification"},{"seat":"intent"}]'
GID=$(fid scrutiny completeness)
edit src/b.sh 5 five
run --plan scrutiny "$SESSION"
reverify scrutiny "$GID" "line 5 fixed"
edit src/b.sh 5 broken-again
run --plan scrutiny "$SESSION"
[ "$(due scrutiny)" = "$GID" ] && pass "a closed finding whose location a later fix touched is due (regression check)" \
    || fail "due is [$(due scrutiny)]"
record scrutiny "[{\"seat\":\"reverifier\",\"answers\":[{\"id\":\"$GID\",\"record\":\"holds\"}]}]"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict after a regression check answered holds" 1
jq -e --arg id "$GID" '.findings[$id].records[-1].kind == "holds"' "$SHIM_STORE/$SESSION/verdict_ledger.json" >/dev/null \
    && pass "the regression check re-opened the finding" || fail "records $(jq -c --arg id "$GID" '.findings[$id].records' "$SHIM_STORE/$SESSION/verdict_ledger.json")"

# Advisory findings are never due.
fixture advisory
plan_record scrutiny '[{"seat":"completeness","findings":[{"severity":"advisory","summary":"nice","path":"src/b.sh","lines":"5"},
                                                           {"severity":"blocking","summary":"must","path":"src/b.sh","lines":"5"}]},
                       {"seat":"justification"},{"seat":"intent"}]'
edit src/b.sh 5 five
run --plan scrutiny "$SESSION"
[ "$(due scrutiny)" = "$(sid must)" ] && pass "only the blocking finding is due; an advisory one never is" \
    || fail "due is [$(due scrutiny)]"
GOT=$(jq -r '[.findings[] | select(.raiser.name == "completeness")] | length' "$SHIM_STORE/$SESSION/verdict_ledger.json")
[ "$GOT" = 2 ] && pass "the ledger keeps both findings" || fail "the ledger holds $GOT findings"

echo "--- script: each full-round trigger, one case each"

fixture tr-oldledger
plan_record scrutiny "$ALL_PASS"
jq 'del(.findings)' "$SHIM_STORE/$SESSION/verdict_ledger.json" > "$WORKDIR/l" && mv "$WORKDIR/l" "$SHIM_STORE/$SESSION/verdict_ledger.json"
edit docs/c.md 1 changed
run --plan scrutiny "$SESSION"
expect_full "a ledger with no findings key" scrutiny "predates finding records"

fixture tr-criteria
plan_record scrutiny "$ALL_PASS"
printf 'AC: the issue body, amended\n' > "$SHIM_STORE/$SESSION/context.md"
run --plan scrutiny "$SESSION"
expect_full "the acceptance criteria changed" scrutiny "acceptance criteria or the plan changed"

fixture tr-plan
printf 'plan v1\n' > "$SHIM_STORE/$SESSION/plan.md"
plan_record scrutiny "$ALL_PASS"
printf 'plan v2, scope expanded\n' > "$SHIM_STORE/$SESSION/plan.md"
run --plan scrutiny "$SESSION"
expect_full "the plan was rewritten" scrutiny "acceptance criteria or the plan changed"

fixture tr-rewritten
plan_record scrutiny "$ALL_PASS"
(cd "$FX/repo" && git reset -q --hard HEAD~1 && seq 1 50 > src/a.sh && echo x >> docs/c.md && git commit -q -am redo) >/dev/null 2>&1
run --plan scrutiny "$SESSION"
expect_full "a recorded commit is off HEAD's history" scrutiny "no longer an ancestor of HEAD"

fixture tr-dirty
plan_record scrutiny "$ALL_PASS"
(cd "$FX/repo" && echo uncommitted >> docs/c.md)
run --plan scrutiny "$SESSION"
expect_full "an uncommitted fix" scrutiny "uncommitted changes"
run --carried scrutiny "$SESSION"
expect_rc "--carried on a dirty tree" 1

fixture tr-nocommits
(cd "$FX/repo" && git rev-parse HEAD) > "$SHIM_STORE/$SESSION/impl_base"
plan_record scrutiny "$ALL_PASS"
rm -f "$SHIM_STORE/$SESSION/scrutiny_scope.json"
run --plan scrutiny "$SESSION"
expect_full "no commits since impl_base" scrutiny "no commits since impl_base"

fixture tr-nobase
plan_record scrutiny "$ALL_PASS"
rm -f "$SHIM_STORE/$SESSION/impl_base"
edit docs/c.md 1 changed
run --plan scrutiny "$SESSION"
expect_full "impl_base unrecorded" scrutiny "no commits since impl_base"

fixture tr-emptyjudged
(cd "$FX/repo" && git rev-parse HEAD) > "$SHIM_STORE/$SESSION/impl_base"
run --plan scrutiny "$SESSION"
record scrutiny "$ALL_PASS"
edit docs/c.md 1 changed
run --plan scrutiny "$SESSION"
expect_full "seats that judged no commit since impl_base" scrutiny "no commit since impl_base"

fixture tr-201
plan_record scrutiny "$ALL_PASS"
(cd "$FX/repo" && seq 1 201 > docs/new.txt && git add docs/new.txt && git commit -q -m big) >/dev/null 2>&1
run --plan scrutiny "$SESSION"
expect_full "a 201-line fix" scrutiny "changes 201 lines"

fixture tr-200
plan_record scrutiny "$ALL_PASS"
(cd "$FX/repo" && seq 1 200 > docs/new.txt && git add docs/new.txt && git commit -q -m big) >/dev/null 2>&1
run --plan scrutiny "$SESSION"
expect_not_full "a 200-line fix" scrutiny

# The 200-line rule is measured from the panel's own newest record, not from
# the newest commit any panel recorded: a large fix that scrutiny reviewed in
# full still makes review's round full, rather than leaving review's seats
# with an empty diff to carry on.
fixture tr-crosspanel
plan_record scrutiny "$ALL_PASS"
plan_record review "$REVIEW_PASS"
(cd "$FX/repo" && seq 1 250 > docs/new.txt && git add docs/new.txt && git commit -q -m big) >/dev/null 2>&1
run --plan scrutiny "$SESSION"
expect_full "a 250-line fix at the first panel" scrutiny "changes 250 lines"
record scrutiny "$ALL_PASS"
run --plan review "$SESSION"
expect_full "the same fix at the next panel, after the first recorded it in full" review "changes 250 lines"

# A full round hands each seat its own unclosed findings, and the findings no
# seat raised to a re-verifier.
fixture tr-handoff
plan_record scrutiny '[{"seat":"completeness","findings":[{"severity":"blocking","summary":"mine","path":"src/b.sh","lines":"5"}]},
                       {"seat":"justification"},{"seat":"intent"}]'
edit src/a.sh 45 forty-five
run --plan scrutiny "$SESSION"
record scrutiny '[{"seat":"reverifier","findings":[{"severity":"blocking","summary":"the fix broke a.sh","path":"src/a.sh","lines":"45"}]}]'
printf 'plan v2\n' > "$SHIM_STORE/$SESSION/plan.md"
run --plan scrutiny "$SESSION"
expect_full "a full round after a block" scrutiny "acceptance criteria or the plan changed"
GOT=$(jq -r '[.decisions[] | "\(.seat)=\(.decision):\([(.findings // [])[].summary] | join(","))"] | join(" ")' \
    "$SHIM_STORE/$SESSION/scrutiny_scope.json")
[ "$GOT" = "completeness=full:mine justification=full: intent=full: reverifier=recheck:the fix broke a.sh" ] \
    && pass "each seat is handed its own unclosed findings by id, and the fix-diff review's go to a re-verifier" \
    || fail "full-round decisions are [$GOT]"
jq -e '[.decisions[] | select(.seat == "completeness") | .findings[0].id | test("^[0-9a-f]{16}$")] == [true]' \
    "$SHIM_STORE/$SESSION/scrutiny_scope.json" >/dev/null \
    && pass "a seat's handed-back findings carry their ids" || fail "no id on the handed-back finding"

echo "--- script: the fix-diff review"

fixture fixreview
plan_record scrutiny "$ALL_PASS"
plan_record review "$REVIEW_PASS"
C1=$(cd "$FX/repo" && git rev-parse HEAD)
plan_record qa '[{"seat":"tester","findings":[{"severity":"blocking","summary":"scenario 2 fails"}]}]'
QID=$(fid qa tester)
edit src/a.sh 45 forty-five
run --mark-fixed qa "$SESSION" "$QID"
run --plan scrutiny "$SESSION"
GOT=$(jq -r '.decisions[] | select(.seat == "reverifier") | "\(.fix_review)|\(.review_from)"' "$SHIM_STORE/$SESSION/scrutiny_scope.json")
[ "$GOT" = "true|$C1" ] \
    && pass "the fix-diff review lands at the first panel, from the newest recorded commit; an agent's fixed record at HEAD doesn't empty it" \
    || fail "scrutiny re-verifier is [$GOT], expected true|$C1"
record scrutiny '[{"seat":"reverifier","findings":[{"severity":"blocking","summary":"the fix broke line 45","path":"src/a.sh","lines":"45"}]}]'
FRID=$(sid "the fix broke line 45")
jq -e --arg id "$FRID" '.findings[$id] | .raiser == {kind: "reviewer", name: "fix-review"} and .panel == "scrutiny"
       and .records[-1].kind == "raised"' "$SHIM_STORE/$SESSION/verdict_ledger.json" >/dev/null \
    && pass "a finding the fix-diff review raises is open under raiser fix-review, in the panel it ran in" \
    || fail "fix-review finding $(jq -c --arg id "$FRID" '.findings[$id]' "$SHIM_STORE/$SESSION/verdict_ledger.json")"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict with an open fix-review finding" 1
grep -q 'scrutiny/fix-review: the fix broke line 45' <<<"$OUT" \
    && pass "the gate names the fix-review raiser" || fail "verdict printed: $OUT"
run --plan review "$SESSION"
[ "$(spawned review)" = 0 ] && pass "the next panel plans no fix-diff review once one is recorded" \
    || fail "review scope: $(cat "$SHIM_STORE/$SESSION/review_scope.json")"
run --plan qa "$SESSION"
GOT=$(jq -r '.decisions[] | select(.seat == "reverifier") | "\(.fix_review)|\([.findings[].id] | join(","))"' "$SHIM_STORE/$SESSION/qa_scope.json")
[ "$GOT" = "false|$QID" ] && pass "QA re-verifies its fixed scenario, with no second fix-diff review" \
    || fail "qa re-verifier is [$GOT]"

# Recording the reverifier's fix-diff findings needs a planned review.
fixture noreview
plan_record scrutiny "$ALL_PASS"
plan_record review "$REVIEW_PASS"
edit src/a.sh 45 forty-five
run --plan scrutiny "$SESSION"
record scrutiny '[{"seat":"reverifier"}]'
run --plan review "$SESSION"
printf '[{"seat":"reverifier","run":"review-r2-reverifier","findings":[{"severity":"blocking","summary":"late"}]}]\n' > "$WORKDIR/round.json"
NO_AUTORUN=1 run --record review "$SESSION" "$WORKDIR/round.json"
expect_rc "--record of a re-verifier the scope didn't plan" 65

echo "--- script: --recorded holds a round whose record was skipped"

fixture recorded
run --recorded scrutiny "$SESSION"
expect_rc "--recorded with no scope and no ledger" 0
run --plan scrutiny "$SESSION"
run --recorded scrutiny "$SESSION"
expect_rc "--recorded on a first round with nothing recorded" 1
record scrutiny '[{"seat":"intent","findings":[{"severity":"blocking","summary":"x","path":"src/a.sh","lines":"41"}]},
                  {"seat":"completeness","cited":[{"path":"src/a.sh","lines":"41-50"}]},
                  {"seat":"justification","cited":[{"path":"src/a.sh","lines":"41-50"}]}]'
run --recorded scrutiny "$SESSION"
expect_rc "--recorded once the round is recorded" 0
edit src/a.sh 41 fixed
run --plan scrutiny "$SESSION"
run --recorded scrutiny "$SESSION"
expect_rc "--recorded before the re-verifier is recorded" 1
grep -q "reverifier" "$WORKDIR/stderr" && pass "--recorded names the unrecorded run" || fail "--recorded stderr: $(cat "$WORKDIR/stderr")"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict before the re-verifier is recorded" 2
record scrutiny "[{\"seat\":\"reverifier\",\"answers\":[{\"id\":\"$(fid scrutiny intent)\",\"record\":\"reverified\",\"reason\":\"line 41 fixed\"}]}]"
run --recorded scrutiny "$SESSION"
expect_rc "--recorded after the re-verifier is recorded" 0
run --recorded bogus "$SESSION"
expect_rc "--recorded never exits outside 0/1 (bad panel)" 1
# A commit made while the panel is open is one no seat saw.
edit docs/c.md 1 mid-round
run --recorded scrutiny "$SESSION"
expect_rc "--recorded after a recorded round, even with HEAD moved since" 0
printf '[{"seat":"reverifier","run":"scrutiny-r9-reverifier"}]\n' > "$WORKDIR/round.json"
NO_AUTORUN=1 run --record scrutiny "$SESSION" "$WORKDIR/round.json"
expect_rc "--record refuses to stamp a commit the round never saw" 68

echo "--- script: the history counts rounds, not ticks"

fixture history
run --plan review "$SESSION"
run --plan review "$SESSION"
N=$(jq '[.history[] | select(.panel == "review")] | length' "$SHIM_STORE/$SESSION/verdict_ledger.json")
[ "$N" = 1 ] && pass "two ticks at one HEAD are one round" || fail "two ticks at one HEAD made $N history entries"
record review '[{"seat":"pragmatic","findings":[{"severity":"blocking","summary":"x","path":"docs/c.md"}]},
                {"seat":"architect","cited":[{"path":"src/a.sh","lines":"41-50"}]},
                {"seat":"maintainer","cited":[{"path":"src/a.sh","lines":"41-50"}]}]'
edit docs/c.md 1 fixed
run --plan review "$SESSION"
GOT=$(jq -c '[.history[] | select(.panel == "review") | [.round, .spawned]]' "$SHIM_STORE/$SESSION/verdict_ledger.json")
[ "$GOT" = '[[1,3],[2,1]]' ] && pass "history records each round's spawn count" || fail "history is $GOT, expected [[1,3],[2,1]]"
jq -e '.history[-1].decisions | all(.reason | length > 0)' "$SHIM_STORE/$SESSION/verdict_ledger.json" >/dev/null 2>&1 \
    && pass "every decision in the history has a reason" || fail "a history decision has no reason"

echo "--- script: the light seat's re-verification packet, before and after a fix"

fixture light-recheck
plan_record light '[{"seat":"reviewer","findings":[{"severity":"blocking","summary":"a.sh line 45 is wrong","path":"src/a.sh","lines":"45"}]}]'
LJUDGED=$(cd "$FX/repo" && git rev-parse HEAD)
LID=$(fid light reviewer)
run --mark-fixed light "$SESSION" "$LID"
# Nothing committed since the seat blocked, but the agent marked it fixed: due,
# and its packet says the fix diff is empty rather than failing or widening it.
run --plan light "$SESSION"
[ "$(due light)" = "$LID" ] && pass "a finding marked fixed with nothing committed is due" || fail "light due [$(due light)]"
packet recheck --session "$SESSION" --panel light --seat reverifier
if [ "$PRC" -eq 0 ] && grep -q '^changed paths: 0$' "$POUT" \
    && grep -q "^\[empty: no commit since $LJUDGED changes anything\]\$" "$POUT" \
    && grep -q '"summary": "a.sh line 45 is wrong"' "$POUT"; then
    pass "an empty fix diff gives the light re-verifier its finding and an empty diff, said so"
else
    fail "light re-check with an empty fix diff: exit $PRC: $(cat "$WORKDIR/pstderr")"
fi
[ "$PRC" -eq 0 ] && rm -f "$POUT"
edit src/a.sh 45 forty-five
run --plan light "$SESSION"
[ "$(due light)" = "$LID" ] && pass "a fix on the light seat's finding makes it due" || fail "light due [$(due light)]"
packet recheck --session "$SESSION" --panel light --seat reverifier
if [ "$PRC" -eq 0 ] && grep -q "^fix diff from: $LJUDGED (fix_diff_from)\$" "$POUT" \
    && grep -q '^+forty-five$' "$POUT" && ! grep -q '^+50$' "$POUT"; then
    pass "the light re-verifier's packet carries the fix and not the implementation it judged"
else
    fail "light re-check after a fix: exit $PRC: $(cat "$WORKDIR/pstderr")"
fi
[ "$PRC" -eq 0 ] && rm -f "$POUT"
[ -z "$(ls "$WORKDIR/ptmp")" ] && pass "every packet was cleaned up" || fail "packets left behind: $(ls "$WORKDIR/ptmp")"

echo "--- script: a seat's verdict comes from its findings' severity"

# ledger_verdict <panel/seat>: the verdict the ledger holds for the seat.
ledger_verdict() {
    jq -r --arg k "$1" '.seats[$k].verdict // "none"' "$SHIM_STORE/$SESSION/verdict_ledger.json" 2>/dev/null
}

fixture severity
record scrutiny '[{"seat":"intent","blocking_count":0,
                   "findings":[{"severity":"blocking","summary":"x","path":"src/a.sh","lines":"41"}]}]'
GOT=$(ledger_verdict scrutiny/intent)
[ "$GOT" = blocking ] && pass "a blocking finding with blocking_count 0 records the seat as blocking" \
    || fail "a blocking finding with blocking_count 0 recorded [$GOT]"
record scrutiny '[{"seat":"completeness","blocking_count":2,
                   "findings":[{"severity":"advisory","summary":"a","path":"src/a.sh","lines":"42"},
                               {"severity":"advisory","summary":"b"}]}]'
GOT=$(ledger_verdict scrutiny/completeness)
[ "$GOT" = passed ] && pass "blocking_count 2 with only advisory findings records the seat as passing" \
    || fail "blocking_count 2 with only advisory findings recorded [$GOT]"
record scrutiny '[{"seat":"justification","passed":false}]'
GOT=$(ledger_verdict scrutiny/justification)
[ "$GOT" = passed ] && pass "a seat with no findings passes whatever its summary fields say" \
    || fail "a seat with no findings and passed:false recorded [$GOT]"

cp "$SHIM_STORE/$SESSION/verdict_ledger.json" "$WORKDIR/ledger.before"
printf '%s\n' '[{"seat":"intent","findings":[{"summary":"no severity","path":"src/a.sh"}]}]' > "$WORKDIR/round.json"
run --record scrutiny "$SESSION" "$WORKDIR/round.json"
expect_rc "--record with a finding that has no severity" 65
grep -q intent "$WORKDIR/stderr" && pass "the refusal names the seat" || fail "refusal stderr: $(cat "$WORKDIR/stderr")"
printf '%s\n' '[{"seat":"intent","findings":[{"severity":"major","summary":"x"}]}]' > "$WORKDIR/round.json"
run --record scrutiny "$SESSION" "$WORKDIR/round.json"
expect_rc "--record with a severity other than blocking or advisory" 65
printf '%s\n' '[{"seat":"intent","findings":[{"severity":"advisory","summary":"ok"},{"severity":null,"summary":"x"}]}]' > "$WORKDIR/round.json"
run --record scrutiny "$SESSION" "$WORKDIR/round.json"
expect_rc "--record with one good finding and one null severity" 65
printf '%s\n' '[{"seat":"intent","findings":"blocking"}]' > "$WORKDIR/round.json"
run --record scrutiny "$SESSION" "$WORKDIR/round.json"
expect_rc "--record with findings that are not a list" 65
cmp -s "$WORKDIR/ledger.before" "$SHIM_STORE/$SESSION/verdict_ledger.json" \
    && pass "a refused round leaves the ledger untouched" || fail "a refused round changed the ledger"

echo "--- script: --verdict, the panel's pass"

# verdict_findings: the finding lines of the last --verdict run.
verdict_findings() { printf '%s\n' "$OUT" | grep '^::koto-finding::' | sed 's/^::koto-finding:://'; }
OPEN_SUMMARY=$("$SCRIPT_DIR/../../../scripts/rule-registry.sh" summary panel/open-finding)
RS7_SUMMARY=$("$SCRIPT_DIR/../../../scripts/rule-registry.sh" summary rs-007)

fixture verdict
run --verdict scrutiny "$SESSION"
expect_rc "--verdict with no ledger" 2
same_laddered "--verdict, laddered, with no ledger (undecided)" --verdict scrutiny "$SESSION"
run --plan scrutiny "$SESSION"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict on a planned round with nothing recorded" 2
grep -q 'completeness' "$WORKDIR/stderr" && pass "the hold names the unrecorded runs" || fail "--verdict stderr: $(cat "$WORKDIR/stderr")"
[ -z "$(verdict_findings)" ] && pass "a held verdict prints no finding" || fail "a held verdict printed: $OUT"
record scrutiny '[{"seat":"completeness","findings":[{"severity":"advisory","summary":"a"}]},
                  {"seat":"justification"}]'
run --verdict scrutiny "$SESSION"
expect_rc "--verdict with one planned run still unrecorded" 2
grep -q 'intent' "$WORKDIR/stderr" && pass "the hold names intent" || fail "--verdict stderr: $(cat "$WORKDIR/stderr")"
record scrutiny '[{"seat":"intent","findings":[{"severity":"advisory","summary":"b"}]}]'
run --verdict scrutiny "$SESSION"
expect_rc "--verdict when every run is recorded and only advisory findings are open" 0
[ -z "$OUT" ] && pass "a passing verdict prints nothing" || fail "a passing verdict printed: $OUT"
run --open-count scrutiny "$SESSION"
[ "$RC" = 0 ] && [ "$OUT" = 0 ] && pass "--open-count counts no advisory finding" || fail "--open-count: exit $RC, [$OUT]"

# A new round, full again, recorded with blocking findings: one unruled, one
# citing an active rule, one marked fixed, one a decider left unverified.
rm -f "$SHIM_STORE/$SESSION/scrutiny_scope.json"
printf 'plan v2\n' > "$SHIM_STORE/$SESSION/plan.md"
run --plan scrutiny "$SESSION"
record scrutiny '[{"seat":"intent","findings":[{"severity":"blocking","summary":"first","path":"src/a.sh","lines":"41-43"},
                                               {"severity":"advisory","summary":"aside"},
                                               {"severity":"blocking","summary":"second","rule_id":"rs-007"}]},
                  {"seat":"justification","findings":[{"severity":"blocking","summary":"third","path":"docs/c.md"}]},
                  {"seat":"completeness"}]'
run --mark-fixed scrutiny "$SESSION" "$(sid third)"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict with three unclosed blocking findings" 1
N=$(verdict_findings | grep -c .)
[ "$N" = 3 ] && pass "one finding per unclosed blocking finding (3), a fixed one included, none for the advisory one" || fail "$N findings: $OUT"
GOT=$(verdict_findings | jq -sc '[.[] | [.rule_id, .message, .path, .line]]')
WANT=$(jq -nc --arg o "$OPEN_SUMMARY" --arg r "$RS7_SUMMARY" '[
    ["panel/open-finding", ($o + ": scrutiny/intent: first"), "src/a.sh", 41],
    ["rs-007", ($r + ": scrutiny/intent: second"), null, null],
    ["panel/open-finding", ($o + ": scrutiny/justification: third"), "docs/c.md", null]]')
[ "$GOT" = "$WANT" ] \
    && pass "an unruled finding prints under panel/open-finding, a ruled one under its own rule, with panel, raiser, summary and location" \
    || fail "findings are $GOT, want $WANT"
WANT_RANGE=$(rf_test_expected_range panel/open-finding)
N=$(verdict_findings | jq -s --arg r "$WANT_RANGE" '[.[] | select(.rule_id == "panel/open-finding" and (.rule_ref | split("@")[0]) == $r)] | length')
[ -n "$WANT_RANGE" ] && [ "$N" = 2 ] && pass "every panel/open-finding rule_ref range is $WANT_RANGE, found from its anchors with grep" \
    || fail "rule_ref: want range [$WANT_RANGE] on 2 findings, got $N"
run --open-count scrutiny "$SESSION"
[ "$RC" = 0 ] && [ "$OUT" = 3 ] && pass "--open-count prints the number of findings --verdict printed" || fail "--open-count: exit $RC, [$OUT]"
# As run() does: from the fixture repository, with the koto stand-in on PATH,
# so the unaltered copy reads the same ledger and decides (exit 1).
RF_SAVED_PATH=$PATH
PATH="$SHIM_BIN:$PATH"
cd "$FX/repo" || exit 1
rf_test_refusals "--verdict" skills/work-on/scripts/panel-scope.sh panel/open-finding --verdict scrutiny "$SESSION"
cd "$WORKDIR" || exit 1
PATH=$RF_SAVED_PATH

# A rule retired after the finding cited it prints under panel/open-finding,
# naming the old id; the gate neither prints it nor holds on it.
SECOND=$(sid second)
jq --arg id "$SECOND" '.findings[$id].rule_id = "panel/blocking-finding"' \
    "$SHIM_STORE/$SESSION/verdict_ledger.json" > "$WORKDIR/l" && mv "$WORKDIR/l" "$SHIM_STORE/$SESSION/verdict_ledger.json"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict with a finding citing a retired rule" 1
verdict_findings | jq -se --arg o "$OPEN_SUMMARY" 'any(.[]; .rule_id == "panel/open-finding"
        and .message == ($o + ": scrutiny/intent: second (cites rule panel/blocking-finding, which is no longer active)"))
    and all(.[]; .rule_id != "panel/blocking-finding")' >/dev/null \
    && pass "a retired rule falls back to panel/open-finding, named in the message" || fail "findings: $OUT"

# Closing records: a reviewer's reverified closes; a closing record written
# by a writer the table doesn't allow does not.
FIRST=$(sid first)
jq --arg id "$FIRST" '.findings[$id].records += [{kind: "reverified", writer: {kind: "agent", name: "work-on", run: "scrutiny-r2-intent"}, round: 2, commit: "x", rev: 1}]' \
    "$SHIM_STORE/$SESSION/verdict_ledger.json" > "$WORKDIR/l" && mv "$WORKDIR/l" "$SHIM_STORE/$SESSION/verdict_ledger.json"
run --verdict scrutiny "$SESSION"
verdict_findings | grep -q 'scrutiny/intent: first' \
    && pass "a reverified record by the agent doesn't close a finding" || fail "findings: $OUT"

printf '{"rev": 9, "seats": {}}\n' > "$SHIM_STORE/$SESSION/verdict_ledger.json"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict with a ledger that has no findings key" 2
run --open-count scrutiny "$SESSION"
expect_rc "--open-count with a ledger that has no findings key" 2
printf 'not json\n' > "$SHIM_STORE/$SESSION/verdict_ledger.json"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict with an unreadable ledger" 2
run --verdict bogus "$SESSION"
expect_rc "--verdict with an unknown panel" 2
run --verdict scrutiny
expect_rc "--verdict with no session" 2

# Stages. Every finding --verdict prints takes panel/open-finding's stage,
# whichever rule it cites, and only at block does the panel fail. One finding
# is unruled; the other cites commit/conventional-subject, a script rule whose
# stage a plugin copy can set.
fixture verdictstage
plan_record scrutiny '[{"seat":"intent","findings":[{"severity":"blocking","summary":"unruled","path":"src/a.sh","lines":"41"},
                                                    {"severity":"blocking","summary":"ruled","rule_id":"commit/conventional-subject"}]},
                       {"seat":"completeness"},{"seat":"justification"}]'
run --verdict scrutiny "$SESSION"
expect_rc "--verdict on the stage fixture against the real registry" 1
verdict_in_copy() { # <copy>
    cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$1/skills/work-on/scripts/panel-scope.sh" --verdict scrutiny "$SESSION"
}
rf_test_stages "--verdict" panel/open-finding 1 panel/open-finding verdict_in_copy \
    skills/work-on/scripts/panel-scope.sh

# The cited rule at warn doesn't soften its finding while panel/open-finding
# is at block: the finding still prints at error, under the cited rule.
STAGE_COPY="$RF_TEST_DIR/stage-copy"
STAGE_LOG="$RF_TEST_DIR/stage-copy.log"
if rf_test_stage_copy "$STAGE_COPY" commit/conventional-subject warn skills/work-on/scripts/panel-scope.sh; then
    : > "$STAGE_LOG"
    OUT=$(cd "$FX/repo" && SHIRABE_FINDINGS_LOG="$STAGE_LOG" PATH="$SHIM_BIN:$PATH" \
        "$STAGE_COPY/skills/work-on/scripts/panel-scope.sh" --verdict scrutiny "$SESSION" 2>"$WORKDIR/stderr")
    RC=$?
    GOT=$(verdict_findings | jq -r '"\(.rule_id)=\(.level)"' | sort | tr '\n' ' ')
    if [ "$RC" = 1 ] && [ "$GOT" = "commit/conventional-subject=error panel/open-finding=error " ]; then
        pass "--verdict: a finding citing a warn-stage rule prints at error while panel/open-finding is at block"
    else
        fail "--verdict with the cited rule at warn: exit $RC, findings [$GOT]"
    fi
    rf_test_verify_copy "--verdict, cited rule at warn" "$STAGE_COPY" "$STAGE_LOG" panel/open-finding
else
    fail "--verdict: could not make a plugin copy with commit/conventional-subject at warn"
fi
rm -rf "$STAGE_COPY" "$STAGE_LOG"

# The rule the gate used to print is retired: kept joinable, never printed.
REGISTRY_JSON="$PLUGIN_ROOT/references/rule-registry.json"
jq -e '[.rules[] | select(.id == "panel/blocking-finding")][0]
       | .status == "retired" and (.notes | test("panel/open-finding"))' "$REGISTRY_JSON" >/dev/null 2>&1 \
    && pass "panel/blocking-finding is retired, its notes naming panel/open-finding" \
    || fail "panel/blocking-finding: $(jq -c '[.rules[] | select(.id == "panel/blocking-finding")][0] | {status, notes}' "$REGISTRY_JSON")"
HITS=$(grep -rln 'panel/blocking-finding' "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/references" 2>/dev/null \
    | grep -v '/rule-registry\.json$' | grep -v '_test\.sh$' | grep -v '/work-on/evals/')
[ -z "$HITS" ] && pass "no RULE_IDS line, directive or reference names panel/blocking-finding" \
    || fail "panel/blocking-finding is still named in: $HITS"

# 2 wins over 1: a round planned and not recorded holds the gate even with a
# blocking finding open.
fixture verdict2
plan_record scrutiny '[{"seat":"intent","findings":[{"severity":"blocking","summary":"x","path":"src/a.sh","lines":"41"}]},
                       {"seat":"completeness"},{"seat":"justification"}]'
run --verdict scrutiny "$SESSION"
expect_rc "--verdict on a recorded blocking round" 1
edit src/a.sh 41 fixed
run --plan scrutiny "$SESSION"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict with a blocking finding open and the round's run unrecorded" 2
printf '%s\n' "$(jq 'del(.seats["scrutiny/completeness"])' "$SHIM_STORE/$SESSION/verdict_ledger.json")" > "$WORKDIR/l"
cp "$WORKDIR/l" "$SHIM_STORE/$SESSION/verdict_ledger.json"
rm -f "$SHIM_STORE/$SESSION/scrutiny_scope.json"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict with a seat that has no verdict, and a blocking finding open" 2

# koto re-runs --plan on every tick without evidence, and the agent ticks with
# none once the round is recorded. A blocking round recorded at this HEAD must
# stand, so --verdict reports the block (1), not an unrecorded round (2).
fixture replan
run --plan scrutiny "$SESSION"
record scrutiny '[{"seat":"completeness"},{"seat":"justification"},
                  {"seat":"intent","findings":[{"severity":"blocking","summary":"x","path":"src/a.sh","lines":"41"}]}]'
cp "$SHIM_STORE/$SESSION/scrutiny_scope.json" "$WORKDIR/scope.before"
cp "$SHIM_STORE/$SESSION/verdict_ledger.json" "$WORKDIR/ledger.before"
run --plan scrutiny "$SESSION"
expect_rc "--plan on a recorded blocking round at the same HEAD" 0
cmp -s "$WORKDIR/scope.before" "$SHIM_STORE/$SESSION/scrutiny_scope.json" \
    && pass "the recorded blocking round's scope stands" || fail "the scope was re-planned: $(cat "$SHIM_STORE/$SESSION/scrutiny_scope.json")"
cmp -s "$WORKDIR/ledger.before" "$SHIM_STORE/$SESSION/verdict_ledger.json" \
    && pass "and the history gains no round" || fail "the ledger changed on a re-plan of a complete round"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict after the re-plan tick" 1
# An uncommitted change at the recorded HEAD plans again: a full round.
(cd "$FX/repo" && echo uncommitted >> src/a.sh)
run --plan scrutiny "$SESSION"
expect_full "a recorded blocking round with an uncommitted fix" scrutiny "uncommitted changes"

# The light and QA panels have one seat each.
fixture verdictone
plan_record qa '[{"seat":"tester","findings":[{"severity":"blocking","summary":"scenario 2 fails"}]}]'
run --verdict qa "$SESSION"
expect_rc "--verdict qa with a failed scenario" 1
plan_record light '[{"seat":"reviewer"}]'
run --verdict light "$SESSION"
expect_rc "--verdict light with the reviewer passing" 0

# A decider that couldn't answer a criterion in the panel's first round blocks
# under the criterion's own rule id, rather than passing.
fixture verdictdecider
plan_record scrutiny "$ALL_PASS"
mkdir -p "$SHIM_STORE/$SESSION/sessiondir"
printf '{"type":"decider_checked","payload":{"state":"scrutiny","visit_seq":1,"gate":"scrutiny_decider","rule_id":"rs-007","declaration_hash":"abcd1234","outcome":"escape"}}\n' \
    > "$SHIM_STORE/$SESSION/sessiondir/koto-$SESSION.state.jsonl"
record scrutiny '[{"decider":{"state":"scrutiny","visit_seq":1,"gate":"scrutiny_decider","rule_id":"rs-007","declaration_hash":"abcd1234","outcome":"escape"}}]'
run --verdict scrutiny "$SESSION"
expect_rc "--verdict with a decider escape in round one" 1
verdict_findings | jq -se 'length == 1 and .[0].rule_id == "rs-007"' >/dev/null \
    && pass "the escape prints under the criterion's rule id" || fail "findings: $OUT"

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

# The light review level's panel: one seat, named reviewer.
run --plan light "$SESSION";         expect_rc "--plan for the light panel" 0
GOT=$(jq -r '[.decisions[] | .seat] | join(",")' "$SHIM_STORE/$SESSION/light_scope.json" 2>/dev/null)
[ "$GOT" = reviewer ] && pass "the light panel's one seat is reviewer" || fail "light_scope.json seats are [$GOT]"
run --record light "$SESSION" "$WORKDIR/wrong.json";     expect_rc "--record light with another panel's seat" 65
printf '[{"seat":"reviewer","blocking_count":0}]\n' > "$WORKDIR/light.json"
run --record light "$SESSION" "$WORKDIR/light.json";     expect_rc "--record light with its reviewer seat" 0
jq -e '.seats["light/reviewer"].verdict == "passed"' "$SHIM_STORE/$SESSION/verdict_ledger.json" >/dev/null 2>&1 \
    && pass "the light seat's verdict is in the verdict ledger" || fail "no light/reviewer entry in the verdict ledger"
FAILSESSION=fail-write
mkdir -p "$SHIM_STORE/$FAILSESSION"
OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" --plan scrutiny "$FAILSESSION" 2>"$WORKDIR/stderr"); RC=$?
expect_rc "--plan when the context write fails" 66
OUT=$(cd "$WORKDIR" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" --plan scrutiny "$SESSION" 2>"$WORKDIR/stderr"); RC=$?
expect_rc "--plan outside a git repository" 64


# --- the findings ledger: ids, records and the refusals of --record ----------

# led <jq args...>: query the session's ledger.
led() { jq "$@" "$SHIM_STORE/$SESSION/verdict_ledger.json"; }
# snap / unchanged <label>: the ledger is byte-identical to the last snap.
snap() { cp "$SHIM_STORE/$SESSION/verdict_ledger.json" "$WORKDIR/ledger.snap" 2>/dev/null || : > "$WORKDIR/ledger.snap"; }
unchanged() {
    cmp -s "$WORKDIR/ledger.snap" "$SHIM_STORE/$SESSION/verdict_ledger.json" \
        && pass "$1: the ledger is unchanged" || fail "$1: the ledger changed"
}
# refused <label> <panel> <json>: --record exits 65 and writes nothing.
refused() {
    snap
    printf '%s\n' "$3" > "$WORKDIR/round.json"
    NO_AUTORUN=1 run --record "$2" "$SESSION" "$WORKDIR/round.json"
    expect_rc "$1" 65
    unchanged "$1"
}
# mint <panel> [<prefix>]: each decision of the panel's stored scope gets run
# <prefix>-<seat> (default minted), and a kept seat is made full, so a case can
# record any seat under a run id it chose.
mint() {
    jq --arg p "${2:-minted}" '.decisions |= map(. + {run: ($p + "-" + .seat)} + (if .decision == "keep" then {decision: "full"} else {} end))' "$SHIM_STORE/$SESSION/$1_scope.json" > "$WORKDIR/scope" \
        && cp "$WORKDIR/scope" "$SHIM_STORE/$SESSION/$1_scope.json"
}

echo "--- script: a recorded round's findings, with ids and records"

fixture ledger
run --plan scrutiny "$SESSION"
HEAD_SHA=$(cd "$FX/repo" && git rev-parse HEAD)
record scrutiny '[{"seat":"completeness","run":"scrutiny-r1-completeness","findings":[{"severity":"blocking","summary":"line 42 is   wrong","path":"src/a.sh","lines":"42"}]},
                  {"seat":"justification","run":"scrutiny-r1-justification","findings":[{"severity":"advisory","summary":"b.sh could say more","path":"src/b.sh"}]},
                  {"seat":"intent","run":"scrutiny-r1-intent","findings":[{"severity":"blocking","summary":"the change misses the design","rule_id":"rs-007"}]}]'
[ "$(led '.findings | length')" = 3 ] && pass "every finding of the round is in the ledger" || fail "findings: $(led -c '.findings')"
F1=$(led -r '[.findings[] | select(.raiser.name == "completeness")][0].id')
F2=$(led -r '[.findings[] | select(.raiser.name == "justification")][0].id')
F3=$(led -r '[.findings[] | select(.raiser.name == "intent")][0].id')
case "$F1" in [0-9a-f]*) [ "${#F1}" = 16 ] && pass "a finding id is 16 hex characters" || fail "id [$F1]" ;; *) fail "id [$F1]" ;; esac
led -e --arg id "$F1" --arg h "$HEAD_SHA" '.findings[$id] | .panel == "scrutiny" and .severity == "blocking" and .round == 1
    and .raiser == {kind: "reviewer", name: "completeness"} and .run == "scrutiny-r1-completeness"
    and .location == {kind: "lines", path: "src/a.sh", lines: "42", at: $h} and .summary == "line 42 is   wrong"
    and (.records | length == 1) and .records[0].kind == "raised" and .records[0].writer.run == "scrutiny-r1-completeness"
    and .records[0].commit == $h' >/dev/null \
    && pass "a finding records panel, severity, round, raiser, run, location, summary and its first record" \
    || fail "finding $F1 is $(led -c --arg id "$F1" '.findings[$id]')"
led -e --arg id "$F2" '.findings[$id].location == {kind: "file", path: "src/b.sh", at: .findings[$id].location.at}' >/dev/null \
    && pass "a path alone is a file location" || fail "F2 location $(led -c --arg id "$F2" '.findings[$id].location')"
led -e --arg id "$F3" '.findings[$id].location.kind == "none" and .findings[$id].rule_id == "rs-007"' >/dev/null \
    && pass "no path is a none location, and a cited active rule is kept" || fail "F3 $(led -c --arg id "$F3" '.findings[$id]')"
led -e --arg id "$F2" '.findings[$id].severity == "advisory" and (.findings[$id].records | map(.kind)) == ["raised"]' >/dev/null \
    && pass "an advisory finding is recorded with raised and nothing else" || fail "F2 records"
led -e --arg id "$F1" --arg h "$HEAD_SHA" '.seats["scrutiny/completeness"] | .verdict == "blocking" and .judged_at == $h
    and (.ac_sha | length == 40) and .findings == [{id: $id, severity: "blocking", summary: "line 42 is   wrong", path: "src/a.sh", lines: "42"}]' >/dev/null \
    && pass "the seat entry keeps verdict, judged_at, ac_sha and findings with path and lines" \
    || fail "seat entry $(led -c '.seats["scrutiny/completeness"]')"
led -e '.seats["scrutiny/justification"].verdict == "passed" and .runs["scrutiny-r1-completeness"].recorded == true' >/dev/null \
    && pass "an advisory-only seat passes, and the round's runs are recorded" || fail "justification $(led -c '.seats["scrutiny/justification"]')"
[ "$(led '[.history[] | select(.panel == "scrutiny")] | last | .spawned')" = 3 ] \
    && pass "the round's history spawned equals its runs" || fail "spawned $(led -c '.history')"

echo "--- script: a finding keeps its id across rounds"

run --plan scrutiny "$SESSION"
mint scrutiny
NO_AUTORUN=1 record scrutiny '[{"seat":"completeness","run":"minted-completeness","answers":[],"findings":[{"severity":"blocking","summary":"line 42   is wrong ","path":"src/a.sh","lines":"40-44"},
                                                                                      {"severity":"blocking","summary":"a new one","path":"src/a.sh"}]}]'
[ "$(led --arg id "$F1" '.findings[$id].records | length')" = 2 ] \
    && pass "the same panel, raiser, path and summary, re-spaced and on other lines, is the same id" \
    || fail "re-raise records $(led -c --arg id "$F1" '.findings[$id].records')"
[ "$(led '.findings | length')" = 4 ] && pass "a different summary is a different id" || fail "count $(led '.findings | length')"
NEWID=$(cd "$FX/repo" && printf 'scrutiny\nreviewer\nintent\nsrc/a.sh\nline 42 is wrong' | git hash-object --stdin | cut -c1-16)
[ "$NEWID" != "$F1" ] && pass "a different raiser is a different id" || fail "raiser does not change the id"
PID=$(cd "$FX/repo" && printf 'review\nreviewer\ncompleteness\nsrc/a.sh\nline 42 is wrong' | git hash-object --stdin | cut -c1-16)
[ "$PID" != "$F1" ] && pass "a different panel is a different id" || fail "panel does not change the id"
SID=$(cd "$FX/repo" && printf 'scrutiny\nreviewer\ncompleteness\nsrc/a.sh\nline 42 is wrong' | git hash-object --stdin | cut -c1-16)
[ "$SID" = "$F1" ] && pass "the id is the hash of panel, raiser kind and name, path and collapsed summary" \
    || fail "id $F1 is not $SID"

echo "--- script: --record refuses, and writes nothing"

run --plan scrutiny "$SESSION"
mint scrutiny m2
refused "two findings of one run with one id" scrutiny \
    '[{"seat":"completeness","run":"m2-completeness","findings":[{"severity":"blocking","summary":"twin","path":"src/a.sh","lines":"1"},{"severity":"blocking","summary":"twin ","path":"src/a.sh","lines":"9"}]}]'
grep -q "word their summaries apart" "$WORKDIR/stderr" && pass "the refusal asks for distinct summaries" || fail "stderr: $(cat "$WORKDIR/stderr")"
refused "a run the scope did not mint" scrutiny '[{"seat":"completeness","run":"made-up-run","findings":[]}]'
refused "a run with no id" scrutiny '[{"seat":"completeness","findings":[]}]'
refused "a malformed run id" scrutiny '[{"seat":"completeness","run":"-x","findings":[]}]'
refused "a run already recorded" scrutiny '[{"seat":"completeness","run":"scrutiny-r1-completeness","findings":[]}]'
refused "an answer for an id the decision did not plan" scrutiny \
    "[{\"seat\":\"completeness\",\"run\":\"m2-completeness\",\"answers\":[{\"id\":\"$F3\",\"record\":\"reverified\",\"reason\":\"x\"}]}]"
refused "an answer for an id the ledger does not hold" scrutiny \
    '[{"seat":"completeness","run":"m2-completeness","answers":[{"id":"0000000000000000","record":"holds"}]}]'
refused "an inactive rule id" scrutiny \
    '[{"seat":"completeness","run":"m2-completeness","findings":[{"severity":"blocking","summary":"r","rule_id":"panel/no-such-rule"}]}]'
refused "an unsafe path" scrutiny \
    '[{"seat":"completeness","run":"m2-completeness","findings":[{"severity":"blocking","summary":"p","path":"../etc/x"}]}]'
refused "lines without a path" scrutiny \
    '[{"seat":"completeness","run":"m2-completeness","findings":[{"severity":"blocking","summary":"p","lines":"3"}]}]'
LONG=$(head -c 1001 /dev/zero | tr '\0' 'a')
refused "a summary over 1000 bytes" scrutiny \
    "[{\"seat\":\"completeness\",\"run\":\"m2-completeness\",\"findings\":[{\"severity\":\"blocking\",\"summary\":\"$LONG\"}]}]"
refused "a severity in the wrong case" scrutiny \
    '[{"seat":"completeness","run":"m2-completeness","findings":[{"severity":"Blocking","summary":"s"}]}]'

# The re-check seat is planned with its open findings; it answers them by id.
run --plan scrutiny "$SESSION"
mint scrutiny m2
jq --arg id "$F1" '.decisions |= map(if .seat == "completeness" then .decision = "recheck" | .findings = [{id: $id}] else . end)' \
    "$SHIM_STORE/$SESSION/scrutiny_scope.json" > "$WORKDIR/scope" && cp "$WORKDIR/scope" "$SHIM_STORE/$SESSION/scrutiny_scope.json"
refused "a dismissed answer without a reason" scrutiny \
    "[{\"seat\":\"completeness\",\"run\":\"m2-completeness\",\"answers\":[{\"id\":\"$F1\",\"record\":\"dismissed\"}]}]"
refused "an answer record outside holds, reverified and dismissed" scrutiny \
    "[{\"seat\":\"completeness\",\"run\":\"m2-completeness\",\"answers\":[{\"id\":\"$F1\",\"record\":\"closed\"}]}]"
jq --arg id "$F1" '.decisions += [{seat: "reverifier", decision: "recheck", run: "m2-reverifier", findings: [{id: $id}], fix_review: false}]' \
    "$SHIM_STORE/$SESSION/scrutiny_scope.json" > "$WORKDIR/scope" && cp "$WORKDIR/scope" "$SHIM_STORE/$SESSION/scrutiny_scope.json"
refused "a dismissal from the re-verifier" scrutiny \
    "[{\"seat\":\"reverifier\",\"run\":\"m2-reverifier\",\"answers\":[{\"id\":\"$F1\",\"record\":\"dismissed\",\"reason\":\"not a defect\"}]}]"
refused "a reverified from the re-verifier without a reason" scrutiny \
    "[{\"seat\":\"reverifier\",\"run\":\"m2-reverifier\",\"answers\":[{\"id\":\"$F1\",\"record\":\"reverified\"}]}]"
refused "findings from a re-verifier with no fix-diff review planned" scrutiny \
    '[{"seat":"reverifier","run":"m2-reverifier","findings":[{"severity":"blocking","summary":"new"}]}]'

echo "--- script: --mark-fixed asks for re-verification and closes nothing"

snap
run --mark-fixed scrutiny "$SESSION" 0000000000000000
expect_rc "--mark-fixed on an id the ledger does not hold" 65
run --mark-fixed scrutiny "$SESSION" "$F2"
expect_rc "--mark-fixed on an advisory finding" 65
unchanged "the refused --mark-fixed calls"
run --mark-fixed scrutiny "$SESSION" "$F1"
expect_rc "--mark-fixed on an open blocking finding" 0
led -e --arg id "$F1" '.findings[$id].records[-1] | .kind == "fixed" and .writer == {kind: "agent", name: "work-on"}' >/dev/null \
    && pass "--mark-fixed writes a fixed record by the agent" || fail "last record $(led -c --arg id "$F1" '.findings[$id].records[-1]')"
led -e '.seats["scrutiny/completeness"].verdict == "blocking"' >/dev/null \
    && pass "a fixed finding still blocks its seat" || fail "seat $(led -c '.seats["scrutiny/completeness"]')"
record scrutiny "[{\"seat\":\"completeness\",\"run\":\"m2-completeness\",\"answers\":[{\"id\":\"$F1\",\"record\":\"reverified\",\"reason\":\"fixed\"}]}]"
led -e --arg id "$F1" '.findings[$id].records[-1].kind == "reverified" and ([.seats["scrutiny/completeness"].findings[] | .id] | index($id)) == null' >/dev/null \
    && pass "a reviewer's reverified answer closes the finding" || fail "after reverify $(led -c --arg id "$F1" '.findings[$id].records')"
run --mark-fixed scrutiny "$SESSION" "$F1"
expect_rc "--mark-fixed on a closed finding" 65

echo "--- script: a write that races another is refused"

snap
rm -f "$SHIM_STORE/$SESSION/.raced"
SHIM_RACE=1 run --mark-fixed scrutiny "$SESSION" "$F3"
expect_rc "--mark-fixed when the ledger changed under it" 69
rm -f "$SHIM_STORE/$SESSION/.raced"
unchanged "--mark-fixed that lost the race"


echo "--- script: answers by id, row by row"

fixture answers
run --plan scrutiny "$SESSION"
mint scrutiny a1
record scrutiny '[{"seat":"completeness","run":"a1-completeness","findings":[{"severity":"blocking","summary":"one","path":"src/a.sh"},{"severity":"blocking","summary":"two","path":"src/b.sh"}]},
                  {"seat":"justification","run":"a1-justification","findings":[{"severity":"blocking","summary":"three"}]},
                  {"seat":"intent","run":"a1-intent","findings":[]}]'
A1=$(led -r '[.findings[] | select(.summary == "one")][0].id')
A2=$(led -r '[.findings[] | select(.summary == "two")][0].id')
A3=$(led -r '[.findings[] | select(.summary == "three")][0].id')
# The full round's seats are planned with their own open findings; the
# re-verifier with the ones it is to re-check.
run --plan scrutiny "$SESSION"
jq --arg a "$A1" --arg b "$A2" --arg c "$A3" '
    .decisions = [{seat: "completeness", decision: "full", run: "a2-completeness", findings: [{id: $a}, {id: $b}]},
                  {seat: "justification", decision: "full", run: "a2-justification", findings: [{id: $c}]},
                  {seat: "intent", decision: "keep"}]' \
    "$SHIM_STORE/$SESSION/scrutiny_scope.json" > "$WORKDIR/scope" && cp "$WORKDIR/scope" "$SHIM_STORE/$SESSION/scrutiny_scope.json"
record scrutiny "[{\"seat\":\"completeness\",\"run\":\"a2-completeness\",\"answers\":[{\"id\":\"$A1\",\"record\":\"holds\"}]},
                  {\"seat\":\"justification\",\"run\":\"a2-justification\",\"answers\":[{\"id\":\"$A3\",\"record\":\"dismissed\",\"reason\":\"intended\"}]}]"
led -e --arg a "$A1" '.findings[$a].records[-1].kind == "holds" and ([.seats["scrutiny/completeness"].findings[].id] | index($a)) != null' >/dev/null \
    && pass "a holds answer keeps the finding open" || fail "A1 $(led -c --arg a "$A1" '.findings[$a].records')"
led -e --arg b "$A2" '(.findings[$b].records | map(.kind)) == ["raised"]' >/dev/null \
    && pass "a due finding the answer omits keeps its status" || fail "A2 $(led -c --arg b "$A2" '.findings[$b].records')"
led -e --arg c "$A3" '.findings[$c].records[-1] | .kind == "dismissed" and .reason == "intended" and .writer.name == "justification"' >/dev/null \
    && led -e '.seats["scrutiny/justification"].verdict == "passed"' >/dev/null \
    && pass "a dismissal with a reason by the raising seat closes the finding" || fail "A3 $(led -c --arg c "$A3" '.findings[$c].records')"
led -e '[.history[] | select(.panel == "scrutiny")] | last | .spawned == (.runs | length) and (.runs | index("a2-completeness")) != null' >/dev/null \
    && pass "a round's history spawned is the runs it recorded" || fail "history $(led -c '.history')"
run --plan scrutiny "$SESSION"
jq --arg a "$A1" '.decisions = [{seat: "completeness", decision: "keep"}, {seat: "justification", decision: "keep"},
                  {seat: "intent", decision: "keep"},
                  {seat: "reverifier", decision: "recheck", run: "a3-reverifier", findings: [{id: $a}], fix_review: false}]' \
    "$SHIM_STORE/$SESSION/scrutiny_scope.json" > "$WORKDIR/scope" && cp "$WORKDIR/scope" "$SHIM_STORE/$SESSION/scrutiny_scope.json"
record scrutiny "[{\"seat\":\"reverifier\",\"run\":\"a3-reverifier\",\"answers\":[{\"id\":\"$A1\",\"record\":\"reverified\",\"reason\":\"the fix rewrote it\"}]}]"
led -e --arg a "$A1" --arg h "$(cd "$FX/repo" && git rev-parse HEAD)" '.findings[$a].records[-1].kind == "reverified"
    and .findings[$a].records[-1].writer == {kind: "reviewer", name: "reverifier", run: "a3-reverifier"}
    and .reverified.scrutiny.run == "a3-reverifier" and .reverified.scrutiny.head == $h' >/dev/null \
    && pass "the re-verifier's reverified answer closes the finding and sets the panel's marker" \
    || fail "A1 after reverify $(led -c --arg a "$A1" '.findings[$a].records[-1]') marker $(led -c '.reverified')"
led -e '[.history[] | select(.panel == "scrutiny")] | last | .spawned == (.runs | length) and (.runs | index("a3-reverifier")) != null' >/dev/null \
    && pass "a re-verification run is counted in its round's spawned" || fail "history $(led -c '.history')"
refused "a malformed answer id" scrutiny '[{"seat":"intent","run":"a4-intent","answers":[{"id":"ABC","record":"holds"}]}]'
LONG=$(head -c 1001 /dev/zero | tr '\0' 'a')
run --plan scrutiny "$SESSION"
jq --arg a "$A2" '.decisions = [{seat: "completeness", decision: "full", run: "a5-completeness", findings: [{id: $a}]}]' \
    "$SHIM_STORE/$SESSION/scrutiny_scope.json" > "$WORKDIR/scope" && cp "$WORKDIR/scope" "$SHIM_STORE/$SESSION/scrutiny_scope.json"
refused "an answer reason over 1000 bytes" scrutiny \
    "[{\"seat\":\"completeness\",\"run\":\"a5-completeness\",\"answers\":[{\"id\":\"$A2\",\"record\":\"dismissed\",\"reason\":\"$LONG\"}]}]"
snap
printf '%s\n' "[{\"seat\":\"completeness\",\"run\":\"a5-completeness\",\"answers\":[{\"id\":\"$A2\",\"record\":\"holds\"}]}]" > "$WORKDIR/round.json"
rm -f "$SHIM_STORE/$SESSION/.raced"
SHIM_RACE=1 NO_AUTORUN=1 run --record scrutiny "$SESSION" "$WORKDIR/round.json"
expect_rc "--record when the ledger changed under it" 69
rm -f "$SHIM_STORE/$SESSION/.raced"
unchanged "--record that lost the race"

echo "--- script: the ledger --record writes, read by review-level.sh report"

fixture rlreport
run --plan scrutiny "$SESSION"
record scrutiny "$ALL_PASS"
RL=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT_DIR/review-level.sh" report "$SESSION" 2>"$WORKDIR/rl.err" | sed -n 2p)
[ "$(printf '%s' "$RL" | awk -F'\t' '{ print $1 "=" $NF }')" = "rlreport=3" ] \
    && pass "review-level.sh report counts the three runs a recorded round spawned" \
    || fail "report row [$RL] err [$(cat "$WORKDIR/rl.err")]"

echo "--- script: decider entries, bound to koto's own log"

fixture decider
run --plan scrutiny "$SESSION"
mkdir -p "$SHIM_STORE/$SESSION/sessiondir"
LOG="$SHIM_STORE/$SESSION/sessiondir/koto-$SESSION.state.jsonl"
dc() { # dc <visit_seq> <rule_id> <outcome>
    printf '{"type":"decider_checked","payload":{"state":"scrutiny","visit_seq":%s,"gate":"scrutiny_decider","rule_id":"%s","declaration_hash":"abcd1234","outcome":"%s","input_sha256":"ef01"}}\n' "$1" "$2" "$3" >> "$LOG"
}
dent() { # dent <visit_seq> <rule_id> <outcome>
    printf '{"decider":{"state":"scrutiny","visit_seq":%s,"gate":"scrutiny_decider","rule_id":"%s","declaration_hash":"abcd1234","input_sha256":"ef01","outcome":"%s"}}' "$1" "$2" "$3"
}
: > "$LOG"
refused "a decider entry koto's log does not hold" scrutiny "[$(dent 1 rs-007 fail)]"
# koto 0.20.0 records the agent's answer to a criterion the decider couldn't
# grade as decider_check_answered; it is the agent's, and backs no entry.
printf '{"type":"decider_check_answered","payload":{"state":"scrutiny","visit_seq":1,"gate":"scrutiny_decider","rule_id":"rs-007","declaration_hash":"abcd1234","input_sha256":"ef01","answer":"pass"}}\n' >> "$LOG"
refused "a decider entry backed only by the agent's answer" scrutiny "[$(dent 1 rs-007 pass)]"
grep -q "holds no decider_checked event" "$WORKDIR/stderr" \
    && pass "the refusal says koto's log holds no decider verdict for it" || fail "stderr: $(cat "$WORKDIR/stderr")"
: > "$LOG"
refused "a decider entry with a malformed gate" scrutiny '[{"decider":{"state":"scrutiny","visit_seq":1,"gate":"Bad Gate","rule_id":"rs-007","declaration_hash":"abcd1234","outcome":"fail"}}]'
dc 1 rs-007 fail
refused "a decider entry whose input hash differs from the event's" scrutiny '[{"decider":{"state":"scrutiny","visit_seq":1,"gate":"scrutiny_decider","rule_id":"rs-007","declaration_hash":"abcd1234","input_sha256":"ffff","outcome":"fail"}}]'
: > "$LOG"
refused "a decider entry with no visit_seq" scrutiny '[{"decider":{"state":"scrutiny","gate":"scrutiny_decider","rule_id":"rs-007","declaration_hash":"abcd1234","outcome":"fail"}}]'
dc 1 rs-007 fail
record scrutiny "[$(dent 1 rs-007 fail)]"
D1=$(led -r '[.findings[] | select(.raiser.kind == "decider")][0].id')
led -e --arg id "$D1" '.findings[$id] | .severity == "blocking" and .raiser.name == "scrutiny_decider/rs-007"
    and .raiser.ref.visit_seq == 1 and .summary == "rs-007" and .rule_id == "rs-007" and .location.kind == "none"
    and .records[-1].kind == "raised"' >/dev/null \
    && pass "a decider fail raises a blocking finding under its criterion" || fail "decider finding $(led -c --arg id "$D1" '.findings[$id]')"
refused "a decider event that already backed an entry" scrutiny "[$(dent 1 rs-007 fail)]"
dc 2 rs-007 escape
record scrutiny "[$(dent 2 rs-007 escape)]"
[ "$(led -r --arg id "$D1" '.findings[$id].records[-1].kind')" = unverified ] \
    && pass "a decider escape on its finding writes unverified" || fail "escape record"
VS=10
for o in not_graded unanswered something_new; do
    VS=$((VS + 1)); dc "$VS" rs-008 "$o"; record scrutiny "[$(dent "$VS" rs-008 "$o")]"
done
D2=$(led -r '[.findings[] | select(.raiser.name == "scrutiny_decider/rs-008")][0].id')
led -e --arg id "$D2" '(.findings[$id].records | map(.kind)) == ["unverified", "unverified", "unverified"]' >/dev/null \
    && pass "not_graded, unanswered and an unknown outcome create the criterion's finding as unverified, then keep it there" \
    || fail "rs-008 records $(led -c --arg id "$D2" '.findings[$id].records')"
dc 4 rs-009 pass
record scrutiny "[$(dent 4 rs-009 pass)]"
[ "$(led '[.findings[] | select(.raiser.name == "scrutiny_decider/rs-009")] | length')" = 0 ] \
    && pass "a decider pass with no finding for its criterion writes nothing" || fail "rs-009 wrote a finding"
dc 5 rs-007 pass
record scrutiny "[$(dent 5 rs-007 pass)]"
led -e --arg id "$D1" '.findings[$id].records[-1] | .kind == "reverified" and .writer.kind == "decider"' >/dev/null \
    && pass "a decider pass closes its own finding" || fail "rs-007 last $(led -c --arg id "$D1" '.findings[$id].records[-1]')"

echo "--- script: a failed koto session dir is not a missing log"

# A session with no log yet imports no decider verdict and records the round;
# a `koto session dir` that fails is not read as a missing log: --record exits
# 66 with koto's error and writes nothing, so the round can't pass on a log it
# never read.
fixture nolog-record
run --plan scrutiny "$SESSION"
printf '%s\n' "$ALL_PASS" > "$WORKDIR/round.json"
run --record scrutiny "$SESSION" "$WORKDIR/round.json"
expect_rc "--record with no session log yet" 0
fixture sdfail-record
run --plan scrutiny "$SESSION"
expect_rc "--plan for a session whose koto session dir fails" 0
snap
printf '%s\n' "$ALL_PASS" > "$WORKDIR/round.json"
run --record scrutiny "$SESSION" "$WORKDIR/round.json"
expect_rc "--record when koto session dir fails" 66
grep -qF 'koto session dir failed' "$WORKDIR/stderr" \
    && grep -qF 'koto shim: the session store is unavailable' "$WORKDIR/stderr" \
    && pass "--record names the failed koto session dir and passes koto's error on" \
    || fail "--record's stderr: $(cat "$WORKDIR/stderr")"
unchanged "--record when koto session dir fails"
printf '%s\n' '[{"decider":{"state":"scrutiny","visit_seq":1,"gate":"scrutiny_decider","rule_id":"rs-007","declaration_hash":"abcd1234","outcome":"escape"}}]' \
    > "$WORKDIR/round.json"
NO_AUTORUN=1 run --record scrutiny "$SESSION" "$WORKDIR/round.json"
expect_rc "--record of a named decider entry when koto session dir fails" 66
unchanged "--record of a named decider entry when koto session dir fails"

echo "--- script: a decider batch's verdicts, imported from koto's log by mode"

BCRIT=work-on/scrutiny-decision-reasons
BNAME="scrutiny_decider/$BCRIT"
# bfix <name>: a fixture with a planned scrutiny round and an empty session log.
bfix() {
    fixture "$1"
    run --plan scrutiny "$SESSION"
    mkdir -p "$SHIM_STORE/$SESSION/sessiondir"
    LOG="$SHIM_STORE/$SESSION/sessiondir/koto-$SESSION.state.jsonl"
    : > "$LOG"
    BN=0
}
# bc <visit_seq> <outcome> <mode|-> [<state>] [<rule_id>]: a decider_checked
# event for the batch; mode `-` leaves the field out.
bc() {
    jq -nc --argjson v "$1" --arg o "$2" --arg m "$3" --arg st "${4:-scrutiny}" --arg r "${5:-$BCRIT}" \
        '{type: "decider_checked", payload: ({state: $st, visit_seq: $v, gate: "scrutiny_decider", rule_id: $r,
          declaration_hash: "abcd1234", outcome: $o, input_sha256: "ef01"} + (if $m == "-" then {} else {mode: $m} end))}' >> "$LOG"
}
# seats [<panel>]: records every seat of the panel's round clean, under fresh
# run ids, so the round names no decider entry.
seats() {
    local p=${1:-scrutiny} s round='['
    BN=$((BN + 1))
    mint "$p" "b$BN"
    case "$p" in
        qa) round='[{"seat":"tester","findings":[]}]' ;;
        *) round='[{"seat":"completeness","findings":[]},{"seat":"justification","findings":[]},{"seat":"intent","findings":[]}]' ;;
    esac
    record "$p" "$round"
}
bfind() { led -c --arg n "${1:-$BNAME}" '[.findings[] | select(.raiser.kind == "decider" and .raiser.name == $n)]'; }

# A fail's severity is the event's mode: advisory only for shadow.
for m in shadow veto -; do
    bfix "batch-fail-$m"
    bc 1 fail "$m"
    seats
    want=blocking; [ "$m" = shadow ] && want=advisory
    [ "$(bfind | jq -r --arg r "$BCRIT" '[.[] | select(.rule_id == $r) | .severity] | join(",")')" = "$want" ] \
        && pass "a $m fail from the log, with no entry naming it, raises a $want finding under $BCRIT" \
        || fail "a $m fail raised $(bfind)"
done

# A veto fail, then a pass: reverified, and the panel passes.
bfix batch-veto-pass
bc 1 fail veto
seats
run --verdict scrutiny "$SESSION"
expect_rc "--verdict with the batch's veto fail open" 1
bc 2 pass veto
seats
[ "$(bfind | jq -r '.[0].records | map(.kind) | join(",")')" = "raised,reverified" ] \
    && pass "a later veto pass adds a decider reverified record" || fail "records $(bfind)"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict after the batch's pass, nothing else open" 0

# A shadow fail, then a pass: reverified, still advisory.
bfix batch-shadow-pass
bc 1 fail shadow
seats
bc 2 pass shadow
seats
[ "$(bfind | jq -r '.[0] | "\(.severity)|\(.records | map(.kind) | join(","))"')" = "advisory|raised,reverified" ] \
    && pass "a later shadow pass adds reverified and the finding stays advisory" || fail "finding $(bfind)"

# A pass with no earlier finding adds nothing; shadow non-verdicts add nothing.
bfix batch-quiet
bc 1 pass veto
bc 2 escape shadow
bc 3 unanswered shadow
bc 4 not_graded shadow
seats
[ "$(bfind | jq length)" = 0 ] \
    && pass "a pass with no finding, and a shadow escape, unanswered and not_graded, add no finding" \
    || fail "findings $(bfind)"
[ "$(led '.decider_events | length')" = 4 ] && pass "each of the four events is marked used" \
    || fail "decider_events $(led -c '.decider_events')"

# A veto escape with no earlier finding: blocking, only unverified.
bfix batch-veto-escape
bc 1 escape veto
seats
[ "$(bfind | jq -r '.[0] | "\(.severity)|\(.records | map(.kind) | join(","))"')" = "blocking|unverified" ] \
    && pass "a veto escape with no finding raises a blocking finding whose only record is unverified" \
    || fail "finding $(bfind)"

# One group: a fail wins over the passes beside it. An earlier visit's unused
# events come in with the next record; another state's never do.
bfix batch-group
bc 1 pass veto
bc 1 fail veto
bc 1 pass veto
bc 2 fail veto
bc 1 fail veto review_level_check
seats
[ "$(bfind | jq -r '.[0].records | map(.kind) | join(",")')" = "raised,raised" ] \
    && pass "of one group's events the fail is recorded, and visit 2's fail beside it" || fail "records $(bfind)"
[ "$(led -c '.decider_events | sort')" = '["scrutiny|1|scrutiny_decider|work-on/scrutiny-decision-reasons|abcd1234","scrutiny|2|scrutiny_decider|work-on/scrutiny-decision-reasons|abcd1234"]' ] \
    && pass "one event per group is imported, and none of another state" || fail "decider_events $(led -c '.decider_events')"
snap
seats
[ "$(led '.decider_events | length')" = 2 ] && [ "$(bfind | jq -r '.[0].records | length')" = 2 ] \
    && pass "a second record over the same log imports nothing again" || fail "after a second record $(led -c '.decider_events') $(bfind)"
refused "a round file naming an event the log already backed" scrutiny \
    '[{"decider":{"state":"scrutiny","visit_seq":2,"gate":"scrutiny_decider","rule_id":"work-on/scrutiny-decision-reasons","declaration_hash":"abcd1234","input_sha256":"ef01","outcome":"fail"}}]'

# A round file's own fail entry takes the matched event's mode.
bfix batch-named-shadow
bc 1 fail shadow
record scrutiny '[{"decider":{"state":"scrutiny","visit_seq":1,"gate":"scrutiny_decider","rule_id":"work-on/scrutiny-decision-reasons","declaration_hash":"abcd1234","input_sha256":"ef01","outcome":"fail","mode":"veto"}}]'
[ "$(bfind | jq -r '.[0].severity')" = advisory ] \
    && pass "a named fail matching a shadow event is advisory, whatever the round file says" || fail "finding $(bfind)"

# The qa panel imports its own state's events.
bfix batch-qa
run --plan qa "$SESSION"
bc 1 fail veto qa_validation
bc 1 fail veto scrutiny
seats qa
[ "$(led -r --arg n "$BNAME" '[.findings[] | select(.raiser.name == $n) | .panel] | join(",")')" = qa ] \
    && pass "--record qa imports qa_validation's event and not scrutiny's" || fail "findings $(led -c '.findings')"

# The agent's answer backs nothing; a missing log imports nothing; an
# unreadable one refuses the round.
bfix batch-answered
printf '%s\n' '{"type":"decider_check_answered","payload":{"state":"scrutiny","visit_seq":1,"gate":"scrutiny_decider","rule_id":"work-on/scrutiny-decision-reasons","declaration_hash":"abcd1234","input_sha256":"ef01","answer":"fail"}}' >> "$LOG"
seats
[ "$(bfind | jq length)|$(led '.decider_events // [] | length')" = "0|0" ] \
    && pass "a decider_check_answered event creates no ledger entry" || fail "findings $(bfind)"
rm -f "$LOG"
seats
[ "$RC" = 0 ] && [ "$(bfind | jq length)" = 0 ] && pass "a missing session log imports nothing" || fail "rc $RC findings $(bfind)"
if [ "$(id -u)" -ne 0 ]; then
    bc 1 fail veto
    chmod 000 "$LOG"
    BN=$((BN + 1)); mint scrutiny "b$BN"
    refused "an existing session log that can't be read" scrutiny "[{\"seat\":\"completeness\",\"run\":\"b$BN-completeness\",\"findings\":[]}]"
    chmod 644 "$LOG"
else
    echo "SKIP: running as root, an unreadable file is readable"
fi

# One blocking and one advisory batch finding: only the blocking one counts.
bfix batch-count
bc 1 fail shadow
bc 1 fail veto scrutiny rs-007
seats
run --open-count scrutiny "$SESSION"
[ "$RC" = 0 ] && [ "$OUT" = 1 ] && pass "--open-count counts the blocking finding only" || fail "--open-count rc $RC out [$OUT]"
run --verdict scrutiny "$SESSION"
expect_rc "--verdict with one blocking and one advisory batch finding" 1
case "$OUT" in
    *rs-007*) case "$OUT" in *"$BCRIT"*) fail "--verdict printed the advisory finding: $OUT" ;; *) pass "--verdict prints only the blocking finding" ;; esac ;;
    *) fail "--verdict did not print the blocking finding: $OUT" ;;
esac
RB=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT_DIR/panel-retry-budget.sh" "$SESSION" scrutiny 2>"$WORKDIR/rb.err")
RBRC=$?
[ "$RBRC" = 0 ] && [ "$(cat "$SHIM_STORE/$SESSION/panel_retries" 2>/dev/null)" = "scrutiny 1" ] \
    && pass "panel-retry-budget.sh reads a count of 1" || fail "retry budget rc $RBRC out [$RB] err [$(cat "$WORKDIR/rb.err")]"

# --plan never reads the log: its decisions are the same with batch events of
# every outcome in it.
bfix batch-plan
seats
run --plan scrutiny "$SESSION"
jq -S '.decisions' "$SHIM_STORE/$SESSION/scrutiny_scope.json" > "$WORKDIR/plan.before"
for o in pass fail escape unanswered not_graded; do bc 3 "$o" shadow; bc 4 "$o" veto; done
run --plan scrutiny "$SESSION"
jq -S '.decisions' "$SHIM_STORE/$SESSION/scrutiny_scope.json" > "$WORKDIR/plan.after"
cmp -s "$WORKDIR/plan.before" "$WORKDIR/plan.after" \
    && pass "--plan writes the same decisions with batch events in the log" || fail "--plan decisions changed: $(diff "$WORKDIR/plan.before" "$WORKDIR/plan.after")"

# --- edited tests: every seat judges each one ----------------------------------
echo "--- --record: every seat judges each edited test"

# te_fixture <name>: the fixture, with tests/t_test.sh (ten lines) and
# tests/u_test.sh (three) committed and impl_base moved to that commit, then
# one commit that removes a line of t_test.sh (an edit), appends one to
# u_test.sh (an addition) and changes src/a.sh.
te_fixture() {
    fixture "$1"
    (cd "$FX/repo" && mkdir -p tests && seq 1 10 > tests/t_test.sh && seq 1 3 > tests/u_test.sh \
        && git add -A && git commit -q -m "test: base tests" && git rev-parse HEAD) > "$SHIM_STORE/$SESSION/impl_base" 2>/dev/null
    (cd "$FX/repo" && sed -i.bak '2d' tests/t_test.sh && rm -f tests/t_test.sh.bak && printf '4\n' >> tests/u_test.sh \
        && seq 1 60 > src/a.sh && git commit -q -am "fix: correct t") >/dev/null 2>&1
}
T_OK='{"path":"tests/t_test.sh","judgment":"corrects"}'

te_fixture te-unjudged
run --plan scrutiny "$SESSION"
printf '[{"seat":"completeness","findings":[],"test_edits":[%s]},{"seat":"justification","findings":[]},{"seat":"intent","findings":[],"test_edits":[%s]}]\n' \
    "$T_OK" "$T_OK" > "$WORKDIR/round.json"
cp "$SHIM_STORE/$SESSION/verdict_ledger.json" "$WORKDIR/te-ledger.before"
run --record scrutiny "$SESSION" "$WORKDIR/round.json"
ERRTXT=$(cat "$WORKDIR/stderr")
[ "$RC" -eq 65 ] && pass "a round with a seat that didn't judge the edited test: exit 65" \
    || fail "unjudged round: exit $RC ($ERRTXT)"
case "$ERRTXT" in
    *"rule review/test-edit-judgment"*"seat [justification] did not judge the edited test [tests/t_test.sh]"*)
        pass "the refusal names the rule, the seat and the test" ;;
    *) fail "the refusal reads [$ERRTXT]" ;;
esac
cmp -s "$WORKDIR/te-ledger.before" "$SHIM_STORE/$SESSION/verdict_ledger.json" \
    && pass "a refused round leaves the ledger byte-identical" || fail "a refused round changed the ledger"
case "$ERRTXT" in *u_test.sh*) fail "a test that only gained lines was asked for a judgment" ;;
    *) pass "a test that only gained lines needs no judgment" ;; esac

printf '[{"seat":"completeness","findings":[],"test_edits":[%s]},{"seat":"justification","findings":[],"test_edits":[{"path":"tests/t_test.sh","judgment":"fine"}]},{"seat":"intent","findings":[],"test_edits":[%s]}]\n' \
    "$T_OK" "$T_OK" > "$WORKDIR/round.json"
run --record scrutiny "$SESSION" "$WORKDIR/round.json"
[ "$RC" -eq 65 ] && grep -q 'is not corrects or weakens' "$WORKDIR/stderr" \
    && pass "a judgment other than corrects or weakens: exit 65" || fail "bad judgment: exit $RC ($(cat "$WORKDIR/stderr"))"

printf '[{"seat":"completeness","findings":[],"test_edits":[%s]},{"seat":"justification","findings":[],"test_edits":[%s]},{"seat":"intent","findings":[],"test_edits":[%s]}]\n' \
    "$T_OK" "$T_OK" "$T_OK" > "$WORKDIR/round.json"
run --record scrutiny "$SESSION" "$WORKDIR/round.json"
[ "$RC" -eq 0 ] && pass "every seat judged the edited test corrects: recorded" || fail "corrects round: exit $RC ($(cat "$WORKDIR/stderr"))"
L="$SHIM_STORE/$SESSION/verdict_ledger.json"
[ "$(jq '[.findings[]] | length' "$L")" = 0 ] && pass "corrects judgments raise no finding" \
    || fail "corrects judgments raised $(jq -c '[.findings[]]' "$L")"
[ "$(jq -r '.seats["scrutiny/justification"].test_edits[0] | "\(.path) \(.judgment)"' "$L")" = "tests/t_test.sh corrects" ] \
    && pass "each seat entry keeps its judgments" || fail "seat entry: $(jq -c '.seats["scrutiny/justification"]' "$L")"
run --verdict scrutiny "$SESSION"
[ "$RC" -eq 0 ] && pass "a corrects-only round passes the verdict" || fail "corrects round verdict: exit $RC"

te_fixture te-weakens
run --plan scrutiny "$SESSION"
printf '[{"seat":"completeness","findings":[],"test_edits":[{"path":"tests/t_test.sh","judgment":"weakens","reason":"drops the check on line 2"}]},{"seat":"justification","findings":[],"test_edits":[%s]},{"seat":"intent","findings":[],"test_edits":[%s]}]\n' \
    "$T_OK" "$T_OK" > "$WORKDIR/round.json"
run --record scrutiny "$SESSION" "$WORKDIR/round.json"
[ "$RC" -eq 0 ] && pass "a round with a weakens judgment is recorded" || fail "weakens round: exit $RC ($(cat "$WORKDIR/stderr"))"
L="$SHIM_STORE/$SESSION/verdict_ledger.json"
GOT=$(jq -r '[.findings[]] | .[0] | "\(.severity)|\(.raiser.name)|\(.rule_id)|\(.location.path)|\(.summary)"' "$L")
[ "$GOT" = "blocking|completeness|review/test-edit-weakens|tests/t_test.sh|the edit to tests/t_test.sh weakens the test: drops the check on line 2" ] \
    && pass "a weakens judgment is a blocking finding raised by that seat, under review/test-edit-weakens" \
    || fail "weakens finding: $GOT"
[ "$(jq -r '.seats["scrutiny/completeness"].verdict' "$L")" = blocking ] \
    && pass "the seat that judged weakens is blocking" || fail "completeness verdict: $(jq -r '.seats["scrutiny/completeness"].verdict' "$L")"
run --verdict scrutiny "$SESSION"
[ "$RC" -eq 1 ] && pass "a weakens finding holds the panel's verdict" || fail "weakens verdict: exit $RC"
case "$OUT" in *'"rule_id":"review/test-edit-weakens"'*) pass "the verdict prints it under review/test-edit-weakens" ;;
    *) fail "the verdict printed [$OUT]" ;; esac

# A change with no edited test records rounds with no test_edits, as before.
fixture te-none
run --plan scrutiny "$SESSION"
record scrutiny '[{"seat":"completeness","findings":[]},{"seat":"justification","findings":[]},{"seat":"intent","findings":[]}]'
[ "$RC" -eq 0 ] && pass "no edited test: a round without test_edits records" || fail "no edited test: exit $RC"

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

# fix_determination reads the issue's labels with gh; the stand-in serves an
# unlabelled issue, so these runs are changes.
. "$PLUGIN_ROOT/scripts/lib/gh-issue-testlib.sh"
gh_issue_stand_in "$WORKDIR/gh-bin"

NEXT_STATE=""
submit() {
    NEXT_STATE=$(koto next "$1" --with-data "$2" --no-cleanup 2>/dev/null \
        | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
}
# tick <session>: a tick with nothing submitted, the way a panel advances once
# its round is recorded and the <panel>_verdict gate passes.
tick() {
    NEXT_STATE=$(koto next "$1" --no-cleanup 2>/dev/null \
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
    # staleness_check routes on its own gate: no GitHub remote, so exit 3.
    submit "$s" '{"status":"override"}'
    printf 'plan\n' | koto context add "$s" plan.md >/dev/null 2>&1
    printf 'AC: the issue body\n' | koto context add "$s" context.md >/dev/null 2>&1
    submit "$s" '{"plan_outcome":"plan_ready"}'
    git rev-parse main | koto context add "$s" impl_base >/dev/null 2>&1
    # The full review level keeps all three panels on the path.
    "$PLUGIN_ROOT/skills/work-on/scripts/review-level.sh" set "$s" full >/dev/null 2>&1 \
        || { fail "$s: review-level.sh set full failed"; return 1; }
    # Into fix_determination, whose action binds UNIT_KIND; koto routes on it
    # from the next tick, to implementation.
    koto next "$s" --no-cleanup >/dev/null 2>&1
    koto next "$s" --no-cleanup >/dev/null 2>&1
    submit "$s" '{"implementation_status":"complete"}'
    [ "$NEXT_STATE" = issue_type_routing ] && submit "$s" '{"issue_type":"code"}'
    [ "$NEXT_STATE" = scrutiny ] || { fail "$s: walk stopped at [$NEXT_STATE] before scrutiny"; return 1; }

    printf '%s\n' '[{"seat":"completeness","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
        {"seat":"justification","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
        {"seat":"intent","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]}]' > "$WORKDIR/r.json"
    panel_round_runs "$s" scrutiny "$WORKDIR/r.json"
    "$SCRIPT" --record scrutiny "$s" "$WORKDIR/r.json" || fail "$s: --record scrutiny failed"
    tick "$s"
    [ "$NEXT_STATE" = review ] || { fail "$s: scrutiny went to [$NEXT_STATE], not review"; return 1; }

    printf '%s\n' '[{"seat":"pragmatic","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
        {"seat":"architect","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]},
        {"seat":"maintainer","blocking_count":0,"cited":[{"path":"src/a.sh","lines":"41-50"}]}]' > "$WORKDIR/r.json"
    panel_round_runs "$s" review "$WORKDIR/r.json"
    "$SCRIPT" --record review "$s" "$WORKDIR/r.json" || fail "$s: --record review failed"
    tick "$s"
    [ "$NEXT_STATE" = qa_validation ] || { fail "$s: review went to [$NEXT_STATE], not qa_validation"; return 1; }

    printf '%s\n' '[{"seat":"tester","blocking_count":1,"cited":[{"path":"src/a.sh","lines":"41-50"}],
        "findings":[{"severity":"blocking","summary":"no test covers lines 41-50","path":"tests/a_test.sh"}]}]' > "$WORKDIR/r.json"
    panel_round_runs "$s" qa "$WORKDIR/r.json"
    "$SCRIPT" --record qa "$s" "$WORKDIR/r.json" || fail "$s: --record qa failed"
    # A tick with nothing submitted re-runs --plan, which must leave the
    # recorded blocking round standing: qa_verdict exits 1, so the retry
    # below is accepted.
    tick "$s"
    [ "$NEXT_STATE" = qa_validation ] || { fail "$s: a blocking QA round went to [$NEXT_STATE]"; return 1; }
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

echo "--- engine: a QA retry runs one fix-diff review, carries review, and re-verifies QA's finding"

S=qa-narrow
if engine_to_qa_retry "$S"; then
    mkdir -p tests && printf 'test\n' > tests/a_test.sh && git add tests && git commit -q -m "test: cover a.sh"
    submit "$S" '{"implementation_status":"complete"}'
    [ "$NEXT_STATE" = issue_type_routing ] && submit "$S" '{"issue_type":"code"}'
    [ "$NEXT_STATE" = scrutiny ] && pass "the run stops at scrutiny, the first panel the retry enters" \
        || fail "the run stopped at [$NEXT_STATE], expected scrutiny"
    GOT=$(koto context get "$S" scrutiny_scope.json 2>/dev/null \
        | jq -r '[.decisions[] | "\(.seat)=\(.decision)\(if .fix_review then "+review" else "" end)"] | join(" ")')
    [ "$GOT" = "completeness=keep justification=keep intent=keep reverifier=recheck+review" ] \
        && pass "scrutiny keeps every seat and plans one fix-diff review" || fail "scrutiny decisions are [$GOT]"
    printf '[{"seat":"reverifier"}]\n' > "$WORKDIR/r.json"
    panel_round_runs "$S" scrutiny "$WORKDIR/r.json"
    "$SCRIPT" --record scrutiny "$S" "$WORKDIR/r.json" || fail "$S: --record scrutiny failed"
    tick "$S"
    [ "$NEXT_STATE" = qa_validation ] \
        && pass "with the fix-diff review recorded, review carries and the run reaches qa_validation" \
        || fail "the run stopped at [$NEXT_STATE], expected qa_validation"
    koto context get "$S" review_results.json 2>/dev/null | jq -e '.carried == true' >/dev/null 2>&1 \
        && pass "review carried its verdict" || fail "review has no carried review_results.json"
    GOT=$(koto context get "$S" qa_scope.json 2>/dev/null \
        | jq -r '.decisions[] | select(.seat == "reverifier") | "\(.decision)|\(.findings[0].summary)|\(.fix_review)"')
    [ "$GOT" = "recheck|no test covers lines 41-50|false" ] \
        && pass "QA re-verifies its finding, with no second fix-diff review" || fail "qa_scope.json re-verifier is [$GOT]"
    GOT=$(koto context get "$S" verdict_ledger.json 2>/dev/null \
        | jq -c '[.history[] | select(.round == 2) | [.panel, .spawned]]')
    [ "$GOT" = '[["scrutiny",1],["review",0],["qa",1]]' ] \
        && pass "round 2 made two runs: the fix-diff review and QA's re-verification" || fail "round 2 history is $GOT"
    for st in scrutiny review qa_validation; do
        N=$(visits "$S" "$st")
        [ "$N" = 2 ] && pass "koto's log records both $st rounds" || fail "koto's log has $N transitions into $st, expected 2"
    done
    # The re-check passes, but its verdict isn't recorded: qa_verdict holds,
    # and a results key written by hand changes nothing.
    printf '{"passed": true, "round": 2}\n' | koto context add "$S" qa_results.json >/dev/null 2>&1
    tick "$S"
    [ "$NEXT_STATE" = qa_validation ] \
        && pass "an unrecorded re-check holds qa_validation" \
        || fail "an unrecorded re-check advanced to [$NEXT_STATE]"
    # The re-verifier answers the failing scenario by id: it now passes.
    QID=$(koto context get "$S" verdict_ledger.json 2>/dev/null | jq -r '.seats["qa/tester"].findings[0].id // empty')
    jq -n --arg id "$QID" '[{seat: "reverifier", answers: [{id: $id, record: "reverified", reason: "the scenario passes"}]}]' \
        > "$WORKDIR/r.json"
    panel_round_runs "$S" qa "$WORKDIR/r.json"
    "$SCRIPT" --record qa "$S" "$WORKDIR/r.json" || fail "$S: --record qa failed"
    tick "$S"
    # koto runs verification itself on entry; this fixture commits no
    # verification map, so the run fails closed there in the same tick. The
    # transition into verification in koto's log is the advance.
    { [ "$NEXT_STATE" = verification ] || [ "$(visits "$S" verification)" = 1 ]; } \
        && pass "the recorded re-check advances to verification" \
        || fail "the recorded re-check went to [$NEXT_STATE]"
fi

echo "--- engine: a fix on cited lines stops at scrutiny for one run, not three"

S=qa-wide
if engine_to_qa_retry "$S"; then
    awk 'NR == 45 { print "forty-five"; next } { print }' src/a.sh > x && mv x src/a.sh && git commit -q -am "fix: a.sh"
    submit "$S" '{"implementation_status":"complete"}'
    [ "$NEXT_STATE" = issue_type_routing ] && submit "$S" '{"issue_type":"code"}'
    [ "$NEXT_STATE" = scrutiny ] && pass "the run stops at scrutiny" || fail "the run went to [$NEXT_STATE], expected scrutiny"
    GOT=$(koto context get "$S" scrutiny_scope.json 2>/dev/null | jq -r '[.decisions[] | select(.decision != "keep") | .seat] | join(",")')
    [ "$GOT" = reverifier ] && pass "no passed seat re-runs; one re-verifier reviews the fix" || fail "scrutiny runs are [$GOT]"
    koto context exists "$S" scrutiny_results.json 2>/dev/null \
        && fail "a scrutiny verdict is in place while the fix-diff review must run" \
        || pass "no scrutiny verdict stands in for the fix-diff review"
    tick "$S"
    [ "$NEXT_STATE" = scrutiny ] && pass "scrutiny holds until the fix-diff review is recorded" \
        || fail "scrutiny advanced to [$NEXT_STATE] before the fix-diff review was recorded"
fi
cd "$WORKDIR" || exit 1

# Every finding --verdict prints is at panel/open-finding's stage, whichever
# rule it names.
rf_test_verify "panel-scope --verdict" panel/open-finding

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
