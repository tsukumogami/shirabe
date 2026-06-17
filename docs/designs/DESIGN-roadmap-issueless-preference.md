---
schema: design/v1
status: Planned
problem: |
  shirabe's roadmap workflow assumes the Implementation Issues table and
  Dependency Graph are filled by creating one GitHub issue per feature. An
  org that sequences features in roadmap prose without filing issues has no
  first-class path: the format reference stamps both sections "Do not fill
  manually", the only populate command mints issues, and the validator's FC06
  rejects the soft/external dependency annotations such authors reach for.
decision: |
  Add a repo/org-level `## Roadmap Issues: optional` CLAUDE.md convention
  header (default `required`) read by the roadmap skill. When `optional`, the
  skill fills both reserved sections from the Features section via an issueless
  render path on `shirabe roadmap populate` (no `gh issue create`), and the
  "Do not fill manually" instruction is conditioned on the preference. The
  validator is unchanged; authors keep Dependencies cells as bare feature keys.
rationale: |
  The validator already accepts the issueless feature-keyed shape (verified:
  clean with bare-key deps), so the change is skill-behavior only -- making it
  a CLAUDE.md header like `## Execution Mode:` rather than a validator gate.
  Generating the sections from feature context (not freehand) keeps the
  "filled by a tool, not by hand" invariant that makes the table trustworthy,
  and bare-key deps avoid the one real FC06 blocker without loosening a check.
motivating_context: |
  Adopters have begun authoring roadmaps that sequence features in prose and
  fill the issues table and dependency diagram from that prose, deliberately
  not filing a GitHub issue per feature. shirabe tolerates the resulting
  document but neither blesses nor supports authoring it.
---

# DESIGN: roadmap-issueless-preference

## Status

Planned

Accepted after human review. Authored via the tactical chain (`/scope`), BRIEF
and PRD skipped (the framing and the requirement were settled during the
upstream `/explore` run). A PLAN has been authored against this design.

## Context and Problem Statement

A shirabe ROADMAP carries two reserved sections -- Implementation Issues (a
`Feature | Issues | Dependencies | Status` table) and Dependency Graph (a
Mermaid diagram). The blessed way to fill them is `shirabe roadmap populate`,
which reads the Features section, creates **one GitHub issue per feature**
(`skills/roadmap/SKILL.md:289-293`), then renders the table and diagram keyed
on those issues. The format reference stamps both empty sections with
`<!-- Populated by /plan during decomposition. Do not fill manually. -->`
(`skills/roadmap/references/roadmap-format.md:132,147`).

Some adopters sequence features entirely in roadmap prose and want the table
and diagram filled **from that prose, without filing an issue per feature** --
the feature rows carry `needs-design`/`needs-spike` labels in the Issues column
and the diagram uses feature nodes (`F1 --> F2`). shirabe has no first-class
path for this. The author must step around the "Do not fill manually"
instruction, there is no issueless populate mode, and nothing declares that a
given repo authors roadmaps this way.

What is *not* the problem: a hard requirement that Active roadmaps have issues.
There is none. The Draft -> Active transition checks only for >= 2 `### Feature`
headings (`crates/shirabe-validate/src/transition.rs`, `Precondition::MinFeatures(2)`).
The friction is workflow prose and tooling shape, not a validation gate.

Empirically grounding the validator's actual behavior (binary `shirabe v0.11.0`,
`validate --visibility=public` on a feature-keyed fixture mirroring the adopter
shape):

- An issueless, feature-keyed table (`needs-*` in the Issues column) plus an
  `F`-node diagram validates **clean (0 errors)**. FC05 (table schema), FC07
  (table/diagram reconciliation) do not fire -- FC07 excludes non-`I<n>`
  diagram nodes by design (`crates/shirabe-validate/src/checks.rs:716-719`).
- The **one** error-level blocker is FC06: dependency-cell *annotations* are
  rejected. `F1 (soft)` and `None (ext: onboarding)` each produce
  `[FC06] dependency "..." names no row in this table`
  (`crates/shirabe-validate/src/checks.rs:471-518`). Rewriting those cells as
  bare keys (`F1`, `None`) clears all errors.

So the capability is one header, one issueless render path, a conditioned prose
line, and an authoring convention for dependency cells -- with the validator
left untouched.

## Decision Drivers

- **D1 -- Per-repo/org, not per-document.** The preference is a property of how
  an org runs its roadmap process, so it belongs at repo configuration
  altitude, parallel to `## Execution Mode:` and `## Repo Visibility:`.
- **D2 -- The validator is already permissive; do not gate it on the
  preference.** The validator never enforced "issues required" (verified
  above). A design that adds a validator gate would add enforcement that does
  not exist today and couple two layers that need not couple.
- **D3 -- Keep reserved sections tool-generated, not freehand.** The "filled by
  a tool, not by hand" property is what lets a reader trust the table mirrors
  the Features section and lets a CI staleness check work. A solution that
  invites freehand editing erodes that.
- **D4 -- Avoid loosening a useful check without cause.** FC06's bare-key rule
  catches real typos in dependency references. Relaxing it to tolerate
  arbitrary parenthetical prose has a cost; it should be chosen only if the
  annotation is worth more than the check.
- **D5 -- Backward compatibility.** Repos with no new header must behave exactly
  as today (issue-creating populate, "Do not fill manually" in force). The
  default must be `required`.
- **D6 -- Minimal surface.** The change should touch the fewest moving parts
  that deliver the capability; each added subcommand flag or validator branch
  is future maintenance.

## Considered Options

Three decisions are in play. Each is presented with its alternatives.

### Decision A -- Where the preference is declared

- **A1: CLAUDE.md convention header (`## Roadmap Issues: optional | required`).**
  Repo/org-level, read by the roadmap skill during discovery, exactly mirroring
  the `## Execution Mode:` mechanism (skill greps the header, defaults when
  absent). Satisfies D1 and D5. The validator never reads it (D2). Chosen.
- **A2: Per-roadmap frontmatter flag (e.g. `issues: optional`).** Per-document,
  not per-org -- contradicts D1, and would have to be repeated on every roadmap
  in a repo that always works this way. Also widens the `roadmap/v1` frontmatter
  schema, pulling the validator in (against D2). Rejected as the primary
  mechanism; a frontmatter override could be layered on later if a repo needs
  per-roadmap divergence, but v1 does not need it (D6).
- **A3: A new config file (`.shirabe.toml`).** No such loader exists; skills and
  the validator read CLAUDE.md headers and CLI flags only (the validator's
  `Config` is fed by flags, `crates/shirabe-validate/src/doc.rs`). Introducing a
  config-file layer for one boolean is disproportionate (D6). Rejected.

### Decision B -- How the reserved sections get filled in issueless mode

- **B1: Issueless render path on `shirabe roadmap populate`.** Extend the
  existing subcommand with a mode that reads the Features section (it already
  does this via the shared `shirabe-validate` parser), renders a feature-keyed
  table and `F`-node diagram, and writes them by structural section
  replacement -- **skipping the `gh issue create` loop and the R14 gate**. The
  sections stay tool-generated (D3); the parser and section-replacement
  machinery are reused (D6). Chosen.
- **B2: Author-fill guidance (relax "Do not fill manually", have the skill write
  the cells in prose).** Lighter -- no subcommand change -- but it makes the
  sections freehand, breaking the tool-generated invariant (D3) and making any
  future CI staleness check impossible. Rejected as primary; retained as the
  documented fallback if the subcommand change is deferred.
- **B3: Hand to `/plan`.** `/plan` owns issue-keyed population and creates
  issues; bending it to a no-issue feature-keyed render duplicates the
  roadmap-native populate path the project already chose
  (`skills/roadmap/SKILL.md:81-84`). Rejected.

### Decision C -- The FC06 dependency-annotation blocker

- **C1: Author discipline -- bare-key dependency cells (no validator change).**
  In issueless mode, Dependencies cells are bare feature keys or `None`
  (`F1`, `F1, F2`, `None`); soft/hard nuance and external dependencies move into
  the feature prose and the Sequencing Rationale, where the adopter shape
  already explains them. Verified clean. Zero code, ships immediately, FC06
  stays strict (D4). Chosen.
- **C2: Teach FC06 to tolerate annotations.** Strip trailing `(...)` from
  roadmap dependency tokens and treat `None (...)` as `None`. Blesses the
  `F1 (soft)` idiom directly, but costs a Rust change plus tests and loosens a
  check that catches typos (against D4 and D6) for a nuance that reads fine in
  prose. Rejected for v1; revisit if soft/hard-in-the-cell proves to carry
  weight prose cannot.

## Decision Outcome

Ship the issueless roadmap mode as a **repo/org preference, skill-behavior
only, validator untouched**:

1. A `## Roadmap Issues:` CLAUDE.md header with values `optional | required`,
   default `required` when absent (Decision A1). The roadmap skill reads it
   during discovery the way it reads `## Execution Mode:`.
2. When `optional`, `shirabe roadmap populate` runs an **issueless render path**
   (Decision B1): it builds the feature-keyed Implementation Issues table and
   the `F`-node Dependency Graph from the Features section and writes both by
   structural section replacement, with no `gh issue create` and no R14 gate.
   When `required` (or header absent), the subcommand behaves exactly as today.
3. The reserved-section `<!-- ... Do not fill manually. -->` markers and the
   roadmap-format prose are conditioned on the preference: under `optional` the
   sections are tool-filled from feature context rather than from issues, so the
   "populated by /plan" framing is replaced by an "issueless populate" framing.
4. Dependencies cells in issueless mode are authored as **bare feature keys**
   (Decision C1). The validator needs no change; FC06, FC05, and FC07 pass as
   verified.

This keeps the two layers decoupled (D2), the sections tool-generated (D3), the
default behavior unchanged (D5), and the footprint to one header + one
subcommand branch + conditioned prose (D6).

## Solution Architecture

Components touched:

- **`## Roadmap Issues:` header (config surface).** Documented in
  `references/fixes/claude-md-conventions.md` alongside the other convention
  headers so the FC-CONVENTIONS check recognizes it. Grammar: `## Roadmap
  Issues: optional` or `## Roadmap Issues: required`. Absent -> `required`.
- **Roadmap skill (`skills/roadmap/`).** Discovery reads the header into the
  run's context (mirroring the `## Execution Mode:` read). The populate input
  mode (`SKILL.md:81-84, 289-346`) branches on the preference: `required`
  keeps the issue-creating path and the R14 approval gate; `optional` calls the
  subcommand's issueless render and skips R14 (there is nothing to approve --
  no issues are created).
- **`shirabe roadmap populate` subcommand (CLI, `crates/`).** Gains an issueless
  mode (flag, e.g. `--no-issues`, set by the skill from the preference). The
  feature parse, table renderer, diagram renderer, and structural
  section-replacement writer are shared with the issue-creating path; only the
  issue-creation step and the issue-keyed vs feature-keyed rendering differ. In
  issueless mode the Issues column carries the feature's `needs-*` label, the
  diagram nodes are `F<n>`, and dependency edges derive from the Features
  section's stated dependencies as bare keys.
- **Format reference (`skills/roadmap/references/roadmap-format.md`).** The two
  "Do not fill manually" markers and the validation-rules prose gain the
  issueless branch: under `optional`, the sections are populated by the
  issueless populate path from feature context; the bare-key dependency-cell
  convention is documented here.
- **`/charter` chain + roadmap SKILL framing.** Text that presents issue
  creation as the only populate outcome is updated to present the two modes.
- **Validator (`crates/shirabe-validate/`).** Unchanged. The issueless shape
  already validates clean; this is an explicit non-change recorded so a future
  reader does not "fix" FC06 expecting it to be part of this work.

Data flow (issueless populate): Features section --> shared feature parser -->
per-feature manifest (label, deps as bare keys) --> feature-keyed table renderer
+ `F`-node diagram renderer --> structural section replacement into the two
reserved sections. No GitHub round-trip.

## Implementation Approach

Three batches, sequenced so each lands independently useful:

- **Batch 1 -- Preference plumbing + docs (no behavior change yet).** Add the
  `## Roadmap Issues:` header to `claude-md-conventions.md`; teach the roadmap
  skill's discovery to read it; document the bare-key dependency convention and
  the issueless branch in `roadmap-format.md`, conditioning the "Do not fill
  manually" markers. At this point an author can hand-produce a clean issueless
  roadmap following documented rules even before the subcommand lands (this is
  the B2 fallback, made correct-by-docs).
- **Batch 2 -- Issueless render path on `shirabe roadmap populate`.** Add the
  issueless mode to the subcommand (feature-keyed table + `F`-node diagram, no
  `gh issue create`); branch the skill's populate mode and R14 gate on the
  preference. Batch 2 depends on Batch 1 (the preference must exist to branch
  on). This is the batch that makes the sections tool-generated.
- **Batch 3 -- Chain framing + evals.** Update the `/charter` chain and roadmap
  SKILL prose to present both modes; add/refresh roadmap skill evals covering
  an `optional`-repo run (issueless populate, no issue creation, clean
  validation) and confirm the `required`-repo run is unchanged. Run the evals
  per the repo's eval discipline.

The PLAN (downstream) owns the atomic issue decomposition within each batch and
the Implementation Issues table; this design names the batches only.

## Security Considerations

Low surface. The change is configuration-and-rendering, not a new external
input path.

- **Header parsing.** `## Roadmap Issues:` is parsed from the repo's own
  CLAUDE.md, the same trust domain as the existing convention headers; values
  are constrained to the `optional | required` enum and default safely to
  `required`. An unrecognized value falls back to `required` (fail-closed
  toward the issue-creating, human-gated path).
- **R14 gate.** R14 gates GitHub issue *creation*. The issueless path creates no
  issues, so skipping R14 in that mode removes a gate over an action that does
  not occur -- it does not bypass approval over any side effect. The
  issue-creating path retains R14 unchanged.
- **No new interpolation.** The issueless renderer consumes the already-parsed
  Features section via the shared validator parser; it introduces no new
  untrusted-input interpolation into shell commands (it removes the `gh issue
  create` invocations rather than adding any).

Residual risk accepted: an org that sets `optional` forgoes per-feature GitHub
issue tracking at the roadmap layer by design; downstream `/plan` still creates
issues when a feature is decomposed.

## Consequences

**Positive:**

- Orgs that sequence features in prose get a first-class, documented,
  CI-clean roadmap mode instead of stepping around "Do not fill manually".
- The validator is untouched, so there is no risk of regressing issue-keyed
  roadmaps and no new enforcement to reason about.
- The reserved sections stay tool-generated in both modes, preserving the
  trust property a future CI staleness check would rely on.
- The preference mirrors an existing, well-understood mechanism
  (`## Execution Mode:`), so adopters and maintainers have a precedent to read.

**Negative and mitigations:**

- *Two populate modes to maintain.* The subcommand now has an issue-creating and
  an issueless path. Mitigation: they share the parser, renderers, and writer;
  only issue creation and the table/diagram keying differ, keeping the divergence
  small (D6).
- *Soft/hard and external-dependency nuance leaves the table cell.* Under the
  bare-key convention, that nuance lives in feature prose and Sequencing
  Rationale, not the Dependencies cell. Mitigation: the adopter shape already
  explains these in prose; Decision C2 (FC06 tolerance) remains a documented
  escalation if cell-level annotation proves necessary.
- *A new convention header to keep in sync.* `## Roadmap Issues:` joins the
  convention-header set the FC-CONVENTIONS check and docs track. Mitigation: it
  is added to `claude-md-conventions.md`, the single canonical list, the same
  way the others are.
