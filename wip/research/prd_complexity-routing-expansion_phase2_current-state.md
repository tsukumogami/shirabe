# Current-State Analysis: Complexity Routing Expansion

## Lead 1: Current Routing Behavior Gaps

### Three Routing Sections in SKILL.md

The explore SKILL.md contains three distinct routing mechanisms in its header section (lines 29-58). Each serves a different entry point for routing decisions.

#### 1. Artifact Type Routing Guide (lines 33-41)

Situation-based table. Maps user statements to recommended commands. Six rows covering the spectrum from "don't know where to start" to "this is simple, just do it."

**Trivial coverage:** The last row explicitly handles the trivial case:
> "This is simple, just do it" -> `/work-on <issue>` -> "No artifact needed, go straight to implementation"

This is passive routing advice (when explore is auto-loaded and the user needs help picking a command). It already redirects trivial work away from /explore before the workflow starts.

**Strategic coverage:** No row explicitly addresses strategic/visionary work like "I have a new business idea" or "should this project exist?" The closest is the first row ("I want to build X but don't know where to start" -> `/explore`), which absorbs strategic topics into the generic explore funnel. There's no row that says "This is a new project that needs strategic justification" -> `/vision` or similar.

#### 2. Quick Decision Table (lines 44-50)

Question-based table. Maps core questions to best-fit artifact types, with alternatives. Five rows.

**Trivial coverage:** No explicit trivial row. The PRD vs "No artifact" alternative hints at trivial cases ("Can we build this?" -> Explore, with "No artifact (just try it)" as an alternative), but this is really about feasibility, not trivial tasks.

**Strategic coverage:** No row for "Should this project exist?" or "Is this worth pursuing?" The closest is "Can we build this?" (feasibility) which maps to Explore, but strategic justification is a different question than feasibility.

#### 3. Complexity-Based Routing (lines 54-58)

Complexity-based table. Three levels: Simple, Medium, Complex.

**Current levels:**

| Complexity | Signals | Recommended Path |
|------------|---------|------------------|
| Simple | Clear requirements, few files, one person | `/work-on` or `/prd` then implement |
| Medium | Known approach, some integration risk | `/design` then `/plan` |
| Complex | Multiple unknowns, shape unclear | `/explore` to discover first |

**Trivial gap:** "Simple" is the lowest level, but it still routes to `/work-on` OR `/prd`. There's no level below Simple that says "skip all workflow skills entirely" or "this doesn't even need /work-on, just make the edit." True trivial work (fix a typo, update a config value) gets routed to `/work-on` which still runs a full implementation workflow. The Artifact Type Routing Guide does better here by pointing to `/work-on` directly.

**Strategic gap:** "Complex" is the highest level, but its signals ("multiple unknowns, shape unclear") and routing (`/explore`) don't distinguish between tactical complexity (hard engineering problem) and strategic complexity (should this project exist?). A user exploring "should we build a new product?" gets the same routing as a user exploring "how should we refactor the database layer?" -- both land in /explore, but the crystallize framework has very different artifact types for these (VISION vs Design Doc).

### What Happens When Trivial Work Reaches /explore?

If a user invokes `/explore fix a typo`, the workflow runs through Phase 0 (setup), then Phase 1 (Scope) which is a conversational scoping phase. Phase 1 asks open-ended questions and tries to identify 3-8 research leads. For a truly trivial task, the conversation would likely conclude quickly, but there is no early-exit mechanism in Phase 1 that says "this is too simple for exploration." The user would need to go through the full scoping conversation before the system could determine the task is trivial.

The Artifact Type Routing Guide (passive routing) would catch this if Claude is auto-loaded and the user asks for help. But once `/explore` is explicitly invoked, there's no circuit breaker.

### What Happens When Strategic Work Reaches /explore?

If a user invokes `/explore I have a new business idea`, the workflow works correctly but takes a roundabout path:

1. Phase 1 scopes the topic
2. Phase 2-3 discover-converge loop runs research
3. Phase 4 (Crystallize) evaluates artifact types against the crystallize framework

The crystallize framework (crystallize-framework.md) **does** handle this well. It has a full VISION artifact type with clear signals:
- "Project doesn't exist yet (no repo, no codebase)"
- "Exploration centered on 'should we build this?'"
- "Org fit or strategic alignment was the core question"
- Anti-signal: "Scope is tactical (override or repo default)"

Phase 5 has a dedicated `phase-5-produce-vision.md` that creates a handoff artifact and invokes `/vision`.

So strategic work IS handled, but only after running through the full explore workflow. The complexity routing table doesn't hint that strategic topics exist as a category -- it just absorbs them into "Complex."

### Crystallize Framework Coverage

The crystallize framework (crystallize-framework.md) supports **ten artifact types** plus one deferred type:

**Supported:** PRD, Design Doc, Plan, No Artifact, Rejection Record, VISION, Roadmap, Spike Report, Decision Record, Competitive Analysis

**Deferred:** Prototype

The framework is well-designed for the full spectrum of work types. However, there's an internal inconsistency: Phase 4 (phase-4-crystallize.md, line 70) refers to "five supported types" in its Step 4.3:

> "For each of the five supported types (PRD, Design Doc, Plan, No Artifact, Rejection Record):"

But the crystallize framework itself lists ten supported types. Phase 4 then mentions deferred types separately (line 77-79):

> "Also check the deferred types (Spike Report, Decision Record, Competitive Analysis, Prototype, Roadmap)."

This means VISION is missing from both lists in Phase 4. It's in the crystallize framework's supported types but Phase 4 doesn't explicitly mention scoring it. The framework would still produce correct results (the scoring procedure references the framework's full type list), but the Phase 4 instructions are inconsistent with the framework.

---

## Lead 2: Routing Table Consistency

### What Each Section Covers

| Section | Input Type | Audience | Purpose |
|---------|-----------|----------|---------|
| Artifact Type Routing Guide | User situation statements | Passive (auto-loaded Claude) | Redirect users to the right command BEFORE entering /explore |
| Quick Decision Table | Core questions about the work | User deciding between PRD/Design/Plan/Explore | Help users self-classify what artifact they need |
| Complexity-Based Routing | Complexity signals | User or Claude deciding on workflow depth | Match workflow depth to task complexity |

### Do All Three Need Updates for the 5-Level Model?

**Complexity-Based Routing:** Yes, this is the primary target. Expanding from 3 to 5 levels means adding Trivial and Strategic rows.

**Artifact Type Routing Guide:** Partially. It already covers the trivial case ("This is simple, just do it" -> `/work-on`). But it lacks a strategic row. Adding a row like "This is a new project that needs strategic justification" -> `/vision` or `/explore --strategic` would improve coverage.

**Quick Decision Table:** Partially. Missing questions for the Trivial and Strategic ends:
- Trivial: "Is this a quick fix?" -> No artifact, `/work-on` directly
- Strategic: "Should this project exist?" -> VISION (or Explore -> VISION)

### Inconsistencies Between the Three Tables

**Inconsistency 1: "Simple" has different meanings.**
- Artifact Type Routing Guide: "This is simple, just do it" -> `/work-on` (skip all artifacts)
- Complexity-Based Routing: Simple -> `/work-on` OR `/prd` then implement

The routing guide treats "simple" as what a 5-level model would call "Trivial" (skip artifacts entirely). The complexity table's "Simple" is broader -- it includes work that might need a PRD first. These are different complexity levels conflated under the same label.

**Inconsistency 2: No alignment between Quick Decision Table and Complexity Routing.**
The Quick Decision Table doesn't reference complexity at all. It's purely about the nature of the question (what vs how vs order). The Complexity-Based Routing doesn't reference the question type. A user asking "What should we build?" at Simple complexity has no clear path -- the Quick Decision Table says PRD, the Complexity table says `/work-on` or `/prd`.

**Inconsistency 3: Strategic scope is in the Context Resolution section, not the routing tables.**
The SKILL.md has a scope detection mechanism (lines 127-133) that reads `--strategic` or `--tactical` flags and repo defaults. But the routing tables don't reference scope at all. A user in a Strategic-default repo gets the same routing advice as one in a Tactical-default repo. The crystallize framework does check scope (VISION anti-signal: "Scope is tactical"), but this is deep in Phase 4 -- far after the initial routing advice.

**Inconsistency 4: Phase 4 lists only 5 supported types but the framework lists 10.**
As noted above, Phase 4's Step 4.3 says "five supported types" but the crystallize framework defines ten. VISION, Roadmap, Spike Report, Decision Record, and Competitive Analysis are relegated to "deferred types" in Phase 4's text (line 77-79), even though the framework considers several of these as fully supported. This means Phase 4's instructions are stale relative to the framework.

### What Already Works for Trivial Cases

1. The Artifact Type Routing Guide catches "This is simple, just do it" and redirects to `/work-on`.
2. The crystallize framework's "No Artifact" type has signals for: "Simple enough to act on directly," "One person can implement without coordination," and "Short exploration (1 round) with high user confidence."
3. Phase 5's No Artifact handler (`phase-5-produce-no-artifact.md`) suggests `/work-on` or `/issue` as next steps.

**What's missing for Trivial:** No early-exit in Phase 1 that detects trivial work and short-circuits the exploration. No routing guidance that distinguishes "simple but needs a PRD" from "trivial, don't bother with any workflow skill."

### What Already Works for Strategic Cases

1. The crystallize framework has full VISION support with clear signals/anti-signals.
2. Phase 5 has a dedicated VISION handoff (`phase-5-produce-vision.md`) that creates a scope artifact and auto-invokes `/vision`.
3. The crystallize framework has tiebreakers for VISION vs PRD, VISION vs Roadmap, VISION vs Rejection Record, VISION vs No Artifact.
4. Disambiguation rules handle "strategic justification AND feature requirements" (VISION first, then PRD).
5. The Roadmap artifact type covers "multiple features need ordering across initiatives."

**What's missing for Strategic:** No upfront signal that tells explore to expect a strategic outcome. The complexity routing table doesn't mention strategic work. The scope detection (`--strategic` flag) exists but doesn't feed into the routing tables or Phase 1's scoping conversation. A user with a strategic topic gets the same Phase 1 conversation style as a user with a tactical bug.

---

## Summary of Gaps

### Critical Gaps (must address in 5-level expansion)

1. **Complexity-Based Routing table needs Trivial and Strategic rows** with distinct signals and paths.
2. **Phase 4 type count is stale** -- says "five supported types" but the framework has ten. Must be updated regardless of the complexity expansion.
3. **No early-exit for trivial work** once /explore is invoked. Need a circuit breaker in Phase 1 or a pre-Phase 1 gate.

### Important Gaps (should address)

4. **Artifact Type Routing Guide needs a strategic row** -- currently no advice for "should this project exist?"
5. **Quick Decision Table needs trivial and strategic questions** -- missing "Is this a quick fix?" and "Should this project exist?"
6. **Scope (strategic/tactical) doesn't feed into routing tables** -- the `--strategic` flag exists but only matters deep in Phase 4's crystallize scoring.

### Minor Inconsistencies

7. **"Simple" means different things** in the Routing Guide vs Complexity table.
8. **Quick Decision Table and Complexity Routing are orthogonal** with no cross-reference.

### Things That Already Work

- Crystallize framework handles the full spectrum (10 artifact types including VISION)
- Phase 5 has dedicated handlers for VISION, Roadmap, and other strategic artifacts
- Passive routing advice catches trivial work before /explore starts
- The `--strategic`/`--tactical` scope mechanism exists in context resolution
