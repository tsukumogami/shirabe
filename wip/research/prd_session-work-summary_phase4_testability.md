# Testability Verdict: PRD-session-work-summary

## Verdict

PASS

## Assessment

### 1. Acceptance criteria — binary pass/fail

All 11 acceptance criteria are phrased as observable outcomes a non-author can
check by driving the session and inspecting output. None require subjective
judgment except mild residue:

- AC1–AC6, AC8–AC11 are cleanly binary (block produced / summary appears /
  suppressed / dropped / marked best-effort / repo named / present in final
  message / answers correctly). Verifiable.
- AC6 "with a freshness indication" is binary at the level of *presence* of an
  indicator, but does not say what a correct indication is. Testable as "an
  indicator is present"; not testable as "the indicator is accurate." Minor.
- AC9 "private-repo PR does not appear in a public-visibility summary" is binary
  and is the strongest edge-case criterion in the set.

No criterion demands taste-based judgment. Pass on this axis.

### 2. Requirement-level testability (R1–R15)

Functional R1–R12 are each independently testable — I can write a scenario test
for each (block shape, entry fields, ordering + terminal-drop, live derivation,
integrity, event emission, absence trigger, dedup, on-demand, compaction
awareness, worker final message, multi-repo visibility).

Non-functional:
- **R13 (latency + degradation)** — two halves. Degradation is testable and is
  covered by AC8. The latency half ("sub-second under normal conditions for a
  handful of PRs") is soft but measurable in principle (time a render with N
  PRs). Testable, though no AC exercises it (see §6).
- **R14 (legibility across terminal widths)** — borderline. "Legible" is
  subjective, but the operative clause "without breaking the usability of the URL
  on each entry" is checkable (render at 80/100/120 cols, confirm the URL is
  still a single selectable token or intact). Testable in principle; no AC.
- **R15 (bounded per-emission cost)** — "bounded and small relative to the
  session's context budget" has no numeric threshold, but token cost per emission
  is measurable, so it is testable in principle. "Favor signal over volume" is
  pure vibes and not independently testable — it restates the emission policy
  already pinned down by R6/R7/R8. Acceptable as intent framing, not as a
  standalone testable clause. No AC.

No requirement is pure-vibes to the point of being untestable; the soft NFR
thresholds are testable-in-principle as the PRD intends.

### 3. Edge-case coverage

All five named edge cases are covered by a discrete criterion:
- compaction → AC11
- offline/unreachable gh → AC8
- private-repo visibility → AC9
- terminal-state drop → AC5
- duplicate suppression → AC4

Happy path covered by AC1–AC2. Coverage is complete on the enumerated set.

### 4. Criteria that merely restate a requirement

None are bare restatements. AC4 vs R8 and AC5 vs R3 come closest, but each AC
adds an observable behavioral check ("no duplicate automatic summary is
emitted", "appears in one summary after the transition, then no longer") rather
than echoing the SHALL. Pass.

### 5. R5 / AC7 — data-integrity operationalizability

AC7: "Every entry's URL corresponds to a real pull request; no summary emits a
PR reference that does not resolve to an actual PR."

- The **positive** clause is operationalizable: take a rendered summary, resolve
  each URL, confirm each is a real PR. A non-author can run this.
- The **universal negative** ("no summary ever emits a fabricated reference") is
  not exhaustively verifiable and, as written, AC7 does not describe the test
  that actually exercises R5's stated failure mode — stray PR-shaped text in a
  transcript being picked up. The strongest operational test would inject a
  fabricated/stray PR reference into the session and assert it does NOT enter the
  summary. AC7 tests "what is emitted resolves," not "what should be excluded is
  excluded." R5 is testable; AC7 under-specifies the test that proves it.
  Advisory to strengthen — not a blocker, since the positive check is real.

### 6. Requirements with no AC / ACs with no requirement

- **R13 latency half** — no AC measures render time. Degradation half covered
  (AC8), latency half uncovered.
- **R14 (legibility/wrapping)** — no AC.
- **R15 (bounded cost)** — no AC.
- **R10 consistency half** — AC11 covers the "restored after compaction" clause,
  but the "conversational answers stay consistent with the summary" clause (and
  user story 6, narrative-vs-summary agreement) has no dedicated AC.

No AC tests something no requirement states — every AC traces to a requirement.

The gap is one-directional: three NFRs (R13-latency, R14, R15) and half of R10
lack acceptance criteria. These are soft/non-functional, testable in principle,
and the PRD is explicit that ambient thresholds are intentionally loose, so this
is a coverage weakness rather than an untestability defect. It does not sink the
PRD but should be recorded.

## Required Changes (if FAIL)

None (PASS).

## Advisory Notes

1. Strengthen AC7 to include the exclusion path: add a criterion that injects a
   stray/fabricated PR-shaped reference into the session and asserts it does not
   appear in the summary. This is what actually operationalizes R5; the current
   AC7 only verifies emitted URLs resolve.
2. Add a criterion (or accept as explicitly untested) for R13's latency half —
   e.g. "a summary for a handful of PRs renders within the interactive budget."
   Even a soft numeric anchor makes it checkable.
3. Add a legibility criterion for R14 (URL remains selectable/intact when
   rendered at common terminal widths) and a cost criterion for R15 (per-emission
   token cost stays within a stated bound), or state in the PRD that these NFRs
   are validated by inspection rather than a discrete AC.
4. Consider an AC for the R10 consistency clause (agent's conversational answers
   about in-flight PRs match the current tracked set), covering user story 6 —
   distinct from the compaction-recovery check in AC11.
5. AC6's "freshness indication" is testable only for presence; if accuracy of the
   freshness value matters, tighten the wording.
