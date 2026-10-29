#!/usr/bin/env bash
# record-coord-setup.sh — for /execute: fix a coordinated run's write set and
# coordination home at start, and seal its run record, or rebuild one a run
# lost, and record a follow-up PR against one of its nodes.
#
# execute-coordinated.md's `coord_setup` state is agent-run: the agent runs
# this script in the coordination checkout (the checkout holding the
# coordination branch and the PLAN), then ticks. The state's non-overridable
# context-matches gates read back what it wrote, so a run that could not
# record its write set never reaches the loop.
#
# What it writes. Four fixed context keys:
#
#   repos         the write set: every PR node's REPO as plan-to-tasks.sh
#                 emits it, sorted, de-duplicated, comma-joined. Every node PR
#                 the run opens, edits, readies, or merges must be in one of
#                 these repositories, and a recorded node naming any other is
#                 refused. The coordination PR is the one exception: it lives
#                 in home_repo.
#   home_repo     the one repository holding the coordination branch, read
#                 from the origin remote the way record-write-set.sh reads it.
#                 It must match ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$. It need not
#                 be one of the repos entries: a PLAN whose nodes all land in
#                 other repositories (a private planning repository over
#                 public ones, say) keeps its coordination PR here. The run
#                 writes to it only through the coordination PR's own paths:
#                 the body edits, marking it ready, and its merge, which take
#                 home_repo explicitly, and the coordination branch's push,
#                 which goes to this checkout's origin, the remote home_repo
#                 is read from.
#   coord_branch  the checked-out branch: the coordination branch. A detached
#                 HEAD and the remote's default branch are refused.
#   plan_abs      the PLAN's absolute path in this checkout, which outline
#                 children receive as PLAN_DOC (node branches don't carry it).
#
# All four are fixed for the run: a re-run that computes the same values is a
# no-op, and one that computes a different value refuses rather than moving
# the write set mid-run. The one exception is plan_abs on a moved attach:
# when the run's checkout moved (re-cloned elsewhere, the old directory
# removed, the session rebound to the new one), execute-open.sh runs
# --reroot-plan on attaching the coordinated session, and plan_abs is
# re-rooted to the PLAN in this checkout. That happens only when the recorded
# file doesn't exist, this checkout is on the recorded coord_branch, its
# origin (read as record-write-set.sh reads it) is the recorded home_repo, and
# --plan names an existing file. It then writes plan_abs and nothing else,
# prints `plan_abs=rerooted`, and names both paths in one stderr line; in any
# other case it writes nothing and prints `plan_abs=kept`. It makes no GitHub
# read and no isolation check, and takes no other flag.
#
# Besides them: the run's identity, `run_id` (run-id.sh mint on a new run,
# and seed, adopt or mint on a recovery); the run record's `run/` keys, only
# through run-record.sh (`setup` on a new run, `adopt` and `recover` on a
# recovery, `follow-up` for --follow-up); and, after a recovery, the
# `recovered` context key. On GitHub it makes two writes at most: adopt's
# marker stamps on a recovering start given --adopt-run, and the coordination
# PR's body, rendered by coord-render.sh after a follow-up is recorded or
# removed.
#
# A session that holds its record (run/setup present) makes no lookup: it
# compares --store with the sealed store, a --coordination-pr with the
# recorded number, and reads the recorded PR's state, refusing one closed
# unmerged. With the PLAN gone (the cascade deleted it) `repos` comes from
# run/setup and plan_abs is still computed from --plan; with the PLAN there,
# a PLAN whose nodes now name other repositories exits 68. It mints the run's
# identity if a crash left the record without one. --adopt-run is refused
# here (`adopt-run-refused`), before any GitHub read.
#
# A session with no record finds the coordination PR through the ownership
# lookup (owned-pr.sh on home_repo and the coordination branch, in any state,
# carrying the declaration marker), checks a --coordination-pr against it,
# refuses a PR closed unmerged (an already-merged one is accepted: the loop
# ends it done:merged), and reads its body with cb_parse
# (scripts/lib/coordination-body.sh, the codec; no other body read exists).
# With the PLAN on the branch, each PR node's branch impl/<slug>-<node> gets
# one owned-PR lookup (no --run-id, so another run's marker is seen below
# rather than hidden). Then it decides whether a run had started: a carried
# run_id (the opener seeds one only from a replaced session or a snapshot), a
# rendered `run=` line, a PR Index line (a node's or a follow-up's), or an
# owned PR on a PLAN node's branch. The store of that run is --store, else
# the body's `store=` line, else github; a --store that differs from the
# body's line stops store-mismatch.
#
#   Nothing started: a new run. It seals run/setup through `run-record.sh
#   setup` (the store, the coordination PR's number, repos, mode
#   `coordinated`, the node list from the PLAN ({name, kind, repo, waits_on},
#   in plan-to-tasks.sh's order), and the body's run lines as cb_parse reads
#   them), then mints the run's identity (`run-id.sh mint`), in that order,
#   so a seal that fails leaves no run_id to read as started next time. With
#   no PLAN this is the usage error it always was. --adopt-run stops
#   adopt-run-refused.
#
#   Started, store session: the record lived in the run's execute session,
#   which is not here. It stops session-absent, naming the import.
#
#   Started, store github: recovery. The PLAN must be on the branch (else
#   coordination-index-missing with no index line, or recovery-plan-gone).
#   An index with no node line, beside an owned PR on a PLAN node's branch,
#   stops coordination-index-missing. Each node line must name a PR node of
#   the PLAN in that node's repository, the one owned PR on its branch (no PR,
#   several, a PR closed unmerged, another author, branch, base or a fork all
#   fail), and then carry the run's marker. The run's identity is, in order:
#   --adopt-run, the carried run_id, the body's run= line, the one id every
#   node PR's marker names, and, only when the index holds no node line, a
#   minted one. A node PR whose marker names another run, a malformed one, or
#   none, and every node PR when there is no identity, stops
#   recovery-unproven naming each, with its reason and URL. With --adopt-run
#   those PRs (and only those) are stamped instead: run-id.sh restamp or
#   stamp, `gh pr edit --body-file`, and a re-read that must show the id. A
#   stamp that fails stops recovery-unproven naming the PR as not stampable;
#   stamps already made stay, and a re-run with the same id finds them
#   already marked and makes no edit. The stamps run only after every check
#   passed. Each follow-up line is kept or dropped: kept when its node is a
#   recovered node, its repository the node's, its id's number its ref's, and
#   a live read passes coord_follow_up_check (no marker is asked of it: a
#   follow-up is a person's PR); dropped otherwise, printing
#   `follow-up-dropped:<url>` with the reason on stderr. A failed read of one
#   exits 72 rather than dropping it. Then it writes, in order: the identity
#   (run-id.sh adopt, seed or mint; a carried one stays), run/adopted {id,
#   login, at} with --adopt-run (`run-record.sh adopt`), and one `run-record.sh
#   recover` document: run/setup (store github, the coordination PR's number,
#   repos, the PLAN's nodes, the body's run lines), run/node/<node> {repo, pr,
#   head: the live headRefOid, merged_head: the live merge commit when
#   MERGED}, each kept follow-up's run/follow-up/<node>/<n> {repo, pr, head,
#   removed false, merged_head when MERGED}, run/cascade {verdict: not-run}
#   and run/recovered {pr: the coordination PR's URL, source}. Then the
#   `recovered` context key (the URL; the opener removes it at every
#   invocation's start). No head the body names is ever recorded.
#
# --follow-up "<node> <url>" records a follow-up PR against a node, after the
# record is loaded or recovered and before any write. The space form is the
# only form: the template sends it from execute-open.sh's FOLLOW_UP, which
# turns the <node>=<url> the user types into it because koto's value
# allowlist has no `=`, so a `<node>=<url>` here is a usage error. The node
# must be a PR node of the run with a recorded node PR, and the URL none of the run's node
# PRs, not the coordination PR and not a follow-up recorded under another
# node (else follow-up-node; a new run has no node PR, so it is always
# follow-up-node there); the PR must be in the node's repository
# (follow-up-repo), based on its default branch (follow-up-base), opened by
# the authenticated login from this repository, not a fork (follow-up-author),
# and not closed unmerged (follow-up-closed). An open or MERGED PR is recorded
# through `run-record.sh follow-up` as run/follow-up/<node>/<n> {repo, pr,
# head: its live headRefOid, removed false}; recording it again updates the
# head. With --follow-up-remove true it is marked removed instead: the key
# must exist (else follow-up-node), and no live check runs, since a closed
# follow-up is the one a person removes. Either way it prints
# `follow-up=recorded:<url>` or `follow-up=removed:<url>`, then renders the
# coordination PR's body (coord-render.sh) and prints its lines; the render's
# result never changes this script's exit (a refusal prints
# `body=refused:execute:visibility`, any other failure `body=stale`, and the
# next transition renders again).
#
# Every check runs before any write, so a stop changes no key and, adopt's
# stamps aside, nothing on GitHub. The first comes right after the argument
# checks, before any GitHub read or koto call, and only while the PLAN is
# present: worktree-isolation.sh stops worktree-isolated when this
# session is isolated in one repository's worktree and the PLAN has PR nodes
# in other repositories, which it couldn't build; its message names both and
# what to do.
#
# Usage: record-coord-setup.sh --session <koto-session> --plan <path>
#            [--store <github|session>] [--coordination-pr <url>]
#            [--follow-up "<node> <url>" [--follow-up-remove true]]
#            [--adopt-run <id>]
#        record-coord-setup.sh --reroot-plan --session <koto-session> --plan <path>
#
# Each optional value may be empty (the template passes its rebind variables
# verbatim), which is the same as leaving the flag out. --follow-up-remove
# true with no --follow-up is a usage error.
#
# Output: `repos=`, `home_repo=`, `coord_branch=`, `plan_abs=`, `store=`,
# `coordination_pr=<url>`, `record=new|existing|recovered` lines on stdout,
# `recovered=<url>` after a recovery, one `follow-up-dropped:<url>` per
# follow-up line a recovery dropped, and with --follow-up the
# `follow-up=recorded:<url>` or `follow-up=removed:<url>` line and the
# render's `observed=` and `body=` lines. A typed stop prints only
# `stop=<code>`: store-mismatch, coordination-pr-missing,
# coordination-pr-ambiguous, coordination-pr-mismatch,
# coordination-pr-closed, session-absent, recovery-unproven,
# recovery-plan-gone, coordination-index-missing, coordination-body-full,
# adopt-run-refused, follow-up-node, follow-up-repo, follow-up-base,
# follow-up-author, follow-up-closed, worktree-isolated.
#
# Exit codes:
#   0   recorded (or already recorded with the same values); with
#       --reroot-plan, plan_abs re-rooted or kept
#   64  usage error
#   65  HEAD is detached
#   66  a value is outside its pattern, this checkout's owner/repo could
#       not be read, or worktree-isolation.sh could not decide whether this
#       session is isolated
#   67  the checked-out branch is the remote's default branch
#   68  a different value is already recorded for this session
#   69  the PLAN could not be read into nodes
#   70  a koto context read or write failed, the run record write was
#       refused, or no run identity could be minted
#   71  a typed stop (stdout `stop=<code>`); nothing was written
#   72  a GitHub read failed; nothing was written
#
# Requires: bash 3.2+, git, jq, gh, koto.
set -uo pipefail

PROG=record-coord-setup

COORD_SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=coord-common.sh
. "$COORD_SELF_DIR/coord-common.sh"
# shellcheck source=../../../scripts/lib/coordination-body.sh
. "$COORD_SELF_DIR/../../../scripts/lib/coordination-body.sh" || exit 64

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_STORE='^(github|session)?$'
RE_URL_OPT='^(https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*)?$'
RE_FOLLOW_UP='^([a-z][a-z0-9-]* https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*)?$'
RE_REMOVE='^(true)?$'
RE_ADOPT='^([0-9a-f]{32})?$'
RE_LOGIN='^[A-Za-z0-9](-?[A-Za-z0-9]){0,38}$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: record-coord-setup.sh --session <koto-session> --plan <path> [--store <github|session>] [--coordination-pr <url>] [--follow-up \"<node> <url>\" [--follow-up-remove true]] [--adopt-run <id>]" >&2
    echo "       record-coord-setup.sh --reroot-plan --session <koto-session> --plan <path>" >&2
    exit 64
}

stop() { # stop <code> <why> -- a typed stop: nothing has been written
    printf 'stop=%s\n' "$1"
    echo "$PROG: stopped ($1): $2. Nothing was written." >&2
    exit 71
}

SESSION=""; PLAN=""; STORE=""; CPR=""; FOLLOW_UP=""; REMOVE=""; ADOPT=""; REROOT=0
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --reroot-plan)
            [ "$REROOT" -eq 0 ] || usage_error "--reroot-plan given more than once"
            REROOT=1
            shift
            ;;
        --session|--plan|--store|--coordination-pr|--follow-up|--follow-up-remove|--adopt-run)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --session) SESSION="$2" ;;
                --plan) PLAN="$2" ;;
                --store) STORE="$2" ;;
                --coordination-pr) CPR="$2" ;;
                --follow-up) FOLLOW_UP="$2" ;;
                --follow-up-remove) REMOVE="$2" ;;
                --adopt-run) ADOPT="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done
[[ $SESSION =~ $RE_SESSION ]] || usage_error "session [$SESSION] is not a koto session name"
[ -n "$PLAN" ] || usage_error "--plan is required"
case "$PLAN" in *"
"*) usage_error "the PLAN path holds a newline" ;; esac
[[ $STORE =~ $RE_STORE ]] || usage_error "--store [$STORE] is not github or session"
[[ $CPR =~ $RE_URL_OPT ]] || usage_error "--coordination-pr [$CPR] is not a pull request URL"
[[ $FOLLOW_UP =~ $RE_FOLLOW_UP ]] || usage_error "--follow-up [$FOLLOW_UP] is not \"<node> <pull request URL>\""
[[ $REMOVE =~ $RE_REMOVE ]] || usage_error "--follow-up-remove [$REMOVE] is not true"
[[ $ADOPT =~ $RE_ADOPT ]] || usage_error "--adopt-run [$ADOPT] is not a run id"
# The opener refuses --remove without --follow-up too; this script doesn't
# rely on it.
[ -n "$REMOVE" ] && [ -z "$FOLLOW_UP" ] && usage_error "--follow-up-remove true needs --follow-up \"<node> <url>\""

# --reroot-plan: the one change plan_abs takes once recorded (see the header).
# Each condition that fails keeps the recorded path; only a failed write is an
# error.
if [ "$REROOT" -eq 1 ]; then
    [ -z "$STORE$CPR$FOLLOW_UP$REMOVE$ADOPT" ] || usage_error "--reroot-plan takes only --session and --plan"
    kept() { printf 'plan_abs=kept\n'; exit 0; }
    # A session before setup has none of the keys: `exists` answers that
    # quietly, so only a read that really fails reaches stderr.
    koto context exists "$SESSION" plan_abs >/dev/null || kept
    OLD_ABS=$(koto context get "$SESSION" plan_abs) || kept
    [ -n "$OLD_ABS" ] && [ ! -e "$OLD_ABS" ] && [ -f "$PLAN" ] || kept
    # --quiet: a detached HEAD fails with no message.
    CB=$(git symbolic-ref --quiet --short HEAD) || kept
    koto context exists "$SESSION" coord_branch >/dev/null || kept
    REC_CB=$(koto context get "$SESSION" coord_branch) || kept
    [ -n "$REC_CB" ] && [ "$CB" = "$REC_CB" ] || kept
    HOME_REPO=$("$BASH" "$COORD_SELF_DIR/record-write-set.sh" --print 2>/dev/null) || kept
    koto context exists "$SESSION" home_repo >/dev/null || kept
    REC_HOME=$(koto context get "$SESSION" home_repo) || kept
    [ -n "$REC_HOME" ] && [ "$HOME_REPO" = "$REC_HOME" ] || kept
    PLAN_DIR=$(CDPATH='' cd "$(dirname -- "$PLAN")" && pwd -P) || kept
    PLAN_ABS="$PLAN_DIR/$(basename -- "$PLAN")"
    [ "$PLAN_ABS" != "$OLD_ABS" ] || kept
    printf '%s' "$PLAN_ABS" | koto context add "$SESSION" plan_abs >/dev/null || {
        echo "$PROG: could not write context key plan_abs in session $SESSION" >&2
        exit 70
    }
    echo "$PROG: plan_abs [$OLD_ABS] is gone; re-rooted to [$PLAN_ABS], the PLAN in this checkout of $HOME_REPO on $CB" >&2
    printf 'plan_abs=rerooted\n'
    exit 0
fi

# The follow-up, split at its first space (a node id holds none):
# its node, the URL as given, its owner/repo and its number.
FU_NODE=""; FU_URL_IN=""; FU_REPO_IN=""; FU_NUM=""
if [ -n "$FOLLOW_UP" ]; then
    FU_NODE="${FOLLOW_UP%% *}"
    FU_URL_IN="${FOLLOW_UP#* }"
    FU_REPO_IN=$(printf '%s' "$FU_URL_IN" | sed -E 's#^https://[^/]+/([^/]+/[^/]+)/pull/[0-9]+$#\1#')
    FU_NUM="${FU_URL_IN##*/}"
    coord_valid_repo "$FU_REPO_IN" || usage_error "--follow-up's URL [$FU_URL_IN] names no usable owner/repo"
fi

PLAN_PRESENT=0
[ -f "$PLAN" ] && PLAN_PRESENT=1
SLUG=$(basename -- "$PLAN" .md)
SLUG=${SLUG#PLAN-}

# A session isolated in one repository's worktree can't run git in another
# repository's checkout, so a PLAN with nodes there stops here, before any
# GitHub read or koto call and before any node is cut. With the PLAN gone
# (the cascade deleted it) no node is left to cut, so the check is skipped.
if [ "$PLAN_PRESENT" -eq 1 ]; then
    ISOLATION=$(bash "$COORD_SELF_DIR/worktree-isolation.sh" --plan "$PLAN" </dev/null)
    case $? in
        0) ;;
        1)
            ISOLATION_MSG=$(printf '%s\n' "$ISOLATION" | sed -n 's/^message=//p')
            stop worktree-isolated "${ISOLATION_MSG%.}"
            ;;
        64)
            echo "$PROG: worktree-isolation.sh refused its arguments" >&2
            exit 64
            ;;
        *)
            echo "$PROG: could not tell whether this session is isolated in one repository's worktree" >&2
            exit 66
            ;;
    esac
fi

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf -- "$WORK"; return 0; }
trap cleanup EXIT

# read_plan -- TASKS, REPOS and NODES from the PLAN on the branch.
read_plan() {
    TASKS=$("$BASH" "$COORD_PLAN_TO_TASKS" "$PLAN" </dev/null) || {
        echo "$PROG: plan-to-tasks.sh could not read $PLAN into nodes" >&2
        exit 69
    }
    REPOS=$(printf '%s' "$TASKS" | jq -r '
        if type != "array" then error("not an array") else . end
        | [.[] | select((.vars.NODE_KIND // "pr") == "pr") | .vars.REPO // ""] | unique | join(",")') || {
        echo "$PROG: plan-to-tasks.sh did not emit a node list" >&2
        exit 69
    }
    coord_valid_repo_list "$REPOS" || {
        echo "$PROG: the PLAN's node repositories [$REPOS] are not a list of owner/repo" >&2
        exit 66
    }
    NODES=$(printf '%s' "$TASKS" | jq -c '[.[] | {name, kind: (.vars.NODE_KIND // "pr"), repo: (.vars.REPO // ""), waits_on: (.waits_on // [])}]') || exit 69
}

# read_login -- the authenticated login, read once for the run: adopt records
# it, and a follow-up's author must be it.
read_login() {
    [ -n "$LOGIN" ] && return 0
    coord_gh_read LOGIN api user --jq .login || { echo "$PROG: could not read the authenticated login" >&2; exit 72; }
    [[ $LOGIN =~ $RE_LOGIN ]] || { echo "$PROG: the authenticated login read as [$LOGIN]" >&2; exit 72; }
}

# home_repo, read exactly as record-write-set.sh reads it.
HOME_REPO=$("$BASH" "$COORD_SELF_DIR/record-write-set.sh" --print) || {
    echo "$PROG: could not read this checkout's owner/repo" >&2
    exit 66
}
coord_valid_repo "$HOME_REPO" || { echo "$PROG: home_repo [$HOME_REPO] is not a single owner/repo" >&2; exit 66; }

# coord_branch.
CB=$(git symbolic-ref --quiet --short HEAD) || {
    echo "$PROG: HEAD is detached; check out the coordination branch" >&2
    exit 65
}
coord_valid_branch "$CB" || { echo "$PROG: branch [$CB] is not an allowed branch name" >&2; exit 66; }
DEFAULT=$(git ls-remote --symref origin HEAD </dev/null \
    | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p')
DEFAULT=${DEFAULT%%$'\n'*}
if [ -z "$DEFAULT" ]; then
    DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD || true)
    DEFAULT=${DEFAULT#origin/}
fi
if [ -n "$DEFAULT" ]; then
    [ "$CB" = "$DEFAULT" ] && { echo "$PROG: [$CB] is the default branch, not a coordination branch" >&2; exit 67; }
else
    case "$CB" in main|master) echo "$PROG: [$CB] is a default branch name, not a coordination branch" >&2; exit 67 ;; esac
fi

# plan_abs: the PLAN's directory resolved physically. With the PLAN gone the
# directory may be gone too; then it is the path as given, under this
# checkout (PLAN_DOC's pattern admits no `.` or `..` segment).
PLAN_ABS=""
if [ "$PLAN_PRESENT" -eq 1 ] || [ -d "$(dirname -- "$PLAN")" ]; then
    PLAN_DIR=$(CDPATH='' cd "$(dirname -- "$PLAN")" && pwd -P) || exit 69
    PLAN_ABS="$PLAN_DIR/$(basename -- "$PLAN")"
else
    case "$PLAN" in
        /*) PLAN_ABS="$PLAN" ;;
        *) PLAN_ABS="$(pwd -P)/$PLAN" ;;
    esac
fi
case "$PLAN_ABS" in /*) ;; *) echo "$PROG: [$PLAN_ABS] is not absolute" >&2; exit 66 ;; esac
case "$PLAN_ABS" in *"
"*) echo "$PROG: the PLAN path holds a newline" >&2; exit 66 ;; esac

# The run's identity, when the session has one. With no record it can only
# have been carried in (the opener seeds one from a replaced session or a
# snapshot and never mints for a coordinated PLAN; setup mints only after it
# seals), so it is one of the signals that a run had started. The ownership
# lookup carries it.
COORD_RUN_ID=$("$BASH" "$COORD_SELF_DIR/run-id.sh" get "$SESSION" 2>/dev/null </dev/null)
case $? in
    0) ;;
    67) COORD_RUN_ID="" ;;
    *) echo "$PROG: could not read run_id in session $SESSION" >&2; exit 70 ;;
esac
CARRIED="$COORD_RUN_ID"

# The handed coordination PR, split into its repository and number.
CPR_REPO=""; CPR_NUM=""
if [ -n "$CPR" ]; then
    CPR_REPO=$(printf '%s' "$CPR" | sed -E 's#^https://[^/]+/([^/]+/[^/]+)/pull/[0-9]+$#\1#')
    CPR_NUM="${CPR##*/}"
fi
cpr_matches() { # cpr_matches <number> -- the handed PR is #<number> in home_repo
    [ "$(coord_lower "$CPR_REPO")" = "$(coord_lower "$HOME_REPO")" ] && [ "$CPR_NUM" = "$1" ]
}

# The run record. START_KIND is which start this is: existing (the session
# holds run/setup), and, once the record's absence is read below, new or
# recovered.
SETUP=$(rr_setup "$SESSION")
case $? in
    0) START_KIND=existing ;;
    1) START_KIND=none ;;
    *) echo "$PROG: could not read the run record in session $SESSION" >&2; exit 70 ;;
esac

RUN_LINES='{}'; NODES='[]'; RECOVER_ROWS=""; FU_ROWS=""; DROPPED=""; SOURCE=""; RUN_ID=""; STAMPS=""; LOGIN=""
# VIEW: the run record as it will stand once this invocation's own writes
# land (the held one, the recovered one, or a new run's), which a
# --follow-up is checked against before anything is written.
VIEW='{}'

if [ "$START_KIND" = existing ]; then
    if [ -n "$ADOPT" ]; then
        stop adopt-run-refused "this session holds the run's record; --adopt-run applies only to a start that recovers"
    fi
    SEALED_STORE=$(printf '%s' "$SETUP" | jq -r '.store // ""')
    SEALED_REPOS=$(printf '%s' "$SETUP" | jq -r '(.repos // []) | join(",")')
    C_NUM=$(printf '%s' "$SETUP" | jq -r '.coordination_pr // ""')
    [[ $C_NUM =~ ^[1-9][0-9]*$ ]] || { echo "$PROG: run/setup holds no coordination PR number" >&2; exit 70; }
    if [ -n "$STORE" ] && [ "$STORE" != "$SEALED_STORE" ]; then
        stop store-mismatch "this run's store is sealed as $SEALED_STORE, and this invocation asked for $STORE"
    fi
    STORE="$SEALED_STORE"
    if [ "$PLAN_PRESENT" -eq 1 ]; then
        read_plan
        if [ "$REPOS" != "$SEALED_REPOS" ]; then
            echo "$PROG: the run record's repos are [$SEALED_REPOS]; the PLAN's nodes now name [$REPOS]; refusing to change the write set" >&2
            exit 68
        fi
    else
        # The cascade deleted the PLAN: the write set is the one sealed.
        REPOS="$SEALED_REPOS"
        coord_valid_repo_list "$REPOS" || { echo "$PROG: run/setup's repos [$REPOS] are not a list of owner/repo" >&2; exit 70; }
    fi
    if [ -n "$CPR" ] && ! cpr_matches "$C_NUM"; then
        stop coordination-pr-mismatch "the run recorded #$C_NUM in $HOME_REPO as its coordination PR, not $CPR"
    fi
    # No lookup: the recorded number, read once for its state.
    C_VIEW=""
    coord_gh_read C_VIEW pr view "$C_NUM" --repo "$HOME_REPO" --json state,url || {
        echo "$PROG: could not read the recorded coordination PR #$C_NUM in $HOME_REPO" >&2
        exit 72
    }
    C_STATE=$(printf '%s' "$C_VIEW" | jq -r 'if type == "object" then (.state // "") else "" end')
    C_URL=$(printf '%s' "$C_VIEW" | jq -r 'if type == "object" then (.url // "") else "" end')
    case "$C_STATE" in
        OPEN|MERGED) ;;
        CLOSED) stop coordination-pr-closed "the recorded coordination PR $C_URL is closed unmerged" ;;
        *) echo "$PROG: the recorded coordination PR's state read as [$C_STATE]" >&2; exit 72 ;;
    esac
    [[ $C_URL =~ $RE_COORD_URL ]] || { echo "$PROG: the recorded coordination PR's URL read as [$C_URL]" >&2; exit 72; }
    if [ -n "$FOLLOW_UP" ]; then
        VIEW=$(rr_record "$SESSION") || { echo "$PROG: could not read the run record in session $SESSION" >&2; exit 70; }
    fi
else
    # No record: the ownership lookup, once, over every state. A coordination
    # PR already MERGED is a run the loop ends done:merged; only one CLOSED
    # unmerged stops, below.
    coord_find_pr "$HOME_REPO" "$CB" all
    case $? in
        0) ;;
        2) exit 72 ;;
        *)
            case "$C_WHY" in
                several) stop coordination-pr-ambiguous "several owned coordination PRs on $HOME_REPO $CB, or an ambiguous lookup" ;;
                *)
                    if [ -n "$CPR" ]; then
                        # The lookup never sees a PR closed unmerged
                        # (owned-pr.sh --state all drops it). A handed one,
                        # in home_repo on this branch with the marker, that
                        # reads CLOSED is that stop, not a mismatch.
                        if [ "$C_WHY" = none ] && [ "$(coord_lower "$CPR_REPO")" = "$(coord_lower "$HOME_REPO")" ]; then
                            C_VIEW=""
                            coord_gh_read C_VIEW pr view "$CPR_NUM" --repo "$HOME_REPO" --json state,headRefName,body || exit 72
                            if printf '%s' "$C_VIEW" | jq -e --arg cb "$CB" --arg m "$COORD_MARKER" \
                                'type == "object" and .state == "CLOSED" and .headRefName == $cb and ((.body // "") | contains($m))' >/dev/null; then
                                stop coordination-pr-closed "the handed coordination PR $CPR is closed unmerged"
                            fi
                        fi
                        stop coordination-pr-mismatch "$CPR is not the one coordination PR this run owns on $HOME_REPO $CB ($C_WHY)"
                    fi
                    stop coordination-pr-missing "no coordination PR this run owns on $HOME_REPO $CB ($C_WHY); /scope opens it"
                    ;;
            esac
            ;;
    esac
    if [ -n "$CPR" ] && ! cpr_matches "$C_NUM"; then
        stop coordination-pr-mismatch "$CPR differs from the coordination PR the lookup found, $C_URL"
    fi
    case "$(printf '%s' "$C_JSON" | jq -r '.state // ""')" in
        OPEN|MERGED) ;;
        CLOSED) stop coordination-pr-closed "the coordination PR $C_URL is closed unmerged" ;;
        *) echo "$PROG: the coordination PR's state read as [$(printf '%s' "$C_JSON" | jq -r '.state // ""')]" >&2; exit 72 ;;
    esac

    # The body, read once, through the codec.
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/record-coord-setup.XXXXXX") || { WORK=""; echo "$PROG: no temporary directory" >&2; exit 70; }
    printf '%s' "$C_JSON" | jq -j '.body // ""' > "$WORK/coordination.md" || exit 70
    PARSED=$(cb_parse "$WORK/coordination.md" "$HOME_REPO" "$C_NUM" 2>"$WORK/parse.err")
    case $? in
        0) ;;
        3) stop coordination-body-full "the coordination PR $C_URL's body is over the $CB_MAX_BYTES-byte cap, so it was not read" ;;
        4) stop recovery-unproven "a PR Index line of $C_URL is outside the entry grammar ($(tail -1 "$WORK/parse.err"))" ;;
        *) cat "$WORK/parse.err" >&2; echo "$PROG: could not read the coordination PR's body" >&2; exit 72 ;;
    esac
    RUN_LINES=$(printf '%s' "$PARSED" | jq -c '.run_lines') || exit 72
    BODY_RUN=$(printf '%s' "$PARSED" | jq -r '.run // ""')
    BODY_STORE=$(printf '%s' "$PARSED" | jq -r '.store // ""')
    N_INDEX_NODES=$(printf '%s' "$PARSED" | jq '.nodes | length')
    N_INDEX_FUS=$(printf '%s' "$PARSED" | jq '[.follow_ups[] | length] | add // 0')

    # The PLAN's nodes, and each PR node's branch read through the ownership
    # lookup, without --run-id: a PR another run marked is kept here and its
    # marker read below, never hidden.
    OWNED_ROWS=""
    if [ "$PLAN_PRESENT" -eq 1 ]; then
        read_plan
        [[ $SLUG =~ $RE_COORD_SLUG ]] || { echo "$PROG: the PLAN's slug [$SLUG] is outside ^[a-z0-9-]+\$" >&2; exit 66; }
        PR_NODES=$(printf '%s' "$NODES" | jq -r '.[] | select(.kind == "pr") | [.name, .repo] | @tsv') || exit 69
        while IFS=$'\t' read -r n r; do
            [ -n "$n" ] || continue
            # coord_owned with no identity (its hand-run branch), in the
            # subshell only: with --run-id a PR another run marked would be
            # exit 5 here, and recovery has to read that marker to name it.
            out=$(COORD_RUN_ID=""; coord_owned "$r" "impl/$SLUG-$n" all)
            rc=$?
            case "$rc" in
                0) if [ -n "$out" ]; then st=owned; else st=none; fi ;;
                3) st=several; out="" ;;
                *) echo "$PROG: the owned-PR lookup on $r impl/$SLUG-$n failed (owned-pr.sh exit $rc)" >&2; exit 72 ;;
            esac
            OWNED_ROWS="$OWNED_ROWS$n	$r	$st	$out
"
        done <<<"$PR_NODES"
    fi
    OWNED_NODES=$(printf '%s' "$OWNED_ROWS" | awk -F'\t' '$3 == "owned" { printf "%s%s", sep, $1; sep = ", " }')

    # Had a run started here? Each signal is something only a started run
    # leaves behind:
    STARTED=0
    # a carried run_id: the opener seeds one only from a replaced session or
    # a snapshot of one, never for a new coordinated run;
    [ -n "$CARRIED" ] && STARTED=1
    # a `run=` line: only a render writes one, and a render needs a record;
    [ -n "$BODY_RUN" ] && STARTED=1
    # an index line, a node's or a follow-up's: only a run writes one;
    [ "$N_INDEX_NODES" -gt 0 ] && STARTED=1
    [ "$N_INDEX_FUS" -gt 0 ] && STARTED=1
    # an owned PR on a PLAN node's branch: only node-push.sh opens those.
    [ -n "$OWNED_NODES" ] && STARTED=1
    if [ "$PLAN_PRESENT" -eq 0 ] && [ "$STARTED" -eq 0 ]; then
        usage_error "no PLAN at [$PLAN]"
    fi

    # The store of the run that started, or of the new one.
    if [ -n "$STORE" ] && [ -n "$BODY_STORE" ] && [ "$STORE" != "$BODY_STORE" ]; then
        stop store-mismatch "the coordination PR's body says this run's store is $BODY_STORE, and this invocation asked for $STORE"
    fi
    [ -n "$STORE" ] || STORE="$BODY_STORE"
    [ -n "$STORE" ] || STORE=github

    if [ "$STARTED" -eq 0 ]; then
        if [ -n "$ADOPT" ]; then
            stop adopt-run-refused "no run had started here (no run line, no index line, no owned node PR, no carried run_id); --adopt-run applies only to a start that recovers"
        fi
        START_KIND=new
    elif [ "$STORE" = session ]; then
        stop session-absent "this run keeps its record in its execute session, which isn't in this workspace. Bring it here with skill-session.sh import execute $SLUG --from <workspace>, or run /execute where that session lives"
    else
        START_KIND=recovered
        if [ "$PLAN_PRESENT" -eq 0 ]; then
            if [ "$N_INDEX_NODES" -eq 0 ] && [ "$N_INDEX_FUS" -eq 0 ]; then
                stop coordination-index-missing "the PLAN [$PLAN] is gone and $C_URL holds no PR Index line to rebuild the run from"
            fi
            stop recovery-plan-gone "the PLAN [$PLAN] was deleted by the cascade; only the coordination merge is left: merge $C_URL by hand, or import the run's session"
        fi
        if [ "$N_INDEX_NODES" -eq 0 ] && [ -n "$OWNED_NODES" ]; then
            stop coordination-index-missing "$C_URL holds no node in its PR Index, but $OWNED_NODES have an owned PR on their branches"
        fi

        # Pass 1, no GitHub read: each index node is a PR node of the PLAN, in
        # that node's repository.
        UNPROVEN=""; ONLY_MARKER_REASONS=1
        # unproven <node> <where> <reason> <marker|other> -- name a node PR
        # recovery can't prove is this run's. A reason other than its marker
        # means --adopt-run can't help, so the hint to use it is dropped.
        unproven() {
            UNPROVEN="$UNPROVEN
  $1 ($2): $3"
            [ "$4" = marker ] || ONLY_MARKER_REASONS=0
        }
        ENTRIES=$(printf '%s' "$PARSED" | jq -r '.nodes | to_entries[] | [.key, .value.repo, (.value.pr | tostring)] | @tsv')
        PASS1=""
        while IFS=$'\t' read -r n r p; do
            [ -n "$n" ] || continue
            plan_repo=$(printf '%s' "$NODES" | jq -r --arg n "$n" '[.[] | select(.name == $n and .kind == "pr") | .repo][0] // ""')
            if [ -z "$plan_repo" ] || [ "$(coord_lower "$plan_repo")" != "$(coord_lower "$r")" ] \
                || ! coord_in_list "$plan_repo" "$REPOS"; then
                unproven "$n" "$r#$p" "outside the PLAN: not a PR node of it in that repository" other
                continue
            fi
            PASS1="$PASS1$n	$plan_repo	$p
"
        done <<<"$ENTRIES"
        # Pass 2: the one owned PR on the node's branch is the entry's.
        PASS2=""
        while IFS=$'\t' read -r n r p; do
            [ -n "$n" ] || continue
            row=$(printf '%s' "$OWNED_ROWS" | awk -F'\t' -v n="$n" '$1 == n { print $3 "\t" $4; exit }')
            st="${row%%	*}"; url="${row#*	}"
            u_repo=$(printf '%s' "$url" | sed -E 's#^https://[^/]+/([^/]+/[^/]+)/pull/[0-9]+$#\1#')
            if [ "$st" != owned ] || ! [[ $url =~ $RE_COORD_URL ]] \
                || [ "$(coord_lower "$u_repo")" != "$(coord_lower "$r")" ] || [ "${url##*/}" != "$p" ]; then
                unproven "$n" "$r#$p" "not owned on impl/$SLUG-$n (no owned PR, several, one closed unmerged, or a PR by another author, on another branch or base, or from a fork)" other
                continue
            fi
            PASS2="$PASS2$n	$r	$p	$url
"
        done <<<"$PASS1"
        # Pass 3: one live read of each owned node PR: its head, its merge
        # commit, and its marker. The head's name is oid, and the merge
        # commit's moid: the structure test bans `head=` text on any line
        # that isn't a printf output line.
        PASS3=""; i=0
        while IFS=$'\t' read -r n r p url; do
            [ -n "$n" ] || continue
            i=$((i + 1))
            N_VIEW=""
            coord_gh_read N_VIEW pr view "$p" --repo "$r" --json url,state,headRefOid,mergeCommit,body || {
                echo "$PROG: could not read $url" >&2
                exit 72
            }
            oid=$(printf '%s' "$N_VIEW" | jq -r 'if type == "object" then (.headRefOid // "") else "" end')
            [[ $oid =~ $RE_COORD_SHA ]] || { echo "$PROG: $url's head read as [$oid]" >&2; exit 72; }
            moid=$(printf '%s' "$N_VIEW" | jq -r 'if .state == "MERGED" then (.mergeCommit.oid // "") else "" end')
            # "-" for none: a tab-separated field read back must never be
            # empty, or read folds it into its neighbour.
            [[ $moid =~ $RE_COORD_SHA ]] || moid=-
            f="$WORK/node-$i.md"
            printf '%s' "$N_VIEW" | jq -j '.body // ""' > "$f" || exit 70
            # Its diagnostic for no marker or a malformed one is the case
            # below, so it goes to a file, read only when the read failed.
            mk=$("$BASH" "$COORD_SELF_DIR/run-id.sh" marker "$f" 2>"$WORK/marker.err" </dev/null)
            case $? in
                0) ;;
                67) mk=none ;;
                65) mk=malformed ;;
                *) cat "$WORK/marker.err" >&2; echo "$PROG: could not read the run marker of $url" >&2; exit 70 ;;
            esac
            PASS3="$PASS3$n	$r	$p	$url	$oid	$moid	$mk	$f
"
        done <<<"$PASS2"

        # The run's identity, in order. --adopt-run is a person's recorded
        # act, so it outranks everything. A carried run_id is the session's
        # own. The run= line is the last render's. Unanimous markers prove
        # the node PRs agree on one run. A minted id is allowed only when the
        # index names no node PR, since a fresh id would disown them.
        MARKS=$(printf '%s' "$PASS3" | awk -F'\t' 'NF >= 7 { print $7 }' | LC_ALL=C sort -u)
        if [ -n "$ADOPT" ]; then
            SOURCE=adopted; RUN_ID="$ADOPT"
        elif [ -n "$CARRIED" ]; then
            SOURCE=carried; RUN_ID="$CARRIED"
        elif [ -n "$BODY_RUN" ]; then
            SOURCE=run-line; RUN_ID="$BODY_RUN"
        elif [ -z "$UNPROVEN" ] && [ -n "$PASS3" ] && [[ $MARKS =~ $RE_COORD_RUN_ID ]]; then
            SOURCE=markers; RUN_ID="$MARKS"
        elif [ "$N_INDEX_NODES" -eq 0 ]; then
            SOURCE=minted
        fi
        while IFS=$'\t' read -r n r p url oid moid mk f; do
            [ -n "$n" ] || continue
            if [ -z "$SOURCE" ]; then
                unproven "$n" "$url" "no identity to prove it by (no carried run_id, no run= line, and the node PRs' markers don't name one run); its marker: $mk" marker
                continue
            fi
            [ "$mk" = "$RUN_ID" ] && continue
            if [ -n "$ADOPT" ]; then
                STAMPS="$STAMPS$n	$r	$p	$url	$mk	$f
"
                continue
            fi
            case "$mk" in
                none) unproven "$n" "$url" "no marker" marker ;;
                malformed) unproven "$n" "$url" "a malformed marker" marker ;;
                *) unproven "$n" "$url" "another run's marker" marker ;;
            esac
        done <<<"$PASS3"
        if [ -n "$UNPROVEN" ]; then
            hint=""
            [ "$ONLY_MARKER_REASONS" -eq 1 ] && hint=". Every reason is the marker: if these PRs are this run's, invoke again with --adopt-run <id> to stamp them"
            stop recovery-unproven "the coordination PR's index names node PRs this run can't prove are its own:$UNPROVEN
$hint"
        fi
        [ -n "$ADOPT" ] && read_login
        RECOVER_ROWS="$PASS3"

        # The follow-up lines: each kept or dropped, in order of its checks.
        # No marker is asked of one: a follow-up is a person's PR, and the
        # live read decides. A dropped one is reported on stdout with the
        # other output lines (DROPPED), never before a stop.
        C_HOST="${C_URL%/*/*/pull/*}"
        FU_IN=$(printf '%s' "$PARSED" | jq -r '.follow_ups | to_entries[] | .key as $n | .value[]
            | [$n, .repo, (.pr | tostring), ((.fu // 0) | tostring)] | @tsv')
        while IFS=$'\t' read -r n r p fu; do
            [ -n "$n" ] || continue
            durl="$C_HOST/$r/pull/$p"
            # Here-strings, not pipes: an awk that exits early would SIGPIPE
            # its producer under pipefail.
            node_row=$(awk -F'\t' -v n="$n" '$1 == n { print $2 "\t" $3; exit }' <<<"$PASS3")
            why=""
            if [ -z "$node_row" ]; then
                why="its node $n is no node PR this recovery rebuilt"
            elif [ "$(coord_lower "${node_row%%	*}")" != "$(coord_lower "$r")" ]; then
                why="it is not in its node's repository ${node_row%%	*}"
            elif [ "$fu" != "$p" ]; then
                why="its id names follow-up-$fu and its ref #$p"
            elif awk -F'\t' -v r="$(coord_lower "$r")" -v p="$p" \
                    'tolower($2) == r && $3 == p { found = 1 } END { exit !found }' <<<"$PASS3"; then
                why="it is one of the run's node PRs"
            fi
            if [ -z "$why" ]; then
                read_login
                coord_follow_up_check "${node_row%%	*}" "$p" "$LOGIN" || {
                    echo "$PROG: could not read the follow-up $durl; nothing was written" >&2
                    exit 72
                }
                durl="$FU_URL"
                case "$FU_FAULT" in
                    base) why="its base is not the repository's default branch" ;;
                    author) why="it is from a fork or another author than $LOGIN" ;;
                    closed) why="it is closed unmerged" ;;
                esac
            fi
            if [ -n "$why" ]; then
                DROPPED="${DROPPED}follow-up-dropped:$durl
"
                echo "$PROG: dropped the follow-up $durl of $n: $why" >&2
                continue
            fi
            [[ $FU_MOID =~ $RE_COORD_SHA ]] || FU_MOID=-
            FU_ROWS="$FU_ROWS$n	${node_row%%	*}	$p	$FU_OID	$FU_MOID
"
        done <<<"$FU_IN"
    fi
fi

# The records each start writes, built before any write so a --follow-up is
# checked against the record as it will stand.
case "$START_KIND" in
    existing) ;;
    new)
        DOC=$(jq -cn --arg store "$STORE" --argjson c "$C_NUM" --arg repos "$REPOS" --argjson nodes "$NODES" \
            --argjson lines "$RUN_LINES" '{"run/setup": {store: $store, coordination_pr: $c,
                repos: ($repos | split(",")), mode: "coordinated", nodes: $nodes, run_lines: $lines}}') || exit 70
        VIEW="$DOC"
        ;;
    recovered)
        # The record, in one document: the PLAN's nodes, the live heads, the
        # kept follow-ups, the cascade not run, and the recovery marker.
        DOC=$(jq -cn --argjson c "$C_NUM" --arg repos "$REPOS" --argjson nodes "$NODES" \
            --argjson lines "$RUN_LINES" --arg url "$C_URL" --arg source "$SOURCE" --arg rows "$RECOVER_ROWS" \
            --arg furows "$FU_ROWS" '
            def rows($s): [$s | split("\n")[] | select(length > 0) | split("\t")];
            {"run/setup": {store: "github", coordination_pr: $c, repos: ($repos | split(",")),
                           mode: "coordinated", nodes: $nodes, run_lines: $lines},
             "run/cascade": {verdict: "not-run"},
             "run/recovered": {pr: $url, source: $source}}
            + ([rows($rows)[]
                | {("run/node/" + .[0]): ({repo: .[1], pr: (.[2] | tonumber), head: .[4]}
                    + (if .[5] == "-" then {} else {merged_head: .[5]} end))}] | add // {})
            + ([rows($furows)[]
                | {("run/follow-up/" + .[0] + "/" + .[2]): ({repo: .[1], pr: (.[2] | tonumber), head: .[3], removed: false}
                    + (if .[4] == "-" then {} else {merged_head: .[4]} end))}] | add // {})') || exit 70
        VIEW="$DOC"
        ;;
    *) echo "$PROG: no start was decided" >&2; exit 70 ;;
esac

# The follow-up, checked against VIEW before any write. FU_DOC is its write.
FU_DOC=""; FU_REPORT=""
if [ -n "$FOLLOW_UP" ]; then
    # The node: a PR node of the run with a recorded node PR. cb_render
    # indexes follow-ups only under such a node, so one recorded anywhere
    # else would be invisible to the merge-last gate.
    FU_NODE_REPO=$(printf '%s' "$VIEW" | jq -r --arg n "$FU_NODE" '
        if has("run/node/" + $n) then
            ([(.["run/setup"].nodes // [])[] | select(.name == $n and .kind == "pr") | .repo][0] // "")
        else "" end')
    [ -n "$FU_NODE_REPO" ] || stop follow-up-node "$FU_NODE has no recorded PR in this run (a PR node of it whose PR is open or merged), so $FU_URL_IN can't be recorded against it"
    # The URL is no other PR the run already holds: a node PR, the
    # coordination PR, or a follow-up recorded under another node.
    if printf '%s' "$VIEW" | jq -e --arg r "$(coord_lower "$FU_REPO_IN")" --argjson p "$FU_NUM" --arg n "$FU_NODE" '
        any(to_entries[]; ((.key | startswith("run/node/"))
                or ((.key | startswith("run/follow-up/")) and ((.key | split("/") | .[2]) != $n)))
            and ((.value.repo // "") | ascii_downcase) == $r and .value.pr == $p)' >/dev/null; then
        stop follow-up-node "$FU_URL_IN is already this run's: a node PR, or a follow-up recorded against another node"
    fi
    if [ "$(coord_lower "$FU_REPO_IN")" = "$(coord_lower "$HOME_REPO")" ] && [ "$FU_NUM" = "$C_NUM" ]; then
        stop follow-up-node "$FU_URL_IN is the coordination PR, not a follow-up"
    fi
    if [ "$(coord_lower "$FU_REPO_IN")" != "$(coord_lower "$FU_NODE_REPO")" ]; then
        stop follow-up-repo "$FU_URL_IN is not in $FU_NODE's repository $FU_NODE_REPO"
    fi
    FU_KEY="run/follow-up/$FU_NODE/$FU_NUM"
    if [ "$REMOVE" = true ]; then
        # No live check: a closed follow-up is the one a person removes.
        printf '%s' "$VIEW" | jq -e --arg k "$FU_KEY" 'has($k)' >/dev/null \
            || stop follow-up-node "no follow-up $FU_URL_IN is recorded against $FU_NODE"
        FU_DOC=$(jq -cn --arg k "$FU_KEY" '{($k): {removed: true}}') || exit 70
        FU_REPORT="removed:$FU_URL_IN"
    else
        read_login
        coord_follow_up_check "$FU_NODE_REPO" "$FU_NUM" "$LOGIN" || {
            echo "$PROG: could not read the follow-up $FU_URL_IN; nothing was written" >&2
            exit 72
        }
        case "$FU_FAULT" in
            base) stop follow-up-base "$FU_URL is not based on $FU_NODE_REPO's default branch" ;;
            author) stop follow-up-author "$FU_URL is from a fork, or opened by another author than $LOGIN" ;;
            closed) stop follow-up-closed "$FU_URL is closed unmerged; record its replacement, or remove it with --follow-up $FU_NODE=$FU_URL --remove" ;;
        esac
        # The node's repository as run/setup spells it: run-record.sh's
        # check that the repository is in the write set is exact.
        FU_DOC=$(jq -cn --arg k "$FU_KEY" --arg r "$FU_NODE_REPO" --argjson p "$FU_NUM" --arg h "$FU_OID" \
            '{($k): {repo: $r, pr: $p, head: $h, removed: false}}') || exit 70
        FU_REPORT="recorded:$FU_URL"
    fi
fi

# Every fixed key checked before any write, so a refusal leaves the earlier
# record whole.
for pair in "repos=$REPOS" "home_repo=$HOME_REPO" "coord_branch=$CB" "plan_abs=$PLAN_ABS"; do
    k="${pair%%=*}"; v="${pair#*=}"
    old=$(koto context get "$SESSION" "$k") || old=""
    if [ -n "$old" ] && [ "$old" != "$v" ]; then
        echo "$PROG: $k is already recorded as [$old] for this run; refusing to change it to [$v]" >&2
        exit 68
    fi
done

# rr_write <setup|adopt|recover|follow-up> <json> -- one run-record.sh write,
# from a file. Each verb is called by name (the structure test resolves every
# call's verb to its owner).
rr_write() {
    local doc rc
    doc=$(mktemp "${TMPDIR:-/tmp}/record-coord-setup.XXXXXX") || exit 70
    printf '%s' "$2" > "$doc" || { rm -f "$doc"; exit 70; }
    case "$1" in
        setup) "$BASH" "$COORD_SELF_DIR/run-record.sh" setup --session "$SESSION" --json "$doc" </dev/null >&2 ;;
        adopt) "$BASH" "$COORD_SELF_DIR/run-record.sh" adopt --session "$SESSION" --json "$doc" </dev/null >&2 ;;
        recover) "$BASH" "$COORD_SELF_DIR/run-record.sh" recover --session "$SESSION" --json "$doc" </dev/null >&2 ;;
        follow-up) "$BASH" "$COORD_SELF_DIR/run-record.sh" follow-up --session "$SESSION" --json "$doc" </dev/null >&2 ;;
        *) false ;;
    esac
    rc=$?
    rm -f "$doc"
    if [ "$rc" -ne 0 ]; then
        echo "$PROG: the run record's $1 write exited $rc; the run record was not written" >&2
        exit 70
    fi
}
mint_run_id() {
    "$BASH" "$COORD_SELF_DIR/run-id.sh" mint "$SESSION" </dev/null >/dev/null || {
        echo "$PROG: could not mint this run's identity in session $SESSION" >&2
        exit 70
    }
}

case "$START_KIND" in
    existing)
        # A crash between an earlier seal and its mint is repaired here; an
        # id the session holds is kept.
        mint_run_id
        ;;
    new)
        rr_write setup "$DOC"
        # After the seal: a seal that fails leaves no run_id behind to read
        # as a started run on the next start.
        mint_run_id
        ;;
    recovered)
        # Adopt's stamps, the one GitHub write before the record, after every
        # check passed and only on PRs that passed the ownership lookup.
        while IFS=$'\t' read -r n r p url mk f; do
            [ -n "$n" ] || continue
            if [ "$mk" = none ]; then
                "$BASH" "$COORD_SELF_DIR/run-id.sh" stamp "$RUN_ID" "$f" </dev/null >&2
            else
                "$BASH" "$COORD_SELF_DIR/run-id.sh" restamp "$RUN_ID" "$f" </dev/null >&2
            fi
            ok=$?
            if [ "$ok" -eq 0 ]; then
                gh pr edit "$p" --repo "$r" --body-file "$f" </dev/null >&2
                ok=$?
            fi
            if [ "$ok" -eq 0 ]; then
                S_VIEW=""
                if coord_gh_read S_VIEW pr view "$p" --repo "$r" --json body; then
                    printf '%s' "$S_VIEW" | jq -j '.body // ""' > "$f.after" \
                        && [ "$("$BASH" "$COORD_SELF_DIR/run-id.sh" marker "$f.after" </dev/null)" = "$RUN_ID" ] || ok=1
                else
                    ok=1
                fi
            fi
            if [ "$ok" -ne 0 ]; then
                printf 'stop=recovery-unproven\n'
                echo "$PROG: stopped (recovery-unproven): $n ($url) is not stampable: its marker could not be set to $RUN_ID. No run record was written; stamps already made on other PRs stay, and a re-run with the same --adopt-run finds them marked and edits them no more." >&2
                exit 71
            fi
        done <<<"$STAMPS"
        # The writes run in this order for two reasons. `run-record.sh
        # adopt` refuses once run/setup exists, so run/adopted has to come
        # before the recover document that seals it. And the identity comes
        # first of all: a crash after it leaves a carried run_id, so the next
        # start recovers again under the same id. Written after the record,
        # a crash between the two would leave a record with no id, which the
        # next start (record=existing) would mint afresh, losing the run's
        # identity.
        # 1. The identity.
        case "$SOURCE" in
            adopted)
                "$BASH" "$COORD_SELF_DIR/run-id.sh" adopt "$SESSION" "$RUN_ID" </dev/null \
                    || { echo "$PROG: could not adopt run id $RUN_ID in session $SESSION" >&2; exit 70; }
                ;;
            run-line|markers)
                "$BASH" "$COORD_SELF_DIR/run-id.sh" seed "$SESSION" "$RUN_ID" </dev/null \
                    || { echo "$PROG: could not record run id $RUN_ID in session $SESSION" >&2; exit 70; }
                ;;
            minted) mint_run_id ;;
            carried) ;;
            *) echo "$PROG: no identity source was chosen" >&2; exit 70 ;;
        esac
        # 2. Who adopted the run, and when.
        if [ "$SOURCE" = adopted ]; then
            rr_write adopt "$(jq -cn --arg id "$RUN_ID" --arg login "$LOGIN" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                '{"run/adopted": {id: $id, login: $login, at: $at}}')" || exit 70
        fi
        # 3. The record, in one document.
        rr_write recover "$DOC"
        # 4. This invocation recovered: the terminal result reports it.
        printf '%s' "$C_URL" | koto context add "$SESSION" recovered >/dev/null || {
            echo "$PROG: could not write context key recovered in session $SESSION" >&2
            exit 70
        }
        ;;
esac
# The follow-up, once the record it joins exists.
[ -n "$FU_DOC" ] && rr_write follow-up "$FU_DOC"

record_fixed_key() { # record_fixed_key <key> <value>
    local old
    old=$(koto context get "$SESSION" "$1") || old=""
    if [ -n "$old" ]; then
        [ "$old" = "$2" ] && return 0
        echo "$PROG: $1 is already recorded as [$old] for this run; refusing to change it to [$2]" >&2
        exit 68
    fi
    printf '%s' "$2" | koto context add "$SESSION" "$1" >/dev/null || {
        echo "$PROG: could not write context key $1 in session $SESSION" >&2
        exit 70
    }
}
record_fixed_key plan_abs "$PLAN_ABS"
record_fixed_key coord_branch "$CB"
record_fixed_key home_repo "$HOME_REPO"
# Last: coord_setup's gates read repos, so a partial write never passes.
record_fixed_key repos "$REPOS"

printf 'repos=%s\nhome_repo=%s\ncoord_branch=%s\nplan_abs=%s\n' "$REPOS" "$HOME_REPO" "$CB" "$PLAN_ABS"
printf 'store=%s\ncoordination_pr=%s\nrecord=%s\n' "$STORE" "$C_URL" "$START_KIND"
[ "$START_KIND" = recovered ] && printf 'recovered=%s\n' "$C_URL"
[ -n "$DROPPED" ] && printf '%s' "$DROPPED"
if [ -n "$FU_REPORT" ]; then
    printf 'follow-up=%s\n' "$FU_REPORT"
    # The body shows the follow-up's line, or no longer shows it. The
    # render's result never changes this exit: a body it couldn't post is
    # rendered again at the next transition, and the coordination steps
    # render before they read it.
    RENDER_OUT=$("$BASH" "$COORD_SELF_DIR/coord-render.sh" --session "$SESSION" --slug "$SLUG" \
        --home-repo "$HOME_REPO" --coord-branch "$CB" </dev/null)
    RENDER_RC=$?
    [ -n "$RENDER_OUT" ] && printf '%s\n' "$RENDER_OUT"
    if ! grep -q '^body=' <<<"$RENDER_OUT"; then
        if [ "$RENDER_RC" -eq 77 ]; then
            printf 'body=refused:execute:visibility\n'
        else
            printf 'body=stale\n'
        fi
    fi
fi
exit 0
