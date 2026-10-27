#!/usr/bin/env bash
# check-hop-document.sh -- does a /scope hop's document pass the document rules?
# Part of the scope skill
#
# A gate script: koto runs it as a command gate in /scope's hop states and in
# the fold, and holds the state until it exits 0. It runs the validator once
# per document and reports, as `::koto-finding::` lines, every finding the
# validator calls an error, plus the banned-word findings it reports only as a
# notice. docs/designs/current/DESIGN-scope-document-gates.md is the design.
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
#   - an FC10 finding whose message starts with DV_BANNED_PREFIX or
#     DV_TRUNC_PREFIX in scripts/lib/doc-validate.sh (a banned word, or the
#     line saying banned-word findings were capped).
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
#   0  every checked document passes, or none exists, or every violation is
#      of a rule below the `block` stage (printed, at its stage's level)
#   1  at least one violation of a rule at `block`; one `::koto-finding::`
#      line per violation, a line on stderr saying how to dispute one, and,
#      when the template supplies its context, the escalation ladder's
#      output on stderr (rf_deliver, scripts/lib/rule-findings.sh)
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
# The validator call, its envelope, the in-repository refusal, the rules pin,
# the canary and the file checks, shared with scripts/doc-check.sh.
# shellcheck source=../../../scripts/lib/doc-validate.sh
. "$PLUGIN_ROOT/scripts/lib/doc-validate.sh" || undecided "cannot load scripts/lib/doc-validate.sh"

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
# own author could have written it. Symlinks are followed to the file they name
# (a link outside the tree to a binary inside it is still inside), with a hop
# limit so a link loop can't hang the gate.
dv_resolve_validator "$ROOT_REAL" || undecided "$DV_REASON"
# The path only: skills/scope/requires.tsv may declare shirabe subcommands and
# nothing else, so the gate doesn't call `shirabe --version`.
echo "check-hop-document: validator $DV_SHIRABE" >&2

# Always the plugin's file: an inherited value (SHIRABE_RULES=/dev/null, say)
# would switch the banned-word check off without a word.
dv_pin_rules "$PLUGIN_ROOT" || undecided "$DV_REASON"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-hop-document.XXXXXX") \
    || undecided "cannot create a temporary directory"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
trap 'cleanup; exit 2' INT TERM HUP

# --- the canary ---------------------------------------------------------------

dv_canary "$WORK" || undecided "$DV_REASON"

# --- the documents ------------------------------------------------------------

# With no declared visibility the flag is left off, so the validator detects
# visibility as it does in CI.
VIS=$(declared_visibility)

: > "$WORK/checked"
n=0
for p in $PATHS; do
    if [ ! -e "$p" ] && [ ! -L "$p" ]; then
        continue
    fi
    dv_check_file "$p" "$ROOT_REAL" || undecided "$DV_REASON"
    n=$((n + 1))
    dv_validate "$p" "$WORK/$n.json" "$WORK/$n.err" "$VIS" || undecided "$DV_REASON"
    dv_select_violations "$WORK/$n.json" >> "$WORK/hits" 2>/dev/null \
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
# printing anything. Only those entries are resolved: each resolution runs
# rule-registry.sh (reference, summary and stage in one call), and on a busy
# shared host resolving all seventeen up front made a clean PLAN check take 19
# seconds, against about 3 this way, under koto's 30-second command limit.
# rf_require caches each rule's stage as it resolves, so resolving late still
# prints every finding at its stage.
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

while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    code=$(printf '%s' "$hit" | jq -r '.code // ""')
    file=$(printf '%s' "$hit" | jq -r '.file // ""')
    line=$(printf '%s' "$hit" | jq -r 'if .line == null then "" else (.line | tostring) end')
    msg=$(printf '%s' "$hit" | jq -r '.message // ""')
    if [ "${#msg}" -gt "$MESSAGE_CAP" ]; then
        msg="${msg:0:$((MESSAGE_CAP - 3))}..."
    fi
    rf_finding "$(code_to_id "$code")" "$msg" "$file" "$line"
done < "$WORK/hits"

checked=$(awk 'NR > 1 { printf ", " } { printf "%s", $0 }' "$WORK/checked")
# Only a finding of a rule at block holds the hop; one below block printed at
# its stage's level and leaves the gate passing, and one at retired printed
# nothing, so RF_PRINTED, not the number of violations, says whether any
# finding is above this line.
if [ "$RF_BLOCKING" -gt 0 ]; then
    echo "check-hop-document: $RF_BLOCKING violation(s) in $checked" >&2
    rf_dispute_hint
    rf_deliver
    exit 1
fi
if [ "$RF_PRINTED" -gt 0 ]; then
    echo "check-hop-document: $checked pass; no violation is of a rule at block" >&2
else
    echo "check-hop-document: $checked pass" >&2
fi
exit 0
