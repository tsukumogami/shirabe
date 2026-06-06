# PRD Scope: doc-vs-github-state-reconciliation (FC09)

## Topic Slug
doc-vs-github-state-reconciliation

## Upstream
docs/briefs/BRIEF-doc-vs-github-state-reconciliation.md (Accepted)

## Visibility
Public (per CLAUDE.md `## Repo Visibility: Public`).

## Execution Mode
--auto (no user confirmation rounds; record assumed decision blocks per
references/decision-protocol.md at human-judgment gates).

## Scope (decided assumed)

The BRIEF settles every framing question this PRD inherits:

- One check `check_fc09`, three sub-checks (A doc-claims-done vs GH, B
  doc-claims-open vs GH, C PR `Closes #N` consistency).
- Dispatched in the plan and roadmap arms alongside FC05/FC06/FC07.
- Client surface as a trait with no transport pre-committed.
- Four self-disable paths: missing credentials, missing PR context,
  rate-limit exhausted after one retry, per-row cross-repo 403 / 404.
- Per-defect notices in the FC05/FC06/FC07 voice.
- Notice-level shipping via `is_notice` membership, one-line promotion seam.
- Bounded behavior over arbitrary external input (defensive parsing,
  bounded retries, explicit timeouts, token never logged).

## Out-of-frame (sub-DESIGN owns)

- Transport choice (`gh api` subprocess vs raw HTTP).
- Exact notice message strings.
- Specific timeout values.
- Test fixture mechanism (trait-mock vs recorded fixtures).
- Module layout under `crates/shirabe-validate/src/`.

## Parent invariants the PRD inherits

From `PRD-roadmap-plan-standardization.md`:

- R8: staged reconciliation behind notice-then-error.
- R20: no day-one breakage on the committed corpus.
- R22: public-cleanliness of every notice body and rule.

The FC09 PRD re-states the public-cleanliness invariant at the
FC09-scoped layer (mirroring FC07's R12 re-statement) so downstream
implementers binding notice strings see the constraint at the layer
where strings are authored.

## Coverage Map (what the PRD must contain)

| Section | Source |
|---------|--------|
| Status (Draft) + frontmatter | format ref |
| Problem Statement | BRIEF Problem |
| Goals | BRIEF Outcome + parent R8/R20 |
| User Stories | BRIEF five journeys |
| Requirements R1..Rk | BRIEF scope inside-list + sub-checks A/B/C + self-disable contracts + bounded-iteration NFR + public-cleanliness NFR |
| Acceptance Criteria | one binary AC per requirement clause |
| Out of Scope | BRIEF excluded-list |
| Known Limitations | network dependency, rate-limit posture, cross-repo 403 staleness |
| Decisions and Trade-offs | 4-6 entries mirroring FC07 PRD pattern |
| Downstream Artifacts | sub-DESIGN and sub-PLAN |
| Related | BRIEF, FC07 PRD/DESIGN, parent PRD/DESIGN/PLAN, references |

## Research Leads (Phase 2 inline)

- BRIEF text settles all framing.
- FC07 PRD precedent for shape, tone, AC density.
- FC07 sub-DESIGN Decision 6 (class-vs-Status pass) as the
  architectural seed FC09 extends with `observed_state` from a GH client.
- `crates/shirabe-validate/src/validate.rs` for the `is_notice`
  membership site (current value `matches!(code, "SCHEMA" | "FC07")`).
- `references/issues-table.md` and `references/dependency-diagram.md`
  for the surfaces FC09 reconciles against (Status classes,
  cross-repo `owner/repo#N` form, strikethrough convention).
- GH issue #153 for the canonical acceptance criteria text the BRIEF
  was derived from.

## Decision (assumed) under --auto

Decision: proceed with scope above without user confirmation.
Status: assumed.
Review priority: low (BRIEF was just Accepted; no open questions).
Reason: --auto contract; BRIEF settles framing.
