---
name: explore
description: Structured exploration workflow and artifact-type routing advisor. Use when the user
  isn't sure what to build, doesn't know which workflow fits their situation, or wants to research
  before committing to a PRD, design doc, or plan. Also triggers on explicit /explore invocations
  and on questions like "should I write a PRD or a design doc?" or "I don't know where to start."
  Runs a discover-converge loop with research agents, then recommends the right artifact type based
  on findings.
argument-hint: '<topic or issue number>'
---

@.claude/shirabe-extensions/explore.md
@.claude/shirabe-extensions/explore.local.md

# Explore

Explore is the entry point for "I don't know what I need." It serves two roles:
as a passive routing advisor (when Claude is auto-loaded and users need help picking
a command), and as an active exploration workflow (when invoked via /explore).

Other skills own specific artifact types: /prd owns requirements, /design owns
technical architecture, /plan owns issue decomposition. Explore owns the question
of WHICH artifact type to produce. It investigates before committing.

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Artifact Type Routing Guide

When a user isn't sure what to build, use this table to recommend a starting point.

| Situation | Route To | Why |
|-----------|----------|-----|
| "I want to build X but don't know where to start" | `/explore <topic>` | Open-ended; the right artifact type isn't clear yet |
| "Should I write a PRD or design doc?" | Read the decision table below | Match signals to the situation |
| "I know what to build, not how" | `/design <topic>` | What-to-build is settled, how-to-build is the question |
| "I know what we need but haven't written it down" | `/prd <topic>` | Requirements need to be captured and agreed on |
| "I have a design doc, need to break it into issues" | `/plan <design-doc-path>` | Decomposition of an existing artifact |
| "This is simple, just do it" | `/work-on <issue>` | No artifact needed, go straight to implementation |

### Quick Decision Table

| Core Question | Best Fit | Alternative |
|---------------|----------|-------------|
| "What should we build and why?" | PRD | Explore (if even the question is unclear) |
| "How should we build this?" | Design Doc | Explore (if multiple paths exist) |
| "What order do we build in?" | Plan | Design Doc (if approach isn't decided) |
| "Can we build this?" (feasibility) | Explore | No artifact (just try it) |
| "What exists already?" (landscape) | Explore | No artifact (write up findings) |

### Complexity-Based Routing

| Complexity | Signals | Recommended Path |
|------------|---------|------------------|
| Simple | Clear requirements, few files, one person | `/work-on` or `/prd` then implement |
| Medium | Known approach, some integration risk | `/design` then `/plan` |
| Complex | Multiple unknowns, shape unclear | `/explore` to discover first |

## Crystallize Framework Summary

The crystallize framework evaluates which artifact type fits an exploration's findings.
Full reference: `references/quality/crystallize-framework.md`

**Supported types** with key signals:

| Type | Key Signals | Key Anti-Signals |
|------|------------|-----------------|
| PRD | Single feature, unclear requirements, multiple stakeholders | Requirements were given as input (not discovered), multiple independent features |
| Design Doc | What is clear but how is not, technical decisions needed | What is still unclear, no technical risk |
| Plan | Scope confirmed, work decomposable into issues | Open decisions remain, no clear deliverables |
| No artifact | Confirmed existing understanding, no new decisions made | Any decisions were made during exploration, others need docs |

**Deferred types** (recognized but not yet routable -- Feature 5):
Spike Report, Decision Record, Competitive Analysis, Prototype, Roadmap.
If these fit best, suggest the closest available alternative.

**Scoring:** Count signals present minus anti-signals present per type. Demote any
type with anti-signals below types without. Apply tiebreakers for close calls.
See the full framework for details.

## Lead Conventions

Leads are research questions produced during Scope (Phase 1). Each lead becomes an
agent assignment during Discover (Phase 2). Good leads share three properties:

1. **Questions, not solutions.** "What deployment models exist for plugin systems?"
   beats "Evaluate a WASM-based plugin system." Questions keep the investigation open.

2. **Specific enough to investigate.** "How do other CLI tools handle version
   resolution?" gives an agent something to look into. "Explore versioning" is too
   vague for useful output.

3. **Open enough to surprise.** A lead should allow the agent to return unexpected
   findings. If you already know the answer, it's not a lead -- it's validation.

**Lead count:** 3-8 per round. Fewer than 3 doesn't cover enough ground. More than 8
risks spreading too thin (and hits agent parallelism limits). Cluster related leads
if the scope produces more.

**Round evolution:** Later rounds should build on earlier findings. If Round 1
discovered three competing approaches, Round 2 leads might investigate each one's
trade-offs. The leads change shape as understanding deepens.

## Convergence Patterns

After agents return from a discover round, the Converge phase presents findings and
helps the user narrow focus. Effective convergence surfaces four things:

1. **Key insights** -- what did the agents find that matters most? Prioritize
   surprising or decision-relevant findings over confirmations of what was already known.

2. **Tensions** -- where do findings contradict each other or create trade-offs?
   These often point toward the real decisions that need to be made.

3. **Gaps** -- what's still missing? Which leads didn't produce useful results?
   Gaps inform the next round's leads.

4. **Open questions** -- what does the user want to know more about? The answer
   determines whether to loop back (more rounds) or crystallize (decide artifact type).

After convergence, explicitly capture any decisions made during the round --
scope narrowing, option elimination, priority choices -- in the decisions file.
These accumulate across rounds and feed into crystallize and produce phases.

The user controls the loop. After convergence, they choose: explore further or
decide what to build. Don't push toward crystallization prematurely.

## Handoff Artifact Formats

When /explore crystallizes to a target type, Phase 5 writes artifacts matching
that command's expected format. The full templates live in `references/phases/phase-5-produce.md`.

Summary of handoffs by target:

| Target | Handoff artifact(s) |
|--------|---------------------|
| /prd | `wip/prd_<topic>_scope.md` |
| /design | `docs/designs/DESIGN-<topic>.md` + `wip/design_<topic>_summary.md` |
| /plan | None (user runs `/plan <topic>` directly) |
| No artifact | None (summarize findings, suggest next steps) |
| Roadmap, Spike, ADR, Competitive Analysis | Produced directly in Phase 5 |

Do NOT delete wip/ research files after routing. The target skill's phases may
reference them. Cleanup happens when the target workflow completes or when the
user runs `/cleanup`.

---

## Exploration Workflow

When invoked as `/explore`, this skill drives a structured expansion-contraction
loop. Fan out research agents on leads, converge findings with the user, repeat
until ready, then decide what artifact type to produce.

### Input Detection

From `$ARGUMENTS`:

1. **Empty** -- ask the user what they want to explore
2. **Issue number** (matches `#?\d+` or `org/repo#\d+`) -- read the issue, check
   for `needs-triage` label, and derive topic from the issue title
3. **Anything else** -- use as the topic string, proceed to scope

For cross-repo issues (e.g., `owner/repo#42`), use `gh` commands:
```bash
gh issue view 42 --repo owner/repo --json title,body,labels
```

### Context Resolution

#### 1. Detect Visibility

Read the repo's CLAUDE.md (or CLAUDE.local.md) for:
```
## Repo Visibility: Private
```
or
```
## Repo Visibility: Public
```

If not found, infer from path: `private/` -> Private, `public/` -> Public.
Default to Private if unknown.

Visibility is immutable. Flags can't override it.

#### 2. Detect Scope

Check `$ARGUMENTS` for `--strategic` or `--tactical` flags. If neither, read
default from CLAUDE.md:
```
## Default Scope: Strategic
```

Default to Tactical if not found.

#### 3. Log Context

Output before proceeding:
```
Exploring with [Private|Public] visibility in [Strategic|Tactical] scope...
```

### Cross-Repo Issue Handling

When starting from an issue in a different repo than the working directory:

1. Read the issue via `gh issue view <N> --repo <owner/repo>`
2. Resolve visibility from the WORKING repo (where artifacts land), not the issue's repo
3. Visibility rule: public repos must not reference private issues in produced artifacts
4. Research agents may read the issue's repo for context, but wip/ artifacts live in
   the working repo

### Resume Logic

Resume is based on topic-scoped wip/ artifacts. Evaluate the conditions top-to-bottom
and resume at the first match.

```
wip/explore_<topic>_crystallize.md exists                          -> Phase 5 (Produce)
wip/explore_<topic>_findings.md has "## Decision: Crystallize"     -> Phase 4 (Crystallize)
wip/explore_<topic>_findings.md exists (no crystallize marker)     -> Phase 3 (Converge)
wip/research/explore_<topic>_r*_lead-*.md exist, no findings file  -> Phase 3 (Converge)
wip/explore_<topic>_scope.md exists                                -> Phase 2 (Discover)
On topic branch, no explore artifacts                              -> Phase 1 (Scope)
Not on topic branch                                                -> Phase 0 (Setup)
```

When resuming:
- **Phase 3:** Read all research files and the findings file. Present accumulated
  results and ask whether to explore further or crystallize.
- **Phase 4:** The user decided to crystallize (marker in findings file) but the
  crystallize artifact wasn't written. Re-run crystallize.
- **Phase 5:** Read the crystallize decision and proceed with handoff.

### Workflow Phases

```
Phase 0: SETUP -> Phase 1: SCOPE -> Phase 2: DISCOVER -> Phase 3: CONVERGE --+
                                          ^                     |             |
                                          |      "explore       |             |
                                          +---- further" ------+             |
                                                                 "ready"      |
                                                                    |         |
                                                           Phase 4: CRYSTALLIZE
                                                                    |
                                                           Phase 5: PRODUCE
```

| Phase | Purpose | Artifact |
|-------|---------|----------|
| 0. Setup | Branch, context, triage (if needed) | On topic branch |
| 1. Scope | Conversational scoping, produce leads | `wip/explore_<topic>_scope.md` |
| 2. Discover | Fan out lead agents (round N) | `wip/research/explore_<topic>_r<N>_lead-<name>.md` |
| 3. Converge | Present findings, user narrows or exits loop | `wip/explore_<topic>_findings.md` |
| 4. Crystallize | Evaluate artifact type, user confirms | `wip/explore_<topic>_crystallize.md` |
| 5. Produce | Hand off to target command or route to action | Handoff artifact for target command |

### Phase Execution with Loop Management

Execute phases sequentially. After Phase 3, the orchestrator (this file) manages
the discover-converge loop -- not the phase files.

**Phase 0: Setup**
Read: `references/phases/phase-0-setup.md`

**Phase 1: Scope**
Read: `references/phases/phase-1-scope.md`

**Phase 2: Discover (Round N)**
Read: `references/phases/phase-2-discover.md`

On the first pass, N=1. On subsequent passes after "explore further," increment N.

**Phase 3: Converge**
Read: `references/phases/phase-3-converge.md`

After Phase 3 completes, present the loop decision using AskUserQuestion
following the pattern in `references/decision-presentation.md`.

**Recommendation heuristic:** If the convergence output surfaces significant gaps,
open questions, or contradictions, recommend "Explore further." If findings are
sufficient and no major gaps remain, recommend "Ready to decide."

**Options:**
1. "Explore further (Recommended)" or "Ready to decide (Recommended)" -- based on heuristic above
2. The other option, with a brief justification for why it ranks lower

**Description field:** Ground the recommendation in specific convergence output --
cite the gaps that remain or explain why coverage is sufficient.

If **Explore further:**
- Capture new leads from the user (informed by gaps and open questions from convergence)
- Update the scope file with the new leads for this round
- Return to Phase 2 with N incremented

If **Ready to decide:**
- Add `## Decision: Crystallize` marker to the findings file
- Proceed to Phase 4

**Phase 4: Crystallize**
Read: `references/phases/phase-4-crystallize.md`

**Phase 5: Produce**
Read: `references/phases/phase-5-produce.md`

### wip/ Artifact Naming

All artifacts use topic-scoped naming with kebab-case topics:

| Artifact | Path |
|----------|------|
| Scope | `wip/explore_<topic>_scope.md` |
| Accumulated findings | `wip/explore_<topic>_findings.md` |
| Accumulated decisions | `wip/explore_<topic>_decisions.md` |
| Crystallize decision | `wip/explore_<topic>_crystallize.md` |
| Research (round N, lead L) | `wip/research/explore_<topic>_r<N>_lead-<name>.md` |

#### Decisions File Format

The decisions file (`wip/explore_<topic>_decisions.md`) tracks choices made
during convergence rounds. It's created in Phase 3 on the first round that
produces decisions, and appended to in subsequent rounds.

```markdown
# Exploration Decisions: <topic>

## Round 1
- <decision>: <rationale>
- <decision>: <rationale>

## Round 2
- <decision>: <rationale>
```

Decisions include scope narrowing (areas eliminated), option elimination
(approaches ruled out), priority choices (what matters most), and constraints
accepted (trade-offs acknowledged). Each entry states what was decided and why
in one or two lines.

Phase 4 reads this file to inform artifact type scoring. Phase 5 includes
accumulated decisions in handoff artifacts. The file may not exist if no
explicit decisions were made during exploration.

Handoff artifacts use the TARGET command's naming:

| Target | Handoff Artifact |
|--------|-----------------|
| /design | `docs/designs/DESIGN-<topic>.md` + `wip/design_<topic>_summary.md` |
| /prd | `wip/prd_<topic>_scope.md` |
| /plan | None (takes doc path directly) |

Do NOT delete wip/ research files after routing. The target skill's phases may
reference them. Cleanup happens when the target workflow completes or when the
user runs `/cleanup`.

---

## Reference Files

| File | When to load |
|------|-------------|
| `references/phases/phase-0-setup.md` | Phase 0 |
| `references/phases/phase-1-scope.md` | Phase 1 |
| `references/phases/phase-2-discover.md` | Phase 2 (each round) |
| `references/phases/phase-3-converge.md` | Phase 3 (each round) |
| `references/phases/phase-4-crystallize.md` | Phase 4 |
| `references/phases/phase-5-produce.md` | Phase 5 |
| `references/quality/crystallize-framework.md` | Phase 4 (full decision framework) |
