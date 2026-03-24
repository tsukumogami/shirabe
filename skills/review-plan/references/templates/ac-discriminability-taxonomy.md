# AC Discriminability Taxonomy

This file documents the 7 AC failure patterns used by Category C review (Phase 3).

Phase 3 runs two passes:
1. **Pattern pass** — scans AC text for automatable signals (patterns 1, 3, 7)
2. **Adversarial pass** — prompts the review agent to reason taxonomically for ACs
   that didn't match in the pattern pass (patterns 2, 4, 5, 6)

Full pattern specifications and detection triggers are added in Issue 3.

---

## Pattern 1 — Fixture-anchored

[To be completed in Issue 3]

**Failure mode:** AC passes because test data is pre-populated; a wrong implementation
that skips initialization still satisfies the criterion.

**Detection method:** Pattern pass (automatable)

---

## Pattern 2 — Mock-swallowed

[To be completed in Issue 3]

**Failure mode:** AC passes against a mock dependency that hides the real failure.

**Detection method:** Adversarial pass (semantic reasoning required)

---

## Pattern 3 — Happy-path only

[To be completed in Issue 3]

**Failure mode:** No AC in the issue mentions a failure case, error condition, or
edge case; a wrong implementation that handles only the happy path passes all criteria.

**Detection method:** Pattern pass (automatable)

---

## Pattern 4 — State-without-transition

[To be completed in Issue 3]

**Failure mode:** AC checks final state but not the transition; a wrong implementation
that starts in the target state passes without performing the required operation.

**Detection method:** Adversarial pass (semantic reasoning required)

---

## Pattern 5 — Integration scope gap

[To be completed in Issue 3]

**Failure mode:** AC can only be observed through integration; unit-scope verification
misses the actual behavior under test.

**False-positive guard:** Only flagged when integration scope is the *only* observable
path — not for every unit AC.

**Detection method:** Adversarial pass (semantic reasoning required)

---

## Pattern 6 — Interface name drift

[To be completed in Issue 3]

**Failure mode:** AC references an interface or method name that differs from the
design doc; a wrong implementation using the design-doc name passes the criterion
while the correct implementation fails.

**Detection method:** Adversarial pass (semantic reasoning required; requires
reading the upstream design doc)

---

## Pattern 7 — Existence-without-correctness

[To be completed in Issue 3]

**Failure mode:** AC checks that something exists or was created but not that it
contains the correct content; a wrong implementation that creates an empty or
malformed artifact passes the criterion.

**Detection method:** Pattern pass (automatable)
