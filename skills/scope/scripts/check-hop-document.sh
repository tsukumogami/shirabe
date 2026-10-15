#!/usr/bin/env bash
# check-hop-document.sh -- does a /scope hop's document pass the document rules?
# Part of the scope skill
#
# A gate script: koto runs it as a command gate in /scope's hop states and in
# the fold, and holds the state until it exits 0. It runs the validator once
# per document and reports, as `::koto-finding::` lines, every finding the
# validator calls an error, plus the banned-word findings it reports only as a
# notice. docs/designs/DESIGN-scope-document-gates.md is the design.
#
# Usage:
#   check-hop-document.sh --topic <slug> --hop <brief|prd|design|plan|all>
#
# The documents, in this order (a hop takes its own; `all`, the fold's set,
# takes every one):
#   brief   docs/briefs/BRIEF-<topic>.md
#   prd     docs/prds/PRD-<topic>.md
#   design  docs/designs/DESIGN-<topic>.md, docs/designs/current/DESIGN-<topic>.md
#   plan    docs/plans/PLAN-<topic>.md
# A path that doesn't exist is skipped; with none present the gate passes and
# says so on stderr, because whether a hop landed is hop-complete.sh's question.
#
# What counts as a violation:
#   - every finding whose `severity` is "error", whatever its code, so a check
#     the validator adds or promotes later is held with no change here;
#   - an FC10 finding whose message starts with BANNED_PREFIX or TRUNC_PREFIX
#     below (a banned word, or the line saying banned-word findings were capped).
#     FC10's em-dash-density finding and every other notice are not violations.
# Each violation prints under the registry entry whose `aliases` hold its code
# (code_to_id below), with the validator's message, cut to 400 characters, as
# the detail. An error-level code with no entry, or an entry that doesn't
# resolve, is "could not decide": the gate never prints a finding it can't
# register.
#
# The banned words come from the plugin's own skills/writing-style/rules.yaml.
# The validator finds its rules by SHIRABE_RULES, else by walking up from the
# working directory, and with neither it checks no banned word and says
# nothing. So this script always sets SHIRABE_RULES to the plugin's file,
# ignoring any inherited value, and before checking a document it runs a
# canary: a one-line file holding the first banned word of the rules, which
# must come back through the same selector the documents go through. A
# validator that silently loaded no rules, or whose wording the prefixes no
# longer match, fails the canary instead of passing every document.
#
# Exit status (the gate scripts' shared convention):
#   0  every checked document passes, or none exists
#   1  at least one violation; one `::koto-finding::` line per violation
#   2  could not decide: a usage error; git, jq or shirabe missing; a shirabe
#      that resolves inside the repository; the rules file unreadable or with
#      no words; a failed canary; a validator exit other than 0 or 2; an
#      envelope that isn't a complete shirabe-validate/v1 verdict (including a
#      schema-skipped document, outcome `incomplete`); an exit 2 with no error
#      finding; a symlink, non-regular or empty file at a topic path, or one
#      resolving outside the repository; an error-level code with no registry
#      entry. No finding is printed for any document; the reason goes to stderr.
#
# Every document is decided before anything prints, so a partial list of
# findings never reads as the whole answer.
#
# Written for the bash 3.2 floor and deliberately without `set -e`: an
# unexpected failure must not exit 1 and read as a violation. Decisions read
# files written to a private temporary directory, never `printf | grep -q`
# under pipefail, which can fail when grep exits before printf has written.

set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN_ROOT=$(cd "$HERE/../../.." && pwd -P)
RULE_IDS="docs/required-fields docs/valid-status docs/status-matches-body docs/required-sections plan/issues-table-shape plan/issues-table-dependencies plan/outline-dependency-resolves docs/absorbed-declaration docs/absorbed-requirement-citation docs/no-stale-reference docs/upstream-resolves docs/upstream-direction docs/upstream-lifetime prose/banned-word docs/visibility-vision-sections docs/visibility-strategy-sections docs/private-only-type"

# The validator's FC10 message prefixes, from check_writing_style_with in
# crates/shirabe-validate/src/checks.rs. check-hop-document_test.sh pins both
# against the built validator.
BANNED_PREFIX='[FC10] writing-style banned word '
TRUNC_PREFIX='[FC10] writing-style findings truncated at '
MESSAGE_CAP=400

usage() {
    cat >&2 <<'EOF'
Usage: check-hop-document.sh --topic <slug> --hop <brief|prd|design|plan|all>

Exit 0 the documents pass, 1 a violation (findings on stdout), 2 could not decide.
EOF
}

undecided() {
    echo "check-hop-document: $*" >&2
    exit 2
}

# shellcheck source=../../../scripts/lib/rule-findings.sh
. "$PLUGIN_ROOT/scripts/lib/rule-findings.sh" || undecided "cannot load scripts/lib/rule-findings.sh"
# shellcheck source=../../../scripts/lib/declared-visibility.sh
. "$PLUGIN_ROOT/scripts/lib/declared-visibility.sh" || undecided "cannot load scripts/lib/declared-visibility.sh"

# --- arguments ----------------------------------------------------------------

TOPIC=""
HOP=""
while [ $# -gt 0 ]; do
    case "$1" in
        --topic)
            [ $# -ge 2 ] && [ -z "$TOPIC" ] || { usage; exit 2; }
            TOPIC=$2; shift 2 ;;
        --hop)
            [ $# -ge 2 ] && [ -z "$HOP" ] || { usage; exit 2; }
            HOP=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done
[ -n "$TOPIC" ] && [ -n "$HOP" ] || { usage; exit 2; }

# The slug composes every path below; koto constrains it, and it is checked
# again here because this script can be run by hand.
case "$TOPIC" in
    *[!a-z0-9-]*|-*|*-) undecided "--topic [$TOPIC] is not a topic slug" ;;
esac

B="docs/briefs/BRIEF-$TOPIC.md"
P="docs/prds/PRD-$TOPIC.md"
D1="docs/designs/DESIGN-$TOPIC.md"
D2="docs/designs/current/DESIGN-$TOPIC.md"
L="docs/plans/PLAN-$TOPIC.md"
case "$HOP" in
    brief)  PATHS="$B" ;;
    prd)    PATHS="$P" ;;
    design) PATHS="$D1 $D2" ;;
    plan)   PATHS="$L" ;;
    all)    PATHS="$B $P $D1 $D2 $L" ;;
    *) undecided "--hop [$HOP] is not brief, prd, design, plan or all" ;;
esac

# --- environment --------------------------------------------------------------

for tool in git jq shirabe awk; do
    command -v "$tool" >/dev/null 2>&1 || undecided "$tool is not on PATH"
done

ROOT=$(git rev-parse --show-toplevel) || undecided "not inside a git working tree"
cd "$ROOT" || undecided "cannot enter $ROOT"
ROOT_REAL=$(pwd -P)

# A validator planted inside the tree under review is refused: the document's
# own author could have written it.
SHIRABE_BIN=$(command -v shirabe)
SHIRABE_DIR=$(cd "$(dirname "$SHIRABE_BIN")" 2>/dev/null && pwd -P) \
    || undecided "cannot resolve the directory of $SHIRABE_BIN"
case "$SHIRABE_DIR/" in
    "$ROOT_REAL"/*) undecided "shirabe resolves inside the repository ($SHIRABE_DIR); refusing a validator from the tree under review" ;;
esac
SHIRABE_VERSION=$(shirabe --version | awk 'NR == 1 { print; exit }')
echo "check-hop-document: validator $SHIRABE_DIR/$(basename "$SHIRABE_BIN") (${SHIRABE_VERSION:-unknown version})" >&2

RULES_FILE="$PLUGIN_ROOT/skills/writing-style/rules.yaml"
[ -f "$RULES_FILE" ] && [ -r "$RULES_FILE" ] \
    || undecided "the writing-style rules $RULES_FILE are not readable"
awk '/^words:/ { found = 1; exit } END { exit found ? 0 : 1 }' "$RULES_FILE" \
    || undecided "the writing-style rules $RULES_FILE have no words: entry"
# Always the plugin's file: an inherited value (SHIRABE_RULES=/dev/null, say)
# would switch the banned-word check off without a word.
SHIRABE_RULES=$RULES_FILE
export SHIRABE_RULES

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-hop-document.XXXXXX") \
    || undecided "cannot create a temporary directory"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
trap 'cleanup; exit 2' INT TERM HUP

# select_violations <envelope>: one compact JSON object per violation.
select_violations() {
    jq -c --arg bw "$BANNED_PREFIX" --arg tr "$TRUNC_PREFIX" '
        .findings[]
        | select(.severity == "error"
                 or (.code == "FC10"
                     and ((.message | tostring | startswith($bw))
                          or (.message | tostring | startswith($tr)))))' "$1"
}

# complete_envelope <envelope>: a full verdict this script can read.
complete_envelope() {
    jq -e '
        .schema_version == "shirabe-validate/v1"
        and (.summary.outcome == "clean" or .summary.outcome == "violations")
        and (.findings | type == "array")
        and all(.findings[]; (.severity | type) == "string")' "$1" >/dev/null 2>&1
}

# --- the canary ---------------------------------------------------------------

# The first `- <term>` under the first `terms:` of the rules file.
CANARY_WORD=$(awk '
    /^[[:space:]]*terms:[[:space:]]*$/ { inside = 1; next }
    inside && /^[[:space:]]*-[[:space:]]+/ {
        line = $0
        sub(/^[[:space:]]*-[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        gsub(/^["'"'"']|["'"'"']$/, "", line)
        print line
        exit
    }' "$RULES_FILE")
[ -n "$CANARY_WORD" ] || undecided "no banned word could be read from $RULES_FILE"
printf 'Canary: we %s this.\n' "$CANARY_WORD" > "$WORK/canary.md" \
    || undecided "cannot write the canary"
(cd "$WORK" && shirabe validate --format json canary.md) > "$WORK/canary.json" 2> "$WORK/canary.err"
rc=$?
[ "$rc" -eq 0 ] || undecided "the canary run exited $rc: $(tail -n 1 "$WORK/canary.err")"
select_violations "$WORK/canary.json" > "$WORK/canary.hits" 2>/dev/null \
    || undecided "cannot read the canary run's output"
[ -s "$WORK/canary.hits" ] \
    || undecided "the validator reported no banned-word finding for the canary word [$CANARY_WORD]; its rules didn't load or its message wording changed"

# --- the documents ------------------------------------------------------------

VIS=$(declared_visibility)
set --
[ -z "$VIS" ] || set -- "--visibility=$VIS"

: > "$WORK/checked"
n=0
for p in $PATHS; do
    if [ ! -e "$p" ] && [ ! -L "$p" ]; then
        continue
    fi
    [ -L "$p" ] && undecided "$p is a symlink"
    [ -f "$p" ] || undecided "$p is not a regular file"
    [ -s "$p" ] || undecided "$p is empty"
    dir_real=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P) || undecided "cannot resolve the directory of $p"
    case "$dir_real/" in
        "$ROOT_REAL"/*) ;;
        *) undecided "$p resolves outside the repository" ;;
    esac
    n=$((n + 1))
    shirabe validate --format json "$@" -- "$p" > "$WORK/$n.json" 2> "$WORK/$n.err"
    rc=$?
    case "$rc" in
        0|2) ;;
        *) undecided "shirabe validate exited $rc on $p: $(tail -n 1 "$WORK/$n.err")" ;;
    esac
    complete_envelope "$WORK/$n.json" \
        || undecided "shirabe validate gave no complete verdict on $p (a schema-skipped document, or output this script can't read)"
    errors=$(jq '[.findings[] | select(.severity == "error")] | length' "$WORK/$n.json") \
        || undecided "cannot count the errors on $p"
    if [ "$rc" -eq 2 ] && [ "$errors" -eq 0 ]; then
        undecided "shirabe validate exited 2 on $p but reported no error"
    fi
    if [ "$rc" -eq 0 ] && [ "$errors" -ne 0 ]; then
        undecided "shirabe validate exited 0 on $p but reported $errors error(s)"
    fi
    select_violations "$WORK/$n.json" >> "$WORK/hits" 2>/dev/null \
        || undecided "cannot read shirabe validate's output on $p"
    printf '%s\n' "$p" >> "$WORK/checked"
done

if [ "$n" -eq 0 ]; then
    echo "check-hop-document: no document at any of: $PATHS" >&2
    exit 0
fi

# code_to_id <code>: the registry entry whose aliases hold <code>.
code_to_id() {
    case "$1" in
        FC01) echo docs/required-fields ;;
        FC02) echo docs/valid-status ;;
        FC03) echo docs/status-matches-body ;;
        FC04) echo docs/required-sections ;;
        FC05) echo plan/issues-table-shape ;;
        FC06) echo plan/issues-table-dependencies ;;
        FC10) echo prose/banned-word ;;
        FC17) echo plan/outline-dependency-resolves ;;
        FC18) echo docs/absorbed-declaration ;;
        FC19) echo docs/absorbed-requirement-citation ;;
        FC20) echo docs/no-stale-reference ;;
        R6)   echo docs/upstream-resolves ;;
        R7)   echo docs/visibility-vision-sections ;;
        R8)   echo docs/visibility-strategy-sections ;;
        R9)   echo docs/private-only-type ;;
        R10)  echo docs/upstream-direction ;;
        R11)  echo docs/upstream-lifetime ;;
        *)    echo "" ;;
    esac
}

# Map every code, and resolve the entries the findings will print under, before
# printing anything. Only those entries are resolved: each resolution reads the
# registry and git, about half a second apiece, and resolving all seventeen on
# every gate run would put a clean hop near koto's 30-second command limit.
# check-rule-registry.sh in CI is what keeps every anchor resolvable.
[ -f "$WORK/hits" ] || : > "$WORK/hits"
: > "$WORK/ids"
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    code=$(printf '%s' "$hit" | jq -r '.code // ""')
    id=$(code_to_id "$code")
    [ -n "$id" ] \
        || undecided "the validator reported error-level code [$code], which no registry entry aliases"
    printf '%s\n' "$id" >> "$WORK/ids"
done < "$WORK/hits"
for id in $(sort -u "$WORK/ids"); do
    rf_require "$id"
done

printed=0
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    code=$(printf '%s' "$hit" | jq -r '.code // ""')
    file=$(printf '%s' "$hit" | jq -r '.file // ""')
    line=$(printf '%s' "$hit" | jq -r 'if .line == null then "" else (.line | tostring) end')
    msg=$(printf '%s' "$hit" | jq -r '.message // ""')
    if [ "${#msg}" -gt "$MESSAGE_CAP" ]; then
        msg="${msg:0:$MESSAGE_CAP}..."
    fi
    rf_finding "$(code_to_id "$code")" "$msg" "$file" "$line"
    printed=$((printed + 1))
done < "$WORK/hits"

checked=$(awk 'NR > 1 { printf ", " } { printf "%s", $0 }' "$WORK/checked")
if [ "$printed" -gt 0 ]; then
    echo "check-hop-document: $printed violation(s) in $checked" >&2
    exit 1
fi
echo "check-hop-document: $checked pass" >&2
exit 0
