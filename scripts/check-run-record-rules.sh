#!/usr/bin/env bash
# check-run-record-rules.sh -- the run record's retention rules, checked over
# shirabe's own skills and scripts.
#
# A run that leaves its PRs ready or merged pins the sessions holding its
# evidence (scripts/run-record-pin.sh), and a pin keeps a session past every
# removal by rule. Three things would quietly undo that, and this check fails
# on each:
#
#   run-record/unpin            a `koto session unpin` call anywhere in
#                               skills/ or scripts/. shirabe never unpins: a
#                               pin comes off by hand
#                               (references/koto-session-retention.md).
#   run-record/retention-window a retention window shirabe sets itself: a
#                               `koto config set` of a `retention.` key, or a
#                               prune given `--older-than`. How long koto
#                               keeps a finished session is koto's setting,
#                               and the pin is what keeps the record.
#   run-record/prune-unpinned   a Markdown paragraph in skills/ that tells
#                               the reader to run `koto session cleanup` or
#                               `koto session prune` without saying that
#                               pinned sessions are kept (it must say
#                               "pinned"): an instruction that reads as
#                               removing everything sends someone to
#                               unpin first. The guard is lexical: any
#                               paragraph holding the word passes, so a
#                               reviewer still reads what it says.
#
# Not policed: skills/coordinate/, which another change edits; test suites
# (`*_test.sh`) and test data (`testdata/`), which set up throwaway scratch
# stores; and this script and its own test, which name the patterns.
#
# Usage: check-run-record-rules.sh [--root DIR]
#   --root  the repository to check (default: the one this script is in)
#
# Output: one line per finding, `<rule>: <path>:<line>: <text>`, on stdout;
# a summary on stderr.
#
# Exit codes: 0 clean, 1 a finding, 64 usage.
#
# Requires: bash 3.2+, grep, awk.
set -uo pipefail

PROG=check-run-record-rules
SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
ROOT=$(CDPATH='' cd "$SELF_DIR/.." && pwd) || exit 64

usage() { echo "$PROG: $*" >&2; echo "usage: check-run-record-rules.sh [--root DIR]" >&2; exit 64; }

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || usage "--root needs a directory"
            [ -d "$2" ] || usage "--root [$2] is not a directory"
            ROOT=$(CDPATH='' cd "$2" && pwd) || usage "--root [$2] can't be entered"
            shift 2
            ;;
        *) usage "unexpected argument [$1]" ;;
    esac
done

cd -- "$ROOT" || exit 64

# files: every regular file under skills/ and scripts/ this check polices, one
# path per line, relative to the root.
files() {
    local d
    for d in skills scripts; do
        [ -d "$d" ] || continue
        find "$d" -type f \
            ! -path 'skills/coordinate/*' \
            ! -path '*/testdata/*' \
            ! -name '*_test.sh' \
            ! -path 'scripts/check-run-record-rules.sh' \
            -print
    done | LC_ALL=C sort
}

FOUND=0
report() { # report <rule> <path> <line> <text>
    printf '%s: %s:%s: %s\n' "$1" "$2" "$3" "$4"
    FOUND=$((FOUND + 1))
}

LIST=$(files)

while IFS= read -r f; do
    [ -n "$f" ] || continue
    # The unpin call.
    while IFS=: read -r n text; do
        [ -n "$n" ] && report run-record/unpin "$f" "$n" "$text"
    done <<<"$(grep -nE 'koto[[:space:]]+session[[:space:]]+unpin' -- "$f" 2>/dev/null)"
    # A retention window shirabe sets.
    while IFS=: read -r n text; do
        [ -n "$n" ] && report run-record/retention-window "$f" "$n" "$text"
    done <<<"$(grep -nE 'koto[[:space:]]+config[[:space:]]+set([[:space:]]+--[a-z-]+)*[[:space:]]+["'"'"']?(session\.)?retention\.|session[[:space:]]+prune[^#]*--older-than' -- "$f" 2>/dev/null)"
done <<<"$LIST"

# A cleanup or prune instruction in a skill's Markdown whose paragraph doesn't
# say pinned sessions are kept. A paragraph is a run of non-blank lines; the
# line number is its first line's.
while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in skills/*.md) ;; *) continue ;; esac
    while IFS=$'\t' read -r n text; do
        [ -n "$n" ] && report run-record/prune-unpinned "$f" "$n" "$text"
    done <<<"$(awk '
        function flush() {
            if (para != "" && para ~ pat && tolower(para) !~ /pinned/)
                printf "%d\t%s\n", start, substr(first, 1, 160)
            para = ""
        }
        BEGIN { pat = "koto[ \t\n]+session[ \t\n]+(cleanup|prune)" }
        /^[ \t]*$/ { flush(); next }
        { if (para == "") { start = NR; first = $0 }; para = para "\n" $0 }
        END { flush() }' "$f" 2>/dev/null)"
done <<<"$LIST"

if [ "$FOUND" -gt 0 ]; then
    echo "$PROG: $FOUND finding(s); see references/koto-session-retention.md, \"What shirabe pins\"" >&2
    exit 1
fi
echo "$PROG: clean" >&2
exit 0
