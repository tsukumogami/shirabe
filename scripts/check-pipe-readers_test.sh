#!/usr/bin/env bash
# check-pipe-readers_test.sh -- scripts/check-pipe-readers.sh.
#
# Covers: the repository's own scripts pass; each refused shape is found (a
# printf, echo or cat piped into grep -q, a quiet flag cluster, --quiet,
# grep -m, head; after if, elif, !, && and inside $(...); a pipe on a
# continued line), with its path and line; the shapes that are fine are not
# (a here-string, grep -c, grep without a quiet flag, a pipe from another
# writer, a comment, a pipe inside a command substitution in the writer's
# arguments); a named file and a directory; a missing path (2). And the
# hazard itself, deterministically: with a value larger than a pipe holds,
# `printf | grep -q` fails a match under pipefail every time, and the
# here-string form passes (shirabe#833, #846, #849, #864, #865, #872).
#
# Usage: bash scripts/check-pipe-readers_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CHECK="$HERE/check-pipe-readers.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/check-pipe-readers-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

echo "== the repository =="
if OUT=$(bash "$CHECK" 2>&1); then ok "every tracked script passes"; else bad "every tracked script passes" "$OUT"; fi

CASES="$HERE/check-pipe-readers.cases"
NL=$'\n'
# put <file> <line>: a script holding the line, each <NL> a newline.
put() { printf '#!/usr/bin/env bash\n%s\n' "${2//<NL>/$NL}" > "$1"; }

echo "== refused and fine shapes (check-pipe-readers.cases) =="
n=0
while IFS=$'\t' read -r kind label line; do
    case "$kind" in refused|fine) n=$((n + 1)) ;; *) continue ;; esac
    put "$T/f.sh" "$line"
    OUT=$(bash "$CHECK" "$T/f.sh" 2>&1); rc=$?
    if [ "$kind" = refused ]; then
        case "$rc:$OUT" in 1:*"f.sh:2:"*) ok "refused: $label" ;; *) bad "refused: $label" "rc=$rc out=$OUT" ;; esac
    elif [ "$rc" = 0 ]; then
        ok "fine: $label"
    else
        bad "fine: $label" "rc=$rc out=$OUT"
    fi
done < "$CASES"
[ "$n" -ge 19 ] && ok "every case was read ($n)" || bad "every case was read" "only $n"

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

echo "== the hazard, with a value larger than a pipe holds =="
# The match is the first line and 256 KiB follow on the next (grep reads a
# whole line before it matches), so grep -q exits while printf still has most
# of it to write: the old shape fails every time, the new one never does.
BIG="done"$'\n'"$(head -c 262144 /dev/zero | tr '\0' x)"
old=0; new=0
# The writer is held in a variable so the check, which this file is in scope
# of, doesn't refuse the one place the old shape is kept on purpose; its
# "write error: Broken pipe" is the expected outcome and is discarded.
W=printf
for i in 1 2 3; do
    "$W" '%s' "$BIG" 2>/dev/null | grep -q done || old=$((old + 1))
    grep -q done <<<"$BIG" || new=$((new + 1))
done
[ "$old" = 3 ] && ok "printf | grep -q misses the match under pipefail (3 of 3)" || bad "printf | grep -q misses the match under pipefail (3 of 3)" "missed $old of 3"
[ "$new" = 0 ] && ok "grep -q <<< finds it (3 of 3)" || bad "grep -q <<< finds it (3 of 3)" "missed $new of 3"

echo
echo "check-pipe-readers: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
