#!/usr/bin/env bash
# build-output-pin.sh — for /execute: pin the base a recorded worktree's
# build-output cleanup reads its declaration at.
#
# Usage: build-output-pin.sh --session <S> --id <id> --worktree <dir> [--fetch]
#
#   <S>     the run's koto session, ^[A-Za-z0-9][A-Za-z0-9._-]*$
#   <id>    the worktree's id in the run record: `single` on single-pr, the
#           node id on coordinated (^[a-z][a-z0-9-]*$)
#   <dir>   the worktree, any directory inside it
#   --fetch fetch `origin` in the worktree's clone first (a node's clone,
#           which the run's own fetch never reaches)
#
# The cleanup at the run's successful end (build-output-end.sh) reads the
# repository's `build_output` declaration at a base, never at the branch
# head, so a branch can't widen what its own run removes. A plan parent has no
# base of its own to hand it, so this pins one per worktree:
# `git merge-base HEAD <ref>`, where <ref> is the default branch's remote ref
# as default_remote_ref (scripts/lib/default-remote-ref.sh) resolves it in the
# worktree's clone, the same function the cleanup's ancestry check uses. It is
# written through `run-record.sh pin` as `run/cleanup/<id>` holding
# {"path": <the worktree's root>, "pin": <the merge base>}. The pin verb is
# write-once, so a later call (every push of a node calls this) keeps the first
# value: after the branch's pull request merges, a merge base recomputed then
# would be the branch head itself.
#
# Nothing is pinned when:
#   - the session holds run/recovered: a recovered run rebuilt its record from
#     GitHub, and a merge base taken now may already be the merged head;
#   - no ref resolves (a single-branch clone with neither origin/HEAD nor
#     origin/main);
#   - HEAD is already an ancestor of the ref: that head is on the default
#     branch, and a pin there would read the branch's own declaration.
# The end then prints `base unreadable` for that worktree and cleans nothing.
#
# Everything this prints goes to stderr, and it exits 0 whatever happened: a
# pin it can't write never changes the run. Its callers are drift-facts.sh
# (single-pr, right after its own fetch) and node-push.sh node (coordinated,
# after the node's run record is written), both of which keep their own
# stdout and exit codes.
#
# Requires: bash 3.2+, git, jq, koto.
set -uo pipefail

PROG=build-output-pin

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
# shellcheck source=run-record-lib.sh
. "$SELF_DIR/run-record-lib.sh"
# shellcheck source=../../../scripts/lib/default-remote-ref.sh
. "$SELF_DIR/../../../scripts/lib/default-remote-ref.sh" || exit 0

# Nothing reaches the caller's stdout: drift-facts.sh's and node-push.sh's
# lines are their callers' to read.
exec 1>&2

note() { echo "$PROG: $*"; }
stop() { note "$*; nothing was pinned"; exit 0; }

SESSION=""; ID=""; WT=""; FETCH=0
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--id|--worktree)
            [ $# -ge 2 ] || stop "$1 needs a value"
            case "$1" in
                --session) SESSION="$2" ;;
                --id) ID="$2" ;;
                --worktree) WT="$2" ;;
            esac
            shift 2
            ;;
        --fetch) FETCH=1; shift ;;
        *) stop "unexpected argument [$1]" ;;
    esac
done
[[ $SESSION =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || stop "session [$SESSION] is not a koto session name"
[[ $ID =~ ^[a-z][a-z0-9-]*$ ]] || stop "id [$ID] is not a worktree id"
[ -n "$WT" ] && [ -d "$WT" ] || stop "worktree [$WT] is not a directory"
command -v jq >/dev/null || stop "jq is not on PATH"

ROOT=$(git -C "$WT" rev-parse --show-toplevel) || stop "[$WT] is not inside a git work tree"
ROOT=$(CDPATH='' cd -- "$ROOT" && pwd -P) || stop "cannot resolve the work tree root of [$WT]"

rr__present "$SESSION" run/recovered
case $? in
    0) stop "the run recovered its record, so no base predates its merge" ;;
    1) ;;
    *) stop "could not check run/recovered in session $SESSION" ;;
esac

if [ "$FETCH" -eq 1 ]; then
    git -C "$ROOT" fetch --quiet origin </dev/null \
        || note "git fetch origin failed in $ROOT; pinning against the ref already there"
fi

REF=$(default_remote_ref "$ROOT") || stop "no default-branch remote ref resolves in $ROOT"
HEAD_SHA=$(git -C "$ROOT" rev-parse --verify --quiet 'HEAD^{commit}') || stop "HEAD in $ROOT is not a commit"
if git -C "$ROOT" merge-base --is-ancestor "$HEAD_SHA" "$REF"; then
    stop "HEAD in $ROOT is already on $REF"
fi
PIN=$(git -C "$ROOT" merge-base "$HEAD_SHA" "$REF") || stop "HEAD and $REF share no history in $ROOT"
[[ $PIN =~ ^[0-9a-f]{40}$ ]] || stop "the merge base in $ROOT is not a commit id"

DOC=$(mktemp "${TMPDIR:-/tmp}/build-output-pin.XXXXXX") || stop "cannot make a temporary file"
trap 'rm -f "$DOC"' EXIT
jq -cn --arg k "run/cleanup/$ID" --arg p "$ROOT" --arg s "$PIN" '{($k): {path: $p, pin: $s}}' > "$DOC" \
    || stop "cannot build the record"
"$BASH" "$SELF_DIR/run-record.sh" pin --session "$SESSION" --json "$DOC" </dev/null \
    || note "run-record.sh pin did not write run/cleanup/$ID"
exit 0
