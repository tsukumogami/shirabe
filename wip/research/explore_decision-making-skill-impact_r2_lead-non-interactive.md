# Non-Interactive Execution Mode Design

Research lead: How should shirabe skills support fully non-interactive execution where
the agent never blocks on user input?

## Methodology

Cataloged every AskUserQuestion call site across all five workflow skills (explore,
design, prd, plan, work-on), classified each by purpose, and designed a unified
non-interactive mode that handles all of them.

## Inventory of User Interaction Points

Before designing the mode, here's what it needs to handle. Each interaction falls
into one of four categories.

### Category A: Conversational Scoping (must be eliminated)

These phases are inherently dialogic -- the skill doesn't know what to do without
user input. Non-interactive mode must replace the conversation with autonomous
scoping based on available context.

| Skill | Phase | Current Behavior |
|-------|-------|-----------------|
| explore | Phase 1 (Scope) | 2-4 turn dialogue to derive research leads |
| prd | Phase 1 (Scope) | 2-4 turn dialogue to derive problem statement and leads |

**Non-interactive behavior**: Skip the dialogue. Derive scope from `$ARGUMENTS`,
issue body, linked documents, and codebase analysis. Produce the scope artifact
directly. Document assumed scope boundaries as assumptions.

### Category B: Selection Decisions (auto-select with assumption)

The agent presents options and recommends one; the user approves or overrides. These
are the most common interaction type.

| Skill | Phase | Decision |
|-------|-------|----------|
| design | Phase 2 | Select technical approach from advocate findings |
| design | Phase 3 | Confirm investigation areas |
| design | Phase 4 | Confirm architecture direction |
| design | Phase 6 | Plan vs Approve-only routing |
| explore | Phase 3 | Explore further vs Ready to decide (loop control) |
| explore | Phase 4 | Confirm artifact type from crystallize scoring |
| explore | Phase 5 (deferred) | Select deferred artifact action |
| plan | Phase 3.0 | Walking skeleton vs horizontal (when ambiguous) |
| plan | Phase 3.6 | Single-pr vs multi-pr execution mode |
| plan | Phase 1 | Scope ambiguity in features |
| work-on | Phase 2 | Clarify or Amend stale issue spec |

**Non-interactive behavior**: Auto-select the recommended option. Record the
selection and rationale as an assumption. The agent already forms a recommendation
in interactive mode, so this is straightforward -- just follow through on it.

### Category C: Approval Gates (auto-approve with assumption)

Binary approve/reject decisions where the agent has produced an artifact and needs
sign-off before proceeding.

| Skill | Phase | What's Being Approved |
|-------|-------|----------------------|
| design | Phase 6.7 | Complete design doc ready for acceptance |
| prd | Phase 4.5 | Complete PRD ready for acceptance |
| explore | Phase 0 | Triage classification for needs-triage issues |

**Non-interactive behavior**: Auto-approve and document. The agent did the work; in
non-interactive mode it should trust its own output and move forward. But these
are the highest-risk assumptions because they commit to a deliverable the user
hasn't reviewed.

### Category D: Narrowing Questions (auto-answer with assumption)

Questions asked to help the user process findings and direct subsequent work. These
don't block on a specific option set -- they're open-ended.

| Skill | Phase | Question Type |
|-------|-------|--------------|
| explore | Phase 3 | "What matters most?" / "What surprised you?" |
| prd | Phase 3 | Thematic questions during drafting |
| prd | Phase 4 | Jury findings that surface trade-offs |

**Non-interactive behavior**: The agent answers its own question based on research
evidence, documenting the reasoning as an assumption. For thematic questions during
drafting, the agent picks the direction best supported by research and notes what
was uncertain.

---

## Question 1: How Is Non-Interactive Mode Signaled?

### Recommendation: Skill argument flag (`--auto`)

**Why not the other options:**

- **CLAUDE.md header**: Too permanent. Non-interactive is a per-invocation choice,
  not a project-level setting. A user might want interactive `/explore` but
  non-interactive `/work-on` in the same session.
- **Environment variable**: Works for propagation but invisible to the skill
  instructions. Skill files are markdown consumed by an LLM -- they can't
  read env vars. The agent would need separate instructions about checking env vars.
- **Per-invocation parameter**: This is what a flag is. The question is just naming.

**Flag name**: `--auto` over `--non-interactive` because:
- Shorter, easier to type in repeated use
- Positive framing (what it does) vs negative framing (what it doesn't do)
- Familiar from CI/CD tools (`--auto-approve`, `--yes`, etc.)

**Propagation to sub-operations**: When a skill spawns sub-agents (design Phase 1
advocates, prd Phase 4 jury, plan Phase 4 generation agents), the sub-agents don't
interact with users anyway -- they write to files and return summaries. The `--auto`
flag only matters at the orchestrator level where AskUserQuestion calls live. No
propagation problem exists because sub-agents already run non-interactively.

When one skill invokes another (explore Phase 5 handing off to `/design`), the
handoff instruction should carry the flag forward. The SKILL.md orchestrator is
responsible for passing `--auto` in the suggested command. This is explicit and
auditable.

**Detection in skill files**: Add a section to each SKILL.md:

```markdown
### Auto Mode

Check `$ARGUMENTS` for `--auto` flag. When present:
- Skip all conversational phases (derive scope from available context)
- Auto-select recommended options at all decision points
- Auto-approve all approval gates
- Record every autonomous decision in the assumptions file
- At workflow end, present the assumptions summary for review
```

### Alternative considered: dual-signal (flag + CLAUDE.md default)

A CLAUDE.md setting like `## Default Interaction Mode: auto` could set the default,
with `--interactive` overriding back. This would serve CI/pipeline use cases where
every invocation should be auto. Worth considering for v2 but adds complexity for
initial implementation.

---

## Question 2: Assumption Documentation Format

### The core tension

Assumptions range from heavyweight ("I chose approach A over B for the entire
architecture") to throwaway ("I assumed kebab-case naming because the codebase uses
it"). A single format must handle both without making lightweight assumptions feel
bureaucratic or heavyweight assumptions feel underdocumented.

### Recommendation: Tiered assumption records in a single wip/ file

**File**: `wip/<skill>_<topic>_assumptions.md`

Examples:
- `wip/design_caching-layer_assumptions.md`
- `wip/explore_plugin-system_assumptions.md`
- `wip/work-on_issue_42_assumptions.md`

**Structure**:

```markdown
# Assumptions: <topic>

## Summary

<N> assumptions made during non-interactive execution.
- <X> approach/direction assumptions (review recommended)
- <Y> scope/configuration assumptions (spot-check recommended)
- <Z> convention assumptions (review if unexpected)

## Approach Assumptions

These shaped the direction of the work. Invalidating one may require
re-executing from a specific phase.

### A1: Selected caching approach over direct storage

- **Phase**: design/Phase 2
- **Context**: Three approaches investigated by advocates. Caching scored highest
  on decision drivers (latency, simplicity).
- **What was decided**: Selected "Redis-backed cache" over "direct DB queries"
  and "in-memory LRU cache."
- **Evidence**: Advocate findings showed Redis handles the 99th percentile latency
  target; in-memory doesn't survive restarts; direct DB adds 40ms per request.
- **If wrong**: Re-execute from design/Phase 2 with different selection.
- **Confidence**: High -- evidence clearly favored this option.

### A2: Assumed API supports pagination

- **Phase**: design/Phase 3
- **Context**: Architecture assumes paginated list endpoints. Didn't verify
  because the API docs weren't accessible during execution.
- **What was decided**: Designed the data layer around paginated fetches.
- **Evidence**: Most REST APIs in this codebase use pagination. Convention-based
  assumption.
- **If wrong**: Re-execute from design/Phase 4; architecture section needs rewrite.
- **Confidence**: Medium -- based on convention, not verified.

## Scope Assumptions

These bounded what was included or excluded. Invalidating one changes what the
deliverable covers.

### A3: Excluded real-time sync from scope

- **Phase**: explore/Phase 1
- **Context**: Topic mentioned "data synchronization" but didn't specify real-time
  vs batch. Scoped to batch only.
- **What was decided**: Real-time sync is out of scope.
- **Evidence**: The issue title says "batch processing pipeline."
- **If wrong**: Re-scope and re-execute from Phase 1.
- **Confidence**: High -- title is explicit.

## Convention Assumptions

These followed existing patterns. Rarely wrong but worth knowing about.

### A4: Used kebab-case for file naming

- **Phase**: plan/Phase 3
- **Context**: Existing files in docs/ use kebab-case.
- **What was decided**: Named all new files with kebab-case.
- **Evidence**: Checked 12 existing files; all kebab-case.
- **If wrong**: Rename files. No re-execution needed.
- **Confidence**: High.
```

### Why three levels?

The levels correspond to re-execution cost:

| Level | Re-execution scope | Review urgency |
|-------|-------------------|----------------|
| Approach | Phase-level re-run | Review recommended |
| Scope | Possible full re-run | Spot-check recommended |
| Convention | Local fix, no re-run | Review if surprising |

This lets users triage efficiently. Read Approach assumptions first. Skim Scope.
Ignore Convention unless something looks wrong.

### Inline vs formal

Every assumption goes in the assumptions file regardless of weight. The level
determines how much detail is recorded:

- **Approach**: Full record (context, evidence, alternatives, re-execution path)
- **Scope**: Medium record (context, evidence, re-execution path)
- **Convention**: Brief record (what, evidence, fix path)

The agent writes assumptions incrementally as they occur. The Summary section is
updated at the end of the workflow.

---

## Question 3: Assumption Review Surface

### Recommendation: Three surfaces, increasing detail

**1. Terminal summary (immediate, always shown)**

When the workflow completes, print a structured summary before the final status
message:

```
--- Auto Mode: Assumption Summary ---

3 assumptions made (1 approach, 1 scope, 1 convention)

Approach assumptions (review recommended):
  A1: Selected Redis caching over direct DB [design/Phase 2, High confidence]
  A2: Assumed API supports pagination [design/Phase 3, Medium confidence]

Scope assumptions:
  A3: Excluded real-time sync [explore/Phase 1, High confidence]

Full details: wip/design_caching-layer_assumptions.md
```

This gives the user an at-a-glance view. They can stop here if everything looks
right, or dig into the full file for any that look suspicious.

**2. Assumptions file (detailed, always generated)**

The `wip/<skill>_<topic>_assumptions.md` file described in Question 2. This is the
source of truth. It persists in the branch alongside other wip/ artifacts and gets
cleaned up with them before merge.

**3. PR body section (when a PR is created)**

For skills that create PRs (design, prd, work-on), add an "Assumptions (Auto Mode)"
section to the PR body:

```markdown
## Assumptions (Auto Mode)

This workflow ran in `--auto` mode. The following assumptions were made
without user confirmation:

| # | Assumption | Phase | Confidence | Impact if Wrong |
|---|-----------|-------|------------|-----------------|
| A1 | Selected Redis caching | design/Phase 2 | High | Re-run Phase 2 |
| A2 | API supports pagination | design/Phase 3 | Medium | Re-run Phase 4 |
| A3 | Excluded real-time sync | explore/Phase 1 | High | Re-scope |

See `wip/<file>` on the branch for full details.
```

This makes assumptions visible during code review, not just to the invoker.
Reviewers who weren't present for the execution can see what was assumed.

### Why not an interactive review step?

An interactive review step ("here are your assumptions, approve each one") defeats
the purpose. The user wanted non-interactive execution. The review happens after
the fact, at the user's pace, on the user's terms. They read the summary, check
anything that looks off, and only then trigger re-execution if needed.

---

## Question 4: Assumption Invalidation and Re-execution

### The general pattern

When the user says "assumption X is wrong," the response depends on the assumption's
level and phase.

**Step 1: Identify the assumption by ID** (A1, A2, etc.) from the assumptions file.

**Step 2: Read the "If wrong" field** to determine re-execution scope.

**Step 3: Re-execute from the specified phase** with the user's correction as input.

### How this maps to different assumption types

**Approach assumptions (from decision skill / design phases)**:

The design skill already defines restart points. Phase 2 decisions restart from
Phase 2 (re-present approaches with the user's correction as a constraint). Phase 3
decisions restart from Phase 3. Phase 4 decisions restart from Phase 4.

In non-interactive mode, the same restart points apply. The difference is that the
re-execution also runs in auto mode unless the user explicitly asks for interactive
on the re-run. The user's correction becomes an additional constraint: "Given that
assumption A1 was wrong (API does NOT support pagination), re-execute from Phase 4."

**Scope assumptions**:

Scope corrections typically require re-running from Phase 1 (scoping) because they
change what's in/out. If the scope change is narrow ("include real-time sync"),
the agent can sometimes patch from a later phase. The assumptions file's "If wrong"
field captures the minimum restart point.

**Convention assumptions**:

These don't require re-execution. The fix is local: rename files, change formatting,
update a config value. The agent applies the correction directly.

**Non-decision assumptions** (e.g., "I assumed the API supports pagination"):

These are captured as Approach or Scope level assumptions depending on impact.
The "If wrong" field specifies the restart phase. The agent doesn't distinguish
between "a decision I made" and "a fact I assumed" -- both have a recorded restart
point and a correction path.

### Batch invalidation

The user might invalidate multiple assumptions at once. The agent should:

1. Collect all invalidated assumptions
2. Find the earliest restart phase among them
3. Re-execute from that phase with all corrections applied
4. Don't restart per-assumption sequentially -- that wastes work since later phases
   may depend on earlier ones

### Re-execution preserves other assumptions

When re-executing from Phase N, assumptions from phases before N remain valid
(they weren't invalidated). Assumptions from Phase N onward are cleared and
re-derived. The assumptions file is updated accordingly: prior assumptions stay,
invalidated ones are marked as corrected, and new assumptions from re-execution
are appended.

### The correction command

The user triggers re-execution by referencing assumptions:

```
"A2 is wrong -- the API uses cursor-based pagination, not offset pagination."
```

or in a more structured invocation:

```
/design --auto --correct A2="cursor-based pagination, not offset pagination" caching-layer
```

The simpler conversational form should work too. The agent reads the assumptions
file, finds A2, and knows to restart from design/Phase 4 with the correction.

---

## Question 5: Interaction with Existing Approval Gates

### The problem

Some AskUserQuestion calls are genuinely "the artifact is done, approve it." These
serve a quality control function, not an information-gathering function. In
interactive mode, they let the user reject substandard work. In auto mode, should
the agent auto-approve its own work?

### Recommendation: Auto-approve by default, with a confidence threshold

**Default behavior**: Auto-approve. The agent trusts its own output and moves
forward. The assumption is recorded as an Approach-level assumption ("Auto-approved
design doc for acceptance").

**Rationale**: The whole point of `--auto` is unblocked execution. If approval
gates block, the mode is useless for batch/pipeline scenarios. The user reviews
at the end via the assumptions summary.

**However**: The agent should self-assess before auto-approving. If it detects
quality issues during the approval phase (failing validation checks, unresolved
review feedback, incomplete sections), it should NOT auto-approve. Instead:

1. Record the issues in the assumptions file as a special "blocked" entry
2. Stop execution at that phase
3. The terminal summary shows the blocker

This is different from other assumption types -- it's not "I assumed X," it's
"I couldn't complete the work to a standard I'd approve."

### Specific gate behaviors

| Gate | Auto Behavior | Rationale |
|------|--------------|-----------|
| Design doc approval (Phase 6.7) | Auto-approve if validation passes | Validation is mechanical |
| PRD approval (Phase 4.5) | Auto-approve if jury passes | Jury review catches issues |
| Explore triage (Phase 0) | Auto-classify based on evidence | Low-risk; easily correctable |
| Design complexity routing (Phase 6.8) | Auto-select recommended | Same as selection decisions |
| PRD next-step routing (Phase 4.6) | Auto-select recommended | Same as selection decisions |

### What about work-on?

The work-on skill is interesting because it creates a PR that actually changes code.
The approval gate is implicit (creating the PR itself). In auto mode, it should
still create the PR, but the PR becomes the review surface. The user reviews
assumptions in the PR body and the code in the diff. This is actually the natural
workflow -- PRs exist for human review.

---

## Cross-Cutting Concerns

### Context window pressure

The assumptions file grows throughout the workflow. In long workflows (explore
with multiple rounds, or design with many decisions), the file could get large.
The agent should keep the assumptions file on disk and only load it when needed
(at decision points and at the end), not carry it in context throughout.

### Partial auto mode

Some users might want auto mode for scoping but interactive for approval gates, or
vice versa. The current design doesn't support this -- it's all-or-nothing.
A future enhancement could support `--auto=scope` or `--auto=decisions` for
granular control, but this adds significant complexity for unclear demand. Start
with all-or-nothing; split later if users request it.

### Existing resume logic compatibility

The assumptions file follows the same wip/ naming convention as other artifacts.
Resume logic should recognize it: if `wip/<skill>_<topic>_assumptions.md` exists,
the workflow was running in auto mode. On resume, continue in auto mode and append
to the existing assumptions file.

### Skills that spawn other skills

When explore hands off to design (Phase 5), or design hands off to plan (Phase 6.8),
the assumptions file from the parent skill should be referenced in the child skill's
assumptions file. The child creates its own assumptions file but includes a link:

```markdown
# Assumptions: caching-layer

## Parent Workflow
Continued from: `wip/explore_caching-layer_assumptions.md`
```

This lets the user see the full assumption chain across skill boundaries.

---

## Open Questions

1. **Should `--auto` be the default in any context?** Pipeline/CI environments
   might benefit from auto-by-default. Defer to v2.

2. **Assumption ID stability across re-execution.** When re-executing from Phase N,
   do assumption IDs restart? Recommendation: keep prior IDs stable, append new
   ones with incrementing numbers. A1 stays A1 even if invalidated.

3. **How does this interact with the decision-making skill from issue 6?** If that
   skill becomes a standalone invocable skill, its phases would need their own
   auto-mode behavior. The pattern generalizes cleanly -- each phase that has an
   AskUserQuestion gets an auto-mode alternative.
