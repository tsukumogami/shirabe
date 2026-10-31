#!/usr/bin/env bash
# check-setup-script-copy.sh -- fail when a repository's copy of shirabe's
# pre-commit setup script differs from the canonical one.
#
# Usage: check-setup-script-copy.sh <caller root> <canonical file> <ref label>
#
# The canonical copy is scripts/setup/shirabe-pre-commit.sh in shirabe. Every
# product repository that carries a copy keeps it byte-identical, and the
# reusable lifecycle workflow runs this check in each of them on every pull
# request, against the shirabe checkout at the called ref. <ref label> names
# that ref (a commit) in the message, so the fix points at the exact bytes.
#
# Exit codes: 0 no copy (nothing to compare) or the copy matches and is
# executable; 1 the copy is a symlink or not a regular file, differs, or isn't
# executable, with a GitHub Actions ::error line naming the fix; 2 usage, or
# the canonical file is missing.
set -euo pipefail

if [ $# -ne 3 ]; then
    echo "usage: check-setup-script-copy.sh <caller root> <canonical file> <ref label>" >&2
    exit 2
fi
root=$1 canonical=$2 ref=$3
rel=scripts/setup/shirabe-pre-commit.sh
copy="$root/$rel"

if [ ! -f "$canonical" ]; then
    echo "check-setup-script-copy: canonical file $canonical not found" >&2
    exit 2
fi

if [ ! -e "$copy" ] && [ ! -L "$copy" ]; then
    echo "no $rel in this repository; nothing to compare"
    exit 0
fi

# Removing first means the same command also replaces a symlink or a directory
# standing at the path; curl -o alone would write through a link.
restore="rm -rf -- $rel && curl -fsSL https://raw.githubusercontent.com/tsukumogami/shirabe/$ref/$rel -o $rel && chmod 0755 $rel"

if [ -L "$copy" ] || [ ! -f "$copy" ]; then
    echo "::error file=$rel::$rel must be a regular file, a byte-identical copy of the canonical one in tsukumogami/shirabe at $ref, not a symlink or directory. Replace it with: $restore"
    exit 1
fi

if ! cmp -s "$canonical" "$copy"; then
    echo "::error file=$rel::$rel differs from the canonical copy in tsukumogami/shirabe at $ref. Copies are kept byte-identical; restore it with: $restore"
    exit 1
fi

if [ ! -x "$copy" ]; then
    echo "::error file=$rel::$rel matches the canonical copy but isn't executable; niwa's setup step runs only executable files. Fix it with: chmod 0755 $rel (and commit the mode)"
    exit 1
fi

echo "$rel matches the canonical copy in tsukumogami/shirabe at $ref"
