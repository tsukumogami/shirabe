---
schema: design/v1
status: Accepted
upstream: docs/prds/PRD-shirabe-check-absorption.md
problem: |
  Deterministic document checks are implemented in more than one place -- the
  shirabe validate engine, external CI shell scripts, and rules restated in
  skill prose -- and the copies drift. Three families exist on both sides.
  The engine must become the single authority by absorbing the in-scope
  external checks and reconciling the overlaps to one behavior.
decision: |
  Add absorbed checks as first-class checks in the engine's existing check
  registry under stable codes; govern absorption with a written determinism
  rubric and a per-check disposition record; reconcile each overlapping
  family to one behavior with a bash-vs-Rust parity harness over a captured
  corpus; retire each external copy as its absorption lands; and point
  mechanized skill prose at the engine check by code.
rationale: |
  Reusing the existing checks.rs dispatch and the per-check registry keeps
  absorption additive; a captured-corpus parity harness makes each
  reconciliation auditable rather than a silent reimplementation; the rubric
  turns the absorb/defer/keep-out boundary into a stated rule; and retiring
  each external copy as it lands keeps duplication falling, never tripling.
---

# DESIGN: Deterministic check absorption

## Status

Accepted

## Context and Problem Statement

The validate engine (`crates/shirabe-validate`) already runs the project's
deterministic document checks as first-class Rust checks: `validate_file`
dispatches the FC-family (frontmatter fields, status match, required
sections, issues-table shape and consistency, and more) and the R-family
(visibility-gated content), each emitting a `ValidationError` carrying a
stable code. SR6 added a per-check selection registry (`is_known_check_code`)
so a consumer can run one named check.

The same kind of deterministic checks are also implemented outside the
engine, as external CI shell scripts (copied across repositories by a sync
mechanism) and as rules restated in the workflow skills' prose. In three
families -- frontmatter, required sections, and the issues table -- the
external scripts and the engine implement the same rule twice; in other
families the external scripts implement a check the engine does not have yet
(document location vs status, strikethrough state, and a large diagram
validator). The duplication drifts: the two implementations of an
overlapping family can disagree on an edge, and a skill's prose paraphrase of
a rule can fall out of step with what the engine enforces.

The technical problem is to make the engine the single definition site for
the deterministic checks in scope -- adding the absorbed checks into the
existing dispatch and registry, reconciling each overlapping family to one
authoritative behavior, proving each absorbed check faithful to the source it
replaces, and retiring the external copy as the absorption lands -- while
leaving out the checks a determinism rubric places out of scope (a
cost-deferred diagram validator; any judgment-dependent check). The hard part
is not translation but reconciliation: settling, per disagreeing edge, which
behavior is authoritative.

## Decision Drivers

- **Reconcile, do not port twice.** For the three overlapping families, the
  end state is one implementation, not two; each previously-divergent edge
  needs a defined verdict (PRD R3).
- **Provable parity.** Each absorbed check must be shown faithful to the
  source it replaces over a representative corpus, or its deliberate
  divergence named (PRD R4) -- a silent behavior change during absorption is
  the failure mode to prevent.
- **A stated rubric, not reflex.** The absorb / cost-defer / keep-out
  boundary is a written rule applied per check, with the disposition recorded
  (PRD R2, R7).
- **Additive over rewrite.** Absorbed checks join the existing `checks.rs`
  dispatch and the per-check registry; the existing checks' behavior and the
  annotation/exit contracts are preserved except where a reconciliation
  deliberately settles an overlap (PRD R9).
- **Individually invocable.** Each absorbed check is selectable through the
  per-check surface SR6 shipped, under a stable code in the existing
  code-family style (PRD R1, R8).
- **Duplication falls, never triples.** Each external copy is retired as the
  engine absorbs it; no check is implemented in three places at any committed
  point (PRD R5).
- **Prose references the check.** Mechanized skill-prose rules point at the
  engine check by code instead of restating the rule (PRD R6).
- **Public visibility.** The artifact names only shirabe's own checks and
  describes the external sources generically; no private paths or names.

## Considered Options

The design makes five decisions. Each is presented with the chosen option and
the genuine alternatives weighed against it.

### Decision 1 -- The determinism rubric and the disposition record

**Chosen: an input-provenance rubric, a dependency-weight cost heuristic, and a
single disposition table.**

A candidate check is classified by what its verdict is a function of.
**Category A** is a pure function of the document's own bytes. **Category B** is
a pure function of the document plus external state an orchestrator injects --
the way the engine's existing git-backed upstream check (R6) and its
GitHub-state check (FC09) already work: the CLI does not fetch, the caller
passes the state in. A and B absorb. **Category C** is deterministic but too
heavy to run inline; **category D** needs human or model judgment. C
cost-defers, D keeps out. Provenance is the objective first cut and puts the
A/B line -- where a classifier actually hesitates -- first.

The cost line for category C is **dependency weight**, not a line count: a
check is too heavy when absorbing it would drag a new grammar or parser into
the offline binary (the large diagram validator, which needs a full diagram
parser, is the anchor). Line count and runtime are corroborating signals, not
the rule.

The disposition is recorded as **one table** -- `Check | Family | Category |
Disposition | Engine code | Rationale`, one row per candidate -- so the record
is complete at a glance (every candidate has a row) and lives in the durable
design rather than a side file. The first-pass classification absorbs every
candidate family except the diagram validator (cost-deferred); there are no
judgment-only keep-outs among the current candidates. The GitHub-issue-status
check is category B and absorbs by extending FC09's existing injected-state
pattern.

**Alternatives rejected:**

- **Determinism-first question order.** Asking "is it deterministic?" before
  "what is it a function of?" defers the A/B distinction -- the one a
  classifier trips on -- to last. Provenance is the objective test and belongs
  first.
- **A hard line-count threshold for category C.** Brittle and gameable;
  misclassifies a small-but-parser-heavy check as cheap and a large-but-pure
  check as expensive. Dependency weight names the real cost.
- **Per-check prose subsections instead of a table.** No at-a-glance
  completeness check against the candidate set, so a candidate can be silently
  dropped -- the table makes the recorded-disposition requirement mechanically
  verifiable.

### Decision 2 -- Reconciling the three overlapping families

**Chosen: union by default, adjudicate by exception, discover edges by
corpus diff.**

When the engine's FC check and the external check disagree on an edge, the
**default is the stricter (union) behavior** -- the absorbed check enforces
what either side enforced. The default must fail toward strictness because the
failure mode of a consolidation is *silently weakening* a check: union is the
only default under which no edge gets looser without a deliberate, written
act. Union handles the trivial majority automatically. The edges union cannot
auto-decide -- where the two rules are incomparable, or where taking the
stricter rule would widen a check's scope to artifact types it never covered
-- are **adjudicated individually, each with a recorded verdict**. The edges
themselves are found by the parity harness (Decision 4): running both sides
over a captured corpus and diffing the fired-rule sets.

The reconciliation is grounded in the verified gaps. The frontmatter family
(FC01/FC02/FC03) is at near-parity. The required-sections family has one real
gap: **FC04 checks section presence but not order**, while the external check
enforces order -- so order is absorbed as new behavior (Decision 3 makes it a
new code, since it is genuinely new, not an FC04 tweak). The issues-table
family has three gaps, all strict supersets the engine absorbs by extending
its row-shape validation: the dependency-link **format** (`[#N](url)`), the
**tier-value enum**, and the **child-design reference link**. The external
diagram and strikethrough checks are already subsumed by the engine's FC07
(table-vs-diagram reconciliation) and FC08 (strikethrough consistency), so
those sub-families are already consolidated and out of this reconciliation.

After reconciliation, the external copy of each family is removed, the engine
check is the single definition, and every previously-divergent edge has a
defined verdict.

**Alternatives rejected:**

- **Engine-wins by default.** Guarantees the named failure mode on the four
  confirmed gaps -- section order, dependency-link format, tier enum, and
  child link would all silently vanish. Survives only as one possible
  *adjudicated* outcome for a specific edge, never as the default.
- **Bash-wins by default.** Inverts the consolidation: the engine would chase
  the external scripts' quirks, and it cannot express scope (the external
  checks are single-format; the engine checks are cross-format).
- **Pure mechanical union with no adjudication.** Adopted as the default bias
  but not the whole policy -- union has no answer for incomparable edges and
  would silently auto-decide a scope-widening edge.
- **Adjudicate every edge.** Adopted as the exception mechanism but not the
  policy for all edges -- unbounded ceremony on the trivial majority gets
  abandoned under deadline, which reintroduces silent weakening.

### Decision 3 -- Absorbed-check architecture

**Chosen: additive `check_*` functions in the existing dispatch, the FC number
sequence extended (with a reconcile-vs-new rule), and a lifecycle-style entry
for the non-per-file checks.**

A new absorbed check is the same four-edit shape every existing FC check uses:
a `check_*` function in `checks.rs`, one `errs.extend(...)` line in
`validate_file`'s dispatch (format-gated where appropriate), its code added to
`is_known_check_code` (so `--check` can select it, per PRD R8), and -- only if
the check is advisory -- its code added to `is_notice`. Most absorbed checks
need no `FormatSpec` change; one is added only when a rule is parameterized
per format, following the existing optional-field precedent so
non-participating formats are unaffected.

Codes **extend the existing FC number sequence** rather than introducing a
per-source family prefix, keeping one coherent namespace consumers reference
the same way. The reconcile-vs-new rule: a rule that is genuinely the same
concern as an existing check is folded into it (a reconciliation); a rule that
is new behavior takes the next free code. Section *order* is new (FC04 is
presence-only), so it is a new code, not an FC04 extension; the issues-table
gaps are the same concern as FC05's row shape, so they extend FC05.

Two candidates are **not per-file checks**: a corpus-wide strikethrough rule
(spanning all docs at once) and a document-location-versus-status rule (needs
the path, not just the parsed document). These do not fit a single-document
`validate_file` call; they take a separate traversal entry modeled on the
existing `--lifecycle` traversal, and -- like the L-family lifecycle codes --
stay out of the per-file `--check` registry.

**Alternatives rejected:**

- **A per-source / per-domain family prefix.** Fragments the flat code
  namespace consumers reference, forces a second taxonomy onto the `--check`
  surface, and buys no grouping the FC sequence does not already provide.
- **Reconcile everything into existing FC checks.** Overloads FC04 with
  ordering semantics it does not have and erases the tightened-vs-new
  distinction the registry and the audit trail depend on; kept only narrowly
  for genuine same-concern rules.
- **One mega-check function for all absorbed rules.** Breaks per-code `--check`
  selectability (R8) and per-code notice/error classification, and obscures
  which code came from which rule.

### Decision 4 -- The parity harness and external retirement

**Chosen: a captured-corpus rule-set-diff harness modeled on the existing
`transition_parity.rs`, a data-driven divergence manifest, and
delete-and-rewire retirement gated by the harness.**

The engine already solved this exact problem once: `transition_parity.rs`
compares engine output against a bash-script oracle over a frozen corpus,
carries a documented-divergence exemption, and acts as the cutover gate before
the scripts are deleted. The absorption harness is a third instance of that
shape. For each document in a captured corpus (clean plus each known
violation), both the external check's verdict and the engine check's verdict
are recorded and compared **at the fired-rule-set granularity** -- each side
normalized to the set of rules it fired, and the sets diffed. Pass/fail-only
comparison would hide the four known same-verdict-different-rule gaps;
byte-level comparison cannot survive the two sides' different code
vocabularies and message formats.

A **deliberate divergence** -- an edge where Decision 2's adjudication chose a
behavior that differs from the external source -- is recorded in a data-driven
manifest (a `divergences` table keyed to the reconciliation verdicts) that the
harness consults, so the parity test asserts the chosen behavior instead of
failing blindly, and the manifest cannot drift from the design's verdict
table. The corpus and manifest live beside the existing golden corpora
(`crates/shirabe/tests/fixtures/absorption-golden/`, driver
`absorption_parity.rs`).

Retirement is **one change per check**: the engine extension, the deletion of
the external copy, and the CI rewire to the engine check land together, gated
by the harness. This enforces the invariant that no check is implemented in
three places at any committed point (PRD R5/AC5); a public CI existence check
guards it.

**Alternatives rejected:**

- **Pass/fail-only comparison.** Cannot detect same-verdict-different-rule
  edges -- exactly the four known gaps where both sides reject a document but
  the engine fires fewer rules -- so it would report a clean diff over a real
  gap.
- **Byte-for-byte annotation comparison** (the Go-rewrite parity shape).
  Appropriate when both sides are the same tool meant to be identical; here
  the two sides use different vocabularies by design, so byte comparison fails
  on benign formatting and never names the diverging rule.
- **A hardcoded divergence exemption list.** Fine for a couple of incidental
  quirks, but a set of adjudicated reconciliation verdicts must stay in
  lockstep with Decision 2's table -- a data manifest tied to the verdict rows
  keeps the divergence list auditable and exhaustive.
- **Retire external checks in a separate later change.** Creates a committed
  window with the rule in three places, violating the invariant, and decouples
  the proof from the absorption.

### Decision 5 -- Prose mechanization

**Chosen: reference, do not restate -- split by the prose's role.**

A mechanized rule's prose stops enumerating the rule's substance and instead
carries a one-line human summary plus the check code. The split is by role:
**runtime prose** (a phase step that should actually enforce the rule) invokes
`shirabe validate --check <CODE>` and branches on the result; **reference
prose** (a format document describing the rule) cites the code as the
authority and defers the enumerable detail to the spec the check reads. The
format docs already half-implement this -- a "Validation Rules" block naming
the FC codes sits next to a duplicate prose enumeration of the same fields and
sections; that duplication is exactly what is removed.

The first candidates split into two waves. **Citation swaps**, where the check
already exists: frontmatter fields cite FC01, valid statuses FC02, status
match FC03, section presence FC04. **New absorptions**: section order (a new
code, since FC04 is presence-only) and the topic-slug regex (a new boolean
check; the existing slug-prefix recommender is not a gate). The Phase-0
source-status gate references the engine's chain-status lifecycle mode
(`--lifecycle-chain`) rather than restating its per-status stop table. The
`wip/` path-hygiene rule **stays prose** -- it turns on a human judgment
(distinguishing a path-shaped reference from rule-stating prose), so the rubric
places it out of scope, and it keeps its reviewer-grep backing.

The drift invariant: after mechanization there is exactly one enumerated
definition of a rule, in the check; the prose carries no second copy, so there
is nothing left to drift.

**Alternatives rejected:**

- **Delete the prose, replace with "run `--check <CODE>`".** Strips the
  human-readable contract from the reference docs and conflates a runnable step
  with a format description -- a format doc is not a runnable step.
- **Code-only in the format doc** (name the code, no summary). The same
  readability loss in the reference layer, with no extra safety over keeping a
  one-line summary beside the code.

## Decision Outcome

The five decisions compose into one additive, incremental consolidation. A
written input-provenance rubric (D1) classifies every external and prose check
into a single disposition table; the in-scope checks are absorbed as
additive `check_*` functions on the existing dispatch, under codes that extend
the FC sequence, with corpus-wide and path-context checks routed to a
lifecycle-style traversal entry (D3). Where an absorbed check overlaps an
existing one, the two are reconciled to the stricter behavior by default and
adjudicated by exception (D2), with every edge discovered and every verdict
proven by a captured-corpus rule-set-diff harness that also gates the deletion
of the external copy (D4). Deterministic rules restated in skill prose are
mechanized and the prose is rewritten to reference the check by code (D5).

The result moves each check to a single definition site without ever putting
it in three places, and makes every behavior change during the move
deliberate and recorded -- the diagram validator deferred on cost, the
judgment rule kept as prose, and each absorbed rule proven against the source
it replaces.

## Solution Architecture

### Components

1. **The disposition table (in this design).** The `Check | Family | Category
   | Disposition | Engine code | Rationale` record for every candidate. It is
   the authoritative scope list the plan decomposes against.

2. **Absorbed checks (`crates/shirabe-validate/src/checks.rs`).** New
   `check_*` functions wired into `validate_file`, and extensions to existing
   functions where a reconciliation tightens an existing check (FC05 row shape
   gains dependency-link format, tier enum, and child-link; FC04's family
   gains a new section-order code; FC09 gains the github-status edge). Each new
   per-file code is registered in `is_known_check_code`.

3. **A traversal entry for non-per-file checks
   (`crates/shirabe-validate/src/lifecycle.rs` or a sibling).** The corpus-wide
   strikethrough rule and the document-location-versus-status rule run through
   a traversal modeled on the existing `--lifecycle` modes, with their own
   codes (kept out of the per-file `--check` registry, like the L-family).

4. **The parity harness (`crates/shirabe/tests/absorption_parity.rs` +
   `tests/fixtures/absorption-golden/`).** Per-document, it normalizes both the
   external check's verdict and the engine check's verdict to a fired-rule set
   and diffs them, consulting a data-driven `divergences` manifest for the
   adjudicated edges. It is the cutover gate: a check is not retired until its
   corpus diff is clean or every divergence is recorded.

5. **Mechanized prose (`skills/**`).** Runtime steps invoke `validate --check
   <CODE>`; reference docs cite the code and drop the duplicated enumeration.

### Data flow (per absorbed check)

```
classify (rubric, D1) --> disposition table row
   |
   v
implement check_* in engine (D3) --> new/extended FC code, registered
   |
   v
parity harness (D4): external verdict-set  vs  engine verdict-set
   |                         |
   |                    diff edges
   |                         v
   |                 adjudicate (D2): union default / recorded verdict
   |                         |
   v                         v
clean diff OR every edge recorded  --> retire: delete external copy + rewire CI (one change)
   |
   v
mechanize any prose that restated the rule --> reference --check <CODE> (D5)
```

The CLI never fetches external state; category-B checks consume state the
orchestrator injects, exactly as FC09 and R6 do today.

## Implementation Approach

The work is per-check and naturally incremental; each check is one
self-contained landing that leaves the suite green:

1. **Land the rubric and the disposition table.** Classify every candidate,
   record the table in this design. This is the scope artifact everything else
   decomposes against; no code yet.
2. **Stand up the parity harness.** Build `absorption_parity.rs` and the
   `absorption-golden/` corpus + `divergences` manifest, following the
   `transition_parity.rs` shape, with one already-absorbed check (a
   near-parity frontmatter rule) as the first case to prove the harness.
3. **Absorb the overlapping families, reconciled.** Extend FC05 (link format,
   tier enum, child link) and add the section-order code; for each, the parity
   diff drives the adjudication, the divergence manifest records any
   deliberate edge, and the external copy is deleted in the same change.
4. **Absorb the non-overlapping per-file checks.** The github-status edge
   (extending FC09) and any other category-A/B per-file check, each
   parity-gated and retired in one change.
5. **Add the traversal entry and its checks.** The corpus-wide strikethrough
   and the location-versus-status rule, through the lifecycle-style entry.
6. **Mechanize the prose.** Citation swaps first (the FC01-FC04 enumerations),
   then the new-check references (section order, slug regex), then the Phase-0
   gate's reference to the lifecycle mode.
7. **Record the diagram validator as a cost deferral** and leave it on the
   external mechanism.

Steps 3-6 are independent per check once the harness (step 2) exists, so they
can land in any order and in parallel; the diagram deferral (step 7) is a
record, not code.

## Security Considerations

Absorption is additive over surfaces the engine already trusts; it must not
introduce new ones. Four invariants:

1. **Reuse the single parse surface.** Absorbed per-file checks operate on the
   already-parsed `Doc` IR (sections, fields, body, the table model). No
   absorbed in-scope check re-parses raw document bytes or pulls a new
   parser/grammar. The diagram validator is cost-deferred for exactly this
   reason; its absorption would require a separate dependency-trust review.

2. **No new fetch site.** The CLI stays offline. The one category-B absorbed
   check (github issue status) extends FC09's existing injected-state path:
   PR/issue context comes from orchestrator-injected environment variables,
   owner/repo substrings pass the existing validation gate before any
   subprocess, and the subprocess timeout, the output ceiling, and the rule
   that a malformed payload never reaches a user-visible surface all carry over
   unchanged. No absorbed check performs its own git or network fetch.

3. **Messages route through the central sanitizer.** Every absorbed check emits
   a `ValidationError` and lets `annotation::format_error`/`format_notice`
   render it; checks must not pre-render the `::error`/`::notice`
   workflow-command syntax. Document-derived values interpolated into messages
   use the existing debug-quoting convention; the formatter's newline/carriage-
   return stripping is the backstop against annotation-command injection.

4. **Path checks reuse the contained path.** The location-versus-status and
   corpus-wide checks run through the lifecycle-style traversal, which already
   canonicalizes every path and rejects any that escapes the canonical root.
   These checks derive their verdict from the traversal's already-contained,
   canonicalized path; they must not re-resolve or join a document-supplied
   path string outside that root.

The parity harness asserts against committed baseline files, never a live
external-script run. The external check is executed only by the ahead-of-time
capture step, in a controlled environment over the authors' own corpus;
`cargo test` and CI read fixtures only and spawn no external shell. Retirement
is one atomic change per check (engine extension, external deletion, and CI
rewire together, harness-gated), so a rule is never in three places and never
in zero places at any committed point.

## Consequences

**Positive:**

- Each deterministic check in scope moves to a single definition site. A
  maintainer corrects a rule once and every consumer enforces the corrected
  behavior; a contributor gets one verdict instead of two that can disagree.
- Every behavior change during the move is deliberate and recorded: the
  union-by-default policy means no edge weakens silently, the parity harness
  proves each absorbed check against the source it replaces, and the
  divergence manifest names each adjudicated edge.
- The change is additive over the existing engine -- new `check_*` functions on
  the existing dispatch, codes extending the FC sequence, the parity harness a
  third instance of an established shape -- so the blast radius is small and
  the existing checks' parity is preserved.
- Duplication falls monotonically: each absorption deletes its external copy in
  the same change, so the external mechanism shrinks check by check and a rule
  is never implemented in three places.

**Negative / trade-offs:**

- The reconciliation work is genuinely per-edge: the union default handles the
  majority, but each incomparable or scope-widening edge needs a human
  adjudication and a recorded verdict. That is design-and-review effort that
  cannot be fully mechanized -- it is the cost of settling the behavior
  deliberately rather than inheriting a silent disagreement.
- Absorption proceeds check by check, so the external mechanism shrinks
  gradually and is fully gone only when the last in-scope check lands; the
  cost-deferred diagram validator keeps it alive beyond that until a later
  effort absorbs it.
- The divergence manifest and the reconciliation table must stay in lockstep;
  if a future change alters an adjudicated edge without updating both, the
  parity gate and the recorded rationale drift apart. The data-driven manifest
  keyed to the verdict rows is the mitigation, but it is a coupling to
  maintain.

**Mitigations:**

- The parity harness is the cutover gate: no external copy is deleted until its
  corpus diff is clean or every divergence is recorded, so the proof and the
  retirement are bound together.
- A public CI existence check guards the three-places invariant, so a check
  cannot be added to the engine while its external copy still ships.
- The disposition table is the single scope artifact; the plan decomposes
  against it, so a candidate cannot be silently skipped.
