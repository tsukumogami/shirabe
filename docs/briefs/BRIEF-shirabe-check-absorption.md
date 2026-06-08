---
schema: brief/v1
status: Done
problem: |
  The same deterministic doc checks are implemented in more than one place
  -- the shirabe validate engine, external CI shell scripts, and rules
  restated in skill prose -- and the copies drift. Three check families
  exist in both the engine and the scripts, so one document can pass one and
  fail the other.
outcome: |
  The validate engine is the single authority for these checks: each check
  is defined once, every consumer runs that one definition, the duplicated
  external copies are absorbed where they are deterministic and cheap, and a
  rule change happens in one place.
---

# BRIEF: Deterministic check absorption

## Status

Done

Drafted under the tactical chain. The downstream PRD owns the requirements;
the DESIGN owns the per-check absorb/defer/keep decisions, the
reconciliation method for the overlapping families, and the order in which
external sources are retired.

## Problem Statement

`shirabe validate` is meant to be the one authority for the project's
deterministic document checks -- the rules that say a doc's frontmatter is
well-formed, its required sections are present and ordered, its issues
table is consistent. The engine already implements a large set of these as
first-class checks (the FC- and R-families). But it is not yet the *only*
place those rules live.

The same kind of checks are also implemented outside the engine, in two
other forms:

- **External CI shell scripts.** A parallel set of deterministic checks
  runs as shell scripts in continuous integration, copied across more than
  one repository. They validate the same things the engine does -- and in
  three families (frontmatter, required sections, the issues table) they
  overlap the engine directly: the rule is implemented twice, once in Rust
  and once in shell.
- **Rules restated in skill prose.** Some deterministic rules are written
  out as English in the workflow skills -- a Phase-0 validation step, a
  frontmatter-field list, a section-ordering rule, a path-hygiene scan.
  The prose describes a rule a check could execute, but nothing keeps the
  prose and any executed check in step.

Because the rule lives in several places, the places drift. A document can
pass the shell script and fail the engine, or vice versa, because the two
implementations of "the same" check disagree on an edge. A maintainer who
fixes a frontmatter rule has to find and fix every copy. And a skill whose
prose restates a rule can fall out of sync with what the validator actually
enforces, so the written rule and the executed rule diverge silently.

The engine cannot become the single authority just by existing alongside
the duplicates. The deterministic checks that still live outside it have to
be absorbed *into* it -- and where a check already exists on both sides,
the two have to be reconciled to one authoritative behavior rather than
left to disagree. Until that happens, "the validator is the source of
truth" is an aspiration the duplicated copies quietly contradict.

## User Outcome

A deterministic check has exactly one definition, in the engine, and every
consumer runs that definition. A maintainer who corrects a rule corrects it
once; CI, the skills, and local hooks all pick up the corrected behavior
without a second copy to hunt down. A document gets one verdict, not two
that can disagree, because the families that used to exist on both sides
have been reconciled to a single authoritative behavior. A skill author who
needs a deterministic rule enforced points at the engine's check instead of
restating the rule in prose, so the written rule and the executed rule can
no longer drift apart.

The change the user feels: the duplication and the drift go away. The
checks stop being a thing maintained in several places that disagree at the
edges, and become one authority the whole project shares -- with the
expensive or judgment-dependent checks deliberately left out, by a rule
anyone can apply, rather than absorbed by reflex.

## User Journeys

### A maintainer fixes a rule once

A maintainer finds that the frontmatter check accepts something it should
reject. They change the rule in the engine, once. The next CI run on every
repository, and the next time a skill shells out to the validator, both
enforce the corrected rule -- there is no second shell-script copy to
update, and no skill prose restating the old behavior to fall out of step.

### A contributor gets one verdict, not two

A contributor opens a pull request whose document passes the external
shell check but trips the engine, because the two implementations of the
issues-table rule disagree on an edge case. After absorption, the family
has been reconciled to one authoritative behavior, so the contributor sees
a single consistent verdict and does not have to reconcile two tools'
contradicting output by hand.

### A skill author references the check instead of restating it

A skill author is writing a phase that must confirm a document's required
sections are present before proceeding. Instead of restating the
section-ordering rule in prose -- a copy that can drift from what the
validator enforces -- they invoke the engine's check and read its verdict.
The skill's behavior is now bound to the executed rule, not a written
paraphrase of it.

### A maintainer decides what stays out

A maintainer weighs whether a particular external check should be absorbed.
They apply a determinism rubric: a check that is a pure function of the
document (or of state an orchestrator can hand in) is in scope; a check
that is too expensive to run inline, or that needs a human or model
judgment, is left where it is. The decision is made by the rubric, not by
reflex, so the engine takes on the checks that belong in an offline
authority and refuses the ones that do not.

## Scope Boundary

**In:**

- Absorbing the deterministic checks that currently live outside the
  engine -- in external CI shell scripts and in skill-prose rules -- into
  it as first-class checks.
- A determinism rubric that governs what is absorbed: a check that is a
  pure function of the document, or deterministic over external state an
  orchestrator injects, is in scope; a check that is cost-deferred or
  needs human/model judgment is not.
- Reconciling the check families that exist on both sides (frontmatter,
  required sections, the issues table) to one authoritative behavior, so
  the two implementations stop disagreeing.
- Mechanizing deterministic rules currently restated in skill prose so the
  prose references the engine's check instead of duplicating the rule.
- A parity test for each absorbed check, asserting its verdict matches the
  source it replaces -- or naming the deliberate divergence where the
  reconciled behavior intentionally differs.
- Retiring each external copy of a check as the engine absorbs it, so the
  duplication actually goes away rather than accumulating a third
  implementation.

**Out:**

- The expensive checks deferred on cost grounds (the large diagram
  validator is the clear example). They stay where they are, on the
  shrinking external mechanism, until a later effort absorbs them. The
  exclusion is about cost, not about whether they are deterministic.
- Judgment-only checks that need a human or a model call. They never
  belong in an offline validator and are out by definition, not by
  deferral.
- The per-check absorb/defer/keep decisions, the reconciliation method for
  each overlapping family, and the order in which external sources are
  retired. These are design decisions the downstream DESIGN settles, not
  framing the brief fixes.
- The output and selection surface the checks are invoked through (the
  output modes, per-check selection, the exit-code contract). That surface
  already exists; this feature populates it with absorbed checks rather
  than reshaping it.
- Distributing or installing the engine to its consumers. Making the one
  authority reachable on every consumer's path is separate downstream
  work.
