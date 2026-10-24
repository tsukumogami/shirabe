#!/usr/bin/env bash
# state-structure_test.sh -- the structure test: no file under
# skills/coordinate/scripts/ or koto-templates/ may match the patterns the
# GitHub coordinator record's removal deleted
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, "The structure
# test"). The removal is done, so the allow list is empty and every match
# fails except a named fixture.
#
# The patterns: a file named `record-*.sh` or `record-codec.jq` (key `name`),
# and a file whose text names `record-(common|source|parse|render).sh`
# (`libs`), `record-codec` (`codec`), `Coordinator record:` (`title`),
# `collaborators/` (`collaborators`), `docs/disciplines/` (`disciplines`) or
# one of the five removed `store-*` refusal codes (`store-codes`). The allow
# list below held each `<key> <path>` pair that matched while the removal ran;
# a match not on it or on the fixtures list fails, and so does an entry that no
# longer matches. The machinery stays, so the cases below show both rules still
# hold.
#
# This file names every pattern, so it is left out of the scan; its fixtures
# are built at run time in the suite's scratch directory, so no file in the
# tree is one.
#
# Covers: the skill's files pass with an empty allow list; one fixture per
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

# The allow list: empty, now the removal is done.
cat > "$T/allow" <<'EOF'
EOF
# The fixtures: a file that names a pattern for good, each with the reason it
# stays. The legacy importer reads a GitHub record's author's access from the
# collaborators endpoint, so the gh stand-in answers it.
cat > "$T/fixtures" <<'EOF'
collaborators scripts/testdata/gh
EOF
# The skill's tree is checked against the fixtures and the allow list together.
cat "$T/fixtures" "$T/allow" > "$T/skill"
: > "$T/empty"

echo "== the skill's files =="
eq "the allow list is empty" "0" "$(wc -l < "$T/allow" | tr -d ' ')"
OUT=$(check "$SKILL" "$T/skill"); rc=$?
eq "the skill's files pass with the fixtures and an empty allow list" "0 " "$rc $OUT"

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
OUT=$(check "$T/copy" "$T/skill"); rc=$?
eq "a new record-*.sh file fails it" "1 unexpected: name scripts/record-extra.sh" "$rc $OUT"
rm -f "$T/copy/scripts/record-extra.sh"
printf 'echo "Coordinator record: ROADMAP-x"\n' > "$T/copy/scripts/notes.sh"
OUT=$(check "$T/copy" "$T/skill"); rc=$?
eq "a new mention in a file not on the list fails it" "1 unexpected: title scripts/notes.sh" "$rc $OUT"
rm -f "$T/copy/scripts/notes.sh"
# A file the list allows for one pattern, with its own one-entry list (the
# skill's own list holds no entry once the removal is done).
printf 'echo "see docs/disciplines/perf.md"\n' > "$T/copy/scripts/allowed.sh"
{ cat "$T/skill"; printf 'disciplines scripts/allowed.sh\n'; } > "$T/allow-one"
OUT=$(check "$T/copy" "$T/allow-one"); rc=$?
eq "a file the list allows for a pattern passes" "0 " "$rc $OUT"
printf '# refused: store-moved\n' >> "$T/copy/scripts/allowed.sh"
OUT=$(check "$T/copy" "$T/allow-one"); rc=$?
eq "an allowed file mentioning a pattern it isn't listed for fails it" "1 unexpected: store-codes scripts/allowed.sh" "$rc $OUT"
rm -f "$T/copy/scripts/allowed.sh"
OUT=$(check "$T/copy" "$T/skill"); rc=$?
eq "  ... and the copy passes again once it is gone" "0 " "$rc $OUT"
{ cat "$T/skill"; printf 'name scripts/record-gone.sh\n'; } > "$T/allow-stale"
OUT=$(check "$T/copy" "$T/allow-stale"); rc=$?
eq "an entry that no longer matches fails it" "1 stale: name scripts/record-gone.sh" "$rc $OUT"
# A symbolic link and a binary file don't slip past: a link counts by its own
# name and by its target's text, and a file holding a NUL byte is read as text.
mkdir -p "$T/outside"
printf 'echo clean\n' > "$T/outside/clean.sh"
printf 'echo "Coordinator record: ROADMAP-x"\n' > "$T/outside/titled.sh"
ln -s "$T/outside/clean.sh" "$T/copy/scripts/record-link.sh"
OUT=$(check "$T/copy" "$T/skill"); rc=$?
eq "a symbolic link named record-*.sh fails it" "1 unexpected: name scripts/record-link.sh" "$rc $OUT"
rm -f "$T/copy/scripts/record-link.sh"
ln -s "$T/outside/titled.sh" "$T/copy/scripts/notes-link.sh"
OUT=$(check "$T/copy" "$T/skill"); rc=$?
eq "a symbolic link whose target names a pattern fails it" "1 unexpected: title scripts/notes-link.sh" "$rc $OUT"
rm -f "$T/copy/scripts/notes-link.sh"
printf 'x\000y\nCoordinator record: ROADMAP-x\n' > "$T/copy/scripts/blob.bin"
OUT=$(check "$T/copy" "$T/skill"); rc=$?
eq "a binary file naming a pattern fails it" "1 unexpected: title scripts/blob.bin" "$rc $OUT"
rm -f "$T/copy/scripts/blob.bin"
OUT=$(check "$T/copy" "$T/skill"); rc=$?
eq "  ... and the copy passes again once they are gone" "0 " "$rc $OUT"

done_tests state-structure_test
