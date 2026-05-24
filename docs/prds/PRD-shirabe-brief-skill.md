---
schema: prd/v1
status: Draft
problem: |
  shirabe's tactical chain runs roadmap to PRD to design to plan, but
  has no codified artifact between feature sequencing and requirements.
  Authors jump from "which feature" straight to "what are the
  requirements," skipping the step that frames a feature's problem,
  outcome, journeys, and scope. The brief shape exists by demonstration
  but has no skill, format spec, validation, or jury. The upstream
  brief committed to a standalone `/brief` skill plus a BRIEF template;
  this PRD locks the requirements for both.
goals: |
  BRIEF becomes a first-class shirabe artifact type alongside VISION,
  STRATEGY, ROADMAP, PRD, DESIGN, and PLAN, with the same shape of
  infrastructure each of the others has: a loadable phased skill, a
  format reference, a Phase 4 jury, `shirabe validate` CLI coverage,
  and CI validation through the existing reusable workflow. Authors
  reach for `/brief` to frame a feature before requirements exist; the
  jury catches content and structural defects; validation runs at the
  CLI and PR layers using the patterns the other types already
  established. The already-shipped brief keeps validating green.
upstream: docs/briefs/BRIEF-shirabe-brief-skill.md
---

# PRD: shirabe-brief-skill

## Status

Draft

This PRD picks up the requirements work scoped by
`docs/briefs/BRIEF-shirabe-brief-skill.md`. It owns the artifact-format
details, the jury rubric, the `shirabe validate` extension, the CI
activation, the `/brief` skill structure, and the brief-specific
artifact-decision prose. Implementation (the skill body, the
format-reference content, the Go-side Formats map entry, the
transition script) lands in a downstream DESIGN doc plus
implementation issues.

The PRD closes the three open questions the brief raised: the required
frontmatter field set, which sections are required versus optional,
and the skill's phase count. Positions are recorded in the Decisions
and Trade-offs section with rationale grounded in existing
artifact-type precedents.

## Problem Statement

shirabe recognizes six artifact types today, each with a dedicated
loadable skill, a format reference at
`skills/<name>/references/<name>-format.md`, a Phase 4 jury where
applicable, and `shirabe validate` Formats-map coverage. The tactical
authoring chain runs `/roadmap` to `/prd` to `/design` to `/plan` to
`/work-on`.

The gap sits between the roadmap and the PRD. Once a roadmap names a
feature, an author who reaches for `/prd` is asked to articulate
requirements — user stories, acceptance criteria, scope — before
anything has framed the feature's problem, its intended outcome, the
journeys it serves, and its boundary. The roadmap entry is a line
item; the PRD is a requirements contract; the framing step between
them is uncodified.

The proof-of-concept already exists: `BRIEF-shirabe-strategy-skill.md`
was authored by hand, ahead of any `/brief` skill, because the brief
shape was the right tool and no skill produced it. The structural
pattern is stable. What's missing is durability:

- **No skill entry point.** An author who wants to frame a feature
  before writing requirements has no `/brief` to load. They skip the
  step or reverse-engineer the shape from the one existing example.
- **No format reference.** There is no `brief-format.md`, so the next
  author has no canonical source for required sections, frontmatter
  schema, or lifecycle.
- **No jury rubric.** The prior brief got no Phase 4 review. Without a
  codified jury, brief quality depends on author discipline alone.
- **No validation discipline.** `shirabe validate` doesn't recognize
  BRIEF frontmatter or required sections; CI doesn't gate on
  structural correctness; lifecycle transitions go unenforced.

Each is small in isolation. Together they're the gap between "a brief
has been written once" and "briefs are first-class shirabe
infrastructure."

## Goals

1. **Codify BRIEF as a first-class artifact type.** Define the
   frontmatter schema (`schema: brief/v1`), required and optional
   sections, and lifecycle states, in a format reference that follows
   the existing `strategy-format.md` and `prd-format.md` skeleton.

2. **Author `/brief` as a loadable phased skill.** Follow the
   `/strategy` and `/decision` precedent: plain-English SKILL.md, phase
   files under `references/phases/`, progressive disclosure, wip/-based
   intermediates, and a Phase 4 jury that aggregates two parallel
   reviews before the artifact transitions to Accepted.

3. **Carry the brief-specific artifact decision.** The skill's phase
   prose decides, when the tactical chain is entered partway up,
   whether to produce a durable brief artifact or pass existing
   evidence forward to the PRD.

4. **Enable validation at both layers.** Add `brief/v1` to the
   `shirabe validate` Formats map so the CLI validates locally; the
   existing reusable validation workflow then activates the same
   checks in CI for shirabe and downstream adopters.

5. **Hold the bootstrapping constraint.** The already-shipped
   `BRIEF-shirabe-strategy-skill.md` must keep validating green the
   moment `brief/v1` enters the Formats map. The required-field and
   required-section sets are chosen to satisfy this.

6. **Close the three open questions from the brief.** Take positions
   on required frontmatter fields, required-versus-optional sections,
   and skill phase count, recorded in Decisions and Trade-offs.

## User Stories

**As a feature author before requirements exist**, I want to invoke
`/brief` cold so that I can frame a feature's problem, outcome,
journeys, and scope without reading the one prior brief and
reverse-engineering the format.

**As a feature author working through the phased skill**, I want Phase
4's jury to catch content and structural defects before the document
transitions to Accepted, so that briefs land with the same quality
gating other artifact types get.

**As an author entering the chain partway up**, I want the skill to
decide whether a durable brief earns its keep or whether my existing
evidence should pass forward to the PRD, so that I don't author a
ceremonial document when the framing already exists.

**As a PRD author**, I want to declare `upstream:
docs/briefs/BRIEF-<name>.md` in my PRD's frontmatter and have the
reference resolve through the same upstream/downstream graph the other
types use, so that the framing step integrates without special-casing.

**As a reviewer of a BRIEF PR**, I want CI to fail when the document
is missing a required section or has an invalid status, so that I
don't verify structural correctness by hand on every brief.

**As a maintainer of the existing strategy-skill brief**, I want it to
keep passing validation once `brief/v1` ships, so that codifying the
schema doesn't retroactively break the document that proved the shape.

## Requirements

### Functional Requirements

**R1: BRIEF artifact type definition.** The format reference file at
`skills/brief/references/brief-format.md` defines `schema: brief/v1`
with the following frontmatter:

- Required fields:
  - `status` — lifecycle state; string matching one of the valid
    statuses named in R4.
  - `problem` — YAML literal block scalar (`|`), a 2-4 line summary of
    the problem the feature solves. Same content the Problem Statement
    section elaborates in prose.
  - `outcome` — YAML literal block scalar (`|`), a 2-4 line summary of
    the outcome a user should experience. Same content the User
    Outcome section elaborates in prose.
- Optional field: `upstream` (path to an upstream artifact such as a
  roadmap, possibly cross-repo using the `owner/repo:path` convention
  defined in `references/cross-repo-references.md`). Omitted when the
  upstream is a private artifact a public brief cannot name.

**R2: Required sections.** BRIEF documents include the following
top-level sections, in order:

1. Status
2. Problem Statement
3. User Outcome
4. User Journeys
5. Scope Boundary

**R3: Optional sections.** BRIEF documents may additionally include:

- **Open Questions** (Draft status only; deferred items the downstream
  PRD resolves; must be empty or removed before Draft → Accepted).
- **Downstream Artifacts** (links to the PRD and design that pick up
  the brief; added as downstream work starts).
- **References** (in-repo precedents the brief draws on).

R2 and R3 are chosen so the already-shipped
`BRIEF-shirabe-strategy-skill.md` validates green: its sections are a
superset of the R2 required set, and every additional section it
carries is in the R3 optional set (see R8 and Decision 2).

**R4: Lifecycle states and transitions.** BRIEF uses a PRD-style
three-state lifecycle with no directory movement on any terminal
state:

| State | Meaning | Transition Trigger |
|-------|---------|--------------------|
| Draft | Under development; may have open questions | Created by `/brief` |
| Accepted | Framing locked; Phase 4 jury all-PASS recorded | Phase 4 jury all-PASS + explicit human approval |
| Done | Brief has been operationalized by its downstream PRD | Manual transition via `skills/brief/scripts/transition-status.sh` |

The transition script follows the per-skill convention established by
`skills/strategy/scripts/transition-status.sh` and equivalents in
`/prd`, `/roadmap`, and `/design`. Unlike STRATEGY, BRIEF has no
Active or Sunset state and no directory move on Done — it mirrors PRD's
terminal-state handling, not VISION's or STRATEGY's. BRIEF introduces
no cross-repo graph-watching infrastructure; transitions are
operator-invoked.

**R5: `/brief` skill structure.** The skill is a plain-English
SKILL.md at `skills/brief/SKILL.md` with phase files at
`skills/brief/references/phases/phase-<N>-<name>.md`. Phase structure
mirrors `/strategy` and `/decision`:

- Phase 0: Setup (entry mode, upstream detection, wip/ initialization,
  and the brief-specific artifact decision; see R7).
- Phase 1-3: Discovery, drafting, structural fill.
- Phase 4: Jury validate (two parallel reviewers; see R6).
- Phase 5: Finalize (status transition, cleanup, PR).

The skill performs the Draft → Accepted status change in code after
the user explicitly approves via the standard finalization
AskUserQuestion dialogue (mirroring `/strategy` and `/prd`
finalization). Jury PASS is a necessary precondition for the approval
prompt; jury PASS alone does not transition status.

**R6: Phase 4 jury structure.** Phase 4 spawns two parallel review
agents (using the Agent tool with `run_in_background: true`, matching
the `/strategy` Phase 4 pattern), each writing a verdict to
`wip/research/brief_<topic>_phase4_<role>.md`:

- **Content-quality reviewer.** Verifies the Problem Statement states
  a problem, not a smuggled solution; the User Outcome is
  outcome-shaped, not a feature list; each User Journey is concrete
  (named user, trigger, outcome shape) and the journeys are distinct;
  the Scope Boundary has explicit in/out and the OUT items are real
  exclusions; Open Questions (if present) genuinely defer to the
  downstream PRD and don't hide blockers.
- **Structural-format reviewer.** Verifies all R2 required sections
  are present and in order; frontmatter fields and status value are
  valid; the body `## Status` first word matches the frontmatter
  status; the document is public-visibility clean (no private paths,
  repos, filenames, or issue numbers; no `upstream:` to a private
  artifact); writing-style rules are honored.

There is no altitude reviewer; briefs aren't altitude-sensitive the
way the strategy type is (see Decision 4 in the upstream brief's scope
and Decision 3 here). Verdict aggregation matches the `/strategy`
pattern: both PASS to proceed; minor issues are fixed in place by the
authoring agent with a brief user-facing summary; a FAIL with
significant issues surfaces to the user via AskUserQuestion with the
option to loop back to drafting.

**R7: Brief-specific artifact-decision prose.** The `/brief` skill's
phase prose includes a decision the author hits when the tactical
chain is entered partway up (for example, from a rich issue body that
already implies the problem and the outcome): produce a durable brief
artifact when the framing warrants recording, or pass the existing
evidence forward to the PRD when authoring a separate document would
be ceremony. This is the brief-specific instance of the decision; the
general per-skill artifact-decision contract across every tactical
skill is out of scope (see Out of Scope).

**R8: `shirabe validate` Formats-map entry.** Add `brief/v1` to the
`Formats` map in `internal/validate/formats.go`:

```go
"brief/v1": {
    Name:          "Brief",
    Prefix:        "BRIEF-",
    SchemaVersion: "brief/v1",
    RequiredFields: []string{"status", "problem", "outcome"},
    ValidStatuses:  []string{"Draft", "Accepted", "Done"},
    RequiredSections: []string{
        "Status",
        "Problem Statement",
        "User Outcome",
        "User Journeys",
        "Scope Boundary",
    },
},
```

The existing `DetectFormat` longest-prefix-match routing picks up
`BRIEF-*.md` files automatically; no detection change is needed.
Checks FC01 (required fields), FC02 (valid statuses), FC03
(frontmatter status matches body Status), and FC04 (required sections
present) activate with no Go code beyond the map entry. No custom
check and no new error code are added: BRIEF has no visibility-gated
section.

**R9: Bootstrapping constraint.** The already-shipped
`docs/briefs/BRIEF-shirabe-strategy-skill.md` must pass `shirabe
validate` with exit code 0 once the R8 entry lands. The R8
`RequiredFields` (`status`, `problem`, `outcome`) and `RequiredSections`
(the five R2 sections) are chosen so that document validates: its
frontmatter carries `status`, `problem`, and `outcome`, and its body
carries all five required sections plus the three R3 optional ones.
This is a hard constraint, not a preference; any change to R1, R2, or
R8 must preserve it.

**R10: CI validation enablement.** The reusable validation workflow in
`.github/workflows/` shells out to `shirabe validate` on PR-changed
files matching its `paths:` filter. No workflow code changes are
required for BRIEF validation to activate; the Formats-map entry (R8)
is the load-bearing change.

- **Shirabe self-caller** (`validate-shirabe-docs.yml`) already
  path-filters on `docs/**`, so it picks up
  `docs/briefs/BRIEF-*.md` automatically.
- **Release-notes obligation.** The shirabe release that ships the
  Formats-map entry calls out that adopter workflows path-filtering
  narrowly need to widen the filter to include `docs/briefs/**` to
  pick up BRIEF documents on PR.

**R11: Shirabe CLAUDE.md guidance.** Add a short paragraph to
shirabe's CLAUDE.md explaining when to reach for a brief versus a PRD:
the brief frames a single feature's problem, outcome, journeys, and
scope before requirements exist; the PRD captures the requirements
once the framing is settled. Add a light `/explore` routing-table
touch placing the brief between the roadmap and the PRD in the
tactical chain.

### Non-Functional Requirements

**R12: Skill structure consistency.** The `/brief` skill follows
existing shirabe skill conventions: SKILL.md is plain English, phase
files use progressive disclosure, intermediates live in `wip/`, and
the cleanup phase deletes `wip/` artifacts before the PR can merge per
the workspace-wide wip-hygiene rule.

**R13: No new validation infrastructure.** All validation reuses the
existing `internal/validate/` package and the existing reusable
validation workflow. No new CLI binary, no parallel validation
pipeline, no new GitHub Actions reusable workflow, no custom check.

**R14: Evals coverage.** The `/brief` skill ships with evals at
`skills/brief/evals/evals.json` covering the structural happy path, a
missing-required-section rejection path, and an invalid-status
rejection path. Evals follow the format documented in shirabe's
CLAUDE.md.

## Acceptance Criteria

- [ ] `skills/brief/references/brief-format.md` exists and defines the
  frontmatter schema, required/optional sections, lifecycle states,
  validation rules, and per-section quality guidance, following the
  skeleton of `strategy-format.md` and `prd-format.md`.
- [ ] `skills/brief/SKILL.md` exists and runs end-to-end against a
  fresh repo (manual smoke test plus evals scenarios passing).
- [ ] `skills/brief/references/phases/` contains phase files for Phase
  0 through Phase 5, with Phase 4 specifying the two-reviewer jury
  structure named in R6 and Phase 0 carrying the artifact decision
  named in R7.
- [ ] `internal/validate/formats.go` includes the `brief/v1` entry
  exactly as specified in R8.
- [ ] Running `shirabe validate` against a fresh `BRIEF-<name>.md` with
  all five required sections passes with exit code 0.
- [ ] Running `shirabe validate` against a `BRIEF-<name>.md` with a
  missing required section fails with an FC04 error.
- [ ] Running `shirabe validate` against a `BRIEF-<name>.md` with an
  invalid status value fails with an FC02 error.
- [ ] Running `shirabe validate` against the already-shipped
  `docs/briefs/BRIEF-shirabe-strategy-skill.md` passes with exit code
  0 (the R9 bootstrapping constraint).
- [ ] The shirabe self-caller workflow `validate-shirabe-docs.yml`
  runs `shirabe validate` against changed `docs/briefs/**` files on PR
  (no workflow file changes needed; the path filter already covers
  `docs/**`).
- [ ] shirabe's CLAUDE.md includes a paragraph explaining when to use
  BRIEF versus PRD, and the `/explore` routing table places the brief
  between the roadmap and the PRD.
- [ ] `skills/brief/evals/evals.json` exists with at least three
  scenarios covering the cases named in R14, and `scripts/run-evals.sh
  brief` reports all assertions passing.

## Out of Scope

This PRD scopes the standalone `/brief` skill, the BRIEF artifact
type, and the validation infrastructure needed to make both
first-class. The scope explicitly excludes:

- **The `/scope` parent-skill integration.** A parent skill that
  delegates to `/brief` as a child phase is downstream design
  territory. The standalone `/brief` invocation is the primary mode at
  ship-time; the parent integration lands later as separate feature
  work.
- **The general per-skill artifact-decision contract.** A later
  feature generalizes the produce-versus-hand-off decision across
  every tactical skill. This PRD ships only the brief-specific prose
  (R7), not the general mechanism.
- **Any new visibility-gated section or custom validate check.** BRIEF
  has no equivalent of the strategy type's competitive framing, so no
  `checkBriefPublic`-style check and no new validate error code are
  added.
- **Migration of existing artifacts.** This work adds BRIEF without
  changing the shape, naming, validation, or lifecycle of VISION,
  STRATEGY, ROADMAP, PRD, DESIGN, or PLAN.
- **Cross-repo BRIEF upstream validation.** A check that verifies the
  `upstream:` path exists and is git-tracked is not extended to BRIEF
  in this PRD; a brief's upstream may be cross-repo, which such a check
  would incorrectly reject. Cross-repo upstream validation is a
  separate initiative.
- **Adoption tracking outside the reference fleet.** Whether external
  shirabe adopters reach for BRIEF is a downstream signal worth
  measuring but isn't a requirement this PRD must satisfy.

## Decisions and Trade-offs

### Decision 1: Required frontmatter fields are status, problem, outcome

**Decision.** The `brief/v1` schema requires exactly three frontmatter
fields: `status`, `problem`, `outcome`. `schema` is the map key, not a
checked field. `upstream` is optional.

**Alternatives considered.**

- *Add `upstream` as required.* Rejected: a public brief whose
  motivating upstream is a private artifact must omit the field
  entirely (the visibility rule), so requiring it would make
  correctly-sanitized public briefs fail validation.
- *Require only `status`.* Rejected: `problem` and `outcome` are the
  brief's load-bearing summary; the PRD precedent requires `status`,
  `problem`, `goals`, and the brief mirrors that shape with `outcome`
  in place of `goals`.

**Rationale.** Mirrors the PRD's `status`, `problem`, `goals` triple.
The already-shipped `BRIEF-shirabe-strategy-skill.md` carries exactly
`status`, `problem`, `outcome` in frontmatter, so this set satisfies
the R9 bootstrapping constraint.

### Decision 2: Status plus the four content sections are required; Open Questions, Downstream Artifacts, and References are optional

**Decision.** Required sections are Status, Problem Statement, User
Outcome, User Journeys, and Scope Boundary. Open Questions, Downstream
Artifacts, and References are optional.

**Alternatives considered.**

- *Make all eight sections required.* Rejected: a lean brief
  authored mid-chain may have no open questions and no downstream
  artifacts yet, and forcing empty sections is noise. Optional
  matches the PRD precedent, where Open Questions and Downstream
  Artifacts are explicitly optional.
- *Make only the four content sections required (drop Status).*
  Rejected: every shirabe artifact type requires Status, and FC03
  needs a body `## Status` section to match against the frontmatter.

**Rationale.** The four content sections are the brief's whole point;
Status is required across every type. Keeping the remaining three
optional both matches the PRD precedent and satisfies R9 — the
existing brief carries all three optional sections, and validation
accepts supersets of the required set.

### Decision 3: Two-reviewer jury, no altitude reviewer

**Decision.** Phase 4 runs two parallel reviewers — content-quality
and structural-format. There is no altitude reviewer.

**Alternatives considered.**

- *Three reviewers mirroring STRATEGY (add altitude).* Rejected:
  STRATEGY's altitude reviewer checks that the document operates at
  medium-term defensibility without re-justifying the long-term thesis
  or pre-sequencing features. A brief frames a single named feature;
  there is no altitude band to police, so a third reviewer would have
  no distinct rubric.
- *One combined reviewer.* Rejected: content quality and structural
  conformance are distinct rubrics, and folding them into one reviewer
  loses the independent-judgment property the jury depends on.

**Rationale.** The two rubrics that matter for a brief are whether the
content is well-shaped (problem is a problem, outcome is an outcome,
journeys are concrete, scope is explicit) and whether the structure
conforms (sections, frontmatter, visibility). Both are real and
distinct; a third reviewer has no job.

### Decision 4: Three-state lifecycle, no directory movement

**Decision.** BRIEF uses Draft → Accepted → Done, with no directory
move on any terminal state. It mirrors PRD's lifecycle, not VISION's
or STRATEGY's.

**Alternatives considered.**

- *Four-state with Active/Sunset (mirroring STRATEGY).* Rejected:
  Active and Sunset exist for falsifiable bets that can be invalidated
  by external events. A brief frames a feature; it doesn't make a bet
  that can fail, so there's nothing to Sunset.
- *Move the file to a `done/` subdirectory on Done.* Rejected: PRDs
  stay in place on Done, and the brief mirrors PRD. Directory movement
  on terminal state is a ROADMAP/PLAN working-artifact convention; the
  brief is a durable artifact like the PRD.

**Rationale.** A brief is a durable framing artifact consumed by its
downstream PRD. Done means the PRD has operationalized it, not that
the brief is invalid. PRD's terminal-state semantics fit; VISION's and
STRATEGY's do not.

### Decision 5: Six-phase skill structure mirroring /strategy

**Decision.** The `/brief` skill exposes six phases (Phase 0 through
Phase 5), the same structure `/strategy` uses, as specified in R5.

**Alternatives considered.**

- *Fewer phases (collapse discovery, drafting, and structural fill).*
  The brief's content is simpler than a strategy's — four sections, no
  altitude dimension — which could argue for a shorter path. Rejected:
  the phase count tracks the *authoring stages* (setup, discovery,
  draft, structural fill, jury, finalize), not the number of content
  sections. Those stages apply to a brief as much as to a strategy;
  collapsing them would diverge from the precedent without removing
  real work.
- *More phases (a dedicated artifact-decision phase).* Rejected: the
  brief-specific artifact decision (R7) fits inside Phase 0 setup,
  where upstream detection and entry-mode selection already live. A
  standalone phase would split a single early decision across two
  phases.

**Rationale.** Pattern fidelity: `/strategy` and `/decision` both use
this phase shape, and the brief's authoring stages are the same. The
simpler section content lives inside the drafting phases, not in a
different phase count. This closes the brief's third open question.

## Downstream Artifacts

Forthcoming work flowing from this PRD:

- **`DESIGN-shirabe-brief-skill.md`** (in `docs/designs/current/`).
  Implementation specifics — file layouts under `skills/brief/`, phase
  file contents, the Go-side `FormatSpec` literal and test fixtures,
  the artifact-decision prose, and the CLAUDE.md guidance text. Picks
  up the Decisions and Trade-offs positions and operationalizes them.
- **`skills/brief/scripts/transition-status.sh`** — per-skill
  lifecycle transition script following the precedent of
  `skills/strategy/scripts/transition-status.sh`. Handles Draft →
  Accepted, Accepted → Done, with no directory move.
- **Release notes** for the shirabe version that ships the Formats-map
  entry, calling out the path-filter widening adopters may need (per
  R10).
- **Implementation issues** — created from the design via `/plan`,
  covering skill authoring, format-reference authoring, validate-CLI
  changes, transition-script authoring, CLAUDE.md update, and evals
  authoring.

## Related

- **Upstream brief:** `docs/briefs/BRIEF-shirabe-brief-skill.md`.
- **Proof-by-example and structural template:**
  `docs/briefs/BRIEF-shirabe-strategy-skill.md` (the R9 bootstrapping
  constraint protects this document).
- **Precedents the artifact type mirrors:** `/strategy`
  (`skills/strategy/`), `/prd` (`skills/prd/`), and the `/strategy`
  Phase 4 jury pattern.
- **Validation precedents:** `internal/validate/formats.go` (Formats-map
  pattern), `internal/validate/checks.go` (FC01-FC04 check logic).
- **Cross-repo reference rules:** `references/cross-repo-references.md`
  (governs how BRIEF's `upstream:` value resolves cross-repo).
