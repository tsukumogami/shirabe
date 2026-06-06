# Phase 3 cross-validation: doc-vs-github-state-reconciliation (FC09)

Each decision was reviewed against the others for conflicts, assumption divergence, and load-bearing dependencies. None found requiring revision; details below.

## Pairwise assumption check

| Pair | Shared assumption | Conflict? |
|---|---|---|
| D1 (transport) + D2 (module) | The trait surface (`IssueStateClient`) is the substrate; the subprocess client is one impl. D2 declares the trait; D1 chooses its impl. | No conflict. D2 is impl-agnostic by design. |
| D1 + D3 (test fixture) | The mock implements the same trait. D1's transport choice does not constrain the test path because the trait abstracts it. | No conflict. |
| D1 + D5 (timeout/retry) | The 5s timeout, 2s back-off, and rate-limit detection patterns are subprocess-specific. They bind to D1's choice. | No conflict; D5 is conditional on D1. If D1 were revisited (raw HTTP), D5 would be re-derived. |
| D2 + D7 (env vars) | `detect_pr_context` lives inside the `gh` module. D2 names it; D7 specifies its behavior. | No conflict. |
| D4 (notice strings) + D7 | The "no PR context" skip notice names env vars (`GITHUB_REF`, `GITHUB_REPOSITORY`, `SHIRABE_PR_NUMBER`); D7 fixes the precedence. | No conflict. The notice text names all three, and D7 makes the override the highest-priority signal -- consistent. |
| D4 + D5 | The rate-limit-exhausted notice mentions "one retry"; D5 fixes the retry count at exactly one. | No conflict. |
| D6 (`is_notice` extension) + D4 | The membership entry promotes from notice to error by removing the `FC09` arm; D4's notices ship at notice level until that removal lands. | No conflict. |
| D2 + D6 | The crate-root `pub mod gh;` declaration sits in `lib.rs`; the membership entry sits in `validate.rs`. Both files are touched by the FC09 PR. | No conflict; they are independent edits. |
| D3 + D4 | The mock's test cases exercise every notice form D4 names. The pinned-fixture set in D3 covers all six defect notices plus the four self-disable notices. | No conflict. |

## Load-bearing assumptions surfaced

- **`gh` is on `$PATH` in every supported environment.** Underpins D1 and D5. Mitigation: dev-environment self-disable (the missing-credentials path effectively swallows a missing binary -- `gh auth status` returns non-zero if `gh` is absent, which fires the Auth `ClientError`).
- **`gh api`'s stderr signals are stable enough to pattern-match for rate-limit detection.** Underpins D5. Mitigation: defensive fallback (any unrecognized non-zero exit maps to `Network`, not `RateLimit`, so a future `gh` change downgrades the impact -- no false rate-limit-self-disable).
- **The trait surface (two methods) is sufficient for FC09's three sub-checks.** Underpins D2. PRD R3 names exactly these two operations. Sub C reuses `fetch_issue_state` for the "doc anticipates closure no PR delivers" case; no new method is needed.
- **PR-context detection is FC09-local until a second consumer appears.** Underpins D2 and D7. PRD Out-of-Scope item 7 explicitly defers a shared layer. Consistent.

## No contradictions between decisions and the PRD

Walked each PRD requirement R1-R17 against the seven decisions:

- R1 (three sub-checks in one check): no decision constrains a single-check shape; D2's `check_fc09` function is the single dispatch.
- R2 (reconciling subset): no decision; FC09 reuses FC07's `ISSUE_KEYED_NODE_ID` regex and `STATUS_CLASSES` set via the same `crate::checks` static constants.
- R3 (trait surface): D2 binds.
- R4 (auth chain): D7 binds.
- R5 (PR-context env vars): D7 binds.
- R6-R9 (four self-disables): D4 (the strings), D5 (the rate-limit retry policy), D7 (the credentials gate).
- R10-R11 (notice level + promotion seam): D6 binds.
- R12 (per-defect voice): D4 binds.
- R13 (Sub C asymmetry): D4 binds (the two distinct strings).
- R14 (5xx and malformed inputs contribute no per-row notice): D5 binds (the `Network` and `Malformed` error mappings).
- R15 (bounded behavior): D1 (subprocess surface), D5 (explicit timeout and one retry), D7 (token never read by FC09).
- R16 (reuse of existing infrastructure): D2 (one new module + one new check function + one membership-line extension).
- R17 (public-cleanliness): D4 (the notice strings) and D7 (env-var detection echoes names, not values).

Every requirement maps to at least one decision; no decision contradicts another.

## Outcome

No revisions required. The seven decisions compose cleanly into a single `check_fc09` whose loop mirrors FC07's `class_vs_status_pass` but pulls observed state from the trait client instead of from `Row.terminal`. Proceed to Phase 4 (draft).
