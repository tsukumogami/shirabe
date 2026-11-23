#!/usr/bin/env bash
# issue-type-route_test.sh -- issue-type-route.sh against a koto stand-in.
#
# issue_type_routing's code_route gate: exit 0 takes the code route on entry
# with nothing asked, exit 1 leaves the question to the agent. Covers:
#
#   code       a code hint and a script path; a code hint and a SKILL.md
#              (instruction as well as docs); a rename whose new side is code
#   ask        a code hint and only docs/*.md and README.md; a docs hint and a
#              task hint over a script path; no changed_paths.txt; a
#              changed_paths.txt with headers and no path lines; a read koto
#              refuses
#   bad args   a missing argument, an extra one, a bad session name: each
#              asks (exit 1, a `route: ask` line), since the gate's edges
#              name only 0 and 1
#
# The real review-level.sh classifies, from the shipped rules file.
#
# Usage: bash skills/work-on/scripts/issue-type-route_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/issue-type-route.sh"

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "[$3] lacks [$2]" ;; esac; }

W=$(mktemp -d) || { echo "FAIL: could not create a temporary directory"; exit 1; }
ktg_on_exit 'rm -rf "$W"'
export HOME="$W/home"
mkdir -p "$HOME"

# koto: context exists|get <s> <key>  files under $SHIM_STORE/<s>;
#       SHIM_FAIL_GET=1 fails every get
BIN="$W/bin"
STORE="$W/store"
mkdir -p "$BIN" "$STORE"
cat > "$BIN/koto" <<'SHIM'
#!/usr/bin/env bash
[ "$1" = context ] || { echo "shim: unsupported $*" >&2; exit 2; }
f="$SHIM_STORE/$3/$4"
case "$2" in
    exists) [ -f "$f" ] ;;
    get) [ -z "${SHIM_FAIL_GET:-}" ] || { echo "shim: refused" >&2; exit 2; }
         [ -f "$f" ] || exit 1; cat "$f" ;;
    *) echo "shim: unsupported $*" >&2; exit 2 ;;
esac
SHIM
chmod +x "$BIN/koto"
export SHIM_STORE="$STORE"

OUT="" RC=0
run() {
    OUT=$(PATH="$BIN:$PATH" bash "$SCRIPT" "$@" 2>"$W/err")
    RC=$?
}
# paths <session> <line>...: a changed_paths.txt with its two header lines.
paths() {
    local s=$1
    shift
    mkdir -p "$STORE/$s"
    { printf 'base: abc123\ncommits: 2\n'; printf '%s\n' "$@"; } > "$STORE/$s/changed_paths.txt"
}
T=$(printf '\t')

# --- code, from the facts --------------------------------------------------------
paths c1 "M${T}scripts/build.sh" "M${T}docs/guide.md"
run c1 code
eq "a code hint and a script path: exit 0" 0 "$RC"
has "a code hint and a script path: names the path" "route: code (scripts/build.sh is not documentation)" "$OUT"

paths c2 "M${T}skills/x/SKILL.md"
run c2 code
eq "a code hint and a SKILL.md: exit 0" 0 "$RC"

paths c3 "R100${T}docs/old.md${T}scripts/new.sh"
run c3 code
eq "a rename whose new side is code: exit 0" 0 "$RC"
has "a rename whose new side is code: names the new side" "scripts/new.sh" "$OUT"

# --- the agent is asked ------------------------------------------------------------
paths a1 "M${T}docs/guide.md" "A${T}docs/designs/DESIGN-x.md" "M${T}README.md"
run a1 code
eq "a code hint and only docs/*.md and README.md: exit 1" 1 "$RC"
has "documentation only: says so" "every changed path is documentation" "$OUT"

paths a2 "M${T}scripts/build.sh"
run a2 docs
eq "a docs hint over a script path: exit 1" 1 "$RC"
has "a docs hint: names the hint" "the type hint is docs" "$OUT"
run a2 task
eq "a task hint over a script path: exit 1" 1 "$RC"
run a2 ""
eq "an empty hint: exit 1" 1 "$RC"

mkdir -p "$STORE/a3"
run a3 code
eq "no changed_paths.txt: exit 1" 1 "$RC"
has "no changed_paths.txt: says so" "no changed_paths.txt recorded" "$OUT"

paths a4
run a4 code
eq "headers and no path lines: exit 1" 1 "$RC"
has "headers and no path lines: says so" "no changed paths" "$OUT"

SHIM_FAIL_GET=1 run a2 code
eq "a read koto refuses: exit 1" 1 "$RC"

# --- bad arguments ask -----------------------------------------------------------
# asks <label>: the last run exited 1 with a `route: ask` line.
asks() {
    eq "$1: exit 1" 1 "$RC"
    has "$1: a route: ask line" "route: ask" "$OUT"
}
run c1
asks "a missing hint"
run
asks "no arguments"
run c1 code extra
asks "an extra argument"
run "bad name" code
asks "a bad session name"
run -x code
asks "a session name that looks like a flag"

echo
echo "issue-type-route: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
