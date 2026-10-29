#!/usr/bin/env bash
# doc-shadow-check.sh -- at /scope publish, check each final document of the
# topic against its format's document rules and record the result as
# telemetry. It is never a gate: it always exits 0 once its arguments pass.
#
# Usage: doc-shadow-check.sh --topic <topic>
#
# For each of the topic's BRIEF, PRD, DESIGN and PLAN that exists at its
# canonical path (references/doc-check-phases.json), it runs
# `shirabe validate --format json --visibility=<v>` once through
# scripts/lib/doc-validate.sh (the validator resolution, rule pinning, canary
# and envelope checks), with the visibility the repository declares (private
# when it declares none). Each finding code maps to its registered rule through
# the registry's aliases, as doc-check.sh maps them. For each of the format's
# check-held rules it records one result:
#
#   failed  a violation (an error-level finding, a banned word, a notice
#           doc-validate.sh selects by code, or a schema-only skip read as
#           SCHEMA) maps to it
#   error   the validator reached no verdict, or a violation's code maps to no
#           check-held rule of the format, which leaves every rule that would
#           have passed undecided
#   passed  otherwise
#
# and prints `doc-shadow-check: <format> <rule-id> <result>` per rule. The
# results go, best effort, to
#   koto review record <session> doc-checks --file <batch>
# with entries {rule_id, outcome, doc_type, schema?}, one batch per document,
# on the session `skill-session.sh dispatch read scope <topic>` resolves
# (scope-<topic>, or a parent that dispatched /scope). A failed call prints one
# notice on stderr and changes nothing else. No validator text is printed or
# recorded.
#
# Exit status: 0 always, once the arguments pass; 2 refused (a usage error, a
# topic outside its pattern, not inside a git working tree, jq missing).
#
# Environment: KOTO_BIN, the koto to run (default `koto` on PATH).
#
# Written for the bash 3.2 floor and without `set -e`.

set -u

PROG=doc-shadow-check
HERE=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN_ROOT=$(cd "$HERE/.." && pwd -P)
KOTO="${KOTO_BIN:-koto}"
FORMATS="brief prd design plan"

usage() {
    echo "Usage: doc-shadow-check.sh --topic <topic>" >&2
    exit 2
}

refuse() {
    echo "doc-shadow-check: refused: $*" >&2
    exit 2
}

# shellcheck source=lib/declared-visibility.sh
. "$PLUGIN_ROOT/scripts/lib/declared-visibility.sh" || refuse "cannot load scripts/lib/declared-visibility.sh"
# shellcheck source=lib/doc-validate.sh
. "$PLUGIN_ROOT/scripts/lib/doc-validate.sh" || refuse "cannot load scripts/lib/doc-validate.sh"
# shellcheck source=lib/doc-session.sh
. "$PLUGIN_ROOT/scripts/lib/doc-session.sh" || refuse "cannot load scripts/lib/doc-session.sh"

[ $# -eq 2 ] && [ "$1" = --topic ] || usage
TOPIC=$2
[[ "$TOPIC" =~ $DS_RE_TOPIC ]] || refuse "--topic must match $DS_RE_TOPIC"
for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || refuse "$tool is not on PATH"
done
[ -r "$DS_PHASES" ] || refuse "cannot read $DS_PHASES"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || refuse "not inside a git working tree"
cd "$ROOT" || refuse "cannot enter the repository root"
ROOT_REAL=$(pwd -P)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/doc-shadow-check.XXXXXX") || refuse "cannot create a private scratch directory"
chmod 700 "$WORK" || refuse "cannot make the scratch directory private"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM HUP

REGISTRY="$PLUGIN_ROOT/references/rule-registry.json"
VIS=$(declared_visibility)
[ -n "$VIS" ] || VIS=private

# The validator is set up once for every document; a failure leaves every
# document's rules at error.
ENV_ERROR=""
if ! command -v shirabe >/dev/null 2>&1; then
    ENV_ERROR="shirabe is not on PATH"
elif ! dv_resolve_validator "$ROOT_REAL"; then
    ENV_ERROR=$DV_REASON
elif ! dv_pin_rules "$PLUGIN_ROOT"; then
    ENV_ERROR=$DV_REASON
elif ! dv_canary "$WORK"; then
    ENV_ERROR=$DV_REASON
fi

RECORD_SESSION=""
for FORMAT in $FORMATS; do
    DOC=""
    while IFS= read -r c; do
        if [ -n "$c" ] && [ -e "$c" ]; then DOC=$c; break; fi
    done <<EOF
$(ds_canonical_paths "$FORMAT" "$TOPIC")
EOF
    [ -n "$DOC" ] || continue

    err=$ENV_ERROR
    : > "$WORK/hits"
    if [ -z "$err" ] && ! dv_check_file "$DOC" "$ROOT_REAL"; then
        err=$DV_REASON
    fi
    if [ -z "$err" ] && ! dv_validate "$DOC" "$WORK/env.json" "$WORK/env.err" "$VIS"; then
        err=$DV_REASON
    fi
    if [ -z "$err" ] && ! dv_select_violations "$WORK/env.json" > "$WORK/hits" 2>/dev/null; then
        err="cannot read shirabe validate's output on $DOC"
    fi
    if [ -n "$err" ]; then
        printf 'doc-shadow-check: no validator verdict on %s: %s\n' "$DOC" "$(printf '%s' "$err" | ds_sanitize)" >&2
    fi

    # The rules the violations map to, and whether any maps to none.
    : > "$WORK/failed"
    UNMAPPED=false
    if [ -z "$err" ]; then
        jq -r '.code // "" | tostring' "$WORK/hits" | sort -u > "$WORK/codes"
        while IFS= read -r code; do
            [ -n "$code" ] || { UNMAPPED=true; continue; }
            id=$(dv_registry_id "$REGISTRY" "$code")
            if [ -n "$id" ] && jq -e --arg f "$FORMAT" --arg id "$id" '.formats[$f].rules | index($id)' "$DS_PHASES" >/dev/null 2>&1; then
                printf '%s\n' "$id" >> "$WORK/failed"
            else
                UNMAPPED=true
            fi
        done < "$WORK/codes"
    fi

    jq -n -c --slurpfile map "$DS_PHASES" --rawfile failed "$WORK/failed" \
        --arg f "$FORMAT" --arg err "$err" --argjson unmapped "$UNMAPPED" '
        ($failed | split("\n") | map(select(length > 0))) as $fl
        | [$map[0].formats[$f].rules[] as $r
           | {rule_id: $r,
              outcome: (if $err != "" then "error"
                        elif any($fl[]; . == $r) then "failed"
                        elif $unmapped then "error"
                        else "passed" end)}]' > "$WORK/outcomes.json" \
        || { ds_notice "could not compute the results for $DOC"; continue; }
    jq -r --arg f "$FORMAT" '.[] | "doc-shadow-check: \($f) \(.rule_id) \(.outcome)"' "$WORK/outcomes.json"

    SCHEMA=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
                  NR > 1 && /^schema:/ { sub(/^schema:[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }' "$DOC" 2>/dev/null)
    [[ "$SCHEMA" =~ ^[a-z0-9][a-z0-9./-]{0,31}$ ]] || { [ -z "$SCHEMA" ] || SCHEMA=unrecognized; }
    BATCH=$(mktemp "$WORK/doc-checks.XXXXXX") || { ds_notice "could not create the telemetry batch for $DOC"; continue; }
    jq -c --slurpfile reg "$REGISTRY" --arg dt "$FORMAT" --arg schema "$SCHEMA" '
        ([$reg[0].rules[].id]) as $ids
        | [.[] | select(.rule_id as $r | any($ids[]; . == $r))
           | {rule_id, outcome, doc_type: $dt} + (if $schema == "" then {} else {schema: $schema} end)]' \
        "$WORK/outcomes.json" > "$BATCH" 2>/dev/null \
        || { ds_notice "could not build the telemetry batch for $DOC"; continue; }
    jq -e 'length > 0' "$BATCH" >/dev/null 2>&1 || continue
    if [ -z "$RECORD_SESSION" ]; then
        ds_record_session scope "$TOPIC"
        RECORD_SESSION=$DS_RECORD_SESSION
    fi
    ds_record "the document checks of $DOC" "$RECORD_SESSION" doc-checks --file "$BATCH"
done
exit 0
