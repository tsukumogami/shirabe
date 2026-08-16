---
name: explore
description: Structured exploration workflow and routing advisor. Use when the user
  isn't sure what to build, doesn't know which workflow fits their situation, or wants to research
  before committing to a chain. Triggers on "should I write a PRD or a design
  doc?", "I don't know where to start", "what should I do next?", "how do I start this?", "I'm
  stuck", or explicit /explore invocations. Helps figure out whether the work enters at /scope or
  /charter, is one issue, or is a spike, decision, or landscape write-up, through a
  discover-converge loop with research agents. Does NOT apply when the user already knows the
  altitude -- use /scope, /charter, or /execute directly instead.
argument-hint: '<topic or issue number>'
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh explore 2>&1 || true`

@.claude/shirabe-extensions/explore.md
@.claude/shirabe-extensions/explore.local.md

# Explore

Explore is the entry point for "I don't know what I need." It serves two roles:
as a passive routing advisor (when Claude is auto-loaded and users need help picking
a command), and as an active exploration workflow (when invoked via /explore).

Other skills own the work itself: `/scope` runs the tactical chain, `/charter`
the strategic one, `/execute` drives a finished PLAN, and `/work-on` takes a
single issue. Explore owns the question of which one receives the work, and it
answers that question after the research rather than before it.

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Routing Guide

When a user isn't sure where to start, use this table to recommend a command.
Every destination is something the author runs. None of them is a step inside a
chain that a parent skill already sequences: a BRIEF, a PRD, a DESIGN, and a
PLAN are hops inside `/scope`, and picking one of them as an entry point is the
choice this skill stopped making.

| Situation | Route To | Why |
|-----------|----------|-----|
| "I want to build X but don't know where to start" | `/explore <topic>` | Open-ended; what the work turns out to be isn't clear yet |
| "I have one feature to specify, from its framing through its issues" | `/scope <topic>` | The tactical chain runs whole and reduces per hop; its terminal artifact is a PLAN |
| "I need to justify this project" or "I have a multi-feature initiative" | `/charter <topic>` | The strategic chain: thesis, bet, and a sequenced roadmap |
| "I have a PLAN and want it built" | `/execute <plan-path>` | Plan-level execution; it accepts a PLAN path and nothing else |
| "This is simple, just do it" | `/work-on <issue>` | No document needed, go straight to implementation |
| "I have one choice between named options" | `/decision <question>` | A single decision with a durable record and no work attached |
| "What exists in this space?" | `/comp <topic>` | Competitive landscape, with a jury and a lifecycle transition; private repos only |

### Quick Decision Table

| Core Question | Best Fit | Alternative |
|---------------|----------|-------------|
| "Do I need any document at all?" | File an issue, then `/work-on` | `/scope` if the scope is likely to grow |
| "What should we build, and how?" | `/scope` | `/explore` if even the question is unclear |
| "Can we build this?" (feasibility) | `/explore`, which authors the spike report | File an issue and try |
| "What exists already?" (landscape) | `/explore`, which routes to `/comp` in a private repo | File an issue and write the findings into it |
| "Which option, and why?" | `/decision` | `/explore` if the options aren't identified yet |
| "Should this project exist?" or "Which features should we build?" | `/charter` | `/explore` if the scope is unclear |
| "Should we start building the PLAN we have?" | `/execute <plan-path>` | `/work-on <issue>` if only one issue out of it is in play |

Two rows are gone rather than re-pointed. "Should I write a PRD or a design
doc?" and the pair that split "what should we build" from "how should we build
it" drew the same distinction, and that distinction only existed while a PRD and
a DESIGN were separately choosable. Both are hops inside `/scope` now, so the
question has one answer.

### Complexity-Based Routing

Complexity is advisory, and only here. It answers "which command should I run?"
before any exploration exists. Once an exploration has run, Phase 4 scores the
accumulated findings, and nothing in this section feeds that scoring -- a second
classification vocabulary inside the one routing surface would just disagree
with it.

| Complexity | Signals | Recommended Path |
|------------|---------|------------------|
| Trivial | Self-evident change, single file, no decisions, no issue needed | `/work-on` directly, no issue |
| Simple | Clear requirements, few files, one person, no competing approaches | File an issue, then `/work-on <issue>` |
| Complex | Multiple unknowns, shape unclear, can't state requirements or approach | `/explore`, and let the crystallize step name the destination |
| Strategic | Project inception, multi-feature sequencing, thesis validation needed | `/charter` |

The Medium row is removed rather than re-pointed. Its recommendation was design
then plan, and the case it described -- requirements settled, approach open --
was worth separating only while those two were separately choosable. A request
that used to land on Medium reads as Complex here, and `/explore` decides
whether it enters the chain at `/scope` or is small enough to file.

### Detection Algorithm

Check from highest complexity down. Stop at the first YES.

```
1. Does the request reference project direction, multi-feature sequencing,
   or thesis validation?
   YES -> Strategic
   Boundary: if it's about one feature within an existing project -> Complex

2. Can the user clearly state both what to build and how?
   NO (the problem is unclear, or the approach is contested) -> Complex

3. Does a GitHub issue exist (or should one exist) with defined scope?
   YES -> Simple
   Boundary: if "done" is self-evident without acceptance criteria -> Trivial

4. Is the change self-evident and fire-and-forget?
   YES -> Trivial

5. Default -> Simple (file an issue and proceed)
```

Step 2 absorbs the old Medium question. Design decisions where reasonable people
could disagree leave "how" unstated, which is a Complex answer now.

## Crystallize Framework

Phase 4 scores the exploration's findings in two stages: what the exploration is
-- four terminal outcomes no chain owns, plus "a chain" -- and then, for a chain,
which entry point receives it. See `references/quality/crystallize-framework.md`
for the candidacy preconditions, both scoreboards, and the tiebreakers. Loaded
during Phase 4.

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

Scope sets how the research phases read the topic and how content governance
applies. It puts no thumb on the crystallize scoreboard. `--strategic` is also a
repo default read from CLAUDE.md, so letting it bias the outcome would
pre-answer the router for every exploration in a strategic-default repo. An
exploration launched strategic can land on `/scope`, and one launched tactical
can land on `/charter`.

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
| 0. Setup | Branch, context, entry assessment (if from an issue) | On topic branch |
| 1. Scope | Conversational scoping, produce leads | `wip/explore_<topic>_scope.md` |
| 2. Discover | Fan out lead agents (round N) | `wip/research/explore_<topic>_r<N>_lead-<name>.md` |
| 3. Converge | Present findings, user narrows or exits loop | `wip/explore_<topic>_findings.md` |
| 4. Crystallize | Evaluate artifact type, user confirms | `wip/explore_<topic>_crystallize.md` |
| 5. Produce | Author the outcome, or hand off to the command that owns it | Terminal document, issue, or parent handoff |

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
| `references/phases/phase-5-produce-rejection-record.md` | Phase 5, rejection record (authored here) |
| `references/phases/phase-5-produce-spike-report.md` | Phase 5, spike report (authored here) |
| `references/phases/phase-5-produce-decision.md` | Phase 5, routes to `/decision` |
| `references/phases/phase-5-produce-comp.md` | Phase 5, routes to `/comp` (private repos) |
| `references/phases/phase-5-produce-file-an-issue.md` | Phase 5, file an issue |
| `references/phases/phase-5-produce-handoff.md` | Phase 5, both parent arms (`/scope` and `/charter`) |
| `references/phases/phase-5-produce-execute.md` | Phase 5, `/execute` |
| `references/phases/phase-5-produce-deferred.md` | Phase 5, deferred type (prototype) |
| `references/quality/crystallize-framework.md` | Phase 4 (full decision framework) |
| `references/label-reference.md` | Phase 0, when the topic came from a labelled issue |
