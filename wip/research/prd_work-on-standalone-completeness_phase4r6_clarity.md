# Clarity Review (round 6): PRD-work-on-standalone-completeness

## Verdict

PASS

## The exclusion clause — verified against the lifecycle tables

The current file (R16a, "What 'the surface' bounds") reads:

> "It excludes durable artifacts that have finished their own lifecycle and
> assert the old routing. Each type's format reference defines that for
> itself: a BRIEF or PRD at `Done`, a DESIGN at `Current` or `Superseded`,
> and any decision record. Those are the audit trail — they record what was
> true when they were written, and the repository corrects them by
> supersession rather than by editing history, which is exactly what R18 does
> for the two that matter."

This is the corrected, per-type formula the round-5 fix promised, and it
checks out against the three real lifecycle tables:

- `brief-format.md`'s lifecycle table has three states (Draft, Accepted,
  Done) and calls out Done explicitly: "Done | The downstream PRD has
  operationalized the brief. **Terminal state.**" Accepted is mid-chain
  ("Accepted -> Done" exists). So "a BRIEF at `Done`" names the one real
  terminal status and nothing else.
- `prd-format.md`'s lifecycle is Draft -> Accepted -> In Progress -> Done,
  with an explicit "No 'Superseded' state" callout instructing that a PRD
  whose requirements are replaced is still marked Done. Done is the only
  state nothing transitions out of. "a PRD at `Done`" is correct.
- `design-format.md`'s lifecycle is Proposed, Accepted, Planned, Current,
  Superseded. There is no Done state for DESIGN at all — the clause's own
  next sentence says so explicitly ("A DESIGN has no `Done` state at all"),
  which matches the table. Current is reached only via "Planned -> Current"
  and its only further transition is the exceptional "any -> Superseded"
  row; Superseded has no listed outgoing transition. So Current and
  Superseded are exactly the two settled DESIGN states, and "a DESIGN at
  `Current` or `Superseded`" matches the table precisely — this also
  explains why a Current design's routing claim is *not* just edited in
  place: `design-format.md`'s Superseded transition ("A successor DESIGN
  names this one as `superseded_by:`") is the format's own correction
  channel for a Current design that turns out wrong, which is exactly the
  channel R18 uses (a decision record, not an in-place rewrite).
- `Accepted` is checked and correctly excluded from terminal status for
  all three types by the clause's own next paragraph: "`Accepted` is NOT
  such a status for any type: an Accepted BRIEF still feeds a PRD and an
  Accepted PRD still feeds a DESIGN, so both remain live operational
  documents inside the surface." This is true in each table — Accepted is
  a mid-chain state in BRIEF, PRD, and DESIGN alike, none of which show a
  transition making Accepted a dead end.

No R18 contradiction: R18 itself says "a Current design" — describing the
document's status *before* this feature acts on it, present tense. The
exclusion clause lists both `Current` and `Superseded` together precisely
so that whichever state the document is actually in (Current now, possibly
Superseded once R18's decision record lands) it is excluded from the
routing-claim-fixing surface either way. There is no version of the text
that requires the document to already be Superseded for the exclusion to
apply, so R18 calling it "Current" does not conflict with anything R16a
says.

## The disposition text

The three dispositions are defined cleanly against R16a's own surface
definition:

> "`edited` when the claim is corrected in place, `superseded` when the
> document carrying it is corrected by a decision record under R18 rather
> than rewritten, and `delegated` when R17 governs it."

Each has a matching, independently-testable Acceptance Criterion:

- `edited` — "the named file at the named location contains that row's
  'after' text and no longer contains its 'before' text. A correct
  inventory committed alongside unedited files fails this criterion
  (R16a)."
- `superseded` — "names one of the two documents R18 covers, and those
  documents are NOT edited in place — their correction is the decision
  record. A row marked `superseded` that names any other document, or a
  superseded document whose text was rewritten, fails this criterion
  (R16a, R18)."
- `delegated` — "names a file inside an eval suite and is resolved under
  R17 (R16a, R17)."

This resolves the round-4 testability contradiction cleanly: R16a's
completion criterion no longer demands every inventory row's file be
edited. It demands the file be edited *only* for rows disposed `edited`,
and for `superseded` rows it demands the opposite — that the file is
*not* rewritten, matching R18's requirement that the two documents be
superseded on the record rather than edited. The triad is exhaustive
against R16a's own surface: anything inside the surface is either
directly editable (`edited`), one of the exact two R18-named documents
(`superseded`), or inside an eval suite (`delegated`); anything outside
the surface (a Done BRIEF/PRD, a settled DESIGN other than the one R18
names, a decision record) never enters the inventory at all, so it needs
no disposition.

## Per-requirement ambiguity scan

Read end to end (Problem Statement through Known Limitations). R1–R22,
the Acceptance Criteria, Out of Scope, and Decisions and Trade-offs are
all specific and testable; no vague qualifiers, no new uniform-formula
regressions elsewhere, and no requirement leans on a term the file itself
doesn't define. The "Terms used below" and "Anchor" glosses at the top of
the Requirements section still do the work of disambiguating "run" vs.
"session" and "anchor" before R1 uses them.

## Writing style

`CLAUDE.md` names `tier`, `journey`, and `underscore` as terms of art the
style rules must not fire on. None of the three appear anywhere in this
PRD, so there's nothing to except. A scan for the other flagged AI-writing
words (`robust`, `leverage`, `comprehensive`, `holistic`, `facilitate`,
`seamless`, `delve`) also returned nothing.

## Required changes

None.

## Observations

The fix this round is real, not cosmetic: the round-4/5 uniform "Done or
Accepted" formula would have been wrong on every count for DESIGN (no
Done state exists, and Accepted is supposed to stay inside the live
surface, not be excluded from it). The replacement formula is derived
from each format reference's actual lifecycle rather than asserted, and
the text shows its work by naming *why* Current is a settled state for
DESIGN (the format's own supersede-rather-than-edit correction channel),
which is what keeps this from reading as another guess.
