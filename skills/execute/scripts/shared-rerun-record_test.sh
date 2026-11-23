#!/usr/bin/env bash
# shared-rerun-record_test.sh -- does pr_finalization's rerun_recorded gate
# hold /execute's shared PR until its body carries a re-run line for every
# archived verification attempt its children hold, and pass a run with none
# without reading GitHub?
# Part of the execute skill
#
# shared-rerun-record.sh finds the children that re-ran (a
# verification_attempts key with a line in it) and checks the owned PR's body
# with /work-on's check-pr-output.sh --rerun-record. This file checks:
#
#   1. No engine, through a koto stub, a gh stub and an owned-pr.sh stand-in
#      (check-pr-output.sh's CHECK_PR_OUTPUT_OWNED_PR seam), with the real
#      check-pr-output.sh:
#        - no ledger in any child passes (0) and reads nothing from GitHub;
#        - one child's attempt holds the PR (1, naming the attempt) until its
#          line is written, then passes;
#        - two children's attempts are each needed, and the message names the
#          child whose line is missing;
#        - --child reads exactly the named sessions with no child listing;
#        - --child-dir runs every koto read in that directory, check-pr-output.sh's
#          own ledger reads included;
#        - --list prints the children that re-ran, with no GitHub read;
#        - --lines prints each child's re-run lines, with no GitHub read and
#          in --child-dir when given, and a body carrying them passes;
#        - --recorded checks the body against the given lines with no koto
#          read (under either workflow-content setting), --lines with it
#          prints them once each, and a line in another shape or spanning
#          lines can't be decided;
#        - a failed listing or a failed key read can't be decided (2);
#        - a repository that omits workflow content is checked all the same:
#          the re-run lines are required under either setting;
#        - usage errors are 2.
#   2. Engine: a parent session and two children made with `koto init
#      --parent`, one holding a verification_attempts ledger written with
#      `koto context add`. The script, over the real koto, holds the shared PR
#      until its body has that attempt's line. A parent whose children hold no
#      ledger passes with no gh call.
#
# Part 2 skips, loudly, when koto is absent (the bash 3.2 floor leg has none),
# and runs under this suite's temporary HOME only.
#
# Usage: shared-rerun-record_test.sh
# Exit codes: 0 all pass (or the engine part skipped), 1 any failed, 2 the
# harness could not run.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
GATE="$SCRIPT_DIR/shared-rerun-record.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -x "$GATE" ] || { echo "not executable: $GATE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }
REAL_KOTO=$(command -v koto || true)

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/shared-rerun-record-test.XXXXXX") || exit 2
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 2
cleanup() { case "${WORKDIR:-}" in */shared-rerun-record-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
ktg_on_exit cleanup

# The re-run lines are required whatever the workflow-content setting, so the
# gate runs in a repository that opts in and, in its own case, in one that
# doesn't.
mkdir -p "$WORKDIR/include-repo" "$WORKDIR/omit-repo"
printf '## PR Workflow Content: include\n' > "$WORKDIR/include-repo/CLAUDE.md"
printf '# A repo\n' > "$WORKDIR/omit-repo/CLAUDE.md"
cd "$WORKDIR/include-repo" || exit 2

BIN="$WORKDIR/bin"
STUB="$WORKDIR/stub"
mkdir -p "$BIN" "$STUB/ctx"

# koto stub: `workflows --children <s>` prints $STUB/children.json (exit
# $STUB/workflows.rc when that file exists); `context exists <c> <key>` is 0
# when $STUB/ctx/<c>/<key> exists, else 1 with nothing on stdout (exit
# $STUB/exists.rc overrides); `context get <c> <key>` prints that file (exit
# $STUB/get.rc overrides). Every call is logged, with the directory it ran in.
cat > "$BIN/koto" <<'EOF'
#!/usr/bin/env bash
STUB="${SRR_STUB:?}"
printf '%s\n' "$*" >> "$STUB/koto.calls"
printf '%s\n' "$(pwd -P)" >> "$STUB/koto.dirs"
case "$1 ${2-}" in
    "workflows --children")
        if [ -f "$STUB/workflows.rc" ]; then echo "koto: no session" >&2; exit "$(cat "$STUB/workflows.rc")"; fi
        cat "$STUB/children.json" ;;
    "context exists")
        if [ -f "$STUB/exists.rc" ]; then echo "koto: store unreadable" >&2; exit "$(cat "$STUB/exists.rc")"; fi
        [ -f "$STUB/ctx/$3/$4" ] ;;
    "context get")
        if [ -f "$STUB/get.rc" ]; then echo "koto: store unreadable" >&2; exit "$(cat "$STUB/get.rc")"; fi
        [ -f "$STUB/ctx/$3/$4" ] || exit 1
        cat "$STUB/ctx/$3/$4" ;;
    *) echo "koto stub: unexpected call: $*" >&2; exit 64 ;;
esac
EOF
# gh stub: `gh pr view <url> --json body` prints {"body": <$STUB/body.md>}.
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
STUB="${SRR_STUB:?}"
printf '%s\n' "$*" >> "$STUB/gh.calls"
jq -Rsc '{body: .}' "$STUB/body.md"
EOF
# owned-pr.sh stand-in: one URL, or $STUB/owned.rc's exit.
cat > "$BIN/owned-pr.sh" <<'EOF'
#!/usr/bin/env bash
STUB="${SRR_STUB:?}"
printf '%s\n' "$*" >> "$STUB/owned.calls"
if [ -f "$STUB/owned.rc" ]; then exit "$(cat "$STUB/owned.rc")"; fi
echo https://github.com/acme/widgets/pull/12
EOF
chmod +x "$BIN/koto" "$BIN/gh" "$BIN/owned-pr.sh"

HEAD_A=fedcba9876543210fedcba9876543210fedcba98
HEAD_B=abcdef0123456789abcdef0123456789abcdef01
MB=1111111111111111111111111111111111111111
REASON='flaky network test'
OWNED_ARGS="--repo acme/widgets --head impl/x --state open --run-id 00112233445566778899aabbccddeeff"

# ledger_line <head>: attempt 1 at <head>, its `unit` command failed.
ledger_line() {
    jq -cn --arg h "$1" --arg m "$MB" --arg r "$REASON" '{attempt: 1, folder: 1, head: $h, merge_base: $m,
        exit: 1, status: "done", reason: $r, archived_at: "2026-01-01T00:00:00Z",
        commands: [{id: "unit", exit_status: 1, timed_out: false, duration_secs: 3, log: "attempts/1/0-unit.log"}]}'
}
# rerun_line <head>: that attempt's re-run line.
rerun_line() { printf 'Re-run attempt 1 at `%s`: `unit` failed; reason `%s`.' "$(printf '%s' "$1" | cut -c1-7)" "$REASON"; }
# body <line>...: a shared PR body whose Verification section holds the lines.
body() {
    {
        printf '%s\n' "A change." "" "---" "" "## Verification" "" "Ran the verification map's commands."
        local l
        for l in "$@"; do printf '%s\n' "$l"; done
        printf '%s\n' "" "Fixes #12"
    } > "$STUB/body.md"
}
children() { # children <name>...
    jq -nc '$ARGS.positional | map({name: ., parent_workflow: "execute-x"})' --args "$@" > "$STUB/children.json"
}
child_reran() { mkdir -p "$STUB/ctx/$1"; printf '%s\n' "$2" > "$STUB/ctx/$1/verification_attempts"; }
reset_stub() {
    rm -rf "$STUB"
    mkdir -p "$STUB/ctx"
    : > "$STUB/koto.calls"
    : > "$STUB/koto.dirs"
    : > "$STUB/gh.calls"
    : > "$STUB/owned.calls"
    children
    body
}
count() { grep -c . "$STUB/$1" || true; }

RC=0
# run_gate <gate arguments>...: the gate under the stubs.
run_gate() {
    (PATH="$BIN:$PATH" SRR_STUB="$STUB" CHECK_PR_OUTPUT_OWNED_PR="$BIN/owned-pr.sh" "$GATE" "$@") \
        >"$WORKDIR/out" 2>"$WORKDIR/err"
    RC=$?
}
# run_stub: the gate over the session's children, with the owned-PR arguments.
run_stub() {
    # shellcheck disable=SC2086 # OWNED_ARGS is a word list
    run_gate --session execute-x -- $OWNED_ARGS
}
expect() { # expect <label> <rc>
    if [ "$RC" -eq "$2" ]; then pass "$1 ($RC)"; else fail "$1: want $2, got $RC; stderr [$(cat "$WORKDIR/err")]"; fi
}
expect_err() { # expect_err <label> <text>
    grep -qF -- "$2" "$WORKDIR/err" && pass "$1" || fail "$1: stderr [$(cat "$WORKDIR/err")] lacks [$2]"
}

echo "--- the gate, through stubs"

reset_stub
children execute-x.o-a execute-x.o-b
run_stub
expect "no ledger in any child: passes" 0
[ "$(count gh.calls)" = 0 ] && [ "$(count owned.calls)" = 0 ] \
    && pass "no ledger in any child: no owned-PR lookup and no gh call" \
    || fail "no ledger: gh calls $(count gh.calls), owned calls $(count owned.calls)"
expect_err "no ledger in any child: stderr says so" "nothing to record"

reset_stub
children execute-x.o-a execute-x.o-b
mkdir -p "$STUB/ctx/execute-x.o-a"
: > "$STUB/ctx/execute-x.o-a/verification_attempts"
run_stub
expect "an empty ledger is no re-run: passes" 0
[ "$(count gh.calls)" = 0 ] && pass "an empty ledger: no gh call" || fail "an empty ledger: gh calls $(count gh.calls)"

reset_stub
children execute-x.o-a execute-x.o-b
child_reran execute-x.o-b "$(ledger_line "$HEAD_A")"
run_stub
expect "one child's attempt, no re-run line: holds" 1
expect_err "one child's attempt, no line: stderr names the attempt and its head" "no re-run line for attempt 1 at fedcba987654"
body "$(rerun_line "$HEAD_A")"
run_stub
expect "one child's attempt, its line written: passes" 0
grep -q -- '--repo acme/widgets' "$STUB/owned.calls" \
    && pass "the owned-PR lookup gets the arguments after --" \
    || fail "owned-pr.sh got [$(cat "$STUB/owned.calls")]"

reset_stub
children execute-x.o-a execute-x.o-b execute-x.o-c
child_reran execute-x.o-a "$(ledger_line "$HEAD_A")"
child_reran execute-x.o-c "$(ledger_line "$HEAD_B")"
body "$(rerun_line "$HEAD_A")"
run_stub
expect "two children's attempts, the body has one line: holds" 1
expect_err "two children, one line missing: stderr names that child" "no re-run line for attempt 1 at abcdef012345 (session execute-x.o-c)"
if grep -qF "(session execute-x.o-a)" "$WORKDIR/err"; then
    fail "two children: the child whose line is there is reported"
else
    pass "two children: the child whose line is there isn't reported"
fi
body "$(rerun_line "$HEAD_A")" "$(rerun_line "$HEAD_B")"
run_stub
expect "two children's attempts, both lines: passes" 0

echo "--- checked under either workflow-content setting"

reset_stub
children execute-x.o-a
child_reran execute-x.o-a "$(ledger_line "$HEAD_A")"
cd "$WORKDIR/omit-repo" || exit 2
run_stub
cd "$WORKDIR/include-repo" || exit 2
expect "a repository that omits workflow content: a body without the line still holds (no omit pass)" 1
[ "$(count gh.calls)" -ge 1 ] && pass "omit: the body is read from GitHub" || fail "omit: no gh call"

echo "--- what can't be decided"

reset_stub
printf '1\n' > "$STUB/workflows.rc"
run_stub
expect "the child listing failed" 2
expect_err "the child listing failed: stderr names the listing" "koto workflows --children execute-x failed"
reset_stub
printf '[{"nome":"x"}]\n' > "$STUB/children.json"
run_stub
expect "the child listing is not a list of sessions" 2
reset_stub
children execute-x.o-a
printf '3\n' > "$STUB/exists.rc"
run_stub
expect "a child's key check failed (exit 3)" 2
expect_err "a failed key check: stderr names the child" "koto context exists execute-x.o-a verification_attempts failed (exit 3)"
[ "$(count gh.calls)" = 0 ] && pass "a failed key check: no gh call" || fail "a failed key check: gh calls $(count gh.calls)"
reset_stub
children execute-x.o-a
child_reran execute-x.o-a "$(ledger_line "$HEAD_A")"
printf '3\n' > "$STUB/get.rc"
run_stub
expect "a child's key read failed (exit 3)" 2
reset_stub
children execute-x.o-a
child_reran execute-x.o-a "$(ledger_line "$HEAD_A")"
body "$(rerun_line "$HEAD_A")"
printf '3\n' > "$STUB/owned.rc"
run_stub
expect "a re-run, and no single owned PR" 2

echo "--- --child, --child-dir and --list"

reset_stub
children execute-x.o-a
child_reran execute-x.o-a "$(ledger_line "$HEAD_A")"
# shellcheck disable=SC2086
run_gate --session execute-x --child work-on-t-core-1 -- $OWNED_ARGS
expect "--child: a listed child's ledger outside the named ones isn't read" 0
if grep -q 'workflows' "$STUB/koto.calls"; then
    fail "--child still listed the session's children: $(cat "$STUB/koto.calls")"
else
    pass "--child reads exactly the named sessions, with no child listing"
fi
[ "$(count gh.calls)" = 0 ] && pass "--child, no named child re-ran: no gh call" \
    || fail "--child, no re-run: gh calls $(count gh.calls)"

reset_stub
child_reran work-on-t-core-2 "$(ledger_line "$HEAD_B")"
# shellcheck disable=SC2086
run_gate --session execute-x --child work-on-t-core-1 --child work-on-t-core-2 -- $OWNED_ARGS
expect "--child: a named child re-ran, no line: holds" 1
body "$(rerun_line "$HEAD_B")"
# shellcheck disable=SC2086
run_gate --session execute-x --child work-on-t-core-1 --child work-on-t-core-2 -- $OWNED_ARGS
expect "--child: the body has the named child's line: passes" 0

reset_stub
child_reran work-on-t-core-1 "$(ledger_line "$HEAD_A")"
child_reran work-on-t-core-3 "$(ledger_line "$HEAD_B")"
run_gate --session execute-x --child work-on-t-core-1 --child work-on-t-core-2 --child work-on-t-core-3 --list
expect "--list: listed" 0
if [ "$(cat "$WORKDIR/out")" = "$(printf '%s\n%s' work-on-t-core-1 work-on-t-core-3)" ]; then
    pass "--list prints each child that re-ran, in order"
else
    fail "--list printed [$(cat "$WORKDIR/out")]"
fi
[ "$(count gh.calls)" = 0 ] && [ "$(count owned.calls)" = 0 ] \
    && pass "--list reads nothing from GitHub" \
    || fail "--list: gh calls $(count gh.calls), owned calls $(count owned.calls)"
reset_stub
run_gate --session execute-x --child work-on-t-core-1 --list
expect "--list with no re-run" 0
[ -s "$WORKDIR/out" ] && fail "--list with no re-run printed [$(cat "$WORKDIR/out")]" \
    || pass "--list with no re-run prints nothing"

# --child-dir: the named children are read from that directory (a coordinated
# node's worktree, where their sessions were opened), and so are
# check-pr-output.sh's own reads of their ledgers.
reset_stub
mkdir -p "$WORKDIR/node-worktree"
NODE_DIR=$(cd "$WORKDIR/node-worktree" && pwd -P)
child_reran work-on-t-core-2 "$(ledger_line "$HEAD_B")"
body "$(rerun_line "$HEAD_B")"
# shellcheck disable=SC2086
run_gate --session execute-x --child work-on-t-core-1 --child work-on-t-core-2 --child-dir "$WORKDIR/node-worktree" -- $OWNED_ARGS
expect "--child-dir: the body has the named child's line: passes" 0
if grep -qF 'context exists work-on-t-core-2 verification_results.json' "$STUB/koto.calls"; then
    pass "--child-dir: check-pr-output.sh read the child's ledger and result itself"
else
    fail "--child-dir: check-pr-output.sh made no koto read: [$(cat "$STUB/koto.calls")]"
fi
if [ -s "$STUB/koto.dirs" ] && [ -z "$(grep -vxF "$NODE_DIR" "$STUB/koto.dirs")" ]; then
    pass "--child-dir: every koto read ran in that directory, check-pr-output.sh's included"
else
    fail "--child-dir: the koto reads ran in [$(sort -u "$STUB/koto.dirs" | tr '\n' ' ')]"
fi
body
# shellcheck disable=SC2086
run_gate --session execute-x --child work-on-t-core-2 --child-dir "$WORKDIR/node-worktree" -- $OWNED_ARGS
expect "--child-dir: a body without the named child's line holds" 1
run_gate --session execute-x --child-dir "$WORKDIR/node-worktree" --list
expect "--child-dir with no --child: usage" 2
run_gate --session execute-x --child work-on-t-core-1 --child-dir "$WORKDIR/no-such-dir" --list
expect "--child-dir that is no directory: undecided" 2

echo "--- --lines and --recorded"

# printed_line <head>: the line --lines prints for ledger_line <head>, with
# 12 hex of the head and no next result (no verification_results.json).
printed_line() { printf 'Re-run attempt 1 at `%s`: `unit` failed; reason `%s`.' "$(printf '%s' "$1" | cut -c1-12)" "$REASON"; }
LINE_A=$(printed_line "$HEAD_A")
LINE_B=$(printed_line "$HEAD_B")

reset_stub
child_reran work-on-t-core-1 "$(ledger_line "$HEAD_A")"
child_reran work-on-t-core-3 "$(ledger_line "$HEAD_B")"
run_gate --session execute-x --child work-on-t-core-1 --child work-on-t-core-2 --child work-on-t-core-3 --lines
expect "--lines: printed" 0
if [ "$(cat "$WORKDIR/out")" = "$(printf '%s\n%s' "$LINE_A" "$LINE_B")" ]; then
    pass "--lines prints each re-run line, the children in order"
else
    fail "--lines printed [$(cat "$WORKDIR/out")]"
fi
[ "$(count gh.calls)" = 0 ] && [ "$(count owned.calls)" = 0 ] \
    && pass "--lines reads nothing from GitHub" \
    || fail "--lines: gh calls $(count gh.calls), owned calls $(count owned.calls)"
body "$LINE_A" "$LINE_B"
# shellcheck disable=SC2086
run_gate --session execute-x --child work-on-t-core-1 --child work-on-t-core-2 --child work-on-t-core-3 -- $OWNED_ARGS
expect "a body carrying the lines --lines printed passes the gate" 0

reset_stub
run_gate --session execute-x --child work-on-t-core-1 --lines
expect "--lines with no re-run" 0
[ -s "$WORKDIR/out" ] && fail "--lines with no re-run printed [$(cat "$WORKDIR/out")]" \
    || pass "--lines with no re-run prints nothing"

reset_stub
child_reran work-on-t-core-2 "$(ledger_line "$HEAD_B")"
run_gate --session execute-x --child work-on-t-core-2 --child-dir "$WORKDIR/node-worktree" --lines
expect "--lines with --child-dir: printed" 0
[ "$(cat "$WORKDIR/out")" = "$LINE_B" ] && pass "--lines with --child-dir prints the named child's line" \
    || fail "--lines with --child-dir printed [$(cat "$WORKDIR/out")]"
if [ -s "$STUB/koto.dirs" ] && [ -z "$(grep -vxF "$NODE_DIR" "$STUB/koto.dirs")" ]; then
    pass "--lines with --child-dir: every koto read ran in that directory, check-pr-output.sh's included"
else
    fail "--lines with --child-dir: the koto reads ran in [$(sort -u "$STUB/koto.dirs" | tr '\n' ' ')]"
fi

# --recorded: the run record's lines in place of the children, no koto read.
reset_stub
body "$(rerun_line "$HEAD_A")"
# shellcheck disable=SC2086
run_gate --session execute-x --recorded "$LINE_A" -- $OWNED_ARGS
expect "--recorded: the body has the recorded attempt's line: passes" 0
[ "$(count koto.calls)" = 0 ] && pass "--recorded reads no child session" \
    || fail "--recorded made koto calls: [$(cat "$STUB/koto.calls")]"
[ "$(count gh.calls)" -ge 1 ] && pass "--recorded: the body is read from GitHub" || fail "--recorded: no gh call"
body
# shellcheck disable=SC2086
run_gate --session execute-x --recorded "$LINE_A" --recorded "$LINE_B" -- $OWNED_ARGS
expect "--recorded: a body without the lines holds" 1
expect_err "--recorded, no line: stderr names the attempt and its head" "no re-run line for attempt 1 at fedcba987654"
body "$(rerun_line "$HEAD_A")"
# shellcheck disable=SC2086
run_gate --session execute-x --recorded "$LINE_A" --recorded "$LINE_B" -- $OWNED_ARGS
expect "--recorded: one of two lines missing holds" 1
expect_err "--recorded: stderr names the missing line's attempt" "no re-run line for attempt 1 at abcdef012345"
cd "$WORKDIR/omit-repo" || exit 2
body
# shellcheck disable=SC2086
run_gate --session execute-x --recorded "$LINE_A" -- $OWNED_ARGS
cd "$WORKDIR/include-repo" || exit 2
expect "--recorded in a repository that omits workflow content: still checked" 1
run_gate --session execute-x --recorded "$LINE_A" --recorded "$LINE_A" --recorded "$LINE_B" --lines
expect "--recorded --lines: printed" 0
[ "$(cat "$WORKDIR/out")" = "$(printf '%s\n%s' "$LINE_A" "$LINE_B")" ] \
    && pass "--recorded --lines prints the recorded lines, the same line once" \
    || fail "--recorded --lines printed [$(cat "$WORKDIR/out")]"
# shellcheck disable=SC2086
run_gate --session execute-x --recorded 'Attempt 1 was re-run.' -- $OWNED_ARGS
expect "--recorded: a line in another shape can't be decided" 2
# shellcheck disable=SC2086
run_gate --session execute-x --recorded "$(printf '%s\n%s' "$LINE_A" "$LINE_B")" -- $OWNED_ARGS
expect "--recorded: a line spanning lines can't be decided" 2
run_gate --session execute-x --recorded "$LINE_A" --child work-on-t-core-1 --lines
expect "--recorded with --child: usage" 2
run_gate --session execute-x --recorded "$LINE_A" --list
expect "--recorded with --list: usage" 2
run_gate --session execute-x --recorded "" --lines
expect "--recorded with an empty line: usage" 2
[ "$(count koto.calls)" = 0 ] && pass "no --recorded case made a koto call" \
    || fail "a --recorded case made koto calls: [$(cat "$STUB/koto.calls")]"

echo "--- usage"

reset_stub
run_gate --session execute-x
expect "no owned-pr.sh arguments: usage" 2
run_gate -- --repo a/b
expect "no --session: usage" 2
run_gate --session execute-x --child
expect "--child with no session name: usage" 2
run_gate --session execute-x --verification local -- --repo a/b
expect "an unknown flag: usage" 2
for bad in "0 -" "x -" "- 0" "5 5" "5 9"; do
    reset_stub
    # shellcheck disable=SC2086 # two words on purpose
    set -- $bad
    if [ "$1" != - ]; then export SHARED_RERUN_RECORD_SECS="$1"; fi
    if [ "$2" != - ]; then export SHARED_RERUN_RECORD_LOOP_SECS="$2"; fi
    run_stub
    unset SHARED_RERUN_RECORD_SECS SHARED_RERUN_RECORD_LOOP_SECS
    expect "time seams [$bad] are a usage error" 2
done
set --

# --- 2. engine --------------------------------------------------------------------------

if [ -z "$REAL_KOTO" ]; then
    echo
    echo "SKIP: koto not on PATH -- the engine cases did not run"
    echo
    echo "shared-rerun-record_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
fi

echo "--- a child's ledger, through koto"

export HOME="$WORKDIR/home"
mkdir -p "$HOME"
REPO="$WORKDIR/repo"
mkdir -p "$REPO"
(cd "$REPO" && git init -q . && git config user.email t@example.com && git config user.name t \
    && git commit -q --allow-empty -m "chore: init") >/dev/null 2>&1 \
    || { echo "could not create the fixture repository" >&2; exit 2; }

# One template serves the parent and the children: a state that waits.
printf '%s\n' '---' 'name: shared-rerun-fixture' 'version: "1.0"' \
    'description: A session that waits, for the re-run record.' 'initial_state: wait' 'states:' \
    '  wait:' '    accepts:' '      go:' '        type: enum' '        values: [now]' '        required: true' \
    '    transitions:' '      - target: over' '        when:' '          go: now' \
    '  over:' '    terminal: true' '---' '' '## wait' '' 'Wait.' '' '## over' '' 'Over.' > "$WORKDIR/fixture.md"

k() { (cd "$REPO" && "$REAL_KOTO" "$@"); }
k init execute-eng --template "$WORKDIR/fixture.md" >"$WORKDIR/init.out" 2>&1 \
    || fail "parent init: $(head -c 300 "$WORKDIR/init.out")"
k init execute-eng.o-1 --parent execute-eng --template "$WORKDIR/fixture.md" >"$WORKDIR/init1.out" 2>&1 \
    || fail "first child init: $(head -c 300 "$WORKDIR/init1.out")"
k init execute-eng.o-2 --parent execute-eng --template "$WORKDIR/fixture.md" >"$WORKDIR/init2.out" 2>&1 \
    || fail "second child init: $(head -c 300 "$WORKDIR/init2.out")"
ledger_line "$HEAD_A" > "$WORKDIR/ledger.jsonl"
k context add execute-eng.o-1 verification_attempts --from-file "$WORKDIR/ledger.jsonl" >/dev/null 2>&1 \
    || fail "could not write the first child's verification_attempts"
GOT=$(k context get execute-eng.o-1 verification_attempts 2>/dev/null)
[ "$GOT" = "$(ledger_line "$HEAD_A")" ] && pass "engine: the first child holds one ledger line" \
    || fail "engine: the first child's verification_attempts is [$GOT]"

# run_engine <session>: the gate over the real koto, with the gh and
# owned-pr.sh stand-ins (only the stub koto is left off PATH).
run_engine() {
    rm -f "$BIN/koto"
    # shellcheck disable=SC2086
    (cd "$REPO" && PATH="$BIN:$PATH" SRR_STUB="$STUB" CHECK_PR_OUTPUT_OWNED_PR="$BIN/owned-pr.sh" \
        "$GATE" --session "$1" -- $OWNED_ARGS) \
        >"$WORKDIR/out" 2>"$WORKDIR/err"
    RC=$?
}

reset_stub
run_engine execute-eng
expect "engine: a child re-ran, the shared PR has no re-run line: holds" 1
expect_err "engine: the message names attempt 1 and its head" "no re-run line for attempt 1 at fedcba987654"
body "$(rerun_line "$HEAD_A")"
run_engine execute-eng
expect "engine: the shared PR has the child's re-run line: passes" 0

k init execute-none --template "$WORKDIR/fixture.md" >/dev/null 2>&1
k init execute-none.o-1 --parent execute-none --template "$WORKDIR/fixture.md" >/dev/null 2>&1
reset_stub
run_engine execute-none
expect "engine: no child re-ran: passes" 0
[ "$(count gh.calls)" = 0 ] && pass "engine: no child re-ran: no gh call" \
    || fail "engine: no re-run, gh calls [$(cat "$STUB/gh.calls")]"

echo
echo "shared-rerun-record_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
