#!/usr/bin/env bash
# verification-outside-change_test.sh -- the verdict for a local failure or
# timeout outside the change (exit 5), and every result that must keep its
# old exit.
#
# check-verification.sh --verdict exits 5 when every block-stage cause is a
# failed or timed-out command whose log attributes its failures only to files
# the change doesn't touch. Attribution needs two things in the result: a
# result-level `changed_paths` (the merge-base diff run-verification.sh
# --start selected on) and, on the command, a `failure_lines` map:
#
#     "failure_lines": {"prefix": "FAIL: ", "path_prefix": "FAIL: bash "}
#
# A failure line starts with `prefix` at column 0. It names a file only when
# it starts with `path_prefix`; the file is the text after it up to the first
# space, and must be a plain repo-relative path (no leading `/`, no `./`, no
# `..` component) that exists at the result's head. Anything else is
# unattributable and keeps today's exit. A timed-out command may have no
# failure line at all ("its log names no failure"). Runaway, not-started and
# the run-level budget (result `status: timed-out`) are never eligible.
#
# The harness builds one throwaway repository: main, and a `work` branch whose
# change touches skills/a/f.txt and skills/a/scripts/a_test.sh, with
# skills/b/scripts/b_test.sh present and untouched. Each case writes
# result.json and its command logs directly at the path
# `run-verification.sh --locate` gives for its own session, so no supervisor
# runs and nothing is timed, then runs the verdict and asserts its exit.
#
# koto: a settled verdict records verification_results.json in koto context,
# so the cases run against a stand-in on PATH that logs each write.
#
# Usage: verification-outside-change_test.sh
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

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/vocx.XXXXXX") || exit 2
WORKDIR=$(cd "$WORKDIR" && pwd -P)
cleanup() {
    [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"
    return 0
}
ktg_on_exit cleanup

export HOME="$WORKDIR/home"
export XDG_STATE_HOME="$WORKDIR/state"
mkdir -p "$HOME" "$WORKDIR/bin" "$WORKDIR/logs"
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
: > "$KOTO_STUB_STORE/log"
export PATH="$WORKDIR/bin:$PATH"

# --- the repository ------------------------------------------------------------------

REPO="$WORKDIR/repo"
mkdir -p "$REPO/skills/a/scripts" "$REPO/skills/b/scripts"
cd "$REPO" || exit 2
git init -q -b main . || exit 2
echo base > top.txt
echo base > skills/a/f.txt
printf '#!/bin/sh\nexit 0\n' > skills/a/scripts/a_test.sh
printf '#!/bin/sh\nexit 0\n' > skills/b/scripts/b_test.sh
git add -A && git commit -q -m init || exit 2
git checkout -q -b work || exit 2
echo change >> skills/a/f.txt
echo '# change' >> skills/a/scripts/a_test.sh
git commit -q -am change || exit 2

LOC=$("$START" --locate --session s-probe) || { echo "run-verification.sh --locate failed" >&2; exit 2; }
HEAD_SHA=$(printf '%s\n' "$LOC" | sed -n 1p)
MB=$(printf '%s\n' "$LOC" | sed -n 2p)
[ -n "$HEAD_SHA" ] && [ -n "$MB" ] || { echo "--locate gave no head or merge-base: [$LOC]" >&2; exit 2; }
# The merge-base diff, as run-verification.sh --start computes it.
CHANGED=$(git diff --name-only -z "$MB..HEAD" | jq -Rsc 'split("\u0000") | map(select(. != ""))')
[ "$(printf '%s' "$CHANGED" | jq -c 'sort')" = '["skills/a/f.txt","skills/a/scripts/a_test.sh"]' ] \
    || { echo "the fixture's change is not the two skills/a files: $CHANGED" >&2; exit 2; }

FL='{"prefix": "FAIL: ", "path_prefix": "FAIL: bash "}'
B_LINE="FAIL: bash skills/b/scripts/b_test.sh exited 1"
A_LINE="FAIL: bash skills/a/scripts/a_test.sh exited 1"

# --- fixtures ------------------------------------------------------------------------

# log <name> <line>...: a command log under $WORKDIR/logs; prints its path.
log() {
    local f="$WORKDIR/logs/$1.log"
    shift
    : > "$f"
    while [ $# -gt 0 ]; do
        printf '%s\n' "$1" >> "$f"
        shift
    done
    printf '%s\n' "$f"
}

# cmd <id> <kind> <log path | -> [nofl]: one command entry. <kind> is failed
# (exit 1), timed (killed at its timeout), runaway or notstarted. The entry
# carries failure_lines unless the fourth argument is `nofl`.
cmd() {
    local fl="$FL" lg=null
    [ "${4-}" = nofl ] && fl=null
    [ "$3" != - ] && lg=$(jq -cn --arg l "$3" '$l')
    jq -cn --arg id "$1" --arg kind "$2" --argjson log "$lg" --argjson fl "$fl" '
        {id: $id, argv: ["bash", "scripts/\($id).sh"], duration_secs: 1, pgid: 4242, log: $log,
         exit_status: 1, timed_out: false, runaway: false, not_started: false}
        | if $kind == "timed" then .exit_status = 143 | .timed_out = true
          elif $kind == "runaway" then .exit_status = 137 | .runaway = true
          elif $kind == "notstarted" then .exit_status = null | .not_started = true | .duration_secs = 0 | .pgid = null
          else . end
        | if $fl == null then . else .failure_lines = $fl end'
}

# result <session> <status> <detail> <commands json> [nochanged]: write the
# session's result.json at the path --locate gives, with changed_paths unless
# the fifth argument is `nochanged`.
result() {
    local res
    res=$("$START" --locate --session "$1" | sed -n 3p)
    [ -n "$res" ] || { fail "$1: --locate gave no result path"; return 1; }
    (umask 077 && mkdir -p "$(dirname "$res")")
    if [ "${5-}" = nochanged ]; then
        jq -n --arg head "$HEAD_SHA" --arg mb "$MB" --arg status "$2" --arg detail "$3" --argjson c "$4" \
            '{schema: "shirabe-verification-result/v1", head: $head, merge_base: $mb,
              status: $status, detail: $detail, commands: $c}' > "$res"
    else
        jq -n --arg head "$HEAD_SHA" --arg mb "$MB" --arg status "$2" --arg detail "$3" --argjson c "$4" \
            --argjson ch "$CHANGED" \
            '{schema: "shirabe-verification-result/v1", head: $head, merge_base: $mb,
              status: $status, detail: $detail, changed_paths: $ch, commands: $c}' > "$res"
    fi
}

# verdict <session>: one --verdict run; sets RC and OUT.
verdict() {
    OUT=$("$VERDICT" --verdict --session "$1" 2>"$WORKDIR/verdict.err")
    RC=$?
}

# expect <label> <session> <want exit>: run the verdict and check its exit.
expect() {
    verdict "$2"
    if [ "$RC" -eq "$3" ]; then
        pass "$1: verdict exit $RC"
    else
        fail "$1: verdict exit $RC, want $3"
        printf '    out: %s\n    err: %s\n' "$OUT" "$(head -c 400 "$WORKDIR/verdict.err")"
    fi
}

# finding_has <label> <rule_id> <text>: the last verdict printed a finding
# with <rule_id> whose message contains <text>.
finding_has() {
    local msgs
    msgs=$(printf '%s\n' "$OUT" | sed -n 's/^::koto-finding:://p' \
        | jq -r --arg r "$2" 'select(.rule_id == $r) | .message' 2>/dev/null)
    case "$msgs" in
        *"$3"*) pass "$1: a $2 finding says [$3]" ;;
        *) fail "$1: no $2 finding saying [$3] in [$OUT]" ;;
    esac
}

# recorded_once <label> <session>: verification_results.json was recorded in
# koto context exactly once for the session.
recorded_once() {
    local n
    n=$(grep -c -x "add $2 verification_results.json" "$KOTO_STUB_STORE/log")
    [ "$n" -eq 1 ] && pass "$1: verification_results.json recorded once" \
        || fail "$1: verification_results.json recorded $n times"
}

# --- exit 1 -----------------------------------------------------------------------------

echo "--- a failed command"

L=$(log b-only "ok: bash skills/a/scripts/a_test.sh" "$B_LINE")
result s-b-only done "" "[$(cmd check-skill failed "$L")]"
expect "a command failed only in files the change doesn't touch" s-b-only 5
finding_has "a failure outside the change" verification/command-failed "b_test.sh"
recorded_once "a failure outside the change" s-b-only

L=$(log a-only "$A_LINE" "ok: bash skills/b/scripts/b_test.sh")
result s-a-only done "" "[$(cmd check-skill failed "$L")]"
expect "a failure in a file the change touches" s-a-only 1

L=$(log a-and-b "$A_LINE" "$B_LINE")
result s-a-and-b done "" "[$(cmd check-skill failed "$L")]"
expect "failures in a touched and an untouched file" s-a-and-b 1

echo "--- a failed command the result can't attribute"

L=$(log validate "$B_LINE" "FAIL: shirabe validate docs/x.md: a finding")
result s-validate done "" "[$(cmd check-skill failed "$L")]"
expect "a FAIL: shirabe validate line names no file" s-validate 1

L=$(log no-line "ok: bash skills/b/scripts/b_test.sh" "1 passed")
result s-no-line done "" "[$(cmd check-skill failed "$L")]"
expect "a failed command whose log has no failure line" s-no-line 1

L=$(log indented "ok: bash skills/b/scripts/b_test.sh" "every FAIL line:" "  $B_LINE" "  FAIL: one case")
result s-indented done "" "[$(cmd check-skill failed "$L")]"
expect "a failed command whose log has only indented FAIL lines" s-indented 1

L=$(log dot-slash "FAIL: bash ./skills/b/scripts/b_test.sh exited 1")
result s-dot-slash done "" "[$(cmd check-skill failed "$L")]"
expect "a ./-prefixed path" s-dot-slash 1

L=$(log absolute "FAIL: bash $REPO/skills/b/scripts/b_test.sh exited 1")
result s-absolute done "" "[$(cmd check-skill failed "$L")]"
expect "an absolute path" s-absolute 1

L=$(log dotdot "FAIL: bash skills/a/../b/scripts/b_test.sh exited 1")
result s-dotdot done "" "[$(cmd check-skill failed "$L")]"
expect "a path with a .. component" s-dotdot 1

L=$(log absent "FAIL: bash skills/c/scripts/gone_test.sh exited 1")
result s-absent done "" "[$(cmd check-skill failed "$L")]"
expect "a path absent at head" s-absent 1

L=$(log no-fl "$B_LINE")
result s-no-fl done "" "[$(cmd check-skill failed "$L" nofl)]"
expect "a command with no failure_lines" s-no-fl 1

L=$(log no-changed "$B_LINE")
result s-no-changed done "" "[$(cmd check-skill failed "$L")]" nochanged
expect "a result with no changed_paths" s-no-changed 1

# --- timed out ---------------------------------------------------------------------------

echo "--- a timed-out command"

L=$(log t-ok "ok: bash skills/a/scripts/a_test.sh" "ok: bash skills/b/scripts/b_test.sh")
result s-t-ok done "" "[$(cmd check-skill timed "$L")]"
expect "a timed-out command whose log names no failure" s-t-ok 5
finding_has "a timeout with nothing failing" verification/timed-out "no failure"
recorded_once "a timeout with nothing failing" s-t-ok

L=$(log t-a "ok: bash skills/b/scripts/b_test.sh" "$A_LINE")
result s-t-a done "" "[$(cmd check-skill timed "$L")]"
expect "a timed-out command whose log names a touched file" s-t-a 4

L=$(log t-no-fl "ok: bash skills/a/scripts/a_test.sh")
result s-t-no-fl done "" "[$(cmd check-skill timed "$L" nofl)]"
expect "a timed-out command with nothing failing but no failure_lines" s-t-no-fl 4

L=$(log t-budget "ok: bash skills/a/scripts/a_test.sh")
result s-t-budget timed-out \
    "the run passed its total budget of 7200 seconds; command check-skill was stopped; 1 later command(s) were not started: cargo-test" \
    "[$(cmd check-skill timed "$L")]"
expect "a run past its total budget" s-t-budget 4

# --- mixed causes ------------------------------------------------------------------------

echo "--- an eligible failure beside other causes"

L=$(log m-run "$B_LINE")
L2=$(log m-run-2 "forked")
result s-m-runaway done "" "[$(cmd check-skill failed "$L"), $(cmd forker runaway "$L2")]"
expect "an eligible failure beside a runaway command" s-m-runaway 4

L=$(log m-ns "$B_LINE")
result s-m-notstarted done "" "[$(cmd check-skill failed "$L"), $(cmd gone notstarted -)]"
expect "an eligible failure beside a command that did not start" s-m-notstarted 4

L=$(log m-to "$B_LINE")
L2=$(log m-to-2 "ok: bash skills/a/scripts/a_test.sh")
result s-m-timeout done "" "[$(cmd check-skill failed "$L"), $(cmd slow timed "$L2")]"
expect "an eligible failure beside an eligible timeout" s-m-timeout 5
finding_has "an eligible failure beside an eligible timeout" verification/command-failed "b_test.sh"
finding_has "an eligible failure beside an eligible timeout" verification/timed-out "no failure"
recorded_once "an eligible failure beside an eligible timeout" s-m-timeout

echo
echo "verification-outside-change_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
