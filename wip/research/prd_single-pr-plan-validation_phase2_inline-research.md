# /prd Phase 2 — Inline Research (single-pr-plan-validation)

Driven inline under `/scope --auto` rather than via parallel specialist agents. The three research leads from Phase 1 are grounded against the current codebase at HEAD `7c7fd4d` (BRIEF acceptance) on the `session/b194c234` branch.

## Lead 1: FormatSpec extension shape

**Current state.** `crates/shirabe-validate/src/formats.rs` defines a flat `FormatSpec` struct with `required_sections: Vec<String>`. The Plan profile (line 127-142) declares:

```rust
required_sections: s(&[
    "Status",
    "Scope Summary",
    "Decomposition Strategy",
    "Implementation Issues",
    "Dependency Graph",
    "Implementation Sequence",
]),
```

There is no per-`execution_mode` branching anywhere in the validator. FC04 (`check_fc04` at line 173) consumes `spec.required_sections` directly and reports any missing section.

**Implication for FC14.** The PRD must specify a `FormatSpec` extension that carries an `execution_mode`-aware required-sections shape *only* for the Plan profile, with a graceful fallback to the existing flat `required_sections` for all other profiles. Two viable shapes:

- A new field `execution_mode_sections: Option<HashMap<String, Vec<String>>>` keyed by execution_mode value (`"single-pr"`, `"multi-pr"`).
- A new field `execution_mode_sections: Option<Vec<(String, Vec<String>)>>` preserving declaration order.

The PRD names the contract but leaves the exact data structure to DESIGN/implementation. FC04's existing call site (`spec.required_sections`) must continue to work for non-Plan profiles unchanged.

## Lead 2: Outline parser shape

**Current state.** `crates/shirabe-validate/src/table.rs::parse_issues_table(doc: &Doc) -> Option<Table>` is the precedent. It locates the `## Implementation Issues` section, parses the GFM pipe table, and returns a `Table` with `columns`, `rows`, `header_line`, `profile`. Each `Row` carries `kind`, `key`, `deps`, `line`, `raw`, `terminal`, `status`.

**Implication for FC14.** The outline parser parallels this shape:

```
parse_issue_outlines(doc: &Doc) -> Vec<OutlineBlock>
```

Where `OutlineBlock` carries `key` (the outline heading text), `goal` (`Option<String>` — present if the block declares one), `acceptance_criteria` (`Option<Vec<String>>` — the bullet list inside the AC block), `dependencies` (`Vec<String>` — outline keys or the literal `"None"`), and `line` (1-indexed line number where the block heading sits).

The function MUST be total over arbitrary input — never panic on malformed headers, missing fields, or unterminated blocks. The PRD specifies this contract explicitly; the parser emits per-defect notices (via FC14) rather than refusing to return.

File location (extending `table.rs` vs new `outlines.rs`) is a downstream implementation choice; the PRD does not pick it.

## Lead 3: Sibling-check pattern (FC07-FC13) and `is_notice` wiring

**Current state.** `crates/shirabe-validate/src/validate.rs` registers notice-level checks via the `is_notice` function (around line 42). Current notice codes: FC07, FC08, FC09, FC10, FC11, FC12, FC13.

**FC07-FC09 pattern.** Each is a separate `check_fcNN` function in `checks.rs`, dispatched in the appropriate arm of `validate_file`. Their reconciliation messages are formatted `[FCNN] <specific-defect>: <verbatim-key-or-name>`. Tests live in the same file as `tests` modules; FC07 has table-driven tests covering each AC-RNN scenario (see lines 3333+ for the AC mapping comments).

**CRITICAL CORRECTION: code-name collision.** The new check **cannot use the code `FC10`**: that code is already taken by `check_fc10` (writing-style banned-word check, lines 2090-2155 of `checks.rs`). The next free code after FC07-FC13 is **FC14**.

The issue title (#154 "feat(validate): add fc10 single-pr plan validation") uses "fc10" as a working name only. The PRD MUST specify the actual implementation code as **FC14**, and the BRIEF MUST be amended to drop "FC10" specificity (or note the rename) before the PRD lands.

Promotion path (notice → error) is uniform across the family: extend or remove from the `is_notice` match arm. The PRD's notice-severity acceptance criterion names this seam exactly.

## Open Questions Surfaced (deferred to PRD body)

1. **Where does the outline parser live?** `table.rs` extension or new `outlines.rs` — implementation choice.
2. **Exact `FormatSpec` field shape for execution-mode-aware sections** — implementation choice; PRD specifies the contract.
3. **Does FC14 emit one notice per defect, or one aggregate notice per outline block?** PRD specifies the granularity.

These are not blockers — they will be settled during DESIGN-altitude work or directly in the implementation PR.

## Constraints the PRD must honor

- The new check MUST use code `FC14` (not `FC10`).
- The check MUST ship at notice severity via `is_notice` membership.
- The Roadmap arm MUST be unchanged (roadmaps have no single-pr / multi-pr distinction).
- The outline parser MUST be total over arbitrary input — no panics.
- Reconciliation messages MUST name the specific defect verbatim (outline key, missing field, unresolved dep name).
- All five sub-checks in the BRIEF MUST be addressed in the AC set.
- Multi-pr plans MUST see no behavioural change.
