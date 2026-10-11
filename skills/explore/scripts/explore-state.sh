#!/usr/bin/env bash
# explore-state.sh -- the decisions /explore makes from its session's keys.
#
# /explore keeps its working state as keys in the koto session explore-<topic>
# (references/skill-session-convention.md). The three rules that branch on that
# state or sequence several session operations live here, so a test can run
# them on the real path; plain open, get, put and close calls stay in the
# prose as direct skill-session.sh calls. This script reaches the session
# through scripts/skill-session.sh (found relative to this file) and `koto
# context`, and never touches the staging folder.
#
# Usage:
#   explore-state.sh resume-phase <topic>
#   explore-state.sh ingest-leads <topic> <round> <dir>
#   explore-state.sh finish-handoff <topic>
#
# Arguments (all checked before any koto call):
#   <topic>   ^[a-z0-9][a-z0-9-]*$.
#   <round>   a positive integer, no leading zero.
#   <dir>     the scratch directory `skill-session.sh scratch` printed for the
#             round: a real directory (not a symlink), owned by the caller,
#             mode 0700, outside the git work tree, and neither / nor $HOME.
#
# Subcommands and their output (stdout carries machine-readable lines only;
# messages go to stderr):
#
#   resume-phase   prints the phase /explore resumes at, from the keys of a
#             live explore-<topic>; first match wins:
#               work/crystallize.md present                          5
#               work/findings.md holds a line equal to
#                 "## Decision: Crystallize"                         4
#               work/findings.md present                             3
#               a research/r<N>_lead-*.md key, no findings           3
#               work/scope.md present                                2
#               none of these                                        none
#             An absent session and a finished one print none: a finished
#             session is never resumed (the next open replaces it). When it
#             prints none the prose's branch rows decide (on the topic branch,
#             Phase 1; otherwise Phase 0). Reads only.
#
#   ingest-leads   for a round's lead outputs in <dir>: an entry whose name is
#             not r<round>_lead-<slug>.md with a kebab-case slug is deleted
#             from <dir> and reported as
#               rejected=<name>        (name sanitised to [A-Za-z0-9._-])
#             so the ingest that follows cannot pick it up; then
#               skill-session.sh ingest explore-<topic> research <dir>
#             runs, and its added=research/<name> lines and exit code pass
#             through (<dir> is removed by that ingest). A rejected entry
#             does not change the exit code: it is reported, not lost.
#
#   finish-handoff   requires a non-blank key handoff/scope.md or
#             handoff/charter.md in the live explore-<topic>, then removes
#             every key under work/ and research/, leaving the handoff and
#             session/branch. Prints
#               handoff=<key>          (each handoff key found)
#               removed=<key>          (each key removed)
#               refused=no_handoff     (and removes nothing)
#               refused=session_not_live
#               failed=<key>           (a removal failed; the rest still run)
#
# Exit codes:
#   0    success (resume-phase: a phase or none was printed)
#   1    a koto operation failed
#   2    refused: finish-handoff without a handoff or a live session, or an
#        ingest-leads <dir> that fails the scratch checks (refused=not_scratch);
#        skill-session.sh's own refusals pass through with their codes
#   4    cannot tell: koto answered something other than a session's state
#   64   usage error; no koto call was made
#   127  koto or jq is not on PATH (skill-session.sh's code passes through)
#
# Environment:
#   KOTO_BIN   the koto binary to run (default: `koto` from PATH); the nested
#              skill-session.sh reads it too.
#
# Requires: bash 3.2+, jq, git. No eval, no associative arrays, no mapfile, no
# namerefs.

set -uo pipefail

PROG="explore-state"

SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
SS="$SCRIPT_DIR/../../../scripts/skill-session.sh"
BASH_BIN="${BASH:-bash}"
KOTO="${KOTO_BIN:-koto}"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_ROUND='^[1-9][0-9]*$'
RE_KEY='^(work|research)/[A-Za-z0-9][A-Za-z0-9._/-]*$'

say() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
    printf 'error=usage\n'
    say "$1"
    say "usage: explore-state.sh resume-phase <topic> | ingest-leads <topic> <round> <dir> | finish-handoff <topic> (see the header of this script)"
    exit 64
}

check_topic() { [[ "$1" =~ $RE_TOPIC ]] || usage "topic must match $RE_TOPIC"; }

need_tools() {
    if ! command -v "$KOTO" >/dev/null 2>&1; then
        printf 'failed=koto_missing\n'
        say "koto is not on PATH; /explore needs koto (install it with \`tsuku install koto\`)"
        exit 127
    fi
    if ! command -v jq >/dev/null 2>&1; then
        printf 'failed=jq_missing\n'
        say "jq is not on PATH"
        exit 127
    fi
}

# session_live <session> -- exit 0 when the session is live. Exits the script
# when skill-session.sh cannot answer (koto missing, an unreadable state).
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

# list_keys <session> <prefix> -- print the keys under the prefix, one per
# line; exits the script when the listing fails.
list_keys() {
    local json
    json=$("$KOTO" context list "$1" --prefix "$2" 2>/dev/null) || { say "koto context list $2 failed"; exit 1; }
    printf '%s' "$json" | jq -r '.[]' 2>/dev/null || { say "koto context list answered something that is not a key list"; exit 1; }
}

# --- resume-phase -----------------------------------------------------------------------

cmd_resume_phase() {
    local topic s findings leads
    [ "$#" -eq 1 ] || usage "resume-phase takes <topic>"
    topic="$1"
    check_topic "$topic"
    need_tools
    s="explore-$topic"
    if ! session_live "$s"; then
        printf 'none\n'
        return 0
    fi
    if key_exists "$s" work/crystallize.md; then
        printf '5\n'
        return 0
    fi
    if key_exists "$s" work/findings.md; then
        findings=$("$KOTO" context get "$s" work/findings.md 2>/dev/null) || { say "cannot read work/findings.md"; exit 1; }
        if printf '%s\n' "$findings" | grep -qxF '## Decision: Crystallize'; then
            printf '4\n'
        else
            printf '3\n'
        fi
        return 0
    fi
    leads=$(list_keys "$s" research/) || exit 1
    if printf '%s\n' "$leads" | grep -Eq '^research/r[0-9]+_lead-.*\.md$'; then
        printf '3\n'
        return 0
    fi
    if key_exists "$s" work/scope.md; then
        printf '2\n'
        return 0
    fi
    printf 'none\n'
    return 0
}

# --- ingest-leads -----------------------------------------------------------------------

# lead_dir_ok <dir> -- the checks that make deleting inside <dir> safe: the
# same ones skill-session.sh applies before it ingests.
lead_dir_ok() {
    local d="$1" mode phys home top
    if [ -L "$d" ] || [ ! -d "$d" ] || [ ! -O "$d" ]; then
        say "$d is not a private directory of ours (a symlink is refused)"
        return 1
    fi
    mode=$(stat -c '%a' -- "$d" 2>/dev/null || stat -f '%Lp' -- "$d" 2>/dev/null) || mode=""
    case "$mode" in
        700|0700) ;;
        *) say "$d has mode ${mode:-unknown}; a scratch directory is 0700"; return 1 ;;
    esac
    phys=$(cd -P -- "$d" 2>/dev/null && pwd -P) || return 1
    home=""
    [ -n "${HOME:-}" ] && home=$(cd -P -- "$HOME" 2>/dev/null && pwd -P)
    if [ "$phys" = "/" ] || { [ -n "$home" ] && [ "$phys" = "$home" ]; }; then
        say "$d is not a scratch directory"
        return 1
    fi
    top=$(git rev-parse --show-toplevel 2>/dev/null) && top=$(cd -P -- "$top" 2>/dev/null && pwd -P)
    if [ -n "$top" ]; then
        case "$phys" in
            "$top"|"$top"/*) say "$d lies inside the work tree; scratch content lives outside it"; return 1 ;;
        esac
    fi
    return 0
}

cmd_ingest_leads() {
    local topic round dir f name re shown rc
    [ "$#" -eq 3 ] || usage "ingest-leads takes <topic> <round> <dir>"
    topic="$1"; round="$2"; dir="$3"
    check_topic "$topic"
    [[ "$round" =~ $RE_ROUND ]] || usage "round must be a positive integer"
    [ -n "$dir" ] || usage "dir must not be empty"
    need_tools
    if ! lead_dir_ok "$dir"; then
        printf 'refused=not_scratch\n'
        exit 2
    fi
    re="^r${round}_lead-[a-z0-9]+(-[a-z0-9]+)*\\.md\$"
    for f in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
        [ -e "$f" ] || [ -L "$f" ] || continue
        name="${f##*/}"
        if [ ! -L "$f" ] && [ -f "$f" ] && [[ "$name" =~ $re ]]; then
            continue
        fi
        shown=$(printf '%s' "$name" | LC_ALL=C tr -c 'A-Za-z0-9._-' '?')
        printf 'rejected=%s\n' "$shown"
        say "rejected $shown: a lead file is r${round}_lead-<slug>.md, a regular file, with a kebab-case slug"
        rm -rf -- "$f"
    done
    rc=0
    "$BASH_BIN" "$SS" ingest "explore-$topic" research "$dir" || rc=$?
    exit "$rc"
}

# --- finish-handoff ---------------------------------------------------------------------

cmd_finish_handoff() {
    local topic s k found=0 failed=0 content keys
    [ "$#" -eq 1 ] || usage "finish-handoff takes <topic>"
    topic="$1"
    check_topic "$topic"
    need_tools
    s="explore-$topic"
    if ! session_live "$s"; then
        printf 'refused=session_not_live\n'
        say "$s is not live; no handoff was finished"
        exit 2
    fi
    for k in handoff/scope.md handoff/charter.md; do
        key_exists "$s" "$k" || continue
        content=$("$KOTO" context get "$s" "$k" 2>/dev/null) || { say "cannot read $k"; exit 1; }
        if printf '%s' "$content" | grep -q '[^[:space:]]'; then
            printf 'handoff=%s\n' "$k"
            found=1
        fi
    done
    if [ "$found" -eq 0 ]; then
        printf 'refused=no_handoff\n'
        say "$s holds no non-empty handoff/scope.md or handoff/charter.md; nothing was removed"
        exit 2
    fi
    for k in work/ research/; do
        keys=$(list_keys "$s" "$k") || exit 1
        while IFS= read -r key; do
            [ -n "$key" ] || continue
            if ! [[ "$key" =~ $RE_KEY ]]; then
                say "skipped a key that is not under work/ or research/ with a plain name"
                failed=1
                continue
            fi
            case "$key" in
                *..*) say "skipped a key containing '..'"; failed=1; continue ;;
            esac
            if "$KOTO" context remove "$s" "$key" >/dev/null 2>&1; then
                printf 'removed=%s\n' "$key"
            else
                printf 'failed=%s\n' "$key"
                failed=1
            fi
        done <<EOF
$keys
EOF
    done
    [ "$failed" -eq 0 ] || exit 1
    exit 0
}

# --- dispatch ---------------------------------------------------------------------------

[ "$#" -ge 1 ] || usage "a subcommand is required"
sub="$1"
shift
case "$sub" in
    resume-phase) cmd_resume_phase "$@" ;;
    ingest-leads) cmd_ingest_leads "$@" ;;
    finish-handoff) cmd_finish_handoff "$@" ;;
    *) usage "unknown subcommand: $sub" ;;
esac
