#!/usr/bin/env bash
set -euo pipefail

# Tests for check-status-words.sh.
#
# The first case runs the check on this repository as it stands. The planted
# cases copy skills/ and crates/ to a scratch root once, add one line to a
# file, run the check against the copy through STATUS_WORDS_ROOT, and put the
# file back. The small cases build a throwaway root holding only the files
# they need. Each asserts the exit code and, for a failure, that the output
# names the file and line.
#
# Usage:
#   bash scripts/check-status-words_test.sh
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-status-words.sh"

PASS_COUNT=0
FAIL_COUNT=0
TMP_ROOTS=""

cleanup() {
    for d in $TMP_ROOTS; do rm -rf "$d"; done
}
trap cleanup EXIT

fail() {
    echo "FAIL: $1 - $2" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo "PASS: $1" >&2
    PASS_COUNT=$((PASS_COUNT + 1))
}

# new_root: a fresh empty directory, removed on exit.
new_root() {
    # macOS mktemp ignores TMPDIR without an explicit template.
    d=$(mktemp -d "${TMPDIR:-/tmp}/check-status-words.XXXXXX")
    TMP_ROOTS="$TMP_ROOTS $d"
    mkdir -p "$d/scripts" "$d/skills" "$d/crates"
    printf '# allowlist\n' > "$d/scripts/check-status-words.allow"
    printf '%s\n' "$d"
}

# run_check <root>: runs the check against root; sets OUT and RC.
run_check() {
    set +e
    OUT=$(STATUS_WORDS_ROOT="$1" bash "$CHECK" 2>&1)
    RC=$?
    set -e
}

# expect_pass <name> <root>
expect_pass() {
    run_check "$2"
    if [ "$RC" -eq 0 ]; then pass "$1"; else fail "$1" "expected exit 0, got $RC: $OUT"; fi
}

# expect_fail <name> <root> <text the output must contain>
expect_fail() {
    run_check "$2"
    if [ "$RC" -ne 1 ]; then
        fail "$1" "expected exit 1, got $RC: $OUT"
    else
        case "$OUT" in
            *"$3"*) pass "$1" ;;
            *) fail "$1" "output does not name '$3': $OUT" ;;
        esac
    fi
}

# add <root> <repo-relative file> <line>: appends the line, creating the file.
add() {
    mkdir -p "$(dirname "$1/$2")"
    printf '%s\n' "$3" >> "$1/$2"
}

# record <root> <file> <match> <reason>
record() {
    printf '%s\t%s\t%s\n' "$2" "$3" "$4" >> "$1/scripts/check-status-words.allow"
}

# ── The repository as it stands ──────────────────────────────────────────────

expect_pass "this repository passes" "$REPO"

# ── Planted lines in a copy of this repository ──────────────────────────────

COPY=$(new_root)
cp -R "$REPO/skills/." "$COPY/skills/"
cp -R "$REPO/crates/." "$COPY/crates/"
rm -rf "$COPY/crates/target"
cp "$REPO/scripts/check-status-words.allow" "$COPY/scripts/"
expect_pass "the copy passes before anything is planted" "$COPY"

# plant <name> <file> <line> <pass|fail>: appends the line to a copy of the
# file, runs the check, and restores the file.
plant() {
    f="$COPY/$2"
    # The original is kept outside the scanned tree, so the check never
    # reads it.
    cp "$f" "$COPY/scripts/planted.orig"
    printf '%s\n' "$3" >> "$f"
    n=$(wc -l < "$f" | tr -d ' ')
    if [ "$4" = pass ]; then
        expect_pass "$1" "$COPY"
    else
        expect_fail "$1" "$COPY" "$2:$n:"
    fi
    mv "$COPY/scripts/planted.orig" "$f"
}

plant "a shell test against Done in a coordinate script fails" \
    skills/coordinate/scripts/pick-facts.sh '[ "$status" = "Done" ]' fail
plant "a shell test against Done in another coordinate script fails" \
    skills/coordinate/scripts/progress-view.sh 'if [ "$status" = "Done" ]; then :; fi' fail
plant "eq_ignore_ascii_case(\"Verified\") in populate.rs fails" \
    crates/shirabe/src/populate.rs '    let v = s.eq_ignore_ascii_case("Verified");' fail
plant "a PLAN's status: Done in a plan script passes" \
    skills/plan/scripts/build-dependency-graph.sh '[ "$(sed -n "s/^status: //p" "$PLAN")" = "Done" ] && echo done' pass
plant "a line naming the PLAN's status elsewhere passes" \
    skills/work-on/scripts/run-cascade.sh '[[ "$plan_status" == "Done" ]] # the PLAN frontmatter status' pass

# ── Small fixtures ───────────────────────────────────────────────────────────

R=$(new_root)
add "$R" skills/coordinate/scripts/state-common.sh 'lib_status_prop() {'
add "$R" skills/coordinate/scripts/state-common.sh '    [ "$2" = "Done" ] && echo true'
add "$R" skills/coordinate/scripts/state-common.sh '}'
add "$R" skills/coordinate/scripts/state-common.sh 'lib_status_family() { case "$1" in roadmap/v4) echo Verified ;; esac; }'
expect_pass "a comparison inside lib_status functions passes" "$R"
add "$R" skills/coordinate/scripts/state-common.sh 'lib_other() {'
add "$R" skills/coordinate/scripts/state-common.sh '    [ "$2" = "Done" ] && echo true'
add "$R" skills/coordinate/scripts/state-common.sh '}'
expect_fail "a comparison in state-common.sh outside lib_status fails" "$R" \
    "skills/coordinate/scripts/state-common.sh:6:"

R=$(new_root)
add "$R" crates/shirabe-validate/src/statuses.rs 'if s == "Done" { return true; }'
add "$R" skills/coordinate/scripts/lib-status_test.sh '[ "$(prop roadmap/v3 Shipped satisfies)" = "true" ]'
add "$R" skills/coordinate/scripts/x_test.sh 'echo "== a failure reopens the Done milestone =="'
add "$R" skills/coordinate/scripts/x.sh 'if [ "$V4" = 1 ]; then S=; else S=Done; fi'
add "$R" crates/shirabe/src/x.rs 'Err(case) => fails.push(FailClosed {'
add "$R" skills/coordinate/scripts/x.sh 'STATUS=Done'
expect_pass "readers, their tests, headings and non-comparisons pass" "$R"

R=$(new_root)
add "$R" skills/coordinate/scripts/x.sh 'case "$status" in Done|Shipped) echo y ;; esac'
expect_fail "a case on a status word fails" "$R" "skills/coordinate/scripts/x.sh:1:"
record "$R" skills/coordinate/scripts/x.sh 'case "$status" in Done|Shipped)' "a test record"
expect_pass "a record covers the line" "$R"

R=$(new_root)
add "$R" skills/coordinate/scripts/x.sh 'echo fine'
record "$R" skills/coordinate/scripts/x.sh 'in Done)' "covers nothing"
expect_fail "a stale record fails" "$R" "covers no flagged line (stale)"

R=$(new_root)
add "$R" skills/coordinate/scripts/x.sh '[ "$s" != "Completed" ] || exit 0'
record "$R" skills/coordinate/scripts/x.sh '"$s" != "Completed"' ""
expect_fail "a record with no reason fails" "$R" "has no reason"

R=$(new_root)
add "$R" skills/coordinate/scripts/x.sh '[ "$s" != "Completed" ] || exit 0'
record "$R" docs/x.md '"$s" != "Completed"' "outside the scan"
expect_fail "a record outside skills/ and crates/ fails" "$R" "names a file outside skills/ and crates/"

echo "" >&2
echo "$PASS_COUNT passed, $FAIL_COUNT failed" >&2
[ "$FAIL_COUNT" -eq 0 ]
