---
schema: prd/v1
status: Accepted
problem: |
  Lifecycle enforcement today has two distribution paths, both with gaps.
  The reusable CI workflow only protects opted-in repos; the work-on skill
  prose at `skills/work-on/SKILL.md` directs the agent to run the
  chain-aware lifecycle check before and after the cascade, but the
  agent-directed prose depends on the agent invoking the check correctly
  and parsing the output without misreading. Any repo using the shirabe
  plugin's `/work-on` skill without adopting the reusable CI workflow has
  no deterministic lifecycle enforcement on its single-pr PRs at
  ready-for-review time.
goals: |
  Add a chain-targeted CLI mode to `shirabe validate` that takes a doc-in-
  a-chain (typically the PLAN doc) and validates only that chain, reusing
  the chain-walker landed in the prior increment. Wire the work-on
  cascade script (`skills/work-on/scripts/run-cascade.sh`) to invoke the
  chain-targeted check deterministically at pre-cascade probe and
  post-cascade verification points, parsing the exit code without agent
  interpretation. Update prose in `skills/work-on/SKILL.md` and
  `skills/plan/SKILL.md` to describe the script-driven enforcement model.
  Keep the reusable CI workflow unchanged as the cross-chain whole-tree
  backstop.
upstream: docs/briefs/BRIEF-skill-cascade-lifecycle-check.md
source_issue: 175
complexity: Complex
---

# PRD: skill-cascade-lifecycle-check

## Status

Accepted

The PRD operationalizes the upstream BRIEF's framing. One architectural
choice is settled by a separate Decision Record:
`DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06` records the
CLI-shape choice (new `--lifecycle-chain <DOC-PATH>` flag, rejecting
overload of `--lifecycle` and a new `validate-chain` subcommand). The
downstream DESIGN consumes this outcome and the implementation encodes
the new flag.

## Problem Statement

The previous increment landed the chain-aware `shirabe validate
--lifecycle <ROOT>` check, the `--strict` flag that re-targets
single-pr-mid-PR to single-pr-at-merge, and the work-on cascade
sequence that performs the atomic finalization commit. The cascade
runs in the `plan_completion` koto state via
`skills/work-on/scripts/run-cascade.sh` — a deterministic shell script
that walks the upstream chain from the PLAN doc and applies the
appropriate transition at each node.

What is NOT deterministic today is the verification surrounding the
cascade. The current `skills/work-on/SKILL.md` prose tells the agent to
run `shirabe validate --lifecycle . --strict` before the cascade (to
confirm the expected failure naming the present PLAN) and after the
cascade (to confirm the clean pass). The agent is the load-bearing
element: it reads the prose, runs the command, parses the output, and
decides whether to proceed. A misread, a short-circuit, or a silent
skip all break the discipline silently. The script does the cascade
deterministically but leaves the verification to the agent.

A separate gap: the prose-directed verification runs in whole-tree
mode (`--lifecycle .`). That works in repos with one or two chains but
produces noisy output as the corpus grows. Unrelated chains that drift
surface their errors on every work-on cascade run, drowning the
signal the cascade actually cares about — the cascade's own chain
posture.

Any repo using the shirabe plugin's `/work-on` skill without adopting
the reusable CI workflow has no deterministic lifecycle enforcement
on its PRs at ready-for-review time. The CI workflow is the backstop
for repos that adopt it; the plugin's bundled cascade is where the
discipline ships otherwise — and the cascade leaves the verification
to the agent.

## Goals

Bake the chain-aware lifecycle check into the work-on cascade script
deterministically, so that:

- The cascade script invokes the check directly via a chain-targeted
  CLI mode that takes the PLAN doc path and validates only that chain.
- The pre-cascade probe runs first and confirms the strict-mode
  failure (PLAN present, BRIEF/PRD at non-terminal upstream).
- The post-cascade verification runs after the atomic finalization
  commit and confirms a clean pass.
- The script parses exit codes deterministically and fails fast on
  unexpected outcomes (clean pass at the pre-probe, failure at the
  post-verification).
- The chain-targeted mode reuses the chain-walker landed in the prior
  increment by filtering to the chain containing the input doc-path.
- The whole-tree `--lifecycle <ROOT>` contract is unchanged; the
  reusable CI workflow continues to work as the cross-chain backstop.
- The skill prose in `skills/work-on/SKILL.md` and
  `skills/plan/SKILL.md` describes the script-driven enforcement
  model and removes the agent-directed invocation language.

## User Stories

**US-1 (cascade pre-probe).** As the work-on cascade script invoked
by koto in the `plan_completion` state, when the script reaches the
pre-cascade probe point, it runs `shirabe validate --lifecycle-chain
<plan-doc> --strict` and reads the exit code. An exit code of zero
means the chain is already at its terminal — the script logs that
the cascade is a no-op and exits with `cascade_status: skipped`. A
non-zero exit code is the expected outcome at the probe point — the
script proceeds with the cascade transitions.

**US-2 (cascade post-verification).** As the same cascade script,
after the atomic finalization commit (PLAN deleted, BRIEF/PRD
transitioned to Done, DESIGN promoted to Current), the script runs
the same `shirabe validate --lifecycle-chain <plan-doc> --strict`
invocation. An exit code of zero is the expected outcome — the
chain is at its at-merge passing state. A non-zero exit code means
the cascade left the chain in a bad shape (a cascade bug) — the
script logs the validator's stderr and exits non-zero.

**US-3 (local chain audit).** As a chain author iterating on a
single feature's docs, I can run `shirabe validate --lifecycle-chain
docs/plans/PLAN-foo.md` locally to verify my chain is healthy
without scanning every chain in the repo. Errors that surface come
only from my chain's members, not from unrelated drift.

**US-4 (CI backstop unchanged).** As a CI workflow author who has
adopted the reusable lifecycle workflow, my `shirabe validate
--lifecycle . --strict` invocation continues to work unchanged. The
new chain-targeted mode is purely additive at the CLI surface.

## Acceptance Criteria

- [ ] `shirabe validate --lifecycle-chain <DOC-PATH>` walks the chain
      containing the input doc and validates only that chain.
- [ ] `--lifecycle-chain` and `--lifecycle` are mutually exclusive;
      passing both surfaces a clear error.
- [ ] `--lifecycle-chain` works with `--strict`; the strict-mode
      re-target applies to the matched chain only.
- [ ] Non-doc-path inputs (missing file, path outside docs/, file
      with unrecognized prefix) are rejected with a clear error.
- [ ] An orphan doc (no chain participation) at its artifact's
      target state passes; an orphan at non-terminal status fails
      with L02 — same as the whole-tree mode's orphan handling.
- [ ] `skills/work-on/scripts/run-cascade.sh` invokes
      `--lifecycle-chain --strict` at the pre-cascade probe and
      post-cascade verification points.
- [ ] The script parses the exit code only; the validator's stderr
      is logged on unexpected outcomes for debugging.
- [ ] An already-terminal chain (pre-probe clean pass) is detected
      and the script exits 0 with `cascade_status: skipped`.
- [ ] A cascade bug (post-verify failure) causes the script to exit
      non-zero with `cascade_status: partial`.
- [ ] `skills/work-on/SKILL.md` Completion Cascade section is
      rewritten without the agent-directed `shirabe validate
      --lifecycle . --strict` invocation.
- [ ] `skills/plan/SKILL.md` describes both whole-tree and
      chain-targeted modes.
- [ ] The reusable CI workflow at `.github/workflows/lifecycle.yml`
      is unchanged.
- [ ] `cargo build --release` and `cargo test` pass; the cascade
      script's `run-cascade_test.sh` passes.

## Out of Scope

- Replacing whole-tree mode with chain-targeted mode. The CI workflow
  needs whole-tree coverage to catch unrelated drift; the cascade
  needs chain-targeted coverage to avoid noise. Both modes coexist.
- Adding JSON output to the chain-targeted mode. Exit codes plus
  stderr are sufficient for the cascade script's needs and match the
  existing whole-tree mode's output contract.
- Modifying the reusable CI workflow's invocation contract or its
  conditional strict-mode logic.
- Adding new lifecycle rules. The chain-targeted mode reuses the
  existing rules (L01 through L05); only the chain selection differs.

## Requirements

R1. **Chain-targeted CLI mode.** `shirabe validate` gains a new flag
    `--lifecycle-chain <DOC-PATH>` that takes a single doc-in-a-chain
    (PLAN, DESIGN, PRD, BRIEF) and validates only the chain containing
    that doc. Mutually exclusive with `--lifecycle <ROOT>` and with
    positional file arguments.

R2. **Strict-mode compatibility.** `--lifecycle-chain <DOC>` works with
    `--strict`. When both are set, the chain-targeted mode applies the
    strict-mode single-pr-mid-PR re-target to the matched chain only.
    Multi-pr postures are unchanged regardless of strict mode.

R3. **Chain discovery from any node.** The chain-targeted mode walks
    the chain from any input doc — PLAN, DESIGN, PRD, or BRIEF —
    using the existing `discover_chains` walker, filtered to the
    chain containing the input path. A doc not participating in any
    chain (orphan) produces a single-member chain and applies the
    orphan rule.

R4. **Input validation.** A non-doc-path input (a path that does not
    resolve to a file inside `docs/{briefs,prds,designs,designs/current,plans,roadmaps}/`)
    is rejected with a clear error naming the expected location set.
    A path that exists but is not a recognized artifact (no
    `BRIEF-`/`PRD-`/`DESIGN-`/`PLAN-`/`ROADMAP-` prefix) is rejected
    with a clear error.

R5. **Cascade script integration.** `skills/work-on/scripts/run-cascade.sh`
    invokes `shirabe validate --lifecycle-chain <plan-doc> --strict`
    at two natural points:
    - **Pre-cascade probe**, before any transition: expects exit code
      non-zero (the chain is at single-pr-mid-PR; strict mode forces
      a failure naming the present PLAN). A clean pass at the probe
      means the chain is already at its terminal — the script logs
      "cascade no-op for already-terminal chain" and skips the
      cascade.
    - **Post-cascade verification**, after the atomic finalization
      commit: expects exit code zero. A non-zero exit here is a
      cascade bug — the script logs the validator output and exits
      non-zero.

R6. **Deterministic parsing.** The script parses the exit code only —
    no JSON output, no stderr regex. The validator's stderr is logged
    on unexpected outcomes for debugging; the control flow follows the
    exit code.

R7. **Backward compatibility.** The whole-tree `--lifecycle <ROOT>`
    mode is unchanged — same flags, same exit code, same output
    format, same behavior. The reusable CI workflow's
    `shirabe validate --lifecycle . --strict` invocation continues
    to work.

R8. **Prose updates.** `skills/work-on/SKILL.md`'s completion-cascade
    section describes the script-driven enforcement model, naming the
    cascade script as the load-bearing element and removing the
    agent-directed `shirabe validate --lifecycle . --strict`
    invocation. `skills/plan/SKILL.md`'s lifecycle reference is
    updated to describe the chain-targeted mode alongside the whole-
    tree mode.

R9. **Tests.** Unit tests cover the chain-targeted mode's behavior:
    - Single-pr chain mid-PR with strict mode: fails on the present
      PLAN.
    - Single-pr chain at terminal (PLAN absent, BRIEF/PRD Done,
      DESIGN Current) with strict mode: passes.
    - Multi-pr chain in-flight with strict mode: passes (multi-pr
      postures are unchanged by strict).
    - Non-doc-path input: rejects with clear error.
    - Path inside docs/ but with no recognizable artifact prefix:
      rejects with clear error.
    - Orphan doc (chain length 1) at target state: passes via the
      orphan rule.
    - Cascade script test (in `run-cascade_test.sh`): verifies the
      script invokes the chain-targeted check and parses the exit
      code correctly.

R10. **Build and test passes.** `cargo build --release` and `cargo
     test` both pass. The cascade script's shell test
     (`run-cascade_test.sh`) continues to pass.

## Decisions and Trade-offs

**Decision (settled): CLI shape for chain-targeted mode.** A new
`--lifecycle-chain <DOC-PATH>` flag, alongside the existing
`--lifecycle <ROOT>` flag. Rejected alternatives: overloading
`--lifecycle` to accept either a directory or a doc-path (ambiguous
behavior, hard error messages), and a new `validate-chain` subcommand
(misleading verb, more wiring than a flag for an equivalent surface).
See `docs/decisions/DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06.md`.

**Trade-off (accepted): two modes on validate.** The validate
subcommand grows from one mode flag (`--lifecycle`) to two
(`--lifecycle` and `--lifecycle-chain`). Mitigated by both flags
being mutually exclusive and documented in the same `--help`
section, and by both following the same `--strict` toggle behavior.

**Trade-off (accepted): exit code parsing in the script.** The script
parses exit codes only — no JSON output. The validator's stderr is
logged for debugging on unexpected outcomes, but control flow is
exit-code-driven. This matches the existing whole-tree mode's
contract and keeps the script simple.
