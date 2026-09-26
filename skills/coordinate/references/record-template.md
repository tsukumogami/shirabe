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

If the host repository is public, the record never names a private
repository, path or issue. A holding that would need one is a scope
question for the human.

## Finding or Opening the Record

Run on every start, as part of the full reconcile, before the first
dispatch.

**Roadmap scope.** Look for open issues carrying the record's title:

```bash
gh issue list --repo <owner/repo> --state open --search 'in:title "Coordinator record: ROADMAP-<name>"' --json number,url,title,body
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
   declaration line.** Adopt it. Never replace it or open a second one.
   First read the rotation's end date from the pull request's title, which
   carries it from the day the pull request opened: if that date has
   passed, the pull request belongs to the previous rotation, so close it
   out (see Closing a Rotation). If it merged and the branch is gone, open
   your own as in outcome 4; if the workspace reserves the merge for a
   person, hand it over and wait before opening yours.
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

## The Rotation's Pull Request Title

`docs(coordinate): <name> rotation <start> to <end>`, with both dates in
`YYYY-MM-DD` form from the day it opens. The end date is the start plus
the rotation's length. If the human ends the rotation early, or sets a new
length, edit the end date to match in the same update that records the
decision; the title is where a successor reads it.

## The Body

Write the whole body to a file and pass it with `--body-file`; never
inline it into a command. A rotation's pull request body needs a Part 1:
one prose sentence with no headings, true after merge, then a line that is
exactly `---`. An issue body starts at the declaration line. Neither uses
any further `---` line.

```markdown
Coordinator record for the <name> discipline, kept on coordinate/discipline-<name>.

---

> This is a **coordinator record** for <scope>.

Written: <YYYY-MM-DDTHH:MM:SSZ>

## Holdings

| Unit | Entry point | Mode | Session | Repo | Branch | Pull request | Verified head | Dispatched |
|------|-------------|------|---------|------|--------|--------------|---------------|------------|
| <feature, issue, question or choice> | <skill> | <--auto, --interactive, flags> | <session name> | <owner/repo> | <branch> | <[#n](URL), or none yet> | <full sha once parked, else blank> | <YYYY-MM-DD> |

## Deferrals

| Deferral | Reason | Raised |
|----------|--------|--------|
| <what> | <why not now> | <YYYY-MM-DD> |

## Side effects in flight

| Action | Target | Verified head | Attempted | How to confirm |
|--------|--------|---------------|-----------|----------------|
| <merge, close, teardown> | <pull request, issue, session> | <full sha verified before acting or asking> | <YYYY-MM-DDTHH:MMZ> | <the read that settles it> |

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
commit messages and bodies. If a script edits the record or a roadmap by
replacing text, make it check that the text it replaces matches exactly
once before it writes; a replacement that matches nothing succeeds
silently and leaves the old text in place.

## Feature State on the Default Branch

The roadmap record commits nothing, and never edits the roadmap. When a
feature lands, its state reaches the roadmap on the default branch through
the finalization cascade if the feature's PLAN is in the roadmap's
repository. Otherwise, brief a worker for a small pull request that sets
that feature's `**Status:**` line and nothing else. No one but the cascade
transitions or deletes the roadmap, and no one edits the sections
`shirabe roadmap populate` owns.

## Closing a Roadmap Record

When every feature reads terminal on GitHub, Holdings and Side effects in
flight are empty, and every deferral is filed or closed: write the final
body, then close the issue if the workspace permits, or hand the close to
the human.

## The Discipline Handoff

At rotation end, write `docs/disciplines/<name>.md`, one file per
discipline, overwritten each rotation. It is plain markdown, not a
validated shirabe artifact, and names no sessions or instances:

```markdown
# <name> handoff, <YYYY-MM-DD>

Rotation from <start> to <end>. Host repository: <owner/repo>. Record:
<pull request URL>, kept on coordinate/discipline-<name>.

## Holdings

| Unit | Entry point | Mode | Repo | Branch | Pull request | Verified head | Dispatched |
|------|-------------|------|------|--------|--------------|---------------|------------|

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

Session names stay in the merged pull request's body, which remains
readable on GitHub.

## Closing a Rotation

1. Commit the handoff to the record branch and push.
2. If the rotation ended on a different day than the title says, edit the
   title's end date to the actual one.
3. Mark the pull request ready and merge it if the workspace permits;
   otherwise hand it to the human as the last row of the merge-order
   table in `references/loop.md`.
4. Delete the branch once it has merged.

The discipline check's first outcome is where a new rotation meets the
previous one's open pull request: an expired window means close it out and
open your own, and a live window means this is a restart of that rotation.
