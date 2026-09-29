#!/usr/bin/env bash
# reconcile-check.sh -- one reconcile re-check, printed as one fact.
#
# Each subcommand makes the reads for one claim in the coordinator's record
# and prints one fact in reconcile-report.sh's coordinate-reconcile-facts/v1
# shape: {kind, status: ok|not_verified, read_at, reason, ...}. A read that
# fails, runs past its deadline, or returns something this script can't
# interpret is a not_verified fact with the reason, not a failure of this
# script: reconcile reports what it couldn't read rather than stopping on it,
# and it never turns an unreadable answer into a verdict. Every value taken
# from a record row is checked against a fixed pattern before it reaches a
# command, and one that fails is a not_verified fact that reaches no command.
#
# Reads only. `gh` is called with read subcommands and `gh api` with GET;
# `git` only with ls-remote against a github.com repository, and, inside a
# worker's instance, with reads that neither take the index lock nor run
# anything the clone's config names (rd_git); `niwa` only with `list`; `koto`
# only with `request get`.
#
# Usage:
#   reconcile-check.sh pr       --repo R --number N
#   reconcile-check.sh board    --repo R --sha S --base B
#   reconcile-check.sh branch   --repo R --branch B
#   reconcile-check.sh appeared --repo R --branch B
#   reconcile-check.sh files    --repo R --number N
#   reconcile-check.sh merge    --repo R --number N --verified-head S
#   reconcile-check.sh close    --repo R --kind issue|pr --number N
#   reconcile-check.sh deferral --repo R --row-file F --run-start T [--chain-start T]
#   reconcile-check.sh host      --topic T
#   reconcile-check.sh teardown  --topic T
#   reconcile-check.sh leg       --return-path "leg <request>:<leg>"
#   reconcile-check.sh inventory --path <instance directory>
#
# Exit codes: 0 a fact printed; 64 usage error.
#
# Environment: RECONCILE_READ_DEADLINE, seconds per read (default 8), and
# RECONCILE_BOARD_DEADLINE for the board check (default 26, since the board
# check bounds itself at 24 s); each is clamped to 1-60. A deadline decides
# when a read gives up, never what it concludes: a read that gives up is not
# verified.
#
# Requires: bash 3.2+, jq, gh, git, niwa (host, teardown), koto (leg).
set -uo pipefail

PROG=reconcile-check
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=reconcile-deps.sh
. "$HERE/reconcile-deps.sh"

clamp_secs() { if rd_valid_secs "$1" && [ "$1" -le 60 ]; then echo "$1"; else echo "$2"; fi; }
DEADLINE=$(clamp_secs "${RECONCILE_READ_DEADLINE:-8}" 8)
BOARD_DEADLINE=$(clamp_secs "${RECONCILE_BOARD_DEADLINE:-26}" 26)
# The file list a scoping-ahead holding is judged by. Past this many files
# the fact says truncated, and the report doesn't call the holding
# consistent on a partial list.
FILES_CAP=300
# An inventory walks at most this many clones in one instance, and this many
# files or branch-changed files per clone; past either it says truncated.
INV_CLONE_CAP=20
INV_FILE_CAP=200
INV_ITEM_CAP=200
# GitHub containment reads for tips a clone can't settle locally, per run.
INV_COMPARE_CAP=40
INV_FIND_DEPTH=16

usage() {
    awk '/^# Usage:/{on=1} on&&/^# Exit codes/{exit} on' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 64
}

[ $# -ge 1 ] || usage
SUB=$1
shift
REPO="" NUMBER="" SHA="" BASE="" BRANCH="" KIND="" VHEAD="" ROWFILE="" RUNSTART="" CHAINSTART=""
TOPIC="" RETURN_PATH="" IPATH=""
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$1" in
        --repo) REPO=$2 ;;
        --number) NUMBER=$2 ;;
        --sha) SHA=$2 ;;
        --base) BASE=$2 ;;
        --branch) BRANCH=$2 ;;
        --kind) KIND=$2 ;;
        --verified-head) VHEAD=$2 ;;
        --row-file) ROWFILE=$2 ;;
        --run-start) RUNSTART=$2 ;;
        --chain-start) CHAINSTART=$2 ;;
        --topic) TOPIC=$2 ;;
        --return-path) RETURN_PATH=$2 ;;
        --path) IPATH=$2 ;;
        *) usage ;;
    esac
    shift 2
done

# refuse KIND REASON -- print the not_verified fact and stop.
refuse() { rd_not_verified "$1" "$2"; exit 0; }

need_repo()   { rd_valid_repo "$REPO" || refuse "$SUB" "invalid repository in the record row"; }
need_number() { rd_valid_number "$NUMBER" || refuse "$SUB" "invalid pull request or issue number in the record row"; }
need_branch() { rd_valid_branch "$BRANCH" || refuse "$SUB" "invalid branch in the record row"; }

# read_or_fail KIND SECS CMD... -- run CMD under a deadline; on failure print
# the not_verified fact and exit. CMD's stdout is left in $OUT.
read_or_fail() {
    local kind=$1 secs=$2 rc
    shift 2
    OUT=$(rd_deadline "$secs" "$@" 2>/dev/null)
    rc=$?
    [ "$rc" -eq 124 ] && refuse "$kind" "read timed out after ${secs}s"
    [ "$rc" -ne 0 ] && refuse "$kind" "read failed (exit $rc)"
    return 0
}

# blob_at PATH SHA -- the blob sha of PATH at commit SHA, or "absent" when the
# read says 404 (SHA is always a resolved commit, so a 404 is about the
# path). Returns 3 for a refused path, 4 for a read past its deadline, 2 for
# any other failed read.
blob_at() {
    local enc out rc
    enc=$(rd_urlencode_path "$1") || return 3
    out=$(rd_deadline "$DEADLINE" gh api "repos/$REPO/contents/$enc?ref=$2" --jq .sha 2>&1)
    rc=$?
    [ "$rc" -eq 124 ] && return 4
    if [ "$rc" -eq 0 ] && rd_valid_sha "$out"; then printf '%s' "$out"; return 0; fi
    case "$out" in *"HTTP 404"*) printf 'absent'; return 0 ;; esac
    return 2
}

# ---------------------------------------------------------------------------
# The inventory: what a worker's instance holds that exists nowhere else,
# read without writing and without running anything the clone's config names.
#
# It never runs `git status`: status refreshes the index, recurses into
# submodules with their own config, and runs clean and process filters, and
# no set of flags reliably turns all of that off. It reads plumbing that runs
# no filter instead -- ls-files, ls-tree, rev-list, cat-file, merge-base,
# diff --name-only -- and hashes working-tree files itself with
# `hash-object --no-filters --stdin-paths` (never -w, so nothing is written),
# in one process per clone. Every call is `ig`: rd_git (no fsmonitor, no
# hooks, no transport, no index lock) under the read deadline. A read that
# fails or runs late marks the clone unchecked, never empty.
#
# The default branch's content comes from one recursive tree read per clone
# (the contents API per file only when GitHub truncates that tree).
#
# Globals inv_clone sets for the helpers it calls: REPO (the clone's github.com
# origin), LIVE (its ls-remote read), DEFAULT (its default branch name),
# DEFAULT_SHA, TREE (the default branch's path -> blob map, a file) and
# EXCLUDE (^sha per live sha the clone has, a file). A linked worktree reuses
# the ones read for its repository.

# ig CLONE ARGS... -- one git read in CLONE, under the deadline.
ig() {
    local c=$1
    shift
    rd_deadline "$DEADLINE" rd_git -C "$c" "$@"
}

# ig_stdin CLONE FILE ARGS... -- as ig, with FILE on stdin. A background job's
# stdin is /dev/null, so the redirect lives inside the function it runs.
ig_in() { local c=$1 f=$2; shift 2; rd_git -C "$c" "$@" < "$f"; }
ig_stdin() { rd_deadline "$DEADLINE" ig_in "$@"; }

# inv_item CLONE KIND PATH -- for an unchecked item, PATH is the reason.
inv_item() {
    INV_N=$((INV_N + 1))
    if [ "$INV_N" -gt "$INV_ITEM_CAP" ]; then TRUNC=true; return 0; fi
    jq -nc --arg c "$1" --arg k "$2" --arg p "$3" '{clone: $c, kind: $k, path: $p}' >> "$ITEMS"
}

# inv_queue DIR -- add a clone's directory to the walk, once, if it is inside
# the instance. Returns 1 for a directory outside it.
inv_queue() {
    local r q
    r=$(cd -P "$1" 2>/dev/null && pwd -P) || return 0
    case "$r/" in "$IROOT"/*) ;; *) return 1 ;; esac
    for q in ${QUEUE[@]+"${QUEUE[@]}"}; do [ "$q" = "$r" ] && return 0; done
    QUEUE+=("$r")
}

# default_blob PATH -- the default branch's blob sha for PATH, or "absent".
# From the tree map, or from the contents API when GitHub truncated the tree
# and PATH isn't in the part it returned. Returns 1 when that can't be read.
default_blob() {
    local b
    b=$(jq -r --arg p "$1" '.blobs[$p] // (if .truncated then "?" else "absent" end)' "$TREE" 2>/dev/null) || return 1
    if [ "$b" = "?" ]; then
        blob_at "$1" "$DEFAULT_SHA" || return 1
        return 0
    fi
    printf '%s' "$b"
}

# gh_contains SHA TARGET -- ask GitHub whether commit SHA is TARGET or an
# ancestor of it, for a clone that hasn't fetched TARGET: 0 contained; 1 not
# contained, or SHA isn't on GitHub; 2 the read failed, ran late, or the run
# has spent its INV_COMPARE_CAP reads.
gh_contains() {
    local out rc
    INV_COMPARES=$((INV_COMPARES + 1))
    if [ "$INV_COMPARES" -gt "$INV_COMPARE_CAP" ]; then TRUNC=true; return 2; fi
    out=$(rd_deadline "$DEADLINE" gh api "repos/$REPO/compare/$1...$2" --jq '.behind_by' 2> "$ITEMS.cmp.err")
    rc=$?
    if [ "$rc" -ne 0 ]; then
        [ "$rc" -ne 124 ] && grep -q 'HTTP 404' "$ITEMS.cmp.err" && return 1
        return 2
    fi
    case "$out" in 0) return 0 ;; [1-9]*) return 1 ;; *) return 2 ;; esac
}

# is_local CLONE SHA -- 0 when SHA is a commit this clone has.
is_local() { ig "$1" cat-file -e "$2^{commit}" >/dev/null 2>&1; }

# live_sha REF -- REF's sha in the ls-remote read, or nothing.
live_sha() {
    printf '%s\n' "$LIVE" | awk -v r="$1" 'length($1) == 40 && $1 ~ /^[0-9a-f]+$/ && $2 == r { print $1; exit }'
}

# local_default CLONE -- a commit in this clone that GitHub's default branch
# contains, standing in for a default tip the clone hasn't fetched: its
# remote-tracking default, else its local default branch.
local_default() {
    local c=$1 r s
    for r in "refs/remotes/origin/$DEFAULT" "refs/heads/$DEFAULT"; do
        s=$(ig "$c" rev-parse --verify --quiet "$r^{commit}" 2>/dev/null) || continue
        rd_valid_sha "$s" || continue
        gh_contains "$s" "$DEFAULT_SHA" && { printf '%s' "$s"; return 0; }
    done
    return 1
}

# inv_landed CLONE TIP -- 0 when every file TIP changes against its merge base
# with the default branch has, on the default branch, the content it has at
# TIP (a squash-landed branch); 1 otherwise or when that can't be read. In a
# clone that hasn't fetched the default tip, the merge base is taken with
# local_default's commit; the content is still compared with GitHub's current
# tree.
inv_landed() {
    local c=$1 tip=$2 base want have nf=0 f against=$DEFAULT_SHA
    is_local "$c" "$DEFAULT_SHA" || against=$(local_default "$c") || return 1
    base=$(ig "$c" merge-base "$tip" "$against" 2>/dev/null) || return 1
    rd_valid_sha "$base" || return 1
    ig "$c" diff --name-only -z "$base" "$tip" > "$ITEMS.diff" 2>/dev/null || return 1
    while IFS= read -r -d '' f; do
        nf=$((nf + 1))
        [ "$nf" -gt "$INV_FILE_CAP" ] && return 1
        want=$(ig "$c" rev-parse --verify --quiet "$tip:$f" 2>/dev/null) || want=absent
        have=$(default_blob "$f") || return 1
        [ "$want" = "$have" ] || return 1
    done < "$ITEMS.diff"
    return 0
}

# nul_lines IN OUT -- NUL-separated IN as one path per line in OUT. Returns 1
# when a path holds a newline, which a line can't carry.
nul_lines() {
    [ -z "$(tr -cd '\n' < "$1")" ] || return 1
    tr '\0' '\n' < "$1" > "$2"
}

# inv_hash CLONE LIST OUT -- "path<TAB>hash" per regular file in LIST, from one
# hash-object --no-filters --stdin-paths. Returns 1 when the hashes can't be
# read or don't line up with the paths.
inv_hash() {
    : > "$3"
    [ -s "$2" ] || return 0
    ig_stdin "$1" "$2" hash-object --no-filters --stdin-paths > "$3.h" 2>/dev/null || return 1
    [ "$(wc -l < "$2")" -eq "$(wc -l < "$3.h")" ] || return 1
    awk 'NR == FNR { p[FNR] = $0; next } { print p[FNR] "\t" $0 }' "$2" "$3.h" > "$3"
}

# inv_files CLONE REL -- tracked, staged, deleted and untracked changes.
inv_files() {
    local C=$1 REL=$2 meta path tag mode sha line have nf=0
    if ! ig "$C" ls-files -z -s -v > "$ITEMS.idx0" 2>/dev/null; then
        inv_item "$REL" unchecked "the index could not be read"; return
    fi
    nul_lines "$ITEMS.idx0" "$ITEMS.idx" || { inv_item "$REL" unchecked "a tracked path holds a newline"; return; }
    # HEAD's tree; an unborn HEAD has none, and every index entry is staged.
    if ig "$C" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
        ig "$C" ls-tree -r -z --full-tree HEAD > "$ITEMS.head0" 2>/dev/null \
            || { inv_item "$REL" unchecked "HEAD's tree could not be read"; return; }
        nul_lines "$ITEMS.head0" "$ITEMS.head" || { inv_item "$REL" unchecked "a tracked path holds a newline"; return; }
    else
        : > "$ITEMS.head"
    fi
    : > "$ITEMS.present"; : > "$ITEMS.deleted"
    : > "$ITEMS.links"
    # Split each "TAG MODE SHA STAGE<TAB>path" by hand: `read` with IFS set to
    # a tab strips a path's own leading and trailing tabs.
    while IFS= read -r line; do
        meta=${line%%$'\t'*}
        path=${line#*$'\t'}
        tag=${meta%% *}; mode=${meta#* }; mode=${mode%% *}
        if [ "$mode" = 160000 ]; then
            # A submodule: walked as a clone of its own, never through the
            # superproject's git.
            [ -e "$C/$path/.git" ] && { inv_queue "$C/$path" || inv_item "$REL" unchecked "$path (submodule outside the instance)"; }
            continue
        fi
        if [ -L "$C/$path" ]; then
            # A tracked symlink's blob is its link text: compared like a file,
            # so an unchanged one isn't listed on every run.
            if [ "$mode" = 120000 ]; then printf '%s\n' "$path" >> "$ITEMS.links"
            else inv_item "$REL" file "$path (symlink, not read)"; fi
            continue
        fi
        if [ -f "$C/$path" ]; then printf '%s\n' "$path" >> "$ITEMS.present"; continue; fi
        # Missing: a skip-worktree entry (sparse checkout) is meant to be
        # absent; anything else was deleted in the working tree.
        [ "$tag" = S ] || printf '%s\n' "$path" >> "$ITEMS.deleted"
    done < "$ITEMS.idx"
    inv_hash "$C" "$ITEMS.present" "$ITEMS.wt" || { inv_item "$REL" unchecked "working-tree files could not be hashed"; return; }
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        printf '%s' "$(readlink "$C/$path")" > "$ITEMS.lt"
        have=$(ig_stdin "$C" "$ITEMS.lt" hash-object --no-filters --stdin 2>/dev/null) || { inv_item "$REL" file "$path (symlink)"; continue; }
        printf '%s\t%s\n' "$path" "$have" >> "$ITEMS.wt"
    done < "$ITEMS.links"

    if ! ig "$C" ls-files -z --others --exclude-standard > "$ITEMS.oth0" 2>/dev/null; then
        inv_item "$REL" unchecked "untracked files could not be listed"; return
    fi
    nul_lines "$ITEMS.oth0" "$ITEMS.oth" || { inv_item "$REL" unchecked "an untracked path holds a newline"; return; }
    : > "$ITEMS.othp"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
            */) [ -e "$C/$path.git" ] && { inv_queue "$C/$path" || inv_item "$REL" unchecked "$path (nested repository outside the instance)"; }
                continue ;;
        esac
        nf=$((nf + 1))
        if [ "$nf" -gt "$INV_FILE_CAP" ]; then TRUNC=true; break; fi
        if [ -L "$C/$path" ]; then inv_item "$REL" file "$path (symlink, not read)"; continue; fi
        [ -f "$C/$path" ] && printf '%s\n' "$path" >> "$ITEMS.othp"
    done < "$ITEMS.oth"
    inv_hash "$C" "$ITEMS.othp" "$ITEMS.othh" || { inv_item "$REL" unchecked "untracked files could not be hashed"; return; }

    # One comparison: a path is unique unless the content that differs from
    # HEAD (staged) or from the index (working tree) is the default branch's.
    jq -rn --rawfile idx "$ITEMS.idx" --rawfile head "$ITEMS.head" --rawfile wt "$ITEMS.wt" \
        --rawfile del "$ITEMS.deleted" --rawfile oth "$ITEMS.othh" --slurpfile tree "$TREE" '
        def lines($s): $s | split("\n") | map(select(length > 0));
        # "meta<TAB>path": the path is everything after the first tab.
        def metapath: split("\t") | {meta: (.[0] | split(" ")), path: (.[1:] | join("\t"))};
        # "path<TAB>hash": the hash is the last field.
        def pathhash: split("\t") | {key: (.[:-1] | join("\t")), value: .[-1]};
        ($tree[0].blobs // {}) as $def | ($tree[0].truncated // false) as $trunc
        | [lines($idx)[] | metapath | select(.meta[1] != "160000") | {key: .path, value: .meta[2]}] | from_entries as $index
        | [lines($head)[] | metapath | select(.meta[0] != "160000") | {key: .path, value: .meta[2]}] | from_entries as $headmap
        | [lines($wt)[] | pathhash] | from_entries as $work
        # unique unless the content is on the default branch; "absent" means
        # the path is gone, which the default branch may agree with.
        # A truncated tree speaks only for the paths it holds; any other path
        # is asked of the contents API, deletions included.
        | def verdict($p; $sha): if ($def | has($p)) then (if $def[$p] == $sha then empty else "unique" end)
                                 elif $trunc then "ask"
                                 elif $sha == "absent" then empty
                                 else "unique" end;
          ( ($index | to_entries[] | .key as $p | .value as $i
              | ((if ($headmap[$p] // "") != $i then verdict($p; $i) | "\(.)\tchange\t\($i)\t\($p)" else empty end),
                 (if ($work | has($p)) and $work[$p] != $i then verdict($p; $work[$p]) | "\(.)\tchange\t\($work[$p])\t\($p)" else empty end))),
            ($headmap | keys[] as $p | select(($index | has($p)) | not)
              | verdict($p; "absent") | "\(.)\tdeleted\tabsent\t\($p)"),
            (lines($del)[] | . as $p | verdict($p; "absent") | "\(.)\tdeleted\tabsent\t\($p)"),
            ([lines($oth)[] | pathhash][] | .key as $p | .value as $h | verdict($p; $h) | "\(.)\tfile\t\($h)\t\($p)")
          ) ' > "$ITEMS.cmp" 2>/dev/null || { inv_item "$REL" unchecked "the comparison could not be made"; return; }
    # "ask": GitHub truncated the tree and the path is in the part it left out.
    local verdict kind p want have
    while IFS= read -r line; do
        verdict=${line%%$'\t'*}; line=${line#*$'\t'}
        kind=${line%%$'\t'*}; line=${line#*$'\t'}
        want=${line%%$'\t'*}; p=${line#*$'\t'}
        [ "$TRUNC" = true ] && [ "$INV_N" -ge "$INV_ITEM_CAP" ] && break
        if [ "$verdict" = ask ]; then
            have=$(default_blob "$p") || have="?"
            [ "$have" = "$want" ] && continue
        fi
        if [ "$kind" = deleted ]; then inv_item "$REL" change "$p (deleted)"; else inv_item "$REL" "$kind" "$p"; fi
    done < "$ITEMS.cmp"
}

# inv_clone DIR -- inventory one clone.
# inv_remote_has CLONE TIP NAME -- for a tip with commits outside the live
# shas the clone has, ask GitHub whether the default branch, or the remote
# branch of the same name, contains it, for each of those the clone hasn't
# fetched: a stale clone's pushed main, or a branch pushed and then extended
# from elsewhere. 0 contained; 1 not; 2 a read that couldn't answer.
inv_remote_has() {
    local c=$1 tip=$2 name=$3 cand same="" unknown=false
    [ "${name#branch }" != "$name" ] && same=$(live_sha "refs/heads/${name#branch }")
    [ "$same" = "$DEFAULT_SHA" ] && same=""
    for cand in "$DEFAULT_SHA" "$same"; do
        rd_valid_sha "$cand" || continue
        is_local "$c" "$cand" && continue
        gh_contains "$tip" "$cand"
        case $? in 0) return 0 ;; 2) unknown=true ;; esac
    done
    [ "$unknown" = true ] && return 2
    return 1
}

# inv_tips CLONE REL -- list each tip in $ITEMS.tips (sha TAB name) holding a
# commit found nowhere else: outside the live shas the clone has, not
# contained in GitHub's default or same-named branch, and not squash-landed.
# One rev-list per tip, no cap on refs.
inv_tips() {
    local C=$1 REL=$2 tip bname n
    while IFS=$'\t' read -r tip bname; do
        rd_valid_sha "$tip" || continue
        { printf '%s\n' "$tip"; cat "$EXCLUDE"; } > "$ITEMS.revs"
        n=$(ig_stdin "$C" "$ITEMS.revs" rev-list --stdin --count 2>/dev/null) \
            || { inv_item "$REL" unchecked "$bname could not be compared with the remote"; continue; }
        [ "$n" = 0 ] && continue
        inv_remote_has "$C" "$tip" "$bname"
        case $? in
            0) continue ;;
            2) inv_item "$REL" unchecked "$bname could not be compared with the remote"; continue ;;
        esac
        inv_landed "$C" "$tip" || inv_item "$REL" commit "$bname"
    done < "$ITEMS.tips"
}

# inv_detached CLONE -- a detached HEAD as a tip line, or nothing.
inv_detached() {
    local tip
    ig "$1" symbolic-ref -q HEAD >/dev/null 2>&1 && return 0
    tip=$(ig "$1" rev-parse --verify --quiet HEAD 2>/dev/null) && printf '%s\tdetached HEAD\n' "$tip"
    return 0
}

inv_clone() {
    local C=$1 REL URL loc common top n line w wr k
    REL=${C#"$IROOT"}; REL=${REL#/}; [ -n "$REL" ] || REL=.
    if [ -L "$C/.git" ]; then inv_item "$REL" unchecked "its .git is a symlink, not read"; return; fi
    loc=$(ig "$C" rev-parse --path-format=absolute --git-common-dir --show-toplevel 2>/dev/null) \
        || { inv_item "$REL" unchecked "not a readable repository"; return; }
    common=$(printf '%s\n' "$loc" | sed -n 1p); top=$(printf '%s\n' "$loc" | sed -n 2p)
    common=$(cd -P "$common" 2>/dev/null && pwd -P) || common=/
    top=$(cd -P "$top" 2>/dev/null && pwd -P) || top=/
    case "$common/" in "$IROOT"/*) ;; *) inv_item "$REL" unchecked "its git directory is outside the instance, not read"; return ;; esac
    [ "$top" = "$C" ] || { inv_item "$REL" unchecked "its working tree is set elsewhere (core.worktree), not read"; return; }
    # A linked worktree of a repository already read shares its refs, stash
    # and worktree list, so only its own HEAD and files are read, against the
    # remote reads made for that repository (or not at all when those failed:
    # the repository is already marked unchecked).
    k=0
    while [ "$k" -lt "${#SEEN_COMMON[@]}" ]; do
        if [ "${SEEN_COMMON[$k]}" = "$common" ]; then
            [ -s "$ITEMS.live.$k" ] || return 0
            REPO=$(sed -n 1p "$ITEMS.live.$k"); DEFAULT=$(sed -n 2p "$ITEMS.live.$k")
            DEFAULT_SHA=$(sed -n 3p "$ITEMS.live.$k"); LIVE=$(sed '1,3d' "$ITEMS.live.$k")
            TREE="$ITEMS.tree.$k"; EXCLUDE="$ITEMS.exclude.$k"
            inv_detached "$C" > "$ITEMS.tips"
            inv_tips "$C" "$REL"
            inv_files "$C" "$REL"
            return
        fi
        k=$((k + 1))
    done
    SEEN_COMMON+=("$common")
    URL=$(ig "$C" config --get remote.origin.url 2>/dev/null)
    if ! REPO=$(rd_github_repo "$URL"); then
        inv_item "$REL" unchecked "no github.com origin to compare against"; return
    fi
    # From /, so no repository's config (the caller's included) applies.
    LIVE=$(RD_GIT_PROTOCOL=https rd_deadline "$DEADLINE" rd_git -C / -c protocol.https.allow=always ls-remote --symref "https://github.com/$REPO.git" 2>/dev/null) \
        || { inv_item "$REL" unchecked "remote refs could not be read"; return; }
    DEFAULT=$(printf '%s\n' "$LIVE" | awk '$1 == "ref:" && $3 == "HEAD" { sub("refs/heads/", "", $2); print $2; exit }')
    DEFAULT_SHA=$(printf '%s\n' "$LIVE" | awk -v r="refs/heads/$DEFAULT" 'length($1) == 40 && $1 ~ /^[0-9a-f]+$/ && $2 == r { print $1; exit }')
    rd_valid_sha "$DEFAULT_SHA" || { inv_item "$REL" unchecked "the default branch could not be resolved"; return; }
    TREE="$ITEMS.tree.$k"
    rd_deadline "$DEADLINE" gh api "repos/$REPO/git/trees/$DEFAULT_SHA?recursive=1" \
        --jq '{truncated: .truncated, blobs: ([.tree[] | select(.type == "blob") | {key: .path, value: .sha}] | from_entries)} | tojson' \
        > "$TREE" 2>/dev/null && jq -e '.blobs | type == "object"' "$TREE" >/dev/null 2>&1 \
        || { inv_item "$REL" unchecked "the default branch's tree could not be read"; return; }

    # Commits: a tip (local branches, local tags, a detached HEAD) is pushed
    # when rev-list finds no commit of it outside the live shas this clone
    # has, or GitHub says a live branch the clone hasn't fetched contains it.
    EXCLUDE="$ITEMS.exclude.$k"
    printf '%s\n' "$LIVE" | awk 'length($1) == 40 && $1 ~ /^[0-9a-f]+$/ { print $1 }' | sort -u > "$ITEMS.shas"
    ig_stdin "$C" "$ITEMS.shas" cat-file --batch-check='%(objectname) %(objecttype)' 2>/dev/null \
        | awk '$2 == "commit" { print "^" $1 }' > "$EXCLUDE"
    printf '%s\n%s\n%s\n%s\n' "$REPO" "$DEFAULT" "$DEFAULT_SHA" "$LIVE" > "$ITEMS.live.$k"
    {
        ig "$C" for-each-ref refs/heads refs/tags --format='%(objectname)%09%(refname)' 2>/dev/null \
            | awk -F'\t' '{ r = $2; sub(/^refs\/heads\//, "branch ", r); sub(/^refs\/tags\//, "tag ", r); print $1 "\t" r }'
        inv_detached "$C"
    } > "$ITEMS.tips"
    inv_tips "$C" "$REL"

    # A stash is local by nature: listed whenever it exists.
    if ig "$C" rev-parse --verify --quiet refs/stash >/dev/null 2>&1; then
        n=$(ig "$C" rev-list --walk-reflogs --count refs/stash 2>/dev/null) || n="?"
        inv_item "$REL" change "stash ($n entries)"
    fi

    inv_files "$C" "$REL"

    # Worktrees: one inside the instance is walked like a clone; one outside
    # is listed, not read.
    ig "$C" worktree list --porcelain > "$ITEMS.wt0" 2>/dev/null || inv_item "$REL" unchecked "worktrees could not be listed"
    while IFS= read -r line; do
        case "$line" in "worktree "*) ;; *) continue ;; esac
        w=${line#worktree }
        wr=$(cd -P "$w" 2>/dev/null && pwd -P) || continue
        [ "$wr" = "$C" ] && continue
        inv_queue "$wr" || inv_item "$REL" worktree "$(basename "$w") (outside the instance, not read)"
    done < "$ITEMS.wt0"
}

# board_fact -- map board-verdict.sh's object to a board fact. A verdict it
# doesn't recognise is not verified: an unknown answer is not a failing board.
board_fact() {
    jq -c --arg sha "$SHA" --arg t "$(rd_now)" '
        def first_reason: (.reasons // [])[0]
          | if . == null then ""
            else (.name // .code // "") + (if (.detail // "") != "" then " (" + .detail + ")" else "" end) end;
        if (.verdict | type) != "string" then error("shape")
        elif .verdict == "verified" then {kind: "board", status: "ok", at: $sha, verdict: "holds", detail: "", read_at: $t}
        elif .verdict == "pending" then {kind: "board", status: "ok", at: $sha, verdict: "pending", detail: first_reason, read_at: $t}
        elif .verdict == "unverified" then {kind: "board", status: "ok", at: $sha, verdict: "fails", detail: first_reason, read_at: $t}
        else {kind: "board", status: "not_verified", at: $sha, reason: ("board " + .verdict), read_at: $t} end'
}

case "$SUB" in
pr)
    need_repo; need_number
    read_or_fail pr "$DEADLINE" gh pr view "$NUMBER" --repo "$REPO" --json state,isDraft,headRefOid,mergeStateStatus,baseRefName
    printf '%s' "$OUT" | jq -ce --arg t "$(rd_now)" '
        select((.state | IN("OPEN", "MERGED", "CLOSED")) and (.headRefOid | test("^[0-9a-f]{40}$")))
        | {kind: "pr", status: "ok", state, draft: (.isDraft == true), head: .headRefOid,
           merge_state: .mergeStateStatus, base: .baseRefName, read_at: $t}' 2>/dev/null \
        || refuse pr "unreadable pull request response"
    ;;

board)
    need_repo
    rd_valid_sha "$SHA" || refuse board "invalid sha"
    rd_valid_branch "$BASE" || refuse board "invalid base branch"
    read_or_fail board "$BOARD_DEADLINE" "$RD_BOARD_CHECK" --repo "$REPO" --sha "$SHA" --base "$BASE"
    printf '%s' "$OUT" | board_fact 2>/dev/null || refuse board "unreadable board verdict"
    ;;

branch)
    need_repo; need_branch
    read_or_fail branch "$DEADLINE" git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH"
    TIP=$(printf '%s\n' "$OUT" | awk -v r="refs/heads/$BRANCH" '$2 == r { print $1; exit }')
    if [ -z "$TIP" ]; then
        jq -nc --arg t "$(rd_now)" '{kind: "branch", status: "ok", state: "gone", tip: null, read_at: $t}'
    elif rd_valid_sha "$TIP"; then
        jq -nc --arg tip "$TIP" --arg t "$(rd_now)" '{kind: "branch", status: "ok", state: "present", tip: $tip, read_at: $t}'
    else
        refuse branch "unreadable ls-remote output"
    fi
    ;;

appeared)
    need_repo; need_branch
    read_or_fail appeared "$DEADLINE" gh pr list --repo "$REPO" --head "$BRANCH" --state all --json number,state,url
    printf '%s' "$OUT" | jq -ce --arg t "$(rd_now)" '
        select(type == "array")
        | {kind: "appeared", status: "ok", prs: [.[] | {number, state, url}], read_at: $t}' 2>/dev/null \
        || refuse appeared "unreadable pull request list"
    ;;

files)
    need_repo; need_number
    # One JSON string per path, both sides of a rename, so a path holding a
    # tab or a newline arrives intact rather than split.
    read_or_fail files "$DEADLINE" gh api "repos/$REPO/pulls/$NUMBER/files?per_page=100" --paginate \
        --jq '.[] | .filename, (.previous_filename // empty) | tojson'
    printf '%s\n' "$OUT" | jq -sc --argjson cap "$FILES_CAP" --arg t "$(rd_now)" '
        {kind: "files", status: "ok", paths: .[0:$cap], truncated: (length > $cap), read_at: $t}' 2>/dev/null \
        || refuse files "unreadable file list"
    ;;

merge)
    # The record feature's own merge check, so a restart's reconcile and the
    # loop's merge_confirm read a side effect by one rule: the pull request is
    # merged and every file it changed has, on the default branch, the content
    # it had at the verified head ("Confirming a Merge" in
    # references/verification-checklist.md).
    need_repo; need_number
    rd_valid_sha "$VHEAD" || refuse merge "invalid verified head in the side-effect row"
    R=$(rd_merge_compare "$DEADLINE" "$REPO" "$NUMBER" "$VHEAD") || refuse merge "a merge read failed"
    case "$R" in
        merged) verdict=confirmed reason="" ;;
        unconfirmed) verdict=not_confirmed reason="a file the pull request changed differs on the default branch from the verified head" ;;
        not-merged) verdict=not_confirmed reason="pull request is not merged" ;;
        *) refuse merge "unreadable merge verdict" ;;
    esac
    jq -nc --arg v "$verdict" --arg r "$reason" --arg t "$(rd_now)" \
        '{kind: "merge", status: "ok", verdict: $v, reason: $r, read_at: $t}'
    ;;

close)
    # A close is settled when the target reads closed; a merged pull request
    # is closed too.
    need_repo; need_number
    case "$KIND" in issue|pr) ;; *) usage ;; esac
    read_or_fail close "$DEADLINE" gh "$KIND" view "$NUMBER" --repo "$REPO" --json state
    printf '%s' "$OUT" | jq -ce --arg t "$(rd_now)" '
        select(.state | IN("OPEN", "CLOSED", "MERGED"))
        | (.state != "OPEN") as $done
        | {kind: "close", status: "ok", verdict: (if $done then "confirmed" else "not_confirmed" end),
           reason: (if $done then "" else "target is open" end), read_at: $t}' 2>/dev/null \
        || refuse close "unreadable state"
    ;;

deferral)
    need_repo
    [ -f "$ROWFILE" ] || usage
    # koto's created_at carries milliseconds; both forms are a time.
    RE_START='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?Z$'
    [[ $RUNSTART =~ $RE_START ]] || usage
    CHAIN=()
    if [ -n "$CHAINSTART" ]; then [[ $CHAINSTART =~ $RE_START ]] || usage; CHAIN=(--chain-start "$CHAINSTART"); fi
    RAW=$(rd_deadline "$DEADLINE" "$RD_DEFERRAL_CHECK" --row-file "$ROWFILE" --run-start "$RUNSTART" ${CHAIN[@]+"${CHAIN[@]}"} 2>/dev/null)
    rc=$?
    [ "$rc" -eq 124 ] && refuse deferral "disposal check timed out after ${DEADLINE}s"
    # The check prints one line; anything else is an answer this script
    # doesn't interpret.
    case "$RAW" in *$'\n'*) refuse deferral "disposal check printed more than one line" ;; esac
    case "$rc:$RAW" in
        0:"disposed filed "*)
            N=${RAW#disposed filed }
            N=${N#\#}
            rd_valid_number "$N" || refuse deferral "disposal names an unreadable issue number"
            # An issue that can't be read is not verified rather than
            # undisposed: gh doesn't tell a missing issue from a failed read.
            read_or_fail deferral "$DEADLINE" gh issue view "$N" --repo "$REPO" --json number
            jq -nc --arg how "filed #$N" --arg t "$(rd_now)" \
                '{kind: "deferral", status: "ok", disposed: true, how: $how, read_at: $t}' ;;
        0:"disposed closed"|0:"disposed carried "*)
            jq -nc --arg how "${RAW#disposed }" --arg t "$(rd_now)" \
                '{kind: "deferral", status: "ok", disposed: true, how: $how, read_at: $t}' ;;
        0:"undisposed raised-this-run")
            jq -nc --arg t "$(rd_now)" \
                '{kind: "deferral", status: "ok", disposed: true, how: "raised this run", read_at: $t}' ;;
        1:"undisposed "*)
            jq -nc --arg why "${RAW#undisposed }" --arg t "$(rd_now)" \
                '{kind: "deferral", status: "ok", disposed: false, how: $why, read_at: $t}' ;;
        *)
            refuse deferral "disposal check failed (exit $rc)" ;;
    esac
    ;;

host)
    # One listing read. A miss is reported as missed, never as gone: the
    # pass re-reads after 30 seconds before it says "not found on this read".
    [[ $TOPIC =~ ^[A-Za-z0-9][A-Za-z0-9\ _.-]{0,79}$ ]] || refuse host "invalid dispatch topic in the record row"
    SLUG=$(rd_slug "$TOPIC")
    [ -n "$SLUG" ] || refuse host "the dispatch topic has no usable slug"
    read_or_fail host "$DEADLINE" niwa list --json
    printf '%s' "$OUT" | jq -ce --arg s "$SLUG" --arg t "$(rd_now)" '
        select(type == "array")
        | [.[] | select(((.name // "") | test("\\+" + $s + "-[0-9a-f]{8}$"))
                        or ((.session_name // "") | test("^" + $s + "-[0-9a-f]{8}$")))] as $m
        | if ($m | length) == 1 then {kind: "host", status: "ok", state: "found", reads: 1, path: $m[0].path, read_at: $t}
          elif ($m | length) > 1 then {kind: "host", status: "ok", state: "ambiguous", reads: 1, read_at: $t}
          else {kind: "host", status: "ok", state: "missed", reads: 1, read_at: $t} end' 2>/dev/null \
        || refuse host "unreadable workspace listing"
    ;;

teardown)
    # Settled when the listing has no instance for the topic and no instance
    # directory for it is left in the workspace root. One read; the pass
    # re-reads a miss before it relies on it, as it does for host.
    [[ $TOPIC =~ ^[A-Za-z0-9][A-Za-z0-9\ _.-]{0,79}$ ]] || refuse teardown "invalid dispatch topic in the side-effect row"
    SLUG=$(rd_slug "$TOPIC")
    [ -n "$SLUG" ] || refuse teardown "the dispatch topic has no usable slug"
    read_or_fail teardown "$DEADLINE" niwa list --json
    LISTED=$(printf '%s' "$OUT" | jq -r --arg s "$SLUG" '
        [.[] | select(((.name // "") | test("\\+" + $s + "-[0-9a-f]{8}$"))
                      or ((.session_name // "") | test("^" + $s + "-[0-9a-f]{8}$")))] | length' 2>/dev/null) \
        || refuse teardown "unreadable workspace listing"
    [[ $LISTED =~ ^[0-9]+$ ]] || refuse teardown "unreadable workspace listing"
    # The workspace root is the directory every listed instance sits in.
    WROOT=$(printf '%s' "$OUT" | jq -r '[.[].path | select(type == "string") | sub("/[^/]+$"; "")] | unique | if length == 1 then .[0] else empty end' 2>/dev/null)
    [ -n "$WROOT" ] && [ -d "$WROOT" ] || refuse teardown "the workspace root could not be found from the listing"
    LEFT=0
    for d in "$WROOT"/*+"$SLUG"-????????; do
        [ -d "$d" ] && case "${d##*-}" in *[!0-9a-f]*) ;; *) LEFT=1 ;; esac
    done
    if [ "$LISTED" -eq 0 ] && [ "$LEFT" -eq 0 ]; then
        jq -nc --arg t "$(rd_now)" '{kind: "teardown", status: "ok", verdict: "confirmed", reason: "", reads: 1, read_at: $t}'
    else
        jq -nc --arg t "$(rd_now)" --argjson l "$LISTED" --argjson d "$LEFT" \
            '{kind: "teardown", status: "ok", verdict: "not_confirmed",
              reason: (if $l > 0 then "the instance is still listed" else "its instance directory is still on disk" end), read_at: $t}'
    fi
    ;;

leg)
    # Only a holding whose return path names a leg has one to read.
    case "$RETURN_PATH" in
        message) refuse leg "the holding reports by message; no leg to read" ;;
        "leg "*) ;;
        *) refuse leg "unreadable return path in the record row" ;;
    esac
    SPEC=${RETURN_PATH#leg }
    REQ=${SPEC%%:*}
    LEG=${SPEC#*:}
    [[ $REQ =~ ^[a-z0-9_][a-z0-9_-]{0,63}$ ]] || refuse leg "invalid request id in the record row"
    [[ $LEG =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || refuse leg "invalid leg name in the record row"
    # koto prints its errors as JSON on stdout too, and a missing store reads
    # exactly like an unknown request: both are "not on this host".
    OUT=$(rd_deadline "$DEADLINE" koto request get "$REQ" </dev/null 2>/dev/null)
    rc=$?
    [ "$rc" -eq 124 ] && refuse leg "read timed out after ${DEADLINE}s"
    [ "$rc" -eq 2 ] && refuse leg "request not found on this host"
    [ "$rc" -ne 0 ] && refuse leg "read failed (exit $rc)"
    printf '%s' "$OUT" | jq -ce --arg l "$LEG" --arg t "$(rd_now)" '
        (.legs[$l] // null) as $leg
        | select($leg != null and ($leg.disposition | IN("open", "resolved", "abandoned")))
        | {kind: "leg", status: "ok",
           disposition: (if $leg.disposition == "open" and $leg.bound_child != null then "bound" else $leg.disposition end),
           result: (
             if $leg.result_source == "refused" then
               "refused:" + (($leg.result.payload.reason // $leg.result.summary // "unknown") | tostring)
             elif $leg.result == null then ""
             elif ($leg.result.payload.outcome | type) == "string" then $leg.result.payload.outcome
             else $leg.result.status + (if $leg.result_final_state then " at " + $leg.result_final_state else "" end)
             end),
           read_at: $t}' 2>/dev/null \
        || refuse leg "the request has no readable leg by that name"
    ;;

inventory)
    [ -n "$IPATH" ] || usage
    case "$IPATH" in /*) ;; *) refuse inventory "instance path is not absolute" ;; esac
    [ -d "$IPATH" ] && [ ! -L "$IPATH" ] || refuse inventory "instance directory not found on this host"
    IROOT=$(cd -P "$IPATH" 2>/dev/null && pwd -P) || refuse inventory "instance directory can't be read"
    ITEMS=$(mktemp "${TMPDIR:-/tmp}/reconcile-inv.XXXXXX")
    trap 'rm -f "$ITEMS" "$ITEMS".*' EXIT
    TRUNC=false
    INV_N=0
    QUEUE=()
    SEEN_COMMON=()
    INV_COMPARES=0
    # find -P follows no symlinks; a .git file marks a linked worktree. Every
    # directory is searched, ignored ones included, to INV_FIND_DEPTH; clones
    # deeper than that are reached only through worktree lists, submodule
    # entries and untracked directories.
    # Into a file, so a search that runs late is seen: the clones it hadn't
    # reached would otherwise just be missing. A .git directory is printed and
    # then not descended into.
    rd_deadline "$DEADLINE" find -P "$IROOT" -maxdepth "$INV_FIND_DEPTH" -name .git \( -type d -o -type f -o -type l \) -print -prune \
        > "$ITEMS.found" 2>/dev/null
    case $? in
        0) ;;
        124) TRUNC=true; inv_item . unchecked "the search for clones timed out; clones it hadn't reached were not read" ;;
        *) TRUNC=true; inv_item . unchecked "the search for clones failed partway" ;;
    esac
    while IFS= read -r gitpath; do
        [ -n "$gitpath" ] && inv_queue "$(dirname "$gitpath")"
    done < <(sort "$ITEMS.found")
    i=0
    while [ "$i" -lt "${#QUEUE[@]}" ]; do
        if [ "$i" -ge "$INV_CLONE_CAP" ]; then TRUNC=true; break; fi
        inv_clone "${QUEUE[$i]}"
        i=$((i + 1))
    done
    jq -sc --argjson tr "$TRUNC" --arg t "$(rd_now)" \
        '{kind: "inventory", status: "ok", taken: true, items: ., truncated: $tr, read_at: $t}' "$ITEMS"
    ;;

*) usage ;;
esac
