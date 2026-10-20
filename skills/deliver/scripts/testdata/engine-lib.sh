# engine-lib.sh -- the stand-in children, repository fixture and koto helpers
# deliver.md's engine suites share. Sourced by deliver-engine_test.sh and
# deliver-move-engine_test.sh after each sets T (its scratch directory), puts
# the gh stand-in first on PATH, and defines pass and fail; TPL,
# PLUGIN_ROOT_VAR and KOTO_LEGACY_ENV_ARG are read when a run starts. Not
# shipped behaviour.
#
# The children are throwaway templates named scope.md and execute.md (the file
# names the legs accept), each a single state whose evidence becomes its
# terminal result, so a case can make a child promote any payload it needs,
# /scope's `intent` included. They attach to a run's legs with `koto init
# --koto-leg`, exactly as /scope and /execute do.
#
# k runs koto in the repository R. A suite that runs koto some other way (as a
# simulated host) redefines k after sourcing this file; every helper below
# reaches koto only through it.
#
# Requires: bash 3.2+, git, jq, koto.

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
      next:
        type: string
      repos:
        type: string
      resume:
        type: string
      waiting:
        type: string
      intent:
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
          next: "\${evidence.next}"
          repos: "\${evidence.repos}"
          resume: "\${evidence.resume}"
          waiting: "\${evidence.waiting}"
          intent: "\${evidence.intent}"
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
      next: "\${context.next}"
      repos: "\${context.repos}"
      resume: "\${context.resume}"
      waiting: "\${context.waiting}"
      intent: "\${context.intent}"
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
# repository on docs/<topic>, pushed to a bare origin (`private` is a
# single-pr PLAN in a repository declaring Private). Sets R, TOPIC, URL,
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
# START_EXTRA, when set, adds its --var arguments to the init.
START_EXTRA=()
start() {
    # $KOTO_LEGACY_ENV_ARG (#483) is unquoted on purpose: when the knob is off it is
    # empty and must expand to no argument at all, not to an empty one.
    k init "deliver-$TOPIC" $KOTO_LEGACY_ENV_ARG --template "$TPL" --var TOPIC="$TOPIC" --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" \
        --var MODE="${1:-auto}" --var MERGE="${2:-true}" ${START_EXTRA[@]+"${START_EXTRA[@]}"} >/dev/null 2>"$T/init.err" \
        || { fail "$TOPIC: koto init deliver" "$(cat "$T/init.err")"; return 1; }
    # The run identity deliver-open.sh mints at the session's birth; the
    # probes only read it.
    printf '00112233445566778899aabbccddeeff' | k context add "deliver-$TOPIC" run_id >/dev/null 2>&1
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
    local leg="$1" ev="$2"
    shift 2
    child_attach "$leg" "$@" || return 1
    child_finish "$leg" "$ev"
}
# child_attach <scope|execute> [extra init args] -- the stand-in's koto init on
# this run's leg (REQ), left live at its one state. A refused init fails the
# case with koto's output.
child_attach() {
    local leg="$1" sess tplf
    shift
    if [ "$leg" = scope ]; then
        sess="scope-$TOPIC"; tplf="$T/tpl/scope.md"
        set -- --var TOPIC="$TOPIC" --var INTENT_FLAG=continue "$@"
    else
        sess="execute-$TOPIC"; tplf="$T/tpl/execute.md"
        set -- --var PLAN_SLUG="$TOPIC" "$@"
    fi
    k init "$sess" --template "$tplf" "$@" --koto-leg "$REQ:$leg" >/dev/null 2>"$T/child.err" \
        || { fail "$TOPIC: the $leg child attaches" "$(cat "$T/child.err")"; return 1; }
}
# child_finish <scope|execute> <evidence-json> -- drive the stand-in to its
# terminal, whose result its leg gets.
child_finish() {
    local sess="scope-$TOPIC"
    [ "$1" = scope ] || sess="execute-$TOPIC"
    k next "$sess" --no-cleanup --with-data "$(jq -c '. + {finish: "go"}' <<<"$2")" >/dev/null 2>&1
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
to_execute_run() { # a scope child reports scoped (intent continue, the owned PR), the re-check passes, auto mode
    child scope "{\"outcome\":\"scoped\",\"intent\":\"continue\",\"pr\":\"$URL\",\"plan_path\":\"docs/plans/PLAN-$TOPIC.md\",\"plan_execution_mode\":\"single-pr\"}"
    tick
}
