#!/usr/bin/env bash
# run-record-lookup_test.sh -- from a PR's repository and number to the
# session that ran its plan (scripts/run-record-lookup.sh)
#
# The skeleton case is the whole path: a single-pr run's root is opened in
# workspace A (its run_id and trail/self as execute-open.sh leaves them), its
# home PR is adopted and recorded through
# skills/execute/scripts/adopt-or-create-pr.sh against the stand-in koto
# (scripts/testdata/record-koto/koto) and a stub gh, and the lookup runs from a
# different directory B. Then:
#
#   the answer      exit 0, JSON naming execute-<topic>, workspace A, the
#                   run_id, complete: true and exactly the one PR with its state
#   unconfirmed     an index entry naming a root whose trail/pr doesn't hold
#                   the PR: not returned, exit 3
#   exit codes      3 no index entry, 2 a failed store read, 64 for an owner
#                   without a repository, PR number 0 and a non-numeric one,
#                   each with its message on stderr
#   read-only       the lookup's calls are reads only: no write, no import,
#                   no migration marker
#   both modes      option absent: the lookup reads from the addressed
#                   directories and no call carries --workspace; option
#                   present: the stub refuses any write given it, the
#                   skeleton still passes, and the lookup's reads carry it
#   no GitHub       with a gh that fails every call, the same JSON and exit
#
# The shared address is the real fixed directory, under an owner unique to
# this run, removed at exit.
#
# Usage: run-record-lookup_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
ROOT=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
LOOKUP="$SCRIPT_DIR/run-record-lookup.sh"
TRAIL="$SCRIPT_DIR/run-trail.sh"
ADOPT="$ROOT/skills/execute/scripts/adopt-or-create-pr.sh"
STUB_DIR="$SCRIPT_DIR/testdata/record-koto"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/run-record-lookup-test.XXXXXX") || exit 1
OWNER="rrtest-$$-$(od -An -tx1 -N4 /dev/urandom | tr -d ' \n')"
trap 'rm -rf "$WORK" "/tmp/shirabe-run-record/$OWNER"' EXIT
export RECORD_KOTO_STORE="$WORK/store"
TOPIC=skel
S="execute-$TOPIC"
RID=0123456789abcdef0123456789abcdef

# A gh that answers owned-pr.sh's three reads with one owned PR, number 7, on
# impl/skel; and one that fails every call.
GH_OK="$WORK/gh-ok"
GH_BAD="$WORK/gh-bad"
mkdir -p "$GH_OK" "$GH_BAD"
cat > "$GH_OK/gh" <<STUB
#!/usr/bin/env bash
case "\$1 \${2:-}" in
    "api user") echo '{"login":"octo"}' ;;
    "api repos/"*) echo '{"default_branch":"main"}' ;;
    "pr list") echo '[{"url":"https://github.com/$OWNER/r/pull/7","state":"OPEN","isCrossRepository":false,"author":{"login":"octo"},"baseRefName":"main","headRefName":"impl/$TOPIC","body":"A draft."}]' ;;
    *) echo "gh stub: unexpected [\$*]" >&2; exit 1 ;;
esac
STUB
printf '#!/usr/bin/env bash\necho "gh: no network" >&2\nexit 1\n' > "$GH_BAD/gh"
chmod +x "$GH_OK/gh" "$GH_BAD/gh"

TAB=$(printf '\t')
calls_since() { tail -n "+$(($1 + 1))" "$RECORD_KOTO_STORE/calls.log"; }
log_len() { wc -l < "$RECORD_KOTO_STORE/calls.log" | tr -d ' '; }

# skeleton <mode>: a fresh store and workspaces A and B; the run's root opened
# in A as execute-open.sh leaves it, then its home PR adopted and recorded
# through adopt-or-create-pr.sh. Sets A, B and ADOPT_RC.
skeleton() {
    rm -rf "$RECORD_KOTO_STORE" "$WORK/a" "$WORK/b" "/tmp/shirabe-run-record/$OWNER"
    mkdir -p "$RECORD_KOTO_STORE" "$WORK/a" "$WORK/b"
    A=$(cd "$WORK/a" && pwd -P)
    B=$(cd "$WORK/b" && pwd -P)
    export RECORD_KOTO_WORKSPACE_OPTION=$1
    (
        cd "$A" || exit 1
        export PATH="$STUB_DIR:$GH_OK:$PATH"
        koto init "$S" --template execute.md >/dev/null || exit 1
        printf '%s' "$RID" | koto context add "$S" run_id || exit 1
        bash "$TRAIL" self --session "$S" </dev/null || exit 1
        bash "$ADOPT" --session "$S" --repo "$OWNER/r" --head "impl/$TOPIC" </dev/null >"$WORK/adopt.out" 2>"$WORK/adopt.err"
    )
    ADOPT_RC=$?
}

lookup() { # lookup <gh dir> <args>: from B
    local gh=$1
    shift
    OUT=$(cd "$B" && PATH="$STUB_DIR:$gh:$PATH" bash "$LOOKUP" "$@" </dev/null 2>"$WORK/stderr")
    RC=$?
    ERR=$(cat "$WORK/stderr")
}

expect_answer() { # expect_answer <label>
    local want
    want=$(jq -nc --arg ws "$A" --arg s "$S" --arg r "$RID" --arg repo "$OWNER/r" \
        '{record_root: {workspace: $ws, session: $s}, run_id: $r, complete: true, unique: true,
          missing: [], prs: [{repo: $repo, number: 7, state: "open"}], others: [], steps: []}')
    if [ "$RC" -eq 0 ] && [ "$(jq -c . <<<"$OUT")" = "$want" ]; then
        pass "$1"
    else
        fail "$1: exit $RC, out [$OUT], stderr [$ERR]"
    fi
}

# --- the skeleton, option absent ------------------------------------------------------

skeleton absent
[ "$ADOPT_RC" -eq 0 ] && [ "$(cat "$WORK/adopt.out")" = "https://github.com/$OWNER/r/pull/7" ] \
    && pass "the run records its home PR in workspace A through adopt-or-create-pr.sh" \
    || fail "adopt: exit $ADOPT_RC [$(cat "$WORK/adopt.err")]"

MARK=$(log_len)
lookup "$GH_OK" "$OWNER/r" 7
expect_answer "from directory B: execute-$TOPIC, workspace A, the run_id, complete, exactly that one PR"
GOOD_OUT=$OUT
GOOD_RC=$RC

LOOKUP_CALLS=$(calls_since "$MARK")
if [ -n "$LOOKUP_CALLS" ] \
    && ! grep -qE "${TAB}(init|next|cancel|context add|context remove|session import|session cleanup|session prune|decisions) " <<<"$LOOKUP_CALLS" \
    && [ -z "$(find "$RECORD_KOTO_STORE" -name migrated)" ]; then
    pass "the lookup made reads only: no write, no import, no migration marker"
else
    fail "lookup calls: [$LOOKUP_CALLS]"
fi
if ! grep -q -- '--workspace' "$RECORD_KOTO_STORE/calls.log"; then
    pass "option absent: no call carries --workspace, the run's or the lookup's"
else
    fail "option absent, --workspace seen: [$(grep -- '--workspace' "$RECORD_KOTO_STORE/calls.log")]"
fi
if grep "${TAB}context " <<<"$LOOKUP_CALLS" | grep -v -- '--help' | cut -f1 | grep -qvxF -e "$A" -e "$(cd "/tmp/shirabe-run-record/$OWNER" && pwd -P)"; then
    fail "option absent: a read ran outside the addressed directories: [$LOOKUP_CALLS]"
else
    pass "option absent: every read ran from an addressed directory, the shared one or A"
fi

lookup "$GH_BAD" "$OWNER/r" 7
if [ "$RC" -eq "$GOOD_RC" ] && [ "$OUT" = "$GOOD_OUT" ]; then
    pass "with a gh that fails every call: the same JSON and exit code"
else
    fail "failing gh: exit $RC, out [$OUT]"
fi

lookup "$GH_OK" "$(printf '%s' "$OWNER" | tr '[:lower:]' '[:upper:]')/R" 7
expect_answer "the repository is matched without regard to case"

# --- an entry its root doesn't confirm ---------------------------------------------------

# The root's index entry for PR 8, which its own trail/pr list doesn't hold.
(cd "$A" && PATH="$STUB_DIR:$PATH" bash "$TRAIL" index --repo "$OWNER/r" --number 8 --session "$S" \
    --mode single-pr --topic "$TOPIC" </dev/null)
lookup "$GH_OK" "$OWNER/r" 8
if [ "$RC" -eq 3 ] && [ -z "$OUT" ] && grep -q 'lists the PR' <<<"$ERR"; then
    pass "an index entry whose root doesn't list the PR: not returned, exit 3"
else
    fail "unconfirmed: exit $RC, out [$OUT], stderr [$ERR]"
fi

# --- exit codes -----------------------------------------------------------------------------

lookup "$GH_OK" "$OWNER/r" 99
[ "$RC" -eq 3 ] && [ -z "$OUT" ] && grep -q 'no index entry' <<<"$ERR" \
    && pass "a PR with no index entry: exit 3, said on stderr" \
    || fail "no entry: exit $RC, stderr [$ERR]"

export RECORD_KOTO_FAIL_READS=1
lookup "$GH_OK" "$OWNER/r" 7
unset RECORD_KOTO_FAIL_READS
[ "$RC" -eq 2 ] && [ -z "$OUT" ] && grep -q 'could not read' <<<"$ERR" \
    && pass "a failed store read: exit 2, said on stderr" \
    || fail "read failure: exit $RC, stderr [$ERR]"

check_usage() { # check_usage <label> <stderr pattern> <args...>
    local label=$1 pattern=$2
    shift 2
    MARK=$(log_len)
    lookup "$GH_OK" "$@"
    if [ "$RC" -eq 64 ] && [ -z "$OUT" ] && grep -q -- "$pattern" <<<"$ERR" && [ -z "$(calls_since "$MARK")" ]; then
        pass "$label: exit 64, said on stderr, no koto call"
    else
        fail "$label: exit $RC, stderr [$ERR]"
    fi
}
check_usage "an owner without a repository" "owner without a repository" "$OWNER" 7
check_usage "an owner with an empty repository" "owner without a repository" "$OWNER/" 7
check_usage "PR number 0" "not a positive integer" "$OWNER/r" 0
check_usage "a non-numeric PR number" "not a positive integer" "$OWNER/r" seven
check_usage "an owner outside GitHub's grammar" "not a GitHub owner name" "-x/r" 7
check_usage "a missing PR number" "expected" "$OWNER/r"

# --- the skeleton, option present -------------------------------------------------------------

skeleton present
[ "$ADOPT_RC" -eq 0 ] && pass "option present: the run still records its home PR (no write carries --workspace)" \
    || fail "option present, adopt: exit $ADOPT_RC [$(cat "$WORK/adopt.err")]"
if ! grep -E "${TAB}(init|context add|context remove) " "$RECORD_KOTO_STORE/calls.log" | grep -q -- '--workspace'; then
    pass "option present: none of the run's writes carries --workspace"
else
    fail "option present: a write carried --workspace"
fi

MARK=$(log_len)
lookup "$GH_OK" "$OWNER/r" 7
expect_answer "option present: from directory B, the same answer"
READS=$(calls_since "$MARK" | grep -E "${TAB}context (get|list) " | grep -v -- '--help')
if [ -n "$READS" ] && ! grep -qv -- '--workspace=' <<<"$READS" \
    && grep -qF -- "--workspace=$A " <<<"$READS" \
    && [ "$(cut -f1 <<<"$READS" | LC_ALL=C sort -u)" = "$B" ]; then
    pass "option present: the lookup's reads carry --workspace and run from B itself"
else
    fail "option present reads: [$READS]"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
