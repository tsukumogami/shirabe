#!/usr/bin/env bash
set -euo pipefail

# Keeps "merged" honest in the SKILL.md files that describe how a run ends.
#
# `/execute` without `--merge` leaves a ready pull request; so does a
# coordinated run that pauses for a human merge, and `/work-on` never merges at
# all. Text that says these skills take work "to merged code" promises a merge
# the default run does not make, and a caller reading `exit: full-run` as "the
# PR merged" acts on something that did not happen. So in the scanned files the
# word describes exactly two things: the `merged` final state, and a PR GitHub
# itself reports as `MERGED`.
#
# Every line containing "merged" (case-insensitive) is flagged, except where
# the only occurrences are these accepted tokens:
#
#   `merged`           the final state, in backticks
#   outcome=merged     the printed outcome line
#   pr_state=merged    a recorded PR state
#   MERGED             GitHub's PR state, upper case
#   unmerged           negation
#   not-merged         negation
#
# Any other occurrence needs a record in scripts/check-merged-wording.allow
# saying why that line describes GitHub PR state rather than a run outcome.
# The allowlist format is documented at the top of that file.
#
# The records are checked too. A record whose fixed string matches no line or
# more than one line in its file, whose matched line has no flagged occurrence
# left (stale), whose reason is empty, or which names a file this script does
# not scan, is itself a failure. An allowlist that silently stops covering
# anything is worse than none.
#
# Usage:
#   bash scripts/check-merged-wording.sh
#
# Environment:
#   MERGED_WORDING_ROOT       repository root to scan (tests point it at a
#                             fixture copy); the allowlist is read from
#                             <root>/scripts/check-merged-wording.allow
#
# Exit codes:
#   0 - every flagged line is covered and every record is valid
#   1 - a flagged line without a record, or an invalid record
#
# Runs on bash 3.2: no associative arrays, no mapfile, no ${var,,}.

# The files this check scans, repository-relative and space-separated. Adding
# a skill is a one-line change here.
SCANNED_FILES="skills/execute/SKILL.md skills/work-on/SKILL.md skills/deliver/SKILL.md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${MERGED_WORDING_ROOT:-$SCRIPT_DIR/..}"
ROOT="$(cd "$ROOT" && pwd)"
ALLOWLIST="$ROOT/scripts/check-merged-wording.allow"
ALLOW_REL="scripts/check-merged-wording.allow"

TAB="$(printf '\t')"
failures=0

fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# residual <line>: the line with every accepted token removed. Whatever
# "merged" survives this is an occurrence that needs a record.
residual() {
    printf '%s\n' "$1" | sed \
        -e 's/`merged`//g' \
        -e 's/outcome=merged//g' \
        -e 's/pr_state=merged//g' \
        -e 's/not-merged//g' \
        -e 's/[Uu]nmerged//g' \
        -e 's/MERGED//g'
}

# is_flagged <line>: true when the line still says "merged" after the
# accepted tokens are removed.
is_flagged() {
    residual "$1" | grep -qi 'merged'
}

is_scanned() {
    local f
    for f in $SCANNED_FILES; do
        [ "$f" = "$1" ] && return 0
    done
    return 1
}

# -- scanned files exist ------------------------------------------------------

for f in $SCANNED_FILES; do
    if [ ! -f "$ROOT/$f" ]; then
        fail "$f: scanned file not found"
    fi
done

# -- allowlist records ----------------------------------------------------------

# Valid records, one "<file><TAB><match>" per line, for the coverage pass.
records=""

if [ -f "$ALLOWLIST" ]; then
    lineno=0
    while IFS= read -r raw || [ -n "$raw" ]; do
        lineno=$((lineno + 1))
        case "$raw" in
            ''|'#'*) continue ;;
        esac
        where="$ALLOW_REL:$lineno"

        case "$raw" in
            *"$TAB"*"$TAB"*) ;;
            *)
                fail "$where: not a tab-separated <file> <match> <reason> record"
                continue
                ;;
        esac
        file="${raw%%"$TAB"*}"
        rest="${raw#*"$TAB"}"
        match="${rest%%"$TAB"*}"
        reason="${rest#*"$TAB"}"
        label="$where ($file: $match)"

        if ! is_scanned "$file"; then
            fail "$label: names a file outside the scanned list ($SCANNED_FILES)"
            continue
        fi
        if [ -z "$(printf '%s' "$reason" | tr -d ' \t')" ]; then
            fail "$label: empty reason"
            continue
        fi
        if [ -z "$match" ]; then
            fail "$label: empty match string"
            continue
        fi
        [ -f "$ROOT/$file" ] || continue

        count=$(grep -c -F -- "$match" "$ROOT/$file" || true)
        if [ "$count" -ne 1 ]; then
            fail "$label: matches $count lines in $file, expected exactly 1"
            continue
        fi
        matched=$(grep -F -- "$match" "$ROOT/$file")
        if ! is_flagged "$matched"; then
            fail "$label: stale, its line has no flagged \"merged\" left"
            continue
        fi
        records="${records}${file}${TAB}${match}
"
    done < "$ALLOWLIST"
fi

# is_covered <file> <line>: a valid record for this file whose fixed string
# appears in the line.
is_covered() {
    local rf rmatch rec
    while IFS= read -r rec; do
        [ -n "$rec" ] || continue
        rf="${rec%%"$TAB"*}"
        rmatch="${rec#*"$TAB"}"
        [ "$rf" = "$1" ] || continue
        case "$2" in
            *"$rmatch"*) return 0 ;;
        esac
    done <<EOF
$records
EOF
    return 1
}

# -- flagged lines --------------------------------------------------------------

for f in $SCANNED_FILES; do
    [ -f "$ROOT/$f" ] || continue
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        n="${hit%%:*}"
        text="${hit#*:}"
        is_flagged "$text" || continue
        is_covered "$f" "$text" && continue
        fail "$f:$n: \"merged\" that is neither the \`merged\` final state nor GitHub's MERGED, and no record covers it: $text"
    done <<EOF
$(grep -n -i 'merged' "$ROOT/$f" || true)
EOF
done

if [ "$failures" -gt 0 ]; then
    echo "check-merged-wording: $failures failure(s)"
    exit 1
fi
echo "PASS: check-merged-wording ($SCANNED_FILES)"
exit 0
