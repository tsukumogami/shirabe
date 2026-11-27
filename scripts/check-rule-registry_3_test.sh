#!/usr/bin/env bash
# check-rule-registry_3_test.sh -- part 3 of 4 of the tests for
# check-rule-registry.sh and check-rule-registry-adoption.sh: the rest of
# stage shape, stage safety, gates, releasable ids, baseline keys and the
# path filter.
#
# The four parts were one suite, cut by case order so each runs in its own CI
# slice; scripts/lib/check-rule-registry-testlib.sh holds the setup they share
# and describes the scratch copy the cases alter.
#
# Run from anywhere: bash scripts/check-rule-registry_3_test.sh

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1
. "$(dirname "$0")/lib/check-rule-registry-testlib.sh" || exit 1

# ---------------------------------------------------------------- stage shape

reg "$(sel $RS).stage = \"block\""
expect_problem "a review-shadow entry with a stage" "$RS: stage is only for an entry with check.kind script"

reg "$(sel $TK).stage_backstops = []"
expect_problem "a prose entry with stage_backstops" "$TK: stage_backstops is only for an entry with check.kind script"

reg "$(sel $R).stage = \"block\""
expect_problem "a status retired entry at another stage" "$R: a status retired entry needs stage retired"

reg "$(sel $G).gates = []"
expect_problem "an active script entry with no gates" "$G: gates is empty on an active entry"

# scripts/doc-check.sh runs from a skill's phase step, not a koto gate, so an
# entry it checks may have no gates; the same entry under another check may not.
reg "$(sel roadmap/milestone-shape).check.path = \"skills/scope/scripts/check-hop-document.sh\""
expect_problem "an empty gates list on an entry another script checks" "roadmap/milestone-shape: gates is empty on an active entry"

reg "$(sel rs-027).held_by = \"rs-026\""
expect_problem "a held_by naming an entry no script checks" "rs-027: held_by \"rs-026\" is not an active script-checked entry"

reg "$(sel rs-027).held_by = \"docs/no-such-rule\""
expect_problem "a held_by naming no entry" "rs-027: held_by \"docs/no-such-rule\" is not an active script-checked entry"

reg "$(sel $G).held_by = \"docs/required-sections\""
expect_problem "a held_by on an entry that isn't an rs- item" "$G: held_by is only for an rs- jury or review-shadow item"

reg "$(sel rs-027).held_by = 7"
expect_problem "a held_by that isn't a string" "rs-027: held_by is not a string"

reg "$(sel $G).gates = [\"work-on:pr_creation\"]"
expect_problem "a gate missing its gate name" "$G: gate \"work-on:pr_creation\" is not <skill>:<state>:<gate>"

reg "$(sel $G).gates = [\"Work-On:pr_creation:pr_body_conformant\"]"
expect_problem "a gate with an upper-case skill" "is not <skill>:<state>:<gate>"

reg "$(sel $G2).stage_backstops = [{\"before\": \"pr-create\", \"check\": \"$HK\"}]"
expect_problem "stage_backstops with no notes" "$G2: stage_backstops needs notes saying why"

reg "$(sel $G2).stage_backstops = [{\"before\": \"deploy\", \"check\": \"$HK\"}] | $(sel $G2).notes = \"why\""
expect_problem "a stage backstop before an unprotected action" "$G2: stage_backstops before \"deploy\" is not a protected action"

reg "$(sel $G2).stage_backstops = [{\"before\": \"pr-create\", \"check\": \"$HK\"}, {\"before\": \"pr-create\", \"check\": \".github/workflows/validate-pr-body.yml\"}] | $(sel $G2).notes = \"why\""
expect_problem "a stage backstop action named twice" "$G2: stage_backstops names pr-create more than once"

reg "$(sel $G2).stage_backstops = [{\"before\": \"pr-create\", \"check\": \"\"}] | $(sel $G2).notes = \"why\""
expect_problem "a stage backstop with no check" "$G2: a stage_backstops check is not a path"

# ---------------------------------------------------------------- stage safety

# G2 guards pr-create and publish. Each case lowers it below block.
BS_PUB='{"before": "publish", "check": ".github/workflows/validate-pr-body.yml"}'
below() { printf '%s.stage = "%s" | %s.notes = "a backstop holds each guard"' "$(sel $G2)" "$1" "$(sel $G2)"; }

reg "$(below warn)"
expect_problem "a guarded entry at warn with no backstop" "$G2: guards pr-create at stage warn with no stage_backstops entry"

reg "$(below warn) | $(sel $G2).stage_backstops = [$BS_PR]"
expect_problem "a guarded entry at warn with a backstop for one guard of two" "$G2: guards publish at stage warn with no stage_backstops entry"

reg "$(below shadow) | $(sel $G2).stage_backstops = [$BS_PR, {\"before\": \"publish\", \"check\": \".github/workflows/no-such.yml\"}]"
expect_problem "a stage backstop path that does not exist" "$G2: stage backstop path .github/workflows/no-such.yml does not exist"

reg "$(below warn) | $(sel $G2).stage_backstops = [$BS_PR, {\"before\": \"publish\", \"check\": \"skills/work-on/scripts/check-pr-output.sh\"}]"
expect_problem "a stage backstop that is the entry's own check" "$G2: guards publish at stage warn with no stage_backstops entry"

reg "$(below retired) | $(sel $G2).stage_backstops = [$BS_PR, $BS_PUB]"
run_check
[ "$RC" = 0 ] && pass "an active guarded entry at retired with an existing backstop for every guard passes" \
    || fail "an active guarded entry at retired with an existing backstop for every guard passes" "rc=$RC: $OUT"
reset_copy

reg "$(below warn) | $(sel $G2).stage_backstops = [$BS_PR, $BS_PUB]"
run_check
[ "$RC" = 0 ] && pass "a guarded entry at warn with every guard backed passes" \
    || fail "a guarded entry at warn with every guard backed passes" "rc=$RC: $OUT"
reset_copy

reg "$(sel $G).stage = \"shadow\""
run_check
[ "$RC" = 0 ] && pass "an unguarded entry at shadow needs no backstop" \
    || fail "an unguarded entry at shadow needs no backstop" "rc=$RC: $OUT"
reset_copy

# The stage safety rule and rule-registry.sh's run-time copy of it read the
# same protected actions.
P1=$(grep -m1 '^PROTECTED=' "$SCRIPT_DIR/rule-registry.sh")
P2=$(grep -m1 '^PROTECTED=' "$CHECK")
if [ -n "$P1" ] && [ "$P1" = "$P2" ]; then
    pass "rule-registry.sh and check-rule-registry.sh list the same protected actions"
else
    fail "rule-registry.sh and check-rule-registry.sh list the same protected actions" "[$P1] vs [$P2]"
fi

# ---------------------------------------------------------------- gates

reg "$(sel $G).gates += [\"work-on:no_such_state:pr_body_conformant\"]"
expect_problem "a gate naming no state of the skill" "$G: gate work-on:no_such_state:pr_body_conformant names no state no_such_state"

reg "$(sel $G).gates += [\"work-on:pr_creation:no_such_gate\"]"
expect_problem "a gate that is not a command gate of its state" "$G: gate work-on:pr_creation:no_such_gate is not a command gate of state pr_creation"

reg "$(sel $G).gates += [\"work-on:verification:verification_verdict\"]"
expect_problem "a gate whose script does not list the id" "$G: gate work-on:verification:verification_verdict runs no script whose RULE_IDS line lists $G"

reg "$(sel $R).gates = [\"execute:no_such_state:x\"]"
expect_problem "a retired entry's gate is still checked by name" "$R: gate execute:no_such_state:x names no state"

# A review-panel gate runs panel-scope.sh, which prints any active rule, so
# only panel/open-finding may list one; rule-lifecycle.sh counts every
# finding there for it.
reg "$(sel $G).gates += [\"work-on:scrutiny:scrutiny_verdict\", \"work-on:light_review:light_verdict\"]"
expect_problem "a review-panel gate on another entry" "$G: gate work-on:scrutiny:scrutiny_verdict is a panel gate; only panel/open-finding may list one"

reg "$(sel $R).gates = [\"work-on:review:review_verdict\"]"
expect_problem "a review-panel gate on a retired entry" "$R: gate work-on:review:review_verdict is a panel gate; only panel/open-finding may list one"

run_check
[ "$RC" = 0 ] && pass "panel/open-finding lists the review-panel gates and passes" \
    || fail "panel/open-finding lists the review-panel gates and passes" "rc=$RC: $OUT"

sed 's/^      owned_pr_body_conformant:/      owned_pr_body_renamed:/' \
    "$WORK/orig/skills/execute/koto-templates/execute.md" > "$S/skills/execute/koto-templates/execute.md"
expect_problem "a gate renamed in its template" "$G: gate execute:pr_finalization:owned_pr_body_conformant is not a command gate"

# ---------------------------------------------------------------- releasable

{ cat "$WORK/orig/skills/execute/scripts/adopt-or-create-pr.sh"
  printf '%s\n' '"$SELF_DIR/../../../scripts/rule-registry.sh" release rs-001 </dev/null >&2 || true'
} > "$S/skills/execute/scripts/adopt-or-create-pr.sh"
expect_problem "a released id outside the releasable directories" "rs-001 would not be released"

{ cat "$WORK/orig/skills/execute/scripts/adopt-or-create-pr.sh"
  printf '%s\n' '    "$SELF_DIR/../../../scripts/rule-registry.sh" release no-such/rule >&2 || true  # a trailing comment'
} > "$S/skills/execute/scripts/adopt-or-create-pr.sh"
expect_problem "an indented release with a trailing comment is still read" "releases no-such/rule, which is not an active registry entry"

awk '{ print } index($0, "**Another run'"'"'s PR (exit 6 on") { for (i = 0; i < 70; i++) print "filler line" }' \
    "$WORK/orig/skills/execute/koto-templates/execute.md" > "$S/skills/execute/koto-templates/execute.md"
expect_problem "a released range over 60 lines" "$TK would not be released"

# ---------------------------------------------------------------- baseline keys

jq '.pinned_commit = "abc123"' "$WORK/orig/docs/measurement/offload-baseline/template-pin.json" \
    > "$S/docs/measurement/offload-baseline/template-pin.json"
expect_problem "a pinned commit that isn't 40 hex" "pinned_commit [abc123] is not 40 lowercase hex characters"

reg "$(sel $G).baseline_keys = [\"references/pr-body-conformance.md:61\"]"
expect_problem "a malformed baseline key" "$G: baseline key [references/pr-body-conformance.md:61] is not"

reg "$(sel $G).baseline_keys = [\"references/pr-body-conformance.md#L61-L99999\"]"
expect_problem "a baseline key past its file's end" "$G: baseline key references/pr-body-conformance.md#L61-L99999 runs past"

reg "$(sel $TK).baseline_keys = [\"references/pr-body-conformance.md#L61-L75\"]"
expect_problem "an unexplained shared key" "$TK: shares baseline key references/pr-body-conformance.md#L61-L75 with $G"

reg "$(sel $G).baseline_keys = [] | $(sel $G).notes = \"\""
expect_problem "an unexplained empty key list" "$G: an empty baseline_keys needs a reason in notes"

# ---------------------------------------------------------------- path filter

grep -vxF "      - 'CLAUDE.md'" "$WORK/orig/.github/workflows/check-rule-registry.yml" \
    > "$S/.github/workflows/check-rule-registry.yml"
expect_problem "a text.path outside the workflow's path filter" "rs-001: text.path CLAUDE.md is outside"

echo
echo "check-rule-registry_3_test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
