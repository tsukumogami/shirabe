#!/usr/bin/env bash
# run-verification_test.sh -- the bounded verification runner and its verdict.
#
# Builds throwaway repositories whose verification map, committed on main,
# names small fixture commands, then runs run-verification.sh --start and
# check-verification.sh --verdict against them and asserts the verdict exit,
# the finding's rule_id, what was started (each fixture command records its
# argv to a file outside the repository), and that nothing a command started
# is left running.
#
# The runaway case is bounded on purpose: its command starts twelve sleeping
# children under a max_procs of 4, never an unbounded fork. Every fixture path
# lives under a mktemp directory whose name carries a unique marker, so the
# leak check (`pgrep -f <marker>`) and the cleanup can only ever see this
# run's processes.
#
# koto: the verdict records a settled result in koto context, so most cases
# run against a stand-in on PATH that logs the write. One case runs a real
# koto: a fixture template whose state runs --start as its default_action and
# --verdict as a poll: gate, ticked until it routes. It skips when koto is
# absent; CI's Linux leg installs koto, so it runs there.
#
# Usage: run-verification_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
START="$SCRIPT_DIR/run-verification.sh"
VERDICT="$SCRIPT_DIR/check-verification.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -x "$START" ] && [ -x "$VERDICT" ] || { echo "the scripts under test are missing or not executable" >&2; exit 2; }
REAL_KOTO=$(command -v koto 2>/dev/null || true)

MARK="rvtest$$x$RANDOM"
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/$MARK.XXXXXX") || exit 2
WORKDIR=$(cd "$WORKDIR" && pwd -P)

# Stop only this run's processes: everything that could be left carries the
# marker in its command line, and the marker is unique to this run.
reap_ours() {
    command -v pgrep >/dev/null 2>&1 || return 0
    for p in $(pgrep -f "$MARK" 2>/dev/null); do
        [ "$p" = "$$" ] && continue
        kill -KILL "$p" 2>/dev/null
    done
    return 0
}
cleanup() {
    reap_ours
    [ -n "${WORKDIR:-}" ] && chmod -R u+rwX "$WORKDIR" 2>/dev/null
    [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"
    return 0
}
trap cleanup EXIT

export HOME="$WORKDIR/home"
export XDG_STATE_HOME="$WORKDIR/state"
mkdir -p "$HOME" "$WORKDIR/bin"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main

# The koto stand-in: `koto context add <s> <key> --from-file <f>` copies the
# file to $WORKDIR/kotostore/<s>/<key> and logs the call.
cat > "$WORKDIR/bin/koto" <<'EOF'
#!/bin/sh
[ "$1" = context ] && [ "$2" = add ] || exit 9
mkdir -p "$KOTO_STUB_STORE/$3"
[ "${5-}" = --from-file ] && cp "$6" "$KOTO_STUB_STORE/$3/$4" || cat > "$KOTO_STUB_STORE/$3/$4"
echo "add $3 $4" >> "$KOTO_STUB_STORE/log"
EOF
chmod +x "$WORKDIR/bin/koto"
export KOTO_STUB_STORE="$WORKDIR/kotostore"
mkdir -p "$KOTO_STUB_STORE"
STUB_PATH="$WORKDIR/bin:$PATH"
export PATH="$STUB_PATH"

# --- fixtures ------------------------------------------------------------------------

# mkrepo <name> <map json | NONE>: a repository on branch `work`, one commit
# past main, whose main carries the map and the fixture commands. Leaves the
# shell in the repository.
mkrepo() {
    local dir="$WORKDIR/r-$1"
    mkdir -p "$dir/bin" "$dir/src/x" "$dir/skills/a" "$dir/skills/b" "$dir/docs"
    cd "$dir" || exit 2
    git init -q -b main .
    cat > bin/rec.sh <<'EOF'
#!/bin/sh
rec=$1; shift
printf '%s\n' "$*" >> "$rec"
EOF
    printf '#!/bin/sh\nexit 3\n' > bin/fail.sh
    printf '#!/bin/sh\nsleep 30\n' > bin/slow.sh
    printf '#!/bin/sh\nsleep 30\n' > bin/child.sh
    cat > bin/forker.sh <<'EOF'
#!/bin/sh
here=$(dirname "$0")
n=0
while [ "$n" -lt 12 ]; do
    "$here/child.sh" &
    n=$((n + 1))
done
wait
EOF
    chmod +x bin/*.sh
    echo base > top.txt
    echo base > src/x/f.txt
    echo base > skills/a/f.txt
    echo base > skills/b/f.txt
    echo base > docs/d.md
    if [ "$2" != NONE ]; then
        mkdir -p .claude/shirabe-extensions
        printf '%s\n' "$2" > .claude/shirabe-extensions/verification-map.json
    fi
    git add -A && git commit -q -m init
    git checkout -q -b work
}

# change <path>...: append to each path and commit.
change() {
    local p
    for p in "$@"; do
        mkdir -p "$(dirname "$p")"
        echo "change $RANDOM" >> "$p"
    done
    git add -A && git commit -q -m "change $*"
}

# map <commands json> <entries json> [<default json>]
map() {
    if [ $# -ge 3 ]; then
        jq -cn --argjson c "$1" --argjson e "$2" --argjson d "$3" \
            '{schema: "shirabe-verification-map/v1", commands: $c, entries: $e, default: $d}'
    else
        jq -cn --argjson c "$1" --argjson e "$2" \
            '{schema: "shirabe-verification-map/v1", commands: $c, entries: $e}'
    fi
}

# rec <file> <label>: a command that records its argv to <file>.
rec() { jq -cn --arg f "$1" --arg l "$2" '{run: ["bin/rec.sh", $f, $l]}'; }

# start <session>: run --start and assert it returned within two seconds.
# Whole seconds: a difference of at most 1 between two `date +%s` readings
# means less than two seconds passed.
start() {
    local t0 t1 rc
    t0=$(date +%s)
    "$START" --start --session "$1" >"$WORKDIR/start.out" 2>&1
    rc=$?
    t1=$(date +%s)
    [ "$rc" -eq 0 ] || fail "$1: --start exited $rc: $(cat "$WORKDIR/start.out")"
    if [ $((t1 - t0)) -le 1 ]; then
        pass "$1: --start returned in under two seconds"
    else
        fail "$1: --start took $((t1 - t0)) seconds"
    fi
}

# verdict <session>: one --verdict run; sets RC and OUT.
verdict() {
    OUT=$("$VERDICT" --verdict --session "$1" 2>"$WORKDIR/verdict.err")
    RC=$?
}

# settle <session>: --verdict until it stops saying pending, for at most 40s.
settle() {
    local n=0
    while :; do
        verdict "$1"
        [ "$RC" -ne 75 ] && return 0
        n=$((n + 1))
        [ "$n" -ge 160 ] && return 0
        sleep 0.25
    done
}

expect_rc() {
    if [ "$RC" -eq "$2" ]; then pass "$1: verdict exit $2"
    else fail "$1: verdict exit $RC, expected $2 (stderr: $(cat "$WORKDIR/verdict.err"); out: $OUT)"; fi
}

# expect_rule <label> <rule_id>: a finding with that rule_id, and every finding
# line parses as koto's finding shape.
expect_rule() {
    local line bad=0 found=0
    while IFS= read -r line; do
        case "$line" in
            ::koto-finding::*)
                printf '%s' "${line#::koto-finding::}" | jq -e '.rule_id and .level and .message and .rule_ref' >/dev/null 2>&1 || bad=1
                [ "$(printf '%s' "${line#::koto-finding::}" | jq -r .rule_id 2>/dev/null)" = "$2" ] && found=1 ;;
        esac
    done <<EOF
$OUT
EOF
    [ "$found" -eq 1 ] && pass "$1: finding $2" || fail "$1: no $2 finding in [$OUT]"
    [ "$bad" -eq 0 ] && pass "$1: every finding parses as koto's finding shape" || fail "$1: a finding line does not parse: [$OUT]"
}

expect_no_finding() {
    case "$OUT" in *::koto-finding::*) fail "$1: unexpected finding [$OUT]" ;; *) pass "$1: no finding" ;; esac
}

result_of() { sed -n 3p <<EOF
$("$START" --locate --session "$1")
EOF
}

group_alive() {
    ps -A -o pgid= 2>/dev/null | awk -v g="$1" '$1 == g { c++ } END { print c + 0 }'
}

# --- verdicts ---------------------------------------------------------------------------

echo "--- pass, pending, an older head"
mkrepo pass "$(map "{\"ok\": $(rec "$WORKDIR/pass.rec" ok)}" '[]' '["ok"]')"
change top.txt
verdict s-pass
expect_rc "no result yet" 75
start s-pass
settle s-pass
expect_rc "every command passes" 0
expect_no_finding "a pass"
[ -f "$KOTO_STUB_STORE/s-pass/verification_results.json" ] \
    && pass "a settled verdict records verification_results.json in koto context" \
    || fail "verification_results.json was not recorded"
change top.txt
verdict s-pass
expect_rc "a result for an older head only" 75

echo "--- a failing command"
mkrepo fail "$(map '{"bad": {"run": ["bin/fail.sh"]}}' '[]' '["bad"]')"
change top.txt
start s-fail
settle s-fail
expect_rc "a failing command" 1
expect_rule "a failing command" verification/command-failed

echo "--- a command that forks past max_procs"
mkrepo fork "$(map '{"forker": {"run": ["bin/forker.sh"], "max_procs": 4}}' '[]' '["forker"]')"
change top.txt
start s-fork
settle s-fork
expect_rc "forking past max_procs" 4
expect_rule "forking past max_procs" verification/runaway
PGID=$(jq -r '.commands[0].pgid' "$(result_of s-fork)")
case "$PGID" in
    ''|null) fail "the runaway result records no process group" ;;
    *) [ "$(group_alive "$PGID")" -eq 0 ] && pass "no process of the runaway's group ($PGID) is alive" \
           || fail "the runaway's group $PGID still has $(group_alive "$PGID") processes" ;;
esac

echo "--- a command past its timeout_secs"
mkrepo slow "$(map '{"slow": {"run": ["bin/slow.sh"], "timeout_secs": 1}}' '[]' '["slow"]')"
change top.txt
start s-slow
settle s-slow
expect_rc "past timeout_secs" 4
expect_rule "past timeout_secs" verification/timed-out
PGID=$(jq -r '.commands[0].pgid' "$(result_of s-slow)")
[ "$(group_alive "$PGID")" -eq 0 ] && pass "no process of the timed-out group is alive" \
    || fail "the timed-out group $PGID is still alive"

echo "--- a command that cannot start"
mkrepo nostart "$(map '{"gone": {"run": ["bin/missing.sh"]}}' '[]' '["gone"]')"
change top.txt
start s-nostart
settle s-nostart
expect_rc "run[0] does not exist" 4
expect_rule "run[0] does not exist" verification/not-started

echo "--- no map, a bad map, a map that selects nothing"
mkrepo nomap NONE
change top.txt
start s-nomap
settle s-nomap
expect_rc "no map at the merge-base" 3
expect_rule "no map at the merge-base" verification/no-map

mkrepo badmap '{"schema": "shirabe-verification-map/v1", "commands": {'
change top.txt
start s-badmap
settle s-badmap
expect_rc "a map that is not JSON" 3
expect_rule "a map that is not JSON" verification/bad-map

mkrepo badnet "$(map '{"net": {"run": ["bin/fail.sh"], "network": true}}' '[]' '["net"]')"
change top.txt
start s-badnet
settle s-badnet
expect_rc "a network command without unattended" 3
expect_rule "a network command without unattended" verification/bad-map

mkrepo nothing "$(map "{\"d\": $(rec "$WORKDIR/nothing.rec" d)}" '[{"paths": ["docs/**"], "commands": ["d"]}]')"
change top.txt
start s-nothing
settle s-nothing
expect_rc "a map that selects nothing" 3
expect_rule "a map that selects nothing" verification/no-map

echo "--- a map edited only on the branch"
mkrepo edited "$(map '{"bad": {"run": ["bin/fail.sh"]}}' '[]' '["bad"]')"
printf '%s\n' "$(map "{\"bad\": $(rec "$WORKDIR/edited.rec" ok)}" '[]' '["bad"]')" > .claude/shirabe-extensions/verification-map.json
git commit -q -am "branch edits the map"
start s-edited
settle s-edited
expect_rc "the branch's own map is not used" 1
[ ! -e "$WORKDIR/edited.rec" ] && pass "the branch's map command never ran" || fail "the branch's map command ran"

echo "--- a dirty tracked file"
mkrepo dirty "$(map "{\"ok\": $(rec "$WORKDIR/dirty.rec" ok)}" '[]' '["ok"]')"
change top.txt
echo uncommitted >> src/x/f.txt
start s-dirty
settle s-dirty
expect_rc "a dirty tracked file" 4
expect_rule "a dirty tracked file" verification/dirty-tree
[ ! -e "$WORKDIR/dirty.rec" ] && pass "nothing ran on a dirty tree" || fail "a command ran on a dirty tree"

echo "--- an attended command"
CMDS=$(jq -cn --arg f "$WORKDIR/attended.rec" '{a: {run: ["bin/rec.sh", $f, "a"], unattended: false}}')
mkrepo attended "$(map "$CMDS" '[]' '["a"]')"
change top.txt
start s-attended
settle s-attended
expect_rc "an unattended: false command" 4
expect_rule "an unattended: false command" verification/needs-person
[ ! -e "$WORKDIR/attended.rec" ] && pass "the attended command was never started" || fail "the attended command ran"

echo "--- an unreadable result"
mkrepo unread "$(map "{\"ok\": $(rec "$WORKDIR/unread.rec" ok)}" '[]' '["ok"]')"
change top.txt
start s-unread
settle s-unread
RES=$(result_of s-unread)
if [ "$(id -u)" -ne 0 ]; then
    chmod 000 "$RES"
    verdict s-unread
    expect_rc "a result file with no read permission" 2
    chmod 600 "$RES"
fi
echo '{"schema": "shirabe-verification-result/v1", "head": ' > "$RES"
verdict s-unread
expect_rc "a result file that does not parse" 2

# --- selection --------------------------------------------------------------------------

echo "--- selection"
R="$WORKDIR/sel.rec"
# Built in steps: bash 3.2 misparses a quoted jq filter nested two command
# substitutions deep.
CMDS=$(jq -cn --arg f "$R" '{A: {run: ["bin/rec.sh", $f, "A"]}, B: {run: ["bin/rec.sh", $f, "B"]},
    E: {run: ["bin/rec.sh", $f, "E"], each: "skills/*"}, D: {run: ["bin/rec.sh", $f, "D"]}}')
ENTRIES='[{"paths": ["src/**"], "commands": ["A"]}, {"paths": ["src/x/**"], "commands": ["B", "A"]}, {"paths": ["skills/**"], "commands": ["E"]}]'
MAP=$(map "$CMDS" "$ENTRIES" '["D"]')
mkrepo sel "$MAP"
change src/x/f.txt
start s-sel1
settle s-sel1
expect_rc "two matching entries" 0
[ "$(sort "$R" | tr '\n' ' ')" = "A B " ] && pass "a change matching two entries runs both entries' commands, A once" \
    || fail "two entries ran [$(tr '\n' ' ' < "$R")], expected A and B once each"

rm -f "$R"
change skills/a/f.txt skills/b/f.txt
start s-sel2
settle s-sel2
expect_rc "each over two skills" 0
# The branch now changes src/x and skills; only E's lines are about each.
[ "$(grep '^E' "$R" | tr '\n' ' ')" = "E a E b " ] && pass "an each command runs once per changed skill, a and b as the last argument" \
    || fail "each ran [$(tr '\n' ' ' < "$R")]"
jq -e '[.commands[] | select(.id == "E") | .argv[-1]] == ["a", "b"]' "$(result_of s-sel2)" >/dev/null \
    && pass "the result records each run's argv ending in a, then b" || fail "the result's argv for E is wrong"
grep -q '^D' "$R" && fail "the default ran though every changed path matches an entry" \
    || pass "the default does not run when every changed path matches an entry"

R2="$WORKDIR/sel2.rec"
CMDS=$(jq -cn --arg f "$R2" '{E: {run: ["bin/rec.sh", $f, "E"], each: "skills/*"}, D: {run: ["bin/rec.sh", $f, "D"]}}')
MAP=$(map "$CMDS" '[{"paths": ["skills/**"], "commands": ["E"]}]' '["D"]')
mkrepo seld "$MAP"
change top.txt
start s-seld
settle s-seld
expect_rc "an unmatched path" 0
[ "$(tr '\n' ' ' < "$R2")" = "D " ] && pass "the default runs for a path no entry matches, and the each command with no matching directory does not" \
    || fail "an unmatched path ran [$(tr '\n' ' ' < "$R2")]"

# --- the lock, the state directories ------------------------------------------------------

echo "--- a stale lock"
mkrepo lock "$(map "{\"ok\": $(rec "$WORKDIR/lock.rec" ok)}" '[]' '["ok"]')"
change top.txt
RES=$(result_of s-lock)
mkdir -p "$(dirname "$RES")"
sh -c 'exit 0' &
DEAD=$!
wait "$DEAD"
ln -s "$DEAD" "$(dirname "$RES")/lock"
start s-lock
settle s-lock
expect_rc "a stale lock whose process is gone" 0
[ -e "$WORKDIR/lock.rec" ] && pass "a stale lock does not block a new start" || fail "the stale lock blocked the start"

echo "--- directory modes and pruning"
mkrepo prune "$(map "{\"ok\": $(rec "$WORKDIR/prune.rec" ok)}" '[]' '["ok"]')"
n=0
while [ "$n" -lt 12 ]; do
    change top.txt
    "$START" --start --session s-prune >/dev/null 2>&1
    settle s-prune
    n=$((n + 1))
done
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
SDIR="$XDG_STATE_HOME/shirabe/verification/s-prune"
BAD=""
for d in "$XDG_STATE_HOME/shirabe" "$XDG_STATE_HOME/shirabe/verification" "$SDIR" "$SDIR"/*; do
    [ "$(mode_of "$d")" = 700 ] || BAD="$BAD $d=$(mode_of "$d")"
done
[ -z "$BAD" ] && pass "every state directory has mode 0700" || fail "directories not 0700:$BAD"
COUNT=$(ls "$SDIR" | wc -l | tr -d ' ')
[ "$COUNT" -eq 10 ] && pass "twelve heads leave ten head directories" || fail "twelve heads left $COUNT directories"
[ -d "$SDIR/$(git rev-parse HEAD)" ] && pass "the current head's directory is kept" || fail "the current head's directory was pruned"

# --- what the scripts must not use -----------------------------------------------------------

echo "--- portability"
for f in "$START" "$VERDICT"; do
    c=$(grep -c -E '\bsetsid\b|\btimeout ' "$f")
    [ "$c" -eq 0 ] && pass "$(basename "$f") uses neither setsid nor GNU timeout" || fail "$(basename "$f"): $c matches"
done

# --- a real koto ---------------------------------------------------------------------------

echo "--- engine: the launcher as a default_action, the verdict as a poll: gate"
if [ -z "$REAL_KOTO" ]; then
    echo "SKIP: koto not on PATH -- the engine case did not run"
else
    export PATH="${PATH#"$WORKDIR/bin:"}"
    mkrepo engine "$(map "{\"ok\": $(rec "$WORKDIR/engine.rec" ok)}" '[]' '["ok"]')"
    change top.txt
    TPL="$WORKDIR/rv-fixture.md"
    cat > "$TPL" <<EOF
---
name: rv-fixture
version: "1.0"
description: the verification state's launcher and verdict, alone
initial_state: verification
states:
  verification:
    default_action:
      command: '"$START" --start --session "{{SESSION_NAME}}"'
    gates:
      verdict:
        type: command
        command: '"$VERDICT" --verdict --session "{{SESSION_NAME}}"'
        poll:
          interval_secs: 1
          timeout_secs: 120
          hold_secs: 20
    transitions:
      - target: passed
        when:
          gates.verdict.exit_code: 0
      - target: implementation
        when:
          gates.verdict.exit_code: 1
  passed:
    terminal: true
  implementation:
    terminal: true
---

## verification

Verify.

## passed

Passed.

## implementation

Fix.
EOF
    S=rv-engine
    if ! koto init "$S" --template "$TPL" >"$WORKDIR/init.out" 2>&1; then
        fail "engine: koto init failed: $(cat "$WORKDIR/init.out")"
    else
        STATE=""
        n=0
        while [ "$n" -lt 6 ]; do
            koto next "$S" --no-cleanup >"$WORKDIR/next.out" 2>&1
            STATE=$(koto status "$S" 2>/dev/null | jq -r '.current_state // empty')
            [ "$STATE" = verification ] || break
            n=$((n + 1))
        done
        [ "$STATE" = passed ] && pass "engine: koto routed the verdict to [passed]" \
            || fail "engine: the session is at [$STATE]: $(head -c 600 "$WORKDIR/next.out")"
        koto context get "$S" verification_results.json 2>/dev/null | jq -e '.status == "done"' >/dev/null \
            && pass "engine: the verdict recorded verification_results.json in the session" \
            || fail "engine: no verification_results.json in the session"
    fi
    export PATH="$STUB_PATH"
fi

# --- nothing left behind --------------------------------------------------------------------

sleep 1
LEFT=""
command -v pgrep >/dev/null 2>&1 && LEFT=$(pgrep -f "$MARK" 2>/dev/null | grep -v "^$$\$" | tr '\n' ' ')
[ -z "$LEFT" ] && pass "no process this suite started is still running" || fail "left running: $LEFT"

echo
echo "run-verification_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
