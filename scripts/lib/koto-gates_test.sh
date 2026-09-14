#!/usr/bin/env bash
# koto-gates_test.sh — reading a gate must not depend on what follows it.
#
# koto_gate_command used to pipe into an awk that exited at the first match. The
# writer upstream then took SIGPIPE, and a caller running under `set -o pipefail`
# and `set -e` — which both of this library's callers do — died with status 141
# and NO output: every assertion it had already printed said PASS, and then the
# run simply stopped. A visibly successful run that failed.
#
# Whether it fired depended on how much the writer still had to say after the
# match, so it stayed invisible until a template grew gates BELOW the one being
# read. That is the shape Case 1 builds, and it is why the fixture is large: the
# writer has to still be writing when the reader would have exited.
#
# WHY CASE 1 WATCHES THE WRITER RATHER THAN THE EXIT CODE. The first version of
# this test asserted the symptom — a 141 from the caller — and passed against the
# pre-fix library on this host, which would have made it a pin that pins nothing.
# Two things decide whether the symptom appears: the shell (bash 3.2 turns the
# writer's SIGPIPE into a fatal status where bash 5 does not) and the awk
# implementation (it reproduces under the floor image's BusyBox awk and not under
# mawk, which is what Linux runners use). Either one is enough to make a
# symptom-watching test silently stop testing.
#
# Watching whether the writer finished is true of the defect itself rather than
# of one platform's reaction to it. Measured against the reverted library: fails
# under mawk on bash 5, and under BusyBox awk on bash 3.2.
#
# Usage: koto-gates_test.sh
# Exit codes: 0 all pass, 1 any failed.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=koto-gates.sh
. "$SCRIPT_DIR/koto-gates.sh"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMPS=()
cleanup() { for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; return 0; }
trap cleanup EXIT

# build_template <dir> <gates-after> — a template whose FIRST gate is the one
# under test, followed by <gates-after> more. Each trailing gate carries a long
# command so the rows after the match exceed a pipe buffer; a handful of short
# ones would let the writer finish before the reader exited, and the case would
# pass against the defect it exists to catch.
build_template() {
    local dir="$1" after="$2" i
    {
        printf -- '---\nname: fixture\nversion: "1.0"\ndescription: Gate-reading fixture.\ninitial_state: only\nstates:\n'
        printf -- '  only:\n    gates:\n'
        printf -- '      target_gate:\n        type: command\n        command: "the command under test"\n'
        i=0
        while [ "$i" -lt "$after" ]; do
            printf -- '      filler_%s:\n        type: command\n        command: "%s"\n' \
                "$i" "filler gate $i padded so the rows after the match are large enough to fill a pipe buffer while the reader has already gone away"
            i=$((i + 1))
        done
        printf -- '    transitions:\n      - target: only\n---\n\n## only\nStub.\n'
    } > "$dir/fixture.md"
}

# ---------------------------------------------------------------------------
# Case 1 — THE MECHANISM, not the symptom: does the reader consume everything
# the writer sends?
#
# Asserting the symptom instead would be a no-op on most machines. Whether an
# early-exiting reader produces a fatal 141 depends on the awk implementation:
# measured, it reproduces under the floor image's BusyBox awk and does NOT under
# mawk, which is what this host and the Linux runners use. A test that only
# watched for 141 would therefore pass everywhere that matters while the defect
# sat in place — the exact failure this file exists to pin.
#
# So the writer is replaced with one under this test's control, which records
# that it finished. If the reader stops early the writer is killed by the broken
# pipe and the sentinel never appears, whatever awk or shell is in use.
# ---------------------------------------------------------------------------
SENTINEL=$(mktemp -d); TMPS+=("$SENTINEL")
SENTINEL_FILE="$SENTINEL/writer-finished"

# Stands in for the real row producer. koto_gate_command calls this by name.
koto_gate_rows() {
    local i=0 pad
    pad="padding so the rows after the match are far larger than any pipe buffer"
    printf 'COMMAND\ttarget_gate\t"the command under test"\n'
    while [ "$i" -lt 20000 ]; do
        printf 'COMMAND\tfiller_%s\t%s\n' "$i" "$pad"
        i=$((i + 1))
    done
    : > "$SENTINEL_FILE"
}

got=$(koto_gate_command ignored-path target_gate)

if [[ ! -f "$SENTINEL_FILE" ]]; then
    fail "the reader stopped before the writer finished: the writer was killed by the closed pipe, which is the defect"
elif [[ "$got" != '"the command under test"' ]]; then
    fail "wrong command returned: $got"
else
    pass "the reader consumes the whole stream, so the writer is never killed mid-write"
fi

unset -f koto_gate_rows
# shellcheck source=koto-gates.sh
. "$SCRIPT_DIR/koto-gates.sh"

# Case 2 — the same read with nothing below it, which is the arrangement that
# always worked and is why the defect stayed hidden.
D2=$(mktemp -d); TMPS+=("$D2")
build_template "$D2" 0
got2=$(
    set -euo pipefail
    koto_gate_command "$D2/fixture.md" target_gate
)
if [[ "$?" -eq 0 && "$got2" == '"the command under test"' ]]; then
    pass "a gate with nothing below it still reads correctly"
else
    fail "the no-trailing-gates arrangement broke: $got2"
fi

# Case 3 — a gate that is not there returns empty and does not fail, because the
# callers distinguish "absent" from "unreadable" themselves.
D3=$(mktemp -d); TMPS+=("$D3")
build_template "$D3" 50
got3=$(
    set -uo pipefail
    koto_gate_command "$D3/fixture.md" no_such_gate
)
if [[ -z "$got3" ]]; then
    pass "an absent gate reads as empty rather than as an error"
else
    fail "an absent gate returned: $got3"
fi

# Case 4 — the shipped templates still read, so the fixture has not drifted from
# the real layout the library is written against.
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
real="$REPO_ROOT/skills/work-on/koto-templates/work-on.md"
if [[ -f "$real" ]]; then
    got4=$(
        set -euo pipefail
        koto_gate_command "$real" ci_passing
    )
    if [[ "$got4" == *"gh pr checks"* ]]; then
        pass "the shipped work-on template's ci_passing gate reads"
    else
        fail "reading ci_passing from the shipped template returned: $got4"
    fi
else
    fail "shipped template not found at $real"
fi

echo
echo "koto-gates_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
