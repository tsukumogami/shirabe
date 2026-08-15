<!-- decision:start id="conditional-required-field" status="decided" -->

## Context

PRD R13 requires a PLAN to carry a shape-record field whenever `execution_mode`
is not `single-pr`, OR `execution_mode` differs from what the repository's
resolved delivery preference would have produced. R15 exempts the common case
(single-pr matching the preference). R16 makes the finding draft-tolerant:
non-blocking on a draft PR, blocking once ready.

`formats.rs`'s `FormatSpec.required_fields` (checked by FC01) is a flat,
always-required list evaluated purely from the doc's own frontmatter — no
filesystem I/O, no repo config. `execution_mode_required_sections` is the one
existing conditional mechanism on `FormatSpec`, but it is *also* doc-local: it
branches on the doc's own `execution_mode` value and reads nothing outside the
file. R13's second condition (departure from the resolved preference) is
categorically different — it requires walking up from the doc to a CLAUDE.md
and parsing a header, the same mechanism `visibility.rs`'s
`resolve_claude_md_header` already generalizes for the visibility and
prose-vocabulary headers.

`validate.rs`'s `posture_class()` currently names exactly three codes —
`L02`, `L06`, `L07` — as `DraftTolerable`, and every doc comment describing
the draft-tolerable set states it as "the lifecycle in-flight findings," not
as an open family. Those codes live in `lifecycle.rs`'s whole-corpus
traversal (`build_doc_index` → `discover_chains` → obligation map), which
`is_known_check_code`'s own doc comment says is produced by the `--lifecycle`
traversal mode, *not* the per-file `validate` pass.

The Known Limitations section names this exact gap and calls the two-part
question (conditional-field mechanism vs. check-location; CLAUDE.md-read
cost) a DESIGN decision this document owns.

## Assumptions

- R1-R3's delivery-preference resolution (a new CLAUDE.md convention header,
  parsed the same way `## Repo Visibility:` is) exists as a function this
  check can call; this decision does not re-derive R1-R3, only how the R13
  check consumes their result.
- The AC's phrasing — "`shirabe validate` on a non-`single-pr` PLAN missing
  the R13 field reports a finding" — describes the ordinary per-file
  `validate <file>` invocation, the same phrasing pattern used for every
  other per-file FC finding in this PRD's AC list, not the separate
  `--lifecycle` traversal mode.

## Chosen

**Alternative B, refined**: a new per-file, Plan-only structural check in
`checks.rs`, dispatched in `validate_structural`'s `"Plan"` match arm
alongside FC14/FC17, with its own code — the next unused FC number, `FC20` —
registered as `DraftTolerable` in `validate::posture_class()`. It is *not*
implemented as an `L`-family lifecycle check and does not live in
`lifecycle.rs`.

Internally the check short-circuits before touching the filesystem: if
`execution_mode != "single-pr"`, R13's first disjunct is already satisfied
and the field is required without reading any CLAUDE.md. Only when
`execution_mode == "single-pr"` does it call the R1-R3 preference resolver
(built on `visibility::resolve_claude_md_header`, the same generic walker
`resolve_doc_visibility` and `resolve_prose_vocabulary` already share) to
decide whether the plan departed from the resolved preference.

`required_fields` and `execution_mode_required_sections` on `FormatSpec` are
left untouched. `FormatSpec` gains nothing for this feature.

## Rationale

1. **Why not extend `FormatSpec` (rejected A).** Every existing consumer of
   `FormatSpec` — `required_fields` via FC01, `execution_mode_required_sections`
   via FC04 — is answerable purely from the doc's own parsed frontmatter.
   `formats()` builds every `FormatSpec` with zero I/O. Folding a
   CLAUDE.md-reading condition into that struct means either (a) giving
   `FormatSpec` a closure/enum field that can perform filesystem reads,
   which turns a declarative structural table into something with hidden
   I/O for one field of one of eight formats, or (b) threading `Config`/repo
   context through `check_fc01`, which today is `(doc, spec)` with no `cfg`
   parameter at all, for a change only Plan needs. Either way the module's
   own contract — "Structural contract for a single shirabe doc format,"
   documented as doc-local even in the `execution_mode_required_sections`
   doc comment — breaks for every format to serve one.

2. **Why not a sentinel value (rejected C).** R15 exists specifically so the
   common case carries no new field at all; a permitted sentinel keeps a
   field present-but-meaningless in that case, which is a different shape
   than "absent," adds a value both authors and the check must special-case,
   and has no support anywhere in the PRD (R19, R20, and the "Free text
   rather than an enumeration" trade-off all argue the opposite direction:
   minimize new required structure in the common path).

3. **Why not two split checks/codes (rejected literal D, kept its
   optimization).** D's instinct — the doc-local half doesn't need a
   CLAUDE.md read — is correct and I keep it as the short-circuit inside one
   check function. But making it two *checks with two codes* over-fits the
   AC: every AC bullet for the shape record speaks of "a finding" singular
   for the same underlying fact ("the field is missing," full stop), never
   two distinguishable outcomes. Two codes would double what
   `references/fixes/claude-md-conventions.md`-adjacent docs and `--check`
   selection would need to describe, for a distinction no AC or user story
   asks a reader to make. One check, one code, with the read skipped when
   it's provably unnecessary, gets D's efficiency without D's surface-area
   cost.

4. **Why FC-family, not a new `L09` (the real fork in the road).**
   `lifecycle.rs`'s traversal exists to answer questions that need the whole
   corpus graph — chain membership, posture inferred from a *root's* status,
   cross-document obligations. R13's departure condition needs none of that:
   it is one PLAN's own `execution_mode` plus a single upward CLAUDE.md walk,
   exactly the shape `resolve_doc_visibility` already handles as a per-file
   concern. Placing it in `lifecycle.rs` would make it reachable only through
   `--lifecycle`, per that module's own documented boundary — which would
   silently fail the AC's plain `shirabe validate <file>` framing. FC-family,
   dispatched in `validate_structural`'s existing `"Plan"` arm, is reachable
   exactly where the AC says it must be.

## Alternatives Considered

- **A. Extend `FormatSpec` with a conditional-required-fields mechanism.**
  Rejected — see Rationale 1. Breaks the doc-local invariant every existing
  `FormatSpec` consumer relies on, for the one format that needs
  filesystem I/O.
- **B. New lifecycle-style check, own code, added to `DraftTolerable`.**
  Chosen, with "lifecycle-style" narrowed to "own code, `DraftTolerable`
  classification" and explicitly *not* "lives in `lifecycle.rs` / requires
  the whole-corpus traversal." See Rationale 4.
- **C. Unconditionally required field with a sentinel value.** Rejected —
  see Rationale 2. Contradicts R15/R19/R20 in spirit and adds a state no
  requirement asks for.
- **D. Split into a doc-local FormatSpec part and a separate
  config-dependent check.** Partially adopted as an internal short-circuit,
  rejected as two separate checks/codes — see Rationale 3. Also inherits
  A's problem for its doc-local half if that half is expressed as a
  `FormatSpec` extension rather than folded into the one new check.

## Adversarial Pass

**The strongest case against this choice:** every doc comment in
`validate.rs` that describes the draft-tolerable set states it as a closed,
named triple — `PostureClass`'s doc comment says "The draft-tolerable set is
the lifecycle in-flight findings `L02` ... `L06` ... `L07`"; `is_intrinsic_notice`
and `posture_class`'s comments repeat the same framing; four separate unit
tests (`draft_tolerable_codes_are_notices_under_draft_only`,
`posture_class_classifies_lifecycle_codes`,
`effective_severity_draft_tolerable_flips_with_posture`, and the roll-up in
`is_notice_only_schema_and_fc_advisory_codes`) enumerate exactly
`["L02", "L06", "L07"]` as inline literals. Choosing FC20 as `DraftTolerable`
makes every one of those comments false the moment it lands, and a reviewer
skimming `posture_class` six months from now who trusts the comment over the
`match` arm will misread the invariant. That's a real, not cosmetic, cost:
comments in this file are treated as load-bearing documentation elsewhere in
the same crate (`formats.rs`'s doc comments are asserted against verbatim in
tests), so leaving them stale here is inconsistent with the codebase's own
practice.

**Answer:** the cost is real but bounded and one-time, and the alternative
that avoids it — `L09` in `lifecycle.rs` — has a worse, structural cost: it
would make the R16 finding invisible to a plain `shirabe validate <file>`
run, which is what the AC describes and what R16 itself says must gate the
PR ("blocking once ready" — the ready gate is the per-PR `validate` run, not
a separate corpus-wide job). Mechanically, `posture_class` is already just a
string match with no enforced constraint that its `DraftTolerable` arm stay
`L`-only — nothing prevents the addition; only the prose claims it's closed.
The correct response to that tension is to fix the prose, not to contort the
check's location to keep three-year-old comments accurate. This PRD is a
natural first case for exactly that kind of growth: R16's own posture split
(non-blocking draft / blocking ready) is *definitionally* what
`DraftTolerable` was built to express, and `PostureClass` was designed with
two variants, not one, for a reason. Implementation should update the four
comments and add FC20 to the enumeration in each of the four tests rather
than skip them — that's part of the check's own PR, not a follow-on.

## Consequences

- A new `FC20` check function in `checks.rs`, dispatched from `validate.rs`'s
  `"Plan"` arm in `validate_structural`, after FC14/FC17 (both of which it
  logically follows: FC14 already validates execution_mode-aware structural
  shape for Plan).
- `FC20` added to `posture_class()`'s `DraftTolerable` match arm in
  `validate.rs`, and *not* added to `is_intrinsic_notice` (it must actually
  gate at Ready, unlike the FC07-FC15/FC-CONVENTIONS notice-only set).
- `FC20` added to `is_known_check_code`'s registered set, so `--check FC20`
  is selectable the same way every other per-file structural code is.
- The four doc comments and four unit tests named in the Adversarial Pass
  need updating in the same PR to keep `L02`/`L06`/`L07`/`FC20` as the
  accurate `DraftTolerable` enumeration.
- The check calls the R1-R3 delivery-preference resolver only when
  `execution_mode == "single-pr"`; for every non-single-pr PLAN it never
  touches the filesystem beyond what parsing the doc already did.
- The validator does read the repository's resolved CLAUDE.md delivery
  preference for single-pr PLANs, accepting the Known Limitations drift risk
  (a preference change after authoring flips the finding without the plan
  changing) as-is — the PRD documents this as a deliberate, accepted cost,
  and dropping it would fail the AC bullet requiring a finding on a
  single-pr PLAN in an `atomic` repository.
- `FormatSpec`, `required_fields`, and `execution_mode_required_sections` are
  untouched by this feature.

<!-- decision:end id="conditional-required-field" -->
