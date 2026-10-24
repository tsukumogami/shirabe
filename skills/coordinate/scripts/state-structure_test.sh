#!/usr/bin/env bash
# state-structure_test.sh -- the transitional structure test: no new file
# under skills/coordinate/scripts/ or koto-templates/ may match the patterns
# the GitHub coordinator record's removal deletes
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, "The structure
# test"), and the files that match today are allowed by name, so the list can
# only shrink.
#
# The patterns: a file named `record-*.sh` or `record-codec.jq` (key `name`),
# and a file whose text names `record-(common|source|parse|render).sh`
# (`libs`), `record-codec` (`codec`), `Coordinator record:` (`title`),
# `collaborators/` (`collaborators`), `docs/disciplines/` (`disciplines`) or
# one of the five removed `store-*` refusal codes (`store-codes`). The allow
# list below holds each `<key> <path>` pair that matched at this change's base
# commit. A match not on it fails, and so does an entry that no longer
# matches: a change that removes a match removes its entry, and the removal
# (#984) empties the list. Whichever of this test and another change that adds
# or removes a match merges second keeps the list in step.
#
# This file names every pattern, so it is left out of the scan; its fixtures
# are built at run time in the suite's scratch directory, so no file in the
# tree is one.
#
# Covers: the skill's files pass with today's matches allowed; one fixture per
# pattern, each failing alone under its key, in either directory; a new
# record-*.sh file, a new mention in a file not on the list, and an allowed
# file mentioning a pattern it isn't listed for, each added to a copy of the
# skill's tree, fail it; an entry that no longer matches fails it; and a
# symbolic link named record-*.sh, a link whose target names a pattern, and a
# binary file naming one each fail it too.
#
# Usage: bash skills/coordinate/scripts/state-structure_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/test-lib.sh"
SKILL=$(cd "$HERE/.." && pwd)
SELF=scripts/state-structure_test.sh

# <key> <extended regular expression>, one pattern a line.
PATTERNS='libs record-(common|source|parse|render)\.sh
codec record-codec
title Coordinator record:
collaborators collaborators/
disciplines docs/disciplines/
store-codes store-(malformed|unverified|conflict|moved|discipline)'

# matches <skill root>: every match under its scripts/ and koto-templates/, one
# `<key> <path>` line each, sorted, this file left out. A symbolic link counts
# by its own name and by its target's text, and a file grep would call binary
# is read as text, so neither slips past.
matches() {
    (
        cd "$1" || exit 2
        find scripts koto-templates \( -type f -o -type l \) \( -name 'record-*.sh' -o -name 'record-codec.jq' \) | sed 's/^/name /'
        # find -L lists a link's target as a file under the link's own path, on
        # GNU and BSD alike (BSD grep -R doesn't follow links by default).
        find -L scripts koto-templates -type f -print0 > "$T/scan-files"
        while read -r key pat; do
            xargs -0 grep -alE -e "$pat" < "$T/scan-files" | sed "s/^/$key /"
        done <<EOF
$PATTERNS
EOF
    ) | awk -v s="$SELF" '$2 != s' | LC_ALL=C sort
}
# check <skill root> <allow file>: prints `unexpected: <key> <path>` for each
# match the list doesn't hold and `stale: <key> <path>` for each entry that no
# longer matches; 0 when there is neither.
check() {
    matches "$1" > "$T/matches"
    awk 'FILENAME == ARGV[1] { a[$0] = 1; next } !($0 in a) { print "unexpected: " $0 }' "$2" "$T/matches" > "$T/check"
    awk 'FILENAME == ARGV[1] { m[$0] = 1; next } !($0 in m) { print "stale: " $0 }' "$T/matches" "$2" >> "$T/check"
    cat "$T/check"
    [ ! -s "$T/check" ]
}
# fixture <path> <text>: a scratch tree holding one file, for the empty list.
fixture() {
    rm -rf "$T/fx"
    mkdir -p "$T/fx/scripts" "$T/fx/koto-templates" "$(dirname "$T/fx/$1")"
    printf '%s\n' "$2" > "$T/fx/$1"
}

# The allow list: the matches at this change's base commit.
cat > "$T/allow" <<'EOF'
codec scripts/milestone.sh
codec scripts/pick-facts.sh
codec scripts/record-decision.sh
codec scripts/roadmap-status.sh
codec scripts/state-schema_test.sh
collaborators scripts/testdata/gh
disciplines scripts/discipline-session_test.sh
libs scripts/board-lib.sh
libs scripts/board-verdict_test.sh
libs scripts/closeout-read.sh
libs scripts/coordinate-open.sh
libs scripts/coordinate-report.sh
libs scripts/coordinate-template-structure_engine_test.sh
libs scripts/decision-archive_test.sh
libs scripts/decision-next.sh
libs scripts/decision-next_test.sh
libs scripts/decision-render.sh
libs scripts/deferral-check.sh
libs scripts/dispatch-common.sh
libs scripts/holding-link.sh
libs scripts/land-check_test.sh
libs scripts/milestone.sh
libs scripts/pause-read.sh
libs scripts/pick-facts.sh
libs scripts/posture-read.sh
libs scripts/quiet-check.sh
libs scripts/reconcile-check_test.sh
libs scripts/reconcile-deps.sh
libs scripts/reconcile-pass.sh
libs scripts/reconcile-pass_engine_test.sh
libs scripts/reconcile-pass_test.sh
libs scripts/reconcile-read.sh
libs scripts/record-append.sh
libs scripts/record-common.sh
libs scripts/record-confirm.sh
libs scripts/record-decision.sh
libs scripts/record-find.sh
libs scripts/record-handover.sh
libs scripts/record-hold.sh
libs scripts/record-holding.sh
libs scripts/record-open.sh
libs scripts/record-source.sh
libs scripts/record-source_test.sh
libs scripts/record-state.sh
libs scripts/record-state_test.sh
libs scripts/record-write-core.sh
libs scripts/record-write.sh
libs scripts/record-write_test.sh
libs scripts/report-facts.sh
libs scripts/report-questions.sh
libs scripts/roadmap-features_test.sh
libs scripts/roadmap-status-entry_test.sh
libs scripts/roadmap-status.sh
libs scripts/start-check.sh
libs scripts/state-schema.jq
libs scripts/testdata/board/helpers.sh
name scripts/record-append-on_test.sh
name scripts/record-append.sh
name scripts/record-append_test.sh
name scripts/record-common.sh
name scripts/record-confirm.sh
name scripts/record-confirm_test.sh
name scripts/record-decision.sh
name scripts/record-decision_test.sh
name scripts/record-find.sh
name scripts/record-find_test.sh
name scripts/record-handover.sh
name scripts/record-hold.sh
name scripts/record-hold_test.sh
name scripts/record-holding.sh
name scripts/record-holding_test.sh
name scripts/record-open.sh
name scripts/record-open_test.sh
name scripts/record-source.sh
name scripts/record-source_test.sh
name scripts/record-state.sh
name scripts/record-state_test.sh
name scripts/record-write-core.sh
name scripts/record-write.sh
name scripts/record-write_test.sh
store-codes scripts/record-source_test.sh
store-codes scripts/state-schema.jq
store-codes scripts/state-schema_test.sh
EOF
: > "$T/empty"

echo "== the skill's files =="
OUT=$(check "$SKILL" "$T/allow"); rc=$?
eq "the skill's files pass, today's matches allowed by name" "0 " "$rc $OUT"

echo "== one fixture per pattern =="
fx() { # fx <label> <path> <text> <key>: the fixture fails alone, under its key
    fixture "$2" "$3"
    OUT=$(check "$T/fx" "$T/empty"); local rc=$?
    eq "$1" "1 unexpected: $4 $2" "$rc $OUT"
}
fx "a file named record-*.sh" scripts/record-new.sh 'echo new' name
fx "a file named record-codec.jq, anywhere" scripts/lib/record-codec.jq 'def x: 1;' name
fx "a file naming a record library" scripts/x.sh '. "$HERE/record-source.sh"' libs
fx "a file naming the codec" koto-templates/x.md 'include "record-codec";' codec
fx "a file naming the record's title" scripts/x.sh 'title="Coordinator record: ROADMAP-x"' title
fx "a file naming a collaborator read" scripts/x.sh 'gh api repos/o/r/collaborators/alice/permission' collaborators
fx "a file naming a discipline's handoff file" koto-templates/x.md 'see docs/disciplines/perf.md' disciplines
fx "a file naming a removed store code" scripts/x.sh 'echo "refused: store-moved"' store-codes

echo "== a change to the skill's tree =="
rm -rf "$T/copy"
mkdir -p "$T/copy"
cp -R "$SKILL/scripts" "$SKILL/koto-templates" "$T/copy/"
printf 'echo extra\n' > "$T/copy/scripts/record-extra.sh"
OUT=$(check "$T/copy" "$T/allow"); rc=$?
eq "a new record-*.sh file fails it" "1 unexpected: name scripts/record-extra.sh" "$rc $OUT"
rm -f "$T/copy/scripts/record-extra.sh"
printf 'echo "Coordinator record: ROADMAP-x"\n' > "$T/copy/scripts/notes.sh"
OUT=$(check "$T/copy" "$T/allow"); rc=$?
eq "a new mention in a file not on the list fails it" "1 unexpected: title scripts/notes.sh" "$rc $OUT"
rm -f "$T/copy/scripts/notes.sh"
grep -qxF 'store-codes scripts/record-append.sh' "$T/allow" && bad "record-append.sh isn't listed for store-codes" "" || ok "record-append.sh isn't listed for store-codes"
printf '# refused: store-moved\n' >> "$T/copy/scripts/record-append.sh"
OUT=$(check "$T/copy" "$T/allow"); rc=$?
eq "an allowed file mentioning a pattern it isn't listed for fails it" "1 unexpected: store-codes scripts/record-append.sh" "$rc $OUT"
cp "$SKILL/scripts/record-append.sh" "$T/copy/scripts/record-append.sh"
OUT=$(check "$T/copy" "$T/allow"); rc=$?
eq "  ... and the copy passes again once it is back" "0 " "$rc $OUT"
{ cat "$T/allow"; printf 'name scripts/record-gone.sh\n'; } > "$T/allow-stale"
OUT=$(check "$T/copy" "$T/allow-stale"); rc=$?
eq "an entry that no longer matches fails it" "1 stale: name scripts/record-gone.sh" "$rc $OUT"
# A symbolic link and a binary file don't slip past: a link counts by its own
# name and by its target's text, and a file holding a NUL byte is read as text.
mkdir -p "$T/outside"
printf 'echo clean\n' > "$T/outside/clean.sh"
printf 'echo "Coordinator record: ROADMAP-x"\n' > "$T/outside/titled.sh"
ln -s "$T/outside/clean.sh" "$T/copy/scripts/record-link.sh"
OUT=$(check "$T/copy" "$T/allow"); rc=$?
eq "a symbolic link named record-*.sh fails it" "1 unexpected: name scripts/record-link.sh" "$rc $OUT"
rm -f "$T/copy/scripts/record-link.sh"
ln -s "$T/outside/titled.sh" "$T/copy/scripts/notes-link.sh"
OUT=$(check "$T/copy" "$T/allow"); rc=$?
eq "a symbolic link whose target names a pattern fails it" "1 unexpected: title scripts/notes-link.sh" "$rc $OUT"
rm -f "$T/copy/scripts/notes-link.sh"
printf 'x\000y\nCoordinator record: ROADMAP-x\n' > "$T/copy/scripts/blob.bin"
OUT=$(check "$T/copy" "$T/allow"); rc=$?
eq "a binary file naming a pattern fails it" "1 unexpected: title scripts/blob.bin" "$rc $OUT"
rm -f "$T/copy/scripts/blob.bin"
OUT=$(check "$T/copy" "$T/allow"); rc=$?
eq "  ... and the copy passes again once they are gone" "0 " "$rc $OUT"

done_tests state-structure_test
