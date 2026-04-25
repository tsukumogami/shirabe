---
complexity: simple
complexity_rationale: Planning issue that produces a DESIGN doc; no code changes; simple per the planning-issue convention.
---

## Goal

Produce a DESIGN doc deciding how `phase-6` and the `pr_creation` state
pause for user confirmation before `git push` and `gh pr create`, while
still behaving correctly in `--auto` mode.

## Context

`phase-6-pr.md` goes straight from Pre-PR Verification to `git push`
and `gh pr create`; the `pr_creation` state in
`koto-templates/work-on.md` accepts `pr_status` without a pause.
Pushing and opening a PR are visible side-effects on shared systems.
The Claude Code system prompt's "Executing actions with care" guidance
expects pauses on actions like these.

The `--auto` interaction is the design tension: in `--auto` mode the
skill is supposed to run unattended. A pause that blocks waiting for
user input would defeat that. Either `--auto` skips the gate (and the
user accepts that PR creation is included in unattended runs) or the
skill follows the decision-protocol and proceeds with a recorded
decision.

Options to evaluate:
- New explicit confirmation step in `phase-6-pr.md` (interactive only;
  `--auto` skips with a recorded decision)
- New `pre_push_confirmation` state with `accepts: confirmed | aborted`
- Decision-protocol invocation in both modes (interactive blocks for
  user; auto records and proceeds)

## Acceptance Criteria

- [ ] `docs/designs/DESIGN-pre-push-confirmation.md` exists at status
  `Accepted` with all required sections, including an `Alternatives`
  section
- [ ] Decision addresses interactive vs `--auto` behaviour explicitly
- [ ] Decision is concrete enough that `/plan` can decompose it into
  implementation issues
- [ ] Tests pass (run project's test command)
- [ ] CI green

## Dependencies

None

## Downstream Dependencies

None
