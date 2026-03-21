# Maintainability Review Round 2: Decision Framework Design

Reviewer focus: critique what changed since round 1. Prior feedback on compiled prompt
drift (D8), cross-cutting protocol copies (shared reference), and format coupling (D11)
was incorporated. This review evaluates whether the revisions hold up and identifies
new risks introduced by D12-D14.

## 1. D12 Tier Annotations: Discoverability Gap

The design places `<!-- decision-tier: N -->` annotations in 39 phase file locations.
These are HTML comments -- invisible in rendered markdown, invisible in most editor
outlines, and not greppable by anyone who doesn't already know the exact syntax.

The design mentions a "decision point manifest" as a Phase 1 deliverable that catalogues
all 39 blocking points with "locations, categories, pre-classified tiers, and expected
behavior in each mode." This is the right idea. But the design doesn't specify:

- **Format**: is the manifest a markdown table? JSON? A reference file in `references/`?
- **Sync mechanism**: when an annotation changes in a phase file, what ensures the
  manifest updates? The annotations are the runtime truth (agents read them); the
  manifest is the human-readable catalogue. These are two representations of the same
  data with no defined sync direction.
- **Ownership**: which Phase 1 deliverable *is* the manifest? It appears in a bullet
  list alongside 7 other items. Is it a standalone reference file or a section in
  `references/decision-protocol.md`?

The practical risk: someone changes a tier annotation from 2 to 3 in a phase file.
The manifest still says tier 2. No CI catches this because the design doesn't propose
any validation. Over time the manifest becomes stale and developers stop trusting it,
falling back to grepping for `decision-tier:` -- exactly the discoverability problem
the manifest was supposed to solve.

**Recommendation:** Define the manifest as the single source of truth. Phase files
reference it by decision point ID rather than embedding tier values. This inverts
the current proposal (annotations reference manifest, not manifest references
annotations) and eliminates dual-write. If that's too much indirection for agents,
at minimum add a CI grep that extracts all `<!-- decision-tier: N -->` annotations
and diffs them against the manifest.

## 2. D13 Auto-Split: Unspecified Workflow Mechanics

D13 says that at 8-9 decisions, Phase 1 "presents a concrete split proposal" and in
`--auto` mode "executes the split." This is the most consequential auto-mode behavior
in the design, and its mechanics are entirely unspecified.

Questions the design doesn't answer:

- **Branch strategy**: does the split create two design docs on the same branch? Two
  branches? The design skill's Phase 0 creates a single topic branch. A split produces
  two design docs, each of which needs its own topic branch per the existing convention.
  Mid-workflow branch creation is not part of the current resume logic.
- **Resume after split**: the design skill's resume logic (SKILL.md lines 162-170)
  maps artifact existence to phases. After a split in Phase 1, there are two design
  doc skeletons. Which one does resume pick up? Both? Neither? The resume logic has
  no concept of sibling documents.
- **PR creation**: the design skill creates one PR per design doc. A split means two
  PRs. Does Phase 7 create both? Does the user get prompted for each?
- **Cross-references**: if the original problem statement spans both split docs, how
  do they reference each other? The design mentions "concrete split proposal" but not
  the artifact format of the proposal or the cross-reference mechanism.
- **Split criteria**: "presents a concrete split proposal" implies the agent decides
  how to split. What signals does it use? Decision coupling? Topic clustering? The
  design's own split criterion ("options for one question don't affect options for
  another") gives a necessary condition for independence but not a grouping heuristic.

In `--auto` mode, the agent executes this split without confirmation and then continues.
The design doesn't say whether the agent continues with one of the resulting docs (which
one?) or completes both sequentially, or fans out parallel design workflows. Any of these
has different implications for context window usage and wip/ artifact naming.

**Recommendation:** Either (a) scope D13 auto-split to interactive mode only (auto mode
warns and continues with all decisions in one doc, accepting the readability cost), or
(b) specify the split mechanics: branch strategy, resume behavior, artifact naming for
sibling docs, and which doc the workflow continues with.

## 3. D14 Consolidated File: Dual-Write Not Eliminated

D14 consolidates the decision manifest and assumptions file into a single
`wip/<workflow>_<topic>_decisions.md`. The stated goal is "one extra file per invocation
instead of two." But the design still has decision blocks inline in source artifacts
(the wip/ research files, the design doc itself) AND entries in the consolidated file.

When an assumption is invalidated, what gets updated?

- The consolidated `decisions.md` has the assumption detail with "if wrong" restart path.
  This is clearly the file the user edits.
- The inline decision block (in the design doc's Considered Options section or in a wip/
  research file) has `status="assumed"`. Does this change to `status="confirmed"` or
  `status="invalidated"`?
- The terminal summary and PR body are "read-only views" per D2. They don't update. But
  the inline block and the consolidated file are both writable, and the design doesn't
  say which is the source of truth for status.

The design says the consolidated file is "append-only during execution and serves as the
source of truth for the terminal summary and PR body section." But the inline decision
blocks also carry status attributes. An agent reading a design doc sees
`status="assumed"` in the inline block. An agent reading the consolidated file sees the
same decision with potentially different metadata. The source-of-truth question is
unresolved for post-execution edits (assumption invalidation).

Additionally, the design introduces two coordination files for the design skill:
- `wip/design_<topic>_decisions.json` -- coordination manifest (Phase 3 deliverable,
  used for parallel agent coordination)
- `wip/design_<topic>_decisions.md` -- consolidated decisions file (D14, used for
  assumption tracking and review)

These serve different purposes but the naming overlap (`decisions.json` vs `decisions.md`)
is confusing. The `.json` file is a technical coordination artifact for cross-validation.
The `.md` file is a human-readable review surface. Both contain decision metadata. A
developer modifying the design skill's cross-validation phase needs to understand which
file to read from and write to in each context. The design doesn't clarify this.

**Recommendation:** (a) Declare the consolidated `decisions.md` as the sole source of
truth for decision status. Inline blocks carry status at write-time but are not updated
post-execution -- they're snapshots. Document this explicitly. (b) Rename the
coordination manifest to something that doesn't overlap with the consolidated file --
e.g., `wip/design_<topic>_coordination.json` or `wip/design_<topic>_cross-val.json`.

## 4. Phase 1 Scope: 8 Deliverables Is a Lot

Phase 1 deliverables:
1. `references/decision-protocol.md` (shared protocol spec)
2. `--auto` flag handling in each SKILL.md (5 skills)
3. `--max-rounds=N` flag handling with per-skill defaults
4. Consolidated decisions file format
5. Decision point manifest (39 entries)
6. `<!-- decision-tier: N -->` annotations in 39 locations
7. Review surface (terminal summary + PR body template)
8. Progress feedback protocol

Items 1-4 are the foundation and form a coherent unit. Items 5-6 are a cataloguing
exercise that touches every phase file across every skill. Items 7-8 are output
formatting concerns.

The risk isn't that Phase 1 is too large to plan -- it's that items 5-6 create a
39-file changeset that will produce merge conflicts with any parallel work on phase
files. The annotation pass is mechanical but touches the same files that Phase 2
(decision skill creation) and Phase 3 (design skill restructuring) will modify.

**Recommendation:** Split Phase 1 into two sub-phases:
- Phase 1a: items 1-4, 7-8 (protocol, flags, formats, surfaces). Self-contained,
  no cross-skill file edits beyond SKILL.md flag parsing.
- Phase 1b: items 5-6 (manifest + annotations). Execute after Phase 2-3 are designed
  but before they're implemented, so annotations land in the final phase file structure
  rather than the pre-restructuring files.

## Top 3 Maintenance Risks (Post-Revision)

### Risk 1: Annotation-Manifest Drift (New, from D12)

39 HTML comment annotations across phase files with a separate manifest that catalogues
them. Two representations of the same data, no sync mechanism, no CI validation. The
manifest will go stale within the first quarter of active development, removing its
value as a discoverability aid and leaving developers to grep for annotations they may
not know the syntax of.

**Why it's the top risk:** This is an exact replay of the compiled-prompt-drift problem
from round 1, just with a different artifact pair. The design fixed D8 by making agents
read SKILL.md directly (eliminating the second representation). D12 introduces a new
second representation with the same maintenance characteristics.

### Risk 2: Auto-Split Has No Defined Mechanics (New, from D13)

The most consequential --auto behavior (splitting a design into multiple docs) has no
specification for branch strategy, resume logic, artifact naming, or workflow
continuation. An implementer will have to make these decisions at implementation time,
outside the design's guidance. Those implementation-time decisions won't get the
adversarial evaluation the design framework itself prescribes.

**Why it's #2:** Unlike annotation drift (which degrades slowly), a broken auto-split
produces immediate user-visible failures: orphaned branches, duplicate wip/ artifacts,
or a workflow that hangs because resume logic can't determine which split doc to
continue with.

### Risk 3: Inline Block vs. Consolidated File Source-of-Truth Ambiguity (Revised, from D14)

D14 consolidated two files into one but didn't resolve the dual-write between inline
decision blocks and the consolidated file. During execution, both are written. After
execution, the invalidation path is undefined. The two similarly-named coordination
files (`decisions.json` and `decisions.md`) add confusion about which artifact an
agent should consult in which context.

**Why it's #3:** The ambiguity won't cause failures during happy-path execution (both
artifacts are written in sequence). It surfaces when assumptions are invalidated or
when a resumed workflow needs to reconcile stale inline blocks with updated
consolidated entries. That's an error path, so it'll be discovered late and be harder
to fix.
