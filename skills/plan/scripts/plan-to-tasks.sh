#!/usr/bin/env bash
#
# plan-to-tasks.sh - Emit koto task-entry JSON from a PLAN.md document
#
# Reads a PLAN.md path and outputs a JSON array of koto task-entry objects on
# stdout. Each object has the shape: {"name":"...","vars":{...},"waits_on":[...]}.
# The template field is omitted.
#
# Supports both single-pr and multi-pr execution modes as indicated by the
# PLAN frontmatter's execution_mode field.
#
# Usage:
#   plan-to-tasks.sh <PLAN.md-path>
#
# Exit codes:
#   0 - success
#   1 - malformed input (file not found, unreadable, or jq missing)
#   2 - PLAN schema mismatch or unsanitizable name

set -euo pipefail

PLAN_PATH=""

usage() {
    cat >&2 <<'EOF'
Usage: plan-to-tasks.sh <PLAN.md-path>

Reads a PLAN.md and emits a JSON array of koto task-entry objects on stdout.

Exit codes:
  0 - success
  1 - malformed input (file not found, unreadable, or jq missing)
  2 - PLAN schema mismatch or unsanitizable name
EOF
    exit 1
}

log() {
    echo "[plan-to-tasks] $*" >&2
}

die_input() {
    log "Error: $*"
    exit 1
}

die_schema() {
    log "Error: $*"
    exit 2
}

# Validate a task name against R9: ^[a-z][a-z0-9-]*$
validate_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        return 1
    fi
    return 0
}

# Convert a bash array of strings to a JSON array.
# Handles empty arrays correctly (returns []).
# Usage: array_to_json_array "${arr[@]+"${arr[@]}"}"
# But call as: array_to_json_array_safe arr_name
# Actually just inline with length check.
# Returns JSON array string on stdout.
array_to_json() {
    local -n _arr_ref=$1
    if [[ ${#_arr_ref[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${_arr_ref[@]}" | jq -R . | jq -s .
    fi
}

# Sanitize a title to a slug: lowercase, replace non-[a-z0-9] with -, collapse
# multiple -, strip leading/trailing -
slugify() {
    local title="$1"
    local slug
    slug=$(echo "$title" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]/-/g' \
        | sed 's/-\+/-/g' \
        | sed 's/^-//;s/-$//')
    echo "$slug"
}

# Parse YAML frontmatter block (between first --- and second ---)
# Returns the value of a given key (simple scalar values only)
parse_frontmatter_key() {
    local content="$1"
    local key="$2"
    echo "$content" | awk -v key="$key" '
        /^---$/ {
            count++
            if (count == 2) exit
            next
        }
        count == 1 {
            if (match($0, "^" key ": *(.+)$", a)) {
                # Strip surrounding quotes if present
                val = a[1]
                gsub(/^["'"'"']|["'"'"']$/, "", val)
                print val
            }
        }
    '
}

# Extract the frontmatter block as raw text (between --- markers)
extract_frontmatter() {
    local file="$1"
    awk '
        /^---$/ {
            count++
            if (count == 1) { next }
            if (count == 2) { exit }
        }
        count == 1 { print }
    ' "$file"
}

# Process multi-pr mode: parse the ## Implementation Issues table
process_multi_pr() {
    local file="$1"

    # Parse the Implementation Issues section in two passes.
    # First, find the header row to determine the Dependencies column index.
    # Then extract issue number + deps from each data row.
    local in_section=0
    local dep_col=0
    local entries=()
    local re_issue_num="#([0-9]+)"

    while IFS= read -r line; do
        # Detect section header
        if [[ "$line" =~ ^##[[:space:]]+Implementation[[:space:]]+Issues ]]; then
            in_section=1
            continue
        fi
        # Stop at next ## section
        if [[ $in_section -eq 1 && "$line" =~ ^##[[:space:]] ]]; then
            break
        fi
        [[ $in_section -eq 0 ]] && continue

        # Skip separator rows (all pipes, dashes, spaces)
        if [[ "$line" =~ ^\|[-|[:space:]]+$ ]]; then
            continue
        fi

        # Detect the header row: contains "Issue" and "Dependencies"
        if [[ "$dep_col" -eq 0 && "$line" =~ \|.*Issue.*\|.*Dependencies ]]; then
            # Split by | to find the Dependencies column index
            local IFS_SAVE="$IFS"
            IFS='|'
            local -a header_cols=()
            read -ra header_cols <<< "$line"
            IFS="$IFS_SAVE"
            local hi
            for hi in "${!header_cols[@]}"; do
                local hcell="${header_cols[$hi]}"
                hcell="${hcell#"${hcell%%[![:space:]]*}"}"
                hcell="${hcell%"${hcell##*[![:space:]]}"}"
                if [[ "$hcell" == "Dependencies" ]]; then
                    dep_col=$hi
                    break
                fi
            done
            continue
        fi

        # Data rows: must start with | and have #N in first data cell
        if [[ "$line" =~ ^\| ]]; then
            # Extract issue number from the line using regex
            local issue_num=""
            local rest="$line"
            if [[ "$rest" =~ $re_issue_num ]]; then
                issue_num="${BASH_REMATCH[1]}"
            else
                continue
            fi

            # Extract the dependencies cell by column index or fallback
            local IFS_SAVE2="$IFS"
            IFS='|'
            local -a data_cols=()
            read -ra data_cols <<< "$line"
            IFS="$IFS_SAVE2"

            local deps_cell=""
            if [[ "$dep_col" -gt 0 && "$dep_col" -lt "${#data_cols[@]}" ]]; then
                deps_cell="${data_cols[$dep_col]}"
            else
                # Fallback: use last non-empty cell
                local di
                for (( di=${#data_cols[@]}-1; di>=0; di-- )); do
                    local dc="${data_cols[$di]}"
                    dc="${dc#"${dc%%[![:space:]]*}"}"
                    dc="${dc%"${dc##*[![:space:]]}"}"
                    if [[ -n "$dc" ]]; then
                        deps_cell="$dc"
                        break
                    fi
                done
            fi
            # Trim whitespace
            deps_cell="${deps_cell#"${deps_cell%%[![:space:]]*}"}"
            deps_cell="${deps_cell%"${deps_cell##*[![:space:]]}"}"

            entries+=("${issue_num}|${deps_cell}")
        fi
    done < "$file"

    if [[ ${#entries[@]} -eq 0 ]]; then
        die_schema "multi-pr PLAN has no rows in Implementation Issues table"
    fi

    # Build JSON array using jq
    local json_entries=()
    for entry in "${entries[@]}"; do
        local issue_num="${entry%%|*}"
        local deps_cell="${entry#*|}"
        local name="issue-${issue_num}"

        if ! validate_name "$name"; then
            die_schema "generated name '${name}' violates R9 regex ^[a-z][a-z0-9-]*$"
        fi

        # Parse dependencies: extract all #N references from deps_cell
        # Use a variable for the regex to avoid bash inline literal issues
        local re_issue_ref="#([0-9]+)"
        local waits_on=()
        if [[ "$deps_cell" != "None" && -n "$deps_cell" ]]; then
            while [[ "$deps_cell" =~ $re_issue_ref ]]; do
                local dep_num="${BASH_REMATCH[1]}"
                waits_on+=("issue-${dep_num}")
                # Remove the matched portion to find the next one
                deps_cell="${deps_cell#*#${dep_num}}"
            done
        fi

        local waits_json
        waits_json=$(array_to_json waits_on)

        json_entries+=("$(jq -n \
            --arg name "$name" \
            --arg issue_source "github" \
            --arg issue_number "$issue_num" \
            --argjson waits_on "$waits_json" \
            '{name: $name, vars: {ISSUE_SOURCE: $issue_source, ISSUE_NUMBER: $issue_number}, waits_on: $waits_on}')")
    done

    # Combine into array
    printf '%s\n' "${json_entries[@]}" | jq -s .
}

# Process single-pr mode: parse ## Issue Outlines section
process_single_pr() {
    local file="$1"

    # First pass: collect all issue outlines with their titles and dependencies
    local -a issue_numbers=()
    local -a issue_titles=()
    local -a issue_deps_raw=()

    local in_section=0
    local current_number=""
    local current_title=""
    local current_deps=""

    while IFS= read -r line; do
        # Detect section header
        if [[ "$line" =~ ^##[[:space:]]+Issue[[:space:]]+Outlines ]]; then
            in_section=1
            continue
        fi
        # Stop at next ## section (but not ### which are issue headings)
        if [[ $in_section -eq 1 && "$line" =~ ^##[[:space:]] && ! "$line" =~ ^###[[:space:]] ]]; then
            break
        fi
        [[ $in_section -eq 0 ]] && continue

        # Detect issue heading: ### Issue N: Title
        if [[ "$line" =~ ^###[[:space:]]+Issue[[:space:]]+([0-9]+):[[:space:]]*(.+)$ ]]; then
            # Save previous issue if any
            if [[ -n "$current_number" ]]; then
                issue_numbers+=("$current_number")
                issue_titles+=("$current_title")
                issue_deps_raw+=("$current_deps")
            fi
            current_number="${BASH_REMATCH[1]}"
            current_title="${BASH_REMATCH[2]}"
            current_deps=""
            continue
        fi

        # Detect dependencies line within an issue outline
        if [[ -n "$current_number" && "$line" =~ \*\*Dependencies\*\*:[[:space:]]*(.+)$ ]]; then
            current_deps="${BASH_REMATCH[1]}"
            # Remove trailing period
            current_deps="${current_deps%.}"
            continue
        fi
    done < "$file"

    # Save last issue
    if [[ -n "$current_number" ]]; then
        issue_numbers+=("$current_number")
        issue_titles+=("$current_title")
        issue_deps_raw+=("$current_deps")
    fi

    local count="${#issue_numbers[@]}"
    if [[ $count -eq 0 ]]; then
        die_schema "single-pr PLAN has no issue outlines in ## Issue Outlines section"
    fi

    # Second pass: compute names with slug + collision handling
    local -a issue_names=()
    local -A slug_counts=()

    for i in "${!issue_numbers[@]}"; do
        local title="${issue_titles[$i]}"
        local slug
        slug=$(slugify "$title")

        if [[ -z "$slug" ]]; then
            die_schema "issue ${issue_numbers[$i]} title '${title}' produces empty slug after sanitization"
        fi

        local base_name="outline-${slug}"

        if ! validate_name "$base_name"; then
            die_schema "generated name '${base_name}' violates R9 regex ^[a-z][a-z0-9-]*$"
        fi

        # Handle collisions
        if [[ -z "${slug_counts[$base_name]+x}" ]]; then
            slug_counts[$base_name]=1
            issue_names+=("$base_name")
        else
            local count_val="${slug_counts[$base_name]}"
            ((count_val++)) || true
            slug_counts[$base_name]=$count_val
            local suffixed_name="${base_name}-${count_val}"
            if ! validate_name "$suffixed_name"; then
                die_schema "generated name '${suffixed_name}' violates R9 regex ^[a-z][a-z0-9-]*$"
            fi
            issue_names+=("$suffixed_name")
        fi
    done

    # Build a map from issue number to name for dependency resolution
    declare -A number_to_name=()
    for i in "${!issue_numbers[@]}"; do
        number_to_name["${issue_numbers[$i]}"]="${issue_names[$i]}"
    done

    # Third pass: build JSON entries
    local json_entries=()
    for i in "${!issue_numbers[@]}"; do
        local issue_num="${issue_numbers[$i]}"
        local name="${issue_names[$i]}"
        local deps_raw="${issue_deps_raw[$i]}"

        # Parse waits_on from deps_raw
        local waits_on=()
        if [[ "$deps_raw" != "None" && -n "$deps_raw" ]]; then
            # Extract all "Issue N" references
            local remaining="$deps_raw"
            while [[ "$remaining" =~ Issue[[:space:]]+([0-9]+) ]]; do
                local dep_num="${BASH_REMATCH[1]}"
                if [[ -z "${number_to_name[$dep_num]+x}" ]]; then
                    die_schema "issue ${issue_num} references unknown dependency Issue ${dep_num}"
                fi
                waits_on+=("${number_to_name[$dep_num]}")
                remaining="${remaining#*Issue ${dep_num}}"
            done
        fi

        local waits_json
        waits_json=$(array_to_json waits_on)

        json_entries+=("$(jq -n \
            --arg name "$name" \
            --arg issue_source "plan_outline" \
            --arg artifact_prefix "$name" \
            --argjson waits_on "$waits_json" \
            '{name: $name, vars: {ISSUE_SOURCE: $issue_source, ARTIFACT_PREFIX: $artifact_prefix}, waits_on: $waits_on}')")
    done

    printf '%s\n' "${json_entries[@]}" | jq -s .
}

# ── Argument parsing ──

if [[ $# -eq 0 ]]; then
    usage
fi

case "$1" in
    -h|--help)
        usage
        ;;
    *)
        PLAN_PATH="$1"
        ;;
esac

if [[ $# -gt 1 ]]; then
    log "Error: too many arguments"
    usage
fi

# ── Prerequisites ──

if ! command -v jq &>/dev/null; then
    die_input "jq is required but not found in PATH"
fi

# ── File validation ──

if [[ ! -e "$PLAN_PATH" ]]; then
    die_input "file not found: $PLAN_PATH"
fi

if [[ ! -r "$PLAN_PATH" ]]; then
    die_input "file is not readable: $PLAN_PATH"
fi

# ── Frontmatter validation ──

# Check file starts with ---
first_line=$(head -1 "$PLAN_PATH")
if [[ "$first_line" != "---" ]]; then
    die_schema "PLAN file does not start with YAML frontmatter (expected '---' on line 1)"
fi

frontmatter=$(extract_frontmatter "$PLAN_PATH")

schema_val=$(echo "$frontmatter" | awk '/^schema:/ { gsub(/^schema: */, ""); print; exit }')
if [[ "$schema_val" != "plan/v1" ]]; then
    die_schema "PLAN frontmatter schema must be 'plan/v1', got: '${schema_val}'"
fi

execution_mode=$(echo "$frontmatter" | awk '/^execution_mode:/ { gsub(/^execution_mode: */, ""); print; exit }')
if [[ -z "$execution_mode" ]]; then
    die_schema "PLAN frontmatter missing required field: execution_mode"
fi

case "$execution_mode" in
    single-pr)
        log "Processing single-pr PLAN: $PLAN_PATH"
        process_single_pr "$PLAN_PATH"
        ;;
    multi-pr)
        log "Processing multi-pr PLAN: $PLAN_PATH"
        process_multi_pr "$PLAN_PATH"
        ;;
    *)
        die_schema "Unknown execution_mode '${execution_mode}': expected 'single-pr' or 'multi-pr'"
        ;;
esac
