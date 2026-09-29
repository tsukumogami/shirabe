#!/usr/bin/env bash
# teardown-inventory.sh -- what does a worker's instance hold that exists
# nowhere else?
#
# A coordinator destroys a worker's instance only once nothing in it would be
# lost. This script inventories every git repository in the instance,
# worktrees included, and prints a verdict per repository. It never destroys,
# stops or deletes anything: the destroy is the coordinator's, one instance at
# a time, after this passes.
#
# Durability is proven by content, never by ancestry. A squash merge lands a
# branch's changes as a new commit, so every finished branch looks unmerged to
# `git branch --no-merged`. For a branch whose head is on no remote branch,
# the check diffs the branch head's tree, over the paths the branch changed,
# against the squash merge commit of the merged pull request whose head was
# that branch; only when no merged pull request exists does it compare
# against the default branch's head. Comparing against the merge commit keeps a
# later change to the same paths on the default branch from reading as unique
# work.
#
# The read runs nothing a worker's clone could have configured: it never
# runs `git status` or `git fetch` in the clone, since status runs clean and
# process filters (a worker's filter can make a change vanish from it) and
# recurses into submodules with their own config, and a fetch runs the
# clone's URL rewrites, transports and credential helpers. It reads plumbing
# (ls-files, ls-tree, rev-list, cat-file, merge-base, diff-tree, reflog) with
# fsmonitor, hooks, the pager, signature verification (which runs the
# clone's gpg.program) and every transport off, and hashes working-tree files
# itself with `hash-object --no-filters`. The remote's refs come from
# `ls-remote` against the github.com URL under the coordinator's own git
# config, authenticated by the gh login (github-refs.sh, the read reconcile
# makes too), and the trees it compares against from GitHub, one read per
# commit.
#
# Per repository (all its findings are listed):
#
#   1. Staged, uncommitted, deleted and untracked changes, from the index,
#      HEAD's tree and the working tree's own bytes, so skip-worktree and
#      assume-unchanged entries hide nothing.
#   2. Stash entries.
#   3. Each local branch, local tag and a detached HEAD with a commit on none
#      of origin's live refs, and each origin tracking ref whose branch is
#      gone from origin and that this clone pushed, checked by content as
#      above. Whether it pushed is read from the ref's log; a gone ref whose
#      log exists but reads empty (expired or unreadable), or any gone ref
#      when the clone keeps no usable ref log, is an error.
#
# Submodules, clones nested in the working tree and linked worktrees inside
# the instance are inventoried as clones of their own. Anything it can't
# classify (a bare repository, a repository it can't read or whose git
# directory is outside the instance, a clone with no github.com origin, a
# lookup that fails) is an error, never `durable`. A content filter (LFS, a
# line-ending conversion) makes the working tree's bytes differ from the
# index, so such a clone reads as unique rather than durable.
#
# Files a repository's .gitignore excludes are not inventoried: they are
# build output, caches and dependencies in practice, and counting them would
# make every instance unique. Anything load-bearing a worker keeps belongs in a
# commit, a pull request or an issue, which is where the teardown's two
# questions to the worker send it before this runs.
#
# Usage:
#   teardown-inventory.sh --topic <topic> [--instance <dir>]
#   teardown-inventory.sh --seal --session <s> [--instance <dir>]
#
#   --topic     the worker's dispatch topic; with --seal it is read from the
#               session's `teardown_topic` context key instead, as every other
#               step reads its inputs, and --topic is refused
#   --instance  the instance directory; found by the topic's worker session
#               in `niwa list --json` when absent
#   --seal      run as the teardown_inventory state's default action: store the verdict
#               in the context key `teardown_verdict` through the record
#               feature's seal helper and print the bare token
#               `sealed:<seq>:<sha256>`, which the state captures (the
#               verdict's word goes to stderr, for a reader). The sealed
#               verdict opens with three lines, the word, `instance <path>`
#               and `topic <topic>`, so the destroy acts on the instance that
#               was inventoried and nothing else. The state's gate checks the
#               stored verdict against the seal, so it can't be edited after
#               the fact, and the destroy directive reads it through
#               teardown-verdict.sh, which also refuses a destroy entered by a
#               directed transition (koto#251).
#
# Output: one line per repository, `durable <path> (vs <target>)` or
# `unique <path>: <why> (vs <target>)` or `error <path>: <why>`, each path
# relative to the instance and each target `merge <sha>`, `default <branch>`
# or `-`. With --seal, the verdict goes to the seal helper and stderr, and
# stdout carries only the word and the token.
#
# Exit codes: 0 every repository durable; 1 at least one unique; 2 an error,
# no instance found, or usage. With --seal it exits 0 whatever the verdict,
# since a failed default action runs no gates; 2 there means the verdict
# couldn't be sealed (or a read that may succeed next tick failed).
#
# Writes nothing in the instance (with --seal, only the sealed verdict).
# TEARDOWN_FETCH_SECS bounds each network read (ls-remote, a gh call).
# bash 3.2; needs git, jq, and gh for the trees and the pull request lookup.
set -uo pipefail

PROG=teardown-inventory
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

GH="${GH:-gh}"
FETCH_SECS="${TEARDOWN_FETCH_SECS:-6}"
# The whole scan's budget. As the teardown state's default action this has
# koto's 30 seconds, and an action killed there is a failure, not a verdict;
# a repository the budget doesn't reach is an error, never durable.
TOTAL_SECS="${TEARDOWN_TOTAL_SECS:-24}"
STARTED=$(date +%s)

usage() { printf 'usage: %s --topic <topic> [--instance <dir>] | --seal --session <s> [--instance <dir>]\n' "$PROG" >&2; exit 2; }

TOPIC=""
INSTANCE=""
SEAL=0
SESSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --topic) [ $# -ge 2 ] || usage; TOPIC="$2"; shift 2 ;;
        --instance) [ $# -ge 2 ] || usage; INSTANCE="$2"; shift 2 ;;
        --seal) SEAL=1; shift ;;
        --session) [ $# -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
        *) usage ;;
    esac
done
WORK=$(mktemp -d "${TMPDIR:-/tmp}/teardown-inventory.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT

# unfound <reason>: the inventory can't start. Outside --seal that is exit 2.
# Under --seal it is sealed as an error verdict and the action exits 0, so the
# gate runs and routes it to the human: a failed default action runs no gates
# and the state takes no evidence, so an exit 2 here would hold the run at the
# inventory for good. A read that may succeed on the next tick still exits 2.
unfound() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    [ "$SEAL" = 1 ] || exit 2
    local t=-
    dc_valid_topic "$TOPIC" && t=$TOPIC
    printf 'error\ninstance -\ntopic %s\nerror .: %s\n' "$t" "$1" >"$WORK/sealed"
    TOKEN=$(dc_seal "$SESSION" teardown_inventory "$WORK/sealed" teardown_verdict) || { printf '%s: sealing the verdict failed\n' "$PROG" >&2; exit 2; }
    printf 'error\n' >&2
    printf '%s\n' "$TOKEN"
    exit 0
}

if [ "$SEAL" = 1 ]; then
    [ -n "$SESSION" ] && [ -z "$TOPIC" ] || usage
    TOPIC=$("${KOTO:-koto}" context get "$SESSION" teardown_topic) || {
        printf '%s: cannot read teardown_topic\n' "$PROG" >&2
        exit 2
    }
    dc_valid_topic "$TOPIC" || unfound "teardown_topic is not a dispatch topic"
fi
dc_valid_topic "$TOPIC" || usage

if [ -z "$INSTANCE" ]; then
    ROOT=$(dc_workspace_root) || unfound "no workspace root found"
    FOUND=$(dc_find_session "$ROOT" "$TOPIC")
    case "$?" in
        0) INSTANCE=${FOUND#*	} ;;
        1) unfound "no instance for $TOPIC" ;;
        *) printf '%s: niwa list could not be read\n' "$PROG" >&2; exit 2 ;;
    esac
fi
INSTANCE=$(cd "$INSTANCE" 2>/dev/null && pwd -P) || unfound "no instance directory for $TOPIC"
VERDICT="$WORK/verdict"
: >"$VERDICT"
WORST=0

note() {
    # note <level 0|1|2> <line>
    printf '%s\n' "$2" >>"$VERDICT"
    [ "$1" -gt "$WORST" ] && WORST="$1"
}

# ig <dir> <args...>: one git read in a worker's clone that runs nothing the
# clone's config names and takes no lock: no fsmonitor, no hooks, no
# transport. `git status` is never used: it refreshes the index, recurses
# into submodules with their own config and runs clean and process filters
# (a worker's filter can make a change vanish from it), and no set of flags
# reliably turns all of that off.
ig() {
    local d=$1
    shift
    # GIT_ALLOW_PROTOCOL and GIT_NO_LAZY_FETCH, unlike -c protocol.allow,
    # can't be widened by a protocol.<name>.allow in the clone's own config:
    # a partial clone's lazy fetch of a missing object is a transport too.
    # log.showSignature makes reflog show (and log) verify a signed commit by
    # running the clone's gpg.program; --no-pager keeps its core.pager out.
    GIT_ALLOW_PROTOCOL=none GIT_NO_LAZY_FETCH=1 \
        git --no-pager --no-optional-locks -c core.fsmonitor= -c core.hooksPath=/dev/null \
        -c protocol.allow=never -c log.showSignature=false -C "$d" "$@"
}

# github_repo <url>: owner/repo for a github.com remote URL, or nothing.
github_repo() {
    local r
    case "$1" in
        https://github.com/*) r=${1#https://github.com/} ;;
        git@github.com:*) r=${1#git@github.com:} ;;
        ssh://git@github.com/*) r=${1#ssh://git@github.com/} ;;
        *) return 1 ;;
    esac
    r=${r%.git}
    printf '%s' "$r" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || return 1
    case "/$r/" in */./* | */../*) return 1 ;; esac
    printf '%s' "$r"
}

# tree_map <owner/repo> <sha> <out>: the commit's tree as a JSON object
# {truncated, blobs: {path: blob sha}}, from one API read. The tree is read
# from GitHub, never from the worker's clone, which may not have the commit.
tree_map() {
    dc_with_deadline "$FETCH_SECS" "$GH" api "repos/$1/git/trees/$2?recursive=1" >"$3.raw" 2>"$WORK/gh.err" || return 1
    jq -c '{truncated: (.truncated // false), blobs: ([.tree[] | select(.type == "blob") | {key: .path, value: .sha}] | from_entries)}' \
        "$3.raw" >"$3" 2>"$WORK/gh.err" && jq -e '.blobs | type == "object"' "$3" >/dev/null 2>"$WORK/gh.err"
}

# QUEUE: every clone to inventory, by physical path, once.
QUEUE=()
# SEEN_COMMON: the git directories whose shared refs are already read.
SEEN_COMMON=()
queue() {
    local r q
    r=$(cd -P "$1" 2>/dev/null && pwd -P) || return 0
    case "$r/" in "$INSTANCE"/*) ;; *) return 1 ;; esac
    for q in ${QUEUE[@]+"${QUEUE[@]}"}; do [ "$q" = "$r" ] && return 0; done
    QUEUE+=("$r")
}

# files_changed <dir>: write to $WORK/why the clone's files hold something no commit
# does, or nothing. Staged, working-tree, deleted and untracked changes, read
# from the index, HEAD's tree and the working tree's own bytes, so
# skip-worktree and assume-unchanged entries and a clean filter hide nothing.
# Returns 1 when a read fails. Submodules and nested clones join the queue.
files_changed() {
    local d=$1 meta path tag mode rest n
    ig "$d" ls-files -z -s -v >"$WORK/idx0" || return 1
    : >"$WORK/why"
    [ -z "$(tr -cd '\n' <"$WORK/idx0")" ] || { printf 'a tracked path holds a newline; ' >"$WORK/why"; return 0; }
    tr '\0' '\n' <"$WORK/idx0" >"$WORK/idx"
    if ig "$d" rev-parse --verify --quiet HEAD >/dev/null; then
        ig "$d" ls-tree -r -z --full-tree HEAD >"$WORK/head0" || return 1
        tr '\0' '\n' <"$WORK/head0" >"$WORK/head"
    else
        : >"$WORK/head"
    fi
    : >"$WORK/present"; : >"$WORK/links"; n=0
    local why=""
    while IFS='	' read -r meta path; do
        [ -n "$path" ] || continue
        tag=${meta%% *}; rest=${meta#* }; mode=${rest%% *}
        if [ "$mode" = 160000 ]; then
            # A submodule: inventoried as a clone of its own, never through
            # the superproject's git.
            if [ -e "$d/$path/.git" ]; then
                queue "$d/$path" || why="${why}submodule $path is outside the instance; "
            fi
            continue
        fi
        if [ -L "$d/$path" ]; then printf '%s\t%s\n' "$path" "$(readlink "$d/$path")" >>"$WORK/links"; continue; fi
        if [ -f "$d/$path" ]; then printf '%s\n' "$path" >>"$WORK/present"; continue; fi
        # Missing: a skip-worktree entry is meant to be absent; anything else
        # was deleted in the working tree.
        [ "$tag" = S ] || n=$((n + 1))
    done <"$WORK/idx"
    [ "$n" -gt 0 ] && why="${why}tracked files deleted; "
    : >"$WORK/wt"
    if [ -s "$WORK/present" ]; then
        ig "$d" hash-object --no-filters --stdin-paths <"$WORK/present" >"$WORK/wt.h" || return 1
        [ "$(wc -l <"$WORK/present")" -eq "$(wc -l <"$WORK/wt.h")" ] || return 1
        awk 'NR == FNR { p[FNR] = $0; next } { print p[FNR] "\t" $0 }' "$WORK/present" "$WORK/wt.h" >"$WORK/wt"
    fi
    # A symlink's content is its target.
    while IFS='	' read -r path rest; do
        [ -n "$path" ] || continue
        printf '%s\t%s\n' "$path" "$(printf '%s' "$rest" | ig "$d" hash-object --stdin)" >>"$WORK/wt"
    done <"$WORK/links"
    local cmp
    cmp=$(jq -rn --rawfile idx "$WORK/idx" --rawfile head "$WORK/head" --rawfile wt "$WORK/wt" '
        def lines($s): $s | split("\n") | map(select(length > 0));
        def metapath: split("\t") | {meta: (.[0] | split(" ")), path: (.[1:] | join("\t"))};
        def pathhash: split("\t") | {key: (.[:-1] | join("\t")), value: .[-1]};
        [lines($idx)[] | metapath | select(.meta[1] != "160000") | {key: .path, value: .meta[2]}] | from_entries as $index
        | [lines($head)[] | metapath | select(.meta[1] != "commit") | {key: .path, value: .meta[2]}] | from_entries as $h
        | [lines($wt)[] | pathhash] | from_entries as $work
        | [ ($index | to_entries[] | select(($h[.key] // "") != .value) | "staged"),
            ($h | keys[] as $k | select(($index | has($k)) | not) | "staged"),
            ($work | to_entries[] | select(($index[.key] // "") != .value) | "modified") ]
        | unique | join(" ")') || return 1
    case "$cmp" in *staged*) why="${why}staged changes; " ;; esac
    case "$cmp" in *modified*) why="${why}uncommitted changes; " ;; esac
    ig "$d" ls-files -z --others --exclude-standard >"$WORK/oth0" || return 1
    tr '\0' '\n' <"$WORK/oth0" >"$WORK/oth"
    n=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
            */) if [ -e "$d/$path.git" ]; then
                    queue "$d/$path" || why="${why}nested clone $path is outside the instance; "
                    continue
                fi ;;
        esac
        n=$((n + 1))
    done <"$WORK/oth"
    [ "$n" -gt 0 ] && why="${why}untracked files; "
    printf '%s' "$why" >"$WORK/why"
}

# check_repo <dir> <rel>: one verdict line for one clone.
check_repo() {
    local d="$1" rel="$2" loc common top url repo live default dsha
    if [ -L "$d/.git" ]; then note 2 "error $rel: its .git is a symlink, not read"; return; fi
    loc=$(ig "$d" rev-parse --path-format=absolute --git-common-dir --show-toplevel) || {
        note 2 "error $rel: not a readable git repository"; return; }
    common=$(printf '%s\n' "$loc" | sed -n 1p); top=$(printf '%s\n' "$loc" | sed -n 2p)
    common=$(cd -P "$common" 2>/dev/null && pwd -P) || common=/
    top=$(cd -P "$top" 2>/dev/null && pwd -P) || top=/
    case "$common/" in "$INSTANCE"/*) ;; *) note 2 "error $rel: its git directory is outside the instance, not read"; return ;; esac
    [ "$top" = "$d" ] || { note 2 "error $rel: its working tree is set elsewhere, not read"; return; }

    url=$(ig "$d" config --get remote.origin.url) || url=""
    repo=$(github_repo "$url") || { note 2 "error $rel: no github.com origin to compare against"; return; }
    # The remote's refs, read by github-refs.sh with the coordinator's own git
    # config rather than the clone's, so nothing the worker configured (a URL
    # rewrite, a transport, a credential helper) runs, and authenticated by
    # the gh login, so a private repository reads too. https reads GitHub;
    # file lets a URL the coordinator's own config rewrites point at a local
    # repository, and runs nothing.
    live=$(dc_with_deadline "$FETCH_SECS" "$HERE/github-refs.sh" --gh "$GH" "$repo" 2>"$WORK/ls.err")
    case $? in
        0) ;;
        124) note 2 "error $rel: origin's refs could not be read: the read timed out after ${FETCH_SECS}s"; return ;;
        *) note 2 "error $rel: origin's refs could not be read: $(tail -n 1 "$WORK/ls.err" | tr -d '\r' | cut -c1-200)"; return ;;
    esac
    default=$(printf '%s\n' "$live" | awk '$1 == "ref:" && $3 == "HEAD" { sub("refs/heads/", "", $2); print $2; exit }')
    dsha=$(printf '%s\n' "$live" | awk -v r="refs/heads/$default" 'length($1) == 40 && $2 == r { print $1; exit }')
    [ -n "$default" ] && [ -n "$dsha" ] || { note 2 "error $rel: no default branch on origin"; return; }

    local why="" key
    : >"$WORK/targets"
    : >"$WORK/reflog-failed"
    key=$(printf '%s' "$repo" | tr / _)
    # No usable ref log: logging turned off, or no log for HEAD, which every
    # clone has from the clone itself (it's missing when the logs directory
    # can't be read).
    local nolog=""
    case "$(ig "$d" config --get core.logAllRefUpdates | tr 'A-Z' 'a-z')" in
        false | no | off | 0) nolog=1 ;;
    esac
    ig "$d" reflog exists HEAD || nolog=1
    files_changed "$d" || { note 2 "error $rel: its files could not be read"; return; }
    why=$(cat "$WORK/why")
    # A clone and its linked worktrees share one git directory, and with it
    # the branches, tags and stash: those are read at the first of them only,
    # so a finding isn't listed once per worktree. Each worktree's own files
    # and detached HEAD are read every time.
    local first=1 c
    for c in ${SEEN_COMMON[@]+"${SEEN_COMMON[@]}"}; do [ "$c" = "$common" ] && first=0; done
    [ "$first" = 1 ] && SEEN_COMMON+=("$common")
    if [ "$first" = 1 ]; then
        ig "$d" rev-parse --verify --quiet refs/stash >/dev/null && why="${why}stash entries; "
    fi

    # Tips: local branches, local tags, a detached HEAD, and origin tracking
    # refs this clone pushed for branches gone from origin. A tip is on the
    # remote when it has no commit outside the remote's live refs this clone
    # holds.
    printf '%s\n' "$live" | awk 'length($1) == 40 && $1 ~ /^[0-9a-f]+$/ { print $1 }' | sort -u >"$WORK/live"
    ig "$d" cat-file --batch-check='%(objectname) %(objecttype)' <"$WORK/live" |
        awk '$2 == "commit" { print "^" $1 }' >"$WORK/exclude"
    {
        if [ "$first" = 1 ]; then
            ig "$d" for-each-ref refs/heads refs/tags --format='%(objectname)	%(refname)' |
                awk -F'\t' '{ r = $2; sub(/^refs\/heads\//, "", r); sub(/^refs\/tags\//, "tag ", r); print $1 "\t" r }'
            # An origin tracking ref counts only when it can be the one thing
            # holding the worker's commit: its branch is gone from origin and
            # this clone pushed it (its reflog says so). Any other tracking
            # ref is someone else's branch as last fetched; counting it would
            # read every clean clone in an active repository as unique.
            ig "$d" for-each-ref refs/remotes/origin --format='%(objectname)	%(refname)	%(symref)' |
                while IFS='	' read -r tsha tref tsym; do
                    [ -z "$tsym" ] || continue
                    tb=${tref#refs/remotes/origin/}
                    printf '%s\n' "$live" | awk -v r="refs/heads/$tb" '$2 == r { f = 1 } END { exit !f }' && continue
                    # Whether this clone pushed it is read from the ref's log.
                    # With ref logging off there's no log to read, so the
                    # clone can't be judged. A ref git clone created has no log
                    # file at all, which is normal; a log file that exists but
                    # reads empty (expired, or unreadable: reflog show exits 0
                    # either way) can't be judged either.
                    if [ -n "$nolog" ]; then
                        printf '%s (ref logging is off)\n' "$tref" >>"$WORK/reflog-failed"
                        continue
                    fi
                    if ! ig "$d" reflog show --format=%gs "$tref" -- >"$WORK/reflog" 2>"$WORK/err"; then
                        printf '%s (%s)\n' "$tref" "$(tail -1 "$WORK/err")" >>"$WORK/reflog-failed"
                        continue
                    fi
                    if [ ! -s "$WORK/reflog" ] && ig "$d" reflog exists "$tref"; then
                        printf '%s (its log is empty or unreadable)\n' "$tref" >>"$WORK/reflog-failed"
                        continue
                    fi
                    grep -q '^update by push' "$WORK/reflog" || continue
                    printf '%s\tremote-tracking origin/%s\n' "$tsha" "$tb"
                done
        fi
        if ! ig "$d" symbolic-ref -q HEAD >/dev/null; then
            printf '%s\tHEAD\n' "$(ig "$d" rev-parse HEAD)"
        fi
    } >"$WORK/tips"
    if [ -s "$WORK/reflog-failed" ]; then
        note 2 "error $rel: whether it pushed $(head -1 "$WORK/reflog-failed") can't be read, so a commit only that ref holds can't be ruled out"
        return
    fi
    local sha name bname n base target label merge paths p want have differ
    [ -f "$WORK/tree-$key-$dsha" ] || tree_map "$repo" "$dsha" "$WORK/tree-$key-$dsha" || {
        note 2 "error $rel: the default branch's tree could not be read ($(tail -1 "$WORK/gh.err"))"; return; }
    while IFS='	' read -r sha name; do
        [ -n "$sha" ] || continue
        if [ $(( $(date +%s) - STARTED )) -ge "$TOTAL_SECS" ]; then
            note 2 "error $rel: not fully inventoried; the scan ran out of its ${TOTAL_SECS}s budget at $name"
            return
        fi
        { printf '%s\n' "$sha"; cat "$WORK/exclude"; } >"$WORK/revs"
        n=$(ig "$d" rev-list --stdin --count <"$WORK/revs") || { note 2 "error $rel: $name could not be compared with origin"; return; }
        [ "$n" = 0 ] && continue
        target="$dsha"
        label="default $default"
        case "$name" in
            HEAD | "tag "*) ;;
            *)
                # A remote-tracking ref's pull request is its branch's:
                # origin/<branch> after a merge deleted the branch there.
                bname=$name
                case "$name" in "remote-tracking "*) bname=${name#remote-tracking }; bname=${bname#*/} ;; esac
                if ! dc_with_deadline "$FETCH_SECS" "$GH" pr list --repo "$repo" --head "$bname" --state merged \
                    --json mergeCommit --jq '.[0].mergeCommit.oid // ""' >"$WORK/gh.out" 2>"$WORK/gh.err"; then
                    note 2 "error $rel: the merged pull request for $name could not be looked up ($(tail -1 "$WORK/gh.err"))"
                    return
                fi
                merge=$(cat "$WORK/gh.out")
                if [ -n "$merge" ]; then
                    target="$merge"
                    label="merge $merge"
                    [ -f "$WORK/tree-$key-$merge" ] || tree_map "$repo" "$merge" "$WORK/tree-$key-$merge" || {
                        note 2 "error $rel: the tree of merge commit $merge for $name could not be read ($(tail -1 "$WORK/gh.err"))"; return; }
                fi
                ;;
        esac
        printf '%s\n' "$label" >>"$WORK/targets"
        # The paths the tip changed since it left the default branch, from
        # the newest default-branch commit this clone holds; an older base
        # only adds paths, each still judged by content.
        base=""
        ig "$d" cat-file -e "$dsha^{commit}" 2>"$WORK/err" && base=$(ig "$d" merge-base "$sha" "$dsha")
        [ -n "$base" ] || base=$(ig "$d" merge-base "$sha" "refs/remotes/origin/$default" 2>"$WORK/err") || base=""
        if [ -z "$base" ]; then
            why="${why}${name} shares no history with $default here; "
            continue
        fi
        paths=$(ig "$d" diff-tree -r --no-renames --name-only -z "$base" "$sha" | tr '\0' '\n') || {
            note 2 "error $rel: cannot list what $name changed"; return; }
        differ=""
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            want=$(ig "$d" rev-parse --verify --quiet "$sha:$p") || want=absent
            have=$(jq -r --arg p "$p" '.blobs[$p] // (if .truncated then "?" else "absent" end)' "$WORK/tree-$key-$target")
            [ "$want" = "$have" ] || differ="$differ$p "
        done <<EOF
$paths
EOF
        [ -n "$differ" ] && why="${why}${name} changed ${differ% } unlike its target; "
    done <"$WORK/tips"

    # Worktrees: one inside the instance is inventoried as a clone; one
    # outside it is named, not read.
    local line w
    ig "$d" worktree list --porcelain >"$WORK/wtl" || { note 2 "error $rel: its worktrees could not be listed"; return; }
    while IFS= read -r line; do
        case "$line" in "worktree "*) ;; *) continue ;; esac
        w=${line#worktree }
        [ "$(cd -P "$w" 2>/dev/null && pwd -P)" = "$d" ] && continue
        # A submodule lists its git directory, inside the superproject's
        # .git, as its worktree; that isn't a working tree to read.
        case "$w/" in */.git/*) continue ;; esac
        queue "$w" || why="${why}worktree $w is outside the instance, not read; "
    done <"$WORK/wtl"

    local shown
    shown=$(sort -u "$WORK/targets" | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 }')
    [ -n "$shown" ] || shown=-
    if [ -n "$why" ]; then
        note 1 "unique $rel: ${why%; } (vs $shown)"
    else
        note 0 "durable $rel (vs $shown)"
    fi
}

# Every clone in the instance: a .git directory or file marks one (a linked
# worktree has a .git file). Clones this search doesn't reach, such as a
# submodule or a clone inside an ignored directory, join the queue from the
# clone that holds them.
# A directory the search can't read could hide a clone, so a failed search
# is an error, never "no repositories".
find -P "$INSTANCE" -name .git \( -type d -o -type f -o -type l \) -print -prune >"$WORK/gits0" 2>"$WORK/find.err" ||
    note 2 "error .: the instance could not be searched in full ($(tail -1 "$WORK/find.err"))"
sort "$WORK/gits0" >"$WORK/gits"
while IFS= read -r gitpath; do
    [ -n "$gitpath" ] && queue "$(dirname "$gitpath")"
done <"$WORK/gits"

# A bare repository has no .git, so the search above can't see it: look for a
# HEAD file beside objects/ and refs/ outside any .git directory. This
# inventory doesn't classify one, and an unclassified repository is never
# durable.
find -P "$INSTANCE" -name .git -prune -o -type f -name HEAD -print >"$WORK/heads"
while IFS= read -r head; do
    dir=$(dirname "$head")
    [ -d "$dir/objects" ] && [ -d "$dir/refs" ] || continue
    if [ "$(ig "$dir" rev-parse --is-bare-repository)" = true ]; then
        rel=${dir#"$INSTANCE"}
        rel=${rel#/}
        note 2 "error ${rel:-.}: a bare repository, which this inventory doesn't classify"
    fi
done <"$WORK/heads"

if [ "${#QUEUE[@]}" -eq 0 ] && [ "$WORST" -eq 0 ]; then
    note 0 "durable . (vs -): no git repositories"
fi
i=0
while [ "$i" -lt "${#QUEUE[@]}" ]; do
    dir=${QUEUE[$i]}
    i=$((i + 1))
    rel=${dir#"$INSTANCE"}
    rel=${rel#/}
    [ -n "$rel" ] || rel=.
    if [ $(( $(date +%s) - STARTED )) -ge "$TOTAL_SECS" ]; then
        note 2 "error $rel: not inventoried; the scan ran out of its ${TOTAL_SECS}s budget"
        continue
    fi
    check_repo "$dir" "$rel"
done

if [ "$SEAL" = 1 ]; then
    # As a default action this exits 0 whatever the verdict: a non-zero exit
    # is an action failure, and a failed action's gates never run. The gate
    # reads the sealed verdict and routes on it.
    case "$WORST" in
        0) WORD=durable ;;
        1) WORD=unique ;;
        *) WORD=error ;;
    esac
    { printf '%s\ninstance %s\ntopic %s\n' "$WORD" "$INSTANCE" "$TOPIC"; cat "$VERDICT"; } >"$WORK/sealed"
    TOKEN=$(dc_seal "$SESSION" teardown_inventory "$WORK/sealed" teardown_verdict) || { printf '%s: sealing the verdict failed\n' "$PROG" >&2; exit 2; }
    cat "$VERDICT" >&2
    printf '%s\n' "$WORD" >&2
    printf '%s\n' "$TOKEN"
    exit 0
fi
cat "$VERDICT"
exit "$WORST"
