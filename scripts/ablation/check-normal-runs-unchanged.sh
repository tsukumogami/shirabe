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
#   2 - usage error, or <base> is not a commit

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

list="$(mktemp)"
trap 'rm -f "$list"' EXIT

# Column 2 of every data row: skip comments, blank lines and the header.
awk -F '\t' '
    /^#/ || /^[[:space:]]*$/ { next }
    !header { header = 1; next }
    $2 != "" { print $2 }
' "$manifest" >> "$list"

# Every koto template, at HEAD and at the base, so a template added or
# removed on either side is compared too.
{
    git ls-tree -r --name-only "$head" -- skills
    git ls-tree -r --name-only "$fork" -- skills
} | grep -E '^skills/[^/]+/koto-templates/[^/]+\.md$' >> "$list" || true

changed=0
while IFS= read -r path; do
    if ! git diff --quiet "$fork" "$head" -- "$path"; then
        echo "$PROG: $path differs from $base" >&2
        changed=1
    fi
done < <(sort -u "$list")

if [ "$changed" -eq 0 ]; then
    echo "$PROG: nothing a normal run loads differs from $base"
fi
exit "$changed"
