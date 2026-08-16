# Phase 0: Setup

Establish the working branch, resolve context, and assess the issue if it
arrived unclassified.

## Goal

Get onto a topic branch with visibility and scope resolved, ready for scoping.
If starting from a `needs-triage` issue, record what the issue looks like so the
crystallize step has it. Phase 0 assigns no labels and takes no routing
decision: the skill has one routing surface and it runs after the research, not
before it.

**Label vocabulary reference:** `references/label-reference.md`

## Resume Check

If already on a `docs/<topic>` branch and `wip/explore_<topic>_scope.md` exists,
skip to Phase 1. If the scope file doesn't exist but you're on the topic branch,
proceed from Step 0.2.

## Steps

### 0.1 Branch Setup

If already on a `docs/<topic>` branch, skip to Step 0.2.

Otherwise:
- Derive topic from `$ARGUMENTS` (issue title or provided topic string)
- Convert to kebab-case: `docs/<topic>`
- Create from latest main and switch to it
- Confirm you're on the correct branch

### 0.2 Context Resolution

Resolve visibility and scope per the Context Resolution section in SKILL.md.
Log the effective context before continuing:

```
Exploring with [Private|Public] visibility in [Strategic|Tactical] scope...
```

### 0.2a Persist Visibility to Scope File

Write the resolved visibility value to `wip/explore_<topic>_scope.md` now,
before Phase 1. This makes the value available during Phase 1 lead construction
and survives context resets.

Create or update the file with a `## Visibility` section containing exactly
the resolved value:

```markdown
## Visibility

Private
```

or

```markdown
## Visibility

Public
```

The value must be derived from the actual repo context: read the `## Repo
Visibility:` header in the nearest CLAUDE.md, or infer from path (content
under `private/` is Private; content under `public/` is Public). Do not
hardcode this value.

### 0.3 Issue Entry Point

**If starting from an issue with `needs-triage` label:** proceed to Step 0.4.

**If starting from an issue with `needs-design` label:** Gather context from
upstream strategic issues and design docs by reading any linked issues, related
design docs referenced in the issue body, and upstream artifacts noted in the
codebase. Then proceed to Phase 1.

**If starting from a plain topic (no issue):** proceed directly to Phase 1.

### 0.4 Entry Assessment

Read the issue and record what it looks like before any research has run. The
assessment is an input to the crystallize step, not a decision: whatever it
says, this step ends at Phase 1. Nothing here edits a label, stops the skill, or
sends the author to another command.

Launch 3 agents in parallel, each arguing for one category:

**Agent 1 -- needs investigation:**
Argue that this issue requires upstream artifact work before it can be implemented.
Look for: ambiguity in requirements or approach, multiple possible solutions,
technical risk, feasibility questions, cross-cutting concerns, unclear scope
boundaries.

**Agent 2 -- needs breakdown:**
Argue that this issue is well-understood but too large for one session. Look for:
clear approach but multiple independent pieces, no technical uncertainty, scope
that implies several PRs or distinct work items.

**Agent 3 -- ready:**
Argue that this issue can be implemented directly. Look for: clear requirements,
single deliverable, low risk, straightforward approach, small scope (one person,
one PR).

Each agent writes a 3-5 line assessment to chat (no files needed). Include the
issue number and a confidence level (low/medium/high).

#### Agent Prompt Template

```
You are assessing an issue from the perspective of a [ROLE]. Your assessment is
evidence for a decision made later, after research; it does not route anything.

Issue: [TITLE]
Body: [BODY]
Upstream context: [CONTEXT FROM STEP 0.3]

Evaluate which category fits best:

1. **Needs Investigation**: Has unknowns that require upstream artifact work --
   requirements unclear, approach undecided, feasibility unknown, or architectural
   choice needed
2. **Needs Breakdown**: Well-specified but too large for one session, multiple
   independent chunks, no design decisions needed
3. **Ready**: Atomic task, clear acceptance criteria, single session of work,
   no design decisions needed

Provide:
- Your recommended category (investigation/breakdown/ready)
- Brief rationale (2-3 sentences)
- Confidence level (high/medium/low)
```

#### Synthesis

After agents respond, synthesize:
1. If unanimous: that category is the result
2. If split: the majority category is the result, note dissent

Write the result to `wip/explore_<topic>_scope.md` under an `## Entry
Assessment` heading, next to the `## Visibility` value Step 0.2a wrote:

```markdown
## Entry Assessment

Result: <needs investigation | needs breakdown | ready>
Confidence: <high | medium | low>
Dissent: <the category a dissenting agent argued for, and its reason, or "none">
Signals cited: <what the agents pointed at in the issue body>
```

Then continue to Phase 1 regardless of the result. Say the result to the user in
one line so the assessment isn't invisible, and say that the exploration
continues either way.

#### What the Assessment Feeds

Phase 4 reads this section as stage-2 evidence, alongside everything the
research turned up:

- **ready** carries the file-an-issue signals: one deliverable, one person, no
  coordination, "just do it" is the right next step.
- **needs breakdown** carries a shape signal rather than an altitude one. Work
  that splits into several independent pieces reads toward `/scope`, whose
  terminal artifact is the PLAN that sequences them, or toward `/charter` when
  the pieces are separate features whose order affects delivery.
- **needs investigation** says the issue arrived with open requirements or an
  open approach, which is the chain's own signal set.

None of these is a verdict. The exploration can contradict any of them, and when
it does, the findings win: the assessment saw the issue body and nothing else.

## Quality Checklist

Before proceeding:
- [ ] On branch `docs/<topic>`
- [ ] Visibility and scope resolved and logged
- [ ] Visibility value written to `wip/explore_<topic>_scope.md` under `## Visibility`
- [ ] If from needs-triage: entry assessment run and written under
      `## Entry Assessment`
- [ ] No label added or removed, and no routing decision taken

## Artifact State

After this phase:
- On the `docs/<topic>` branch
- Context resolved (visibility + scope)
- If from an issue: entry assessment recorded, upstream context gathered
- `wip/explore_<topic>_scope.md` exists with a `## Visibility` section, plus an
  `## Entry Assessment` section when the topic came from a `needs-triage` issue

## Next Phase

Proceed to Phase 1: Scope (`phase-1-scope.md`)
