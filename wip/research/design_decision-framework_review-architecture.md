# Architecture Review: DESIGN-decision-framework.md

Reviewer focus: structural fit within Claude Code's agent model, composition
patterns, and implementation viability. Reviewed against existing design, explore,
and plan skill implementations.

---

## Issue 1 (Critical): Compiled Agent Prompts Are a Sync Liability, Not a Proven Pattern

The design claims the "compile phases into prompt" approach is "proven viable by
plan Phase 4's 220-line agent prompts." This comparison is misleading.

**Plan Phase 4 agents do one thing.** Each agent receives a single issue outline
plus the design doc and produces one file. The agent prompt template
(`skills/plan/references/templates/agent-prompt.md`) is 221 lines -- but it
describes a single task with a single output contract. There is no sequencing,
no intermediate artifacts, no conditional branching, and no resume logic.

**Decision skill agents must execute 4-7 sequential phases.** Even the fast path
(phases 0, 1, 2, 6) requires the agent to: frame the question, research the
codebase, generate alternatives with evidence, then synthesize a structured
report. The full path adds adversarial bakeoff, peer revision, and cross-
examination. Each phase produces intermediate reasoning that feeds the next.

The design says each phase compresses to 25-40 lines in the compiled template,
putting the full template at 175-280 lines of instructions plus context. That's
comparable to plan's agent prompt in token count -- but structurally different.
Plan agents execute a flat task. Decision agents execute a sequential workflow
with state accumulation.

**Failure mode:** Claude Code agents don't have persistent state between steps
within a single prompt. The agent must hold all intermediate reasoning in its
generation context. By phase 6 (synthesis), the agent needs to reference:
- The framed question (phase 0)
- Research findings (phase 1)
- All generated alternatives with evidence (phase 2)
- Bakeoff results, if full path (phase 3)
- Revision notes (phase 4)
- Cross-examination findings (phase 5)

This isn't a token limit problem -- it's an attention and instruction-following
problem. LLMs degrade on multi-step sequential instructions embedded in a single
prompt, especially when later steps reference outputs of earlier steps that exist
only in the model's own generation. Plan Phase 4 avoids this entirely because
each agent does exactly one thing.

**The maintenance burden is also real.** The design proposes a monolithic template
at `references/templates/agent-prompt.md` with `{{PLACEHOLDER}}` variables.
Every time a decision skill phase file is updated, someone must manually update
the compiled template. The plan skill doesn't have this problem because its agent
prompt is the authoritative source -- there's no separate phase file that it
derives from. The decision skill has both phase files (for inline execution by
explore) AND a compiled template (for agent execution by design). Two sources of
truth for the same workflow logic.

**Recommendation:** Don't compile phases into a single prompt. Instead, have the
decision agent write intermediate artifacts to wip/ files (like every other
multi-phase workflow), with the design skill's Phase 2 orchestrating them via
sequential agent spawns or a single agent that reads its own prior outputs from
disk. Alternatively, accept that decision agents will be less reliable than plan
agents and build aggressive retry/fallback logic from day one.

---

## Issue 2 (Critical): wip/ Artifact Lifecycle Has a Cross-Validation Gap

The design specifies cleanup after each decision completes (implied by the
coordination manifest tracking per-decision status). But cross-validation
(Phase 3) needs to read ALL decision reports and their assumptions to check
for conflicts.

The timeline looks like this:
1. Phase 2: spawn 3-5 decision agents in parallel
2. Each agent writes `wip/design_<topic>_decision_<N>_report.md`
3. Phase 3: cross-validation reads all reports, checks assumptions
4. Cross-validation flags conflicts, restarts conflicting decisions
5. Restarted decisions write updated reports
6. Cross-validation accepts remaining conflicts as assumptions

**The design never specifies when intermediate decision artifacts get cleaned.**
The "cleanup" mention is in Phase 7 of the plan skill (line 295 of plan SKILL.md),
not in the design skill's proposed phase structure. If decision agents produce
intermediate wip/ files during their 4-7 phase execution (research notes,
alternative lists, bakeoff results), those files accumulate across all parallel
decisions.

For a design doc with 5 decisions, each running the full 7-phase path, the wip/
directory could contain:
- 5 x report files
- 5 x intermediate research files
- 5 x alternative analysis files
- 5 x bakeoff result files (full path only)
- 1 coordination manifest
- 1 assumptions file
- 1 cross-validation result

That's 16-26 files for the decision framework alone, on top of the design skill's
own artifacts. The design doc's wip/ naming convention
(`wip/design_<topic>_decision_<N>_*`) provides namespace separation, but the
volume creates practical problems:
- Resume logic must parse through all of them
- Git commits during the workflow touch dozens of files
- Context window pressure from reading artifacts during cross-validation

**More critically:** if a decision is restarted during cross-validation (Decision 5's
bounded restart), the old report must be preserved for comparison with the new
one. The design says "restart conflicting decisions once with peer constraints
injected" but doesn't specify whether the old report is overwritten or versioned.
If overwritten, the cross-validation phase loses the ability to explain what
changed. If versioned, add another 1-3 files.

**Recommendation:** Define the full artifact lifecycle explicitly in the design.
Specify: (a) which intermediate artifacts decision agents produce, (b) whether
they persist after the agent completes or are summarized into the report,
(c) whether restarted decisions overwrite or version their reports, and
(d) when the bulk cleanup runs relative to cross-validation completion.

---

## Issue 3 (High): prd Skill Is Unaddressed and Breaks the Static Dispatch Model

The design claims "each parent knows at development time which mode to use"
(Decision 4). It specifies:
- Design always uses Task agents (parallel)
- Explore always uses inline (single decision)

**prd is never mentioned.** The design says prd "switches to research-first
pattern" (Component 6, line 466), which covers the lightweight decision protocol.
But prd already has contested decisions that would benefit from the heavyweight
skill:
- Requirements prioritization (which features are must-have vs. nice-to-have)
- Scope boundaries (what's in vs. out of the PRD)
- The jury review pattern (prd's existing mechanism for contested requirements)

If prd's jury review involves a contested requirement where stakeholder needs
conflict, that's exactly the kind of Tier 3/4 decision the framework is designed
for. But the design doesn't address whether prd invokes the decision skill inline
or via agents.

**The static dispatch model breaks here.** prd might have 0 heavyweight decisions
(most PRDs) or 2-3 (contested requirements PRD). The count isn't known at
development time -- it depends on the input. This is precisely the "dynamic
dispatch" case that Decision 4 rejected as adding "branching complexity for
minimal gain."

The design also doesn't address how prd's existing jury review pattern interacts
with the decision skill. Does the jury review become a decision skill invocation?
Does it stay separate? If separate, there are two mechanisms for adversarial
evaluation in the system -- the decision skill's bakeoff and prd's jury review --
with no clear guidance on when to use which.

**Recommendation:** Either explicitly scope prd out of heavyweight decision
support (with rationale), or add prd to the static dispatch table with its own
invocation mode. If prd gets heavyweight support, address the jury review
overlap -- the cleanest path is probably to reimplement jury review as a decision
skill invocation, which unifies the adversarial evaluation pattern.

---

## Additional Findings

### Context Window Math (Asked but Not Critical)

Design Phase 2 would have in the conversation:
- Design SKILL.md: ~235 lines (~3.5K tokens)
- Phase 2 file: ~150 lines (~2.2K tokens)
- Coordination manifest: ~50 lines
- Conversation history from phases 0-1: ~2-4K tokens

The decision agents run in separate contexts, so their prompts (3-4K tokens each)
don't compete with the orchestrator's context. The orchestrator only sees the
structured summaries returned by agents (similar to plan Phase 4's pattern of
writing to files and returning summaries).

**This actually works.** The design correctly follows plan's pattern of offloading
heavy work to agents and keeping the orchestrator lightweight. Context pressure
is manageable as long as the orchestrator doesn't read full decision reports into
its own context -- it should read them only during cross-validation (Phase 3),
which is a bounded operation.

The concern is more about cross-validation reading 3-5 full decision reports
(each potentially 200-400 lines) into the orchestrator's context at once. That's
1-2K lines of content on top of the accumulated conversation. Tight but feasible
if the conversation history is managed well.

### Tier Classification Is Underspecified

The design defines four tiers (trivial, lightweight, standard, critical) but
doesn't give the agent clear classification criteria. "Tier 2" decisions trigger
the lightweight protocol; "Tier 3+" triggers the heavyweight skill. But the
boundary between Tier 2 and Tier 3 is described only as complexity requiring
"deeper evaluation" (Decision 3, step 2 of lightweight protocol).

In practice, agents will default to the path described in more detail. If the
lightweight protocol is simpler to follow, most decisions will stay lightweight
regardless of actual complexity. If the heavyweight skill is the default path
in a given skill's phase file, everything will escalate. The classification
needs concrete signals (number of alternatives, presence of conflicting evidence,
cross-component impact) to be reliable.

### The --auto Flag Interaction With Agents Is Clean

Sub-agents inherently can't use AskUserQuestion (line 305-306). The flag only
controls the top-level orchestrator. This is a correct observation and means
the non-interactive mode doesn't require any special handling in the decision
skill's phase files or compiled template. Clean design.

---

## Summary: Top 3 Issues

| Rank | Issue | Risk | Impact |
|------|-------|------|--------|
| 1 | Compiled multi-phase agent prompts are structurally different from plan's single-task agents; reliability will degrade on sequential phase execution | Implementation failure | Decision agents produce low-quality or incomplete reports, requiring extensive retry logic |
| 2 | wip/ artifact lifecycle undefined for cross-validation window; cleanup timing, restart versioning, and volume unaddressed | Degraded experience | Artifact sprawl breaks resume logic, bloats git history, and loses evidence during cross-validation |
| 3 | prd skill unaddressed; static dispatch doesn't hold when decision count is input-dependent | Design gap | prd either gets no heavyweight support (limiting the framework's value) or requires dynamic dispatch (contradicting Decision 4) |
