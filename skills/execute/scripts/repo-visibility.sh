#!/usr/bin/env bash
# repo-visibility.sh — for /execute's coordinated path: read the visibility
# the Coordination-PR Visibility Rule turns on, live from GitHub.
#
# Two uses.
#
#   repo-visibility.sh --home-repo <owner/repo>
#
#     The coordination PR's own visibility, for the merge-last gate: prints
#     `home=public` or `home=private`. A private coordination PR is gated with
#     `shirabe validate --merge-gate --visibility private`, which lets it index
#     private nodes; a public one is gated without the flag, and the gate
#     refuses any private node in its index.
#
#   repo-visibility.sh --home-repo <owner/repo> --repo <owner/repo> --node <node-id>
#
#     One node checked against its own target before it is dispatched:
#     prints `home=<vis>` and `node=<vis>`, and refuses a private node under a
#     public coordination PR (exit 77) with a diagnostic that names the node
#     id, never the private repository. node-push.sh makes the same check
#     before it pushes.
#
# Both read `gh api repos/<r>`'s `visibility` through coord-common.sh's
# coord_repo_visibility, the read the merge gate's own resolver makes;
# `internal` counts as private. A failed read is never read as either value.
#
# Exit codes:
#   0   printed; the pair (when given) is allowed
#   64  usage error
#   72  a visibility read failed (the caller's execute:status-read)
#   77  a public coordination PR over a private node (execute:visibility)
#
# Read-only. Requires: bash 3.2+, gh, jq.
set -uo pipefail

PROG=repo-visibility

COORD_SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=coord-common.sh
. "$COORD_SELF_DIR/coord-common.sh"

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: repo-visibility.sh --home-repo <owner/repo> [--repo <owner/repo> --node <node-id>]" >&2
    exit 64
}

HOME_REPO=""; REPO=""; NODE=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --home-repo|--repo|--node)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --home-repo) HOME_REPO="$2" ;;
                --repo) REPO="$2" ;;
                --node) NODE="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done
coord_valid_repo "$HOME_REPO" || usage_error "--home-repo [$HOME_REPO] is not a single owner/repo"
if [ -n "$REPO" ] || [ -n "$NODE" ]; then
    { [ -n "$REPO" ] && [ -n "$NODE" ]; } || usage_error "--repo and --node go together"
    coord_valid_repo "$REPO" || usage_error "--repo [$REPO] is not a single owner/repo"
    [[ $NODE =~ $RE_COORD_NODE ]] || usage_error "--node [$NODE] is outside ^[a-z][a-z0-9-]*\$"
fi
command -v jq >/dev/null || { echo "$PROG: jq is not on PATH" >&2; exit 72; }

if [ -z "$REPO" ]; then
    VIS=$(coord_repo_visibility "$HOME_REPO") || {
        echo "$PROG: could not read the visibility of $HOME_REPO" >&2
        exit 72
    }
    printf 'home=%s\n' "$VIS"
    exit 0
fi

coord_node_visibility "$HOME_REPO" "$REPO" "$NODE"
case $? in
    0) printf 'home=%s\nnode=%s\n' "$COORD_HOME_VIS" "$COORD_NODE_VIS"; exit 0 ;;
    3) printf 'home=%s\nnode=%s\n' "$COORD_HOME_VIS" "$COORD_NODE_VIS"; exit 77 ;;
    *) exit 72 ;;
esac
