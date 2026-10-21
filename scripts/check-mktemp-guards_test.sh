#!/usr/bin/env bash
# check-mktemp-guards_test.sh -- scripts/check-mktemp-guards.sh.
#
# Covers: the repository's own scripts pass; each refused shape is found (a
# cd, pushd, git -C, or an rm, mv, redirection, mkdir, cp, tee or touch on a
# path built from an unchecked mktemp value; the quoted, backtick, umask and
# continued forms; a use above the assignment; local masking the status under
# errexit), named at the mktemp's line; the shapes that are fine are not (a
# check with ||, an if condition, errexit, a plain rm of the value alone, a
# read, another name, a comment, a string); a named file and a directory; a
# missing path (2). And the hazard itself: `cd ""` succeeds and stays put, so
# an unchecked empty value turns into the current directory (shirabe#922,
# #924, #925, #926).
#
# Usage: bash scripts/check-mktemp-guards_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CHECK="$HERE/check-mktemp-guards.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/check-mktemp-guards-test.XXXXXX") || exit 1
trap 'case "$T" in */check-mktemp-guards-test.*) rm -rf "$T" ;; esac' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

echo "== the repository =="
if OUT=$(bash "$CHECK" 2>&1); then ok "every tracked script passes"; else bad "every tracked script passes" "$OUT"; fi

CASES="$HERE/check-mktemp-guards.cases"
NL=$'\n'
# put <file> <text>: a script holding the text, each <NL> a newline.
put() { printf '#!/usr/bin/env bash\n%s\n' "${2//<NL>/$NL}" > "$1"; }

echo "== refused and fine shapes (check-mktemp-guards.cases) =="
n=0
while IFS=$'\t' read -r kind label text; do
    case "$kind" in refused|fine) n=$((n + 1)) ;; *) continue ;; esac
    put "$T/f.sh" "$text"
    OUT=$(bash "$CHECK" "$T/f.sh" 2>&1); rc=$?
    if [ "$kind" = refused ]; then
        # Named at the line holding the mktemp, counting the shebang.
        at=$(awk '/mktemp/ { print NR; exit }' "$T/f.sh")
        case "$rc:$OUT" in 1:*"f.sh:$at:"*) ok "refused: $label" ;; *) bad "refused: $label" "rc=$rc out=$OUT" ;; esac
    elif [ "$rc" = 0 ]; then
        ok "fine: $label"
    else
        bad "fine: $label" "rc=$rc out=$OUT"
    fi
done < "$CASES"
[ "$n" -ge 25 ] && ok "every case was read ($n)" || bad "every case was read" "only $n"

echo "== paths =="
mkdir -p "$T/d/sub"
FIRST=$(awk -F'\t' '$1 == "refused" { print $3; exit }' "$CASES")
put "$T/d/sub/a.sh" "$FIRST"
put "$T/d/sub/notes.txt" "$FIRST"
OUT=$(bash "$CHECK" "$T/d" 2>&1); rc=$?
case "$rc:$OUT" in 1:*"sub/a.sh:2:"*) ok "a directory: its *.sh files" ;; *) bad "a directory: its *.sh files" "rc=$rc out=$OUT" ;; esac
case "$OUT" in *notes.txt*) bad "a directory: nothing but *.sh" "$OUT" ;; *) ok "a directory: nothing but *.sh" ;; esac
bash "$CHECK" "$T/none" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "a missing path: exit 2" || bad "a missing path: exit 2" "rc=$rc"

echo "== the hazard: an empty value is the current directory =="
mkdir -p "$T/here"
E=""
got=$(cd "$T/here" && X=$(cd "$E" && pwd -P) && printf '%s' "$X")
want=$(cd "$T/here" && pwd -P)
[ "$got" = "$want" ] && ok "cd \"\" succeeds and stays put, so \$(cd \"\" && pwd) is the caller's directory" \
    || bad "cd \"\" succeeds and stays put" "got '$got', want '$want'"

echo
echo "check-mktemp-guards: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
