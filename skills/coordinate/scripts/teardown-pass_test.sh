#!/usr/bin/env bash
# teardown-pass_test.sh -- the pass's own checks on the fields it builds
# commands from.
#
# A sealed verdict can't carry a bad instance name: teardown-handoff.sh
# refuses one when it seals (teardown-pass_engine_test.sh covers that). The
# pass still checks every field it builds a command from, so a verdict that
# somehow carried one would stop there. This feeds such verdicts straight to
# `teardown-pass.sh run` through a stand-in for `teardown-handoff.sh read`,
# and asserts each is refused before any niwa, claude or gh command runs.
#
# Usage: bash skills/coordinate/scripts/teardown-pass_test.sh
# Exit codes: 0 all pass; 1 a failure. bash 3.2.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/teardown-pass-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

# The plugin tree: the pass and its library, with a stand-in reader that
# prints whatever verdict the case put in $T/verdict.
S="$T/plugin/skills/coordinate/scripts"
mkdir -p "$S" "$T/bin" "$T/ws/.niwa"
cp "$HERE/teardown-pass.sh" "$HERE/dispatch-common.sh" "$S/"
cat >"$S/teardown-handoff.sh" <<'EOF'
#!/usr/bin/env bash
cat "$VERDICT_FILE"
EOF
# Every tool the pass could run past its checks logs and fails.
for tool in niwa claude gh koto; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\nexit 97\n' "$tool" "$T" >"$T/bin/$tool"
done
chmod +x "$S"/*.sh "$T/bin"/*
: >"$T/ws/.niwa/workspace.toml"
: >"$T/ws/.niwa/instance.json"
export VERDICT_FILE="$T/verdict" PATH="$T/bin:$PATH" HOME="$T/home"
mkdir -p "$HOME"

KS=keyseal:7:0000000000000000000000000000000000000000000000000000000000000000
# verdict <name> <path> <job> <session>: a ready verdict with those fields.
verdict() {
    printf 'topic w5\ninstance %s %s\njob %s %s\ntranscript /t/x.jsonl\npr acme/widgets#600 %s\nhandoff https://github.com/acme/widgets/pull/600#issuecomment-1\ninventory sealed:1:%s\nkeyseal %s\n' \
        "$1" "$2" "$3" "$4" 0123456789012345678901234567890123456789 "${KS#keyseal:7:}" "$KS" >"$VERDICT_FILE"
}
# refused <label> <reason>: the pass refuses the verdict with the reason and runs nothing.
refused() {
    : >"$T/calls"
    out=$(cd "$T/ws" && bash "$S/teardown-pass.sh" run --session s --keyseal "$KS" 2>&1)
    rc=$?
    [ "$rc" = 1 ] && ok "$1: refused" || bad "$1: refused" "exit $rc: $out"
    case "$out" in *"$2"*) ok "$1: says why" ;; *) bad "$1: says why" "$out" ;; esac
    [ -s "$T/calls" ] && bad "$1: no tool runs" "$(cat "$T/calls")" || ok "$1: no tool runs"
}

verdict --workspace /i/w5 4b3597d2 4b3597d2-6184-4a48
refused "an instance name that starts with a dash" "instance name is not a plain name"
verdict '' /i/w5 4b3597d2 4b3597d2-6184-4a48
refused "an empty instance name" "instance name is not a plain name"
verdict 'tsuku w5' /i/w5 4b3597d2 4b3597d2-6184-4a48
refused "an instance name with a space" "instance path is not absolute"
verdict tsuku+w5 relative/w5 4b3597d2 4b3597d2-6184-4a48
refused "a relative instance path" "instance path is not absolute"
verdict tsuku+w5 /i/w5 ';rm' 4b3597d2-6184-4a48
refused "a job id that isn't one" "job id is not a job id"
verdict tsuku+w5 /i/w5 4b3597d2 'x y'
refused "a session id that isn't one" "session id is not a session id"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
