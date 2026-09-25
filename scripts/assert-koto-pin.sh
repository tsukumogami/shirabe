#!/usr/bin/env bash
# assert-koto-pin.sh -- fail unless the koto on PATH is the release .tsuku.toml
# pins.
#
# shirabe's CI gets koto through tsuku from the project manifest, and every
# suite that drives a real koto session skips with exit 0 when koto is absent.
# So a workflow that installs koto runs this right after the install: it prints
# `koto version`, and fails the job when koto is missing, when the manifest
# does not pin an exact version, or when the installed koto is not that
# version. Without it, a skip, or a stale koto left on a runner, would pass as
# green having tested something other than the pinned release.
#
# Usage: scripts/assert-koto-pin.sh [<manifest>]
#
# <manifest> defaults to .tsuku.toml at the repository root. The pin is the
# value of the `"tsukumogami/koto"` key under [tools], an exact version such as
# "0.13.0" (a leading `v` is accepted).
#
# Environment:
#   KOTO_BIN   the koto binary to check (default: `koto` from PATH)
#
# Exit codes:
#   0 -- koto is present and is the pinned release
#   1 -- koto is missing, the pin is not an exact version, or they differ

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="${1:-$ROOT/.tsuku.toml}"
KOTO="${KOTO_BIN:-koto}"

[ -f "$MANIFEST" ] || { echo "assert-koto-pin: manifest not found: $MANIFEST" >&2; exit 1; }

PIN=$(sed -n 's/^[[:space:]]*"tsukumogami\/koto"[[:space:]]*=[[:space:]]*"\([^"]*\)".*$/\1/p' "$MANIFEST" | head -1)
PIN="${PIN#v}"
if [ -z "$PIN" ]; then
    echo "assert-koto-pin: $MANIFEST does not pin \"tsukumogami/koto\"" >&2
    exit 1
fi
if ! printf '%s' "$PIN" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "assert-koto-pin: \"tsukumogami/koto\" = \"$PIN\" is not an exact version; pin the release CI must run" >&2
    exit 1
fi

if ! command -v "$KOTO" >/dev/null 2>&1; then
    echo "assert-koto-pin: koto is not on PATH; expected $PIN" >&2
    exit 1
fi

VERSION_LINE=$("$KOTO" version 2>/dev/null | head -1)
echo "koto version: ${VERSION_LINE:-<no output>}"
GOT=$(printf '%s' "$VERSION_LINE" | sed -n 's/^koto v\{0,1\}\([0-9][0-9.]*\).*$/\1/p')
if [ "$GOT" != "$PIN" ]; then
    echo "assert-koto-pin: koto on PATH is ${GOT:-unknown}, but .tsuku.toml pins $PIN" >&2
    exit 1
fi
echo "assert-koto-pin: koto $GOT matches the pin"
