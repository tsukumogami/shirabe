# Brief Discovery: scope-chain-mandatory-steps

## Visibility

Public

## Grounding

No ROADMAP. This repo has no `docs/roadmaps/` directory, so there is no
sequencing artifact to ground on and no `upstream:` to resolve. The brief is
framed from the topic and from the `/explore` run that preceded it on this
branch:

- `wip/explore_scope-chain-mandatory-steps_findings.md`
- `wip/explore_scope-chain-mandatory-steps_decisions.md`
- `wip/research/explore_scope-chain-mandatory-steps_r1_lead-*.md` (six files)

## Problem / Outcome Pair

**Problem.** The corpus gives two different answers to whether a chain step is
optional, and an author meets the wrong one first. `/scope` and `/execute` state
the current model — steps are mandatory, reduction happens after the artifacts
exist. `/explore`, the shared parent-skill pattern both parents inherit from,
and the `/scope` eval suite still state the model #302 replaced.

**Outcome.** An author never decides which chain step to start at. They pick an
entry point, the chain runs whole, and what did not earn its keep is folded
afterward. Every surface that describes chain shape says the same thing.

## Coverage Notes

- **Intent** — make the corpus state one model, without re-opening what #302
  settled. `PRD-scope-artifact-persistence.md` R28 already forbids reintroducing
  a pre-artifact worth decision "in any form, including an author-chosen entry
  altitude"; this work enforces that rule against the surfaces that predate it.
- **Prior knowledge** — the author identified `/explore` and `/scope` as the two
  offenders. Research confirmed both and relocated the fix: the `/scope` prompt
  is inherited from `references/parent-skill-pattern.md`, and `/explore`'s
  defect is behavioral (it authors durable documents) rather than editorial.
- **Uncertainty** — two questions the brief defers: what "a shorter chain" means
  to an author now that absorption reduces the artifact set but not the
  conversation, and where the interactive entry to R8 bail-handling lives if
  `Bail` leaves the Phase 1 prompt.
- **Constraints** — `/charter`'s roadmap declination stays (author decision);
  `/execute` is out; `crates/shirabe-validate/src/formats.rs` already encodes
  the current model and is not touched.
- **Scope edges** — the eval repairs are in, because scenarios 18-21 are an
  unmet acceptance criterion of #302's own PRD rather than new work. Porting a
  consolidation judgment to the strategic chain is out.
- **Stakes** — the eval suite is the only executable statement of `/scope`'s
  behavior, it runs on a weekly cron rather than on pull requests, and it
  currently grades the retired model. Any agent optimizing against it is pulled
  backward.
