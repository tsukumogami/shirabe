#!/usr/bin/env bash
# lead-shape-text_test.sh -- /deliver's lead-shape text, pinned phrase by phrase
# Part of the deliver skill
#
# Under --auto, /deliver hands its /scope call to a scope agent; under
# --interactive it calls /scope itself. That split is prose the owning session
# follows: no koto state or gate enforces it, so this pins the prose. Each
# phrase is checked as a fixed, case-sensitive substring (grep -F) of the named
# text -- the `## scope_run` section of koto-templates/deliver.md, and the
# "Running the Workflow" section of SKILL.md -- after the text is joined into
# one line, so a rewrap cannot break a phrase in two. A missing phrase fails
# the suite with the phrase named.
#
# It asserts:
#
#   the scope_run directive hands the /scope Skill call, with exactly the
#     arguments it builds, to one foreground scope agent under `auto`; says
#     what the scope agent is told (ten lines the run doesn't use, no settings
#     or credential reads, /scope's children's agents spawn nothing beyond the
#     pattern reference's exception); invokes the Skill tool directly under
#     `interactive`; and keeps the `child_returned: yes` path;
#   SKILL.md's Running the Workflow states the same split and names the lead
#     shape;
#
# and, so the check is known to bite, that a copy of the section without the
# scope-agent phrase is reported missing it.
#
# Usage: lead-shape-text_test.sh
# Exit codes: 0 all pass, 1 a failure

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)

SKILL_MD="$SKILL_DIR/SKILL.md"
TEMPLATE="$SKILL_DIR/koto-templates/deliver.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/deliver-lead-shape-text-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# section <file> <heading line> -> the lines from that exact heading up to the
# next heading of the same or a higher level. Lines inside ``` fences are never
# headings, so a `# comment` in a code block doesn't end the section.
section() {
    awk -v h="$2" '
        /^```/ { fence = !fence }
        !on && !fence && $0 == h { on = 1; level = index(h, " ") - 1; print; next }
        on && !fence && /^#+ / { if (index($0, " ") - 1 <= level) exit }
        on { print }
    ' "$1"
}

# flat <file> -> the file as one line, runs of whitespace squeezed to a space
flat() { tr '\n\t' '  ' < "$1" | tr -s ' '; }

# missing <flat text file> <phrase file> -> each phrase the text lacks, one per line
missing() {
    local phrase
    while IFS= read -r phrase; do
        [ -n "$phrase" ] || continue
        grep -qF -- "$phrase" "$1" || printf '%s\n' "$phrase"
    done < "$2"
}

# check <label> <flat text file> <phrase file>
check() {
    local label="$1" text="$2" phrases="$3" phrase gone
    gone=$(missing "$text" "$phrases")
    while IFS= read -r phrase; do
        [ -n "$phrase" ] || continue
        if grep -qxF -- "$phrase" <<<"$gone"; then
            fail "$label is missing the phrase [$phrase]"
        else
            pass "$label has [$phrase]"
        fi
    done < "$phrases"
}

for f in "$SKILL_MD" "$TEMPLATE"; do
    [ -f "$f" ] || fail "missing file: $f"
done
if [ "$FAIL_COUNT" -ne 0 ]; then
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    exit 1
fi

# --- the texts --------------------------------------------------------------------

# deliver.md's front matter holds the states; the directives follow it, and the
# `## scope_run` heading there is the directive's.
section "$TEMPLATE" "## scope_run" > "$WORK/scope_run.md"
flat "$WORK/scope_run.md" > "$WORK/scope_run.flat"
section "$SKILL_MD" "## Running the Workflow" > "$WORK/running.md"
flat "$WORK/running.md" > "$WORK/running.flat"

if [ -s "$WORK/scope_run.md" ] && [ "$(wc -l < "$WORK/scope_run.md")" -gt 5 ]; then
    pass "deliver.md has a ## scope_run directive"
else
    fail "deliver.md has no ## scope_run directive to check"
fi
if [ -s "$WORK/running.md" ] && [ "$(wc -l < "$WORK/running.md")" -gt 5 ]; then
    pass "SKILL.md has a ## Running the Workflow section"
else
    fail "SKILL.md has no ## Running the Workflow section to check"
fi

# --- the scope_run directive -------------------------------------------------------

cat > "$WORK/scope_run.txt" <<'EOF'
`{{TOPIC}} --intent=continue --{{MODE}} --koto-leg={{REQ}}:scope`
which reads `{{MODE}}`
**`auto`** -- the lead shape: hand the /scope Skill call, with exactly the arguments above, to one scope agent started in the foreground in this checkout
Make no /scope call in this session.
**`interactive`** -- invoke the Skill tool with skill `scope` and the arguments above directly in this session
run the /scope Skill call above to its terminal
never open, read or search a settings or credential file
spawn nothing further, except where `references/parent-skill-pattern.md` names an exception
return at most ten lines
None of those lines is used by this run: the owning session ticks `deliver-{{TOPIC}}` to read the leg and reads the PLAN and the scoping documents from disk.
Submit `child_returned: yes` only when the /scope Skill call has returned (or, under `auto`, the scope agent has returned) and `koto next` still reports the leg open
That reaches only an error, `deliver:child-absent`.
EOF
check "the scope_run directive" "$WORK/scope_run.flat" "$WORK/scope_run.txt"

# --- SKILL.md's Running the Workflow ---------------------------------------------------

cat > "$WORK/running.txt" <<'EOF'
lead shape
the owning session hands the `/scope` Skill call, with exactly the arguments the directive builds, to one scope agent started in the foreground in the same checkout
returns at most ten lines, none of which the run uses
ticks `deliver-<topic>` to read the leg and reads the PLAN and the scoping documents from disk
Under `--interactive` the owning session invokes `/scope` itself
`child_returned: yes`
EOF
check "SKILL.md's Running the Workflow" "$WORK/running.flat" "$WORK/running.txt"

# --- the check bites ----------------------------------------------------------------

# WANT is the scope-agent line of scope_run.txt above, verbatim: reword one
# and the other has to follow.
sed 's/to one scope agent started in the foreground/to a helper/' "$WORK/scope_run.flat" > "$WORK/scope_run-mutated.flat"
GONE=$(missing "$WORK/scope_run-mutated.flat" "$WORK/scope_run.txt")
WANT='**`auto`** -- the lead shape: hand the /scope Skill call, with exactly the arguments above, to one scope agent started in the foreground in this checkout'
if cmp -s "$WORK/scope_run.flat" "$WORK/scope_run-mutated.flat"; then
    fail "the mutation did not change the directive; its phrase no longer matches"
elif grep -qxF -- "$WANT" <<<"$GONE"; then
    pass "a directive without the scope-agent phrase is reported missing it"
else
    fail "a directive without the scope-agent phrase was not reported"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
