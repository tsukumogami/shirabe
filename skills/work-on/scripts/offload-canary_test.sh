#!/usr/bin/env bash
# offload-canary_test.sh -- does offload-canary.sh draw a group only when every
# condition holds, split the draws about evenly, keep a session's group once
# drawn, leave PB4 and nothing else out of the withheld rendering, and fall
# back to neither group whenever anything is off?
#
# The script runs against a scratch plugin root, a copy of the real
# rule-registry.sh, references/pr-body-conformance.md and a registry whose
# pr-body/no-heading-in-part1 entry is marked withhold: eligible, so the
# withheld branch can be tested whatever the real registry says. The opt-in file
# lives under a scratch XDG_CONFIG_HOME.
#
# Usage: offload-canary_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SUT="$SCRIPT_DIR/offload-canary.sh"
REAL_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
RULE=pr-body/no-heading-in-part1

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }
[ -x "$SUT" ] || { echo "$SUT is missing or not executable" >&2; exit 2; }

T=$(mktemp -d "${TMPDIR:-/tmp}/offload-canary-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */offload-canary-test.*) rm -rf "$T" ;; esac; return 0; }
ktg_on_exit cleanup

# make_root <dir> <withhold>: a plugin root whose registry gives the rule the
# withhold value named.
make_root() {
    mkdir -p "$1/scripts" "$1/references"
    cp "$REAL_ROOT/scripts/rule-registry.sh" "$1/scripts/rule-registry.sh"
    cp "$REAL_ROOT/references/pr-body-conformance.md" "$1/references/pr-body-conformance.md"
    jq --arg id "$RULE" --arg w "$2" '(.rules[] | select(.id == $id) | .withhold) = $w' \
        "$REAL_ROOT/references/rule-registry.json" > "$1/references/rule-registry.json"
}
ROOT="$T/root"
make_root "$ROOT" eligible
CONF="$ROOT/references/pr-body-conformance.md"

export XDG_CONFIG_HOME="$T/xdg"
mkdir -p "$XDG_CONFIG_HOME/shirabe"
OPTIN="$XDG_CONFIG_HOME/shirabe/offload-canary"
echo on > "$OPTIN"

mkdir -p "$T/s"
# fresh: a new session directory. It runs in a command substitution, so it
# can't keep a counter; mktemp gives each call its own directory.
fresh() { mktemp -d "$T/s/session.XXXXXX"; }
# draw <session-dir> [switch] [shared] [root]: stdout of draw, exit code in RC.
draw() {
    OUT=$("$SUT" draw "${2-on}" "${3-}" "$1" "${4-$ROOT}"); RC=$?
}
arm() { "$SUT" arm "$1"; }
neither() { # neither <label> <session-dir>: the run took no group
    if [ "$RC" -eq 0 ] && [ "$OUT" = "$CONF" ] && [ ! -e "$2/pr-rules/sample" ]; then
        arm "$2"; local a=$?
        [ $a -eq 3 ] && pass "$1: neither group, the real conformance text, arm exits 3" \
            || fail "$1: arm exited $a"
    else
        fail "$1: rc=$RC out=[$OUT] sample=$(cat "$2/pr-rules/sample" 2>/dev/null)"
    fi
}

# --- balance over 200 draws ----------------------------------------------------

W=0; P=0; OTHER=0
i=0
while [ $i -lt 200 ]; do
    d=$(fresh)
    draw "$d"
    arm "$d"
    case $? in
        0) W=$((W + 1)) ;;
        1) P=$((P + 1)) ;;
        *) OTHER=$((OTHER + 1)) ;;
    esac
    i=$((i + 1))
done
if [ $W -ge 70 ] && [ $W -le 130 ] && [ $P -ge 70 ] && [ $P -le 130 ] && [ $OTHER -eq 0 ]; then
    pass "200 draws: $W withheld, $P preloaded, none in neither group"
else
    fail "200 draws: $W withheld, $P preloaded, $OTHER neither"
fi

# --- what each group reads -----------------------------------------------------

WD=""; PD=""
while [ -z "$WD" ] || [ -z "$PD" ]; do
    d=$(fresh)
    draw "$d"
    if arm "$d"; then [ -n "$WD" ] || { WD=$d; WOUT=$OUT; }; else [ -n "$PD" ] || { PD=$d; POUT=$OUT; }; fi
done
[ "$POUT" = "$CONF" ] && pass "a preloaded run reads the real conformance text" \
    || fail "a preloaded run reads [$POUT]"
[ "$WOUT" = "$WD/pr-rules/pr-body-conformance.md" ] && pass "a withheld run reads the session's rendering" \
    || fail "a withheld run reads [$WOUT]"
[ "$(cat "$WD/pr-rules/sample")" = withheld ] && [ "$(cat "$PD/pr-rules/sample")" = preloaded ] \
    && pass "each group is recorded in the session directory" || fail "the sample files"

RANGE=$("$ROOT/scripts/rule-registry.sh" range "$RULE")
A=${RANGE% *}; B=${RANGE#* }
LC_ALL=C awk -v a="$A" -v b="$B" 'NR < a || NR > b' "$CONF" > "$T/want"
cmp -s "$T/want" "$WOUT" && pass "the rendering is the real file with exactly lines $A-$B removed" \
    || fail "the rendering differs from the file minus lines $A-$B"
if grep -qiE 'PB4|heading|no-heading-in-part1' "$WOUT"; then
    fail "the rendering still names PB4 or a heading"
else
    pass "the rendering names neither PB4 nor a heading"
fi
FIRST=$(jq -r --arg id "$RULE" '.rules[] | select(.id == $id) | .text.first' "$ROOT/references/rule-registry.json")
grep -qF -- "$FIRST" "$WOUT" && fail "the rendering holds PB4's first anchor" \
    || pass "the rendering does not hold PB4's first anchor"

# --- a session keeps its group ---------------------------------------------------

same=0
i=0
while [ $i -lt 20 ]; do
    draw "$WD"; [ "$OUT" = "$WOUT" ] && arm "$WD" && same=$((same + 1))
    draw "$PD"; [ "$OUT" = "$CONF" ] && { arm "$PD"; [ $? -eq 1 ]; } && same=$((same + 1))
    i=$((i + 1))
done
[ $same -eq 40 ] && pass "a second draw reads the recorded group back, 20 times out of 20 per group" \
    || fail "a second draw changed the group ($same of 40 kept)"

# --- neither group -------------------------------------------------------------------

d=$(fresh); draw "$d" off; neither "OFFLOAD_CANARY off" "$d"
d=$(fresh); draw "$d" on impl/plan; neither "a shared branch" "$d"
d=$(fresh); draw "$d" maybe; neither "a switch value other than on" "$d"

mv "$OPTIN" "$T/optin.saved"
d=$(fresh); draw "$d"; neither "no opt-in file" "$d"
echo off > "$OPTIN"
d=$(fresh); draw "$d"; neither "an opt-in file reading off" "$d"
printf '' > "$OPTIN"
d=$(fresh); draw "$d"; neither "an empty opt-in file" "$d"
rm -f "$OPTIN"; ln -s "$T/optin.saved" "$OPTIN"
d=$(fresh); draw "$d"; neither "a symlinked opt-in file" "$d"
rm -f "$OPTIN"; mv "$T/optin.saved" "$OPTIN"

NEVER="$T/never"; make_root "$NEVER" never
d=$(fresh); draw "$d" on "" "$NEVER"
[ "$OUT" = "$NEVER/references/pr-body-conformance.md" ] && [ ! -e "$d/pr-rules/sample" ] \
    && pass "the rule marked withhold: never: neither group" || fail "never: out=[$OUT]"

NOREG="$T/noreg"; make_root "$NOREG" eligible; rm -f "$NOREG/references/rule-registry.json"
d=$(fresh); draw "$d" on "" "$NOREG"
[ "$RC" -eq 0 ] && [ "$OUT" = "$NOREG/references/pr-body-conformance.md" ] && [ ! -e "$d/pr-rules/sample" ] \
    && pass "a missing registry: neither group, exit 0" || fail "missing registry: rc=$RC out=[$OUT]"

# A first anchor moved out of the rendering's reach: the range still resolves,
# but a rendering that names PB4 is refused.
LEAK="$T/leak"; make_root "$LEAK" eligible
printf '\nA note that mentions PB4 outside its paragraph.\n' >> "$LEAK/references/pr-body-conformance.md"
leak_w=0; leak_n=0
i=0
while [ $i -lt 20 ]; do
    d=$(fresh); draw "$d" on "" "$LEAK"
    if [ -e "$d/pr-rules/sample" ] && [ "$(cat "$d/pr-rules/sample")" = withheld ]; then leak_w=$((leak_w + 1)); fi
    [ "$OUT" = "$LEAK/references/pr-body-conformance.md" ] || leak_n=$((leak_n + 1))
    i=$((i + 1))
done
[ $leak_w -eq 0 ] && [ $leak_n -eq 0 ] && pass "a rendering that would still name PB4 is never used, and no run is labeled withheld" \
    || fail "a leaky rendering: $leak_w withheld labels, $leak_n runs read a rendering"

# A registry whose text resolves in another file: the range it gives is that
# file's, so its first line here isn't PB4's, and the draw refuses to cut.
MOVED="$T/moved"; make_root "$MOVED" eligible
{ echo "An extra first line that shifts every line below it."; cat "$MOVED/references/pr-body-conformance.md"; } \
    > "$MOVED/references/other.md"
jq --arg id "$RULE" '(.rules[] | select(.id == $id) | .text.path) = "references/other.md"' \
    "$MOVED/references/rule-registry.json" > "$T/moved.json" && mv "$T/moved.json" "$MOVED/references/rule-registry.json"
moved_w=0
i=0
while [ $i -lt 20 ]; do
    d=$(fresh); draw "$d" on "" "$MOVED"
    if [ -e "$d/pr-rules/sample" ] && [ "$(cat "$d/pr-rules/sample")" = withheld ]; then moved_w=$((moved_w + 1)); fi
    i=$((i + 1))
done
[ $moved_w -eq 0 ] && pass "a range whose first line here isn't PB4's first line is never cut" \
    || fail "a mismatched range was cut in $moved_w draws"

# The real plugin root: the registry marks PB4 eligible, so an opted-in draw
# takes a group.
real_group=0
i=0
while [ $i -lt 6 ] && [ $real_group -eq 0 ]; do
    d=$(fresh); draw "$d" on "" "$REAL_ROOT"
    [ -e "$d/pr-rules/sample" ] && real_group=1
    i=$((i + 1))
done
[ $real_group -eq 1 ] && pass "against the real plugin root an opted-in draw takes a group" \
    || fail "against the real plugin root no draw took a group (is PB4 eligible?)"

# --- symlinks and unwritable directories ----------------------------------------------

d=$(fresh); ln -s "$T/s" "$T/linked-session"
draw "$T/linked-session"; neither "a symlinked session directory" "$T/linked-session"
d=$(fresh); mkdir -p "$T/elsewhere"; ln -s "$T/elsewhere" "$d/pr-rules"
draw "$d"
[ "$OUT" = "$CONF" ] && [ ! -e "$T/elsewhere/sample" ] && pass "a symlinked pr-rules directory: neither group, nothing written through it" \
    || fail "symlinked pr-rules: out=[$OUT]"
d=$(fresh); mkdir -p "$d/pr-rules"; ln -s "$T/target-sample" "$d/pr-rules/sample"; echo withheld > "$T/target-sample"
draw "$d"
[ "$OUT" = "$CONF" ] && { arm "$d"; [ $? -eq 3 ]; } && pass "a symlinked sample file is not read back as a group" \
    || fail "symlinked sample: out=[$OUT]"
d=$(fresh); chmod 500 "$d"
draw "$d"
chmod 700 "$d"
[ "$RC" -eq 0 ] && [ "$OUT" = "$CONF" ] && pass "an unwritable session directory: neither group, exit 0" \
    || fail "unwritable: rc=$RC out=[$OUT]"
draw "$T/does-not-exist"
[ "$RC" -eq 0 ] && [ "$OUT" = "$CONF" ] && pass "a missing session directory: neither group, exit 0" \
    || fail "missing session dir: rc=$RC out=[$OUT]"

# --- the guide's off switch ---------------------------------------------------------------

# The guide tells a maintainer which line turns the canary off. That line must
# be the template's: OFFLOAD_CANARY's default, quoted in the guide's yaml block.
TEMPLATE_DEFAULT=$(awk '/^  OFFLOAD_CANARY:$/ { f = 1; next } f && /^    default: / { print; exit } f && /^  [A-Z_]+:$/ { exit }' \
    "$REAL_ROOT/skills/work-on/koto-templates/work-on.md")
GUIDE="$REAL_ROOT/docs/guides/offload-live-canary.md"
if [ -n "$TEMPLATE_DEFAULT" ] && grep -qxF -- "$TEMPLATE_DEFAULT" "$GUIDE" \
    && grep -qF 'under `OFFLOAD_CANARY:`' "$GUIDE"; then
    pass "the guide quotes the template's OFFLOAD_CANARY default line ($TEMPLATE_DEFAULT)"
else
    fail "the guide's off-switch line doesn't match the template's [$TEMPLATE_DEFAULT]"
fi

# --- the one-line contract -------------------------------------------------------------

d=$(fresh)
LINES=$("$SUT" draw on "" "$d" "$ROOT" | wc -l | tr -d ' ')
[ "$LINES" = 1 ] && pass "draw prints exactly one line" || fail "draw printed $LINES lines"
"$SUT" bogus >/dev/null 2>&1; rc=$?
[ $rc -eq 64 ] && pass "an unknown subcommand exits 64" || fail "unknown subcommand exited $rc"
"$SUT" arm >/dev/null 2>&1; rc=$?
[ $rc -eq 3 ] && pass "arm with no session directory exits 3" || fail "arm with no argument exited $rc"

echo
echo "offload-canary_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
