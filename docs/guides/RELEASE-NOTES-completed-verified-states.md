# Completed and Verified milestone states

A milestone roadmap used to say one thing about finished work: Done, and
only once its verdict merged. Work that had landed and was waiting on its
verdict read as unfinished to everyone looking at the roadmap, and the
coordinator kept it out of the way of the milestones that depended on it.
`roadmap/v4` splits that word in two. A milestone reads Completed when its
work lands and Verified when a verdict says it holds. Existing roadmaps keep
validating; moving one to v4 is a single command, but only after every
coordinator host runs this release (see Rolling it out).

## What's new

**`schema: roadmap/v4` and its five statuses.** A v4 roadmap has the
`roadmap/v3` layout. Its milestones read exactly one of:

- `Not started` and `In progress`: work still to do. Dependents wait, and
  the coordinator may dispatch it.
- `Completed`: the work has landed and its verdict is owed. Dependents may
  start straight away, the coordinator dispatches no more delivery for it,
  and the roadmap stays open until a verdict moves it on.
- `Verified`: a verified or verified-with-follow-ups verdict says the
  milestone holds. It satisfies its dependents and closes.
- `Dropped`: an author's edit, with a reason. It closes but never
  satisfies, so a milestone that depends only on a Dropped one stays
  blocked.

Done, Shipped and Closed aren't v4 statuses, and `shirabe validate` reports
one on a v4 roadmap, naming the milestone and the five words. It also
reports a roadmap that reads Done while a milestone is still Completed, and
a milestone whose block and Progress row disagree. The statuses, the
transitions between them and the optional Progress table are in
`skills/roadmap/references/roadmap-format.md`, roadmap/v4.

**One status table for every reader.** The properties behind those
readings (whether a status satisfies its dependents, closes, takes work, and
how populate renders it) live in one file,
`skills/roadmap/references/milestone-statuses.json`. The validator,
populate, the coordinator's picker, its dispatch check and its close-out
all read it, so they can't disagree about what a word means. A CI check,
`scripts/check-status-words.sh`, fails a pull request that compares a
milestone status word anywhere else.

**Shipped and Closed now read as Done on older schemas.** On `roadmap/v1`
to `roadmap/v3`, a milestone at Shipped or Closed is treated as Done
everywhere: validation, populate and the picker. Before, some readers
accepted only the word Done. Nothing on your side has to change, but a
roadmap that used Shipped for work it didn't consider finished will now see
that milestone's dependents become pickable.

**The coordinator records Completed when the work lands.** On a v4 roadmap
the coordinator writes Completed and the delivering pull requests at the
merge, folded into a roadmap edit it already has pending, or in a new one.
The milestone's verdict becomes owed, and the progress view lists it as
`landed, verdict owed` until the verdict is given. A verdict owed holds back
only its own milestone: its dependents are picked as soon as it lands.
`--verdict` sets Verified on a verified verdict and In progress on changes
needed, and `--reopen` sets a Completed or Verified milestone back to In
progress. Every move goes through the table's transitions, and one the table
doesn't list is refused with the milestone, its status and the trigger
named.

**"Checks passed", not "verified", for pull requests.** The progress view
and the reconcile report used to call a pull request whose checks had
passed "verified", which now collides with a Verified milestone. They say
`checks passed` instead, for example `checks passed, ready to merge`.

## Rolling it out

**Install this release on every coordinator host first.** A coordinator
from an earlier release reads a `roadmap/v4` roadmap as having no
milestones at all. Upgrade every host that runs `/coordinate`, and finish
that before you migrate any roadmap.

**Preview the move with `--dry-run`.** Run

```bash
shirabe roadmap migrate docs/roadmaps/ROADMAP-<name>.md --dry-run
```

It prints one line per milestone, `<tag>: <old> -> <new>`, with the verdict
line it based the new status on, and writes nothing. A milestone at Done,
Shipped or Closed becomes Verified when its latest verdict line in Progress
is verified or verified with follow-ups, and Completed otherwise (no verdict
line, or a changes-needed one last). Every other status is kept. A
`roadmap/v2` roadmap's `## Features` layout becomes `## Milestones` in the
same pass. The preview also validates the migrated result, so a roadmap the
real run would refuse is refused here too, with the same findings and exit
status.

**Then migrate for real.** The same command without `--dry-run` rewrites
the file: the schema line, each changed milestone's Status and its Progress
row. It validates the result first and leaves the file untouched when
validation fails. A roadmap already at `roadmap/v4` prints
`already roadmap/v4` and is left alone.

**A finished roadmap isn't migrated.** `migrate` refuses a roadmap whose own
status is Done. Its milestones already ended under the old rules, and
there's nothing a v4 status would change. It also refuses `roadmap/v1` and a
roadmap with no schema line.

**Re-populate after migrating.** `migrate` changes statuses but not the
generated sections, so the Implementation Issues table and the dependency
graph still show the old renderings. Run

```bash
shirabe roadmap populate docs/roadmaps/ROADMAP-<name>.md
```

once on each migrated roadmap, so Completed milestones pick up their
`completed` class, and commit that alongside the migration.
