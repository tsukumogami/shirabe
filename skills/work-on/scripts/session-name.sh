#!/usr/bin/env bash
# session-name.sh -- the koto session name of an issue-backed /work-on run:
# `<WF>` in SKILL.md.
#
# Usage:
#   session-name.sh <N> [<owner/repo>]
#
# Prints `issue_<N>.<owner>.<repo>`, lowercased, and exits 0. The repository is
# <owner/repo> when it is given and not empty (the run's ISSUE_REPO), and
# otherwise the one the current directory's `origin` remote names.
#
# Why the repository is in the name: an issue number alone is not unique on a
# host that works across several repositories. With the name `issue_<N>`, a
# run for issue 750 in one repository was refused because a run for issue 750
# in another held the name, and SKILL.md's Resume would have matched that
# other run as its own (#1842). The name is the only thing koto keys a session
# on, so it has to carry the repository.
#
# Why `.` separates: GitHub owner names can't contain a dot, so the first dot
# after the number always ends the owner, and two repositories never map to
# one name. A `-` would not do, since both parts can contain it (`a-b/c` and
# `a/b-c`). Repository names may contain dots; they come last, so they are
# never mistaken for the separator. Lowercasing folds the case GitHub ignores,
# so `Acme/Tools` and `acme/tools` give one name.
#
# The result always meets koto's rule for a workflow name: it starts with a
# letter, uses only letters, digits, `.`, `_` and `-`, has no `~`, and stays
# far under 255 bytes (an owner is at most 39 characters and a repository at
# most 100).
#
# ARTIFACT_PREFIX is not this name. It stays `issue_<N>`: it names context
# keys and branches inside the one repository, and a request leg can pin it.
#
# Refusals, each with exit 64, a message on stderr and nothing on stdout:
#   - <N> is not a positive issue number;
#   - <owner/repo> is given but isn't owner/repo as GitHub allows it;
#   - no repository was given and the current directory has no `origin`
#     remote, or one whose URL names no owner/repo.
# There is no fallback to the bare `issue_<N>`: that name is the collision
# this script exists to remove.
#
# Origin URLs are read the way test-change.sh reads them: a trailing `.git` is
# dropped and the last two path segments are the owner and repository, which
# covers https://host/owner/repo, ssh://git@host/owner/repo and the scp-style
# git@host:owner/repo.
#
# Requires: bash 3.2+, git (only when no repository is given).
set -uo pipefail

PROG=session-name

refuse() {
    echo "$PROG: $*" >&2
    exit 64
}

RE_NUM='^[1-9][0-9]{0,9}$'
RE_OWNER='^[A-Za-z0-9][A-Za-z0-9-]{0,38}$'
RE_REPO='^[A-Za-z0-9._-]{1,100}$'

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || refuse "usage: session-name.sh <N> [<owner/repo>]"
NUM="$1"
REPO="${2:-}"

[[ "$NUM" =~ $RE_NUM ]] || refuse "the issue number must be a positive integer, got [$NUM]"

FROM="the repository given"
if [ -z "$REPO" ]; then
    FROM="origin"
    URL=$(git remote get-url origin 2>/dev/null) \
        || refuse "no repository was given and this directory has no origin remote; pass <owner/repo>"
    REPO=$(printf '%s' "$URL" | sed -E 's#\.git$##; s#^.*[:/]([^/:]+/[^/:]+)$#\1#')
fi

case "$REPO" in
    */*/*|*/) refuse "$FROM is not owner/repo: [$REPO]" ;;
    */*) ;;
    *) refuse "$FROM is not owner/repo: [$REPO]" ;;
esac
OWNER="${REPO%%/*}"
NAME="${REPO#*/}"
[[ "$OWNER" =~ $RE_OWNER ]] || refuse "$FROM has an owner GitHub would not allow: [$OWNER]"
[[ "$NAME" =~ $RE_REPO ]] && [ "$NAME" != . ] && [ "$NAME" != .. ] \
    || refuse "$FROM has a repository name GitHub would not allow: [$NAME]"

printf 'issue_%s.%s.%s\n' "$NUM" "$(printf '%s' "$OWNER" | LC_ALL=C tr 'A-Z' 'a-z')" \
    "$(printf '%s' "$NAME" | LC_ALL=C tr 'A-Z' 'a-z')"
