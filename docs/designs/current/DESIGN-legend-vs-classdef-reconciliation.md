---
schema: design/v1
status: Current
problem: |
  shirabe-validate reconciles plans and roadmaps along the FC07 intra-document
  axis (table-vs-diagram) and the FC09 cross-document axis (doc-vs-GitHub) but
  does not inspect the Legend prose line that sits below most Dependency
  Graph blocks. FC07 deliberately bounded its contract to the four parallel
  views the diagram extractor produces; the Legend is prose outside the
  mermaid fence and the FC07 sub-DESIGN named explicitly that prose-vs-
  diagram reconciliation belongs to a separate follow-on check. The PRD
  scopes FC08 as that follow-on, behind the same notice-then-error rollout
  FC07 and FC09 use. This design settles the implementation gates the PRD
  deferred: the Legend extractor call site, the exact notice-message
  strings, the table-driven test layout, and the pipeline-stage class set's
  exact membership.
decision: |
  FC08 lands as one new check function `check_fc08` in
  `crates/shirabe-validate/src/checks.rs` alongside `check_fc07` and
  `check_fc09`, plus a small Legend-prose extractor `extract_legend` placed
  inline in `checks.rs` rather than in `mermaid.rs`. The extractor scans
  body lines following the located Dependency Graph fence and parses the
  first matching `Legend:` or `**Legend**:` line into a `Vec<String>` of
  class names. `check_fc08` runs the three sub-checks (Legend-names-no-
  classDef, classDef-omitted-from-Legend, normalization-mismatch) in one
  pass over the parsed table location, the existing `Diagram.class_defs`
  field FC07 produces, and the extracted Legend names. The check joins the
  existing `is_notice` membership; the promotion seam is the one-line
  addition of `FC08` to the `matches!` arm. The canonical-palette tolerance
  hard-codes the Status set (`done`, `ready`, `blocked`) as the universally
  assumed default and the pipeline-stage set as the names that genuinely
  need Legend entries.
rationale: |
  Placing the Legend extractor in `checks.rs` (not `mermaid.rs`) keeps
  `mermaid.rs` bounded to the diagram-fence-content extraction it already
  owns; the Legend is prose between body lines, not part of the mermaid
  fence, so the extractor's natural home is next to its only consumer. The
  three-sub-check shape composes with the existing FC07 dispatch pattern
  (one check function per FC code, per-defect notices in the FC05/FC06/
  FC07/FC09 voice). Joining the existing `is_notice` membership preserves
  the one-seam-one-mechanism promotion path FC07 and FC09 ride. The
  canonical-palette tolerance prevents notice spam on the Status classes
  every diagram inherits while keeping the pipeline-stage classes inside
  the reconciliation surface where they belong (a `needsExplore` node a
  Legend forgets is exactly the case a reader needs the validator to
  catch). The kebab-to-camel normalization is one-directional toward the
  codebase canonical form, recommending the substitution the corpus
  already uses for `class` and `classDef` statements.
upstream: docs/prds/PRD-legend-vs-classdef-reconciliation.md
---

# DESIGN: legend-vs-classdef-reconciliation

## Status

Current

## Context and Problem Statement

The `shirabe-validate` crate dispatches its content checks in the `Plan`
and `Roadmap` arms of `validate_file`. The arms today run, in order: the
schema gate, the visibility gate, FC01 through FC04, then the format-
specific checks (`check_plan_upstream` on plans only, then `check_fc05`,
`check_fc06`, `check_fc07`, and `check_fc09`). FC08 is the queued
intra-document increment that sits between FC07 and FC09 in the
reconciliation taxonomy.

FC07 reconciles the intra-document table-and-diagram pair across four
parallel views the diagram extractor produces (`nodes`, `edges`,
`class_assignments`, `class_defs`). FC09 reconciles the doc against
external GitHub state. Neither inspects the Legend prose line that sits
below most Dependency Graph blocks and tells the reader what each color
in the diagram means. FC07's sub-DESIGN Decision 4 bounded the FC07
contract to the four parallel views the diagram extractor produces, and
named explicitly that prose-vs-diagram reconciliation belongs to a
separate follow-on check rather than smuggling into FC07.

The Legend convention is documented in `references/dependency-diagram.md`
near the end of the file. Authors are instructed to add a line of the
shape `**Legend**: Green = done, Blue = ready, Yellow = blocked, ...`
immediately following the diagram. Two concrete drift surfaces are
currently live in the committed corpus: the pipeline-stage class
proliferation that landed earlier in this milestone (`needsPlanning`,
`needsExplore`, `needsSpike` did not exist before, and Legends written
against the older spec silently fell out of agreement with diagrams
that use the newer classes), and the documented-convention
normalization mismatch where the canonical Legend example itself uses
hyphenated names (`needs-design`) against the codebase's universal
camelCase `classDef` form (`needsDesign`).

The PRD scopes the FC08 check that closes this gap. Its 16 numbered
requirements and 17 acceptance criteria fix the contract:

- One check, three sub-checks: Legend-names-no-classDef,
  classDef-omitted-from-Legend, normalization-mismatch.
- Bidirectional reconciliation in a single pass over the parsed table
  location, the existing `Diagram.class_defs` field, and the extracted
  Legend names.
- Kebab-to-camel normalization one-directional toward the codebase
  canonical form.
- Canonical-palette tolerance for the Status set (`done`, `ready`,
  `blocked`); pipeline-stage classes (`needsDesign`, `needsPrd`,
  `needsPlanning`, `needsSpike`, `needsDecision`, `needsExplore`,
  `tracksDesign`, `tracksPlan`) are inside the reconciliation surface.
- Notice-level shipping via the existing `is_notice` membership; a
  single-point promotion seam.
- Per-defect notice messages in the FC05/FC06/FC07/FC09 voice.
- Bounded behavior over arbitrary Legend input -- no panics on
  malformed prose, no unbounded loops, no allocations proportional to
  anything outside the diagram's own size.
- Absent-Legend produces no notice (the convention is optional).

The parent design `DESIGN-roadmap-plan-standardization.md` Decision 3
established the staging shape -- a notice-then-error rollout, no new
external dependency, the one-line `is_notice` promotion seam. The FC07
sub-DESIGN `DESIGN-table-diagram-reconciliation.md` is the
architectural precedent this design extends: its Decision 1 introduced
the `Diagram.class_defs: HashSet<String>` field FC08 consumes, and its
Decision 2 set the per-defect notice grouping FC08 follows. The FC09
sub-DESIGN `DESIGN-doc-vs-github-state-reconciliation.md` is the
precedent for joining the existing `is_notice` membership (its
Decision 6).

The implementation gaps left for this design are the four that the
PRD's Downstream Artifacts section names explicitly: the Legend
extractor call site (helper in `mermaid.rs` vs inline in `checks.rs`),
the exact notice message strings, the table-driven test layout, and
the pipeline-stage class set's exact membership.

## Decision Drivers

- **PRD requirements bind first.** The 16 requirements (R1-R16) and
  the 17 acceptance criteria fix the contract; every decision below
  must keep them satisfied.
- **The FC07 and FC09 sub-DESIGNs bind the precedent.** Per-defect
  notice voice (`[FCxx] <description>`), inline-string fixtures,
  `is_notice` membership-entry promotion seam, doc-comment binding
  for non-obvious conventions -- FC08 follows the precedent verbatim
  unless a PRD requirement forces a divergence.
- **No new dependency.** The parent DESIGN's no-new-dependency posture
  anchors the staged-reconciliation family; FC08 honors it by using
  only stdlib string operations and the existing `regex` dependency
  the workspace already pays for.
- **Total behavior over arbitrary Legend input (R15).** No panics on
  malformed prose, no unbounded loops, no unbounded recursion. The
  extractor parses what it can and silently drops the rest.
- **Single, locatable promotion seam.** The `is_notice` membership is
  the one place to flip; the FC08 PR adds the arm and the cleanup PR
  removes it.
- **Public-cleanliness of notice prose (R12).** Every notice body and
  every shared rule citing FC08 names only entities the doc itself
  already names (class names, the side that omits them, the
  normalized form to substitute).
- **Reuse FC07's class-extraction infrastructure.** No new field on
  the `Diagram` struct, no new view, no new extractor pass over the
  diagram fence content. The Legend extractor is the only net-new
  prose-parsing surface.

## Considered Options

This design settles four implementation questions. Each subsection
records the chosen approach, at least one rejected alternative with
its reason, and a citation back to the PRD requirement or the FC07/
FC09 sub-DESIGN precedent where the binding came from.

### Decision 1: Legend extractor call site -- inline in `checks.rs`

**Chosen.** The Legend extractor `extract_legend` is a small free
function placed in `crates/shirabe-validate/src/checks.rs` immediately
above `check_fc08`. Its signature is:

```rust
/// Extract the first Legend line's class names from body lines
/// following the located Dependency Graph fence.
///
/// Returns an empty Vec when no Legend line is found, when the line
/// is malformed beyond recovery, or when the recovered entries
/// contain no parseable class names. The extractor is total: it
/// never panics, never indexes by byte into a multi-byte UTF-8
/// boundary, and never loops unboundedly.
fn extract_legend(body: &[String], fence_end_line: usize) -> Vec<String>;
```

The function scans `body[fence_end_line..]` for the first line whose
content (after `trim()` and stripping optional `**` wrappers) begins
with `Legend:` (case-sensitive on the leading token). It parses the
text after the colon into comma-separated entries, splits each entry
on `=`, takes the right-hand side, trims, and collects into the
return Vec. Entries without `=`, with empty halves, or with
unparseable contents are silently dropped.

**Alternatives considered.**

- *Helper in `mermaid.rs` next to the diagram extractor.* Rejected.
  - `mermaid.rs` is documented in its module doc-comment as the
    diagram-fence-content extractor: "Extract the four-view
    [`Diagram`] from a slice of body lines (the lines BETWEEN the
    opening and closing fences)." The Legend lives OUTSIDE the
    fence, in the body, not inside the diagram block.
    Placing the Legend extractor in `mermaid.rs` would force the
    module to grow a new concept (post-fence body parsing) that
    conflicts with the module doc-comment and the existing
    extractor's contract.
  - The Legend extractor has exactly one consumer (`check_fc08`).
    Co-locating producer and consumer keeps the change diff small
    and gives the test surface (the `tests` module in `checks.rs`)
    direct access to both.
  - A future reader looking for the Legend extractor naturally looks
    next to its only call site, not in a module whose name suggests
    diagram-fence content.

- *Adding a `legend: Option<Vec<String>>` field on the `Diagram`
  struct, populated by an extended `extract_diagram`.* Rejected.
  - Forces a behavioral change on `extract_diagram` (it would need to
    receive body lines past the fence end, not just lines between
    fences). PRD R16 explicitly excludes new fields on the `Diagram`
    struct.
  - Couples the FC08 check's extraction surface to the FC07
    extractor's lifetime, complicating future independent evolution
    (e.g., the Legend extractor might want to recognize a second
    Legend shape that has no diagram-side counterpart).

**Citation.** PRD R5 (extraction location and shape), R16 (reuse of
FC07's infrastructure, no new field on `Diagram`). FC07 sub-DESIGN
Decision 1 (extractor view shape and ownership in `mermaid.rs`).

### Decision 2: Notice message strings and per-sub-check distinct forms

**Chosen.** The three sub-checks emit distinct notice forms so a
maintainer reading CI output can tell from the message which sub-
check fired. The strings below are the canonical wording; tests pin
them as exact-match assertions where the message is short, and as
substring assertions where the message includes a variable class
name.

- **Sub-check A (Legend-names-no-classDef).**

  ```
  [FC08] Legend names class `<name>` but no `classDef <name>` exists in the diagram and `<name>` is not in the canonical Status palette
  ```

- **Sub-check B (classDef-omitted-from-Legend).**

  ```
  [FC08] Diagram declares `classDef <name>` outside the canonical Status palette but the Legend does not name it
  ```

- **Sub-check C (normalization-mismatch).**

  ```
  [FC08] Legend names class `<kebab-form>` but the diagram declares `classDef <camel-form>`; use the camelCase form `<camel-form>` to match the codebase convention
  ```

Every notice begins with `[FC08]`, matching the prefix shape every
other FC code uses. Notices identify classes by their bare name
(backtick-quoted to mirror the existing FC05/FC06/FC07/FC09 voice),
do not include URLs, do not include external identifiers, and do not
quote any GitHub-API or env-var content.

**Alternatives considered.**

- *Grouped notice (one line per file naming all defects).* Rejected.
  - PRD R6 requires per-defect notice messages naming the specific
    class name. A grouped notice would name only the file path and a
    count, forcing the author to manually re-read the doc to find
    each defect. The FC05/FC06/FC07/FC09 voice is per-defect and
    FC08 follows that precedent.

- *A single Sub-check C notice naming all normalization mismatches
  in one line.* Rejected.
  - Same reasoning as above; per-mismatch is the canonical voice.

- *Surfacing the recommended substitution as a separate notice from
  the mismatch detection itself.* Rejected.
  - The substitution is the actionable signal; pairing the detection
    with the substitution in one notice keeps the fix path
    mechanical (R6).

**Citation.** PRD R6 (notice voice mirroring FC05/FC06/FC07/FC09),
R12 (public-cleanliness). FC07 sub-DESIGN Decision 2 (per-defect
over grouped). FC09 sub-DESIGN Decision 4 (per-defect notice
wording precedent).

### Decision 3: Table-driven test layout and canonical-palette / pipeline-stage hard-coding

**Chosen.** Tests live in `crates/shirabe-validate/src/checks.rs`'s
`tests` module alongside the existing `check_fc07_*` and
`check_fc09_*` test functions, following the AC-numbered
convention. Each AC from the PRD gets at least one dedicated test
function whose name matches `check_fc08_<scenario>` and whose body
constructs an inline-string doc via the existing `parse_doc`
helper, calls `check_fc08(&doc, &spec_for("plan/v1"))` or
`check_fc08(&doc, &spec_for("roadmap/v1"))`, and asserts on the
emitted notice set.

The canonical-palette and pipeline-stage class sets are hard-coded
as module-level `const` arrays inside `checks.rs`:

```rust
/// The canonical Status palette every diagram inherits. A
/// `classDef` declaring one of these does not require a Legend
/// entry; a Legend entry naming one of these does not require a
/// matching `classDef`. Tracks
/// `references/dependency-diagram.md` "Status Classes" section.
const FC08_STATUS_PALETTE: &[&str] = &["done", "ready", "blocked"];

/// The pipeline-stage and tracks-prefix class set. These names
/// MUST be Legend-named when declared in a diagram (Sub-check B
/// fires when omitted). They participate in the kebab-to-camel
/// normalization rule (Sub-check C). Tracks
/// `references/dependency-diagram.md` "Pipeline Stage Classes"
/// section.
const FC08_PIPELINE_STAGE_CLASSES: &[&str] = &[
    "needsDesign",
    "needsPrd",
    "needsPlanning",
    "needsSpike",
    "needsDecision",
    "needsExplore",
    "tracksDesign",
    "tracksPlan",
];
```

The pipeline-stage set is consulted by the normalization pass
(Sub-check C) to recognize the documented kebab-case forms
(`needs-design`, `tracks-design`) as variants of the camelCase
canonical forms. The Status palette is consulted by Sub-check A
and Sub-check B to apply the canonical-palette tolerance.

**Alternatives considered.**

- *Reading the palette from `references/dependency-diagram.md` at
  runtime.* Rejected.
  - Introduces a runtime file read for what is effectively
    compile-time data. The reference file is committed alongside
    the validator; changes to the palette would update both files
    in the same PR.
  - Forces the validator binary to ship with embedded reference
    docs or to assume a working-directory layout; both shapes
    expand FC08's contract beyond the PRD scope.

- *Reusing a `STATUS_CLASSES` constant from FC07 if one exists.*
  Considered but no such constant is currently exposed. FC07
  hard-codes its Status class set inline in `class_vs_status_pass`;
  exposing a shared constant is a refactor outside FC08's scope.
  The Known Limitation in the PRD flags this; a future increment
  can deduplicate.

- *Generating the test cases from a data table at compile time
  (proc macro).* Rejected.
  - Proc macros add a build-dependency. The hand-written test set
    is at the size where readability outweighs deduplication; each
    AC has 1-2 dedicated test functions and the total is
    approximately 12-15 tests.

**Citation.** PRD R9 (pipeline-stage class set), R13 (determinism),
R14 (no new dependency). FC07 sub-DESIGN Decision 4 (inline-string
fixtures with pinned cases).

### Decision 4: `is_notice` extension wording and promotion seam

**Chosen.** The `is_notice` function in
`crates/shirabe-validate/src/validate.rs` is extended to a four-arm
match:

```rust
pub fn is_notice(err: &ValidationError) -> bool {
    matches!(err.code.as_str(), "SCHEMA" | "FC07" | "FC08" | "FC09")
}
```

The accompanying doc-comment is updated to name FC08 alongside FC07
and FC09 in the notice-level membership and to re-state the
promotion-to-error seam. The test
`is_notice_only_schema_fc07_fc09` is renamed to
`is_notice_only_schema_fc07_fc08_fc09` and its body extended with
an FC08 case.

The promotion seam is the one-line removal of `| "FC08"` from the
`matches!` expression, in a follow-up cleanup PR once the corpus
notice volume drops to zero.

**Alternatives considered.**

- *A new severity field on `ValidationError`.* Rejected.
  - Forks the staging mechanism. FC07 and FC09 already use the
    `is_notice` membership; a new mechanism for FC08 alone would
    inconsistently fragment the validator's per-check severity
    contract. The FC09 sub-DESIGN's Decision 6 settled this for
    the family.

- *A per-check `severity()` method on a hypothetical `Check` trait.*
  Rejected.
  - The validator's check functions are free functions, not
    instances of a trait. Adding a trait surface for severity alone
    is a larger refactor outside FC08's scope.

**Citation.** PRD R10 (notice-level shipping via existing
`is_notice`), R11 (promotion-to-error seam). FC09 sub-DESIGN
Decision 6 (`is_notice` extension wording precedent).

## Decision Outcome

The four decisions above bind FC08's implementation to:

- One new check function `check_fc08` in
  `crates/shirabe-validate/src/checks.rs` next to `check_fc07` and
  `check_fc09`.
- One small helper `extract_legend` in `checks.rs` immediately above
  `check_fc08`.
- Two new module-level `const` arrays (`FC08_STATUS_PALETTE`,
  `FC08_PIPELINE_STAGE_CLASSES`) in `checks.rs`.
- A one-line dispatch extension in each of the `"Plan"` and
  `"Roadmap"` arms of `validate_file` to invoke `check_fc08`
  alongside `check_fc07` and `check_fc09`.
- A one-line extension to the `is_notice` match expression in
  `validate.rs` adding `"FC08"`.
- Approximately 12-15 table-driven tests in `checks.rs`'s `tests`
  module, each AC-numbered with a comment naming the AC it covers.

No new module is added. No field is added to the `Diagram` struct.
No new external dependency is introduced. The diff stays under
~500 lines of Rust including tests.

## Solution Architecture

### Module Layout

```
crates/shirabe-validate/src/
├── checks.rs              # +FC08_STATUS_PALETTE, +FC08_PIPELINE_STAGE_CLASSES,
│                          # +extract_legend (helper), +check_fc08 (check fn),
│                          # +check_fc08_* tests in tests module
├── validate.rs            # is_notice extended to include "FC08"
├── mermaid.rs             # unchanged
├── doc.rs                 # unchanged
├── formats.rs             # unchanged
├── gh.rs                  # unchanged
└── lib.rs                 # unchanged (no new pub mod)
```

### `check_fc08` Signature and Flow

```rust
/// FC08 -- Legend-vs-classDef reconciliation.
///
/// Reconciles the Dependency Graph Legend prose line against the
/// diagram's `classDef` declarations and the canonical class palette.
/// Three sub-checks in one pass:
///
/// - **Sub A (Legend-names-no-classDef).** Each Legend class name
///   must correspond to a local `classDef` declaration OR be in the
///   canonical Status palette. A name satisfying neither fires.
/// - **Sub B (classDef-omitted-from-Legend).** Each `classDef`
///   declaration outside the canonical Status palette must be named
///   by the Legend (modulo kebab-to-camel normalization). An omitted
///   classDef fires.
/// - **Sub C (normalization-mismatch).** A Legend entry that matches
///   a `classDef` only under normalization fires a notice
///   recommending the camelCase form.
///
/// Ships at notice level via the `is_notice` membership; promotion
/// to error is a one-line change.
pub fn check_fc08(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError> {
    // 1. Profile gate: only run on Plan and Roadmap formats.
    if spec.issues_table_columns.is_empty() {
        return Vec::new();
    }

    // 2. Locate the Dependency Graph block; absent block -> no notice.
    let location = match find_dependency_graph_block(doc) {
        Some(l) => l,
        None => return Vec::new(),
    };

    // 3. Extract the diagram class_defs (FC07 infrastructure).
    let body_start_idx = location.body_start.saturating_sub(1);
    let body_end_idx = location.body_end.saturating_sub(1).min(doc.body.len());
    let body_slice: Vec<&str> = doc.body[body_start_idx..body_end_idx]
        .iter().map(|s| s.as_str()).collect();
    let (diagram, _issues) = extract_diagram(&body_slice, location.body_start);

    // 4. Extract the Legend (the only net-new prose-parsing surface).
    let fence_end_line = location.body_end; // 1-based, points past the closing fence
    let legend_names = extract_legend(&doc.body, fence_end_line);

    // 5. Run the three sub-checks; concatenate notices.
    let mut errs = Vec::new();
    errs.extend(check_fc08_sub_a(&legend_names, &diagram.class_defs));
    errs.extend(check_fc08_sub_b(&legend_names, &diagram.class_defs));
    errs.extend(check_fc08_sub_c(&legend_names, &diagram.class_defs));
    errs
}
```

### `extract_legend` Implementation Sketch

```rust
fn extract_legend(body: &[String], fence_end_line: usize) -> Vec<String> {
    // body is the doc body lines (1-based fence_end_line); convert to 0-based.
    let start = fence_end_line.saturating_sub(1).min(body.len());
    for line in &body[start..] {
        let trimmed = line.trim();
        // Strip optional bold-markdown wrapper.
        let stripped = trimmed.strip_prefix("**").unwrap_or(trimmed);
        let stripped = stripped.strip_suffix("**").unwrap_or(stripped);
        let rest = match stripped.strip_prefix("Legend:") {
            Some(r) => r,
            None => {
                // Also accept `**Legend**:` (bold + colon outside the **).
                match trimmed.strip_prefix("**Legend**:") {
                    Some(r) => r,
                    None => continue,
                }
            }
        };
        // We found the first Legend line; parse entries.
        return parse_legend_entries(rest);
    }
    Vec::new()
}

fn parse_legend_entries(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    for entry in s.split(',') {
        let Some((_color, name)) = entry.split_once('=') else { continue };
        let name = name.trim();
        if name.is_empty() { continue; }
        // Drop trailing prose after a slash (e.g. "tracks-design/tracks-plan"
        // is two distinct names per the documented Legend convention).
        for part in name.split('/') {
            let part = part.trim();
            if !part.is_empty() {
                out.push(part.to_string());
            }
        }
    }
    out
}
```

### Kebab-to-Camel Normalization

```rust
fn normalize_kebab_to_camel(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut upper_next = false;
    for c in s.chars() {
        if c == '-' {
            upper_next = true;
        } else if upper_next {
            out.extend(c.to_uppercase());
            upper_next = false;
        } else {
            out.push(c);
        }
    }
    out
}
```

The function is total over arbitrary UTF-8 input. It does not unwrap,
does not index by byte, and does not allocate beyond the input length.

### Sub-check Implementations

```rust
fn check_fc08_sub_a(legend: &[String], class_defs: &HashSet<String>)
    -> Vec<ValidationError>
{
    let mut errs = Vec::new();
    let mut seen = HashSet::new();
    for name in legend {
        if !seen.insert(name.clone()) { continue; }   // dedupe
        let normalized = normalize_kebab_to_camel(name);
        let in_palette = FC08_STATUS_PALETTE.iter().any(|p| *p == name || *p == normalized);
        let in_classdefs = class_defs.contains(name) || class_defs.contains(&normalized);
        if !in_palette && !in_classdefs {
            errs.push(ValidationError {
                code: "FC08".into(),
                message: format!(
                    "Legend names class `{name}` but no `classDef {name}` exists \
                     in the diagram and `{name}` is not in the canonical Status palette"
                ),
                line: None,
            });
        }
    }
    errs
}

fn check_fc08_sub_b(legend: &[String], class_defs: &HashSet<String>)
    -> Vec<ValidationError>
{
    let legend_normalized: HashSet<String> = legend.iter()
        .map(|n| normalize_kebab_to_camel(n))
        .collect();
    let mut class_def_names: Vec<&String> = class_defs.iter().collect();
    class_def_names.sort();   // determinism (R13)
    let mut errs = Vec::new();
    for cd in class_def_names {
        if FC08_STATUS_PALETTE.iter().any(|p| *p == cd.as_str()) { continue; }
        if legend.iter().any(|n| n == cd) || legend_normalized.contains(cd) {
            continue;
        }
        errs.push(ValidationError {
            code: "FC08".into(),
            message: format!(
                "Diagram declares `classDef {cd}` outside the canonical Status \
                 palette but the Legend does not name it"
            ),
            line: None,
        });
    }
    errs
}

fn check_fc08_sub_c(legend: &[String], class_defs: &HashSet<String>)
    -> Vec<ValidationError>
{
    let mut errs = Vec::new();
    let mut seen = HashSet::new();
    for name in legend {
        if !seen.insert(name.clone()) { continue; }
        let normalized = normalize_kebab_to_camel(name);
        if normalized != *name && class_defs.contains(&normalized) {
            errs.push(ValidationError {
                code: "FC08".into(),
                message: format!(
                    "Legend names class `{name}` but the diagram declares \
                     `classDef {normalized}`; use the camelCase form `{normalized}` \
                     to match the codebase convention"
                ),
                line: None,
            });
        }
    }
    errs
}
```

### Dispatch Wiring

The `"Plan"` arm of `validate_file` extends to:

```rust
"Plan" => {
    errs.extend(check_plan_upstream(doc));
    errs.extend(check_fc05(doc, spec));
    errs.extend(check_fc06(doc, spec));
    errs.extend(check_fc07(doc, spec));
    errs.extend(check_fc08(doc, spec));   // <-- new
    let fc09_client = GhSubprocessClient::new();
    let fc09_ctx = detect_pr_context();
    errs.extend(check_fc09(doc, spec, &fc09_client, fc09_ctx.as_ref()));
}
```

The `"Roadmap"` arm extends identically (no `check_plan_upstream`
call; otherwise the same shape).

### Notice-Membership Site

```rust
pub fn is_notice(err: &ValidationError) -> bool {
    matches!(err.code.as_str(), "SCHEMA" | "FC07" | "FC08" | "FC09")
}
```

## Implementation Approach

The work decomposes into four implementation steps. Each is one PR-
sized step; the dependencies are linear and named. Since the PLAN
will ship in single-pr mode, the four steps land in one PR.

### Step 1: Add the constants, the extractor, and the normalization helper

Create `FC08_STATUS_PALETTE` and `FC08_PIPELINE_STAGE_CLASSES` as
module-level `const` arrays in `checks.rs`. Add `extract_legend`,
`parse_legend_entries`, and `normalize_kebab_to_camel` as free
functions. Unit-test:

- `extract_legend` with the documented Legend shapes (`Legend:`,
  `**Legend**:`, bold wrapper outside the colon, bold wrapper inside
  the colon).
- `extract_legend` with absent Legend (no matching line).
- `extract_legend` with malformed Legend (stray comma, entry without
  `=`, empty entry, leading/trailing whitespace, slash-separated
  composite entry like `tracks-design/tracks-plan`).
- `extract_legend` with multiple Legend lines (first one wins).
- `normalize_kebab_to_camel` on `needs-design`, `tracks-design`,
  `done` (no change), empty string (no change), `-leading-hyphen`
  (capitalizes first letter after the hyphen).

### Step 2: Add `check_fc08` and the three sub-check functions

Implement `check_fc08_sub_a`, `check_fc08_sub_b`, `check_fc08_sub_c`
inside `check_fc08`. Implement the profile gate, the diagram-block
locator (reusing `find_dependency_graph_block`), the class-defs
extraction (reusing `extract_diagram`), and the Legend extraction.
Unit-test each sub-check against the PRD's 17 acceptance criteria:

- Sub A fires on a Legend entry naming a class outside the
  classDef set and outside the canonical palette.
- Sub A does not fire on canonical-palette names regardless of
  local classDef declarations.
- Sub B fires on a classDef declaration outside the canonical
  palette that the Legend omits.
- Sub B does not fire on canonical-palette classDef declarations.
- Sub B respects normalization (a Legend entry `needs-design` does
  not cause a Sub B fire for `classDef needsDesign`).
- Sub C fires on a Legend entry matching a classDef only under
  normalization.
- Absent Legend produces no notice.
- Absent diagram block produces no notice.
- Malformed Legend does not panic.
- Duplicate Legend entries are deduplicated.
- Multiple defects in one doc produce multiple notices, in
  deterministic order.

### Step 3: Wire `check_fc08` into `validate_file`

Extend the `"Plan"` and `"Roadmap"` arms of `validate_file` to
invoke `check_fc08`. Add integration-style tests that construct a
full plan doc and a full roadmap doc each with one FC08 defect and
assert the notice is emitted alongside the other expected notices.

### Step 4: Extend `is_notice` to include FC08

Update `is_notice` in `validate.rs` to the four-arm match. Rename
`is_notice_only_schema_fc07_fc09` to
`is_notice_only_schema_fc07_fc08_fc09` and extend its body. Update
the doc-comment to mention FC08.

The four steps are sequential because Step 2 calls the extractor
Step 1 lands, Step 3 calls the check function Step 2 lands, and
Step 4 is the membership wiring that turns the check into a
notice rather than an error. A single PR carrying all four steps
is the default shape (single-pr PLAN execution mode).

## Security Considerations

The FC08 check and its extractor are total over arbitrary line
input. The extractor scans body lines after the located fence
boundary and parses each candidate line in constant time per
character. There are no nested loops over input, no unbounded
recursion, and no allocations proportional to anything outside the
diagram's own size.

### Defensive parsing of the Legend prose

Each Legend line goes through three string operations:

- `trim()` -- total on arbitrary UTF-8 input.
- `strip_prefix` / `strip_suffix` -- total; returns `None` on no-
  match rather than panicking.
- `split(',').split_once('=')` -- total; produces an iterator that
  may be empty.

The slash-split for composite entries (`tracks-design/tracks-plan`)
uses `str::split('/')`, which is total. Empty parts are filtered
out before pushing to the result Vec.

The kebab-to-camel normalization iterates over `chars()` (total
over UTF-8) and uses `to_uppercase()` (also total). The output
String is pre-allocated to the input length so it never grows
beyond the input's character count. No `unwrap()`, no byte
indexing past a UTF-8 boundary.

### Bounded extraction surface

The extractor reads at most all body lines from `fence_end_line`
to the end of the body. The body is already fully materialized in
memory by the doc parser; FC08's extraction is a linear scan over
already-bounded input. The "first Legend line wins" rule short-
circuits the scan as soon as a Legend line is found.

### Notice-string public-cleanliness

The three notice strings (Sub A, Sub B, Sub C) interpolate only
two kinds of content: bare class names parsed from the diagram or
the Legend, and the kebab-to-camel normalized form derived from
those names. Neither path quotes any GitHub-API content, any env-
var value, any file path, or any external identifier. The PRD R12
public-cleanliness scan reviews the strings against the same
criterion FC07 and FC09 already pass.

A malicious or accidental Legend entry containing backtick
characters, newlines, or other markdown-active characters does
not break the notice output. The notice format strings use
`{name}` interpolation; if a name contains a backtick, the output
contains the backtick verbatim. CI annotation surfaces (GHA
`::notice` annotations) render the notice as plain text in their
output panel, not as rendered markdown, so the backtick contents
do not execute any side effect.

## Consequences

### Positive

- The third drift surface FC07 deliberately left untouched closes
  via a small, additive check that reuses FC07's class-extraction
  infrastructure.
- The one-line `is_notice` promotion seam continues the FC07/FC09
  pattern; a future maintainer flips one arm to promote FC08 to
  error after corpus reconciliation.
- The notice volume is bounded by design: the canonical-palette
  tolerance keeps the Status set from generating notices on every
  doc, while the pipeline-stage set is precisely the set a reader
  needs the validator to catch.
- No new external dependency, no new module, no new field on the
  `Diagram` struct. The diff stays small and reviewable.

### Negative

- A four-arm `is_notice` match (`SCHEMA | FC07 | FC08 | FC09`) is
  approaching the size where a more general severity mechanism
  would be cleaner. The current shape stays readable at five arms;
  if the next check needs to join, the maintainer should consider
  a general mechanism before adding the fifth arm.
- The kebab-to-camel normalization is hard-coded to the codebase
  canonical form. A future convention change that allows kebab-
  case in `classDef` declarations would require revisiting the
  normalization direction. The PRD's known-limitation note flags
  this; the cost of extending the normalization is small.
- The "first Legend wins" rule silently accepts a doc with
  multiple Legend lines. A future enhancement could fire a notice
  on multiple Legends; this design ships the simple rule.

### Neutral

- The pipeline-stage class set is hard-coded in `checks.rs` rather
  than referenced from a shared constant. FC07 also hard-codes its
  Status class set inline; deduplicating to a shared constant is a
  separate refactor outside FC08's scope.

## References

- Parent PRD (R8 staged reconciliation, R20 notice-then-error,
  R22 public-cleanliness):
  `docs/prds/PRD-roadmap-plan-standardization.md`.
- Parent DESIGN (Decision 3 staging the reconciliation increment
  behind a notice rollout):
  `docs/designs/DESIGN-roadmap-plan-standardization.md`.
- Parent PLAN (the row that schedules this increment):
  `docs/plans/PLAN-roadmap-plan-standardization.md`.
- PRD that this DESIGN picks up:
  `docs/prds/PRD-legend-vs-classdef-reconciliation.md`.
- BRIEF that the PRD picks up:
  `docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md`.
- FC07 sub-DESIGN (the architectural precedent for the
  `class_defs: HashSet<String>` field FC08 consumes, the dispatch
  arm FC08 slots into, and the inline-string fixture test
  convention): `docs/designs/current/DESIGN-table-diagram-reconciliation.md`.
- FC09 sub-DESIGN (the `is_notice` extension wording precedent and
  the four-arm match expression FC08 extends):
  `docs/designs/current/DESIGN-doc-vs-github-state-reconciliation.md`.
- Canonical dependency-diagram conventions (the Legend convention,
  the canonical Status palette, the pipeline-stage class set, the
  documented hyphenated-vs-camelCase mismatch in the example
  Legend): `references/dependency-diagram.md`.
