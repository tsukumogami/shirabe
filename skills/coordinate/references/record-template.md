# The Record: Template and Procedures

What the record holds, and where it lives for each scope, are in
`skills/coordinate/SKILL.md`. This file holds the literal shapes and the
steps that open, update and close it. Load it when you open or update the
record.

## Container and Host

| Scope | Host repository | Container |
|---|---|---|
| Roadmap `docs/roadmaps/ROADMAP-<name>.md` | the roadmap's repository | an issue titled `Coordinator record: ROADMAP-<name>` |
| Discipline `<name>` | the host repository the human named | a draft pull request from `coordinate/discipline-<name>` |

A roadmap's record is an issue because an issue fits a record that commits
nothing: there is no branch to maintain, no merges from the default branch
to absorb, and it closes cleanly when the roadmap finishes. A rotation's
record is a pull request because its diff is the handoff file it commits
at the end.

Name every worker, in the record and in every pull request, by its dispatch
topic, never by session id, instance path or job id: those are host facts
that don't survive a restart or a move, and reconcile finds sessions by
topic. When the record's host repository is public, it never names a
private repository, path or issue; a holding that would need one is a
scope question for the human.

## Finding or Opening the Record

Run on every start, as part of the full reconcile, before the first
dispatch.

**Roadmap scope.** List open issues and match the record's title exactly.
Don't use `--search`: the search index can lag a newly created issue, so
a coordinator restarted just after opening its record would find none and
open a second, and a phrase search also matches longer titles such as a
`-v2` roadmap.

```bash
gh issue list --repo <owner/repo> --state open --limit 1000 --json number,url,title,body \
  --jq '.[] | select(.title == "Coordinator record: ROADMAP-<name>")'
```

1. **One issue whose body carries the declaration line:** adopt it. Never
   open a second one.
2. **An issue with the title but without the declaration line, or more
   than one match:** don't pick. Report what you found and ask the human.
3. **None:** open one with the body below, written to a file:

   ```bash
   gh issue create --repo <owner/repo> --title "Coordinator record: ROADMAP-<name>" --body-file <body-file>
   ```

**Discipline scope.** Check the branch; exactly one of four outcomes:

1. **The branch has an open pull request whose body carries the
   declaration line.** Read the rotation's end date from the pull
   request's title, which carries it from the day the pull request opened.
   If that date hasn't passed, this is a restart of that rotation: adopt
   it, and never replace it or open a second one. If it has passed, the
   pull request belongs to the previous rotation: close it out as "Closing
   a Predecessor's Rotation" says, and once it has merged, run this check
   again from the top.
2. **The branch has an open pull request without the declaration line.**
   Don't adopt it. Report the conflict and ask the human, because a pull
   request on the record's branch that isn't a record is a scope question.
3. **The branch exists and its last pull request was merged or closed.**
   Delete the branch and cut it again from the default branch, so a
   squash-merged history never comes back:

   ```bash
   git push origin --delete coordinate/discipline-<name>
   git switch -c coordinate/discipline-<name> origin/<default-branch>
   ```

4. **No branch exists.** Cut it from the default branch, push an empty
   commit, and open a draft pull request:

   ```bash
   git switch -c coordinate/discipline-<name> origin/<default-branch>
   git commit --allow-empty -m "docs(coordinate): open <name> rotation record"
   git push origin HEAD:refs/heads/coordinate/discipline-<name>
   gh pr create --draft --repo <owner/repo> --head coordinate/discipline-<name> \
     --base <default-branch> --title "<title>" --body-file <body-file>
   ```

Report the record's issue number or pull request URL up with every
report, so a successor is handed it as a decision and reads it directly.

## The Rotation's Pull Request Title

`docs(coordinate): <name> rotation <start> to <end>`, with both dates in
`YYYY-MM-DD` form from the day it opens. The end date is the start plus
the rotation's length. If the human ends the rotation early, or sets a new
length, edit the end date to match in the same update that records the
decision; the title is where a successor reads it.

## The Body

Write the whole body to a file and pass it with `--body-file`; never
inline it into a command. A rotation's pull request body follows
`references/pr-body-conformance.md` in the shirabe plugin; its Part 2
starts at the declaration line. An issue body starts at the declaration
line.

```markdown
Coordinator record for the <name> discipline, kept on coordinate/discipline-<name>.

---

> This is a **coordinator record** for <scope>.

Written: <YYYY-MM-DDTHH:MM:SSZ>

## Holdings

| Unit | Entry point | Mode | Worker | Repo | Branch | Verified head | Dispatched | Pull request |
|------|-------------|------|--------|------|--------|---------------|------------|--------------|
| <feature, issue, question or choice> | <skill> | <--auto and flags> | <dispatch topic> | <owner/repo> | <branch> | <full sha once parked, else blank> | <YYYY-MM-DD> | <[#n](URL), or none yet> |

## Deferrals

| Deferral | Reason | Raised |
|----------|--------|--------|
| <what> | <why not now> | <YYYY-MM-DD> |

## Side effects in flight

| Action | Target | Verified head | Attempted | How to confirm |
|--------|--------|---------------|-----------|----------------|
| <merge, close, teardown> | <pull request, issue, worker> | <full sha verified before acting or asking> | <YYYY-MM-DDTHH:MMZ> | <the read that settles it> |

## Reversals

| Date | Reversed | Now | Reason | From |
|------|----------|-----|--------|------|
| <YYYY-MM-DD> | <earlier decision> | <new decision> | <why> | <who decided> |
```

An empty section reads `None.` in place of its table. No table carries a
status, CI or merge-state column: those are read from GitHub every time. A
row leaves Side effects in flight once confirmed. Reversals only grow. A
deferral carried forward keeps its row with a new reason.

The verified head is the sha you verified before you acted or asked. After
a crash, confirming a merge compares the default branch against that sha,
not against whatever the branch holds now.

The declaration line is for readers. It is deliberately different from the
`This is a **coordination PR**` marker that `/execute` uses, so no gate
written for coordination pull requests ever parses a record.

**Updating.** Rewrite the body whole from what you hold now, with a new
`Written:` time, and apply it with `gh issue edit <n> --body-file <file>`
or `gh pr edit <n> --body-file <file>`. Every pull request in the record is
a link. Follow the host repository's conventions (its CLAUDE.md) for
commit messages and bodies.

## Closing a Roadmap Record

When every feature reads Done or Dropped on the roadmap, Holdings and Side
effects in flight are empty, and every deferral is filed or closed: write
the final body, then close the issue if the workspace permits, or hand the
close to the human.

## The Discipline Handoff

At rotation end, write `docs/disciplines/<name>.md`, one file per
discipline, overwritten each rotation. It is plain markdown with no
shirabe artifact prefix, so `shirabe validate` applies no structural
checks to it, though the host's docs validation still runs its prose
checks on it:

```markdown
# <name> handoff, <YYYY-MM-DD>

Rotation from <start> to <end>. Host repository: <owner/repo>. Record:
<pull request URL>, kept on coordinate/discipline-<name>.

## Holdings

| Unit | Entry point | Mode | Worker | Repo | Branch | Verified head | Dispatched | Pull request |
|------|-------------|------|--------|------|--------|---------------|------------|--------------|

## Deferrals

| Deferral | Reason | Raised |
|----------|--------|--------|

## Side effects in flight

| Action | Target | Verified head | Attempted | How to confirm |
|--------|--------|---------------|-----------|----------------|

## Reversals

| Date | Reversed | Now | Reason | From |
|------|----------|-----|--------|------|

## Reasoning for the next rotation

<Prose: what this rotation learned that the tables can't say.>
```

Write the reasoning section fresh each rotation. Replace the previous
rotation's text; never append to it, or the handoff grows into a standing
protocol.

## Closing a Rotation

1. Commit the handoff to the record branch and push.
2. If the rotation ended on a different day than the title says, edit the
   title's end date to the actual one.
3. Mark the pull request ready and merge it if the workspace permits;
   otherwise hand it to the human as the last row of the merge-order
   table in `references/verification-checklist.md`.
4. Delete the branch once it has merged.

## Closing a Predecessor's Rotation

When the discipline check finds a previous rotation's record still open
past its end date, the successor closes it, and writes only what it can
stand behind:

- The tables are copied from the predecessor's record body as it stands,
  under a line reading "As written by the previous rotation at <its
  Written time>; not re-checked." Your own reconcile re-checks those rows
  when you carry them into your record.
- The reasoning section says the outgoing rotation's reasoning was not
  recorded. Never write it on the predecessor's behalf.
- Open deferrals carry into your own record, to be disposed of before your
  first dispatch.

Then follow Closing a Rotation for that record.
