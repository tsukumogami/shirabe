# Content-Quality Verdict: BRIEF-scope-chain-mandatory-steps

## Verdict

FAIL

One blocking defect: the frontmatter `problem` field contradicts the Problem
Statement body on whether `/scope` is one of the stale surfaces. Everything else
on the rubric passes, several parts strongly. The fix is two lines.

## Per-Criterion

### 1. Problem Statement is a problem

PASS on shape, FAIL on frontmatter consistency.

The section states a gap, not a fix. It opens with what changed and what did not
follow: "The corpus did not finish moving. Four surfaces still describe the world
before #302, and they are not footnotes — they are the surfaces an author touches
first." Nothing in the section proposes a skill, a router, or an edit; each
paragraph names a surface and the specific way it contradicts the shipped model.
It closes on cost rather than remedy — "An author who reads `/explore` first is
told to pick an artifact type, which is the decision #302 removed." That is the
gap a reader feels before the feature exists, which is exactly what the rule
asks.

It also stands alone. A cold reader gets #280's argument, #302's replacement, and
the current model ("runs BRIEF → PRD → DESIGN → PLAN on every invocation and
reduces the set afterward, per hop, against two bodies that exist") inside the
first paragraph, without opening an upstream doc.

The defect is the frontmatter. `problem:` reads:

> /scope and /execute state the post-#302 model; /explore, the shared
> parent-skill pattern both parents inherit, and /scope's own eval suite still
> state the model #302 replaced.

That places `/scope` in the correct-model column and names three stale surfaces.
The body names four and `/scope` is one of them — the entire fourth paragraph is
about `/scope`'s own prose ("states the current model in its own prose and then
asks a question that contradicts it"), and IN-list bullet four is `/scope` Phase
1's prompt plus five stale paragraphs beside it. The exploration backs the body,
not the summary: `wip/explore_scope-chain-mandatory-steps_findings.md:300-328`
lists "The four surfaces that have not caught up" and item 4 is "A handful of
single-paragraph staleness in `/scope`'s own prose." The format reference is
explicit that `problem:` carries the "same content the Problem Statement section
elaborates in prose," and agent workflows parse frontmatter — a downstream reader
who takes the summary at face value scopes three surfaces and drops a quarter of
the work.

### 2. User Outcome is outcome-shaped

PASS.

The section leads with a state change, not a build list: "An author never has to
decide which chain step to start at, and never reads two answers about whether
they could have." Each following paragraph names a user whose experience changes
— the author reaching shirabe cold, the author entering the tactical chain, the
maintainer reading the shared pattern, the agent graded by the evals — and says
what is different for them. No paragraph enumerates parts that get built; the
closest it comes is "The router asks which conversation they are having, not
which document they want," which is still an experience, not a component.

The negative-space framing works in its favor: "What goes is the question mark"
tells a downstream PRD author what the user stops encountering without
prescribing the replacement prose.

Coverage against the `outcome:` frontmatter is adequate — never deciding a step,
entry points rather than chain-internal children, and every surface agreeing all
appear in both. The frontmatter's "the chain runs whole, and what did not earn
its keep is folded after the fact" is carried in the body only implicitly ("they
are told what will run and why each child fires"); it is stated outright in
Journey 3 instead. Non-blocking, but see Optional 1.

### 3. Journeys concrete and distinct

PASS.

Each of the five names a user, a trigger, and an outcome shape, and each enters
from a different surface:

1. **An author who does not know what they need.** User: a contributor who
   "cannot say whether it needs requirements, a design, or just a fix." Trigger:
   runs `/explore`. Outcome: "routes them to one of four places to start — not to
   'write a PRD' or 'write a design doc.'" Entry point: the router.
2. **An author entering the tactical chain.** User: an author running `/scope` on
   a feature. Trigger: invocation, before any child fires. Outcome: they read the
   per-child verdicts and the chain starts, with no adjust prompt and no bail
   "whose two branches cannot execute from where they stand." Entry point: the
   Phase 1 proposal.
3. **An author who knows the framing is already settled.** User: an author with
   problem and requirements settled who "wants to talk about architecture."
   Trigger: arriving at `/scope` with prior framing in hand — the case the
   direct-invocation redirect currently answers. Outcome: the whole chain runs and
   the skill says why, "rather than a redirect that one paragraph offers and
   another retires." Entry point: the escape-hatch prose, not the proposal.
4. **A maintainer building a third parent skill.** User and trigger are concrete
   (opens `references/parent-skill-pattern.md` to bind a new parent). Outcome: the
   model stated in one place plus a legitimate reason vocabulary. No skill
   invocation at all — a genuinely different entry.
5. **An agent graded by the eval suite.** Trigger: runs against
   `skills/scope/evals/evals.json`. Outcome: every scenario describes the
   implemented model. Thinnest of the five but complete, and it is the only
   journey through the executable surface.

Journeys 2 and 3 are the pair worth checking, since both begin with an author
invoking `/scope`. They do not collapse: 2 exercises the confirmation prompt (the
author is asked something), 3 exercises the shorter-chain redirect (the author is
offered a way out of the chain). Different surfaces, different frictions,
different fixes downstream. Journey 3 also carries the load of stating the
post-hoc fold — "If the BRIEF turns out to do no work the PRD does not, it is
absorbed after both exist" — which no other journey does.

### 4. Scope Boundary has real exclusions

PASS, and this is the strongest section.

The OUT list is seven items and none is filler. Every one is a boundary a
downstream PRD author could plausibly cross by accident, and each carries the
reason it sits outside:

- Porting a consolidation judgment to `/charter` — reachable by symmetry, and the
  brief says why it is a separate question ("STRATEGY is the durable audit trail
  and ROADMAP is a working artifact retired by the plan cascade, which is a
  different disposal model from absorb-into-survivor").
- Retiring `/charter`'s roadmap declination — the single most likely accidental
  crossing, since the declination clause is named as a defect in the shared
  pattern. Held out explicitly: "The model is restated around it rather than
  against it."
- `/execute` — a parent skill in an audit of parent skills; the exclusion says it
  already states the model correctly.
- `crates/shirabe-validate/src/formats.rs` — the code someone would assume needs
  matching edits; excluded because "the prose and the evals are what lagged."
- The child skills' phase workflows, `/explore`'s research loop, and re-opening
  what #302 settled — each a plausible spillover, each bounded.

The IN list is equally specific, down to named surfaces and files, so a PRD author
knows where the feature ends on both sides.

### 5. Open Questions defer rather than block

PASS.

Both defer a framing detail and neither is a brief-stopper. Q1 ("What does 'a
shorter chain' mean to an author now?") is a genuine framing question the brief
cannot settle from where it stands — absorption "reduces the artifact set but not
the conversation" — and it names the three live answers (retired, narrowed,
re-justified) without picking one. Journey 3 is written to hold under all three,
so the brief does not quietly presume an answer. Q2 (where the interactive entry
to bail-handling lives) is a reachability question created by a change the brief
does scope, which is the right shape for a deferral.

Neither is of the "we don't know if this feature should exist" kind. The brief
resolves that question in its own Problem Statement.

### Content boundaries

No blocking crossing. Two places sit near the line and are worth naming.

The IN list occasionally prescribes the fix rather than bounding the surface: the
`/explore` bullet ends "replaced by a router over chain entry points," and the
pattern-doc bullet asks for "a bounded `chain_skipped[].reason` vocabulary" and
the declination clause "restated so it reads as a preserved instance of the model
rather than an exception." Read strictly, those are requirements. Read against
the User Outcome, they are restatements of framing the brief already established
("routed to a place to start... rather than to a step inside one of those
chains", "along with what a skip may legitimately mean"), so they bound rather
than specify. They stay inside the line, but a PRD author should not treat them as
settled requirements.

The Problem Statement carries a lot of field- and line-level detail — the orphan
`chain_revised:` field, the `Proceed / Adjust / Bail?` prompt, `--auto`, the
`chain_skipped[].reason` free text. All of it is diagnostic evidence that the
surfaces are stale, not architecture for the fix, so it is inside the boundary.
It does make the section read as an inventory in places (see Optional 2).

No acceptance criteria, no user stories, no interface shapes, no task
decomposition, no sequencing of this feature against others.

## Required Changes

1. **Fix the frontmatter `problem:` field so it agrees with the body on
   `/scope`.** It currently reads "/scope and /execute state the post-#302 model"
   and names three stale surfaces; the Problem Statement says "Four surfaces still
   describe the world before #302" and devotes its fourth paragraph to `/scope`'s
   own prose contradicting itself, and IN-list bullet four scopes exactly that.
   `wip/explore_scope-chain-mandatory-steps_findings.md:300-328` confirms the body
   is the accurate count. Rewrite the summary so `/scope` appears as internally
   split rather than as a correct-model surface — something on the order of
   "`/execute` states the post-#302 model and `/scope` states it and then
   contradicts it; `/explore`, the shared parent-skill pattern both parents
   inherit, and `/scope`'s own eval suite still state the model #302 replaced."
   Keep it within the 2-4 line limit.

## Optional Improvements

1. **Carry the fold into the User Outcome.** The `outcome:` frontmatter says "the
   chain runs whole, and what did not earn its keep is folded after the fact," but
   the section only implies it; the explicit statement lives in Journey 3. One
   clause in the second or third paragraph would close the gap and make the
   section independently complete.

2. **Tighten the Problem Statement's fifth and sixth paragraphs.** The eval and
   `/scope` paragraphs carry named fields, flag names, and scenario names. Every
   detail is load-bearing as evidence, but the density makes the section read as a
   defect inventory in the middle before the closing paragraph recovers the
   framing. Moving the most granular items (the orphan `chain_revised:` field, the
   `--auto` behavior) into the IN list, where their siblings already live, would
   let the problem paragraphs stay at problem altitude without losing anything.

3. **Reframe Open Question 2 to the framing half.** "Where does the interactive
   entry to bail-handling live?" asks for a placement, which is closer to design
   than to framing. The question the brief actually defers is whether the
   abandonment exit must stay reachable from the author's flow once it leaves the
   Phase 1 prompt, and from where. Asking it that way keeps the PRD's Decisions and
   Trade-offs section as the right closure surface.

4. **Journey 5 could name its entry more concretely.** "An agent runs against
   `skills/scope/evals/evals.json`" is a valid trigger, but the journey would read
   less like a restatement of the eval IN-list item if it named the moment — an
   agent optimizing against the suite reaching scenario
   `consolidation-keep-at-unmapped-hop` and being pulled toward the retired model.
