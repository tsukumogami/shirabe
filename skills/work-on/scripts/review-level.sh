#!/usr/bin/env bash
# review-level.sh -- for /work-on: choose, raise, lower, check and report a
# run's review level.
#
# A run's review level (light, standard or full; references/review-levels.md
# defines them) lives in the rebindable template variable REVIEW_LEVEL, which
# koto routes on, and in a per-run ledger, the context key
# `review_level.jsonl`. This script is the one way the level changes: `set`
# rebinds the variable and appends to the ledger in the same call, so the two
# agree after every exit. The facts of the change (its size, the path classes
# it touched, whether tests or acceptance criteria changed) set a floor the
# level can't sit below; references/review-level-rules.tsv holds the rules.
#
# Usage:
#   review-level.sh init   <session> <floor> <ceiling>
#   review-level.sh set    <session> <level> [--reason <text>] [--cause veto:<criterion>]
#   review-level.sh facts  <session> [<level>]
#   review-level.sh check  <session> <level>
#   review-level.sh slice  <session> <level>
#   review-level.sh report [<session>...]
#
# <floor>, <ceiling> and the <level> of facts/check/slice may be empty (an
# unset template variable); <level> for set must be one of the three names.
#
#   init    run by the level-choice state's action. Stores the bound in
#           `review_level_bound.json`, the acceptance-criteria text in
#           `review_level_criteria.txt` and a copy of the rules file in
#           `review_level_rules.tsv`, then appends one `bound` line. A second
#           run finds the `bound` line and writes nothing.
#   set     run by the agent. Decides the event from the ledger's last level,
#           the bound and the recorded facts:
#             no level yet  choose; refused outside the bound, or under a bound
#                           whose floor is above its ceiling
#             higher        floor_raise when the new level is the facts floor
#                           and the current level is below it; veto with
#                           --cause veto:<c>; raise otherwise. Above the
#                           ceiling a floor_raise passes and adds `breach`;
#                           any other raise needs --reason and adds `breach`
#             lower         needs --reason; refused below the facts floor or
#                           the bound floor
#             same          no event; the variable is rebound to it, which
#                           clears a hand rebind's mismatch hold
#           Then it rebinds REVIEW_LEVEL with `koto init <s> --template
#           <template> --attach-live --var REVIEW_LEVEL=<level>`, appends the
#           ledger lines and reads them back. A failed rebind writes no line; a
#           failed ledger write rebinds back to the ledger's level.
#   facts   run by the level-check state's action. Diffs impl_base..HEAD,
#           classifies every path (both sides of a rename) with the stored
#           rules copy, writes `review_facts.json`, and appends a `check` line
#           when the head, level or floor differs from the last one, or an
#           `unset` line when the level is empty.
#   check   the level-check gate. Read-only.
#   slice   the decider check's command: a fixed projection of the facts
#           (counts, class names, booleans, the floor) and a `level:` line.
#           Never a path, a reason or criteria text.
#   report  one tab-separated row per /work-on session, after a header:
#           session chosen final floor ceiling raises lowers floor_raises
#           vetoes breaches overrides seats. With no session named, every
#           session `koto workflows` lists whose template is named work-on.
#
# The acceptance-criteria text is the session's `context.md` section headed
# "Acceptance Criteria" or "Done when" (a markdown heading or a bold label),
# or the whole of `context.md` when it has no such section.
#
# Environment (tests only):
#   REVIEW_LEVEL_TEMPLATE  the template `set` attaches with; default
#                          ../koto-templates/work-on.md beside this script.
#                          koto refuses an attach whose template hash differs
#                          from the session's, so a wrong path fails closed.
#   REVIEW_LEVEL_RULES     the rules file `init` copies; default
#                          ../references/review-level-rules.tsv.
#
# Exit codes:
#   0  -- done: init stored (or already had) the bound; set recorded the
#         change; facts recorded; check passes; slice and report printed
#   1  -- set refused (a `refused:` line on stdout names the rule; nothing
#         changed), or check holds (a `hold:` line names why)
#   2  -- report printed every row, but a ledger had a line that isn't JSON
#   3  -- check: the level is empty (the unset route)
#   64 -- usage: unknown subcommand, a bad level, session name, flag or rules
#         file, or no git base to diff
#   66 -- a koto write failed: the rebind, or a context write. After set
#         exits 66 neither the variable nor the ledger has changed
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="${REVIEW_LEVEL_TEMPLATE:-$SKILL_DIR/koto-templates/work-on.md}"
RULES_SHIPPED="${REVIEW_LEVEL_RULES:-$SKILL_DIR/references/review-level-rules.tsv}"

LEDGER=review_level.jsonl
BOUND_KEY=review_level_bound.json
CRITERIA_KEY=review_level_criteria.txt
RULES_KEY=review_level_rules.tsv
FACTS_KEY=review_facts.json
REASON_MAX=200

WORK=$(mktemp -d) || { echo "review-level: could not create a temporary directory" >&2; exit 66; }
trap 'rm -rf "$WORK"' EXIT

die() {
    # $1 exit code, $2 message
    echo "review-level: $2" >&2
    exit "$1"
}

usage() {
    die 64 "$1
usage: review-level.sh init   <session> <floor> <ceiling>
       review-level.sh set    <session> <level> [--reason <text>] [--cause veto:<criterion>]
       review-level.sh facts  <session> [<level>]
       review-level.sh check  <session> <level>
       review-level.sh slice  <session> <level>
       review-level.sh report [<session>...]"
}

# rank <level>: 1 light, 2 standard, 3 full, 0 empty or unknown.
rank() {
    case "$1" in
        light) echo 1 ;;
        standard) echo 2 ;;
        full) echo 3 ;;
        *) echo 0 ;;
    esac
}

valid_level() {
    case "$1" in light|standard|full) return 0 ;; esac
    return 1
}

# level_or_empty <value> <what>: dies 64 unless empty or a level name.
level_or_empty() {
    [ -z "$1" ] || valid_level "$1" || usage "$2 [$1] is not light, standard or full"
}

valid_session() {
    case "$1" in
        ""|-*|*[!A-Za-z0-9._-]*) return 1 ;;
    esac
    return 0
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ctx_get <session> <key> <file>: the key's content into <file>, empty when the
# key is absent. Returns 1 when the key exists but can't be read.
ctx_get() {
    : > "$3"
    if koto context exists "$1" "$2"; then
        koto context get "$1" "$2" > "$3" || return 1
    fi
    return 0
}

# ctx_put <session> <key> <file>: writes the key from <file> and reads it back.
ctx_put() {
    koto context add "$1" "$2" < "$3" >/dev/null || return 1
    koto context get "$1" "$2" > "$WORK/readback" || return 1
    cmp -s "$3" "$WORK/readback"
}

# line <event> [<key> <value>]...: one compact JSON ledger line. A pair whose
# value is empty is left out.
line() {
    jq -nc --arg ts "$(now)" --arg event "$1" '
        reduce range(0; $ARGS.positional | length; 2) as $i
            ({ts: $ts, event: $event};
             if $ARGS.positional[$i + 1] == "" then .
             else . + {($ARGS.positional[$i]): $ARGS.positional[$i + 1]} end)
    ' --args "${@:2}"
}

# The ledger's level events, read leniently: a line that isn't JSON is skipped
# here (report is what flags it).
LEVEL_EVENTS='["choose","raise","lower","floor_raise","veto"]'

# last_level <ledger-file>: the `to` of the ledger's last level event.
last_level() {
    jq -Rr --argjson ev "$LEVEL_EVENTS" '
        fromjson? | select(type == "object") | select(.event as $e | $ev | index($e)) | .to // ""
    ' "$1" | tail -n 1
}

# has_event <ledger-file> <event> [<to>]: 0 when the ledger has that event
# (with that `to`, when given).
has_event() {
    jq -Rne --arg e "$2" --arg to "${3:-}" '
        [inputs | fromjson? | select(type == "object" and .event == $e and ($to == "" or .to == $to))]
        | length > 0
    ' "$1" >/dev/null
}

# ---------------------------------------------------------------- rules -------

NCLASS=0
NRULE=0
# CLASS_NAME[i] CLASS_GLOB[i]; RULE_LEVEL[i] RULE_FACT[i].

# load_rules <file>: parses and validates; dies 64 on anything it doesn't know.
load_rules() {
    local file="$1" n=0 type a b rest i j found name
    [ -f "$file" ] || die 64 "rules file [$file] is not a file"
    NCLASS=0
    NRULE=0
    while IFS=$'\t' read -r type a b rest || [ -n "$type" ]; do
        n=$((n + 1))
        case "$type" in
            ""|"#"*) continue ;;
            class)
                case "$a" in ""|*[!a-z0-9_]*) die 64 "rules line $n: bad class name [$a]" ;; esac
                [ -n "$b" ] || die 64 "rules line $n: class [$a] has no glob"
                CLASS_NAME[$NCLASS]="$a"
                CLASS_GLOB[$NCLASS]="$b"
                NCLASS=$((NCLASS + 1))
                ;;
            rule)
                valid_level "$a" || die 64 "rules line $n: unknown level [$a]"
                case "$b" in
                    class:*) ;;
                    lines\>*|files\>*)
                        case "${b#*>}" in ""|*[!0-9]*) die 64 "rules line $n: bad threshold in [$b]" ;; esac
                        ;;
                    tests_changed|criteria_changed) ;;
                    *) die 64 "rules line $n: unknown fact [$b]" ;;
                esac
                RULE_LEVEL[$NRULE]="$a"
                RULE_FACT[$NRULE]="$b"
                NRULE=$((NRULE + 1))
                ;;
            *) die 64 "rules line $n: unknown record type [$type]" ;;
        esac
    done < "$file"
    i=0
    while [ "$i" -lt "$NRULE" ]; do
        case "${RULE_FACT[$i]}" in
            class:*)
                name="${RULE_FACT[$i]#class:}"
                found=0
                j=0
                while [ "$j" -lt "$NCLASS" ]; do
                    [ "${CLASS_NAME[$j]}" = "$name" ] && found=1
                    j=$((j + 1))
                done
                [ "$found" -eq 1 ] || die 64 "rules: rule [${RULE_FACT[$i]}] names a class no class line defines"
                ;;
        esac
        i=$((i + 1))
    done
}

# glob_match <path> <glob>: bash case matching; a leading `**/` also matches
# no directory at all.
glob_match() {
    # shellcheck disable=SC2254
    case "$1" in $2) return 0 ;; esac
    case "$2" in
        '**/'*)
            # shellcheck disable=SC2254
            case "$1" in ${2#\*\*/}) return 0 ;; esac
            ;;
    esac
    return 1
}

# ------------------------------------------------------------ criteria --------

# criteria_text <context.md file>: the acceptance-criteria section, or the whole
# file when it has none.
criteria_text() {
    awk '
        function is_ac(s) {
            s = tolower(s)
            return s ~ /^#+[ \t]+(acceptance criteria|done when)/ \
                || s ~ /^\*\*(acceptance criteria|done when)/
        }
        function is_heading(s) { return s ~ /^#+[ \t]/ || s ~ /^\*\*[^*]+\*\*/ }
        { all[NR] = $0 }
        inside && is_heading($0) { inside = 0; done = 1 }
        !done && !inside && is_ac($0) { inside = 1; found = 1; print; next }
        inside { print }
        END {
            if (!found) for (i = 1; i <= NR; i++) print all[i]
        }
    ' "$1"
}

session_criteria() {
    # $1 session, $2 output file
    ctx_get "$1" context.md "$WORK/context.md" || return 1
    criteria_text "$WORK/context.md" > "$2"
}

# ---------------------------------------------------------------- init --------

cmd_init() {
    [ $# -eq 3 ] || usage "init takes <session> <floor> <ceiling>"
    local s="$1" floor="$2" ceiling="$3"
    valid_session "$s" || usage "bad session name [$s]"
    level_or_empty "$floor" floor
    level_or_empty "$ceiling" ceiling

    ctx_get "$s" "$LEDGER" "$WORK/ledger" || die 66 "could not read $LEDGER"
    if has_event "$WORK/ledger" bound; then
        exit 0
    fi
    load_rules "$RULES_SHIPPED"

    jq -nc --arg f "$floor" --arg c "$ceiling" \
        '{floor: (if $f == "" then null else $f end), ceiling: (if $c == "" then null else $c end)}' \
        > "$WORK/bound"
    session_criteria "$s" "$WORK/criteria" || die 66 "could not read context.md"
    ctx_put "$s" "$BOUND_KEY" "$WORK/bound" || die 66 "could not write $BOUND_KEY"
    ctx_put "$s" "$CRITERIA_KEY" "$WORK/criteria" || die 66 "could not write $CRITERIA_KEY"
    ctx_put "$s" "$RULES_KEY" "$RULES_SHIPPED" || die 66 "could not write $RULES_KEY"

    # The bound line goes last: its presence is what says init finished.
    jq -nc --arg ts "$(now)" --slurpfile b "$WORK/bound" '{ts: $ts, event: "bound"} + $b[0]' > "$WORK/new"
    cat "$WORK/ledger" "$WORK/new" > "$WORK/ledger.next"
    ctx_put "$s" "$LEDGER" "$WORK/ledger.next" || die 66 "could not write $LEDGER"
    exit 0
}

# ---------------------------------------------------------------- set ---------

REBIND_ERR=""
# rebind <session> <level>: 0 when koto reports the variable at <level>.
rebind() {
    local reply
    reply=$(koto init "$1" --template "$TEMPLATE" --attach-live --var "REVIEW_LEVEL=$2" 2>"$WORK/rebind.err")
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        REBIND_ERR="koto init --attach-live exited $rc: $(printf '%s' "$reply" | head -c 400) $(head -c 400 "$WORK/rebind.err")"
        return 1
    fi
    if printf '%s' "$reply" | jq -e --arg l "$2" \
        '.outcome == "attached"
         and (((.rebound // {}) | has("REVIEW_LEVEL") | not) or .rebound.REVIEW_LEVEL == $l)' \
        >/dev/null; then
        return 0
    fi
    REBIND_ERR="koto did not report REVIEW_LEVEL rebound to [$2]: $(printf '%s' "$reply" | head -c 400)"
    return 1
}

refuse() {
    echo "refused: $1"
    exit 1
}

cmd_set() {
    [ $# -ge 2 ] || usage "set takes <session> <level>"
    local s="$1" new="$2" reason="" cause="" has_reason=0
    shift 2
    valid_session "$s" || usage "bad session name [$s]"
    valid_level "$new" || usage "level [$new] is not light, standard or full"
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason) [ $# -ge 2 ] || usage "--reason needs a value"; reason="$2"; has_reason=1; shift 2 ;;
            --reason=*) reason="${1#--reason=}"; has_reason=1; shift ;;
            --cause) [ $# -ge 2 ] || usage "--cause needs a value"; cause="$2"; shift 2 ;;
            --cause=*) cause="${1#--cause=}"; shift ;;
            *) usage "unknown argument [$1]" ;;
        esac
    done
    if [ -n "$cause" ]; then
        case "$cause" in
            veto:*) case "${cause#veto:}" in ""|*[!A-Za-z0-9._-]*) usage "bad --cause [$cause]" ;; esac ;;
            *) usage "--cause must be veto:<criterion>" ;;
        esac
    fi
    # Control characters become spaces; the text is cut to REASON_MAX.
    if [ "$has_reason" -eq 1 ]; then
        reason=$(printf '%s' "$reason" | LC_ALL=C tr '\000-\037\177' ' ')
        reason="${reason:0:$REASON_MAX}"
        case "$reason" in *[![:space:]]*) ;; *) reason="" ;; esac
    fi

    ctx_get "$s" "$LEDGER" "$WORK/ledger" || die 66 "could not read $LEDGER"
    has_event "$WORK/ledger" bound || refuse "no bound recorded yet"
    ctx_get "$s" "$BOUND_KEY" "$WORK/bound" || die 66 "could not read $BOUND_KEY"
    local bfloor bceil
    bfloor=$(jq -r '.floor // ""' "$WORK/bound")
    bceil=$(jq -r '.ceiling // ""' "$WORK/bound")
    ctx_get "$s" "$FACTS_KEY" "$WORK/facts" || die 66 "could not read $FACTS_KEY"
    local ffloor="" frule=""
    if [ -s "$WORK/facts" ]; then
        ffloor=$(jq -r '.floor // ""' "$WORK/facts")
        frule=$(jq -r '.rule // ""' "$WORK/facts")
    fi
    local cur
    cur=$(last_level "$WORK/ledger")

    local r_new r_cur r_bf r_bc r_ff
    r_new=$(rank "$new"); r_cur=$(rank "$cur"); r_bf=$(rank "$bfloor")
    r_bc=$(rank "$bceil"); r_ff=$(rank "$ffloor")

    if [ -n "$bfloor" ] && [ -n "$bceil" ] && [ "$r_bf" -gt "$r_bc" ]; then
        refuse "the bound's floor $bfloor is above its ceiling $bceil"
    fi

    local event="" breach=0 rule=""
    if [ -z "$cur" ]; then
        [ -z "$cause" ] || usage "--cause applies to a raise, and no level is recorded yet"
        if [ -n "$bfloor" ] && [ "$r_new" -lt "$r_bf" ]; then
            refuse "$new is below the bound's floor $bfloor (bound: floor ${bfloor:--}, ceiling ${bceil:--})"
        fi
        if [ -n "$bceil" ] && [ "$r_new" -gt "$r_bc" ]; then
            refuse "$new is above the bound's ceiling $bceil (bound: floor ${bfloor:--}, ceiling ${bceil:--})"
        fi
        event=choose
    elif [ "$r_new" -gt "$r_cur" ]; then
        if [ -n "$ffloor" ] && [ "$new" = "$ffloor" ] && [ "$r_cur" -lt "$r_ff" ]; then
            event=floor_raise
            rule="$frule"
        elif [ -n "$cause" ]; then
            event=veto
            rule="${cause#veto:}"
        else
            event=raise
        fi
        if [ -n "$bceil" ] && [ "$r_new" -gt "$r_bc" ]; then
            if [ "$event" != floor_raise ] && [ -z "$reason" ]; then
                refuse "$new is above the ceiling $bceil; a raise past it needs --reason"
            fi
            breach=1
        fi
    elif [ "$r_new" -lt "$r_cur" ]; then
        [ -z "$cause" ] || usage "--cause applies to a raise"
        [ -n "$reason" ] || refuse "lowering $cur to $new needs --reason"
        if [ -n "$ffloor" ] && [ "$r_new" -lt "$r_ff" ]; then
            refuse "$new is below the facts floor $ffloor${frule:+ (rule $frule)}"
        fi
        if [ -n "$bfloor" ] && [ "$r_new" -lt "$r_bf" ]; then
            refuse "$new is below the bound's floor $bfloor"
        fi
        event=lower
    else
        [ -z "$cause" ] || usage "--cause applies to a raise"
        rebind "$s" "$new" || die 66 "rebind failed, nothing recorded: $REBIND_ERR"
        echo "unchanged: $new (REVIEW_LEVEL rebound to the ledger's level)"
        exit 0
    fi

    rebind "$s" "$new" || die 66 "rebind failed, nothing recorded: $REBIND_ERR"

    {
        line "$event" from "$cur" to "$new" reason "$reason" rule "$rule"
        [ "$breach" -eq 0 ] || line breach from "$cur" to "$new" ceiling "$bceil" reason "$reason" rule "$rule"
    } > "$WORK/new" || {
        rebind "$s" "$cur" || echo "review-level: rebinding back to [$cur] also failed: $REBIND_ERR" >&2
        die 66 "could not build the ledger line"
    }
    cat "$WORK/ledger" "$WORK/new" > "$WORK/ledger.next"
    if ! ctx_put "$s" "$LEDGER" "$WORK/ledger.next"; then
        # Put back what was there, then the variable, so the two still agree.
        koto context add "$s" "$LEDGER" < "$WORK/ledger" >/dev/null || true
        rebind "$s" "$cur" || echo "review-level: rebinding back to [$cur] also failed: $REBIND_ERR" >&2
        die 66 "could not write $LEDGER; REVIEW_LEVEL rebound back to [${cur:-unset}]"
    fi
    echo "recorded: $event ${cur:--} -> $new"
    [ "$breach" -eq 0 ] || echo "recorded: breach of ceiling $bceil"
    exit 0
}

# ---------------------------------------------------------------- facts -------

resolve_base() {
    # $1 session. Prints the base commit; 1 when none resolves.
    local stored="" ref=""
    if ctx_get "$1" impl_base "$WORK/impl_base"; then
        stored=$(tr -d '[:space:]' < "$WORK/impl_base")
    fi
    if [ -n "$stored" ] && git rev-parse --verify -q "${stored}^{commit}"; then
        return 0
    fi
    ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD)
    if [ -z "$ref" ] && git rev-parse --verify -q "refs/remotes/origin/main^{commit}" >/dev/null; then
        ref=origin/main
    fi
    if [ -n "$ref" ] && git merge-base HEAD "$ref"; then
        return 0
    fi
    if git rev-parse --verify -q "refs/heads/main^{commit}" >/dev/null && git merge-base HEAD main; then
        return 0
    fi
    return 1
}

cmd_facts() {
    [ $# -ge 1 ] && [ $# -le 2 ] || usage "facts takes <session> [<level>]"
    local s="$1" level="${2:-}"
    valid_session "$s" || usage "bad session name [$s]"
    level_or_empty "$level" level
    git rev-parse --git-dir >/dev/null || die 64 "not inside a git repository"
    local head base
    head=$(git rev-parse --verify -q "HEAD^{commit}") || die 64 "HEAD does not name a commit"
    base=$(resolve_base "$s") || die 64 "no base resolves: impl_base is unset and no merge-base with origin's default branch or main"

    # The stored copy, never the working tree's: a diff that edits the rules
    # can't change its own floor. A session init never ran for falls back to
    # the shipped file.
    ctx_get "$s" "$RULES_KEY" "$WORK/rules" || die 66 "could not read $RULES_KEY"
    if [ -s "$WORK/rules" ]; then
        load_rules "$WORK/rules"
    else
        load_rules "$RULES_SHIPPED"
    fi

    git diff -z --numstat -M "$base" HEAD > "$WORK/numstat" || die 64 "git diff $base HEAD failed"

    # numstat -z: "<add>\t<del>\t<path>\0", or for a rename
    # "<add>\t<del>\t\0<old>\0<new>\0". Binary files count "-" as 0 lines.
    local lines=0 files=0 rec add del p p2
    : > "$WORK/paths"
    while IFS= read -r -d '' rec; do
        add="${rec%%$'\t'*}"
        rec="${rec#*$'\t'}"
        del="${rec%%$'\t'*}"
        p="${rec#*$'\t'}"
        case "$add" in ""|*[!0-9]*) add=0 ;; esac
        case "$del" in ""|*[!0-9]*) del=0 ;; esac
        lines=$((lines + add + del))
        files=$((files + 1))
        if [ -z "$p" ]; then
            IFS= read -r -d '' p || break
            IFS= read -r -d '' p2 || break
            printf '%s\0%s\0' "$p" "$p2" >> "$WORK/paths"
        else
            printf '%s\0' "$p" >> "$WORK/paths"
        fi
    done < "$WORK/numstat"

    # Classes, in the rules file's order, each once.
    local i hit=""
    : > "$WORK/classes"
    i=0
    while [ "$i" -lt "$NCLASS" ]; do
        case " $hit " in
            *" ${CLASS_NAME[$i]} "*) ;;
            *)
                while IFS= read -r -d '' p; do
                    if glob_match "$p" "${CLASS_GLOB[$i]}"; then
                        hit="$hit ${CLASS_NAME[$i]}"
                        echo "${CLASS_NAME[$i]}" >> "$WORK/classes"
                        break
                    fi
                done < "$WORK/paths"
                ;;
        esac
        i=$((i + 1))
    done

    local tests_changed=false criteria_changed=false
    case " $hit " in *" test "*) tests_changed=true ;; esac
    while IFS= read -r -d '' p; do
        case "$p" in docs/plans/*|docs/prds/*) criteria_changed=true ;; esac
    done < "$WORK/paths"
    if [ "$criteria_changed" = false ] && koto context exists "$s" "$CRITERIA_KEY"; then
        ctx_get "$s" "$CRITERIA_KEY" "$WORK/criteria.stored" || die 66 "could not read $CRITERIA_KEY"
        session_criteria "$s" "$WORK/criteria.now" || die 66 "could not read context.md"
        cmp -s "$WORK/criteria.stored" "$WORK/criteria.now" || criteria_changed=true
    fi

    # The floor: the highest level any rule yields. rule names the first rule
    # that yielded it.
    local floor=light frank=1 rule="" fired=0 fact n r
    : > "$WORK/fired"
    i=0
    while [ "$i" -lt "$NRULE" ]; do
        fact="${RULE_FACT[$i]}"
        fired=0
        case "$fact" in
            class:*) case " $hit " in *" ${fact#class:} "*) fired=1 ;; esac ;;
            lines\>*) n="${fact#*>}"; [ "$lines" -gt "$n" ] && fired=1 ;;
            files\>*) n="${fact#*>}"; [ "$files" -gt "$n" ] && fired=1 ;;
            tests_changed) [ "$tests_changed" = true ] && fired=1 ;;
            criteria_changed) [ "$criteria_changed" = true ] && fired=1 ;;
        esac
        if [ "$fired" -eq 1 ]; then
            echo "${RULE_LEVEL[$i]}:$fact" >> "$WORK/fired"
            r=$(rank "${RULE_LEVEL[$i]}")
            if [ "$r" -gt "$frank" ]; then
                frank="$r"
                floor="${RULE_LEVEL[$i]}"
                rule="$fact"
            fi
        fi
        i=$((i + 1))
    done

    jq -n \
        --argjson lines "$lines" --argjson files "$files" \
        --argjson tests_changed "$tests_changed" --argjson criteria_changed "$criteria_changed" \
        --arg floor "$floor" --arg rule "$rule" --arg head "$head" --arg base "$base" \
        --rawfile classes "$WORK/classes" --rawfile fired "$WORK/fired" '
        {lines: $lines, files: $files,
         classes: ($classes | split("\n") | map(select(length > 0))),
         tests_changed: $tests_changed, criteria_changed: $criteria_changed,
         floor: $floor, rule: (if $rule == "" then null else $rule end),
         rules_fired: ($fired | split("\n") | map(select(length > 0))),
         head: $head, base: $base}
    ' > "$WORK/facts.json" || die 66 "could not build $FACTS_KEY"
    ctx_put "$s" "$FACTS_KEY" "$WORK/facts.json" || die 66 "could not write $FACTS_KEY"

    ctx_get "$s" "$LEDGER" "$WORK/ledger" || die 66 "could not read $LEDGER"
    local last
    last=$(jq -Rr 'fromjson? | select(type == "object" and (.event == "check" or .event == "unset"))
                   | "\(.head // "")|\(.level // "")|\(.floor // "")"' "$WORK/ledger" | tail -n 1)
    if [ "$last" != "$head|$level|$floor" ]; then
        if [ -z "$level" ]; then
            line unset floor "$floor" rule "$rule" head "$head" > "$WORK/new"
        else
            line check level "$level" floor "$floor" rule "$rule" head "$head" > "$WORK/new"
        fi
        cat "$WORK/ledger" "$WORK/new" > "$WORK/ledger.next"
        ctx_put "$s" "$LEDGER" "$WORK/ledger.next" || die 66 "could not write $LEDGER"
    fi
    exit 0
}

# ---------------------------------------------------------------- check -------

hold() {
    echo "hold: $1"
    exit 1
}

cmd_check() {
    [ $# -eq 2 ] || { echo "hold: check takes <session> <level>"; exit 1; }
    local s="$1" level="$2"
    valid_session "$s" || hold "bad session name [$s]"
    [ -n "$level" ] || exit 3
    valid_level "$level" || hold "REVIEW_LEVEL [$level] is not light, standard or full"

    ctx_get "$s" "$LEDGER" "$WORK/ledger" || hold "could not read $LEDGER"
    local recorded
    recorded=$(last_level "$WORK/ledger")
    if [ "$recorded" != "$level" ]; then
        hold "REVIEW_LEVEL is $level but the ledger's last level is ${recorded:-none}; run review-level.sh set $s <level> to record the level the run should be at"
    fi
    ctx_get "$s" "$FACTS_KEY" "$WORK/facts" || hold "could not read $FACTS_KEY"
    [ -s "$WORK/facts" ] || hold "no facts recorded yet; the next tick's action gathers them"
    local head fhead floor rule
    head=$(git rev-parse --verify -q "HEAD^{commit}") || hold "HEAD does not name a commit"
    fhead=$(jq -r '.head // ""' "$WORK/facts")
    [ "$fhead" = "$head" ] || hold "the facts were gathered at ${fhead:-no head}, not HEAD $head; the next tick re-gathers them"
    floor=$(jq -r '.floor // "light"' "$WORK/facts")
    rule=$(jq -r '.rule // "-"' "$WORK/facts")
    if [ "$(rank "$level")" -lt "$(rank "$floor")" ]; then
        hold "level $level is below the facts floor $floor (rule $rule); raise it with review-level.sh set $s $floor"
    fi

    ctx_get "$s" "$BOUND_KEY" "$WORK/bound" || hold "could not read $BOUND_KEY"
    local bfloor bceil
    bfloor=$(jq -r '.floor // ""' "$WORK/bound")
    bceil=$(jq -r '.ceiling // ""' "$WORK/bound")
    if [ -n "$bfloor" ] && [ "$(rank "$level")" -lt "$(rank "$bfloor")" ]; then
        hold "level $level is below the bound's floor $bfloor"
    fi
    if [ -n "$bceil" ] && [ "$(rank "$level")" -gt "$(rank "$bceil")" ]; then
        has_event "$WORK/ledger" breach "$level" \
            || hold "level $level is above the bound's ceiling $bceil with no breach recorded"
    fi
    echo "pass: level $level, facts floor $floor"
    exit 0
}

# ---------------------------------------------------------------- slice -------

cmd_slice() {
    local s="${1:-}" level="${2:-}"
    valid_level "$level" || level=unset
    if valid_session "$s" && ctx_get "$s" "$FACTS_KEY" "$WORK/facts" && [ -s "$WORK/facts" ]; then
        jq -c '{lines: (.lines // 0), files: (.files // 0),
                classes: ([.classes[]? | strings | select(test("^[a-z0-9_]+$"))]),
                tests_changed: (.tests_changed == true), criteria_changed: (.criteria_changed == true),
                floor: (.floor | if . == "light" or . == "standard" or . == "full" then . else "unknown" end)}' \
            "$WORK/facts" || echo '{}'
    else
        echo '{}'
    fi
    echo "level: $level"
    exit 0
}

# ---------------------------------------------------------------- report ------

# The row, built in jq so every field is escaped the same way: backslash, tab,
# newline and carriage return as \\ \t \n \r, any other control character as
# \xHH.
REPORT_JQ='
def hex2: [(. / 16 | floor), (. % 16)] | map("0123456789abcdef"[.:. + 1]) | add;
def esc: tostring
    | gsub("\\\\"; "\\\\") | gsub("\t"; "\\t") | gsub("\n"; "\\n") | gsub("\r"; "\\r")
    | gsub("(?<c>[\\x00-\\x1f\\x7f])"; "\\x" + (.c | explode[0] | hex2));
def rank: if . == "light" then 1 elif . == "standard" then 2 elif . == "full" then 3 else 0 end;
($ledger | split("\n") | map(select(length > 0)) | map(try fromjson catch null)) as $lines
| ($lines | map(select(type == "object"))) as $ev
| (if $has_ledger == "0" then "none"
   elif ($lines | any(type != "object")) then "corrupt"
   else ([$ev[] | select(.event == "choose") | .to][0] // "-") end) as $chosen
| ([$ev[] | select(.event == "bound")] | last // {}) as $bound
| ([$ev[] | select(.event == "check" and ((.level | rank) >= (.floor | rank)) and ((.level | rank) > 0))] | last | .level // "-") as $final
| def count($e): [$ev[] | select(.event == $e)] | length;
[$session, $chosen, $final, ($bound.floor // "-"), ($bound.ceiling // "-"),
 count("raise"), count("lower"), count("floor_raise"), count("veto"), count("breach"),
 $overrides, $seats]
| map(esc) | join("\t")
'

cmd_report() {
    local s rc=0
    : > "$WORK/names"
    if [ $# -gt 0 ]; then
        for s in "$@"; do
            valid_session "$s" || usage "bad session name [$s]"
            echo "$s" >> "$WORK/names"
        done
    else
        koto workflows | jq -r '.[]?.name // empty' > "$WORK/all" || true
        while IFS= read -r s; do
            valid_session "$s" || continue
            local tpath
            tpath=$(koto status "$s" | jq -r '.template_path // empty')
            [ -n "$tpath" ] && [ -f "$tpath" ] || continue
            [ "$(jq -r '.name // empty' "$tpath")" = work-on ] || continue
            echo "$s" >> "$WORK/names"
        done < "$WORK/all"
    fi

    printf 'session\tchosen\tfinal\tfloor\tceiling\traises\tlowers\tfloor_raises\tvetoes\tbreaches\toverrides\tseats\n'
    while IFS= read -r s; do
        local has=0 overrides seats
        : > "$WORK/ledger"
        if koto context exists "$s" "$LEDGER"; then
            has=1
            koto context get "$s" "$LEDGER" > "$WORK/ledger" || has=0
        fi
        overrides=$(koto overrides list "$s" \
            | jq -r '[.overrides.items[]? | select(.gate == "level_floor" or .gate == "level_fits_facts")] | length')
        [ -n "$overrides" ] || overrides=-
        seats=0
        if ctx_get "$s" verdict_ledger.json "$WORK/verdicts" && [ -s "$WORK/verdicts" ]; then
            seats=$(jq -r '[.history[]?.spawned // 0 | numbers] | add // 0' "$WORK/verdicts")
            [ -n "$seats" ] || seats=-
        fi
        jq -nr --arg session "$s" --rawfile ledger "$WORK/ledger" --arg has_ledger "$has" \
            --arg overrides "$overrides" --arg seats "$seats" "$REPORT_JQ" \
            || { printf '%s\tcorrupt\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\n' "$s"; rc=2; continue; }
        if [ "$has" -eq 1 ] && ! jq -Rne '[inputs | select(length > 0) | (try fromjson catch null) | type == "object"] | all' \
            "$WORK/ledger" >/dev/null; then
            rc=2
        fi
    done < "$WORK/names"
    exit "$rc"
}

# ---------------------------------------------------------------- main --------

command -v jq >/dev/null || die 64 "jq is required"
SUB="${1:-}"
[ $# -gt 0 ] && shift
case "$SUB" in
    init)   cmd_init "$@" ;;
    set)    cmd_set "$@" ;;
    facts)  cmd_facts "$@" ;;
    check)  cmd_check "$@" ;;
    slice)  cmd_slice "$@" ;;
    report) cmd_report "$@" ;;
    "")     usage "missing subcommand" ;;
    *)      usage "unknown subcommand [$SUB]" ;;
esac
