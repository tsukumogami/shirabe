#!/usr/bin/env bash
# deliver-preflight.sh -- /deliver's repository binding: public repositories
# only, decided the way /scope decides visibility.
#
# /scope v1 binds to public-repo tactical chains, and /deliver inherits that
# binding. The visibility is the one /scope's Phase 0 reads: the
# `## Repo Visibility:` header in the repository's CLAUDE.md, `Public` or
# `Private`, with a missing header treated as Private ("Default to Private if
# unknown"). CLAUDE.local.md is read the same way when CLAUDE.md declares
# nothing, as /scope's publish step reads both.
#
# `preflight` is gate-only over this script: a public repository goes on to
# open the run's request, anything else ends the run at `done_refused` with
# reason `private-repo`, before any child runs or any request is written.
#
# Usage: deliver-preflight.sh
#   (run from inside the repository; no arguments)
#
# Exit codes:
#   0   Public
#   1   Private
#   2   unknown: no header, a value other than Public or Private, or not
#       inside a git work tree -- refused like Private
#   64  usage error
#
# Read-only: reads CLAUDE.md and CLAUDE.local.md at the work-tree root.
# bash 3.2.
set -uo pipefail

PROG=deliver-preflight

if [ "$#" -ne 0 ]; then
    printf 'usage: deliver-preflight.sh\n' >&2
    exit 64
fi

TOP=$(git rev-parse --show-toplevel) || TOP=""
if [ -z "$TOP" ]; then
    printf '%s: not inside a git work tree; the repository visibility is unknown\n' "$PROG" >&2
    exit 2
fi

# header_value <file> -- the first `## Repo Visibility:` value, lowercased.
header_value() {
    [ -f "$1" ] || return 0
    sed -nE 's/^##[[:space:]]+Repo Visibility:[[:space:]]*([A-Za-z]+)[[:space:]]*$/\1/p' "$1" \
        | sed -n 1p | tr '[:upper:]' '[:lower:]'
}

VALUE=$(header_value "$TOP/CLAUDE.md")
[ -n "$VALUE" ] || VALUE=$(header_value "$TOP/CLAUDE.local.md")

case "$VALUE" in
    public)
        exit 0
        ;;
    private)
        printf '%s: this repository declares ## Repo Visibility: Private; /deliver runs public-repo tactical chains only\n' "$PROG" >&2
        exit 1
        ;;
    *)
        printf '%s: no ## Repo Visibility: header in CLAUDE.md; Default to Private if unknown, so /deliver does not run here\n' "$PROG" >&2
        exit 2
        ;;
esac
