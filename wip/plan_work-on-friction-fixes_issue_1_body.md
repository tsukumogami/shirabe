---
complexity: simple
complexity_rationale: Planning issue that produces a DESIGN doc; no code changes; simple per the planning-issue convention.
---

## Goal

Produce a DESIGN doc deciding how `extract-context.sh` resolves a
DESIGN document that lives on a remote branch or in a sibling repo,
not in the local working tree.

## Context

`skills/work-on/references/scripts/extract-context.sh` currently
searches `find docs -name "DESIGN-*.md"` in the local repo only
(line ~150). When an issue references a DESIGN doc that exists on
`origin/<branch>` in a sibling repo (the friction-log run hit this with
a doc on `origin/docs/f1-m1-policy-guardrail` in a sibling repo), the
script returns `status: degraded / warnings: ["Design doc not found"]`
and falls back to the issue body alone. Multi-repo workspaces hit this
routinely.

Options to evaluate:
- Scan `origin/*` refs for design-doc-shaped paths
- Use a workspace manifest (e.g., niwa) to enumerate sibling repos
- Require an explicit `Design: <path> @ <repo>` annotation on issues
- Leave as-is and document the limitation

## Acceptance Criteria

- [ ] `docs/designs/DESIGN-extract-context-remote-resolution.md` exists
  at status `Accepted` with all required sections, including an
  `Alternatives` section evaluating the four options above
- [ ] Decision is concrete enough that `/plan` can decompose it into
  implementation issues
- [ ] Tests pass (run project's test command)
- [ ] CI green

## Dependencies

None

## Downstream Dependencies

#6 — the per-branch context findings cache design depends on the
resolution strategy chosen here.
