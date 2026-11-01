#!/usr/bin/env bash
# check-handoff_test.sh -- tests for scripts/check-handoff.sh, the hand-off
# check the script-graded eval cases run.
#
# Usage: bash scripts/check-handoff_test.sh
#
# Every case runs a temporary copy's own scripts/check-handoff.sh, after one
# mutation of that copy; the checkout is never changed. Two kinds of copy:
#
#   - a small copy: the check and its helpers, the five skills' SKILL.md and
#     koto-templates/, deliver-open-request.sh (the opener the attach runs)
#     and /coordinate's entry-points.tsv, with a stand-in for each route
#     suite check-handoff.routes.tsv names that passes one case. The
#     contract, directive and attach mutations run here, so each costs a
#     compile and a few koto inits rather than the engine suites.
#   - a full copy of the tree (tracked and untracked files git doesn't
#     ignore), made once: the unchanged runs, the route mutations and the
#     route selectors run here against the real suites. Each mutation of it
#     is undone before the next case.
#
# The mutations, per hand-off:
#
#   deliver -> execute  the outcome word on the edges into each terminal of
#                       execute.md renamed; a new terminal with a new word;
#                       exec_leg's expect list short each of its five
#                       outcomes; each key execute_run copies dropped from a
#                       terminal that ends with its outcome; an extra copied
#                       key; exec_leg removed and renamed; execute_run's
#                       directive without skill `execute` and without
#                       --koto-leg; execute.md renamed; --koto-leg gone from
#                       execute's SKILL.md; deliver-execute-leg.sh exiting
#                       non-zero and dropping --store (full copy)
#   deliver -> scope    scope_leg and scope_intent removed and renamed;
#                       scope_leg's expect list short each outcome;
#                       scope_intent's short intent-mismatch (full copy);
#                       scope_run's directive without skill `scope` and
#                       without --koto-leg; scope.md renamed; pr_state,
#                       step and reason dropped from the terminals that end
#                       with executed, error and refused; a results record
#                       naming an unknown outcome, an uncopied key, or
#                       leaving out a key every terminal of its outcome
#                       carries
#   execute -> work-on  default_template pointing at a missing template;
#                       work-on.md renamed; assert-child-template_test.sh
#                       failing, with its route row and without (full copy)
#   coordinate -> <to>  deliver's entry-points row naming no leg; scope's
#                       row not admitting scope.md; --koto-leg gone from
#                       work-on's SKILL.md; pr dropped from work-on.md's
#                       terminals; the `-` results record listing an
#                       uncopied key, leaving out pr, and deleted; wait_leg
#                       capturing WAIT_LEG_X; leg_result reading an init
#                       variable; work-on.md renamed; dispatch-worker.sh
#                       dropping --koto-leg from a /deliver worker (full copy)
#
# and: koto absent and a koto without --koto-leg, for each hand-off; a route
# suite that SKIPs or passes nothing; the caller's own koto sessions the same
# before and after a passing and a failing run, and what `koto workflows`
# lists the same around a passing and a failing coordinate -> work-on run,
# with nothing left in TMPDIR; and deliver-engine_test.sh under each
# selector and none.
#
# Needs koto (with --koto-leg), python3, jq and git. With no koto on PATH
# every case fails rather than skips: a skip here would report green having
# checked nothing.
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# bash 3.2 floor: no associative arrays, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'ok   %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/check-handoff-test.XXXXXX") || { echo "FAIL mktemp"; exit 1; }
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
ktg_on_exit cleanup

if ! command -v koto >/dev/null; then
    fail "koto is not on PATH; check-handoff.sh needs it, so no case can run"
    echo ""
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    exit 1
fi

COPY="$T/tree"
FULL="$T/full"
EXEC_TPL="skills/execute/koto-templates/execute.md"
DELIVER_TPL="skills/deliver/koto-templates/deliver.md"
SCOPE_TPL="skills/scope/koto-templates/scope.md"
COORD_TPL="skills/coordinate/koto-templates/coordinate.md"
WORKON_TPL="skills/work-on/koto-templates/work-on.md"
ENTRY_POINTS="skills/coordinate/references/entry-points.tsv"
RESULTS="scripts/check-handoff.results.tsv"
ROUTES="scripts/check-handoff.routes.tsv"
TAB=$(printf '\t')
EDGES="deliver:execute deliver:scope execute:work-on coordinate:deliver coordinate:execute coordinate:scope coordinate:work-on"
# Every suite the route table names, once each.
ROUTE_SUITES=$(awk -F "$TAB" '$0 !~ /^#/ && NF == 3 { print $3 }' "$REPO_ROOT/$ROUTES" | sort -u)

# stub_suite <path> [<line>...]: a stand-in route suite printing its lines,
# by default one passing case.
stub_suite() {
    local path="$1"
    shift
    [ "$#" -gt 0 ] || set -- "ok   stand-in route suite" "Results: 1 passed, 0 failed"
    mkdir -p "$(dirname "$path")"
    {
        echo '#!/usr/bin/env bash'
        for line in "$@"; do printf 'echo %s\n' "'$line'"; done
        echo 'exit 0'
    } >"$path"
}

# fresh_copy: the small copy in $COPY, replacing any earlier one.
fresh_copy() {
    rm -rf "$COPY"
    mkdir -p "$COPY/scripts/lib" "$COPY/skills/deliver/scripts" || return 1
    cp "$REPO_ROOT/scripts/check-handoff.sh" "$REPO_ROOT/$RESULTS" "$REPO_ROOT/$ROUTES" \
        "$COPY/scripts/" || return 1
    cp "$REPO_ROOT/scripts/lib/check-handoff.py" "$REPO_ROOT/scripts/lib/koto-test-guard.sh" \
        "$COPY/scripts/lib/" || return 1
    for s in deliver execute scope work-on coordinate; do
        mkdir -p "$COPY/skills/$s" || return 1
        cp "$REPO_ROOT/skills/$s/SKILL.md" "$COPY/skills/$s/" || return 1
        cp -R "$REPO_ROOT/skills/$s/koto-templates" "$COPY/skills/$s/" || return 1
    done
    cp "$REPO_ROOT/skills/deliver/scripts/deliver-open-request.sh" "$COPY/skills/deliver/scripts/" || return 1
    mkdir -p "$COPY/skills/coordinate/references" || return 1
    cp "$REPO_ROOT/$ENTRY_POINTS" "$COPY/$ENTRY_POINTS" || return 1
    for suite in $ROUTE_SUITES; do stub_suite "$COPY/$suite"; done
}

# full_copy: the whole tree in $FULL, once.
full_copy() {
    mkdir -p "$FULL" || return 1
    (cd "$REPO_ROOT" && git ls-files -co --exclude-standard -z | tar -cf - --null -T -) \
        | tar -xf - -C "$FULL"
}

RC=0
OUT=""
# run_check <tree> <from> <to>: that tree's check; sets RC and OUT.
run_check() {
    RC=0
    OUT=$(bash "$1/scripts/check-handoff.sh" "$2" "$3" 2>&1) || RC=$?
}

# apply <file> <awk program> [awk -v assignments...]: rewrite a file in the
# small copy through awk, and fail when the rewrite changed nothing, so a
# mutation that no longer matches the template is reported instead of
# passing quietly.
apply() {
    local file="$COPY/$1" prog="$2"
    shift 2
    awk "$@" "$prog" "$file" >"$file.new" || return 1
    if cmp -s "$file" "$file.new"; then
        rm -f "$file.new"
        return 1
    fi
    mv "$file.new" "$file"
}

# The state a line belongs to (a two-space-indented key in the frontmatter)
# and the target of the transition it sits under.
TRACK='
/^  [A-Za-z_][A-Za-z0-9_]*:[ ]*$/ { state = $1; sub(/:$/, "", state); target = "" }
/^ *- target: / { target = $0; sub(/^ *- target: */, "", target); sub(/[ ]*$/, "", target) }
'

# mut <file> <op> <args...>: a structured mutation (see MUTATOR below);
# exits 1 when it changed nothing.
MUTATOR="$T/mutate.py"
cat >"$MUTATOR" <<'PY'
import re, sys

path, op, args = sys.argv[1], sys.argv[2], sys.argv[3:]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().split("\n")
out = []

def state_of(i):
    """The frontmatter state (two-space key) line i sits in."""
    for j in range(i, -1, -1):
        m = re.match(r"  ([A-Za-z_][A-Za-z0-9_]*):\s*$", lines[j])
        if m:
            return m.group(1)
    return None

if op == "section-replace":          # <## section> <old> <new>
    section, old, new = args
    sec = None
    for line in lines:
        if line.startswith("## "):
            sec = line[3:].strip()
        out.append(line.replace(old, new) if sec == section else line)
elif op == "gate-remove":            # <state> <gate>
    state, gate = args
    skip = False
    for i, line in enumerate(lines):
        if line == "      %s:" % gate and state_of(i) == state:
            skip = True
            continue
        if skip and line.startswith("        "):
            continue
        skip = False
        out.append(line)
elif op == "gate-rename":            # <state> <gate> <new name>
    state, gate, new = args
    for i, line in enumerate(lines):
        out.append("      %s:" % new if line == "      %s:" % gate and state_of(i) == state else line)
elif op == "expect-drop":            # <state> <field> <value>
    state, field, value = args
    for i, line in enumerate(lines):
        m = re.match(r"(\s+%s: \[)(.*)(\].*)$" % re.escape(field), line)
        if m and state_of(i) == state:
            items = [x.strip() for x in m.group(2).split(",")]
            line = m.group(1) + ", ".join(x for x in items if x.strip('"') != value) + m.group(3)
        out.append(line)
elif op == "result-drop":            # <terminal> <key>
    terminal, key = args
    for i, line in enumerate(lines):
        if re.match(r"      %s: " % re.escape(key), line) and state_of(i) == terminal:
            continue
        out.append(line)
elif op == "line-replace":           # <old line> <new line>
    old, new = args
    out = [new if line == old else line for line in lines]
elif op == "line-insert-after":      # <line> <new line>
    old, new = args
    for line in lines:
        out.append(line)
        if line == old:
            out.append(new)
else:
    sys.exit("unknown op " + op)

if out == lines:
    sys.exit(1)
with open(path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(out))
PY
mut() {
    local file="$1"
    shift
    python3 "$MUTATOR" "$file" "$@"
}

# expect_fail <label> <needle>...: the check exited non-zero and its output
# names every needle.
expect_fail() {
    local label="$1" needle missing=""
    shift
    for needle in "$@"; do
        case "$OUT" in *"$needle"*) ;; *) missing="$missing [$needle]" ;; esac
    done
    if [ "$RC" -ne 0 ] && [ -z "$missing" ]; then
        pass "$label: exit $RC, output names $*"
    else
        fail "$label (rc=$RC, missing:$missing): $OUT"
    fi
}

# expect_pass <label> <from> <to>: exit 0 with one PASS line per check.
expect_pass() {
    local label="$1" want
    want="PASS: handoff $2 -> $3: receiving-side contract
PASS: handoff $2 -> $3: rendered directive
PASS: handoff $2 -> $3: attach
PASS: handoff $2 -> $3: routes"
    if [ "$RC" -eq 0 ] && [ "$OUT" = "$want" ]; then
        pass "$label: $2 -> $3 exits 0 with a PASS line for each of the four checks"
    else
        fail "$label: $2 -> $3 (rc=$RC): $OUT"
    fi
}

# small <label> <from> <to> <needle>... -- <mutation command...>: a fresh
# small copy, the mutation, the check, and the expected failure.
small() {
    local label="$1" from="$2" to="$3" needles=()
    shift 3
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do needles+=("$1"); shift; done
    shift
    fresh_copy || { fail "$label: could not copy the tree"; return; }
    if ! "$@"; then
        fail "$label: the mutation matched nothing"
        rm -rf "$COPY"
        return
    fi
    run_check "$COPY" "$from" "$to"
    expect_fail "$label" "${needles[@]}"
    rm -rf "$COPY"
}

# -- unchanged small copy ----------------------------------------------------

for edge in $EDGES; do
    fresh_copy || { fail "could not copy the tree"; break; }
    run_check "$COPY" "${edge%%:*}" "${edge#*:}"
    expect_pass "the small copy, unchanged" "${edge%%:*}" "${edge#*:}"
done
rm -rf "$COPY"

# -- deliver -> execute: outcome words on the edges into each terminal ----------

rename_edge() { # rename_edge <terminal> <old word> <new word>
    apply "$EXEC_TPL" "$TRACK"'
{ if (target == t && $0 ~ ("^ +outcome: " old "$")) sub("outcome: " old "$", "outcome: " new); print }' \
        -v t="$1" -v old="$2" -v new="$3"
}
for spec in paused_for_review:paused-for-review merged:merged \
    ready_awaiting_merge:ready-awaiting-merge done_blocked:error; do
    terminal=${spec%%:*}
    word=${spec#*:}
    small "'$word' renamed to '$word-renamed' on the edges into $terminal" deliver execute \
        "receiving-side contract" "outcome word '$word-renamed'" "doesn't expect it" "exec_leg" \
        -- rename_edge "$terminal" "$word" "$word-renamed"
done

# escalate's one unconditional edge goes to a new terminal, parked, assigning
# the word parked; parked's result map is the others'.
add_parked() {
    apply "$EXEC_TPL" "$TRACK"'
$0 == "  done_blocked:" {
    print "  parked:"; print "    terminal: true"; print "    result:"
    print "      outcome: \"${context.outcome}\""; print "      step: \"${context.step}\""
    print "      reason: \"${context.reason}\""; print "      pr: \"${context.home_pr}\""
    print "      repos: \"${context.repos}\""; print "      resume: \"${context.resume}\""
    print "      waiting: \"${context.waiting}\""; print ""
}
{
    if (state == "escalate" && $0 ~ /^ *- target: done_blocked$/) sub(/done_blocked$/, "parked")
    else if (state == "escalate" && $0 ~ /^ +outcome: error$/) sub(/error$/, "parked")
    print
}
END { print ""; print "## parked"; print ""; print "Parked." }'
}
small "a new terminal state reached by an edge assigning 'parked'" deliver execute \
    "outcome word 'parked'" "terminal state parked" "doesn't expect it" -- add_parked

# -- deliver -> execute: exec_leg's expect list, and the gate itself ------------

for word in merged ready-awaiting-merge paused-for-review paused-awaiting-merges error; do
    small "exec_leg's expect list without $word" deliver execute \
        "receiving-side contract" "exec_leg" "'$word'" "expect" \
        -- mut "$COPY/$DELIVER_TPL" expect-drop execute_run outcome "$word"
done
small "exec_leg removed from execute_run" deliver execute "receiving-side contract" "exec_leg" \
    -- mut "$COPY/$DELIVER_TPL" gate-remove execute_run exec_leg
small "exec_leg renamed in execute_run" deliver execute "receiving-side contract" "exec_leg" \
    -- mut "$COPY/$DELIVER_TPL" gate-rename execute_run exec_leg exec_gate

# -- deliver -> execute: result keys, per outcome ---------------------------------

# Each key the merged transition copies, dropped from merged; step, which
# only the error transition copies, from done_blocked, the terminal error
# ends at.
for spec in merged:pr merged:repos merged:resume merged:waiting merged:reason done_blocked:step; do
    terminal=${spec%%:*}
    key=${spec#*:}
    small "'$key' dropped from the result map of terminal state $terminal" deliver execute \
        "key '$key'" "terminal state $terminal" "execute_run" \
        -- mut "$COPY/$EXEC_TPL" result-drop "$terminal" "$key"
done
# step from merged: no transition that can end at merged copies it.
fresh_copy && mut "$COPY/$EXEC_TPL" result-drop merged step && run_check "$COPY" deliver execute
case "$OUT" in
    *"key 'step'"*) fail "'step' dropped from merged, which no merged transition copies, fails the check: $OUT" ;;
    *) pass "'step' dropped from merged, which no transition for outcome merged copies, is not a failure" ;;
esac
rm -rf "$COPY"

add_extra() {
    apply "$DELIVER_TPL" "$TRACK"'
{
    print
    if (state == "execute_run" && !done && $0 ~ /^ +pr: "\$\{gates\.exec_leg\.payload\.pr\}"$/) {
        line = $0; sub(/pr: .*/, "", line)
        print line "extra: \"${gates.exec_leg.payload.extra}\""
        done = 1
    }
}'
}
small "execute_run also copying 'extra'" deliver execute "key 'extra'" "missing from the result map" \
    -- add_extra

# -- deliver -> execute: the rendered directive, the template, the SKILL.md --------

small "execute_run's directive not naming skill execute" deliver execute \
    "rendered directive" "does not name skill \`execute\`" \
    -- mut "$COPY/$DELIVER_TPL" section-replace execute_run '`execute` and these arguments' '`exec` and these arguments'
small "execute_run's directive without --koto-leg" deliver execute \
    "rendered directive" "does not carry --koto-leg=req-handoff-check:execute" \
    -- mut "$COPY/$DELIVER_TPL" section-replace execute_run '--koto-leg={{REQ}}:execute' '--leg={{REQ}}:execute'
small "execute.md renamed to execute-v2.md" deliver execute \
    "execute.md" "does not exist" "attach" "koto refused" "execute-v2.md" \
    -- mv "$COPY/$EXEC_TPL" "$COPY/skills/execute/koto-templates/execute-v2.md"
small "--koto-leg removed from skills/execute/SKILL.md" deliver execute \
    "--koto-leg" "skills/execute/SKILL.md" \
    -- apply "skills/execute/SKILL.md" 'index($0, "--koto-leg") == 0 { print }'

# -- deliver -> scope ----------------------------------------------------------------

for gate in scope_leg scope_intent; do
    small "$gate removed from scope_run" deliver scope "receiving-side contract" "$gate" \
        -- mut "$COPY/$DELIVER_TPL" gate-remove scope_run "$gate"
    small "$gate renamed in scope_run" deliver scope "receiving-side contract" "$gate" \
        -- mut "$COPY/$DELIVER_TPL" gate-rename scope_run "$gate" "${gate}_x"
done
for word in scoped handed-off-multi-pr executed re-evaluation abandonment cancelled refused error; do
    small "scope_leg's expect list without $word" deliver scope \
        "receiving-side contract" "scope_leg" "'$word'" \
        -- mut "$COPY/$DELIVER_TPL" expect-drop scope_run outcome "$word"
done
small "scope_run's directive not naming skill scope" deliver scope \
    "rendered directive" "does not name skill \`scope\`" \
    -- mut "$COPY/$DELIVER_TPL" section-replace scope_run '`scope` and' '`scoping` and'
small "scope_run's directive without --koto-leg" deliver scope \
    "rendered directive" "does not carry --koto-leg=req-handoff-check:scope" \
    -- mut "$COPY/$DELIVER_TPL" section-replace scope_run '--koto-leg={{REQ}}:scope' '--leg={{REQ}}:scope'
small "scope.md renamed to scope-v2.md" deliver scope \
    "attach" "koto refused" "scope-v2.md" \
    -- mv "$COPY/$SCOPE_TPL" "$COPY/skills/scope/koto-templates/scope-v2.md"
for spec in done_executed:pr_state:executed done_error:step:error done_refused:reason:refused; do
    terminal=${spec%%:*}
    rest=${spec#*:}
    key=${rest%%:*}
    word=${rest#*:}
    small "'$key' dropped from $terminal" deliver scope \
        "key '$key'" "terminal state $terminal" "outcome '$word'" \
        -- mut "$COPY/$SCOPE_TPL" result-drop "$terminal" "$key"
done

# -- deliver -> scope: the results records --------------------------------------------

TAB=$(printf '\t')
small "a results record naming an outcome scope_leg doesn't expect" deliver scope \
    "check-handoff.results.tsv" "outcome 'shipped'" "doesn't expect" \
    -- mut "$COPY/$RESULTS" line-insert-after "deliver${TAB}scope${TAB}cancelled${TAB}intent" \
    "deliver${TAB}scope${TAB}shipped${TAB}intent"
small "a results record naming a key the transition doesn't copy" deliver scope \
    "check-handoff.results.tsv" "key 'via'" "copies" \
    -- mut "$COPY/$RESULTS" line-replace "deliver${TAB}scope${TAB}cancelled${TAB}intent" \
    "deliver${TAB}scope${TAB}cancelled${TAB}intent,via"
small "a results record leaving out a key every terminal of its outcome carries" deliver scope \
    "check-handoff.results.tsv" "leaves out key 'pr_state'" "done_executed" \
    -- mut "$COPY/$RESULTS" line-replace "deliver${TAB}scope${TAB}executed${TAB}intent,pr,pr_state" \
    "deliver${TAB}scope${TAB}executed${TAB}intent,pr"

# -- execute -> work-on ------------------------------------------------------------------

small "spawn_and_await's default_template pointing at a missing work-on template" execute work-on \
    "child template reference" "skills/work-on/koto-templates/work-on-v2.md" "does not exist" \
    -- mut "$COPY/$EXEC_TPL" line-replace "      default_template: ../../work-on/koto-templates/work-on.md" \
    "      default_template: ../../work-on/koto-templates/work-on-v2.md"
small "work-on.md renamed" execute work-on \
    "child template reference" "skills/work-on/koto-templates/work-on.md" "does not exist" \
    -- mv "$COPY/skills/work-on/koto-templates/work-on.md" "$COPY/skills/work-on/koto-templates/work-on-v1.md"

# -- coordinate -> deliver, execute, scope, work-on: the templated leg ---------------------

# entry_field <skill> <field> <value>: set one field of a skill's row in
# entry-points.tsv.
entry_field() {
    apply "$ENTRY_POINTS" 'BEGIN { FS = OFS = "\t" } $0 !~ /^#/ && $1 == s { $f = v } { print }' \
        -v s="$1" -v f="$2" -v v="$3"
}
small "deliver's entry-points row naming no leg" coordinate deliver \
    "receiving-side contract" "entry-points.tsv" "row for \`deliver\` names leg \`-\`" \
    -- entry_field deliver 2 -
small "scope's entry-points row no longer admitting scope.md" coordinate scope \
    "receiving-side contract" "entry-points.tsv" "doesn't admit scope.md" \
    -- entry_field scope 3 scope-v2.md
small "--koto-leg removed from skills/work-on/SKILL.md" coordinate work-on \
    "--koto-leg" "skills/work-on/SKILL.md" \
    -- apply "skills/work-on/SKILL.md" 'index($0, "--koto-leg") == 0 { print }'
drop_work_on_pr() {
    mut "$COPY/$WORKON_TPL" result-drop "done" pr &&
        mut "$COPY/$WORKON_TPL" result-drop done_already_complete pr
}
small "pr dropped from work-on.md's done and done_already_complete" coordinate work-on \
    "receiving-side contract" "key 'pr'" "every terminal state" -- drop_work_on_pr
WORKON_RECORD="coordinate${TAB}work-on${TAB}-${TAB}pr"
RECORD_LINE=$(grep -n -F -x "$WORKON_RECORD" "$REPO_ROOT/$RESULTS" | cut -d: -f1)
small "the '-' record listing a key wait_leg doesn't copy" coordinate work-on \
    "check-handoff.results.tsv line $RECORD_LINE" "key 'repos'" \
    -- mut "$COPY/$RESULTS" line-replace "$WORKON_RECORD" "coordinate${TAB}work-on${TAB}-${TAB}pr,repos"
small "the '-' record leaving out pr, which a work-on terminal carries" coordinate work-on \
    "check-handoff.results.tsv line $RECORD_LINE" "leaves out key 'pr'" \
    -- mut "$COPY/$RESULTS" line-replace "$WORKON_RECORD" "coordinate${TAB}work-on${TAB}-${TAB}-"
small "the coordinate work-on record deleted" coordinate work-on \
    "key 'step'" "key 'reason'" "work-on.md" \
    -- apply "$RESULTS" '$0 != r { print }' -v r="$WORKON_RECORD"
# koto refuses to compile a gate reading a variable nothing declares or
# captures, naming it; the directive check fails with it.
small "wait_leg capturing WAIT_LEG_X" coordinate work-on \
    "rendered directive" "WAIT_LEG" \
    -- mut "$COPY/$COORD_TPL" line-replace "      capture_stdout_as: WAIT_LEG" "      capture_stdout_as: WAIT_LEG_X"
# A gate reading a declared init variable compiles; only the directive check,
# which wants a value a state's action captured, refuses it.
small "leg_result reading the init variable SCOPE, which no state captures" coordinate work-on \
    "rendered directive" "SCOPE" "capture_stdout_as" \
    -- mut "$COPY/$COORD_TPL" line-replace '        leg: "{{WAIT_LEG}}"' '        leg: "{{SCOPE}}"'
small "work-on.md renamed, against the templated leg" coordinate work-on \
    "attach" "koto refused" "work-on-v1.md" \
    -- mv "$COPY/$WORKON_TPL" "$COPY/skills/work-on/koto-templates/work-on-v1.md"

# -- route suites that check nothing -------------------------------------------------------

small "a route suite that SKIPs and exits 0" deliver execute "routes" "SKIP: jq not on PATH" \
    -- stub_suite "$COPY/skills/deliver/scripts/deliver-engine_test.sh" "SKIP: jq not on PATH"
small "a route suite that passes no case" deliver execute "routes" "reported no passing case" \
    -- stub_suite "$COPY/skills/deliver/scripts/deliver-engine_test.sh" "Results: 0 passed, 0 failed"

# -- koto ------------------------------------------------------------------------------------

fresh_copy || fail "could not copy the tree"
NOKOTO="$T/nokoto-bin"
mkdir -p "$NOKOTO"
ln -s "$(command -v python3)" "$NOKOTO/python3"
OLDKOTO="$T/oldkoto-bin"
mkdir -p "$OLDKOTO"
printf '#!/bin/sh\n[ "$1 $2" = "init --help" ] && { echo "Usage: koto init [OPTIONS] <NAME>"; exit 0; }\nexit 1\n' \
    >"$OLDKOTO/koto"
chmod +x "$OLDKOTO/koto"
for edge in $EDGES; do
    from=${edge%%:*}
    to=${edge#*:}
    if PATH="$NOKOTO:/usr/bin:/bin" command -v koto >/dev/null; then
        echo "SKIP: a koto in /usr/bin or /bin -- the no-koto case was not checked"
    else
        RC=0
        OUT=$(PATH="$NOKOTO:/usr/bin:/bin" /bin/bash "$COPY/scripts/check-handoff.sh" "$from" "$to" 2>&1) || RC=$?
        expect_fail "$from $to with no koto on PATH" "koto is not on PATH"
    fi
    RC=0
    OUT=$(PATH="$OLDKOTO:$PATH" bash "$COPY/scripts/check-handoff.sh" "$from" "$to" 2>&1) || RC=$?
    expect_fail "$from $to with a koto whose init has no --koto-leg" "koto" "--koto-leg"
done

RC=0
OUT=$(bash "$COPY/scripts/check-handoff.sh" deliver nosuchskill 2>&1) || RC=$?
if [ "$RC" -eq 2 ] && case "$OUT" in *"skills/nosuchskill"*) true ;; *) false ;; esac; then
    pass "a skill with no directory under skills/ is a usage error, exit 2"
else
    fail "missing skill (rc=$RC): $OUT"
fi

# -- the caller's koto store and TMPDIR ---------------------------------------------------

# This suite's own store stands for the caller's: a session in it, listed
# before and after a passing run and a failing one, which each run with a
# TMPDIR of their own that must be empty afterwards.
PROBE="$T/probe"
mkdir -p "$PROBE"
cat >"$PROBE/probe.md" <<'TPL'
---
name: probe
version: "1.0"
description: a caller session check-handoff.sh must not touch
initial_state: work
states:
  work:
    terminal: true
---
## work
Probe.
TPL
(cd "$PROBE" && koto init caller-probe --template "$PROBE/probe.md" >/dev/null 2>&1)
BEFORE=$(cd "$PROBE" && koto session list 2>/dev/null)
for kind in passing failing; do
    run_tmp="$T/tmp-$kind"
    mkdir -p "$run_tmp"
    [ "$kind" = failing ] && mut "$COPY/$EXEC_TPL" result-drop merged pr
    RC=0
    OUT=$(cd "$PROBE" && TMPDIR="$run_tmp" bash "$COPY/scripts/check-handoff.sh" deliver execute 2>&1) || RC=$?
    AFTER=$(cd "$PROBE" && koto session list 2>/dev/null)
    left=$(ls -A "$run_tmp")
    want_rc=0
    [ "$kind" = failing ] && want_rc=1
    if [ "$RC" -eq "$want_rc" ] && [ -n "$BEFORE" ] && [ "$BEFORE" = "$AFTER" ] && [ -z "$left" ]; then
        pass "a $kind run (exit $RC) leaves the caller's koto sessions as they were and nothing in TMPDIR"
    else
        fail "a $kind run (rc=$RC): sessions before [$BEFORE] after [$AFTER], left in TMPDIR [$left]: $OUT"
    fi
done
rm -rf "$COPY"

# The same for coordinate -> work-on, read through `koto workflows`: its
# attach opens a request and a work-on session, both in the scratch store.
fresh_copy || fail "could not copy the tree"
WF_BEFORE=$(cd "$PROBE" && koto workflows 2>/dev/null)
for kind in passing failing; do
    run_tmp="$T/tmp-coordinate-$kind"
    mkdir -p "$run_tmp"
    [ "$kind" = failing ] && drop_work_on_pr
    RC=0
    OUT=$(cd "$PROBE" && TMPDIR="$run_tmp" bash "$COPY/scripts/check-handoff.sh" coordinate work-on 2>&1) || RC=$?
    WF_AFTER=$(cd "$PROBE" && koto workflows 2>/dev/null)
    left=$(ls -A "$run_tmp")
    want_rc=0
    [ "$kind" = failing ] && want_rc=1
    case "$WF_BEFORE" in *caller-probe*) listed=1 ;; *) listed=0 ;; esac
    if [ "$RC" -eq "$want_rc" ] && [ "$listed" -eq 1 ] && [ "$WF_BEFORE" = "$WF_AFTER" ] && [ -z "$left" ]; then
        pass "a $kind coordinate work-on run (exit $RC) leaves what koto workflows lists as it was and nothing in TMPDIR"
    else
        fail "a $kind coordinate work-on run (rc=$RC): workflows before [$WF_BEFORE] after [$WF_AFTER], left in TMPDIR [$left]: $OUT"
    fi
done
rm -rf "$COPY"

# -- the full copy: unchanged, the route breaks, the selectors ------------------------------

if ! full_copy; then
    fail "could not make the full copy of the tree"
else
    for edge in $EDGES; do
        run_check "$FULL" "${edge%%:*}" "${edge#*:}"
        expect_pass "the full copy, unchanged" "${edge%%:*}" "${edge#*:}"
    done

    # A /deliver worker's invocation without --koto-leg: dispatch-worker_test.sh,
    # which /coordinate's edges run whole, fails, and the routes check carries
    # its failing line.
    DW="skills/coordinate/scripts/dispatch-worker.sh"
    cp "$FULL/$DW" "$T/dw.orig"
    if mut "$FULL/$DW" line-replace \
        'INVOCATION=$(dc_invocation "$INPUT" "$RETURN_PATH") || die 2 "building the invocation failed"' \
        'INVOCATION=$(if [ "$ENTRY" = deliver ]; then dc_invocation "$INPUT" message; else dc_invocation "$INPUT" "$RETURN_PATH"; fi) || die 2 "building the invocation failed"'; then
        run_check "$FULL" coordinate deliver
        expect_fail "dispatch-worker.sh dropping --koto-leg from a /deliver worker's invocation" \
            "routes" "dispatch-worker_test.sh" "FAIL prompt: invocation"
    else
        fail "the dispatch-worker.sh mutation matched nothing"
    fi
    cp "$T/dw.orig" "$FULL/$DW"

    # The route table alone decides which suites an edge runs: with
    # assert-child-template_test.sh failing, execute -> work-on fails while
    # its row is there and passes once the row is gone, with no edit to
    # check-handoff.sh.
    ACT="skills/execute/scripts/assert-child-template_test.sh"
    cp "$FULL/$ACT" "$T/act.orig"
    cp "$FULL/$ROUTES" "$T/routes.orig"
    printf '#!/usr/bin/env bash\necho "FAIL made to fail"\necho "Results: 0 passed, 1 failed"\nexit 1\n' >"$FULL/$ACT"
    run_check "$FULL" execute work-on
    expect_fail "assert-child-template_test.sh failing, its row present" \
        "routes" "assert-child-template_test.sh" "made to fail"
    if mut "$FULL/$ROUTES" line-replace "execute${TAB}work-on${TAB}$ACT" "# row removed"; then
        run_check "$FULL" execute work-on
        expect_pass "assert-child-template_test.sh failing, its row removed" execute work-on
    else
        fail "the route table row removal matched nothing"
    fi
    if cmp -s "$REPO_ROOT/scripts/check-handoff.sh" "$FULL/scripts/check-handoff.sh"; then
        pass "the route table row removal needed no edit to check-handoff.sh"
    else
        fail "check-handoff.sh in the full copy differs from the checkout's"
    fi
    cp "$T/act.orig" "$FULL/$ACT"
    cp "$T/routes.orig" "$FULL/$ROUTES"

    LEG="skills/deliver/scripts/deliver-execute-leg.sh"
    cp "$FULL/$LEG" "$T/leg.orig"
    if mut "$FULL/$LEG" line-insert-after "handover)" "    exit 3"; then
        run_check "$FULL" deliver execute
        expect_fail "deliver-execute-leg.sh exiting non-zero on handover" \
            "routes" "deliver-engine_test.sh" "a single-pr PLAN: the handover reads none"
    else
        fail "the leg script mutation matched nothing"
    fi
    cp "$T/leg.orig" "$FULL/$LEG"
    if mut "$FULL/$LEG" line-replace "        printf -- '--coordination-pr %s --store %s\\n' \"\$PR\" \"\$STORE\"" \
        "        printf -- '--coordination-pr %s\\n' \"\$PR\""; then
        run_check "$FULL" deliver execute
        expect_fail "deliver-execute-leg.sh dropping --store from the handover" \
            "routes" "a coordinated PLAN with --store session: both flags"
    else
        fail "the --store mutation matched nothing"
    fi
    cp "$T/leg.orig" "$FULL/$LEG"

    cp "$FULL/$DELIVER_TPL" "$T/deliver.orig"
    if mut "$FULL/$DELIVER_TPL" expect-drop scope_run reason intent-mismatch; then
        run_check "$FULL" deliver scope
        expect_fail "scope_intent's expect list without intent-mismatch" "routes" "scope_intent"
    else
        fail "the scope_intent mutation matched nothing"
    fi
    cp "$T/deliver.orig" "$FULL/$DELIVER_TPL"

    # deliver-engine_test.sh under each selector and none. The sections and
    # the routes each names come from the suite's own `if section` lines.
    ENGINE="$FULL/skills/deliver/scripts/deliver-engine_test.sh"
    for route in all execute scope; do
        RC=0
        if [ "$route" = all ]; then
            bash "$ENGINE" >"$T/engine-$route.out" 2>&1 || RC=$?
        else
            HANDOFF_ROUTE="$route" bash "$ENGINE" >"$T/engine-$route.out" 2>&1 || RC=$?
        fi
        echo "$RC" >"$T/engine-$route.rc"
    done
    VERDICT=$(python3 - "$ENGINE" "$T" <<'PY'
import re, sys
src, t = sys.argv[1], sys.argv[2]
sections = re.findall(r'^if section "([^"]*)" "(.*)"; then$', open(src).read(), re.M)
def parse(route):
    counts, cur, total = {}, None, None
    for line in open("%s/engine-%s.out" % (t, route)):
        m = re.match(r"== (.*) ==$", line.rstrip("\n"))
        if m:
            cur = m.group(1)
            counts[cur] = 0
        elif line.startswith("ok ") and cur is not None:
            counts[cur] += 1
        m = re.match(r"Results: (\d+) passed, (\d+) failed", line)
        if m:
            total = (int(m.group(1)), int(m.group(2)))
    rc = int(open("%s/engine-%s.rc" % (t, route)).read())
    return counts, total, rc
problems = []
every, total, rc = parse("all")
if rc != 0 or total is None or total[1] != 0:
    problems.append("no selector: exit %d, %s" % (rc, total))
if list(every) != [title for _, title in sections]:
    problems.append("no selector ran %s, not every section" % list(every))
if total and sum(every.values()) != total[0]:
    problems.append("no selector: section passes add up to %d, Results says %d" % (sum(every.values()), total[0]))
for route in ("execute", "scope"):
    got, rtotal, rrc = parse(route)
    want = [title for routes, title in sections if route in routes.split()]
    if rrc != 0 or rtotal is None or rtotal[1] != 0:
        problems.append("%s: exit %d, %s" % (route, rrc, rtotal))
    if list(got) != want:
        problems.append("%s ran %s, not its sections %s" % (route, list(got), want))
    for title, n in got.items():
        if every.get(title) != n:
            problems.append("%s: section [%s] passed %d, %s with no selector" % (route, title, n, every.get(title)))
print("; ".join(problems) if problems else "ok %d %d" % (len(sections), total[0]))
PY
)
    case "$VERDICT" in
        "ok "*) pass "deliver-engine_test.sh: no selector runs all ${VERDICT#ok } (sections, passes); execute and scope run only their own sections, each with the same passes" ;;
        *) fail "deliver-engine_test.sh selectors: $VERDICT" ;;
    esac
    RC=0
    OUT=$(HANDOFF_ROUTE=work-on bash "$ENGINE" 2>&1) || RC=$?
    expect_fail "deliver-engine_test.sh with a route it has no sections for" "HANDOFF_ROUTE=work-on"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
