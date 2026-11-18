# default-merge.sh: sourced, never run. Sets a merge of the default branch
# aside when a diff measures a branch's own change.
#
# A branch that merges the default branch after the commit a diff starts from
# carries everything that merge brought in, so `git diff <base> HEAD` reports
# the default branch's work as the branch's own. fold_default_merge gives the
# diff a base that already holds that merge, and the diff from it to HEAD is
# the branch's own change again.
#
# fold_default_merge <base>: sets FOLDED_BASE to the commit a diff to HEAD
# starts from, and FOLDED_DEFAULT to the default-branch commit folded into it,
# or "". The default branch is what origin/HEAD names, else origin/main; with
# neither, or no shared history with it, local main. When that branch's
# merge-base with HEAD is already in <base>, or there is none, nothing of the
# default branch came in after <base> and FOLDED_BASE is <base> itself. So it
# is when HEAD is itself in the default branch (the merge-base is HEAD): the
# work was committed there, and folding it in would hide it. Otherwise
# FOLDED_BASE is a commit whose tree is the clean merge of the two (parents
# <base> and the merge-base, a fixed author and date, so the same inputs give
# the same commit). A merge that conflicts, or that git can't build
# (merge-tree --write-tree needs git 2.38), leaves FOLDED_BASE at <base>,
# which counts what the merge brought in: never less than the branch's own
# change.
#
# review-level.sh and record-changed-paths.sh fold the same merge the same
# way, so the facts, the changed-paths record, the panel round's size and the
# review packet all measure one change.
#
# Callers run under `set -u`; the function never exits the shell and always
# returns 0.

FOLDED_BASE=""
FOLDED_DEFAULT=""

# default_merge_base: prints the merge-base of HEAD with the default branch, or
# nothing.
default_merge_base() {
    local ref="" mb=""
    ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || ref=""
    if [ -z "$ref" ] && git rev-parse --verify -q "refs/remotes/origin/main^{commit}" >/dev/null 2>&1; then
        ref=origin/main
    fi
    [ -z "$ref" ] || mb=$(git merge-base HEAD "$ref" 2>/dev/null) || mb=""
    if [ -z "$mb" ] && git rev-parse --verify -q "refs/heads/main^{commit}" >/dev/null 2>&1; then
        mb=$(git merge-base HEAD main 2>/dev/null) || mb=""
    fi
    [ -z "$mb" ] || printf '%s\n' "$mb"
    return 0
}

fold_default_merge() {
    local base="$1" mb tree commit
    FOLDED_BASE="$base"
    FOLDED_DEFAULT=""
    [ -n "$base" ] || return 0
    mb=$(default_merge_base)
    [ -n "$mb" ] || return 0
    git merge-base --is-ancestor "$mb" "$base" 2>/dev/null && return 0
    git merge-base --is-ancestor HEAD "$mb" 2>/dev/null && return 0
    tree=$(git merge-tree --write-tree "$base" "$mb" 2>/dev/null) || return 0
    commit=$(GIT_AUTHOR_NAME=work-on GIT_AUTHOR_EMAIL=work-on@localhost \
        GIT_AUTHOR_DATE='2000-01-01T00:00:00+0000' GIT_COMMITTER_NAME=work-on \
        GIT_COMMITTER_EMAIL=work-on@localhost GIT_COMMITTER_DATE='2000-01-01T00:00:00+0000' \
        git commit-tree --no-gpg-sign "$tree" -p "$base" -p "$mb" \
        -m "base with the default branch merged in" </dev/null 2>/dev/null) || return 0
    [ -n "$commit" ] || return 0
    FOLDED_BASE="$commit"
    FOLDED_DEFAULT="$mb"
    return 0
}
