# Brief discovery: work-on-standalone-completeness

## Grounding Path

None. No ROADMAP exists in this repo (`docs/roadmaps/` is absent) and no
`--upstream` was supplied, so `upstream:` is omitted from the produced BRIEF.

## Visibility

Public.

## Invocation context

Invoked inline by `/scope` with the `parent_orchestration:` sentinel present
(`invoking_child: brief`, `rationale: fresh-chain`). Discovery input is the
`/explore` handoff at `wip/scope_work-on-standalone-completeness_handoff.md`,
which carries a two-round exploration plus two adversarial reviews.

## Problem/outcome pair

**Problem.** A `/work-on` run invoked on its own opens a pull request and
stops short of what makes the change mergeable. Two distinct causes, and the
tracking issue names only the first: one capability is genuinely absent (the
document-chain cascade), and the rest of the finishing obligations exist but as
prose a run may skip rather than as gated states a run cannot pass. The cost is
paid every time by whoever is supervising, who must know the missing steps and
say them out loud.

**Outcome.** Someone running `/work-on` on a single issue gets a pull request
that is actually mergeable, without anyone supplying steps from memory — or a
run that stops and names what is missing rather than looking finished.

## Evidence carried from the exploration

- Three dispatched worker sessions ran `/work-on` standalone; each needed a
  supervising session to supply steps by hand.
- Two of the tracking issue's six claimed gaps do not survive the code:
  `/work-on` never creates a draft PR, and it already carries `Fixes #N` and PR
  body conformance via `references/phases/phase-6-pr.md:35` and the repo-root
  `references/pr-body-conformance.md` that `/execute` also consumes.
- `skills/work-on/` contains exactly one mention of cascade or lifecycle
  (`SKILL.md:183`, saying the cascade now lives in `/execute`).
- koto seeds a materialized child straight from the compiled template and never
  loads `SKILL.md` (`src/cli/init_child.rs:481-628`), so where a fix is written
  decides whether children receive it at all.
- The author decided multi-pr execution moves into `/execute`; `/work-on`
  should not be what a person points at a PLAN's individual issues.

## Scope edges surfaced

In: enforcement altitude, cascade states, the shared script and where it lives,
the multi-pr migration, a per-child do-not-cascade signal, a no-chain skip path.

Out: the `cannot_verify` verification-map gap, the missing `check-staleness.sh`,
issue #87, shirabe#360, shirabe#352, and the naming fossils from the earlier
split.

## Journeys identified

Four distinct entry points, each exercising the feature from a different
direction: a standalone issue with no chain, a standalone issue that belongs to
a chain, an `/execute` child that must not cascade, and a person pointing
`/work-on` at a multi-pr PLAN under the inverted routing.
