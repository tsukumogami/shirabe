# Category B: PASS

## Prior finding — resolved

The original finding (Issue 6's grep-based AC was unsatisfiable because two
Rust comment sites carrying the old "multi-pr requires human approval"
framing were missing from its Files list) is fixed on both ends, verified
directly:

- Design Decision E (docs/designs/DESIGN-multi-pr-plan-decoupling.md:309-341)
  now carries a seven-row table naming every site by kind, four prose/format
  plus `lifecycle.rs` (module doc) plus `transition.rs` (two comment sites)
  plus the decision record, states explicitly "no code implements it" is not
  "no code mentions it," and names the earlier four-site-plus-record
  enumeration as wrong. The Context and Problem Statement (line 94) now says
  "prose in seven places, two of them Rust doc comments." `grep -n "human
  approval\|human-approval" lifecycle.rs transition.rs` returns six hits
  across the two files, confirming the table's claim.
- Plan Issue 6 (docs/plans/PLAN-multi-pr-plan-decoupling.md:258-304) now
  names "all seven sites... five in skill and format prose, and two in Rust
  doc comments," its Files list includes `crates/shirabe-validate/src/lifecycle.rs`
  and `crates/shirabe-validate/src/transition.rs`, its grep AC is now a
  concrete command run against `skills/ crates/ docs/`, and a second AC
  requires a human read-through against paraphrase evasion (Category C's
  concern, correctly out of my scope).

No finding remains from this issue.

## Second requested check — Decision C's `/work-on`/`/execute` claim — the correction is accurate, but it did not fully propagate

Verified `/execute`'s actual behavior: `skills/execute/SKILL.md:40` states
"`multi-pr` — out of scope for `/execute`; multi-pr plans run one issue at a
time." So the corrected claim in Consequences (Negative, lines 597-609) is
accurate: "`/execute` declines `multi-pr` outright... so there is no
path-driven fallback either... an earlier draft of this section understated
it by claiming the author could drive the plan by path 'the way `/execute`
already drives single-pr and coordinated plans' — `/execute` does not drive
multi-pr at all. *Mitigation:* none within this design's scope." That
correction is correct and matches Category A's finding.

**But the correction was applied only in Consequences, not at the other place
the same false claim lives.** Decision C's own "What is lost" paragraph
(lines 252-255) still reads: "`/work-on M<N>` has no milestone to resolve
against when tracking is `none`. The entry point is genuinely gone for that
combination; the author drives the plan by path instead, the way `/execute`
already drives single-pr and coordinated plans." That is the exact sentence
Consequences now quotes and refutes as false, word for word, still standing
uncorrected two sections earlier in the same document. A reader who stops at
Decision C — which is where a reader deciding whether to accept the
trade-off would naturally look — gets the false, mitigated-sounding version;
only a reader who continues to Consequences gets the corrected,
unmitigated-capability-gap version. This is not currently encoded in any
plan issue (grepped the PLAN and PRD for "drives the plan by path" and
"work-on M<N>" — no hits), so it does not break an issue's AC the way the
prior finding did, but it is a stale statement that survived this round of
revision and should be fixed before the design is finalized: either delete
the "the author drives the plan by path instead, the way `/execute` already
drives single-pr and coordinated plans" clause from line 254-255, or replace
it with a forward reference to the corrected Consequences entry.

**A second, smaller instance of the same pattern:** the Solution Architecture
component table row for `plan-doc-structure.md` (line 415) still reads
"...one of Decision E's five prose sites" — a leftover count from before
Decision E was rewritten to seven sites. The two other component-table rows
touched by the same fix (`lifecycle.rs` line 418, `transition.rs` line 420)
were correctly updated to the new seven-site framing; this one row was
missed. Same disposition as above: not inherited by any issue (Issue 1's and
Issue 6's Files/ACs are unaffected — the row only describes `plan-doc-
structure.md`, which is already in Issue 6's Files list), but it is residue
from the revision that should be corrected to keep the document internally
consistent — change "five" to "seven" (or drop the count and just say "one
of Decision E's prose sites").

I checked the rest of Consequences (Positive and Negative) and the
Decision-Drivers cross-references for similar unchecked cross-file capability
claims (`DESIGN-roadmap-issueless-preference.md` rejecting a config file, the
`issues-table.md`/`dependency-diagram.md` shared-core-plus-profile precedent
cited by Decision D) — both check out against the actual files in the tree.
No other entry makes a claim of this kind that doesn't hold.

## Verdict rationale

No issue currently encodes a contradiction inherited from the design — the
grep-AC-breaking defect from the last round is fully fixed in both documents.
The two items above are design-only residue: statements that were true
before this revision's fixes and are now false-by-omission of an update,
but neither is quoted or relied on by any PLAN issue. Recommend fixing both
before the design is finalized, but they do not block this plan on Category
B's own finding criteria (an issue's body/AC does not encode either stale
claim).
