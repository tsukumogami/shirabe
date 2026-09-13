# Testability Review (confirming): PRD-work-on-standalone-completeness

## Verdict

PASS

## The reconciliation — satisfiable and falsifiable

The three touch points now say the same thing in three places, and I checked all three against the current file rather than trusting the summary:

- R16a's disposition definition (line 232-234): `superseded` applies "when the document carrying it is corrected by a decision record under R18 rather than rewritten."
- The converse criterion (line 390-399): "Neither document R18 names has its contradicted text rewritten... its routing claim preserved verbatim — not reworded, not deleted. The only modification permitted to either is the addition of a pointer to the decision record."
- R18's own acceptance criterion (line 403-410): "Each of the two documents carries a pointer to that record, added without touching the contradicted text itself, which is the one modification the criterion above permits."

The bold absolute ("modified... at all") that caused the prior FAIL is gone; I grepped for "modified" and it now appears only in the bounded form "The only modification permitted... is the addition of a pointer." One implementation satisfies all three: for each of the two documents, leave every existing line byte-for-byte intact and append one new line or short block that names/links the decision record. A diff of before/after shows only added lines, zero removed or changed lines. That satisfies the converse criterion (claim verbatim), R18's criterion (pointer added, contradicted text untouched), and R16a's disposition definition (corrected by decision record, not rewritten) simultaneously. Nothing forces a second, incompatible edit to reach any of the three.

I also checked the premise the author cited for why the standard routes don't apply, since a wrong premise would undermine the whole reconciliation: `skills/prd/references/prd-format.md:165-166` reads "**No 'Superseded' state.** If requirements change fundamentally, create a new PRD and mark the old one as Done (with a note that it was replaced)" — confirmed at that exact location. `skills/design/references/design-format.md:227` reads "| any -> Superseded | A successor DESIGN names this one as `superseded_by:` | None; the doc stays where it is |" — also confirmed exactly. Both citations are accurate, and the PRD in question is already `Done` while the DESIGN has no successor, so neither route is available. The decision-record-plus-pointer mechanism is a legitimate third path, not a workaround invented to dodge the rule.

## Per-criterion falsifiability table

| Criterion | Checkable by | Catches quiet reword? |
|---|---|---|
| Converse (line 390-399): claim preserved verbatim | `git diff` of the two named files against pre-change state; any changed/deleted line in the claim's text fails it | Yes — a reworded claim shows as a removed+added line pair, which is exactly what "not reworded, not deleted" prohibits |
| R18 acceptance (line 403-410): decision record exists, pointer added, contradicted text untouched | Same diff, plus existence check on the decision record file and `shirabe validate`'s lifecycle/upstream-link check | Yes — same diff mechanism; a reworded claim under a pointer still fails "without touching the contradicted text itself" |
| R16a `superseded` disposition (line 385-389): document not edited in place, text not rewritten | Inventory row cross-referenced against the named document's diff | Yes — "text was rewritten" is the explicit failure condition, and it is evaluated on the actual file, not on the inventory's self-report |
| R16a `edited` disposition (line 381-384) | Named file contains "after" text, no longer contains "before" text | Not applicable to the two R18 documents — see coverage note below |

The important design point: even if an implementer tried to dodge by mislabeling one of the two R18 documents as `edited` instead of `superseded` in the inventory, the direct-diff criteria at lines 390-399 and 403-410 inspect the actual document content independent of what the inventory claims. A mislabeled row does not exempt the file from the verbatim-preservation check. The three criteria are cross-checking, not merely parallel.

## Requirement coverage map

- R16a (disposition, inventory correctness) — covered by the classification criteria at lines 381-389 plus the general inventory criteria at 375-380.
- R18 (supersession mechanism, decision record) — covered by the acceptance criterion at 403-410 and cross-checked by the converse criterion at 390-399.
- The anti-dodge property (original purpose: stop a row being labeled `edited` and the document rewritten in place) — survives. The weaker prohibition still forbids rewriting; it only additionally permits one narrow, additive, diff-visible action (a pointer). That is not a weakening of the anti-dodge guarantee, it is a correction of an overly broad prohibition that was factually impossible to satisfy given the two documents' actual lifecycle states.
- Every other requirement (R1-R15, R17, R19-R22) is unchanged from the prior review pass and was not in scope for this reconciliation; I did not re-derive their criteria but scanned the full Acceptance Criteria list (lines 328-425) and found no new internal contradictions introduced by this edit.

## Required changes

None.

## Observations

One soft spot, not a testability failure: the PRD does not bound the *size or form* of "a pointer" — a bad-faith implementation could in principle append a very large block of prose adjacent to the untouched claim that functionally recharacterizes it for a reader without touching the claim's own bytes. The diff-based check still passes in that case (no line of the original claim is touched), so this is a documentation-quality risk rather than a hole in the falsifiability of the stated criteria. It doesn't reopen the original dodge (row mislabeled + full rewrite), since the original text truly does survive verbatim in both the good-faith and this edge-case reading. Left as an observation because tightening it further is a design/implementation-time call, not a gap in what this PRD can verify.
