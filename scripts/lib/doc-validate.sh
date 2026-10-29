# doc-validate.sh -- running the document validator the way a document check
# trusts it.
#
# Sourced, never run. Two scripts source it:
# skills/scope/scripts/check-hop-document.sh (the /scope hop gate) and
# scripts/doc-check.sh (the check a skill runs before a jury and after a fix).
# Both need the same validator handling, so it lives here once:
#
#   dv_resolve_validator <root_real>
#                       follows `shirabe` on PATH through its links (at most
#                       40) and refuses one that resolves inside the
#                       repository at <root_real>: the document's own author
#                       could have written it. Sets DV_SHIRABE (the resolved
#                       file's path).
#   dv_pin_rules <plugin_root>
#                       checks the plugin's own writing-style rules
#                       (skills/writing-style/rules.yaml) are readable and hold
#                       a `words:` entry, then sets and exports SHIRABE_RULES to
#                       that file, ignoring any inherited value (which could
#                       switch the banned-word check off). Sets DV_RULES_FILE.
#   dv_canary <work_dir>
#                       two canary documents, BRIEF-canary.md and
#                       DESIGN-canary.md, validated in one run that must exit 0
#                       and come back through dv_select_violations with the
#                       first banned word of the pinned rules (FC10) and each
#                       code in DV_SELECTED_NOTICES. A validator that loaded no
#                       rules, whose wording the prefixes below no longer
#                       match, or that predates the selected codes fails here
#                       instead of passing every document. Call after
#                       dv_pin_rules.
#   dv_check_file <path> <root_real>
#                       the file checks: not a symlink, a regular file, not
#                       empty, and in a directory that resolves inside the
#                       repository.
#   dv_validate <path> <out_json> <err_file> [<visibility>]
#                       one `shirabe validate --format json` run on <path>,
#                       with `--visibility=<visibility>` when one is given. The
#                       run must exit 0 or 2 with a complete
#                       shirabe-validate/v1 envelope that agrees with itself
#                       (exit 2 only with an error finding, exit 0 only with
#                       none), or exit 4 with a schema-only skip of <path>
#                       (see dv_complete_envelope).
#   dv_select_violations <envelope>
#                       one compact JSON object per violation: every finding
#                       whose severity is "error"; an FC10 finding whose
#                       message starts with DV_BANNED_PREFIX or
#                       DV_TRUNC_PREFIX (a banned word, or the line saying
#                       banned-word findings were capped); a finding whose
#                       code is in DV_SELECTED_NOTICES, chosen by code and
#                       never by its message; and, in a schema-only skip's
#                       envelope, its SCHEMA finding, at line 1.
#   dv_complete_envelope <envelope> [<path>]
#                       exit 0 when the envelope is a full verdict a caller can
#                       read. With <path>, a schema-only skip of <path> is one
#                       too: outcome `incomplete`, exactly one `skipped` entry,
#                       naming <path>, a SCHEMA finding for <path>, and no
#                       error-level finding. Any other incomplete envelope is
#                       not.
#   dv_registry_id <registry> <code>
#                       the id of the active registry entry whose `aliases`
#                       hold <code>, or nothing. check-hop-document.sh keeps its
#                       own fixed table (its suite pins every arm against the
#                       registry); doc-check.sh, which covers every format,
#                       asks the registry through this.
#
# Every function returns 0 on success and 1 on a failure, with the reason in
# DV_REASON; it never exits. Each caller decides what a failure means: the hop
# gate turns it into its could-not-decide exit with DV_REASON as the message,
# doc-check.sh into an `error` outcome. The reasons are the hop gate's own
# messages, word for word, so its output did not change when the code moved
# here.
#
# Written for the bash 3.2 floor, with no `set -e` of its own.

# The validator's FC10 message prefixes, from check_writing_style_with in
# crates/shirabe-validate/src/checks.rs. check-hop-document_test.sh pins both
# against the built validator.
DV_BANNED_PREFIX='[FC10] writing-style banned word '
DV_TRUNC_PREFIX='[FC10] writing-style findings truncated at '

# The validator's notice-level codes a document check reports as violations,
# each under the registry entry that aliases it. Selected by code: FC07 to FC15
# are notices too, with no registered rule, and are never selected.
DV_SELECTED_NOTICES="FC23 FC24 FC25"

DV_REASON=""
DV_SHIRABE=""
DV_RULES_FILE=""

dv_fail() {
    DV_REASON=$1
    return 1
}

dv_resolve_validator() {
    local root_real=$1 bin target hops=0 dir
    bin=$(command -v shirabe) || { dv_fail "shirabe is not on PATH"; return 1; }
    while [ -L "$bin" ] && [ "$hops" -lt 40 ]; do
        target=$(readlink "$bin") || { dv_fail "cannot read the link $bin"; return 1; }
        case "$target" in
            /*) bin=$target ;;
            *) bin="$(dirname "$bin")/$target" ;;
        esac
        hops=$((hops + 1))
    done
    [ -L "$bin" ] && { dv_fail "shirabe resolves through more than 40 links"; return 1; }
    dir=$(cd "$(dirname "$bin")" 2>/dev/null && pwd -P) \
        || { dv_fail "cannot resolve the directory of $bin"; return 1; }
    case "$dir/" in
        "$root_real"/*)
            dv_fail "shirabe resolves inside the repository ($dir); refusing a validator from the tree under review"
            return 1 ;;
    esac
    DV_SHIRABE="$dir/$(basename "$bin")"
    return 0
}

dv_pin_rules() {
    local rules="$1/skills/writing-style/rules.yaml"
    [ -f "$rules" ] && [ -r "$rules" ] \
        || { dv_fail "the writing-style rules $rules are not readable"; return 1; }
    awk '/^words:/ { found = 1; exit } END { exit found ? 0 : 1 }' "$rules" \
        || { dv_fail "the writing-style rules $rules have no words: entry"; return 1; }
    DV_RULES_FILE=$rules
    SHIRABE_RULES=$rules
    export SHIRABE_RULES
    return 0
}

dv_select_violations() {
    jq -c --arg bw "$DV_BANNED_PREFIX" --arg tr "$DV_TRUNC_PREFIX" --arg sel " $DV_SELECTED_NOTICES " '
        (.summary.outcome == "incomplete") as $skip
        | .findings[]
        | if .code == "SCHEMA" then select($skip) | .line = 1
          else select(.severity == "error"
                      or (.code == "FC10"
                          and ((.message | tostring | startswith($bw))
                               or (.message | tostring | startswith($tr))))
                      or (.code as $c | ($c | type) == "string" and ($sel | contains(" " + $c + " "))))
          end' "$1"
}

dv_complete_envelope() {
    jq -e --arg p "${2-}" '
        .schema_version == "shirabe-validate/v1"
        and (.findings | type == "array")
        and all(.findings[]; (.severity | type) == "string")
        and ((.summary.outcome == "clean" or .summary.outcome == "violations")
             or ($p != ""
                 and .summary.outcome == "incomplete"
                 and (.skipped | type == "array" and length == 1)
                 and .skipped[0].file == $p
                 and any(.findings[]; .code == "SCHEMA" and .file == $p)
                 and all(.findings[]; .severity != "error")))' "$1" >/dev/null 2>&1
}

# dv_canary_docs <work_dir> <word>: the two canary documents. Each is a
# complete document of its format, so the run exits 0, and each breaks the
# selected notices' rules: the BRIEF a five-line problem (FC23) and the banned
# word, the DESIGN a key out of order (FC24) and an option with no provenance
# opener (FC25).
dv_canary_docs() {
    local work=$1 word=$2
    cat > "$work/BRIEF-canary.md" <<EOF || return 1
---
schema: brief/v1
status: Draft
problem: |
  Authors lose track of which documents a run wrote.
  The run writes them in several places.
  Nothing lists them at the end.
  Authors search for each one by hand.
  Some are missed.
outcome: |
  Authors can see every document a run wrote.
  One list names them all.
---

# BRIEF: canary

## Status

Draft

## Problem Statement

Canary: we $word this.

## User Outcome

Authors can see every document a run wrote.

## User Journeys

An author opens the run's record and reads the list.

## Scope Boundary

In: the list. Out: editing the documents.
EOF
    cat > "$work/DESIGN-canary.md" <<'EOF' || return 1
---
schema: design/v1
problem: |
  Runs don't list their documents.
status: Proposed
decision: |
  Print a list at exit.
rationale: |
  It is the simplest place.
decision_provenance: inline-resolved
---

# DESIGN: canary

## Status

Proposed

## Context and Problem Statement

Runs don't list their documents.

## Decision Drivers

Keep it simple.

## Considered Options

### Decision 1: where the list goes

The list prints at exit.

## Decision Outcome

Print at exit.

## Solution Architecture

One function prints the list.

## Implementation Approach

Add the function and call it.

## Security Considerations

The list holds only paths the run wrote.

## Consequences

Authors see the list.
EOF
    return 0
}

dv_canary() {
    local work=$1 word rc code
    # The first `- <term>` under the first `terms:` of the rules file. `terms:`
    # is the list inside the `words:` entry dv_pin_rules requires, so both read
    # the same banned-word list.
    word=$(awk '
        /^[[:space:]]*terms:[[:space:]]*$/ { inside = 1; next }
        inside && /^[[:space:]]*-[[:space:]]+/ {
            line = $0
            sub(/^[[:space:]]*-[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            gsub(/^["'"'"']|["'"'"']$/, "", line)
            print line
            exit
        }' "$DV_RULES_FILE")
    [ -n "$word" ] || { dv_fail "no banned word could be read from $DV_RULES_FILE"; return 1; }
    dv_canary_docs "$work" "$word" || { dv_fail "cannot write the canary"; return 1; }
    (cd "$work" && shirabe validate --format json BRIEF-canary.md DESIGN-canary.md) \
        > "$work/canary.json" 2> "$work/canary.err"
    rc=$?
    [ "$rc" -eq 0 ] || { dv_fail "the canary run exited $rc: $(tail -n 1 "$work/canary.err")"; return 1; }
    dv_select_violations "$work/canary.json" > "$work/canary.hits" 2>/dev/null \
        || { dv_fail "cannot read the canary run's output"; return 1; }
    jq -e --arg bw "$DV_BANNED_PREFIX" 'select(.code == "FC10" and .file == "BRIEF-canary.md"
            and (.message | tostring | startswith($bw)))' "$work/canary.hits" >/dev/null 2>&1 \
        || { dv_fail "the validator reported no banned-word finding for the canary word [$word]; its rules didn't load or its message wording changed"; return 1; }
    for code in $DV_SELECTED_NOTICES; do
        jq -e --arg c "$code" 'select(.code == $c)' "$work/canary.hits" >/dev/null 2>&1 \
            || { dv_fail "the validator reported no $code finding for the canary; it predates the checks this script reports"; return 1; }
    done
    return 0
}

dv_check_file() {
    local p=$1 root_real=$2 dir_real
    [ -L "$p" ] && { dv_fail "$p is a symlink"; return 1; }
    [ -f "$p" ] || { dv_fail "$p is not a regular file"; return 1; }
    [ -s "$p" ] || { dv_fail "$p is empty"; return 1; }
    dir_real=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P) \
        || { dv_fail "cannot resolve the directory of $p"; return 1; }
    case "$dir_real/" in
        "$root_real"/*) ;;
        *) dv_fail "$p resolves outside the repository"; return 1 ;;
    esac
    return 0
}

dv_validate() {
    local p=$1 out=$2 err=$3 vis=${4-} rc errors
    if [ -n "$vis" ]; then
        shirabe validate --format json "--visibility=$vis" -- "$p" > "$out" 2> "$err"
    else
        shirabe validate --format json -- "$p" > "$out" 2> "$err"
    fi
    rc=$?
    case "$rc" in
        0|2) dv_complete_envelope "$out" \
                 || { dv_fail "shirabe validate gave no complete verdict on $p (output this script can't read)"; return 1; } ;;
        # Exit 4 is the validator's incomplete run. Only a schema-only skip of
        # this document is a verdict: its SCHEMA finding is the violation.
        4) jq -e '.summary.outcome == "incomplete"' "$out" >/dev/null 2>&1 \
               && dv_complete_envelope "$out" "$p" \
               || { dv_fail "shirabe validate exited 4 on $p with no schema-only skip of it: $(tail -n 1 "$err")"; return 1; } ;;
        *) dv_fail "the validator exited $rc on $p: $(tail -n 1 "$err")"; return 1 ;;
    esac
    errors=$(jq '[.findings[] | select(.severity == "error")] | length' "$out") \
        || { dv_fail "cannot count the errors on $p"; return 1; }
    if [ "$rc" -eq 2 ] && [ "$errors" -eq 0 ]; then
        dv_fail "shirabe validate exited 2 on $p but reported no error"
        return 1
    fi
    if [ "$rc" -ne 2 ] && [ "$errors" -ne 0 ]; then
        dv_fail "shirabe validate exited $rc on $p but reported $errors error(s)"
        return 1
    fi
    return 0
}

dv_registry_id() {
    jq -r --arg code "$2" '
        [.rules[] | select(.status == "active" and ((.aliases // []) | index($code)))
         | .id] | first // ""' "$1" 2>/dev/null
}
