# The Loop: Reconcile and Failure Mechanics

The rules for each step are in `skills/coordinate/SKILL.md`. This file holds
the mechanics two of them need when they run: the order of reads in a full
reconcile, and the shape of an escalation. Load it on the first turn after a
start or restart, and whenever the failure branch fires.

## A Full Reconcile, in Order

Hand the reads to a local agent when there are more than a few holdings, and
have it return the table below rather than the raw output. Your context is
for the judgment at the end, not for the reads.

1. **Find the record.** Run the record's branch check from
   `references/record-template.md`. It either adopts the record's pull
   request, opens a new one, or stops to ask. Read Part 2 of the body and
   note its `Written:` time: every row under it is a claim as of that time.
2. **Read the scope.** For a roadmap, read its Features section from the
   default branch (each feature's status and dependencies). For a
   discipline, read the previous handoff at `docs/disciplines/<name>.md` on
   the default branch, then list the open issues and failing checks in its
   area.
3. **Re-check each holding against GitHub.** For each row in Holdings:

   ```bash
   gh pr view <n> --repo <owner/repo> --json state,isDraft,headRefOid,mergeStateStatus,statusCheckRollup
   git ls-remote https://github.com/<owner/repo>.git refs/heads/<branch>
   ```

   For a row whose pull request is "none yet", check whether one has
   appeared since:

   ```bash
   gh pr list --repo <owner/repo> --head <branch> --state all --json number,state,url
   ```

   Read the state of any issue a holding names with `gh issue view`.
4. **Re-check each holding against the host.** Ask the workspace manager
   whether each dispatched session and its instance still exist. For any
   session or instance you might tear down, list its unique material: in
   each clone, `git status --porcelain` and
   `git log --branches --not --remotes --oneline`; its worktrees
   (`git worktree list`); and its scratch directory. Record a session
   missing from the roster as "not seen" in the report, never "dead";
   When Something Goes Wrong in SKILL.md says why one read can't tell.
5. **Re-check side effects in flight.** For each row, run its "How to
   confirm" read. A merge attempted and never confirmed is settled only by
   reading the pull request's state and the changed files on the default
   branch.
6. **Read the deferrals.** List every row for the report; SKILL.md's
   record section says when each must be disposed of.

## Resolving a Claim GitHub Contradicts

When a row says one thing and the read says another, act on the read,
rewrite the row at the next update, and put the difference in
the reconcile report as a change, with both values and the time the row
was written. Never average the two, and never keep the row "until it's
confirmed": the read is the confirmation.

A holding whose pull request merged since the record was written is done.
Drop it from Holdings, and if it was a roadmap feature, confirm the
feature's status on the roadmap rather than setting it yourself.

## The Reconcile Report

```
Reconciled <scope> against the record written <time>.

Changed since then:
- <holding or side effect>: record said <old>, GitHub or the host says <new>.

Holding (<n> of <bound> active):
- <unit> -- <entry point> -- <session> -- <pull request URL, or "none yet"> -- <state as just read>

Unique material held outside any remote:
- <session or instance>: <what, where>

Open deferrals:
- <deferral> (raised <date>): <reason>

Not verified: <anything you could not read, and why>.
```

## The Merge-Order Table

The table the land step hands over, one row per verified pull request:

```
Ready to merge, in this order:

| # | Pull request | Head sha | Verified at | Why this position |
|---|--------------|----------|-------------|-------------------|
| 1 | <URL> | <sha> | <time> | <e.g. no dependencies; others rebase onto it> |
| 2 | <URL> | <sha> | <time> | <e.g. depends on #1's schema change> |

After each merge I'll confirm it on the default branch before the next one
is safe.
```

The head sha is the one you verified. If a pull request's head moves after
you hand the table over, it drops back to unverified until you read it
again.

## Confirming a Merge

After any merge, yours or the human's, read each changed file on the
default branch and compare it with the pull request's version:

```bash
gh pr view <n> --repo <owner/repo> --json files --jq '.files[].path'
gh api "repos/<owner/repo>/contents/<path>?ref=<default-branch>" --jq .sha
gh api "repos/<owner/repo>/contents/<path>?ref=<verified-head-sha>" --jq .sha
```

A deleted file shows as not found on the default branch, which is the
expected result for it.

A file whose blob sha on the default branch doesn't match the pull
request's head version means the merge isn't what was verified; report it
before dispatching anything that depends on it.

## The Shape of an Escalation

An escalation goes to whoever dispatched you, once, and carries everything
needed to decide without asking back:

```
Escalating <unit> in <scope>.

What happened: <the failure, with the pull request and the CI job or
conflict that shows it>.
What I verified: <reads, with the head sha and time>.
What I tried: <re-dispatches so far, with what each learned>.
Options: <two or three, each with its consequence>.
Recommendation: <one option and why>.
Until you answer: <what stays paused; everything else keeps moving>.
```

## More Worked Examples

SKILL.md gives three examples of the human-decision conditions. Some more
cases:

- A worker reports that a feature needs a second pull request it didn't
  plan for. Inside the feature's scope, so not asked: re-dispatch or let the
  worker continue.
- A worker's findings show a roadmap feature should be split in two.
  Asked: it changes the roadmap's feature list.
- The human said "no merges on Fridays" and a verified pull request is
  ready on a Friday. Not asked: hold it and say so in the next report.
  Merging it would reverse a supplied decision.
- A deferral from the previous rotation names work that is now done by a
  merged pull request. Not asked: close the deferral with the pull request
  as the reason.
- A teardown the workspace permits would remove an instance whose unique
  material you listed and found empty. Not asked: tear it down and record
  it. The same teardown with unique material listed: move the material to
  a durable place first, or ask if there is none.
