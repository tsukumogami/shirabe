#!/usr/bin/env bash
# record-settled-branch.sh — for /execute: record the branch this run settled on.
#
# The settled branch is the only thing that knows where children commit on the
# adopt path: the run stays on a branch that already has an open PR and creates
# nothing, so nothing downstream can re-derive it. This script writes it to the
# session's `settled_branch` context key and prints it, so the state's
# `capture_stdout_as` can deliver it to `spawn_and_await`.
#
# Usage: record-settled-branch.sh <koto-session-name>
#
# Output: the branch name on stdout, and nothing else. Diagnostics go to stderr.
#
# Exit codes:
#   0  — recorded, and the name is on stdout
#   64 — HEAD is detached, so there is no branch to record
#   65 — the branch name is outside ^[A-Za-z0-9._/-]+$
#   66 — the branch is the repository's default; recording it would send every
#        child's commits there
#   67 — the session name argument is missing
#   any other non-zero — koto's own, from the context write
#
# ## Why each refusal is here
#
# The malformed-name refusal is the input-surface check: the branch name is
# recovered from the environment, reaches a koto context value, and is
# interpolated into instructions downstream, so it is validated before it is
# stored rather than after.
#
# The default-branch refusal is the one that used to be impossible. The
# directive this script replaces carried five paragraphs explaining that the
# recording block had to run LAST, because running it before the creation
# script checked out `impl/<slug>` would record `main` — "the one wrong value
# neither the pattern nor the read-back can catch, because nothing about it is
# malformed; the ordering is the only thing that prevents it." A script can
# simply refuse it, and this one does. The ordering is now also structural: the
# recording lives in its own state after `orchestrator_setup`.
#
# ## Why there is no read-back here
#
# The state that runs this declares a `settled_branch_recorded` gate —
# `context-matches` against the same key, evaluated by koto after the action
# returns. That is a read the action cannot influence, which is a stronger check
# than a comparison inside the command, so the hand-rolled read-back the old
# directive carried is gone rather than ported.
set -uo pipefail

SESSION="${1:-}"
if [ -z "$SESSION" ]; then
    echo "record-settled-branch: no koto session name given" >&2
    echo "usage: record-settled-branch.sh <koto-session-name>" >&2
    exit 67
fi

BRANCH=$(git symbolic-ref --quiet --short HEAD) || {
    echo "record-settled-branch: HEAD is detached, so there is no branch to record." >&2
    echo "Check out the branch this run should settle on, then tick again." >&2
    exit 64
}

case "$BRANCH" in
    *[!A-Za-z0-9._/-]*|"")
        echo "record-settled-branch: refusing branch name [$BRANCH]" >&2
        echo "It does not match ^[A-Za-z0-9._/-]+\$, and the value is stored and" >&2
        echo "interpolated downstream." >&2
        exit 65
        ;;
esac

# The resolved default first, then the two conventional names. `--quiet` makes
# an absent refs/remotes/origin/HEAD silent (exit 1, no output) rather than
# noisy, which is the ordinary case in a clone that never fetched it — and why
# `main` and `master` are also named literally. A resolution that came back
# empty would otherwise leave this check satisfied by every branch.
DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
DEFAULT=${DEFAULT#origin/}
case "$BRANCH" in
    "${DEFAULT:-main}"|main|master)
        echo "record-settled-branch: refusing to record the default branch [$BRANCH]" >&2
        echo "as the settled branch. Every child of this run commits to whatever is" >&2
        echo "recorded here. Check out the run's own branch and tick again." >&2
        exit 66
        ;;
esac

# `printf '%s'`, not `echo`, and piped rather than passed as an argument: koto
# stores what it receives verbatim, so the newline echo appends would become
# part of the branch name.
printf '%s' "$BRANCH" | koto context add "$SESSION" settled_branch >/dev/null 2>&1 || {
    RC=$?
    echo "record-settled-branch: koto context add failed (exit $RC) for session [$SESSION]" >&2
    exit "$RC"
}

# The only thing on stdout, for capture_stdout_as.
printf '%s' "$BRANCH"
