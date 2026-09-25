#!/usr/bin/env bash
# owned-pr_test.sh — the ownership filter's four outcomes, table-driven
# Part of the execute skill
#
# owned-pr.sh is the one head-branch lookup /execute, /scope, and /deliver share.
# This harness drives it through a test-local `gh` stub on PATH that serves
# per-case JSON fixtures and logs every call, so no case touches GitHub.
#
# It asserts the exit contract, case by case:
#
#   one owned PR                                   its URL, exit 0
#   no PR / fork only / other author only /
#     wrong base only / wrong head only            empty stdout, exit 0
#   two owned PRs                                  empty stdout, exit 3
#   --state all: closed-unmerged + open owned      the open URL, exit 0
#   --state all: one merged owned PR alone         its URL, exit 0
#   --state open: a merged owned PR                empty stdout, exit 0
#   failing gh for pr list, and for api user       empty stdout, exit 2
#   usage errors                                   empty stdout, exit 64, no gh call
#
# plus: the base defaults to the repository's default branch, the output names
# no caller step, and every gh call reads no stdin.
#
# Usage: owned-pr_test.sh
# Exit codes: 0 all pass, 1 a failure (or jq missing)

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
OWNED="$SCRIPT_DIR/owned-pr.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
[ -f "$OWNED" ] || { echo "FAIL: $OWNED not found" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/owned-pr-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN" "$WORK/cases"

# The gh stub: routes a call to a fixture key, logs it, and serves
# <case>/<key>.out / .err / .rc. A key with neither .out nor .rc fails.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
fix="${GH_FIX:?}"
printf '%s\n' "$*" >> "$fix/calls.log"
if [ ! -t 0 ]; then
    # Anything readable on stdin means the caller let its own stdin through.
    if [ -n "$(cat 2>/dev/null)" ]; then echo stdin >> "$fix/stdin.log"; fi
fi
key=unknown
case "$1 ${2:-}" in
    "api user") key=user ;;
    "api repos/"*) key=repo ;;
    "pr list") key=list ;;
esac
[ -f "$fix/$key.out" ] || [ -f "$fix/$key.rc" ] || { echo "gh stub: no fixture for [$key]" >&2; exit 1; }
[ -f "$fix/$key.out" ] && cat "$fix/$key.out"
[ -f "$fix/$key.err" ] && cat "$fix/$key.err" >&2
rc=0; [ -f "$fix/$key.rc" ] && rc=$(cat "$fix/$key.rc")
exit "$rc"
STUB
chmod +x "$BIN/gh"

ME=octo
URL1="https://github.com/o/r/pull/7"
URL2="https://github.com/o/r/pull/8"

# pr <number> <state> [field=value ...] — one pull request object, owned by
# default: same repository, author $ME, base main, head feat/x.
pr() {
    local n="$1" st="$2" f
    shift 2
    local obj
    obj=$(jq -nc --arg n "$n" --arg st "$st" --arg me "$ME" '{
        url: ("https://github.com/o/r/pull/" + $n), state: $st,
        isCrossRepository: false, author: {login: $me},
        baseRefName: "main", headRefName: "feat/x"}')
    for f in "$@"; do
        obj=$(printf '%s' "$obj" | jq -c "$f")
    done
    printf '%s' "$obj"
}

new_case() {
    CASE="$WORK/cases/$1"
    rm -rf "$CASE"; mkdir -p "$CASE"; : > "$CASE/calls.log"
    printf '{"login":"%s"}\n' "$ME" > "$CASE/user.out"
    echo '{"default_branch":"main"}' > "$CASE/repo.out"
    echo '[]' > "$CASE/list.out"
}

list() { # list <pr-json>... — the pr list fixture
    local items="" p
    for p in "$@"; do items="${items:+$items,}$p"; done
    printf '[%s]\n' "$items" > "$CASE/list.out"
}

failing() {
    rm -f "$CASE/$1.out"; echo 1 > "$CASE/$1.rc"; echo "HTTP 502" > "$CASE/$1.err"
}

run() { # run [args...] — default: open lookup on o/r feat/x base main
    if [ $# -eq 0 ]; then set -- --repo o/r --head feat/x --state open --base main; fi
    run_raw "$@"
}

run_raw() { # run_raw [args...] — exactly these arguments, none added
    OUT=$(GH_FIX="$CASE" PATH="$BIN:$PATH" bash "$OWNED" "$@" </dev/null 2>"$CASE/stderr")
    RC=$?
    ERR=$(cat "$CASE/stderr")
}

expect() { # expect <label> <stdout> <rc> [args...]
    local label="$1" want="$2" want_rc="$3"
    shift 3
    run "$@"
    if [ "$RC" -eq "$want_rc" ] && [ "$OUT" = "$want" ]; then
        pass "$label -> [${want}] exit $want_rc"
    else
        fail "$label: want [$want] exit $want_rc, got [$OUT] exit $RC; stderr: $ERR"
    fi
}

# --- exactly one survivor -----------------------------------------------------

new_case one
list "$(pr 7 OPEN)"
expect "one owned open PR" "$URL1" 0

# --- zero survivors, every flavour --------------------------------------------

new_case none
expect "no PR on the branch" "" 0

new_case fork
list "$(pr 7 OPEN '.isCrossRepository = true')"
expect "a same-named fork PR only" "" 0

new_case other-author
list "$(pr 7 OPEN '.author.login = "someone-else"')"
expect "another author's PR only" "" 0

new_case wrong-base
list "$(pr 7 OPEN '.baseRefName = "release"')"
expect "a wrong-base PR only" "" 0

new_case wrong-head
list "$(pr 7 OPEN '.headRefName = "feat/y"')"
expect "a wrong-head PR only" "" 0

new_case owned-closed-open-lookup
list "$(pr 7 CLOSED)"
expect "--state open: a closed owned PR is not a survivor" "" 0

new_case merged-open-lookup
list "$(pr 7 MERGED)"
expect "--state open: a merged owned PR is not a survivor" "" 0

# --- several survivors ---------------------------------------------------------

new_case two
list "$(pr 7 OPEN)" "$(pr 8 OPEN)"
expect "two owned PRs" "" 3

new_case two-plus-foreign
list "$(pr 7 OPEN)" "$(pr 8 OPEN)" "$(pr 9 OPEN '.isCrossRepository = true')"
expect "two owned PRs beside a fork PR still refuse to pick" "" 3

# --- --state all ---------------------------------------------------------------

new_case all-closed-plus-open
list "$(pr 7 CLOSED)" "$(pr 8 OPEN)"
expect "--state all: closed-unmerged plus open gives the open one" "$URL2" 0 \
    --repo o/r --head feat/x --state all --base main

new_case all-merged
list "$(pr 7 MERGED)"
expect "--state all: one merged owned PR alone" "$URL1" 0 \
    --repo o/r --head feat/x --state all --base main

new_case all-merged-and-open
list "$(pr 7 MERGED)" "$(pr 8 OPEN)"
expect "--state all: a merged and an open owned PR are several" "" 3 \
    --repo o/r --head feat/x --state all --base main

new_case all-state-arg
list "$(pr 7 MERGED)"
run --repo o/r --head feat/x --state all --base main
if grep -q -- '--state all' "$CASE/calls.log"; then
    pass "--state all is passed through to gh pr list"
else
    fail "--state all did not reach gh pr list: $(cat "$CASE/calls.log")"
fi

# --- read failures -------------------------------------------------------------

new_case list-fails
failing list
expect "failing gh pr list" "" 2

new_case user-fails
list "$(pr 7 OPEN)"
failing user
expect "failing gh api user" "" 2

new_case list-not-json
echo 'not json' > "$CASE/list.out"
expect "gh pr list printing something that is not JSON" "" 2

new_case user-bad-login
list "$(pr 7 OPEN)"
echo '{"login":"a b; rm"}' > "$CASE/user.out"
expect "an unusable login" "" 2

new_case foreign-url
list "$(pr 7 OPEN '.url = "https://github.com/evil/r/pull/7"')"
expect "a survivor whose URL names another repository" "" 2

# --- the base defaults to the repository's default branch ---------------------

new_case default-base
echo '{"default_branch":"trunk"}' > "$CASE/repo.out"
list "$(pr 7 OPEN '.baseRefName = "trunk"')"
expect "no --base: the default branch is the expected base" "$URL1" 0 \
    --repo o/r --head feat/x --state open

new_case default-base-mismatch
list "$(pr 7 OPEN '.baseRefName = "release"')"
expect "no --base: a PR on another base is not a survivor" "" 0 \
    --repo o/r --head feat/x --state open

new_case default-base-fails
failing repo
expect "no --base and the repository read fails" "" 2 \
    --repo o/r --head feat/x --state open

# --- usage: exit 64, no gh call -----------------------------------------------

expect_usage() {
    local label="$1"
    shift
    new_case usage
    run_raw "$@"
    if [ "$RC" -eq 64 ] && [ -z "$OUT" ] && [ ! -s "$CASE/calls.log" ]; then
        pass "usage: $label"
    else
        fail "usage: $label: exit $RC, stdout [$OUT], calls [$(cat "$CASE/calls.log")]"
    fi
}
expect_usage "no arguments"
expect_usage "missing --state" --repo o/r --head feat/x
expect_usage "bad --state" --repo o/r --head feat/x --state merged
expect_usage "comma-joined --repo" --repo o/r,o/s --head feat/x --state open
expect_usage "dot repo" --repo o/.. --head feat/x --state open
expect_usage "head with .." --repo o/r --head 'a..b' --state open
expect_usage "head with a leading dash" --repo o/r --head '-x' --state open
expect_usage "head with a space" --repo o/r --head 'a b' --state open
expect_usage "bad base" --repo o/r --head feat/x --state open --base 'm;n'
expect_usage "repeated --head" --repo o/r --head a --head b --state open
expect_usage "stray positional" --repo o/r --head a --state open extra

# --- the contract names no caller step ----------------------------------------

if grep -n 'pr-adopt\|status-read\|pr-create\|child-outcome' "$OWNED" >/dev/null; then
    fail "owned-pr.sh names a caller step; callers map its exit codes themselves"
else
    pass "owned-pr.sh names no caller step"
fi

# --- no stdin reaches gh -------------------------------------------------------

new_case stdin
list "$(pr 7 OPEN)"
OUT=$(echo "leak" | GH_FIX="$CASE" PATH="$BIN:$PATH" bash "$OWNED" --repo o/r --head feat/x --state open --base main 2>/dev/null)
if [ "$OUT" = "$URL1" ] && [ ! -s "$CASE/stdin.log" ]; then
    pass "gh reads no stdin"
else
    fail "gh saw stdin or the lookup changed: [$OUT] $(cat "$CASE/stdin.log" 2>/dev/null)"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
