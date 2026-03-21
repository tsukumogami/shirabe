# Decision Cluster A: Format, Review Surface, and Escalation

**Date:** 2026-03-21
**Context:** Three coupled architectural decisions for the shirabe decision framework.
**Mode:** Non-interactive (research-first, best-call-with-evidence, document assumptions)

---

## Background

The decision framework introduces structured decision records across all shirabe
workflow skills. Three foundational choices need to be made together because they
interact: the block format determines what can be extracted, the review surface
determines where extracted content appears, and the escalation model determines
how lightweight blocks transform into heavyweight ones.

Research inputs:
- `explore_decision-making-skill-impact_r2_lead-lightweight-framework.md` (block format, manifest, tiers)
- `explore_decision-making-skill-impact_r2_lead-non-interactive.md` (assumption lifecycle, review surface)
- `explore_decision-making-skill-impact_r1_lead-output-format.md` (canonical report structure)

---

## Decision 1: Decision Block Format

### The Question

What delimiters and internal structure should decision blocks use?

### Options Evaluated

**(a) HTML comment delimiters with markdown content**

```markdown
<!-- decision:start id="foo" -->
### Decision: Foo
**Question:** ...
**Choice:** ...
**Assumptions:** ...
<!-- decision:end -->
```

Pros:
- Machine-extractable via simple regex on delimiters
- Content between delimiters is standard markdown -- agents produce this naturally
- Invisible in rendered GitHub markdown (both in repo file views and PR diffs)
- Won't collide with document heading structure
- Supports attributes on the delimiter (`id`, `status`) without inventing syntax

Cons:
- **Invisible in rendered markdown is a double-edged sword.** When a reviewer reads
  a design doc on GitHub, decision blocks vanish. The content between the comments
  renders as normal markdown (headings, bold text), but the delimiters themselves
  disappear. This means the block boundaries aren't visible -- a reviewer sees the
  Decision heading and fields but can't tell where one block ends and another begins
  without viewing raw markdown.
- HTML comments are sometimes stripped by markdown processors (GitHub preserves them
  in source but hides them in rendered view, which is the desired behavior here).
- Agents occasionally produce malformed HTML comments (missing closing `-->`) though
  this is rare with modern models.

**(b) YAML blocks (fenced with ```yaml)**

```yaml
```yaml decision
id: foo
question: ...
choice: ...
assumptions:
  - ...
```
```

Pros:
- Strictly parseable
- Familiar to developers

Cons:
- Agents are less fluent writing YAML than markdown -- indentation errors,
  quoting issues with colons in values, multiline strings requiring `|` or `>`
- Content is constrained to YAML-safe strings. Rich descriptions with markdown
  formatting (bold, lists, links) require escaping or multiline blocks.
- YAML blocks render as code blocks on GitHub -- visually prominent but
  not readable as documentation. The content looks like config, not prose.
- No natural way to include a compact variant (the 1-2 sentence version
  the research proposes for trivial-but-documented decisions)

**(c) Structured markdown with heading conventions**

```markdown
#### Decision: Foo {#decision-foo}

**Question:** ...
**Choice:** ...
**Assumptions:** ...

---
```

Pros:
- Fully visible in rendered markdown
- No special delimiters to parse
- Heading anchors provide linkability

Cons:
- Extraction requires heuristic parsing (find headings matching the pattern,
  determine where the block ends). Horizontal rules or next heading?
  Fragile when agents add extra content.
- Heading level conflicts: if the block appears inside a section with `###`
  headings, a `####` Decision heading works. If it appears inside `####`,
  there's no room. The heading level is context-dependent.
- No clean way to attach metadata (`id`, `status`) without non-standard
  syntax like `{#id}` which many markdown renderers ignore.
- No invisible option -- every decision block adds visible structure to the
  document even when the user just wants inline documentation.

### Analysis

The key question is: do we need decision blocks to be visible in rendered markdown?

No. Decision blocks serve two audiences:
1. **The agent** that writes and reads them during workflow execution (needs machine-extractable structure)
2. **The reviewer** who audits decisions at the end (reads them via the manifest, the PR body section, or the terminal summary -- not by scrolling through rendered markdown)

The rendered-invisible property of HTML comments is actually correct for this use case.
The review surface (Decision 2) handles visibility. The blocks themselves are the
storage format, not the presentation format.

**Regarding agent reliability:** Claude models reliably produce HTML comments. The
pattern `<!-- tag -->` is well-represented in training data (Hugo front matter,
Jekyll includes, TODO markers). The decision block format uses HTML comments only
for delimiters, not for content -- the markdown between them is what agents write
naturally.

**Regarding GitHub visibility:** HTML comments are preserved in the raw source
(visible in "Edit" or "Raw" view) and stripped from the rendered view. In PR diffs,
the comments appear in the diff itself (since diffs show source, not rendered
markdown). So reviewers DO see the delimiters in PR reviews. They DON'T see them
when reading the rendered file on the repo page. This is the right split: PR review
is where decision scrutiny happens, and the diff shows everything.

**Regarding extraction:** A regex like `<!-- decision:start.*?-->[\s\S]*?<!-- decision:end -->`
captures complete blocks. The `id` and `status` attributes parse from the opening
delimiter. This is simpler than YAML parsing and more reliable than heading-based
heuristics.

### Interaction with other decisions

The format choice constrains the review surface (Decision 2): if blocks are
invisible in rendered markdown, the review surface MUST provide an alternative
way to see them. This favors a PR body section over "just read the doc."

The format also constrains escalation (Decision 3): the `status` attribute on
the delimiter (`status="escalated"`) enables marking a block as escalated
without changing its content. YAML could do this too. Heading-based format
could not (no metadata slot).

<!-- decision:start id="block-format" -->
### Decision: Decision block format

**Question:** What format should decision blocks use for delimiters and internal structure?

**Evidence:** Three options evaluated against agent reliability, GitHub rendering behavior, extractability, and compact variant support. HTML comments are reliably produced by Claude models, appear in PR diffs (where review happens), are invisible in rendered markdown (reducing document noise), and support attribute metadata on the delimiter. YAML blocks constrain content to YAML-safe strings and render as code blocks. Heading-based blocks require fragile heuristic extraction and have heading-level conflicts.

**Choice:** HTML comment delimiters with markdown content

**Alternatives considered:**
- YAML blocks: agents produce YAML less reliably (indentation, colon escaping), rich markdown content requires multiline string syntax, renders as code blocks rather than documentation. Rejected because the content of a decision block is fundamentally prose, not configuration.
- Structured markdown with heading conventions: extraction is heuristic and fragile, heading levels conflict with surrounding document structure, no clean metadata attachment mechanism. Rejected because reliable machine extraction is a core requirement for the manifest and review surface.

**Assumptions:**
- Claude models will continue to reliably produce HTML comment syntax (high confidence -- well-established pattern)
- PR diff view is the primary review surface for decision blocks in context (validated by Decision 2 analysis)
- A simple regex is sufficient for extraction; no need for a full HTML parser (high confidence -- delimiters are structured and don't nest)

**Reversibility:** High. Migrating from HTML comments to another format is a mechanical find-and-replace operation. The markdown content between delimiters stays the same regardless of delimiter choice.
<!-- decision:end -->

---

## Decision 2: Assumption Review Surface

### The Question

Where should assumptions be surfaced for review at the end of a non-interactive workflow?

### Options Evaluated

**(a) Terminal summary at workflow end**

Print a structured summary to the terminal when the workflow completes.

Pros:
- Immediate visibility -- the user sees assumptions as soon as the workflow finishes
- No additional artifact to find
- Natural for the "run and review" pattern

Cons:
- Ephemeral -- if the terminal scrolls or the session closes, the summary is lost
- Not shareable with other reviewers
- Limited space for detail (terminal output should be scannable, not a document)

**(b) Dedicated assumptions section in PR body**

Add an "Assumptions (Auto Mode)" section to the PR description.

Pros:
- Visible to all PR reviewers, not just the invoker
- Persistent -- survives session close
- Integrates into the existing review workflow (PRs are where code review happens)
- Table format works well for scanning

Cons:
- Only available when the workflow creates a PR (design, work-on, prd create PRs;
  explore and plan don't always)
- PR body has size limits and competing content (summary, test plan, etc.)
- Assumptions are separate from the decisions they relate to

**(c) Separate wip/ artifact**

Write assumptions to `wip/<skill>_<topic>_assumptions.md`.

Pros:
- Full detail for every assumption
- Source of truth that other surfaces can reference
- Fits the existing wip/ pattern
- Available for all skills, not just PR-creating ones
- Supports the assumption lifecycle (invalidation, correction, re-execution)

Cons:
- Requires the reviewer to know it exists and navigate to it
- Another file to manage and clean up before merge

**(d) All three (layered)**

Terminal summary + wip/ artifact + PR body section, each at different detail levels.

Pros:
- Every reviewer persona is served: invoker (terminal), collaborator (PR), auditor (wip/ file)
- Progressive disclosure: scan terminal -> check PR -> deep-dive in file

Cons:
- Three surfaces to maintain
- Risk of inconsistency between surfaces (though all derive from the wip/ source)
- Implementation cost: each skill needs to write to three places

### Analysis

The user's stated need is to "review assumptions alongside decisions at the end."
This points to the terminal summary as the primary surface -- it's what appears
"at the end" of workflow execution.

But terminal output alone is insufficient for collaborative review. When the
workflow creates a PR, assumptions need to be in the PR body so other reviewers
see them.

The wip/ artifact is necessary regardless of which presentation surface we choose.
The assumption lifecycle (invalidation, correction, batch review) requires a
persistent, detailed record. The terminal summary and PR section are derived views.

The question is whether the overhead of three surfaces is justified.

**The layered approach works because each surface has a distinct purpose and audience:**
- Terminal: "did anything surprising happen?" (invoker, immediate)
- PR body: "what should I know before reviewing this code?" (reviewer, asynchronous)
- wip/ file: "I need to understand and possibly correct assumption A2" (auditor, detailed)

The cost of maintaining three surfaces is manageable because:
1. The wip/ file is written incrementally during execution (already needed)
2. The terminal summary is generated once at workflow end from the wip/ file
3. The PR body section is generated once during PR creation from the wip/ file

All three derive from the same source. Inconsistency is prevented by generation,
not manual synchronization.

However, Option (d) as described in the research adds complexity to every skill.
A pragmatic simplification: the wip/ file is always written (source of truth).
The terminal summary is always printed (every workflow ends). The PR section is
added only when a PR is created (not all workflows create PRs). This is still
"layered" but the third layer is conditional.

### Interaction with other decisions

The block format (Decision 1) uses HTML comments that are invisible in rendered
markdown. This makes the PR body section more important -- it's the rendered-visible
place where assumptions appear for reviewers who read the PR on GitHub.

The escalation model (Decision 3) may generate additional assumptions during
escalation. The wip/ file handles this naturally (append new assumptions). The
terminal summary regenerates at workflow end. The PR section generates at PR
creation time, after all decisions are complete.

<!-- decision:start id="review-surface" -->
### Decision: Assumption review surface

**Question:** Where should assumptions from non-interactive execution be surfaced for review?

**Evidence:** Four options evaluated against the user's stated need ("review assumptions alongside decisions at the end"), collaborative review requirements, and implementation cost. Terminal summary serves the invoker immediately. PR body serves asynchronous reviewers. The wip/ artifact is needed regardless for the assumption lifecycle (invalidation, correction, re-execution). All three surfaces serve distinct audiences and derive from the same source of truth, preventing inconsistency.

**Choice:** Layered approach -- wip/ artifact (source of truth, always written), terminal summary (always printed at workflow end), PR body section (conditional, added when a PR is created)

**Alternatives considered:**
- Terminal-only: ephemeral and not shareable. Insufficient for collaborative review on PRs.
- PR-body-only: not all workflows create PRs (explore, plan). Insufficient as a detailed record for assumption lifecycle management.
- wip/-artifact-only: requires the reviewer to know the file exists and navigate to it. Doesn't surface assumptions at the natural review moments (workflow completion, PR review).

**Assumptions:**
- The wip/ file is sufficient as the single source from which other surfaces derive (high confidence -- the file contains all fields, summaries compress)
- Terminal output is read by the invoker at workflow completion (high confidence -- standard CLI pattern)
- PR reviewers read the PR body before reviewing code (medium confidence -- some reviewers skip to the diff, but the PR body is the conventional place for reviewer context)

**Reversibility:** High. Adding or removing a review surface is additive/subtractive work with no impact on the underlying data model. The wip/ file structure doesn't change regardless of how many presentation surfaces consume it.
<!-- decision:end -->

---

## Decision 3: Lightweight-to-Heavyweight Escalation

### The Question

When a lightweight decision (micro-protocol) turns out to need heavyweight treatment
(decision skill), how should the transition work?

### Options Evaluated

**(a) Partial block with status="escalated" that feeds into decision skill**

During Step 2 of the micro-protocol, if the agent determines the decision is Tier 3+:
1. Write a partial decision block with Question and Evidence gathered so far
2. Mark the delimiter `status="escalated"`
3. Invoke the decision skill with the partial block as input context
4. The decision skill's report replaces the partial block in the manifest

Pros:
- Zero information loss: the framing and evidence from Steps 1-2 carry forward
- The partial block documents that escalation happened (audit trail)
- The decision skill can skip its Phase 0 (context extraction) since the
  lightweight protocol already framed the question
- The `status` attribute is already part of the block format spec (used for
  `status="assumed"` in non-interactive mode)

Cons:
- The partial block sits in the artifact in an incomplete state until the decision
  skill finishes. If the skill fails or is interrupted, there's a dangling partial block.
- The decision skill needs to know how to read a partial block as input -- adds
  an integration contract.
- "Replaces the partial block in the manifest" means the manifest entry gets
  updated, adding update semantics to what was an append-only structure.

**(b) Restart from scratch in decision skill (discard lightweight context)**

When escalation is needed, the agent simply invokes the decision skill with the
original question. The lightweight protocol's work is abandoned.

Pros:
- Simplest implementation -- no integration contract between micro-protocol and
  decision skill
- Decision skill runs its full workflow without assumptions about prior work
- No partial blocks to manage

Cons:
- **Information loss.** The micro-protocol's Step 1 (framing) and Step 2 (evidence
  gathering) work is discarded. The decision skill re-derives the question framing
  and re-gathers initial evidence. This is wasted work and, more importantly, the
  agent's initial framing might have been good -- re-framing could produce a worse
  or different question.
- No record that escalation happened. The decision appears in the manifest as a
  standard heavyweight decision with no trace of the lightweight attempt.

**(c) Lightweight always completes; heavyweight runs separately if needed**

The lightweight protocol always writes a complete decision block (Step 3 included).
If the decision later proves to need heavyweight treatment, the decision skill
runs as a separate operation. The lightweight block stays as a historical record.

Pros:
- No special escalation machinery
- Every lightweight decision has a complete record regardless of later treatment
- The heavyweight decision stands alone -- no dependency on the lightweight block

Cons:
- **The lightweight decision might be wrong.** If the agent recognized at Step 2
  that evidence was insufficient but was forced to complete Step 3 anyway, it writes
  a decision it knows is poorly supported. This is the opposite of the micro-protocol's
  design intent (don't decide when you don't have enough evidence).
- Two records for the same decision (lightweight block + heavyweight report) creates
  ambiguity about which one is authoritative.
- No workflow integration -- the agent has to manually determine "this earlier
  lightweight decision needs heavyweight treatment" as a separate cognitive step.

### Analysis

The core constraint is **no information loss during escalation.** This directly
eliminates Option (b).

The choice between (a) and (c) comes down to: should the agent commit to a
lightweight decision it knows is under-supported?

Option (c) forces the agent to write a decision it doesn't have confidence in.
The lightweight protocol's design explicitly says "if evidence is ambiguous (Tier 3+),
escalate." Forcing completion contradicts this principle. It also creates two
records for the same decision, requiring disambiguation rules.

Option (a) respects the tier boundary: when evidence indicates Tier 3+, the agent
stops the lightweight protocol and hands off to the heavyweight skill. The partial
block preserves work done so far. The decision skill reads the partial block as
seed context, skipping redundant framing.

**The dangling partial block concern** is manageable. If the decision skill fails:
- The partial block with `status="escalated"` remains in the artifact
- The manifest entry shows `status="escalated"` with no completion
- On workflow resume, the agent sees the escalated block and re-invokes the decision skill

This is actually better recovery behavior than Option (c), where a failed heavyweight
run leaves a dubious lightweight decision as the record of truth.

**The manifest update concern** is also manageable. The manifest already needs to
handle `status` transitions (e.g., `assumed` -> `confirmed` when a user reviews
assumptions). Adding `escalated` -> `decided` is the same pattern. The manifest
is an index, not a log -- it reflects current state, not history.

**The integration contract** (decision skill reads partial blocks) is lightweight:
the decision skill's Phase 0 checks for an existing partial block matching the
topic. If found, it uses the Question and Evidence fields as input instead of
extracting from scratch. If not found, it runs normally. This is an optimization
path, not a hard dependency.

### Interaction with other decisions

The `status="escalated"` attribute on the HTML comment delimiter (Decision 1) makes
this work cleanly. The block format already supports arbitrary attributes on the
opening delimiter.

The wip/ artifact (Decision 2) holds the partial block. The manifest shows its status.
The terminal summary at workflow end shows escalated decisions alongside completed ones.

<!-- decision:start id="escalation-model" -->
### Decision: Lightweight-to-heavyweight escalation model

**Question:** When a lightweight decision needs heavyweight treatment, how should the transition preserve context?

**Evidence:** Three options evaluated against the no-information-loss constraint. Option (b) discards the lightweight protocol's framing and evidence work -- direct information loss. Option (c) forces a decision the agent knows is under-supported, creating a dubious record and dual-record ambiguity. Option (a) preserves all work via a partial block, uses the existing `status` attribute mechanism, and provides clean recovery if the heavyweight skill fails mid-execution.

**Choice:** Partial block with status="escalated" that feeds into the decision skill

**Alternatives considered:**
- Restart from scratch: violates the no-information-loss constraint. The lightweight protocol's framing (Step 1) and evidence (Step 2) are discarded and re-derived, with no guarantee of equivalent quality. No escalation audit trail.
- Lightweight always completes: forces the agent to write a decision it recognizes as insufficiently supported, contradicting the tier-boundary principle. Creates two records for the same decision (lightweight + heavyweight) with ambiguous authority.

**Assumptions:**
- The decision skill can accept a partial block as optional seed context without tight coupling (high confidence -- it's a read-if-present optimization, not a hard dependency)
- Manifest entries can transition status (append-only is not a hard constraint) (high confidence -- the manifest is an index reflecting current state)
- Partial blocks with status="escalated" are rare in practice; most lightweight decisions complete at Tier 2 (medium confidence -- based on the tier distribution analysis showing most workflow decisions are lightweight)

**Reversibility:** Medium. The escalation integration contract (decision skill reads partial blocks) is a one-way coupling. Switching to Option (c) would require removing that integration and adding dual-record disambiguation. Switching to Option (b) would simply remove the partial-block reading code. The block format itself doesn't change.
<!-- decision:end -->

---

## Cross-Decision Interactions

These three decisions form a coherent system:

1. **Format enables review and escalation.** HTML comment delimiters with attributes
   (`id`, `status`) support both the escalation state machine (`status="escalated"`)
   and the review surface extraction (regex on delimiters).

2. **Review surface compensates for format invisibility.** Because HTML comments are
   invisible in rendered markdown, the layered review surface (terminal + PR body +
   wip/ file) ensures assumptions and decisions are always visible at the right
   moment and to the right audience.

3. **Escalation produces the same format.** Whether a decision completes as lightweight
   (full block) or escalates to heavyweight (partial block replaced by decision report),
   the manifest entry and review surface handle both identically. The reviewer doesn't
   need to know or care whether a decision was lightweight or escalated.

## Summary Table

| Decision | Choice | Key Rationale |
|----------|--------|---------------|
| Block format | HTML comment delimiters | Machine-extractable, agent-reliable, visible in PR diffs, supports metadata attributes |
| Review surface | Layered (wip/ + terminal + PR body) | Each surface serves a distinct audience; all derive from one source of truth |
| Escalation model | Partial block with status="escalated" | Zero information loss, clean recovery on failure, uses existing attribute mechanism |
