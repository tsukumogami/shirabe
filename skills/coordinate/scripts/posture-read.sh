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
#   teardown  niwa destroy, niwa reap, niwa instance remove, niwa remove
#
# Per step: a matching deny rule gives `deny`; else a matching ask gives
# `confirm`; else a matching allow, or defaultMode bypassPermissions with no
# matching rule, gives `permit`; any other defaultMode gives `confirm`.
# Permission rules look like Bash(gh pr merge:*) or Bash(gh pr merge *); a
# deny or ask rule also matches when its text names a step's command. Then
# PreToolUse hooks whose matcher covers Bash: a hook whose command or script
# text mentions a step's command makes that step `confirm` unless it is
# `deny` (the reader can't tell what the hook decides, so it reserves the
# step); a hook script that can't be read makes every step not already
# `deny` `unread`. With no root found, every step is `unread`.
#
# Verdict token: `readable merge=<v> close=<v> teardown=<v>` when no step is
# unread, else `unread merge=<v> close=<v> teardown=<v>`, with each <v> one of
# permit, deny, confirm, unread.
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
step_patterns() {
    case "$1" in
        merge) printf '%s\n' 'gh pr merge' 'merge-exec.sh' 'land-merge.sh' ;;
        close) printf '%s\n' 'gh issue close' 'gh pr close' 'record-write.sh --close' ;;
        teardown) printf '%s\n' 'niwa destroy' 'niwa reap' 'niwa instance remove' 'niwa remove' ;;
    esac
}
# Commands a rule is tried against, one per way the step can be typed.
step_commands() {
    case "$1" in
        merge) printf '%s\n' 'gh pr merge 12 --repo o/r --squash --match-head-commit 0' \
            'bash /p/skills/execute/scripts/merge-exec.sh o/r 12 0' '/p/skills/execute/scripts/merge-exec.sh o/r 12 0' \
            'bash /p/skills/coordinate/scripts/land-merge.sh --session s' '/p/skills/coordinate/scripts/land-merge.sh --session s' ;;
        close) printf '%s\n' 'gh issue close 7 --repo o/r' 'gh pr close 7 --repo o/r' \
            'bash /p/skills/coordinate/scripts/record-write.sh --session s --body-file f --close' \
            '/p/skills/coordinate/scripts/record-write.sh --session s --body-file f --close' ;;
        teardown) printf '%s\n' 'niwa destroy x' 'niwa reap' 'niwa instance remove x' 'niwa remove x' ;;
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

# Hook texts: the command, plus every script it names, read as text.
HOOK_UNREAD=0
: > "$T/hooktext"
while IFS='	' read -r root cmd; do
    [ -n "$cmd" ] || continue
    printf '%s\n' "$cmd" >> "$T/hooktext"
    # Split on whitespace without globbing: a hook's `*` must stay text.
    set -f
    for tok in $(printf '%s' "$cmd" | tr -d "\"'"); do
        case "$tok" in -*|*=*|*'>'*|*'<'*|*'|'*|*';'*|*'&'*) continue ;; esac
        case "$tok" in */*) ;; *) continue ;; esac
        p=$(printf '%s' "$tok" | sed -e "s|\${CLAUDE_PROJECT_DIR}|$root|g" -e "s|\$CLAUDE_PROJECT_DIR|$root|g" -e "s|^~/|$HOME/|")
        case "$p" in /dev/*|/bin/*|/sbin/*|/usr/*|/opt/homebrew/*) continue ;; esac
        case "$p" in /*) ;; *) p="$root/$p" ;; esac
        if [ -f "$p" ] && [ -r "$p" ]; then
            cat "$p" >> "$T/hooktext" 2> /dev/null || HOOK_UNREAD=1
            printf '\n' >> "$T/hooktext"
        else
            HOOK_UNREAD=1
            printf '%s\n' "$p" >> "$T/unreadable"
        fi
    done
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
    TOKEN="$TOKEN $step=$v"
    STEPS_JSON=$(printf '%s' "$STEPS_JSON" | jq -c --arg s "$step" --arg v "$v" --arg w "$why" '.[$s] = {verdict: $v, why: $w}')
done
TOKEN="$TOKEN_WORD$TOKEN"

jq -n --arg t "$TOKEN" --arg i "$IROOT" --arg w "$WROOT" --arg m "$MODE" --argjson f "$FILES_JSON" --argjson s "$STEPS_JSON" \
    '{token: $t, instance_root: $i, workspace_root: $w, default_mode: $m, files: $f, steps: $s}' > "$T/detail.json"
lib_emit start_posture "$TOKEN" coord/posture.json "$T/detail.json"
