# Lead 1: Design Skill Decomposition

How the design skill changes when approach selection delegates to the decision-making skill.

## Current Design Skill: Expansion-Contraction Pattern

The design skill runs 7 phases (0-6). The decision-relevant phases are:

### Phase 1: Approach Discovery (EXPAND)
- Brainstorms candidate approaches for the overall design question
- Quick-filters infeasible ones, clusters to cap at 5
- Launches parallel advocate agents, each arguing FOR one approach
- Each advocate writes to `wip/research/design_<topic>_phase1_advocate-<approach>.md`
- Advocates investigate strengths, weaknesses, deal-breaker risks, implementation complexity

### Phase 2: Present Approaches (CONVERGE)
- Reads all advocate reports, builds side-by-side comparison
- Recommends strongest approach, user approves or overrides
- Loop-back mechanism if user says "none of these"
- Writes Considered Options and Decision Outcome sections in the design doc

### Phase 3: Deep Investigation
- Research agents examine the chosen approach in depth (2-4 investigation areas)
- Surfaces decisions that emerge during investigation
- Records emergent decisions to Considered Options via AskUserQuestion
- Decision Review Checkpoint (step 3.4) catches unrecorded decisions

### Phase 4: Architecture
- Implicit Decision Review (step 4.4) catches decisions baked into prose
- Presents each implicit decision via AskUserQuestion, records to Considered Options

## Mapping to Decision Skill's 7 Phases

| Decision Skill Phase | Design Skill Current Equivalent | Coverage |
|---|---|---|
| 1. Problem Clarification & Research | Phase 1, step 1.1 (brainstorm candidates) + wip summary | Partial -- design skill doesn't have dedicated research agent for the decision question itself |
| 2. Alternative Identification | Phase 1, steps 1.1-1.3 (generate, filter, cluster) | Strong overlap -- same divergent-thinking step |
| 3. Solution Validation (Bakeoff) | Phase 1, step 1.4 (advocate agents) | Direct match -- advocates ARE solution validators |
| 4. Informed Peer Revision | Not present | Gap -- advocates never see each other's work |
| 5. Cross-Examination | Not present | Gap -- no adversarial dialogue between advocates |
| 6. Synthesis & Decision | Phase 2, steps 2.1-2.3 (comparison + recommendation + user approval) | Partial -- design skill does comparison but no formal synthesis step |
| 7. Decision Report | Phase 2, steps 2.4-2.5 (write Considered Options + Decision Outcome) | Strong overlap -- same output structure |

### Key Gaps in Current Design Skill
1. **No peer revision**: Advocates work in isolation. They never learn what other advocates found.
2. **No cross-examination**: There's no adversarial challenge between approaches. The orchestrator compares them, but the advocates don't defend or critique each other.
3. **No dedicated problem clarification**: Phase 1 jumps straight to brainstorming approaches without a research agent first building context on critical unknowns.

## What the Design Skill KEEPS vs DELEGATES

### KEEPS (Design-Doc-Specific Orchestration)

1. **Phase 0**: Setup, branch creation, PRD extraction, design doc skeleton. Purely design-doc workflow, nothing to do with decision-making.

2. **Decision question identification**: The design skill must identify WHICH decisions a design doc needs. Currently it treats the entire design as one big decision (which approach?). With the decision skill, it needs to decompose the problem into independent decision questions before delegating.

3. **Considered Options formatting**: The decision skill produces a Decision Report (Context, Decision, Rationale, Alternatives, Assumptions). The design skill must map that into the design doc's Considered Options format (Decision N: context / Chosen / Alternatives Considered). This is an adapter, not delegation.

4. **Decision Outcome synthesis**: After all decision questions are resolved, the design skill weaves individual decisions into a unified Decision Outcome narrative. The decision skill handles one decision at a time -- the design skill owns the "how do these fit together" synthesis.

5. **Phase 3: Deep Investigation**: Retained but narrowed (see below).

6. **Phase 4: Architecture synthesis**: Writing Solution Architecture, Implementation Approach, Consequences from investigation findings. No overlap with decision skill.

7. **Phase 5: Security review**: Domain-specific review, orthogonal to decision-making.

8. **Phase 6: Final review, strawman check, frontmatter, PR**: All design-doc lifecycle concerns.

9. **Implicit Decision Review (Phase 4, step 4.4)**: Detects decisions baked into prose. These are lightweight decisions that don't warrant the full 7-phase framework -- the design skill should keep a lightweight decision path for these.

### DELEGATES (To Decision Skill)

1. **Major design decisions**: The "which approach?" question currently handled by Phase 1 + Phase 2. Each decision question in Considered Options would invoke the decision skill independently.

2. **Advocate pattern**: The fan-out of advocate agents (Phase 1, step 1.4) maps directly to the decision skill's Phase 3 (Solution Validation / Design Bakeoff). The decision skill generalizes this.

3. **Approach comparison and recommendation**: Phase 2's side-by-side comparison maps to the decision skill's Phase 6 (Synthesis & Decision).

4. **Loop-back on "none of these"**: Currently Phase 2, step 2.3. The decision skill handles this via its own Phase 2 restart mechanism.

5. **Emergent decisions from Phase 3**: Currently handled ad-hoc (steps 3.3 item 4, 3.4). With the decision skill, emergent decisions that are non-trivial could be delegated to a lighter-weight decision run.

## Multi-Decision Design Docs (3-5 Decision Questions)

### Current Model: One Big Decision
The design skill currently treats the entire design as a single decision: "which overall approach?" Phase 1 fans out advocates for complete approaches. If the design involves 3 independent decisions (e.g., "storage backend?", "API style?", "deployment model?"), these are conflated into monolithic approaches that bundle all three choices.

This causes problems:
- Approach A might have the best storage answer but the worst API style
- Users can't mix-and-match across approaches
- If one sub-decision is obvious, it still gets entangled in the overall comparison

### New Model: Per-Question Decision Runs

With the decision skill:

1. **Phase 0 (setup)**: Same as today, plus a new step: **Decision Decomposition**. After building the design doc skeleton with Context and Decision Drivers, the design skill identifies independent decision questions. This requires understanding the problem well enough to know which choices are independent vs coupled.

2. **New Phase 1 (Decision Decomposition)**:
   - Analyze the problem statement and decision drivers
   - Identify 1-N independent decision questions
   - For each, define: the question, constraints, how it connects to other decisions
   - Present the decomposition to the user for approval
   - This replaces the current Phase 1 (Approach Discovery)

3. **New Phase 2 (Decision Execution)**:
   - For each decision question, invoke the decision skill
   - Independent decisions can run in parallel
   - Coupled decisions run sequentially (later decisions receive earlier results as context)
   - Each decision skill invocation writes results to `wip/research/design_<topic>_decision-<N>/`
   - This replaces the current Phase 2 (Present Approaches) and absorbs the decision-relevant parts of Phase 3

4. **New Phase 3 (Cross-Validation)**:
   - After all decisions complete, the design skill runs the cross-validation loop from the issue #6 spec
   - Each decider reviews peer decisions for assumption invalidation
   - If assumptions are invalidated, the affected decision reruns from the appropriate phase
   - This is orchestrated by the design skill, not the decision skill (per the spec: "orchestrated by the parent workflow")
   - Write unified Considered Options and Decision Outcome to the design doc

5. **Phase 4-6**: Largely unchanged (architecture, security, final review), but Phase 4's implicit decision review might trigger lightweight decision skill runs for decisions discovered during writing.

### Dependency Between Decisions

Not all decisions are independent. Examples:
- "Use SQLite or Postgres?" affects "How to handle migrations?"
- "Monolith or microservices?" affects "How to deploy?"

The design skill needs to model dependencies:
- Independent decisions: run in parallel
- Dependent decisions: run sequentially, feed prior results as context
- The decomposition step (new Phase 1) must identify these dependencies

## What Happens to Phase 3 (Deep Investigation)?

Phase 3 currently serves two purposes:

### Purpose 1: Validate the chosen approach in depth
This maps to the decision skill's Phase 3 (Solution Validation) + Phase 4 (Peer Revision) + Phase 5 (Cross-Examination). The decision skill does this MORE thoroughly (peer revision and cross-examination are new). So this purpose is **subsumed** by the decision skill.

### Purpose 2: Build implementation-level understanding for architecture writing
The decision skill's validators focus on "is this the right choice?" not "how exactly do we build this?" After a decision is made, the design skill still needs investigation focused on:
- Codebase integration specifics
- Edge cases in the chosen approach
- Dependencies and patterns
- Implementation details that affect Solution Architecture

This purpose is **retained**, but the scope narrows. It no longer needs to validate the approach (the decision skill did that). It focuses purely on "given this decision, what do we need to know to write the architecture?"

### Proposed Resolution
Keep a slimmed-down investigation phase between Decision Execution and Architecture:
- Reads decision skill outputs for the chosen approaches
- Identifies remaining unknowns specific to implementation (not decision validation)
- Runs 1-2 focused research agents
- Feeds results to Phase 4 (Architecture)

This becomes lighter because the decision skill's validators already did significant codebase investigation.

## New Phases / Steps Needed for Multi-Decision Orchestration

### 1. Decision Decomposition (replaces current Phase 1)
- Input: Design doc skeleton (Context, Decision Drivers)
- Process: Identify independent decision questions, model dependencies
- Output: Ordered list of decision questions with dependency graph
- User approval: Present decomposition for validation

### 2. Decision Execution (replaces current Phase 2)
- Input: Decision questions + dependency ordering
- Process: Invoke decision skill per question (parallel where independent)
- Output: Decision reports per question in wip/
- Adapter: Map decision reports to Considered Options format

### 3. Cross-Validation (new)
- Input: All completed decision reports
- Process: Each decider reviews peer decisions for assumption conflicts
- Output: Validated decisions (or restarted decisions if assumptions invalidated)
- Loop: May trigger re-execution of individual decisions

### 4. Decision Integration (new, or folded into architecture phase)
- Input: All validated decision reports
- Process: Write Considered Options, synthesize Decision Outcome, identify remaining implementation unknowns
- Output: Design doc with Considered Options + Decision Outcome, list of investigation topics

### 5. Lightweight Decision Path (new)
- For implicit decisions discovered in Phase 4 (architecture writing)
- These don't warrant the full 7-phase decision framework
- Options: (a) the design skill handles them directly (current approach with AskUserQuestion), (b) the decision skill has a "fast mode" that skips peer revision and cross-examination
- Recommendation: Keep these in the design skill. They're typically "we chose X because Y, the only real alternative was Z which we rejected because W." The decision skill's value is in deeply contested decisions, not obvious ones.

## Revised Phase Structure

```
Phase 0: SETUP (unchanged)
Phase 1: DECISION DECOMPOSITION (new, replaces Approach Discovery)
Phase 2: DECISION EXECUTION (delegates to decision skill per question)
Phase 3: CROSS-VALIDATION (new, multi-decision assumption checking)
Phase 4: INVESTIGATION (slimmed down, implementation-focused only)
Phase 5: ARCHITECTURE (was Phase 4)
Phase 6: SECURITY (was Phase 5, unchanged)
Phase 7: FINAL REVIEW (was Phase 6, strawman check uses decision reports)
```

This expands from 7 to 8 phases, but the new phases (1, 2, 3) replace the old phases (1, 2) and slim down the old Phase 3, so net complexity is managed. The decision skill absorbs the most complex part (multi-agent advocate pattern with the addition of peer revision and cross-examination).

## Resumability Impact

The current resume logic checks for wip/ artifacts to determine which phase to resume at. With per-question decision runs:

- Each decision question gets its own subdirectory: `wip/research/design_<topic>_decision-<N>/`
- The decision skill manages its own resumability within that directory
- The design skill's resume logic checks: are all decision questions complete? If not, resume at Phase 2 for the incomplete ones
- Cross-validation results need their own marker file

New resume chain:
```
All decisions have cross-validation markers     -> Resume at Phase 4 (Investigation)
All decision questions have reports             -> Resume at Phase 3 (Cross-Validation)
Some decision questions have reports            -> Resume at Phase 2 (continue remaining)
Decision decomposition exists                   -> Resume at Phase 2
Design doc skeleton exists                      -> Resume at Phase 1
```

## Summary

The design skill's Phase 1-2 (advocate fan-out, approach comparison) maps almost entirely to the decision skill's Phases 1-6, with two notable additions: peer revision (Phase 4) and cross-examination (Phase 5) that the design skill currently lacks. The design skill retains orchestration concerns: decision decomposition, multi-decision execution, cross-validation, format adaptation, and all post-decision phases (investigation, architecture, security, review). A design doc with 3-5 decision questions would decompose into independent decision runs, execute them in parallel where possible, then cross-validate to check for assumption conflicts. The current Phase 3 (deep investigation) splits: its validation purpose is subsumed by the decision skill's bakeoff, while its implementation-research purpose is retained in a slimmer form. The design skill gains three new responsibilities: decision decomposition, cross-validation orchestration, and a lightweight decision path for implicit decisions discovered during architecture writing.
