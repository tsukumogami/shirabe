---
schema: design/v1
status: Current
upstream: docs/prds/PRD-skill-cascade-lifecycle-check.md
problem: |
  The work-on cascade today drives the chain to its strict-mode passing
  state by invoking `shirabe validate --lifecycle . --strict` from
  agent-directed prose in `skills/work-on/SKILL.md`. The agent reads
  the prose, runs the command, parses the output, and decides whether
  to proceed. A misread, a short-circuit, or a silent skip all break
  the discipline. The whole-tree scope also scans every chain in the
  repo on every cascade run, surfacing unrelated drift as noise.
decision: |
  Add a `--lifecycle-chain <DOC-PATH>` CLI flag to the validate
  subcommand. The flag accepts a single doc-path (PLAN, DESIGN, PRD,
  or BRIEF) and validates only the chain containing that doc. The
  chain-targeted mode reuses the existing `discover_chains` walker by
  filtering to the chain containing the input path. The cascade
  script `skills/work-on/scripts/run-cascade.sh` is extended to
  invoke the new mode at a pre-cascade probe (expecting non-zero
  exit) and post-cascade verification (expecting zero exit), parsing
  exit codes deterministically. Skill prose in
  `skills/work-on/SKILL.md` and `skills/plan/SKILL.md` is updated to
  describe the script-driven enforcement model.
rationale: |
  The chain-targeted CLI shape comes from
  `DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06.md`: a new
  flag rather than overloading the existing `--lifecycle` or
  introducing a new subcommand. The cascade script is the natural
  host for the deterministic invocation because it already has the
  PLAN doc path and runs in the `plan_completion` koto state where
  the pre/post probes belong. Exit-code parsing matches the existing
  whole-tree mode's contract and keeps the script simple.
---

# DESIGN: skill-cascade-lifecycle-check

## Status

Current

The DESIGN consumes the PRD's requirements and the chosen CLI shape
from `DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06`. One
architectural choice remains as an obvious-default call surfaced in
the Considered Options section: where the script invocation lives
(inline functions in `run-cascade.sh` vs sibling scripts vs a new
helper script). The Decision Outcome section settles it as
inline-in-run-cascade.

## Context and Problem Statement

The shirabe plugin ships two lifecycle-enforcement paths:

1. **Reusable CI workflow** (`.github/workflows/lifecycle.yml`) —
   adopted per-repo by explicit reference. Catches violations at
   PR-time, whole-tree.
2. **Work-on skill prose** (`skills/work-on/SKILL.md`) — agent-
   directed instruction to run `shirabe validate --lifecycle .
   --strict` before and after the cascade.

Path 1 only protects repos that adopt the workflow. Path 2 is
agent-directed; a misread, a short-circuit, or a silent skip breaks
the discipline silently. A repo using the plugin's `/work-on` skill
without adopting the reusable CI workflow has no deterministic
lifecycle enforcement on its single-pr PRs at ready-for-review time.

The cascade script already exists at
`skills/work-on/scripts/run-cascade.sh` and runs deterministically in
the `plan_completion` koto state — it walks the upstream chain from
the PLAN doc, applies the appropriate transition at each node, and
emits a JSON result. The script knows the PLAN doc path. What it
does not do today is invoke the lifecycle check directly; the
verification is left to the agent.

The fix is two-part:

- Add a chain-targeted CLI mode that the script can invoke with the
  PLAN doc path. The mode walks only that chain, not the whole tree,
  so the cascade does not surface unrelated drift as noise.
- Extend the cascade script to invoke the chain-targeted check
  at the pre-cascade probe (expecting strict-mode failure) and
  post-cascade verification (expecting clean pass), parsing exit
  codes deterministically.

## Decision Drivers

- **Determinism.** The verification must run without agent
  interpretation. The script is the load-bearing element; the agent
  reads the script's output, not the validator's.
- **Scope.** The script's verification scope is the cascade's own
  chain. Whole-tree scope surfaces noise from unrelated chains on
  every cascade run.
- **Backward compatibility.** The whole-tree `--lifecycle <ROOT>`
  contract is consumed by the reusable CI workflow and any external
  caller. It must not change.
- **Pattern consistency.** The new CLI surface should follow the
  existing codebase idiom for validate-subcommand modes (per
  `DECISION-lifecycle-strict-mode-interface-2026-06-06`).
- **Test surface.** The new mode is testable in isolation via unit
  tests against the lifecycle module; the script's integration is
  testable via the existing `run-cascade_test.sh` harness.

## Considered Options

The CLI shape itself is settled by
`DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06`. Two
implementation-detail questions remain.

### Question A: where the cascade script's invocation lives

**Option A.1: inline functions in `run-cascade.sh`.** Add `lifecycle_pre_probe`
and `lifecycle_post_verify` shell functions to the existing script.
Pre-probe runs before the PLAN deletion; post-verify runs after the
final `git commit` of the cascade's staged transitions.

**Option A.2: sibling scripts.** Add `pre-cascade-probe.sh` and
`post-cascade-verify.sh` next to `run-cascade.sh`. The koto template
invokes all three in sequence.

**Option A.3: new helper script.** Add `lifecycle-check.sh` that the
existing `run-cascade.sh` calls at the two points.

**Choice: A.1.** The cascade script already coordinates the
transitions; the pre/post probes belong with the rest of the
cascade's control flow. Sibling scripts (A.2) would require the
koto template to orchestrate three scripts, duplicating the PLAN-
doc-path argument and adding two new invocation points. A helper
script (A.3) adds a layer with no commensurate benefit. Inline
functions keep the cascade as one coherent unit.

### Question B: invocation timing relative to staging

**Option B.1: pre-probe before any staging, post-verify after the final commit.**
The pre-probe sees the working tree as it stood when the cascade
started. The post-verify sees the tree after the cascade's atomic
finalization commit (PLAN deleted, BRIEF/PRD transitioned, DESIGN
promoted).

**Option B.2: pre-probe and post-verify both against staged content.**
Both probes run against the index, not the working tree.

**Choice: B.1.** The lifecycle module reads files from disk, not
from the git index. The probes must run against on-disk content for
the chain-walker to see the chain as it actually is. The pre-probe
runs before any `git rm` or `shirabe transition` has touched the
tree; the post-verify runs after the final `git commit` (so the
working tree reflects the committed state).

## Decision Outcome

**Chosen:**

1. **CLI shape:** `--lifecycle-chain <DOC-PATH>` flag on
   `shirabe validate`, per
   `DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06`.
2. **Cascade script invocation location:** inline functions in
   `skills/work-on/scripts/run-cascade.sh` (Option A.1).
3. **Probe timing:** pre-probe against working tree before any
   transitions; post-verify against working tree after the final
   commit (Option B.1).

The implementation reuses `discover_chains` by filtering to the
chain whose members include the canonicalized input doc-path. The
strict-mode toggle re-targets single-pr-mid-PR to single-pr-at-merge
for the matched chain only, mirroring the whole-tree mode's
behavior.

## Solution Architecture

### Component changes

**`crates/shirabe/src/main.rs`** — extend `ValidateArgs`:

```rust
/// Chain-targeted lifecycle mode. Takes a doc-in-a-chain (PLAN,
/// DESIGN, PRD, or BRIEF) and validates only the chain containing
/// that doc. Mutually exclusive with `--lifecycle` and with
/// positional file arguments.
#[arg(long, value_name = "DOC")]
lifecycle_chain: Option<String>,
```

The mutual-exclusion check in `run_validate` extends:

- `--lifecycle-chain` plus `--lifecycle` => error.
- `--lifecycle-chain` plus positional files => error.
- `--lifecycle-chain` plus `--strict` => allowed (works together).

A new dispatch arm calls `run_lifecycle_chain(doc_path, visibility,
strict)`, mirroring `run_lifecycle`.

**`crates/shirabe-validate/src/lifecycle.rs`** — add a public
function `run_lifecycle_chain_check`:

```rust
pub fn run_lifecycle_chain_check(
    doc_path: &Path,
    cfg: &Config,
    strict: bool,
) -> Vec<ValidationError>
```

Implementation:

1. Canonicalize `doc_path`. If it does not resolve to a file, return
   a single L05-style error naming the missing path.
2. Verify the path's basename has a recognized prefix
   (`BRIEF-`/`PRD-`/`DESIGN-`/`PLAN-`/`ROADMAP-`). If not, return a
   single L05 error naming the expected prefix set.
3. Determine the implied root directory: walk up from the doc-path
   until a parent directory contains either a `docs/` ancestor or
   the path matches one of the indexed doc dirs. The lifecycle
   module already has the `docs/{briefs,prds,designs,designs/current,plans,roadmaps}`
   enumeration; we derive the root from the doc-path by stripping
   the matching suffix.
4. Call `build_doc_index(root)` to build the same index the
   whole-tree mode uses.
5. Look up the canonicalized doc-path in the index. If missing,
   return a single L05 error ("doc not found in index — is it in
   `docs/`?").
6. Build the inverse-upstream graph (same as whole-tree mode).
7. Call `discover_chains(idx)` and filter to chains whose members
   include the canonicalized doc-path. Expected count: zero (orphan)
   or one (in a chain).
8. If zero chains match, treat the doc as an orphan. Run `check_orphan`
   on the doc and return its single-error-or-none result.
9. If one chain matches, run the same per-chain passing-state check
   the whole-tree mode runs — including the strict-mode posture
   re-target. Errors are sorted and deduplicated the same way.

The function reuses every helper in `lifecycle.rs` — only the chain
selection differs. No new chain-walking logic, no new posture
inference, no new passing-state computation.

**`crates/shirabe-validate/src/lib.rs`** — re-export
`run_lifecycle_chain_check` so `main.rs` can call it.

**`skills/work-on/scripts/run-cascade.sh`** — add two functions and
two invocation points:

```bash
# Run the chain-targeted lifecycle check in strict mode against the
# cascade's PLAN doc. Exit code 0 = clean pass; non-zero = failure.
# Logs the validator's stderr on unexpected outcomes.
lifecycle_probe() {
    local mode="$1"  # "pre" or "post"
    local exit_code=0
    local output
    output=$("$SHIRABE_BIN" validate \
        --lifecycle-chain "$PLAN_DOC" \
        --strict 2>&1) || exit_code=$?

    if [[ "$mode" == "pre" ]]; then
        # Expect failure: the chain has a present PLAN at single-pr-mid-PR.
        if [[ "$exit_code" -eq 0 ]]; then
            log_info "Pre-cascade probe: clean pass — chain already terminal; cascade is a no-op"
            return 1  # signal caller to skip cascade
        fi
        return 0
    elif [[ "$mode" == "post" ]]; then
        # Expect clean pass: cascade has finalized the chain.
        if [[ "$exit_code" -ne 0 ]]; then
            log_warn "Post-cascade verification failed (cascade bug):"
            log_warn "$output"
            return 1
        fi
        return 0
    fi
}
```

The pre-probe runs immediately after the setup section and before
the PLAN deletion. If the pre-probe signals "chain already
terminal," the script emits a `cascade_status: skipped` JSON result
and exits 0 without performing any transitions.

The post-verify runs immediately after the cascade's `git commit`
when `--push` is set. If the post-verify fails, the script emits a
`cascade_status: partial` JSON result with an error step naming the
verification failure and exits non-zero.

When `--push` is NOT set (dry-run mode), the post-verify is skipped
— the script has not committed the transitions, so the chain has
not actually finalized. The pre-probe still runs in dry-run mode to
catch already-terminal chains.

**`skills/work-on/scripts/run-cascade_test.sh`** — add scenarios:

- A single-pr chain mid-PR — pre-probe fails (expected), cascade
  runs, post-verify passes.
- A chain already at terminal — pre-probe passes (early-exit
  signal), cascade does not run, script exits 0 with
  `cascade_status: skipped`.
- A cascade-bug scenario (mock the transitions to leave the chain in
  a bad shape) — pre-probe fails, cascade runs, post-verify fails,
  script exits non-zero.

**`skills/work-on/SKILL.md`** — Completion Cascade section is
rewritten. The four-step sequence becomes a two-step sequence:

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/run-cascade.sh
   --push {{PLAN_DOC}}`. The script runs the pre-probe internally,
   performs the cascade, and runs the post-verify internally.
2. `gh pr ready <pr-number>`.

The agent-directed `shirabe validate --lifecycle . --strict`
invocations are removed. The script is the load-bearing element.

**`skills/plan/SKILL.md`** — the lifecycle reference is extended to
describe both modes: `--lifecycle <ROOT>` for whole-tree (CI
backstop) and `--lifecycle-chain <DOC>` for chain-targeted
(cascade-bundled). The DRAFT-vs-READY discipline section is
unchanged; only the mode coverage is added.

### Component diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ shirabe validate --lifecycle-chain <DOC> --strict               │
│                                                                  │
│  main.rs                                                         │
│   └─> run_lifecycle_chain(doc, cfg, strict)                      │
│        └─> lifecycle.rs::run_lifecycle_chain_check               │
│             ├─> canonicalize doc-path                            │
│             ├─> derive root, build_doc_index(root)               │
│             ├─> discover_chains(idx), filter to chain w/ doc    │
│             └─> per-member passing-state check + strict re-target│
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ run-cascade.sh --push <PLAN-DOC>                                 │
│                                                                  │
│  ├─> setup (resolve SHIRABE_BIN, validate PLAN_DOC)              │
│  ├─> lifecycle_probe "pre"   (expects exit non-zero)             │
│  │     ├─ if exit 0 → log "already terminal" + skip cascade      │
│  │     └─ if exit non-zero → proceed                             │
│  ├─> step 1: git rm PLAN_DOC                                     │
│  ├─> step 2: walk upstream chain, transition each node           │
│  ├─> step 3: git commit, git push (if --push)                    │
│  ├─> lifecycle_probe "post"  (expects exit 0)                    │
│  │     └─ if exit non-zero → emit partial result + exit 1        │
│  └─> emit cascade_status JSON                                    │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Approach

Single-pr execution. The implementation lands in one PR with the
following commit sequence:

1. **Add `run_lifecycle_chain_check` and tests.** Implements the new
   function in `lifecycle.rs`, re-exports from `lib.rs`, adds
   ~8-10 unit tests covering the behaviors enumerated in PRD R9.
   `cargo build` and `cargo test -p shirabe-validate` pass.

2. **Wire the new flag into main.rs.** Adds the `lifecycle_chain`
   field to `ValidateArgs`, extends the mutual-exclusion check,
   adds the `run_lifecycle_chain` dispatch function. The full build
   passes.

3. **Extend `run-cascade.sh` with pre/post probes.** Adds the
   `lifecycle_probe` function, wires the pre-probe before the PLAN
   deletion and the post-verify after the commit. Updates the
   shell test harness with the new scenarios. The shell tests pass.

4. **Update skill prose.** Rewrites the Completion Cascade section
   in `skills/work-on/SKILL.md` and extends the lifecycle reference
   in `skills/plan/SKILL.md`. Adds a cross-link to the new
   Decision Record.

5. **Finalize.** The cascade this PLAN is itself delivering runs at
   merge time — PLAN deleted, BRIEF and PRD transitioned to Done,
   DESIGN promoted from `docs/designs/` to `docs/designs/current/`
   with status Current. The atomic finalization commit is the
   cascade the new code path enables.

## Security Considerations

The new CLI mode accepts a doc-path argument. The implementation
canonicalizes the path and verifies it resolves inside the indexed
doc directories before walking. Path-traversal containment (the
existing L05 check) is reused. No new attack surface is introduced.

The cascade script's invocation of the new mode interpolates
`$PLAN_DOC` into a `shirabe validate` command line. `$PLAN_DOC` is
validated by the script's existing `validate_upstream_path` function
before any subprocess invocation; the path is verified to be tracked
by git and to resolve inside `$REPO_ROOT`. The interpolation is
safe.

No secrets or credentials are touched. No network calls are added.
The new mode reads files only from the doc directories the
whole-tree mode already reads.

## Consequences

**Positive:**
- Any repo using the shirabe plugin's `/work-on` skill gets
  deterministic lifecycle enforcement on every cascade run,
  regardless of CI integration.
- The cascade script becomes the single source of truth for
  pre/post verification; the agent prose is removed from the
  critical path.
- The chain-targeted mode is available for local use ("is this
  one chain healthy?") without scanning the whole tree.
- The whole-tree mode and CI workflow are unchanged.

**Negative:**
- The validate subcommand grows from one mode flag to two.
  Mitigated by mutual exclusion and shared `--strict` behavior.
- The cascade script gains ~50 lines for the probe functions and
  their wiring. Mitigated by all the new logic being inline-and-
  cohesive with the existing transition logic.

## References

- `docs/decisions/DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06.md`
- `docs/decisions/DECISION-lifecycle-strict-mode-interface-2026-06-06.md`
- `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md`
- `docs/briefs/BRIEF-skill-cascade-lifecycle-check.md`
- `docs/prds/PRD-skill-cascade-lifecycle-check.md`
- `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` (parent)
