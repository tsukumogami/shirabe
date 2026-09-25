#!/usr/bin/env bash
# check-upstream.sh -- the working-tree checks on /scope's --upstream value.
#
# koto has already refused a value of the wrong shape at `koto init`: UPSTREAM
# is constrained to empty, a repository-relative docs/roadmaps/.../ROADMAP-*.md
# path, or `owner/repo:` followed by one, never with a `..` segment. What a
# pattern cannot see is the file the value names, and that is what this script
# checks, from the repository root it runs in:
#
#   upstream-outside    the path, symlinks followed, leaves the repository,
#                       or does not land under <repo-root>/docs/roadmaps/
#   upstream-wip        the path, symlinks followed, lands under
#                       <repo-root>/wip/, which the wip-hygiene cleanup deletes
#   upstream-basename   the resolved file's basename does not start with
#                       ROADMAP-
#   upstream-untracked  the file does not exist or git does not track it
#
# They run in that order and the first that fires is the one reported, so a
# symlink into wip/ reads as upstream-wip rather than as a confinement failure.
# A cross-repo value (`owner/repo:path`) names no file here: only the
# basename check applies to it. The visibility check (a private upstream named
# from a public repo) omits the value rather than refusing the run, so it stays
# with Phase 0 and is not in this script.
#
# Usage:
#   check-upstream.sh --upstream <value>
#
# Output and exit codes:
#   0  the value passes, or is empty; nothing on stdout
#   1  refused; stdout carries exactly one line, the reason above
#   2  cannot tell: a usage error, or git could not name the repository root.
#      Nothing on stdout.
#
# Read-only: it reads the working tree and git's index and writes nothing.
# bash 3.2.

set -uo pipefail

PROG=check-upstream.sh

die() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 2
}

refuse() {
    printf '%s\n' "$1"
    exit 1
}

VALUE=""
SEEN=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --upstream)
            [ "$#" -ge 2 ] || die "--upstream requires a value (it may be empty)"
            [ "$SEEN" -eq 0 ] || die "--upstream given more than once"
            VALUE="$2"; SEEN=1; shift ;;
        --upstream=*)
            [ "$SEEN" -eq 0 ] || die "--upstream given more than once"
            VALUE="${1#--upstream=}"; SEEN=1 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done
[ "$SEEN" -eq 1 ] || die "--upstream is required"

[ -n "$VALUE" ] || exit 0

# A cross-repo value: `owner/repo:path`. Not resolved against this working
# tree at all; its file component still has to be a roadmap.
RE_CROSS='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+:'
if [[ "$VALUE" =~ $RE_CROSS ]]; then
    FILE_PART="${VALUE#*:}"
    case "${FILE_PART##*/}" in
        ROADMAP-*) exit 0 ;;
        *) refuse upstream-basename ;;
    esac
fi

# resolve_path <path> -- the physical absolute path, symlinks on the file and
# on every directory above it followed. Fails when the directory does not
# exist or a symlink chain loops.
resolve_path() {
    local p="$1" d b t n=0
    while [ -L "$p" ]; do
        n=$((n + 1))
        [ "$n" -le 40 ] || return 1
        t=$(readlink -- "$p") || return 1
        case "$t" in
            /*) p="$t" ;;
            *) p="$(dirname -- "$p")/$t" ;;
        esac
    done
    d=$(dirname -- "$p")
    b=$(basename -- "$p")
    d=$(cd -P -- "$d" 2>/dev/null && pwd -P) || return 1
    case "$b" in
        .|..) d=$(cd -P -- "$d/$b" 2>/dev/null && pwd -P) || return 1; printf '%s' "$d"; return 0 ;;
    esac
    if [ "$d" = "/" ]; then
        printf '/%s' "$b"
    else
        printf '%s/%s' "$d" "$b"
    fi
}

TOP=$(git rev-parse --show-toplevel) || die "not inside a git work tree"
[ -n "$TOP" ] || die "git named no repository root"
TOP=$(cd -P -- "$TOP" 2>/dev/null && pwd -P) || die "the repository root cannot be entered"

case "$VALUE" in
    /*) CANDIDATE="$VALUE" ;;
    *) CANDIDATE="$TOP/$VALUE" ;;
esac

if [ ! -e "$CANDIDATE" ]; then
    # Nothing to follow. A missing file is not a tracked file.
    refuse upstream-untracked
fi

RESOLVED=$(resolve_path "$CANDIDATE") || refuse upstream-outside

case "$RESOLVED" in
    "$TOP"/*) ;;
    *) refuse upstream-outside ;;
esac

case "$RESOLVED" in
    "$TOP"/wip/*) refuse upstream-wip ;;
esac

case "${RESOLVED##*/}" in
    ROADMAP-*) ;;
    *) refuse upstream-basename ;;
esac

case "$RESOLVED" in
    "$TOP"/docs/roadmaps/*) ;;
    *) refuse upstream-outside ;;
esac

[ -f "$RESOLVED" ] || refuse upstream-untracked

REL="${RESOLVED#"$TOP"/}"
TRACKED=$(git -C "$TOP" ls-files -- "$REL") || die "git ls-files failed for $REL"
[ -n "$TRACKED" ] || refuse upstream-untracked

exit 0
