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
#     a multi-pr PLAN: error=multi-pr, exit 64, no koto call, /work-on named;
#     a single-pr PLAN is not refused and reaches koto
#     the pairs a stub koto is handed: without the review-level flags exactly
#     PLAN_DOC, PLAN_SLUG, PLUGIN_ROOT, MERGE and PAUSE_BEFORE_FINALIZE, as
#     before the flags existed; --review-floor= and --review-ceiling= add one
#     REVIEW_FLOOR or REVIEW_CEILING pair per occurrence
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
#     --review-floor=standard --review-ceiling=full: both variables set on
#       the session; resumed without them, both rebound to empty, never
#       inherited, like MERGE; --review-floor=medium: invalid_var, no session;
#       a repeated --review-ceiling: duplicate_var; a coordinated PLAN takes
#       the bound too
#     a coordinated PLAN: execute-coordinated.md under the same execute-<slug>
#       name; on a live execute.md session koto's template_mismatch (session
#       unchanged, outcome=error step=execute:refused, recorded on the leg
#       under --koto-leg); a retained terminal execute.md session replaced
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

# A multi-pr PLAN runs through /work-on: refused before any koto call, naming
# /work-on as the entry point.
mkdir -p "$FIXREPO/docs/plans"
printf -- '---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\n---\n\n# PLAN: multi\n' \
    > "$FIXREPO/docs/plans/PLAN-multi.md"
: > "$WORK/stub.log"
tokens '["docs/plans/PLAN-multi.md","--auto","--koto-leg=req1:execute"]'
OUT=$(cd "$FIXREPO" && KOTO_STUB_LOG="$WORK/stub.log" PATH="$STUB_BIN:$PATH" bash "$OPEN" "$TOKENS" 2>"$WORK/stderr")
RC=$?
if [ "$RC" -eq 64 ] && [ "$OUT" = "error=multi-pr" ] && [ ! -s "$WORK/stub.log" ] && [ ! -e "$TOKENS" ] \
    && grep -q '/work-on docs/plans/PLAN-multi.md' "$WORK/stderr"; then
    pass "a multi-pr PLAN: error=multi-pr, exit 64, no koto call, /work-on named, tokens file removed"
else
    fail "multi-pr PLAN: exit $RC, out [$OUT], koto calls [$(cat "$WORK/stub.log")], stderr [$(cat "$WORK/stderr")]"
fi
# The control: the same PLAN at single-pr is not refused here and reaches koto.
printf -- '---\nschema: plan/v1\nstatus: Active\nexecution_mode: single-pr\n---\n\n# PLAN: single\n' \
    > "$FIXREPO/docs/plans/PLAN-single.md"
: > "$WORK/stub.log"
tokens '["docs/plans/PLAN-single.md"]'
OUT=$(cd "$FIXREPO" && KOTO_STUB_LOG="$WORK/stub.log" PATH="$STUB_BIN:$PATH" bash "$OPEN" "$TOKENS" 2>/dev/null)
if [ "$OUT" != "error=multi-pr" ] && grep -q 'execute-single' "$WORK/stub.log"; then
    pass "a single-pr PLAN is not refused as multi-pr and reaches koto"
else
    fail "single-pr control: out [$OUT], koto calls [$(cat "$WORK/stub.log")]"
fi
rm -f "$FIXREPO/docs/plans/PLAN-multi.md" "$FIXREPO/docs/plans/PLAN-single.md"

: > "$WORK/stub.log"
OUT=$(cd "$FIXREPO" && KOTO_STUB_LOG="$WORK/stub.log" PATH="$STUB_BIN:$PATH" bash "$OPEN" "$WORK/missing.json" 2>/dev/null)
[ $? -eq 64 ] && [ ! -s "$WORK/stub.log" ] && pass "own refusal: a missing tokens file" \
    || fail "missing tokens file"

# The pairs the tokens become, read from a stub that keeps a copy of the vars
# file koto would have been handed (koto-open.sh removes the original).
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
    (cd "$FIXREPO" && KOTO_STUB_VARS="$WORK/vars.json" PATH="$PAIRS_BIN:$PATH" bash "$OPEN" "$TOKENS" >/dev/null 2>&1)
}
pairs_eq() { # pairs_eq <label> <want> <jq filter>
    local got
    got=$(jq -c "$3" "$WORK/vars.json" 2>/dev/null)
    if [ "$got" = "$2" ]; then pass "$1"; else fail "$1: want [$2], got [$got]"; fi
}
pairs_of '["docs/plans/PLAN-t.md","--merge"]'
pairs_eq "no review-level flags: the pairs are the ones before the flags existed" \
    '["PLAN_DOC","PLAN_SLUG","PLUGIN_ROOT","MERGE","PAUSE_BEFORE_FINALIZE"]' 'map(.[0])'
pairs_of '["docs/plans/PLAN-t.md","--review-floor=standard","--review-ceiling=full"]'
pairs_eq "--review-floor=standard --review-ceiling=full: one pair each" \
    '[["REVIEW_FLOOR","standard"],["REVIEW_CEILING","full"]]' 'map(select(.[0] | startswith("REVIEW_")))'
pairs_of '["docs/plans/PLAN-t.md","--review-ceiling=light","--review-ceiling=full","--review-floor"]'
pairs_eq "a repeat is two pairs and a bare flag its literal token, both left to koto" \
    '[["REVIEW_FLOOR","--review-floor"],["REVIEW_CEILING","light"],["REVIEW_CEILING","full"]]' \
    'map(select(.[0] | startswith("REVIEW_")))'

# --- engine-backed ------------------------------------------------------------

if ! command -v koto >/dev/null 2>&1; then
    echo
    echo "SKIP: koto not on PATH -- the engine-backed cases did not run"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
fi

k() { (cd "$FIXREPO" && koto "$@"); }

# record_write_set <session> — write the `repos` record write_set_record's
# script would have made, so repos_recorded is satisfied by its real input. The
# fixture has no origin remote for the script to read, so the value is a fixed
# owner/repo inside the gate's pattern.
record_write_set() { printf 'o/r' | k context add "$1" repos >/dev/null 2>&1; }

# The walks to paused_for_review hop out of pr_finalization, whose owned-PR
# lookup (final_owned_pr) is overridable: false, so koto runs it on the hop
# and refuses the hop unless it answers 0. /koto-probe has no scripts to run,
# so those two sessions are opened under a stand-in plugin root whose lookup
# answers one owned PR; nothing else on the walk runs a script.
WALK_ROOT="$WORK/walk-plugin"
mkdir -p "$WALK_ROOT/skills/work-on/scripts" "$WALK_ROOT/skills/execute/scripts"
printf '#!/usr/bin/env bash\necho https://github.com/o/r/pull/1\n' > "$WALK_ROOT/skills/work-on/scripts/check-pr-output.sh"
printf '#!/usr/bin/env bash\necho 00112233445566778899aabbccddeeff\n' > "$WALK_ROOT/skills/execute/scripts/run-id.sh"
chmod +x "$WALK_ROOT/skills/work-on/scripts/check-pr-output.sh" "$WALK_ROOT/skills/execute/scripts/run-id.sh"

# session_var <session> <VAR> — the variable's effective value from the log.
session_var() {
    local dir
    dir=$(k session dir "$1" 2>/dev/null) || { echo "<no session>"; return; }
    cat "$dir"/*.state.jsonl 2>/dev/null | jq -rs --arg v "$2" '
        reduce (.[] | select(.type == "workflow_initialized" or .type == "variables_rebound")) as $e
            ({}; . + ($e.payload.variables // {})) | .[$v] // "<unset>"'
}
# log_len_without_reads <session> -- how many entries the session's log holds,
# reads left out. From koto's context-read logging (tsukumogami/koto#290),
# execute-open.sh's own `koto context exists` presence check appends a
# context_read to the session it probes; that records the read, not a change,
# so a session a refusal left untouched still compares equal. It fails, and
# prints nothing, when the session's log can't be found or read, so a caller
# can't compare two failed reads as equal.
log_len_without_reads() {
    local dir n
    dir=$(k session dir "$1" 2>/dev/null) && [ -n "$dir" ] || return 1
    set -- "$dir"/*.state.jsonl
    [ -f "$1" ] || return 1
    n=$(cat "$@" | jq -c 'select(.type != "context_read")' | wc -l) || return 1
    printf '%s\n' "$n" | tr -d ' '
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

# The review-level bound: set on the session when given, and, being rebind
# like MERGE, rebound to empty by a resume that doesn't pass it.
run_open '["docs/plans/PLAN-bounded.md","--review-floor=standard","--review-ceiling=full"]'
if [ "$RC" -eq 0 ] && [ "$(session_var execute-bounded REVIEW_FLOOR)" = standard ] \
    && [ "$(session_var execute-bounded REVIEW_CEILING)" = full ]; then
    pass "--review-floor=standard --review-ceiling=full: both set on the session"
else
    fail "bounded: exit $RC, floor [$(session_var execute-bounded REVIEW_FLOOR)], ceiling [$(session_var execute-bounded REVIEW_CEILING)]; $ERR"
fi
run_open '["docs/plans/PLAN-bounded.md"]'
if [ "$RC" -eq 0 ] && line 'opened=attached' && [ "$(session_var execute-bounded REVIEW_FLOOR)" = "" ] \
    && [ "$(session_var execute-bounded REVIEW_CEILING)" = "" ]; then
    pass "resumed without the bound flags: both rebound to empty, never inherited"
else
    fail "bounded resume: out [$OUT], floor [$(session_var execute-bounded REVIEW_FLOOR)], ceiling [$(session_var execute-bounded REVIEW_CEILING)]"
fi
if [ "$(session_var execute-fresh REVIEW_FLOOR)" = "<unset>" ] || [ "$(session_var execute-fresh REVIEW_FLOOR)" = "" ]; then
    pass "a run without the flags carries no review floor"
else
    fail "unbounded run: REVIEW_FLOOR [$(session_var execute-fresh REVIEW_FLOOR)]"
fi
refusal "--review-floor=medium" '["docs/plans/PLAN-medium.md","--review-floor=medium"]' invalid_var execute-medium
refusal "a repeated --review-ceiling" '["docs/plans/PLAN-twice.md","--review-ceiling=light","--review-ceiling=full"]' duplicate_var execute-twice

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
LOG_BEFORE=$(log_len_without_reads execute-other) || LOG_BEFORE="unreadable (before)"
refusal "a live session from another template" '["docs/plans/PLAN-other.md","--merge"]' template_mismatch execute-nonexistent
LOG_AFTER=$(log_len_without_reads execute-other) || LOG_AFTER="unreadable (after)"
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
run_open '["docs/plans/PLAN-paused.md"]' CLAUDE_PLUGIN_ROOT="$WALK_ROOT"
FIRST_RUN_ID=$(k context get execute-paused run_id 2>/dev/null)
if [[ $FIRST_RUN_ID =~ ^[0-9a-f]{32}$ ]]; then
    pass "an opened session carries a run identity (run_id)"
else
    fail "no run_id after open: [$FIRST_RUN_ID]"
fi
# The first hop leaves write_set_record across repos_recorded, which is
# overridable: false. From koto 0.14 (koto#257) a directed hop across such a
# gate is refused unless the gate's current result satisfies the edge, so the
# walk records the write set first, as write_set_record's own script would.
record_write_set execute-paused
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
    if [ "$(k context get execute-paused run_id 2>/dev/null)" = "$FIRST_RUN_ID" ]; then
        pass "the replacement carries the finished run's identity, so it still owns that run's PR"
    else
        fail "run_id after replacement: [$(k context get execute-paused run_id 2>/dev/null)], was [$FIRST_RUN_ID]"
    fi
else
    fail "could not walk execute-paused to paused_for_review"
fi

# --- the coordinated template ------------------------------------------------------
#
# A PLAN whose execution_mode is coordinated enters execute-coordinated.md
# under the same execute-<slug> name. A live execute.md session of that name is
# koto's template_mismatch; a retained terminal one is replaced.

coord_plan() { # coord_plan <slug>
    mkdir -p "$FIXREPO/docs/plans"
    printf -- '---\nschema: plan/v1\nstatus: Active\nexecution_mode: coordinated\ntracking_level: none\n---\n\n# PLAN: %s\n' \
        "$1" > "$FIXREPO/docs/plans/PLAN-$1.md"
}
built_from() { # built_from <session> -> the template file name the session was built from
    cat "$(k session dir "$1")"/*.state.jsonl 2>/dev/null \
        | grep -o 'execute-coordinated\.md\|koto-templates/execute\.md\|"execute\.md"' | head -1
}

coord_plan cfresh
run_open '["docs/plans/PLAN-cfresh.md","--merge"]'
if [ "$RC" -eq 0 ] && line 'opened=new' && line 'session=execute-cfresh' \
    && [ "$(built_from execute-cfresh)" = execute-coordinated.md ] \
    && [ "$(session_var execute-cfresh MERGE)" = true ] \
    && [ "$(k status execute-cfresh | jq -r .current_state)" = coord_setup ]; then
    pass "a coordinated PLAN opens execute-coordinated.md under execute-<slug>, MERGE from --merge"
else
    fail "coordinated open: exit $RC, out [$OUT], template [$(built_from execute-cfresh)]; $ERR"
fi

# A live execute.md session, then a coordinated invocation of the same topic.
run_open '["docs/plans/PLAN-mix.md"]'
[ "$(built_from execute-mix)" != execute-coordinated.md ] && line 'opened=new' \
    || fail "could not open a single-pr execute-mix session: [$OUT]"
coord_plan mix
LOG_BEFORE=$(log_len_without_reads execute-mix) || LOG_BEFORE="unreadable (before)"
STATE_BEFORE=$(k status execute-mix | jq -r .current_state)
run_open '["docs/plans/PLAN-mix.md","--merge"]'
LOG_AFTER=$(log_len_without_reads execute-mix) || LOG_AFTER="unreadable (after)"
if [ "$RC" -eq 2 ] && line 'refused=template_mismatch' && line 'outcome=error' && line 'step=execute:refused' \
    && [ "$LOG_BEFORE" = "$LOG_AFTER" ] && [ "$(k status execute-mix | jq -r .current_state)" = "$STATE_BEFORE" ] \
    && [ "$(session_var execute-mix MERGE)" = false ]; then
    pass "a coordinated invocation on a live execute.md session: template_mismatch, outcome=error step=execute:refused, session unchanged"
else
    fail "template mismatch: exit $RC, out [$OUT], log $LOG_BEFORE -> $LOG_AFTER; $ERR"
fi
if printf '%s' "$OUT" | grep -q "outcome=""refused"; then
    fail "the refusal printed the refused token after outcome="
else
    pass "the refusal never prints the refused token after outcome="
fi
REQ3=$(k request create --with-data '{"legs":[{"name":"execute","role":"execute","template":["execute.md","execute-coordinated.md"],"inputs":{}}]}' \
    --requested-by execute-open-test --coordinator-of-record execute-open-test 2>/dev/null \
    | jq -r 'if type == "object" then (.id // .request_id // .request // "") else . end' 2>/dev/null)
run_open '["docs/plans/PLAN-mix.md","--koto-leg='"$REQ3"':execute"]'
SOURCE=$(k request get "$REQ3" 2>/dev/null | jq -r '[.. | objects | select(has("result_source")) | .result_source][0] // ""')
if [ "$RC" -eq 2 ] && line 'refused=template_mismatch' && [ "$SOURCE" = refused ]; then
    pass "under --koto-leg the template mismatch is recorded on the leg (source refused)"
else
    fail "--koto-leg template mismatch: exit $RC, out [$OUT], source [$SOURCE]"
fi

# A retained terminal execute.md session is replaced by the coordinated run.
run_open '["docs/plans/PLAN-swap.md"]' CLAUDE_PLUGIN_ROOT="$WALK_ROOT"
record_write_set execute-swap
for t in orchestrator_setup settled_branch_record drift_facts worktree_sync worktree_discipline_check \
         spawn_and_await pr_finalization paused_for_review; do
    k next execute-swap --to "$t" --rationale probe --no-cleanup >/dev/null 2>&1
done
coord_plan swap
if [ "$(k status execute-swap | jq -r .current_state)" = paused_for_review ]; then
    run_open '["docs/plans/PLAN-swap.md"]'
    if [ "$RC" -eq 0 ] && line 'opened=replaced' && [ "$(built_from execute-swap)" = execute-coordinated.md ]; then
        pass "a retained terminal execute.md session is replaced by the coordinated run"
    else
        fail "replace: exit $RC, out [$OUT], template [$(built_from execute-swap)]; $ERR"
    fi
else
    fail "could not walk execute-swap to paused_for_review"
fi

# A coordinated PLAN takes the bound too.
printf -- '---\nschema: plan/v1\nstatus: Active\nexecution_mode: coordinated\n---\n\n# PLAN: cbound\n' \
    > "$FIXREPO/docs/plans/PLAN-cbound.md"
run_open '["docs/plans/PLAN-cbound.md","--review-floor=light"]'
if [ "$RC" -eq 0 ] && [ "$(built_from execute-cbound)" = execute-coordinated.md ] \
    && [ "$(session_var execute-cbound REVIEW_FLOOR)" = light ]; then
    pass "a coordinated PLAN with --review-floor=light: execute-coordinated.md, REVIEW_FLOOR=light"
else
    fail "coordinated bound: exit $RC, template [$(built_from execute-cbound)], floor [$(session_var execute-cbound REVIEW_FLOOR)]; $ERR"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
