---
schema: brief/v1
status: Accepted
problem: |
  The two chains keep their state in koto sessions now, but /explore, /comp,
  /release and /work-on's no-koto fallback still write the staging folder on
  main. While any writer is left, the sweep, gate and report field built around
  the folder have to stay, and a chain can't be moved to another host at once.
outcome: |
  Whoever runs a shirabe skill finds its state in its own session by name, a
  pull request carries documents and nothing else with no sweep or gate standing
  guard, and an operator moves a topic's chain to another host with one command.
motivating_context: |
  The resume convention (docs/designs/current/DESIGN-resume-convention.md)
  moved the tactical and strategic chains onto session keys and named, in its
  "What later work moves" table, what it left: /comp, /release, /explore's own
  working files, /work-on's fallback file, and then the enforcement layer. The
  convention's own references also still carry three stale examples, filed as
  tsukumogami/shirabe#747.
---

# BRIEF: Leaf skills off the staging folder

## Status

Accepted

## Problem Statement

A shirabe skill that keeps intermediate state on disk puts it in `wip/`, a
folder committed to the feature branch and deleted before merge. The resume
convention replaced that folder with koto session keys for the eleven skills a
chain runs, but it stopped there on purpose, and a read of main today finds four
skills still writing the folder:

- **/explore** keeps its scope file, each research lead's output, the
  accumulated findings, its decision blocks, its crystallize verdict and the
  brief it hands /decision under `wip/`, and its resume table decides where to
  continue by testing which of those files exist. Its handoff to /scope or
  /charter already lives in the `explore-<topic>` session, so one /explore run
  now spans two stores, and the handoff it writes cites folder paths that are
  gone by the time anyone reads it.
- **/comp** writes its scope file and its three jury verdicts to the folder, and
  its setup still looks for a parent's state file there that no parent has
  written since /charter moved onto its session.
- **/release** writes the release range, the list of pull requests the release
  contains, the unattributed commits and the drafted notes to the folder,
  because its phases run as separate shell invocations and need somewhere to
  pass that membership along.
- **/work-on**'s context step falls back to writing `IMPLEMENTATION_CONTEXT.md`
  under the folder when koto isn't on the path, a fallback that no other part
  of /work-on reads and that its own template, which needs koto to run at all,
  can never reach.

Each writer keeps alive the machinery that exists only because of the folder.
/execute's node-push script sweeps the folder out of every node branch in a
commit of its own and refuses a pushed head that still carries it; /work-on and
/execute each gate their pull request on a branch check for leftover files;
/scope untracks its children's files before publishing and reports any it
pushed as `wip_paths=`, which /deliver relays in its own report. None of it can
come out while a skill still writes the folder, and nobody reading a run's
output can yet trust that a field named for the folder will always be empty.

A second gap sits beside the first. The convention fixed session names so that
importing a chain's sessions under their own names gives another host a
resumable chain, but there's no step that does it: an operator moving a topic
has to know every session name a chain might hold and run koto's import once
per name. And the convention's own reference documents still describe the
file-era world in three places a later skill move will copy from.

## User Outcome

A maintainer or an agent running any shirabe skill finds that skill's state in
its own session, `<skill>-<topic>`, by name, the same way the chains already
work, and an interrupted /explore, /comp or /release picks up from that session
instead of from files on the branch. A pull request from any shirabe workflow
carries the documents the work produced and nothing else, without a sweep commit
or a branch gate standing guard over it, and the reports a coordinator reads no
longer carry a field about a folder no skill writes. An operator who needs to
move a topic's work to another host does it with one command that knows which
sessions belong to the chain.

## User Journeys

### An interrupted exploration resumes from its session

A maintainer running `/explore` on a feasibility question loses the session
after the research leads have come back but before convergence. They re-invoke
`/explore <topic>` and the skill continues at convergence, reading the leads'
outputs and the scope from `explore-<topic>`, with no files under the branch to
find, commit or clean up. When the run hands off to /scope, the handoff it
leaves points at nothing that will disappear.

### A release keeps its membership out of the tree

A maintainer cuts a shirabe release with `/release`. The range, the pull
requests it contains and the drafted notes are kept in the release's session
between phases, the notes reach `gh release create` from a private scratch
directory, and the release branch never carries a working file that a later
cleanup has to remember to delete.

### A chain moves to another host in one step

An operator is moving work from one machine to another mid-chain. On the new
host they run one shared step naming the topic and the source workspace, and
every session the chain holds for that topic arrives under its own name, with
the ones the chain never opened skipped rather than reported as failures. The
chain resumes on the new host where it stopped.

### A coordinator reads a clean report

A coordinator's worker finishes a `/deliver` run, and the coordinator opens its
result on the request leg to decide whether the pull requests can land. The node
pull requests carry no sweep commit, the branch gate that looked for
leftover files is gone because there's nothing left to look for, and the report
has no `wip_paths=` line to check. The rule that governed the folder can then be
retired from the workspace configuration that carries it.

## Scope Boundary

**In:**

- Moving /explore's own working files, /comp's scope and verdicts, and
  /release's range, membership and notes onto session keys under the existing
  convention, using `scripts/skill-session.sh`, with each skill's resume
  behavior rewritten against keys.
- Removing /comp's read of a parent state file that no parent writes.
- Removing /work-on's fallback file, with what /work-on does when koto is
  unreachable recorded instead.
- A shared step that imports every session a chain holds for a topic, by name,
  built on koto's session import as it ships and not on parent-child lineage.
- Correcting the three stale examples in the convention's shared references
  that tsukumogami/shirabe#747 lists.
- Removing the enforcement layer once nothing writes the folder: /execute's
  sweep and its post-push check, the leftover-files branch rule and the gates
  that run it, /scope's untrack step and its `wip_paths=` report, and the
  field /deliver relays from it. This lands last.
- Tests that run each moved skill's real path and read its state back from the
  session.

**Out:**

- Changing the convention itself: the naming, key areas, dispatch key, close
  rule and reclaimable rule are settled. A gap found while moving a skill is
  raised as a question, not fixed here.
- The workspace rule that governs the folder. It lives in workspace
  configuration outside this repository; this feature proposes its retirement
  and doesn't edit it.
- The coordinate skill's own state and its record scripts, which later work
  moves onto the coordinator's session.
- Any change to koto. A storage shape koto lacks is proposed as a koto feature,
  not worked around here.
- Pruning finished sessions, which the reclaimable rule only evaluates.
- Rules that keep a durable document from citing a staging path (the upstream
  guards and the per-skill finalize greps): they protect committed documents,
  not the folder, and stay.

## Downstream Artifacts

- `docs/prds/PRD-leaf-skills-off-folder.md` (to be written): the requirements.

## References

- `references/skill-session-convention.md`
- `docs/designs/current/DESIGN-resume-convention.md`
- `docs/prds/PRD-resume-convention.md`
