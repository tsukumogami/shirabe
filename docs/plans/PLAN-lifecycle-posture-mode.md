---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-lifecycle-posture-mode.md
milestone: "Lifecycle posture mode"
issue_count: 4
---

## Status

Active

## Scope Summary

Implements the lifecycle posture model from
`docs/designs/DESIGN-lifecycle-posture-mode.md`: a `ReviewPosture` (`--mode=draft|ready`,
default draft) threaded into the lifecycle check, a posture-aware severity classifier
(L02/L06/L07 draft-tolerable, others always-enforced) that fixes issue #197, and a
context-aware advisory layer that explains a verdict without ever gating on ambient
state. Single PR.

## Decomposition Strategy

**Horizontal.** The design already sequences the work into four layers with a clean
dependency order, and the first layer is a behavior-preserving refactor that the
existing test suite guards as a green bar. Issue 1 introduces the posture plumbing
with no behavior change; Issue 2 turns on the classification (closing #197); Issue 3
adds the advisory layer; Issue 4 updates callers, docs, and evals. Each builds on the
prior, so the chain is linear (1 → 2 → 3 → 4). The components have stable interfaces
between them (the `effective_severity` seam, the advisory module boundary), which
favors horizontal over a walking skeleton.

## Issue Outlines

### Issue 1: feat(validate): introduce ReviewPosture and --mode, behavior-preserving

**Goal**: Add the `ReviewPosture { Draft, Ready }` enum and the `--mode=draft|ready`
CLI flag, thread posture through the lifecycle check in place of `strict: bool`, and
route severity through a single `effective_severity(code, posture)` seam — all with no
change in observable behavior.

**Acceptance Criteria**:
- [ ] `ReviewPosture { Draft, Ready }` exists (named to avoid the existing chain
  `Posture` enum in `lifecycle.rs`).
- [ ] `validate --mode <draft|ready>` parses with `default_value = "draft"`; an
  invalid value is a usage error (exit 1).
- [ ] `--strict` is accepted as a deprecated alias resolving to `--mode=ready` and
  emits a deprecation notice.
- [ ] `run_lifecycle_check` / `run_lifecycle_chain_check` take `ReviewPosture`; the L01
  re-target fires when posture is `Ready` (identical to the old `strict == true`).
- [ ] `effective_severity(code, posture)` replaces every static `is_notice(code)` call
  site (across `validate.rs`, `report.rs`, `main.rs`, `populate.rs`); with the
  draft-tolerable set empty, behavior is identical to today.
- [ ] The existing `cargo test -p shirabe -p shirabe-validate` suite passes unchanged.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe/src/main.rs`, `crates/shirabe-validate/src/validate.rs`, `crates/shirabe-validate/src/lifecycle.rs`

### Issue 2: feat(validate): posture classification closing issue #197

**Goal**: Populate the draft-tolerable set (L02, L06, L07) so those findings resolve to
non-failing notices under `draft` posture and to errors under `ready`, fixing the #197
hard-fail on draft PRs while leaving L03/L04/L05 always-enforced.

**Acceptance Criteria**:
- [ ] `posture_class` classifies L02/L06/L07 as draft-tolerable; L03/L04/L05 and the
  FC-family as always-enforced.
- [ ] A document set with only draft-tolerable findings exits 0 under `draft` and 2
  under `ready`.
- [ ] A document set with an always-enforced finding exits 2 under both postures.
- [ ] The issue #197 reproduction (a BRIEF at Draft with no downstream artifact, the
  head of a fresh chain) exits 0 under `draft` and 2 under `ready` (the L02 case).
- [ ] An Active single-pr PLAN with unticked acceptance criteria — the L06 case, for
  which this PR's own PLAN is a live fixture — exits 0 under `draft` (L06 surfaces as
  a notice) and 2 under `ready`. Running `validate --lifecycle --mode=draft .` on this
  PR's tree passes; `--mode=ready` still fails on the same unticked ACs.
- [ ] A single-pr chain whose PLAN is still present exits 0 under `draft` and 2 under
  `ready` (L01 posture sensitivity preserved).
- [ ] Each finding's JSON `severity` field agrees with the computed exit code.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `crates/shirabe-validate/src/validate.rs`, `crates/shirabe-validate/src/lifecycle.rs`

### Issue 3: feat(validate): context-aware advisory explanation layer

**Goal**: Add an advisory module that explains a verdict in posture terms — reading
only the typed `draft` boolean from `GITHUB_EVENT_PATH` for phrasing — and never
affects the exit code or a finding's enforced status.

**Acceptance Criteria**:
- [ ] An in-flight pass's advisory output names each tolerated finding by code (e.g.
  `L02`) and what it needs before ready.
- [ ] A `ready` failure caused by a draft-tolerable finding states that draft posture
  would pass and names what to fix to stay ready.
- [ ] Identical documents and posture with differing ambient PR context yield an
  identical exit code and JSON result (anti-gating).
- [ ] An absent or malformed event payload degrades to posture-only phrasing (no crash,
  no changed verdict).
- [ ] Advisory output is sanitized so a crafted event payload cannot emit
  control/escape characters into the rendered output.
- [ ] The gate path makes no network call.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `crates/shirabe-validate/src/advisory.rs`, `crates/shirabe-validate/src/gh.rs`, `crates/shirabe-validate/src/report.rs`

### Issue 4: chore(validate): update callers, document classification, evals

**Goal**: Point shirabe's own callers at `--mode`, document the posture classification,
and cover the surface with tests/evals.

**Acceptance Criteria**:
- [ ] `.github/workflows/lifecycle.yml` asserts `--mode=ready` only when
  `github.event.pull_request.draft == false` (else defaults to draft).
- [ ] `skills/work-on/scripts/run-cascade.sh` asserts `--mode=ready` in place of its
  unconditional `--strict`.
- [ ] `docs/guides/lifecycle-posture.md` documents the posture model and the
  draft-tolerable-vs-always-enforced classification table (PRD R10).
- [ ] The `/scope` and work-on cascade JSON pass-throughs still parse the
  `shirabe-validate/v1` envelope (exit-code contract 0/1/2/3 unchanged).
- [ ] `cargo test` is green and any affected evals pass.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code
**Files**: `.github/workflows/lifecycle.yml`, `skills/work-on/scripts/run-cascade.sh`, `docs/guides/lifecycle-posture.md`

## Implementation Sequence

The critical path is the full linear chain: **Issue 1 → Issue 2 → Issue 3 → Issue 4**.
There is no parallelism — each issue depends on the one before it. Issue 1 is a
behavior-preserving refactor (existing tests are the green bar). Issue 2 is the
smallest change that closes issue #197 and can ship value even before the advisory
layer. Issue 3 adds the explanation surface. Issue 4 wires the callers and documents
the contract. All four land in a single PR.
