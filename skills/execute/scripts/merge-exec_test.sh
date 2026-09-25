#!/usr/bin/env bash
# merge-exec_test.sh — the one merge call site, and everything that refuses it
# Part of the execute skill
#
# merge-exec.sh recomputes a verdict with merge-verdict.sh and makes the single
# fixed-text `gh pr merge` call only when that fresh verdict is mergeable at
# the expected head. This harness drives it through a test-local `gh` stub on
# PATH that serves per-case JSON fixtures and appends every invocation to a
# call log. Cases are table-driven, one row per outcome.
#
# It asserts:
#
#   argument count and the closed patterns, with no gh call    (usage cases)
#   the verdict script is found by directory, never PATH        (location case)
#   every refusal prints merge-refused:<verdict>, no merge      (refusal cases)
#   the merge call, byte for byte, per method                   (merge cases)
#   a failing merge call is not retried                         (row 18)
#   merge-called is never read as merged                        (end to end)
#   no merge call carries --admin, --auto, or --delete-branch
#   `gh pr merge` appears on exactly one non-comment line in the repository
#
# Usage: merge-exec_test.sh
#
# Exit codes:
#   0 — all cases pass
#   1 — one or more cases failed, or jq is missing

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
EXEC="$SCRIPT_DIR/merge-exec.sh"
VERDICT="$SCRIPT_DIR/merge-verdict.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
[ -f "$EXEC" ] || { echo "FAIL: $EXEC not found" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"
mkdir -p "$BIN" "$WORK/cases"
OUTPUT_LOG="$WORK/outputs.log"
: > "$OUTPUT_LOG"

HEAD=1111111111111111111111111111111111111111
OTHER=2222222222222222222222222222222222222222

# The same stub merge-verdict_test.sh uses: routes each call to a fixture key,
# logs it, and serves $GH_FIX/<key>.out / .err / .rc, with <key>.<ext>.<N>
# winning for the Nth call.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
fix="${GH_FIX:?GH_FIX is not set}"
printf '%s\n' "$*" >> "$fix/calls.log"
key=unknown
case "$1 ${2:-}" in
    "pr view")
        case " $* " in
            *" --json state "*) key=confirm ;;
            *) key=view ;;
        esac
        ;;
    "pr checks") key=checks ;;
    "pr merge") key=merge ;;
    "api "*)
        case "$2" in
            repos/*/*/rules/branches/*) key=rules ;;
            repos/*/*/pulls/*/files) key=files ;;
            repos/*/*/commits/*) key=commit ;;
            repos/*/*/branches/*) key=branch ;;
            repos/*/*) key=repo ;;
        esac
        ;;
esac
n=0
[ -f "$fix/$key.count" ] && n=$(cat "$fix/$key.count")
n=$((n + 1))
echo "$n" > "$fix/$key.count"
pick() {
    if [ -f "$fix/$key.$1.$n" ]; then echo "$fix/$key.$1.$n"; else echo "$fix/$key.$1"; fi
}
out=$(pick out); err=$(pick err); rcf=$(pick rc)
if [ ! -f "$out" ] && [ ! -f "$rcf" ]; then
    echo "gh stub: no fixture for [$key] ($*)" >&2
    exit 1
fi
[ -f "$out" ] && cat "$out"
[ -f "$err" ] && cat "$err" >&2
rc=0
[ -f "$rcf" ] && rc=$(cat "$rcf")
exit "$rc"
STUB
chmod +x "$BIN/gh"

# A merge-verdict.sh planted on PATH. merge-exec.sh must never run it; if it
# does, it leaves a marker and claims the PR is mergeable.
PLANTED="$WORK/planted"
mkdir -p "$PLANTED"
cat > "$PLANTED/merge-verdict.sh" <<EOF
#!/usr/bin/env bash
touch "$WORK/planted-ran"
echo "mergeable:squash:$HEAD"
EOF
chmod +x "$PLANTED/merge-verdict.sh"

# new_case <name> — a PR mergeable with squash at $HEAD (see merge-verdict_test.sh).
new_case() {
    CASE="$WORK/cases/$1"
    rm -rf "$CASE"
    mkdir -p "$CASE"
    : > "$CASE/calls.log"
    jq -n --arg head "$HEAD" '{
        state: "OPEN", isDraft: false, mergeStateStatus: "CLEAN",
        reviewDecision: "", headRefOid: $head, baseRefName: "main",
        changedFiles: 1,
        commits: [{oid: $head, committedDate: ((now - 600) | todate)}]
    }' > "$CASE/view.out"
    echo '[{"name":"build","bucket":"pass"}]' > "$CASE/checks.out"
    echo '{"name":"main","protected":false}' > "$CASE/branch.out"
    echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"build"}]}}]' > "$CASE/rules.out"
    echo '[{"filename":"src/main.go"}]' > "$CASE/files.out"
    echo '{"allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":true}' > "$CASE/repo.out"
    echo '{"state":"MERGED"}' > "$CASE/confirm.out"
    echo 'Merged pull request #7' > "$CASE/merge.out"
}

view() {
    jq "$1" "$CASE/view.out" > "$CASE/view.tmp" && mv "$CASE/view.tmp" "$CASE/view.out"
}

fixture() {
    printf '%s\n' "$2" > "$CASE/$1.out"
}

merge_calls() {
    grep -c '^pr merge' "$CASE/calls.log"
}

# run_exec <script> [args...] — stdin closed, the planted verdict script first
# on PATH.
run_exec() {
    local script="$1"
    shift
    OUT=$(GH_FIX="$CASE" PATH="$PLANTED:$BIN:$PATH" bash "$script" "$@" </dev/null 2>"$CASE/stderr")
    RC=$?
    ERR=$(cat "$CASE/stderr")
    [ -n "$OUT" ] && printf '%s\n' "$OUT" >> "$OUTPUT_LOG"
    return 0
}

# expect <label> <output> [args...] — runs the shipped merge-exec.sh.
expect() {
    local label="$1" want="$2"
    shift 2
    run_exec "$EXEC" "$@"
    if [ "$RC" -eq 0 ] && [ "$OUT" = "$want" ]; then
        pass "$label -> $want"
    else
        fail "$label: want [$want] exit 0, got [$OUT] exit $RC; stderr: $ERR"
    fi
}

expect_no_merge() {
    if [ "$(merge_calls)" -eq 0 ]; then
        pass "$1: no merge call"
    else
        fail "$1: a merge call was made: $(cat "$CASE/calls.log")"
    fi
}

expect_usage() {
    local label="$1"
    shift
    new_case usage
    run_exec "$EXEC" "$@"
    if [ "$RC" -ne 0 ] && [ -z "$OUT" ] && [ ! -s "$CASE/calls.log" ] \
        && printf '%s' "$ERR" | grep -q 'usage:'; then
        pass "usage: $label"
    else
        fail "usage: $label: exit $RC, stdout [$OUT], calls [$(cat "$CASE/calls.log")], stderr [$ERR]"
    fi
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

expect_usage "no arguments"
expect_usage "two arguments" o/r 7
expect_usage "four arguments" o/r 7 "$HEAD" --admin
expect_usage "flag instead of a positional" --repo o/r 7
expect_usage "expected head none" o/r 7 none
expect_usage "39-character sha" o/r 7 "${HEAD%1}"
expect_usage "uppercase sha" o/r 7 ABCDEF1111111111111111111111111111111111
expect_usage "pr 0" o/r 0 "$HEAD"
expect_usage "pr 012" o/r 012 "$HEAD"
expect_usage "pr 1;rm" o/r '1;rm' "$HEAD"
expect_usage "repo owner/repo/extra" o/r/extra 7 "$HEAD"
expect_usage "repo dot segment" ../r 7 "$HEAD"

# ---------------------------------------------------------------------------
# Refusals: the fresh verdict is not mergeable at the expected head
# ---------------------------------------------------------------------------

new_case refuse-head-moved; view ".headRefOid = \"$OTHER\" | .commits[0].oid = \"$OTHER\""
expect "fresh verdict head-moved" "merge-refused:awaiting:head-moved" o/r 7 "$HEAD"
expect_no_merge "head-moved"

new_case refuse-unprotected; fixture rules '[]'
expect "fresh verdict base-unprotected" "merge-refused:awaiting:base-unprotected" o/r 7 "$HEAD"
expect_no_merge "base-unprotected"

new_case refuse-pending; fixture checks '[{"name":"build","bucket":"pending"}]'
expect "fresh verdict pending:checks" "merge-refused:pending:checks" o/r 7 "$HEAD"
expect_no_merge "pending:checks"

new_case refuse-merged; view '.state = "MERGED"'
expect "fresh verdict merged" "merge-refused:merged" o/r 7 "$HEAD"
expect_no_merge "merged"

# A verdict script that says mergeable, but at a sha other than the expected
# head. Row 8 keeps the real script from ever printing this, so the case runs a
# copy of merge-exec.sh beside a stand-in, which is also what locating the
# verdict script by directory means.
SHIM_DIR="$WORK/shim-dir"
mkdir -p "$SHIM_DIR"
cp "$EXEC" "$SHIM_DIR/merge-exec.sh"
cat > "$SHIM_DIR/merge-verdict.sh" <<EOF
#!/usr/bin/env bash
echo "mergeable:squash:$OTHER"
EOF
new_case refuse-other-sha
run_exec "$SHIM_DIR/merge-exec.sh" o/r 7 "$HEAD"
if [ "$RC" -eq 0 ] && [ "$OUT" = "merge-refused:mergeable:squash:$OTHER" ]; then
    pass "fresh verdict mergeable at another sha -> $OUT"
else
    fail "mergeable at another sha: got [$OUT] exit $RC; stderr: $ERR"
fi
expect_no_merge "mergeable at another sha"

cat > "$SHIM_DIR/merge-verdict.sh" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
new_case refuse-verdict-failed
run_exec "$SHIM_DIR/merge-exec.sh" o/r 7 "$HEAD"
if [ "$RC" -eq 0 ] && [ "$OUT" = "merge-refused:not-merged:merge-call-failed" ]; then
    pass "a failing verdict script refuses -> $OUT"
else
    fail "failing verdict script: got [$OUT] exit $RC; stderr: $ERR"
fi
expect_no_merge "failing verdict script"

# ---------------------------------------------------------------------------
# The merge call
# ---------------------------------------------------------------------------

rm -f "$WORK/planted-ran"
for METHOD in squash merge rebase; do
    new_case "merge-$METHOD"
    case "$METHOD" in
        squash) fixture repo '{"allow_squash_merge":true,"allow_merge_commit":false,"allow_rebase_merge":false}' ;;
        merge)  fixture repo '{"allow_squash_merge":false,"allow_merge_commit":true,"allow_rebase_merge":false}' ;;
        rebase) fixture repo '{"allow_squash_merge":false,"allow_merge_commit":false,"allow_rebase_merge":true}' ;;
    esac
    expect "mergeable with $METHOD" "merge-called:$METHOD:$HEAD" o/r 7 "$HEAD"
    WANT_CALL="pr merge 7 --repo o/r --$METHOD --match-head-commit $HEAD"
    if [ "$(merge_calls)" -eq 1 ] && [ "$(grep '^pr merge' "$CASE/calls.log")" = "$WANT_CALL" ]; then
        pass "$METHOD: exactly one call, byte for byte [gh $WANT_CALL]"
    else
        fail "$METHOD: merge calls: $(grep '^pr merge' "$CASE/calls.log")"
    fi
done
if [ -e "$WORK/planted-ran" ]; then
    fail "location: the merge-verdict.sh planted on PATH was run"
else
    pass "location: the merge-verdict.sh planted on PATH was never run"
fi

new_case merge-fails
echo 1 > "$CASE/merge.rc"
echo 'GraphQL: Head branch was modified. Review and try the merge again.' > "$CASE/merge.err"
expect "merge call fails (row 18)" "merge-refused:not-merged:merge-call-failed" o/r 7 "$HEAD"
if [ "$(merge_calls)" -eq 1 ]; then
    pass "row 18: exactly one merge call, no second attempt"
else
    fail "row 18: $(merge_calls) merge calls"
fi

# End to end: the merge call succeeds but GitHub never reports MERGED (a merge
# queue that accepted without merging).
new_case merge-not-observed
fixture confirm '{"state":"OPEN"}'
expect "end to end: merge call exits 0" "merge-called:squash:$HEAD" o/r 7 "$HEAD"
EXEC_LINE="$OUT"
CONFIRM_LINE=$(GH_FIX="$CASE" MERGE_CONFIRM_WAIT_SECS=1 PATH="$BIN:$PATH" bash "$VERDICT" \
    --repo o/r --pr 7 --merge true --expected-head "$HEAD" --confirm </dev/null 2>/dev/null)
if [ "$CONFIRM_LINE" = "not-merged:merge-not-observed" ] && [ "$EXEC_LINE" != merged ] && [ "$CONFIRM_LINE" != merged ]; then
    pass "end to end: merge-called then not-merged:merge-not-observed; neither line is merged"
else
    fail "end to end: exec [$EXEC_LINE] confirm [$CONFIRM_LINE]"
fi

# ---------------------------------------------------------------------------
# Every merge call any case logged
# ---------------------------------------------------------------------------

BAD_FLAGS=$(cat "$WORK"/cases/*/calls.log | grep '^pr merge' | grep -E -- '--admin|--auto|--delete-branch')
ALL_MERGES=$(cat "$WORK"/cases/*/calls.log | grep -c '^pr merge')
if [ "$ALL_MERGES" -gt 0 ] && [ -z "$BAD_FLAGS" ]; then
    pass "none of $ALL_MERGES logged merge calls carries --admin, --auto, or --delete-branch"
else
    fail "merge calls with forbidden flags: [$BAD_FLAGS] (of $ALL_MERGES)"
fi

# ---------------------------------------------------------------------------
# Output grammar
# ---------------------------------------------------------------------------

GRAMMAR="$WORK/grammar"
sed -n 's/^#   \(\^.*\$\)$/\1/p' "$VERDICT" > "$GRAMMAR"
BAD_OUT=""
while IFS= read -r line; do
    case "$line" in
        merge-called:*)
            printf '%s\n' "$line" | grep -qE '^merge-called:(squash|merge|rebase):[0-9a-f]{40}$' || BAD_OUT="$BAD_OUT [$line]"
            ;;
        merge-refused:*)
            printf '%s\n' "${line#merge-refused:}" | grep -qE -f "$GRAMMAR" || BAD_OUT="$BAD_OUT [$line]"
            ;;
        *)
            BAD_OUT="$BAD_OUT [$line]"
            ;;
    esac
done < "$OUTPUT_LOG"
if [ -s "$OUTPUT_LOG" ] && [ -z "$BAD_OUT" ]; then
    pass "grammar: every merge-exec.sh output is merge-called or merge-refused:<verdict>"
else
    fail "grammar: outputs outside the grammar:$BAD_OUT"
fi
if grep -q '^#   ^merge-called:(squash|merge|rebase):\[0-9a-f\]{40}\$$' "$EXEC" \
    && grep -q '^#   ^merge-refused:<verdict>\$$' "$EXEC"; then
    pass "grammar: merge-exec.sh's header lists its anchored grammar"
else
    fail "grammar: merge-exec.sh's header does not list its anchored grammar"
fi

# ---------------------------------------------------------------------------
# One merge call site in the repository
# ---------------------------------------------------------------------------
#
# Every *.sh outside the tests, every workflow, and every `command:` or
# `default_action` line in a koto template. Comments do not count: headers are
# allowed to name the call they document.

SITES="$WORK/sites"
: > "$SITES"

# prefix_with <file> — prefixes each grep -n line with the file's repo path.
prefix_with() {
    local rel
    rel=${1#$REPO_ROOT/}
    sed "s|^|$rel:|"
}
find "$REPO_ROOT" -type f -name '*.sh' ! -name '*_test.sh' \
    -not -path '*/.git/*' -not -path '*/target/*' -not -path '*/node_modules/*' \
    -not -path "$REPO_ROOT/.claude/worktrees/*" > "$WORK/sh-files"
while IFS= read -r f; do
    grep -n 'gh pr merge' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | prefix_with "$f" >> "$SITES"
done < "$WORK/sh-files"
for f in "$REPO_ROOT"/.github/workflows/*.yml; do
    [ -f "$f" ] || continue
    grep -n 'gh pr merge' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | prefix_with "$f" >> "$SITES"
done
for f in "$REPO_ROOT"/skills/*/koto-templates/*.md; do
    [ -f "$f" ] || continue
    grep -n 'gh pr merge' "$f" | grep -E '^[0-9]+:.*(command:|default_action)' | prefix_with "$f" >> "$SITES"
done
SITE_COUNT=$(wc -l < "$SITES" | tr -d ' ')
if [ "$SITE_COUNT" -eq 1 ] && grep -q '^skills/execute/scripts/merge-exec.sh:' "$SITES"; then
    pass "one merge call site: $(cat "$SITES")"
else
    fail "want exactly one gh pr merge site, in merge-exec.sh; found $SITE_COUNT: $(cat "$SITES")"
fi

# ---------------------------------------------------------------------------
# Isolation: no stdin, no workflow engine
# ---------------------------------------------------------------------------

TOOLS="$WORK/tools"
mkdir -p "$TOOLS"
ln -s "$(command -v jq)" "$TOOLS/jq"
ln -s "$(command -v bash)" "$TOOLS/bash"
BARE_PATH="$TOOLS:/usr/bin:/bin"
if PATH="$BARE_PATH" command -v koto >/dev/null 2>&1; then
    fail "isolation: koto is reachable from $BARE_PATH, so the absence case proves nothing"
else
    new_case isolated
    WANT=$(printf 'yes\n' | GH_FIX="$CASE" PATH="$BIN:$PATH" bash "$EXEC" o/r 7 "$HEAD" 2>/dev/null)
    new_case isolated
    GOT=$(GH_FIX="$CASE" PATH="$BIN:$BARE_PATH" bash "$EXEC" o/r 7 "$HEAD" </dev/null 2>/dev/null)
    if [ "$WANT" = "merge-called:squash:$HEAD" ] && [ "$WANT" = "$GOT" ]; then
        pass "isolation: same output with stdin closed and no koto on PATH ($GOT)"
    else
        fail "isolation: normal [$WANT] vs isolated [$GOT]"
    fi
fi

echo ""
echo "merge-exec_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
