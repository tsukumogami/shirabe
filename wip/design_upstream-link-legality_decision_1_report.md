# Decision 1 — Where a type's lifetime class and legal-parent set are declared

## The question

R2 and R3 require every artifact type to declare two facts "in the same place
its required sections and valid statuses are declared": its lifetime class
(`Durable` or `Working`) and the set of types that may be named as its
upstream. R3 requires the set to be expressible as empty. R4 requires that no
Durable type declare a Working type as a parent, and that a maintainer who
writes such a declaration "finds out before it can reach the corpus."

The place required sections and valid statuses are declared is
`FormatSpec` in `crates/shirabe-validate/src/formats.rs`. The question is
whether these two facts go there as fields, somewhere else, or are derived
rather than declared — and, if declared, in what data shape.

## What the code actually is

Facts established by reading, not assumed:

- `FormatSpec` is constructed in exactly one place: the `formats()` literal
  at `crates/shirabe-validate/src/formats.rs:87-242`. Nothing outside that
  function builds one; every other site clones from `formats()` or
  `detect_format()`. Nothing destructures it, so adding a field breaks no
  pattern match.
- `formats()` returns a closed set of eight specs. The referent set for any
  cross-reference between formats is finite and enumerable inside the same
  function.
- `#[derive(Debug, Clone, PartialEq, Eq)]` on `FormatSpec` is already at its
  ceiling: `execution_mode_required_sections: Option<HashMap<...>>` rules out
  `Hash` and `Ord` on the struct today, so no new field can lower it.
- The struct already carries an empty-vec-means-none field:
  `issues_table_columns: vec![]`, documented as "Empty for formats without an
  issues table." R3's empty parent set has an established idiom in this very
  struct.
- Format identity travels as a `String` everywhere else in the crate:
  `validate_file`'s `match spec.name.as_str()`, `transition_spec(format_name)`,
  `ChainRole::from_format(&node.format)`, `finalize`'s `f.name == "Plan"`.
- The casing inconsistency is real and load-bearing.
  `FormatSpec::name` values are `"Comp"`, `"Design"`, `"PRD"`, `"VISION"`,
  `"Roadmap"`, `"Plan"`, `"Strategy"`, `"Brief"` — three casing conventions in
  eight rows. `validate.rs:221-223` warns explicitly: "Do not normalize the
  case here without updating formats()."
- The uppercase display form already exists twice, independently:
  `ChainRole::as_str()` (`lifecycle.rs:150-158`) returns `"BRIEF"`, `"PRD"`,
  `"DESIGN"`, `"PLAN"`, `"ROADMAP"`, and `check_orphan` calls
  `doc.format.to_uppercase()` for its message. Both exist because
  `FormatSpec::name` is not the form a message wants.
- `ChainRole` has five variants (Brief, Prd, Design, Plan, Roadmap). VISION,
  STRATEGY and COMP have no representation in it.
- There is no altitude ordering anywhere in the crate. `compute_passing_state`
  is a 25-cell `(role, posture)` table, not an ordering.
  `Chain::members` order is documented as presentational only: "member order
  is presentational only... nothing reads meaning out of a member's position."
- This codebase reaches for small purpose-built enums constantly: `TargetState`,
  `Posture`, `ChainRole`, `RootKind`, `PassingState`, `Entry`, `PostureClass`,
  `Severity`, `ReviewPosture`, `ExtraField`, `Rule`, `Precondition`. A new
  two-variant enum is house style, not a novelty.
- `check_upstream_resolves(doc)` takes only the `Doc` — it has no `FormatSpec`.
  A direction check needs the naming document's spec, and `validate_file`
  already holds it, so the new check's signature is `(doc, spec)` and the
  wiring is one line beside the existing `errs.extend(check_upstream_resolves(doc))`
  at `validate.rs:217`.

### An R21 hazard worth reporting up

`crates/shirabe/tests/fixtures/golden/corpus/real/PRD-roadmap-skill.md`
carries `upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md` — a PRD naming
a ROADMAP, which is both a direction violation and a lifetime violation under
R5. Its frozen expected output is a single line
(`::notice ...::schema field missing, skipping`, exit 0), because the doc has
no `schema:` field and `validate_file`'s schema gate short-circuits at
`validate.rs:185-187` before any FC or R check runs.

So R21 holds — **as long as the new checks run inside `validate_file`, after
the schema gate.** A check placed before that gate, or run from the
`--lifecycle` traversal instead, changes a frozen golden baseline and breaks
R21. This constrains where the check lives, not where the declaration lives, so
it does not decide D1; it should be recorded wherever the check's placement is
decided. No other golden-corpus fixture has an `upstream:` that becomes
illegal (`PLAN-...` names a DESIGN, `DESIGN-...` names a PRD, and the synthetic
R6 fixture's target basename matches no artifact prefix, so R9 leaves it
unchecked).

---

## Option A — two new fields on `FormatSpec`

### Strongest case

R2 and R3 name this location literally, and the reason behind the wording is
mechanical rather than stylistic: **a field makes the declaration mandatory.**
The `formats()` literal will not compile until a maintainer adding a ninth
format supplies both values. Every other option makes the declaration optional
in the sense that omitting it produces a silent default rather than a build
failure — which is precisely the failure mode R4's "finds out before it can
reach the corpus" is written against, one level up.

R4's enforcement is a plain unit test over `formats()`, with no I/O, no
fixtures, and no traversal:

```rust
#[test]
fn no_durable_format_declares_a_working_parent() {
    for spec in formats() {
        if spec.lifetime != Lifetime::Durable { continue; }
        for parent in &spec.legal_upstream {
            assert_ne!(lookup(*parent).lifetime, Lifetime::Working,
                "{} is Durable and declares Working parent {:?}", spec.name, parent);
        }
    }
}
```

It runs in `cargo test -p shirabe-validate` in milliseconds and fails the
moment a bad row is written. The acceptance criteria' "a test asserts that no
Durable type declares a Working type among its legal parents, and fails when
one is added" is satisfied exactly and only by something of this shape.

Both derives survive. `Vec<String>` already appears four times in the struct.
A fieldless enum deriving `Debug, Clone, Copy, PartialEq, Eq` satisfies
`FormatSpec`'s derive set with room to spare, and neither field touches the
`Hash`/`Ord` ceiling the `HashMap` field already set.

### Cost

`formats.rs` grows by roughly 50 lines: two type definitions with doc
comments, two field declarations with doc comments, and two lines per format
in the literal. **No other file changes for the declaration itself.** New types
are reachable inside the crate as `crate::formats::Lifetime` without touching
`lib.rs`; a `lib.rs` re-export is one line and only needed if the binary crate
names them.

The struct gains two fields that most of its readers ignore. `FormatSpec` is
already a grab-bag of per-format facts (`private`, `issues_table_columns`,
`execution_mode_required_sections` are each read by exactly one check), so
this is the established shape rather than a new dilution.

---

## Option B — a separate legality module keyed by format name

### Strongest case

This is not a strawman: **the codebase already does exactly this, once.**
`transition.rs` holds `transition_table()` — a per-format behavioral table,
keyed by `FormatSpec.name`, living in its own module, with `FormatSpec`
untouched. If the legality rule is a behavior rather than a structure, that is
its precedent, and it is a good one: the whole rule (both facts, both check
codes, the R4 assertion, the message wording) sits in one file next to the
check that consumes it, instead of splitting the declaration from its
enforcement across two modules. `formats.rs` stays a description of document
shape; legality stays a description of document lineage. Cohesion by concern
rather than by struct.

It also has zero derive risk, zero churn in `formats()`, and no chance of
disturbing the eight-format assertions already in `formats.rs`'s test module.

### Real cost

Three things sink it.

1. **R2 and R3 say "in the same place."** Not "declared once" — *in the same
   place its required sections and valid statuses are declared.* The user story
   behind them is explicit about the motivation ("so that I do not have to find
   four skill files to learn what the type may point at"). A side table
   satisfies "declared once" and fails the requirement as written.

2. **The declaration becomes optional.** A maintainer adding a ninth format
   edits `formats.rs`, compiles clean, and ships a format with no lifetime
   class and no parent set. The lookup returns `None`, the check skips, and
   nothing fails. Contrast `transition_spec`, where `None` is a *legitimate*
   answer — "this format has no transition behavior" is a real state of the
   world, and the set of transitioning formats is open. Legality is a closed
   set: **every** format has a lifetime, including a format whose parent set is
   empty. Encoding a total function as a partial lookup throws away the one
   property that makes R4 enforceable at build time.

3. **The key is a `String` with the casing problem in it, and no compiler
   help on either side.** Option A's `legal_upstream` entries have the same
   exposure, but Option B adds a second: the table's *keys* can also be
   misspelled, and a misspelled key silently makes a format undeclared rather
   than mis-declared. Two typo surfaces instead of one.

The R4 test is still a plain unit test under Option B — that is not a
differentiator. What differs is what the test can assume: under A the parent
lookup is total; under B the test must first assert that all eight formats
appear as keys, or a missing row passes vacuously.

---

## Option C — derive it from the existing chain model

### Strongest case

`lifecycle.rs` already models the tactical chain, already knows which types
are deleted at completion (`target_state_for` returns `TargetState::Deleted`
for Plan and Roadmap and a named status for the rest — which *is* the
Working/Durable distinction, spelled differently), and already walks the
`upstream:` edge. If the same distinction is spelled twice it can drift, and
the strongest version of this option is: don't declare the lifetime class at
all; read it off `target_state_for`, where `Deleted` means Working and
`Status(_)` means Durable.

That much is genuinely true and worth noting: **`target_state_for` is a
partial second spelling of the lifetime class today.** Any option that
declares the class separately creates a two-spellings-of-one-fact situation
that a maintainer could let drift.

### Real cost

The derivation does not reach.

`target_state_for` covers five formats and returns `TargetState::Unknown` for
VISION, STRATEGY and COMP — all three of which R5 classifies as Durable. So
the lifetime half is derivable for five of eight and silently wrong for three.
`ChainRole` has the same five variants and the same three gaps, so the
direction half cannot even name VISION, STRATEGY or COMP, let alone express
`VISION -> VISION`, `STRATEGY -> VISION`, or COMP's empty set.

There is no ordering to derive direction from. Nothing in the crate ranks the
types by altitude; `Chain::members` order is documented as carrying no
meaning, and `compute_passing_state` is a lookup table over `(role, posture)`.
An ordering would have to be invented, and inventing it does not finish the
job, because R5 is not a function of one ordering. It needs:

- an altitude ordering, plus
- a partition into strategic and tactical chains, plus
- a per-chain strictness flag (R5.1: strategic is immediate-parent-only,
  tactical is any-strictly-higher), plus
- BRIEF as a hardcoded exception — BRIEF sits above PRD in altitude and is
  tactical, so "any strictly higher" yields ROADMAP, STRATEGY, VISION, which is
  exactly the shape R4 forbids and R13 removes; its declared set is empty, plus
- COMP as a second hardcoded exception (empty set, no chain membership), plus
- PLAN's ROADMAP entry, which crosses from the tactical partition into the
  strategic one.

Eight literal rows are shorter, more readable, and directly diffable against
R5's table. The derivation is longer and answers a different question.

Two further objections, either of which is independently sufficient:

- The acceptance criteria demand "a test asserts... all eight declared legal
  parent sets against R2 and R5 **verbatim**, and fails on a single changed
  entry in any row." Against a derivation, that test asserts the derivation's
  output, and a change to the derivation's parameters that happens to produce
  the same eight rows passes. Verbatim against a table is a real check;
  verbatim against a computation is a tautology one refactor away.
- R18 requires the chain-walking readers to keep their current type-agnostic
  behaviour and says "the opinion about legality is the validator's alone."
  Deriving the validator's opinion from `lifecycle.rs`'s chain model couples
  the opinion to the walk the PRD explicitly says must not hold one. It also
  puts a `checks.rs` dependency on `lifecycle.rs`, inverting the current
  direction (`lifecycle.rs` depends on `formats.rs` and `frontmatter.rs`).

**Reject.** The one thing to carry forward from it: `target_state_for` and the
new lifetime class are two spellings of one fact for the five types they
overlap on, and the design should say which is authoritative. The right
resolution is a comment on `target_state_for` pointing at the declaration, and
a test asserting the two agree for the five overlapping formats — cheap, and it
converts the drift risk into a build failure. It should not become a
derivation in either direction: `target_state_for` also encodes *which* status
is terminal, which the lifetime class does not know.

---

## Option D — declare it in the skill prose, validator reads it at runtime

### Strongest case

The lifetime class is already written in every skill's `## Artifact Lifecycle`
section, in a consistent shape — `skills/brief/SKILL.md:46` reads
"**Lifecycle:** Durable. Stays in `docs/briefs/` after completion.", and
`skills/design/SKILL.md:26` reads the same shape. R2 even points at those
sections as the source: "The classes are those already documented in each
skill's `## Artifact Lifecycle` section." The strongest version is the
single-source-of-truth argument: put the fact in one human-readable place, and
code and prose cannot drift because there is only one of them.

### Real cost

`shirabe validate` is run against arbitrary trees. The golden parity harness
runs the binary with `tests/fixtures/golden/corpus/` as its working directory
— a directory with no `skills/` tree in it. A validator that resolves format
metadata by reading `skills/<name>/SKILL.md` either fails or silently
degrades there, changing frozen baselines and breaking R21 directly, and it
would impose a skills tree on every consumer repo.

R4 stops being a plain unit test. It becomes a test that reads files from
disk, and in a checkout without the skills tree it passes vacuously — the
exact opposite of "finds out before it can reach the corpus."

The parse target does not exist. "**Lifecycle:** Durable. Stays in
`docs/briefs/`..." is a sentence, not a field, and the legal parent sets are
not stated in that section at all — they would have to be added in a new prose
shape and then parsed. Parsing prose for a rule the build depends on is
strictly worse than declaring the rule.

It also turns `validate_file` — currently a pure function of `(Doc, FormatSpec,
Config)` — into something that does I/O, which every existing test of it would
have to accommodate.

**Reject.** The legitimate worry underneath it is code/prose drift, and the
PRD already answers it: R5.2 requires every reference documenting a forbidden
shape to be updated as part of this work, and the acceptance criteria include
"No file under `references/` or `skills/*/references/` documents a ROADMAP as
a legal upstream for a BRIEF, a PRD, or a DESIGN." Prose follows the
declaration; it does not become it.

---

## Referential integrity — the crux

A `legal_upstream: Vec<String>` entry naming a format that does not exist is a
typo the compiler cannot catch. The honest assessment has three parts.

### 1. The hazard is worse here than the usual stringly-typed complaint

The casing inconsistency turns a low-probability typo into a likely one. The
values a maintainer must write are `"Design"`, `"PRD"`, `"Brief"`,
`"Roadmap"`, `"VISION"`, `"Strategy"`, `"Plan"`, `"Comp"`. The table they will
copy from is R5, which spells all eight in upper case: VISION, STRATEGY,
ROADMAP, BRIEF, PRD, DESIGN, PLAN, COMP. A maintainer transcribing PLAN's row
faithfully writes `s(&["DESIGN", "PRD", "BRIEF", "ROADMAP"])` — and **three of
those four match nothing.** The same trap is set on every row except PRD's.

The failure is silent and directed the wrong way. An entry that matches
nothing shrinks the legal parent set, so the check reports a *direction
violation on a legal document*. Under the acceptance criteria that is a
false-positive error-severity finding on correct work, in a check whose entire
purpose is to be trusted at authoring time. This is not a cosmetic concern.

### 2. The referent set is closed, so a test closes the hole completely

`formats()` is a total, closed, in-process function returning eight specs.
Every legal-parent entry can be resolved against
`formats().iter().map(|f| &f.name)` in a unit test with no I/O:

```rust
#[test]
fn every_legal_upstream_entry_names_a_known_format() { ... }
```

That test catches every typo, every casing slip, and every renamed format,
with certainty rather than probability — unlike the usual open-world
stringly-typed case where no test can enumerate the referents. And the
acceptance criteria already require a test asserting all eight parent sets
against R5 verbatim, which subsumes it. So the gap is *closable* at zero
marginal cost.

### 3. It is still worth the enum, and the reason is not the typo

If the only argument were the typo, the test would win and `Vec<String>` would
be right. Two things push past it.

**The enum makes the failure impossible rather than caught.** R4's promise is
that a maintainer "finds out before it can reach the corpus," and the same
standard should apply to R3's declaration. With `Vec<FormatId>`, the parent
lookup is *total* — `formats().into_iter().find(|f| f.id == parent).expect(..)`
has an `expect` that provably cannot fire — and R4's test is an assertion
about lifetimes rather than an assertion about lifetimes plus an assertion
that the referents exist. That is a real reduction in what the test has to
carry, and the difference shows up again every time someone adds a format.

**The enum is where the display name goes.** The direction and lifetime
findings must name "the resolved type pair" (R6). `FormatSpec::name` is the
wrong string for that — three casings in one message — and `validate.rs:221`
forbids normalizing it in place. The codebase has solved this twice already
(`ChainRole::as_str()`, `check_orphan`'s `.to_uppercase()`), both times by
adding a display mapping beside a type. A `FormatId` gives that mapping a home
that covers all eight formats, so the finding reads `BRIEF -> DESIGN` in the
same casing as R5's table, with no third ad-hoc uppercasing added to the
crate.

**Churn is small and idiomatic.** Eight variants, one `id: FormatId` field
(eight one-line additions to the literal), one `display()` method. This crate
defines a dozen small enums for exactly this kind of closed domain. Nothing
outside `formats.rs` changes.

### The objection to the enum, and its answer

`ChainRole` is already a format-identity enum. Adding `FormatId` gives the
crate two overlapping identity types, and a reviewer will ask why.

The answer is that they are not the same question. `ChainRole` means "which of
the five roles a document can play in a tactical chain," lives in
`lifecycle.rs`, and is deliberately partial — VISION, STRATEGY and COMP have
no chain role and never will. `FormatId` means "which of the eight formats
this is," lives beside the formats it identifies, and is total. The right
long-term relationship is `ChainRole::from_format` taking a `FormatId` instead
of a `&str`, but **that migration is out of scope here**: it touches
`lifecycle.rs`, which R18 says must keep its current behaviour, and R21
forbids modifying existing tests. Recommend a doc comment on `FormatId`
stating the relationship and that unifying them is deliberate future work, so
the next reader finds the answer instead of the question.

The weaker middle path — `&'static str` constants (`const DESIGN: &str =
"Design";`) with `legal_upstream: Vec<&'static str>` — gets the casing fixed
in one place and catches a misspelled *constant name*, but the field's type
still accepts any string literal, so nothing forces a maintainer through the
constants. It is strictly less than the enum for the same amount of new code.
Not recommended.

---

## Lifetime class: enum, `bool`, or something else

**Two-variant enum.** `private: bool` is the right comparison to judge
against, and it reads well for three reasons that do not transfer:

- It is a predicate. "is private" is a yes/no property, and `!private` needs no
  name. `!durable` needs one, and the PRD gives it: **Working**. Encoding a
  named two-valued domain as the negation of one of its values discards the
  name, and the name is needed — R6's finding message has to say the word
  "Working" to a reader who has never opened a format reference, which is what
  R6 promises.
- It gates exactly one behavior (`check_private_only`'s early return). The
  lifetime class is read by the R4 build-time assertion, by the lifetime check
  at runtime, and by the R7 precedence rule — three readers, which is when a
  named type starts paying.
- `private` is not plausibly extensible; a third lifetime class is imaginable
  (something retired on a schedule rather than on chain completion). Not a
  strong argument on its own, but it points the same way.

R4's assertion reads better either way — `if spec.durable { assert!(parent.durable) }`
is perfectly clear — so the assertion is not the deciding factor. The message
text and the named domain are.

**Naming warning.** Do not call it `lifecycle: Lifecycle`. `crates/shirabe-validate/src/lifecycle.rs`
is a module, `lifecycle::Posture` is a type, and `ReviewPosture` carries a doc
comment saying it was named that way specifically "to avoid collision with the
multi-variant `crate::lifecycle::Posture`". A third collision in the same crate
is avoidable: R1 and R2 call the property **lifetime**, so
`lifetime: Lifetime { Durable, Working }` names it in the PRD's own vocabulary
and collides with nothing.

**Derives.** `#[derive(Debug, Clone, Copy, PartialEq, Eq)]` on both new enums.
`Copy` because they are fieldless and every existing peer (`ChainRole`,
`Posture`, `RootKind`) is `Copy`, so the check can pass them by value. Add
`PartialOrd, Ord` to `FormatId` only if a finding message needs a
deterministically ordered set of types — `Posture` derives them for exactly
that reason and documents it. `FormatSpec` itself cannot gain `Hash` or `Ord`
regardless, because `execution_mode_required_sections` already precludes them;
neither new field changes that ceiling.

---

## Recommendation

**Option A, with typed identities: add `lifetime: Lifetime` and
`legal_upstream: Vec<FormatId>` to `FormatSpec`, plus an `id: FormatId` field,
all defined in `formats.rs`.**

- `Lifetime { Durable, Working }` — a named two-value domain, not a `bool`,
  because R6's message must say "Working" and three readers consume the class.
- `FormatId` — eight variants, `id: FormatId` on `FormatSpec`, with a
  `display()` returning the upper-case form R5's table uses. It makes the
  parent lookup total, kills the casing trap that R5's own table sets, and
  gives the new findings their type names without touching `FormatSpec::name`,
  which `validate.rs` forbids normalizing.
- Empty parent set is `vec![]`, matching `issues_table_columns`' existing
  empty-means-none idiom in the same struct.
- Reject Option B because a side table makes the declaration optional where
  it must be total; reject C because `ChainRole` and `target_state_for` cover
  five of eight types and no altitude ordering exists to derive from; reject D
  because it puts I/O in `validate_file` and makes R4 pass vacuously in a tree
  without a skills directory.

Scope: **one file** for the declaration (`crates/shirabe-validate/src/formats.rs`),
about 60 lines including doc comments. One optional line in `lib.rs` if the
binary crate needs the types. No existing test is touched, satisfying R21.

Two tests, both plain unit tests over `formats()`, no I/O, no fixtures:

1. R4: no `Durable` format lists a `Working` format in `legal_upstream`.
2. R2 + R5 verbatim: all eight lifetime classes and all eight parent sets
   asserted literally against the PRD's table, failing on one changed entry.

Two follow-ups the design should record rather than do:

- `target_state_for` is a second, partial spelling of the lifetime class for
  five formats. Add a test asserting the two agree on those five and a comment
  naming `Lifetime` as authoritative. Do not derive either from the other —
  `target_state_for` also encodes *which* status is terminal.
- `ChainRole` and `FormatId` should eventually unify with `ChainRole::from_format`
  taking a `FormatId`. Out of scope here: it touches `lifecycle.rs` (R18) and
  its tests (R21).

## What would change my mind

- **If a reviewer rules that `FormatId` cannot coexist with `ChainRole` in
  this change**, fall back to `legal_upstream: Vec<String>` holding
  `FormatSpec::name` values, plus a mandatory third test asserting every entry
  resolves to a known format name. The hole is fully closable that way,
  because the referent set is closed — the loss is that the failure becomes
  caught rather than impossible, and the casing trap stays armed for the next
  maintainer. That is a defensible position, not a wrong one.
- **If `FormatSpec` turns out to be constructed outside this crate** (an
  external consumer building specs, or a `#[non_exhaustive]` requirement),
  adding required fields is a breaking change and Option B's side table
  becomes the pragmatic answer. I checked: nothing outside `formats.rs`
  constructs one today, and `lib.rs`'s own doc comment says the public surface
  is "unstable" and should be treated as `pub(crate)` until a concrete external
  caller commits. If koto has already linked against it, re-check.
- **If R2/R3's "in the same place" is read as satisfied by "declared once,
  anywhere"** — the PRD author's call, not mine — Option B's cohesion argument
  gets much stronger, and the deciding question narrows to whether a silently
  undeclared ninth format is acceptable. I would still say no, but the margin
  shrinks a lot.
- **If a third lifetime class is already anticipated** for a type that is
  neither retired-on-completion nor permanent, the enum choice stops being a
  judgment call and becomes forced.
