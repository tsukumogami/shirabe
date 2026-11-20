# shellcheck shell=bash
# default-remote-ref.sh -- the remote ref of a clone's default branch.
#
# Sourced, never run. Defines one function:
#
#   default_remote_ref <dir>
#       Prints the full name of the remote-tracking ref for origin's default
#       branch, for the clone <dir> is in:
#         1. the target of the refs/remotes/origin/HEAD symref, when it is set
#            and names a ref that exists;
#         2. else refs/remotes/origin/main, when it exists;
#         3. else nothing, and returns 1.
#       It never names a local branch: a clone whose remote refs are missing has
#       no answer, rather than one a branch's own commits could move.
#
# The build-output cleanup's ancestry check and every pin of a base the
# cleanup later reads resolve the ref through this one function, so they can't
# disagree about which branch is the default.
#
# Written for the bash 3.2 floor.

default_remote_ref() {
    local dir="$1" target
    [ -n "$dir" ] || return 1
    target=$(git -C "$dir" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null)
    case "$target" in
        refs/remotes/origin/?*)
            if git -C "$dir" show-ref --verify -q "$target" 2>/dev/null; then
                printf '%s\n' "$target"
                return 0
            fi
            ;;
    esac
    if git -C "$dir" show-ref --verify -q refs/remotes/origin/main 2>/dev/null; then
        printf '%s\n' refs/remotes/origin/main
        return 0
    fi
    return 1
}
