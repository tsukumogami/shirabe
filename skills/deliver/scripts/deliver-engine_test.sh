#!/usr/bin/env bash
# deliver-engine_test.sh -- deliver.md on a real koto, walked through every
# route that matters, with the outcome asserted from `koto status` on the
# deliver-<topic> session.
#
# The children are stand-ins: throwaway templates named scope.md and
# execute.md (the file names the legs accept), each a single state whose
# evidence becomes its terminal result, so a case can make a child promote any
# payload it needs. They attach to this run's legs with `koto init
# --koto-leg`, exactly as /scope and /execute do. The re-checks run for real
# (deliver-probe.sh, owned-pr.sh, publish-scoping-pr.sh --verify,
# merge-verdict.sh --confirm) against real git with a local bare origin and
# the gh stand-in in testdata/gh.
#
# Routes asserted:
#   - the three paths into `done` and the `pr` each reports: the /execute
#     leg's own pr on ready-awaiting-merge; the owned PR the probe found on
#     merged_check and on executed_check, replacing the leg's; no pr at all
#     when merged_check's lookup failed
#   - the --auto merged happy path: checked_pr left non-empty by scoped_check
#     before mode_route, and a `done` result whose pr equals the owned PR's
#     URL and checked_pr
#   - a merged claim GitHub contradicts is downgraded to ready-awaiting-merge,
#     and a leg pr naming some other merged PR is ignored
#   - explicit resolves with progress-shaped payloads on either leg end
#     deliver:child-absent without reaching scoped_check, execute_run,
#     merged_check, done or done_stopped, and without the forged pr
#   - `koto overrides record`, with and without --with-data, refused on both
#     leg gates and the intent gate
#   - a child that never attaches ends deliver:child-absent through the absent
#     state; a child bound in the meantime keeps the run waiting
#   - refusals on the leg: an invalid INTENT_FLAG (scope:refused), a live
#     intent=stop session (deliver:intent-mismatch), a throwaway template on
#     the execute leg (execute:refused); a promoted intent-mismatch refusal
#   - /scope stopping early (scope-ended-early naming which), its errors, an
#     unrecognised outcome (deliver:child-outcome), the multi-pr hand-off with
#     no /execute leg bound, the interactive confirmation (stop and proceed),
#     /execute's pauses and errors, an abandoned request, a private repository
#   - the stale-run fence: a new run abandons the old request, and the old
#     run's child finishing later does not answer the new run's leg
#
# In a checkout whose path koto's --var allowlist refuses (a `+` in a
# directory name), the cases run a copy of deliver.md with this checkout's
# path written in for {{PLUGIN_ROOT}}, as the other engine suites do.
#
# Usage: bash skills/deliver/scripts/deliver-engine_test.sh
# Exit codes: 0 all pass (SKIP when koto or jq is absent); 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd)
TEMPLATE="$REPO_ROOT/skills/deliver/koto-templates/deliver.md"

for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine-backed cases did not run"; exit 0; }
done
if ! koto init --help 2>/dev/null | grep -q -- '--koto-leg'; then
    echo "SKIP: this koto predates --koto-leg -- no case ran"
    exit 0
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/deliver-engine-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME"
export GIT_CEILING_DIRECTORIES="$T"
export MERGE_CONFIRM_WAIT_SECS=0

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }

KOTO_ALLOW='^[a-zA-Z0-9._/:@ -]*$'
TPL="$TEMPLATE"
if [[ $REPO_ROOT =~ $KOTO_ALLOW ]]; then
    PLUGIN_ROOT_VAR="$REPO_ROOT"
else
    ln -s "$REPO_ROOT" "$T/plugin"
    if [[ $T/plugin =~ $KOTO_ALLOW ]]; then
        PLUGIN_ROOT_VAR="$T/plugin"
    else
        mkdir -p "$T/derived"
        TPL="$T/derived/deliver.md"
        sed "s#{{PLUGIN_ROOT}}#$REPO_ROOT#g" "$TEMPLATE" >"$TPL"
        PLUGIN_ROOT_VAR=/koto-probe
        echo "  note: this checkout's path is outside koto's --var allowlist, so these cases run a"
        echo "        copy of deliver.md with the path written in for {{PLUGIN_ROOT}}"
    fi
fi

BIN="$T/bin"
mkdir -p "$BIN"
cp "$HERE/testdata/gh" "$BIN/gh"
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

# --- stand-in children ------------------------------------------------------------

mkdir -p "$T/tpl"
child_template() { # child_template <file> <name> <variables block>
    cat >"$1" <<TPL
---
name: $2
version: "1.0"
description: a stand-in child for deliver-engine_test.sh
initial_state: work
variables:
$3
states:
  work:
    accepts:
      finish:
        type: enum
        values: [go]
        required: true
      outcome:
        type: string
      step:
        type: string
      reason:
        type: string
      pr:
        type: string
      pr_state:
        type: string
      plan_path:
        type: string
      plan_execution_mode:
        type: string
      startable:
        type: string
      wip_paths:
        type: string
      next:
        type: string
      repos:
        type: string
      resume:
        type: string
      waiting:
        type: string
    transitions:
      - target: done
        when:
          finish: go
        context_assignments:
          outcome: "\${evidence.outcome}"
          step: "\${evidence.step}"
          reason: "\${evidence.reason}"
          pr: "\${evidence.pr}"
          pr_state: "\${evidence.pr_state}"
          plan_path: "\${evidence.plan_path}"
          plan_execution_mode: "\${evidence.plan_execution_mode}"
          startable: "\${evidence.startable}"
          wip_paths: "\${evidence.wip_paths}"
          next: "\${evidence.next}"
          repos: "\${evidence.repos}"
          resume: "\${evidence.resume}"
          waiting: "\${evidence.waiting}"
  done:
    terminal: true
    result:
      outcome: "\${context.outcome}"
      step: "\${context.step}"
      reason: "\${context.reason}"
      pr: "\${context.pr}"
      pr_state: "\${context.pr_state}"
      plan_path: "\${context.plan_path}"
      plan_execution_mode: "\${context.plan_execution_mode}"
      startable: "\${context.startable}"
      wip_paths: "\${context.wip_paths}"
      next: "\${context.next}"
      repos: "\${context.repos}"
      resume: "\${context.resume}"
      waiting: "\${context.waiting}"
---
## work
Stand-in.
## done
Done.
TPL
}
child_template "$T/tpl/scope.md" scope "  TOPIC:
    required: true
  INTENT_FLAG:
    pattern: '^(continue|stop)?\$'
    default: \"\""
child_template "$T/tpl/execute.md" execute "  PLAN_SLUG:
    required: true"
mkdir -p "$T/forged"
child_template "$T/forged/forged.md" forged "  PLAN_SLUG:
    required: true"

# --- fixtures -----------------------------------------------------------------------

# fixture <topic> <single-pr|multi-pr|coordinated|executed|private> -- a
# repository on docs/<topic>, pushed to a bare origin. Sets R, TOPIC, URL,
# GH_DB (one owned open PR on the topic branch recording intent=continue).
fixture() {
    TOPIC="$1"
    R="$T/repo-$TOPIC"
    local o="$T/origin-$TOPIC.git" vis="Public"
    [ "$2" = private ] && vis="Private"
    git init -q --bare -b main "$o"
    git init -q -b main "$R"
    printf '# r\n\n## Repo Visibility: %s\n' "$vis" >"$R/CLAUDE.md"
    g add CLAUDE.md
    g commit -q -m init
    g remote add origin "$o"
    g push -q origin main
    g checkout -q -b "docs/$TOPIC"
    mkdir -p "$R/docs/plans" "$R/docs/designs/current"
    case "$2" in
        executed)
            printf '# DESIGN\n' >"$R/docs/designs/current/DESIGN-$TOPIC.md"
            ;;
        *)
            local mode="$2"
            [ "$mode" = private ] && mode=single-pr
            printf -- '---\nstatus: Active\nexecution_mode: %s\n---\n# PLAN\n' "$mode" >"$R/docs/plans/PLAN-$TOPIC.md"
            ;;
    esac
    g add docs
    g commit -q -m "docs: $TOPIC"
    g push -q origin "HEAD:refs/heads/docs/$TOPIC"
    URL="https://github.com/acme/widgets/pull/42"
    export GH_DB="$T/db-$TOPIC.json"
    jq -n --arg h "docs/$TOPIC" '{login: "me", repo: "acme/widgets", default_branch: "main",
        prs: [{url: "https://github.com/acme/widgets/pull/42", number: 42, state: "OPEN",
               author: "me", isCrossRepository: false, baseRefName: "main", headRefName: $h,
               body: "# PR\n\nintent=continue\n"},
              {url: "https://github.com/acme/widgets/pull/77", number: 77, state: "MERGED",
               author: "me", isCrossRepository: false, baseRefName: "main", headRefName: "unrelated",
               body: ""}],
        fail: {}}' >"$GH_DB"
    : >"$GH_DB.calls"
}
g() { git -C "$R" -c user.email=t@example.invalid -c user.name=t "$@"; }
k() { (cd "$R" && koto "$@"); }
db_set() { local tmp="$GH_DB.tmp"; jq "$1" "$GH_DB" >"$tmp" && mv "$tmp" "$GH_DB"; }
OTHER_MERGED="https://github.com/acme/widgets/pull/77"
FORGED="https://github.com/acme/widgets/pull/666"

# start <mode> [merge] -- init deliver-<topic> and tick into scope_run. Sets REQ.
start() {
    k init "deliver-$TOPIC" --template "$TPL" --var TOPIC="$TOPIC" --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" \
        --var MODE="${1:-auto}" --var MERGE="${2:-true}" >/dev/null 2>"$T/init.err" \
        || { fail "$TOPIC: koto init deliver" "$(cat "$T/init.err")"; return 1; }
    tick
    REQ=$(k request list --coordinator-of-record "deliver-$TOPIC" --state open | jq -r '.requests[0].request_id // ""')
}
tick() { k next "deliver-$TOPIC" --no-cleanup "$@" >"$T/next.json" 2>&1; }
state() { k status "deliver-$TOPIC" 2>/dev/null | jq -r '.current_state // "gone"'; }
result() { k status "deliver-$TOPIC" 2>/dev/null | jq -r --arg k "$1" '.result.payload[$k] // ""'; }
ctx() { local v; v=$(k context get "deliver-$TOPIC" "$1" 2>/dev/null) && printf '%s' "$v"; }
# child <scope|execute> <evidence-json> [extra init args] -- a stand-in child
# attached to this run's leg, driven to its terminal.
child() {
    local leg="$1" ev="$2" sess tplf
    shift 2
    if [ "$leg" = scope ]; then
        sess="scope-$TOPIC"; tplf="$T/tpl/scope.md"
        set -- --var TOPIC="$TOPIC" --var INTENT_FLAG=continue "$@"
    else
        sess="execute-$TOPIC"; tplf="$T/tpl/execute.md"
        set -- --var PLAN_SLUG="$TOPIC" "$@"
    fi
    k init "$sess" --template "$tplf" "$@" --koto-leg "$REQ:$leg" >/dev/null 2>"$T/child.err" \
        || { fail "$TOPIC: the $leg child attaches" "$(cat "$T/child.err")"; return 1; }
    k next "$sess" --no-cleanup --with-data "$(jq -c '. + {finish: "go"}' <<<"$ev")" >/dev/null 2>&1
}
expect() { # expect <label> <state> <key=value>...
    local label="$1" want="$2" kv key val got ok=1
    shift 2
    if [ "$(state)" != "$want" ]; then
        fail "$label: stops at $want" "at $(state): $(head -c 600 "$T/next.json")"
        return
    fi
    for kv in "$@"; do
        key="${kv%%=*}"; val="${kv#*=}"
        got=$(result "$key")
        if [ "$val" = "+" ]; then
            [ -n "$got" ] || { fail "$label: result $key is empty"; ok=0; }
        elif [ "$got" != "$val" ]; then
            fail "$label: result $key" "want [$val], got [$got]"; ok=0
        fi
    done
    [ "$ok" -eq 1 ] && pass "$label: $want with $*"
}
to_execute_run() { # a scope child reports scoped, the re-check passes, auto mode
    child scope "{\"outcome\":\"scoped\",\"pr\":\"$FORGED\",\"plan_path\":\"docs/plans/PLAN-$TOPIC.md\",\"plan_execution_mode\":\"single-pr\"}"
    tick
}

# --- the three paths into done ----------------------------------------------------------

echo "== the --auto merged happy path =="
fixture happy single-pr
start auto && to_execute_run
eq "happy: at execute_run after scoped_check, mode_route and confirm" execute_run "$(state)"
eq "happy: scoped_check left checked_pr non-empty, the owned PR" "$URL" "$(ctx checked_pr)"
eq "happy: the leg's pr was replaced by the owned PR" "$URL" "$(ctx pr)"
db_set '(.prs[] | select(.number == 42) | .state) = "MERGED"'
child execute "{\"outcome\":\"merged\",\"pr\":\"$OTHER_MERGED\",\"repos\":\"acme/widgets\"}"
tick
expect "happy" done outcome=merged "pr=$URL" repos=acme/widgets
eq "happy: the result's pr equals checked_pr" "$(ctx checked_pr)" "$(result pr)"
eq "happy: merged_check confirmed it" merged "$(ctx merged_verdict)"

echo "== ready-awaiting-merge carries the /execute leg's own pr =="
fixture ready single-pr
start auto && to_execute_run
child execute "{\"outcome\":\"ready-awaiting-merge\",\"pr\":\"$URL\",\"waiting\":\"$URL:human\",\"reason\":\"merge-not-requested\",\"repos\":\"acme/widgets\"}"
tick
expect "ready" done outcome=ready-awaiting-merge "pr=$URL" "waiting=$URL:human" reason=merge-not-requested
if [ -z "$(ctx merged_verdict)" ]; then pass "ready: merged_check did not run"; else fail "ready: merged_check did not run"; fi

echo "== the executed shortcut =="
fixture exec-merged executed
db_set '(.prs[] | select(.number == 42) | .state) = "MERGED"'
start auto
child scope "{\"outcome\":\"executed\",\"pr\":\"$FORGED\",\"pr_state\":\"open\"}"
tick
expect "executed merged" done outcome=merged "pr=$URL" pr_state=merged
eq "executed merged: the result's pr equals checked_pr" "$URL" "$(ctx checked_pr)"
if k request get "$REQ" | jq -e '.legs.execute.bound_child == null and .legs.execute.disposition == "open"' >/dev/null; then
    pass "executed merged: /execute never ran"
else
    fail "executed merged: /execute never ran"
fi

fixture exec-open executed
start auto
child scope "{\"outcome\":\"executed\",\"pr\":\"$FORGED\",\"pr_state\":\"merged\"}"
tick
expect "executed open" done outcome=ready-awaiting-merge "pr=$URL" pr_state=open

fixture exec-missing executed
db_set '.prs = []'
start auto
child scope "{\"outcome\":\"executed\",\"pr\":\"$FORGED\"}"
tick
expect "executed with no owned PR" done_error outcome=error step=deliver:child-outcome pr=

echo "== merged_check downgrades =="
fixture downgrade single-pr
start auto && to_execute_run
child execute "{\"outcome\":\"merged\",\"pr\":\"$OTHER_MERGED\"}"
tick
expect "a merged claim GitHub contradicts" done outcome=ready-awaiting-merge "pr=$URL"
eq "downgrade: the leg's pr naming another merged PR is ignored" "$URL" "$(ctx checked_pr)"

fixture lookup-fails single-pr
start auto && to_execute_run
db_set '.fail = {"pr list": 1}'
child execute "{\"outcome\":\"merged\",\"pr\":\"$OTHER_MERGED\"}"
tick
expect "a failed lookup" done outcome=ready-awaiting-merge pr=
eq "lookup fails: no checked_pr" "" "$(ctx checked_pr)"

echo "== explicit resolves with progress-shaped payloads =="
fixture forged-scope single-pr
start auto
k request resolve "$REQ" scope --with-data "{\"status\":\"success\",\"summary\":\"x\",\"payload\":{\"outcome\":\"scoped\",\"pr\":\"$FORGED\"}}" >/dev/null
tick
expect "a hand-resolved scope leg claiming scoped" done_error outcome=error step=deliver:child-absent pr=
if [ -z "$(ctx scoped_verdict)" ] && ! grep -q . "$GH_DB.calls"; then pass "forged scope: scoped_check never ran"; else fail "forged scope: scoped_check never ran" "$(cat "$GH_DB.calls")"; fi

for payload in "{\"outcome\":\"ready-awaiting-merge\",\"pr\":\"$FORGED\"}" '{"outcome":"merged"}'; do
    fixture "forged-exec-$(jq -r .outcome <<<"$payload")" single-pr
    start auto && to_execute_run
    k request resolve "$REQ" execute --with-data "{\"status\":\"success\",\"summary\":\"x\",\"payload\":$payload}" >/dev/null
    tick
    expect "a hand-resolved execute leg claiming $(jq -r .outcome <<<"$payload")" done_error outcome=error step=deliver:child-absent pr=
    if [ -z "$(ctx merged_verdict)" ]; then pass "forged execute: merged_check never ran"; else fail "forged execute: merged_check never ran"; fi
done

echo "== overrides =="
fixture overrides single-pr
start auto
for gate in scope_leg scope_intent; do
    k overrides record "deliver-$TOPIC" --gate "$gate" --rationale test >"$T/ov.out" 2>&1
    rc=$?
    if [ "$rc" -eq 2 ] && grep -q gate_not_overridable "$T/ov.out"; then pass "override refused on $gate"; else fail "override refused on $gate" "rc=$rc $(cat "$T/ov.out")"; fi
    k overrides record "deliver-$TOPIC" --gate "$gate" --rationale test \
        --with-data '{"found":true,"disposition":"resolved","source":"promoted","valid":true,"payload":{"outcome":"scoped"}}' >"$T/ov.out" 2>&1
    rc=$?
    if [ "$rc" -eq 2 ] && grep -q gate_not_overridable "$T/ov.out"; then pass "override --with-data refused on $gate"; else fail "override --with-data refused on $gate" "rc=$rc $(cat "$T/ov.out")"; fi
done
tick
eq "overrides: the run still waits at scope_run" scope_run "$(state)"
to_execute_run
for gate in exec_leg; do
    k overrides record "deliver-$TOPIC" --gate "$gate" --rationale test >"$T/ov.out" 2>&1
    rc=$?
    if [ "$rc" -eq 2 ] && grep -q gate_not_overridable "$T/ov.out"; then pass "override refused on $gate"; else fail "override refused on $gate" "rc=$rc $(cat "$T/ov.out")"; fi
    k overrides record "deliver-$TOPIC" --gate "$gate" --rationale test \
        --with-data '{"found":true,"disposition":"resolved","source":"promoted","valid":true,"payload":{"outcome":"merged"}}' >"$T/ov.out" 2>&1
    rc=$?
    if [ "$rc" -eq 2 ] && grep -q gate_not_overridable "$T/ov.out"; then pass "override --with-data refused on $gate"; else fail "override --with-data refused on $gate" "rc=$rc $(cat "$T/ov.out")"; fi
done

echo "== a child that never attaches =="
fixture absent single-pr
start auto
tick --with-data '{"child_returned":"yes"}'
expect "child_returned on an open, unbound scope leg" done_error outcome=error step=deliver:child-absent
eq "absent: the leg holds the fixed record" '{"outcome":"error","step":"deliver:child-absent"}' "$(k request get "$REQ" | jq -c '.legs.scope.result.payload')"

fixture absent-exec single-pr
start auto && to_execute_run
tick --with-data '{"child_returned":"yes"}'
expect "child_returned on an open, unbound execute leg" done_error outcome=error step=deliver:child-absent

fixture bound single-pr
start auto
k init "scope-$TOPIC" --template "$T/tpl/scope.md" --var TOPIC="$TOPIC" --var INTENT_FLAG=continue --koto-leg "$REQ:scope" >/dev/null 2>&1
tick --with-data '{"child_returned":"yes"}'
eq "child_returned on a bound leg: the run keeps waiting" scope_run "$(state)"

echo "== refusals on the leg =="
fixture refuse-var single-pr
start auto
k init "scope-$TOPIC" --template "$T/tpl/scope.md" --var TOPIC="$TOPIC" --var INTENT_FLAG=bogus --koto-leg "$REQ:scope" >/dev/null 2>&1
tick
expect "an invalid INTENT_FLAG refused at init" done_error outcome=error step=scope:refused reason=invalid-var:INTENT_FLAG
if k status "scope-$TOPIC" >/dev/null 2>&1; then fail "the refused child opened no session"; else pass "the refused child opened no session"; fi

fixture refuse-intent single-pr
k init "scope-$TOPIC" --template "$T/tpl/scope.md" --var TOPIC="$TOPIC" --var INTENT_FLAG=stop >/dev/null 2>&1
start auto
k init "scope-$TOPIC" --template "$T/tpl/scope.md" --var TOPIC="$TOPIC" --var INTENT_FLAG=continue --attach-live --koto-leg "$REQ:scope" >/dev/null 2>&1
tick
expect "a live intent=stop run" done_error outcome=error step=deliver:intent-mismatch reason=var-mismatch:INTENT_FLAG

fixture promoted-intent single-pr
start auto
child scope '{"outcome":"refused","reason":"intent-mismatch","step":"scope:refused"}'
tick
expect "a promoted intent-mismatch refusal" done_error outcome=error step=deliver:intent-mismatch reason=intent-mismatch

fixture promoted-refused single-pr
start auto
child scope '{"outcome":"refused","reason":"plan-active","step":"scope:refused"}'
tick
expect "any other promoted refusal" done_error outcome=error step=scope:refused reason=plan-active

fixture forged-tpl single-pr
start auto && to_execute_run
k init "execute-$TOPIC" --template "$T/forged/forged.md" --var PLAN_SLUG="$TOPIC" --koto-leg "$REQ:execute" >/dev/null 2>&1
tick
expect "a throwaway template declaring merged is refused at attach" done_error outcome=error step=execute:refused reason=template-mismatch

echo "== /scope's other outcomes =="
for which in re-evaluation abandonment cancelled; do
    fixture "early-$which" single-pr
    start auto
    child scope "{\"outcome\":\"$which\"}"
    tick
    expect "/scope ended at $which" done_stopped outcome=scope-ended-early "reason=$which"
done

fixture scope-error single-pr
start auto
child scope '{"outcome":"error","step":"scope:push"}'
tick
expect "/scope's error keeps its step" done_error outcome=error step=scope:push

fixture scope-odd single-pr
start auto
child scope '{"outcome":"shipped"}'
tick
expect "an outcome /deliver doesn't recognise" done_error outcome=error step=deliver:child-outcome

fixture multi multi-pr
start auto
child scope "{\"outcome\":\"handed-off-multi-pr\",\"pr\":\"$URL\",\"startable\":\"#101 First\\n#102 Second\",\"next\":\"/work-on #101\"}"
tick
expect "a multi-pr PLAN" done_stopped outcome=handed-off-multi-pr "pr=$URL" "next=/work-on #101"
eq "multi-pr: the startable list is relayed" "#101 First
#102 Second" "$(result startable)"
if k request get "$REQ" | jq -e '.legs.execute.bound_child == null' >/dev/null; then pass "multi-pr: /execute never started"; else fail "multi-pr: /execute never started"; fi

echo "== the interactive confirmation =="
fixture confirm-stop single-pr
start interactive && to_execute_run
eq "interactive: stops at confirm" confirm "$(state)"
tick --with-data '{"decision":"stop"}'
expect "a declined confirmation" done_stopped outcome=scoped "next=/deliver confirm-stop" "pr=$URL"

fixture confirm-go single-pr
start interactive && to_execute_run
tick --with-data '{"decision":"proceed"}'
eq "a confirmed run goes on to execute_run" execute_run "$(state)"

fixture auto-stray single-pr
start auto && to_execute_run
eq "--auto asks nothing" execute_run "$(state)"

echo "== /execute's other outcomes =="
for which in paused-for-review paused-awaiting-merges; do
    fixture "pause-$which" single-pr
    start auto && to_execute_run
    child execute "{\"outcome\":\"$which\",\"pr\":\"$URL\",\"waiting\":\"$URL:human\",\"resume\":\"/execute docs/plans/PLAN-$TOPIC.md --merge\"}"
    tick
    expect "/execute paused ($which)" done_stopped "outcome=$which" "pr=$URL" "resume=/execute docs/plans/PLAN-$TOPIC.md --merge"
done

fixture exec-error single-pr
start auto && to_execute_run
child execute '{"outcome":"error","step":"execute:ci"}'
tick
expect "/execute's error keeps its step" done_error outcome=error step=execute:ci

fixture exec-odd single-pr
start auto && to_execute_run
child execute '{"outcome":"refused"}'
tick
expect "a promoted outcome outside /execute's set" done_error outcome=error step=deliver:child-outcome

echo "== the request and the repository =="
fixture abandoned single-pr
start auto
k request abandon-request "$REQ" --rationale test >/dev/null
tick
expect "an abandoned request" done_error outcome=error step=deliver:request-abandoned

fixture private private
k init "deliver-$TOPIC" --template "$TPL" --var TOPIC="$TOPIC" --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" >/dev/null 2>&1
tick
expect "a private repository" done_refused "$(printf 'outcome=%s' refused)" reason=private-repo step=deliver:refused
if k request list --coordinator-of-record "deliver-$TOPIC" | jq -e '.requests | length == 0' >/dev/null; then
    pass "private: no request was opened"
else
    fail "private: no request was opened"
fi

echo "== the stale-run fence =="
fixture fence single-pr
start auto
OLD_REQ="$REQ"
k init "scope-$TOPIC" --template "$T/tpl/scope.md" --var TOPIC="$TOPIC" --var INTENT_FLAG=continue --koto-leg "$OLD_REQ:scope" >/dev/null 2>&1
# A new /deliver run on the same topic: a fresh session and a fresh request.
k session cleanup "deliver-$TOPIC" >/dev/null 2>&1
start auto
if [ "$REQ" != "$OLD_REQ" ]; then pass "fence: a new request"; else fail "fence: a new request"; fi
eq "fence: the old request is closed" '"closed"' "$(k request get "$OLD_REQ" | jq -c '.request_state')"
# The old run's child finishes late: its result is not the new run's.
k next "scope-$TOPIC" --no-cleanup --with-data "{\"finish\":\"go\",\"outcome\":\"scoped\",\"pr\":\"$FORGED\"}" >/dev/null 2>&1
tick
eq "fence: the new run is still waiting on its own leg" scope_run "$(state)"
eq "fence: the new request's scope leg is still open" '"open"' "$(k request get "$REQ" | jq -c '.legs.scope.disposition')"
eq "fence: the old leg took no result" 'null' "$(k request get "$OLD_REQ" | jq -c '.legs.scope.result')"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
