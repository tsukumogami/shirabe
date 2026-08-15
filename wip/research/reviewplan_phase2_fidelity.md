# Category B: PASS

## Re-verified: the grep-AC finding is now solid, including against the expanded 11-site table

Ran the actual verification commands rather than trusting either document.
`grep -n "human approval\|human-approval\|human-approved\|approval gate"` on
`lifecycle.rs`/`transition.rs` returns exactly the lines Decision E's new
table claims: lifecycle.rs:52,61,764 and transition.rs:263,469,1960,2011 (7
occurrences across those two files, matching "seven ... Rust doc comments"
read as an occurrence count — see note below on unit-mixing). I also ran
Issue 6's actual two-stage AC command
(`grep -rniE "multi-pr" skills/ crates/ docs/ | grep -iE "(human[ -]approv|approval gate)"`)
against the current tree: it returns hits at all six `re-key` sites (expected,
pre-fix), all four `leave` sites, and inside the DESIGN and PLAN documents
themselves where they quote the phrasing for illustration. Issue 6's Files
list (`skills/plan/SKILL.md`, `plan-format.md`, `plan-doc-structure.md`,
`phase-7-creation.md`, `lifecycle.rs`, `transition.rs`,
`DECISION-multi-pr-posture-detection-2026-06-06.md`) is exactly the six
`re-key` sites plus the one `amend` site — correct and complete against the
design's own table. Issue 6's Goal and ACs now also correctly encode: the
four `leave` sites and why, the four phrasing variants, and the
`DESIGN-roadmap-plan-standardization.md` line-577-is-`leave`-while-Issue-8-
amends-elsewhere-in-the-same-file distinction (verified against Issue 8's
actual Goal text — it amends Decision 6's split-rule default, a different
section, and never touches or claims to touch the approval-gate framing at
line 577). This is fully resolved; no finding here.

## New finding — the Solution Architecture component table was not updated in the same pass as Decision E, and now contradicts it

- category: B
- affected_issue_ids: [] (design-only; no PLAN issue currently relies on the stale wording)
- description: Decision E's site table (docs/designs/DESIGN-multi-pr-plan-decoupling.md:322-334) was rewritten to 11 rows with verified line numbers, but the Solution Architecture "Components and where they change" table three sections later still reflects the pre-fix counts:
  - Line 434, `plan-doc-structure.md` row: "...one of Decision E's **five** prose sites" — Decision E now names eleven sites total (six `re-key`, one `amend`, four `leave`), not five.
  - Line 437, `lifecycle.rs` row: describes the change only as "module-doc comment restating the gate as mode-keyed re-keyed" — Decision E's table lists three lifecycle.rs occurrences (52, 61, 764), and line 764 is not in the module doc (it's inline in `infer_posture_from`, confirmed by direct read of the file); the row undercounts and mischaracterizes the site.
  - Line 439, `transition.rs` row: "Comment-only: **two** sites restating the gate as mode-keyed" — Decision E's table lists **four** transition.rs occurrences (263, 469, 1960, 2011), confirmed by direct grep against the source.

  None of these three stale lines is quoted by or relied on by any PLAN issue — Issue 6 gets its file list and phrasing-variant list directly from Decision E's table, correctly, and Issue 1's AC references "Decision E's...sites" nowhere. So this doesn't break an issue's AC the way the original finding did. But it is exactly the "stale statement survives a revision" pattern the checklist exists to catch: three lines in the same document, three sections after the fix, still describe the old five-site/two-site accounting the fix explicitly says was wrong "in both directions."
- correction_hint: (empty — Category B correction requires the design fix to be completed, not issue content changed)

**Secondary, lower-confidence note on the Context section's count.** Line 94
now reads "prose in eleven places, seven of them Rust doc comments." Read as
site-count, this doesn't match the table (only 2 of 11 table rows are "Rust
comment" kind — lifecycle.rs and transition.rs); read as occurrence-count,
"eleven" doesn't match either (there are more than eleven individual line
occurrences once you count every row's `Line(s)` column entries, e.g.
plan-doc-structure.md has two, the decision record has two). The two numbers
in that sentence appear to mix site-count and occurrence-count without saying
so. This doesn't affect any downstream issue and I'd weight it well below the
component-table finding above, but flagging it since you asked whether the
Context section's count agrees with the table.

## Answering your question 1 — the `leave` verdict: right for two of the four sites, questionable for the DESIGN docs

The `leave` call is correct for the golden fixture (pinned test input — not
in dispute) and for the `DECISION-multi-pr-posture-detection-2026-06-06.md`
predicate history (a DECISION record is explicitly point-in-time in this
codebase's own convention — Decision E itself chooses to amend rather than
supersede that same record for exactly this reason).

I don't think the same reasoning transfers cleanly to the three `Current`
DESIGN docs, and I'd push back rather than confirm. Checked
`skills/design/references/design-format.md:213`: "Current | The PLAN has
shipped. **The DESIGN documents the current architecture.**" and line
229-232: "distinguishes designs that documented historical decisions from
designs that document the current architecture. A reader scanning
`docs/designs/current/` sees only currently-applicable designs." That is a
different contract than a DECISION record's. A DECISION file is explicitly an
audit-trail artifact — amended, never edited, by established convention in
this exact codebase. A `Current` DESIGN is not documented as an audit-trail
artifact; per its own format contract it is supposed to be presently
accurate. Once Issue 6 re-keys the gate, all three cited DESIGN statements
("Draft -> Active gate auto-fires for single-pr and is human-approved for
multi-pr") become false statements about the shipped system's actual
behavior, sitting in `docs/designs/current/`, with nothing pointing a reader
to the correction:

- `DESIGN-lifecycle-draft-ready-discipline.md:398` — no amendment anywhere in this plan touches this file at all.
- `DESIGN-shirabe-artifact-decision-contract.md:453` — same; untouched by any issue.
- `DESIGN-roadmap-plan-standardization.md:577` — Issue 8 does amend this file, but I checked its Goal text: it amends Decision 6's split-rule *default*, a different section entirely, and neither claims nor covers the approval-gate framing at line 577. The PLAN's own Issue 6 AC (line 300-304) is honest about this — it explicitly says line 577 stays a `leave` site "while Issue 8 separately appends an amendment elsewhere in the same file" — so the PLAN doesn't overclaim here even though the design's table annotation ("leave; amended separately by Decision 6's own amendment," line 333) could be misread as implying Issue 8 covers this statement. It doesn't.

So: two of the three DESIGN docs get no correction at all, and the third gets
a correction to an unrelated part of the same file. If a `Current` design is
supposed to reflect current architecture, this design should either (a) add
a lightweight amendment note at each of the three sites — the same treatment
the DECISION record gets — or (b) explicitly name this as an accepted
Consequence ("three Current designs retain a stale gate-predicate statement
post-merge, uncorrected") the way the design already names "two decision
records and one design need amending" for a related but different set of
edits. Right now it does neither; it asserts `leave` is costless when, for
two of the three files, it leaves live documentation wrong with no trail to
follow. This is a genuine disagreement with the `leave` verdict as currently
justified, not a rubber-stamp.

## Unrelated, still open from the prior round

Decision C's "What is lost" paragraph (lines 252-255) still contains the
sentence Consequences (lines 597-609) explicitly quotes and refutes as false
("the author drives the plan by path instead, the way `/execute` already
drives single-pr and coordinated plans" — `/execute` declines multi-pr
outright per `skills/execute/SKILL.md:40`). Re-verified still present at line
255; not addressed by this round's edits. Flagged previously, repeating since
it's still live.

## Verdict rationale

PASS stands: no PLAN issue currently encodes a contradiction inherited from
the design. The grep-AC defect that caused the prior FAIL is now completely
and correctly fixed, verified by actually running the commands against the
tree. Everything above this line is design-document-only residue — three
stale counts in the component table, a still-unresolved stale claim in
Decision C, and a `leave` justification I think is only partly right — none
of which is quoted, relied on, or contradicted by any issue's body or
acceptance criteria. Recommend fixing all of it before the design is
finalized, since the pattern (a fix landing in one section without the
downstream section being swept for the same stale count) has now recurred
twice in two review rounds on the same document.
