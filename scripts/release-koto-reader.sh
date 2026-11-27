#!/usr/bin/env bash
#
# release-koto-reader.sh - name the koto release the shirabe binary's session
# reader comes from
#
# The shirabe binary compiles in koto's read-only session reader, the
# koto-session-reader crate, from a koto release tag pinned in
# crates/shirabe/Cargo.toml. This check reads that pin and the lock file's
# entry for the crate, and fails unless both name the same release:
#
#   - crates/shirabe/Cargo.toml has one koto-session-reader line, an inline
#     git dependency on https://github.com/tsukumogami/koto with
#     tag = "vX.Y.Z" and no branch, rev or path;
#   - Cargo.lock has one [[package]] named koto-session-reader, whose source
#     is git+https://github.com/tsukumogami/koto?tag=vX.Y.Z#<commit>, with
#     the same tag and a full commit hash.
#
# On success it prints the one line the release notes carry:
#
#   koto session reader: koto vX.Y.Z (<first 8 characters of the commit>)
#
# Declared as a release check in .claude/shirabe-extensions/release.md. It
# reads the two files and nothing else: no network, no cargo, no koto.
#
# Usage:
#   scripts/release-koto-reader.sh [<repository root>]
#
# The root defaults to the repository this script is in.
#
# Exit codes:
#   0 -- the pin and the lock agree; the line is printed
#   1 -- a file is missing, or the pin or the lock isn't in the form above;
#        the reason is on stderr
#   2 -- a usage error
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -euo pipefail

KOTO_REPO="https://github.com/tsukumogami/koto"
CRATE="koto-session-reader"

die() {
    echo "release-koto-reader: $*" >&2
    exit 1
}

case "$#" in
    0) ROOT=$(cd "$(dirname "$0")/.." && pwd) ;;
    1) ROOT=$1 ;;
    *)
        echo "usage: scripts/release-koto-reader.sh [<repository root>]" >&2
        exit 2
        ;;
esac

MANIFEST="$ROOT/crates/shirabe/Cargo.toml"
LOCK="$ROOT/Cargo.lock"
[ -f "$MANIFEST" ] || die "no manifest at $MANIFEST"
[ -f "$LOCK" ] || die "no lock file at $LOCK"

# -- the pin --------------------------------------------------------------------

dep=$(grep -E "^[[:space:]]*${CRATE}[[:space:]]*=" "$MANIFEST" || true)
count=$(grep -c . <<<"$dep" || true)
[ "$count" = 1 ] || die "crates/shirabe/Cargo.toml has $count $CRATE dependency lines, not one"

# field <key>: the quoted value of <key> in the dependency's inline table.
field() {
    sed -nE "s/.*[{,][[:space:]]*$1[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\\1/p" <<<"$dep"
}

for key in branch rev path; do
    if grep -Eq "[{,][[:space:]]*${key}[[:space:]]*=" <<<"$dep"; then
        die "$CRATE is pinned by $key in crates/shirabe/Cargo.toml; pin it by a koto release tag"
    fi
done
git_url=$(field git)
[ "$git_url" = "$KOTO_REPO" ] ||
    die "$CRATE in crates/shirabe/Cargo.toml isn't a git dependency on $KOTO_REPO: $dep"
tag=$(field tag)
grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$tag" ||
    die "$CRATE in crates/shirabe/Cargo.toml has no tag = \"vX.Y.Z\": $dep"

# -- the lock -------------------------------------------------------------------

# The source of every [[package]] named after the crate, one per line.
sources=$(awk -v want="\"$CRATE\"" '
    /^\[\[package\]\]/ { in_pkg = 1; name = ""; next }
    /^\[/ { in_pkg = 0; next }
    in_pkg && $1 == "name" && $2 == "=" { name = $3; next }
    in_pkg && name == want && $1 == "source" && $2 == "=" { gsub(/"/, "", $3); print $3 }
' "$LOCK")
count=$(grep -c . <<<"$sources" || true)
[ "$count" = 1 ] || die "Cargo.lock has $count $CRATE sources, not one"

prefix="git+$KOTO_REPO?tag=$tag#"
case "$sources" in
    "$prefix"*) sha=${sources#"$prefix"} ;;
    *) die "Cargo.lock's $CRATE source is $sources; crates/shirabe/Cargo.toml pins $KOTO_REPO at $tag" ;;
esac
grep -Eq '^[0-9a-f]{40}$' <<<"$sha" ||
    die "Cargo.lock's $CRATE source has no full commit hash: $sources"

printf 'koto session reader: koto %s (%s)\n' "$tag" "${sha:0:8}"
