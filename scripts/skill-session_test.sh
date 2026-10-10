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
#   no eval, no --parent, and --no-cleanup on every koto next.
#
#   engine-backed cases, which drive the real koto in a store isolated by
#   KOTO_SESSIONS_BASE (and a private HOME), from a throwaway git repository:
#   every subcommand, the parent-and-child case, and the read-only status. They
#   skip with a message when koto is absent, like the other engine-backed
#   suites; the CI job that runs this asserts koto is present first, so a skip
#   there cannot pass as green.
#
# Everything the suite creates lives under one mktemp -d directory, removed on
# exit; no session outside its own store is touched.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

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

T=$(mktemp -d "${TMPDIR:-/tmp}/skill-session-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
cleanup() { [ -n "${T:-}" ] && chmod -R u+rwx "$T" 2>/dev/null; [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

# A private HOME (koto's template cache lands there) and a private session
# store: nothing here reaches the developer's own sessions.
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
if printf '%s\n' "$CODE" | grep -qE '(^|[^A-Za-z_])eval([^A-Za-z_]|$)'; then
    fail "skill-session.sh contains eval"
else
    pass "skill-session.sh contains no eval"
fi
if printf '%s\n' "$CODE" | grep -q -- '--parent'; then
    fail "skill-session.sh passes --parent somewhere"
else
    pass "skill-session.sh never passes --parent"
fi
NEXT_LINES=$(printf '%s\n' "$CODE" | grep -E '(koto|"\$KOTO") next ')
if [ -z "$NEXT_LINES" ]; then
    fail "found no koto next call in skill-session.sh to check"
elif printf '%s\n' "$NEXT_LINES" | grep -qv -- '--no-cleanup'; then
    fail "a koto next call in skill-session.sh lacks --no-cleanup: $(printf '%s\n' "$NEXT_LINES" | grep -v -- '--no-cleanup')"
else
    pass "every koto next call in skill-session.sh carries --no-cleanup ($(printf '%s\n' "$NEXT_LINES" | wc -l | tr -d ' ') call site)"
fi
if printf '%s\n' "$CODE" | grep -qE 'declare -A|mapfile|readarray|local -n|declare -n'; then
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
check_refused "reclaimable of ../x" reclaimable ../x
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

# --- reclaimable ---

run open vision r1
run reclaimable vision-r1
assert_eq "a live session is not reclaimable" "no" "$STDOUT"
run close vision-r1 done
run reclaimable vision-r1
assert_eq "a finished session with no chain/parent is reclaimable" "yes" "$STDOUT"

run open scope r2
run open prd r2
kadd prd-r2 chain/parent "scope-r2"
run close prd-r2 done
run reclaimable prd-r2
assert_eq "a finished child whose parent is live is not reclaimable" "no" "$STDOUT"
run close scope-r2 done
run reclaimable prd-r2
assert_eq "a finished child whose parent is finished is reclaimable" "yes" "$STDOUT"

run open roadmap r2
kadd roadmap-r2 chain/parent "charter-r2"
run close roadmap-r2 done
run reclaimable roadmap-r2
assert_eq "a finished child whose parent is absent is reclaimable" "yes" "$STDOUT"

run open strategy r3
kadd strategy-r3 chain/parent "scope-other"
run close strategy-r3 done
run reclaimable strategy-r3
assert_eq "a chain/parent naming another topic is malformed: not reclaimable" "no" "$STDOUT"
kadd strategy-r3 chain/parent "../x"
run reclaimable strategy-r3
assert_eq "a chain/parent outside the grammar is malformed: not reclaimable" "no" "$STDOUT"
kadd strategy-r3 chain/parent "scope-r3
"
run reclaimable strategy-r3
assert_eq "a chain/parent with a trailing newline is malformed: not reclaimable" "no" "$STDOUT"

run open review-plan r4
run close review-plan-r4 done
run reclaimable review-plan-r4
assert_eq "a hyphenated skill's topic is derived longest first" "yes" "$STDOUT"
run reclaimable nobody-r1
assert_eq "an absent session is not reclaimable" "no" "$STDOUT"
k init unknown-r5 --template "$TEMPLATE" >/dev/null 2>&1
k next unknown-r5 --no-cleanup --with-data '{"close":"done"}' >/dev/null 2>&1
run reclaimable unknown-r5
assert_eq "a session of a skill the convention doesn't know is not reclaimable" "no" "$STDOUT"

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

assert_no_staging "the whole engine run wrote nothing under the staging folder"

echo
echo "skill-session_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
