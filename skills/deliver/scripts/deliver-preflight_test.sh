#!/usr/bin/env bash
# deliver-preflight_test.sh -- /deliver's repository binding: Public passes;
# Private, a missing header, an unknown value, and no work tree are refused.
#
# Usage: bash skills/deliver/scripts/deliver-preflight_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs bash and git.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/deliver-preflight.sh"
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/deliver-preflight-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"

PASS=0
FAIL=0
check() { # check <label> <want-rc> <dir>
    local rc
    (cd "$3" && bash "$S" >/dev/null 2>"$T/err")
    rc=$?
    if [ "$rc" = "$2" ]; then PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; else FAIL=$((FAIL + 1)); printf 'FAIL %s\n     want %s, got %s: %s\n' "$1" "$2" "$rc" "$(cat "$T/err")"; fi
}
repo() { # repo <name> [CLAUDE.md content] [CLAUDE.local.md content]
    local r="$T/$1"
    git init -q "$r"
    [ -n "${2:-}" ] && printf '%s\n' "$2" >"$r/CLAUDE.md"
    [ -n "${3:-}" ] && printf '%s\n' "$3" >"$r/CLAUDE.local.md"
    printf '%s' "$r"
}

check "Public passes" 0 "$(repo pub "# x

## Repo Visibility: Public")"
check "public in any case passes" 0 "$(repo pub2 "## Repo Visibility: public")"
check "Private is refused (exit 1)" 1 "$(repo priv "## Repo Visibility: Private")"
check "no header is refused as unknown (exit 2)" 2 "$(repo none "# x")"
check "no CLAUDE.md is refused as unknown" 2 "$(repo nofile)"
check "an unknown value is refused as unknown" 2 "$(repo odd "## Repo Visibility: Internal")"
check "a value with trailing prose is not Public" 2 "$(repo prose "## Repo Visibility: Public, mostly")"
check "a header only in the body text is not a header" 2 "$(repo body "Repo Visibility: Public")"
check "CLAUDE.local.md is read when CLAUDE.md declares nothing" 0 "$(repo local "# x" "## Repo Visibility: Public")"
check "CLAUDE.md wins over CLAUDE.local.md" 1 "$(repo both "## Repo Visibility: Private" "## Repo Visibility: Public")"
check "the first header wins" 1 "$(repo twice "## Repo Visibility: Private
## Repo Visibility: Public")"
R=$(repo sub "## Repo Visibility: Public")
mkdir -p "$R/a/b"
check "run from a subdirectory, the work-tree root's CLAUDE.md is read" 0 "$R/a/b"
mkdir -p "$T/plain"
check "outside a git work tree is refused as unknown" 2 "$T/plain"

(cd "$T/pub" && bash "$S" extra >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 64 ]; then PASS=$((PASS + 1)); echo "ok   an argument is a usage error"; else FAIL=$((FAIL + 1)); echo "FAIL usage: rc=$rc"; fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
