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
#     SKILL.md runs draft-probe.sh after the session opens and before its
#     Resume Logic, whose rows read the committed status in the design's
#     order and quote the marker; Phase 4's resume check counts a stub-only
#     section as absent; Phase 5 makes no 5.3 commit and cites the commit
#     rule; Phase 6's resume check, 6.2 and 6.7 resets, 6.4 marker grep, 6.5
#     transition, 6.6 pull request reuse and serial fallback files hold
#     their shape. One more runs SKILL.md's resume-row commit block in a
#     repository with another file staged and checks that only the design
#     file is committed;
#   - real-validator cases run the `shirabe` on PATH, because what they check
#     is the validator's own verdict: `shirabe install-hooks` puts its hook in
#     the repository and `git commit` runs it, and scripts/doc-check.sh runs
#     the validator with a stand-in session store (the stubs in
#     scripts/lib/doc-check-testlib.sh, with the real shirabe first on PATH).
#     Beyond the skeleton and the Phase 4 draft, they commit the Phase 5
#     draft, run step 6.5's own transition and validate lines and commit the
#     result, take it back to Draft with 6.2's transition line, and run the
#     early-Proposed resume row's lines from SKILL.md, all under the hook.
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

# --- pins: the resume rows, Phases 4 to 6 -------------------------------------------

PHASE4="$PHASES_DIR/phase-4-architecture.md"
PHASE5="$PHASES_DIR/phase-5-security.md"
PHASE6="$PHASES_DIR/phase-6-final-review.md"
DOC_T='docs/designs/DESIGN-<topic>.md'
# The session-store calls the phase files name, as text to find. This suite
# runs no session-store command, so it holds no copy of the tool's name.
LIST_JURY='context list design-<topic> --prefix research/phase6_'
REMOVE_KEY='context remove design-<topic>'

# region <file> <start> <end>: the lines from the first one holding <start> up
# to, not including, the next one holding <end> (to the end of the file when
# none does).
region() {
    awk -v s="$2" -v e="$3" '
        !on && index($0, s) { on = 1; print; next }
        on && index($0, e) { exit }
        on { print }
    ' "$1"
}

# fenced <lang>: the first ```<lang> block of stdin, its fences dropped.
fenced() {
    local open
    open=$(printf '%s%s' '```' "$1")
    awk -v open="$open" '
        !on && $0 == open { on = 1; next }
        on && $0 == "```" { exit }
        on { print }
    '
}

# has <file> <text>...: every <text> appears in <file>.
has() {
    local f=$1 t
    shift
    for t in "$@"; do grep -qF -- "$t" "$f" || return 1; done
    return 0
}

RESUME="$WORKDIR/resume-logic"
region "$SKILL_MD" '### Resume Logic' '### Critical Requirements' > "$RESUME"

label="SKILL.md: the resume rows quote the marker exactly as design-format.md defines it"
if [ -n "$MARKER" ] && grep -qxF -- "$MARKER" "$RESUME"; then pass "$label"; else fail "$label"; fi

label="SKILL.md: the statusless row follows Accepted, and the Proposed/attached row precedes the research/phase5_security.md row"
acc=$(first_line "$RESUME" 'Design doc status "Accepted"')
nos=$(first_line "$RESUME" 'Design doc exists with no frontmatter status')
att=$(first_line "$RESUME" 'Design doc status "Proposed", opened=attached, no research/phase6_ key')
oth=$(first_line "$RESUME" 'Design doc status "Proposed", any other case')
dra=$(first_line "$RESUME" 'Design doc status "Draft"')
sec=$(first_line "$RESUME" 'key research/phase5_security.md in design-<topic>')
if [ "$acc" -gt 0 ] && [ "$nos" -gt "$acc" ] && [ "$att" -gt "$nos" ] && [ "$oth" -gt "$att" ] \
    && [ "$dra" -gt "$oth" ] && [ "$sec" -gt "$dra" ] \
    && has "$RESUME" 'Solution Architecture (not stub-only)' 'Considered Options (not stub-only)' \
    && ! grep -qF 'Offer to continue' "$RESUME"; then
    pass "$label"
else
    fail "$label (Accepted $acc, statusless $nos, attached $att, other Proposed $oth, Draft $dra, phase5 key $sec)"
fi

label="SKILL.md: the early-Proposed row transitions to Draft, prints its line, and is taken without asking under --auto or a suppressed prompt"
if has "$RESUME" "shirabe transition $DOC_T Draft" \
    'Set DESIGN-<topic>.md back to Draft: it read Proposed with no review on record; the review runs at 6.1.' \
    "$LIST_JURY" '--auto' 'suppress_status_aware_prompt=true'; then
    pass "$label"
else
    fail "$label"
fi

label="SKILL.md: the resume-row commit block names the design file as the only pathspec of both lines"
region "$SKILL_MD" '**The resume-row commit.**' '### Critical Requirements' | fenced bash > "$WORKDIR/rowcommit"
n=$(awk 'END { print NR }' "$WORKDIR/rowcommit")
if [ "$n" -eq 2 ] && [ "$(awk -v d="$DOC_T" '{ n = split($0, w, " ") } w[n] == d && w[n - 1] == "--" { c++ } END { print c + 0 }' "$WORKDIR/rowcommit")" -eq 2 ] \
    && grep -q '^git add -- ' "$WORKDIR/rowcommit" && grep -q '^git commit -m ' "$WORKDIR/rowcommit"; then
    pass "$label"
else
    fail "$label"
    show "the block" "$WORKDIR/rowcommit"
fi

label="phase 4: its resume check counts a stub-only Solution Architecture as absent"
region "$PHASE4" '## Resume Check' '## Steps' > "$WORKDIR/p4-resume"
if has "$WORKDIR/p4-resume" 'stub marker' 'counts as' 'absent'; then pass "$label"; else fail "$label"; fi

label="phase 5: no commit after 5.3, and every commit step cites the commit rule"
uncited=$(awk '{ l[NR] = $0 } END {
    for (i = 1; i <= NR; i++) if (index(l[i], "docs(design):")) {
        t = l[i] " " l[i + 1] " " l[i + 2]
        n++
        if (!index(t, "commit rule")) printf "%s ", i
    }
    if (n < 2) printf "only %d commit steps", n
}' "$PHASE5")
region "$PHASE5" '### 5.3' '## Quality Checklist' > "$WORKDIR/p5-53"
if [ -z "$uncited" ] && ! grep -qF 'docs(design):' "$WORKDIR/p5-53" && ! grep -qF 'complete security review' "$PHASE5" \
    && ! grep -qF 'not ready rather than missing' "$PHASE5"; then
    pass "$label"
else
    fail "$label (commit lines with no citation: $uncited)"
fi

label="phase 6: the resume check has no unconditional skip to 6.7 on Proposed"
region "$PHASE6" '## Resume Check' '## Steps' > "$WORKDIR/p6-resume"
draft_ln=$(first_line "$WORKDIR/p6-resume" '`Draft`: run from 6.1')
skip_ln=$(first_line "$WORKDIR/p6-resume" 'skip to step 6.7')
if [ "$draft_ln" -gt 0 ] && [ "$skip_ln" -gt "$draft_ln" ] \
    && has "$WORKDIR/p6-resume" 'opened=attached' "git diff --quiet HEAD -- $DOC_T" "git show HEAD:$DOC_T" 'Resume at' '6.6' \
    && ! grep -qF 'with status "Proposed", skip to step 6.7' "$WORKDIR/p6-resume"; then
    pass "$label"
else
    fail "$label (Draft row line $draft_ln, 6.7 row line $skip_ln)"
fi

label="phase 6: 6.2 loop_back and 6.7 Continue revising run shirabe transition $DOC_T Draft and remove research/phase6_ keys"
region "$PHASE6" '### 6.2' '### 6.3' > "$WORKDIR/p6-62"
region "$PHASE6" '**If continue-revising:**' '**If reject:**' > "$WORKDIR/p6-revise"
bad=""
for f in p6-62 p6-revise; do
    has "$WORKDIR/$f" "shirabe transition $DOC_T Draft" "$LIST_JURY" "$REMOVE_KEY" || bad="$bad $f"
done
grep -qF 'loop_back' "$WORKDIR/p6-62" || bad="$bad p6-62:loop_back"
if [ -z "$bad" ]; then pass "$label"; else fail "$label (missing in:$bad)"; fi

label="phase 6: 6.4 greps for the marker and expects Draft"
region "$PHASE6" '### 6.4' '### 6.5' > "$WORKDIR/p6-64"
if [ -n "$MARKER" ] && grep -qxF -- "grep -nxF -- '$MARKER' $DOC_T || true" "$WORKDIR/p6-64" \
    && grep -qF 'must be "Draft"' "$WORKDIR/p6-64" && ! grep -qF 'must be "Proposed"' "$WORKDIR/p6-64"; then
    pass "$label"
else
    fail "$label"
fi

label="phase 6: 6.5 runs shirabe transition $DOC_T Proposed, then shirabe validate, and its block leaves status at Draft"
region "$PHASE6" '### 6.5' '### 6.6' > "$WORKDIR/p6-65"
tr_ln=$(awk -v t="shirabe transition $DOC_T Proposed" '$0 == t { print NR; exit }' "$WORKDIR/p6-65")
va_ln=$(awk -v t="shirabe validate $DOC_T" '$0 == t { print NR; exit }' "$WORKDIR/p6-65")
if [ -n "$tr_ln" ] && [ -n "$va_ln" ] && [ "$va_ln" -gt "$tr_ln" ] \
    && grep -qx 'status: Draft' "$WORKDIR/p6-65" && ! grep -qx 'status: Proposed' "$WORKDIR/p6-65"; then
    pass "$label"
else
    fail "$label (transition line ${tr_ln:-none}, validate line ${va_ln:-none})"
fi

label="phase 6: 6.6 pushes to an open pull request instead of opening a second one"
region "$PHASE6" '### 6.6' '### 6.7' > "$WORKDIR/p6-66"
if has "$WORKDIR/p6-66" 'already has an open pull request' 'open no second one' 'commit rule'; then pass "$label"; else fail "$label"; fi

label="phase 6: the serial self-review fallback writes the same three review files the parallel seats write"
region "$PHASE6" '**Serial self-review fallback.**' '### 6.2' > "$WORKDIR/p6-fallback"
bad=""
for r in architecture security structural-format; do
    grep -qF "Write full analysis to <reviews-dir>/phase6_$r-review.md" "$PHASE6" || bad="$bad seat:$r"
    has "$WORKDIR/p6-fallback" "<reviews-dir>/phase6_$r-review.md" "research/phase6_$r-review.md" || bad="$bad fallback:$r"
done
has "$WORKDIR/p6-fallback" '--fallback' 'ingest' || bad="$bad fallback:ingest"
if [ -z "$bad" ]; then pass "$label"; else fail "$label (missing:$bad)"; fi

# --- the resume-row commit, in a repository ------------------------------------------

# row_commit <message>: run SKILL.md's resume-row commit block in $REPO, with
# its placeholders filled for topic t and <message> (the subject after
# "docs(design): "), and the caller's PATH (so a hook finds the real
# shirabe). Its exit status is kept in RC.
row_commit() {
    sed -e 's/<topic>/t/g' -e "s/<message>/$1/g" "$WORKDIR/rowcommit" > "$WORKDIR/rowcommit.sh"
    (cd "$REPO" && real bash "$WORKDIR/rowcommit.sh") > "$OUT" 2>&1
    RC=$?
}

# only_design_committed <subject>: HEAD has that subject and touches only
# $DOC, and other.txt is still staged.
only_design_committed() {
    [ "$(git -C "$REPO" log -1 --format=%s)" = "$1" ] \
        && [ "$(git -C "$REPO" show --name-only --format= HEAD)" = "$DOC" ] \
        && [ "$(git -C "$REPO" diff --cached --name-only)" = other.txt ]
}

label="resume commit: with another file staged, the row's commit lists only the design file and the other file stays staged"
if [ -s "$WORKDIR/rowcommit" ] && [ -s "$WORKDIR/freeform-skeleton.md" ]; then
    dct_repo rowcommit
    mkdir -p "$REPO/docs/designs"
    cp "$WORKDIR/freeform-skeleton.md" "$REPO/$DOC"
    dct_commit "docs(design): initialize design for t"
    printf '\nA rewrite.\n' >> "$REPO/$DOC"
    printf 'staged\n' > "$REPO/other.txt"
    git -C "$REPO" add -- other.txt
    row_commit "rewrite design for t as a Draft"
    if [ "$RC" -eq 0 ] && only_design_committed "docs(design): rewrite design for t as a Draft"; then
        pass "$label"
    else
        fail "$label (commit exit $RC)"
        show "the commit" "$OUT"
        git -C "$REPO" show --stat --format=%s HEAD > "$WORKDIR/stat" 2>&1
        show "git show --stat HEAD" "$WORKDIR/stat"
    fi
else
    fail "$label: no commit block in SKILL.md or no skeleton to commit"
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

# fm_status <file>: the frontmatter status: value.
fm_status() {
    awk '
        NR == 1 && $0 == "---" { fm = 1; next }
        fm && $0 == "---" { exit }
        fm && /^status:/ { sub(/^status:[ \t]*/, ""); print; exit }
    ' "$1"
}

# both_status <want>: the frontmatter and the body Status of $DOC in $REPO
# both read <want>.
both_status() {
    [ "$(fm_status "$REPO/$DOC")" = "$1" ] && [ "$(section_body "$REPO/$DOC" Status)" = "$1" ]
}

# add_decision: stdin with decision and rationale written right after
# problem's block, as step 6.5 writes them.
add_decision() {
    awk '
        NR == 1 && $0 == "---" { fm = 1; print; next }
        fm && inprob && !/^  / { print "decision: |"; print "  Text."; print "rationale: |"; print "  Text."; inprob = 0 }
        fm && $0 == "---" { fm = 0 }
        fm && $0 == "problem: |" { inprob = 1 }
        { print }
    '
}

# drop_decision <file>: the file with decision and rationale, and their
# blocks, taken out of the frontmatter, as the early-Proposed resume row does.
drop_decision() {
    awk '
        NR == 1 && $0 == "---" { fm = 1; print; next }
        fm && $0 == "---" { fm = 0; skip = 0 }
        fm && /^(decision|rationale):/ { skip = 1; next }
        fm && skip && /^  / { next }
        fm { skip = 0 }
        { print }
    ' "$1"
}

# phase_line <region file> <prefix>: the first line of the region that starts
# with <prefix>, its placeholders filled for topic t, in $WORKDIR/line.sh.
# Exit 1 when there is none.
phase_line() {
    awk -v p="$2" '{ l = $0; sub(/^[ \t]+/, "", l) } index(l, p) == 1 { print l; found = 1; exit } END { exit !found }' \
        "$1" > "$WORKDIR/line.raw" || return 1
    sed 's/<topic>/t/g' "$WORKDIR/line.raw" > "$WORKDIR/line.sh"
}

# run_line: run $WORKDIR/line.sh in $REPO with the real shirabe; RC keeps its
# exit status and $VAL its output.
run_line() {
    (cd "$REPO" && real bash "$WORKDIR/line.sh") > "$VAL" 2>&1
    RC=$?
}

# hook_commit <subject>: stage $DOC and commit under the hook in $REPO; RC
# keeps the exit status.
hook_commit() {
    git -C "$REPO" add -- "$DOC"
    (cd "$REPO" && real git commit -qm "$1") > "$OUT" 2>&1
    RC=$?
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
    hook_case freeform phase5 "freeform: the Phase 5 draft, Security Considerations written, commits under the validating pre-commit hook"

    # Step 6.5 in a hooked repository: the Phase 5 draft committed, decision
    # and rationale written, then the phase file's own transition and
    # validate lines, then the commit 6.6 makes.
    label="6.5: decision and rationale, then the phase file's shirabe transition line, leave both status lines Proposed, shirabe validate exits 0, and the commit passes the hook"
    if [ -s "$WORKDIR/freeform-phase5.md" ] && phase_line "$WORKDIR/p6-65" 'shirabe transition '; then
        new_repo freeform
        why=""
        (cd "$REPO" && real shirabe install-hooks) > "$OUT" 2>&1 || why="$why install-hooks"
        mkdir -p "$REPO/docs/designs"
        cp "$WORKDIR/freeform-phase5.md" "$REPO/$DOC"
        hook_commit "docs(design): add security considerations for t"
        [ "$RC" -eq 0 ] || why="$why phase-5-commit:$RC"
        add_decision < "$WORKDIR/freeform-phase5.md" > "$REPO/$DOC"
        run_line
        [ "$RC" -eq 0 ] || why="$why transition:$RC"
        cp "$VAL" "$WORKDIR/transition.out"
        both_status Proposed || why="$why status:$(fm_status "$REPO/$DOC")/$(section_body "$REPO/$DOC" Status)"
        if phase_line "$WORKDIR/p6-65" 'shirabe validate '; then
            run_line
            [ "$RC" -eq 0 ] || why="$why validate:$RC"
            ! grep -qF 'FC03' "$VAL" || why="$why FC03"
        else
            why="$why no-validate-line"
        fi
        hook_commit "docs(design): add design for t"
        [ "$RC" -eq 0 ] && git -C "$REPO" diff --quiet HEAD -- "$DOC" || why="$why 6.6-commit:$RC"
        if [ -z "$why" ]; then
            pass "$label"
        else
            fail "$label (failed:$why)"
            show "shirabe transition" "$WORKDIR/transition.out"
            show "shirabe validate" "$VAL"
            show "the last git commit" "$OUT"
        fi

        # A loop-back after 6.5 (6.7 Continue revising) on that committed
        # Proposed design, with 6.2's own transition line.
        label="loop-back: 6.2's shirabe transition line takes the committed Proposed design back to Draft in both status lines, and the commit passes the hook"
        why=""
        if [ "$(fm_status "$REPO/$DOC")" = Proposed ] && phase_line "$WORKDIR/p6-62" 'shirabe transition '; then
            run_line
            [ "$RC" -eq 0 ] || why="$why transition:$RC"
            both_status Draft || why="$why status:$(fm_status "$REPO/$DOC")/$(section_body "$REPO/$DOC" Status)"
            hook_commit "docs(design): return design for t to Draft"
            [ "$RC" -eq 0 ] || why="$why commit:$RC"
        else
            why=" no committed Proposed design or no transition line in 6.2"
        fi
        if [ -z "$why" ]; then
            pass "$label"
        else
            fail "$label (failed:$why)"
            show "shirabe transition" "$VAL"
            show "git commit" "$OUT"
        fi
    else
        fail "$label: no Phase 5 draft, or no line starting with shirabe transition in 6.5"
    fi

    # The early-Proposed resume row, with SKILL.md's own lines: transition,
    # the placeholder fields out, and the design-file-only commit block, with
    # another file staged and the hook installed.
    label="resume revert: SKILL.md's transition line and commit block take an early Proposed back to Draft under the hook, committing only the design file"
    if [ -s "$WORKDIR/freeform-phase5.md" ] && [ -s "$WORKDIR/rowcommit" ] && phase_line "$RESUME" 'shirabe transition '; then
        cp "$WORKDIR/line.sh" "$WORKDIR/resume-line.sh"
        new_repo freeform
        why=""
        (cd "$REPO" && real shirabe install-hooks) > "$OUT" 2>&1 || why="$why install-hooks"
        mkdir -p "$REPO/docs/designs"
        # An early Proposed: placeholder decision and rationale, status set by hand.
        add_decision < "$WORKDIR/freeform-phase5.md" \
            | sed -e 's/^status: Draft$/status: Proposed/' -e 's/^Draft$/Proposed/' > "$REPO/$DOC"
        hook_commit "docs(design): add design for t"
        [ "$RC" -eq 0 ] || why="$why seed-commit:$RC"
        printf 'staged\n' > "$REPO/other.txt"
        git -C "$REPO" add -- other.txt
        cp "$WORKDIR/resume-line.sh" "$WORKDIR/line.sh"
        run_line
        [ "$RC" -eq 0 ] || why="$why transition:$RC"
        cp "$VAL" "$WORKDIR/transition.out"
        drop_decision "$REPO/$DOC" > "$WORKDIR/dropped.md" && cp "$WORKDIR/dropped.md" "$REPO/$DOC"
        row_commit "return design for t to Draft"
        [ "$RC" -eq 0 ] || why="$why commit:$RC"
        only_design_committed "docs(design): return design for t to Draft" || why="$why not-design-only"
        both_status Draft || why="$why status:$(fm_status "$REPO/$DOC")/$(section_body "$REPO/$DOC" Status)"
        git -C "$REPO" show "HEAD:$DOC" > "$WORKDIR/head.md" 2>/dev/null
        ! grep -qE '^(decision|rationale):' "$WORKDIR/head.md" || why="$why placeholders-left"
        if [ -z "$why" ]; then
            pass "$label"
        else
            fail "$label (failed:$why)"
            show "shirabe transition" "$WORKDIR/transition.out"
            show "the commit block" "$OUT"
        fi
    else
        fail "$label: no Phase 5 draft, no commit block, or no line starting with shirabe transition in the Resume Logic"
    fi
fi

echo
echo "draft-skeleton_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
