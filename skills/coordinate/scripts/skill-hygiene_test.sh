#!/usr/bin/env bash
# skill-hygiene_test.sh -- nothing the coordinate skill ships names a
# workflow-staging path, a private repository, a session or request id, a
# workspace instance, or a UUID.
#
# Scans every file git tracks under skills/coordinate except *_test.sh, whose
# fixtures carry such strings on purpose to prove the renderer refuses them.
# One finding per matching line, then a count; exits 1 on any finding.
#
# Usage: bash skills/coordinate/scripts/skill-hygiene_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SKILL=$(cd "$HERE/.." && pwd)
ROOT=$(git -C "$SKILL" rev-parse --show-toplevel) || { echo "FAIL not in a git work tree"; exit 1; }

# label<TAB>extended regex
PATTERNS='staging path	(^|[^A-Za-z0-9_])wip/
private repository	dot-niwa-overlay|coding-tools|tsukumogami/(vision|tools)([^A-Za-z0-9_-]|$)|private/(vision|tools|coding-tools)
UUID	[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}
request id	req-[0-9a-f]{8}-
instance name	[A-Za-z0-9_-]+\+[A-Za-z0-9_]+-[0-9a-f]{8}
session socket	cc-socks/'

PASS=0 FAIL=0
FILES=$(cd "$ROOT" && git ls-files -- skills/coordinate | grep -v '_test\.sh$')
while IFS='	' read -r label re; do
    [ -n "$label" ] || continue
    HITS=$(cd "$ROOT" && printf '%s\n' "$FILES" | while IFS= read -r f; do
        [ -f "$f" ] || continue
        grep -nE -- "$re" "$f" | sed "s|^|$f:|"
    done)
    if [ -n "$HITS" ]; then
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n' "$label"
        printf '%s\n' "$HITS" | cut -c1-200 | sed 's/^/     /'
    else
        PASS=$((PASS + 1))
        printf 'ok   no %s\n' "$label"
    fi
done <<< "$PATTERNS"

# The patterns catch what they claim: each fires on a sample.
T=$(mktemp -d "${TMPDIR:-/tmp}/skill-hygiene.XXXXXX")
trap 'rm -rf "$T"' EXIT
printf '%s\n' 'see wip/notes.md' 'from dot-niwa-overlay' 'w-6f1c2e3a-1b2c-4d5e-8f90-123456789abc' \
    'req-cb2ae3c7-e66f' 'tsuku+coordinate_record-43e4a66f' '/run/user/1/cc-socks/1.sock' > "$T/sample"
N=$(printf '%s\n' "$PATTERNS" | cut -f2 | while IFS= read -r re; do grep -cE -- "$re" "$T/sample"; done | awk '$1 > 0' | wc -l | tr -d ' ')
if [ "$N" = 6 ]; then PASS=$((PASS + 1)); echo "ok   every pattern fires on its sample"
else FAIL=$((FAIL + 1)); echo "FAIL only $N of 6 patterns fire on their samples"; fi

echo
echo "skill-hygiene: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
