#!/usr/bin/env bash
# default-merge_test.sh: tests for scripts/lib/default-merge.sh's
# fold_default_merge, the base a diff measures a branch's own change from
# when the branch merged the default branch after it.
#
# Usage: bash scripts/lib/default-merge_test.sh
#
# Builds throwaway git repositories under a temporary directory and touches
# nothing else: no network, no koto.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=default-merge.sh
. "$HERE/default-merge.sh"

PASS_COUNT=0
FAIL_COUNT=0
ok() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
bad() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $1"; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/default-merge-test.XXXXXX") || exit 1
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global user.name t
git config --global user.email t@example.com
git config --global init.defaultBranch main
git config --global commit.gpgsign false

# repo <name>: a repository with main at one commit and a branch `work` with
# one commit of its own; sets R and BASE (main's commit, where work forked).
repo() {
    R="$ROOT/$1"
    git init -q "$R"
    (cd "$R" && seq 1 10 > a.txt && git add a.txt && git commit -q -m init) || exit 1
    BASE=$(git -C "$R" rev-parse HEAD)
    (cd "$R" && git checkout -q -b work && echo own > own.txt && git add own.txt && git commit -q -m own) || exit 1
}

# main_moves <file>: main commits 300 lines to <file>.
main_moves() {
    (cd "$R" && git checkout -q main && seq 1 300 > "$1" && git add "$1" && git commit -q -m main-moves \
        && git checkout -q work) >/dev/null 2>&1
}

# own_paths <base>: the paths the diff from <base> to HEAD names, one line.
own_paths() {
    git -C "$R" diff --name-only "$1" HEAD | tr '\n' ' '
}

fold() {
    (cd "$R" && fold_default_merge "$1" && printf '%s %s\n' "$FOLDED_BASE" "$FOLDED_DEFAULT")
}

# No merge of main: the base stands.
repo plain
main_moves docs.md
read -r fb fd <<<"$(fold "$BASE")"
[ "$fb" = "$BASE" ] && [ -z "${fd:-}" ] \
    && ok "main moved but was not merged: the base stands" || bad "unmerged: [$fb] [${fd:-}]"

# A merge of main after the base: folded, and the diff is the branch's own.
repo merged
main_moves docs.md
(cd "$R" && git merge -q --no-ff --no-edit main && echo more >> own.txt && git commit -q -am more) >/dev/null 2>&1
MAIN_TIP=$(git -C "$R" rev-parse main)
read -r fb fd <<<"$(fold "$BASE")"
[ "$fb" != "$BASE" ] && [ "${fd:-}" = "$MAIN_TIP" ] \
    && ok "a merge of main after the base: folded, naming main's commit" || bad "merged: [$fb] [${fd:-}]"
[ "$(cd "$R" && own_paths "$fb")" = "own.txt " ] \
    && ok "a merge of main after the base: the diff from the fold is the branch's own" \
    || bad "merged paths: [$(cd "$R" && own_paths "$fb")]"
[ "$(cd "$R" && own_paths "$BASE")" = "docs.md own.txt " ] \
    && ok "a merge of main after the base: the raw base still counts main's file (the bug's shape)" \
    || bad "raw paths: [$(cd "$R" && own_paths "$BASE")]"
read -r fb2 _ <<<"$(fold "$BASE")"
[ "$fb2" = "$fb" ] && ok "the fold is the same commit on the same inputs" || bad "fold not stable: $fb vs $fb2"

# A base that already holds the merged main stands.
MERGE=$(git -C "$R" rev-parse HEAD~1)
read -r fb fd <<<"$(fold "$MERGE")"
[ "$fb" = "$MERGE" ] && [ -z "${fd:-}" ] \
    && ok "a base past the merge: the base stands" || bad "past merge: [$fb] [${fd:-}]"

# origin/main is preferred over local main when it exists.
repo origin
main_moves docs.md
(cd "$R" && git update-ref refs/remotes/origin/main main && git merge -q --no-ff --no-edit main) >/dev/null 2>&1
(cd "$R" && git checkout -q main && git reset -q --hard "$BASE" && git checkout -q work) >/dev/null 2>&1
read -r fb fd <<<"$(fold "$BASE")"
[ "${fd:-}" = "$(git -C "$R" rev-parse origin/main)" ] && [ "$(cd "$R" && own_paths "$fb")" = "own.txt " ] \
    && ok "origin/main is read before local main" || bad "origin: [$fb] [${fd:-}]"

# HEAD on the default branch itself: folding would hide the work.
repo onmain
(cd "$R" && git checkout -q main && git merge -q --ff-only work) >/dev/null 2>&1
read -r fb fd <<<"$(fold "$BASE")"
[ "$fb" = "$BASE" ] && [ -z "${fd:-}" ] \
    && ok "HEAD in the default branch: the base stands" || bad "on main: [$fb] [${fd:-}]"

# A merge that conflicts with the base: the base stands, counting what the
# merge brought in. The base is the branch's own commit (a panel's last head),
# which edits the file main then edits too.
repo conflict
OWN=$(git -C "$R" rev-parse work)
(cd "$R" && git checkout -q main && echo main-side > own.txt && git add own.txt && git commit -q -m clash \
    && git checkout -q work && { git merge -q --no-edit main || true; } && git checkout -q --ours own.txt \
    && git add own.txt && git commit -q --no-edit) >/dev/null 2>&1
read -r fb fd <<<"$(fold "$OWN")"
[ "$fb" = "$OWN" ] && [ -z "${fd:-}" ] \
    && ok "a conflicting merge: the base stands" || bad "conflict: [$fb] [${fd:-}]"

# No default branch at all, and an empty base.
repo nomain
(cd "$R" && git branch -q -m main trunk) >/dev/null 2>&1
read -r fb fd <<<"$(fold "$BASE")"
[ "$fb" = "$BASE" ] && [ -z "${fd:-}" ] && ok "no default branch: the base stands" || bad "no main: [$fb] [${fd:-}]"
read -r fb fd <<<"$(fold "")"
[ -z "${fb:-}" ] && [ -z "${fd:-}" ] && ok "an empty base stays empty" || bad "empty: [${fb:-}] [${fd:-}]"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
