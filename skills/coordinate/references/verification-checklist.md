# Verification Checklist

The rule is in `skills/coordinate/SKILL.md`: verify before you relay or act.
This file is the exact reads behind it, the wording of a report, and the
land step's merge-order table and merge confirmation. Load it at the
verify step and the land step. Run the reads at the moment you are about
to repeat the claim, not from an earlier turn.

## Before the Board Finishes

Write down, before CI finishes, which reds you would report and which you
would escalate. Deciding after the result is in lets the result move the
standard.

## The Reads

1. **Head sha.** The commit the pull request is at now. Use the full
   40-character sha in every later query; a short sha can match more than
   one commit.

   ```bash
   gh pr view <n> --repo <owner/repo> --json headRefOid,state,isDraft,mergeStateStatus
   ```

2. **The board: every required check, and every job with a runner and real
   steps.** `scripts/board-verdict.sh` is the read; the verify step runs it
   for you, and for a reconcile or any read by hand run it directly. It is
   read-only and needs no session:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/coordinate/scripts/board-verdict.sh --repo <owner/repo> --pr <n>
   ```

   It judges the head the pull request is at, and prints one JSON verdict
   with its reasons. What it holds, so you know what `verified` means:

   - every workflow run on the head sha, from any event or branch, counted
     against the total GitHub reports;
   - for each run, its latest attempt. A re-run that supersedes a failed
     attempt is what GitHub's own checks judge, so an earlier failed attempt
     isn't red on its own; it is listed as `superseded`;
   - every job in that attempt ran on a named runner and has at least one
     step that succeeded; a job whose steps were all skipped, or that ran on
     no runner, is red even when it shows green;
   - the required set is the union of branch protection, the branch rules and
     every check the rollup marks required, and each one must have passed; a
     required check that never registered is missing, and an unreadable
     source is an error, never "requires nothing";
   - a merge state of `DIRTY` is red.

   Read these as red too, which the verdict's reasons name: a run that failed
   at startup; a board read before a required summary job registered; and a
   stacked pull request whose runs were all created before its blocker
   merged, which tested the old base and needs a run created after.

3. **The file list.** What the pull request actually changes, against what
   the brief asked for. Check it for paths under a workflow staging
   directory that must not merge.

   ```bash
   gh pr view <n> --repo <owner/repo> --json files --jq '.files[].path'
   ```

4. **The remote ref.** The branch on the remote still points at the head you
   read. `board-verdict.sh` reads it last, through the API
   (`repos/<head repo>/git/ref/heads/<branch>`), so a push during the read
   shows as a moved head. By hand:

   ```bash
   gh api repos/<owner/repo>/git/ref/heads/<branch> --jq .object.sha
   ```

Report green only when the pull request's head, the remote ref and the CI
board all agree on one sha, with no caveat attached.

## The Report

Separate what you read from what you were told, and grade each claim:
**measured** (you ran the read), **verified by reading** (you read the
artifact), or **inferred**. Never put an inferred clause beside a measured
one in the same sentence.

```
<unit>: <pull request URL>
Verified at <time>, head <full sha>:
- measured: head matches ls-remote on <branch>
- measured: CI <n> jobs on <sha>, all success; <job> succeeded <k> steps on <runner> ...
- verified by reading: files <count>, all inside the brief's scope
Not verified:
- <what you didn't or couldn't read, and why>
Reported by the worker, not re-derived (inferred):
- <anything you are passing on without reading it>
```

A claim you can't re-derive right now goes under "Not verified", never in
the verified list, however recently you last read it.

## The Merge-Order Table

The table the land step hands over, one row per verified pull request:

```
Ready to merge, in this order:

| # | Pull request | Worker | Verified at | Why this position |
|---|--------------|--------|-------------|-------------------|
| 1 | [#<n>](<URL>) | `<dispatch topic>` | <time> | <e.g. no dependencies; others rebase onto it> |
| 2 | [#<n>](<URL>) | `<dispatch topic>` | <time> | <e.g. depends on the first one's schema change> |

After each merge I'll confirm it on the default branch before the next one
is safe.
```

The table shows no commit hash: the head you verified stays in the record's
Verified head and in the evidence. A pull request is a link, never a bare
number, and a worker is inline code, as in every table the human sees. If a
pull request's head moves after you hand the table over, it drops back to
unverified until you read it again.

## Confirming a Merge

For each file the pull request changed, compare its blob sha on the default
branch with its blob sha at the head you verified:

```bash
gh pr view <n> --repo <owner/repo> --json files --jq '.files[].path'
gh api "repos/<owner/repo>/contents/<path>?ref=<default-branch>" --jq .sha
gh api "repos/<owner/repo>/contents/<path>?ref=<verified-head-sha>" --jq .sha
```

A deleted file shows as not found on the default branch, which is the
expected result for it. A file whose blob sha on the default branch
doesn't match the verified head's version means the merge isn't what was
verified; report it before dispatching anything that depends on it.
