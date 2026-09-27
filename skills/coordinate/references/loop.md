# The Loop: Mechanics for Reconcile, Pick and Failure

The rules for each step are in `skills/coordinate/SKILL.md`. This file holds
the mechanics three of them need when they run: the order of reads in a
full reconcile, the issue-timeline read before dispatching an issue, and
the shape of an escalation. Load it on the first turn after a start or
restart, before dispatching an issue, and whenever the failure branch
fires. The land step's table and merge confirmation are in
`references/verification-checklist.md`.

## A Full Reconcile, in Order

Hand the reads to a local agent when there are more than a few holdings, and
have it return the report below rather than the raw output. Your context is
for the judgment at the end, not for the reads.

1. **Read the record.** The record is the one `record_find` adopted (the
   reconcile directive names it; an issue at roadmap scope, a pull request at
   discipline scope). Read its body and note its `Written:` time: every row
   under it is a claim as of that time.
2. **Read the scope.** For a roadmap, read its Features section from the
   default branch (each feature's status and dependencies). For a
   discipline, read the previous handoff at `docs/disciplines/<name>.md` on
   the default branch, then list the open issues and failing checks in its
   area.
3. **Re-check each holding against GitHub.** For each row in Holdings:

   ```bash
   gh pr view <n> --repo <owner/repo> --json state,isDraft,headRefOid,mergeStateStatus
   ```

   Read its CI and remote ref with `scripts/board-verdict.sh --repo
   <owner/repo> --pr <n>`, not a checks rollup: it is the read that shows each
   job's runner and step count and re-reads the ref last, and the same one the
   verify step uses (`references/verification-checklist.md`, "The Reads").

   For a row whose pull request is "none yet", check whether one has
   appeared since:

   ```bash
   gh pr list --repo <owner/repo> --head <branch> --state all --json number,state,url
   ```

   Read the state of any issue a holding names with `gh issue view`.
4. **Re-check each holding against the host.** Ask the workspace manager
   whether each worker's session and instance still exist: with niwa,
   `niwa list` from the workspace root, finding each worker by its dispatch
   topic, then check that its instance directory is still on disk. For any
   session or instance you might tear down, list its unique material: in
   each clone, `git status --porcelain` and
   `git log --branches --not --remotes --oneline`; its worktrees
   (`git worktree list`); and its scratch directory. Prove a file durable
   by its content, not by ancestry: its blob hash must appear on a remote
   ref that survives a squash merge, since a commit reachable from a
   feature branch is gone once that branch is squashed and deleted.

   ```bash
   BLOB=$(git hash-object <file>)
   git fetch origin <default-branch>
   git log origin/<default-branch> --find-object="$BLOB" --oneline -1
   ```

   Output means the content is on the default branch; no output means the
   file is unique material. Record a session missing from the roster as "not
   seen" in the report, never "dead": a roster read just after an outage
   can't tell "gone" from "not back yet", so only a signal that the worker
   is gone, such as a message that bounces, makes it dead.
5. **Re-check side effects in flight.** For each row, run its "How to
   confirm" read. A merge attempted and never confirmed is settled by
   comparing the default branch against the row's verified head, as
   "Confirming a Merge" in `references/verification-checklist.md` shows.
6. **Read the deferrals.** List every row for the report; SKILL.md's
   record section says when each must be disposed of.

## Before Dispatching an Issue

List the pull requests that reference the issue from its timeline:

```bash
gh api "repos/<owner/repo>/issues/<n>/timeline" --paginate \
  --jq '.[] | select(.event == "cross-referenced") | .source.issue | select(.pull_request) | {number, state, url: .html_url}'
```

An open or merged one that closes the issue means the unit is taken or
done; read it before dispatching anything.

## Checking a Worker's Premise

A worker's report rests on premises: that a feature depends on another, that a
unit is independent, that a check is required. Test each one you would act on
against what you can read yourself, the roadmap's own dependency lines and
statuses, the record, and GitHub. A premise the roadmap or GitHub contradicts
is a finding: name the contradiction, with both sources, before you weigh the
proposal that rests on it.

A claimed dependency the roadmap doesn't list is a contradiction, not a
detail. If the roadmap says two features are independent (neither lists the
other under Dependencies) and a worker says one exists only to serve the
other, the worker is asserting a dependency the roadmap denies: say "the
worker's claim contradicts the roadmap, which lists features N and M as
independent", whichever side turns out right. Agreeing that the roadmap says
they're independent and then calling the claim consistent misses it.

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
- <holding or side effect>: record said <old>, GitHub or the host says <new> (measured | verified by reading | inferred).

Holding (<n> of <bound> active; parked at ready: <m>):
- <unit> -- `<dispatch topic>` -- <state as just read> -- next: <what happens next> -- [#<n>](<URL>), or "none yet"

Waiting on the human:
- <decision or finishing step> -- <recommendation>

Unique material held outside any remote:
- <worker or instance>: <what, where>

Open deferrals:
- <deferral> (raised <date>): <reason>

Not verified: <anything you could not read, and why>.
```

Every later report ends with the progress table `scripts/progress-view.sh`
prints (SKILL.md, "Reporting").

## The Shape of an Escalation

An escalation goes to whoever dispatched you, once, and carries everything
needed to decide without asking back. It lists options because the
recipient is choosing between moves you can't make alone:

```
Escalating <unit> in <scope>.

What happened: <the failure, with the pull request and the CI job or
conflict that shows it>.
What I verified: <reads, with the head sha and time, each marked measured, verified by reading, or inferred>.
What I tried: <re-dispatches so far, with what each learned>.
Options: <two or three, each with its consequence>.
Recommendation: <one option and why>.
Until you answer: <what stays paused; everything else keeps moving>.
Waiting on the human:
- <this decision> -- <recommendation>
- <anything else already waiting on them>
```

## More Worked Examples

Three examples of the conditions that make a decision the human's:

- Dispatching the next feature on an Active roadmap: not asked.
- Dropping a feature from the roadmap: asked, because it changes scope.
- Running a worker past a cap the human set: asked, because it extends a
  supplied decision.

Some more cases:

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
