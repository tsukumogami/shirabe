#!/usr/bin/env bash
# explore-state_test.sh -- test harness for explore-state.sh, the decisions
# /explore makes from the keys of its session explore-<topic>, and for the
# prose that has to call it.
#
# Usage: bash skills/explore/scripts/explore-state_test.sh
#        /bin/bash skills/explore/scripts/explore-state_test.sh   # bash 3.2 floor
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the engine-backed cases skipped
#   1 -- one or more cases failed
#
# Three groups, in execution order:
#
#   stand-in cases, which need jq and git but no koto: every argument refusal
#   (no koto call is made), koto missing (exit 127) and a koto below the floor
#   (exit 69) at the open /explore's Phase 0 runs, and no staging folder.
#
#   engine-backed cases, which drive the real koto in a store isolated by
#   KOTO_SESSIONS_BASE (and a private HOME) from a throwaway git repository on
#   a branch. State is written with skill-session.sh (open, scratch, put,
#   ingest, close) and explore-state.sh's own subcommands, and every result is
#   read back with `koto context get|list|exists`. They skip with a message
#   when koto is absent; the CI job that runs this asserts koto is present
#   first, so a skip there cannot pass as green.
#
#   static cases, which read SKILL.md and the phase files: the resume section,
#   Phase 2 and the handoff arm call the script by its ${CLAUDE_PLUGIN_ROOT}
#   path, the /decision arm writes its brief before it invokes /decision and
#   closes after, and no research-lead prompt names a koto command.
#
# Everything the suite creates lives under one mktemp -d directory, removed on
# exit; no session outside its own store is touched.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd -P "$(dirname "$0")" && pwd -P)
ES="$SCRIPT_DIR/explore-state.sh"
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

[ -f "$ES" ] || { echo "FAIL: explore-state.sh not found at $ES" >&2; exit 1; }
[ -f "$SS" ] || { echo "FAIL: skill-session.sh not found at $SS" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }

REAL_JQ=$(command -v jq)
REAL_GIT=$(command -v git)
REAL_KOTO=$(command -v koto 2>/dev/null) || REAL_KOTO=""

T=$(mktemp -d "${TMPDIR:-/tmp}/explore-state-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */explore-state-test.*) chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T" ;; esac; return 0; }
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

# es <args...> -- run explore-state.sh from the repository, with real koto.
es() {
    RC=0
    (cd "$REPO" && PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$ES" "$@") >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}

# es_stub <args...> -- run it against the stand-in koto.
es_stub() {
    rm -f "$STUB_LOG"
    RC=0
    (cd "$REPO" && KOTO_BIN="$STUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$ES" "$@") \
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
assert_not_contains() {
    case "$3" in
        *"$2"*) fail "$1: did not expect [$2] in [$3]" ;;
        *) pass "$1" ;;
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
echo "explore-state_test.sh: running under $BASH_BIN ($("$BASH_BIN" -c 'echo $BASH_VERSION'))"
echo

# --- the script itself -------------------------------------------------------------------

CODE=$(grep -v '^[[:space:]]*#' "$ES")
if grep -qE '(^|[^A-Za-z_])eval([^A-Za-z_]|$)' <<<"$CODE"; then
    fail "explore-state.sh contains eval"
else
    pass "explore-state.sh contains no eval"
fi
if grep -qE 'declare -A|mapfile|readarray|local -n|declare -n' <<<"$CODE"; then
    fail "explore-state.sh uses a bash 4 construct"
else
    pass "explore-state.sh uses no bash 4 construct"
fi
if grep -qF 'SCRIPT_DIR/../../../scripts/skill-session.sh' "$ES"; then
    pass "explore-state.sh finds skill-session.sh relative to its own location"
else
    fail "explore-state.sh does not locate skill-session.sh from SCRIPT_DIR/../../../scripts"
fi

# --- argument checks, before any koto call --------------------------------------------------

check_usage() { # check_usage <label> <args...>
    local label="$1"
    shift
    es_stub "$@"
    assert_eq "$label exits 64" "64" "$RC"
    if stub_called; then fail "$label reached koto: $(cat "$STUB_LOG")"; else pass "$label makes no koto call"; fi
}

check_usage "no subcommand"
check_usage "an unknown subcommand" frobnicate t
check_usage "resume-phase with no topic" resume-phase
check_usage "resume-phase with topic -x" resume-phase -x
check_usage "resume-phase with an uppercase topic" resume-phase Topic
check_usage "resume-phase with a topic holding a slash" resume-phase a/b
check_usage "ingest-leads with topic -x" ingest-leads -x 1 "$T/none"
check_usage "ingest-leads with round 0" ingest-leads t 0 "$T/none"
check_usage "ingest-leads with round 01" ingest-leads t 01 "$T/none"
check_usage "ingest-leads with round abc" ingest-leads t abc "$T/none"
check_usage "ingest-leads with round -1" ingest-leads t -1 "$T/none"
check_usage "ingest-leads with no dir" ingest-leads t 1
check_usage "ingest-leads with an empty dir argument" ingest-leads t 1 ""
check_usage "finish-handoff with topic -x" finish-handoff -x
check_usage "finish-handoff with no topic" finish-handoff

# --- koto missing, koto below the floor, at the open Phase 0 runs ---------------------------

if PATH="$TOOLS:$SYS_PATH" command -v koto >/dev/null 2>&1; then
    echo "SKIP: a koto in $SYS_PATH -- the koto-absent cases cannot remove it from PATH"
else
    RC=0
    (cd "$REPO" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" open explore absent) >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "open explore with koto absent from PATH exits 127" "127" "$RC"
    assert_contains "it says failed=koto_missing" "failed=koto_missing" "$(cat "$T/stdout")"
    assert_contains "its message names koto" "koto" "$(cat "$T/stderr")"
    assert_no_staging "open explore with koto absent"

    RC=0
    (cd "$REPO" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$ES" resume-phase absent) >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "resume-phase with koto absent from PATH exits 127" "127" "$RC"
    RC=0
    (cd "$REPO" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$ES" finish-handoff absent) >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "finish-handoff with koto absent from PATH exits 127" "127" "$RC"
fi

rm -f "$STUB_LOG"
RC=0
(cd "$REPO" && KOTO_FLOOR=99.0.0 KOTO_BIN="$STUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" open explore low) \
    >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "open explore with a koto below the floor exits 69" "69" "$RC"
assert_contains "it says failed=koto_below_floor" "failed=koto_below_floor" "$(cat "$T/stdout")"
assert_contains "its message names koto" "koto" "$(cat "$T/stderr")"
assert_no_staging "open explore with a koto below the floor"

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
kexists() { (cd "$REPO" && "$REAL_KOTO" context exists "$1" "$2" >/dev/null 2>&1); }

# open_topic <topic> -- skill-session.sh open explore <topic>.
open_topic() {
    ss open explore "$1"
    [ "$RC" -eq 0 ] || fail "open explore $1 exited $RC: $STDOUT $STDERR"
}

# put_key <topic> <key> <content> -- write a work/ key the way the prose does:
# a file in a scratch directory, then skill-session.sh put.
put_key() {
    local dir
    ss scratch
    dir="$STDOUT"
    printf '%s\n' "$3" >"$dir/content"
    ss put "explore-$1" "$2" "$dir/content"
    [ "$RC" -eq 0 ] || fail "put $2 into explore-$1 exited $RC: $STDOUT $STDERR"
    rm -rf "$dir"
}

# lead_dir <topic> <name>... -- ingest-leads input: a scratch directory holding
# one small file per name; prints its path.
lead_dir() {
    local dir
    ss scratch
    dir="$STDOUT"
    shift
    local n
    for n in "$@"; do printf 'lead body for %s\n' "$n" >"$dir/$n"; done
    printf '%s' "$dir"
}

if [ "$ENGINE" -eq 1 ]; then

# --- open, put the scope, ingest a round's leads, read them back --------------------------------

echo
echo "== open + put + ingest-leads =="
T1=trial
open_topic "$T1"
assert_contains "open explore creates the session" "opened=new" "$STDOUT"
assert_eq "open recorded the branch" "docs/trial" "$(kget explore-$T1 session/branch)"

put_key "$T1" work/scope.md "# Explore Scope: trial"
assert_eq "work/scope.md reads back" "# Explore Scope: trial" "$(kget explore-$T1 work/scope.md)"

D1=$(lead_dir "$T1" r1_lead-alpha.md r1_lead-beta-two.md r1_lead-Bad_Name.md notes.md r2_lead-late.md r1_lead-x.txt r1_lead-.md r1_lead--x.md)
ln -s /etc/hosts "$D1/r1_lead-link.md"
mkdir "$D1/r1_lead-dir.md"
es ingest-leads "$T1" 1 "$D1"
assert_eq "ingest-leads exits 0 with rejects reported" "0" "$RC"
assert_contains "the first good lead is added" "added=research/r1_lead-alpha.md" "$STDOUT"
assert_contains "the second good lead is added" "added=research/r1_lead-beta-two.md" "$STDOUT"
for bad in r1_lead-Bad_Name.md notes.md r2_lead-late.md r1_lead-x.txt r1_lead-.md r1_lead--x.md r1_lead-link.md r1_lead-dir.md; do
    assert_contains "a bad name is reported: $bad" "rejected=$bad" "$STDOUT"
    if kexists "explore-$T1" "research/$bad"; then fail "a key exists for the rejected $bad"; else pass "no key exists for the rejected $bad"; fi
done
assert_eq "only the two good leads became keys" \
    "research/r1_lead-alpha.md,research/r1_lead-beta-two.md,session/branch,work/scope.md" "$(kkeys explore-$T1)"
assert_eq "research/r1_lead-alpha.md reads back" "lead body for r1_lead-alpha.md" "$(kget explore-$T1 research/r1_lead-alpha.md)"
assert_eq "research/r1_lead-beta-two.md reads back" "lead body for r1_lead-beta-two.md" "$(kget explore-$T1 research/r1_lead-beta-two.md)"
if [ -e "$D1" ]; then fail "ingest-leads left the scratch directory"; else pass "ingest-leads removed the scratch directory"; fi
assert_no_staging "after open, put and ingest-leads"

# A second round's leads add to the first's.
D1b=$(lead_dir "$T1" r2_lead-gamma.md r1_lead-stale.md)
es ingest-leads "$T1" 2 "$D1b"
assert_eq "round 2 ingest exits 0" "0" "$RC"
assert_contains "round 2 rejects a round 1 name" "rejected=r1_lead-stale.md" "$STDOUT"
assert_eq "round 2's lead joins round 1's" \
    "research/r1_lead-alpha.md,research/r1_lead-beta-two.md,research/r2_lead-gamma.md,session/branch,work/scope.md" "$(kkeys explore-$T1)"

# A name with a control character is sanitised on stdout and still deleted.
D1c=$(lead_dir "$T1" r3_lead-ok.md)
printf 'x\n' >"$D1c/$(printf 'bad\nrejected=forged')"
es ingest-leads "$T1" 3 "$D1c"
assert_eq "ingest-leads with a newline in a name exits 0" "0" "$RC"
assert_not_contains "a newline in a name cannot forge an output line" "
rejected=forged" "$STDOUT"
assert_contains "the sanitised name is reported" "rejected=bad?rejected?forged" "$STDOUT"
assert_contains "the good lead beside it is added" "added=research/r3_lead-ok.md" "$STDOUT"

# --- ingest-leads refuses a directory that is not a scratch directory ----------------------------

echo
echo "== ingest-leads directory checks =="
OPEN_DIR="$T/open-dir"
mkdir -p "$OPEN_DIR"
chmod 0755 "$OPEN_DIR"
printf 'x\n' >"$OPEN_DIR/keepme.md"
es ingest-leads "$T1" 1 "$OPEN_DIR"
assert_eq "a 0755 directory is refused with 2" "2" "$RC"
assert_contains "it says refused=not_scratch" "refused=not_scratch" "$STDOUT"
if [ -f "$OPEN_DIR/keepme.md" ]; then pass "a refused directory keeps its files"; else fail "a refused directory lost a file"; fi

INSIDE="$REPO/inside"
mkdir -p "$INSIDE"
chmod 0700 "$INSIDE"
printf 'x\n' >"$INSIDE/keepme.md"
es ingest-leads "$T1" 1 "$INSIDE"
assert_eq "a directory inside the work tree is refused with 2" "2" "$RC"
if [ -f "$INSIDE/keepme.md" ]; then pass "a work-tree directory keeps its files"; else fail "a work-tree directory lost a file"; fi
rm -rf "$INSIDE"

LINKED="$T/linked"
ln -s "$OPEN_DIR" "$LINKED"
es ingest-leads "$T1" 1 "$LINKED"
assert_eq "a symlinked directory is refused with 2" "2" "$RC"
es ingest-leads "$T1" 1 "$T/does-not-exist"
assert_eq "a missing directory is refused with 2" "2" "$RC"

# --- resume-phase rows ------------------------------------------------------------------------

echo
echo "== resume-phase =="
es resume-phase never-opened
assert_eq "an absent session prints none" "none" "$STDOUT"
assert_eq "an absent session exits 0" "0" "$RC"

open_topic bare
es resume-phase bare
assert_eq "a session with no working keys prints none" "none" "$STDOUT"

open_topic row2
put_key row2 work/scope.md "scope"
es resume-phase row2
assert_eq "only work/scope.md prints 2" "2" "$STDOUT"

open_topic row3a
put_key row3a work/scope.md "scope"
D=$(lead_dir row3a r1_lead-one.md)
es ingest-leads row3a 1 "$D"
es resume-phase row3a
assert_eq "lead keys and no findings print 3" "3" "$STDOUT"

open_topic row3b
put_key row3b work/scope.md "scope"
put_key row3b work/findings.md "# Exploration Findings: row3b"
es resume-phase row3b
assert_eq "findings without the marker print 3" "3" "$STDOUT"

open_topic row3c
put_key row3c work/scope.md "scope"
put_key row3c work/findings.md "see ## Decision: Crystallize in the notes
and ### Decision: Crystallize too"
es resume-phase row3c
assert_eq "the marker inside a longer line does not count" "3" "$STDOUT"

open_topic row4
put_key row4 work/scope.md "scope"
D=$(lead_dir row4 r1_lead-one.md)
es ingest-leads row4 1 "$D"
put_key row4 work/findings.md "# Exploration Findings: row4

## Decision: Crystallize"
es resume-phase row4
assert_eq "findings holding the marker print 4" "4" "$STDOUT"

open_topic row5
put_key row5 work/scope.md "scope"
put_key row5 work/findings.md "findings

## Decision: Crystallize"
put_key row5 work/crystallize.md "# Crystallize Decision: row5"
es resume-phase row5
assert_eq "work/crystallize.md prints 5" "5" "$STDOUT"

open_topic rowdone
put_key rowdone work/scope.md "scope"
ss close explore-rowdone "done"
es resume-phase rowdone
assert_eq "a finished session prints none, never resumed" "none" "$STDOUT"
assert_eq "its keys stay readable" "scope" "$(kget explore-rowdone work/scope.md)"

# --- finish-handoff ---------------------------------------------------------------------------

echo
echo "== finish-handoff =="
# seed_exploration <topic> -- every working key an exploration reaches Phase 5 with.
seed_exploration() {
    open_topic "$1"
    put_key "$1" work/scope.md "scope"
    put_key "$1" work/findings.md "findings

## Decision: Crystallize"
    put_key "$1" work/decisions.md "decisions"
    put_key "$1" work/crystallize.md "crystallize"
    local d
    d=$(lead_dir "$1" r1_lead-a.md r1_lead-b.md r1_lead-c.md)
    es ingest-leads "$1" 1 "$d" >/dev/null
}
# put_handoff <topic> <name> <content> -- write handoff/<name> through ingest,
# as the handoff arm does.
put_handoff() {
    local dir
    ss scratch
    dir="$STDOUT"
    printf '%s' "$3" >"$dir/$2"
    ss ingest "explore-$1" handoff "$dir"
    [ "$RC" -eq 0 ] || fail "ingest handoff/$2 into explore-$1 exited $RC: $STDOUT $STDERR"
}

seed_exploration fh1
BEFORE=$(kkeys explore-fh1)
es finish-handoff fh1
assert_eq "no handoff key: refused with 2" "2" "$RC"
assert_contains "it says refused=no_handoff" "refused=no_handoff" "$STDOUT"
assert_eq "no handoff key: nothing was removed" "$BEFORE" "$(kkeys explore-fh1)"

put_handoff fh1 scope.md ""
BEFORE=$(kkeys explore-fh1)
assert_contains "an empty handoff/scope.md exists" "handoff/scope.md" "$BEFORE"
es finish-handoff fh1
assert_eq "an empty handoff key: refused with 2" "2" "$RC"
assert_contains "an empty handoff key says refused=no_handoff" "refused=no_handoff" "$STDOUT"
assert_eq "an empty handoff key: nothing was removed" "$BEFORE" "$(kkeys explore-fh1)"
if kexists explore-fh1 work/scope.md && kexists explore-fh1 research/r1_lead-a.md; then
    pass "an empty handoff key: the working keys are still there"
else
    fail "an empty handoff key: a working key was removed"
fi

put_handoff fh1 scope.md "# /scope Handoff: fh1
carried material"
es finish-handoff fh1
assert_eq "with handoff/scope.md: exits 0" "0" "$RC"
assert_contains "it reports the handoff it kept" "handoff=handoff/scope.md" "$STDOUT"
assert_contains "it reports a removed work key" "removed=work/findings.md" "$STDOUT"
assert_contains "it reports a removed research key" "removed=research/r1_lead-c.md" "$STDOUT"
assert_eq "exactly the handoff and session/branch remain" "handoff/scope.md,session/branch" "$(kkeys explore-fh1)"
assert_eq "the handoff body is intact" "# /scope Handoff: fh1
carried material" "$(kget explore-fh1 handoff/scope.md)"
es finish-handoff fh1
assert_eq "a second run is a no-op that exits 0" "0" "$RC"
assert_eq "a second run changes nothing" "handoff/scope.md,session/branch" "$(kkeys explore-fh1)"

# The consumer's close rule: remove the handoff, close the session.
(cd "$REPO" && "$REAL_KOTO" context remove explore-fh1 handoff/scope.md >/dev/null 2>&1)
assert_eq "after the consumer removes the handoff only session/branch is left" "session/branch" "$(kkeys explore-fh1)"
ss close explore-fh1 "done"
assert_eq "the close exits 0" "0" "$RC"
ss status explore-fh1
assert_eq "skill-session.sh status prints finished" "finished" "$STDOUT"

seed_exploration fh2
put_handoff fh2 charter.md "# /charter Handoff: fh2"
es finish-handoff fh2
assert_eq "with handoff/charter.md: exits 0" "0" "$RC"
assert_contains "it reports the charter handoff" "handoff=handoff/charter.md" "$STDOUT"
assert_eq "exactly the charter handoff and session/branch remain" "handoff/charter.md,session/branch" "$(kkeys explore-fh2)"

es finish-handoff fh-absent
assert_eq "an absent session: refused with 2" "2" "$RC"
assert_contains "it says refused=session_not_live" "refused=session_not_live" "$STDOUT"

seed_exploration fh3
put_handoff fh3 scope.md "handoff"
ss close explore-fh3 "done"
es finish-handoff fh3
assert_eq "a finished session: refused with 2" "2" "$RC"
assert_eq "a finished session keeps its working keys" "1" "$(kexists explore-fh3 work/scope.md && echo 1 || echo 0)"

# --- a non-handoff arm: close, then read ------------------------------------------------------------

echo
echo "== a non-handoff close =="
seed_exploration nh
ss close explore-nh "done"
assert_eq "close done exits 0" "0" "$RC"
assert_contains "close reports closed=done" "closed=done" "$STDOUT"
ss status explore-nh
assert_eq "the session is finished" "finished" "$STDOUT"
assert_eq "a work/ key is readable from the finished session" "scope" "$(kget explore-nh work/scope.md)"
assert_eq "a research/ key is readable from the finished session" "lead body for r1_lead-a.md" "$(kget explore-nh research/r1_lead-a.md)"
assert_no_staging "after the whole engine run"

fi

# --- static cases: the prose calls the script -----------------------------------------------------------

echo
echo "== the prose =="
# shellcheck disable=SC2016
CALL='${CLAUDE_PLUGIN_ROOT}/skills/explore/scripts/explore-state.sh'
SKILL_MD="$SKILL_DIR/SKILL.md"
PH="$SKILL_DIR/references/phases"

# section <file> <heading-regex> -- the lines after the heading up to the next
# heading of level 2 or 3.
section() { awk -v re="$2" '$0 ~ re {p=1; next} /^##/ {if (p) exit} p' "$1"; }
# fenced <file> -- the lines inside code fences.
fenced() { awk '/^```/ {f = !f; next} f' "$1"; }

for f in "$SKILL_MD" "$PH"/*.md "$SKILL_DIR/references/quality/crystallize-framework.md"; do
    [ -f "$f" ] || fail "missing $f"
done

RESUME=$(section "$SKILL_MD" '^### Resume Logic')
case "$RESUME" in
    *"\"$CALL\" resume-phase"*) pass "the resume section calls explore-state.sh resume-phase by its plugin-root path" ;;
    *) fail "the resume section of SKILL.md does not call \"$CALL\" resume-phase" ;;
esac

case "$(cat "$PH/phase-2-discover.md")" in
    *"\"$CALL\" ingest-leads"*) pass "Phase 2 calls explore-state.sh ingest-leads by its plugin-root path" ;;
    *) fail "phase-2-discover.md does not call \"$CALL\" ingest-leads" ;;
esac

case "$(cat "$PH/phase-5-produce-handoff.md")" in
    *"\"$CALL\" finish-handoff"*) pass "the handoff arm calls explore-state.sh finish-handoff by its plugin-root path" ;;
    *) fail "phase-5-produce-handoff.md does not call \"$CALL\" finish-handoff" ;;
esac

# Every call to the script names it by the plugin-root path.
BARE=$(grep -rnE 'explore-state\.sh"? +(resume-phase|ingest-leads|finish-handoff)' "$SKILL_MD" "$SKILL_DIR/references" | grep -vF "$CALL" || true)
if [ -n "$BARE" ]; then
    fail "a call names explore-state.sh without its plugin-root path: $BARE"
else
    pass "every call to explore-state.sh names it by its plugin-root path"
fi

# The per-phase resume checks call the same subcommand.
for f in phase-1-scope.md phase-2-discover.md phase-3-converge.md phase-4-crystallize.md phase-5-produce.md; do
    case "$(cat "$PH/$f")" in
        *"\"$CALL\" resume-phase"*) pass "$f resume check calls resume-phase" ;;
        *) fail "$f resume check does not call \"$CALL\" resume-phase" ;;
    esac
done

# Phase 0 opens the session after the branch step and before the first scope write.
L_BRANCH=$(grep -n '^### 0\.1 ' "$PH/phase-0-setup.md" | head -1 | cut -d: -f1)
L_OPEN=$(grep -nF 'skill-session.sh" open explore <topic>' "$PH/phase-0-setup.md" | head -1 | cut -d: -f1)
L_SCOPE=$(grep -n '^### 0\.2a ' "$PH/phase-0-setup.md" | head -1 | cut -d: -f1)
if [ -n "$L_BRANCH" ] && [ -n "$L_OPEN" ] && [ -n "$L_SCOPE" ] && [ "$L_BRANCH" -lt "$L_OPEN" ] && [ "$L_OPEN" -lt "$L_SCOPE" ]; then
    pass "Phase 0 opens explore-<topic> after branch setup and before the first scope write"
else
    fail "Phase 0 does not open the session between 0.1 and 0.2a (lines: branch=$L_BRANCH open=$L_OPEN scope=$L_SCOPE)"
fi

# The /decision arm: brief put, then /decision, then the close.
DEC="$PH/phase-5-produce-decision.md"
L_PUT=$(grep -nF 'skill-session.sh" put explore-<topic> work/decision-brief.md' "$DEC" | head -1 | cut -d: -f1)
# shellcheck disable=SC2016
L_INVOKE=$(grep -n 'Invoke the decision skill' "$DEC" | head -1 | cut -d: -f1)
L_CLOSE=$(grep -nF 'skill-session.sh" close explore-<topic> done' "$DEC" | head -1 | cut -d: -f1)
if [ -n "$L_PUT" ] && [ -n "$L_INVOKE" ] && [ -n "$L_CLOSE" ] && [ "$L_PUT" -lt "$L_INVOKE" ] && [ "$L_INVOKE" -lt "$L_CLOSE" ]; then
    pass "the /decision arm puts work/decision-brief.md, then invokes /decision, then closes"
else
    fail "the /decision arm is out of order (lines: put=$L_PUT invoke=$L_INVOKE close=$L_CLOSE)"
fi
if grep -qE 'git commit|^## Commit|^Commit' "$DEC"; then
    fail "the /decision arm still has a commit step"
else
    pass "the /decision arm has no commit step"
fi
case "$(cat "$DEC")" in
    *'koto context get explore-<topic> research/'*) pass "the brief's research references are koto context get reads" ;;
    *) fail "the brief's research references are not 'koto context get explore-<topic> research/<name>' reads" ;;
esac

# The /comp arm closes after /comp returns.
COMP="$PH/phase-5-produce-comp.md"
# shellcheck disable=SC2016
L_INVOKE=$(grep -n 'Invoke `/comp <topic>`' "$COMP" | head -1 | cut -d: -f1)
L_CLOSE=$(grep -nF 'skill-session.sh" close explore-<topic> done' "$COMP" | head -1 | cut -d: -f1)
if [ -n "$L_INVOKE" ] && [ -n "$L_CLOSE" ] && [ "$L_INVOKE" -lt "$L_CLOSE" ]; then
    pass "the /comp arm closes after /comp returns"
else
    fail "the /comp arm does not close after invoking /comp (lines: invoke=$L_INVOKE close=$L_CLOSE)"
fi

# The other arms end with the plain close; the handoff arm does not close.
for f in phase-5-produce-rejection-record.md phase-5-produce-spike-report.md phase-5-produce-file-an-issue.md \
         phase-5-produce-execute.md phase-5-produce-deferred.md; do
    if grep -qF 'skill-session.sh" close explore-<topic> done' "$PH/$f"; then
        pass "$f ends with skill-session.sh close explore-<topic> done"
    else
        fail "$f has no skill-session.sh close explore-<topic> done"
    fi
done
if grep -qE 'skill-session\.sh"? close explore-' "$PH/phase-5-produce-handoff.md"; then
    fail "the handoff arm closes explore-<topic>; the consumer does"
else
    pass "the handoff arm does not close explore-<topic>"
fi

# No research-lead prompt names a koto command.
GENERIC=$(awk '/Agent prompt template/ {s=1} s && /^```/ {n++; if (n == 2) exit; next} s && n == 1' "$PH/phase-2-discover.md")
ADVERSARIAL=$(awk '/^### Adversarial Lead Agent Prompt Template/ {s=1; next} /^## Quality Checklist/ {s=0} s && /^```/ {f = !f; next} s && f' "$PH/phase-1-scope.md")
if [ -z "$GENERIC" ]; then fail "could not read the generic lead prompt from phase-2-discover.md"; fi
if [ -z "$ADVERSARIAL" ]; then fail "could not read the adversarial lead prompt from phase-1-scope.md"; fi
if grep -qi 'koto' <<<"$GENERIC"; then fail "the generic research-lead prompt names koto"; else pass "the generic research-lead prompt names no koto command"; fi
if grep -qi 'koto' <<<"$ADVERSARIAL"; then fail "the adversarial lead's prompt names koto"; else pass "the adversarial lead's prompt names no koto command"; fi
if fenced "$PH/phase-2-discover.md" | grep -qi 'koto'; then fail "a fenced block in Phase 2 names koto"; else pass "no fenced block in Phase 2 names koto"; fi
case "$GENERIC" in
    *'r<N>_lead-<name>.md'*) pass "the generic prompt pins output to a file r<N>_lead-<name>.md" ;;
    *) fail "the generic prompt does not pin its output file" ;;
esac
case "$ADVERSARIAL" in
    *'{{LEAD_OUTPUT_FILE}}'*) pass "the adversarial prompt pins output to the substituted output file" ;;
    *) fail "the adversarial prompt has no {{LEAD_OUTPUT_FILE}} output pin" ;;
esac

# The handoff's provenance points at no key.
PROV=$(awk '/^## Provenance$/ {p=1; next} /^## / {if (p) exit} p' "$PH/phase-5-produce-handoff.md")
if [ -z "$PROV" ]; then
    fail "could not read the handoff provenance"
elif grep -qE 'work/|research/|koto|wip/' <<<"$PROV"; then
    fail "the handoff provenance points at a key or a staging path"
else
    pass "the handoff provenance points at no key"
fi

# No staging-file names anywhere in the skill's prose.
if grep -rnE 'explore_(<topic>|<t>)_' "$SKILL_MD" "$SKILL_DIR/references" >/dev/null 2>&1; then
    fail "an old staging file name remains in the skill's prose"
else
    pass "no old staging file name remains in the skill's prose"
fi
# shellcheck disable=SC2016
if grep -rnE 'stays? in `?wip/|saved in `?wip/|in `wip/` \(untouched\)' "$SKILL_MD" "$SKILL_DIR/references" >/dev/null 2>&1; then
    fail "a message still says research stays in the staging folder"
else
    pass "no message says research stays in the staging folder"
fi

echo
echo "explore-state_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
