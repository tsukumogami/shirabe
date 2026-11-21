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
#   - extraction cases need only bash, git and awk, so they run everywhere,
#     the bash 3.2 floor included;
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
PHASES_DIR="$ROOT_DIR/skills/design/references/phases"
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

# doccheck_case <variant> <label>: the Phase 4 draft, committed, through
# doc-check.sh pre_jury --phase 5 as Phase 5 runs it. Passes on exit 0, no
# `fail` outcome, and required-fields and status-matches-body passing.
doccheck_case() {
    local v=$1 label=$2 fails
    if [ ! -s "$WORKDIR/$v-phase4.md" ]; then
        fail "$label: no skeleton was extracted from phase-0-setup-$v.md"
        return
    fi
    new_repo "$v"
    mkdir -p "$REPO/docs/designs"
    cp "$WORKDIR/$v-phase4.md" "$REPO/$DOC"
    dct_commit "docs(design): the Phase 4 draft"
    dct_session design-t
    (cd "$REPO" && real "$DOC_CHECK" --doc "$DOC" --format design --moment pre_jury --phase 5 \
        --topic t --skill design) > "$OUT" 2> "$ERR"
    RC=$?
    fails=$(grep -c '^doc-check: [^ ]* fail$' "$OUT")
    if [ "$RC" -eq 0 ] && [ "$fails" -eq 0 ] \
        && grep -qx 'doc-check: docs/required-fields pass' "$OUT" \
        && grep -qx 'doc-check: docs/status-matches-body pass' "$OUT"; then
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
        hook_case "$v" skeleton "$v: the Phase 0 skeleton commits under the validating pre-commit hook"
        hook_case "$v" phase4 "$v: the Phase 4 draft commits under the validating pre-commit hook"
        doccheck_case "$v" "$v: the Phase 4 draft the validating pre-commit hook takes passes doc-check pre_jury --phase 5 with no fail line"
    done
fi

echo
echo "draft-skeleton_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
