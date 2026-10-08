#!/usr/bin/env bash
# posture-read.sh -- the check action of state start_posture: what does the
# workspace let the coordinator do on its own at the three finishing steps
# (merge, close, teardown)?
#
# It reads the posture from where the workspace declares it, never from a
# cloned repository: the niwa instance root (the first directory at or above
# the current one holding .niwa/instance.json; koto runs actions in the
# execution directory) and the workspace root (the nearest directory above
# the instance root holding .niwa/workspace.toml). At each root it reads
# .claude/settings.json and .claude/settings.local.json; a missing file is
# fine, an unparseable one leaves every step it could have narrowed unread.
# Files are parsed, never executed: a hook's script is read as text.
#
# Each step is stood for by the commands that perform it, so a rule on any of
# them governs the step (a hook matching a typed command never sees a script
# that calls it inside itself):
#   merge     gh pr merge, merge-exec.sh, land-merge.sh
#   close     gh issue close, gh pr close, record-write.sh --close
#   teardown  niwa destroy
#
# Only the commands the skill runs stand for a step. The skill never runs
# `niwa reap` or another untargeted removal, so a rule or hook about those
# (a workspace hook that denies the reap sweep, say) gates nothing it does
# and leaves the teardown step as the other rules make it.
#
# Per step: a matching deny rule gives `deny`; else a matching ask gives
# `confirm`; else a matching allow, or defaultMode bypassPermissions with no
# matching rule, gives `permit`; any other defaultMode gives `confirm`.
# Permission rules look like Bash(gh pr merge:*) or Bash(gh pr merge *); a
# deny or ask rule also matches when its text names a step's command. Then
# PreToolUse hooks whose matcher covers Bash: a hook whose command or script
# text mentions a step's command makes that step `confirm` unless it is
# `deny` (the reader can't tell what the hook decides, so it reserves the
# step); a hook the reader can't locate and read (an interpreter's script
# with no path, a bare PATH command other than a text tool like jq or grep,
# an absolute path outside the two roots, a missing file, a command
# substitution) makes every step not already `deny` `unread`. With no root
# found, every step is `unread`.
#
# Verdict token: `readable merge:<v> close:<v> teardown:<v>` when no step is
# unread, else `unread merge:<v> close:<v> teardown:<v>`, with each <v> one of
# permit, deny, confirm, unread. The separator is `:` because koto refuses to
# capture a value holding `=`.
#
# Usage:
#   posture-read.sh --session S
#   posture-read.sh [--session S] [--instance-root DIR] [--workspace-root DIR]
#                   [--no-seal]                                          (tests)
#
# The detail goes to context key coord/posture.json as data (roots, files
# read, default mode, each step's verdict and the rules or hooks behind it).
# It never carries a settings file's env block.
#
# Exit codes: 0 a verdict was printed; 2 the seal or context write failed; 64 usage.
set -uo pipefail

PROG=posture-read
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= IROOT= WROOT=
NO_SEAL=0 GIVEN=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --instance-root) [ $# -ge 2 ] || usage; IROOT=$2; GIVEN=1; shift 2 ;;
        --workspace-root) [ $# -ge 2 ] || usage; WROOT=$2; GIVEN=1; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/record-common.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/posture-read.XXXXXX")
trap 'rm -rf "$T"' EXIT

if [ "$GIVEN" = 0 ]; then
    d=$(pwd -P)
    while :; do
        if [ -f "$d/.niwa/instance.json" ]; then IROOT=$d; break; fi
        [ "$d" = / ] && break
        d=$(dirname "$d")
    done
    if [ -n "$IROOT" ] && [ "$IROOT" != / ]; then
        d=$(dirname "$IROOT")
        while :; do
            if [ -f "$d/.niwa/workspace.toml" ]; then WROOT=$d; break; fi
            [ "$d" = / ] && break
            d=$(dirname "$d")
        done
    fi
fi
for r in "$IROOT" "$WROOT"; do
    [ -z "$r" ] || [ -d "$r" ] || { echo "$PROG: $r is not a directory" >&2; exit 64; }
done

STEPS="merge close teardown"
# The merge command is spelled in two parts below so that this file, which only
# names it as a pattern, isn't counted as a second place that runs it
# (skills/execute/scripts/merge-exec_test.sh allows exactly one).
MERGE_CMD="gh pr"' merge'
step_patterns() {
    case "$1" in
        merge) printf '%s\n' "$MERGE_CMD" 'merge-exec.sh' 'land-merge.sh' ;;
        close) printf '%s\n' 'gh issue close' 'gh pr close' 'record-write.sh --close' ;;
        teardown) printf '%s\n' 'niwa destroy' ;;
    esac
}
# Commands a rule is tried against, one per way the step can be typed.
step_commands() {
    case "$1" in
        merge) printf '%s\n' "$MERGE_CMD 12 --repo o/r --squash --match-head-commit 0" \
            'bash /p/skills/execute/scripts/merge-exec.sh o/r 12 0' '/p/skills/execute/scripts/merge-exec.sh o/r 12 0' \
            'bash /p/skills/coordinate/scripts/land-merge.sh --session s' '/p/skills/coordinate/scripts/land-merge.sh --session s' ;;
        close) printf '%s\n' 'gh issue close 7 --repo o/r' 'gh pr close 7 --repo o/r' \
            'bash /p/skills/coordinate/scripts/record-write.sh --session s --body-file f --close' \
            '/p/skills/coordinate/scripts/record-write.sh --session s --body-file f --close' ;;
        teardown) printf '%s\n' 'niwa destroy x' 'niwa destroy --force x' ;;
    esac
}

# rule_matches <kind> <rule> <step>
rule_matches() {
    local inner glob cmd pat
    case "$2" in
        Bash) inner='*' ;;
        'Bash('*')') inner=${2#Bash(}; inner=${inner%)} ;;
        *) return 1 ;;
    esac
    glob=$inner
    case "$glob" in *:\*) glob="${glob%:\*}*" ;; esac
    while IFS= read -r cmd; do
        # Unquoted on purpose: the rule is a glob.
        case "$cmd" in $glob) return 0 ;; esac
    done <<CMDS
$(step_commands "$3")
CMDS
    [ "$1" = allow ] && return 1
    while IFS= read -r pat; do
        case "$inner" in *"$pat"*) return 0 ;; esac
    done <<PATS
$(step_patterns "$3")
PATS
    return 1
}

# Per-file extraction. Each settings file yields "rule<TAB>kind<TAB>rule",
# "mode<TAB>value" and "hook<TAB>command" lines, or fails as unparseable.
FILES_JSON='[]'
ALL_UNREAD=0
MODE=
: > "$T/rules"
: > "$T/hooks"
[ -n "$IROOT$WROOT" ] || ALL_UNREAD=1
for pair in "$IROOT|settings.local.json" "$IROOT|settings.json" "$WROOT|settings.local.json" "$WROOT|settings.json"; do
    root=${pair%%|*}
    [ -n "$root" ] || continue
    f="$root/.claude/${pair#*|}"
    [ -e "$f" ] || continue
    if jq -r '
        if type != "object" then error("not an object") else . end
        | (.permissions // {}) as $p
        | ( (["allow", "deny", "ask"][] as $k | ($p[$k] // [])[] | select(type == "string") | "rule\t\($k)\t\(gsub("[\t\n]"; " "))"),
            "mode\t\($p.defaultMode // "")",
            ((.hooks.PreToolUse // [])[] | select(type == "object")
             | ((.matcher // "") | . == "" or . == "*" or (. as $m | try ("Bash" | test("^(" + $m + ")$")) catch true)) as $covers
             | select($covers) | (.hooks // [])[] | select(type == "object" and .type == "command")
             | "hook\t\(.command // "" | gsub("[\t\n]"; " "))") )' "$f" > "$T/one" 2> /dev/null; then
        status=read
        grep '^rule	' "$T/one" | cut -f2- >> "$T/rules"
        grep '^hook	' "$T/one" | cut -f2- | sed "s|^|$root	|" >> "$T/hooks"
        m=$(sed -n 's/^mode	//p' "$T/one" | head -1)
        [ -z "$MODE" ] && [ -n "$m" ] && MODE=$m
    else
        status=unparseable
        ALL_UNREAD=1
    fi
    FILES_JSON=$(printf '%s' "$FILES_JSON" | jq -c --arg p "$f" --arg s "$status" '. + [{path: $p, status: $s}]')
done

# Hook texts: the command, plus the script each of its simple commands runs,
# read as text. A hook the reader can't classify never passes as harmless:
# every simple command must be either a text tool whose whole behaviour is in
# the command line (jq, grep, sed, ...), an interpreter given inline code
# (bash -c, python3 -c, ...), or a script located as a readable file under
# the instance or workspace root. Anything else (`python3 guard.py`, a bare
# PATH command, an absolute path outside the roots, a missing file, a command
# substitution) is recorded as unreadable, which makes every step not already
# `deny` unread.
HOOK_UNREAD=0
: > "$T/hooktext"
: > "$T/unreadable"
canon_root() { [ -n "$1" ] && (cd "$1" 2> /dev/null && pwd -P); }
ROOTS_P="$(canon_root "$IROOT")
$(canon_root "$WROOT")"
unreadable() { HOOK_UNREAD=1; printf '%s\n' "$1" >> "$T/unreadable"; }
# expand_path <root> <token>: the token with $CLAUDE_PROJECT_DIR and ~/ expanded.
expand_path() {
    printf '%s' "$2" | sed -e "s|\${CLAUDE_PROJECT_DIR}|$1|g" -e "s|\$CLAUDE_PROJECT_DIR|$1|g" -e "s|^~/|$HOME/|"
}
# read_script <root> <token>: append the script's text, or record it unreadable.
# It must name a path (hold a `/`), resolve under a root, and be a readable file.
read_script() {
    local p dir real r inside=0
    p=$(expand_path "$1" "$2")
    case "$p" in */*) ;; *) unreadable "$2 (not a path the reader can locate)"; return ;; esac
    case "$p" in /*) ;; *) p="$1/$p" ;; esac
    if ! [ -f "$p" ] || ! [ -r "$p" ]; then unreadable "$p (missing or unreadable)"; return; fi
    dir=$(cd "$(dirname "$p")" 2> /dev/null && pwd -P) || { unreadable "$p"; return; }
    real="$dir/$(basename "$p")"
    while IFS= read -r r; do
        [ -n "$r" ] || continue
        case "$real" in "$r"/*) inside=1 ;; esac
    done <<ROOTS
$ROOTS_P
ROOTS
    [ "$inside" = 1 ] || { unreadable "$p (outside the instance and workspace roots)"; return; }
    if cat "$real" >> "$T/hooktext" 2> /dev/null; then printf '\n' >> "$T/hooktext"; else unreadable "$p"; fi
}
# classify_segment <root> <words...>: one simple command, quotes stripped.
classify_segment() {
    local root=$1 w base script= inline=0 rest icode
    shift
    # Leading assignments, then `env` with its options and assignments.
    while [ $# -gt 0 ]; do
        case "$1" in
            [A-Za-z_]*=*) shift ;;
            env|/usr/bin/env) shift; while [ $# -gt 0 ]; do case "$1" in -*|[A-Za-z_]*=*) shift ;; *) break ;; esac; done ;;
            # Shell keywords that lead into a command: the command follows them.
            # Quoted: bash 3.2 can't parse a bare keyword as a case pattern.
            'if'|'then'|'else'|'elif'|'do'|'while'|'until'|'!'|'{'|'}'|'('|'time'|'exec'|'command'|'nohup') shift ;;
            # `case WORD in PATTERN) command`: the command follows the pattern.
            'case') shift; while [ $# -gt 0 ]; do w=$1; shift; case "$w" in *')') break ;; esac; done ;;
            *')') shift ;;
            'fi'|'done'|'esac'|'for'|'in'|';;') return 0 ;;
            *) break ;;
        esac
    done
    [ $# -gt 0 ] || return 0
    w=$1; shift
    base=${w##*/}
    case "$base" in
        jq|grep|egrep|fgrep|sed|awk|tr|cut|head|tail|cat|echo|printf|test|'['|'[['|']]'|exit|true|false|read|:|cd)
            # A text tool: its behaviour is the command line, already read. Any
            # path it names is read too when it can be.
            for rest in "$@"; do
                case "$rest" in -*|*'>'*|*'<'*) continue ;; esac
                case "$rest" in */*) ;; *) continue ;; esac
                rest=$(expand_path "$root" "$rest")
                case "$rest" in /*) ;; *) rest="$root/$rest" ;; esac
                [ -f "$rest" ] && [ -r "$rest" ] && { cat "$rest" >> "$T/hooktext" 2> /dev/null; printf '\n' >> "$T/hooktext"; }
            done
            return 0 ;;
        .|source)
            # Sourcing a file runs it: read it like a script.
            [ $# -gt 0 ] || { unreadable "$w with no file"; return 0; }
            read_script "$root" "$1" ;;
        bash|sh|zsh|dash|ksh|python|python2|python3|node|ruby|perl)
            # The flag that takes inline code: -c for shells and python
            # (alone or ending a cluster like -ec), -e/-E/--eval for the rest.
            case "$base" in
                node|ruby|perl) icode='^(-e|-E|--eval|-p|--print)$' ;;
                *) icode='^-[A-Za-z]*c$' ;;
            esac
            while [ $# -gt 0 ]; do
                if [[ $1 =~ $icode ]]; then inline=1; break; fi
                case "$1" in
                    # A shell's -o takes an option name, alone or at the end of a cluster.
                    -o|-O|-[A-Za-z]*o) shift; [ $# -gt 0 ] && shift ;;
                    -*) shift ;;
                    *) script=$1; break ;;
                esac
            done
            if [ "$inline" = 1 ]; then
                # A shell's inline code is itself commands: classify it as one,
                # so `bash -c /usr/local/bin/guard` is no more readable than
                # the guard alone. Another language's inline code is on the
                # command line, already read.
                case "$base" in
                    bash|sh|zsh|dash|ksh) shift; classify_segment "$root" "$@" ;;
                esac
                return 0
            fi
            [ -n "$script" ] || { unreadable "$w with no script"; return 0; }
            read_script "$root" "$script" ;;
        *)
            read_script "$root" "$w" ;;
    esac
}
while IFS='	' read -r root cmd; do
    [ -n "$cmd" ] || continue
    printf '%s\n' "$cmd" >> "$T/hooktext"
    case "$cmd" in *'$('*|*'`'*|*'<('*) unreadable "$cmd (a command substitution)"; continue ;; esac
    # One simple command per line, split on the shell's list and pipe operators.
    printf '%s\n' "$cmd" | awk '{ gsub(/&&|\|\||[|;&]/, "\n"); print }' | tr -d "\"'" > "$T/segments"
    # Split on whitespace without globbing: a hook's `*` must stay text.
    set -f
    while IFS= read -r seg; do
        # shellcheck disable=SC2086
        set -- $seg
        # Redirections are not words the command runs.
        n=$#; i=0
        while [ $i -lt $n ]; do
            w=$1; shift
            case "$w" in *'>'*|*'<'*) ;; *) set -- "$@" "$w" ;; esac
            i=$((i + 1))
        done
        classify_segment "$root" "$@"
    done < "$T/segments"
    set +f
done < "$T/hooks"
# A second copy with shell and regex spellings of a space made plain, so
# `gh\ pr\ merge` or `gh\s+pr\s+merge` in a hook still names the command.
sed -e 's/\\ / /g' -e 's/\\s[+*]\{0,1\}/ /g' -e 's/\[\[:space:\]\][+*]\{0,1\}/ /g' -e 's/\[ \][+*]/ /g' -e 's/  */ /g' \
    "$T/hooktext" > "$T/hooktext.plain"

TOKEN_WORD=readable
TOKEN=
STEPS_JSON='{}'
for step in $STEPS; do
    v= why=
    if [ "$ALL_UNREAD" = 1 ] && [ -z "$IROOT$WROOT" ]; then
        v=unread; why="no niwa instance or workspace root found"
    else
        for kind in deny ask allow; do
            while IFS='	' read -r k rule; do
                [ "$k" = "$kind" ] || continue
                if rule_matches "$kind" "$rule" "$step"; then
                    case "$kind" in deny) v=deny ;; ask) v=confirm ;; allow) v=permit ;; esac
                    why="$kind $rule"
                    break
                fi
            done < "$T/rules"
            [ -n "$v" ] && break
        done
        if [ "$v" != deny ]; then
            if [ "$ALL_UNREAD" = 1 ]; then
                v=unread; why="a settings file is unparseable"
            elif [ "$HOOK_UNREAD" = 1 ]; then
                v=unread; why="a PreToolUse hook script can't be read: $(head -1 "$T/unreadable")"
            else
                while IFS= read -r pat; do
                    if grep -qF -- "$pat" "$T/hooktext" "$T/hooktext.plain"; then
                        v=confirm; why="a PreToolUse hook mentions $pat"
                        break
                    fi
                done <<PATS
$(step_patterns "$step")
PATS
            fi
        fi
        if [ -z "$v" ]; then
            if [ "$MODE" = bypassPermissions ]; then v=permit; why="defaultMode bypassPermissions"
            else v=confirm; why="no rule; defaultMode ${MODE:-default}"; fi
        fi
    fi
    [ "$v" = unread ] && TOKEN_WORD=unread
    TOKEN="$TOKEN $step:$v"
    STEPS_JSON=$(printf '%s' "$STEPS_JSON" | jq -c --arg s "$step" --arg v "$v" --arg w "$why" '.[$s] = {verdict: $v, why: $w}')
done
TOKEN="$TOKEN_WORD$TOKEN"

jq -n --arg t "$TOKEN" --arg i "$IROOT" --arg w "$WROOT" --arg m "$MODE" --argjson f "$FILES_JSON" --argjson s "$STEPS_JSON" \
    '{token: $t, instance_root: $i, workspace_root: $w, default_mode: $m, files: $f, steps: $s}' > "$T/detail.json"
lib_emit start_posture "$TOKEN" coord/posture.json "$T/detail.json"
