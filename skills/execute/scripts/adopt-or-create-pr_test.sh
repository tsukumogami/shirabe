#!/usr/bin/env bash
# adopt-or-create-pr_test.sh — orchestrator_setup's home-PR step, and the write
# set it runs against
# Part of the execute skill
#
# Two scripts that run before any child is spawned:
#
#   adopt-or-create-pr.sh  finds the owned PR on a branch, opens one only on the
#                          create path, and records home_pr from owned-pr.sh's
#                          output (never from anything the agent says);
#   record-write-set.sh    fixes the run's write set, `repos`, at start.
#
# A `gh` stub serves per-case fixtures (a numbered file answers the Nth call,
# which is how "no PR, then the PR just created" is served) and logs every call;
# a `koto` stub keeps context in a directory. No network, no engine.
#
# Usage: adopt-or-create-pr_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
ADOPT="$SCRIPT_DIR/adopt-or-create-pr.sh"
WRITESET="$SCRIPT_DIR/record-write-set.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/adopt-or-create-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN"
S=execute-topic
URL="https://github.com/o/r/pull/7"

cat > "$BIN/koto" <<'STUB'
#!/usr/bin/env bash
store="${KOTO_STORE:?}"
printf '%s\n' "$*" >> "$store/koto.log"
d="$store/ctx/$3"
mkdir -p "$d"
case "$1 $2" in
    "context add") cat > "$d/$4" ;;
    "context get") [ -f "$d/$4" ] || exit 3; cat "$d/$4" ;;
    *) exit 9 ;;
esac
STUB
chmod +x "$BIN/koto"

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
fix="${GH_FIX:?}"
printf '%s\n' "$*" >> "$fix/gh.log"
key=unknown
case "$1 ${2:-}" in
    "api user") key=user ;;
    "api repos/"*) key=repo ;;
    "pr list") key=list ;;
    "pr create") key=create ;;
    "repo view") key=repoview ;;
esac
n=0; [ -f "$fix/$key.count" ] && n=$(cat "$fix/$key.count"); n=$((n + 1)); echo "$n" > "$fix/$key.count"
out="$fix/$key.out"; [ -f "$fix/$key.out.$n" ] && out="$fix/$key.out.$n"
rcf="$fix/$key.rc"; [ -f "$fix/$key.rc.$n" ] && rcf="$fix/$key.rc.$n"
[ -f "$out" ] || [ -f "$rcf" ] || { echo "gh stub: no fixture for [$key]" >&2; exit 1; }
[ -f "$out" ] && cat "$out"
rc=0; [ -f "$rcf" ] && rc=$(cat "$rcf")
exit "$rc"
STUB
chmod +x "$BIN/gh"

owned() { # owned <number> [jq edit] — one PR object on impl/topic
    jq -nc --arg n "$1" '{url: ("https://github.com/o/r/pull/" + $n), state: "OPEN",
        isCrossRepository: false, author: {login: "octo"}, baseRefName: "main", headRefName: "impl/topic"}' \
        | jq -c "${2:-.}"
}

new_case() {
    CASE="$WORK/cases/$1"
    rm -rf "$CASE"; mkdir -p "$CASE/ctx/$S"
    : > "$CASE/gh.log"; : > "$CASE/koto.log"
    echo '{"login":"octo"}' > "$CASE/user.out"
    echo '{"default_branch":"main"}' > "$CASE/repo.out"
    echo '[]' > "$CASE/list.out"
    : > "$CASE/create.out"
}
ctx() { cat "$CASE/ctx/$S/$1" 2>/dev/null; }

run_adopt() {
    OUT=$(env KOTO_STORE="$CASE" GH_FIX="$CASE" PATH="$BIN:$PATH" bash "$ADOPT" "$@" </dev/null 2>"$CASE/stderr")
    RC=$?
}
creates() { grep -c '^pr create' "$CASE/gh.log"; }

# --- adopt: one owned PR on the branch ----------------------------------------

new_case adopt
echo "[$(owned 7)]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic
if [ "$RC" -eq 0 ] && [ "$OUT" = "$URL" ] && [ "$(ctx home_pr)" = "$URL" ] \
    && [ "$(ctx waiting)" = "$URL:human" ] && [ "$(creates)" -eq 0 ]; then
    pass "one owned PR: adopted, home_pr and waiting recorded, no pr create"
else
    fail "adopt: exit $RC, out [$OUT], home_pr [$(ctx home_pr)], creates $(creates)"
fi

new_case adopt-with-create
echo "[$(owned 7)]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 0 ] && [ "$(creates)" -eq 0 ]; then
    pass "--create with an owned PR already there reuses it and creates nothing"
else
    fail "adopt with --create: exit $RC, creates $(creates)"
fi

# --- zero survivors -----------------------------------------------------------

new_case current-branch-foreign
echo "[$(owned 7 '.author.login = "someone-else"')]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic
if [ "$RC" -eq 4 ] && [ -z "$(ctx home_pr)" ] && [ "$(creates)" -eq 0 ]; then
    pass "another author's PR only, no --create: exit 4, not adopted, nothing recorded"
else
    fail "foreign no-create: exit $RC, home_pr [$(ctx home_pr)]"
fi

new_case create
echo '[]' > "$CASE/list.out.1"
echo "[$(owned 7)]" > "$CASE/list.out.2"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 0 ] && [ "$(creates)" -eq 1 ] && [ "$(ctx home_pr)" = "$URL" ]; then
    pass "zero owned PRs with --create: exactly one pr create, then the new PR is recorded"
else
    fail "create: exit $RC, creates $(creates), home_pr [$(ctx home_pr)]"
fi
if grep -q '^pr create --draft --repo o/r --head impl/topic --title impl: topic --body Implements docs/plans/PLAN-topic.md.$' "$CASE/gh.log"; then
    pass "the create call is the fixed draft form"
else
    fail "create call: $(grep '^pr create' "$CASE/gh.log")"
fi

new_case fork-then-create
echo "[$(owned 7 '.isCrossRepository = true')]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 3 ] && [ "$(creates)" -eq 1 ] && [ -z "$(ctx home_pr)" ]; then
    pass "a same-named fork PR: one pr create, the fork PR is never adopted; still none owned ends pr-adopt (3)"
else
    fail "fork then create: exit $RC, creates $(creates), home_pr [$(ctx home_pr)]"
fi

new_case create-fails
echo 1 > "$CASE/create.rc"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 5 ] && [ -z "$(ctx home_pr)" ]; then
    pass "a failed pr create: exit 5, nothing recorded"
else
    fail "create fails: exit $RC"
fi

# --- several, and read failure ------------------------------------------------

new_case several
echo "[$(owned 7),$(owned 8)]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 3 ] && [ "$(creates)" -eq 0 ] && [ -z "$(ctx home_pr)" ]; then
    pass "several owned PRs: exit 3 (pr-adopt), no create, nothing recorded"
else
    fail "several: exit $RC, creates $(creates)"
fi

new_case read-fails
rm -f "$CASE/list.out"; echo 1 > "$CASE/list.rc"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 2 ] && [ "$(creates)" -eq 0 ]; then
    pass "a failed read: exit 2 (status-read), no create"
else
    fail "read fails: exit $RC, creates $(creates)"
fi

# --- usage --------------------------------------------------------------------

for args in \
    "--repo o/r --head impl/topic" \
    "--session $S --repo o/r,o/s --head impl/topic" \
    "--session $S --repo o/r --head a..b" \
    "--session $S --repo o/r --head impl/topic --create" \
    "--session $S --repo o/r --head impl/topic --create --plan-slug Topic --plan-doc x.md" \
    "--session $S --repo o/r --head impl/topic --create --plan-slug topic --plan-doc ../x.md" \
    "--session $S --repo o/r --head impl/topic --plan-slug topic"; do
    new_case usage
    # shellcheck disable=SC2086
    run_adopt $args
    if [ "$RC" -eq 64 ] && [ ! -s "$CASE/gh.log" ] && [ ! -s "$CASE/koto.log" ]; then
        pass "usage: [$args]"
    else
        fail "usage: [$args] exit $RC"
    fi
done

# --- record-write-set.sh ------------------------------------------------------

ws_repo() { # ws_repo <name> <origin url or empty>
    WS="$WORK/ws/$1"
    rm -rf "$WS"; mkdir -p "$WS"
    git init -q "$WS"
    [ -n "$2" ] && git -C "$WS" remote add origin "$2"
    return 0
}
run_ws() {
    OUT=$(cd "$WS" && env KOTO_STORE="$CASE" GH_FIX="$CASE" PATH="$BIN:$PATH" bash "$WRITESET" "$@" </dev/null 2>"$CASE/stderr")
    RC=$?
}

for url in https://github.com/o/r https://github.com/o/r.git https://github.com/o/r/ \
           git@github.com:o/r.git ssh://git@github.com/o/r.git https://token@github.com/o/r.git; do
    new_case ws
    ws_repo url "$url"
    run_ws "$S"
    if [ "$RC" -eq 0 ] && [ "$OUT" = "o/r" ] && [ "$(ctx repos)" = "o/r" ]; then
        pass "write set from origin [$url] is o/r"
    else
        fail "write set from [$url]: exit $RC, out [$OUT], repos [$(ctx repos)]"
    fi
done

new_case ws-insteadof
ws_repo insteadof https://github.com/o/r.git
git -C "$WS" config url."$WORK/elsewhere.git".insteadOf https://github.com/o/r.git
run_ws "$S"
[ "$(ctx repos)" = "o/r" ] && pass "the configured URL is read, not its insteadOf rewrite" \
    || fail "insteadOf: repos [$(ctx repos)]"

new_case ws-fallback
ws_repo local "$WORK/some/local/origin.git"
echo 'o/fallback' > "$CASE/repoview.out"
run_ws "$S"
if [ "$RC" -eq 0 ] && [ "$(ctx repos)" = "o/fallback" ]; then
    pass "a non-GitHub origin falls back to gh repo view"
else
    fail "fallback: exit $RC, repos [$(ctx repos)]"
fi

new_case ws-none
ws_repo none ""
echo 1 > "$CASE/repoview.rc"
run_ws "$S"
if [ "$RC" -eq 65 ] && [ -z "$(ctx repos)" ]; then
    pass "no readable owner/repo: exit 65, nothing recorded"
else
    fail "none: exit $RC"
fi

new_case ws-bad
ws_repo bad "$WORK/x.git"
echo 'o/r;rm' > "$CASE/repoview.out"
run_ws "$S"
if [ "$RC" -eq 66 ] && [ -z "$(ctx repos)" ]; then
    pass "an owner/repo outside the pattern: exit 66"
else
    fail "bad: exit $RC"
fi

new_case ws-fixed
ws_repo fixed https://github.com/o/r
printf 'o/other' > "$CASE/ctx/$S/repos"
run_ws "$S"
if [ "$RC" -eq 67 ] && [ "$(ctx repos)" = "o/other" ]; then
    pass "a write set already fixed is never changed (exit 67)"
else
    fail "fixed: exit $RC, repos [$(ctx repos)]"
fi

new_case ws-same
ws_repo same https://github.com/o/r
printf 'o/r' > "$CASE/ctx/$S/repos"
run_ws "$S"
[ "$RC" -eq 0 ] && pass "re-running with the same write set is a no-op" || fail "same: exit $RC"

new_case ws-print
ws_repo print git@github.com:o/r.git
run_ws --print
if [ "$RC" -eq 0 ] && [ "$OUT" = "o/r" ] && [ ! -s "$CASE/koto.log" ]; then
    pass "--print derives the same write set and records nothing"
else
    fail "--print: exit $RC, out [$OUT], koto [$(cat "$CASE/koto.log")]"
fi

new_case ws-usage
ws_repo usage https://github.com/o/r
run_ws 'a b'
[ "$RC" -eq 64 ] && [ ! -s "$CASE/koto.log" ] && pass "record-write-set.sh: an invalid session is a usage error" \
    || fail "ws usage: exit $RC"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
