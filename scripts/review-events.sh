#!/usr/bin/env bash
# review-events.sh -- record a document jury's rounds, its seats' per-rule
# verdicts and the decision that follows each round, as telemetry.
#
# The /brief, /prd, /design and /review-plan jury references call it around
# each round (references/review-verdicts.md has the seat's side). Recording
# never changes a verdict, a gate or what the skill does next.
#
# Usage:
#   review-events.sh round-started --skill <s> --topic <t> --doc <path>
#                                  --seat-count <n> [--fallback]
#   review-events.sh verdicts --skill <s> --topic <t> --doc <path> --dir <verdicts-dir>
#   review-events.sh decision --skill <s> --topic <t> --doc <path> --decision <d>
#
#   --skill       brief, prd, design or plan (the skill whose <skill>-<topic>
#                 session holds the round counter; /review-plan records under
#                 plan). It is also the document type recorded.
#   --topic       the topic slug
#   --doc         the document under review; its frontmatter `schema:` value
#                 is recorded as is (koto buckets it), or none when the file
#                 is absent or has none
#   --seat-count  how many seats the round spawns, a positive integer
#   --fallback    the round runs as the serial self-jury fallback
#   --dir         the directory the seats wrote their files to, before
#                 `skill-session.sh ingest` removes it
#   --decision    rerun, fix_and_proceed, loop_back, proceed or stop
#
# round-started: adds one to the session key review/round in <skill>-<topic>
#   (0 when absent) and records
#     koto review record <session> round-started --doc-type <s> --schema <v>
#                        --round <n> --seat-count <n> [--fallback]
# verdicts: for each seat of the skill's own seat list (below), reads the
#   seat's pinned file in --dir and the last fenced `review-verdicts` block in
#   it, and records one batch per seat
#     koto review record <session> verdicts --file <batch>
#   with entries {rule_id, section, verdict, seat, round, doc_type, schema?}.
#   An entry is dropped when it isn't an object of string rule_id, section and
#   verdict, when its verdict isn't PASS or FAIL, or when its rule id isn't one
#   `rule-registry.sh resolve` resolves (a lookup that fails or can't run
#   counts as unknown). A section outside the format's closed list (its
#   required sections from references/doc-check-phases.json slugged, plus
#   frontmatter and document) is recorded as document. A seat with no file, no
#   block, a block that isn't a JSON array, or no valid entry records one FAIL
#   on rs-verdict-missing, section document. At most 200 entries per seat.
# decision: records
#     koto review record <session> decision --doc-type <s> --schema <v>
#                        --round <n> --decision <d>
#   at the round review/round holds; with no round recorded it records nothing.
#
# The seat name comes from the seat list and the pinned file name, never from
# the seat's output. A parse error or a dropped entry is reported on stderr by
# seat, entry number and field, never with the text the seat wrote.
#
# Telemetry goes to the session `skill-session.sh dispatch read` resolves (the
# chain's parent when one dispatched the skill, else <skill>-<topic>), best
# effort: koto absent, a koto without the verb, no session or a refused call
# prints one notice on stderr and changes nothing else.
#
# Exit status: 0 done (whether or not anything was recorded); 2 refused (a
# usage error, an input outside its closed set or pattern, jq missing).
#
# Environment: KOTO_BIN, the koto to run (default `koto` on PATH).
#
# Written for the bash 3.2 floor and without `set -e`.

set -u

PROG=review-events
HERE=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN_ROOT=$(cd "$HERE/.." && pwd -P)
KOTO="${KOTO_BIN:-koto}"
ENTRY_CAP=200
ROUND_KEY=review/round
MISSING_RULE=rs-verdict-missing
ID_SHAPE='^([a-z0-9-]+/[a-z0-9-]+|rs-[0-9]{3}|rs-verdict-missing)$'

usage() {
    cat >&2 <<'EOF'
Usage: review-events.sh round-started --skill <s> --topic <t> --doc <path> --seat-count <n> [--fallback]
       review-events.sh verdicts --skill <s> --topic <t> --doc <path> --dir <verdicts-dir>
       review-events.sh decision --skill <s> --topic <t> --doc <path> --decision <d>
EOF
    exit 2
}

refuse() {
    echo "review-events: refused: $*" >&2
    exit 2
}

# shellcheck source=lib/doc-session.sh
. "$PLUGIN_ROOT/scripts/lib/doc-session.sh" || refuse "cannot load scripts/lib/doc-session.sh"

# seats_of <skill>: the skill's jury seats, one `<seat>\t<pinned file>` line
# each. The jury references pin these file names.
seats_of() {
    case "$1" in
        brief) printf '%s\t%s\n' content-quality phase4_content-quality.md structural-format phase4_structural-format.md ;;
        prd) printf '%s\t%s\n' completeness phase4_completeness.md clarity phase4_clarity.md testability phase4_testability.md ;;
        design) printf '%s\t%s\n' architecture phase6_architecture-review.md security phase6_security-review.md \
            structural-format phase6_structural-format-review.md ;;
        plan) printf '%s\t%s\n' scope-gate category-a.md design-fidelity category-b.md ac-discriminability category-c.md \
            sequencing category-d.md functional-shape category-e.md ;;
    esac
}

# --- arguments ----------------------------------------------------------------

[ $# -ge 1 ] || usage
CMD=$1
shift
case "$CMD" in
    round-started|verdicts|decision) ;;
    *) usage ;;
esac
SKILL="" TOPIC="" DOC="" SEATS="" FALLBACK=false DIR="" DECISION=""
set_once() { # <current value> <name>
    [ -z "$1" ] || { echo "review-events: $2 given twice" >&2; usage; }
}
while [ $# -gt 0 ]; do
    if [ "$CMD:$1" = round-started:--fallback ]; then
        [ "$FALLBACK" = false ] || { echo "review-events: --fallback given twice" >&2; usage; }
        FALLBACK=true
        shift
        continue
    fi
    [ $# -ge 2 ] || usage
    case "$CMD:$1" in
        *:--skill) set_once "$SKILL" --skill; SKILL=$2 ;;
        *:--topic) set_once "$TOPIC" --topic; TOPIC=$2 ;;
        *:--doc) set_once "$DOC" --doc; DOC=$2 ;;
        round-started:--seat-count) set_once "$SEATS" --seat-count; SEATS=$2 ;;
        verdicts:--dir) set_once "$DIR" --dir; DIR=$2 ;;
        decision:--decision) set_once "$DECISION" --decision; DECISION=$2 ;;
        *) usage ;;
    esac
    shift 2
done
[ -n "$SKILL" ] && [ -n "$TOPIC" ] && [ -n "$DOC" ] || usage
case "$CMD" in
    round-started) [ -n "$SEATS" ] || usage ;;
    verdicts) [ -n "$DIR" ] || usage ;;
    decision) [ -n "$DECISION" ] || usage ;;
esac

command -v jq >/dev/null 2>&1 || refuse "jq is not on PATH"
case "$SKILL" in
    brief|prd|design|plan) ;;
    *) refuse "--skill is not brief, prd, design or plan" ;;
esac
[[ "$TOPIC" =~ $DS_RE_TOPIC ]] || refuse "--topic must match $DS_RE_TOPIC"
if [ "$CMD" = round-started ]; then
    [[ "$SEATS" =~ ^[1-9][0-9]{0,2}$ ]] || refuse "--seat-count must be a positive integer"
fi
if [ "$CMD" = decision ]; then
    case "$DECISION" in
        rerun|fix_and_proceed|loop_back|proceed|stop) ;;
        *) refuse "--decision is not rerun, fix_and_proceed, loop_back, proceed or stop" ;;
    esac
fi
if [ "$CMD" = verdicts ]; then
    [ -d "$DIR" ] && [ ! -L "$DIR" ] || refuse "--dir is not a directory"
fi
[ -r "$DS_PHASES" ] || refuse "cannot read $DS_PHASES"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/review-events.XXXXXX") || refuse "cannot create a private scratch directory"
chmod 700 "$WORK" || refuse "cannot make the scratch directory private"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
trap 'cleanup; exit 2' INT TERM HUP

SESSION="$SKILL-$TOPIC"

# The schema value from the document's frontmatter, only when it has the
# shape of one; anything else is passed as `unrecognized`, which koto buckets
# as other. The author controls it, so no other byte of it is passed on.
SCHEMA=""
if [ -f "$DOC" ] && [ ! -L "$DOC" ]; then
    raw=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
               NR > 1 && /^schema:/ { sub(/^schema:[ \t]*/, ""); sub(/[ \t]+$/, ""); gsub(/^["'"'"']|["'"'"']$/, ""); print; exit }' "$DOC" 2>/dev/null)
    if [ -n "$raw" ]; then
        if [[ "$raw" =~ ^[a-z0-9][a-z0-9./-]{0,31}$ ]]; then SCHEMA=$raw; else SCHEMA=unrecognized; fi
    fi
fi

# round_read: the round review/round holds in the skill's session, or 0.
round_read() {
    local v
    command -v "$KOTO" >/dev/null 2>&1 || { echo 0; return 0; }
    v=$("$KOTO" context get "$SESSION" "$ROUND_KEY" 2>/dev/null | head -n 1 | tr -d '[:space:]')
    [[ "$v" =~ ^[1-9][0-9]{0,5}$ ]] || v=0
    echo "$v"
}

ds_record_session "$SKILL" "$TOPIC"

# --- round-started -------------------------------------------------------------

if [ "$CMD" = round-started ]; then
    ROUND=$(( $(round_read) + 1 ))
    if command -v "$KOTO" >/dev/null 2>&1; then
        printf '%s\n' "$ROUND" > "$WORK/round"
        "$KOTO" context add "$SESSION" "$ROUND_KEY" --from-file "$WORK/round" >/dev/null 2>&1 \
            || ds_notice "could not write $ROUND_KEY into $SESSION"
    fi
    set -- --doc-type "$SKILL" --schema "$SCHEMA" --round "$ROUND" --seat-count "$SEATS"
    [ "$FALLBACK" = false ] || set -- "$@" --fallback
    echo "review-events: round $ROUND started"
    ds_record "round $ROUND" "$DS_RECORD_SESSION" round-started "$@"
    exit 0
fi

ROUND=$(round_read)
if [ "$ROUND" -eq 0 ]; then
    ds_notice "no round-started is recorded in $SESSION; the $CMD was not recorded"
    exit 0
fi

# --- decision -------------------------------------------------------------------

if [ "$CMD" = decision ]; then
    echo "review-events: round $ROUND decision $DECISION"
    ds_record "the round $ROUND decision" "$DS_RECORD_SESSION" decision \
        --doc-type "$SKILL" --schema "$SCHEMA" --round "$ROUND" --decision "$DECISION"
    exit 0
fi

# --- verdicts -------------------------------------------------------------------

{
    jq -r --arg f "$SKILL" '.formats[$f].required_sections[]' "$DS_PHASES" | while IFS= read -r s; do ds_slug "$s"; echo; done
    printf 'frontmatter\ndocument\n'
} | sed '/^$/d' | sort -u > "$WORK/sections" || refuse "cannot read the required sections of $SKILL"

# registered <id>: whether the registry resolves the id.
registered() {
    [[ "$1" =~ $ID_SHAPE ]] || return 1
    "$PLUGIN_ROOT/scripts/rule-registry.sh" resolve "$1" >/dev/null 2>&1
}

seats_of "$SKILL" > "$WORK/seats"
while IFS='	' read -r seat file; do
    [ -n "$seat" ] || continue
    : > "$WORK/valid"
    src="$DIR/$file"
    if [ ! -f "$src" ] || [ -L "$src" ]; then
        ds_notice "seat $seat: no output file"
    else
        awk '/^```review-verdicts[ \t]*$/ { inside = 1; n++; buf[n] = ""; next }
             inside && /^```[ \t]*$/ { inside = 0; done[n] = 1; next }
             inside { buf[n] = buf[n] $0 "\n" }
             END { for (i = n; i >= 1; i--) if (i in done) { printf "%s", buf[i]; exit } }' "$src" > "$WORK/block" 2>/dev/null
        if [ ! -s "$WORK/block" ]; then
            ds_notice "seat $seat: no review-verdicts block"
        elif ! jq -e 'type == "array"' "$WORK/block" >/dev/null 2>&1; then
            ds_notice "seat $seat: the review-verdicts block is not a JSON array"
        else
            jq -c 'to_entries[]' "$WORK/block" > "$WORK/entries"
            while IFS= read -r e; do
                n=$(( $(printf '%s' "$e" | jq -r '.key') + 1 ))
                bad=$(printf '%s' "$e" | jq -r '.value as $v
                    | if ($v | type) != "object" then "entry"
                      else (["rule_id", "section", "verdict"][] | select(($v[.] | type) != "string")) end' | head -n 1)
                if [ -n "$bad" ]; then
                    ds_notice "seat $seat entry $n: $bad is missing or not a string; dropped"
                    continue
                fi
                verdict=$(printf '%s' "$e" | jq -r '.value.verdict')
                case "$verdict" in
                    PASS|FAIL) ;;
                    *) ds_notice "seat $seat entry $n: verdict is not PASS or FAIL; dropped"; continue ;;
                esac
                rule=$(printf '%s' "$e" | jq -r '.value.rule_id')
                if ! registered "$rule"; then
                    ds_notice "seat $seat entry $n: rule_id is not a registered rule; dropped"
                    continue
                fi
                section=$(printf '%s' "$e" | jq -r '.value.section')
                # The slug shape comes first: grep -F reads a value with a
                # newline as several patterns, so "document\n<forged row>"
                # would match the list and its extra line would reach the
                # tab-separated file below as an unchecked entry.
                if ! [[ "$section" =~ ^[a-z0-9-]+$ ]] || ! grep -qxF -- "$section" "$WORK/sections"; then
                    ds_notice "seat $seat entry $n: section is not on the $SKILL list; recorded as document"
                    section=document
                fi
                printf '%s\t%s\t%s\n' "$rule" "$section" "$verdict" >> "$WORK/valid"
            done < "$WORK/entries"
        fi
    fi
    if [ ! -s "$WORK/valid" ]; then
        printf '%s\tdocument\tFAIL\n' "$MISSING_RULE" > "$WORK/valid"
    fi
    total=$(wc -l < "$WORK/valid" | tr -d ' ')
    if [ "$total" -gt "$ENTRY_CAP" ]; then
        ds_notice "seat $seat: $total entries; only the first $ENTRY_CAP are recorded"
    fi
    BATCH=$(mktemp "$WORK/verdicts.XXXXXX") || { ds_notice "could not create the telemetry batch for seat $seat"; continue; }
    head -n "$ENTRY_CAP" "$WORK/valid" | jq -R -s -c --arg seat "$seat" --argjson round "$ROUND" \
        --arg dt "$SKILL" --arg schema "$SCHEMA" '
        split("\n") | map(select(length > 0) | split("\t")
            | {rule_id: .[0], section: .[1], verdict: .[2], seat: $seat, round: $round, doc_type: $dt}
              + (if $schema == "" then {} else {schema: $schema} end))' > "$BATCH" \
        || { ds_notice "could not build the telemetry batch for seat $seat"; continue; }
    echo "review-events: seat $seat $(jq 'length' "$BATCH") verdict(s)"
    ds_record "seat $seat's verdicts" "$DS_RECORD_SESSION" verdicts --file "$BATCH"
done < "$WORK/seats"
exit 0
