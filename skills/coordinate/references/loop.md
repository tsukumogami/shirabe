# The Loop: Mechanics for Reconcile, Pick and Failure

The rules for each step are in `skills/coordinate/SKILL.md`. This file holds
the mechanics three of them need when they run: the order of reads in a
full reconcile, the issue-timeline read before dispatching an issue, and
the shape of an escalation. Load it on the first turn after a start or
restart, before dispatching an issue, and whenever the failure branch
fires. The land step's table and merge confirmation are in
`references/verification-checklist.md`.

## A Full Reconcile, in Order

The reads are the engine's, not yours. Once `record_find` has found the
record, the workflow enters `reconcile_pass`, whose action is
`scripts/reconcile-pass.sh`. Each tick runs one bounded pass of it; your only
move there is to tick again with no evidence.

- **Pending.** While reads remain, the state holds and `reconcile/progress`
  says how many are left. A worker the workspace manager didn't list is read
  again 30 seconds after the first read, so a pass can end pending with that
  re-read still due. Tick again after the wait.
- **Blocked.** When the record can't be read, the state holds and
  `reconcile/refusal` names the case (`none` or `unreadable`) and the reason.
  Say what it names to the human and stop. Ticking again re-reads the record.
- **Sealed.** When every read is done, the pass writes `reconcile/report.json`
  and `reconcile/report.md` (and, at discipline scope, `reconcile/reasoning.md`
  with the previous rotation's reasoning, verbatim), seals the report to this
  visit, and the workflow moves to `reconcile`. Read `reconcile/report.md`
  there and report it up. The state's gate accepts only the report the pass
  sealed in this visit.

Never write a `reconcile/` context key. A report written or changed by anyone
but the pass holds the workflow in `reconcile`.

What the pass reads, per claim in the record. The report grades each claim as
measured, verified by reading, or inferred:

1. **The record.** It reads the record body live, parses it with the record
   feature's parser, and treats every row as a claim as of its `Written:`
   time. A row it can't parse is listed under "Not verified" with its raw
   line, and every other row is still re-checked. At discipline scope it adds
   the previous handoff at `docs/disciplines/<name>.md` on the default branch,
   rows labelled with the handoff's date.
2. **Each holding against GitHub.** For a holding with a pull request, it runs
   `gh pr view <n> --repo <owner/repo> --json state,isDraft,headRefOid,mergeStateStatus,baseRefName`
   and reads the branch with `git ls-remote`. It reads CI at the verified head
   (and at the live head when they differ) through the record feature's board
   check, which reads runs then jobs, not a checks rollup. For a row whose pull
   request is "none yet", it lists pull requests on its branch the way
   `gh pr list --repo <owner/repo> --head <branch> --state all` does.
   Read the state of any issue a holding names yourself, when you act on it.
3. **Each holding against the host.** It finds each worker by its dispatch
   topic in the workspace manager's listing: with niwa,
   `niwa list` from the workspace root, the listing it reads. A worker it finds has its unique
   material listed from every clone in the instance: commits no live remote
   ref holds (the plumbing equivalent of
   `git log --branches --not --remotes --oneline`, run without `git status`
   and without fetching), uncommitted changes, untracked files, stashes and
   worktrees. Prove a file durable by its content, not by ancestry: the pass
   compares each changed file's content with the default branch's tree, so a
   squash-merged branch reads as landed. A worker missing from two listing
   reads 30 seconds apart is "not found on this read", never "dead" or
   "gone". A roster read just after an outage can't tell "gone" from "not back
   yet", so only a signal that the worker is gone, such as a message that
   bounces, makes it gone.
4. **Re-check side effects in flight.** A merge is confirmed when every file
   the pull request changed at the verified head has that content in the
   merge commit, as "Confirming a Merge" in
   `references/verification-checklist.md` describes. A close is confirmed when
   the target reads closed, and a teardown by two listing reads and the disk.
   Any other side effect is reported as not re-checked.
5. **Read the deferrals.** List every row for the report, disposed or not,
   through the record feature's disposal check; SKILL.md's record section says
   when each must be disposed of.

After the report is up, read the scope. For a roadmap, read its Features section from the
default branch (each feature's status and dependencies). For a discipline,
list the open issues and failing checks in its
area. The pick that follows works from both.

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

The pass builds the report (`scripts/reconcile-report.sh`) and seals it; you
report it, you don't write it. `reconcile/report.md` opens with the scope,
when the record was written and when it was reconciled, then has these
sections, in this order, each line carrying its grade:

- **Changed since then:** each claim the reads contradict, with what the
  record said and what GitHub or the host says now.
- **Holding:** each holding with its state as just read, its board, its
  request leg where it has one, and what happens next.
- **Waiting on a person:** the decisions and finishing steps only a person
  can take, derived at each report and never stored.
- **Exists nowhere else:** workers with no pull request, and anything their
  instance holds that no remote does.
- **Side effects:** each side effect in flight, confirmed, not confirmed with
  the reason, or not re-checked.
- **Undisposed deferrals:** every deferral still owed a disposition.
- **Predecessor's reasoning** (discipline scope): where the previous
  rotation's reasoning is, as its view, not re-checked.
- **Not verified:** everything the pass couldn't read, and why, including
  record rows it couldn't parse.

What a person reads follows one rule, and the renderer enforces it: a pull
request or issue is a clickable link, never a bare number; a worker's name is
inline code; and no commit hash appears. Heads stay in the record's rows and in
`reconcile/report.json`, where the checks read them. Keep the same form when
you report it up.

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
