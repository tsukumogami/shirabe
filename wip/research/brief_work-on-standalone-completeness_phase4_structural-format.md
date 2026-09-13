# Structural Format Review: BRIEF-work-on-standalone-completeness

## Verdict
PASS

## Validator output

Ran: `shirabe validate --format json docs/briefs/BRIEF-work-on-standalone-completeness.md`

```json
{
  "schema_version": "shirabe-validate/v1",
  "summary": {
    "outcome": "clean",
    "errors": 0,
    "notices": 0
  },
  "findings": [],
  "advisory": {
    "summary": "Draft posture: no draft-tolerable findings to flag.",
    "notes": []
  }
}
```

`shirabe` resolved on PATH at `/home/dangazineu/.tsuku/tools/current/shirabe`; the command ran cleanly with no errors and no notices.

## Per-criterion findings

**1. Frontmatter.** `schema: brief/v1` present. `status: Draft`, `problem`, `outcome` all present and non-empty (both are 2-4 line YAML block scalars, matching the format reference's requirement). `motivating_context` is present, well-formed, and distinct in content from `problem`/`outcome`. No field outside the schema (`schema`, `status`, `problem`, `outcome`, `motivating_context`) appears. `upstream` is absent — legal, see #2.

**2. `upstream:` correctness.** The field is omitted entirely. The format reference lists `upstream` as optional precisely because a brief may lack a roadmap-derived ancestor, and this repo has no `docs/roadmaps/` directory at all (confirmed: `ls docs/roadmaps` → "No such file or directory"), so there is no roadmap to walk up from. The one occurrence of the string "ROADMAP" in the document (line 48, Problem Statement) is generic prose about which document types the chain cascade touches ("a BRIEF, PRD, DESIGN, PLAN or ROADMAP that should be pulled to its terminal state") — not an upstream reference. The document never names a ROADMAP as its upstream, in frontmatter or prose.

**3. Required sections present and in order.** Heading scan confirms exact canonical order: `## Status` (19) → `## Problem Statement` (28) → `## User Outcome` (64) → `## User Journeys` (81) → `## Scope Boundary` (121), followed by the optional `## Open Questions` (156) and `## References` (170), matching the Section Matrix's own ordering.

**4. FC03 status convention.** Body `## Status` section's first non-blank line is `Draft`, alone, followed by a blank line, then prose. Matches frontmatter `status: Draft` exactly (case and content). This is the exact shape the reference calls out as passing. Confirmed independently by `shirabe validate` returning zero findings.

**5. User Journeys sub-structure.** All four journeys lead with a `###` heading: "A maintainer fixes a one-off bug with no documents behind it," "A maintainer implements the last issue behind a design," "An orchestrator runs a plan and the cascade fires once," "Someone points the single-issue skill at a whole plan." Each names a concrete user, a trigger, and an outcome shape, and each is a genuinely distinct entry point (no-chain path, mid-chain path, plan-orchestrator path, misrouted-entry-point path).

**6. Scope Boundary structure.** Two explicit sub-headings, `### In` (123) and `### Out` (137), each a bulleted list. IN has 6 items, OUT has 6 items with named reasons (each OUT item states why it's excluded rather than being a filler exclusion).

**7. Optional sections legal for this status.** `Open Questions` is present with three items; status is Draft, so this is permitted per the Section Matrix ("Draft only") and the Lifecycle table. Noting for the record: per the format reference, this section must be emptied or removed before the Draft → Accepted transition (`shirabe transition` precondition), which is a forward-looking flag, not a defect in the current Draft artifact.

**8. Reference path durability.** Four paths appear in the References section:
- `docs/designs/current/DESIGN-execute-skill.md` — exists
- `docs/prds/PRD-execute-skill.md` — exists
- `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md` — exists
- `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md` — exists

Grepped the entire document (prose, frontmatter, References) for `wip/` — no hits. No dangling or `wip/`-rooted paths anywhere in the document.

**9. Public-visibility cleanliness.** Repo's own `CLAUDE.md` declares `Repo Visibility: Public`. Grepped the document for `private/`, `wip/`, and private-repo issue-reference patterns (`vision#`, `coding-tools#`, `tools#`, `dot-niwa-overlay#`) — no hits. The one issue reference in the document, "tracking issue #361" (line 23), carries no owner/repo prefix, which per the format reference's convention means it is read as a same-repo (public) issue number — not a forbidden private cross-repo reference.

**10. Writing style.** Grepped the full banned-word list from `skills/writing-style/rules.yaml` (tier/tiered, robust, comprehensive, holistic, crucial, pivotal, paramount, leverage, utilize, facilitate, delve, foster, navigate, showcase, grapple, transcend, elucidate, underscore, highlight, enhance, "align with," garner, innovative, transformative, profound, vibrant, seamless, meticulous, invaluable, nuanced, groundbreaking, intricate, journey, narrative, tapestry, testament, resilience, interplay, realm, and the adverb-openers) against the document body — zero matches. "Journey"/"Journeys" appears only as the required section name and in ordinary structural use, and the repo's `CLAUDE.md` explicitly exempts `journey` (along with `tier` and `underscore`) as a term of art for this repo, so even if it had appeared as prose it would not be a finding. Computed em-dash frequency independently: 13 em dashes across ~1446 body words = ~9.0 per 1000 words, under the rules.yaml `em-dash-density` threshold of 10 per 1000 (and above the 300-word minimum denominator, so the rule was live and non-triggering). No AI-writing-pattern tells ("it's worth noting," "in today's," etc.) found either.

## Required changes

None.

## Observations

- The single Open Questions section (3 items) will need to be resolved or removed before any Draft → Accepted transition is requested; this is expected Draft-stage content, not a current defect.
- `shirabe validate` corroborates every mechanical finding above (FC01-FC04 all implicitly clean, zero errors/notices), giving independent confirmation beyond manual inspection.
