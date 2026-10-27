#!/usr/bin/env bash
# doc-events_test.sh -- does doc-events.sh record the right section writes and
# fix entries, and refuse what it should?
#
# The same stand-ins as doc-check_test.sh (scripts/lib/doc-check-testlib.sh):
# a stub koto keeping sessions as directories and a stub `shirabe`, so the
# suite needs only bash, git and jq and runs on the bash 3.2 floor.
#
# Usage: doc-events_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
EVENTS="$SCRIPT_DIR/doc-events.sh"
CHECK="$SCRIPT_DIR/doc-check.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -x "$EVENTS" ] || { echo "$EVENTS is missing or not executable" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/doc-events-test.XXXXXX") || exit 2
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 2
cleanup() { case "${WORKDIR:-}" in */doc-events-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
trap cleanup EXIT

# shellcheck source=lib/doc-check-testlib.sh
. "$SCRIPT_DIR/lib/doc-check-testlib.sh"
dct_setup "$WORKDIR"

OUT="$WORKDIR/out"
ERR="$WORKDIR/err"
RC=0
ev() { (cd "$REPO" && "$EVENTS" "$@") > "$OUT" 2> "$ERR"; RC=$?; }
show() { printf 'rc=%s out=[%s] err=[%s]' "$RC" "$(tr '\n' '|' < "$OUT")" "$(head -c 400 "$ERR" | tr '\n' '|')"; }
recorded() { grep '^[^ ]* section-written ' "$STUB_KOTO_DIR/review.log" | sed 's/^[^ ]* section-written //' | sort | tr '\n' '|'; }

PRD="docs/prds/PRD-t.md"
write_prd() { # <problem text> [<goals text>]
    mkdir -p "$REPO/docs/prds"
    {
        printf -- '---\nschema: prd/v1\nstatus: Draft\n---\n\n# PRD\n\n## Status\n\nDraft\n\n## Problem Statement\n\n%s\n\n' "$1"
        printf '```\n## Goals\nnot a heading, inside a fence\n```\n\n## Notes\n\nfree text %s\n' "$1"
        [ -z "${2-}" ] || printf '\n## Goals\n\n%s\n' "$2"
    } > "$REPO/$PRD"
}

# --- sections ---------------------------------------------------------------------

dct_repo sections
dct_session prd-t
write_prd "first problem"
dct_commit "docs: draft"
A=$(dct_head)
: > "$STUB_KOTO_DIR/review.log"
ev sections --doc "$PRD" --format prd
if [ "$RC" -eq 0 ] && [ "$(recorded)" = "--doc-format prd --section problem-statement --write first|--doc-format prd --section status --write first|" ] \
    && grep -qx 'doc-events: section status first' "$OUT"; then
    pass "no recorded commit: every present required section is first; a section the format doesn't require and a fenced heading are ignored"
else
    fail "first sections: $(show) recorded=[$(recorded)]"
fi
[ "$(dct_key prd-t work/doc-check.json | jq -r '.sections_commit')" = "$A" ] \
    && pass "the recorded commit is updated to HEAD afterwards" || fail "sections_commit: [$(dct_key prd-t work/doc-check.json)]"

write_prd "second problem" "the goals"
dct_commit "docs: more"
: > "$STUB_KOTO_DIR/review.log"
ev sections --doc "$PRD" --format prd
if [ "$RC" -eq 0 ] && [ "$(recorded)" = "--doc-format prd --section goals --write first|--doc-format prd --section problem-statement --write rewrite|" ]; then
    pass "a new section is first, a changed one rewrite, an unchanged one and a non-required one nothing"
else
    fail "second sections: $(show) recorded=[$(recorded)]"
fi
: > "$STUB_KOTO_DIR/review.log"
ev sections --doc "$PRD" --format prd
[ "$RC" -eq 0 ] && [ ! -s "$OUT" ] && [ ! -s "$STUB_KOTO_DIR/review.log" ] \
    && pass "run again on the same commit: nothing changed, nothing recorded" || fail "rerun: $(show)"
: > "$STUB_KOTO_DIR/review.log"
ev sections --doc "$PRD" --format prd --since "$A"
[ "$(recorded)" = "--doc-format prd --section goals --write first|--doc-format prd --section problem-statement --write rewrite|" ] \
    && pass "--since diffs from the commit given" || fail "--since: $(show) recorded=[$(recorded)]"
STUB_KOTO_REVIEW=missing ev sections --doc "$PRD" --format prd --since "$A"
if [ "$RC" -eq 0 ] && [ "$(grep -c 'notice: telemetry for section' "$ERR")" -eq 2 ] && [ "$(awk 'END { print NR }' "$OUT")" -eq 2 ]; then
    pass "a koto without the verb: one notice per failed call, the same output, exit 0"
else
    fail "sections without the verb: $(show)"
fi

# --- fix --------------------------------------------------------------------------

dct_repo fix
dct_session prd-t
write_prd "a problem"
dct_commit "docs: draft"
ev fix --doc "$PRD" --format prd --answers check_fail
[ "$RC" -eq 0 ] && [ ! -s "$OUT" ] && [ ! -s "$STUB_KOTO_DIR/review.log" ] && grep -q 'no check of' "$ERR" \
    && pass "no recorded check: no fix entry, a notice, exit 0" || fail "fix without a check: $(show)"

pline=$(grep -n '^a problem$' "$REPO/$PRD" | cut -d: -f1)
dct_envelope 2 \
    '{"code":"FC04","severity":"error","message":"[FC04] missing required section '"'"'## Goals'"'"'","file":"x","line":null}' \
    '{"code":"FC01","severity":"error","message":"[FC01] missing field","file":"x","line":2}' \
    "{\"code\":\"R6\",\"severity\":\"error\",\"message\":\"[R6] upstream\",\"file\":\"x\",\"line\":$pline}"
(cd "$REPO" && "$CHECK" --doc "$PRD" --format prd --moment pre_jury --phase 4 --topic t --skill prd) >/dev/null 2>&1
: > "$STUB_KOTO_DIR/review.log"
ev fix --doc "$PRD" --format prd --answers check_fail
call=$(sed -n 1p "$STUB_KOTO_DIR/review.log")
batch=$(sed -n 's/^file://p' "$STUB_KOTO_DIR/review.log")
want='[{"check_rule":"docs/required-fields","rule_id":"docs/required-fields","section":"other"},{"check_rule":"docs/required-sections","rule_id":"docs/required-sections","section":"goals"},{"check_rule":"docs/upstream-resolves","rule_id":"docs/upstream-resolves","section":"problem-statement"}]'
case "$call" in
    "prd-t fix --doc-format prd --answers check_fail --file "*)
        if [ "$(printf '%s' "$batch" | jq -c 'map(to_entries | sort_by(.key) | from_entries) | sort_by(.rule_id)')" = "$want" ] \
            && [ "$(awk 'END { print NR }' "$OUT")" -eq 3 ]; then
            pass "one fix entry per (rule, section), check_rule the failing rule, sections from the check or the finding's line"
        else
            fail "fix batch: [$batch] $(show)"
        fi ;;
    *) fail "fix call: [$call] $(show)" ;;
esac

dct_envelope 0
(cd "$REPO" && "$CHECK" --doc "$PRD" --format prd --moment post_fix --phase 4 --topic t --skill prd) >/dev/null 2>&1
: > "$STUB_KOTO_DIR/review.log"
ev fix --doc "$PRD" --format prd --answers check_fail
[ "$RC" -eq 0 ] && [ ! -s "$OUT" ] && [ ! -s "$STUB_KOTO_DIR/review.log" ] \
    && pass "a check with no failure: no fix entry written" || fail "fix after a clean check: $(show)"

# --- input hardening ----------------------------------------------------------------

refused() { # <label> <args...>
    local label=$1
    shift
    : > "$STUB_KOTO_DIR/review.log"
    ev "$@"
    if [ "$RC" -eq 2 ] && [ ! -s "$OUT" ] && [ ! -s "$STUB_KOTO_DIR/review.log" ]; then
        pass "refused: $label"
    else
        fail "refused: $label: $(show)"
    fi
}
refused "an unknown subcommand" record --doc "$PRD" --format prd
refused "--answers jury_fail (not recorded here)" fix --doc "$PRD" --format prd --answers jury_fail
refused "--answers outside its set" fix --doc "$PRD" --format prd --answers maybe
refused "--answers on sections" sections --doc "$PRD" --format prd --answers check_fail
refused "--since on fix" fix --doc "$PRD" --format prd --answers check_fail --since "$(dct_head)"
refused "--since abbreviated" sections --doc "$PRD" --format prd --since "$(dct_head | cut -c1-12)"
refused "--since not hexadecimal" sections --doc "$PRD" --format prd --since HEAD
refused "--since naming no commit" sections --doc "$PRD" --format prd --since 0123456789012345678901234567890123456789
refused "--format outside the seven" sections --doc "$PRD" --format comp
refused "--skill outside the skill pattern" sections --doc "$PRD" --format prd --skill 'P;x'
refused "--doc not a canonical path" sections --doc CLAUDE.md --format prd
refused "--doc another format's path" sections --doc "$PRD" --format brief
mkdir -p "$WORKDIR/outside/docs/prds"
cp "$REPO/$PRD" "$WORKDIR/outside/docs/prds/PRD-t.md"
ln -s "$WORKDIR/outside/docs/prds/PRD-t.md" "$REPO/link-out.md"
refused "--doc a symlink resolving outside the repository" sections --doc link-out.md --format prd
refused "--doc with a bad topic" sections --doc docs/prds/PRD-Bad_Topic.md --format prd

echo
echo "doc-events_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
