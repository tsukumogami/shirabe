# Usability Review Round 3: Decision Framework Design

Final review. Focus: end-to-end user experience, validator persistence UX,
assumption invalidation flow, first-time reader comprehension.

Previously addressed (not re-raised): review noise / 20-80 split, --auto
progress feedback, artifact proliferation / consolidation, auto-split
expectations in D13, tier annotation confusion in D12.

---

## 1. End-to-end walkthrough: `/design --auto some-topic` with 3 decisions

Walking through the 8-phase workflow to identify rough edges.

### Phase 0: SETUP

The agent creates `wip/design_some-topic_*` artifacts, reads constraints from
CLAUDE.md, sets up the design doc skeleton. No decisions yet. The user sees a
progress line: "Phase 0: setup complete."

**No issues.** Standard setup, unchanged from today.

### Phase 1: DECISION DECOMPOSITION

The agent reads the Context and Decision Drivers sections, identifies 3
independent decision questions. Count is under 5, so no scaling friction.

**Rough edge: what is the skeleton?** The design says Phase 1 "reads the
design doc skeleton's Context and Decision Drivers sections." But in --auto
mode, who wrote the skeleton? Phase 0 presumably creates it, but the design
doesn't specify what content is in the skeleton at this point. If the skeleton
is blank (just headings), the agent is decomposing decisions from... the issue
description? The SKILL.md input? This matters because decision decomposition
quality depends entirely on the input quality. The design assumes good input
without specifying where it comes from.

**User sees:** "Phase 1: identified 3 decision questions." Fine.

### Phase 2: DECISION EXECUTION

The agent spawns 3 Task agents (one per decision). Each agent reads the
decision skill's SKILL.md and navigates 4-7 phases depending on tier.

**Rough edge: what does the user see during parallel agent execution?**
The progress protocol says "one-line status after each phase transition."
But Phase 2 contains 3 sub-workflows, each with their own phases. Does the
user see:

- "Phase 2: executing decision 1/3..." (coarse -- could run 5+ minutes with
  no further signal)
- "Phase 2: decision 1 phase 3 (bakeoff)..." (fine-grained -- noisy, and the
  user doesn't know what "decision 1 phase 3" means without context)
- Something in between?

The design says "one-line status after each phase transition" at the
orchestrator level. But during Phase 2, the orchestrator is waiting on Task
agents. It has no phase transitions of its own to report. The sub-agents
are running in background and can't emit progress to the user's terminal
(they're Task agents, not the interactive session).

**This is the biggest UX gap in --auto mode.** Phase 2 is where most of the
work happens, and the user gets exactly one status line at entry and one at
exit. For a 3-decision Tier 4 design, Phase 2 could run 10-15 minutes with
no intermediate feedback. The progress protocol as designed doesn't cover
intra-phase parallelism.

**Possible fix (not prescriptive):** the orchestrator could poll Task agents
and emit completion lines: "Phase 2: decision 1 complete (TTL-based caching,
confirmed), 2/3 remaining." This gives the user a completion counter without
exposing sub-phase detail.

### Phase 3: CROSS-VALIDATION

The agent reads all 3 decision reports, checks assumptions against peer
choices, flags conflicts. Suppose decisions 1 and 3 conflict. Decision 3 is
restarted once with decision 1's output as a constraint.

**Rough edge: restart cost is invisible.** The user sees "Phase 3:
cross-validation." If a decision restarts, that's another full decision skill
run for one question. The user doesn't know this happened. They don't know
why Phase 3 is taking longer than expected. The restart should emit a status
line: "Phase 3: conflict detected between decisions 1 and 3, restarting
decision 3 with constraints."

**Otherwise fine.** Single pass with bounded restart is a clean design. The
user doesn't need to understand the mechanics -- they just need to know it's
happening and roughly how long it will take.

### Phase 4: INVESTIGATION

Slimmed to implementation-level unknowns. No approach validation (the bakeoff
handled that).

**Rough edge: is this phase still needed for 3-decision designs?** The design
says Phase 4 focuses on "implementation-level unknowns needed for architecture
writing." But the decision skill's Phase 1 (research) already investigates
implementation feasibility per decision. If all 3 decisions were Tier 3+,
their research phases already covered implementation unknowns.

The risk is that Phase 4 re-investigates what the decision agents already
found, wasting context window and time. The design should clarify what
investigation Phase 4 does that the decision skill's research didn't. If the
answer is "cross-cutting implementation concerns that span multiple
decisions," say that explicitly.

### Phases 5-7: ARCHITECTURE, SECURITY, FINAL REVIEW

These proceed as before with decision blocks already written. The agent
writes the architecture section informed by the 3 decision reports.
Implicit decisions during architecture use the lightweight micro-protocol.

**Rough edge: lightweight decisions during Phase 5 don't go through
cross-validation.** The design says "implicit decisions discovered during
Architecture (Phase 5) stay inline using the lightweight micro-protocol."
Cross-validation ran in Phase 3, before architecture writing. So a lightweight
decision made in Phase 5 that conflicts with a heavyweight decision from Phase
2 will never be caught by cross-validation.

This is probably acceptable (Phase 5 decisions are genuinely simpler), but
the design should acknowledge this gap. A user reviewing assumptions might
wonder why a Phase 5 decision wasn't cross-validated against earlier ones.

### End state

The user gets:
- A design doc with 3 Considered Options sections and inline decision blocks
- `wip/design_some-topic_decisions.md` with index + assumption details
- A terminal summary listing high-priority assumptions
- (Later) a PR body section with assumptions

**Rough edge: what does the user do next?** The terminal summary says "3
decisions made, 2 confirmed, 1 assumed (high priority)." The assumed decision
has a confidence level and an "if wrong" restart path. But the design doesn't
describe the interaction pattern. Does the user:

a) Read the assumption, decide it's fine, do nothing? (What marks it as
   reviewed?)
b) Read the assumption, disagree, and... what? (See section 3 below.)
c) Read the assumption, want more detail, and... open the wip/ file? (How
   do they find the right entry?)

The terminal summary needs to be actionable. Each high-priority assumption
should include enough context to decide without opening a file, plus a clear
next step ("to override, re-run with --interactive" or "to accept, no action
needed").

---

## 2. Validator persistence UX (Tier 4)

In Tier 4, the decision skill spawns validator agents in Phase 3. These
agents persist through Phases 4 (peer revision via SendMessage) and Phase 5
(cross-examination via SendMessage).

### What does the user see in interactive mode?

The design is silent on this. The validator agents are sub-agents of the
decider, which is itself a sub-agent of the orchestrator. The user's
interactive session is with the orchestrator.

**Scenario:** the user runs `/design some-topic` (interactive). Phase 2
spawns a decider agent. The decider spawns 3 validator agents. They argue,
revise, cross-examine. Then the decider synthesizes and reports back.

**What appears in the user's terminal?** The orchestrator's tool calls. The
user sees `run_in_background` calls to spawn decider agents, then
`TaskOutput` calls to collect results. They don't see the validator debate.
They don't see the revision or cross-examination. They see the final
decision report.

**This is probably correct.** The validator debate is an internal quality
mechanism, not something the user needs to observe in real-time. Exposing it
would be overwhelming -- three agents arguing about cache invalidation
strategies while the user watches tool calls scroll past.

**But the user has no visibility into decision quality.** In the current
design skill, the user sees advocate arguments directly (they're written
to artifacts the user can inspect). In the new system, validator arguments
are internal to sub-agents. The decision report includes the chosen option
and rejected alternatives with reasons, but not the full argument/counter-
argument exchange.

**Recommendation:** the decision report (output contract) should include a
brief "deliberation summary" -- 3-5 sentences describing the key arguments
and what swung the decision. Not the full transcript, but enough to give the
user confidence that the validators actually stress-tested the choice. This
is especially important for Tier 4 decisions, which are the ones where the
user would most want to understand the reasoning.

### Interactive mode for the decider itself

When the decider agent runs in a context where the parent is interactive,
the decider itself can't interact with the user (it's a Task agent). So
even in interactive mode, the validator debate runs autonomously. The user
only interacts at the orchestrator level, after the decision report comes
back.

**The design should state this explicitly.** A reader might assume
"interactive mode" means the user participates in the bakeoff. They don't.
Interactive mode means the user confirms or overrides the decision *after*
the bakeoff produces a recommendation. The bakeoff itself is always
autonomous.

---

## 3. Assumption invalidation flow

The user reviews the terminal summary and says "assumption A3 is wrong."
What happens?

### What the design says

The Security Considerations section states: "When a human invalidates an
assumption, the agent re-evaluates decisions but doesn't re-run
implementation. No blast radius beyond the decision artifacts themselves."

Decision 14 says the consolidated decisions file has "if wrong" restart
paths per assumption.

### What the design doesn't say

**How does the user express "A3 is wrong"?** This is a conversational
interaction -- the user is in the terminal after the workflow completes, so
they type something. But what? The design doesn't specify:

- Is there a command? (`/invalidate A3`? `/review-assumptions`?)
- Does the user just type "A3 is wrong" in the conversation?
- Does the user edit the wip/ file directly?

**What happens mechanically after invalidation?** "Re-evaluates decisions"
means... what? The design lists several possibilities without committing:

1. The agent re-reads the decision that produced A3, runs the decision
   protocol again with the new constraint ("A3 is false"), and produces a
   revised decision block.
2. The agent looks at the "if wrong" restart path in the decisions.md file
   and tells the user what to do.
3. The agent re-runs the entire phase that produced the decision.

Option 1 requires the agent to have context about the original decision
(which it might not, if it's a fresh conversation). Option 2 is passive --
the "if wrong" path is documentation, not automation. Option 3 is expensive
and might not be feasible.

**The most likely actual experience:** the user finishes a `/design --auto`
run. They read the terminal summary. They disagree with assumption A3. They
type "A3 is wrong because X." The agent, still in the same conversation,
reads the decisions.md file, finds A3's decision, and... needs to re-run
the decision skill for that question. But the decision skill's context
(research, alternatives, bakeoff) is in artifacts that were cleaned up
after cross-validation.

**This is a gap.** The design explicitly says intermediate artifacts are
cleaned after cross-validation (Decision 5, Decision 6). So the agent
can't cheaply re-evaluate -- it has to re-run the full decision from
scratch, or work from only the final report.

**Recommendation:** define the invalidation flow concretely. At minimum:
- Specify that the user invalidates by telling the agent in conversation
  (no special command needed)
- Specify that the agent re-reads the decision report (which persists) and
  the user's correction, then re-runs the lightweight or heavyweight
  protocol for that single decision with the correction as a constraint
- Acknowledge that intermediate artifacts aren't available and the re-run
  starts from the report, not from cached bakeoff results
- Specify what happens to downstream decisions that assumed A3 was true
  (cascade invalidation? manual review? nothing?)

### Cascade invalidation

Suppose A3 was an assumption from decision 1, and decision 3 was built on
decision 1's output (they were coupled). Invalidating A3 potentially
invalidates decision 3. The design's cross-validation catches conflicts
between decisions during the initial run, but doesn't describe what happens
when a post-hoc invalidation creates a new conflict.

At minimum, the agent should check whether any other decisions reference the
invalidated assumption's decision in their constraints or context. If so,
flag them for review.

---

## 4. First-time reader comprehension

A contributor opens DESIGN-decision-framework.md without having read the
exploration, the issue, or the prior reviews. Can they understand the system?

### What works

- The frontmatter summary is dense but complete. A reader who parses it
  carefully gets the high-level picture.
- Decision 1 (block format) is concrete and shows examples. Good anchor.
- The tier system (1-4) in Decision Outcome is clear and well-structured.
- The Solution Architecture section with 7 numbered components provides a
  solid structural overview.

### What's confusing

**The "39 decision points" claim has no grounding.** The design references
39 blocking points, 28% researchable, 49% judgment calls, 26% approval
gates. These numbers appear authoritative, but there's no reference to
where they come from. A first-time reader has to trust these statistics
without being able to verify them. The design should cite the source
(presumably the exploration or an appendix) or at minimum say "identified
during exploration of existing skill files."

**Tier 3 vs Tier 4 distinction is unclear until you read Decision 8.**
The Decision Outcome section lists 4 tiers. Tier 3 is "decision skill
fast path (phases 0, 1, 2, 6)." Tier 4 is "decision skill full 7-phase."
The difference is whether phases 3-5 (bakeoff, peer revision, cross-
examination) run. But what makes a decision Tier 3 vs Tier 4? Decision 12
provides the signals, but it's 8 decisions later. A reader hitting Tier 3
and Tier 4 in the outcome section has to keep reading for ~300 lines before
understanding when each applies.

**Recommendation:** add one sentence to the tier descriptions in Decision
Outcome. E.g., "Tier 3 (standard -- multiple viable options, reversible)"
and "Tier 4 (critical -- irreversible or high-stakes)." Don't duplicate
D12's full checklist, just enough for a reader to build an intuition.

**The relationship between components is forward-referenced.** Component 1
(decision skill) references Decision 8 (agent prompt). Component 2
(lightweight protocol) references Decision 12 (tier classification).
Component 4 (design skill changes) references Decision 5, 6, and 13. A
linear reader hits these components before the referenced decisions are
fully explained.

This is inherent to the document structure (Considered Options before
Solution Architecture), and there's no clean fix. But a brief "how to
read this document" note after the status section could help: "Considered
Options (14 decisions) establishes the architectural choices. Solution
Architecture shows how they compose. Implementation Approach sequences the
build order."

**"Decision skill" vs "decision protocol" vs "decision framework" naming.**
The design uses all three terms. The "decision skill" is the heavyweight
7-phase component. The "decision protocol" is the lightweight 3-step
micro-workflow. The "decision framework" is the umbrella term for all three
layers. This is clear once you've read the full design, but a first-time
reader encountering "decision protocol" in one paragraph and "decision
skill" in the next may think they're the same thing.

The Context section (lines 47-51) defines the three components clearly.
But by line 200, a reader who didn't memorize the distinction may confuse
them. The naming is correct and consistent, but the terms are similar
enough to blur on first reading.

---

## Summary of findings

### High priority (affects user experience or design completeness)

1. **Phase 2 progress gap.** The progress protocol doesn't cover intra-phase
   parallelism. During Phase 2 of a multi-decision design, the user gets no
   feedback for potentially 10-15 minutes. The orchestrator should emit
   completion lines as Task agents finish.

2. **Assumption invalidation flow is undefined.** The design mentions
   re-evaluation but doesn't specify how the user triggers it, what the
   agent does mechanically, or how cascade effects are handled. The "if
   wrong" restart paths in the decisions file are documentation, not a
   working mechanism.

3. **Post-Phase-2 actionability.** The terminal summary lists assumptions
   but doesn't tell the user what to do with them. Each high-priority
   assumption needs a concrete next step (accept by doing nothing, override
   by re-running interactively, etc.).

### Medium priority (clarity improvements)

4. **Phase 4 overlap with decision research.** The slimmed Investigation
   phase may re-investigate what decision agents already covered. Clarify
   that Phase 4 focuses on cross-cutting implementation concerns that span
   multiple decisions.

5. **Validator debate visibility.** The user never sees the bakeoff
   arguments, even in interactive mode. The decision report should include
   a brief deliberation summary so the user can assess decision quality.

6. **Bakeoff is always autonomous.** Even in interactive mode, the user
   doesn't participate in the validator debate. They confirm or override
   after the fact. The design should state this explicitly to avoid
   misunderstanding.

### Low priority (first-time reader improvements)

7. **Tier 3/4 distinction needs a one-line hint** in Decision Outcome before
   the full classification system appears 300 lines later.

8. **The 39 decision points statistic needs a source reference** for readers
   without exploration context.

9. **A brief "how to read this document" note** after the status section
   would help readers navigate the 830-line structure.
