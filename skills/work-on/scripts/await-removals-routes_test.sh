#!/usr/bin/env bash
# await-removals-routes_test.sh -- does work-on.md hold a run before setup
# while a build-output removal is still running in its work tree, driven
# through real `koto next` calls?
#
# The shipped template, against a scratch plugin root holding the real
# run-verification.sh, in a scratch repository whose git directory holds a
# removal record. The record reads live while a stand-in deleter, a script
# named clean-build-output.sh started as `clean-build-output.sh --delete
# <stamp>`, waits for the test to let it go; it then rewrites the record as
# done and exits. For each state the gate sits on (context_injection on the
# issue-backed path, post_research_validation on the free-form path,
# plan_context_injection on the plan-backed path, with and without
# SHARED_BRANCH), a submission that would leave for setup or plan_validation
# holds while the record reads live, no setup state is entered (koto's run
# journal), and the first tick after the record reads done moves on. Then: a
# person's override of await_removals lets a held run on; a work tree with no
# records directory, or a plugin root with no runner, passes at once; a
# `status: completed` with no context.md holds; the blocked edge needs no
# gate; and the compiled template keeps the gate on every edge into a setup
# state or plan_validation, with no unconditional edge left beside them.
#
# The engine cases skip, loudly, when koto is absent (the bash 3.2 floor leg
# has no koto).
#
# Usage: await-removals-routes_test.sh
# Exit codes: 0 all pass (or the engine cases skipped), 1 any failed, 2 the
# harness could not run.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
finish() {
    echo
    echo "await-removals-routes_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
}

[ -f "$TEMPLATE" ] || { echo "template not found: $TEMPLATE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required to run this suite" >&2; exit 2; }

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto is not on PATH; the engine cases did not run"
    finish
fi

# The directory's name carries a marker unique to this run, so the stand-in
# deleters it starts can be found, and only they can be, at the end.
MARK="awaitrm$$x$RANDOM"
T=$(mktemp -d "${TMPDIR:-/tmp}/$MARK.XXXXXX") || exit 2
T=$(cd -P "$T" && pwd -P) || exit 2
reap_ours() {
    command -v pgrep >/dev/null 2>&1 || return 0
    for p in $(pgrep -f "$MARK" 2>/dev/null); do
        [ "$p" = "$$" ] && continue
        kill -KILL "$p" 2>/dev/null
    done
    return 0
}
cleanup() { reap_ours; case "${T:-}" in */"$MARK".*) rm -rf "$T" ;; esac; return 0; }
ktg_on_exit cleanup

export KOTO_SESSIONS_BASE="$T/sessions"
mkdir -p "$KOTO_SESSIONS_BASE"
JOURNAL="$KOTO_SESSIONS_BASE/_run_journal.jsonl"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t

# The plugin root: the real scripts the walk to setup runs. koto refuses a
# variable value with a character outside its allowlist, which a checkout path
# may hold, so the root is a copy under the scratch directory.
ROOT="$T/root"
mkdir -p "$ROOT/skills/work-on"
cp -R "$SCRIPT_DIR" "$ROOT/skills/work-on/scripts"
NORUNNER="$T/root-norunner"
mkdir -p "$NORUNNER/skills/work-on/scripts"

# The stand-in deleter: named and called the way the real one is, so
# bo_record_live reads its record live. It waits for <records dir>/go-<stamp>,
# then rewrites the record as done, with ended_at, atomically, and exits.
FAKE="$T/bin/clean-build-output.sh"
mkdir -p "$T/bin"
cat > "$FAKE" <<'EOF'
#!/bin/sh
stamp=$2 dir=$3
rec="$dir/removal-$stamp.json"
while [ ! -e "$dir/go-$stamp" ]; do sleep 0.1; done
jq -c --arg e "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.status = "done" | .ended_at = $e' "$rec" > "$rec.tmp" \
    && mv -f "$rec.tmp" "$rec"
EOF
chmod +x "$FAKE"

N=0
# mkrepo: a fresh repository with one commit, in REPO.
mkrepo() {
    N=$((N + 1))
    REPO="$T/repo-$N"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" commit -q --allow-empty -m init
}

# live_record: a running removal record in REPO's git directory, its deleter
# started and waiting. Sets STAMP and REC.
live_record() {
    local dir="$REPO/.git/shirabe-build-output" pid
    mkdir -p "$dir"
    STAMP="20261116T080412Z-$N$RANDOM"
    REC="$dir/removal-$STAMP.json"
    "$FAKE" --delete "$STAMP" "$dir" </dev/null >/dev/null 2>&1 &
    pid=$!
    jq -cn --argjson pid "$pid" '{schema: "shirabe-build-output-removal/v1",
        started_at: "2026-11-16T08:04:12Z", pid: $pid, paths: {"1": "target"}, reaped: [],
        status: "running"}' > "$REC"
}

# release: let the deleter go and wait until the record reads done.
release() {
    local n=0
    : > "$(dirname "$REC")/go-$STAMP"
    while ! jq -e '.status == "done"' "$REC" >/dev/null 2>&1 && [ "$n" -lt 100 ]; do
        sleep 0.1; n=$((n + 1))
    done
}

k() { (cd "$REPO" && koto "$@"); }
S=0
# init <prefix> [--var K=V]...: init the shipped template in REPO; SESS names it.
init() {
    local prefix=$1; shift
    S=$((S + 1)); SESS="await-$S"
    k init "$SESS" --template "$TEMPLATE" --var ARTIFACT_PREFIX="${prefix}_$S" "$@" >/dev/null 2>"$T/init.err"
}
submit() { RESP=$(k next "$SESS" --no-cleanup --with-data "$1" 2>&1); }
tick() { RESP=$(k next "$SESS" --no-cleanup 2>&1); }
state() { k status "$SESS" 2>/dev/null | jq -r '.current_state // empty'; }
# entered <state>: how many times the journal has SESS entering <state>.
entered() {
    [ -f "$JOURNAL" ] || { echo 0; return; }
    jq -c --arg s "$SESS" --arg st "$1" 'select(.kind == "state_entered" and .session == $s and ."koto.state" == $st)' \
        "$JOURNAL" | grep -c .
}
blocked_on_gate() {
    printf '%s' "$RESP" | jq -e '[.blocking_conditions[]? | select(.name == "await_removals")] | length == 1' >/dev/null 2>&1
}

# held <label> <state> <setup states>: the run is at <state>, the response
# names await_removals as what holds it, and no <setup state> was entered.
held() {
    local st n=0
    for st in $3; do n=$((n + $(entered "$st"))); done
    if [ "$(state)" = "$2" ] && blocked_on_gate && [ "$n" -eq 0 ]; then
        pass "$1: holds at $2 on await_removals and enters no setup state"
    else
        fail "$1: at [$(state)], setup entries $n, response $(head -c 400 <<<"$RESP")"
    fi
}
moved() { # moved <label> <state>: the run left for <state>
    if [ "$(entered "$2")" -ge 1 ]; then
        pass "$1: moves on to $2"
    else
        fail "$1: never entered $2; at [$(state)], response $(head -c 400 <<<"$RESP")"
    fi
}

# --- the issue-backed path: context_injection -------------------------------------------

mkrepo
live_record
init issue --var PLUGIN_ROOT="$ROOT" --var ISSUE_NUMBER=42 || { fail "init: $(cat "$T/init.err")"; finish; }
submit '{"mode":"issue_backed","issue_number":"42"}'
printf 'context\n' | k context add "$SESS" context.md >/dev/null 2>&1
submit '{"status":"completed"}'
held "issue-backed, completed" context_injection setup_issue_backed
tick
held "issue-backed, a plain tick while it is still live" context_injection setup_issue_backed
release
tick
moved "issue-backed, the first tick after the record reads done" setup_issue_backed

mkrepo
live_record
init issue --var PLUGIN_ROOT="$ROOT" --var ISSUE_NUMBER=42
submit '{"mode":"issue_backed","issue_number":"42"}'
submit '{"status":"override"}'
held "issue-backed, override" context_injection setup_issue_backed
release
tick
moved "issue-backed override, the first tick after the record reads done" setup_issue_backed

# --- the free-form path: post_research_validation ----------------------------------------

mkrepo
live_record
init task --var PLUGIN_ROOT="$ROOT"
submit '{"mode":"free_form","task_description":"add a flag"}'
submit '{"verdict":"proceed"}'
submit '{"context_summary":"read the code"}'
submit '{"verdict":"ready"}'
held "free-form, ready" post_research_validation setup_free_form
release
tick
moved "free-form, the first tick after the record reads done" setup_free_form

# --- the plan-backed path: plan_context_injection ----------------------------------------

PLAN="$T/PLAN-x.md"
printf -- '---\nschema: plan/v1\n---\n' > "$PLAN"
for shared in "" impl/x-node; do
    label="plan-backed, plan_outline${shared:+, SHARED_BRANCH set}"
    mkrepo
    live_record
    if [ -n "$shared" ]; then
        init plan --var PLUGIN_ROOT="$ROOT" --var ISSUE_SOURCE=plan_outline --var ISSUE_NUMBER=1 \
            --var PLAN_DOC="$PLAN" --var SHARED_BRANCH="$shared"
    else
        init plan --var PLUGIN_ROOT="$ROOT" --var ISSUE_SOURCE=plan_outline --var ISSUE_NUMBER=1 \
            --var PLAN_DOC="$PLAN"
    fi
    submit '{"mode":"plan_backed","issue_source":"plan_outline","issue_number":"1"}'
    printf 'outline\n' | k context add "$SESS" context.md >/dev/null 2>&1
    submit '{"status":"completed","issue_source":"plan_outline"}'
    held "$label" plan_context_injection "plan_validation setup_plan_backed"
    release
    tick
    moved "$label, the first tick after the record reads done" plan_validation
done

mkrepo
live_record
init plan --var PLUGIN_ROOT="$ROOT" --var ISSUE_SOURCE=github --var ISSUE_NUMBER=1 --var SHARED_BRANCH=impl/x-node
submit '{"mode":"plan_backed","issue_source":"github","issue_number":"1"}'
printf 'issue\n' | k context add "$SESS" context.md >/dev/null 2>&1
submit '{"status":"completed","issue_source":"github"}'
held "plan-backed, github, SHARED_BRANCH set" plan_context_injection "setup_plan_backed analysis"
release
tick
moved "plan-backed github child, the first tick after the record reads done" setup_plan_backed

# --- an override, no records, no runner ------------------------------------------------------

mkrepo
live_record
init issue --var PLUGIN_ROOT="$ROOT" --var ISSUE_NUMBER=42
submit '{"mode":"issue_backed","issue_number":"42"}'
submit '{"status":"override"}'
held "before the override" context_injection setup_issue_backed
# From koto 0.37.0 an override needs a decider, and the guard clears the
# caller's session id, so the call carries a stand-in one (shirabe#1733).
if (cd "$REPO" && env CLAUDE_CODE_SESSION_ID=await-removals-test-agent koto overrides record "$SESS" \
        --gate await_removals --rationale "the record's pid was reused") >"$T/ovr.out" 2>&1; then
    tick
    moved "a person's override of await_removals while the record reads live" setup_issue_backed
else
    fail "koto refused the override of await_removals: $(cat "$T/ovr.out")"
fi
release

mkrepo
init issue --var PLUGIN_ROOT="$ROOT" --var ISSUE_NUMBER=42
submit '{"mode":"issue_backed","issue_number":"42"}'
submit '{"status":"override"}'
moved "no shirabe-build-output directory: the gate passes" setup_issue_backed

mkrepo
mkdir -p "$REPO/.git/shirabe-build-output"
printf '{"status": "done", "ended_at": "2026-11-16T08:05:00Z"}\n' \
    > "$REPO/.git/shirabe-build-output/removal-20261116T080412Z-1.json"
printf 'not json\n' > "$REPO/.git/shirabe-build-output/removal-20261116T080413Z-2.json"
init issue --var PLUGIN_ROOT="$ROOT" --var ISSUE_NUMBER=42
submit '{"mode":"issue_backed","issue_number":"42"}'
submit '{"status":"override"}'
moved "only a done and an unparsable record: the gate passes" setup_issue_backed

mkrepo
live_record
init issue --var PLUGIN_ROOT="$NORUNNER" --var ISSUE_NUMBER=42
submit '{"mode":"issue_backed","issue_number":"42"}'
submit '{"status":"override"}'
moved "a plugin root with no runner: the gate passes" setup_issue_backed
release

# --- what holds regardless of the gate ------------------------------------------------------

mkrepo
init issue --var PLUGIN_ROOT="$ROOT" --var ISSUE_NUMBER=42
submit '{"mode":"issue_backed","issue_number":"42"}'
submit '{"status":"completed"}'
if [ "$(state)" = context_injection ] && [ "$(entered setup_issue_backed)" -eq 0 ]; then
    pass "status: completed with no context.md holds at context_injection (no unconditional edge)"
else
    fail "status: completed with no context.md left context_injection for [$(state)]"
fi

mkrepo
live_record
init issue --var PLUGIN_ROOT="$ROOT" --var ISSUE_NUMBER=42
submit '{"mode":"issue_backed","issue_number":"42"}'
submit '{"status":"blocked","detail":"no issue"}'
[ "$(state)" = done_blocked ] && pass "the blocked edge needs no gate: done_blocked while the record reads live" \
    || fail "blocked while the record reads live reached [$(state)]"
release

# --- the compiled template ---------------------------------------------------------------------

COMPILED=$(koto template compile "$TEMPLATE" 2>/dev/null | tail -n 1)
if [ -f "$COMPILED" ]; then
    # Every edge out of the three states into a setup state or plan_validation
    # requires the gate at 0, and every edge has a condition. The six such
    # edges are counted too, so a compiled shape this doesn't read can't pass.
    EDGES='.states as $s
        | ["context_injection", "post_research_validation", "plan_context_injection"][] as $n
        | $s[$n].transitions[] | . + {from: $n}'
    bad=$(jq -r "$EDGES"'
        | select((.when // null) == null
                 or ((.target | test("^setup_|^plan_validation$"))
                     and .when["gates.await_removals.exit_code"] != 0))
        | "\(.from) -> \(.target)"' "$COMPILED" 2>&1)
    gated=$(jq -r "[$EDGES"' | select(.target | test("^setup_|^plan_validation$"))] | length' "$COMPILED" 2>&1)
    [ -z "$bad" ] && [ "$gated" = 6 ] \
        && pass "the six edges into setup or plan_validation require await_removals, and none is unconditional" \
        || fail "edges into setup or plan_validation: $gated, without the gate: $bad"
    gates=$(jq -r '[.states.context_injection, .states.post_research_validation, .states.plan_context_injection
        | .gates.await_removals.command] | unique | length' "$COMPILED")
    [ "$gates" = 1 ] && pass "the three states run the same await_removals command" \
        || fail "the three states' await_removals commands differ or are missing"
else
    fail "koto template compile gave no compiled file: [$COMPILED]"
fi
if (cd "$SKILL_DIR/koto-templates" && koto template export work-on.md --output work-on.mermaid.md --check >/dev/null 2>&1); then
    pass "work-on.mermaid.md matches the template"
else
    fail "work-on.mermaid.md is stale; regenerate it with koto template export"
fi

reap_ours
finish
