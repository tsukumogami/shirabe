---
complexity: simple
complexity_rationale: Planning issue that produces a DESIGN doc; no code changes; simple per the planning-issue convention.
---

## Goal

Produce a DESIGN doc deciding how the setup phase detects monorepo
structure and scopes baseline tests to touched packages, and decides
whether scoping logic lives in `/work-on` itself or in a future
language skill.

## Context

`phase-1-setup.md` runs an unscoped baseline ("Run the project's test
suite. All must pass."). For a monorepo, this can mean running tests
across many unrelated packages on every issue, costing minutes when
the actual issue touches one package. The friction-log run hit this:
"Full workspace test run across many packages is minutes-long. For a
single-migration PR, baselining the entire workspace is overkill."

This intersects with a deeper question: should `/work-on` know about
monorepo structure, or should that knowledge live in a per-language
skill (`tsukumogami:nodejs`-style) that work-on consults?

Detection signals to consider:
- npm/pnpm/yarn workspaces (root `package.json` `workspaces` field)
- turbo (`turbo.json`)
- go modules (multiple `go.mod` files)
- Cargo workspaces (`[workspace]` in root `Cargo.toml`)
- pnpm workspaces (`pnpm-workspace.yaml`)

Options to evaluate:
- Detection in `/work-on`'s phase-1, with hardcoded knowledge of common
  monorepo signals
- Delegation to a language skill that supplies a "scoped baseline
  command" for the touched packages
- Hybrid: `/work-on` detects but defers the actual scoping command to
  the language skill

## Acceptance Criteria

- [ ] `docs/designs/DESIGN-monorepo-baseline-scoping.md` exists at
  status `Accepted` with all required sections, including an
  `Alternatives` section
- [ ] Design names the detection signals (workspaces, turbo, go,
  Cargo) and the ownership question (work-on vs language skill)
- [ ] Decision is concrete enough that `/plan` can decompose it into
  implementation issues
- [ ] Tests pass (run project's test command)
- [ ] CI green

## Dependencies

None

## Downstream Dependencies

None
