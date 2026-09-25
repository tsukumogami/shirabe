#!/usr/bin/env bash
# plan-mode_test.sh -- plan-mode.sh maps a PLAN's execution_mode to an exit
# code, and refuses everything that isn't one of the three modes.
#
# Usage: bash scripts/plan-mode_test.sh
# Exit codes: 0 all pass; 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/plan-mode.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/plan-mode-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
check() { # check <label> <want-rc> <want-stdout> <file>
    local out rc
    out=$(bash "$SCRIPT" "$4" 2>/dev/null)
    rc=$?
    if [ "$rc" = "$2" ] && [ "$out" = "$3" ]; then
        PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"
    else
        FAIL=$((FAIL + 1)); printf 'FAIL %s\n     want rc=%s out=[%s], got rc=%s out=[%s]\n' "$1" "$2" "$3" "$rc" "$out"
    fi
}
plan() { # plan <name> <frontmatter-line>...
    local f="$T/$1"
    shift
    { printf -- '---\n'; printf '%s\n' "$@"; printf -- '---\n\n# PLAN\n'; } >"$f"
    printf '%s' "$f"
}

check "single-pr exits 0" 0 single-pr "$(plan a.md 'status: Active' 'execution_mode: single-pr')"
check "coordinated exits 10" 10 coordinated "$(plan b.md 'execution_mode: coordinated')"
check "multi-pr exits 20" 20 multi-pr "$(plan c.md 'execution_mode: multi-pr' 'status: Draft')"
check "a quoted value" 0 single-pr "$(plan d.md 'execution_mode: "single-pr"')"
check "a single-quoted value with a comment" 20 multi-pr "$(plan e.md "execution_mode: 'multi-pr'  # split")"
check "trailing whitespace" 10 coordinated "$(plan f.md 'execution_mode: coordinated   ')"
check "an unknown value exits 4" 4 "" "$(plan g.md 'execution_mode: parallel')"
check "an empty value exits 4" 4 "" "$(plan h.md 'execution_mode:')"
check "no execution_mode key exits 4" 4 "" "$(plan i.md 'status: Active')"
check "a value with prose appended exits 4" 4 "" "$(plan j.md 'execution_mode: single-pr and more')"
check "a missing file exits 4" 4 "" "$T/nope.md"

printf '# PLAN\n\nexecution_mode: single-pr\n' >"$T/body.md"
check "a key in the body, not the frontmatter, exits 4" 4 "" "$T/body.md"

printf -- '---\nstatus: Active\n---\nexecution_mode: single-pr\n' >"$T/after.md"
check "a key after the frontmatter closes exits 4" 4 "" "$T/after.md"

printf -- '---\nexecution_mode: single-pr\x1b[2J\n---\n' >"$T/ctl.md"
check "a value with a control character exits 4" 4 "" "$T/ctl.md"

# Usage errors.
out=$(bash "$SCRIPT" 2>/dev/null); rc=$?
if [ "$rc" -eq 64 ] && [ -z "$out" ]; then PASS=$((PASS + 1)); echo "ok   no argument is a usage error"; else FAIL=$((FAIL + 1)); echo "FAIL no argument: rc=$rc"; fi
out=$(bash "$SCRIPT" a b 2>/dev/null); rc=$?
if [ "$rc" -eq 64 ]; then PASS=$((PASS + 1)); echo "ok   two arguments are a usage error"; else FAIL=$((FAIL + 1)); echo "FAIL two arguments: rc=$rc"; fi

# A path starting with `-` is read as a path, never as an option.
mkdir -p "$T/d"
plan d/-dash.md 'execution_mode: single-pr' >/dev/null
out=$(cd "$T/d" && bash "$SCRIPT" -dash.md 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = single-pr ]; then PASS=$((PASS + 1)); echo "ok   a leading-dash path is a path"; else FAIL=$((FAIL + 1)); echo "FAIL leading-dash path: rc=$rc out=$out"; fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
