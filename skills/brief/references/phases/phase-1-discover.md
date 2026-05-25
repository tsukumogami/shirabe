# Phase 1: Discover

Conversational scoping to ground the feature's problem and intended outcome.
Phase 1 routes on entry mode: upstream paths produce a problem/outcome candidate
derived from the upstream content; freeform topics produce a candidate from a
short directed conversation; cold-start invocations begin with a wider scoping
exchange before landing on a feature.

## Goal

By the end of Phase 1 the workflow should have:

- A **problem candidate**: a one-paragraph statement of the problem the feature
  solves, framed as a problem the user has — not a solution in disguise. The
  candidate is not yet load-bearing; Phase 2's drafting and Phase 4's jury refine
  it.
- An **outcome candidate**: a one-paragraph statement of what a user should
  experience once the feature exists, framed as an outcome — not a feature list.
- An anchor for grounding: either an upstream ROADMAP or PRD (when the feature is
  already named in the chain), or — for freeform and cold-start invocations — the
  conversation itself.
- A rough sense of the journeys the feature serves. Phase 3 owns the actual User
  Journeys section; Phase 1 just needs enough signal to confirm the feature is one
  framable thing, not three.

The anchor is the problem/outcome pair. A brief makes no falsifiable bet; there is
no hypothesis to articulate here.

## Resume Check

If `wip/brief_<topic>_discover.md` exists, Phase 1 already ran. Re-read it and skip
to Phase 2.

If the file does not exist, proceed with the entry-mode router below.

## 1.1 Route on Entry Mode

Read `wip/brief_<topic>_context.md` and dispatch on the recorded entry mode.

### Mode: Upstream ROADMAP

The user invoked `/brief <path>` where `<path>` resolves to a
`docs/roadmaps/ROADMAP-*.md` file inside the repo. This is the common entry: the
roadmap named the feature, and the brief frames it before requirements start.

1. Load the upstream ROADMAP and find the feature this brief frames. Read its
   line-item description and any sequencing rationale around it.
2. Draft a problem candidate: what problem does this feature solve for a user? A
   roadmap line item names *what* gets built; the brief names *why it matters to a
   user*. Pull the why out of the roadmap framing and state it as a problem.
3. Draft an outcome candidate: what should a user be able to do, or stop having to
   do, once the feature ships? State it as an experience, not as the feature's
   parts.
4. Note the journeys the feature plausibly serves — who triggers it, and what they
   get.

Present the problem and outcome candidates to the user in a single message. Ask
them to confirm or redirect. Do not prompt through every dimension — the roadmap
carries the naming load.

### Mode: Upstream PRD

The user invoked `/brief <path>` where `<path>` resolves to a `docs/prds/PRD-*.md`
file inside the repo. Less common, and Phase 0's artifact decision may already have
recommended hand-off for this case (a PRD usually means the framing exists). If the
decision was `produce`, the user wants a brief that captures framing the PRD
assumed but never wrote down.

1. Load the upstream PRD and read its Problem Statement, Goals, and User Stories.
2. Extract the feature framing the PRD took as given: the problem it solves and the
   outcome it targets. The PRD encodes both implicitly in its requirements; the
   brief makes the framing explicit and standalone.
3. Draft problem and outcome candidates grounded in that framing.

Confirm the candidates with the user as in the ROADMAP mode.

### Mode: Freeform Topic

The user invoked `/brief <topic-string>` with a slug but no path. Run a short
directed conversation:

1. Open with "What feature are you framing, and what problem does it solve for a
   user? State the problem first — we'll get to the solution later."
2. Probe for the outcome: "Once this feature exists, what can a user do, or stop
   having to do, that they can't today?"
3. Ask whether an upstream exists that names this feature ("Is there a roadmap
   entry or an issue this maps to?"). If yes and a path is available, fold the
   upstream framing into the candidates; if a relevant ROADMAP clearly exists but
   no path was given, find it yourself by searching `docs/roadmaps/`.
4. Ask one or two questions about who the feature serves and how they reach it —
   enough to confirm the feature is one framable thing, not several. The signal is
   coherence, not completeness; Phase 3 owns the journeys.

Stop the conversation when the problem candidate, the outcome candidate, and a
rough sense of journeys are all surface-level clear. Do not over-scope; Phase 2
owns the drafting.

### Mode: Cold Start

`$ARGUMENTS` was empty. Ask the user which feature they want to frame, then
redirect to the appropriate mode:

> "Are you starting from a roadmap entry, an existing PRD, or a feature you'd like
> to frame from scratch?"

If they name an upstream, ask for the path and re-enter the corresponding mode. If
they name a feature, derive a slug (subject to the Phase 0 constraint) and re-enter
Freeform Topic mode. If they're genuinely uncertain whether a brief is the right
artifact — for instance, the framing already exists and a PRD is the real need —
revisit the Phase 0 artifact decision, or suggest `/explore` if the conversation is
still open-ended.

## 1.2 Problem-vs-Solution Check

The most common brief failure is a Problem Statement that is a solution wearing a
problem's clothes. Before exiting Phase 1, sanity-check the problem candidate:

- A problem names something a user struggles with, lacks, or can't do today.
- A smuggled solution names a feature and asserts its absence is the problem
  ("users can't export to CSV" is a missing feature; "users have no way to get
  their data out of the tool for use elsewhere" is a problem).

If the candidate names a specific mechanism, ask the user what the underlying user
problem is. Phase 2's drafting and Phase 4's content-quality reviewer both defend
this distinction; catching it here is cheapest.

## 1.3 Outcome-Shape Check

Run the parallel check on the outcome candidate:

- An outcome describes what a user experiences — what they can now do, what
  friction is gone, what they no longer have to think about.
- A feature list describes what the product does — its parts, screens, or
  capabilities.

If the candidate reads as a list of capabilities, ask "and what does that let the
user do?" until the answer is experience-shaped. This is the second-most-common
brief failure; Phase 4's content-quality reviewer checks it.

## 1.4 Persist Discovery

Write `wip/brief_<topic>_discover.md` with the following:

```markdown
# /brief Discovery: <topic>

## Problem Candidate
<one-paragraph statement of the user problem the feature solves>

## Outcome Candidate
<one-paragraph statement of what a user should experience>

## Grounding Anchor
<upstream ROADMAP path, OR upstream PRD path, OR "conversation only">

## Journey Sketch
- <who triggers the feature, and what they get>
- <a distinct second entry point, if any>
- ...

## Open Questions for Drafting
<things to flag to the user during Phase 2 drafting>
```

Update `wip/brief_<topic>_context.md`'s `## Phase` line to `1`.

## Quality Checklist

Before proceeding:
- [ ] Problem candidate names a user problem, not a smuggled solution
- [ ] Outcome candidate is experience-shaped, not a feature list
- [ ] Grounding anchor is identified (upstream path or "conversation only")
- [ ] Journey sketch confirms the feature is one framable thing
- [ ] User confirmed the problem/outcome direction

## Artifact State

After this phase:
- Context file at `wip/brief_<topic>_context.md` (Phase 0)
- Discovery file at `wip/brief_<topic>_discover.md` (this phase)
- No BRIEF draft yet

## Next Phase

Proceed to Phase 2: Draft (`phase-2-draft.md`)
