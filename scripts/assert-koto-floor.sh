#!/usr/bin/env bash
# assert-koto-floor.sh -- fail unless the koto on PATH is at least the release
# shirabe requires.
#
# shirabe's CI gets koto through tsuku from the project manifest, which tracks
# the newest koto 0.x rather than an exact release (an exact pin would make
# `tsuku install` downgrade a newer koto a developer already has). Every suite
# that drives a real koto session skips with exit 0 when koto is absent, so a
# workflow that installs koto runs this right after the install: it prints
# `koto version`, and fails the job when koto is missing or older than the
# floor. Without it, a skip, or a stale koto left on a runner, would pass as
# green having tested something shirabe does not support.
#
# The floor is KOTO_FLOOR below, not a value read from .tsuku.toml: the
# manifest names the major version shirabe tracks, the floor names the oldest
# release that has what shirabe uses. 0.13.0 is the release that shipped the
# koto init entry flags (--vars-file, --attach-live, --replace-terminal,
# --koto-leg) /scope, /execute and /deliver enter through, and from which the
# templates' context_assignments execute. Raise it in the pull request that
# adopts a feature from a newer koto. check-koto-entry-floor.yml runs the koto-backed
# suites on exactly this release, so keep the two in step.
#
# Usage: scripts/assert-koto-floor.sh
#
# Environment:
#   KOTO_BIN     the koto binary to check (default: `koto` from PATH)
#   KOTO_FLOOR   override the floor (used by the tests)
#
# Exit codes:
#   0 -- koto is present and at or above the floor
#   1 -- koto is missing, its version is unreadable, or it is below the floor
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile, no sort -V.

set -uo pipefail

FLOOR="${KOTO_FLOOR:-0.13.0}"
KOTO="${KOTO_BIN:-koto}"

# semver_ge A B -- exit 0 when MAJOR.MINOR.PATCH A >= B, compared numerically
# field by field. Missing fields count as 0; any pre-release or build suffix on
# the patch field is dropped.
semver_ge() {
    local a="$1" b="$2" i x y
    local IFS=.
    # shellcheck disable=SC2206
    local av=($a) bv=($b)
    for i in 0 1 2; do
        x="${av[$i]:-0}"; x="${x%%[!0-9]*}"; x="${x:-0}"
        y="${bv[$i]:-0}"; y="${y%%[!0-9]*}"; y="${y:-0}"
        if [ "$((10#$x))" -gt "$((10#$y))" ]; then return 0; fi
        if [ "$((10#$x))" -lt "$((10#$y))" ]; then return 1; fi
    done
    return 0
}

FLOOR="${FLOOR#v}"
if ! printf '%s' "$FLOOR" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "assert-koto-floor: the floor \"$FLOOR\" is not a MAJOR.MINOR.PATCH version" >&2
    exit 1
fi

if ! command -v "$KOTO" >/dev/null 2>&1; then
    echo "assert-koto-floor: koto is not on PATH; shirabe needs koto $FLOOR or later" >&2
    exit 1
fi

VERSION_LINE=$("$KOTO" version 2>/dev/null | head -1)
echo "koto version: ${VERSION_LINE:-<no output>}"
GOT=$(printf '%s' "$VERSION_LINE" | sed -n 's/^koto v\{0,1\}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p')
if [ -z "$GOT" ]; then
    echo "assert-koto-floor: cannot read a version from \`$KOTO version\`; shirabe needs koto $FLOOR or later" >&2
    exit 1
fi
if ! semver_ge "$GOT" "$FLOOR"; then
    echo "assert-koto-floor: koto on PATH is $GOT, below the floor $FLOOR; upgrade koto" >&2
    exit 1
fi
echo "assert-koto-floor: koto $GOT meets the floor $FLOOR"
