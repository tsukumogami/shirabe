#!/usr/bin/env bash
# check-rule-registry_2_test.sh -- part 2 of 4 of the tests for
# check-rule-registry.sh and check-rule-registry-adoption.sh: paths,
# pointers, review-shadow ids, printable ids, hook links and the first
# stage-shape cases.
#
# The four parts were one suite, cut by case order so each runs in its own CI
# slice; scripts/lib/check-rule-registry-testlib.sh holds the setup they share
# and describes the scratch copy the cases alter.
#
# Run from anywhere: bash scripts/check-rule-registry_2_test.sh

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1
. "$(dirname "$0")/lib/check-rule-registry-testlib.sh" || exit 1

# ---------------------------------------------------------------- paths

reg "$(sel $G).check.path = \"skills/work-on/scripts/no-such-check.sh\""
expect_problem "a missing check path" "$G: check path skills/work-on/scripts/no-such-check.sh does not exist"

reg "$(sel $G2).check = ($DECIDER | .template = \"skills/work-on/koto-templates/no-such.md\") | $(sel $G2).guards = [\"none\"] | $(sel $G2).withhold = \"never\""
expect_problem "a decider check naming a missing template" "$G2: template path skills/work-on/koto-templates/no-such.md does not exist"

reg "$(sel $G).fixtures = [\"scripts/no-such_test.sh\"]"
expect_problem "a missing fixture" "$G: fixture path scripts/no-such_test.sh does not exist"

reg "$(sel $RS).check.criterion = \"rs-999\""
expect_problem "a criterion absent from criteria.json" "$RS: review-shadow criterion rs-999 is not in criteria.json"

reg "$(sel $G).text.path = \"../outside.md\""
expect_problem "an unsafe path" "$G: text path [../outside.md] is unsafe"

# ---------------------------------------------------------------- pointers

reg "$(sel $G).text.first = \"PB4\""
expect_problem "an anchor found twice" "first anchor is not on exactly one line"

reg "$(sel $G).text.first = \"no line says this 7f3a\""
expect_problem "an anchor found zero times" "first anchor is not on exactly one line"

reg "$(sel $G).text.last = \"# PR-body conformance: the mechanical rule\""
expect_problem "a last anchor before the first" "last anchor is not at or after its first"

awk '{ print } index($0, "**PB4 — no markdown section heading in Part 1.**") { print "::shirabe-rule-end::" }' \
    "$WORK/orig/references/pr-body-conformance.md" > "$S/references/pr-body-conformance.md"
expect_problem "a marker line in a range" "$G: its range holds a ::shirabe-rule marker line"

reg "$(sel $RS).status = \"retired\" | $(sel $RS).text.first = \"no line says this 7f3a\""
run_check
[ "$RC" = 0 ] && pass "a retired entry with an unresolvable anchor passes" \
    || fail "a retired entry with an unresolvable anchor passes" "rc=$RC: $OUT"
reset_copy

# ---------------------------------------------------------------- review-shadow

reg ".rules += [$(sel $RS) | .id = \"rs-998\" | .check.criterion = \"rs-998\"]"
expect_problem "an rs- id only in the registry" "rs-998: in the registry but not in criteria.json"

reg "del(.rules[] | select(.id == \"$RS\"))"
expect_problem "an rs- id only in criteria.json" "$RS: in criteria.json but not in the registry"

# A document criterion is graded by its koto template, so it needs no
# criteria.json row; rs-073 has none.
reg ".rules += [$(sel rs-073) | .id = \"rs-998\"]"
run_check
[ "$RC" = 0 ] && pass "a decider-checked rs- id needs no criteria.json row" \
    || fail "a decider-checked rs- id needs no criteria.json row" "rc=$RC: $OUT"
reset_copy

reg "$(sel $RS).text.path = \"references/wip-hygiene.md\""
expect_problem "a mismatched criterion path" "$RS: text.path \"references/wip-hygiene.md\" differs from the criterion rule_ref"

# ---------------------------------------------------------------- printable ids

sed 's#^\(RULE_IDS="pr-body/conventional-title\)#\1 pr-body/not-registered#' \
    "$WORK/orig/skills/work-on/scripts/check-pr-output.sh" > "$S/skills/work-on/scripts/check-pr-output.sh"
expect_problem "an unregistered RULE_IDS id" "RULE_IDS names pr-body/not-registered"

sed 's|^RULE_IDS="\(.*\)"$|RULE_IDS="\1" # trailing words|' \
    "$WORK/orig/skills/work-on/scripts/check-pr-output.sh" > "$S/skills/work-on/scripts/check-pr-output.sh"
# The line is read from the script rather than pinned, so its header can grow.
RULE_IDS_LINE=$(grep -n '^RULE_IDS=' "$WORK/orig/skills/work-on/scripts/check-pr-output.sh" | cut -d: -f1)
expect_problem "a malformed RULE_IDS line" "check-pr-output.sh:$RULE_IDS_LINE: malformed RULE_IDS line"

# The declared exception: RULE_IDS_ANY_ACTIVE=1 beside an rf_require_any call,
# in panel-scope.sh only. Each case builds its alteration from the original so
# it holds whether or not the original already carries the pair.
PS=skills/work-on/scripts/panel-scope.sh
PO=skills/work-on/scripts/check-pr-output.sh
{ cat "$WORK/orig/$PO"; echo 'RULE_IDS_ANY_ACTIVE=1'; echo 'rf_require_any "$id"'; } > "$S/$PO"
expect_problem "the any-active marker outside the allowed script" "RULE_IDS_ANY_ACTIVE is allowed only in"

{ sed 's/rf_require_any/rf_require_some/g; /^RULE_IDS_ANY_ACTIVE=/d' "$WORK/orig/$PS"; echo 'RULE_IDS_ANY_ACTIVE=1'; } > "$S/$PS"
expect_problem "the any-active marker with no rf_require_any call" "declares RULE_IDS_ANY_ACTIVE=1 but never calls rf_require_any"

{ sed '/^RULE_IDS_ANY_ACTIVE=/d' "$WORK/orig/$PO"; echo 'rf_require_any "$id"'; } > "$S/$PO"
expect_problem "an rf_require_any call with no marker" "calls rf_require_any without declaring RULE_IDS_ANY_ACTIVE=1"

{ sed '/^RULE_IDS_ANY_ACTIVE=/d' "$WORK/orig/$PS"; echo 'RULE_IDS_ANY_ACTIVE=yes'; } > "$S/$PS"
expect_problem "a malformed any-active marker" "malformed RULE_IDS_ANY_ACTIVE line"

# The hook's RULE_IDS line is read like a gate script's. Its suite's own
# RULE_IDS=$(...) line is not a declaration: the unaltered copy carries it and
# passes.
# The line the checker names, read from the script so an edit above it
# doesn't break these cases.
HKL="$HK:$(grep -n '^RULE_IDS="' "$WORK/orig/$HK" | cut -d: -f1)"
sed 's#^\(RULE_IDS="pr-body/conventional-title\)#\1 pr-body/not-registered#' "$WORK/orig/$HK" > "$S/$HK"
expect_problem "an unregistered RULE_IDS id in a hook script" "$HKL: RULE_IDS names pr-body/not-registered, which is not"

# ---------------------------------------------------------------- hook links

P=commit/no-ai-trailer

reg "$(sel $G).deny = \"$HK\""
expect_problem "a deny that is not an object" "$G: deny is not an object"

reg "$(sel $G).deny = {\"before\": [\"pr-create\"]}"
expect_problem "a deny with no hook" "$G: deny.hook is not a path"

reg "$(sel $G).deny.befor = [\"pr-create\"]"
expect_problem "a deny with an unknown field" "$G: deny has a field other than hook and before: befor"

reg "$(sel $G).deny.hook = \"../outside.sh\""
expect_problem "a deny naming an unsafe path" "$G: deny.hook [../outside.sh] is unsafe"

reg "$(sel $G).deny.hook = \"hooks/no-such-hook.sh\""
expect_problem "a deny naming a missing file" "$G: deny.hook hooks/no-such-hook.sh does not exist"

reg "$(sel $P).deny.before = []"
expect_problem "a deny with an empty before" "$P: deny.before is not a non-empty list"

reg "$(sel $P).deny.before = \"push\""
expect_problem "a deny whose before is not a list" "$P: deny.before is not a non-empty list"

reg "$(sel $P).deny.before = [\"push\", \"deploy\"]"
expect_problem "a deny before an unprotected action" "$P: deny.before \"deploy\" is not a protected action"

reg "$(sel $P).deny.before = [\"none\"]"
expect_problem "a deny before none" "$P: deny.before \"none\" is not a protected action"

reg "del($(sel $P).deny)"
expect_problem "a hook's RULE_IDS id with no deny" "$HKL: RULE_IDS names $P, whose registry entry has no deny naming $HK"

reg "$(sel $P).deny.hook = \"skills/work-on/scripts/check-branch-output.sh\""
expect_problem "a deny naming another script" "$HKL: RULE_IDS names $P, whose registry entry has no deny naming $HK"

reg "$(sel commit/conventional-subject).deny = {\"hook\": \"$HK\", \"before\": [\"push\"]}"
expect_problem "a deny whose script does not list the id" "commit/conventional-subject: deny names $HK, whose RULE_IDS line does not list it"

sed 's#^RULE_IDS="\(.*\) commit/no-ai-trailer"$#RULE_IDS="\1"#' "$WORK/orig/$HK" > "$S/$HK"
expect_problem "an id dropped from the hook's RULE_IDS line" "$P: deny names $HK, whose RULE_IDS line does not list it"

# ---------------------------------------------------------------- stage shape

for f in stage stage_since gates; do
    reg "del($(sel $G).$f)"
    expect_problem "a script entry with no $f" "$G: missing field $f"
done

reg "$(sel $G).stage = \"hard\""
expect_problem "a stage outside the vocabulary" "$G: stage \"hard\" is not shadow, warn, block or retired"

reg "$(sel $G).stage_since = \"2026-13-01\""
expect_problem "a stage_since with no such month" "$G: stage_since \"2026-13-01\" is not a YYYY-MM-DD date"

reg "$(sel $G).stage_since = \"16 Oct 2026\""
expect_problem "a stage_since in another format" "$G: stage_since \"16 Oct 2026\" is not a YYYY-MM-DD date"

echo
echo "check-rule-registry_2_test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
