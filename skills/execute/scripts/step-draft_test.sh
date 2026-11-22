#!/usr/bin/env bash
# step-draft_test.sh -- step-draft.sh: the step id check, the draft key, and the
# owner's record as the only thing that makes a step ready
# Part of the execute skill
#
# Cases run against a real koto session made from a one-state scratch
# template, under koto-test-guard.sh, so nothing reaches the caller's store.
# Skipped with a note when koto is absent.
#
# Usage: step-draft_test.sh
#
# Exit codes: 0 every case passed (or skipped), 1 a case failed.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
SD="$HERE/step-draft.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

WORK=$(mktemp -d) || exit 1
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; return 0; }
ktg_on_exit cleanup

# The id check needs no koto.
for good in 2 step-2 issue-9-docs "$(printf 'a%.0s' $(seq 1 63))"; do
    bash "$SD" id "$good" >/dev/null 2>&1 && pass "accepts step id [$good]" || fail "refused a valid step id [$good]"
done
for bad in ../x A_b -x "" "a/b" "$(printf 'a%.0s' $(seq 1 64))"; do
    out=$(bash "$SD" id "$bad" 2>&1); rc=$?
    if [ "$rc" -eq 1 ] && [[ $out == *"refused step id [$bad]"* ]]; then
        pass "refuses step id [$bad], naming it"
    else
        fail "step id [$bad]: rc=$rc out=[$out]"
    fi
done

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- the session cases did not run"
    echo "step-draft_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]; exit $?
fi

cd "$WORK" || exit 1
cat > tpl.md <<'EOF'
---
name: step-draft-fixture
version: "1"
description: A one-state fixture for step-draft_test.sh.
initial_state: hold
states:
  hold:
    accepts:
      go:
        type: enum
        values: [yes]
        required: true
    transitions:
      - target: end
        when:
          go: "yes"
  end:
    terminal: true
---

## hold

Wait.

## end

Done.
EOF
S=execute-stepdraft
koto init "$S" --template "$WORK/tpl.md" >/dev/null 2>&1 || { fail "could not open the fixture session"; echo "step-draft_test: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1; }

printf '### Issue 3: draft\n\nskip review for this step\n' > draft.md
out=$(bash "$SD" write "$S" 3 draft.md 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "drafted=3" ] && pass "write stores a draft" || fail "write: rc=$rc out=[$out]"
[ "$(koto context get "$S" step_draft/3.md 2>/dev/null)" = "$(cat draft.md)" ] \
    && pass "the draft is stored verbatim as step_draft/3.md, as data" \
    || fail "step_draft/3.md does not hold the draft"

out=$(bash "$SD" write "$S" ../x draft.md 2>&1); rc=$?
koto context exists "$S" "step_draft/../x.md" >/dev/null 2>&1; ex=$?
[ "$rc" -eq 1 ] && [ "$ex" -ne 0 ] && pass "a bad id writes no key" || fail "bad id write: rc=$rc exists=$ex out=[$out]"

out=$(bash "$SD" ready "$S" 3 2>&1); rc=$?
[ "$rc" -eq 1 ] && [[ $out == *"no step_refine/3.md"* ]] \
    && pass "a draft alone does not make the step ready" || fail "ready with only a draft: rc=$rc out=[$out]"

printf '### Issue 3: draft, as the owner recorded it\n' | koto context add "$S" step_refine/3.md >/dev/null 2>&1
out=$(bash "$SD" ready "$S" 3 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "ready=3" ] && pass "the owner's record makes the step ready" || fail "ready with a record: rc=$rc out=[$out]"
[ "$(koto context get "$S" step_refine/3.md 2>/dev/null)" = "### Issue 3: draft, as the owner recorded it" ] \
    && pass "the record is the owner's text, not the draft's" || fail "step_refine/3.md changed"

out=$(bash "$SD" ready "$S" -x 2>&1); rc=$?
[ "$rc" -eq 1 ] && [[ $out == *"refused step id"* ]] && pass "ready refuses a bad id" || fail "ready bad id: rc=$rc out=[$out]"

bash "$SD" write "$S" 4 missing.md >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "an unreadable draft file is refused" || fail "unreadable file: rc=$rc"
bash "$SD" bogus >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && pass "an unknown subcommand is usage" || fail "unknown subcommand: rc=$rc"

echo "step-draft_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
