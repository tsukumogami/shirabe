#!/usr/bin/env bash
# check-rule-registry_1_test.sh -- part 1 of 4 of the tests for
# check-rule-registry.sh and check-rule-registry-adoption.sh: the control
# cases and the shape and withhold checks.
#
# The four parts were one suite, cut by case order so each runs in its own CI
# slice; scripts/lib/check-rule-registry-testlib.sh holds the setup they share
# and describes the scratch copy the cases alter.
#
# Run from anywhere: bash scripts/check-rule-registry_1_test.sh

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1
. "$(dirname "$0")/lib/check-rule-registry-testlib.sh" || exit 1

# ---------------------------------------------------------------- control

run_check
[ "$RC" = 0 ] && pass "the unaltered copy passes" || fail "the unaltered copy passes" "rc=$RC: $OUT"

OUT=$("$CHECK" 2>&1); RC=$?
[ "$RC" = 0 ] && pass "the repository itself passes" || fail "the repository itself passes" "rc=$RC: $OUT"

# ---------------------------------------------------------------- shape

reg "del($(sel $G).summary)"
expect_problem "a missing field" "$G: missing field summary"

reg '.rules = []'
expect_problem "an empty registry" "the registry has no active entries"

reg "$(sel $G).level = \"hard\""
expect_problem "an out-of-vocabulary value" "level \"hard\" is not gate"

reg ".rules += [$(sel $TK) | .id = \"Takeover_Copy\" | .notes = \"copy\"]"
expect_problem "an id matching neither pattern" "id \"Takeover_Copy\" matches neither"

reg ".rules += [$(sel $TK)]"
expect_problem "a duplicate id" "id $TK is used by more than one entry"

reg "$(sel $TK).aliases = [\"PB1\"]"
expect_problem "a duplicate alias" "alias PB1 is used more than once"

reg "$(sel $TK).aliases = [\"$G\"]"
expect_problem "an alias equal to an id" "$TK: alias $G is also an id"

reg "$(sel $RS).guards = [\"deploy\"]"
expect_problem "a guard outside the vocabulary" "$RS: guard \"deploy\" is not in the vocabulary"

reg "$(sel $RS).guards = [\"none\", \"push\"]"
expect_problem "none mixed with another guard" "$RS: none is mixed with other guards"

reg "$(sel $RS).timing = [\"work-on:no_such_state\"]"
expect_problem "a timing naming no state section" "names no '## no_such_state' section"

reg "$(sel $G).summary = \"one\\u0001two\""
expect_problem "a summary with a control character" "$G: summary holds a control character"

reg "$(sel $G).summary = \"one :: two\""
expect_problem "a summary with ::" "$G: summary holds the marker ::"

# ---------------------------------------------------------------- withhold

reg "$(sel $RS).guards = [\"push\"]"
expect_problem "an eligible entry with a protected guard" "$RS: a protected guard requires withhold never"

reg "$(sel $RS).guards = [\"merge\"]"
expect_problem "an eligible entry guarding merge" "$RS: a protected guard requires withhold never"

reg "$(sel $RS).guards = [\"pr-create\"]"
expect_problem "an eligible entry guarding pr-create" "$RS: a protected guard requires withhold never"

reg "$(sel $RS).check = {\"kind\": \"none\"}"
expect_problem "an eligible entry with check none" "$RS: check.kind none requires withhold never"

reg "$(sel $G2).guards = [\"none\"]"
expect_problem "a gate entry guarding none" "$G2: a gate entry needs a guard other than none, or a backstop"

# A script entry at shadow or warn never fails its gate, so it may guard
# nothing; at block it may not.
reg "$(sel docs/required-fields).guards = [\"none\"] | $(sel docs/required-fields).stage = \"warn\""
expect_clean "a script gate entry at warn guarding nothing passes"
reg "$(sel docs/required-fields).guards = [\"none\"] | $(sel docs/required-fields).stage = \"shadow\""
expect_clean "a script gate entry at shadow guarding nothing passes"
reg "$(sel $WN).stage = \"block\""
expect_problem "a script gate entry at block guarding nothing" "$WN: a gate entry needs a guard other than none, or a backstop"
reg "$(sel $WN).status = \"retired\" | $(sel $WN).stage = \"retired\""
expect_problem "a retired script gate entry guarding nothing" "$WN: a gate entry needs a guard other than none, or a backstop"

reg "$(sel $G2).guards = [\"none\"] | $(sel $G2).withhold = \"eligible\""
expect_problem "an eligible gate entry with no backstop" "$G2: a gate entry needs a guard other than none, or a backstop"

reg "$(sel $G2).withhold = \"eligible\""
expect_problem "another gate entry marked eligible with its guards" "$G2: a protected guard requires withhold never"

reg "del($(sel $G).backstop)"
expect_problem "the eligible gate entry without its backstop" "$G: a gate entry needs a guard other than none, or a backstop"

reg "$(sel $G).backstop.before = \"deploy\""
expect_problem "a backstop before an unprotected action" "$G: backstop.before \"deploy\" is not a protected action"

reg "$(sel $G).backstop.check = \"\""
expect_problem "a backstop with no check" "$G: backstop.check is not a path"

reg "$(sel $G).backstop.check = \".github/workflows/no-such.yml\""
expect_problem "a backstop check that does not exist" "$G: backstop path .github/workflows/no-such.yml does not exist"

reg "$(sel $G).guards = [\"merge\"]"
expect_problem "a backstop beside a protected guard" "$G: a backstop needs guards [\"none\"]"

reg "$(sel $G).withhold = \"never\""
expect_problem "a backstop on a never-withhold entry" "$G: a backstop needs withhold eligible"

reg "$(sel $G).notes = \"\""
expect_problem "a backstop with no notes" "$G: a backstop needs notes saying why"

reg "$(sel $RS).backstop = {\"before\": \"merge\", \"check\": \".github/workflows/validate-pr-body.yml\"}"
expect_problem "a backstop on a review-shadow entry" "$RS: a backstop needs level gate"

reg "$(sel $TK).check = {\"kind\": \"script\", \"path\": \"skills/execute/scripts/adopt-or-create-pr.sh\"}"
expect_problem "a prose entry with a check" "$TK: a prose entry must have check.kind none"

# A decider check: a koto decider-check gate's criterion. It guards nothing,
# so check 2's guard rule doesn't apply to it, while a script gate with the
# same fields still fails ("a gate entry guarding none" above). The lifecycle
# fields belong to script entries only, so the converted entry drops them.
reg "$(sel $G2).check = $DECIDER | $(sel $G2).guards = [\"none\"] | $(sel $G2).withhold = \"never\"
     | del($(sel $G2).stage, $(sel $G2).stage_since, $(sel $G2).gates, $(sel $G2).stage_backstops)"
expect_clean "a decider entry guarding none"

reg "$(sel $RS).jev = {\"state\": \"rejected\"}"
expect_clean "a jev object on an entry"

reg "$(sel $G2).check = ($DECIDER | del(.gate))"
expect_problem "a decider check with no gate" "$G2: a decider check has no gate"

reg "$(sel $G2).check = ($DECIDER | .criterion = \"\")"
expect_problem "a decider check with an empty criterion" "$G2: a decider check has no criterion"

reg "$(sel $RS).jev = []"
expect_problem "a jev that is not an object" "$RS: jev is not an object"

reg "$(sel $G2).check = {\"kind\": \"jev\"}"
expect_problem "an unknown check kind" "check.kind \"jev\" is not script, review-shadow, decider or none"

echo
echo "check-rule-registry_1_test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
