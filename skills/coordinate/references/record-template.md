# The Record: Template and Procedures

What the record holds, and where it lives for each scope, are in
`skills/coordinate/SKILL.md`. This file holds the literal shapes and the
steps that open, update and close it. Load it when you open or update the
record.

## Branch and Host

| Scope | Host repository | Branch |
|---|---|---|
| Roadmap `docs/roadmaps/ROADMAP-<name>.md` | the roadmap's repository | `coordinate/roadmap-<name>` |
| Discipline `<name>` | the host repository the human named | `coordinate/discipline-<name>` |

One branch per scope, cut from the default branch. GitHub allows one open
pull request per head and base, so the record needs no other marker to be
unique. A successor finds it with:

```bash
gh pr list --repo <owner/repo> --head <branch> --base <default-branch> --state open --json number,url,body
```

If the host repository is public, the record never names a private
repository, path or issue. A holding that would need one is a scope
question for the human.

## The Branch Check

Run on every start, as part of the full reconcile, before the first
dispatch. Exactly one of four outcomes:

1. **The branch has an open pull request whose body carries the
   declaration line.** Adopt it. Never replace it or open a second one.
   For a discipline, first read the rotation's end date from the pull
   request's title, which carries it from the day the pull request opened:
   if that date has passed, the pull request belongs to the previous
   rotation, so close it out (see Closing a Rotation). If it
   merged and the branch is gone, open your own as in outcome 4; if the
   workspace reserves the merge for a person, hand it over and wait
   before opening yours.
2. **The branch has an open pull request without the declaration line.**
   Don't adopt it. Report the conflict and ask the human, because a pull
   request on the record's branch that isn't a record is a scope question.
3. **The branch exists and its last pull request was merged or closed.**
   Delete the branch and cut it again from the default branch, so a
   squash-merged history never comes back:

   ```bash
   git push origin --delete <branch>
   git switch -c <branch> origin/<default-branch>
   ```

4. **No branch exists.** Cut it from the default branch, push an empty
   commit, and open a draft pull request:

   ```bash
   git switch -c <branch> origin/<default-branch>
   git commit --allow-empty -m "docs(coordinate): open record for <scope>"
   git push origin HEAD:refs/heads/<branch>
   gh pr create --draft --repo <owner/repo> --head <branch> --base <default-branch> \
     --title "<title>" --body-file <body-file>
   ```

## The Pull Request

**Title.**

- Roadmap: `docs(coordinate): record for ROADMAP-<name>`
- Discipline: `docs(coordinate): <name> rotation <start> to <end>`, with
  both dates in `YYYY-MM-DD` form from the day it opens. The end date is
  the start plus the rotation's length. If the human ends the rotation
  early, or sets a new length, edit the end date to match in the same
  update that records the decision; the title is where a successor reads
  it.

**Body.** Part 1 is one prose sentence with no headings, true after merge.
Then a line that is exactly `---`, then Part 2. Part 2 uses no further
`---` line. Write the whole body to a file and pass it with `--body-file`;
never inline it into a command.

```markdown
Coordinator record for <docs/roadmaps/ROADMAP-<name>.md | the <name> discipline>, kept on <branch>.

---

> This is a **coordinator record** for <scope>.

Written: <YYYY-MM-DDTHH:MM:SSZ>

## Holdings

| Unit | Entry point | Mode | Session | Repo | Branch | Pull request | Dispatched |
|------|-------------|------|---------|------|--------|--------------|------------|
| <feature, issue, question or choice> | <skill> | <--auto, --interactive, flags> | <session name> | <owner/repo> | <branch> | <[#n](URL), or none yet> | <YYYY-MM-DD> |

## Deferrals

| Deferral | Reason | Raised |
|----------|--------|--------|
| <what> | <why not now> | <YYYY-MM-DD> |

## Side effects in flight

| Action | Target | Attempted | How to confirm |
|--------|--------|-----------|----------------|
| <merge, close, teardown> | <pull request, issue, session> | <YYYY-MM-DDTHH:MMZ> | <the read that settles it> |

## Reversals

| Date | Reversed | Now | Reason | From |
|------|----------|-----|--------|------|
| <YYYY-MM-DD> | <earlier decision> | <new decision> | <why> | <who decided> |
```

An empty section reads `None.` in place of its table. No table carries a
status, CI or merge-state column: those are read from GitHub every time. A
row leaves Side effects in flight once confirmed. Reversals only grow. A
deferral carried forward keeps its row with a new reason.

The declaration line is for readers. It is deliberately different from the
`This is a **coordination PR**` marker that `/execute` uses, so no gate
written for coordination pull requests ever parses a record.

**Updating.** Rewrite Part 2 whole from what you hold now, with a new
`Written:` time, and apply it with `gh pr edit <n> --body-file <file>`.
Every pull request in the record is a link. If a script edits the record
or the roadmap by replacing text, make it check that the text it replaces
matches exactly once before it writes; a replacement that matches nothing
succeeds silently and leaves the old text in place.

## Roadmap Progress

The record branch changes only the roadmap's Progress section. For each
Progress update:

1. Bring the branch up to date by merging the default branch in, never by
   rebasing, and never force-push:

   ```bash
   git fetch origin
   git merge --no-edit origin/<default-branch>
   ```

   or `gh api --method PUT repos/<owner/repo>/pulls/<n>/update-branch`.
2. If the merge conflicts on the roadmap, take the default branch's
   version (`git checkout --theirs -- <roadmap-path>`) and write Progress
   again from the Features section and the pull requests. Progress is
   derived, so writing it again is always safe.
3. If the default branch has deleted the roadmap, the merge takes the
   deletion and there is no further Progress commit.
4. Commit only the Progress section and push with a plain refspec:

   ```bash
   git add -- <roadmap-path>
   git commit -m "docs(coordinate): progress for ROADMAP-<name>"
   git push origin HEAD:refs/heads/<branch>
   ```

Never edit the Features section or the sections `shirabe roadmap populate`
owns, and never transition or delete the roadmap.

## Closing a Roadmap Record

When every feature reads terminal on GitHub, Holdings and Side effects in
flight are empty, and every deferral is filed or closed:

1. Merge the default branch in one last time (step 1 above).
2. Mark the pull request ready with `gh pr ready <n>`.
3. Merge it if the workspace permits; otherwise hand it to the human as the
   last row of the merge-order table in `references/loop.md`.
4. Delete the branch once it has merged.

The merge may carry the final Progress, or no file change at all if the
roadmap was already deleted. Either way it marks the record done. If GitHub
refuses to merge a pull request with no file change, hand the merge or the
close to the human, saying the roadmap finished. Don't add a commit to
create a diff.

## The Discipline Handoff

At rotation end, write `docs/disciplines/<name>.md`, one file per
discipline, overwritten each rotation. It is plain markdown, not a
validated shirabe artifact, and names no sessions or instances:

```markdown
# <name> handoff, <YYYY-MM-DD>

Rotation from <start> to <end>. Host repository: <owner/repo>. Record:
<pull request URL>, kept on coordinate/discipline-<name>.

## Holdings

| Unit | Entry point | Mode | Repo | Branch | Pull request | Dispatched |
|------|-------------|------|------|--------|--------------|------------|

## Deferrals

| Deferral | Reason | Raised |
|----------|--------|--------|

## Side effects in flight

| Action | Target | Attempted | How to confirm |
|--------|--------|-----------|----------------|

## Reversals

| Date | Reversed | Now | Reason | From |
|------|----------|-----|--------|------|

## Reasoning for the next rotation

<Prose: what this rotation learned that the tables can't say.>
```

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

The branch check's first outcome is where a new rotation meets the
previous one's open pull request: an expired window means close it out and
open your own, and a live window means this is a restart of that rotation.
