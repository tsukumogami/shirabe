#!/usr/bin/env bash
# posture-read.sh -- the check action of state start_posture: what does the
# workspace let the coordinator do on its own at the finishing steps (merge,
# close, teardown, release)?
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
#   close     gh's issue close and pull request close commands
#   teardown  niwa destroy, claude rm, teardown-pass.sh
#   release   gh release create
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
# substitution) makes every step not already `deny` `unread`. A
# `command -v NAME` lookup runs nothing and is read past. One exemption by
# name: niwa's own worktree hook, exactly as niwa writes it
# (`command -v niwa ... && exec niwa worktree guard; exec '<abs>' worktree guard`,
# or `worktree from-hook`), gates no step, since niwa's guard decides only
# worktree builds and git; any other niwa call is a PATH command like the
# rest. With no root found, every step is `unread`.
#
# The coordinator's own grant. When niwa is found (on PATH, else an
# executable $NIWA_BIN), CLAUDE_CODE_SESSION_ID is set and an instance root
# was found, the reader asks niwa once, bounded at NIWA_LOOKUP_SECONDS (3):
#   niwa authority check --json --session <id> -C <instance root>
#        --point merge-pr --point close-issue --point cut-release
# The answer counts only when it exits 0 with schema niwa.authority.check/v1
# and every state, authority, level, decider and author_exclusion inside
# niwa's vocabularies; anything else is a failed lookup, the gate's own rule,
# so this reading never trusts an answer the gate would have refused. Then:
#   bound            merge, close and release skip the hook reading: each is
#                    the stricter of its permission reading (rules, else an
#                    unparseable file's unread, else defaultMode) and the
#                    grant's answer, by the table the workspace gate uses:
#                      held, decider session, author exclusion off  permit
#                      not held                                       deny
#                      held, decider dispatcher                       deny
#                      held, decider person or author exclusion on    deny
#                        for merge and release, confirm for close
#                    teardown reads as below.
#   record-unusable  merge and release are deny (niwa answers this only for
#                    the dispatch's own session, so it can't show the grant);
#                    every other step reads as below.
#   anything else    (not-dispatched, a failed lookup, no lookup) every step
#                    reads as below, as it did before the grant existed.
# The grant never lifts a deny or an ask rule: Claude Code's own permissions
# still apply to a command the gate allows.
#
# Verdict token: `readable merge:<v> close:<v> teardown:<v> release:<v>` when
# none of merge, close and teardown is unread, else `unread ...` with the same
# steps, with each <v> one of permit, deny, confirm, unread. The leading word
# doesn't follow release: an unread release alone leaves the token as it read
# before the step existed, and stays reserved for a person. The separator is
# `:` because koto refuses to capture a value holding `=`.
#
# Usage:
#   posture-read.sh --session S
#   posture-read.sh [--session S] [--instance-root DIR] [--workspace-root DIR]
#                   [--no-seal]                                          (tests)
#
# The detail goes to context key coord/posture.json as data (roots, files
# read, default mode, each step's verdict, the rules, hooks or grant behind it
# and its source, `grant` for a step the grant decided and `workspace`
# otherwise, and the lookup's answer under `grant_check`). It never carries a
# settings file's env block.
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
. "$HERE/state-common.sh"
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/posture-read.XXXXXX") || lib_die2 "cannot make a temporary directory"
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

STEPS="merge close teardown release"
# The merge command is spelled in two parts below so that this file, which only
# names it as a pattern, isn't counted as a second place that runs it
# (skills/execute/scripts/merge-exec_test.sh allows exactly one).
MERGE_CMD="gh pr"' merge'
# The close commands likewise: this file names them as patterns and closes
# nothing, so a search for the scripts that close an issue or a pull request
# doesn't find it.
CLOSE_ISSUE="gh issue"' close' CLOSE_PR="gh pr"' close'
# And the release command, which this file names and never runs.
RELEASE_CMD="gh release"' create'
step_patterns() {
    case "$1" in
        merge) printf '%s\n' "$MERGE_CMD" 'merge-exec.sh' 'land-merge.sh' ;;
        close) printf '%s\n' "$CLOSE_ISSUE" "$CLOSE_PR" ;;
        teardown) printf '%s\n' 'niwa destroy' 'claude rm' 'teardown-pass.sh' ;;
        release) printf '%s\n' "$RELEASE_CMD" ;;
    esac
}
# Commands a rule is tried against, one per way the step can be typed.
step_commands() {
    case "$1" in
        merge) printf '%s\n' "$MERGE_CMD 12 --repo o/r --squash --match-head-commit 0" \
            'bash /p/skills/execute/scripts/merge-exec.sh o/r 12 0' '/p/skills/execute/scripts/merge-exec.sh o/r 12 0' \
            'bash /p/skills/coordinate/scripts/land-merge.sh --session s' '/p/skills/coordinate/scripts/land-merge.sh --session s' ;;
        close) printf '%s\n' "$CLOSE_ISSUE 7 --repo o/r" "$CLOSE_PR 7 --repo o/r" ;;
        teardown) printf '%s\n' 'niwa destroy x' 'niwa destroy --force x' 'claude rm x' \
            'bash /p/skills/coordinate/scripts/teardown-pass.sh run --session s --keyseal k' '/p/skills/coordinate/scripts/teardown-pass.sh run --session s --keyseal k' ;;
        release) printf '%s\n' "$RELEASE_CMD v1.2.3 --repo o/r --notes-file n.md" ;;
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
# expand_path <root> <token>: the token with $CLAUDE_PROJECT_DIR and ~/ expanded
# (~/ only when HOME is set, so a missing HOME leaves a path nothing resolves).
expand_path() {
    printf '%s' "$2" | sed -e "s|\${CLAUDE_PROJECT_DIR}|$1|g" -e "s|\$CLAUDE_PROJECT_DIR|$1|g" -e "s|^~/|${HOME:-~}/|"
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
            'if'|'then'|'else'|'elif'|'do'|'while'|'until'|'!'|'{'|'}'|'('|'time'|'exec'|'nohup') shift ;;
            # `command -v NAME` and `command -V NAME` look one NAME up and run
            # nothing; any other `command` leads into the command after it.
            # One name only: the hook's newlines arrive here as spaces, so a
            # word after NAME may be a command on the next line.
            'command') [ $# -eq 3 ] && case "$2" in -v|-V) return 0 ;; esac; shift ;;
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
# is_niwa_hook <root> <words...>: the words are one of niwa's own worktree
# hooks, exactly as niwa writes them: the bare `niwa` or the
# $HOME/.tsuku/tools/current/niwa it installs, then `worktree guard` or
# `worktree from-hook` and nothing else. Safe to pass unread: niwa's guard
# refuses only worktree builds and git, never a merge, close or teardown
# command (niwa's internal/cli/worktree_guard.go, added in niwa 0.34.0). If
# niwa's guard ever decides more than that, this exemption goes. A bare
# `niwa` is trusted by name because the reader models what a hook gates, not
# whether PATH is sound, as it already does for the text tools.
is_niwa_hook() {
    local root=$1 w=$2
    shift 2
    case "$(expand_path "$root" "$w")" in
        niwa|"${HOME:-/nonexistent-home}/.tsuku/tools/current/niwa") ;;
        *) return 1 ;;
    esac
    case "$*" in 'worktree guard'|'worktree from-hook') return 0 ;; esac
    return 1
}
# niwa_shaped <root> <words-file>: the hook is niwa's own, as niwa writes it:
# every simple command is either a `command -v niwa` / `command -V niwa`
# lookup or, after an optional `exec`, one of niwa's worktree hooks. Anything
# else anywhere in the hook (an assignment, `env`, `cd`, another command)
# could change which niwa runs, so the hook is then classified like any other
# and niwa is just a PATH command. This is a whitelist of one shape, kept
# apart from classify_segment's general lead-in rules on purpose: widening
# those must never widen this.
niwa_shaped() {
    local root=$1 words=$2 seg
    while IFS= read -r seg; do
        # shellcheck disable=SC2086
        set -- $seg
        [ $# -gt 0 ] || continue
        [ "$1" = exec ] && shift
        [ $# -eq 3 ] && [ "$1" = command ] && [ "$3" = niwa ] && case "$2" in -v|-V) continue ;; esac
        [ $# -gt 0 ] && is_niwa_hook "$root" "$@" && continue
        return 1
    done < "$words"
    return 0
}
while IFS='	' read -r root cmd; do
    [ -n "$cmd" ] || continue
    printf '%s\n' "$cmd" >> "$T/hooktext"
    case "$cmd" in *'$('*|*'`'*|*'<('*|*'>('*) unreadable "$cmd (a command substitution)"; continue ;; esac
    # One simple command per line, split on the shell's list and pipe operators.
    # A redirection that duplicates or closes a descriptor (`2>&1`, `>&2`,
    # `<&0`, `>&-`) names no file, so it goes first: its `&` is not a list
    # operator. The descriptor number before it counts only as a word of its own.
    printf '%s\n' "$cmd" | awk '{
        gsub(/(^|[ \t])[0-9]+[<>]&([0-9]+-?|-)/, " "); gsub(/[<>]&([0-9]+-?|-)/, " ")
        gsub(/&&|\|\||[|;&]/, "\n"); print }' | tr -d "\"'" > "$T/segments"
    # Split on whitespace without globbing: a hook's `*` must stay text.
    # Redirections are not words the command runs, so each segment's words
    # are written once without them, for both readings below.
    set -f
    : > "$T/words"
    while IFS= read -r seg; do
        # shellcheck disable=SC2086
        set -- $seg
        kept=
        for w in "$@"; do case "$w" in *'>'*|*'<'*) ;; *) kept="$kept $w" ;; esac; done
        printf '%s\n' "${kept# }" >> "$T/words"
    done < "$T/segments"
    # niwa's own worktree hook gates no step; see is_niwa_hook.
    if niwa_shaped "$root" "$T/words"; then set +f; continue; fi
    while IFS= read -r seg; do
        # shellcheck disable=SC2086
        set -- $seg
        classify_segment "$root" "$@"
    done < "$T/words"
    set +f
done < "$T/hooks"
# A second copy with shell and regex spellings of a space made plain, so
# `gh\ pr\ merge` or `gh\s+pr\s+merge` in a hook still names the command.
sed -e 's/\\ / /g' -e 's/\\s[+*]\{0,1\}/ /g' -e 's/\[\[:space:\]\][+*]\{0,1\}/ /g' -e 's/\[ \][+*]/ /g' -e 's/  */ /g' \
    "$T/hooktext" > "$T/hooktext.plain"

# The grant lookup (see the header). GRANT_STATE is the answer's state, or
# empty when there was no usable answer; $T/grant holds "step<TAB>verdict<TAB>why"
# for the steps a bound answer decides.
GRANT_STATE=
CHECK_JSON='{"lookup": "skipped", "why": "no niwa on PATH or in NIWA_BIN"}'
: > "$T/grant"
find_niwa() {
    local p
    p=$(command -v niwa 2> /dev/null) && [ -n "$p" ] && { printf '%s\n' "$p"; return 0; }
    [ -n "${NIWA_BIN:-}" ] && [ -f "$NIWA_BIN" ] && [ -x "$NIWA_BIN" ] && { printf '%s\n' "$NIWA_BIN"; return 0; }
    return 1
}
NIWA=$(find_niwa)
IROOT_P=$(canon_root "$IROOT")
if [ -z "$NIWA" ]; then
    :
elif [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    CHECK_JSON='{"lookup": "skipped", "why": "CLAUDE_CODE_SESSION_ID is not set"}'
elif [ -z "$IROOT_P" ]; then
    CHECK_JSON='{"lookup": "skipped", "why": "no niwa instance root found"}'
elif ! dc_with_deadline "${NIWA_LOOKUP_SECONDS:-3}" dc_tree "$NIWA" authority check --json \
        --session "$CLAUDE_CODE_SESSION_ID" -C "$IROOT_P" --point merge-pr --point close-issue --point cut-release \
        < /dev/null > "$T/check.json" 2> /dev/null; then
    CHECK_JSON='{"lookup": "failed", "why": "niwa authority check exited non-zero or ran past its bound"}'
elif ! jq -e '
        def in_set($s): . as $v | any($s[]; . == $v);
        type == "object"
        and .schema == "niwa.authority.check/v1"
        and (.state | in_set(["bound", "record-unusable", "not-dispatched"]))
        and (if .state != "bound" then true else
            (.grant | type == "array")
            and all(.grant[]; type == "object" and (.authority | in_set(["merge-pr", "close-issue", "cut-release"])))
            and (.level | in_set(["autonomous", "supervised", "strict"]))
            and (.points | type == "array")
            and all(.points[]; type == "object"
                and (.decider | in_set(["session", "dispatcher", "person"]))
                and (.author_exclusion | in_set(["on", "off"])))
            and (.points as $pts | all("merge-pr", "close-issue", "cut-release"; . as $p | any($pts[]; .point == $p)))
        end)' "$T/check.json" > /dev/null 2>&1; then
    CHECK_JSON='{"lookup": "failed", "why": "niwa authority check printed no document this reader knows"}'
else
    GRANT_STATE=$(jq -r .state "$T/check.json")
    CHECK_JSON=$(jq -c '{lookup: "answered", state, reason, binding, dispatch_id, parent, level,
        grant: [.grant[]?.authority]} | with_entries(select(.value != null))' "$T/check.json")
    if [ "$GRANT_STATE" = bound ]; then
        jq -r '. as $d
            | ([.grant[].authority] | if length == 0 then "none" else join(",") end) as $holds
            | (["merge", "merge-pr"], ["close", "close-issue"], ["release", "cut-release"]) as [$s, $a]
            | first(.points[] | select(.point == $a)) as $p
            | (if (any($d.grant[]; .authority == $a) | not) then
                  ["deny", "the grant holds \($holds); needs \($a)"]
               elif $p.decider == "dispatcher" then
                  ["deny", "level \($d.level): \($a) is settled by dispatcher"]
               elif $p.decider == "person" then
                  [(if $s == "close" then "confirm" else "deny" end), "level \($d.level): \($a) is settled by person"]
               elif $p.author_exclusion == "on" then
                  [(if $s == "close" then "confirm" else "deny" end), "\($a) carries author exclusion"]
               else
                  ["permit", "the grant holds \($a) at level \($d.level)"]
               end) as [$v, $why]
            | "\($s)\t\($v)\t\($why)"' "$T/check.json" > "$T/grant"
    fi
fi

rank() { case "$1" in permit) echo 0 ;; unread) echo 1 ;; confirm) echo 2 ;; deny) echo 3 ;; *) echo 9 ;; esac; }

TOKEN_WORD=readable
TOKEN=
STEPS_JSON='{}'
for step in $STEPS; do
    v= why= src=workspace gv= gwhy=
    IFS='	' read -r _ gv gwhy <<GRANT
$(grep "^$step	" "$T/grant")
GRANT
    if [ "$ALL_UNREAD" = 1 ] && [ -z "$IROOT$WROOT" ]; then
        v=unread; why="no niwa instance or workspace root found"
    elif [ "$GRANT_STATE" = record-unusable ] && { [ "$step" = merge ] || [ "$step" = release ]; }; then
        v=deny; why="niwa authority check: the session's dispatch record is unusable"; src=grant
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
            elif [ -n "$gv" ]; then
                # The grant stands where the hook's text would be read, an
                # unreadable hook's included: the workspace gate decides a
                # bound session's merge, close and release by the same answer,
                # so the hook's text no longer says what it decides.
                :
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
        # The stricter of the permission reading and the grant's answer. The
        # grant is the step's source when its answer stands (a tie included);
        # a stricter rule or defaultMode keeps the step the workspace's.
        if [ -n "$gv" ] && [ "$(rank "$gv")" -ge "$(rank "$v")" ]; then
            v=$gv; why=$gwhy; src=grant
        fi
    fi
    [ "$v" = unread ] && [ "$step" != release ] && TOKEN_WORD=unread
    TOKEN="$TOKEN $step:$v"
    STEPS_JSON=$(printf '%s' "$STEPS_JSON" | jq -c --arg s "$step" --arg v "$v" --arg w "$why" --arg src "$src" \
        '.[$s] = {verdict: $v, why: $w, source: $src}')
done
TOKEN="$TOKEN_WORD$TOKEN"

jq -n --arg t "$TOKEN" --arg i "$IROOT" --arg w "$WROOT" --arg m "$MODE" --argjson f "$FILES_JSON" --argjson s "$STEPS_JSON" \
    --argjson g "$CHECK_JSON" \
    '{token: $t, instance_root: $i, workspace_root: $w, default_mode: $m, files: $f, steps: $s, grant_check: $g}' > "$T/detail.json"
lib_emit start_posture "$TOKEN" coord/posture.json "$T/detail.json"
