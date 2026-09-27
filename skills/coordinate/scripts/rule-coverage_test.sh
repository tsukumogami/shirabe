#!/usr/bin/env bash
# rule-coverage_test.sh -- every rule of the prose /coordinate skill still has
# a carrier in the koto-based one.
#
# Reads testdata/rule-coverage.tsv: one row per rule of the pre-koto rule
# inventory, naming the file that now carries it, the coordinate.md state it
# sits in (or -), and a short verbatim phrase from it. For each row it checks
# the phrase occurs in that file and, when a state is named, inside that
# `## <state>` section of the template body. It also checks that the rows and
# the `# lost:` line together name every ID from C1 to C190 exactly once, and
# that each of the four reference files is named in at least one state
# section of coordinate.md.
#
# Usage: bash skills/coordinate/scripts/rule-coverage_test.sh
# Exit codes: 0 every check passed; 1 a check failed.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
TSV="$HERE/testdata/rule-coverage.tsv"
TEMPLATE=skills/coordinate/koto-templates/coordinate.md
TOTAL=190
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; [ -n "${2-}" ] && printf '     %s\n' "$2"; return 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/rule-coverage.XXXXXX")
trap 'rm -rf "$T"' EXIT

# The template body: everything after the frontmatter's closing `---`.
awk 'f >= 2 { print; next } /^---$/ { f++ }' "$ROOT/$TEMPLATE" > "$T/body"

# section <state>: the lines of `## <state>` up to the next `## ` heading.
section() {
    awk -v h="## $1" '$0 == h { on = 1; next } /^## / { on = 0 } on' "$T/body"
}

[ -r "$TSV" ] || { echo "FAIL fixture missing: $TSV"; echo "rule-coverage: 0 passed, 1 failed"; exit 1; }

: > "$T/ids"
while IFS=$'\t' read -r id file state phrase note; do
    case "$id" in ''|'#'*) continue ;; esac
    echo "$id" >> "$T/ids"
    label="$id $file${state:+ [$state]}"
    case "$id" in C[0-9]*) ;; *) bad "$label" "malformed ID"; continue ;; esac
    if [ -z "${phrase-}" ]; then bad "$label" "no key phrase"; continue; fi
    len=${#phrase}
    if [ "$len" -lt 8 ] || [ "$len" -gt 60 ]; then
        bad "$label" "key phrase is $len chars; want 8-60"; continue
    fi
    case "${note-}" in ''|'changed: '?*) ;; *) bad "$label" "fifth column must read 'changed: <why>'"; continue ;; esac
    if [ ! -f "$ROOT/$file" ]; then bad "$label" "no such file"; continue; fi
    if [ "$state" = - ]; then
        cp "$ROOT/$file" "$T/hay"
    elif [ "$file" = "$TEMPLATE" ]; then
        section "$state" > "$T/hay"
        if [ ! -s "$T/hay" ]; then bad "$label" "no '## $state' section"; continue; fi
    else
        bad "$label" "a state is named only for $TEMPLATE"; continue
    fi
    if grep -qF -e "$phrase" "$T/hay"; then
        ok "$label"
    else
        bad "$label" "phrase not found: $phrase"
    fi
done < "$TSV"

# Completeness: rows plus the lost list name C1..C$TOTAL, each once.
sed -n 's/^# lost://p' "$TSV" | tr ' ' '\n' | grep . > "$T/lost"
LOST=$(wc -l < "$T/lost" | tr -d ' ')
cat "$T/ids" "$T/lost" | sort > "$T/named"
i=1
: > "$T/want"
while [ "$i" -le "$TOTAL" ]; do echo "C$i" >> "$T/want"; i=$((i + 1)); done
sort "$T/want" > "$T/want.s"
dups=$(uniq -d "$T/named" | tr '\n' ' ')
[ -z "$dups" ] && ok "no rule named twice" || bad "no rule named twice" "repeated: $dups"
missing=$(grep -vxF -f "$T/named" "$T/want.s" | tr '\n' ' ')
extra=$(grep -vxF -f "$T/want.s" "$T/named" | tr '\n' ' ')
[ -z "$missing" ] && ok "every rule C1..C$TOTAL is named" || bad "every rule C1..C$TOTAL is named" "missing: $missing"
[ -z "$extra" ] && ok "no rule outside C1..C$TOTAL" || bad "no rule outside C1..C$TOTAL" "extra: $extra"

# Each reference file is named in at least one state section of the template.
awk '/^## / { on = 1 } on' "$T/body" > "$T/sections"
for ref in loop.md brief-template.md verification-checklist.md record-template.md; do
    if grep -qF -e "references/$ref" "$T/sections"; then
        ok "coordinate.md names references/$ref"
    else
        bad "coordinate.md names references/$ref"
    fi
done

# Every rule of the prose skill must be carried; a rule on the lost line fails.
if [ "$LOST" -gt 0 ]; then bad "every rule has a carrier" "no carrier yet: $(tr '\n' ' ' < "$T/lost")"; else ok "every rule has a carrier"; fi
echo; echo "rule-coverage: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ] || exit 1
