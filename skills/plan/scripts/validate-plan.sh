#!/usr/bin/env bash
#
# validate-plan.sh - Pre-flight validation for PLAN.md documents
#
# Checks frontmatter fields and optional upstream chain before plan-to-tasks.sh
# or the cascade consume the document.
#
# Usage:
#   validate-plan.sh <PLAN.md-path>
#
# Exit codes:
#   0 - valid PLAN doc (upstream check passes or upstream is absent)
#   1 - malformed input (file not found, not readable)
#   2 - frontmatter validation failure (missing or wrong required fields)
#   3 - upstream validation failure (file missing, not tracked, or wrong status)

set -euo pipefail

# Portable realpath: resolve to absolute path (file need not exist).
# macOS ships without standalone realpath; python3 is available on both platforms.
_realpath() { python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$1"; }

usage() {
    cat >&2 <<'EOF'
Usage: validate-plan.sh <PLAN.md-path>

Validates a PLAN.md document's frontmatter and optional upstream chain.

Exit codes:
  0 - valid
  1 - malformed input (file not found, not readable)
  2 - frontmatter validation failure
  3 - upstream validation failure
EOF
    exit 1
}

log_error() {
    echo "validate-plan: error: $*" >&2
}

log_ok() {
    echo "validate-plan: ok: $*" >&2
}

# Extract the YAML frontmatter block (between the first two --- markers)
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

# Get a single field value from frontmatter text on stdin.
# Strips surrounding quotes and trims trailing whitespace.
get_field() {
    local field="$1"
    awk -v field="$field" '
        $0 ~ "^" field ":" {
            sub("^" field ":[ \t]*", "")
            gsub(/^["'"'"']|["'"'"']$/, "")  # strip surrounding quotes
            sub(/[ \t]+$/, "")               # strip trailing whitespace
            print
            exit
        }
    '
}

# Emit one `upstream:` entry per line, handling every written shape the
# document format supports. Reading only the text after `upstream:` -- which is
# what get_field does -- returns EMPTY for a sequence, and the caller then
# skipped the whole upstream check without saying so. A PLAN that names both a
# DESIGN and a ROADMAP is a sequence, so that silent skip would disable the one
# continuous gate that validates a plan's upstream at all.
#
# Supported shapes:
#   upstream: docs/designs/DESIGN-x.md          (scalar)
#   upstream: [docs/a.md, docs/b.md]            (inline sequence)
#   upstream:                                    (block sequence)
#     - docs/a.md
#     - docs/b.md
get_upstream_entries() {
    awk '
        /^upstream:[ \t]*$/       { block = 1; next }
        /^upstream:[ \t]*\[/ {
            line = $0
            sub(/^upstream:[ \t]*\[/, "", line)
            sub(/\][ \t]*$/, "", line)
            n = split(line, items, ",")
            for (i = 1; i <= n; i++) {
                gsub(/^[ \t]+|[ \t]+$/, "", items[i])
                gsub(/^["'"'"']|["'"'"']$/, "", items[i])
                if (items[i] != "") print items[i]
            }
            exit
        }
        /^upstream:/ {
            line = $0
            sub(/^upstream:[ \t]*/, "", line)
            gsub(/^["'"'"']|["'"'"']$/, "", line)
            sub(/[ \t]+$/, "", line)
            if (line != "") print line
            exit
        }
        block && /^[ \t]*-[ \t]*/ {
            line = $0
            sub(/^[ \t]*-[ \t]*/, "", line)
            gsub(/^["'"'"']|["'"'"']$/, "", line)
            sub(/[ \t]+$/, "", line)
            if (line != "") print line
            next
        }
        block && /^[^ \t-]/ { exit }
    '
}

# ── Argument parsing ──

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

PLAN_PATH="$1"

if [[ $# -gt 1 ]]; then
    log_error "too many arguments"
    usage
fi

# ── File validation ──

if [[ ! -e "$PLAN_PATH" ]]; then
    log_error "file not found: $PLAN_PATH"
    exit 1
fi

if [[ ! -r "$PLAN_PATH" ]]; then
    log_error "file is not readable: $PLAN_PATH"
    exit 1
fi

# ── Frontmatter presence ──

first_line=$(head -1 "$PLAN_PATH")
if [[ "$first_line" != "---" ]]; then
    log_error "PLAN file does not start with YAML frontmatter (expected '---' on line 1): $PLAN_PATH"
    exit 2
fi

frontmatter=$(extract_frontmatter "$PLAN_PATH")

# ── Required field: schema ──

schema_val=$(echo "$frontmatter" | get_field "schema")
if [[ "$schema_val" != "plan/v1" ]]; then
    log_error "frontmatter 'schema' must be 'plan/v1', got: '${schema_val}' — ${PLAN_PATH}"
    exit 2
fi

# ── Required field: execution_mode ──

execution_mode=$(echo "$frontmatter" | get_field "execution_mode")
if [[ -z "$execution_mode" ]]; then
    log_error "frontmatter missing required field 'execution_mode' — ${PLAN_PATH}"
    exit 2
fi

# ── Required field: issue_count ──

issue_count=$(echo "$frontmatter" | get_field "issue_count")
if [[ -z "$issue_count" ]]; then
    log_error "frontmatter missing required field 'issue_count' — ${PLAN_PATH}"
    exit 2
fi

# ── Optional field: upstream ──
#
# Every entry is validated, not just the first, and a sequence is enumerated
# rather than skipped. A PLAN may name a DESIGN and the ROADMAP whose feature
# it implements; the ROADMAP entry is the strategic-to-tactical crossing, which
# lives on the PLAN because the PLAN is deleted by the same cascade and goes
# first, so the link cannot dangle.

# Read the entries with a loop rather than `mapfile`: mapfile is a bash 4
# builtin and this script runs under the bash each platform ships, which on
# macOS is 3.2 (see check-plan-scripts.yml, whose macOS leg invokes /bin/bash
# explicitly). `upstream_entries=()` is declared before the loop because bash
# 3.2 leaves an array assigned empty in that form *unset*, which `set -u` then
# trips on at the length test below.
upstream_entries=()
while IFS= read -r upstream_entry; do
    [[ -n "$upstream_entry" ]] || continue
    upstream_entries+=("$upstream_entry")
done < <(echo "$frontmatter" | get_upstream_entries)

if [[ ${#upstream_entries[@]} -eq 0 ]]; then
    log_ok "no upstream field — skipping upstream validation"
    log_ok "${PLAN_PATH} is valid"
    exit 0
fi

# Resolve repo root relative to the PLAN file's location
repo_root=$(git -C "$(dirname "$(_realpath "$PLAN_PATH")")" rev-parse --show-toplevel 2>/dev/null) || {
    log_error "could not determine git repo root from ${PLAN_PATH} — is this file in a git repository?"
    exit 3
}

for upstream_val in "${upstream_entries[@]}"; do
    # An unfilled template placeholder names nothing to resolve.
    if [[ "$upstream_val" == *"<"* || "$upstream_val" == *">"* ]]; then
        log_ok "upstream '${upstream_val}' is an unfilled placeholder — skipping"
        continue
    fi

    # A cross-repo `owner/repo:path` value names a file in another repository:
    # there is no local path to resolve and no local status to read.
    selector="${upstream_val%%:*}"
    if [[ "$upstream_val" == *:* && "$selector" == */* && "$selector" != *" "* ]]; then
        log_ok "upstream '${upstream_val}' is a cross-repo reference — skipping local checks"
        continue
    fi

    upstream_abs="${repo_root}/${upstream_val}"

    # ── Upstream: file existence ──

    if [[ ! -f "$upstream_abs" ]]; then
        log_error "upstream file does not exist: '${upstream_val}' (resolved to ${upstream_abs}) — ${PLAN_PATH}"
        exit 3
    fi

    # ── Upstream: containment and symlink rejection ──
    #
    # The value reaches a committed frontmatter field, so a symlink out of the
    # tree or a `../`-shaped path is rejected here rather than left for the
    # index lookup below to refuse by accident.

    if [[ -L "$upstream_abs" ]]; then
        log_error "upstream '${upstream_val}' is a symlink — ${PLAN_PATH}"
        log_error "  name the target directly; a symlinked upstream resolves differently for different readers"
        exit 3
    fi

    upstream_real=$(_realpath "$upstream_abs")
    repo_root_real=$(_realpath "$repo_root")
    if [[ "$upstream_real" != "$repo_root_real"/* ]]; then
        log_error "upstream '${upstream_val}' resolves outside the repository: ${upstream_real} — ${PLAN_PATH}"
        exit 3
    fi

    # ── Upstream: git tracking ──
    #
    # `--` terminates option parsing so a value beginning with a dash is a
    # pathspec rather than an option. Validation is not the guarantee; the
    # argument boundary is.

    if ! git -C "$repo_root" ls-files --error-unmatch -- "$upstream_val" &>/dev/null; then
        log_error "upstream file exists but is not tracked by git: '${upstream_val}' — ${PLAN_PATH}"
        log_error "  run 'git add -- ${upstream_val}' or check the path"
        exit 3
    fi

    # ── Upstream: status field ──

    upstream_frontmatter=$(extract_frontmatter "$upstream_abs")
    upstream_status=$(echo "$upstream_frontmatter" | get_field "status")

    upstream_base="${upstream_val##*/}"
    if [[ "$upstream_base" == ROADMAP-* ]]; then
        # A ROADMAP entry is the strategic-to-tactical crossing. It is Active
        # for as long as any of its features is still being built, which is
        # exactly the window in which a PLAN naming it exists.
        if [[ "$upstream_status" != "Active" ]]; then
            log_error "upstream roadmap '${upstream_val}' has status '${upstream_status}' — expected 'Active' — ${PLAN_PATH}"
            log_error "  a ROADMAP is Active while its features are being built; a PLAN should not name a Draft or Done one"
            exit 3
        fi
    else
        # Accept both Accepted and Planned: /plan transitions the upstream design
        # from Accepted → Planned when creating the PLAN doc, so both are valid
        # states on PRs.
        if [[ "$upstream_status" != "Accepted" && "$upstream_status" != "Planned" ]]; then
            log_error "upstream file '${upstream_val}' has status '${upstream_status}' — expected 'Accepted' or 'Planned' — ${PLAN_PATH}"
            log_error "  the upstream document must be Accepted (before planning) or Planned (after planning starts)"
            exit 3
        fi
    fi

    log_ok "upstream '${upstream_val}' is ${upstream_status}"
done

log_ok "${PLAN_PATH} is valid"
exit 0
