#!/usr/bin/env bash
# takeover-flags_test.sh -- testdata/takeover-flags.sh, against a stand-in
# koto whose `init --help` lists the takeover flags or doesn't.
#
# Covers: a koto listing --continues and --supersede sets TAKEOVER_FLAGS=1 and
# needs_takeover returns 0 printing nothing; a koto listing neither (the floor's
# shape), one listing --continues alone and one whose --help fails set 0, and
# there needs_takeover returns 1 and prints a line naming the case that doesn't
# start with SKIP, counting each case left out; `koto init --help` is read once
# however many cases a suite declares.
#
# Usage: bash skills/coordinate/scripts/takeover-flags_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
TF="$HERE/testdata/takeover-flags.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/takeover-flags.XXXXXX") || exit 1
trap 'case "$T" in */takeover-flags.*) rm -rf "$T" ;; esac' EXIT
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

# The stand-in koto prints $T/help for `init --help`, exits $T/rc, and logs
# every call to $T/calls.
mkdir -p "$T/bin"
cat > "$T/bin/koto" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
[ "\$*" = "init --help" ] && cat "$T/help"
exit \$(cat "$T/rc")
EOF
chmod +x "$T/bin/koto"
PATH="$T/bin:$PATH"

CURRENT='      --continues <PRED>            Record that this session continues session PRED
      --continues-from <WORKSPACE>  The workspace PRED lives in
      --supersede                   Take PRED'"'"'s work over: fence PRED'
FLOOR='      --template <TEMPLATE>         Path to template file
      --var <KEY=VALUE>             Set a template variable (repeatable)'
CONTINUES_ONLY='      --continues <PRED>            Record that this session continues session PRED'

# run <help> <rc> <script>: source the helper in a fresh shell against that
# --help, then run the script there; prints what the script prints.
run() {
    printf '%s\n' "$1" > "$T/help"; printf '%s\n' "$2" > "$T/rc"; : > "$T/calls"
    bash -c '. "$1"; eval "$2"' _ "$TF" "$3"
}

echo "== a koto with the takeover flags =="
eq "TAKEOVER_FLAGS is 1" 1 "$(run "$CURRENT" 0 'echo $TAKEOVER_FLAGS')"
eq "needs_takeover returns 0 and prints nothing" "rc=0 out=" \
    "$(run "$CURRENT" 0 'o=$(needs_takeover "1: a case"); echo "rc=$? out=$o"')"
eq "  ... and leaves nothing out" 0 "$(run "$CURRENT" 0 'needs_takeover "1: a case"; echo $TAKEOVER_LEFT_OUT')"

echo "== the floor's koto, with neither flag =="
eq "TAKEOVER_FLAGS is 0" 0 "$(run "$FLOOR" 0 'echo $TAKEOVER_FLAGS')"
eq "needs_takeover returns 1" 1 "$(run "$FLOOR" 0 'needs_takeover "1: a case" >/dev/null; echo $?')"
OUT=$(run "$FLOOR" 0 'needs_takeover "3: past the hop cap"')
eq "  ... printing a line naming the case" "left out 3: past the hop cap: this koto has no init --continues or --supersede" "$OUT"
case "$OUT" in SKIP*) bad "  ... that run-tests.sh --engine doesn't read as a SKIP" "$OUT" ;; *) ok "  ... that run-tests.sh --engine doesn't read as a SKIP" ;; esac
eq "  ... and counting each case left out" "2" \
    "$(run "$FLOOR" 0 'needs_takeover a >/dev/null; needs_takeover b >/dev/null; echo $TAKEOVER_LEFT_OUT')"
eq "a suite can end on the line that declares the rest" "left out 4-7: the rest: this koto has no init --continues or --supersede|ended" \
    "$(run "$FLOOR" 0 'needs_takeover "4-7: the rest" || { echo "|ended"; exit 0; }; echo "|ran on"' | tr -d '\n')"

echo "== --continues alone, and a --help that fails =="
eq "--continues without --supersede is 0" 0 "$(run "$CONTINUES_ONLY" 0 'echo $TAKEOVER_FLAGS')"
eq "a --help that fails, printing nothing, is 0" 0 "$(run "" 2 'echo $TAKEOVER_FLAGS')"

echo "== --help is read once =="
run "$CURRENT" 0 'needs_takeover a; needs_takeover b; needs_takeover c' >/dev/null
eq "three cases, one koto init --help" "init --help" "$(cat "$T/calls")"
run "$FLOOR" 0 'needs_takeover a; needs_takeover b; needs_takeover c' >/dev/null
eq "  ... on the floor's koto too" "init --help" "$(cat "$T/calls")"

echo; echo "takeover-flags: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
