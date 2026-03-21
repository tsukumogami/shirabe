# Crystallize Decision Framework

Reference for evaluating which artifact type fits an exploration's accumulated findings.
Loaded by Phase 4 (Crystallize) to score, rank, and recommend an artifact type.

## Documentation Purpose

Artifacts capture decisions already made, not only decisions yet to be made.

`wip/` is cleaned before every PR merges. Any decision recorded only in research
files or findings will be permanently lost when the branch closes. If exploration
produced architectural choices, dependency selections, structural decisions, or
design rationale that future contributors need to understand, those must be written
to a permanent document before the branch closes.

The question is not "do we still have something to decide?" — it's "did we decide
something a future contributor needs to know?"

## Supported Types

Four artifact types can be produced through /explore today. Each has a dedicated
command or a defined "no artifact" action path.

### PRD

Produces a requirements contract. Routes to /prd.

| Signals | Anti-Signals |
|---------|-------------|
| Single coherent feature emerged from exploration | Requirements were provided as input to the exploration |
| Requirements are unclear or contested | Multiple independent features that don't share scope |
| Multiple stakeholders need alignment on what to build | Independently-shippable steps that don't need coordination |
| The core question is "what should we build and why?" | |
| User stories or acceptance criteria are missing | |

### Design Doc

Produces a technical architecture document. Routes to /design.

| Signals | Anti-Signals |
|---------|-------------|
| What to build is clear, but how to build it is not | What to build is still unclear (route to PRD first) |
| Technical decisions need to be made between approaches | No meaningful technical risk or trade-offs |
| Architecture, integration, or system design questions remain | Problem is operational, not architectural |
| Exploration surfaced multiple viable implementation paths | |
| Architectural or technical decisions were made during exploration that should be on record | |
| The core question is "how should we build this?" | |

### Plan

Produces an issue breakdown with sequencing. Routes to /plan (user runs separately).

| Signals | Anti-Signals |
|---------|-------------|
| An existing PRD or design doc covers this topic | No clear deliverables or milestones |
| The work is understood well enough to break into issues | Technical approach is still debated |
| Exploration confirmed scope and approach, needs execution | Open architectural decisions need to be made first |
| The core question is "what order do we build in?" | |

### No Artifact

No document produced. Suggests direct action instead.

| Signals | Anti-Signals |
|---------|-------------|
| Simple enough to act on directly | Others need documentation to build from |
| One person can implement without coordination | Multiple people will work on this |
| Exploration confirmed existing understanding without making new decisions | Any architectural, dependency, or structural decisions were made during exploration |
| Short exploration (1 round) with high user confidence | Scope was debated across rounds |
| The right next step is "just do it" | |

## Deferred Types

The following artifact types are recognized by the Crystallize framework but not yet
supported by /explore's Produce phase. They'll be added in Feature 5. If Crystallize
identifies one of these as the best fit, inform the user and suggest the closest
available alternative.

| Type | Core Question | Closest Available Alternative |
|------|---------------|-------------------------------|
| Spike Report | Can we? (feasibility) | No artifact -- summarize findings, suggest next step |
| Decision Record | Which option? (single choice) | Design Doc -- captures the decision with full context |
| Competitive Analysis | What exists? (market/ecosystem) | No artifact -- summarize research, file as reference |
| Prototype | Does this work? (proof-of-concept) | No artifact -- start building directly with /work-on |
| Roadmap | What's next? (multi-feature sequence) | Plan -- covers single-feature sequencing |

When a deferred type fits best, explain:
1. Why the deferred type matches the findings
2. That /explore doesn't produce it yet
3. Which available alternative comes closest and why
4. Offer to produce a rough outline the user can develop manually

## Evaluation Procedure

Run these four steps against the accumulated findings from all discover-converge rounds.

### Step 1: Score Each Supported Type

For each of the four supported types (PRD, Design Doc, Plan, No artifact):
- Count the number of signals present in the findings
- Count the number of anti-signals present in the findings
- Score = signals present minus anti-signals present

Also check deferred types. If a deferred type scores highest, handle it per the
Deferred Types section above before continuing with supported types.

### Step 2: Rank and Demote

Rank supported types by score (highest first).

**Demotion rule:** Any type with one or more anti-signals present is demoted below
all types without anti-signals, regardless of its raw score. A type scoring 3 with
1 anti-signal ranks below a type scoring 1 with 0 anti-signals.

### Step 3: Apply Tiebreakers

When the top two types are tied or within 1 point after demotion, use these rules:

**PRD vs Design Doc:** If requirements were given as input to the exploration (known
before it started), a PRD already exists or isn't needed — favor Design Doc. If
requirements emerged during exploration (the exploration itself produced them), they
need to be captured in a PRD before design begins. The distinguishing question: did
/explore identify the requirements, or were they given to it? Identified -> PRD.
Given -> Design Doc.

**PRD vs No artifact:** If the exploration was short (1 round) and the user seems
confident about what to build, favor No artifact. If scope was debated across rounds
or multiple stakeholders are involved, favor PRD. The distinguishing question: can one
person act on this without a written contract? Yes -> No artifact. No -> PRD.

**Design Doc vs Plan:** If a PRD or design doc already exists in the repo for this
topic, favor Plan -- the upstream artifact is ready to decompose. If no source artifact
exists, favor Design Doc -- the technical decisions haven't been made yet.

### Step 4: Insufficient-Signal Fallback

If no supported type scores above 0 after demotion, the findings are too vague to
recommend an artifact. Instead of forcing a choice:

1. Tell the user the findings don't clearly point to any artifact type
2. Identify which signals are missing and what questions would surface them
3. Recommend another discover-converge round with specific leads targeting the gaps
4. Return to Phase 2 (Discover) with the new leads

This prevents premature commitment when exploration hasn't gone deep enough.

## Recommendation Format

Present the Crystallize output to the user with three parts:

### 1. Recommended Type

State the top-scoring type and list which signals matched. Be specific -- reference
actual findings from the exploration, not generic descriptions.

Example:
> **Recommended: Design Doc**
> Your exploration established clear requirements (the recipe format and CLI flags are
> well-defined) but surfaced three competing approaches for the version resolver. The
> core open question is architectural: how should version resolution work across
> providers?

### 2. Alternatives

List other types that partially fit. For each, note which signals matched and which
anti-signals or missing signals caused it to rank lower.

Example:
> **Alternative: PRD** -- Ranked lower because requirements emerged clearly during
> Round 2. The what-to-build question is answered; the how-to-build question is not.
>
> **Alternative: No artifact** -- Ranked lower because three implementation approaches
> need comparison before committing. Direct implementation risks choosing the wrong
> approach.

### 3. Deferred Types (if applicable)

If a deferred type scored well, note it separately with the suggested workaround
from the Deferred Types section.

## Disambiguation Rules

These rules handle common ambiguous patterns that raw scoring doesn't resolve cleanly.

**Exploration surfaced both requirement gaps AND technical questions.** If the user
doesn't know what to build AND doesn't know how to build it, favor PRD. Requirements
come first -- you can't design a solution without knowing the problem. The design doc
can follow the PRD.

**Exploration was deep but the user wants to act fast.** Urgency doesn't override the
need to capture decisions. If exploration made architectural or dependency choices,
those need a design doc regardless of how quickly the user wants to start coding.
What can be compressed is scope — a lean design doc that records the decisions is
still required. The right response is "write a lean doc and implement immediately,"
not "skip the doc."

**Plan signals are present but no upstream artifact exists.** Check whether open
decisions remain. If the scope is clear and the work is small enough that no
architectural or requirements decisions need to be documented first, a Plan is the
right artifact — exploration itself produced the understanding. If open decisions
remain (technical approach contested, requirements unclear), write the upstream
artifact (PRD or Design Doc) first; a Plan can't sequence work that hasn't been
decided yet.

**Multiple deferred types match.** If findings point to a spike report AND a prototype
(both are feasibility-focused), suggest No artifact with a recommendation to start
building. The fastest path to answering "can we?" is usually trying.

**Findings contradict across rounds.** If early rounds pointed to one type but later
rounds shifted direction, weight the later rounds more heavily. The user narrowed
focus during Converge phases, and later findings reflect that refined understanding.
