---
name: explore
description: Structured exploration workflow and artifact-type routing advisor. Use when the user
  isn't sure what to build, doesn't know which workflow fits their situation, or wants to research
  before committing to a PRD, design doc, or plan. Triggers on "should I write a PRD or a design
  doc?", "I don't know where to start", "what should I do next?", "how do I start this?", "I'm
  stuck", or explicit /explore invocations. Helps figure out whether you need a PRD, design doc,
  plan, or something else through a discover-converge loop with research agents.
  Does NOT apply when the user already knows their artifact type -- use /prd, /design,
  or /plan directly instead.
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

## Crystallize Framework

Phase 4 uses the crystallize framework to evaluate which artifact type fits the
exploration's findings. See `references/quality/crystallize-framework.md` for the
full scoring system, loaded during Phase 4.

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

#### 0. Detect Execution Mode

Check `$ARGUMENTS` for `--auto` or `--interactive` flags. Also check for
`--max-rounds=N`. If neither mode flag is present, read CLAUDE.md
`## Execution Mode:` header (values: `auto` or `interactive`, default:
`interactive`).

In `--auto` mode, the agent never blocks on user input. At decision points,
follow the research-first protocol in `references/decision-protocol.md`:
gather evidence, form recommendation, follow it, document as a decision
block. Create `wip/explore_<topic>_decisions.md` to track all decisions.

Default max rounds in --auto: 3. Override with `--max-rounds=N`.

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

Visibility is immutable -- public repos must never accidentally include private
references, even if a user passes --private. Flags can't override it.

After detecting visibility, load the appropriate content governance skill:
- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

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
following the pattern in `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`.

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

---

## Reference Files

| File | When to load |
|------|-------------|
| `references/phases/phase-0-setup.md` | Phase 0 |
| `references/phases/phase-1-scope.md` | Phase 1 |
| `references/phases/phase-2-discover.md` | Phase 2 (each round) |
| `references/phases/phase-3-converge.md` | Phase 3 (each round) |
| `references/phases/phase-4-crystallize.md` | Phase 4 |
| `references/phases/phase-5-produce.md` | Phase 5 (routing stub) |
| `references/phases/phase-5-produce-prd.md` | Phase 5, PRD handoff |
| `references/phases/phase-5-produce-design.md` | Phase 5, Design Doc handoff |
| `references/phases/phase-5-produce-plan.md` | Phase 5, Plan handoff |
| `references/phases/phase-5-produce-no-artifact.md` | Phase 5, No artifact |
| `references/phases/phase-5-produce-decision.md` | Phase 5, Decision Record handoff |
| `references/phases/phase-5-produce-deferred.md` | Phase 5, Roadmap/Spike/Competitive/Prototype |
| `references/quality/crystallize-framework.md` | Phase 4 (full decision framework) |
