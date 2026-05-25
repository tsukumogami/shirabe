---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-roadmap-plan-standardization.md
problem: |
  The roadmap and plan workflows share an issues table, a dependency
  diagram, a lifecycle vocabulary, and one validator, but none of that is
  defined once: the table has several drifting schemas across the skill
  references and committed corpus, the diagram spec lives inside one plan
  reference and is unenforced, the validator checks only section presence
  (no Markdown-table or mermaid tokenizer exists in internal/validate), the
  single-pr/multi-pr rule is buried in a lazily loaded plan phase file, the
  roadmap fills its table by re-driving the plan workflow through in-prose
  string surgery, and the lifecycle terminal is three-way contradictory with
  no CI enforcement. This design fixes the implementation shape of all six.
decision: |
  Introduce a shared references directory both skills consume (a principles
  reference, one issues-table framework with a plan and a roadmap profile,
  and the promoted diagram convention), extend internal/validate with one
  new Markdown-table parser feeding two error-level content checks (schema
  conformance, cross-reference existence) plus a deferred mermaid-reconcile
  check staged behind a spike and shipped notice-then-error, surface and
  re-anchor the single-pr/multi-pr decision with a value-confirmation guard,
  add a scripted roadmap-to-issues path mirroring the plan's, and enforce a
  single verify-then-delete lifecycle via a new whole-tree-scan CI surface
  running alongside the existing changed-files validator.
rationale: |
  Most machinery already exists; the work is naming shared parts as shared
  and defining each once. The validator's pure-function check architecture,
  the SCHEMA notice-then-error precedent, and the existing git-shelling
  presence check (checkPlanUpstream) all extend cleanly, so the first
  content pass adds exactly one parser and reuses the existing CLI and
  reusable workflow. Staging reconciliation behind a mermaid-parser spike
  honors strictness-tracks-blast-radius: the two cheap checks land strict
  while the corpus-wide one lands as a notice first. A separate whole-tree
  scan is required because presence-without-touch is invisible to the
  existing changed-files diff.
---

# DESIGN: roadmap-plan-standardization

## Status

Planned

## Context and Problem Statement

shirabe's `/roadmap` and `/plan` skills sit at opposite ends of the tactical
chain yet share four things at the implementation level: an issues table, a
mermaid dependency diagram, a lifecycle vocabulary (`Draft`/`Active`/`Done`),
and one Go validator (`internal/validate/`). None of these shared concerns is
defined in a single place, and the drift that follows is the technical problem
this design solves. The work is meta: the artifacts being modified are
shirabe's own skill references, its Go validator package, the skill scripts,
and the reusable CI workflows in this repo.

Six concrete gaps, each grounded in current code:

- **The issues table has no single definition.** The plan profile is specified
  in `skills/plan/references/quality/plan-doc-structure.md` as `Issue |
  Dependencies | Complexity` with a still-accepted legacy `Issue | Title |
  Dependencies | Complexity` variant; the roadmap reserves `Feature | Issues |
  Status` in `skills/roadmap/references/roadmap-format.md`; and committed docs
  carry further divergences. There is no shared reference and no parser that
  can read a table to check it.

- **The diagram spec is buried and unenforced.** A complete mermaid spec
  (syntax rules, a fixed status-class palette, a legend) lives only inside the
  plan's `plan-doc-structure.md`. The roadmap reserves an empty `mermaid`
  block with no spec reference. Nothing checks a committed diagram against the
  palette or legend.

- **Validation stops at section presence.** `internal/validate/` parses a doc
  into a `Doc` IR (`Fields`, `Sections`, `Body`) and runs pure-function checks
  (FC01-FC04, the format-specific R6/R7/R8 checks) dispatched by `spec.Name` in
  `ValidateFile`. No function tokenizes a Markdown table or a fenced `mermaid`
  block. A malformed table, a dangling dependency link, or a table-diagram
  disagreement all pass as long as the headings exist.

- **The single-pr/multi-pr decision is buried and mechanism-driven.** The rule
  lives in `skills/plan/references/phases/phase-3-decomposition.md` (step 3.6),
  loaded lazily, never on the skill surface. Its "Roadmap input forces
  multi-pr" row reaches the right outcome by mechanism, not by the usable-value
  principle, and nothing confirms each unit delivers standalone value.

- **The roadmap fills its table by string surgery.** The roadmap writes empty
  reserved placeholders; the only fill path is the plan workflow's roadmap mode
  (`input_type: roadmap`), which rewrites placeholders in prose. The plan
  populates its own table with scripts (`plan-to-tasks.sh`,
  `create-issues-batch.sh`); the roadmap has no equivalent native path.

- **The lifecycle terminal is contradictory and unenforced.** `plan-doc-
  structure.md` says move a Done plan to `docs/plans/done/`; the live work-on
  cascade deletes it; a completed roadmap is kept forever (roadmap-format.md:
  "Done -> any: Forbidden... a historical record"). No CI check holds a doc to
  the state its mode requires, and the existing `validate-docs.yml` runs only
  on the changed-files diff (`git diff --name-only base...head`), which cannot
  observe a doc the PR does not touch.

The PRD settles five decisions (the five-principle set, the staged validation
split, the smallest table split, the whole-tree-scan/ephemeral-Done lifecycle,
and record-and-proceed for both `--auto` gates). This design operationalizes
them: it does not relitigate them. The downstream questions it must answer are
the implementation shapes the PRD explicitly deferred -- the shared-reference
file layout, the validation check codes and parser design, the
roadmap-to-issues script interface, the mermaid-parser spike framing, the CI
whole-tree-scan surface, and the final principle wording.

## Decision Drivers

- **Reuse over rebuild (R19).** The first content pass must extend the existing
  `internal/validate/` package, run through the existing `shirabe validate`
  CLI and the existing reusable workflow, and add exactly one new parser (the
  shared Markdown table parser). No second binary, no parallel pipeline.

- **Strictness tracks blast radius (R1.5, R8, R20).** Schema conformance and
  cross-reference (small, localized retrofit cost, no new parser beyond the
  shared table parser) land at error-level on day one. Table-diagram
  reconciliation (needs a mermaid parser, corpus-wide retrofit) is staged into
  a later increment behind a spike and ships as a notice before promotion to
  error -- mirroring the existing SCHEMA notice gate.

- **Define each shared concern once (R1.4, R2-R5).** The issues table, the
  dependency diagram, and the principle set each get one source of truth both
  skills consume, replacing per-skill restatement.

- **Presence-without-touch must be observable (R17, R18).** The two lifecycle
  checks need whole-tree visibility the changed-files diff cannot provide, so
  they require a distinct CI surface that scans the checked-out tree.

- **`--auto` must never deadlock (R12, R14).** Both human-judgment gates
  (value confirmation, issue-creation approval) record a decision block and
  proceed under `--auto`, surfacing high-priority assumed blocks rather than
  blocking on a human who is not present.

- **Public-repo cleanliness (R22).** Every shared reference, surfaced rule, and
  validation message must be free of private repo names, paths, filenames,
  issue numbers, and pre-announcement features.

- **Altitude distinction must survive (R2-R4).** The shared table framework
  carries two profiles (feature-keyed roadmap, issue-keyed plan) rather than
  collapsing the altitude difference.

- **Migration is in scope, not a permanent dual format (R3, R4).** The legacy
  separate-`Title` plan table and the divergent committed roadmap shapes are
  migrated into the canonical profiles, not accepted forever.

## Considered Options

The PRD settled five decisions (the principle-set membership, the validation
staging seam, the table split, the lifecycle shape, and the `--auto` gate
behavior). This design decomposed the deferred implementation shape into six
independent questions, each evaluated against the current code. The PRD's
settled positions are inputs here, not options to relitigate.

### Decision 1: Where shared references live and how the skills consume them

Today the issues-table spec and the dependency-diagram spec are trapped inside
`skills/plan/references/quality/plan-doc-structure.md`, and the roadmap's table
stub lives in `skills/roadmap/references/roadmap-format.md`. Nothing is shared.
The PRD's principle "one canonical format per concern, defined once" (R1.4)
requires a single home both skills consume. The plugin already hosts cross-skill
references at its root (`references/decision-protocol.md`,
`references/cross-repo-references.md`), loaded via `${CLAUDE_PLUGIN_ROOT}`. The
Go validator does not read these references at runtime -- it hardcodes the
format contract in `internal/validate/formats.go` -- so the references are
authoring guidance and the validator is their enforcement twin.

Key assumptions: the references and `formats.go` are kept in sync by the author
(edited together), mirroring the existing split where `formats.go` encodes what
the prose describes.

#### Chosen: Plugin-root shared references, consumed via `${CLAUDE_PLUGIN_ROOT}`

Add three shared references at the plugin root: `workflow-principles.md` (the
five named principles, R1), `issues-table.md` (the one table framework -- shared
core, shared rendering, the plan and roadmap profiles, plus the migration rules),
and `dependency-diagram.md` (the diagram convention promoted verbatim out of
`plan-doc-structure.md`). Both skills point at them with `${CLAUDE_PLUGIN_ROOT}`,
the mechanism already used for the decision protocol. `plan-doc-structure.md` and
`roadmap-format.md` shrink to their profile-specific deltas and lifecycle
content. This reuses a proven loader with no new machinery and gives a future
sibling doc type one place to consume the same conventions.

#### Alternatives Considered

**One skill owns, the other cross-references**: keep the spec in the plan
references and have the roadmap link into it. Rejected because it re-encodes the
"trapped in one skill" anti-pattern the PRD names as the root cause, and makes
the roadmap depend on a plan-internal path.

**Duplicate the content into each skill**: Rejected outright -- duplication is
the exact drift source being removed, violating define-once (R1.4).

### Decision 2: The Markdown-table parser and the two content checks

`internal/validate/` parses a doc into a `Doc` IR (`Fields`, `Sections`,
`Body []string`) and runs pure-function checks dispatched by `spec.Name` in
`ValidateFile`. No function tokenizes a table. R6 (schema conformance) and R7
(cross-reference existence) both need to read the issues table, and R19 caps the
first pass at exactly one new parser. The corpus shows the shapes the parser
must read and reject: plan `Issue | Dependencies | Complexity` (and a legacy
`Issue | Title | ...`), roadmap `Feature | Issues | Status`, and divergences
`Feature | Status | Downstream Artifact` and `Issue | Phase | Dependencies |
Label`. Cells carry markdown links, `None`, comma-separated links, and
`~~strikethrough~~`.

Key assumptions: tables use GFM pipe syntax with a `---` separator (true across
the corpus); profile is selected by doc schema, not by inspecting the header, so
a roadmap carrying a plan-shaped table fails the schema check (the intended
migration signal).

#### Chosen: One tokenizer in `table.go` feeding `checkFC05` (schema) and `checkFC06` (cross-reference)

A new `parseIssuesTable(doc Doc)` locates the table under the Implementation
Issues section using `Doc.Sections` line bounds and `Doc.Body`, parses the
header into columns, and classifies each body row as entity, description
(`| _..._ | | |`), or child (`| ^_..._ | ... |`), stripping `~~..~~` before
classification so a done row parses like an open one. `checkFC05` selects the
profile from the doc's format, compares the header against the profile's
required columns and order, and checks row well-formedness; `checkFC06` builds
the set of entity-row keys and verifies every Dependencies value resolves to a
row in the same table. Both are error-level, dispatch in the `Plan` and a new
`Roadmap` arm of the `ValidateFile` switch, and name the specific defect in
their messages. The legacy `Title`-column plan table is recognized as a
migration input the message points the author to migrate, not a permanent
accepted form. This adds one file, two checks, two dispatch arms -- no IR or CLI
change -- and the `Table` it produces is the foundation the later
reconciliation check reuses.

#### Alternatives Considered

**Two independent parsers, one per check**: Rejected -- R6 and R7 read the same
table; two parsers duplicate tokenization and cut against R19's one-parser
constraint.

**Regex-only checks with no table model**: Rejected -- R7 needs the set of row
keys, a structured property; per-line regex cannot build that set cleanly and is
brittle against link syntax.

### Decision 3: The mermaid-parser spike and the staged reconciliation check

Table-diagram reconciliation (R8) is the one content check needing a mermaid
node/edge parser, and its retrofit blast radius is the whole committed-diagram
corpus (which carries ad-hoc classDefs and reworded legends). The PRD stages it
behind a feasibility spike (R9) and requires notice-then-error rollout. shirabe
has a spike artifact type, and `checkSchema`/`IsNotice` is a working
notice-then-error precedent. The corpus uses a narrow mermaid subset:
`graph LR`/`TD`, quoted node labels, `-->` edges, `subgraph`, `classDef`, and
`class` directives -- far smaller than full mermaid.

Key assumptions: a line-oriented extractor over the corpus subset suffices (the
spike confirms before R8 is detailed); notice-level R8 is wired by adding its
code to the notice set in `IsNotice` initially.

#### Chosen: A named spike precedes R8; R8 is a later increment, notice-then-error, reusing the table parser

A spike artifact (under `docs/spikes/`) investigates the three things R9 names:
the exact `graph` subset the docs use, how to extract nodes and edges without a
full grammar (a line-oriented extractor, no external dependency), and the
reconciliation strictness (exact node-set equality versus subset, to allow
external cross-repo nodes). R8 then lands as `checkFC07` in a later increment,
adding `mermaid.go` and consuming both the existing parsed `Table` and the
extracted diagram. It ships as a notice (via `IsNotice`, like `SCHEMA`) so an
unreconciled committed diagram does not redden CI, then is promoted to
error-level once the corpus is reconciled -- a one-line change to the notice
membership. This keeps R8 off the first pass's critical path and honors
strictness-tracks-blast-radius (R1.5) and no-day-one-breakage (R20).

#### Alternatives Considered

**Skip the spike, write R8 against a guessed subset**: Rejected -- the PRD makes
the spike an explicit upstream and an acceptance criterion, and skipping it risks
a grammar mismatch.

**Pull in a full mermaid grammar or external parser**: Rejected -- over-built for
the narrow subset, and it adds a Go dependency to a package that has none beyond
stdlib and yaml. The spike exists precisely to avoid a full grammar.

### Decision 4: The roadmap-to-issues scripted path interface

The plan populates its own table with scripts (a manifest plus
`create-issues-batch.sh`, which is manifest-driven and skill-agnostic). The
roadmap has no script -- its only fill path is the plan workflow's
`input_type: roadmap` mode, which rewrites reserved placeholders in prose. R13
wants a path native to the roadmap, not a re-drive of the plan workflow. The
roadmap already ships `transition-status.sh`, so it has a scripts directory and
a JSON-output convention.

Key assumptions: the roadmap's Features section is machine-readable enough (the
per-feature format with `Needs`/`Dependencies`) to build a manifest;
`create-issues-batch.sh` stays generic.

#### Chosen: A roadmap-owned populate script reusing the generic create-issues primitive, writing reserved sections by section replacement

Add `skills/roadmap/scripts/populate-issues-table.sh`. It reads the Features
section, builds a per-feature planning-issue manifest in the shape
`create-issues-batch.sh` already consumes, calls that shared primitive to create
the issues and obtain an id-to-url mapping, then renders the feature-keyed table
(with the Issues fan-out column populated) and the dependency diagram and writes
them into the reserved sections by replacing each section's body between its
headings -- a structural replacement, not the fragile placeholder string match
the plan re-entry used. Issue creation is the gated step (R14): in interactive
mode the skill stops for approval before invoking it; under `--auto` it records
an assumed approval block at high review priority, then proceeds. The gate lives
in the skill phase that invokes the script, so the scripted path does not bypass
it. `create-issues-batch.sh` may optionally be relocated to a shared scripts
location so both skills cite one copy.

#### Alternatives Considered

**Keep the plan re-entry but make it script-driven instead of prose**: Rejected
-- R13 explicitly wants the path native to the roadmap; even a script-driven
re-entry still drives the plan workflow against the roadmap document.

### Decision 5: The CI surface for the lifecycle checks and the verify-then-delete wiring

The existing `validate-docs.yml` runs `shirabe validate` on the changed-files
diff (`git diff --name-only base...head`), which cannot see a doc the PR does not
touch -- so it provably cannot enforce presence-without-touch, the core of both
lifecycle checks (the PRD's Decision 4 settles this). The validator already
shells out to git (`checkPlanUpstream` runs `git ls-files`) and already parses
frontmatter `status` and `execution_mode`, so a whole-tree status read fits the
existing CLI.

Key assumptions: roadmaps and plans live under a known doc tree the scan walks,
selected by filename prefix via `DetectFormat`; `execution_mode` is present in
plan frontmatter (a required field), so the multi-pr/single-pr split is reliable;
`L01`/`L02` are new error-level codes.

#### Chosen: A new whole-tree `--lifecycle` validator mode, run by a separate CI job alongside the unchanged changed-files validator

The validator gains a `--lifecycle <root>` mode that walks the doc tree, selects
roadmap and plan docs, and runs two stateless checks on the parsed `Doc` IR:
Check A (`L01`) fails any roadmap or `multi-pr` plan present with a status other
than `Active` (a present Draft fails; a present Done fails, the forcing function
for deletion), and Check B (`L02`) fails while any `single-pr` plan exists in the
tree and passes once it is gone. A new reusable workflow plus a self-caller runs
this mode on every PR with no `paths:` filter, as a separate job from the
content validator (which keeps running diff-scoped and unchanged). The
verify-then-delete terminal (R15) lands atomically in the work-completing PR: the
skill transitions Active to Done via `transition-status.sh`, the author verifies,
and the same PR deletes the doc. CI never deletes -- Check A failing on a present
Done is what makes the deletion non-optional (R18). The stale
move-to-`docs/plans/done/` wording is removed.

#### Alternatives Considered

**Extend `validate-docs.yml` to also scan the whole tree**: Rejected -- it
conflates two concerns with different trigger semantics. The content validator is
correctly diff-scoped and `paths:`-filtered; the lifecycle gate must run on every
PR regardless of what changed. Bundling forces one to inherit the other's wrong
trigger.

**A bash/grep-only CI step with no Go**: Rejected -- frontmatter status and
`execution_mode` parsing already live in `ParseDoc`; re-implementing YAML
frontmatter parsing in shell duplicates logic and drifts from the validator.

### Decision 6: Surfacing the single-pr/multi-pr decision and the value guard

The single-pr/multi-pr rule lives in
`skills/plan/references/phases/phase-3-decomposition.md` (step 3.6), loaded
lazily, never on the SKILL surface, tangled with the separate
decomposition-strategy decision, and its multi-pr trigger table includes
"Roadmap input" as a mechanism row. R10 wants it surfaced, anchored on usable
value, and de-conflated; R11 wants a guard that can fail; R12 wants `--auto`
record-and-proceed. The decision protocol already defines confirmed / assumed /
escalated record-and-proceed.

Key assumptions: the plan `SKILL.md` is the right always-loaded surface; "high
review priority" is expressed via the assumed block and its appearance in the
terminal summary and PR body, with no new priority field.

#### Chosen: Lift the rule onto the SKILL surface anchored on usable value; add a separate value-confirmation step that records-and-proceeds under `--auto`

The plan `SKILL.md` gains a short always-loaded statement of the default (one PR)
and its named escape conditions (a hard constraint, or each PR independently
useful), citing the usable-value principle in `workflow-principles.md`. The
decomposition-strategy decision is named as separate and stays in the phase file.
The roadmap's always-multi-pr outcome is re-anchored on value (each feature is a
cohesive deliverable), not on the mechanism "the input is a roadmap." A
value-confirmation step checks each unit -- every feature for a roadmap, each
value-driven PR for a plan -- and can fail, naming the mis-decomposed unit and
why. Under `--auto` it writes a decision block: `confirmed` for a clear
standalone-value unit, `assumed` at high review priority for a failing or
ambiguous unit (both route to the same recorded outcome on purpose), surfaced in
the terminal summary and PR body. This is the same record-and-proceed shape the
issue-creation approval gate uses, so the two `--auto` gates stay symmetric.

#### Alternatives Considered

**Keep the rule in the phase file but add a pointer from the surface**: Rejected
-- a pointer is not surfacing; a "see phase 3" link reproduces the
buried-reference problem R10 fixes.

**Make the guard hard-fail even under `--auto`**: Rejected by the PRD's
Decision 5 -- a hard stop breaks `--auto`'s non-interactive contract.

## Decision Outcome

**Chosen: 1A + 2A + 3A + 4A + 5A + 6A** (the chosen option of each decision
above), forming one coherent standardization.

### Summary

The work splits cleanly into three tracks that share one foundation. The
foundation is a set of three plugin-root shared references --
`workflow-principles.md`, `issues-table.md`, `dependency-diagram.md` -- that both
the plan and roadmap skills consume via `${CLAUDE_PLUGIN_ROOT}`, with
`plan-doc-structure.md` and `roadmap-format.md` trimmed to point at them and keep
only their profile deltas and lifecycle content. The five named principles get
their wording finalized here; each surfaced rule in the two skills cites the
principle it derives from.

The validation track extends `internal/validate/` with one new file,
`table.go`, exposing `parseIssuesTable` over the existing `Doc.Body`/`Doc.Sections`
IR. Two new error-level checks consume it: `checkFC05` (schema conformance --
header matches the doc's profile, rows well-formed) and `checkFC06`
(cross-reference -- every Dependencies value names a row that exists). Both
dispatch in the `Plan` and a new `Roadmap` arm of `ValidateFile` and run through
the existing CLI and the existing changed-files reusable workflow, so the first
pass adds no second binary and exactly one parser (R19). Table-diagram
reconciliation is deliberately not in this pass: it is staged behind a named
mermaid-parser spike, then lands later as `checkFC07` in a new `mermaid.go`,
reusing the parsed `Table` and shipping as a notice (via `IsNotice`, the SCHEMA
precedent) before promotion to error -- so the committed-diagram corpus can be
reconciled before reconciliation becomes blocking (R20).

The workflow track surfaces and re-anchors the single-pr/multi-pr decision on the
plan `SKILL.md`, de-conflated from the decomposition-strategy decision, with a
value-confirmation step that can fail and names the mis-decomposed unit. The
roadmap gains a native scripted path, `populate-issues-table.sh`, that builds a
per-feature manifest, reuses the generic `create-issues-batch.sh`, and writes the
reserved table and diagram sections by structural section replacement rather than
prose string surgery. The lifecycle track adds a whole-tree `--lifecycle`
validator mode -- Check A (`L01`, a present roadmap or multi-pr plan must be
Active; a present Done or Draft fails) and Check B (`L02`, a single-pr plan must
be absent) -- run by a new CI job on every PR with no `paths:` filter, alongside
the unchanged diff-scoped content validator. The verify-then-delete terminal
lands atomically in the work-completing PR (transition to Done, verify, delete in
one PR); CI demands the deletion by failing a present Done but never performs it.

Both `--auto` human-judgment gates -- the value-confirmation guard and the
issue-creation approval gate -- record a decision block (`confirmed` or `assumed`
at high review priority) and proceed, never deadlocking, surfacing the assumed
block in the terminal summary and PR body.

### Rationale

The decisions reinforce each other through two shared mechanisms. First, the
`Doc` IR and the pure-function check pattern carry the entire validation track:
`table.go` reads the same IR the lifecycle mode reads, and the reconciliation
increment reuses the `Table` the first pass already produces -- so the three
validation pieces compose rather than duplicate. Second, one record-and-proceed
gate pattern serves both `--auto` judgment points across the plan script, the
roadmap script, and the surfaced decision, so authors and the harness track one
behavior, not three.

The build order falls out of two couplings the cross-validation surfaced (and
the Implementation Approach phases): the reconciliation check depends on the
table parser existing, and on the spike; everything else in the first pass is
independent. Staging reconciliation last is the seam the PRD chose on
blast-radius grounds, and nothing in the first pass needs it. The main trade-off
accepted is the one the PRD already named: the whole-tree lifecycle scan reads
unchanged docs on every PR, so an unrelated PR can fail on a left-behind doc --
which is exactly how presence-without-touch becomes observable and how the
Done-must-delete forcing function works.

## Solution Architecture

### Overview

The standardization touches four surfaces in this repo: shared skill references
(authoring guidance), the Go validator (`internal/validate/`, enforcement), the
skill scripts (`skills/plan/scripts/`, `skills/roadmap/scripts/`), and the
reusable CI workflows (`.github/workflows/`). References describe the
conventions; the validator enforces the subset that is machine-checkable; the
scripts populate tables and create issues; CI runs the validator on PRs. The
references and the validator are kept in agreement by the author -- they are two
expressions of the same contract, not a runtime coupling.

### Components

- **Shared references (plugin root).**
  - `references/workflow-principles.md` -- the five named principles (R1), each a
    one-line statement plus the rule(s) it governs.
  - `references/issues-table.md` -- the one table framework: shared core (key
    column parameterized by profile, Dependencies, Status), shared rendering
    (italic description row, strikethrough-on-done across entity/description/child
    rows), the plan profile (`Issue` key, `[#N: <title>](url)` link form, the
    `Complexity` column, the `^_Child: ..._` row), the roadmap profile (`Feature`
    key, the `Issues` fan-out column), and the migration rules for the legacy
    `Title` plan form and the divergent committed roadmap shapes.
  - `references/dependency-diagram.md` -- the diagram convention moved out of
    `plan-doc-structure.md`: `graph` syntax rules, the fixed status-class
    palette, node format, and the legend.
  - The two skill references (`skills/plan/references/quality/plan-doc-structure.md`,
    `skills/roadmap/references/roadmap-format.md`) are trimmed to cite these and
    keep only profile deltas and lifecycle content.

- **Validator (`internal/validate/`).**
  - `table.go` (new): `parseIssuesTable(doc Doc) (Table, bool)` and the `Table`
    type (header columns, typed rows: entity / description / child). Reads
    `Doc.Body` within the Implementation Issues section bounds from
    `Doc.Sections`. Strips `~~..~~` before classifying.
  - `checks.go` (extended): `checkFC05` (R6 schema conformance) and `checkFC06`
    (R7 cross-reference existence), both pure functions returning
    `[]ValidationError`, both error-level.
  - `validate.go` (extended): a new `Roadmap` arm in the `ValidateFile` switch
    that runs FC05/FC06; the existing `Plan` arm gains FC05/FC06 alongside
    `checkPlanUpstream`.
  - `mermaid.go` (new, later increment): the line-oriented node/edge extractor
    and `checkFC07` (R8 reconciliation), shaped by the spike.
  - A whole-tree `--lifecycle` mode (CLI flag in `cmd/shirabe/main.go` plus a
    tree walk) running Check A (`L01`) and Check B (`L02`) against the parsed IR.

- **Scripts.**
  - `skills/roadmap/scripts/populate-issues-table.sh` (new): Features -> manifest
    -> `create-issues-batch.sh` -> rendered table + diagram written by section
    replacement.
  - `create-issues-batch.sh` (existing, treated as shared; optional relocation).
  - `transition-status.sh` (existing for roadmap; drives the roadmap's
    Active->Done step). The plan's Active->Done step is wired through the
    work-completion cascade rather than a standalone plan script -- the precise
    per-doc transition mechanics are the plan's to settle, but both modes land
    the transition, verification, and deletion atomically in the
    work-completing PR.

- **CI (`.github/workflows/`).**
  - `validate-docs.yml` (unchanged): diff-scoped content/frontmatter validation.
  - A new reusable lifecycle workflow plus a self-caller: runs `shirabe validate
    --lifecycle` on the checked-out tree on every PR, no `paths:` filter.

### Key Interfaces

- **`parseIssuesTable(doc Doc) (Table, bool)`** -- returns the parsed table and
  whether one was found under the Implementation Issues section. `Table` carries
  `Columns []string` and `Rows []Row`, where `Row` has a kind
  (entity/description/child), the key token (the `#N` for plan, the feature label
  for roadmap), and the dependency targets parsed from the Dependencies cell.

- **`checkFC05(doc, spec, cfg) []ValidationError`** -- profile selected by
  `spec.SchemaVersion` (plan/v1 vs roadmap/v1); compares header to the profile's
  column contract and checks row pairing. Message form:
  `[FC05] <specific defect naming the column or row>`.

- **`checkFC06(doc, spec, cfg) []ValidationError`** -- builds the entity-row key
  set, validates each Dependencies target against it. Message form:
  `[FC06] dependency "<key>" in row "<key>" names no row in this table`.

- **`--lifecycle` mode** -- input: a root path. Walks the doc tree, selects docs
  by `DetectFormat` prefix, reads frontmatter `status` and `execution_mode` from
  the parsed `Doc`. Output: `L01`/`L02` errors (error-level, non-notice). Exit
  non-zero if any fire.

- **`populate-issues-table.sh <roadmap-path>`** -- reads the Features section,
  emits a per-feature manifest (`title`, `needs_label`, `dependencies`,
  `complexity: simple`), calls `create-issues-batch.sh --manifest`, renders and
  writes the reserved sections by replacing the body between each section's
  heading and the next. Output: updated doc + a JSON summary on stdout.

### Data Flow

Authoring a plan or roadmap: the skill reads the shared references for the table
and diagram shape, drafts the doc, and (multi-pr) stops at the approval gate. On
approval -- or under `--auto`, after recording an assumed approval block -- the
populate/create scripts run, issues are created, the table and diagram are
written, and the doc transitions to Active. Validation runs two ways: per-PR on
the changed files (content checks FC01-FC06) and per-PR whole-tree (lifecycle
checks L01/L02). The work-completing PR transitions Active->Done, the author
verifies, and the same PR deletes the doc; L01 failing on a present Done is what
forces the deletion into that PR.

## Implementation Approach

The phases match the PRD's staging: the shared references, the table parser, the
two error-level checks, the decision-surfacing, the roadmap script, and the
lifecycle/CI gate all land before the reconciliation increment, which sits behind
the spike.

### Phase 1: Shared references and principle wording

Create `workflow-principles.md`, `issues-table.md`, and `dependency-diagram.md`
at the plugin root. Move the diagram spec out of `plan-doc-structure.md`
verbatim. Trim `plan-doc-structure.md` and `roadmap-format.md` to cite the shared
references and keep only profile deltas and lifecycle content. Finalize the
five-principle wording. No code yet.
Deliverables: three new references; two trimmed skill references.

### Phase 2: Table parser and the two content checks

Add `internal/validate/table.go` with `parseIssuesTable` and the `Table` type.
Add `checkFC05` and `checkFC06` to `checks.go`, wire them into the `Plan` and a
new `Roadmap` arm of `ValidateFile`, with unit tests covering the canonical
profiles, the legacy `Title` plan form (migration message), the divergent
roadmap shapes, and a dangling cross-reference. The existing changed-files CI
workflow picks these up with no change.
Deliverables: `table.go`; FC05/FC06 in `checks.go`; switch arms in `validate.go`;
tests in `checks_test.go`.

### Phase 3: Migrate the committed corpus to the canonical profiles

Migrate the committed roadmap tables (`Feature | Status | Downstream Artifact`,
`Issue | Phase | Dependencies | Label`) into the roadmap profile and the legacy
plan table into the canonical plan shape, so FC05/FC06 pass on the corpus. This
phase exists because FC05 is error-level on day one (R6) and the divergent shapes
would otherwise redden CI.
Deliverables: migrated `docs/roadmaps/*` and `docs/plans/*` tables.

### Phase 4: Surface the decision and add the value guard

Lift the single-pr/multi-pr rule onto the plan `SKILL.md`, anchored on the
usable-value principle and de-conflated from the decomposition-strategy decision
(which stays in the phase file, explicitly named separate). Re-anchor the roadmap
multi-pr case on value. Add the value-confirmation step (can fail; names the
unit) with `--auto` record-and-proceed via decision blocks.
Deliverables: edits to plan `SKILL.md` and phase-3-decomposition.md; roadmap
SKILL value framing; value-guard step.

### Phase 5: Roadmap-to-issues scripted path

Add `skills/roadmap/scripts/populate-issues-table.sh` reusing
`create-issues-batch.sh`, writing the reserved sections by section replacement.
Route its issue-creation step through the R14 approval gate (interactive stop;
`--auto` assumed block). Retire the plan re-entry's prose string surgery for the
roadmap case. Add a script test mirroring the existing plan-script tests.
Deliverables: `populate-issues-table.sh`; its test; skill-phase gate wiring.

### Phase 6: Enforced lifecycle and the whole-tree CI gate

Add the `--lifecycle` mode (CLI flag + tree walk + `L01`/`L02` checks) and the
new reusable lifecycle workflow plus self-caller (no `paths:` filter). Wire the
verify-then-delete terminal into the skills/cascade: Active->Done +
verify + delete atomically in the work-completing PR. Remove the stale
move-to-`docs/plans/done/` wording. Update both skills' lifecycle references.
Deliverables: `--lifecycle` mode + tests; new CI workflow + self-caller; lifecycle
wiring; reference edits.

### Phase 7 (later increment): Mermaid-parser spike, then reconciliation

Write the spike artifact (grammar subset, extraction approach, strictness
recommendation). Then add `mermaid.go` and `checkFC07` reusing the parsed
`Table`, shipping as a notice first (via `IsNotice`) and promoted to error after
the committed-diagram corpus is reconciled.
Deliverables: spike artifact; later: `mermaid.go`, `checkFC07`, corpus diagram
reconciliation, notice-to-error promotion.

### Implicit decisions recorded

In `--auto` the implicit-decision review records rather than prompts. Two
implicit choices in the architecture above:

<!-- decision:start id="check-code-family" status="assumed" -->
### Decision: New checks reuse the FCnn code family; lifecycle checks use a new Lnn family

**Question:** What code namespace do the new content and lifecycle checks use?

**Choice:** Content checks continue the `FCnn` family (`FC05`, `FC06`, later
`FC07`); the whole-tree lifecycle checks use a new `L01`/`L02` family.

**Assumptions:** `FCnn` is the established family for per-doc content/structure
checks, so schema/cross-reference/reconciliation fit it; the lifecycle checks are
a distinct concern (whole-tree, presence-based) that reads more clearly under its
own prefix. A reviewer may prefer a single family -- low-cost to rename before
implementation.

**Consequences:** Check codes group by concern. Recorded as assumed so the
naming can be confirmed at plan time.
<!-- decision:end -->

<!-- decision:start id="corpus-migration-phase" status="assumed" -->
### Decision: Migrate the committed corpus in its own phase, before the checks go error-level in CI

**Question:** When does the committed-corpus migration happen relative to FC05/FC06 landing?

**Choice:** A dedicated migration phase (Phase 3) lands the corpus on the
canonical profiles right after the checks exist, so error-level FC05/FC06 do not
redden CI on the next PR.

**Assumptions:** The corpus is small (a handful of roadmaps/plans), so a single
migration phase is enough; FC05 is error-level on day one per R6 (only
reconciliation R8 is staged as a notice).

**Consequences:** The schema/cross-reference checks are strict immediately with
no retroactive breakage, satisfying R20 for the first pass. Recorded as assumed
because the exact per-document migration mechanics are the plan's.
<!-- decision:end -->

## Security Considerations

A dedicated security review covered four dimensions. The feature parses
repo-local Markdown and creates GitHub issues from committed content; it
downloads and executes nothing external and exposes no new data. The review's
verdict was that the architecture's existing controls address the risks, with
one implementation must-fix to capture.

**External artifact handling (applies, low).** The table parser (`table.go`),
the later mermaid extractor (`mermaid.go`), and the `--lifecycle` tree walk all
read repo-local committed text -- no network or user-supplied artifacts. The
risk is parser robustness, not a trust boundary: each parser must be total over
arbitrary line input (no index panics on ragged rows, bounded iteration on
missing separators or unterminated fences) and must fail with a validation error
or a clean "no table/diagram found" rather than panicking. The `--lifecycle`
walk reads a fixed doc-tree root, selects by filename prefix, and parses only
frontmatter; it must not follow symlinks out of the repo. Mitigation:
table-driven tests over malformed input; bound the walk to the doc tree.

**Permission scope (applies, medium, bounded).** The new
`populate-issues-table.sh` reuses `create-issues-batch.sh`, which runs `gh` to
create real GitHub issues -- a write action with effects outside the repo. The
R14 approval gate bounds it: interactive runs stop before any issue is created;
`--auto` runs proceed but record a loud high-priority assumed block, the
documented trade-off backstopped by the value guard and the human's later review
of the created issues. Implementation must-fix: the script passes manifest
values (feature names, titles) to `gh` as discrete arguments, never interpolated
into a shell string, so content with shell metacharacters cannot inject a
command. The section-replacement write must edit only between a section heading
and the next heading and write atomically (temp file plus rename) so a partial
run cannot corrupt the doc. The new lifecycle CI workflow declares
`permissions: contents: read` (matching the existing validator workflow); the
gate is a read-only scan and needs no write token.

**Supply chain or dependency trust (applies, low).** The first pass adds no new
dependency -- the table parser is stdlib-only, matching the package's current
footprint, and the design rejected a full mermaid parser, so the later increment
adds no parsing dependency either. The new reusable lifecycle workflow follows
the existing validator workflow's pattern: SHA-pinned actions and building the
binary from the called workflow's own pinned ref, so it does not widen the
supply-chain surface.

**Data exposure (not applicable).** The feature operates on repo-local Markdown
and creates issues whose content comes from those same committed docs, using the
repo's existing `gh` credential. Validation messages quote doc content (headers,
dependency keys) that is already public in a public repo. No secrets, tokens,
PII, or system data enter the new code paths.

## Consequences

### Positive

- One source of truth per shared concern (principles, table, diagram), consumed
  by both skills -- the per-document reinvention ends, and a future sibling doc
  type can adopt the same references.
- The first validation pass catches malformed tables and dangling
  cross-references with one new parser, reusing the existing CLI, the existing
  reusable workflow, and the established pure-function check pattern (R19).
- Reconciliation is de-risked: the spike sizes the mermaid problem before any
  code, and notice-then-error lets the corpus converge before the check blocks.
- The single-pr/multi-pr call is made where the reasoning is visible, anchored on
  value rather than mechanism, with a guard that can catch a mis-decomposition.
- The lifecycle has one terminal, enforced: Done is ephemeral, the verify-delete
  PR forces a final human review, and the two doc modes are symmetric (both
  CI-forced-absent at merge).
- Both `--auto` gates are non-blocking and loud -- no deadlock, and the assumed
  block surfaces in the PR body and terminal summary.

### Negative

- The whole-tree lifecycle scan re-reads unchanged docs on every PR, so an
  unrelated PR can fail because of a doc it did not touch (a left-behind single-pr
  plan, or a Done doc not yet deleted).
- The references and `formats.go` express the same contract in two places and can
  drift if edited separately.
- The first pass leaves table-diagram disagreement uncaught until the
  reconciliation increment lands.
- An `--auto` run can file GitHub issues and reach a mis-decomposed draft without
  an interactive human, because both gates record-and-proceed.
- The corpus migration is required work before the checks go strict, not optional
  cleanup.

### Mitigations

- The whole-tree re-read is the intended forcing mechanism, not a defect; the PRD
  records it as a known limitation, and Check A failing on a present Done is how
  the deletion becomes non-optional.
- The Implementation Approach calls out editing the references and `formats.go`
  together; the validator tests pin the contract `formats.go` enforces.
- The uncaught-disagreement gap closes when the reconciliation increment ships;
  it is a deliberate consequence of staging by blast radius (R20).
- The `--auto` issue-creation and value-judgment risks are mitigated by the loud
  high-priority assumed blocks (PR body + terminal summary), the value guard as a
  backstop to the approval gate, and the human's later review of the created
  issues; an operator who wants a hard human approval runs interactively.
- The migration is scoped to a single early phase because the committed corpus is
  small; it lands right after the checks exist so CI is never retroactively red.
