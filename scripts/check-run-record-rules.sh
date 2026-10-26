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
# A fourth rule keeps the lifecycle documents saying one thing: a PLAN and a
# ROADMAP are deleted when their work finishes, and a later reader goes to the
# run's koto session through scripts/run-record-lookup.sh, not to the plan.
#
#   run-record/lifecycle        in any of the seven documents LIFECYCLE_DOCS
#                               lists, a stale claim: a PLAN that stays in
#                               docs/plans/ through every state; Done as a
#                               PLAN's or ROADMAP's terminal state (a table
#                               row for Done calling it terminal, a Plan or
#                               Roadmap row whose last cell is Done, or
#                               prose saying Done is terminal); or a
#                               historical or audit record. Also a document
#                               that doesn't name
#                               scripts/run-record-lookup.sh, or that is
#                               missing. Prose is matched a paragraph at a
#                               time, case-folded, so a claim wrapped over
#                               two lines is still found; in a shell script
#                               only the leading comment block is read.
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

# The lifecycle documents: each states the PLAN and ROADMAP lifecycle and sends
# a later reader to the lookup.
LIFECYCLE_DOCS='skills/plan/references/plan-format.md
skills/plan/SKILL.md
skills/plan/references/quality/plan-doc-structure.md
skills/roadmap/references/roadmap-format.md
skills/roadmap/SKILL.md
references/pipeline-model.md
skills/work-on/scripts/run-cascade.sh'
LOOKUP_NAME='scripts/run-record-lookup.sh'

while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -f "$f" ]; then
        report run-record/lifecycle "$f" 0 "lifecycle document missing"
        continue
    fi
    sh=0
    case "$f" in *.sh) sh=1 ;; esac
    # A stale claim, by paragraph (prose) or by line (table rows).
    while IFS=$'\t' read -r n text; do
        [ -n "$n" ] && report run-record/lifecycle "$f" "$n" "$text"
    done <<<"$(awk -v sh="$sh" '
        function stale(p) {
            if (p ~ /(stays?|remains?|lives?|kept)[^.]* through every (lifecycle )?(state|status)/) return 1
            if (p ~ /(historical|audit)[ -](record|artifact|archive)/) return 1
            if (p ~ /done[*` ]* (is|as|remains) (the |a |its )?((plan|roadmap)(.s)? )?terminal/) return 1
            return 0
        }
        function flush() {
            if (para != "" && stale(para))
                printf "%d\t%s\n", start, substr(first, 1, 160)
            para = ""
        }
        {
            line = $0
            if (sh) {
                if (NR == 1 && line ~ /^#!/) next
                if (line !~ /^#/) { flush(); exit }
                sub(/^# ?/, "", line)
            }
            low = tolower(line)
            # Table rows: Done called terminal, or a Plan/Roadmap whose
            # last cell is Done.
            if (low ~ /^[ \t]*\|[ \t*]*done[ \t*]*\|.*terminal/ ||
                low ~ /^[ \t]*\|[ \t*]*(plan|roadmap)[ \t*]*\|.*\|[ \t*]*done[ \t*]*\|[ \t]*$/) {
                printf "%d\t%s\n", NR, substr(line, 1, 160)
            }
            if (low ~ /^[ \t]*$/) { flush(); next }
            if (para == "") { start = NR; first = line }
            para = para " " low
            gsub(/[ \t]+/, " ", para)
        }
        END { flush() }' "$f" 2>/dev/null)"
    # The lookup named (in a shell script, in its header).
    named=$(awk -v sh="$sh" '
        sh && NR == 1 && /^#!/ { next }
        sh && !/^#/ { exit }
        { print }' "$f" 2>/dev/null)
    case "$named" in
        *"$LOOKUP_NAME"*) ;;
        *) report run-record/lifecycle "$f" 1 "does not name $LOOKUP_NAME, where a later reader finds what the work followed" ;;
    esac
done <<<"$LIFECYCLE_DOCS"

if [ "$FOUND" -gt 0 ]; then
    echo "$PROG: $FOUND finding(s); see references/koto-session-retention.md, \"What shirabe pins\", and the Lifecycle section of skills/plan/references/plan-format.md" >&2
    exit 1
fi
echo "$PROG: clean" >&2
exit 0
