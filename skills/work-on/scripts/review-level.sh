#!/usr/bin/env bash
# review-level.sh -- for /work-on: set a run's review level from the facts of
# the change, raise or lower it, check it and report it.
#
# A run's review level (light, standard or full; references/review-levels.md
# defines them) lives in the rebindable template variable REVIEW_LEVEL, which
# koto routes on, and in a per-run ledger, the context key
# `review_level.jsonl`. This script is the one way the level changes: `set`
# and `set-from-facts` rebind the variable and append to the ledger in the same
# call, so the two agree after every exit. The facts of the change (its size,
# the path classes it touched, whether tests or acceptance criteria changed)
# set a floor the level can't sit below; references/review-level-rules.tsv
# holds the rules. Nobody chooses a level up front: the level check's action
# runs `facts` and then `set-from-facts`, which puts the level at the facts
# floor, or higher when the agent raised it or the bound's floor says so.
#
# Usage:
#   review-level.sh init   <session> <floor> <ceiling>
#   review-level.sh set    <session> <level> [--reason <text>] [--cause veto:<criterion>]
#   review-level.sh set-from-facts <session>
#   review-level.sh facts  <session> [<level>] [--shared-branch <branch>] [--no-check-line]
#   review-level.sh check  <session> <level>|--ledger
#   review-level.sh agree  <session> <level>
#   review-level.sh slice  <session> <level>|--ledger
#   review-level.sh project <facts-file> <level> [<rules-file>]
#   review-level.sh report [<session>...]
#   review-level.sh level  <session> [--exit]
#   review-level.sh raise  <session> <level> --reason <why>
#   review-level.sh audit  <session>
#   review-level.sh classify <path>...
#
# <floor>, <ceiling> and the <level> of facts/check/agree/slice may be empty (an
# unset template variable); <level> for set must be one of the three names.
#
#   init    run by analysis's action as the run enters analysis, and again
#           by fix_determination's, where it is a no-op unless analysis's
#           failed and was recovered by hand. Stores the bound in
#           `review_level_bound.json`, the acceptance-criteria text in
#           `review_level_criteria.txt` and a copy of the rules file in
#           `review_level_rules.tsv`, then appends one `bound` line. A second
#           run finds the `bound` line and writes nothing, except the
#           criteria copy when the first run found no context.md and one
#           exists now.
#   set     run by the agent, to raise (or, with a reason, lower) the level.
#           Refused until init has recorded the bound, which analysis's
#           action does: a level is set from analysis on. Decides the event from the
#           ledger's last level, the bound and the recorded facts:
#             no level yet  choose; refused below the bound's floor, above
#                           its ceiling without --reason (with one it adds
#                           `breach`), or under a bound whose floor is above
#                           its ceiling. A choose before the level check is a
#                           raise the check keeps
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
#           <template> --attach-live --var REVIEW_LEVEL=<level>` (plus
#           PLUGIN_ROOT, this script's plugin, and UNIT_KIND, the fix-kind
#           ledger's kind once one is recorded, when the template declares
#           them: an attach resets every rebind variable it doesn't pass), appends the
#           ledger lines and reads them back. A failed rebind writes no line; a
#           failed ledger write rebinds back to the ledger's level.
#   set-from-facts
#           the second half of the level check's action, after `facts`. The
#           level is the highest of the facts floor (review_facts.json), the
#           ledger's last level (which carries every raise the agent made,
#           and never drops on its own: only a `set` lower moves it down),
#           every level `raise` recorded, and the bound's floor. When that
#           differs from the ledger's last level it appends one `from_facts`
#           line (from, to, rule, and source: `facts` when the facts floor
#           set it, `bound` when the bound's floor did, `raise` when a kept
#           raise did), plus a `breach` line when the new level is above the
#           bound's ceiling, which only a facts floor above the ceiling can
#           cause; when it is the same, no level line. Either way it appends a
#           `check` line when the head, level or floor differs from the last
#           one, and rebinds REVIEW_LEVEL as `set` does, so the variable
#           matches the ledger from the next tick on. Refused (exit 1, nothing
#           changed) with no bound or no facts recorded, or under a bound
#           whose floor is above its ceiling.
#   facts   run by the level-check state's action. Diffs HEAD against two
#           bases, the stored impl_base and the merge-base with the default
#           branch (origin/HEAD's branch, else origin/main, else main), and
#           keeps the larger diff (more changed lines, then more files; a tie
#           keeps impl_base; with no merge-base, impl_base alone). With a
#           non-empty --shared-branch (the run is a step on a branch its
#           siblings also commit to) the merge-base is never a candidate: the
#           impl_base diff is the only one, so earlier steps' commits don't
#           count, and an unset impl_base exits 64. An empty value is the
#           same as no option. When the default branch was merged in after
#           impl_base (its merge-base with HEAD isn't in impl_base), the
#           impl_base diff is taken from the clean merge of impl_base and
#           that merge-base instead, so what the merge brought in doesn't
#           count, and `bases.merged_default` names the folded-in commit
#           (null otherwise; a merge that conflicts keeps impl_base).
#           Classifies every path (both sides of a rename)
#           with the stored rules copy; a binary file, a rename or copy, a
#           mode or type change and a submodule bump count as `unclassified`
#           (and in `unsized`), since their line counts say nothing about
#           their size. Records `red_test_edited` when a fix's reproducing
#           test or harness file (named in `red_first.json`) changed after the
#           red, and `tests_edited` when a `test`
#           path was edited rather than only added to (scripts/lib/
#           test-classify.sh's test_classify_unit over the winning base, with
#           the red's `red_first.json` for a fix; a classification that fails
#           counts every changed test as edited), writes `review_facts.json`
#           (`base_source` names the base that won, `shared_branch` the
#           branch or "", `cap` the rules file's first cap row and whether it
#           lowered the floor, null with no cap row), appends the same object as one line to
#           `review_facts.jsonl` (every gather, so the size at each visit
#           survives the run; nothing reads it back), and appends a `check`
#           line when the head, level or
#           floor differs from the last one, or an `unset` line when the level
#           is empty. --no-check-line writes neither: the level check's
#           action passes it, and set-from-facts writes the check line at the
#           level it settles on.
#   check   the level-check gate. Read-only. --ledger in place of <level>
#           judges the ledger's last level instead of a variable's: the level
#           set-from-facts recorded in the same tick, which the variable shows
#           only from the next tick. With --ledger a ledger with no level
#           holds; it never exits 3.
#   agree   the ledger-agreement gate on the states after the level check
#           that route on the level (review, light_review). Read-only. Passes
#           when the variable equals the ledger's last level, and when the
#           variable is empty; holds otherwise, naming both, so a hand rebind
#           made after the level check can't change where the run goes. An
#           empty variable passes because the tick that first records a level
#           enters light_review or scrutiny before the rebind shows, and
#           because an empty level takes review's most thorough route (QA),
#           so it can never skip a panel.
#   slice   the decider check's command: a typed projection of the facts
#           (counts, class names, booleans, the floor), the order of the
#           levels, the level definitions rendered from the stored rules
#           copy (what the facts call for at each level, and the floor as
#           the most thorough of them) and a `level:` line. With no facts
#           recorded, the projection is `{}` and the definitions are left
#           out. Never a path, a reason or criteria text. --ledger in place of
#           <level> takes the ledger's last level, as for check.
#   project the same slice for a facts file, for the Jev criteria fixtures
#           and the slice measurement, with the rules file given (a
#           session's stored copy) or else the shipped one.
#   report  one tab-separated row per /work-on session, after a header:
#           session chosen final floor ceiling raises lowers floor_raises
#           vetoes breaches overrides seats. With no session named, every
#           session `koto workflows` lists whose template is named work-on.
#   level   the ledger's last level (the `to` of its last level event), or
#           nothing when the session has no ledger or no level event in it.
#           Read-only. work-on-open.sh passes it as REVIEW_LEVEL when it
#           attaches a live session, because an attach resets every rebind
#           variable it isn't passed. With --exit it is the level check's
#           level_route gate and answers in its exit status, so koto routes on
#           the level set-from-facts recorded in the same tick: 11 light, 12
#           standard, 13 full (10 plus the level's rank), 4 no level
#           recorded, 66 a read that failed.
#   raise   `set` for a move up the run keeps, with a reason: the light seat's
#           escalate (`raise <s> standard --reason escalate`). It records a
#           `raise` line with source `raise` (past the ceiling, a `breach`
#           line too, as `set` does). set-from-facts never settles below the
#           highest such raise and `set` never lowers below it. A level at or
#           below the current one changes nothing (exit 0).
#   audit   exit 0 when the session's name is audited (its SHA-256, read as a
#           number, is 0 mod 10), 1 when it isn't. Read-only, and the same
#           answer on every call. light_review's `audited` gate runs it.
#   classify  one tab-separated row per path: the path, then the classes the
#           shipped rules file puts it in, comma-separated, or `-` for none.
#           Read-only; no session.
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
#   0  -- done: init stored (or already had) the bound; set or raise recorded
#         the change (or raise found the level already there); facts
#         recorded; check passes; slice, report and level printed; audit:
#         the session is audited
#   1  -- set, raise or set-from-facts refused (a `refused:` line on stdout
#         names the rule; nothing changed), check or agree holds (a `hold:`
#         line names why), or audit: the session is not audited
#   2  -- report printed every row, but a ledger had a line that isn't JSON
#         or couldn't be read (koto refused the read, or the get failed)
#   3  -- check: the level is empty and the ledger records none (the unset
#         route, a session from an earlier template). An empty level over a
#         ledger that has one holds (1): the variable was reset
#   4  -- level --exit: the ledger records no level
#   11, 12, 13 -- level --exit: light, standard, full
#   64 -- usage: unknown subcommand, a bad level, session name, flag or rules
#         file, a --shared-branch that isn't a branch name, or no git base to
#         diff (on a shared branch, no impl_base)
#   66 -- a koto call failed: the rebind, or a context read or write (for
#         level, a ledger that exists but can't be read, or a session koto
#         refuses to read, such as one bound to another workspace; nothing
#         is printed on stdout, and koto's reason goes to stderr). A key
#         koto answers is absent is never a failure. After
#         set or set-from-facts exits 66 neither the variable nor the ledger
#         has changed. (check
#         and agree never exit 66: a read they can't make is a hold)
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PLUGIN_ROOT_SELF=$(cd "$SKILL_DIR/../.." && pwd)
TEMPLATE="${REVIEW_LEVEL_TEMPLATE:-$SKILL_DIR/koto-templates/work-on.md}"
RULES_SHIPPED="${REVIEW_LEVEL_RULES:-$SKILL_DIR/references/review-level-rules.tsv}"

LEDGER=review_level.jsonl
BOUND_KEY=review_level_bound.json
CRITERIA_KEY=review_level_criteria.txt
RULES_KEY=review_level_rules.tsv
FACTS_KEY=review_facts.json
# A fix round's record of the run it fixes, and the rule naming that run's floor.
FIX_ROUND_KEY=fix_round.json
FIX_ROUND_RULE=fix_round_parent
FACTS_HISTORY_KEY=review_facts.jsonl
RED_KEY=red_first.json
REASON_MAX=200

# shellcheck source=../../../scripts/lib/test-classify.sh
. "$PLUGIN_ROOT_SELF/scripts/lib/test-classify.sh" \
    || { echo "review-level: cannot load scripts/lib/test-classify.sh" >&2; exit 64; }
# shellcheck source=../../../scripts/lib/default-merge.sh
. "$PLUGIN_ROOT_SELF/scripts/lib/default-merge.sh" \
    || { echo "review-level: cannot load scripts/lib/default-merge.sh" >&2; exit 64; }

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
       review-level.sh set-from-facts <session>
       review-level.sh facts  <session> [<level>] [--shared-branch <branch>] [--no-check-line]
       review-level.sh check  <session> <level>|--ledger
       review-level.sh agree  <session> <level>
       review-level.sh slice  <session> <level>|--ledger
       review-level.sh project <facts-file> <level> [<rules-file>]
       review-level.sh report [<session>...]
       review-level.sh level  <session> [--exit]
       review-level.sh raise  <session> <level> --reason <why>
       review-level.sh audit  <session>
       review-level.sh classify <path>..."
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

# ctx_has <session> <key>: 0 when the key is present, 1 when koto answers that
# it is absent, 2 when the read failed. koto's `context exists` answers an
# absent key with exit 1 and nothing on stdout; a refusal (a session bound to
# another workspace, say) prints its JSON on stdout and exits 2. An exit 1
# that prints anything is a failed read too, never an absent key. Anything
# koto prints goes to stderr, so a refusal never reaches the caller's stdout
# as a value.
ctx_has() {
    local rc=0
    koto context exists "$1" "$2" > "$WORK/exists.out" || rc=$?
    [ -s "$WORK/exists.out" ] && cat "$WORK/exists.out" >&2
    case "$rc" in
        0) return 0 ;;
        1) [ -s "$WORK/exists.out" ] || return 1 ;;
    esac
    echo "review-level: koto context exists $1 $2 exited $rc" >&2
    return 2
}

# ctx_get <session> <key> <file>: the key's content into <file>, empty when the
# key is absent. Returns 1 when the read failed (koto refused it, or the key
# exists but can't be read), with <file> empty and koto's output on stderr.
ctx_get() {
    : > "$3"
    ctx_has "$1" "$2"
    case $? in
        0) ;;
        1) return 0 ;;
        *) return 1 ;;
    esac
    if ! koto context get "$1" "$2" > "$3"; then
        cat "$3" >&2
        : > "$3"
        return 1
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
# value is empty is left out. The -- after --args ends jq's options, so a value
# starting with a dash (a --reason of -r, say) is stored, not read as one.
line() {
    jq -nc --arg ts "$(now)" --arg event "$1" '
        reduce range(0; $ARGS.positional | length; 2) as $i
            ({ts: $ts, event: $event};
             if $ARGS.positional[$i + 1] == "" then .
             else . + {($ARGS.positional[$i]): $ARGS.positional[$i + 1]} end)
    ' --args -- "${@:2}"
}

# The ledger's level events, read leniently: a line that isn't JSON is skipped
# here (report is what flags it).
LEVEL_EVENTS='["choose","raise","lower","floor_raise","veto","from_facts"]'

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
NCAP=0
# CLASS_NAME[i] CLASS_GLOB[i]; RULE_LEVEL[i] RULE_FACT[i]; CAP_LEVEL[i]
# CAP_LINES[i] CAP_FILES[i] CAP_CLASSES[i] (space-separated) CAP_SPEC[i] (the
# row's terms, normalized to "lines<=N files<=M classes=a,b").

# class_defined <name>: 0 when a loaded `class` line defines it.
class_defined() {
    local j=0
    while [ "$j" -lt "$NCLASS" ]; do
        [ "${CLASS_NAME[$j]}" = "$1" ] && return 0
        j=$((j + 1))
    done
    return 1
}

# load_cap <line-number> <level> <terms>: one `cap` row. The terms are
# lines<=N, files<=M and classes=a,b, each exactly once, separated by tabs or
# spaces. A cap lowers a `standard` floor, so its level is `light`; `manifest`
# is never one of its classes, so a dependency change keeps `standard`.
load_cap() {
    local n="$1" level="$2" terms="$3" t lines="" files="" classes=""
    [ "$level" = light ] || die 64 "rules line $n: a cap lowers a standard floor to light, not to [$level]"
    terms=$(printf '%s' "$terms" | tr '\t' ' ')
    for t in $terms; do
        case "$t" in
            lines\<=*)
                [ -z "$lines" ] || die 64 "rules line $n: cap names lines<= twice"
                lines="${t#lines<=}"
                case "$lines" in ""|*[!0-9]*) die 64 "rules line $n: bad bound in [$t]" ;; esac
                ;;
            files\<=*)
                [ -z "$files" ] || die 64 "rules line $n: cap names files<= twice"
                files="${t#files<=}"
                case "$files" in ""|*[!0-9]*) die 64 "rules line $n: bad bound in [$t]" ;; esac
                ;;
            classes=*)
                [ -z "$classes" ] || die 64 "rules line $n: cap names classes= twice"
                classes="${t#classes=}"
                case "$classes" in ""|,*|*,|*,,*|*[!a-z0-9_,]*) die 64 "rules line $n: bad class list in [$t]" ;; esac
                ;;
            *) die 64 "rules line $n: unknown cap term [$t]" ;;
        esac
    done
    [ -n "$lines" ] && [ -n "$files" ] && [ -n "$classes" ] \
        || die 64 "rules line $n: a cap needs lines<=N, files<=M and classes=a,b"
    case ",$classes," in *,manifest,*) die 64 "rules line $n: a cap can't list manifest: a dependency change keeps standard" ;; esac
    CAP_LEVEL[$NCAP]="$level"
    CAP_LINES[$NCAP]="$lines"
    CAP_FILES[$NCAP]="$files"
    CAP_CLASSES[$NCAP]=$(printf '%s' "$classes" | tr ',' ' ')
    CAP_SPEC[$NCAP]="lines<=$lines files<=$files classes=$classes"
    NCAP=$((NCAP + 1))
}

# load_rules <file>: parses and validates; dies 64 on anything it doesn't know.
load_rules() {
    local file="$1" n=0 type a b rest i j found name c
    [ -f "$file" ] || die 64 "rules file [$file] is not a file"
    NCLASS=0
    NRULE=0
    NCAP=0
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
                    tests_changed|tests_edited|red_test_edited|criteria_changed|unclassified) ;;
                    *) die 64 "rules line $n: unknown fact [$b]" ;;
                esac
                RULE_LEVEL[$NRULE]="$a"
                RULE_FACT[$NRULE]="$b"
                NRULE=$((NRULE + 1))
                ;;
            cap)
                load_cap "$n" "$a" "$b${rest:+ $rest}"
                ;;
            *) die 64 "rules line $n: unknown record type [$type]" ;;
        esac
    done < "$file"
    i=0
    while [ "$i" -lt "$NCAP" ]; do
        for c in ${CAP_CLASSES[$i]}; do
            class_defined "$c" || die 64 "rules: cap [${CAP_SPEC[$i]}] names class [$c], which no class line defines"
        done
        i=$((i + 1))
    done
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

# store_criteria <session>: stores the acceptance-criteria copy once, from
# context.md, when no copy is stored yet and context.md exists. With no
# context.md yet it stores nothing, so a later init (fix_determination's,
# after analysis's) stores it once context.md is there, rather than a copy of
# nothing that every later facts call would read as changed criteria.
store_criteria() {
    local rc=0
    ctx_has "$1" "$CRITERIA_KEY" || rc=$?
    case "$rc" in
        0) return 0 ;;
        1) ;;
        *) die 66 "could not read $CRITERIA_KEY" ;;
    esac
    rc=0
    ctx_has "$1" context.md || rc=$?
    case "$rc" in
        0) ;;
        1) return 0 ;;
        *) die 66 "could not read context.md" ;;
    esac
    session_criteria "$1" "$WORK/criteria" || die 66 "could not read context.md"
    ctx_put "$1" "$CRITERIA_KEY" "$WORK/criteria" || die 66 "could not write $CRITERIA_KEY"
}

cmd_init() {
    [ $# -eq 3 ] || usage "init takes <session> <floor> <ceiling>"
    local s="$1" floor="$2" ceiling="$3"
    valid_session "$s" || usage "bad session name [$s]"
    level_or_empty "$floor" floor
    level_or_empty "$ceiling" ceiling

    ctx_get "$s" "$LEDGER" "$WORK/ledger" || die 66 "could not read $LEDGER"
    if has_event "$WORK/ledger" bound; then
        store_criteria "$s"
        exit 0
    fi
    load_rules "$RULES_SHIPPED"

    jq -nc --arg f "$floor" --arg c "$ceiling" \
        '{floor: (if $f == "" then null else $f end), ceiling: (if $c == "" then null else $c end)}' \
        > "$WORK/bound"
    ctx_put "$s" "$BOUND_KEY" "$WORK/bound" || die 66 "could not write $BOUND_KEY"
    store_criteria "$s"
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
#
# An attach re-applies every rebind variable from its own arguments: one it
# omits is reset to its default, and a required one it omits refuses the
# attach. work-on.md's PLUGIN_ROOT is both, so it is passed too, as the plugin
# this script ships in, which is the plugin the session's gates should reach.
# UNIT_KIND is passed as the fix-kind ledger's kind once one is recorded, so a
# level change after fix_determination leaves the fix determination in force
# (fix-kind.sh agree still passes); before then it is left out, as its reset
# value is the empty one fix_determination starts from.
rebind() {
    local reply kind
    set -- "$1" "$2" --var "REVIEW_LEVEL=$2"
    if grep -q '^  PLUGIN_ROOT:' "$TEMPLATE" 2>/dev/null; then
        set -- "$@" --var "PLUGIN_ROOT=$PLUGIN_ROOT_SELF"
    fi
    if grep -q '^  UNIT_KIND:' "$TEMPLATE" 2>/dev/null && [ -x "$SCRIPT_DIR/fix-kind.sh" ]; then
        kind=$("$SCRIPT_DIR/fix-kind.sh" kind "$1" 2>"$WORK/kind.err") || {
            REBIND_ERR="could not read the unit's kind to carry it through the rebind: $(head -c 300 "$WORK/kind.err")"
            return 1
        }
        [ -z "$kind" ] || set -- "$@" --var "UNIT_KIND=$kind"
    fi
    reply=$(koto init "$1" --template "$TEMPLATE" --attach-live "${@:3}" 2>"$WORK/rebind.err")
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        local err
        err=$(head -c 400 "$WORK/rebind.err")
        REBIND_ERR="koto init --attach-live exited $rc: ${reply:0:400} $err"
        return 1
    fi
    if printf '%s' "$reply" | jq -e --arg l "$2" \
        '.outcome == "attached"
         and (((.rebound // {}) | has("REVIEW_LEVEL") | not) or .rebound.REVIEW_LEVEL == $l)' \
        >/dev/null; then
        return 0
    fi
    REBIND_ERR="koto did not report REVIEW_LEVEL rebound to [$2]: ${reply:0:400}"
    return 1
}

refuse() {
    echo "refused: $1"
    exit 1
}

# kept_raise <ledger-file>: the highest level a `raise` subcommand recorded
# (a `raise` line, or a `choose` before any level, with source "raise"), or
# nothing. set-from-facts never
# settles below it and `set` never lowers below it, so an escalated run stays
# at the raised level for the rest of the run.
kept_raise() {
    jq -Rr 'fromjson? | select(type == "object" and (.event == "raise" or .event == "choose") and .source == "raise") | .to // ""
            | if . == "full" then 3 elif . == "standard" then 2 elif . == "light" then 1 else empty end' "$1" \
        | sort -n | tail -n 1 \
        | awk '$1 == 3 { print "full" } $1 == 2 { print "standard" } $1 == 1 { print "light" }'
}

# 1 while `raise` runs cmd_set: it records every move up as a `raise` line
# with source "raise", and a level at or below the current one as no change.
RAISE_MODE=0

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
    has_event "$WORK/ledger" bound \
        || refuse "no bound recorded yet: koto records it as the run enters analysis, so set the level from analysis on (tick into analysis first)"
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
    local cur kept src=""
    cur=$(last_level "$WORK/ledger")
    kept=$(kept_raise "$WORK/ledger")
    [ "$RAISE_MODE" -eq 0 ] || src=raise

    local r_new r_cur r_bf r_bc r_ff
    r_new=$(rank "$new"); r_cur=$(rank "$cur"); r_bf=$(rank "$bfloor")
    r_bc=$(rank "$bceil"); r_ff=$(rank "$ffloor")

    if [ "$RAISE_MODE" -eq 1 ] && [ -n "$cur" ] && [ "$r_new" -le "$r_cur" ]; then
        echo "unchanged: the level is $cur, at or above $new; nothing to raise"
        exit 0
    fi

    if [ -n "$bfloor" ] && [ -n "$bceil" ] && [ "$r_bf" -gt "$r_bc" ]; then
        refuse "the bound's floor $bfloor is above its ceiling $bceil"
    fi

    local event="" breach=0 rule=""
    if [ -z "$cur" ]; then
        [ -z "$cause" ] || usage "--cause applies to a raise, and no level is recorded yet"
        if [ -n "$bfloor" ] && [ "$r_new" -lt "$r_bf" ]; then
            refuse "$new is below the bound's floor $bfloor (bound: floor ${bfloor:--}, ceiling ${bceil:--})"
        fi
        # Before the level check a choose is the agent's raise, which the
        # check keeps; past the ceiling it needs a reason and adds a breach,
        # as a raise does.
        if [ -n "$bceil" ] && [ "$r_new" -gt "$r_bc" ]; then
            [ -n "$reason" ] \
                || refuse "$new is above the bound's ceiling $bceil; a level past it needs --reason (bound: floor ${bfloor:--}, ceiling ${bceil:--})"
            breach=1
        fi
        event=choose
    elif [ "$r_new" -gt "$r_cur" ]; then
        if [ "$RAISE_MODE" -eq 1 ]; then
            event=raise
        elif [ -n "$ffloor" ] && [ "$new" = "$ffloor" ] && [ "$r_cur" -lt "$r_ff" ]; then
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
        if [ -n "$kept" ] && [ "$r_new" -lt "$(rank "$kept")" ]; then
            refuse "$new is below the level review-level.sh raise recorded, $kept; a raise is kept for the rest of the run"
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
        line "$event" from "$cur" to "$new" reason "$reason" rule "$rule" source "$src"
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

# stored_base <file>: prints the impl_base read into <file> when it names a
# commit.
stored_base() {
    local stored
    stored=$(tr -d '[:space:]' < "$1")
    [ -n "$stored" ] && git rev-parse --verify -q "${stored}^{commit}"
}

# measure <base> <tag>: diffs <base>..HEAD, writes every changed path (both
# sides of a rename) NUL-separated to $WORK/paths.<tag>, and sets M_LINES and
# M_FILES. numstat -z: "<add>\t<del>\t<path>\0", or for a rename
# "<add>\t<del>\t\0<old>\0<new>\0". Binary files count "-" as 0 lines.
#
# M_UNSIZED counts the changes whose line count says nothing about their size:
# a binary file (numstat's "-"), and from `git diff --raw` a rename or copy, a
# type change, a mode change on a file that exists on both sides, and a
# submodule (mode 160000 on either side). facts counts any of them as
# `unclassified`, so they keep `standard` and never reach a cap.
M_LINES=0
M_FILES=0
M_UNSIZED=0
measure() {
    local rec add del p p2 omode nmode st
    M_LINES=0
    M_FILES=0
    M_UNSIZED=0
    git diff -z --numstat -M "$1" HEAD > "$WORK/numstat.$2" || return 1
    git diff -z --raw -M "$1" HEAD > "$WORK/raw.$2" || return 1
    # --raw -z: ":<old mode> <new mode> <old sha> <new sha> <status>\0<path>\0",
    # or for a rename or copy a second path after the first.
    while IFS= read -r -d '' rec; do
        case "$rec" in :*) ;; *) continue ;; esac
        rec="${rec#:}"
        omode="${rec%% *}"; rec="${rec#* }"
        nmode="${rec%% *}"; rec="${rec#* }"
        rec="${rec#* }"; rec="${rec#* }"
        st="$rec"
        IFS= read -r -d '' p || break
        case "$st" in R*|C*) IFS= read -r -d '' p2 || break ;; esac
        case "$st" in
            R*|C*|T*) M_UNSIZED=$((M_UNSIZED + 1)); continue ;;
        esac
        if [ "$omode" = 160000 ] || [ "$nmode" = 160000 ]; then
            M_UNSIZED=$((M_UNSIZED + 1))
        elif [ "$omode" != 000000 ] && [ "$nmode" != 000000 ] && [ "$omode" != "$nmode" ]; then
            M_UNSIZED=$((M_UNSIZED + 1))
        fi
    done < "$WORK/raw.$2"
    : > "$WORK/paths.$2"
    while IFS= read -r -d '' rec; do
        add="${rec%%$'\t'*}"
        rec="${rec#*$'\t'}"
        del="${rec%%$'\t'*}"
        p="${rec#*$'\t'}"
        # A binary file's counts are "-": it counts 0 lines, and as unsized.
        if [ "$add" = - ] || [ "$del" = - ]; then M_UNSIZED=$((M_UNSIZED + 1)); fi
        case "$add" in ""|*[!0-9]*) add=0 ;; esac
        case "$del" in ""|*[!0-9]*) del=0 ;; esac
        M_LINES=$((M_LINES + add + del))
        M_FILES=$((M_FILES + 1))
        if [ -z "$p" ]; then
            IFS= read -r -d '' p || break
            IFS= read -r -d '' p2 || break
            printf '%s\0%s\0' "$p" "$p2" >> "$WORK/paths.$2"
        else
            printf '%s\0' "$p" >> "$WORK/paths.$2"
        fi
    done < "$WORK/numstat.$2"
    return 0
}

# path_classes <path>: the classes the path is in, one per line, in the rules
# file's order, each once.
path_classes() {
    local i=0 seen=" "
    while [ "$i" -lt "$NCLASS" ]; do
        case "$seen" in
            *" ${CLASS_NAME[$i]} "*) ;;
            *)
                if glob_match "$1" "${CLASS_GLOB[$i]}"; then
                    seen="$seen${CLASS_NAME[$i]} "
                    echo "${CLASS_NAME[$i]}"
                fi
                ;;
        esac
        i=$((i + 1))
    done
}

cmd_facts() {
    [ $# -ge 1 ] || usage "facts takes <session> [<level>] [--shared-branch <branch>] [--no-check-line]"
    local s="$1" level="" shared="" check_line_owed=1
    shift
    # <level> is optional and may be empty, so the slot after the session
    # takes the next word unless that word is one of the options.
    case "${1:-}" in
        --shared-branch|--no-check-line) ;;
        *) [ $# -eq 0 ] || { level="$1"; shift; } ;;
    esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --shared-branch) [ $# -ge 2 ] || usage "--shared-branch needs a value"; shared="$2"; shift 2 ;;
            --no-check-line) check_line_owed=0; shift ;;
            *) usage "facts takes <session> [<level>] [--shared-branch <branch>] [--no-check-line]; unknown argument [$1]" ;;
        esac
    done
    valid_session "$s" || usage "bad session name [$s]"
    level_or_empty "$level" level
    # An empty value is no shared branch: the template passes an unset
    # SHARED_BRANCH as "". A value that starts with `-` is refused before git
    # sees it, so it can't be read as an option. Only stdout (the normalized
    # name) is dropped: git's own reason for refusing a name reaches stderr.
    if [ -n "$shared" ]; then
        case "$shared" in -*) usage "--shared-branch [$shared] is not a branch name" ;; esac
        git check-ref-format --branch "$shared" >/dev/null \
            || usage "--shared-branch [$shared] is not a branch name"
    fi
    git rev-parse --git-dir >/dev/null || die 64 "not inside a git repository"
    local head
    head=$(git rev-parse --verify -q "HEAD^{commit}") || die 64 "HEAD does not name a commit"

    # The stored copy, never the working tree's: a diff that edits the rules
    # can't change its own floor. A session init never ran for falls back to
    # the shipped file.
    ctx_get "$s" "$RULES_KEY" "$WORK/rules" || die 66 "could not read $RULES_KEY"
    if [ -s "$WORK/rules" ]; then
        load_rules "$WORK/rules"
    else
        load_rules "$RULES_SHIPPED"
    fi

    # Two bases, and the larger diff wins (more changed lines, then more
    # files): the stored impl_base, and the merge-base with the default
    # branch. impl_base alone can be recorded after some of the work, which
    # shrinks the diff and lowers the floor. With no shared history there is
    # no merge-base, and impl_base is used alone. A tie keeps impl_base.
    #
    # On a shared branch the merge-base diff holds every earlier step's
    # commits, so it is never taken: impl_base is the only base, and without
    # it there is no base. (record-changed-paths.sh also prefers impl_base,
    # but falls back to the merge-base; a floor must not.)
    #
    # Either way, a merge of the default branch after impl_base is not the
    # step's change: the impl_base candidate is measured from
    # fold_default_merge's base (scripts/lib/default-merge.sh), which folds
    # what the merge brought in into the base.
    local ibase="" mbase="" dbase="" base="" source="" lines=0 files=0 unsized=0
    ctx_get "$s" impl_base "$WORK/impl_base" || die 66 "could not read impl_base"
    ibase=$(stored_base "$WORK/impl_base") || ibase=""
    dbase=$(default_merge_base) || dbase=""
    if [ -n "$shared" ]; then
        [ -n "$ibase" ] || die 64 "no base resolves on a shared branch: impl_base is unset"
    else
        mbase="$dbase"
    fi
    [ -n "$ibase" ] || [ -n "$mbase" ] \
        || die 64 "no base resolves: impl_base is unset and HEAD shares no history with origin's default branch or main"
    if [ -n "$ibase" ]; then
        fold_default_merge "$ibase"
        measure "$FOLDED_BASE" impl || die 64 "git diff $FOLDED_BASE HEAD failed"
        base="$FOLDED_BASE"; source=impl_base; lines="$M_LINES"; files="$M_FILES"; unsized="$M_UNSIZED"
        cp "$WORK/paths.impl" "$WORK/paths"
    fi
    if [ -n "$mbase" ] && [ "$mbase" != "$ibase" ]; then
        measure "$mbase" merge || die 64 "git diff $mbase HEAD failed"
        if [ -z "$base" ] || [ "$M_LINES" -gt "$lines" ] \
            || { [ "$M_LINES" -eq "$lines" ] && [ "$M_FILES" -gt "$files" ]; }; then
            base="$mbase"; source=merge_base; lines="$M_LINES"; files="$M_FILES"; unsized="$M_UNSIZED"
            cp "$WORK/paths.merge" "$WORK/paths"
        fi
    fi

    # Every path's classes. A path in no class at all is `unclassified`, and
    # so is a change measure() couldn't size (a binary file, a rename, a mode
    # change, a submodule): its line count says nothing about its size.
    local p unclassified=false
    [ "$unsized" -eq 0 ] || unclassified=true
    : > "$WORK/pathclasses"
    while IFS= read -r -d '' p; do
        path_classes "$p" > "$WORK/one"
        [ -s "$WORK/one" ] || unclassified=true
        cat "$WORK/one" >> "$WORK/pathclasses"
    done < "$WORK/paths"
    # The classes hit, in the rules file's order, each once.
    local i hit=""
    : > "$WORK/classes"
    i=0
    while [ "$i" -lt "$NCLASS" ]; do
        case " $hit " in
            *" ${CLASS_NAME[$i]} "*) ;;
            *)
                if grep -qxF "${CLASS_NAME[$i]}" "$WORK/pathclasses"; then
                    hit="$hit ${CLASS_NAME[$i]}"
                    echo "${CLASS_NAME[$i]}" >> "$WORK/classes"
                fi
                ;;
        esac
        i=$((i + 1))
    done

    local tests_changed=false tests_edited=false red_test_edited=false criteria_changed=false
    case " $hit " in *" test "*) tests_changed=true ;; esac
    # A fix's reproducing test (or harness file) rewritten after its red: the
    # red's record (red_first.json) names each one with the blob it was red
    # at, and one whose blob at HEAD differs is `red_test_edited`, whatever
    # class its path is in and whether it only gained lines. This is the
    # classifier's own fix-red comparison (test_classify_red_changed), so the
    # floor, the hold and the packet agree on it. A record that doesn't parse
    # counts as edited, so a failure can raise the floor and never lower it.
    ctx_get "$s" "$RED_KEY" "$WORK/red" || die 66 "could not read $RED_KEY"
    if [ -s "$WORK/red" ]; then
        if test_classify_red_changed "$head" "$WORK/red" > "$WORK/redrows"; then
            [ -s "$WORK/redrows" ] && red_test_edited=true
        else
            red_test_edited=true
        fi
    fi
    # An edited test, as opposed to one only added to: the shared classifier
    # over the same base, the same rules copy and, for a fix, the red's record,
    # so the floor, the hold and the review packet agree on which test was
    # edited. A classification that fails counts every changed test as edited,
    # so a failure can raise the floor and never lower it.
    if [ "$tests_changed" = true ]; then
        local rules_used="$WORK/rules"
        [ -s "$rules_used" ] || rules_used="$RULES_SHIPPED"
        if test_classify_unit "$base" "$head" "$rules_used" "$WORK/red" > "$WORK/testrows" 2>/dev/null; then
            awk -F '\t' '$1 == "edited" { f = 1 } END { exit !f }' "$WORK/testrows" && tests_edited=true
        else
            tests_edited=true
        fi
    fi
    while IFS= read -r -d '' p; do
        case "$p" in docs/plans/*|docs/prds/*) criteria_changed=true ;; esac
    done < "$WORK/paths"
    if [ "$criteria_changed" = false ]; then
        local has_criteria=0
        ctx_has "$s" "$CRITERIA_KEY" || has_criteria=$?
        [ "$has_criteria" -le 1 ] || die 66 "could not read $CRITERIA_KEY"
        if [ "$has_criteria" -eq 0 ]; then
            ctx_get "$s" "$CRITERIA_KEY" "$WORK/criteria.stored" || die 66 "could not read $CRITERIA_KEY"
            session_criteria "$s" "$WORK/criteria.now" || die 66 "could not read context.md"
            cmp -s "$WORK/criteria.stored" "$WORK/criteria.now" || criteria_changed=true
        fi
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
            tests_edited) [ "$tests_edited" = true ] && fired=1 ;;
            red_test_edited) [ "$red_test_edited" = true ] && fired=1 ;;
            criteria_changed) [ "$criteria_changed" = true ] && fired=1 ;;
            unclassified) [ "$unclassified" = true ] && fired=1 ;;
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

    # The caps, after the floor rules and before the fix round's parent floor
    # (which can only raise). A cap lowers a `standard` floor to its level,
    # `light`, when no `full` rule fired (the floor would be full), neither
    # criteria_changed nor unclassified holds, the lines and files are within
    # its bounds, and every class a path is in is one of its classes. The
    # union of the classes hit is the same test as each path's, path by path.
    # A path in a class the cap doesn't list (manifest, which load_rules keeps
    # out of every cap, or executable, instruction and the rest) keeps
    # `standard`. The first cap that applies is the one recorded.
    local c cap_i=-1 cap_applied=false ok
    if [ "$NCAP" -gt 0 ]; then cap_i=0; fi
    i=0
    while [ "$i" -lt "$NCAP" ]; do
        ok=0
        if [ "$floor" = standard ] && [ "$criteria_changed" = false ] && [ "$unclassified" = false ] \
            && [ "$lines" -le "${CAP_LINES[$i]}" ] && [ "$files" -le "${CAP_FILES[$i]}" ]; then
            ok=1
            for c in $hit; do
                case " ${CAP_CLASSES[$i]} " in *" $c "*) ;; *) ok=0 ;; esac
            done
        fi
        if [ "$ok" -eq 1 ]; then
            cap_i="$i"
            cap_applied=true
            floor="${CAP_LEVEL[$i]}"
            frank=$(rank "$floor")
            rule="cap:${CAP_SPEC[$i]}"
            echo "$floor:$rule" >> "$WORK/fired"
            break
        fi
        i=$((i + 1))
    done
    local cap_json=null
    if [ "$cap_i" -ge 0 ]; then
        cap_json=$(jq -nc --arg level "${CAP_LEVEL[$cap_i]}" --arg spec "${CAP_SPEC[$cap_i]}" \
            --argjson lines "${CAP_LINES[$cap_i]}" --argjson files "${CAP_FILES[$cap_i]}" \
            --arg classes "${CAP_CLASSES[$cap_i]}" --argjson applied "$cap_applied" \
            '{level: $level, rule: $spec, lines: $lines, files: $files,
              classes: ($classes | split(" ")), applied: $applied}') || die 66 "could not build the cap record"
    fi

    # A fix round (fix-round.sh records fix_round.json) never sits below the
    # floor of the run it fixes. Off a shared branch the merge-base diff
    # already holds that run's change, but on one impl_base is the only base
    # and the round's diff is the fix alone. A run with no facts recorded
    # adds nothing.
    local from pfloor
    ctx_get "$s" "$FIX_ROUND_KEY" "$WORK/fix_round" || die 66 "could not read $FIX_ROUND_KEY"
    if [ -s "$WORK/fix_round" ]; then
        from=$(jq -r '.from // "" | strings' "$WORK/fix_round") || from=""
        valid_session "$from" || die 66 "$FIX_ROUND_KEY names no run to take a floor from"
        ctx_get "$from" "$FACTS_KEY" "$WORK/parent_facts" || die 66 "could not read $FACTS_KEY from $from"
        if [ -s "$WORK/parent_facts" ]; then
            pfloor=$(jq -r '.floor // "" | strings' "$WORK/parent_facts") || pfloor=""
            if valid_level "$pfloor"; then
                echo "$pfloor:$FIX_ROUND_RULE" >> "$WORK/fired"
                r=$(rank "$pfloor")
                if [ "$r" -gt "$frank" ]; then
                    frank="$r"
                    floor="$pfloor"
                    rule="$FIX_ROUND_RULE"
                fi
            fi
        fi
    fi

    jq -n \
        --argjson lines "$lines" --argjson files "$files" \
        --argjson tests_changed "$tests_changed" --argjson tests_edited "$tests_edited" \
        --argjson red_test_edited "$red_test_edited" \
        --argjson criteria_changed "$criteria_changed" \
        --argjson unclassified "$unclassified" --argjson unsized "$unsized" \
        --argjson cap "$cap_json" \
        --arg floor "$floor" --arg rule "$rule" --arg head "$head" --arg base "$base" \
        --arg base_source "$source" --arg impl_base "$ibase" --arg merge_base "$mbase" \
        --arg shared_branch "$shared" --arg merged_default "$FOLDED_DEFAULT" \
        --rawfile classes "$WORK/classes" --rawfile fired "$WORK/fired" '
        {lines: $lines, files: $files,
         classes: ($classes | split("\n") | map(select(length > 0))),
         tests_changed: $tests_changed, tests_edited: $tests_edited,
         red_test_edited: $red_test_edited,
         criteria_changed: $criteria_changed,
         unclassified: $unclassified, unsized: $unsized,
         cap: $cap,
         floor: $floor, rule: (if $rule == "" then null else $rule end),
         rules_fired: ($fired | split("\n") | map(select(length > 0))),
         head: $head, base: $base, base_source: $base_source,
         shared_branch: $shared_branch,
         bases: {impl_base: (if $impl_base == "" then null else $impl_base end),
                 merge_base: (if $merge_base == "" then null else $merge_base end),
                 merged_default: (if $merged_default == "" then null else $merged_default end)}}
    ' > "$WORK/facts.json" || die 66 "could not build $FACTS_KEY"
    ctx_put "$s" "$FACTS_KEY" "$WORK/facts.json" || die 66 "could not write $FACTS_KEY"

    # Every gather also lands as one line of the history, so the size of the
    # change at each visit can be read after the run; review_facts.json keeps
    # only the latest. Nothing in the workflow reads the history.
    ctx_get "$s" "$FACTS_HISTORY_KEY" "$WORK/facts_history" \
        || die 66 "could not read $FACTS_HISTORY_KEY"
    jq -c . "$WORK/facts.json" >> "$WORK/facts_history" \
        || die 66 "could not build $FACTS_HISTORY_KEY"
    ctx_put "$s" "$FACTS_HISTORY_KEY" "$WORK/facts_history" \
        || die 66 "could not write $FACTS_HISTORY_KEY"

    [ "$check_line_owed" -eq 1 ] || exit 0
    ctx_get "$s" "$LEDGER" "$WORK/ledger" || die 66 "could not read $LEDGER"
    check_line "$WORK/ledger" "$level" "$floor" "$rule" "$head" > "$WORK/new" \
        || die 66 "could not build the ledger line"
    if [ -s "$WORK/new" ]; then
        cat "$WORK/ledger" "$WORK/new" > "$WORK/ledger.next"
        ctx_put "$s" "$LEDGER" "$WORK/ledger.next" || die 66 "could not write $LEDGER"
    fi
    exit 0
}

# check_line <ledger-file> <level> <floor> <rule> <head>: prints the `check`
# line the ledger owes (an `unset` line for an empty level), or nothing when
# its last check or unset line already names this head, level and floor.
check_line() {
    local last
    last=$(jq -Rr 'fromjson? | select(type == "object" and (.event == "check" or .event == "unset"))
                   | "\(.head // "")|\(.level // "")|\(.floor // "")"' "$1" | tail -n 1)
    [ "$last" != "$5|$2|$3" ] || return 0
    if [ -z "$2" ]; then
        line unset floor "$3" rule "$4" head "$5"
    else
        line check level "$2" floor "$3" rule "$4" head "$5"
    fi
}

# ------------------------------------------------------- set-from-facts -------

# The level check's action runs this after `facts`, so no one has to choose a
# level before the change exists. The level only moves up here: the ledger's
# last level already carries every raise (and every lower) the agent made with
# `set`, and a lap whose diff shrank keeps the level an earlier lap reached.
cmd_set_from_facts() {
    [ $# -eq 1 ] || usage "set-from-facts takes <session>"
    local s="$1"
    valid_session "$s" || usage "bad session name [$s]"

    ctx_get "$s" "$LEDGER" "$WORK/ledger" || die 66 "could not read $LEDGER"
    has_event "$WORK/ledger" bound \
        || refuse "no bound recorded yet: analysis's action records it with review-level.sh init"
    ctx_get "$s" "$BOUND_KEY" "$WORK/bound" || die 66 "could not read $BOUND_KEY"
    local bfloor bceil
    bfloor=$(jq -r '.floor // ""' "$WORK/bound")
    bceil=$(jq -r '.ceiling // ""' "$WORK/bound")
    if [ -n "$bfloor" ] && [ -n "$bceil" ] && [ "$(rank "$bfloor")" -gt "$(rank "$bceil")" ]; then
        refuse "the bound's floor $bfloor is above its ceiling $bceil"
    fi
    ctx_get "$s" "$FACTS_KEY" "$WORK/facts" || die 66 "could not read $FACTS_KEY"
    [ -s "$WORK/facts" ] || refuse "no facts recorded yet: run review-level.sh facts first"
    local ffloor frule fhead
    ffloor=$(jq -r '.floor // "light"' "$WORK/facts") || die 66 "could not read $FACTS_KEY"
    frule=$(jq -r '.rule // ""' "$WORK/facts")
    fhead=$(jq -r '.head // ""' "$WORK/facts")
    valid_level "$ffloor" || die 64 "the facts floor [$ffloor] is not light, standard or full"

    local cur level source rule kept
    cur=$(last_level "$WORK/ledger")
    kept=$(kept_raise "$WORK/ledger")
    level="$ffloor"; source=facts; rule="$frule"
    if [ -n "$bfloor" ] && [ "$(rank "$bfloor")" -gt "$(rank "$level")" ]; then
        level="$bfloor"; source=bound; rule=""
    fi
    # A raise is kept: the cap lowers only the facts floor, never a level
    # review-level.sh raise recorded (the light seat's escalate is one).
    if [ -n "$kept" ] && [ "$(rank "$kept")" -gt "$(rank "$level")" ]; then
        level="$kept"; source=raise; rule=""
    fi
    if [ "$(rank "$cur")" -ge "$(rank "$level")" ]; then
        level="$cur"; source=""
    fi

    local breach=0
    : > "$WORK/new"
    if [ -n "$source" ]; then
        # A level above the ceiling can only come from the facts floor: the
        # bound's floor is at or below its ceiling (refused above), and the
        # ledger's level, which `set` breached the ceiling for, wins nothing
        # here.
        [ -n "$bceil" ] && [ "$(rank "$level")" -gt "$(rank "$bceil")" ] && breach=1
        {
            line from_facts from "$cur" to "$level" source "$source" rule "$rule"
            [ "$breach" -eq 0 ] || line breach from "$cur" to "$level" ceiling "$bceil" source "$source" rule "$rule"
        } > "$WORK/new" || die 66 "could not build the ledger line"
    fi
    check_line "$WORK/ledger" "$level" "$ffloor" "$frule" "$fhead" >> "$WORK/new" \
        || die 66 "could not build the ledger line"

    rebind "$s" "$level" || die 66 "rebind failed, nothing recorded: $REBIND_ERR"
    if [ -s "$WORK/new" ]; then
        cat "$WORK/ledger" "$WORK/new" > "$WORK/ledger.next"
        if ! ctx_put "$s" "$LEDGER" "$WORK/ledger.next"; then
            koto context add "$s" "$LEDGER" < "$WORK/ledger" >/dev/null || true
            rebind "$s" "$cur" || echo "review-level: rebinding back to [$cur] also failed: $REBIND_ERR" >&2
            die 66 "could not write $LEDGER; REVIEW_LEVEL rebound back to [${cur:-unset}]"
        fi
    fi
    if [ -n "$source" ]; then
        echo "recorded: from_facts ${cur:--} -> $level ($source floor${rule:+, rule $rule})"
        [ "$breach" -eq 0 ] || echo "recorded: breach of ceiling $bceil"
    else
        echo "unchanged: $level (facts floor $ffloor)"
    fi
    exit 0
}

# ---------------------------------------------------------------- raise -------

# raise <session> <level> --reason <why>: `set` for a move up that the run
# keeps. The light seat's escalate runs it (--reason escalate) before
# light_review routes back to the level check. It records a `raise` line with
# source "raise" and the reason, past the ceiling with a `breach` line as a
# raise through `set` does; a level at or below the current one changes
# nothing and exits 0. set-from-facts never settles below the highest such
# raise and `set` refuses to lower below it.
cmd_raise() {
    [ $# -ge 2 ] || usage "raise takes <session> <level> --reason <why>"
    local s="$1" new="$2" reason="" has_reason=0
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason) [ $# -ge 2 ] || usage "--reason needs a value"; reason="$2"; has_reason=1; shift 2 ;;
            --reason=*) reason="${1#--reason=}"; has_reason=1; shift ;;
            *) usage "raise: unknown argument [$1]" ;;
        esac
    done
    valid_session "$s" || usage "bad session name [$s]"
    valid_level "$new" || usage "level [$new] is not light, standard or full"
    [ "$has_reason" -eq 1 ] || usage "raise needs --reason <why>"
    case "$reason" in *[![:space:]]*) ;; *) usage "raise needs a --reason that isn't blank" ;; esac
    RAISE_MODE=1
    cmd_set "$s" "$new" --reason "$reason"
}

# ---------------------------------------------------------------- audit -------

# sha256_hex: the hex SHA-256 of stdin, with whichever tool the host has.
sha256_hex() {
    local out
    if command -v sha256sum >/dev/null; then
        out=$(sha256sum) || return 1
    elif command -v shasum >/dev/null; then
        out=$(shasum -a 256) || return 1
    else
        echo "review-level: neither sha256sum nor shasum is installed" >&2
        return 1
    fi
    printf '%s\n' "${out%% *}"
}

# audit <session>: whether this run is one of the light runs the full panel
# checks. Exit 0 when the SHA-256 of the session name, read as a number, is 0
# mod 10, 1 otherwise: about a tenth of names, and always the same answer for
# the same name, with no state read or written. light_review's `audited` gate
# runs it; an audited run's passed light panel goes on to scrutiny, review and
# qa_validation as a full run would.
cmd_audit() {
    [ $# -eq 1 ] || usage "audit takes <session>"
    valid_session "$1" || usage "bad session name [$1]"
    local hex
    hex=$(printf '%s' "$1" | sha256_hex) || die 66 "could not hash the session name"
    case "$hex" in ""|*[!0-9a-f]*) die 66 "the session name's hash [$hex] is not hex" ;; esac
    printf '%s\n' "$hex" | awk '{
        r = 0
        for (i = 1; i <= length($0); i++) r = (r * 16 + index("0123456789abcdef", substr($0, i, 1)) - 1) % 10
        exit (r == 0 ? 0 : 1)
    }'
}

# ---------------------------------------------------------------- check -------

hold() {
    echo "hold: $1"
    exit 1
}

cmd_check() {
    [ $# -eq 2 ] || { echo "hold: check takes <session> <level>|--ledger"; exit 1; }
    local s="$1" level="$2" from_ledger=0
    if [ "$level" = --ledger ]; then
        from_ledger=1
        level=""
    fi
    valid_session "$s" || hold "bad session name [$s]"
    [ -z "$level" ] || valid_level "$level" || hold "REVIEW_LEVEL [$level] is not light, standard or full"

    ctx_get "$s" "$LEDGER" "$WORK/ledger" || hold "could not read $LEDGER"
    local recorded
    recorded=$(last_level "$WORK/ledger")
    # --ledger judges the level set-from-facts recorded in this tick, which
    # the variable won't show until the next one; there is no variable to
    # compare with the ledger, and no unset route.
    if [ "$from_ledger" -eq 1 ]; then
        [ -n "$recorded" ] || hold "no level recorded yet; the level check's action records one with review-level.sh set-from-facts"
        valid_level "$recorded" || hold "the ledger's last level [$recorded] is not light, standard or full"
        level="$recorded"
    fi
    # Empty is the unset route only for a session that never recorded a level
    # (one from an earlier template). With a level in the ledger, an empty
    # variable was reset, most likely by a `koto init --attach-live` that
    # didn't pass it, and the run holds until `set` puts it back.
    if [ -z "$level" ]; then
        [ -n "$recorded" ] || exit 3
        hold "REVIEW_LEVEL is empty but the ledger's last level is $recorded; run review-level.sh set $s $recorded to rebind it"
    fi
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
    # `set` refuses every choice under such a bound, so a level here got past
    # it some other way; hold rather than judge it against a contradiction.
    if [ -n "$bfloor" ] && [ -n "$bceil" ] && [ "$(rank "$bfloor")" -gt "$(rank "$bceil")" ]; then
        hold "the bound's floor $bfloor is above its ceiling $bceil"
    fi
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

# ---------------------------------------------------------------- agree -------

# The level is checked against the facts once, at the level check. The states
# after it that route on the level run this, so a hand rebind made while the
# run sits in one of them holds there instead of taking another route.
cmd_agree() {
    [ $# -eq 2 ] || { echo "hold: agree takes <session> <level>"; exit 1; }
    local s="$1" level="$2" recorded
    valid_session "$s" || hold "bad session name [$s]"
    [ -z "$level" ] || valid_level "$level" || hold "REVIEW_LEVEL [$level] is not light, standard or full"
    ctx_get "$s" "$LEDGER" "$WORK/ledger" || hold "could not read $LEDGER"
    recorded=$(last_level "$WORK/ledger")
    [ "$level" = "$recorded" ] && exit 0
    # An empty variable can't pick a lighter route: review sends it to QA,
    # and light_review doesn't route on it. It is also what the tick that
    # records the run's first level carries into light_review or scrutiny,
    # since a rebind shows only from the next tick.
    [ -z "$level" ] && exit 0
    if [ -z "$recorded" ]; then
        hold "REVIEW_LEVEL is $level but the ledger records no level; it was set by hand after the level check. Clear it with koto init $s --attach-live without REVIEW_LEVEL"
    fi
    hold "REVIEW_LEVEL is ${level:-empty} but the ledger's last level is $recorded; it changed after the level check. Run review-level.sh set $s $recorded to put it back"
}

# ---------------------------------------------------------------- classify ----

cmd_classify() {
    [ $# -ge 1 ] || usage "classify takes <path>..."
    local p c
    load_rules "$RULES_SHIPPED"
    for p in "$@"; do
        c=$(path_classes "$p" | paste -sd, -)
        printf '%s\t%s\n' "$p" "${c:--}"
    done
    exit 0
}

# ---------------------------------------------------------------- level -------

# Prints only one of the three names: a ledger line whose `to` is anything else
# prints nothing, and the level check then holds on the empty variable.
cmd_level() {
    [ $# -eq 1 ] || [ $# -eq 2 ] || usage "level takes <session> [--exit]"
    local s="$1" recorded as_exit=0
    if [ $# -eq 2 ]; then
        [ "$2" = --exit ] || usage "level: unknown argument [$2]"
        as_exit=1
    fi
    valid_session "$s" || usage "bad session name [$s]"
    ctx_get "$s" "$LEDGER" "$WORK/ledger" || die 66 "could not read $LEDGER of $s"
    recorded=$(last_level "$WORK/ledger")
    if valid_level "$recorded"; then
        printf '%s\n' "$recorded"
    fi
    [ "$as_exit" -eq 1 ] || exit 0
    # The level check's level_route gate: 10 plus the level's rank, 4 none.
    valid_level "$recorded" || exit 4
    exit $((10 + $(rank "$recorded")))
}

# ---------------------------------------------------------------- slice -------

# join_or <word>...: "a", "a or b", "a, b or c".
join_or() {
    local out="" n=$#
    while [ $# -gt 0 ]; do
        if [ -z "$out" ]; then
            out="$1"
        elif [ $# -eq 1 ]; then
            out="$out or $1"
        else
            out="$out, $1"
        fi
        shift
    done
    if [ "$n" -gt 0 ]; then printf '%s' "$out"; fi
}

# render_rules: the loaded rules as the slice's definition lines, one per level
# that raises the floor, full then standard (load_rules admits no other
# level), then light as the default. On each line the class rules come first,
# as one "classes has" list, then the other facts, each group in the rules
# file's order. Every word comes from load_rules, which admits only level
# names, [a-z0-9_] class names, digit thresholds and the fixed fact names, so
# no path or free text reaches the slice. A `light` rule never raises the
# floor and isn't printed. Each `cap` row follows the standard line, as the
# exception it is: what lowers `standard` to `light`, in the same words.
#
# "Call for" is the phrase the criterion's pass and fail texts use; the
# decider answered far more full-facts fixtures under it than under "the
# highest level any rule yields" (references/jev-criteria.md has the run).
render_rules() {
    local lvl i fact parts classes
    for lvl in full standard; do
        parts=""
        classes=""
        i=0
        while [ "$i" -lt "$NRULE" ]; do
            if [ "${RULE_LEVEL[$i]}" = "$lvl" ]; then
                fact="${RULE_FACT[$i]}"
                case "$fact" in
                    class:*) classes="$classes ${fact#class:}" ;;
                    lines\>*) parts="$parts; or lines > ${fact#lines>}" ;;
                    files\>*) parts="$parts; or files > ${fact#files>}" ;;
                    *) parts="$parts; or $fact" ;;
                esac
            fi
            i=$((i + 1))
        done
        # shellcheck disable=SC2086
        [ -z "$classes" ] || parts="; or classes has $(join_or $classes)$parts"
        [ -z "$parts" ] || echo "the facts call for $lvl when ${parts#; or }"
    done
    i=0
    while [ "$i" -lt "$NCAP" ]; do
        # shellcheck disable=SC2086
        echo "the facts call for ${CAP_LEVEL[$i]} instead of standard when nothing calls for full, criteria_changed and unclassified are false, lines <= ${CAP_LINES[$i]}, files <= ${CAP_FILES[$i]} and every class is $(join_or ${CAP_CLASSES[$i]})"
        i=$((i + 1))
    done
    echo "the facts call for light otherwise"
}

# project_slice <facts-file> <level> <rules-file>: the decider check's slice.
# Every value is typed, so a hand-edited facts key can't carry free text to
# Jev: counts are non-negative integers (anything else is 0), class names match
# [a-z0-9_] and there are at most 16 of them, the booleans are booleans and the
# floor is a level or `unknown`.
#
# After the facts come the level definitions the question judges against: the
# order of the levels, the rules file's floor rules and what the floor is, all
# built from the rules the run's facts were derived from. With only the order
# the decider escaped on full facts. The slice doesn't say what "too light"
# means: the criterion's pass and fail texts carry that, and a slice that
# equated it with "below the floor" would have the decider repeat the
# level_floor gate.
#
# A facts file that is empty or that jq can't parse projects as `{}` and gets
# no definitions: there is nothing to apply them to, so the decider escapes,
# and the level check itself holds on missing or unreadable facts.
project_slice() {
    local facts=$1 level=$2 rules=$3 first='{}'
    valid_level "$level" || level=unset
    if [ -s "$facts" ]; then
        first=$(jq -c 'def count: if type == "number" and . >= 0 and . == floor then . else 0 end;
               {lines: (.lines | count), files: (.files | count),
                classes: ([.classes[]? | strings | select(test("^[a-z0-9_]+$"))] | .[:16]),
                tests_changed: (.tests_changed == true), tests_edited: (.tests_edited == true),
                red_test_edited: (.red_test_edited == true),
                criteria_changed: (.criteria_changed == true),
                unclassified: (.unclassified == true),
                floor: (.floor | if . == "light" or . == "standard" or . == "full" then . else "unknown" end)}' \
            "$facts" 2>/dev/null) || first='{}'
        [ -n "$first" ] || first='{}'
    fi
    # Rules that don't load exit before anything is printed.
    [ "$first" = '{}' ] || load_rules "$rules"
    echo "$first"
    echo "levels: light < standard < full"
    if [ "$first" != '{}' ]; then
        render_rules
        echo "floor: the most thorough level the facts call for"
    fi
    echo "level: $level"
}

# cmd_slice judges with the rules copy init stored, the one `facts` derived the
# floor from; a session init never ran for falls back to the shipped file, as
# `facts` does. Facts or a stored copy that can't be read, or a copy that can't
# be parsed, exits 66 or 64, and koto records the criterion unanswered: never a
# pass.
cmd_slice() {
    local s="${1:-}" level="${2:-}" rules="$RULES_SHIPPED"
    : > "$WORK/facts"
    if [ "$level" = --ledger ]; then
        level=""
        if valid_session "$s"; then
            ctx_get "$s" "$LEDGER" "$WORK/ledger" || die 66 "could not read $LEDGER"
            level=$(last_level "$WORK/ledger")
        fi
    fi
    if valid_session "$s"; then
        ctx_get "$s" "$FACTS_KEY" "$WORK/facts" || die 66 "could not read $FACTS_KEY"
    fi
    if [ -s "$WORK/facts" ]; then
        ctx_get "$s" "$RULES_KEY" "$WORK/rules" || die 66 "could not read $RULES_KEY"
        [ -s "$WORK/rules" ] && rules="$WORK/rules"
        project_slice "$WORK/facts" "$level" "$rules"
    else
        project_slice /dev/null "$level" "$rules"
    fi
    exit 0
}

# project <facts-file> <level> [<rules-file>]: the slice for a facts file, the
# way `slice` prints it for a session, so anything that builds this slice
# outside a live session (a fixture, a measurement) gets this script's output
# by construction. <rules-file> is the session's stored copy when there is
# one; without it, the shipped rules.
cmd_project() {
    local facts="${1:-}" level="${2:-}" rules="${3:-$RULES_SHIPPED}"
    [ -f "$facts" ] && [ -r "$facts" ] || die 64 "project: $facts is not a readable file"
    project_slice "$facts" "$level" "$rules"
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
   elif $has_ledger == "2" then "unreadable"
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
        # has: 0 no ledger, 1 read, 2 present but unreadable, or a read koto
        # refused (a row of its own, not `none`, and exit 2).
        ctx_has "$s" "$LEDGER"
        case $? in
            0) has=1 ;;
            1) has=0 ;;
            *) has=2 ;;
        esac
        if [ "$has" -eq 1 ] && ! koto context get "$s" "$LEDGER" > "$WORK/ledger"; then
            cat "$WORK/ledger" >&2
            : > "$WORK/ledger"
            has=2
        fi
        [ "$has" -ne 2 ] || rc=2
        overrides=$(koto overrides list "$s" \
            | jq -r '[.overrides.items[]? | select(.gate == "level_floor" or .gate == "level_fits_facts")] | length')
        [ -n "$overrides" ] || overrides=-
        seats=0
        if ! ctx_get "$s" verdict_ledger.json "$WORK/verdicts"; then
            seats=-
        elif [ -s "$WORK/verdicts" ]; then
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
    set-from-facts) cmd_set_from_facts "$@" ;;
    facts)  cmd_facts "$@" ;;
    check)  cmd_check "$@" ;;
    agree)  cmd_agree "$@" ;;
    classify) cmd_classify "$@" ;;
    slice)  cmd_slice "$@" ;;
    project) cmd_project "$@" ;;
    report) cmd_report "$@" ;;
    level)  cmd_level "$@" ;;
    raise)  cmd_raise "$@" ;;
    audit)  cmd_audit "$@" ;;
    "")     usage "missing subcommand" ;;
    *)      usage "unknown subcommand [$SUB]" ;;
esac
