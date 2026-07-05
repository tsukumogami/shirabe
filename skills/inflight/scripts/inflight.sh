#!/usr/bin/env bash
#
# inflight.sh - /inflight skill glue.
#
# Resolves the current session id from the harness env var CLAUDE_CODE_SESSION_ID
# and asks the work-summary component to render this session's tracked PRs. When
# the session ledger is empty or unreachable, it degrades to a REPO-SCOPED gh
# fallback (never an author-scoped cross-repo search, which would over-collect
# private PRs into a public context), formatted to the same block spec.
#
# Fail-safe: always exits 0. Prints nothing when there is nothing to show.
#
# Env seams (shared with work-summary.sh): GH, WS_STORE_DIR, WS_NOW.

set -uo pipefail
trap 'exit 0' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENT="$SCRIPT_DIR/work-summary.sh"

# Reuse the component's format helpers (MARKER, US, JQ_PROG, sanitize,
# validate_sid) so the fallback follows the exact same block spec. Sourcing is
# safe: work-summary.sh only runs main() when executed directly.
# shellcheck source=/dev/null
source "$COMPONENT" 2>/dev/null || exit 0

GH_BIN="${GH:-gh}"

# --- primary path: session-scoped component render -------------------------

sid="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
if [[ -n "$sid" ]] && validate_sid "$sid"; then
    out="$(bash "$COMPONENT" render --session "$sid" 2>/dev/null)"
    if [[ -n "$out" ]]; then
        printf '%s\n' "$out"
        exit 0
    fi
fi

# --- fallback path: repo-scoped gh listing ---------------------------------
# Fail-closed: if we cannot confirm the current repo, emit nothing rather than
# risk surfacing PRs whose repository/visibility we cannot establish.
repo="$("$GH_BIN" repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)" || repo=""
if [[ -z "$repo" ]]; then
    exit 0
fi

list_json="$("$GH_BIN" pr list --repo "$repo" --author '@me' --state open \
    --json number,title,state,url,isDraft,statusCheckRollup,reviewDecision \
    2>/dev/null)" || list_json=""
if [[ -z "$list_json" || "$list_json" == "[]" ]]; then
    exit 0
fi

# Build the block, mirroring render_block's line shape and token logic. Only the
# confirmed current repo is ever listed here; no cross-repo collection happens.
declare -a lines=()
while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    parsed="$(printf '%s' "$item" | jq -r "$JQ_PROG" 2>/dev/null | tr '\t' "$US")" || continue
    IFS="$US" read -r st isd ci rev title <<< "$parsed"
    number="$(printf '%s' "$item" | jq -r '.number // empty' 2>/dev/null)"
    url="$(printf '%s' "$item" | jq -r '.url // empty' 2>/dev/null)"
    [[ -z "$number" || -z "$url" ]] && continue
    # Confirm the URL belongs to the confirmed repo (fail-closed redaction).
    case "$url" in
        "https://github.com/$repo/pull/"*) : ;;
        *) continue ;;
    esac
    st="${st^^}"
    if   [[ "$isd" == "true" ]]; then base="draft"; else base="open"; fi
    tokens="$base"
    [[ -n "$ci" ]] && tokens="$tokens ci:$ci"
    rvu="${rev^^}"
    if   [[ "$rvu" == "CHANGES_REQUESTED" ]]; then tokens="$tokens review:changes_requested"
    elif [[ "$rvu" == "APPROVED" ]];          then tokens="$tokens review:approved"; fi
    stitle="$(sanitize "$title")"
    lines+=("$(printf '%s#%s | %s | %s | %s' "$repo" "$number" "$tokens" "$stitle" "$url")")
done < <(printf '%s' "$list_json" | jq -c '.[]' 2>/dev/null)

if (( ${#lines[@]} == 0 )); then
    exit 0
fi

printf '%s\n' "$MARKER"
printf '%s\n' "${lines[@]}"
if [[ -n "${WS_NOW:-}" ]]; then
    ts="$(date -u -d "@${WS_NOW}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
else
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
printf 'updated %s (repo-scoped fallback: %s)\n' "$ts" "$repo"
exit 0
