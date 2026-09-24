#!/usr/bin/env bash
#
# check-koto-floor_test.sh - tests for check-koto-floor.sh and its helpers
#
# Covers the logic the floor check depends on without a network or a real
# koto install: the strip, the decider and escape readers, template
# discovery, the transcript line and comparison, the escape-leak check, the
# installer's checksum and output checks, and the script's refusals -- a
# missing checksum tool, a missing or wrong yq, a missing jq, and a koto that
# reports the wrong version. None of those refusals reaches a download: each
# one fails before install.sh would be fetched, and curl is kept off PATH in
# the one case that would otherwise get that far.
#
# Usage:
#   bash scripts/check-koto-floor_test.sh
#
# Requires: jq, mikefarah yq v4, git.
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-koto-floor.sh"
FIXTURES="$SCRIPT_DIR/koto-floor/fixtures"
WORKFLOW="$REPO_ROOT/.github/workflows/check-koto-floor.yml"

# shellcheck source=koto-floor/lib.sh
. "$SCRIPT_DIR/koto-floor/lib.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 - $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
check_yq || { echo "FAIL: mikefarah yq v4 is required" >&2; exit 1; }

T=$(mktemp -d)
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

# path_without <dir> <name>...: fills <dir> with links to every executable on
# PATH except the named ones, first match wins, the way PATH lookup does. The
# script can then run with everything it needs but the tool under test.
path_without() {
    local dest="$1" d f base skip x
    shift
    mkdir -p "$dest"
    local IFS=:
    for d in $PATH; do
        [ -d "$d" ] || continue
        for f in "$d"/*; do
            [ -f "$f" ] && [ -x "$f" ] || continue
            base=${f##*/}
            skip=0
            for x in "$@"; do
                [ "$base" = "$x" ] && skip=1
            done
            [ "$skip" -eq 1 ] && continue
            [ -e "$dest/$base" ] || ln -s "$f" "$dest/$base"
        done
    done
}

# run_check <path> [env assignments...]: runs the script under that PATH with
# KOTO_BIN unset unless it is passed. Sets OUT and RC.
OUT=""
RC=0
run_check() {
    local p="$1"
    shift
    OUT=$(env -u KOTO_BIN -u RUNNER_TEMP HOME="$T/home" PATH="$p" "$@" /bin/bash "$CHECK" 2>&1)
    RC=$?
}

# -- strip --------------------------------------------------------------------

cp "$FIXTURES/decider.md" "$T/decider.md"
strip_decider "$T/decider.md"

if [ "$(decider_count "$FIXTURES/decider.md")" = 1 ] && [ "$(decider_count "$T/decider.md")" = 0 ]; then
    pass "the strip removes the fixture's decider block"
else
    fail "the strip removes the fixture's decider block" "counts $(decider_count "$FIXTURES/decider.md") -> $(decider_count "$T/decider.md")"
fi

want=$(yq --front-matter=extract -o=json 'del(.states[].accepts[]?.decider)' "$FIXTURES/decider.md")
got=$(yq --front-matter=extract -o=json '.' "$T/decider.md")
if [ -n "$want" ] && [ "$want" = "$got" ]; then
    pass "the strip leaves the rest of the front matter intact"
else
    fail "the strip leaves the rest of the front matter intact" "front matter changed beyond the decider block"
fi

if [ "$(yq --front-matter=extract '.states.question.accepts.verdict.values | join(",")' "$T/decider.md")" = "proceed,exit" ] \
    && [ "$(yq --front-matter=extract '.states.question.accepts.verdict.description' "$T/decider.md")" = "Is the item clear enough to proceed?" ]; then
    pass "the stripped field keeps its values and description"
else
    fail "the stripped field keeps its values and description" "$(yq --front-matter=extract '.states.question.accepts.verdict' "$T/decider.md")"
fi

body() { awk 'n >= 2 {print} /^---$/ {n++}' "$1"; }
if [ "$(body "$FIXTURES/decider.md")" = "$(body "$T/decider.md")" ] && [ -n "$(body "$T/decider.md")" ]; then
    pass "the strip leaves the markdown body alone"
else
    fail "the strip leaves the markdown body alone" "the body changed"
fi

if [ "$(decider_count "$FIXTURES/child-success.md")" = 0 ]; then
    pass "a template with no decider key counts zero"
else
    fail "a template with no decider key counts zero" "$(decider_count "$FIXTURES/child-success.md")"
fi

# A decider somewhere the strip does not reach must still be counted, so the
# script reports it rather than calling the strip clean.
cat > "$T/misplaced.md" <<'EOF'
---
name: misplaced
initial_state: a
states:
  a:
    decider: {escape: {value: nope}}
    terminal: true
---

## a

A.
EOF
strip_decider "$T/misplaced.md"
if [ "$(decider_count "$T/misplaced.md")" = 1 ]; then
    pass "a decider outside states.*.accepts.* survives the strip and is counted"
else
    fail "a decider outside states.*.accepts.* survives the strip and is counted" "$(decider_count "$T/misplaced.md")"
fi

# -- escape collection --------------------------------------------------------

if [ "$(collect_escapes "$FIXTURES/decider.md")" = "unclear" ]; then
    pass "the escape collector returns the fixture's escape value"
else
    fail "the escape collector returns the fixture's escape value" "[$(collect_escapes "$FIXTURES/decider.md")]"
fi

if [ -z "$(collect_escapes "$FIXTURES/child-failure.md")" ]; then
    pass "a template with no declarations yields no escape values"
else
    fail "a template with no declarations yields no escape values" "[$(collect_escapes "$FIXTURES/child-failure.md")]"
fi

# -- discovery ----------------------------------------------------------------

mkdir -p "$T/root/skills/alpha/koto-templates" "$T/root/skills/beta/koto-templates" "$T/root/scripts/koto-floor/fixtures"
: > "$T/root/skills/alpha/koto-templates/alpha.md"
: > "$T/root/skills/alpha/koto-templates/alpha.mermaid.md"
: > "$T/root/skills/beta/koto-templates/beta.md"
: > "$T/root/scripts/koto-floor/fixtures/f.md"
got=$(list_templates "$T/root" | tr '\n' ' ')
if [ "$got" = "skills/alpha/koto-templates/alpha.md skills/beta/koto-templates/beta.md scripts/koto-floor/fixtures/f.md " ]; then
    pass "templates are discovered by glob, mermaid companions excluded"
else
    fail "templates are discovered by glob, mermaid companions excluded" "[$got]"
fi

got=$(list_templates "$REPO_ROOT")
if printf '%s\n' "$got" | grep -qx 'skills/execute/koto-templates/execute.md' \
    && printf '%s\n' "$got" | grep -qx 'skills/work-on/koto-templates/work-on.md' \
    && printf '%s\n' "$got" | grep -qx 'scripts/koto-floor/fixtures/decider.md' \
    && ! printf '%s\n' "$got" | grep -q 'mermaid'; then
    pass "the checkout's templates and the decider fixture are all covered"
else
    fail "the checkout's templates and the decider fixture are all covered" "[$got]"
fi

# -- transcripts --------------------------------------------------------------

line=$(printf '%s' '{"state":"entry","action":"evidence_required","advanced":false}' | transcript_line)
if [ "$line" = "$(printf 'entry\tevidence_required\tfalse')" ]; then
    pass "a transcript line records state, action, and advanced -- false included"
else
    fail "a transcript line records state, action, and advanced -- false included" "[$line]"
fi

line=$(printf '%s' '{"error":{"code":"precondition_failed","message":"x"}}' | transcript_line)
if [ "$line" = "$(printf -- '-\terror:precondition_failed\t-')" ]; then
    pass "an error response is recorded with its code"
else
    fail "an error response is recorded with its code" "[$line]"
fi

printf 'a\tevidence_required\ttrue\nfinal\tb\n' > "$T/t1"
cp "$T/t1" "$T/t2"
printf 'a\tevidence_required\ttrue\nfinal\tc\n' > "$T/t3"
if compare_transcripts "$T/t1" "$T/t2" same 2>/dev/null; then
    pass "identical transcripts compare equal"
else
    fail "identical transcripts compare equal" "reported a difference"
fi
err=$(compare_transcripts "$T/t1" "$T/t3" differing 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$err" | grep -q '^< final	b$' && printf '%s\n' "$err" | grep -q '^> final	c$'; then
    pass "differing transcripts fail with a diff"
else
    fail "differing transcripts fail with a diff" "rc $rc, output [$err]"
fi

# -- escape leaks -------------------------------------------------------------

printf 'unclear\n' > "$T/escapes"
: > "$T/none"
printf '%s\n' '{"expects":{"fields":{"verdict":{"type":"enum","values":["proceed","exit"]}},"options":[{"target":"x","when":{"verdict":"proceed","gates.g.exists":true}}]}}' > "$T/clean.jsonl"
printf '%s\n' '{"expects":{"fields":{"verdict":{"type":"enum","values":["proceed","exit","unclear"]}}}}' > "$T/leak-field.jsonl"
printf '%s\n' '{"expects":{"fields":{"verdict":{"type":"enum","values":["proceed"]}},"options":[{"target":"y","when":{"verdict":"unclear"}}]}}' > "$T/leak-option.jsonl"
if [ -z "$(escape_leaks "$T/escapes" "$T/clean.jsonl")" ]; then
    pass "responses that never offer the escape value pass"
else
    fail "responses that never offer the escape value pass" "[$(escape_leaks "$T/escapes" "$T/clean.jsonl")]"
fi
if [ "$(escape_leaks "$T/escapes" "$T/clean.jsonl" "$T/leak-field.jsonl")" = "unclear" ]; then
    pass "an escape value among a field's values is reported"
else
    fail "an escape value among a field's values is reported" "[$(escape_leaks "$T/escapes" "$T/leak-field.jsonl")]"
fi
if [ "$(escape_leaks "$T/escapes" "$T/leak-option.jsonl")" = "unclear" ]; then
    pass "an escape value an option routes on is reported"
else
    fail "an escape value an option routes on is reported" "[$(escape_leaks "$T/escapes" "$T/leak-option.jsonl")]"
fi
if [ -z "$(escape_leaks "$T/none" "$T/leak-field.jsonl")" ]; then
    pass "with no declarations the check still runs and finds nothing"
else
    fail "with no declarations the check still runs and finds nothing" "reported a leak"
fi

# -- installer checks ---------------------------------------------------------

printf 'hello\n' > "$T/blob"
sum=$(sha256_of "$T/blob")
if [ "$sum" = "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03" ] && verify_sha256 "$T/blob" "$sum" 2>/dev/null; then
    pass "a matching SHA-256 verifies"
else
    fail "a matching SHA-256 verifies" "got [$sum]"
fi
if ! verify_sha256 "$T/blob" "0000000000000000000000000000000000000000000000000000000000000000" 2>/dev/null; then
    pass "a mismatched SHA-256 fails"
else
    fail "a mismatched SHA-256 fails" "it verified"
fi

printf 'Downloading koto-linux-amd64...\nVerifying checksum...\nWarning: Could not verify checksum (sha256sum/shasum not found)\n' > "$T/install-unverified.log"
printf 'Downloading koto-linux-amd64...\nVerifying checksum...\nInstalling to /x/bin...\n' > "$T/install-ok.log"
if ! check_installer_output "$T/install-unverified.log" 2>/dev/null && check_installer_output "$T/install-ok.log" 2>/dev/null; then
    pass "installer output saying it could not verify the checksum fails"
else
    fail "installer output saying it could not verify the checksum fails" "not detected, or a clean log was refused"
fi

if printf '%s' "$KOTO_INSTALLER_COMMIT" | grep -Eq '^[0-9a-f]{40}$' \
    && [ "$KOTO_INSTALLER_URL" = "https://raw.githubusercontent.com/tsukumogami/koto/$KOTO_INSTALLER_COMMIT/install.sh" ] \
    && printf '%s' "$KOTO_INSTALLER_SHA256" | grep -Eq '^[0-9a-f]{64}$'; then
    pass "install.sh is fetched from a full 40-character commit and checked against a SHA-256"
else
    fail "install.sh is fetched from a full 40-character commit and checked against a SHA-256" "$KOTO_INSTALLER_URL"
fi

if ! grep -Eq 'koto/(main|master|refs/heads)[/]' "$CHECK" "$SCRIPT_DIR/koto-floor/lib.sh" "$WORKFLOW" 2>/dev/null \
    && [ -f "$WORKFLOW" ] && ! grep -Eq 'curl|wget|raw\.githubusercontent' "$WORKFLOW"; then
    pass "neither the script nor the workflow fetches install.sh from a branch"
else
    fail "neither the script nor the workflow fetches install.sh from a branch" "found a branch URL, or the workflow downloads something itself"
fi

# Every koto call in the script, the library, and the scenarios goes through
# $KOTO_BIN. Comments are dropped first; what is left must never start a
# command with a bare `koto <subcommand>`.
bare=$(for f in "$CHECK" "$SCRIPT_DIR/koto-floor/lib.sh" "$SCRIPT_DIR"/koto-floor/scenarios/*.sh; do
    sed -e 's/^[[:space:]]*#.*$//' "$f" | grep -nE '(^|[[:space:];|&(`])koto[[:space:]]+(init|next|status|context|template|session|version|rewind|cancel|workflows)([[:space:]]|$)' | sed "s|^|${f##*/}:|"
done)
if [ -z "$bare" ]; then
    pass "no bare koto invocation in the script, the library, or the scenarios"
else
    fail "no bare koto invocation in the script, the library, or the scenarios" "$bare"
fi

# -- the script's refusals ----------------------------------------------------

mkdir -p "$T/home"

path_without "$T/p-nosha" sha256sum shasum curl
run_check "$T/p-nosha"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'sha256sum' && printf '%s' "$OUT" | grep -q 'shasum'; then
    pass "a missing checksum tool fails, naming sha256sum and shasum"
else
    fail "a missing checksum tool fails, naming sha256sum and shasum" "rc $RC, output [$OUT]"
fi

path_without "$T/p-noyq" yq
run_check "$T/p-noyq"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'yq is required'; then
    pass "a missing yq fails, naming yq"
else
    fail "a missing yq fails, naming yq" "rc $RC, output [$OUT]"
fi

path_without "$T/p-pyyq" yq
cat > "$T/p-pyyq/yq" <<'EOF'
#!/bin/sh
echo "yq 3.4.3"
EOF
chmod +x "$T/p-pyyq/yq"
run_check "$T/p-pyyq"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'mikefarah yq v4'; then
    pass "a yq that is not mikefarah v4 fails, naming yq"
else
    fail "a yq that is not mikefarah v4 fails, naming yq" "rc $RC, output [$OUT]"
fi

path_without "$T/p-nojq" jq
run_check "$T/p-nojq"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'jq is required'; then
    pass "a missing jq fails, naming jq"
else
    fail "a missing jq fails, naming jq" "rc $RC, output [$OUT]"
fi

cat > "$T/koto-old" <<'EOF'
#!/bin/sh
[ "$1" = version ] && { echo "koto 0.12.1 (0000000 2026-01-01T00:00:00Z)"; exit 0; }
echo "stub koto: $*" >&2
exit 1
EOF
chmod +x "$T/koto-old"
run_check "$PATH" KOTO_BIN="$T/koto-old"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'want 0.12.2'; then
    pass "a koto reporting the wrong version fails"
else
    fail "a koto reporting the wrong version fails" "rc $RC, output [$OUT]"
fi

run_check "$PATH" KOTO_BIN="koto"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'absolute path'; then
    pass "a KOTO_BIN that is not an absolute path is refused"
else
    fail "a KOTO_BIN that is not an absolute path is refused" "rc $RC, output [$OUT]"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
