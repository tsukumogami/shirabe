# Discovery — upstream-link-legality

## Framing-shift answer

Cold start. No BRIEF, PRD, DESIGN, or PLAN exists for this topic. No
ROADMAP exists in this repo at all (`docs/roadmaps/` is absent), so no
upstream is available and none is recorded.

## Sources consulted

- Issue #272 — durable documents must not name ephemeral ones as upstream.
- Issue #253 — upstream link legality is unenforceable.
- `docs/briefs/BRIEF-chain-cardinality.md`, `docs/prds/PRD-chain-cardinality.md`,
  `docs/designs/current/DESIGN-chain-cardinality.md` — the artifacts behind PR #271.
- `crates/shirabe-validate/src/{upstream,formats,validate,checks}.rs` — the
  enforcement surface as it stands after #271.
- `skills/*/SKILL.md` `## Artifact Lifecycle` sections — the Durable/Working
  declarations, which today live only in skill prose.

## Grounded facts (verified, not inherited)

1. **Lifecycle class is not represented in code.** `grep -rn "Working"
   --include=*.rs crates/` returns nothing. Durable-vs-Working is declared in
   eight `SKILL.md` files and summarized in `CLAUDE.md`; the validator has no
   notion of it. Working: ROADMAP, PLAN. Durable: VISION, STRATEGY, BRIEF, PRD,
   DESIGN, COMP.

2. **Type legality is not represented in code either.** `FormatSpec` carries
   `required_fields`, `valid_statuses`, `required_sections`,
   `issues_table_columns`, `private`, and the per-`execution_mode` override.
   There is no field naming which upstream types are legal.

3. **The corpus, re-inventoried at `9f45603` (81 edges, not #253's 71):**

   | Edge | Count |
   |---|---:|
   | DESIGN → PRD | 38 |
   | PRD → BRIEF | 35 |
   | BRIEF → DESIGN | 4 |
   | BRIEF → PLAN | 2 |
   | BRIEF → BRIEF | 2 |

   Every irregular edge is a BRIEF upstream. **There are zero BRIEF → ROADMAP
   edges**, so the edge the formats say is a BRIEF's *only* legal upstream does
   not occur in the corpus even once.

4. **#253's premise about R6 is stale.** `check_upstream_resolves` runs for
   every format from the shared block in `validate.rs` (2b), with per-entry
   reporting and an explicit empty-field finding. Its "Adjacent, separate"
   section is already done.

5. **The private-upstream precedent is real and already implemented**, in
   `skills/scope/references/phases/phase-0-setup.md` (Upstream Validation,
   check 3): Public repo + private upstream → do not record, do not pass the
   flag to any child, tell the author, continue. Checks 1 and 2 (`wip/`,
   untracked) reject the run instead. So the skill layer already distinguishes
   "malformed input, reject" from "legitimate but unrecordable, omit and
   continue".

6. **The read-vs-record precedent is real**: `/strategy` reads a grounding PRD
   for context and does not record it as `upstream:`.

## Problem / outcome pair

**Problem.** `upstream:` is the only durable record of a document's lineage,
and nothing defines what makes one legal. Two independent failures follow —
one of type, one of lifetime — and neither is caught.

**Outcome.** An illegal upstream link fails at the moment it is written, and
the skills that record links stop producing the illegal kind, so a reader
following a durable document's chain lands on documents that still exist.

## Open framing question deferred downstream

Which mechanism replaces a durable→ephemeral link — navigate to the nearest
durable ancestor, or carry no upstream and absorb the context — and whether
that rule and the existing private-upstream rule are one rule or two. This is
a requirements-and-design question, not a framing one; the PRD's Decisions and
Trade-offs section is its closure surface.
