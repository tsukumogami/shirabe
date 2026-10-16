#!/usr/bin/env bash
# run-id.sh — the run identity a pull request's ownership is decided by.
#
# A branch name and an author login can't tell two runs apart: two sessions
# resuming the same PLAN slug under one account share both. So every PR a run
# opens carries one hidden marker line naming the run that opened it,
#
#   <!-- shirabe-run: <id> -->
#
# and owned-pr.sh --run-id keeps only PRs whose marker names the caller's run
# (or that carry none). The id is 32 lowercase hex characters from
# /dev/urandom. It says nothing about where the run happened: no path, no
# session name, no host. It is minted rather than derived from the koto
# session name because that name is the same for two runs of one PLAN
# (execute-<slug>), which is exactly the pair this has to tell apart.
#
# The id lives in the run's koto session context under `run_id`. This script
# is the one place it is minted and the one place the marker line is written;
# owned-pr.sh is the one place it is read off a PR. It is minted only where a
# session is born -- execute-open.sh, scope-open.sh and deliver-open.sh, right
# after the open -- and every later caller reads it with `get`, which never
# mints: a read that fails is an error, never a new identity for the run.
#
# Usage:
#   run-id.sh mint <session>
#       Print the session's id, minting and storing one when it has none.
#       Only the session-opening scripts call this.
#   run-id.sh get <session>
#       Print the session's id. A session with no id exits 67; a failed read
#       exits 66. Never mints.
#   run-id.sh seed <session> <id>
#       Store <id> as the session's id when it has none; a session that
#       already has one keeps it. execute-open.sh uses this to carry a
#       finished session's id into the session koto replaces it with, so a
#       resumed run still owns the PR it opened.
#   run-id.sh stamp <id> <body-file>
#       Append the marker line for <id> to a PR body about to be created. A
#       body that already names <id> is left as it is; one naming any other
#       run is refused.
#   run-id.sh restamp <id> <body-file>
#       For owned-pr.sh --take-over: drop every marker line the body carries
#       and append the one for <id>. The rest of the body is kept.
#   run-id.sh carry <live-body-file> <new-body-file>
#       For a full-body rewrite of an existing PR: drop every marker line the
#       new body carries and append the live body's, so a rewrite can neither
#       lose the creator's marker nor forge one. A live body with no marker
#       leaves the new body unmarked.
#
#   <session>  ^[A-Za-z0-9][A-Za-z0-9._-]*$
#   <id>       ^[0-9a-f]{32}$
#
# Exit codes:
#   0   done (get, mint: the id is the only line on stdout)
#   64  usage error
#   65  stamp: the body names another run
#   66  a koto context call failed, or no id could be minted
#   67  get: the session has no run_id (it was not opened through a
#       session-opening script, or the id was lost)
#   74  a body file could not be read or written
#
# Requires: bash 3.2+, koto (get, mint, seed), od.
set -uo pipefail

PROG=run-id

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_ID='^[0-9a-f]{32}$'
# A marker line, loosely: anything that starts like one is treated as one,
# whether or not its id is well formed.
RE_MARKER_LINE='^[[:space:]]*<!--[[:space:]]*shirabe-run:'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: run-id.sh mint <session> | get <session> | seed <session> <id> | stamp <id> <body-file> | restamp <id> <body-file> | carry <live-body-file> <new-body-file>" >&2
    exit 64
}

marker_line() { printf '<!-- shirabe-run: %s -->' "$1"; }

# stored <session> -- print the session's stored id, empty when it has none.
# Only `exists` answering 1 means "none"; any other exit is an error.
stored() {
    local v rc
    koto context exists "$1" run_id </dev/null >/dev/null
    rc=$?
    case "$rc" in
        0) ;;
        1) return 0 ;;
        *) echo "$PROG: could not check run_id in session $1 (koto exit $rc)" >&2; exit 66 ;;
    esac
    v=$(koto context get "$1" run_id </dev/null) || { echo "$PROG: could not read run_id from session $1" >&2; exit 66; }
    printf '%s' "$v"
}

store() {
    printf '%s' "$2" | koto context add "$1" run_id >/dev/null \
        || { echo "$PROG: could not record run_id in session $1" >&2; exit 66; }
}

new_id() {
    local id
    id=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    [[ $id =~ $RE_ID ]] || { echo "$PROG: could not mint a run id" >&2; exit 66; }
    printf '%s' "$id"
}

# marker_lines <file> -- the file's marker lines, each trimmed of surrounding
# whitespace, which is how every mode here compares them. owned-pr.sh reads
# the same shape: a line that starts like a marker is one, and only the exact
# `<!-- shirabe-run: <id> -->` (surrounding whitespace allowed) names a run.
marker_lines() {
    grep -E "$RE_MARKER_LINE" "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# replace_markers <file> <lines> -- drop every marker line from the file, then
# append <lines> (none when empty) after a blank line.
replace_markers() {
    local tmp="$1.run-id.$$" rc
    # grep exits 1 when every line was a marker (nothing kept), 2 on a read
    # error; only the second is a failure. Trailing blank lines are dropped so
    # repeated rewrites don't grow the body.
    grep -vE "$RE_MARKER_LINE" "$1" > "$tmp.raw"
    rc=$?
    if [ "$rc" -gt 1 ]; then
        rm -f "$tmp.raw"; echo "$PROG: could not read $1" >&2; exit 74
    fi
    awk '{ lines[NR] = $0 } NF { last = NR } END { for (i = 1; i <= last; i++) print lines[i] }' \
        "$tmp.raw" > "$tmp" && rm -f "$tmp.raw" \
        || { rm -f "$tmp" "$tmp.raw"; echo "$PROG: could not write $1" >&2; exit 74; }
    if [ -n "$2" ]; then
        { printf '\n'; printf '%s\n' "$2"; } >> "$tmp"
    fi
    mv -f "$tmp" "$1" || { rm -f "$tmp"; echo "$PROG: could not write $1" >&2; exit 74; }
}

[ $# -ge 1 ] || usage_error "a mode is required"
MODE="$1"; shift

case "$MODE" in
    mint)
        [ $# -eq 1 ] || usage_error "mint takes one session"
        [[ $1 =~ $RE_SESSION ]] || usage_error "[$1] is not a koto session name"
        ID=$(stored "$1") || exit $?
        if [ -z "$ID" ]; then
            ID=$(new_id) || exit $?
            store "$1" "$ID"
        fi
        [[ $ID =~ $RE_ID ]] || { echo "$PROG: session $1 holds an unusable run_id" >&2; exit 66; }
        printf '%s\n' "$ID"
        ;;
    get)
        [ $# -eq 1 ] || usage_error "get takes one session"
        [[ $1 =~ $RE_SESSION ]] || usage_error "[$1] is not a koto session name"
        ID=$(stored "$1") || exit $?
        if [ -z "$ID" ]; then
            echo "$PROG: session $1 has no run_id; it is minted when the session is opened (execute-open.sh, scope-open.sh, deliver-open.sh)" >&2
            exit 67
        fi
        [[ $ID =~ $RE_ID ]] || { echo "$PROG: session $1 holds an unusable run_id" >&2; exit 66; }
        printf '%s\n' "$ID"
        ;;
    seed)
        [ $# -eq 2 ] || usage_error "seed takes a session and an id"
        [[ $1 =~ $RE_SESSION ]] || usage_error "[$1] is not a koto session name"
        [[ $2 =~ $RE_ID ]] || usage_error "[$2] is not a run id"
        ID=$(stored "$1") || exit $?
        [ -n "$ID" ] || store "$1" "$2"
        ;;
    stamp)
        [ $# -eq 2 ] || usage_error "stamp takes an id and a body file"
        [[ $1 =~ $RE_ID ]] || usage_error "[$1] is not a run id"
        [ -f "$2" ] || { echo "$PROG: no body file [$2]" >&2; exit 74; }
        OTHERS=$(marker_lines "$2" | grep -vxF "$(marker_line "$1")")
        if [ -n "$OTHERS" ]; then
            echo "$PROG: the body already names another run" >&2
            exit 65
        fi
        if ! marker_lines "$2" | grep -qxF "$(marker_line "$1")"; then
            { printf '\n'; marker_line "$1"; printf '\n'; } >> "$2" \
                || { echo "$PROG: could not write $2" >&2; exit 74; }
        fi
        ;;
    restamp)
        [ $# -eq 2 ] || usage_error "restamp takes an id and a body file"
        [[ $1 =~ $RE_ID ]] || usage_error "[$1] is not a run id"
        [ -f "$2" ] || { echo "$PROG: no body file [$2]" >&2; exit 74; }
        replace_markers "$2" "$(marker_line "$1")"
        ;;
    carry)
        [ $# -eq 2 ] || usage_error "carry takes the live body file and the new body file"
        [ -f "$1" ] || { echo "$PROG: no live body file [$1]" >&2; exit 74; }
        [ -f "$2" ] || { echo "$PROG: no new body file [$2]" >&2; exit 74; }
        replace_markers "$2" "$(marker_lines "$1")"
        ;;
    *)
        usage_error "unknown mode [$MODE]"
        ;;
esac
exit 0
