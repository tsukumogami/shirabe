#!/usr/bin/env bash
# check-tick-launches.sh -- no koto tick launches a worker that inherits koto's
# cloud settings.
#
# koto runs a template's gate commands and default actions inside a tick, and
# what they run inherits the tick's environment, KOTO_SESSION_* included: the
# cloud backend, its bucket and its credentials. A worker started from there,
# a `niwa dispatch` or a `claude` session, would carry them into a session that
# was never meant to have them. No shirabe path does this today; this check
# keeps it so, and lets a path that comes to need a launch through once it
# unsets KOTO_SESSION_* first.
#
# What it reads:
#
#   every `command:` in the YAML frontmatter of every koto template the plugin
#   ships (koto-templates/*.md and skills/*/koto-templates/*.md): the gates'
#   commands and the default actions' alike, one-line or block scalars;
#
#   every script those commands run, found by path: a `{{PLUGIN_ROOT}}/...`
#   path in a command, and in each script reached, every `.sh` or `.py` path
#   on a line that isn't a comment, resolved against the script's own
#   directory, the plugin root, and the `scripts/` or `skills/` part of the
#   path. Only files inside the plugin root are followed, each once.
#
# What counts as a launch, on a line that isn't a comment, once every quoted
# string holding a space is set aside (a message such as "claude agents could
# not be read" is text, not a command), except the script a shell is handed
# with -c (`bash -c 'claude -p x'`), which is read as a command. A subcommand
# that starts nothing is set aside where it occurs, so a launch beside it on
# the same line is still seen:
#
#   `niwa dispatch` (by name or by a path ending in /niwa), or a variable
#   whose name holds NIWA followed by
#   `dispatch` (`"$NIWA" dispatch`), unless what follows is `--help` or `-h`;
#   `claude` as a word or a path ending in /claude, or a variable whose name
#   holds CLAUDE, followed by an
#   argument or ending the command (`"$CLAUDE_CLI" -p ...`), unless what
#   follows is a subcommand that starts no session: `agents`, `rm`,
#   `--version`, `-v`, `--help`, `-h`;
#   in Python, `"claude"` or `"niwa", "dispatch"` as list items.
#
# A launch passes when the launch line or an earlier line of the same command
# or script unsets KOTO_SESSION_*: a line naming KOTO_SESSION_ after `unset`,
# `env ... -u`, or, in Python, `.pop`, `del` or `startswith`.
#
# Limits, stated rather than hidden. The scan reads lines, not shell scope:
# an unset anywhere above a launch in the same file clears it, even one inside
# another function or branch. A launch through a variable is seen only when
# the variable is named for the tool (NIWA, CLAUDE, or either with _BIN, _CLI,
# _CMD, _COMMAND or _EXE). A script is followed only by a path written in a
# command or script; a mode the callee takes from its arguments is not, which
# is what scripts/check-tick-launches.allow records, one call at a time.
#
# Usage:
#   check-tick-launches.sh [--root <plugin-root>] [<template>...]
#
#   --root      the plugin root (default: this script's parent directory).
#   <template>  the templates to read (default: every template the root
#               ships, as above). Scripts are still resolved against --root.
#
# Output: one line per offending launch on stdout, naming the template line of
# the command that reaches it and, for a script, the script's own line:
#   <template>:<line>: the command, its line <n>: launches <what> without unsetting KOTO_SESSION_*
#   <template>:<line> runs <script>:<n>: launches <what> without unsetting KOTO_SESSION_*
# <line> is the template line of the command's `command:` key; <n> counts the
# lines of the command itself (2 is a block scalar's second line) or of the
# script.
# and a one-line summary on stderr. A script reached from several commands is
# read once and named under the first.
#
# Exit codes:
#   0  no launch inside a tick, or every one unsets KOTO_SESSION_* first
#   1  at least one launch that doesn't
#   2  usage error, or a template or root that can't be read
#
# Requires: bash 3.2+, awk, sed, grep. No eval, no associative arrays, no
# mapfile.

set -uo pipefail

PROG=check-tick-launches
SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
ROOT="$SCRIPT_DIR/.."
TEMPLATES=""
COUNT=0

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: check-tick-launches.sh [--root <plugin-root>] [<template>...]\n' >&2
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --root)
            [ "$#" -ge 2 ] || usage "--root needs a directory"
            ROOT="$2"; shift ;;
        -*) usage "unknown option: $1" ;;
        *)
            [ -f "$1" ] && [ -r "$1" ] || usage "no readable template at $1"
            TEMPLATES="$TEMPLATES$1
"
            ;;
    esac
    shift
done
ROOT=$(cd -P -- "$ROOT" 2>/dev/null && pwd -P) || usage "the plugin root can't be read"

CHECK_STALE=0
if [ -z "$TEMPLATES" ]; then
    CHECK_STALE=1
    TEMPLATES=$( {
        find "$ROOT/koto-templates" -maxdepth 1 -type f -name '*.md' 2>/dev/null
        find "$ROOT/skills" -mindepth 3 -maxdepth 3 -path '*/koto-templates/*.md' -type f 2>/dev/null
    } | LC_ALL=C sort)
    [ -n "$TEMPLATES" ] || usage "no koto template under $ROOT"
fi
ALLOW="$ROOT/scripts/check-tick-launches.allow"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-tick-launches.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT

# The allow records: <caller><TAB><callee><TAB><reason>, paths from the root.
# A record with no reason is refused.
: >"$WORK/allow"
if [ -f "$ALLOW" ]; then
    awk -F '\t' '
        /^[[:space:]]*(#|$)/ { next }
        NF < 3 || $3 ~ /^[[:space:]]*$/ { bad = 1; print "check-tick-launches: " FILENAME ":" NR ": a record is <caller><TAB><callee><TAB><reason>" > "/dev/stderr"; next }
        { print $1 "\t" $2 }
        END { exit bad }
    ' "$ALLOW" >"$WORK/allow" || exit 2
fi

# The patterns, read by awk from the environment so no backslash in them is
# reinterpreted. Q is a single quote.
Q="'"
TAB=$(printf '\t')
export CTL_UNSET='(unset|env[[:space:]].*-u|[.]pop|del[[:space:]]|startswith)[^#]*KOTO_SESSION_'
TOOLVAR='(_(BIN|CLI|CMD|COMMAND|EXE))?[}]?'
export CTL_NIWA="(^|[^A-Za-z0-9_./-])([^[:space:]\"$Q=;|&()]*/)?(niwa|[\$][{]?NIWA$TOOLVAR)[\"$Q]?[[:space:]]+dispatch([^A-Za-z0-9_-]|\$)"
export CTL_NIWA_SAFE="dispatch[[:space:]]+(--help|-h)([[:space:]]|\$|[;|&)\"$Q])"
export CTL_CLAUDE="(^|[^A-Za-z0-9_./-])([^[:space:]\"$Q=;|&()]*/)?(claude|[\$][{]?CLAUDE$TOOLVAR)[\"$Q]?([[:space:]]+[^[:space:]]|[[:space:]]*\$|[[:space:]]*[;|&])"
export CTL_CLAUDE_SAFE="(claude|[\$][{]?CLAUDE$TOOLVAR)[\"$Q]?[[:space:]]+(agents|rm|--version|-v|--help|-h)([[:space:]]|\$|[;|&)\"$Q])"
export CTL_PY="[\"$Q]claude[\"$Q][[:space:]]*[],]|[\"$Q]niwa[\"$Q][[:space:]]*,[[:space:]]*[\"$Q]dispatch[\"$Q]"

# AWK_TEXT -- the awk function text(s): s with every quoted string that holds
# a space or a tab replaced by "", read left to right so each quote pairs with
# the next of its kind (a backslash escapes a double quote). A message such as
# "claude agents could not be read" is text, not a command, and not a path a
# command runs.
AWK_TEXT='
    function text(s,    q, out, i, c, j, seg) {
        q = sprintf("%c", 39)
        out = ""
        i = 1
        while (i <= length(s)) {
            c = substr(s, i, 1)
            if (c == "\\") { out = out substr(s, i, 2); i += 2; continue }
            if (c != q && c != "\"") { out = out c; i++; continue }
            j = i + 1
            while (j <= length(s) && substr(s, j, 1) != c) {
                if (c == "\"" && substr(s, j, 1) == "\\") j++
                j++
            }
            seg = substr(s, i, j - i + 1)
            # The script a shell is handed with -c is a command, not text:
            # keep what is inside its quotes.
            if (out ~ /(^|[^A-Za-z0-9_])-c[ \t]+$/) out = out "; " substr(seg, 2, length(seg) - 2)
            else out = out ((seg ~ /[ \t]/) ? "\"\"" : seg)
            i = j + 1
        }
        return out
    }
'

# launches <file> -- print `<line>\t<what>` for each launch in <file> that no
# earlier line, nor the line itself, unsets KOTO_SESSION_* for.
launches() {
    awk "$AWK_TEXT"'
        BEGIN {
            unset_re = ENVIRON["CTL_UNSET"]; niwa_re = ENVIRON["CTL_NIWA"]
            claude_re = ENVIRON["CTL_CLAUDE"]; safe_re = ENVIRON["CTL_CLAUDE_SAFE"]
            niwa_safe_re = ENVIRON["CTL_NIWA_SAFE"]; py_re = ENVIRON["CTL_PY"]
        }
        /^[[:space:]]*#/ { next }
        {
            line = $0
            if (line ~ unset_re) cleared = 1
            if (cleared) next
            if (line ~ py_re) { print NR "\tclaude or niwa dispatch (as a Python argument list)"; next }
            line = text(line)
            # A subcommand that starts nothing is set aside where it occurs,
            # so a launch beside it on the same line is still seen.
            gsub(niwa_safe_re, "", line)
            gsub(safe_re, "", line)
            if (line ~ niwa_re) { print NR "\tniwa dispatch"; next }
            if (line ~ claude_re) print NR "\tclaude"
        }
    ' "$1"
}

# refs <file> <dir of file> -- every existing file inside ROOT that a `.sh` or
# `.py` path names, on a line of <file> that isn't a comment and outside a
# quoted string holding a space, one per line.
refs() {
    local f="$1" d="$2" tok rel t cands cand
    awk "$AWK_TEXT"' /^[[:space:]]*#/ { next } { print text($0) }' "$f" 2>/dev/null \
        | grep -oE '[A-Za-z0-9_./${}-]*[A-Za-z0-9_-][.](sh|py)([^A-Za-z0-9_]|$)' \
        | sed -E 's/[^A-Za-z0-9_]$//' \
        | LC_ALL=C sort -u \
        | while IFS= read -r tok; do
            # Drop a leading variable: $DIR/x.sh, ${PLUGIN_DIR}/scripts/x.sh.
            rel=$(printf '%s' "$tok" | sed -E 's/^.*[$][{]?[A-Za-z_][A-Za-z0-9_]*[}]?//')
            # The path as written from the file's directory and from the
            # root, then each tail of it that starts at scripts/ or skills/.
            cands="$d/$rel
$ROOT/${rel#/}"
            t="$rel"
            while :; do
                case "$t" in
                    scripts/*|skills/*) cands="$cands
$ROOT/$t" ;;
                esac
                case "$t" in */*) t="${t#*/}" ;; *) break ;; esac
            done
            while IFS= read -r cand; do
                [ -f "$cand" ] || continue
                cand=$(cd -P -- "$(dirname -- "$cand")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename -- "$cand")") || continue
                case "$cand" in "$ROOT"/*) printf '%s\n' "$cand"; break ;; esac
            done <<EOF_CANDS
$cands
EOF_CANDS
        done
}

# report <where> <file> -- one stdout line per launch in <file>, each named
# <where><line>.
report() {
    local where="$1" f="$2" n what
    while IFS="$TAB" read -r n what; do
        [ -n "$n" ] || continue
        printf '%s%s: launches %s without unsetting KOTO_SESSION_*\n' "$where" "$n" "$what"
        COUNT=$((COUNT + 1))
    done <<EOF_LAUNCHES
$(launches "$f")
EOF_LAUNCHES
}

SEEN="
"
COMMANDS=0
SCRIPTS=0
while IFS= read -r tpl; do
    [ -n "$tpl" ] || continue
    rm -rf "$WORK/cmds"
    mkdir -p "$WORK/cmds"
    # One file per `command:` in the frontmatter, named for its line: the
    # value unquoted ('' is a quote inside single quotes; \" and \\ inside
    # double ones), or a block scalar's lines.
    awk -v out="$WORK/cmds" '
        BEGIN { q = sprintf("%c", 39) }
        NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
        /^---[[:space:]]*$/ { exit }
        blk {
            match($0, /^[[:space:]]*/)
            if ($0 ~ /^[[:space:]]*$/ || RLENGTH > ind) { print $0 > file; next }
            close(file); blk = 0
        }
        /^[[:space:]]*command:/ {
            file = out "/" NR
            v = $0
            sub(/^[[:space:]]*command:[[:space:]]*/, "", v)
            if (v ~ /^[|>]/) { match($0, /^[[:space:]]*/); ind = RLENGTH; blk = 1; printf "" > file; next }
            if (substr(v, 1, 1) == q) {
                sub("^" q, "", v); sub(q "[[:space:]]*$", "", v); gsub(q q, q, v)
            } else if (substr(v, 1, 1) == "\"") {
                sub(/^"/, "", v); sub(/"[[:space:]]*$/, "", v); gsub(/\\"/, "\"", v); gsub(/\\\\/, "\\", v)
            }
            print v > file
            close(file)
        }
    ' "$tpl"
    name="${tpl#"$ROOT"/}"
    for c in "$WORK"/cmds/*; do
        [ -f "$c" ] || continue
        COMMANDS=$((COMMANDS + 1))
        at="${c##*/}"
        report "$name:$at: the command, its line " "$c"
        # The scripts the command runs, then the scripts they run. A
        # {{PLUGIN_ROOT}}/ path is the same path from the root.
        sed 's#{{PLUGIN_ROOT}}/##g' "$c" >"$WORK/cmd.sh"
        queue=$(refs "$WORK/cmd.sh" "$ROOT")
        while [ -n "$queue" ]; do
            s="${queue%%
*}"
            case "$queue" in
                *"
"*) queue="${queue#*
}" ;;
                *) queue="" ;;
            esac
            [ -n "$s" ] || continue
            case "$SEEN" in *"
$s
"*) continue ;; esac
            SEEN="$SEEN$s
"
            SCRIPTS=$((SCRIPTS + 1))
            report "$name:$at runs ${s#"$ROOT"/}:" "$s"
            more=$(refs "$s" "$(dirname -- "$s")")
            while IFS= read -r callee; do
                [ -n "$callee" ] || continue
                if [ -s "$WORK/allow" ] && grep -qxF "${s#"$ROOT"/}$TAB${callee#"$ROOT"/}" "$WORK/allow"; then
                    printf '%s\t%s\n' "${s#"$ROOT"/}" "${callee#"$ROOT"/}" >>"$WORK/used"
                    continue
                fi
                queue="$queue${queue:+
}$callee"
            done <<EOF_MORE
$more
EOF_MORE
        done
    done
done <<EOF_TEMPLATES
$TEMPLATES
EOF_TEMPLATES

# Every allow record has to name a call this run passed over; one that no
# longer matches is reported, so a stale record can't hide a later call.
if [ "$CHECK_STALE" -eq 1 ] && [ -s "$WORK/allow" ]; then
    while IFS= read -r pair; do
        [ -n "$pair" ] || continue
        if ! grep -qxF "$pair" "$WORK/used" 2>/dev/null; then
            printf '%s: stale record: %s calls nothing the templates reach; remove it\n' \
                "${ALLOW#"$ROOT"/}" "$(printf '%s' "$pair" | sed "s/$TAB/ -> /")"
            COUNT=$((COUNT + 1))
        fi
    done <"$WORK/allow"
fi

if [ "$COUNT" -gt 0 ]; then
    printf '%s: %s launch(es) inside a koto tick would inherit KOTO_SESSION_*; unset it first, or move the launch out of the gate or action\n' "$PROG" "$COUNT" >&2
    exit 1
fi
printf '%s: OK (%s template command(s) and the %s script(s) they run; no launch inside a tick)\n' "$PROG" "$COMMANDS" "$SCRIPTS" >&2
exit 0
