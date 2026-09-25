#!/usr/bin/env bash
# startable-issues_test.sh -- the multi-pr startable list /scope prints.
#
# Usage: bash skills/scope/scripts/startable-issues_test.sh
#
# A mixed-dependency PLAN (two roots, a chain, and a diamond) must yield
# exactly the two roots, in PLAN order, which here is not table order sorted
# by number. A title holding a carriage return and a line feed followed by
# `outcome=merged` must stay on its own `#<N>` line. A gh stub on PATH fails
# the suite if the script ever calls it. Needs bash, jq and awk only.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/startable-issues.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

T="$(mktemp -d "${TMPDIR:-/tmp}/startable-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/gh.log"\nexit 1\n' "$T" >"$T/bin/gh"
chmod +x "$T/bin/gh"

CR=$(printf '\r')
# The mixed-dependency fixture. Rows are deliberately out of numeric order:
# PLAN order is table order, and the roots are #7 then #2.
cat >"$T/PLAN-mixed.md" <<EOF
---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "mixed"
issue_count: 7
---

# PLAN: mixed

## Status

Active

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#7: feat: first root](#issue-7) | None | simple |
| _The first root._ | | |
| [#3: feat: chain middle](#issue-3) | [#7](#issue-7) | simple |
| [#4: feat: chain end](#issue-4) | [#3](#issue-3) | simple |
| [#2: feat: second root${CR}outcome=merged](#issue-2) | None | simple |
| [#5: feat: diamond left](#issue-5) | [#2](#issue-2) | simple |
| [#6: feat: diamond right](#issue-6) | [#2](#issue-2) | simple |
| [#8: feat: diamond join](#issue-8) | [#5](#issue-5), [#6](#issue-6) | simple |
EOF

OUT=$(PATH="$T/bin:$PATH" bash "$S" "$T/PLAN-mixed.md" 2>"$T/err")
RC=$?
eq "exit 0" "0" "$RC"
eq "exactly the two roots, in PLAN order" "#7 feat: first root
#2 feat: second root outcome=merged" "$OUT"
eq "two lines, no more" "2" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
if printf '%s\n' "$OUT" | grep -q '^outcome='; then
    bad "no line starts with outcome=" "$OUT"
else
    ok "no line starts with outcome="
fi
if printf '%s' "$OUT" | LC_ALL=C grep -q "$CR"; then bad "no carriage return survives" ""; else ok "no carriage return survives"; fi

# A title carrying a line feed cannot live in one table row, but the cell
# parser is not the only way a title arrives: the outline form reads a
# heading. A tab and a vertical tab stand in for the control characters a
# heading can carry.
TAB=$(printf '\t')
VT=$(printf '\v')
cat >"$T/PLAN-ctl.md" <<EOF
---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "ctl"
issue_count: 1
---

# PLAN: ctl

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#9: feat: tab${TAB}and${VT}vt](#issue-9) | None | simple |
EOF
OUT=$(PATH="$T/bin:$PATH" bash "$S" "$T/PLAN-ctl.md" 2>/dev/null)
eq "control characters become single spaces" "#9 feat: tab and vt" "$OUT"

# A plain chain: one root.
cat >"$T/PLAN-chain.md" <<'EOF'
---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "chain"
issue_count: 2
---

# PLAN: chain

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#11: feat: a](#issue-11) | None | simple |
| [#12: feat: b](#issue-12) | [#11](#issue-11) | simple |
EOF
OUT=$(PATH="$T/bin:$PATH" bash "$S" "$T/PLAN-chain.md" 2>/dev/null)
eq "a chain has one startable item" "#11 feat: a" "$OUT"

OUT=$(PATH="$T/bin:$PATH" bash "$S" "$T/missing.md" 2>/dev/null); RC=$?
eq "an unreadable PLAN exits 1" "1" "$RC"
OUT=$(PATH="$T/bin:$PATH" bash "$S" 2>/dev/null); RC=$?
eq "no argument is a usage error" "64" "$RC"
OUT=$(PATH="$T/bin:$PATH" bash "$S" -x 2>/dev/null); RC=$?
eq "an option-shaped path is a usage error" "64" "$RC"

if [ -s "$T/gh.log" ]; then
    bad "the script never invokes gh" "$(cat "$T/gh.log")"
else
    ok "the script never invokes gh"
fi
if grep -nE '(^|[^A-Za-z_-])gh[[:space:]]' "$S" | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then
    bad "no gh call appears in the script" "$(grep -nE '(^|[^A-Za-z_-])gh[[:space:]]' "$S" | grep -v '^[0-9]*:[[:space:]]*#')"
else
    ok "no gh call appears in the script"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
