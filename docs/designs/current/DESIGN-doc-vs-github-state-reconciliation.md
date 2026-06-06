---
schema: design/v1
status: Current
problem: |
  shirabe-validate's reconciliation surface today is offline: FC07 reconciles
  the Implementation Issues table against the dependency diagram, FC08
  reconciles the Legend against the classDef set, and R6 reconciles upstream
  references across docs. None of them reaches outside the docs. A plan or
  roadmap that is perfectly self-consistent can still lie about external
  reality -- the doc claims a row done while GitHub shows the issue open, or
  the doc still classes a node ready long after a parallel PR closed the
  issue, or a PR's `Closes #N` line disagrees with what the doc shows as
  done. The PRD scopes FC09 as the third reconciliation axis behind a
  notice-then-error rollout. This design settles the implementation gates
  the PRD deferred: the transport choice between a `gh` CLI subprocess and a
  raw HTTP client, the GitHub client module layout and its trait surface,
  the test-fixture mechanism, the exact notice-message strings, the
  timeout/retry/back-off values, the `is_notice` extension wording, and the
  PR-context env-var plumbing.
decision: |
  FC09 lands as one new check function in `crates/shirabe-validate/src/checks.rs`,
  consuming a new `gh` module (`crates/shirabe-validate/src/gh.rs`) that
  declares an `IssueStateClient` trait with two methods (`fetch_issue_state`,
  `fetch_pr_body`), a `GhSubprocessClient` impl that shells out to `gh api`,
  a `MockIssueStateClient` (cfg(test)) for inline-canned-response tests, and
  a `detect_pr_context` env-var reader. `check_fc09` runs the three
  sub-checks in a single pass over the parsed Table and the extracted
  Diagram, structured around the same class-versus-Status loop FC07's
  Decision 6 uses but with `observed_state` coming from the trait client
  instead of `Row.terminal`. The check ships at notice level by joining the
  existing `is_notice` membership; the promotion seam is the one-line
  removal of the `FC09` arm from the `matches!` expression. Per-request
  timeout is 5 seconds, the retry policy is exactly one retry on rate-limit
  errors with a fixed 2-second back-off, and on second rate-limit the check
  self-disables for the remainder of the run.
rationale: |
  The trait-shaped client surface keeps FC09 testable without ever invoking
  `gh` in unit tests and absorbs PRD R3's transport-neutral binding. The
  `gh` subprocess choice reuses workspace-wide tooling that already pays
  the auth, retry, and rate-limit detection costs, leaving FC09's own
  defensive-parsing surface small enough to discharge PRD R15 by
  construction. The single-pass three-sub-check shape composes with the
  existing FC07 dispatch pattern (one check function per FC code, per-defect
  notices, profile-aware via `Table.profile`), so the new check joins the
  family without expanding the family's interface surface. Joining the
  existing `is_notice` membership rather than inventing a new severity level
  preserves the one-seam-one-mechanism promotion path FC07 and FC08 ride.
  The fixed timeout, single retry, and bounded request ceiling honor the
  totality contract over arbitrary external input while keeping the
  per-doc wall-clock well under any CI budget.
upstream: docs/prds/PRD-doc-vs-github-state-reconciliation.md
---

# DESIGN: doc-vs-github-state-reconciliation

## Status

Current

## Context and Problem Statement

The `shirabe-validate` crate dispatches its content checks in the `Plan` and
`Roadmap` arms of `validate_file`. The arms today run, in order: the schema
gate, the visibility gate, FC01 through FC04, then the format-specific
checks (`check_plan_upstream` on plans only, then `check_fc05`,
`check_fc06`, `check_fc07`). FC08 is queued as a parallel notice-level
increment; FC09 is the next.

Every existing check is offline. The validator binary has no network
surface, no GitHub API client, and no PR-context awareness. The committed
plan-and-roadmap corpus has already shown the gap that follows from
this -- the same milestone that motivated FC07 saw a hand-fix to a plan
because an issue's state had moved out from under the doc, and FC07
caught some of that drift after the fact only because the table
strikethrough happened to have been updated. The cases where the table
is not updated, or where the issue closes through a different repo's
PR, or where a fresh PR body says one thing and the doc says another,
remain entirely uncaught.

The PRD scopes the FC09 check that closes this gap. Its 17 numbered
requirements and 28 acceptance criteria fix the contract:

- One check, three sub-checks: doc-claims-done vs GitHub,
  doc-claims-open vs GitHub, PR `Closes` vs doc.
- A trait-shaped client surface with no transport binding at the PRD
  altitude.
- Authentication via `GITHUB_TOKEN` or `gh auth status`, PR-context
  detection from `GITHUB_REPOSITORY` plus `GITHUB_REF` or
  `SHIRABE_PR_NUMBER`.
- Four self-disable paths (missing credentials, missing PR context,
  rate-limit exhausted, per-row cross-repo access denied), each with a
  distinct skip notice.
- Notice-level shipping via the existing `is_notice` membership; a
  single-point promotion seam.
- Per-defect notice messages in FC05/FC06/FC07 voice.
- Bounded behavior over arbitrary external input -- no panics on
  malformed JSON, no unbounded retries, no logged tokens.
- Public-visibility cleanliness of notice messages and rule prose.

The parent design `DESIGN-roadmap-plan-standardization.md` Decision 3
established the staging shape -- a feasibility spike upstream of the
reconciliation check, a notice-then-error rollout, no new transport-side
dependency beyond what the workspace already pays for. The FC07 sub-DESIGN
`DESIGN-table-diagram-reconciliation.md` is the architectural precedent
this design extends: its Decision 6's class-versus-Status pass is the
exact loop FC09 reuses, swapping `Row.terminal` for an `observed_state`
fetched through the new client. This design refines the parent's
Decision 3 in light of the FC09 scope and the FC07 sub-DESIGN's
precedents; it does not supersede either upstream.

The implementation gaps left for this design are the seven that the PRD's
Out-of-Scope section names explicitly: the transport choice, the GitHub
client module layout, the test-fixture mechanism, the exact notice
strings, the specific timeout values, the `is_notice` extension wording,
and the PR-context env-var fallback chain. Each is a HOW decision the
PRD deferred; each is settled below.

## Decision Drivers

- **PRD requirements bind first.** The 17 requirements (R1-R17) and the
  28 acceptance criteria fix the contract; every decision below must
  keep them satisfied.
- **The FC07 sub-DESIGN's six decisions bind the precedent.** Module
  shape (separate file under `crates/shirabe-validate/src/`), notice
  voice (per-defect, `[FCxx] <description>`), inline-string fixtures,
  membership-entry promotion seam, doc-comment binding for
  non-obvious conventions -- FC09 follows the FC07 shape verbatim
  unless a PRD requirement forces a divergence.
- **No new dependency beyond what `gh` and stdlib already pay for.**
  The parent DESIGN's Decision 3 anchored the staged-reconciliation
  family on the no-new-dependency posture; FC09 honors it by routing
  the network surface through `gh` (already a workspace dependency)
  rather than linking an HTTP client.
- **Total behavior over arbitrary external input (R15).** No panics on
  malformed JSON, no unbounded retries, no unbounded loops, no
  unbounded recursion. Every external operation has an explicit
  timeout and at most a single retry on recoverable failure.
- **Token never reaches FC09 code.** PRD R4 and R15 bind the no-leak
  posture; the design uses `gh` as the token consumer so the validator
  process never holds the token bytes.
- **Single, locatable promotion seam.** The `is_notice` membership is
  the one place to flip; the FC09 PR adds the arm and the cleanup PR
  removes it.
- **Public-cleanliness of notice prose (R17).** Every notice body and
  every shared rule citing FC09 names only entities the doc itself
  already names (row keys, diagram ids, issue numbers inferred from
  the doc, PR body lines quoted verbatim).
- **Graceful self-disable on missing substrate.** Four independent
  failure modes, each with a distinct skip notice and a per-surface
  self-disable; FC01-FC08 keep running regardless.

## Considered Options

This design settles seven implementation questions. Each subsection
records the chosen approach, at least one rejected alternative with its
reason, and a citation back to the PRD requirement or the FC07 sub-DESIGN
precedent where the binding came from.

### Decision 1: Transport choice -- `gh` CLI subprocess

**Chosen.** The `GhSubprocessClient` implementation of the
`IssueStateClient` trait shells out to `gh api repos/<owner>/<repo>/issues/<n>`
and `gh api repos/<owner>/<repo>/pulls/<n>`, capturing stdout and the
process exit code. `gh` itself handles the auth chain (`GITHUB_TOKEN`
env var first, `gh auth status`-configured token otherwise) and the
HTTP transport; FC09 never holds the token bytes. The subprocess
boundary is the one network surface the validator owns; everything
inside that boundary is `gh`'s responsibility.

**Alternatives considered.**

- *Raw HTTP client (`reqwest`, `ureq`, or `hyper`).* Rejected.
  - Pulls a TLS stack and either an async runtime or a hand-rolled
    blocking transport into a crate whose only direct dependencies
    today are `regex` and the two `saphyr` carriers. The parent
    DESIGN's Decision 3 anchored the staged-reconciliation family on
    the no-new-dependency posture; the spirit of that anchor applies
    to FC09 even though the parent's scope was the mermaid extractor.
  - Forces FC09 to re-implement the auth fallback chain, the rate-limit
    detection (`X-RateLimit-Remaining` header parsing), and the
    defensive-parsing surface for TLS errors, connection failures, and
    HTTP status codes. `gh` already pays each of those costs once for
    the whole workspace.
  - Increases the no-token-leak surface area. With `gh`, the token is
    consumed by a separate process; with raw HTTP, the validator
    process loads it into memory and risks exposure in a panic
    backtrace.

- *A hybrid -- `gh` for auth discovery, raw HTTP for the calls.*
  Rejected.
  - Combines the failure modes of both: still pulls the HTTP
    dependency tree, still re-implements auth precedence (since
    `gh auth status` does not expose the raw token in a guaranteed-stable
    form), still owns TLS and connection failures. No win.

- *Defer the transport choice by leaving the trait empty.* Rejected.
  - PRD R3 requires the trait to be implementable; the sub-DESIGN
    owes a concrete impl that the v1 plan can land. A trait without
    an implementation pushes the decision into an implementation PR
    that would not get the trade-off review a design decision does.

**Citation.** PRD R3 (trait surface), R4 (auth via env or `gh`), R15
(bounded behavior), Out-of-Scope item 3 (transport deferred to
sub-DESIGN). Parent DESIGN Decision 3 (no-new-dependency posture).

### Decision 2: GitHub client module layout

**Chosen.** A new module `crates/shirabe-validate/src/gh.rs`, declared
`pub mod gh;` in `lib.rs`, exposes the trait, the data types, the
production impl, and the PR-context detector:

```rust
pub trait IssueStateClient {
    fn fetch_issue_state(&self, owner: &str, repo: &str, number: u64)
        -> Result<IssueState, ClientError>;
    fn fetch_pr_body(&self, owner: &str, repo: &str, number: u64)
        -> Result<String, ClientError>;
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum IssueState { Open, Closed }

#[derive(Clone, Debug)]
pub enum ClientError {
    Auth,
    NotFound,
    Forbidden,
    RateLimit,
    Network,
    Malformed(String),
}

pub struct GhSubprocessClient { /* timeout, gh binary path */ }

impl GhSubprocessClient {
    pub fn new() -> Self;
}

impl IssueStateClient for GhSubprocessClient { /* ... */ }

pub fn detect_pr_context() -> Option<PrContext>;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PrContext {
    pub owner: String,
    pub repo: String,
    pub number: u64,
}
```

`check_fc09` accepts `&dyn IssueStateClient` polymorphically. The
test-only `MockIssueStateClient` lives in a `#[cfg(test)]` submodule of
`gh.rs` (see Decision 3). PR-context detection is co-located with the
client because both surfaces consume environment state; PRD's
Out-of-Scope item 7 forecloses promoting either to a shared validator
layer in v1.

**Alternatives considered.**

- *Inline the client surface in `checks.rs`.* Rejected.
  - The client touches process spawning, env-var reading, and JSON
    parsing -- none of which `checks.rs` does today. Inlining would
    mix the network surface with the pure-data per-defect notice
    emitters. The FC07 sub-DESIGN's Decision 1 precedent ("a separate
    module matches the existing `table.rs` precedent") binds here.

- *Split the trait declaration from the subprocess impl into two
  modules (`gh.rs` for the trait, `gh_subprocess.rs` for the impl).*
  Rejected.
  - The crate has ten modules today. Splitting `gh` into two leans
    into sprawl without separating concerns -- the impl is small
    enough (~150 lines) to live next to its trait.

- *Put `detect_pr_context` in `validate.rs` and pass the resolved
  context as a parameter to `check_fc09`.* Rejected for v1.
  - PRD Out-of-Scope item 7 explicitly defers any shared PR-context
    layer until a second consumer appears; FC09 is the first and only
    consumer, so its detection surface stays local.

**Citation.** PRD R3 (trait surface), R5 (PR-context env vars),
Out-of-Scope item 7 (no general PR-context layer in v1). FC07
sub-DESIGN Decision 1 (separate-module precedent).

### Decision 3: Test-fixture mechanism -- trait-based mocking with inline canned responses

**Chosen.** A `#[cfg(test)] pub(crate) struct MockIssueStateClient`
inside `gh.rs` implements the `IssueStateClient` trait by consulting
two `HashMap`s populated inline at test setup:

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

Each FC09 test constructs the mock with the cases it exercises (open,
closed, malformed, rate-limit, 403, 404), passes
`&mock as &dyn IssueStateClient` into `check_fc09`, and asserts on the
returned `Vec<ValidationError>`. The test corpus stays in-crate; no
fixture file ever ships.

**Alternatives considered.**

- *Recorded HTTP fixtures under
  `crates/shirabe-validate/testdata/gh-fixtures/`.* Rejected.
  - The FC07 sub-DESIGN's Decision 4 already rejected externalized
    fixtures for the same crate, on the rationale that the in-crate
    fixture pattern matches the existing parser-test convention and
    avoids a second fixture surface that would not be exercised by
    `shirabe validate`'s own corpus walk.
  - Recorded fixtures bind to the transport impl (the subprocess
    client). The trait-based mock binds to the trait, so a future
    impl change reuses the same test corpus.
  - A new test case (e.g., "a row whose issue returns 502 Bad Gateway")
    requires only one line of mock setup. A recorded fixture would
    require either capturing a real 502 or hand-authoring the JSON
    body under `testdata/`.

- *`wiremock`/`mockito`-style HTTP-mocking server.* Rejected.
  - Adds a dev-dependency the mock-trait pattern does not need.

- *A real-GitHub integration test gated by `SHIRABE_FC09_LIVE=1`.*
  Rejected as the primary fixture mechanism.
  - Cannot run in offline CI, depends on a long-lived test PR, and
    binds to network availability. Acceptable as a development-time
    spot-check; not the test contract.

The pinned-fixture set covers every case the PRD's acceptance criteria
name: Sub A reconciled and defect, Sub B reconciled and defect, Sub C
over-claims and under-claims, the four self-disable paths (missing
credentials, missing PR context, rate-limit exhausted, per-row
cross-repo denied), and the bounded-over-malformed-input case.

**Citation.** PRD R3 (trait makes mocking straightforward), R6-R9
(four self-disable paths the mock has to reach), R15 (bounded behavior
over malformed input). FC07 sub-DESIGN Decision 4 (inline-string
fixture precedent).

### Decision 4: Notice-message wording

**Chosen.** Every FC09 notice begins with the `[FC09]` prefix and names
the entity (row key, diagram node id, issue number, PR body line where
applicable) plus observed and expected state where applicable. The
eight canonical forms (Sub A defect, Sub B defect, Sub C over-claims
same-repo, Sub C over-claims cross-repo, Sub C under-claims, plus the
four self-disable notices):

- **Sub A defect (doc claims terminal/`done`, GitHub observes open):**

  ```
  [FC09] row "#42" (node I42) claims done; GitHub observes issue #42 still open
  ```

- **Sub B defect (doc claims non-`done`, GitHub observes closed):**

  ```
  [FC09] row "#42" (node I42) claims open with class ready; GitHub observes issue #42 closed (expected done)
  ```

- **Sub C over-claims (PR body `Closes #N` for an N the doc shows non-`done`):**

  ```
  [FC09] PR body line "Closes #42" claims a closure the doc still shows non-done (row "#42", node I42, class ready)
  ```

- **Sub C over-claims, cross-repo form (PR body `Closes owner/repo#N` for an N the doc shows non-`done`):**

  ```
  [FC09] PR body line "Closes owner/repo#42" claims a cross-repo closure the doc still shows non-done (row "#42", node I42, class ready)
  ```

  The `owner/repo` substring is the literal that the validator-side
  character-set gate accepted. Before this notice is emitted, the
  `owner` and `repo` substrings parsed from the PR body line are
  validated against the same `^[A-Za-z0-9][A-Za-z0-9._-]{0,38}$` regex
  the `gh api` argument validator uses (Security Considerations
  below); a substring failing that gate causes Sub C to drop the
  reference (no `gh api` call, no notice) rather than echo the
  attacker-influenced text into the GHA annotation surface.

- **Sub C under-claims (`done`-claimed row, issue observed open, no matching `Closes` line):**

  ```
  [FC09] row "#42" (node I42) claims done but GitHub observes issue #42 open and no "Closes #42" appears in this PR
  ```

- **Self-disable -- missing credentials (R6):**

  ```
  [FC09] skipped: no GitHub credentials available (set GITHUB_TOKEN or run `gh auth login`)
  ```

- **Self-disable -- missing PR context (R7):**

  ```
  [FC09] Sub-check C skipped: no PR context (set GITHUB_REF=refs/pull/<n>/merge, GITHUB_REPOSITORY, or SHIRABE_PR_NUMBER)
  ```

- **Self-disable -- rate-limit exhausted (R8):**

  ```
  [FC09] skipped: GitHub rate limit exhausted after one retry (subsequent rows in this run will not be reconciled)
  ```

- **Self-disable -- per-row cross-repo access denied (R9):**

  ```
  [FC09] row "#42" (cross-repo "owner/repo#65") skipped: GitHub returned access denied (token cannot read owner/repo)
  ```

The variables in each form (row key, node id, issue number, declared
class, PR body literal) are substituted from the doc and the client
response. No notice quotes the GitHub token, no notice includes a
URL, no notice names a private repo or pre-announcement feature.

**Alternatives considered.**

- *Single grouped notice for all FC09 defects in a doc.* Rejected.
  - FC07's Decision 2 already rejected grouping for the same reasons
    (loss of per-line targeting, GHA-annotation surface uses line
    numbers, per-defect voice matches the FC05/FC06/FC07 family).

- *Embed the `gh api` URL in the notice body.* Rejected.
  - PRD R12 binds "notices identify nodes by their diagram id, not by
    a URL or external identifier." A URL would leak environment state
    and increase the public-cleanliness surface.

- *Vary the wording per profile (Plan vs Roadmap).* Rejected.
  - The defect is identical across profiles -- a row claims X and
    GitHub observes Y. Profile-specific wording would multiply the
    notice set without adding signal.

**Citation.** PRD R12 (notice voice, four distinct self-disable
strings), R13 (Sub C asymmetry), R17 (public-cleanliness). FC07
sub-DESIGN Decision 2 (per-defect-over-grouped precedent).

### Decision 5: Timeout, retry, and back-off values

**Chosen.**

| Knob | Value |
|---|---|
| Per-request timeout | 5 seconds |
| Timeout enforcement | User-space poll-and-kill on `Child::try_wait` + `Child::kill` (no new dep; mechanism specified in Security Considerations) |
| Subprocess output ceiling | 4 MiB on stdout per call (in-code byte bound, not "GitHub will not send more") |
| Retry policy | Exactly one retry, only on `RateLimit` errors |
| Back-off before retry | Fixed 2 seconds |
| Rate-limit detection | `gh api` nonzero exit combined with stderr substring match (`API rate limit exceeded` or `secondary rate limit`) |
| Network-error fallback | Subprocess spawn failure, subprocess timeout, or any nonzero exit not matching a recognised pattern maps to `ClientError::Network` |
| Per-invocation request ceiling | None imposed by FC09; bounded by the corpus |

The 5-second timeout is well above the typical `gh api` latency
(median ~200ms, p99 ~2s on healthy GitHub) and well under the CI job
budget. The 2-second back-off is short enough to clear a brief
secondary-rate-limit window and long enough that the first request's
rate-limit signal has a chance to clear before the retry. The single
retry is mandated by PRD R8; on the second rate-limit response,
`check_fc09` emits the rate-limit skip notice and stops iterating.

The implementation orchestrates the retry at the call site (inside
`check_fc09`), not inside the client. The client returns
`Err(ClientError::RateLimit)` once; the caller sleeps 2 seconds and
re-invokes once more; on the second `RateLimit`, the caller emits the
skip notice and breaks out of the per-row loop. Subsequent rows are
not reconciled in that run; the next `shirabe validate` invocation
with a fresh budget catches the drift (this is the PRD's Known
Limitation #2).

**Alternatives considered.**

- *Exponential back-off (1s, 2s, 4s, 8s).* Rejected.
  - PRD R8 mandates exactly one retry. Exponential implies multiple.

- *Honor `Retry-After` from the GitHub response.* Rejected for v1.
  - `gh api` does not expose response headers in a guaranteed-stable
    form. Parsing them from stderr requires regex against unstable
    text. The fixed 2-second back-off keeps the contract simple.

- *Per-request timeout 30s or 60s.* Rejected.
  - `gh api`'s 30-second default is for interactive CLI use against
    slow networks; in CI the 5-second ceiling keeps wall-clock under
    control on stalled rows.

- *No timeout, rely on `gh api`'s underlying HTTP defaults.* Rejected.
  - PRD R15 binds "every external operation has an explicit timeout."
    The wrapper enforces it.

- *Configurable timeout via env var.* Rejected for v1.
  - PRD R5 binds three env vars; adding a fourth purely for tuning is
    YAGNI.

**Citation.** PRD R8 (single retry on rate-limit then self-disable),
R14 (no per-row notice on 5xx and malformed payloads), R15 (explicit
timeout, at most one retry, no unbounded loops).

### Decision 6: `is_notice` extension wording

**Chosen.** Extend the existing `is_notice` match in
`crates/shirabe-validate/src/validate.rs` from:

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

The doc comment above the function is rewritten to name both
notice-level additions together:

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
/// All other codes (`FC01`-`FC06`, `R6`-`R9`) are errors that
/// contribute to a non-zero exit. `SCHEMA` is the long-standing
/// notice; `FC07` and `FC09` are notice-level additions pending their
/// respective corpus-cleanup PRs.
```

The test `is_notice_only_schema_and_fc07` is renamed to
`is_notice_only_schema_fc07_fc09` and its body adds an FC09
positive-assertion plus removes `"FC09"` from the for-loop of codes
that must not be notices.

The promotion mechanic for FC09 is removing the `| "FC09"` arm from
the `matches!` expression -- a four-character diff in production
code, plus the matching test update (the test's name reverts to
`is_notice_only_schema_and_fc07` and the FC09 positive-assertion is
moved back to the for-loop).

**Alternatives considered.**

- *Reshape `is_notice` into a `match` expression with one arm per
  code.* Rejected.
  - Adds churn without changing the seam shape. The `matches!` form
    is the FC07 precedent.

- *Per-check `is_notice_fcXX` functions.* Rejected.
  - The promotion seam is a single line, not a function removal.

- *A `const FC09_NOTICE: bool = true;` constant guarding the
  dispatch.* Rejected.
  - Two seams (the constant flip and the membership flip) doubles
    the change surface PRD R11 wants minimized.

**Citation.** PRD R10 (notice-level via existing `is_notice`
membership), R11 (one-line promotion seam). FC07 sub-DESIGN
Decision 3 (the precedent seam wording this design extends).

### Decision 7: PR-context env-var plumbing

**Chosen.** `gh::detect_pr_context() -> Option<PrContext>` reads
three env vars in priority order:

1. **`SHIRABE_PR_NUMBER`.** If set and non-empty, parsed as a `u64`.
   On parse failure, treated as if absent. This is the highest-priority
   signal because it exists for invocations outside GitHub Actions.
2. **`GITHUB_REF`.** If set and matching `^refs/pull/(\d+)/merge$`,
   the captured number is the PR number. Other shapes of `GITHUB_REF`
   (`refs/heads/<branch>`, `refs/tags/<tag>`) are silently ignored.
3. If neither resolves a PR number, PR context is `None`.

`owner` and `repo` come from `GITHUB_REPOSITORY` of form
`<owner>/<repo>`. If `GITHUB_REPOSITORY` is unset, PR context is
`None` regardless of whether a PR number was discovered.

The token fallback chain (PRD R4: `GITHUB_TOKEN` first, `gh auth status`
second, neither = self-disable) is not implemented inside
`detect_pr_context`; it lives inside `GhSubprocessClient`. The client
runs `gh auth status` once at construction; if it exits 0, the token
is available (either via env var or via gh-config) and the client
proceeds; if it exits non-zero, the client returns
`Err(ClientError::Auth)` on every `fetch_*` call and `check_fc09`
converts that to the missing-credentials skip notice. FC09's own
code never reads the token bytes.

**Alternatives considered.**

- *Read `GITHUB_TOKEN` in the validator and pass it as
  `--header "Authorization: Bearer <token>"` to `gh api`.* Rejected.
  - Adds a token-handling surface FC09 does not need; `gh api` does
    this internally. Increases the leak risk (the validator process
    would hold the token in memory).

- *Use `gh auth token` to extract the configured token and pass it
  onward.* Rejected.
  - Same reason. The point of using `gh` as the transport is to keep
    the token-handling inside `gh`.

- *Auto-detect the PR number from `git config branch.<current>.merge`
  or from a recent `git push`.* Rejected for v1.
  - PRD Known Limitation #4 explicitly defers this.

- *Detect `CI` and force-skip PR-context detection in non-CI
  environments.* Rejected.
  - PRD R5 binds detection to the env-var surface, not to a CI/non-CI
    signal. The `SHIRABE_PR_NUMBER` override exists precisely so
    local invocations against a PR can engage Sub C.

**Citation.** PRD R4 (auth chain), R5 (PR-context env-var surface),
R15 (token never leaked), Out-of-Scope item 7 (no shared PR-context
layer in v1).

## Decision Outcome

FC09 is one check function in `crates/shirabe-validate/src/checks.rs`,
dispatched in the `Plan` and `Roadmap` arms of `validate_file`
alongside FC05, FC06, and FC07. It consumes the parsed `Table` (with
the `terminal` and `status` fields FC07's Decision 6 added) and the
extracted `Diagram` (produced by the existing `mermaid.rs` module);
the new substrate it adds is an `IssueStateClient` trait declared in
the new `gh.rs` module plus its `GhSubprocessClient` production impl
and the `MockIssueStateClient` test stand-in. The three sub-checks
run in a single pass over the diagram's class assignments; Sub A and
Sub B follow the same shape as FC07's `class_vs_status_pass` but
swap `Row.terminal` for `client.fetch_issue_state`, and Sub C runs a
separate post-pass over the PR body's `Closes #N` lines. Notice
membership joins the existing `is_notice` function via a third match
arm (Decision 6); notices are per-defect in FC05/FC06/FC07 voice
(Decision 4). Tests use inline-string fixtures with a trait-based mock
client (Decision 3). PR-context detection is co-located with the
client (Decision 2 and Decision 7). The per-request timeout is 5
seconds; the retry policy is exactly one retry on rate-limit errors
with a 2-second back-off (Decision 5).

The seven decisions compose: Decision 1 fixes the transport, Decision 2
fixes the trait surface and the module boundary, Decision 3 fixes how
the contract is tested, Decision 4 fixes the notice voice, Decision 5
fixes the bounded-behavior knobs, Decision 6 fixes the membership
wiring, and Decision 7 fixes the env-var detection. No decision
contradicts the parent design's Decision 3: the notice-then-error
staging is preserved, the no-new-dependency posture is preserved
(`gh` is already a workspace dependency), and the single-point
promotion seam is preserved. No decision contradicts the FC07
sub-DESIGN: the module layout follows Decision 1, the notice voice
follows Decision 2, the membership seam follows Decision 3, the
fixture pattern follows Decision 4, and the doc-comment-binding
discipline follows Decision 5.

## Solution Architecture

### Components

- **`crates/shirabe-validate/src/gh.rs` (new).** Declares the
  `IssueStateClient` trait, the `IssueState`/`ClientError` data
  types, the `PrContext` struct, the `GhSubprocessClient` production
  impl, the `detect_pr_context()` env-var reader, and the
  `#[cfg(test)] MockIssueStateClient` test stand-in. No external
  dependency beyond `std::process::Command`, `std::env`,
  `std::time::Duration`, and the `regex` carrier the crate already
  uses (for PR-body `Closes #N` extraction and `GITHUB_REF` parsing).
  The module is a leaf -- it does not depend on `crate::table`,
  `crate::doc`, `crate::mermaid`, or `crate::checks`.

- **`crates/shirabe-validate/src/checks.rs` (modified).** Adds
  `check_fc09(doc: &Doc, spec: &FormatSpec, client: &dyn IssueStateClient,
  pr_ctx: Option<&PrContext>) -> Vec<ValidationError>` next to
  `check_fc07`. The function returns an empty vec when the spec has
  no `issues_table_columns` (the same no-op gate FC05, FC06, and
  FC07 use), then loads the parsed `Table`, locates the diagram
  block, extracts the views, and runs the three sub-checks.
  Per-issue notices the extractor surfaces are not re-emitted by
  FC09 (FC07 already emits them); a `MissingBlock` from the
  extractor short-circuits FC09's per-node passes the same way it
  short-circuits FC07's.

- **`crates/shirabe-validate/src/validate.rs` (modified).** Extends
  `is_notice` to include the `FC09` arm (Decision 6) and adds the
  FC09 dispatch in the `Plan` and `Roadmap` arms of `validate_file`.
  The dispatch constructs a `GhSubprocessClient` once at function
  entry and calls `detect_pr_context()` once; both are passed by
  reference to `check_fc09`. A construction failure (e.g., `gh
  auth status` returns non-zero) results in the client returning
  `Err(ClientError::Auth)` on its first use; `check_fc09` converts
  that to the missing-credentials skip notice.

- **`crates/shirabe-validate/src/lib.rs` (modified).** Adds
  `pub mod gh;`. No re-exports are added at the crate root for the
  `gh` types -- the crate doc comment's "Public exports are unstable
  across shirabe versions" posture applies; in-crate code that needs
  the types reaches them through the `crate::gh::*` path.

### Key Interfaces

```rust
// gh.rs (new module)
pub trait IssueStateClient {
    fn fetch_issue_state(&self, owner: &str, repo: &str, number: u64)
        -> Result<IssueState, ClientError>;
    fn fetch_pr_body(&self, owner: &str, repo: &str, number: u64)
        -> Result<String, ClientError>;
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum IssueState { Open, Closed }

#[derive(Clone, Debug)]
pub enum ClientError {
    Auth,
    NotFound,
    Forbidden,
    RateLimit,
    Network,
    Malformed(String),
}

pub struct GhSubprocessClient {
    timeout: std::time::Duration,
    gh_bin:  String,
    auth_ok: bool,
}

impl GhSubprocessClient {
    pub fn new() -> Self;
}

impl IssueStateClient for GhSubprocessClient {
    fn fetch_issue_state(&self, owner: &str, repo: &str, number: u64)
        -> Result<IssueState, ClientError> { /* ... */ }
    fn fetch_pr_body(&self, owner: &str, repo: &str, number: u64)
        -> Result<String, ClientError> { /* ... */ }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PrContext {
    pub owner: String,
    pub repo: String,
    pub number: u64,
}

pub fn detect_pr_context() -> Option<PrContext>;
```

```rust
// checks.rs (new function signature)
pub fn check_fc09(
    doc: &Doc,
    spec: &FormatSpec,
    client: &dyn IssueStateClient,
    pr_ctx: Option<&PrContext>,
) -> Vec<ValidationError>;
```

```rust
// validate.rs (updated is_notice)
pub fn is_notice(err: &ValidationError) -> bool {
    matches!(err.code.as_str(), "SCHEMA" | "FC07" | "FC09")
}
```

### Data Flow

`validate_file(doc, spec, cfg)` runs the schema gate, the visibility
gate, FC01-FC04, and then dispatches to the format-specific arm. In
the `Plan` and `Roadmap` arms, the existing order (FC05, FC06, FC07)
is extended with FC09. The dispatch constructs the production client
once and the PR-context once; the per-doc cost is one `gh auth status`
call (inside `GhSubprocessClient::new`) and one env-var read (inside
`detect_pr_context`).

`check_fc09` then:

1. Returns empty if `spec.issues_table_columns` is empty (same no-op
   gate FC05-FC07 use).
2. Parses the issues table (reusing `parse_issues_table`).
3. Locates the diagram block (`find_dependency_graph_block`) and
   extracts the views (`extract_diagram`); on `MissingBlock`, returns
   the FC07-already-emitted notice path -- FC09 contributes nothing
   without a diagram to reconcile.
4. Probes the client for credentials by calling `fetch_issue_state`
   for the first reconcilable row; if it returns
   `Err(ClientError::Auth)`, emits the missing-credentials skip
   notice and returns.
5. Iterates over the diagram's `class_assignments`, filtering to
   Status-bearing classes (`done`, `ready`, `blocked`) and to
   `^I[0-9]+$` node ids -- the same filters FC07's
   `class_vs_status_pass` applies. For each surviving assignment:
   - Resolves the corresponding `Row` via the same profile-aware
     lookup FC07 uses (`I<n>` -> `#n` for Plan, `I<n>` -> row whose
     Issues cell contains `#n` for Roadmap).
   - Calls `client.fetch_issue_state(owner, repo, n)` for the issue
     number derived from the node id. The `(owner, repo)` pair comes
     from `pr_ctx` for same-repo references; for cross-repo
     references (the row's Dependencies cell carries
     `owner/repo#<n>` form), the cross-repo `(owner, repo)` is
     parsed from the cell.
   - Maps the result onto Sub A or Sub B per the truth table below
     and emits at most one notice per row per sub-check.
6. If `pr_ctx` is `Some`, fetches the PR body once via
   `client.fetch_pr_body(pr_ctx.owner, pr_ctx.repo, pr_ctx.number)`
   and runs Sub C: extracts `Closes #N` lines (case-insensitive
   match against the conventional keywords `closes`, `fixes`,
   `resolves`), reconciles in both directions per R13. If `pr_ctx`
   is `None`, emits the missing-PR-context skip notice once.

The truth tables for Sub A and Sub B:

| Doc claim | GitHub observes | Sub A fires? | Sub B fires? |
|---|---|---|---|
| terminal + class `done` | Closed | no | -- |
| terminal + class `done` | Open | YES | -- |
| non-terminal + class `ready`/`blocked` | Open | -- | no |
| non-terminal + class `ready`/`blocked` | Closed | -- | YES |
| terminal + class `done` | RateLimit (after retry) | self-disable | -- |
| anything | Forbidden / NotFound (cross-repo) | per-row skip | per-row skip |
| anything | Malformed / Network | no notice for this row | no notice for this row |

The retry orchestration sits between the iterator and the client:

```rust
for assignment in eligible_assignments {
    match client.fetch_issue_state(owner, repo, n) {
        Ok(state) => emit_for(state, ...),
        Err(ClientError::RateLimit) => {
            std::thread::sleep(Duration::from_secs(2));
            match client.fetch_issue_state(owner, repo, n) {
                Ok(state) => emit_for(state, ...),
                Err(ClientError::RateLimit) => {
                    emit_rate_limit_skip();
                    break; // skip subsequent rows in this run
                }
                Err(e) => handle_other(e),
            }
        }
        Err(e) => handle_other(e),
    }
}
```

### Scope, in and out

FC09 reconciles:

- Status-bearing classes (`done`, `ready`, `blocked`) on `^I[0-9]+$`
  nodes. Same subset FC07 reconciles for its class-versus-Status
  pass. Pipeline-stage classes (`needsDesign`, `needsPrd`, ...) and
  custom-mnemonic external nodes are excluded.
- Same-repo issue references: the `(owner, repo)` pair from `pr_ctx`.
- Cross-repo issue references: the `owner/repo#N` form parsed from
  the row's Dependencies cell (same parser FC06's R6 uses).
- PR `Closes` keywords: `closes`, `fixes`, `resolves`, case-insensitive,
  with optional cross-repo `owner/repo#N` qualifiers. Matches the
  set the GitHub UI itself recognises.

FC09 does not reconcile:

- Pipeline-stage classes (PRD R2). Their semantics are pre-binding,
  not GitHub-issue-state, so no reconciliation makes sense.
- Custom-mnemonic external nodes (PRD R2). These represent cross-repo
  features whose tracking issue ids are intentionally hidden from the
  doc; FC09 has no `(owner, repo, number)` to query.
- Rows whose Issues cell is `None` in the roadmap profile (PRD R2).
  These contribute no expected node and therefore no FC09 reconciliation.
- Rows whose issue cannot be fetched for reasons other than
  rate-limit or cross-repo denial (PRD R14). 5xx, malformed payloads,
  unexpected schemas -- these contribute no per-row notice and the
  check proceeds.
- Sub C in the absence of PR context (PRD R7). Sub A and Sub B still
  run.
- The committed corpus's pre-cleanup state. FC09 ships at notice
  level so the corpus reconciles incrementally (PRD R10, R11).

## Implementation Approach

The work decomposes into six implementation steps. The first four are
sequential; the last two compose the rollout.

### Step 1: Add `gh.rs` with the trait, the data types, and the PR-context detector

Create the new module. Declare `IssueStateClient`, `IssueState`,
`ClientError`, `PrContext`, the empty `GhSubprocessClient` struct
(constructor only, no method impls yet), and `detect_pr_context()`.
Unit-test `detect_pr_context` against the env-var matrix from
Decision 7 (override-only, `GITHUB_REF`-only, both-set, neither-set,
malformed `GITHUB_REF`, malformed `GITHUB_REPOSITORY`, malformed
override). Add `pub mod gh;` to `lib.rs`.

### Step 2: Implement `GhSubprocessClient` and the `MockIssueStateClient`

Implement the two `IssueStateClient` methods on `GhSubprocessClient`:
spawn `gh api`, poll with timeout, parse stdout JSON, classify stderr
patterns. Implement the `#[cfg(test)] MockIssueStateClient` per
Decision 3. Unit-test:

- The subprocess client's success path (a fixture `gh` script that
  echoes a known JSON body).
- Each `ClientError` variant via the same fixture-script pattern.
- The timeout (a fixture script that sleeps longer than 5 seconds).
- The auth probe (a fixture script for `gh auth status` that exits
  non-zero).
- The mock's behavior across all six pinned cases (Decision 3).

The subprocess unit tests gate on the presence of `gh` on `$PATH`;
absent `gh`, they skip with a `cargo test` warning, not a failure
(the workspace CI installs `gh`, so they run there).

### Step 3: Add `check_fc09` and wire it into `validate_file`

Implement the three sub-check passes inside `check_fc09`. The Sub A
and Sub B passes reuse the FC07 `class_vs_status_pass` shape -- same
profile-aware `row_by_id` lookup, same `STATUS_CLASSES` filter, same
`ISSUE_KEYED_NODE_ID` regex. Sub C extracts `Closes #N` lines from
the PR body with a `LazyLock<Regex>` matching
`(?i)(?:closes|fixes|resolves)\s+(?:([^\s/]+)/([^\s#]+))?#(\d+)`.
Wire FC09 into the `Plan` and `Roadmap` arms of `validate_file`. The
dispatch constructs `GhSubprocessClient::new()` once per
`validate_file` call (so the auth probe runs once per doc).

Integration-test the dispatch with at least one plan and one roadmap
fixture per sub-check defect, using `MockIssueStateClient` in every
test. The pinned-fixture set is the eleven cases enumerated in
Decision 3.

### Step 4: Extend `is_notice` to include FC09

Update `is_notice` to the three-arm match expression (Decision 6).
Rename the test to `is_notice_only_schema_fc07_fc09` and update its
body. Update the doc comment to the FC09-aware wording.

### Step 5: Public-cleanliness scan

Walk the committed corpus's notice output by running the compiled
validator with FC09 enabled against `docs/plans/*.md` and
`docs/roadmaps/*.md`. Inspect every emitted notice body for:

- Token bytes (the `GITHUB_TOKEN` value, if set in the running
  shell).
- Private repo names (FC09 in this repo only ever cites `tsukumogami/`
  org members, all of which are public; a private repo name would
  indicate a cross-repo reference into a private repo and would fire
  the cross-repo per-row skip with a public-clean message).
- Pre-announcement features, paths to private files, external issue
  numbers from private repos.

The scan is the PRD R17 acceptance criterion's surface. A passing
scan is one bullet in the implementation PR's verification section.

### Step 6: Notice volume corpus impact survey

Run the validator with FC09 enabled against the full
`docs/plans/*.md` and `docs/roadmaps/*.md` corpus locally. Capture
the notice count. The number goes into the PR body's verification
section as evidence that FC09 ships at a tractable notice volume
(the parent DESIGN's R20 "no-day-one-breakage" invariant; PRD's
Known Limitation #1 about notice volume).

### Dependency between steps

Steps 1, 2, 3, and 4 are sequential because Step 2 depends on the
trait declared in Step 1, Step 3 calls into the impl Step 2 lands,
and Step 4 is the membership wiring that turns the check into a
notice. Steps 5 and 6 run after Step 4 and can be combined with
each other (both are corpus-scoped scans). A single PR carrying all
six steps is the default shape; the FC07 sub-DESIGN's Decision 6
also defaults to a single bundled PR and notes that splitting at the
trait/impl boundary (Step 1 alone) is acceptable if the maintainer
prefers a smaller diff.

## Security Considerations

The FC09 check and its client are total over arbitrary external
input. Each external operation has an explicit 5-second timeout
(Decision 5) and at most one retry on a `RateLimit` error (PRD R8).
The retry surface is bounded -- after the second rate-limit, the
check self-disables for the remainder of the run and does not retry
further rows.

### Subprocess timeout enforcement

The 5-second timeout cannot be expressed as a knob on
`std::process::Command::output()` because stable Rust's standard
library has no built-in subprocess timeout. The implementation
enforces the timeout in user-space without adding a new dependency:

```rust
let mut child = Command::new(&self.gh_bin)
    .args(["api", &path])
    .stdout(Stdio::piped())
    .stderr(Stdio::piped())
    .spawn()
    .map_err(|_| ClientError::Network)?;

let deadline = Instant::now() + self.timeout;
loop {
    match child.try_wait() {
        Ok(Some(status)) => { /* drain stdout/stderr, classify */ break; }
        Ok(None) => {
            if Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                return Err(ClientError::Network);
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        Err(_) => return Err(ClientError::Network),
    }
}
```

The poll-and-kill shape uses only `std::process::Child::try_wait`,
`Child::kill`, and `std::thread::sleep`, all of which are stable
stdlib. The 50ms poll interval gives the watcher sub-second
responsiveness without busy-spinning; the worst-case overshoot of
the 5-second budget is 50ms. No `wait_timeout` crate, no async
runtime, no signal handler.

A separate thread reads the child's `stdout` to completion under a
capped byte budget (see "Subprocess output byte bound" below). When
the timeout fires, `Child::kill` sends SIGKILL on Unix and
`TerminateProcess` on Windows; the subsequent `wait` reaps the
zombie. The pipe is dropped, which closes the reader thread's
handle and lets it unwind.

### Subprocess output byte bound

`gh api` stdout is read into a `String` with an explicit ceiling of
**4 MiB**. The reader uses `Read::read` into a fixed-capacity
buffer; once the cumulative byte count exceeds the ceiling, the
reader signals `ClientError::Malformed("response exceeded 4 MiB
ceiling")` and the polling loop kills the child. GitHub's
documented issue and PR JSON bodies are well under 1 MiB even with
the largest realistic comment/reaction payloads; the 4 MiB ceiling
gives 4x headroom for fields the API may add without forcing the
ceiling to be re-tuned, while bounding worst-case memory in code
rather than relying on "GitHub will not send more." A malicious or
buggy `gh` returning an unbounded stream cannot OOM the validator.

### Defensive parsing of `gh api` stdout

Parsing is intentionally narrow and pinned to the top-level
fields FC09 needs. Two operations:

1. **Issue state extraction.** The `state` field FC09 needs is a
   top-level field of the issue JSON object. To avoid the
   first-match hazard of a permissive regex (the issue JSON
   contains nested fields like `milestone.state`, `pull_request.merged_at`,
   and reaction sub-objects that may textually precede the
   top-level `state` after `gh api`'s key ordering changes), the
   implementation uses a two-step parse: locate the outermost
   `{...}` object via brace-depth counting (constant-time per byte,
   no recursion), then within that scope match the top-level
   `"state"` field via a depth-aware regex that consumes the value
   only when brace-depth is exactly 1. The match expression is:

   ```rust
   // Pseudocode for the depth-aware extraction
   fn extract_top_level_state(body: &str) -> Result<&str, ClientError> {
       let mut depth = 0usize;
       let mut i = 0usize;
       while i < body.len() {
           let b = body.as_bytes()[i];
           match b {
               b'{' => { depth += 1; i += 1; }
               b'}' => { depth = depth.saturating_sub(1); i += 1; }
               b'"' if depth == 1 => {
                   // attempt to match `"state":"..."` starting here
                   if let Some(val) = try_match_state_kv(&body[i..]) {
                       return Ok(val);
                   }
                   i = skip_string_literal(body, i); // safe over UTF-8
               }
               _ => i += 1,
           }
       }
       Err(ClientError::Malformed(String::new()))
   }
   ```

   `try_match_state_kv` uses a precompiled `LazyLock<Regex>` matching
   `^"state"\s*:\s*"([^"]+)"`. `skip_string_literal` advances past
   the current `"..."` token by scanning for the unescaped closing
   quote, never indexing into a multi-byte UTF-8 boundary. The
   captured value classifies as `Open`, `Closed`, or
   `Malformed`.

2. **PR body extraction.** The PR body is the top-level `body`
   field of the PR JSON object. It is extracted by the same
   depth-aware scanner with a matcher for `^"body"\s*:\s*"..."`,
   accounting for JSON's `\"`, `\\`, and `\n` escape sequences.
   The extracted body is treated as opaque UTF-8 text input to the
   `Closes #N` regex; FC09 does not interpret its content beyond
   the regex's matches.

If the depth scanner exhausts input without finding the target
field at depth 1, the call returns `Err(ClientError::Malformed)`
and the per-row notice path absorbs the defect.

### `ClientError::Malformed` payload boundary

`ClientError::Malformed(String)` is a `#[derive(Debug)]` variant
whose payload is consumed by FC09's error-handling path only.
**The payload is never embedded in a notice body, never logged to
stdout or stderr, never written to a file, and never serialized
to any user-visible surface.** The variant's `Debug` impl exists
for unit-test assertions; the production code paths discard the
payload (matching `Err(ClientError::Malformed(_))` with a wildcard
on the inner value). The R17 acceptance scan (Step 5 of the
Implementation Approach) is extended to grep the compiled binary's
output for any string that could plausibly originate from
`gh api`'s stdout, verifying the payload-non-emission invariant
holds in practice.

Future changes that move the `Malformed(String)` payload into a
notice body, a log message, or a `println!`/`eprintln!` call are
explicitly out of scope for this design and would require a
follow-up review. The string parameter exists exclusively for
in-crate debugging and unit tests.

### Token handling

The token is consumed by `gh` itself. The validator process never
reads `GITHUB_TOKEN` and never invokes `gh auth token` (which would
expose the token to FC09's address space). The `gh auth status`
probe at `GhSubprocessClient::new()` reads only the exit code; the
probe's stderr is captured but not interpreted beyond the
auth-success classification. The `gh api` calls themselves consume
the token transparently. No notice body, no log message, no panic
backtrace mentions the token value.

### Subprocess spawning and argument validation

Subprocess spawning uses `std::process::Command` with explicit
argument arrays (no shell interpolation), so a malicious row whose
Dependencies cell contains shell metacharacters cannot escape into
the surrounding process.

The `gh` binary path is the literal string `"gh"` baked into
`GhSubprocessClient::new()`; it is not overridable via env var, CLI
flag, config file, or any other input surface. `Command::new("gh")`
resolves via `$PATH` per stdlib semantics, which is the
workspace-standard binary discovery contract. There is no
attacker-controllable surface that re-points the binary.

The `owner`, `repo`, and `number` arguments are validated against
narrow character sets before being passed to `gh api`:

- `owner` and `repo`: `^[A-Za-z0-9][A-Za-z0-9._-]{0,38}$` (GitHub's
  documented limits).
- `number`: parsed as a `u64` (which already rejects anything
  non-numeric).

This validation applies to **every** source of `owner` and `repo`
substrings, including:

- The `owner` and `repo` from the resolved `PrContext` (sourced
  from `GITHUB_REPOSITORY`).
- The `owner` and `repo` parsed from a row's Dependencies cell
  cross-repo reference (`owner/repo#N` form).
- The `owner` and `repo` parsed from a `Closes owner/repo#N` line
  in the PR body (Sub C cross-repo case).

Any input failing validation is treated as `ClientError::NotFound`
(no `gh api` call is made, no notice is emitted for the
unparseable form) -- the per-row notice path absorbs the defect.
The validation gate runs **before** the substring is included in
any notice body, so attacker-controlled text from the PR body
cannot reach the GHA annotation surface unless it conforms to the
narrow character set the gate enforces.

The notice messages FC09 emits are reviewed against the parent
PRD's R22 public-cleanliness invariant (re-stated as PRD R17) before
the implementation PR merges. The R17 acceptance scan (no private
repo names, paths, filenames, external issue numbers, or
pre-announcement features in notice bodies, plus no token-bytes
appearing anywhere in the validator's process output) is Step 5 of
the Implementation Approach.

FC09 does not read files outside the doc passed to `validate_file`,
does not write to disk, does not invoke processes other than `gh`,
and does not allocate unbounded buffers. Memory usage is linear in
the number of entity rows plus the size of the PR body, with the
PR body itself bounded by the 4 MiB subprocess output ceiling
described above. The PR body is fetched once per doc and cached in
a local variable; it is discarded when `check_fc09` returns.

The four self-disable paths each emit exactly one notice per run for
their corresponding failure mode (with the per-row cross-repo case
producing one notice per affected row, not per affected doc). The
self-disable does not contribute to the validator's exit code; FC09's
notices are at notice level (Decision 6) until the corpus-cleanup PR
promotes the check to error.

## Consequences

### Positive

- The third reconciliation axis is closed without expanding the
  validator's interface surface. `check_fc09` is one function in one
  file; its substrate is one new module; its dispatch is two
  additional lines in `validate_file`'s `Plan` and `Roadmap` arms.
- The trait-shaped client surface makes the test path independent of
  `gh`. Every FC09 test runs in offline CI with no network access.
  A future transport change (raw HTTP, gRPC, batched fetches) reuses
  the same test corpus.
- Joining the existing `is_notice` membership preserves the
  one-seam-one-mechanism rollout shape. The cleanup PR that promotes
  FC09 to error is a one-line diff in production code, mirroring the
  FC07 promotion PR's shape.
- The per-defect notice voice gives authors a mechanical fix path.
  Each notice names the row, the node, the issue number, and the
  observed-versus-expected state; no notice requires the author to
  read a multi-page context document to understand the defect.
- The four self-disable paths preserve the local-dev workflow. An
  author editing a plan without `GITHUB_TOKEN` and without `gh auth`
  configured sees one skip notice; the rest of the validator runs
  normally. FC09 punishes the offline edit cycle nowhere.
- The graceful-degradation posture for cross-repo references means
  one restricted cross-org dependency does not blank the whole
  check. Other rows reconcile normally; the inaccessible row's
  per-row skip names the gap so the author can act on it.

### Negative

- Notice volume on the present committed corpus is bounded by the
  existing doc-versus-GitHub drift; until the cleanup PR lands,
  every plan or roadmap PR may carry FC09 notices. The signal
  degrades if authors learn to skim past FC09 output without reading
  it; the forcing function is the maintainer's cleanup PR, the same
  as FC07's.
- The `gh` subprocess overhead per request (~50-200ms cold-start of
  `gh` plus the actual API round-trip) accumulates linearly in the
  number of entity rows. A doc with 20 rows in PR context costs on
  the order of 4-10 seconds of validator wall-clock under FC09. The
  CI per-job budget absorbs this comfortably; local invocations on
  large corpora are slower than the offline-only validator. A future
  refactor could parallelize the fetches inside `check_fc09` without
  changing the trait surface.
- The `gh` subprocess shape ties FC09's rate-limit detection to `gh
  api`'s stderr wording. If a future `gh` release rewords the
  rate-limit error, FC09's detection regex misses; the defensive
  fallback (any unrecognised non-zero exit maps to `Network`)
  downgrades the failure from "false rate-limit-self-disable" to
  "no per-row notice on the affected row" -- the safer of the two
  failure modes, but still a behavior change the maintainer has to
  notice.
- The trait-based mock pattern adds Rust test boilerplate (a
  `HashMap::new()` plus `.insert(...)` calls) to every FC09 test.
  The alternative (recorded fixtures) was rejected for the reasons in
  Decision 3; the cost is a small amount of test code that scales
  linearly with the case count.
- The `is_notice` membership grows by one arm. The match expression
  is still a single line; the cost is one additional code (`FC09`)
  to remember in the promotion-PR's diff.

### Mitigations

- The notice-erosion risk is mitigated by FC09's per-defect
  specificity: every notice points at a concrete row and node, so an
  author treating the notices as actionable converges on zero
  quickly. The PRD's Known Limitation #1 documents this trade-off
  explicitly; the FC07 rollout shipped behind the same posture and
  the corpus reconciled inside one cleanup PR.
- The subprocess overhead is bounded by the corpus size; a future
  increment can parallelize the fetches if the wall-clock becomes a
  bottleneck. The trait surface is parallelism-friendly (no shared
  mutable state on `IssueStateClient`); a `ParallelClient` wrapper
  could fan out without changing `check_fc09`'s loop.
- The `gh`-stderr-pattern brittleness is mitigated by the defensive
  fallback: an unrecognised non-zero exit maps to `Network` rather
  than `RateLimit`, so a wording change downgrades the failure mode
  rather than introducing false positives. A unit test pins the
  current `gh` rate-limit strings against a recorded sample; a `gh`
  upgrade that breaks the pattern surfaces in CI as a test failure,
  not as a silent corpus drift.
- The mock-boilerplate cost is bounded by the case count from
  Decision 3 (eleven pinned cases); a helper function inside the
  `#[cfg(test)]` module can reduce per-test boilerplate to one line
  per case if maintenance becomes a concern.
- The promotion-PR diff size is bounded by Decision 6 -- two lines
  in production code (the match arm plus the doc comment update)
  and three lines in test code (the test rename, the FC09
  positive-assertion removal, the for-loop addition). The cleanup
  PR's reviewability is identical to FC07's.

## References

- **Upstream PRD.** `docs/prds/PRD-doc-vs-github-state-reconciliation.md`
  (R1-R17 and 28 acceptance criteria; PRD Decisions 1-6 frame this
  design's seven decisions).
- **Parent DESIGN (the Decision 3 this design refines).**
  `docs/designs/DESIGN-roadmap-plan-standardization.md`, Decision 3
  ("The mermaid-parser spike and the staged reconciliation check");
  the notice-then-error staging posture and the no-new-dependency
  anchor.
- **FC07 sub-DESIGN (the architectural precedent).**
  `docs/designs/current/DESIGN-table-diagram-reconciliation.md`
  (Decisions 1-6: separate-module layout, per-defect notice voice,
  membership-entry promotion seam, inline-string fixtures,
  doc-comment binding for non-obvious conventions, `Row.terminal`
  loop FC09 extends).
- **Canonical issues-table conventions.**
  `references/issues-table.md` (Status column for the roadmap
  profile; strikethrough-on-done for the plan profile;
  `owner/repo#N` form for cross-repo Dependencies cells).
- **Canonical dependency-diagram conventions.**
  `references/dependency-diagram.md` (Status-class palette FC09
  binds to; pipeline-stage classes FC09 ignores;
  custom-mnemonic external-node exclusion).
- **Validation precedents.**
  `crates/shirabe-validate/src/checks.rs` (FC05, FC06, FC07 voice;
  `class_vs_status_pass` -- the loop FC09 extends);
  `crates/shirabe-validate/src/validate.rs` (the dispatcher and the
  `is_notice` membership FC09 joins);
  `crates/shirabe-validate/src/table.rs` (the `Row.terminal` and
  `Profile` infrastructure FC09 reads);
  `crates/shirabe-validate/src/mermaid.rs` (the `Diagram` extractor
  FC09 reuses).
