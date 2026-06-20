#!/usr/bin/env bash
#
# plan-to-tasks.sh - Emit koto task-entry JSON from a PLAN.md document
#
# Reads a PLAN.md path and outputs a JSON array of koto task-entry objects on
# stdout. Each object has the shape: {"name":"...","vars":{...},"waits_on":[...]}.
# The template field is omitted.
#
# Supports single-pr, multi-pr, and coordinated execution modes as indicated by
# the PLAN frontmatter's execution_mode field.
#
# Coordinated mode (the multi-repo generalization defined in
# references/coordination-strategy.md) collapses the issue-level waits_on graph
# into a (repo, pr_group)-level two-node merge-order DAG: PR nodes (one per
# (repo, pr_group) unit) plus non-PR gate nodes. After contraction it runs the
# R13 acyclicity check; on a contraction cycle it applies the R16-vs-R13
# discriminator (split-at-seam / re-sequence) and either resolves to an acyclic
# order or refuses (exit 2). It NEVER emits a cyclic order.
#
# Usage:
#   plan-to-tasks.sh <PLAN.md-path>
#
# Exit codes:
#   0 - success
#   1 - malformed input (file not found, unreadable, or jq missing)
#   2 - PLAN schema mismatch, unsanitizable name, or unschedulable
#       coordinated effort (irreducible contraction cycle / cross-repo
#       atomicity)

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

# Convert a bash array (passed by nameref) to a JSON array on stdout.
# Handles empty arrays correctly (returns []).
# Usage: array_to_json <array-variable-name>
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

    # First pass: collect all issue outlines with their titles, dependencies,
    # optional Type, and optional Files annotations.
    local -a issue_numbers=()
    local -a issue_titles=()
    local -a issue_deps_raw=()
    local -a issue_types=()    # empty string = not specified
    local -a issue_files=()    # space-separated list of backtick-quoted paths (no backticks)

    # 64 chars: koto rejects names with length_out_of_range above this limit (empirically verified)
    local KOTO_NAME_MAX=64
    local in_section=0
    local in_deps_section=0
    local current_number=""
    local current_title=""
    local current_deps=""
    local current_type=""
    local current_files=""

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
                issue_types+=("$current_type")
                issue_files+=("$current_files")
            fi
            current_number="${BASH_REMATCH[1]}"
            current_title="${BASH_REMATCH[2]}"
            current_deps=""
            current_type=""
            current_files=""
            in_deps_section=0
            continue
        fi

        # Detect dependencies line within an issue outline.
        # Accept both colon placements (#156):
        #   **Dependencies**: ...    (canonical, colon outside bold)
        #   **Dependencies:** ...    (colon inside bold — silently dropped before this fix)
        if [[ -n "$current_number" && "$line" =~ \*\*Dependencies:?\*\*:?[[:space:]]*(.+)$ ]]; then
            current_deps="${BASH_REMATCH[1]}"
            # Remove trailing period
            current_deps="${current_deps%.}"
            continue
        fi

        # Detect **Type**: line (optional field)
        if [[ -n "$current_number" && "$line" =~ \*\*Type\*\*:[[:space:]]*([a-zA-Z]+) ]]; then
            current_type=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
            continue
        fi

        # Detect **Files**: line (optional field)
        # Extract only backtick-quoted tokens, e.g. `path/to/file.md`
        if [[ -n "$current_number" && "$line" =~ \*\*Files\*\*: ]]; then
            # Extract all backtick-quoted tokens using sed.
            # Matches `token` patterns and outputs one token per line.
            local extracted_files
            extracted_files=$(echo "$line" | grep -o '`[^`]*`' | tr -d '`' | tr '\n' ' ' | sed 's/ $//')
            current_files="$extracted_files"
            continue
        fi

        # Detect section-header dependency format: ### Dependencies
        if [[ -n "$current_number" && "$line" =~ ^###[[:space:]]+Dependencies([[:space:]]|$) ]]; then
            in_deps_section=1
            continue
        fi

        # Accumulate lines inside a ### Dependencies section
        if [[ -n "$current_number" && $in_deps_section -eq 1 ]]; then
            if [[ -z "$line" ]]; then
                continue
            elif [[ "$line" =~ ^---$ ]]; then
                in_deps_section=0
                continue
            elif [[ "$line" =~ ^### ]]; then
                # Another ### heading ends the deps section.
                # Intentional fall-through: the line is processed by the heading
                # checks below (e.g., ### Issue N: Title saves the current issue).
                in_deps_section=0
            else
                # Accumulate the line as dependency content
                if [[ -n "$current_deps" ]]; then
                    current_deps="${current_deps}, ${line}"
                else
                    current_deps="$line"
                fi
                continue
            fi
        fi
    done < "$file"

    # Save last issue
    if [[ -n "$current_number" ]]; then
        issue_numbers+=("$current_number")
        issue_titles+=("$current_title")
        issue_deps_raw+=("$current_deps")
        issue_types+=("$current_type")
        issue_files+=("$current_files")
    fi

    local count="${#issue_numbers[@]}"
    if [[ $count -eq 0 ]]; then
        die_schema "single-pr PLAN has no issue outlines in ## Issue Outlines section"
    fi

    # Asymmetric-empty-deps warning (#156, AC2.1/AC2.2):
    # When a multi-issue single-pr PLAN has SOME issues with declared deps AND
    # SOME with empty deps (excluding `None`), warn that the regex previously
    # silently dropped edges authored with `**Dependencies:**` (colon inside
    # bold). After this fix both colon placements parse identically, but the
    # asymmetry pattern is still suspicious enough to flag for the author.
    if [[ $count -ge 2 ]]; then
        local empty_count=0
        local nonempty_count=0
        for i in "${!issue_numbers[@]}"; do
            local d="${issue_deps_raw[$i]}"
            # Treat literal "None" as an empty declaration (legitimate
            # strictly-independent issue); only count truly empty as suspicious.
            if [[ -z "$d" ]]; then
                empty_count=$((empty_count + 1))
            else
                nonempty_count=$((nonempty_count + 1))
            fi
        done
        if [[ $empty_count -gt 0 && $nonempty_count -gt 0 ]]; then
            log "Warning: asymmetric empty-deps detected (${empty_count} issue(s) with no \`**Dependencies**:\` line, ${nonempty_count} issue(s) with one). Likely authoring cause: an issue outline used \`**Dependencies:**\` (colon inside bold) where \`**Dependencies**:\` (colon outside bold) was expected, or the line was omitted. Both colon placements now parse identically, but verify each outline declares dependencies explicitly (use \`**Dependencies**: None\` for strictly-independent issues)."
        fi
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

        local base_name="o-${slug}"

        # Truncate name if it exceeds koto's maximum length
        if [[ ${#base_name} -gt $KOTO_NAME_MAX ]]; then
            local orig_base="$base_name"
            base_name="${base_name:0:$KOTO_NAME_MAX}"
            # Strip trailing dash introduced by truncation
            while [[ "${base_name: -1}" == "-" ]]; do
                base_name="${base_name%?}"
            done
            log "Warning: name '${orig_base}' (${#orig_base} chars) truncated to '${base_name}'"
        fi

        if ! validate_name "$base_name"; then
            die_schema "generated name '${base_name}' violates R9 regex ^[a-z][a-z0-9-]*$"
        fi

        # Handle collisions.
        # slug_counts stores the number of times a base_name has appeared.
        # The first occurrence (count=1) gets no suffix; subsequent occurrences
        # get a numeric suffix equal to their count (e.g. -2, -3).
        if [[ -z "${slug_counts[$base_name]+x}" ]]; then
            slug_counts[$base_name]=1
            issue_names+=("$base_name")
        else
            local count_val="${slug_counts[$base_name]}"
            ((count_val++)) || true
            slug_counts[$base_name]=$count_val
            local suffixed_name="${base_name}-${count_val}"
            if [[ ${#suffixed_name} -gt $KOTO_NAME_MAX ]]; then
                suffixed_name="${suffixed_name:0:$KOTO_NAME_MAX}"
                while [[ "${suffixed_name: -1}" == "-" ]]; do
                    suffixed_name="${suffixed_name%?}"
                done
            fi
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

    # Build a file-to-first-name map for Files-based waits_on edges.
    # When two outlines share a file path, the later one must wait on the earlier one.
    declare -A file_first_owner=()  # file_path -> name of first outline that declares it
    for i in "${!issue_numbers[@]}"; do
        local files_str="${issue_files[$i]}"
        if [[ -z "$files_str" ]]; then
            continue
        fi
        local name="${issue_names[$i]}"
        for fpath in $files_str; do
            if [[ -z "${file_first_owner[$fpath]+x}" ]]; then
                file_first_owner["$fpath"]="$name"
            fi
        done
    done

    # Third pass: build JSON entries
    local json_entries=()
    for i in "${!issue_numbers[@]}"; do
        local issue_num="${issue_numbers[$i]}"
        local name="${issue_names[$i]}"
        local deps_raw="${issue_deps_raw[$i]}"
        local issue_type="${issue_types[$i]}"
        local files_str="${issue_files[$i]}"

        # Parse waits_on from deps_raw
        local waits_on=()

        # Normalize <<ISSUE:N>> placeholders to "Issue N" before parsing.
        # /plan uses <<ISSUE:N>> in single-pr Issue Outlines; without this
        # normalization, all dependency edges are silently dropped.
        local re_ph='<<ISSUE:([0-9]+)>>'
        while [[ "$deps_raw" =~ $re_ph ]]; do
            local ph_num="${BASH_REMATCH[1]}"
            deps_raw="${deps_raw/<<ISSUE:${ph_num}>>/Issue ${ph_num}}"
        done

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

        # Add file-based waits_on edges: if this outline declares a file that
        # was already claimed by an earlier outline, wait on that earlier outline.
        if [[ -n "$files_str" ]]; then
            for fpath in $files_str; do
                local owner="${file_first_owner[$fpath]+x}"
                if [[ -n "$owner" ]]; then
                    local owner_name="${file_first_owner[$fpath]}"
                    # Only add if the owner is a different outline and not already in waits_on
                    if [[ "$owner_name" != "$name" ]]; then
                        local already=0
                        for w in "${waits_on[@]+"${waits_on[@]}"}"; do
                            if [[ "$w" == "$owner_name" ]]; then
                                already=1
                                break
                            fi
                        done
                        if [[ $already -eq 0 ]]; then
                            waits_on+=("$owner_name")
                        fi
                    fi
                fi
            done
        fi

        local waits_json
        waits_json=$(array_to_json waits_on)

        # Build the vars object. Always include ISSUE_SOURCE and ARTIFACT_PREFIX.
        # Include ISSUE_TYPE only when the outline specifies a **Type**: annotation.
        if [[ -n "$issue_type" ]]; then
            json_entries+=("$(jq -n \
                --arg name "$name" \
                --arg issue_source "plan_outline" \
                --arg artifact_prefix "$name" \
                --arg issue_type "$issue_type" \
                --argjson waits_on "$waits_json" \
                '{name: $name, vars: {ISSUE_SOURCE: $issue_source, ARTIFACT_PREFIX: $artifact_prefix, ISSUE_TYPE: $issue_type}, waits_on: $waits_on}')")
        else
            json_entries+=("$(jq -n \
                --arg name "$name" \
                --arg issue_source "plan_outline" \
                --arg artifact_prefix "$name" \
                --argjson waits_on "$waits_json" \
                '{name: $name, vars: {ISSUE_SOURCE: $issue_source, ARTIFACT_PREFIX: $artifact_prefix}, waits_on: $waits_on}')")
        fi
    done

    printf '%s\n' "${json_entries[@]}" | jq -s .
}

# Validate a pr_group tag against the coordination contract:
#   pr_group: ^[a-z][a-z0-9-]*$
# (mirrors the repo/pr_group re-validation rule in
# references/coordination-strategy.md, which is identical to the R9 name regex).
validate_pr_group() {
    local g="$1"
    [[ "$g" =~ ^[a-z][a-z0-9-]*$ ]]
}

# Validate a repo tag against the GitHub owner/repo charset
# (^[A-Za-z0-9][A-Za-z0-9._-]{0,38}$ per component, joined by a single slash).
# This is the same charset the F2 validator enforces in coordination.rs.
validate_repo_tag() {
    local r="$1"
    local owner="${r%%/*}"
    local name="${r#*/}"
    # Must contain exactly one slash and non-empty components.
    [[ "$r" == "$owner/$name" && -n "$owner" && -n "$name" && "$name" != *"/"* ]] || return 1
    [[ "$owner" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,38}$ ]] || return 1
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,38}$ ]] || return 1
    return 0
}

# Build a stable, R9-valid node id from a (repo, pr_group) pair.
# repo "owner/name" + group "g" -> "pr-<name>-<g>" (the owner is dropped from
# the public node id; the slug is sanitized to ^[a-z][a-z0-9-]*$).
pr_node_id() {
    local repo="$1" group="$2"
    local name="${repo#*/}"
    local slug
    slug=$(slugify "${name}-${group}")
    echo "pr-${slug}"
}

# Process coordinated mode: collapse the issue-level waits_on graph into a
# (repo, pr_group)-level two-node merge-order DAG (PR nodes + non-PR gate
# nodes), check post-contraction acyclicity (R13), apply the R16-vs-R13
# discriminator on a contraction cycle, and emit the serialized order.
#
# Per-issue tagging lives in the ## Implementation Issues table as an annotation
# row directly under the issue's entity row, mirroring the existing `^_Child:_`
# convention:
#
#   | [#1: feat ...](url) | None | testable |
#   | ^_Repo: owner/repo \| Group: api_ | | |
#
# A non-PR gate node is declared the same way, on a row whose first cell is a
# gate marker:
#
#   | ^_Gate: publish-foo \| After: pr-...,  \| Before: pr-..._ | | |
process_coordinated() {
    local file="$1"

    # ---- Pass 1: parse the Implementation Issues table into issue records ----
    # We reuse the multi-pr table walk to find issue numbers + dependency cells,
    # but additionally capture the `^_Repo: ... | Group: ..._` annotation row and
    # the `^_Gate: ... | After: ... | Before: ..._` gate rows.
    local in_section=0
    local dep_col=0
    local re_issue_num="#([0-9]+)"

    # Parallel arrays keyed by appearance order.
    local -a issue_nums=()
    local -a issue_deps=()
    local -a issue_repos=()
    local -a issue_groups=()
    local last_issue_idx=-1

    # Gate declarations: name|after-csv|before-csv per entry.
    local -a gates=()

    while IFS= read -r line; do
        if [[ "$line" =~ ^##[[:space:]]+Implementation[[:space:]]+Issues ]]; then
            in_section=1
            continue
        fi
        if [[ $in_section -eq 1 && "$line" =~ ^##[[:space:]] ]]; then
            break
        fi
        [[ $in_section -eq 0 ]] && continue

        # Separator rows.
        if [[ "$line" =~ ^\|[-|[:space:]]+$ ]]; then
            continue
        fi

        # Header row: locate the Dependencies column.
        if [[ "$dep_col" -eq 0 && "$line" =~ \|.*Issue.*\|.*Dependencies ]]; then
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

        # Gate annotation row. The Gate/After/Before fields are separated by an
        # escaped pipe (`\|`) so the row stays a single markdown table cell.
        if [[ "$line" =~ \^_Gate:[[:space:]]*(.+)\\\|[[:space:]]*After:[[:space:]]*(.*)\\\|[[:space:]]*Before:[[:space:]]*([^_]*)_ ]]; then
            local gname="${BASH_REMATCH[1]}"
            local gafter="${BASH_REMATCH[2]}"
            local gbefore="${BASH_REMATCH[3]}"
            # Trim each component.
            gname="${gname#"${gname%%[![:space:]]*}"}"; gname="${gname%"${gname##*[![:space:]]}"}"
            gafter="${gafter#"${gafter%%[![:space:]]*}"}"; gafter="${gafter%"${gafter##*[![:space:]]}"}"
            gbefore="${gbefore#"${gbefore%%[![:space:]]*}"}"; gbefore="${gbefore%"${gbefore##*[![:space:]]}"}"
            if ! validate_pr_group "$gname"; then
                die_schema "coordinated gate name '${gname}' violates ^[a-z][a-z0-9-]*\$"
            fi
            gates+=("${gname}|${gafter}|${gbefore}")
            continue
        fi

        # Repo/Group annotation row for the most recent issue. Repo and Group
        # are separated by an escaped pipe (`\|`) to stay one table cell.
        if [[ "$line" =~ \^_Repo:[[:space:]]*(.+)\\\|[[:space:]]*Group:[[:space:]]*([^_]+)_ ]]; then
            local rtag="${BASH_REMATCH[1]}"
            local gtag="${BASH_REMATCH[2]}"
            rtag="${rtag#"${rtag%%[![:space:]]*}"}"; rtag="${rtag%"${rtag##*[![:space:]]}"}"
            gtag="${gtag#"${gtag%%[![:space:]]*}"}"; gtag="${gtag%"${gtag##*[![:space:]]}"}"
            if [[ $last_issue_idx -lt 0 ]]; then
                die_schema "coordinated PLAN has a Repo/Group annotation with no preceding issue row"
            fi
            if ! validate_repo_tag "$rtag"; then
                die_schema "coordinated issue #${issue_nums[$last_issue_idx]} has invalid repo tag '${rtag}'"
            fi
            if ! validate_pr_group "$gtag"; then
                die_schema "coordinated issue #${issue_nums[$last_issue_idx]} has invalid pr_group tag '${gtag}'"
            fi
            issue_repos[$last_issue_idx]="$rtag"
            issue_groups[$last_issue_idx]="$gtag"
            continue
        fi

        # Entity rows: start with | and carry #N in the first data cell.
        if [[ "$line" =~ ^\| && "$line" =~ $re_issue_num ]]; then
            local issue_num="${BASH_REMATCH[1]}"

            local IFS_SAVE2="$IFS"
            IFS='|'
            local -a data_cols=()
            read -ra data_cols <<< "$line"
            IFS="$IFS_SAVE2"

            local deps_cell=""
            if [[ "$dep_col" -gt 0 && "$dep_col" -lt "${#data_cols[@]}" ]]; then
                deps_cell="${data_cols[$dep_col]}"
            fi
            deps_cell="${deps_cell#"${deps_cell%%[![:space:]]*}"}"
            deps_cell="${deps_cell%"${deps_cell##*[![:space:]]}"}"

            issue_nums+=("$issue_num")
            issue_deps+=("$deps_cell")
            issue_repos+=("")
            issue_groups+=("")
            last_issue_idx=$(( ${#issue_nums[@]} - 1 ))
        fi
    done < "$file"

    local n_issues="${#issue_nums[@]}"
    if [[ $n_issues -eq 0 ]]; then
        die_schema "coordinated PLAN has no rows in Implementation Issues table"
    fi

    # Every coordinated issue MUST carry repo + pr_group tags.
    local idx
    for idx in "${!issue_nums[@]}"; do
        if [[ -z "${issue_repos[$idx]}" || -z "${issue_groups[$idx]}" ]]; then
            die_schema "coordinated issue #${issue_nums[$idx]} is missing a Repo/Group annotation row (\`^_Repo: owner/repo | Group: <pr-group>_\`)"
        fi
    done

    # ---- Initial node assignment: each issue -> its (repo, pr_group) PR node.
    # `issue_to_node` is the mutable assignment the resolver re-writes when it
    # splits a repo at the seam. The issue-level deps in `issue_deps` are the
    # source of truth the contraction re-derives edges from on every attempt.
    declare -A issue_to_node=()
    for idx in "${!issue_nums[@]}"; do
        local node0
        node0=$(pr_node_id "${issue_repos[$idx]}" "${issue_groups[$idx]}")
        if ! validate_name "$node0"; then
            die_schema "derived PR node id '${node0}' violates R9 regex ^[a-z][a-z0-9-]*\$"
        fi
        issue_to_node["${issue_nums[$idx]}"]="$node0"
    done

    # `is_gate` marks gate node ids; populated by build_contracted_graph.
    declare -A is_gate=()
    # `node_order` + `edges_set` are the contracted graph, rebuilt each attempt.
    local -a node_order=()
    declare -A edges_set=()

    # ---- Contraction + acyclicity loop (R13) with split-at-seam resolution.
    # Build the contracted (repo, pr_group) graph, attempt a topological order,
    # and on a contraction cycle apply the R16-vs-R13 discriminator: split a
    # repo node on the residual cycle into per-issue PR nodes (re-sequence at
    # the seam) and retry. If no split yields an acyclic order, refuse.
    local serialized=""
    local resolved=0
    # Bounded retries: at most one split per issue (worst case every issue
    # becomes its own PR node), so the loop terminates.
    local attempt
    for (( attempt=0; attempt <= n_issues; attempt++ )); do
        build_contracted_graph
        if kahn_order; then
            serialized="$KAHN_ORDER"
            resolved=1
            break
        fi
        # kahn_order failed: $RESIDUAL_NODES holds the cyclic PR nodes.
        # Pick a splittable victim (a PR node, not a gate, that maps >1 issue).
        local victim=""
        local cand
        for cand in $RESIDUAL_NODES; do
            [[ -n "${is_gate[$cand]+x}" ]] && continue
            # Count issues mapped to this node.
            local cnt=0
            local inum
            for inum in "${issue_nums[@]}"; do
                [[ "${issue_to_node[$inum]}" == "$cand" ]] && cnt=$(( cnt + 1 ))
            done
            if [[ $cnt -gt 1 ]]; then
                victim="$cand"
                break
            fi
        done
        if [[ -z "$victim" ]]; then
            # No multi-issue PR node on the cycle to split: the cycle is
            # irreducible (true cross-repo atomicity). Refuse — never emit a
            # cyclic order.
            log "Refusing: contraction cycle among PR nodes [${RESIDUAL_NODES}] has no split-at-seam resolution (true cross-repo atomicity)."
            die_schema "coordinated effort is unschedulable: no acyclic merge order exists after contraction (cross-repo atomicity). Reshape into a compatible-intermediate sequence per references/coordination-strategy.md."
        fi
        # Split the victim at the seam: give each of its issues its own PR node.
        split_repo_at_seam "$victim"
    done

    if [[ $resolved -ne 1 ]]; then
        die_schema "coordinated effort is unschedulable: contraction did not converge to an acyclic order."
    fi

    # ---- Emit the serialized two-node order as JSON ----
    # Each node becomes a task entry; waits_on lists its immediate predecessors.
    local -a json_entries=()
    local node
    for node in $serialized; do
        local -a waits_on=()
        local pred_node
        for pred_node in "${node_order[@]}"; do
            if [[ -n "${edges_set["${pred_node}->${node}"]+x}" ]]; then
                waits_on+=("$pred_node")
            fi
        done
        local waits_json
        waits_json=$(array_to_json waits_on)
        local kind="pr"
        [[ -n "${is_gate[$node]+x}" ]] && kind="gate"
        json_entries+=("$(jq -n \
            --arg name "$node" \
            --arg node_kind "$kind" \
            --argjson waits_on "$waits_json" \
            '{name: $name, vars: {NODE_KIND: $node_kind}, waits_on: $waits_on}')")
    done

    printf '%s\n' "${json_entries[@]}" | jq -s .
}

# Re-derive the contracted graph (node_order, edges_set, is_gate) from the
# current issue_to_node assignment + issue_deps + gates. Idempotent: clears and
# rebuilds the three structures, so the resolver can call it after every split.
#
# issue_nums, issue_deps, issue_to_node, gates, node_order, edges_set, and
# is_gate are in scope from process_coordinated (bash dynamic scope).
build_contracted_graph() {
    node_order=()
    local e
    for e in "${!edges_set[@]}"; do unset 'edges_set[$e]'; done
    for e in "${!is_gate[@]}"; do unset 'is_gate[$e]'; done

    declare -A seen=()
    local idx
    # PR nodes in first-appearance order.
    for idx in "${!issue_nums[@]}"; do
        local node="${issue_to_node[${issue_nums[$idx]}]}"
        if [[ -z "${seen[$node]+x}" ]]; then
            seen[$node]=1
            node_order+=("$node")
        fi
    done

    # Contract issue-level waits_on into PR-node edges.
    for idx in "${!issue_nums[@]}"; do
        local this_node="${issue_to_node[${issue_nums[$idx]}]}"
        local deps="${issue_deps[$idx]}"
        [[ "$deps" == "None" || -z "$deps" ]] && continue
        local re_ref="#([0-9]+)"
        local remaining="$deps"
        while [[ "$remaining" =~ $re_ref ]]; do
            local dep_num="${BASH_REMATCH[1]}"
            remaining="${remaining#*#${dep_num}}"
            if [[ -z "${issue_to_node[$dep_num]+x}" ]]; then
                die_schema "coordinated issue #${issue_nums[$idx]} references unknown dependency #${dep_num}"
            fi
            local dep_node_id="${issue_to_node[$dep_num]}"
            if [[ "$dep_node_id" != "$this_node" ]]; then
                edges_set["${dep_node_id}->${this_node}"]=1
            fi
        done
    done

    # Gate nodes + their After/Before edges.
    local g
    for g in "${gates[@]+"${gates[@]}"}"; do
        local gname="${g%%|*}"
        local rest="${g#*|}"
        local gafter="${rest%%|*}"
        local gbefore="${rest#*|}"
        local gnode="gate-${gname}"
        if ! validate_name "$gnode"; then
            die_schema "derived gate node id '${gnode}' violates R9 regex ^[a-z][a-z0-9-]*\$"
        fi
        if [[ -z "${seen[$gnode]+x}" ]]; then
            seen[$gnode]=1
            node_order+=("$gnode")
        fi
        is_gate[$gnode]=1
        local pred
        for pred in ${gafter//,/ }; do
            [[ -z "$pred" ]] && continue
            edges_set["${pred}->${gnode}"]=1
        done
        local succ
        for succ in ${gbefore//,/ }; do
            [[ -z "$succ" ]] && continue
            edges_set["${gnode}->${succ}"]=1
        done
    done
}

# Topologically order the contracted graph via Kahn's algorithm. On success,
# sets the global KAHN_ORDER to the space-separated node order and returns 0.
# On a cycle, sets the global RESIDUAL_NODES to the space-separated nodes that
# never drained and returns 1. Writes globals (not stdout) so the caller can
# read RESIDUAL_NODES without a subshell. node_order + edges_set are in scope.
RESIDUAL_NODES=""
KAHN_ORDER=""
kahn_order() {
    local -a nodes=("${node_order[@]}")
    declare -A indeg=()
    local nd
    for nd in "${nodes[@]}"; do indeg[$nd]=0; done
    local e
    for e in "${!edges_set[@]}"; do
        local to="${e#*->}"
        indeg[$to]=$(( ${indeg[$to]} + 1 ))
    done

    local -a order=()
    local -a queue=()
    for nd in "${nodes[@]}"; do
        [[ "${indeg[$nd]}" -eq 0 ]] && queue+=("$nd")
    done
    local processed=0
    while [[ ${#queue[@]} -gt 0 ]]; do
        local cur="${queue[0]}"
        queue=("${queue[@]:1}")
        order+=("$cur")
        processed=$(( processed + 1 ))
        local nbr
        for nbr in "${nodes[@]}"; do
            if [[ -n "${edges_set["${cur}->${nbr}"]+x}" ]]; then
                indeg[$nbr]=$(( ${indeg[$nbr]} - 1 ))
                [[ "${indeg[$nbr]}" -eq 0 ]] && queue+=("$nbr")
            fi
        done
    done

    if [[ $processed -eq ${#nodes[@]} ]]; then
        KAHN_ORDER="${order[*]}"
        return 0
    fi

    # Cycle: collect residual nodes (never ordered).
    local -a residual=()
    for nd in "${nodes[@]}"; do
        local in_order=0
        local o
        for o in "${order[@]+"${order[@]}"}"; do
            [[ "$o" == "$nd" ]] && { in_order=1; break; }
        done
        [[ $in_order -eq 0 ]] && residual+=("$nd")
    done
    RESIDUAL_NODES="${residual[*]}"
    return 1
}

# Split a repo PR node at the seam (R16-vs-R13 resolution): re-assign each issue
# currently mapped to $1 to its own per-issue PR node id, so a repo that
# participated in an X->Y->X contraction cycle through *distinct* issues is
# re-sequenced into orderable halves. The issue-level edges then re-contract
# without the cross-repo cycle. issue_to_node is mutated in place; the caller
# re-runs build_contracted_graph + kahn_order.
split_repo_at_seam() {
    local victim="$1"
    log "Resolving contraction cycle: splitting PR node '${victim}' at the seam into per-issue PR nodes."
    local idx
    for idx in "${!issue_nums[@]}"; do
        local inum="${issue_nums[$idx]}"
        if [[ "${issue_to_node[$inum]}" == "$victim" ]]; then
            local split_node
            split_node=$(slugify "${victim}-i${inum}")
            if ! validate_name "$split_node"; then
                die_schema "derived split PR node id '${split_node}' violates R9 regex ^[a-z][a-z0-9-]*\$"
            fi
            issue_to_node["$inum"]="$split_node"
        fi
    done
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
    coordinated)
        log "Processing coordinated PLAN: $PLAN_PATH"
        process_coordinated "$PLAN_PATH"
        ;;
    *)
        die_schema "Unknown execution_mode '${execution_mode}': expected 'single-pr', 'multi-pr', or 'coordinated'"
        ;;
esac
