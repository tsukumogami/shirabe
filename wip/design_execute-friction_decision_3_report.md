# Decision D3: Which layer owns the docs-coverage guarantee (PRD R3), and what signal detects "this plan adds user-visible surface"?

## Options Considered

**Owner options:**

- **A. /plan owns it.** /plan already reads the full DESIGN body (Phase 4
  step 4.2 reads the whole design doc into agent prompts; Phase 1 analysis
  parses it for components). It is the only layer that decomposes the design
  into issues and is therefore the only layer that can EMIT a docs work item
  derived from the design's user-visible surface. It already routes a
  first-class `Type: docs` issue end-to-end (plan-doc-structure.md:209-231,
  plan-to-tasks.sh ISSUE_TYPE).
- **B. /execute owns it (content-completeness gate before done-signal).**
  Rejected — violates /execute's metadata-only inspection contract.
- **C. /work-on owns it (per-issue).** Rejected — /work-on sees one issue at
  a time; it has no view of the whole design's surface and cannot tell that a
  docs issue is *missing* from the set.

**Detection-signal options:**

- **S1. Structured frontmatter flag** `user_visible_surface: true` on the
  DESIGN (and/or PRD).
- **S2. Prose grep** for a `docs/guides/*` reference in the DESIGN body.
- **S3. Both** — structured flag as the authoritative signal, prose
  `docs/guides/*`-reference as a fallback when the flag is absent (back-compat
  with already-authored designs).

## Chosen Option (owner + signal)

**Owner = /plan.** /plan emits the docs work item in Phase 3 decomposition,
and a Phase 6 (review-plan Category A / Scope Gate) backstop flags the gap if
the emit was skipped. **/execute keeps NO content-level docs gate** — at most
the existing metadata-only state surface, which already cannot read child
bodies, so a "docs coverage" content check there is out of contract.

**Signal = S3 (both, flag-authoritative + prose fallback).** A structured
`user_visible_surface: true` frontmatter field is the clean, reliable
primary; a `docs/guides/*` prose reference in the DESIGN body is the fallback
so the guarantee still fires on designs authored before the field exists.
Rationale: the frontmatter schemas (design-format.md:43, prd-format.md) are
small, validator-checked field sets — adding one boolean is low-cost and
deterministic to read. Pure prose-grepping (S2 alone) is brittle: a design
can add user-visible surface without literally writing `docs/guides/`, and a
`docs/guides/` mention can appear in unrelated context (e.g. "unlike the
existing docs/guides/ flow"). The flag makes intent explicit; the prose
fallback preserves coverage during migration.

## Concrete Mechanism

**1. Frontmatter field addition (signal source).**
Add an optional boolean `user_visible_surface` to the DESIGN frontmatter
schema, written by `/design`:

- File: `skills/design/references/design-format.md` — add
  `user_visible_surface: true|false  # optional` to the frontmatter block
  (after `motivating_context`), documented as: "true when this design
  introduces or changes CLI surface or behavior a user reads about in a
  guide." Designs that omit it default to "unknown — fall back to prose
  scan."
- `/design`'s authoring phase sets it. Same field MAY be mirrored into
  `skills/prd/references/prd-format.md` so a PRD-input plan has the signal
  too; the DESIGN is the primary writer since it is the body /plan reads in
  full.

**2. Detection contract (read by /plan).**
In `skills/plan/references/phases/phase-3-decomposition.md`, in the Standard
Decomposition section (after step 3.1 "Decompose by Component"), add a
**docs-coverage emit step**:

> After component decomposition, determine whether the source adds
> user-visible surface:
> 1. If frontmatter `user_visible_surface: true` → user-visible surface present.
> 2. Else if `user_visible_surface` is absent AND the DESIGN body references a
>    `docs/guides/*` path → user-visible surface present (prose fallback).
> 3. Else → no user-visible surface; skip.
>
> When present, ensure the decomposition includes at least one issue whose
> work covers the user-facing documentation — either a dedicated
> `**Type**: docs` issue, or an explicit docs deliverable folded into a
> covering issue's acceptance criteria. Record which issue carries docs
> coverage in the decomposition artifact.

This rides the existing `Type: docs` machinery (no new routing) — the emitted
item is just an outline with `**Type**: docs`, which plan-to-tasks.sh already
maps to `ISSUE_TYPE=docs` and which /work-on already routes to the docs path.

**3. Phase 6 backstop (cannot pass silently).**
In `skills/review-plan/` Category A (Scope Gate, the completeness reviewer),
add one check: if the source signals user-visible surface (same two-step
detection contract) and no issue in the decomposition carries docs coverage,
emit a critical finding → loop-back to Phase 3. This is the forcing function
that makes the gap fail loudly rather than pass. Minimal touch: one finding
rule in the Category A reviewer's prompt/criteria, reusing the detection
contract defined in step 2.

**Net file changes (minimal):**
- `skills/design/references/design-format.md` — add `user_visible_surface`
  field (+ `/design` authoring sets it).
- `skills/prd/references/prd-format.md` — mirror the optional field (PRD-input
  path).
- `skills/plan/references/phases/phase-3-decomposition.md` — docs-coverage
  emit step + detection contract.
- `skills/review-plan/` Category A — one backstop finding rule.

## Why not in /execute

`/execute`'s Child Inspection contract (skills/execute/SKILL.md:418-435)
states it inspects "issue, pull-request, and unit state **only through status
surfaces** — never by reading child artifact bodies (R14 widened, R15)." Its
only inspection inputs are "the validator and merge-gate results, lifecycle
status, and content fingerprints." A docs-coverage check is inherently a
*content-completeness* question — "does the produced documentation actually
cover the user-visible surface?" — which requires reading child bodies (the
guide, the issue body). That is precisely the read /execute is forbidden from
doing. Placing the guarantee in /execute would force a contract violation, so
/execute keeps at most a metadata-only posture and does not own R3. The
guarantee belongs upstream, at the only layer (/plan) that reads the design
body where the signal lives and that produces the issue set where a docs item
can be added before the run ever reaches a done-signal.

## Open Risks

- **Prose-fallback false positives/negatives.** A `docs/guides/*` mention in
  rejected-option prose could trip the fallback (false positive → an unneeded
  docs issue, low harm), and a design adding surface without the literal path
  string would miss the fallback (false negative). The structured flag is the
  mitigation; the fallback is only for un-migrated designs. Risk decays as
  `/design` populates the flag going forward.
- **PRD-input plans.** When /plan runs on a PRD (input_type: prd) rather than
  a DESIGN, the signal must live on the PRD. Mirroring the field to
  prd-format.md covers this, but the PRD body is less of a "surface spec" than
  a DESIGN, so the flag (not prose fallback) should be the primary signal
  there.
- **Topic-input plans** (no upstream doc) have no frontmatter to read; the
  emit step degrades to "no signal → skip," and docs coverage falls to author
  judgment. Acceptable: R3 is scoped to plans derived from a design/PRD.
- **Backstop is advisory, not a hard validator.** Category A is an AI
  reviewer, not a deterministic CLI check, so the backstop's reliability is
  bounded by the reviewer. The Phase 3 emit step is the primary guarantee; the
  backstop is the second net, consistent with how /plan already layers
  generation + review rather than relying on a single gate.
