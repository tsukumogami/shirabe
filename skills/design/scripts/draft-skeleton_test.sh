#!/usr/bin/env bash
# draft-skeleton_test.sh -- does the DESIGN skeleton /design writes at Phase 0
# commit under a validating pre-commit hook, and does the draft Phase 4 leaves
# behind pass the pre-jury document check Phase 5 runs?
#
# The skeleton is read from the phase files themselves, so the suite checks
# the prose an agent follows, not a copy of it: for each of
# skills/design/references/phases/phase-0-setup-freeform.md and
# phase-0-setup-prd.md, the first ```markdown block under the "Create Design
# Doc Skeleton" heading. Its placeholders are filled (<Topic> is Probe,
# <topic> and <name> are t, any other <...> is "Text."), and it is written to
# docs/designs/DESIGN-t.md in a throwaway repository. The PRD variant keeps
# its upstream: line and has docs/prds/PRD-t.md committed beside it.
#
# "The Phase 4 draft" is that skeleton with Considered Options, Decision
# Outcome, Solution Architecture, Implementation Approach and Consequences
# written (each section's body replaced by "Text.", or the section appended
# when the skeleton lacks it), Security Considerations left as the skeleton
# has it, and the frontmatter left as the skeleton leaves it.
#
# Two kinds of case:
#
#   - extraction and pin cases need only bash, git and awk, so they run
#     everywhere, the bash 3.2 floor included. The pins hold the prose to one
#     shape: the stub marker is defined once, in a ```text block under "The
#     stub marker" in skills/design/references/design-format.md, and every
#     copy of it (the Phase 0 skeletons, draft-probe.sh's probe document) is
#     that line exactly; the skeletons hold status Draft, problem and the nine
#     sections in order; the skeleton commit comes before the summary key;
#     and SKILL.md runs draft-probe.sh after the session opens and before its
#     Resume Logic;
#   - real-validator cases run the `shirabe` on PATH, because what they check
#     is the validator's own verdict: `shirabe install-hooks` puts its hook in
#     the repository and `git commit` runs it, and scripts/doc-check.sh runs
#     the validator with a stand-in session store (the stubs in
#     scripts/lib/doc-check-testlib.sh, with the real shirabe first on PATH).
#     They need a shirabe that accepts a design at status Draft: without one
#     they SKIP with a notice, and with DESIGN_REQUIRE_SHIRABE=1 (the Linux
#     job that builds it) a missing or older validator is a failure, so CI
#     can't report green having asserted nothing.
#
# Doc-check outcomes are asserted by name, never by exit code alone: a failed
# canary turns every rule to `error` with exit 0.
#
# Usage: draft-skeleton_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd -P)
DESIGN_DIR="$ROOT_DIR/skills/design"
PHASES_DIR="$DESIGN_DIR/references/phases"
FORMAT_REF="$DESIGN_DIR/references/design-format.md"
SKILL_MD="$DESIGN_DIR/SKILL.md"
PROBE="$SCRIPT_DIR/draft-probe.sh"
SECTIONS="Status|Context and Problem Statement|Decision Drivers|Considered Options|Decision Outcome|Solution Architecture|Implementation Approach|Security Considerations|Consequences"
UNREACHED=("Considered Options" "Decision Outcome" "Solution Architecture" "Implementation Approach" "Security Considerations" "Consequences")
DOC_CHECK="$ROOT_DIR/scripts/doc-check.sh"
DOC=docs/designs/DESIGN-t.md

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
# show <title> <file>: a captured output, indented under the FAIL line.
show() {
    printf '  %s:\n' "$1"
    if [ -s "$2" ]; then sed 's/^/    /' "$2"; else echo "    (empty)"; fi
}

for tool in git jq awk sed; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -x "$DOC_CHECK" ] || { echo "$DOC_CHECK is missing or not executable" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/draft-skeleton-test.XXXXXX") || exit 2
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 2
cleanup() { case "${WORKDIR:-}" in */draft-skeleton-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
trap cleanup EXIT

# Read before the testlib puts its stub shirabe first on PATH.
REAL_SHIRABE=$(command -v shirabe 2>/dev/null || true)

# shellcheck source=../../../scripts/lib/doc-check-testlib.sh
. "$ROOT_DIR/scripts/lib/doc-check-testlib.sh"
dct_setup "$WORKDIR"

# real <command...>: run with the caller's PATH, so `shirabe` is the real one
# (the testlib's stub is first on PATH otherwise). The stand-in session store
# stays in place through the exported KOTO_BIN.
real() { PATH="$DCT_ORIG_PATH" "$@"; }

OUT="$WORKDIR/out"
ERR="$WORKDIR/err"
VAL="$WORKDIR/validate"
RC=0

# --- the skeleton, from the phase files ----------------------------------------

# extract_skeleton <phase file>: the first ```markdown block under the
# "Create Design Doc Skeleton" heading, its fences dropped. Exit 1 when the
# heading is missing, when another heading comes before the block opens, or
# when the block never closes.
extract_skeleton() {
    awk '
        !under && /^#+[ \t]+[0-9.]*[ \t]*Create Design Doc Skeleton[ \t]*$/ { under = 1; next }
        under && !inblock && /^#+[ \t]/ { exit }
        under && !inblock && $0 == "```markdown" { inblock = 1; next }
        inblock && $0 == "```" { done = 1; exit }
        inblock { print }
        END { exit done ? 0 : 1 }
    ' "$1"
}

# fill_placeholders: stdin with its placeholders filled in.
fill_placeholders() {
    sed -e 's/<Topic>/Probe/g' -e 's/<topic>/t/g' -e 's/<name>/t/g' -e 's/<[^>]*>/Text./g'
}

# to_phase4: stdin with the five sections Phases 3 and 4 write written.
to_phase4() {
    awk '
        BEGIN {
            n = split("Considered Options|Decision Outcome|Solution Architecture|Implementation Approach|Consequences", want, "|")
            for (i = 1; i <= n; i++) w[want[i]] = 1
        }
        /^## / {
            name = substr($0, 4)
            sub(/[ \t]+$/, "", name)
            filling = (name in w)
            if (filling) { seen[name] = 1; print; print ""; print "Text."; print ""; next }
        }
        filling { next }
        { print }
        END {
            for (i = 1; i <= n; i++) {
                if (!(want[i] in seen)) { print ""; print "## " want[i]; print ""; print "Text." }
            }
        }
    '
}

VARIANTS="freeform prd"
for v in $VARIANTS; do
    src="$PHASES_DIR/phase-0-setup-$v.md"
    label="$v: the Create Design Doc Skeleton heading in phase-0-setup-$v.md holds a markdown block"
    if [ ! -f "$src" ]; then
        fail "$label: $src is missing"
    elif extract_skeleton "$src" > "$WORKDIR/raw-$v.md" && [ -s "$WORKDIR/raw-$v.md" ]; then
        fill_placeholders < "$WORKDIR/raw-$v.md" > "$WORKDIR/$v-skeleton.md"
        to_phase4 < "$WORKDIR/$v-skeleton.md" > "$WORKDIR/$v-phase4.md"
        pass "$label"
    else
        fail "$label: no line equal to \`\`\`markdown, closed by a line equal to \`\`\`, follows the heading before the next heading"
    fi
done

# --- pins: the stub marker and its copies ----------------------------------------

# format_marker: the non-blank lines of the ```text blocks under the "The stub
# marker" heading of design-format.md, up to the next heading.
format_marker() {
    awk '
        !under && /^#+[ \t]+The stub marker[ \t]*$/ { under = 1; next }
        under && !inblock && /^#+[ \t]/ { exit }
        under && !inblock && $0 == "```text" { inblock = 1; next }
        inblock && $0 == "```" { inblock = 0; next }
        inblock && NF { print }
    ' "$FORMAT_REF"
}

# section_body <file> <name>: the non-blank lines of section "## <name>".
section_body() {
    awk -v want="$2" '
        /^## / { name = substr($0, 4); sub(/[ \t]+$/, "", name); on = (name == want); next }
        on && NF { print }
    ' "$1"
}

# headings <file>: the "## " headings, joined with "|".
headings() {
    awk '/^## / { name = substr($0, 4); sub(/[ \t]+$/, "", name); printf "%s%s", sep, name; sep = "|" } END { print "" }' "$1"
}

# frontmatter_keys <file>: the top-level frontmatter keys, space-separated.
frontmatter_keys() {
    awk '
        NR == 1 && $0 == "---" { fm = 1; next }
        fm && $0 == "---" { exit }
        fm && /^[A-Za-z_][A-Za-z0-9_]*:/ { k = $0; sub(/:.*/, "", k); printf "%s%s", sep, k; sep = " " }
        END { print "" }
    ' "$1"
}

# first_line <file> <text>: the number of the first line holding <text>, or 0.
first_line() {
    awk -v p="$2" 'index($0, p) { print NR; found = 1; exit } END { if (!found) print 0 }' "$1"
}

# last_line <file> <text>: the number of the last line holding <text>, or 0.
last_line() {
    awk -v p="$2" 'index($0, p) { n = NR } END { print n + 0 }' "$1"
}

MARKER=""
label="marker: design-format.md defines exactly one stub marker line"
format_marker > "$WORKDIR/marker" 2>/dev/null
n=$(awk 'END { print NR }' "$WORKDIR/marker")
if [ "$n" -eq 1 ]; then
    MARKER=$(cat "$WORKDIR/marker")
    copies=$(grep -cxF -- "$MARKER" "$FORMAT_REF")
    if [ "$copies" -eq 1 ]; then
        pass "$label"
    else
        fail "$label: the line appears $copies times in design-format.md, not once"
    fi
else
    fail "$label: the text block under The stub marker holds $n non-blank lines, not one"
    show "found" "$WORKDIR/marker"
fi

if [ -n "$MARKER" ]; then
    label="marker: every line under skills/design that starts like the marker is the marker exactly"
    prefix=${MARKER%%:*}
    find "$DESIGN_DIR" -type f \( -name '*.md' -o -name '*.sh' \) -exec awk -v p="$prefix" -v m="$MARKER" \
        'index($0, p) == 1 && $0 != m { print FILENAME ":" FNR ": " $0 }' {} + > "$WORKDIR/drift"
    if [ ! -s "$WORKDIR/drift" ]; then
        pass "$label"
    else
        fail "$label"
        show "lines that differ from the marker" "$WORKDIR/drift"
    fi

    label="draft-probe.sh: its probe document carries the same marker, under each of the six unreached sections"
    copies=$(grep -cxF -- "$MARKER" "$PROBE" 2>/dev/null)
    if [ "${copies:-0}" -eq 6 ] && grep -qx 'status: Draft' "$PROBE" && ! grep -q '^upstream:' "$PROBE"; then
        pass "$label"
    else
        fail "$label: the marker appears ${copies:-0} times (want 6), with status: Draft and no upstream:"
    fi
fi

for v in $VARIANTS; do
    raw="$WORKDIR/raw-$v.md"
    [ -s "$raw" ] || continue
    if [ "$v" = prd ]; then
        want_keys="schema status problem upstream"
        label="prd: the skeleton holds status Draft, problem, a Draft body Status and the nine sections in order, with upstream after problem"
    else
        want_keys="schema status problem"
        label="freeform: the skeleton holds status Draft, problem, a Draft body Status and the nine sections in order"
    fi
    keys=$(frontmatter_keys "$raw")
    got_sections=$(headings "$raw")
    body_status=$(section_body "$raw" Status)
    if [ "$keys" = "$want_keys" ] && grep -qx 'status: Draft' "$raw" && grep -qx 'problem: |' "$raw" \
        && [ "$body_status" = Draft ] && [ "$got_sections" = "$SECTIONS" ]; then
        pass "$label"
    else
        fail "$label"
        printf '  frontmatter keys: %s (want %s)\n  body Status: %s\n  sections: %s\n' \
            "$keys" "$want_keys" "$body_status" "$got_sections"
    fi

    label="$v: each of the six unreached sections' whole body is the marker"
    if [ -z "$MARKER" ]; then
        fail "$label: design-format.md defines no single marker line to compare with"
        continue
    fi
    bad=""
    for s in "${UNREACHED[@]}"; do
        [ "$(section_body "$raw" "$s")" = "$MARKER" ] || bad="$bad${bad:+, }$s"
    done
    if [ -z "$bad" ]; then pass "$label"; else fail "$label: not so for $bad"; fi
done

# --- pins: Phase 0 and SKILL.md ----------------------------------------------------

for v in $VARIANTS; do
    src="$PHASES_DIR/phase-0-setup-$v.md"
    [ -f "$src" ] || continue
    label="phase 0 ($v): the file no longer says the skeleton has no status"
    if grep -qF 'no `status:` on purpose' "$src"; then fail "$label"; else pass "$label"; fi

    label="phase 0 ($v): the skeleton commit comes after the skeleton and before the summary key is written"
    skel=$(first_line "$src" "Create Design Doc Skeleton")
    first_commit=$(first_line "$src" "docs(design): initialize design for")
    last_commit=$(last_line "$src" "docs(design): initialize design for")
    key=$(first_line "$src" "Write the Summary Key")
    if [ "$skel" -gt 0 ] && [ "$first_commit" -gt "$skel" ] && [ "$key" -gt 0 ] && [ "$last_commit" -lt "$key" ] \
        && grep -qF 'references/doc-check-steps.md' "$src"; then
        pass "$label"
    else
        fail "$label (skeleton heading line $skel, commit lines $first_commit-$last_commit, summary key heading line $key, or no citation of the commit rule)"
    fi
done

label="SKILL.md: the probe runs after skill-session.sh open and before the Resume Logic, and the run keeps the opened= line"
open_ln=$(first_line "$SKILL_MD" 'skill-session.sh" open design')
probe_ln=$(first_line "$SKILL_MD" 'skills/design/scripts/draft-probe.sh"')
resume_ln=$(first_line "$SKILL_MD" '### Resume Logic')
if [ "$open_ln" -gt 0 ] && [ "$probe_ln" -gt "$open_ln" ] && [ "$resume_ln" -gt "$probe_ln" ] \
    && grep -qF 'opened=attached' "$SKILL_MD" && grep -qF 'opened=new' "$SKILL_MD"; then
    pass "$label"
else
    fail "$label (open line $open_ln, probe line $probe_ln, Resume Logic line $resume_ln)"
fi

# --- fixtures ---------------------------------------------------------------------

# new_repo <variant>: a fresh repository in $REPO (the testlib's dct_repo); the
# prd variant also has the PRD its skeleton's upstream: names, committed.
new_repo() {
    dct_repo "$1"
    if [ "$1" = prd ]; then
        mkdir -p "$REPO/docs/prds"
        printf -- '---\nschema: prd/v1\nstatus: In Progress\nproblem: |\n  Text.\n---\n\n# PRD: Probe\n\n## Status\n\nIn Progress\n' \
            > "$REPO/docs/prds/PRD-t.md"
        dct_commit "docs(prd): the upstream PRD"
    fi
}

# validator_output: the real validator's human report on $DOC in $REPO.
validator_output() {
    (cd "$REPO" && real shirabe validate --format human -- "$DOC") > "$VAL" 2>&1
}

# --- the real-validator gate ------------------------------------------------------

# A shirabe that refuses a design at status Draft, or has no install-hooks,
# can't give the verdicts these cases ask for, so it counts as missing.
run_real=0
if [ -n "$REAL_SHIRABE" ]; then
    probe="$WORKDIR/probe"
    mkdir -p "$probe/docs/designs"
    git -C "$probe" init -q
    {
        printf -- '---\nschema: design/v1\nstatus: Draft\nproblem: |\n  Text.\n---\n\n# DESIGN: Probe\n\n## Status\n\nDraft\n'
        for s in "Context and Problem Statement" "Decision Drivers" "Considered Options" "Decision Outcome" \
            "Solution Architecture" "Implementation Approach" "Security Considerations" "Consequences"; do
            printf '\n## %s\n\nText.\n' "$s"
        done
    } > "$probe/docs/designs/DESIGN-probe.md"
    if (cd "$probe" && real shirabe validate --format human -- docs/designs/DESIGN-probe.md) >/dev/null 2>&1 \
        && real shirabe install-hooks --help >/dev/null 2>&1; then
        run_real=1
    fi
fi
if [ "$run_real" -eq 1 ]; then
    :
elif [ "${DESIGN_REQUIRE_SHIRABE:-}" = 1 ]; then
    fail "no shirabe on PATH that accepts a design at status Draft and has install-hooks, and DESIGN_REQUIRE_SHIRABE=1: the real-validator cases can't run"
elif [ -n "$REAL_SHIRABE" ]; then
    echo "SKIP: the shirabe on PATH refuses a design at status Draft -- the real-validator cases did not run"
else
    echo "SKIP: shirabe not on PATH -- the real-validator cases did not run"
fi

# --- real-validator cases ---------------------------------------------------------

# hook_case <variant> <stage> <label>: commit the <stage> document (skeleton or
# phase4) under the hook `shirabe install-hooks` writes. Passes when the commit
# lands holding the document as written.
hook_case() {
    local v=$1 stage=$2 label=$3 src
    src="$WORKDIR/$v-$stage.md"
    if [ ! -s "$src" ]; then
        fail "$label: no skeleton was extracted from phase-0-setup-$v.md"
        return
    fi
    new_repo "$v"
    if ! (cd "$REPO" && real shirabe install-hooks) > "$OUT" 2>&1; then
        fail "$label: shirabe install-hooks failed"
        show "shirabe install-hooks" "$OUT"
        return
    fi
    mkdir -p "$REPO/docs/designs"
    cp "$src" "$REPO/$DOC"
    git -C "$REPO" add -- "$DOC"
    (cd "$REPO" && real git commit -qm "docs(design): initialize design for t") > "$OUT" 2>&1
    RC=$?
    if [ "$RC" -eq 0 ] && git -C "$REPO" cat-file -e "HEAD:$DOC" 2>/dev/null \
        && git -C "$REPO" diff --quiet HEAD -- "$DOC"; then
        pass "$label"
    else
        fail "$label (git commit exit $RC)"
        show "git commit, with the hook's validator output" "$OUT"
    fi
}

# validate_case <variant> <label>: the skeleton as written, in a repository
# that holds what its upstream: names, through a plain shirabe validate.
# Passes on exit 0 with no FC24 notice: the frontmatter keys are in order,
# upstream after problem.
validate_case() {
    local v=$1 label=$2
    if [ ! -s "$WORKDIR/$v-skeleton.md" ]; then
        fail "$label: no skeleton was extracted from phase-0-setup-$v.md"
        return
    fi
    new_repo "$v"
    mkdir -p "$REPO/docs/designs"
    cp "$WORKDIR/$v-skeleton.md" "$REPO/$DOC"
    validator_output
    RC=$?
    if [ "$RC" -eq 0 ] && ! grep -qF '[FC24]' "$VAL"; then
        pass "$label"
    else
        fail "$label (shirabe validate exit $RC)"
        show "shirabe validate --format human $DOC" "$VAL"
    fi
}

# doccheck_case <variant> <stage> <phase> <label>: the <stage> draft,
# committed, through doc-check.sh pre_jury --phase <phase> as that phase runs
# it. Passes on exit 0, no `fail` outcome, and required-fields,
# status-matches-body and required-sections passing.
doccheck_case() {
    local v=$1 stage=$2 phase=$3 label=$4 fails
    if [ ! -s "$WORKDIR/$v-$stage.md" ]; then
        fail "$label: no skeleton was extracted from phase-0-setup-$v.md"
        return
    fi
    new_repo "$v"
    mkdir -p "$REPO/docs/designs"
    cp "$WORKDIR/$v-$stage.md" "$REPO/$DOC"
    dct_commit "docs(design): the $stage draft"
    dct_session design-t
    (cd "$REPO" && real "$DOC_CHECK" --doc "$DOC" --format design --moment pre_jury --phase "$phase" \
        --topic t --skill design) > "$OUT" 2> "$ERR"
    RC=$?
    fails=$(grep -c '^doc-check: [^ ]* fail$' "$OUT")
    if [ "$RC" -eq 0 ] && [ "$fails" -eq 0 ] \
        && grep -qx 'doc-check: docs/required-fields pass' "$OUT" \
        && grep -qx 'doc-check: docs/status-matches-body pass' "$OUT" \
        && grep -qx 'doc-check: docs/required-sections pass' "$OUT" \
        && ! grep -qE '^(decision|rationale):' "$REPO/$DOC"; then
        pass "$label"
    else
        fail "$label (doc-check exit $RC, $fails fail lines)"
        show "doc-check output" "$OUT"
        show "doc-check stderr" "$ERR"
        validator_output
        show "shirabe validate --format human $DOC" "$VAL"
    fi
}

if [ "$run_real" -eq 1 ]; then
    for v in $VARIANTS; do
        validate_case "$v" "$v: the skeleton as written validates with exit 0 and no FC24"
        hook_case "$v" skeleton "$v: the Phase 0 skeleton commits under the validating pre-commit hook"
        hook_case "$v" phase4 "$v: the Phase 4 draft commits under the validating pre-commit hook"
        doccheck_case "$v" phase4 5 "$v: the Phase 4 draft the validating pre-commit hook takes passes doc-check pre_jury --phase 5 with no fail line"
    done
    # Phase 5 written: Security Considerations' marker replaced too.
    if [ -s "$WORKDIR/freeform-phase4.md" ]; then
        awk '
            /^## / {
                name = substr($0, 4); sub(/[ \t]+$/, "", name); skip = 0
                if (name == "Security Considerations") { print; print ""; print "Text."; print ""; skip = 1; next }
            }
            skip { next }
            { print }
        ' "$WORKDIR/freeform-phase4.md" > "$WORKDIR/freeform-phase5.md"
    fi
    doccheck_case freeform phase5 6 "freeform: doc-check pre_jury --phase 6 on the Draft design with Security Considerations written exits 0 with no decision or rationale"
    # Still stubbed: doc-check and FC04 read the marker as a written section,
    # which is why step 6.4 greps for the marker.
    doccheck_case freeform phase4 6 "freeform: doc-check pre_jury --phase 6 with Security Considerations still stubbed exits 0"
fi

echo
echo "draft-skeleton_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
