# Round 3 Architecture Review: DESIGN-decision-framework.md

Reviewer focus: agent hierarchy viability, internal consistency, completeness, implementability.

---

## 1. Agent Hierarchy Viability (D8)

### SendMessage persistence pattern -- platform risk

D8 describes validators spawned in Phase 3 that receive follow-up messages via `SendMessage` in Phases 4 and 5. This is the critical architectural bet in the design. Three concerns:

**1a. No documented timeout/keepalive contract.** Claude Code's Agent tool spawns sub-agents, and `SendMessage` continues a conversation with a running agent. The design assumes validators stay alive across three phases while the decider orchestrates sequentially. If a validator's process is garbage-collected between phases (Claude Code doesn't document agent lifetime guarantees), Phase 4's `SendMessage` fails silently or errors.

**Recommendation:** The design should specify a fallback for validator loss. Options: (a) treat validator loss as equivalent to validator concession (drop that alternative), or (b) re-spawn with prior conversation context injected as a prompt preamble. Either is acceptable -- the gap is that neither is specified.

**1b. Agent count scaling.** For a Tier 4 decision with 4 alternatives, the decider spawns 4 validator agents in Phase 3. A design doc with 3 Tier 4 decisions (the design's own example range) means 3 deciders x 4 validators = 12 concurrent agents plus the orchestrator. That is 13 agents. Claude Code likely has practical concurrency limits. The plan skill's Phase 4 already uses parallel agents for issue generation, so the pattern works at some scale -- but the plan skill spawns disposable agents, not persistent ones.

**Recommendation:** Add a note about maximum concurrent validator count per decider (cap at 4-5 alternatives is already implied by the design skill's existing cap of 5 approaches, but this should be explicit in the decision skill's phase files). Also note that design skill Phase 2 runs decisions in parallel, but each decider's validators are internal to that decider -- the orchestrator doesn't see 12 agents, each decider manages its own 3-4.

**1c. Fast path mitigates most risk.** The design correctly notes that Tier 3 (standard) decisions skip Phases 3-5 entirely, meaning no persistent agents. Only Tier 4 (critical) decisions use the full pattern. If most design doc decisions are Tier 3, the persistent agent pattern is exercised rarely. This is a sound architectural choice -- but the design should state the expected Tier 3:Tier 4 ratio for a typical design doc to make the risk profile explicit.

### Verdict: viable with specified fallbacks

The pattern is sound in principle. The risk is that Claude Code's agent lifetime isn't contractually guaranteed for the multi-phase SendMessage pattern. The fast-path escape valve limits exposure. Two additions needed: validator-loss fallback and expected tier ratio.

---

## 2. Internal Consistency

### 2a. Phase numbering between D6 and Component 4

D6 specifies 8 phases (0-7):
```
Phase 0: SETUP
Phase 1: DECISION DECOMPOSITION
Phase 2: DECISION EXECUTION
Phase 3: CROSS-VALIDATION
Phase 4: INVESTIGATION
Phase 5: ARCHITECTURE
Phase 6: SECURITY
Phase 7: FINAL REVIEW
```

Component 4 (Solution Architecture) repeats the same mapping. Consistent.

The existing design SKILL.md has 7 phases (0-6) with different names (EXPAND, CONVERGE, INVESTIGATE, etc.). The mapping from old to new is implied but never made explicit. Implementation Phase 3 says "Rewrite design Phases 1-3" but the old skill has Phases 1-3 as EXPAND, CONVERGE, INVESTIGATE. The new Phases 1-3 are DECISION DECOMPOSITION, DECISION EXECUTION, CROSS-VALIDATION. This is a complete replacement, not a rewrite -- the language should be precise.

**Impact: low.** An implementer reading both the design doc and the existing SKILL.md would figure this out, but "rewrite" understates the scope. The phase file names also need to change entirely (e.g., `phase-1-approach-discovery.md` becomes `phase-1-decomposition.md`). Implementation Phase 3 deliverables list the new names, so this is handled -- just the prose is imprecise.

### 2b. D2 assumption file vs D14 consolidated file

D2 says assumptions live in `wip/<workflow>_<topic>_assumptions.md`. D14 consolidates this into `wip/<workflow>_<topic>_decisions.md`. Component 2 and Component 3 both reference the consolidated file from D14. But D2's "Chosen" section still names `_assumptions.md` as the source of truth.

**Impact: medium.** An implementer reading D2 in isolation would create a separate assumptions file. D14 supersedes D2's file naming, but D2 doesn't acknowledge this. Add a forward reference in D2: "Note: D14 consolidates this into a single decisions file; the `_assumptions.md` name is superseded."

### 2c. Decision skill phase count: "7 phases" vs actual phases 0-6

The design consistently says "7 phases" and lists phases 0 through 6. This is correct (7 phases, 0-indexed). No inconsistency.

### 2d. D4 says "Task agents" but the plan skill uses `run_in_background`

D4 references "the proven plan Phase 4 pattern: fan-out with `run_in_background`, collect via TaskOutput." The plan skill's Phase 4 confirms this pattern. However, the design calls them "Task agents" which could be confused with the `Task` tool. The plan skill uses Agent tool calls with `run_in_background`. This is a naming ambiguity, not a contradiction.

**Impact: low.** Clarify in D4 or Component 1 that "Task agent" means "Agent tool invocation with run_in_background", not a separate tool.

### 2e. Component 5 references "phase-5-produce-decision.md"

The explore skill currently has `phase-5-produce.md`, `phase-5-produce-design.md`, `phase-5-produce-prd.md`, `phase-5-produce-plan.md`, `phase-5-produce-no-artifact.md`, and `phase-5-produce-deferred.md`. Adding `phase-5-produce-decision.md` follows the established pattern. The crystallize framework currently lists "Decision Record" as a deferred type (line 82). Component 5 says to move it to supported types. Consistent.

---

## 3. Completeness Gaps

### 3a. Input contract format is YAML but delivery mechanism is unspecified

Component 1 defines `decision_context` and `decision_result` as YAML structures. But how does the parent actually pass this to the decider agent? The Agent tool takes a text prompt, not structured YAML. The design says the parent provides "the decision context (question, options, constraints, background)" -- but doesn't specify whether this is:
- Embedded in the agent prompt as a YAML block
- Written to a file the agent reads
- Some other mechanism

**Recommendation:** Specify that the parent writes `decision_context` as a YAML block in the agent prompt string (the simplest approach, consistent with how plan Phase 4 passes issue context).

### 3b. Output contract delivery mechanism also unspecified

The `decision_result` YAML includes `report_file`. The decider presumably writes the report file and... returns the YAML as its final message? Writes it to a coordination file? The plan skill writes to `wip/` files and the orchestrator reads them. The decision skill should do the same, but this needs to be stated.

**Recommendation:** Specify that the decider writes both the report file (`wip/<prefix>_report.md`) and a result file (`wip/<prefix>_result.yaml`) that the orchestrator reads after collecting the agent. Or specify that the report file's YAML frontmatter contains the result fields.

### 3c. coordination.json format undefined

Component 4 lists `wip/design_<topic>_coordination.json` as a new artifact. Implementation Phase 3 lists it as a deliverable. But nowhere does the design specify what this file contains. The plan skill has `wip/plan_<topic>_decomposition.md` with YAML frontmatter that serves a similar coordination role. The design should specify the coordination manifest's schema -- at minimum: list of decision questions, their assigned prefixes, completion status, and tier.

**Recommendation:** Add a schema sketch to Component 4 or Implementation Phase 3.

### 3d. Resume logic not addressed

The existing design skill SKILL.md has detailed resume logic (lines 160-171). The new 8-phase design doesn't describe how resume works with the new phases. If the agent crashes mid-Phase 2 (decision execution) with 2 of 5 decisions complete, what happens on resume? The coordination manifest would need to track per-decision completion status.

**Recommendation:** Add resume logic to Component 4 or note it as an implementation detail for the phase files.

### 3e. Decision report format specification location

D11 says the format spec includes consumer rendering sections. Implementation Phase 2 lists "Decision report format specification" as a deliverable. But Implementation Phase 1a also lists "Decision report format specification with consumer rendering sections." Same deliverable appears in two phases.

**Impact: medium.** An implementer would build the format spec in Phase 1a, then the same spec appears as a Phase 2 deliverable. Either remove it from Phase 2 or clarify that Phase 1a creates the spec and Phase 2 implements skill code that uses it.

---

## 4. Implementability Assessment

### Could you build this from the design doc alone?

**Yes, with the gaps noted above filled.** The design is structurally complete for the major flows. The 14 decisions are well-reasoned and the components map clearly to implementation work. Specific places where an implementer would get stuck:

1. **coordination.json schema** (gap 3c) -- would need to invent the format
2. **Agent I/O mechanism** (gaps 3a, 3b) -- would need to decide how context enters and results exit the agent boundary
3. **Validator loss handling** (issue 1a) -- would need to make an ad-hoc decision during implementation
4. **Resume logic for new phases** (gap 3d) -- would need to design resume from scratch

None of these are architectural -- they're specification gaps that an implementer could fill without contradicting the design. But filling them during implementation risks inconsistency across the 4 implementation phases.

### Implementation phase ordering is sound

Phase 1a (protocol specs) before Phase 1b (integration) before Phase 2 (decision skill) is the right order. The shared protocol must be stable before skills reference it, and the lightweight protocol should be integrated before the heavyweight skill is built on top of it.

Phase 3 (design restructuring) depending on Phase 2 (decision skill) is correct -- the design skill delegates to the decision skill.

Phase 4 (explore integration) is correctly last -- it's additive and lower-risk.

---

## Summary of Findings

| # | Severity | Category | Issue |
|---|----------|----------|-------|
| 1a | Medium | Viability | Validator-loss fallback unspecified for SendMessage pattern |
| 1b | Low | Viability | Concurrent agent count not explicitly bounded |
| 1c | Low | Viability | Expected Tier 3:Tier 4 ratio not stated |
| 2b | Medium | Consistency | D2 still names `_assumptions.md`; D14 supersedes to `_decisions.md` |
| 2d | Low | Consistency | "Task agent" naming ambiguous with Task tool |
| 3a | Medium | Completeness | Input contract delivery mechanism (prompt vs file) unspecified |
| 3b | Medium | Completeness | Output contract delivery mechanism unspecified |
| 3c | Medium | Completeness | coordination.json schema undefined |
| 3d | Medium | Completeness | Resume logic for new 8-phase design not addressed |
| 3e | Low | Completeness | Decision report format spec appears in both Phase 1a and Phase 2 deliverables |

No blocking issues. Five medium-severity gaps that should be addressed before implementation to prevent ad-hoc decisions diverging across phases. The agent hierarchy design is viable given the fast-path escape valve, but needs a stated fallback for the validator persistence assumption.
