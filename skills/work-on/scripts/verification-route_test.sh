#!/usr/bin/env bash
# verification-route_test.sh -- the hosted-of-record route's script: when the
# route is open, the record it writes and checks, the body lines, the hosted
# read, and the settled, ready and mark-ready checks.
#
# Fixtures:
#   - repositories: throwaway git repositories whose main carries a
#     verification map with a `hosted` row (check-skill, each skills/*) and a
#     row without one (plain), stand-in scripts/skill-gate.sh and
#     scripts/check-skill.sh (one runs "$SCRIPT_DIR/fixture-helper.sh", the
#     other sources "$SCRIPT_DIR/lib/fixture-lib.sh"), a coordinate
#     check-skill.tsv, the coverage test's path and a workflow under
#     .github/. Branch `work` touches the six coordinate files shirabe#1934's
#     example diff touches.
#   - results: fixture result.json and run.json written at the path
#     run-verification.sh --locate names, under a scratch XDG_STATE_HOME.
#   - koto: a stand-in on PATH over $KOTO_STUB_STORE/<session>/<key>
#     (context add, get, exists, remove), `session list` printing
#     $KOTO_STUB_STORE/sessions.json; KOTO_STUB_FAIL=<subcommand> makes that
#     subcommand exit 7.
#   - gh: a stand-in on PATH over $FAKE_GH: `pr view` prints pr.json,
#     `pr edit --body-file` stores the body (edited-body) and sets it in
#     pr.json, `pr ready` clears isDraft, `api <path>` prints
#     api/<path with / ? & = as _>.json (missing: HTTP 404, exit 1; a .fail
#     twin: exit 1). Every call is logged to $FAKE_GH/calls.
#   - clock: SHIRABE_ROUTE_NOW on each call.
#
# Usage: verification-route_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROUTE="$SCRIPT_DIR/verification-route.sh"
START="$SCRIPT_DIR/run-verification.sh"
VERDICT="$SCRIPT_DIR/check-verification.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -x "$ROUTE" ] && [ -x "$START" ] && [ -x "$VERDICT" ] || { echo "the scripts under test are missing or not executable" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/verification-route-test.XXXXXX") || exit 2
WORKDIR=$(cd "$WORKDIR" && pwd -P) || exit 2
cleanup() { case "${WORKDIR:-}" in */verification-route-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
ktg_on_exit cleanup

export HOME="$WORKDIR/home"
export XDG_STATE_HOME="$WORKDIR/state"
mkdir -p "$HOME" "$WORKDIR/bin"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main

cat > "$WORKDIR/bin/koto" <<'EOF'
#!/bin/sh
echo "$*" >> "$KOTO_STUB_STORE/calls"
[ -n "${KOTO_STUB_FAIL-}" ] && [ "${2-}" = "$KOTO_STUB_FAIL" ] && exit 7
case "$1 ${2-}" in
    "context add")
        mkdir -p "$(dirname "$KOTO_STUB_STORE/$3/$4")"
        [ "${5-}" = --from-file ] && cp "$6" "$KOTO_STUB_STORE/$3/$4" || cat > "$KOTO_STUB_STORE/$3/$4" ;;
    "context exists") [ -f "$KOTO_STUB_STORE/$3/$4" ] ;;
    "context get") [ -f "$KOTO_STUB_STORE/$3/$4" ] || exit 1; cat "$KOTO_STUB_STORE/$3/$4" ;;
    "context remove") rm -f "$KOTO_STUB_STORE/$3/$4" ;;
    "session list") [ -f "$KOTO_STUB_STORE/sessions.json" ] || exit 9; cat "$KOTO_STUB_STORE/sessions.json" ;;
    *) exit 9 ;;
esac
EOF
cat > "$WORKDIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_GH/calls"
case "${1-} ${2-}" in
    "pr view")
        [ ! -e "$FAKE_GH/pr.fail" ] || { echo "gh: could not read the pull request" >&2; exit 1; }
        [ -f "$FAKE_GH/pr.json" ] || { echo "no pull requests found for branch" >&2; exit 1; }
        cat "$FAKE_GH/pr.json" ;;
    "pr edit")
        f=""; prev=""
        for a in "$@"; do [ "$prev" = --body-file ] && f=$a; prev=$a; done
        [ -n "$f" ] || { echo "gh pr edit: no --body-file" >&2; exit 1; }
        cp "$f" "$FAKE_GH/edited-body"
        jq --rawfile b "$f" '.body = $b' "$FAKE_GH/pr.json" > "$FAKE_GH/pr.tmp" && mv "$FAKE_GH/pr.tmp" "$FAKE_GH/pr.json" ;;
    "pr ready")
        jq '.isDraft = false' "$FAKE_GH/pr.json" > "$FAKE_GH/pr.tmp" && mv "$FAKE_GH/pr.tmp" "$FAKE_GH/pr.json" ;;
    api\ *)
        name=$(printf '%s' "$2" | tr '/?&=' '____')
        [ ! -e "$FAKE_GH/api/$name.fail" ] || { echo "gh: HTTP 502" >&2; exit 1; }
        [ -f "$FAKE_GH/api/$name.json" ] || { echo "gh: HTTP 404: Not Found ($2)" >&2; exit 1; }
        cat "$FAKE_GH/api/$name.json" ;;
    *) echo "gh stand-in: unexpected call: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$WORKDIR/bin/koto" "$WORKDIR/bin/gh"
export KOTO_STUB_STORE="$WORKDIR/kotostore"
export FAKE_GH="$WORKDIR/gh"
mkdir -p "$KOTO_STUB_STORE" "$FAKE_GH/api"
echo '[]' > "$KOTO_STUB_STORE/sessions.json"
export PATH="$WORKDIR/bin:$PATH"

# --- helpers -----------------------------------------------------------------------------

T0=1795000000
iso() { jq -rn --argjson t "$1" '$t | todate'; }
FIN=$(iso $((T0 - 600)))
export SHIRABE_ROUTE_NOW=$T0

OUT=""
RC=0
ERR="$WORKDIR/err"
# route <args>...: one run of the script; sets OUT and RC, stderr in $ERR.
route() {
    OUT=$("$ROUTE" "$@" 2>"$ERR")
    RC=$?
}
# expect <label> <exit> [<stderr fragment>]...
expect() {
    local label=$1 want=$2 frag ok=1
    shift 2
    [ "$RC" -eq "$want" ] || ok=0
    for frag in "$@"; do
        grep -qF -- "$frag" "$ERR" || ok=0
    done
    if [ "$ok" -eq 1 ]; then
        pass "$label"
    else
        fail "$label: exit $RC (want $want), stderr: $(head -c 1500 "$ERR")"
    fi
}

# root_session <s> / child_session <s>: how koto session list shows <s>.
root_session() {
    jq --arg s "$1" '[.[] | select(.id != $s)] + [{id: $s}]' "$KOTO_STUB_STORE/sessions.json" > "$WORKDIR/sl" \
        && mv "$WORKDIR/sl" "$KOTO_STUB_STORE/sessions.json"
}
child_session() {
    jq --arg s "$1" '[.[] | select(.id != $s)] + [{id: $s, parent_workflow: "parent"}]' "$KOTO_STUB_STORE/sessions.json" > "$WORKDIR/sl" \
        && mv "$WORKDIR/sl" "$KOTO_STUB_STORE/sessions.json"
}

HOSTED='[{"workflow": ".github/workflows/check-skill-gate.yml", "job": "skill-gate (ubuntu-latest)", "runs": "check-skill {skill}"}]'
WF=.github/workflows/check-skill-gate.yml
JOB='skill-gate (ubuntu-latest)'
COORD_FILES="skills/coordinate/scripts/state-holding.sh skills/coordinate/scripts/teardown-pass.sh skills/coordinate/koto-templates/coordinate.md skills/coordinate/references/teardown-agent.md skills/coordinate/scripts/state-holding_test.sh skills/coordinate/scripts/teardown-pass_test.sh"

# mkfix <name> <ok|none|bad>: a fixture repository (see the header), on
# branch `work` one commit past main touching the six coordinate files. The
# map is the hosted one (ok), absent (none) or not JSON (bad). Leaves the
# shell in it.
mkfix() {
    local dir="$WORKDIR/r-$1" p
    mkdir -p "$dir"
    cd "$dir" || exit 2
    git init -q -b main .
    mkdir -p scripts/lib skills/coordinate skills/plan skills/work-on/scripts .github/workflows .claude/shirabe-extensions
    cat > scripts/skill-gate.sh <<'EOF'
#!/bin/sh
SCRIPT_DIR=$(dirname "$0")
"$SCRIPT_DIR/fixture-helper.sh"
exec scripts/check-skill.sh "$@"
EOF
    cat > scripts/check-skill.sh <<'EOF'
#!/bin/sh
SCRIPT_DIR=$(dirname "$0")
. "$SCRIPT_DIR/lib/fixture-lib.sh"
EOF
    echo ': fixture library' > scripts/lib/fixture-lib.sh
    echo ': fixture helper' > scripts/fixture-helper.sh
    echo ': not read by the hosted job' > scripts/unrelated.sh
    printf 'suite\ta_test.sh\nsuite\tb_test.sh\n' > skills/coordinate/check-skill.tsv
    echo base > skills/plan/SKILL.md
    echo base > skills/work-on/scripts/verification-hosted-coverage_test.sh
    echo 'name: skill gate' > "$WF"
    echo base > top.txt
    for p in $COORD_FILES; do
        mkdir -p "$(dirname "$p")"
        echo base > "$p"
    done
    case "$2" in
        ok) jq -cn --argjson h "$HOSTED" '{schema: "shirabe-verification-map/v1",
                commands: {"check-skill": {run: ["scripts/check-skill.sh", "--changed"], each: "skills/*", timeout_secs: 3600, hosted: $h},
                           plain: {run: ["scripts/unrelated.sh"]}},
                entries: [{paths: ["skills/**"], commands: ["check-skill"]}], default: ["plain"]}' \
                > .claude/shirabe-extensions/verification-map.json ;;
        bad) echo '{"schema": "shirabe-verification-map/v1", "commands": {' > .claude/shirabe-extensions/verification-map.json ;;
    esac
    git add -A && git commit -q -m init
    git checkout -q -b work
    for p in $COORD_FILES; do echo "change" >> "$p"; done
    git add -A && git commit -q -m "coordinate change"
}

# branch <name> [<path>...]: a new branch from `work` that appends to each
# path and commits.
branch() {
    local n=$1 p
    shift
    git checkout -q -B "$n" work || exit 2
    for p in "$@"; do
        mkdir -p "$(dirname "$p")"
        echo "change $n" >> "$p"
    done
    [ $# -eq 0 ] || { git add -A && git commit -q -m "$n"; }
}

# cmd_rec <check> <outcome> [<json merged in>]: one command record.
cmd_rec() {
    local x=${3:-}
    [ -n "$x" ] || x='{}'
    jq -cn --arg c "$1" --arg o "$2" --argjson x "$x" '
        {id: ($c | split(":")[0]), check: $c,
         argv: (["scripts/check-skill.sh", "--changed"] + ($c | split(":")[1:])),
         exit_status: (if $o == "passed" then 0 elif $o == "timed-out-limit" then 143 else 1 end),
         duration_secs: 1, timed_out: ($o == "timed-out-limit"), runaway: false, not_started: false,
         pgid: 1, log: null, outcome: $o, suites: null} + $x'
}

# put_result <session> <commands json> [<status>] [<jq filter>]: the stored
# result for <session> at HEAD (and its run.json), the session listed as a
# root. The filter, when given, edits the result before it is written.
put_result() {
    local loc head mb res
    loc=$("$START" --locate --session "$1") || { fail "could not locate $1's result"; return 1; }
    head=$(sed -n 1p <<<"$loc"); mb=$(sed -n 2p <<<"$loc"); res=$(sed -n 3p <<<"$loc")
    mkdir -p "$(dirname "$res")"
    jq -cn --arg head "$head" --arg mb "$mb" --arg st "${3:-done}" --arg fin "$FIN" --argjson c "$2" \
        '{schema: "shirabe-verification-result/v1", head: $head, merge_base: $mb, status: $st, detail: "",
          finished_at: $fin, commands: $c}' | jq -c "${4:-.}" > "$res"
    jq -cn --argjson c "$2" '{invocations: [$c[] | {id, check}]}' > "$(dirname "$res")/run.json"
    root_session "$1"
}

# put_result_at <session> <head> <mb> <commands json>: a stored result at an
# explicit head (a child's), outside --locate.
put_result_at() {
    local res="$XDG_STATE_HOME/shirabe/verification/$1/$2/result.json"
    mkdir -p "$(dirname "$res")"
    jq -cn --arg head "$2" --arg mb "$3" --arg fin "$FIN" --argjson c "$4" \
        '{schema: "shirabe-verification-result/v1", head: $head, merge_base: $mb, status: "done", detail: "",
          finished_at: $fin, commands: $c}' > "$res"
}

key_of() { cat "$KOTO_STUB_STORE/$1/hosted_of_record" 2>/dev/null; }
set_key() { mkdir -p "$KOTO_STUB_STORE/$1" && printf '%s\n' "$2" > "$KOTO_STUB_STORE/$1/hosted_of_record"; }

# The result shirabe#1934's example diff produces: check-skill:coordinate
# stopped at its limit with no failed suite, 121 of the skill's suites
# selected (100 passed, 1 running, 20 not started).
SUITES121=$(jq -cn '{passed: [range(100) | "s/p\(.)_test.sh"], failed: [], running: ["s/r_test.sh"],
                     not_started: [range(20) | "s/n\(.)_test.sh"]}')
COORD_TO=$(cmd_rec check-skill:coordinate timed-out-limit "{\"suites\": $SUITES121}")
PLAN_TO=$(cmd_rec check-skill:plan timed-out-limit)
PLAN_OK=$(cmd_rec check-skill:plan passed)
REASON='the coordinate suites need more than an hour on this host'

# --- --open --------------------------------------------------------------------------------

echo "--- --open on shirabe#1934's example diff"
mkfix main ok
MAIN_REPO=$PWD
[ "$(jq '[.passed, .failed, .running, .not_started] | map(length) | add' <<<"$SUITES121")" = 121 ] \
    && pass "the fixture's suite lists add up to 121" || fail "the fixture's suite lists don't add up to 121"
[ "$(git diff --name-only main work | LC_ALL=C sort | tr '\n' ' ')" = "$(printf '%s\n' $COORD_FILES | LC_ALL=C sort | tr '\n' ' ')" ] \
    && pass "the fixture diff touches exactly the six coordinate files" || fail "the fixture diff: $(git diff --name-only main work)"
put_result s-open "[$COORD_TO]"
route --open --session s-open
expect "--open: one timed-out check whose row declares hosted jobs, a diff under skills/coordinate/ only: open (0)" 0
"$VERDICT" --verdict --session s-open >"$WORKDIR/verdict.out" 2>"$ERR"
RC=$?
expect "the verdict on the same result is 5, the hold" 5 "hosted_of_record"
route --record --session s-open --reason "$REASON"
expect "--record --reason on it: 0" 0
route --check-record --session s-open
expect "--check-record on the key --record wrote: 0" 0

echo "--- --open: each closing cause"
# closed <label> <session> <fragment>...: --open exits 1 naming each fragment.
closed() {
    local label=$1 s=$2
    shift 2
    route --open --session "$s"
    expect "--open: $label: closed (1), naming the cause" 1 "$@"
}
put_result s-norow "[$(cmd_rec plain timed-out-limit)]"
closed "a timed-out check whose row declares no hosted jobs" s-norow "row plain declares no hosted jobs"
put_result s-failed "[$COORD_TO, $(cmd_rec check-skill:plan failed)]"
closed "a failed check beside the timed-out one" s-failed "check check-skill:plan failed"
put_result s-nostart "[$COORD_TO, $(cmd_rec plain failed '{"not_started": true, "exit_status": null}')]"
closed "a command that did not start" s-nostart "command plain did not start"
put_result s-runaway "[$COORD_TO, $(cmd_rec plain failed '{"runaway": true}')]"
closed "a runaway command" s-runaway "grew past its max_procs"
put_result s-superr "[$COORD_TO]" supervisor-error
closed "a supervisor-error result" s-superr "status is supervisor-error"
put_result s-budget "[$COORD_TO]" timed-out '.detail = "the run passed its total budget"'
jq -c '.invocations += [{id: "plain", check: "plain"}]' "$(dirname "$("$START" --locate --session s-budget | sed -n 3p)")/run.json" > "$WORKDIR/rj" \
    && mv "$WORKDIR/rj" "$(dirname "$("$START" --locate --session s-budget | sed -n 3p)")/run.json"
closed "a budget stop that left a command unstarted" s-budget "1 later command(s) were not started"
put_result s-old "[$COORD_TO]" done 'del(.finished_at)'
closed "a result that predates the route" s-old "predates the route"
put_result s-nothing "[$PLAN_OK]"
closed "no check timed out" s-nothing "no check timed out"
put_result s-dirty "[$COORD_TO]"
echo dirty >> top.txt
closed "a dirty tree" s-dirty "tracked files have uncommitted changes"
git checkout -q -- top.txt
put_result s-two "[$COORD_TO, $(cmd_rec check-skill:plan failed)]"
echo dirty >> top.txt
closed "two causes at once, both named" s-two "check check-skill:plan failed" "tracked files have uncommitted changes"
git checkout -q -- top.txt

n=0
for p in .github/x "$WF" scripts/skill-gate.sh scripts/check-skill.sh scripts/lib/fixture-lib.sh scripts/fixture-helper.sh \
        .claude/shirabe-extensions/verification-map.json skills/work-on/scripts/verification-hosted-coverage_test.sh; do
    n=$((n + 1))
    branch "close$n" "$p"
    put_result "s-close$n" "[$COORD_TO]"
    closed "a diff touching $p" "s-close$n" "touches $p, which decides what the hosted job runs"
done

branch tsvadd
printf 'suite\tc_test.sh\n' >> skills/coordinate/check-skill.tsv
git commit -q -am "add a row"
put_result s-tsvadd "[$COORD_TO]"
route --open --session s-tsvadd
expect "--open: a check-skill.tsv that only gains a row stays open (0)" 0
branch tsvedit
sed 's/a_test.sh/z_test.sh/' skills/coordinate/check-skill.tsv > "$WORKDIR/tsv" && cat "$WORKDIR/tsv" > skills/coordinate/check-skill.tsv
git commit -q -am "edit a row"
put_result s-tsvedit "[$COORD_TO]"
closed "a check-skill.tsv row edited" s-tsvedit "edits or deletes rows of skills/coordinate/check-skill.tsv"
branch tsvdel
grep -v b_test.sh skills/coordinate/check-skill.tsv > "$WORKDIR/tsv"; cat "$WORKDIR/tsv" > skills/coordinate/check-skill.tsv
git commit -q -am "delete a row"
put_result s-tsvdel "[$COORD_TO]"
closed "a check-skill.tsv row deleted" s-tsvdel "edits or deletes rows of skills/coordinate/check-skill.tsv"
branch tsvgone
git rm -q skills/coordinate/check-skill.tsv && git commit -q -m "drop the tsv"
put_result s-tsvgone "[$COORD_TO]"
closed "a check-skill.tsv removed" s-tsvgone "changes skills/coordinate/check-skill.tsv (status D)"

branch newlib
echo ': a new helper' > scripts/lib/new.sh
git add scripts/lib/new.sh && git commit -q -m "add a library"
echo '. "$SCRIPT_DIR/lib/new.sh"' >> scripts/check-skill.sh
echo ': edited' >> scripts/lib/new.sh
git commit -q -am "source and edit it"
put_result s-newlib "[$COORD_TO]"
closed "a diff that adds a sourced library and edits it" s-newlib "touches scripts/check-skill.sh"
branch other scripts/unrelated.sh
put_result s-other "[$COORD_TO]"
route --open --session s-other
expect "--open: a script the hosted job doesn't run, changed, stays open (0)" 0

git checkout -q work
mkfix nomap none
put_result s-nomap "[$COORD_TO]"
closed "no map at the merge-base" s-nomap "missing or bad map" "no .claude/shirabe-extensions/verification-map.json at the merge-base"
mkfix badmap bad
put_result s-badmap "[$COORD_TO]"
closed "a bad map at the merge-base" s-badmap "missing or bad map"
cd "$MAIN_REPO" || exit 2

echo "--- --open: a child of /execute takes the route"
put_result s-shared "[$COORD_TO]"
route --open --session s-shared --shared-branch docs/x
expect "--open --shared-branch docs/x, a single-pr shared-branch child: open (0)" 0
put_result s-child "[$COORD_TO]"
child_session s-child
route --open --session s-child
expect "--open for a child session /execute started: open (0)" 0
route --open --session s-open --shared-branch ""
expect "--open with an empty --shared-branch, a root session: open (0)" 0
# The one /execute refusal is gone: nothing in the script consults
# SHARED_BRANCH or session-role.sh to close the route.
SR=$(grep -v '^[[:space:]]*#' "$ROUTE" | grep -c 'session-role.sh')
CALLS=$(grep -c 'vr_refuse_execute_child' "$ROUTE")
[ "$SR" -eq 0 ] && [ "$CALLS" -eq 0 ] \
    && pass "the /execute refusal is gone: no session-role.sh read and no vr_refuse_execute_child" \
    || fail "session-role.sh named $SR time(s); vr_refuse_execute_child named $CALLS time(s)"
route --record --session s-shared --reason "$REASON"
SHARED_KEY=$(key_of s-shared)
route --record --session s-open --reason "$REASON"
[ "$(jq -cS 'del(.taken_at)' <<<"$SHARED_KEY")" = "$(key_of s-open | jq -cS 'del(.taken_at)')" ] \
    && [ "$(jq -r 'keys | join(",")' <<<"$SHARED_KEY")" = "checks,head,reason,taken_at" ] \
    && pass "--record for a shared-branch child writes the same fields, and per check the same jobs, as a root run's" \
    || fail "--record parity: child $SHARED_KEY, root $(key_of s-open)"

# --- --record and --check-record ---------------------------------------------------------

echo "--- --record"
put_result s-rec "[$COORD_TO, $PLAN_OK]"
route --record --session s-rec --reason "$REASON"
expect "--record: 0" 0
HEAD_SHA=$(git rev-parse HEAD)
WANT=$(jq -cn --arg h "$HEAD_SHA" --arg t "$(iso $T0)" --arg r "$REASON" --arg wf "$WF" --arg job "$JOB" \
    '{head: $h, taken_at: $t, reason: $r,
      checks: [{id: "check-skill:coordinate", jobs: [{workflow: $wf, job: $job, run_id: null, conclusion: null, attempt: null}]}]}')
[ "$(key_of s-rec | jq -cS .)" = "$(jq -cS . <<<"$WANT")" ] \
    && pass "--record: head, taken_at, reason, and only the timed-out check, with the merge-base map's jobs and null run fields" \
    || fail "--record wrote $(key_of s-rec)"
put_result s-rec2 "[$COORD_TO, $PLAN_TO]"
route --record --session s-rec2 --reason "$REASON"
[ "$RC" -eq 0 ] && [ "$(key_of s-rec2 | jq -c '[.checks[].id]')" = '["check-skill:coordinate","check-skill:plan"]' ] \
    && pass "--record: two timed-out checks are both listed" || fail "--record with two timed-out checks: rc $RC, $(key_of s-rec2)"

MARKER="$WORKDIR/marker"
EVIL="\$(touch $MARKER); x"
route --record --session s-rec --reason "$EVIL"
[ "$RC" -eq 0 ] && [ ! -e "$MARKER" ] && [ "$(key_of s-rec | jq -r .reason)" = "$EVIL" ] \
    && pass "--record: a reason with \$(touch ...) and ; runs nothing and is stored as text" \
    || fail "--record with a shell reason: rc $RC, marker $([ -e "$MARKER" ] && echo made || echo absent), key $(key_of s-rec)"
route --record --session s-rec --reason "$(printf 'a\tb`c\001d `e`\n')"
[ "$(key_of s-rec | jq -r .reason)" = "a bc d e" ] \
    && pass "--record: control characters become spaces and backticks go" \
    || fail "--record: the cleaned reason is [$(key_of s-rec | jq -r .reason)]"
LONG=$(printf 'x%.0s' $(seq 1 400))
route --record --session s-rec --reason "$LONG"
[ "$(key_of s-rec | jq -r '.reason | length')" = 300 ] && pass "--record: a 400-character reason is capped at 300" \
    || fail "--record: the long reason is $(key_of s-rec | jq -r '.reason | length') characters"
route --record --session s-rec --reason "   "
expect "--record: a reason of spaces alone is refused (1)" 1 "needs a reason"
printf 'from the hold' > "$KOTO_STUB_STORE/s-rec/hosted_route_reason"
route --record --session s-rec
[ "$RC" -eq 0 ] && [ "$(key_of s-rec | jq -r .reason)" = "from the hold" ] \
    && pass "--record: without --reason, the reason is hosted_route_reason from context" \
    || fail "--record from context: rc $RC, $(key_of s-rec)"
rm -f "$KOTO_STUB_STORE/s-failed/hosted_of_record"
route --record --session s-failed --reason "$REASON"
[ "$RC" -eq 1 ] && [ -z "$(key_of s-failed)" ] && grep -qF "check check-skill:plan failed" "$ERR" \
    && pass "--record: a closed route records nothing (1), naming the cause" \
    || fail "--record on a closed route: rc $RC, key [$(key_of s-failed)]"
KOTO_STUB_FAIL=add route --record --session s-rec --reason "$REASON"
expect "--record: koto failing to write the key is 2" 2

echo "--- --check-record"
route --record --session s-rec --reason "$REASON"
GOOD=$(key_of s-rec)
route --check-record --session s-rec
expect "--check-record: the key --record wrote is valid (0)" 0
# bad_key <label> <jq edit> [<fragment>]: the edited key is refused (1).
bad_key() {
    set_key s-rec "$(jq -c "$2" <<<"$GOOD")"
    route --check-record --session s-rec
    if [ $# -ge 3 ]; then expect "--check-record: $1 (1)" 1 "$3"; else expect "--check-record: $1 (1)" 1; fi
}
bad_key "an empty reason" '.reason = ""' "reason is empty"
bad_key "a reason --record would have cleaned" '.reason = "a`b"' "strips"
bad_key "a head other than the current one" '.head = "0000000000000000000000000000000000000000"' "not $HEAD_SHA"
bad_key "a check added" '.checks += [{id: "check-skill:plan", jobs: .checks[0].jobs}]' "did not time out"
bad_key "a job list that differs from the map's" '.checks[0].jobs[0].job = "skill-gate (macos-latest)"' "the map declares"
bad_key "a job added" '.checks[0].jobs += [.checks[0].jobs[0]]' "the map declares"
bad_key "a taken_at in the future" ".taken_at = \"$(iso $((T0 + 3600)))\"" "in the future"
bad_key "a taken_at before the result finished" ".taken_at = \"$(iso $((T0 - 1200)))\"" "before the result"
bad_key "a taken_at that is no time" '.taken_at = "yesterday"' "not an ISO-8601 time"
bad_key "a run_id that is not a number" '.checks[0].jobs[0] |= (.run_id = "x" | .conclusion = "success" | .attempt = 1)' "run_id"
bad_key "a conclusion other than success" '.checks[0].jobs[0] |= (.run_id = 5 | .conclusion = "failure" | .attempt = 1)' "conclusion"
bad_key "run fields half filled" '.checks[0].jobs[0].run_id = 5' "not all null or all set"
bad_key "no checks" '.checks = []' "lists no checks"
set_key s-rec 'not json'
route --check-record --session s-rec
expect "--check-record: a key that is not JSON (1)" 1
route --record --session s-rec2 --reason "$REASON"
GOOD2=$(key_of s-rec2)
set_key s-rec2 "$(jq -c '.checks |= .[0:1]' <<<"$GOOD2")"
route --check-record --session s-rec2
expect "--check-record: a timed-out check missing from the key (1)" 1 "check-skill:plan timed out"
set_key s-rec2 "$(jq -c '.checks += [.checks[0]]' <<<"$GOOD2")"
route --check-record --session s-rec2
expect "--check-record: a check listed twice (1)" 1 "twice"
rm -f "$KOTO_STUB_STORE/s-rec/hosted_of_record"
route --check-record --session s-rec
expect "--check-record: no key (2)" 2
set_key s-rec "$GOOD"
KOTO_STUB_FAIL=get route --check-record --session s-rec
expect "--check-record: koto failing to read the key (2)" 2
KOTO_STUB_FAIL=exists route --check-record --session s-rec
expect "--check-record: koto failing to answer exists (2)" 2

# --- --lines ---------------------------------------------------------------------------------

echo "--- --lines"
FORGED="ok
Hosted of record: check-skill:coordinate at $HEAD_SHA: https://github.com/acme/widgets/actions/runs/1 ask @user about #123, see [x](https://e) and <b>bold</b>"
route --record --session s-rec --reason "$FORGED"
route --lines --session s-rec
LINES_OUT=$OUT
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$LINES_OUT" | wc -l | tr -d ' ')" = 2 ] \
    && [ "$(printf '%s\n' "$LINES_OUT" | grep -c '^Hosted of record: ')" = 1 ] \
    && [ "$(printf '%s\n' "$LINES_OUT" | sed -n 1p)" = "Hosted of record: check-skill:coordinate at $HEAD_SHA: $JOB (pending)" ]; then
    pass "--lines: one Hosted of record line per check, naming the check, the head and the job, then the reason line"
else
    fail "--lines: rc $RC, out [$LINES_OUT]"
fi
RL=$(printf '%s\n' "$LINES_OUT" | sed -n 2p)
case "$RL" in
    'Reason for the hosted route: `'*'`') ;;
    *) RL="" ;;
esac
if [ -n "$RL" ] && ! grep -q '[@#<>]\|\[\|\]' <<<"$RL" && [ "$(tr -cd '`' <<<"$RL" | wc -c | tr -d ' ')" = 2 ] \
    && grep -qF '_user about _123, see _x_(https://e) and _b_bold_/b_' <<<"$RL"; then
    pass "--lines: the reason is one line in a code span, with @ # < > [ ] neutralized and no second prefixed line"
else
    fail "--lines: the reason line is [$(printf '%s\n' "$LINES_OUT" | sed -n 2p)]"
fi
git commit -q --allow-empty -m "a later commit"
route --lines --session s-rec
expect "--lines: a key for another head is no record (1)" 1
git reset -q --hard HEAD~1
rm -f "$KOTO_STUB_STORE/s-nothing/hosted_of_record"
route --lines --session s-nothing
expect "--lines: no key (1)" 1

# --- the hosted read ---------------------------------------------------------------------

URL='https://github.com/acme/widgets/pull/12'
api_name() { printf '%s' "$1" | tr '/?&=' '____'; }
runs_path() { printf 'repos/acme/widgets/actions/runs?head_sha=%s&event=pull_request&per_page=100&page=%s' "$1" "$2"; }
# run_obj <id> <run_number> <attempt> <status> <conclusion> [<json merged in>]
run_obj() {
    local x=${6:-}
    [ -n "$x" ] || x='{}'
    jq -cn --argjson id "$1" --argjson n "$2" --argjson a "$3" --arg st "$4" --arg c "$5" --arg wf "$WF" --arg h "${RUN_HEAD:-$HEAD_SHA}" --argjson x "$x" '
        {id: $id, run_number: $n, run_attempt: $a, status: $st, conclusion: (if $c == "" then null else $c end),
         created_at: "2026-11-20T00:00:00Z", path: ($wf + "@refs/pull/12/merge"), event: "pull_request",
         head_sha: $h, repository: {full_name: "acme/widgets"}, head_repository: {full_name: "acme/widgets"},
         pull_requests: [{number: 12}]} + $x'
}
# runs_page <head> <page> <runs json array>
runs_page() {
    jq -cn --argjson r "$3" '{total_count: ($r | length), workflow_runs: $r}' > "$FAKE_GH/api/$(api_name "$(runs_path "$1" "$2")").json"
}
# jobs_at <run> <attempt> <jobs json array>
jobs_at() {
    jq -cn --argjson j "$3" '{total_count: ($j | length), jobs: $j}' \
        > "$FAKE_GH/api/$(api_name "repos/acme/widgets/actions/runs/$1/attempts/$2/jobs?per_page=100&page=1").json"
}
job_obj() { jq -cn --arg n "${3:-$JOB}" --arg st "$1" --arg c "$2" '{name: $n, status: $st, conclusion: (if $c == "" then null else $c end)}'; }
# run_file <run json>: what gh api repos/<repo>/actions/runs/<id> answers.
run_file() { printf '%s\n' "$1" > "$FAKE_GH/api/$(api_name "repos/acme/widgets/actions/runs/$(jq -r .id <<<"$1")").json"; }

# gh_reset <session> [<pr head>]: no api answers, a draft pull request at
# <pr head> (default HEAD) whose body carries --lines' output for <session>,
# and the session's record restored to RECORD. The head branch's name points
# at another repository on purpose: nothing may read it.
gh_reset() {
    local body
    rm -rf "$FAKE_GH"
    mkdir -p "$FAKE_GH/api"
    set_key "$1" "$RECORD"
    body="Summary of the change.

$("$ROUTE" --lines --session "$1" 2>/dev/null)

---

Fixes #12"
    jq -cn --arg url "$URL" --arg h "${2:-$HEAD_SHA}" --arg b "$body" \
        '{number: 12, url: $url, headRefOid: $h, headRefName: "other-owner/other-repo/pull/99", isDraft: true,
          isCrossRepository: false, body: $b}' > "$FAKE_GH/pr.json"
}
read_at() { # <minutes after taken_at> [<session>]
    SHIRABE_ROUTE_NOW=$((T0 + $1 * 60)) route --read --session "${2:-s-read}"
}

echo "--- --read"
put_result s-read "[$COORD_TO]"
route --record --session s-read --reason "$REASON"
RECORD=$(key_of s-read)

gh_reset s-read
runs_page "$HEAD_SHA" 1 "[$(run_obj 501 7 1 completed success)]"
jobs_at 501 1 "[$(job_obj completed success)]"
read_at 30
expect "--read: the declared job's latest attempt concluded success (0)" 0
[ "$(key_of s-read | jq -c '.checks[0].jobs[0] | [.run_id, .conclusion, .attempt]')" = '[501,"success",1]' ] \
    && pass "--read: fills run_id, conclusion and attempt" || fail "--read filled $(key_of s-read)"
if grep -qxF "Hosted of record: check-skill:coordinate at $HEAD_SHA: $JOB https://github.com/acme/widgets/actions/runs/501" "$FAKE_GH/edited-body" 2>/dev/null \
    && grep -q '^pr edit https://github.com/acme/widgets/pull/12 --body-file ' "$FAKE_GH/calls" \
    && grep -qF 'Summary of the change.' "$FAKE_GH/edited-body" && grep -qF 'Fixes #12' "$FAKE_GH/edited-body"; then
    pass "--read: rewrites the line with the run URL from the numeric id, by gh pr edit --body-file, keeping the rest"
else
    fail "--read: the edited body: $(cat "$FAKE_GH/edited-body" 2>&1); calls: $(cat "$FAKE_GH/calls")"
fi
grep -q '^api repos/acme/widgets/actions/runs?head_sha=' "$FAKE_GH/calls" \
    && ! grep -q 'other-owner\|other-repo' "$FAKE_GH/calls" \
    && pass "--read: the repository and number come from the pull request object, not the branch" \
    || fail "--read: the api calls: $(cat "$FAKE_GH/calls")"
run_file "$(run_obj 501 7 1 completed success)"
route --ready --session s-read
expect "--ready: 1 while the pull request is a draft" 1 "still a draft"
cp "$FAKE_GH/pr.json" "$WORKDIR/pr.ready.json"
route --settled --session s-read
expect "--settled: 0 for the record --read filled" 0
jq '.headRefOid = "1111111111111111111111111111111111111111"' "$WORKDIR/pr.ready.json" > "$FAKE_GH/pr.json"
route --mark-ready --session s-read
expect "--mark-ready: refuses when the pull request's head moved (1)" 1
grep -q '^pr ready' "$FAKE_GH/calls" && fail "--mark-ready: called gh pr ready on a moved head" \
    || pass "--mark-ready: no gh pr ready on a moved head"
cp "$WORKDIR/pr.ready.json" "$FAKE_GH/pr.json"
route --mark-ready --session s-read
[ "$RC" -eq 0 ] && grep -q "^pr ready $URL" "$FAKE_GH/calls" && pass "--mark-ready: runs gh pr ready once the record is settled" \
    || fail "--mark-ready: rc $RC, calls $(cat "$FAKE_GH/calls"); $(cat "$ERR")"
route --ready --session s-read
expect "--ready: 0 once out of draft, at the record's head, with every line linking its run" 0
jq '.headRefOid = "1111111111111111111111111111111111111111"' "$FAKE_GH/pr.json" > "$WORKDIR/p" && cp "$WORKDIR/p" "$FAKE_GH/pr.json"
route --ready --session s-read
expect "--ready: 1 when the pull request's head moved" 1
jq --arg h "$HEAD_SHA" '.headRefOid = $h | .body |= sub("/actions/runs/501"; "")' "$FAKE_GH/pr.json" > "$WORKDIR/p" && cp "$WORKDIR/p" "$FAKE_GH/pr.json"
route --ready --session s-read
expect "--ready: 1 when a line lacks its run link" 1 "does not link"

# read_case <label> <exit> [<fragment>...]: a read at 30 minutes over the
# fixtures already set.
read_case() {
    local label=$1 want=$2
    shift 2
    read_at 30
    expect "--read: $label ($want)" "$want" "$@"
}
gh_reset s-read
runs_page "$HEAD_SHA" 1 "[$(run_obj 502 8 2 completed success)]"
jobs_at 502 1 "[$(job_obj completed failure)]"
jobs_at 502 2 "[$(job_obj completed success)]"
read_case "a first attempt that failed and a second that succeeded" 0
[ "$(key_of s-read | jq -c '.checks[0].jobs[0].attempt')" = 2 ] && pass "--read: records the attempt it took (2)" \
    || fail "--read: recorded attempt $(key_of s-read | jq -c '.checks[0].jobs[0].attempt')"
gh_reset s-read
runs_page "$HEAD_SHA" 1 "[$(run_obj 503 8 2 completed failure)]"
jobs_at 503 1 "[$(job_obj completed success)]"
jobs_at 503 2 "[$(job_obj completed failure)]"
read_case "a first attempt that succeeded and a second that failed" 1 "concluded failure"
for c in cancelled failure skipped timed_out neutral action_required stale; do
    gh_reset s-read
    runs_page "$HEAD_SHA" 1 "[$(run_obj 504 9 1 completed "$c")]"
    jobs_at 504 1 "[$(job_obj completed "$c")]"
    read_case "a latest attempt concluded $c, naming the job and the commit" 1 \
        "check check-skill:coordinate, job $JOB, commit $HEAD_SHA" "concluded $c"
done
# The skill gate's job of record waits on its suite slices (needs:), so a
# failed slice leaves it skipped while the other slices pass.
gh_reset s-read
runs_page "$HEAD_SHA" 1 "[$(run_obj 508 9 1 completed failure)]"
jobs_at 508 1 "[$(job_obj completed success 'skill-gate-suites (ubuntu-latest, 1)'), $(job_obj completed failure 'skill-gate-suites (ubuntu-latest, 2)'), $(job_obj completed success 'skill-gate-suites (ubuntu-latest, 3)'), $(job_obj completed success 'skill-gate-suites (ubuntu-latest, 4)'), $(job_obj completed skipped)]"
read_case "a skill-gate skipped after a failed suite slice is not passed" 1 \
    "check check-skill:coordinate, job $JOB, commit $HEAD_SHA" "concluded skipped"
gh_reset s-read
runs_page "$HEAD_SHA" 1 "[$(run_obj 505 9 1 completed success)]"
touch "$FAKE_GH/api/$(api_name "$(runs_path "$HEAD_SHA" 1)").fail"
read_case "an unreadable runs page" 1 "unreadable"
gh_reset s-read
printf 'not json\n' > "$FAKE_GH/api/$(api_name "$(runs_path "$HEAD_SHA" 1)").json"
read_case "a runs page that is not JSON" 1 "unreadable"
gh_reset s-read
runs_page "$HEAD_SHA" 1 "[$(run_obj 506 9 1 completed success)]"
jobs_at 506 1 "[$(job_obj completed success 'skill-gate (macos-latest)')]"
read_case "a completed run with no job of the declared name" 1 "no job of that name"
gh_reset s-read
runs_page "$HEAD_SHA" 1 "[$(run_obj 507 9 1 completed success)]"
jobs_at 507 1 "[$(job_obj completed success), $(job_obj completed success)]"
read_case "two jobs of the declared name" 1 "has 2 jobs of that name"
gh_reset s-read 2222222222222222222222222222222222222222
read_case "a pull request whose head is not the record's" 1 "a new commit voids the route"
gh_reset s-read
jq '.isCrossRepository = true' "$FAKE_GH/pr.json" > "$WORKDIR/p" && cp "$WORKDIR/p" "$FAKE_GH/pr.json"
read_case "a pull request from another repository" 1 "another repository"
gh_reset s-read
touch "$FAKE_GH/pr.fail"
read_case "a pull request that can't be read" 1

echo "--- --read: pending, and the 120 minutes"
gh_reset s-read
runs_page "$HEAD_SHA" 1 "[$(run_obj 510 9 1 in_progress '')]"
jobs_at 510 1 "[$(job_obj in_progress '')]"
read_at 119
expect "--read: a job in progress at 119 minutes waits (75)" 75
gh_reset s-read
runs_page "$HEAD_SHA" 1 "[$(run_obj 511 9 1 queued '')]"
jobs_at 511 1 "[]"
read_at 119
expect "--read: a queued run with no job yet at 119 minutes waits (75)" 75
gh_reset s-read
runs_page "$HEAD_SHA" 1 "[]"
read_at 119
expect "--read: no run yet at 119 minutes waits (75)" 75
rm -f "$KOTO_STUB_STORE/s-read/failure_reason"
read_at 121
expect "--read: still no run past 120 minutes ends the wait (3)" 3
grep -qF "check-skill:coordinate/$JOB at $HEAD_SHA" "$KOTO_STUB_STORE/s-read/failure_reason" 2>/dev/null \
    && grep -qF "120 minutes" "$KOTO_STUB_STORE/s-read/failure_reason" \
    && pass "--read: the failure_reason it wrote names the pending job and the commit" \
    || fail "--read: failure_reason is [$(cat "$KOTO_STUB_STORE/s-read/failure_reason" 2>&1)]"
gh_reset s-read
runs_page "$HEAD_SHA" 1 "[$(run_obj 512 9 1 completed failure)]"
jobs_at 512 1 "[$(job_obj completed failure)]"
read_at 121
expect "--read: a refusal past 120 minutes is still a refusal (1)" 1

echo "--- --read: runs that don't count"
gh_reset s-read
DECOYS="[$(run_obj 520 20 1 completed success '{"path": ".github/workflows/other.yml@refs/pull/12/merge"}'),
         $(run_obj 521 21 1 completed success '{"event": "push"}'),
         $(run_obj 522 22 1 completed success '{"pull_requests": [{"number": 13}]}'),
         $(run_obj 523 23 1 completed success '{"head_repository": {"full_name": "fork/widgets"}}'),
         $(RUN_HEAD=3333333333333333333333333333333333333333 run_obj 524 24 1 completed success)]"
runs_page "$HEAD_SHA" 1 "$DECOYS"
for r in 520 521 522 523 524; do jobs_at "$r" 1 "[$(job_obj completed success)]"; done
read_at 30
expect "--read: runs of another workflow, event, pull request, head repository or commit are ignored (75, not 0)" 75
gh_reset s-read
PAGE1=$(jq -cn --arg wf "$WF" --argjson base "$(run_obj 600 5 1 completed failure '{"path": ".github/workflows/other.yml"}')" \
    '[range(99) | $base + {id: (1000 + .)}]')
PAGE1=$(jq -c --argjson old "$(run_obj 601 5 1 completed failure)" '. + [$old]' <<<"$PAGE1")
runs_page "$HEAD_SHA" 1 "$PAGE1"
runs_page "$HEAD_SHA" 2 "[$(run_obj 602 9 1 completed success)]"
jobs_at 601 1 "[$(job_obj completed failure)]"
jobs_at 602 1 "[$(job_obj completed success)]"
read_at 30
[ "$RC" -eq 0 ] && [ "$(key_of s-read | jq -c '.checks[0].jobs[0].run_id')" = 602 ] \
    && pass "--read: follows pagination to the newest matching run on page 2" \
    || fail "--read over two pages: rc $RC, $(key_of s-read); $(cat "$ERR")"
gh_reset s-read
runs_page "$HEAD_SHA" 1 "$PAGE1"
SHIRABE_ROUTE_MAX_PAGES=1 read_at 30
expect "--read: full pages past SHIRABE_ROUTE_MAX_PAGES are unreadable (1)" 1 "full pages"

echo "--- --read: two refusing jobs"
put_result s-read2 "[$COORD_TO, $PLAN_TO]"
route --record --session s-read2 --reason "$REASON"
RECORD=$(key_of s-read2)
gh_reset s-read2
runs_page "$HEAD_SHA" 1 "[$(run_obj 530 9 1 completed failure)]"
jobs_at 530 1 "[$(job_obj completed failure)]"
read_at 30 s-read2
expect "--read: two refusing jobs are both named" 1 "check check-skill:coordinate, job $JOB" "check check-skill:plan, job $JOB"

# --- --settled and the ready gate over hand-filled keys ------------------------------------

echo "--- --settled"
RECORD=$(key_of s-read)
rm -f "$KOTO_STUB_STORE/s-nothing/hosted_of_record"
route --settled --session s-nothing
expect "--settled: no key (0)" 0
put_result s-hand "[$COORD_TO]"
route --record --session s-hand --reason "$REASON"
UNREAD=$(key_of s-hand)
RECORD=$UNREAD
gh_reset s-hand
jq '.isDraft = false' "$FAKE_GH/pr.json" > "$WORKDIR/p" && cp "$WORKDIR/p" "$FAKE_GH/pr.json"
route --settled --session s-hand
expect "--settled: an unread record of a non-draft pull request (1)" 1 "have not been read"
HAND=$(jq -c '.checks[0].jobs[0] |= (.run_id = 700 | .conclusion = "success" | .attempt = 1)' <<<"$UNREAD")
# hand_case <label> <run json> <jobs json> [<attempt>]: a key filled by hand
# with run 700 fails --settled and --ready.
hand_case() {
    RECORD=$HAND
    gh_reset s-hand
    jq '.isDraft = false' "$FAKE_GH/pr.json" > "$WORKDIR/p" && cp "$WORKDIR/p" "$FAKE_GH/pr.json"
    run_file "$2"
    jobs_at 700 "${4:-1}" "$3"
    route --settled --session s-hand
    expect "--settled: a hand-filled key whose run $1 (1)" 1 "not settled"
    route --ready --session s-hand
    expect "--ready: a hand-filled key whose run $1 (1)" 1
}
hand_case "names another workflow" "$(run_obj 700 9 1 completed success '{"path": ".github/workflows/other.yml"}')" "[$(job_obj completed success)]"
hand_case "has another job" "$(run_obj 700 9 1 completed success)" "[$(job_obj completed success 'lint (ubuntu-latest)')]"
hand_case "is at another head" "$(RUN_HEAD=3333333333333333333333333333333333333333 run_obj 700 9 1 completed success)" "[$(job_obj completed success)]"
hand_case "concluded failure" "$(run_obj 700 9 1 completed failure)" "[$(job_obj completed failure)]"
hand_case "has a later attempt than the recorded one" "$(run_obj 700 9 2 completed success)" "[$(job_obj completed success)]"
RECORD=$HAND
gh_reset s-hand
route --settled --session s-hand
expect "--settled: a hand-filled run id the API doesn't know (1)" 1 "could not be read"

# --- a new commit voids the route; a stale key is replaced ----------------------------------

echo "--- a new commit"
RECORD=$(jq -c '.checks[0].jobs[0] |= (.run_id = 501 | .conclusion = "success" | .attempt = 1)' <<<"$(key_of s-read)")
OLD_HEAD=$HEAD_SHA
gh_reset s-read
run_file "$(run_obj 501 7 1 completed success)"
jobs_at 501 1 "[$(job_obj completed success)]"
route --settled --session s-read
expect "--settled: the filled record at its head (0)" 0
echo "later" >> top.txt
git commit -q -am "a later commit"
NEW_HEAD=$(git rev-parse HEAD)
read_at 30
expect "--read: after a new commit the record's head is not HEAD (1)" 1 "not $NEW_HEAD"
route --settled --session s-read
expect "--settled: after a new commit (1)" 1 "the record is for $OLD_HEAD"
put_result s-read "[$COORD_TO]"
route --record --session s-read --reason "$REASON"
[ "$RC" -eq 0 ] && [ "$(key_of s-read | jq -c '[.head, [.checks[].jobs[] | .run_id, .conclusion, .attempt]]')" = "[\"$NEW_HEAD\",[null,null,null]]" ] \
    && pass "--record at the new head replaces the key: the new head and fresh nulls" \
    || fail "--record at the new head: rc $RC, $(key_of s-read)"
RECORD=$(key_of s-read)
gh_reset s-read "$NEW_HEAD"
# The page for the new head holds only a run at the old one: nothing counts.
runs_page "$NEW_HEAD" 1 "[$(RUN_HEAD=$OLD_HEAD run_obj 501 7 1 completed success)]"
read_at 30
expect "--read: hosted runs at the earlier head record no pass for the new one (75)" 75
git reset -q --hard "$OLD_HEAD"

# --- a record over children's results (/execute parity) --------------------------------------

echo "--- children's parts"
MB=$(git merge-base HEAD main)
git checkout -q -B child-a work && echo a >> top.txt && git commit -q -am a && HA=$(git rev-parse HEAD)
git checkout -q -B child-b work && echo b >> top.txt && git commit -q -am b && HB=$(git rev-parse HEAD)
git checkout -q -B shared work && echo s >> top.txt && git commit -q -am s && HS=$(git rev-parse HEAD)
put_result_at c-a "$HA" "$MB" "[$COORD_TO, $PLAN_OK]"
put_result_at c-b "$HB" "$MB" "[$PLAN_TO]"
route --record --session p-shared --reason "$REASON" --head "$HS" --child "c-a@$HA" --child "c-b@$HB"
if [ "$RC" -eq 0 ] && [ "$(key_of p-shared | jq -c '[.head, [.checks[] | [.id, .session, .result_head]]]')" \
        = "[\"$HS\",[[\"check-skill:coordinate\",\"c-a\",\"$HA\"],[\"check-skill:plan\",\"c-b\",\"$HB\"]]]" ]; then
    pass "--record --head --child: the parts carry each child's session and result head"
else
    fail "--record with children: rc $RC, $(key_of p-shared); $(cat "$ERR")"
fi
route --check-record --session p-shared --head "$HS"
expect "--check-record --head: each part validates against its child's result and map (0)" 0
CHILDREC=$(key_of p-shared)
set_key p-shared "$(jq -c '.checks[0].id = "check-skill:other"' <<<"$CHILDREC")"
route --check-record --session p-shared --head "$HS"
expect "--check-record --head: a part naming a check its child's result doesn't time out (1)" 1 "session c-a at $HA"
RECORD=$CHILDREC
gh_reset p-shared "$HS"
runs_page "$HS" 1 "[$(RUN_HEAD=$HS run_obj 540 9 1 completed success)]"
jobs_at 540 1 "[$(job_obj completed success)]"
SHIRABE_ROUTE_NOW=$((T0 + 1800)) route --read --session p-shared --head "$HS"
expect "--read --head: the shared pull request's head, over the children's parts (0)" 0
run_file "$(RUN_HEAD=$HS run_obj 540 9 1 completed success)"
route --settled --session p-shared --head "$HS"
expect "--settled --head: the shared head's filled record (0)" 0

# --- --collect and --parent-read: /execute's own record ------------------------------------

echo "--- --collect"
# child_key <session> <head> <reason> <taken epoch>: the child's own
# hosted_of_record, as its --record wrote it: every check its stored result at
# <head> timed out, with the map's job.
child_key() {
    local res="$XDG_STATE_HOME/shirabe/verification/$1/$2/result.json"
    jq -c --arg h "$2" --arg r "$3" --arg t "$(iso "$4")" --arg wf "$WF" --arg job "$JOB" '
        {head: $h, taken_at: $t, reason: $r,
         checks: [.commands[] | select(.outcome == "timed-out-limit" or .outcome == "timed-out-inside")
                  | {id: .check, jobs: [{workflow: $wf, job: $job, run_id: null, conclusion: null, attempt: null}]}]}' "$res" \
        > "$WORKDIR/ck" && set_key "$1" "$(cat "$WORKDIR/ck")"
}
pkey() { cat "$KOTO_STUB_STORE/$1/${2:-hosted_of_record}" 2>/dev/null; }
child_key c-a "$HA" "reason a" $((T0 - 300))
child_key c-b "$HB" "reason b" $((T0 - 200))
rm -f "$KOTO_STUB_STORE/p-col/hosted_of_record"
route --collect --session p-col --head "$HS" --base main --child c-a --child c-b
if [ "$RC" -eq 0 ] && [ "$(pkey p-col | jq -c --arg t "$(iso $T0)" '[.head, .reason, .taken_at == $t,
        [.checks[] | [.id, .session, .result_head, (.jobs | map(.job))]]]')" \
        = "[\"$HS\",\"reason a; reason b\",true,[[\"check-skill:coordinate\",\"c-a\",\"$HA\",[\"$JOB\"]],[\"check-skill:plan\",\"c-b\",\"$HB\",[\"$JOB\"]]]]" ]; then
    pass "--collect: the parent's key is at the shared head, the union of the children's checks naming each child, one reason from both in order, its own taken_at"
else
    fail "--collect over two children: rc $RC, $(pkey p-col); $(cat "$ERR")"
fi
[ "$(pkey p-col | jq -r '.taken_at | fromdateiso8601')" -gt $((T0 - 200)) ] \
    && pass "--collect: the parent's taken_at is later than both children's" || fail "--collect: taken_at $(pkey p-col | jq -r .taken_at)"
route --check-record --session p-col --head "$HS"
expect "--check-record on the parent's key: each part validates against its child's result and map (0)" 0
SHIRABE_ROUTE_NOW=$((T0 + 600)) route --collect --session p-col --head "$HS" --base main --child c-a --child c-b
[ "$RC" -eq 0 ] && [ "$(pkey p-col | jq -r .taken_at)" = "$(iso $T0)" ] \
    && pass "--collect again at the same head keeps the key and its taken_at, so the wait is not restarted" \
    || fail "--collect again: rc $RC, taken_at $(pkey p-col | jq -r .taken_at)"
child_key c-b "$HB" "reason a" $((T0 - 200))
rm -f "$KOTO_STUB_STORE/p-same/hosted_of_record"
route --collect --session p-same --head "$HS" --base main --child c-a --child c-b
[ "$RC" -eq 0 ] && [ "$(pkey p-same | jq -r .reason)" = "reason a" ] \
    && pass "--collect: a reason two children share is given once" || fail "--collect same reason: rc $RC, $(pkey p-same)"
child_key c-b "$HB" "reason b" $((T0 - 200))

rm -rf "$KOTO_STUB_STORE/c-none" "$KOTO_STUB_STORE/p-none"
route --collect --session p-none --head "$HS" --base main --child c-none
[ "$RC" -eq 4 ] && [ -z "$(pkey p-none)" ] \
    && pass "--collect: no child took the route (4), and no parent key is written" || fail "--collect with no child record: rc $RC, $(pkey p-none)"
printf '[{"name": "c-a"}, {"name": "c-b"}]\n' > "$WORKDIR/children.json"
rm -f "$KOTO_STUB_STORE/p-list/hosted_of_record"
cp "$WORKDIR/bin/koto" "$WORKDIR/koto.orig"
cat > "$WORKDIR/bin/koto" <<EOF
#!/bin/sh
if [ "\$1 \${2-}" = "workflows --children" ]; then cat "$WORKDIR/children.json"; exit 0; fi
exec "$WORKDIR/koto.orig" "\$@"
EOF
chmod +x "$WORKDIR/bin/koto"
route --collect --session p-list --head "$HS" --base main
[ "$RC" -eq 0 ] && [ "$(pkey p-list | jq -c '[.checks[].session]')" = '["c-a","c-b"]' ] \
    && pass "--collect without --child reads the children koto workflows --children lists" \
    || fail "--collect from the listing: rc $RC, $(pkey p-list); $(cat "$ERR")"

# refused_collect <label> <head> <fragment> [<child>...]: --collect exits 1,
# names the cause and writes nothing.
refused_collect() {
    local label=$1 h=$2 frag=$3
    shift 3
    rm -f "$KOTO_STUB_STORE/p-ref/hosted_of_record"
    set -- $(for c in "$@"; do printf -- '--child %s ' "$c"; done)
    route --collect --session p-ref --head "$h" --base main "$@"
    if [ "$RC" -eq 1 ] && [ -z "$(pkey p-ref)" ] && grep -qF -- "$frag" "$ERR"; then
        pass "--collect: $label: refused (1), naming the cause, nothing written"
    else
        fail "--collect: $label: rc $RC, key [$(pkey p-ref)], stderr $(head -c 800 "$ERR")"
    fi
}
git checkout -q -B shared-gh shared && mkdir -p .github && echo x >> .github/x && git add -A && git commit -q -m gh
HSG=$(git rev-parse HEAD)
refused_collect "another child's commit on the shared branch touches .github/" "$HSG" "touches .github/x" c-a c-b
git checkout -q -B shared-cs shared && echo x >> scripts/check-skill.sh && git commit -q -am cs
refused_collect "the shared branch touches scripts/check-skill.sh" "$(git rev-parse HEAD)" "touches scripts/check-skill.sh" c-a c-b
git checkout -q -B shared-tsv shared && sed 's/a_test.sh/z_test.sh/' skills/coordinate/check-skill.tsv > "$WORKDIR/tsv" \
    && cat "$WORKDIR/tsv" > skills/coordinate/check-skill.tsv && git commit -q -am tsv
refused_collect "the shared branch edits a check-skill.tsv row" "$(git rev-parse HEAD)" "edits or deletes rows" c-a c-b
git checkout -q shared
git checkout -q -B child-f work && echo f >> top.txt && git commit -q -am f && HF=$(git rev-parse HEAD)
git checkout -q shared
put_result_at c-f "$HF" "$MB" "[$COORD_TO, $(cmd_rec check-skill:plan failed)]"
child_key c-f "$HF" "reason f" $((T0 - 100))
refused_collect "a child whose stored result has a failed check" "$HS" "check check-skill:plan failed" c-a c-f
put_result_at c-j "$HF" "$MB" "[$COORD_TO]"
child_key c-j "$HF" "reason j" $((T0 - 100))
set_key c-j "$(key_of c-j | jq -c '.checks[0].jobs[0].job = "skill-gate (macos-latest)"')"
refused_collect "a child's record naming a job the map doesn't declare for its check" "$HS" "the map declares" c-a c-j
put_result_at c-n "$HF" "$MB" "[$PLAN_OK, $COORD_TO]"
child_key c-n "$HF" "reason n" $((T0 - 100))
set_key c-n "$(key_of c-n | jq -c '.checks += [{id: "check-skill:plan", jobs: .checks[0].jobs}]')"
refused_collect "a child's record naming a check that didn't time out in its result" "$HS" "did not time out" c-n

echo "--- the parent's key, checked part by part"
GOODP=$(pkey p-col)
set_key p-col "$(jq -c '.checks[1].jobs[0].job = "lint"' <<<"$GOODP")"
route --check-record --session p-col --head "$HS"
expect "--check-record: a parent part naming a job the map doesn't declare (1)" 1 "the map declares"
set_key p-col "$(jq -c '.checks[0].session = "c-f" | .checks[0].result_head = "'"$HF"'"' <<<"$GOODP")"
route --check-record --session p-col --head "$HS"
expect "--check-record: a parent part from a child whose stored result has a failed check (1)" 1 "check check-skill:plan failed"
set_key p-col "$GOODP"

echo "--- --parent-read"
SURL='https://github.com/acme/widgets/pull/12'
# parent_pr <head>: the shared pull request, a draft at <head>.
parent_pr() {
    rm -rf "$FAKE_GH"
    mkdir -p "$FAKE_GH/api"
    jq -cn --arg url "$SURL" --arg h "$1" '{number: 12, url: $url, headRefOid: $h, isDraft: true,
        isCrossRepository: false, body: "Shared change.\n\n---\n\nPart two."}' > "$FAKE_GH/pr.json"
}
rm -f "$KOTO_STUB_STORE/p-run/hosted_of_record" "$KOTO_STUB_STORE/p-run/failure_reason"
parent_pr "$HS"
runs_page "$HS" 1 "[$(RUN_HEAD=$HS run_obj 550 9 1 completed success)]"
jobs_at 550 1 "[$(job_obj completed success)]"
route --parent-read --session p-run --pr "$SURL" --base main --child c-a --child c-b
if [ "$RC" -eq 0 ] && [ "$(pkey p-run | jq -c '[.head, [.checks[].jobs[].run_id]]')" = "[\"$HS\",[550,550]]" ] \
    && grep -qxF "Hosted of record: check-skill:coordinate at $HS: $JOB https://github.com/acme/widgets/actions/runs/550" "$FAKE_GH/edited-body" \
    && grep -qxF "Hosted of record: check-skill:plan at $HS: $JOB https://github.com/acme/widgets/actions/runs/550" "$FAKE_GH/edited-body" \
    && grep -q "^pr view $SURL " "$FAKE_GH/calls"; then
    pass "--parent-read: every declared job concluded success at the shared head: run ids filled, one body line per check with its run link"
else
    fail "--parent-read: rc $RC, $(pkey p-run); body $(cat "$FAKE_GH/edited-body" 2>&1); $(cat "$ERR")"
fi
run_file "$(RUN_HEAD=$HS run_obj 550 9 1 completed success)"
route --mark-ready --session p-run --pr "$SURL" --head "$HS"
[ "$RC" -eq 0 ] && grep -q "^pr ready $SURL" "$FAKE_GH/calls" && pass "--mark-ready --pr: marks the settled shared pull request ready" \
    || fail "--mark-ready --pr: rc $RC; $(cat "$ERR")"
route --ready --session p-run --pr "$SURL" --head "$HS"
expect "--ready --pr: out of draft, settled, every line linked (0)" 0

rm -f "$KOTO_STUB_STORE/p-run/hosted_of_record"
parent_pr "$HS"
runs_page "$HS" 1 "[$(RUN_HEAD=$HA run_obj 551 9 1 completed success)]"
jobs_at 551 1 "[$(job_obj completed success)]"
route --parent-read --session p-run --pr "$SURL" --base main --child c-a --child c-b
expect "--parent-read: success at a child's head only, none at the shared head: no pass (75)" 75
route --mark-ready --session p-run --pr "$SURL" --head "$HS"
[ "$RC" -eq 1 ] && ! grep -q '^pr ready' "$FAKE_GH/calls" && grep -qF "have not been read at $HS: check-skill:coordinate/$JOB" "$ERR" \
    && pass "--mark-ready: refuses an unread parent record, naming the job and the shared head, and marks nothing ready" \
    || fail "--mark-ready on an unread record: rc $RC; $(cat "$ERR")"

for c in cancelled failure skipped; do
    rm -f "$KOTO_STUB_STORE/p-run/hosted_of_record"
    parent_pr "$HS"
    runs_page "$HS" 1 "[$(RUN_HEAD=$HS run_obj 552 9 1 completed "$c")]"
    jobs_at 552 1 "[$(job_obj completed "$c")]"
    route --parent-read --session p-run --pr "$SURL" --base main --child c-a --child c-b
    expect "--parent-read: a declared job concluded $c at the shared head is refused, naming both jobs and the commit (1)" 1 \
        "check check-skill:coordinate, job $JOB, commit $HS" "check check-skill:plan, job $JOB, commit $HS" "concluded $c"
done

echo "--- --parent-read: the wait is the parent's"
rm -f "$KOTO_STUB_STORE/p-wait/hosted_of_record" "$KOTO_STUB_STORE/p-wait/failure_reason"
child_key c-a "$HA" "reason a" $((T0 - 300))
parent_pr "$HS"
runs_page "$HS" 1 "[]"
SHIRABE_ROUTE_NOW=$((T0 + 10 * 60)) route --parent-read --session p-wait --pr "$SURL" --base main --child c-a
expect "--parent-read: pending, parent taken_at 0 minutes old: waits (75)" 75
PT=$(pkey p-wait | jq -r '.taken_at | fromdateiso8601')
child_key c-a "$HA" "reason a" $((PT - 130 * 60))
put_result_at c-a "$HA" "$MB" "[$COORD_TO, $PLAN_OK]"
jq --arg f "$(iso $((PT - 140 * 60)))" '.finished_at = $f' "$XDG_STATE_HOME/shirabe/verification/c-a/$HA/result.json" > "$WORKDIR/r" \
    && mv "$WORKDIR/r" "$XDG_STATE_HOME/shirabe/verification/c-a/$HA/result.json"
rm -f "$KOTO_STUB_STORE/p-wait/hosted_of_record"
SHIRABE_ROUTE_NOW=$PT route --collect --session p-wait --head "$HS" --base main --child c-a
SHIRABE_ROUTE_NOW=$((PT + 10 * 60)) route --parent-read --session p-wait --pr "$SURL" --base main --child c-a
expect "--parent-read: a child taken_at 130 minutes old, the parent's 10: still waits (75)" 75
SHIRABE_ROUTE_NOW=$((PT + 119 * 60)) route --parent-read --session p-wait --pr "$SURL" --base main --child c-a
expect "--parent-read: the parent's taken_at 119 minutes old: waits (75)" 75
SHIRABE_ROUTE_NOW=$((PT + 121 * 60)) route --parent-read --session p-wait --pr "$SURL" --base main --child c-a
expect "--parent-read: past 120 minutes from the parent's taken_at (3)" 3
grep -qF "check-skill:coordinate/$JOB at $HS" "$KOTO_STUB_STORE/p-wait/failure_reason" 2>/dev/null \
    && pass "--parent-read: its failure_reason names the pending job and the shared head" \
    || fail "--parent-read: failure_reason [$(cat "$KOTO_STUB_STORE/p-wait/failure_reason" 2>&1)]"
put_result_at c-a "$HA" "$MB" "[$COORD_TO, $PLAN_OK]"
child_key c-a "$HA" "reason a" $((T0 - 300))

echo "--- --parent-read with no child record, and --ready --absent-ok"
rm -rf "$KOTO_STUB_STORE/p-quiet"
parent_pr "$HS"
route --parent-read --session p-quiet --pr "$SURL" --base main --child c-none
[ "$RC" -eq 0 ] && [ -z "$(pkey p-quiet)" ] && ! grep -q '^api ' "$FAKE_GH/calls" \
    && pass "--parent-read: no child took the route: 0, no key, no hosted job read" \
    || fail "--parent-read with no child record: rc $RC, $(cat "$FAKE_GH/calls" 2>&1)"
route --ready --session p-quiet --pr "$SURL" --absent-ok
expect "--ready --absent-ok: no key (0)" 0
route --ready --session p-quiet --pr "$SURL"
expect "--ready without --absent-ok: no key is still 1" 1
parent_pr "$HS"
route --mark-ready --session p-quiet --pr "$SURL" --absent-ok --child c-a
[ "$RC" -eq 1 ] && ! grep -q '^pr ready' "$FAKE_GH/calls" 2>/dev/null \
    && pass "--mark-ready --absent-ok: a child took the route and no parent key yet: refused (1), nothing marked ready" \
    || fail "--mark-ready --absent-ok with a child record: rc $RC; $(cat "$ERR")"
route --mark-ready --session p-quiet --pr "$SURL" --absent-ok --child c-none
[ "$RC" -eq 0 ] && grep -q "^pr ready $SURL" "$FAKE_GH/calls" \
    && pass "--mark-ready --absent-ok: no child took the route: the plain gh pr ready" \
    || fail "--mark-ready --absent-ok with no child record: rc $RC; $(cat "$ERR")"

echo "--- a node's key, its work tree, and --read --dry-run"
rm -f "$KOTO_STUB_STORE/p-node/run/hosted/n1"
route --collect --session p-node --key run/hosted/n1 --head "$HS" --base main --work-tree "$PWD" --child c-a --child c-b
[ "$RC" -eq 0 ] && [ "$(pkey p-node run/hosted/n1 | jq -r .work_tree)" = "$PWD" ] && [ -z "$(pkey p-node)" ] \
    && pass "--collect --key run/hosted/n1: the node's own key, carrying its work tree; hosted_of_record untouched" \
    || fail "--collect for a node: rc $RC, $(pkey p-node run/hosted/n1); $(cat "$ERR")"
NODE_BEFORE=$(pkey p-node run/hosted/n1)
parent_pr "$HS"
runs_page "$HS" 1 "[$(RUN_HEAD=$HS run_obj 560 9 1 completed success)]"
jobs_at 560 1 "[$(job_obj completed success)]"
(cd "$WORKDIR" && "$ROUTE" --read --dry-run --session p-node --key run/hosted/n1 --pr "$SURL" --head "$HS" 2>"$ERR")
RC=$?
[ "$RC" -eq 0 ] && [ "$(pkey p-node run/hosted/n1)" = "$NODE_BEFORE" ] && [ ! -e "$FAKE_GH/edited-body" ] \
    && pass "--read --dry-run on a node's key, run outside the work tree it records: 0, and nothing written" \
    || fail "--read --dry-run: rc $RC; $(cat "$ERR")"
runs_page "$HS" 1 "[]"
SHIRABE_ROUTE_NOW=$((T0 + 121 * 60)) route --read --dry-run --session p-node --key run/hosted/n1 --pr "$SURL" --head "$HS"
[ "$RC" -eq 3 ] && [ ! -e "$KOTO_STUB_STORE/p-node/failure_reason" ] \
    && pass "--read --dry-run past 120 minutes: 3, and no failure_reason written" || fail "--read --dry-run at 121 minutes: rc $RC"
route --read --session p-node --key bad/key --pr "$SURL"
expect "--key outside hosted_of_record and run/hosted/<node> is a usage error (2)" 2
route --read --session p-node --pr "not-a-url"
expect "--pr that is no pull request URL is a usage error (2)" 2
cp "$WORKDIR/koto.orig" "$WORKDIR/bin/koto"
git checkout -q work

echo
echo "verification-route_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
