# Verification Checklist

The rule is in `skills/coordinate/SKILL.md`: verify before you relay or act.
This file is the exact reads behind it and the wording of a report. Load it
at the verify step. Run the reads at the moment you are about to repeat the
claim, not from an earlier turn.

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

2. **Each CI job, its runner, and the steps it ran.** Read every run on
   the head sha, and every job in each run. Each job needs a runner name
   and a non-zero count of steps that ran; a job whose steps were all
   skipped, or that ran on no runner, can show green while testing
   nothing.

   ```bash
   gh run list --repo <owner/repo> --commit <full-head-sha> --json databaseId,name,conclusion,status,createdAt
   gh api repos/<owner/repo>/actions/runs/<run-id>/jobs \
     --jq '.jobs[] | {name, conclusion, runner: .runner_name, ran: ([.steps[] | select(.conclusion == "success")] | length), not_ok: [.steps[] | select(.conclusion != "success" and .conclusion != "skipped") | .name]}'
   ```

   Read these as red even when nothing says "failure":

   - a merge state of `DIRTY` with no runs on the head: CI never started;
   - a run that failed at startup, which can leave the board with no
     failing job to see;
   - a board read too early: the aggregate check registers last;
   - a stacked pull request whose runs were all created before its blocker
     merged: they tested the old base. It needs a run created after.

   On a re-run, read each attempt, not only the latest.

3. **The file list.** What the pull request actually changes, against what
   the brief asked for. Check it for paths under a workflow staging
   directory that must not merge.

   ```bash
   gh pr view <n> --repo <owner/repo> --json files --jq '.files[].path'
   ```

4. **The remote ref.** The branch on the remote matches the head you read.

   ```bash
   git ls-remote https://github.com/<owner/repo>.git refs/heads/<branch>
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
- measured: CI <n> jobs on <sha>, all success; <job> ran <k> steps on <runner> ...
- verified by reading: files <count>, all inside the brief's scope
Not verified:
- <what you didn't or couldn't read, and why>
Reported by the worker, not re-derived (inferred):
- <anything you are passing on without reading it>
```

A claim you can't re-derive right now goes under "Not verified", never in
the verified list, however recently you last read it.
