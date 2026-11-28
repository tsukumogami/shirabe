#!/usr/bin/env bash
#
# check-normal-runs-unchanged.sh - prove a change leaves what normal runs load alone
#
# The ablation harness withholds instruction sections only inside scratch
# copies of the plugin. Nothing a normal run of a shipped skill loads may
# change. This script checks that mechanically: every path the offload
# baseline's load manifest lists, and every koto template under
# skills/*/koto-templates/ (at <head> or at the base), must be identical
# between the merge base of <base> and <head>, and <head>.
#
# Usage:
#   scripts/ablation/check-normal-runs-unchanged.sh <base> [<head>]
#
# <base> is any commit-ish (for CI, the pull request's base sha) and <head>
# defaults to HEAD. Comparing from the merge base means commits that landed on
# the base branch after the change forked are never counted as the change's
# own. The manifest is read from the working tree; set ABLATION_MANIFEST to
# point it elsewhere (tests do).
#
# Exit codes:
#   0 - nothing a normal run loads differs from <base>
#   1 - at least one such file differs; each is named on stderr
#   2 - usage error, <base> is not a commit, or the run's temporary path list
#       was lost mid-run ("is gone or unreadable"), so nothing was verified

set -euo pipefail

PROG=check-normal-runs-unchanged

die() {
    echo "$PROG: $*" >&2
    exit 2
}

[ "$#" -eq 1 ] || [ "$#" -eq 2 ] || die "usage: $0 <base> [<head>]"
base="$1"
head="${2:-HEAD}"
for ref in "$base" "$head"; do
    case "$ref" in
        ""|-*) die "refusing base that is empty or starts with '-': $ref" ;;
    esac
    git rev-parse --verify --quiet --end-of-options "${ref}^{commit}" >/dev/null \
        || die "not a commit: $ref"
done
fork=$(git merge-base "$base" "$head") || die "no merge base between $base and $head"

repo_root=$(git rev-parse --show-toplevel)
manifest="${ABLATION_MANIFEST:-$repo_root/docs/measurement/offload-baseline/load-manifest.tsv}"
[ -f "$manifest" ] || die "manifest not found: $manifest"

list="$(mktemp)" || die "cannot create a temporary file"
sorted="$list.sorted"
trap 'rm -f "$list" "$sorted"' EXIT

# The path list is the whole verdict, so a write or read-back that fails must
# end the run (shirabe#2229): an unreadable list is not an empty one.
lost() {
    die "temporary file $list is gone or unreadable: cannot $1"
}

# Column 2 of every data row: skip comments, blank lines and the header.
awk -F '\t' '
    /^#/ || /^[[:space:]]*$/ { next }
    !header { header = 1; next }
    $2 != "" { print $2 }
' "$manifest" >> "$list" || lost "write the manifest paths"

# Every koto template, at HEAD and at the base, so a template added or
# removed on either side is compared too. Status 1 is grep's no match (or an
# append the shell couldn't open, which the read-back below catches); more
# than that is a failed git or grep, and the list is incomplete.
grc=0
{
    git ls-tree -r --name-only "$head" -- skills
    git ls-tree -r --name-only "$fork" -- skills
} | grep -E '^skills/[^/]+/koto-templates/[^/]+\.md$' >> "$list" || grc=$?
[ "$grc" -le 1 ] || die "could not list the koto templates at $head and $fork (status $grc)"

[ -r "$list" ] || lost "read back the path list"
sort -u "$list" > "$sorted" || lost "sort the path list"
[ -r "$sorted" ] || lost "read back the sorted path list"

changed=0
while IFS= read -r path; do
    if ! git diff --quiet "$fork" "$head" -- "$path"; then
        echo "$PROG: $path differs from $base" >&2
        changed=1
    fi
done < "$sorted"

if [ "$changed" -eq 0 ]; then
    echo "$PROG: nothing a normal run loads differs from $base"
fi
exit "$changed"
