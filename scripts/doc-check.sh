#!/usr/bin/env bash
# doc-check.sh -- run the document checks on one document, at one moment of a
# skill's run, and say per rule whether it passed, failed, isn't ready, or
# couldn't be decided.
#
# A skill runs it before every jury round, after every fix, and after /plan
# writes its PLAN. It covers the seven formats (brief, prd, design, plan,
# vision, strategy, roadmap). It is not a koto gate: it holds the skill's step
# only through its exit code, and only on a rule at the `block` stage.
#
# Usage:
#   doc-check.sh --doc <path> --format <f> --moment <m> --phase <p>
#                --topic <t> --skill <s>
#
#   --doc     the document; it must resolve, symlinks followed, to the
#             canonical path for --format and --topic under the repository's
#             docs/ (references/doc-check-phases.json lists them)
#   --format  brief, prd, design, plan, vision, strategy or roadmap
#   --moment  pre_jury, post_fix or post_create
#   --phase   the skill phase the step is in; a phase the format lists in
#             references/doc-check-phases.json
#   --topic   the topic slug (skill-session's topic pattern)
#   --skill   the skill running the check (skill-session's skill pattern);
#             its <skill>-<topic> session holds work/doc-check.json
#
# It runs `shirabe validate --format json --visibility=<v>` once, with the
# visibility the repository declares in its `## Repo Visibility:` header
# (private when it declares none), and maps each finding code to its
# registered rule through the registry's aliases. For each check-held rule of
# the format (the phase map's `rules`) it writes one outcome:
#
#   not_ready  the document doesn't exist (every rule), or the rule reads a
#              required section the phase hasn't reached: a section-reading
#              rule's sections (`rule_sections`), or for docs/required-sections
#              a missing section outside the phase's reached list
#   fail       a violation (an error-level finding, or a banned word) maps to
#              the rule and the not-ready test doesn't apply; a reached
#              required section that is missing fails
#   error      no validator verdict (a missing or untrusted validator, a failed
#              canary, a run that gave no complete envelope), or a code that
#              maps to no check-held rule (a `defect` line on stderr names it),
#              which turns every rule that would have passed into error
#   pass       otherwise
#
# Only this script declares not_ready, from two facts it establishes itself:
# the file's absence, and the phase map. It reads no line of the document and
# parses only the validator's JSON fields.
#
# Standard output:
#   ::koto-not-ready::                      first, when any rule is not_ready
#   doc-check: <rule-id> <outcome>          one per check-held rule
#   ::koto-finding::{...}                   one per violation of a rule at
#                                           block (rule_id, rule_ref, path,
#                                           line, message cut to 400
#                                           characters), only on exit 1
#   doc-check: unresolved after 3 cycles    on the fourth failing check in a
#                                           row at one moment
# The validator's message is the only validator text printed, and only inside
# a finding line, with control characters, line and paragraph separators and
# bidirectional controls replaced; a document can't start a line of its own.
#
# State: work/doc-check.json in the <skill>-<topic> session holds the last
# check (moment, document commit, outcomes, whether a block rule failed), a
# per-moment count of failing checks in a row, and the commit
# doc-events.sh last recorded sections at. A failing check is one that exits
# 1; any other check sets its moment's count back to 0. At pre_jury, when the
# last check was a post_fix check on the same document commit with no block
# failure, it records nothing and exits 0: that check serves as the round's
# pre-jury check.
#
# Telemetry: the outcomes go, best effort, to
#   koto review record rule-checks <session> --doc-format <f> --moment <m> --file <batch>
# on the session `skill-session.sh dispatch read` resolves (the chain's parent
# when one dispatched this skill, else <skill>-<topic>), entries
# {"rule_id","outcome"}, dropping any rule id the registry doesn't hold. A
# call that fails prints one notice on stderr and changes nothing else.
#
# Exit status:
#   0  no rule at block failed (not_ready, error, and warn- or shadow-stage
#      failures included), or a pre_jury check served by the last post_fix one
#   1  a rule at block failed
#   2  refused: a usage error, an input outside its closed set or pattern, a
#      --doc that isn't the format's canonical path, git or jq missing, or a
#      registry entry that doesn't resolve
#
# Environment: KOTO_BIN, the koto to run (default `koto` on PATH).
#
# Written for the bash 3.2 floor and deliberately without `set -e`: an
# unexpected failure must not exit 1 and read as a block failure.

set -u

PROG=doc-check
HERE=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN_ROOT=$(cd "$HERE/.." && pwd -P)
KOTO="${KOTO_BIN:-koto}"
START_DIR=$(pwd -P)
MESSAGE_CAP=400
RULE_IDS="docs/required-fields docs/valid-status docs/status-matches-body docs/required-sections plan/issues-table-shape plan/issues-table-dependencies plan/outline-dependency-resolves docs/absorbed-declaration docs/absorbed-requirement-citation docs/no-stale-reference docs/upstream-resolves docs/upstream-direction docs/upstream-lifetime prose/banned-word docs/visibility-vision-sections docs/visibility-strategy-sections"

usage() {
    cat >&2 <<'EOF'
Usage: doc-check.sh --doc <path> --format <brief|prd|design|plan|vision|strategy|roadmap>
                    --moment <pre_jury|post_fix|post_create> --phase <p>
                    --topic <slug> --skill <skill>

Exit 0 no block-stage rule failed, 1 one did (findings on stdout), 2 refused.
EOF
    exit 2
}

undecided() {
    echo "doc-check: refused: $*" >&2
    exit 2
}

# shellcheck source=lib/rule-findings.sh
. "$PLUGIN_ROOT/scripts/lib/rule-findings.sh" || undecided "cannot load scripts/lib/rule-findings.sh"
# shellcheck source=lib/declared-visibility.sh
. "$PLUGIN_ROOT/scripts/lib/declared-visibility.sh" || undecided "cannot load scripts/lib/declared-visibility.sh"
# shellcheck source=lib/doc-validate.sh
. "$PLUGIN_ROOT/scripts/lib/doc-validate.sh" || undecided "cannot load scripts/lib/doc-validate.sh"
# shellcheck source=lib/doc-session.sh
. "$PLUGIN_ROOT/scripts/lib/doc-session.sh" || undecided "cannot load scripts/lib/doc-session.sh"

# --- arguments ----------------------------------------------------------------

DOC_ARG="" FORMAT="" MOMENT="" PHASE="" TOPIC="" SKILL=""
set_once() { # <current value> <name>
    [ -z "$1" ] || { echo "doc-check: $2 given twice" >&2; usage; }
}
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$1" in
        --doc) set_once "$DOC_ARG" --doc; DOC_ARG=$2 ;;
        --format) set_once "$FORMAT" --format; FORMAT=$2 ;;
        --moment) set_once "$MOMENT" --moment; MOMENT=$2 ;;
        --phase) set_once "$PHASE" --phase; PHASE=$2 ;;
        --topic) set_once "$TOPIC" --topic; TOPIC=$2 ;;
        --skill) set_once "$SKILL" --skill; SKILL=$2 ;;
        *) usage ;;
    esac
    shift 2
done
[ -n "$DOC_ARG" ] && [ -n "$FORMAT" ] && [ -n "$MOMENT" ] && [ -n "$PHASE" ] \
    && [ -n "$TOPIC" ] && [ -n "$SKILL" ] || usage

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || undecided "$tool is not on PATH"
done

case " $DS_FORMATS " in
    *" $FORMAT "*) ;;
    *) undecided "--format is not one of: $DS_FORMATS" ;;
esac
case "$MOMENT" in
    pre_jury|post_fix|post_create) ;;
    *) undecided "--moment is not pre_jury, post_fix or post_create" ;;
esac
[[ "$TOPIC" =~ $DS_RE_TOPIC ]] || undecided "--topic must match $DS_RE_TOPIC"
[[ "$SKILL" =~ $DS_RE_SKILL ]] || undecided "--skill must match $DS_RE_SKILL"
[[ "$PHASE" =~ ^[0-9]{1,2}$ ]] || undecided "--phase must be a phase number"
[ -r "$DS_PHASES" ] || undecided "cannot read $DS_PHASES"
jq -e --arg f "$FORMAT" --arg p "$PHASE" '.formats[$f].phases | has($p)' "$DS_PHASES" >/dev/null 2>&1 \
    || undecided "--phase $PHASE is not a phase the $FORMAT format lists in references/doc-check-phases.json"

# --- the repository and the document ------------------------------------------

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || undecided "not inside a git working tree"
cd "$ROOT" || undecided "cannot enter the repository root"
ROOT_REAL=$(pwd -P)

ds_resolve_doc "$START_DIR" "$DOC_ARG" || undecided "$DS_REASON"
DOC=$DS_DOC
ds_canonical_paths "$FORMAT" "$TOPIC" > /dev/null 2>&1 || undecided "cannot read the canonical paths"
canonical=0
while IFS= read -r c; do
    [ "$c" = "$DOC" ] && canonical=1
done <<EOF
$(ds_canonical_paths "$FORMAT" "$TOPIC")
EOF
[ "$canonical" -eq 1 ] || undecided "--doc resolves to $DOC, not the canonical $FORMAT path for topic $TOPIC"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/doc-check.XXXXXX") || undecided "cannot create a private scratch directory"
chmod 700 "$WORK" || undecided "cannot make the scratch directory private"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
trap 'cleanup; exit 2' INT TERM HUP

STATE_SESSION="$SKILL-$TOPIC"
ds_state_read "$STATE_SESSION" "$WORK/state.json"
COMMIT=$(ds_doc_commit "$DOC")

# A pre-jury check right after a clean post-fix check of the same commit is
# that check: nothing runs and nothing is recorded.
if [ "$MOMENT" = pre_jury ] && [ -n "$COMMIT" ] \
    && jq -e --arg doc "$DOC" --arg c "$COMMIT" '
        .doc == $doc and .last.moment == "post_fix" and .last.commit == $c
        and .last.block_fail == false' "$WORK/state.json" >/dev/null 2>&1; then
    echo "doc-check: the post_fix check of $DOC at $COMMIT serves as this pre_jury check" >&2
    exit 0
fi

# --- the validator ------------------------------------------------------------

REGISTRY="$PLUGIN_ROOT/references/rule-registry.json"
VIS=$(declared_visibility)
[ -n "$VIS" ] || VIS=private
: > "$WORK/hits"
DOC_STATE=present
ENV_ERROR=""
if [ ! -e "$DOC" ] && [ ! -L "$DOC" ]; then
    DOC_STATE=missing
elif ! command -v shirabe >/dev/null 2>&1; then
    ENV_ERROR="shirabe is not on PATH"
elif ! dv_resolve_validator "$ROOT_REAL"; then
    ENV_ERROR=$DV_REASON
elif ! dv_pin_rules "$PLUGIN_ROOT"; then
    ENV_ERROR=$DV_REASON
elif ! dv_canary "$WORK"; then
    ENV_ERROR=$DV_REASON
elif ! dv_check_file "$DOC" "$ROOT_REAL"; then
    ENV_ERROR=$DV_REASON
elif ! dv_validate "$DOC" "$WORK/env.json" "$WORK/env.err" "$VIS"; then
    ENV_ERROR=$DV_REASON
elif ! dv_select_violations "$WORK/env.json" > "$WORK/raw-hits" 2>/dev/null; then
    ENV_ERROR="cannot read shirabe validate's output on $DOC"
fi
if [ -n "$ENV_ERROR" ]; then
    printf 'doc-check: defect: no validator verdict: %s\n' "$(printf '%s' "$ENV_ERROR" | ds_sanitize)" >&2
fi

# Each violation, with the rule its code maps to ("" for none) and, for FC04,
# the section the validator says is missing (from its message's '## <name>').
UNMAPPED=false
if [ "$DOC_STATE" = present ] && [ -z "$ENV_ERROR" ]; then
    jq -r '.code // "" | tostring' "$WORK/raw-hits" | sort -u > "$WORK/raw-codes"
    while IFS= read -r code; do
        id=$(dv_registry_id "$REGISTRY" "$code")
        if [ -n "$id" ] && jq -e --arg f "$FORMAT" --arg id "$id" '.formats[$f].rules | index($id)' "$DS_PHASES" >/dev/null 2>&1; then
            printf '%s\t%s\n' "$code" "$id" >> "$WORK/codes"
        else
            UNMAPPED=true
            case "$code" in
                *[!A-Z0-9-]*|"") shown="<an unprintable code>" ;;
                *) shown=$code ;;
            esac
            printf 'doc-check: defect: the validator reported error-level code [%s], which maps to no check-held rule of %s\n' \
                "${shown:0:20}" "$FORMAT" >&2
        fi
    done < "$WORK/raw-codes"
    [ -f "$WORK/codes" ] || : > "$WORK/codes"
    jq -c --rawfile codes "$WORK/codes" '
        ($codes | split("\n") | map(select(length > 0) | split("\t") | {(.[0]): .[1]}) | add // {}) as $map
        | {code: (.code // "" | tostring),
           id: ($map[(.code // "" | tostring)] // ""),
           line: (if (.line | type) == "number" then .line else null end),
           message: (.message // "" | tostring),
           section: (if .code == "FC04"
                     then ((.message // "" | tostring) | capture("## (?<s>[^'"'"']*)'"'"'$").s? // null)
                     else null end)}' "$WORK/raw-hits" > "$WORK/hits" 2>/dev/null \
        || { ENV_ERROR="cannot read shirabe validate's output on $DOC"; : > "$WORK/hits"; }
fi

# --- the outcomes -------------------------------------------------------------

jq -n -c --slurpfile hits "$WORK/hits" --slurpfile map "$DS_PHASES" \
    --arg f "$FORMAT" --arg p "$PHASE" --arg doc_state "$DOC_STATE" \
    --arg env_error "$ENV_ERROR" --argjson unmapped "$UNMAPPED" '
    def inlist($l): . as $x | any($l[]; . == $x);
    $map[0].formats[$f] as $fm
    | $fm.phases[$p] as $reached
    | [$fm.rules[] as $r
       | ($fm.rule_sections[$r] // []) as $secs
       | [$hits[] | select(.id == $r)] as $h
       | if $doc_state == "missing" then {rule_id: $r, outcome: "not_ready"}
         elif $env_error != "" then {rule_id: $r, outcome: "error"}
         elif any($secs[]; inlist($reached) | not) then {rule_id: $r, outcome: "not_ready"}
         elif $r == "docs/required-sections" then
           ([$h[] | select(.section == null or (.section | inlist($reached)))]) as $fails
           | if ($fails | length) > 0 then
               {rule_id: $r, outcome: "fail", findings: $fails,
                sections: ([$fails[].section | select(. != null)] | unique)}
             elif ($h | length) > 0 then {rule_id: $r, outcome: "not_ready"}
             elif $unmapped then {rule_id: $r, outcome: "error"}
             else {rule_id: $r, outcome: "pass"} end
         elif ($h | length) > 0 then {rule_id: $r, outcome: "fail", findings: $h, sections: $secs}
         elif $unmapped then {rule_id: $r, outcome: "error"}
         else {rule_id: $r, outcome: "pass"} end]' > "$WORK/outcomes.json" \
    || undecided "cannot compute the outcomes"

# Stages are resolved for the failing rules only, before anything prints, so a
# registry entry that doesn't resolve refuses the run instead of cutting its
# output short.
: > "$WORK/stages"
for id in $(jq -r '.[] | select(.outcome == "fail") | .rule_id' "$WORK/outcomes.json"); do
    rf_require "$id"
    stage=$(rf_stage "$id") || exit 2
    printf '%s\t%s\n' "$id" "$stage" >> "$WORK/stages"
done
BLOCK_FAIL=false
awk -F'\t' '$2 == "block" { found = 1 } END { exit found ? 0 : 1 }' "$WORK/stages" && BLOCK_FAIL=true
# at_block <id>: whether the rule's stage is block.
at_block() {
    awk -F'\t' -v id="$1" '$1 == id && $2 == "block" { found = 1 } END { exit found ? 0 : 1 }' "$WORK/stages"
}

# --- the state ----------------------------------------------------------------

jq -c --arg doc "$DOC" --arg f "$FORMAT" --arg p "$PHASE" --arg m "$MOMENT" \
    --arg c "$COMMIT" --argjson bf "$BLOCK_FAIL" --slurpfile o "$WORK/outcomes.json" '
    (if .doc == $doc then . else {} end) as $prev
    | ($prev.cycles // {pre_jury: 0, post_fix: 0, post_create: 0}) as $cy
    | {schema: "doc-check-state/v1", doc: $doc, format: $f,
       sections_commit: ($prev.sections_commit // ""),
       last: {moment: $m, phase: $p, commit: $c, block_fail: $bf,
              outcomes: [$o[0][] | {rule_id, outcome,
                                    sections: (.sections // []),
                                    lines: ([(.findings // [])[] | .line | select(. != null)] | unique)}]},
       cycles: ($cy + {($m): (if $bf then (($cy[$m] // 0) + 1) else 0 end)})}' \
    "$WORK/state.json" > "$WORK/state.new" || undecided "cannot build the check state"
CYCLES=$(jq -r --arg m "$MOMENT" '.cycles[$m]' "$WORK/state.new")

# --- output -------------------------------------------------------------------

if jq -e 'any(.[]; .outcome == "not_ready")' "$WORK/outcomes.json" >/dev/null 2>&1; then
    echo "::koto-not-ready::"
fi
jq -r '.[] | "doc-check: \(.rule_id) \(.outcome)"' "$WORK/outcomes.json"

if [ "$BLOCK_FAIL" = true ]; then
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        id=$(printf '%s' "$hit" | jq -r '.id')
        at_block "$id" || continue
        line=$(printf '%s' "$hit" | jq -r '.line // ""')
        msg=$(printf '%s' "$hit" | jq -r '.message' | ds_sanitize)
        if [ "${#msg}" -gt "$MESSAGE_CAP" ]; then
            msg="${msg:0:$((MESSAGE_CAP - 3))}..."
        fi
        rf_finding "$id" "$msg" "$DOC" "$line"
    done <<EOF
$(jq -c '.[] | select(.outcome == "fail") | .findings[]' "$WORK/outcomes.json")
EOF
fi

if [ "$CYCLES" -ge 4 ] 2>/dev/null; then
    echo "doc-check: unresolved after 3 cycles"
fi

# --- recording (best effort) --------------------------------------------------

ds_state_write "$STATE_SESSION" "$WORK/state.new"
BATCH=$(mktemp "$WORK/rule-checks.XXXXXX") || BATCH=""
if [ -n "$BATCH" ] && jq -c --slurpfile reg "$REGISTRY" '
        ([$reg[0].rules[].id]) as $ids
        | [.[] | select(.rule_id as $r | any($ids[]; . == $r)) | {rule_id, outcome}]' \
        "$WORK/outcomes.json" > "$BATCH" 2>/dev/null; then
    if jq -e 'length > 0' "$BATCH" >/dev/null 2>&1; then
        ds_record_session "$SKILL" "$TOPIC"
        ds_record "the rule checks" rule-checks "$DS_RECORD_SESSION" \
            --doc-format "$FORMAT" --moment "$MOMENT" --file "$BATCH"
    fi
else
    ds_notice "could not build the telemetry batch; the rule checks were not recorded"
fi

if [ "$BLOCK_FAIL" = true ]; then
    echo "doc-check: a rule at block failed in $DOC" >&2
    exit 1
fi
exit 0
