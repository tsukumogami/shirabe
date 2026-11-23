#!/usr/bin/env bash
# pre-pr-evidence_test.sh — a placeholder must not satisfy an obligation.
#
# The pre-PR evidence is the record a run writes at `finalization` before a pull
# request exists: summary.md with its `## Changes Made` section, pre_pr.md with
# the cleanup commit and the design-diagram referent, and the run's commits.
# Prose asking for cleanup, a summary shape, a commit convention and a diagram
# update could not detect its own omission, so finalization's ready_for_pr edge
# checks the record with gates. The risk in replacing prose with evidence is
# replacing it with evidence that anything satisfies: koto's evidence schema has
# no way to constrain a string, so a `type: string` field is satisfied by
# "done" and the obligation is unenforced in substance while looking enforced in
# the record.
#
# So the cases that matter here are the placeholder ones. Each drives the SHIPPED
# finalization state with a referent a careless run would write and requires it
# not to reach pr_precheck. A referent can also be shaped right and name nothing
# (shirabe#422): a mistyped sha, a commit from another branch, a diagram path
# that was never written. The fixture repository has real commits so those cases
# fail on existence, and the gate that held is read back from the response's
# blocking conditions.
#
# These checks used to sit on a later state, pre_pr_evidence, which ended the run
# at done_blocked on a failure. That state is gone; finalization runs the same
# gates and holds on a failure, so each case here expects either pr_precheck or a
# hold at finalization naming the gate. finalization-shape_test.sh walks the
# whole template to finalization and checks the hold is fixed in place;
# this suite drives the state alone, in a fixture, to cover the referent forms.
#
# Usage: pre-pr-evidence_test.sh
# Exit codes: 0 all pass, 1 any failed, 0 with a skip notice when koto is absent.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { echo -e "${YELLOW}SKIP${NC}: $*"; }

TMPS=()
SESSIONS=()
# Ends with an explicit success. The last command in this trap is a test that is
# FALSE when the arrays are empty, which under `set -e` would replace this
# script's own exit status -- a clean `exit 0` on the skip path coming back as 1,
# with every line printed saying it had passed.
#
# It never did so HERE. This file runs `set -uo pipefail` with no -e, and
# measured against the pre-fix version with koto absent it exits 0. The shape was
# present and could not fire; adding -e is what would make it fire, which is the
# useful thing for the next author to know. cascade-chaining_test.sh, which sets
# -euo pipefail, is where it actually bit.
#
# The trigger is `set -e` and not any shell version: bash 5.2 and 3.2 behave
# identically.
cleanup() {
    for w in "${SESSIONS[@]:-}"; do [[ -n "$w" ]] && koto cancel "$w" >/dev/null 2>&1; done
    for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done
    return 0
}
ktg_on_exit cleanup

if ! command -v koto >/dev/null 2>&1; then
    skip "koto not on PATH; finalization cannot be driven without the engine"
    exit 0
fi
[[ -f "$TEMPLATE" ]] || { echo "template not found: $TEMPLATE"; exit 2; }

# Keep every session out of the developer's real ~/.koto: a case that reaches a
# terminal with --no-cleanup is retained, and koto cancel does not remove it.
KOTO_HOME=$(mktemp -d); TMPS+=("$KOTO_HOME")
export HOME="$KOTO_HOME"

extract_state() {
    local name="$1"
    awk -v want="  $name:" '
        $0 == want { found=1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        found { print }
    ' "$TEMPLATE"
}

FINALIZATION=$(extract_state finalization)
[[ -n "$FINALIZATION" ]] || { echo "finalization not found in $TEMPLATE"; exit 2; }

# The referent gates run check-pre-pr-referents.sh through PLUGIN_ROOT. koto
# rejects a variable value outside ^[a-zA-Z0-9._/:@ \-]*$, so a checkout under
# such a path is reached through a symlink (as in finalization-shape_test.sh).
PLUGIN_ROOT=$(cd "$SKILL_DIR/../.." && pwd)
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*)
        link_dir=$(mktemp -d) || exit 1; TMPS+=("$link_dir")
        ln -s "$PLUGIN_ROOT" "$link_dir/plugin"
        PLUGIN_ROOT="$link_dir/plugin"
        ;;
esac

# The commit_convention gate runs check-branch-output.sh --commits over the
# run's own commits (impl_base..HEAD), and the referent gates run git against
# the working directory too. Stubbing them would remove the cases that exercise
# a real command, so instead each run happens in a throwaway repository whose
# commits the case chooses: the tip's message, and optionally an earlier one
# below it. impl_base is the root commit, recorded in context as analysis would.
# The repository holds the design doc the good record names, and a side branch
# whose commit is not on the working branch.
#
# Every target finalization names is a stub terminal; the cases only care
# whether ready_for_pr reaches pr_precheck or holds.
build_fixture() {
    local dir="$1"
    cat > "$dir/fixture.md" <<FIXTURE
---
name: pre-pr-evidence-fixture
version: "1.0"
description: Fixture exercising the pre-PR evidence checks at finalization.
initial_state: start
variables:
  PLUGIN_ROOT:
    description: shirabe checkout the referent gates run their script from
    required: true
states:
  start:
    transitions:
      - target: finalization
$FINALIZATION
  implementation:
    terminal: true
  check_exit:
    terminal: true
    failure: true
    accepts:
      failure_reason:
        type: string
  deferral_approval:
    terminal: true
  pr_precheck:
    terminal: true
---

## start
Stand-in for pass_counting.

## finalization
Write the summary and the pre-PR record.

## implementation
Stub terminal.

## check_exit
Stub terminal.

## deferral_approval
Stub terminal.

## pr_precheck
Stub terminal standing in for the pull-request path.
FIXTURE
}

# land <session> <commit-message> <summary-body> <pre_pr-body> <evidence-json> [<earlier-message>]
#
# In the pre_pr body, @HEAD@ is replaced by the fixture's tip sha, @HEAD7@ by
# its first seven characters and @OTHER@ by the side branch's tip, since none
# exists until the repository is built. Prints the response to the submission.
land() {
    local session="$1" subject="$2" summary="$3" prepr="$4" data="$5" earlier="${6:-}"
    local repo; repo=$(mktemp -d) || exit 1; TMPS+=("$repo")
    build_fixture "$repo"
    (
        cd "$repo" || exit 1
        git init -q -b main .
        git config user.email t@example.invalid
        git config user.name t
        git commit -q --allow-empty -m init
        git checkout -q -b other
        git commit -q --allow-empty -m "side work"
        git checkout -q main
        [ -z "$earlier" ] || git commit -q --allow-empty -m "$earlier"
        mkdir -p docs/designs
        echo x > f.txt
        echo diagram > docs/designs/DESIGN-thing.md
        git add f.txt docs
        git commit -qm "$subject"
    ) >/dev/null 2>&1
    local head other base
    head=$(git -C "$repo" rev-parse main)
    base=$(git -C "$repo" rev-list --max-parents=0 main)
    other=$(git -C "$repo" rev-parse other)
    prepr=${prepr//@HEAD@/$head}
    prepr=${prepr//@HEAD7@/${head:0:7}}
    prepr=${prepr//@OTHER@/$other}
    (
        cd "$repo" || exit 1
        koto init "$session" --template "$repo/fixture.md" \
            --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1 || exit 1
        printf '%s\n' "$summary" | koto context add "$session" summary.md >/dev/null 2>&1
        printf '%s\n' "$prepr" | koto context add "$session" pre_pr.md >/dev/null 2>&1
        printf '%s\n' "$base" | koto context add "$session" impl_base >/dev/null 2>&1
        koto next "$session" >/dev/null 2>&1 || true
        koto next "$session" --with-data "$data" --no-cleanup 2>/dev/null
    )
    SESSIONS+=("$session")
}

# expect_hold <label> <gate> <response>: held at finalization, naming <gate>.
expect_hold() {
    if grep -q '"state":"pr_precheck"' <<<"$3"; then
        fail "$1: reached pr_precheck -- the obligation is unenforced in substance"
    elif ! grep -q '"state":"finalization"' <<<"$3"; then
        fail "$1: expected a hold at finalization, got: $(head -c 300 <<<"$3")"
    elif ! grep -q "\"name\":\"$2\"" <<<"$3"; then
        fail "$1: held at finalization without naming $2: $(head -c 300 <<<"$3")"
    else
        pass "$1: holds at finalization, naming $2"
    fi
}
# expect_rule <label> <rule-id> <response>: the held commit_convention gate's
# captured output carries a finding for <rule-id>, which tells the commit
# cases apart.
expect_rule() {
    local got
    got=$(jq -r '.blocking_conditions[]? | select(.name == "commit_convention") | .failure.captured.stdout // ""' <<<"$3" 2>/dev/null)
    if sed -n 's/^::koto-finding:://p' <<<"$got" | jq -e --arg r "$2" 'select(.rule_id == $r)' >/dev/null 2>&1; then
        pass "$1: the finding names $2"
    else
        fail "$1: expected a $2 finding, got: $(head -c 300 <<<"$got")"
    fi
}
expect_advance() {
    if grep -q '"state":"pr_precheck"' <<<"$2"; then
        pass "$1: reaches pr_precheck"
    else
        fail "$1: expected pr_precheck, got: $(head -c 300 <<<"$2")"
    fi
}

GOOD_SUMMARY='# Summary

## What Was Implemented
A thing.

## Changes Made
- `f.txt`: added

## Key Decisions
- none'
GOOD_PREPR='cleanup_commit: @HEAD@
design_diagram: docs/designs/DESIGN-thing.md'
GOOD_EVIDENCE='{"finalization_status":"ready_for_pr","cleanup_done":"removed","design_diagram":"updated"}'

# Case 1 — everything in order reaches the pull-request path.
OUT=$(land "prepr-ok-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" "$GOOD_PREPR" "$GOOD_EVIDENCE" || true)
expect_advance "a complete record" "$OUT"

# ---------------------------------------------------------------------------
# Case 2 — THE PLACEHOLDER CASE. "done" is what a careless run writes where a
# commit belongs, and it is exactly what a `type: string` field would accept.
# ---------------------------------------------------------------------------
OUT=$(land "prepr-placeholder-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" \
    'cleanup_commit: done
design_diagram: docs/designs/DESIGN-thing.md' "$GOOD_EVIDENCE" || true)
expect_hold "a placeholder where the cleanup commit belongs" cleanup_referent "$OUT"

# Case 3 — the same for the diagram: "yes" is neither a path nor a stated reason.
OUT=$(land "prepr-diagram-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" \
    'cleanup_commit: @HEAD@
design_diagram: yes' "$GOOD_EVIDENCE" || true)
expect_hold "a placeholder where the diagram referent belongs" diagram_referent "$OUT"

# Case 4 — not-applicable is accepted, but only WITH a reason after it. An
# obligation that does not apply is a legitimate answer; "not-applicable" alone
# is the same placeholder problem wearing a different word.
OUT=$(land "prepr-na-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" \
    'cleanup_commit: @HEAD@
design_diagram: not-applicable: no design document is touched' \
    '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}' || true)
expect_advance "not-applicable with a stated reason" "$OUT"
OUT=$(land "prepr-na-bare-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" \
    'cleanup_commit: @HEAD@
design_diagram: not-applicable' \
    '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}' || true)
expect_hold "not-applicable with no reason" diagram_referent "$OUT"

# Case 5 — a summary without the required section holds the run.
OUT=$(land "prepr-summary-$$" "feat(work-on): add a thing" '# Summary

Some prose and no sections.' "$GOOD_PREPR" "$GOOD_EVIDENCE" || true)
expect_hold "a summary missing its required section" summary_shape "$OUT"

# Case 6 — a tip commit that is not a Conventional Commits subject holds the run.
OUT=$(land "prepr-subject-$$" "fixed some stuff" "$GOOD_SUMMARY" "$GOOD_PREPR" "$GOOD_EVIDENCE" || true)
expect_hold "a non-conventional commit subject" commit_convention "$OUT"
expect_rule "a non-conventional commit subject" commit/conventional-subject "$OUT"

# Case 6b — the gate reads every commit the run made, not only the tip: a
# conventional tip over a non-conventional earlier commit still holds the run.
OUT=$(land "prepr-early-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" "$GOOD_PREPR" "$GOOD_EVIDENCE" \
    "wip stuff" || true)
expect_hold "a non-conventional commit below a conventional tip" commit_convention "$OUT"
expect_rule "a non-conventional commit below a conventional tip" commit/conventional-subject "$OUT"

# Case 6c — an AI-attribution trailer on a commit holds the run too.
OUT=$(land "prepr-trailer-$$" "feat(work-on): add a thing

Co-Authored-By: Claude <noreply@anthropic.com>" "$GOOD_SUMMARY" "$GOOD_PREPR" "$GOOD_EVIDENCE" || true)
expect_hold "an AI-attribution trailer" commit_convention "$OUT"
expect_rule "an AI-attribution trailer" commit/no-ai-trailer "$OUT"

# Case 7 — the judgment calls are enums, closed sets a placeholder can't
# satisfy: a word where cleanup_done's value belongs is refused outright.
OUT=$(land "prepr-enum-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" "$GOOD_PREPR" \
    '{"finalization_status":"ready_for_pr","cleanup_done":"done","design_diagram":"updated"}' || true)
if grep -q '"state":"pr_precheck"' <<<"$OUT"; then
    fail "cleanup_done: done advanced -- the enum accepted a placeholder"
else
    pass "a placeholder where cleanup_done's enum value belongs is refused"
fi

# ---------------------------------------------------------------------------
# Cases 8-11 — shirabe#422. A referent shaped right that names nothing. The
# mistyped full sha is the one the issue was filed from: the tip's first seven
# characters and nothing real behind them.
# ---------------------------------------------------------------------------
OUT=$(land "prepr-nonexistent-sha-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" \
    'cleanup_commit: @HEAD7@aaa9d49d45e7453fce2d9cc39537bbd5e
design_diagram: docs/designs/DESIGN-thing.md' "$GOOD_EVIDENCE" || true)
expect_hold "nonexistent-sha" cleanup_referent "$OUT"
OUT=$(land "prepr-other-branch-sha-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" \
    'cleanup_commit: @OTHER@
design_diagram: docs/designs/DESIGN-thing.md' "$GOOD_EVIDENCE" || true)
expect_hold "other-branch-sha" cleanup_referent "$OUT"
OUT=$(land "prepr-abbreviated-head-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" \
    'cleanup_commit: @HEAD7@
design_diagram: docs/designs/DESIGN-thing.md' "$GOOD_EVIDENCE" || true)
expect_advance "abbreviated-head" "$OUT"
OUT=$(land "prepr-missing-diagram-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" \
    'cleanup_commit: @HEAD@
design_diagram: docs/designs/DESIGN-missing.md' "$GOOD_EVIDENCE" || true)
expect_hold "missing-diagram" diagram_referent "$OUT"

# Case 12 — the status is required. Submitting nothing must not advance, since
# the state would otherwise be satisfied by silence.
OUT=$(land "prepr-empty-$$" "feat(work-on): add a thing" "$GOOD_SUMMARY" "$GOOD_PREPR" '{}' || true)
if grep -q '"state":"pr_precheck"' <<<"$OUT"; then
    fail "a submission with no evidence advanced"
else
    pass "a submission with no evidence does not advance"
fi

echo
echo "pre-pr-evidence_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
