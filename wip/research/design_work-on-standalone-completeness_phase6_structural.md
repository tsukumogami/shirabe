# Structural Format Review: DESIGN-work-on-standalone-completeness
## Verdict
FAIL
## Validator output
```
{
  "schema_version": "shirabe-validate/v1",
  "summary": {
    "outcome": "incomplete",
    "errors": 0,
    "notices": 1
  },
  "findings": [
    {
      "code": "SCHEMA",
      "severity": "notice",
      "message": "schema field missing, skipping",
      "file": "docs/designs/DESIGN-work-on-standalone-completeness.md",
      "line": 1
    }
  ],
  "skipped": [
    {
      "file": "docs/designs/DESIGN-work-on-standalone-completeness.md",
      "reason": "schema field missing, skipping"
    }
  ],
  "advisory": {
    "summary": "Draft posture: no draft-tolerable findings to flag.",
    "notes": []
  }
}
```
Exit code: 4. Command run: `shirabe validate --format json --visibility=Public docs/designs/DESIGN-work-on-standalone-completeness.md` (shirabe v0.19.1).

## Per-criterion findings

**1. Frontmatter.** `status`, `problem`, `decision`, `rationale` are all present, non-empty, and use literal block scalars (`|`) where required. `upstream: docs/prds/PRD-work-on-standalone-completeness.md` resolves to a real file. No field outside the known set is present. However, the frontmatter is missing `schema: design/v1`. Every other DESIGN document in the repo (checked all of `docs/designs/current/*.md` and `docs/designs/*.md`) carries this field as line 2; this document is the sole exception. `skills/design/references/design-format.md:44-48` names `schema` as required alongside `status`, `problem`, `decision`, `rationale`, and the live validator enforces it: it emits a `SCHEMA` finding and skips the file entirely, so none of R6-R11, FC01-FC16, or FC-CONVENTIONS ran against this document. This is the single decisive defect in this review — it also blocks the validator from checking everything else on its list.

**2. Frontmatter/body status agreement.** Body `## Status` section's first non-blank line (line 33, "Proposed") matches frontmatter `status: Proposed` exactly. Pass.

**3. Nine required sections, in order.** Confirmed present at these lines, in the specified order: Status (31), Context and Problem Statement (35), Decision Drivers (75), Considered Options (94), Decision Outcome (206), Solution Architecture (244), Implementation Approach (292), Security Considerations (310), Consequences (339). Pass.

**4. Context-aware sections.** Repo `CLAUDE.md` declares `## Repo Visibility: Public` and `## Planning Context: Tactical`. Per the design skill's table, Tactical means Market Context is forbidden, Required Tactical Designs is forbidden, and Upstream Design Reference applies only "if exists" (i.e., if there is a parent strategic design). The document correctly omits Market Context and Required Tactical Designs. It has no `spawned_from` field and its `upstream` points to a PRD (ordinary tactical-chain lineage, not a cross-altitude strategic parent), so no Upstream Design Reference section is owed, and none is present. Pass.

**5. Path resolution.** Every path cited resolves: `skills/execute/scripts/run-cascade.sh` (1156 lines; cited line ranges 531-579, 603-604, 903-919, 377-381, 1093-1100 all check out against actual content), `skills/work-on/koto-templates/work-on.md`, `skills/execute/koto-templates/execute.md`, `skills/work-on/koto-templates/work-on.mermaid.md`, `skills/work-on/requires.tsv`, `skills/execute/requires.tsv`, `skills/execute/SKILL.md`, `skills/work-on/SKILL.md`, `scripts/check-template-directives.sh`, `scripts/check-template-interpolation.sh`, `scripts/validate-template-mermaid.sh`, `skills/execute/scripts/assert-child-template.sh`, `skills/plan/scripts/plan-to-tasks.sh`, `docs/designs/current/DESIGN-multi-pr-plan-decoupling.md`, and the cross-repo `koto` citation `src/cli/init_child.rs:481-628` (file is 1654 lines; the cited range lands inside `init_child_core`, consistent with the child-session-creation claim). No `wip/` path is cited anywhere in the document — grep for `wip/` returns nothing. The document mentions "the reports are the record of what was considered" for the five decision reports but does not cite them by path, which is correct: those reports live under `wip/research/` in this worktree and would be deleted before merge, so citing them by path would have been a wip-hygiene violation. Pass.

**6. Public-visibility cleanliness.** No private-repo references (`private/`, `vision`, `coding-tools`, `dot-niwa-overlay`, `tools`) and no issue-number references at all, so no same-repo-vs-cross-repo issue question arises. The only cross-repo citation is to `koto`, itself a public repo. Pass.

**7. Writing style.** No banned terms from `skills/writing-style/rules.yaml` appear (checked every term list: organizing, verbs, descriptors, abstract-nouns, adverb-openers), and neither `tier`, `journey`, nor `underscore` appear at all, so the repo's term-of-art exemption is moot here. Em-dash density: 21 em dashes over ~2540 scoped-prose words (frontmatter, code fences, and table rows excluded) is about 8.3 per thousand, under the documented threshold of 10. The prose reads as dense, technical narrative consistent with this repo's style — no AI-writing tics ("it's worth noting," "in today's fast-paced," etc.) and no bullet-heavy sections where narrative would read better; the bulleted Decision Drivers and Components table are genuinely tabular content. Pass.

**8. Diagram.** The fenced ASCII data-flow diagram (lines ~246-262) is well-formed and matches the surrounding prose exactly: `ci_monitor` branches on `session_role` to `done` (child) or `cascade_entry` (root, ci_outcome: passing), matching "ci_monitor decides role first"; `cascade_entry`'s gate splits to `done` (no anchor found) or `cascade_run`, matching "routes past the cascade when there is none"; the evidence annotation on the `cascade_run → done` edge ("observed post-state, commit read from commit paths") matches the Decision Outcome paragraph on evidence. Pass.

## Required changes
1. **Line 1-2 (frontmatter):** Add `schema: design/v1` as the first frontmatter field, immediately after the opening `---`, matching the format every other DESIGN document in this repo uses (see `skills/design/references/design-format.md:44-48` and any file under `docs/designs/current/`). This is not optional cosmetics: the live `shirabe validate` invocation specified in this review's instructions skips the entire document and returns `outcome: incomplete` (exit 4) without it, meaning none of the mechanical rule checks (R6-R11, FC01-FC16, FC-CONVENTIONS) have actually run against this document yet. Re-run the validator after the fix and confirm a clean or genuinely-checked result before this document is considered structurally sound.

## Observations
- `skills/design/SKILL.md`'s own inline "Structure" section (the frontmatter example under `### Frontmatter`) is itself stale relative to `skills/design/references/design-format.md` and the actual validator: it lists only `status`, `problem`, `decision`, `rationale` as the frontmatter block and never mentions `schema` at all. An author following `SKILL.md` literally, without also consulting `design-format.md`, would reproduce exactly the omission found here. Worth a separate fix to `SKILL.md` so this doesn't recur, though that is outside this document's own scope.
- Everything else in the document is in strong shape: the frontmatter prose is tight and specific, every cited path and line range checks out against real files, the diagram is consistent with the prose describing it, and the writing carries no flagged style violations. The one required change is mechanical and isolated to two words on one line.
