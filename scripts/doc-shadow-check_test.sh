#!/usr/bin/env bash
# doc-shadow-check_test.sh -- does doc-shadow-check.sh record one result per
# (document, document rule) at /scope publish, and always exit 0?
#
# The same stand-ins as doc-check_test.sh (scripts/lib/doc-check-testlib.sh):
# a stub `shirabe` answering with a prepared envelope and a stub koto that logs
# every `review record` call with the --file contents.
#
# Usage: doc-shadow-check_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
CHECK="$SCRIPT_DIR/doc-shadow-check.sh"
PHASES="$SCRIPT_DIR/../references/doc-check-phases.json"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -x "$CHECK" ] || { echo "$CHECK is missing or not executable" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/doc-shadow-check-test.XXXXXX") || exit 2
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 2
cleanup() { case "${WORKDIR:-}" in */doc-shadow-check-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
trap cleanup EXIT

# shellcheck source=lib/doc-check-testlib.sh
. "$SCRIPT_DIR/lib/doc-check-testlib.sh"
dct_setup "$WORKDIR"

OUT="$WORKDIR/out"
ERR="$WORKDIR/err"
LOG="$STUB_KOTO_DIR/review.log"
RC=0
run() { (cd "$REPO" && "$CHECK" "$@") > "$OUT" 2> "$ERR"; RC=$?; }
show() { printf 'rc=%s out=[%s] err=[%s]' "$RC" "$(head -c 600 "$OUT" | tr '\n' '|')" "$(head -c 400 "$ERR" | tr '\n' '|')"; }
recorded() { sed -n 's/^file://p' "$LOG" | jq -c '.[]'; }
outcome_of() { recorded | jq -r --arg d "$1" --arg r "$2" 'select(.doc_type == $d and .rule_id == $r) | .outcome'; }
rules_of() { jq -r --arg f "$1" '.formats[$f].rules[]' "$PHASES"; }
write_prd() {
    mkdir -p "$REPO/docs/prds"
    printf -- '---\nschema: prd/v1\nstatus: Draft\n---\n\n# PRD\n\n## Status\n\nDraft\n' > "$REPO/docs/prds/PRD-t.md"
}

# --- R10: a known violation fails its rule, the rest pass ---------------------------

dct_repo violation
dct_session scope-t
write_prd
dct_commit "docs: prd"
dct_envelope 2 '{"code":"FC01","severity":"error","message":"[FC01] missing field problem","line":1}'
run --topic t
fails=$(recorded | jq -r 'select(.outcome == "failed") | .rule_id' | tr '\n' ' ')
passes=$(recorded | jq -r 'select(.outcome == "passed") | .rule_id' | sort | tr '\n' ' ')
want_pass=$(rules_of prd | grep -vxF docs/required-fields | sort | tr '\n' ' ')
if [ "$RC" -eq 0 ] && [ "$fails" = "docs/required-fields " ] && [ "$passes" = "$want_pass" ]; then
    pass "R10: a known violation records failed for its rule and passed for the others"
else
    fail "R10: fails=[$fails] passes=[$passes] $(show)"
fi
n=$(recorded | wc -l | tr -d ' ')
[ "$n" -eq "$(rules_of prd | wc -l | tr -d ' ')" ] && pass "R10: one result per (document, document rule)" \
    || fail "R10: $n results"
recorded | jq -e -s 'all(.[]; .doc_type == "prd" and .schema == "prd/v1" and (keys == ["doc_type","outcome","rule_id","schema"]))' >/dev/null \
    && pass "R10: entries carry the doc type and schema in koto's doc-checks shape" || fail "R10: shape [$(recorded | head -n 2)]"
grep -q '^scope-t doc-checks --file ' "$LOG" && pass "R10: the results go on the scope session" || fail "R10: session [$(cat "$LOG")]"
grep -qF 'missing field problem' "$OUT" "$ERR" "$LOG" && fail "R10: validator text was printed or recorded" \
    || pass "R10: no validator text is printed or recorded"
grep -qxF 'doc-shadow-check: prd docs/required-fields failed' "$OUT" && pass "R10: each result is printed" || fail "R10: $(show)"

# --- R10: the validator reaches no verdict -----------------------------------------

dct_repo validator-fails
dct_session scope-t
write_prd
dct_commit "docs: prd"
printf 'not json\n' > "$STUB_JSON"
STUB_RC=1
run --topic t
others=$(recorded | jq -r 'select(.outcome != "error") | .rule_id')
if [ "$RC" -eq 0 ] && [ -z "$others" ] && [ -n "$(recorded)" ]; then
    pass "R10: a validator failure records error for every rule and exits 0"
else
    fail "R10: validator failure $(show) [$others]"
fi

dct_repo canary
dct_session scope-t
write_prd
dct_commit "docs: prd"
dct_envelope 0
export STUB_CANARY=none
run --topic t
unset STUB_CANARY
[ "$RC" -eq 0 ] && [ -z "$(recorded | jq -r 'select(.outcome != "error")')" ] \
    && pass "R10: a validator that fails its canary records error" || fail "R10: canary $(show)"

# A code that maps to no rule of the format leaves passing rules undecided.
dct_repo unmapped
dct_session scope-t
write_prd
dct_commit "docs: prd"
dct_envelope 2 '{"code":"FC99","severity":"error","message":"x","line":1}'
run --topic t
[ "$RC" -eq 0 ] && [ -z "$(recorded | jq -r 'select(.outcome == "passed")')" ] \
    && pass "R10: an unmapped code turns the passing rules into error" || fail "R10: unmapped $(show)"

# --- several documents, none, and best effort ---------------------------------------

dct_repo several
dct_session scope-t
write_prd
mkdir -p "$REPO/docs/plans"
printf -- '---\nschema: plan/v2\nstatus: Draft\n---\n\n# PLAN\n' > "$REPO/docs/plans/PLAN-t.md"
dct_commit "docs: prd and plan"
dct_envelope 0
run --topic t
types=$(recorded | jq -r '.doc_type' | sort -u | tr '\n' ' ')
[ "$RC" -eq 0 ] && [ "$types" = "plan prd " ] && [ "$(grep -c ' doc-checks ' "$LOG")" -eq 2 ] \
    && pass "R10: each existing document gets its own batch" || fail "R10: several [$types] $(show)"
[ -z "$(recorded | jq -r 'select(.doc_type == "plan" and .schema != "plan/v2")')" ] \
    && pass "R10: the plan's schema value is passed as is" || fail "R10: plan schema"

dct_repo none
dct_session scope-t
run --topic t
[ "$RC" -eq 0 ] && [ ! -s "$LOG" ] && pass "R10: a topic with no documents records nothing" || fail "R10: none $(show)"

for mode in missing refuse; do
    dct_repo "koto-$mode"
    dct_session scope-t
    write_prd
    dct_commit "docs: prd"
    dct_envelope 0
    export STUB_KOTO_REVIEW=$mode
    run --topic t
    unset STUB_KOTO_REVIEW
    [ "$RC" -eq 0 ] && [ "$(grep -c 'notice: telemetry for the document checks' "$ERR")" -eq 1 ] \
        && pass "R10: a stub koto in mode $mode leaves it exiting 0 with one stderr line" || fail "R10: $mode $(show)"
done

dct_repo usage
run --topic 'Bad Topic'
[ "$RC" -eq 2 ] && pass "a bad topic is refused" || fail "topic $(show)"
run
[ "$RC" -eq 2 ] && pass "no --topic is a usage error" || fail "usage $(show)"

echo
echo "doc-shadow-check_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
