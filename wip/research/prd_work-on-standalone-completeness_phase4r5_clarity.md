# Clarity Review (round 5): PRD-work-on-standalone-completeness

## Verdict

FAIL

## The corrected R16a exclusion — verified against the lifecycle tables

The author's claimed correction is not present in the document. R16a's
exclusion clause, at lines 235-237 of
`docs/prds/PRD-work-on-standalone-completeness.md`, reads verbatim:

> It excludes durable artifacts at a terminal status (a Done or Accepted
> BRIEF, PRD, DESIGN or decision record) that assert the old routing.

This is character-for-character the same uniform "Done or Accepted" formula
that round 4 failed. There is no per-type enumeration of terminal statuses,
and no note stating that Accepted is not a terminal status for any type. The
described fix — "a BRIEF or PRD at Done, a DESIGN at Current or Superseded...
Accepted is not such a status for any type" — was never written into the
file. Whatever the author applied it to, it did not land in this draft.

Checked against the actual lifecycle tables:

- `skills/brief/references/brief-format.md`: BRIEF states are Draft,
  Accepted, Done. Only Done is marked terminal ("Terminal state" in the
  Meaning column); Accepted is explicitly non-terminal ("Ready for the
  downstream PRD").
- `skills/prd/references/prd-format.md`: PRD states are Draft, Accepted, In
  Progress, Done. Only Done is terminal ("Feature shipped, all acceptance
  criteria met"); Accepted feeds In Progress.
- `skills/design/references/design-format.md`: DESIGN states are Proposed,
  Accepted, Planned, Current, Superseded. There is no Done state at all.
  Terminal statuses are Current and Superseded; Accepted transitions to
  Planned and is not terminal.

So "Accepted" is non-terminal for all three types, and "Done" is not a valid
status for DESIGN at all — the clause is wrong on exactly the two axes round
4 identified, unchanged.

## Per-requirement ambiguity scan

Everything else scanned clean. R18 still calls the contradicted design
"Current," consistent with the design lifecycle table, and nothing else in
the corrected-but-not-actually-corrected R16a text introduces new
contradictions beyond the one carried over. R1-R15, R17, R19-R22, the
Decisions and Trade-offs section, and the acceptance criteria read the same
as in the passing round-4 review and introduce no new ambiguity. No
term-of-art collisions ("tier," "journey," "underscore") appear in this
document.

## Required changes

Replace the R16a exclusion clause with a per-type enumeration drawn from each
format's own lifecycle table, e.g.: "durable artifacts at a terminal status —
a BRIEF or PRD at Done, a DESIGN at Current or Superseded, or [decision
record terminal status] — that assert the old routing," plus an explicit
statement that Accepted is not a terminal status for any of these types
(an Accepted BRIEF still feeds a PRD; an Accepted PRD still feeds a DESIGN;
both remain inside the surface this requirement covers). This is the fix the
author described in their response — it simply is not in the file under
review. Also confirm what terminal status a decision record actually carries
in this corpus (the format reference for decision records was not checked
against this clause since the clause never named one) before enumerating it.

## Observations

The gap between the described fix and the committed text suggests either an
edit that was made in a different branch/copy and not applied here, or a
draft that was prepared but not saved before this round was submitted for
review. Either way, the text a reviewer can actually read still contradicts
the repository's lifecycle tables and R18, for the same reason as round 4.
