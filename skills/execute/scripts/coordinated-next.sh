#!/usr/bin/env bash
# coordinated-next.sh — for /execute: print the one next action of a
# coordinated run.
#
# The coordinated loop's decisions live here, not in prose. The script is
# stateless and read-only: it reads the PLAN's nodes (through
# plan-to-tasks.sh), the run record in the session (run-record-lib.sh: the
# coordination PR's number, the sealed node list, each node's recorded PR and
# pushed head, the cascade's verdict), each open node's work-item children's
# `verification_deferral` keys when its record holds no `deferrals`, read
# where koto says each child is bound (`koto session list`, then
# shared-deferral-record.sh --child-dir), and live `gh`
# (each recorded PR checked against the ownership filter, and an open node
# PR's body when its children deferred), writes nothing anywhere, and prints exactly
# one line. The agent performs that action and runs the script again, until it
# prints `done:<outcome>`, `pause`, or `error:<step>`.
#
# Usage:
#   coordinated-next.sh --session <koto-session> --plan <path> --slug <slug>
#                       --repos <owner/repo,...> --home-repo <owner/repo>
#                       --coord-branch <branch> --merge true|false
#                       [--attempts <node:result,...>] [--run-id <id>]
#
#   --session       the run's koto session, ^[A-Za-z0-9][A-Za-z0-9._-]*$,
#                   whose run record the script reads (never writes). A
#                   session with no run/setup is error:execute:status-read:
#                   coord_setup seals the record before the loop runs.
#   --plan          the PLAN in the coordination checkout. While it exists its
#                   nodes come from plan-to-tasks.sh; once the finalization
#                   cascade has deleted it, from the node list run/setup
#                   sealed.
#   --slug          the topic slug, ^[a-z0-9-]+$; node branches are
#                   impl/<slug>-<node-id>
#   --repos         the write set recorded at coord_setup, comma-joined: the
#                   repositories the PLAN's PR nodes name
#   --home-repo     the repository holding the coordination branch. It need
#                   not be in --repos: a PLAN whose nodes all land elsewhere
#                   keeps its coordination PR in a repository that holds no
#                   node; the run record holds that PR by number, not as a
#                   node
#   --coord-branch  the coordination branch
#   --merge         this invocation's merge intent: exactly `true` or `false`,
#                   passed explicitly by the caller from the session's MERGE
#                   variable. The script reads no koto variable or environment
#                   for it; a missing or other value is a usage error.
#   --run-id        this run's identity (`run-id.sh get <session>`),
#                   ^[0-9a-f]{32}$. Every owned-PR lookup carries it, so a PR
#                   another run opened on a node or coordination branch is
#                   never adopted. Omitted only on a hand run, where the
#                   lookups match by login and branch alone.
#   --attempts      the session's `merge_attempts` record:
#                   `<id>:merge-not-observed` or `<id>:merge-call-failed`
#                   for a merge this run already called and did not see land,
#                   `<id>:merge-refused` for one coord-merge.sh refused
#                   before or at the call (<id> a node, a follow-up's
#                   `<node>/follow-up-<n>`, or `coordination` for the
#                   coordination PR), and `coordination:body-stale` or
#                   `coordination:body-full` for a coordination body
#                   coord-render.sh could not bring up to date before the
#                   coordination PR's evaluation or merge. Such a PR is not
#                   merged or evaluated again in this invocation; it is
#                   reported unmerged with that reason (merge-refused keeps
#                   an awaiting verdict's own reason, and the body results
#                   read merge-refused:body-stale or merge-refused:body-full).
#
# Output: exactly one line, from the closed set (first match wins):
#
#   error:<step>              a read failed, or the session holds no run
#                             record (execute:status-read), a PR the run must
#                             adopt is not the one owned PR on its branch, or
#                             the recorded coordination PR lost its marker
#                             (execute:pr-adopt), a recorded node PR outside
#                             the write set (execute:write-set), a failing
#                             check (execute:ci), a closed PR
#                             (execute:pr-closed), an open node PR whose
#                             work items deferred verification to hosted CI
#                             and whose body doesn't record it
#                             (execute:deferral-record; checked before the
#                             node can be evaluated or merged, so it is never
#                             readied or merged without the record), or a
#                             verdict error
#   done:merged               the coordination PR is MERGED
#   merge:<node>              a node PR whose verdict is mergeable at the head
#                             the run record holds (only with --merge true);
#                             run coord-merge.sh on it
#   merge:<node>/follow-up-<n>  a follow-up PR recorded against a node GitHub
#                             reports MERGED, mergeable at the head the run
#                             record holds for it (only with --merge true);
#                             run coord-merge.sh on that id
#   dispatch:<node>           a node with no recorded PR whose predecessors
#                             are all satisfied: cut it, run its work items,
#                             push
#   evaluate:<node>           a node PR that is still a draft (mark it ready
#                             once its checks pass) or whose checks are pending
#   evaluate:<node>/follow-up-<n>  a follow-up PR whose checks are pending:
#                             wait for them only (the run never readies or
#                             pushes to a follow-up)
#   cascade                   every node PR and every live follow-up (one
#                             recorded and not removed) MERGED, and the
#                             finalization cascade has not run, or
#                             run/cascade holds no `pushed` verdict (absent,
#                             or `failed`)
#   evaluate-coordination     the coordination PR is a draft after the cascade,
#                             or its checks are pending
#   merge-coordination        the coordination PR is mergeable (only with
#                             --merge true)
#   pause                     something is unmerged and a node cannot start
#                             because a predecessor is not satisfied
#   done:ready-awaiting-merge nothing is left to start and something is
#                             unmerged
#
# A PR node is satisfied only when a live read reports its PR MERGED: a merge
# call that returned `merge-called` is never read as merged. A gate node is
# never satisfied by this script, whose reads cannot verify a prose condition:
# it fails closed, and the nodes after it wait.
#
# Exit codes: 0 a line was printed (an error: line included); 64 usage error
# (nothing printed, no gh call made).
#
# Requires: bash 3.2+, jq, gh (through owned-pr.sh and merge-verdict.sh),
# koto (the run record's reads).
set -uo pipefail

PROG=coordinated-next

COORD_SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=coord-common.sh
. "$COORD_SELF_DIR/coord-common.sh"

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: coordinated-next.sh --session <koto-session> --plan <path> --slug <slug> --repos <list> --home-repo <owner/repo> --coord-branch <branch> --merge true|false [--attempts <list>] [--run-id <id>]" >&2
    exit 64
}

CC_SESSION=""; CC_PLAN=""; CC_SLUG=""; CC_REPOS=""; CC_HOME=""; CC_CB=""; CC_MERGE=""; CC_ATTEMPTS=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--plan|--slug|--repos|--home-repo|--coord-branch|--merge|--attempts|--run-id)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --run-id) COORD_RUN_ID="$2" ;;
                --session) CC_SESSION="$2" ;;
                --plan) CC_PLAN="$2" ;;
                --slug) CC_SLUG="$2" ;;
                --repos) CC_REPOS="$2" ;;
                --home-repo) CC_HOME="$2" ;;
                --coord-branch) CC_CB="$2" ;;
                --merge) CC_MERGE="$2" ;;
                --attempts) CC_ATTEMPTS="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done

for f in --session --plan --slug --repos --home-repo --coord-branch --merge; do
    case "$SEEN" in *" $f "*) ;; *) usage_error "$f is required" ;; esac
done
case "$CC_MERGE" in true|false) ;; *) usage_error "--merge must be true or false, got [$CC_MERGE]" ;; esac
[[ $CC_SESSION =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage_error "--session [$CC_SESSION] is not a koto session name"
[[ $CC_SLUG =~ $RE_COORD_SLUG ]] || usage_error "--slug [$CC_SLUG] is outside ^[a-z0-9-]+\$"
coord_valid_repo_list "$CC_REPOS" || usage_error "--repos [$CC_REPOS] is not a comma-joined owner/repo list"
coord_valid_repo "$CC_HOME" || usage_error "--home-repo [$CC_HOME] is not a single owner/repo"
coord_valid_branch "$CC_CB" || usage_error "--coord-branch [$CC_CB] is not an allowed branch name"
[ -n "$CC_PLAN" ] || usage_error "--plan is empty"
case "/$CC_PLAN/" in */../*) usage_error "--plan [$CC_PLAN] has a .. segment" ;; esac
case "$CC_PLAN" in *[!A-Za-z0-9._/-]*) usage_error "--plan [$CC_PLAN] holds a character outside [A-Za-z0-9._/-]" ;; esac
if [ -n "$CC_ATTEMPTS" ] && ! [[ $CC_ATTEMPTS =~ $RE_COORD_ATTEMPTS ]]; then
    usage_error "--attempts [$CC_ATTEMPTS] is outside <node|node/follow-up-n|coordination>:<merge-not-observed|merge-call-failed|merge-refused|body-stale|body-full>,..."
fi
case "$SEEN" in
    *" --run-id "*) [[ $COORD_RUN_ID =~ $RE_COORD_RUN_ID ]] || usage_error "--run-id [$COORD_RUN_ID] is not a run id" ;;
esac
command -v jq >/dev/null || { printf 'error:execute:status-read\n'; echo "$PROG: jq is not on PATH" >&2; exit 0; }

coord_compute
printf '%s\n' "$CC_ACTION"
exit 0
