#!/usr/bin/env bash
# extract-context_test.sh -- extract-context.sh writes no file
# Part of the work-on skill
#
# extract-context.sh used to fall back to a context file in the branch's staging
# folder when it had no koto session or no koto binary. It now stores context in a koto
# session and nowhere else; the two ways it can't are failures the caller reads
# from the JSON it prints. This harness runs the script both ways and asserts:
#
#   without --session                       status failed, context_available
#                                           false, a warning naming koto
#   with --session and no koto on PATH      the same
#   in both                                 exit 0, no file created in the
#                                           working directory, and no
#                                           context_file field
#
# It also checks the script's header and source carry no context_file.
#
# Usage: extract-context_test.sh
#
# Exit codes:
#   0 -- all cases pass (or jq is absent and the run skipped)
#   1 -- one or more cases failed
#
# Needs only bash and jq; no koto, so every case runs on the bash 3.2 floor.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/../references/scripts/extract-context.sh"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$SCRIPT" ] || { echo "FAIL: extract-context.sh not found at $SCRIPT" >&2; exit 1; }
REAL_JQ=$(command -v jq 2>/dev/null) || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }

WORKDIR=$(mktemp -d)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# A PATH with jq and nothing else: no koto, no gh.
BIN="$WORKDIR/bin"
mkdir -p "$BIN"
ln -s "$REAL_JQ" "$BIN/jq"
RUN="$WORKDIR/run"
mkdir -p "$RUN"

OUT=""
RC=0
# run_script <args...> -- run the script from an empty directory with only jq on PATH.
run_script() {
    RC=0
    OUT=$(cd "$RUN" && PATH="$BIN:/usr/bin:/bin" "$BASH" "$SCRIPT" "$@" 2>/dev/null) || RC=$?
}

# Only reachable if /usr/bin or /bin holds a koto; then the no-koto case can't be built.
if PATH="$BIN:/usr/bin:/bin" command -v koto >/dev/null 2>&1; then
    echo "SKIP: a koto in /usr/bin or /bin -- the koto-absent case cannot remove it from PATH"
    exit 0
fi

expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected [$2], got [$3]"; fi; }

check_failed_json() { # check_failed_json <label>
    local label="$1" status avail warn_has_koto ctx
    status=$(printf '%s' "$OUT" | jq -r '.status' 2>/dev/null)
    avail=$(printf '%s' "$OUT" | jq -r '.context_available' 2>/dev/null)
    warn_has_koto=$(printf '%s' "$OUT" | jq -r '[.warnings[] | select(test("koto"))] | length' 2>/dev/null)
    ctx=$(printf '%s' "$OUT" | jq -r 'has("context_file")' 2>/dev/null)
    expect "$label: exits 0" "0" "$RC"
    expect "$label: status is failed" "failed" "$status"
    expect "$label: context_available is false" "false" "$avail"
    if [ "${warn_has_koto:-0}" -ge 1 ] 2>/dev/null; then pass "$label: a warning names koto"; else fail "$label: no warning names koto: $OUT"; fi
    expect "$label: the JSON carries no context_file" "false" "$ctx"
    if [ -z "$(ls -A "$RUN")" ]; then pass "$label: creates no file"; else fail "$label: left files in the working directory: $(ls -A "$RUN")"; fi
}

echo "extract-context_test.sh"
echo

run_script 123
check_failed_json "without --session"

run_script 123 --session some-session
check_failed_json "with --session and no koto on PATH"

# The header, usage line and JSON contract carry no fallback. The old file's
# name is built from two pieces so this file doesn't name it either.
OLD_FILE="IMPLEMENTATION""_CONTEXT"
PATTERN="(^|[^a-z_])context_file([^a-z_]|\$)|$OLD_FILE|wip/"
if grep -qE "$PATTERN" "$SCRIPT"; then
    fail "extract-context.sh still names the fallback file or the folder: $(grep -nE "$PATTERN" "$SCRIPT")"
else
    pass "extract-context.sh names no context_file field, fallback file or wip/ path"
fi

echo
echo "extract-context_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
