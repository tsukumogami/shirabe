#!/usr/bin/env bash
# run-cascade.sh — Post-implementation artifact lifecycle cascade
# Part of the work-on skill
#
# Walks the upstream frontmatter chain from a completed PLAN doc and applies
# the appropriate lifecycle transition at each node (DESIGN → Current,
# PRD → Done, ROADMAP feature update + optional ROADMAP → Done).
#
# Usage: run-cascade.sh [--push] <plan-doc-path>
#
# Options:
#   --push    Commit and push staged changes. Without this flag, the script
#             stages changes and prints a per-file status summary but does not
#             commit or push. Use --push for automated cascade; omit for dry-run.
#
# Output: JSON to stdout (always, regardless of success or failure):
#   {
#     "cascade_status": "completed | partial | skipped",
#     "steps": [
#       {
#         "action": "delete_plan | transition_design | transition_prd |
#                    update_roadmap_feature | transition_roadmap",
#         "target": "<path being acted on>",
#         "found_in": "<path where reference was discovered>",
#         "status": "ok | skipped | failed",
#         "detail": "<required when status is skipped or failed>"
#       }
#     ]
#   }
#
# Exit codes:
#   0 — cascade ran (completed, partial, or skipped)
#   1 — PLAN doc not found or initial path validation failed

set -euo pipefail

# ── Global state ──────────────────────────────────────────────────────────────

PUSH=false
PLAN_DOC=""
REPO_ROOT=""
STEPS_JSON=""      # accumulates JSON step objects, comma-separated
ANY_FAILED=false
STAGED_FILES=()    # files staged for commit
HANDLE_DESIGN_NEW_PATH=""  # return value from handle_design (avoids subshell capture)

# ── Logging ───────────────────────────────────────────────────────────────────

log_warn() {
    echo "[cascade] WARNING: $*" >&2
}

log_info() {
    echo "[cascade] $*" >&2
}

# ── Inline utility: get_frontmatter_field ────────────────────────────────────
# Reads YAML frontmatter (between first --- pair), extracts named field value.
# Outputs the value or empty string. Never exits non-zero.
# Usage: get_frontmatter_field <field-name> <doc-path>

get_frontmatter_field() {
    local field="$1"
    local doc="$2"
    awk -v field="$field" '
        /^---$/ { count++; next }
        count == 2 { exit }
        count == 1 && $0 ~ "^" field ": " {
            sub("^" field ": *", "")
            # Strip surrounding quotes if present
            gsub(/^'"'"'|'"'"'$/, "")
            gsub(/^"|"$/, "")
            print
            exit
        }
    ' "$doc" 2>/dev/null || true
}

# ── Inline utility: validate_upstream_path ───────────────────────────────────
# Validates that a path is:
#   1. Within $REPO_ROOT (no path traversal)
#   2. A regular file (not symlink, pipe, or device)
#   3. Tracked by git
# Exits non-zero and logs a warning on any failure.
# Usage: validate_upstream_path <path>

validate_upstream_path() {
    local path="$1"

    # Resolve to absolute path
    local abs_path
    abs_path=$(realpath -m "$path" 2>/dev/null) || {
        log_warn "validate_upstream_path: realpath failed for '$path'"
        return 1
    }

    # Check path does not escape repo root
    if [[ "$abs_path" != "$REPO_ROOT"/* && "$abs_path" != "$REPO_ROOT" ]]; then
        log_warn "validate_upstream_path: '$path' resolves outside repository root ($REPO_ROOT)"
        return 1
    fi

    # Check it is a regular file (not symlink, pipe, device, directory)
    if [[ ! -f "$abs_path" ]] || [[ -L "$abs_path" ]]; then
        log_warn "validate_upstream_path: '$path' is not a regular file"
        return 1
    fi

    # Check file is tracked by git
    if ! git ls-files --error-unmatch "$abs_path" > /dev/null 2>&1; then
        log_warn "validate_upstream_path: '$path' is not tracked by git"
        return 1
    fi

    return 0
}

# ── Inline utility: check_issue_closed ───────────────────────────────────────
# Parses a GitHub issue URL, validates owner/repo against the current origin
# remote, and queries the issue state.
# Returns 0 if closed, 1 if open or if URL does not match current repo.
# Usage: check_issue_closed <github-issue-url>

check_issue_closed() {
    local url="$1"

    # Extract owner, repo, and issue number from URL
    # Expected format: https://github.com/<owner>/<repo>/issues/<number>
    local owner repo number
    owner=$(echo "$url" | sed -n 's|https://github.com/\([^/]*\)/.*|\1|p')
    repo=$(echo "$url" | sed -n 's|https://github.com/[^/]*/\([^/]*\)/.*|\1|p')
    number=$(echo "$url" | sed -n 's|.*/issues/\([0-9]*\)|\1|p')

    if [[ -z "$owner" || -z "$repo" || -z "$number" ]]; then
        log_warn "check_issue_closed: could not parse URL: $url"
        return 1
    fi

    # Validate owner/repo against origin remote
    local origin_url
    origin_url=$(git remote get-url origin 2>/dev/null) || {
        log_warn "check_issue_closed: could not read origin remote"
        return 1
    }

    # Normalize origin URL to owner/repo (handles both https and ssh)
    local origin_slug
    origin_slug=$(echo "$origin_url" | sed -n \
        -e 's|https://github.com/\([^/]*/[^/]*\).*|\1|p' \
        -e 's|git@github.com:\([^/]*/[^.]*\).*|\1|p')

    if [[ "$origin_slug" != "$owner/$repo" ]]; then
        log_warn "check_issue_closed: issue URL owner/repo ($owner/$repo) does not match origin ($origin_slug)"
        return 1
    fi

    # Query issue state
    local state
    state=$(gh issue view "$number" --repo "$owner/$repo" --json state --jq '.state' 2>/dev/null) || {
        log_warn "check_issue_closed: gh issue view failed for $owner/$repo#$number"
        return 1
    }

    [[ "$state" == "CLOSED" ]]
}

# ── Inline utility: strip_implementation_issues ──────────────────────────────
# Idempotently removes the ## Implementation Issues section from a DESIGN doc.
# No-op if the section is absent. Writes result back to the same file.
# Usage: strip_implementation_issues <doc-path>

strip_implementation_issues() {
    local doc="$1"

    # Check section exists before modifying
    if ! grep -q '^## Implementation Issues' "$doc"; then
        return 0
    fi

    # Strip from ## Implementation Issues heading to (but not including) the next
    # ## heading, or end of file if none follows.
    local tmp
    tmp=$(mktemp)
    awk '
        /^## Implementation Issues$/ { skip=1; next }
        skip && /^## / { skip=0 }
        !skip { print }
    ' "$doc" > "$tmp"
    mv "$tmp" "$doc"
}

# ── JSON helpers ──────────────────────────────────────────────────────────────

# Append a step to STEPS_JSON
add_step() {
    local action="$1"
    local target="$2"
    local found_in="$3"   # pass "null" for no found_in
    local status="$4"
    local detail="$5"     # pass "" for no detail

    local found_in_json detail_json
    if [[ "$found_in" == "null" ]]; then
        found_in_json="null"
    else
        found_in_json=$(jq -n --arg v "$found_in" '$v')
    fi

    if [[ -z "$detail" ]]; then
        detail_json="null"
    else
        detail_json=$(jq -n --arg v "$detail" '$v')
    fi

    local step
    step=$(jq -n \
        --arg action "$action" \
        --arg target "$target" \
        --argjson found_in "$found_in_json" \
        --arg status "$status" \
        --argjson detail "$detail_json" \
        '{action: $action, target: $target, found_in: $found_in, status: $status, detail: $detail}')

    if [[ -z "$STEPS_JSON" ]]; then
        STEPS_JSON="$step"
    else
        STEPS_JSON="$STEPS_JSON,$step"
    fi
}

emit_result() {
    local cascade_status="$1"
    local steps_array="[$STEPS_JSON]"
    jq -n --arg cs "$cascade_status" --argjson steps "$steps_array" \
        '{cascade_status: $cs, steps: $steps}'
}

# ── Handler: handle_design ────────────────────────────────────────────────────
# Strip Implementation Issues, then transition design to Current.
# Usage: handle_design <design-path> <found-in>

handle_design() {
    local path="$1"
    local found_in="$2"

    log_info "Transitioning DESIGN: $path → Current"
    HANDLE_DESIGN_NEW_PATH="$path"  # default: unchanged path

    # Strip Implementation Issues section
    strip_implementation_issues "$path"

    # Transition to Current
    local script
    script=$(dirname "$(dirname "$0")")/../../skills/design/scripts/transition-status.sh
    # Resolve relative to repo root if needed
    if [[ ! -f "$script" ]]; then
        script="$REPO_ROOT/skills/design/scripts/transition-status.sh"
    fi

    local result
    if ! result=$(bash "$script" "$path" Current 2>&1); then
        local errmsg
        errmsg=$(echo "$result" | head -1)
        ANY_FAILED=true
        add_step "transition_design" "$path" "$found_in" "failed" \
            "attempted to transition $path to Current (referenced in $found_in), but transition-status.sh exited with: $errmsg"
        return 1
    fi

    # Extract new path from transition result (design may have moved)
    local new_path
    new_path=$(echo "$result" | jq -r '.new_path // empty' 2>/dev/null) || new_path="$path"
    if [[ -z "$new_path" ]]; then
        new_path="$path"
    fi

    git add "$new_path" 2>/dev/null || git add "$path" 2>/dev/null || true
    STAGED_FILES+=("$new_path")
    add_step "transition_design" "$path" "$found_in" "ok" ""

    # Set global return value so caller can continue chain from new path without a subshell
    HANDLE_DESIGN_NEW_PATH="$new_path"
}

# ── Handler: handle_prd ───────────────────────────────────────────────────────
# Transition PRD to Done.
# Usage: handle_prd <prd-path> <found-in>

handle_prd() {
    local path="$1"
    local found_in="$2"

    log_info "Transitioning PRD: $path → Done"

    local script="$REPO_ROOT/skills/prd/scripts/transition-status.sh"
    local result
    if ! result=$(bash "$script" "$path" Done 2>&1); then
        local errmsg
        errmsg=$(echo "$result" | head -1)
        ANY_FAILED=true
        add_step "transition_prd" "$path" "$found_in" "failed" \
            "attempted to transition $path to Done (referenced in $found_in), but transition-status.sh exited with: $errmsg"
        return 1
    fi

    git add "$path"
    STAGED_FILES+=("$path")
    add_step "transition_prd" "$path" "$found_in" "ok" ""
}

# ── Handler: handle_roadmap ───────────────────────────────────────────────────
# Locate the feature entry referencing plan-slug, update Status and Downstream,
# guard full ROADMAP → Done transition.
# Usage: handle_roadmap <roadmap-path> <found-in> <plan-slug>

handle_roadmap() {
    local path="$1"
    local found_in="$2"
    local plan_slug="$3"

    log_info "Updating ROADMAP feature for plan slug: $plan_slug"

    # Find the line number of the Downstream: field referencing the plan slug
    local downstream_line
    downstream_line=$(grep -n -F "$plan_slug" "$path" | grep -i "Downstream:" | head -1 | cut -d: -f1) || true

    if [[ -z "$downstream_line" ]]; then
        ANY_FAILED=true
        add_step "update_roadmap_feature" "$path" "$found_in" "skipped" \
            "searched $path for a feature whose Downstream: field references plan slug '$plan_slug' (from $found_in), but no matching feature entry was found — ROADMAP feature status was not updated"
        return 0
    fi

    # Walk up from downstream_line to find the enclosing ### Feature N: heading
    local feature_line
    feature_line=$(head -n "$downstream_line" "$path" | grep -n "^### Feature" | tail -1 | cut -d: -f1) || true

    if [[ -z "$feature_line" ]]; then
        ANY_FAILED=true
        add_step "update_roadmap_feature" "$path" "$found_in" "skipped" \
            "searched $path for a feature whose Downstream: field references plan slug '$plan_slug' (from $found_in), but no matching feature entry was found — ROADMAP feature status was not updated"
        return 0
    fi

    # Update the feature's **Status:** to Done using awk with ENVIRON
    # Find the **Status:** line within the feature entry (between feature_line and next ###)
    export CASCADE_PLAN_SLUG="$plan_slug"
    local tmp
    tmp=$(mktemp)

    # Update **Status:** field for this specific feature entry
    awk -v fline="$feature_line" '
        NR == fline { in_feature = 1 }
        in_feature && /^\*\*Status:\*\*/ {
            sub(/\*\*Status:\*\*.*/, "**Status:** Done")
            in_feature = 0
        }
        in_feature && NR > fline && /^###/ { in_feature = 0 }
        { print }
    ' "$path" > "$tmp" && mv "$tmp" "$path"

    # Update **Downstream:** to include "Done" marker
    local design_path
    design_path=$(get_frontmatter_field "upstream" "$found_in") || true

    # Get design basename for downstream reference
    local design_ref=""
    if [[ -n "$design_path" ]]; then
        design_ref=$(basename "$design_path")
    fi

    add_step "update_roadmap_feature" "$path" "$found_in" "ok" ""

    # Check if all features are Done → guard ROADMAP → Done transition
    local all_done=true
    local feature_statuses
    feature_statuses=$(grep "^\*\*Status:\*\*" "$path" | sed 's/\*\*Status:\*\*[[:space:]]*//')
    while IFS= read -r line; do
        if [[ "$line" != "Done" ]]; then
            all_done=false
            break
        fi
    done <<< "$feature_statuses"

    if [[ "$all_done" == "true" ]]; then
        log_info "All ROADMAP features Done. Checking open issues before transitioning ROADMAP."

        # Find any open issue URLs in the feature entry
        local open_issues=false
        local issue_urls
        issue_urls=$(sed -n "${feature_line},/^###/p" "$path" | grep -oE 'https://github\.com/[^/]+/[^/]+/issues/[0-9]+' || true)
        while IFS= read -r issue_url; do
            [[ -z "$issue_url" ]] && continue
            if ! check_issue_closed "$issue_url"; then
                open_issues=true
                local feature_name
                feature_name=$(sed -n "${feature_line}p" "$path" | sed 's/^### //')
                add_step "transition_roadmap" "$path" "$found_in" "skipped" \
                    "feature '$feature_name' in $path references issue $issue_url which is still open — not transitioning $path to Done; close the issue first or run the cascade again after it closes"
                break
            fi
        done <<< "$issue_urls"

        if [[ "$open_issues" == "false" ]]; then
            local script="$REPO_ROOT/skills/roadmap/scripts/transition-status.sh"
            local result
            if ! result=$(bash "$script" "$path" Done 2>&1); then
                local errmsg
                errmsg=$(echo "$result" | head -1)
                ANY_FAILED=true
                add_step "transition_roadmap" "$path" "$found_in" "failed" \
                    "attempted to transition $path to Done (referenced in $found_in), but transition-status.sh exited with: $errmsg"
            else
                add_step "transition_roadmap" "$path" "$found_in" "ok" ""
            fi
        fi
    fi

    git add "$path"
    STAGED_FILES+=("$path")
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat >&2 <<'EOF'
Usage: run-cascade.sh [--push] <plan-doc-path>

Walks the upstream frontmatter chain from a completed PLAN doc and applies
the appropriate lifecycle transition at each node.

Options:
  --push    Commit and push all staged changes. Without this flag,
            changes are staged but not committed (dry-run-safe).

Output: JSON to stdout describing each step and the overall cascade_status.

Exit codes:
  0 — cascade ran (completed, partial, or skipped)
  1 — PLAN doc not found or path validation failed at the PLAN level
EOF
    exit 1
}

# ── Argument parsing ──────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    usage
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --push)
            PUSH=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            PLAN_DOC="$1"
            shift
            ;;
    esac
done

if [[ -z "$PLAN_DOC" ]]; then
    echo "Error: plan-doc-path is required" >&2
    usage
fi

# ── Setup ─────────────────────────────────────────────────────────────────────

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo '{"cascade_status":"skipped","steps":[],"error":"not a git repository"}' >&2
    exit 1
}

# Validate PLAN doc
if [[ ! -f "$PLAN_DOC" ]]; then
    echo "{\"cascade_status\":\"skipped\",\"steps\":[],\"error\":\"PLAN doc not found: $PLAN_DOC\"}" >&2
    exit 1
fi

if ! validate_upstream_path "$PLAN_DOC"; then
    echo "{\"cascade_status\":\"skipped\",\"steps\":[],\"error\":\"PLAN doc failed path validation: $PLAN_DOC\"}" >&2
    exit 1
fi

# ── Read PLAN metadata before deletion ────────────────────────────────────────

# Derive plan slug from PLAN doc filename for ROADMAP feature lookup
PLAN_SLUG=$(basename "$PLAN_DOC" .md | sed 's/^PLAN-//')

# Read upstream chain before deleting the file
UPSTREAM=$(get_frontmatter_field "upstream" "$PLAN_DOC") || true

# ── Step 1: Delete PLAN doc ────────────────────────────────────────────────────

log_info "Deleting PLAN doc: $PLAN_DOC"
if git rm "$PLAN_DOC" > /dev/null 2>&1; then
    add_step "delete_plan" "$PLAN_DOC" "null" "ok" ""
else
    ANY_FAILED=true
    add_step "delete_plan" "$PLAN_DOC" "null" "failed" \
        "attempted to git rm $PLAN_DOC but the operation failed"
fi

# ── Step 2: Walk upstream chain ────────────────────────────────────────────────

if [[ -z "$UPSTREAM" ]]; then
    log_info "No upstream field in PLAN doc — cascade complete (skipped)"
    emit_result "skipped"
    exit 0
fi

current_doc="$PLAN_DOC"
current_upstream="$UPSTREAM"

while [[ -n "$current_upstream" ]]; do
    next_path="$current_upstream"
    found_in="$current_doc"

    # Validate the upstream path before acting
    if ! validate_upstream_path "$next_path"; then
        ANY_FAILED=true
        node_name=$(basename "$next_path")
        # Determine artifact type for error message
        case "$node_name" in
            DESIGN-*) artifact_type="DESIGN" ; target_status="Current" ;;
            PRD-*)    artifact_type="PRD"    ; target_status="Done" ;;
            ROADMAP-*)artifact_type="ROADMAP"; target_status="Done" ;;
            *)        artifact_type="artifact"; target_status="target status" ;;
        esac

        if [[ ! -f "$next_path" ]]; then
            detail="upstream field in $found_in references $next_path, but that file does not exist — cannot transition $artifact_type to $target_status"
        elif [[ -L "$next_path" ]] || [[ ! -f "$next_path" ]]; then
            detail="upstream field in $found_in references $next_path, which resolves outside the repository root — refusing to operate on files outside the working tree"
        else
            detail="upstream field in $found_in references $next_path, but that file is not tracked by git — it may be a new uncommitted file or a typo in the upstream field"
        fi

        case "$node_name" in
            DESIGN-*) add_step "transition_design"  "$next_path" "$found_in" "failed" "$detail" ;;
            PRD-*)    add_step "transition_prd"      "$next_path" "$found_in" "failed" "$detail" ;;
            ROADMAP-*)add_step "update_roadmap_feature" "$next_path" "$found_in" "failed" "$detail" ;;
            *)        add_step "transition_design"   "$next_path" "$found_in" "failed" "$detail" ;;
        esac
        break
    fi

    # Dispatch by filename prefix
    node_basename=$(basename "$next_path")
    case "$node_basename" in
        DESIGN-*)
            handle_design "$next_path" "$found_in" || true
            # Continue chain from the (possibly moved) design doc
            if [[ -n "$HANDLE_DESIGN_NEW_PATH" ]] && [[ -f "$HANDLE_DESIGN_NEW_PATH" ]]; then
                current_doc="$HANDLE_DESIGN_NEW_PATH"
            else
                current_doc="$next_path"
            fi
            ;;
        PRD-*)
            handle_prd "$next_path" "$found_in" || true
            current_doc="$next_path"
            ;;
        ROADMAP-*)
            handle_roadmap "$next_path" "$found_in" "$PLAN_SLUG" || true
            # ROADMAP is terminal — stop chain walk
            break
            ;;
        VISION-*)
            log_info "VISION node encountered — stopping chain walk (no action)"
            break
            ;;
        *)
            ANY_FAILED=true
            add_step "transition_design" "$next_path" "$found_in" "failed" \
                "upstream field in $found_in references $next_path, which has an unrecognized filename prefix — expected DESIGN-*, PRD-*, ROADMAP-*, or VISION-*; stopping chain walk here"
            break
            ;;
    esac

    # Get upstream of current node for next iteration
    current_upstream=$(get_frontmatter_field "upstream" "$current_doc") || true
done

# ── Step 3: Commit and push (if --push) ───────────────────────────────────────

if [[ "$PUSH" == "true" ]] && [[ ${#STAGED_FILES[@]} -gt 0 ]]; then
    log_info "Committing and pushing staged changes"
    git commit -m "chore(cascade): post-implementation artifact transitions"
    git push
elif [[ "$PUSH" == "false" ]] && [[ ${#STAGED_FILES[@]} -gt 0 ]]; then
    log_info "Staged (dry run — pass --push to commit):"
    for f in "${STAGED_FILES[@]}"; do
        log_info "  $f"
    done
fi

# ── Emit result ────────────────────────────────────────────────────────────────

if [[ "$ANY_FAILED" == "true" ]]; then
    emit_result "partial"
else
    emit_result "completed"
fi
