#!/usr/bin/env bash
# milestone_test.sh -- milestone.sh, the file-only reader of a milestone
# roadmap's schema and Evidence and the check of a milestone verdict entry
# (docs/designs/DESIGN-milestone-verdicts.md, Decisions 2 and 4).
#
# Covers: schema on a roadmap/v2 roadmap, on one naming roadmap/v1 and on one
# with no schema line; evidence as JSON with wrapped clause lines joined, the
# field ending at a blank line, and exit 2 for a tag that isn't a milestone
# with Evidence (no such heading, a v1 roadmap, a block with no clause, a
# block holding a code fence); check-verdict accepting one well-formed entry
# of each verdict and refusing, naming the line: a missing line, a reordered
# line, a clause count other than the milestone's, a verified verdict with a
# clause not held, with `does not fit`, with a follow-up or with a change
# named, verified with follow-ups and no follow-up, changes needed with every
# clause held and `fits` and with `Changes needed: none`, a Checked on later
# than --today, a Checked by containing the --worker topic in any letter
# case, a Checked by or Work checked outside its closed shape, a follow-up
# title with markdown in it, and an entry over 16 KiB; progress-has.
#
# Usage: bash skills/coordinate/scripts/milestone_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
MS="$HERE/milestone.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/milestone-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

cat > "$T/v2.md" <<'EOF'
---
schema: roadmap/v2
status: Active
---

# ROADMAP: widgets

## Features

### MV1: the plugin list

**Outcome:** A maintainer lists the plugins they installed.

**Evidence:**
- A reviewer, from a clean install with three sample plugins, runs
  `widgets list` and sees exactly those three names.
- The same reviewer removes one manifest and sees it named as skipped.

**Left open:** the output layout.

**Dependencies:** None
**Status:** In progress

### MV2: the host serves

**Outcome:** The host answers.

**Evidence:**
- An operator curls the host and gets a 200.
**Left open:** None

**Dependencies:** MV1
**Status:** Not started

### MV3: no clause

**Outcome:** Nothing to check.

**Evidence:**

**Dependencies:** None
**Status:** Not started

### MV4: fenced

**Evidence:**
- one
```
code
```
**Status:** Not started

## Progress

- 2026-10-01: MV1 started
EOF
printf -- '---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Features\n\n### Feature 1: one\n**Dependencies:** None\n**Status:** In progress\n' > "$T/v1.md"
printf -- '---\nstatus: Active\n---\n\n## Features\n\n### Feature 1: one\n**Status:** In progress\n' > "$T/v0.md"

echo "== schema =="
eq "a roadmap/v2 roadmap" roadmap/v2 "$(bash "$MS" schema "$T/v2.md")"
eq "a roadmap/v1 roadmap" roadmap/v1 "$(bash "$MS" schema "$T/v1.md")"
eq "a roadmap with no schema line reads as roadmap/v1" roadmap/v1 "$(bash "$MS" schema "$T/v0.md")"
bash "$MS" schema "$T/none.md" >/dev/null 2>&1; eq "an unreadable roadmap is 2" 2 $?

echo "== evidence =="
OUT=$(bash "$MS" evidence "$T/v2.md" MV1); rc=$?
eq "MV1's evidence reads" 0 $rc
eq "  ... its title and status" "the plugin list|In progress|roadmap/v2" "$(printf '%s' "$OUT" | jq -r '"\(.title)|\(.status)|\(.schema)"')"
eq "  ... two clauses, the wrapped line joined" \
    '["A reviewer, from a clean install with three sample plugins, runs `widgets list` and sees exactly those three names.","The same reviewer removes one manifest and sees it named as skipped."]' \
    "$(printf '%s' "$OUT" | jq -c .evidence)"
eq "a field line ends the Evidence" '["An operator curls the host and gets a 200."]' "$(bash "$MS" evidence "$T/v2.md" MV2 | jq -c .evidence)"
bash "$MS" evidence "$T/v2.md" MV9 >/dev/null 2>&1; eq "a tag no heading carries is 2" 2 $?
bash "$MS" evidence "$T/v2.md" MV3 >/dev/null 2>&1; eq "a milestone with no clause is 2" 2 $?
bash "$MS" evidence "$T/v2.md" MV4 >/dev/null 2>"$T/err"; eq "a block holding a code fence is 2" 2 $?
grep -q 'code fence' "$T/err" && ok "  ... saying why" || bad "  ... saying why" "$(cat "$T/err")"
bash "$MS" evidence "$T/v1.md" "Feature 1" >/dev/null 2>"$T/err"; eq "a v1 roadmap has no milestones: 2" 2 $?

echo "== progress-has =="
bash "$MS" progress-has "$T/v2.md" "MV1 started"; eq "text in Progress is found" 0 $?
bash "$MS" progress-has "$T/v2.md" "the plugin list"; eq "text elsewhere isn't" 1 $?

echo "== check-verdict =="
SRC="Source: docs/roadmaps/ROADMAP-widgets.md at 1111111111111111111111111111111111111111"
entry() { # entry <verdict> <c1> <c2> <fit> <follow-ups> <changes> [checked-by] [checked-on] [work]
    printf 'Verdict: MV1 -- %s\nChecked by: %s\nChecked on: %s\n%s\nWork checked: %s\n\nEvidence:\n1. %s -- ran widgets list and saw three\n2. %s -- removed a manifest\n\nStrategy fit: %s -- it serves the plugin bet\nFollow-ups: %s\nChanges needed: %s\n' \
        "$1" "${7:-coordinate-widgets-20261010T000000Z}" "${8:-2026-10-09}" "$SRC" "${9:-acme/widgets#12, acme/widgets#14}" "$2" "$3" "$4" "$5" "$6"
}
check() { bash "$MS" check-verdict "$T/v2.md" MV1 "$T/e.txt" --worker plugin-list --today 2026-10-10 2>"$T/err"; }
accept() { # accept <label> <entry args...>
    local l=$1; shift
    entry "$@" > "$T/e.txt"; check > "$T/out"; eq "$l" 0 $?
}
refuse() { # refuse <label> <stderr phrase> <entry args...>
    local l=$1 p=$2; shift 2
    entry "$@" > "$T/e.txt"; check > /dev/null; local rc=$?
    if [ $rc = 1 ] && grep -q -- "$p" "$T/err"; then ok "$l"; else bad "$l" "rc $rc: $(cat "$T/err")"; fi
}
accept "a verified entry passes" verified held held fits none none
eq "  ... printed as JSON" "verified|coordinate-widgets-20261010T000000Z|2|acme/widgets#12,acme/widgets#14|1111111111111111111111111111111111111111" \
    "$(jq -r '"\(.verdict)|\(.checked_by)|\(.clauses | length)|\(.work_checked | join(","))|\(.source.commit)"' "$T/out")"
accept "a verified-with-follow-ups entry passes" "verified with follow-ups" held held fits "new: a plugin search; amend MV2: name the port" none
eq "  ... its follow-ups parsed" '[{"kind":"new","title":"a plugin search"},{"kind":"amend","tag":"MV2","what":"name the port"}]' "$(jq -c .follow_ups "$T/out")"
accept "a changes-needed entry passes" "changes needed" held "not held" fits none "name the skipped plugin"
accept "changes needed with every clause held but not fitting passes" "changes needed" held held "does not fit" none "drop the extra flag"
accept "Work checked none passes" verified held held fits none none "" "" none
refuse "a verified verdict with a clause not held" "line 1: verified needs every clause held" verified held "not held" fits none none
refuse "a verified verdict that does not fit" "line 11: verified needs the work to fit" verified held held "does not fit" none none
refuse "a verified verdict with a follow-up" "line 12: verified names no follow-up" verified held held fits "new: a search" none
refuse "a verified verdict with a change named" "line 13: verified names no change" verified held held fits none "rename it"
refuse "verified with follow-ups and no follow-up" "line 12: verified with follow-ups names at least one" "verified with follow-ups" held held fits none none
refuse "changes needed with every clause held and fits" "line 1: changes needed needs a clause not held" "changes needed" held held fits none "x"
refuse "changes needed with Changes needed: none" "line 13: changes needed names what must change" "changes needed" held "not held" fits none none
refuse "a Checked on later than today" "line 3: Checked on 2026-10-11 is later than today" verified held held fits none none "" 2026-10-11
refuse "a Checked by naming the worker" "line 2: Checked by names plugin-list" verified held held fits none none "relayed from Plugin-List"
refuse "a Checked by with a slash" "line 2: Checked by is a login" verified held held fits none none "wip/me"
refuse "a Work checked item that isn't owner/repo#n" "line 5: Work checked is" verified held held fits none none "" "" "#12"
refuse "a follow-up title with markdown" "line 12: a new follow-up's title holds" "verified with follow-ups" held held fits "new: [a link](x)" none
refuse "a follow-up that is neither new nor amend" "line 12: a follow-up is" "verified with follow-ups" held held fits "later: x" none
entry verified held held fits none none | sed 's/^Verdict: MV1/Verdict: MV2/' > "$T/e.txt"; check >/dev/null
[ $? = 1 ] && grep -q 'line 1: the verdict names MV2' "$T/err" && ok "a verdict naming another milestone is refused" || bad "a verdict naming another milestone is refused" "$(cat "$T/err")"
entry verified held held fits none none | sed '/^Checked on:/d' > "$T/e.txt"; check >/dev/null
[ $? = 1 ] && grep -q 'line 3: expected `Checked on' "$T/err" && ok "a missing line is refused, naming it" || bad "a missing line is refused, naming it" "$(cat "$T/err")"
entry verified held held fits none none | awk 'NR == 2 { l = $0; next } NR == 3 { print; print l; next } { print }' > "$T/e.txt"; check >/dev/null
[ $? = 1 ] && grep -q 'line 2: expected `Checked by' "$T/err" && ok "a reordered line is refused, naming it" || bad "a reordered line is refused, naming it" "$(cat "$T/err")"
entry verified held held fits none none | sed '/^2\. held/d' > "$T/e.txt"; check >/dev/null
[ $? = 1 ] && grep -q 'line 8: the entry judges 1 clause(s); MV1.s Evidence at Source has 2' "$T/err" && ok "a clause count other than the milestone's is refused" || bad "a clause count other than the milestone's is refused" "$(cat "$T/err")"
entry verified held held fits none none | sed 's/^2\. held -- removed a manifest/2. held -- removed a manifest\n3. held -- more/' | awk '{ gsub(/\\n/, "\n"); print }' > "$T/e.txt"; check >/dev/null
[ $? = 1 ] && grep -q 'line 8: the entry judges 3 clause(s)' "$T/err" && ok "  ... more clauses too" || bad "  ... more clauses too" "$(cat "$T/err")"
entry verified held held fits none none | sed 's/^2\. held/3. held/' > "$T/e.txt"; check >/dev/null
[ $? = 1 ] && grep -q 'line 9: clause 3 where clause 2 belongs' "$T/err" && ok "a misnumbered clause is refused" || bad "a misnumbered clause is refused" "$(cat "$T/err")"
{ entry verified held held fits none none; echo "Note: more"; } > "$T/e.txt"; check >/dev/null
[ $? = 1 ] && grep -q 'line 14: nothing follows Changes needed' "$T/err" && ok "a line after Changes needed is refused" || bad "a line after Changes needed is refused" "$(cat "$T/err")"
entry verified held held fits none none | sed 's/$/\r/' > "$T/e.txt"; check >/dev/null
[ $? = 1 ] && grep -q 'control character' "$T/err" && ok "CRLF line endings are refused" || bad "CRLF line endings are refused" "$(cat "$T/err")"
{ entry verified held held fits none none; head -c 17000 /dev/zero | tr '\0' 'x'; echo; } > "$T/e.txt"; check >/dev/null
[ $? = 1 ] && grep -q 'over 16384' "$T/err" && ok "an entry over 16 KiB is refused" || bad "an entry over 16 KiB is refused" "$(cat "$T/err")"
entry verified held held fits none none > "$T/e.txt"
bash "$MS" check-verdict "$T/v2.md" MV1 "$T/e.txt" --today 2026-10-10 >/dev/null 2>&1; eq "with no --worker, no topic is compared" 0 $?
bash "$MS" check-verdict "$T/v2.md" MV9 "$T/e.txt" --today 2026-10-10 >/dev/null 2>&1; eq "a tag that isn't a milestone is 2" 2 $?
bash "$MS" check-verdict "$T/v2.md" "not a tag" "$T/e.txt" >/dev/null 2>&1; eq "a malformed tag is 64" 64 $?
bash "$MS" frobnicate >/dev/null 2>&1; eq "an unknown subcommand is 64" 64 $?

echo
echo "milestone: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
