#!/usr/bin/env bash
# check-template-compat_test.sh -- check-template-compat.sh over compiled
# template fixtures, with no koto.
#
# Proves: a table listing the structure at compat with the gate-script digest
# holds; a change to directive, details or description text, or to a
# variable's rebind flag, keeps the structure and holds; a renamed state, a
# changed transition, a new evidence field and a changed gate command each
# move the structure, so the table fails `fingerprint` until it lists it; a
# changed gate script, or a script it sources through $HERE, fails
# `gate-scripts` until the digest is recorded; against a base table a new
# structure at the base's compat fails `structure` and one at a higher compat
# holds, compat going down fails `compat-down`, and a base fingerprint
# renumbered fails `renumbered`; a malformed table and an unreadable compiled
# template can't be decided (exit 2).
# Also: raising compat over a structure the base lists fails
# `raise-needs-structure`, whether it stays listed at the old number or the
# new, and a changed gate invocation listed at the raised number holds; an
# evidence field named description is structure, not text.
set -uo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
CHECK="$REPO/scripts/check-template-compat.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/check-template-compat-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }

SK="$T/skills/demo"
mkdir -p "$SK/koto-templates" "$SK/scripts"
cp "$REPO/skills/coordinate/scripts/template-fingerprint.jq" "$SK/scripts/"
cp "$REPO/skills/coordinate/scripts/template-fingerprint.sh" "$SK/scripts/"
TPL="$SK/koto-templates/demo.md"
TABLE="$SK/koto-templates/demo.compat.json"
echo "# demo template (only its path matters here)" > "$TPL"
cat > "$SK/scripts/gate.sh" <<'EOF'
#!/usr/bin/env bash
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/common.sh"
exit 0
EOF
mkdir -p "$SK/scripts/lib"
echo 'common() { :; }' > "$SK/scripts/lib/common.sh"
echo 'unreached() { :; }' > "$SK/scripts/unreached.sh"

# The compiled template: two states, a gate running gate.sh, one evidence field.
cat > "$T/c0.json" <<'EOF'
{"format_version":1,"name":"demo","version":"1","description":"A demo.","initial_state":"a",
 "variables":{"PLUGIN_ROOT":{"description":"Root.","required":true}},
 "states":{
  "a":{"directive":"Do a.","details":"Longer.","accepts":{"go":{"type":"enum","values":["yes"],"required":true,"description":"Go?"}},
       "gates":{"g":{"type":"command","command":"\"{{PLUGIN_ROOT}}/skills/demo/scripts/gate.sh\""}},
       "transitions":[{"target":"b","when":{"go":"yes"}}]},
  "b":{"directive":"Done.","terminal":true}}}
EOF
variant() { jq "$1" "$T/c0.json" > "$T/$2.json"; }
variant '.states.a.directive = "Do a, carefully." | .description = "Another demo." | .variables.PLUGIN_ROOT.rebind = true' text
variant '.states = (.states | with_entries(if .key == "b" then .key = "c" else . end)) | .states.a.transitions[0].target = "c"' renamed
variant '.states.a.transitions[0].when.go = "no"' transition
variant '.states.a.accepts.why = {"type":"string"}' field
variant '.states.a.gates.g.command += " --strict"' gate

print() { bash "$CHECK" --template "$TPL" --compiled "$1" --print; }
FP0=$(print "$T/c0.json" | jq -r .fingerprint)
GS0=$(print "$T/c0.json" | jq -r .gate_scripts)
table() { # table <compat> <fingerprints-json> <gate digest>
    jq -n --argjson c "$1" --argjson f "$2" --arg g "$3" '{compat: $c, fingerprints: $f, gate_scripts: $g}' > "$TABLE"
}
run() { bash "$CHECK" --template "$TPL" --compiled "$@" > "$T/out" 2> "$T/err"; echo $?; }

table 1 "{\"$FP0\": 1}" "$GS0"
eq "a table listing the structure at compat with the digest holds" 0 "$(run "$T/c0.json")"
eq "a change to text and to a variable's rebind flag keeps the structure" 0 "$(run "$T/text.json")"
for v in renamed transition field gate; do
    eq "a $v change moves the structure" 1 "$(run "$T/$v.json")"
    grep -q 'check-template-compat: fingerprint:' "$T/err" && pass "  ... and fails fingerprint" || fail "  ... and fails fingerprint" "$(cat "$T/err")"
done

echo 'common() { echo changed; }' > "$SK/scripts/lib/common.sh"
eq "a script a gate script sources changing fails" 1 "$(run "$T/c0.json")"
grep -q 'check-template-compat: gate-scripts:' "$T/err" && pass "  ... gate-scripts" || fail "  ... gate-scripts" "$(cat "$T/err")"
GS1=$(print "$T/c0.json" | jq -r .gate_scripts)
table 1 "{\"$FP0\": 1}" "$GS1"
eq "  ... and holds once the digest is recorded" 0 "$(run "$T/c0.json")"
echo 'unreached() { echo changed; }' > "$SK/scripts/unreached.sh"
eq "a script no gate reaches changing holds" 0 "$(run "$T/c0.json")"

FPR=$(print "$T/renamed.json" | jq -r .fingerprint)
jq -n --arg f "$FP0" --arg g "$GS1" '{compat: 1, fingerprints: {($f): 1}, gate_scripts: $g}' > "$T/base.json"
table 1 "{\"$FP0\": 1, \"$FPR\": 1}" "$GS1"
eq "against the base, a new structure at the base's compat fails" 1 "$(run "$T/renamed.json" --base-table "$T/base.json")"
grep -q 'check-template-compat: structure:' "$T/err" && pass "  ... structure" || fail "  ... structure" "$(cat "$T/err")"
table 2 "{\"$FP0\": 1, \"$FPR\": 2}" "$GS1"
eq "  ... and holds at a higher compat" 0 "$(run "$T/renamed.json" --base-table "$T/base.json")"
jq -n --arg f "$FP0" --arg g "$GS1" '{compat: 3, fingerprints: {($f): 3}, gate_scripts: $g}' > "$T/base3.json"
table 2 "{\"$FP0\": 2}" "$GS1"
eq "compat going down fails" 1 "$(run "$T/c0.json" --base-table "$T/base3.json")"
grep -q 'check-template-compat: compat-down:' "$T/err" && pass "  ... compat-down" || fail "  ... compat-down" "$(cat "$T/err")"
grep -q 'check-template-compat: renumbered:' "$T/err" && pass "  ... and renumbered" || fail "  ... and renumbered" "$(cat "$T/err")"

# A script's meaning change can't be marked by raising compat alone: the
# base's runs carry the same structure and would still be admitted. The raise
# is refused, and changing how the template invokes the script is the way.
table 2 "{\"$FP0\": 1}" "$GS1"
eq "raising compat over a structure the base lists fails" 1 "$(run "$T/c0.json" --base-table "$T/base.json")"
grep -q 'check-template-compat: raise-needs-structure:' "$T/err" && pass "  ... raise-needs-structure" || fail "  ... raise-needs-structure" "$(cat "$T/err")"
table 2 "{\"$FP0\": 2}" "$GS1"
eq "  ... and relisting that structure at the raised compat fails too" 1 "$(run "$T/c0.json" --base-table "$T/base.json")"
grep -q 'check-template-compat: raise-needs-structure:' "$T/err" && pass "  ... raise-needs-structure" || fail "  ... raise-needs-structure" "$(cat "$T/err")"
FPG=$(print "$T/gate.json" | jq -r .fingerprint)
table 2 "{\"$FP0\": 1, \"$FPG\": 2}" "$GS1"
eq "  ... and a changed invocation listed at the raised compat holds" 0 "$(run "$T/gate.json" --base-table "$T/base.json")"

# An evidence field named like a text key holds an object, not text, and is
# part of the structure.
variant '.states.a.accepts.description = {"type":"string","required":true}' descfield
table 1 "{\"$FP0\": 1}" "$GS1"
eq "an evidence field named description moves the structure" 1 "$(run "$T/descfield.json")"
grep -q 'check-template-compat: fingerprint:' "$T/err" && pass "  ... and fails fingerprint" || fail "  ... and fails fingerprint" "$(cat "$T/err")"

# The fingerprint CI records is the one a resume computes: coord-log.sh hashes
# a run's compiled copy with template-fingerprint.sh, and so does the check.
# The real coordinate template's shipped table must match what that script
# prints for a compiled copy of it.
eq "the check's fingerprint is template-fingerprint.sh's" "$(bash "$REPO/skills/coordinate/scripts/template-fingerprint.sh" "$T/c0.json")" "$FP0"
grep -q 'template-fingerprint.sh' "$REPO/skills/coordinate/scripts/coord-log.sh" \
    && pass "  ... and coord-log.sh fingerprints a run with the same script" || fail "  ... and coord-log.sh fingerprints a run with the same script"

echo '{"compat": 0}' > "$TABLE"
eq "a malformed table can't be decided" 2 "$(run "$T/c0.json")"
eq "an unreadable compiled template can't be decided" 2 "$(run "$T/missing.json")"
eq "no template is usage" 64 "$(bash "$CHECK" > /dev/null 2>&1; echo $?)"

echo; echo "check-template-compat: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
