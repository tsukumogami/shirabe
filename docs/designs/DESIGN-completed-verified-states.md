---
schema: design/v1
status: Accepted
problem: |
  On a milestone roadmap one status, Done, has to say both that a milestone's
  work landed and that a non-delivering checker verified it, so landed work
  reads In progress until the verdict's edit merges and the coordinator holds
  dependents and successors behind a verdict owed. Whether a milestone is
  finished is decided separately in an awk reader, two Rust predicates and the
  picker, and they disagree on Dropped and on spellings.
decision: |
  A `roadmap/v4` schema with five statuses, and one status definition written
  as a data file in the roadmap skill's references, embedded in the shirabe
  binary at build time and read by the coordinate scripts with jq. Each status
  carries four properties (satisfies, closes, takes work, renders) that every
  reader asks instead of comparing words. The coordinator's merge-time
  roadmap step records Completed in the pending roadmap edit or a new one, a
  verdict owed becomes a pickable unit that refuses only its own milestone's
  delivery, and `shirabe roadmap migrate` moves a v2 or v3 roadmap to v4.
rationale: |
  A data file gives one authored copy that both the Rust binary and the shell
  scripts read without making every script depend on a newer binary, and it is
  the natural place a configurable workflow would later supply its own table.
  Folding the Completed record into the edit already pending keeps the
  one-pending-edit queue, and a separate schema version leaves every v1, v2
  and v3 roadmap untouched for hosts that haven't upgraded. Moving the whole
  roadmap parser into Rust was weighed and rejected as a larger change than
  the problem needs.
upstream: docs/prds/PRD-completed-verified-states.md
---

# DESIGN: Completed and Verified milestone states

## Status

Accepted

## Context and Problem Statement

The PRD this design implements
([PRD-completed-verified-states](../prds/PRD-completed-verified-states.md))
asks for a `roadmap/v4` schema whose milestones read Not started, In progress,
Completed, Verified or Dropped, with one shared status definition that every
shirabe component reads, coordinator behaviour that starts dependents on
Completed and treats a verdict owed as work rather than a gate, and a
migration from `roadmap/v2` and `roadmap/v3`.

Four places decide milestone status today, each with its own rule:

- `lib_roadmap_features` in `skills/coordinate/scripts/state-common.sh`, an awk
  and jq parser that every coordinate script reads roadmaps through, passes the
  raw `**Status:**` text on, and the picker (`pick-facts.sh`) then treats Done
  (or Shipped) as finished and Dropped as finished but never satisfying a
  dependency.
- `is_terminal_roadmap_status` in `crates/shirabe-validate/src/table.rs`
  treats Done and Closed as terminal for the Implementation Issues table
  checks.
- `feature_is_terminal` in `crates/shirabe/src/populate.rs` uses the same rule
  for striking rows, picking diagram classes and deciding whether a
  dependent is ready, so Dropped renders open and blocks its dependents.
- FC21 in `crates/shirabe-validate/src/checks.rs` holds the four status words
  of a milestone roadmap.

The coordinator scripts already call the `shirabe` binary (`roadmap-status.sh`
runs `shirabe roadmap populate`), but the roadmap parser they share is shell,
and the plugin's scripts and the installed binary are released together but
installed separately, so a script can meet a binary one release behind.

Two coordinator terms recur below. The **landed tick** is the evidence the
coordinator records when a unit's work is finished: its last pull request
merged, or, with nothing to merge, its work reported done. A **pending edit**
is a roadmap pull request the coordinator's run has opened and not yet seen
merge; the run holds at most one.

On a milestone roadmap the merge path writes no roadmap edit at all:
`roadmap-status.sh --unit` writes a `verdict-owed` Work row, the picker reads
it as `verdict_owed`, the dispatch check refuses the milestone with code 49,
`dispatch-worker.sh` exits 10 for any brief naming it (a successor's
included), and the closeout read blocks on it. The verdict step
(`roadmap-status.sh --verdict`) is the only writer of Done, and its
changes-needed edit leaves Status untouched.

## Decision Drivers

- One authored definition of every status's behaviour, read by shell and Rust
  alike (PRD R4, R5).
- No behaviour change on `roadmap/v1`, `v2`, `v3` or schema-less roadmaps
  beyond accepting Done, Shipped and Closed everywhere (R2).
- The coordinator's one-pending-roadmap-edit-at-a-time rule stays (R9).
- A plugin script may run against a binary one release older or newer; the
  new behaviour must not need the two to match exactly.
- Leave a seam for a later configurable workflow without building one.
- Keep the change within shirabe; consumers outside it adapt on their own.

## Considered Options

### Decision 1: Where the shared status definition lives and how each reader gets it

Key assumptions: the plugin directory the scripts run from always holds the
roadmap skill's references (they ship in one plugin), and `jq` is already a
hard dependency of every coordinate script.

#### Chosen: a data file embedded in Rust and read by the scripts

`skills/roadmap/references/milestone-statuses.json` holds a `version`
integer and, per schema family (`v1-v3` and `v4`), each status word, its
accepted spellings, the four properties from PRD R4 (`satisfies`, `closes`,
`takes_work`, `renders` with a `struck` flag and a diagram class), and for
`v4` the transition table from PRD R7 as `from`, `to` and `trigger` entries. The Rust crates embed it with
`include_str!` and parse it once into a `StatusTable` in a new
`crates/shirabe-validate/src/statuses.rs`, which `table.rs`, `checks.rs`
(FC21 and the new v4 checks) and `populate.rs` call instead of their own
predicates. The shell side gets a small `lib_status` helper in
`state-common.sh` that loads the same file from the scripts' own directory
(`$HERE/../../roadmap/references/milestone-statuses.json`, the path every
coordinate script can compute from `$HERE` as `pick-facts.sh` and
`roadmap-status.sh` already do) with jq, and answers
`lib_status_prop <schema> <status> <property>` and
`lib_status_move <from> <to> <trigger>`. A missing or malformed file, or a
`version` it doesn't know, stops the script with a message naming the path:
a coordinator that can't read the statuses must not guess them; `lib_roadmap_features`
adds the four properties to each milestone it emits, and `pick-facts.sh`,
`dispatch-common.sh`, `closeout-read.sh` and `progress-view.sh` read those
fields instead of comparing words. A unit test in Rust and a shell test both
load the file and assert the PRD's table, so the two readers can't drift from
the file, and `scripts/check-status-words.sh`, run in CI, fails when the PRD's
search pattern finds a status-word comparison outside `statuses.rs`,
`lib_status` and their tests.

`rules.rs` deliberately does not embed `skills/writing-style/rules.yaml`,
because a binary built from one release would keep checking an old word list
after the shipped file changed. The status table makes the opposite trade on
purpose. A validator that can't find the file, as happens when it runs in an
adopter's repository, must not fall back to accepting nothing, and the
binary's statuses only change in a release that also changes the scripts. The
`version` field makes the one remaining gap visible: `shirabe --version`
output names the table version it embeds, and the scripts refuse a table
version they don't know. `pre_action/registry.rs` already embeds a reference
file the same way.

#### Alternatives

- **The Rust binary owns the table and the scripts ask it** (`shirabe roadmap
  statuses --json`). One copy, but every coordinate script would need a binary
  at least as new as the plugin, and a host one release behind would see no
  statuses at all. Rejected for the version coupling.
- **Move the whole roadmap parser into Rust** (`shirabe roadmap features
  --json` replacing `lib_roadmap_features`). Removes the duplicate parser too,
  but rewrites the most-used function in the coordinate scripts and carries
  the same version coupling. Rejected as larger than the problem.
- **Two hand-kept copies, one in Rust and one in shell, held equal by a
  test.** Cheapest to write, but it keeps two authored copies, which is the
  failure the PRD names. Rejected.

### Decision 2: How `roadmap/v4` enters the validator and populate

#### Chosen: a fourth version of the existing Roadmap spec

`formats.rs` already lets the Roadmap spec read `roadmap/v2` and `roadmap/v3`
with a per-version section name and heading word. `roadmap/v4` is added as one
more accepted version with the `roadmap/v3` layout (`## Milestones`,
`### Milestone N:`). FC21's fixed four-word list becomes a lookup in the
status table for the document's schema, and three v4-only checks join it: a
status outside the v4 set (naming the milestone and the five allowed words), a
roadmap at Done with a milestone that doesn't close, and a block Status that
disagrees with its Progress row. Populate picks the schema family from the
frontmatter and asks the table for strike, class and dependency answers; it
declares the `completed` and `dropped` classes only on a v4 diagram, so v1 to
v3 output stays byte-identical.

#### Alternatives

- **A separate `RoadmapV4` spec.** Clean separation, but duplicates the
  section, heading and table logic the v2 and v3 paths already share.
  Rejected.

### Decision 3: How the coordinator records Completed and stops gating on a verdict owed

Key assumption: on a v4 roadmap the `landed` tick already fires at exactly the
point PRD R8 calls the work finished, for a merge and for a unit with nothing
to merge.

#### Chosen: the merge-time step writes Completed into the pending edit, and verdict-owed narrows to one milestone

On a `roadmap/v4` roadmap, `roadmap-status.sh --unit` does two things where it
did one. It still writes the `verdict-owed` Work row, which is now read as
"this milestone owes a verdict" rather than as a block. And it records the
Completed transition and the merged pull requests. When none of the run's
roadmap edits is pending, it opens one the way `--verdict` opens its edit
today. When one is pending (the run's record holds at most one, and it always
targets the run's own roadmap), it checks out that edit's branch in its
scratch worktree, commits the Completed change on top, pushes the branch
without force, and rewrites the pull request body so it lists every folded
change on a line of its own. A pending edit that isn't the run's own, or a
push that isn't a fast-forward, is refused, and the step falls back to
waiting for the pending edit to merge and then opening its own; the
milestone is still Completed for the coordinator in the meantime. The picker offers a `verdict_owed` milestone to the
verdict step as a unit of its own. The dispatch check's code 49 and
`dispatch-worker.sh`'s exit 10 apply only to a delivery brief for that same
milestone; a successor's brief, another milestone's brief and a dependent's
brief go through. On v4, `--verdict` no longer requires a `verdict-owed` row:
it accepts a verdict on a milestone in any status the transition table
allows, consumes the row when there is one, sets Verified on either verified
verdict and In progress on changes needed, and prints the held-dependent lines
the reopen path already prints. `--reopen` accepts a Completed milestone as
well as a Verified one. Every write first asks `lib_status_move`, so a move the
table doesn't list (a Verified milestone dropped, a changes-needed verdict on
a Verified milestone, a Dropped milestone moved anywhere) is refused before
anything is written. Every edit writes the block Status and the Progress row in one
pass. On v1 to v3 roadmaps none of this changes.

#### Alternatives

- **Derive Completed and never write it.** No extra edit, but the file, the
  populate output and anyone reading the roadmap never see it, and the
  migration has to write Completed anyway. Rejected (the PRD's decision).
- **Always open a separate Completed-only edit.** Simplest to code, but a
  Completed edit queued behind a pending verdict edit breaks the
  one-pending-edit rule or waits behind it. Rejected.

### Decision 4: How the migration is built

#### Chosen: `shirabe roadmap migrate` in the CLI crate, reusing the validator's parsers

A new subcommand beside `roadmap populate` in `crates/shirabe/src/`. It reads
the roadmap with the validator's existing feature parser, applies the PRD's
check order (already v4, then v1 or schema-less, then roadmap Done, then an
unparseable block), maps each Done, Shipped or Closed milestone by its latest
verdict line (the last `- <date>: <milestone> -- <verdict>` line naming it in
Progress, with `Feature N` read as `Milestone N`), converts a v2 `## Features`
layout to `## Milestones`, and writes the result to a temporary file in the
same directory, validates it, and renames it over the original. `--dry-run`
prints the lines and stops before writing.

#### Alternatives

- **A coordinate-side shell script.** Keeps it near the other roadmap edits,
  but the layout conversion and atomic write are far easier in the crate that
  already parses and validates roadmaps. Rejected.

## Decision Outcome

The four decisions fit together around the status table. The data file is the
single answer to "what does this status mean?", the validator and populate
read it through `statuses.rs`, the coordinate scripts read it through
`lib_status`, and the migration writes only words the v4 entry of that same
file accepts. The coordinator change is confined to the v4 branch of
`roadmap-status.sh` and to narrowing two refusals, so v1 to v3 runs follow
the paths they follow today. A later configurable workflow would supply its
own entry in the same shape; nothing here reads a workspace setting, so it
stays a seam rather than a feature.

## Solution Architecture

**Status table.** `milestone-statuses.json`:

```json
{
  "version": 1,
  "schemas": {
    "v1-v3": {
      "Done":    {"spellings": ["Done", "Shipped", "Closed"], "satisfies": true,  "closes": true, "takes_work": false, "renders": {"struck": true,  "class": "done"}},
      "Dropped": {"spellings": ["Dropped"], "satisfies": false, "closes": true, "takes_work": false, "renders": {"struck": false, "class": null}}
    },
    "v4": {
      "Completed": {"spellings": ["Completed"], "satisfies": true,  "closes": false, "takes_work": false, "renders": {"struck": false, "class": "completed"}},
      "Verified":  {"spellings": ["Verified"],  "satisfies": true,  "closes": true,  "takes_work": false, "renders": {"struck": true,  "class": "done"}},
      "Dropped":   {"spellings": ["Dropped"],   "satisfies": false, "closes": true,  "takes_work": false, "renders": {"struck": true,  "class": "dropped"}}
    }
  },
  "open": {"satisfies": false, "closes": false, "takes_work": true, "renders": {"struck": false, "class": null}},
  "transitions": {
    "v4": [
      {"from": ["Not started", "In progress"], "to": "Completed", "trigger": "finished"},
      {"from": ["Not started", "In progress", "Completed"], "to": "Verified", "trigger": "verified"},
      {"from": ["Not started", "In progress", "Completed"], "to": "In progress", "trigger": "changes-needed"},
      {"from": ["Completed", "Verified"], "to": "In progress", "trigger": "reopen"},
      {"from": ["Not started", "In progress", "Completed"], "to": "Dropped", "trigger": "drop"}
    ]
  }
}
```

Not started, In progress and any other value (a Needs annotation, for
instance) fall to `open`, whose class is chosen as today (ready, blocked or a
Needs class). The table for `v1-v3` lists only the statuses whose behaviour
differs from `open`, which is how today's readers already behave.

**Readers.**

| Reader | Asks | Today | After |
|---|---|---|---|
| `table.rs` FC07 to FC09 | is the row terminal | Done or Closed | `renders.struck` (Done on v1 to v3, Verified and Dropped on v4) |
| `checks.rs` FC21 and v4 checks | is the word allowed | fixed list | table entry exists for the schema |
| `populate.rs` | strike, class, dependency met | Done or Closed | `renders`, `satisfies` |
| `lib_roadmap_features` | (passes text) | raw text | adds the four properties per milestone |
| `pick-facts.sh` | pickable, dependency met | Done or Shipped; Dropped finished | `takes_work`, `satisfies` |
| `dispatch-common.sh`, `dispatch-worker.sh` | refuse | any verdict owed | verdict owed on the brief's own milestone only |
| `closeout-read.sh` | can the run close | verdict owed blocks | on v4, every milestone `closes`, which a milestone owing a verdict doesn't; v1 to v3 unchanged |
| `roadmap-status.sh` | may this move happen | no check | `lib_status_move` on v4; refusal names milestone, status and trigger |
| `progress-view.sh` | row text | `verified, ready to merge` | `checks passed, ready to merge`; `landed, verdict owed` |

**Coordinator flow on v4.**

```
last PR merges / landed tick
  -> roadmap-status.sh --unit
       writes verdict-owed row (milestone owes a verdict)
       pending edit?  yes -> add Completed + Delivered to it
                      no  -> open an edit with Completed + Delivered
  -> pick: dependents (satisfies) pickable; milestone not (takes_work=false)
           verdict step offered the milestone
  -> roadmap-status.sh --verdict
       verified*      -> Verified (block + Progress row)
       changes needed -> In progress, held-dependent lines
```

**Migration.** `shirabe roadmap migrate <roadmap> [--dry-run]` prints
`<milestone>: <old> -> <new> (<latest verdict line>|no verdict line)` per
milestone and, without `--dry-run`, writes through a temporary file and a
rename after validating the result.

## Implementation Approach

1. **Status table and Rust readers.** Add `milestone-statuses.json` and
   `statuses.rs`; switch `table.rs` and `populate.rs` to it for v1 to v3 and
   capture fixture outputs on the default branch first so the change is shown
   byte-identical (the Shipped and Closed spellings aside).
2. **`roadmap/v4` in the validator and populate.** Accept the version, add the
   three v4 checks and the two diagram classes, and the format reference's v4
   section with the status table, the transition table and the Active-edit
   rules.
3. **Shell reader.** Add `lib_status` and the four properties in
   `lib_roadmap_features`; switch `pick-facts.sh` and `closeout-read.sh` to
   them; add the word-comparison CI check.
4. **Verdict owed stops gating.** Narrow code 49 and exit 10 to the
   milestone's own delivery brief, offer the owed verdict as a unit, and list
   milestones that owe a verdict when a coordinator takes a roadmap up.
5. **Completed at the merge.** `--unit` records Completed in a new edit or by
   folding into the run's pending edit.
6. **Verdict and reopen on v4.** `--verdict` without the row precondition,
   Verified and In progress writes, held-dependent lines, `--reopen` on
   Completed, and the `lib_status_move` refusals.
7. **Progress view wording.** `landed, verdict owed` and `checks passed`.
8. **Migration.** `shirabe roadmap migrate` with its fixtures.
9. **Release notes.** The install-before-migrate order.

Steps 1 and 2 land before 3 to 7 so the scripts never read a table the binary
rejects; step 8 needs step 2.

## Security Considerations

The change reads and writes roadmap files and runs inside the existing
coordinate scripts, so its exposure is the same class as today's
`roadmap-status.sh` edits.

- **Untrusted roadmap text.** Status words and verdict lines come from
  roadmap files that authors and agents edit. They are matched against the
  table's closed set and never evaluated or interpolated into a shell
  command: `lib_status` passes them to jq with `--arg`, and the migration
  matches verdict lines with a fixed pattern and copies no other text into its
  output beyond the milestone tag and the matched line.
- **The status file itself.** It ships inside the plugin and is embedded in
  the binary at build time; nothing reads a workspace or roadmap copy, so a
  repository can't change how its own statuses behave. A later configurable
  workflow would have to add that deliberately, with its own review.
- **File writes.** The migration writes only the roadmap it was given, after
  resolving it and refusing a path outside the repository it runs in (populate
  has no such check today; the migration adds its own). It writes through a
  temporary file created exclusively (`create_new`) with an unpredictable name
  in the same directory and then renames it over the original, so a failure
  leaves the original and a planted temp file can't be followed.
- **Text copied out.** Milestone tags and verdict lines copied into the
  migration's output and into folded pull request bodies are matched against
  the fixed pattern `^- [0-9]{4}-[0-9]{2}-[0-9]{2}: (Feature|Milestone) [0-9]+
  -- (verified|verified with follow-ups|changes needed)`, and control
  characters are stripped before printing.
- **The status file on disk.** The scripts trust the file in the plugin
  directory they run from, the same trust they place in their own code, and
  fail closed when it is missing, malformed or of an unknown version.
- **Coordinator authority.** Starting dependents on Completed widens policy,
  not privilege: it lets through briefs the coordinator could already
  dispatch on a roadmap without a verdict owed. The verdict step stays bound
  by the existing checker rule, a verdict whose checker is the delivering
  session is refused, and folding into a pending edit is limited to the run's
  own edit and a fast-forward push.

## Consequences

**Positive**

- Landed work shows on the roadmap in the same pass it lands, and dependents
  and successors no longer wait on a verdict.
- One file answers every status question, and the Dropped and spelling
  disagreements end.
- v1 to v3 roadmaps and the hosts still driving them are unaffected.

**Negative**

- A second roadmap schema version to support alongside v2 and v3 until they
  are migrated.
- Folding Completed into a pending edit means that edit's pull request body
  changes after it was opened, which reviewers see as an amended pull request.
- A coordinator from a release before v4 reads a v4 roadmap as having no
  milestones.

**Mitigations**

- The release notes and format reference state the install-before-migrate
  order, and the migration refuses nothing on v2 or v3 a host can't still
  read.
- The amended pull request body names each folded Completed change in its own
  line, so the reviewer sees what was added.
