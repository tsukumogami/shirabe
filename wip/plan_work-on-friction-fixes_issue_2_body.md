---
complexity: simple
complexity_rationale: Planning issue that produces a DESIGN doc; no code changes; simple per the planning-issue convention.
---

## Goal

Produce a DESIGN doc deciding how the `staleness_check` gate should
work on a shirabe-only install, given that the script it currently
calls — `check-staleness.sh` — does not ship with shirabe.

## Context

`skills/work-on/koto-templates/work-on.md` has a gate that runs
`check-staleness.sh --issue {{ISSUE_NUMBER}} | jq -e '.introspection_recommended == false'`.
Verification during the friction-log triage turned up no
`check-staleness.sh` anywhere in shirabe. The script lives only in
the private `tsukumogami` plugin at
`skills/issue-staleness/scripts/check-staleness.sh`. Users installing
shirabe alone get a broken gate (the `command not found` exit code
misroutes through introspection accidentally rather than meaningfully).

Options to evaluate:
- Port `check-staleness.sh` into shirabe
- Make the `staleness_check` gate conditional on script availability
- Move staleness logic into koto itself
- Drop the gate, recover the staleness signal another way

## Acceptance Criteria

- [ ] `docs/designs/DESIGN-staleness-check-portability.md` exists at
  status `Accepted` with all required sections, including an
  `Alternatives` section evaluating the four options above
- [ ] Decision is concrete enough that `/plan` can decompose it into
  implementation issues
- [ ] Tests pass (run project's test command)
- [ ] CI green

## Dependencies

None

## Downstream Dependencies

None
