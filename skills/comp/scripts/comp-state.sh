#!/usr/bin/env bash
# comp-state.sh -- the decision /comp makes from its session's keys.
#
# /comp keeps its working state as keys in the koto session comp-<topic>
# (references/skill-session-convention.md): the scope as work/scope.md and each
# juror's verdict as research/phase4_<role>.md. The one rule that branches on
# that state, whether Phase 4's jury has already run, lives here so a test can
# run it on the real path; plain open, put, ingest, get and close calls stay in
# the prose as direct skill-session.sh calls. This script reaches the session
# through scripts/skill-session.sh (found relative to this file) and `koto
# context`, and never touches the staging folder.
#
# Usage:
#   comp-state.sh jury-resume <topic>
#
# Arguments (checked before any koto call):
#   <topic>   ^[a-z0-9][a-z0-9-]*$.
#
# Subcommands and their output (stdout carries machine-readable lines only;
# messages go to stderr):
#
#   jury-resume   counts the three verdict keys of a live comp-<topic>:
#               research/phase4_competitive-framing.md
#               research/phase4_content-quality.md
#               research/phase4_structural-format.md
#             All three present: prints
#               aggregate
#             and changes nothing. Otherwise it removes each of the three that
#             is present, so a re-run never mixes old and new verdicts, and
#             prints
#               fresh
#             (each removal is noted on stderr). A key that cannot be removed
#             prints failed=<key>, the rest are still tried, and the script
#             exits 1 without printing fresh.
#             A session that is not live prints refused=session_not_live and
#             exits 2.
#
# Exit codes:
#   0    aggregate or fresh was printed
#   1    a koto operation failed
#   2    refused: the session is not live
#   4    cannot tell: koto answered something other than a session's state
#   64   usage error; no koto call was made
#   127  koto or jq is not on PATH
#
# Environment:
#   KOTO_BIN   the koto binary to run (default: `koto` from PATH); the nested
#              skill-session.sh reads it too.
#
# Requires: bash 3.2+, jq. No eval, no associative arrays, no mapfile, no
# namerefs.

set -uo pipefail

PROG="comp-state"

SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
SS="$SCRIPT_DIR/../../../scripts/skill-session.sh"
BASH_BIN="${BASH:-bash}"
KOTO="${KOTO_BIN:-koto}"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
ROLES="competitive-framing content-quality structural-format"

say() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
    printf 'error=usage\n'
    say "$1"
    say "usage: comp-state.sh jury-resume <topic> (see the header of this script)"
    exit 64
}

need_tools() {
    if ! command -v "$KOTO" >/dev/null 2>&1; then
        printf 'failed=koto_missing\n'
        say "koto is not on PATH; /comp needs koto (install it with \`tsuku install koto\`)"
        exit 127
    fi
    if ! command -v jq >/dev/null 2>&1; then
        printf 'failed=jq_missing\n'
        say "jq is not on PATH"
        exit 127
    fi
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
    "$KOTO" context exists "$1" "$2" >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0) return 0 ;;
        1) return 1 ;;
        *) say "koto context exists $2 failed (exit $rc)"; exit 4 ;;
    esac
}

# --- jury-resume ------------------------------------------------------------------------

cmd_jury_resume() {
    local topic s role key present="" count=0 failed=0
    [ "$#" -eq 1 ] || usage "jury-resume takes <topic>"
    topic="$1"
    [[ "$topic" =~ $RE_TOPIC ]] || usage "topic must match $RE_TOPIC"
    need_tools
    s="comp-$topic"
    if ! session_live "$s"; then
        printf 'refused=session_not_live\n'
        say "$s is not live; the jury cannot be resumed"
        exit 2
    fi
    for role in $ROLES; do
        key="research/phase4_${role}.md"
        if key_exists "$s" "$key"; then
            count=$((count + 1))
            present="$present $key"
        fi
    done
    if [ "$count" -eq 3 ]; then
        printf 'aggregate\n'
        return 0
    fi
    for key in $present; do
        if "$KOTO" context remove "$s" "$key" >/dev/null 2>&1; then
            say "removed $key"
        else
            printf 'failed=%s\n' "$key"
            failed=1
        fi
    done
    [ "$failed" -eq 0 ] || exit 1
    printf 'fresh\n'
    return 0
}

# --- dispatch ---------------------------------------------------------------------------

[ "$#" -ge 1 ] || usage "a subcommand is required"
sub="$1"
shift
case "$sub" in
    jury-resume) cmd_jury_resume "$@" ;;
    *) usage "unknown subcommand: $sub" ;;
esac
