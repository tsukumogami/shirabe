#!/usr/bin/env bash
# owned-pr_test.sh — the ownership filter's outcomes, table-driven
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
#   --run-id: latest index entry names this run    its URL, exit 0
#   --run-id: no index entry                       its URL, exit 0 (fallback)
#   --run-id: one PR, another run's latest entry   empty stdout, exit 5
#   --run-id: an entry for this run on a PR that   never a survivor
#     fails one of the five checks
#   several candidates, at least one recorded      empty stdout, exit 4
#     (including a lone survivor beside a PR another run recorded)
#   --run-id: an index that can't be read          empty stdout, exit 2
#   no --run-id: the index is never read
#   --take-over: the exit-5 PR gets this run's     its URL, exit 0; no PR
#     index entry                                  edited; never a fork's,
#                                                  another author's, or
#                                                  another branch's PR
#   --state all: closed-unmerged + open owned      the open URL, exit 0
#   --state all: one merged owned PR alone         its URL, exit 0
#   --state open: a merged owned PR                empty stdout, exit 0
#   --state open-else-merged: the open answer       the open URL, exit 0; never
#     while one is open, else the merged one       an earlier run's merged PR
#                                                  beside it, and a closed-
#                                                  unmerged PR is no survivor
#   failing gh for pr list, and for api user       empty stdout, exit 2
#   usage errors                                   empty stdout, exit 64, no gh call
#
# plus: the base defaults to the repository's default branch, the output names
# no caller step, and every gh call reads no stdin. The index lives in the
# record stub koto (scripts/testdata/record-koto), asserted to be the koto on
# PATH, at a shared address under each case's own SHIRABE_RUN_RECORD_TEST_ROOT.
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

WORK=$(mktemp -d "${TMPDIR:-/tmp}/owned-pr-test.XXXXXX") || exit 1
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
    "pr edit")
        # gh pr edit <n> --repo <repo> --body-file <f>: replace that PR's body
        # in the list fixture, so the next lookup sees the edit.
        [ -f "$fix/edit.rc" ] && exit "$(cat "$fix/edit.rc")"
        [ "$4" = "--repo" ] && [ "$6" = "--body-file" ] || { echo "gh stub: pr edit shape [$*]" >&2; exit 1; }
        url="https://github.com/$5/pull/$3"
        cp "$7" "$fix/edited-body"
        jq --arg u "$url" --rawfile b "$7" 'map(if .url == $u then .body = $b else . end)' \
            "$fix/list.out" > "$fix/list.new" && mv "$fix/list.new" "$fix/list.out"
        exit 0
        ;;
esac
[ -f "$fix/$key.out" ] || [ -f "$fix/$key.rc" ] || { echo "gh stub: no fixture for [$key]" >&2; exit 1; }
[ -f "$fix/$key.out" ] && cat "$fix/$key.out"
[ -f "$fix/$key.err" ] && cat "$fix/$key.err" >&2
rc=0; [ -f "$fix/$key.rc" ] && rc=$(cat "$fix/$key.rc")
exit "$rc"
STUB
chmod +x "$BIN/gh"

# The index reads and a takeover's write go to the record stub koto, never a
# real one, with each case's shared address in its own temp directory
# (SHIRABE_RUN_RECORD_TEST_ROOT). The stub must be the koto on PATH.
STUB_DIR="$SCRIPT_DIR/../../../scripts/testdata/record-koto"
STUB_DIR=$(CDPATH='' cd "$STUB_DIR" && pwd) || { echo "FAIL: the record stub koto is missing" >&2; exit 1; }
case "$(PATH="$BIN:$STUB_DIR:$PATH" command -v koto)" in
    "$STUB_DIR/koto") ;;
    *) echo "FAIL: the koto on PATH is not the record stub; refusing to run" >&2; exit 1 ;;
esac
export PATH="$STUB_DIR:$PATH"

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
    RUN_DIR="$WORK"
    rm -rf "$CASE"; mkdir -p "$CASE/koto" "$CASE/shared"; : > "$CASE/calls.log"
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
    OUT=$(cd "$RUN_DIR" && GH_FIX="$CASE" PATH="$BIN:$STUB_DIR:$PATH" RECORD_KOTO_STORE="$CASE/koto" \
        SHIRABE_RUN_RECORD_TEST_ROOT="$CASE/shared" bash "$OWNED" "$@" </dev/null 2>"$CASE/stderr")
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

# --- the run's index entry --------------------------------------------------------

# A PR's index session holds one entry per run that recorded it; the latest
# (by written_at) decides. plant <n> <run_id> [<written_at>] writes one entry
# the way scripts/run-trail.sh index lays it out, at this case's shared
# address, through the stub koto.
MINE=0123456789abcdef0123456789abcdef
OTHER=fedcba9876543210fedcba9876543210
THIRD=11111111111111111111111111111111
plant() {
    local n="$1" rid="$2" at="${3:-2026-01-01T00:00:00Z}" d="$CASE/shared/o"
    mkdir -p "$d"
    (cd "$d" && RECORD_KOTO_STORE="$CASE/koto" koto init "pr.o.r.$n" --template t >/dev/null 2>&1
     jq -nc --arg at "$at" '{workspace: "/w", session: "execute-x", session_id: "sid-1",
         mode: "single-pr", topic: "x", written_at: $at}' \
         | RECORD_KOTO_STORE="$CASE/koto" koto context add "pr.o.r.$n" "run/$rid" >/dev/null)
}
# latest <n>: the run the PR's index names last, read the way owned-pr.sh does.
latest() {
    (SHIRABE_RUN_RECORD_TEST_ROOT="$CASE/shared" RECORD_KOTO_STORE="$CASE/koto" bash -c \
        '. "$1/../../../scripts/lib/record-store.sh" && rs_index_latest_run o/r "$2"' _ "$SCRIPT_DIR" "$1")
}
RUN=(--repo o/r --head feat/x --state open --base main --run-id "$MINE")

new_case index-mine
list "$(pr 7 OPEN)"; plant 7 "$MINE"
expect "--run-id: the PR's latest index entry names this run" "$URL1" 0 "${RUN[@]}"

new_case index-foreign
list "$(pr 7 OPEN)"; plant 7 "$OTHER"
expect "--run-id: the one PR on this login and branch was recorded by another run (exit 5)" "" 5 "${RUN[@]}"
case "$ERR" in
    *"$URL1"*) pass "exit 5 names the other run's PR on stderr" ;;
    *) fail "exit 5 does not name the PR on stderr: [$ERR]" ;;
esac

new_case index-latest-mine
list "$(pr 7 OPEN)"; plant 7 "$OTHER" 2026-01-01T00:00:00Z; plant 7 "$MINE" 2026-02-01T00:00:00Z
expect "--run-id: the latest entry decides (this run's after another's)" "$URL1" 0 "${RUN[@]}"

new_case index-latest-foreign
list "$(pr 7 OPEN)"; plant 7 "$MINE" 2026-01-01T00:00:00Z; plant 7 "$OTHER" 2026-02-01T00:00:00Z
expect "--run-id: the latest entry decides (another run's after this one's)" "" 5 "${RUN[@]}"

new_case index-none
list "$(pr 7 OPEN '.body = "Implements docs/plans/PLAN-x.md."')"
expect "--run-id: a PR with no index entry falls back to the five checks" "$URL1" 0 "${RUN[@]}"

new_case index-malformed
list "$(pr 7 OPEN)"; plant 7 "$OTHER" not-a-time
expect "--run-id: an entry whose written_at fails its pattern is passed over" "$URL1" 0 "${RUN[@]}"

new_case index-mine-other-author
list "$(pr 7 OPEN '.author.login = "someone-else"')"; plant 7 "$MINE"
expect "--run-id: an entry for this run never rescues another author's PR" "" 0 "${RUN[@]}"

new_case index-mine-fork
list "$(pr 7 OPEN '.isCrossRepository = true')"; plant 7 "$MINE"
expect "--run-id: an entry for this run never rescues a fork's PR" "" 0 "${RUN[@]}"

new_case index-mine-wrong-base
list "$(pr 7 OPEN '.baseRefName = "release"')"; plant 7 "$MINE"
expect "--run-id: an entry for this run never rescues a PR on another base" "" 0 "${RUN[@]}"

new_case index-mine-closed
list "$(pr 7 CLOSED)"; plant 7 "$MINE"
expect "--run-id: an entry for this run never rescues a closed PR" "" 0 "${RUN[@]}"

new_case index-hand-run
list "$(pr 7 OPEN)"; plant 7 "$OTHER"
expect "no --run-id (a hand run): the index is not read and the five checks decide" "$URL1" 0
if [ -s "$CASE/koto/calls.log" ] && grep -q 'context list' "$CASE/koto/calls.log"; then
    fail "a hand run read the index: $(cat "$CASE/koto/calls.log")"
else
    pass "a hand run makes no koto call"
fi

new_case index-mine-beside-none
list "$(pr 7 OPEN)" "$(pr 8 OPEN)"; plant 7 "$MINE"
expect "this run's PR beside one with no entry is ambiguous (exit 4)" "" 4 "${RUN[@]}"

new_case index-two-hand
list "$(pr 7 OPEN)" "$(pr 8 OPEN)"; plant 7 "$MINE"; plant 8 "$OTHER"
expect "no --run-id: two owned PRs stay several (exit 3), the index unread" "" 3

new_case index-two-foreign
list "$(pr 7 OPEN)" "$(pr 8 OPEN)"; plant 7 "$OTHER"; plant 8 "$THIRD"
expect "--run-id: two other runs' PRs and none of mine are ambiguous (exit 4)" "" 4 "${RUN[@]}"

new_case index-mine-beside-foreign
list "$(pr 7 MERGED)" "$(pr 8 OPEN)"; plant 7 "$OTHER"; plant 8 "$MINE"
expect "--run-id --state all: my PR beside one another run recorded is ambiguous (exit 4)" "" 4 \
    --repo o/r --head feat/x --state all --base main --run-id "$MINE"

new_case index-foreign-beside-none
list "$(pr 8 MERGED)" "$(pr 7 OPEN)"; plant 7 "$OTHER"
expect "--run-id --state all: an unrecorded merged PR beside another run's open PR is ambiguous (exit 4)" "" 4 \
    --repo o/r --head feat/x --state all --base main --run-id "$MINE"

new_case index-two-none
list "$(pr 7 OPEN)" "$(pr 8 OPEN)"
expect "--run-id: two candidates with no entry stay exit 3" "" 3 "${RUN[@]}"

new_case index-unreadable
list "$(pr 7 OPEN)"; plant 7 "$MINE"
RECORD_KOTO_FAIL_READS=1 run "${RUN[@]}"
if [ "$RC" -eq 2 ] && [ -z "$OUT" ]; then
    pass "--run-id: an index that can't be read is a failed read (exit 2), never a guess"
else
    fail "an unreadable index: [$OUT] exit $RC; stderr: $ERR"
fi

new_case index-no-body
list "$(pr 7 OPEN)"
run "${RUN[@]}"
if grep -q -- '--json url,state,isCrossRepository,author,baseRefName,headRefName --limit' "$CASE/calls.log"; then
    pass "gh pr list no longer asks for the body"
else
    fail "gh pr list's fields: $(cat "$CASE/calls.log")"
fi

# --- --state open-else-merged -------------------------------------------------

# The open answer while the branch has an open candidate, the merged one only
# once it has none (#958): /execute's ci_monitor gates follow the run's PR
# from open to merged with it.
OEM=(--repo o/r --head feat/x --state open-else-merged --base main --run-id "$MINE")

new_case oem-open
list "$(pr 7 OPEN)"; plant 7 "$MINE"
expect "open-else-merged: my open PR alone" "$URL1" 0 "${OEM[@]}"

new_case oem-merged
list "$(pr 7 MERGED)"; plant 7 "$MINE"
expect "open-else-merged: my merged PR alone" "$URL1" 0 "${OEM[@]}"

new_case oem-merged-unrecorded
list "$(pr 7 MERGED)"
expect "open-else-merged: a merged PR with no entry falls back to the five checks" "$URL1" 0 "${OEM[@]}"

new_case oem-closed-only
list "$(pr 7 CLOSED)"; plant 7 "$MINE"
expect "open-else-merged: a closed-unmerged PR alone is no survivor, as under --state open" "" 0 "${OEM[@]}"
run --repo o/r --head feat/x --state open --base main --run-id "$MINE"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] \
    && pass "open-else-merged: --state open gives the same answer on that branch" \
    || fail "--state open on a closed-only branch: [$OUT] exit $RC"

new_case oem-none
expect "open-else-merged: no PR on the branch" "" 0 "${OEM[@]}"

new_case oem-earlier-merged-plus-open
list "$(pr 7 MERGED)" "$(pr 8 OPEN)"; plant 7 "$OTHER"; plant 8 "$MINE"
expect "open-else-merged: an earlier run's merged PR beside my open one gives the open one" "$URL2" 0 "${OEM[@]}"

new_case oem-unrecorded-merged-plus-open
list "$(pr 7 MERGED)" "$(pr 8 OPEN)"; plant 8 "$MINE"
expect "open-else-merged: an unrecorded merged PR beside my open one gives the open one" "$URL2" 0 "${OEM[@]}"

new_case oem-my-merged-plus-foreign-open
list "$(pr 7 MERGED)" "$(pr 8 OPEN)"; plant 7 "$MINE"; plant 8 "$OTHER"
expect "open-else-merged: my merged PR beside another run's open one is that run's branch (exit 5, as --state open)" "" 5 "${OEM[@]}"

new_case oem-foreign-merged
list "$(pr 7 MERGED)"; plant 7 "$OTHER"
expect "open-else-merged: another run's merged PR alone is never mine (exit 5)" "" 5 "${OEM[@]}"

new_case oem-merged-other-author
list "$(pr 7 MERGED '.author.login = "someone-else"')"; plant 7 "$MINE"
expect "open-else-merged: another author's merged PR is no survivor" "" 0 "${OEM[@]}"

new_case oem-merged-fork
list "$(pr 7 MERGED '.isCrossRepository = true')"; plant 7 "$MINE"
expect "open-else-merged: a fork's merged PR is no survivor" "" 0 "${OEM[@]}"

new_case oem-two-merged
list "$(pr 7 MERGED)" "$(pr 8 MERGED)"; plant 7 "$MINE"; plant 8 "$MINE"
expect "open-else-merged: two merged PRs of mine are ambiguous (exit 4)" "" 4 "${OEM[@]}"

new_case oem-closed-plus-merged
list "$(pr 7 CLOSED)" "$(pr 8 MERGED)"; plant 7 "$MINE"; plant 8 "$MINE"
expect "open-else-merged: a closed-unmerged PR never stands beside the merged one" "$URL2" 0 "${OEM[@]}"

new_case oem-state-arg
list "$(pr 7 MERGED)"
run "${OEM[@]}"
if grep -q -- '--state all ' "$CASE/calls.log" && ! grep -q -- 'open-else-merged' "$CASE/calls.log"; then
    pass "open-else-merged asks gh pr list for --state all"
else
    fail "open-else-merged's gh call: $(cat "$CASE/calls.log")"
fi

# --- taking over ------------------------------------------------------------------

# take_case: a case whose checkout holds this run's record root, execute-x,
# with run_id MINE, so run-trail.sh index can write its entry from there.
take_case() {
    new_case "$1"
    RUN_DIR="$CASE/checkout"
    mkdir -p "$RUN_DIR"
    (cd "$CASE/checkout" && RECORD_KOTO_STORE="$CASE/koto" koto init execute-x --template t >/dev/null \
        && printf '%s' "$MINE" | RECORD_KOTO_STORE="$CASE/koto" koto context add execute-x run_id >/dev/null)
}
TAKE=(--take-over --session execute-x)

take_case takeover
list "$(pr 7 OPEN '.body = "Some body.\ntrailing words\n"')"; plant 7 "$OTHER" 2026-01-01T00:00:00Z
run "${RUN[@]}" "${TAKE[@]}"
if [ "$RC" -eq 0 ] && [ "$OUT" = "$URL1" ]; then
    pass "--take-over: the one PR another run recorded on my branch is recorded as mine and returned"
else
    fail "--take-over: [$OUT] exit $RC; stderr: $ERR"
fi
if [ "$(latest 7)" = "$MINE" ]; then
    pass "--take-over writes this run's index entry, now the PR's latest"
else
    fail "--take-over: the latest entry is [$(latest 7)]"
fi
if grep -q '^pr edit' "$CASE/calls.log"; then
    fail "--take-over edited a PR: $(grep '^pr edit' "$CASE/calls.log")"
else
    pass "--take-over edits no PR body"
fi
expect "after a takeover the ordinary lookup matches" "$URL1" 0 "${RUN[@]}"

take_case takeover-not-silent
list "$(pr 7 OPEN)"; plant 7 "$OTHER"
expect "without --take-over another run's PR is refused and nothing is written" "" 5 "${RUN[@]}"
if [ "$(latest 7)" = "$OTHER" ]; then pass "the ordinary lookup writes no index entry"; else fail "the ordinary lookup wrote an entry"; fi

take_case takeover-other-author
list "$(pr 7 OPEN '.author.login = "someone-else"')"; plant 7 "$OTHER"
expect "--take-over refuses a PR that is not mine (another author)" "" 0 "${RUN[@]}" "${TAKE[@]}"
take_case takeover-fork
list "$(pr 7 OPEN '.isCrossRepository = true')"; plant 7 "$OTHER"
expect "--take-over refuses a PR that is not mine (a fork)" "" 0 "${RUN[@]}" "${TAKE[@]}"
take_case takeover-other-head
list "$(pr 7 OPEN '.headRefName = "feat/y"')"; plant 7 "$OTHER"
expect "--take-over refuses a PR on another branch" "" 0 "${RUN[@]}" "${TAKE[@]}"
if [ "$(latest 7)" = "$OTHER" ]; then
    pass "--take-over writes nothing for a PR it refuses"
else
    fail "--take-over wrote an entry for a PR that was not mine"
fi

take_case takeover-two-foreign
list "$(pr 7 OPEN)" "$(pr 8 OPEN)"; plant 7 "$OTHER"; plant 8 "$THIRD"
expect "--take-over never picks among several foreign PRs (exit 4)" "" 4 "${RUN[@]}" "${TAKE[@]}"

take_case takeover-mine-already
list "$(pr 7 OPEN)"; plant 7 "$MINE"
expect "--take-over on a PR already mine just returns it" "$URL1" 0 "${RUN[@]}" "${TAKE[@]}"
if [ "$(grep -c 'context add pr.o.r.7' "$CASE/koto/calls.log")" -eq 1 ]; then
    pass "no entry written when the PR is already mine"
else
    fail "--take-over wrote an entry for a PR already mine"
fi

take_case takeover-write-fails
list "$(pr 7 OPEN)"; plant 7 "$OTHER"
RECORD_KOTO_FAIL_WRITES=1 run "${RUN[@]}" "${TAKE[@]}"
if [ "$RC" -eq 2 ] && [ -z "$OUT" ]; then
    pass "--take-over whose index write fails is a failed read (exit 2)"
else
    fail "--take-over with a failing write: [$OUT] exit $RC"
fi

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
expect_usage "malformed --run-id" --repo o/r --head a --state open --run-id ABC
expect_usage "empty --run-id" --repo o/r --head a --state open --run-id ''
expect_usage "repeated --run-id" --repo o/r --head a --state open --run-id "$MINE" --run-id "$MINE"
expect_usage "--take-over without --run-id" --repo o/r --head a --state open --take-over
expect_usage "--take-over with --state all" --repo o/r --head a --state all --run-id "$MINE" --take-over --session execute-x
expect_usage "--take-over with --state open-else-merged" --repo o/r --head a --state open-else-merged --run-id "$MINE" --take-over --session execute-x
expect_usage "a near miss of open-else-merged" --repo o/r --head a --state open-or-merged
expect_usage "--take-over without --session" --repo o/r --head a --state open --run-id "$MINE" --take-over
expect_usage "--take-over with a session that is not a record root" --repo o/r --head a --state open --run-id "$MINE" --take-over --session scope-x
expect_usage "--session without --take-over" --repo o/r --head a --state open --run-id "$MINE" --session execute-x

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
