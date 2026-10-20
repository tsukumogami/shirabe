# coord-common.sh — shared pieces of /execute's coordinated loop scripts.
#
# Sourced, never run: coordinated-next.sh and coordination-verdict.sh share
# the one computation of where a coordinated run stands (coord_compute), and
# node-push.sh and coord-merge.sh share the coordination-PR read. Keeping them
# in one file is what stops the loop's next action and the verdict it ends on
# from disagreeing about the same state.
#
# Callers set PROG before sourcing and set -uo pipefail themselves.
#
# The run record. The run's control-plane facts (the node list, each node's
# PR and pushed head, the cascade's verdict, the coordination PR's number)
# live as `run/` keys in the run's koto session, written only through
# run-record.sh and read through run-record-lib.sh, which this file sources.
# coord_compute and coord-merge.sh read them from there, never from the
# coordination PR's body.
#
# The coordination PR's body is the record's rendering, built and posted by
# coord-render.sh through scripts/lib/coordination-body.sh, the one codec of
# its PR index. Nothing here reads or writes the index.
#
# Callers set COORD_SELF_DIR (this directory) before sourcing.
#
# Every owned-PR lookup here goes through coord_owned, which carries the run's
# identity (owned-pr.sh --run-id) when the caller set COORD_RUN_ID: from its
# own --run-id flag (coordinated-next.sh, coordination-verdict.sh,
# node-push.sh), or from its session through run-id.sh (coord-merge.sh,
# record-coordination-verdict.sh). Empty means a hand run, and owned-pr.sh then
# matches by login and branch alone. record-coord-setup.sh's recovery empties
# it on purpose for its node-branch lookups, so a PR another run marked is
# found and its marker read rather than refused.
#
# Requires: bash 3.2+, jq, gh (through owned-pr.sh and the reads below), koto
# (the run record's reads).

# The run record's reader. The coordinate skill's reconcile scripts source
# this file for its patterns alone, and their tests copy it without its
# siblings, so the reader is sourced only where it sits beside this file.
if [ -f "$COORD_SELF_DIR/run-record-lib.sh" ]; then
    # shellcheck source=run-record-lib.sh
    . "$COORD_SELF_DIR/run-record-lib.sh"
fi

COORD_MARKER='This is a **coordination PR**'
COORD_RUN_ID=""
RE_COORD_RUN_ID='^[0-9a-f]{32}$'
# The PLAN's node list, from /plan's script: the one cross-skill path the
# coordinated scripts share.
COORD_PLAN_TO_TASKS="$COORD_SELF_DIR/../../plan/scripts/plan-to-tasks.sh"

RE_COORD_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_COORD_REPO_LIST='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)*$'
RE_COORD_BRANCH='^[A-Za-z0-9._/-]+$'
RE_COORD_SLUG='^[a-z0-9-]+$'
# plan-to-tasks.sh's node-name pattern (R9).
RE_COORD_NODE='^[a-z][a-z0-9-]*$'
RE_COORD_SHA='^[0-9a-f]{40}$'
RE_COORD_URL='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$'
# merge_attempts: <node>:<result> entries, comma-joined. merge-not-observed,
# merge-call-failed and merge-refused come from coord-merge.sh; body-stale and
# body-full only for node `coordination`, from coord-render.sh
# --before-coordination, when the body CI's merge-last gate reads could not
# be brought up to date with the record.
RE_COORD_ATTEMPT_VALUE='(merge-not-observed|merge-call-failed|merge-refused|body-stale|body-full)'
RE_COORD_ATTEMPTS="^([a-z][a-z0-9-]*:$RE_COORD_ATTEMPT_VALUE)(,[a-z][a-z0-9-]*:$RE_COORD_ATTEMPT_VALUE)*\$"

coord_valid_repo() {
    [[ $1 =~ $RE_COORD_REPO ]] || return 1
    case "/$1/" in */./*|*/../*) return 1 ;; esac
    return 0
}

coord_valid_branch() {
    [[ $1 =~ $RE_COORD_BRANCH ]] || return 1
    case "$1" in -*|/*|*..*|*/) return 1 ;; esac
    return 0
}

coord_valid_repo_list() {
    local r rest
    [[ $1 =~ $RE_COORD_REPO_LIST ]] || return 1
    rest="$1"
    while [ -n "$rest" ]; do
        r="${rest%%,*}"
        if [ "$r" = "$rest" ]; then rest=""; else rest="${rest#*,}"; fi
        coord_valid_repo "$r" || return 1
    done
    return 0
}

# coord_in_list <item> <comma-list> -- exact membership.
coord_in_list() {
    case ",$2," in *",$1,"*) return 0 ;; esac
    return 1
}

# coord_lower <s>
coord_lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# coord_git_common_dir <dir> -- the physical path of the git directory the
# checkout or worktree at <dir> shares (its common dir), so two worktrees of
# one clone print the same path. Returns 1, printing nothing, when <dir> is
# not in a git repository: `cd ""` would succeed and answer with <dir> itself.
coord_git_common_dir() {
    local d
    d=$(CDPATH='' cd "$1" && git rev-parse --git-common-dir) || return 1
    [ -n "$d" ] || return 1
    (CDPATH='' cd "$1" && CDPATH='' cd "$d" && pwd -P)
}

# coord_url_key <url> -- a remote URL reduced to a comparison key, so the
# https and ssh spellings of one repository, with or without .git or a
# trailing slash, compare equal: <host>/<path>, lowercased, for the forms
# scheme://[user@]host[:port]/path and user@host:path. Any other form (a
# local path, or host:path with no user) is its own key, unchanged.
coord_url_key() {
    local u="$1"
    case "$u" in
        *://*)
            u="${u#*://}"
            u="${u#*@}"
            u=$(printf '%s' "$u" | sed -E 's#^([^/:]+):[0-9]+/#\1/#')
            ;;
        *@*:*)
            u="${u#*@}"
            u="${u%%:*}/${u#*:}"
            ;;
        *) printf '%s' "$u"; return 0 ;;
    esac
    u="${u%/}"
    u="${u%.git}"
    coord_lower "$u"
}

# coord_gh_read <outvar> <args...> -- one gh read with stdin from /dev/null,
# retried once after 1 s. Sets the named variable on success.
coord_gh_read() {
    local __out="$1" attempt out
    shift
    for attempt in 1 2; do
        if out=$(gh "$@" </dev/null); then
            printf -v "$__out" '%s' "$out"
            return 0
        fi
        [ "$attempt" -eq 1 ] && sleep 1
    done
    return 1
}

# coord_repo_visibility <owner/repo> -- print `public` or `private`, read live
# from `gh api repos/<r>`'s `visibility`: the same read the merge gate's
# visibility resolver makes (shirabe-validate's fetch_repo_is_public), so the
# check before a push and the gate before the merge can't disagree about a
# repository. `internal`, and any value other than `public`, prints
# `private`. Returns 2, printing nothing, when the read fails or carries no
# visibility: a caller stops as a status read and never guesses.
coord_repo_visibility() {
    local json v
    coord_gh_read json api "repos/$1" || return 2
    v=$(printf '%s' "$json" | jq -r 'if type == "object" then (.visibility // "") else "" end') || return 2
    case "$v" in
        public) printf 'public' ;;
        "") return 2 ;;
        *) printf 'private' ;;
    esac
}

# coord_node_visibility <home-repo> <node-repo> <node-id> -- the
# Coordination-PR Visibility Rule for one node, checked against the node's own
# target before anything is pushed (references/coordination-strategy.md). Sets
# COORD_HOME_VIS and COORD_NODE_VIS. Returns 0 when the pair is allowed: a
# private coordination PR may index any node, and a public one a public node.
# Returns 3, with a diagnostic, for a public coordination PR over a private
# node: the index line would name a private repository in a public body. The
# diagnostic names the node id and the public home, never the private
# repository (F1). Returns 2 when either read failed. Both callers,
# node-push.sh and repo-visibility.sh, map 3 to their exit 77
# (execute:visibility) and 2 to 72 (execute:status-read).
coord_node_visibility() {
    COORD_HOME_VIS=""; COORD_NODE_VIS=""
    COORD_HOME_VIS=$(coord_repo_visibility "$1") || {
        echo "$PROG: could not read the visibility of the coordination PR's repository $1" >&2
        return 2
    }
    COORD_NODE_VIS=$(coord_repo_visibility "$2") || {
        echo "$PROG: could not read the visibility of node $3's repository" >&2
        return 2
    }
    if [ "$COORD_HOME_VIS" = public ] && [ "$COORD_NODE_VIS" = private ]; then
        echo "$PROG: refused: node $3 lands in a private repository, and the coordination PR lives in the public repository $1; a public coordination PR never indexes a private node. Move the node into $1, or run the effort from a PLAN in a private repository, whose coordination PR may index public and private nodes alike." >&2
        return 3
    fi
    return 0
}

# coord_owned <repo> <head> <state> -- owned-pr.sh, carrying COORD_RUN_ID.
# Prints its output and returns its exit code.
coord_owned() {
    if [ -n "$COORD_RUN_ID" ]; then
        "$BASH" "$COORD_SELF_DIR/owned-pr.sh" --repo "$1" --head "$2" --state "$3" \
            --run-id "$COORD_RUN_ID" </dev/null
    else
        "$BASH" "$COORD_SELF_DIR/owned-pr.sh" --repo "$1" --head "$2" --state "$3" </dev/null
    fi
}

# coord_find_pr <home-repo> <coord-branch> <state> -- the coordination PR,
# by the ownership lookup. Only record-coord-setup.sh calls it, once, on a new
# run; every later step reads the number the run recorded (coord_recorded_pr).
# Sets C_URL, C_NUM, C_JSON (state,isDraft,body,title,headRefOid,url), and C_WHY to
# why it failed: none (no owned PR), several (several, or an ambiguous
# lookup), foreign (another run's PR), marker (the declaration marker
# missing), or read (a failed read). Returns 0 on success, 2 on a failed
# read, 3 when no single owned PR carries the marker.
coord_find_pr() {
    local out rc
    C_URL=""; C_NUM=""; C_JSON=""; C_WHY=""
    out=$(coord_owned "$1" "$2" "$3")
    rc=$?
    case "$rc" in
        0) [ -n "$out" ] || { C_WHY=none; echo "$PROG: no owned coordination PR on $1 head $2" >&2; return 3; } ;;
        2) C_WHY=read; echo "$PROG: the coordination PR lookup failed" >&2; return 2 ;;
        3|4) C_WHY=several; echo "$PROG: several owned PRs on $1 head $2, or an ambiguous lookup (owned-pr.sh exit $rc); refusing to pick one" >&2; return 3 ;;
        5) C_WHY=foreign; echo "$PROG: the PR on $1 head $2 was opened by another run" >&2; return 3 ;;
        *) C_WHY=read; echo "$PROG: owned-pr.sh exited $rc" >&2; return 2 ;;
    esac
    C_URL="$out"
    C_NUM="${out##*/}"
    coord_view_pr "$1" || return $?
    return 0
}

# coord_view_pr <home-repo> -- read the coordination PR #C_NUM into C_JSON and
# check it is a PR object carrying the declaration marker. Returns 2 on a
# failed read (C_WHY read), 3 when the marker is missing (C_WHY marker).
coord_view_pr() {
    coord_gh_read C_JSON pr view "$C_NUM" --repo "$1" --json url,state,isDraft,body,title,headRefOid \
        || { C_WHY=read; echo "$PROG: gh pr view of the coordination PR failed" >&2; return 2; }
    printf '%s' "$C_JSON" | jq -e 'type == "object" and (.state | type) == "string"' >/dev/null \
        || { C_WHY=read; echo "$PROG: the coordination PR read is not a PR object" >&2; return 2; }
    [ -n "$C_URL" ] || C_URL=$(printf '%s' "$C_JSON" | jq -r '.url // ""')
    # A here-string, not a pipe into grep -q: under pipefail an early grep
    # exit can SIGPIPE the producer and fail a match that succeeded.
    local c_body
    c_body=$(printf '%s' "$C_JSON" | jq -r '.body // ""')
    if ! grep -qF "$COORD_MARKER" <<<"$c_body"; then
        C_WHY=marker
        echo "$PROG: $C_URL does not carry the coordination PR declaration marker" >&2
        return 3
    fi
    return 0
}

# coord_recorded_pr <session> <home-repo> <open|all> -- the coordination PR
# whose number the run recorded at setup (run/setup's coordination_pr), read
# with `gh pr view`: no lookup, so the loop makes no owned-PR read for it.
# Sets C_URL, C_NUM, C_JSON as coord_find_pr does. Returns 0 on success, 2 on
# a failed read (the record's or GitHub's), 3 when `open` was asked and the PR
# is not OPEN, or it no longer carries the marker, and 4 when the session has
# no run/setup.
coord_recorded_pr() {
    local setup rc
    C_URL=""; C_NUM=""; C_JSON=""; C_WHY=""
    setup=$(rr_setup "$1")
    rc=$?
    case "$rc" in
        0) ;;
        1) echo "$PROG: session $1 has no run record (run/setup); coord_setup records it" >&2; return 4 ;;
        *) return 2 ;;
    esac
    C_NUM=$(printf '%s' "$setup" | jq -r '.coordination_pr // ""')
    [[ $C_NUM =~ ^[1-9][0-9]*$ ]] || { echo "$PROG: run/setup in session $1 holds no coordination PR number" >&2; return 2; }
    coord_view_pr "$2" || return $?
    C_URL=$(printf '%s' "$C_JSON" | jq -r '.url // ""')
    [[ $C_URL =~ $RE_COORD_URL ]] || { echo "$PROG: the coordination PR read carries no usable URL" >&2; return 2; }
    if [ "$3" = open ] && [ "$(printf '%s' "$C_JSON" | jq -r '.state')" != OPEN ]; then
        echo "$PROG: the recorded coordination PR $C_URL is not open" >&2
        return 3
    fi
    return 0
}

# coord_attempt_of <attempts> <node> -- print the recorded merge result for
# <node> (one of RE_COORD_ATTEMPT_VALUE's), or nothing.
coord_attempt_of() {
    local rest e
    rest="$1"
    while [ -n "$rest" ]; do
        e="${rest%%,*}"
        if [ "$e" = "$rest" ]; then rest=""; else rest="${rest#*,}"; fi
        case "$e" in "$2":*) printf '%s' "${e#*:}"; return 0 ;; esac
    done
    return 0
}

# coord_record_attempt <session> <node> <result> -- record <node>:<result> in
# the session's merge_attempts context key, replacing an earlier result for
# <node> and keeping every other node's: the one writer of that key, called
# by coord-merge.sh and by coord-render.sh --before-coordination. A stored
# value outside RE_COORD_ATTEMPTS is dropped rather than kept. Returns 70,
# with a diagnostic, when the write fails.
coord_record_attempt() {
    local old new rest e
    old=$(koto context get "$1" merge_attempts </dev/null) || old=""
    [[ $old =~ $RE_COORD_ATTEMPTS ]] || old=""
    new=""
    rest="$old"
    while [ -n "$rest" ]; do
        e="${rest%%,*}"
        if [ "$e" = "$rest" ]; then rest=""; else rest="${rest#*,}"; fi
        case "$e" in "$2":*) continue ;; esac
        if [ -z "$new" ]; then new="$e"; else new="$new,$e"; fi
    done
    if [ -z "$new" ]; then new="$2:$3"; else new="$new,$2:$3"; fi
    printf '%s' "$new" | koto context add "$1" merge_attempts >/dev/null || {
        echo "$PROG: could not record merge_attempts in session $1" >&2
        return 70
    }
    return 0
}

# coord_compute -- where the coordinated run stands. Inputs (globals):
#   CC_SESSION CC_PLAN CC_SLUG CC_REPOS CC_HOME CC_CB CC_MERGE CC_ATTEMPTS
# CC_SESSION is the run's koto session. Its run record is read once per pass
# (rr_record, local koto reads only): the coordination PR's number, the node
# list sealed at setup, each node's recorded PR and pushed head, and the
# cascade's verdict and pushed head. GitHub is read live for every PR's state,
# checks, and merge verdict, which merge-verdict.sh computes at the recorded
# head. The coordination PR's body is not read for any of it.
# Outputs (globals):
#   CC_ACTION      the one next action, from the closed set
#   CC_COORD_URL   the coordination PR's URL (empty when it was not found)
#   CC_UNMERGED    newline-separated `<url> <human|predecessor> <reason>` for
#                  each unmerged PR, in merge order, the coordination PR last
#   CC_BLOCKED     1 when some PR node cannot start because a predecessor is
#                  not satisfied
#   CC_BLOCK_REASON  the first such predecessor's condition
#   CC_COORD_ATTEMPT the recorded result of a coordination merge call, or of
#                  the render before it (body-stale, body-full)
# Never writes anything. Returns 0 whenever CC_ACTION is set.
coord_compute() {
    CC_ACTION=""; CC_COORD_URL=""; CC_UNMERGED=""; CC_BLOCKED=0; CC_BLOCK_REASON=""
    CC_COORD_ATTEMPT=""
    local rc rec tasks n i name kind repo waits
    local satisfied="," blocked_reason_first="" merge_cand="" dispatch_cand="" eval_cand=""
    local all_merged=1 pr_nodes=0 state draft verdict out node_branch exp
    local plan_present=0 node_rec n_repo n_pr n_sha

    # The run record, read once for the whole pass.
    rec=$(rr_record "$CC_SESSION") || { CC_ACTION="error:execute:status-read"; return 0; }
    if [ "$(rr_q "$rec" 'has("run/setup")')" != true ]; then
        echo "$PROG: session $CC_SESSION holds no run record (run/setup); coord_setup seals it before the loop runs" >&2
        CC_ACTION="error:execute:status-read"; return 0
    fi

    # The coordination PR, by the number setup recorded: no lookup.
    coord_recorded_pr "$CC_SESSION" "$CC_HOME" all
    rc=$?
    case "$rc" in
        0) ;;
        3) CC_ACTION="error:execute:pr-adopt"; return 0 ;;
        *) CC_ACTION="error:execute:status-read"; return 0 ;;
    esac
    CC_COORD_URL="$C_URL"
    local c_state c_draft
    c_state=$(printf '%s' "$C_JSON" | jq -r '.state')
    c_draft=$(printf '%s' "$C_JSON" | jq -r '.isDraft')
    case "$c_state" in
        MERGED) CC_ACTION="done:merged"; return 0 ;;
        OPEN) ;;
        *) CC_ACTION="error:execute:pr-closed"; return 0 ;;
    esac
    CC_COORD_ATTEMPT=$(coord_attempt_of "$CC_ATTEMPTS" coordination)

    # Every recorded node PR names a repository in the write set. The
    # coordination PR is recorded by number in run/setup, not as a node, so
    # the home repository need not be in the write set (a PLAN whose nodes
    # all land in other repositories); a node may name the home only when
    # some node lands there, which puts the home in the write set.
    local recorded
    recorded=$(rr_q "$rec" 'to_entries[] | select(.key | startswith("run/node/"))
        | "\(.key | ltrimstr("run/node/")) \(.value.repo // "")"') \
        || { CC_ACTION="error:execute:status-read"; return 0; }
    while read -r name repo; do
        [ -n "$name" ] || continue
        if ! coord_in_list "$repo" "$CC_REPOS"; then
            echo "$PROG: the run record names $repo for node $name, outside the write set [$CC_REPOS]" >&2
            CC_ACTION="error:execute:write-set"; return 0
        fi
    done <<<"$recorded"

    # The nodes, from the PLAN while it exists. After the cascade deleted it,
    # from the node list run/setup sealed, and every node must already be
    # merged.
    if [ -f "$CC_PLAN" ]; then
        plan_present=1
        tasks=$("$BASH" "$COORD_PLAN_TO_TASKS" "$CC_PLAN" </dev/null) || {
            echo "$PROG: plan-to-tasks.sh could not read $CC_PLAN" >&2
            CC_ACTION="error:execute:status-read"; return 0
        }
        printf '%s' "$tasks" | jq -e 'type == "array"' >/dev/null || {
            CC_ACTION="error:execute:status-read"; return 0
        }
    else
        tasks=$(rr_q "$rec" '[.["run/setup"].nodes // [] | .[]
            | {name, vars: {NODE_KIND: .kind, REPO: .repo, ISSUES: ""}, waits_on}]') || {
            CC_ACTION="error:execute:status-read"; return 0
        }
    fi

    n=$(printf '%s' "$tasks" | jq 'length')
    i=0
    while [ "$i" -lt "$n" ]; do
        name=$(printf '%s' "$tasks" | jq -r ".[$i].name")
        kind=$(printf '%s' "$tasks" | jq -r ".[$i].vars.NODE_KIND // \"pr\"")
        repo=$(printf '%s' "$tasks" | jq -r ".[$i].vars.REPO // \"\"")
        waits=$(printf '%s' "$tasks" | jq -r ".[$i].waits_on | join(\",\")")
        i=$((i + 1))
        [[ $name =~ $RE_COORD_NODE ]] || { CC_ACTION="error:execute:status-read"; return 0; }

        # Every predecessor satisfied? A gate node is never satisfied here:
        # its condition is prose this script cannot verify, so it fails
        # closed and the nodes after it wait.
        local preds_ok=1 p rest first_unsat=""
        rest="$waits"
        while [ -n "$rest" ]; do
            p="${rest%%,*}"
            if [ "$p" = "$rest" ]; then rest=""; else rest="${rest#*,}"; fi
            if ! coord_in_list "$p" "$satisfied"; then
                preds_ok=0
                [ -n "$first_unsat" ] || first_unsat="$p"
            fi
        done

        if [ "$kind" = "gate" ]; then
            continue
        fi
        pr_nodes=$((pr_nodes + 1))
        if ! coord_in_list "$repo" "$CC_REPOS"; then
            echo "$PROG: node $name names $repo, outside the write set [$CC_REPOS]" >&2
            CC_ACTION="error:execute:write-set"; return 0
        fi
        node_branch="impl/$CC_SLUG-$name"

        node_rec=$(printf '%s' "$rec" | jq -c --arg k "run/node/$name" '.[$k] // empty') \
            || { CC_ACTION="error:execute:status-read"; return 0; }
        if [ -z "$node_rec" ]; then
            all_merged=0
            if [ "$plan_present" -eq 0 ]; then
                CC_ACTION="error:execute:status-read"; return 0
            fi
            if [ "$preds_ok" -eq 1 ]; then
                [ -n "$dispatch_cand" ] || dispatch_cand="$name"
            else
                CC_BLOCKED=1
                if [ -z "$blocked_reason_first" ]; then
                    case "$first_unsat" in
                        gate-*) blocked_reason_first="gate-unverified" ;;
                        *) blocked_reason_first="predecessor-unmerged" ;;
                    esac
                fi
            fi
            continue
        fi
        n_repo=$(printf '%s' "$node_rec" | jq -r '.repo // ""')
        n_pr=$(printf '%s' "$node_rec" | jq -r '.pr // ""')
        n_sha=$(printf '%s' "$node_rec" | jq -r '.head // ""')
        if [ "$n_repo" != "$repo" ]; then
            echo "$PROG: the run record names $n_repo for $name, the PLAN names $repo" >&2
            CC_ACTION="error:execute:pr-adopt"; return 0
        fi
        # The recorded PR must be the one owned PR on this node's branch.
        out=$(coord_owned "$n_repo" "$node_branch" all)
        rc=$?
        case "$rc" in
            0) ;;
            2) CC_ACTION="error:execute:status-read"; return 0 ;;
            *) CC_ACTION="error:execute:pr-adopt"; return 0 ;;
        esac
        if [ -z "$out" ] || [ "${out##*/}" != "$n_pr" ]; then
            echo "$PROG: the run record names #$n_pr for $name, which is not the owned PR on $n_repo $node_branch" >&2
            CC_ACTION="error:execute:pr-adopt"; return 0
        fi
        local url="$out" view
        coord_gh_read view pr view "$n_pr" --repo "$n_repo" --json state,isDraft \
            || { CC_ACTION="error:execute:status-read"; return 0; }
        state=$(printf '%s' "$view" | jq -r '.state // ""')
        draft=$(printf '%s' "$view" | jq -r '.isDraft // false')
        case "$state" in
            MERGED)
                satisfied="$satisfied$name,"
                continue
                ;;
            OPEN) ;;
            CLOSED) CC_ACTION="error:execute:pr-closed"; return 0 ;;
            *) CC_ACTION="error:execute:status-read"; return 0 ;;
        esac
        all_merged=0
        if [ "$draft" = "true" ]; then
            local checks
            if ! coord_gh_read checks pr checks "$n_pr" --repo "$n_repo" --json name,bucket; then
                checks="[]"
            fi
            if printf '%s' "$checks" | jq -e 'type == "array" and any(.[]; .bucket == "fail" or .bucket == "cancel")' >/dev/null; then
                CC_ACTION="error:execute:ci"; return 0
            fi
            [ -n "$eval_cand" ] || eval_cand="$name"
            continue
        fi
        exp="${n_sha:-none}"
        verdict=$("$BASH" "$COORD_SELF_DIR/merge-verdict.sh" --repo "$n_repo" --pr "$n_pr" \
            --merge "$CC_MERGE" --expected-head "$exp" </dev/null) \
            || { CC_ACTION="error:execute:status-read"; return 0; }
        local attempt
        attempt=$(coord_attempt_of "$CC_ATTEMPTS" "$name")
        case "$verdict" in
            merged) satisfied="$satisfied$name," ;;
            pending:*) [ -n "$eval_cand" ] || eval_cand="$name" ;;
            mergeable:*)
                if [ -n "$attempt" ]; then
                    CC_UNMERGED="$CC_UNMERGED$url human $attempt
"
                elif [ "$CC_MERGE" = "true" ]; then
                    [ -n "$merge_cand" ] || merge_cand="$name"
                else
                    CC_UNMERGED="$CC_UNMERGED$url human merge-not-requested
"
                fi
                ;;
            awaiting:*)
                # A refused merge keeps the verdict's own reason (a moved
                # head stays head-moved); any other recorded result names it.
                if [ -n "$attempt" ] && [ "$attempt" != merge-refused ]; then
                    CC_UNMERGED="$CC_UNMERGED$url human $attempt
"
                else
                    CC_UNMERGED="$CC_UNMERGED$url human ${verdict#awaiting:}
"
                fi
                ;;
            error:execute:*) CC_ACTION="$verdict"; return 0 ;;
            *) CC_ACTION="error:execute:status-read"; return 0 ;;
        esac
    done
    # Every PR node merged, read from the facts rather than tracked above.
    all_merged=1
    [ "$pr_nodes" -gt 0 ] || all_merged=0
    i=0
    while [ "$i" -lt "$n" ]; do
        name=$(printf '%s' "$tasks" | jq -r ".[$i].name")
        kind=$(printf '%s' "$tasks" | jq -r ".[$i].vars.NODE_KIND // \"pr\"")
        i=$((i + 1))
        [ "$kind" = gate ] && continue
        coord_in_list "$name" "$satisfied" || all_merged=0
    done

    if [ -n "$merge_cand" ]; then CC_ACTION="merge:$merge_cand"; return 0; fi
    if [ -n "$dispatch_cand" ]; then CC_ACTION="dispatch:$dispatch_cand"; return 0; fi
    if [ -n "$eval_cand" ]; then CC_ACTION="evaluate:$eval_cand"; return 0; fi

    if [ "$all_merged" -eq 1 ]; then
        # Every node PR merged. The cascade runs once, on the coordination
        # branch: while the PLAN is present it has not run, and unless the
        # run record holds its verdict as pushed (with the head
        # node-push.sh's coordination mode pushed), it didn't finish. A
        # `failed` verdict, or none, runs it again.
        local c_verdict c_sha
        c_verdict=$(rr_q "$rec" '.["run/cascade"].verdict // "not-run"')
        c_sha=$(rr_q "$rec" '.["run/cascade"].head // ""')
        if [ "$plan_present" -eq 1 ] || [ "$c_verdict" != pushed ] || [ -z "$c_sha" ]; then
            CC_ACTION="cascade"; return 0
        fi
        # The body CI's merge-last gate reads could not be brought up to date
        # with the record this invocation (coord-render.sh
        # --before-coordination recorded it): neither the coordination PR's
        # evaluation nor its merge runs again until the next invocation.
        case "$CC_COORD_ATTEMPT" in
            body-stale|body-full)
                CC_UNMERGED="$CC_UNMERGED$CC_COORD_URL human merge-refused:$CC_COORD_ATTEMPT
"
                CC_ACTION="done:ready-awaiting-merge"; return 0
                ;;
        esac
        if [ "$c_draft" = "true" ]; then
            CC_ACTION="evaluate-coordination"; return 0
        fi
        verdict=$("$BASH" "$COORD_SELF_DIR/merge-verdict.sh" --repo "$CC_HOME" --pr "$C_NUM" \
            --merge "$CC_MERGE" --expected-head "$c_sha" </dev/null) \
            || { CC_ACTION="error:execute:status-read"; return 0; }
        case "$verdict" in
            merged) CC_ACTION="done:merged" ;;
            pending:*) CC_ACTION="evaluate-coordination" ;;
            mergeable:*)
                if [ -n "$CC_COORD_ATTEMPT" ]; then
                    CC_UNMERGED="$CC_UNMERGED$CC_COORD_URL human $CC_COORD_ATTEMPT
"
                    CC_ACTION="done:ready-awaiting-merge"
                elif [ "$CC_MERGE" = "true" ]; then
                    CC_ACTION="merge-coordination"
                else
                    CC_UNMERGED="$CC_UNMERGED$CC_COORD_URL human merge-not-requested
"
                    CC_ACTION="done:ready-awaiting-merge"
                fi
                ;;
            awaiting:*)
                if [ -n "$CC_COORD_ATTEMPT" ] && [ "$CC_COORD_ATTEMPT" != merge-refused ]; then
                    CC_UNMERGED="$CC_UNMERGED$CC_COORD_URL human $CC_COORD_ATTEMPT
"
                else
                    CC_UNMERGED="$CC_UNMERGED$CC_COORD_URL human ${verdict#awaiting:}
"
                fi
                CC_ACTION="done:ready-awaiting-merge"
                ;;
            error:execute:*) CC_ACTION="$verdict" ;;
            *) CC_ACTION="error:execute:status-read" ;;
        esac
        return 0
    fi

    # Something is unmerged and nothing can start. The coordination PR waits
    # on its predecessors.
    CC_UNMERGED="$CC_UNMERGED$CC_COORD_URL predecessor ${blocked_reason_first:-predecessor-unmerged}
"
    CC_BLOCK_REASON="$blocked_reason_first"
    if [ "$CC_BLOCKED" -eq 1 ]; then
        CC_ACTION="pause"
    else
        CC_ACTION="done:ready-awaiting-merge"
    fi
    return 0
}
