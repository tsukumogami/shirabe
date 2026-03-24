---
issue: 18
design_ref: koto docs/designs/DESIGN-shirabe-work-on-template.md
key_constraints:
  - Template already landed on feat/work-on-koto-template branch (PR #20)
  - SKILL.md orchestration wrapper (~55 lines) must be eliminated
  - Three input modes: issue-backed, free-form, plan-backed
  - koto v0.2.1 has all required platform capabilities
integration_points:
  - skills/work-on/SKILL.md — rewrite to drive koto
  - skills/work-on/koto-templates/work-on.md — already present
  - skills/work-on/references/phases/*.md — phase files need koto awareness
  - skills/work-on/references/scripts/extract-context.sh — context extraction
risks:
  - Phase files contain detailed agent instructions that the template directives now cover
  - SKILL.md Resume Logic section manages state that koto now tracks
  - Phase reference files are still needed for agent guidance within states
---

## Summary

Issue #18 migrates the /work-on skill from direct state management to koto-driven
orchestration. The template (17 states, split topology) is already on the branch.
The remaining work is rewriting SKILL.md to init koto, loop on `koto next`, and
submit evidence — replacing the ~55-line orchestration wrapper that currently
dispatches phases manually.

The template handles: mode routing (entry), context gathering (issue-backed vs
free-form paths), setup, staleness, introspection, analysis, implementation,
finalization, PR creation, CI monitoring, and terminal states (done/done_blocked).

Key change: the skill no longer needs Resume Logic or phase dispatch. koto tracks
state via its event log. The skill's job becomes: (1) init the workflow with the
right variables, (2) read `koto next` to know what state we're in, (3) execute
the phase reference file for that state, (4) submit evidence via `koto transition`.
