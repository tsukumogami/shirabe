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
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

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

# Every finding the verdicts below print is logged and verified against the
# rule registry at the end.
# shellcheck source=../../../scripts/lib/rule-findings-testlib.sh
. "$SCRIPT_DIR/../../../scripts/lib/rule-findings-testlib.sh"
rf_test_setup "$WORKDIR"

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
    printf '#!/bin/sh\nsleep "${NAP_SECS:-1}"\n' > bin/nap.sh
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

# --- how long --start may take ------------------------------------------------------
#
# --start must return without waiting for the commands it starts. A fixed
# wall-clock bound turns host load into a failure, so each start is measured
# against a reference workload timed just before it, in the same repository:
# --locate, which is the same script's startup and resolve, then the git and
# jq calls --start makes after it (status, ls-tree, show, diff, and the map's
# jq passes). That is about the same number of git and jq processes --start
# runs, so load slows both alike. --start may take START_MULT times the
# reference, never less than START_FLOOR_MS, which keeps a quiet host's check
# as loose as the two seconds it replaced, and never more than
# START_CEILING_MS, so a real hang still fails however slow the reference was.
START_MULT=4
START_FLOOR_MS=2000
START_CEILING_MS=30000

# A millisecond clock. bash 3.2 has no EPOCHREALTIME and macOS `date` has no
# %N, so python3 is used when it is there -- both CI legs have it -- and whole
# seconds otherwise, which the floor absorbs.
PY=$(command -v python3 2>/dev/null || true)
now_ms() {
    if [ -n "$PY" ]; then
        "$PY" -c 'import time; print(int(time.time()*1000))'
    else
        printf '%s\n' "$(( $(date +%s) * 1000 ))"
    fi
}

# reference_work <session>: the reference workload, run in the current
# repository. Read-only: it starts nothing and writes no state.
reference_work() {
    local mb mp=.claude/shirabe-extensions/verification-map.json json
    mb=$("$START" --locate --session "$1" 2>/dev/null | sed -n 2p)
    [ -n "$mb" ] || mb=HEAD
    git status --porcelain --untracked-files=no >/dev/null 2>&1
    git ls-tree "$mb" -- "$mp" >/dev/null 2>&1
    json=$(git show "$mb:$mp" 2>/dev/null) || json='{}'
    git diff --name-only -z "$mb..HEAD" 2>/dev/null | jq -Rs 'split("\u0000")' >/dev/null 2>&1
    printf '%s' "$json" | jq -se 'length == 1' >/dev/null 2>&1
    printf '%s' "$json" | jq -c '.commands // {} | to_entries' >/dev/null 2>&1
    printf '%s' "$json" | jq -r '.error // empty' >/dev/null 2>&1
    printf '%s' "$json" | jq '.entries // [] | length' >/dev/null 2>&1
    printf '%s' "$json" | jq -r '.default // [] | join(", ")' >/dev/null 2>&1
    jq -cn --arg mb "$mb" --argjson sel "$json" '{merge_base: $mb, sel: $sel}' >/dev/null 2>&1
    return 0
}

# start_bound_ms <reference ms>: how long --start may take.
start_bound_ms() {
    local b=$(( START_MULT * $1 ))
    [ "$b" -ge "$START_FLOOR_MS" ] || b=$START_FLOOR_MS
    [ "$b" -le "$START_CEILING_MS" ] || b=$START_CEILING_MS
    printf '%s\n' "$b"
}

# timed_start <launcher> <session>: time the reference, then the launcher's
# --start. Sets START_RC, REF_MS, START_MS and BOUND_MS.
timed_start() {
    local t0 t1
    t0=$(now_ms)
    reference_work "$2"
    t1=$(now_ms)
    REF_MS=$((t1 - t0))
    BOUND_MS=$(start_bound_ms "$REF_MS")
    t0=$(now_ms)
    START_BOUND_MS=$BOUND_MS "$1" --start --session "$2" >"$WORKDIR/start.out" 2>&1
    START_RC=$?
    t1=$(now_ms)
    START_MS=$((t1 - t0))
}

# start <session>: run --start and assert it returned within its bound.
start() {
    timed_start "$START" "$1"
    [ "$START_RC" -eq 0 ] || fail "$1: --start exited $START_RC: $(cat "$WORKDIR/start.out")"
    if [ "$START_MS" -le "$BOUND_MS" ]; then
        pass "$1: --start returned in ${START_MS}ms, within its bound of ${BOUND_MS}ms (reference ${REF_MS}ms)"
    else
        fail "$1: --start took ${START_MS}ms, past its bound of ${BOUND_MS}ms (reference ${REF_MS}ms)"
    fi
}

# verdict <session>: one --verdict run; sets RC and OUT.
verdict() {
    OUT=$("$VERDICT" --verdict --session "$1" 2>"$WORKDIR/verdict.err")
    RC=$?
}

# same_laddered_verdict <label> <session>: --verdict with the escalation
# ladder's context (a session log where koto recorded verification_verdict
# failing once on verification/command-failed) exits and prints on standard
# output exactly what it does without, and adds no ::shirabe- line to stderr
# when it printed no finding.
same_laddered_verdict() {
    local plain_out plain_rc log="$WORKDIR/ladder-same.jsonl"
    verdict "$2"; plain_out=$OUT; plain_rc=$RC
    rf_test_ladder_log "$log" verification verification_verdict verification/command-failed 1
    OUT=$(SHIRABE_GATE_LOG="$log" SHIRABE_GATE_NAME=verification_verdict \
        SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" \
        "$VERDICT" --verdict --session "$2" 2>"$WORKDIR/verdict.err")
    RC=$?
    if [ "$RC" -eq "$plain_rc" ] && [ "$OUT" = "$plain_out" ] \
        && { case "$OUT" in *::koto-finding::*) true ;; *) ! grep -q '^::shirabe-' "$WORKDIR/verdict.err" ;; esac; }; then
        pass "$1: exits and prints the same with the ladder's context"
    else
        fail "$1: differs with the ladder's context: rc $RC vs $plain_rc, stderr $(cat "$WORKDIR/verdict.err")"
    fi
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
same_laddered_verdict "a pass, laddered" s-pass
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
REF=$(printf '%s\n' "$OUT" | sed -n 's/^::koto-finding:://p' | jq -r 'select(.rule_id == "verification/command-failed") | .rule_ref')
REF=${REF%%$'\n'*}
WANT_RANGE=$(rf_test_expected_range verification/command-failed)
[ "${REF%@*}" = "$WANT_RANGE" ] && pass "a failing command: verification/command-failed's range is $WANT_RANGE, found from its anchors with grep" \
    || fail "a failing command: range [${REF%@*}], want [$WANT_RANGE]"
# The escalation ladder: koto already recorded the verdict gate failing once on
# the rule, so the template's context releases its text and changes nothing else.
PLAIN_OUT=$OUT; PLAIN_RC=$RC
LADDER_LOG="$WORKDIR/ladder.jsonl"
rf_test_ladder_log "$LADDER_LOG" verification verification_verdict verification/command-failed 1
OUT=$(SHIRABE_GATE_LOG="$LADDER_LOG" SHIRABE_GATE_NAME=verification_verdict \
    SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" \
    "$VERDICT" --verdict --session s-fail 2>"$WORKDIR/verdict.err")
RC=$?
if [ "$RC" -eq "$PLAIN_RC" ] && [ "$OUT" = "$PLAIN_OUT" ] \
    && [ "$(grep -c '^::shirabe-rule::{"rule_id":"verification/command-failed"' "$WORKDIR/verdict.err")" -eq 1 ] \
    && ! grep -q '^::shirabe-check-exit::' "$WORKDIR/verdict.err"; then
    pass "a failing command, laddered: a second failure releases the rule's text and changes nothing else"
else
    fail "a failing command, laddered: rc $RC, stderr $(cat "$WORKDIR/verdict.err")"
fi
rf_test_refusals "--verdict" skills/work-on/scripts/check-verification.sh verification/command-failed --verdict --session s-fail

# The same result against plugin copies with verification/command-failed at
# each stage: its finding prints at the stage's level, and only at block does
# it route the run back (1).
VERDICT_PATHS="skills/work-on/scripts/check-verification.sh skills/work-on/scripts/run-verification.sh"
verdict_in_copy() { # <copy>
    cd "$WORKDIR/r-fail" && "$1/skills/work-on/scripts/check-verification.sh" --verdict --session s-fail
}
# shellcheck disable=SC2086 # the two paths, split on purpose
rf_test_stages "--verdict" verification/command-failed 1 "" verdict_in_copy $VERDICT_PATHS

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

echo "--- a run past its total budget"
# Two commands, each well inside its own timeout_secs, under a 5-second budget
# for the whole run: the first is stopped at the budget, the second never starts.
# The budget's clock starts with the supervisor, so its setup before the first
# command counts against it; 5 seconds leaves a loaded host room for that and
# is still far short of bin/slow.sh's 30-second sleep. The time the case checks
# is the supervisor's own record of the stopped command, not this harness's
# wall clock, which also counts starting the supervisor and settling (#1063).
mkrepo budget "$(map '{"a": {"run": ["bin/slow.sh"], "timeout_secs": 60}, "b": {"run": ["bin/slow.sh"], "timeout_secs": 60}}' '[]' '["a", "b"]')"
change top.txt
BUDGET_S=5
SHIRABE_VERIFICATION_BUDGET_SECS=$BUDGET_S start s-budget
settle s-budget
expect_rc "past the total budget" 4
expect_rule "past the total budget" verification/timed-out
BRES=$(result_of s-budget)
if jq -e '.status == "timed-out" and (.commands | length) == 1 and .commands[0].timed_out == true
          and (.detail | test("not started: b"))' "$BRES" >/dev/null 2>&1; then
    pass "the budget stops the running command and starts no other (status timed-out)"
else
    fail "the budget result is wrong: $(head -c 400 "$BRES" 2>&1)"
fi
# A stop at the budget lands a poll after it, plus the 1-second grace between
# TERM and KILL. 20 seconds leaves a loaded host 15 seconds for that and still
# fails a command stopped late or left to bin/slow.sh's own 30-second end.
BDUR=$(jq -r '.commands[0].duration_secs' "$BRES" 2>/dev/null)
case "$BDUR" in
    ''|*[!0-9]*) fail "the budget result records no duration for the stopped command: [$BDUR]" ;;
    *) [ "$BDUR" -lt 20 ] && pass "the command was stopped at the budget (${BDUR}s), not at bin/slow.sh's own 30s end" \
           || fail "the stopped command ran ${BDUR}s under a ${BUDGET_S}-second budget" ;;
esac
PGID=$(jq -r '.commands[0].pgid' "$BRES")
[ "$(group_alive "$PGID")" -eq 0 ] && pass "no process of the group stopped at the budget is alive" \
    || fail "the group $PGID stopped at the budget is still alive"

echo "--- a supervisor stopped by TERM"
# The command runs in its own process group, so a TERM to the supervisor never
# reaches it: the supervisor has to stop the group itself before it exits. The
# command records its pid, which is its group's id, and starts a child sleep,
# so the group holds two processes when the TERM lands.
HELD_CMD=$(jq -cn --arg f "$WORKDIR/held.pid" '{held: {run: ["bin/held.sh", $f], timeout_secs: 60}}')
mkrepo stopped "$(map "$HELD_CMD" '[]' '["held"]')"
printf '#!/bin/sh\necho $$ > "$1"\nsleep 30 &\nwait\n' > bin/held.sh
chmod +x bin/held.sh
change top.txt
start s-stopped
n=0
while [ ! -s "$WORKDIR/held.pid" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
HELD=$(cat "$WORKDIR/held.pid" 2>/dev/null)
SRES=$(result_of s-stopped)
SUP=$(readlink "$(dirname "$SRES")/lock" 2>/dev/null)
if [ -n "$HELD" ] && [ -n "$SUP" ] && [ "$(group_alive "$HELD")" -ge 2 ]; then
    kill -TERM "$SUP"
    n=0
    while kill -0 "$SUP" 2>/dev/null && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
    jq -e '.status == "supervisor-error"' "$SRES" >/dev/null 2>&1 \
        && pass "a supervisor stopped by TERM still writes a result (supervisor-error)" \
        || fail "a supervisor stopped by TERM wrote no supervisor-error result: $(head -c 300 "$SRES" 2>&1)"
    [ "$(group_alive "$HELD")" -eq 0 ] && pass "a supervisor stopped by TERM stops the running command's group" \
        || fail "a supervisor stopped by TERM left the command's group $HELD running"
    kill -KILL -- "-$HELD" 2>/dev/null
else
    fail "the held command never started (pid [$HELD], supervisor [$SUP])"
fi

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

echo "--- the route ranks only the causes at block"
# verdict_at_warn <session> <rule at warn> <label> <exit> <levels>: the verdict
# from a plugin copy with <rule> at warn; <levels> is the sorted
# `<rule>=<level>` list the findings must print, space-terminated.
STAGE_COPY="$RF_TEST_DIR/stage-copy"
STAGE_LOG="$RF_TEST_DIR/stage-copy.log"
verdict_at_warn() {
    local got hints
    # shellcheck disable=SC2086 # the two paths, split on purpose
    if ! rf_test_stage_copy "$STAGE_COPY" "$2" warn $VERDICT_PATHS 2>"$WORKDIR/verdict.err"; then
        fail "$3: could not make a plugin copy with $2 at warn: $(cat "$WORKDIR/verdict.err")"
        return
    fi
    : > "$STAGE_LOG"
    # Session s-<name> belongs to the repository r-<name>.
    OUT=$(cd "$WORKDIR/r-${1#s-}" && SHIRABE_FINDINGS_LOG="$STAGE_LOG" \
        "$STAGE_COPY/skills/work-on/scripts/check-verification.sh" --verdict --session "$1" 2>"$WORKDIR/verdict.err")
    RC=$?
    expect_rc "$3" "$4"
    got=$(printf '%s\n' "$OUT" | sed -n 's/^::koto-finding:://p' | jq -r '"\(.rule_id)=\(.level)"' | sort -u | tr '\n' ' ')
    [ "$got" = "$5" ] && pass "$3: findings $5" || fail "$3: findings [$got], want [$5]"
    hints=$(grep -c -F -- "$RF_TEST_HINT" "$WORKDIR/verdict.err")
    if [ "$4" -eq 0 ]; then
        [ "$hints" -eq 0 ] && pass "$3: a passing verdict prints no dispute hint" || fail "$3: dispute hint printed on a pass"
    else
        [ "$hints" -eq 1 ] && pass "$3: the route prints the dispute hint once" || fail "$3: dispute hint printed $hints times"
    fi
    rf_test_verify_copy "$3" "$STAGE_COPY" "$STAGE_LOG"
}

# needs-person can't share a result with a failed command (an attended result
# lists no commands), so the mixed result is a failed command beside one past
# its timeout, which ranks 4 like needs-person does.
mkrepo mixed "$(map '{"bad": {"run": ["bin/fail.sh"]}, "slow": {"run": ["bin/slow.sh"], "timeout_secs": 1}}' '[]' '["bad", "slow"]')"
change top.txt
start s-mixed
settle s-mixed
expect_rc "a failed command beside a timed-out one, both at block" 4
verdict_at_warn s-mixed verification/timed-out "timed-out at warn beside command-failed at block" 1 \
    "verification/command-failed=error verification/timed-out=warning "
verdict_at_warn s-mixed verification/command-failed "command-failed at warn beside timed-out at block" 4 \
    "verification/command-failed=warning verification/timed-out=error "
verdict_at_warn s-attended verification/needs-person "needs-person at warn alone" 0 \
    "verification/needs-person=warning "
rm -rf "$STAGE_COPY" "$STAGE_LOG"

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
same_laddered_verdict "a result file that does not parse (undecided), laddered" s-unread

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

# --- the bound on --start ------------------------------------------------------------------

echo "--- the bound on --start"
[ "$(start_bound_ms 100)" -eq "$START_FLOOR_MS" ] && pass "a quick reference bounds --start at the floor" \
    || fail "a 100ms reference gives a bound of $(start_bound_ms 100)ms, want ${START_FLOOR_MS}ms"
[ "$(start_bound_ms 1000)" -eq $((START_MULT * 1000)) ] && pass "a slower reference scales the bound" \
    || fail "a 1000ms reference gives a bound of $(start_bound_ms 1000)ms, want $((START_MULT * 1000))ms"
[ "$(start_bound_ms 60000)" -eq "$START_CEILING_MS" ] && pass "however slow the reference, the bound stops at the ceiling" \
    || fail "a 60000ms reference gives a bound of $(start_bound_ms 60000)ms, want ${START_CEILING_MS}ms"

# A --start that waits for the commands it starts, the regression the bound is
# for. Its command naps a second past the bound timed_start hands it, so it
# trips the check however loaded the host is.
SLOW_START="$WORKDIR/slow-start.sh"
cat > "$SLOW_START" <<EOF
#!/bin/sh
NAP_SECS=\$(( START_BOUND_MS / 1000 + 1 ))
export NAP_SECS
"$START" "\$@" || exit \$?
n=0
while [ "\$n" -lt 240 ]; do
    "$VERDICT" --verdict --session "\$3" >/dev/null 2>&1
    [ \$? -ne 75 ] && exit 0
    n=\$((n + 1))
    sleep 0.25
done
exit 0
EOF
chmod +x "$SLOW_START"
mkrepo slowstart "$(map '{"nap": {"run": ["bin/nap.sh"], "timeout_secs": 60}}' '[]' '["nap"]')"
change top.txt
timed_start "$SLOW_START" s-slowstart
[ "$START_RC" -eq 0 ] || fail "the slow --start exited $START_RC: $(cat "$WORKDIR/start.out")"
if [ "$START_MS" -gt "$BOUND_MS" ]; then
    pass "a --start that waits for its commands trips the bound (${START_MS}ms against ${BOUND_MS}ms)"
else
    fail "a --start that waits for its commands took ${START_MS}ms, within its bound of ${BOUND_MS}ms"
fi

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

rf_test_verify "check-verification"

echo
echo "run-verification_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
