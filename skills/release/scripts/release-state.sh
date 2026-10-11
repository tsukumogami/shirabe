#!/usr/bin/env bash
# release-state.sh -- the session logic /release runs on the keys of
# release-<topic>.
#
# /release keeps what Phase 1 derives as keys in the koto session
# release-<topic> (references/skill-session-convention.md), because each phase
# runs in a new shell and a shell variable set in Phase 1 is gone by Phase 2.
# The three rules that compute or read that state live here, so a test can run
# them on the real path; plain open, put, get and close calls stay in the prose
# as direct skill-session.sh calls. This script reaches the session through
# scripts/skill-session.sh (found relative to this file) and `koto context`,
# and never touches the staging folder.
#
# Usage:
#   release-state.sh topic
#   release-state.sh membership <topic>
#   release-state.sh read <topic> <range|prs|unattributed|notes>
#
# Arguments (checked before any koto call):
#   <topic>   ^[a-z0-9][a-z0-9-]*$; `topic` prints one.
#
# Subcommands and their output (stdout carries machine-readable lines or the
# key's content only; messages go to stderr):
#
#   topic        prints <owner>-<name> for the repository `gh repo view --json
#             owner,name` names: lowercased, each run of characters outside
#             [a-z0-9] turned into one -, leading and trailing - removed
#             (tsukumogami-shirabe). The owner keeps two same-named
#             repositories on one machine apart. An empty result is refused
#             (refused=empty_topic). Needs gh and jq; no koto call.
#
#   membership   in the live release-<topic>, from the git repository in the
#             current directory, computes what the release contains and writes
#             it as three keys, replacing any value an earlier run left:
#               work/range          the last v* tag's range <tag>..HEAD, or
#                                   HEAD when no v* tag exists (a first release)
#               work/prs            the pull request numbers named by "(#N)"
#                                   at the end of a subject in the range, one
#                                   per line, numerically sorted, unique
#               work/unattributed   "<short hash> <subject>" for each commit in
#                                   the range whose subject names no pull
#                                   request
#             A list with nothing in it is an empty key. It also removes
#             work/notes.md when an earlier run left one, so a crashed run's
#             notes can't be published. Prints
#               range=<range>
#               prs=<count>
#               unattributed=<count>
#
#   read         prints the key's content as stored (range -> work/range,
#             prs -> work/prs, unattributed -> work/unattributed, notes ->
#             work/notes.md), or exits 1 with "Phase 1 did not run" on stderr
#             when the key is absent. An empty key prints nothing and exits 0.
#
# Exit codes:
#   0    success
#   1    a koto, gh or git operation failed; read: the key is absent
#   2    refused: topic's empty result, membership's session not live or
#        directory not a git work tree
#   4    cannot tell: koto answered something other than a session's state
#   64   usage error; no koto call was made
#   127  koto, gh, git or jq is not on PATH (whichever the subcommand needs)
#
# Environment:
#   KOTO_BIN   the koto binary to run (default: `koto` from PATH); the nested
#              skill-session.sh reads it too.
#   TMPDIR     where membership's temporary files are made (a private 0700
#              directory, removed on every exit path).
#
# Requires: bash 3.2+, jq, git, gh (topic), koto (membership, read). No eval,
# no associative arrays, no mapfile, no namerefs.

set -uo pipefail

PROG="release-state"

SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
SS="$SCRIPT_DIR/../../../scripts/skill-session.sh"
BASH_BIN="${BASH:-bash}"
KOTO="${KOTO_BIN:-koto}"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'

say() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
    printf 'error=usage\n'
    say "$1"
    say "usage: release-state.sh topic | membership <topic> | read <topic> <range|prs|unattributed|notes> (see the header of this script)"
    exit 64
}

check_topic() { [[ "$1" =~ $RE_TOPIC ]] || usage "topic must match $RE_TOPIC"; }

need_tool() { # need_tool <command> <hint>
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'failed=%s_missing\n' "$1"
        say "$1 is not on PATH; $2"
        exit 127
    fi
}

need_koto() {
    need_tool "$KOTO" "/release needs koto (install it with \`tsuku install koto\`)"
    need_tool jq "install jq"
}

# session_live <session> -- exit 0 when the session is live. Exits the script
# when skill-session.sh cannot answer.
session_live() {
    local out rc
    out=$("$BASH_BIN" "$SS" status "$1" 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        say "cannot tell the state of $1 (skill-session.sh status exited $rc)"
        exit "$rc"
    fi
    [ "$out" = "live" ]
}

# key_exists <session> <key> -- exit 0 present, 1 absent; exits the script on
# any other answer.
key_exists() {
    local rc=0
    "$KOTO" context exists "$1" "$2" >/dev/null || rc=$?
    case "$rc" in
        0) return 0 ;;
        1) return 1 ;;
        *) say "koto context exists $2 failed (exit $rc)"; exit 4 ;;
    esac
}

# --- topic ------------------------------------------------------------------------------

cmd_topic() {
    local json owner name joined topic
    [ "$#" -eq 0 ] || usage "topic takes no arguments"
    need_tool gh "/release reads the repository's owner and name with gh"
    need_tool jq "install jq"
    json=$(gh repo view --json owner,name) || { say "gh repo view failed"; exit 1; }
    owner=$(printf '%s' "$json" | jq -r '(.owner | if type == "object" then (.login // "") else (. // "") end)') || { say "gh repo view answered something that is not the repository's owner and name"; exit 1; }
    name=$(printf '%s' "$json" | jq -r '(.name // "")') || { say "gh repo view answered something that is not the repository's owner and name"; exit 1; }
    joined="${owner}-${name}"
    topic=$(printf '%s' "$joined" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
    if [ -z "$owner" ] || [ -z "$name" ] || [ -z "$topic" ]; then
        printf 'refused=empty_topic\n'
        say "gh repo view named no owner or no name; there is no topic to key the session on"
        exit 2
    fi
    printf '%s\n' "$topic"
}

# --- membership -------------------------------------------------------------------------

TMPD=""
cleanup() { [ -n "$TMPD" ] && rm -rf "$TMPD"; return 0; }

# put_file <session> <key> <file> -- store the file's bytes under the key,
# replacing a value an earlier run left; exits the script on failure.
put_file() {
    if ! "$KOTO" context add "$1" "$2" --from-file "$3" >/dev/null; then
        say "koto context add $2 failed"
        printf 'failed=%s\n' "$2"
        exit 1
    fi
}

cmd_membership() {
    local topic s last_tag range count_prs count_un
    [ "$#" -eq 1 ] || usage "membership takes <topic>"
    topic="$1"
    check_topic "$topic"
    need_koto
    need_tool git "install git"
    s="release-$topic"
    if ! git rev-parse --is-inside-work-tree >/dev/null; then
        printf 'refused=not_a_repository\n'
        say "the current directory is not in a git work tree"
        exit 2
    fi
    if ! session_live "$s"; then
        printf 'refused=session_not_live\n'
        say "$s is not live; open it first with skill-session.sh open release $topic"
        exit 2
    fi

    TMPD=$(mktemp -d "${TMPDIR:-/tmp}/release-state.XXXXXX") || { say "cannot make a temporary directory"; exit 1; }
    trap cleanup EXIT

    last_tag=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo "")
    # An empty last tag is the first release. The guard is load-bearing:
    # "..HEAD" is a range git accepts, and it resolves to zero commits, so
    # without it a first release derives an empty set silently.
    if [ -n "$last_tag" ]; then
        range="$last_tag..HEAD"
    else
        range="HEAD"
    fi
    printf '%s\n' "$range" >"$TMPD/range"

    # The pull requests the release contains: GitHub's squash merge appends
    # "(#N)" to the commit subject. grep exits 1 when nothing matches, which is
    # a legal outcome (an empty list), so it is guarded.
    git log --format='%s' "$range" >"$TMPD/subjects" || { say "git log $range failed"; exit 1; }
    { grep -oE '\(#[0-9]+\)$' "$TMPD/subjects" || true; } | tr -d '(#)' | sort -n -u >"$TMPD/prs"

    # Commits in the range that name no pull request: the release chore
    # commits, and anything pushed straight to the base branch.
    git log --format='%h %s' "$range" >"$TMPD/log" || { say "git log $range failed"; exit 1; }
    { grep -vE '\(#[0-9]+\)$' "$TMPD/log" || true; } >"$TMPD/unattributed"

    # Nothing an earlier run wrote survives into this one: its notes, and its
    # membership keys, which go before any new one is written so a write that
    # fails part-way leaves keys missing (read stops on them) rather than a mix
    # of this run's and the last one's.
    for k in work/notes.md work/range work/prs work/unattributed; do
        key_exists "$s" "$k" || continue
        if ! "$KOTO" context remove "$s" "$k" >/dev/null; then
            printf 'failed=%s\n' "$k"
            say "could not remove $k"
            exit 1
        fi
    done

    put_file "$s" work/range "$TMPD/range"
    put_file "$s" work/prs "$TMPD/prs"
    put_file "$s" work/unattributed "$TMPD/unattributed"

    count_prs=$(grep -c . "$TMPD/prs" || true)
    count_un=$(grep -c . "$TMPD/unattributed" || true)
    printf 'range=%s\n' "$range"
    printf 'prs=%s\n' "${count_prs:-0}"
    printf 'unattributed=%s\n' "${count_un:-0}"
}

# --- read -------------------------------------------------------------------------------

cmd_read() {
    local topic which s key
    [ "$#" -eq 2 ] || usage "read takes <topic> <range|prs|unattributed|notes>"
    topic="$1"
    which="$2"
    check_topic "$topic"
    case "$which" in
        range) key="work/range" ;;
        prs) key="work/prs" ;;
        unattributed) key="work/unattributed" ;;
        notes) key="work/notes.md" ;;
        *) usage "read's key must be range, prs, unattributed or notes" ;;
    esac
    need_koto
    s="release-$topic"
    if ! key_exists "$s" "$key"; then
        say "Phase 1 did not run: $key is absent from $s (run Phase 1 first; its membership step writes it)"
        exit 1
    fi
    "$KOTO" context get "$s" "$key" || { say "cannot read $key"; exit 1; }
}

# --- dispatch ---------------------------------------------------------------------------

[ "$#" -ge 1 ] || usage "a subcommand is required"
sub="$1"
shift
case "$sub" in
    topic) cmd_topic "$@" ;;
    membership) cmd_membership "$@" ;;
    read) cmd_read "$@" ;;
    *) usage "unknown subcommand: $sub" ;;
esac
