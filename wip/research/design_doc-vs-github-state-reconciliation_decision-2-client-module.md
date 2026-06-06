# Decision 2: GitHub client module layout

## Question

Where does the GitHub client live in `shirabe-validate`'s module graph? What is its public surface? How is it reached from `check_fc09`?

## Chosen

A new module `crates/shirabe-validate/src/gh.rs`, declared `pub mod gh;` in `lib.rs`, exposing:

```rust
// trait surface FC09 consumes
pub trait IssueStateClient {
    fn fetch_issue_state(&self, owner: &str, repo: &str, number: u64)
        -> Result<IssueState, ClientError>;
    fn fetch_pr_body(&self, owner: &str, repo: &str, number: u64)
        -> Result<String, ClientError>;
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum IssueState { Open, Closed }

#[derive(Debug)]
pub enum ClientError {
    Auth,                  // no credentials available (R6)
    NotFound,              // 404 -- cross-repo access denied or missing issue (R9)
    Forbidden,             // 403 -- cross-repo access denied (R9)
    RateLimit,             // 429 / secondary rate limit (R8)
    Network,               // transport failure (timeout, connection refused, etc.)
    Malformed(String),     // parser-side failure on the response body (R15)
}

pub struct GhSubprocessClient { /* timeout config, gh path */ }

impl GhSubprocessClient {
    pub fn new() -> Self;          // defaults: timeout = 5s, gh = "gh"
}

impl IssueStateClient for GhSubprocessClient { /* ... */ }

// PR-context detection lives here too so the env-var surface is local
// to the module that consumes it.
pub fn detect_pr_context() -> Option<PrContext>;

pub struct PrContext {
    pub owner: String,
    pub repo: String,
    pub number: u64,
}
```

`check_fc09` accepts `&dyn IssueStateClient` polymorphically. A constructor inside the module (`GhSubprocessClient::new()`) is the production path; tests pass a `MockIssueStateClient` (see Decision 3).

## Alternatives considered

- **Inline the client surface in `checks.rs`.** Rejected.
  - The client touches process spawning, env-var reading, and JSON parsing -- none of which `checks.rs` does today. Inlining mixes the network surface with the pure-data per-defect notice emitters. The FC07 sub-DESIGN's Decision 1 precedent ("a separate module matches the existing `table.rs` precedent") binds here too.
  - The trait isolates the test boundary. A trait declared in `checks.rs` would force the mock to live alongside production checks; pulling it into `gh.rs` keeps the test-only impl in a `#[cfg(test)]` submodule of `gh.rs`.

- **Split the trait declaration from the subprocess impl into two modules (`gh.rs` for the trait, `gh_subprocess.rs` for the impl).** Rejected.
  - The crate has nine modules today (`annotation`, `checks`, `doc`, `features`, `formats`, `frontmatter`, `mermaid`, `table`, `transition`, `validate`). Splitting `gh` into two leans into module sprawl without separating concerns -- the impl is small enough (~150 lines) to live next to its trait.

- **Put PR-context detection inside `validate.rs` (alongside the dispatcher) and pass the resolved context as a parameter to `check_fc09`.** Rejected for now.
  - The PR-context surface is only consumed by FC09 (PRD Out-of-Scope item 7: "A general PR-context plumbing layer for the validator. FC09 reads the env vars it needs and detects PR context from them. Generalizing PR context into a shared validator runtime layer that future checks could consume is downstream work; FC09 is the first check to need any of this and its surface stays local until a second consumer appears."). Co-locating it with the client keeps the env-var surface in one module; a future second consumer triggers the lift.

## Public surface boundary

The crate doc comment in `lib.rs` already calls out: "Public exports are unstable across shirabe versions. Treat as `pub(crate)` at all call sites that are not the shirabe binary crate." FC09's `gh` module follows the same posture -- the trait, the enum types, and the constructor are `pub` only because the binary crate links across the crate boundary; they remain unstable from any external linker's perspective.

The trait is intentionally minimal: two methods that take `&self` (no `&mut self`, no internal state mutation per call) and return `Result`. No async, no streaming, no batching. PRD R3 names exactly these two operations.

## Module dependencies inside the crate

- `gh.rs` depends on `std::process::Command`, `std::env`, `std::time::Duration`, and reuses the `regex` carrier that `features.rs` and `checks.rs` already pull in (for PR-body `Closes #N` extraction).
- `gh.rs` does not depend on any other crate module (no `crate::table`, no `crate::doc`). It is a leaf module.
- `checks.rs` adds a `use crate::gh::{IssueStateClient, PrContext, IssueState, ClientError, detect_pr_context};` line and a new `check_fc09(doc, spec, client, pr_ctx)` function next to `check_fc07`.

## Citation

- PRD R3 (trait surface), R5 (PR-context env vars), Out-of-Scope item 7 (no general PR-context layer in v1).
- FC07 sub-DESIGN Decision 1 ("a separate module matches the existing `table.rs` precedent").
- `crates/shirabe-validate/src/lib.rs` doc comment (the internal-shape stability posture).
