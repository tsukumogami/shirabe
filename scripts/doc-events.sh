#!/usr/bin/env bash
# doc-events.sh -- record, as telemetry, which required sections of a document
# a commit wrote, and which rules a fix answered.
#
# Usage:
#   doc-events.sh sections --doc <path> --format <f> [--since <commit>] [--skill <s>]
#   doc-events.sh fix --doc <path> --format <f> --answers check_fail [--skill <s>]
#   doc-events.sh fix --doc <path> --format <f> --answers jury_fail [--round <n>] [--skill <s>]
#
#   --doc      the document, resolved as doc-check.sh resolves it: symlinks
#              followed, it must be the format's canonical path under the
#              repository's docs/; the topic is the one that path names
#   --format   brief, prd, design, plan, vision, strategy or roadmap
#   --since    a full hexadecimal commit id (40 or 64 characters)
#   --answers  check_fail: the fix answers the last doc-check.sh failure;
#              jury_fail: the fix answers a jury round's FAIL verdicts
#   --round    the jury round the fix answers, 1 to 50 (jury_fail only);
#              default: the round review/round holds in the skill's session
#   --skill    the skill whose <skill>-<topic> session holds
#              work/doc-check.json and the jury's keys; default: the
#              format's own skill
#
# sections: diffs the document's `##` sections between <commit> and HEAD and,
#   for each required section of the format (references/doc-check-phases.json)
#   that is new at HEAD or whose body changed, prints
#     doc-events: section <slug> first|rewrite
#   and records
#     koto review record <session> section-written --doc-format <f> --section <slug> --write first|rewrite
#   Unchanged sections and sections the format doesn't require are ignored.
#   With no --since it diffs from the commit work/doc-check.json last recorded
#   sections at; with none recorded every present required section is
#   `first`. Afterwards it records HEAD as that commit.
#
# fix: reads work/doc-check.json and, for each rule the last check failed,
#   writes one entry per (rule, section) the failure is in, with check_rule
#   the failing rule itself:
#     doc-events: fix <rule-id> <section slug>
#     koto review record <session> fix --doc-format <f> --answers check_fail --file <batch>
#   The section is the one the check named (a missing required section, or a
#   section-reading rule's section), else the required section around the
#   finding's line in the document as the check saw it, else `other`. With no
#   failure it writes none.
#
# fix --answers jury_fail: reads each seat's verdict file the skill ingested
#   as `research/<pinned file>` in the <skill>-<topic> session (the seat list
#   and file names of scripts/lib/review-verdicts.sh), parses its last
#   review-verdicts block with that library, and writes one entry per distinct
#   (rule, section) FAIL, rs-verdict-missing aside, with check_rule the rule's
#   `held_by` in references/rule-registry.json, else none:
#     doc-events: fix <rule-id> <section slug> <check rule>
#     koto review record <session> fix --doc-format <f> --answers jury_fail --round <n> --file <batch>
#   At most 200 entries. With no round recorded, or no FAIL, it writes none.
#
# Telemetry goes to the session `skill-session.sh dispatch read` resolves,
# best effort: each failed call prints one notice on stderr and changes
# nothing else. Section events carry the slug of a required section, never
# heading text.
#
# Exit status: 0 done (whether or not anything was recorded); 2 refused (a
# usage error, an input outside its closed set or pattern, a --doc that isn't
# the canonical path, a --since that names no commit, git or jq missing).
#
# Environment: KOTO_BIN, the koto to run (default `koto` on PATH).
#
# Written for the bash 3.2 floor and without `set -e`.

set -u

PROG=doc-events
HERE=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN_ROOT=$(cd "$HERE/.." && pwd -P)
KOTO="${KOTO_BIN:-koto}"
START_DIR=$(pwd -P)

usage() {
    cat >&2 <<'EOF'
Usage: doc-events.sh sections --doc <path> --format <f> [--since <commit>] [--skill <s>]
       doc-events.sh fix --doc <path> --format <f> --answers check_fail [--skill <s>]
       doc-events.sh fix --doc <path> --format <f> --answers jury_fail [--round <n>] [--skill <s>]
EOF
    exit 2
}

refuse() {
    echo "doc-events: refused: $*" >&2
    exit 2
}

# shellcheck source=lib/doc-session.sh
. "$PLUGIN_ROOT/scripts/lib/doc-session.sh" || refuse "cannot load scripts/lib/doc-session.sh"
# shellcheck source=lib/review-verdicts.sh
. "$PLUGIN_ROOT/scripts/lib/review-verdicts.sh" || refuse "cannot load scripts/lib/review-verdicts.sh"

# --- arguments ----------------------------------------------------------------

[ $# -ge 1 ] || usage
CMD=$1
shift
case "$CMD" in
    sections|fix) ;;
    *) usage ;;
esac
DOC_ARG="" FORMAT="" SINCE="" ANSWERS="" SKILL="" ROUND=""
set_once() { # <current value> <name>
    [ -z "$1" ] || { echo "doc-events: $2 given twice" >&2; usage; }
}
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$CMD:$1" in
        *:--doc) set_once "$DOC_ARG" --doc; DOC_ARG=$2 ;;
        *:--format) set_once "$FORMAT" --format; FORMAT=$2 ;;
        *:--skill) set_once "$SKILL" --skill; SKILL=$2 ;;
        sections:--since) set_once "$SINCE" --since; SINCE=$2 ;;
        fix:--answers) set_once "$ANSWERS" --answers; ANSWERS=$2 ;;
        fix:--round) set_once "$ROUND" --round; ROUND=$2 ;;
        *) usage ;;
    esac
    shift 2
done
[ -n "$DOC_ARG" ] && [ -n "$FORMAT" ] || usage
[ "$CMD" = sections ] || [ -n "$ANSWERS" ] || usage

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || refuse "$tool is not on PATH"
done

case " $DS_FORMATS " in
    *" $FORMAT "*) ;;
    *) refuse "--format is not one of: $DS_FORMATS" ;;
esac
[ -n "$SKILL" ] || SKILL=$FORMAT
[[ "$SKILL" =~ $DS_RE_SKILL ]] || refuse "--skill must match $DS_RE_SKILL"
if [ "$CMD" = fix ]; then
    case "$ANSWERS" in
        check_fail|jury_fail) ;;
        *) refuse "--answers must be check_fail or jury_fail" ;;
    esac
    if [ -n "$ROUND" ]; then
        [ "$ANSWERS" = jury_fail ] || refuse "--round is for --answers jury_fail only"
        [[ "$ROUND" =~ ^[1-9][0-9]?$ ]] && [ "$ROUND" -le 50 ] || refuse "--round must be a whole number from 1 to 50"
    fi
fi
if [ -n "$SINCE" ]; then
    [[ "$SINCE" =~ ^[0-9a-f]{40}$ ]] || [[ "$SINCE" =~ ^[0-9a-f]{64}$ ]] \
        || refuse "--since must be a full hexadecimal commit id"
fi
[ -r "$DS_PHASES" ] || refuse "cannot read $DS_PHASES"

# --- the repository and the document ------------------------------------------

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || refuse "not inside a git working tree"
cd "$ROOT" || refuse "cannot enter the repository root"
ROOT_REAL=$(pwd -P)

ds_resolve_doc "$START_DIR" "$DOC_ARG" || refuse "$DS_REASON"
DOC=$DS_DOC
TOPIC=$(ds_topic_of "$FORMAT" "$DOC")
[ -n "$TOPIC" ] && [[ "$TOPIC" =~ $DS_RE_TOPIC ]] \
    || refuse "--doc resolves to $DOC, not a canonical $FORMAT path"
canonical=0
while IFS= read -r c; do
    [ "$c" = "$DOC" ] && canonical=1
done <<EOF
$(ds_canonical_paths "$FORMAT" "$TOPIC")
EOF
[ "$canonical" -eq 1 ] || refuse "--doc resolves to $DOC, not a canonical $FORMAT path"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/doc-events.XXXXXX") || refuse "cannot create a private scratch directory"
chmod 700 "$WORK" || refuse "cannot make the scratch directory private"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
trap 'cleanup; exit 2' INT TERM HUP

STATE_SESSION="$SKILL-$TOPIC"
ds_state_read "$STATE_SESSION" "$WORK/state.json"
jq -r --arg f "$FORMAT" '.formats[$f].required_sections[]' "$DS_PHASES" > "$WORK/required" \
    || refuse "cannot read the required sections of $FORMAT"

# sections_of <file>: one `<name>\t<body>` line per `## ` section outside code
# fences, the first of a repeated name only. The body's newlines, tabs and
# backslashes are escaped, so a body is one line and two bodies compare as
# strings.
sections_of() {
    awk '
        function esc(s) { gsub(/\\/, "\\\\", s); gsub(/\t/, "\\t", s); return s }
        function flush() { if (name != "" && !(name in seen)) { seen[name] = 1; printf "%s\t%s\n", name, body } }
        /^(```|~~~)/ { fence = !fence }
        !fence && /^## / {
            flush()
            name = substr($0, 4); sub(/[ \t]+$/, "", name); gsub(/\t/, " ", name)
            body = ""
            next
        }
        name != "" { body = body esc($0) "\\n" }
        END { flush() }' "$1"
}

# --- sections -----------------------------------------------------------------

if [ "$CMD" = sections ]; then
    HEAD=$(git rev-parse --verify --quiet --end-of-options 'HEAD^{commit}') || refuse "the repository has no HEAD commit"
    if [ -z "$SINCE" ]; then
        SINCE=$(jq -r --arg doc "$DOC" 'if .doc == $doc then (.sections_commit // "") else "" end' "$WORK/state.json")
        [[ "$SINCE" =~ ^[0-9a-f]{40}$ ]] || [[ "$SINCE" =~ ^[0-9a-f]{64}$ ]] || SINCE=""
    fi
    : > "$WORK/old.md"
    if [ -n "$SINCE" ]; then
        git rev-parse --verify --quiet --end-of-options "$SINCE^{commit}" >/dev/null \
            || refuse "--since names no commit in this repository"
        git show --end-of-options "$SINCE:$DOC" > "$WORK/old.md" 2>/dev/null || : > "$WORK/old.md"
    fi
    git show --end-of-options "HEAD:$DOC" > "$WORK/new.md" 2>/dev/null || : > "$WORK/new.md"
    sections_of "$WORK/old.md" > "$WORK/old.sec"
    sections_of "$WORK/new.md" > "$WORK/new.sec"
    awk -F'\t' '
        FILENAME == ARGV[1] { req[$0] = 1; next }
        FILENAME == ARGV[2] { old[$1] = $2; had[$1] = 1; next }
        ($1 in req) {
            if (!($1 in had)) print $1 "\tfirst"
            else if (old[$1] != $2) print $1 "\trewrite"
        }' "$WORK/required" "$WORK/old.sec" "$WORK/new.sec" > "$WORK/written"
    if [ -s "$WORK/written" ]; then
        ds_record_session "$SKILL" "$TOPIC"
    fi
    while IFS='	' read -r name write; do
        [ -n "$name" ] || continue
        slug=$(ds_slug "$name")
        echo "doc-events: section $slug $write"
        ds_record "section $slug" "$DS_RECORD_SESSION" section-written \
            --doc-format "$FORMAT" --section "$slug" --write "$write"
    done < "$WORK/written"
    jq -c --arg doc "$DOC" --arg f "$FORMAT" --arg h "$HEAD" '
        (if .doc == $doc then . else {} end)
        + {schema: "doc-check-state/v1", doc: $doc, format: $f, sections_commit: $h}' \
        "$WORK/state.json" > "$WORK/state.new" || refuse "cannot build the check state"
    ds_state_write "$STATE_SESSION" "$WORK/state.new"
    exit 0
fi

# --- fix --answers jury_fail ----------------------------------------------------

if [ "$ANSWERS" = jury_fail ]; then
    ENTRY_CAP=200
    REGISTRY="$PLUGIN_ROOT/references/rule-registry.json"
    if [ -z "$ROUND" ]; then
        if command -v "$KOTO" >/dev/null 2>&1; then
            ROUND=$("$KOTO" context get "$STATE_SESSION" review/round 2>/dev/null | head -n 1 | tr -d '[:space:]')
        fi
        [[ "$ROUND" =~ ^[1-9][0-9]?$ ]] && [ "$ROUND" -le 50 ] || ROUND=""
    fi
    if [ -z "$ROUND" ]; then
        ds_notice "no jury round is recorded in $STATE_SESSION; no fix entry written"
        exit 0
    fi
    {
        jq -r --arg f "$FORMAT" '.formats[$f].required_sections[]' "$DS_PHASES" | while IFS= read -r s; do ds_slug "$s"; echo; done
        printf 'frontmatter\ndocument\n'
    } | sed '/^$/d' | sort -u > "$WORK/sections"
    : > "$WORK/fails"
    rv_seats_of "$SKILL" > "$WORK/seats"
    [ -s "$WORK/seats" ] || rv_seats_of "$FORMAT" > "$WORK/seats"
    while IFS='	' read -r seat file; do
        [ -n "$seat" ] || continue
        if ! command -v "$KOTO" >/dev/null 2>&1 \
            || ! "$KOTO" context get "$STATE_SESSION" "research/$file" > "$WORK/seat.md" 2>/dev/null; then
            ds_notice "seat $seat: no verdict key research/$file in $STATE_SESSION"
            continue
        fi
        rv_block "$WORK/seat.md" "$WORK/block"
        if [ ! -s "$WORK/block" ]; then
            ds_notice "seat $seat: no review-verdicts block"
            continue
        fi
        if ! rv_entries "$WORK/block" "$WORK/sections" "$seat" "$WORK/valid" "$FORMAT"; then
            ds_notice "seat $seat: the review-verdicts block is not a JSON array"
            continue
        fi
        awk -F'\t' '$3 == "FAIL" && $1 != "rs-verdict-missing" { print $1 "\t" $2 }' "$WORK/valid" >> "$WORK/fails"
    done < "$WORK/seats"
    sort -u "$WORK/fails" | head -n "$ENTRY_CAP" > "$WORK/fails.u"
    if [ ! -s "$WORK/fails.u" ]; then
        exit 0
    fi
    BATCH=$(mktemp "$WORK/fix.XXXXXX") || { ds_notice "could not create the telemetry batch; the fix was not recorded"; exit 0; }
    jq -R -s -c --slurpfile reg "$REGISTRY" '
        ($reg[0].rules | map({(.id): (.held_by // "none")}) | add) as $held
        | split("\n") | map(select(length > 0) | split("\t")
          | {rule_id: .[0], section: .[1], check_rule: ($held[.[0]] // "none")})' "$WORK/fails.u" > "$BATCH" \
        || { ds_notice "could not build the telemetry batch; the fix was not recorded"; exit 0; }
    jq -r '.[] | "doc-events: fix \(.rule_id) \(.section) \(.check_rule)"' "$BATCH"
    ds_record_session "$SKILL" "$TOPIC"
    ds_record "the fix" "$DS_RECORD_SESSION" fix --doc-format "$FORMAT" --answers jury_fail --round "$ROUND" --file "$BATCH"
    exit 0
fi

# --- fix --answers check_fail ----------------------------------------------------

if ! jq -e --arg doc "$DOC" '.doc == $doc and (.last.outcomes | type) == "array"' "$WORK/state.json" >/dev/null 2>&1; then
    ds_notice "no check of $DOC is recorded in $STATE_SESSION; no fix entry written"
    exit 0
fi
COMMIT=$(jq -r '.last.commit // ""' "$WORK/state.json")
: > "$WORK/seen.md"
if [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || [[ "$COMMIT" =~ ^[0-9a-f]{64}$ ]]; then
    git show --end-of-options "$COMMIT:$DOC" > "$WORK/seen.md" 2>/dev/null || : > "$WORK/seen.md"
fi
[ -s "$WORK/seen.md" ] || { [ -f "$DOC" ] && cp "$DOC" "$WORK/seen.md"; }

# heading_at <line>: the `## ` heading above <line> in the document as the
# check saw it, outside code fences, or nothing.
heading_at() {
    awk -v n="$1" '
        NR > n { exit }
        /^(```|~~~)/ { fence = !fence }
        !fence && /^## / { h = substr($0, 4); sub(/[ \t]+$/, "", h) }
        END { print h }' "$WORK/seen.md"
}

# headings_of_lines: stdin holds line numbers; prints the heading above each.
headings_of_lines() {
    local ln
    while IFS= read -r ln; do
        case "$ln" in
            ''|*[!0-9]*) continue ;;
        esac
        heading_at "$ln"
    done
}

: > "$WORK/pairs"
while IFS= read -r o; do
    [ -n "$o" ] || continue
    rule=$(printf '%s' "$o" | jq -r '.rule_id')
    jq -e --arg f "$FORMAT" --arg r "$rule" '.formats[$f].rules | index($r)' "$DS_PHASES" >/dev/null 2>&1 || continue
    secs=$(printf '%s' "$o" | jq -r '.sections[]?')
    if [ -z "$secs" ]; then
        secs=$(printf '%s' "$o" | jq -r '.lines[]?' | headings_of_lines)
    fi
    [ -n "$secs" ] || secs=other
    printf '%s\n' "$secs" | while IFS= read -r s; do
        if [ "$s" != other ] && grep -qxF -- "$s" "$WORK/required"; then
            printf '%s\t%s\n' "$rule" "$(ds_slug "$s")"
        else
            printf '%s\tother\n' "$rule"
        fi
    done >> "$WORK/pairs"
done <<EOF
$(jq -c '.last.outcomes[] | select(.outcome == "fail")' "$WORK/state.json")
EOF

sort -u "$WORK/pairs" > "$WORK/pairs.u"
if [ ! -s "$WORK/pairs.u" ]; then
    exit 0
fi
while IFS='	' read -r rule slug; do
    echo "doc-events: fix $rule $slug"
done < "$WORK/pairs.u"
BATCH=$(mktemp "$WORK/fix.XXXXXX") || { ds_notice "could not create the telemetry batch; the fix was not recorded"; exit 0; }
jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")
    | {rule_id: .[0], section: .[1], check_rule: .[0]})' "$WORK/pairs.u" > "$BATCH" \
    || { ds_notice "could not build the telemetry batch; the fix was not recorded"; exit 0; }
ds_record_session "$SKILL" "$TOPIC"
ds_record "the fix" "$DS_RECORD_SESSION" fix --doc-format "$FORMAT" --answers check_fail --file "$BATCH"
exit 0
