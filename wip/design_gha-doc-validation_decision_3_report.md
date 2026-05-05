<!-- decision:start id="validation-check-structure" status="assumed" -->
### Decision: Validation Check Structure and Execution

**Context**

The shirabe CLI validates doc files against four universal checks (FC01-FC04) and
format-specific rules. FC01 checks required frontmatter fields, FC02 checks status
enum validity, FC03 checks frontmatter/body status sync (conditional on the Status
section's presence), and FC04 checks required section headings. Two format-specific
rules exist at launch: Plan's upstream file git-tracking check (R6) and VISION's
public-repo prohibited section check (R7). A schema version gate (R8) runs before
all checks and aborts the check sequence for unsupported files.

All errors are collected before exit (no fail-fast). The validator runs per-file
and accumulates errors across all files before exiting non-zero, with each error
becoming a GHA annotation.

The CLI is not yet built. This decision shapes the initial architecture of the
validation package.

**Assumptions**

- The CLI will have 2-5 formats at launch, with at most 1-2 new formats per year.
  If the format count grows to dozens, a registry becomes more attractive.
- Checks remain stateless per file — no check needs output from a preceding check
  (beyond the schema gate abort). If inter-check dependencies emerge, this needs
  revisiting.
- Decision 2 (module layout) will establish a separate `internal/validate` package
  where this logic lives.
- This decision runs in --auto mode without user confirmation, so status is "assumed".

**Chosen: Flat sequential functions**

A `validateFile(doc Doc, format FormatSpec, config Config) []ValidationError` function
calls each check directly in sequence. The schema gate is an early-return (`if
!supported { return nil }`). Universal checks are plain functions (`checkFC01`,
`checkFC02`, `checkFC03`, `checkFC04`) that accept a `FormatSpec` carrying per-format
configuration (required fields, accepted statuses, required sections). Format-specific
checks run under a `switch format.Name` block.

Per-format variation is primarily data-driven: which fields are required, which
sections are required, which statuses are valid. These live in a `FormatSpec` struct,
not in separate code paths. The behavioral variation (R6, R7) is two cases in a
switch — four lines total.

Each check function accepts `(Doc, FormatSpec, Config)` and returns `[]ValidationError`,
making it independently unit-testable without interface setup or registry initialization.

**Rationale**

The flat approach is the right fit for this scale. With 5 formats and 6 checks, the
registry's main benefit — "adding a format requires no central edit" — is a minor
convenience against a meaningful cost: global mutable state in `init()`, invisible
execution order, and registration boilerplate per check. Explicit beats implicit when
the call graph is small and stable.

The "must edit validateFile for a new format" concern is not a real burden: adding a
format always requires adding a `FormatSpec` entry, test cases, and format-specific
rule logic regardless of architecture. The only thing a registry saves is one `case`
in a switch.

Per-format structs add inheritance-like coupling without benefit — universal checks
are data-parameterized, not behavior-polymorphic, so embedding a `BaseValidator`
adds indirection without reducing repetition. The pipeline/middleware approach
threads an accumulator through every step and adds short-circuit booleans that are
only natural when step composition is genuinely dynamic; here the check set is
statically known.

The flat approach is also the most debuggable: any reader can see what runs, in what
order, with no registration indirection or middleware wrapping. Stack traces reference
real function names. Grep for `checkFC01` finds one definition and one call site.

**Alternatives Considered**

- **Check interface + registry**: Defines a `Check` interface with `AppliesTo` and
  `Run` methods; registers checks at `init()`. Rejected because `init()`-based global
  registration introduces implicit execution order, adds a struct type per check versus
  a single function, and solves a format-count scaling problem that doesn't exist at
  this scale. The extensibility benefit (no central edit for new formats) is a minor
  gain against concrete costs in readability and debuggability.

- **Per-format validator structs**: Each format embeds a `BaseValidator` implementing
  FC01-FC04; format-specific checks are methods on the format type. Rejected because
  Go embedding is not inheritance — the universal checks still need explicit call sites
  in each `Validate()` method, which is boilerplate without benefit. The factory switch
  has the same coupling point as the flat sequential switch. Adds 5 struct definitions
  for what is fundamentally a data-parameterization problem.

- **Pipeline with middleware**: Each check is a step receiving `(Doc, []ValidationError,
  Config)` and returning `([]ValidationError, bool)`. Rejected because threading the
  accumulator and short-circuit bool through every step adds incidental complexity.
  Collect-all semantics are trivially achieved with `append` in a flat function.
  Pipeline flexibility is only valuable when step composition is dynamic at runtime;
  here the check set is static.

**Consequences**

What becomes easier:
- Reading and debugging the validator: the call graph is fully visible in `validateFile`
- Unit testing individual checks: each is a pure function with no setup
- Adding a new universal check: add a function, add one call in `validateFile`
- Adding a format-specific check: add a function, add a `case` in the format switch

What becomes harder:
- Adding a tenth+ format without fatigue: the switch grows; if this happens, migrate
  to a registry at that point (the flat implementation is straightforwardly refactorable)
- Discovering which checks apply to a given format without reading `validateFile`

What stays the same:
- Adding a new format requires editing `validateFile` regardless of architecture
  (to add its `FormatSpec` and any format-specific rules)
<!-- decision:end -->
