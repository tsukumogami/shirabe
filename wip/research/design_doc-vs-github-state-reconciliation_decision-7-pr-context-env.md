# Decision 7: PR-context env-var plumbing

## Question

PRD R5 binds FC09's detection of PR context to `GITHUB_REPOSITORY`, `GITHUB_REF` of form `refs/pull/<N>/merge`, and a dedicated `SHIRABE_PR_NUMBER` override. The sub-DESIGN names the exact fallback order, the parser for `GITHUB_REF`, and where the detection lives.

## Chosen

`gh::detect_pr_context() -> Option<PrContext>` reads three env vars in priority order:

1. **`SHIRABE_PR_NUMBER`** -- override. If set and non-empty, parse it as a `u64`. On parse failure, treat as if the override were absent (the missing-PR-context self-disable fires; the validator does not panic on a malformed override). The override is the highest-priority signal because it exists for invocations outside GitHub Actions.
2. **`GITHUB_REF`** -- if set and matches `refs/pull/<N>/merge` (regex `^refs/pull/(\d+)/merge$`), the captured `<N>` is the PR number. Other shapes of `GITHUB_REF` (`refs/heads/<branch>`, `refs/tags/<tag>`, etc.) are not PR contexts and are silently ignored.
3. If neither of the above resolves a PR number, PR context is absent (`None`).

`owner` and `repo` come from `GITHUB_REPOSITORY` of form `<owner>/<repo>` (regex `^([^/]+)/([^/]+)$`). If `GITHUB_REPOSITORY` is unset, PR context is `None` regardless of whether a PR number was discovered (Sub C cannot fire without knowing which repo's PR body to fetch).

The function returns `None` when any required component is missing. It does not return a structured "credentials present, PR context missing" enum -- the caller (`check_fc09`) consults credentials separately (via the client's first call, which returns `Err(ClientError::Auth)` if credentials are missing).

## Env-var precedence rationale

- **`SHIRABE_PR_NUMBER` first** lets a maintainer running `shirabe validate` locally against a PR they have open ship the PR number explicitly. The `gh` CLI cannot in general infer the PR number from the local checkout (a feature branch may not have a PR yet). Naming an explicit override is the cleanest local-dev story.
- **`GITHUB_REF` second** is the GitHub Actions native signal for `pull_request` triggers. PRD R5 explicitly mentions this format. The validator picks it up automatically when it runs inside a GHA workflow without any per-workflow plumbing.
- **No third signal.** PRD's Known Limitations note ("A future increment could extend the detection surface (for example, parsing `git config branch.<current>.merge` for a local PR association), but the v1 contract is the env-var surface only") forecloses additional detection paths. The sub-DESIGN follows.

## Fallback chain for the issue-state token

This is separate from PR-context detection but shares the env-var surface, so it lands here. PRD R4 binds the chain: `GITHUB_TOKEN` first, `gh auth status` second, neither = self-disable.

The chain is implemented inside `GhSubprocessClient` (not inside `detect_pr_context`). `gh api` itself honors `GITHUB_TOKEN` automatically when present and falls back to its own `gh auth status`-configured token otherwise. FC09's only explicit detection step is: before the first `gh api` call, the client runs `gh auth status` once; if it exits 0, the token is available (either via env or via gh-config) and the client proceeds; if it exits non-zero, the client returns `Err(ClientError::Auth)` on every `fetch_*` call and the higher-level `check_fc09` converts that to the missing-credentials self-disable notice.

This means the validator never reads the token bytes directly; it relies on `gh auth status` as the gate and on `gh api` as the consumer. The token is never logged, never echoed, never written to a notice (PRD R15's no-token-leak posture).

## Alternatives considered

- **Read `GITHUB_TOKEN` directly in the validator and pass it as a `--header "Authorization: Bearer <token>"` to `gh api`.** Rejected.
  - Adds a token-handling surface FC09 does not need. `gh api` already does this internally.
  - Increases the leak risk -- the validator process would hold the token in memory and could expose it in a panic backtrace.

- **Use `gh auth token` to extract the raw token from `gh auth status`'s configured store and pass it onward.** Rejected.
  - Same reason. The point of using `gh` as the transport is to keep the token-handling inside `gh`.

- **Add a fourth env var (`SHIRABE_FC09_GH_PATH`) to override the `gh` binary location.** Rejected for v1.
  - YAGNI. The binary is on `$PATH` in every supported environment. If a future increment needs the override, the sub-DESIGN can be revised.

- **Auto-detect the PR number from `git config branch.<current>.merge` or from a recent `git push` that filed a PR.** Rejected for v1.
  - PRD Known Limitations explicitly defers this. Sub-DESIGN follows.

- **Detect `CI` and force-skip PR-context detection in non-CI environments.** Rejected.
  - PRD R5 binds detection to the env-var surface, not to a CI/non-CI signal. The `SHIRABE_PR_NUMBER` override exists precisely so local-CI-like invocations can engage Sub C.

## Public-cleanliness boundary

`detect_pr_context` reads env vars but does not echo them. The notice strings (Decision 4) name only the env var names, not their values, on the missing-PR-context skip. R17 holds.

## Citation

- PRD R4 (auth chain: env var, then gh auth status), R5 (PR-context env-var surface), R15 (token never leaked), Out-of-Scope item 7 (no shared PR-context plumbing in v1).
- Known Limitations of the PRD ("the v1 contract is the env-var surface only").
- Workspace handoff document Phase D (matching env-var enumeration).
