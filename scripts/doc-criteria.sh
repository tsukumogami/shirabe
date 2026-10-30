#!/usr/bin/env bash
# doc-criteria.sh -- grade a document's Jev criteria in shadow before a jury
# round, and record how each criterion's verdict agreed with the jury's after
# it.
#
# The /brief, /prd, /design, /strategy and /roadmap jury references call it
# around each round: `grade` right after `doc-check.sh --moment pre_jury`
# exits 0 and before `review-events.sh round-started`, `agreement` right after
# `review-events.sh verdicts`. Both are telemetry: neither changes a verdict,
# a gate, a state of the run's session, or what the skill does next.
#
# Usage:
#   doc-criteria.sh grade --doc <path> --format <f> --topic <t> --skill <s>
#   doc-criteria.sh agreement --format <f> --topic <t> --skill <s> [--round <n>]
#
#   --doc     the document; it must resolve, symlinks followed, to the
#             canonical path for --format and --topic under the repository's
#             docs/ (references/doc-check-phases.json lists them)
#   --format  a format references/doc-criteria.json maps: brief, prd, design,
#             strategy or roadmap
#   --topic   the topic slug (skill-session's topic pattern)
#   --skill   the skill running the step (skill-session's skill pattern); its
#             <skill>-<topic> session holds doc-criteria/latest.json
#   --round   the jury round the agreement is for, 1 to 50; without it, the
#             round review-events.sh last started (key review/round of
#             <skill>-<topic>)
#
# The run session is the one the skill's other telemetry lands on: the parent
# `skill-session.sh dispatch read` prints, else <skill>-<topic>.
#
# grade: for each criterion references/doc-criteria.json lists for the format,
#   starts one throwaway child session of the run session from the
#   criterion's template,
#     koto init <s>-<t>-crit-<rule>-<n> --template <template> --parent <run>
#               --execution-dir <repository root>
#               --var DOC=<doc> --var COMMIT=<sha> --var PLUGIN_ROOT=<plugin>
#   and ticks it once with `koto next <child> --no-cleanup`. The format's
#   children tick in parallel, each in its own process group. A tick still
#   running 180 seconds after the step started is signalled and its child
#   cancelled; a child its tick left waiting (a unit the decider gave no
#   verdict, which waits on an answer nobody gives here) is cancelled too.
#   The run's own session is never ticked, and every koto response goes to
#   this script and is discarded: no criterion text, finding or answer
#   command reaches the caller. It never runs `koto decider answer`, records
#   an override or forces a transition.
#
#   <n> is the document's name counter, kept in doc-criteria/latest.json of
#   <skill>-<topic> with the moment count: each grade is one moment and takes
#   the counter's next value; a name koto refuses as taken is tried again with
#   the next value, up to five more times. A document's eleventh moment starts
#   nothing. latest.json then holds the moment, the counter, the document, its
#   commit and, per criterion, its rule id, section key and child session
#   (`none` when none ran).
#
#   Before any child starts, each template's sha256 and the slicer's are
#   compared with the pins in references/doc-criteria.json; any difference
#   refuses every criterion of the format.
#
# agreement: builds the entries file from latest.json and the format's map,
#   one {"rule_id", "section", "criteria_session"} per criterion, the child
#   latest.json names or `none` when it holds none for the rule, and records
#     koto review record <run> criteria-agreement --doc-format <f>
#                        --round <n> --file <entries>
#   koto computes both verdicts and the agreement from its own records. On a
#   koto without the verb it prints one line and records nothing.
#
# Standard error carries fixed lines only, never text from koto, the decider
# or the document:
#   doc-criteria: <rule-id> not run: <reason>   one per criterion grade skipped,
#                                               reason old_koto, no_python,
#                                               refused_template, name_taken or
#                                               init_failed
#   doc-criteria: <rule-id> stopped: deadline   a tick stopped at 180 seconds
#   doc-criteria: <rule-id> cancelled: waiting  a child left waiting on a unit
#                                               the decider gave no verdict
#                                               (a provider error, a unit over
#                                               budget or past the cap)
#   doc-criteria: refused: <what>               a usage error or an input
#                                               outside its set or pattern
#   doc-criteria: notice: <what>                a record that wasn't made
# Standard output carries one summary line per subcommand.
#
# Exit status: 0, always. The step is telemetry and the skill goes on.
#
# Environment: KOTO_BIN, the koto to run (default `koto` on PATH).
# DOC_CRITERIA_DEADLINE, a whole number of seconds from 1 to 180, shortens
# the deadline for tests; any other value is ignored.
#
# Written for the bash 3.2 floor and deliberately without `set -e`.

set -u

PROG=doc-criteria
HERE=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN_ROOT=$(cd "$HERE/.." && pwd -P)
KOTO="${KOTO_BIN:-koto}"
START_DIR=$(pwd -P)
MAP="$PLUGIN_ROOT/references/doc-criteria.json"
SLICER_REL=scripts/doc-criteria/slice.py
LATEST_KEY=doc-criteria/latest.json
ROUND_KEY=review/round
KOTO_MIN=0.26.0
DEADLINE=180
MOMENT_CAP=10
NAME_TRIES=6
RE_RULE='^rs-[0-9]{3}$'
RE_SECTION='^[a-z0-9][a-z0-9-]{0,63}$'
RE_COMMIT='^[0-9a-f]{40}([0-9a-f]{24})?$'
RE_PLUGIN='^[A-Za-z0-9._/@+-]+$'

case "${DOC_CRITERIA_DEADLINE:-}" in
    [1-9]|[1-9][0-9]|1[0-7][0-9]|180) DEADLINE=$DOC_CRITERIA_DEADLINE ;;
esac

# Every line this script prints on stderr goes through fd 3, so the shell's
# own job reports (a signalled tick's "Terminated") can be sent elsewhere.
exec 3>&2

say() { printf '%s: %s\n' "$PROG" "$*" >&3; }
done0() { exit 0; }
refuse() { say "refused: $*"; done0; }
usage() {
    cat >&3 <<'EOF'
Usage: doc-criteria.sh grade --doc <path> --format <f> --topic <t> --skill <s>
       doc-criteria.sh agreement --format <f> --topic <t> --skill <s> [--round <n>]
EOF
    done0
}

# shellcheck source=lib/doc-session.sh
. "$PLUGIN_ROOT/scripts/lib/doc-session.sh" || refuse "cannot load scripts/lib/doc-session.sh"
ds_notice() { say "notice: $*"; }

# --- arguments ----------------------------------------------------------------

[ $# -ge 1 ] || usage
CMD=$1
shift
case "$CMD" in
    grade|agreement) ;;
    *) usage ;;
esac
DOC_ARG="" FORMAT="" TOPIC="" SKILL="" ROUND=""
set_once() { # <current value> <name>
    [ -z "$1" ] || { say "$2 given twice"; usage; }
}
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$CMD:$1" in
        grade:--doc) set_once "$DOC_ARG" --doc; DOC_ARG=$2 ;;
        *:--format) set_once "$FORMAT" --format; FORMAT=$2 ;;
        *:--topic) set_once "$TOPIC" --topic; TOPIC=$2 ;;
        *:--skill) set_once "$SKILL" --skill; SKILL=$2 ;;
        agreement:--round) set_once "$ROUND" --round; ROUND=$2 ;;
        *) usage ;;
    esac
    shift 2
done
[ -n "$FORMAT" ] && [ -n "$TOPIC" ] && [ -n "$SKILL" ] || usage
[ "$CMD" = agreement ] || [ -n "$DOC_ARG" ] || usage

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || refuse "$tool is not on PATH"
done
[ -r "$MAP" ] || refuse "cannot read references/doc-criteria.json"
[[ "$FORMAT" =~ ^[a-z]+$ ]] && jq -e --arg f "$FORMAT" '.formats | has($f)' "$MAP" >/dev/null 2>&1 \
    || refuse "--format is not one of: $(jq -r '.formats | keys | join(" ")' "$MAP" 2>/dev/null)"
[[ "$TOPIC" =~ $DS_RE_TOPIC ]] || refuse "--topic must match $DS_RE_TOPIC"
[[ "$SKILL" =~ $DS_RE_SKILL ]] || refuse "--skill must match $DS_RE_SKILL"
if [ -n "$ROUND" ]; then
    [[ "$ROUND" =~ ^[1-9][0-9]?$ ]] && [ "$ROUND" -le 50 ] || refuse "--round must be a whole number from 1 to 50"
fi

# The format's criteria, one "<rule>\t<section>\t<template>" line each, every
# field checked against its shape so nothing from the map reaches a name or a
# command line unchecked.
CRITERIA=$(jq -r --arg f "$FORMAT" '.formats[$f][] | [.rule_id, .section, .template] | @tsv' "$MAP" 2>/dev/null) \
    || refuse "cannot read the $FORMAT criteria in references/doc-criteria.json"
while IFS='	' read -r rule section tpl; do
    [ -n "$rule" ] || continue
    [[ "$rule" =~ $RE_RULE ]] && [[ "$section" =~ $RE_SECTION ]] \
        && [[ "$tpl" =~ ^koto-templates/doc-criteria/[a-z]+-rs-[0-9]{3}\.md$ ]] \
        || refuse "references/doc-criteria.json has a $FORMAT entry outside its shape"
done <<EOF
$CRITERIA
EOF
[ -n "$CRITERIA" ] || refuse "references/doc-criteria.json lists no criteria for $FORMAT"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || refuse "not inside a git working tree"
cd "$ROOT" || refuse "cannot enter the repository root"
ROOT_REAL=$(pwd -P)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/doc-criteria.XXXXXX") || refuse "cannot create a private scratch directory"
chmod 700 "$WORK" || refuse "cannot make the scratch directory private"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM HUP

STATE_SESSION="$SKILL-$TOPIC"
KOTO_OK=false
command -v "$KOTO" >/dev/null 2>&1 && KOTO_OK=true

# latest_read <out>: doc-criteria/latest.json of the skill's own session, or
# `{}` when it is absent, unreadable or not one.
latest_read() {
    printf '{}\n' > "$1"
    [ "$KOTO_OK" = true ] || return 0
    "$KOTO" context exists "$STATE_SESSION" "$LATEST_KEY" >/dev/null 2>&1 || return 0
    if "$KOTO" context get "$STATE_SESSION" "$LATEST_KEY" > "$1.raw" 2>/dev/null \
        && jq -e 'type == "object" and .schema == "doc-criteria-latest/v1"' "$1.raw" >/dev/null 2>&1; then
        mv "$1.raw" "$1"
    else
        ds_notice "$LATEST_KEY in $STATE_SESSION is not a criteria record; starting from none"
    fi
    rm -f "$1.raw"
    return 0
}

ds_record_session "$SKILL" "$TOPIC" 2>/dev/null
RUN_SESSION=$DS_RECORD_SESSION

# =============================================================== agreement

if [ "$CMD" = agreement ]; then
    if [ "$KOTO_OK" != true ]; then
        ds_notice "koto is not on PATH; the criteria agreement was not recorded"
        done0
    fi
    if [ -z "$ROUND" ]; then
        ROUND=$("$KOTO" context get "$STATE_SESSION" "$ROUND_KEY" 2>/dev/null | head -n 1 | tr -d '[:space:]')
        if ! [[ "$ROUND" =~ ^[1-9][0-9]?$ ]] || [ "$ROUND" -gt 50 ]; then
            ds_notice "no review round from 1 to 50 is recorded in $STATE_SESSION; the criteria agreement was not recorded"
            done0
        fi
    fi
    if ! "$KOTO" review record --help 2>/dev/null | grep -q '^ *criteria-agreement '; then
        ds_notice "this koto has no criteria-agreement record; the criteria agreement was not recorded"
        done0
    fi
    latest_read "$WORK/latest.json"
    printf '%s\n' "$CRITERIA" > "$WORK/criteria.tsv"
    # A child latest.json names for a rule is passed only when it has the
    # shape of this step's own child names; koto checks the rest.
    if ! jq -c --arg f "$FORMAT" --arg pre "$SKILL-$TOPIC-crit-" --rawfile crit "$WORK/criteria.tsv" '
            (if .format == $f then (.criteria // []) else [] end) as $ran
            | [$crit | split("\n")[] | select(length > 0) | split("\t") | {rule_id: .[0], section: .[1]}
               | . as $c
               | ([$ran[] | select(.rule_id == $c.rule_id and .section == $c.section) | .session // "none"]
                  | first // "none") as $s
               | $c + {criteria_session: (if ($s | type) == "string" and ($s | startswith($pre + $c.rule_id + "-"))
                                              and ($s | test("-[0-9]{1,3}$")) then $s else "none" end)}]' \
            "$WORK/latest.json" > "$WORK/entries.json" 2>/dev/null; then
        ds_notice "could not build the agreement entries; the criteria agreement was not recorded"
        done0
    fi
    "$KOTO" review record "$RUN_SESSION" criteria-agreement --doc-format "$FORMAT" --round "$ROUND" \
        --file "$WORK/entries.json" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        ds_notice "the round $ROUND criteria agreement was not recorded (koto exit $rc)"
        done0
    fi
    echo "doc-criteria: round $ROUND agreement recorded for $(jq 'length' "$WORK/entries.json") criteria"
    done0
fi

# =================================================================== grade

ds_resolve_doc "$START_DIR" "$DOC_ARG" || refuse "$DS_REASON"
DOC=$DS_DOC
canonical=0
while IFS= read -r c; do
    [ "$c" = "$DOC" ] && canonical=1
done <<EOF
$(ds_canonical_paths "$FORMAT" "$TOPIC" 2>/dev/null)
EOF
[ "$canonical" -eq 1 ] || refuse "--doc resolves to $DOC, not the canonical $FORMAT path for topic $TOPIC"
[[ "$DOC" =~ ^docs/[A-Za-z0-9._/@+-]+$ ]] || refuse "--doc has a character koto's --var refuses"
COMMIT=$(ds_doc_commit "$DOC")
[[ "$COMMIT" =~ $RE_COMMIT ]] || refuse "$DOC has no committed version without uncommitted changes"
[[ "$PLUGIN_ROOT" =~ $RE_PLUGIN ]] || refuse "the plugin root has a character koto's --var refuses"

# skip_all <reason>: every criterion not run, for one reason.
: > "$WORK/results"
skip_all() {
    local rule section tpl
    while IFS='	' read -r rule section tpl; do
        [ -n "$rule" ] || continue
        say "$rule not run: $1"
        printf '%s\t%s\tnone\t%s\n' "$rule" "$section" "$1" >> "$WORK/results"
    done <<EOF
$CRITERIA
EOF
}

# version_at_least <have> <want>: both x.y.z.
version_at_least() {
    local IFS=.
    # shellcheck disable=SC2206
    local a=($1) b=($2) i
    for i in 0 1 2; do
        [ "${a[$i]:-0}" -gt "${b[$i]:-0}" ] 2>/dev/null && return 0
        [ "${a[$i]:-0}" -lt "${b[$i]:-0}" ] 2>/dev/null && return 1
    done
    return 0
}

sha_of() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 < "$1" 2>/dev/null | awk '{ print $1 }'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum < "$1" 2>/dev/null | awk '{ print $1 }'
    fi
}

latest_read "$WORK/latest.json"
PREV_MOMENT=$(jq -r --arg d "$DOC" 'if .doc == $d then (.moment // 0) else 0 end' "$WORK/latest.json" 2>/dev/null)
PREV_COUNTER=$(jq -r --arg d "$DOC" 'if .doc == $d then (.counter // 0) else 0 end' "$WORK/latest.json" 2>/dev/null)
[[ "$PREV_MOMENT" =~ ^[0-9]{1,3}$ ]] || PREV_MOMENT=0
[[ "$PREV_COUNTER" =~ ^[0-9]{1,3}$ ]] || PREV_COUNTER=0
MOMENT=$((PREV_MOMENT + 1))
COUNTER=$PREV_COUNTER

KOTO_VERSION=""
if [ "$KOTO_OK" = true ]; then
    KOTO_VERSION=$("$KOTO" version 2>/dev/null | head -n 1 | sed -n 's/^koto v\{0,1\}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
fi

STARTED=""
if [ "$MOMENT" -gt "$MOMENT_CAP" ]; then
    MOMENT=$PREV_MOMENT
    skip_all name_taken
elif [ -z "$KOTO_VERSION" ] || ! version_at_least "$KOTO_VERSION" "$KOTO_MIN"; then
    skip_all old_koto
elif ! command -v python3 >/dev/null 2>&1; then
    skip_all no_python
else
    pins_ok=true
    while IFS='	' read -r rule section tpl; do
        [ -n "$rule" ] || continue
        for f in "$tpl" "$SLICER_REL"; do
            want=$(jq -r --arg p "$f" '.pins[$p] // ""' "$MAP" 2>/dev/null)
            have=""
            [ -f "$PLUGIN_ROOT/$f" ] && [ ! -L "$PLUGIN_ROOT/$f" ] && have=$(sha_of "$PLUGIN_ROOT/$f")
            [ -n "$want" ] && [ "$have" = "$want" ] || pins_ok=false
        done
    done <<EOF
$CRITERIA
EOF
    if [ "$pins_ok" != true ]; then
        skip_all refused_template
    else
        STARTED=yes
    fi
fi

# --- start the children ------------------------------------------------------------

# start_child <rule> <section> <template>: inits the criterion's child under
# the next free name; appends "<rule>\t<section>\t<child|none>\t<reason>" to
# results.
start_child() {
    local rule=$1 section=$2 tpl=$3 try=0 n name rc
    while [ "$try" -lt "$NAME_TRIES" ]; do
        n=$((BASE_N + try))
        [ "$n" -gt "$COUNTER" ] && COUNTER=$n
        name="$SKILL-$TOPIC-crit-$rule-$n"
        try=$((try + 1))
        "$KOTO" init "$name" --template "$PLUGIN_ROOT/$tpl" --parent "$RUN_SESSION" \
            --execution-dir "$ROOT_REAL" \
            --var "DOC=$DOC" --var "COMMIT=$COMMIT" --var "PLUGIN_ROOT=$PLUGIN_ROOT" >/dev/null 2>&1
        rc=$?
        if [ "$rc" -eq 0 ]; then
            printf '%s\t%s\t%s\tstarted\n' "$rule" "$section" "$name" >> "$WORK/results"
            return 0
        fi
        # A name koto already holds is taken; any other refusal ends the
        # criterion here.
        if ! "$KOTO" status "$name" >/dev/null 2>&1; then
            say "$rule not run: init_failed"
            printf '%s\t%s\tnone\tinit_failed\n' "$rule" "$section" >> "$WORK/results"
            return 0
        fi
    done
    say "$rule not run: name_taken"
    printf '%s\t%s\tnone\tname_taken\n' "$rule" "$section" >> "$WORK/results"
}

STEP_START=$(date +%s)
# Every child of one moment takes the counter's next value; a rule whose name
# is taken tries the values after it, and the counter keeps the highest used.
BASE_N=$((PREV_COUNTER + 1))
if [ "$STARTED" = yes ]; then
    while IFS='	' read -r rule section tpl; do
        [ -n "$rule" ] || continue
        start_child "$rule" "$section" "$tpl"
    done <<EOF
$CRITERIA
EOF
fi

# --- tick them, in parallel, under the deadline ------------------------------------

# Each tick is a background job in its own process group (job control on), so a
# signal reaches koto and the gate command it runs. A job writes its marker on
# exit; the watcher reads markers, never a process table.
tick_all() {
    local i=0 child pid now running
    set -m
    while IFS='	' read -r rule section child status; do
        [ "$status" = started ] || continue
        i=$((i + 1))
        ( "$KOTO" next "$child" --no-cleanup >/dev/null 2>&1; echo done > "$WORK/tick.$i.done" ) &
        printf '%s\t%s\t%s\n' "$i" "$!" "$child" >> "$WORK/ticks"
    done < "$WORK/results"
    set +m
    [ -s "$WORK/ticks" ] || return 0
    while :; do
        running=0
        while IFS='	' read -r i pid child; do
            [ -f "$WORK/tick.$i.done" ] || running=1
        done < "$WORK/ticks"
        [ "$running" -eq 1 ] || break
        now=$(date +%s)
        if [ $((now - STEP_START)) -ge "$DEADLINE" ]; then
            while IFS='	' read -r i pid child; do
                [ -f "$WORK/tick.$i.done" ] && continue
                kill -TERM -- "-$pid" 2>/dev/null
                printf '%s\n' "$child" >> "$WORK/stopped"
            done < "$WORK/ticks"
            sleep 1
            while IFS='	' read -r i pid child; do
                [ -f "$WORK/tick.$i.done" ] || kill -KILL -- "-$pid" 2>/dev/null
            done < "$WORK/ticks"
            break
        fi
        sleep 1
    done
    wait
    return 0
}
: > "$WORK/ticks"
: > "$WORK/stopped"
[ "$STARTED" = yes ] && tick_all 2>/dev/null

# --- cancel what was stopped or left waiting ----------------------------------------

while IFS='	' read -r rule section child status; do
    [ "$status" = started ] || continue
    if grep -qxF -- "$child" "$WORK/stopped"; then
        say "$rule stopped: deadline"
        "$KOTO" cancel "$child" >/dev/null 2>&1 || ds_notice "could not cancel the $rule child after the deadline"
        continue
    fi
    terminal=$("$KOTO" status "$child" 2>/dev/null | jq -r '.is_terminal // false' 2>/dev/null)
    if [ "$terminal" != true ]; then
        say "$rule cancelled: waiting"
        "$KOTO" cancel "$child" >/dev/null 2>&1 || ds_notice "could not cancel the waiting $rule child"
    fi
done < "$WORK/results"

# --- the record ----------------------------------------------------------------------

if jq -n -c --arg d "$DOC" --arg f "$FORMAT" --arg c "$COMMIT" \
        --argjson m "$MOMENT" --argjson n "$COUNTER" --rawfile r "$WORK/results" '
        {schema: "doc-criteria-latest/v1", doc: $d, format: $f, commit: $c, moment: $m, counter: $n,
         criteria: [$r | split("\n")[] | select(length > 0) | split("\t")
                    | {rule_id: .[0], section: .[1], session: .[2], status: .[3]}]}' > "$WORK/latest.new" 2>/dev/null; then
    if [ "$KOTO_OK" = true ]; then
        "$KOTO" context add "$STATE_SESSION" "$LATEST_KEY" --from-file "$WORK/latest.new" >/dev/null 2>&1 \
            || ds_notice "could not write $LATEST_KEY into $STATE_SESSION"
    fi
else
    ds_notice "could not build $LATEST_KEY"
fi

ran=$(awk -F'\t' '$4 == "started" { n++ } END { print n + 0 }' "$WORK/results")
echo "doc-criteria: moment $MOMENT graded $ran of $(printf '%s\n' "$CRITERIA" | grep -c .) criteria"
done0
