# Phase 2 Research: Architecture Perspective

## Lead 2: Crystallize Framework Integration

### Findings

#### Current Framework Structure

The crystallize framework (`crystallize-framework.md`) scores five supported types (PRD, Design Doc, Plan, No Artifact, Rejection Record) using signal/anti-signal tables. The evaluation procedure: count signals minus anti-signals per type, demote any type with anti-signals below all types without, apply tiebreakers within 1 point, fall back if nothing scores above 0. Five deferred types exist (Spike Report, Decision Record, Competitive Analysis, Prototype, Roadmap) with workaround guidance.

VISION would become the sixth supported type. The framework is type-agnostic in structure -- no changes needed to the evaluation procedure itself.

#### Existing Type Signal Structure for Comparison

Each supported type has a "core question" that anchors its signals:

| Type | Core Question | Signal Count | Anti-Signal Count |
|------|---------------|-------------|-------------------|
| PRD | What should we build and why? | 5 | 3 |
| Design Doc | How should we build this? | 6 | 3 |
| Plan | What order do we build in? | 4 | 3 |
| No Artifact | (direct action) | 5 | 4 |
| Rejection Record | Should we NOT do this? | 5 | 3 |

The exploration's draft signal table proposed 8 signals and 6 anti-signals for VISION. That's more anti-signals than any existing type, which is appropriate given the emphasis on preventing false positives.

#### Refined Signal/Anti-Signal Table

After comparing the draft against existing types, three adjustments are needed to prevent overlap and strengthen discrimination:

**Overlap identified: PRD signal "The core question is 'what should we build and why?'" partially overlaps with VISION signal "Exploration centered on 'should we build this?'"** The distinction is subtle but real: PRD assumes a project and asks about its features; VISION questions the project itself. The signal text needs to make this gap explicit.

**Overlap identified: Rejection Record and VISION both deal with "should this exist?"** The draft handles this via an implied positive/negative split, but VISION needs an explicit anti-signal for negative conclusions.

**Missing anti-signal: scope gating.** The exploration decided tactical scope is a hard anti-signal. The draft table doesn't include this.

Proposed final signal/anti-signal table:

| Signals | Anti-Signals |
|---------|-------------|
| Project doesn't exist yet (no repo, no codebase, no prior art in the org) | Project already exists and the question is about its next feature or iteration |
| Exploration centered on "should we build this?" not "what should it do?" | Requirements or user stories emerged during exploration (route to PRD) |
| Org fit, strategic alignment, or ecosystem positioning was the core question | A PRD, design doc, or roadmap already covers this project |
| Thesis validation or falsification was the exploration's primary output | Single coherent feature emerged from exploration (route to PRD) |
| Multiple fundamentally different project directions are still viable | Specific users and their needs are already identified (project is past VISION stage) |
| Target audience or user base is not yet well-defined | Exploration reached a negative conclusion -- the project should NOT exist (route to Rejection Record) |
| The core question is "should this project exist and what would it offer?" | Scope is tactical (override or repo default) |
| Exploration produced strategic justification or positioning arguments | |

8 signals, 7 anti-signals. The seventh anti-signal (tactical scope) is the hard gate from the exploration decisions. It functions differently from other anti-signals: it's a precondition check, not an evidence-based signal. The framework's demotion rule means one anti-signal knocks VISION below all clean-scoring types, so the tactical gate is sufficient -- it doesn't need special handling beyond being listed.

#### Tiebreaker Rules

Four tiebreaker rules needed, one for each neighboring type:

**VISION vs PRD (the primary boundary):**
If the project doesn't exist yet (no repo, no codebase, no prior implementation in the org), favor VISION -- requirements are premature when the project's existence is unjustified. If the project exists and exploration surfaced what it should do next, favor PRD -- the strategic question is settled. The distinguishing question: does the project exist yet? No -> VISION. Yes -> PRD.

**VISION vs Roadmap:**
If the exploration produced a sequenced set of features for a project that already exists, that's a Roadmap. If it produced a strategic case for why a new project should be created, that's a VISION. The distinguishing question: is this "what should we do in sequence?" or "should we do this at all?" Sequence -> Roadmap. Existence -> VISION.

**VISION vs Rejection Record:**
If the exploration actively concluded the project should NOT exist (with cited evidence of absent demand or failure modes), that's a Rejection Record. If the conclusion is affirmative (proceed with caveats), that's a VISION. The distinguishing question: is the overall conclusion "proceed" or "don't proceed"? Proceed -> VISION. Don't proceed -> Rejection Record.

**VISION vs No Artifact:**
If the exploration was short (1 round), validated a thesis quickly, and one person can act without coordination, No Artifact may suffice. If the strategic case needs to be documented for others to evaluate (multiple stakeholders, budget, org-level decision), favor VISION. The distinguishing question: does anyone else need to see the strategic argument? Yes -> VISION. No -> No Artifact.

#### Disambiguation Rules

One new disambiguation rule for the framework:

**Exploration surfaced both strategic justification AND feature requirements.** If the exploration produced both "why this project should exist" AND "what it should do," VISION comes first. Strategic justification must be accepted before requirements are worth writing. Recommend VISION with a note that a PRD should follow once the VISION is accepted. The VISION's downstream artifacts section would reference the eventual PRD.

#### Verification: Hypothetical Scoring

**Scenario A: "Should we build a CLI linter for tsuku recipes?"**
- Project: doesn't exist, no repo, no prior art -> VISION signals: project doesn't exist (+1), core question is should-this-exist (+1), thesis validation (+1), strategic justification (+1). Score: +4.
- PRD signals: none match (no feature emerged, requirements unclear, no stakeholder alignment need). Anti-signals: requirements not provided as input, so no anti-signal. Score: 0.
- Result: VISION wins clearly. Correct.

**Scenario B: "What feature should tsuku add for Windows support?"**
- Project: exists (tsuku has a repo, codebase, users) -> VISION anti-signal: project already exists (-1). VISION signals: target audience not defined (+1), org fit question (+1). Score: +1 with 1 anti-signal, demoted.
- PRD signals: single coherent feature (+1), requirements unclear (+1), core question is what-to-build (+1). Score: +3, no anti-signals.
- Result: PRD wins via demotion rule. Correct.

**Scenario C: "Should we build a package manager? No -- the market is saturated."**
- VISION signals: project doesn't exist (+1), core question is should-this-exist (+1), thesis validation (+1). Anti-signal: negative conclusion (-1). Score: +2, demoted.
- Rejection Record signals: active rejection conclusion (+1), cited blockers (+1), re-proposal risk (+1). Score: +3, no anti-signals.
- Result: Rejection Record wins. Correct.

**Scenario D: "Should we build X?" in a tactical-scope repo.**
- VISION anti-signal: tactical scope (-1). Regardless of other signals, VISION is demoted.
- PRD or No Artifact would win in the supported types. Correct -- VISION shouldn't appear in tactical contexts.

**Scenario E (edge case): "Should we build X?" -- 1 round, user seems confident, no stakeholders.**
- VISION signals: project doesn't exist (+1), core question (+1). Score: +2.
- No Artifact signals: simple enough to act on (+1), one person (+1), short exploration (+1). Score: +3.
- Tiebreaker not needed; No Artifact wins outright. But what if user's confidence is lower? If score tie, tiebreaker asks "does anyone else need to see the strategic argument?" If no, No Artifact. This seems right -- not every new-project idea needs a VISION doc.

**Scenario F (edge case): Exploration produced a thesis AND requirements.**
- VISION signals: project doesn't exist (+1), thesis validation (+1), strategic justification (+1). Score: +3.
- PRD signals: single feature (+1), requirements unclear -> emerged (+1), user stories missing (+1). Score: +3.
- Tie. Disambiguation rule applies: VISION first, PRD follows. Correct.

#### Potential Discrimination Failures

1. **Gray zone: project "sort of" exists.** An abandoned prototype, or an informal effort with a few scripts but no official repo. The "project doesn't exist" signal is binary but reality is a spectrum. The tiebreaker rule says "no repo, no codebase, no prior implementation" which covers prototypes-with-repos, but doesn't cleanly handle "we talked about it and wrote some notes" without a repo.

2. **Scope gating leaks through override.** A user in a strategic repo could run `--tactical` to override scope, which would suppress VISION via the anti-signal. But a user in a tactical repo running `--strategic` would enable VISION. This is the intended behavior per the scope document, but worth noting: the tactical anti-signal only applies to effective scope (after override), not repo default.

3. **Public repos with strategic override.** A public tactical repo where someone runs `--strategic` could produce a VISION. The VISION would be content-constrained (no competitive positioning, no internal resource analysis) but structurally valid. Is this actually useful? The scope document says yes -- Strategic+Public produces a "public manifesto."

### Implications for Requirements

1. The signal/anti-signal table needs exactly 8 signals and 7 anti-signals. The seventh anti-signal (tactical scope) is structurally different from the others -- it's a precondition, not an evidence evaluation. The PRD should specify whether the scoring procedure treats it identically (just another anti-signal in the demotion rule) or as a pre-filter that removes VISION from the candidate list before scoring. Both achieve the same result, but a pre-filter is cleaner and matches the exploration's language of "hard anti-signal."

2. Four tiebreaker rules need explicit text in the crystallize framework: VISION vs PRD, VISION vs Roadmap, VISION vs Rejection Record, VISION vs No Artifact. Each uses a single distinguishing question.

3. One new disambiguation rule: "strategic justification AND feature requirements" -> VISION first, PRD follows.

4. The framework's Step 1 expands from five to six supported types. No structural changes to Steps 2-4.

### Open Questions

1. **Pre-filter vs anti-signal for tactical scope gating.** Should tactical scope be a regular anti-signal that participates in demotion scoring, or a pre-filter that removes VISION from the candidate list before scoring begins? The demotion rule makes both functionally equivalent, but the pre-filter is conceptually cleaner. The PRD should specify one.

2. **"Project doesn't exist" threshold.** How much prior art counts as "existing"? A conversation? A spike report? An abandoned prototype with a repo? The signal text says "no repo, no codebase, no prior art" but a spike report about the project's feasibility is "prior art" that doesn't mean the project "exists." The PRD may need to define what constitutes project existence.

3. **Design Doc vs VISION tiebreaker.** The draft doesn't include a VISION vs Design Doc tiebreaker. These types rarely compete (Design Doc assumes the project exists and asks "how"; VISION asks "should it exist"). But if an exploration of a potential project dove deep into technical feasibility, both could score. Is a tiebreaker needed or does the demotion rule handle it? The "project already exists" anti-signal on VISION and "what to build is still unclear" anti-signal on Design Doc seem sufficient.


## Lead 4: VISION Lifecycle

### Findings

#### Lifecycle Comparison Across All Artifact Types

| Type | States | Terminal State | Can Be Superseded? | Movement Pattern |
|------|--------|----------------|-------------------|-----------------|
| PRD | Draft -> Accepted -> In Progress -> Done | Done | No (create new PRD, mark old as Done) | Stays in place |
| Design Doc | Proposed -> Accepted -> Planned -> Current -> Superseded | Current or Superseded | Yes (explicit Superseded state with link) | Moves directories by status |
| Decision Record | Proposed -> Accepted -> Deprecated / Superseded | Accepted (or Deprecated/Superseded) | Yes (Superseded links to replacement) | Stays in place |
| Spike Report | Draft -> Complete | Complete | No (create new spike) | Stays in place |
| Roadmap | Draft -> Active -> Done | Done | No (create new roadmap) | Stays in place |
| **VISION** | **Draft -> Accepted -> Active -> Sunset** | **Active (long-lived) or Sunset** | **TBD** | **TBD** |

#### What Makes VISION's Lifecycle Distinct

Every other artifact type has a clear completion state:

- PRD: "Done" means all acceptance criteria met, feature shipped.
- Design Doc: "Current" means all implementation issues closed.
- Roadmap: "Done" means all features delivered or explicitly dropped.
- Spike Report: "Complete" means investigation finished, recommendation made.
- Decision Record: "Accepted" is the stable state (Deprecated/Superseded are terminal variants).

VISION breaks this pattern. A VISION doc captures why a project exists and what it offers. That thesis stays relevant as long as the project is alive. "Active" is the steady state, not a waypoint toward "Done." This is similar to Decision Record's "Accepted" being stable -- but Decision Records can be Deprecated or Superseded. VISION needs its own termination mechanics.

#### VISION State Definitions

**Draft**: VISION created by /explore Phase 5. Thesis, audience, value proposition, org fit, and success criteria are written but may have open questions. The document is a proposal, not yet endorsed.

- Entry: Created by /explore's Phase 5 produce handler.
- Exit conditions: Open Questions section empty or removed. Human explicitly approves.
- Forbidden transitions from Draft: Active (must be Accepted first), Sunset (must be Accepted first).

**Accepted**: Thesis endorsed. The project has organizational buy-in to proceed. Downstream work (PRDs, design docs) can reference this VISION as their strategic justification.

- Entry: Human approval. Open Questions resolved.
- Exit conditions: Downstream work begins (transition to Active), OR the VISION is sunset before any work starts.
- Transition trigger to Active: First downstream artifact (PRD, design doc, or repo creation) references this VISION.

**Active**: The project exists and this VISION is its strategic anchor. Downstream artifacts (PRDs, design docs, plans) reference it. The VISION itself doesn't change frequently -- it's a stable reference point.

- Entry: Downstream work has started.
- No automatic exit. A VISION stays Active as long as the project is alive.
- The VISION can be updated while Active (thesis refinement, success criteria adjustment), but structural changes (fundamentally different thesis) should produce a new VISION and Sunset the old one.

**Sunset**: The VISION is no longer the active strategic anchor. Either the project was abandoned, the thesis was invalidated by experience, or a new VISION replaced it.

- Entry: Explicit human decision. Three triggers:
  1. Project abandoned (no longer pursuing this).
  2. Thesis invalidated (project exists but thesis was wrong -- e.g., the audience turned out to be different than expected).
  3. Superseded by a new VISION (project pivoted fundamentally).
- Terminal state. No transitions out of Sunset.

#### State Transition Diagram

```
Draft --> Accepted --> Active --> Sunset
                  \-> Sunset (accepted but never started)
```

#### Forbidden Transitions

- **Draft -> Active**: A VISION must be explicitly endorsed before it becomes the project's strategic anchor. Skipping Accepted means no one reviewed the thesis.
- **Draft -> Sunset**: If a Draft VISION is abandoned, delete it -- there's no value in preserving an unendorsed thesis as a historical record. (This differs from Decision Records, where even Proposed records aren't deleted but instead "just delete it" is the guidance.)
- **Active -> Accepted**: Regression. Once downstream work exists, you can't un-Active a VISION.
- **Active -> Draft**: Regression. A published strategic anchor can't become a draft again.
- **Sunset -> any**: Terminal.

#### Comparison with Decision Record's Deprecated/Superseded

Decision Records have two terminal states: Deprecated ("still valid but discouraged") and Superseded ("explicitly replaced by ADR-X"). VISION collapses these into one terminal state: Sunset. The rationale:

- A VISION's thesis is either the active strategic anchor or it's not. There's no meaningful "still valid but discouraged" state for a project's reason-to-exist. If the thesis is wrong, the project either pivots (new VISION supersedes) or winds down (Sunset without replacement).
- The Sunset state can carry a note explaining why: "superseded by VISION-X," "project abandoned," or "thesis invalidated." This information goes in the Status section, not a separate state.

This is a deliberate simplification. Two terminal states add complexity without corresponding value for a document type that captures project identity rather than a single technical choice.

#### What "Sunset" Means in Practice

Sunset means the VISION no longer guides the project's direction. Three concrete scenarios:

1. **Project abandoned.** The org decided not to pursue this project. The VISION becomes a historical record of why the project was considered and what changed. Useful for preventing re-proposals.

2. **Project pivoted.** The project still exists but its thesis changed fundamentally. A new VISION captures the updated thesis. The old VISION's Status section notes "Sunset: superseded by VISION-<new-name>.md" with a link to the replacement. Both VISIONs stay in docs/visions/ -- the Sunset one provides historical context.

3. **Thesis invalidated.** The project launched but the original value proposition turned out to be wrong (different audience, different value, different positioning). The VISION is Sunset with a note explaining what was learned. A new VISION may or may not follow -- sometimes the project continues without a formal thesis document because it has found its identity through usage rather than planning.

#### Can a VISION Be Superseded by Another VISION?

Yes. This is scenario 2 above. The mechanism: create a new VISION doc, transition the old one to Sunset with a "superseded by" note in its Status section. No formal `superseded_by` frontmatter field is needed (unlike Decision Records) because VISION docs are few per project -- the link in the Status section is sufficient.

However, the `upstream` frontmatter field (from the scope document) could serve double duty: a project-level VISION's `upstream` points to its org-level VISION, and a superseding VISION could reference the one it replaces. This would need a different field name to avoid confusion. Recommendation: keep supersession as prose in the Status section, not a frontmatter field. Keep `upstream` for the org/project hierarchy only.

#### Lifecycle of "Active" Compared to Other Types' In-Progress States

| Type | In-Progress Equivalent | What's Happening | Exit Condition |
|------|----------------------|------------------|----------------|
| PRD | In Progress | Being implemented via downstream workflows | All acceptance criteria met |
| Design Doc | Planned | Issues created, implementation underway | All issues closed |
| Roadmap | Active | Features being delivered in sequence | All features complete or dropped |
| **VISION** | **Active** | **Project exists and operates under this thesis** | **None (stays until Sunset)** |

VISION's "Active" is fundamentally different: it has no automatic exit condition. PRD's "In Progress" ends when criteria are met. Design Doc's "Planned" ends when issues close. Roadmap's "Active" ends when features ship. VISION's "Active" ends only when a human decides the thesis is no longer valid. This is the key lifecycle innovation.

#### File Location and Movement

Following existing patterns:

- Design Docs move between directories based on status (docs/designs/ -> docs/designs/current/ -> docs/designs/archive/).
- PRDs, Decision Records, Spike Reports, and Roadmaps stay in their directory regardless of status.

VISION should follow the simpler pattern: all VISIONs stay in `docs/visions/` regardless of status. Movement isn't needed because there's no "current vs archive" distinction that aids navigation -- a project typically has one Active VISION at a time, and the frontmatter status field is sufficient for filtering.

### Implications for Requirements

1. The lifecycle is exactly 4 states: Draft -> Accepted -> Active -> Sunset. No "Done" or "Complete" state -- Active is indefinite.

2. Three transition triggers need specification: Draft->Accepted (human approval, open questions resolved), Accepted->Active (first downstream artifact references this VISION), Active->Sunset (human decision: abandoned, pivoted, or invalidated).

3. Sunset is the only terminal state. It covers three scenarios (abandoned, pivoted/superseded, invalidated) via prose in the Status section rather than separate states.

4. Draft VISIONs that are abandoned should be deleted, not Sunset. Only Accepted or Active VISIONs get Sunset.

5. Supersession by another VISION is documented as prose in the Status section ("Sunset: superseded by VISION-X"), not via a frontmatter field. The `upstream` field is reserved for org/project hierarchy.

6. VISIONs stay in `docs/visions/` regardless of status -- no directory movement.

### Open Questions

1. **Accepted->Active trigger precision.** "First downstream artifact references this VISION" is conceptually clean but hard to detect automatically. Should the transition be manual (human marks it Active) or should the /prd skill auto-detect an `upstream` field pointing to an Accepted VISION and trigger the transition? If automated, what happens if someone writes a PRD referencing a Draft VISION?

2. **Update-while-Active rules.** The findings say "thesis refinement" is allowed during Active, but "structural changes" should produce a new VISION. Where's the line? If success criteria change, is that refinement or structural? The PRD should define what kinds of changes are permitted during Active vs. what forces a new VISION.

3. **Deletion of abandoned Drafts.** The recommendation is "delete abandoned Draft VISIONs." But /explore produces them via Phase 5 commit. If the VISION was committed to a feature branch that never merged, it's already cleaned up. If it merged as Draft and is then abandoned, deletion means lost git history context. Should abandoned Draft VISIONs be deleted or moved to a "rejected" convention (like placing them in docs/visions/rejected/)?


## Summary

VISION integrates into the crystallize framework as the sixth supported type with 8 signals, 7 anti-signals (including tactical scope as a hard gate), and 4 tiebreaker rules against neighboring types (PRD, Roadmap, Rejection Record, No Artifact). The sharpest discriminator remains project existence, and hypothetical scoring across 6 scenarios confirmed the signals discriminate correctly with one gray area around what "project exists" means for informal or abandoned efforts. The lifecycle (Draft -> Accepted -> Active -> Sunset) is unique among all artifact types in having no automatic completion state -- Active is indefinite until a human Sunsets it -- and Sunset consolidates three termination scenarios (abandoned, pivoted, invalidated) into a single terminal state with prose-level differentiation, a deliberate simplification over Decision Record's two-terminal-state pattern.
