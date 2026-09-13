# Clarity Review (confirming): PRD-work-on-standalone-completeness
## Verdict
FAIL
## The rewritten R18 criterion
The acceptance-criterion bullet now reads (line 401-407):

> A decision record exists that names both superseded items — the requirement
> in the plan entry point's PRD and the chosen option in the `Current` design —
> and states what supersedes each and why. **The record carries the pointer;
> the superseded documents are not edited to carry it**, which is what keeps
> this criterion consistent with the prohibition above on modifying them. The
> validator reports no lifecycle or upstream-link violation (R18).

This resolves the prior contradiction cleanly: possession of the "record of
what superseded them" is now explicitly placed on the decision record, not on
the two documents, and the sentence names the exact prohibition it is
reconciling itself with. Read next to the "Neither document R18 names is
modified by this change at all" bullet, the two now state one rule from two
angles rather than disagreeing.

## R18 and R16a — the terminal-status interaction
R18 (lines 274-279) now says: "a requirement in the plan entry point's own
PRD, which is at `Done`, and the chosen option in a DESIGN at `Current` ...
Both are at a terminal status by R16a's own definition, and they are inside
the surface only because R16a names them in addition to it; they are the
exception the exclusion is written around, not instances of it."

R16a's surface definition (lines 238-256) independently states the same
bidirectional relationship: the surface is the live operational corpus "plus
exactly the two settled documents R18 names as superseded," and separately
explains why a DESIGN's terminal-equivalent status is `Current` (since DESIGN
has no `Done` state) — matching R18's use of `Current` rather than `Done` for
the design. The two passages cross-reference each other correctly and use the
same status vocabulary (`Done`, `Current`) throughout that pair of sections.
This reads as deliberate, not as two rules in tension.

## Required changes
The Decisions and Trade-offs entry for the superseding decision (line
515) was not updated to match R18's corrected, status-accurate language and
reintroduces the same imprecision the R18 fix removed:

> **Decided:** one decision record amending both the accepted requirement and
> the chosen design option, rather than editing either in place.

`Accepted` is a defined, load-bearing lifecycle term in this same document —
R16a states explicitly that "`Accepted` is NOT such a status for any type: an
Accepted BRIEF still feeds a PRD and an Accepted PRD still feeds a DESIGN, so
both remain live operational documents inside the surface." That is the
opposite of what R18 is describing here: the PRD requirement in question is at
`Done`, not `Accepted`, and its being at `Done` (a terminal status) is the
entire reason it needs a decision record instead of an edit. Calling it "the
accepted requirement" in the very next major section, using a word this PRD
has reserved for a different, non-terminal status with different
consequences, reopens the ambiguity R18's rewrite just closed. A reader
cross-referencing this line against R16a's `Accepted`-is-not-terminal carve-out
could reasonably conclude the wrong document is being superseded, or that
`Accepted` and `Done` are being used interchangeably.

Fix: replace "amending both the accepted requirement and the chosen design
option" with wording that matches R18's own terms, e.g. "amending both the
`Done`-status PRD requirement and the `Current`-status chosen design option."

## Observations
No other instance of stray "accepted" language was found outside the one
legitimate, capitalized, defined use in R16a's own carve-out paragraph (lines
250-251) and this one leftover in the Decisions and Trade-offs section. The
rest of the R18/R16a pairing — surface definition, disposition scheme, and the
acceptance criteria for `edited`/`superseded`/`delegated` rows — is internally
consistent.
