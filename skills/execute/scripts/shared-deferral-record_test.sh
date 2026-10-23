#!/usr/bin/env bash
# shared-deferral-record_test.sh -- does pr_finalization's deferral_recorded
# gate hold /execute's shared PR until its body records every verification
# deferral the run carries, and pass a run with none without reading GitHub?
# Part of the execute skill
#
# shared-deferral-record.sh collects the run's own reason (VERIFICATION
# hosted-ci) and each child's verification_deferral, and checks the owned PR's
# body with /work-on's check-pr-output.sh --deferral-record. This file checks:
#
#   1. No engine, through a koto stub, a gh stub and an owned-pr.sh stand-in
#      (check-pr-output.sh's CHECK_PR_OUTPUT_OWNED_PR seam), with the real
#      check-pr-output.sh:
#        - a run with no deferral passes (0) and reads nothing from GitHub;
#        - the run's own reason, and a child's, each need the record (1 until
#          the body has it, then 0), a child's counting even when the run
#          didn't defer;
#        - several children's reasons are each needed, and one reason given by
#          the run and a child is asked for once;
#        - hosted-ci with no reason, a failed child listing, a failed or odd
#          key read, an empty key, no single owned PR, and bad usage can't be
#          decided (2);
#        - --child reads exactly the named sessions (a coordinated node's
#          work items) with no child listing, holding the PR on a named
#          child's reason and ignoring a listed child it doesn't name;
#        - --list prints the run's reason and each named child's, once each,
#          with no GitHub read, and nothing with no deferral.
#   2. Engine: a parent session and two children made with `koto init
#      --parent`, one from a fixture holding work-on.md's SHIPPED
#      verification_deferred state (extracted at run time) with
#      VERIFICATION=hosted-ci and a reason on a shared branch, the other
#      local. The deferred child writes verification_deferral itself, and the
#      script, over the real koto, holds the shared PR until its body records
#      that reason. A parent whose children didn't defer passes with no gh
#      call.
#
# Part 2 skips, loudly, when koto is absent (the bash 3.2 floor leg has none).
#
# Usage: shared-deferral-record_test.sh
# Exit codes: 0 all pass (or the engine part skipped), 1 any failed, 2 the
# harness could not run.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$SKILL_DIR/../.." && pwd)
GATE="$SCRIPT_DIR/shared-deferral-record.sh"
WORK_ON_TEMPLATE="$REPO_ROOT/skills/work-on/koto-templates/work-on.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -x "$GATE" ] || { echo "not executable: $GATE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }
REAL_KOTO=$(command -v koto || true)

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/shared-deferral-record-test.XXXXXX") || exit 2
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 2
cleanup() { case "${WORKDIR:-}" in */shared-deferral-record-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
trap cleanup EXIT

BIN="$WORKDIR/bin"
STUB="$WORKDIR/stub"
mkdir -p "$BIN" "$STUB/ctx"

# koto stub: `workflows --children <s>` prints $STUB/children.json (exit
# $STUB/workflows.rc when that file exists); `context exists <c> <key>` is 0
# when $STUB/ctx/<c> exists, else 1 (exit $STUB/exists.rc overrides);
# `context get <c> <key>` prints that file.
cat > "$BIN/koto" <<'EOF'
#!/usr/bin/env bash
STUB="${SDR_STUB:?}"
printf '%s\n' "$*" >> "$STUB/koto.calls"
case "$1 ${2-}" in
    "workflows --children")
        if [ -f "$STUB/workflows.rc" ]; then echo "koto: no session" >&2; exit "$(cat "$STUB/workflows.rc")"; fi
        cat "$STUB/children.json" ;;
    "context exists")
        if [ -f "$STUB/exists.rc" ]; then echo "koto: store unreadable" >&2; exit "$(cat "$STUB/exists.rc")"; fi
        [ -f "$STUB/ctx/$3" ] ;;
    "context get")
        cat "$STUB/ctx/$3" ;;
    *) echo "koto stub: unexpected call: $*" >&2; exit 64 ;;
esac
EOF
# gh stub: `gh pr view <url> --json body` prints {"body": <$STUB/body.md>}.
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
STUB="${SDR_STUB:?}"
printf '%s\n' "$*" >> "$STUB/gh.calls"
jq -Rsc '{body: .}' "$STUB/body.md"
EOF
# owned-pr.sh stand-in: one URL, or $STUB/owned.rc's exit.
cat > "$BIN/owned-pr.sh" <<'EOF'
#!/usr/bin/env bash
STUB="${SDR_STUB:?}"
printf '%s\n' "$*" >> "$STUB/owned.calls"
if [ -f "$STUB/owned.rc" ]; then exit "$(cat "$STUB/owned.rc")"; fi
echo https://github.com/acme/widgets/pull/12
EOF
chmod +x "$BIN/koto" "$BIN/gh" "$BIN/owned-pr.sh"

REASON="host is in a measurement window until 02:40Z"
REASON2="runner pool is down until Monday"
OWNED_ARGS="--repo acme/widgets --head impl/x --state open --run-id 00112233445566778899aabbccddeeff"

# body <reason>...: a Part 2 Verification section naming each reason.
body() {
    {
        printf '%s\n' "A change." "" "---" "" "## Verification" "" \
            "Local verification did not run: it was deferred to hosted CI."
        local r
        for r in "$@"; do printf 'Reason: %s\n' "$r"; done
        printf '%s\n' "Hosted CI is the build of record for this change."
    } > "$STUB/body.md"
}
children() { # children <name>...
    jq -nc '$ARGS.positional | map({name: ., parent_workflow: "execute-x"})' --args "$@" > "$STUB/children.json"
}
child_deferred() { printf '%s' "$2" > "$STUB/ctx/$1"; }
reset_stub() {
    rm -rf "$STUB"
    mkdir -p "$STUB/ctx"
    : > "$STUB/koto.calls"
    : > "$STUB/gh.calls"
    : > "$STUB/owned.calls"
    children
    printf '%s\n' "A change." "" "---" "" "Context." > "$STUB/body.md"
}
count() { grep -c . "$STUB/$1" || true; }

RC=0
# run_stub <verification> <reason>: the gate under the stubs.
run_stub() {
    # shellcheck disable=SC2086 # OWNED_ARGS is a word list
    (PATH="$BIN:$PATH" SDR_STUB="$STUB" CHECK_PR_OUTPUT_OWNED_PR="$BIN/owned-pr.sh" \
        "$GATE" --session execute-x --verification "$1" --reason "$2" -- $OWNED_ARGS) \
        >"$WORKDIR/out" 2>"$WORKDIR/err"
    RC=$?
}
expect() { # expect <label> <rc>
    if [ "$RC" -eq "$2" ]; then pass "$1 ($RC)"; else fail "$1: want $2, got $RC; stderr [$(cat "$WORKDIR/err")]"; fi
}

echo "--- the gate, through stubs"

reset_stub
children execute-x.o-a execute-x.o-b
run_stub local ""
expect "no deferral anywhere: passes" 0
[ "$(count gh.calls)" = 0 ] && [ "$(count owned.calls)" = 0 ] \
    && pass "no deferral anywhere: no owned-PR lookup and no gh call" \
    || fail "no deferral: gh calls $(count gh.calls), owned calls $(count owned.calls)"

reset_stub
run_stub "" ""
expect "VERIFICATION empty (an older session) and no child deferred: passes" 0

reset_stub
children execute-x.o-a
run_stub hosted-ci "$REASON"
expect "the run deferred, the body has no record: holds" 1
grep -q 'local verification did not run' "$WORKDIR/err" \
    && pass "the run deferred, no record: stderr names the missing part" \
    || fail "no record: stderr [$(cat "$WORKDIR/err")]"
body "$REASON"
run_stub hosted-ci "$REASON"
expect "the run deferred, the body records its reason: passes" 0
grep -q -- '--repo acme/widgets' "$STUB/owned.calls" \
    && pass "the owned-PR lookup gets the arguments after --" \
    || fail "owned-pr.sh got [$(cat "$STUB/owned.calls")]"

reset_stub
children execute-x.o-a execute-x.o-b
child_deferred execute-x.o-b "$REASON2"
run_stub local ""
expect "the run didn't defer, a child did, no record: holds" 1
body "$REASON2"
run_stub local ""
expect "the run didn't defer, a child did, the body records it: passes" 0

reset_stub
children execute-x.o-a execute-x.o-b execute-x.o-c
child_deferred execute-x.o-a "$REASON"
child_deferred execute-x.o-b "$REASON2"
body "$REASON"
run_stub hosted-ci "$REASON"
expect "two children's reasons, the body records one: holds" 1
grep -qF "verbatim: $REASON2" "$WORKDIR/err" \
    && pass "two reasons, one missing: stderr names the missing reason" \
    || fail "two reasons: stderr [$(cat "$WORKDIR/err")]"
if grep -qF "verbatim: $REASON" "$WORKDIR/err"; then
    fail "two reasons: the recorded reason is reported missing"
else
    pass "two reasons: the recorded reason is not reported missing"
fi
body "$REASON" "$REASON2"
run_stub hosted-ci "$REASON"
expect "two children's reasons, both recorded: passes" 0

reset_stub
children execute-x.o-a
child_deferred execute-x.o-a "$REASON"
body "$REASON"
run_stub hosted-ci "$REASON"
expect "the run's reason and a child's are the same: one record passes" 0

echo "--- what can't be decided"

reset_stub
run_stub hosted-ci ""
expect "hosted-ci with no reason" 2
reset_stub
printf '1\n' > "$STUB/workflows.rc"
run_stub local ""
expect "the child listing failed" 2
reset_stub
printf '[{"nome":"x"}]\n' > "$STUB/children.json"
run_stub local ""
expect "the child listing is not a list of sessions" 2
reset_stub
children execute-x.o-a
printf '3\n' > "$STUB/exists.rc"
run_stub local ""
expect "a child's key check failed (exit 3)" 2
reset_stub
children execute-x.o-a
child_deferred execute-x.o-a ""
run_stub local ""
expect "a child recorded an empty reason" 2
reset_stub
children execute-x.o-a
child_deferred execute-x.o-a "$REASON"
body "$REASON"
printf '3\n' > "$STUB/owned.rc"
run_stub local ""
expect "a deferral, and no single owned PR" 2

reset_stub
(PATH="$BIN:$PATH" SDR_STUB="$STUB" "$GATE" --session execute-x --verification local) >/dev/null 2>"$WORKDIR/err"
RC=$?
expect "no owned-pr.sh arguments: usage" 2
(PATH="$BIN:$PATH" SDR_STUB="$STUB" "$GATE" --verification local -- --repo a/b) >/dev/null 2>"$WORKDIR/err"
RC=$?
expect "no --session: usage" 2
(PATH="$BIN:$PATH" SDR_STUB="$STUB" "$GATE" --session execute-x -- --repo a/b) >/dev/null 2>"$WORKDIR/err"
RC=$?
expect "no --verification: usage" 2
run_stub sometimes ""
expect "a VERIFICATION outside local and hosted-ci" 2

echo "--- a coordinated node's children (--child) and the reasons alone (--list)"

# run_child <verification> <reason> <child>... -- the gate over an explicit
# child list, with the owned-PR arguments after it.
run_child() {
    local v="$1" r="$2" c args=()
    shift 2
    for c in "$@"; do args+=(--child "$c"); done
    # shellcheck disable=SC2086 # OWNED_ARGS is a word list
    (PATH="$BIN:$PATH" SDR_STUB="$STUB" CHECK_PR_OUTPUT_OWNED_PR="$BIN/owned-pr.sh" \
        "$GATE" --session execute-x --verification "$v" --reason "$r" "${args[@]}" -- $OWNED_ARGS) \
        >"$WORKDIR/out" 2>"$WORKDIR/err"
    RC=$?
}
# run_list <verification> <reason> <child>... -- --list over an explicit child
# list; the reasons on $WORKDIR/out.
run_list() {
    local v="$1" r="$2" c args=()
    shift 2
    for c in ${1+"$@"}; do args+=(--child "$c"); done
    (PATH="$BIN:$PATH" SDR_STUB="$STUB" "$GATE" --session execute-x --verification "$v" --reason "$r" \
        ${args[@]+"${args[@]}"} --list) >"$WORKDIR/out" 2>"$WORKDIR/err"
    RC=$?
}

reset_stub
children execute-x.o-a
child_deferred work-on-t-core-2 "$REASON2"
run_child local "" work-on-t-core-1 work-on-t-core-2
expect "--child: a named child deferred, no record: holds" 1
if grep -q 'workflows' "$STUB/koto.calls"; then
    fail "--child still listed the session's children: $(cat "$STUB/koto.calls")"
else
    pass "--child reads exactly the named sessions, with no child listing"
fi
body "$REASON2"
run_child local "" work-on-t-core-1 work-on-t-core-2
expect "--child: the body records the named child's reason: passes" 0

reset_stub
child_deferred execute-x.o-a "$REASON"
children execute-x.o-a
run_child local "" work-on-t-core-1
expect "--child: a listed child's deferral outside the named ones isn't read" 0
[ "$(count gh.calls)" = 0 ] && pass "--child, no named child deferred: no gh call" \
    || fail "--child, no deferral: gh calls $(count gh.calls)"

reset_stub
child_deferred work-on-t-core-1 "$REASON"
child_deferred work-on-t-core-2 "$REASON2"
run_list hosted-ci "$REASON" work-on-t-core-1 work-on-t-core-2 work-on-t-core-3
expect "--list: listed" 0
if [ "$(cat "$WORKDIR/out")" = "$(printf '%s\n%s' "$REASON" "$REASON2")" ]; then
    pass "--list prints each reason once, the run's first"
else
    fail "--list printed [$(cat "$WORKDIR/out")]"
fi
[ "$(count gh.calls)" = 0 ] && [ "$(count owned.calls)" = 0 ] \
    && pass "--list reads nothing from GitHub" \
    || fail "--list: gh calls $(count gh.calls), owned calls $(count owned.calls)"

reset_stub
run_list local "" work-on-t-core-1
expect "--list with no deferral" 0
[ -s "$WORKDIR/out" ] && fail "--list with no deferral printed [$(cat "$WORKDIR/out")]" \
    || pass "--list with no deferral prints nothing"

reset_stub
printf '3\n' > "$STUB/exists.rc"
run_list local "" work-on-t-core-1
expect "--list: a child's key check failed" 2
reset_stub
run_list hosted-ci "" work-on-t-core-1
expect "--list: hosted-ci with no reason" 2
(PATH="$BIN:$PATH" SDR_STUB="$STUB" "$GATE" --session execute-x --verification local --child) >/dev/null 2>"$WORKDIR/err"
RC=$?
expect "--child with no session name: usage" 2

# --- 2. engine --------------------------------------------------------------------------

if [ -z "$REAL_KOTO" ]; then
    echo
    echo "SKIP: koto not on PATH -- the engine cases did not run"
    echo
    echo "shared-deferral-record_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
fi

echo "--- a deferred child's session, through koto"

export HOME="$WORKDIR/home"
mkdir -p "$HOME"
REPO="$WORKDIR/repo"
mkdir -p "$REPO"
(cd "$REPO" && git init -q . && git config user.email t@example.com && git config user.name t \
    && git commit -q --allow-empty -m "chore: init") >/dev/null 2>&1 \
    || { echo "could not create the fixture repository" >&2; exit 2; }

# extract <kind> <name>: a state's block (kind states) or a variable's block
# (kind variables) from work-on.md's frontmatter.
extract() {
    awk -v sec="$1:" -v want="  $2:" '
        $0 == sec { in_sec = 1; next }
        in_sec && /^[a-z_]+:/ { in_sec = 0 }
        in_sec && $0 == want { found = 1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
        found && /^[a-z_]+:/ { exit }
        found && /^---$/ { exit }
        found && /^[[:space:]]*$/ { next }
        found { print }
    ' "$WORK_ON_TEMPLATE"
}
DEFERRED_BLOCK=$(extract states verification_deferred)
[ -n "$DEFERRED_BLOCK" ] || { echo "verification_deferred not found in $WORK_ON_TEMPLATE" >&2; exit 2; }

# The child fixture: start goes to the shipped verification_deferred, whose
# edges lead to pass_counting (here a terminal, as finalization is for a
# local run) or done_blocked.
{
    printf '%s\n' '---' 'name: shared-deferral-child' 'version: "1.0"' \
        'description: A plan-backed child that defers verification.' 'initial_state: start' 'variables:' \
        '  SHARED_BRANCH:' '    description: shared branch' '    required: false'
    extract variables VERIFICATION
    extract variables VERIFICATION_DEFERRAL_REASON
    printf '%s\n' 'states:' '  start:' '    transitions:' '      - target: verification_deferred' \
        '        when:' '          vars.VERIFICATION: hosted-ci' '      - target: finalization' \
        '        when:' '          vars.VERIFICATION: local'
    printf '%s\n' "$DEFERRED_BLOCK"
    printf '%s\n' '  finalization:' '    terminal: true' '  pass_counting:' '    terminal: true' '  done_blocked:' '    terminal: true' \
        '    failure: true' '    accepts:' '      failure_reason:' '        type: string' '---' '' '## start' '' 'Start.' '' '## verification_deferred' '' 'Stub.' \
        '' '## finalization' '' 'Stub.' '' '## pass_counting' '' 'Stub.' '' '## done_blocked' '' 'Stub.'
} > "$WORKDIR/child.md"
printf '%s\n' '---' 'name: shared-deferral-parent' 'version: "1.0"' \
    'description: The execute session the children belong to.' 'initial_state: wait' 'states:' \
    '  wait:' '    accepts:' '      go:' '        type: enum' '        values: [now]' '        required: true' \
    '    transitions:' '      - target: over' '        when:' '          go: now' \
    '  over:' '    terminal: true' '---' '' '## wait' '' 'Wait.' '' '## over' '' 'Over.' > "$WORKDIR/parent.md"

k() { (cd "$REPO" && "$REAL_KOTO" "$@"); }
k init execute-eng --template "$WORKDIR/parent.md" >"$WORKDIR/init.out" 2>&1 \
    || { fail "parent init: $(head -c 300 "$WORKDIR/init.out")"; }
k init execute-eng.o-1 --parent execute-eng --template "$WORKDIR/child.md" \
    --var SHARED_BRANCH=impl/eng --var VERIFICATION=hosted-ci \
    --var "VERIFICATION_DEFERRAL_REASON=$REASON" >"$WORKDIR/init1.out" 2>&1 \
    || fail "deferred child init: $(head -c 300 "$WORKDIR/init1.out")"
k init execute-eng.o-2 --parent execute-eng --template "$WORKDIR/child.md" \
    --var SHARED_BRANCH=impl/eng >"$WORKDIR/init2.out" 2>&1 \
    || fail "local child init: $(head -c 300 "$WORKDIR/init2.out")"
k next execute-eng.o-1 --no-cleanup >/dev/null 2>&1
k next execute-eng.o-2 --no-cleanup >/dev/null 2>&1
GOT=$(k context get execute-eng.o-1 verification_deferral 2>/dev/null)
[ "$GOT" = "$REASON" ] && pass "the deferred child recorded its reason through the shipped verification_deferred" \
    || fail "the deferred child's verification_deferral is [$GOT]"
if k context exists execute-eng.o-2 verification_deferral >/dev/null 2>&1; then
    fail "the local child recorded a deferral"
else
    pass "the local child recorded no deferral"
fi

# run_engine <session> <verification> <reason>: the gate over the real koto,
# with the gh and owned-pr.sh stand-ins (only the stub koto is left off PATH).
run_engine() {
    rm -f "$BIN/koto"
    # shellcheck disable=SC2086
    (cd "$REPO" && PATH="$BIN:$PATH" SDR_STUB="$STUB" CHECK_PR_OUTPUT_OWNED_PR="$BIN/owned-pr.sh" \
        "$GATE" --session "$1" --verification "$2" --reason "$3" -- $OWNED_ARGS) \
        >"$WORKDIR/out" 2>"$WORKDIR/err"
    RC=$?
}

reset_stub
run_engine execute-eng local ""
expect "engine: a run that didn't defer, with a deferred child, and no record: holds" 1
body "$REASON"
run_engine execute-eng local ""
expect "engine: the shared PR records the child's reason: passes" 0

k init execute-none --template "$WORKDIR/parent.md" >/dev/null 2>&1
k init execute-none.o-1 --parent execute-none --template "$WORKDIR/child.md" \
    --var SHARED_BRANCH=impl/none >/dev/null 2>&1
k next execute-none.o-1 --no-cleanup >/dev/null 2>&1
reset_stub
run_engine execute-none local ""
expect "engine: no child deferred: passes" 0
[ "$(count gh.calls)" = 0 ] && pass "engine: no child deferred: no gh call" \
    || fail "engine: no deferral, gh calls [$(cat "$STUB/gh.calls")]"

echo
echo "shared-deferral-record_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
