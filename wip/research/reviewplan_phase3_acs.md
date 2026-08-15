# Category C: FAIL

Third pass. Full pattern scan re-run over all eight issues; Issue 6 re-reviewed
in depth, including running every grep command in its ACs against the real tree
and checking the "leave" judgment against this project's own design-lifecycle
documentation rather than taking the framing at face value.

---

## Issues 1, 2, 3, 4, 5, 7, 8 — unchanged, no findings

Re-scanned; nothing in these issues changed since the last pass and the keyword
scan shows the same result (fail/error/conflict language present in 2, 3, 4, 7;
substantive negative-path coverage present in 1, 5, 8 without the taxonomy's
exact trigger words, as previously assessed). No new findings.

---

## Issue 6 — two new, narrow findings; plus a direct answer on the `leave` judgment

The eleven-site table, the file-scoped completeness check, and the byte-identity
check on the four `leave` lines are all independently verified accurate: I ran
`grep -cniE "(human[ -]approv|approval gate)"` against all six `re-key` files and
got exactly the "before" counts the AC states — SKILL.md 1, plan-doc-structure.md
3, phase-7-creation.md 1, plan-format.md 0, lifecycle.rs 3, transition.rs 4,
totaling twelve. That part is solid and matches the tree exactly.

### Finding 1 — the discovery check's own explanation is wrong about one line

AC text: "it requires `multi-pr` on the *same line*, so it misses
`transition.rs:1960` and `:2011` and `lifecycle.rs:61` and `:764`." I ran the
exact command:

```
grep -rniE "multi-pr" skills/ crates/ docs/ | grep -iE "(human[ -]approv|approval gate)"
```

`transition.rs:1960`, `:2011`, and `lifecycle.rs:61` are indeed absent from the
output — confirmed. But `lifecycle.rs:764` **is** in the output: `/// (human-approved
for multi-pr, auto-fired for single-pr), so the` — "multi-pr" and "human-approved"
are on the same line there, unlike the other three. The claim that the discovery
check misses it is simply false; it's a misreading of which sites the two checks
overlap on. This doesn't break the AC's soundness (the file-scoped completeness
check still catches `:764` correctly, since it's pattern-based, not co-occurrence-
based), but the AC as written misdescribes its own paired-check reasoning, which
is exactly the kind of unverified claim that produced the original three-error
version of this issue.

*Correction:* drop `lifecycle.rs:764` from the "misses" list — the discovery
check misses only `transition.rs:1960`, `transition.rs:2011`, and
`lifecycle.rs:61`, all because the mode name sits on a neighbouring line, not
because of the "human-approved" wording variant.

### Finding 2 — the discovery check's own success bound is unsatisfiable, even for a correct fix

The AC requires the discovery-check grep to return "hits only at the four `leave`
sites and the amendment's quotation." I ran it against the tree as it stands
today (mid-review, with Issue 6's corrected Goal/AC text already in the plan) and
it also returns two more hits that are neither:

- `docs/designs/DESIGN-multi-pr-plan-decoupling.md:357` — this design's own
  Decision E prose, listing "human-approval", "human-approved", and
  "multi-pr-style approval gate" as the phrasing variants a verification pattern
  must cover.
- `docs/plans/PLAN-multi-pr-plan-decoupling.md:270` — this very PLAN's Issue 6
  Goal text, for the same reason.

Both are durable, committed artifacts (not `wip/`) that will remain in the tree
after Issue 6 merges, and both legitimately quote the old phrasing as
documentation of what changed — there's no way to write this Goal section, or
the design's Decision E table, without naming the exact strings being retired.
A correct implementation of Issue 6 does not remove either quotation, so the
discovery check as literally scoped will never return clean, even once every
real site is fixed. This is a bound that fails a correct implementation, not one
that passes a wrong one, but it's the same discriminability defect in the
opposite direction — the AC can't be satisfied at all as written.

*Corrected AC:* "...returns hits only at the four `leave` sites, the amendment's
quotation, and this design's and this plan's own prose describing the phrasing
variants (`DESIGN-multi-pr-plan-decoupling.md` and
`docs/plans/PLAN-multi-pr-plan-decoupling.md` themselves) — catching any other
site the design's table failed to enumerate."

### The `leave` judgment — two of the four are wrong, verified against this project's own conventions

You asked me to say so if a historical DESIGN should in fact be re-keyed. Two
should be.

`skills/design/references/lifecycle.md` and `design-format.md` are explicit about
what `docs/designs/current/` means: *"Current | The PLAN has shipped. The DESIGN
documents the current architecture"* and *"The directory move on `Planned ->
Current` is load-bearing: it distinguishes designs that documented historical
decisions from designs that document the current architecture. A reader scanning
`docs/designs/current/` sees only currently-applicable designs."* That is the
opposite of "records what was decided when written" — a `Current` DESIGN's whole
reason for living in that directory, instead of staying in `docs/designs/` or
moving to an archive, is that it is supposed to stay accurate. `DECISION-*.md`
files are genuinely point-in-time records (hence "amend, do not rewrite" is
correct there, and for Decision 6's own text in
`DESIGN-roadmap-plan-standardization.md`, which Issue 8 amends the same way).
Treating all three `Current` DESIGN mentions the same way as the DECISION file is
a category error against this project's own stated definition.

I checked all three directly (`status: Current` confirmed in each frontmatter):

- **`DESIGN-lifecycle-draft-ready-discipline.md:398`** — a parenthetical inside a
  passing-state table description, about a different subject (strict-mode
  posture detection) that mentions the gate's asymmetry only as supporting
  context. Should be **re-key**, not leave: it's collateral prose describing
  current mechanics, structurally identical in kind to the Rust doc comments
  Issue 6 already re-keys as comment-only edits.
- **`DESIGN-shirabe-artifact-decision-contract.md:453`** — same situation, a
  different subject (the durable-vs-working artifact contract) mentioning the
  gate as context. Should be **re-key** for the same reason.
- **`DESIGN-roadmap-plan-standardization.md:577`** — closer call, and I'd leave
  it as currently judged, but flag an inconsistency: this line is in a *Data
  Flow* paragraph, not in Decision 6's own text, so "amended separately by
  Decision 6's own amendment" doesn't actually cover it — Issue 8's amendment
  targets Decision 6 specifically, and line 577 sits elsewhere in the same
  document. If the "leave because it's amended elsewhere" reasoning is meant to
  extend to the whole document (not just Decision 6's text), that's worth
  stating explicitly rather than implying the amendment already covers it.
- **Golden fixture** — correctly `leave`. Pinned test input; no objection.

Re-classifying the first two as `re-key` changes the split from "six re-key, one
amend, four leave" to eight re-key, one amend, and one-to-two leave (depending on
how the `roadmap-plan-standardization.md:577` question above is resolved), adds
those two DESIGN files to Issue 6's `Files` list and to the file-scoped
completeness check (one occurrence each, by my count, bringing the "twelve
occurrences to clear" total to fourteen), and removes them from the discovery
check's expected-hit set.

---

## Summary

FAIL. Issues 1, 2, 3, 4, 5, 7, and 8 are clean — verified fresh, no regressions.
Issue 6 is close but not there: one factual error in its own explanatory text
(which line the discovery check misses), one unsatisfiable success bound (the
discovery check can never return clean because this design and this plan
legitimately quote the retired phrasing), and a `leave` judgment that's right for
the golden fixture, arguably right for one DESIGN doc, and wrong for two —
`DESIGN-lifecycle-draft-ready-discipline.md` and
`DESIGN-shirabe-artifact-decision-contract.md` are `status: Current` specifically
*because* this project's own lifecycle documentation wants them to stay accurate,
which is the opposite of the "falsifies the audit trail" reasoning used to
exempt them.
