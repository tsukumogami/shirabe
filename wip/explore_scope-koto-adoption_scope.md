# Explore Scope: scope-koto-adoption

## Visibility

Public

## Scope

Tactical

## Entry Assessment

Not run. Issue #331 carries `bug` and `documentation`, not `needs-triage`, so
the Phase 0.4 assessment does not apply. The label pre-gate reads `bug` as an
explicit skip for the adversarial demand lead, and the post-conversation
classification gate is skipped with it.

## Core Question

`/scope`'s `SKILL.md` loads whole at invocation and never unloads, so an agent
holds every one of its 968 lines -- including the only passage in the file that
argues an outcome is worth wanting, and that outcome is a smaller artifact set --
before it has done any work. That is the one defect prose cannot repair, and it
is what koto is being reached for. The question is whether `/scope` can be
expressed as a koto workflow without losing the author conversation that is
most of what `/scope` is, and if so, at what shape: koto sequencing `/scope`'s
own phases with children still dispatched inline, or the full materialized
binding `/execute` uses.

## Context

Issue #331 is a first-person incident report. An agent invoked `/scope`, followed
its structure, produced only the terminal PLAN, and wrote a Status section
asserting the upstream artifacts had been consolidated away -- using the skill's
own reader-economy argument as the justification. The author's framing, which
survives unless evidence contradicts it: the process is the product; an artifact
is a materialization of a step, the sink for the step that produced it and the
source for the step that follows. Running the chain is not a way to obtain four
documents.

A prior exploration ran two full rounds against #331 on a prose-and-framing
framing and completed through crystallize. Its research is the input to this run
and is not re-derived here. What it established, and what binds this exploration:

- Every phase reference in `/scope` is already correctly bound to its phase.
  `phase-0-setup.md` and `phase-resume.md` never mention consolidation. The
  residue is that `SKILL.md` arrives whole. Prose can shrink that file; it
  cannot make it arrive in pieces.
- koto buys instruction sequencing and gating, not isolation. `koto-user/SKILL.md`
  states it flatly: koto "doesn't launch child agents -- you do that yourself."
  A design that assumes a context boundary will build toward one that does not
  exist.
- Neither dispatch binding was ever artifact-carrying. The pattern's Layer-1
  mechanism is "a parent hands a child a name and a topic key". So the sourcing
  property proposed in #331 -- an agent that skipped a hop holds nothing to pass
  along -- is not reachable by changing the binding, and that framing is dropped.
- The materialized binding passes children *more* context, not less
  (`cross-issue-context.md`).
- What the binding does buy is gating: a `context-exists` gate makes the parent
  unable to skip a hop and still finish. That is an enforcement-hardness upgrade
  on `/scope`'s existing R20 check, which today is prose the agent runs against
  itself. Weaker than the sourcing property; stronger than anything available now.
- The deciding obstacle is shape, not effort. `/execute` drives a script-computed
  issue list with no author in the loop. `/scope` drives a 563-line author
  conversation whose unwritten parts reach children only because the inline
  binding runs them in the parent's own agent context.
- Disclosure must defer verdicts and front-load premises. "The artifact set can
  shrink" is a verdict an agent can aim at. "What this hop buys" is a premise an
  agent cannot optimize against. A workflow that defers uniformly starves its
  earliest states of purpose, which is the condition that produced #331.
- koto governs when a directive arrives, never what it says. A koto-driven
  `/scope` whose first state delivers the current `## Why the Artifact Set
  Shrinks` reproduces #331 with better plumbing. The framing content work is
  carried inside this effort, not replaced by it.

Costs already established for full materialization, not to be re-derived: four
new koto templates (dominant, structural -- `/scope`'s children ship none and
koto's E9/F5 compile rules require one each, over skills 900-2700 lines long);
the eight-step per-child loop re-expressed as states including the ~270-line
consolidation judgment; dual state alongside the 255-line `wip/` schema; the
360-line artifact-status resume ladder, which `/execute`'s home-PR-keyed
solution does not transfer to because `/scope` has no PR mid-Phase-2; koto eval
fixtures from scratch. Pattern text is cheaper than feared -- only the
Observability Surface would widen.

## In Scope

- Whether a conversational parent can be expressed as a koto workflow at all,
  and what happens to the Phase 1 author dialogue and its Proceed / Adjust /
  Bail gates.
- Two candidate adoption shapes, ranked against each other by evidence: koto as
  `/scope`'s own phase substrate with inline child dispatch, versus the full
  materialized binding. The prior research priced only the second.
- What koto mechanically delivers into an agent's context at each state, and
  whether a koto-driven `/scope` still loads a whole `SKILL.md`.
- Gating: what is available, what `/scope` would gate on, how defeatable it is.
- Placement of the already-drafted replacement prose across a state sequence,
  under defer-verdicts / front-load-premises.
- Whether `/scope` and `/charter` can sit on different substrates, and what
  parent-skill-pattern conformance text moves if they do.

## Out of Scope

- Deterministic post-hoc validation that an agent executed the steps. Ruled out
  by the author. koto gating is a substrate property rather than a checker, and
  the distinction stays sharp.
- Relocating the closed write-target set out of `SKILL.md`. Established as
  theatre: the terminal address appears in the Overview's second paragraph and
  five other places in the same file, and `parent-skill-security.md:49-73` binds
  the set to `SKILL.md` by name and requires concrete paths.
- The sourcing property as a design target. Falsified.
- Editing, re-scoping, or closing `tsukumogami/shirabe#320`.
- `tsukumogami/dot-niwa-overlay#7` and `tsukumogami/niwa#258`.
- Committing `/charter` to the adoption. Only whether the parents may diverge.

## Research Leads

1. **What happens to `/scope`'s Phase 1 author conversation under a koto binding, and what actually serializes the unwritten parts?** (lead-conversation-under-koto)
   The prior run named this the deciding obstacle and could only bound it. Phase 1
   discovery is 563 lines of author dialogue with Proceed / Adjust / Bail gates,
   and its unwritten content reaches children today only because the inline
   binding runs them in the parent's agent context. Establish what koto offers a
   workflow that has a human in the loop mid-run, whether an interactive state is
   expressible, and what mechanism would write conversational content into koto
   context at each hop.

2. **Is "koto sequences a parent's own phases, children dispatched inline" a legal and supported koto shape?** (lead-substrate-shape)
   Nobody has asked. Both shipped shirabe adopters use koto to materialize
   children. If a koto workflow can instead deliver directives to the same agent
   that keeps calling the Skill tool inline, it targets the residue directly and
   skips the four child templates that dominate the materialization cost. Find
   out whether koto's template model, gate types, and compile rules permit it,
   and whether anything in koto's own docs names or forbids the pattern.

3. **What does koto mechanically put into an agent's context at each state, and does a koto-driven `/scope` still load a whole `SKILL.md`?** (lead-disclosure-mechanics)
   The claimed win is progressive disclosure. Verify it at the mechanism level:
   what a `koto next` response contains, whether a directive substitutes for a
   phase reference or supplements it, what the agent must read to bootstrap the
   session at all, and therefore what actually shrinks. If the bootstrap surface
   is still a full skill file, the win is smaller than stated and the design has
   to know that up front.

4. **Who ticks a child session in `/execute` today?** (lead-child-ticking)
   `execute.md:428-430` asserts the coordinator delegates to a fresh child and
   reads only status. Two `koto next` calls ship, both on the parent's own
   session, and nothing in `skills/execute/` mentions the Agent tool,
   `--needs-agent`, or `unassigned_children`. Establish what actually happens
   before designing against it. If no boundary exists anywhere in the repo, that
   is a stronger and cleaner disposition than "the boundary would buy nothing
   here."

5. **What gates are available, what would `/scope` gate on per hop, and how cheaply can a parent satisfy a gate without doing the work?** (lead-gating-strength)
   Gating is the one thing the prior research found genuinely buyable. Price it
   honestly: enumerate koto's gate types and their evaluation semantics, draft
   what each `/scope` hop would gate on, and adversarially ask what a motivated
   agent does to advance a state it has not earned. An upgrade over R20 that is
   defeated by one `koto context add` is worth knowing about before it is
   designed in.

6. **Which of the drafted replacement passages are premises that belong in the bootstrap, and which are verdicts that must arrive at their state?** (lead-content-placement)
   The framing content survives the reframe and rides inside this effort. A first
   draft exists: a lede purpose statement, four per-hop passages, a rewritten
   `## Consolidation Judgment` as a bound rather than an argument, replacements
   for three licensing sentences, and a `## The Chain Is a Constant` section.
   Map each onto a state sequence under defer-verdicts / front-load-premises and
   say where each lands and why. React to the draft rather than treating it as
   settled.

7. **Can `/scope` and `/charter` sit on different substrates under the parent-skill pattern, and what conformance text moves if they do?** (lead-parent-divergence)
   `/charter` is the other consumer of the same pattern, with the same phase
   structure and the same three exit paths, and it has no reported failure
   driving it. The pattern already anticipated a second parent adopting the
   second binding. Establish whether it anticipates parents diverging on
   substrate, which of the seven required structural elements are binding-neutral,
   and what would have to change for the two to differ without breaking
   conformance.
