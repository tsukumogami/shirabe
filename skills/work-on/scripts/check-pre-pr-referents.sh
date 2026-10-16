#!/usr/bin/env bash
# check-pre-pr-referents.sh -- for /work-on: check that the referents pre_pr.md
# names exist, not only that they are shaped like referents.
#
# pre_pr.md is the context key a run writes at `finalization` to name what its
# pre-PR obligations were judged against. Two lines in it are checked here:
#
#   cleanup_commit: <sha>
#       The commit whose diff was reviewed for debug statements, commented-out
#       code and the like. 7 to 40 lowercase hex characters, and the value must
#       name a commit in this repository (`git cat-file -e <sha>^{commit}`)
#       that is HEAD or one of its ancestors (`git merge-base --is-ancestor`).
#       A mistyped full sha names no object; a commit from another branch is
#       not what this branch's pull request contains. Both fail.
#
#   design_diagram: docs/<path>.md
#   design_diagram: not-applicable: <reason>
#       The design document whose diagram was updated, or the reason no diagram
#       applies. A path must name a file in HEAD's tree (`git cat-file -t
#       HEAD:<path>` is `blob`), so a path that was never written, or was
#       written and not committed, fails. The not-applicable form needs a
#       reason after it.
#
# The template runs this as the command of two gates, `cleanup_referent` and
# `diagram_referent`, in `finalization`, in `deferral_approval` and in
# `pre_pr_evidence`. They replaced `context-matches` gates that checked the
# shape alone, which a sha naming nothing passed (shirabe#422).
#
# The value stays evidence the agent writes rather than something the template
# derives. The line records which commit the cleanup pass reviewed, and only the
# agent knows that. A HEAD koto recorded itself could never fail this check, so
# it would attest nothing about the review, and it would be the wrong commit
# besides: the summary commit lands after pre_pr.md is written, so HEAD at
# pre_pr_evidence is past the reviewed one. What the gate can check is that the
# agent's answer names a real commit in HEAD's history. That history
# includes commits already on the base branch, so the check proves the sha is
# real and reachable, not that it is one of this branch's own commits. It is not
# bounded by impl_base (record-changed-paths.sh): amending the commit
# `analysis` started from leaves impl_base off HEAD's history, and a bound on it would then refuse the
# reviewed commit of a run that did nothing wrong.
#
# Each key must appear on exactly one line, starting at the beginning of the
# line. A second line for the same key is refused rather than resolved: which
# one was meant is not something this check can decide. Trailing blanks are
# ignored; any other text after the value fails the shape.
#
# koto runs a gate command with the working directory of the `koto next`
# process, the repository being worked, so the git commands here read that
# repository.
#
# Usage: check-pre-pr-referents.sh --cleanup <koto-session-name>
#        check-pre-pr-referents.sh --diagram <koto-session-name>
#
# Nothing on stdout. The reason for a failure goes to stderr, together with the
# stderr of the command that failed. koto discards a failed gate's output, so
# the reason is seen only when the agent runs this script itself, which the
# finalization directive tells it to do.
#
# Exit codes:
#   0 -- the referent exists
#   1 -- anything else: the key is absent or malformed, the referent does not
#        exist, pre_pr.md could not be read, this is not a git repository, or
#        the arguments are wrong. Fails closed on every path. Only 0 and 1 are
#        ever returned: a check that cannot run must not pass, and at
#        pre_pr_evidence a status no edge names would leave a run that already
#        submitted its evidence held with no reason recorded, where 1 stops it
#        at done_blocked with a failure_reason that says to run this script.
#        A separate "could not run" code would need a rung of its own on that
#        ladder for no difference in what the agent does next.
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

fail() {
    echo "check-pre-pr-referents: $*" >&2
    exit 1
}

MODE="${1:-}"
SESSION="${2:-}"

case "$MODE" in
    --cleanup) KEY=cleanup_commit ;;
    --diagram) KEY=design_diagram ;;
    "") fail "missing mode: expected --cleanup or --diagram" ;;
    *)  fail "unrecognised mode [$MODE]: expected --cleanup or --diagram" ;;
esac
[ -n "$SESSION" ] || fail "missing session argument for $MODE"
[ "$#" -eq 2 ] || fail "expected exactly two arguments, got $#"

# `koto context get` exits non-zero for an absent key, with its own message on
# stderr, which is left to reach the reader.
PREPR=$(koto context get "$SESSION" pre_pr.md) \
    || fail "could not read pre_pr.md from session [$SESSION]"

# Lines for this key, trailing blanks and a CR stripped. grep exits 1 on no
# match, which is the "absent" case below, not an error.
LINES=$(printf '%s\n' "$PREPR" | sed 's/[[:space:]]*$//' | grep -E "^${KEY}:")
COUNT=$(printf '%s' "$LINES" | grep -c '^')
[ "$COUNT" -ge 1 ] || fail "pre_pr.md has no line starting with '${KEY}:'"
[ "$COUNT" -eq 1 ] || fail "pre_pr.md has $COUNT lines starting with '${KEY}:'; write exactly one"

VALUE=${LINES#"${KEY}: "}
[ "$VALUE" != "$LINES" ] || fail "pre_pr.md's ${KEY} line is not written as '${KEY}: <value>' (one space after the colon)"

git rev-parse --git-dir >/dev/null || fail "not inside a git repository"

if [ "$MODE" = --cleanup ]; then
    printf '%s' "$VALUE" | grep -qE '^[0-9a-f]{7,40}$' \
        || fail "cleanup_commit [$VALUE] is not a sha of 7 to 40 lowercase hex characters"
    git cat-file -e "${VALUE}^{commit}" \
        || fail "cleanup_commit [$VALUE] does not name a commit in this repository"
    git merge-base --is-ancestor "$VALUE" HEAD \
        || fail "cleanup_commit [$VALUE] is not HEAD or an ancestor of HEAD; name the reviewed commit on this branch"
    exit 0
fi

case "$VALUE" in
    "not-applicable: "[!\ ]*)
        exit 0
        ;;
esac
printf '%s' "$VALUE" | grep -qE '^docs/[^ ]+[.]md$' \
    || fail "design_diagram [$VALUE] is neither a docs/<path>.md nor 'not-applicable: <reason>'"
TYPE=$(git cat-file -t "HEAD:${VALUE}") \
    || fail "design_diagram [$VALUE] is not in HEAD's tree; commit it, or name the path that exists"
[ "$TYPE" = blob ] || fail "design_diagram [$VALUE] is a $TYPE in HEAD's tree, not a file"
exit 0
