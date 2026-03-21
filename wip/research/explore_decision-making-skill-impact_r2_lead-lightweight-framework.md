# Research: Lightweight Decision Framework

**Lead:** lightweight-framework
**Round:** 2
**Date:** 2026-03-21
**Scope:** Design a lightweight decision protocol for inline skill decisions that shares principles with the heavyweight 7-phase framework but is appropriate for smaller choices made during workflow execution.

---

## 1. Current Landscape: Where Lightweight Decisions Happen

### Inventory of inline decision points across skills

**Design skill:**
- Phase 4.4 implicit decision review: discovers decisions baked into architecture prose (polling vs webhooks, strict vs permissive validation). Uses AskUserQuestion for each, appends to Considered Options.
- Phase 2 approach selection: user picks from advocate presentations. This is a heavyweight decision (full Phase 1-2 cycle), not lightweight.

**Plan skill:**
- Decomposition strategy: walking skeleton vs horizontal. Evaluated by assessing component coupling, defaulting based on flags or heuristic analysis. Currently embedded in Phase 3 prose with no structured record.
- Execution mode: single-pr vs multi-pr. Heuristic signals (issue count, complexity depth) drive a recommendation presented via AskUserQuestion.

**Explore skill:**
- Loop decision: "explore further" vs "crystallize." Based on gap analysis from convergence output. Presented via AskUserQuestion with recommendation heuristic.
- Scope narrowing during convergence rounds: areas eliminated, options ruled out. Recorded in `wip/explore_<topic>_decisions.md` with one-line rationale per decision.

**Work-on skill:**
- Branch strategy, implementation approach within a single issue. Currently undocumented -- the agent just does it.

### What these share

Every lightweight decision follows the same cognitive pattern:
1. The agent encounters a fork
2. Available information suggests one path over another
3. The agent either asks the user or just picks
4. The rationale is either lost (work-on), embedded in prose (plan), or minimally recorded (explore decisions file)

The problem: rationale capture is inconsistent, assumptions are implicit, and there's no way to review these decisions alongside heavyweight ones.

---

## 2. The Lightweight Decision Protocol

### Design principles

Borrowed from the heavyweight framework but scaled down:
- **Research first**: exhaust available information before deciding (don't guess when you can check)
- **Document the choice**: every non-trivial decision gets a structured record
- **Track assumptions**: state what you're betting on so invalidation is detectable
- **Support review**: records are extractable for end-of-workflow audit
- **Enable re-execution**: if an assumption breaks, the record tells you what to revisit

### The three-step micro-protocol

**Step 1: Frame.** State the question in one sentence. Identify what's at stake (reversibility, blast radius, downstream dependencies).

**Step 2: Gather.** Check available evidence before deciding. This is NOT research-agent-level investigation -- it's what the agent can determine from context already loaded: codebase patterns, prior decisions in the same workflow, constraint files, existing artifacts. The key discipline is "look before you leap" -- don't default to asking the user when the answer is in the codebase.

**Step 3: Decide and record.** Pick the best option. Write a structured decision block (format below). In interactive mode, present to the user for confirmation. In non-interactive mode, document and continue.

### When to invoke the micro-protocol

Not every fork needs documentation. The protocol triggers when any of these hold:
- The decision affects artifacts other agents will consume (downstream dependency)
- A reasonable person could have chosen differently (genuine alternative exists)
- The decision rests on an assumption that could be wrong (falsifiable bet)
- Reversing the decision later would require rework (not trivially undoable)

Trivial decisions (variable naming, formatting, which file to read first) skip the protocol entirely. The agent uses judgment -- the same judgment it uses to decide whether a code comment is necessary.

---

## 3. Output Format: The Decision Block

A structured block that can appear inline in any wip/ artifact. Compact enough that 3-5 per artifact don't bloat it. Structured enough to be extracted by pattern matching.

```markdown
<!-- decision:start id="decomp-strategy" -->
### Decision: Decomposition strategy

**Question:** Walking skeleton or horizontal decomposition for this design?

**Evidence:** The design spans 3 components with well-defined interfaces (parser, validator, emitter). No runtime interaction between parser and emitter -- validator mediates. Component boundaries are stable (defined in the design doc's Key Interfaces section).

**Choice:** Horizontal decomposition

**Alternatives considered:**
- Walking skeleton: would force premature integration when interfaces are already clear. Adds a thin-slice issue that provides limited early feedback since components don't interact at runtime.

**Assumptions:**
- Interface definitions in the design doc are stable and won't change during implementation
- Components can be tested independently with mocked interfaces

**Reversibility:** Medium. Switching to walking skeleton after 2 horizontal issues are complete would require restructuring the dependency graph but not rewriting code.
<!-- decision:end -->
```

### Format rules

1. **HTML comment delimiters** (`<!-- decision:start -->` / `<!-- decision:end -->`): machine-extractable, invisible in rendered markdown, won't collide with document structure.
2. **`id` attribute**: kebab-case, unique within the artifact. Used for cross-referencing ("invalidated by decision `cache-strategy`").
3. **Required fields**: Question, Choice, Assumptions. Evidence, Alternatives, and Reversibility are included when non-trivial.
4. **Compact variant** for very simple decisions (one alternative, obvious evidence):

```markdown
<!-- decision:start id="branch-name" -->
**Decision:** Branch name `feat/parser-component` -- follows existing `feat/<component>` convention in the repo. Assumes no parallel work on the parser.
<!-- decision:end -->
```

The compact variant collapses all fields into 1-2 sentences. It's for decisions that clear the "document this" bar but barely. The full format is for decisions where someone might later ask "why did you do it that way?"

### Why not YAML or JSON blocks?

Markdown is what agents write naturally. Forcing structured data formats adds friction that reduces adoption. The HTML comment delimiters give machine extractability without requiring the content to be parseable as data. A script can extract all decision blocks from an artifact by matching the delimiters; the content inside is human-readable markdown.

---

## 4. Decision Registry: Where Decisions Accumulate

### Option A: Centralized decisions file per workflow

A single `wip/<workflow>_<topic>_decisions.md` that all decisions flow into. Already exists for explore (`wip/explore_<topic>_decisions.md`).

**Problem:** Requires dual-write (decision recorded in the artifact where it was made AND copied to the central file). Dual-write means drift risk. Also, central files lose the context surrounding the decision -- you see the choice but not the phase it happened in.

### Option B: Inline in each artifact, extracted for review

Decision blocks live in the artifact where they were made. A review step at the end of the workflow extracts all blocks across all artifacts into a consolidated view.

**Advantage:** No dual-write. Decision stays co-located with the context that produced it. The extraction is a read-only operation that can't create inconsistency.

**Disadvantage:** Requires a script or manual scan to find all decisions. Harder to get a quick overview mid-workflow.

### Option C: Hybrid -- inline as source of truth, manifest as derived index

Decision blocks are written inline (Option B). A lightweight manifest tracks their locations:

```markdown
# Decision Manifest: <topic>

| ID | Artifact | Phase | Question (abbreviated) |
|----|----------|-------|----------------------|
| decomp-strategy | wip/plan_foo_decomposition.md | Plan Phase 3 | Walking skeleton vs horizontal |
| exec-mode | wip/plan_foo_decomposition.md | Plan Phase 3.5 | Single-pr vs multi-pr |
| cache-approach | wip/design_foo_decision_2_report.md | Design Decision 2 | Cache invalidation strategy |
```

The manifest is rebuilt whenever a new decision block is written (append-only). It's the index, not the source of truth. If it gets lost, all decisions are still in their artifacts.

### Recommendation: Option C (hybrid)

The manifest lives at `wip/<workflow>_<topic>_decision-manifest.md`. Appended to after each decision block is written. The end-of-workflow review reads the manifest to locate all decisions, then reads each artifact for the full block. Heavyweight decisions (from the decision skill) also get entries in the same manifest, creating a unified view.

### Unified view across heavyweight and lightweight

The manifest doesn't distinguish between decision types. A design workflow's manifest might look like:

| ID | Artifact | Type | Question |
|----|----------|------|----------|
| approach | wip/design_foo_decision_1_report.md | heavyweight | Which architecture approach? |
| data-model | wip/design_foo_decision_2_report.md | heavyweight | Which data model? |
| decomp-strategy | wip/plan_foo_decomposition.md | lightweight | Walking skeleton vs horizontal? |
| error-format | docs/designs/DESIGN-foo.md | lightweight | Error response format |

"Type" is informational. The review process treats them identically -- read the block, check assumptions, verify rationale.

---

## 5. The Decision Complexity Spectrum

Four tiers from "just do it" to "full bakeoff." The boundaries are defined by signals, not rigid rules -- agents assess which tier fits using the criteria below.

### Tier 1: Trivial (no documentation)

**What it looks like:** The "decision" has only one reasonable option, or the choice is immediately reversible with no downstream impact.

**Signals:**
- No genuine alternative exists (there's only one way to do it)
- Reversing takes seconds (rename a variable, change a flag)
- No one downstream consumes the output of this choice
- The codebase convention dictates the answer

**Examples:** Branch naming convention, import order, which test file to put a test in, indentation style.

**Action:** Just do it. No record.

### Tier 2: Lightweight (micro-protocol)

**What it looks like:** A genuine fork with 2-3 options where evidence from available context points to a clear winner. Reversible with moderate effort.

**Signals:**
- 2-3 viable alternatives exist
- Available context (codebase, prior decisions, constraints) strongly favors one
- Reversing requires rework in 1-3 files but no architectural change
- One or more downstream artifacts depend on this choice
- An assumption underlies the choice that could be wrong

**Examples:** Decomposition strategy (plan), execution mode (plan), loop exit decision (explore), implicit architecture choices (design Phase 4.4), error handling strategy within a component, file organization within a feature.

**Action:** Three-step micro-protocol. Decision block in the current artifact. Entry in the manifest.

### Tier 3: Standard (decision skill, fast path)

**What it looks like:** A decision with 3+ options where trade-offs are genuinely contested. Evidence requires targeted investigation beyond what's already loaded. The choice shapes the architecture or user experience.

**Signals:**
- 3+ viable alternatives, none obviously dominant
- Evidence requires looking beyond the current context (reading external docs, testing assumptions, comparing prior art)
- Reversing requires architectural changes across multiple components
- Multiple stakeholders might reasonably disagree
- The decision is the primary purpose of the current phase (not incidental)

**Examples:** Cache invalidation strategy, API authentication approach, data model selection, component communication pattern. These are the decisions that end up as "Considered Options" in design docs.

**Action:** Decision skill, fast path (Phases 0, 1, 2, 6 -- skip validation bakeoff, peer revision, cross-examination). Produces a structured decision report. ~4 interaction points.

### Tier 4: Critical (decision skill, full 7-phase)

**What it looks like:** High-stakes, hard-to-reverse decisions where getting it wrong has significant consequences. The decision warrants adversarial evaluation.

**Signals:**
- Choice is practically irreversible (database selection, API contract, public interface)
- Consequences compound over time (technical debt if wrong)
- Multiple experts would disagree on the right answer
- The decision has been contentious in past discussions or similar projects
- Security, compliance, or data integrity implications

**Examples:** Primary data store selection, authentication/authorization architecture, public API design, migration strategy for production data.

**Action:** Decision skill, full 7-phase workflow. Research, alternatives, validation bakeoff, peer revision, cross-examination, synthesis, report. ~7-10 interaction points.

### Classification heuristic

When an agent hits a decision point, it evaluates these signals in order:

1. **Is there only one reasonable option?** -> Tier 1 (trivial)
2. **Does available context clearly favor one option?** -> Tier 2 (lightweight)
3. **Is this the primary decision the current phase exists to make?** -> Tier 3 or 4
4. **Is the decision practically irreversible?** -> Tier 4 (critical)
5. **Default:** Tier 2 (lightweight) -- when in doubt, document the choice with the micro-protocol rather than escalating to the decision skill

The default to Tier 2 is intentional. Most decisions during workflow execution are lightweight. The micro-protocol is cheap enough that over-documenting is better than under-documenting. Escalating to Tier 3+ should feel like a deliberate shift, not the default.

---

## 6. Replacing AskUserQuestion

### Current pattern

AskUserQuestion is the universal mechanism for agent-to-user decision points. It presents options with a recommendation (per `decision-presentation.md`). The agent blocks until the user responds.

### Problems with the current pattern

1. **No evidence gathering before asking.** Agents often ask before checking. "Should I use walking skeleton or horizontal?" when the codebase's component coupling would answer the question.

2. **No record of rationale.** AskUserQuestion captures what was chosen but not why. The conversation log has the context, but it's not structured or extractable.

3. **Blocks in non-interactive mode.** If no human is watching, the workflow stops. There's no fallback to "make the best call and document it."

4. **Same mechanism for all decision weights.** A trivial formatting question uses the same pattern as an architecture selection. Users get decision fatigue.

### New pattern: Research-first, mode-aware decisions

Replace the "ask first" pattern with "gather first, then decide based on mode."

**Interactive mode (human present):**

```
1. Frame the question
2. Gather available evidence
3. Form a recommendation with rationale
4. Present via AskUserQuestion with:
   - Recommended option marked "(Recommended)"
   - Evidence summary in the description field
   - Alternatives with brief rejection rationale
5. Record the decision (user's choice, not just the agent's recommendation)
   using the decision block format
```

This is the current AskUserQuestion pattern PLUS steps 1-2 (gather before asking) and step 5 (record after deciding). The user still has full control. The difference is the agent arrives with evidence, not just a question.

**Non-interactive mode (autonomous execution):**

```
1. Frame the question
2. Gather available evidence
3. Form a recommendation with rationale
4. If evidence strongly favors one option (Tier 2):
   - Choose it
   - Write a decision block with full rationale
   - Continue execution
5. If evidence is ambiguous (Tier 3+):
   - Choose the conservative/reversible option
   - Write a decision block marking it as "assumed, pending review"
   - Flag for end-of-workflow review
   - Continue execution
```

The key insight: non-interactive mode doesn't mean "guess and hope." It means "make the best call you can, document your reasoning, mark assumptions, and let a human review the batch at the end." The decision block's Assumptions field is what makes this safe -- reviewers can check each assumption and override if needed.

### Mapping specific AskUserQuestion sites

**Design Phase 4.4 (implicit decisions):**
- Current: AskUserQuestion per implicit decision found
- New (interactive): Same, but with evidence from the codebase gathered first. The agent checks if the implicit choice matches existing patterns before asking.
- New (non-interactive): Agent documents each implicit decision as a decision block, marks as "assumed, pending review," continues to Phase 4.5.

**Plan Phase 3 (decomposition strategy):**
- Current: Heuristic evaluation, AskUserQuestion with recommendation
- New (interactive): Same behavior. The heuristic IS the evidence gathering.
- New (non-interactive): Agent applies heuristic, picks the winner, writes a decision block. If heuristic is close (e.g., 60/40), marks as "assumed, pending review."

**Explore Phase 3 (loop decision):**
- Current: Gap analysis, AskUserQuestion with "explore further" or "ready to decide"
- New (interactive): Same behavior. Gap analysis IS the evidence gathering.
- New (non-interactive): Agent evaluates gaps. If significant gaps remain, continues exploring (up to a round limit). If coverage is sufficient, crystallizes. Writes a decision block either way.

**Plan Phase 3.5 (execution mode):**
- Current: Signal analysis, AskUserQuestion with recommendation
- New: Same as decomposition strategy -- heuristic is the evidence, record the choice.

### The "assumed, pending review" marker

For non-interactive decisions where evidence isn't definitive:

```markdown
<!-- decision:start id="decomp-strategy" status="assumed" -->
### Decision: Decomposition strategy

**Question:** Walking skeleton or horizontal decomposition?

**Evidence:** Component coupling is moderate -- 2 of 3 components share a data structure but have independent codepaths. Neither strategy is clearly dominant.

**Choice:** Horizontal decomposition (assumed, pending review)

**Assumptions:**
- Shared data structure interface is stable (if it changes, walking skeleton would have caught integration issues earlier)

**Review note:** Evidence was 60/40 in favor of horizontal. If the shared data structure is less stable than it appears, consider switching to walking skeleton before Phase 2 issues are started.
<!-- decision:end -->
```

The `status="assumed"` attribute in the delimiter lets extraction scripts flag these for priority review. The "Review note" field gives the reviewer enough context to override quickly.

---

## 7. Integration with the Decision Skill

### How lightweight and heavyweight decisions relate

The lightweight micro-protocol and the heavyweight decision skill share a common core:

| Concern | Lightweight | Heavyweight |
|---------|------------|-------------|
| Frame the question | Step 1 (1 sentence) | Phase 0 (full context extraction) |
| Gather evidence | Step 2 (check loaded context) | Phases 1-5 (research agents, bakeoff, cross-examination) |
| Decide and record | Step 3 (decision block) | Phase 6 (structured report) |
| Track assumptions | Assumptions field in block | Assumptions in report + cross-validation |
| Review | End-of-workflow manifest scan | Cross-examination phase + post-workflow |

The lightweight protocol is the heavyweight framework with the middle compressed. Same structure, less depth. This means:

1. A lightweight decision can be **escalated** to heavyweight mid-stream. If Step 2 reveals that evidence is contested and the decision warrants deeper investigation, the agent invokes the decision skill instead of completing Step 3.

2. A heavyweight decision report **contains** a decision block. The report's frontmatter IS the expanded version of the block's fields. No format translation needed for the manifest -- both types get entries.

3. **Assumption invalidation** works identically. Whether a lightweight or heavyweight decision assumed X, if X proves false, the decision manifest points to the record, the record states the assumption, and the agent can re-evaluate.

### Escalation from lightweight to heavyweight

During Step 2 of the micro-protocol, if the agent determines the decision is Tier 3+:

1. Write a partial decision block with just the Question and Evidence gathered so far
2. Mark it `status="escalated"`
3. Invoke the decision skill (inline or via agent, depending on context)
4. The decision skill reads the partial block as input context (saves re-framing)
5. The decision skill's report replaces the partial block in the manifest

This prevents the worst case: an agent spends 5 minutes on a micro-protocol only to realize the decision needed the full framework. The escalation path is cheap because the framing work isn't lost.

---

## Summary

The lightweight decision framework is a three-step micro-protocol (frame, gather, decide) that produces structured decision blocks embeddable in any wip/ artifact. Blocks use HTML comment delimiters for machine extraction and track assumptions explicitly. A decision manifest indexes all decisions (lightweight and heavyweight) for end-of-workflow review. Four complexity tiers (trivial, lightweight, standard, critical) determine which framework applies, with the lightweight micro-protocol as the default. In interactive mode, the protocol enhances AskUserQuestion with evidence-gathering-first; in non-interactive mode, it replaces AskUserQuestion with assumption-based decisions marked for review. The lightweight format is a compressed version of the heavyweight decision report -- same structure, less depth -- enabling escalation without information loss.
