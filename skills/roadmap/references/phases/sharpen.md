# Sharpen a Milestone in Place

The procedure behind the Active-roadmap resume row in `SKILL.md`. It changes
one milestone's Evidence or Left open on an Active milestone roadmap
(`roadmap/v2` or `roadmap/v3`) and nothing else, which a milestone roadmap allows without a new roadmap
(`references/roadmap-format.md`, Milestones, What may change while it is
Active).

## When It Applies

`/roadmap` found `docs/roadmaps/ROADMAP-<topic>.md` at `status: Active`.

- **`schema: roadmap/v2` or `schema: roadmap/v3`** -- offer two choices: sharpen one milestone's
  Evidence or Left open in place, or start a new roadmap. Recommend
  sharpening when the author's request names a check that can't be judged
  as written or a decision that turned out to belong to the delivering
  session; recommend a new roadmap when they want to add, remove, reorder or
  retitle milestones, change dependencies, or widen an Outcome.
- **`schema: roadmap/v1`** -- start a new roadmap is the only choice. Say
  that sharpening in place needs a milestone roadmap first, which is a
  migration (`references/roadmap-format.md`, Milestones, Migrating a
  roadmap), not something this procedure does.

The procedure is the same on v2 and v3; only the words differ (a v2 roadmap's
milestones sit under `## Features`, a v3 roadmap's under `## Milestones`).
Sharpening never moves a v2 roadmap to v3: that is its own edit.

A Draft roadmap is edited through the usual resume at Phase 3, and a Done
one takes its own resume row; neither uses this procedure.

Under `--auto`, take the recommendation and say which choice was taken.

## Steps

1. **Pick the milestone and the field.** Ask which milestone (by tag) and
   whether its Evidence or its Left open changes, unless the request already
   says. Read that milestone's current text.

2. **Write the sharper text.** For Evidence, every clause still follows the
   format reference's Evidence rule: it names who checks, from what starting
   state, what they do and what they see; a merge, a test run or an artifact
   existing is still not Evidence, and neither is the file, script, function
   or line that implements the check (that goes in Left open). Sharpening may add a clause, split one, or make one concrete;
   it must not narrow what the Outcome promises. For Left open, move a
   how-decision in or out; anything whose absence would make the Outcome
   false stays out of Left open. If the change the author wants narrows the
   Outcome, stop: that takes a dated amendment line in Progress
   (`- YYYY-MM-DD: <tag> Outcome amended -- <what changed and why>`) and
   the author's say-so, not this procedure.

3. **Edit only that field.** Replace the field's lines (its marker line and
   the lines up to the next blank line, field line or heading) and leave
   every other line of the file as it was. The status stays Active.

4. **Check it.**

   ```bash
   shirabe validate docs/roadmaps/ROADMAP-<topic>.md
   git diff --stat -- docs/roadmaps/ROADMAP-<topic>.md
   git diff -- docs/roadmaps/ROADMAP-<topic>.md
   ```

   Validation passes, and the diff touches only the chosen field's lines in
   the chosen milestone. If either fails, fix the edit before going on.

5. **Commit** on the current branch:

   ```
   docs(roadmap): sharpen <tag> <Evidence|Left open> in ROADMAP-<topic>
   ```

   Then say what changed, in a sentence, and that the roadmap is still
   Active.
