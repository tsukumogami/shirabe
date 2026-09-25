# coord-common.sh — shared pieces of /execute's coordinated loop scripts.
#
# Sourced, never run: coordinated-next.sh and coordination-verdict.sh share
# the one computation of where a coordinated run stands (coord_compute), and
# node-push.sh and coord-merge.sh share the coordination-PR lookup and the
# PR-index parser. Keeping them in one file is what stops the loop's next
# action and the verdict it ends on from disagreeing about the same GitHub
# state.
#
# Callers set PROG before sourcing and set -uo pipefail themselves.
#
# The PR index. Each node's line in the coordination PR body's `## PR Index`
# section has the shape
#
#   - <node-id> | <owner/repo>:<path>#<number> | <open|merged> | head=<sha>
#
# where the `head=` field is present once node-push.sh has pushed the node and
# is written by nothing else. The coordination PR's own record uses the node
# id `coordination`. A line in the section that starts `- <word> |` is an
# entry and must parse; any other line (prose, a blank) is ignored.
#
# Requires: bash 3.2+, jq, gh (through owned-pr.sh and the reads below).

COORD_MARKER='This is a **coordination PR**'

RE_COORD_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_COORD_REPO_LIST='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)*$'
RE_COORD_BRANCH='^[A-Za-z0-9._/-]+$'
RE_COORD_SLUG='^[a-z0-9-]+$'
# plan-to-tasks.sh's node-name pattern (R9).
RE_COORD_NODE='^[a-z][a-z0-9-]*$'
RE_COORD_SHA='^[0-9a-f]{40}$'
RE_COORD_URL='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$'
RE_COORD_ENTRY='^- ([a-z][a-z0-9-]*) \| ([A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._-]+):([^ |#]+)#([1-9][0-9]*) \| (open|merged)( \| head=([0-9a-f]{40}))?[[:space:]]*$'
RE_COORD_ENTRY_LIKE='^- [^|]+\|'
# merge_attempts: <node>:<result> entries, comma-joined.
RE_COORD_ATTEMPTS='^([a-z][a-z0-9-]*:(merge-not-observed|merge-call-failed))(,[a-z][a-z0-9-]*:(merge-not-observed|merge-call-failed))*$'

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

# coord_index_entries <body> -- print the PR Index section's entry lines, one
# per line. Lines outside the section, and lines inside it that are not
# entry-shaped, are dropped here; entry-shaped lines that fail the full
# grammar are kept so the caller can refuse them.
coord_index_entries() {
    printf '%s\n' "$1" | awk '
        /^## / { insec = ($0 ~ /^## PR Index[[:space:]]*$/); next }
        insec && /^- [^|]+\|/ { sub(/\r$/, ""); print }
    '
}

# coord_parse_entry <line> -- set E_NODE, E_REPO, E_PATH, E_NUM, E_STATE,
# E_HEAD (empty when absent). Returns 1 when the line is outside the grammar.
coord_parse_entry() {
    E_NODE=""; E_REPO=""; E_PATH=""; E_NUM=""; E_STATE=""; E_HEAD=""
    [[ $1 =~ $RE_COORD_ENTRY ]] || return 1
    E_NODE="${BASH_REMATCH[1]}"
    E_REPO="${BASH_REMATCH[2]}"
    E_PATH="${BASH_REMATCH[3]}"
    E_NUM="${BASH_REMATCH[4]}"
    E_STATE="${BASH_REMATCH[5]}"
    E_HEAD="${BASH_REMATCH[7]:-}"
    coord_valid_repo "$E_REPO" || return 1
    case "/$E_PATH/" in */../*|//*) return 1 ;; esac
    return 0
}

# coord_find_entry <entries> <node> -- print the one entry line for <node>.
# Returns 1 when there is none, 2 when there are several.
coord_find_entry() {
    local line found="" count=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in
            "- $2 |"*)
                count=$((count + 1))
                found="$line"
                ;;
        esac
    done <<<"$1"
    [ "$count" -eq 0 ] && return 1
    [ "$count" -gt 1 ] && return 2
    printf '%s\n' "$found"
    return 0
}

# coord_find_pr <home-repo> <coord-branch> <state> -- the coordination PR.
# Sets C_URL, C_NUM, C_JSON (state,isDraft,body,headRefOid,url). Returns 0 on
# success, 2 on a failed read, 3 when no single owned PR carries the marker
# (zero, several, or the marker missing).
coord_find_pr() {
    local out rc
    C_URL=""; C_NUM=""; C_JSON=""
    out=$("$BASH" "$COORD_SELF_DIR/owned-pr.sh" --repo "$1" --head "$2" --state "$3" </dev/null)
    rc=$?
    case "$rc" in
        0) [ -n "$out" ] || { echo "$PROG: no owned coordination PR on $1 head $2" >&2; return 3; } ;;
        2) echo "$PROG: the coordination PR lookup failed" >&2; return 2 ;;
        3) echo "$PROG: several owned PRs on $1 head $2; refusing to pick one" >&2; return 3 ;;
        *) echo "$PROG: owned-pr.sh exited $rc" >&2; return 2 ;;
    esac
    C_URL="$out"
    C_NUM="${out##*/}"
    coord_gh_read C_JSON pr view "$C_NUM" --repo "$1" --json url,state,isDraft,body,headRefOid \
        || { echo "$PROG: gh pr view of the coordination PR failed" >&2; return 2; }
    printf '%s' "$C_JSON" | jq -e 'type == "object" and (.state | type) == "string"' >/dev/null \
        || { echo "$PROG: the coordination PR read is not a PR object" >&2; return 2; }
    if ! printf '%s' "$C_JSON" | jq -r '.body // ""' | grep -qF "$COORD_MARKER"; then
        echo "$PROG: $C_URL does not carry the coordination PR declaration marker" >&2
        return 3
    fi
    return 0
}

# coord_attempt_of <attempts> <node> -- print the recorded merge result for
# <node> (merge-not-observed or merge-call-failed), or nothing.
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

# coord_compute -- where the coordinated run stands. Inputs (globals):
#   CC_PLAN CC_SLUG CC_REPOS CC_HOME CC_CB CC_MERGE CC_ATTEMPTS
# Outputs (globals):
#   CC_ACTION      the one next action, from the closed set
#   CC_COORD_URL   the coordination PR's URL (empty when it was not found)
#   CC_UNMERGED    newline-separated `<url> <human|predecessor> <reason>` for
#                  each unmerged PR, in merge order, the coordination PR last
#   CC_BLOCKED     1 when some PR node cannot start because a predecessor is
#                  not satisfied
#   CC_BLOCK_REASON  the first such predecessor's condition
#   CC_COORD_ATTEMPT the recorded result of a coordination merge call
# Never writes anything. Returns 0 whenever CC_ACTION is set.
coord_compute() {
    CC_ACTION=""; CC_COORD_URL=""; CC_UNMERGED=""; CC_BLOCKED=0; CC_BLOCK_REASON=""
    CC_COORD_ATTEMPT=""
    local rc entries line tasks n i name kind repo issues waits
    local satisfied="," blocked_reason_first="" merge_cand="" dispatch_cand="" eval_cand=""
    local all_merged=1 pr_nodes=0 state draft verdict out node_branch head exp
    local plan_present=0

    coord_find_pr "$CC_HOME" "$CC_CB" all
    rc=$?
    case "$rc" in
        0) ;;
        2) CC_ACTION="error:execute:status-read"; return 0 ;;
        *) CC_ACTION="error:execute:pr-adopt"; return 0 ;;
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

    # The index: every entry parses, names a repository in the write set, and
    # appears once.
    entries=$(coord_index_entries "$(printf '%s' "$C_JSON" | jq -r '.body // ""')")
    local seen=","
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        if ! coord_parse_entry "$line"; then
            echo "$PROG: PR index entry outside the grammar: [$line]" >&2
            CC_ACTION="error:execute:status-read"; return 0
        fi
        if ! coord_in_list "$E_REPO" "$CC_REPOS"; then
            echo "$PROG: PR index entry $E_NODE names $E_REPO, outside the write set [$CC_REPOS]" >&2
            CC_ACTION="error:execute:write-set"; return 0
        fi
        if coord_in_list "$E_NODE" "$seen"; then
            echo "$PROG: PR index lists $E_NODE more than once" >&2
            CC_ACTION="error:execute:status-read"; return 0
        fi
        seen="$seen$E_NODE,"
    done <<<"$entries"

    # The nodes, from the PLAN while it exists. After the cascade deleted it,
    # the index is the node list, and every node must already be merged.
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
        tasks=$(printf '%s\n' "$entries" | while IFS= read -r line; do
            [ -n "$line" ] || continue
            coord_parse_entry "$line" || continue
            [ "$E_NODE" = coordination ] && continue
            jq -nc --arg n "$E_NODE" --arg r "$E_REPO" '{name: $n, vars: {NODE_KIND: "pr", REPO: $r, ISSUES: ""}, waits_on: []}'
        done | jq -s '.')
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

        line=$(coord_find_entry "$entries" "$name")
        if [ -z "$line" ]; then
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
        coord_parse_entry "$line"
        if [ "$E_REPO" != "$repo" ]; then
            echo "$PROG: the index names $E_REPO for $name, the PLAN names $repo" >&2
            CC_ACTION="error:execute:pr-adopt"; return 0
        fi
        # The indexed PR must be the one owned PR on this node's branch.
        out=$("$BASH" "$COORD_SELF_DIR/owned-pr.sh" --repo "$E_REPO" --head "$node_branch" --state all </dev/null)
        rc=$?
        case "$rc" in
            0) ;;
            2) CC_ACTION="error:execute:status-read"; return 0 ;;
            *) CC_ACTION="error:execute:pr-adopt"; return 0 ;;
        esac
        if [ -z "$out" ] || [ "${out##*/}" != "$E_NUM" ]; then
            echo "$PROG: index entry $name names #$E_NUM, which is not the owned PR on $E_REPO $node_branch" >&2
            CC_ACTION="error:execute:pr-adopt"; return 0
        fi
        local url="$out" view
        coord_gh_read view pr view "$E_NUM" --repo "$E_REPO" --json state,isDraft \
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
            if ! coord_gh_read checks pr checks "$E_NUM" --repo "$E_REPO" --json name,bucket; then
                checks="[]"
            fi
            if printf '%s' "$checks" | jq -e 'type == "array" and any(.[]; .bucket == "fail" or .bucket == "cancel")' >/dev/null; then
                CC_ACTION="error:execute:ci"; return 0
            fi
            [ -n "$eval_cand" ] || eval_cand="$name"
            continue
        fi
        exp="${E_HEAD:-none}"
        verdict=$("$BASH" "$COORD_SELF_DIR/merge-verdict.sh" --repo "$E_REPO" --pr "$E_NUM" \
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
                if [ -n "$attempt" ]; then
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
        # branch: while the PLAN is present it has not run, and without the
        # coordination PR's own head= record its push was never recorded.
        local c_line c_head=""
        c_line=$(coord_find_entry "$entries" coordination)
        if [ -n "$c_line" ] && coord_parse_entry "$c_line"; then c_head="$E_HEAD"; fi
        if [ "$plan_present" -eq 1 ] || [ -z "$c_head" ]; then
            CC_ACTION="cascade"; return 0
        fi
        if [ "$c_draft" = "true" ]; then
            CC_ACTION="evaluate-coordination"; return 0
        fi
        verdict=$("$BASH" "$COORD_SELF_DIR/merge-verdict.sh" --repo "$CC_HOME" --pr "$C_NUM" \
            --merge "$CC_MERGE" --expected-head "$c_head" </dev/null) \
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
                if [ -n "$CC_COORD_ATTEMPT" ]; then
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
