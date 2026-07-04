# Structural Format Verdict: BRIEF-session-work-summary

## Verdict
PASS

## Per-Check Assessment

### 1. Frontmatter
PASS. `schema: brief/v1` present as the routing key. Required fields all present: `status: Draft`, `problem` (4-line literal block scalar), `outcome` (4-line literal block scalar) — both within the 2-4 line requirement. Optional `motivating_context` is a well-formed literal block scalar (the 2-4 line rule applies only to problem/outcome, so its 6 lines are fine). `upstream` is absent, which is acceptable — the field is optional, and the spec explicitly allows omission when a brief is authored without a single upstream document. No frontmatter field points at a `wip/` path.

### 2. Status (FC03 shape)
PASS. Frontmatter `status` is `Draft`. The first non-blank line under body `## Status` (line 26) is exactly the bare word `Draft`, with explanatory prose after a blank line — the shape FC03 requires.

### 3. Required sections in canonical order (FC04/FC15)
PASS. All five present in order: Status (line 24), Problem Statement (line 32), User Outcome (line 52), User Journeys (line 68), Scope Boundary (line 111).

### 4. User Journeys
PASS. Five journeys, each with a `###` name heading: "The multi-PR afternoon", "Returning after a break", "Finding a link from an hour ago", "Checking on a dispatched worker", "Asking for status on demand". Each names a user, a trigger, and an outcome shape, and each enters from a distinct entry point.

### 5. Scope Boundary
PASS. Both lists present: `### In scope` (7 bullets) and `### Out of scope` (6 bullets). OUT items are real exclusions (harness modification, timed digests, always-on display channels, notification fan-out, the hook-matcher prerequisite fix, non-PR work items).

### 6. Optional sections
PASS. References section entries (`references/coordination-strategy.md`, `references/issues-table.md`) are durable repo-relative paths; both files verified to exist at the repo root's `references/` directory. Neither is a `wip/` path. No Downstream Artifacts section — acceptable at Draft. No Open Questions section — optional, so absence is fine.

### 7. Public-visibility cleanliness
PASS. Grep for `wip/`, `private/`, `vision`, `coding-tools`, `dot-niwa-overlay`, and private-repo issue references returned no matches (exit 1). The out-of-scope mention of a "workspace tooling bug" is described generically without naming a private repo or issue number. No internal codenames.

### 8. Validator corroboration
PASS. `shirabe validate --format json --visibility=Public docs/briefs/BRIEF-session-work-summary.md` exited 0 with outcome "clean": 0 errors, 0 notices, no findings, and the draft-posture advisory reported nothing to flag.

## Required Changes (if FAIL)
None.

## Advisory Notes (non-blocking)

- The References entries use paths relative to the repo root (`references/...`) while the brief lives in `docs/briefs/`. The files resolve from the repo root, which matches the "durable repo-relative path" convention, but a reader resolving relative to the brief's own directory would miss. Consider no change; noted only for awareness.
- `motivating_context` runs 6 lines. The spec sets no length bound for this field, so this is compliant — flagged only because problem/outcome carry a 2-4 line bound and a future reviewer might assume parity.
