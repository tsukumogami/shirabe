#!/usr/bin/env bash
# check-setup-script-copy_test.sh -- scripts/check-setup-script-copy.sh.
#
# Each case builds a caller repository layout in a throwaway directory and runs
# the check against the real canonical script, asserting the exit status and
# the line it prints.
#
# Usage: bash scripts/check-setup-script-copy_test.sh
#
# `cond && ok ... || bad ...` is safe here: ok only prints and counts, so it
# never fails and bad runs only when the condition does.
# shellcheck disable=SC2015
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CHECK="$HERE/check-setup-script-copy.sh"
CANON="$HERE/setup/shirabe-pre-commit.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/check-setup-script-copy-test.XXXXXX") || exit 1
trap 'case "$T" in */check-setup-script-copy-test.*) rm -rf "$T" ;; esac' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

# caller <name>: an empty caller root with scripts/setup/, printing its path.
caller() { mkdir -p "$T/$1/scripts/setup" && printf '%s' "$T/$1"; }
REL=scripts/setup/shirabe-pre-commit.sh

r=$(caller none)
out=$(bash "$CHECK" "$r" "$CANON" abc123 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$out" = "no $REL in this repository; nothing to compare" ] \
    && ok "no copy: nothing to compare, exit 0" || bad "no copy: nothing to compare, exit 0" "rc=$rc out=[$out]"

r=$(caller same)
cp "$CANON" "$r/$REL" && chmod 0755 "$r/$REL"
out=$(bash "$CHECK" "$r" "$CANON" abc123 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$out" = "$REL matches the canonical copy in tsukumogami/shirabe at abc123" ] \
    && ok "identical and executable: exit 0" || bad "identical and executable: exit 0" "rc=$rc out=[$out]"

r=$(caller differs)
cp "$CANON" "$r/$REL" && printf '# a local edit\n' >> "$r/$REL" && chmod 0755 "$r/$REL"
out=$(bash "$CHECK" "$r" "$CANON" abc123 2>&1); rc=$?
case "$out" in
    "::error file=$REL::$REL differs from the canonical copy in tsukumogami/shirabe at abc123."*"rm -rf -- $REL && curl -fsSL https://raw.githubusercontent.com/tsukumogami/shirabe/abc123/$REL -o $REL && chmod 0755 $REL")
        [ "$rc" = 1 ] && ok "a differing copy: exit 1 with the restore command" || bad "a differing copy: exit 1" "rc=$rc" ;;
    *) bad "a differing copy: exit 1 with the restore command" "rc=$rc out=[$out]" ;;
esac

r=$(caller mode)
cp "$CANON" "$r/$REL" && chmod 0644 "$r/$REL"
out=$(bash "$CHECK" "$r" "$CANON" abc123 2>&1); rc=$?
case "$out" in
    "::error file=$REL::$REL matches the canonical copy but isn't executable"*"chmod 0755 $REL (and commit the mode)")
        [ "$rc" = 1 ] && ok "identical but not executable: exit 1 naming the chmod fix" || bad "identical but not executable: exit 1" "rc=$rc" ;;
    *) bad "identical but not executable: exit 1 naming the chmod fix" "rc=$rc out=[$out]" ;;
esac

# A symlink and a directory at the path are the same failure: not a regular
# file, with the remove-then-restore command.
r=$(caller link)
ln -s "$CANON" "$r/$REL"
out=$(bash "$CHECK" "$r" "$CANON" abc123 2>&1); rc=$?
case "$out" in
    "::error file=$REL::$REL must be a regular file"*"not a symlink or directory. Replace it with: rm -rf -- $REL && curl"*)
        [ "$rc" = 1 ] && ok "a symlink in place of the copy: exit 1, not a regular file" || bad "a symlink: exit 1" "rc=$rc" ;;
    *) bad "a symlink in place of the copy: exit 1, not a regular file" "rc=$rc out=[$out]" ;;
esac

r=$(caller dir)
mkdir "$r/$REL"
out=$(bash "$CHECK" "$r" "$CANON" abc123 2>&1); rc=$?
case "$out" in
    "::error file=$REL::$REL must be a regular file"*"Replace it with: rm -rf -- $REL && curl"*)
        [ "$rc" = 1 ] && ok "a directory in place of the copy: exit 1, not a regular file" || bad "a directory: exit 1" "rc=$rc" ;;
    *) bad "a directory in place of the copy: exit 1, not a regular file" "rc=$rc out=[$out]" ;;
esac

out=$(bash "$CHECK" "$T/none" "$T/missing.sh" abc123 2>&1); rc=$?
[ "$rc" = 2 ] && ok "a missing canonical file: exit 2" || bad "a missing canonical file: exit 2" "rc=$rc out=[$out]"

out=$(bash "$CHECK" "$T/none" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "wrong argument count: exit 2" || bad "wrong argument count: exit 2" "rc=$rc out=[$out]"

echo
echo "check-setup-script-copy: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
