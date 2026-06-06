# Clarity Review

## Verdict: PASS

The PRD's requirements are unambiguous, each names a specific subject and binary-verifiable action, the four self-disable paths and the Sub-check C asymmetry are individually distinguishable, the bounded-behavior NFR's clauses each have their own AC, and the Decisions section reasons through alternatives with named rejections.

## Ambiguities Found

None that rise to the level of a clarity failure. Two minor edges worth surfacing as improvements rather than defects (see below).

## Suggested Improvements

1. **R5 parse-failure path could be made explicit.** R5 names `GITHUB_REPOSITORY` plus `GITHUB_REF` of the form `refs/pull/<N>/merge` (or `SHIRABE_PR_NUMBER`) as the PR-context detection surface. The PRD does not state what happens when `GITHUB_REF` is set but does not match the `refs/pull/<N>/merge` pattern (a `push`-event run, for example). The only sensible interpretation -- fall through to "no PR context" and engage R7 -- is consistent with R7's contract and AC at lines 432-436, but one implementer could match the pattern strictly and treat a non-match as "no PR context" while another could surface an error on a malformed PR ref. Rationale: one extra clause in R5 -- "a `GITHUB_REF` that does not match `refs/pull/<N>/merge` is treated as missing PR context" -- forecloses the interpretation gap.

2. **R14 implicit retry bound could be tightened.** R14 says rows that cannot be fetched for non-rate-limit / non-cross-repo reasons (HTTP 5xx, malformed payload) contribute no FC09 notice and the check proceeds with remaining rows. R15 implies a per-request single-retry bound ("at most a single retry on recoverable failure"). The composition is sound but the link is implicit. An implementer following only R14 could ask: do we retry per row, or just skip on first 5xx? Rationale: a one-clause cross-reference in R14 ("subject to R15's per-request single-retry bound") would make the totality contract more directly readable.

3. **"Status-bearing classes" is shorthand-defined-by-enumeration.** R2 introduces "Status-bearing classes" with the enumeration `(`done`, `ready`, `blocked`)`. The term is then used downstream (in R14 implicitly, in ACs explicitly). The enumeration suffices, but adding the phrase "the three Status-bearing classes (`done`, `ready`, `blocked`)" at first mention in R2's opening sentence would tighten reusability of the term across the doc. Cosmetic.

## Detailed Criteria Walk

**Requirement wording (PASS).** Requirements use declarative-present voice ("FC09 reconciles...", "FC09 authenticates...", "The check is dispatched..."). The voice is binding-imperative throughout R1-R17 -- no "should", "may", "appropriate", "reasonable", or "as needed" appears inside any numbered requirement or AC. (The hedging words appear elsewhere -- problem statement narrative, journey prose, decision rationales -- which is appropriate to those altitudes.)

**Requirement subject (PASS).** Every requirement names a concrete subject: "FC09", "The check", "The GitHub client surface", "Every notice FC09 emits", "FC09 and its client surface". No soft "The author should consider..." or "Implementers may want to..." forms.

**Acronym and term definition (PASS).** First-use definitions are present for the load-bearing terms:
- FC09 is named in title, frontmatter problem, and the opening section; sibling-check context (FC05, FC06, FC07, FC08) is established at the parent-PRD altitude this PRD inherits.
- `is_notice` is named with its mechanical role ("the `matches!` arm-shaped match that holds `SCHEMA` and `FC07`") in R10.
- `check_fc09` is named alongside its dispatch context (R1).
- `Closes #N` is named in R1 Sub-check C with its parsing surface (R13, Known Limitations).
- `GITHUB_TOKEN`, `gh auth status`, `GITHUB_REPOSITORY`, `GITHUB_REF`, `SHIRABE_PR_NUMBER` are named with their roles in R4-R5.
- `^I[0-9]+$` is named in R2 with its discrimination semantics.
- "terminal state" is parenthetically defined in R1 ("strikethrough applied in the plan profile, or Status `Done` in the roadmap profile").
- Pipeline-stage classes are enumerated in R2 and again in the AC at line 412-416.
- "Status-bearing classes" is defined by enumeration in R2.

**Sentence crispness (PASS).** Each requirement is its own paragraph (or labeled sub-paragraph for R1's A/B/C and R13's two directions). R1 is the longest but its structure is three labeled sub-checks, not a single compound sentence. R15 binds four guarantees (totality, defensive parsing, bounded retries, timeouts, no-token-logged) into one paragraph but each clause is independently verifiable -- and the ACs reflect that separation:
- AC line 480-484 verifies bounded behavior over malformed responses (no panic, no UTF-8 panic, no unbounded loop) -- ties to "totality" and "defensive parsing" clauses.
- AC line 485-488 verifies bounded retries with explicit timeouts -- ties to "bounded retries" and "timeouts" clauses.
- AC line 489-492 verifies the token never appears in any log surface -- ties to "no-token-logged" clause.

R12 has one long enumeration sentence (lines 322-327) that lists the four self-disable forms inline. This reads as a parenthetical enumeration rather than four bundled requirements -- the enforceability is carried by the corresponding AC at lines 465-469 ("four distinct, identifiable notice strings"). Not a defect.

**Decisions and Trade-offs reasoning (PASS).** Six decisions, each structured as `**Decision.**` + `**Alternatives considered.**` + `**Rationale.**`. Every decision names at least two alternatives, every alternative is paired with a named rejection reason:

- Decision 1: rejects (a) per-sub-check split (coupled client surface, coupled subset rule, coupled promotion seam) and (b) deferring Sub-check C (would force a second increment covering the same client surface).
- Decision 2: rejects (a) new severity level (existing two-level system suffices; FC07/FC08 precedent) and (b) flag-gated default-off (invisible to authors; no forcing function for cleanup).
- Decision 3: rejects (a) hard-fail on missing credentials (blocks local-dev; cost-benefit inverted) and (b) startup pre-flight (collapses four independent surfaces; prevents partial engagement).
- Decision 4: rejects (a) pre-commit `gh` subprocess and (b) pre-commit raw HTTP -- both for the same reason (HOW decision at the wrong altitude).
- Decision 5: rejects (a) sole reliance on parent R22 (downstream implementers may not consult; messages are exactly where leakage occurs) and (b) skipping public-cleanliness (CI logs may be world-readable).
- Decision 6: rejects (a) unbounded retries (CI timeout budget; runaway consumption) and (b) panic-catch shield (foot-gun; lets defensive-parsing bugs hide).

**Writing style (PASS).** No banned words appear: tier, tiered, robust, leverage, comprehensive, holistic, facilitate -- none. ASCII-only, em-dashes used as `--`. No emojis. No AI attribution. The voice matches the FC07 precedent (`PRD-table-diagram-reconciliation.md`) in tone and density.

**Specific surface audits requested by coordinator.**

1. *Four self-disable paths (R6-R9) and their notice forms (R12).* Each is distinguishable:
   - R6 missing-credentials: full self-disable, FC01-FC08 continue.
   - R7 missing-PR-context: Sub-check C only self-disables; A and B run.
   - R8 rate-limit-exhausted: per-request single retry then self-disable the *remainder*; prior notices preserved.
   - R9 cross-repo-access-denied: per-row skip; other rows reconciled.
   An implementer can encode all four distinct dispatch paths from the PRD text alone without re-reading the BRIEF. R12's "per-path notice form" clause and the four-distinct-strings AC at lines 465-469 verify that each path's notice is identifiable in CI output.

2. *Sub-check C asymmetry (R13).* Two directions, distinct notice forms, each binary-verifiable:
   - PR over-claims: `Closes #N` line on PR body, doc shows issue non-`done` -> notice names issue, PR body line, doc claim.
   - Doc anticipates a closure no PR delivers: `done`-claimed row, issue observed open on GitHub, no `Closes` line for it -> notice names row, diagram node, observed open state, absence of `Closes` line.
   ACs at lines 403-411 verify both directions. R13's last sentence ("Both directions are emitted by Sub-check C and both are subject to its missing-PR-context self-disable") binds R13 to R7 explicitly.

3. *Bounded-behavior NFR (R15).* Binds totality + defensive parsing + bounded retries + timeouts + no-token-logged in one paragraph. The ACs verify each clause independently (see "Sentence crispness" above). The check is binary-verifiable: totality by AC-line 480-484; bounded retries+timeouts by AC-line 485-488; no-token-logged by AC-line 489-492. The PRD does not say *what* the timeout values are -- but the Out-of-Scope section and Decision 4 explicitly defer concrete values to the sub-DESIGN, so the binding is "every external op has an explicit timeout" (verifiable: any external call without an explicit timeout fails the AC) rather than a specific value.

4. *Reconciling-subset rule (R2).* R2 names "matching FC07's reconciling subset" and re-states the rule inline (`^I[0-9]+$` filter; pipeline-stage exclusion; `None`-Issues-cell exclusion). An implementer reading R2 alone has the full subset rule; the cross-reference to FC07 is for traceability, not for content the implementer must look up. ACs at lines 412-423 verify the filter rules independently. Composition with FC07 is clean: R2's last sentence ("A doc whose Diagram or Table is malformed enough that FC07 emits structural notices is reconciled by FC09 only over the subset FC07 successfully extracted") makes the dependency explicit.

## Summary

The PRD is clear, binding, and free of interpretation gaps that would let two implementers build different things. Every requirement names a specific subject and a verifiable action; the four self-disable paths and Sub-check C's two directions are each independently encodable; R15's compound clauses each have a dedicated AC. The Decisions section reasons through alternatives with named rejections. Two minor improvements (R5 parse-failure path, R14 implicit retry bound cross-reference) would tighten the contract but neither rises to a clarity defect. Verdict: PASS.
