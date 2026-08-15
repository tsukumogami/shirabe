# Category B: FAIL

## Finding 1 — Decision E's "five sites" undercounts real occurrences of the old framing; Issue 6 will fail its own AC

- category: B
- affected_issue_ids: [6]
- description: Design Decision E states the Draft→Active gate asymmetry
  ("multi-pr requires human approval") "lives in skill prose in five places"
  and that "[n]othing in `transition.rs` or `lifecycle.rs` implements that
  gate" (true in the narrow sense of *implements*), then concludes the re-key
  is confined to "a prose-only re-key across five sites" — SKILL.md,
  plan-doc-structure.md, phase-7-creation.md, plan-format.md, plus a separate
  decision-record amendment. In fact the same "multi-pr requires human
  approval" framing is also restated verbatim in two Rust source comments the
  design never accounts for: `crates/shirabe-validate/src/lifecycle.rs`
  (module doc, ~line 51: "the only branch is the Draft -> Active gate:
  multi-pr requires human approval (GitHub issues + milestone are created on
  the transition)") and `crates/shirabe-validate/src/transition.rs` (two
  occurrences, ~line 263 and ~line 469: "the gate difference between modes
  (auto for single-pr, human-approval for multi-pr) is enforced out-of-band by
  the calling skill"). Neither file appears in Issue 6's Files list
  (`skills/plan/SKILL.md`, `skills/plan/references/plan-format.md`,
  `skills/plan/references/quality/plan-doc-structure.md`,
  `skills/plan/references/phases/phase-7-creation.md`,
  `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md`). Issue
  6's own AC reads "A grep for the old framing returns nothing outside the
  amendment's own quotation of it" — that AC is unsatisfiable as scoped,
  because `lifecycle.rs` and `transition.rs` will still carry the
  "multi-pr...human approval" phrasing after Issue 6 lands, and neither is the
  amendment's quotation. This is a design under-specification (the site count
  and enumeration are wrong) that the plan inherited verbatim into an issue
  whose acceptance criterion cannot pass against the real codebase.
- correction_hint: (empty — Category B correction requires re-running Phase 1
  Analysis to fix the design's site enumeration before issue content changes)

## Other checks — no findings

1. **Design decisions A–E vs. issues.** Faithfully reflected. Decision A's
   exact header names/vocab (`## Delivery Preference: consolidated|atomic`,
   `## Tracking Level: none|issues|issues-and-milestone`) are used unchanged
   in Issues 4–5. Decision B's `L09`/`DraftTolerable`/`FormatSpec`-untouched
   shape matches Issue 3's ACs verbatim, including the short-circuit ordering.
   Decision C's `ISSUE_SOURCE=plan_item`, `m-<slug>` scheme matches Issue 7.
   Decision D's `references/split-triggers.md` shared-core-plus-profiles
   matches Issue 1. Decision E's re-key-not-supersede treatment of the
   decision record matches Issue 6 (apart from Finding 1 above).

2. **Design self-consistency across its two revisions.** `FC20` appears
   exactly once, inside the "rejected on review" alternative in Decision B —
   correctly retained as historical record, not a stale live reference; grep
   confirms no other `FC20` mention anywhere in the design. The
   `tracking_level` re-resolution question is stated consistently everywhere
   it appears (Decision Outcome, Solution Architecture component table, both
   data-flow diagrams): the field is written once at authoring time and read
   from the PLAN by extraction, never re-resolved from CLAUDE.md. No stale
   statement implying re-resolution survives.

3. **Design's factual claims, verified against source:**
   - `L08` is the highest lifecycle code in use (`crates/shirabe-validate/src/lifecycle.rs:1107`, module-doc catalog stops at L08) and `L09` does not yet exist anywhere in the crate — confirmed, `L09` is free.
   - `L06` is a legitimate single-document-property precedent — confirmed. The code comment "L06 is chain-scoped, not member-scoped" (lifecycle.rs:1219) refers only to how the check *locates* its subject (it needs chain traversal to find the chain's single-pr PLAN); the property it verifies is entirely within that one PLAN's own body (outline-AC checkboxes), matching the design's characterization exactly. `L09` needs no chain traversal at all, so it is a strictly simpler case of the same precedent.
   - `validate.rs` documents the FC-family as `AlwaysEnforced` in two places — confirmed at lines 62–63 and 106–107 (near-identical doc comments, both stating "the entire FC-family...is AlwaysEnforced").
   - Nothing in `transition.rs` or `lifecycle.rs` **implements** the Draft-to-Active approval gate as code — confirmed; `transition.rs` explicitly states in its own comment that the gate is "enforced out-of-band by the calling skill, not by this subcommand," and no branch in either file conditions the Draft→Active edge on `execution_mode`. (But see Finding 1: both files' *comments* restate the old framing in prose, which the design's claim glosses over.)

4. **Decomposition Strategy vs. Implementation Approach.** The mapping is
   stated in the plan's own Decomposition Strategy section and is correct:
   Batch 1 (record/emitter/check) = Issues 1–3; Batch 2 (delivery preference)
   = Issue 4; Batch 3 (tracking level) is split across Issues 5 and 6, a
   reasonable finer-grained decomposition of one design batch into two
   reviewable issues, consistent with the design's own statement that the
   header/gating half and the gate-re-key half are independent within that
   batch; Batch 4 (issueless extraction) = Issue 7. Issue 8 (amending
   `DESIGN-roadmap-plan-standardization.md` Decision 6) is not named as one of
   the design's four batches but is listed in the design's Solution
   Architecture component table, so its addition as a ninth artifact is a
   correct pickup of an unbatched component rather than a contradiction.
   Issue 7 depending only on Issue 5 (not Issue 6) is also correct: the
   design's stated reason for Batch 4 depending on Batch 3 — "the tracking
   level has to be resolvable" — is fully satisfied by Issue 5 alone (which
   writes `tracking_level` to frontmatter); Issue 6 is pure prose re-key with
   no bearing on extraction.
