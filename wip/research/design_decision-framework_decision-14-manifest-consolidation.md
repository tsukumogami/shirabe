# Decision 14: Manifest and Assumption File Consolidation

## Context

The current design specifies two new wip/ files per workflow invocation:
- `wip/<workflow>_<topic>_assumptions.md` -- assumption tracking (source of truth for all assumed decisions)
- `wip/<workflow>_<topic>_decision-manifest.md` -- decision index (pointers to inline decision blocks across all artifacts)

For work-on, this doubles the wip/ file count from 2 to 4. The usability reviewer flagged artifact proliferation as a top-3 daily-user frustration (review-usability.md, item 3): "the design should consider consolidating the assumptions and decision manifests into a single file, or embedding them in the existing skill artifacts rather than creating parallel files."

The lightweight framework research (r2_lead-lightweight-framework.md, Section 4) recommends the manifest as a "derived index" -- it's rebuilt whenever a decision block is written, it's append-only, and if lost, all decisions are still in their source artifacts. The assumptions file (r2_lead-non-interactive.md, Question 2) is also incremental and serves as the review surface for --auto runs.

## Decision Question

Should assumptions and decision manifests be separate files or consolidated?

## Options Analyzed

### Option A: Two separate files (current design)

The assumptions file is the review surface for --auto mode. The decision manifest is the index pointing to inline decision blocks across artifacts. Clear separation of concerns.

**Strengths:**
- Each file has a single purpose
- The manifest is a pure index (locations only); the assumptions file has rich content (evidence, confidence, re-execution paths)
- Easier to regenerate the manifest independently since it's just pointers

**Weaknesses:**
- 2 extra files per invocation. For work-on (currently 2 files), this is a 100% increase in wip/ clutter.
- The manifest and assumptions file share significant overlap. Every assumed decision appears in both: as a row in the manifest index AND as a full entry in the assumptions file. Confirmed decisions appear only in the manifest. This means the manifest is nearly a subset of the assumptions file's content.
- Resume logic must track two files instead of one.
- Users must know which file to open for which purpose. The manifest says "where is decision X?" The assumptions file says "what did the agent assume?" In practice, users want both answers from the same surface.

### Option B: Single consolidated file

One file: `wip/<workflow>_<topic>_decisions.md`. Contains the decision index at the top (table with ID, artifact, phase, status) and the full assumption records below, organized by decision ID.

**Strengths:**
- 1 extra file per invocation instead of 2. For work-on, the file count goes from 2 to 3 instead of 2 to 4.
- Single source of truth for "what decisions were made and what was assumed." The index table at the top serves the manifest's purpose; the detailed entries below serve the assumptions file's purpose.
- Resume logic checks one file. If it exists, the workflow had decision tracking enabled.
- The review experience improves: user opens one file, sees the summary table, scrolls to any entry that looks suspicious.
- The assumption ID scheme (A1, A2...) and the decision block ID scheme (kebab-case) can coexist. The index table maps between them.

**Weaknesses:**
- File serves two purposes (index + details), which is a mild violation of single-responsibility.
- If the file gets large (20+ decisions in a complex design run), it's a long scroll. But the index table at the top mitigates this -- it's the same pattern as a table of contents.
- Confirmed decisions (no assumptions) get index entries but minimal detail sections, creating some structural asymmetry.

### Option C: Embed in existing artifacts, derive at review time

No new files. Decision blocks stay inline in wip/ artifacts. At workflow end, the agent scans all wip/ files for `<!-- decision:start -->` blocks and generates a terminal summary. Assumptions are part of each inline block's Assumptions field.

**Strengths:**
- Zero additional files. No wip/ clutter increase at all.
- Decision blocks already live inline (the lightweight framework requires this). No dual-write.
- Matches the explore skill's existing pattern: `explore_<topic>_decisions.md` is already a lightweight decisions record, and the inline blocks capture rationale at the point of decision.

**Weaknesses:**
- The review experience degrades significantly. To find all assumptions, the user must open every wip/ artifact and search for decision blocks, or rely on the terminal summary (which is ephemeral -- lost if the terminal scrolls or the session ends).
- No persistent review surface. The terminal summary and PR body section are "read-only views" (per the non-interactive design), but they're not durable. If the user comes back the next day, there's no single file to open.
- Resume logic can't easily determine "which decisions have been made so far" without scanning all files. This is slower and more fragile than checking a single index.
- Assumption invalidation via `--correct A2=...` requires a stable ID scheme. Without a central file, IDs must be derived from scanning, which means they could shift if artifacts change.

### Option D: Single file for lightweight, separate for heavyweight

Lightweight decisions go inline in existing artifacts. Heavyweight decision reports are their own files (they already are -- `wip/design_<topic>_decision_<N>_report.md`). A single manifest/index file points to both.

**Strengths:**
- Heavyweight reports justify their own files (they're 50+ lines of structured analysis).
- Lightweight decisions don't create extra files.

**Weaknesses:**
- Still requires an index file, so the file count increase is 1 (same as Option B).
- But Option B already handles this: the consolidated file indexes both lightweight (inline blocks) and heavyweight (separate report files) decisions. Option D is Option B minus the assumption details in the index file.
- The split logic ("is this lightweight or heavyweight?") adds a branching decision to the recording protocol. Option B treats all decisions uniformly in the index.

## Analysis

### The review experience

The primary use case for these files is end-of-workflow review: the user finishes an --auto run and wants to check what was assumed. Option B gives the best review experience: one file, summary table at top, details below. Option A forces the user to cross-reference two files. Option C has no persistent review surface. Option D is functionally identical to Option B for the reviewer.

### Resume logic

The assumptions file currently serves a dual purpose in resume detection: if it exists, the workflow was running in auto mode. Option B preserves this -- if `wip/<workflow>_<topic>_decisions.md` exists, the workflow had decision tracking. Option C breaks this because there's no single file to check. Option A works but requires checking two files.

### The manifest's actual value

The manifest's purpose is to answer: "where are all the decisions?" In Option C (inline-only), this requires scanning. But in Options A, B, and D, the manifest is a table. The question is whether that table deserves its own file or can live as a section within a broader file.

The manifest is a derived artifact. The lightweight framework research explicitly says: "The manifest is rebuilt whenever a new decision block is written. It's the index, not the source of truth. If it gets lost, all decisions are still in their artifacts." A derived artifact that can be regenerated from primary sources doesn't need its own file. It needs to exist somewhere persistent, but a section within the consolidated decisions file satisfies that.

### The assumptions file's actual value

The assumptions file is a primary artifact -- it contains unique content (confidence levels, re-execution paths, the tiered organization by approach/scope/convention). This content can't be regenerated from inline decision blocks alone because the blocks don't have the assumption-level categorization or the "If wrong" re-execution guidance.

This means the assumptions file has more justification for persistence than the manifest. But the two are complementary: the manifest says where decisions live, the assumptions file says what was assumed. Combining them into one file loses nothing because the index table can include a "Status" column (confirmed/assumed) that distinguishes the two.

### wip/ cleanup

All options are compatible with the existing cleanup pattern (clean wip/ before merge, squash-merge hides branch artifacts). Option B reduces the cleanup surface from 2 files to 1. Option C eliminates it entirely but at the cost of the review experience.

## Choice

<!-- decision:start id="manifest-consolidation" status="confirmed" -->
### Decision: Manifest and assumption file consolidation

**Question:** Should assumptions and decision manifests be separate files or consolidated?

**Evidence:** The manifest is a derived index (can be regenerated from inline decision blocks). The assumptions file contains primary content (confidence, re-execution paths, tiered categorization). Both share significant overlap -- every assumed decision appears in both. The usability review flagged 2 extra files per invocation as a top-3 concern. Resume logic benefits from a single file check.

**Choice:** Option B -- single consolidated file (`wip/<workflow>_<topic>_decisions.md`)

**Alternatives considered:**
- Option A (two separate files): doubles wip/ file count per invocation, forces cross-referencing for review, provides separation of concerns that doesn't justify the usability cost.
- Option C (no new files, derive at review): eliminates file overhead but destroys the persistent review surface and breaks stable ID-based assumption invalidation (`--correct A2=...`). The terminal summary is ephemeral.
- Option D (split by weight): functionally identical to Option B for review purposes, adds unnecessary branching logic to the recording protocol.

**Assumptions:**
- A single consolidated file won't grow too large for practical use. In the worst case (complex design run with 20+ decisions), the file is ~200-300 lines. The index table at the top provides fast navigation.
- The tiered assumption categorization (approach/scope/convention) can coexist with the decision index in one file. The index table covers all decisions; the detailed sections below cover only assumed decisions with their tier-specific fields.

**Reversibility:** High. Splitting the file back into two is a mechanical refactoring of the template. No protocol changes needed -- just where content is written.
<!-- decision:end -->

## Consolidated File Structure

```markdown
# Decisions: <topic>

## Index

| ID | Location | Phase | Status | Summary |
|----|----------|-------|--------|---------|
| decomp-strategy | (inline) plan_foo_decomposition.md | Plan/3 | assumed | Horizontal over walking skeleton |
| cache-approach | decision_2_report.md | Design/2 | confirmed | Redis-backed cache |
| api-pagination | (inline) design_foo_arch.md | Design/3 | assumed | Offset pagination assumed |

## Assumptions

3 assumptions made during execution.
- 1 approach assumption (review recommended)
- 1 scope assumption (spot-check recommended)
- 1 convention assumption (review if unexpected)

### Approach Assumptions

#### A1: Horizontal over walking skeleton (decomp-strategy)

- **Phase**: Plan/Phase 3
- **Evidence**: Component coupling is moderate; interfaces are well-defined.
- **If wrong**: Re-execute from Plan/Phase 3.
- **Confidence**: Medium

### Scope Assumptions

#### A2: API supports offset pagination (api-pagination)

- **Phase**: Design/Phase 3
- **Evidence**: Convention-based; most REST APIs in codebase use offset pagination.
- **If wrong**: Re-execute from Design/Phase 4; data layer needs rewrite.
- **Confidence**: Medium

### Convention Assumptions

(none)
```

Key structural points:
- The Index table replaces the decision-manifest.md entirely. It includes all decisions (confirmed and assumed).
- The Assumptions section replaces the assumptions.md entirely. It includes only assumed decisions, organized by tier.
- The `ID` column in the index maps to the `(decision-id)` parenthetical in assumption entries, connecting the two views.
- Confirmed decisions appear only in the index table -- they need no detailed assumption record because nothing was assumed.

## Impact on Design

The following design references need updating:
- Component 4 (non-interactive mode): change `wip/<skill>_<topic>_assumptions.md` to `wip/<workflow>_<topic>_decisions.md`
- Component 5 (lightweight framework): change `wip/<workflow>_<topic>_decision-manifest.md` to a section within the decisions file
- The three review surfaces (terminal summary, decisions file, PR body) remain unchanged in concept; only the file path changes
- Resume detection: check for `wip/<workflow>_<topic>_decisions.md` instead of the assumptions file
- Assumption invalidation (`--correct A2=...`): unchanged -- IDs are stable within the consolidated file
