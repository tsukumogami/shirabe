# Category C: FAIL

Re-review of the corrected plan. Full pattern pass re-run over all eight issues
(not only the ones previously flagged), plus verification of every prior finding
against the applied text and against the actual current source for Issue 6's
grep-based ACs.

---

## Method

1. Re-ran the Pattern 1/3/7 keyword scan over the full updated plan text.
2. Re-verified each of my eight prior findings against the corrected AC text.
3. For Issue 6 specifically — since its correction is a shell command — actually
   ran the grep against the real tree and read every site it's meant to cover,
   rather than trusting the AC's own site count.
4. Applied adversarial reasoning (patterns 2/4/5/6) fresh to every AC that changed,
   to catch anything the correction itself introduced.

---

## Issues 1, 2, 3, 4, 5, 7, 8 — all prior findings resolved, no new findings

- **Issue 1** AC1 now requires the shared-core section to name and define all
  three branches at `issues-table.md`'s specificity and states "matching section
  headings is not sufficient" — closes the existence-without-correctness gap.
  The new retirement AC ("independently mergeable/rollback-able appear only
  inside... not as free-standing bullets... reviewability appears nowhere outside
  Stated Preference") gives the issue real negative/exclusion coverage.
- **Issue 2** AC1 now states both disjuncts of the condition explicitly, and the
  new AC ties the format contract to `L09`'s actual behavior ("a `split_rationale`
  present but naming none of the three branches fails `L09`") — closes both the
  weak-conditional gap and the format-contract/check agreement gap.
- **Issue 3** AC3 now exercises both directions with the reasoning inlined
  (constructibility before Issue 4, and what a stubbed departure branch would get
  away with) — closes the vacuous-departure-test gap completely; this is the
  strongest of the corrections, it reads as a definition of done rather than a
  checkbox.
- **Issue 4** AC2 now pins verification to the recorded resolved preference rather
  than to comparing final shapes, and states directly why shape-comparison alone
  can't distinguish a real header parse from a correlated fixture — closes the
  Pattern 5 / unchecked-causal-chain gap.
- **Issue 5** gained the malformed-header-value AC ("falls back to the default
  rather than using the value or erroring") — closes the missing-edge-case gap,
  and ties it to the design's own stated security mitigation.
- **Issue 7** AC1 now requires the fixture to carry a real edge and states the
  vacuous-truth reasoning inline; the new AC2 covers an unresolvable reference
  producing an error rather than a silently dropped edge — closes both the
  vacuous-pass and missing-failure-path gaps.
- **Issue 8** all three ACs now carry explicit negative/exclusion clauses: AC1
  ("a pointer to another document... does not satisfy this"), AC2 (bounded to
  two-to-three sentences, "does not re-argue"), AC3 ("appended as a clearly
  separated section rather than interleaved," "not phrased as superseding") —
  closes both the unbounded-prose-presence gap and the missing-negative-case gap.

**On the fresh Pattern 3 pass:** a literal keyword-only re-scan still shows no
hits in Issues 1, 5, 6, and 8 (their new negative-path ACs use "does not
satisfy," "falls back... rather than erroring," "blocked," "does not re-argue,"
"is not phrased as" — none of which are in the taxonomy's fixed trigger-word
list: fail/failure/error/invalid/edge case/empty/missing/etc.). Read
substantively rather than by regex, all four now carry genuine negative-path or
exclusion coverage, which is what the false-positive guard's *intent* protects
against — a wrong implementation that only handles the happy path would fail
these new criteria. I'm treating this as resolved rather than flagging a finding
that would only exist by being more literal than the taxonomy's own guard
intends. Flagging it here as a process note rather than a finding: an automated,
regex-only pattern pass over this plan would still under-count negative-path
coverage by four issues, because correction agents phrase exclusions
idiomatically rather than with the taxonomy's specific vocabulary.

---

## Issue 6 — one finding survives the correction, narrower and independently verified

The correction added the co-occurrence grep, the reviewer-confirms-each-site
clause, and the behavioral check against Phase 7's actual gate. All three are
real improvements. But the Goal's site inventory is still wrong, and one real
site still evades every mechanical check in the issue.

**Verified against actual source (not the Goal's claims):**

`crates/shirabe-validate/src/transition.rs` carries the gate-asymmetry comment at
**four** sites — lines 263, 469, 1960, 2011 — not the "two comment sites" the
Goal still states. All four were re-read directly and confirmed as real
Draft→Active-gate-keyed-on-mode comments. This part turns out *not* to be a live
gap for AC4: `grep -rn "human approval\|human-approval"` matches all four,
because each uses "human approval" or "human-approval" (with a hyphen) verbatim.
The grep is exhaustive over the whole tree, so it will force fixing all four
regardless of the Goal's undercount — the undercount is real but doesn't
translate into a surviving AC gap here.

`crates/shirabe-validate/src/lifecycle.rs` carries the gate-asymmetry comment at
**two** sites, not the one ("module doc") the Goal names: lines 45-61 (the
module doc — re-verified as one contiguous block, matches the grep) **and a
separate, unrelated-looking comment at line 764** — `/// (human-approved for
multi-pr, auto-fired for single-pr), so the` — which the Goal never identifies
as something to touch, and which evades every check in the issue:

- AC4's literal grep (`human approval\|human-approval`) does not match
  "human-approved" (different word form — participle vs. noun — confirmed by
  running the pattern against the line).
- AC5's co-occurrence grep requires `execution_mode` to co-occur; the literal
  token "execution_mode" never appears anywhere in that comment or its
  surrounding lines (760-768) — it says "differs between modes," not
  "execution_mode" — so the co-occurrence check also does not fire.
- The reviewer-confirmation clause is scoped to "the seven sites," and the
  Goal's own enumeration tells a reviewer to look at "lifecycle.rs's module
  doc" specifically — a reviewer following that instruction has no reason to
  scan the rest of the file for a second, structurally unrelated comment.

A wrong implementation that re-keys the module doc and all four `transition.rs`
sites (everything the corrected grep AND the Goal's list both point to) but
leaves `lifecycle.rs:764` exactly as it is today passes AC4, AC5's grep half,
and — if the reviewer trusts the Goal's site list rather than independently
re-deriving it — AC5's reviewer-confirmation half too. It would still assert the
old `execution_mode`-keyed rule in a committed doc comment.

*Corrected Goal text:* "...across all eight sites that carry it — five in skill
and format prose, and three in Rust doc comments (`lifecycle.rs`'s module doc,
`lifecycle.rs` line 764's separate posture-inference comment, and four comment
sites in `transition.rs` at lines 263, 469, 1960, and 2011)."

*Corrected AC (replace the "seven sites" reference in AC5):* "...across all
eight sites [as enumerated above] returns nothing outside that same quotation,
AND a reviewer independently re-derives the site list by reading every
`///`/`//!` doc comment in `lifecycle.rs` and `transition.rs` that mentions the
Draft→Active gate or execution mode — not by checking only the sites the Goal
names — since the Goal's own count has already been wrong once."

---

## Summary

FAIL, down from 8/8 issues with findings to 1/8. The seven corrections against
Issues 1, 2, 3, 4, 5, 7, and 8 each close the gap precisely — verified against
the actual applied AC text, not just the description of the correction. Issue 6
improved substantially (three of four original problems closed) but the Goal's
Rust-site count is still wrong in a way that's independently verifiable against
the real files, and it produces one concrete, named, currently-unclosed gap:
`crates/shirabe-validate/src/lifecycle.rs:764` can keep its stale
"human-approved for multi-pr" wording through every check in Issue 6 as
currently written.
