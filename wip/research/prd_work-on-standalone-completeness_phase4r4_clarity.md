# Clarity Review (round 4): PRD-work-on-standalone-completeness

## Verdict

FAIL

## Prior findings — closed or not

**1. "Run"/"session" bridging (round 3 optional item) — closed.** The
Requirements section now opens with a "Terms used below" clause: "A *run*
and a *session* are the same materialized thing seen at two layers... R19
uses 'session' for exactly that reason." That is exactly the bridge round 3
asked for. A reader hits it before R19 and never has to infer the
equivalence. Genuinely fixed.

**2. "The surface" boundary in R16a (round 3's required change) — NOT
closed, though it looks closed on first read.** The new clause names a
concrete-sounding boundary: the surface is "the live operational corpus" (a
closed, enumerable list — skill prose/frontmatter, reference files, routing
tables, eval suites, README.md, shared references) plus the two documents
R18 names, and it "excludes durable artifacts at a terminal status (a Done
or Accepted BRIEF, PRD, DESIGN or decision record)."

That parenthetical is where it breaks. Checked against this repository's own
lifecycle definitions:

- `skills/design/references/design-format.md` — DESIGN's states are
  Proposed, Accepted, Planned, Current, Superseded. There is no "Done"
  state for DESIGN at all, and "Accepted" is explicitly non-terminal (it is
  followed by Planned, then Current or Superseded).
- `skills/brief/references/brief-format.md` — BRIEF's states are Draft,
  Accepted, Done, with Done marked "Terminal state." Accepted is not.
- This repository already has an established, worked precedent for the
  exact phrase "terminal-status" applied to BRIEF, in
  `docs/prds/PRD-lifecycle-passing-state-validation.md`: "Orphan
  terminal-status (BRIEF Done with no downstream): passes" versus "Orphan
  non-terminal-status (BRIEF Accepted with no downstream...): fails." The
  corpus's own prior usage classifies an Accepted BRIEF as non-terminal —
  the opposite of what this PRD's parenthetical says.
- R18 itself, three sections away in the same document, describes the
  contradicted design as "the chosen option in a **Current** design" — not
  Accepted, not Done. Checking the actual file confirms it:
  `docs/designs/current/DESIGN-multi-pr-plan-decoupling.md` carries
  `status: Current`, and its paired
  `docs/prds/PRD-multi-pr-plan-decoupling.md` carries `status: Done`. So
  the two documents R16a's clause calls "the two accepted documents R18
  names" are, respectively, Done and Current — neither is literally
  "Accepted," and the DESIGN one isn't covered by either status word the
  exclusion parenthetical lists as terminal for DESIGN.

So an implementer who takes the parenthetical literally, status by status,
would: exclude Accepted BRIEFs and Accepted PRDs from the surface even
though this repository's own established terminal/non-terminal split calls
Accepted non-terminal for those types, and would find that *no* DESIGN
document is ever excluded under the stated rule (since DESIGN never
reaches "Done," and "Accepted" precedes Planned/Current for DESIGN) —
meaning every Current or Superseded DESIGN asserting the old routing, other
than the one R18 names, falls inside "the surface" and must be inventoried
and edited. A second implementer who instead imports this repository's own
prior "terminal-status" precedent would draw the opposite line. That is
exactly the two-implementers-diverge failure round 3 named, just relocated
from "no definition at all" to "a definition using status labels that
contradict this repository's own lifecycle tables and its own prior usage
of the same term." The boundary is not decidable from the repository
without further inference — checking the repository is what surfaces the
contradiction.

## New text — R19b block and the two new criteria

**R19b's new block** closes the testability-review gap cleanly. It gives a
concrete, checkable definition of "reuse" — "the cascade states call the
same named helper or discriminator that fix introduces, and a search for a
second implementation of the same root-versus-child test returns nothing"
— and an explicit escalation clause for the case the referenced fix hasn't
landed, or lands with a different mechanism, rather than leaving a tester
with no fallback. It also correctly disambiguates "the referent is the
merged change, not the filed issue," with a stated reason (the issue's text
proposes unconditional retention, which is the defect). This is clear,
internally consistent with R19/R19a, and does not reopen the R12 overlap
question — it explicitly defers that as a design question, unchanged from
round 3. One small, non-blocking observation: the acceptance criterion for
R19b ("The root-only mechanism used is the one established by the
separately landing fix, not a second implementation of the same idea") was
not updated to reference the new, more concrete "helper/discriminator, no
duplicate implementation" language — it still reads as the old, vaguer
SHALL. It's not ambiguous on its own (the requirement text a reader checks
against is unambiguous), just a missed opportunity to make the criterion
itself carry the sharper test.

**The two new acceptance criteria (R16a files-actually-edited, R8
classification-correctness)** are both clear and testable as written. The
R16a one is binary and grep-able: "the named file at the named location
contains that row's 'after' text and no longer contains its 'before'
text." The R8 one gives a concrete, independent re-derivation test for each
class ("names a gate that exists on the state it names and that fails when
driven to failure" / "names a field that the state's own evidence schema
marks required"). Neither introduces new ambiguity, and both close the gaps
the testability reviewer found in round 3.

## Per-requirement ambiguity scan

- Definitions (Anchor, Terms used below) — clear.
- R1–R15 — unchanged from round 3's clean pass; still clear.
- R16 — clear as a two-part split.
- **R16a — the eval/R17 boundary is still closed. The surface boundary is
  not; see above.**
- R16b — inherits R16a's gap: "every hit is either in the inventory or is
  non-routing" still depends on a surface definition that doesn't resolve
  cleanly for BRIEF/PRD/DESIGN documents at non-obvious statuses.
- R17–R22 — unchanged; clear.
- R19/R19a/R19b — clear; see above.

## Required changes

1. **Fix the "terminal status" enumeration in R16a's boundary clause.** It
   currently reads "(a Done or Accepted BRIEF, PRD, DESIGN or decision
   record)" as if one status pair were terminal across all four types. It
   isn't: DESIGN has no Done state and terminates at Current or Superseded;
   this repository's own prior usage (`PRD-lifecycle-passing-state-validation.md`)
   already classifies an Accepted BRIEF as non-terminal, not terminal. Either
   (a) state each type's actual terminal status explicitly — e.g. "a Done
   BRIEF or PRD, a Current or Superseded DESIGN, or a decision record (always
   terminal at Accepted, its only status)" — or (b) drop status-gating
   entirely if the real intent is "every BRIEF/PRD/DESIGN/decision record
   except the two R18 names," since none of those document types appear in
   the "live operational corpus" enumeration to begin with. Either fix
   removes the need for a reader to reconcile the clause against the format
   specs themselves.

## Observations

Writing style is clean: no `rules.yaml` banned words fire anywhere in the
document (checked the full word list), and `tier`/`journey`/`underscore`
don't appear at all, so the CLAUDE.md carve-out is moot rather than tested.
Em dash density is 37 over ~4,730 words, about 7.8 per thousand — under the
10-per-thousand threshold. Problem Statement stands alone without the
upstream BRIEF. Section order matches the format spec's canonical order.
No private-repo references, and the only issue number present
(`source_issue: 361`) is this repo's own public issue. Citation vs.
restatement is unchanged from round 3 and still fine.
