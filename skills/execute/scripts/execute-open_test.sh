#!/usr/bin/env bash
# execute-open_test.sh — /execute's koto entry: every invocation's own flags,
# and koto as the only judge of them
# Part of the execute skill
#
# execute-open.sh maps an invocation's tokens to variable pairs with jq and
# enters `execute-<slug>` through koto-open.sh with --attach-live
# --replace-terminal. These cases pin what reaches koto and what koto decides:
#
#   engine-free (a logging koto stub on PATH):
#     a malformed --koto-leg, a leg other than `execute`, a repeated
#     --koto-leg, and an unreadable tokens file are this script's own refusals:
#     exit 64 and no koto call
#
#   engine-backed (the real koto; skipped, loudly, when koto is absent):
#     a fresh run: MERGE=false, PAUSE_BEFORE_FINALIZE=true (interactive)
#     --merge --auto: MERGE=true, PAUSE_BEFORE_FINALIZE=false
#     the repository's `## Execution Mode: auto` header: PAUSE=false
#     a repeated --merge: koto's duplicate_var, exit 2, no session,
#       outcome=error step=execute:refused
#     --merge=yes: koto's invalid_var, exit 2, no session
#     both mode flags: duplicate_var on PAUSE_BEFORE_FINALIZE
#     a slug outside the pattern: invalid_var on PLAN_SLUG, no session
#     a live session resumed with --merge: attached, MERGE rebound to true,
#       and resumed again without it: rebound back to false
#     a live session from another template: template_mismatch, the session
#       untouched and its MERGE unchanged
#     under --koto-leg: that refusal recorded on the leg with source refused;
#       an accepted run bound to the leg
#     a retained paused_for_review session: replaced, and the resume passes
#       PAUSE_BEFORE_FINALIZE=false
#
# koto status does not print a session's variables, so the effective value is
# read from the session's own log: the init event's variables with every
# variables_rebound event applied in order.
#
# Usage: execute-open_test.sh
# Exit codes: 0 all pass (or koto absent), 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
OPEN="$SCRIPT_DIR/execute-open.sh"
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
KOTO_OPEN="$REPO_ROOT/scripts/koto-open.sh"
TEMPLATE="$SCRIPT_DIR/../koto-templates/execute.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/execute-open-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME"

FIXREPO="$WORK/repo"
mkdir -p "$FIXREPO"
(cd "$FIXREPO" && git init -q . && git config user.email t@example.com && git config user.name t \
    && git commit -q --allow-empty -m init) >/dev/null 2>&1

# The plugin root is a stand-in: no case here ticks, so no action runs, and a
# checkout path outside koto's --var allowlist can't get in the way.
export CLAUDE_PLUGIN_ROOT=/koto-probe

# tokens <json array> — a tokens file in a private directory outside the work
# tree, as SKILL.md has the agent write it.
tokens() {
    local d
    d=$(cd "$FIXREPO" && bash "$KOTO_OPEN" --alloc-dir)
    printf '%s' "$1" > "$d/tokens.json"
    TOKENS="$d/tokens.json"
}

run_open() { # run_open <json array> [env...]
    tokens "$1"
    shift
    OUT=$(cd "$FIXREPO" && env "$@" bash "$OPEN" "$TOKENS" 2>"$WORK/stderr")
    RC=$?
    ERR=$(cat "$WORK/stderr")
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
    OUT=$(cd "$FIXREPO" && KOTO_STUB_LOG="$WORK/stub.log" PATH="$STUB_BIN:$PATH" bash "$OPEN" "$TOKENS" 2>/dev/null)
    RC=$?
    if [ "$RC" -eq 64 ] && [ ! -s "$WORK/stub.log" ] && [ ! -e "$TOKENS" ]; then
        pass "own refusal: $1 (exit 64, no koto call, tokens file removed)"
    else
        fail "own refusal: $1: exit $RC, koto calls [$(cat "$WORK/stub.log")], out [$OUT]"
    fi
}
own_refusal "--koto-leg with no colon" '["docs/plans/PLAN-t.md","--koto-leg=abc"]'
own_refusal "--koto-leg naming another leg" '["docs/plans/PLAN-t.md","--koto-leg=req1:scope"]'
own_refusal "--koto-leg with an empty request id" '["docs/plans/PLAN-t.md","--koto-leg=:execute"]'
own_refusal "--koto-leg given twice" '["docs/plans/PLAN-t.md","--koto-leg=r1:execute","--koto-leg","r2:execute"]'
own_refusal "a tokens file that is not an array of strings" '{"plan":"x"}'

: > "$WORK/stub.log"
OUT=$(cd "$FIXREPO" && KOTO_STUB_LOG="$WORK/stub.log" PATH="$STUB_BIN:$PATH" bash "$OPEN" "$WORK/missing.json" 2>/dev/null)
[ $? -eq 64 ] && [ ! -s "$WORK/stub.log" ] && pass "own refusal: a missing tokens file" \
    || fail "missing tokens file"

# --- engine-backed ------------------------------------------------------------

if ! command -v koto >/dev/null 2>&1; then
    echo
    echo "SKIP: koto not on PATH -- the engine-backed cases did not run"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
fi

k() { (cd "$FIXREPO" && koto "$@"); }

# session_var <session> <VAR> — the variable's effective value from the log.
session_var() {
    local dir
    dir=$(k session dir "$1" 2>/dev/null) || { echo "<no session>"; return; }
    cat "$dir"/*.state.jsonl 2>/dev/null | jq -rs --arg v "$2" '
        reduce (.[] | select(.type == "workflow_initialized" or .type == "variables_rebound")) as $e
            ({}; . + ($e.payload.variables // {})) | .[$v] // "<unset>"'
}
exists() { k status "$1" >/dev/null 2>&1; }
line() { printf '%s\n' "$OUT" | grep -qx "$1"; }

# A fresh run, no flags.
run_open '["docs/plans/PLAN-fresh.md"]'
if [ "$RC" -eq 0 ] && line 'opened=new' && line 'session=execute-fresh' \
    && [ "$(session_var execute-fresh MERGE)" = false ] \
    && [ "$(session_var execute-fresh PAUSE_BEFORE_FINALIZE)" = true ]; then
    pass "a fresh run: opened=new, MERGE=false, PAUSE_BEFORE_FINALIZE=true"
else
    fail "fresh: exit $RC, out [$OUT], MERGE [$(session_var execute-fresh MERGE)]; $ERR"
fi
if [ "$(session_var execute-fresh PLUGIN_ROOT)" = /koto-probe ] && [ "$(session_var execute-fresh PLAN_SLUG)" = fresh ]; then
    pass "PLUGIN_ROOT comes from CLAUDE_PLUGIN_ROOT and PLAN_SLUG from the PLAN's basename"
else
    fail "vars: PLUGIN_ROOT [$(session_var execute-fresh PLUGIN_ROOT)], PLAN_SLUG [$(session_var execute-fresh PLAN_SLUG)]"
fi

run_open '["docs/plans/PLAN-merging.md","--merge","--auto"]'
if [ "$RC" -eq 0 ] && [ "$(session_var execute-merging MERGE)" = true ] \
    && [ "$(session_var execute-merging PAUSE_BEFORE_FINALIZE)" = false ]; then
    pass "--merge --auto: MERGE=true, PAUSE_BEFORE_FINALIZE=false"
else
    fail "--merge --auto: exit $RC, out [$OUT]; $ERR"
fi

# The repository's own header, when no mode flag is given.
printf '# x\n\n## Execution Mode: auto\n' > "$FIXREPO/CLAUDE.md"
run_open '["docs/plans/PLAN-headered.md"]'
rm -f "$FIXREPO/CLAUDE.md"
if [ "$RC" -eq 0 ] && [ "$(session_var execute-headered PAUSE_BEFORE_FINALIZE)" = false ]; then
    pass "## Execution Mode: auto with no mode flag: PAUSE_BEFORE_FINALIZE=false"
else
    fail "header mode: [$(session_var execute-headered PAUSE_BEFORE_FINALIZE)]"
fi

# koto's refusals: exit 2, no session, and the refused exit lines.
refusal() { # refusal <label> <tokens> <code> <session that must not exist>
    run_open "$2"
    if [ "$RC" -eq 2 ] && line "refused=$3" && line 'outcome=error' && line 'step=execute:refused' \
        && ! exists "$4"; then
        pass "$1: koto's $3, exit 2, no session, outcome=error step=execute:refused"
    else
        fail "$1: exit $RC, out [$OUT], session exists: $(exists "$4" && echo yes || echo no); $ERR"
    fi
}
refusal "a repeated --merge" '["docs/plans/PLAN-dup.md","--merge","--merge"]' duplicate_var execute-dup
refusal "--merge=yes" '["docs/plans/PLAN-yes.md","--merge=yes"]' invalid_var execute-yes
refusal "both mode flags" '["docs/plans/PLAN-modes.md","--auto","--interactive"]' duplicate_var execute-modes
refusal "a slug outside ^[a-z0-9-]+\$" '["docs/plans/PLAN-Bad_Slug.md"]' invalid_var execute-unnamed
run_open '["docs/plans/PLAN-yes.md","--merge=yes"]'
if printf '%s' "$ERR" | grep -q 'MERGE'; then
    pass "the invalid_var wording names the variable"
else
    fail "invalid_var wording: [$ERR]"
fi

# A live session resumed with, then without, --merge.
run_open '["docs/plans/PLAN-fresh.md","--merge"]'
if [ "$RC" -eq 0 ] && line 'opened=attached' && [ "$(session_var execute-fresh MERGE)" = true ]; then
    pass "resumed with --merge: attached, and MERGE is rebound to true"
else
    fail "resume with --merge: out [$OUT], MERGE [$(session_var execute-fresh MERGE)]; $ERR"
fi
run_open '["docs/plans/PLAN-fresh.md"]'
if [ "$RC" -eq 0 ] && line 'opened=attached' && [ "$(session_var execute-fresh MERGE)" = false ]; then
    pass "resumed without --merge: MERGE is rebound back to false, never inherited"
else
    fail "resume without --merge: MERGE [$(session_var execute-fresh MERGE)]"
fi

# A live session from another template: refused at attach, untouched.
cat > "$WORK/other.md" <<'OTHER'
---
name: other
version: "1.0"
description: a live session under the execute-<slug> name from another template
initial_state: wait
variables:
  PLAN_DOC:
    required: true
  PLAN_SLUG:
    required: true
  PLUGIN_ROOT:
    required: true
  PAUSE_BEFORE_FINALIZE:
    default: "false"
    rebind: true
  MERGE:
    default: "false"
    rebind: true
states:
  wait:
    accepts:
      go:
        type: enum
        values: [x]
    transitions:
      - target: fin
        when:
          go: x
  fin:
    terminal: true
---
## wait
Waiting.
## fin
Done.
OTHER
k init execute-other --template "$WORK/other.md" --var PLAN_DOC=docs/plans/PLAN-other.md \
    --var PLAN_SLUG=other --var PLUGIN_ROOT=/koto-probe --var MERGE=false >/dev/null 2>&1
LOG_BEFORE=$(cat "$(k session dir execute-other)"/*.state.jsonl | wc -l | tr -d ' ')
refusal "a live session from another template" '["docs/plans/PLAN-other.md","--merge"]' template_mismatch execute-nonexistent
LOG_AFTER=$(cat "$(k session dir execute-other)"/*.state.jsonl | wc -l | tr -d ' ')
if [ "$(session_var execute-other MERGE)" = false ] && [ "$LOG_BEFORE" = "$LOG_AFTER" ] \
    && [ "$(k status execute-other | jq -r .current_state)" = wait ]; then
    pass "the other template's session is untouched: same state, same log, MERGE still false"
else
    fail "other session changed: MERGE [$(session_var execute-other MERGE)], log $LOG_BEFORE -> $LOG_AFTER"
fi

# Under --koto-leg: the refusal is recorded on the leg by koto.
REQ=$(k request create --with-data '{"legs":[{"name":"execute","role":"execute","template":"execute.md","inputs":{}}]}' \
    --requested-by execute-open-test --coordinator-of-record execute-open-test 2>/dev/null \
    | jq -r 'if type == "object" then (.id // .request_id // .request // "") else . end' 2>/dev/null)
if [ -z "$REQ" ] || [ "$REQ" = null ]; then
    fail "koto request create printed no request id"
else
    run_open '["docs/plans/PLAN-other.md","--merge","--koto-leg='"$REQ"':execute"]'
    SOURCE=$(k request get "$REQ" 2>/dev/null | jq -r '[.. | objects | select(has("result_source")) | .result_source][0] // ""')
    if [ "$RC" -eq 2 ] && line 'refused=template_mismatch' && [ "$SOURCE" = refused ] \
        && [ "$(session_var execute-other MERGE)" = false ]; then
        pass "under --koto-leg the refusal is recorded on the leg (source refused), MERGE unchanged"
    else
        fail "--koto-leg refusal: exit $RC, out [$OUT], leg source [$SOURCE]; $(k request get "$REQ" 2>&1 | head -c 600)"
    fi
fi

REQ2=$(k request create --with-data '{"legs":[{"name":"execute","role":"execute","template":"execute.md","inputs":{}}]}' \
    --requested-by execute-open-test --coordinator-of-record execute-open-test 2>/dev/null \
    | jq -r 'if type == "object" then (.id // .request_id // .request // "") else . end' 2>/dev/null)
run_open '["docs/plans/PLAN-legged.md","--koto-leg='"$REQ2"':execute"]'
if [ "$RC" -eq 0 ] && line 'opened=new' && printf '%s\n' "$OUT" | grep -q '^leg='; then
    pass "an accepted run under --koto-leg is bound to the leg"
else
    fail "--koto-leg accepted: exit $RC, out [$OUT]; $ERR"
fi

# A retained paused_for_review session: replaced, and resumed as the finalize
# invocation.
run_open '["docs/plans/PLAN-paused.md"]'
for t in orchestrator_setup settled_branch_record drift_facts worktree_sync worktree_discipline_check \
         spawn_and_await pr_finalization paused_for_review; do
    k next execute-paused --to "$t" --rationale probe --no-cleanup >/dev/null 2>&1
done
if [ "$(k status execute-paused | jq -r .current_state)" = paused_for_review ]; then
    run_open '["docs/plans/PLAN-paused.md"]'
    if [ "$RC" -eq 0 ] && line 'opened=replaced' && line 'replaced_state=paused_for_review' \
        && [ "$(session_var execute-paused PAUSE_BEFORE_FINALIZE)" = false ]; then
        pass "a retained pause is replaced, and the resume passes PAUSE_BEFORE_FINALIZE=false"
    else
        fail "paused resume: out [$OUT], PAUSE [$(session_var execute-paused PAUSE_BEFORE_FINALIZE)]; $ERR"
    fi
else
    fail "could not walk execute-paused to paused_for_review"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
