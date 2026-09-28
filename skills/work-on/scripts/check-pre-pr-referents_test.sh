#!/usr/bin/env bash
# check-pre-pr-referents_test.sh -- the pre_pr.md referents must exist, not
# only look like referents.
#
# Drives check-pre-pr-referents.sh directly against a fixture repository with
# real commits and a real koto session holding pre_pr.md. The template-level
# cases, where the same script runs as a gate, are in pre-pr-evidence_test.sh
# and finalization-shape_test.sh.
#
#   cleanup_commit: HEAD, abbreviated HEAD and an ancestor pass; a sha that
#   names no object (the mistyped full sha from shirabe#422), a commit on
#   another branch, a placeholder, an uppercase sha, a second line, and a key
#   that does not start its line fail.
#   design_diagram: a committed docs/ file and not-applicable with a reason
#   pass; a missing path, a path present only in the working tree, a directory,
#   the enum spelling, and not-applicable without a reason fail.
#   Fail closed: an absent pre_pr.md, an unknown session, and bad arguments
#   exit 1, and no case exits with anything but 0 or 1.
#
# Usage: check-pre-pr-referents_test.sh
# Exit codes: 0 all pass, or koto/git absent and the run skipped; 1 any failed.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SUT="$SCRIPT_DIR/check-pre-pr-referents.sh"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

command -v koto >/dev/null 2>&1 || { echo "SKIP: koto not on PATH -- no case ran"; exit 0; }
command -v git  >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }
[ -x "$SUT" ] || { echo "FAIL: $SUT is not executable" >&2; exit 1; }

WORKDIR=$(mktemp -d)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# Keep every session out of the developer's real ~/.koto.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"

# main: init, then a commit adding the design doc and a directory named like
# one. A side branch carries a commit main never sees. HEAD ends on main, with
# an untracked docs file that exists only in the working tree.
REPO="$WORKDIR/repo"
mkdir -p "$REPO"
cd "$REPO" || exit 1
git init -q -b main .
git config user.email t@example.com
git config user.name t
git commit -q --allow-empty -m init
ANCESTOR=$(git rev-parse HEAD)
git checkout -q -b other
git commit -q --allow-empty -m "side work"
OTHER=$(git rev-parse HEAD)
git checkout -q main
mkdir -p docs/designs docs/dir.md
echo diagram > docs/designs/DESIGN-thing.md
echo x > docs/dir.md/inner.txt
git add docs
git commit -q -m "docs: add design"
HEAD_SHA=$(git rev-parse HEAD)
echo draft > docs/designs/DESIGN-draft.md

# A mistyped full sha: HEAD's first seven characters and nothing behind them.
MISTYPED="${HEAD_SHA:0:7}aaa9d49d45e7453fce2d9cc39537bbd5e"
[ "${#MISTYPED}" -eq 40 ] || { echo "FAIL: fixture sha is ${#MISTYPED} characters, not 40" >&2; exit 1; }

cat > "$WORKDIR/t.md" <<'EOF'
---
name: referents-fixture
version: "1.0"
description: Holds a pre_pr.md for check-pre-pr-referents.sh.
initial_state: s
states:
  s:
    terminal: true
---
## s
Holder.
EOF
SESSION=referents
koto init "$SESSION" --template "$WORKDIR/t.md" >/dev/null 2>&1 \
    || { echo "FAIL: koto init failed" >&2; exit 1; }

# expect <want-exit> <mode> <description> [pre_pr.md body]
# With no body, pre_pr.md is removed first, so the case reads an absent key.
expect() {
    local want="$1" mode="$2" desc="$3" got
    if [ "$#" -ge 4 ]; then
        printf '%s\n' "$4" | koto context add "$SESSION" pre_pr.md >/dev/null
    else
        koto context remove "$SESSION" pre_pr.md >/dev/null
    fi
    "$SUT" "$mode" "$SESSION" 2>"$WORKDIR/err"
    got=$?
    if [ "$got" = "$want" ]; then
        pass "$desc (exit $got)"
    else
        fail "$desc: expected exit $want, got $got; stderr: $(head -c 300 "$WORKDIR/err")"
    fi
}
# reason <pattern>: the case just run failed for the reason it was meant to,
# not on an earlier check.
reason() {
    if grep -qE "$1" "$WORKDIR/err"; then
        pass "  ...and stderr names the reason [$1]"
    else
        fail "  expected stderr to match [$1]; got: $(head -c 300 "$WORKDIR/err")"
    fi
}
NA='design_diagram: not-applicable: no design document is touched'

echo "--- cleanup_commit"
expect 0 --cleanup "the full HEAD sha passes" "cleanup_commit: $HEAD_SHA
$NA"
expect 0 --cleanup "an abbreviated HEAD sha passes" "cleanup_commit: ${HEAD_SHA:0:7}
$NA"
expect 0 --cleanup "an ancestor of HEAD passes" "cleanup_commit: $ANCESTOR
$NA"
# Built with printf so the trailing blanks and the CR survive any editor.
TRAILING=$(printf 'cleanup_commit: %s  \t\r\n%s\r' "$HEAD_SHA" "$NA")
expect 0 --cleanup "trailing blanks and a CR after the sha are ignored" "$TRAILING"
expect 0 --diagram "a CR after the not-applicable reason is ignored" "$TRAILING"
expect 1 --cleanup "a sha that names no object fails" "cleanup_commit: $MISTYPED
$NA"
reason "does not name a commit"
expect 1 --cleanup "a commit from another branch fails" "cleanup_commit: $OTHER
$NA"
reason "not HEAD or an ancestor"
expect 1 --cleanup "a placeholder word fails" "cleanup_commit: done
$NA"
expect 1 --cleanup "an uppercase sha fails the shape" "cleanup_commit: $(printf '%s' "$HEAD_SHA" | tr 'a-f' 'A-F')
$NA"
expect 1 --cleanup "text after the sha fails the shape" "cleanup_commit: $HEAD_SHA (reviewed)
$NA"
expect 1 --cleanup "two cleanup_commit lines fail" "cleanup_commit: $HEAD_SHA
cleanup_commit: $ANCESTOR
$NA"
expect 1 --cleanup "a cleanup_commit that does not start its line fails" "note cleanup_commit: $HEAD_SHA
$NA"
expect 1 --cleanup "no cleanup_commit line fails" "$NA"

echo "--- design_diagram"
C="cleanup_commit: $HEAD_SHA"
expect 0 --diagram "a committed docs/ path passes" "$C
design_diagram: docs/designs/DESIGN-thing.md"
expect 0 --diagram "not-applicable with a reason passes" "$C
$NA"
expect 1 --diagram "a docs/ path that does not exist fails" "$C
design_diagram: docs/designs/DESIGN-missing.md"
reason "not in HEAD.s tree"
expect 1 --diagram "a path present only in the working tree fails" "$C
design_diagram: docs/designs/DESIGN-draft.md"
reason "not in HEAD.s tree"
expect 1 --diagram "a directory named like a doc fails" "$C
design_diagram: docs/dir.md"
reason "is a tree"
expect 1 --diagram "a path outside docs/ fails the shape" "$C
design_diagram: README.md"
expect 1 --diagram "the evidence enum spelling fails" "$C
design_diagram: not_applicable"
expect 1 --diagram "not-applicable without a reason fails" "$C
design_diagram: not-applicable:"
expect 1 --diagram "a placeholder word fails" "$C
design_diagram: yes"
expect 1 --diagram "two design_diagram lines fail" "$C
design_diagram: docs/designs/DESIGN-thing.md
$NA"

echo "--- fail closed"
expect 1 --cleanup "an absent pre_pr.md fails --cleanup"
reason "could not read pre_pr.md"
expect 1 --diagram "an absent pre_pr.md fails --diagram"
reason "could not read pre_pr.md"
printf '%s\n' "$C" "$NA" | koto context add "$SESSION" pre_pr.md >/dev/null
for args in "--cleanup no-such-session" "--bogus $SESSION" "--cleanup" "" "--cleanup $SESSION extra"; do
    # shellcheck disable=SC2086
    "$SUT" $args 2>/dev/null
    got=$?
    if [ "$got" = 1 ]; then
        pass "arguments [$args] exit 1"
    else
        fail "arguments [$args]: expected exit 1, got $got"
    fi
done

cd "$WORKDIR" || exit 1
"$SUT" --cleanup "$SESSION" 2>/dev/null
got=$?
if [ "$got" = 1 ]; then
    pass "outside a git repository exits 1"
else
    fail "outside a git repository: expected exit 1, got $got"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
