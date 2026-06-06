# Decision 6: `is_notice` extension wording

## Question

The PRD's R10 and R11 bind FC09 to the same membership-based notice/error split that SCHEMA and FC07 already use, and the promotion seam is the membership entry itself. Exact match-arm change needs settling.

## Chosen

Extend the existing `is_notice` match in `crates/shirabe-validate/src/validate.rs` from:

```rust
pub fn is_notice(err: &ValidationError) -> bool {
    matches!(err.code.as_str(), "SCHEMA" | "FC07")
}
```

to:

```rust
pub fn is_notice(err: &ValidationError) -> bool {
    matches!(err.code.as_str(), "SCHEMA" | "FC07" | "FC09")
}
```

Plus a one-line doc-comment extension above the function naming FC09 alongside FC07 as a notice-level check pending its corpus cleanup. The promotion seam is removing the `| "FC09"` arm -- one token plus the leading pipe-and-space, four characters of diff.

The test `is_notice_only_schema_and_fc07` in `validate.rs` becomes `is_notice_only_schema_fc07_fc09`. The function body adds:

```rust
assert!(is_notice(&ValidationError {
    file: String::new(),
    line: 0,
    code: "FC09".to_string(),
    message: String::new(),
}));
```

and removes `"FC09"` from the `for code in [...]` block that asserts the non-notice codes do not match (so the test no longer asserts FC09 is NOT a notice).

## Alternatives considered

- **Extend `is_notice` to a `match` expression with one arm per code instead of a `matches!`-comma list.** Rejected.
  - The `matches!` form is what the FC07 sub-DESIGN settled on. Reshaping the function adds churn for no gain; the membership stays a single-line diff in either shape, and the `matches!` form is the more idiomatic Rust expression.

- **Introduce a per-check "notice or error" field on `ValidationError` and let each check declare its own severity.** Rejected.
  - Same reason FC07's Decision 3 rejected the equivalent move ("a method would multiply the surface for no functional gain"). The two-level notice/error split is intentional and the membership is the seam.

- **Introduce a separate `is_notice_fc09(err)` function so the FC09 promotion is removable independently.** Rejected.
  - The promotion seam is supposed to be a single line, not a function-removal. The shared `matches!` form delivers exactly that.

- **Use a `const FC09_NOTICE: bool = true;` constant and gate the dispatch on it.** Rejected.
  - Adds a second seam (the constant flip and the membership flip would both be required to promote, doubling the change surface). PRD R11 wants exactly one seam.

## Promotion mechanics

The promotion PR is the one-line membership change plus the test update (the test's `is_notice_only_schema_fc07_fc09` becomes `is_notice_only_schema_fc07`, and `FC09` moves from the "is a notice" branch back to the "is not a notice" loop). Two-line diff in production code, three-line diff in test code -- still independently reviewable as a single intent.

The corpus-cleanup PR that lands the promotion is the maintainer's responsibility (PRD Out-of-Scope item 1: "The actual promotion of FC09 to error-level. Promotion is a one-line change at the `is_notice` membership site (R11), landed in a separate cleanup PR once the committed corpus is reconciled. This PRD ships the seam, not the flip"). The sub-DESIGN ships only the addition.

## Doc-comment extension

The doc comment above `is_notice` today reads:

```rust
/// Reports whether a [`ValidationError`] should be emitted as a GHA
/// `::notice` annotation rather than a `::error`.
///
/// **Promotion seam.** FC07 ships notice-level for v1; remove the
/// `"FC07"` arm from this match to promote the check from notice to
/// error in a single-line diff. The match expression is the one place
/// that drives the notice-vs-error split; the corresponding test in this
/// module (`is_notice_only_schema_and_fc07`) tracks the membership.
///
/// All other codes (`FC01`-`FC06`, `R6`-`R9`) are errors that contribute
/// to a non-zero exit. `SCHEMA` is the long-standing notice; `FC07` is
/// the v1 addition pending the corpus-cleanup PR.
```

The FC09 extension rewrites the doc comment to name both notice-level additions:

```rust
/// Reports whether a [`ValidationError`] should be emitted as a GHA
/// `::notice` annotation rather than a `::error`.
///
/// **Promotion seam.** FC07 and FC09 ship notice-level for v1; remove
/// the corresponding arm from this match to promote the check from
/// notice to error in a single-line diff. The match expression is the
/// one place that drives the notice-vs-error split; the corresponding
/// test in this module (`is_notice_only_schema_fc07_fc09`) tracks the
/// membership.
///
/// All other codes (`FC01`-`FC06`, `R6`-`R9`) are errors that contribute
/// to a non-zero exit. `SCHEMA` is the long-standing notice; `FC07` and
/// `FC09` are notice-level additions pending their respective
/// corpus-cleanup PRs.
```

This phrasing extends the FC07 seam wording the FC07 sub-DESIGN's Decision 3 already locked in (so a future reader sees both notice-level checks share the same seam and the same membership semantics).

## Citation

- PRD R10 (notice-level via existing `is_notice` membership), R11 (one-line promotion seam).
- FC07 sub-DESIGN Decision 3 (the precedent seam wording this design extends).
- `crates/shirabe-validate/src/validate.rs` (the actual `is_notice` function and its test).
