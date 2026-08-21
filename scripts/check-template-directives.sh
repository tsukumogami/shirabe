#!/usr/bin/env bash
set -euo pipefail

# Fails the build on the two koto authoring shapes the engine punishes silently.
#
# Both are shapes a template compiles cleanly with. `koto template compile`
# reports neither, and nothing at runtime raises them either -- the run simply
# does the wrong thing and reports success. That is what makes them worth a
# static check rather than a review note.
#
# ---------------------------------------------------------------------------
# Rule one (every template): unguarded evidence on a non-terminal state
# ---------------------------------------------------------------------------
#
# A non-terminal state that declares an `accepts:` block but has no transition
# carrying a `when:` clause fails.
#
# koto's engine (src/engine/advance.rs:757-758) fires a state's unconditional
# fallback transition unless `gate_failed || (!fresh_evidence && has_conditional)`.
# With every transition unconditional, `has_conditional` is false, so the
# fallback fires on entry: the engine advances straight through the state and
# the agent never receives its directive. The `accepts:` block is what says the
# author expected the agent to stop there, which is why it is the trigger.
#
# The same mechanism is why a gate on such a state is inert. execute.md's
# orchestrator_setup records it in its own comments: a failed gate on a state
# with an `accepts:` block does not block on its own, it falls through to
# transition resolution, and a `when:` clause is what makes the gate
# load-bearing.
#
# Terminal states are exempt, and the exemption is structural rather than a
# concession: a terminal cannot have a transition at all, so `done_blocked` and
# its siblings can never satisfy the rule. Flagging them would be a false
# positive by construction.
#
# ---------------------------------------------------------------------------
# Rule two (/scope's template only): hop completion from the artifact tree
# ---------------------------------------------------------------------------
#
# In /scope's template, a gate that reads `wip/scope_` or an agent-submitted
# evidence field fails.
#
# This is the mechanical form of the design's rule that hop completion is
# decided from the artifact tree and never from the run's own state file or
# from the run's own claim about itself. `wip/scope_<topic>_state.md` is the
# state file /scope writes; a gate reading it asks the run whether the run
# finished, which is the self-report the design exists to remove. An evidence
# field is the same self-report arriving through the agent instead.
#
# Three boundaries are deliberate:
#
#   `wip/` on its own is not flagged. Only the parent's own `wip/scope_`
#   prefix is. The design's bail state legitimately reads child-intermediate
#   `wip/` prefixes, and flagging those would make the shipped template
#   unwritable.
#
#   A template variable is not an evidence field. `{{KEY}}` references are
#   stripped before matching. koto resolves and compile-time-validates them,
#   and skills/work-on/koto-templates/work-on.md interpolates {{PLAN_SLUG}}
#   into a gate command today -- an implementation flagging any interpolation
#   would make the shipped templates unpassable.
#
#   A `context-exists` / `context-matches` gate is not flagged, even though the
#   design rejects the context store as a hop-completion signal for the same
#   reason it rejects evidence. Nothing in a template distinguishes a context
#   gate deciding a hop from one recording a session's origin worktree, and
#   guessing from the gate's name would fail on a rename in either direction.
#   That limb stays with review.
#
# The rule reads the scripts a gate invokes, not only the gate's command
# string. A `wip/scope_` read added inside an invoked predicate would otherwise
# be invisible to it, which is the hole the design names explicitly. An
# invoked `.sh` path that cannot be resolved is an error rather than a pass:
# the rule cannot be enforced on a file the check cannot find, and reporting
# that as clean would be a lie about coverage.
#
# The rule is applied to every gate in /scope's template rather than to a
# name-matched subset of hop-completion gates. The design states that no gate
# command in the graph contains `wip/scope_`, so the superset is exact, and
# narrowing by gate name would let a rename walk out from under the rule.
#
# ---------------------------------------------------------------------------
# The allowlist
# ---------------------------------------------------------------------------
#
# scripts/check-template-directives.allow carries the known violations, one
# tab-separated record each, with an issue reference beside every one. A record
# without a `owner/repo#N` reference is itself an error, so the allowlist
# cannot silence a finding that has no ticket behind it.
#
# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
#
#   scripts/check-template-directives.sh [template ...]
#
# With no arguments, scans skills/*/koto-templates/*.md relative to the
# repository root. Files with no YAML frontmatter are skipped: the glob also
# matches execute.mermaid.md and work-on.mermaid.md, which are mermaid diagrams
# carrying no states to check.
#
# Environment:
#   TEMPLATE_DIRECTIVES_ALLOWLIST   override the allowlist path (tests use it)
#
# Exit codes:
#   0  clean
#   1  one or more findings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ALLOWLIST="${TEMPLATE_DIRECTIVES_ALLOWLIST:-$SCRIPT_DIR/check-template-directives.allow}"

TAB=$(printf '\t')

errors=0
allow_records=""

# The two rule identifiers, used in allowlist records and in findings.
RULE_UNGUARDED="unguarded-evidence"
RULE_STATE_FILE="state-file-read"

# -- allowlist ---------------------------------------------------------------

# Records are "<rule>\t<template>\t<subject>\t<issue>\t<reason>". The template
# path is repository-relative; subject is a state name for rule one and a gate
# name for rule two.
load_allowlist() {
    [ -f "$ALLOWLIST" ] || return 0

    local line rule template subject issue rest lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        case "$line" in
            ''|'#'*) continue ;;
        esac

        rule="${line%%"$TAB"*}"; rest="${line#*"$TAB"}"
        template="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
        subject="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
        issue="${rest%%"$TAB"*}"

        if [ "$rule" = "$line" ] || [ -z "$template" ] || [ -z "$subject" ]; then
            echo "FAIL: $ALLOWLIST:$lineno is not a tab-separated record"
            echo "  expected: <rule><TAB><template><TAB><subject><TAB><issue><TAB><reason>"
            errors=$((errors + 1))
            continue
        fi

        case "$rule" in
            "$RULE_UNGUARDED"|"$RULE_STATE_FILE") ;;
            *)
                echo "FAIL: $ALLOWLIST:$lineno names an unknown rule '$rule'"
                echo "  known rules: $RULE_UNGUARDED, $RULE_STATE_FILE"
                errors=$((errors + 1))
                continue
                ;;
        esac

        # An allowlist entry is a deferral, and a deferral needs somewhere to be
        # chased. Without a ticket it is just a suppression that nobody will
        # ever revisit.
        case "$issue" in
            *[A-Za-z0-9]'#'[0-9]*) ;;
            *)
                echo "FAIL: $ALLOWLIST:$lineno has no issue reference"
                echo "  field 4 must carry one, in the form owner/repo#N"
                echo "  record: $line"
                errors=$((errors + 1))
                continue
                ;;
        esac

        allow_records="${allow_records}${rule}|${template}|${subject}
"
    done < "$ALLOWLIST"
}

# is_allowed <rule> <repo-relative-template> <subject>
is_allowed() {
    case "
$allow_records" in
        *"
$1|$2|$3
"*) return 0 ;;
    esac
    return 1
}

# -- frontmatter readers -----------------------------------------------------

# has_frontmatter <file>
#
# True when the file opens with a `---` line and closes the block later. The
# *.mermaid.md companions have no frontmatter and carry no states, so they are
# skipped rather than reported.
has_frontmatter() {
    awk 'NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit 1; next }
         /^---[[:space:]]*$/ { found = 1; exit 0 }
         END { exit (found ? 0 : 1) }' "$1"
}

# read_template_name <file> -- the frontmatter `name:` value, or empty.
read_template_name() {
    awk '
        NR == 1 { next }
        /^---[[:space:]]*$/ { exit }
        /^name:[[:space:]]*/ {
            sub(/^name:[[:space:]]*/, "")
            gsub(/["'"'"']/, "")
            sub(/[[:space:]]+$/, "")
            print
            exit
        }
    ' "$1"
}

# scan_states <file>
#
# One record per state: "<line>\t<state>\t<terminal>\t<accepts>\t<guarded>",
# each flag 0 or 1.
#
# The walk is YAML-block-scalar aware. A state's `directive:` is a block scalar
# holding markdown prose, and prose indented four spaces would otherwise read as
# a state key -- the templates are full of indented lists and fenced blocks.
scan_states() {
    awk '
        function indent_of(s,   i) {
            i = match(s, /[^ ]/)
            return (i == 0) ? -1 : i - 1
        }
        function flush() {
            if (state != "") {
                printf "%d\t%s\t%d\t%d\t%d\n", state_line, state, terminal, accepts, guarded
            }
        }

        NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; in_fm = 1; skip = -1; next }
        !in_fm { next }

        # Inside a block scalar body: everything more deeply indented than the
        # key that opened it belongs to the scalar, blank lines included.
        skip >= 0 {
            if ($0 ~ /^[[:space:]]*$/) next
            if (indent_of($0) > skip) next
            skip = -1
        }

        # Closing the frontmatter. Clearing `state` keeps END from flushing the
        # last state a second time.
        /^---[[:space:]]*$/ { flush(); state = ""; exit }

        # `key: |`, `key: >`, and the indent/chomp variants open a block scalar.
        /^[[:space:]]*(- )?[A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*[|>][0-9+-]*[[:space:]]*$/ {
            skip = indent_of($0)
            next
        }

        /^states:[[:space:]]*$/ { in_states = 1; next }
        !in_states { next }

        # A state key: exactly two leading spaces, a name, a colon, nothing else.
        /^  [a-z_][a-z0-9_]*:[[:space:]]*$/ {
            flush()
            state = $0
            sub(/:[[:space:]]*$/, "", state)
            sub(/^[[:space:]]+/, "", state)
            state_line = NR
            terminal = 0; accepts = 0; guarded = 0
            next
        }

        state == "" { next }

        /^    terminal:[[:space:]]*true[[:space:]]*$/ { terminal = 1; next }
        /^    accepts:[[:space:]]*$/ { accepts = 1; next }
        /^[[:space:]]+when:/ { guarded = 1; next }

        END { flush() }
    ' "$1"
}

# scan_gate_lines <file>
#
# One record per line inside a gate declaration:
# "<line>\t<state>\t<gate>\t<text>".
#
# Block-scalar skipping is suspended inside a `gates:` subtree on purpose. A
# gate whose command is written as `command: >` puts the command body on the
# following lines, and skipping it would hide exactly the string rule two
# exists to find.
scan_gate_lines() {
    awk '
        function indent_of(s,   i) {
            i = match(s, /[^ ]/)
            return (i == 0) ? -1 : i - 1
        }

        NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; in_fm = 1; skip = -1; next }
        !in_fm { next }

        skip >= 0 {
            if ($0 ~ /^[[:space:]]*$/) next
            if (indent_of($0) > skip) next
            skip = -1
        }

        /^---[[:space:]]*$/ { exit }

        # Leaving the gates subtree: any non-blank line indented less than a
        # gate name.
        in_gates {
            if ($0 ~ /^[[:space:]]*$/) next
            if (indent_of($0) < 6) {
                in_gates = 0; gate = ""
            }
        }

        !in_gates && /^[[:space:]]*(- )?[A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*[|>][0-9+-]*[[:space:]]*$/ {
            skip = indent_of($0)
            next
        }

        /^states:[[:space:]]*$/ { in_states = 1; next }
        !in_states { next }

        /^  [a-z_][a-z0-9_]*:[[:space:]]*$/ {
            state = $0
            sub(/:[[:space:]]*$/, "", state)
            sub(/^[[:space:]]+/, "", state)
            in_gates = 0; gate = ""
            next
        }

        /^    gates:[[:space:]]*$/ { in_gates = 1; gate = ""; next }
        !in_gates { next }

        /^      [a-z_][a-z0-9_]*:[[:space:]]*$/ {
            gate = $0
            sub(/:[[:space:]]*$/, "", gate)
            sub(/^[[:space:]]+/, "", gate)
            next
        }

        gate != "" { printf "%d\t%s\t%s\t%s\n", NR, state, gate, $0 }
    ' "$1"
}

# -- rule two matchers -------------------------------------------------------

# strip_interpolation <text> -- removes every {{KEY}} span.
#
# The closing `}}` is searched for only in what follows the opening `{{`. The
# obvious form -- cut at the first `{{`, rejoin after the first `}}` -- does not
# terminate on a line where a `}}` precedes a `{{`, because the rejoin then
# reintroduces text the cut removed and the string grows on every pass. This
# form strictly shortens.
strip_interpolation() {
    local s="$1" prefix rest
    while :; do
        case "$s" in
            *'{{'*) ;;
            *) break ;;
        esac
        prefix="${s%%\{\{*}"
        rest="${s#*\{\{}"
        case "$rest" in
            *'}}'*) ;;
            *) break ;;
        esac
        s="${prefix}${rest#*\}\}}"
    done
    printf '%s' "$s"
}

# reads_state_file <text> -- the parent's own wip/scope_ prefix.
reads_state_file() {
    case "$1" in
        *wip/scope_*) return 0 ;;
    esac
    return 1
}

# reads_evidence <text> -- koto's agent-submitted evidence namespace.
#
# `${evidence.<field>}` is the form koto itself uses. `$evidence.` and
# `KOTO_EVIDENCE` cover the two ways the same value reaches a shell.
reads_evidence() {
    case "$1" in
        *'${evidence.'*|*'$evidence.'*|*KOTO_EVIDENCE*) return 0 ;;
    esac
    return 1
}

# -- invoked-script resolution -----------------------------------------------

# script_tokens <text> -- every `*.sh` word in the line, quotes stripped.
script_tokens() {
    printf '%s\n' "$1" \
        | tr ' \t"'"'"'();|&' '\n\n\n\n\n\n\n\n\n' \
        | grep '\.sh$' || true
}

# template_root <template-dir>
#
# The tree a template's gate paths are relative to: the nearest ancestor
# holding a `skills` directory or a `.git` entry. For a shipped template that
# is the repository root; for a fixture tree it is the fixture's own root,
# which is what lets rule two be exercised somewhere other than this checkout.
template_root() {
    local dir="$1"
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if [ -d "$dir/skills" ] || [ -e "$dir/.git" ]; then
            printf '%s' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    printf '%s' "$REPO_ROOT"
}

# resolve_script <token> <template-dir> <template-root>
#
# Prints the resolved path, or nothing when the token cannot be resolved.
# `$SCRIPT_DIR/x.sh` and `./x.sh` both reduce to a basename lookup, which is
# why the search by basename is a step rather than a fallback of last resort.
resolve_script() {
    local token="$1" tmpl_dir="$2" root="$3" base cleaned hit

    # An absolute token that exists is the answer. One that does not is usually
    # the tail of a `$(dirname "$0")/x.sh` the word split left behind, so it
    # falls through to the basename search rather than being called missing.
    case "$token" in
        /*)
            if [ -f "$token" ]; then
                printf '%s' "$token"
                return 0
            fi
            ;;
    esac

    # Drop a leading `$VAR/` or `./` so a root-relative remainder is testable.
    cleaned="$token"
    cleaned="${cleaned#./}"
    case "$cleaned" in
        '$'*|'${'*) cleaned="${cleaned#*/}" ;;
    esac

    if [ -f "$root/$cleaned" ]; then
        printf '%s' "$root/$cleaned"
        return 0
    fi
    if [ -f "$tmpl_dir/$cleaned" ]; then
        printf '%s' "$tmpl_dir/$cleaned"
        return 0
    fi

    base="${token##*/}"
    hit=$(find "$tmpl_dir" -name "$base" -type f 2>/dev/null | head -1)
    [ -n "$hit" ] || hit=$(find "$root" -name "$base" -type f 2>/dev/null | head -1)
    [ -n "$hit" ] && printf '%s' "$hit"
    return 0
}

# scan_invoked_script <path> <template-rel> <state> <gate>
#
# Reports a finding for each offending line, and returns the `.sh` tokens it
# found so the caller can follow them.
INVOKED_TOKENS=""
scan_invoked_script() {
    local path="$1" rel="$2" state="$3" gate="$4"
    local lineno=0 line stripped

    INVOKED_TOKENS=""
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))

        # A whole-line comment is not a read. This is not a convenience: the
        # first script this check ever followed was flagged for the line
        # documenting that it never reads the state file, so the rule fired on
        # a script's statement that it complies. Any script that documents this
        # property would trip the same way, and rewording each one teaches the
        # wrong lesson.
        #
        # Whole-line comments only. A trailing comment after code is left in,
        # because deciding where code ends needs a shell parser -- a `#` inside
        # a quoted string is not a comment -- and cutting at the first `#`
        # would blind the scan to real reads on the same line.
        case "$line" in
            [[:space:]]*\#*|\#*)
                case "$(printf '%s' "$line" | sed 's/^[[:space:]]*//')" in
                    \#*) continue ;;
                esac
                ;;
        esac

        stripped=$(strip_interpolation "$line")

        if reads_state_file "$stripped"; then
            report_state_file "$state" "$gate" \
                "${path#"$REPO_ROOT"/}:$lineno" "$line" "invoked script"
        elif reads_evidence "$stripped"; then
            report_evidence "$state" "$gate" \
                "${path#"$REPO_ROOT"/}:$lineno" "$line" "invoked script"
        fi

        INVOKED_TOKENS="$INVOKED_TOKENS
$(script_tokens "$line")"
    done < "$path"
}

# -- findings ----------------------------------------------------------------

# report_state_file <state> <gate> <where> <line-text> <kind>
#
# `where` is file:line, and `kind` says whether the read was in the gate's own
# declaration or in a script it invokes -- the second is the limb a reader is
# least likely to have expected.
report_state_file() {
    local state="$1" gate="$2" where="$3" text="$4" kind="$5"
    echo "FAIL: $where state '$state' gate '$gate': $kind reads the run's own state file"
    echo "  line: $(printf '%s' "$text" | sed 's/^[[:space:]]*//')"
    echo "  wip/scope_<topic>_state.md is what the run writes about itself. A gate"
    echo "  reading it asks the run whether the run finished, which is the"
    echo "  self-report deciding hop completion from the artifact tree removes."
    echo "  Fix: decide the hop with the shared predicate over the canonical"
    echo "  artifact paths. Reading a child-intermediate wip/ prefix is fine;"
    echo "  the parent's own wip/scope_ prefix is not."
    errors=$((errors + 1))
}

# report_evidence <state> <gate> <where> <line-text> <kind>
report_evidence() {
    local state="$1" gate="$2" where="$3" text="$4" kind="$5"
    echo "FAIL: $where state '$state' gate '$gate': $kind reads an agent-submitted evidence field"
    echo "  line: $(printf '%s' "$text" | sed 's/^[[:space:]]*//')"
    echo "  Evidence is the run's claim about itself. A gate deciding on it"
    echo "  reports the claim rather than the engine's finding, and the finding"
    echo "  is what reaches the surviving per-hop record."
    echo "  Fix: read the artifact tree. Co-route the gate with an evidence field"
    echo "  in the transition's when clause instead -- that is where evidence"
    echo "  belongs."
    errors=$((errors + 1))
}

# -- per-template checks -----------------------------------------------------

check_rule_unguarded() {
    local file="$1" rel="$2"
    local record lineno state terminal accepts guarded

    while IFS="$TAB" read -r lineno state terminal accepts guarded; do
        [ -n "$state" ] || continue
        [ "$terminal" = "0" ] || continue
        [ "$accepts" = "1" ] || continue
        [ "$guarded" = "0" ] || continue

        if is_allowed "$RULE_UNGUARDED" "$rel" "$state"; then
            continue
        fi

        echo "FAIL: $rel:$lineno state '$state' accepts evidence with no guarded transition"
        echo "  koto fires a state's unconditional transition on entry unless the"
        echo "  state has a conditional one, so this state advances without ever"
        echo "  delivering its directive. The accepts block never reaches the agent,"
        echo "  and any gate here is evaluated, reported and ignored."
        echo "  Fix: put a when clause on at least one transition, keyed on a field"
        echo "  from this state's accepts block. Or, if the state is meant to be an"
        echo "  endpoint, declare terminal: true."
        errors=$((errors + 1))
    done <<EOF
$(scan_states "$file")
EOF
}

# Rule two applies to /scope's template. A template is /scope's when its
# frontmatter names it so, or when it sits where /scope's template lives --
# either alone is enough, so a fixture can carry the rule without occupying
# the shipped path, and the shipped path carries it whatever it is named.
applies_rule_state_file() {
    local file="$1" name="$2"
    [ "$name" = "scope" ] && return 0
    case "$file" in
        */scope/koto-templates/*.md) return 0 ;;
    esac
    return 1
}

check_rule_state_file() {
    local file="$1" rel="$2"
    local tmpl_dir tmpl_root seen="" queue="" token resolved
    local lineno state gate text stripped

    tmpl_dir="$(cd "$(dirname "$file")" && pwd)"
    tmpl_root="$(template_root "$tmpl_dir")"

    while IFS="$TAB" read -r lineno state gate text; do
        [ -n "$gate" ] || continue

        if is_allowed "$RULE_STATE_FILE" "$rel" "$gate"; then
            continue
        fi

        stripped=$(strip_interpolation "$text")

        if reads_state_file "$stripped"; then
            report_state_file "$state" "$gate" "$rel:$lineno" "$text" "gate"
        elif reads_evidence "$stripped"; then
            report_evidence "$state" "$gate" "$rel:$lineno" "$text" "gate"
        fi

        # Queue every script the gate invokes. Rule two covers what those
        # scripts read, not only what the gate string says.
        while IFS= read -r token; do
            [ -n "$token" ] || continue
            resolved=$(resolve_script "$token" "$tmpl_dir" "$tmpl_root")
            if [ -z "$resolved" ]; then
                echo "FAIL: $rel:$lineno state '$state' gate '$gate' invokes '$token', which was not found"
                echo "  The rule covers the scripts a gate invokes, and it cannot be"
                echo "  enforced on a file the check cannot resolve. Reporting this as"
                echo "  clean would overstate what was checked."
                echo "  Fix: reference the script by a repository-relative path."
                errors=$((errors + 1))
                continue
            fi
            queue="$queue
$resolved$TAB$state$TAB$gate"
        done <<EOF
$(script_tokens "$text")
EOF
    done <<EOF
$(scan_gate_lines "$file")
EOF

    # Walk the queue, following scripts that invoke further scripts. `seen`
    # keeps a cycle from spinning and stops one shared predicate from being
    # reported once per gate that calls it.
    local entry path
    while [ -n "$queue" ]; do
        entry=$(printf '%s' "$queue" | grep -v '^$' | head -1)
        queue=$(printf '%s' "$queue" | grep -v '^$' | tail -n +2)
        [ -n "$entry" ] || break

        path="${entry%%"$TAB"*}"
        state="${entry#*"$TAB"}"; gate="${state#*"$TAB"}"; state="${state%%"$TAB"*}"

        case "
$seen" in
            *"
$path
"*) continue ;;
        esac
        seen="$seen
$path
"

        scan_invoked_script "$path" "$rel" "$state" "$gate"

        while IFS= read -r token; do
            [ -n "$token" ] || continue
            resolved=$(resolve_script "$token" "$tmpl_dir" "$tmpl_root")
            [ -n "$resolved" ] || continue
            queue="$queue
$resolved$TAB$state$TAB$gate"
        done <<EOF
$INVOKED_TOKENS
EOF
    done
}

check_template() {
    local file="$1" rel name

    rel="${file#"$REPO_ROOT"/}"

    # The glob matches execute.mermaid.md and work-on.mermaid.md too. Those are
    # diagrams with no frontmatter and no states, so they are skipped rather
    # than counted as checked -- a count including them would overstate the
    # coverage this check has.
    if ! has_frontmatter "$file"; then
        skipped=$((skipped + 1))
        return 0
    fi

    checked=$((checked + 1))
    name=$(read_template_name "$file")

    check_rule_unguarded "$file" "$rel"

    if applies_rule_state_file "$file" "$name"; then
        check_rule_state_file "$file" "$rel"
    fi
}

# -- main --------------------------------------------------------------------

load_allowlist

TEMPLATES=""
if [ $# -gt 0 ]; then
    for f in "$@"; do
        TEMPLATES="$TEMPLATES
$f"
    done
else
    TEMPLATES=$(find "$REPO_ROOT/skills" -path '*/koto-templates/*' -name '*.md' 2>/dev/null | sort)
fi

checked=0
skipped=0
seen_any=0
while IFS= read -r template; do
    [ -n "$template" ] || continue
    seen_any=1
    if [ ! -f "$template" ]; then
        echo "FAIL: $template: not a file"
        errors=$((errors + 1))
        continue
    fi
    check_template "$template"
done <<EOF
$TEMPLATES
EOF

if [ "$seen_any" -eq 0 ]; then
    echo "check-template-directives: no koto templates found"
    exit 0
fi

if [ "$errors" -gt 0 ]; then
    echo ""
    echo "check-template-directives: $errors finding(s) across $checked template(s)"
    exit 1
fi

echo "check-template-directives: OK ($checked template(s) checked, $skipped without frontmatter)"
exit 0
