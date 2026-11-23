#!/usr/bin/env bash
set -euo pipefail

# Keeps milestone status words out of comparisons outside the shared readers.
#
# A roadmap milestone's status is read through four properties (satisfies,
# closes, terminal, colour) defined once in
# skills/roadmap/references/milestone-statuses.json. Two readers load that
# table: crates/shirabe-validate/src/statuses.rs for the Rust crates, and the
# lib_status functions in skills/coordinate/scripts/state-common.sh for the
# coordinate scripts. A tool that compares a status word itself (`== "Done"`,
# `case ... in Done)`, `eq_ignore_ascii_case("Verified")`) reads a v4 roadmap
# wrong the day a status is added or renamed, and nothing else notices. So
# this check runs the PRD's search over skills/ and crates/ and fails on every
# comparison against Done, Shipped, Closed, Completed or Verified that it
# finds anywhere else.
#
# The search is the PRD's pattern (an operator, then the status word), with
# three changes that keep it to comparisons:
#
#   - `!=`, and a shell test bracket's `=` with the word inside the bracket
#     (`[ "$s" = "Done" ]`), count as operators, since the PRD's `==` alone
#     misses the commonest shell form;
#   - `case` counts only as the shell `case ... in` form, so Rust's
#     `Err(case)` is not one;
#   - the status word must stand alone, so `FailClosed` is not `Closed`.
#
# A test suite's section heading (`echo "== a failure against the Done
# milestone =="`) is prose, not a comparison: the leading `echo "==` is
# removed before the line is matched.
#
# Accepted without a record:
#
#   - crates/shirabe-validate/src/statuses.rs, the Rust reader and its tests;
#   - the lib_status* functions in skills/coordinate/scripts/state-common.sh,
#     and skills/coordinate/scripts/lib-status_test.sh, their tests;
#   - lines that compare a PLAN, PRD, DESIGN or BRIEF document's status rather
#     than a milestone's: any line naming one of those words, and any line in
#     skills/plan, skills/prd, skills/design or skills/brief.
#
# Any other match needs a record in scripts/check-status-words.allow saying
# why the line is not a milestone status read (the format is documented at the
# top of that file). A record that covers no flagged line (stale), names a
# file outside skills/ and crates/, or has an empty reason is itself a
# failure: an allowlist that silently stops covering anything is worse than
# none.
#
# Usage:
#   bash scripts/check-status-words.sh
#
# Environment:
#   STATUS_WORDS_ROOT   repository root to scan (tests point it at a fixture
#                       copy); the allowlist is read from
#                       <root>/scripts/check-status-words.allow
#
# Exit codes:
#   0 - every flagged line is accepted or covered and every record is valid
#   1 - a flagged line without a record, or an invalid record
#   2 - the search itself could not run
#
# Runs on bash 3.2: no associative arrays, no mapfile, no ${var,,}.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${STATUS_WORDS_ROOT:-$SCRIPT_DIR/..}"
ROOT="$(cd "$ROOT" && pwd)"
ALLOWLIST="$ROOT/scripts/check-status-words.allow"
ALLOW_REL="scripts/check-status-words.allow"

TAB="$(printf '\t')"
failures=0

fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# The status words, each standing alone (no letter, digit or underscore on
# either side).
WORD='(^|[^[:alnum:]_])(Done|Shipped|Closed|Completed|Verified)([^[:alnum:]_]|$)'
# The comparison forms: the PRD's operators, `!=`, and the shell
# `case ... in`, each followed anywhere later on the line by a status word as
# in the PRD's search; and a shell test bracket's `=`, whose word must sit
# inside the same bracket, since `[ "$V4" = 1 ]; then S=Done` compares
# nothing against Done.
OP='(==|!=|=~|starts_with|eq_ignore_ascii_case|test\(|(^|[^[:alnum:]_])case .* in( |$))'
BRACKET='\[\[? [^]]* = [^]]*'
PATTERN="($OP.*$WORD)|($BRACKET$WORD)"
# A line naming the document types whose statuses are not milestone statuses.
DOC_TYPES='(^|[^[:alnum:]_])(PLAN|PRD|DESIGN|BRIEF)([^[:alnum:]_]|$)'

# lib_status_lines <file>: the line numbers inside a lib_status* function of
# a shell file, one per line. A function starts at `lib_status...() {` in the
# first column and ends at the first `}` in the first column after it; a
# one-line function is its own line.
lib_status_lines() {
    awk '
        /^lib_status[[:alnum:]_]*\(\)[[:space:]]*\{/ {
            print NR
            if ($0 !~ /\}[[:space:]]*$/) inside = 1
            next
        }
        inside { print NR; if ($0 ~ /^\}/) inside = 0 }
    ' "$1"
}

# is_flagged <text>: true when the line, its test-heading prefix removed, is
# a status-word comparison.
is_flagged() {
    printf '%s\n' "$1" | sed -e "s/^[[:space:]]*echo [\"']==//" | grep -qE "$PATTERN"
}

# accepted <file> <lineno> <text>: true when the line needs no record.
STATE_COMMON="skills/coordinate/scripts/state-common.sh"
STATE_COMMON_LINES=""
if [ -f "$ROOT/$STATE_COMMON" ]; then
    STATE_COMMON_LINES=" $(lib_status_lines "$ROOT/$STATE_COMMON" | tr '\n' ' ')"
fi
accepted() {
    case "$1" in
        crates/shirabe-validate/src/statuses.rs) return 0 ;;
        skills/coordinate/scripts/lib-status_test.sh) return 0 ;;
        skills/plan/* | skills/prd/* | skills/design/* | skills/brief/*) return 0 ;;
        "$STATE_COMMON")
            case "$STATE_COMMON_LINES " in *" $2 "*) return 0 ;; esac
            ;;
    esac
    printf '%s\n' "$3" | grep -qE "$DOC_TYPES"
}

# The search. In a git work tree it reads the tracked files, as the PRD's
# `git grep` does; a fixture root that isn't one is searched as a directory.
CANDIDATES=$(mktemp "${TMPDIR:-/tmp}/check-status-words.XXXXXX") || {
    echo "ERROR: could not create a temporary file" >&2
    exit 2
}
trap 'rm -f "$CANDIDATES"' EXIT
if git -C "$ROOT" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    GREP_MODE=""
else
    GREP_MODE="--no-index"
fi
set +e
(cd "$ROOT" && git grep $GREP_MODE -nIE "$PATTERN" -- skills crates) > "$CANDIDATES"
grep_status=$?
set -e
if [ "$grep_status" -gt 1 ]; then
    echo "ERROR: the search over skills/ and crates/ failed (git grep exit $grep_status)" >&2
    exit 2
fi

# The allowlist's records, as file<TAB>match<TAB>reason lines, comments and
# blank lines dropped.
RECORDS=""
if [ -f "$ALLOWLIST" ]; then
    RECORDS=$(grep -v '^[[:space:]]*#' "$ALLOWLIST" | grep -v '^[[:space:]]*$' || true)
fi

# covered <file> <text>: true when a record for the file has a match the
# line contains.
covered() {
    [ -n "$RECORDS" ] || return 1
    while IFS="$TAB" read -r rfile rmatch _rreason; do
        [ "$rfile" = "$1" ] || continue
        [ -n "$rmatch" ] || continue
        case "$2" in *"$rmatch"*) return 0 ;; esac
    done <<EOF
$RECORDS
EOF
    return 1
}

# Every flagged line that is neither accepted nor covered.
FLAGGED=""
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file=${hit%%:*}
    rest=${hit#*:}
    lineno=${rest%%:*}
    text=${rest#*:}
    is_flagged "$text" || continue
    accepted "$file" "$lineno" "$text" && continue
    FLAGGED="$FLAGGED$file$TAB$text
"
    if ! covered "$file" "$text"; then
        trimmed=$(printf '%s' "$text" | sed -e 's/^[[:space:]]*//' | cut -c1-200)
        fail "$file:$lineno: compares a milestone status word outside the shared readers: $trimmed"
    fi
done < "$CANDIDATES"

# Every record must cover at least one flagged line, in a scanned file, and
# give a reason.
if [ -n "$RECORDS" ]; then
    while IFS="$TAB" read -r rfile rmatch rreason; do
        case "$rfile" in
            skills/* | crates/*) ;;
            *)
                fail "$ALLOW_REL: record for '$rfile' names a file outside skills/ and crates/"
                continue
                ;;
        esac
        if [ -z "$rmatch" ]; then
            fail "$ALLOW_REL: record for $rfile has an empty match"
            continue
        fi
        if [ -z "$rreason" ]; then
            fail "$ALLOW_REL: record for $rfile ('$rmatch') has no reason"
        fi
        hit=0
        if [ -n "$FLAGGED" ]; then
            while IFS="$TAB" read -r ffile ftext; do
                [ "$ffile" = "$rfile" ] || continue
                case "$ftext" in *"$rmatch"*) hit=1; break ;; esac
            done <<EOF
$FLAGGED
EOF
        fi
        if [ "$hit" -eq 0 ]; then
            fail "$ALLOW_REL: record for $rfile ('$rmatch') covers no flagged line (stale)"
        fi
    done <<EOF
$RECORDS
EOF
fi

if [ "$failures" -gt 0 ]; then
    echo ""
    echo "$failures problem(s). Read a milestone's status through its properties:"
    echo "  Rust: crates/shirabe-validate/src/statuses.rs"
    echo "  shell: lib_status_prop in skills/coordinate/scripts/state-common.sh"
    echo "A line that compares something other than a milestone status needs a"
    echo "record in $ALLOW_REL saying why."
    exit 1
fi

echo "OK: no milestone status word is compared outside the shared readers."
exit 0
