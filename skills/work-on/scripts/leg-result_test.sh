#!/usr/bin/env bash
# leg-result_test.sh -- does a /work-on run bound to a caller's leg
# (--koto-leg) resolve that leg with the pull request it opened? (#995)
# Part of the work-on skill
#
# koto builds a bound leg's promoted payload from a `result:` map on the
# terminal the run lands in. work-on.md's `pr_creation` writes the submitted
# `pr_url` into context on its created edge, and `done` and
# `done_already_complete` declare `pr: "${context.pr_url}"`. A coordinator
# reads that `pr` with record-common.sh's lib_report_pr, so a worker that
# opened a pull request never has to be asked for it again.
#
# This file checks two things:
#
#   1. Static, no engine: the shipped template carries the assignment on the
#      created edge, both success terminals declare the map, and done_blocked
#      declares none, so a failure's payload stays koto's own.
#   2. Engine: a fixture built from the SHIPPED state blocks (pr_creation,
#      ci_monitor, ci_pass_counting, cascade_entry and the three terminals,
#      extracted from the
#      template at run time) is opened on a `work-on` leg and driven to each
#      terminal, and koto's record of the leg is read:
#        - created + pr_url, CI green, no anchor: done through record_keep,
#          payload.pr the URL and payload.record skipped, nothing missing;
#        - the same as a child (ci_pass_counting straight to done): the URL;
#        - created with no pr_url: pr "", read as naming none;
#        - done_already_complete with pr_url in context: the URL;
#        - done_already_complete with none: pr "" listed under `missing`,
#          which lib_report_pr reads as naming no pull request;
#        - done_blocked (no closing keyword): status failure, no pr.
#      The gh one-liners are replaced by fixed exits and the gate scripts by
#      fakes under a fake PLUGIN_ROOT, as in output-gates-routing_test.sh.
#
# Part 2 skips, loudly, when no koto with --koto-leg is on PATH (the bash 3.2
# floor leg has no koto).
#
# Usage: leg-result_test.sh
# Exit codes: 0 all pass (or the engine part skipped), 1 any failed, 2 the
# harness could not run.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
REAL_ROOT=$(cd "$SKILL_DIR/../.." && pwd)
COORD_SCRIPTS="$REAL_ROOT/skills/coordinate/scripts"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: want [$2], got [$3]"; fi; }

[ -f "$TEMPLATE" ] || { echo "template not found: $TEMPLATE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/leg-result.XXXXXX") || exit 1
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 1
cleanup() { case "${WORKDIR:-}" in */leg-result.*) rm -rf "$WORKDIR" ;; esac; return 0; }
trap cleanup EXIT

# extract_state <name>: the state's block from the template's frontmatter.
extract_state() {
    awk -v want="  $1:" '
        $0 == want { found = 1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        found && /^---$/ { exit }
        found { print }
    ' "$TEMPLATE"
}

# --- 1. static -----------------------------------------------------------------------

echo "--- the shipped template"

# The created edge into ci_monitor, from its `- target:` line to the next one.
CREATED_EDGE=$(extract_state pr_creation | awk '
    /^      - target: ci_monitor$/ { on = 1; print; next }
    on && /^      - target:/ { exit }
    on { print }')
# shellcheck disable=SC2016 # the ${...} is koto's, matched literally
if grep -q '^          pr_url: "\${evidence.pr_url}"$' <<<"$CREATED_EDGE"; then
    pass "pr_creation's created edge writes pr_url from the evidence"
else
    fail "pr_creation's created edge does not write pr_url: [$CREATED_EDGE]"
fi
for t in "done" done_already_complete; do
    BLOCK=$(extract_state "$t")
    # shellcheck disable=SC2016 # the ${...} is koto's, matched literally
    if grep -q '^      pr: "\${context.pr_url}"$' <<<"$BLOCK"; then
        pass "$t declares result pr from context.pr_url"
    else
        fail "$t does not declare result pr: [$BLOCK]"
    fi
done
BLOCK=$(extract_state done_blocked)
if grep -q '^    result:' <<<"$BLOCK"; then
    fail "done_blocked declares a result map; its payload must stay koto's own"
else
    pass "done_blocked declares no result map"
fi

# --- 2. engine -----------------------------------------------------------------------

if ! command -v koto >/dev/null 2>&1 || ! koto init --help 2>/dev/null | grep -q -- '--koto-leg'; then
    echo
    echo "SKIP: no koto with --koto-leg on PATH -- the engine cases did not run"
    echo
    echo "leg-result_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
fi

echo "--- a leg-bound run's result"

# Sessions and requests live under a temporary HOME, out of the developer's
# $HOME/.koto.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"
REPO="$WORKDIR/repo"
mkdir -p "$REPO"
(cd "$REPO" && git init -q . && git config user.email t@example.com && git config user.name t \
    && git commit -q --allow-empty -m "chore: init" && git checkout -q -b feature/x) >/dev/null 2>&1 \
    || { echo "could not create the fixture repository" >&2; exit 2; }

# The fake plugin root. check-pr-output.sh passes, and so do red-first.sh and
# test-change.sh (ci_pass_counting's gates); find-anchor-plan.sh finds no PLAN
# (exit 1); session-role.sh prints the word in $RC_DIR/role (default root).
FAKE_ROOT="$WORKDIR/plugin"
RC_DIR="$WORKDIR/rc"
mkdir -p "$FAKE_ROOT/skills/work-on/scripts" "$RC_DIR"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_ROOT/skills/work-on/scripts/check-pr-output.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_ROOT/skills/work-on/scripts/red-first.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_ROOT/skills/work-on/scripts/test-change.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAKE_ROOT/skills/work-on/scripts/find-anchor-plan.sh"
cat > "$FAKE_ROOT/skills/work-on/scripts/session-role.sh" <<EOF
#!/usr/bin/env bash
if [ -f "$RC_DIR/role" ]; then cat "$RC_DIR/role"; else echo root; fi
EOF
chmod +x "$FAKE_ROOT"/skills/work-on/scripts/*
# record_keep's script is the real one, with the record scripts it reaches,
# so a root run that isn't a multi-pr item records record=skipped there.
mkdir -p "$FAKE_ROOT/scripts/lib"
cp "$SCRIPT_DIR/multi-pr-item-record.sh" "$FAKE_ROOT/skills/work-on/scripts/"
cp "$REAL_ROOT/scripts/run-trail.sh" "$REAL_ROOT/scripts/run-record-pin.sh" "$FAKE_ROOT/scripts/"
cp "$REAL_ROOT/scripts/lib/record-store.sh" "$FAKE_ROOT/scripts/lib/"
chmod +x "$FAKE_ROOT/skills/work-on/scripts/multi-pr-item-record.sh" "$FAKE_ROOT/scripts/run-trail.sh" "$FAKE_ROOT/scripts/run-record-pin.sh"

# stub_block <block> <gate=exit>...: the named gates' commands replaced by
# fixed exits, keyed on the gate name above each command.
stub_block() {
    local block="$1"; shift
    printf '%s\n' "$block" | awk -v stubs="$*" '
        BEGIN { n = split(stubs, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, "="); ex[kv[1]] = kv[2] } }
        /^      [a-z_]+:$/ { gate = $1; sub(/:$/, "", gate) }
        /^        command:/ { if (gate in ex) { print "        command: \"exit " ex[gate] "\""; next } }
        { print }'
}

# build <dir> <gate=exit>...: a fixture named work-on.md, since koto admits a
# session to a leg by its template's file name. `start` routes to the shipped
# pr_creation (go: pr) or straight to the shipped done_already_complete (go:
# already); the shipped ci_monitor, ci_pass_counting, cascade_entry, done, done_already_complete
# and done_blocked follow, and any other target is a stub terminal.
build() {
    local dir="$1"; shift
    local s blocks="" t stubs=""
    local shipped="pr_creation ci_monitor ci_pass_counting cascade_entry record_keep done done_already_complete done_blocked"
    for s in pr_creation ci_monitor ci_pass_counting cascade_entry record_keep; do
        blocks="$blocks$(stub_block "$(extract_state "$s")" "$@")
"
    done
    for t in $(printf '%s\n' "$blocks" | awk '/^      - target:/ { print $3 }' | sort -u); do
        case " $shipped " in *" $t "*) ;; *) stubs="$stubs $t" ;; esac
    done
    {
        printf '%s\n' '---' 'name: work-on' 'version: "1.0"' \
            'description: Fixture driving work-on.md to its terminals on a leg.' 'initial_state: start' \
            'variables:' \
            '  ISSUE_NUMBER:' '    description: issue' '    required: false' \
            '  ISSUE_REPO:' '    description: issue repository' '    required: false' \
            '  PLUGIN_ROOT:' '    description: plugin root' '    required: false' \
            '  SHARED_BRANCH:' '    description: shared branch' '    required: false' \
            '  ISSUE_SOURCE:' '    description: issue source' '    required: false' \
            '  ARTIFACT_PREFIX:' '    description: artifact prefix' '    required: false' \
            '  PLAN_DOC:' '    description: plan' '    required: false' \
            '  VERIFICATION:' '    description: verification' '    required: false' \
            '    default: local' '    values: [local, hosted-ci]' \
            '  VERIFICATION_DEFERRAL_REASON:' '    description: deferral reason' '    required: false' \
            'states:' '  start:' '    accepts:' '      go:' '        type: enum' \
            '        values: [pr, already]' '        required: true' '    transitions:' \
            '      - target: pr_creation' '        when:' '          go: pr' \
            '      - target: done_already_complete' '        when:' '          go: already'
        printf '%s' "$blocks"
        for s in "done" done_already_complete done_blocked; do
            extract_state "$s"
        done
        for t in $stubs; do
            printf '%s\n' "  $t:" '    terminal: true'
        done
        printf '%s\n' '---' '' '## start' '' 'Start.'
        for s in $shipped $stubs; do
            printf '%s\n' '' "## $s" '' 'Stub.'
        done
    } > "$dir/work-on.md"
}

N=0
# open_leg <gate=exit>...: builds a fixture, creates a request with a
# `work-on` leg and opens a session bound to it. Sets S, REQ and DIR.
open_leg() {
    N=$((N + 1))
    DIR="$WORKDIR/f$N"
    S="lr-$N"
    mkdir -p "$DIR"
    build "$DIR" "$@"
    REQ=$(cd "$REPO" && koto request create \
        --with-data '{"legs":[{"name":"work-on","role":"work-on","template":"work-on.md","inputs":{}}]}' \
        --requested-by test --coordinator-of-record test 2>"$DIR/req.err" | jq -r '.request_id // empty')
    [ -n "$REQ" ] || { fail "case $N: koto request create: $(head -c 300 "$DIR/req.err")"; return 1; }
    (cd "$REPO" && koto init "$S" --template "$DIR/work-on.md" --var PLUGIN_ROOT="$FAKE_ROOT" \
        --var ISSUE_NUMBER=7 --koto-leg "$REQ:work-on") >"$DIR/init.out" 2>&1 \
        || { fail "case $N: koto init: $(head -c 300 "$DIR/init.out")"; return 1; }
}
tick() { (cd "$REPO" && koto next "$S" --no-cleanup "$@") >"$DIR/tick.out" 2>&1; }
state() { (cd "$REPO" && koto status "$S" 2>/dev/null) | jq -r '.current_state // "none"'; }
leg() { (cd "$REPO" && koto request get "$REQ" 2>/dev/null) | jq -c "(.request // .) | .legs[\"work-on\"]$1"; }

# report_pr: what coordinate's lib_report_pr reads from koto's record of the
# leg, the reader the payload exists for.
report_pr() {
    # HERE, PROG and UNIT_LEG are record-common.sh's inputs.
    # shellcheck disable=SC1091,SC2034
    (
        HERE="$COORD_SCRIPTS" PROG=leg-result_test
        . "$COORD_SCRIPTS/record-common.sh"
        UNIT_LEG="leg $REQ:work-on"
        cd "$REPO" && lib_report_pr && printf '%s' "$REPORT_PR"
    )
}

URL=https://github.com/o/r/pull/7
CREATED="{\"pr_status\":\"created\",\"pr_url\":\"$URL\"}"

# 1. A root run: created, CI green, no PLAN behind it, done.
if open_leg closing_keyword=0 ci_passing=0 merge_state_clean=0; then
    tick --with-data '{"go":"pr"}'
    tick --with-data "$CREATED"
    eq "root: created with CI green ends at done" "done" "$(state)"
    eq "root: pr_url is in context" "$URL" "$(cd "$REPO" && koto context get "$S" pr_url 2>/dev/null)"
    eq "root: the leg's result was promoted" '"promoted"' "$(leg .result_source)"
    eq "root: the leg records done" '"done"' "$(leg .result_final_state)"
    eq "root: the leg's status is success" '"success"' "$(leg .result.status)"
    eq "root: the leg's payload carries the pull request" "\"$URL\"" "$(leg .result.payload.pr)"
    eq "root: the payload lists nothing missing" null "$(leg .result.payload.missing)"
    eq "root: record_keep passed on the way, and the payload says it pinned nothing (not a multi-pr item)" \
        '"skipped"' "$(leg .result.payload.record)"
    if [ -f "$COORD_SCRIPTS/record-common.sh" ]; then
        eq "root: lib_report_pr reads the pull request" "$URL" "$(report_pr)"
    fi
fi

# 2. A child of /execute: ci_pass_counting goes straight to done.
printf 'child\n' > "$RC_DIR/role"
if open_leg closing_keyword=0 ci_passing=0 merge_state_clean=0; then
    tick --with-data '{"go":"pr"}'
    tick --with-data "$CREATED"
    eq "child: created with CI green ends at done" "done" "$(state)"
    eq "child: the leg's payload carries the pull request" "\"$URL\"" "$(leg .result.payload.pr)"
fi
rm -f "$RC_DIR/role"

# 3. created sent without pr_url: the edge writes an empty value, so the
# payload's pr is empty (not listed as missing, since the key was written),
# and a coordinator reads it as naming no pull request, today's fallback.
if open_leg closing_keyword=0 ci_passing=0 merge_state_clean=0; then
    tick --with-data '{"go":"pr"}'
    tick --with-data '{"pr_status":"created"}'
    eq "no pr_url: created with CI green still ends at done" "done" "$(state)"
    eq "no pr_url: the leg's status is success" '"success"' "$(leg .result.status)"
    eq "no pr_url: pr is empty" '""' "$(leg .result.payload.pr)"
    if [ -f "$COORD_SCRIPTS/record-common.sh" ]; then
        eq "no pr_url: lib_report_pr reads no pull request" "" "$(report_pr)"
    fi
fi

# 4. done_already_complete with a pull request recorded (an earlier lap
# opened one).
if open_leg; then
    printf '%s' "$URL" | (cd "$REPO" && koto context add "$S" pr_url) >/dev/null 2>&1
    tick --with-data '{"go":"already"}'
    eq "already, with a pull request: the run ends at done_already_complete" done_already_complete "$(state)"
    eq "already, with a pull request: the leg records done_already_complete" '"done_already_complete"' "$(leg .result_final_state)"
    eq "already, with a pull request: the payload carries it" "\"$URL\"" "$(leg .result.payload.pr)"
fi

# 5. done_already_complete with none: pr is empty and koto names it missing,
# which a coordinator reads as naming no pull request.
if open_leg; then
    tick --with-data '{"go":"already"}'
    eq "already, none: the run ends at done_already_complete" done_already_complete "$(state)"
    eq "already, none: the leg's status is success" '"success"' "$(leg .result.status)"
    eq "already, none: pr is empty" '""' "$(leg .result.payload.pr)"
    eq "already, none: koto lists pr as missing" '["pr"]' "$(leg .result.payload.missing)"
    if [ -f "$COORD_SCRIPTS/record-common.sh" ]; then
        eq "already, none: lib_report_pr reads no pull request" "" "$(report_pr)"
    fi
fi

# 6. done_blocked: a body without the closing keyword. Its result is koto's
# own, with no pr.
if open_leg closing_keyword=1 ci_passing=0 merge_state_clean=0; then
    tick --with-data '{"go":"pr"}'
    tick --with-data "$CREATED"
    eq "blocked: a body without the closing keyword ends at done_blocked" done_blocked "$(state)"
    eq "blocked: the leg records done_blocked" '"done_blocked"' "$(leg .result_final_state)"
    eq "blocked: the leg's status is failure" '"failure"' "$(leg .result.status)"
    eq "blocked: the payload has no pr" false "$(leg '.result.payload // {} | has("pr")')"
fi

echo
echo "leg-result_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
