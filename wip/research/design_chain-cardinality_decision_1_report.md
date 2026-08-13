# Decision 1: parsing representation for sequence-valued frontmatter

**Decision question.** How should a YAML sequence value survive frontmatter
parsing, in what representation, and how should upstream resolution report
multi-entry and empty fields?

Source of requirements: `docs/prds/PRD-chain-cardinality.md` (R1-R5, R23, R24).

## Drivers

- **R1** — every entry preserved and *individually recoverable*, in written
  order, block and flow, single-entry included; the guarantee is *generic to
  sequence-valued fields*, not special-cased to `upstream:`.
- **R2** — one finding per unresolvable entry.
- **R3** — a present-but-empty `upstream:` reports exactly one finding that
  *names the field*, never a placeholder rendered as a path.
- **R5** — every reader interprets the same written value the same way; no
  reader silently reinterprets or discards what another accepted.
- **R23** — no corpus document changes its validation result; the full suite,
  including the frozen cross-implementation parity gate, passes unmodified.
- **R24** — no new frontmatter field, artifact type, or status.

## Evidence gathered

Everything below was measured in this worktree, either by reading the code, by
running the built binary against throwaway fixtures under the job tmp
directory, or by a standalone saphyr 0.0.6 probe. The repository was not
modified.

**E1 — saphyr hands us per-entry line numbers; the sequence container has
none.** Under `early_parse(false)` a block sequence yields
`YamlDataOwned::Sequence` whose *container* span is zeroed (`line 0 col 0`)
while each scalar entry carries a real span:

```
upstream:                     key  @line 2   value Sequence(len=2) @line 0
  - docs/a.md                   [0] Representation("docs/a.md") @line 3
  - docs/b.md                   [1] Representation("docs/b.md") @line 4
```

Flow sequences behave the same with both entries reporting the key's line.
Quoted entries arrive with comments already stripped and quotes already
removed (`- "docs/a.md"   # trailing comment` → `docs/a.md`). Nested
sequence-of-sequence and sequence-of-mapping entries carry no source text and
a zeroed span.

**E2 — newline-joining is provably ambiguous.** `- "docs/a\nb.md"` is a
*single* entry whose text contains a newline; saphyr returns it as one
`Representation("docs/a\nb.md")`. Joined with `\n`, it is byte-identical to a
two-entry sequence `- docs/a` / `- b.md`, and `extract_upstreams` splits both
to the same two-element result. Entry count and entry boundaries are not
recoverable from the joined string. R1's "individually recoverable" fails on
this input under any join-based scheme.

**E3 — the joined-multi-path failure is observable today, not hypothetical.**
A `|` block scalar already reaches the scalar readers as one joined string.
Running the built binary against a fixture:

```
::error file=docs/prds/PRD-blockscalar.md,line=6::[R6] upstream
  "docs/briefs/BRIEF-x.md\ndocs/briefs/BRIEF-missing.md" does not exist on disk
```

That message — a path nobody wrote, with an escaped newline in the middle — is
exactly what a join-based representation would produce for *every*
sequence-valued `upstream:`. Meanwhile the same document is absent from the
L02 orphan list, because `extract_upstreams` did split it into two upstreams.
One document, two readers, two different answers, no diagnostic. That is the
R5 violation in its live form.

**E4 — the Go baseline collapses sequences identically, so any fix is a
deliberate divergence from the frozen parity reference.**
`git show 20fb8ed:internal/validate/frontmatter.go` reads
`value := valNode.Value` for every mapping value; `yaml.Node.Value` is `""`
for a `SequenceNode`. The Rust `scalar_source_text(...).unwrap_or_default()` is
a faithful port of that behavior. Consequence: a sequence-valued fixture can
never be added to `crates/shirabe/tests/fixtures/golden/corpus/`, because the
expected bytes are captured from a Go binary that cannot be fixed. Sequence
coverage must live in crate unit tests and the non-parity integration tests.

**E5 — R23 holds for every option, and the check is now on the record.** All
four `upstream:` values in the parity corpus are plain scalar paths. Across
this repository and the two sibling public repositories the PRD names as the
validation set (`koto`, `niwa`, `tsuku`), every `upstream:` in `docs/` is a
plain scalar path: no sequence, no flow list, no `|` or `>` block scalar, no
null, no empty string. The only `<placeholder>` forms live in skill reference
templates, which carry no detectable format prefix and are never validated.

**E6 — the churn surface of a typed representation is small.** Seven
`FieldValue { ... }` construction sites exist crate-wide, two of which are the
`fv()` test helpers in `checks.rs:3353` and `validate.rs:283` that absorb the
fixture churn. Eleven real `.value` reads exist: `frontmatter.rs:122,126`
(deriving `Doc.schema` / `Doc.status`), `checks.rs:178,790,2898,3005`,
`lifecycle.rs:376,399`, `finalize.rs:725,810`, `transition.rs:1228`.
`populate.rs` parses docs but never touches `fields`.

**E7 — parsing alone does not satisfy R5; two reader divergences survive it.**
Verified against the binary and the source:

| Written value | `check_upstream_resolves` | `extract_upstreams` |
|---|---|---|
| `docs/briefs/BRIEF-<name>.md` | R6 error, "does not exist on disk" | silently skipped (`<`/`>` filter, `lifecycle.rs:418`) |
| `owner/repo:docs/x.md` | silently skipped (`is_cross_repo_reference`) | joined to root as a relative path, kept as an edge |

Neither is live in the current corpora, but both are the same class of defect
the PRD is fixing, and R5's text ("every reader interprets the same written
value the same way") covers them. `extract_upstreams` also does its own `- `
stripping, `#` comment stripping and newline splitting, none of which the
other readers do.

**E8 — written order survives to output on the per-file path.**
`validate_file` extends its error vector in check order and does not sort;
`check_upstream_resolves`'s own vector order is the emission order. The
lifecycle path sorts by `(file, code, message)` (`lifecycle.rs:917`), which
concerns L-codes, not R6.

**E9 — the three empty shapes, as the parser sees them.** `upstream:` (null)
arrives as `Representation("~")`; `upstream: []` as `Sequence(len=0)`;
`upstream: ""` as `Representation("", DoubleQuoted)`. The first two produce
today's `[R6] upstream "~" does not exist on disk` and
`[R6] upstream "" does not exist on disk`.

## Options

### (a) Render sequences as newline-joined text

`scalar_source_text` gains a sequence arm that joins entry texts with `\n`;
`FieldValue.value` stays `String`. `extract_upstreams` starts working
unchanged, since it already splits lines and strips `- `.

*What breaks.* Nothing compiles differently, which is the problem. **This is
the option that leaves every scalar reader silently receiving a joined
multi-path string** — all three of them: `check_upstream_resolves` reports
E3's fabricated path, `finalize::read_upstream` returns it into the chain walk
as one node path, and `transition.rs`'s status reader would do the same for
any field written as a list. The only fix is to update those readers, at
which point option (a) has cost as much as (b) and delivered less.

*R1.* Fails on E2: entry boundaries are not recoverable when an entry contains
a newline, and a blank entry vanishes entirely.

*R2.* Per-entry line numbers (E1) are thrown away, so every finding lands on
the key's line. Workable but strictly worse than what the parser already
offers for free.

*R5.* Violated by construction, and the violation is invisible to the compiler
and to any future reader added after this change.

A delimiter variant — join with a control character no path can contain —
closes E2's ambiguity but keeps handing scalar readers an unreadable string
and invents a private encoding on top of a data structure that already models
lists. Strictly dominated by (b).

### (b) Typed field value, every reader asks for what it wants — RECOMMENDED

```rust
pub struct FieldValue {
    pub line: usize,          // the key's line, unchanged
    pub value: FieldData,
}

pub enum FieldData {
    Scalar(String),            // a scalar node's original source text
    Sequence(Vec<FieldEntry>), // entries, in written order
    Unsupported,               // mapping, alias, bad value
}

pub struct FieldEntry {
    pub text: String,  // the entry scalar's source text; empty for a non-scalar entry
    pub line: usize,   // absolute line, or the key's line when the entry has no span
}

impl FieldValue {
    pub fn as_scalar(&self) -> Option<&str>;   // None for Sequence and Unsupported
    pub fn entries(&self) -> Vec<FieldEntry>;  // a Scalar yields exactly one entry
}
```

*What changes.* `as_scalar()` is fallible, so `fv.value` no longer compiles
and the compiler enumerates all eleven reads (E6). Scalar-only fields
(`status`, `execution_mode`, `issue_count`) write `as_scalar().unwrap_or("")`,
which reproduces today's bytes exactly and turns an invisible default into a
greppable, per-site declaration that the field is scalar-only. The three
upstream readers call `entries()`. `Doc.schema` and `Doc.status` stay `String`,
derived the same way, so `populate.rs`, `transition.rs`'s body rewriter and
every status consumer are untouched.

*R1.* Satisfied generically: the parser preserves entries for *any*
sequence-valued field with no schema knowledge, and `entries()` is available on
every field. Order is the mapping-iteration order saphyr produced (E1).

*R2.* Per-entry findings at per-entry lines, straight from E1.

*R5.* Satisfied at the type level rather than by review discipline: there is no
representation in which a multi-entry value can masquerade as a scalar. The
uniform interpretation is "a field's value is a list of entries; a scalar is a
one-entry list," which is R1's own wording.

*R23/R24.* No new frontmatter field, artifact type or status. No corpus
document changes result (E5). No serde derive exists on `Doc`, and
`shirabe-validate` is `publish = false`, so the type change has no consumer
outside the workspace.

### (c) Scalar path retained, parallel accessor only for declared multi-valued fields

`FormatSpec` gains a `multi_valued_fields` list; the parser populates entries
only for those keys.

*What breaks.* `FormatSpec` has no per-field type information today — it
carries `required_fields: Vec<String>` and nothing else about a field — so this
is new declaration machinery. Worse, `parse_yaml_fields` is reached from
`parse_doc`, which is schema-blind by design and called from five modules
(`main.rs`, `populate.rs`, `finalize.rs` ×2, `lifecycle.rs` ×2,
`transition.rs`); the format is detected separately, from the filename, *after*
parsing. Threading a `FormatSpec` into the parser inverts the module
dependency and forces every caller to know a format before it can read a file —
including callers that parse documents whose format is unknown or absent.

*R1.* Directly contradicted. R1 says the guarantee is "generic to
sequence-valued fields, not special-cased to `upstream:`", and a declaration
list is that special case wearing a general-purpose costume: a sequence-valued
field nobody remembered to declare still collapses to `""`. The acceptance
criterion "a sequence-valued frontmatter field other than `upstream:` survives
parsing" would pass only for whichever second field the implementer thought to
declare.

### (d) Additive entries alongside an unchanged scalar `value`

`FieldValue` keeps `value: String` with today's exact semantics (`""` for a
sequence) and gains `entries: Vec<FieldEntry>`, populated always, never
schema-gated. Three upstream readers opt into `entries`; nothing else changes.

This is the strongest rival to (b) and deserves to be taken seriously: it
compiles with zero edits outside the three readers, it is R23-free by
construction because every existing reader sees byte-identical values, and it
satisfies R1 and R2 as completely as (b) does. Its whole cost is eight fewer
one-line edits.

*Why it still loses.* It keeps the silent collapse alive for everyone who does
not opt in. A sequence written under `status:` or `execution_mode:` still
arrives as `""` at readers that will never know a sequence was there — which
is verbatim what R5 forbids ("SHALL NOT be silently reinterpreted or
discarded"). The three upstream readers being correct is a fact about today's
code, not a property of the representation; the fourth reader, added six months
from now against a `value: String` that looks total, inherits the bug. The PRD
exists because exactly that happened once already: `extract_upstreams` was
written to handle lists and shipped unreachable for want of a representation
that could carry one.

### (e) Re-parse the raw YAML inside the upstream readers

Leave the parser alone; give `lifecycle.rs`, `checks.rs` and `finalize.rs` a
shared `upstream_entries(doc)` that re-reads the file with saphyr.

Rejected on R5's plainest reading: two parsers over one file is the definition
of two readers that can disagree, and the second one would not see the
`early_parse(false)` representation guarantees the first depends on (module
docs in `frontmatter.rs:196-204`). It also doubles I/O on every document and
leaves `FieldValue.value` still lying about sequences.

## Recommendation

Adopt **(b)**, with four companion commitments that the design should carry
explicitly, because (b) alone does not close R5.

**1. Do not newline-split scalars in `entries()`.** A `Scalar` yields exactly
one entry containing its whole text. Splitting scalars is precisely the
ambiguity that sinks option (a), and it would make every `problem: |` prose
block read as a many-entry list. The cost is real and should be stated: a
`upstream: |` two-line value stops half-working — today it produces E3's
fabricated R6 message *and* two chain edges; afterwards it produces one
unresolvable entry naming the joined text. E5 confirms no such document exists
in any of the three repositories the PRD validates against.

**2. Delete the string surgery in `extract_upstreams`.** The line splitting,
`- ` stripping and `#` comment stripping at `lifecycle.rs:407-420` all become
dead once the parser returns real entries, and saphyr already strips comments
and quotes correctly (E1). Leaving them in means three copies of normalization,
which is how readers drift apart in the first place.

**3. Put entry normalization in one shared helper.** The placeholder rule, the
cross-repo rule, self-reference suppression and trimming must live in one
function that all three readers call. E7 shows two divergences that survive a
perfect sequence parser untouched. If the design splits this into a separate
decision, the two must land in the same change; R5 is not met by parsing alone.

**4. Keep sequence coverage out of the parity corpus.** E4: the frozen Go
baseline collapses sequences, so any sequence fixture in
`tests/fixtures/golden/corpus/` would fail the parity gate permanently and
could only be "fixed" by editing the gate, which R23 forbids.

### The empty-field finding (R3)

Report `[R6] upstream is present but empty`, at the key's line, at error
severity, under the existing `R6` code. It names the field, carries no
placeholder masquerading as a path, and matches house message style (the
existing R6 messages state a fact and offer no remediation clause).

*Which written shapes are empty.* Null (`upstream:`, E9's `~`), an empty
sequence (`upstream: []` and an empty block sequence), and a scalar that is
empty after trimming (`""`, `''`, whitespace only). The third goes beyond R3's
literal text, which names only "no value at all" and "an empty sequence".
Recommend including it anyway and flagging the extension to the PRD author:
`upstream: ""` is the same authoring mistake, and its current message —
`[R6] upstream "" does not exist on disk` — is exactly the
placeholder-reported-as-a-path that R3 outlaws. E5 confirms no document in the
validated set writes it, so R23 is unaffected either way.

*Where the boundary sits.* A sequence with at least one entry is never "the
empty field", even when an entry is blank. `upstream: [""]` is one entry that
is blank, and reports one *per-entry* finding under R2, not a field-level one.
This keeps R3's "exactly one finding" true in both directions and stops the
field-level message from absorbing a per-entry problem.

*Unsupported values.* `upstream: {a: b}` maps to `FieldData::Unsupported` and
reports one finding, `[R6] upstream value is not a path or a list of paths`.
Dropping it silently would be the discard R5 forbids, and calling it "empty"
would be untrue.

### Per-entry findings (R2)

- One finding per entry that does not resolve; resolving entries produce
  nothing. **At most one finding per entry** — check existence first, git
  tracking second, and stop at the first failure for that entry, so a missing
  file never also reports as untracked.
- Cross-repo entries are skipped per entry, so a two-entry `upstream:` mixing
  a local and a cross-repo reference reports only on the local one.
- A non-scalar entry (a nested list or mapping under `upstream:`) has no source
  text and no span (E1). Report one finding at the key's line rather than
  dropping the entry.
- **Line**: the entry's own absolute line. Block-sequence entries get their own
  `- ` line; flow-sequence entries all resolve to the key's line, which is
  correct because that is where they are written; a scalar and a non-scalar
  entry fall back to the key's line.
- **Order**: written order, which is also the order `entries()` returns and,
  per E8, the order that survives to output on the per-file path. The design
  should pin this with a test asserting finding order for a three-entry
  sequence with two failures — nothing structurally prevents a future sort from
  silently breaking it.

## Open risks

1. **The PRD's parity note points the wrong way.** Known Limitations says "R1 is
   also what makes a sequence-valued parity fixture possible, so the parity
   baseline needs re-establishing as part of satisfying R23." E4 says the
   opposite: R1 makes such a fixture *impossible*, because the reference binary
   is a frozen Go build that collapses sequences, and re-capturing the baseline
   from ref `20fb8ed` reproduces the collapse rather than the fix. The
   acceptance criterion "a sequence-valued frontmatter field other than
   `upstream:` survives parsing" must be satisfied by a crate test. Worth
   raising with the PRD author.

2. **Multiple R6 findings per file is new.** Today `check_upstream_resolves`
   returns at most one error per document. A three-bad-entry document will emit
   three. Nothing was found that assumes one, but the merge gate, the
   annotation writer and the advisory summariser were not audited for it. Cheap
   to check; should be checked before the change lands.

3. **The `|` block-scalar behavior change is verified narrowly.** E5 covers this
   repository plus `koto`, `niwa` and `tsuku`. The PRD's own Known Limitations
   already concede this set is narrower than the documents these changes will
   eventually meet.

4. **Order comes from saphyr's mapping iteration.** Entry order within a
   sequence is source order and is solid. Field iteration order across the
   mapping is not something any requirement depends on, but if a later decision
   needs deterministic field ordering it should not assume `HashMap<String,
   FieldValue>` provides it.

5. **R5's remaining half is a different decision's territory.** `lifecycle.rs:542`
   (`cur = node.upstreams.first().cloned()`) still keeps only the first upstream
   in the chain walk. That is R4's problem, not R1's, but a reviewer checking
   the acceptance criterion "the same set of two upstream paths is visible in
   all three of the resolution check, the chain memberships, and the
   finalization walk's node list" will fail it on this line even with Decision 1
   fully implemented.

---

<!-- decision:start id="chain-cardinality-decision-1" status="confirmed" -->
### Decision: Sequence-valued frontmatter parsing representation

**Context**
`scalar_source_text` returns `None` for a sequence node, so every
sequence-valued frontmatter field collapses to `""` before any consumer sees
it (`frontmatter.rs:236,264-270`). Three readers of `upstream:` disagree about
the field's shape, and the one that understands lists has never been reachable.
The Go baseline the parity gate freezes has the same defect, so any fix is a
deliberate divergence from it. The representation chosen here determines
whether R5 — every reader interprets the same written value the same way —
becomes a compile-time property or a review convention.

**Assumptions**
- No document in this repository, `koto`, `niwa` or `tsuku` writes `upstream:`
  as a sequence, a block scalar, a null or an empty string. Verified today; if
  wrong, that document's validation result changes and R23 breaks.
- No consumer outside the workspace depends on `FieldValue`'s shape. Verified:
  no serde derive on `Doc`, `shirabe-validate` is `publish = false`.
- Nothing downstream assumes at most one R6 finding per file. Not verified.

**Chosen: typed field value with fallible scalar access**
`FieldValue` carries `FieldData::{Scalar(String), Sequence(Vec<FieldEntry>),
Unsupported}` plus the key's line. `as_scalar() -> Option<&str>` returns `None`
for anything that is not a scalar; `entries() -> Vec<FieldEntry>` returns
per-entry text and per-entry line numbers, with a scalar yielding exactly one
entry and no newline splitting. `Doc.schema` and `Doc.status` stay `String`.
Scalar-only readers write `as_scalar().unwrap_or("")`, reproducing today's
bytes. Companion commitments: delete `extract_upstreams`'s string surgery,
centralize entry normalization (placeholder, cross-repo, self-reference,
trimming) in one shared helper, and keep sequence fixtures out of the parity
corpus. A present-but-empty field reports `[R6] upstream is present but empty`
at the key's line; unresolvable entries report one finding each, at their own
lines, in written order.

**Rationale**
It is the only option under which a multi-entry value cannot masquerade as a
scalar, which is what R5 asks for. The cost is bounded and was measured: eleven
`.value` reads and seven construction sites, two of them test helpers. Per-entry
line numbers come free from the parser and make R2's findings point at the
offending entry. R1's genericity requirement is met without the parser learning
anything about formats.

**Alternatives Considered**
- **Newline-joined text**: provably ambiguous when an entry contains a newline,
  discards per-entry line numbers, and hands all three scalar readers a
  fabricated multi-path string — a failure already observable today through the
  `|` block-scalar path. Rejected.
- **Schema-declared multi-valued fields**: contradicts R1's "not special-cased"
  clause, requires new `FormatSpec` machinery, and inverts the module dependency
  by forcing a schema-blind parser to know the format. Rejected.
- **Additive `entries` beside an unchanged `value: String`**: satisfies R1 and
  R2 fully and costs eight fewer edits, but preserves the silent collapse for
  every reader that does not opt in, which is the discard R5 forbids, and makes
  correctness a property of today's three call sites rather than of the type.
  Rejected, narrowly.
- **Re-parsing the raw YAML in the upstream readers**: two parsers over one
  file is the R5 violation restated. Rejected.

**Consequences**
Sequence-valued fields become recoverable for every field, not just
`upstream:`, and findings gain per-entry precision. Eleven call sites must
state whether they want a scalar, which is the point. A `upstream: |` block
scalar stops producing two chain edges — verified to affect nothing in the
validated corpora. Sequence coverage cannot enter the parity corpus and must
live in crate tests. A document with several bad upstream entries now emits
several R6 findings where it emitted one.
<!-- decision:end -->
