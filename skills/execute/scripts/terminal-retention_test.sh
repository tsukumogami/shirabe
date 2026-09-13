#!/usr/bin/env bash
# terminal-retention_test.sh -- the orchestrator's terminal tick keeps its record
# Part of the execute skill
#
# koto deletes a session on the tick that reaches a terminal state, and the
# deletion takes the session's `ctx/` with it. `/execute` ends at `done_blocked`
# when the chain cannot proceed and at `paused_for_review` when an interactive
# run hands a DRAFT PR back for review; both lose their context without
# `koto next --no-cleanup` (#360). The second is the worse loss -- a pause is
# solicited, and what dies with it is what a resume reads.
#
# `/execute` passes the flag unconditionally, where `/work-on` has to decide per
# run. That is sound only while an orchestrator session is always a root, so this
# harness checks the premise rather than trusting it. Case groups, in execution
# order -- deliberately not numbered, because a numbered map goes stale the first
# time a case is inserted and then misdirects the reader it was written for:
#
#   engine-free, so they also run on the bash 3.2 floor where koto is absent:
#     nothing in the corpus names execute.md as a child template (the tripwire)
#     SKILL.md and the template frontmatter both state the rule
#     every koto next command line in the template carries the flag
#     escalate still has the shape that chains
#
#   engine-backed, against the SHIPPED execute.md:
#     the blocked terminal keeps its context, and a control without the flag
#     the PAUSE terminal keeps its context, and a control
#     retention does not block the resume it exists to protect
#     the chain itself, driven in both directions on a minimal template
#
# The tripwire matters most: if a future change makes `/execute` spawnable as a
# child, the unconditional flag would withhold its result from its parent, as
# references/koto-session-retention.md documents, and that case says so before
# it ships.
#
# The pause cases walk the declared edges with `koto next --to`, because reaching
# pr_finalization by evidence alone would mean satisfying the children-complete
# gate with real children -- a great deal of machinery to assert something about
# the tick that LEAVES the state, not about how it was entered. Every hop is a
# declared transition; koto refuses an undeclared one, so the walk cannot drift
# from the template's own graph without failing.
#
# Usage: terminal-retention_test.sh
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the run skipped
#   1 -- one or more cases failed
#
# A missing koto exits 0 with a loud SKIP, matching settled-branch-record_test.sh:
# the Linux leg of check-execute-scripts.yml installs koto through the project
# tool manifest so the assertions genuinely run, and the macOS leg is the bash
# 3.2 floor check, where failing on absence would red the leg for a reason that
# has nothing to do with what it checks.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SKILLS_DIR=$(cd "$SKILL_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/execute.md"
SKILL_MD="$SKILL_DIR/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$TEMPLATE" ] || { echo "FAIL: template not found at $TEMPLATE" >&2; exit 1; }

REPO_ROOT=$(cd "$SKILLS_DIR/.." && pwd)
WORK_ON_TPL="skills/work-on/koto-templates/work-on.md"

# Every `koto next` inside a fenced code block, at any indentation and inside
# `$(...)`, excluding shell-comment lines. Prints "line: text". This is the one
# definition of "a tick" in this suite; both the template count and the
# orchestrator walk use it, so they cannot disagree about what they are counting.
fenced_ticks() {
    awk '
        /^[[:space:]]*```/ { inblk = !inblk; next }
        inblk && /koto next / {
            t = $0; sub(/^[[:space:]]+/, "", t)
            if (t ~ /^#/) next
            printf "%d: %s\n", NR, $0
        }' "$1"
}
raw_cites() { grep -oE '(skills|references)/[A-Za-z0-9_/.-]*\.md' "$1" 2>/dev/null | sort -u; }
resolve() { # $1 citation, $2 citing file (repo-relative) -> repo-relative path, or nothing
    [ -f "$REPO_ROOT/$1" ] && { echo "$1"; return; }
    case "$2" in
        skills/*) sd=$(printf '%s' "$2" | cut -d/ -f1-2)
                  [ -f "$REPO_ROOT/$sd/$1" ] && echo "$sd/$1" ;;
    esac
}

# --- the engine-free cases, which run before the koto skip -------------------
#
# The premise behind /execute's unconditional flag: nothing materializes
# execute.md as a child.
#
# Three routes, not one. `default_template` is what /execute uses for its own
# children; a per-task `template:` field overrides it per child; and a session
# started under an explicit parent makes a child of any template at all.
#
# The scan covers every markdown file under skills/, not just templates and
# SKILL.md: this repo puts `koto init` in references/phases too (see
# skills/scope/references/phases/phase-0-setup.md), so a narrower scan would
# report a guarantee it had not checked. It still cannot see a `koto init
# --parent` issued from outside this repo, which is the residual blind spot --
# the premise this case asserts is "nothing in the shirabe corpus spawns
# execute.md as a child", not "koto could not be made to".
#
# The awk drops the `path:line:` prefix before matching, or every hit inside
# execute.md would match on its own filename.
CHILD_DECLS=$(grep -rn 'default_template:\|template:\|--parent' \
        --include='*.md' "$SKILLS_DIR" 2>/dev/null \
    | grep -v '^[^:]*:[0-9]*: *#' \
    | grep -v '/evals/' \
    | awk -F: '{ line = $0; sub(/^[^:]*:[0-9]*:/, "", line); if (line ~ /execute\.md/) print $0 }')
if [ -z "$CHILD_DECLS" ]; then
    pass "nothing names execute.md as a child template, so an orchestrator session is always a root"
else
    fail "execute.md is named as a child template, so /execute can now run as a child and its unconditional --no-cleanup would block the parent's converge:
$CHILD_DECLS"
fi

if grep -q -- '--no-cleanup' "$SKILL_MD"; then
    pass "SKILL.md states the terminal-tick retention rule"
else
    fail "SKILL.md must state that the orchestrator's koto next carries --no-cleanup"
fi

# execute.md's own note. Unlike work-on.md the flag is not forbidden here, but a
# terminal-reaching `koto next` added to this template must carry it, and the
# only thing that will tell a future editor so is the note. This is the template
# half of the issue's "say why the flag is there" criterion.
if grep -q '^# *Terminal-tick retention' "$TEMPLATE"; then
    pass "execute.md's frontmatter records why the flag rides every tick and what a new terminal-reaching tick must do"
else
    fail "execute.md has no frontmatter note explaining the retention rule to a template editor"
fi

# Every koto next command line in this template must carry the flag. An earlier
# version of this suite asserted the opposite for spawn_and_await's two ticks, on
# the false premise that a state declaring `accepts` cannot be chained through.
# Counted with the same shape-aware matcher as the walk below -- fenced, any
# indentation, inside $(...) -- not a column-0 grep, which would miss an indented
# tick and report a smaller denominator than the template really has.
TEMPLATE_TICKS=$(fenced_ticks "$TEMPLATE" | grep -c .)
TEMPLATE_TICKS_FLAGGED=$(fenced_ticks "$TEMPLATE" | grep -c -- '--no-cleanup')
if [ "$TEMPLATE_TICKS" -gt 0 ] && [ "$TEMPLATE_TICKS" -eq "$TEMPLATE_TICKS_FLAGGED" ]; then
    pass "every koto next command line in execute.md carries --no-cleanup ($TEMPLATE_TICKS of $TEMPLATE_TICKS)"
else
    fail "execute.md has $TEMPLATE_TICKS koto next command lines but only $TEMPLATE_TICKS_FLAGGED carry --no-cleanup. A tick keeps advancing while the next transition needs no evidence, so a tick that looks non-terminal can still chain into one."
fi

# The orchestrator's ticks are not all in execute.md. A state directive can send
# the agent to another file for the command to run, and that command is an
# orchestrator tick exactly as much as one written inline. Counting only
# execute.md's own lines is how phase-2.5's bare intent-changing tick -- which
# chains through escalate_upstream_drift into done_blocked -- went unflagged.
#
# What this scan covers, stated exactly so nothing relies on more:
#
#   the ticks  every `koto next` inside a fenced code block, at any indentation
#              and inside `$(...)`, excluding shell-comment lines. A tick written
#              only as inline code in prose is not treated as one.
#   the files  execute.md and skills/execute/SKILL.md, then every file reachable
#              from them by citation, transitively. Citations are resolved as
#              repo-rooted first, then relative to the citing skill.
#   bounded to the files /execute's orchestrator can be sent to: /execute's own
#              tree, repo-root references/, and /work-on's reference files --
#              but NOT /work-on's phase files that work-on.md itself cites. Those
#              are the child's instructions, and their ticks are correctly bare.
#              Other skills' trees are not entered: shared references cite them
#              as examples, not as commands the orchestrator runs.
#
# A citation that resolves to nothing is not followed, and is reported.

# The child's own phase files: the /work-on phase files work-on.md sends a child to.
CHILD_PHASES=" "
for c in $(raw_cites "$REPO_ROOT/$WORK_ON_TPL"); do
    r=$(resolve "$c" "$WORK_ON_TPL")
    case "$r" in skills/work-on/references/phases/*) CHILD_PHASES="$CHILD_PHASES$r " ;; esac
done

orchestrator_reachable() { # $1 candidate -> 0 if the walk may enter it
    case "$CHILD_PHASES" in *" $1 "*) return 1 ;; esac
    case "$1" in
        references/*.md)                 return 0 ;;
        skills/execute/*)                return 0 ;;
        skills/work-on/references/*)     return 0 ;;
        *)                               return 1 ;;
    esac
}

WALK_QUEUE="skills/execute/koto-templates/execute.md skills/execute/SKILL.md"
WALK_SEEN=""
WALK_UNRESOLVED=""
WALK_SHARED=" "
while [ -n "$WALK_QUEUE" ]; do
    set -- $WALK_QUEUE; cur="$1"; shift; WALK_QUEUE="$*"
    case " $WALK_SEEN " in *" $cur "*) continue ;; esac
    WALK_SEEN="$WALK_SEEN $cur"
    for c in $(raw_cites "$REPO_ROOT/$cur"); do
        r=$(resolve "$c" "$cur")
        if [ -z "$r" ]; then WALK_UNRESOLVED="$WALK_UNRESOLVED
  $cur -> $c"; continue; fi
        # A file the orchestrator is sent to that is ALSO one of the child's phase
        # files has two readers with opposite needs. Record it; it is checked below.
        case "$CHILD_PHASES" in *" $r "*) WALK_SHARED="$WALK_SHARED$r " ;; esac
        orchestrator_reachable "$r" && WALK_QUEUE="$WALK_QUEUE $r"
    done
done

WALK_BARE=""
for f in $WALK_SEEN; do
    bare=$(fenced_ticks "$REPO_ROOT/$f" | grep -v -- '--no-cleanup')
    [ -n "$bare" ] && WALK_BARE="$WALK_BARE
$f:
$bare"
done
WALK_COUNT=$(echo $WALK_SEEN | wc -w | tr -d ' ')
if [ -z "$WALK_BARE" ]; then
    pass "every fenced koto next in the $WALK_COUNT files the orchestrator can be sent to carries --no-cleanup"
else
    fail "a file the orchestrator can be sent to carries a bare koto next -- a bare tick that chains into a terminal destroys its record:$WALK_BARE"
fi

# Sanity on the walk itself: it has to have reached the file whose miss started
# this, or a change to how citations are written has quietly shrunk it.
case " $WALK_SEEN " in
    *" skills/work-on/references/phases/phase-2.5-worktree-discipline.md "*)
        pass "the walk reaches phase-2.5, the orchestrator-only /work-on file" ;;
    *)  fail "the walk no longer reaches phase-2.5 -- citation resolution changed and the scan has shrunk" ;;
esac
# An unresolved citation fails rather than being noted. A file the orchestrator
# is told to read that the walk cannot find is a file it cannot scan -- exactly
# the hole this whole scan exists to close. The case that proved it: execute.md
# cited /work-on's phase-6-pr.md by a path relative to /work-on, inherited when
# the orchestrator was lifted out of it, so the orchestrator was sent to a file
# nothing checked.
if [ -z "$WALK_UNRESOLVED" ]; then
    pass "every citation in the orchestrator's files resolves, so nothing it is sent to escapes the scan"
else
    fail "a file the orchestrator reads cites a path that resolves to no file, so the scan cannot see it (write it repo-rooted):$WALK_UNRESOLVED"
fi

# A file read by BOTH the orchestrator and a child cannot carry a tick at all:
# the orchestrator would need it flagged and a child needs it bare, and no one
# line can be both. Resolving that by judgement fails the next person to add a
# tick there, who will not know the file has two readers -- so it is a check.
SHARED_TICKS=""
for f in $WALK_SHARED; do
    t=$(fenced_ticks "$REPO_ROOT/$f")
    [ -n "$t" ] && SHARED_TICKS="$SHARED_TICKS
$f:
$t"
done
SHARED_COUNT=$(echo $WALK_SHARED | wc -w | tr -d ' ')
if [ -z "$SHARED_TICKS" ]; then
    pass "the $SHARED_COUNT file(s) read by both the orchestrator and a child carry no koto next tick"
else
    fail "a file read by both the orchestrator and a child carries a koto next tick, which cannot be right for both (flagged for the orchestrator, bare for a child). Move the command into a file only one of them reads:$SHARED_TICKS"
fi

# The mechanism behind that rule, pinned so nobody reinstates the carve-out on
# the reasoning that was wrong the first time: a state halts an auto-advance
# chain only if it declares at least one CONDITIONAL transition. Declaring
# `accepts` halts nothing, so a state can require evidence and still be chained
# straight through to a terminal.
ESCALATE_BLOCK=$(sed -n '/^  escalate:/,/^  [a-z_]*:$/p' "$TEMPLATE")
if printf '%s' "$ESCALATE_BLOCK" | grep -q 'accepts:' \
   && printf '%s' "$ESCALATE_BLOCK" | grep -q 'target: done_blocked' \
   && ! printf '%s' "$ESCALATE_BLOCK" | grep -q 'when:'; then
    pass "escalate still declares accepts and reaches done_blocked unconditionally -- the shape that chains, which is why spawn_and_await's ticks are flagged"
else
    fail "escalate's shape changed. Re-derive whether spawn_and_await's ticks can still chain into a terminal before trusting the flag count above; do NOT conclude from 'it accepts evidence' that it cannot."
fi


skip_engine_cases() {
    echo
    echo "SKIP: $1 -- the engine-backed cases did not run"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
}

command -v koto >/dev/null 2>&1 || skip_engine_cases "koto not on PATH"
# jq skips rather than failing, matching koto. A runner with koto but no jq is
# an environment gap, not a defect in what this suite tests, and the Linux leg
# installs both so the cases genuinely run where it matters.
command -v jq >/dev/null 2>&1 || skip_engine_cases "jq not on PATH"

WORKDIR=$(mktemp -d)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# Keep every session this harness creates out of the developer's real ~/.koto.
# This suite retains sessions on purpose, so it would leave more behind than most.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"

# PLUGIN_ROOT is a fixed literal rather than this checkout's path. koto validates
# a variable's value against `^[a-zA-Z0-9._/:@ \-]*$`, and a checkout sitting
# under a directory with a `+` in it fails that -- silently, since the failure is
# on `koto init` and every later call then reports the session missing. The
# states these cases touch never read PLUGIN_ROOT, so a stand-in is honest here;
# what would not be honest is a suite whose init failed and whose assertions
# therefore proved nothing, which is why init_or_die exists.
init_orchestrator() {
    koto init "$1" --template "$TEMPLATE" \
        --var PLAN_DOC=docs/plans/PLAN-probe.md \
        --var PLAN_SLUG=probe \
        --var PLUGIN_ROOT=/koto-probe \
        --var PAUSE_BEFORE_FINALIZE=false >/dev/null 2>&1
    if ! koto status "$1" >/dev/null 2>&1; then
        echo "FAIL: koto init did not produce session '$1' -- the engine-backed cases cannot run" >&2
        koto init "$1" --template "$TEMPLATE" \
            --var PLAN_DOC=docs/plans/PLAN-probe.md \
            --var PLAN_SLUG=probe \
            --var PLUGIN_ROOT=/koto-probe \
            --var PAUSE_BEFORE_FINALIZE=false 2>&1 | tail -2 >&2
        exit 1
    fi
    printf 'the orchestrator record\n' | koto context add "$1" summary.md >/dev/null 2>&1
}

# --- the blocked terminal keeps its context ----------------------------------

init_orchestrator block_keep
koto next block_keep --with-data '{"status":"blocked","detail":"probe"}' --no-cleanup >/dev/null 2>&1
if [ "$(koto context get block_keep summary.md 2>/dev/null)" = "the orchestrator record" ]; then
    pass "an orchestrator run reaching done_blocked with the flag keeps its context"
else
    fail "an orchestrator run reaching done_blocked with the flag lost its context"
fi

# Without the control this suite would pass on a koto that had stopped cleaning
# up at all, and the flag would look load-bearing while doing nothing.
init_orchestrator block_drop
koto next block_drop --with-data '{"status":"blocked","detail":"probe"}' >/dev/null 2>&1
if koto context get block_drop summary.md >/dev/null 2>&1; then
    fail "an orchestrator run reaching done_blocked without the flag kept its context -- the control did not fire"
else
    pass "an orchestrator run reaching done_blocked without the flag loses its context (control)"
fi

# --- the pause terminal keeps its context ------------------------------------
#
# paused_for_review is a suspension, not a termination: the operator is expected
# to come back, and what a resume reads is exactly the context koto disposes of
# on arrival, because the state is still terminal: true. #360's written
# acceptance criteria cover only the blocked terminal; this is the widening, and
# it is measured here rather than inferred from koto's source.

# The declared edges from orchestrator_setup to the pause terminal. koto refuses
# a hop it cannot find in the template, so this list is checked against the real
# graph on every run -- if a future edit reroutes the pause path, the walk stops
# short and the assertions below fail rather than silently testing nothing.
PAUSE_PATH="settled_branch_record worktree_sync worktree_discipline_check spawn_and_await pr_finalization paused_for_review"

walk_to_pause() {
    # $1 session name, $2 extra flag for every hop ("" or --no-cleanup)
    local target
    for target in $PAUSE_PATH; do
        if [ -n "$2" ]; then
            koto next "$1" --to "$target" --rationale "terminal-retention probe" "$2" >/dev/null 2>&1
        else
            koto next "$1" --to "$target" --rationale "terminal-retention probe" >/dev/null 2>&1
        fi
    done
}

init_orchestrator pause_keep
walk_to_pause pause_keep --no-cleanup
PAUSE_STATE=$(koto status pause_keep 2>/dev/null | jq -r '.current_state // "gone"')
if [ "$PAUSE_STATE" != "paused_for_review" ]; then
    fail "the walk did not reach paused_for_review (stopped at '$PAUSE_STATE') -- the pause path in execute.md has changed and this case is no longer testing it"
elif [ "$(koto context get pause_keep summary.md 2>/dev/null)" = "the orchestrator record" ]; then
    pass "an orchestrator run reaching paused_for_review with the flag keeps its context"
else
    fail "an orchestrator run reaching paused_for_review with the flag lost its context"
fi

init_orchestrator pause_drop
walk_to_pause pause_drop ""
if koto context get pause_drop summary.md >/dev/null 2>&1; then
    fail "an orchestrator run reaching paused_for_review without the flag kept its context -- the control did not fire"
else
    pass "an orchestrator run reaching paused_for_review without the flag loses its context (control)"
fi

# --- retention must not block the resume it exists to protect ----------------
#
# The pause terminal is retained so a resume can read its record. But a retained
# session keeps its name, and `koto init execute-<plan-slug>` -- the only
# documented entry point for a single-pr run -- refuses a name already in use.
# So retention would break the very resume that justifies it unless the Resume
# step recognises the finished session first. These pin the signal it reads and
# the fact that reading it is non-destructive.

if [ "$(koto status pause_keep 2>/dev/null | jq -r '.is_terminal')" = "true" ]; then
    pass "the retained pause session reports is_terminal: true, the signal the Resume guard reads"
else
    fail "koto status no longer reports is_terminal: true for the retained pause session -- the Resume guard's signal is gone"
fi

if koto init pause_keep --template "$TEMPLATE" \
        --var PLAN_DOC=docs/plans/PLAN-probe.md --var PLAN_SLUG=probe \
        --var PLUGIN_ROOT=/koto-probe --var PAUSE_BEFORE_FINALIZE=false >/dev/null 2>&1; then
    fail "koto init accepted a name still held by the retained session -- re-check whether the Resume guard is still needed"
else
    pass "koto init refuses the retained session's name, which is why Resume must check before initializing"
fi

if [ "$(koto context get pause_keep summary.md 2>/dev/null)" = "the orchestrator record" ]; then
    pass "koto status and the refused init left the record intact"
else
    fail "inspecting the retained session destroyed or altered its record"
fi

if grep -q 'is_terminal' "$SKILL_MD"; then
    pass "SKILL.md's Resume step reads is_terminal (grep, not an executed agent run)"
else
    fail "SKILL.md no longer reads is_terminal on re-entry -- the Resume guard has been dropped"
fi

# --- the chain is real, not just a shape in the template --------------------
#
# escalate's shape asserted above is only worth asserting if that shape actually
# chains. This drives koto with a minimal template of exactly that shape -- a
# state declaring required evidence whose single transition to a failure
# terminal carries no `when` -- and shows one bare tick two states upstream
# landing on the terminal and taking the record with it. A stand-in rather than
# execute.md because reaching spawn_and_await for real means satisfying the
# settled-branch capture and materializing children, none of which is what this
# case is about.

cat > "$WORKDIR/chain.md" <<'CHAIN_EOF'
---
name: retention-chain-probe
version: "1.0"
description: A state with required evidence and one unconditional edge to a terminal.
initial_state: start
states:
  start:
    accepts:
      outcome:
        type: enum
        values: [ok, bad]
        required: true
    transitions:
      - target: middle
        when:
          outcome: bad
      - target: finished_ok
        when:
          outcome: ok
  middle:
    accepts:
      reason:
        type: string
        required: true
    transitions:
      - target: dead_end
  dead_end:
    terminal: true
    failure: true
  finished_ok:
    terminal: true
---

## start
Submit outcome.

## middle
Submit reason.

## dead_end
Terminal.

## finished_ok
Terminal.
CHAIN_EOF

koto init chain_bare --template "$WORKDIR/chain.md" >/dev/null 2>&1
printf 'the orchestrator record\n' | koto context add chain_bare summary.md >/dev/null 2>&1
koto next chain_bare --with-data '{"outcome":"bad"}' >/dev/null 2>&1
if koto context get chain_bare summary.md >/dev/null 2>&1; then
    fail "a bare tick did not chain through the accepts-declaring state -- re-check whether spawn_and_await's ticks still need the flag"
else
    pass "a bare tick chains through a state that declares required evidence and destroys the record (the defect the flag closes)"
fi

koto init chain_flagged --template "$WORKDIR/chain.md" >/dev/null 2>&1
printf 'the orchestrator record\n' | koto context add chain_flagged summary.md >/dev/null 2>&1
koto next chain_flagged --with-data '{"outcome":"bad"}' --no-cleanup >/dev/null 2>&1
if [ "$(koto context get chain_flagged summary.md 2>/dev/null)" = "the orchestrator record" ]; then
    pass "the same chained tick carrying --no-cleanup keeps the record"
else
    fail "the chained tick lost the record even with --no-cleanup"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
