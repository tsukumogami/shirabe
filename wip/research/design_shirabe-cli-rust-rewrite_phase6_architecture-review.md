# Phase 6 Architecture Review: shirabe-cli-rust-rewrite

## Review questions

1. Is the architecture clear enough to implement?
2. Are there missing components or interfaces?
3. Are the implementation phases correctly sequenced?
4. Are there simpler alternatives we overlooked?

## Findings

### Clarity for implementation

Strong. Solution Architecture names every module (`doc.rs`,
`formats.rs`, `frontmatter.rs`, `checks.rs`, `validate.rs`,
`annotation.rs`) and the public surface re-exported by `lib.rs`.
The data-flow diagram traces from `Cli::parse()` through to the
per-error `format_error`/`format_notice` emission with the same
control flow as the Go binary. The YAML field→line reconstruction
sketch shows the saphyr API shape with the explicit fallback to
`saphyr-parser`'s `SpannedEventReceiver` if the high-level API
drifts.

A developer implementing this can build directly from the design
without reaching for the Go source for ordering or naming
decisions.

### Missing components or interfaces

One gap: the **error type** in `shirabe-validate` is implied but
not named. The Go code uses `ValidationError` (a struct) and
returns `Vec<ValidationError>` from each check. The Rust port
mirrors this; the design doesn't explicitly name the error type's
derive set (`Debug`, `Clone`, `PartialEq` would be conventional;
`thiserror`-style would be over-engineering for a struct that
just carries data). Minor — implementer can pick — but worth a
note.

A second gap: the design names `parse_doc` and `parse_yaml_fields`
but doesn't say what the error type of `parse_doc` is. Go's
`parseDoc` returns `(Doc, error)`; the Rust port presumably
returns `Result<Doc, ParseError>`. Whether `ParseError` is a
separate type or a variant of a single `Error` enum (covering
parse, validate, and IO errors) is an implicit choice. Minor.

The fallback path (saphyr-parser event-receiver walk) is described
but not coded; the design says it's "~70 LOC instead of ~30" but
doesn't sketch the event-handling state machine. If the fallback
fires, the implementer has to design the receiver from the parser
docs alone. Acceptable because (a) the fallback is contingent and
(b) the saphyr-parser docs are sufficient; not acceptable would be
naming a fallback without naming the actual parser primitive
(`SpannedEventReceiver`), which the design does name.

### Phase sequencing

Phases 1–5 inside the rewrite PR are sequenced correctly:
workspace skeleton → frontmatter (no deps on checks) → checks (no
deps on CLI) → CLI (depends on checks + frontmatter) → fixture +
Go deletion.

The "feature flag" framing in §Sequencing inside the PR is the
right shape: Phases 1–4 ship behind a `cargo build` target that
doesn't replace the Go binary in CI; Phase 5 flips
`validate-docs.yml`'s build step from Go to Rust and deletes the
Go side. This isolates the Go-removal commit to one reviewable
diff inside the PR.

One concern: the "feature flag" language is loose. There isn't a
literal cargo feature here — the Go binary and the Rust binary
have different build commands. A clearer framing: "Phases 1–4
add a Rust crate that builds in CI alongside Go; tests run on
both. Phase 5 deletes Go and switches the workflow's build step.
No actual feature flag, just two coexisting build paths during
Phases 1–4." Worth a small clarification in the design.

### Simpler alternatives overlooked

I considered: is there a path that avoids the workspace entirely?
The pragmatic-reviewer pass will scrutinize Decision 4 directly;
my read is the workspace is the right answer because the SR4
import-path churn would otherwise concentrate at the moment SR4
needs cognitive bandwidth for library API decisions. Not simpler.

Is there a path that uses serde + a hand-rolled scanner instead
of saphyr? Decision 1 already analyzes and rejects this. The
risk concentration argument holds: the strategy named this as
the rewrite's single non-trivial portability risk.

Is there a path that delays the Go deletion to a follow-up PR?
That would create a Go-Rust coexistence window. Strategy
Decision 3 (no v2 break) plus the parity fixture make the
deletion safe in one cut; coexistence would create two PRs
where one suffices. Not simpler.

## Recommendations

1. **Add error-type naming.** A line in Solution Architecture
   naming `ValidationError` as the canonical error struct and
   `ParseError` as the parser's error type, with `Debug + Clone +
   PartialEq` derives. Implementer-clarity win, low cost.

2. **Refine "feature flag" framing.** Replace "feature flag" with
   "coexisting build paths" or similar. The semantic difference
   is small but the term `feature flag` has a specific meaning
   (cargo features) that doesn't apply here.

3. **No design changes required** beyond these two clarifications.

## Verdict

PASS with minor clarifications. The architecture is implementable
as-is; the two clarifications above are nice-to-haves that the
implementer can absorb.
