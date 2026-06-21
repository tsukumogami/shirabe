# Phase 6 Security Review — DESIGN-execute-friction

VERDICT: PASS

## Findings

- **D1 single-pr recovered branch (input surface):** PASS. The claim is correct and
  sufficient. The settled HEAD branch captured into a koto context key is treated as
  an input surface and re-validated before interpolation, mirroring the existing
  `gh`-recovered-slug discipline already bound in SKILL.md item 1 (slug re-validation
  against `^[a-z0-9-]+$` on cross-branch resume, rows 8-9). The current template
  derives `PLAN_SLUG` deterministically from the PLAN basename, so the
  `|| impl/$PLAN_SLUG` fallback is built from a validated, non-untrusted token — the
  fallback never interpolates recovered free text. Verified against
  `execute.md:238` (slug derivation) and `:286/:300` (the `SHARED_BRANCH` injection
  points the design replaces). The "unparseable recovered branch rejects rather than
  interpolating" posture is the same fail-closed rule the parent already applies.

- **D1 coordinated worktree paths:** PASS. Paths derive from the validated PR-Index
  `repo`/`pr_group` tags, which SKILL.md item 3 already states are re-validated on
  every refresh read (the PR-Index is re-derived from the editable body each pass).
  Not free text. Stays inside the closed write-target discipline. No new path-traversal
  surface.

- **D2 pause / R9 non-bypass:** PASS — and this is the load-bearing claim, so I
  checked the R9 spec directly. `parent-skill-state-schema.md:215-255` defines R9 as
  firing "at parent finalization" — it is a gate on the act of recording a terminal
  exit, not a periodic invariant. A suspension legitimately leaves `exit:` UNSET
  because the run has not terminated; it never reaches the finalization gate, so there
  is nothing for R9 to bypass. On resume the run re-enters `plan_completion` and
  finalizes with `exit:` set, at which point R9 fires normally. The `paused_for_review`
  terminal is a non-failure resumable marker (chain intact: PLAN present, upstream
  un-transitioned, PR DRAFT) and writes only the existing state projection — no new
  write target. This is NOT a loophole that lets an unfinalized run escape R9; an
  abandoned-and-never-resumed pause is an availability/audit concern, not an R9 bypass,
  and the design's claim is correctly scoped to the bypass question.

- **D3 signal read-not-interpolated; metadata-only contract:** PASS. `user_visible_surface`
  is a boolean frontmatter flag read by `/plan` (which already reads DESIGN bodies);
  the `docs/guides/*` fallback is a path-pattern match. Confirmed neither field exists
  in `/execute` today and the design places both in `/plan` + `/review-plan`, never in
  `/execute`. `/execute` gains no content read — its metadata-only inspection contract
  (R14/R15, SKILL.md:420-435) is untouched. No untrusted interpolation introduced.

- **D4 fail-closed reuse:** PASS. Reuses `shirabe validate --lifecycle-chain <seed>
  --mode=ready` with its existing multi-level exit-code contract; the design correctly
  distinguishes exit 1 (tool-error) from exit 2 (violation), preserving fail-closed
  behavior. No new code surface, no renderer subcommand (respects the CLI-Surface
  contract). The cascade already self-verifies with this exact probe.

- **D5 write-target set not widened:** PASS, and correctly conservative. The
  durable-capture home is a convention (developer-authored GitHub issue / `docs/` note),
  deliberately NOT an automated `/execute` emit, precisely to avoid adding a remote
  write target outside the closed set declared in SKILL.md item 2. The automated emit
  is explicitly deferred with the stated reason that it would need an R9 amendment.
  Security-neutral.

- **D6 no-untrusted-input-interpolation:** PASS, and this is a genuine tightening, not
  a rubber-stamp. The current template uses inline `gh pr edit --body "<assembled
  description>"` (execute.md:323) and `gh pr create --title "impl: $PLAN_SLUG"`
  (:242). The design's D6 (a) builds the title from the validated PLAN slug
  (`^[a-z0-9-]+$`), never raw prose, and (b) moves the two-part body to
  `--body-file`/stdin discipline rather than inline `-m`/`--body` interpolation — a
  strictly safer posture than today's inline `--body`. The body content is child-outcome
  metadata derived from validated fields and live `gh` reads, not PLAN-body prose, so
  no untrusted author prose reaches a shell `-m` or an unescaped title. Consistent with
  SKILL.md item 6.

- **No new attack surface:** PASS. Every decision either reuses an existing fail-closed
  check (D4), reads-not-interpolates (D1 branch, D3 flag), stays inside the closed
  write-target set (D1 worktrees, D2 terminal, D6 edit), or deliberately declines to
  widen it (D5). No surface beyond the six documented in
  `references/parent-skill-security.md`.

- **Visibility boundary:** PASS. Unchanged. `/execute` v1 stays bound to public-repo
  chains; the design adds no cross-visibility path and explicitly states so. No new
  governance-routing concern.

- **Honesty / completeness:** PASS. The review is not a rubber-stamp. The negatives
  section acknowledges the surfaces a skeptic would probe: the coordinated path's
  finalization contract is explicitly left unchanged (R2/R4/R5/R6 are single-pr-scoped),
  the worktree lifecycle is named as operational surface to get right, and the D5
  convention's dependence on developer discipline is stated with the automated
  alternative's cost. The adopted-PR case is addressed (D1 re-validates the recovered
  branch). The `docs/guides/*` fallback path-matching is correctly placed in `/plan`
  (a body-reader) rather than `/execute`, so it cannot violate the metadata-only
  contract.

## Required changes (only if FAIL)

None.

## Summary

The security review is sound and grounded in the actual baseline: each of the six
decisions either reuses an existing fail-closed check, reads-rather-than-interpolates,
or declines to widen the closed write-target set, and the load-bearing D2 claim (pause
does not bypass R9) is correct because R9 fires only at the finalization transition that
a suspension never reaches. D6 is a genuine tightening (validated-slug title +
`--body-file`/stdin) over today's inline `--body`. No new attack surface, the
public-repo visibility binding is unchanged, and the negatives section honestly scopes
the coordinated-path and worktree-lifecycle residue rather than rubber-stamping.
