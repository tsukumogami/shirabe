#!/usr/bin/env bash
# koto-open_test.sh -- test harness for scripts/koto-open.sh, the shared koto
# entry every koto-backed skill in the tactical chain goes through.
#
# Usage: bash scripts/koto-open_test.sh
#        /bin/bash scripts/koto-open_test.sh     # the bash 3.2 floor
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the engine-backed cases skipped
#   1 -- one or more cases failed
#
# Two groups, in execution order:
#
#   stand-in cases, which need jq and git but no koto. A stub koto records its
#   argv and a byte copy of the vars file it was handed, and can be told to
#   print a canned response, crash, or hang. These pin what the script does
#   around the one koto call: argument checking, the location rule, removal on
#   every exit path (signals included), what reaches koto, and rendering.
#
#   engine-backed cases, which drive the real koto: the four outcomes and each
#   refusal kind, the request leg recording a refusal, and a no-origin-record
#   session. They skip with a message when koto is absent, like the other
#   engine-backed suites; the CI job that runs this asserts koto is present
#   first, so a skip there cannot pass as green.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
OPEN="$SCRIPT_DIR/koto-open.sh"
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { printf "${GREEN}PASS${NC}: %s\n" "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf "${RED}FAIL${NC}: %s\n" "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$OPEN" ] || { echo "FAIL: koto-open.sh not found at $OPEN" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || {
    echo "SKIP: jq not on PATH -- koto-open.sh needs it, no case ran"
    exit 0
}
command -v git >/dev/null 2>&1 || {
    echo "SKIP: git not on PATH -- the location cases need it, no case ran"
    exit 0
}

# The system tools the stub and the script need, without the developer's koto.
# PATH for stand-in runs is this directory plus the system dirs, so a koto on
# the developer's PATH can never answer a stand-in case.
REAL_JQ=$(command -v jq)
REAL_GIT=$(command -v git)

T=$(mktemp -d "${TMPDIR:-/tmp}/koto-open-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

export HOME="$T/home"
mkdir -p "$HOME"

TOOLS="$T/tools"
mkdir -p "$TOOLS"
ln -s "$REAL_JQ" "$TOOLS/jq"
ln -s "$REAL_GIT" "$TOOLS/git"

# The work tree the location rule is measured against, and the directory every
# run starts in.
REPO="$T/repo"
mkdir -p "$REPO/sub"
git -C "$REPO" init -q
printf 'tracked\n' >"$REPO/tracked.json"
git -C "$REPO" add tracked.json
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -q -m init

OUTSIDE="$T/outside"
mkdir -p "$OUTSIDE"

# --- the stand-in koto -------------------------------------------------------
#
# STUB_MODE: ok (default, prints a created outcome), canned (prints
# $STUB_RESPONSE, exits $STUB_RC), crash (kills itself with SIGSEGV), hang
# (records its pid and sleeps).
STUB_DIR="$T/stubbin"
mkdir -p "$STUB_DIR"
STUB_LOG="$T/stub-argv"
STUB_VARS="$T/stub-vars"
cat >"$STUB_DIR/koto" <<'STUB'
#!/bin/bash
: >"$STUB_LOG"
for a in "$@"; do printf '%s\n' "$a" >>"$STUB_LOG"; done
prev=""
for a in "$@"; do
    if [ "$prev" = "--vars-file" ]; then cat "$a" >"$STUB_VARS" 2>/dev/null; fi
    prev="$a"
done
case "${STUB_MODE:-ok}" in
    ok) printf '{"name":"x","outcome":"created","state":"work"}\n' ;;
    canned) printf '%s\n' "$STUB_RESPONSE"; exit "${STUB_RC:-0}" ;;
    crash) kill -SEGV $$ ;;
    hang) printf '%s\n' "$$" >"$STUB_LOG.pid"; exec sleep 30 ;;
esac
STUB
chmod +x "$STUB_DIR/koto"
export STUB_LOG STUB_VARS

SYS_PATH="/usr/bin:/bin"

RC=0
STDOUT=""
STDERR=""

# run_stub <args...> -- run koto-open.sh from $REPO against the stand-in.
run_stub() {
    rm -f "$STUB_LOG" "$STUB_VARS"
    RC=0
    (cd "$REPO" && PATH="$STUB_DIR:$TOOLS:$SYS_PATH" "$BASH_BIN" "$OPEN" "$@") \
        >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}

assert_eq() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected [$2], got [$3]"; fi
}

assert_gone() {
    if [ -e "$2" ] || [ -L "$2" ]; then fail "$1: $2 still exists"; else pass "$1"; fi
}

assert_contains() {
    case "$3" in
        *"$2"*) pass "$1" ;;
        *) fail "$1: expected to contain [$2], got [$3]" ;;
    esac
}

stub_called() { [ -f "$STUB_LOG" ]; }

# new_args <dir> <jq-program> [--arg ...] -- write an args file with jq, the way
# a thin wrapper builds one. Prints its path.
N=0
new_args() {
    local dir="$1" prog="$2"
    shift 2
    N=$((N + 1))
    mkdir -p "$dir"
    jq -n -c "$@" "$prog" >"$dir/args-$N.json"
    printf '%s' "$dir/args-$N.json"
}

echo "koto-open_test.sh: running under $BASH_BIN ($("$BASH_BIN" -c 'echo $BASH_VERSION'))"
echo

# --- the script never evaluates anything --------------------------------------

if grep -v '^[[:space:]]*#' "$OPEN" | grep -qE '(^|[^A-Za-z_])eval([^A-Za-z_]|$)'; then
    fail "koto-open.sh contains eval"
else
    pass "koto-open.sh contains no eval"
fi

# --- usage errors: exit 64, no koto call, file removed -------------------------

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
run_stub s1 "$T/t.md"
assert_eq "a missing args-file argument is a usage error (exit 64)" "64" "$RC"
assert_eq "a usage error prints error=usage" "error=usage" "$STDOUT"
stub_called && fail "a usage error called koto" || pass "a usage error makes no koto call"

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
run_stub s1 "$T/t.md" "$A" --bogus
assert_eq "an unknown option is a usage error" "64" "$RC"
assert_gone "the args file is removed on a usage error" "$A"

for bad in "BAD:scope" "req-1:" ":scope" "nocolon" "-req:scope" "req-1:-leg" "req-1:le.g" "req-1:a:b"; do
    A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
    run_stub s1 "$T/t.md" "$A" --koto-leg "$bad"
    if [ "$RC" -eq 64 ] && ! stub_called && [ ! -e "$A" ]; then
        pass "a malformed --koto-leg '$bad' is a usage error with no koto call, and the file is removed"
    else
        fail "--koto-leg '$bad': rc=$RC, koto called: $(stub_called && echo yes || echo no), file left: $([ -e "$A" ] && echo yes || echo no)"
    fi
done

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
run_stub -s1 "$T/t.md" "$A"
assert_eq "a session name that reads as an option is a usage error" "64" "$RC"

# --- what reaches koto ---------------------------------------------------------

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
run_stub s1 "$T/t.md" "$A"
EXPECTED_ARGV=$(printf '%s\n' init s1 --template "$T/t.md" --vars-file "$A")
assert_eq "no entry flag given: exactly init <session> --template <path> --vars-file <file>" \
    "$EXPECTED_ARGV" "$(cat "$STUB_LOG" 2>/dev/null)"
assert_eq "a created outcome prints opened=new" "opened=new" "$STDOUT"
assert_eq "an opened session exits 0" "0" "$RC"
assert_gone "the args file is removed on success" "$A"

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
run_stub s1 "$T/t.md" "$A" --attach-live --replace-terminal --koto-leg req-abc_1:execute
EXPECTED_ARGV=$(printf '%s\n' init s1 --template "$T/t.md" --vars-file "$A" --attach-live --replace-terminal --koto-leg req-abc_1:execute)
assert_eq "each entry flag is passed through when given" "$EXPECTED_ARGV" "$(cat "$STUB_LOG" 2>/dev/null)"

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
run_stub s1 "$T/t.md" "$A" --attach-live
EXPECTED_ARGV=$(printf '%s\n' init s1 --template "$T/t.md" --vars-file "$A" --attach-live)
assert_eq "only the flags given are passed" "$EXPECTED_ARGV" "$(cat "$STUB_LOG" 2>/dev/null)"

# The transport. The value holds a command substitution, backticks, a
# semicolon, a newline, and a leading dash; the thin wrapper maps it with jq,
# and koto must be handed exactly the bytes jq wrote.
HOSTILE='-$(touch pwned) `touch pwned2`; rm -rf x
second line'
A=$(new_args "$OUTSIDE" '[["TOPIC",$v],["TOPIC",$v]]' --arg v "$HOSTILE")
cp "$A" "$T/expected-vars"
run_stub s1 "$T/t.md" "$A"
if cmp -s "$T/expected-vars" "$STUB_VARS"; then
    pass "koto receives the args file byte-for-byte, hostile value and duplicate pair included"
else
    fail "the vars file koto read differs from the one jq built"
fi
if [ -e "$REPO/pwned" ] || [ -e "$REPO/pwned2" ] || [ -e "$OUTSIDE/pwned" ]; then
    fail "a token in the args file was executed"
else
    pass "no token in the args file was executed"
fi

# --- location: never inside the work tree ---------------------------------------

A=$(new_args "$REPO/sub" '[["TOPIC","t1"]]')
run_stub s1 "$T/t.md" "$A"
assert_eq "an args file inside the work tree is refused with exit 2" "2" "$RC"
assert_eq "the refusal names the rule" "refused=args_file_in_work_tree" "$STDOUT"
stub_called && fail "the work-tree refusal called koto" || pass "the work-tree refusal makes no koto call"
assert_gone "an args file inside the work tree is removed" "$A"

ln -s "$REPO/sub" "$OUTSIDE/link-into-repo"
A=$(new_args "$REPO/sub" '[["TOPIC","t1"]]')
run_stub s1 "$T/t.md" "$OUTSIDE/link-into-repo/$(basename "$A")"
assert_eq "an args file reached through a symlinked directory is still inside the work tree" \
    "refused=args_file_in_work_tree" "$STDOUT"
stub_called && fail "the symlinked-directory case called koto" || pass "the symlinked-directory case makes no koto call"

A=$(new_args "$REPO/sub" '[["TOPIC","t1"]]')
run_stub s1 "$T/t.md" "$OUTSIDE/../repo/sub/$(basename "$A")"
assert_eq "an args file reached through a .. segment is still inside the work tree" \
    "refused=args_file_in_work_tree" "$STDOUT"

A=$(new_args "$REPO/sub" '[["TOPIC","t1"]]')
ln -s "$A" "$OUTSIDE/file-link.json"
run_stub s1 "$T/t.md" "$OUTSIDE/file-link.json"
assert_eq "an args file that is a symlink into the work tree is refused" \
    "refused=args_file_in_work_tree" "$STDOUT"

run_stub s1 "$T/t.md" "$REPO/tracked.json"
if [ -f "$REPO/tracked.json" ]; then
    pass "a file git tracks is refused but never deleted"
else
    fail "koto-open.sh deleted a tracked file passed as its args file"
fi

SESSION_DIR_LIKE="$HOME/.koto/sessions/s1"
A=$(new_args "$SESSION_DIR_LIKE" '[["TOPIC","t1"]]')
run_stub s1 "$T/t.md" "$A"
assert_eq "an args file under the koto session directory is accepted" "opened=new" "$STDOUT"
assert_gone "the args file under the session directory is removed" "$A"

ALLOC=$(cd "$REPO" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$OPEN" --alloc-dir)
MODE=$(ls -ld "$ALLOC" 2>/dev/null | cut -c1-10)
assert_eq "--alloc-dir creates a private directory (mode 0700)" "drwx------" "$MODE"
case "$ALLOC" in
    "$REPO"/*) fail "--alloc-dir allocated inside the work tree" ;;
    *) pass "--alloc-dir allocates outside the work tree" ;;
esac
A=$(new_args "$ALLOC" '[["TOPIC","t1"]]')
run_stub s1 "$T/t.md" "$A"
assert_eq "an args file in an allocated directory is accepted" "opened=new" "$STDOUT"
assert_gone "the allocated directory is removed with the args file" "$ALLOC"

# --- removal on every exit path -------------------------------------------------

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
RC=0
(cd "$REPO" && PATH="$TOOLS:$SYS_PATH" KOTO_BIN=koto "$BASH_BIN" "$OPEN" s1 "$T/t.md" "$A") >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "no koto on PATH exits 127" "127" "$RC"
assert_eq "no koto on PATH prints failed=koto_missing" "failed=koto_missing" "$(cat "$T/stdout")"
assert_gone "the args file is removed when koto is missing" "$A"

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
STUB_MODE=crash run_stub s1 "$T/t.md" "$A"
assert_eq "a crashing koto prints failed=koto_crashed" "failed=koto_crashed" "$STDOUT"
if [ "$RC" -ne 0 ] && [ "$RC" -ne 2 ]; then pass "a crashing koto exits non-zero, not as a refusal ($RC)"; else fail "a crashing koto exited $RC"; fi
assert_gone "the args file is removed when koto crashes" "$A"

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
STUB_MODE=canned STUB_RC=2 STUB_RESPONSE='{"code":"invalid_var","command":"init","error":"bad","var":"TOPIC","value":"x","constraint":"allowlist"}' \
    run_stub s1 "$T/t.md" "$A"
assert_gone "the args file is removed on a koto refusal" "$A"

# The signal paths. Job control is on so the backgrounded script keeps its
# default SIGINT disposition: a non-interactive shell starts & jobs with SIGINT
# ignored, and a signal ignored on entry cannot be trapped.
signal_case() {
    local sig="$1" want="$2" A pid i rc
    A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
    rm -f "$STUB_LOG" "$STUB_LOG.pid"
    set -m
    (cd "$REPO" && STUB_MODE=hang PATH="$STUB_DIR:$TOOLS:$SYS_PATH" exec "$BASH_BIN" "$OPEN" s1 "$T/t.md" "$A") >/dev/null 2>&1 &
    pid=$!
    set +m
    i=0
    while [ ! -s "$STUB_LOG.pid" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
    if [ ! -s "$STUB_LOG.pid" ]; then
        fail "SIG$sig: the stand-in koto never started"
        kill -KILL "$pid" 2>/dev/null
        return
    fi
    kill -"$sig" "$pid"
    rc=0
    wait "$pid" || rc=$?
    assert_eq "SIG$sig exits $want" "$want" "$rc"
    assert_gone "the args file is removed on SIG$sig" "$A"
    if kill -0 "$(cat "$STUB_LOG.pid")" 2>/dev/null; then
        fail "SIG$sig left koto running"
        kill -KILL "$(cat "$STUB_LOG.pid")" 2>/dev/null
    else
        pass "SIG$sig stops the koto call too"
    fi
}
signal_case INT 130
signal_case TERM 143

# --- rendering --------------------------------------------------------------------

printf '# a per-skill wording table\n' >"$T/wording.tsv"
printf 'invalid_var\tInvalid value "{value}" for {var}; it must satisfy {constraint}.\n' >>"$T/wording.tsv"
printf 'var_mismatch\t%s\n' 'session {session}: {var} was {recorded}, not {requested}.\nRun it again without the flag.' >>"$T/wording.tsv"
printf 'origin_mismatch\tsomeone else owns {session}.\n' >>"$T/wording.tsv"
printf 'already_exists\tA session named {session} already exists.\n' >>"$T/wording.tsv"

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
STUB_MODE=canned STUB_RC=2 STUB_RESPONSE='{"code":"var_mismatch","command":"init","error":"koto words","var":"INTENT_FLAG","recorded":"stop","requested":"continue"}' \
    run_stub s1 "$T/t.md" "$A" --wording "$T/wording.tsv"
assert_eq "a mapped refusal prints refused=<code>" "refused=var_mismatch" "$STDOUT"
assert_eq "a mapped refusal exits 2" "2" "$RC"
assert_eq "a mapped refusal renders the caller's wording byte-for-byte" \
    'session s1: INTENT_FLAG was stop, not continue.
Run it again without the flag.' "$STDERR"

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
STUB_MODE=canned STUB_RC=2 STUB_RESPONSE='{"code":"session_live","command":"init","error":"session is still running","state":"work"}' \
    run_stub s1 "$T/t.md" "$A" --wording "$T/wording.tsv"
assert_eq "an unmapped refusal prints koto's own message, never nothing" "session is still running" "$STDERR"

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
STUB_MODE=canned STUB_RC=2 STUB_RESPONSE='{"code":"invalid_var","command":"init","error":"x","var":"TOPIC","value":"{var} $(id) \\n &","constraint":"pattern:^[a-z]+$"}' \
    run_stub s1 "$T/t.md" "$A" --wording "$T/wording.tsv"
assert_eq "a value is substituted as bytes: its own placeholders, escapes, and \$(...) print literally" \
    'Invalid value "{var} $(id) \n &" for TOPIC; it must satisfy pattern:^[a-z]+$.' "$STDERR"

cp "$T/wording.tsv" "$T/wording-var.tsv"
printf 'invalid_var:INTENT_FLAG\t--intent takes continue or stop, got "{value}".\n' >>"$T/wording-var.tsv"
A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
STUB_MODE=canned STUB_RC=2 STUB_RESPONSE='{"code":"invalid_var","command":"init","error":"x","var":"INTENT_FLAG","value":"bogus","constraint":"pattern:^(continue|stop)?$"}' \
    run_stub s1 "$T/t.md" "$A" --wording "$T/wording-var.tsv"
assert_eq "a <code>:<VAR> line wins over the plain <code> line for that variable" \
    '--intent takes continue or stop, got "bogus".' "$STDERR"
A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
STUB_MODE=canned STUB_RC=2 STUB_RESPONSE='{"code":"invalid_var","command":"init","error":"x","var":"TOPIC","value":"Bad","constraint":"pattern:^[a-z]+$"}' \
    run_stub s1 "$T/t.md" "$A" --wording "$T/wording-var.tsv"
assert_eq "another variable still gets the plain <code> line" \
    'Invalid value "Bad" for TOPIC; it must satisfy pattern:^[a-z]+$.' "$STDERR"

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
STUB_MODE=canned STUB_RC=1 STUB_RESPONSE='{"command":"init","error":"workflow '"'"'s1'"'"' already exists; run `koto session cleanup s1` to reuse the name"}' \
    run_stub s1 "$T/t.md" "$A" --wording "$T/wording.tsv"
assert_eq "koto's untyped already-exists refusal is typed as already_exists" "refused=already_exists" "$STDOUT"
assert_eq "an existing session prints the caller's wording for it" "A session named s1 already exists." "$STDERR"
assert_eq "the already-exists refusal keeps koto's exit code" "1" "$RC"

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
STUB_MODE=canned STUB_RC=3 STUB_RESPONSE='{"command":"init","error":"corrupt state"}' \
    run_stub s1 "$T/t.md" "$A"
assert_eq "an untyped koto failure prints failed=koto_error" "failed=koto_error" "$STDOUT"
assert_eq "an untyped koto failure passes koto's exit code through" "3" "$RC"

# --- engine-backed ------------------------------------------------------------------

REAL_KOTO=$(command -v koto 2>/dev/null) || REAL_KOTO=""
if [ -z "$REAL_KOTO" ]; then
    echo
    echo "SKIP: koto not on PATH -- the engine-backed cases did not run"
    echo "koto-open_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
fi
if ! "$REAL_KOTO" init --help 2>/dev/null | grep -q -- '--vars-file'; then
    echo
    echo "SKIP: this koto predates --vars-file -- the engine-backed cases did not run"
    echo "koto-open_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
fi
ln -s "$REAL_KOTO" "$TOOLS/koto"
echo
echo "engine-backed cases against $("$REAL_KOTO" version 2>/dev/null | head -1)"

TPL_DIR="$T/templates"
mkdir -p "$TPL_DIR"
cat >"$TPL_DIR/open.md" <<'TPL'
---
name: koto-open-probe
version: "1.0"
description: Minimal template for koto-open.sh's engine-backed cases.
initial_state: work
variables:
  TOPIC:
    required: true
    pattern: '^[a-z0-9][a-z0-9-]*$'
  MERGE:
    default: "false"
    values: ["true", "false"]
    rebind: true
states:
  work:
    accepts:
      status:
        type: enum
        values: [ok]
        required: true
    transitions:
      - target: done
        when:
          status: ok
  done:
    terminal: true
    result:
      outcome: ok
---

## work

Submit `status: ok`.

## done

Terminal.
TPL
# The same workflow under another file name: koto compares templates by file
# name, which is how execute.md and execute-coordinated.md tell apart.
sed 's/^name: koto-open-probe$/name: koto-open-probe-other/' "$TPL_DIR/open.md" >"$TPL_DIR/other.md"
TPL="$TPL_DIR/open.md"

run_real() {
    RC=0
    (cd "$REPO" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$OPEN" "$@") >"$T/stdout" 2>"$T/stderr" || RC=$?
    STDOUT=$(cat "$T/stdout")
    STDERR=$(cat "$T/stderr")
}
first_line() { printf '%s\n' "$STDOUT" | head -1; }
state_file() { printf '%s/.koto/sessions/%s/koto-%s.state.jsonl' "$HOME" "$1" "$1"; }

# new
A=$(new_args "$OUTSIDE" '[["TOPIC","t1"],["MERGE","true"]]')
run_real e1 "$TPL" "$A" --attach-live --replace-terminal
assert_eq "no session: opened=new" "opened=new" "$STDOUT"
assert_eq "no session: exit 0" "0" "$RC"
assert_gone "the args file is gone after a real open" "$A"

# attach, with the rebind variable re-applied
A=$(new_args "$OUTSIDE" '[["TOPIC","t1"],["MERGE","false"]]')
run_real e1 "$TPL" "$A" --attach-live --replace-terminal
assert_eq "a live session with matching variables: opened=attached" "opened=attached" "$(first_line)"
assert_contains "the rebind variable is re-applied and reported" 'rebound={"MERGE":"false"}' "$STDOUT"
if grep -q '"variables_rebound"' "$(state_file e1)"; then
    pass "koto recorded the rebind in the session"
else
    fail "no variables_rebound event in the session after an attach that changed MERGE"
fi

# var_mismatch, with the session left unchanged
cp "$(state_file e1)" "$T/e1-before"
A=$(new_args "$OUTSIDE" '[["TOPIC","t2"],["MERGE","true"]]')
run_real e1 "$TPL" "$A" --attach-live --replace-terminal --wording "$T/wording.tsv"
assert_eq "a differing fixed variable: refused=var_mismatch" "refused=var_mismatch" "$STDOUT"
assert_eq "a koto refusal exits 2" "2" "$RC"
assert_eq "the refusal renders in the caller's wording" \
    'session e1: TOPIC was t1, not t2.
Run it again without the flag.' "$STDERR"
if cmp -s "$T/e1-before" "$(state_file e1)"; then
    pass "a refusal changes nothing on the session, its rebind variable included"
else
    fail "the session's state file changed on a refused attach"
fi

# template_mismatch
A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
run_real e1 "$TPL_DIR/other.md" "$A" --attach-live --replace-terminal
assert_eq "a live session from another template: refused=template_mismatch" "refused=template_mismatch" "$STDOUT"
assert_eq "template_mismatch exits 2" "2" "$RC"

# origin_mismatch: the same name from another worktree
OTHER_TREE="$T/other-tree"
mkdir -p "$OTHER_TREE"
git -C "$OTHER_TREE" init -q
A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
RC=0
(cd "$OTHER_TREE" && PATH="$TOOLS:$SYS_PATH" "$BASH_BIN" "$OPEN" e1 "$TPL" "$A" --attach-live --replace-terminal) \
    >"$T/stdout" 2>"$T/stderr" || RC=$?
assert_eq "a same-named session from another worktree: refused=origin_mismatch" "refused=origin_mismatch" "$(cat "$T/stdout")"
assert_eq "origin_mismatch exits 2" "2" "$RC"

# session_live under --replace-terminal alone
A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
run_real e1 "$TPL" "$A" --replace-terminal
assert_eq "a live session under --replace-terminal alone: refused=session_live" "refused=session_live" "$STDOUT"

# replace-terminal, returning the old result
(cd "$REPO" && PATH="$TOOLS:$SYS_PATH" koto next e1 --with-data '{"status":"ok"}' --no-cleanup >/dev/null 2>&1)
A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
run_real e1 "$TPL" "$A" --attach-live
assert_eq "a finished session under --attach-live alone: refused=session_terminal" "refused=session_terminal" "$STDOUT"
A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
run_real e1 "$TPL" "$A" --attach-live --replace-terminal
assert_eq "a finished session: opened=replaced" "opened=replaced" "$(first_line)"
assert_contains "the replaced session's state is reported" "replaced_state=done" "$STDOUT"
RESULT_LINE=$(printf '%s\n' "$STDOUT" | grep '^replaced_result=' | sed 's/^replaced_result=//')
if [ "$(printf '%s' "$RESULT_LINE" | jq -r '.payload.outcome' 2>/dev/null)" = "ok" ]; then
    pass "the replaced session's result is written to stdout as one JSON line"
else
    fail "replaced_result did not carry the old result: [$RESULT_LINE]"
fi

# The finished session of one template, replaced by a run of the other one --
# the execute.md / execute-coordinated.md shape.
(cd "$REPO" && PATH="$TOOLS:$SYS_PATH" koto next e1 --with-data '{"status":"ok"}' --no-cleanup >/dev/null 2>&1)
A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
run_real e1 "$TPL_DIR/other.md" "$A" --attach-live --replace-terminal
assert_eq "a finished session from another template is replaced" "opened=replaced" "$(first_line)"

# the variable refusals
A=$(new_args "$OUTSIDE" '[["TOPIC","t1"],["MERGE","yes"]]')
run_real e2 "$TPL" "$A" --attach-live --replace-terminal
assert_eq "a value outside its constraint: refused=invalid_var" "refused=invalid_var" "$STDOUT"
assert_eq "invalid_var exits 2" "2" "$RC"

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"],["MERGE","true"],["MERGE","true"]]')
run_real e2 "$TPL" "$A" --attach-live --replace-terminal
assert_eq "a flag given twice stays two pairs: refused=duplicate_var" "refused=duplicate_var" "$STDOUT"
assert_eq "duplicate_var exits 2" "2" "$RC"

A=$(new_args "$OUTSIDE" '[["TOPIC","t1"],["NOPE","x"]]')
run_real e2 "$TPL" "$A" --attach-live --replace-terminal
assert_eq "an undeclared variable: refused=unknown_var" "refused=unknown_var" "$STDOUT"

if (cd "$REPO" && PATH="$TOOLS:$SYS_PATH" koto status e2 >/dev/null 2>&1); then
    fail "a refused open created a session"
else
    pass "a refused open creates no session"
fi

# koto receives the hostile value as data: it reports back the exact bytes.
A=$(new_args "$OUTSIDE" '[["TOPIC",$v]]' --arg v "$HOSTILE")
run_real e2 "$TPL" "$A" --wording "$T/wording.tsv"
assert_eq "a hostile value is refused as invalid_var, not run" "refused=invalid_var" "$STDOUT"
assert_eq "koto reports the hostile value byte-for-byte" \
    "Invalid value \"$HOSTILE\" for TOPIC; it must satisfy pattern:^[a-z0-9][a-z0-9-]*\$." "$STDERR"
if [ -e "$REPO/pwned" ] || [ -e "$REPO/pwned2" ]; then fail "the hostile value was executed"; else pass "the hostile value was not executed"; fi

# The existing session a direct init refuses today: no entry flag at all.
A=$(new_args "$OUTSIDE" '[["TOPIC","t1"]]')
run_real e1 "$TPL" "$A" --wording "$T/wording.tsv"
assert_eq "an existing session with no entry flag: refused=already_exists" "refused=already_exists" "$STDOUT"
assert_eq "it prints the caller's wording for that condition" "A session named e1 already exists." "$STDERR"

# --- the request leg ------------------------------------------------------------

REQ=$(cd "$REPO" && PATH="$TOOLS:$SYS_PATH" koto request create \
    --with-data '{"legs":[{"name":"execute","role":"execute","template":"open.md","inputs":{}}]}' \
    --requested-by koto-open-test --coordinator-of-record koto-open-test 2>/dev/null | jq -r '.request_id')

A=$(new_args "$OUTSIDE" '[["TOPIC","t3"],["MERGE","false"]]')
run_real e3 "$TPL" "$A" --attach-live --replace-terminal
cp "$(state_file e3)" "$T/e3-before"

# A refused invocation under --koto-leg: the fixed TOPIC differs, and MERGE,
# a rebind variable, asks for a change it must not get.
A=$(new_args "$OUTSIDE" '[["TOPIC","t9"],["MERGE","true"]]')
run_real e3 "$TPL" "$A" --attach-live --replace-terminal --koto-leg "$REQ:execute"
assert_eq "a refusal under --koto-leg: refused=var_mismatch" "refused=var_mismatch" "$STDOUT"
SOURCE=$(cd "$REPO" && PATH="$TOOLS:$SYS_PATH" koto request get "$REQ" 2>/dev/null | jq -r '.legs.execute.result_source')
REASON=$(cd "$REPO" && PATH="$TOOLS:$SYS_PATH" koto request get "$REQ" 2>/dev/null | jq -r '.legs.execute.result.payload.reason')
assert_eq "koto recorded the refusal on the leg (source: refused)" "refused" "$SOURCE"
assert_eq "the leg's refusal names the variable" "var-mismatch:TOPIC" "$REASON"
if cmp -s "$T/e3-before" "$(state_file e3)"; then
    pass "the refused leg invocation left the session's rebind variable unchanged"
else
    fail "the session changed on a refused --koto-leg invocation"
fi

REQ2=$(cd "$REPO" && PATH="$TOOLS:$SYS_PATH" koto request create \
    --with-data '{"legs":[{"name":"execute","role":"execute","template":["open.md","other.md"],"inputs":{}}]}' \
    --requested-by koto-open-test --coordinator-of-record koto-open-test 2>/dev/null | jq -r '.request_id')
A=$(new_args "$OUTSIDE" '[["TOPIC","t3"],["MERGE","true"]]')
run_real e3 "$TPL" "$A" --attach-live --replace-terminal --koto-leg "$REQ2:execute"
assert_eq "an accepted attach under --koto-leg: opened=attached" "opened=attached" "$(first_line)"
assert_contains "the leg binding is reported" '"written":true' "$STDOUT"

# --- a session with no origin record -----------------------------------------------
#
# Sessions made by a koto older than the entry flags carry no origin record,
# and --attach-live refuses them. The rendering must keep koto's instruction to
# finish or clean the session, even when the caller maps origin_mismatch to
# generic wording.
A=$(new_args "$OUTSIDE" '[["TOPIC","t4"]]')
run_real e4 "$TPL" "$A"
SF=$(state_file e4)
{ head -1 "$SF" | jq -c 'del(.origin)'; tail -n +2 "$SF"; } >"$SF.new" && mv "$SF.new" "$SF"
A=$(new_args "$OUTSIDE" '[["TOPIC","t4"]]')
run_real e4 "$TPL" "$A" --attach-live --replace-terminal --wording "$T/wording.tsv"
assert_eq "a session with no origin record: refused=origin_mismatch" "refused=origin_mismatch" "$STDOUT"
assert_contains "the rendering names the missing origin record" "no origin record" "$STDERR"
assert_contains "the rendering keeps the koto session cleanup instruction" "koto session cleanup e4" "$STDERR"
case "$STDERR" in
    *"someone else owns"*) fail "the no-origin refusal was replaced by generic mismatch wording" ;;
    *) pass "the no-origin refusal is not replaced by generic mismatch wording" ;;
esac

echo
echo "koto-open_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
