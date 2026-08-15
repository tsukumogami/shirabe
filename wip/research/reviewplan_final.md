# Final Verification — Category Final

# NOT READY

## Method

Re-verified all four prior verdicts against the current documents (not against
the descriptions of the fixes), ran every grep command named in the task
literally against the current tree, checked every line number in the design's
eleven-row Decision E table against the actual files, and read the PLAN
document's own structure against `skills/plan/references/plan-format.md`'s
Required Sections contract.

## 1. Prior findings — three of four categories fully closed, one category's residue items were not applied

- **Category A (scope):** No findings to close. Still holds.
- **Category C (AC discriminability):** The one surviving finding —
  `lifecycle.rs:764`'s "human-approved for multi-pr" comment evading Issue 6's
  checks — is closed. The plan's Goal text and Files list now name
  `lifecycle.rs` lines 52, 61, 764 and `transition.rs` lines 263, 469, 1960,
  2011 (six re-key files total, matching the design table), and the AC's
  completeness grep is now `grep -cniE "(human[ -]approv|approval gate)"`,
  whose `[ -]` alternation and `approv` stem catch "human-approved" where the
  old literal-string grep did not. Ran it myself against all six files; it
  returns exactly the numbers the task specified (SKILL.md 1,
  plan-doc-structure.md 3, phase-7-creation.md 1, plan-format.md 0,
  lifecycle.rs 3, transition.rs 4).
- **Category D (sequencing):** The Issue 6 / Issue 8 file-contention finding
  is closed correctly, and by the more durable of the two options the review
  offered. Issue 6's AC now checks `git diff` on "the specific lines the
  design's table names" rather than whole-file byte-identity, and says so
  explicitly, naming `DESIGN-roadmap-plan-standardization.md` as the case that
  motivated the change. No dependency edge was added between 6 and 8, but none
  is needed under the rescoped AC — verified against Issue 8's own AC, which
  requires the amendment "appended as a clearly separated section," so it
  cannot land on line 577 regardless of run order.
- **Category B (design fidelity): NOT closed.** Both residue items the review
  flagged as "should be fixed before the design is finalized" are still
  present verbatim in the current design document:
  - `docs/designs/DESIGN-multi-pr-plan-decoupling.md:255` — Decision C's "What
    is lost" paragraph still reads "...the author drives the plan by path
    instead, the way `/execute` already drives single-pr and coordinated
    plans." This is the exact sentence the Consequences section (line ~627)
    quotes and refutes as false two sections later in the same document. A
    reader stopping at Decision C gets the false, mitigated-sounding version.
  - `docs/designs/DESIGN-multi-pr-plan-decoupling.md:440` — the Solution
    Architecture component table still says "one of Decision E's five prose
    sites" for `plan-doc-structure.md`, a stale count from before Decision E
    was rewritten to seven Rust-comment-inclusive sites (Context and Problem
    Statement, line 94, correctly says "seven comment occurrences"; this one
    table cell was never updated to match).

  Neither is inherited by a PLAN issue's AC, so neither would cause an
  implementer to do the wrong thing mechanically — but both are exactly the
  kind of stale, self-contradicting prose this design's own subject matter
  (auditability, a merged artifact answering "why") argues against leaving in
  place. Two one-line edits close both.

## 2. Issue 6 grep criteria — verified correct, plus one factual error in the surrounding prose

Ran both commands from the task against the current tree.

**File-scoped completeness grep** — exact match to the specified numbers:
```
crates/shirabe-validate/src/transition.rs:4
skills/plan/references/plan-format.md:0
skills/plan/SKILL.md:1
skills/plan/references/quality/plan-doc-structure.md:3
skills/plan/references/phases/phase-7-creation.md:1
crates/shirabe-validate/src/lifecycle.rs:3
```

**Tree-wide discovery grep** — `grep -rniE "multi-pr" skills/ crates/ docs/ | grep -iE "(human[ -]approv|approval gate)"` — currently (pre-implementation) hits all eleven-table sites that have "multi-pr" and the approval phrasing on the same line, which is expected since none of the re-key work has landed yet; the AC's claim that this reduces to "only the four leave sites and the amendment's quotation" is a post-implementation claim I cannot falsify today.

But one thing in this section IS checkable today, independent of implementation state, and it's wrong: both the design (line 359-361) and the plan (Issue 6, ~line 294-296) assert that the same-line requirement "silently drops `transition.rs:1960` and `:2011` and `lifecycle.rs:61` and `:764`, where the mode is named on a neighbouring line." I read all four sites directly:

- `transition.rs:1960` ("...execution fires it under human approval") — `multi-pr` is on line 1959. Genuinely missed. Correct.
- `transition.rs:2011` ("The human-approval + GitHub-issue-creation gate...") — `multi-pr` is on line 2010. Genuinely missed. Correct.
- `lifecycle.rs:61` ("...human approval gate never ran") — `multi-pr` is on line 60. Genuinely missed. Correct.
- `lifecycle.rs:764` — the line itself reads `/// (human-approved for multi-pr, auto-fired for single-pr), so the`. Both `multi-pr` and `human-approved` are on this one line. It is **not** missed — my literal run of the two-stage grep above returns this exact line. Only three of the four named sites are actually missed by the same-line requirement; `lifecycle.rs:764` is caught by it just fine.

This doesn't break AC4 or AC5 mechanically (both catch line 764 regardless, via the completeness grep and via the discovery grep's actual behavior), so it's not a Category C-style AC gap. But it's a factual error in the stated justification for why two checks are needed, repeated identically in both the design and the plan, and worth a one-word fix (drop "and `:764`" from both sentences, or correct the reasoning).

## 3. Design's eleven-row site table — accurate

Checked every line number in Decision E's table against the actual files:
`SKILL.md:60`, `plan-doc-structure.md:85,92`, `phase-7-creation.md:263`,
`lifecycle.rs:52,61,764`, `transition.rs:263,469,1960,2011`,
`DECISION-multi-pr-posture-detection-2026-06-06.md:43,56`,
`DESIGN-lifecycle-draft-ready-discipline.md:398`,
`DESIGN-shirabe-artifact-decision-contract.md:453`,
`DESIGN-roadmap-plan-standardization.md:577`, golden fixture `:73`. All eleven
check out against the current tree content. No line-number defects.

## 4. Cross-issue conflicts — none beyond the already-resolved Issue 6/8 case

Re-checked the full dependency graph (`1→2→3→4→8`, `5→6`, `5→7`) against every
issue's Files list and AC text for other same-file, unordered contention.
Issue 3 and Issue 6 both touch `lifecycle.rs` but at disjoint, named line
regions (Issue 3 appends the L09 function; Issue 6 edits pre-existing comment
lines), already checked clean by Category D. No other pair contends over an
unordered shared file.

## 5. Internal consistency of counts — accurate

"Eleven sites" = the eleven table rows, verified by counting. "Two of them
Rust source files carrying seven comment occurrences between them" =
`lifecycle.rs` (3 lines) + `transition.rs` (4 lines) = 7, verified against the
same table and against the actual grep counts in section 2 above. Consistent.

## 6. A gap none of the four categories were positioned to catch: the PLAN document itself is not in the required format

`skills/plan/references/plan-format.md` defines six Required Sections in
order, including **"4. Implementation Issues -- the atomic-issue table plus
issue outlines"** and **"5. Dependency Graph -- the Mermaid diagram showing
inter-issue dependencies and class assignments."** A committed example in the
same repo (`docs/plans/PLAN-work-on-friction-fixes.md`) shows the real shape:
a `## Issue Outlines` section, a *separate* `## Implementation Issues` section
carrying the two-row-per-issue link/summary table, and a `## Dependency Graph`
section carrying a fenced `mermaid` `graph TD` block with node ids, edges,
`classDef`s, class assignments, and a Legend.

`docs/plans/PLAN-multi-pr-plan-decoupling.md` has none of that. Its top-level
headings are exactly:
```
## Status
## Scope Summary
## Decomposition Strategy
## Issue Outlines
## Dependency Graph
## Implementation Sequence
```
There is no `## Implementation Issues` section or table anywhere in the
document (`grep -n "^## " ` confirms), and the `## Dependency Graph` section
(line 397) is completely empty — no fenced mermaid block, no nodes, no edges,
no classDefs, no Legend (`grep -n "mermaid\|graph TD\|-->"` returns nothing in
the whole file).

This is checkable today, needs no implementation to have landed, and would
fail `shirabe validate` outright (the validator's `mermaid.rs` explicitly
returns a finding when `## Dependency Graph` has no fenced mermaid block, and
`formats.rs` treats "Implementation Issues" as a required section name for
`plan/v1`). It would also leave an implementing agent with no anchor table to
navigate by and no dependency graph to sequence against — exactly the
artifact the four-category review assumes exists when it reasons about
"critical path" and "the graph." This is the actual blocker: everything the
four categories checked is checking content that currently has no compliant
container.

## What must change before this is READY

1. `docs/designs/DESIGN-multi-pr-plan-decoupling.md:255` — remove or replace
   the stale "the author drives the plan by path instead, the way `/execute`
   already drives single-pr and coordinated plans" clause in Decision C's
   "What is lost" paragraph; it contradicts the corrected Consequences entry
   two sections later.
2. `docs/designs/DESIGN-multi-pr-plan-decoupling.md:440` — change "one of
   Decision E's five prose sites" to "seven" (or drop the count).
3. `docs/designs/DESIGN-multi-pr-plan-decoupling.md:359-361` and
   `docs/plans/PLAN-multi-pr-plan-decoupling.md:294-296` — correct the
   discovery-grep justification: only `transition.rs:1960`, `:2011`, and
   `lifecycle.rs:61` are missed by the same-line requirement;
   `lifecycle.rs:764` is caught (both `multi-pr` and `human-approved` are on
   that line). Drop `:764` from the "silently drops" / "misses" list in both
   documents.
4. `docs/plans/PLAN-multi-pr-plan-decoupling.md` — add the missing
   `## Implementation Issues` section (the three-column
   Issue/Dependencies/Complexity table, two rows per issue, with local-anchor
   links to the eight outlines and a Complexity classification for each), and
   populate `## Dependency Graph` with the actual Mermaid `graph TD` block
   (nodes `I1`-`I8`, edges `I1-->I2-->I3-->I4-->I8`, `I5-->I6`, `I5-->I7`,
   `classDef`s, class assignments, and a Legend), matching the shape
   `docs/plans/PLAN-work-on-friction-fixes.md` already demonstrates for this
   repo's `plan/v1` format. This is the blocking item — without it the
   document does not conform to its own format contract and would fail
   `shirabe validate`.
