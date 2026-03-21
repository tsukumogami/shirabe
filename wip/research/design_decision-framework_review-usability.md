# Usability review: Decision framework design

Reviewer perspective: daily user of shirabe skills (work-on, explore, design).

---

## 1. Decision fatigue vs decision recording

The design replaces 39 blocking points with structured decision blocks. The claim is that this reduces friction. But it shifts the burden from "answer a question now" to "review a wall of assumptions later."

**The math doesn't work for lightweight decisions.** The compact variant (Decision 1) is 3 lines. The full variant is 10-20 lines. A design doc run hits ~10 decision points in the design skill alone (D1-D10), plus lightweight decisions discovered during architecture. In --auto mode, that's 10-20 decision blocks dumped into `wip/design_<topic>_assumptions.md`, plus the inline blocks in the design doc itself, plus a terminal summary, plus a PR body section.

A user who runs `/design --auto caching-strategy` will finish with:
- A design doc containing inline decision blocks (rendered markdown, invisible delimiters)
- A separate assumptions manifest in wip/
- A terminal summary listing all assumed decisions
- A PR body section repeating the assumptions

That's 3 views of the same information. The terminal summary and PR section are "read-only views" (Decision 2), but the user still has to process them to know whether to trust the output.

**The real problem: most of these decisions don't deserve review.** Branch naming (D1 equivalent in work-on), decomposition strategy (PL3), loop termination (E7, P4) -- these are choices the agent should just make. The inventory itself shows 14 of 19 judgment calls already have heuristics. Recording them as decision blocks with Question/Evidence/Choice/Assumptions fields turns a 0-second non-event into a 10-line artifact the user is implicitly asked to review.

**What would actually help:** a two-tier review surface. Tier 1 decisions (trivial) produce no record -- the design already says this. But the boundary between Tier 1 and Tier 2 is "a reasonable person could have chosen differently." That bar is too low. Branch naming passes it (someone might prefer `feature/parser` over `feat/parser`). Decomposition strategy passes it. The bar should be: "if the agent chose wrong, would the user need to restart?"

## 2. The --auto experience during execution

The design specifies what happens at the end (terminal summary, PR body, assumptions artifact). It says nothing about what happens during a 10-20 minute --auto run.

Current interactive experience: the user sees questions, answers them, watches the agent work between questions. There's a rhythm. The user knows where the workflow is.

Proposed --auto experience: silence. The agent runs, makes decisions, writes artifacts. The user sees... tool calls scrolling past? Nothing until the terminal summary?

**Missing from the design:**
- Progress indicators. Which phase is the agent in? How many decisions has it made?
- Intermediate output. When the agent makes a significant assumed decision (approach selection in design, artifact type in explore), should it log that immediately rather than batching it for the end?
- Failure modes. If the agent gets stuck in Phase 3 of a design run, the user has no signal. In interactive mode, the agent would ask. In --auto, it either halts silently or produces garbage.

The design addresses loop termination (Decision 10) with `--max-rounds`, which is good. But that's the only concession to the "what's happening while I wait" problem.

**What's needed:** a progress protocol. Not a new skill -- just a convention that each phase logs a 1-line status message ("Phase 2: selected TTL-based caching, assumed") and each assumed decision gets a 1-line immediate log. The terminal summary then becomes a recap, not the first time the user sees the information.

## 3. Lightweight protocol overhead on phase file authors

The 3-step micro-protocol (frame, gather, decide) applies at "any decision point" in any phase file. The triggers are:

- The decision affects downstream artifacts
- A reasonable person could have chosen differently
- The choice rests on a falsifiable assumption
- Reversing would require rework

These triggers are broad enough that a phase file author writing "check if the branch exists, if not create one" now has to ask: "Is branch naming a decision? A reasonable person could name it differently. It rests on a convention assumption. Should I add a decision block?"

**Currently, phase files just say what to do.** "Create a branch named `feat/<issue-slug>`." That's an instruction. The lightweight protocol turns it into a decision point that needs framing, evidence gathering, and recording.

The design acknowledges Tier 1 (trivial, no record), but the tier classification itself is a judgment call the agent makes at runtime. Phase file authors can't pre-classify because the same instruction might be trivial in one context and non-trivial in another.

**The overhead is real but may be acceptable** if the phase files themselves don't change. If the protocol is purely a runtime behavior (the agent decides whether to invoke it), phase file authors are unaffected. But the design says "every skill that currently uses AskUserQuestion at decision points switches to the research-first pattern" (Component 6), which implies phase file changes. That's 39 points across 20+ phase files that need rewriting.

The question is: does each phase file need to encode the 3-step protocol explicitly, or does the agent internalize it from a reference document? If the former, that's significant overhead on phase file maintenance. If the latter, it's a one-time cost to write the reference doc, and phase files stay as instructions.

## 4. The 50/50 confirmed/assumed split

Decision 9 explicitly targets a 50/50 split between confirmed and assumed decisions. The rationale: "both values carry signal for review triage."

This is backward. The purpose of the review surface is to flag things that might be wrong. If half of all items are flagged, the signal-to-noise ratio is 1:1. Users will stop reading.

**The category mapping guarantees the problem:**
- All approval gates (26% of decisions) are always "assumed"
- Judgment calls are "assumed" when "heuristic was close, or contradicting evidence exists"
- Only research-backed choices with clear answers get "confirmed"

So the user finishes a `/design --auto` run and sees: 5 assumed decisions (the approval gates plus a couple close judgment calls) and 5 confirmed decisions. The assumed list includes "Final design approval was automatic" -- which the user already knows because they ran --auto. It includes "decomposition strategy: walking skeleton" -- which is only assumed because someone *could* have picked horizontal.

**A better split: 80/20.** Reserve "assumed" for decisions where the agent found contradicting evidence, where the heuristic was genuinely ambiguous, or where the decision has high reversal cost. Make "confirmed" the default for: applying documented heuristics, following existing conventions, auto-approving after validation passes. The review surface shrinks to 2-4 items that actually need human judgment.

The current design treats "would have asked the user" as a considered-and-rejected threshold. But the replacement threshold ("category-based") is barely better. Judgment calls with clear heuristics should be confirmed, not assumed.

## 5. Backward compatibility

The design doesn't mention opt-out. Existing users get:
- `--auto` flag added to all skills (harmless -- it's opt-in)
- Decision blocks appearing in artifacts (even in interactive mode)
- Research-first behavior at all 39 decision points (changes the interactive experience)

**The interactive mode change is the real compatibility concern.** Currently: agent hits a decision point, asks. Proposed: agent hits a decision point, researches first, then asks with evidence. This is better in theory, but it changes the pacing. A user who knew the answer immediately now waits while the agent researches something they could have answered in 2 seconds.

The writing-style skill (SKILL.md reviewed) is unaffected -- it has no decision points, no phases, no AskUserQuestion calls. It's a reference skill that agents apply proactively. The decision framework correctly scopes to workflow skills only.

work-on has only 4 blocking points. W3 and W4 are safety gates that stay blocking in both modes. W1 (needs-triage) and W2 (spec ambiguity) are minor. The impact on work-on is small -- it's already the most linear skill. But even here, the decision block format adds artifacts to a workflow that currently produces `wip/issue_<N>_plan.md` and `wip/issue_<N>_summary.md`. Now it also produces `wip/work-on_<N>_assumptions.md` and `wip/work-on_<N>_decision-manifest.md`. Two more files in wip/ per issue.

**There's no way to say "I don't want decision blocks."** A user who likes the current interactive experience -- quick questions, quick answers, minimal artifacts -- now gets structured decision records whether they want them or not. The CLAUDE.md `## Execution Mode: interactive` default preserves the asking, but the research-first behavior and decision recording still apply.

---

## Top 3 daily-user frustrations

### 1. Review surface is too noisy to be useful

A 50/50 confirmed/assumed split means the assumptions list is long and includes items the user doesn't care about (branch names, decomposition strategy, auto-approvals). After 2-3 runs, users will learn to skip the review entirely, defeating the purpose. The framework needs a higher bar for "assumed" -- something like 80/20 -- so the review surface contains only decisions with genuine uncertainty.

### 2. No feedback during --auto execution

Running `/design --auto` or `/explore --auto` produces nothing visible for 10-20 minutes, then dumps results. The design specifies the end-state review surface thoroughly but ignores the during-execution experience. Users need per-phase progress lines and immediate logging of significant assumed decisions to maintain trust that the agent isn't stuck or heading in a wrong direction.

### 3. Artifact proliferation in wip/

Every skill invocation now produces 2 additional wip/ files (assumptions manifest + decision manifest) on top of existing artifacts. For work-on, that's 4 wip/ files per issue instead of 2. For design, the count grows further with per-decision report files. These files are committed to feature branches and cleaned before merge, but during active development they add clutter. The design should consider consolidating the assumptions and decision manifests into a single file, or embedding them in the existing skill artifacts rather than creating parallel files.

---

## Additional observations

**The compact decision block is good.** The 3-line variant for simple decisions (Decision 1) is a reasonable format. The problem is that the tier classification and trigger conditions will push agents toward the full variant too often.

**The escalation path (Decision 3) is well-designed.** Lightweight to heavyweight via status="escalated" is clean and preserves work. This is one of the stronger parts of the design.

**Decision 10 (round limits) is practical.** Per-skill defaults with --max-rounds override is the right approach. This directly addresses a real pain point (infinite explore loops) without over-engineering.

**The self-validation approach worked.** Using the framework to make its own architectural decisions (Decisions 8-10) is a solid validation technique that surfaced real refinements. The design is stronger for it.
