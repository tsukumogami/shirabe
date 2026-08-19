# Explore Scope: scope-process-framing

Source: tsukumogami/shirabe#331 -- "/scope argues for a smaller artifact set
before any artifact exists, and an agent can act on that argument to skip the
chain"

## Visibility

Public

## Core Question

`/scope`'s `SKILL.md` spends its only motivated argument on why the artifact set
shrinks, states that argument before any artifact exists, and never states why
the steps are run at all. An agent read it for intent, found one purpose, and
acted on it -- producing the terminal artifact and asserting the upstream
documents away in prose. What should the skill say instead, and at which point
in the disclosure order should each thing be said, so that an agent reading it
for intent finds the process rather than the reduction?

## Context

The issue is a first-person incident report written by the agent that committed
the failure. The reasoning is recovered from a transcript rather than
reconstructed: the sentence "three upstream documents restating that at three
altitudes would be ceremony" was really committed into a PLAN's Status section,
and it is the skill's own argument quoted back at it.

The load-bearing framing, from the author: **the process is the product. An
artifact is a materialization of a step -- the sink for the step that produced
it and the source for the step that follows. Running the chain is not a way to
obtain four documents.** Under that framing, "should we produce this artifact"
is not a question the chain asks; the reduction question is a narrow, local one
about whether a particular document still earns its place once it exists.

Verified ground truth at the time of scoping:

- `skills/scope/SKILL.md` is 968 lines; `skills/charter/SKILL.md` is 352.
- `## Why the Artifact Set Shrinks` (SKILL.md:472) runs ~60 lines and
  `## Consolidation Judgment` (SKILL.md:532) ~45. Neither section exists in
  `/charter`.
- The `## Workflow Phases` table (SKILL.md:285) lists phase names, one-line
  purposes, and reference-file paths. Nothing states what any step buys.
- The closed write-target set (SKILL.md:847) prints
  `docs/{prds,designs,plans}/{PRD,DESIGN,PLAN}-<topic>.md`. `/charter`'s
  equivalent section describes slug-composed paths and per-phase targets and
  never prints a chain of concrete artifact addresses.

Author decisions taken during scoping:

- Blast radius is `/scope` only. The framing is general, but the argumentation
  asymmetry is this skill's, and the fix stays here.
- Prose and placement only. Mechanism is #320's question; a mechanism finding
  would have to be earned against the prose path, not assumed beside it.
- The scale mismatch (the incident pointed `/scope` at thirteen documentation
  edits) is in scope and gets a lead.
- The write-target enumeration conflict is open: the exploration investigates it
  and proposes a resolution rather than being handed one.

## In Scope

- `skills/scope/SKILL.md` prose, its section set, and the order in which it
  discloses things.
- Where the artifact-persistence justification is delivered, and what already
  exists at the hop where the judgment fires
  (`skills/scope/references/phases/phase-2-chain-orchestration.md`).
- The write-target enumeration at SKILL.md:847 read against disclosure ordering,
  including whether the security bound can be stated without publishing the
  chain's addresses.
- `/charter` as a control for what the parent-skill pattern actually requires.
- Whether `/scope` has an applicability lower bound, and what an author holding
  thirteen documentation edits should run.
- Whether the chain can be made self-sequencing by what it discloses and when --
  a property of the prose, not a new mechanism.

## Out of Scope

- `tsukumogami/shirabe#320`. Read for context; not edited, re-scoped, or closed.
- Any deterministic validation, hook, or validator work. Prose and placement
  only, by author decision.
- Changes to `/charter`, `/brief`, `/prd`, `/design`, or `/plan` beyond reading
  them as controls.
- `tsukumogami/dot-niwa-overlay#7` and `tsukumogami/niwa#258`.

## Research Leads

1. **What does `SKILL.md` tell an agent the chain is for, and which text carries
   that message?**
   The incident's claim is that the skill states exactly one purpose and that
   purpose is reduction. Establish whether that holds by reading the file as an
   agent would -- what is argued versus what is merely tabulated, where the
   argumentation budget goes, and which passages describe this failure mode in
   the past tense so they reassure rather than warn.

2. **Where does the artifact-persistence justification belong, and what already
   exists at the hop where the judgment fires?**
   The proposal is to move the justification to the consolidation judgment,
   scoped to the two documents in hand. Read
   `phase-2-chain-orchestration.md` and find out what it already says, what
   `SKILL.md` duplicates from it, and what would actually have to move versus
   be written fresh.

3. **Can `/scope` state its closed write-target set without publishing every
   artifact address in the chain?**
   The security bound is legitimate and the disclosure side effect is what let
   the terminal document be addressed directly. Read
   `references/parent-skill-security.md` for what the contract actually requires
   of a parent, compare against how `/charter` states the same bound, and
   propose a resolution that keeps the bound intact.

4. **What does the parent-skill pattern require of every parent, and what does
   `/scope` carry beyond it?**
   `/charter` is the natural control: same pattern, same phase structure, same
   three exit paths, neither of the two reduction sections. Establish whether
   removing the reduction argument restores parity or breaks something
   `/charter` handles differently.

5. **Does `/scope` have a lower bound of applicable work, and what should an
   author with thirteen documentation edits run instead?**
   The incident may sit on a real mismatch: the sanctioned path costs four
   documents to legitimately arrive at one, and the shortcut yields an artifact
   that looks identical. Find out what the routing surfaces say today and
   whether any of them name a destination for work of that shape.

6. **Can the chain be made self-sequencing by what it discloses and when?**
   Deferring a justification only helps if the decision point is reached. The
   cheapest version of making the hop unavoidable is the sourcing property
   itself: if each step can only be addressed with the previous step's output,
   an agent that skipped a step holds nothing to pass along. Establish what
   actually feeds each child its invocation argument today and whether that
   property is real or aspirational.
