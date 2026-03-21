# Decision Cluster B: Invocation, Cross-Validation, and Phase Structure

Three coupled decisions for the decision framework's integration with the design
skill. These were evaluated together because the invocation model constrains
cross-validation behavior, and both shape the phase count.

## Analysis

### Decision 4 Context: Invocation Model

The research identifies four invocation patterns in shirabe (shell script, parallel
agent, skill reading, slash command delegation). Only two are viable for the
decision skill: Task agents (Pattern B) and inline skill reading (Pattern C).

**Agent viability for multi-phase skills.** The plan Phase 4 pattern proves that
agents can follow detailed multi-step prompts -- agent-prompt.md is 220 lines
and agents successfully produce validated output files. However, plan agents run
a single-concern task (generate one issue body), not a 7-phase workflow with
resume logic and intermediate artifacts. A decision agent would need to:
1. Read the decision SKILL.md and relevant phase files
2. Execute 4-7 phases sequentially
3. Write intermediate artifacts to wip/
4. Handle its own resume if spawned to replace a failed predecessor

This is more complex than plan's agents, but still feasible. The agent receives a
self-contained prompt with all phase instructions inlined (not loaded from files).
The parent pre-compiles the decision skill's phases into a single prompt. This
avoids the agent needing to navigate file references. Token cost is high (~3-5K
tokens for the compiled prompt per decision) but acceptable given that the
alternative -- sequential execution of N decisions inline -- has even higher token
cost from context window pollution.

**Hybrid evaluation.** The hybrid approach (agents for parallel, inline for single)
adds a branch in every parent skill that invokes the decision skill. The parent
must check: "am I running one decision or many?" and dispatch differently. This
is manageable complexity -- the design skill knows it has multiple decisions,
explore knows it has one.

The real question is whether hybrid is worth it over always-agent. For single
decisions, inline saves the serialization overhead and keeps the parent's context
available. For a skill like explore that already has full context loaded, reading
the decision SKILL.md inline avoids duplicating that context into an agent prompt.
The cost: the decision phases pollute explore's context window. Given explore
already runs 5+ phases, adding 4-7 decision phases inline is a real concern.

**Always-agent alternative.** Using agents even for single decisions simplifies the
invocation contract: every parent always spawns a Task agent. The overhead for a
single decision is one agent with a compiled prompt. The parent just waits for the
report file. Simpler code, one path to test, one contract to maintain.

The downside: for a single simple decision, an agent spawn adds latency and loses
the parent's context. But the decision skill's input contract already handles this
-- the parent passes all relevant context in the `background` field.

**Verdict.** The hybrid approach is practical but the complexity cost doesn't
justify the gain for single decisions. The difference between inline and agent for
a single decision is minor (slightly faster inline, slightly cleaner agent). Use
agents universally for a simpler contract. This can be revisited if inline proves
necessary for specific cases.

Wait -- reconsider. The research from lead-sub-operation explicitly recommends
hybrid and makes a strong argument: explore's single-decision case already has all
context loaded and doesn't benefit from agent overhead. The inline path for single
decisions is genuinely simpler for the calling skill. And the two paths are
well-separated: design always uses agents (multiple decisions), explore always
uses inline (single decision). No skill needs to dynamically choose.

Revised verdict: hybrid, but with static dispatch. Each parent skill knows at
design time whether it uses agent or inline. No runtime branching.

### Decision 5 Context: Cross-Validation Loop Termination

Three options on the table. The system runs non-interactive (per the --auto mode
research), so "escalate to user if conflicts persist" doesn't work as a primary
strategy.

**Fixed round limit (max 2).** The multi-decision research recommends this
directly: "max 2 cross-validation rounds. After 2 rounds, escalate to the user
with the remaining conflicts for manual resolution." But escalation contradicts
non-interactive mode.

In non-interactive mode, after 2 rounds, the system needs to do something other
than ask the user. Options: (a) pick the least-conflicting combination and record
the unresolved conflict as an assumption, (b) merge the decisions as-is and flag
the conflict in the design doc's Considered Options section, (c) fail the
workflow.

Option (a) is the most aligned with the --auto mode pattern. The non-interactive
research shows that every decision point gets auto-selected with the agent's
recommendation, and assumptions are recorded. An unresolved cross-validation
conflict is just another assumption: "These two decisions may conflict; the agent
proceeded with both choices as-is."

**Convergence detection.** Theoretically cleaner but hard to implement correctly.
"No new conflicts found" requires comparing the current round's conflicts against
the previous round's. If Decision 2 was restarted and now conflicts with Decision
3 (which didn't conflict before), that's a new conflict -- but detecting this
requires tracking conflict identity across rounds. Overengineered for the initial
implementation.

**Single pass with escalation.** Works in interactive mode, contradicts
non-interactive. But interesting as a simplification: what if cross-validation is
always single-pass? One round of checking, conflicts flagged, affected decisions
restarted once, and then done. No loop at all.

The risk of single-pass: a restarted decision might introduce a new conflict with
a third decision. But the probability is low -- restarts receive the conflicting
decision's output as an additional constraint, which should steer away from new
conflicts. And if it happens, the conflict surfaces in the design doc as a noted
tension.

Single-pass is simpler than a bounded loop and handles the non-interactive case
cleanly: one restart, then proceed with assumptions for any remaining conflicts.

### Decision 6 Context: Design Skill Phase Restructuring

The current design skill has 7 phases (0-6). The proposed restructuring adds
Decision Decomposition (new 1), Decision Execution (new 2), and Cross-Validation
(new 3), while removing the current Phase 1 (Approach Discovery) and Phase 2
(Present Approaches), and slimming Phase 3 (Deep Investigation).

**Phase count evaluation.** The proposed 8 phases (0-7):

```
0: SETUP (unchanged)
1: DECISION DECOMPOSITION (new)
2: DECISION EXECUTION (new, delegates to decision skill)
3: CROSS-VALIDATION (new)
4: INVESTIGATION (slimmed Phase 3)
5: ARCHITECTURE (was Phase 4)
6: SECURITY (was Phase 5)
7: FINAL REVIEW (was Phase 6)
```

The phase-discipline research says the complexity budget breaks at 20+ phase files
loaded in one session. The design skill's 8 phases plus 7 decision skill phases
(loaded per-decision via agents) = 15 in the worst case, within budget.

But should cross-validation be its own phase? It runs after Decision Execution
and before Investigation. It reads all decision outputs, checks assumptions,
and triggers restarts. If restarts happen, it loops back to Phase 2 for the
affected decisions. This is a coordination step, not a content-producing step --
it doesn't write design doc sections.

**Cross-validation as sub-phase of Decision Execution.** If cross-validation is
Phase 2b rather than Phase 3, the phase count drops to 7 (matching current).
Phase 2 becomes: (a) spawn decision agents, (b) collect results, (c) validate
assumptions cross-decision, (d) restart if needed. This makes Phase 2 heavier
but keeps it as a single "make all decisions" phase.

The problem: the phase file for Phase 2 would be large. It already contains agent
spawning, result collection, validation, retry, and manifest compilation (similar
to plan Phase 4 at 437 lines). Adding cross-validation logic pushes it well past
300 lines.

**Cross-validation as separate phase.** Keeps Phase 2 focused on execution and
Phase 3 focused on validation. Two clean files under 150 lines each. But adds a
phase number, and the resume logic gets an extra check point.

The phase-discipline research explicitly recommends separate phase files for
separate concerns and notes that plan's Phase 4 is already the largest outlier
at 437 lines. Don't repeat that pattern.

**The lightweight decision path.** The research recommends keeping implicit
decisions (discovered during architecture writing in what becomes Phase 5) in the
design skill rather than delegating to the decision skill. These are simple
"we chose X because Y" decisions that don't warrant the full framework. This
means Phase 5 (Architecture) retains its step 4.4 (Implicit Decision Review)
using the existing inline pattern. No change needed here.

**Verdict on phase count.** 8 phases is correct. Cross-validation earns its own
phase because: (1) it's a distinct concern from decision execution, (2) combining
them would create another 400+ line file, (3) the resume logic benefit of a
separate checkpoint is real -- if the session breaks during cross-validation, you
don't have to re-run all decision agents.

---

## Decisions

<!-- decision:start id="d4-invocation-model" -->
### Decision: Multi-decision invocation model

**Question:** How should parent skills invoke the decision skill -- task agents per decision (parallel), sequential inline execution (read SKILL.md), or hybrid?

**Evidence:**
- Plan Phase 4 proves parallel Task agents work for self-contained prompts (437-line phase file, validated output artifacts, retry/fallback logic). Agents handle 220-line prompt templates successfully.
- The sub-operation research (lead-sub-operation) shows two viable patterns: agents for multi-decision (design skill) and inline for single-decision (explore skill). Each parent skill knows its invocation mode at design time -- no runtime branching needed.
- Agent spawning for a full multi-phase skill is more complex than plan's single-concern agents, but feasible if the parent pre-compiles phase instructions into a single prompt. The decision skill's input/output contract (question + context in, report + assumptions out) is clean enough for agent serialization.
- Inline execution for explore's single-decision case avoids context duplication overhead and keeps the parent's rich context available to the decision phases.

**Choice:** Hybrid with static dispatch. Design skill always uses Task agents (one per decision question, spawned in parallel). Explore skill always uses inline execution (reads decision SKILL.md and follows phases in its own context). Each parent skill hardcodes its invocation mode -- no runtime detection or branching. The decision skill's interface is the same for both modes: structured input (question, constraints, background), structured output (choice, rationale, assumptions, report file).

**Alternatives considered:**
- *Always-agent*: Simpler single contract, but wastes overhead for explore's single-decision case and loses explore's pre-loaded context. The simplicity gain doesn't justify the context duplication cost.
- *Always-inline*: Can't parallelize multiple decisions. Design skill with 3-5 decisions would run them sequentially, multiplying wall-clock time by N.
- *Dynamic hybrid*: Parent chooses at runtime based on decision count. Adds branching complexity for no benefit since each parent skill's usage pattern is known at design time.

**Assumptions:**
- The decision skill can be compiled into a single self-contained prompt for agent invocation (no file references that the agent would need to resolve).
- Each parent skill's decision count pattern is stable: design always has multiple decisions, explore always has one.
- The compiled prompt for agent mode stays under 5K tokens, keeping total agent cost manageable for 3-5 parallel decisions.
<!-- decision:end -->

<!-- decision:start id="d5-cross-validation-termination" -->
### Decision: Cross-validation loop termination strategy

**Question:** How should the cross-validation loop terminate when checking for assumption conflicts across parallel decisions?

**Evidence:**
- The multi-decision research (lead-multi-decision) recommends max 2 rounds with user escalation on persistent conflicts. But the non-interactive research (lead-non-interactive) shows the system must support `--auto` mode where user escalation isn't available.
- Cross-validation conflicts occur when Decision A's assumptions are invalidated by Decision B's choice. Restarting Decision A with updated constraints should resolve the conflict in most cases -- the restarted decision receives the peer's outcome as a constraint.
- Oscillation (A invalidates B, B's restart invalidates A) is theoretically possible but unlikely when restarts incorporate peer constraints. The restarted decision is explicitly constrained by the conflicting peer's outcome.
- The --auto mode pattern handles unresolvable situations by recording assumptions: "proceeded despite potential conflict" is a valid assumption record with an "if wrong" remediation path.

**Choice:** Single pass with bounded restart. Cross-validation runs once after all decisions complete. Conflicting decisions are restarted once with peer constraints injected. After the restart round, any remaining conflicts are accepted and recorded as assumptions in the assumptions file (approach-level, with "if wrong: re-run design from Phase 2 with manual conflict resolution" remediation). No second cross-validation round. In interactive mode, remaining conflicts are presented to the user for confirmation rather than auto-accepted.

**Alternatives considered:**
- *Fixed 2-round limit*: More thorough but adds complexity (must track cross-validation round number, coordinate which decisions to restart in round 2, handle the "what if round 2 finds new conflicts" question). The marginal benefit of a second round is low if the first restart properly constrains decisions.
- *Convergence detection*: Requires comparing conflict identity across rounds, tracking which conflicts are new vs recurring. Overengineered for the expected frequency of multi-round conflicts. Could be added later if single-pass proves insufficient.
- *Always escalate*: Contradicts non-interactive mode. Works for interactive-only but limits the decision framework's use in automated pipelines.

**Assumptions:**
- Restarting a decision with peer constraints as additional input is sufficient to resolve most conflicts in one pass.
- Oscillating conflicts (A breaks B, B breaks A) are rare enough that recording them as assumptions rather than resolving them is acceptable.
- The assumptions file infrastructure from the --auto mode design is available when the decision framework ships.
<!-- decision:end -->

<!-- decision:start id="d6-design-phase-restructuring" -->
### Decision: Design skill phase restructuring

**Question:** Should the design skill expand from 7 phases (0-6) to 8 phases (0-7), and should cross-validation be a standalone phase or a sub-phase of decision execution?

**Evidence:**
- The design-decomposition research (lead-design-decomposition) proposes 8 phases: Setup, Decision Decomposition, Decision Execution, Cross-Validation, Investigation (slimmed), Architecture, Security, Final Review. This replaces Phase 1 (Approach Discovery) and Phase 2 (Present Approaches) with three new phases while slimming Phase 3.
- The phase-discipline research (lead-phase-discipline) shows plan Phase 4 (agent generation) is already the largest outlier at 437 lines. Combining decision execution and cross-validation into one phase would create a similarly oversized file.
- The 150-line target is met by 58% of current phase files. Cross-validation as its own file should be ~80-120 lines (read reports, compare assumptions, flag conflicts, trigger restarts). Decision execution as its own file should be ~150-180 lines (spawn agents, collect results, validate, compile manifest).
- The complexity budget breaks at 20+ phase files loaded per session. Design's 8 phases plus decision skill's 7 phases (loaded via agents, not in parent context) = 15 maximum, within budget.
- The research recommends keeping implicit decisions (discovered during Phase 5 architecture writing) in the design skill using the existing lightweight inline pattern, not delegating them to the decision skill.

**Choice:** 8 phases (0-7), with cross-validation as its own phase (Phase 3). The full structure:

```
Phase 0: SETUP (unchanged)
Phase 1: DECISION DECOMPOSITION (new -- replaces Approach Discovery)
Phase 2: DECISION EXECUTION (new -- delegates to decision skill per question)
Phase 3: CROSS-VALIDATION (new -- single-pass assumption checking across decisions)
Phase 4: INVESTIGATION (slimmed -- implementation-focused research only, no approach validation)
Phase 5: ARCHITECTURE (was Phase 4, retains implicit decision review at step 5.4)
Phase 6: SECURITY (was Phase 5, unchanged)
Phase 7: FINAL REVIEW (was Phase 6, strawman check references decision reports)
```

Implicit decisions discovered during Phase 5 are handled inline by the design skill using the existing AskUserQuestion pattern (or auto-selected in --auto mode). They don't invoke the decision skill.

**Alternatives considered:**
- *7 phases (cross-validation as sub-phase of execution)*: Keeps phase count stable but creates a 300+ line Phase 2 file combining agent orchestration, result collection, and cross-validation logic. Violates the lesson from plan Phase 4's size.
- *9 phases (separate Decision Integration phase)*: The research proposes a Decision Integration step between cross-validation and investigation. But integration (writing Considered Options, synthesizing Decision Outcome) can be the final step of cross-validation or the first step of investigation. Doesn't need its own phase.
- *Keep 7 phases, delegate decisions within existing Phase 1-2 structure*: Forces decision decomposition, execution, and validation into two phases that were designed for a single-decision model. Awkward fit, unclear resume points.

**Assumptions:**
- The decision skill absorbs the advocate pattern's complexity, so the design skill's new Phase 2 is primarily orchestration (spawn, collect, validate) rather than content generation.
- Slimming Investigation (Phase 4) compensates for the added phases. Investigation no longer validates the approach (the decision skill did that) -- it only researches implementation specifics.
- The resume logic chain for 8 phases is straightforward: each phase produces a distinct artifact that the next phase checks for.
<!-- decision:end -->
