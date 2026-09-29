#!/usr/bin/env bash
# github-refs.sh -- the one read of a GitHub repository's live refs.
#
# Both instance inventories (reconcile-check.sh's and teardown-inventory.sh's)
# and reconcile's branch check read a repository's refs through this script,
# so a private repository reads the same way in all three.
#
# The read is `git ls-remote --symref` against
# https://github.com/<owner/repo>.git, run from / so no repository's config
# applies, the caller's included, and under the coordinator's own git config:
# nothing a worker's clone configured (a URL rewrite, a transport, a
# credential helper) runs. It authenticates with the gh login, the channel
# every other GitHub read of /coordinate's already uses: `gh auth
# git-credential` is the only credential helper, the coordinator's own
# helpers are cleared, and git never prompts. So a private repository the gh
# login can read is read on a host with no https credential helper, and a
# public one reads as before. A read that can't authenticate fails at once
# with git's own reason on stderr, rather than waiting on a prompt.
#
# https reads GitHub; file lets a URL the coordinator's own config rewrites
# point at a local repository, and runs nothing. No other transport runs.
#
# The script ends by exec'ing git, so a caller's deadline that stops this
# process stops the read itself.
#
# Usage: github-refs.sh [--gh <gh command>] <owner/repo> [<pattern>...]
#   --gh  the gh to authenticate with (default: gh on PATH)
#
# Output: ls-remote's own lines, limited to the patterns when given.
# Exit codes: git's; 64 usage (including a repository that isn't owner/repo).
#
# Requires: bash 3.2+, git, gh.
set -uo pipefail

usage() { printf 'usage: github-refs.sh [--gh <gh command>] <owner/repo> [<pattern>...]\n' >&2; exit 64; }

GH_CMD=gh
if [ "${1-}" = --gh ]; then
    [ $# -ge 2 ] && [ -n "$2" ] || usage
    GH_CMD=$2
    shift 2
fi
[ $# -ge 1 ] || usage
REPO=$1
shift
printf '%s' "$REPO" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || usage
case "/$REPO/" in */./* | */../* | /-*) usage ;; esac
for p in "$@"; do case "$p" in -*) usage ;; esac; done

HELPER="!$(printf '%q' "$GH_CMD") auth git-credential"
export GIT_ALLOW_PROTOCOL=https:file GIT_TERMINAL_PROMPT=0 GIT_ASKPASS= SSH_ASKPASS= GIT_NO_LAZY_FETCH=1
exec git --no-optional-locks -c core.fsmonitor= -c core.hooksPath=/dev/null -c protocol.allow=never -C / \
    -c protocol.https.allow=always -c protocol.file.allow=always \
    -c core.askPass= -c credential.interactive=false \
    -c credential.helper= -c credential.https://github.com.helper= \
    -c "credential.helper=$HELPER" \
    ls-remote --symref "https://github.com/$REPO.git" "$@"
