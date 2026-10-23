#!/usr/bin/env bash
# claude-md-header_test.sh -- claude-md-header.sh reads one `## <Name>:`
# declaration from a CLAUDE.md, in the working tree or at a commit.
#
# Covers: a declared value, trimmed, any case of the name; an empty value; an
# absent header and an absent file (exit 1); a header inside a ``` or ~~~
# fence ignored, and one after the fence closes read; a longer fence that a
# shorter run doesn't close; a duplicate refused (exit 2); a CRLF file; an
# indented heading; a `###` heading ignored; at a commit, the committed text
# and not the working tree's, a file absent at that commit, and a commit that
# doesn't exist (exit 2).
#
# Usage: bash scripts/lib/claude-md-header_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }
# shellcheck source=claude-md-header.sh
. "$HERE/claude-md-header.sh"

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

W=$(mktemp -d) || { echo "FAIL: could not create a temporary directory"; exit 1; }
trap 'rm -rf "$W"' EXIT

f="$W/CLAUDE.md"
put() { printf "$1" > "$f"; }

put '# Repo\n\n## Fix Labels: bug, regression  \n'
eq "a declared value, trimmed" "bug, regression" "$(claude_md_header 'Fix Labels' "$f")"
claude_md_header 'Fix Labels' "$f" >/dev/null; eq "a declared value: exit 0" 0 $?
eq "the name matches in any case" "bug, regression" "$(claude_md_header 'fix labels' "$f")"

put '## Fix Labels:\n'
claude_md_header 'Fix Labels' "$f" >/dev/null; eq "an empty value: exit 0" 0 $?
eq "an empty value prints nothing" "" "$(claude_md_header 'Fix Labels' "$f")"

put '# Repo\n\n## Repo Visibility: Public\n'
claude_md_header 'Fix Labels' "$f" >/dev/null; eq "an absent header: exit 1" 1 $?
claude_md_header 'Fix Labels' "$W/none.md" >/dev/null; eq "an absent file: exit 1" 1 $?

put '```markdown\n## Fix Labels: example\n```\n'
claude_md_header 'Fix Labels' "$f" >/dev/null; eq "a header inside a backtick fence is ignored" 1 $?
put '~~~\n## Fix Labels: example\n~~~\n\n## Fix Labels: regression\n'
eq "a header after a tilde fence closes is read" "regression" "$(claude_md_header 'Fix Labels' "$f")"
put '````\n```\n## Fix Labels: example\n```\n````\n## Fix Labels: real\n'
eq "a shorter run inside a longer fence doesn't close it" "real" "$(claude_md_header 'Fix Labels' "$f")"

put '## Fix Labels: bug\n\n## Fix Labels: regression\n'
claude_md_header 'Fix Labels' "$f" >/dev/null 2>&1; eq "a duplicate is refused: exit 2" 2 $?
eq "a duplicate prints no value" "" "$(claude_md_header 'Fix Labels' "$f" 2>/dev/null)"
eq "a duplicate is named on stderr" "1" "$(claude_md_header 'Fix Labels' "$f" 2>&1 >/dev/null | grep -c 'more than once')"

put '## Fix Labels: bug\r\n'
eq "a CRLF line ending is dropped" "bug" "$(claude_md_header 'Fix Labels' "$f")"
put '   ## Fix Labels: bug\n'
eq "a heading indented three spaces counts" "bug" "$(claude_md_header 'Fix Labels' "$f")"
put '### Fix Labels: bug\n'
claude_md_header 'Fix Labels' "$f" >/dev/null; eq "a level-3 heading is not a declaration" 1 $?

# --- at a commit ---------------------------------------------------------------
R="$W/repo"
mkdir -p "$R"
(
    cd "$R" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf '## Fix Labels: regression\n' > CLAUDE.md
    git add CLAUDE.md
    git commit -q -m one
    git rev-parse HEAD > "$W/c1"
    printf '## Fix Labels: chore\n' > CLAUDE.md
) || { echo "FAIL: could not build the fixture repository"; exit 1; }
C1=$(cat "$W/c1")
eq "at a commit, the committed text is read, not the working tree's" "regression" "$(cd "$R" && claude_md_header_at "$C1" 'Fix Labels')"
(cd "$R" && claude_md_header_at "$C1" 'Fix Labels' AGENTS.md >/dev/null); eq "a file absent at the commit: exit 1" 1 $?
(cd "$R" && claude_md_header_at 0123456789abcdef0123456789abcdef01234567 'Fix Labels' >/dev/null 2>&1)
eq "a commit that doesn't exist: exit 2" 2 $?

echo
echo "claude-md-header: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
