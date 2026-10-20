#!/usr/bin/env bash
# record-coord-setup.sh — for /execute: fix a coordinated run's write set and
# coordination home at start, and seal its run record, or rebuild one a run
# lost.
#
# execute-coordinated.md's `coord_setup` state is agent-run: the agent runs
# this script in the coordination checkout (the checkout holding the
# coordination branch and the PLAN), then ticks. The state's non-overridable
# context-matches gates read back what it wrote, so a run that could not
# record its write set never reaches the loop.
#
# It records four context keys:
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
# the write set mid-run.
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
#   already marked and makes no edit. That is the one GitHub write this script
#   makes, and it runs only after every check passed. Then it writes, in
#   order: the identity (run-id.sh adopt, seed or mint; a carried one stays),
#   run/adopted {id, login, at} with --adopt-run (`run-record.sh adopt`), and
#   one `run-record.sh recover` document: run/setup (store github, the
#   coordination PR's number, repos, the PLAN's nodes, the body's run lines),
#   run/node/<node> {repo, pr, head: the live headRefOid, merged_head: the
#   live merge commit when MERGED}, run/cascade {verdict: not-run} and
#   run/recovered {pr: the coordination PR's URL, source}. Then the
#   `recovered` context key (the URL; the opener removes it at every
#   invocation's start). No head the body names is ever recorded. Follow-up
#   lines are read, and count as started, but none is recorded yet.
#
# Every check runs before any write, so a stop changes no key and, adopt's
# stamps aside, nothing on GitHub.
#
# --follow-up and --follow-up-remove are accepted and reported
# `ignored=<flag>` (follow-ups are a later change); they change nothing.
#
# Usage: record-coord-setup.sh --session <koto-session> --plan <path>
#            [--store <github|session>] [--coordination-pr <url>]
#            [--follow-up <node>=<url>] [--follow-up-remove true]
#            [--adopt-run <id>]
#
# Each optional value may be empty (the template passes its rebind variables
# verbatim), which is the same as leaving the flag out.
#
# Output: `repos=`, `home_repo=`, `coord_branch=`, `plan_abs=`, `store=`,
# `coordination_pr=<url>`, `record=new|existing|recovered` lines on stdout,
# `recovered=<url>` after a recovery, and `ignored=follow-up`,
# `ignored=remove` for each inert flag given. A typed stop prints only
# `stop=<code>`: store-mismatch, coordination-pr-missing,
# coordination-pr-ambiguous, coordination-pr-mismatch,
# coordination-pr-closed, session-absent, recovery-unproven,
# recovery-plan-gone, coordination-index-missing, coordination-body-full,
# adopt-run-refused.
#
# Exit codes:
#   0   recorded (or already recorded with the same values)
#   64  usage error
#   65  HEAD is detached
#   66  a value is outside its pattern, or this checkout's owner/repo could
#       not be read
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
RE_FOLLOW_UP='^([a-z][a-z0-9-]*=https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*)?$'
RE_REMOVE='^(true)?$'
RE_ADOPT='^([0-9a-f]{32})?$'
RE_LOGIN='^[A-Za-z0-9](-?[A-Za-z0-9]){0,38}$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: record-coord-setup.sh --session <koto-session> --plan <path> [--store <github|session>] [--coordination-pr <url>] [--follow-up <node>=<url>] [--follow-up-remove true] [--adopt-run <id>]" >&2
    exit 64
}

stop() { # stop <code> <why> -- a typed stop: nothing has been written
    printf 'stop=%s\n' "$1"
    echo "$PROG: stopped ($1): $2. Nothing was written." >&2
    exit 71
}

SESSION=""; PLAN=""; STORE=""; CPR=""; FOLLOW_UP=""; REMOVE=""; ADOPT=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
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
[[ $FOLLOW_UP =~ $RE_FOLLOW_UP ]] || usage_error "--follow-up [$FOLLOW_UP] is not <node>=<pull request URL>"
[[ $REMOVE =~ $RE_REMOVE ]] || usage_error "--follow-up-remove [$REMOVE] is not true"
[[ $ADOPT =~ $RE_ADOPT ]] || usage_error "--adopt-run [$ADOPT] is not a run id"

PLAN_PRESENT=0
[ -f "$PLAN" ] && PLAN_PRESENT=1
SLUG=$(basename -- "$PLAN" .md)
SLUG=${SLUG#PLAN-}

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

# The run record.
SETUP=$(rr_setup "$SESSION")
case $? in
    0) RECORD=existing ;;
    1) RECORD=none ;;
    *) echo "$PROG: could not read the run record in session $SESSION" >&2; exit 70 ;;
esac

RUN_LINES='{}'; NODES='[]'; RECOVER_ROWS=""; SOURCE=""; RUN_ID=""; STAMPS=""; LOGIN=""

if [ "$RECORD" = existing ]; then
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
    VIEW=""
    coord_gh_read VIEW pr view "$C_NUM" --repo "$HOME_REPO" --json state,url || {
        echo "$PROG: could not read the recorded coordination PR #$C_NUM in $HOME_REPO" >&2
        exit 72
    }
    C_STATE=$(printf '%s' "$VIEW" | jq -r 'if type == "object" then (.state // "") else "" end')
    C_URL=$(printf '%s' "$VIEW" | jq -r 'if type == "object" then (.url // "") else "" end')
    case "$C_STATE" in
        OPEN|MERGED) ;;
        CLOSED) stop coordination-pr-closed "the recorded coordination PR $C_URL is closed unmerged" ;;
        *) echo "$PROG: the recorded coordination PR's state read as [$C_STATE]" >&2; exit 72 ;;
    esac
    [[ $C_URL =~ $RE_COORD_URL ]] || { echo "$PROG: the recorded coordination PR's URL read as [$C_URL]" >&2; exit 72; }
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
                            VIEW=""
                            coord_gh_read VIEW pr view "$CPR_NUM" --repo "$HOME_REPO" --json state,headRefName,body || exit 72
                            if printf '%s' "$VIEW" | jq -e --arg cb "$CB" --arg m "$COORD_MARKER" \
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

    # R8: had a run started?
    STARTED=0
    [ -n "$CARRIED" ] && STARTED=1
    [ -n "$BODY_RUN" ] && STARTED=1
    [ "$N_INDEX_NODES" -gt 0 ] && STARTED=1
    [ "$N_INDEX_FUS" -gt 0 ] && STARTED=1
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
        RECORD=new
    elif [ "$STORE" = session ]; then
        stop session-absent "this run keeps its record in its execute session, which isn't in this workspace. Bring it here with skill-session.sh import execute $SLUG --from <workspace>, or run /execute where that session lives"
    else
        RECORD=recovered
        if [ "$PLAN_PRESENT" -eq 0 ]; then
            if [ "$N_INDEX_NODES" -eq 0 ] && [ "$N_INDEX_FUS" -eq 0 ]; then
                stop coordination-index-missing "the PLAN [$PLAN] is gone and $C_URL holds no PR Index line to rebuild the run from"
            fi
            stop recovery-plan-gone "the PLAN [$PLAN] was deleted by the cascade; only the coordination merge is left: merge $C_URL by hand, or import the run's session"
        fi
        if [ "$N_INDEX_NODES" -eq 0 ] && [ -n "$OWNED_NODES" ]; then
            stop coordination-index-missing "$C_URL holds no node in its PR Index, but $OWNED_NODES have an owned PR on their branches"
        fi
        if [ "$N_INDEX_FUS" -gt 0 ]; then
            echo "$PROG: the coordination PR's index names follow-up PRs; follow-up lines are not recovered yet, so none is recorded" >&2
        fi

        # Pass 1, no GitHub read: each index node is a PR node of the PLAN, in
        # that node's repository.
        UNPROVEN=""; NONMARKER=0
        unproven() { # unproven <node> <where> <reason> <marker-reason 0|1>
            UNPROVEN="$UNPROVEN
  $1 ($2): $3"
            [ "$4" -eq 1 ] || NONMARKER=1
        }
        ENTRIES=$(printf '%s' "$PARSED" | jq -r '.nodes | to_entries[] | [.key, .value.repo, (.value.pr | tostring)] | @tsv')
        PASS1=""
        while IFS=$'\t' read -r n r p; do
            [ -n "$n" ] || continue
            plan_repo=$(printf '%s' "$NODES" | jq -r --arg n "$n" '[.[] | select(.name == $n and .kind == "pr") | .repo][0] // ""')
            if [ -z "$plan_repo" ] || [ "$(coord_lower "$plan_repo")" != "$(coord_lower "$r")" ] \
                || ! coord_in_list "$plan_repo" "$REPOS"; then
                unproven "$n" "$r#$p" "outside the PLAN: not a PR node of it in that repository" 0
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
                unproven "$n" "$r#$p" "not owned on impl/$SLUG-$n (no owned PR, several, one closed unmerged, or a PR by another author, on another branch or base, or from a fork)" 0
                continue
            fi
            PASS2="$PASS2$n	$r	$p	$url
"
        done <<<"$PASS1"
        # Pass 3: one live read of each owned node PR: its head, its merge
        # commit, and its marker.
        PASS3=""; i=0
        while IFS=$'\t' read -r n r p url; do
            [ -n "$n" ] || continue
            i=$((i + 1))
            VIEW=""
            coord_gh_read VIEW pr view "$p" --repo "$r" --json url,state,headRefOid,mergeCommit,body || {
                echo "$PROG: could not read $url" >&2
                exit 72
            }
            oid=$(printf '%s' "$VIEW" | jq -r 'if type == "object" then (.headRefOid // "") else "" end')
            [[ $oid =~ $RE_COORD_SHA ]] || { echo "$PROG: $url's head read as [$oid]" >&2; exit 72; }
            moid=$(printf '%s' "$VIEW" | jq -r 'if .state == "MERGED" then (.mergeCommit.oid // "") else "" end')
            # "-" for none: a tab-separated field read back must never be
            # empty, or read folds it into its neighbour.
            [[ $moid =~ $RE_COORD_SHA ]] || moid=-
            f="$WORK/node-$i.md"
            printf '%s' "$VIEW" | jq -j '.body // ""' > "$f" || exit 70
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

        # The run's identity, in order: --adopt-run, the carried run_id, the
        # body's run line, the one id every node PR's marker names, and a
        # minted one only when the index holds no node line.
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
                unproven "$n" "$url" "no identity to prove it by (no carried run_id, no run= line, and the node PRs' markers don't name one run); its marker: $mk" 1
                continue
            fi
            [ "$mk" = "$RUN_ID" ] && continue
            if [ -n "$ADOPT" ]; then
                STAMPS="$STAMPS$n	$r	$p	$url	$mk	$f
"
                continue
            fi
            case "$mk" in
                none) unproven "$n" "$url" "no marker" 1 ;;
                malformed) unproven "$n" "$url" "a malformed marker" 1 ;;
                *) unproven "$n" "$url" "another run's marker" 1 ;;
            esac
        done <<<"$PASS3"
        if [ -n "$UNPROVEN" ]; then
            hint=""
            [ "$NONMARKER" -eq 0 ] && hint=". Every reason is the marker: if these PRs are this run's, invoke again with --adopt-run <id> to stamp them"
            stop recovery-unproven "the coordination PR's index names node PRs this run can't prove are its own:$UNPROVEN
$hint"
        fi
        if [ -n "$ADOPT" ]; then
            coord_gh_read LOGIN api user --jq .login || { echo "$PROG: could not read the authenticated login" >&2; exit 72; }
            [[ $LOGIN =~ $RE_LOGIN ]] || { echo "$PROG: the authenticated login read as [$LOGIN]" >&2; exit 72; }
        fi
        RECOVER_ROWS="$PASS3"
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

# run_record <setup|adopt|recover> <json> -- one run-record.sh write, from a
# file. Each verb is called by name (the structure test resolves every call's
# verb to its owner).
run_record() {
    local doc rc
    doc=$(mktemp "${TMPDIR:-/tmp}/record-coord-setup.XXXXXX") || exit 70
    printf '%s' "$2" > "$doc" || { rm -f "$doc"; exit 70; }
    case "$1" in
        setup) "$BASH" "$COORD_SELF_DIR/run-record.sh" setup --session "$SESSION" --json "$doc" </dev/null >&2 ;;
        adopt) "$BASH" "$COORD_SELF_DIR/run-record.sh" adopt --session "$SESSION" --json "$doc" </dev/null >&2 ;;
        recover) "$BASH" "$COORD_SELF_DIR/run-record.sh" recover --session "$SESSION" --json "$doc" </dev/null >&2 ;;
        *) false ;;
    esac
    rc=$?
    rm -f "$doc"
    if [ "$rc" -ne 0 ]; then
        echo "$PROG: the run record's $1 write exited $rc; the run record was not written" >&2
        exit 70
    fi
}
mint() {
    "$BASH" "$COORD_SELF_DIR/run-id.sh" mint "$SESSION" </dev/null >/dev/null || {
        echo "$PROG: could not mint this run's identity in session $SESSION" >&2
        exit 70
    }
}

case "$RECORD" in
    existing)
        # A crash between an earlier seal and its mint is repaired here; an
        # id the session holds is kept.
        mint
        ;;
    new)
        DOC=$(jq -cn --arg store "$STORE" --argjson c "$C_NUM" --arg repos "$REPOS" --argjson nodes "$NODES" \
            --argjson lines "$RUN_LINES" '{"run/setup": {store: $store, coordination_pr: $c,
                repos: ($repos | split(",")), mode: "coordinated", nodes: $nodes, run_lines: $lines}}') || exit 70
        run_record setup "$DOC"
        # After the seal: a seal that fails leaves no run_id behind to read
        # as a started run on the next start.
        mint
        ;;
    recovered)
        # Adopt's stamps, the one GitHub write, after every check passed and
        # only on PRs that passed the ownership lookup.
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
                VIEW=""
                if coord_gh_read VIEW pr view "$p" --repo "$r" --json body; then
                    printf '%s' "$VIEW" | jq -j '.body // ""' > "$f.after" \
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
            minted) mint ;;
            carried) ;;
        esac
        # 2. Who adopted the run, and when.
        if [ "$SOURCE" = adopted ]; then
            run_record adopt "$(jq -cn --arg id "$RUN_ID" --arg login "$LOGIN" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                '{"run/adopted": {id: $id, login: $login, at: $at}}')" || exit 70
        fi
        # 3. The record, in one document: the PLAN's nodes, the live heads,
        # the cascade not run, and the recovery marker.
        DOC=$(jq -cn --argjson c "$C_NUM" --arg repos "$REPOS" --argjson nodes "$NODES" \
            --argjson lines "$RUN_LINES" --arg url "$C_URL" --arg source "$SOURCE" --arg rows "$RECOVER_ROWS" '
            {"run/setup": {store: "github", coordination_pr: $c, repos: ($repos | split(",")),
                           mode: "coordinated", nodes: $nodes, run_lines: $lines},
             "run/cascade": {verdict: "not-run"},
             "run/recovered": {pr: $url, source: $source}}
            + ([$rows | split("\n")[] | select(length > 0) | split("\t")
                | {("run/node/" + .[0]): ({repo: .[1], pr: (.[2] | tonumber), head: .[4]}
                    + (if .[5] == "-" then {} else {merged_head: .[5]} end))}] | add // {})') || exit 70
        run_record recover "$DOC"
        # 4. This invocation recovered: the terminal result reports it.
        printf '%s' "$C_URL" | koto context add "$SESSION" recovered >/dev/null || {
            echo "$PROG: could not write context key recovered in session $SESSION" >&2
            exit 70
        }
        ;;
esac

record() { # record <key> <value>
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
record plan_abs "$PLAN_ABS"
record coord_branch "$CB"
record home_repo "$HOME_REPO"
# Last: coord_setup's gates read repos, so a partial write never passes.
record repos "$REPOS"

printf 'repos=%s\nhome_repo=%s\ncoord_branch=%s\nplan_abs=%s\n' "$REPOS" "$HOME_REPO" "$CB" "$PLAN_ABS"
printf 'store=%s\ncoordination_pr=%s\nrecord=%s\n' "$STORE" "$C_URL" "$RECORD"
[ "$RECORD" = recovered ] && printf 'recovered=%s\n' "$C_URL"
[ -n "$FOLLOW_UP" ] && printf 'ignored=follow-up\n'
[ -n "$REMOVE" ] && printf 'ignored=remove\n'
exit 0
