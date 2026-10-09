#!/usr/bin/env bash
# check-rule-registry-adoption.sh -- the one-time checks for the pull request
# that adopts references/rule-registry.json, against its merge base.
#
# Adopting the registry must lose nothing. Compared with <base>:
#
#   - every id in the gate scripts' old rule table
#     (skills/work-on/scripts/gate-rules.tsv) and in the review-shadow
#     criteria.json is the id of exactly one registry entry;
#   - review-shadow.py, test_review_shadow.py and criteria.json are unchanged;
#   - no line is removed from a span the offload baseline's load manifest
#     loads into an agent's context (a whole file, a file's body after its
#     frontmatter, or a koto template's `## <state>` section, cut the way
#     scripts/offload-baseline.sh cuts them), nor from /execute's template.
#
# These hold for the adopting pull request only: a later change that removes
# a template line on purpose is how a rule gets withheld, which a standing
# check would forbid. So this runs only while the base still has the old
# table, and once main no longer does it prints that it skipped. The standing
# checks are scripts/check-rule-registry.sh.
#
# Usage: check-rule-registry-adoption.sh [--root <dir>] <base>
#   --root  the repository to check (default: this script's repository)
#
# Exit codes: 0 passed or skipped, 1 problems listed on stdout, 2 could not run.

set -u

PROG=check-rule-registry-adoption

die2() {
    echo "$PROG: $*" >&2
    exit 2
}

SELF_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) \
    || die2 "cannot find its own directory"
ROOT=$(CDPATH='' cd -P -- "$SELF_DIR/.." && pwd -P) || die2 "cannot find the repository root"
BASE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || die2 "--root needs a directory"
            ROOT=$(CDPATH='' cd -P -- "$2" 2>/dev/null && pwd -P) || die2 "--root $2 is not a directory"
            shift 2 ;;
        -*) die2 "unknown option $1" ;;
        *)
            [ -z "$BASE" ] || die2 "usage: check-rule-registry-adoption.sh [--root <dir>] <base>"
            BASE=$1; shift ;;
    esac
done
[ -n "$BASE" ] || die2 "usage: check-rule-registry-adoption.sh [--root <dir>] <base>"

command -v jq >/dev/null 2>&1 || die2 "jq is required"
command -v git >/dev/null 2>&1 || die2 "git is required"

OLD_TABLE=skills/work-on/scripts/gate-rules.tsv
CRITERIA=scripts/review-shadow/criteria.json
SHADOW_FILES="scripts/review-shadow/review-shadow.py scripts/review-shadow/test_review_shadow.py $CRITERIA"
MANIFEST=docs/measurement/offload-baseline/load-manifest.tsv
EXECUTE_TEMPLATE=skills/execute/koto-templates/execute.md
REG="$ROOT/references/rule-registry.json"

repo_git() {
    git -C "$ROOT" "$@"
}

repo_git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 || die2 "$BASE is not a commit"

# at_base <path>: 0 when the base has the file, 1 when it doesn't. A tree git
# can't read (a partial clone, say) is no answer, so it exits 2 rather than
# reading as absent.
at_base() {
    local out
    out=$(repo_git ls-tree --name-only "$BASE" -- "$1" 2>/dev/null) || die2 "cannot read the base's tree for $1"
    [ -n "$out" ]
}

if ! at_base "$OLD_TABLE"; then
    echo "$PROG: skipped: the base has no $OLD_TABLE, so there is no adoption to check"
    exit 0
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/check-rule-registry-adoption.XXXXXX") || die2 "cannot make a scratch directory"
trap 'rm -rf "$TMP"' EXIT

PROBLEMS=0
problem() {
    printf '%s: %s\n' "$PROG" "$*"
    PROBLEMS=$((PROBLEMS + 1))
}

# ---------------------------------------------------------------- ids

jq -r '.rules[] | objects | .id | strings' "$REG" > "$TMP/head-ids" 2>/dev/null \
    || die2 "cannot read references/rule-registry.json"
repo_git show "$BASE:$OLD_TABLE" > "$TMP/table" || die2 "cannot read $OLD_TABLE at the base"
awk -F'\t' '/^#/ || NF == 0 { next } { print $1 }' "$TMP/table" > "$TMP/base-ids"
if at_base "$CRITERIA"; then
    repo_git show "$BASE:$CRITERIA" > "$TMP/criteria.json" || die2 "cannot read $CRITERIA at the base"
    jq -r '.criteria[].rule_id | strings' "$TMP/criteria.json" >> "$TMP/base-ids" 2>/dev/null \
        || die2 "$CRITERIA at the base does not parse"
fi
[ -s "$TMP/base-ids" ] || die2 "found no ids at the base"
while IFS= read -r id; do
    [ -n "$id" ] || continue
    n=$(grep -cxF -- "$id" "$TMP/head-ids")
    [ "$n" = 1 ] || problem "$id: at the base, and the id of $n registry entries (want exactly 1)"
done < "$TMP/base-ids"

# ---------------------------------------------------------------- review-shadow

for f in $SHADOW_FILES; do
    if at_base "$f"; then
        repo_git diff --quiet --no-renames "$BASE" -- "$f"
        case $? in
            0) ;;
            1) problem "$f differs from the base" ;;
            *) die2 "git diff failed on $f" ;;
        esac
    fi
done

# ---------------------------------------------------------------- loaded spans

# span_lines <selector> < file: the line numbers of the file a selector loads,
# one per line, cut as scripts/offload-baseline.sh cuts spans: `body` and
# `state:<name>` skip a leading frontmatter block, and a state section runs
# from its `## <name>` heading to the next `## ` heading.
span_lines() {
    awk -v sel="$1" '
        BEGIN { want = (sel ~ /^state:/) ? "## " substr(sel, 7) : "" }
        sel == "file" { print NR; next }
        NR == 1 && $0 == "---" { infm = 1; next }
        infm && $0 == "---" { infm = 0; next }
        infm { next }
        sel == "body" { print NR; next }
        $0 == want { on = 1; print NR; next }
        on && /^## / { on = 0 }
        on { print NR }
    '
}

# removed_lines <path>: the base-side line numbers git diff removes from the
# file between the base and the working tree.
removed_lines() {
    repo_git diff -U0 --no-renames --no-ext-diff --no-color "$BASE" -- "$1" > "$TMP/diff" \
        || die2 "git diff failed on $1"
    awk '
        /^@@ / {
            split($2, o, ","); old = substr(o[1], 2) + 0; hunk = 1; next
        }
        !hunk { next }
        /^-/ { print old; old++; next }
    ' "$TMP/diff"
}

repo_git show "$BASE:$MANIFEST" > "$TMP/manifest" 2>/dev/null || die2 "cannot read $MANIFEST at the base"
awk -F'\t' '/^#/ || NF < 3 || $1 == "profile" { next } { print $2 "\t" $3 }' "$TMP/manifest" | sort -u > "$TMP/spans"
[ -s "$TMP/spans" ] || die2 "$MANIFEST at the base lists no spans"
printf '%s\tfile\n' "$EXECUTE_TEMPLATE" >> "$TMP/spans"

cut -f1 "$TMP/spans" | sort -u > "$TMP/span-paths"
while IFS= read -r p; do
    # A manifest row for a file the base doesn't have loads nothing to lose.
    at_base "$p" || continue
    removed_lines "$p" > "$TMP/removed"
    [ -s "$TMP/removed" ] || continue
    repo_git show "$BASE:$p" > "$TMP/base-file" || die2 "cannot read $p at the base"
    awk -F'\t' -v p="$p" '$1 == p { print $2 }' "$TMP/spans" > "$TMP/selectors"
    while IFS= read -r sel; do
        case "$sel" in
            file|body|state:?*) ;;
            *) die2 "$MANIFEST names selector [$sel] for $p, which this script can't cut" ;;
        esac
        span_lines "$sel" < "$TMP/base-file" > "$TMP/span" || die2 "cannot cut $p ($sel)"
        # A selector that selects nothing would protect nothing, silently.
        [ -s "$TMP/span" ] || die2 "$p ($sel) selects no lines at the base"
        hits=$(awk 'NR == FNR { in_span[$1] = 1; next } ($1 in in_span) { printf "%s%s", sep, $1; sep = "," }' \
            "$TMP/span" "$TMP/removed")
        [ -z "$hits" ] || problem "$p ($sel): base line(s) $hits removed"
    done < "$TMP/selectors"
done < "$TMP/span-paths"

if [ "$PROBLEMS" -gt 0 ]; then
    echo "$PROG: $PROBLEMS problem(s)"
    exit 1
fi
echo "$PROG: ok"
exit 0
