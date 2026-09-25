#!/usr/bin/env bash
# check-upstream_test.sh -- every output check-upstream.sh can produce.
#
# Usage: bash skills/scope/scripts/check-upstream_test.sh
# Exit 0 when every case holds. Needs bash and git; runs on the 3.2 floor.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/check-upstream.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/check-upstream-test.XXXXXX")"
T="$(cd -P "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
# The scratch directory may itself sit inside a checkout (TMPDIR pointed into
# one); stop git's discovery at it so "outside any work tree" means that.
export GIT_CEILING_DIRECTORIES="$T"

command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }

PASS=0
FAIL=0

# expect <label> <want-exit> <want-stdout> <dir> <args...>
expect() {
    local label="$1" want_rc="$2" want_out="$3" dir="$4" out rc
    shift 4
    out=$(cd "$dir" && bash "$S" "$@" 2>/dev/null); rc=$?
    if [ "$rc" = "$want_rc" ] && [ "$out" = "$want_out" ]; then
        PASS=$((PASS + 1)); printf 'ok   %s\n' "$label"
    else
        FAIL=$((FAIL + 1)); printf 'FAIL %s\n     want exit=%s out=[%s], got exit=%s out=[%s]\n' "$label" "$want_rc" "$want_out" "$rc" "$out"
    fi
}

R="$T/repo"
mkdir -p "$R/docs/roadmaps/sub" "$R/docs/other" "$R/wip" "$T/elsewhere" "$T/plain"
git -C "$R" init -q
printf 'r\n' >"$R/docs/roadmaps/ROADMAP-good.md"
printf 'r\n' >"$R/docs/roadmaps/sub/ROADMAP-nested.md"
printf 'r\n' >"$R/docs/roadmaps/notes.md"
printf 'r\n' >"$R/docs/other/ROADMAP-other.md"
printf 'r\n' >"$R/wip/ROADMAP-scratch.md"
printf 'r\n' >"$T/elsewhere/ROADMAP-far.md"
git -C "$R" add docs wip
printf 'r\n' >"$R/docs/roadmaps/ROADMAP-untracked.md"
ln -s ../../wip/ROADMAP-scratch.md "$R/docs/roadmaps/ROADMAP-intowip.md"
ln -s ../other/ROADMAP-other.md "$R/docs/roadmaps/ROADMAP-sideways.md"
ln -s notes.md "$R/docs/roadmaps/ROADMAP-renamed.md"
ln -s "$T/elsewhere/ROADMAP-far.md" "$R/docs/roadmaps/ROADMAP-away.md"
git -C "$R" add docs/roadmaps/ROADMAP-intowip.md docs/roadmaps/ROADMAP-sideways.md \
    docs/roadmaps/ROADMAP-renamed.md docs/roadmaps/ROADMAP-away.md

echo "== passes (exit 0, nothing on stdout) =="
expect "an empty value"                            0 "" "$R" --upstream ""
expect "a tracked roadmap"                         0 "" "$R" --upstream docs/roadmaps/ROADMAP-good.md
expect "a tracked roadmap in a subdirectory"       0 "" "$R" --upstream docs/roadmaps/sub/ROADMAP-nested.md
expect "from a subdirectory of the repository"     0 "" "$R/docs" --upstream docs/roadmaps/ROADMAP-good.md
expect "a cross-repo roadmap"                      0 "" "$R" --upstream owner/repo:docs/roadmaps/ROADMAP-x.md
expect "the --upstream=value form"                 0 "" "$R" --upstream=docs/roadmaps/ROADMAP-good.md

echo "== refused (exit 1, one reason) =="
expect "a symlink into wip/"                       1 upstream-wip       "$R" --upstream docs/roadmaps/ROADMAP-intowip.md
expect "a path under wip/"                         1 upstream-wip       "$R" --upstream wip/ROADMAP-scratch.md
expect "an untracked roadmap"                      1 upstream-untracked "$R" --upstream docs/roadmaps/ROADMAP-untracked.md
expect "a roadmap that does not exist"             1 upstream-untracked "$R" --upstream docs/roadmaps/ROADMAP-missing.md
expect "a symlink leaving the repository"          1 upstream-outside   "$R" --upstream docs/roadmaps/ROADMAP-away.md
expect "an absolute path outside the repository"   1 upstream-outside   "$R" --upstream "$T/elsewhere/ROADMAP-far.md"
expect "a symlink out of docs/roadmaps/"           1 upstream-outside   "$R" --upstream docs/roadmaps/ROADMAP-sideways.md
expect "a roadmap-named file outside docs/roadmaps/" 1 upstream-outside "$R" --upstream docs/other/ROADMAP-other.md
expect "a symlink to a file not named ROADMAP-"    1 upstream-basename  "$R" --upstream docs/roadmaps/ROADMAP-renamed.md
expect "a file not named ROADMAP-"                 1 upstream-basename  "$R" --upstream docs/roadmaps/notes.md
expect "a cross-repo value not naming a roadmap"   1 upstream-basename  "$R" --upstream owner/repo:docs/roadmaps/PLAN-x.md

echo "== cannot tell (exit 2) =="
expect "outside any git work tree"                 2 "" "$T/plain" --upstream docs/roadmaps/ROADMAP-good.md
expect "a missing --upstream"                      2 "" "$R"
expect "an unknown argument"                       2 "" "$R" --upstream "" --x
expect "--upstream given twice"                    2 "" "$R" --upstream "" --upstream ""

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
