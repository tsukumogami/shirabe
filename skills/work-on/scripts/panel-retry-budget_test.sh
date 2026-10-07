#!/usr/bin/env bash
# panel-retry-budget_test.sh -- the panel retry cap that follows progress
# Part of the work-on skill
#
# panel-retry-budget.sh decides whether a review panel that found blocking
# defects may send the work back to implementation again, and records the
# retries it grants in the koto context key `panel_retries`. The rule is in
# docs/decisions/DECISION-work-on-panel-retry-progress-cap-2026-10-01.md: two
# retries whatever the counts, a third only when the same panel's count fell,
# never a fourth.
#
# Each sequence case starts a fresh session and feeds it rounds in order, each
# round "<panel>:<count>", and asserts the verdict of every round. A granted
# round is recorded; a refused one is not, so a sequence can continue past a
# refusal only to show that the refusal left the record alone.
#
# Three parts:
#
#   rule cases -- sequences against a koto stand-in on PATH that keeps each
#     key as a file. No engine, so they also run on the bash 3.2 floor leg.
#   fail-closed cases -- a record that can't be written, can't be read back,
#     or holds a line the script didn't write is a refusal, never a grant.
#   shipped-text cases -- no shipped /work-on file but the three panel
#     directives (and SKILL.md's description of the script) names
#     `panel_retries`, so no clearing site can reset it; and,
#     when koto is present, the same sequences against a real session.
#
# Usage: panel-retry-budget_test.sh
#
# Exit codes:
#   0 -- all cases pass (the real-koto case may have been skipped without koto)
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/panel-retry-budget.sh"
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PHASES="$SKILL_DIR/references/phases"
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
PLUGIN_ROOT=$(cd "$SKILL_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT is missing or not executable" >&2; exit 1; }

WORKDIR=$(mktemp -d)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

export HOME="$WORKDIR/home"
mkdir -p "$HOME"

# --- the koto stand-in ---------------------------------------------------------
#
# `koto context add|get|exists|remove <session> <key>` against
# $SHIM_STORE/<session>/<key>; `get` and `exists` exit 1 for an absent key, as
# koto does. SHIM_FAIL_ADD=1 makes `add` fail without writing; SHIM_DROP_ADD=1
# makes it report success without writing, the case only a read-back catches.

SHIM_BIN="$WORKDIR/shim-bin"
SHIM_STORE="$WORKDIR/shim-store"
mkdir -p "$SHIM_BIN" "$SHIM_STORE"
cat > "$SHIM_BIN/koto" <<'SHIM'
#!/usr/bin/env bash
[ "$1" = context ] || { echo "koto shim: unsupported: $*" >&2; exit 2; }
f="$SHIM_STORE/$3/$4"
case "$2" in
    add)
        [ "${SHIM_FAIL_ADD:-0}" = 1 ] && { cat >/dev/null; exit 1; }
        [ "${SHIM_DROP_ADD:-0}" = 1 ] && { cat >/dev/null; exit 0; }
        mkdir -p "$SHIM_STORE/$3"; cat > "$f" ;;
    get)    [ -e "$f" ] || { echo "koto shim: no key $4" >&2; exit 1; }; cat "$f" ;;
    exists) [ -e "$f" ] ;;
    remove) rm -f "$f" ;;
    *) echo "koto shim: unsupported: $*" >&2; exit 2 ;;
esac
SHIM
chmod +x "$SHIM_BIN/koto"
export SHIM_STORE

budget() { PATH="$SHIM_BIN:$PATH" "$SCRIPT" "$@"; }
record() { cat "$SHIM_STORE/$1/panel_retries" 2>/dev/null; }

# expect <name> <session-runner> <round:verdict>...
# Feeds each round to a fresh session and compares the verdict (retry or
# escalate, read from the exit code and cross-checked against stdout).
SEQ=0
expect() {
    local name=$1 runner=$2; shift 2
    SEQ=$((SEQ + 1))
    local session="seq-$SEQ" item round panel count want out rc got ok=1 detail=""
    for item in "$@"; do
        round=${item%=*}
        want=${item#*=}
        panel=${round%:*}
        count=${round#*:}
        out=$("$runner" "$session" "$panel" "$count" 2>/dev/null)
        rc=$?
        case "$rc:$out" in
            0:verdict=retry*)    got=retry ;;
            1:verdict=escalate*) got=escalate ;;
            *)                   got="rc=$rc out=[$out]" ;;
        esac
        detail="$detail $panel:$count->$got"
        [ "$got" = "$want" ] || ok=0
    done
    if [ "$ok" -eq 1 ]; then
        pass "$name:$detail"
    else
        fail "$name:$detail (wanted: $*)"
    fi
}

# --- rule cases ------------------------------------------------------------------

# The reported runs: 7, then 2, then 1. Today's fixed cap of 2 refuses the third.
expect "falling count below the ceiling gets a third retry" budget \
    scrutiny:7=retry scrutiny:2=retry scrutiny:1=retry

expect "flat count past the floor escalates" budget \
    scrutiny:7=retry scrutiny:2=retry scrutiny:2=escalate

expect "rising count past the floor escalates" budget \
    scrutiny:3=retry scrutiny:2=retry scrutiny:4=escalate

expect "the ceiling escalates even a falling count" budget \
    scrutiny:9=retry scrutiny:5=retry scrutiny:3=retry scrutiny:1=escalate

expect "the first two retries are granted whatever the counts" budget \
    scrutiny:1=retry scrutiny:5=retry

expect "a panel with no earlier blocking round escalates past the floor" budget \
    scrutiny:7=retry scrutiny:5=retry review:1=escalate

expect "progress is judged against the same panel, not the last round" budget \
    scrutiny:4=retry review:9=retry scrutiny:3=retry

expect "another panel's lower count is not progress" budget \
    scrutiny:2=retry review:9=retry review:9=escalate

expect "qa_validation compares its own failed scenarios" budget \
    qa_validation:3=retry scrutiny:1=retry qa_validation:2=retry

# light_review, the single seat of the `light` review level, is a panel of its
# own: it spends from the same run-wide retries and is judged on its own counts.
expect "light_review gets a third retry on a falling count" budget \
    light_review:4=retry light_review:3=retry light_review:1=retry light_review:1=escalate
expect "light_review shares the ceiling and is not compared with scrutiny" budget \
    scrutiny:5=retry scrutiny:4=retry light_review:1=escalate

# A refusal records nothing, and the ceiling counts recorded grants only.
expect "a refusal leaves the record as it was" budget \
    scrutiny:7=retry scrutiny:2=retry scrutiny:2=escalate scrutiny:1=retry
if [ "$(record "seq-$SEQ")" = "$(printf 'scrutiny 7\nscrutiny 2\nscrutiny 1')" ]; then
    pass "the record holds the three grants and not the refusal"
else
    fail "record after a refusal: [$(record "seq-$SEQ")]"
fi

# The script's own account of itself: the retry number it prints.
OUT=$(budget acct scrutiny 5 2>/dev/null)
OUT2=$(budget acct scrutiny 4 2>/dev/null)
OUT3=$(budget acct scrutiny 3 2>/dev/null)
if [ "$OUT" = "verdict=retry retry=1 ceiling=3" ] \
    && [ "$OUT2" = "verdict=retry retry=2 ceiling=3" ] \
    && [ "$OUT3" = "verdict=retry retry=3 ceiling=3" ]; then
    pass "the printed retry number counts the grants"
else
    fail "printed [$OUT] [$OUT2] [$OUT3]"
fi
OUT=$(budget acct scrutiny 1 2>/dev/null)
case "$OUT" in
    "verdict=escalate reason=this run has used all 3 blocking retries") pass "the ceiling refusal says why" ;;
    *) fail "ceiling refusal printed [$OUT]" ;;
esac

# --- fail-closed cases -----------------------------------------------------------

OUT=$(SHIM_FAIL_ADD=1 budget fc1 scrutiny 4 2>/dev/null); RC=$?
[ "$RC" -eq 66 ] && [ "${OUT%% *}" = verdict=escalate ] \
    && pass "a record that can't be written refuses (66)" \
    || fail "failed write gave rc=$RC out=[$OUT]"

OUT=$(SHIM_DROP_ADD=1 budget fc2 scrutiny 4 2>/dev/null); RC=$?
[ "$RC" -eq 66 ] && pass "a write that reports success but didn't land refuses (66)" \
    || fail "dropped write gave rc=$RC out=[$OUT]"

mkdir -p "$SHIM_STORE/fc3"
printf 'scrutiny 7\nscrutiny 2\n' > "$SHIM_STORE/fc3/panel_retries"
OUT=$(SHIM_DROP_ADD=1 budget fc3 scrutiny 1 2>/dev/null); RC=$?
[ "$RC" -eq 66 ] && pass "a dropped write on a non-empty record refuses (66)" \
    || fail "dropped write on a non-empty record gave rc=$RC out=[$OUT]"

mkdir -p "$SHIM_STORE/fc4"
printf 'scrutiny 7\nbogus line\n' > "$SHIM_STORE/fc4/panel_retries"
OUT=$(budget fc4 scrutiny 1 2>/dev/null); RC=$?
[ "$RC" -eq 64 ] && pass "a record line the script didn't write refuses (64)" \
    || fail "foreign record line gave rc=$RC out=[$OUT]"

# An unreadable record: the stand-in's exists says yes (a directory is there)
# and get fails (cat of a directory). The reason pins the read branch, so the
# case can't pass through the write failure instead.
mkdir -p "$SHIM_STORE/fc5/panel_retries"
OUT=$(budget fc5 scrutiny 1 2>/dev/null); RC=$?
[ "$RC" -eq 64 ] && [ "$OUT" = "verdict=escalate reason=could not read the retry record (panel_retries) for session fc5" ] \
    && pass "a record that can't be read refuses (64)" \
    || fail "unreadable record gave rc=$RC out=[$OUT]"

mkdir -p "$SHIM_STORE/fc6"
printf 'scrutiny 7 extra\n' > "$SHIM_STORE/fc6/panel_retries"
OUT=$(budget fc6 scrutiny 1 2>/dev/null); RC=$?
[ "$RC" -eq 64 ] && pass "a record line with an extra field refuses (64)" \
    || fail "record line with an extra field gave rc=$RC out=[$OUT]"

for args in "s scrutiny 0" "s scrutiny -1" "s scrutiny x" "s nope 3" "s scrutiny" "'' scrutiny 2" \
    "s scrutiny 1234567" "s scrutiny 99999999999999999999"; do
    eval "set -- $args"
    OUT=$(budget "$@" 2>/dev/null); RC=$?
    [ "$RC" -eq 67 ] && [ "${OUT%% *}" = verdict=escalate ] && pass "usage refused, with a verdict line: [$args]" \
        || fail "usage [$args] exited $RC, printed [$OUT]"
done
[ -z "$(ls "$SHIM_STORE/s" 2>/dev/null)" ] && pass "a usage refusal writes nothing" \
    || fail "a usage refusal wrote to the store"

# Leading zeros are decimal, not octal.
expect "a count with a leading zero is read as decimal" budget \
    scrutiny:09=retry scrutiny:08=retry scrutiny:07=retry

# --- shipped-text cases ----------------------------------------------------------

# Nothing that clears context may clear the record, or a retry would reset the
# count it is about to be judged by. Every clearing site names its keys, so the
# check is that the key's name appears in no shipped /work-on file except the
# three panel directives that call the script, which say where the record
# lives. The panel phase files are checked to still hold a clearing block, so
# the absence can't come from a block that moved.
for f in phase-4a-scrutiny.md phase-4b-review.md phase-4c-qa.md; do
    if grep -q 'koto context remove' "$PHASES/$f"; then
        pass "$f: still holds a clearing block"
    else
        fail "$f: found no clearing block"
    fi
done
# SKILL.md's Scripts list describes the script and names the key; it runs
# nothing, so it is left out with the script itself and the tests. So is
# evals/, as in settled-policy_test.sh: its fixtures are scenario text, and its
# gitignored workspace holds run transcripts that name the key.
HITS=$(grep -rn 'panel_retries' "$SKILL_DIR" --include='*.md' --include='*.sh' \
    | grep -v '_test\.sh:' | grep -v '/scripts/panel-retry-budget\.sh:' | grep -v '/work-on/SKILL\.md:' \
    | grep -v '/work-on/evals/')
OTHER=$(printf '%s\n' "$HITS" | grep . | grep -v 'koto-templates/work-on\.md:[0-9]*:Retry cap: ')
DIRECTIVES=$(printf '%s\n' "$HITS" | grep -c 'koto-templates/work-on\.md:[0-9]*:Retry cap: ')
if [ -z "$OTHER" ] && [ "$DIRECTIVES" -eq 3 ]; then
    pass "panel_retries is named only by the three panel directives"
else
    fail "panel_retries is named outside the panel directives, or not by all three ($DIRECTIVES): $OTHER"
fi

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- the real-session case did not run"
    echo
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
fi

# The same sequences against a real koto session store.
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$PLUGIN_ROOT" "$WORKDIR/plugin"
        PLUGIN_ROOT="$WORKDIR/plugin"
        ;;
esac
RUN="$WORKDIR/run"
mkdir -p "$RUN"
real() {
    if ! (cd "$RUN" && koto context exists "$1" plan.md >/dev/null 2>&1); then
        (cd "$RUN" && koto init "$1" --template "$TEMPLATE" \
            --var ARTIFACT_PREFIX=issue_7 --var ISSUE_NUMBER=7 \
            --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1)
        printf 'plan\n' | (cd "$RUN" && koto context add "$1" plan.md)
    fi
    (cd "$RUN" && "$SCRIPT" "$@")
}
expect "real koto: falling count gets a third retry" real \
    scrutiny:7=retry scrutiny:2=retry scrutiny:1=retry
expect "real koto: the ceiling refuses a still-falling fourth" real \
    scrutiny:9=retry scrutiny:5=retry scrutiny:3=retry scrutiny:1=escalate
expect "real koto: flat count past the floor escalates" real \
    review:4=retry review:3=retry review:3=escalate

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
