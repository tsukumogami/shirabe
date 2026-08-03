#!/usr/bin/env bash
# validate-template-mermaid.sh - Validates koto template consistency
#
# Checks:
#   1. State names in YAML frontmatter match states in companion .mermaid.md
#      (skipped if no .mermaid.md companion exists)
#   2. default_template: references point to existing files
#   3. No hardcoded workflow names in koto next calls (use {{SESSION_NAME}})
#   4. A gate name used by more than one template carries the same command in
#      all of them (only meaningful when several templates are validated at once)
#
# Usage:
#   validate-template-mermaid.sh [file ...]
#   If no files given, scans skills/*/koto-templates/*.md (excluding *.mermaid.md)
#
# Exit codes:
#   0  All checks passed
#   1  One or more validation errors found

set -euo pipefail

ERRORS=0

# ---------------------------------------------------------------------------
# Check 1: state name consistency between YAML frontmatter and .mermaid.md
# ---------------------------------------------------------------------------

check_state_consistency() {
    local template="$1"
    local mermaid="$2"

    # Extract state names from YAML frontmatter.
    # States appear as exactly-2-space-indented keys directly under `states:`
    # (e.g., `  entry:`, `  analysis:`). Fields within a state are at 4+ spaces.
    local yaml_states
    yaml_states=$(awk '
        BEGIN { in_states = 0 }
        /^states:$/ { in_states = 1; next }
        in_states && /^---$/ { exit }
        in_states && /^  [a-z_][a-z_0-9]*:/ {
            name = $0
            sub(/:.*/, "", name)
            sub(/^[[:space:]]+/, "", name)
            print name
        }
    ' "$template" | sort -u)

    if [[ -z "$yaml_states" ]]; then
        echo "WARNING: $template: no states found in YAML frontmatter, skipping check 1"
        return 0
    fi

    # Extract state names from mermaid --> transitions.
    # Lines look like:
    #   "    state1 --> state2 : condition"
    #   "    state1 --> state2"
    #   "    [*] --> state1"  (exclude [*])
    local mermaid_states
    mermaid_states=$(awk '
        / --> / {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            # Split on " --> "
            n = split(line, parts, " --> ")
            left = parts[1]
            # Right side may have " : condition", strip it
            right = parts[2]
            sub(/ :.*/, "", right)
            sub(/[[:space:]]+$/, "", right)
            if (left != "[*]") print left
            if (right != "[*]") print right
        }
    ' "$mermaid" | sort -u)

    if [[ -z "$mermaid_states" ]]; then
        echo "WARNING: $template: no transitions found in $mermaid, skipping check 1"
        return 0
    fi

    local yaml_only mermaid_only
    yaml_only=$(comm -23 <(echo "$yaml_states") <(echo "$mermaid_states"))
    mermaid_only=$(comm -13 <(echo "$yaml_states") <(echo "$mermaid_states"))

    if [[ -n "$yaml_only" || -n "$mermaid_only" ]]; then
        echo "ERROR: $template: state mismatch between YAML and $(basename "$mermaid")"
        if [[ -n "$yaml_only" ]]; then
            echo "  In YAML only: $(echo "$yaml_only" | tr '\n' ' ')"
        fi
        if [[ -n "$mermaid_only" ]]; then
            echo "  In mermaid only: $(echo "$mermaid_only" | tr '\n' ' ')"
        fi
        ERRORS=$((ERRORS + 1))
    fi
}

# ---------------------------------------------------------------------------
# Check 2: default_template: references point to existing files
# ---------------------------------------------------------------------------

check_default_template_refs() {
    local template="$1"
    local dir
    dir="$(dirname "$template")"

    while IFS= read -r line; do
        local ref
        ref=$(echo "$line" | sed 's/.*default_template:[[:space:]]*//' | tr -d "'\"\r")
        if [[ -n "$ref" ]]; then
            local target="${dir}/${ref}"
            if [[ ! -f "$target" ]]; then
                echo "ERROR: $template: default_template '$ref' not found (expected at $target)"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    done < <(grep 'default_template:' "$template" 2>/dev/null || true)
}

# ---------------------------------------------------------------------------
# Check 3: no hardcoded workflow names in koto next calls
# ---------------------------------------------------------------------------

check_hardcoded_names() {
    local template="$1"

    # Extract the `name:` field from YAML frontmatter (first occurrence)
    local name
    name=$(awk '
        BEGIN { count = 0 }
        /^---$/ { count++; if (count == 2) exit; next }
        count == 1 && /^name:/ { print $2; exit }
    ' "$template")

    if [[ -z "$name" ]]; then
        return 0  # No name in frontmatter, skip check
    fi

    # Extract only the directive section (after the closing --- of frontmatter)
    # and look for "koto next <name>" with the literal name (not {{SESSION_NAME}})
    local matches
    matches=$(awk '/^---$/{count++} count>=2' "$template" \
        | grep -F "koto next ${name}" 2>/dev/null || true)

    if [[ -n "$matches" ]]; then
        echo "ERROR: $template: hardcoded workflow name '$name' in koto next call"
        echo "  Use koto next {{SESSION_NAME}} instead"
        while IFS= read -r m; do
            echo "  > $m"
        done <<< "$matches"
        ERRORS=$((ERRORS + 1))
    fi
}

# ---------------------------------------------------------------------------
# Check 4: gate commands shared across templates stay identical
#
# Some templates are near-copies of one another and carry the same gate under
# the same name. When one copy is fixed and the other is not, the workflows
# silently disagree about what a gate means -- that is how issue #244 got two
# templates gating CI on the same wrong expression. This check makes the
# duplication mechanical rather than a matter of remembering.
# ---------------------------------------------------------------------------

# Emits one "<gate-name>\t<command>" line per gate that defines a command.
#
# Only the single-line `command: "..."` form is understood, which is the form
# every gate in this repo uses. A YAML block scalar (`command: >` or `command: |`)
# would put the body on following lines where this cannot see it, and comparing
# the empty remainders would make two different commands look identical. So a
# block scalar is reported as its own error rather than quietly compared: the
# whole point of this check is that it must not pass on something it did not read.
extract_gate_commands() {
    local template="$1"
    awk '
        /^    gates:[[:space:]]*$/ { in_gates = 1; gate = ""; next }
        in_gates && /^      [a-z_][a-z_0-9]*:[[:space:]]*$/ {
            gate = $0
            sub(/:.*/, "", gate)
            sub(/^[[:space:]]+/, "", gate)
            next
        }
        in_gates && gate != "" && /^        command:/ {
            cmd = $0
            sub(/^        command:[[:space:]]*/, "", cmd)
            if (cmd ~ /^[|>][0-9+-]*[[:space:]]*$/ || cmd == "") {
                print "UNREADABLE\t" gate "\t"
            } else {
                print "COMMAND\t" gate "\t" cmd
            }
            next
        }
        /^  [a-z_]/ { in_gates = 0 }
    ' "$template"
}

check_shared_gate_commands() {
    local templates=("$@")

    # Fewer than two templates means there is nothing to compare against.
    if [[ ${#templates[@]} -lt 2 ]]; then
        return 0
    fi

    # Each row is "<template>\t<kind>\t<gate>\t<command>", where kind is COMMAND
    # for a gate this can read and UNREADABLE for one it cannot.
    local rows=""
    local t line
    for t in "${templates[@]}"; do
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            rows+="${t}"$'\t'"${line}"$'\n'
        done < <(extract_gate_commands "$t")
    done

    [[ -z "$rows" ]] && return 0

    # A gate whose command could not be read cannot be compared, so say so
    # rather than treating it as agreeing with everything.
    local unreadable
    unreadable=$(printf '%s' "$rows" | awk -F'\t' '$2 == "UNREADABLE" { print "  " $1 ": " $3 }' | sort -u)
    if [[ -n "$unreadable" ]]; then
        echo "ERROR: gate command is not a single-line scalar, so it cannot be compared across templates"
        printf '%s\n' "$unreadable"
        ERRORS=$((ERRORS + 1))
    fi

    local gate variants
    while IFS= read -r gate; do
        [[ -z "$gate" ]] && continue

        variants=$(printf '%s' "$rows" \
            | awk -F'\t' -v g="$gate" '$2 == "COMMAND" && $3 == g { print $4 }' | sort -u)

        if [[ $(printf '%s\n' "$variants" | wc -l) -gt 1 ]]; then
            echo "ERROR: gate '$gate' has drifted between templates"
            local owner
            while IFS= read -r owner; do
                echo "  $owner"
            done < <(printf '%s' "$rows" \
                | awk -F'\t' -v g="$gate" '$2 == "COMMAND" && $3 == g { print $1 ": " $4 }' | sort -u)
            ERRORS=$((ERRORS + 1))
        fi
    done < <(printf '%s' "$rows" | awk -F'\t' '$2 == "COMMAND" { print $3 }' | sort | uniq -d)
}

# ---------------------------------------------------------------------------
# Main: determine files to validate
# ---------------------------------------------------------------------------

check_template() {
    local template="$1"
    local dir basename mermaid_file

    dir="$(dirname "$template")"
    basename="$(basename "$template" .md)"
    mermaid_file="${dir}/${basename}.mermaid.md"

    # Check 1: only when companion mermaid file exists
    if [[ -f "$mermaid_file" ]]; then
        check_state_consistency "$template" "$mermaid_file"
    fi

    # Check 2: default_template references
    check_default_template_refs "$template" "$dir"

    # Check 3: hardcoded workflow names
    check_hardcoded_names "$template"
}

TEMPLATE_SET=()

if [[ $# -gt 0 ]]; then
    TEMPLATE_SET=("$@")
else
    while IFS= read -r f; do
        TEMPLATE_SET+=("$f")
    done < <(find . -path "*/koto-templates/*.md" ! -name "*.mermaid.md" -type f 2>/dev/null | sort)
fi

for f in "${TEMPLATE_SET[@]+"${TEMPLATE_SET[@]}"}"; do
    check_template "$f"
done

# Check 4 compares templates against each other, so it runs once over the set.
check_shared_gate_commands "${TEMPLATE_SET[@]+"${TEMPLATE_SET[@]}"}"

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo "Validation failed: ${ERRORS} error(s) found"
    exit 1
else
    echo "All templates valid"
fi
