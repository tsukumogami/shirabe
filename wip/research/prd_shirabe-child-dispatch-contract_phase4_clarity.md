# Clarity Review

## Verdict: PASS

The PRD's mechanism-neutral framing is consistently applied across requirements, acceptance criteria, and out-of-scope items. Ambiguous-sounding words ("appropriate," "reasonable," "as needed") are absent; load-bearing terms ("dispatch mechanism," "team-shape declaration," "Layer 1," "Layer 2") are tied to existing pattern-reference vocabulary.

## Ambiguities Found

1. **AC1 "or equivalent" wording.** AC1 says "exactly one top-level section whose heading identifies it as the dispatch contract (e.g., `## Child-Dispatch Contract` or equivalent)." The "or equivalent" softens a binary criterion. Suggested clarification: AC1 SHOULD bind a grep-anchorable substring (e.g., "the heading text contains 'dispatch contract' or 'child-dispatch contract' as a substring"), since the structural-floor purpose of AC1 is to make the section grep-findable. Two reviewers could read "or equivalent" differently — this is the same flaw the PRD is fixing in the pattern.

   **Correction location**: AC1 line.
   **Suggested rewording**: "...whose heading text contains the case-insensitive substring 'dispatch contract' or 'child-dispatch contract'." This is grep-anchorable and matches the PRD's own AC-design philosophy.

2. **AC2 "structured grep against the contract section."** AC2 says "running a structured grep against the contract section surfaces four element markers." "Structured grep" is not a defined verb in this PRD. Suggested clarification: name the grep concretely (e.g., "running `grep -n '^### '` against the contract section returns at least four lines"), or note that the four markers may be sub-headings, bold-text leaders, or frontmatter-style labels — DESIGN's call, but the AC names what gets greppped.

   **Correction location**: AC2 line.
   **Suggested rewording**: "...identifiable by a sub-heading (e.g., `### R2.1 — Dispatch Mechanism`), a bold-text leader, or an equivalent grep-anchor. The four markers are findable by a structural grep DESIGN specifies; the marker shape is fixed at contract-section time."

3. **AC18 / AC19 / AC20 judgment-based criteria.** These three are explicitly judgment-based per L2 (Known Limitation). The PRD already labels them as such. No ambiguity; the limitation is acknowledged. Leaving as-is.

## Suggested Improvements

1. **R2.3 observability surface: clarify the positive vs negative statement.** R2.3 says "The contract's positive statement of the observability surface SHALL be explicit; relying solely on R14's negative statement is insufficient." This is correct, but the distinction between "positive" and "negative" statements is implicit ground-truth. Suggested clarification: add a parenthetical example: "(positive: 'the parent reads the child's durable artifact at `docs/<type>/<TYPE>-<topic>.md` for terminal-artifact polling'; negative: 'R14 prohibits the parent from reading the child's `wip/` internals')."

2. **R5 "identical" cross-reference shape.** R5 says "the same heading text in the same SKILL.md slot, the same cross-reference shape in the same Phase 2 slot." "Same shape" is borderline; it's clearer to bind "verbatim with substitution only for child names and topic-slug placeholders." The PRD already names this in AC13 — R5 could pull AC13's specificity inline.

## Summary

PRD passes clarity review with minor wording adjustments. Two AC ambiguities (AC1 "or equivalent"; AC2 "structured grep") are minor — the load-bearing meaning is clear from context but a reviewer could read them more loosely than intended. Two suggested improvements to R2.3 and R5 add specificity without changing scope. None of these are blocking; all are post-Accept polish.
