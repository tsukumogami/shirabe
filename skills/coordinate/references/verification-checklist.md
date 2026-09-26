# Verification Checklist

The rule is in `skills/coordinate/SKILL.md`: verify before you relay or act.
This file is the exact reads behind it and the wording of a report. Load it
at the verify step. Run the reads at the moment you are about to repeat the
claim, not from an earlier turn.

## The Reads

1. **Head sha.** The commit the pull request is at now.

   ```bash
   gh pr view <n> --repo <owner/repo> --json headRefOid,state,isDraft,mergeStateStatus
   ```

2. **Each CI job, its runner, and the steps it ran.** Read every run on
   the head sha, and every job in each run. A job whose steps are all
   skipped, or that ran on no runner, can show green while testing
   nothing.

   ```bash
   gh run list --repo <owner/repo> --commit <head-sha> --json databaseId,name,conclusion,status
   gh api repos/<owner/repo>/actions/runs/<run-id>/jobs \
     --jq '.jobs[] | {name, conclusion, runner: .runner_name, ran: ([.steps[] | select(.conclusion == "success")] | length), not_ok: [.steps[] | select(.conclusion != "success" and .conclusion != "skipped") | .name]}'
   ```

   A board read too early is partial: the aggregate check registers last.
   On a re-run, read each attempt, not only the latest.

3. **The file list.** What the pull request actually changes, against what
   the brief asked for.

   ```bash
   gh pr view <n> --repo <owner/repo> --json files --jq '.files[].path'
   ```

4. **The remote ref.** The branch on the remote matches the head you read.

   ```bash
   git ls-remote https://github.com/<owner/repo>.git refs/heads/<branch>
   ```

After a merge, read the changed files on the default branch:

```bash
gh api repos/<owner/repo>/contents/<path>?ref=<default-branch> --jq .sha
```

## The Report

Separate what you read from what you were told. Every claim carries where
it came from.

```
<unit>: <pull request URL>
Verified at <time>:
- head <sha>, matches ls-remote on <branch>
- CI: <n> jobs on <sha>, all success; <job> ran <k> steps on <runner> ...
- files: <count>, all inside the brief's scope
Not verified:
- <what you didn't or couldn't read, and why>
Reported by the worker, not re-derived:
- <anything you are passing on without reading it>
```

A claim you can't re-derive right now goes under "Not verified", never in
the verified list, however recently you last read it.
