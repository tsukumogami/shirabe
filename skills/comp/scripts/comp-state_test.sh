#!/usr/bin/env bash
# comp-state_test.sh -- test harness for comp-state.sh, the decision /comp
# makes from the keys of its session comp-<topic>, and for the prose that has
# to call it.
#
# Usage: bash skills/comp/scripts/comp-state_test.sh
#        /bin/bash skills/comp/scripts/comp-state_test.sh   # bash 3.2 floor
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the engine-backed cases skipped
#   1 -- one or more cases failed
#
# Three groups, in execution order:
#
#   stand-in cases, which need jq and git but no koto: every argument refusal
#   (no koto call is made), koto missing (exit 127) and a koto below the floor
#   (exit 69) at the open /comp's Phase 0 runs, and no staging folder.
#
#   engine-backed cases, which drive the real koto in a store isolated by
#   KOTO_SESSIONS_BASE (and a private HOME) from a throwaway git repository on
#   a branch. State is written with skill-session.sh (open, scratch, put,
#   ingest, close), the way the prose writes it, and every result is read back
#   with `koto context get|list|exists`. They skip with a message when koto is
#   absent; the CI job that runs this asserts koto is present first, so a skip
#   there cannot pass as green.
#
#   static cases, which read SKILL.md and the phase files: Phase 4 calls the
#   script by its ${CLAUDE_PLUGIN_ROOT} path, Phase 0 opens the session after
#   the visibility decision and the topic check, Phase 5 closes it, no phase
#   file reads a parent state file, and the topic check is the topic grammar.
#
# Everything the suite creates lives under one mktemp -d directory, removed on
# exit; no session outside its own store is touched.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd -P "$(dirname "$0")" && pwd -P)
CS="$SCRIPT_DIR/comp-state.sh"
SKILL_DIR=$(cd -P "$SCRIPT_DIR/.." && pwd -P)
PLUGIN_ROOT=$(cd -P "$SCRIPT_DIR/../../.." && pwd -P)
SS="$PLUGIN_ROOT/scripts/skill-session.sh"
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { printf "${GREEN}PASS${NC}: %s\n" "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf "${RED}FAIL${NC}: %s\n" "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$CS" ] || { echo "FAIL: comp-state.sh not found at $CS" >&2; exit 1; }
[ -f "$SS" ] || { echo "FAIL: skill-session.sh not found at $SS" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }

REAL_JQ=$(command -v jq)
REAL_GIT=$(command -v git)
REAL_KOTO=$(command -v koto 2>/dev/null) || REAL_KOTO=""

T=$(mktemp -d "${TMPDIR:-/tmp}/comp-state-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */comp-state-test.*) chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T" ;; esac; return 0; }
ktg_on_exit cleanup

# A private HOME (koto's template cache lands there) and a private session
# store: nothing here reaches the developer's own sessions.
export HOME="$T/home"
export KOTO_SESSIONS_BASE="$T/sessions"
mkdir -p "$HOME" "$KOTO_SESSIONS_BASE"
unset KOTO_BIN KOTO_FLOOR
# The scratch directories skill-session.sh allocates go under the suite's own
# directory, outside the repository.
export TMPDIR="$T/tmp"
mkdir -p "$TMPDIR"
export GIT_CEILING_DIRECTORIES="$T"

# Tool directories: one without koto, one with it.
TOOLS="$T/tools"
TOOLS_KOTO="$T/tools-koto"
mkdir -p "$TOOLS" "$TOOLS_KOTO"
ln -s "$REAL_JQ" "$TOOLS/jq"
ln -s "$REAL_GIT" "$TOOLS/git"
ln -s "$REAL_JQ" "$TOOLS_KOTO/jq"
ln -s "$REAL_GIT" "$TOOLS_KOTO/git"
[ -n "$REAL_KOTO" ] && ln -s "$REAL_KOTO" "$TOOLS_KOTO/koto"
SYS_PATH="/usr/bin:/bin"

REPO="$T/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" checkout -q -b docs/trial
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init

# --- the stand-in koto ---------------------------------------------------------------
#
# Records each call as one line in $STUB_LOG. `koto version` answers 0.15.0;
# everything else fails, so a case that reaches koto past `version` shows up.
STUB_DIR="$T/stubbin"
mkdir -p "$STUB_DIR"
STUB_LOG="$T/stub-calls"
cat >"$STUB_DIR/koto" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "${1:-}" in
    version) printf 'koto 0.15.0 (stub)\n'; exit 0 ;;
esac
printf '{"error":"stub"}\n'
exit 1
STUB
chmod +x "$STUB_DIR/koto"
export STUB_LOG

RC=0
STDOUT=""
STDERR=""

# cs <args...> -- run comp-state.sh from the repository, with real koto.
cs() {
    RC=0
    (cd "$REPO" && PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$CS" "$@") >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}

# cs_stub <args...> -- run it against the stand-in koto.
cs_stub() {
    rm -f "$STUB_LOG"
    RC=0
    (cd "$REPO" && KOTO_BIN="$STUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$CS" "$@") \
        >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}
stub_called() { [ -s "$STUB_LOG" ]; }

# ss <args...> -- run skill-session.sh from the repository, with real koto.
ss() {
    RC=0
    (cd "$REPO" && PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$SS" "$@") >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}

assert_eq() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected [$2], got [$3]"; fi
}
assert_contains() {
    case "$3" in
        *"$2"*) pass "$1" ;;
        *) fail "$1: expected to contain [$2], got [$3]" ;;
    esac
}
assert_no_staging() {
    local porcelain
    porcelain=$(git -C "$REPO" status --porcelain)
    if [ -e "$REPO/wip" ] || [ -n "$porcelain" ]; then
        fail "$1: the test repository has an entry [$porcelain]"
    else
        pass "$1: no wip/ entry and a clean tree in the test repository"
    fi
}

# shellcheck disable=SC2016
echo "comp-state_test.sh: running under $BASH_BIN ($("$BASH_BIN" -c 'echo $BASH_VERSION'))"
echo

# --- the script itself -------------------------------------------------------------------

CODE=$(grep -v '^[[:space:]]*#' "$CS")
if grep -qE '(^|[^A-Za-z_])eval([^A-Za-z_]|$)' <<<"$CODE"; then
    fail "comp-state.sh contains eval"
else
    pass "comp-state.sh contains no eval"
fi
if grep -qE 'declare -A|mapfile|readarray|local -n|declare -n' <<<"$CODE"; then
    fail "comp-state.sh uses a bash 4 construct"
else
    pass "comp-state.sh uses no bash 4 construct"
fi
if grep -qF 'SCRIPT_DIR/../../../scripts/skill-session.sh' "$CS"; then
    pass "comp-state.sh finds skill-session.sh relative to its own location"
else
    fail "comp-state.sh does not locate skill-session.sh from SCRIPT_DIR/../../../scripts"
fi

# --- argument checks, before any koto call --------------------------------------------------

check_usage() { # check_usage <label> <args...>
    local label="$1"
    shift
    cs_stub "$@"
    assert_eq "$label exits 64" "64" "$RC"
    if stub_called; then fail "$label reached koto: $(cat "$STUB_LOG")"; else pass "$label makes no koto call"; fi
}

check_usage "no subcommand"
check_usage "an unknown subcommand" frobnicate t
check_usage "jury-resume with no topic" jury-resume
check_usage "jury-resume with topic -x" jury-resume -x
check_usage "jury-resume with an uppercase topic" jury-resume Topic
check_usage "jury-resume with a topic holding a slash" jury-resume a/b
check_usage "jury-resume with a topic holding a dot" jury-resume a.b
check_usage "jury-resume with a topic holding an underscore" jury-resume a_b
check_usage "jury-resume with an empty topic" jury-resume ""
check_usage "jury-resume with two arguments" jury-resume a b

# The open /comp's Phase 0 runs refuses the same topic before any koto call.
rm -f "$STUB_LOG"
RC=0
(cd "$REPO" && KOTO_BIN="$STUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" open comp -x) >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "open comp with topic -x exits 64" "64" "$RC"
if stub_called; then fail "open comp -x reached koto: $(cat "$STUB_LOG")"; else pass "open comp -x makes no koto call"; fi

# --- koto missing, koto below the floor, at the open Phase 0 runs ---------------------------

if PATH="$TOOLS:$SYS_PATH" command -v koto >/dev/null 2>&1; then
    echo "SKIP: a koto in $SYS_PATH -- the koto-absent cases cannot remove it from PATH"
else
    RC=0
    (cd "$REPO" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" open comp absent) >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "open comp with koto absent from PATH exits 127" "127" "$RC"
    assert_contains "it says failed=koto_missing" "failed=koto_missing" "$(cat "$T/stdout")"
    assert_contains "its message names koto" "koto" "$(cat "$T/stderr")"
    assert_no_staging "open comp with koto absent"

    RC=0
    (cd "$REPO" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$CS" jury-resume absent) >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "jury-resume with koto absent from PATH exits 127" "127" "$RC"
fi

rm -f "$STUB_LOG"
RC=0
(cd "$REPO" && KOTO_FLOOR=99.0.0 KOTO_BIN="$STUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" open comp low) \
    >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "open comp with a koto below the floor exits 69" "69" "$RC"
assert_contains "it says failed=koto_below_floor" "failed=koto_below_floor" "$(cat "$T/stdout")"
assert_contains "its message names koto" "koto" "$(cat "$T/stderr")"
assert_no_staging "open comp with a koto below the floor"

# --- engine-backed --------------------------------------------------------------------------

if [ -z "$REAL_KOTO" ]; then
    echo
    echo "SKIP: koto not on PATH -- the engine-backed cases did not run"
    ENGINE=0
else
    ENGINE=1
fi

# kget <session> <key> -- the key's content, or "<absent>".
kget() {
    local v
    if v=$(cd "$REPO" && "$REAL_KOTO" context get "$1" "$2" 2>/dev/null); then printf '%s' "$v"; else printf '<absent>'; fi
}
# kkeys <session> -- the session's keys, sorted, comma-joined.
kkeys() {
    (cd "$REPO" && "$REAL_KOTO" context list "$1" 2>/dev/null) | jq -r 'sort | join(",")'
}

# open_topic <topic> -- skill-session.sh open comp <topic>.
open_topic() {
    ss open comp "$1"
    [ "$RC" -eq 0 ] || fail "open comp $1 exited $RC: $STDOUT $STDERR"
}

# put_scope <topic> <content> -- write work/scope.md the way Phase 1 does:
# a file in a scratch directory, then skill-session.sh put.
put_scope() {
    local dir
    ss scratch
    dir="$STDOUT"
    printf '%s\n' "$2" >"$dir/scope.md"
    ss put "comp-$1" work/scope.md "$dir/scope.md"
    [ "$RC" -eq 0 ] || fail "put work/scope.md into comp-$1 exited $RC: $STDOUT $STDERR"
    rm -rf "$dir"
}

# ingest_verdicts <topic> <role>... -- write one verdict file per role into a
# scratch directory and ingest it as research/phase4_<role>.md, the way
# Phase 4 does.
ingest_verdicts() {
    local topic="$1" dir role
    shift
    ss scratch
    dir="$STDOUT"
    for role in "$@"; do
        printf 'verdict for %s\n\n**Verdict:** PASS\n' "$role" >"$dir/phase4_${role}.md"
    done
    ss ingest "comp-$topic" research "$dir"
    [ "$RC" -eq 0 ] || fail "ingest into comp-$topic exited $RC: $STDOUT $STDERR"
}

V_ALL="competitive-framing content-quality structural-format"
K_CF="research/phase4_competitive-framing.md"
K_CQ="research/phase4_content-quality.md"
K_SF="research/phase4_structural-format.md"

if [ "$ENGINE" -eq 1 ]; then

echo
echo "== open + put + ingest =="
open_topic trial
assert_contains "open comp creates the session" "opened=new" "$STDOUT"
assert_eq "open recorded the branch" "docs/trial" "$(kget comp-trial session/branch)"

put_scope trial "# Scope: trial"
assert_eq "work/scope.md reads back" "# Scope: trial" "$(kget comp-trial work/scope.md)"

# shellcheck disable=SC2086
ingest_verdicts trial $V_ALL
assert_contains "the first verdict is added" "added=$K_CF" "$STDOUT"
assert_eq "the keys are the scope, the three verdicts and the branch" \
    "$K_CF,$K_CQ,$K_SF,session/branch,work/scope.md" "$(kkeys comp-trial)"
assert_eq "a verdict reads back" "verdict for content-quality

**Verdict:** PASS" "$(kget comp-trial $K_CQ)"
assert_no_staging "after open, put and ingest"

echo
echo "== jury-resume =="
BEFORE=$(kkeys comp-trial)
cs jury-resume trial
assert_eq "all three verdict keys: exits 0" "0" "$RC"
assert_eq "all three verdict keys print aggregate" "aggregate" "$STDOUT"
assert_eq "aggregate changes nothing" "$BEFORE" "$(kkeys comp-trial)"

# Two of three present: removed, fresh.
open_topic two
put_scope two "scope"
ingest_verdicts two competitive-framing content-quality
assert_eq "two verdicts are present" "$K_CF,$K_CQ,session/branch,work/scope.md" "$(kkeys comp-two)"
cs jury-resume two
assert_eq "two verdict keys: exits 0" "0" "$RC"
assert_eq "two verdict keys print fresh" "fresh" "$STDOUT"
assert_eq "the two verdicts are removed, the scope kept" "session/branch,work/scope.md" "$(kkeys comp-two)"
cs jury-resume two
assert_eq "no verdict keys print fresh" "fresh" "$STDOUT"

# One of three.
open_topic one
ingest_verdicts one structural-format
cs jury-resume one
assert_eq "one verdict key prints fresh" "fresh" "$STDOUT"
assert_eq "the one verdict is removed" "session/branch" "$(kkeys comp-one)"

# A re-run after a fresh answer ends with all three new verdicts and aggregates.
# shellcheck disable=SC2086
ingest_verdicts two $V_ALL
cs jury-resume two
assert_eq "after re-spawning all three, the jury aggregates" "aggregate" "$STDOUT"

# A re-ingested role replaces its earlier verdict.
ingest_verdicts two content-quality
assert_eq "re-ingesting a role keeps three verdict keys" \
    "$K_CF,$K_CQ,$K_SF,session/branch,work/scope.md" "$(kkeys comp-two)"

# An absent session and a finished one are refused.
cs jury-resume never-opened
assert_eq "an absent session is refused with 2" "2" "$RC"
assert_contains "it says refused=session_not_live" "refused=session_not_live" "$STDOUT"

# --- the finalize close ---------------------------------------------------------------------

echo
echo "== the finalize close =="
ss status comp-trial
assert_eq "the session is live before the close" "live" "$STDOUT"
ss close comp-trial "done"
assert_eq "close done exits 0" "0" "$RC"
assert_contains "close reports closed=done" "closed=done" "$STDOUT"
ss status comp-trial
assert_eq "skill-session.sh status prints finished" "finished" "$STDOUT"
assert_eq "work/scope.md is readable from the finished session" "# Scope: trial" "$(kget comp-trial work/scope.md)"
cs jury-resume trial
assert_eq "a finished session is refused with 2" "2" "$RC"

# A fresh run on the same topic replaces the finished session.
open_topic trial
assert_contains "the next open replaces the finished session" "opened=replaced" "$STDOUT"
assert_eq "the replaced session starts without the old keys" "session/branch" "$(kkeys comp-trial)"
assert_no_staging "after the whole engine run"

fi

# --- static cases: the prose calls the script -----------------------------------------------------------

echo
echo "== the prose =="
# shellcheck disable=SC2016
CALL='${CLAUDE_PLUGIN_ROOT}/skills/comp/scripts/comp-state.sh'
SKILL_MD="$SKILL_DIR/SKILL.md"
PH="$SKILL_DIR/references/phases"

for f in "$SKILL_MD" "$PH"/phase-*.md; do
    [ -f "$f" ] || fail "missing $f"
done

case "$(cat "$PH/phase-4-validate.md")" in
    *"\"$CALL\" jury-resume"*) pass "Phase 4 calls comp-state.sh jury-resume by its plugin-root path" ;;
    *) fail "phase-4-validate.md does not call \"$CALL\" jury-resume" ;;
esac

# Every call to the script names it by the plugin-root path.
BARE=$(grep -rnE 'comp-state\.sh"? +jury-resume' "$SKILL_MD" "$SKILL_DIR/references" | grep -vF "$CALL" || true)
if [ -n "$BARE" ]; then
    fail "a call names comp-state.sh without its plugin-root path: $BARE"
else
    pass "every call to comp-state.sh names it by its plugin-root path"
fi

# No phase file or SKILL.md reads a parent state file.
PARENT=$(grep -nE '_state\.md|<parent>_|[Ss]entinel|parent-orchestration|parent state' "$SKILL_MD" "$PH"/phase-*.md || true)
if [ -n "$PARENT" ]; then
    fail "the prose still reads or mentions a parent state file: $PARENT"
else
    pass "no phase file and no SKILL.md reads a parent state file"
fi

# The topic check is the topic grammar, in SKILL.md and Phase 0, and the old
# check is gone.
for f in "$SKILL_MD" "$PH/phase-0-setup.md"; do
    if grep -qF '^[a-z0-9][a-z0-9-]*$' "$f"; then
        pass "$(basename "$f") states the topic grammar"
    else
        fail "$(basename "$f") does not state ^[a-z0-9][a-z0-9-]*\$"
    fi
    if grep -qF '^[a-z0-9-]+$' "$f"; then
        fail "$(basename "$f") still states the old topic check"
    else
        pass "$(basename "$f") no longer states the old topic check"
    fi
done

# Phase 0 opens the session after the visibility decision and the topic check.
L_VIS=$(grep -n '^## 0\.2 ' "$PH/phase-0-setup.md" | head -1 | cut -d: -f1)
L_TOPIC=$(grep -n '^## 0\.3 ' "$PH/phase-0-setup.md" | head -1 | cut -d: -f1)
L_OPEN=$(grep -nF 'skill-session.sh" open comp <topic>' "$PH/phase-0-setup.md" | head -1 | cut -d: -f1)
if [ -n "$L_VIS" ] && [ -n "$L_TOPIC" ] && [ -n "$L_OPEN" ] && [ "$L_VIS" -lt "$L_OPEN" ] && [ "$L_TOPIC" -lt "$L_OPEN" ]; then
    pass "Phase 0 opens comp-<topic> after the visibility decision and the topic check"
else
    fail "Phase 0 does not open the session after 0.2 and 0.3 (lines: visibility=$L_VIS topic=$L_TOPIC open=$L_OPEN)"
fi

# Phase 1 writes the scope as a key, Phase 4 ingests the verdicts, Phase 5 closes.
if grep -qF 'skill-session.sh" put comp-<topic> work/scope.md' "$PH/phase-1-scope.md"; then
    pass "Phase 1 puts work/scope.md"
else
    fail "Phase 1 does not put work/scope.md"
fi
if grep -qF 'skill-session.sh" ingest comp-<topic> research' "$PH/phase-4-validate.md"; then
    pass "Phase 4 ingests the verdicts as research/ keys"
else
    fail "Phase 4 does not ingest the verdicts into comp-<topic>"
fi
if grep -qF 'skill-session.sh" close comp-<topic> done' "$PH/phase-5-finalize.md"; then
    pass "Phase 5 closes comp-<topic> done"
else
    fail "Phase 5 has no skill-session.sh close comp-<topic> done"
fi

# No staging-file names anywhere in the skill's prose, and the staging grep that
# keeps a path out of the COMP document stays.
# The folder's name is built from two pieces so this file doesn't spell a
# staging path either.
WP="wi""p/"
if grep -rnE "comp_(<topic>|<t>)_|${WP}comp|${WP}research" "$SKILL_MD" "$SKILL_DIR/references" >/dev/null 2>&1; then
    fail "an old staging file name remains in the skill's prose"
else
    pass "no old staging file name remains in the skill's prose"
fi
if grep -qE 'grep the committed COMP document' "$PH/phase-5-finalize.md"; then
    pass "Phase 5 keeps the grep that keeps a staging path out of the COMP document"
else
    fail "Phase 5 lost the grep over the COMP document for staging paths"
fi
if grep -qF '[/comp] FINALIZED' "$PH/phase-5-finalize.md" && grep -qF '[/comp] WARNING' "$PH/phase-0-setup.md"; then
    pass "the stdout FINALIZED and WARNING lines stay"
else
    fail "a stdout FINALIZED or WARNING line is gone"
fi

echo
echo "comp-state_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
