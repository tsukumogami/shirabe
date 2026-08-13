---
schema: plan/v1
status: Active
execution_mode: single-pr
milestone: Chain Cardinality
issue_count: 12
upstream: docs/designs/DESIGN-chain-cardinality.md
---

# PLAN: Chain Cardinality

## Status

Active

Single-pr. No GitHub milestone or issues are created; the outlines below are the work items,
and the ordering constraints in Implementation Sequence are the contract the design hands to
this document rather than to a requirement.

## Scope Summary

Repairs the four places the tooling assumes one-to-one document lineage, and gives both
parent skills and both head children a way to consume an upstream they did not produce.
Twelve work items across the validator crate, four skills, and two specification corrections.

## Decomposition Strategy

**Horizontal.** The design describes components with stable boundaries between them —
parser, chain walk, obligation map, conflict check, finalization walk, skill contracts — and
one of them is a prerequisite for three others. A walking skeleton would exercise an
end-to-end path that already exists and is not the thing at risk; the risk here is that each
component's repair is subtly wrong on a shape nobody has run, which depth-first work
surfaces and a thin slice does not.

Four ordering edges carry over from the design's cross-validation and from the requirements.
Each has a stated failure mode if inverted; see Implementation Sequence.

## Issue Outlines

### Issue 1: Sequence entries survive frontmatter parsing

**Goal**: The frontmatter parser preserves every entry of a sequence-valued field in written
order, so the value a reader receives is the value the author wrote.

**Acceptance Criteria**:
- Block, flow, and single-entry sequences all parse with every entry individually
  recoverable, in written order.
- A sequence-valued field other than `upstream:` behaves identically.
- A multi-line block scalar still reads as one value, not as many entries.
- The field's scalar value stays the empty string for a sequence, leaving the
  cross-implementation baseline untouched.
- The existing suite passes with no test modified.

**Dependencies**: None

**Complexity**: testable

### Issue 2: One normalization helper, three readers

**Goal**: The resolution check, the chain walk, and the finalization walk obtain entries
through a single helper, so reader agreement is a property of there being one reader.

**Acceptance Criteria**:
- The same written value yields the same entries to all three readers.
- No reader receives a joined multi-path string.
- Cross-repo references are marked not-locally-resolvable rather than removed from the entry
  list, and the finalization walk still stops at one — its existing test passes unmodified.
- Placeholder-shaped entries are skipped rather than reaching path resolution.
- The chain walk's own string surgery is deleted, not left as a second normalization.

**Dependencies**: <<ISSUE:1>>

**Complexity**: testable

### Issue 3: Resolution reporting: per-entry and empty-field

**Goal**: An author with a bad upstream is told which entry is bad, and an author with an
empty field is told the field is empty rather than shown a placeholder as a path.

**Acceptance Criteria**:
- A two-entry value with one unresolvable path reports exactly one finding, naming that path.
- Each empty spelling — null, empty sequence, scalar empty after trimming — reports exactly
  one field-level finding naming the field.
- A sequence with at least one blank entry reports a per-entry finding, never the field-level
  one.
- A value that is neither scalar nor sequence reports one finding saying so.

**Dependencies**: <<ISSUE:2>>

**Complexity**: testable

### Issue 4: The chain walk follows every upstream edge

**Goal**: Membership follows every upstream entry, so a document with two upstreams belongs
to both chains.

**Acceptance Criteria**:
- A document with two upstreams is a member of both chains.
- Two entries reconverging on one ancestor are recognized as a diamond, not reported as a
  cycle, and the chain is not dropped.
- The chain carries an explicit root path rather than relying on member ordering.
- The three preserved behaviors are unchanged: the walk stops at a head document while
  recording it as a member, a genuine cycle still reports with the path in walk order, and
  posture is still inferred from the root.

**Dependencies**: <<ISSUE:2>>

**Complexity**: critical

### Issue 5: Member-keyed obligation map and a single emitter

**Goal**: Both validator modes evaluate a document against every chain containing it, through
one emitter, so duplicate findings become unconstructible rather than deduplicated afterwards.

**Acceptance Criteria**:
- Both modes report the same findings for the same document over the same corpus.
- The same finding arising from several chains is reported once; findings differing in code,
  path, or required set are each reported.
- Renaming a document that nothing references changes no finding except the path a finding
  names.
- Corpus-integrity findings remain whole-corpus in both modes.
- Chain-targeted scope is a shallow closure, not transitive.

**Dependencies**: <<ISSUE:4>>

**Complexity**: critical

### Issue 6: Location check into the emitter; outline check stays chain-keyed

**Goal**: The two checks that sit outside the restructured path get an explicit home, closing
a mode disagreement that has nothing to do with chain selection.

**Acceptance Criteria**:
- A document in the wrong directory is reported identically by both modes.
- The outline-criteria check fires on the same documents it does today, evaluated per chain
  in scope.

**Dependencies**: <<ISSUE:5>>

**Complexity**: testable

### Issue 7: Root-versus-member repair

**Goal**: A document's requirement reflects whether a posture came from its own chain or from
a chain it merely sits above, removing a false positive that fires on correct lineage.

**Acceptance Criteria**:
- A live ROADMAP beneath a completing feature is no longer required to be deleted.
- A ROADMAP-rooted chain still requires its own absence at completion.
- The only corpus diffs are the two expected ones: a finding that disappears, and a finding
  whose expectation changes from absence to Active.

**Dependencies**: <<ISSUE:5>>

**Complexity**: testable

### Issue 8: Conflict finding, supersession, and severity

**Goal**: A document whose consumers demand states no single status satisfies is told so in
one message, instead of being handed contradictory instructions.

**Acceptance Criteria**:
- A document under two disjoint chains reports one conflict finding naming both chains and
  both required sets, and does not additionally report the pair it replaces.
- A document whose required sets intersect passes at the intersection with no conflict finding.
- Two chains requiring the same document absent agree rather than conflicting.
- Findings of other kinds on a conflicted document are still reported.
- The conflict finding is reported at the same severity, under the same modes, as what it
  replaced.
- Required sets are computed from effective postures, after the ready re-target.

**Dependencies**: <<ISSUE:7>>

**Complexity**: critical

### Issue 9: Consumer-aware, multi-branch finalization

**Goal**: The finalization walk stops retiring documents that something else still points at,
which is the path that produced the dangling references already in this repository.

**Acceptance Criteria**:
- A shared ancestor is not transitioned, and the report names the blocking documents and
  their statuses.
- An unshared chain finalizes exactly as it does today.
- A referrer already at a terminal status does not block.
- A document with two upstreams has both branches walked; an ancestor reachable through both
  is visited once.
- A block is a reported skip: the walk continues and the exit code is unaffected.
- Node paths are canonicalized before referrer lookup, and a canonicalization failure blocks.

**Dependencies**: <<ISSUE:2>>

**Complexity**: critical

### Issue 10: Fail-open note, extended to the partial case

**Goal**: When the retirement guard cannot run, the person running the command finds out.

**Acceptance Criteria**:
- Both total and partial index failure produce the note; the partial case is not silent.
- The note reaches the surfaced output, not only the structured report.
- A test asserts the note arrives on the surfaced path.

**Dependencies**: <<ISSUE:9>>

**Complexity**: testable

### Issue 11: The parent and child upstream contract

**Goal**: A run can consume an upstream it did not produce, recorded durably and carried into
the artifact's own frontmatter, without touching the positional argument contract.

**Acceptance Criteria**:
- Both parents and both head children accept the flag and behave identically.
- A supplied upstream reaches the produced document's frontmatter.
- A path in the positional slot is still rejected; a bare flag is rejected naming the missing
  argument.
- The value is recorded when supplied and absent when not; a recorded upstream that no longer
  resolves is surfaced on resume rather than ignored.
- A private upstream in a public repo omits the field rather than writing it.
- A non-durable working path is rejected, and an untracked path is rejected.
- The interpolation discipline is re-stated in both parents' own security sections, including
  the one that has none today.

**Dependencies**: <<ISSUE:8>>

**Complexity**: critical

### Issue 12: Pre-authoring notice, format references, and the two stale criteria

**Goal**: An author is told an existing upstream may apply before a new one is written for
them, and the specifications describe what the tooling actually does.

**Acceptance Criteria**:
- The notice appears before the chain head is authored, blocks nothing, and names no
  candidate.
- The chain-proposal option line the evals assert on is byte-unchanged.
- The notice does not fire when an upstream was supplied, or when the head child is held back.
- The format references name exactly the `upstream:` shapes the tooling accepts.
- Neither stale acceptance criterion still describes a positional path as slug-derived.
- Both keep-in-sync enforcement tables carry the four new rows.

**Dependencies**: <<ISSUE:11>>

**Complexity**: simple

## Implementation Sequence

**Critical path:** 1 → 2 → 4 → 5 → 7 → 8 → 11 → 12. Eight of twelve items sit on it, a
consequence of the parsing work sitting beneath everything and of the requirement that the
conflict diagnostic precede the upstream-recording work.

**Four ordering edges, each with a failure mode if inverted.**

*Parsing before finalization (2 → 9).* Created by this design rather than inherited: the walk
has its own scalar read today and depends on nothing, but it is being routed through the
shared helper, so landing it first means writing a reader that is about to be replaced.

*The multi-edge walk with or before the obligation map (4 → 5).* The map's correctness rests
on membership following every edge; built over a walk that still follows only the first, it is
a union over an incomplete set of chains and looks right while being wrong. This is the least
obvious of the four and the one most likely to be dropped.

*The root-versus-member repair before any disjointness is computed (7 → 8).* Not merely the
conflict work's first commit. Without it a member ROADMAP carries a requirement of absence
against its own chain's requirement of Active, and the conflict finding fires on correct
lineage — the exact failure the design's own driver forbids.

*The conflict diagnostic before the upstream-recording work (8 → 11).* This edge comes from
the requirements rather than the code: recording consumed upstreams makes concurrent chains
under one parent more common, and that is precisely the shape the diagnostic exists to catch.
It constrains the work rather than the software, which is why it lives here rather than as a
requirement with an acceptance criterion — a release ordering cannot be checked by inspecting
the artifact.

**Parallelizable:** items 3, 6, and 10 sit off the critical path and can proceed alongside it
once their single dependency lands. Item 9 depends only on the helper, so the whole
finalization branch can run in parallel with the evaluation and conflict branch.

**Verification gate before starting.** Establish whether any repository in the test set
currently exhibits the ROADMAP false positive, because item 7 removes it and that is a
deliberate change to a validation result. The invariance check has exactly two intended
exceptions, both from item 7: a finding that disappears where a live ROADMAP stopped being
told to delete itself, and a finding whose expectation changes where a retired ROADMAP above
a running chain moves from requiring absence to requiring Active. Every other difference is a
regression. Also confirm no document carries a present-but-empty upstream whose message item 3
would alter, and re-establish the cross-implementation parity baseline rather than assuming it,
since item 1 is what makes a sequence-valued fixture possible.
