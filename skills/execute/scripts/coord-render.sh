#!/usr/bin/env bash
# coord-render.sh — for /execute: bring the coordination PR's body up to date
# with the coordinated run's record, and record the merges it sees.
#
# The coordination PR's body is the rendering of the run's record (the `run/`
# keys in its koto session), built by scripts/lib/coordination-body.sh's
# cb_render. This is the one script that posts it. It runs after every
# transition the body shows: node-push.sh after a node's PR opens or is
# pushed and after the cascade pushes, and before the cascade (its order
# mode); coord-merge.sh after a node is seen merged and before the
# coordination PR's merge; the template's evaluate-coordination step before
# the coordination PR is marked ready; and record-coordination-verdict.sh, the
# coord_verdict default action, before every terminal.
#
# Usage:
#   coord-render.sh --session <S> --slug <slug> --home-repo <owner/repo>
#                   --coord-branch <branch>
#                   [--before-coordination [--rendered-out <file>]]
#
# In order:
#   1. read the run record (rr_record) and the run's identity (`run-id.sh
#      get`, the body's `run=` line); no run/setup, or a failed read, is
#      body=stale;
#   2. read the coordination PR the record names (run/setup's
#      coordination_pr) with `gh pr view` and no marker requirement, so a body
#      /scope republished without the index gets it back; its headRefName must
#      be --coord-branch. A failed read, another branch, or a CLOSED PR is
#      body=stale. A MERGED one gets step 3 only and then body=unchanged: its
#      body is final at the merge, so nothing is posted and no visibility is
#      read;
#   3. read each indexed PR's state (each recorded node, and each live
#      follow-up), with `gh pr view --json state,mergeCommit`; a failed read
#      renders `unknown`. A MERGED one whose record holds no merged_head, and
#      whose mergeCommit.oid is 40 hex, is recorded through
#      `run-record.sh observe` (one document for all of them) before anything
#      is rendered, so the body never shows a head the record doesn't hold; a
#      refused or failed observe is body=stale. Each one so recorded is also
#      recorded merged in the run's trail (scripts/run-trail.sh pr-state), a
#      write that only warns when it fails;
#   4. only when some indexed repository is not the home (case-insensitive),
#      read the home's and each other repository's visibility live
#      (coord_repo_visibility); a failed read is body=stale;
#   5. take the live body's Part 1 (cb_part1: the lines above its first
#      top-level `---`, byte for byte), or none, and build the render document
#      with jq from files, never from shell text;
#   6. render (cb_render): a private repository under a public coordination
#      PR is body=refused:execute:visibility (exit 77; the diagnostic names
#      the node, never the repository); a body over 60,000 bytes is
#      body=full; any other refusal body=stale. A run marker line the live
#      body carries (`<!-- shirabe-run: <id> -->`) is carried to the end of
#      the render and none is forged (`run-id.sh carry`, the rule for any
#      full-body rewrite of a PR);
#   7. check it with `shirabe validate --coordination-body`; a refusal is
#      body=stale;
#   8. a render equal to the live body (a difference of trailing newlines at
#      the very end aside, which GitHub may drop) is body=unchanged, with no
#      post;
#   9. re-read the body; a failed read, or a Part 1 (or its presence) other
#      than the one step 5 read, is body=stale with no post: a person's edit
#      between the render and the post is never overwritten;
#  10. post it: `gh pr edit <n> --repo <home> --body-file <file>`. A failed
#      post is body=stale; the record is unchanged, and the next transition
#      renders again.
#
# --before-coordination is for the steps the coordination PR's own gate
# reads the body for (its evaluation and its merge): a result other than
# posted, unchanged or the visibility refusal also records
# `coordination:body-stale` (or `coordination:body-full`) in the session's
# merge_attempts (coord_record_attempt) and prints `merge-refused:body-stale`
# (or `merge-refused:body-full`), so the loop neither evaluates nor merges the
# coordination PR again in this invocation and the run ends
# ready-awaiting-merge. Without it, a stale or full body never changes a
# node's decision.
#
# --rendered-out <file> (only with --before-coordination) hands the caller the
# body this run's gate is to read: on body=posted it writes the exact bytes it
# posted to <file>, and on body=unchanged the live body it found equal (or,
# for a MERGED coordination PR, the final body it read). It writes nothing on
# any other result, so the caller reads the file only after one of those two.
# <file> is the caller's path: one that exists as anything but a regular file
# (a directory, a symlink, a fifo) is a usage error, and a write that fails
# is body=stale. coord-merge.sh runs the merge-last gate over this file
# rather than a re-read of the body.
#
# Output (stdout): zero or more `observed=<node>[/follow-up-<n>]:<sha>` lines,
# then exactly one `body=posted|unchanged|stale|full|refused:execute:visibility`,
# then, with --before-coordination, the optional `merge-refused:` line. Every
# diagnostic goes to stderr.
#
# Exit codes:
#   0   a body= line other than the refusal was printed
#   64  usage error (nothing read)
#   70  --before-coordination: the merge_attempts write failed
#   77  body=refused:execute:visibility; nothing was posted
#
# Requires: bash 3.2+, gh, jq, koto, shirabe.
set -uo pipefail

PROG=coord-render

COORD_SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=coord-common.sh
. "$COORD_SELF_DIR/coord-common.sh"
# shellcheck source=../../../scripts/lib/coordination-body.sh
. "$COORD_SELF_DIR/../../../scripts/lib/coordination-body.sh" || exit 64

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: coord-render.sh --session <koto-session> --slug <slug> --home-repo <owner/repo> --coord-branch <branch> [--before-coordination [--rendered-out <file>]]" >&2
    exit 64
}

SESSION=""; SLUG=""; HOME_REPO=""; CB=""; BEFORE=0; RENDERED_OUT=""; HAS_OUT=0
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--slug|--home-repo|--coord-branch|--rendered-out)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --session) SESSION="$2" ;;
                --slug) SLUG="$2" ;;
                --home-repo) HOME_REPO="$2" ;;
                --coord-branch) CB="$2" ;;
                --rendered-out) RENDERED_OUT="$2"; HAS_OUT=1 ;;
            esac
            shift 2
            ;;
        --before-coordination)
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            BEFORE=1
            shift
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done
[[ $SESSION =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage_error "--session [$SESSION] is not a koto session name"
[[ $SLUG =~ $RE_COORD_SLUG ]] || usage_error "--slug [$SLUG] is outside ^[a-z0-9-]+\$"
coord_valid_repo "$HOME_REPO" || usage_error "--home-repo [$HOME_REPO] is not a single owner/repo"
coord_valid_branch "$CB" || usage_error "--coord-branch [$CB] is not an allowed branch name"
if [ "$HAS_OUT" -eq 1 ]; then
    [ "$BEFORE" -eq 1 ] || usage_error "--rendered-out applies only with --before-coordination"
    [ -n "$RENDERED_OUT" ] || usage_error "--rendered-out needs a file path"
    if [ -L "$RENDERED_OUT" ] || { [ -e "$RENDERED_OUT" ] && ! [ -f "$RENDERED_OUT" ]; }; then
        usage_error "--rendered-out [$RENDERED_OUT] exists and is not a regular file"
    fi
fi
command -v jq >/dev/null || usage_error "jq is not on PATH"

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; return 0; }
trap cleanup EXIT

# finish <token> -- print the body= line (and, before the coordination PR's
# own steps, record a body that could not be brought up to date), then exit.
finish() {
    printf 'body=%s\n' "$1"
    if [ "$BEFORE" -eq 1 ]; then
        case "$1" in
            stale|full)
                coord_record_attempt "$SESSION" coordination "body-$1" || exit 70
                printf 'merge-refused:body-%s\n' "$1"
                ;;
        esac
    fi
    case "$1" in
        refused:*) exit 77 ;;
    esac
    exit 0
}
stale() { echo "$PROG: $*; the coordination PR's body was not posted" >&2; finish stale; }
# hand_out <file> -- with --rendered-out, copy <file>'s bytes (the body posted
# or found equal) to the caller's path; a failed write is body=stale.
hand_out() {
    [ "$HAS_OUT" -eq 1 ] || return 0
    cat -- "$1" > "$RENDERED_OUT" || {
        echo "$PROG: the body could not be written to --rendered-out; the merge-last gate has nothing to read" >&2
        finish stale
    }
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/coord-render.XXXXXX") || { WORK=""; stale "no temporary directory"; }

# 1. The record and the run's identity.
REC=$(rr_record "$SESSION") || stale "the run record in session $SESSION could not be read"
[ "$(rr_q "$REC" 'has("run/setup")')" = true ] || stale "session $SESSION holds no run record (run/setup)"
RUN=$("$BASH" "$COORD_SELF_DIR/run-id.sh" get "$SESSION" </dev/null) || stale "this run's identity could not be read"
[[ $RUN =~ $RE_COORD_RUN_ID ]] || stale "this run's identity read as [$RUN]"
C_NUM=$(rr_q "$REC" '.["run/setup"].coordination_pr // ""')
[[ $C_NUM =~ ^[1-9][0-9]*$ ]] || stale "run/setup holds no coordination PR number"

# 2. The coordination PR, by its recorded number, with no marker check.
CJSON=""
coord_gh_read CJSON pr view "$C_NUM" --repo "$HOME_REPO" --json state,body,headRefName,url \
    || stale "the coordination PR #$C_NUM could not be read"
C_STATE=$(printf '%s' "$CJSON" | jq -r 'if type == "object" then (.state // "") else "" end') \
    || stale "the coordination PR read is not a PR object"
C_HEAD=$(printf '%s' "$CJSON" | jq -r '.headRefName // ""') || stale "the coordination PR read carries no branch"
[ "$C_HEAD" = "$CB" ] || stale "the recorded coordination PR #$C_NUM is on [$C_HEAD], not the coordination branch [$CB]"
case "$C_STATE" in
    OPEN|MERGED) ;;
    *) stale "the coordination PR #$C_NUM is $C_STATE" ;;
esac

# 3. Each indexed PR's live state; a newly seen merge recorded first.
# The indexed PRs: <key> TAB <label> TAB <repo> TAB <pr> TAB <merged_head>.
ROWS=$(rr_q "$REC" '
    .["run/setup"].nodes as $nodes | . as $r
    | $nodes[] | select(.kind == "pr") | .name as $n
    | select($r | has("run/node/\($n)"))
    | (["run/node/\($n)", $n, $r["run/node/\($n)"].repo, ($r["run/node/\($n)"].pr | tostring),
        ($r["run/node/\($n)"].merged_head // "")] | @tsv),
      ($r | to_entries[] | select(.key | startswith("run/follow-up/\($n)/"))
       | select((.value.removed // false) | not)
       | [.key, "\($n)/follow-up-\(.value.pr)", .value.repo, (.value.pr | tostring),
          (.value.merged_head // "")] | @tsv)') || stale "the run record's indexed PRs could not be listed"
STATES='{}'
OBSERVE='{}'
OBSERVED=""
SEEN_MERGED=""
while IFS=$'\t' read -r key label repo pr mh; do
    [ -n "$key" ] || continue
    view=""
    if ! coord_gh_read view pr view "$pr" --repo "$repo" --json state,mergeCommit; then
        echo "$PROG: could not read $label's PR state; it renders unknown" >&2
        continue
    fi
    st=$(printf '%s' "$view" | jq -r 'if type == "object" then (.state // "") else "" end') || st=""
    case "$st" in
        OPEN) st=open ;;
        MERGED) st=merged ;;
        CLOSED) st=closed ;;
        *) continue ;;
    esac
    STATES=$(jq -cn --argjson s "$STATES" --arg k "$repo#$pr" --arg v "$st" '$s + {($k): $v}') \
        || stale "the state map could not be built"
    if [ "$st" = merged ] && [ -z "$mh" ]; then
        oid=$(printf '%s' "$view" | jq -r '.mergeCommit.oid? // ""') || oid=""
        if [[ $oid =~ $RE_COORD_SHA ]]; then
            OBSERVE=$(jq -cn --argjson o "$OBSERVE" --arg k "$key" --arg h "$oid" '$o + {($k): {merged_head: $h}}') \
                || stale "the observe document could not be built"
            OBSERVED="${OBSERVED}observed=$label:$oid
"
            SEEN_MERGED="${SEEN_MERGED}$repo	$pr
"
        fi
    fi
done <<<"$ROWS"
if [ "$OBSERVE" != '{}' ]; then
    printf '%s' "$OBSERVE" > "$WORK/observe.json" || stale "the observe document could not be staged"
    "$BASH" "$COORD_SELF_DIR/run-record.sh" observe --session "$SESSION" --json "$WORK/observe.json" </dev/null >&2 \
        || stale "run-record.sh observe did not record the merged heads"
    # Each newly seen merge, merged by this run or by a person, is the run
    # observing that PR merge: its trail records it (scripts/run-trail.sh
    # pr-state, which keeps the PR's recorded role). The trail is the
    # record, not the rendering, so a write that fails only warns.
    while IFS=$'\t' read -r mrepo mpr; do
        [ -n "$mrepo" ] || continue
        "$BASH" "$COORD_SELF_DIR/../../../scripts/run-trail.sh" pr-state --session "$SESSION" \
            --repo "$mrepo" --number "$mpr" --state merged </dev/null >/dev/null \
            || echo "$PROG: could not record $mrepo#$mpr as merged in $SESSION's trail" >&2
    done <<<"$SEEN_MERGED"
    printf '%s' "$OBSERVED"
    REC=$(rr_record "$SESSION") || stale "the run record could not be read back after the observe"
fi
if [ "$C_STATE" = MERGED ]; then
    if [ "$HAS_OUT" -eq 1 ]; then
        printf '%s' "$CJSON" | jq -j '.body // ""' > "$WORK/live.md" || stale "the final body could not be staged"
        hand_out "$WORK/live.md"
    fi
    finish unchanged
fi

# 4. Visibility, only when some indexed repository is not the home.
HOME_LC=$(coord_lower "$HOME_REPO")
OTHERS=$(printf '%s\n' "$ROWS" | awk -F'\t' -v h="$HOME_LC" 'NF >= 3 && tolower($3) != h { print $3 }' | LC_ALL=C sort -u)
# With no other repository every indexed line is in the home repository, whose
# lines cb_render resolves through home.visibility, so a private-under-public
# refusal can't arise. The value is only the valid placeholder cb_render's
# document schema requires.
HOME_VIS=public
VIS='{}'
if [ -n "$OTHERS" ]; then
    HOME_VIS=$(coord_repo_visibility "$HOME_REPO") || stale "the visibility of the coordination PR's repository could not be read"
    while IFS= read -r r; do
        [ -n "$r" ] || continue
        v=$(coord_repo_visibility "$r") || stale "the visibility of an indexed repository could not be read"
        VIS=$(jq -cn --argjson m "$VIS" --arg k "$r" --arg v "$v" '$m + {($k): $v}') || stale "the visibility map could not be built"
    done <<<"$OTHERS"
fi

# 5. The live body and its Part 1, then the document, from files.
printf '%s' "$CJSON" | jq -j '.body // ""' > "$WORK/live.md" || stale "the live body could not be staged"
HAS_P1=0
if cb_part1 "$WORK/live.md" > "$WORK/part1.md"; then HAS_P1=1; fi
printf '%s' "$REC" > "$WORK/record.json" || stale "the record could not be staged"
jq -n --rawfile p1 "$WORK/part1.md" --argjson has "$HAS_P1" --slurpfile rec "$WORK/record.json" \
    --arg topic "$SLUG" --arg run "$RUN" --arg home "$HOME_REPO" --argjson pr "$C_NUM" \
    --arg hv "$HOME_VIS" --argjson vis "$VIS" --argjson states "$STATES" '
    $rec[0] as $r
    | ($r["run/setup"]) as $s
    | {topic: $topic,
       part1: (if $has == 1 then $p1 else null end),
       run_lines: ($s.run_lines // {}),
       store: $s.store,
       run: $run,
       nodes: $s.nodes,
       records: ([$r | to_entries[] | select(.key | startswith("run/node/"))
                  | {(.key | ltrimstr("run/node/")): .value}] | add // {}),
       follow_ups: (reduce ($r | to_entries[] | select(.key | startswith("run/follow-up/"))) as $e ({};
                      .[$e.key | split("/")[2]] += [$e.value])),
       states: $states,
       home: {repo: $home, pr: $pr, visibility: $hv},
       visibility: $vis}' > "$WORK/doc.json" || stale "the render document could not be built"

# 6. The render.
cb_render "$WORK/doc.json" > "$WORK/body.md"
case $? in
    0) ;;
    3) printf 'body=refused:execute:visibility\n'; exit 77 ;;
    4) echo "$PROG: the rendered body is over the cap; the coordination PR's body was not posted" >&2; finish full ;;
    *) stale "the record could not be rendered" ;;
esac
# A full-body rewrite keeps the run marker the live body carries and forges
# none (`run-id.sh carry`): a marker line below Part 1 is moved to the end of
# the render, and the render's size is checked again.
"$BASH" "$COORD_SELF_DIR/run-id.sh" carry "$WORK/live.md" "$WORK/body.md" </dev/null >&2 \
    || stale "the live body's run marker could not be carried into the render"
BYTES=$(wc -c < "$WORK/body.md") || stale "the rendered body could not be measured"
if [ "$((BYTES + 0))" -gt "$CB_MAX_BYTES" ]; then
    echo "$PROG: the rendered body is $((BYTES + 0)) bytes with its run marker, over the cap; the coordination PR's body was not posted" >&2
    finish full
fi

# 7. The validator, on what would be posted.
"${SHIRABE_BIN:-shirabe}" validate --coordination-body "$WORK/body.md" </dev/null >&2 \
    || stale "shirabe validate --coordination-body refused the rendered body"

# 8. No difference, no post.
SAME=$(jq -nr --rawfile a "$WORK/live.md" --rawfile b "$WORK/body.md" \
    'if ($a | sub("\n+$"; "")) == ($b | sub("\n+$"; "")) then "yes" else "no" end') \
    || stale "the rendered body could not be compared with the live one"
if [ "$SAME" = yes ]; then
    hand_out "$WORK/live.md"
    finish unchanged
fi

# 9. The body again, just before the post: a Part 1 edited since step 5 is
# a person's, and is never overwritten.
CJSON2=""
coord_gh_read CJSON2 pr view "$C_NUM" --repo "$HOME_REPO" --json state,body,headRefName,url \
    || stale "the coordination PR #$C_NUM could not be read again before the post"
printf '%s' "$CJSON2" | jq -j '.body // ""' > "$WORK/live2.md" || stale "the re-read body could not be staged"
HAS_P1_2=0
if cb_part1 "$WORK/live2.md" > "$WORK/part1-2.md"; then HAS_P1_2=1; fi
SAME=$(jq -nr --rawfile a "$WORK/part1.md" --rawfile b "$WORK/part1-2.md" 'if $a == $b then "yes" else "no" end') \
    || stale "the re-read Part 1 could not be compared"
if [ "$HAS_P1_2" -ne "$HAS_P1" ] || [ "$SAME" != yes ]; then
    stale "the coordination PR's Part 1 changed between the render and the post"
fi

# 10. The post.
gh pr edit "$C_NUM" --repo "$HOME_REPO" --body-file "$WORK/body.md" </dev/null >&2 \
    || stale "gh pr edit failed"
hand_out "$WORK/body.md"
finish posted
