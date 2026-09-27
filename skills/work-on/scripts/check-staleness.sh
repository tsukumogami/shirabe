#!/usr/bin/env bash
# check-staleness.sh -- is this issue still current, or has the codebase moved
# on since it was filed?
#
# /work-on's staleness_check gate runs this against the issue it is about to
# implement. It performs four checks, and the issue is stale when any one fires:
#
#   1. Issue age: stale when the issue is more than 14 days old
#      (AGE_THRESHOLD_DAYS below).
#   2. Closed milestone siblings: stale when at least one issue in the same
#      milestone was closed after this issue was created.
#   3. Milestone position: stale when the issue is "last" (some milestone
#      issues closed and exactly one open) or "middle" (some closed, and any
#      other number open, zero included). "first" (none closed) and "unknown"
#      (no milestone, or empty lists) never fire.
#   4. Referenced files: stale when a file the issue body names (a path ending
#      in one of the extensions in FILE_EXTENSIONS, at most 20 of them) has a
#      commit touching it since the issue was created.
#
# The full statement, including how this differs from the check shirabe used
# before it shipped its own, is skills/work-on/references/staleness-signals.md.
#
# Usage: check-staleness.sh --issue <N>
#
# Exit status carries the verdict, because koto hands the gate only
# {exit_code, error} and runs gate commands without pipefail:
#   0  fresh        no check fired
#   1  stale        at least one check fired
#   2  usage        missing, extra, or malformed argument (a bare issue number
#                   included); usage on stderr, nothing on stdout
#   3  unavailable  gh, jq or git missing, a gh call failed, a git read
#                   failed, or a response or the report couldn't be processed;
#                   no verdict is reached from partial data
#
# `--help` prints usage on stderr and exits 0; the gate never passes it.
#
# On 0, 1 and 3 a JSON report goes to stdout: verdict, introspection_recommended,
# the issue, every signal measured, and a reason.
#
# Needs gh (authenticated), jq and git, and runs from the working tree of the
# repository the issue belongs to; gh resolves the repository from it. At most
# three gh calls per run. Written for the bash 3.2 floor, and deliberately
# without `set -e`: an unexpected failure must not exit 1 and read as stale.

set -u

AGE_THRESHOLD_DAYS=14
FILE_EXTENSIONS='go|ts|tsx|js|jsx|md|sh|py|toml|yaml|yml|json'
MAX_FILE_REFS=20
MILESTONE_LIMIT=100

usage() {
    cat >&2 <<'EOF'
Usage: check-staleness.sh --issue <N>

Report whether GitHub issue <N> is fresh (exit 0), stale (exit 1), or could
not be assessed (exit 3). Exit 2 is a usage error.
EOF
}

TMP_DIR=""
cleanup() { [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"; return 0; }
trap cleanup EXIT

# sanitize_error <file> -- the first line of a command's stderr, cut to 200
# characters, or a fixed message when it carries anything token-shaped. The
# reason travels into evidence and from there into PR text.
sanitize_error() {
    local line
    line=$(head -n 1 "$1" 2>/dev/null | cut -c 1-200)
    case "$line" in
        *ghp_*|*gho_*|*ghs_*|*ghu_*|*github_pat_*)
            line="error output withheld: it contained a credential-shaped string" ;;
    esac
    [ -n "$line" ] || line="no error output"
    printf '%s' "$line"
}

# unavailable <reason> -- report that no verdict was reached, and exit 3.
unavailable() {
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg reason "$1" --argjson issue "${ISSUE:-0}" \
            '{verdict: "unavailable", introspection_recommended: null,
              issue: {number: $issue}, signals: null, reason: $reason}'
    else
        # No jq to encode with. Every reason reaching this branch is a fixed
        # string naming a tool, so it needs no escaping.
        printf '{"verdict":"unavailable","introspection_recommended":null,"issue":{"number":%s},"signals":null,"reason":"%s"}\n' \
            "${ISSUE:-0}" "$1"
    fi
    exit 3
}

# --- Arguments ---------------------------------------------------------------

ISSUE=""
if [ $# -eq 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
    usage
    exit 0
fi
if [ $# -ne 2 ] || [ "$1" != "--issue" ]; then
    usage
    exit 2
fi
case "$2" in
    # Digits only, and no leading zero: 0 is no issue, and 07 would reach gh as
    # a string that doesn't match the number the gate substituted.
    ''|*[!0-9]*|0*) usage; exit 2 ;;
esac
ISSUE="$2"

# --- Tools -------------------------------------------------------------------

for tool in jq gh git; do
    command -v "$tool" >/dev/null 2>&1 || unavailable "$tool not found"
done

TMP_DIR=$(mktemp -d 2>/dev/null) || unavailable "could not create a temporary directory"
ERR="$TMP_DIR/err"

# --- The issue (gh call 1) ---------------------------------------------------

if ! ISSUE_JSON=$(gh issue view "$ISSUE" --json number,title,createdAt,body,milestone 2>"$ERR"); then
    unavailable "gh issue view failed: $(sanitize_error "$ERR")"
fi

if ! CREATED_AT=$(printf '%s' "$ISSUE_JSON" | jq -er '.createdAt' 2>"$ERR"); then
    unavailable "issue response has no createdAt: $(sanitize_error "$ERR")"
fi
if ! AGE_DAYS=$(printf '%s' "$ISSUE_JSON" | jq -er '((now - (.createdAt | fromdateiso8601)) / 86400) | floor' 2>"$ERR"); then
    unavailable "could not compute the issue's age: $(sanitize_error "$ERR")"
fi
TITLE=$(printf '%s' "$ISSUE_JSON" | jq -r '.title // ""')
BODY=$(printf '%s' "$ISSUE_JSON" | jq -r '.body // ""')
MILESTONE=$(printf '%s' "$ISSUE_JSON" | jq -r '.milestone.title // ""')

# --- Milestone (gh calls 2 and 3) --------------------------------------------

SIBLINGS_CLOSED=0
POSITION="unknown"
if [ -n "$MILESTONE" ]; then
    # The title is untrusted GitHub content: it reaches gh only as one quoted
    # argument, never through a string a shell re-reads.
    if ! CLOSED_JSON=$(gh issue list --milestone "$MILESTONE" --state closed \
            --json number,closedAt --limit "$MILESTONE_LIMIT" 2>"$ERR"); then
        unavailable "gh issue list (closed) failed: $(sanitize_error "$ERR")"
    fi
    if ! OPEN_JSON=$(gh issue list --milestone "$MILESTONE" --state open \
            --json number --limit "$MILESTONE_LIMIT" 2>"$ERR"); then
        unavailable "gh issue list (open) failed: $(sanitize_error "$ERR")"
    fi
    # closedAt and createdAt are both GitHub's fixed-width UTC ISO-8601
    # strings, so string order is time order.
    if ! SIBLINGS_CLOSED=$(printf '%s' "$CLOSED_JSON" | jq -e --arg c "$CREATED_AT" \
            '[.[] | select(.closedAt > $c)] | length' 2>"$ERR"); then
        unavailable "could not read the closed milestone list: $(sanitize_error "$ERR")"
    fi
    if ! CLOSED_COUNT=$(printf '%s' "$CLOSED_JSON" | jq -e 'length' 2>"$ERR") ||
       ! OPEN_COUNT=$(printf '%s' "$OPEN_JSON" | jq -e 'length' 2>"$ERR"); then
        unavailable "could not read the milestone lists: $(sanitize_error "$ERR")"
    fi
    if [ $((CLOSED_COUNT + OPEN_COUNT)) -eq 0 ]; then
        POSITION="unknown"
    elif [ "$CLOSED_COUNT" -eq 0 ]; then
        POSITION="first"
    elif [ "$OPEN_COUNT" -eq 1 ]; then
        POSITION="last"
    else
        POSITION="middle"
    fi
fi

# --- Referenced files --------------------------------------------------------

FILE_REFS=$(printf '%s\n' "$BODY" |
    grep -oE '`[^`]+\.[a-z]+`|[a-zA-Z0-9_/-]+\.[a-z]{1,4}' |
    sed 's/`//g' |
    grep -E "\\.($FILE_EXTENSIONS)\$" |
    sort -u |
    head -n "$MAX_FILE_REFS")

MODIFIED_LIST="$TMP_DIR/modified"
: > "$MODIFIED_LIST"
if [ -n "$FILE_REFS" ]; then
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        # Absolute paths and any `..` segment are dropped before any file test,
        # so every path read below is inside the working tree.
        case "$path" in
            /*|..|../*|*/..|*/../*) continue ;;
        esac
        [ -f "$path" ] || continue
        if ! last=$(git log --since="$CREATED_AT" --format=%H -1 -- "$path" 2>"$ERR"); then
            unavailable "git log failed for a referenced file: $(sanitize_error "$ERR")"
        fi
        [ -n "$last" ] && printf '%s\n' "$path" >> "$MODIFIED_LIST"
    done <<EOF
$FILE_REFS
EOF
fi
MODIFIED_JSON=$(jq -R -s 'split("\n") | map(select(length > 0))' < "$MODIFIED_LIST")

# --- Verdict -----------------------------------------------------------------

REPORT=$(jq -n \
    --argjson issue "$ISSUE" \
    --arg title "$TITLE" \
    --arg created "$CREATED_AT" \
    --argjson age "$AGE_DAYS" \
    --argjson threshold "$AGE_THRESHOLD_DAYS" \
    --arg milestone "$MILESTONE" \
    --argjson siblings "$SIBLINGS_CLOSED" \
    --arg position "$POSITION" \
    --argjson modified "$MODIFIED_JSON" '
    [ (if $age > $threshold then "issue is \($age) days old (threshold: \($threshold))" else empty end),
      (if $siblings > 0 then "\($siblings) sibling issues closed since creation" else empty end),
      (if $position == "middle" or $position == "last" then "milestone position is \($position)" else empty end),
      (if ($modified | length) > 0 then "\($modified | length) referenced files modified" else empty end)
    ] as $reasons
    | ($reasons | length > 0) as $stale
    | {
        verdict: (if $stale then "stale" else "fresh" end),
        introspection_recommended: $stale,
        issue: {
          number: $issue,
          title: $title,
          created_at: $created,
          age_days: $age,
          milestone: (if $milestone == "" then null else $milestone end)
        },
        signals: {
          issue_age_days: $age,
          age_threshold_days: $threshold,
          sibling_issues_closed_since_creation: $siblings,
          milestone_position: $position,
          files_modified_since_creation: $modified
        },
        reason: (if $stale then ($reasons | join("; ")) else "no staleness signals detected" end)
      }' 2>"$ERR") || unavailable "could not build the report: $(sanitize_error "$ERR")"

# Read the verdict back before printing anything, so a failed read exits 3
# with one report rather than falling through to 0 and reading as fresh.
VERDICT=$(printf '%s' "$REPORT" | jq -r '.verdict' 2>"$ERR") ||
    unavailable "could not read the report's verdict: $(sanitize_error "$ERR")"
printf '%s\n' "$REPORT"
case "$VERDICT" in
    fresh) exit 0 ;;
    stale) exit 1 ;;
esac
exit 3
