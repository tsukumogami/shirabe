# Lead: Where in Phase 1/2 does the adversarial lead integrate with minimum disruption to existing explore UX?

## Findings

### The Integration Surface in Phase 1

Phase 1 is a conversational scoping phase that ends with a persist step (1.2) writing
`wip/explore_<topic>_scope.md`. The scope file's `## Research Leads` section is what
Phase 2 reads — this is the only interface between Phase 1 and Phase 2. Phase 1 does
not classify topics; it produces questions. The resume check for Phase 1 is a single
file-existence check: if `wip/explore_<topic>_scope.md` exists, skip to Phase 2.

There is no "topic type" field in the scope file schema. The scope file carries: Core
Question, Context, In Scope, Out of Scope, and Research Leads. No metadata tags, no
classification fields.

Phase 1's checkpoint (1.1) is lightweight — a summary presented to the user before
persisting. The user can course-correct but there is no structured decision point that
branches the workflow.

### The Integration Surface in Phase 2

Phase 2 reads leads from `wip/explore_<topic>_scope.md` (the `## Research Leads`
section) and launches one agent per lead in parallel. It is purely mechanical: read
leads, build prompts, launch agents, collect summaries. There is no filtering, branching,
or classification logic in Phase 2. Every lead in the scope file gets an agent.

The scope file is the only input Phase 2 consumes for lead selection. On subsequent
rounds, the orchestrator updates the scope file with new leads before Phase 2 re-runs —
the same read-and-dispatch pattern applies.

Phase 2's resume check: if `wip/research/explore_<topic>_r<N>_lead-*.md` files already
exist for the current round AND no findings file exists, skip to Phase 3. This is a
file-pattern check, not a content check.

### The Orchestrator Controls the Phase Boundary

SKILL.md owns the discover-converge loop. The orchestrator calls Phase 2, waits for
Phase 3 to complete, then decides (via AskUserQuestion) whether to loop back or
crystallize. The phase files themselves do not branch — they execute linearly and hand
back to the orchestrator.

This means any logic that needs to run "between phases" must live in the orchestrator
(SKILL.md), not in a phase file, unless it's part of a phase file's own steps.

### What DESIGN-plan-review.md's Approach Reveals

The plan-review design added a new mandatory phase (Phase 6 replacement, effectively
a new Phase 6.5) without modifying any existing phase file. The core technique was
a two-file artifact scheme: the existing resume trigger (`wip/plan_<topic>_review.md`
exists → Phase 7) remained completely unchanged. A new loopback artifact
(`wip/plan_<topic>_review_loopback.md`) handled the divergent path without touching
the proceed path's resume logic.

The design's stated principle: "preserves the existing Phase 7 resume trigger unchanged
(no regression risk)." The avoid-modifying-existing-logic constraint was treated as
a hard requirement, not a preference.

Applied to the explore context: the analogous principle would be — don't touch
phase-1-scope.md, phase-2-discover.md, phase-3-converge.md, or the existing resume
checks in SKILL.md. Any new behavior should extend, not modify.

The "always run" vs "opt-in" decision in plan-review: the design chose always-run for
all four categories (A-D) in both fast-path and full modes. The argument was that
opt-in for specific categories defeats the purpose — you'd be skipping the exact failure
modes you added the review to catch. This maps onto the adversarial lead question: if
the adversarial lead is only valuable for directional topics, making it opt-in via
classification is acceptable; making it always-run for all topics would add noise to
diagnostic explorations.

### Evaluating the Three Integration Options

**Option A: Phase 2 addition — adversarial lead added to the leads list if topic is directional**

What changes: Phase 2 would need logic to detect topic type (directional vs. diagnostic)
before building agent prompts. Phase 2 currently has no such logic — it reads leads and
dispatches. Adding this check modifies phase-2-discover.md and requires defining what
"directional" means and how to detect it from the scope file.

Alternatively, the scope file could carry an adversarial lead already written by Phase 1
(conditional on topic classification during the conversation). In that case Phase 2 needs
zero changes — it just dispatches whatever leads are in the scope file, including an
adversarial one if present.

Resumability: if the adversarial lead is in the scope file like any other lead, the
existing resume check (`wip/research/explore_<topic>_r<N>_lead-adversarial.md` exists)
works automatically — no new resume infrastructure needed.

UX for diagnostic topics: if the adversarial lead is only added when appropriate (either
via Phase 1 classification or via explicit scope-file inclusion), diagnostic topics get
no adversarial lead and experience zero UX change.

**Option B: Phase 1 classification — add a step at end of Phase 1 that classifies topic type**

What changes: phase-1-scope.md gets a new step (e.g., 1.3 Classify Topic) after 1.2
Persist Scope. This step would write a classification field to the scope file, then
conditionally add an adversarial lead to the `## Research Leads` section before
committing.

Alternatively, the classification could happen during the checkpoint (1.1) and the
adversarial lead is simply included in the leads presented to the user for review —
indistinguishable from any other lead at that point.

Phase 2 changes: none, because the adversarial lead is already a lead in the scope file.
SKILL.md changes: none.

Resumability: Phase 1's resume check is `scope file exists → skip to Phase 2`. If Phase 1
is interrupted after 1.2 but before a hypothetical 1.3 classification step, resume skips
to Phase 2, which may be missing the adversarial lead. This is a small resumability gap —
only relevant if interrupted in a narrow window.

If classification happens as part of producing leads (during 1.1/1.2, not as a separate
post-persist step), there is no gap: the scope file either contains the adversarial lead
or it doesn't, and Phase 2 handles both cases identically.

UX for diagnostic topics: Phase 1's conversation would simply not produce an adversarial
lead for diagnostic topics. The user sees no classification step, no branching, no
special behavior — the lead either appears in the checkpoint summary or it doesn't.

**Option C: Pre-Phase 2 gate — explicit classification step between Phase 1 and Phase 2**

What changes: SKILL.md would need a new block between the "Phase 1" and "Phase 2"
sections that: reads the scope file, classifies the topic, conditionally injects an
adversarial lead into the scope file, then proceeds to Phase 2.

This adds a visible seam in the orchestrator. It also means the scope file can be
updated after Phase 1 commits it — the committed scope file may not match what Phase 2
actually uses, which could confuse a human reviewing the artifact.

Resumability: SKILL.md's resume logic currently routes `scope.md exists → Phase 2` with
no intermediate state. A classification step between Phase 1 and Phase 2 either runs
every time (idempotent, low cost) or requires its own artifact to track completion.
If it runs every time on resume, it re-classifies and potentially re-adds the adversarial
lead, which is safe but wasteful. If it requires an artifact, it adds new resume
infrastructure — what DESIGN-plan-review.md explicitly tried to avoid.

UX for diagnostic topics: if the classification step is transparent (just modifies the
scope file silently), diagnostic topics see nothing. But the step runs for all topics,
adding latency. If the step surfaces to the user ("I've classified this as directional
and added an adversarial lead"), it creates a visible UX interrupt that diagnostic topics
don't need.

### Summary of Change Surface by Option

| Option | phase-1-scope.md | phase-2-discover.md | SKILL.md | New resume artifacts |
|--------|-----------------|---------------------|----------|---------------------|
| A (Phase 2 addition with scope-file pre-population) | Minimal: classification logic folded into lead production | None | None | None |
| A (Phase 2 addition with in-Phase-2 detection) | None | Adds classification logic | None | None |
| B (Phase 1 classification, integrated) | Adds classification logic to lead production | None | None | None |
| C (Pre-Phase 2 gate) | None | None | Adds new block | Possibly |

Options A (scope-file pre-population) and B (Phase 1 classification integrated into lead
production) collapse to the same implementation: Phase 1 decides whether to include an
adversarial lead, writes it to the scope file like any other lead, and Phase 2 dispatches
it automatically. The difference is framing, not implementation.

## Implications

The DESIGN-plan-review.md pattern — preserve existing artifact triggers and resume
logic, extend don't modify — points strongly toward the scope-file-as-interface approach.
Phase 2 already treats the scope file as its sole input. Adding an adversarial lead to
the scope file during Phase 1 (when the topic is directional) requires zero changes to
Phase 2, Phase 3, SKILL.md resume logic, or any other phase. The lead becomes
indistinguishable from any other lead once it's in the file.

The key design question shifts from "where does the adversarial lead integrate?" to
"where does classification happen?" And that question has a clear answer from the
Phase 1 spec: Phase 1 already accumulates understanding of the topic via the coverage
tracking table (Intent, Uncertainty, Stakes, etc.). A directional vs. diagnostic signal
emerges naturally from that conversation. Phase 1 is the right place to make this
judgment — it already has all the inputs.

Classification during Phase 1's lead-production step (before the checkpoint, so the
user sees the adversarial lead in the checkpoint summary) is the minimum-disruption
path because: it touches only phase-1-scope.md, it requires no new artifacts, it
requires no new resume infrastructure, it produces no visible UX difference for
diagnostic topics (the adversarial lead simply isn't there), and Phase 2 and all
subsequent phases are completely unchanged.

## Surprises

Phase 2's read-leads-and-dispatch pattern is simpler than expected. There's no
filtering, no lead-type metadata, no branching — it's a pure fan-out. This means the
scope file is not just the interface but the complete control surface for Phase 2
behavior. Anything you want Phase 2 to do differently, you encode in the scope file
content before Phase 2 runs.

The DESIGN-plan-review.md rationale for two-file scheme is explicitly about not making
the resume logic content-aware. That same principle applies here: if classification
produces a scope file that already contains the adversarial lead, Phase 2's resume
check (`scope file exists → proceed`) remains content-agnostic and unchanged.

Options A (Phase 2 addition via scope file pre-population) and B (Phase 1 classification)
are functionally identical — the implementation difference is only which phase file gets
the classification logic added. Framing them as separate options obscures this.

## Open Questions

1. What signals distinguish "directional" from "diagnostic" reliably enough for Phase 1
   to classify without asking the user? The coverage tracking table's "Intent" and
   "Stakes" fields are the most likely sources, but the boundary cases need definition.

2. Should the adversarial lead be presented to the user during the Phase 1 checkpoint
   as a named lead (making the intent explicit), or written silently into the scope file?
   The Phase 1 spec says the user "can interject at any point to course-correct" — making
   it visible in the checkpoint gives the user a chance to push back on the classification.

3. How does this interact with `--auto` mode? In auto mode, Phase 1 still produces leads
   without user interaction. The classification logic would need to follow the same
   research-first, document-the-decision pattern used elsewhere in auto mode.

4. Is one adversarial lead always sufficient, or does the adversarial challenge need to
   be proportional to the number of directional leads? A topic with 7 leads oriented
   toward a specific direction might need deeper challenge than a topic with 2 directional
   leads.

## Summary

The minimum-disruption integration point is Phase 1's lead-production step: classification
happens during the conversation, and the adversarial lead enters the scope file alongside
other leads, making Phase 2 and all subsequent phases require zero changes. Options A and
B collapse to the same implementation once you recognize that Phase 2 is a pure fan-out
over scope-file leads with no filtering logic. The DESIGN-plan-review.md pattern confirms
this: preserve existing artifact-based resume triggers, extend by adding content to
existing artifacts rather than adding new phases or new resume checks.
