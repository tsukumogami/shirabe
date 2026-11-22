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
ktg_on_exit cleanup

export HOME="$WORKDIR/home"
export XDG_STATE_HOME="$WORKDIR/state"
mkdir -p "$HOME" "$WORKDIR/bin"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main

# The koto stand-in: `koto context add <s> <key> --from-file <f>` copies the
# file to $WORKDIR/kotostore/<s>/<key> and logs the call; `context exists`,
# `get` and `remove` test, print and delete that file (get exits 1 when it is
# absent), and `session list` prints $KOTO_STUB_STORE/sessions.json, or exits
# 9 when there is none (session-role.sh then answers child). Every call is
# logged to $KOTO_STUB_STORE/calls. KOTO_STUB_FAIL=<subcommand> makes that
# subcommand exit 7.
cat > "$WORKDIR/bin/koto" <<'EOF'
#!/bin/sh
echo "$*" >> "$KOTO_STUB_STORE/calls"
[ -n "${KOTO_STUB_FAIL-}" ] && [ "${2-}" = "$KOTO_STUB_FAIL" ] && exit 7
case "$1 ${2-}" in
    "context add")
        mkdir -p "$KOTO_STUB_STORE/$3"
        [ "${5-}" = --from-file ] && cp "$6" "$KOTO_STUB_STORE/$3/$4" || cat > "$KOTO_STUB_STORE/$3/$4"
        echo "add $3 $4" >> "$KOTO_STUB_STORE/log" ;;
    "context exists") [ -f "$KOTO_STUB_STORE/$3/$4" ] ;;
    "context get") [ -f "$KOTO_STUB_STORE/$3/$4" ] || exit 1; cat "$KOTO_STUB_STORE/$3/$4" ;;
    "context remove") rm -f "$KOTO_STUB_STORE/$3/$4"; echo "remove $3 $4" >> "$KOTO_STUB_STORE/log" ;;
    "session list") [ -f "$KOTO_STUB_STORE/sessions.json" ] || exit 9; cat "$KOTO_STUB_STORE/sessions.json" ;;
    *) exit 9 ;;
esac
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
    # --start's stale-record step asks koto whether the session holds one.
    koto context exists "$1" hosted_of_record >/dev/null 2>&1
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

# expect_record <label> <session> <command id> <jq condition>: the result's
# record for <command id> (the first, for an each command) meets <condition>.
expect_record() {
    local res
    res=$(result_of "$2")
    if jq -e --arg id "$3" "[.commands[] | select(.id == \$id)][0] | $4" "$res" >/dev/null 2>&1; then
        pass "$1: the $3 record has $4"
    else
        fail "$1: the $3 record fails $4: $(jq -c --arg id "$3" '[.commands[] | select(.id == $id)][0]' "$res" 2>&1 | head -c 600)"
    fi
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
expect_record "a pass" s-pass ok '.outcome == "passed" and .suites == null'
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
# the rule, so the template's context releases its text, adds its full delivery
# marker on stdout, and changes nothing else.
PLAIN_OUT=$OUT; PLAIN_RC=$RC
LADDER_LOG="$WORKDIR/ladder.jsonl"
rf_test_ladder_log "$LADDER_LOG" verification verification_verdict verification/command-failed 1
OUT=$(SHIRABE_GATE_LOG="$LADDER_LOG" SHIRABE_GATE_NAME=verification_verdict \
    SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" \
    "$VERDICT" --verdict --session s-fail 2>"$WORKDIR/verdict.err")
RC=$?
WANT_OUT="$PLAIN_OUT
::koto-rule-delivered::{\"rule_id\":\"verification/command-failed\",\"extent\":\"full\",\"delivery\":\"printed\"}"
if [ "$RC" -eq "$PLAIN_RC" ] && [ "$OUT" = "$WANT_OUT" ] \
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
# check-verification.sh sources verification-route.sh, which runs
# session-role.sh, so a stage copy carries both.
VERDICT_PATHS="skills/work-on/scripts/check-verification.sh skills/work-on/scripts/run-verification.sh skills/work-on/scripts/verification-eligibility.sh skills/work-on/scripts/verification-route.sh skills/work-on/scripts/session-role.sh"
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
expect_record "a runaway" s-fork forker '.runaway == true and .outcome == "failed"'
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
expect_record "stopped at its limit with no summary" s-slow slow \
    '.timed_out == true and .outcome == "timed-out-limit" and .suites == null'
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

echo "--- a stopped supervisor's result holds the gate"
# The TERM above is what a memory guard does to a suite mid-run. Its result
# says nothing about the change, so the verdict holds (2) instead of routing it
# as a failure (4) that would end the run: no finding, nothing recorded in koto
# context, and a message naming the result and how to go on. A second --start
# keeps the result and starts nothing, so a held tick never launches a suite on
# its own; moving the result aside is what starts a fresh run.
if jq -e '.status == "supervisor-error"' "$SRES" >/dev/null 2>&1; then
    verdict s-stopped
    expect_rc "a guard abort's stopped-supervisor result" 2
    expect_no_finding "a guard abort's stopped-supervisor result"
    [ ! -e "$KOTO_STUB_STORE/s-stopped/verification_results.json" ] \
        && pass "a stopped supervisor's result is not recorded in koto context" \
        || fail "a stopped supervisor's result was recorded in koto context as a verdict"
    if grep -q -F -- "$SRES" "$WORKDIR/verdict.err" && grep -q 'verification_status: blocked' "$WORKDIR/verdict.err"; then
        pass "the hold names the stopped result and how to stop the run"
    else
        fail "the hold's message: $(cat "$WORKDIR/verdict.err")"
    fi

    rm -f "$WORKDIR/held.pid"
    start s-stopped
    sleep 1
    if [ ! -s "$WORKDIR/held.pid" ] && [ ! -e "$(dirname "$SRES")/lock" ] \
        && jq -e '.status == "supervisor-error"' "$SRES" >/dev/null 2>&1; then
        pass "a second --start keeps the stopped result and starts no supervisor"
    else
        fail "a second --start replaced the stopped result or started a run (pid [$(cat "$WORKDIR/held.pid" 2>/dev/null)])"
    fi
    verdict s-stopped
    expect_rc "a guard abort's stopped-supervisor result, after a second --start" 2

    mv "$SRES" "$SRES.aside"
    start s-stopped
    n=0
    while [ ! -s "$WORKDIR/held.pid" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
    HELD=$(cat "$WORKDIR/held.pid" 2>/dev/null)
    SUP=$(readlink "$(dirname "$SRES")/lock" 2>/dev/null)
    [ -n "$HELD" ] && pass "moving the stopped result aside lets --start begin a fresh run" \
        || fail "--start began no run after the stopped result was moved aside"
    [ -n "$SUP" ] && kill -TERM "$SUP" 2>/dev/null
    n=0
    while [ -n "$SUP" ] && kill -0 "$SUP" 2>/dev/null && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
    [ -n "$HELD" ] && kill -KILL -- "-$HELD" 2>/dev/null
else
    fail "no supervisor-error result to hold on: $(head -c 300 "$SRES" 2>&1)"
fi

echo "--- a command that cannot start"
mkrepo nostart "$(map '{"gone": {"run": ["bin/missing.sh"]}}' '[]' '["gone"]')"
change top.txt
start s-nostart
settle s-nostart
expect_rc "run[0] does not exist" 4
expect_rule "run[0] does not exist" verification/not-started
expect_record "a command that never started" s-nostart gone \
    '.not_started == true and .outcome == "failed" and .suites == null'

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
expect_record "an unattended: false command" s-attended a '.not_started == true and .outcome == "failed" and .suites == null'

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

# The mixed result is a failed command beside one past its timeout. A failed
# check outranks a timeout, so both at block route back to implementation (1);
# with the failure at warn, the timeout chooses, and the failed record keeps
# the hosted-of-record route closed (4).
mkrepo mixed "$(map '{"bad": {"run": ["bin/fail.sh"]}, "slow": {"run": ["bin/slow.sh"], "timeout_secs": 1}}' '[]' '["bad", "slow"]')"
change top.txt
start s-mixed
settle s-mixed
expect_rc "a failed command beside a timed-out one, both at block" 1
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

# --- outcomes and suite summaries ---------------------------------------------------------
#
# Each record's outcome: passed, failed, timed-out-limit or timed-out-inside.
# The fixtures:
#   faillike.sh        prints a FAIL line about a timeout and exits 1;
#   sumslow.sh <kind>  writes a suite summary to $SHIRABE_SUITE_SUMMARY, with
#                      no failed suite (clean) or one (failed), then sleeps
#                      past its limit;
#   inner.sh <kind>    exits 1 after printing failure lines that all read as
#                      a timeout (match), the same plus an assertion failure
#                      (mixed), or no failure line at all (none).
FORM='timed out after [0-9]+s'
add_outcome_fixtures() {
    printf '#!/bin/sh\necho "ok 1 - setup"\necho "FAIL: case b: timed out waiting for the lock"\nexit 1\n' > bin/faillike.sh
    cat > bin/sumslow.sh <<'EOF'
#!/bin/sh
case "$1" in
    clean) printf '{"passed":["s/a_test.sh"],"failed":[],"running":["s/b_test.sh"],"not_started":["s/c_test.sh"]}\n' ;;
    failed) printf '{"passed":["s/a_test.sh"],"failed":["s/x_test.sh"],"running":["s/b_test.sh"],"not_started":[]}\n' ;;
esac > "$SHIRABE_SUITE_SUMMARY"
sleep 30
EOF
    cat > bin/inner.sh <<'EOF'
#!/bin/sh
echo "ok 1 - setup"
case "$1" in
    match|mixed)
        echo "FAIL: case b: timed out after 30s"
        echo "    waited for the koto lock"
        printf '\033[31mFAIL\033[0m: case c: timed out after 45s\n' ;;
    none) echo "something went wrong" ;;
esac
[ "$1" = mixed ] && echo "FAIL: case d: expected 3, got 4"
exit 1
EOF
    chmod +x bin/faillike.sh bin/sumslow.sh bin/inner.sh
}

echo "--- outcome: a failure that prints a timeout, from a row with no timeout_form"
mkrepo faillike "$(map '{"bad": {"run": ["bin/faillike.sh"]}}' '[]' '["bad"]')"
add_outcome_fixtures
change top.txt
start s-faillike
settle s-faillike
expect_rc "a timeout-looking failure with no timeout_form" 1
expect_record "a timeout-looking failure with no timeout_form" s-faillike bad \
    '.outcome == "failed" and .timed_out == false and .suites == null'

# A limit of 3, not 1: the supervisor's clock reads whole seconds, so a limit of 1 can stop the fixture before it writes its summary.
echo "--- outcome: stopped at the limit, with a suite summary"
mkrepo sumclean "$(map '{"chk": {"run": ["bin/sumslow.sh", "clean"], "timeout_secs": 3}}' '[]' '["chk"]')"
add_outcome_fixtures
change top.txt
start s-sumclean
settle s-sumclean
expect_rc "stopped at the limit, no failed suite" 4
expect_rule "stopped at the limit, no failed suite" verification/timed-out
expect_record "stopped at the limit, no failed suite" s-sumclean chk \
    '.timed_out == true and .outcome == "timed-out-limit"
     and .suites == {"passed": ["s/a_test.sh"], "failed": [], "running": ["s/b_test.sh"], "not_started": ["s/c_test.sh"]}'

mkrepo sumfailed "$(map '{"chk": {"run": ["bin/sumslow.sh", "failed"], "timeout_secs": 3}}' '[]' '["chk"]')"
add_outcome_fixtures
change top.txt
start s-sumfailed
settle s-sumfailed
expect_rc "stopped at the limit with a finished-failed suite" 1
expect_rule "stopped at the limit with a finished-failed suite" verification/command-failed
expect_record "stopped at the limit with a finished-failed suite" s-sumfailed chk \
    '.timed_out == true and .outcome == "failed" and .suites.failed == ["s/x_test.sh"]'

echo "--- outcome: timeout_form"
CMDS=$(jq -cn --arg form "$FORM" '{
    inside: {run: ["bin/inner.sh", "match"], timeout_form: $form},
    mixed: {run: ["bin/inner.sh", "mixed"], timeout_form: $form},
    noform: {run: ["bin/inner.sh", "match"]},
    nolines: {run: ["bin/inner.sh", "none"], timeout_form: $form}}')
mkrepo forms "$(map "$CMDS" '[]' '["inside", "mixed", "noform", "nolines"]')"
add_outcome_fixtures
change top.txt
start s-forms
settle s-forms
expect_rc "four timeout_form cases in one result" 1
expect_record "every failure line matches the form" s-forms inside \
    '.outcome == "timed-out-inside" and .timed_out == false and .exit_status == 1'
expect_record "one failure line doesn't match the form" s-forms mixed '.outcome == "failed"'
expect_record "the same log from a row with no timeout_form" s-forms noform '.outcome == "failed"'
expect_record "a form, a nonzero exit and no failure line" s-forms nolines '.outcome == "failed"'
RUNJSON="$(dirname "$(result_of s-forms)")/run.json"
jq -e --arg form "$FORM" '[.invocations[] | select(.id == "inside")][0].timeout_form == $form
                          and ([.invocations[] | select(.id == "noform")][0].timeout_form == null)' "$RUNJSON" >/dev/null 2>&1 \
    && pass "the loader carries a row's timeout_form on its invocations, null where the row has none" \
    || fail "run.json's invocations don't carry timeout_form: $(head -c 600 "$RUNJSON" 2>&1)"

CMDS=$(jq -cn --arg form "$FORM" '{inside: {run: ["bin/inner.sh", "match"], timeout_form: $form}}')
mkrepo inside "$(map "$CMDS" '[]' '["inside"]')"
add_outcome_fixtures
change top.txt
start s-inside
settle s-inside
expect_rc "a timed-out-inside record alone, its row declaring no hosted jobs" 4
expect_rule "a timed-out-inside record alone" verification/timed-out
expect_record "a timed-out-inside record alone" s-inside inside '.outcome == "timed-out-inside"'

echo "--- a summary left by an earlier run"
mkrepo stalesum "$(map "{\"ok\": $(rec "$WORKDIR/stalesum.rec" ok)}" '[]' '["ok"]')"
change top.txt
STALE_DIR=$(dirname "$(result_of s-stalesum)")
mkdir -p "$STALE_DIR"
printf '{"passed":["old_test.sh"],"failed":[],"running":[],"not_started":[]}\n' > "$STALE_DIR/0-ok.suites.json"
start s-stalesum
settle s-stalesum
expect_rc "a command that writes no summary" 0
expect_record "a summary file an earlier run left at the path" s-stalesum ok '.outcome == "passed" and .suites == null'

echo "--- a bad timeout_form"
mkrepo badform "$(map '{"inside": {"run": ["bin/fail.sh"], "timeout_form": 5}}' '[]' '["inside"]')"
change top.txt
start s-badform
settle s-badform
expect_rc "a timeout_form that is not a string" 3
expect_rule "a timeout_form that is not a string" verification/bad-map
jq -e '.status == "bad-map" and (.detail | test("command inside: timeout_form"))' "$(result_of s-badform)" >/dev/null 2>&1 \
    && pass "a non-string timeout_form's bad-map names the command" \
    || fail "a non-string timeout_form's result: $(head -c 400 "$(result_of s-badform)" 2>&1)"

mkrepo badre "$(map '{"inside": {"run": ["bin/fail.sh"], "timeout_form": "timed out ("}}' '[]' '["inside"]')"
change top.txt
start s-badre
settle s-badre
expect_rc "a timeout_form that does not compile" 3
expect_rule "a timeout_form that does not compile" verification/bad-map
jq -e '.status == "bad-map" and (.detail | test("command inside: timeout_form"))' "$(result_of s-badre)" >/dev/null 2>&1 \
    && pass "an uncompilable timeout_form's bad-map names the command" \
    || fail "an uncompilable timeout_form's result: $(head -c 400 "$(result_of s-badre)" 2>&1)"

# --- the hosted declaration ---------------------------------------------------------------
#
# A row may declare the hosted jobs that run its suites. A well-formed
# declaration changes nothing about what runs: the same map with and without it
# selects the same invocations (once their hosted key is set aside), exits the
# same and settles the same status. Each invocation carries the row's hosted,
# [] where the row declares none.

echo "--- hosted: a well-formed declaration runs the row as the map without it does"
HOSTED='[{"workflow": ".github/workflows/check-skill-gate.yml", "job": "skill-gate (ubuntu-latest)", "runs": "check-skill {skill}"}]'
HR="$WORKDIR/hosted.rec"
CMDS=$(jq -cn --arg f "$HR" --arg form "$FORM" '{
    chk: {run: ["bin/rec.sh", $f, "chk"], each: "skills/*", timeout_secs: 600, timeout_form: $form},
    plain: {run: ["bin/rec.sh", $f, "plain"]}}')
ENTRIES='[{"paths": ["skills/**"], "commands": ["chk"]}]'
mkrepo nohosted "$(map "$CMDS" "$ENTRIES" '["plain"]')"
change skills/a/f.txt top.txt
start s-nohosted
settle s-nohosted
NOHOSTED_RC=$RC
NOHOSTED_RUN="$(dirname "$(result_of s-nohosted)")/run.json"
NOHOSTED_STATUS=$(jq -r .status "$(result_of s-nohosted)" 2>/dev/null)
CMDS_H=$(printf '%s' "$CMDS" | jq -c --argjson h "$HOSTED" '.chk.hosted = $h')
mkrepo hosted "$(map "$CMDS_H" "$ENTRIES" '["plain"]')"
change skills/a/f.txt top.txt
start s-hosted
settle s-hosted
expect_rc "a row declaring hosted" 0
HOSTED_RUN="$(dirname "$(result_of s-hosted)")/run.json"
[ "$RC" -eq "$NOHOSTED_RC" ] && pass "hosted: the same verdict exit with and without the declaration ($RC)" \
    || fail "hosted: verdict exit $RC with the declaration, $NOHOSTED_RC without"
HOSTED_STATUS=$(jq -r .status "$(result_of s-hosted)" 2>/dev/null)
[ "$HOSTED_STATUS" = "$NOHOSTED_STATUS" ] && [ "$HOSTED_STATUS" = done ] \
    && pass "hosted: the same result status with and without the declaration ($HOSTED_STATUS)" \
    || fail "hosted: result status [$HOSTED_STATUS] with the declaration, [$NOHOSTED_STATUS] without"
if [ -n "$(jq -c '.invocations' "$HOSTED_RUN" 2>/dev/null)" ] \
    && [ "$(jq -c '[.invocations[] | del(.hosted)]' "$HOSTED_RUN" 2>/dev/null)" \
        = "$(jq -c '[.invocations[] | del(.hosted)]' "$NOHOSTED_RUN" 2>/dev/null)" ]; then
    pass "hosted: the same invocations (id, argv, limits, timeout_form) once hosted is set aside"
else
    fail "hosted: the invocations differ: [$(jq -c '.invocations' "$HOSTED_RUN" 2>&1 | head -c 600)] vs [$(jq -c '.invocations' "$NOHOSTED_RUN" 2>&1 | head -c 600)]"
fi
jq -e --argjson h "$HOSTED" --arg form "$FORM" '
    ([.invocations[] | select(.id == "chk")] | length == 1 and all(.hosted == $h and .timeout_form == $form and .argv[-1] == "a"))
    and ([.invocations[] | select(.id == "plain")] | length == 1 and all(.hosted == [] and .timeout_form == null))' \
    "$HOSTED_RUN" >/dev/null 2>&1 \
    && pass "hosted: each invocation carries its row's hosted, [] where the row declares none, beside timeout_form" \
    || fail "hosted: run.json's invocations don't carry hosted: $(head -c 600 "$HOSTED_RUN" 2>&1)"
jq -e '[.invocations[].hosted] == [[], []]' "$NOHOSTED_RUN" >/dev/null 2>&1 \
    && pass "hosted: a map with no declaration carries [] on every invocation" \
    || fail "hosted: a map with no declaration: $(head -c 600 "$NOHOSTED_RUN" 2>&1)"

# bad_hosted <n> <label> <hosted json> <detail fragment>: a row whose hosted is
# malformed settles bad-map (verdict exit 3, verification/bad-map), starts no
# command, and the detail begins `command hrow:` and holds the fragment.
bad_hosted() {
    local rec="$WORKDIR/badhosted$1.rec" cmds
    cmds=$(jq -cn --arg f "$rec" --argjson h "$3" '{hrow: {run: ["bin/rec.sh", $f, "hrow"], hosted: $h}}')
    mkrepo "badhosted$1" "$(map "$cmds" '[]' '["hrow"]')"
    change top.txt
    start "s-badhosted$1"
    settle "s-badhosted$1"
    expect_rc "hosted: $2" 3
    expect_rule "hosted: $2" verification/bad-map
    if jq -e --arg frag "$4" '.status == "bad-map" and (.detail | startswith("command hrow:")) and (.detail | contains($frag))' \
            "$(result_of "s-badhosted$1")" >/dev/null 2>&1; then
        pass "hosted: $2: the bad-map detail begins with the command and says what is wrong"
    else
        fail "hosted: $2: result $(head -c 400 "$(result_of "s-badhosted$1")" 2>&1)"
    fi
    [ ! -e "$rec" ] && pass "hosted: $2: no command started" || fail "hosted: $2: a command started"
}

echo "--- hosted: a malformed declaration is a bad map"
NOT_ARRAY='hosted is not a non-empty array'
BAD_ENTRY='hosted has an entry that is not an object'
OUTSIDE='hosted names a workflow outside .github/workflows/'
W='.github/workflows/check-skill-gate.yml'
n=0
while IFS='|' read -r label h frag; do
    [ -n "$label" ] || continue
    n=$((n + 1))
    bad_hosted "$n" "$label" "$h" "$frag"
done <<EOF
hosted that is not an array|{"workflow": "$W", "job": "j", "runs": "r"}|$NOT_ARRAY
an empty hosted array|[]|$NOT_ARRAY
an entry that is not an object|["$W"]|$BAD_ENTRY
an entry missing workflow|[{"job": "j", "runs": "r"}]|$BAD_ENTRY
an entry missing job|[{"workflow": "$W", "runs": "r"}]|$BAD_ENTRY
an entry missing runs|[{"workflow": "$W", "job": "j"}]|$BAD_ENTRY
an empty workflow|[{"workflow": "", "job": "j", "runs": "r"}]|$BAD_ENTRY
an empty job|[{"workflow": "$W", "job": "", "runs": "r"}]|$BAD_ENTRY
an empty runs|[{"workflow": "$W", "job": "j", "runs": ""}]|$BAD_ENTRY
a workflow that is not a string|[{"workflow": 5, "job": "j", "runs": "r"}]|$BAD_ENTRY
a job that is not a string|[{"workflow": "$W", "job": ["j"], "runs": "r"}]|$BAD_ENTRY
a runs that is not a string|[{"workflow": "$W", "job": "j", "runs": null}]|$BAD_ENTRY
a workflow outside .github/workflows/|[{"workflow": "ci/check.yml", "job": "j", "runs": "r"}]|$OUTSIDE
a workflow that climbs out of .github/workflows/|[{"workflow": ".github/workflows/../x.yml", "job": "j", "runs": "r"}]|$OUTSIDE
EOF

echo "--- hosted: the other row checks still hold beside it"
CMDS=$(jq -cn --argjson h "$HOSTED" '{hrow: {run: ["bin/fail.sh"], timeout_secs: 3601, hosted: $h}}')
mkrepo hostedcap "$(map "$CMDS" '[]' '["hrow"]')"
change top.txt
start s-hostedcap
settle s-hostedcap
expect_rc "a timeout_secs above 3600 beside a well-formed hosted" 3
jq -e '.status == "bad-map" and (.detail | test("command hrow: timeout_secs"))' "$(result_of s-hostedcap)" >/dev/null 2>&1 \
    && pass "hosted: a timeout_secs above 3600 is still refused on a row that declares hosted" \
    || fail "hosted: a timeout_secs above 3600 with hosted: $(head -c 400 "$(result_of s-hostedcap)" 2>&1)"
CMDS=$(jq -cn --argjson h "$HOSTED" '{hrow: {run: ["bin/fail.sh"], timeout_form: "timed out (", hosted: $h}}')
mkrepo hostedform "$(map "$CMDS" '[]' '["hrow"]')"
change top.txt
start s-hostedform
settle s-hostedform
expect_rc "an uncompilable timeout_form beside a well-formed hosted" 3
jq -e '.status == "bad-map" and (.detail | test("command hrow: timeout_form"))' "$(result_of s-hostedform)" >/dev/null 2>&1 \
    && pass "hosted: timeout_form still validates on a row that declares hosted" \
    || fail "hosted: an uncompilable timeout_form with hosted: $(head -c 400 "$(result_of s-hostedform)" 2>&1)"

# --- the hold at 5 ---------------------------------------------------------------------
#
# A timed-out check with no failed one exits 5 when the hosted-of-record route
# is open, which takes a root session (session-role.sh asks the stand-in's
# session list) and a row that declares hosted jobs; 4 otherwise.

echo "--- the hold: a timed-out check whose row declares hosted jobs"
# root_sessions <s>...: the stand-in's session list names each as a root.
root_sessions() {
    jq -cn '$ARGS.positional | map({id: .})' --args "$@" > "$KOTO_STUB_STORE/sessions.json"
}
add_recslow() {
    printf '#!/bin/sh\nprintf "start\\n" >> "$1"\nexec "$(dirname "$0")/sumslow.sh" clean\n' > bin/recslow.sh
    chmod +x bin/recslow.sh
}
HOLD_REC="$WORKDIR/hold.rec"
CMDS=$(jq -cn --arg f "$HOLD_REC" --argjson h "$HOSTED" '{chk: {run: ["bin/recslow.sh", $f], timeout_secs: 1, hosted: $h}}')
mkrepo hold "$(map "$CMDS" '[]' '["chk"]')"
add_outcome_fixtures
add_recslow
change top.txt
root_sessions s-hold s-holdbare
start s-hold
settle s-hold
expect_rc "a timed-out check, none failed, the route open" 5
expect_rule "a timed-out check, none failed, the route open" verification/timed-out
grep -qF 'verification_status: hosted_of_record' "$WORKDIR/verdict.err" \
    && pass "the hold says what it offers: hosted_of_record with a reason, fix, blocked" \
    || fail "the hold's stderr: $(cat "$WORKDIR/verdict.err")"
[ "$(grep -c '^start$' "$HOLD_REC" 2>/dev/null)" = 1 ] && pass "the hold: the check started once" \
    || fail "the hold: the check started $(grep -c '^start$' "$HOLD_REC" 2>/dev/null) times"
start s-hold
verdict s-hold
expect_rc "re-entering verification at the same head and merge-base holds at 5 again" 5
[ "$(grep -c '^start$' "$HOLD_REC" 2>/dev/null)" = 1 ] \
    && pass "re-entry reuses the stored timed-out result and starts no check" \
    || fail "re-entry started the check again: $(grep -c '^start$' "$HOLD_REC" 2>/dev/null) starts"
OUT=$("$VERDICT" --verdict --session s-hold --shared-branch docs/x 2>"$WORKDIR/verdict.err")
RC=$?
expect_rc "the same result for a SHARED_BRANCH run of /execute: the hold, as for any run" 5
grep -q 'child of /execute' "$WORKDIR/verdict.err" \
    && fail "a SHARED_BRANCH run's verdict still names /execute as a closing cause: $(cat "$WORKDIR/verdict.err")" \
    || pass "a SHARED_BRANCH run's verdict names no /execute refusal"
OUT=$("$VERDICT" --verdict --session s-hold --shared-branch "" 2>"$WORKDIR/verdict.err")
RC=$?
expect_rc "an empty --shared-branch, as a run not under /execute passes it" 5
root_sessions s-holdbare
verdict s-hold
expect_rc "the same result when the session is not listed as a root (a child /execute started): the hold" 5

CMDS=$(jq -cn --arg f "$WORKDIR/holdbare.rec" '{chk: {run: ["bin/recslow.sh", $f], timeout_secs: 1}}')
mkrepo holdbare "$(map "$CMDS" '[]' '["chk"]')"
add_outcome_fixtures
add_recslow
change top.txt
start s-holdbare
settle s-holdbare
expect_rc "a timed-out check whose row declares no hosted jobs, the route closed" 4
grep -qF 'declares no hosted jobs' "$WORKDIR/verdict.err" \
    && pass "the closed route's cause is on stderr" || fail "the closed verdict's stderr: $(cat "$WORKDIR/verdict.err")"
rm -f "$KOTO_STUB_STORE/sessions.json"

echo "--- the route's check runs in this process"
if grep -q '^\. "\$HERE/verification-route.sh" ||' "$VERDICT" \
    && ! grep -v '^[[:space:]]*#' "$VERDICT" | grep -q '"\$HERE/verification-route.sh" -'; then
    pass "check-verification.sh sources verification-route.sh and never runs it as a second process"
else
    fail "check-verification.sh does not source verification-route.sh, or runs it"
fi

# --- the check id, finished_at and a stale hosted_of_record key -----------------------

echo "--- the check id and finished_at"
# result_of reads the repository the shell is in, so each lookup runs in its own.
HRES=$(cd "$WORKDIR/r-hosted" && result_of s-hosted)
NRES=$(cd "$WORKDIR/r-nomap" && result_of s-nomap)
jq -e '[.commands[] | select(.id == "chk")] | length == 1 and all(.check == "chk:a")' "$HRES" >/dev/null 2>&1 \
    && pass "check: an each row's record names its check <row>:<last argv> (chk:a)" \
    || fail "check: the each row's record: $(jq -c '[.commands[] | {id, check}]' "$HRES" 2>&1 | head -c 400)"
jq -e '[.commands[] | select(.id == "plain")] | length == 1 and all(.check == "plain")' "$HRES" >/dev/null 2>&1 \
    && pass "check: a plain row's record names its check by the row id" \
    || fail "check: the plain row's record: $(jq -c '[.commands[] | {id, check}]' "$HRES" 2>&1 | head -c 400)"
jq -e '[.invocations[] | {id, check}] == [{id: "chk", check: "chk:a"}, {id: "plain", check: "plain"}]' "$HOSTED_RUN" >/dev/null 2>&1 \
    && pass "check: run.json's invocations carry the check id" \
    || fail "check: run.json's invocations: $(jq -c '[.invocations[] | {id, check}]' "$HOSTED_RUN" 2>&1 | head -c 400)"
jq -e '.finished_at | fromdateiso8601 | . > 0' "$HRES" >/dev/null 2>&1 \
    && pass "finished_at: a supervised result records when it was written" \
    || fail "finished_at: the supervised result has none: $(head -c 400 "$HRES" 2>&1)"
jq -e '.status == "no-map" and (.finished_at | fromdateiso8601 | . > 0)' "$NRES" >/dev/null 2>&1 \
    && pass "finished_at: a result that needs no run records it too" \
    || fail "finished_at: the no-map result: $(head -c 400 "$NRES" 2>&1)"

echo "--- a hosted_of_record key from another head"
mkrepo stalekey "$(map "{\"ok\": $(rec "$WORKDIR/stalekey.rec" ok)}" '[]' '["ok"]')"
change top.txt
SK="$KOTO_STUB_STORE/s-stalekey/hosted_of_record"
OLD_HEAD=$(git rev-parse HEAD~1)
# seed_key <head>: a hosted_of_record key for <head> in the stand-in's store.
seed_key() {
    mkdir -p "$(dirname "$SK")"
    jq -cn --arg h "$1" '{head: $h, taken_at: "2026-01-01T00:00:00Z", reason: "x", checks: []}' > "$SK"
}
seed_key "$OLD_HEAD"
start s-stalekey
[ ! -e "$SK" ] && grep -qx "remove s-stalekey hosted_of_record" "$KOTO_STUB_STORE/log" \
    && pass "stale key: --start removes a hosted_of_record key recorded for another head" \
    || fail "stale key: the key for $OLD_HEAD is still there: $(cat "$SK" 2>&1)"
settle s-stalekey
expect_rc "stale key: the run at the new head" 0
# The result now stands, so this --start returns at the reuse step; the key
# goes all the same, since the step comes first.
seed_key "$OLD_HEAD"
start s-stalekey
[ ! -e "$SK" ] && pass "stale key: removed before a stored result is reused" \
    || fail "stale key: a reused result kept the key for $OLD_HEAD"
seed_key "$(git rev-parse HEAD)"
start s-stalekey
[ -e "$SK" ] && pass "stale key: a key at the current head is kept" || fail "stale key: the current head's key was removed"
mkdir -p "$(dirname "$SK")" && printf 'not json\n' > "$SK"
start s-stalekey
[ ! -e "$SK" ] && pass "stale key: a key that doesn't parse names no head and is removed" \
    || fail "stale key: an unparsable key was kept"
seed_key "$OLD_HEAD"
KOTO_STUB_FAIL=exists "$START" --start --session s-stalekey >"$WORKDIR/start.out" 2>&1
RC=$?
[ "$RC" -eq 2 ] && pass "stale key: koto failing to answer exists is exit 2" \
    || fail "stale key: koto failing on exists: --start exited $RC: $(cat "$WORKDIR/start.out")"
KOTO_STUB_FAIL=remove "$START" --start --session s-stalekey >"$WORKDIR/start.out" 2>&1
RC=$?
[ "$RC" -eq 2 ] && pass "stale key: koto failing to remove the key is exit 2" \
    || fail "stale key: koto failing on remove: --start exited $RC: $(cat "$WORKDIR/start.out")"

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

# build_output belongs to the build-output cleanup, and selection never reads
# it: the same map without the field, with it, with it as a string, and with a
# list holding a number and an empty string beside "target/" all parse and
# select the same invocations for the same change.
R3="$WORKDIR/selbo.rec"
CMDS=$(jq -cn --arg f "$R3" '{A: {run: ["bin/rec.sh", $f, "A"]}, D: {run: ["bin/rec.sh", $f, "D"]}}')
BO_BASE=$(map "$CMDS" '[{"paths": ["src/**"], "commands": ["A"]}]' '["D"]')
# bo_case <n> <label> <build_output json | NONE>: settles a change to an
# entry's path and an unmatched path under that map, and leaves the selected
# invocations (id and argv, in run order) in BO_SEL.
bo_case() {
    local m=$BO_BASE
    [ "$3" = NONE ] || m=$(printf '%s' "$BO_BASE" | jq -c --argjson b "$3" '.build_output = $b')
    mkrepo "selbo$1" "$m"
    change src/x/f.txt top.txt
    start "s-selbo$1"
    settle "s-selbo$1"
    expect_rc "$2" 0
    BO_SEL=$(jq -c '[.commands[] | {id, argv}]' "$(result_of "s-selbo$1")")
}
bo_case 1 "a map without build_output" NONE
BO_NONE=$BO_SEL
[ "$(printf '%s' "$BO_NONE" | jq -c '[.[].id]')" = '["A","D"]' ] \
    && pass "the map without build_output selects A and the default D" \
    || fail "the map without build_output selected $BO_NONE, expected A and D"
bo_case 2 'build_output ["target/"]' '["target/"]'
[ "$BO_SEL" = "$BO_NONE" ] && pass 'build_output ["target/"] selects the same invocations as the map without it' \
    || fail "build_output [\"target/\"] selected $BO_SEL, without it $BO_NONE"
bo_case 3 'build_output as a string (not invalid)' '"target/"'
[ "$BO_SEL" = "$BO_NONE" ] && pass 'build_output as a string selects the same invocations as the map without it' \
    || fail "build_output as a string selected $BO_SEL, without it $BO_NONE"
bo_case 4 'build_output with a number and an empty string (not invalid)' '["target/", 1, ""]'
[ "$BO_SEL" = "$BO_NONE" ] && pass 'build_output holding a number and an empty string selects the same invocations as the map without it' \
    || fail "build_output with a number and an empty string selected $BO_SEL, without it $BO_NONE"

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

# --- attempt folders, the archive, a re-run request ------------------------------------------

echo "--- attempt folders, --archive and verification_rerun_request"

# head_dir <session>: the head directory --locate names, in the current repository.
head_dir() { dirname "$(result_of "$1")"; }
# locate_line <session> <n>: line <n> of --locate (1 the head, 2 the merge-base).
locate_line() { "$START" --locate --session "$1" | sed -n "$2p"; }
# archived_count <head dir>: how many attempt folders hold a result.json.
archived_count() { ls "$1"/attempts/*/result.json 2>/dev/null | wc -l | tr -d ' '; }

# A first suite's logs: attempts/1/<index>-<id>.log, the id made safe.
CMDS=$(jq -cn --arg f "$WORKDIR/att.rec" '{ok: {run: ["bin/rec.sh", $f, "ok"]}, "a b/c": {run: ["bin/rec.sh", $f, "abc"]}}')
mkrepo att "$(map "$CMDS" '[]' '["ok", "a b/c"]')"
change top.txt
start s-att
settle s-att
expect_rc "two passing commands, one with an unsafe id" 0
HD=$(head_dir s-att)
if [ -f "$HD/attempts/1/0-ok.log" ] && [ -f "$HD/attempts/1/1-a_b_c.log" ] \
    && [ ! -e "$HD/0-ok.log" ] && [ ! -e "$HD/1-a_b_c.log" ]; then
    pass "a first suite writes its logs under attempts/1/ as <index>-<id>.log, the id's unsafe characters replaced by _"
else
    fail "the first suite's logs: $(ls -R "$HD" 2>&1 | tr '\n' ' ')"
fi
jq -e --arg a "$HD/attempts/1/0-ok.log" --arg b "$HD/attempts/1/1-a_b_c.log" \
    '[.commands[].log] == [$a, $b]' "$HD/result.json" >/dev/null 2>&1 \
    && pass "the result records each log's path under attempts/1/" \
    || fail "the result's log paths: $(jq -c '[.commands[].log]' "$HD/result.json" 2>&1)"
[ "$(mode_of "$HD/attempts")" = 700 ] && [ "$(mode_of "$HD/attempts/1")" = 700 ] \
    && pass "attempts/ and attempts/1/ have mode 0700" \
    || fail "attempts/ is $(mode_of "$HD/attempts"), attempts/1/ is $(mode_of "$HD/attempts/1")"
BAD=""
for f in "$HD/attempts/1/0-ok.log" "$HD/attempts/1/1-a_b_c.log"; do
    [ "$(mode_of "$f")" = 600 ] || BAD="$BAD $f=$(mode_of "$f")"
done
[ -z "$BAD" ] && pass "every command log has mode 0600" || fail "logs not 0600:$BAD"
if [ -f "$HD/result.json" ] && [ -f "$HD/run.json" ] && [ ! -e "$HD/attempts/1/result.json" ] \
    && jq -e '.attempt == 1' "$HD/run.json" >/dev/null 2>&1; then
    pass "result.json and run.json sit at the head directory, run.json recording attempt 1"
else
    fail "the head directory: $(ls "$HD" | tr '\n' ' '); run.json $(head -c 300 "$HD/run.json" 2>&1)"
fi

# expect_archive_refused <label> <session> <reason> <message>: --archive exits
# non-zero, says <message> on stderr, leaves result.json and run.json where
# they were, archives no result and writes no ledger.
expect_archive_refused() {
    local hd before rc
    hd=$(head_dir "$2")
    before=$(cat "$hd/result.json" 2>/dev/null)
    "$START" --archive --session "$2" --reason "$3" >"$WORKDIR/archive.out" 2>"$WORKDIR/archive.err"
    rc=$?
    if [ "$rc" -ne 0 ] && grep -q -F -- "$4" "$WORKDIR/archive.err" \
        && [ -f "$hd/result.json" ] && [ "$(cat "$hd/result.json")" = "$before" ] && [ -f "$hd/run.json" ] \
        && [ "$(archived_count "$hd")" -eq 0 ] && [ ! -e "$KOTO_STUB_STORE/$2/verification_attempts" ]; then
        pass "$1: --archive refuses (exit $rc) and moves and records nothing"
    else
        fail "$1: --archive exit $rc, stderr $(cat "$WORKDIR/archive.err"), head dir $(ls -R "$hd" 2>&1 | tr '\n' ' ')"
    fi
}

# Refusals: an empty or blank reason, a passing result, a running suite.
mkrepo arcfail "$(map '{"bad": {"run": ["bin/fail.sh"]}}' '[]' '["bad"]')"
change top.txt
start s-arcfail
settle s-arcfail
expect_rc "a failed command to archive" 1
expect_archive_refused "an empty reason" s-arcfail "" "the reason is empty"
expect_archive_refused "a blank reason" s-arcfail "   " "the reason is empty"

cd "$WORKDIR/r-att" || exit 2
start s-arcpass
settle s-arcpass
expect_rc "a passing result to archive" 0
expect_archive_refused "a passing result" s-arcpass "flaky" "ineligible passed"

mkrepo arclock "$(map '{"slow": {"run": ["bin/slow.sh"], "timeout_secs": 60}}' '[]' '["slow"]')"
change top.txt
start s-arclock
HD=$(head_dir s-arclock)
n=0
while [ ! -e "$HD/attempts/1/0-slow.log" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
SUP=$(readlink "$HD/lock" 2>/dev/null)
SLOWPID=""
command -v pgrep >/dev/null 2>&1 && SLOWPID=$(pgrep -f "$WORKDIR/r-arclock/bin/slow.sh" 2>/dev/null | head -n 1)
if [ -n "$SUP" ] && kill -0 "$SUP" 2>/dev/null; then
    # An eligible result for this head beside the live lock, so the lock is
    # the only thing that can refuse the archive.
    jq -cn --arg h "$(locate_line s-arclock 1)" --arg mb "$(locate_line s-arclock 2)" \
        '{schema: "shirabe-verification-result/v1", head: $h, merge_base: $mb, status: "done", detail: "",
          commands: [{id: "slow", argv: ["bin/slow.sh"], exit_status: 1, duration_secs: 1, timed_out: false,
                      runaway: false, not_started: false, pgid: 1, log: null}]}' > "$HD/result.json"
    expect_archive_refused "a running suite" s-arclock "flaky" "still running"
    kill -TERM "$SUP" 2>/dev/null
    n=0
    while kill -0 "$SUP" 2>/dev/null && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
else
    fail "a running suite: the slow suite never started (supervisor [$SUP])"
fi
[ -n "$SLOWPID" ] && kill -KILL -- "-$SLOWPID" 2>/dev/null

# A successful archive of a failed command's result.
cd "$WORKDIR/r-arcfail" || exit 2
HD=$(head_dir s-arcfail)
AH=$(locate_line s-arcfail 1)
AMB=$(jq -r .merge_base "$HD/result.json")
REASON='flaky "net" test'
LEDGER="$KOTO_STUB_STORE/s-arcfail/verification_attempts"
"$START" --archive --session s-arcfail --reason "$REASON" >"$WORKDIR/archive.out" 2>"$WORKDIR/archive.err"
RC=$?
[ "$RC" -eq 0 ] && pass "an eligible failed result archives (exit 0)" \
    || fail "an eligible failed result: --archive exit $RC, stderr $(cat "$WORKDIR/archive.err")"
if [ -f "$LEDGER" ] && [ "$(wc -l < "$LEDGER" | tr -d ' ')" -eq 1 ] \
    && head -n 1 "$LEDGER" | jq -e --arg h "$AH" --arg mb "$AMB" --arg r "$REASON" \
        '.attempt == 1 and .folder == 1 and .head == $h and .merge_base == $mb and .reason == $r' >/dev/null 2>&1; then
    pass "the archive writes one parseable ledger line: attempt 1, folder 1, the head, the merge-base, the reason as given"
else
    fail "the ledger after the archive: $(cat "$LEDGER" 2>&1)"
fi
if [ -f "$HD/attempts/1/result.json" ] && [ -f "$HD/attempts/1/run.json" ] \
    && [ ! -e "$HD/result.json" ] && [ ! -e "$HD/run.json" ]; then
    pass "the archive moves result.json and run.json into attempts/1/"
else
    fail "after the archive, the head directory holds: $(ls -R "$HD" 2>&1 | tr '\n' ' ')"
fi

# A re-run request beside a passing result: dropped, the pass reused.
mkrepo rrpass "$(map "{\"ok\": $(rec "$WORKDIR/rrpass.rec" ok)}" '[]' '["ok"]')"
change top.txt
start s-rrpass
settle s-rrpass
expect_rc "a passing result before a re-run request" 0
HD=$(head_dir s-rrpass)
cp "$HD/result.json" "$WORKDIR/rrpass.before"
mkdir -p "$KOTO_STUB_STORE/s-rrpass"
printf 'please run it again\n' > "$KOTO_STUB_STORE/s-rrpass/verification_rerun_request"
"$START" --start --session s-rrpass >"$WORKDIR/rr.out" 2>"$WORKDIR/rr.err"
RC=$?
[ "$RC" -eq 0 ] && pass "a re-run request beside a pass: --start exits 0" \
    || fail "a re-run request beside a pass: --start exit $RC, stderr $(cat "$WORKDIR/rr.err")"
[ ! -e "$KOTO_STUB_STORE/s-rrpass/verification_rerun_request" ] \
    && grep -q -F 'remove s-rrpass verification_rerun_request' "$KOTO_STUB_STORE/log" \
    && pass "a re-run request beside a pass is removed" \
    || fail "the re-run request beside a pass is still there"
grep -q -F 'rerun request dropped' "$WORKDIR/rr.err" \
    && pass "a dropped re-run request says why on stderr" \
    || fail "a dropped re-run request printed no reason: $(cat "$WORKDIR/rr.err")"
if cmp -s "$HD/result.json" "$WORKDIR/rrpass.before" && [ ! -e "$HD/attempts/2" ] \
    && [ ! -e "$HD/lock" ] && [ ! -e "$KOTO_STUB_STORE/s-rrpass/verification_attempts" ]; then
    pass "the pass is reused: result.json unchanged, no attempts/2, no supervisor, no ledger"
else
    fail "a re-run request beside a pass changed something: $(ls -R "$HD" 2>&1 | tr '\n' ' ')"
fi

# A re-run request beside an eligible failed result: archived, run again.
mkrepo rrfail "$(map '{"bad": {"run": ["bin/fail.sh"]}}' '[]' '["bad"]')"
change top.txt
start s-rrfail
settle s-rrfail
expect_rc "a failed command before a re-run request" 1
HD=$(head_dir s-rrfail)
LEDGER="$KOTO_STUB_STORE/s-rrfail/verification_attempts"
mkdir -p "$KOTO_STUB_STORE/s-rrfail"
printf 'flaky once\n' > "$KOTO_STUB_STORE/s-rrfail/verification_rerun_request"
"$START" --start --session s-rrfail >"$WORKDIR/rr.out" 2>"$WORKDIR/rr.err"
RC=$?
[ "$RC" -eq 0 ] && pass "a re-run request beside a failure: --start exits 0" \
    || fail "a re-run request beside a failure: --start exit $RC, stderr $(cat "$WORKDIR/rr.err")"
[ ! -e "$KOTO_STUB_STORE/s-rrfail/verification_rerun_request" ] \
    && pass "a re-run request beside a failure is removed" \
    || fail "the re-run request beside a failure is still there"
if [ -f "$LEDGER" ] && [ "$(wc -l < "$LEDGER" | tr -d ' ')" -eq 1 ] \
    && head -n 1 "$LEDGER" | jq -e '.attempt == 1 and .folder == 1 and .reason == "flaky once"' >/dev/null 2>&1; then
    pass "the re-run request's archive writes one parseable ledger line: attempt 1, folder 1, the reason"
else
    fail "the ledger after the re-run request: $(cat "$LEDGER" 2>&1)"
fi
[ -f "$HD/attempts/1/result.json" ] && [ -f "$HD/attempts/1/run.json" ] \
    && pass "the re-run request archives result.json and run.json into attempts/1/" \
    || fail "attempts/1/ after the re-run request: $(ls "$HD/attempts/1" 2>&1 | tr '\n' ' ')"
settle s-rrfail
expect_rc "the re-run's failed command" 1
if [ -f "$HD/attempts/2/0-bad.log" ] && [ -f "$HD/result.json" ] \
    && jq -e --arg l "$HD/attempts/2/0-bad.log" '.commands[0].log == $l' "$HD/result.json" >/dev/null 2>&1 \
    && jq -e '.attempt == 2' "$HD/run.json" >/dev/null 2>&1; then
    pass "a new supervisor runs the suite again, its logs under attempts/2/ and its result at the head directory"
else
    fail "after the re-run: $(ls -R "$HD" 2>&1 | tr '\n' ' '); result $(head -c 300 "$HD/result.json" 2>&1)"
fi

# A second lap at the same head: attempt 2 of this head and merge-base.
"$START" --archive --session s-rrfail --reason "flaky twice" >"$WORKDIR/archive.out" 2>"$WORKDIR/archive.err"
RC=$?
[ "$RC" -eq 0 ] && pass "a second failure at the same head archives (exit 0)" \
    || fail "a second failure at the same head: --archive exit $RC, stderr $(cat "$WORKDIR/archive.err")"
FIRST_HEAD=$(head -n 1 "$LEDGER" | jq -r .head 2>/dev/null)
if [ -f "$LEDGER" ] && [ "$(wc -l < "$LEDGER" | tr -d ' ')" -eq 2 ] && [ -n "$FIRST_HEAD" ] \
    && tail -n 1 "$LEDGER" | jq -e --arg h "$FIRST_HEAD" \
        '.attempt == 2 and .folder == 2 and .head == $h' >/dev/null 2>&1; then
    pass "the second archive at a head adds a second ledger line: attempt 2, folder 2, the same head"
else
    fail "the ledger after the second archive: $(cat "$LEDGER" 2>&1)"
fi
[ -f "$HD/attempts/2/result.json" ] \
    && pass "the second archive moves result.json into attempts/2/" \
    || fail "attempts/2/ after the second archive: $(ls "$HD/attempts/2" 2>&1 | tr '\n' ' ')"

# Ledger lines for another head or another merge-base do not count toward
# this head's attempt number.
mkrepo arcother "$(map '{"bad": {"run": ["bin/fail.sh"]}}' '[]' '["bad"]')"
change top.txt
start s-arcother
settle s-arcother
expect_rc "a failed command beside other heads' ledger lines" 1
HD=$(head_dir s-arcother)
AH=$(locate_line s-arcother 1)
AMB=$(jq -r .merge_base "$HD/result.json")
OTHER_SHA=0123456789abcdef0123456789abcdef01234567
LEDGER="$KOTO_STUB_STORE/s-arcother/verification_attempts"
mkdir -p "$KOTO_STUB_STORE/s-arcother"
{
    jq -nc --arg h "$OTHER_SHA" --arg mb "$AMB" '{attempt: 1, folder: 1, head: $h, merge_base: $mb, reason: "another head"}'
    jq -nc --arg h "$AH" --arg mb "$OTHER_SHA" '{attempt: 1, folder: 1, head: $h, merge_base: $mb, reason: "another merge-base"}'
} > "$WORKDIR/arcother.seed"
cp "$WORKDIR/arcother.seed" "$LEDGER"
"$START" --archive --session s-arcother --reason "flaky" >"$WORKDIR/archive.out" 2>"$WORKDIR/archive.err"
RC=$?
[ "$RC" -eq 0 ] && pass "a failure beside other heads' ledger lines archives (exit 0)" \
    || fail "a failure beside other heads' ledger lines: --archive exit $RC, stderr $(cat "$WORKDIR/archive.err")"
if [ -f "$LEDGER" ] && [ "$(wc -l < "$LEDGER" | tr -d ' ')" -eq 3 ] \
    && tail -n 1 "$LEDGER" | jq -e --arg h "$AH" --arg mb "$AMB" \
        '.attempt == 1 and .folder == 1 and .head == $h and .merge_base == $mb' >/dev/null 2>&1; then
    pass "lines for another head or merge-base do not count: the new line is attempt 1, folder 1, this head and merge-base"
else
    fail "the ledger beside other heads' lines: $(cat "$LEDGER" 2>&1)"
fi
head -n 2 "$LEDGER" > "$WORKDIR/arcother.head2"
cmp -s "$WORKDIR/arcother.head2" "$WORKDIR/arcother.seed" \
    && pass "the archive keeps the earlier ledger lines byte for byte" \
    || fail "the earlier ledger lines changed: $(cat "$LEDGER" 2>&1)"

# A ledger line that will not parse refuses the archive before anything is
# written or moved.
mkrepo arcbad "$(map '{"bad": {"run": ["bin/fail.sh"]}}' '[]' '["bad"]')"
change top.txt
start s-arcbad
settle s-arcbad
expect_rc "a failed command beside a ledger line that will not parse" 1
HD=$(head_dir s-arcbad)
LEDGER="$KOTO_STUB_STORE/s-arcbad/verification_attempts"
mkdir -p "$KOTO_STUB_STORE/s-arcbad"
{
    jq -nc --arg h "$OTHER_SHA" --arg mb "$OTHER_SHA" '{attempt: 1, folder: 1, head: $h, merge_base: $mb, reason: "another head"}'
    printf 'not json\n'
} > "$LEDGER"
cp "$LEDGER" "$WORKDIR/arcbad.before"
"$START" --archive --session s-arcbad --reason "flaky" >"$WORKDIR/archive.out" 2>"$WORKDIR/archive.err"
RC=$?
if [ "$RC" -ne 0 ] && grep -q -F 'could not count the attempts' "$WORKDIR/archive.err" \
    && cmp -s "$LEDGER" "$WORKDIR/arcbad.before" \
    && [ -f "$HD/result.json" ] && [ -f "$HD/run.json" ] && [ "$(archived_count "$HD")" -eq 0 ]; then
    pass "a ledger line that will not parse: --archive refuses (exit $RC), the ledger unchanged and nothing moved"
else
    fail "a ledger line that will not parse: --archive exit $RC, stderr $(cat "$WORKDIR/archive.err"), ledger $(cat "$LEDGER" 2>&1), head dir $(ls -R "$HD" 2>&1 | tr '\n' ' ')"
fi

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
