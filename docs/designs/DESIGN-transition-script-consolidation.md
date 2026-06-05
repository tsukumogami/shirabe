---
status: Accepted
upstream: docs/prds/PRD-transition-script-consolidation.md
problem: |
  Six per-skill `transition-status.sh` scripts (~2,000 lines of bash)
  reimplement one lifecycle-transition workflow by copy-paste and have drifted.
  The PRD requires consolidating them into one `shirabe transition` subcommand
  that reproduces each artifact type's behavior faithfully, then migrating every
  caller and deleting the scripts. This design settles the interface and
  internal shape the PRD deferred.
decision: |
  Add a `shirabe transition <file> <status>` subcommand backed by a declarative
  per-type spec table interpreted by one engine. The status is the canonical
  status name (case-insensitive); per-type extra inputs are named flags
  (`--superseded-by`, `--reason`). The engine reuses `validate`'s filename-prefix
  type detection, reproduces each script's validation, edits, git-mv moves,
  per-type JSON result, and 1/2/3 exit codes, and a golden parity harness pins
  the behavior before the scripts are deleted.
rationale: |
  A data-driven spec table removes the duplication (one engine, six small specs)
  while keeping each type's genuine differences explicit and in one place.
  Matching the scripts' `<file> <status>` order and shelling out to git keeps
  caller migration and parity verification simple. Named flags disambiguate the
  doc-path vs free-text third input the scripts overloaded onto one positional.
---

# DESIGN: transition-script consolidation

## Status

Accepted

## Context and Problem Statement

The six artifact-lifecycle skills each ship a `transition-status.sh` (~2,000
lines of bash total). Each reads a document's current status from frontmatter
and the body `## Status` line, decides whether the requested transition is
allowed, rewrites the frontmatter (and body) status, moves the file into a
status subdirectory for the three types that require it, and prints a JSON
result the caller parses. The shared spine is copy-pasted and has drifted; the
genuine per-type differences are tangled into each copy.

The PRD (`PRD-transition-script-consolidation.md`, Accepted) requires one
`shirabe transition` subcommand that reproduces every type's behavior faithfully
(per-type result shapes preserved, not unified; specific 1/2/3 exit codes;
idempotent no-op at the current status), errors when the artifact type cannot be
determined, and a full cutover that migrates all callers and deletes the
scripts. The PRD deferred four questions to this design: the CLI surface, how
the per-skill rules are represented, the `git mv` semantics, and ownership of
the body-status rewrite. This design settles them.

The per-type behavior to preserve, from the scripts:

| Type | Statuses | Transition rule | Moves on | Precondition | Extra input | Result extras |
|------|----------|-----------------|----------|--------------|-------------|---------------|
| vision | Draft, Accepted, Active, Sunset | ordered graph | Sunset → `docs/visions/sunset/` | Open Questions resolved (Draft→Accepted) | `--superseded-by` (optional, Sunset) | `superseded_by`, `new_path`, `moved` |
| strategy | Draft, Accepted, Active, Sunset | ordered graph | Sunset → `docs/strategies/sunset/` | Open Questions resolved (Draft→Accepted) | `--reason` (required, Sunset; sanitized) | `reason`, `new_path`, `moved` |
| roadmap | Draft, Active, Done | ordered graph | never | ≥2 features (Draft→Active) | none | `new_path`, `moved` |
| brief | Draft, Accepted, Done | ordered graph | never | none | none | (4 fields) |
| prd | Draft, Accepted, In Progress, Done | membership only | never | none | none | (4 fields) |
| design | Proposed, Accepted, Planned, Current, Superseded | membership only | Current → `docs/designs/current/`, Superseded → `docs/designs/archive/` | none | `--superseded-by` (required, Superseded) | `superseded_by`, `new_path`, `moved` |

## Decision Drivers

- **Faithful parity.** Callers (including `run-cascade.sh`, which parses
  `new_path` and relies on exit codes) must see no behavior change.
- **Remove the duplication.** The shared spine must exist once; per-type
  differences must be explicit, not copy-pasted.
- **Low migration risk.** The fewer surprises for existing call sites, the
  smaller the cutover.
- **Verifiability.** Parity must be checkable before the scripts are deleted.

## Considered Options

**Decision 1 — CLI surface.**
- (1a) `<file> <status>` positional, status as canonical name, extra input as
  named flags (`--superseded-by`, `--reason`).
- (1b) `<status> <file>` (verb-object reading), as the brief's illustrative
  examples showed.
- (1c) Lifecycle verbs (`accept`, `sunset`) instead of status names.
- Third input: positional (as the scripts overload it) vs named flags.

**Decision 2 — Per-skill rules representation.**
- (2a) A declarative in-code spec table (one struct per type) interpreted by a
  shared engine.
- (2b) Hardcoded per-type functions/branches (mirrors the scripts).
- (2c) An external configuration file.

**Decision 3 — Directory-move mechanics.**
- (3a) Shell out to `git mv` (fall back to `mv`), replicating the scripts.
- (3b) Use a git library (libgit2/gix).

**Decision 4 — Body `## Status` rewrite ownership.**
- (4a) The subcommand owns the body rewrite, with per-type templates.
- (4b) The subcommand rewrites only frontmatter; skills keep the body rewrite.

## Decision Outcome

**1a — `shirabe transition <file> <status>`**, status as the canonical status
name (case-insensitive; multi-word values like `In Progress` accepted quoted),
with per-type extra inputs as named flags: `--superseded-by <path>` (required
for design Superseded, optional for vision Sunset) and `--reason <text>`
(required for strategy Sunset). Rejected 1b/1c: `<file> <status>` matches the
scripts and the `run-cascade.sh` call shape, minimizing migration; status names
(not verbs) match the frontmatter values and avoid a per-type verb-alias table.
Named flags disambiguate the doc-path (`--superseded-by`) from the free-text
(`--reason`) input the scripts overloaded onto a single positional, and let the
engine enforce `(type, target)`-conditional requiredness with clear errors.

**2a — declarative spec table.** One `TransitionSpec` per type holds: the status
set, the transition rule (an ordered edge list, or "membership only"), the
precondition kind, the directory-move map, the extra-input requirement, the
body-template kind, and the result-field set. A single engine interprets the
spec. Rejected 2b (rebuilds the duplication in Rust) and 2c (no need for runtime
configurability; rules are code-coupled, and an in-code table is type-checked).
The table is the one place a rule changes, and is the natural seam for a future
"single authority" effort.

**3a — shell out to `git mv`** (detect the work tree with `git rev-parse`, fall
back to `mv` outside a repo), `mkdir -p` the target, leave the move
staged-but-uncommitted, and error (code 3) if the target already exists —
exactly the scripts' semantics. Rejected 3b: a git library would change the
staged-not-committed behavior and the exact error surface callers depend on, for
no parity benefit.

**4a — the subcommand owns the body rewrite**, reproducing each type's template.
Most types read the first word of the `## Status` line and write the bare status
word; prd is the exception — it matches and rewrites the **entire** status line
(no first-word truncation), which is how the multi-word `In Progress` round-trips.
The non-bare templates: `Superseded by [name](path)` for design, `Sunset:
superseded by [name](path)` for vision, `Sunset: <reason>` for strategy.
Rejected 4b: leaving the body rewrite in the skills would regrow the very logic
this consolidates.

Type detection reuses `validate`'s `detect_format` (filename prefix); an
unrecognized filename errors (exit 1, "cannot determine artifact type"), not
skips — per the PRD.

## Solution Architecture

A `transition` module in the `shirabe-validate` crate (it already owns
`detect_format`, frontmatter parsing, and the FORMATS map), driven by a clap
subcommand in the `shirabe` binary.

- **`TransitionSpec`** — a per-type descriptor: `statuses`, `rule`
  (`Graph(edges)` with the type's own edge list, or `MembershipOnly`),
  `precondition` (`None | OpenQuestionsResolved | MinFeatures(2)`), `moves` (a
  map from status to target directory), `extra_input` (`None |
  SupersededBy{required, missing_code} | Reason{required, sanitized,
  missing_code}`), `body_template`, and `result_fields`. The `edges` are
  per-type — strategy's graph includes `Accepted → Sunset`, which vision's does
  not — so the table holds each type's exact edge list, not a shared one. The
  `missing_code` records the per-type exit code for a missing required input:
  **1** for design's `--superseded-by` (the scripts treat it as an
  invalid-arguments error), **2** for strategy's `--reason`. The six specs live
  in one table.
- **Engine** (`fn run_transition(file, status, flags) -> Result<Outcome, TransitionError>`).
  The order matches the scripts so parity holds — in particular the extra-input
  gate runs **before** the idempotent short-circuit:
  1. `detect_format(basename)` → type, or exit 1 ("cannot determine artifact
     type").
  2. Parse the document's current status from frontmatter and the body
     `## Status` line, reusing the existing read-only frontmatter parser
     (`parse_doc`); an unparseable status is exit 1.
  3. The target must be a known status for the type, else exit 2.
  4. Extra-input gate (before idempotency): if this `(type, target)` requires an
     extra input, it must be present — a missing `--superseded-by` for design
     Superseded is exit 1, a missing `--reason` for strategy Sunset is exit 2 —
     and `--reason`, when given, must pass sanitization (else exit 2). Vision's
     Sunset `--superseded-by` is optional and simply recorded when present.
  5. Idempotent short-circuit: if the target equals the current status →
     success no-op (`moved: false`, path unchanged, no edits), exit 0; the
     transition rule and preconditions do **not** run (the extra-input gate in
     step 4 already did).
  6. Transition rule: `Graph` types check the edge is allowed (else exit 2);
     `MembershipOnly` types are already covered by step 3.
  7. Precondition: `OpenQuestionsResolved` / `MinFeatures(2)`, else exit 2.
  8. Apply edits: a targeted `status:` line replacement in the frontmatter and a
     `## Status` body rewrite per the type's template, plus the extra
     frontmatter field (`superseded_by` / `sunset_reason`) when applicable.
     These are **new** targeted line edits mirroring the scripts' `sed`/`awk`
     (not a YAML re-serialization), so untouched bytes are preserved — only the
     read path reuses the parser.
  9. Move: if the spec moves on this status, `git mv` (or `mv` outside a repo)
     into the target directory; a file-operation failure is exit 3.
  10. Emit the per-type JSON result on stdout (success) or stderr (error, with a
     matching `code` field).
- **CLI**: `shirabe transition <file> <status> [--superseded-by <path>]
  [--reason <text>]`, wired in `crates/shirabe/src/main.rs` alongside `validate`.
- **Parity harness**: a golden corpus capturing, per type, each script's
  resulting frontmatter, body, JSON result, **and exact exit code** as the
  expected baseline, asserted structurally against the subcommand. The cases
  must cover, where applicable per type: a legal move; a rejected move for the
  graph types and a rejected invalid-status (exit 2) for the membership-only
  types (prd, design); each precondition block; an idempotent re-run at a
  terminal status; an idempotent re-run that still fails the extra-input gate
  (design Superseded with no `--superseded-by` → exit 1; strategy Sunset with no
  or an unsafe `--reason` → exit 2); prd transitioning both into and out of
  `In Progress`; and the directory-move and extra-field cases. This mirrors the
  `validate` rewrite's golden-parity approach.

### Boundary and extensibility

The command operates on **one document, deterministically and locally**, like
`validate`. Two kinds of logic deliberately stay out of it:

- **External-state checks.** A gate such as "a PLAN may reach Done only when its
  issues are complete in GitHub or the enclosing PR" needs network and auth and
  is non-deterministic. The command performs no network or GitHub checks; the
  workflow that triggers such a transition (which already holds the GitHub/PR
  context) verifies the condition, then calls `shirabe transition`. Spec-table
  preconditions are limited to deterministic, document-local checks (the
  existing Open-Questions-resolved and ≥2-features gates).
- **Cross-document / cross-repo propagation.** When a document transitions,
  related artifacts sometimes need updating — e.g. an upstream roadmap feature
  dropping its `needs-design` marker once a design is Accepted, possibly in
  another repo. The command edits no other document; propagating a transition's
  effects across the upstream chain is the cascade/workflow layer's job (today's
  `run-cascade.sh`), and the cross-repo case is an open gap tracked separately —
  not part of this consolidation.

Extending per-type behavior follows from this: a new **deterministic,
document-local** rule is a new `TransitionSpec` precondition variant plus its
function, referenced from one type's spec — one localized change. Anything that
needs external state or edits to other documents belongs in the workflow layer,
not the spec table.

## Implementation Approach

The PRD calls for a single PR (full cutover). Suggested commit order within it:

1. `TransitionSpec` table + engine core (detect, parse, validate, frontmatter
   rewrite, result assembly, exit codes) wired as `shirabe transition`, covering
   the membership-only / no-move / no-precondition types first (prd, roadmap,
   brief without their graph/precondition extras) to land the spine.
2. Ordered-graph rule + the content preconditions (vision/strategy Open
   Questions, roadmap ≥2 features) and the idempotent-no-op short-circuit.
3. Directory moves (design/vision/strategy) via `git mv`, the per-type extra
   inputs and `--reason` sanitization, the per-type body templates and extra
   frontmatter fields.
4. The golden parity harness across all six types.
5. Caller migration across the full reference surface (`git grep
   transition-status`): each skill's `SKILL.md`; `work-on/run-cascade.sh` and
   its test; the prd skill's direct call to the brief script; the
   `skills/{brief,strategy}/evals/test-cli.sh` harnesses; the
   `check-brief-scripts.yml` CI job; the affected `evals.json` expected_output;
   and the instructional reference/phase docs. Then delete the six scripts and
   their `transition-status_test.sh`. The grep-clean check excludes the frozen
   `validate` golden corpus (`crates/shirabe/tests/fixtures/golden/corpus/`),
   which holds point-in-time doc snapshots, not live references.

The binary keeps building as `shirabe`; no new crate.

## Security Considerations

- **Reason sanitization is a security control**, not a nicety: strategy rejects
  newlines and `\ / & ---` in the Sunset reason to prevent frontmatter and
  body-line injection. The engine reproduces this for `--reason`; the parity
  harness includes a rejected-reason case.
- **Path handling**: `<file>` and `--superseded-by` are treated as repo-relative
  paths. Rejecting paths that resolve outside the repo work tree is a
  deliberate, **additive** hardening (the scripts do not do this), justified
  because every real caller passes repo-relative paths; flagged here as a
  conscious choice, not an accidental parity break.
- **No shell injection**: `git mv` is invoked with an argument vector, never an
  interpolated shell string.

## Consequences

- **Positive**: ~2,000 lines of drifting bash become one engine plus six small
  specs; a transition rule changes in one place; callers get a single
  installed-binary entry point; parity is pinned by a golden harness.
- **Negative / accepted**: the per-type result shapes stay divergent (the PRD
  chose preserve-over-unify), so the engine carries per-type result specs;
  unifying them is a separate future effort. Shelling out to `git` keeps a
  process dependency, accepted for exact parity.
- **Follow-on**: the declarative spec table is the seam a later "single
  authority for deterministic checks" effort can extend.
