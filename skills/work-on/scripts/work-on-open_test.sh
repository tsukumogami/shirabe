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
#     the review-level bound: --review-floor=/--review-ceiling= tokens become
#     REVIEW_FLOOR/REVIEW_CEILING pairs, one per occurrence; without them the
#     pairs are exactly ISSUE_NUMBER, ARTIFACT_PREFIX and PLUGIN_ROOT, as
#     before the flags existed, and no REVIEW_LEVEL is passed for a session
#     with no ledger
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
#     --review-floor=medium: koto's invalid_var at init, recorded on the leg,
#       no session
#     a run opened with --review-floor=standard has a `bound` line with that
#       floor before its first `choose`, and a light choice under it is refused
#     a resume through this script of a session whose ledger records a level
#       keeps REVIEW_LEVEL at that level (an attach resets every rebind
#       variable it isn't passed), where a bare attach empties it; a resume
#       naming a different floor is koto's var_mismatch
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

# The pairs the tokens become, read from a stub that keeps a copy of the vars
# file koto would have been handed (koto-open.sh removes the original). The
# stub answers every other call (the ledger read) as an absent key.
PAIRS_BIN="$WORK/pairs-bin"
mkdir -p "$PAIRS_BIN"
cat > "$PAIRS_BIN/koto" <<'STUB'
#!/usr/bin/env bash
prev=""
for a in "$@"; do
    [ "$prev" = "--vars-file" ] && cp -- "$a" "${KOTO_STUB_VARS:?}"
    prev="$a"
done
exit 1
STUB
chmod +x "$PAIRS_BIN/koto"
pairs_of() { # pairs_of <json tokens>
    rm -f "$WORK/vars.json"
    tokens "$1"
    (cd "$FIXREPO" && KOTO_STUB_VARS="$WORK/vars.json" PATH="$PAIRS_BIN:$PATH" \
        bash "$OPEN" --workflow issue_7 --var ISSUE_NUMBER=7 --var ARTIFACT_PREFIX=issue_7 "$TOKENS" >/dev/null 2>&1)
}
pairs_of '["7","--koto-leg=r1:work-on"]'
eq "no bound flags: the pairs are the ones before the flags existed" \
    '["ISSUE_NUMBER","ARTIFACT_PREFIX","PLUGIN_ROOT"]' "$(jq -c 'map(.[0])' "$WORK/vars.json" 2>/dev/null)"
pairs_of '["7","--review-floor=standard","--review-ceiling=full","--koto-leg=r1:work-on"]'
eq "--review-floor=standard --review-ceiling=full: the bound pairs" \
    '[["REVIEW_FLOOR","standard"],["REVIEW_CEILING","full"]]' \
    "$(jq -c 'map(select(.[0] | startswith("REVIEW_")))' "$WORK/vars.json" 2>/dev/null)"
pairs_of '["7","--review-floor=light","--review-floor=full","--review-ceiling","--koto-leg=r1:work-on"]'
eq "a repeat is two pairs and a bare flag its literal token, both left to koto" \
    '[["REVIEW_FLOOR","light"],["REVIEW_FLOOR","full"],["REVIEW_CEILING","--review-ceiling"]]' \
    "$(jq -c 'map(select(.[0] | startswith("REVIEW_")))' "$WORK/vars.json" 2>/dev/null)"

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

# --- the review-level bound -----------------------------------------------------

# A floor outside the three names: koto's pattern refuses it at init, and the
# refusal is recorded on the leg.
REQ=$(new_request '{}')
run_open task_badfloor "[\"tidy\",\"--review-floor=medium\",\"--koto-leg=$REQ:work-on\"]" --var ARTIFACT_PREFIX=task_badfloor
eq "--review-floor=medium: exit 2" 2 "$RC"
eq "koto's refusal code" "refused=invalid_var" "$OUT"
eq "the refusal is recorded on the leg" '"refused"' "$(leg "$REQ" .result_source)"
eq "no session is left behind" none "$(state_of task_badfloor)"

# The cases below tick into review_level_choice, whose action runs
# review-level.sh, so PLUGIN_ROOT must reach this checkout. koto admits a
# value only inside its allowlist, so a checkout path outside it is reached
# through a symlink.
REAL_ROOT="$REPO_ROOT"
case "$REAL_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*) ln -s "$REPO_ROOT" "$WORK/plugin"; REAL_ROOT="$WORK/plugin" ;;
esac
RL="$REAL_ROOT/skills/work-on/scripts/review-level.sh"
ledger_events() { k context get "$1" review_level.jsonl 2>/dev/null | jq -r .event | tr '\n' ' ' | sed 's/ $//'; }
# session_var <session> <VAR> -- the effective value from the session's log:
# the init event's variables with every variables_rebound event applied.
session_var() {
    local dir
    dir=$(k session dir "$1" 2>/dev/null) || { echo "<no session>"; return; }
    cat "$dir"/*.state.jsonl 2>/dev/null | jq -rs --arg v "$2" '
        reduce (.[] | select(.type == "workflow_initialized" or .type == "variables_rebound")) as $e
            ({}; . + ($e.payload.variables // {})) | .[$v] // "<unset>"'
}
# to_choice <session> -- from entry to review_level_choice, as an issue-backed
# run that skips its setup states.
to_choice() {
    tick "$1" --with-data '{"mode":"issue_backed","issue_number":"42"}'
    tick "$1" --with-data '{"status":"override"}'
    tick "$1" --with-data '{"status":"override"}'
    tick "$1" --with-data '{"staleness_signal":"override"}'
    printf '# Issue\n\n## Acceptance Criteria\n\n- [ ] it works\n' | k context add "$1" context.md >/dev/null 2>&1
    printf 'plan\n' | k context add "$1" plan.md >/dev/null 2>&1
    tick "$1" --with-data '{"plan_outcome":"plan_ready"}'
}

# Opened through this script with --review-floor=standard: the bound line,
# with that floor, is in the ledger before any choice.
REQ=$(new_request '{}')
CLAUDE_PLUGIN_ROOT="$REAL_ROOT" run_open issue_42 "[\"42\",\"--review-floor=standard\",\"--koto-leg=$REQ:work-on\"]" \
    --var ISSUE_NUMBER=42 --var ARTIFACT_PREFIX=issue_42
eq "--review-floor=standard under --koto-leg: exit 0" 0 "$RC"
eq "the session's REVIEW_FLOOR" standard "$(session_var issue_42 REVIEW_FLOOR)"
to_choice issue_42
eq "plan_ready with no level waits at review_level_choice" review_level_choice "$(state_of issue_42)"
eq "the ledger holds the bound line and no choice yet" bound "$(ledger_events issue_42)"
eq "the bound line records floor standard" standard \
    "$(k context get issue_42 review_level.jsonl 2>/dev/null | jq -r 'select(.event == "bound") | .floor')"
(cd "$FIXREPO" && "$RL" set issue_42 light --reason small >/dev/null 2>&1)
eq "a light choice under the standard floor is refused" 1 "$?"
(cd "$FIXREPO" && "$RL" set issue_42 standard >/dev/null 2>&1)
eq "a standard choice is recorded" 0 "$?"
eq "the ledger reads bound, then choose" "bound choose" "$(ledger_events issue_42)"

# A resume through this script keeps the chosen level. The session is opened
# the plain way (SKILL.md's direct init, with the bound as --var), its level
# chosen, and a bare attach shows what the script guards against: the attach
# resets REVIEW_LEVEL, which isn't passed.
k init issue_43 --template "$TEMPLATE" --var ISSUE_NUMBER=43 --var ARTIFACT_PREFIX=issue_43 \
    --var PLUGIN_ROOT="$REAL_ROOT" --var REVIEW_FLOOR=standard >/dev/null 2>&1
eq "the direct init with --var REVIEW_FLOOR=standard" standard "$(session_var issue_43 REVIEW_FLOOR)"
to_choice issue_43
(cd "$FIXREPO" && "$RL" set issue_43 full >/dev/null 2>&1)
eq "the level is chosen" full "$(session_var issue_43 REVIEW_LEVEL)"
eq "review-level.sh level reads it from the ledger" full "$(cd "$FIXREPO" && "$RL" level issue_43 2>/dev/null)"
k init issue_43 --template "$TEMPLATE" --attach-live --var PLUGIN_ROOT="$REAL_ROOT" >/dev/null 2>&1
eq "control: a bare attach empties REVIEW_LEVEL" "" "$(session_var issue_43 REVIEW_LEVEL)"
(cd "$FIXREPO" && "$RL" set issue_43 full >/dev/null 2>&1)
REQ=$(new_request '{"ISSUE_NUMBER":"43"}')
CLAUDE_PLUGIN_ROOT="$REAL_ROOT" run_open issue_43 "[\"43\",\"--review-floor=standard\",\"--koto-leg=$REQ:work-on\"]" \
    --var ISSUE_NUMBER=43 --var ARTIFACT_PREFIX=issue_43
eq "a resume through work-on-open.sh: exit 0" 0 "$RC"
case "$OUT" in *opened=attached*) pass "the live session is attached" ;; *) fail "resume output: [$OUT] [$ERR]" ;; esac
eq "the resume keeps REVIEW_LEVEL at the ledger's level" full "$(session_var issue_43 REVIEW_LEVEL)"
eq "and the bound it was opened with" standard "$(session_var issue_43 REVIEW_FLOOR)"
eq "the resumed session is bound to the leg" '"issue_43"' "$(leg "$REQ" .bound_child)"
eq "and still waits where it was" review_level_choice "$(state_of issue_43)"

# The bound doesn't move inside a run: REVIEW_FLOOR isn't rebind in
# work-on.md, so a resume naming a different floor is refused.
REQ=$(new_request '{"ISSUE_NUMBER":"43"}')
CLAUDE_PLUGIN_ROOT="$REAL_ROOT" run_open issue_43 "[\"43\",\"--review-floor=full\",\"--koto-leg=$REQ:work-on\"]" \
    --var ISSUE_NUMBER=43 --var ARTIFACT_PREFIX=issue_43
eq "a resume with a different floor: exit 2" 2 "$RC"
eq "koto's refusal code" "refused=var_mismatch" "$OUT"
eq "the session keeps its floor" standard "$(session_var issue_43 REVIEW_FLOOR)"
eq "and its level" full "$(session_var issue_43 REVIEW_LEVEL)"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
