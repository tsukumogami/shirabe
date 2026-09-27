#!/usr/bin/env bash
# preflight-minimum_test.sh -- the koto minimum, as scripts/skill-preflight.sh
# reports it at skill load.
#
# Usage: bash scripts/lib/preflight-minimum_test.sh
#        /bin/bash scripts/lib/preflight-minimum_test.sh   # the bash 3.2 floor
#
# Every case runs the real entry point, with every helper it sources, against a
# throwaway plugin root and a stand-in koto whose `koto version` output the case
# chooses. Two floors:
#
#   the tree's own scripts/assert-koto-floor.sh, in one case, so the real FLOOR
#   line is proven readable and the check silent at it;
#
#   a fixture floor of 0.14.0 written into the root for every other case, so
#   the comparisons are fixed: 0.9.0 is below it and 0.100.0 above it, which a
#   string comparison gets wrong both ways.
#
# Cases:
#   at the tree's own minimum                  zero bytes
#   0.14.0 / 0.100.0 / 1.0.0 / v0.14.0         zero bytes
#   0.13.99 / 0.9.0                            the below-minimum block, with the route
#   0.14.0-dev+abc1234 / 0.13.0-dev+abc1234    compared as 0.14.0 / 0.13.0
#   dev+abc1234 (an untagged build)            the version-unreadable block
#   `koto version` exits 2 with no output      the version-unreadable block
#   `koto version` hangs past the budget       zero bytes, within the budget
#   a component longer than six digits         the version-unreadable block
#   no readable minimum                        zero bytes
#   koto absent                                the absent block only
#   a --mode run load time already covered     zero bytes
#   a --mode run whose only koto record is it  the block
#   three koto records                         one block
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

REAL_MINIMUM=$(sed -n 's/^FLOOR="\${KOTO_FLOOR:-\([0-9.]*\)}"$/\1/p' "$REPO/scripts/assert-koto-floor.sh" | head -1)
case "$REAL_MINIMUM" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "FAIL: cannot read the koto minimum from scripts/assert-koto-floor.sh" >&2; exit 1 ;;
esac

T=$(mktemp -d "${TMPDIR:-/tmp}/preflight-minimum-test.XXXXXX")
T=$(cd "$T" && pwd -P)
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

ROOT="$T/root"
mkdir -p "$ROOT/.claude-plugin" "$ROOT/scripts/lib" "$ROOT/skills"
printf '{"name":"shirabe","version":"0.0.0-test"}\n' >"$ROOT/.claude-plugin/plugin.json"
cp "$REPO/scripts/skill-preflight.sh" "$ROOT/scripts/"
for f in preflight-read.sh preflight-resolve.sh preflight-probe.sh preflight-report.sh preflight-minimum.sh tool-routes.tsv; do
    cp "$REPO/scripts/lib/$f" "$ROOT/scripts/lib/"
done

real_floor()    { cp "$REPO/scripts/assert-koto-floor.sh" "$ROOT/scripts/assert-koto-floor.sh"; }
fixture_floor() { printf 'FLOOR="${KOTO_FLOOR:-0.14.0}"\n' >"$ROOT/scripts/assert-koto-floor.sh"; }

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

BIN="$T/bin"
mkdir -p "$BIN" "$T/cwd" "$T/nokoto"
# The route table resolves koto's upgrade command through tsuku, so a stand-in
# tsuku is on PATH for the route to render.
printf '#!/bin/sh\nprintf "usage\\n"\n' >"$BIN/tsuku"
chmod +x "$BIN/tsuku"
cp "$BIN/tsuku" "$T/nokoto/tsuku"

# stub <version-output> [exit-code] -- a koto whose `version` prints the given
# text (nothing when empty) and exits with the given code. `hang` sleeps
# instead. `--help` prints nothing a surface check would read: the declarations
# below declare no surface.
stub() {
    {
        printf '#!/bin/sh\n'
        printf 'case "$1" in\n'
        if [ "$1" = hang ]; then
            printf '    version) exec sleep 30 ;;\n'
        elif [ -n "$1" ]; then
            printf '    version) printf "%%s\\n" "%s"; exit %s ;;\n' "$1" "${2:-0}"
        else
            printf '    version) exit %s ;;\n' "${2:-0}"
        fi
        printf '    *) printf "usage\\n" ;;\n'
        printf 'esac\n'
    } >"$BIN/koto"
    chmod +x "$BIN/koto"
}

OUT=""
BYTES=0
RC=0
# run <path-dir> <skill> [--mode <m>]
run() {
    local dir="$1"
    shift
    RC=0
    OUT=$(cd "$T/cwd" && PATH="$dir:/usr/bin:/bin" SHIRABE_PREFLIGHT_ROOTS=/nonexistent \
        SHIRABE_PREFLIGHT_BUDGET=1 CLAUDE_PLUGIN_ROOT="$ROOT" \
        "$BASH_BIN" "$ROOT/scripts/skill-preflight.sh" "$@" 2>&1) || RC=$?
    BYTES=${#OUT}
    [ "$RC" -eq 0 ] || fail "the preflight exited $RC; it must exit 0 on every path"
}

flat() { printf '%s' "$OUT" | tr '\n' ' ' | tr -s ' '; }

silent() { # silent <label>
    if [ "$BYTES" -eq 0 ]; then pass "$1"; else fail "$1: printed $BYTES bytes: $OUT"; fi
}
below() { # below <label> <installed>
    case "$(flat)" in
        *"prerequisite not met."*"koto $2 is installed. shirabe's skills are tested on koto 0.14.0 and later"*"Upgrade koto to 0.14.0 or later before running /kskill."*)
            pass "$1" ;;
        *) fail "$1: expected the below-minimum block for $2: $OUT" ;;
    esac
}
unreadable() { # unreadable <label>
    case "$(flat)" in
        *"prerequisite could not be checked."*"\`koto version\` printed no version this check can read"*"minimum, 0.14.0, was not established"*)
            pass "$1" ;;
        *) fail "$1: expected the version-unreadable block: $OUT" ;;
    esac
}

write_decl kskill 'koto\t-\t-\talways'

# The tree's own FLOOR line reads, and a koto at it is silent.
real_floor
stub "koto $REAL_MINIMUM (0000000 2026-01-01T00:00:00Z)"
run "$BIN" kskill
silent "koto at the tree's own minimum ($REAL_MINIMUM) prints zero bytes"

fixture_floor

for v in 0.14.0 0.100.0 1.0.0; do
    stub "koto $v (0000000 2026-01-01T00:00:00Z)"
    run "$BIN" kskill
    silent "koto $v against a 0.14.0 minimum prints zero bytes"
done
stub "koto v0.14.0 (0000000 2026-01-01T00:00:00Z)"
run "$BIN" kskill
silent "a leading v is accepted: koto v0.14.0 prints zero bytes"

stub "koto 0.13.99 (0000000 2026-01-01T00:00:00Z)"
run "$BIN" kskill
below "koto 0.13.99 against 0.14.0 prints the below-minimum block" 0.13.99
case "$(flat)" in
    *"tsuku install koto"*) pass "the below-minimum block carries the upgrade route" ;;
    *) fail "the below-minimum block carries no upgrade route: $OUT" ;;
esac

stub "koto 0.9.0 (0000000 2026-01-01T00:00:00Z)"
run "$BIN" kskill
below "koto 0.9.0 is below 0.14.0 (numeric, not string, comparison)" 0.9.0

stub "koto 0.14.0-dev+abc1234 (abc1234 2026-01-01T00:00:00Z)"
run "$BIN" kskill
silent "a build ahead of tag v0.14.0 (0.14.0-dev+abc1234) compares as 0.14.0"

stub "koto 0.13.0-dev+abc1234 (abc1234 2026-01-01T00:00:00Z)"
run "$BIN" kskill
below "a build ahead of tag v0.13.0 (0.13.0-dev+abc1234) compares as 0.13.0" 0.13.0

stub "koto dev+abc1234 (abc1234 2026-01-01T00:00:00Z)"
run "$BIN" kskill
unreadable "an untagged build (dev+abc1234) gets the version-unreadable block"

stub "" 2
run "$BIN" kskill
unreadable "koto version exiting 2 with no output gets the version-unreadable block"

stub "koto 1234567.0.0 (0000000 2026-01-01T00:00:00Z)"
run "$BIN" kskill
unreadable "a component longer than six digits is not read as a version"

stub hang
start=$(date +%s)
run "$BIN" kskill
elapsed=$(( $(date +%s) - start ))
if [ "$elapsed" -le 5 ]; then
    pass "a hung koto version is cut off by the budget (${elapsed}s)"
else
    fail "a hung koto version held the preflight for ${elapsed}s"
fi
silent "a hung koto version prints zero bytes (the surface probe reports the same binary)"

# No readable minimum.
stub "koto 0.9.0 (0000000 2026-01-01T00:00:00Z)"
rm -f "$ROOT/scripts/assert-koto-floor.sh"
run "$BIN" kskill
silent "with no readable minimum the check prints zero bytes"
fixture_floor

# koto absent: the absent block, and no minimum block.
run "$T/nokoto" kskill
case "$(flat)" in
    *"koto is not installed on this host"*) pass "an absent koto gets the absent block" ;;
    *) fail "an absent koto did not get the absent block: $OUT" ;;
esac
case "$(flat)" in
    *"shirabe's skills are tested on"*|*"printed no version"*) fail "an absent koto also got a minimum block: $OUT" ;;
    *) pass "an absent koto gets no minimum block" ;;
esac

# A --mode run: skipped when load time covered koto, made otherwise.
stub "koto 0.9.0 (0000000 2026-01-01T00:00:00Z)"
write_decl both 'koto\t-\t-\talways' 'koto\t-\t-\tmode:leg'
run "$BIN" both --mode leg
silent "a --mode run skips the minimum when an always record declares koto"

write_decl modeonly 'git\t-\t-\talways' 'koto\t-\t-\tmode:leg'
cp "$BIN/tsuku" "$BIN/git"
run "$BIN" modeonly --mode leg
case "$(flat)" in
    *"koto 0.9.0 is installed"*) pass "a --mode run whose only koto record is that mode checks the minimum" ;;
    *) fail "a mode-only koto declaration was not checked: $OUT" ;;
esac

write_decl many 'koto\t-\t-\talways' 'koto\t-\t-\talways' 'koto\t-\t-\talways'
run "$BIN" many
n=$(printf '%s\n' "$OUT" | grep -c 'is installed. shirabe')
[ "$n" -eq 1 ] && pass "three koto records print one minimum block" \
    || fail "three koto records printed $n minimum blocks"

echo
echo "preflight-minimum_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
