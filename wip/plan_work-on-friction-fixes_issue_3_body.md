---
complexity: simple
complexity_rationale: Planning issue that produces a DESIGN doc; no code changes; simple per the planning-issue convention.
---

## Goal

Produce a DESIGN doc deciding how the setup phase captures and routes
baseline test failures that exist before the current change touches
anything.

## Context

`skills/work-on/references/phases/phase-1-setup.md` currently states
"Run the project's test suite. All must pass." It has no branch for
"baseline is broken upstream — document and proceed." Agents hitting a
broken-baseline state have to route around the gate manually, with no
way to signal downstream gates to ignore those pre-existing failures.

The friction-log run hit this with a pre-existing FK-seeding gap in a
migration chain — the agent had to figure out manually that 8 server
rows needed seeding to unblock migration `0005`, with no signal that
"this is upstream brokenness, not my change."

Options to evaluate:
- New evidence value `baseline_status: broken_preexisting` with a
  rationale field
- A dedicated gate that captures the failing-test list into baseline.md
- Documented human-in-the-loop escape (override + manual baseline note)

The DESIGN must address `--auto` mode behaviour explicitly: a
silent-broken-baseline acceptance in `--auto` mode is dangerous.

## Acceptance Criteria

- [ ] `docs/designs/DESIGN-preexisting-baseline-failures.md` exists at
  status `Accepted` with all required sections, including an
  `Alternatives` section
- [ ] Decision names what `baseline.md` captures, how subsequent gates
  avoid misattributing the failure, and how `--auto` mode behaves
- [ ] Decision is concrete enough that `/plan` can decompose it into
  implementation issues
- [ ] Tests pass (run project's test command)
- [ ] CI green

## Dependencies

None

## Downstream Dependencies

None
