---
schema: brief/v1
status: Accepted
problem: |
  shirabe produces multiple artifact types, but whether each one stays
  durable in docs/ or gets deleted once its job is done is decided
  skill-by-skill with no documented per-skill contract. The
  inconsistency leaves dead artifacts in the tree and skill authors
  with no canonical place to look up the rule.
outcome: |
  Each shirabe skill names, in its own prose, whether its artifact is
  durable or working and — for working artifacts — the condition that
  retires it. The completion cascade learns the same convention so
  retired artifacts disappear from docs/ alongside the PLAN, and a
  skill author can read one skill to learn that artifact's contract.
---

# BRIEF: shirabe-artifact-decision-contract

## Status

Accepted

The downstream PRD picks up the requirements: which existing skills
restate their contract in prose, the exact wording of the durable
versus working distinction, the completion condition for the working
artifacts the cascade handles today, and the cascade's extension point
for future working artifacts.

## Problem Statement

shirabe has seven artifact types in the main pipeline — VISION,
STRATEGY, ROADMAP, BRIEF, PRD, DESIGN, PLAN — plus a private-only
COMP. For each type, an implicit decision lives in the producing
skill's cleanup logic: does this artifact stay in `docs/` forever as
part of the project's audit trail, or does it disappear once its
purpose has been fulfilled? The decision is real, but it is not
documented per skill, and it is not consistent across the pipeline.

The completion cascade today treats one artifact, PLAN, as working:
when a single-PR PLAN finishes, the cascade deletes the PLAN file and
walks the upstream chain transitioning every other node to its
terminal status. Every other artifact type stays durable forever,
including ROADMAP, even after the work it sequenced is complete.

Three gaps follow from this implicit, hard-coded decision:

- **ROADMAP-bloat.** A ROADMAP whose features are all Done and whose
  referenced issues are all closed has finished its sequencing job,
  but it stays in `docs/roadmaps/` indefinitely. The directory grows
  with dead context — old sequencing decisions reviewers must learn to
  skim past — and there is no documented rule that says when, or
  whether, a ROADMAP should ever come out.
- **Missing canonical contract.** A skill author writing a new skill,
  or extending an existing one, has nowhere to look up "what is the
  durable-versus-working contract for this artifact, and where is that
  decision recorded?" The cleanup behavior lives inside the cascade
  template's hard-coded PLAN branch; the rationale for why PLAN is
  the only working artifact lives nowhere. Two authors reading the
  pipeline will form different mental models of the rule.
- **No extension point for the cascade.** The cascade's PLAN-deletion
  step is a one-off branch in its script. If any other artifact ever
  becomes working — even one — the cascade has no pluggable place for
  that artifact's completion condition to participate. Each new
  working artifact would require a fresh hard-coded branch and the
  rationale-lives-nowhere problem compounds.

The framing problem the brief captures is the absence of a documented
contract, not the choice of which artifacts should be working versus
durable. Whether ROADMAP (or any other type) becomes working is a
downstream decision; what the work has to fix is the missing place to
write that decision down and the missing extension point for the
cascade to honor it.

## User Outcome

A skill author writing or extending a shirabe skill reads that skill's
own prose and learns the artifact's lifecycle contract: whether it
stays durable in `docs/`, or whether it is working with a named
completion condition that retires it. The author does not have to
infer the rule from cleanup-script source or from comparing against
other skills.

A reviewer browsing `docs/` sees artifacts that are still doing useful
work. Artifacts whose job is complete and whose lifecycle rule says
they retire are gone from the tree, taken out by the cascade alongside
the PLAN. There is no monotonic accumulation of dead context.

A future maintainer who decides another artifact type should become
working — or who builds a new artifact type from scratch — has an
extension point in the cascade for that artifact's completion
condition. They do not have to fork a hard-coded branch; they add a
participant alongside the PLAN handler, document the contract in the
producing skill's prose, and the convention holds.

## User Journeys

### Journey 1: A skill author looks up the artifact lifecycle contract

A skill author is writing a new shirabe skill, or modifying an
existing one, and needs to decide what happens to the artifact once
its job is done. They open the producing skill's prose and read the
contract: this artifact is durable, or this artifact is working and
retires when the named condition holds. The decision is in the skill,
not buried in cascade source or implied by comparing the skill to its
siblings. The author neither has to guess nor has to discover the
convention by reading the cascade script.

### Journey 2: A reviewer reads docs/ and finds no stale ROADMAPs

A reviewer surveys `docs/` to understand the project's current state.
The ROADMAPs they see in `docs/roadmaps/` describe initiatives that
are still in motion — features still to ship, issues still open. A
ROADMAP whose features are all Done and whose issues are all closed
is not there; the cascade retired it when its completion condition
held. The reviewer's read of `docs/` reflects work currently in
flight, not the union of every initiative ever undertaken.

### Journey 3: A future work-on extension participates in the cascade

A maintainer extending `/work-on` — or any future cascade-using
skill — wants a newly working artifact type to retire on completion
alongside the PLAN. They add a step to the cascade for that
artifact's completion condition: the step names the artifact, names
the condition under which it retires, and runs the deletion when the
condition holds. The cascade does not require its existing PLAN
branch to be rewritten. The new step composes with the existing one,
and the convention scales as more working artifacts arrive.

## Scope Boundary

This brief covers the contract that names which shirabe artifacts are
durable versus working, where that contract is documented, and the
cascade's extension point for honoring it on completion.

The scope holds the following inside:

- **A durable-versus-working contract documented per skill.** Each
  shirabe skill names, in its own prose, the lifecycle contract for
  the artifact it produces — durable, or working with a completion
  condition. The contract lives where the skill lives, so an author
  reading the skill learns the rule that governs its artifact.
- **The ROADMAP lifecycle decision.** The brief covers the framing
  that ROADMAP-bloat is a problem to address; the specific decision
  about whether ROADMAP becomes working, and the exact completion
  condition if so, belongs to the downstream PRD and design.
- **An extension point in the completion cascade.** The cascade gains
  a place for working-artifact handlers to participate alongside the
  existing PLAN-deletion step, so any artifact the contract names as
  working can retire on its named condition without forking a
  hard-coded branch.
- **Prose-only documentation surface.** The contract is captured in
  skill prose and cascade behavior; no new CLI subcommand, no new
  substrate, no new artifact type, and no schema change is introduced
  by the work this brief frames.

The scope explicitly excludes:

- **Amplifier-layer extensions that auto-derive completion from
  evidence.** A future world where the cascade reads richer
  completion evidence — issue closure signals beyond filename
  matching, downstream-consumer state, derived rollups — to decide
  retirement is separate downstream work. The brief covers the
  prose-and-cascade-step contract; the amplification of that contract
  with evidence-driven automation is deferred.
- **Making BRIEF, PRD, or DESIGN working artifacts.** These three
  carry the audit trail of why a feature was framed, what it
  requires, and how it is built. Their durability is what lets a
  future reader reconstruct the chain. The brief frames them as
  durable by intent, not by accident; flipping them to working is out
  of scope and would defeat the chain's purpose.
- **Re-litigating PLAN's existing working behavior.** PLAN already
  retires on single-PR completion, the cascade already handles it,
  and that handling stays as-is. The work names PLAN as the existing
  precedent the new contract generalizes; it does not change PLAN's
  cleanup path.
- **CLI extensions or new substrate.** No new `shirabe` subcommand,
  no new validation rule expressed in code, no new format check. The
  contract is documented in skill prose and honored by the cascade's
  composition of handler steps.

## References

- BRIEF authoring precedent for cascade-touching framing:
  `docs/briefs/BRIEF-scope-completion-cascade.md`.
- BRIEF authoring precedent for engine-versus-bash separation of
  lifecycle decisions: `docs/briefs/BRIEF-finalize-chain.md`.
- BRIEF format reference (lifecycle, validation, content boundaries):
  the brief format reference under the brief skill's references.
