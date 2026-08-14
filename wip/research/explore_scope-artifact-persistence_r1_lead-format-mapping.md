# Lead: What would a total section mapping at PRD-to-DESIGN and DESIGN-to-PLAN actually require of the format contracts?

## Findings

### 1. What the per-type required-section contracts enforce today

`FormatSpec.required_sections` is a `Vec<String>` of H2 heading names
(`crates/shirabe-validate/src/formats.rs:18`). Its doc comment states the
contract explicitly: element **order is significant**, because two checks
consume the same list for two different purposes and reordering entries
silently changes what FC15 enforces (`formats.rs:13-17`).

Exactly one function reads the list:

```rust
// crates/shirabe-validate/src/checks.rs:181
fn required_sections_for(doc: &Doc, spec: &FormatSpec) -> Vec<String> {
    if let Some(map) = &spec.execution_mode_required_sections {
        if let Some(mode_field) = doc.fields.get("execution_mode") {
            if let Some(per_mode) = map.get(&mode_field.value) {
                return per_mode.clone();
            }
        }
    }
    spec.required_sections.clone()
}
```

Its two consumers:

- **FC04 (presence)** — `checks.rs:194-208`. For each name in the resolved
  list, if no `doc.sections` entry has that exact `name`, emit an error at
  line 1. It is a pure presence test; nothing checks that the section has
  content, and nothing checks for sections the format does *not* list.
- **FC15 (canonical order)** — `checks.rs:226-286`. Builds the required
  sections *present in the doc* in document order, builds the same set in
  the format's declared order, and compares. Sections the format does not
  require "may appear anywhere between them" (`checks.rs:213-216`), and a
  missing required section is FC04's problem, not FC15's.

Severity matters for the churn question. FC04 is **error-level**: it is
absent from `is_intrinsic_notice` (`validate.rs:83-98`) and falls through
`posture_class` to `AlwaysEnforced` (`validate.rs:110-115`), so it is an
error under both Draft and Ready posture. FC15 is **notice-level** — it *is*
in the intrinsic-notice set (`validate.rs:95`), with a documented one-line
promotion seam (remove the arm) once a corpus-cleanup PR lands
(`checks.rs:220-225`).

Section names are parsed by `scan_body` with a bare
`line.strip_prefix("## ")` (`crates/shirabe-validate/src/frontmatter.rs:341`),
so only H2 counts, `###` never matches, and the captured name is not
trimmed — `## Goals ` with a trailing space would not satisfy FC04.

`execution_mode_required_sections` (`formats.rs:37`, built by
`plan_execution_mode_sections()` at `formats.rs:56-81`) is populated on the
Plan profile alone: `single-pr` gets `Issue Outlines` where the multi-PR
modes get `Implementation Issues` + `Dependency Graph`; `coordinated`
deliberately clones `multi-pr`'s list. Every other profile passes `None`.

### 2. Is there any notion of optional sections in the validator?

**No. None at all.** There is no `optional_sections` field on `FormatSpec`,
no allowed-set check, and no per-doc suppression or waiver mechanism
anywhere in `crates/shirabe-validate/src/`. `annotation.rs` is only GHA
output formatting; there is no inline `<!-- shirabe:ignore -->` equivalent.

Two consequences worth stating plainly:

- **Extra sections are entirely unconstrained** for `design/v1`, `prd/v1`,
  `plan/v1` and `brief/v1`. A DESIGN can carry `## Goals`, `## Requirements`
  and `## Appendix: Absorbed PRD` today and no check fires. The only
  negative section lists in the codebase are R7 and R8, hard-coded
  two-element and one-element constants for public VISION and STRATEGY docs
  (`checks.rs:31-36`, checks at `checks.rs:878-930`). Neither touches
  design/prd/plan.
- The *prose* contracts already carry a three-way distinction the validator
  does not model. `skills/brief/references/brief-format.md:165-176` has a
  Section Matrix with `Required` / `Draft only` / `Optional` values;
  `skills/plan/references/plan-format.md:94-100` names `References` as
  optional; `skills/design/references/design-format.md:130-145` has a whole
  "Context-Aware Sections" table (Market Context, Required Tactical Designs,
  Upstream Design Reference) and says outright: *"The validator does not
  enforce these (they are advisory), but the Phase 6 structural-format
  reviewer flags missing context-aware sections."* So "optional section"
  exists as a documented, human/agent-reviewed concept and has zero
  machine representation.

### 3. Does the `execution_mode` precedent give a mechanism for a variant list?

It gives one, and it is nearly free — but it is keyed too narrowly as
written. Three properties of `required_sections_for` decide this:

1. **The frontmatter key is hard-coded.** `doc.fields.get("execution_mode")`
   at `checks.rs:183` is a string literal. A variant list keyed off a
   different field (say `absorbed:` or `consolidated:`) needs either a new
   `FormatSpec` field naming the key, or a second lookup, or the reuse of
   `execution_mode` itself for a meaning it does not have on DESIGN/PRD.
2. **It fails open, in the good direction.** If the format declares no map,
   or the doc has no such field, or the value is unmapped, the function
   falls back to `spec.required_sections`. That means a conditional list
   keyed off a *new* frontmatter field is automatically inert for every
   existing doc — none of them carry the field, so all resolve to today's
   flat list. This is the only mechanism in the file with that property.
3. **It is shared by FC04 and FC15.** A variant list defines both presence
   and canonical order for docs that select it, with no extra work.

What it does *not* give: any way for one doc to require a *superset* of the
base list without restating the whole thing (the map value replaces, it does
not extend), and any notion of "this section is required only if present
elsewhere". Both are small additions on top, not things the precedent
already handles.

The precedent is also modest in size: the whole mechanism is the `Option<HashMap>`
field, the 25-line builder, and the 9-line lookup. Generalizing the key from
a literal to a `FormatSpec`-declared field name is a handful of lines.

### 4. The smallest format change that gives each hop a home — options and costs

Baseline for costs, measured in this worktree:

| | `docs/` | repo-wide (incl. fixtures) |
|---|---|---|
| `PRD-*.md` | 42 (`docs/prds`) | 49 |
| `DESIGN-*.md` | 48 (all under `docs/designs/current`) | 80 |
| `PLAN-*.md` | 1 (`docs/plans/PLAN-work-on-friction-fixes.md`) | 18 |
| `BRIEF-*.md` | 35 | — |

How many already have a home for the absorbed content:

- `grep -rlE '^## (Goals|User Stories|Requirements|Acceptance Criteria|Out of Scope)$' docs/designs --include=DESIGN-*.md` → **zero of 48**.
- `grep -rlE '^## (Decision Drivers|Considered Options|Decision Outcome|Solution Architecture|Security Considerations|Consequences)$' docs/plans --include=PLAN-*.md` → **zero of 1**.
- By contrast all 48 DESIGN docs carry their own `## Security Considerations`
  and `## Consequences` (48/48 each), so the corpus is uniformly conformant
  to the *current* contract — the drift is not pre-existing.

**Option A — add the absorbed sections to `required_sections`.**

Five new required sections on `design/v1`, six on `plan/v1`.

- Validator cost: trivial. Two literal-list edits in `formats.rs`. No new
  code path; FC04 and FC15 pick them up for free.
- Corpus cost: catastrophic and immediate. Error-level FC04 on **48/48**
  DESIGN docs and **1/1** PLAN doc in `docs/`, plus 32 non-`docs/`
  DESIGN files and 17 non-`docs/` PLAN files. Every one needs a
  hand-written section, and a DESIGN that never had a PRD has nothing
  honest to write in `## User Stories`.
- Test cost: the golden corpus asserts exact stdout. 14 synthetic + 1 real
  DESIGN fixture (`crates/shirabe/tests/fixtures/golden/expected/synthetic/`,
  `.../expected/real/`) and 5 synthetic + 1 real PLAN fixture would all shift
  output. The absorption parity corpus is worse: `sections-clean`'s expected
  external rule set is *empty*
  (`crates/shirabe/tests/fixtures/absorption-golden/expected/sections-clean/external_rules`),
  so a newly-required section makes the engine fire FC04 where the external
  check fires nothing, breaking parity until the fixture doc is updated.
- Doctrinal cost: this option contradicts the format references head-on.
  `design-format.md:162-171` — *"A DESIGN does NOT contain: Requirements
  articulation — belongs in the upstream PRD."* `plan-format.md:201-213` —
  *"A PLAN does NOT contain: Technical architecture — belongs in the
  upstream DESIGN. Requirements articulation — belongs in the upstream PRD."*
  Making those sections mandatory inverts a stated content boundary for
  every doc, including the ones that never ran through `/scope`.

**Option B — add them as *optional* sections.**

Requires inventing the concept: an `optional_sections` field on
`FormatSpec` plus, if it is to mean anything, a check that consumes it.

- Validator cost: a new field, and a decision about what it enforces.
  Nothing today rejects an unlisted section, so `optional_sections` is
  documentation-only unless it is paired with either (a) a closed-set check
  ("no section outside required ∪ optional"), which would newly break docs
  carrying any bespoke heading, or (b) an order rule extending FC15 to
  optional sections, which is the only enforcement that costs nothing on a
  corpus that has none of them yet.
- Corpus cost: **zero**. No existing doc gains an error.
- Test cost: near zero; new tests only.
- But: it does not by itself satisfy `/scope` Stage 1 as written, which
  demands the downstream's *REQUIRED* sections provide the home
  (`skills/scope/references/phases/phase-2-chain-orchestration.md:419-422`).
  Adopting this option means rewording that rule to accept optional homes —
  which is a real change in meaning, since an optional home is one the
  downstream author may simply not have written.

**Option C — an appendix convention with no validator change.**

Absorb PRD content into a DESIGN under a heading like `## Absorbed
Requirements (from PRD)` placed after `## Consequences`.

- Validator cost: **zero**. Extra H2 sections are already legal for
  design/prd/plan (finding 2), and FC15 explicitly permits non-required
  sections anywhere (`checks.rs:213-216`).
- Corpus cost: **zero**.
- Cost is entirely in the skill layer: Stage 1's absorbability rule and its
  mapping table must change, the format references' Content Boundaries
  sections must carve out the absorbed case, and the Stage 3 carry check
  needs targets to name. It also means the format contract makes no promise
  the content will be there — a reader of an arbitrary DESIGN cannot know
  whether requirements live in it or in a sibling PRD without looking.

**Option D — per-doc conditional sections keyed off frontmatter.**

Generalize the `execution_mode` precedent: a doc that declares e.g.
`absorbed: [prd]` selects a variant required-section list that includes the
absorbed sections; a doc without the field resolves to today's list.

- Validator cost: small and localized. Generalize the hard-coded
  `"execution_mode"` at `checks.rs:183` into a `FormatSpec`-declared key
  name (or add a second, parallel lookup), then populate variant maps for
  `design/v1` and `plan/v1`. Both FC04 and FC15 inherit the behavior with no
  further change, exactly as the Plan profile does today. FC01/FC02 also need
  to accept the new frontmatter field as legal-but-optional — worth
  confirming, since `check_fc01` reads `spec.required_fields`.
- Corpus cost: **zero**, by construction. Existing docs carry no such field,
  so `required_sections_for` falls through to the flat list. This is the only
  option that both makes the home *required* (satisfying Stage 1 unmodified
  in spirit) and breaks nothing.
- Test cost: new tests only; existing goldens unaffected because no fixture
  carries the new field.
- Cost is conceptual: the format contract becomes doc-dependent, so "what is
  a valid DESIGN" now has two answers. That is already true for PLAN
  (three answers, keyed on `execution_mode`), so it is a precedent extension
  rather than a new kind of thing — but on Plan the key describes *what the
  doc is for*, whereas here it would describe *how the doc came to be*,
  which is a different sort of fact to put in a format contract.

**Combination worth noting.** Options B and D compose: declare the absorbed
sections optional at the format level for readers and reviewers, and use the
frontmatter-keyed variant to make them *required* on precisely the docs that
claim an absorb. That is also the only shape under which the Stage 3 carry
check has something to verify against.

### 5. Does FC15 constrain where an absorbed section can go?

Only if the section is in the required list.

- If absorbed sections are **not required** (Options B and C), FC15 is
  indifferent — non-required sections may sit anywhere between required ones
  (`checks.rs:213-216`), so an appendix at the end, or a `## Requirements`
  wedged between `## Decision Outcome` and `## Solution Architecture`, both
  pass.
- If they **are required** (Options A and D), FC15 pins their position: the
  order of entries in the `Vec` *is* the enforced document order. Placement
  becomes a design decision made once, in the list, for every doc. Today
  that is a notice, not an error (`validate.rs:95`), so a misordered doc
  would not fail CI — but the promotion seam is documented as a one-line
  change and the corpus-cleanup PR that promotes it is anticipated, so this
  should be treated as a hard constraint rather than an advisory one.

One practical note on placement: `## Status` is first in every profile and
FC03 reconciles the frontmatter status against the `## Status` body
(`checks.rs:162-175`), so nothing absorbed can precede it.

### 6. What actually validates, and when

CI does not validate the whole corpus. `.github/workflows/validate-docs.yml:88-99`
computes the changed-file set with `git diff` against the PR base and passes
those paths positionally, explicitly excluding `(evals|tests)/fixtures/`.
The comment states the contract: *"the CLI never discovers files itself."*

So Option A's 48-doc breakage would not fail CI on the day it lands. It
would fail on each doc the *next* time that doc is touched, one PR at a
time, for as long as the corpus lives. That is arguably worse than a single
loud failure — the cost is spread across unrelated future PRs — but it does
mean a staged migration is mechanically possible.

The lifecycle traversal (`shirabe validate --lifecycle .`) and the merge
gate emit L-codes, not FC-codes; `validate_file` is not called from
`merge_gate.rs` or `lifecycle.rs`. The full-corpus surfaces that *would*
break at once are the golden and absorption-parity test suites, which run in
`build-and-test.yml`.

## Implications

- The only zero-churn ways to give a downstream a home are the two that do
  not put the absorbed sections in the base `required_sections` list:
  the appendix convention (Option C, zero validator change) and the
  frontmatter-keyed variant (Option D, small validator change). Everything
  else pays in proportion to a 48-doc DESIGN corpus that currently has a
  100% conformance rate to the existing contract.
- Stage 1's rule as written — *the downstream type's required sections
  provide a home for every required section of the upstream type* — is a
  statement about the **type**, evaluated identically for every run. Options
  C and D both make the home a property of the **document**, which means
  Stage 1 has to be reworded regardless of which is chosen. That rewording
  is unavoidable and should be treated as in-scope work, not a side effect.
- The Content Boundaries sections of `design-format.md` and `plan-format.md`
  are the real obstacle, not the validator. They state that a DESIGN must not
  articulate requirements and a PLAN must not carry architecture. Those are
  prose rules with no machine enforcement, but they are also the reason the
  section lists look the way they do. Any total mapping has to either carve
  out the absorbed case explicitly or repeal the boundary.

## Surprises

- **Zero of 48 DESIGN docs carry any PRD section heading.** I expected some
  drift. There is none: the corpus is uniformly on-contract, which means
  every option that adds a required section breaks literally everything.
- **The validator has no concept of optional sections whatsoever**, yet four
  format references document optional sections at length, and
  `design-format.md:130-145` says so in as many words. The gap is deliberate
  and documented, not an oversight — but it means "add it as optional" is
  not a change to an existing mechanism, it is a new mechanism.
- **CI only validates changed files.** The 48-doc breakage of Option A is
  latent, not immediate, which makes it much easier to ship by accident and
  much harder to notice.
- **The absorption-parity golden `sections-clean` expects an empty rule set**,
  so it is a canary that fires on any required-section addition — a useful
  property, and one that means the fixture corpus must be updated in the
  same commit as any `formats.rs` list edit.
- The `execution_mode` lookup **fails open on an unknown value**: a Plan with
  `execution_mode: nonsense` silently gets the flat list rather than an
  error. Worth knowing before keying anything else off frontmatter.

## Open Questions

- Does the author intend the absorbed sections to be **required** on
  absorbing docs (which needs Option A or D), or merely **available**
  (Option B or C)? Stage 1's current wording implies required; the
  content-preserving-MOVE framing does not settle it.
- If a DESIGN absorbs a PRD and then a PLAN absorbs that DESIGN, the PLAN
  must carry both the DESIGN's sections and the PRD's. Under Option D that
  is a third variant list (`absorbed: [prd, design]`), not a composition of
  two. Is a combinatorial variant set acceptable, or does the design need an
  additive "extend the base list" semantic that `execution_mode` does not
  have today?
- The `/scope` framing says a fully-folded PLAN is ephemeral and deleted by
  the finalization cascade. If the terminal artifact is deleted, does the
  DESIGN-to-PLAN mapping need to be *total* at all, or only good enough that
  no content is lost between the DESIGN's deletion and the PLAN's? The
  format-contract cost differs sharply between those two readings.
- Do the Content Boundaries rules get carved out, repealed, or made
  conditional on the absorbing case? This is a human call about what a
  DESIGN *is*, and it is upstream of every option above.
- FC15 is a notice today with a documented promotion seam. Should the
  absorbed-section work assume promotion has happened (and therefore treat
  ordering as hard), or is FC15's advisory status a deliberate escape hatch?

## Summary

The validator enforces exactly one thing about sections — that each name in
a format's ordered `required_sections` list appears as an H2 (FC04,
error-level) in the declared relative order (FC15, notice-level) — and it has
no concept of optional, conditional, or appendix sections at all, despite
four format references documenting optional sections in prose. Adding the
absorbed sections to the base required lists is a two-line `formats.rs` edit
that would put error-level FC04 on 48 of 48 DESIGN docs and 1 of 1 PLAN doc
(zero currently carry any of the target headings), break roughly 20 golden
fixtures, and contradict the Content Boundaries rules in `design-format.md`
and `plan-format.md`. The two zero-churn alternatives are an appendix
convention (extra H2 sections are already unconstrained for design/prd/plan,
so this costs no validator change at all) and generalizing the Plan
profile's `execution_mode` variant-list precedent to a new frontmatter key —
which fails open for every doc lacking the field, giving a required home on
absorbing docs and breaking nothing else.
