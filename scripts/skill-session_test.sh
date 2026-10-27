#!/usr/bin/env bash
# skill-session_test.sh -- test harness for scripts/skill-session.sh, the
# shared operations of the skill-session convention, and for its store
# template, koto-templates/skill-session.md.
#
# Usage: bash scripts/skill-session_test.sh
#        /bin/bash scripts/skill-session_test.sh     # the bash 3.2 floor
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the engine-backed cases skipped
#   1 -- one or more cases failed
#
# Two groups, in execution order:
#
#   stand-in cases, which need jq and git but no koto. A stub koto records
#   every call it gets, so they pin what the script refuses before reaching
#   koto: names, parents and children, get/put keys and paths, koto missing
#   from PATH and koto below the floor. They also read the script itself:
#   no eval, no --parent, and --no-cleanup on every koto next. A second
#   stand-in that keeps sessions and keys in files runs the link step through
#   adopt and open --dispatched-by: the link verb's arguments, a retry that
#   works, two failures (the warning= line and the session/link-warning key,
#   exit 0), and no link on no match, two matches, an open without the flag
#   or a refused open. `reclaimable` is an unknown subcommand.
#
#   engine-backed cases, which drive the real koto in a store isolated by
#   KOTO_SESSIONS_BASE (and a private HOME), from a throwaway git repository:
#   every subcommand, the parent-and-child case with its dispatched-by link
#   and `koto session hierarchy` joining the two, open --dispatched-by, and
#   the read-only status. They
#   skip with a message when koto is absent, like the other engine-backed
#   suites; the CI job that runs this asserts koto is present first, so a skip
#   there cannot pass as green.
#
# Everything the suite creates lives under one mktemp -d directory, removed on
# exit; no session outside its own store is touched.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SS="$SCRIPT_DIR/skill-session.sh"
TEMPLATE="$SCRIPT_DIR/../koto-templates/skill-session.md"
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { printf "${GREEN}PASS${NC}: %s\n" "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf "${RED}FAIL${NC}: %s\n" "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$SS" ] || { echo "FAIL: skill-session.sh not found at $SS" >&2; exit 1; }
[ -f "$TEMPLATE" ] || { echo "FAIL: the store template not found at $TEMPLATE" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || {
    echo "SKIP: jq not on PATH -- skill-session.sh needs it, no case ran"
    exit 0
}
command -v git >/dev/null 2>&1 || {
    echo "SKIP: git not on PATH -- the branch cases need it, no case ran"
    exit 0
}

REAL_JQ=$(command -v jq)
REAL_GIT=$(command -v git)
REAL_KOTO=$(command -v koto 2>/dev/null) || REAL_KOTO=""

T=$(mktemp -d "${TMPDIR:-/tmp}/skill-session-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */skill-session-test.*) chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T" ;; esac; return 0; }
trap cleanup EXIT

# A private HOME (koto's template cache lands there) and a private session
# store: nothing here reaches the developer's own sessions.
# The caller's HOME, kept only for the opt-in real-bucket import case, which
# needs the caller's koto cloud configuration.
ORIG_HOME="${HOME:-}"
export HOME="$T/home"
export KOTO_SESSIONS_BASE="$T/sessions"
mkdir -p "$HOME" "$KOTO_SESSIONS_BASE"
unset KOTO_BIN KOTO_FLOOR
# The scratch directories the script allocates go under the suite's directory.
export TMPDIR="$T/tmp"
mkdir -p "$TMPDIR"

# PATH for every run: the tools directory plus the system directories, so a
# koto on the developer's PATH answers only when the engine cases link it in.
TOOLS="$T/tools"
mkdir -p "$TOOLS"
ln -s "$REAL_JQ" "$TOOLS/jq"
ln -s "$REAL_GIT" "$TOOLS/git"
SYS_PATH="/usr/bin:/bin"

REPO="$T/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" checkout -q -b main
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init

# --- the stand-in koto -------------------------------------------------------
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

# run_in <dir> <args...> -- run skill-session.sh from <dir>.
run_in() {
    local dir="$1"
    shift
    RC=0
    (cd "$dir" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" "$@") >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}
run() { run_in "$REPO" "$@"; }

# run_stub <args...> -- run against the stand-in koto.
run_stub() {
    rm -f "$STUB_LOG"
    RC=0
    (cd "$REPO" && KOTO_BIN="$STUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" "$@") \
        >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}
stub_called() { [ -s "$STUB_LOG" ]; }
stub_called_past_version() { [ -s "$STUB_LOG" ] && grep -qv '^version' "$STUB_LOG"; }

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
assert_gone() {
    if [ -e "$2" ] || [ -L "$2" ]; then fail "$1: $2 still exists"; else pass "$1"; fi
}
assert_no_staging() {
    if [ -e "$REPO/wip" ]; then fail "$1: a staging folder was created"; else pass "$1"; fi
}

# private_dir <path> -- a 0700 directory, the shape the scratch checks accept.
private_dir() { mkdir -p "$1" && chmod 0700 "$1"; }

echo "skill-session_test.sh: running under $BASH_BIN ($("$BASH_BIN" -c 'echo $BASH_VERSION'))"
echo

# --- the script itself ---------------------------------------------------------

CODE=$(grep -v '^[[:space:]]*#' "$SS")
if grep -qE '(^|[^A-Za-z_])eval([^A-Za-z_]|$)' <<<"$CODE"; then
    fail "skill-session.sh contains eval"
else
    pass "skill-session.sh contains no eval"
fi
if grep -q -- '--parent' <<<"$CODE"; then
    fail "skill-session.sh passes --parent somewhere"
else
    pass "skill-session.sh never passes --parent"
fi
NEXT_LINES=$(printf '%s\n' "$CODE" | grep -E '(koto|"\$KOTO") next ')
if [ -z "$NEXT_LINES" ]; then
    fail "found no koto next call in skill-session.sh to check"
elif grep -qv -- '--no-cleanup' <<<"$NEXT_LINES"; then
    fail "a koto next call in skill-session.sh lacks --no-cleanup: $(printf '%s\n' "$NEXT_LINES" | grep -v -- '--no-cleanup')"
else
    pass "every koto next call in skill-session.sh carries --no-cleanup ($(printf '%s\n' "$NEXT_LINES" | wc -l | tr -d ' ') call site)"
fi
if grep -qE 'declare -A|mapfile|readarray|local -n|declare -n' <<<"$CODE"; then
    fail "skill-session.sh uses a construct above the bash 3.2 floor"
else
    pass "skill-session.sh uses no construct above the bash 3.2 floor"
fi

# --- names -------------------------------------------------------------------------

run_stub name brief my-topic
assert_eq "name composes <skill>-<topic>" "brief-my-topic" "$STDOUT"
run_stub name review-plan t1
assert_eq "a hyphenated skill name is accepted" "review-plan-t1" "$STDOUT"

for bad in Foo a_b ../x ""; do
    run_stub name "$bad" t1
    if [ "$RC" -eq 64 ] && ! stub_called; then
        pass "skill name '$bad' is refused (exit 64) with no koto call"
    else
        fail "skill name '$bad': rc=$RC, koto called: $(stub_called && echo yes || echo no)"
    fi
    run_stub name brief "$bad"
    if [ "$RC" -eq 64 ] && ! stub_called; then
        pass "topic '$bad' is refused (exit 64) with no koto call"
    else
        fail "topic '$bad': rc=$RC, koto called: $(stub_called && echo yes || echo no)"
    fi
done

# Every subcommand that takes a name refuses a bad one before koto.
check_refused() {
    local label="$1"
    shift
    run_stub "$@"
    if [ "$RC" -eq 64 ] && ! stub_called; then
        pass "$label: exit 64, no koto call"
    else
        fail "$label: rc=$RC, koto called: $(stub_called && echo yes || echo no) [$STDERR]"
    fi
}
check_refused "open with skill Foo" open Foo t1
check_refused "open with topic ../x" open brief ../x
check_refused "status of Foo-x" status Foo-x
check_refused "status of a_b-x" status a_b-x
check_refused "status of ../x" status ../x
check_refused "status of an empty name" status ""
check_refused "has-work with topic a_b" has-work brief a_b
check_refused "close of ../x" close ../x done
check_refused "close with value finished" close brief-t1 finished
check_refused "dispatch write from a parent not in the closed set" dispatch write brief t1 prd fresh-chain
check_refused "dispatch write of a child not in the parent's list" dispatch write scope t1 vision fresh-chain
check_refused "dispatch write of charter's child from scope" dispatch write charter t1 design fresh-chain
check_refused "dispatch write with rationale other" dispatch write scope t1 design other
check_refused "dispatch write with an unknown option" dispatch write scope t1 design revise --quiet
check_refused "dispatch read with topic Foo" dispatch read design Foo
check_refused "dispatch clear from a parent not in the closed set" dispatch clear plan t1
check_refused "adopt with child a_b" adopt a_b t1
check_refused "close-children from a parent not in the closed set" close-children design t1 done
check_refused "close-children with value x" close-children scope t1 x
check_refused "reclaimable, retired for koto session hierarchy, is an unknown subcommand" reclaimable brief-t1
assert_contains "reclaimable is refused as an unknown subcommand" "unknown subcommand: reclaimable" "$STDERR"
assert_not_contains "the usage line no longer lists reclaimable" "reclaimable" "$(printf '%s\n' "$STDERR" | grep '^skill-session: usage:')"
check_refused "open with --dispatched-by and no name" open brief t1 --dispatched-by
check_refused "open with an option other than --dispatched-by" open brief t1 --parent scope-t1
check_refused "open with --dispatched-by ../x" open brief t1 --dispatched-by ../x
check_refused "open with --dispatched-by -x" open brief t1 --dispatched-by -x
check_refused "open with --dispatched-by naming the session itself" open brief t1 --dispatched-by brief-t1
check_refused "open with a --dispatched-by over 200 bytes" open brief t1 --dispatched-by "$(printf 'a%.0s' $(seq 1 201))"
check_refused "get from session Foo-x" get Foo-x work/a.md "$T"
check_refused "an unknown subcommand" frobnicate

# --- get and put: keys and paths --------------------------------------------------

SCR="$T/scratch-standin"
private_dir "$SCR"
printf 'doc\n' >"$SCR/doc.md"
for key in "work/../x" "work/a/../../b" "../work/a" "research/..hidden" "chain/parent" "session/branch" "handoff/scope.md" "x/work/a" "work/.a" "work/a b" "work/" "workx/a"; do
    run_stub get brief-t1 "$key" "$SCR"
    if [ "$RC" -eq 2 ] && ! stub_called; then
        pass "get refuses key '$key' (exit 2) with no koto call"
    else
        fail "get key '$key': rc=$RC, koto called: $(stub_called && echo yes || echo no)"
    fi
    run_stub put brief-t1 "$key" "$SCR/doc.md"
    if [ "$RC" -eq 2 ] && ! stub_called; then
        pass "put refuses key '$key' (exit 2) with no koto call"
    else
        fail "put key '$key': rc=$RC, koto called: $(stub_called && echo yes || echo no)"
    fi
done

run_stub get brief-t1 work/a.md "$SCR/../scratch-standin"
assert_eq "get refuses a directory path holding '..'" "2" "$RC"
run_stub put brief-t1 work/a.md "$SCR/../scratch-standin/doc.md"
assert_eq "put refuses a file path holding '..'" "2" "$RC"

mkdir -p "$REPO/inside"
chmod 0700 "$REPO/inside"
printf 'doc\n' >"$REPO/inside/doc.md"
run_stub get brief-t1 work/a.md "$REPO/inside"
assert_eq "get refuses a directory inside the work tree" "2" "$RC"
run_stub put brief-t1 work/a.md "$REPO/inside/doc.md"
assert_eq "put refuses a file inside the work tree" "2" "$RC"
rm -rf "$REPO/inside"

mkdir -p "$T/open-dir"
chmod 0755 "$T/open-dir"
run_stub get brief-t1 work/a.md "$T/open-dir"
assert_eq "get refuses a directory other users can read" "2" "$RC"

ln -s "$SCR" "$T/scratch-link"
run_stub get brief-t1 work/a.md "$T/scratch-link"
assert_eq "get refuses a symlinked directory" "2" "$RC"
ln -s "$SCR/doc.md" "$SCR/link.md"
run_stub put brief-t1 work/a.md "$SCR/link.md"
assert_eq "put refuses a symlinked file" "2" "$RC"
rm -f "$SCR/link.md"
stub_called && fail "a refused get/put path reached koto" || pass "refused get/put paths make no koto call"

# --- koto missing, koto below the floor -------------------------------------------

if PATH="$TOOLS:$SYS_PATH" command -v koto >/dev/null 2>&1; then
    echo "SKIP: a koto in $SYS_PATH -- the koto-absent case cannot remove it from PATH"
else
    RC=0
    (cd "$REPO" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" open brief absent) >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "open with koto absent from PATH exits 127" "127" "$RC"
    assert_contains "it says failed=koto_missing" "failed=koto_missing" "$(cat "$T/stdout")"
    assert_contains "its message names koto" "koto" "$(cat "$T/stderr")"
    assert_no_staging "koto absent: no file is created under the staging folder"
fi

rm -f "$STUB_LOG"
RC=0
(cd "$REPO" && KOTO_FLOOR=99.0.0 KOTO_BIN="$STUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" open brief low) \
    >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "open with a koto below the floor exits 69" "69" "$RC"
assert_contains "it says failed=koto_below_floor" "failed=koto_below_floor" "$(cat "$T/stdout")"
assert_contains "its message names koto" "koto" "$(cat "$T/stderr")"
if stub_called_past_version; then
    fail "a koto below the floor was asked for more than its version: $(cat "$STUB_LOG")"
else
    pass "a koto below the floor is asked only for its version"
fi
assert_no_staging "koto below the floor (stand-in): no file is created under the staging folder"

# --- the link step, against a stand-in koto ----------------------------------------
#
# A stand-in that keeps sessions and keys in files under $LINK_STORE, so open,
# adopt and the link step run end to end without a koto that has the link verb.
# Every call is recorded in $STUB_LOG. `koto session link` fails the first
# $LINK_FAILS times it is called (0 when unset) and succeeds after that;
# LINK_ADD_FAILS makes `context add` of the warning key fail too.
LINK_STUB_DIR="$T/linkbin"
mkdir -p "$LINK_STUB_DIR"
LINK_STORE="$T/link-store"
cat >"$LINK_STUB_DIR/koto" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_LOG"
S="$LINK_STORE"
case "${1:-} ${2:-}" in
    "version "*) printf 'koto 99.0.0 (stub)\n'; exit 0 ;;
    "init "*)
        mkdir -p "$S/status" "$S/keys/$2"
        printf 'live\n' >"$S/status/$2"
        printf '{"outcome":"created"}\n'
        exit 0 ;;
    "next "*) printf '{"state":"open"}\n'; exit 0 ;;
    "status "*)
        if [ -f "$S/status/$2" ]; then
            if [ "$(cat "$S/status/$2")" = live ]; then printf '{"is_terminal":false}\n'; else printf '{"is_terminal":true}\n'; fi
            exit 0
        fi
        printf '{"error":"workflow %s not found"}\n' "$2"
        exit 2 ;;
    "context add")
        if [ -n "${LINK_ADD_FAILS:-}" ] && [ "$4" = session/link-warning ]; then exit 1; fi
        mkdir -p "$(dirname "$S/keys/$3/$4")"
        cat >"$S/keys/$3/$4"
        exit 0 ;;
    "context exists") [ -f "$S/keys/$3/$4" ] && exit 0; exit 1 ;;
    "context get") cat "$S/keys/$3/$4" 2>/dev/null || exit 1; exit 0 ;;
    "context remove") rm -f "$S/keys/$3/$4"; exit 0 ;;
    "session link")
        n=$(cat "$S/link-count" 2>/dev/null || echo 0)
        n=$((n + 1))
        printf '%s\n' "$n" >"$S/link-count"
        if [ "$n" -le "${LINK_FAILS:-0}" ]; then
            printf '{"error":{"code":"stub_link_failed","message":"stub"}}\n'
            exit 1
        fi
        printf '{"linked":true}\n'
        exit 0 ;;
esac
printf '{"error":"stub"}\n'
exit 1
STUB
chmod +x "$LINK_STUB_DIR/koto"
export LINK_STORE

# link_fresh -- an empty store and call log.
link_fresh() { rm -rf "$LINK_STORE"; mkdir -p "$LINK_STORE/status" "$LINK_STORE/keys"; rm -f "$STUB_LOG"; }
# link_session <name> <live|finished> -- a session the stand-in answers for.
link_session() { mkdir -p "$LINK_STORE/keys/$1"; printf '%s\n' "$2" >"$LINK_STORE/status/$1"; }
# link_key <session> <key> <value> -- a key the stand-in holds.
link_key() { mkdir -p "$(dirname "$LINK_STORE/keys/$1/$2")"; printf '%s' "$3" >"$LINK_STORE/keys/$1/$2"; }
link_has() { [ -f "$LINK_STORE/keys/$1/$2" ]; }
link_val() { cat "$LINK_STORE/keys/$1/$2" 2>/dev/null; }
# link_calls -- the stand-in's `session link` calls, one per line.
link_calls() { [ -f "$STUB_LOG" ] && grep '^session link ' "$STUB_LOG"; return 0; }
# call_order <session> <key> -- the order of the write of <key> into <session>
# and the link calls, as <key>|link|...
call_order() {
    awk -v add="context add $1 $2" '
        $0 == add { printf "%s|", "'"$2"'" }
        /^session link / { printf "link|" }
    ' "$STUB_LOG"
}
run_link() {
    RC=0
    (cd "$REPO" && KOTO_BIN="$LINK_STUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" "$@") \
        >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}
# A parent scope-<topic> that dispatched design, on this repository's branch.
link_parent() {
    link_session "scope-$1" live
    link_key "scope-$1" session/branch "main"
    link_key "scope-$1" chain/dispatch "child: design
suppress_status_aware_prompt: true
rationale: fresh-chain
"
}

# adopt, one match: chain/parent first, then the link, naming the parent.
link_fresh
link_parent lk1
link_session design-lk1 live
LINK_FAILS=0 run_link adopt design lk1
assert_eq "adopt with one match exits 0" "0" "$RC"
assert_eq "adopt with one match prints only adopted=" "adopted=scope-lk1" "$STDOUT"
assert_eq "adopt runs the link verb once, naming the child and the parent" \
    "session link design-lk1 --dispatched-by scope-lk1" "$(link_calls)"
assert_eq "chain/parent is written before the link" "chain/parent|link|" "$(call_order design-lk1 chain/parent)"
if link_has design-lk1 session/link-warning; then fail "a link that worked recorded a warning key"; else pass "a link that worked records no warning key"; fi

# adopt, a link that fails once and works on the retry.
link_fresh
link_parent lk2
link_session design-lk2 live
LINK_FAILS=1 run_link adopt design lk2
assert_eq "adopt with a link that fails once exits 0" "0" "$RC"
assert_eq "a link that works on the retry prints no warning" "adopted=scope-lk2" "$STDOUT"
assert_eq "the link is run twice" "2" "$(link_calls | grep -c 'session link design-lk2 --dispatched-by scope-lk2')"
if link_has design-lk2 session/link-warning; then fail "a link that worked on the retry recorded a warning key"; else pass "a link that works on the retry records no warning key"; fi

# adopt, a link that fails twice: warn, record, exit 0.
link_fresh
link_parent lk3
link_session design-lk3 live
LINK_FAILS=2 run_link adopt design lk3
assert_eq "adopt with a link that fails twice still exits 0" "0" "$RC"
assert_eq "adopt prints adopted= and then the warning naming the parent" \
    "adopted=scope-lk3
warning=link-failed dispatched_by=scope-lk3" "$STDOUT"
assert_eq "the link is tried twice and no more" "2" "$(link_calls | wc -l | tr -d ' ')"
assert_eq "the warning is recorded in the child's own session" "warning=link-failed
dispatched_by=scope-lk3" "$(link_val design-lk3 session/link-warning)"
if link_has scope-lk3 session/link-warning; then fail "the warning was written into the parent's session"; else pass "nothing is written into the parent's session"; fi
assert_eq "chain/parent stands after a failed link" "scope-lk3" "$(link_val design-lk3 chain/parent)"
assert_contains "the failure is said on stderr" "scope-lk3" "$STDERR"

# The warning key itself can't be written: still exit 0, said on stderr.
link_fresh
link_parent lk4
link_session design-lk4 live
LINK_FAILS=2 LINK_ADD_FAILS=1 run_link adopt design lk4
assert_eq "a warning key that can't be written: adopt still exits 0" "0" "$RC"
assert_contains "it still prints the warning" "warning=link-failed dispatched_by=scope-lk4" "$STDOUT"
assert_contains "and says the key was not written" "session/link-warning" "$STDERR"

# A later link that works removes the earlier failure's record.
link_fresh
link_parent lk5
link_session design-lk5 live
link_key design-lk5 session/link-warning "warning=link-failed
dispatched_by=scope-lk5
"
LINK_FAILS=0 run_link adopt design lk5
if link_has design-lk5 session/link-warning; then fail "a link that worked left an earlier warning key"; else pass "a link that works removes an earlier warning key"; fi

# adopt, no match and two matches: no link.
link_fresh
link_session design-lk6 live
run_link adopt design lk6
assert_eq "adopt with no match prints adopted=none" "adopted=none" "$STDOUT"
assert_eq "adopt with no match runs no link" "" "$(link_calls)"
link_fresh
link_parent lk7
link_session charter-lk7 live
link_key charter-lk7 session/branch "main"
link_key charter-lk7 chain/dispatch "child: design
suppress_status_aware_prompt: true
rationale: revise
"
link_session design-lk7 live
run_link adopt design lk7
assert_eq "adopt with two matches exits 3" "3" "$RC"
assert_eq "adopt with two matches runs no link" "" "$(link_calls)"

# open --dispatched-by: open, then link from the opened session.
link_fresh
LINK_FAILS=0 run_link open brief lk8 --dispatched-by deliver-lk8
assert_eq "open --dispatched-by exits 0" "0" "$RC"
assert_eq "open --dispatched-by prints the open's lines only" "session=brief-lk8
opened=new" "$STDOUT"
assert_eq "open --dispatched-by runs the link verb once, naming the session and the dispatcher" \
    "session link brief-lk8 --dispatched-by deliver-lk8" "$(link_calls)"
assert_eq "the link comes after the session's branch is written" "session/branch|link|" "$(call_order brief-lk8 session/branch)"

link_fresh
LINK_FAILS=1 run_link open brief lk9 --dispatched-by deliver-lk9
assert_eq "open --dispatched-by with a link that fails once exits 0" "0" "$RC"
assert_eq "a retry that works prints no warning" "session=brief-lk9
opened=new" "$STDOUT"
assert_eq "the link is run twice" "2" "$(link_calls | wc -l | tr -d ' ')"
if link_has brief-lk9 session/link-warning; then fail "open recorded a warning for a link that worked on the retry"; else pass "open records no warning for a link that works on the retry"; fi

link_fresh
LINK_FAILS=2 run_link open brief lk10 --dispatched-by deliver-lk10
assert_eq "open --dispatched-by with a link that fails twice still exits 0" "0" "$RC"
assert_eq "open prints its lines and then the warning naming the dispatcher" "session=brief-lk10
opened=new
warning=link-failed dispatched_by=deliver-lk10" "$STDOUT"
assert_eq "the warning is recorded in the opened session" "warning=link-failed
dispatched_by=deliver-lk10" "$(link_val brief-lk10 session/link-warning)"
assert_eq "the opened session keeps its branch" "main" "$(link_val brief-lk10 session/branch)"

# open without the flag: no link, the same lines as before.
link_fresh
LINK_FAILS=0 run_link open brief lk11
assert_eq "open without --dispatched-by exits 0" "0" "$RC"
assert_eq "open without --dispatched-by prints what it always has" "session=brief-lk11
opened=new" "$STDOUT"
assert_eq "open without --dispatched-by runs no link" "" "$(link_calls)"
if [ -f "$STUB_LOG" ] && grep -q 'link-warning' "$STUB_LOG"; then
    fail "open without --dispatched-by touched the warning key"
else
    pass "open without --dispatched-by never touches the warning key"
fi

# A refused open links nothing.
link_fresh
link_session brief-lk12 live
link_key brief-lk12 session/branch "elsewhere"
cat >"$LINK_STUB_DIR/koto-attach" <<'STUB'
#!/bin/bash
if [ "${1:-}" = init ]; then
    printf '%s\n' "$*" >>"$STUB_LOG"
    printf '{"outcome":"attached","rebound":{}}\n'
    exit 0
fi
exec "$(dirname "$0")/koto" "$@"
STUB
chmod +x "$LINK_STUB_DIR/koto-attach"
RC=0
(cd "$REPO" && KOTO_BIN="$LINK_STUB_DIR/koto-attach" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" open brief lk12 --dispatched-by deliver-lk12) \
    >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "an open refused for another branch exits 5" "5" "$RC"
assert_eq "a refused open runs no link" "" "$(link_calls)"

# --- import, against a stand-in koto -----------------------------------------------
#
# The stand-in answers `koto session import <name> --from <path>` from one file
# per name in $IMPORT_ANSWERS: its first line is the exit code, the rest is
# stdout. A name with no file answers as koto does for a source that isn't in
# the bucket. The answers copy the shapes koto documents for the verb in
# tsukumogami/koto, docs/designs/current/DESIGN-session-migration.md ("The
# verb"): one JSON object on success, {"error": {"code", "message"}} with exit
# 2 for the caller-actionable refusals and 1 for the rest.
IMPORT_STUB_DIR="$T/importbin"
mkdir -p "$IMPORT_STUB_DIR"
IMPORT_ANSWERS="$T/import-answers"
cat >"$IMPORT_STUB_DIR/koto" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$1 ${2:-} ${3:-}" in
    "version "*) printf 'koto 0.16.0 (stub)\n'; exit 0 ;;
    "session import --help")
        [ -n "${IMPORT_NO_VERB:-}" ] && { printf 'error: unrecognized subcommand\n' >&2; exit 2; }
        exit 0 ;;
    "template compile "*)
        if [ -n "${IMPORT_COMPILE_FAIL:-}" ] && [ "${3##*/}" = "$IMPORT_COMPILE_FAIL" ]; then
            printf 'error: template %s does not compile\n' "$3" >&2
            exit 1
        fi
        printf '/cache/compiled-%s.json\n' "${3##*/}"
        exit 0 ;;
esac
if [ "$1 ${2:-}" = "session import" ]; then
    f="$IMPORT_ANSWERS/$3"
    if [ -f "$f" ]; then
        rc=$(sed -n 1p "$f")
        sed -n '2,$p' "$f"
        exit "$rc"
    fi
    printf '{"error":{"code":"import_source_not_found","message":"no such session at the source"}}\n'
    exit 2
fi
printf '{"error":"stub"}\n'
exit 1
STUB
chmod +x "$IMPORT_STUB_DIR/koto"
export IMPORT_ANSWERS

# answer <name> <rc> <stdout> -- script the stand-in's answer for one name.
answer() { mkdir -p "$IMPORT_ANSWERS"; printf '%s\n%s\n' "$2" "$3" >"$IMPORT_ANSWERS/$1"; }
imported_json() { printf '{"name":"%s","imported":true,"from":{"workspace":"/src/ws","session":"%s"},"keys":3,"template":"local-cache","marked":true}' "$1" "$1"; }
run_import() {
    rm -f "$STUB_LOG"
    RC=0
    (cd "$REPO" && KOTO_BIN="$IMPORT_STUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" import "$@") \
        >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}
import_calls() {
    if [ -f "$STUB_LOG" ]; then grep -c '^session import [a-z]' "$STUB_LOG" | tr -d ' '; else echo 0; fi
}

rm -rf "$IMPORT_ANSWERS"
answer scope-imp 0 "$(imported_json scope-imp)"
answer plan-imp 0 "$(imported_json plan-imp)"
run_import tactical imp --from /src/ws
assert_eq "import: two of six tactical names present exits 0" "0" "$RC"
assert_eq "import: it prints one line per name, in the set's order" \
"imported=scope-imp
skipped=brief-imp reason=not-found
skipped=prd-imp reason=not-found
skipped=design-imp reason=not-found
imported=plan-imp
skipped=explore-imp reason=not-found" "$STDOUT"
if grep -qE -- '--as|--trust-template' "$STUB_LOG"; then
    fail "import passed --as or --trust-template: $(grep -E -- '--as|--trust-template' "$STUB_LOG")"
else
    pass "import never passes --as or --trust-template"
fi
assert_contains "import passes --from with the path as given" "session import scope-imp --from /src/ws" "$(cat "$STUB_LOG")"

rm -rf "$IMPORT_ANSWERS"
run_import strategic none --from /src/ws
assert_eq "import: nothing of the set at the source exits 3" "3" "$RC"
assert_eq "import: every strategic name is reported skipped" "5" "$(printf '%s\n' "$STDOUT" | grep -c '^skipped=')"
assert_contains "import: the message names the source" "/src/ws" "$STDERR"

rm -rf "$IMPORT_ANSWERS"
answer scope-taken 0 "$(imported_json scope-taken)"
answer brief-taken 0 "$(imported_json brief-taken)"
answer prd-taken 2 '{"error":{"code":"import_name_taken","message":"a session named prd-taken already exists here"}}'
run_import tactical taken --from /src/ws
assert_eq "import: a refusal other than not-found exits 1" "1" "$RC"
assert_eq "import: it prints the failed line last, after the names it imported" \
"imported=scope-taken
imported=brief-taken
failed=prd-taken code=import_name_taken" "$STDOUT"
assert_eq "import: no koto call follows the refusal" "3" "$(import_calls)"

rm -rf "$IMPORT_ANSWERS"
answer comp-garbled 0 'not json at all'
run_import comp garbled --from /src/ws
assert_eq "import: output it can't parse exits 1" "1" "$RC"
assert_eq "import: and reads as code=unparseable" "failed=comp-garbled code=unparseable" "$STDOUT"
answer comp-garbled 1 '{"error":{"code":"import_push_failed; rm -rf /","message":"x"}}'
run_import comp garbled --from /src/ws
assert_eq "import: a code outside koto's shape is printed as unparseable" "failed=comp-garbled code=unparseable" "$STDOUT"

# A re-run after a stop: koto treats the names it already imported as a retry.
rm -rf "$IMPORT_ANSWERS"
answer scope-again 0 "$(imported_json scope-again)"
answer brief-again 2 '{"error":{"code":"import_template_unavailable","message":"compile the template first"}}'
run_import tactical again --from /src/ws
assert_eq "import: a first run stops at the refusal" "1" "$RC"
answer brief-again 0 "$(imported_json brief-again)"
run_import tactical again --from /src/ws
assert_eq "import: the re-run exits 0" "0" "$RC"
assert_eq "import: and reports the earlier name imported again" "imported=scope-again" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"
assert_eq "import: and the rest of the set" "imported=brief-again" "$(printf '%s\n' "$STDOUT" | sed -n 2p)"

rm -rf "$IMPORT_ANSWERS"
answer release-one 0 "$(imported_json release-one)"
run_import release one --from /src/ws
assert_eq "import: a leaf set imports its one session" "imported=release-one" "$STDOUT"
answer explore-one 0 "$(imported_json explore-one)"
run_import explore one --from /src/ws
assert_eq "import: the explore set is the one explore session" "imported=explore-one" "$STDOUT"

for bad in "tactical imp --from ws/relative" "nosuch imp --from /src/ws" "tactical -x --from /src/ws" "tactical imp /src/ws" "tactical imp --to /src/ws"; do
    # shellcheck disable=SC2086
    run_import $bad
    if [ "$RC" -eq 64 ] && ! [ -s "$STUB_LOG" ]; then
        pass "import refuses [$bad] with 64 before any koto call"
    else
        fail "import [$bad]: expected 64 and no koto call, got $RC and calls [$(cat "$STUB_LOG" 2>/dev/null)]"
    fi
done

rm -f "$STUB_LOG"
RC=0
(cd "$REPO" && IMPORT_NO_VERB=1 KOTO_BIN="$IMPORT_STUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" import tactical imp --from /src/ws) \
    >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "import: a koto without session import exits 69" "69" "$RC"
assert_contains "it prints failed=koto_no_import" "failed=koto_no_import" "$(cat "$T/stdout")"
assert_eq "it imports nothing" "0" "$(import_calls)"

compile_calls() {
    if [ -f "$STUB_LOG" ]; then grep -c '^template compile ' "$STUB_LOG" | tr -d ' '; else echo 0; fi
}
# The tactical and strategic sets leave the compile to their caller.
rm -rf "$IMPORT_ANSWERS"
answer scope-imp 0 "$(imported_json scope-imp)"
run_import tactical imp --from /src/ws
assert_eq "import tactical: no template compile call" "0" "$(compile_calls)"
run_import strategic imp --from /src/ws
assert_eq "import strategic: no template compile call" "0" "$(compile_calls)"

# The execute and deliver sets compile their shipped templates first, from the
# script's own plugin root.
PLUGIN_ROOT_T=$(cd -P "$SCRIPT_DIR/.." && pwd -P)
rm -rf "$IMPORT_ANSWERS"
answer execute-imp 0 "$(imported_json execute-imp)"
run_import execute imp --from /src/ws
assert_eq "import execute: exits 0" "0" "$RC"
assert_eq "import execute: prints the session imported under its own name" "imported=execute-imp" "$STDOUT"
assert_eq "import execute: compiles both shipped execute templates, then imports" \
"template compile $PLUGIN_ROOT_T/skills/execute/koto-templates/execute.md
template compile $PLUGIN_ROOT_T/skills/execute/koto-templates/execute-coordinated.md
session import execute-imp --from /src/ws" "$(grep -E '^(template compile|session import [a-z])' "$STUB_LOG")"
if grep -qE -- '--as|--trust-template' "$STUB_LOG"; then
    fail "import execute passed --as or --trust-template"
else
    pass "import execute never passes --as or --trust-template"
fi

rm -rf "$IMPORT_ANSWERS"
answer deliver-imp 0 "$(imported_json deliver-imp)"
run_import deliver imp --from /src/ws
assert_eq "import deliver: exits 0" "0" "$RC"
assert_eq "import deliver: prints imported=deliver-imp" "imported=deliver-imp" "$STDOUT"
assert_eq "import deliver: compiles deliver.md, then imports deliver-imp" \
"template compile $PLUGIN_ROOT_T/skills/deliver/koto-templates/deliver.md
session import deliver-imp --from /src/ws" "$(grep -E '^(template compile|session import [a-z])' "$STUB_LOG")"

rm -rf "$IMPORT_ANSWERS"
answer execute-imp 0 "$(imported_json execute-imp)"
rm -f "$STUB_LOG"
RC=0
(cd "$REPO" && IMPORT_COMPILE_FAIL=execute-coordinated.md KOTO_BIN="$IMPORT_STUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" import execute imp --from /src/ws) \
    >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "import execute: a template that doesn't compile exits 1" "1" "$RC"
assert_eq "import execute: and prints failed=template_compile naming it" \
    "failed=template_compile template=execute-coordinated.md" "$(cat "$T/stdout")"
assert_contains "import execute: koto's compile diagnostic reaches stderr" "does not compile" "$(cat "$T/stderr")"
assert_eq "import execute: no session import after the failed compile" "0" "$(import_calls)"

rm -rf "$IMPORT_ANSWERS"
answer execute-taken 2 '{"error":{"code":"import_name_taken","message":"a session named execute-taken already exists here"}}'
run_import execute taken --from /src/ws
assert_eq "import execute: a live session of that name exits 1" "1" "$RC"
assert_eq "import execute: and prints koto's code" "failed=execute-taken code=import_name_taken" "$STDOUT"

rm -f "$STUB_LOG"
run_import executes t --from /src/ws
if [ "$RC" -eq 64 ] && ! [ -s "$STUB_LOG" ]; then
    pass "import refuses the unknown set [executes] with 64 before any koto call"
else
    fail "import [executes t]: expected 64 and no koto call, got $RC and calls [$(cat "$STUB_LOG" 2>/dev/null)]"
fi

# --- a session koto removed, against a stand-in koto --------------------------------
#
# A koto that keeps finished records (tsukumogami/koto#355) answers `koto status`
# for a session it removed at its terminal: exit 0, "removed": true, and the
# final state and result a kept terminal session reports. An older koto, and the
# new one for a name that never existed, answer "not found" with exit 2. The
# stand-in answers `koto status <name>` from one file per name in
# $STATUS_ANSWERS (first line the exit code, the rest stdout), and a name with
# no file as koto does for one that never existed. A real koto is never asked:
# the one on PATH may predate the record.
STATUS_STUB_DIR="$T/statusbin"
mkdir -p "$STATUS_STUB_DIR"
STATUS_ANSWERS="$T/status-answers"
cat >"$STATUS_STUB_DIR/koto" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "${1:-}" in
    version) printf 'koto 0.16.0 (stub)\n'; exit 0 ;;
    status)
        f="$STATUS_ANSWERS/${2:-}"
        if [ -f "$f" ]; then
            rc=$(sed -n 1p "$f")
            sed -n '2,$p' "$f"
            exit "$rc"
        fi
        printf '{"command":"status","error":"workflow '"'"'%s'"'"' not found"}\n' "${2:-}"
        exit 2 ;;
esac
printf '{"error":"stub"}\n'
exit 1
STUB
chmod +x "$STATUS_STUB_DIR/koto"
export STATUS_ANSWERS

# status_answer <name> <rc> <stdout> -- script the stand-in's answer for one name.
status_answer() { mkdir -p "$STATUS_ANSWERS"; printf '%s\n%s\n' "$2" "$3" >"$STATUS_ANSWERS/$1"; }
# removed_json <name> -- the answer koto documents for a session it removed.
removed_json() {
    printf '{"name":"%s","current_state":"done","is_terminal":true,"result":{"status":"success","payload":{}},"removed":true,"finished_at":"2026-10-12T14:00:00Z","session_id":"0123456789abcdef","execution_dir":"/work/repo"}' "$1"
}
run_status_stub() {
    rm -f "$STUB_LOG"
    RC=0
    (cd "$REPO" && KOTO_BIN="$STATUS_STUB_DIR/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" "$@") \
        >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}
# past_status -- the stand-in's calls other than version and status, one per line.
past_status() { [ -f "$STUB_LOG" ] && grep -vE '^(version|status)( |$)' "$STUB_LOG"; return 0; }

rm -rf "$STATUS_ANSWERS"
status_answer scope-gone 0 "$(removed_json scope-gone)"
status_answer brief-gone 0 "$(removed_json brief-gone)"
status_answer brief-kept 0 '{"name":"brief-kept","current_state":"done","is_terminal":true,"result":{"status":"success","payload":{}}}'
status_answer brief-unremoved 0 '{"name":"brief-unremoved","current_state":"done","is_terminal":true,"removed":false}'

for case in "scope-gone|removed" "scope-never|never-existed"; do
    name="${case%%|*}"
    label="${case#*|}"

    run_status_stub status "$name"
    assert_eq "status of a $label session: exit 0" "0" "$RC"
    assert_eq "status of a $label session prints absent" "absent" "$STDOUT"

    run_status_stub dispatch clear scope "${name#scope-}"
    assert_eq "dispatch clear of a $label parent: exit 0" "0" "$RC"
    assert_eq "dispatch clear of a $label parent prints cleared=absent" "cleared=absent" "$STDOUT"
    assert_eq "dispatch clear of a $label parent asks koto nothing past status" "" "$(past_status)"
done

for case in "brief-gone|removed" "brief-never|never-existed"; do
    name="${case%%|*}"
    label="${case#*|}"

    run_status_stub get "$name" work/a.md "$SCR"
    assert_eq "get from a $label session: exit 2" "2" "$RC"
    assert_eq "get from a $label session prints refused=session_absent" "refused=session_absent" "$STDOUT"
    assert_contains "get from a $label session says it does not exist" "$name does not exist" "$STDERR"
    assert_eq "get from a $label session reads no key" "" "$(past_status)"
    assert_gone "get from a $label session writes no file" "$SCR/a.md"

    run_status_stub close "$name" done
    assert_eq "close of a $label session: exit 0" "0" "$RC"
    assert_eq "close of a $label session is a noop on an absent session" "closed=noop
status=absent" "$STDOUT"
    assert_eq "close of a $label session ticks nothing" "" "$(past_status)"
done

# The removed check reads only a boolean true: a kept terminal session, with or
# without "removed": false, still reads finished.
run_status_stub status brief-kept
assert_eq "status of a kept terminal session still prints finished" "finished" "$STDOUT"
run_status_stub status brief-unremoved
assert_eq "status of a terminal session with removed: false prints finished" "finished" "$STDOUT"

# --- engine-backed -------------------------------------------------------------------

if [ -z "$REAL_KOTO" ]; then
    echo
    echo "SKIP: koto not on PATH -- the engine-backed cases did not run"
    echo "skill-session_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
fi
ln -s "$REAL_KOTO" "$TOOLS/koto"
echo
echo "engine-backed cases against $("$REAL_KOTO" version 2>/dev/null | head -1)"

# koto run from the repository, with the suite's PATH and store.
k() { (cd "$REPO" && PATH="$TOOLS:$SYS_PATH" "$REAL_KOTO" "$@"); }
kadd() { printf '%s' "$3" | k context add "$1" "$2" >/dev/null 2>&1; }
kget() { k context get "$1" "$2" 2>/dev/null; }
khas() { k context exists "$1" "$2" >/dev/null 2>&1; }
state_log() { printf '%s/koto-%s.state.jsonl' "$(k session dir "$1")" "$1"; }
line() { printf '%s\n' "$STDOUT" | sed -n "${1}p"; }

# --- the store template ---

RC=0
k template compile "$TEMPLATE" >"$T/compiled" 2>"$T/compile-err" || RC=$?
assert_eq "the store template compiles" "0" "$RC"
assert_eq "the store template compiles with no warning" "" "$(cat "$T/compile-err")"
k init tpl-probe --template "$TEMPLATE" >/dev/null 2>&1
assert_eq "the store template's first tick stops at open" "open" \
    "$(k next tpl-probe --no-cleanup 2>/dev/null | jq -r '.state')"

# --- open: new, attached, replaced ---

run open brief t1
assert_eq "open on no session exits 0" "0" "$RC"
assert_eq "open prints the session first" "session=brief-t1" "$(line 1)"
assert_eq "open on no session: opened=new" "opened=new" "$(line 2)"
assert_eq "a new session records its branch" "main" "$(kget brief-t1 session/branch)"
assert_eq "the new session waits at open" "open" "$(k status brief-t1 | jq -r '.current_state')"
assert_no_staging "open writes nothing under the staging folder"

kadd brief-t1 work/context.md "kept"
run open brief t1
assert_eq "open on a live session: opened=attached" "opened=attached" "$(line 2)"
assert_eq "an attached session keeps its keys" "kept" "$(kget brief-t1 work/context.md)"

# --- status, read-only ---

run status brief-t1
assert_eq "status of a live session: live" "live" "$STDOUT"
LOG=$(state_log brief-t1)
BEFORE=$(wc -l <"$LOG" | tr -d ' ')
cp "$LOG" "$T/log-before"
run status brief-t1
run status brief-t1
AFTER=$(wc -l <"$LOG" | tr -d ' ')
assert_eq "status leaves the state log unchanged in length" "$BEFORE" "$AFTER"
if cmp -s "$T/log-before" "$LOG"; then pass "status leaves the state log byte-identical"; else fail "status changed the state log"; fi
run status nobody-t1
assert_eq "status of a session that doesn't exist: absent" "absent" "$STDOUT"
assert_eq "absent exits 0" "0" "$RC"

# --- close ---

run close brief-t1 done
assert_eq "close of a live session exits 0" "0" "$RC"
assert_eq "close prints closed=done" "closed=done" "$(line 1)"
RET=$(line 2 | sed 's/^retention=//')
assert_eq "the close tick kept the session (retention.retained)" "true" "$(printf '%s' "$RET" | jq -r '.retained')"
assert_eq "the close tick kept it for --no-cleanup" "no_cleanup" "$(printf '%s' "$RET" | jq -r '.reason')"
run status brief-t1
assert_eq "a closed session is finished" "finished" "$STDOUT"
assert_eq "a closed session stays readable" "kept" "$(kget brief-t1 work/context.md)"
run close brief-t1 abandoned
assert_eq "close of a finished session is a no-op" "closed=noop" "$(line 1)"
assert_eq "it reports the session finished" "status=finished" "$(line 2)"
assert_eq "the finished session keeps its terminal" "done" "$(k status brief-t1 | jq -r '.current_state')"
run close nobody-t1 done
assert_eq "close of an absent session is a no-op" "closed=noop" "$(line 1)"
assert_eq "close of an absent session exits 0" "0" "$RC"

run open strategy ab
run close strategy-ab abandoned
assert_eq "close abandoned reaches the abandoned terminal" "abandoned" "$(k status strategy-ab | jq -r '.current_state')"

run open brief t1
assert_eq "open on a finished session: opened=replaced" "opened=replaced" "$(line 2)"
assert_contains "the replaced state is reported" "replaced_state=done" "$STDOUT"
if khas brief-t1 work/context.md; then fail "the replaced session kept an old key"; else pass "a replaced session's old keys are gone"; fi
assert_eq "the replacement records its branch" "main" "$(kget brief-t1 session/branch)"

# --- open: a finished session its hierarchy holds (koto 0.23.0 and later) ---

if PATH="$TOOLS:$SYS_PATH" KOTO_BIN="$REAL_KOTO" KOTO_FLOOR=0.23.0 "$BASH_BIN" "$SCRIPT_DIR/assert-koto-floor.sh" >/dev/null 2>&1; then
    k init hold-peer --template "$TEMPLATE" >/dev/null 2>&1
    run open brief h1
    kadd brief-h1 work/context.md "first run"
    k session link brief-h1 --dispatched-by hold-peer >/dev/null 2>&1
    run close brief-h1 done
    run open brief h1
    assert_eq "open on a held finished session exits 0" "0" "$RC"
    assert_eq "a held finished session: opened=replaced" "opened=replaced" "$(line 2)"
    assert_contains "open passes moved_to through" "moved_to=brief-h1_r1" "$STDOUT"
    assert_contains "open passes moved_reason through" "moved_reason=" "$STDOUT"
    assert_eq "the moved run keeps its record under its new name" "first run" "$(kget brief-h1_r1 work/context.md)"
    assert_eq "the fresh session records its branch" "main" "$(kget brief-h1 session/branch)"

    run open brief h2
    k session link brief-h2 --dispatched-by hold-peer >/dev/null 2>&1
    k init brief-h2.k --template "$TEMPLATE" --parent brief-h2 >/dev/null 2>&1
    run close brief-h2 done
    run open brief h2
    assert_eq "a held session with live work below it: koto-open's exit 75 passes through" "75" "$RC"
    assert_contains "it prints refused=replace_held_live" "refused=replace_held_live" "$STDOUT"
    assert_contains "it prints the live sessions" 'live=["brief-h2.k"]' "$STDOUT"
    assert_eq "the refused open leaves the finished session as it was" "done" "$(k status brief-h2 | jq -r '.current_state')"
else
    echo "SKIP: this koto predates hierarchy retention (0.23.0) -- the held-predecessor open cases did not run"
fi

# --- open: refusals ---

mkdir -p "$T/other-tpl"
cp "$TEMPLATE" "$T/other-tpl/another-store.md"
k init prd-t9 --template "$T/other-tpl/another-store.md" >/dev/null 2>&1
run open prd t9
assert_eq "open of a session from another template is refused (exit 2)" "2" "$RC"
assert_contains "it prints koto-open's refused=template_mismatch" "refused=template_mismatch" "$STDOUT"

run open plan t8
kadd plan-t8 work/analysis.md "x"
git -C "$REPO" checkout -q -b feature
run open plan t8
assert_eq "open of a session from another branch is refused (exit 5)" "5" "$RC"
assert_contains "it prints refused=branch_mismatch" "refused=branch_mismatch" "$STDOUT"
assert_eq "the refused session is left as it was" "main" "$(kget plan-t8 session/branch)"
RC=0; run has-work plan t8
assert_eq "has-work is false for a session of another branch" "1" "$RC"
git -C "$REPO" checkout -q main
RC=0; run has-work plan t8
assert_eq "has-work is true back on the session's branch" "0" "$RC"

git -C "$REPO" checkout -q --detach
run open brief t7
assert_eq "open on a detached HEAD is refused (exit 6)" "6" "$RC"
assert_contains "it prints refused=no_branch" "refused=no_branch" "$STDOUT"
git -C "$REPO" checkout -q main
run status brief-t7
assert_eq "a refused open creates no session" "absent" "$STDOUT"

RC=0
(cd "$REPO" && KOTO_FLOOR=99.0.0 PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" open roadmap fl) >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "open with the real koto below the floor exits 69" "69" "$RC"
assert_contains "its message names koto" "koto" "$(cat "$T/stderr")"
run status roadmap-fl
assert_eq "below the floor, no session is created" "absent" "$STDOUT"
assert_no_staging "koto below the floor: no file is created under the staging folder"

# --- has-work ---

run open design t6
RC=0; run has-work design t6
assert_eq "has-work is false for a live session with no work/ key" "1" "$RC"
kadd design-t6 research/phase5_x.md "r"
RC=0; run has-work design t6
assert_eq "has-work is false with only a research/ key" "1" "$RC"
kadd design-t6 work/summary.md "s"
RC=0; run has-work design t6
assert_eq "has-work is true with a work/ key" "0" "$RC"
RC=0; run has-work design nope
assert_eq "has-work is false for an absent session" "1" "$RC"
run close design-t6 done
RC=0; run has-work design t6
assert_eq "has-work is false for a finished session" "1" "$RC"

# /charter's ladder rows 7-8 ride on this check: a mid-flight child is a live
# session with a work/ key, with nothing in the staging folder to glob.
run open strategy t6
kadd strategy-t6 work/discover.md "d"
assert_no_staging "a mid-flight strategy child leaves the staging folder empty"
RC=0; run has-work strategy t6
assert_eq "an empty staging folder with a live strategy session holding work/ is mid-flight" "0" "$RC"
run close strategy-t6 done
RC=0; run has-work strategy t6
assert_eq "the same strategy session finished is not mid-flight" "1" "$RC"

# --- the dispatch key ---

run open scope t5
run dispatch write scope t5 design fresh-chain
assert_eq "dispatch write exits 0" "0" "$RC"
assert_eq "dispatch write prints the child" "dispatched=design" "$STDOUT"
assert_eq "the dispatch value is exactly three lines" \
    "child: design
suppress_status_aware_prompt: true
rationale: fresh-chain" "$(kget scope-t5 chain/dispatch)"
run dispatch read design t5
assert_eq "dispatch read round-trips the three fields" \
    "parent=scope-t5
child=design
suppress_status_aware_prompt=true
rationale=fresh-chain" "$STDOUT"
run dispatch write scope t5 design revise --no-suppress
run dispatch read design t5
assert_contains "--no-suppress round-trips as false" "suppress_status_aware_prompt=false" "$STDOUT"
assert_contains "revise round-trips" "rationale=revise" "$STDOUT"
run dispatch clear scope t5
assert_eq "dispatch clear prints the parent session" "cleared=scope-t5" "$STDOUT"
if khas scope-t5 chain/dispatch; then fail "chain/dispatch survived a clear"; else pass "chain/dispatch is gone after clear"; fi
run dispatch clear scope t5
assert_eq "dispatch clear is idempotent" "0" "$RC"
run dispatch read design t5
assert_eq "dispatch read after a clear: no output" "" "$STDOUT"
assert_eq "dispatch read after a clear exits 0" "0" "$RC"
run dispatch write scope nope design fresh-chain
assert_eq "dispatch write into an absent parent session is refused" "2" "$RC"

# A parent opened from its own template has no session/branch until dispatch
# write gives it one.
k init scope-t10 --template "$T/other-tpl/another-store.md" >/dev/null 2>&1
run dispatch write scope t10 brief fresh-chain
assert_eq "dispatch write into a parent with no branch key succeeds" "0" "$RC"
assert_eq "it records the parent's branch" "main" "$(kget scope-t10 session/branch)"

# --- open --dispatched-by ---

run open prd dx --dispatched-by deliver-dx
assert_eq "open --dispatched-by exits 0" "0" "$RC"
assert_eq "open --dispatched-by prints the open's lines and nothing else" "session=prd-dx
opened=new" "$STDOUT"
if khas prd-dx koto/links/dispatched-by/deliver-dx; then
    pass "open --dispatched-by records the link in the opened session (the dispatcher need not exist)"
else
    fail "open --dispatched-by left no koto/links/dispatched-by/deliver-dx in prd-dx"
fi
run open prd dx --dispatched-by deliver-dx
assert_eq "an attach with the same dispatcher exits 0 with no warning" "session=prd-dx
opened=attached" "$STDOUT"
run open prd dy
if k context list prd-dy 2>/dev/null | jq -e 'any(.[]; startswith("koto/links/dispatched-by/"))' >/dev/null 2>&1; then
    fail "open without --dispatched-by wrote a dispatched-by link"
else
    pass "open without --dispatched-by writes no link"
fi
run close prd-dx done
run close prd-dy done

# --- the parent-and-child case ---

run open scope pc
assert_eq "the parent opens" "opened=new" "$(line 2)"
# A key a crashed earlier run left; the parent removes it at start.
kadd scope-pc chain/dispatch "child: brief
suppress_status_aware_prompt: true
rationale: fresh-chain
"
run dispatch clear scope pc
if khas scope-pc chain/dispatch; then fail "the stale dispatch key survived the parent's start"; else pass "a stale dispatch key is removed at parent start"; fi

run dispatch write scope pc design fresh-chain
run open design pc
assert_eq "the child opens its own root session" "opened=new" "$(line 2)"
run dispatch read design pc
assert_eq "the child's dispatch read finds scope-<topic> by name" "parent=scope-pc" "$(line 1)"
run adopt design pc
assert_eq "adopt reports the parent" "adopted=scope-pc" "$STDOUT"
assert_eq "adopt writes chain/parent" "scope-pc" "$(kget design-pc chain/parent)"
if khas design-pc koto/links/dispatched-by/scope-pc; then
    pass "adopt records the dispatched-by link in the child's own session"
else
    fail "adopt left no koto/links/dispatched-by/scope-pc in design-pc"
fi
if khas scope-pc koto/links/dispatched-by/design-pc; then fail "adopt wrote a link into the parent"; else pass "adopt writes no link into the parent"; fi
if khas design-pc session/link-warning; then fail "a link that worked left a warning key"; else pass "a link that worked records no warning key"; fi
assert_eq "koto session hierarchy joins the child to its parent" "true" \
    "$(k session hierarchy design-pc --json 2>/dev/null | jq '[.members[]?.name] | index("scope-pc") != null' 2>/dev/null)"
run adopt design pc
assert_eq "adopting again links again without a warning" "adopted=scope-pc" "$STDOUT"

CHILD_SCR=$(PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" scratch)
printf 'the summary\n' >"$CHILD_SCR/summary.md"
printf '{"a":1}\n' >"$CHILD_SCR/coordination.json"
run ingest design-pc work "$CHILD_SCR"
assert_eq "the child writes its work/ keys" "0" "$RC"
assert_eq "the parent reads the child's key from its session by name" "the summary" "$(kget design-pc work/summary.md)"
RC=0; run has-work design pc
assert_eq "the parent sees a mid-flight child through has-work" "0" "$RC"
run dispatch clear scope pc

# Siblings close-children must leave alone.
run open prd pc
run adopt prd pc
assert_eq "a direct run with no dispatch adopts nothing" "adopted=none" "$STDOUT"
kadd prd-pc chain/parent "scope-pc"
run adopt prd pc
if khas prd-pc chain/parent; then fail "adopt with no match left a chain/parent behind"; else pass "adopt with no match removes an earlier chain/parent"; fi
run open brief pc
kadd brief-pc chain/parent "charter-pc"
run open plan pc
kadd plan-pc chain/parent "scope-pc"
kadd plan-pc session/branch "elsewhere"

run status design-pc
assert_eq "the child is still live before the parent writes its exit" "live" "$STDOUT"
kadd scope-pc work/state.md "exit: done"
run close-children scope pc done
assert_eq "close-children exits 0" "0" "$RC"
assert_contains "close-children closes the dispatched child" "closed=design-pc" "$STDOUT"
assert_contains "a child with no chain/parent is skipped" "skipped=prd-pc reason=no-parent" "$STDOUT"
assert_contains "a child of another parent is skipped" "skipped=brief-pc reason=other-parent" "$STDOUT"
assert_contains "a child of another branch is skipped" "skipped=plan-pc reason=other-branch" "$STDOUT"
run status design-pc
assert_eq "the closed child is finished" "finished" "$STDOUT"
assert_eq "the closed child stays readable" "the summary" "$(kget design-pc work/summary.md)"
for s in prd-pc brief-pc plan-pc; do
    run status "$s"
    assert_eq "$s is still live" "live" "$STDOUT"
done
run close-children scope pc done
assert_contains "close-children again: the finished child is skipped" "skipped=design-pc reason=finished" "$STDOUT"
run close scope-pc done
assert_eq "the parent closes itself last" "closed=done" "$(line 1)"

# --- no match, two matches ---

run open scope t4
run dispatch write scope t4 brief fresh-chain
run dispatch read prd t4
assert_eq "a key naming another child is no match" "" "$STDOUT"
assert_eq "no match exits 0" "0" "$RC"

forge() { kadd "$1" chain/dispatch "$2"; run dispatch read design t4; }
forge scope-t4 "child: design
suppress_status_aware_prompt: true
rationale: fresh-chain
extra: line
"
assert_eq "a value with a fourth line is no match" "" "$STDOUT"
forge scope-t4 "child: design
suppress_status_aware_prompt: maybe
rationale: fresh-chain
"
assert_eq "a suppress value outside true|false is no match" "" "$STDOUT"
forge scope-t4 "child: design
suppress_status_aware_prompt: true
rationale: \$(touch pwned)
"
assert_eq "a rationale outside the closed set is no match" "" "$STDOUT"
assert_gone "a hostile value is never run" "$REPO/pwned"
forge scope-t4 "child: design
suppress_status_aware_prompt: true
rationale: fresh-chain"
assert_eq "a value without its final newline is no match" "" "$STDOUT"
forge scope-t4 "child: design
suppress_status_aware_prompt: true
rationale: fresh-chain
"
assert_eq "a well-formed value matches" "parent=scope-t4" "$(line 1)"
kadd scope-t4 session/branch "elsewhere"
run dispatch read design t4
assert_eq "a parent session of another branch is no match" "" "$STDOUT"
kadd scope-t4 session/branch "main"
run close scope-t4 done
run dispatch read design t4
assert_eq "a finished parent session is no match" "" "$STDOUT"

run open scope t3
run open charter t3
run dispatch write scope t3 design fresh-chain
kadd charter-t3 chain/dispatch "child: design
suppress_status_aware_prompt: true
rationale: revise
"
run dispatch read design t3
assert_eq "two matching parents exit 3" "3" "$RC"
assert_eq "two matches print nothing on stdout" "" "$STDOUT"
assert_contains "the error names scope-<topic>" "scope-t3" "$STDERR"
assert_contains "the error names charter-<topic>" "charter-t3" "$STDERR"
run open design t3
run adopt design t3
assert_eq "adopt on two matches exits 3" "3" "$RC"
if khas design-t3 chain/parent; then fail "adopt wrote chain/parent on two matches"; else pass "adopt on two matches writes nothing"; fi

# --- scratch and ingest ---

run scratch
SCR1="$STDOUT"
assert_eq "scratch exits 0" "0" "$RC"
if [ -d "$SCR1" ] && [ "$(ls -A "$SCR1")" = "" ]; then pass "scratch makes an empty directory"; else fail "scratch: [$SCR1]"; fi
MODE=$(stat -c '%a' "$SCR1" 2>/dev/null || stat -f '%Lp' "$SCR1")
assert_eq "the scratch directory is private (0700)" "700" "$MODE"
case "$SCR1" in
    "$REPO"/*) fail "the scratch directory lies in the work tree" ;;
    *) pass "the scratch directory lies outside the work tree" ;;
esac

run open brief t2
printf 'alpha' >"$SCR1/phase4_a.md"
printf 'beta' >"$SCR1/phase4_b.md"
printf 'secret' >"$T/host-file"
ln -s "$T/host-file" "$SCR1/linked.md"
printf 'x' >"$SCR1/bad name.md"
printf 'x' >"$SCR1/.hidden"
head -c 1048576 /dev/zero >"$SCR1/big.md"
mkdir "$SCR1/subdir"
run ingest brief-t2 research "$SCR1"
assert_eq "ingest exits 0 when every add succeeds" "0" "$RC"
assert_contains "ingest reports each key" "added=research/phase4_a.md" "$STDOUT"
assert_eq "a plain file becomes a key, byte for byte" "alpha" "$(kget brief-t2 research/phase4_a.md)"
assert_eq "a second file becomes a key" "beta" "$(kget brief-t2 research/phase4_b.md)"
if khas brief-t2 research/linked.md; then fail "ingest followed a symlink"; else pass "ingest skips a symlink"; fi
assert_contains "the symlink skip is reported" "linked.md" "$STDERR"
assert_contains "the bad name is reported" "bad name.md" "$STDERR"
assert_contains "the hidden name is reported" ".hidden" "$STDERR"
if khas brief-t2 research/big.md; then fail "ingest took a 1 MiB file"; else pass "ingest skips a file of 1 MiB"; fi
assert_contains "the oversize skip is reported" "big.md" "$STDERR"
assert_contains "the non-regular entry is reported" "subdir" "$STDERR"
KEYS=$(k context list brief-t2 | jq -r '.[]' | grep '^research/' | tr '\n' ' ')
assert_eq "only the two plain files became keys" "research/phase4_a.md research/phase4_b.md " "$KEYS"
assert_gone "ingest removes its directory on success" "$SCR1"

# A failed key write: a koto wrapper refuses one key and passes the rest on.
WRAP="$T/wrapbin"
mkdir -p "$WRAP"
cat >"$WRAP/koto" <<'WRAPPER'
#!/bin/bash
if [ "${1:-}" = "context" ] && [ "${2:-}" = "add" ]; then
    case "${4:-}" in
        */fail.md) printf '{"error":"refused by the test wrapper"}\n'; exit 3 ;;
        */slow.md) sleep 3 ;;
    esac
fi
exec "$WRAP_REAL" "$@"
WRAPPER
chmod +x "$WRAP/koto"
SCR2=$(PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" scratch)
printf 'ok' >"$SCR2/ok.md"
printf 'no' >"$SCR2/fail.md"
RC=0
(cd "$REPO" && WRAP_REAL="$REAL_KOTO" KOTO_BIN="$WRAP/koto" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" ingest brief-t2 work "$SCR2") \
    >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "ingest exits 1 when a key write fails" "1" "$RC"
assert_contains "the failed key is reported" "fail.md" "$(cat "$T/stderr")"
assert_gone "ingest removes its directory on a failed key write" "$SCR2"

SCR3=$(PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" scratch)
printf 'x' >"$SCR3/a.md"
run ingest nobody-t2 work "$SCR3"
assert_eq "ingest into an absent session is refused (exit 2)" "2" "$RC"
assert_gone "ingest removes its directory when the session is refused" "$SCR3"

SCR4=$(PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" scratch)
printf 'x' >"$SCR4/a.md"
run ingest brief-t2 legs "$SCR4"
assert_eq "ingest into a reserved area is a usage error" "64" "$RC"
assert_gone "ingest removes its directory on a usage error" "$SCR4"

# A sub-area: a skill run inside another skill's session (/decision under
# /design) ingests below work/<sub-area>.
SCR4B=$(PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" scratch)
printf 'ctx' >"$SCR4B/context.md"
run ingest brief-t2 work/decision-1 "$SCR4B"
assert_eq "ingest into a work/ sub-area exits 0" "0" "$RC"
assert_contains "the sub-area key is reported" "added=work/decision-1/context.md" "$STDOUT"
assert_eq "the file lands below the sub-area" "ctx" "$(kget brief-t2 work/decision-1/context.md)"
assert_gone "ingest removes its directory after a sub-area ingest" "$SCR4B"
for bad in "work/../chain" "work/" "work/.x" "chain/x" "handoff/x" "work/a b"; do
    SCR4C=$(PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" scratch)
    printf 'x' >"$SCR4C/a.md"
    run ingest brief-t2 "$bad" "$SCR4C"
    assert_eq "ingest refuses area '$bad' as a usage error" "64" "$RC"
    assert_gone "ingest removes its directory after refusing area '$bad'" "$SCR4C"
done

private_dir "$REPO/tree-scratch"
printf 'x' >"$REPO/tree-scratch/a.md"
run ingest brief-t2 work "$REPO/tree-scratch"
assert_eq "ingest of a directory in the work tree is refused (exit 2)" "2" "$RC"
if [ -f "$REPO/tree-scratch/a.md" ]; then pass "a refused directory is never removed"; else fail "ingest removed a directory it refused"; fi
rm -rf "$REPO/tree-scratch"

# A signal mid-ingest: the directory still goes.
SCR5=$(PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" scratch)
printf 'x' >"$SCR5/slow.md"
(cd "$REPO" && WRAP_REAL="$REAL_KOTO" KOTO_BIN="$WRAP/koto" PATH="$TOOLS:$SYS_PATH" exec "$BASH_BIN" "$SS" ingest brief-t2 work "$SCR5") \
    >"$T/stdout" 2>"$T/stderr" &
IPID=$!
sleep 1
kill -TERM "$IPID" 2>/dev/null
RC=0
wait "$IPID" || RC=$?
assert_eq "ingest interrupted by SIGTERM exits 143" "143" "$RC"
assert_gone "ingest removes its directory on a signal" "$SCR5"

# --- get and put ---

SCR6=$(PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" scratch)
printf 'line one\nline two\n' >"$SCR6/decisions.md"
run put brief-t2 work/decisions.md "$SCR6/decisions.md"
assert_eq "put exits 0" "0" "$RC"
assert_eq "put prints the key" "put=work/decisions.md" "$STDOUT"
SCR7=$(PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" scratch)
run get brief-t2 work/decisions.md "$SCR7"
assert_eq "get prints the written path" "$SCR7/decisions.md" "$STDOUT"
if cmp -s "$SCR6/decisions.md" "$SCR7/decisions.md"; then pass "get and put round-trip the bytes"; else fail "get returned other bytes than put stored"; fi
run get brief-t2 research/phase4_a.md "$SCR7"
assert_eq "get reads a research/ key" "alpha" "$(cat "$SCR7/phase4_a.md")"
# Two keys sharing a last component land apart: the path below the area is
# kept, and the directory get creates passes put's scratch checks.
printf 'nested\n' >"$SCR6/context.md"
run put brief-t2 work/decision-1/context.md "$SCR6/context.md"
assert_eq "put writes a nested work/ key" "0" "$RC"
printf 'flat\n' >"$SCR6/context.md"
run put brief-t2 work/context.md "$SCR6/context.md"
run get brief-t2 work/context.md "$SCR7"
assert_eq "get of a top-level key writes below the directory" "$SCR7/context.md" "$STDOUT"
run get brief-t2 work/decision-1/context.md "$SCR7"
assert_eq "get of a nested key keeps the path below the area" "$SCR7/decision-1/context.md" "$STDOUT"
assert_eq "the nested key's bytes" "nested" "$(cat "$SCR7/decision-1/context.md")"
assert_eq "the top-level key is not overwritten by the nested one" "flat" "$(cat "$SCR7/context.md")"
MODE=$(stat -c '%a' "$SCR7/decision-1" 2>/dev/null || stat -f '%Lp' "$SCR7/decision-1")
assert_eq "the directory get creates is private (0700)" "700" "$MODE"
printf 'edited\n' >"$SCR7/decision-1/context.md"
run put brief-t2 work/decision-1/context.md "$SCR7/decision-1/context.md"
assert_eq "put takes a file from the directory get created" "0" "$RC"
assert_eq "the edit round-trips into the nested key" "edited" "$(kget brief-t2 work/decision-1/context.md)"
printf 'x' >"$SCR7/blocker"
run get brief-t2 work/blocker/x.md "$SCR7"
assert_eq "get refuses an intermediate that exists as a file" "2" "$RC"
ln -s "$T" "$SCR7/linkdir"
run get brief-t2 work/linkdir/x.md "$SCR7"
assert_eq "get refuses an intermediate that is a symlink" "2" "$RC"
run get brief-t2 work/missing.md "$SCR7"
assert_eq "get of a missing key is refused" "2" "$RC"
run get brief-t2 work/../session/branch "$SCR7"
assert_eq "get refuses '..' against a real session too" "2" "$RC"
run put brief-t2 chain/parent "$SCR6/decisions.md"
assert_eq "put refuses a chain/ key against a real session too" "2" "$RC"
if khas brief-t2 chain/parent; then fail "a refused put wrote a key"; else pass "a refused put writes nothing"; fi
run get brief-t1 session/branch "$SCR7"
assert_eq "get refuses the session/ area" "2" "$RC"
run close brief-t2 done
run get brief-t2 work/decisions.md "$SCR7"
assert_eq "get reads a finished session" "0" "$RC"
run put brief-t2 work/decisions.md "$SCR6/decisions.md"
assert_eq "put into a finished session is refused" "2" "$RC"
rm -rf "$SCR6" "$SCR7"

# --- close refuses a session from another template ---

cat >"$T/other-tpl/two-step.md" <<'TPL'
---
name: two-step
version: "1.0"
description: A template that is not the store template.
initial_state: work
states:
  work:
    accepts:
      status:
        type: enum
        values: [ok]
        required: true
    transitions:
      - target: fin
        when:
          status: ok
  fin:
    terminal: true
---

## work

Submit status ok.

## fin

Done.
TPL
k init plan-t11 --template "$T/other-tpl/two-step.md" >/dev/null 2>&1
run close plan-t11 done
assert_eq "close refuses a live session from another template (exit 2)" "2" "$RC"
assert_contains "it prints refused=not_store_session" "refused=not_store_session" "$STDOUT"
assert_eq "that session is left where it was" "work" "$(k status plan-t11 | jq -r '.current_state')"

# --- import against real koto ---
#
# The local backend has no bucket, so koto refuses every import with its own
# import_requires_cloud; the subcommand reports that as a failed name and stops.
run import tactical real --from /src/ws
assert_eq "import against real koto on the local backend exits 1" "1" "$RC"
assert_eq "it reports koto's own refusal" "failed=scope-real code=import_requires_cloud" "$STDOUT"

# The opt-in case against a real bucket: set SKILL_SESSION_IMPORT_FROM to a
# source workspace path, and SKILL_SESSION_IMPORT_SET and
# SKILL_SESSION_IMPORT_TOPIC to a set and topic with sessions there, with
# koto's cloud backend configured in your own HOME. It imports into this
# suite's private store and marks the source sessions migrated, which can't be
# undone: point it at a source made for the purpose.
if [ -n "${SKILL_SESSION_IMPORT_FROM:-}" ]; then
    RC=0
    (cd "$REPO" && HOME="$ORIG_HOME" PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$SS" import \
        "${SKILL_SESSION_IMPORT_SET:-tactical}" "${SKILL_SESSION_IMPORT_TOPIC:-}" --from "$SKILL_SESSION_IMPORT_FROM") \
        >"$T/stdout" 2>"$T/stderr" || RC=$?
    assert_eq "import from a real bucket exits 0" "0" "$RC"
    assert_contains "and imports at least one session" "imported=" "$(cat "$T/stdout")"
else
    echo "SKIP: SKILL_SESSION_IMPORT_FROM not set -- the real-bucket import case did not run"
fi

assert_no_staging "the whole engine run wrote nothing under the staging folder"

echo
echo "skill-session_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
