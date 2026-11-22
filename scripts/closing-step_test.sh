#!/usr/bin/env bash
# closing-step_test.sh -- scripts/closing-step.sh against a throwaway instance:
# a clone pushed to a local bare remote, plus a linked worktree of it.
#
# Covers: a stray untracked file, one in a new directory, and an ignored one
# (not stray); an unpushed commit; a branch with no upstream; a detached HEAD;
# the pass once both are resolved, with the instance root, the worktree still
# there at the pushed head, and done=yes only from outside the worktree; the
# instance root of a linked worktree and from --instance; a repository's
# core.fsmonitor and hooks never running; and exit 2 with git off PATH or a
# directory that is no work tree.
#
# Usage: bash scripts/closing-step_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/closing-step.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/closing-step-test.XXXXXX") || exit 1
trap 'case "$T" in */closing-step-test.*) rm -rf "$T" ;; esac' EXIT
T=$(cd "$T" && pwd -P) || exit 1
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "$2 :: rc=${rc-} out=${OUT-}"; fi; }

export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_DIR GIT_WORK_TREE
mkdir -p "$HOME" "$T/inst" "$T/bin-nogit" || exit 1
INST="$T/inst"
REPO="$INST/repo"
git init -q --bare -b main "$T/remote.git" || exit 1
git init -q -b main "$REPO" || exit 1
git -C "$REPO" remote add origin "$T/remote.git" || exit 1
printf 'ignored.log\n' >"$REPO/.gitignore"
printf 'one\n' >"$REPO/a.txt"
git -C "$REPO" add -A || exit 1
git -C "$REPO" commit -q -m first || exit 1
git -C "$REPO" push -q -u origin main || exit 1

run() { (cd "${RUN_CWD:-$T}" && bash "$SCRIPT" "$@"); }

echo "== a clean, pushed worktree passes =="
OUT=$(run "$REPO" 2>&1); rc=$?
check "exit 0" '[ "$rc" -eq 0 ]'
check "closing=pass" 'grep -qx "closing=pass" <<<"$OUT"'
check "instance root is the directory above the repository" 'grep -qx "instance=$INST" <<<"$OUT"'
check "done=yes from outside the worktree" 'grep -qx "done=yes" <<<"$OUT"'

echo "== an ignored file is not stray =="
: >"$REPO/ignored.log"
OUT=$(run "$REPO" 2>&1); rc=$?
check "exit 0 with an ignored file" '[ "$rc" -eq 0 ]'

echo "== a stray file blocks =="
printf 'stray\n' >"$REPO/stray.txt"
mkdir -p "$REPO/newdir"
printf 'deep\n' >"$REPO/newdir/deep file.txt"
OUT=$(run "$REPO" 2>&1); rc=$?
check "exit 1" '[ "$rc" -eq 1 ]'
check "closing=blocked first" '[ "${OUT%%$'"'"'\n'"'"'*}" = closing=blocked ]'
check "names the stray file" 'grep -qx "stray: stray.txt" <<<"$OUT"'
check "names a file in a new directory by its full path" 'grep -qx "stray: newdir/deep file.txt" <<<"$OUT"'
check "does not name the ignored file" '! grep -q "ignored.log" <<<"$OUT"'
rm -rf "$REPO/stray.txt" "$REPO/newdir"

echo "== an unpushed commit blocks =="
printf 'two\n' >>"$REPO/a.txt"
git -C "$REPO" commit -q -am second || exit 1
SECOND=$(git -C "$REPO" rev-parse HEAD)
OUT=$(run "$REPO" 2>&1); rc=$?
check "exit 1" '[ "$rc" -eq 1 ]'
check "closing=blocked" 'grep -qx "closing=blocked" <<<"$OUT"'
check "names the unpushed commit" 'grep -qx "unpushed: $SECOND second" <<<"$OUT"'

echo "== stray file and unpushed commit together, then resolved =="
printf 'stray\n' >"$REPO/stray.txt"
OUT=$(run "$REPO" 2>&1); rc=$?
check "exit 1 naming both" '[ "$rc" -eq 1 ] && grep -qx "stray: stray.txt" <<<"$OUT" && grep -q "^unpushed: $SECOND" <<<"$OUT"'
rm -f "$REPO/stray.txt"
git -C "$REPO" push -q origin main || exit 1
OUT=$(run "$REPO" 2>&1); rc=$?
check "exit 0 once both are resolved" '[ "$rc" -eq 0 ] && grep -qx "closing=pass" <<<"$OUT"'
check "the worktree still exists at the pushed head" \
    '[ -d "$REPO" ] && [ "$(git -C "$REPO" rev-parse HEAD)" = "$(git --git-dir="$T/remote.git" rev-parse main)" ]'

echo "== done only from outside the worktree =="
OUT=$(RUN_CWD="$REPO" run "$REPO" 2>"$T/err"); rc=$?
check "exit 0, done=no from inside the worktree" '[ "$rc" -eq 0 ] && grep -qx "done=no" <<<"$OUT" && ! grep -q "done=yes" <<<"$OUT"'
check "says where to move" 'grep -q "cd $INST" "$T/err"'
OUT=$(RUN_CWD="$INST" run "$REPO" 2>&1); rc=$?
check "done=yes from the instance root" '[ "$rc" -eq 0 ] && grep -qx "done=yes" <<<"$OUT"'

echo "== no upstream, detached HEAD =="
git -C "$REPO" checkout -q -b topic || exit 1
OUT=$(run "$REPO" 2>&1); rc=$?
check "a branch with no upstream blocks" '[ "$rc" -eq 1 ] && grep -qx "closing=blocked" <<<"$OUT" && grep -q "^no-upstream: topic" <<<"$OUT"'
git -C "$REPO" checkout -q --detach || exit 1
OUT=$(run "$REPO" 2>&1); rc=$?
check "a detached HEAD blocks" '[ "$rc" -eq 1 ] && grep -q "^detached: " <<<"$OUT"'
git -C "$REPO" checkout -q main || exit 1

echo "== a linked worktree, and --instance =="
git -C "$REPO" worktree add -q -b wt-branch "$INST/.wt/linked" || exit 1
git -C "$INST/.wt/linked" push -q -u origin wt-branch || exit 1
OUT=$(run "$INST/.wt/linked" 2>&1); rc=$?
check "a linked worktree's instance root is above the main checkout" '[ "$rc" -eq 0 ] && grep -qx "instance=$INST" <<<"$OUT"'
mkdir -p "$T/other-root"
OUT=$(run "$REPO" --instance "$T/other-root" 2>&1); rc=$?
check "--instance is the root printed" '[ "$rc" -eq 0 ] && grep -qx "instance=$T/other-root" <<<"$OUT"'
OUT=$(run "$REPO" --instance "$T/nope" 2>&1); rc=$?
check "--instance that is no directory exits 2" '[ "$rc" -eq 2 ]'

echo "== the repository's own configuration runs nothing =="
git -C "$REPO" config core.fsmonitor "$T/fsmonitor.sh"
printf '#!/bin/sh\n: >"%s/fsmonitor-ran"\n' "$T" >"$T/fsmonitor.sh"
chmod +x "$T/fsmonitor.sh"
OUT=$(run "$REPO" 2>&1); rc=$?
check "core.fsmonitor did not run" '[ "$rc" -eq 0 ] && [ ! -e "$T/fsmonitor-ran" ]'
git -C "$REPO" config --unset core.fsmonitor

echo "== environment faults exit 2 =="
OUT=$(cd "$T" && PATH="$T/bin-nogit" "$BASH" "$SCRIPT" "$REPO" 2>&1); rc=$?
check "git not on PATH exits 2" '[ "$rc" -eq 2 ]'
mkdir -p "$T/plain"
OUT=$(run "$T/plain" 2>&1); rc=$?
check "a directory outside any work tree exits 2" '[ "$rc" -eq 2 ]'
OUT=$(run "$T/missing" 2>&1); rc=$?
check "a missing directory exits 2" '[ "$rc" -eq 2 ]'
OUT=$(run 2>&1); rc=$?
check "no worktree named exits 2" '[ "$rc" -eq 2 ]'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
