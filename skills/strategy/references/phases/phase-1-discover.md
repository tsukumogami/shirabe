# Phase 1: Discover

Conversational scoping to ground the bet candidate and the Strategic Context.
Phase 1 routes on entry mode: upstream paths produce a bet candidate derived
from the upstream content; freeform topics produce a bet candidate from a
short directed conversation; cold-start invocations begin with a wider scoping
exchange before landing on a topic.

## Goal

By the end of Phase 1 the workflow should have:

- A bet candidate stated as a falsifiable hypothesis. The shape is "We bet
  that <thesis> ... and we will know it is invalidated when <condition>." The
  candidate is not yet load-bearing; Phase 2's drafting and Phase 4's jury
  refine it.
- An anchor for Strategic Context: either an upstream VISION (most common),
  an upstream PRD (when STRATEGY is being authored to operationalize a feature
  bet), or — for org-scope strategies without an upstream VISION — a set of
  org-level strategic artifacts or first-principles framings the strategy
  builds on.
- A working understanding of the Building Blocks the strategy will likely
  decompose into. Phase 3 owns the actual decomposition; Phase 1 just needs
  enough signal to confirm the strategy operates at the right altitude.

## Resume Check

If `wip/strategy_<topic>_discover.md` exists, Phase 1 already ran. Re-read it
and skip to Phase 2.

If the file does not exist, proceed with the entry-mode router below.

## 1.1 Route on Entry Mode

Read `wip/strategy_<topic>_context.md` and dispatch on the recorded entry mode.

### Mode: Upstream VISION

The most common entry. The user invoked `/strategy <path>` where `<path>`
resolves to a `docs/visions/VISION-*.md` file inside the repo.

1. Load the upstream VISION and read its Thesis, Audience, Org Fit, and
   Success Criteria sections.
2. Identify the slice of the VISION's thesis that this strategy will
   operationalize. STRATEGY does not re-justify the long-term thesis; it picks
   up a piece of that thesis and articulates the medium-term bet about how to
   realize it.
3. Draft a bet candidate that names the falsifiable hypothesis. Frame it as
   "We bet that <thesis> realizes <piece of VISION>" with explicit
   invalidation conditions.
4. Sketch Strategic Context: which framings carry forward from the VISION,
   and which framings are introduced fresh by the strategy.

Present the bet candidate and the Strategic Context sketch to the user in a
single message. Ask the user to confirm or redirect. Do not prompt them
through every dimension — the upstream VISION carries most of the framing
load.

### Mode: Upstream PRD

The user invoked `/strategy <path>` where `<path>` resolves to a
`docs/prds/PRD-*.md` file inside the repo. This is less common but supported:
the user wants a STRATEGY that operationalizes a PRD's bet at medium-term
altitude (the PRD's requirements then become some — not all — of the
Downstream Artifacts).

1. Load the upstream PRD and read its Problem Statement, Goals, and Decisions
   and Trade-offs sections.
2. Identify the strategic bet the PRD implicitly makes. PRDs often encode a
   falsifiable hypothesis in the framing of their goals; the STRATEGY makes
   that bet explicit.
3. Draft a bet candidate grounded in the PRD's stated goals and an
   articulation of which goals are downstream of the bet.
4. Sketch Strategic Context: PRDs are not usually self-justifying at the
   altitude STRATEGY operates, so the sketch should name what the strategy
   adds (the falsifiability framing) versus what the PRD already provides
   (the requirements decomposition).

Confirm the candidate with the user as in the VISION mode.

### Mode: Freeform Topic

The user invoked `/strategy <topic-string>` with a slug but no path. Run a
short directed conversation:

1. Open with "What's the bet you want to capture? Frame it as a falsifiable
   hypothesis we could be wrong about."
2. Probe for the upstream that grounds the bet. Ask whether a relevant VISION
   exists ("Is there a VISION doc this would build on?"). If yes, ask the user
   for the path; if no path is given but a VISION clearly exists, find it
   yourself by searching `docs/visions/`. If still no VISION emerges, ask
   about the strategy's scope — project or org.
3. For org-scope strategies that lack an upstream VISION, ask which existing
   strategic artifacts the strategy builds on, or whether the Strategic
   Context will be grounded in first-principles framing. This is explicitly
   supported and the Strategic Context format accommodates it.
4. Ask 1-2 questions about Building Blocks to confirm altitude — "What are
   the 5-8 coordinated workstreams that operationalize this bet?" — but do
   not push for full decomposition. The signal is altitude, not completeness.

Stop the conversation when the bet candidate, Strategic Context anchor, and
altitude check are all surface-level clear. Do not over-scope; Phase 2 owns
the drafting.

### Mode: Cold Start

`$ARGUMENTS` was empty. Ask the user what strategic conversation they want
to have, then redirect to the appropriate mode:

> "Are you starting from an existing VISION, an existing PRD, or a topic
> you'd like to scope from scratch?"

If they name an upstream, ask for the path and re-enter the corresponding
mode. If they name a topic, derive a slug (subject to the Phase 0 constraint)
and re-enter Freeform Topic mode. If they're genuinely uncertain whether
STRATEGY is the right artifact type, suggest `/explore` instead.

## 1.2 Handle the Org-Scope-Without-Upstream-VISION Case

Some org-scope strategies legitimately have no upstream VISION. Examples
include strategies that synthesize across multiple org-level artifacts, or
strategies that propose a new strategic direction the org has not yet
codified in a VISION.

The flexible Strategic Context section (per the format reference) supports
this case: it requires content properties (the bet must stand alone in
prose, the surrounding org context must be summarized for a reader who lands
on the document cold) without requiring a literal upstream-VISION quote.

For this case, Phase 1 produces the Strategic Context anchor as a short list:

- 2-4 strategic artifacts the strategy builds on (paths or names)
- The org-level framings the strategy adopts (1-3 sentences each)
- Any first-principles framings the strategy introduces (1-2 sentences each)

Phase 2 expands these into the Strategic Context prose. Phase 4's altitude
reviewer treats the absence of an upstream VISION as a question to answer
("does the Strategic Context stand alone?"), not as a failure mode.

## 1.3 Building Blocks Altitude Check

Before exiting Phase 1, do a quick altitude check by sketching the likely
Building Blocks. The sketch is informal:

- "What are the 5-8 coordinated workstreams this bet decomposes into?"
- "Could a downstream DESIGN doc plausibly land for each one?"

If the sketch produces 0-2 workstreams, the topic may be at PRD altitude
(too narrow for STRATEGY). If it produces 15+ workstreams, the topic may be
at VISION altitude (too broad). Either signal is a reason to confirm with the
user before committing to Phase 2 drafting.

This is a sanity check, not a gate. Phase 3 owns the full decomposition;
Phase 4's altitude reviewer applies the granularity rubric formally.

## 1.4 Persist Discovery

Write `wip/strategy_<topic>_discover.md` with the following:

```markdown
# /strategy Discovery: <topic>

## Bet Candidate
<falsifiable hypothesis with invalidation conditions>

## Strategic Context Anchor
<upstream VISION path, OR upstream PRD path, OR list of org artifacts and framings>

## Building Blocks Sketch
- <workstream 1>
- <workstream 2>
- <workstream 3>
- ...

## Altitude Notes
<any signals from the altitude check that may affect Phase 2 or 4>

## Open Questions for Drafting
<things to flag to the user during Phase 2 drafting>
```

Update `wip/strategy_<topic>_context.md`'s `## Phase` line to `1`.

## Quality Checklist

Before proceeding:
- [ ] Bet candidate is a falsifiable hypothesis (not a problem statement)
- [ ] Strategic Context anchor is identified (upstream path or org artifact list)
- [ ] Building Blocks sketch contains 3-12 workstreams (altitude sanity check)
- [ ] Org-scope-without-upstream-VISION case is handled if applicable
- [ ] User confirmed the bet candidate direction

## Artifact State

After this phase:
- Context file at `wip/strategy_<topic>_context.md` (Phase 0)
- Discovery file at `wip/strategy_<topic>_discover.md` (this phase)
- No STRATEGY draft yet

## Next Phase

Proceed to Phase 2: Draft (`phase-2-draft.md`)
