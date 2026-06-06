# Decision 1: Transport choice -- `gh` CLI subprocess

## Question

How does FC09's client surface reach the GitHub API: by shelling out to `gh api` or by linking a raw HTTP client crate? PRD R3 and R4 bind the contract (trait surface, env-or-`gh` auth) but explicitly defer transport to the sub-DESIGN (PRD Decision 4 and Out-of-Scope item 3).

## Chosen

`gh` CLI subprocess. The `GhSubprocessClient` shells out to `gh api repos/<owner>/<repo>/issues/<n>` and `gh api repos/<owner>/<repo>/pulls/<n>` once per row plus once per PR, capturing stdout and the process exit code. The token is consumed by `gh` itself via `GITHUB_TOKEN` or `gh auth status`; FC09 never sees the bytes of the token.

## Alternatives considered

- **Raw HTTP client (`reqwest`, `ureq`, `hyper`).** Rejected.
  - Brings a new dependency tree into the crate. Today `shirabe-validate` has three direct deps (`regex`, `saphyr`, `saphyr-parser`). Adding a TLS-capable HTTP client transitively pulls a TLS stack, an async runtime (`reqwest`), or hand-rolled connection handling (`ureq`), pushing the crate from stdlib-flavor into a meaningfully bigger build surface. The parent DESIGN's Decision 3 explicitly anchors the staged-reconciliation increment on "no new dependency" for the mermaid extractor; even though that constraint was scoped to the extractor, the spirit applies to the validator's surface.
  - Auth handling becomes FC09's responsibility. With `gh` the token flows through `gh auth status`'s precedence (env var, gh-config file, keychain on some platforms); with raw HTTP the validator has to re-implement that fallback. PRD R4 demands the fallback chain works; adopting `gh` reuses the existing implementation.
  - Defensive-parsing surface is larger. Raw HTTP requires parsing TLS errors, connection failures, HTTP status codes, redirect chains, and content types in addition to JSON bodies. The subprocess surface collapses the network surface into a single "non-zero exit -> ClientError" decision and a JSON-on-stdout parser.
  - Rate-limit detection is implicit with `gh`: the `gh api` tool emits an HTTP error string that the subprocess wrapper recognises ("API rate limit exceeded for ..."). With raw HTTP, FC09 has to read the `X-RateLimit-Remaining` header in every response.

- **A hybrid -- `gh` for auth discovery, raw HTTP for the calls.** Rejected.
  - Combines the failure modes of both: still pulls the HTTP dependency tree, still re-implements auth precedence (since `gh auth status` does not expose the raw token to stdout in a guaranteed-stable form), still has to handle TLS and connection failures. No win.

- **Defer the transport choice by leaving the trait empty and providing no impl.** Rejected.
  - PRD R3 requires the trait to be implementable; the sub-DESIGN owes a concrete impl that the v1 plan can land. Shipping the trait without an implementation forces the consumer of this design to make the call inside an implementation PR, not inside the design review.

## Rationale

- `gh` is already a hard dependency of the workspace (the shirabe handoff notes that `validate-tsuku-recipe.yml` installs `gh` in its CI lane, and `gh auth status` is the documented dev-setup path for every contributor). The runtime-dep cost is zero; the cost was already paid.
- Subprocess auth, retry, and rate-limit detection collapses meaningful surface area inside `gh` instead of inside FC09. PRD R15 (bounded behavior over arbitrary external input) is easier to defend against a single subprocess boundary than against a TLS + HTTP + JSON + rate-limit stack the validator owns.
- The subprocess shape is testable via a `Box<dyn IssueStateClient>` mock that returns canned `IssueState`/`String` values; FC09's tests never invoke `gh`. PRD R3 (trait surface) is what makes this possible regardless of transport, but it is especially natural over a subprocess where the impl is one well-bounded layer.

## Cost the design absorbs

- A test environment that does not have `gh` on `$PATH` cannot exercise `GhSubprocessClient` end-to-end. Mitigation: `cargo test` covers FC09 entirely through the mock trait impl; the subprocess client itself has a small unit test that invokes `gh --version` and skips if the binary is absent. The workspace CI already installs `gh`, so this only matters for hostile dev environments.
- Subprocess overhead per request (~50-200ms cold-start of `gh`) is real. For a typical plan with ~20 entity rows the worst case is one PR body fetch plus 20 issue-state fetches plus 0-20 retries on 429, i.e. on the order of 4-10 seconds. PRD's bounded-behavior posture (R15) and the rate-limit self-disable (R8) accept this; the alternative (parallel HTTP fan-out) is a refactor option a future increment can pursue if validator wall-clock becomes a bottleneck.

## Citation

- PRD R3 (trait surface), R4 (auth via `GITHUB_TOKEN` or `gh auth status`), R15 (bounded behavior), Out-of-Scope item 3 (transport choice deferred to sub-DESIGN).
- Parent DESIGN Decision 3 (notice-then-error rollout, no-new-dependency posture for the increment family).
- Handoff document `wip/handoff-fc09.md` Phase A (workspace recommendation aligned to `gh` subprocess).
