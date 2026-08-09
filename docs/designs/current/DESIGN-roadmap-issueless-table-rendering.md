---
schema: design/v1
status: Current
upstream: docs/prds/PRD-roadmap-issueless-table-rendering.md
problem: |
  `shirabe roadmap populate --no-issues` renders an Implementation Issues table
  keyed `F1`, `F2`, `F3` with description cells derived by an unbounded
  heuristic, so a row can't be identified from the table and a cell can run to
  thousands of characters. A feature with no prose body renders a cell the
  validator rejects outright. The keying also contradicts the shared
  roadmap-profile spec.
decision: |
  Resolve each feature's key once into a positional key table -- the
  decoration-stripped label, or `F<n>` when that label cannot serve as a
  validator key -- and thread that table into both the key column and the shared
  Dependencies renderer. Decide usability with a predicate exported from the
  validator crate that tests the label against the validator's own
  normalizations. Sanitize and bound the description derivation inside the one
  helper both modes already share, and emit the author-facing diagnostics from
  separate pure functions the run paths print.
rationale: |
  Keying on the label is what the shared spec has always specified, and the
  issue-creating renderer already proves the validator accepts it. Resolving into
  a table rather than at each call site makes the key column and the dependency
  cells agree structurally instead of by two code paths converging, and the table
  parameter is what keeps issue-creating mode's output byte-identical while the
  issueless one changes. Usability has to be tested with the validator's own
  normalizers rather than a character list, because a label containing `~~`,
  `#12`, or `](` passes any list a reader would write and still produces an
  error-level finding on the tool's own output.
---

# DESIGN: Roadmap issueless table rendering

## Status

Current

## Context and Problem Statement

`crates/shirabe/src/populate.rs` renders both reserved sections of a roadmap. In
issueless mode (`--no-issues`) it fills the Implementation Issues table from the
Features section with no GitHub calls, and the reserved sections carry a "do not
fill manually" marker, so its output is the only thing a reader of that roadmap
sees.

Three defects in that output are in scope, all in the same two renderers.

The key column carries `format!("F{}", f.id)` (`populate.rs:197`). In issueless
mode the `Issues` column carries a `needs-*` label or `None` rather than an issue
link, so nothing in the two leading columns names the feature. The shared spec at
`references/issues-table.md` specifies the roadmap profile's key as the feature
label; `populate --help` and `skills/roadmap/references/roadmap-format.md` both
document `F<n>`.

The description cell comes from `concise_description` (`populate.rs:766`), which
prefers the text after `**Functional outcome:**` and otherwise returns
`first_sentence`. `first_sentence` returns the entire input when it finds no
`.`, `!`, or `?` followed by whitespace, so a body opening with a bullet list or a
semicolon-chained paragraph puts its whole opening block in one cell. There is no
ceiling anywhere in the path.

A feature with no prose body renders `| __ | | | |`. The validator's
`is_italic_cell` (`crates/shirabe-validate/src/table.rs:444`) rejects a cell
starting `__` as bold, so FC05 reports the entity row as missing its description
row — an error-level finding on a document the tool itself wrote. Reproduced
against a two-feature fixture: two FC05 errors, exit 2.

The PRD settles the product-level questions (label keys win; descriptions are
bounded at render and the author is told; no new validator check). What is left
to decide is where the rules live in a module whose renderers are pure functions
shared between two modes.

## Decision Drivers

- **D1 — The two columns must agree by construction.** R5 requires every
  Dependencies token to name the key its own row renders. A rule that can be
  computed two ways will eventually be computed two ways, and the disagreement is
  invisible until a roadmap has a duplicate or comma-bearing label — at which
  point it is an error-level FC06 failure.
- **D2 — Issue-creating mode's output stays byte-identical.** R24 freezes that
  mode's key column and Dependencies-cell resolution. The shared code path has to
  make that a structural property, not something a reviewer verifies by reading.
- **D3 — The validator is the arbiter, and it is not being changed.** Every
  decision here is constrained by what FC05, FC06, FC07, and FC08 already accept
  (R22, and D5 in the PRD).
- **D4 — Label text is not transformed.** The module's existing security
  invariant is that labels round-trip verbatim into the table and reach `gh` as
  argv rather than through a shell (R23). Escaping or rewriting label characters
  is off the table; falling back is not.
- **D5 — The renderers stay pure.** They are `pub fn ... -> String` with unit
  tests calling them directly. Diagnostics must not turn them into IO.
- **D6 — The diff should be about the reported defect.** Churn in tests and
  signatures that have nothing to do with the three defects makes the change
  harder to review for what it actually does.

## Considered Options

Three decision questions were walked. The full alternatives and the reasoning
are recorded per question; the summaries below carry the shape.

### Decision A — Where the key-resolution rule lives

- **A1: Resolve at each call site.** The key column computes its own key; the
  Dependencies renderer computes each referenced feature's key. Rejected: R2's
  uniqueness clause makes resolution a function of the whole feature list, so
  both sites would build the same duplicate-label index and any drift between the
  copies emits a dependency naming a key no row carries. Against D1.
- **A2: Resolve once into a positional key table and thread it through.**
  `feature_keys(features) -> Vec<String>` is the only place R2's predicate is
  expressed; the key column indexes it and `render_deps_cell` takes it as a
  parameter. **Chosen.** Agreement between the columns becomes structural, and the
  parameter is also what satisfies D2 — issue-creating mode passes the key table
  it already computes.
- **A3: Store the key on the `Feature` struct during parsing.** Rejected:
  `Feature` lives in `shirabe-validate` and is consumed by the validator; a
  rendering rule belonging to one mode of one subcommand does not belong in a
  type another crate shares.

### Decision B — How the diagnostics are produced

- **B1: `eprintln!` inside the renderers.** Rejected against D5: it makes the
  renderers impure, has eight existing unit tests writing to stderr, and leaves
  the diagnostics testable only through the CLI.
- **B2: Renderers return `(String, Vec<String>)`.** Rejected against D6: it
  churns two public signatures and every test calling them, buying nothing over
  B3, because the warnings are derivable from `&[Feature]` alone.
- **B3: Separate pure warnings functions the run paths print.** **Chosen.** Pure,
  directly unit-testable for content and ordering, renderer signatures untouched.
  R18's ordering falls out of iterating features in order. The cost is that the
  description derivation runs twice per feature, which is not worth avoiding at
  this scale.

  The jury caught that a single `render_warnings(features)` would be wrong: the
  fallback diagnostic must fire only where the fallback is applied, and under R24
  issue-creating mode never applies it. Splitting into `truncation_warnings` and
  `key_fallback_warnings` is what lets each run path print exactly what it did.
  The middle option not walked here is an `&mut Vec<String>` out-parameter on the
  renderers, which beats B2 on churn and B3 on the double derivation; it was not
  reached because it reintroduces B2's signature change on the two functions with
  the most existing tests.

### Decision C — Whether issue-creating mode adopts the fallback

- **C1: Extend the fallback to both modes.** The bug is identical and the fix is
  already written; it would change that mode's output only for labels that are
  empty, duplicated, or delimiter-bearing. Rejected on scope, not merit: the PRD
  is Accepted with R24 saying the opposite, and Decision A2 means no shared code
  path forces the change.
- **C2: Issueless only, with the seam left open.** **Chosen.** `render_table`
  builds its key table from `strip_label_decoration` and gets byte-identical
  output; extending the rule later is a one-line change at one call site.
- **C3: Issueless only, with a duplicated dependency renderer.** Rejected: same
  scope discipline as C2 at the price of a second copy of the `Feature N`
  resolution, cross-repo passthrough, and `None` fallback — three behaviours the
  PRD constrains identically in both modes.

### Decision D — What makes a label unusable as a key

- **D-1: A character blacklist.** Fall back when the label is empty, contains
  `,` or `|`, or duplicates another label byte-for-byte. This was the first
  draft. Rejected: it is not the equality the validator applies.
  `extract_entity_key` (`table.rs:414`) strips strikethrough, then lets an
  `ISSUE_REF_PATTERN` match anywhere in the cell *replace* the whole key with
  `#N`, then unwraps `[label](target)` via `normalize_feature_ref`;
  `extract_deps` (`table.rs:373`) applies a different combination to the
  dependency token. So a delivered feature labelled `a~~b` renders the key
  `| ~~a~~b~~ |`, which `strip_strikethrough` collapses to `ab` while the
  dependency token stays `a~~b` — an FC06 error on the tool's own output. Labels
  containing `#12` collapse two distinct features to one key with no duplicate
  detected. The blacklist would have shipped the exact failure the fallback
  exists to prevent.
- **D-2: Re-implement the validator's normalization in `populate.rs`.**
  Rejected: two implementations of one equality is the hazard D1 names, and this
  one drifts silently — the renderer would keep passing its own tests while the
  validator's normalization moved underneath it.
- **D-3: Export a predicate from `shirabe-validate` and call it (chosen).** A
  small `pub fn is_stable_table_key(label: &str) -> bool` lives beside the
  normalizers it uses, in `crates/shirabe-validate/src/table.rs`, and answers one
  question: does this text survive both normalizations unchanged, bare and
  strikethrough-wrapped? **Chosen.** It is the validator's own code, so it cannot
  drift, and it is a predicate rather than a check — D5's "no new validator
  check" holds, since nothing new fires during `shirabe validate`.

### Decision E — What to do about a description that breaks its own row

The empty-body defect turned out to be the degenerate case of a general rule.
`is_italic_cell` rejects any cell opening `__`, so a body opening
`__init__ parsing is deferred.` fails FC05 identically; a `|` anywhere in the body
splits the row so the trailing cells are not empty and the row classifies as an
entity row; and truncating at 197 characters can cut a `~~` span in half, creating
malformed markup the full text did not have.

- **E-1: Placeholder for the empty case only.** Rejected once the general case
  was understood: it fixes one input and leaves three.
- **E-2: Fall back to the placeholder whenever the derived text is unusable.**
  Rejected: it throws away a perfectly good summary because of one character.
- **E-3: Sanitize the derived text, then bound it (chosen).** Drop control
  characters, replace `|`, remove `~`, strip leading `_`, and fall back to the
  placeholder only when nothing is left. **Chosen.** Sanitizing before bounding
  means truncation cannot reintroduce a problem, because the characters that
  could be cut in half are gone before the cut.

This transforms author prose, which R23 forbids for *label* text. The asymmetry
is deliberate and R23 was amended to say so: a label has a usable fallback
(`F<n>`) and a description does not, so the label is preserved-or-replaced while
the description is repaired.

## Decision Outcome

Ship a key table, a bounded and sanitized shared derivation, and two pure
warnings functions in `crates/shirabe/src/populate.rs`, plus one exported
predicate in `crates/shirabe-validate/src/table.rs`.

1. `is_stable_table_key(label)` is added to `shirabe-validate` beside the
   normalizers it calls. No validation check changes.
2. `feature_keys(features)` resolves every feature's key once, applying R2's
   predicate against the whole list.
3. `render_deps_cell` takes the key table as a parameter and resolves a
   `Feature N` reference by position lookup, never by index. `render_table`
   passes the plain stripped labels (today's behaviour);
   `render_issueless_table` passes the resolved keys.
4. `summarize_description(desc) -> (String, bool)` is the single description
   derivation: prefer, sanitize, bound. Both renderers consume its text;
   `truncation_warnings` consumes its flag.
5. `truncation_warnings(features)` and `key_fallback_warnings(features)` are
   separate. Both run paths print the first; only `run_issueless` prints the
   second, because only it applies the fallback.
6. The `--no-issues` help text, three passages in
   `skills/roadmap/references/roadmap-format.md`, one passage in
   `skills/roadmap/SKILL.md`, and the module's own doc comments are corrected to
   match `references/issues-table.md`, which needs no change.

## Solution Architecture

### Components

All changes are in one file plus its two test surfaces.

| Component | Location | Change |
|-----------|----------|--------|
| `is_stable_table_key` | `shirabe-validate/src/table.rs` | New `pub fn`. Answers whether a text survives `extract_entity_key` and `extract_deps` unchanged, bare and strikethrough-wrapped. Re-exported from the crate root. |
| `feature_keys` | `populate.rs` | New. `&[Feature] -> Vec<String>`, positionally aligned. Applies R2. |
| `key_fallback_reason` | `populate.rs` | New. `&[Feature], usize -> Option<String>`, the single expression of R2's predicate, consumed by both `feature_keys` and `key_fallback_warnings`. |
| `summarize_description` | `populate.rs` | New. Wraps the existing `**Functional outcome:**` preference and `first_sentence` fallback, then applies R14 sanitization and R12-R13 bounding. Returns `(String, bool)`. |
| `concise_description` | `populate.rs:766` | Becomes `summarize_description(desc).0`. |
| `render_deps_cell` | `populate.rs:831` | Gains a `keys: &[String]` parameter; resolves each `Feature N` id by `features.iter().position(...)` then `keys.get(i)`, never by arithmetic index. |
| `render_issueless_table` | `populate.rs:187` | Key column reads the key table; Dependencies cell calls `render_deps_cell` with it. `bare_feature_deps` is removed, and its unit test with it. |
| `render_table` | `populate.rs:556` | Passes a plain-label key table. No other change. |
| `truncation_warnings` | `populate.rs` | New. `&[Feature] -> Vec<String>`. |
| `key_fallback_warnings` | `populate.rs` | New. `&[Feature] -> Vec<String>`. Issueless callers only. |
| `diagnostic_label` | `populate.rs` | New. Bounds and control-strips author label text before it reaches stderr (R17a). |
| `run_issueless` | `populate.rs:153` | Prints both warning sets to stderr before the summary JSON. |
| `run_inner` | `populate.rs:94` | Prints the truncation warnings only. |
| `PopulateArgs::no_issues` doc comment | `populate.rs:73` | Rewritten; it is the `--help` text (R20). |
| Module and function doc comments | `populate.rs:147`, `:176`, `:278`, `:821` | Rewritten where they assert the `F<n>` key rule or call `render_deps_cell` issue-creating-only. |

### Data flow

```
parse_features(doc) -> Vec<Feature>
        |
        +--> feature_keys(&features) -> Vec<String>        (issueless only)
        |          |
        |          +--> key column cell
        |          +--> render_deps_cell(deps, features, keys)
        |
        +--> summarize_description(&f.description) -> (text, truncated)
        |          |
        |          +--> description row cell
        |
        +--> render_warnings(&features) -> Vec<String> --> stderr
```

`render_table` enters the same `render_deps_cell` with
`features.iter().map(|f| strip_label_decoration(&f.label)).collect()`, which is
the value it computes inline today, so its output is unchanged by construction.

### The usability predicate

```
is_stable_table_key(text) -> bool          [shirabe-validate]
  t = text.trim()
  t is non-empty
  and t contains no ',' and no '|'         (delimiters, split before normalizing)
  and t contains no control character
  and extract_entity_key(t) == t
  and extract_entity_key("~~" + t + "~~") == t
  and extract_deps(t) == [t]

key_fallback_reason(features, i) -> Option<String>          [populate]
  key = strip_label_decoration(&features[i].label)
  if !is_stable_table_key(&key)      -> Some("label cannot serve as a table key")
  if another feature's stripped key equals key
                                     -> Some("label is shared with another feature")
  if key equals any feature's "F<n>" form
                                     -> Some("label collides with a fallback key")
  else                               -> None
```

`feature_keys` maps `None` to the stripped label and `Some(_)` to
`format!("F{}", features[i].id)`. `key_fallback_warnings` maps `Some(reason)` to
a diagnostic line. One predicate, two consumers, so the fallback and the warning
can never disagree about whether a row fell back.

The fixpoint form is what makes the guarantee real. The validator does not
compare label text; it compares `extract_entity_key`'s output for a key cell
against `extract_deps`'s output for a dependency token, and the two apply
different normalizations. A label is only safe to use as a key when both
normalizations are the identity on it — which is exactly what the predicate
tests, using the validator's own functions so the two cannot drift. The
strikethrough-wrapped variant is tested because a delivered feature's key cell is
wrapped before `extract_entity_key` sees it, while the dependency token naming it
is not.

The third clause closes a collision the first two miss: a feature literally
labelled `F2` alongside a feature whose label is unusable would otherwise produce
two rows keyed `F2`.

### FC07 does not participate

Worth stating because R19 and R3 look like they could collide.
`node_set_pass_roadmap`, `edge_pass_roadmap`, and `class_vs_status_pass` all
filter on `ISSUE_KEYED_NODE_ID` (`^I[0-9]+$`) on the diagram side and on `#N`
tokens in the Issues column on the table side. Issueless output has neither, so
all three passes are empty over it. Keeping `F<n>` node ids while changing the
table's key column cannot produce an FC07 finding, in either direction.

### The description bound

```
summarize_description(desc) -> (String, bool)
  text = desc.trim()
  body = text after "**functional outcome:**" (case-insensitive) if present, else text
  sentence = first_sentence(body); if empty, fall back to text

  sanitize:                                             (R14)
    drop control characters
    replace '|' with '/'
    remove '~'
    trim, then trim leading '_'
  if the sanitized text is empty
      -> ("No description in the feature body.", false) (R14a)

  bound:                                                (R12, R13)
    if chars().count() <= 200 -> (text, false)
    head = first 197 chars, cut back to the last whitespace when one exists
    (head + "...", true)
```

Sanitizing before bounding is the order that matters. The characters that make a
truncated cell malformed — an unbalanced `~~`, a `|` that splits the row — are
gone before the cut happens, so the cut cannot create a problem the full text did
not have. Trimming a leading `_` is what keeps a body opening `__init__` from
rendering `| ___init___ ... |`, which `is_italic_cell` classifies as bold and
FC05 then reports as a missing description row: the same failure the empty-body
case produces, from a different input.

Counting is `chars().count()`, matching the precedent `truncate_label` already
sets, so a multi-byte character is never split. The marker sits inside the
200-character budget, which makes R12 a single assertion on the rendered cell
rather than a rule with an exception.

The placeholder is returned with `false` for truncation: nothing was cut, so no
diagnostic fires. The row it produces,
`| _No description in the feature body._ | | | |`, satisfies `is_italic_cell`
and clears the FC05 finding reproduced above.

### Diagnostic shape

```
warning: feature 2 "Resolver cache": description truncated at 200 characters; add a "**Functional outcome:**" line to control the summary
warning: feature 4 "Establish, then act": key falls back to F4 (label cannot serve as a table key)
```

The feature is named by its heading label so the author can find it by searching
their own document, and by its 1-based number so the reference survives a label
they are about to change. `warning:` matches the existing convention in this
crate (`main.rs:466`). Lines are emitted in feature order, truncation and
fallback interleaved per feature, so the output is deterministic across runs.

The label reaches stderr through `diagnostic_label`, which drops control
characters and bounds the text the way `truncate_label` already bounds a diagram
node label (R17a). A label cannot contain a `\n` — `parse_features` works over
lines the frontmatter reader has already split — but an interior `\r` survives
parsing and would return the cursor to column zero and overwrite the warning, and
an `ESC[` run would reach the terminal directly. Length is otherwise unbounded: a
document with CR-only line endings parses as a single line, so the label absorbs
the rest of the file. None of this leaks anything the author cannot already see,
but a diagnostic that can rewrite its own output is not a diagnostic.

Only `run_issueless` prints the fallback warnings. Issue-creating mode keeps
plain stripped labels under R24, so a fallback line there would tell the author
the tool did something it did not do — on the one mode where the resulting row
genuinely can break FC06. Both modes print the truncation warnings, because both
share the bounded derivation.

## Implementation Approach

Four steps, each independently testable, in an order where the suite stays green
throughout.

**Step 1 — The description derivation.** Add `summarize_description` with R14's
sanitization and R12-R13's bound, and reduce `concise_description` to its first
element. Cover the boundary cases: exactly 200, 201, a single over-long word, an
empty body, a `**Functional outcome:**` line, a bullet-list body, a body opening
`__init__`, a body containing `|`, and a delivered feature whose body contains a
lone `~~`. This alone closes the description defect and the empty-body defect in
both modes and touches no signature. Checked against every existing assertion: no
current test feeds a body long enough to truncate or asserts
`concise_description("")`, so the suite stays green.

**Step 2 — The stability predicate.** Add `is_stable_table_key` to
`shirabe-validate/src/table.rs`, re-export it from the crate root, and unit-test
it there against the shapes that motivated it: a bare label, a delivered label
containing `~~`, a label containing `#12`, a `[label](target)` form, a comma, a
pipe, and a control character. Nothing consumes it yet, so the suite stays green.

**Step 3 — The key table.** Add `key_fallback_reason` and `feature_keys`, give
`render_deps_cell` its `keys` parameter with a `position`-then-`get` lookup,
switch `render_issueless_table` to the resolved table, and delete
`bare_feature_deps`. Five existing unit tests move here:
`render_issueless_table_is_feature_keyed_with_bare_deps`,
`render_issueless_table_no_needs_label_renders_none_issue_cell`, the two
issueless `run_*` tests that assert `| F1 | ... |` rows,
`render_deps_cell_maps_features_to_row_keys_and_keeps_cross_repo` (which needs
the new third argument), and `bare_feature_deps_strips_to_keys_or_none` (which
goes with the function it tests). Add coverage for each fallback trigger, for the
`F<n>`-collides-with-a-literal-label case, and for `Feature 0` and `Feature 99`
resolving to no token rather than panicking. `render_table` gains its plain-label
table and its own tests should not move — that they do not is the check that R24
held.

**Step 4 — The diagnostics.** Add `diagnostic_label`, `truncation_warnings`, and
`key_fallback_warnings`; print both from `run_issueless` and the truncation set
from `run_inner`. Assert the lines at the CLI level with `assert_cmd`, which is
where stderr is naturally observable, including the case that issue-creating mode
emits no fallback line for a roadmap whose labels would trigger one. The three
existing `.stderr(contains(...))` assertions in the CLI tests are substring
predicates on error paths, so added warning lines do not disturb them.

**Step 5 — The documentation.** Rewrite the `no_issues` doc comment (R20); the
three passages in `skills/roadmap/references/roadmap-format.md` that present
`F<n>` as the *table row* key (the Reserved Sections bullet, the FC16 paragraph,
and the "Dependencies cells in issueless mode" section — the fourth `F<n>`
mention is about diagram nodes and correctly stays); the issueless paragraph in
`skills/roadmap/SKILL.md`; and the module's own doc comments that assert the old
rule (`run_issueless`, `render_issueless_table`, `bare_feature_deps`'s successor
text, and `render_deps_cell`'s heading, which calls itself issue-creating-mode
and stops being true once both modes call it). `references/issues-table.md`
already specifies the target behaviour and is not edited.

**Step 6 — Security regression.** Add the metacharacter round-trip fixture under
`--no-issues`. The existing `HIJACKED` test covers issue-creating mode only, and
label text reaching the key column is new in the issueless path.

Test placement follows the existing split: derivation and rendering in the
`#[cfg(test)]` module in `populate.rs`, end-to-end behaviour and stderr in
`crates/shirabe/tests/populate_cli.rs`. The two existing round-trip tests that
feed the renderer's own output through the validator
(`run_issueless_render_validates_clean`, `populated_output_passes_validate`) are
the regression net for R22 and are extended with the fallback fixtures.

## Security Considerations

The populate module states two security invariants in its header comment, and
this change is assessed against both.

**Argument passing.** `gh` arguments go through `Command::arg`, which reaches the
OS as a `posix_spawn` argv array — no shell, no string templating. Nothing in this
change adds a subprocess invocation or moves label text closer to one. The
issueless path constructs no `Command` at all, and the changed functions are pure
string builders.

**Verbatim label round-trip.** Labels containing shell metacharacters must reach
the issue title and the rendered table unmodified. The chosen design preserves
this: the key is either the label with decoration stripped, which is the existing
transform, or `F<n>`. No escaping, quoting, or character rewriting is introduced.
The existing test asserting that
`Safe; rm -rf /tmp/foo && echo HIJACKED` round-trips is unchanged and still
covers the path.

**What the fallback does to the invariant.** R2 makes the rendered key depend on
label content, which is author-controlled. The dependence is a choice between two
fixed forms, not a transformation, and the `F<n>` form is derived from the
feature's position rather than its text. Label text reaching the issueless key
column *is* a new path in that mode; what it is not is a new *class* of exposure,
since issue-creating mode already renders labels in the same column of the same
table.

**Totality over arbitrary input.** The module's parsers are documented as total
over arbitrary line input, and the rendering path has to hold the same line.
`feature_refs_in` extracts any integer following the word `Feature`, straight
from an author-written `**Dependencies:**` line, so `Feature 0` and a stale
`Feature 12` on a three-feature roadmap both reach the resolver. An earlier draft
of this design resolved them by indexing the key table at `id - 1`, which
underflows on `Feature 0` and runs off the end on a stale reference. In
issue-creating mode that panic would land *after* `gh issue create` has run
(`run_inner` creates at `populate.rs:124` and renders at `:127`), leaving the
operator with created issues, no document write, and a stack trace. The design now
specifies `position`-then-`get`, preserving today's total behaviour of dropping an
unknown id.

**Self-invalidating output.** The sharper risk in this change is not privilege
escalation but the tool writing a document its own validator rejects, from input a
pull request can supply. Three inputs do that today or would under a naive fix: a
label whose normalized key differs from the dependency token naming it (`~~`,
`#<digits>`, `](`), a description opening `_`, and a `|` in a body. Decision D
closes the first by testing the label against the validator's own normalizers
rather than a character list; Decision E closes the other two by sanitizing the
derived description. The remaining case is a `|` in a *label*, which falls back
rather than being escaped.

**Diagnostics as an output channel.** The warnings interpolate author-controlled
label text into stderr. A label cannot contain a newline, but an interior `\r`, a
tab, and C0 controls including `ESC` all survive parsing, and a document with
CR-only line endings makes the label absorb the rest of the file. That is log
forging and terminal escape injection rather than disclosure — the content is
in-repo text the author is already looking at — but it is why R17a bounds and
control-strips the label before it is printed.

**Denial of service.** The 200-character ceiling removes an unbounded copy of
author text into a table cell. `feature_keys` adds an O(n²) duplicate scan over
feature labels; on a roadmap of 21 features that is 441 string comparisons, and
the roadmap format has no realistic scale where this matters. Both are
improvements or neutral.

**CLI-argument surface, examined and unchanged.** `--milestone` is interpolated
verbatim into the reserved section body and `--repo` into the rendered issue-link
URL, neither validated; a milestone containing a `## ` line would corrupt the
section structure the next `replace_section` depends on. Separately,
`atomic_write` creates its temp sibling with `fs::File::create` on a
pid-and-clock-derived name, which follows symlinks and does not use `O_EXCL`, so
in a directory an attacker can write to the atomic write can be redirected. Both
are operator-supplied surfaces that predate this change and neither is touched by
it; they are named here so the "no new surface" verdict is a statement about what
was examined rather than about what was noticed.

**Verdict: no new security surface, one hazard removed.** No new subprocess, no
new file write, no new network call. The verbatim label invariant holds at the
string level; the totality contract is preserved explicitly rather than by
accident; and the change closes three ways the tool could emit a document that
fails its own validation.

## Consequences

### Positive

- A row of an issueless Implementation Issues table names its feature, which is
  what the shared spec has specified all along.
- No cell the tool writes exceeds 200 characters, in either mode.
- A roadmap with a feature that has no prose body stops failing the tool's own
  validator, and so do the three other body and label shapes that produced the
  same failure from different inputs.
- **Cross-repo dependencies survive issueless population.** `bare_feature_deps`
  deliberately collapsed `tsukumogami/koto#65` to `None`; its replacement
  preserves the token verbatim. That is R6 compliance and the right outcome, but
  it is a user-visible change to every issueless roadmap carrying a cross-repo
  dependency, and it is a gain rather than a fix to something reported.
- The four documents describing the table agree.
- An author learns at populate time when a summary was cut or a label could not
  serve as a key, and what to do about it.

### Negative

- **Dependencies cells get longer.** A feature with three dependencies now
  repeats three labels rather than `F1, F2, F3`. On a roadmap with long labels the
  cell is visibly wide. This is the shape the spec asks for and the issue-creating
  mode already has.
- **A truncated cell is a lossy fragment.** For a body with no early sentence
  terminator, the cell is the first 197 characters of that body rather than a
  written summary. The diagnostic names the remedy; the tool cannot write prose
  the author did not.
- **Issue-creating mode keeps the same edge-case exposures.** A comma, a pipe, a
  duplicate, or an empty label in that mode still produces a key that can break
  the row or the FC06 reconciliation. This is deliberate under R24 and Decision
  C2. The one-line extension is `render_table`'s key-table argument: swapping
  `strip_label_decoration` for `feature_keys` adopts the rule wholesale.
- **The description derivation runs twice per feature**, once for the cell and
  once for the warning. Negligible at this scale, and the alternative was
  threading state out of a pure renderer.
- **Description text is repaired, not preserved.** Sanitization removes `~`,
  rewrites `|`, and strips a leading `_` from author prose. The transformation is
  invisible in the document — there is no marker saying a character was changed —
  and the only signal is that the cell reads slightly differently from the body.
  Accepted because the alternative is a row the validator rejects.
- **`F<n>` names nothing on a strategy-derived roadmap.** Those roadmaps head
  their features `### ED1:`, `### SE2:`, and so on; `parse_features` numbers them
  positionally, so a fallback key of `F4` refers to a numbering scheme that
  appears nowhere in the document. Cosmetic, and only reachable on a roadmap that
  already has an unusable label, but the `F<n>` form is being kept as "the handle
  that survives" and on those roadmaps it is a handle to nothing.
- **`shirabe-validate` gains public surface.** `is_stable_table_key` is a new
  exported function on a crate whose API is otherwise consumed only by the binary
  crate and the tests. It is small and it lives beside the code it wraps, but it
  is a commitment.

### Mitigations

- The two existing render-then-validate round-trip tests are the guard against
  the renderer drifting out of agreement with FC05/FC06/FC07/FC08; the fallback
  fixtures are added to them rather than to a separate test that could pass while
  the round trip fails.
- `key_fallback_reason` being the single source for both the fallback and the
  warning means a roadmap can never fall back silently or warn about a row that
  did not.
- Existing issueless unit tests encode `F<n>` keys and will fail loudly on step
  2, which is the intended signal that the behaviour changed rather than a
  surprise.
