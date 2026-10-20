#!/usr/bin/env bash
# record-coord-setup.sh — for /execute: fix a coordinated run's write set and
# coordination home at start, and seal its run record.
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
# The run record. On a new run (no run/setup in the session) it finds the
# coordination PR through the ownership lookup (owned-pr.sh on home_repo and
# the coordination branch, carrying the declaration marker), checks a
# --coordination-pr against what the lookup found, and seals run/setup
# through `run-record.sh setup`: the store (--store, else github), the
# coordination PR's number, repos, mode `coordinated`, the node list from the
# PLAN ({name, kind, repo, waits_on}, in plan-to-tasks.sh's order), and
# /scope's run lines (the `topic=`, `exit=`, `outcome=`, `intent=`, `mode=`
# lines above the coordination PR body's first `## ` heading, the first of
# each). It mints the run's identity then (`run-id.sh mint`, which keeps an id
# the opener carried or seeded). On a later invocation (run/setup present) it
# makes no lookup: it compares --store with the sealed store, a
# --coordination-pr with the recorded number, and reads the recorded PR's
# state, refusing a closed one. Every check runs before any write, so a stop
# changes no key.
#
# --follow-up, --follow-up-remove and --adopt-run are accepted and reported
# `ignored=<flag>` (follow-ups and recovery are later changes); they change
# nothing.
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
# `coordination_pr=<url>`, `record=new|existing` lines on stdout, and
# `ignored=follow-up`, `ignored=remove`, `ignored=adopt-run` for each inert
# flag given. A typed stop prints only `stop=<code>`: store-mismatch,
# coordination-pr-missing, coordination-pr-ambiguous,
# coordination-pr-mismatch, coordination-pr-closed.
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

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_STORE='^(github|session)?$'
RE_URL_OPT='^(https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*)?$'
RE_FOLLOW_UP='^([a-z][a-z0-9-]*=https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*)?$'
RE_REMOVE='^(true)?$'
RE_ADOPT='^([0-9a-f]{32})?$'

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
[ -f "$PLAN" ] || usage_error "no PLAN at [$PLAN]"
[[ $STORE =~ $RE_STORE ]] || usage_error "--store [$STORE] is not github or session"
[[ $CPR =~ $RE_URL_OPT ]] || usage_error "--coordination-pr [$CPR] is not a pull request URL"
[[ $FOLLOW_UP =~ $RE_FOLLOW_UP ]] || usage_error "--follow-up [$FOLLOW_UP] is not <node>=<pull request URL>"
[[ $REMOVE =~ $RE_REMOVE ]] || usage_error "--follow-up-remove [$REMOVE] is not true"
[[ $ADOPT =~ $RE_ADOPT ]] || usage_error "--adopt-run [$ADOPT] is not a run id"

# repos, from the nodes.
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
    | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p' | head -1)
if [ -z "$DEFAULT" ]; then
    DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD || true)
    DEFAULT=${DEFAULT#origin/}
fi
if [ -n "$DEFAULT" ]; then
    [ "$CB" = "$DEFAULT" ] && { echo "$PROG: [$CB] is the default branch, not a coordination branch" >&2; exit 67; }
else
    case "$CB" in main|master) echo "$PROG: [$CB] is a default branch name, not a coordination branch" >&2; exit 67 ;; esac
fi

# plan_abs.
PLAN_DIR=$(CDPATH='' cd "$(dirname -- "$PLAN")" && pwd -P) || exit 69
PLAN_ABS="$PLAN_DIR/$(basename -- "$PLAN")"
case "$PLAN_ABS" in /*) ;; *) echo "$PROG: [$PLAN_ABS] is not absolute" >&2; exit 66 ;; esac
case "$PLAN_ABS" in *"
"*) echo "$PROG: the PLAN path holds a newline" >&2; exit 66 ;; esac

# The run's identity, when the opener carried one in: the ownership lookup
# carries it. Absent on a new run's first setup, when the lookup matches by
# login and branch alone (the coordination PR is /scope's and carries no
# marker anyway).
COORD_RUN_ID=$("$BASH" "$COORD_SELF_DIR/run-id.sh" get "$SESSION" 2>/dev/null </dev/null)
case $? in
    0) ;;
    67) COORD_RUN_ID="" ;;
    *) echo "$PROG: could not read run_id in session $SESSION" >&2; exit 70 ;;
esac

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
    1) RECORD=new ;;
    *) echo "$PROG: could not read the run record in session $SESSION" >&2; exit 70 ;;
esac

if [ "$RECORD" = existing ]; then
    SEALED_STORE=$(printf '%s' "$SETUP" | jq -r '.store // ""')
    SEALED_REPOS=$(printf '%s' "$SETUP" | jq -r '(.repos // []) | join(",")')
    C_NUM=$(printf '%s' "$SETUP" | jq -r '.coordination_pr // ""')
    [[ $C_NUM =~ ^[1-9][0-9]*$ ]] || { echo "$PROG: run/setup holds no coordination PR number" >&2; exit 70; }
    if [ -n "$STORE" ] && [ "$STORE" != "$SEALED_STORE" ]; then
        stop store-mismatch "this run's store is sealed as $SEALED_STORE, and this invocation asked for $STORE"
    fi
    STORE="$SEALED_STORE"
    if [ "$REPOS" != "$SEALED_REPOS" ]; then
        echo "$PROG: the run record's repos are [$SEALED_REPOS]; the PLAN's nodes now name [$REPOS]; refusing to change the write set" >&2
        exit 68
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
    C_STATE=$(printf '%s' "$VIEW" | jq -r 'if type == "object" then (.state // "") else "" end' 2>/dev/null)
    C_URL=$(printf '%s' "$VIEW" | jq -r 'if type == "object" then (.url // "") else "" end' 2>/dev/null)
    case "$C_STATE" in
        OPEN|MERGED) ;;
        CLOSED) stop coordination-pr-closed "the recorded coordination PR $C_URL is closed unmerged" ;;
        *) echo "$PROG: the recorded coordination PR's state read as [$C_STATE]" >&2; exit 72 ;;
    esac
    [[ $C_URL =~ $RE_COORD_URL ]] || { echo "$PROG: the recorded coordination PR's URL read as [$C_URL]" >&2; exit 72; }
else
    # A new run: the ownership lookup, once.
    coord_find_pr "$HOME_REPO" "$CB" open
    case $? in
        0) ;;
        2) exit 72 ;;
        *)
            case "$C_WHY" in
                several) stop coordination-pr-ambiguous "several owned coordination PRs on $HOME_REPO $CB, or an ambiguous lookup" ;;
                *)
                    if [ -n "$CPR" ]; then
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
    [ -n "$STORE" ] || STORE=github
    # /scope's run lines: above the body's first `## ` heading, the first of
    # each key. The one read of the body outside the renderer's codec.
    RUN_LINES=$(printf '%s' "$C_JSON" | jq -r '.body // ""' | awk '
        { sub(/\r$/, "") }
        /^## / { exit }
        /^(topic|exit|outcome|intent|mode)=[A-Za-z0-9._-]+$/ {
            k = $0; sub(/=.*/, "", k); v = substr($0, length(k) + 2)
            if (length(v) <= 64 && !(k in seen)) { seen[k] = 1; print k "\t" v }
        }' | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}') || {
        echo "$PROG: could not read the coordination PR's run lines" >&2
        exit 72
    }
    NODES=$(printf '%s' "$TASKS" | jq -c '[.[] | {name, kind: (.vars.NODE_KIND // "pr"), repo: (.vars.REPO // ""), waits_on: (.waits_on // [])}]') || exit 69
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

if [ "$RECORD" = new ]; then
    "$BASH" "$COORD_SELF_DIR/run-id.sh" mint "$SESSION" </dev/null >/dev/null || {
        echo "$PROG: could not mint this run's identity in session $SESSION" >&2
        exit 70
    }
    DOC=$(mktemp "${TMPDIR:-/tmp}/record-coord-setup.XXXXXX") || exit 70
    jq -cn --arg store "$STORE" --argjson c "$C_NUM" --arg repos "$REPOS" --argjson nodes "$NODES" \
        --argjson lines "$RUN_LINES" '{"run/setup": {store: $store, coordination_pr: $c,
            repos: ($repos | split(",")), mode: "coordinated", nodes: $nodes, run_lines: $lines}}' > "$DOC" || {
        rm -f "$DOC"; exit 70
    }
    "$BASH" "$COORD_SELF_DIR/run-record.sh" setup --session "$SESSION" --json "$DOC" </dev/null >&2
    rc=$?
    rm -f "$DOC"
    if [ "$rc" -ne 0 ]; then
        echo "$PROG: run-record.sh setup exited $rc; the run record was not sealed" >&2
        exit 70
    fi
fi

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
[ -n "$FOLLOW_UP" ] && printf 'ignored=follow-up\n'
[ -n "$REMOVE" ] && printf 'ignored=remove\n'
[ -n "$ADOPT" ] && printf 'ignored=adopt-run\n'
exit 0
