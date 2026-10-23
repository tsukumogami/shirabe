#!/usr/bin/env bash
# pr-workflow-content_test.sh -- pr-workflow-content.sh prints include only
# for a repository that declares it, omit otherwise, reading CLAUDE.local.md
# before CLAUDE.md.
#
# Covers: no file, no header (omit); include and omit in CLAUDE.md; case and
# spacing; CLAUDE.local.md before CLAUDE.md, both ways; an unknown value
# passed over; the first well-formed header in a file; CRLF line ends; the
# work tree's root as the default directory; a missing directory; usage.
#
# Usage: bash scripts/pr-workflow-content_test.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/pr-workflow-content.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/pr-workflow-content-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

N=0
repo() { N=$((N + 1)); R="$T/r$N"; mkdir -p "$R"; }

repo
eq "no CLAUDE.md: omit" omit "$(bash "$S" "$R")"
repo; printf '# Repo\n\n## Repo Visibility: Public\n' > "$R/CLAUDE.md"
eq "no header: omit" omit "$(bash "$S" "$R")"
repo; printf '# Repo\n\n## PR Workflow Content: include\n' > "$R/CLAUDE.md"
eq "include in CLAUDE.md: include" include "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: omit\n' > "$R/CLAUDE.md"
eq "omit in CLAUDE.md: omit" omit "$(bash "$S" "$R")"
repo; printf '  ## pr workflow content:   INCLUDE  \n' > "$R/CLAUDE.md"
eq "case and spacing don't matter" include "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: include\r\n' > "$R/CLAUDE.md"
eq "a CRLF line end is read" include "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: include\n' > "$R/CLAUDE.local.md"; printf '## PR Workflow Content: omit\n' > "$R/CLAUDE.md"
eq "CLAUDE.local.md is read before CLAUDE.md (include)" include "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: omit\n' > "$R/CLAUDE.local.md"; printf '## PR Workflow Content: include\n' > "$R/CLAUDE.md"
eq "CLAUDE.local.md is read before CLAUDE.md (omit)" omit "$(bash "$S" "$R")"
repo; printf '# Local\n' > "$R/CLAUDE.local.md"; printf '## PR Workflow Content: include\n' > "$R/CLAUDE.md"
eq "a CLAUDE.local.md with no header falls through to CLAUDE.md" include "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: yes\n## PR Workflow Content: include\n' > "$R/CLAUDE.md"
eq "an unknown value is passed over for the next well-formed header" include "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: always\n' > "$R/CLAUDE.md"
eq "only an unknown value: omit" omit "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: include please\n' > "$R/CLAUDE.md"
eq "trailing words make it not well-formed: omit" omit "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: omit\n## PR Workflow Content: include\n' > "$R/CLAUDE.md"
eq "the first well-formed header wins" omit "$(bash "$S" "$R")"
repo; printf '### PR Workflow Content: include\n' > "$R/CLAUDE.md"
eq "a deeper heading is not the header" omit "$(bash "$S" "$R")"

if command -v git >/dev/null 2>&1; then
    repo; git init -q "$R" && printf '## PR Workflow Content: include\n' > "$R/CLAUDE.md" && mkdir -p "$R/a/b"
    eq "no argument: the work tree's root" include "$(cd "$R/a/b" && bash "$S")"
else
    ok "no argument: the work tree's root (skipped: no git)"
fi

bash "$S" "$T/missing" >/dev/null 2>&1; eq "a directory that doesn't exist: exit 2" 2 $?
bash "$S" a b >/dev/null 2>&1; eq "two arguments: exit 64" 64 $?
bash "$S" --help >/dev/null 2>&1; eq "an option: exit 64" 64 $?

echo
echo "pr-workflow-content: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
