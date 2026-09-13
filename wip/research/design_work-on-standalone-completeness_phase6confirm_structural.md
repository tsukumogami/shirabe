# Structural Format Review (confirming): DESIGN-work-on-standalone-completeness

## Verdict

PASS

## Validator output, with checks actually running

Command run: `shirabe validate --format json --visibility=Public docs/designs/DESIGN-work-on-standalone-completeness.md`

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

`outcome` is explicitly `clean` — not `incomplete`. With `schema: design/v1` now present, the validator actually parsed the document and ran FC01-FC04 (required fields, valid status enum, frontmatter/body status agreement, all nine required sections) plus FC15 (canonical section order) against it, and every check passed with zero errors and zero notices. This is the first time these checks have executed against this file; the result is new information, not a re-confirmation of the prior inert run.

## Re-check of everything assessed while the validator was inert

- **Nine required sections, present and in order:** Status (32), Context and Problem Statement (36), Decision Drivers (76), Considered Options (95), Decision Outcome (207), Solution Architecture (245), Implementation Approach (293), Security Considerations (311), Consequences (340). Matches the canonical order in `skills/design/references/design-format.md`.
- **Frontmatter fields, complete and well-formed:** `schema: design/v1`, `status: Proposed`, `upstream: docs/prds/PRD-work-on-standalone-completeness.md`, `problem`, `decision`, `rationale` all present, each of the three prose fields using a literal block scalar (`|`). Field order — `schema, status, upstream, problem, decision, rationale` — matches the precedent in `docs/designs/current/DESIGN-multi-pr-plan-decoupling.md` exactly.
- **Frontmatter/body status agreement:** frontmatter `status: Proposed`; body `## Status` section's first non-blank line is the bare word `Proposed` with no trailing prose. Agrees case-for-case.
- **Context-aware sections for Tactical/Public:** no `Market Context` (Strategic+Private only — correctly absent), no `Required Tactical Designs` (Strategic only — correctly absent), no `Upstream Design Reference` (only applies when `spawned_from:` is set, which it is not — correctly absent). This document's only optional frontmatter field in use is `upstream:`, pointing at a PRD, which is a different thing from the DESIGN-to-DESIGN `Upstream Design Reference` section.
- **Cited paths and line ranges:** every in-repo path cited resolves — `skills/execute/scripts/run-cascade.sh` (1156 lines), `skills/work-on/koto-templates/work-on.md`, `skills/work-on/SKILL.md`, `skills/execute/SKILL.md`, `skills/execute/koto-templates/execute.md`, `skills/work-on/koto-templates/work-on.mermaid.md`, both `requires.tsv` files, all three `check-template-*.sh` scripts, and `docs/designs/current/DESIGN-multi-pr-plan-decoupling.md`. Bare filenames cited without a path (`assert-child-template.sh`, `plan-to-tasks.sh`) exist at `skills/execute/scripts/assert-child-template.sh` and `skills/plan/scripts/plan-to-tasks.sh` respectively — no path was asserted for these, so nothing is wrong. The cross-repo citation `koto src/cli/init_child.rs:481-628` resolves against the koto repo cloned in this workspace (file has 1654 lines). All five line-range citations into `run-cascade.sh` (531-579, 603-604, 903-919, 377-381, 1093-1100) were read directly and match their claims: the two `awk` rewrites under one unconditional `ok`, the four `git add ... || true` call sites each paired with an unconditional `STAGED_FILES+=(...)`, and the path-based `--lifecycle-chain` invocation and its call site.
- **No `wip/` paths in the committed document:** `grep -nE 'wip/'` returns nothing.
- **No private-repo references:** no mention of `vision`, `coding-tools`, `dot-niwa-overlay`, or private-only content.
- **Writing style / terms of art:** `CLAUDE.md` declares `tier`, `journey`, and `underscore` as this repo's terms of art the writing-style rules must not fire on. None of those three words, nor any of the other commonly-banned terms (`leverage`, `robust`, `comprehensive`, `holistic`, `facilitate`, `tiered`, `delve`, `seamless`, `utilize`) appear anywhere in the document, so the declaration is moot here — there is nothing for the rules to fire on incorrectly or correctly.
- **ASCII diagram consistency with prose:** the `ci_monitor` → `done`/`cascade_entry` → `done`/`cascade_run` → `done` diagram matches the Decision Outcome prose exactly: role decided first (child routes straight to `done`), root routes to a gate-only `cascade_entry` whose two outgoing edges are both gate-decided (no-anchor → `done`, anchor found → `cascade_run`), and `cascade_run` carries the evidence annotation described in prose (observed post-state, commit read from commit's own paths).

## Required changes

None.

## Observations

The single prior finding — missing `schema: design/v1` — is fixed, in the correct position, with the correct value, matching the field order used elsewhere in this repo's DESIGN corpus. With the validator now actually running its checks (rather than skipping the file with a SCHEMA notice), it returns `outcome: clean` with zero errors and zero notices, and every item checked by hand during the prior inert pass still holds under direct re-inspection.
