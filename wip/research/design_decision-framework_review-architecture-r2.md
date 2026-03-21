# Architecture Review Round 2: Decision Framework Design

Reviewer: Architecture specialist
Focus: New decisions (D11-D14) and D8 revision adequacy

## Previously Addressed (not re-raised)

- Compiled prompt drift (D8 revised to agent-reads-SKILL.md)
- PRD unaddressed (Component 6 added)
- wip/ cleanup timing (D5 specifies post-cross-validation)
- Protocol duplication (shared references/decision-protocol.md)
- Review noise (D9 has review priority for ~20/80 visible split)

---

## Issue 1 (High): D14 introduces a ghost file -- `decisions.json` vs `decisions.md`

**The problem.** D14 consolidates assumptions and decision manifests into a single
`wip/<workflow>_<topic>_decisions.md`. Good. But Component 4 (line 677) still
lists `wip/design_<topic>_decisions.json` as a "coordination manifest" alongside
`wip/design_<topic>_decisions.md` as the "consolidated decision index + assumptions."

These are described as different files with different purposes:

- `.json` -- "coordination manifest" (Phase 3 deliverable, line 677)
- `.md` -- "consolidated decision index + assumptions" (Phase 1 deliverable, line 678)

D14's text (lines 498-519) only describes the `.md` file and claims "one extra
file per invocation instead of two." But Component 4 quietly introduces a second
file anyway. The JSON manifest appears to be a machine-readable coordination file
for the Task agent fan-out (tracking which decisions are assigned to which agents,
their status, etc.), while the `.md` file is the human-readable consolidated record.

**Why it matters.** If they're two files, D14's "single consolidated file" claim
is wrong and the design has an undocumented artifact. If they're the same file,
the `.json` extension is wrong and Component 4 contradicts D14.

**Recommendation.** Clarify whether the coordination manifest is a separate
machine-readable artifact or part of the consolidated `.md` file. If separate,
D14 needs to acknowledge it and explain why the consolidation is still two files
(one human-facing, one machine-facing). If same file, fix the extension in
Component 4.

---

## Issue 2 (High): D8 revision solves maintenance but not sequential execution reliability

**The problem.** The round 1 architecture review flagged compiled prompt drift.
D8 was revised so agents read SKILL.md + phase files directly. This solves the
maintenance problem (single source of truth) but doesn't address the deeper
concern: can a spawned Task agent reliably execute a 7-phase sequential workflow
by reading phase files one at a time?

The current design skill (SKILL.md lines 206-217) works because the top-level
orchestrator -- running in the user's Claude Code session -- reads phase files
sequentially with full conversational context. Each phase builds on the prior
conversation. The agent can see what it did in Phase 1 when it starts Phase 2
because the conversation history is right there.

A spawned Task agent is different. It gets a prompt, runs, and returns a result.
If the decision skill's 7 phases are meant to run as a single agent invocation
(agent reads SKILL.md, then sequentially reads and executes all 7 phase files),
that agent needs to hold the full context of phases 0-5 when executing phase 6.
For a Tier 4 critical decision with adversarial bakeoff, peer revision, and
cross-examination, that's a substantial context load in a single agent turn.

The design doesn't specify whether the decision skill runs as:
(a) One long-lived agent that reads all phases sequentially (context pressure), or
(b) Multiple sequential agent spawns with state passed via wip/ files (coordination overhead and loss of conversational context between phases).

Option (a) works if the 7 phases fit comfortably in context, which they likely
do given the 80-160 line estimates per phase. But the design should state this
explicitly rather than leaving it ambiguous. Option (b) would be fragile and
expensive for a sub-operation.

**Why it matters.** The fast path (Tier 3: phases 0, 1, 2, 6) is fine -- four
short phases in one agent context. The full path (Tier 4: all 7 phases) pushes
more into a single agent's context window. If the agent's context fills up mid-
workflow, there's no recovery mechanism described. The negative consequences
table (line 815) acknowledges the risk ("If agent file navigation proves
unreliable, a compiled template can be added later") but this is a fallback for
a different failure mode (can't find files) rather than the one at issue (context
saturation during multi-phase execution).

**Recommendation.** Add an explicit statement in D8 or Component 1 that the
decision skill runs as a single agent invocation across all phases, with a
context budget estimate. Something like: "A full Tier 4 run reads ~800-1100
lines of phase instructions plus accumulated wip/ artifacts. This fits within
a single agent's context window. If context proves tight, the fast path (Tier 3)
handles most decisions, and the full path can be split into two agent stages
(research+bakeoff, then revision+synthesis) with wip/ handoff."

---

## Issue 3 (Medium): D12 HTML comment annotations are invisible to the agent's instruction-following path

**The problem.** D12 says known decision points get `<!-- decision-tier: N -->`
annotations in their phase files. The agent reads the phase file, sees the
annotation, and knows which tier to use without runtime classification.

HTML comments are invisible when markdown is rendered, but agents read raw
markdown -- so the comment IS visible to the agent as text. The concern isn't
visibility per se; it's attention. Phase files are structured as instructions
the agent follows step by step. An HTML comment is structurally different from
an instruction. It's metadata, not a directive.

In practice, LLMs handle HTML comments in markdown with mixed reliability:
- They reliably detect them when explicitly told to look for them
- They less reliably act on them when the comments are interleaved with
  procedural instructions and the agent is in "follow these steps" mode
- The failure mode is silent: the agent skips the annotation and falls through
  to the checklist fallback, which works but adds unnecessary classification
  overhead for decisions that were supposed to be pre-classified

The design partially mitigates this by having the checklist as a fallback. But
if the fallback fires for most pre-classified decisions, the pre-classification
adds complexity (39 annotations to maintain) without delivering its benefit
(skipping classification).

**A concrete alternative:** Instead of HTML comments, use explicit instruction
text:

```markdown
**Decision point (Tier 2):** Choose the decomposition granularity.
Use the lightweight protocol from references/decision-protocol.md.
```

This is a directive the agent will follow, not metadata it has to notice. It's
more verbose but it's in the instruction stream rather than beside it.

**Recommendation.** Test the HTML comment approach with 3-5 representative
phase file locations before committing to annotating all 39 points. If the
agent reliably picks up the annotations, keep them. If not, switch to inline
directive text. The design should acknowledge this as a validation step in
Phase 1 of the implementation approach rather than assuming HTML comments work.

---

## Minor Notes (not top-3 but worth tracking)

### D11 format co-location

The question was whether co-locating consumer rendering rules prevents the 7-8
file change problem or just moves it. The answer: it genuinely helps for field
additions (one file to update), but doesn't help for structural rendering
changes (e.g., "Considered Options should now include a risk matrix"). Structural
changes still propagate to consumers because the rendering rules describe how to
transform, and consumers interpret those rules. The design correctly notes the
escape hatch ("Can migrate to [a dedicated format-mapping file] if rendering
rules grow complex enough"). This is acceptable for v1.

### D13 count enforcement point

The question was whether the agent should merge trivially coupled decisions
before counting. The design says Phase 1 identifies "independent decision
questions using the existing split criterion." If the agent correctly applies
the independence criterion, coupled decisions would already be merged into
single questions. The ceiling of 10 applies after merging. This works IF the
agent applies the criterion before counting. The design could be more explicit:
"Count applies after applying the independence criterion, not before." One
sentence addition to D13 or Phase 1's description.

---

## Summary

| # | Issue | Severity | Location |
|---|-------|----------|----------|
| 1 | Ghost file: decisions.json vs decisions.md are ambiguously two files or one | High | D14 vs Component 4 |
| 2 | D8 doesn't specify single-agent vs multi-agent execution model for 7-phase workflow | High | D8, Component 1 |
| 3 | HTML comment tier annotations may not reliably reach the agent's instruction-following path | Medium | D12 |
