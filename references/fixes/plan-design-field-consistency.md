# PLAN/DESIGN Field Consistency Resolution

Canonical resolution guidance for FC12 notices fired by the
validator's `check_plan_design_field_consistency` function. FC12
detects field-name conflicts across a PLAN's issue ACs and the
structural rubrics declared by its upstream DESIGN.

This file is dereferenced on-demand by FC12 notice text; readers
arrive here from `[FC12] ... see references/fixes/plan-design-field-consistency.md`.

## What an FC12 notice means

FC12 fires when:

- A PLAN issue AC names a field that is also referenced in the
  upstream DESIGN's structural rubrics (e.g. a DESIGN-declared
  required field, a state-machine field, a frontmatter schema
  entry), AND
- The AC's treatment of that field disagrees with the DESIGN's
  declaration (e.g. AC declares the field as free-text but DESIGN
  declares it as a closed enum; AC adds a field DESIGN omits; AC
  drops a field DESIGN requires).

The notice text names the field, the conflicting positions, and
their line numbers. FC12 is a notice (not an error) because the
validator cannot determine which side is authoritative without
human judgment.

## Which side to align

The default is: **align the PLAN to the DESIGN.** A PLAN
operationalizes a DESIGN; the DESIGN is the upstream contract. A
PLAN that introduces a field DESIGN omitted, or contradicts a field
DESIGN declared, is implementing something other than the DESIGN.

Three exceptions to the default:

1. **The DESIGN is stale.** If the PLAN was authored against a
   revised DESIGN whose frontmatter is `Accepted` but whose body
   does not yet reflect the revision, the DESIGN is the side to
   update. Verify by checking the DESIGN's commit log; if a
   revision commit is newer than the body change, the body is
   stale.
2. **The DESIGN was deliberately ambiguous.** Some DESIGNs declare
   a field's shape at high altitude and defer the concrete schema
   to the PLAN ("the worker accepts a config blob; the PLAN defines
   the keys"). In that case the PLAN is the authoritative source
   and the FC12 notice can be suppressed via a comment in the AC
   block.
3. **The conflict is intentional disambiguation.** A PLAN issue
   may need to override a DESIGN field to handle an edge case the
   DESIGN didn't enumerate. Record the rationale in the AC body
   itself ("DESIGN declares status as a free-text string; this
   issue narrows it to the four lifecycle states per the
   downstream FormatSpec"), then suppress.

## When to rewrite the AC

Rewrite the AC (default path) when:

- The DESIGN's declaration is correct and the AC drifted by
  accident.
- The DESIGN was revised and the PLAN was authored against an
  older draft.
- The AC introduces a field the DESIGN deliberately omitted (the
  AC is climbing into DESIGN territory).

The rewrite preserves the AC's intent but conforms to the DESIGN
field's name, type, and enum set.

## When to revise the DESIGN

Revise the DESIGN when:

- The PLAN-authoring pass surfaced a real gap in the DESIGN (a
  field the DESIGN should have declared but didn't).
- The downstream implementation reveals the DESIGN field is
  miscalibrated (e.g. a closed enum should be an open set).
- A schema-version bump landed mid-flight and the DESIGN body did
  not cascade.

The DESIGN revision is a separate commit on the DESIGN doc; the
PLAN is then re-validated against the updated DESIGN and FC12
should clear.

## Suppressing intentional conflicts

When the conflict is intentional disambiguation (case 3 above),
the AC body must record the rationale prose. The FC12 notice
itself does not have a `# suppress-fc12` mechanism (notices are
informational; suppression lives in author judgment). Reviewers
seeing FC12 fire should read the AC body to determine whether
the conflict is intentional.

## Common patterns

- **Enum mismatch.** DESIGN: `status: Draft|Accepted|Done`; AC:
  `status accepts any string`. Default: rewrite AC.
- **Field omission.** DESIGN declares `upstream:` required; AC
  does not mention it. Default: rewrite AC to add the field.
- **Field addition.** DESIGN omits `motivating_context:`; AC
  declares it required. Default: revise DESIGN if the field is
  load-bearing; rewrite AC if speculative.
- **Type drift.** DESIGN: `issue_count: integer`; AC: `issue_count
  is a string`. Default: rewrite AC.
