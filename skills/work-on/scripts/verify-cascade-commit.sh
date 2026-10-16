#!/usr/bin/env bash
# verify-cascade-commit.sh — did the cascade actually land, in the commit?
#
# The cascade script reports its own verdict, and that verdict is not evidence.
# Several of its operations report step-level `ok` having changed nothing, and
# its own post-cascade verification reads the WORKING TREE: a document
# transitioned on disk but never staged into the finalization commit satisfies
# every check it makes. That is not a hypothetical failure mode, it is the one
# its staging defect produces. So the three facts that constitute a completed
# cascade are established here instead, and the third is read from the commit's
# own path list rather than from the tree:
#
#   1. the anchor (the PLAN) is gone from disk;
#   2. every upstream document in its chain is at its terminal posture;
#   3. the finalization commit CONTAINS each of those documents.
#
# Fact 3 is the whole reason this script exists. Facts 1 and 2 are true of a
# tree where someone edited the files and forgot to commit them.
#
# Usage: verify-cascade-commit.sh <plan-path>
#
# Exit codes are deliberately per-cause rather than a single failure value.
# koto discards a failed gate's output, so a caller routing on this gate sees
# the exit code and nothing else. One shared failure code would make "the PLAN
# was never deleted", "nothing was ever committed" and "a document was
# transitioned but not staged" arrive identically in the record, which is the
# defect where an unbounded command with discarded stderr makes a catastrophe
# and a timeout indistinguishable (tsukumogami/shirabe#376). Distinguishing them
# costs four integers.
#
#   0 — all three facts hold.
#   2 — the PLAN is still on disk: the cascade did not delete its anchor.
#   3 — no commit in this history deletes the PLAN: nothing was finalized.
#   4 — a chain document is not at its terminal posture.
#   5 — a chain document IS at its terminal posture on disk but is ABSENT from
#       the finalization commit. The staging defect, exactly.
#   6 — could not decide (not a git repository, unreadable chain, malformed
#       frontmatter). Never silently treated as success.
#
# Diagnostics go to stderr for a human reading a failed run directly. They do
# NOT reach koto, which is why the exit code carries the meaning.
#
# git's OWN stderr is deliberately not discarded either. A `2>/dev/null` on the
# calls below would silence the one line that says which of several causes fired
# — a missing object, a bad ref, a directory that is not a repository — and this
# script exists because a check that cannot tell its failure modes apart is worth
# little. The exit code carries the decision; git's message carries the detail a
# human needs to act on, and something has to keep it.

set -uo pipefail

PLAN_DOC="${1:-}"

die() { echo "verify-cascade-commit: $*" >&2; }

if [[ -z "$PLAN_DOC" ]]; then
    die "usage: verify-cascade-commit.sh <plan-path>"
    exit 6
fi

if ! git rev-parse --git-dir >/dev/null; then
    die "not a git repository"
    exit 6
fi

# --- Fact 1: the anchor is gone from disk ------------------------------------
if [[ -e "$PLAN_DOC" ]]; then
    die "the PLAN is still on disk: $PLAN_DOC"
    die "the cascade did not delete its anchor, whatever it reported."
    exit 2
fi

# --- The finalization commit: the one that deleted the anchor ----------------
# Identified by what it did rather than by being HEAD, so a later commit on the
# branch does not move the target and an amended history still resolves.
FINAL_SHA=$(git log --diff-filter=D -n1 --format=%H -- "$PLAN_DOC")
if [[ -z "$FINAL_SHA" ]]; then
    die "no commit in this history deletes $PLAN_DOC"
    die "the PLAN is absent from the tree but its deletion was never committed."
    exit 3
fi

# The commit's OWN paths. This is the line the whole script exists for: it reads
# what the commit contains, not what the tree happens to hold now.
COMMIT_PATHS=$(git diff-tree --no-commit-id --name-only -r "$FINAL_SHA")
if [[ -z "$COMMIT_PATHS" ]]; then
    die "could not list the paths of commit $FINAL_SHA"
    exit 6
fi

# --- The chain: walk `upstream:` up from the PLAN ----------------------------
# The PLAN is deleted, so its own frontmatter is read from the finalization
# commit's PARENT, where it still exists.
read_field() {
    # read_field <text> <field> — first value of a top-level frontmatter scalar.
    printf '%s\n' "$1" | awk -v f="$2" '
        NR == 1 && $0 == "---" { infm = 1; next }
        infm && $0 == "---" { exit }
        infm && $0 ~ "^" f ":" {
            sub("^" f ":[[:space:]]*", "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            if ($0 != "") { print; exit }
        }
    '
}

PLAN_TEXT=$(git show "${FINAL_SHA}^:${PLAN_DOC}")
if [[ -z "$PLAN_TEXT" ]]; then
    # A root commit, or a PLAN that never existed in the parent. Either way the
    # chain cannot be walked, and guessing it would be worse than stopping.
    die "could not read $PLAN_DOC from ${FINAL_SHA}^"
    exit 6
fi

# expected_path <declared-path> — where the document lives once terminal.
# A DESIGN moves to docs/designs/current/ when it reaches Current; every other
# type keeps its path across every transition.
expected_path() {
    case "$1" in
        docs/designs/current/*) echo "$1" ;;
        docs/designs/*) echo "docs/designs/current/$(basename "$1")" ;;
        *) echo "$1" ;;
    esac
}

# expected_status <path> — the terminal posture for this document's type.
expected_status() {
    case "$1" in
        docs/designs/*) echo "Current" ;;
        *) echo "Done" ;;
    esac
}

CHAIN=()
NEXT=$(read_field "$PLAN_TEXT" upstream)
GUARD=0
while [[ -n "$NEXT" ]]; do
    GUARD=$((GUARD + 1))
    if [[ "$GUARD" -gt 10 ]]; then
        die "upstream chain from $PLAN_DOC does not terminate within 10 hops"
        exit 6
    fi

    DECLARED="$NEXT"
    RESOLVED=$(expected_path "$DECLARED")
    CHAIN+=("$DECLARED")

    if [[ ! -f "$RESOLVED" ]]; then
        die "chain document not found at its terminal path: $RESOLVED"
        die "(declared upstream as $DECLARED)"
        exit 4
    fi

    DOC_TEXT=$(cat "$RESOLVED" 2>/dev/null)
    STATUS=$(read_field "$DOC_TEXT" status)
    WANT=$(expected_status "$RESOLVED")
    if [[ "$STATUS" != "$WANT" ]]; then
        die "$RESOLVED is at status '${STATUS:-<none>}', expected '$WANT'"
        exit 4
    fi

    # Fact 3, per document: the finalization commit must CONTAIN it. A rename
    # reaches diff-tree as its old and new paths, so either satisfies this.
    if ! printf '%s\n' "$COMMIT_PATHS" | grep -qxF "$RESOLVED" &&
       ! printf '%s\n' "$COMMIT_PATHS" | grep -qxF "$DECLARED"; then
        die "$RESOLVED is at '$WANT' on disk but is ABSENT from commit $FINAL_SHA"
        die "the transition was made in the working tree and never staged."
        exit 5
    fi

    NEXT=$(read_field "$DOC_TEXT" upstream)
done

# An anchor with no upstream chain is not a failure: R4 commits and pushes the
# PLAN's own deletion alone and reports `skipped`. Facts 1 and 2 carry that run.
echo "verify-cascade-commit: OK (commit ${FINAL_SHA:0:12}, ${#CHAIN[@]} chain document(s))"
