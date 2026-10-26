#!/usr/bin/env bash
# release-state_test.sh -- test harness for release-state.sh, the session logic
# /release runs on the keys of release-<topic>, and for the prose that has to
# call it.
#
# Usage: bash skills/release/scripts/release-state_test.sh
#        /bin/bash skills/release/scripts/release-state_test.sh   # bash 3.2 floor
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the engine-backed cases skipped
#   1 -- one or more cases failed
#
# Four groups, in execution order:
#
#   stand-in cases, which need jq and git but no koto: `topic` against a
#   stubbed `gh repo view`, every argument refusal (no koto call is made), koto
#   missing (exit 127) and a koto below the floor (exit 69) at the open
#   /release's Phase 1 runs, and no staging folder.
#
#   engine-backed cases, which drive the real koto in a store isolated by
#   KOTO_SESSIONS_BASE (and a private HOME) from a throwaway git repository
#   with tagged history. State is written by `membership` and skill-session.sh
#   (open, scratch, put, close) and every result is read back with `koto
#   context get|list|exists`. They skip with a message when koto is absent; the
#   CI job that runs this asserts koto is present first, so a skip there cannot
#   pass as green.
#
#   extracted-block cases, which cut the Phase 4 bash blocks out of
#   skills/release/SKILL.md at run time and run them against a stubbed `gh
#   release create`, so a change to the shipped block changes what runs here.
#
#   static cases, which read SKILL.md: Phase 1 calls `membership`, Phases 2 and
#   3 call `read`, every call names the script by its ${CLAUDE_PLUGIN_ROOT}
#   path, the close calls are present, and no staging file name remains.
#
# Everything the suite creates lives under one mktemp -d directory, removed on
# exit; no session outside its own store is touched.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd -P "$(dirname "$0")" && pwd -P)
RS="$SCRIPT_DIR/release-state.sh"
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

[ -f "$RS" ] || { echo "FAIL: release-state.sh not found at $RS" >&2; exit 1; }
[ -f "$SS" ] || { echo "FAIL: skill-session.sh not found at $SS" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }

REAL_JQ=$(command -v jq)
REAL_GIT=$(command -v git)
REAL_KOTO=$(command -v koto 2>/dev/null) || REAL_KOTO=""

T=$(mktemp -d "${TMPDIR:-/tmp}/release-state-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */release-state-test.*) chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T" ;; esac; return 0; }
trap cleanup EXIT

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

# --- the stubbed gh ------------------------------------------------------------------
#
# `gh repo view --json owner,name` prints $GH_REPO_JSON and exits $GH_REPO_RC.
# `gh release create ...` records its arguments, copies the file it was given
# with --notes-file to $GH_NOTES_COPY while it still exists, records that
# file's path in $GH_NOTES_PATH, and exits $GH_CREATE_RC. Every call is logged.
STUB_DIR="$T/stubbin"
mkdir -p "$STUB_DIR"
GH_LOG="$T/gh-calls"
cat >"$STUB_DIR/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$1 $2" in
    "repo view")
        [ -n "${GH_REPO_JSON+x}" ] && printf '%s\n' "$GH_REPO_JSON"
        exit "${GH_REPO_RC:-0}"
        ;;
    "release create")
        prev=""
        for a in "$@"; do
            if [ "$prev" = "--notes-file" ]; then
                printf '%s' "$a" >"$GH_NOTES_PATH"
                if [ -f "$a" ]; then cp "$a" "$GH_NOTES_COPY"; fi
            fi
            prev="$a"
        done
        exit "${GH_CREATE_RC:-0}"
        ;;
esac
exit 1
STUB
chmod +x "$STUB_DIR/gh"
export GH_LOG
export GH_NOTES_PATH="$T/gh-notes-path"
export GH_NOTES_COPY="$T/gh-notes-copy"
export GH_REPO_JSON='{"name":"shirabe","owner":{"id":"O_1","login":"tsukumogami"}}'

# Tool directories: one without koto, one with it. Both carry the stub gh.
TOOLS="$T/tools"
TOOLS_KOTO="$T/tools-koto"
mkdir -p "$TOOLS" "$TOOLS_KOTO"
for d in "$TOOLS" "$TOOLS_KOTO"; do
    ln -s "$REAL_JQ" "$d/jq"
    ln -s "$REAL_GIT" "$d/git"
    ln -s "$STUB_DIR/gh" "$d/gh"
done
[ -n "$REAL_KOTO" ] && ln -s "$REAL_KOTO" "$TOOLS_KOTO/koto"
SYS_PATH="/usr/bin:/bin"

# --- the test repository with tagged history -----------------------------------------------

REPO="$T/repo"
mkdir -p "$REPO"
g() { git -C "$REPO" -c user.name=t -c user.email=t@example.invalid "$@"; }
g init -q
g checkout -q -b docs/trial
g commit -q --allow-empty -m "chore: init"
g tag v0.1.0
g commit -q --allow-empty -m "feat: add alpha (#12)"
g commit -q --allow-empty -m "fix: repair beta (#7)"
g commit -q --allow-empty -m "feat: second change for alpha (#12)"
g commit -q --allow-empty -m "chore: bump version"
g commit -q --allow-empty -m "docs: mention a number (see #99)"

# The stand-in koto (for the floor and for argument refusals): `koto version`
# answers 0.15.0 and everything else fails, so a case that reaches koto past
# `version` shows up in $STUB_LOG.
KSTUB_DIR="$T/kstub"
mkdir -p "$KSTUB_DIR"
STUB_LOG="$T/kstub-calls"
cat >"$KSTUB_DIR/koto" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "${1:-}" in
    version) printf 'koto 0.15.0 (stub)\n'; exit 0 ;;
esac
printf '{"error":"stub"}\n'
exit 1
STUB
chmod +x "$KSTUB_DIR/koto"
export STUB_LOG

RC=0
STDOUT=""
STDERR=""

# rs <args...> -- run release-state.sh from the repository, with real koto.
rs() {
    RC=0
    (cd "$REPO" && PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$RS" "$@") >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}

# rs_stub <args...> -- run it against the stand-in koto.
rs_stub() {
    rm -f "$STUB_LOG"
    RC=0
    (cd "$REPO" && KOTO_BIN="$KSTUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$RS" "$@") \
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
echo "release-state_test.sh: running under $BASH_BIN ($("$BASH_BIN" -c 'echo $BASH_VERSION'))"
echo

# --- the script itself -------------------------------------------------------------------

CODE=$(grep -v '^[[:space:]]*#' "$RS")
if grep -qE '(^|[^A-Za-z_])eval([^A-Za-z_]|$)' <<<"$CODE"; then
    fail "release-state.sh contains eval"
else
    pass "release-state.sh contains no eval"
fi
if grep -qE 'declare -A|mapfile|readarray|local -n|declare -n' <<<"$CODE"; then
    fail "release-state.sh uses a bash 4 construct"
else
    pass "release-state.sh uses no bash 4 construct"
fi
if grep -qF 'SCRIPT_DIR/../../../scripts/skill-session.sh' "$RS"; then
    pass "release-state.sh finds skill-session.sh relative to its own location"
else
    fail "release-state.sh does not locate skill-session.sh from SCRIPT_DIR/../../../scripts"
fi

# --- topic ---------------------------------------------------------------------------------

echo
echo "== topic =="
: >"$GH_LOG"
rs_stub topic
assert_eq "topic exits 0" "0" "$RC"
assert_eq "topic prints tsukumogami-shirabe from the stubbed gh repo view" "tsukumogami-shirabe" "$STDOUT"
assert_contains "it asked gh for the owner and name" "repo view --json owner,name" "$(cat "$GH_LOG")"
if stub_called; then fail "topic reached koto: $(cat "$STUB_LOG")"; else pass "topic makes no koto call"; fi

topic_for() { # topic_for <json> -- the topic printed for a stubbed gh answer
    GH_REPO_JSON="$1" rs_stub topic
}
topic_for '{"name":"My_Repo.Name","owner":{"login":"Some-Org"}}'
assert_eq "topic lowercases and turns runs of other characters into one hyphen" "some-org-my-repo-name" "$STDOUT"
topic_for '{"name":"--x--","owner":{"login":"__o__"}}'
assert_eq "topic trims leading and trailing hyphens" "o-x" "$STDOUT"
topic_for '{"name":"a","owner":"plainowner"}'
assert_eq "topic accepts an owner given as a string" "plainowner-a" "$STDOUT"

topic_for '{"name":"","owner":{"login":""}}'
assert_eq "an empty owner and name is refused with 2" "2" "$RC"
assert_contains "it says refused=empty_topic" "refused=empty_topic" "$STDOUT"
topic_for '{"name":"shirabe","owner":{"login":""}}'
assert_eq "an empty owner is refused with 2" "2" "$RC"
topic_for '{"name":"---","owner":{"login":"@@@"}}'
assert_eq "a result with no [a-z0-9] is refused with 2" "2" "$RC"
assert_eq "a refused topic prints no topic" "refused=empty_topic" "$STDOUT"
topic_for ''
assert_eq "an empty answer from gh is refused with 2" "2" "$RC"
GH_REPO_RC=1 topic_for '{"name":"shirabe","owner":{"login":"tsukumogami"}}'
assert_eq "a failing gh repo view exits 1" "1" "$RC"
topic_for 'not json'
assert_eq "an answer that is not JSON exits 1" "1" "$RC"

# --- argument checks, before any koto call --------------------------------------------------

check_usage() { # check_usage <label> <args...>
    local label="$1"
    shift
    rs_stub "$@"
    assert_eq "$label exits 64" "64" "$RC"
    if stub_called; then fail "$label reached koto: $(cat "$STUB_LOG")"; else pass "$label makes no koto call"; fi
}

echo
echo "== argument checks =="
check_usage "no subcommand"
check_usage "an unknown subcommand" frobnicate t
check_usage "topic with an argument" topic extra
check_usage "membership with no topic" membership
check_usage "membership with topic -x" membership -x
check_usage "membership with an uppercase topic" membership Topic
check_usage "membership with a topic holding a slash" membership a/b
check_usage "membership with two arguments" membership a b
check_usage "read with no arguments" read
check_usage "read with one argument" read topic
check_usage "read with topic -x" read -x prs
check_usage "read of an unknown key" read topic frobnicate
check_usage "read of a key path" read topic work/prs

# --- koto missing, koto below the floor, at the open Phase 1 runs ------------------------------

echo
echo "== koto missing or too old =="
if PATH="$TOOLS:$SYS_PATH" command -v koto >/dev/null 2>&1; then
    echo "SKIP: a koto in $SYS_PATH -- the koto-absent cases cannot remove it from PATH"
else
    RC=0
    (cd "$REPO" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" open release tsukumogami-shirabe) >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "open release with koto absent from PATH exits 127" "127" "$RC"
    assert_contains "it says failed=koto_missing" "failed=koto_missing" "$(cat "$T/stdout")"
    assert_contains "its message names koto" "koto" "$(cat "$T/stderr")"
    assert_no_staging "open release with koto absent"

    RC=0
    (cd "$REPO" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$RS" membership absent) >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "membership with koto absent from PATH exits 127" "127" "$RC"
    RC=0
    (cd "$REPO" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$RS" read absent prs) >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "read with koto absent from PATH exits 127" "127" "$RC"
fi

rm -f "$STUB_LOG"
RC=0
(cd "$REPO" && KOTO_FLOOR=99.0.0 KOTO_BIN="$KSTUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" open release low) \
    >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "open release with a koto below the floor exits 69" "69" "$RC"
assert_contains "it says failed=koto_below_floor" "failed=koto_below_floor" "$(cat "$T/stdout")"
assert_contains "its message names koto" "koto" "$(cat "$T/stderr")"
assert_no_staging "open release with a koto below the floor"

# --- version ---------------------------------------------------------------------------------

echo
echo "== version =="
for v in 0.3.0 v0.3.0 10.20.30 1.0.0-rc.1 0.3.0-alpha.2.b; do
    rs_stub version "$v"
    assert_eq "version $v exits 0" "0" "$RC"
    assert_eq "version $v prints the bare version" "${v#v}" "$STDOUT"
done
for v in '1.2.3;id' '1.2' '' 'vv1.2.3' '1.2.3 ' ' 1.2.3' '1.2.3-' '1.2.3-rc_1' '1.2.3$(id)' "1.2.3
id" 'V1.2.3' '1.2.3.4'; do
    rs_stub version "$v"
    assert_eq "version $(printf '%q' "$v") is refused with 2" "2" "$RC"
    assert_eq "version $(printf '%q' "$v") prints refused=bad_version" "refused=bad_version" "$STDOUT"
    assert_contains "version $(printf '%q' "$v"): the message names the version" "$(printf '%q' "$v")" "$STDERR"
done
if stub_called; then fail "version reached koto: $(cat "$STUB_LOG")"; else pass "version makes no koto call"; fi
check_usage "version with no value" version
check_usage "version with two values" version 1.2.3 1.2.4
check_usage "go with no version source" go some-topic
check_usage "go with an unknown bump" go some-topic --bump huge
check_usage "go with --bump and no value" go some-topic --bump
check_usage "go with an unknown flag" go some-topic --given --yes
check_usage "go with a bad topic" go Bad_Topic --given

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
# kbytes <session> <key> -- the number of bytes stored under the key.
kbytes() { (cd "$REPO" && "$REAL_KOTO" context get "$1" "$2" 2>/dev/null) | wc -c | tr -d ' '; }
kexists() { (cd "$REPO" && "$REAL_KOTO" context exists "$1" "$2" >/dev/null 2>&1); }

# open_release <topic> -- skill-session.sh open release <topic>.
open_release() {
    ss open release "$1"
    [ "$RC" -eq 0 ] || fail "open release $1 exited $RC: $STDOUT $STDERR"
}

if [ "$ENGINE" -eq 1 ]; then

echo
echo "== membership =="
TP=tsukumogami-shirabe
open_release "$TP"
assert_contains "open release creates the session" "opened=new" "$STDOUT"
S="release-$TP"

LAST_UNATTR=$(git -C "$REPO" log -1 --format='%h %s' --grep='mention a number')
BUMP_UNATTR=$(git -C "$REPO" log -1 --format='%h %s' --grep='bump version')

rs membership "$TP"
assert_eq "membership exits 0" "0" "$RC"
assert_contains "it reports the range" "range=v0.1.0..HEAD" "$STDOUT"
assert_contains "it counts the pull requests" "prs=2" "$STDOUT"
assert_contains "it counts the unattributed commits" "unattributed=2" "$STDOUT"
assert_eq "work/range matches the tag range" "v0.1.0..HEAD" "$(kget "$S" work/range)"
assert_eq "work/prs holds the numbers in (#N) subjects, sorted and unique" "7
12" "$(kget "$S" work/prs)"
assert_eq "work/unattributed holds the commits naming no pull request" "$LAST_UNATTR
$BUMP_UNATTR" "$(kget "$S" work/unattributed)"
assert_no_staging "after membership"

rs read "$TP" range
assert_eq "read range prints the stored range" "v0.1.0..HEAD" "$STDOUT"
rs read "$TP" prs
assert_eq "read prs exits 0" "0" "$RC"
assert_eq "read prs prints the stored list" "7
12" "$STDOUT"
rs read "$TP" unattributed
assert_eq "read unattributed prints the stored list" "$LAST_UNATTR
$BUMP_UNATTR" "$STDOUT"

# A second run after a new commit replaces the keys.
g commit -q --allow-empty -m "fix: late fix (#30)"
rs membership "$TP"
assert_eq "a second membership run exits 0" "0" "$RC"
assert_eq "the second run replaced work/prs" "7
12
30" "$(kget "$S" work/prs)"
assert_eq "the second run kept the range" "v0.1.0..HEAD" "$(kget "$S" work/range)"
assert_contains "the second run reports 3 pull requests" "prs=3" "$STDOUT"

# A new tag moves the range; a range with no (#N) subjects gives an empty work/prs.
g tag v0.2.0
g commit -q --allow-empty -m "chore: bump to 0.2.1"
rs membership "$TP"
assert_eq "membership after a new tag exits 0" "0" "$RC"
assert_contains "it reports prs=0 for the empty membership" "prs=0" "$STDOUT"
assert_eq "the range moved to the new tag" "v0.2.0..HEAD" "$(kget "$S" work/range)"
if kexists "$S" work/prs; then pass "an empty membership is a key that exists"; else fail "work/prs does not exist for an empty membership"; fi
assert_eq "a range with no (#N) subject reads back as an empty work/prs" "0" "$(kbytes "$S" work/prs)"
rs read "$TP" prs
assert_eq "read of the empty work/prs exits 0" "0" "$RC"
assert_eq "read of the empty work/prs prints nothing" "" "$STDOUT"
assert_eq "the earlier unattributed list was replaced" "$(git -C "$REPO" log -1 --format='%h %s')" "$(kget "$S" work/unattributed)"

# A leftover work/notes.md is removed by membership.
ss scratch
ND="$STDOUT"
printf 'stale notes from a crashed run\n' >"$ND/notes.md"
ss put "$S" work/notes.md "$ND/notes.md"
rm -rf "$ND"
if kexists "$S" work/notes.md; then pass "a notes key was left by the earlier run"; else fail "could not leave a notes key"; fi
rs read "$TP" notes
assert_eq "read of the notes prints them" "stale notes from a crashed run" "$STDOUT"
rs membership "$TP"
assert_eq "membership with a leftover notes key exits 0" "0" "$RC"
if kexists "$S" work/notes.md; then fail "membership left work/notes.md"; else pass "membership removed the leftover work/notes.md"; fi

# read of an absent key exits 1, naming Phase 1.
rs read "$TP" notes
assert_eq "read of the absent notes key exits 1" "1" "$RC"
assert_contains "it names Phase 1" "Phase 1 did not run" "$STDERR"
open_release fresh-session
rs read fresh-session prs
assert_eq "read of an absent work/prs exits 1" "1" "$RC"
assert_contains "it names Phase 1" "Phase 1 did not run" "$STDERR"
assert_eq "it prints nothing on stdout" "" "$STDOUT"
rs read never-opened range
assert_eq "read from an absent session exits 1" "1" "$RC"
assert_contains "it names Phase 1" "Phase 1 did not run" "$STDERR"

# membership refuses a session that is not live.
rs membership never-opened
assert_eq "membership with no session is refused with 2" "2" "$RC"
assert_contains "it says refused=session_not_live" "refused=session_not_live" "$STDOUT"

# --- the close -----------------------------------------------------------------------------------

echo
echo "== the close =="
ss status "$S"
assert_eq "the session is live before the close" "live" "$STDOUT"
ss close "$S" "abandoned"
assert_eq "close abandoned exits 0" "0" "$RC"
assert_contains "close reports closed=abandoned" "closed=abandoned" "$STDOUT"
ss status "$S"
assert_eq "skill-session.sh status prints finished after the abandoned close" "finished" "$STDOUT"
assert_eq "work/range stays readable from the finished session" "v0.2.0..HEAD" "$(kget "$S" work/range)"
rs membership "$TP"
assert_eq "membership on the finished session is refused with 2" "2" "$RC"
open_release "$TP"
assert_contains "the next open replaces the finished session" "opened=replaced" "$STDOUT"
rs membership "$TP"
assert_eq "a run on the replaced session writes the keys again" "v0.2.0..HEAD" "$(kget "$S" work/range)"

# A first release has no v* tag: the range is HEAD.
FIRST="$T/first"
mkdir -p "$FIRST"
git -C "$FIRST" init -q
git -C "$FIRST" checkout -q -b docs/first
git -C "$FIRST" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "feat: only commit (#3)"
RC=0
(cd "$FIRST" && PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$SS" open release first-release) >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "open release in the untagged repository exits 0" "0" "$RC"
RC=0
(cd "$FIRST" && PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$RS" membership first-release) >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "membership in the untagged repository exits 0" "0" "$RC"
assert_eq "a first release's range is HEAD" "HEAD" "$(cd "$FIRST" && "$REAL_KOTO" context get release-first-release work/range)"
assert_eq "a first release's work/prs holds its pull request" "3" "$(cd "$FIRST" && "$REAL_KOTO" context get release-first-release work/prs)"

# membership outside a git work tree is refused.
NOREPO="$T/norepo"
mkdir -p "$NOREPO"
RC=0
(cd "$NOREPO" && PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$RS" membership "$TP") >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "membership outside a git work tree is refused with 2" "2" "$RC"
assert_contains "it says refused=not_a_repository" "refused=not_a_repository" "$(cat "$T/stdout")"

# --- go -------------------------------------------------------------------------------------------

echo
echo "== go =="
# A repository inside a niwa instance root, a stub niwa that logs each call
# and answers as a holder (or, with NIWA_STUB=not-held, without cut-release),
# and a session id: what release-grant.sh needs to ask.
GO_INST="$T/go-inst"
GOREPO="$GO_INST/repo"
mkdir -p "$GO_INST/.niwa" "$GOREPO" "$T/niwastub"
echo '{}' >"$GO_INST/.niwa/instance.json"
NIWA_LOG="$T/niwa-calls"
# Ids are built at run time: a committed id-shaped literal reads as a real session id.
GO_ID=$(printf "%s-%s-%s-%s-%s" 3c803591 4c01 486f a927 f96ec399d6a7)
GO_SID=$(printf "%s-%s-%s-%s-%s" 0f1e2d3c 4b5a 4968 8776 a5b4c3d2e1f0)
export GO_ID
cat >"$T/niwastub/niwa" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NIWA_LOG"
grant='[{"authority":"cut-release","sources":["dispatch"]}]'
[ "${NIWA_STUB:-}" = not-held ] && grant='[{"authority":"merge-pr","sources":["dispatch"]}]'
printf '{"schema":"niwa.authority.check/v1","state":"bound","dispatch_id":"%s","grant":%s,"level":"autonomous","points":[{"point":"cut-release","decider":"session","author_exclusion":"off"}]}\n' "$GO_ID" "$grant"
STUB
chmod +x "$T/niwastub/niwa"
export NIWA_LOG

gg() { git -C "$GOREPO" -c user.name=t -c user.email=t@example.invalid "$@"; }
bot() {
    GIT_AUTHOR_NAME='github-actions[bot]' GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
        GIT_COMMITTER_NAME='github-actions[bot]' GIT_COMMITTER_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
        git -C "$GOREPO" commit -q --allow-empty -m "$1"
}
gg init -q
gg checkout -q -b docs/go
gg commit -q --allow-empty -m "feat: first (#1)"
bot "chore(release): set version to v0.1.0"
gg tag v0.1.0
bot "chore(release): advance to 0.1.1-dev"
gg commit -q --allow-empty -m "feat: add gamma (#21)"

# go_run <args...> -- release-state.sh in the go repository, with real koto,
# the stub niwa and a session id.
go_run() {
    RC=0
    : >"$NIWA_LOG"
    (cd "$GOREPO" && unset NIWA_BIN NIWA_LOOKUP_SECONDS \
        && CLAUDE_CODE_SESSION_ID="$GO_SID" PATH="$T/niwastub:$TOOLS_KOTO:$SYS_PATH" \
            "$BASH_BIN" "$RS" "$@") >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}
niwa_calls() { grep -c . "$NIWA_LOG" 2>/dev/null || true; }
go_membership() {
    RC=0
    (cd "$GOREPO" && PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$RS" membership go-run) >"$T/stdout" 2>"$T/stderr" || RC=$?
    [ "$RC" -eq 0 ] || fail "membership go-run exited $RC: $(cat "$T/stderr")"
}

RC=0
(cd "$GOREPO" && PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$SS" open release go-run) >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "open release go-run exits 0" "0" "$RC"
go_membership

for args in "--bump minor" "--bump patch" "--given" "--given --bump major"; do
    # shellcheck disable=SC2086 # the flags split on purpose
    go_run go go-run $args
    assert_eq "holder, $args: go exits 0" "0" "$RC"
    assert_eq "holder, $args: the go comes from the grant" "go=grant dispatch=$GO_ID" "$STDOUT"
    assert_eq "holder, $args: niwa was asked once" "1" "$(niwa_calls)"
done
assert_contains "the check asked for cut-release from the instance root" "authority check --json --session $GO_SID -C $GO_INST --point cut-release" "$(cat "$NIWA_LOG")"
if [ -z "$STDERR" ]; then pass "the release workflow's own commits are not named as direct pushes"; else fail "go named a commit: $STDERR"; fi

go_run go go-run --bump major
assert_eq "holder, a recommended major bump with no version given asks" "go=person reason=major-bump" "$STDOUT"
assert_eq "major bump: niwa not asked" "0" "$(niwa_calls)"
go_run go go-run --bump minor --unresolved
assert_eq "holder, an UNRESOLVED line in the security check asks" "go=person reason=unresolved" "$STDOUT"
assert_eq "unresolved: niwa not asked" "0" "$(niwa_calls)"

RC=0
(cd "$GOREPO" && NIWA_STUB=not-held NIWA_LOG="$NIWA_LOG" CLAUDE_CODE_SESSION_ID="$GO_SID" \
    PATH="$T/niwastub:$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$RS" go go-run --given) >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "a session without cut-release is asked, with release-grant.sh's reason" "go=person reason=not-held" "$(cat "$T/stdout")"

# Commits with no (#N) that the release workflow didn't write.
gg commit -q --allow-empty -m "fix: pushed straight to main"
go_membership
go_run go go-run --bump patch
assert_eq "holder, a direct push in the range asks" "go=person reason=direct-push" "$STDOUT"
assert_contains "the direct push is named" "pushed straight to main" "$STDERR"
assert_eq "direct push: niwa not asked" "0" "$(niwa_calls)"
gg reset -q --hard HEAD~1
bot "chore: tidy"
go_membership
go_run go go-run --bump patch
assert_eq "the bot identity with another subject is a direct push" "go=person reason=direct-push" "$STDOUT"
gg reset -q --hard HEAD~1
gg commit -q --allow-empty -m "chore(release): advance to 0.1.2-dev"
go_membership
go_run go go-run --bump patch
assert_eq "the release subject from another identity is a direct push" "go=person reason=direct-push" "$STDOUT"
gg reset -q --hard HEAD~1
go_membership
go_run go go-run --bump patch
assert_eq "with the direct pushes gone the go comes from the grant again" "go=grant dispatch=$GO_ID" "$STDOUT"

# A first release asks, whatever the grant and the version given.
RC=0
(cd "$FIRST" && CLAUDE_CODE_SESSION_ID="$GO_SID" PATH="$T/niwastub:$TOOLS_KOTO:$SYS_PATH" \
    "$BASH_BIN" "$RS" go first-release --given) >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "a first release asks for the version" "go=person reason=first-release" "$(cat "$T/stdout")"

go_run go never-opened --given
assert_eq "go without Phase 1's range exits 1" "1" "$RC"
assert_contains "it names Phase 1" "Phase 1 did not run" "$STDERR"

fi

# --- the Phase 4 blocks, extracted from SKILL.md at run time ------------------------------------

echo
echo "== the Phase 4 blocks =="
SKILL_MD="$SKILL_DIR/SKILL.md"
[ -f "$SKILL_MD" ] || fail "missing $SKILL_MD"

# phase <heading-prefix> -- the lines of a "### Phase N" section, up to the next ### heading.
phase() { awk -v h="$1" 'index($0, h) == 1 {p=1; next} /^### / {if (p) exit} /^## / {if (p) exit} p' "$SKILL_MD"; }
# bash_block_with <pattern> -- the first fenced bash block of stdin holding the pattern.
bash_block_with() {
    awk -v pat="$1" '
        /^[ ]*```bash[ ]*$/ {inb=1; blk=""; next}
        /^[ ]*```[ ]*$/ {if (inb) {inb=0; if (index(blk, pat)) {printf "%s", blk; exit}} next}
        inb {blk = blk $0 "\n"}'
}

PH4=$(phase '### Phase 4')
STORE_BLOCK=$(printf '%s\n' "$PH4" | bash_block_with 'put release-<topic> work/notes.md')
CREATE_BLOCK=$(printf '%s\n' "$PH4" | bash_block_with 'gh release create')
if [ -z "$STORE_BLOCK" ]; then fail "could not extract the notes-store block from Phase 4 of SKILL.md"; else pass "extracted the notes-store block from Phase 4"; fi
if [ -z "$CREATE_BLOCK" ]; then fail "could not extract the gh release create block from Phase 4 of SKILL.md"; else pass "extracted the gh release create block from Phase 4"; fi
case "$CREATE_BLOCK" in
    *'--notes-file'*) pass "the shipped block passes gh release create --notes-file" ;;
    *) fail "the shipped block does not pass --notes-file" ;;
esac

# subst <block> <topic> -- fill the prose's placeholders.
subst() { printf '%s\n' "$1" | sed -e "s|<topic>|$2|g" -e 's|<version>|0.3.0|g'; }

if [ "$ENGINE" -eq 1 ] && [ -n "$STORE_BLOCK" ] && [ -n "$CREATE_BLOCK" ]; then
    NOTES_TOPIC=notes-run
    open_release "$NOTES_TOPIC"
    rs membership "$NOTES_TOPIC"

    # Step 1: the store block, with the line where the agent writes the notes
    # replaced by a write of fixed notes.
    NOTES_TEXT='## v0.3.0
- feat: add alpha (#12)'
    subst "$STORE_BLOCK" "$NOTES_TOPIC" >"$T/store.sh"
    sed -i.bak "s|^# write the confirmed notes.*|printf '%s\\\\n' '## v0.3.0' '- feat: add alpha (#12)' >\"\$dir/notes.md\"|" "$T/store.sh"
    RC=0
    (cd "$REPO" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$T/store.sh") >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "the shipped store block exits 0" "0" "$RC"
    assert_eq "the store block put the notes under work/notes.md" "$NOTES_TEXT" "$(kget "release-$NOTES_TOPIC" work/notes.md)"

    # Step 2: the create block against the stubbed gh release create.
    subst "$CREATE_BLOCK" "$NOTES_TOPIC" >"$T/create.sh"
    rm -f "$GH_NOTES_PATH" "$GH_NOTES_COPY"
    : >"$GH_LOG"
    RC=0
    (cd "$REPO" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$T/create.sh") >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "the shipped create block exits 0" "0" "$RC"
    assert_contains "gh release create was called for the version" "release create v0.3.0 --draft --title v0.3.0 --notes-file" "$(cat "$GH_LOG")"
    NOTES_PATH=$(cat "$GH_NOTES_PATH" 2>/dev/null || echo "")
    if [ -n "$NOTES_PATH" ]; then pass "gh was given a --notes-file path"; else fail "gh was given no --notes-file path"; fi
    assert_eq "the file gh read held the stored notes" "$NOTES_TEXT" "$(cat "$GH_NOTES_COPY" 2>/dev/null)"
    case "$NOTES_PATH" in
        "$REPO"/*) fail "the notes file lay inside the work tree: $NOTES_PATH" ;;
        "") ;;
        *) pass "the notes file lay outside the work tree" ;;
    esac
    if [ -n "$NOTES_PATH" ] && [ ! -e "$NOTES_PATH" ] && [ ! -e "$(dirname "$NOTES_PATH")" ]; then
        pass "the notes file and its scratch directory no longer exist after the block"
    else
        fail "the notes file or its directory survived the block: $NOTES_PATH"
    fi
    assert_no_staging "after the Phase 4 blocks"

    # A failing gh still removes the directory and the block fails.
    rm -f "$GH_NOTES_PATH" "$GH_NOTES_COPY"
    RC=0
    (cd "$REPO" && GH_CREATE_RC=1 CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$T/create.sh") >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "a failing gh release create fails the block" "1" "$RC"
    NOTES_PATH=$(cat "$GH_NOTES_PATH" 2>/dev/null || echo "")
    if [ -n "$NOTES_PATH" ] && [ ! -e "$(dirname "$NOTES_PATH")" ]; then
        pass "the scratch directory is removed when gh fails"
    else
        fail "the scratch directory survived a failing gh: $NOTES_PATH"
    fi

    # Without stored notes the block stops before gh runs.
    rs membership "$NOTES_TOPIC"
    : >"$GH_LOG"
    RC=0
    (cd "$REPO" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PATH="$TOOLS_KOTO:$SYS_PATH" "$BASH_BIN" "$T/create.sh") >"$T/stdout" 2>"$T/stderr" || RC=$?
    if [ "$RC" -ne 0 ]; then pass "with no stored notes the create block fails"; else fail "the create block succeeded with no stored notes"; fi
    assert_eq "gh release create was not called without notes" "" "$(grep -c 'release create' "$GH_LOG" | sed 's/^0$//')"

    # The done close after Phase 4.
    ss close "release-$NOTES_TOPIC" "done"
    assert_contains "close done reports closed=done" "closed=done" "$STDOUT"
    ss status "release-$NOTES_TOPIC"
    assert_eq "the session is finished after the done close" "finished" "$STDOUT"
fi

# --- static cases: the prose calls the script -----------------------------------------------------------

echo
echo "== the prose =="
# shellcheck disable=SC2016
CALL='${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh'

PH1=$(phase '### Phase 1')
PH2=$(phase '### Phase 2')
PH3=$(phase '### Phase 3')
DRY=$(awk '/^## Dry-Run Mode/ {p=1; next} /^## / {if (p) exit} p' "$SKILL_MD")
RECOVERY=$(awk '/^## Error Recovery/ {p=1; next} /^## / {if (p) exit} p' "$SKILL_MD")

case "$PH1" in
    *"\"$CALL\" membership"*) pass "Phase 1 calls release-state.sh membership by its plugin-root path" ;;
    *) fail "Phase 1 does not call \"$CALL\" membership" ;;
esac
case "$PH1" in
    *"\"$CALL\" topic"*) pass "Phase 1 derives the topic with release-state.sh topic" ;;
    *) fail "Phase 1 does not call \"$CALL\" topic" ;;
esac
case "$PH1" in
    *'skill-session.sh" open release'*) pass "Phase 1 opens release-<topic>" ;;
    *) fail "Phase 1 does not open release-<topic>" ;;
esac
L_OPEN=$(grep -n -m1 'skill-session.sh" open release' <<<"$PH1" | cut -d: -f1)
L_MEM=$(grep -n -m1 -F "\"$CALL\" membership" <<<"$PH1" | cut -d: -f1)
if [ -n "$L_OPEN" ] && [ -n "$L_MEM" ] && [ "$L_OPEN" -lt "$L_MEM" ]; then
    pass "Phase 1 opens the session before it writes the membership"
else
    fail "Phase 1 does not open before membership (lines: open=$L_OPEN membership=$L_MEM)"
fi
case "$PH1" in
    *'refused=branch_mismatch'*'close release-<topic> abandoned'*) pass "Phase 1 tells the author how to recover from refused=branch_mismatch" ;;
    *) fail "Phase 1 has no recovery text for refused=branch_mismatch" ;;
esac
case "$PH2" in
    *"\"$CALL\" read"*prs*) pass "Phase 2 reads the membership with release-state.sh read" ;;
    *) fail "Phase 2 does not call \"$CALL\" read ... prs" ;;
esac
case "$PH3" in
    *"\"$CALL\" read"*range*) pass "Phase 3 reads the range with release-state.sh read" ;;
    *) fail "Phase 3 does not call \"$CALL\" read ... range" ;;
esac

# Every call to the script names it by the plugin-root path.
BARE=$(grep -nE 'release-state\.sh"? +(topic|membership|read|version|go)' "$SKILL_MD" | grep -vF "$CALL" | grep -vE '`release-state\.sh' || true)
if [ -n "$BARE" ]; then
    fail "a bash call names release-state.sh without its plugin-root path: $BARE"
else
    pass "every bash call to release-state.sh names it by its plugin-root path"
fi

# The closes: done at the end of the run (Phase 6) and of a dry run, abandoned
# on an earlier stop, a refused draft or dispatch included.
PH5=$(phase '### Phase 5')
PH6=$(phase '### Phase 6')
case "$PH6" in
    *'skill-session.sh" close release-<topic> done'*) pass "Phase 6 closes the session done at the end of the run" ;;
    *) fail "Phase 6 has no skill-session.sh close release-<topic> done" ;;
esac
case "$PH4" in
    *'close release-<topic> done'*) fail "Phase 4 still closes the session done before the dispatch" ;;
    *) pass "Phase 4 leaves the session open for the dispatch" ;;
esac
case "$PH4" in
    *'gate'*'close release-<topic> abandoned'*) pass "Phase 4 closes the session abandoned when the draft is refused" ;;
    *) fail "Phase 4 has no abandoned close for a refused draft" ;;
esac
case "$PH5" in
    *'refused'*'abandoned'*'REST'*) pass "Phase 5 closes abandoned on a refused dispatch and rules out the REST route" ;;
    *) fail "Phase 5 does not close abandoned on a refused dispatch, or does not rule out the REST route" ;;
esac

# The version check comes before anything runs; the go reads the grant.
L_VER=$(grep -n -m1 -F "\"$CALL\" version" <<<"$PH1" | cut -d: -f1)
if [ -n "$L_VER" ] && [ -n "$L_OPEN" ] && [ "$L_VER" -lt "$L_OPEN" ]; then
    pass "Phase 1 checks a given version before it opens the session"
else
    fail "Phase 1 does not check the version before the open (lines: version=$L_VER open=$L_OPEN)"
fi
case "$PH3" in
    *"\"$CALL\" go"*) pass "Phase 3 decides the go with release-state.sh go" ;;
    *) fail "Phase 3 does not call \"$CALL\" go" ;;
esac
case "$PH3" in
    *'release go: from the grant of dispatch <id>'*) pass "Phase 3 prints the grant's provenance line" ;;
    *) fail "Phase 3 has no provenance line for a go from the grant" ;;
esac
case "$PH3" in
    *'release-state.sh version'*) pass "Phase 3 checks a version chosen at the go" ;;
    *) fail "Phase 3 does not check a version chosen at the go" ;;
esac
case "$DRY" in
    *'close'*'release-<topic> done'*) pass "the dry run closes the session done" ;;
    *) fail "the dry-run section does not close the session done" ;;
esac
case "$PH2" in
    *'close release-<topic> abandoned'*) pass "Phase 2 closes the session abandoned when a check stops the release" ;;
    *) fail "Phase 2 has no close release-<topic> abandoned" ;;
esac
case "$PH3" in
    *'abandoned'*) pass "Phase 3 closes the session abandoned when the version is declined" ;;
    *) fail "Phase 3 does not close the session abandoned on a declined version" ;;
esac

# Error Recovery points at keys.
case "$RECOVERY" in
    *'work/prs'*'work/unattributed'*'work/range'*) pass "the Error Recovery rows point at the keys" ;;
    *) fail "the Error Recovery rows do not name work/prs, work/unattributed and work/range" ;;
esac

# No staging-file names anywhere in the skill's prose.
# The folder's name is built from two pieces so this file doesn't spell a
# staging path either.
WP="wi""p/"
OLD_NAMES="release-(range|prs|unattributed)\\.txt|release-notes-|${WP}release"
if grep -nE "$OLD_NAMES" "$SKILL_MD" >/dev/null 2>&1; then
    fail "an old staging file name remains in SKILL.md: $(grep -nE "$OLD_NAMES" "$SKILL_MD")"
else
    pass "no old staging file name remains in SKILL.md"
fi
if grep -qE "^[^\`]*(>|<) *${WP}|cat ${WP}|mkdir -p wip" "$SKILL_MD"; then
    fail "a command in SKILL.md still reads or writes the staging folder"
else
    pass "no command in SKILL.md reads or writes the staging folder"
fi

echo
echo "release-state_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
