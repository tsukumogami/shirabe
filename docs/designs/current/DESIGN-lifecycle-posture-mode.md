---
schema: design/v1
status: Current
upstream: docs/prds/PRD-lifecycle-posture-mode.md
decision_provenance: inline-resolved
problem: |
  shirabe validate's lifecycle checking returns one verdict for every context,
  controlled by a single --strict boolean threaded from CI. In-flight findings
  hard-fail (issue #197), a local caller cannot reason about the flag, and the
  result never explains itself. The validator needs a posture concept whose
  verdict stays a pure function of its inputs while the output becomes
  context-aware.
decision: |
  Replace the --strict boolean with an intent-named --mode=draft|ready (default
  draft); thread a Posture enum into the lifecycle check; resolve each finding's
  effective severity through a single posture-aware classifier (L02/L06/L07
  draft-tolerable, others always-enforced); and add an advisory explanation layer
  that reads only local PR context (GITHUB_EVENT_PATH) to phrase why a verdict
  holds and what posture change flips it, never affecting the verdict.
rationale: |
  The verdict stays deterministic (a pure function of docs + posture), so the
  validator remains trustworthy as a gate and as an audit trail; the advisory
  layer gets the ergonomic benefit of context without letting ambient state gate.
  --mode names the author's intent rather than an enforcement level, and the
  in-flight default serves the local/pre-PR case with no ceremony. The change
  reuses the existing notice/error severity seam and the detect_pr_context
  pattern rather than widening the data model.
---

## Status

Current

## Context and Problem Statement

`shirabe validate --lifecycle` is run by an agent drafting a chain locally (no PR
yet), by CI on a draft PR, by CI on a ready-for-review PR, and by ad-hoc manual
runs. Today every caller gets the same verdict for the same documents. The only
control is a `--strict` boolean the reusable `lifecycle.yml` workflow sets from
`github.event.pull_request.draft`, and that boolean only re-targets one finding
(L01, the single-pr-mid-PR posture). Every other lifecycle finding —
orphan/connectivity (L02), outline-ACs (L06), design-location (L07), plus the
always-defect findings L03/L04/L05 — is emitted at error severity regardless of
posture. The result is issue #197: the head of a fresh `/scope` chain (a BRIEF at
Draft with no downstream artifact) hard-fails the lifecycle check on a draft PR.

The PRD (`docs/prds/PRD-lifecycle-posture-mode.md`, R1–R13) requires a posture
concept (in-flight vs review-ready, defaulting to in-flight), a per-finding
draft-tolerable/always-enforced classification, advisory output that explains the
verdict in posture terms, and — critically — a verdict that stays a pure function
of the documents and the declared posture (no ambient state may gate). This design
decides HOW to build that against the existing validator.

The relevant existing seams: `ValidationError` (`doc.rs`) is a flat struct with no
`severity` field; severity is derived per-code by `is_notice(code)`
(`validate.rs`), which buckets findings into `notice` (exit 0) and `error` (exit
2); the lifecycle traversal (`lifecycle.rs`) currently threads `strict: bool` only
into the L01 posture re-target; and `detect_pr_context` (`gh.rs`) already reads PR
number/owner/repo from environment variables for the notice-level FC09 check, but
never reads the `draft` bit and never gates.

## Decision Drivers

- **Determinism (PRD R11).** The verdict — exit code plus `shirabe-validate/v1`
  envelope — must be a pure function of `(documents, posture)`. Identical inputs
  must yield an identical verdict in any environment, so the validator stays
  trustworthy as a gate and the audit trail explains every result from the command
  line.
- **Local-first ergonomics.** An agent drafting locally, before any PR exists,
  must get the in-flight verdict with zero ceremony — the default must be correct.
- **Minimal blast radius.** The reusable `lifecycle.yml` workflow's only consumer
  is shirabe's own self-caller; no external repo pins it, and the binary builds
  from source at-ref. No release/tag coordination is required, and both internal
  call sites can be updated in this change.
- **Reuse existing seams.** The notice/error severity split and the
  `detect_pr_context` env reader already exist; extend them rather than add a
  parallel mechanism or widen the data model.
- **Intent over enforcement.** The interface should name the author's intent
  (drafting vs ready), not an enforcement level (`strict`).
- **Backward-compatible machine contract (PRD R12).** Exit codes 0/1/2/3 and the
  envelope schema must keep parsing for the `/scope` and cascade pass-throughs.

## Considered Options

### Decision 1 — How posture is expressed at the CLI

- **A. Keep `--strict` (status quo).** Rejected: names an enforcement level, not
  intent; a local caller has no basis to choose it; it does not generalize to a
  third posture.
- **B. `--mode=draft|ready`, default `draft` (chosen).** Names the author's
  intent, defaults to the safe in-flight posture, and generalizes. A deprecated
  `--strict` alias (mapping to `--mode=ready`, emitting a notice) is retained for
  one migration window so any unmigrated local caller keeps working.
- **C. CLI auto-detects posture from ambient PR state.** Rejected: a verdict that
  depends on ambient env breaks determinism (the same command flips result as a PR
  goes draft→ready, with nothing on the command line to explain it), and it cannot
  even serve the motivating local case because the draft signal does not exist
  before a PR is opened. Consistent with the prior rejection of git introspection
  for posture detection (`DECISION-multi-pr-posture-detection`).

### Decision 2 — How posture maps to a finding's effect on the verdict

- **A. Add a `severity` field to `ValidationError`, set per finding at production
  time.** Rejected: widens a deliberately flat struct, and scatters posture logic
  across every check that produces a finding.
- **B. A single posture-aware severity resolver (chosen).** Keep the flat struct;
  replace the static `is_notice(code)` with `effective_severity(code, posture)`,
  which returns `notice` for a draft-tolerable code under `draft` posture and
  `error` otherwise. The lifecycle checks keep producing findings unchanged; one
  function owns the posture policy; the exit code is computed from the worst
  effective severity.
- **C. Suppress draft-tolerable findings entirely under `draft`.** Rejected: it
  loses the advisory signal — the author wants to *see* "tolerated now, blocks at
  ready," not have the finding disappear.

### Decision 3 — The advisory explanation

- **A. No advisory; only downgrade severity.** Rejected: PRD R8 requires the
  explanation; a bare notice does not tell the author what posture change flips the
  result or what to fix.
- **B. An advisory layer reading only local context (chosen).** A module composes
  the explanation from `(findings, posture, local PR context)`, where PR context
  comes from `GITHUB_EVENT_PATH` (a hermetic local file the runner writes) plus the
  env `detect_pr_context` already reads. It renders in the human output and adds
  *additive* fields to the JSON envelope; it never changes the exit code or a
  finding's enforced/tolerated status. A failed/absent context read degrades to
  less-specific phrasing.
- **C. Advisory reads `gh`/network.** Rejected: breaks hermeticity (PRD R13) and
  adds a token/auth dependency to a path that must stay offline.

### Decision 4 — Where the `ready` escalation is asserted

- **A. The CI shell asserts it (chosen).** `lifecycle.yml` passes `--mode=ready`
  only when `github.event.pull_request.draft == false`; otherwise it omits the flag
  and the default `draft` applies. The verdict stays an explicit function of the
  command line.
- **B. The CLI reads `GITHUB_EVENT_PATH` and escalates itself.** Rejected for the
  *verdict*: it makes posture ambient and invisible on the command line. (The
  advisory layer in Decision 3 reads the same file, but only to *explain*.)

## Decision Outcome

Introduce a `ReviewPosture { Draft, Ready }` enum — named `ReviewPosture` to avoid
collision with the existing multi-variant `Posture` enum in `lifecycle.rs`, which
models the *chain* posture (single-pr-mid-PR, etc.) and is a distinct concept. The
CLI exposes `--mode=draft|ready` (default `draft`), with `--strict` accepted as a
deprecated alias for `--mode=ready`. `ReviewPosture` is threaded from `run_validate`
into the lifecycle traversal, replacing the current `strict: bool`. A single
`effective_severity(code, posture)` resolver (the evolved `is_notice` seam) decides
each finding's severity: draft-tolerable codes (L02, L06, L07) resolve to `notice`
under `Draft` and `error` under `Ready`; always-enforced codes (L03, L04, L05, and
all FC-family codes, which are not lifecycle and are unaffected) always resolve to
`error`; L01 keeps its existing posture re-target, now driven by the same enum. The
process exit code is computed from the worst effective severity, preserving the
0/1/2/3 contract. Because that same severity value also populates the `severity`
field of every finding in the JSON envelope, `effective_severity` must be the
*single* resolution point threaded through every severity-emitting call site (see
Solution Architecture component 2) so the envelope and the exit code never
disagree. An advisory layer reads local PR context (`GITHUB_EVENT_PATH` +
env) to render a posture-aware explanation in the human output and additive JSON
fields, never affecting the verdict. `lifecycle.yml` and `run-cascade.sh` are
updated to assert `--mode=ready` where they assert strictness today. The
classification is documented in `docs/guides/lifecycle-posture.md`, mirroring the
`posture_class` source of truth.

This satisfies the determinism driver (the verdict is a pure function of docs +
posture), the local-first driver (default `draft`), and reuse (the severity seam
and `detect_pr_context` are extended, not duplicated).

## Solution Architecture

**Components and where they live (`crates/shirabe-validate` unless noted):**

1. **`ReviewPosture` enum** — `Draft | Ready`, named to avoid the existing
   `Posture` (chain posture) in `lifecycle.rs`. Parsed from the CLI in
   `crates/shirabe/src/main.rs` (`ValidateArgs`): `--mode <draft|ready>` with
   `default_value = "draft"`; `--strict` retained as a hidden deprecated boolean
   that, when set, resolves to `ReviewPosture::Ready` and emits a deprecation
   notice. A malformed `--mode` value is a usage error (exits 2 (clap usage
   error)), matching clap's existing invalid-value handling.

2. **`effective_severity(code, posture) -> Severity`** — evolves the current
   static `is_notice(code)` in `validate.rs`. Backed by
   `posture_class(code) -> { DraftTolerable, AlwaysEnforced }`. Draft-tolerable
   set: `L02`, `L06`, `L07`. Everything else (lifecycle L03/L04/L05 and the
   FC-family) is always-enforced. Under `Draft`, a draft-tolerable code resolves to
   `notice`; otherwise `error`. The FC09-style intrinsic notices remain notices in
   both postures. **This resolver must replace every current call to the static
   `is_notice(code)`** — the seam is read at roughly seven sites across
   `validate.rs`, `report.rs`, `main.rs`, and `populate.rs` to set both the JSON
   envelope's per-finding `severity` field and the worst-severity exit-code roll-up.
   All of them must consume `effective_severity(code, posture)` so the envelope's
   `severity` values and the process exit code are computed from one source and
   cannot diverge. That single-source property is also the in-code enforcement of
   the advisory-never-gates invariant (Security Considerations): severity — and
   therefore the verdict — is reachable only from `(code, posture)`, never from the
   advisory layer's context.

3. **Lifecycle threading** — `run_lifecycle_check` / `run_lifecycle_chain_check`
   take `ReviewPosture` instead of `strict: bool`. The L01 single-pr-mid-PR
   re-target fires when `posture == Ready` (identical behavior to today's
   `strict == true`). The findings these functions already produce flow unchanged
   into severity resolution.

4. **Exit-code computation** — unchanged contract. The worst effective severity
   across all findings maps to the exit code: any `error` → 2 (violations); only
   `notice`/none → 0 (clean); tool/IO failures keep 1/3. So a `Draft` run whose
   only findings are draft-tolerable exits 0; the same documents under `Ready` exit
   2.

5. **Advisory layer** — a new module (e.g. `advisory.rs`) exposing
   `explain(findings, posture, pr_context) -> AdvisoryReport`. `pr_context` extends
   `detect_pr_context` (`gh.rs`) to additionally read **only the typed `draft`
   boolean** from the JSON at `GITHUB_EVENT_PATH` when that env var is set (hermetic
   local-file read, size-bounded, parse-failure tolerant → `None`). It does not lift
   any free-form string from the event payload into output. The report distinguishes
   no-PR / draft-PR / ready-PR for phrasing and lists, per draft-tolerable finding,
   what it needs before ready; on a `Ready` failure caused by a draft-tolerable
   finding it states the draft escape hatch. Advisory text is composed only from the
   typed draft bit plus the validator's own finding data (codes, file paths already
   in the envelope), and is run through the same control-character/escape-sequence
   sanitization the human renderer applies, since `report.rs::render_human` emits
   text verbatim. Rendered into the human output by `report.rs`; surfaced as
   additive, non-breaking fields in the JSON envelope. The advisory layer is
   read-only with respect to the verdict.

6. **CI + cascade callers** — `.github/workflows/lifecycle.yml` sets
   `--mode=ready` only when `github.event.pull_request.draft == false` (else omits,
   defaulting to `draft`). `skills/work-on/scripts/run-cascade.sh` replaces its
   unconditional `--strict` with `--mode=ready` (it asserts the terminal posture as
   a forcing function — an explicit-intent use, now named accurately).

7. **Classification doc** — `docs/guides/lifecycle-posture.md` documents the
   posture model and the draft-tolerable-vs-always-enforced table (PRD R10),
   mirroring `posture_class`.

**Data flow:** `main.rs` parses posture → `run_validate` passes `Posture` to the
lifecycle traversal → checks produce findings → `effective_severity(code, posture)`
resolves each → worst severity → exit code + envelope (the gate, pure). In
parallel, the advisory layer reads local PR context and composes the explanation →
human output + additive JSON (advisory, never gates).

## Implementation Approach

- **Phase A — posture plumbing, behavior-preserving.** Add `Posture`, the `--mode`
  flag, and the `--strict` deprecated alias. Thread `Posture` through the lifecycle
  functions, replacing `strict: bool`. Define `effective_severity`/`posture_class`
  with the draft-tolerable set initially equal to the empty set, so behavior is
  identical to today (`Ready` == old strict, `Draft` == old non-strict). Land with
  the existing tests green.
- **Phase B — the classification (fixes #197).** Populate the draft-tolerable set
  with L02/L06/L07 and route their findings through `effective_severity`. Add tests:
  draft-tolerable-only set exits 0 under `Draft`, 2 under `Ready`; always-enforced
  set exits 2 under both; the #197 reproduction (BRIEF-at-Draft chain head) exits 0
  under `Draft`; L01 posture sensitivity preserved.
- **Phase C — advisory layer.** Add `advisory.rs`, extend `detect_pr_context` with
  the `GITHUB_EVENT_PATH` draft read, render advisory output (human + additive
  JSON). Tests: in-flight pass names tolerated findings by code; ready failure names
  the draft escape hatch; identical `(docs, posture)` with differing PR context
  yields identical exit code + JSON (anti-gating); absent context degrades cleanly;
  advisory output is sanitized (a crafted event payload cannot emit control/escape
  characters into the render).
- **Phase D — callers, docs, evals.** Update `lifecycle.yml` and `run-cascade.sh`
  to `--mode`. Write `docs/guides/lifecycle-posture.md`. Update/add evals where the
  posture surface is exercised. Confirm the `/scope` + cascade JSON pass-throughs
  still parse.

## Security Considerations

The security-relevant invariant is **advisory-never-gates**, and it is structural:
the verdict is computed solely from the documents and the declared posture, while
the advisory layer's ambient reads feed only human-facing prose and additive JSON
fields. Consequences:

- **Untrusted event payload — gating channel.** On a pull request from a fork,
  `GITHUB_EVENT_PATH` content is attacker-influenced. Because the verdict is
  reachable only through `effective_severity(code, posture)` — whose inputs are the
  finding code and the declared posture, with no channel to the advisory context —
  a crafted payload cannot move the exit code or a finding's enforced status. The
  read is size-bounded and parse-failure tolerant (degrades to `None`), so a
  malformed payload cannot crash or hang the run.
- **Untrusted event payload — rendering channel.** Separately from gating, advisory
  text is *displayed*, and `report.rs::render_human` emits text verbatim (unlike the
  annotation and JSON paths). If advisory prose lifted arbitrary strings from the
  event JSON, a fork could inject terminal escape sequences into CI logs. The
  mitigation is structural: the advisory layer reads only the typed `draft` boolean
  from the payload (never free-form strings), and all advisory output is passed
  through control-character/escape-sequence sanitization before rendering. So the
  rendering channel carries no attacker-controlled bytes.
- **No path traversal.** The advisory layer reads the file named by the fixed
  `GITHUB_EVENT_PATH` environment variable set by the runner; it does not take a
  path from document content or user argument, so there is no traversal surface.
- **No secrets, no network.** The gate path makes no network call and reads no
  credentials. The advisory layer reads only a local file and env vars; unlike
  FC09's `gh api` path, it shells out to nothing. This keeps the gate hermetic
  (PRD R13).
- **Determinism as a security property.** Because the verdict cannot be moved by
  ambient state, the audit trail (what passed/failed and why, by command line)
  cannot be silently altered by environment manipulation.

No new authentication, authorization, or input-parsing surface is added to the
gate. Security review outcome: low risk, contingent on the advisory/verdict
separation being enforced in code (a finding's severity is resolved only by
`effective_severity(code, posture)`, never by advisory context).

## Consequences

**Positive:**
- Issue #197 is fixed: an in-flight chain head no longer hard-fails on a draft PR.
- Local and draft work gets the correct verdict with no ceremony (default `draft`).
- The result explains itself in posture terms and points at a passing state.
- One documented classification replaces per-check tribal knowledge.
- Determinism is preserved; the machine contract (exit codes, envelope) is
  unchanged for downstream consumers.
- The interface names intent (`--mode`) and disambiguates the cascade's
  forcing-function use of strictness.

**Negative:**
- A public CLI flag changes (`--strict` → `--mode`). Mitigated by the deprecated
  `--strict` alias and a migration window.
- A new advisory code path and a `GITHUB_EVENT_PATH` reader add surface to
  maintain. Mitigated by keeping the advisory best-effort and the reader bounded.
- The richest advisory phrasing is GitHub-Actions-specific (the event file exists
  only there). Mitigated by graceful degradation: outside GHA, the advisory falls
  back to posture-only phrasing with no loss of verdict correctness.

**Mitigations summary:** the `--strict` alias covers migration; the advisory layer
is non-gating and degrades cleanly; the classification is documented; and the
behavior-preserving Phase A de-risks the plumbing before the behavior change in
Phase B.
