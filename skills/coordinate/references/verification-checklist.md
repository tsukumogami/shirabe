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
   - for each workflow and event, its latest run. A pull request event after
     the first (a body edit, say) starts a new run of the same workflow at
     the same head, and re-running the old one replays its old payload, so a
     job that a later run of the same workflow ran again is judged by that
     later run, and the earlier one is listed as `superseded`. While the later
     run is still going the board reads pending, never verified. A job the
     later run didn't run again keeps its own result, and a later red always
     counts;
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
- measured: head matches the remote ref of <branch>
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

Every row has passed the land check: the worker's review round at a fresh
reviewed head, the body's mechanical checks, and your goal-fit call. Under the
table, for each pull request, give the squash message the merge should carry
(`message` in `coord/land.json`, the title and Part 1 as plain text) and say
where the seats' verdicts are (the hand-over block `merge-order-entry.sh`
prints names it), so whoever merges reads neither a second panel nor a
hand-built message.

## The Review Round

A worker records its own review round, the panel the land step reads instead
of running one (`docs/designs/current/DESIGN-coordinate-merge-policy.md`), in
its own /work-on run's session:

```bash
skills/coordinate/scripts/review-round.sh record --session <worker's run> <round.json>
```

```json
{"reviewed_head": "<40-hex sha>",
 "seats": [{"seat": "architect", "model": "sonnet", "run": "<run id>", "verdict": "pass"},
           {"seat": "maintainer", "model": "sonnet", "run": "<run id>", "verdict": "pass"},
           {"seat": "pragmatic", "model": "sonnet", "run": "<run id>", "verdict": "pass"}]}
```

At least three seats, each with its own Seat and a Run unique to that seat's
run (an agent or session id, or `comment-<id>` for a review comment the seat's
verdict was posted as), every Verdict `pass`, and one reviewed head for all of
them: the head itself, or one that only merge-ins of the base branch have moved
past since. The script stores it as the session's `review_round.json`.

The land step reads the round from one of two places. For a holding that
returns on a leg, it reads the session the leg is bound to, when this host's
store holds it. Otherwise it reads the round the worker's report carried: a
message-path worker's report step, `scripts/render-result.sh`, prints the
recorded round in its result block as one `review_round=<compact JSON>` line,
and the report you submit at `wait` keeps that block in your own session's
log, which the land step can read wherever you run. So pass the worker's
message whole, its result block included. `coord/land.json`'s
`evidence.source` says which was read: `session`, `report`, or `none`.

The pull request body is never read for the round. A `## Review panel` table
in it, whatever it says, is not evidence: a body with a table and no round in
a session or a report is `unready` with `no-evidence`. Without the
`## PR Workflow Content: include` opt-in, `/work-on`'s pull request gate
reports such a table as `pr-body/workflow-content`.
`scripts/panel-evidence.sh --round` judges the round; its header lists every
rule.

## Confirming a Merge

Confirm the merge from GitHub's own record, in three reads whatever the pull
request's size: the pull request must be `MERGED`, the head GitHub merged
must be the head you verified, and its merge commit must be on the default
branch:

```bash
gh pr view <n> --repo <owner/repo> --json state,headRefOid,mergeCommit
gh api "repos/<owner/repo>" --jq .default_branch
gh api "repos/<owner/repo>/compare/<default-branch>...<merge-commit>" --jq .status
```

The comparison reads `behind` or `identical` when the merge commit is on the
default branch. A head other than the one you verified (it moved after
verification) or a merge commit that isn't on the default branch means the
merge isn't what was verified;
report it before dispatching anything that depends on it.
The head pins what GitHub merged, so this confirms the merge
itself, not what the default branch holds now: a later change to the same
files doesn't bear on it, and a revert after the merge still reads as merged.
The comparison is with the default branch, which is where the coordinator
merges: a pull request merged into another base doesn't confirm here. If the
pull request reads merged but shows no merge commit, or the comparison
answers not found, the merge can't be confirmed yet; read again, and never
take it as merged.
