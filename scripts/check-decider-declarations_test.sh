#!/usr/bin/env bash
#
# check-decider-declarations_test.sh - tests for check-decider-declarations.sh
#
# Every case builds its own temp tree -- a demo template under
# skills/demo/koto-templates/, its fixture file, and a modes table -- and runs
# the check against it with --root and --table, so nothing here depends on the
# declarations shirabe actually ships. One more case runs the check against
# this repository.
#
# The demo field has two values, `a` (no mode, so shadow) and `b` (never),
# escape `unclear`, and two inputs: `x` with max_bytes 20 and `y` with the
# default budget. Two values leave room for the escape to make up the total, so
# the boundaries separate: 10 of each value and 40 in all passes, while 9 of
# one value (still 40 in all) and 39 in all (still 10 of each) each fail alone.
#
# The check must make no network call and run no koto. Every run here has
# KOTO_DECIDER_API_KEY unset and stubs for curl, wget, gh, and koto first on
# PATH that record any call, and the test fails if one was made.
#
# Usage:
#   bash scripts/check-decider-declarations_test.sh
#
# Requires: jq, mikefarah yq v4.
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-decider-declarations.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 - $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "FAIL: mikefarah yq v4 is required" >&2; exit 1; }

T=$(mktemp -d)
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

# Stubs that record any call. The check must never reach one of them.
STUBS="$T/stubs"
CALLS="$T/network-calls"
mkdir -p "$STUBS"
for tool in curl wget gh koto; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 1\n' "$tool" "$CALLS" > "$STUBS/$tool"
    chmod +x "$STUBS/$tool"
done

TPL_REL="skills/demo/koto-templates/demo.md"
FIX_REL="skills/demo/koto-templates/demo.ask.pick.decider.jsonl"

# new_tree: a fresh root holding the demo template and a matching table.
ROOT=""
TABLE=""
new_tree() {
    ROOT=$(mktemp -d "$T/root.XXXXXX")
    mkdir -p "$ROOT/skills/demo/koto-templates"
    TABLE="$ROOT/modes.tsv"
    cat > "$ROOT/$TPL_REL" <<'EOF'
---
name: demo
version: "1.0"
initial_state: ask
variables:
  ITEM:
    description: The item.
    required: false
states:
  ask:
    gates:
      notes:
        type: context-exists
        key: notes.md
    accepts:
      pick:
        type: enum
        values: [a, b]
        required: true
        description: Which one?
        decider:
          answers:
            a: {description: "The first."}
            b: {description: "The second.", mode: never}
          escape: {value: unclear, description: "Can't tell."}
          inputs:
            - {context: notes.md, label: x, max_bytes: 20}
            - {var: ITEM, label: y}
      note:
        type: string
    transitions:
      - target: done
        when:
          pick: a
      - target: done
        when:
          pick: b
  done:
    terminal: true
---

## ask

Pick one.

## done

Done.
EOF
    printf 'skills/demo/koto-templates/demo.md\task\tpick\ta\tshadow\n' > "$TABLE"
    printf 'skills/demo/koto-templates/demo.md\task\tpick\tb\tnever\n' >> "$TABLE"
}

# cases <label> <n>: <n> fixture lines labelled <label>, appended, with ids
# numbered on from the file's last one.
SEQ=0
cases() {
    local i=0
    while [ "$i" -lt "$2" ]; do
        SEQ=$((SEQ + 1))
        printf '{"id":"c%d","inputs":{"x":"short","y":"item %d"},"expected":"%s"}\n' "$SEQ" "$SEQ" "$1" >> "$ROOT/$FIX_REL"
        i=$((i + 1))
    done
}

# fixture <a> <b> <unclear>: a fresh fixture file with that many of each.
fixture() {
    SEQ=0
    : > "$ROOT/$FIX_REL"
    cases a "$1"
    cases b "$2"
    cases unclear "$3"
}

# run_check: runs the check on ROOT and TABLE with the stubs first on PATH and
# no decider key. Sets OUT and RC.
OUT=""
RC=0
run_check() {
    OUT=$(env -u KOTO_DECIDER_API_KEY PATH="$STUBS:$PATH" /bin/bash "$CHECK" --root "$ROOT" --table "$TABLE" 2>&1)
    RC=$?
}

# expect_pass <name>
expect_pass() {
    if [ "$RC" -eq 0 ]; then
        pass "$1"
    else
        fail "$1" "rc $RC, output [$OUT]"
    fi
}

# expect_fail <name> <fixed-string>...: fails, and the output names the
# template, state, and field, and carries every string given.
expect_fail() {
    local name="$1" s
    shift
    if [ "$RC" -ne 1 ]; then
        fail "$name" "want rc 1, got rc $RC, output [$OUT]"
        return
    fi
    if ! printf '%s\n' "$OUT" | grep -Fq "FAIL: $TPL_REL state ask field pick:"; then
        fail "$name" "the failure does not name the template, state, and field: [$OUT]"
        return
    fi
    for s in "$@"; do
        if ! printf '%s\n' "$OUT" | grep -Fq -- "$s"; then
            fail "$name" "output lacks [$s]: [$OUT]"
            return
        fi
    done
    pass "$name"
}

# -- passing, and the boundaries ----------------------------------------------

new_tree
fixture 10 10 20
run_check
expect_pass "exactly 10 cases per value and 40 in all passes"
if printf '%s\n' "$OUT" | grep -Fq '40 cases (a=10 b=10 unclear=20)'; then
    pass "the passing run reports the counts per label"
else
    fail "the passing run reports the counts per label" "[$OUT]"
fi

new_tree
fixture 9 10 21
run_check
expect_fail "9 cases of one value fails, even at 40 in all" "has 9 case(s) labelled a" "at least 10"
if printf '%s\n' "$OUT" | grep -q 'in all'; then
    fail "9 cases of one value fails on that value alone" "the total was reported too: [$OUT]"
else
    pass "9 cases of one value fails on that value alone"
fi

new_tree
fixture 10 10 19
run_check
expect_fail "39 cases in all fails, even with 10 per value" "has 39 case(s) in all" "at least 40"
if printf '%s\n' "$OUT" | grep -q 'labelled'; then
    fail "39 cases in all fails on the total alone" "a value was reported too: [$OUT]"
else
    pass "39 cases in all fails on the total alone"
fi

# -- the fixture file ---------------------------------------------------------

new_tree
run_check
expect_fail "a missing fixture file fails" "no fixture file at $FIX_REL"

new_tree
fixture 10 10 20
printf '%s\n' '{"inputs":{"x":"a","y":"b"},"expected":"a"' >> "$ROOT/$FIX_REL"
run_check
expect_fail "a line that is not valid JSON fails" "line 41 is not valid JSON"

new_tree
fixture 10 10 20
printf '%s\n' '["a"]' >> "$ROOT/$FIX_REL"
run_check
expect_fail "a line that is not a JSON object fails" "line 41 is a JSON array, not an object"

new_tree
fixture 10 10 20
printf '%s\n' '{"inputs":{"x":"a","y":"b"},"expected":"a","note":"extra"}' >> "$ROOT/$FIX_REL"
run_check
expect_fail "a line with a key other than id, inputs, expected fails" "line 41 has key(s) note"

new_tree
fixture 10 10 20
printf '%s\n' '{"inputs":{"x":"a","y":"b"},"expected":"maybe"}' >> "$ROOT/$FIX_REL"
run_check
expect_fail "an expected that is neither a declared value nor the escape fails" 'line 41: expected "maybe" is neither a declared value (a, b) nor the escape (unclear)'

new_tree
fixture 10 10 20
printf '%s\n' '{"inputs":{"x":"a"},"expected":"a"}' >> "$ROOT/$FIX_REL"
run_check
expect_fail "a line missing a declared input label fails" "line 41: input labels [x] differ from the declared labels [x, y]"

new_tree
fixture 10 10 20
printf '%s\n' '{"inputs":{"x":"a","y":"b","z":"c"},"expected":"a"}' >> "$ROOT/$FIX_REL"
run_check
expect_fail "a line with an undeclared input label fails" "line 41: input labels [x, y, z] differ from the declared labels [x, y]"

new_tree
fixture 10 10 20
printf '%s\n' '{"inputs":{"x":"123456789012345678901","y":"b"},"expected":"a"}' >> "$ROOT/$FIX_REL"
run_check
expect_fail "an input over its declared max_bytes fails" "line 41: input x is 21 bytes, over its max_bytes of 20"

# Bytes, not characters: 7 three-byte characters are 21 bytes.
new_tree
fixture 10 10 20
printf '%s\n' '{"inputs":{"x":"ééééééééééé","y":"b"},"expected":"a"}' >> "$ROOT/$FIX_REL"
run_check
expect_fail "max_bytes counts UTF-8 bytes, not characters" "input x is 22 bytes, over its max_bytes of 20"

new_tree
fixture 10 10 20
printf '{"inputs":{"x":"12345678901234567890","y":"%s"},"expected":"a"}\n' "$(printf '%8192s' '' | tr ' ' y)" >> "$ROOT/$FIX_REL"
run_check
expect_pass "inputs exactly at max_bytes, declared and default, pass"

new_tree
fixture 10 10 20
printf '{"inputs":{"x":"a","y":"%s"},"expected":"a"}\n' "$(printf '%8193s' '' | tr ' ' y)" >> "$ROOT/$FIX_REL"
run_check
expect_fail "an input with no declared budget is held to 8192 bytes" "line 41: input y is 8193 bytes, over its max_bytes of 8192"

new_tree
fixture 10 10 20
printf '%s\n' '{"id":"c3","inputs":{"x":"a","y":"b"},"expected":"a"}' >> "$ROOT/$FIX_REL"
run_check
expect_fail "an id used twice fails" 'id "c3" is used on lines 3, 41'

# -- the modes table ----------------------------------------------------------

new_tree
fixture 10 10 20
printf 'skills/demo/koto-templates/demo.md\task\tpick\ta\tshadow\n' > "$TABLE"
printf 'skills/demo/koto-templates/demo.md\task\tpick\tb\tshadow\n' >> "$TABLE"
run_check
expect_fail "an effective mode that differs from its table row fails" "value [b] has effective mode never, but its row in modes.tsv says shadow"

# a declares no mode; its effective mode is shadow, not an empty string.
new_tree
fixture 10 10 20
printf 'skills/demo/koto-templates/demo.md\task\tpick\ta\tauto\n' > "$TABLE"
printf 'skills/demo/koto-templates/demo.md\task\tpick\tb\tnever\n' >> "$TABLE"
run_check
expect_fail "a value with no mode is held to shadow" "value [a] has effective mode shadow, but its row in modes.tsv says auto"

new_tree
fixture 10 10 20
printf 'skills/demo/koto-templates/demo.md\task\tpick\tc\tnever\n' >> "$TABLE"
run_check
expect_fail "a table row with no declared value fails" "has a row for value [c] (mode never), but no template declares that value"

new_tree
fixture 10 10 20
printf 'skills/demo/koto-templates/demo.md\task\tpick\ta\tshadow\n' > "$TABLE"
run_check
expect_fail "a declared value with no table row fails" "value [b] is declared (mode never) but has no row in modes.tsv"

# -- discovery ----------------------------------------------------------------

# A mermaid companion is a diagram. Even one carrying a decider-shaped front
# matter with no fixture is not checked.
new_tree
fixture 10 10 20
sed 's/^name: demo$/name: demo-diagram/' "$ROOT/$TPL_REL" > "$ROOT/skills/demo/koto-templates/demo.mermaid.md"
run_check
expect_pass "a *.mermaid.md file is not checked"

# A template with no declaration and an empty table pass together.
new_tree
yq --front-matter=process -i 'del(.states[].accepts[]?.decider)' "$ROOT/$TPL_REL"
: > "$TABLE"
run_check
expect_pass "a tree with no declarations and an empty table passes"

# -- no network ---------------------------------------------------------------

if [ ! -e "$CALLS" ]; then
    pass "no run called curl, wget, gh, or koto"
else
    fail "no run called curl, wget, gh, or koto" "$(cat "$CALLS")"
fi

# And the script text names none of them as a command, comments aside.
used=$(sed -e 's/^[[:space:]]*#.*$//' "$CHECK" | grep -nE '(^|[[:space:];|&(`$])(curl|wget|gh|koto)([[:space:]]|$)')
if [ -z "$used" ]; then
    pass "the script invokes no curl, wget, gh, or koto"
else
    fail "the script invokes no curl, wget, gh, or koto" "$used"
fi

# -- this repository ----------------------------------------------------------

OUT=$(env -u KOTO_DECIDER_API_KEY PATH="$STUBS:$PATH" /bin/bash "$CHECK" 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && [ "$(awk -F '\t' '!/^#/ && NF' "$REPO_ROOT/scripts/decider-declarations.tsv" | wc -l | tr -d ' ')" = 7 ]; then
    pass "this repository's declarations match its seven-row table and fixtures"
else
    fail "this repository's declarations match its seven-row table and fixtures" "rc $RC, output [$OUT]"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
