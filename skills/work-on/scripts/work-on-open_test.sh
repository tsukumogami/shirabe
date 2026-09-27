#!/usr/bin/env bash
# work-on-open_test.sh -- /work-on's --koto-leg entry, and the result a leg
# receives from work-on.md's terminals.
# Part of the work-on skill
#
#   engine-free (a logging koto stub on PATH):
#     no --koto-leg, a repeated one, a value that isn't <request-id>:work-on,
#     an empty or malformed request id, a bare --koto-leg, a tokens file that
#     isn't an array of strings, and the flag on a plan-backed child or a PLAN
#     path are this script's own refusals: exit 64, error=usage, no koto call,
#     and the tokens file and its directory removed
#
#   engine-backed (the real koto; skipped, loudly, when koto is absent):
#     an issue-backed run opened under --koto-leg is bound to the leg, driven
#       to done_blocked, and the leg reads back the promoted result: status
#       failure, final state done_blocked
#     a free-form run driven to validation_exit: status success, final state
#       validation_exit
#     a live session opened without the flag (the plain koto init SKILL.md
#       uses) is attached and bound by a later --koto-leg invocation: the
#       resume path; and again after the plugin moved, with PLUGIN_ROOT
#       rebound rather than refused
#     a leg pinning another ISSUE_NUMBER: koto's input check refuses, the
#       refusal is recorded on the leg, and no session is left behind
#     a retained terminal session: koto's session_terminal refusal, recorded
#       on the leg
#
# Usage: work-on-open_test.sh
# Exit codes: 0 all pass (or koto absent), 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
OPEN="$SCRIPT_DIR/work-on-open.sh"
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
KOTO_OPEN="$REPO_ROOT/scripts/koto-open.sh"
TEMPLATE="$SCRIPT_DIR/../koto-templates/work-on.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: want [$2], got [$3]"; fi; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/work-on-open-test.XXXXXX")
WORK=$(cd -P "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME"
export GIT_CEILING_DIRECTORIES="$WORK"

FIXREPO="$WORK/repo"
mkdir -p "$FIXREPO"
(cd "$FIXREPO" && git init -q . && git config user.email t@example.com && git config user.name t \
    && git commit -q --allow-empty -m init) >/dev/null 2>&1

# koto admits a variable value only inside its allowlist, and no case here runs
# a gate or action that needs the real plugin root, so a clean stand-in does.
export CLAUDE_PLUGIN_ROOT=/koto-probe

# tokens <json array> -- a tokens file in a private directory outside the work
# tree, as SKILL.md has the agent write it.
tokens() {
    local d
    d=$(cd "$FIXREPO" && bash "$KOTO_OPEN" --alloc-dir)
    printf '%s' "$1" > "$d/tokens.json"
    TOKENS="$d/tokens.json"
}

# --- engine-free: this script's own refusals -----------------------------------

STUB_BIN="$WORK/stub-bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/koto" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KOTO_STUB_LOG:?}"
exit 1
STUB
chmod +x "$STUB_BIN/koto"

own_refusal() { # own_refusal <label> <json tokens>
    : > "$WORK/stub.log"
    tokens "$2"
    OUT=$(cd "$FIXREPO" && KOTO_STUB_LOG="$WORK/stub.log" PATH="$STUB_BIN:$PATH" \
        bash "$OPEN" --workflow issue_7 --var ISSUE_NUMBER=7 --var ARTIFACT_PREFIX=issue_7 "$TOKENS" 2>/dev/null)
    RC=$?
    if [ "$RC" -eq 64 ] && [ "$OUT" = "error=usage" ] && [ ! -s "$WORK/stub.log" ] && [ ! -e "$(dirname "$TOKENS")" ]; then
        pass "own refusal: $1 (exit 64, no koto call, tokens file and its directory removed)"
    else
        fail "own refusal: $1: exit $RC, out [$OUT], koto calls [$(cat "$WORK/stub.log")]"
    fi
}
own_refusal "no --koto-leg" '["7"]'
own_refusal "--koto-leg with no colon" '["7","--koto-leg=abc"]'
own_refusal "--koto-leg naming another leg" '["7","--koto-leg=req1:execute"]'
own_refusal "--koto-leg with an empty request id" '["7","--koto-leg=:work-on"]'
own_refusal "--koto-leg with an uppercase request id" '["7","--koto-leg=REQ:work-on"]'
own_refusal "a bare --koto-leg" '["7","--koto-leg"]'
own_refusal "--koto-leg given twice" '["7","--koto-leg=r1:work-on","--koto-leg","r2:work-on"]'
own_refusal "a tokens file that is not an array of strings" '{"leg":"r1:work-on"}'
own_refusal "--koto-leg on a plan-backed child" '["--","plan-backed","github","7","--koto-leg=r1:work-on"]'
own_refusal "--koto-leg on a PLAN path" '["docs/plans/PLAN-x.md","--koto-leg=r1:work-on"]'
printf -- '---\nschema: plan/v1\n---\n# a plan\n' > "$FIXREPO/roadmap-plan.md"
own_refusal "--koto-leg on a .md file with plan/v1 frontmatter" '["roadmap-plan.md","--koto-leg=r1:work-on"]'

: > "$WORK/stub.log"
OUT=$(cd "$FIXREPO" && KOTO_STUB_LOG="$WORK/stub.log" PATH="$STUB_BIN:$PATH" \
    bash "$OPEN" --workflow issue_7 "$WORK/missing.json" 2>/dev/null)
[ $? -eq 64 ] && [ ! -s "$WORK/stub.log" ] && pass "own refusal: a missing tokens file" \
    || fail "missing tokens file: out [$OUT]"

# --- engine-backed ------------------------------------------------------------

if ! command -v koto >/dev/null 2>&1 || ! koto init --help 2>/dev/null | grep -q -- '--koto-leg'; then
    echo
    echo "SKIP: no koto with --koto-leg on PATH -- the engine-backed cases did not run"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
fi

k() { (cd "$FIXREPO" && koto "$@"); }
state_of() { k status "$1" 2>/dev/null | jq -r '.current_state // "none"'; }
leg() { k request get "$1" 2>/dev/null | jq -c ".legs[\"work-on\"]$2"; }
new_request() { # new_request <inputs json>
    k request create --with-data "$(jq -nc --argjson i "$1" '{legs: [{name: "work-on", role: "work-on", template: "work-on.md", inputs: $i}]}')" \
        --requested-by test --coordinator-of-record test | jq -r '.request_id'
}
run_open() { # run_open <workflow> <json tokens> [--var ...]
    local wf="$1" t="$2"
    shift 2
    tokens "$t"
    OUT=$(cd "$FIXREPO" && bash "$OPEN" --workflow "$wf" "$@" "$TOKENS" 2>"$WORK/stderr")
    RC=$?
    ERR=$(cat "$WORK/stderr")
}
tick() { k next "$@" --no-cleanup >/dev/null 2>&1; }

# An issue-backed run, bound, driven to done_blocked.
REQ=$(new_request '{"ISSUE_NUMBER":"7","ARTIFACT_PREFIX":"issue_7"}')
run_open issue_7 "[\"7\",\"--koto-leg=$REQ:work-on\"]" --var ISSUE_NUMBER=7 --var ARTIFACT_PREFIX=issue_7
eq "issue-backed under --koto-leg: exit 0" 0 "$RC"
case "$OUT" in *opened=new*session=issue_7*) pass "prints opened=new and session=issue_7" ;; *) fail "open output: [$OUT] [$ERR]" ;; esac
eq "the leg is bound to issue_7" '"issue_7"' "$(leg "$REQ" .bound_child)"
eq "the tokens file is removed" "" "$(ls "$(dirname "$TOKENS")" 2>/dev/null)"
tick issue_7 --with-data '{"mode":"issue_backed","issue_number":"7"}'
tick issue_7 --with-data '{"status":"blocked","detail":"issue unreachable"}'
eq "the run ends at done_blocked" done_blocked "$(state_of issue_7)"
eq "the leg's result was promoted" '"promoted"' "$(leg "$REQ" .result_source)"
eq "the leg records the terminal state" '"done_blocked"' "$(leg "$REQ" .result_final_state)"
eq "the leg's status is failure" '"failure"' "$(leg "$REQ" .result.status)"

# A free-form run, driven to validation_exit.
REQ=$(new_request '{}')
run_open task_ff "[\"tidy notes.md\",\"--koto-leg\",\"$REQ:work-on\"]" --var ARTIFACT_PREFIX=task_ff
eq "free-form under --koto-leg: exit 0" 0 "$RC"
tick task_ff --with-data '{"mode":"free_form","task_description":"do a thing"}'
tick task_ff --with-data '{"verdict":"exit","rationale":"not needed"}'
eq "the run ends at validation_exit" validation_exit "$(state_of task_ff)"
eq "the leg records the terminal state" '"validation_exit"' "$(leg "$REQ" .result_final_state)"
eq "the leg's status is success" '"success"' "$(leg "$REQ" .result.status)"

# Resume: a live session opened the plain way is attached and bound.
k init issue_8 --template "$TEMPLATE" --var ISSUE_NUMBER=8 --var ARTIFACT_PREFIX=issue_8 --var PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT" >/dev/null 2>&1
tick issue_8 --with-data '{"mode":"issue_backed","issue_number":"8"}'
REQ=$(new_request '{"ISSUE_NUMBER":"8","ARTIFACT_PREFIX":"issue_8"}')
run_open issue_8 "[\"8\",\"--koto-leg=$REQ:work-on\"]" --var ISSUE_NUMBER=8 --var ARTIFACT_PREFIX=issue_8
eq "a live session under --koto-leg: exit 0" 0 "$RC"
case "$OUT" in *opened=attached*) pass "the live session is attached" ;; *) fail "resume output: [$OUT] [$ERR]" ;; esac
eq "and stays where it was" context_injection "$(state_of issue_8)"
eq "the attached session is bound to the leg" '"issue_8"' "$(leg "$REQ" .bound_child)"

# A resume after the plugin moved: PLUGIN_ROOT is rebind, so the attach
# re-applies the new path instead of refusing the changed value.
k init issue_10 --template "$TEMPLATE" --var ISSUE_NUMBER=10 --var ARTIFACT_PREFIX=issue_10 --var PLUGIN_ROOT=/koto-probe-old >/dev/null 2>&1
REQ=$(new_request '{"ISSUE_NUMBER":"10"}')
run_open issue_10 "[\"10\",\"--koto-leg=$REQ:work-on\"]" --var ISSUE_NUMBER=10 --var ARTIFACT_PREFIX=issue_10
eq "a resume after a plugin move: exit 0" 0 "$RC"
case "$OUT" in *opened=attached*PLUGIN_ROOT*) pass "attached, with PLUGIN_ROOT rebound" ;; *) fail "plugin-move output: [$OUT] [$ERR]" ;; esac
eq "the moved session is bound to the leg" '"issue_10"' "$(leg "$REQ" .bound_child)"

# A leg pinning another issue: refused, recorded, no session.
REQ=$(new_request '{"ISSUE_NUMBER":"99"}')
run_open issue_9 "[\"9\",\"--koto-leg=$REQ:work-on\"]" --var ISSUE_NUMBER=9 --var ARTIFACT_PREFIX=issue_9
eq "a leg pinning another ISSUE_NUMBER: exit 2" 2 "$RC"
case "$OUT" in refused=*) pass "prints refused=" ;; *) fail "mismatch output: [$OUT]" ;; esac
eq "the refusal is recorded on the leg" '"refused"' "$(leg "$REQ" .result_source)"
eq "the recorded outcome is refused" '"refused"' "$(leg "$REQ" .result.payload.outcome)"
eq "the recorded reason" '"input-mismatch"' "$(leg "$REQ" .result.payload.reason)"
eq "no session is left behind" none "$(state_of issue_9)"

# A retained terminal session: session_terminal, recorded on the leg.
REQ=$(new_request '{"ISSUE_NUMBER":"7"}')
run_open issue_7 "[\"7\",\"--koto-leg=$REQ:work-on\"]" --var ISSUE_NUMBER=7 --var ARTIFACT_PREFIX=issue_7
eq "a terminal session under --koto-leg: exit 2" 2 "$RC"
eq "koto's refusal code" "refused=session_terminal" "$OUT"
eq "the refusal is recorded on the leg" '"refused"' "$(leg "$REQ" .result_source)"
eq "the recorded reason" '"session-terminal"' "$(leg "$REQ" .result.payload.reason)"
eq "the terminal session is untouched" done_blocked "$(state_of issue_7)"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
