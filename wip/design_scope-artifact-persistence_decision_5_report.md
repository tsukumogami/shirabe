<!-- decision:start id="validator-contribution-representation" status="assumed" -->
### Decision: Validator representation and enforcement of contribution sections

**Context**

R8 asks `shirabe validate` to require the contribution sections a document's
absorption declaration implies, R9 asks the existing canonical-section-order
check to enforce their placement, and R29 asks all of it to be invisible on the
516 chain documents already on disk. Three things about the current validator
decide most of the answer.

The frontmatter schema is open — no check anywhere rejects an unknown key, and
every read is a targeted `fields.get("<name>")` — so a new key costs nothing to
introduce. Only `upstream:` is ever resolved as a path, by R6, L04 and the
finalization walk; `superseded_by:`, the nearest analogue, is never resolved by
the validator at all. R21's path-resolution exclusion is therefore satisfied by
construction rather than by a carve-out: any key that is not `upstream:` is
already excluded, and the design's obligation is the negative one of not adding
the new key to those three readers.

The parser, though, cannot read structure. A frontmatter value that is a
mapping becomes `FieldEntries::Other` and its nested pairs are discarded
outright — unrecoverable from `Doc`, since body scanning starts after the
closing `---`. A sequence of mappings becomes `Sequence(["", ""])`: the item
count survives and every item's text is empty. So the declaration is a flat
list of strings or it is a change to `frontmatter.rs`, which sits upstream of
every check and of both parity harnesses.

And `required_sections_for` (`crates/shirabe-validate/src/checks.rs:181`) has
exactly two callers, FC04 and FC15, and every one of the eight formats'
`required_sections` lists begins with `"Status"` — as do all three Plan
`execution_mode` lists. A splice immediately after that first entry is
well-defined for every profile without a per-format special case.

**Assumptions**

- The absorb procedure, not a document template, writes the declaration. No
  template carries `absorbed:` as an unfilled placeholder; if one did, the
  placeholder-skipping normalizer would leave the field with zero entries and
  FC17 clause 1 would fire.
- Two absorbed documents of the same type cannot arise from a legal `/scope`
  run, since each type appears once per chain.
- Recording the per-contribution carry result in the survivor's frontmatter is
  not required of this field. That is R20's record, whose surface is a separate
  open question; the parser could not hold it here anyway.
- The `## Status` line R21 also requires is a separate surface with its own
  pinned shape, modelled on `transition.rs`'s `Superseded by [name](path)`. It
  is not part of this decision beyond the constraint that both surfaces name
  the same absorbed artifact.

**Chosen: `absorbed:` holding paths, spliced into `required_sections_for`,
with `Absorbed <Type>` headings from one table and a fail-closed FC17**

*The declaration.* A new optional frontmatter key, `absorbed:`, holding a
scalar or a sequence of repo-relative paths to the documents this one absorbed
— the same shape `upstream:` accepts, read through the same
`upstream::field_entries` normalizer, and so inheriting its trim, blank-drop
and placeholder-skip semantics for free. The absorbed *type* is derived from
the basename prefix by the longest-prefix rule `detect_format` already uses;
nothing declares the type redundantly.

Transitive accumulation is expressed by the list being flat and complete rather
than nested: the absorb procedure sets `survivor.absorbed = ancestor.absorbed
++ [ancestor.path]`. A PLAN that absorbed a DESIGN which had absorbed a PRD
which had absorbed a BRIEF carries three entries, not a tree and not a product.
The list is read as a set of types ordered by chain position, so a
mis-ordered list cannot produce a mis-ordered section requirement.

Every entry is dead by construction, and `absorbed:` is deliberately not added
to R6, `lifecycle::extract_upstreams`, or `finalize::read_upstream_entries`.

*The mechanism.* `required_sections_for` gains a second branch beside the
`execution_mode` one:

```rust
fn required_sections_for(doc: &Doc, spec: &FormatSpec) -> Vec<String> {
    let base = /* the existing execution_mode branch, unchanged */;
    let contributions = contribution_headings(doc);   // empty when no `absorbed:`
    if contributions.is_empty() {
        return base;
    }
    splice_after_status(base, contributions)
}
```

`contribution_headings` returns the headings implied by `absorbed:`, in chain
order, and returns empty for a document with no such key — which is every
document on disk today. `splice_after_status` inserts them immediately after
the `"Status"` entry.

FC04 then reports a missing contribution section at error level, with its
existing message and from the family authors already know. FC15 reports
relative-order drift. R8 and R9 are satisfied through the existing mechanism,
with no second presence checker and no second order checker.

*The new check.* One error-level code, FC17, gated entirely on `absorbed:`
being present, owning what FC15 structurally cannot express and what the
declaration itself needs. Four clauses:

1. The field yields at least one usable entry. A mapping-shaped value
   (`FieldEntries::Other`), an all-blank sequence, or a value whose every entry
   is a placeholder is an error, not a silent no-op.
2. Every entry's basename matches a prefix in the contribution table, and is
   not a cross-repo `owner/repo:path` reference — you cannot absorb a document
   in another repository.
3. Every entry's type sits strictly above the carrying document's own type in
   the chain. A PRD declaring an absorbed DESIGN is an error.
4. The implied contribution sections appear contiguously and immediately after
   `## Status`, in chain order.

Clause 4 is the reason FC17 is not a severity workaround. `check_fc15`
(`checks.rs:226-286`) compares only the *relative* order of the required
sections present and explicitly permits unrequired sections between them, so a
contribution section three headings below `## Status` satisfies it at any
severity. R4's "after `## Status` and before its own first other required
section" is strictly stronger than what FC15 can say. FC17 also delivers the
acceptance criterion that `shirabe validate` *fails* on out-of-order
contribution sections, which FC15 cannot: FC15 is registered in
`is_intrinsic_notice` behind a documented promotion seam that waits on a
corpus-cleanup PR, and promoting it is exactly the R29 breakage that seam
exists to avoid. On an out-of-order contribution both fire — FC15 as a notice,
FC17 as an error. That is diagnostic redundancy on an already-broken document,
not a contradiction.

*The headings.* Four fixed strings, declared once, in `formats.rs` beside
`required_sections` — the same file the format references mirror:

```rust
/// The tactical chain in order, with the heading a survivor uses to carry each
/// type's contribution. Array order is the chain order R6 and R9 require; the
/// string is the fixed heading R5 requires. One table, so the format
/// references and the validator have a single thing to agree with.
pub const CONTRIBUTION_SECTIONS: [(&str, &str); 4] = [
    ("BRIEF-",  "Absorbed Brief"),
    ("PRD-",    "Absorbed PRD"),
    ("DESIGN-", "Absorbed Design"),
    ("PLAN-",   "Absorbed Plan"),
];
```

Keyed by prefix, so it composes with `detect_format`'s longest-prefix rule and
needs no new `FormatSpec` field and no edit to the eight existing constructors.
Array position gives both the chain order for R6's ordering and the strict
comparison for FC17's clause 3. A prefix absent from the table is FC17 clause
2, which is what makes `absorbed: docs/strategies/STRATEGY-x.md` an error
rather than a silent nothing — the strategic chain has no contribution model,
and the PRD puts it out of scope.

`Absorbed Plan` is structurally unreachable: the PLAN is terminal, so nothing
downstream survives to carry it. The row stays because the acceptance criterion
requires all four format references to name exactly one contribution for their
type, and the table is the thing they name.

Collision check against the union of every required section of all eight
formats plus the three Plan execution-mode lists — 46 distinct names — finds no
name beginning with `Absorbed`. Grep over `docs/`, `crates/` and `skills/`
finds no `^## Absorbed` heading and no `absorbed:` key anywhere in the
repository today.

**Rationale**

The declaration holds paths because the PRD's own acceptance criterion requires
it ("a survivor's absorption declaration is present and holds the absorbed
path") and because R21's named beneficiary is a reader holding a dead path who
does not know the survivor exists. Type names alone would strand exactly that
reader and would not distinguish absorbing this chain's PRD from another's. It
is flat because the parser cannot hold anything else without a change to
`frontmatter.rs`, and flat is also what keeps transitive accumulation linear.

The mechanism is a splice because `required_sections_for` is already the single
seam both checks consult, and because R9 asks for the *existing* order check
rather than a new one. The `execution_mode`-style keyed map — the one existing
precedent — is the alternative that produces R6's combinatorial explosion
literally: one key per reachable absorption combination per profile, each a
copy of the base list, drifting from it the first time a required section
changes.

FC17 exists for clause 4 rather than for severity. Adjacency is a contract FC15
cannot express and would still not express if it were promoted to error
tomorrow.

**The fail-open-or-closed call: closed.**

`execution_mode`'s fail-open does not transfer, and the reason is specific
rather than stylistic. `execution_mode` is a *required* field of the Plan
profile, so FC01 catches its absence at error level; its fail-open arm covers
only a typo in a value the document must carry, and its fallback is the flat
`required_sections` — a real contract that still validates the document. The
contribution key is optional by design and its fail-open fallback is no
obligation at all. A mistyped path, a stray mapping, or a prefix outside the
table would silently disable the one static check standing behind a completed
deletion, at the one moment when the absorbed document is already gone and
cannot be re-read. That is the failure mode R30 names — fail toward `keep` at
every decision point — arriving one step too late to fail toward anything.

Failing closed costs nothing against R29 because the whole family is gated on
the key being *present*: a document with no `absorbed:` emits nothing from
FC04's spliced branch and nothing from FC17, whatever else is wrong with it.

The split matters in implementation. `required_sections_for` stays total and
pure — it returns a `Vec`, so when the declaration is unreadable it can only
return the base list, which is structurally fail-open. The closed door is FC17,
which reads the same field and errors. Fail-closed is a property of the check
family, not of the helper.

**Alternatives Considered**

- **A sequence of type names** (`- BRIEF`, `- PRD`): smaller, and the validator
  wants the type anyway. Rejected because it drops the path the PRD's
  acceptance criterion requires the field to hold, strands R21's named
  beneficiary, and cannot distinguish this chain's PRD from another's.
- **A sequence of mappings** carrying path, type and carry result: the richest
  shape and the only one that could also serve R20's record. Rejected at the
  parser — every item's text comes back empty and a bare mapping is discarded
  unrecoverably, so reading it means changing `frontmatter.rs` upstream of
  every check and both parity harnesses.
- **A compound scalar** (`PRD:docs/prds/PRD-x.md`): fits the parser and carries
  both facts. Rejected because the type is already derivable from the prefix,
  so the encoding is redundant and admits a state the derivation cannot — a
  declared type disagreeing with the filename — and its shape collides with
  `is_cross_repo_reference`'s `owner/repo:path` discriminator.
- **Reuse `upstream:` with a marker**: rejected on sight. R17 splices the
  absorbed document's *parents* into `upstream:`, so the two fields hold
  different things, and `upstream:` is the one field that is path-resolved,
  which is precisely what R21 excludes.
- **Splice only, no new check code**: minimal and satisfies R8 and R9 as
  written. Rejected because R4's adjacency contract then goes entirely
  unchecked, and the acceptance criterion demanding a *failure* on out-of-order
  contributions cannot be met — FC15 is notice-level behind a promotion seam
  that exists because promoting it breaks the corpus.
- **A standalone check owning presence, order and adjacency, leaving
  `required_sections_for` untouched**: smallest blast radius on shared code.
  Rejected because it re-implements presence and order beside the two checks
  that already do it, contradicts R9's instruction that the existing order
  check enforce the placement, and hands authors a missing-section message from
  a different family than every other missing section.
- **An `execution_mode`-style map keyed by the absorption set**: mirrors the
  one existing precedent exactly. Rejected as the literal instance of R6's
  combinatorial explosion, with every entry a copy of the base list that drifts
  from it on the first section change.
- **`Brief Contribution` / `PRD Contribution` headings**: matches the PRD's own
  vocabulary. Rejected as ambiguous in the document — in a surviving PRD,
  `## Brief Contribution` reads as plausibly "what this contributes to the
  brief" — and because it does not announce the absorb event.
- **Contribution-noun headings** (`Framing`, `Requirements`, `Approach`,
  `Sequencing`): the best prose. Rejected because `Requirements` is a live
  required section of the PRD profile, so a DESIGN carrying an absorbed PRD
  would present a heading that is another format's required section, and
  because it needs a per-type noun table with nothing forcing it to agree with
  the format references.
- **Deriving the heading from `FormatSpec.name`** (`format!("Absorbed {}",
  spec.name)`): happens to produce all four correct strings today. Rejected
  because it couples a user-visible heading to a field whose other uses are
  diagnostic, and the coupling breaks silently on a profile rename or if the
  strategic chain ever gains contributions (`Absorbed VISION`).

**Consequences**

*What this buys.* R8 and R9 land as a branch in a function that already
branches, with FC04's error severity and message reused. R21's
path-resolution exclusion needs no code — only the discipline of not adding
`absorbed:` to the three `upstream:` readers, which is worth a comment on the
key's declaration since the omission is the whole mechanism. R6's transitive
accumulation is a list append.

*The fixture tripwires clear, and for one reason.* Every added obligation is
gated on `absorbed:` being present, and no document in this repository carries
it — verified by grep over `docs/`, `crates/` and `skills/`, zero hits.
`absorption-golden/expected/sections-clean/` expects the empty fired-rule set
under `--check FC04 --check FC15` over
`corpus/sections-clean/docs/designs/DESIGN-x.md`; that document's frontmatter
is `schema`, `status`, `problem`, `decision`, `rationale` and nothing else, so
`contribution_headings` returns empty, `required_sections_for` returns the base
list byte-identically, and the case still fires nothing. The other eleven
absorption cases are unaffected for the same reason, and FC17 appears in no
case's `--check` column. `parity.rs`'s 29 corpus files likewise gain no
finding, so stdout, stderr and exit code are unchanged and
`capture_go_baseline.sh` — which would require rebuilding the pinned Go binary
at `20fb8ed` — never has to run. `fc07_corpus.rs`'s notice allowlist is
untouched, since FC17 is error-level and fires on nothing committed.

*What this constrains going forward.* No absorbing document may be added to
`parity.rs`'s golden corpus. The Go reference binary has no FC17 and no spliced
branch, so such a document would diverge byte-for-byte by construction and
could never be baselined. FC17's own coverage therefore belongs in
`shirabe-validate` unit tests plus the corpus-walk test R29's criteria call
for, not in either parity harness. `absorption_parity.rs`'s append-only
contract is satisfied trivially — nothing is appended, because FC17 has no
external counterpart to be at parity with.

*What has to be kept in step.* `is_known_check_code` (`validate.rs:150`) gains
an `FC17` arm or `--check FC17` is rejected; its tests are membership-only, so
omitting the arm fails loudly but adding it breaks nothing. FC17 must stay out
of `is_intrinsic_notice` to be error-level. `main.rs:529`'s valid-codes string
(`"FC01-FC16"`) and the already-stale doc comment at `main.rs:214` (`FC01`-
`FC13`) both need updating, and neither is covered by a test —
they drift silently and always have. R26's `docs/guides/doc-validation.md`
update is likewise unenforced by any harness; the guide currently documents
only FC01-FC04 and is already six codes behind.

*What stays unbought.* Everything Known Limitations already says: FC04 on the
spliced list buys presence, and FC17 buys placement and a well-formed
declaration. Neither says anything about whether the section carries the
ancestor's argument. An empty `## Absorbed PRD` satisfies both.
<!-- decision:end -->
