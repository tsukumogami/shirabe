#!/usr/bin/env bash
# run-id.sh — the run identity a pull request's ownership is decided by.
#
# A branch name and an author login can't tell two runs apart: two sessions
# resuming the same PLAN slug under one account share both. So every PR a run
# records gets an entry naming the run in the PR's index session
# (`pr.<owner>.<repo>.<n>`, scripts/run-trail.sh index), and owned-pr.sh
# --run-id drops a PR whose latest index entry names another run. Nothing is
# written into the PR's text. The id is 32 lowercase hex characters from
# /dev/urandom. It says nothing about where the run happened: no path, no
# session name, no host. It is minted rather than derived from the koto
# session name because that name is the same for two runs of one PLAN
# (execute-<slug>), which is exactly the pair this has to tell apart.
#
# The id lives in the run's koto session context under `run_id`. This script
# is the one place it is minted. It is minted only where a session or a
# coordinated run is born -- execute-open.sh (a single-pr PLAN), scope-open.sh
# and deliver-open.sh right after the open, and record-coord-setup.sh when it
# seals or recovers a coordinated run's record (the opener never mints one
# for a coordinated PLAN) -- and every later caller reads it with `get`, which
# never mints: a read that fails is an error, never a new identity for the
# run. `adopt` is the one place a stored run_id is overwritten, and
# record-coord-setup.sh its one caller, on a recovering start given
# --adopt-run.
#
# Usage:
#   run-id.sh mint <session>
#       Print the session's id, minting and storing one when it has none.
#       Only the session-opening scripts and record-coord-setup.sh call this.
#   run-id.sh get <session>
#       Print the session's id. A session with no id exits 67; a failed read
#       exits 66. Never mints.
#   run-id.sh seed <session> <id>
#       Store <id> as the session's id when it has none; a session that
#       already has one keeps it. execute-open.sh uses this to carry a
#       finished session's id into the session koto replaces it with, so a
#       resumed run still owns the PR it opened.
#   run-id.sh adopt <session> <id>
#       Store <id> as the session's id whether or not it has one. Only
#       record-coord-setup.sh calls this, on a recovering start given
#       --adopt-run <id>, after every recovery check passed.
#
#   <session>  ^[A-Za-z0-9][A-Za-z0-9._-]*$
#   <id>       ^[0-9a-f]{32}$
#
# Any other verb is a usage error (64), the ones that once wrote or read a
# marker line in a PR body (stamp, restamp, carry, marker) included.
#
# Exit codes:
#   0   done (get, mint: the id is the only line on stdout)
#   64  usage error
#   66  a koto context call failed, or no id could be minted
#   67  get: the session has no run_id (it was not opened through a
#       session-opening script, or the id was lost)
#
# Requires: bash 3.2+, koto, od.
set -uo pipefail

PROG=run-id

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_ID='^[0-9a-f]{32}$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: run-id.sh mint <session> | get <session> | seed <session> <id> | adopt <session> <id>" >&2
    exit 64
}

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
    adopt)
        [ $# -eq 2 ] || usage_error "adopt takes a session and an id"
        [[ $1 =~ $RE_SESSION ]] || usage_error "[$1] is not a koto session name"
        [[ $2 =~ $RE_ID ]] || usage_error "[$2] is not a run id"
        store "$1" "$2"
        ;;
    *)
        usage_error "unknown mode [$MODE]"
        ;;
esac
exit 0
