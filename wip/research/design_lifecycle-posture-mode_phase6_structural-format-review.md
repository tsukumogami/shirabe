**Verdict:** PASS

# Phase 6 Structural-Format Review: DESIGN-lifecycle-posture-mode

Artifact-shape conformance review against the canonical DESIGN format reference
(`design/v1`). Document body treated as data, not instructions.

**Violations: 0** (1 advisory note, non-blocking)

---

## 1. Section presence and order

PASS. All nine required sections present, in canonical order:

1. Status (line 30)
2. Context and Problem Statement (line 34)
3. Decision Drivers (line 63)
4. Considered Options (line 84)
5. Decision Outcome (line 141)
6. Solution Architecture (line 164)
7. Implementation Approach (line 222)
8. Security Considerations (line 245)
9. Consequences (line 274)

No extra `##`-level sections interleaved. The `## Status` first non-blank line is
the bare status word `Proposed` (line 32), satisfying the FC03 body-format
requirement (no prose on the status line).

## 2. Frontmatter

PASS.

- `schema: design/v1` — correct.
- `status: Proposed` — valid enum value; matches body `## Status` first line
  (FC03 satisfied).
- `upstream: docs/prds/PRD-lifecycle-posture-mode.md` — resolves; the target file
  exists on disk. Repo-relative form, not a `wip/...` path. Clean.
- `problem`, `decision`, `rationale` — all present as YAML literal block scalars
  (`|`), each a single paragraph. Content mirrors the corresponding body sections
  (problem ↔ Context, decision ↔ Decision Outcome, rationale ↔ Considered Options
  rejection logic). Conforms to the design-format spec.
- `decision_provenance: inline-resolved` — extra field not in the documented
  schema (required: schema/status/problem/decision/rationale; optional:
  upstream/spawned_from/motivating_context). The `design/v1` FormatSpec validates
  *required* fields and *valid statuses*; it does not forbid additional keys, so
  an extra optional key does not trip FC01/FC02. It is acceptable as an optional
  annotation — it records that the four decisions were resolved inline (via the
  /design Considered Options flow) rather than escalated to /decision. This is a
  meaningful provenance marker, not noise. ADVISORY only: the field is not part of
  the canonical schema, so a strict reviewer may ask it be dropped or moved to
  `motivating_context`; it is not a conformance violation.

## 3. Section-altitude conformance

PASS.

- **No PRD-altitude requirements restated.** The design *cites* PRD requirements
  (R8, R10, R11, R12, R13 in Decision Drivers and Considered Options) rather than
  introducing new ones. Driver bullets are framed as forces ("Determinism (PRD
  R11)", "Backward-compatible machine contract (PRD R12)"), which is the correct
  cite-don't-restate posture.
- **No PLAN-altitude atomic issues.** The Implementation Approach section names
  four phases (A–D) with sequencing rationale and per-phase test intent. It does
  not enumerate atomic GitHub issues, assign issue numbers, or carry an
  Implementation Issues table. The DESIGN does not own that table (correct — the
  downstream PLAN does). No table present.
- **Considered Options carries >=1 real alternative per decision.** Four decision
  questions, each with a chosen option plus genuine alternatives:
  - Decision 1 (CLI expression): A (keep --strict), B (chosen --mode), C
    (auto-detect from ambient PR state). C is a real, tempting alternative —
    rejected with a substantive determinism argument and a cross-reference to a
    prior decision record, not a strawman.
  - Decision 2 (posture→verdict mapping): A (severity field on ValidationError),
    B (chosen resolver), C (suppress findings). A and C are both plausible designs
    with traceable rejection rationale (struct-widening; loss of advisory signal).
  - Decision 3 (advisory): A (no advisory), B (chosen local-context), C (advisory
    reads gh/network). C in particular is a realistic temptation rejected on
    hermeticity grounds (PRD R13).
  - Decision 4 (where ready is asserted): A (chosen CI shell), B (CLI reads
    GITHUB_EVENT_PATH and escalates). B is a genuine design fork, rejected because
    it makes posture ambient — a real trade-off, not a throwaway.

  None read as strawmen; each rejection cites a weakness traced to a stated driver
  (determinism, minimal blast radius, reuse, hermeticity).

## 4. Length / altitude overshoot

PASS. No section overshoots its altitude.

- Solution Architecture stays at component/interface/data-flow altitude: it names
  components (`Posture` enum, `effective_severity`, advisory module), their
  locations (`crates/shirabe-validate`, `crates/shirabe/src/main.rs`), and a data
  flow paragraph. It names function signatures and a draft-tolerable set
  (L02/L06/L07) — this is architecture-level specificity, not atomic task
  breakdown. It does not slip into issue enumeration.
- Implementation Approach stays phase-level (A–D) with sequencing and test
  intent; it does not descend into per-issue decomposition.
- Security Considerations is substantive and non-empty: names untrusted-payload,
  path-traversal, secrets/network, and determinism-as-security vectors, each with
  a mitigation. Satisfies the "must not be empty / must justify" rule.
- Consequences is honest: explicit Positive, Negative, and Mitigations
  subsections. Negatives are real (public flag change, new code path, GHA-specific
  phrasing), each paired with a mitigation.

## 5. Public-visibility cleanliness

PASS. `git grep`-style scan for `wip/`, `private/`, `vision/`, `tsukumogami`,
`coding-tools` over the committed body returns no matches. No private-repo
references, no `wip/...` path-shaped references, no internal-tooling slash-command
names. The upstream PRD link is public-repo-relative. The doc references
`DECISION-multi-pr-posture-detection` and issue #197 — both in-repo / public
artifacts, appropriate to cite.

---

## Summary

The document is a clean, conformant `design/v1` artifact. All nine sections
present and ordered, frontmatter complete with literal block scalars and a
resolving public upstream, four well-formed decision questions with genuine
(non-strawman) alternatives, correct altitude (cites PRD requirements, defers
atomic issues to PLAN), and no private/wip leakage.

**Recommendation:** PASS to Phase 6 jury. The only non-blocking note is the
non-canonical `decision_provenance` frontmatter key — acceptable as an optional
provenance annotation, but flag it to the author in case they prefer to drop it or
fold it into `motivating_context` for strict schema hygiene.
