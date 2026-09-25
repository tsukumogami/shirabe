#!/usr/bin/env bash
# push-and-record_test.sh — the push writes the expected-head record, and
# nothing else does
# Part of the execute skill
#
# push-and-record.sh pushes the current branch and, only after the push
# succeeds, writes `git rev-parse HEAD` into the session's `expected_head`
# context key. The cases run real git against a local bare origin and a `koto`
# stub on PATH that logs every call and the bytes piped to it, so they need no
# network and no workflow engine:
#
#   success              pushed, recorded exactly the 40-char sha, printed it
#   push failure         the remote rejects: exit 68, nothing recorded
#   detached HEAD        exit 65, no push, nothing recorded
#   the default branch   exit 67, no push, nothing recorded
#   no symref answer     main is still refused
#   bad branch name      exit 66
#   invalid session      exit 64, no git push, nothing recorded
#   koto write failure   exit 70 after a real push
#   no force option, and the refspec is explicit (static)
#
# Usage: push-and-record_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PAR="$SCRIPT_DIR/push-and-record.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$PAR" ] || { echo "FAIL: $PAR not found" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/push-and-record-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN"

# koto stub: logs "<args>|<stdin>" per call; KOTO_FAIL=1 makes it fail.
cat > "$BIN/koto" <<'STUB'
#!/usr/bin/env bash
data=""
[ -t 0 ] || data=$(cat)
printf '%s|%s\n' "$*" "$data" >> "${KOTO_LOG:?}"
[ "${KOTO_FAIL:-0}" = 1 ] && { echo "koto stub: refused" >&2; exit 3; }
exit 0
STUB
chmod +x "$BIN/koto"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# fixture <name> — a bare origin whose default branch is main, and a clone of
# it on a feature branch with one new commit.
fixture() {
    FX="$WORK/$1"
    rm -rf "$FX"; mkdir -p "$FX"
    git init -q --bare "$FX/origin.git"
    git -C "$FX/origin.git" symbolic-ref HEAD refs/heads/main
    git init -q "$FX/repo"
    (
        cd "$FX/repo" || exit 1
        git checkout -q -b main
        git commit -q --allow-empty -m init
        git remote add origin "$FX/origin.git"
        git push -q origin main 2>/dev/null
        git checkout -q -b impl/topic
        git commit -q --allow-empty -m work
    )
    KOTO_LOG="$FX/koto.log"
    : > "$KOTO_LOG"
}

run() { # run <args...> — in the fixture repo
    OUT=$(cd "$FX/repo" && KOTO_LOG="$KOTO_LOG" PATH="$BIN:$PATH" bash "$PAR" "$@" 2>"$FX/stderr")
    RC=$?
    ERR=$(cat "$FX/stderr")
}

remote_sha() { git -C "$FX/origin.git" rev-parse --verify --quiet "refs/heads/$1" 2>/dev/null; }

# --- success -----------------------------------------------------------------

fixture ok
HEAD_SHA=$(git -C "$FX/repo" rev-parse HEAD)
run execute-topic
if [ "$RC" -eq 0 ] && [ "$OUT" = "$HEAD_SHA" ] && [ "$(remote_sha impl/topic)" = "$HEAD_SHA" ]; then
    pass "success: the branch is pushed and the sha is printed"
else
    fail "success: exit $RC, out [$OUT], remote [$(remote_sha impl/topic)], stderr $ERR"
fi
if [ "$(cat "$KOTO_LOG")" = "context add execute-topic expected_head|$HEAD_SHA" ]; then
    pass "success: expected_head is recorded as exactly the pushed sha, with no newline"
else
    fail "success: koto saw [$(cat "$KOTO_LOG")]"
fi
if [ "$(git -C "$FX/repo" config branch.impl/topic.merge)" = "refs/heads/impl/topic" ]; then
    pass "success: the upstream is set, as the old git push -u did"
else
    fail "success: branch.impl/topic.merge is [$(git -C "$FX/repo" config branch.impl/topic.merge)]"
fi

# --- push failure ------------------------------------------------------------

fixture rejected
printf '#!/bin/sh\necho "rejected by hook" >&2\nexit 1\n' > "$FX/origin.git/hooks/pre-receive"
chmod +x "$FX/origin.git/hooks/pre-receive"
run execute-topic
if [ "$RC" -eq 68 ] && [ -z "$OUT" ] && [ ! -s "$KOTO_LOG" ] && [ -z "$(remote_sha impl/topic)" ]; then
    pass "push failure: exit 68 and nothing recorded"
else
    fail "push failure: exit $RC, out [$OUT], koto [$(cat "$KOTO_LOG")]"
fi

# --- detached HEAD -------------------------------------------------------------

fixture detached
git -C "$FX/repo" checkout -q --detach
run execute-topic
if [ "$RC" -eq 65 ] && [ ! -s "$KOTO_LOG" ] && [ -z "$(remote_sha impl/topic)" ]; then
    pass "detached HEAD: exit 65, nothing pushed, nothing recorded"
else
    fail "detached HEAD: exit $RC, koto [$(cat "$KOTO_LOG")]"
fi

# --- the default branch --------------------------------------------------------

fixture default
git -C "$FX/repo" checkout -q main
git -C "$FX/repo" commit -q --allow-empty -m "on main"
BEFORE=$(remote_sha main)
run execute-topic
if [ "$RC" -eq 67 ] && [ ! -s "$KOTO_LOG" ] && [ "$(remote_sha main)" = "$BEFORE" ]; then
    pass "default branch: exit 67, main is not pushed, nothing recorded"
else
    fail "default branch: exit $RC, koto [$(cat "$KOTO_LOG")]"
fi

# A remote that answers no symref (an unreachable URL) still refuses main.
fixture no-symref
git -C "$FX/repo" checkout -q main
git -C "$FX/repo" remote set-url origin "$FX/does-not-exist.git"
run execute-topic
if [ "$RC" -eq 67 ] && [ ! -s "$KOTO_LOG" ]; then
    pass "no symref answer: main is still refused"
else
    fail "no symref answer: exit $RC"
fi

# A default branch other than main is read from the remote.
fixture trunk
git -C "$FX/repo" push -q origin main:refs/heads/trunk 2>/dev/null
git -C "$FX/origin.git" symbolic-ref HEAD refs/heads/trunk
git -C "$FX/repo" checkout -q -b trunk
run execute-topic
if [ "$RC" -eq 67 ]; then
    pass "the remote's own default branch (trunk) is refused"
else
    fail "trunk: exit $RC"
fi

# --- a refused branch name -----------------------------------------------------

fixture badname
git -C "$FX/repo" checkout -q -b 'feat/a+b'
run execute-topic
if [ "$RC" -eq 66 ] && [ ! -s "$KOTO_LOG" ]; then
    pass "a branch name outside the pattern: exit 66"
else
    fail "bad branch name: exit $RC"
fi

# --- invalid session name ------------------------------------------------------

for bad in '' '-x' 'a b' 'a;b' '../x'; do
    fixture badsession
    run "$bad"
    if [ "$RC" -eq 64 ] && [ ! -s "$KOTO_LOG" ] && [ -z "$(remote_sha impl/topic)" ]; then
        pass "invalid session name [$bad]: exit 64, nothing pushed or recorded"
    else
        fail "invalid session name [$bad]: exit $RC, remote [$(remote_sha impl/topic)]"
    fi
done

fixture toomany
run a b c
[ "$RC" -eq 64 ] && pass "three arguments: exit 64" || fail "three arguments: exit $RC"

# --- a failing record after a real push --------------------------------------

fixture kotofail
OUT=$(cd "$FX/repo" && KOTO_FAIL=1 KOTO_LOG="$KOTO_LOG" PATH="$BIN:$PATH" bash "$PAR" execute-topic 2>/dev/null)
RC=$?
if [ "$RC" -eq 70 ] && [ -z "$OUT" ]; then
    pass "koto write failure after the push: exit 70, nothing on stdout"
else
    fail "koto write failure: exit $RC, out [$OUT]"
fi

# --- static: no force, an explicit refspec ------------------------------------

CODE=$(grep -v '^[[:space:]]*#' "$PAR")
if printf '%s' "$CODE" | grep -Eq -- '--force|--force-with-lease| -f |"\+'; then
    fail "push-and-record.sh carries a force option"
else
    pass "no force option anywhere in the script"
fi
if printf '%s' "$CODE" | grep -q 'git push --set-upstream "$REMOTE" "HEAD:refs/heads/$BRANCH"'; then
    pass "the push names the explicit HEAD:refs/heads/<branch> refspec"
else
    fail "the push is not the explicit-refspec form"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
