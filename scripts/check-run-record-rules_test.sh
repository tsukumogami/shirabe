#!/usr/bin/env bash
# check-run-record-rules_test.sh -- scripts/check-run-record-rules.sh
#
# On a planted tree (--root), the check fails, naming its rule, on:
#   a `koto session unpin` call in a skill's script, and in a skill's prose
#   a `koto config set` of a retention key, and a prune given --older-than
#   a skill paragraph telling the reader to run `koto session prune` or
#   `koto session cleanup` without saying pinned sessions are kept
# and passes on: the same paragraph once it says so, a test suite or test
# data that sets a scratch store's retention, and anything under
# skills/coordinate/. It also passes on the repository as it stands, and
# refuses an unknown flag or a missing root (64).
#
# The planted patterns are built from parts, so this file itself never holds
# one whole.
#
# Usage: check-run-record-rules_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-run-record-rules.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-run-record-rules-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

K="koto session"
UNPIN="$K un""pin"
PRUNE="$K prune"
CLEANUP="$K cleanup"
SETRET="koto config set --user retention"".keep 30d"
OLDER="--older""-than 7d"

# tree <name>: a fresh planted tree with one clean skill.
tree() {
    T="$WORK/$1"
    mkdir -p "$T/skills/demo/scripts" "$T/scripts" "$T/skills/coordinate"
    printf '# Demo\n\nNothing to see.\n' > "$T/skills/demo/SKILL.md"
    printf '#!/usr/bin/env bash\necho ok\n' > "$T/skills/demo/scripts/run.sh"
}
check() { # check <tree dir>
    OUT=$(bash "$CHECK" --root "$1" 2>"$WORK/stderr")
    RC=$?
}
fails_on() { # fails_on <label> <rule>
    if [ "$RC" -eq 1 ] && grep -q "^$2: " <<<"$OUT"; then
        pass "$1: exit 1 naming $2"
    else
        fail "$1: exit $RC, out [$OUT], stderr [$(cat "$WORK/stderr")]"
    fi
}
passes() { # passes <label>
    if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
        pass "$1: clean"
    else
        fail "$1: exit $RC, out [$OUT]"
    fi
}

tree clean
check "$T"
passes "a tree with no koto call"

tree unpin-script
printf '#!/usr/bin/env bash\n%s execute-x\n' "$UNPIN" > "$T/skills/demo/scripts/release.sh"
check "$T"
fails_on "a planted unpin call in a skill script" run-record/unpin

tree unpin-prose
printf '# Demo\n\nWhen done, run `%s execute-x` to free it.\n' "$UNPIN" > "$T/skills/demo/SKILL.md"
check "$T"
fails_on "a planted unpin instruction in a skill" run-record/unpin

tree unpin-scripts-dir
printf '#!/usr/bin/env bash\n%s "$1"\n' "$UNPIN" > "$T/scripts/tidy.sh"
check "$T"
fails_on "a planted unpin call in scripts/" run-record/unpin

tree retention
printf '#!/usr/bin/env bash\n%s\n' "$SETRET" > "$T/skills/demo/scripts/setup.sh"
check "$T"
fails_on "a planted retention window (koto config set of a retention key)" run-record/retention-window

tree older-than
printf '#!/usr/bin/env bash\n%s --apply %s\n' "$PRUNE" "$OLDER" > "$T/scripts/sweep.sh"
check "$T"
fails_on "a planted retention window (a prune given --older-than)" run-record/retention-window

tree prune-prose
printf '# Demo\n\nTo tidy up, run `%s --apply --all`\nonce the run is finished.\n\nNext.\n' "$PRUNE" > "$T/skills/demo/SKILL.md"
check "$T"
fails_on "a planted prune instruction that doesn't say pinned sessions are kept" run-record/prune-unpinned
grep -q 'skills/demo/SKILL.md:3:' <<<"$OUT" && pass "the finding names the paragraph's first line" \
    || fail "the finding's line: [$OUT]"

tree cleanup-prose
printf '# Demo\n\n- Remove it with\n  `%s execute-x`.\n' "$CLEANUP" > "$T/skills/demo/references.md"
check "$T"
fails_on "a planted cleanup instruction in a skill reference that doesn't say pinned sessions are kept" run-record/prune-unpinned

tree prune-pinned
printf '# Demo\n\nTo tidy up, run `%s --apply --all`; a pinned session\nis kept, so the run record stays.\n' "$PRUNE" > "$T/skills/demo/SKILL.md"
check "$T"
passes "a prune instruction whose paragraph says pinned sessions are kept"

tree exempt
printf '#!/usr/bin/env bash\n%s\n%s execute-x\n' "$SETRET" "$UNPIN" > "$T/skills/demo/scripts/scratch_test.sh"
mkdir -p "$T/scripts/testdata"
printf '%s\n' "$UNPIN" > "$T/scripts/testdata/stub"
printf '# Coordinate\n\nRun `%s --apply --all`.\n\n%s x\n' "$PRUNE" "$UNPIN" > "$T/skills/coordinate/SKILL.md"
check "$T"
passes "a test suite, test data and skills/coordinate/ are not policed"

check "$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)"
passes "the repository as it stands"

OUT=$(bash "$CHECK" --bogus 2>/dev/null); RC=$?
[ "$RC" -eq 64 ] && pass "an unknown flag is 64" || fail "unknown flag: exit $RC"
OUT=$(bash "$CHECK" --root "$WORK/missing" 2>/dev/null); RC=$?
[ "$RC" -eq 64 ] && pass "a missing root is 64" || fail "missing root: exit $RC"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
