#!/usr/bin/env bash
# check-init-site-vars.sh — every place a template is initialized passes the
# variables that template requires.
#
# koto fails loudly when a required variable is missing: `koto init` exits
# non-zero, and a child materialized without one lands in the batch's errored
# ledger. So this check does not exist to turn a silent failure into a loud one.
# It exists because "loud" here means "loud at run time, to whoever happens to
# run it" — and work-on.md is the first template in this repo with more than one
# KIND of init site. /scope's and /execute's templates each have exactly one
# init call, so a required variable there cannot drift out of sync with
# anything. work-on.md is initialized by an agent following SKILL.md AND
# materialized as a child from a task array /execute builds, which means a
# variable can be added to one and forgotten in the other, and nothing in the
# repository would notice until someone ran the path that was missed.
#
# What it checks, and why each entry is here rather than derived:
#
#   1. Every open in skills/work-on/SKILL.md passes each variable work-on.md
#      declares required. SKILL.md has the agent open every issue-backed and
#      free-form run through skills/work-on/scripts/work-on-open.sh, which
#      makes the `koto init` of work-on.md and adds PLUGIN_ROOT itself. So each
#      open site must pass every other required variable as --var, and the
#      opener must still add PLUGIN_ROOT; neither is enough alone.
#   2. Every task array /execute builds for its children sets the required
#      variables that plan-to-tasks.sh does not emit. It is not derived from the
#      template because the split is real: ARTIFACT_PREFIX reaches a child from
#      /plan's script, PLUGIN_ROOT, SHARED_BRANCH and PLAN_DOC from /execute's
#      own jq (plan-to-tasks-contract.md is the authority for which is which).
#   3. Every TEST HARNESS that inits the shipped template passes them too. This
#      third category was not in the first version of this check, and its absence
#      cost two suites: a required variable was added, two harnesses that init
#      the real template were not updated, and every case in them failed at init
#      with a message about a missing session rather than a missing variable. A
#      harness is an init site like any other. Fixing the two would have left the
#      next one to fail the same way, which is what makes this a gap to close
#      rather than a pair of bugs to patch.
#
# Usage: check-init-site-vars.sh
# Exit codes: 0 all sites pass, 1 a site is missing a variable.

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

TEMPLATE="skills/work-on/koto-templates/work-on.md"
SKILL_DOC="skills/work-on/SKILL.md"
OPENER="skills/work-on/scripts/work-on-open.sh"
EXECUTE_TEMPLATE="skills/execute/koto-templates/execute.md"
# The required variables the opener adds itself, so an open site doesn't pass
# them.
OPENER_ADDS="PLUGIN_ROOT"

FAILURES=0
note_failure() { echo "check-init-site-vars: $*" >&2; FAILURES=$((FAILURES + 1)); }

# join_continuations <file> -- print the file with each backslash-continued
# command on one line: a trailing backslash and its newline are removed. awk
# rather than a sed loop, whose `:a; ... ba` form BSD sed refuses.
join_continuations() {
    awk '{ if (sub(/\\$/, "")) { buf = buf $0; next } print buf $0; buf = "" }
         END { if (buf != "") print buf }' "$1"
}

for f in "$TEMPLATE" "$SKILL_DOC" "$OPENER" "$EXECUTE_TEMPLATE"; do
    [[ -f "$f" ]] || { note_failure "missing file: $f"; }
done
[[ "$FAILURES" -eq 0 ]] || exit 1

# --- The template's own required variables -----------------------------------
# Read from the `variables:` block: a two-space-indented KEY, then `required:
# true` before the next KEY at that indent.
REQUIRED_VARS=$(awk '
    /^variables:/ { in_vars = 1; next }
    in_vars && /^[a-z_]+:/ { in_vars = 0 }
    in_vars && /^  [A-Z_]+:/ {
        key = $1; sub(/:$/, "", key); current = key; next
    }
    in_vars && current != "" && /^    required:[[:space:]]*true/ {
        print current; current = ""
    }
' "$TEMPLATE")

if [[ -z "$REQUIRED_VARS" ]]; then
    note_failure "no required variables parsed from $TEMPLATE — the parser or the template changed shape"
    exit 1
fi

# --- Site 1: agent-driven opens in SKILL.md ----------------------------------
# Join backslash continuations so one open command is one line, then keep the
# ones that run the opener by its plugin path. The Scripts entry's usage line
# (`scripts/work-on-open.sh --workflow <WF> [--var NAME=VALUE]...`) names it
# without that path, and is not a site.
INIT_COMMANDS=$(join_continuations "$SKILL_DOC" | grep -F "\${CLAUDE_PLUGIN_ROOT}/$OPENER --workflow")

if [[ -z "$INIT_COMMANDS" ]]; then
    note_failure "no '$OPENER --workflow' open found in $SKILL_DOC — the init blocks moved, and this check no longer covers them"
else
    SITE_N=0
    while IFS= read -r cmd; do
        SITE_N=$((SITE_N + 1))
        for var in $REQUIRED_VARS; do
            # ISSUE_NUMBER-style optional variables are not in REQUIRED_VARS, so
            # every name reaching here must appear at this site, unless the
            # opener adds it (checked below).
            case " $OPENER_ADDS " in *" $var "*) continue ;; esac
            if [[ "$cmd" != *"--var ${var}="* ]]; then
                note_failure "$SKILL_DOC init site $SITE_N does not pass required variable $var"
            fi
        done
    done <<< "$INIT_COMMANDS"
fi

# The opener adds the rest: a `["<VAR>", ...]` pair in the variables it writes,
# on a line that isn't a comment.
for var in $OPENER_ADDS; do
    if ! grep -v '^[[:space:]]*#' "$OPENER" | grep -qF "[\"${var}\","; then
        note_failure "$OPENER no longer adds required variable $var, which the $SKILL_DOC open sites leave to it"
    fi
done

# --- Site 2: programmatic child materialization from /execute ----------------
# Each tick that builds a task array must inject the variables the child needs
# and plan-to-tasks.sh does not emit. Counting both sides is what catches a
# second tick added later that forgets the injection.
TASK_BUILDS=$(grep -c 'plan-to-tasks.sh {{PLAN_DOC}}' "$EXECUTE_TEMPLATE")
if [[ "$TASK_BUILDS" -eq 0 ]]; then
    note_failure "no task array build found in $EXECUTE_TEMPLATE — children are materialized somewhere this check does not see"
fi

# PLAN_DOC isn't required by work-on.md, but a plan/v2 child's step_detail gate
# refuses without it, so a task build that drops it strands every child (#1160).
for var in PLUGIN_ROOT SHARED_BRANCH PLAN_DOC; do
    injections=$(grep -c "\.vars\.${var}[[:space:]]*=" "$EXECUTE_TEMPLATE")
    if [[ "$injections" -ne "$TASK_BUILDS" ]]; then
        note_failure "$EXECUTE_TEMPLATE builds $TASK_BUILDS task array(s) but injects .vars.$var into $injections of them"
    fi
done

# --- Site 3: test harnesses that init the shipped template -------------------
# Any script that names the real template in a `koto init` is bound by the same
# requirement as SKILL.md. Found by scanning rather than by listing, so a harness
# added later is covered without anyone remembering to add it here.
# The init COMMAND has to name the template, not the file merely mention it.
# Matching on the file caught two harnesses that only reference the path — one
# extracts states from it into a fixture of its own, another greps it for a flag
# — and neither inits it. A check that reports sites which are not sites teaches
# people to ignore it.
HARNESSES=$(grep -rl "koto init" skills/*/scripts/*.sh 2>/dev/null || true)
HARNESS_SITES=0
for harness in $HARNESSES; do
    # A harness names the template through its own variable, so match the
    # literal text "$TEMPLATE" in the init command AND confirm that variable is
    # assigned this template. Matching the file instead of the command caught two
    # harnesses that only reference the path -- one extracts states from it into a
    # fixture of its own, the other greps it for a flag -- and neither inits it.
    # A check that reports sites which are not sites teaches people to ignore it.
    names_template=0
    if grep -qE '^[[:space:]]*TEMPLATE=.*koto-templates/work-on\.md' "$harness"; then
        names_template=1
    fi
    inits=$(join_continuations "$harness" | grep 'koto init' || true)
    [[ -n "$inits" ]] || continue
    while IFS= read -r cmd; do
        # An --attach-live call is not an init site: it attaches to a live
        # session to re-apply its rebind variables (review-level.sh set rebinds
        # REVIEW_LEVEL that way), and koto refuses one that changes a
        # non-rebind variable. The session it attaches to was created by a
        # site this check covers. An attach that also binds a --koto-leg can
        # create the session, so it stays a site.
        case "$cmd" in *--koto-leg*) ;; *--attach-live*) continue ;; esac
        case "$cmd" in
            *koto-templates/work-on.md*) ;;
            *'"$TEMPLATE"'*) [[ "$names_template" -eq 1 ]] || continue ;;
            *) continue ;;
        esac
        HARNESS_SITES=$((HARNESS_SITES + 1))
        for var in $REQUIRED_VARS; do
            if [[ "$cmd" != *"--var ${var}="* ]]; then
                note_failure "$harness inits the shipped template without required variable $var"
            fi
        done
    done <<< "$inits"
done

# Zero is not a pass. Harnesses that drive the shipped template exist; finding
# none means the matching broke, and a check covering nothing reports OK forever.
if [[ "$HARNESS_SITES" -eq 0 ]]; then
    note_failure "no harness init of the shipped template found -- the scan no longer sees any, so it is covering nothing"
fi

if [[ "$FAILURES" -ne 0 ]]; then
    echo "check-init-site-vars: FAILED ($FAILURES problem(s))" >&2
    exit 1
fi

echo "check-init-site-vars: OK (required: $(echo "$REQUIRED_VARS" | tr '\n' ' ')| $(echo "$INIT_COMMANDS" | wc -l | tr -d ' ') SKILL.md open site(s), $TASK_BUILDS child task build(s), $HARNESS_SITES harness init site(s))"
