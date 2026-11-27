#!/usr/bin/env bash
# verification-pool_test.sh -- does work-on's local suite run on koto's host
# pool `suite`, so a second suite on a host that limits them waits its turn in
# the verification state and runs when the first is done?
# Part of the work-on skill
#
# work-on.md's `verification` state starts the verification map's commands
# with run-verification.sh --start. That action names `pool: suite` and is a
# koto background action (`background: true`, `timeout_secs`), and its command
# goes on to run-verification.sh --hold, which stays while the supervisor
# runs, so koto holds the pool slot for the length of the suite.
#
# This file checks:
#
#   1. Static, no engine, from the shipped template's source: every state
#      whose default_action starts the launcher names `pool: suite`,
#      `background: true` and a `timeout_secs` no shorter than the launcher's
#      own budget, and runs --hold after --start; no other state names a
#      pool; no state carries a key that would size the pool; and the
#      verification directive says what `queued` and `running` mean.
#   2. run-verification.sh --hold, no engine, against a git fixture and a
#      stand-in supervisor: it returns at once without koto's background
#      marker or with another session's, waits with this session's until the
#      supervisor ends, and with --at-most waits no longer than that.
#   3. Engine, on a koto that has pools: a fixture whose one working state
#      carries the SHIPPED default_action, with stand-ins for the two scripts
#      under a stand-in PLUGIN_ROOT, on a host config that defines
#      [pools.suite] with size 1. The first session's tick starts its run;
#      the second's answers a `__pool__` condition with status `queued`, runs
#      no launcher, and leaves the session in verification, not terminal;
#      a later tick, once the first run has ended, starts the second's run,
#      and both sessions reach the passing terminal. With no pool defined two
#      sessions run at once.
#
# Part 3 skips, loudly, when koto is not on PATH or has no `koto pool`
# (a koto older than 0.40.0, where the action runs inside the tick and no
# pool exists).
#
# Usage: verification-pool_test.sh
# Exit codes: 0 all pass (or the engine part skipped), 1 any failed, 2 the
# harness could not run.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
LAUNCHER="$SCRIPT_DIR/run-verification.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: want [$2], got [$3]"; fi; }

[ -f "$TEMPLATE" ] || { echo "template not found: $TEMPLATE" >&2; exit 2; }
[ -x "$LAUNCHER" ] || { echo "launcher not found: $LAUNCHER" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required to run this suite" >&2; exit 2; }
command -v git >/dev/null || { echo "git is required to run this suite" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/verification-pool.XXXXXX") || exit 1
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 1
STANDIN_PID=""
cleanup() {
    # Every stand-in waits on a file under WORKDIR, so removing them ends
    # each one, and with it the koto runner that waits on it.
    case "${WORKDIR:-}" in
        */verification-pool.*)
            rm -f "$WORKDIR"/busy-* 2>/dev/null
            case "$STANDIN_PID" in ''|*[!0-9]*) ;; *) kill "$STANDIN_PID" 2>/dev/null ;; esac
            sleep 1
            rm -rf "$WORKDIR" ;;
    esac
    return 0
}
ktg_on_exit cleanup

# frontmatter: the template's YAML, between its first two `---` lines.
frontmatter() {
    awk '/^---$/ { n++; next } n == 1 { print } n >= 2 { exit }' "$TEMPLATE"
}

# action_of <state>: the state's default_action block, its key line included.
action_of() {
    frontmatter | awk -v want="  $1:" '
        $0 == want { instate = 1; next }
        instate && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        instate && /^    default_action:$/ { inact = 1; print; next }
        inact && /^    [a-z_]+:/ { exit }
        inact && /^    #/ { next }
        inact { print }'
}

# action_field <state> <key>: the scalar value of a default_action key.
action_field() {
    action_of "$1" | awk -v k="      $2:" 'index($0, k) == 1 { sub(/^[^:]*: */, ""); print; exit }'
}

# states_with <pattern>: the states whose default_action block has a line
# matching the fixed string <pattern>, one per line.
states_with() {
    frontmatter | awk -v pat="$1" '
        /^states:$/ { on = 1; next }
        !on { next }
        /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { st = $1; sub(/:$/, "", st); inact = 0; next }
        /^    default_action:$/ { inact = 1; next }
        inact && /^    [a-z_]+:/ { inact = 0 }
        inact && !/^ *#/ && index($0, pat) > 0 && !(st in seen) { seen[st] = 1; print st }'
}

# --- 1. static -----------------------------------------------------------------------------

echo "--- static: the pool on every state that starts the suite"

STARTERS=$(states_with 'run-verification.sh" --start')
eq "the states whose action starts the launcher" "verification" "$(printf '%s' "$STARTERS" | tr '\n' ' ' | sed 's/ $//')"
eq "the states whose action names a pool" "verification" "$(states_with '      pool:' | tr '\n' ' ' | sed 's/ $//')"
eq "no state's action runs check-skill.sh itself" "" "$(states_with 'check-skill.sh')"

BUDGET=$(sed -n 's/^BUDGET_SECS=\([0-9][0-9]*\)$/\1/p' "$LAUNCHER")
case "$BUDGET" in ''|*[!0-9]*) fail "could not read BUDGET_SECS from the launcher: [$BUDGET]"; BUDGET=0 ;; esac

for st in $STARTERS; do
    eq "$st: pool" "suite" "$(action_field "$st" pool)"
    eq "$st: background" "true" "$(action_field "$st" background)"
    T=$(action_field "$st" timeout_secs)
    case "$T" in
        ''|*[!0-9]*) fail "$st: timeout_secs is [$T], want a whole number" ;;
        *)
            if [ "$T" -ge "$BUDGET" ] && [ "$T" -le 86400 ]; then
                pass "$st: timeout_secs $T covers the launcher's $BUDGET-second budget"
            else
                fail "$st: timeout_secs $T is outside [$BUDGET, 86400]"
            fi ;;
    esac
    CMD=$(action_field "$st" command)
    case "$CMD" in
        *'run-verification.sh" --start --session "{{SESSION_NAME}}" && "{{PLUGIN_ROOT}}/skills/work-on/scripts/run-verification.sh" --hold --session "{{SESSION_NAME}}"'"'") \
            pass "$st: the command runs --hold after --start, for the same session" ;;
        *) fail "$st: the command does not end in --start then --hold: [$CMD]" ;;
    esac
    for k in polling requires_confirmation; do
        eq "$st: no $k, which a background action can't carry" "" "$(action_field "$st" "$k")"
    done
done

# koto refuses a template that sizes a pool; the host does that.
SIZED=$(frontmatter | grep -n -E '^ +(size|claim_secs|lapse_secs|wait_secs):' || true)
eq "no state sizes the pool" "" "$SIZED"

DIRECTIVE=$(awk '/^## verification$/ { on = 1; next } on && /^## / { exit } on { print }' "$TEMPLATE")
for want in '`__pool__`, status `queued`' '`__action__`, status `running`' 'koto pool status' \
    '--hold --session "{{SESSION_NAME}}" --at-most'; do
    case "$DIRECTIVE" in
        *"$want"*) pass "the verification directive says [$want]" ;;
        *) fail "the verification directive lacks [$want]" ;;
    esac
done

# --- 2. --hold -----------------------------------------------------------------------------

echo "--- --hold: waits only as a background action's command, or with --at-most"

export XDG_STATE_HOME="$WORKDIR/state"
REPO="$WORKDIR/repo"
mkdir -p "$REPO"
(
    cd "$REPO" || exit 1
    git init -q -b main . || exit 1
    git config user.email suite@example.invalid
    git config user.name suite
    git config commit.gpgsign false
    echo base > base.txt
    git add base.txt && git commit -q -m base || exit 1
    git checkout -q -b work
    echo change > change.txt
    git add change.txt && git commit -q -m change
) >"$WORKDIR/repo.out" 2>&1 || { echo "could not build the git fixture: $(cat "$WORKDIR/repo.out")" >&2; exit 2; }

HS=pool-hold
RESULT_PATH=$(cd "$REPO" && "$LAUNCHER" --locate --session "$HS" 2>"$WORKDIR/locate.err" | sed -n 3p)
[ -n "$RESULT_PATH" ] || { echo "--locate printed no result path: $(cat "$WORKDIR/locate.err")" >&2; exit 2; }
HEAD_DIR=$(dirname "$RESULT_PATH")
mkdir -p "$HEAD_DIR"

# A stand-in supervisor: the launcher counts a lock as live when its pid runs
# a command named run-verification.sh.
mkdir -p "$WORKDIR/standin"
cat > "$WORKDIR/standin/run-verification.sh" <<'EOF'
#!/usr/bin/env bash
while [ -e "$1" ]; do sleep 0.2; done
EOF
chmod +x "$WORKDIR/standin/run-verification.sh"

standin_start() {
    : > "$WORKDIR/busy-standin"
    "$WORKDIR/standin/run-verification.sh" "$WORKDIR/busy-standin" &
    STANDIN_PID=$!
    rm -f "$HEAD_DIR/lock"
    ln -s "$STANDIN_PID" "$HEAD_DIR/lock"
}
standin_stop() {
    rm -f "$WORKDIR/busy-standin"
    wait "$STANDIN_PID" 2>/dev/null
    rm -f "$HEAD_DIR/lock"
    STANDIN_PID=""
}

# hold_run <marker or ""> [args...]: run --hold with KOTO_BACKGROUND_OF set
# to <marker>, or unset; sets HOLD_RC and HOLD_TOOK (whole seconds).
hold_run() {
    local marker=$1 t0=$SECONDS
    shift
    if [ -n "$marker" ]; then
        (cd "$REPO" && KOTO_BACKGROUND_OF="$marker" "$LAUNCHER" --hold --session "$HS" "$@") >"$WORKDIR/hold.out" 2>&1
    else
        (cd "$REPO" && unset KOTO_BACKGROUND_OF && "$LAUNCHER" --hold --session "$HS" "$@") >"$WORKDIR/hold.out" 2>&1
    fi
    HOLD_RC=$?
    HOLD_TOOK=$((SECONDS - t0))
}

standin_start
hold_run ""
if [ "$HOLD_RC" -eq 0 ] && [ "$HOLD_TOOK" -le 2 ]; then
    pass "--hold without koto's background marker returns at once beside a live supervisor (0)"
else
    fail "--hold without the marker: exit $HOLD_RC after ${HOLD_TOOK}s: $(cat "$WORKDIR/hold.out")"
fi
hold_run "another-session"
if [ "$HOLD_RC" -eq 0 ] && [ "$HOLD_TOOK" -le 2 ]; then
    pass "--hold with another session's marker returns at once (0)"
else
    fail "--hold with another session's marker: exit $HOLD_RC after ${HOLD_TOOK}s: $(cat "$WORKDIR/hold.out")"
fi

# With this session's marker it stays while the supervisor lives.
(cd "$REPO" && KOTO_BACKGROUND_OF="$HS" "$LAUNCHER" --hold --session "$HS"; echo "$?" > "$WORKDIR/hold.rc") >"$WORKDIR/hold.out" 2>&1 &
HOLD_PID=$!
sleep 4
if [ ! -e "$WORKDIR/hold.rc" ] && kill -0 "$HOLD_PID" 2>/dev/null; then
    pass "--hold with this session's marker is still waiting after 4 seconds of a live supervisor"
else
    fail "--hold with this session's marker did not wait: rc file [$(cat "$WORKDIR/hold.rc" 2>/dev/null)]: $(cat "$WORKDIR/hold.out")"
fi
standin_stop
n=0
while [ "$n" -lt 80 ] && [ ! -e "$WORKDIR/hold.rc" ]; do sleep 0.1; n=$((n + 1)); done
eq "--hold exits 0 once the supervisor has ended" "0" "$(cat "$WORKDIR/hold.rc" 2>/dev/null)"
wait "$HOLD_PID" 2>/dev/null

hold_run "$HS"
if [ "$HOLD_RC" -eq 0 ] && [ "$HOLD_TOOK" -le 2 ]; then
    pass "--hold with the marker and no supervisor returns at once (0)"
else
    fail "--hold with no supervisor: exit $HOLD_RC after ${HOLD_TOOK}s: $(cat "$WORKDIR/hold.out")"
fi

standin_start
hold_run "" --at-most 3
if [ "$HOLD_RC" -eq 0 ] && [ "$HOLD_TOOK" -ge 2 ] && [ "$HOLD_TOOK" -le 8 ]; then
    pass "--hold --at-most 3 waits beside a live supervisor without the marker, and gives up after about 3 seconds (0)"
else
    fail "--hold --at-most 3: exit $HOLD_RC after ${HOLD_TOOK}s: $(cat "$WORKDIR/hold.out")"
fi
standin_stop
hold_run "" --at-most 30
if [ "$HOLD_RC" -eq 0 ] && [ "$HOLD_TOOK" -le 2 ]; then
    pass "--hold --at-most returns at once when no supervisor is running (0)"
else
    fail "--hold --at-most with no supervisor: exit $HOLD_RC after ${HOLD_TOOK}s"
fi
for bad in 0 -1 abc 3601 007 ""; do
    hold_run "" --at-most "$bad"
    eq "--hold --at-most [$bad] is a usage error" "2" "$HOLD_RC"
done
(cd "$REPO" && "$LAUNCHER" --locate --session "$HS" --at-most 5) >/dev/null 2>&1
eq "--at-most belongs to --hold alone" "2" "$?"

# --- 3. engine -----------------------------------------------------------------------------

echo "--- engine: a full pool queues the second suite in verification"

if ! command -v koto >/dev/null; then
    echo "SKIP: koto not on PATH -- the engine cases did not run"
    echo
    echo "verification-pool_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit
fi
if ! koto pool status >"$WORKDIR/pool-probe.out" 2>"$WORKDIR/pool-probe.err"; then
    echo "SKIP: this koto has no host pools ($(koto version 2>/dev/null | head -n 1)) -- the engine cases did not run"
    echo
    echo "verification-pool_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit
fi

# Stand-ins for the launcher under a stand-in plugin root. --start records
# the call; --hold stays while the session's busy file exists, as the real one
# stays while its supervisor runs.
ROOT="$WORKDIR/plugin"
mkdir -p "$ROOT/skills/work-on/scripts"
cat > "$ROOT/skills/work-on/scripts/run-verification.sh" <<EOF
#!/usr/bin/env bash
W="$WORKDIR"
EOF
cat >> "$ROOT/skills/work-on/scripts/run-verification.sh" <<'EOF'
mode=$1
session=$3
printf '%s %s marker=%s\n' "$mode" "$session" "${KOTO_BACKGROUND_OF:-}" >> "$W/calls.log"
case "$mode" in
    --start) : > "$W/started-$session" ;;
    --hold) while [ -e "$W/busy-$session" ]; do sleep 0.2; done ;;
esac
exit 0
EOF
chmod +x "$ROOT/skills/work-on/scripts/run-verification.sh"

SHIPPED_ACTION=$(action_of verification)
[ -n "$SHIPPED_ACTION" ] || { echo "could not extract verification's default_action" >&2; exit 2; }
FIXTURE="$WORKDIR/fixture.md"
{
    printf '%s\n' '---' 'name: verification-pool-fixture' 'version: "1.0"' \
        'description: The shipped verification action, on a pool.' 'initial_state: start' \
        'variables:' '  PLUGIN_ROOT:' '    description: plugin root' '    required: true' \
        'states:' '  start:' '    transitions:' '      - target: verification' \
        '  verification:'
    printf '%s\n' "$SHIPPED_ACTION"
    printf '%s\n' '    gates:' '      suite_ended:' '        type: command' \
        "        command: 'test ! -e \"$WORKDIR/busy-{{SESSION_NAME}}\"'" \
        '    transitions:' '      - target: passed' '        when:' '          gates.suite_ended.exit_code: 0' \
        '  passed:' '    terminal: true' '---' '' '## start' '' 'Start.' '' '## verification' '' 'Verify.' \
        '' '## passed' '' 'Passed.'
} > "$FIXTURE"

ENGINE_DIR="$WORKDIR/engine"
mkdir -p "$ENGINE_DIR" "$HOME/.koto"
POOL_CONFIG="$HOME/.koto/config.toml"
printf '%s\n' '[pools.suite]' 'size = 1' 'wait_secs = 0' > "$POOL_CONFIG"

# raw_tick <session>: one tick as koto answers it, not the guard's settled
# answer: these cases are about the ticks a wait is made of.
raw_tick() {
    RESP=$(cd "$ENGINE_DIR" && command koto next "$1" --no-cleanup 2>"$WORKDIR/tick.err")
    TICK_RC=$?
}
cond() { printf '%s' "$RESP" | jq -r --arg n "$1" --arg f "$2" '[.blocking_conditions[]? | select(.name == $n)][0] | getpath($f | split(".")) | if . == null then "" else tostring end' 2>/dev/null; }
state_of() { (cd "$ENGINE_DIR" && command koto status "$1" 2>/dev/null) | jq -r '.current_state // ""' 2>/dev/null; }
terminal_of() { (cd "$ENGINE_DIR" && command koto status "$1" 2>/dev/null) | jq -r '.is_terminal | if . == null then "" else tostring end' 2>/dev/null; }
open_session() {
    : > "$WORKDIR/busy-$1"
    (cd "$ENGINE_DIR" && command koto init "$1" --template "$FIXTURE" --var PLUGIN_ROOT="$ROOT") >"$WORKDIR/init.out" 2>&1
}
# tick_until <session> <state> <condition name or ""> : raw ticks, at most
# 100 a tenth of a second apart, until the session answers so.
tick_until() {
    local n=0
    while [ "$n" -lt 100 ]; do
        raw_tick "$1"
        if [ "$(printf '%s' "$RESP" | jq -r '.state // ""' 2>/dev/null)" = "$2" ]; then
            [ -z "$3" ] && return 0
            [ -n "$(cond "$3" name)" ] && return 0
        fi
        sleep 0.1
        n=$((n + 1))
    done
    return 1
}

if ! open_session pool-a || ! open_session pool-b; then
    fail "engine: koto init failed: $(head -c 400 "$WORKDIR/init.out")"
else
    raw_tick pool-a
    eq "first session: its tick stops in verification" "verification" "$(printf '%s' "$RESP" | jq -r '.state // ""')"
    eq "first session: the tick answers a running __action__" "running" "$(cond __action__ status)"
    eq "first session: the run holds the suite pool" "suite" "$(cond __action__ output.pool)"
    n=0
    while [ "$n" -lt 50 ] && [ ! -e "$WORKDIR/started-pool-a" ]; do sleep 0.1; n=$((n + 1)); done
    [ -e "$WORKDIR/started-pool-a" ] && pass "first session: koto ran the launcher's --start" \
        || fail "first session: --start never ran: $(cat "$WORKDIR/calls.log" 2>/dev/null)"
    n=0
    while [ "$n" -lt 50 ] && ! grep -q '^--hold pool-a marker=pool-a$' "$WORKDIR/calls.log" 2>/dev/null; do sleep 0.1; n=$((n + 1)); done
    grep -q '^--hold pool-a marker=pool-a$' "$WORKDIR/calls.log" 2>/dev/null \
        && pass "first session: --hold ran after it, with koto's background marker naming the session" \
        || fail "first session: no --hold call carrying the marker: $(cat "$WORKDIR/calls.log" 2>/dev/null)"

    raw_tick pool-b
    eq "second session, pool full: the tick exits 0" "0" "$TICK_RC"
    eq "second session, pool full: action is gate_blocked" "gate_blocked" "$(printf '%s' "$RESP" | jq -r '.action // ""')"
    eq "second session, pool full: the condition is __pool__, queued" "queued" "$(cond __pool__ status)"
    eq "second session, pool full: the wait is temporal" "temporal" "$(cond __pool__ category)"
    eq "second session, pool full: nothing for the agent to fix" "false" "$(cond __pool__ agent_actionable)"
    eq "second session, pool full: the holder is the first session" "pool-a" \
        "$(printf '%s' "$RESP" | jq -r '[.blocking_conditions[]? | select(.name == "__pool__")][0].output.holders[0].session // ""')"
    eq "second session, pool full: it is in verification" "verification" "$(state_of pool-b)"
    eq "second session, pool full: the session is not terminal" "false" "$(terminal_of pool-b)"
    [ ! -e "$WORKDIR/started-pool-b" ] && pass "second session, pool full: its launcher did not run" \
        || fail "second session, pool full: the launcher ran while the pool was full"

    raw_tick pool-b
    eq "second session, a second tick: still queued" "queued" "$(cond __pool__ status)"
    eq "second session, a second tick: still in verification" "verification" "$(state_of pool-b)"
    [ ! -e "$WORKDIR/started-pool-b" ] && pass "second session, a second tick: its launcher still did not run" \
        || fail "second session, a second tick: the launcher ran while the pool was full"

    STATUS=$(cd "$ENGINE_DIR" && command koto pool status --json 2>/dev/null)
    eq "koto pool status: one holder, one waiter" "1 1" \
        "$(printf '%s' "$STATUS" | jq -r '[.pools[]? | select(.name == "suite")][0] | "\(.held) \(.waiting)"' 2>/dev/null)"

    # The first suite ends: its session passes, and the second's next ticks
    # take the slot and start its run.
    rm -f "$WORKDIR/busy-pool-a"
    tick_until pool-a passed "" && pass "first session: reaches passed once its suite has ended" \
        || fail "first session: never reached passed: $(head -c 400 <<<"$RESP")"

    if tick_until pool-b verification __action__; then
        pass "second session: a later tick resumes it from the queue and starts its run"
    else
        fail "second session: never left the queue: $(head -c 400 <<<"$RESP")"
    fi
    n=0
    while [ "$n" -lt 50 ] && [ ! -e "$WORKDIR/started-pool-b" ]; do sleep 0.1; n=$((n + 1)); done
    [ -e "$WORKDIR/started-pool-b" ] && pass "second session: its launcher ran once the slot was free" \
        || fail "second session: --start never ran: $(cat "$WORKDIR/calls.log" 2>/dev/null)"
    rm -f "$WORKDIR/busy-pool-b"
    tick_until pool-b passed "" && pass "second session: reaches passed once its own suite has ended" \
        || fail "second session: never reached passed: $(head -c 400 <<<"$RESP")"
fi

# No pool defined: nothing is limited, and two sessions run at once.
echo "--- engine: no [pools.suite] on the host, no limit"
rm -f "$POOL_CONFIG"
if ! open_session free-a || ! open_session free-b; then
    fail "engine: koto init failed: $(head -c 400 "$WORKDIR/init.out")"
else
    raw_tick free-a
    eq "no pool defined, first session: a running __action__" "running" "$(cond __action__ status)"
    raw_tick free-b
    eq "no pool defined, second session: a running __action__ too" "running" "$(cond __action__ status)"
    eq "no pool defined, second session: no __pool__ condition" "" "$(cond __pool__ name)"
    n=0
    while [ "$n" -lt 50 ] && { [ ! -e "$WORKDIR/started-free-a" ] || [ ! -e "$WORKDIR/started-free-b" ]; }; do sleep 0.1; n=$((n + 1)); done
    [ -e "$WORKDIR/started-free-a" ] && [ -e "$WORKDIR/started-free-b" ] \
        && pass "no pool defined: both launchers ran while both suites were still going" \
        || fail "no pool defined: started files: $(ls "$WORKDIR" | grep '^started-free' | tr '\n' ' ')"
    rm -f "$WORKDIR/busy-free-a" "$WORKDIR/busy-free-b"
    tick_until free-a passed "" && tick_until free-b passed "" \
        && pass "no pool defined: both sessions reach passed" \
        || fail "no pool defined: a session never reached passed: $(head -c 400 <<<"$RESP")"
fi

echo
echo "verification-pool_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
