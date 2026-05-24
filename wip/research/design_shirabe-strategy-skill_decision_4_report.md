# Decision 4: STRATEGY R7 Custom Check Implementation Shape

## Question

How should the visibility-gated `Competitive Considerations` enforcement for
`strategy/v1` be implemented in `internal/validate/checks.go`, in terms of:

1. Function name
2. Error code (reuse `R7`, or claim a new code such as `R8`?)
3. Dispatch point in `ValidateFile`'s format-specific switch
4. Whether to generalize `checkVisionPublic` into a shared
   `checkVisibilityGatedSections` helper or duplicate the per-format function
5. Which section name(s) `strategy/v1` forbids in public visibility

## Considered Options

### Q1/Q3: Function name and dispatch shape

- **Option A: `checkStrategyPublic` dispatched in the existing switch.** Mirrors
  `checkVisionPublic` line-for-line. Adds one `case "Strategy":` arm in
  `ValidateFile`. Symmetric, immediately greppable.
- **Option B: Inline closure / lambda inside the switch.** Avoids a named
  function. Rejected: harms testability, diverges from the established pattern
  (every other check is a top-level `checkXxx` function), and breaks the
  PRD R12 "no new validation infrastructure" intent of staying boring.

### Q2: Error code

- **Option A: Share code `R7`.** R7 is conceptually "section prohibited in
  public visibility for this format." Sharing keeps one mental tag for the
  visibility-gated section family; the `[R7]` message text already names the
  format (`"section %q is prohibited in public VISION docs"`), so STRATEGY's
  variant would read `"... in public STRATEGY docs"` and disambiguate by
  message.
- **Option B: New code `R8`.** Each numbered rule in shirabe corresponds to a
  distinct PRD requirement. R7 in `DESIGN-gha-doc-validation.md` was scoped to
  VISION's two sections; STRATEGY's `Competitive Considerations` is a separate
  PRD R7 line item in the STRATEGY PRD but a *new* rule from the validator's
  point of view. A distinct code lets users grep their logs by code to find
  failures specific to STRATEGY without false hits from VISION failures, and
  matches the existing convention where each numbered code maps 1:1 to a
  validator-side rule (`R6` = plan upstream; `R7` = VISION sections).
- **Option C: Shared code with discriminator suffix (`R7-STRATEGY`).** Rejected:
  no other check uses a compound code; introduces new parsing in any downstream
  tool that filters on `Code`.

### Q4: Duplicate vs generalize

- **Option A: Duplicate `checkVisionPublic` as `checkStrategyPublic`.** Two
  near-identical functions, each with its own prohibited-sections constant
  (`prohibitedPublicVisionSections`, `prohibitedPublicStrategySections`) and
  its own message string. ~20 lines duplicated.
- **Option B: Generalize into `checkVisibilityGatedSections(doc, cfg, format,
  prohibited)`.** Single helper; per-format wrappers (or a table in
  `FormatSpec`) supply the list. Reduces duplication for a future third
  consumer.
- **Option C: Add `ProhibitedPublicSections []string` to `FormatSpec` and run
  the check unconditionally in `ValidateFile` when the slice is non-empty.**
  Most elegant; pushes the data into the format table and removes the switch
  arm entirely.

## Decision Outcome

**Chosen:**

1. Function name: `checkStrategyPublic`
2. Error code: **`R8`** (new code, not shared with VISION's R7)
3. Dispatch: add `case "STRATEGY":` arm in `ValidateFile`'s format switch,
   alongside the existing `case "VISION":` arm
4. **Duplicate the pattern** (Option A). Defer generalization until a third
   visibility-gated format appears.
5. Forbidden section in public visibility: `Competitive Considerations`
   (single-element slice, mirroring VISION's two-element slice)

### Sketch

```go
// prohibitedPublicStrategySections lists section names that strategy/v1 docs
// must not contain in public repos. See DESIGN-shirabe-strategy-skill.md (R8).
var prohibitedPublicStrategySections = []string{
    "Competitive Considerations",
}

// checkStrategyPublic (R8) flags STRATEGY docs that surface sections forbidden
// in public repos. Bypassed only when cfg.Visibility == "private"; any other
// value (including empty) fails closed.
func checkStrategyPublic(doc Doc, cfg Config) []ValidationError {
    if cfg.Visibility == "private" {
        return nil
    }
    prohibited := make(map[string]bool, len(prohibitedPublicStrategySections))
    for _, name := range prohibitedPublicStrategySections {
        prohibited[name] = true
    }
    var errs []ValidationError
    for _, sec := range doc.Sections {
        if prohibited[sec.Name] {
            errs = append(errs, ValidationError{
                File:    doc.Path,
                Line:    sec.Line,
                Code:    "R8",
                Message: fmt.Sprintf("[R8] section %q is prohibited in public STRATEGY docs", sec.Name),
            })
        }
    }
    return errs
}
```

`ValidateFile` switch (in `validate.go`):

```go
switch spec.Name {
case "Plan":
    errs = append(errs, checkPlanUpstream(doc)...)
case "VISION":
    errs = append(errs, checkVisionPublic(doc, cfg)...)
case "STRATEGY":
    errs = append(errs, checkStrategyPublic(doc, cfg)...)
}
```

### Rationale

- **Distinct `R8` over shared `R7`.** Existing convention: each numbered code
  is one validator rule. VISION's two sections are governed by a single check;
  STRATEGY's section is governed by a separate check with a separate prohibited
  list. Operators filtering CI logs by `Code` get clean separation. The cost
  is one more entry in the code registry, which is trivial. Shared codes would
  be a small ergonomic win at the price of muddying a clean convention this
  early in the validator's life.
- **Duplicate, don't generalize.** YAGNI. There is exactly one prior consumer
  (`checkVisionPublic`); generalizing for a single future case is premature.
  Duplication today costs ~20 lines and zero design overhead. If a third
  visibility-gated artifact appears (which the PRD anticipates is plausible
  within 6 months given the strategy family is expanding), the *second*
  duplication is the trigger to refactor to either Option B (helper) or
  Option C (FormatSpec field). Refactoring with three concrete call sites
  produces a better abstraction than guessing with one.
- **Switch dispatch over FormatSpec-table approach.** Keeps format-specific
  logic next to the other format-specific logic (`checkPlanUpstream`,
  `checkVisionPublic`). The FormatSpec table is structural metadata; pushing
  visibility logic into it conflates static structure with policy. The switch
  is the right place for now.
- **Function name `checkStrategyPublic`.** Naming convention is `check<Name>`
  where `<Name>` matches the PRD requirement identifier or format name. The
  VISION precedent `checkVisionPublic` is unambiguous.

## Assumptions

- The STRATEGY format will be added to `Formats` with `Name: "STRATEGY"` (caps
  matching `VISION`).
- `strategy/v1` will be the schema version string.
- Only one section (`Competitive Considerations`) is forbidden in public
  visibility for the initial release. Future additions extend the slice without
  schema changes.
- `cfg.Visibility` plumbing is already implemented end-to-end (verified in
  `main.go:101`) and STRATEGY consumes it as-is with no CLI changes.
- The PRD's R7 phrasing ("same enforcement pattern VISION uses") refers to the
  *mechanism*, not the *code*; the design doc can use any error code it picks.

## Rejected Alternatives

- **Share error code `R7` across VISION and STRATEGY.** Rejected: breaks the
  one-code-per-rule convention; complicates log filtering; the message-string
  disambiguation is fragile (some downstream consumers parse `Code`, not
  `Message`).
- **Inline lambda in the switch.** Rejected: harms testability and breaks the
  top-level `checkXxx` pattern every other check follows.
- **Generalize into `checkVisibilityGatedSections` helper now.** Rejected: one
  prior consumer is not a pattern; speculative abstraction. Revisit when a
  third visibility-gated format lands.
- **`ProhibitedPublicSections []string` field on `FormatSpec`.** Rejected for
  the same reason as above, plus it conflates static schema with visibility
  policy. Worth revisiting in a future refactor pass if a third consumer
  appears.
- **Compound error code `R7-STRATEGY`.** Rejected: no precedent in the
  validator; introduces parsing complexity downstream for no real gain.
