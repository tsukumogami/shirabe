#!/usr/bin/env bash
# handoff-brief.sh -- a session's compaction note and the ledger entry the
# compaction hooks read.
#
# Usage:
#   scripts/handoff-brief.sh note --reasoning <file> --skill "<name> [<args>] <SKILL.md path>"
#                                 [--skill ...] [--koto-session <name>] [--pr <url>]
#
# `note` writes the reasoning file as key compaction/note.md in the session's
# koto session, then writes the session's ledger entry, which
# `shirabe compaction pre-compact` and `shirabe compaction re-anchor` read back
# by session id:
#
#   $XDG_STATE_HOME/shirabe/compaction/<session-id>
#   (or $HOME/.local/state/shirabe/compaction/<session-id>)
#
# The directory is 0700 and the entry 0600. The entry is replaced whole through
# a temporary file in the same directory, and an entry or directory that is a
# link is refused. It holds one `key: value` line each for the koto session,
# the note key, the branch and the pull request, then one `skill:` line per
# --skill, in the order given (outermost first).
#
#   --reasoning     the note's text, read from a file
#   --skill         a skill the session is running: its name, the arguments it
#                   was invoked with, and the absolute path of its SKILL.md,
#                   separated by single spaces; the path must exist
#   --koto-session  the koto session the note goes to; defaults to $KOTO_SESSION
#   --pr            the pull request URL, when there is one; otherwise `none`
#
# The session id comes from CLAUDE_CODE_SESSION_ID (then CLAUDE_SESSION_ID).
#
# Exit codes:
#   0  the note and the entry were written
#   1  a write failed (koto, or the ledger)
#   2  a usage error or a refused value; nothing was written
#
# bash 3.2.

set -uo pipefail

PROG=handoff-brief.sh
NOTE_KEY=compaction/note.md
MAX_SKILLS=8

usage() {
    sed -n '4,7p' "$0" | sed 's/^# \{0,1\}//' >&2
}

refuse() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 2
}

fail() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 1
}

# The grammars the hooks re-check on read (crates/shirabe/src/compaction.rs).
valid_sid() {
    [[ "$1" =~ ^[A-Za-z0-9-]{1,64}$ ]]
}
valid_koto_session() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]
}
valid_branch() {
    [[ "$1" =~ ^[A-Za-z0-9._/-]{1,200}$ ]] || return 1
    case "$1" in *..*|-*|/*) return 1 ;; esac
    return 0
}
valid_pr() {
    [[ "$1" =~ ^https://github\.com/[A-Za-z0-9][A-Za-z0-9._-]{0,99}/[A-Za-z0-9._-]{1,100}/pull/[0-9]{1,10}$ ]]
}
valid_skill_name() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,63}(:[a-z0-9][a-z0-9-]{0,63})?$ ]]
}
valid_skill_arg() {
    [[ "$1" =~ ^[A-Za-z0-9._/=:@+,-]{1,200}$ ]]
}
valid_skill_path() {
    [[ "$1" =~ ^/[A-Za-z0-9._/+@-]{1,500}/SKILL\.md$ ]] || return 1
    case "/$1/" in */../*) return 1 ;; esac
    return 0
}

# check_skill <line> -- one --skill value: name, args, path, single spaces.
check_skill() {
    local line="$1" name path tok i
    case "$line" in
        *"  "*|" "*|*" ") refuse "--skill [$line]: separate name, arguments and path with single spaces" ;;
    esac
    # Word-split on spaces only, with globbing off.
    local IFS=' '
    set -f
    # shellcheck disable=SC2086
    set -- $line
    set +f
    [ "$#" -ge 2 ] || refuse "--skill [$line]: needs at least a name and a SKILL.md path"
    name="$1"
    eval "path=\${$#}"
    valid_skill_name "$name" || refuse "--skill [$line]: [$name] is not a skill name"
    valid_skill_path "$path" || refuse "--skill [$line]: [$path] is not an absolute path to a SKILL.md"
    [ -f "$path" ] || refuse "--skill [$line]: [$path] does not exist"
    i=0
    for tok in "$@"; do
        i=$((i + 1))
        [ "$i" -eq 1 ] && continue
        [ "$i" -eq "$#" ] && continue
        valid_skill_arg "$tok" || refuse "--skill [$line]: argument [$tok] is outside the allowed characters"
    done
    return 0
}

cmd_note() {
    local reasoning="" koto_session="${KOTO_SESSION:-}" pr="" sid branch dir entry tmp s
    local skills=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --reasoning)    [ "$#" -ge 2 ] || refuse "--reasoning needs a file"; reasoning="$2"; shift ;;
            --skill)        [ "$#" -ge 2 ] || refuse "--skill needs a value"; skills+=("$2"); shift ;;
            --koto-session) [ "$#" -ge 2 ] || refuse "--koto-session needs a name"; koto_session="$2"; shift ;;
            --pr)           [ "$#" -ge 2 ] || refuse "--pr needs a URL"; pr="$2"; shift ;;
            -h|--help)      usage; exit 0 ;;
            *) refuse "unknown argument: $1" ;;
        esac
        shift
    done

    [ -n "$reasoning" ] || refuse "--reasoning is required"
    [ -f "$reasoning" ] && [ -r "$reasoning" ] || refuse "--reasoning [$reasoning] is not a readable file"
    [ -n "$koto_session" ] || refuse "no koto session: pass --koto-session or set KOTO_SESSION"
    valid_koto_session "$koto_session" || refuse "[$koto_session] is not a koto session name"
    if [ -n "$pr" ]; then
        valid_pr "$pr" || refuse "--pr [$pr] is not a GitHub pull request URL"
    else
        pr=none
    fi
    [ "${#skills[@]}" -le "$MAX_SKILLS" ] || refuse "at most $MAX_SKILLS --skill values"
    if [ "${#skills[@]}" -gt 0 ]; then
        for s in "${skills[@]}"; do
            check_skill "$s"
        done
    fi

    sid="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
    [ -n "$sid" ] || refuse "no session id: CLAUDE_CODE_SESSION_ID is not set"
    valid_sid "$sid" || refuse "the session id is outside its grammar"

    branch=$(git -c core.fsmonitor=false symbolic-ref --quiet --short HEAD 2>/dev/null) \
        || refuse "HEAD is not on a named branch"
    valid_branch "$branch" || refuse "branch [$branch] is outside its grammar"

    if [ -n "${XDG_STATE_HOME:-}" ]; then
        dir="$XDG_STATE_HOME/shirabe/compaction"
    else
        [ -n "${HOME:-}" ] || refuse "neither XDG_STATE_HOME nor HOME is set"
        dir="$HOME/.local/state/shirabe/compaction"
    fi
    [ -L "$dir" ] && refuse "the ledger directory [$dir] is a link"
    (umask 077 && mkdir -p "$dir") || fail "cannot create the ledger directory [$dir]"
    [ -d "$dir" ] && [ ! -L "$dir" ] || fail "the ledger directory [$dir] is not a directory"
    chmod 700 "$dir" || fail "cannot set the ledger directory's mode"
    entry="$dir/$sid"
    [ -L "$entry" ] && refuse "the ledger entry [$entry] is a link"

    # The note first: an entry naming a note that was never written would send
    # a compacted session to read nothing.
    koto context add "$koto_session" "$NOTE_KEY" --from-file "$reasoning" >/dev/null \
        || fail "koto context add $koto_session $NOTE_KEY failed"

    tmp=$(umask 077 && mktemp "$dir/.entry.XXXXXX") || fail "cannot create a temporary ledger file"
    {
        printf 'koto_session: %s\n' "$koto_session"
        printf 'note_key: %s\n' "$NOTE_KEY"
        printf 'branch: %s\n' "$branch"
        printf 'pr: %s\n' "$pr"
        if [ "${#skills[@]}" -gt 0 ]; then
            for s in "${skills[@]}"; do
                printf 'skill: %s\n' "$s"
            done
        fi
    } >"$tmp" || { rm -f "$tmp"; fail "cannot write the ledger entry"; }
    chmod 600 "$tmp" || { rm -f "$tmp"; fail "cannot set the ledger entry's mode"; }
    mv -f "$tmp" "$entry" || { rm -f "$tmp"; fail "cannot put the ledger entry in place"; }

    printf 'note=%s/%s\n' "$koto_session" "$NOTE_KEY"
    printf 'ledger=%s\n' "$entry"
    exit 0
}

[ "$#" -ge 1 ] || { usage; exit 2; }
case "$1" in
    note) shift; cmd_note "$@" ;;
    -h|--help) usage; exit 0 ;;
    *) refuse "unknown subcommand: $1 (only 'note' exists yet)" ;;
esac
