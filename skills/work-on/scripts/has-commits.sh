#!/usr/bin/env bash
# has-commits.sh -- for /work-on: has this run committed anything?
#
# The `has_commits` gate on `issue_type_routing` (docs route) and `scrutiny`
# (passed route) runs this. It counts the commits from `impl_base` to HEAD,
# where `impl_base` is the commit `analysis` recorded as this run's starting
# point (record-changed-paths.sh --base). That is exactly the gate's question,
# and it doesn't depend on branch names: a clone with no local `main`, a clone
# whose default branch is called something else, and a linked worktree all
# answer the same way. It also leaves out commits the run didn't make, such as
# a sibling's on a shared branch or whatever the branch started from.
#
# A missing `impl_base` fails the gate rather than guessing a base. The gate
# guards routes that must not be taken without commits, so "don't know" is a
# failure. The recovery is to record the commit the run really started from
# (the parent of its first commit) as `impl_base` and submit again; the
# issue_type_routing and scrutiny directives say so, and so does the message
# this script prints. Re-entering `analysis` doesn't help: it would record the
# current HEAD, which is already past the run's commits.
#
# Limitation, shared with record-changed-paths.sh: a rebase after `analysis`
# can leave `impl_base` off HEAD's history, and the count then includes what
# the rebase pulled in.
#
# Usage: has-commits.sh <koto-session-name>
#
# Nothing on stdout. Diagnostics go to stderr.
#
# Exit codes:
#   0  -- one or more commits in impl_base..HEAD
#   1  -- none
#   64 -- no answer: not a git repository, HEAD names no commit, impl_base is
#         unset, or impl_base is not a commit in this repository
#   67 -- the session argument is missing
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

die() {
    # $1 exit code, $2 message
    echo "has-commits: $2" >&2
    exit "$1"
}

SESSION="${1:-}"
[ -n "$SESSION" ] || die 67 "missing session argument"

git rev-parse --git-dir >/dev/null 2>&1 || die 64 "not inside a git repository"
git rev-parse --verify -q "HEAD^{commit}" >/dev/null \
    || die 64 "HEAD does not name a commit"

RECOVER="record the commit this run started from and submit again: git rev-parse <commit> | koto context add $SESSION impl_base"

# `koto context exists` exits 1, silently, for an absent key.
koto context exists "$SESSION" impl_base \
    || die 64 "impl_base is not recorded for session [$SESSION]; $RECOVER"
stored=$(koto context get "$SESSION" impl_base) \
    || die 64 "could not read impl_base for session [$SESSION]; submit again"
stored=$(printf '%s' "$stored" | tr -d '[:space:]')
[ -n "$stored" ] || die 64 "impl_base is empty for session [$SESSION]; $RECOVER"
BASE=$(git rev-parse --verify -q "${stored}^{commit}") \
    || die 64 "impl_base [$stored] is not a commit in this repository; $RECOVER"

COUNT=$(git rev-list --count "$BASE..HEAD") \
    || die 64 "could not count commits in $BASE..HEAD"
[ "$COUNT" -gt 0 ] || exit 1
exit 0
