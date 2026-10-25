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
# The lifecycle rule (run-record/lifecycle), on a tree whose seven lifecycle
# documents are planted clean: it fails, naming the document, on a PLAN that
# stays in docs/plans/ through every state (wrapped over two lines, and in
# run-cascade.sh's header), a Done table row calling it terminal, a Plan or
# Roadmap row whose last cell is Done, prose saying Done is terminal, a
# historical record and an audit record, a document not naming the lookup,
# a shell header that names it only below the header, and a missing
# document; it passes on a stale-looking comment below run-cascade.sh's
# header, which is code, not the header.
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

LOOKUP="scripts/run-record""-lookup.sh"
LIFECYCLE_MD="skills/plan/references/plan-format.md
skills/plan/SKILL.md
skills/plan/references/quality/plan-doc-structure.md
skills/roadmap/references/roadmap-format.md
skills/roadmap/SKILL.md
references/pipeline-model.md"
CASCADE="skills/work-on/scripts/run-cascade.sh"

# tree <name>: a fresh planted tree with one clean skill and the seven
# lifecycle documents, each clean.
tree() {
    T="$WORK/$1"
    mkdir -p "$T/skills/demo/scripts" "$T/scripts" "$T/skills/coordinate"
    printf '# Demo\n\nNothing to see.\n' > "$T/skills/demo/SKILL.md"
    printf '#!/usr/bin/env bash\necho ok\n' > "$T/skills/demo/scripts/run.sh"
    local d
    while IFS= read -r d; do
        mkdir -p "$T/$(dirname "$d")"
        printf '# Doc\n\nDeleted when its work finishes. A later reader runs\n`%s <owner/repo> <n>`.\n' "$LOOKUP" > "$T/$d"
    done <<<"$LIFECYCLE_MD"
    mkdir -p "$T/$(dirname "$CASCADE")"
    printf '#!/usr/bin/env bash\n# The completion step. See %s.\n\nset -e\n' "$LOOKUP" > "$T/$CASCADE"
}
# plant <doc> <text>: add a paragraph to a planted lifecycle document.
plant() { printf '\n%s\n' "$2" >> "$T/$1"; }
names() { # names <label> <doc>: the lifecycle finding names the document
    if grep -q "^run-record/lifecycle: $2:" <<<"$OUT"; then
        pass "$1: the finding names $2"
    else
        fail "$1: no finding naming $2 in [$OUT]"
    fi
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

# The lifecycle rule. The stale phrases are built from parts.
EVERY="through every"" state"
TERM="Terminal"" state"

tree stays-wrapped
plant skills/plan/references/plan-format.md "$(printf 'The PLAN\nstays in `docs/plans/` %s.' "$EVERY")"
check "$T"
fails_on "a PLAN that stays through every state, wrapped over two lines" run-record/lifecycle
names "stays through every state" skills/plan/references/plan-format.md

tree done-row
plant skills/plan/references/plan-format.md "| Done | All issues complete. $TERM. |"
check "$T"
fails_on "a Done table row calling it terminal" run-record/lifecycle

tree plan-row
plant references/pipeline-model.md "| Plan | Draft -> Active -> Done | Done |"
check "$T"
fails_on "a Plan row whose last cell is Done" run-record/lifecycle
names "a Plan row ending in Done" references/pipeline-model.md

tree roadmap-row
plant skills/roadmap/references/roadmap-format.md "| Roadmap | Draft -> Active -> Done | Done |"
check "$T"
fails_on "a Roadmap row whose last cell is Done" run-record/lifecycle

tree done-prose
plant skills/roadmap/SKILL.md "Once every feature lands, Done is the ROADMAP's $(printf '%s' "$TERM" | tr 'T' 't')."
check "$T"
fails_on "prose saying Done is the ROADMAP's terminal state" run-record/lifecycle
names "Done as terminal in prose" skills/roadmap/SKILL.md

tree historical
plant skills/roadmap/references/roadmap-format.md "$(printf 'A completed roadmap is a historical\nrecord.')"
check "$T"
fails_on "a roadmap kept as a historical record" run-record/lifecycle

tree audit
plant skills/plan/SKILL.md "The finished PLAN is kept as an audit"" record."
check "$T"
fails_on "a PLAN kept as an audit record" run-record/lifecycle
names "an audit record" skills/plan/SKILL.md

tree no-lookup
printf '# Doc\n\nDeleted when its work finishes.\n' > "$T/skills/plan/references/quality/plan-doc-structure.md"
check "$T"
fails_on "a lifecycle document that doesn't name the lookup" run-record/lifecycle
names "no lookup" skills/plan/references/quality/plan-doc-structure.md

tree cascade-header
printf '#!/usr/bin/env bash\n# See %s.\n# The PLAN stays in docs/plans/ %s.\nset -e\n' "$LOOKUP" "$EVERY" > "$T/$CASCADE"
check "$T"
fails_on "a stale claim in run-cascade.sh's header" run-record/lifecycle
names "the cascade header" "$CASCADE"

tree cascade-body
printf '#!/usr/bin/env bash\n# See %s.\nset -e\n# The PLAN stays in docs/plans/ %s.\n' "$LOOKUP" "$EVERY" > "$T/$CASCADE"
check "$T"
passes "a stale-looking comment below run-cascade.sh's header"

tree cascade-lookup-below
printf '#!/usr/bin/env bash\n# The completion step.\nset -e\n# See %s.\n' "$LOOKUP" > "$T/$CASCADE"
check "$T"
fails_on "run-cascade.sh naming the lookup only below its header" run-record/lifecycle

tree missing-doc
rm -f "$T/references/pipeline-model.md"
check "$T"
fails_on "a missing lifecycle document" run-record/lifecycle
names "a missing document" references/pipeline-model.md

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
