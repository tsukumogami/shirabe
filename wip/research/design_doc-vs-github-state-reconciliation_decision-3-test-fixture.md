# Decision 3: Test-fixture mechanism -- trait-based mocking with inline canned responses

## Question

How does FC09's test code stand in for the real GitHub API? Two shapes are on the table: a trait-based mock with canned response maps in `#[cfg(test)]`, or recorded HTTP fixtures under `crates/shirabe-validate/testdata/gh-fixtures/`.

## Chosen

Trait-based mock with inline canned responses. A `MockIssueStateClient` lives in a `#[cfg(test)]` submodule of `gh.rs` and implements `IssueStateClient` by consulting a `HashMap<(String, String, u64), Result<IssueState, ClientError>>` for `fetch_issue_state` and a `HashMap<(String, String, u64), Result<String, ClientError>>` for `fetch_pr_body`. Tests build the maps inline from `&str` literals -- the same inline-string pattern the FC07 sub-DESIGN's Decision 4 settled for mermaid and table fixtures.

```rust
#[cfg(test)]
pub(crate) struct MockIssueStateClient {
    pub issues: HashMap<(String, String, u64), Result<IssueState, ClientError>>,
    pub prs:    HashMap<(String, String, u64), Result<String, ClientError>>,
}

#[cfg(test)]
impl IssueStateClient for MockIssueStateClient {
    fn fetch_issue_state(&self, owner: &str, repo: &str, number: u64)
        -> Result<IssueState, ClientError> {
        self.issues
            .get(&(owner.to_string(), repo.to_string(), number))
            .cloned()
            .unwrap_or(Err(ClientError::NotFound))
    }
    fn fetch_pr_body(&self, owner: &str, repo: &str, number: u64)
        -> Result<String, ClientError> {
        self.prs
            .get(&(owner.to_string(), repo.to_string(), number))
            .cloned()
            .unwrap_or(Err(ClientError::NotFound))
    }
}
```

Tests construct the mock, populate the maps with the cases the test exercises (open, closed, malformed, rate-limit, 403, 404), and pass `&mock as &dyn IssueStateClient` into `check_fc09`. The test corpus stays in-crate; no test fixture file ever ships.

## Alternatives considered

- **Recorded HTTP fixtures under `crates/shirabe-validate/testdata/gh-fixtures/`.** Rejected.
  - The FC07 sub-DESIGN's Decision 4 already rejected externalized fixtures for the same crate ("the crate's existing parsers use inline-string fixtures for the same reason"). Carrying a second precedent (inline for parsing, recorded for client tests) would split the test infrastructure across two patterns for no clear gain.
  - A recorded fixture is harder to amend in a code review. Adding a new test case (e.g., "a row whose issue returns a 502 Bad Gateway") requires either capturing a real 502 from `gh api` or hand-writing the JSON body in the right place under `testdata/`. The inline-map shape lets the test author write `mock.issues.insert((..., 999), Err(ClientError::Malformed("...".to_string())));` in one line at the test's own scope.
  - Recorded fixtures bind to the `GhSubprocessClient` impl (the only thing that can be replayed against them). The trait-based mock binds to the trait. Any future impl swap (raw HTTP, batched gRPC, whatever) reuses the existing test corpus; recorded fixtures would force a re-capture.

- **`wiremock`/`mockito`-style HTTP-mocking server.** Rejected.
  - Adds a new dev-dependency. The mock-trait pattern needs no new dep. The handoff document explicitly flagged "Trait-based is more testable and matches the existing in-file fixture pattern (per sub-DESIGN Decision 4). Recommend trait-based."

- **A real-GitHub integration test that runs only when a guard env var is set (`SHIRABE_FC09_LIVE=1`).** Rejected as the test fixture mechanism.
  - Useful as an ad-hoc verification step but cannot be the primary fixture -- it depends on network access, on a real GitHub repo with a known issue-state matrix, and on a long-lived test PR. None of which can run in offline CI. A small live-spot-check is mentioned in Phase G of the handoff and is fine to do during development; it is not the test fixture.

## Pinned fixture cases

The mock covers every case the PRD's acceptance criteria name:

- **Sub A reconciled (no notice):** `(owner, repo, n) -> Ok(Closed)` for a `done`-classed row whose row is terminal.
- **Sub A defect (notice):** `(owner, repo, n) -> Ok(Open)` for a `done`-classed terminal row.
- **Sub B reconciled (no notice):** `Ok(Open)` for a `ready` or `blocked` row whose row is non-terminal.
- **Sub B defect (notice):** `Ok(Closed)` for a `ready` or `blocked` non-terminal row.
- **Sub C over-claims:** A `Closes #N` line in the PR body for an N the doc shows non-`done`.
- **Sub C under-claims:** A `done`-claimed row whose issue is `Ok(Open)` and whose number does not appear in any `Closes` line.
- **Self-disable -- no credentials:** the test passes a client whose `fetch_*` always returns `Err(ClientError::Auth)` *and* the test asserts on the missing-credentials skip-notice path that fires before the loop starts.
- **Self-disable -- no PR context:** PR-context detection returns `None`; Sub C must skip but A and B must still fire on real defects.
- **Self-disable -- rate-limit exhausted:** The mock returns `Err(ClientError::RateLimit)` twice for the same `(owner, repo, n)`; the test asserts the skip notice is emitted once and the loop stops processing further rows.
- **Self-disable -- cross-repo denied:** Per-row case. The mock returns `Err(ClientError::Forbidden)` (or `NotFound`) for one `(otherorg, otherrepo, n)` while other rows succeed; only that row gets the per-row skip notice.
- **Bounded over malformed input:** The mock returns `Err(ClientError::Malformed("unexpected JSON shape".to_string()))` for one row; the test asserts no panic, no notice for that row, and the loop continues.

## Citation

- PRD R3 (trait-shape client makes mocking straightforward), R6-R9 (the four self-disable paths the mock has to reach), R15 (bounded behavior over malformed responses).
- FC07 sub-DESIGN Decision 4 (inline-string fixture precedent).
- Handoff document `wip/handoff-fc09.md` Phase E (workspace recommendation aligned to trait-based mocking).
