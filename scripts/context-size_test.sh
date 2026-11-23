#!/usr/bin/env bash
# context-size_test.sh -- scripts/context-size.sh against synthetic
# transcripts built from the record shapes Claude Code writes: user and
# assistant records, tool results, compact_boundary system records, sidechain
# and synthetic assistant records, and records of other types.
#
# Covers: the figure with no boundary and after two; boundary counts and the
# assistant turn of each; one turn per message id with the figure from the
# id's last record; sidechain, synthetic and malformed records giving no turn
# and no figure; a half-written line skipped; the same report from the
# instance, the workspace root and an unrelated directory, and again after
# five more turns; the window and hard stop for an integer, invalid and unset
# window; the refusals (no argument, missing, directory, FIFO, empty, no
# usage after the latest boundary); jq off PATH; and planted text in no
# output.
#
# Usage: bash scripts/context-size_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/context-size.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/context-size-test.XXXXXX") || exit 1
trap 'case "$T" in */context-size-test.*) rm -rf "$T" ;; esac' EXIT
T=$(cd "$T" && pwd -P) || exit 1
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "$2 :: rc=${rc-} out=${OUT-}"; fi; }

unset CLAUDE_CODE_AUTO_COMPACT_WINDOW
MARK=PLANTED-TEXT-7f3a
mkdir -p "$T/ws/inst" "$T/elsewhere" "$T/nojq" || exit 1

# Record writers. Each prints one JSONL line.
user_rec() {
    printf '{"type":"user","isSidechain":false,"message":{"role":"user","content":"%s user"}}\n' "$MARK"
}
tool_result_rec() {
    printf '{"type":"user","isSidechain":false,"message":{"role":"user","content":[{"type":"tool_result","content":"%s tool"}]}}\n' "$MARK"
}
# asst <id> <input> <cache_read> <cache_creation> [model] [sidechain]
asst_rec() {
    printf '{"type":"assistant","isSidechain":%s,"message":{"id":"msgid-%s","model":"%s","role":"assistant","content":[{"type":"text","text":"%s assistant"}],"usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"output_tokens":7}}}\n' \
        "${6:-false}" "$1" "${5:-claude-test-model}" "$MARK" "$2" "$3" "$4"
}
boundary_rec() {
    printf '{"type":"system","subtype":"compact_boundary","isSidechain":false,"content":"%s boundary","compactMetadata":{"trigger":"auto","preTokens":90000,"postTokens":20000}}\n' "$MARK"
}
other_rec() {
    printf '{"type":"attachment","isSidechain":false,"attachment":{"text":"%s attachment"}}\n' "$MARK"
}

run() { (cd "${RUN_CWD:-$T}" && bash "$SCRIPT" "$@"); }
val() { sed -n "s/^$1: //p" <<<"$OUT"; }

echo "== no boundary: the newest assistant message's input total =="
TR="$T/ws/inst/a.jsonl"
{
    user_rec
    asst_rec m1 3 1000 2000
    tool_result_rec
    other_rec
    asst_rec m2 5 3000 400
} >"$TR"
OUT=$(run "$TR" 2>&1); rc=$?
check "exit 0" '[ "$rc" -eq 0 ]'
check "context_tokens is 5+3000+400" '[ "$(val context_tokens)" = 3405 ]'
check "boundaries: 0" '[ "$(val boundaries)" = 0 ]'
check "boundary_turns: none" '[ "$(val boundary_turns)" = none ]'
check "window: unset" '[ "$(val window)" = unset ]'
check "no hard_stop line with the window unset" '! grep -q "^hard_stop:" <<<"$OUT"'
check "five lines at most, four here" '[ "$(grep -c . <<<"$OUT")" -eq 4 ]'

echo "== two boundaries: counts, turns, figure after the second =="
TR="$T/ws/inst/b.jsonl"
{
    user_rec
    asst_rec t1 1 100 0
    asst_rec t2 1 200 0
    asst_rec t2 1 250 0
    asst_rec t3 1 300 0
    boundary_rec
    user_rec
    asst_rec t4 2 400 0
    asst_rec t5 2 500 0
    boundary_rec
    tool_result_rec
    asst_rec t6 4 600 10
    asst_rec t6 4 650 20
} >"$TR"
OUT=$(run "$TR" 2>&1); rc=$?
check "exit 0" '[ "$rc" -eq 0 ]'
check "boundaries: 2" '[ "$(val boundaries)" = 2 ]'
check "turns 3 and 5 (records sharing an id count once)" '[ "$(val boundary_turns)" = "3 5" ]'
check "figure from the id's last record after the second boundary" '[ "$(val context_tokens)" = 674 ]'

echo "== the figure is never one from before the latest boundary =="
TR="$T/ws/inst/c.jsonl"
{
    asst_rec u1 1 99000 0
    boundary_rec
    asst_rec u2 1 20000 0
    boundary_rec
    asst_rec u3 1 15000 0
} >"$TR"
OUT=$(run "$TR" 2>&1); rc=$?
check "figure is the post-boundary 15001" '[ "$(val context_tokens)" = 15001 ]'
check "turns 1 2" '[ "$(val boundary_turns)" = "1 2" ]'

echo "== sidechain and synthetic records are not turns and give no figure =="
TR="$T/ws/inst/d.jsonl"
{
    asst_rec v1 1 1000 0
    asst_rec side1 1 777777 0 claude-test-model true
    printf '{"type":"system","subtype":"compact_boundary","isSidechain":true,"content":"x"}\n'
    asst_rec synth1 0 0 0 "<synthetic>"
    asst_rec v2 1 2000 0
    asst_rec side2 1 888888 0 claude-test-model true
    asst_rec synth2 0 0 0 "<synthetic>"
} >"$TR"
OUT=$(run "$TR" 2>&1); rc=$?
check "exit 0" '[ "$rc" -eq 0 ]'
check "figure from the newest main-chain model record" '[ "$(val context_tokens)" = 2001 ]'
check "a sidechain boundary is not a boundary" '[ "$(val boundaries)" = 0 ]'
TR="$T/ws/inst/d2.jsonl"
{
    asst_rec w1 1 10 0
    asst_rec side 1 10 0 claude-test-model true
    asst_rec synth 0 0 0 "<synthetic>"
    asst_rec w2 1 20 0
    boundary_rec
    asst_rec w3 1 30 0
} >"$TR"
OUT=$(run "$TR" 2>&1); rc=$?
check "sidechain and synthetic records add no turn" '[ "$(val boundary_turns)" = 2 ]'

echo "== malformed records and a half-written line =="
TR="$T/ws/inst/e.jsonl"
{
    asst_rec x1 1 500 0
    printf '{"type":"assistant","isSidechain":false,"message":{"id":"x2","model":"m","usage":{"input_tokens":"9999","cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n'
    printf '{"type":"assistant","isSidechain":false,"message":{"id":"x3","model":"m","usage":{"input_tokens":1.5,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n'
    printf '{"type":"assistant","isSidechain":false,"message":{"id":"x4","model":"m","usage":{"input_tokens":-4,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n'
    printf '{"type":"assistant","isSidechain":false,"message":{"id":7,"model":"m","usage":{"input_tokens":4,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n'
    printf '{"type":"assistant","isSidechain":false,"message":{"id":"x5","usage":{"input_tokens":4,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n'
    printf '[1,2,3]\n'
    printf '"just a string"\n'
    printf '{"type":"assistant","isSidechain":false,"message":{"id":"x6","model":"m","usage":{"input_tok'
} >"$TR"
OUT=$(run "$TR" 2>&1); rc=$?
check "exit 0 past every malformed line" '[ "$rc" -eq 0 ]'
check "figure from the one well-formed record" '[ "$(val context_tokens)" = 501 ]'
TR="$T/ws/inst/e2.jsonl"
{
    asst_rec y1 1 500 0
    printf '{"type":"assistant","isSidechain":false,"message":{"id":"y2","model":"m","usage":{"input_tokens":3}}}\n'
} >"$TR"
OUT=$(run "$TR" 2>&1); rc=$?
check "a missing cache count reads as 0" '[ "$(val context_tokens)" = 3 ]'

echo "== the same report from any directory, and after five more turns =="
TR="$T/ws/inst/b.jsonl"
A=$(RUN_CWD="$T/ws/inst" run "$TR" 2>&1)
B=$(RUN_CWD="$T/ws" run "$TR" 2>&1)
C=$(RUN_CWD="$T/elsewhere" run "$TR" 2>&1)
OUT=$A
check "instance and workspace root agree" '[ "$A" = "$B" ]'
check "unrelated directory agrees" '[ "$A" = "$C" ]'
check "a relative path from its own directory agrees" '[ "$(RUN_CWD="$T/ws/inst" run b.jsonl 2>&1)" = "$A" ]'
{
    asst_rec z1 1 700 0
    asst_rec z2 1 800 0
    asst_rec z3 1 900 0
    asst_rec z4 1 1000 0
    asst_rec z5 1 1100 0
} >>"$TR"
OUT=$(RUN_CWD="$T/ws" run "$TR" 2>&1); rc=$?
check "after five more turns the figure follows the newest" '[ "$(val context_tokens)" = 1101 ]'
check "and the boundaries are unchanged" '[ "$(val boundary_turns)" = "3 5" ]'

echo "== the window and the hard stop =="
TR="$T/ws/inst/a.jsonl"
OUT=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=280000 run "$TR" 2>&1); rc=$?
check "window: 280000" '[ "$(val window)" = 280000 ]'
check "hard_stop: 350000" '[ "$(val hard_stop)" = 350000 ]'
check "five lines with a window" '[ "$(grep -c . <<<"$OUT")" -eq 5 ]'
OUT=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=300001 run "$TR" 2>&1)
check "hard_stop rounds down" '[ "$(val hard_stop)" = 375001 ]'
for w in 28e4 "280000 " -1 "+280000" 0 0280000 1000000000 "" abc; do
    OUT=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW="$w" run "$TR" 2>&1); rc=$?
    check "window '$w' is invalid" '[ "$rc" -eq 0 ] && [ "$(val window)" = invalid ]'
    check "no hard_stop for window '$w'" '! grep -q "^hard_stop:" <<<"$OUT"'
done

echo "== refusals: exit 1 naming the path and cause, no figure =="
OUT=$(run 2>&1); rc=$?
check "no argument exits 1" '[ "$rc" -eq 1 ] && grep -q usage <<<"$OUT"'
OUT=$(run "$T/ws/inst/a.jsonl" extra 2>&1); rc=$?
check "two arguments exit 1" '[ "$rc" -eq 1 ]'
OUT=$(run "$T/missing.jsonl" 2>&1); rc=$?
check "missing exits 1 naming it" '[ "$rc" -eq 1 ] && grep -q "missing.jsonl: no such transcript" <<<"$OUT"'
check "missing prints no figure" '! grep -q context_tokens <<<"$OUT"'
OUT=$(run "$T/ws" 2>&1); rc=$?
check "directory exits 1" '[ "$rc" -eq 1 ] && grep -q "is a directory" <<<"$OUT"'
mkfifo "$T/fifo" || exit 1
OUT=$(run "$T/fifo" 2>&1); rc=$?
check "FIFO exits 1 without blocking" '[ "$rc" -eq 1 ] && grep -q "not a regular file" <<<"$OUT"'
: >"$T/empty.jsonl"
OUT=$(run "$T/empty.jsonl" 2>&1); rc=$?
check "empty exits 1" '[ "$rc" -eq 1 ] && grep -q "empty transcript" <<<"$OUT"'
TR="$T/ws/inst/f.jsonl"
{
    asst_rec q1 1 500 0
    boundary_rec
    user_rec
} >"$TR"
OUT=$(run "$TR" 2>&1); rc=$?
check "no usage after the latest boundary exits 1" '[ "$rc" -eq 1 ] && grep -q "no assistant usage after the latest compaction boundary" <<<"$OUT"'
check "and prints no figure" '! grep -q context_tokens <<<"$OUT"'
TR="$T/ws/inst/g.jsonl"
{ user_rec; other_rec; } >"$TR"
OUT=$(run "$TR" 2>&1); rc=$?
check "no assistant record at all exits 1" '[ "$rc" -eq 1 ]'
TR="$T/ws/inst/h.jsonl"
printf 'not json at all\n' >"$TR"
OUT=$(run "$TR" 2>&1); rc=$?
check "a file of junk exits 1, not 2" '[ "$rc" -eq 1 ]'
NL=$(printf 'x\ny')
OUT=$(run "$T/ws/inst/ctl$NL.jsonl" 2>&1); rc=$?
check "a control character in the path is shown as ?" '[ "$rc" -eq 1 ] && grep -q "ctlx?y.jsonl" <<<"$OUT"'
if [ "$(id -u)" -ne 0 ]; then
    cp "$T/ws/inst/a.jsonl" "$T/unreadable.jsonl" || exit 1
    chmod 000 "$T/unreadable.jsonl"
    OUT=$(run "$T/unreadable.jsonl" 2>&1); rc=$?
    check "unreadable exits 1" '[ "$rc" -eq 1 ] && grep -q "not readable" <<<"$OUT"'
    chmod 600 "$T/unreadable.jsonl"
fi

echo "== jq off PATH is an environment fault =="
for tool in tr sed; do
    ln -s "$(command -v "$tool")" "$T/nojq/$tool" || exit 1
done
BASH_BIN=$(command -v bash)
OUT=$( (cd "$T" && PATH="$T/nojq" "$BASH_BIN" "$SCRIPT" "$T/ws/inst/a.jsonl") 2>&1); rc=$?
check "exit 2 with jq absent" '[ "$rc" -eq 2 ] && grep -q "jq is not on PATH" <<<"$OUT"'

echo "== planted transcript text appears in no output =="
LEAK=0
for f in "$T"/ws/inst/*.jsonl; do
    for w in unset 280000 bogus; do
        if [ "$w" = unset ]; then
            OUT=$(run "$f" 2>&1)
        else
            OUT=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=$w run "$f" 2>&1)
        fi
        case "$OUT" in *"$MARK"* | *claude-test-model* | *msgid-*) LEAK=1 ;; esac
    done
done
check "no marker, message id or model in stdout or stderr" '[ "$LEAK" -eq 0 ]'

echo
printf 'context-size: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
