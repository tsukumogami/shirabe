#!/usr/bin/env bash
# default-remote-ref_test.sh -- default_remote_ref names origin's default
# branch as a remote-tracking ref, and never a local branch.
#
# Covers: a clone whose default is master, with origin/HEAD set; origin/HEAD
# unset with origin/main present; origin/HEAD naming a ref that's gone, which
# falls back to origin/main; a single-branch clone with neither ref (exit 1,
# nothing printed); a repository with a local main and no remote at all
# (exit 1); a directory that isn't a repository (exit 1).
#
# Usage: bash scripts/lib/default-remote-ref_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }
# shellcheck source=default-remote-ref.sh
. "$HERE/default-remote-ref.sh"

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

W=$(mktemp -d) || { echo "FAIL: could not create a temporary directory"; exit 1; }
trap 'rm -rf "$W"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# An origin whose default branch is master, with a second branch.
git init -q -b master "$W/origin-master"
git -C "$W/origin-master" commit -q --allow-empty -m one
git -C "$W/origin-master" branch feature
git clone -q "$W/origin-master" "$W/clone-master"
eq "a master default with origin/HEAD set" "refs/remotes/origin/master" "$(default_remote_ref "$W/clone-master")"
default_remote_ref "$W/clone-master" >/dev/null; eq "a master default: exit 0" 0 $?

# origin/HEAD unset, origin/main present.
git init -q -b main "$W/origin-main"
git -C "$W/origin-main" commit -q --allow-empty -m one
git clone -q "$W/origin-main" "$W/clone-main"
git -C "$W/clone-main" remote set-head origin -d
eq "origin/HEAD unset falls back to origin/main" "refs/remotes/origin/main" "$(default_remote_ref "$W/clone-main")"

# origin/HEAD pointing at a ref that no longer exists.
git -C "$W/clone-main" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
eq "a dangling origin/HEAD falls back to origin/main" "refs/remotes/origin/main" "$(default_remote_ref "$W/clone-main")"

# A single-branch clone of a branch that isn't the default: neither ref.
git clone -q --single-branch --branch feature "$W/origin-master" "$W/clone-single"
git -C "$W/clone-single" remote set-head origin -d >/dev/null 2>&1
out=$(default_remote_ref "$W/clone-single"); rc=$?
eq "a single-branch clone with neither ref: exit 1" 1 "$rc"
eq "a single-branch clone with neither ref prints nothing" "" "$out"

# A local main and no remote: never a local branch.
git init -q -b main "$W/local"
git -C "$W/local" commit -q --allow-empty -m one
out=$(default_remote_ref "$W/local"); rc=$?
eq "a local main with no remote: exit 1" 1 "$rc"
eq "a local main with no remote prints nothing" "" "$out"

mkdir "$W/plain"
default_remote_ref "$W/plain" >/dev/null 2>&1; eq "not a repository: exit 1" 1 $?

echo
echo "default-remote-ref: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
