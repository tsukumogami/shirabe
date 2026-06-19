#!/usr/bin/env bash
# run-cascade.sh — Post-implementation artifact lifecycle cascade
# Part of the work-on skill
#
# Walks the upstream frontmatter chain from a completed PLAN doc and brings each
# node to its terminal lifecycle state. The tactical chain walk and per-node
# transition decision are owned by the `shirabe finalize-chain` subcommand; this
# script orchestrates git (rm/add/commit/push), runs the ROADMAP handler on any
# roadmap node finalize-chain hands off, and translates finalize-chain's typed
# report into the cascade's preserved external contract.
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
#                    transition_brief | update_roadmap_feature |
#                    delete_roadmap",
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
#   1 — PLAN doc not found, path validation failed, not a git repo, or the
#       shirabe binary could not be resolved (setup/precondition failures only)

set -euo pipefail

# Portable substitute for GNU realpath -m: normalize path without requiring existence.
# macOS ships coreutils without realpath; python3 is available on both platforms.
_realpath_m() { python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$1"; }

# ── Global state ──────────────────────────────────────────────────────────────

PUSH=false
PLAN_DOC=""
REPO_ROOT=""

# Outline-AC completeness suppression. When WORK_ON_ALLOW_UNTRACKED_ACS=1 is
# set in the environment, the validator's --allow-untracked-acs flag is added
# to every lifecycle invocation in this script; L01-L05 stay active, only
# L06 is suppressed. The flag's use surfaces in the pre/post probe log lines
# and in the add_step l06_suppressed marker so reviewers can grep for it.
ALLOW_UNTRACKED_ACS_ARGS=()
L06_SUPPRESSED_DETAIL=""
if [[ "${WORK_ON_ALLOW_UNTRACKED_ACS:-}" == "1" ]]; then
    ALLOW_UNTRACKED_ACS_ARGS=(--allow-untracked-acs)
    L06_SUPPRESSED_DETAIL="l06_suppressed=1"
fi
# SHIRABE_BIN may be set in the environment (e.g. by the test harness) to point
# at a specific shirabe binary; it is resolved during setup below. It is
# deliberately NOT reset here, so an inherited value survives.
STEPS_JSON=""      # accumulates JSON step objects, comma-separated
ANY_FAILED=false
STAGED_FILES=()    # files staged for commit
CASCADE_DESIGN_PATH=""     # post-transition path to the DESIGN doc (from the report's new_path), used by handle_roadmap for the Downstream rewrite

# ── Logging ───────────────────────────────────────────────────────────────────

log_warn() {
    echo "[cascade] WARNING: $*" >&2
}

log_info() {
    echo "[cascade] $*" >&2
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
    abs_path=$(_realpath_m "$path" 2>/dev/null) || {
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
# Parses a GitHub issue URL, validates the owner/repo charset, and queries the
# issue state. The owner/repo is NOT required to match the origin remote: a
# coordinated multi-repo effort references sibling-repo issues, and the read-only
# `gh issue view --repo <owner>/<repo>` below queries the named repo directly.
# Returns 0 if closed, 1 if open, if the URL cannot be parsed, or if the
# owner/repo fails the charset validation.
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

    # Validate the owner/repo charset before interpolating it into the gh argv.
    # This guards against a crafted URL smuggling shell/path metacharacters into
    # the `--repo` argument. The match is the GitHub-documented owner/repo
    # character set (^[A-Za-z0-9][A-Za-z0-9._-]{0,38}$). Origin-equality is
    # intentionally NOT checked: sibling-repo issue URLs in a coordinated effort
    # are valid targets for a read-only query.
    local ghname_re='^[A-Za-z0-9][A-Za-z0-9._-]{0,38}$'
    if [[ ! "$owner" =~ $ghname_re ]]; then
        log_warn "check_issue_closed: invalid owner component: $owner"
        return 1
    fi
    if [[ ! "$repo" =~ $ghname_re ]]; then
        log_warn "check_issue_closed: invalid repo component: $repo"
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

# ── Inline utility: log_lifecycle_findings ───────────────────────────────────
# Log the validator's findings on an unexpected probe outcome. The probe runs
# in `--format json`, so the combined output is the `shirabe-validate/v1`
# envelope. Parse it with jq and log one readable line per finding —
# `<message> (<file>:<line>)` — so the cascade names which L-code failed
# rather than dumping raw annotation text. The engine already embeds the
# check code in the message (e.g. `[L05] doc path not found ...`), so the
# code is NOT prepended again; this mirrors the human renderer's choice in
# crates/shirabe-validate/src/report.rs.
#
# Degrades gracefully: if the output is not a parseable envelope with at least
# one finding (e.g. an empty capture from a stubbed validator, or stderr noise
# preceding the JSON), fall back to logging the raw combined output verbatim so
# no diagnostic is lost.
#
# Usage: log_lifecycle_findings <combined-output>

log_lifecycle_findings() {
    local output="$1"

    # Count the findings the envelope carries. A non-envelope or empty input
    # yields an empty/0 count via jq's `-e`-less default; guard both.
    local finding_count
    finding_count=$(jq -r '.findings | length' <<< "$output" 2>/dev/null) || finding_count=""

    if [[ -z "$finding_count" || "$finding_count" == "null" || "$finding_count" -eq 0 ]]; then
        # Not a parseable envelope (or no findings): preserve the raw output.
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            log_warn "$line"
        done <<< "$output"
        return 0
    fi

    # Structured per-finding logging: message and file:line. The message
    # already carries the check code, so it is not prepended. A null line
    # renders as the file alone (no `:line` suffix), matching the envelope's
    # null-line sentinel.
    local lines
    lines=$(jq -r '
        .findings[]
        | .message
          + " (" + .file + (if .line == null then "" else ":" + (.line|tostring) end) + ")"
    ' <<< "$output" 2>/dev/null) || lines=""

    if [[ -z "$lines" ]]; then
        # jq parsed a count but the render failed; fall back to raw output.
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            log_warn "$line"
        done <<< "$output"
        return 0
    fi

    while IFS= read -r line; do
        log_warn "$line"
    done <<< "$lines"
}

# ── Inline utility: lifecycle_findings_summary ───────────────────────────────
# Render the probe's findings as a single-line, `; `-joined summary suitable
# for a step's `detail` field (which is one JSON string). Each finding becomes
# `<message> (<file>:<line>)` — the message already carries the check code, so
# it is not prepended. Degrades to the raw combined output, newlines collapsed
# to spaces, when the input is not a parseable envelope with findings.
#
# Usage: lifecycle_findings_summary <combined-output>
# Echoes the summary string to stdout.

lifecycle_findings_summary() {
    local output="$1"

    local finding_count
    finding_count=$(jq -r '.findings | length' <<< "$output" 2>/dev/null) || finding_count=""

    if [[ -n "$finding_count" && "$finding_count" != "null" && "$finding_count" -gt 0 ]]; then
        local summary
        summary=$(jq -r '
            [ .findings[]
              | .message
                + " (" + .file + (if .line == null then "" else ":" + (.line|tostring) end) + ")"
            ] | join("; ")
        ' <<< "$output" 2>/dev/null) || summary=""
        if [[ -n "$summary" ]]; then
            printf '%s' "$summary"
            return 0
        fi
    fi

    # Fallback: the raw output with newlines collapsed to spaces.
    printf '%s' "$output" | tr '\n' ' '
}

# ── Inline utility: lifecycle_probe ──────────────────────────────────────────
# Run the chain-targeted lifecycle check in strict mode against the cascade's
# PLAN doc. Two modes:
#
#   pre:  expects exit code non-zero (chain at single-pr-Active mid-PR;
#         --strict forces a failure naming the present PLAN at Active).
#         Returns 0 if the expected failure was observed; returns 1 (signal:
#         skip cascade entirely) when the validator reports a clean pass —
#         the chain is already at its terminal and the cascade would be a
#         no-op.
#
#   post: expects exit code 0 (cascade has finalized the chain). Returns 0
#         on the expected clean pass; returns 1 on cascade-bug failure.
#         On failure, the validator's findings are logged for diagnosis.
#
# The probe runs the validator in `--format json` and captures its combined
# output so log_lifecycle_findings can surface the structured L-code findings
# on an unexpected outcome. Control flow still follows the exit code only —
# the JSON is consumed for diagnostic logging, never for branching.
#
# Usage: lifecycle_probe <pre|post>
# Side effect: sets LIFECYCLE_PROBE_OUTPUT to the validator's combined output
# (the JSON envelope on stdout; any stderr noise is included too).

LIFECYCLE_PROBE_OUTPUT=""

lifecycle_probe() {
    local mode="$1"
    local exit_code=0
    # bash 3.2 (macOS) errors on `"${arr[@]}"` when arr is empty under
    # `set -u`; the `${arr[@]:+...}` guard expands to nothing when the
    # array is empty and to the spread otherwise. Safe across bash 3.2+
    # and bash 5.x.
    LIFECYCLE_PROBE_OUTPUT=$("$SHIRABE_BIN" validate \
        --lifecycle-chain "$PLAN_DOC" \
        --format json \
        --strict \
        ${ALLOW_UNTRACKED_ACS_ARGS[@]:+"${ALLOW_UNTRACKED_ACS_ARGS[@]}"} 2>&1) || exit_code=$?

    if [[ "$mode" == "pre" ]]; then
        if [[ "$exit_code" -eq 0 ]]; then
            log_info "Pre-cascade probe: chain already at strict-mode passing state — cascade is a no-op"
            return 1
        fi
        log_info "Pre-cascade probe: expected failure observed (chain at single-pr-Active mid-PR)"
        return 0
    elif [[ "$mode" == "post" ]]; then
        if [[ "$exit_code" -ne 0 ]]; then
            log_warn "Post-cascade verification failed (cascade bug):"
            log_lifecycle_findings "$LIFECYCLE_PROBE_OUTPUT"
            return 1
        fi
        log_info "Post-cascade verification: chain at strict-mode passing state"
        return 0
    else
        log_warn "lifecycle_probe called with unknown mode: $mode"
        return 1
    fi
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

# ── Handler: handle_roadmap ───────────────────────────────────────────────────
# Locate the feature entry referencing plan-slug, update Status and Downstream,
# guard full ROADMAP → Done transition. Runs on the roadmap node finalize-chain
# hands off; external-state-dependent (gh) and out of finalize-chain's scope, so
# it stays in bash.
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
        add_step "update_roadmap_feature" "$path" "$found_in" "skipped" \
            "searched $path for a feature whose Downstream: field references plan slug '$plan_slug' (from $found_in), but no matching feature entry was found — ROADMAP feature status was not updated"
        return 0
    fi

    # Walk up from downstream_line to find the enclosing ### Feature N: heading
    local feature_line
    feature_line=$(head -n "$downstream_line" "$path" | grep -n "^### " | tail -1 | cut -d: -f1) || true

    if [[ -z "$feature_line" ]]; then
        add_step "update_roadmap_feature" "$path" "$found_in" "skipped" \
            "searched $path for a feature whose Downstream: field references plan slug '$plan_slug' (from $found_in), but no matching feature entry was found — ROADMAP feature status was not updated"
        return 0
    fi

    # Export variables for all awk substitutions; use ENVIRON["var"] inside awk (not -v)
    export CASCADE_FEATURE_LINE="$feature_line"
    export CASCADE_DOWNSTREAM_LINE="$downstream_line"

    # Update **Status:** for this feature entry using ENVIRON (not -v)
    local tmp
    tmp=$(mktemp)
    awk '
        BEGIN { fline = ENVIRON["CASCADE_FEATURE_LINE"] + 0 }
        NR == fline { in_feature = 1 }
        in_feature && /^\*\*Status:\*\*/ {
            print "**Status:** Done"
            in_feature = 0
            next
        }
        in_feature && NR > fline && /^### / { in_feature = 0 }
        { print }
    ' "$path" > "$tmp" && mv "$tmp" "$path"

    # Update **Downstream:** to reference the DESIGN doc at Current using ENVIRON (not -v)
    local design_ref=""
    if [[ -n "${CASCADE_DESIGN_PATH:-}" ]]; then
        design_ref=$(basename "$CASCADE_DESIGN_PATH")
    fi
    export CASCADE_DESIGN_REF="$design_ref"
    tmp=$(mktemp)
    awk '
        BEGIN { dsline = ENVIRON["CASCADE_DOWNSTREAM_LINE"] + 0 }
        NR == dsline && /^\*\*Downstream:\*\*/ {
            ref = ENVIRON["CASCADE_DESIGN_REF"]
            if (ref != "") {
                print "**Downstream:** " ref " (Current)"
            } else {
                print
            }
            next
        }
        { print }
    ' "$path" > "$tmp" && mv "$tmp" "$path"

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
        log_info "All ROADMAP features Done. Delegating to handle_roadmap_deletion for completion check + delete."
        handle_roadmap_deletion "$path" "$found_in"
    fi

    # Stage the Status/Downstream feature edit. When handle_roadmap_deletion
    # has already removed the file (git rm), this `git add` is a no-op; the
    # staged deletion stays. When the deletion path didn't fire (open issues,
    # not all features Done, or the all_done branch was never reached), this
    # stages the feature Status/Downstream rewrite.
    if [[ -f "$path" ]]; then
        git add "$path" || true
        STAGED_FILES+=("$path")
    fi
}

# ── Handler: handle_roadmap_deletion ──────────────────────────────────────────
# Idempotent check + delete for working-lifecycle ROADMAPs. When the existing
# handle_roadmap() has verified all features are at status Done, this function
# re-verifies the condition, confirms every referenced GitHub issue is CLOSED,
# transitions the ROADMAP Active -> Done, and `git rm`s the file in the same
# staged commit set.
#
# Idempotent at every negative branch:
#   - Missing file returns 0 with no side effects (already deleted).
#   - Any non-Done feature returns 0 with no side effects.
#   - Any open issue records a "delete_roadmap" "skipped" step naming the URL.
#
# On success: records "delete_roadmap" "ok", appends path to STAGED_FILES.
# On git rm failure: sets ANY_FAILED=true and records the step as "failed".
#
# Usage: handle_roadmap_deletion <roadmap-path> <found-in>

handle_roadmap_deletion() {
    local path="$1"
    local found_in="$2"

    # Idempotency guard: missing file is a no-op (already deleted on a prior run).
    if [[ ! -f "$path" ]]; then
        return 0
    fi

    # Re-verify all features are at status Done. The caller in handle_roadmap()
    # already checked, but a direct re-invocation must also be safe.
    local all_done=true
    local feature_statuses
    feature_statuses=$(grep "^\*\*Status:\*\*" "$path" \
        | sed 's/\*\*Status:\*\*[[:space:]]*//')
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" != "Done" ]]; then
            all_done=false
            break
        fi
    done <<< "$feature_statuses"

    if [[ "$all_done" != "true" ]]; then
        # Some feature is not Done; the ROADMAP stays.
        return 0
    fi

    # Confirm all referenced GitHub issues are CLOSED. Reuses check_issue_closed
    # which validates owner/repo against the origin remote.
    local all_closed=true
    local open_issue_url=""
    local issue_urls
    issue_urls=$(grep -oE \
        'https://github\.com/[^/]+/[^/]+/issues/[0-9]+' "$path" || true)
    while IFS= read -r issue_url; do
        [[ -z "$issue_url" ]] && continue
        if ! check_issue_closed "$issue_url"; then
            all_closed=false
            open_issue_url="$issue_url"
            break
        fi
    done <<< "$issue_urls"

    if [[ "$all_closed" != "true" ]]; then
        add_step "delete_roadmap" "$path" "$found_in" "skipped" \
            "$path references issue $open_issue_url which is still open — not deleting $path; close the issue first or run the cascade again after it closes"
        return 0
    fi

    # Active -> Done flip (ephemeral, in-process audit-trail marker).
    if ! "$SHIRABE_BIN" transition "$path" Done > /dev/null 2>&1; then
        log_warn "shirabe transition $path Done failed; proceeding to git rm"
    fi

    # Done -> DELETED via git rm in the same staged commit set.
    if git rm -f "$path" > /dev/null 2>&1; then
        add_step "delete_roadmap" "$path" "$found_in" "ok" ""
        STAGED_FILES+=("$path")
    else
        ANY_FAILED=true
        add_step "delete_roadmap" "$path" "$found_in" "failed" \
            "attempted to git rm $path but the operation failed"
    fi
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
  1 — setup/precondition failure (PLAN missing, path validation, not a git
      repo, or shirabe binary unresolvable)
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

# Resolve the shirabe binary used for status transitions. Precedence:
#   1. $SHIRABE_BIN if set and executable (used by the test harness to inject a stub)
#   2. `shirabe` on PATH (the plugin-installed binary)
#   3. a locally built release/debug binary under the repo's crates target dir
SHIRABE_BIN="${SHIRABE_BIN:-}"
if [[ -z "$SHIRABE_BIN" ]]; then
    if command -v shirabe >/dev/null 2>&1; then
        SHIRABE_BIN="shirabe"
    elif [[ -x "$REPO_ROOT/target/release/shirabe" ]]; then
        SHIRABE_BIN="$REPO_ROOT/target/release/shirabe"
    elif [[ -x "$REPO_ROOT/target/debug/shirabe" ]]; then
        SHIRABE_BIN="$REPO_ROOT/target/debug/shirabe"
    else
        echo '{"cascade_status":"skipped","steps":[],"error":"shirabe binary not found (set SHIRABE_BIN, install shirabe, or build with cargo)"}' >&2
        exit 1
    fi
fi

# Validate PLAN doc
if [[ ! -f "$PLAN_DOC" ]]; then
    echo "{\"cascade_status\":\"skipped\",\"steps\":[],\"error\":\"PLAN doc not found: $PLAN_DOC\"}" >&2
    exit 1
fi

if ! validate_upstream_path "$PLAN_DOC"; then
    echo "{\"cascade_status\":\"skipped\",\"steps\":[],\"error\":\"PLAN doc failed path validation: $PLAN_DOC\"}" >&2
    exit 1
fi

# Surface the L06 suppression once at the start so reviewers grepping the
# cascade's CI log see the marker before any validator output. The literal
# substring matches what reviewer scripts can grep for: the env var name
# is canonical and stable across releases.
if [[ ${#ALLOW_UNTRACKED_ACS_ARGS[@]} -gt 0 ]]; then
    log_info "[L06-suppressed via WORK_ON_ALLOW_UNTRACKED_ACS=1]"
fi

# ── Pre-cascade lifecycle probe ───────────────────────────────────────────────
#
# Run the chain-targeted lifecycle check in strict mode BEFORE any
# transitions are applied. The chain is at single-pr-Active mid-PR; in
# --strict mode the validator surfaces a failure naming the present PLAN
# and its non-terminal BRIEF/PRD upstreams, signaling that the cascade
# must fire. A clean pass at this point means the chain is already at its
# strict-mode terminal — the cascade is a no-op and the script exits 0
# with cascade_status: skipped, no transitions performed.
#
# The post-cascade verification re-runs the same probe after the commit;
# the pre/post pair pins the cascade's behavior end to end without the
# agent having to interpret the validator's output.

if ! lifecycle_probe "pre"; then
    add_step "lifecycle_pre_probe" "$PLAN_DOC" "null" "skipped" \
        "chain at strict-mode passing state — cascade is a no-op${L06_SUPPRESSED_DETAIL:+ ($L06_SUPPRESSED_DETAIL)}"
    emit_result "skipped"
    exit 0
fi
add_step "lifecycle_pre_probe" "$PLAN_DOC" "null" "ok" "$L06_SUPPRESSED_DETAIL"

# ── Read PLAN metadata before deletion ────────────────────────────────────────


# Derive plan slug from PLAN doc filename for ROADMAP feature lookup
PLAN_SLUG=$(basename "$PLAN_DOC" .md | sed 's/^PLAN-//')

# ── Step 1: finalize-chain (before git rm — it must read the PLAN's upstream) ──
#
# finalize-chain walks the PLAN's upstream chain, applies each tactical node's
# terminal transition (DESIGN→Current incl. the git mv into current/ and the
# Implementation-Issues strip; PRD→Done; BRIEF→Done), reports the PLAN as a
# delete node (never deletes it), and stops at a ROADMAP/VISION node, reporting
# the roadmap as a handoff. On a refused transition it exits nonzero (1/2/3) and
# emits a structured error on stderr; we capture both without letting `set -e`
# abort, and translate a node failure into status:failed + cascade_status:partial
# while run-cascade STILL exits 0 (the cascade ran).

log_info "Running finalize-chain on PLAN: $PLAN_DOC"

FINALIZE_OUT=""
FINALIZE_ERR=""
FINALIZE_RC=0
# Capture stdout and stderr separately; do not let a nonzero exit abort the script.
FINALIZE_ERR_FILE=$(mktemp)
FINALIZE_OUT=$("$SHIRABE_BIN" finalize-chain "$PLAN_DOC" 2>"$FINALIZE_ERR_FILE") || FINALIZE_RC=$?
FINALIZE_ERR=$(cat "$FINALIZE_ERR_FILE")
rm -f "$FINALIZE_ERR_FILE"

# PLAN docs use a unified Draft -> Active -> Done -> DELETED lifecycle. The
# Active -> Done flip is an ephemeral marker that bridges to deletion: the
# cascade transitions the PLAN's on-disk frontmatter to Done immediately
# before `git rm` so the audit trail at HEAD shows the Done flip atomically
# with the deletion. finalize-chain owns the tactical chain (DESIGN/PRD/
# BRIEF transitions); the cascade owns the PLAN's Active -> Done -> DELETED
# step. Both modes (single-pr, multi-pr) follow this sequence.
#
# Idempotent: `shirabe transition <plan> Done` is a no-op on a Done doc.
if [[ -f "$PLAN_DOC" ]]; then
    log_info "Transitioning PLAN: $PLAN_DOC Active -> Done (ephemeral, in-process)"
    if ! "$SHIRABE_BIN" transition "$PLAN_DOC" Done >/dev/null 2>&1; then
        # Non-fatal: a PLAN at Draft (auto-transition didn't fire) or other
        # unexpected current status can land here. Log a warning and proceed
        # to the deletion regardless — the deletion is the forcing function,
        # the Done flip is the audit-trail marker.
        log_warn "shirabe transition $PLAN_DOC Done failed (PLAN may already be Done or at an unexpected status); proceeding to git rm"
    fi
fi

# ── Step 2: Translate the finalize-chain report into the cascade contract ─────
#
# On success (rc 0) finalize-chain emits a `{nodes:[...]}` report on stdout. We
# walk those nodes in order. Each node's found_in is the previous node's path
# (its post-move new_path when the previous node was a moved DESIGN); the PLAN's
# found_in is null. We stage every transitioned path (new_path for a moved
# DESIGN) and translate each node into a steps[] entry with the preserved action
# names. A ROADMAP handoff is handed to handle_roadmap (bash).
#
# On a node failure (rc != 0) finalize-chain emits the structured error on
# stderr. Because the report's stdout is then absent, we cannot reconstruct the
# successful prefix of the walk; we record a single failed step carrying the
# engine's node-and-type-aware message and mark the cascade partial. The PLAN was
# never deleted by finalize-chain, so we still git rm it below — the cascade ran.

ROADMAP_PATH=""
ROADMAP_FOUND_IN=""

if [[ "$FINALIZE_RC" -eq 0 ]]; then
    # Parse the report. Walk nodes in order, tracking the previous node's
    # effective path to populate found_in.
    node_count=$(jq -r '.nodes | length' <<< "$FINALIZE_OUT")
    prev_path="null"   # PLAN's found_in is null
    i=0
    while [[ "$i" -lt "$node_count" ]]; do
        action=$(jq -r ".nodes[$i].action" <<< "$FINALIZE_OUT")
        target=$(jq -r ".nodes[$i].path" <<< "$FINALIZE_OUT")
        new_path=$(jq -r ".nodes[$i].new_path // empty" <<< "$FINALIZE_OUT")
        note=$(jq -r ".nodes[$i].note // empty" <<< "$FINALIZE_OUT")

        # The effective on-disk path after this node (post-move for a DESIGN).
        effective_path="$target"
        if [[ -n "$new_path" ]]; then
            effective_path="$new_path"
        fi

        case "$action" in
            delete_plan)
                # Reported, not emitted as a step yet — the git rm below emits it.
                ;;
            transition_design)
                git add "$new_path" 2>/dev/null || git add "$target" 2>/dev/null || true
                STAGED_FILES+=("$effective_path")
                CASCADE_DESIGN_PATH="$effective_path"
                add_step "transition_design" "$target" "$prev_path" "ok" ""
                ;;
            transition_prd)
                git add "$target" 2>/dev/null || true
                STAGED_FILES+=("$target")
                add_step "transition_prd" "$target" "$prev_path" "ok" ""
                ;;
            transition_brief)
                git add "$target" 2>/dev/null || true
                STAGED_FILES+=("$target")
                add_step "transition_brief" "$target" "$prev_path" "ok" ""
                ;;
            roadmap_handoff)
                # Defer the roadmap handler until after the design path is known
                # (it is — the design precedes the roadmap in the chain). Run it
                # now: CASCADE_DESIGN_PATH is set from any earlier design node.
                ROADMAP_PATH="$target"
                ROADMAP_FOUND_IN="$prev_path"
                ;;
            stop)
                # VISION node or cross-repo reference: no action, walk stopped.
                log_info "finalize-chain stopped: ${note:-no further action}"
                ;;
            error)
                # Unrecognized prefix mid-walk: finalize-chain reported it as a
                # per-node error entry but still exited 0. Surface it as a failed
                # step and mark the cascade partial.
                ANY_FAILED=true
                add_step "transition_design" "$target" "$prev_path" "failed" \
                    "${note:-finalize-chain reported an unrecognized node and stopped the chain walk}"
                ;;
            *)
                ANY_FAILED=true
                add_step "transition_design" "$target" "$prev_path" "failed" \
                    "finalize-chain reported an unknown action '$action' for $target"
                ;;
        esac

        prev_path="$effective_path"
        i=$((i + 1))
    done

    # Run the ROADMAP handler (bash) on any handed-off roadmap node, using the
    # report's DESIGN new_path (CASCADE_DESIGN_PATH) for the Downstream rewrite.
    if [[ -n "$ROADMAP_PATH" ]]; then
        handle_roadmap "$ROADMAP_PATH" "$ROADMAP_FOUND_IN" "$PLAN_SLUG" || true
    fi
else
    # finalize-chain refused a node (exit 1/2/3). Its structured error is on
    # stderr as {success,error,code}; extract the node-and-type-aware message.
    ANY_FAILED=true
    errmsg=$(echo "$FINALIZE_ERR" | jq -r '.error // empty' 2>/dev/null) || errmsg=""
    if [[ -z "$errmsg" ]]; then
        errmsg=$(echo "$FINALIZE_ERR" | head -1)
    fi
    add_step "transition_design" "$PLAN_DOC" "null" "failed" \
        "finalize-chain exited $FINALIZE_RC while walking the upstream chain of $PLAN_DOC: ${errmsg:-no error detail}"
fi

# ── Step 3: git rm the PLAN (per the report's delete entry) ────────────────────
#
# finalize-chain never deletes the PLAN; the script owns the git rm. This runs
# after finalize-chain so the subcommand could read the PLAN's upstream first.
# The PLAN's Active -> Done frontmatter flip (Step 1's transition call above)
# was applied just before this delete so the resulting commit carries the
# ephemeral Done marker atomically with the file removal.

log_info "Deleting PLAN doc: $PLAN_DOC"
# `git rm -f` so the deletion succeeds even when the PLAN's
# frontmatter was just edited (the Active -> Done step above leaves
# the file modified-in-worktree until this delete lands). The
# Active -> Done frontmatter change is ephemeral by design: it
# exists only in the commit that also deletes the file.
if git rm -f "$PLAN_DOC" > /dev/null 2>&1; then
    add_step "delete_plan" "$PLAN_DOC" "null" "ok" ""
else
    ANY_FAILED=true
    add_step "delete_plan" "$PLAN_DOC" "null" "failed" \
        "attempted to git rm $PLAN_DOC but the operation failed"
fi

# ── Step 4: Commit and push (if --push) ───────────────────────────────────────

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

# ── Post-cascade lifecycle verification ───────────────────────────────────────
#
# Run the chain-targeted check in strict mode AFTER the commit. We expect
# a clean pass — the cascade should have pulled the chain to its
# at-merge passing state (PLAN deleted, BRIEF/PRD Done, DESIGN Current).
# Failure here is a cascade bug; the validator's structured findings are
# logged (lifecycle_probe) and summarized into the step's detail field.
#
# In dry-run mode (PUSH=false), the transitions are staged but not
# committed, so the chain has not actually finalized — skip the
# verification.

if [[ "$PUSH" == "true" ]] && [[ ${#STAGED_FILES[@]} -gt 0 ]]; then
    if ! lifecycle_probe "post"; then
        ANY_FAILED=true
        add_step "lifecycle_post_verify" "$PLAN_DOC" "null" "failed" \
            "post-cascade lifecycle check failed in strict mode (cascade bug): $(lifecycle_findings_summary "$LIFECYCLE_PROBE_OUTPUT")${L06_SUPPRESSED_DETAIL:+ ($L06_SUPPRESSED_DETAIL)}"
    else
        add_step "lifecycle_post_verify" "$PLAN_DOC" "null" "ok" "$L06_SUPPRESSED_DETAIL"
    fi
fi

# ── Emit result ────────────────────────────────────────────────────────────────
#
# cascade_status:
#   skipped   — the PLAN had no upstream chain (only the delete step ran)
#   partial   — a node failed (finalize-chain refused, an error node, or git rm
#               failed); the cascade still RAN, so the script exits 0
#   completed — every node transitioned cleanly
# The script exits 0 whenever the cascade ran; exit 1 is reserved for the
# setup/precondition failures handled above (before this point).

# A "skipped" cascade is one where finalize-chain reported only the PLAN delete
# node (no upstream chain). Detect it from the successful report.
CASCADE_SKIPPED=false
if [[ "$FINALIZE_RC" -eq 0 ]]; then
    fc_node_count=$(jq -r '.nodes | length' <<< "$FINALIZE_OUT")
    if [[ "$fc_node_count" -eq 1 ]]; then
        CASCADE_SKIPPED=true
    fi
fi

if [[ "$ANY_FAILED" == "true" ]]; then
    emit_result "partial"
elif [[ "$CASCADE_SKIPPED" == "true" ]]; then
    emit_result "skipped"
else
    emit_result "completed"
fi
