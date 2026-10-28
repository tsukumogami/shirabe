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
#   with a trailing --session, no value     the same
#   with a koto (KOTO_BIN) whose context    the same, and no "Context stored"
#     add fails                             banner
#   in all                                  exit 0, no file created in the
#                                           working directory, and no
#                                           context_file field
#
# It also checks the script's header and source carry no context_file, and
# that the issue's repository comes from --issue-repo alone: a value reads the
# issue there, an empty one reads it here, and a missing or malformed one is a
# failed summary with no gh call.
#
# Usage: extract-context_test.sh
#
# Exit codes:
#   0 -- all cases pass (or jq is absent and the run skipped)
#   1 -- one or more cases failed
#
# Needs only bash and jq; koto and gh are absent or stubbed, so every case runs
# on the bash 3.2 floor.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

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

WORKDIR=$(mktemp -d) || { echo "FAIL: could not create a temporary directory" >&2; exit 1; }
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
ktg_on_exit cleanup

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

run_script 123 --session some-session --issue-repo ""
check_failed_json "with --session and no koto on PATH"

# A trailing --session with no value: the flag is consumed alone, set -e does
# not end the script on a short `shift 2`, and the missing session is reported.
run_script 123 --session
check_failed_json "with a trailing --session and no value"

# A koto that refuses the add, reached through KOTO_BIN, with a gh stub that
# answers auth and returns an issue body (no design doc in the empty directory,
# so the run takes the issue-body path to the store). The failed add is
# reported in the JSON with exit 0, and the "stored" banner never prints.
STUBS="$WORKDIR/stubs"
mkdir -p "$STUBS"
cat >"$STUBS/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "auth status") exit 0 ;;
    "issue view") echo "the issue body" ;;
    *) exit 1 ;;
esac
EOF
cat >"$STUBS/koto" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo "koto stub: context add refused" >&2
exit 1
EOF
chmod +x "$STUBS/gh" "$STUBS/koto"
RC=0
OUT=$(cd "$RUN" && KOTO_BIN="$STUBS/koto" PATH="$BIN:$STUBS:/usr/bin:/bin" "$BASH" "$SCRIPT" 123 --session some-session --issue-repo "" 2>/dev/null) || RC=$?
JSON=$(printf '%s\n' "$OUT" | sed -n '/^{/,$p')
OUT="$JSON"
check_failed_json "a koto context add that fails"
if grep -q 'Context stored' <<<"$(cd "$RUN" && KOTO_BIN="$STUBS/koto" PATH="$BIN:$STUBS:/usr/bin:/bin" "$BASH" "$SCRIPT" 123 --session some-session --issue-repo "" 2>/dev/null)"; then
    fail "a koto context add that fails: the 'Context stored' banner printed anyway"
else
    pass "a koto context add that fails: no 'Context stored' banner"
fi

# An issue in another repository, named by --issue-repo. A koto stub logs
# every call and stores `context add` into a file; a gh stub logs every call.
# The working directory holds a design doc that names #123, so a run that
# searched this repository's docs would find it. No session has a state log:
# the repository comes from the flag and nowhere else.
XREPO="$WORKDIR/xrepo"
mkdir -p "$XREPO/docs"
printf '# DESIGN: local\n\n| [#123: a local issue](x) | None | simple |\n' > "$XREPO/docs/DESIGN-local.md"
cat >"$STUBS/gh-log" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
    "auth status") exit 0 ;;
    "issue view") echo "the cross-repo issue body" ;;
    *) exit 1 ;;
esac
EOF
cat >"$STUBS/koto-store" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$KOTO_LOG"
case "$1 $2" in
    "context add") cat > "$KOTO_STORED" ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$STUBS/gh-log" "$STUBS/koto-store"
mkdir -p "$WORKDIR/ghbin"
ln -sf "$STUBS/gh-log" "$WORKDIR/ghbin/gh"

# run_xrepo <arg>...: run the script on issue 123 with the given arguments
# after it; sets OUT (the JSON summary), RC, GH_CALLS, KOTO_CALLS, STORED.
run_xrepo() {
    local log="$WORKDIR/gh.log" klog="$WORKDIR/koto.log" stored="$WORKDIR/stored"
    rm -f "$log" "$klog" "$stored"
    RC=0
    OUT=$(cd "$XREPO" && GH_LOG="$log" KOTO_LOG="$klog" KOTO_STORED="$stored" \
        KOTO_BIN="$STUBS/koto-store" PATH="$BIN:$WORKDIR/ghbin:/usr/bin:/bin" \
        "$BASH" "$SCRIPT" 123 "$@" 2>/dev/null) || RC=$?
    OUT=$(printf '%s\n' "$OUT" | sed -n '/^{/,$p')
    GH_CALLS=$(cat "$log" 2>/dev/null)
    KOTO_CALLS=$(cat "$klog" 2>/dev/null)
    STORED=$(cat "$stored" 2>/dev/null)
}

run_xrepo --session xrepo --issue-repo acme/tracker
expect "cross-repo: exits 0" "0" "$RC"
expect "cross-repo: status is degraded" "degraded" "$(printf '%s' "$OUT" | jq -r '.status' 2>/dev/null)"
if grep -qx 'issue view 123 --repo acme/tracker --json body --jq .body' <<<"$GH_CALLS"; then
    pass "cross-repo: the issue is read from its own repository"
else
    fail "cross-repo: gh calls were [$GH_CALLS]"
fi
expect "cross-repo: the issue body is stored as context.md" "the cross-repo issue body" "$STORED"
if printf '%s' "$OUT" | jq -e '[.warnings[] | select(test("acme/tracker") and test("design doc search skipped"))] | length == 1' >/dev/null 2>&1; then
    pass "cross-repo: the skipped design doc search is a warning naming the repository"
else
    fail "cross-repo: no warning names the skipped search: $OUT"
fi
if [ "$KOTO_CALLS" = "context add xrepo context.md" ]; then
    pass "cross-repo: koto is asked only to store the context, never for the session's log"
else
    fail "cross-repo: koto calls were [$KOTO_CALLS]"
fi

# The same-repository run in the same directory, with the empty value the
# template passes, finds the local design doc and never passes --repo.
run_xrepo --session samerepo --issue-repo ""
expect "same-repo: exits 0" "0" "$RC"
if ! grep -q -- '--repo' <<<"$GH_CALLS"; then
    pass "same-repo: no gh call names a repository"
else
    fail "same-repo: gh calls were [$GH_CALLS]"
fi
if grep -q 'Source\*\*: docs/DESIGN-local.md' <<<"$STORED"; then
    pass "same-repo: the local design doc is still searched and used"
else
    fail "same-repo: the stored context does not come from the local design doc: $STORED"
fi

# Without a usable --issue-repo the script never guesses this repository: it
# reports failed, reads no issue and stores nothing.
check_no_guess() { # check_no_guess <label>
    local label="$1"
    expect "$label: exits 0" "0" "$RC"
    expect "$label: status is failed" "failed" "$(printf '%s' "$OUT" | jq -r '.status' 2>/dev/null)"
    expect "$label: no gh call" "" "$GH_CALLS"
    expect "$label: nothing stored" "" "$STORED"
}
run_xrepo --session xrepo
check_no_guess "no --issue-repo"
if printf '%s' "$OUT" | jq -e '.error | test("--issue-repo")' >/dev/null 2>&1; then
    pass "no --issue-repo: the error names the flag"
else
    fail "no --issue-repo: the error does not name the flag: $OUT"
fi
run_xrepo --session xrepo --issue-repo
check_no_guess "a trailing --issue-repo with no value"
run_xrepo --session xrepo --issue-repo acme
check_no_guess "an --issue-repo that is not owner/repo"
run_xrepo --session xrepo --issue-repo 'acme/tr;cker'
check_no_guess "an --issue-repo with a character outside owner/repo"
run_xrepo --session xrepo --issue-repo 'acme/tracker
evil/x'
check_no_guess "an --issue-repo with a newline"

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
