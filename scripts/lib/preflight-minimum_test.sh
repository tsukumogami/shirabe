#!/usr/bin/env bash
# preflight-minimum_test.sh -- the koto minimum, as scripts/skill-preflight.sh
# reports it at skill load.
#
# Usage: bash scripts/lib/preflight-minimum_test.sh
#        /bin/bash scripts/lib/preflight-minimum_test.sh   # the bash 3.2 floor
#
# Every case runs the real entry point, with every helper it sources, against a
# throwaway plugin root and a stand-in koto whose `koto version` line the case
# chooses. The minimum is read from this tree's scripts/assert-koto-floor.sh and
# the stand-in's versions are derived from it, so the cases mean the same thing
# whatever the minimum is:
#
#   at the minimum                zero bytes
#   one patch below it            the block, naming both versions and the route
#   a major above it              zero bytes
#   below it, with a -dev suffix  compared without the suffix
#   an unreadable version line    zero bytes (the known limit)
#   no readable minimum           zero bytes
#   a --mode run whose skill already declares koto `always`   zero bytes
#   a --mode run whose only koto record is that mode          the block
#   several koto records          one block, not one per record
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/../.." && pwd)
BASH_BIN=$(command -v "${PREFLIGHT_TEST_BASH:-${BASH:-bash}}")

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

MINIMUM=$(sed -n 's/^FLOOR="\${KOTO_FLOOR:-\([0-9.]*\)}"$/\1/p' "$REPO/scripts/assert-koto-floor.sh" | head -1)
case "$MINIMUM" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "FAIL: cannot read the koto minimum from scripts/assert-koto-floor.sh" >&2; exit 1 ;;
esac
MAJ=${MINIMUM%%.*}
REST=${MINIMUM#*.}
MIN=${REST%%.*}
PAT=${REST#*.}
if [ "$PAT" -gt 0 ]; then
    BELOW="$MAJ.$MIN.$((PAT - 1))"
elif [ "$MIN" -gt 0 ]; then
    BELOW="$MAJ.$((MIN - 1)).99"
else
    BELOW="$((MAJ - 1)).99.99"
fi
ABOVE="$((MAJ + 1)).0.0"

T=$(mktemp -d "${TMPDIR:-/tmp}/preflight-minimum-test.XXXXXX")
T=$(cd "$T" && pwd -P)
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

# The plugin root: the entry point, every helper, the route table, and the one
# file the minimum is read from.
ROOT="$T/root"
mkdir -p "$ROOT/.claude-plugin" "$ROOT/scripts/lib" "$ROOT/skills"
printf '{"name":"shirabe","version":"0.0.0-test"}\n' >"$ROOT/.claude-plugin/plugin.json"
cp "$REPO/scripts/skill-preflight.sh" "$ROOT/scripts/"
cp "$REPO/scripts/assert-koto-floor.sh" "$ROOT/scripts/"
for f in preflight-read.sh preflight-resolve.sh preflight-probe.sh preflight-report.sh preflight-minimum.sh tool-routes.tsv; do
    cp "$REPO/scripts/lib/$f" "$ROOT/scripts/lib/"
done

# write_decl <skill> <line>...  (\t in a line becomes a tab)
write_decl() {
    local skill="$1" line
    shift
    mkdir -p "$ROOT/skills/$skill"
    printf '#schema\tskill-requires/v1\n' >"$ROOT/skills/$skill/requires.tsv"
    for line in "$@"; do
        printf '%b\n' "$line" >>"$ROOT/skills/$skill/requires.tsv"
    done
}

# stub <version-line>: a koto whose `version` prints the line and whose `--help`
# prints nothing a surface check would read (the declarations below declare no
# surface).
BIN="$T/bin"
mkdir -p "$BIN" "$T/cwd"
# The route table resolves koto's upgrade command through tsuku, so a stand-in
# tsuku is on PATH for the route case to render.
printf '#!/bin/sh\nprintf "usage\\n"\n' >"$BIN/tsuku"
chmod +x "$BIN/tsuku"
stub() {
    {
        printf '#!/bin/sh\n'
        printf 'case "$1" in\n'
        printf '    version) printf "%%s\\n" "%s" ;;\n' "$1"
        printf '    *) printf "usage\\n" ;;\n'
        printf 'esac\n'
    } >"$BIN/koto"
    chmod +x "$BIN/koto"
}

OUT=""
BYTES=0
RC=0
# run <skill> [--mode <m>]
run() {
    RC=0
    OUT=$(cd "$T/cwd" && PATH="$BIN:/usr/bin:/bin" SHIRABE_PREFLIGHT_ROOTS=/nonexistent \
        CLAUDE_PLUGIN_ROOT="$ROOT" "$BASH_BIN" "$ROOT/scripts/skill-preflight.sh" "$@" 2>&1) || RC=$?
    BYTES=${#OUT}
    [ "$RC" -eq 0 ] || fail "the preflight exited $RC; it must exit 0 on every path"
}

flat() { printf '%s' "$OUT" | tr '\n' ' ' | tr -s ' '; }

write_decl kskill 'koto\t-\t-\talways'

stub "koto $MINIMUM (0000000 2026-01-01T00:00:00Z)"
run kskill
[ "$BYTES" -eq 0 ] && pass "koto at the minimum ($MINIMUM) prints zero bytes" \
    || fail "koto at the minimum printed $BYTES bytes: $OUT"

stub "koto $BELOW (0000000 2026-01-01T00:00:00Z)"
run kskill
case "$(flat)" in
    *"shirabe /kskill: prerequisite not met."*"koto $BELOW is installed, and shirabe needs koto $MINIMUM or later."*)
        pass "koto one step below the minimum ($BELOW) prints the block naming both versions" ;;
    *) fail "koto below the minimum did not print the expected block: $OUT" ;;
esac
case "$(flat)" in
    *"tsuku install koto"*) pass "the block carries the upgrade route" ;;
    *) fail "the block carries no upgrade route: $OUT" ;;
esac

stub "koto $ABOVE (0000000 2026-01-01T00:00:00Z)"
run kskill
[ "$BYTES" -eq 0 ] && pass "koto above the minimum ($ABOVE) prints zero bytes" \
    || fail "koto above the minimum printed $BYTES bytes: $OUT"

stub "koto $BELOW-dev (0000000 2026-01-01T00:00:00Z)"
run kskill
case "$(flat)" in
    *"koto $BELOW is installed"*) pass "a -dev suffix is dropped before comparing ($BELOW-dev reads as $BELOW)" ;;
    *) fail "a -dev build below the minimum was not reported as $BELOW: $OUT" ;;
esac

stub "something that is not a version"
run kskill
[ "$BYTES" -eq 0 ] && pass "an unreadable version line prints zero bytes (the known limit)" \
    || fail "an unreadable version line printed $BYTES bytes: $OUT"

# No readable minimum: the floor file is moved aside.
stub "koto $BELOW (0000000 2026-01-01T00:00:00Z)"
mv "$ROOT/scripts/assert-koto-floor.sh" "$T/floor.bak"
run kskill
[ "$BYTES" -eq 0 ] && pass "with no readable minimum the check prints zero bytes" \
    || fail "with no readable minimum the check printed $BYTES bytes: $OUT"
mv "$T/floor.bak" "$ROOT/scripts/assert-koto-floor.sh"

# A --mode run: skipped when load time already covered koto, run otherwise.
write_decl both 'koto\t-\t-\talways' 'koto\t-\t-\tmode:leg'
run both --mode leg
[ "$BYTES" -eq 0 ] && pass "a --mode run skips the minimum when an always record declares koto" \
    || fail "a --mode run repeated the minimum block: $OUT"

write_decl modeonly 'git\t-\t-\talways' 'koto\t-\t-\tmode:leg'
run modeonly --mode leg
case "$(flat)" in
    *"koto $BELOW is installed"*) pass "a --mode run whose only koto record is that mode checks the minimum" ;;
    *) fail "a mode-only koto declaration was not checked: $OUT" ;;
esac

# Several records, one block.
write_decl many 'koto\t-\t-\talways' 'koto\t-\t-\talways' 'koto\t-\t-\talways'
run many
n=$(printf '%s\n' "$OUT" | grep -c 'is installed, and shirabe needs koto')
[ "$n" -eq 1 ] && pass "three koto records print one minimum block" \
    || fail "three koto records printed $n minimum blocks"

echo
echo "preflight-minimum_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
