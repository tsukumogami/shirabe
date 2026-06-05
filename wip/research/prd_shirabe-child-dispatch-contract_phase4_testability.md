# Testability Review

## Verdict: PASS

The PRD's acceptance criteria split cleanly into grep-checkable structural ACs (AC1-AC17) and judgment-based legibility ACs (AC18-AC20). The split is explicitly acknowledged in L2 (Known Limitation). A test plan can be derived from AC1-AC17 mechanically; AC18-AC20 require human review per the BRIEF's legibility outcome.

## Untestable Criteria

None of the acceptance criteria are technically untestable. AC18-AC20 are judgment-based but testable by a human reviewer reading the docs cold. The PRD acknowledges this trade-off in L2.

## Missing Test Coverage

1. **No AC for OQ3 forward-looking note presence.** R11 requires the forward-looking note; AC17 verifies the note exists. OQ3 says placement is DESIGN-territory. The AC chain is complete (R11 → AC17), so this is not a coverage gap — noting for completeness.

2. **No AC explicitly verifying L1 (contract is documentation, not enforcement).** L1 is a known limitation, not a requirement, so it doesn't need an AC. The PRD is correct to leave it as a limitation. Noting that a reviewer might expect "AC for runtime enforcement" — that's out of scope and the PRD correctly excludes it.

3. **AC3 mechanism-name verification is weak.** AC3 says "names exactly one harness primitive (the specific name is DESIGN's choice)." A reviewer can verify "exactly one is named" by counting names. But a reviewer cannot verify "the named primitive matches DESIGN's intent" without consulting DESIGN. This is correct (the PRD defers the choice to DESIGN), but the test plan must note: AC3 verifies presence + uniqueness; semantic correctness of the mechanism choice is a DESIGN-level concern, not a PRD-level concern.

   **Suggested fix**: none — AC3 is correct. The test plan should be explicit about the structural-vs-semantic boundary.

## Summary

PRD passes testability review. AC1-AC17 are grep-checkable structural criteria; AC18-AC20 are judgment-based legibility criteria with explicit known-limitation acknowledgment. A reviewer can derive a test plan from the AC list alone: 17 mechanical checks (grep, file-existence, diff-equivalence) plus 3 cold-orchestrator read-throughs. No untestable criteria; no missing coverage; one minor note about AC3's structural-vs-semantic boundary that should appear in the test plan but does not require a PRD change.
