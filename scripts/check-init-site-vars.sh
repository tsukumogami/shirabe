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
#   1. Every `koto init` of work-on.md in skills/work-on/SKILL.md passes each
#      variable work-on.md declares required.
#   2. Every task array /execute builds for its children sets the required
#      variables that plan-to-tasks.sh does not emit. It is not derived from the
#      template because the split is real: ARTIFACT_PREFIX reaches a child from
#      /plan's script, PLUGIN_ROOT and SHARED_BRANCH from /execute's own jq
#      (plan-to-tasks-contract.md is the authority for which is which).
#
# Usage: check-init-site-vars.sh
# Exit codes: 0 all sites pass, 1 a site is missing a variable.

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

TEMPLATE="skills/work-on/koto-templates/work-on.md"
SKILL_DOC="skills/work-on/SKILL.md"
EXECUTE_TEMPLATE="skills/execute/koto-templates/execute.md"

FAILURES=0
note_failure() { echo "check-init-site-vars: $*" >&2; FAILURES=$((FAILURES + 1)); }

for f in "$TEMPLATE" "$SKILL_DOC" "$EXECUTE_TEMPLATE"; do
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

# --- Site 1: agent-driven init in SKILL.md -----------------------------------
# Join backslash continuations so one init command is one line, then keep the
# ones that name the template.
INIT_COMMANDS=$(sed ':a; /\\$/ { N; s/\\\n//; ba; }' "$SKILL_DOC" | grep 'koto init' | grep "$TEMPLATE")

if [[ -z "$INIT_COMMANDS" ]]; then
    note_failure "no 'koto init' of $TEMPLATE found in $SKILL_DOC — the init blocks moved, and this check no longer covers them"
else
    SITE_N=0
    while IFS= read -r cmd; do
        SITE_N=$((SITE_N + 1))
        for var in $REQUIRED_VARS; do
            # ISSUE_NUMBER-style optional variables are not in REQUIRED_VARS, so
            # every name reaching here must appear at this site.
            if [[ "$cmd" != *"--var ${var}="* ]]; then
                note_failure "$SKILL_DOC init site $SITE_N does not pass required variable $var"
            fi
        done
    done <<< "$INIT_COMMANDS"
fi

# --- Site 2: programmatic child materialization from /execute ----------------
# Each tick that builds a task array must inject the variables the child needs
# and plan-to-tasks.sh does not emit. Counting both sides is what catches a
# third tick added later that forgets the injection.
TASK_BUILDS=$(grep -c 'plan-to-tasks.sh {{PLAN_DOC}}' "$EXECUTE_TEMPLATE")
if [[ "$TASK_BUILDS" -eq 0 ]]; then
    note_failure "no task array build found in $EXECUTE_TEMPLATE — children are materialized somewhere this check does not see"
fi

for var in PLUGIN_ROOT SHARED_BRANCH; do
    injections=$(grep -c "\.vars\.${var}[[:space:]]*=" "$EXECUTE_TEMPLATE")
    if [[ "$injections" -ne "$TASK_BUILDS" ]]; then
        note_failure "$EXECUTE_TEMPLATE builds $TASK_BUILDS task array(s) but injects .vars.$var into $injections of them"
    fi
done

if [[ "$FAILURES" -ne 0 ]]; then
    echo "check-init-site-vars: FAILED ($FAILURES problem(s))" >&2
    exit 1
fi

echo "check-init-site-vars: OK (required: $(echo "$REQUIRED_VARS" | tr '\n' ' ')| $(echo "$INIT_COMMANDS" | wc -l) direct init site(s), $TASK_BUILDS child task build(s))"
