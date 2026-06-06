---
schema: design/v1
status: Planned
problem: |
  The completion cascade (`run-cascade.sh`) re-implements in bash three things the
  Rust transition engine already owns -- frontmatter parsing, per-artifact-type
  dispatch, and the per-type terminal-transition decision -- so the two copies drift,
  and the bash copy cannot explain engine rejections (it surfaces a bare `{` from
  `head -1` on the engine's JSON error).
decision: |
  Add a `shirabe finalize-chain <plan>` subcommand that walks the PLAN's upstream
  chain, resolves each node's type via `detect_format`, and applies the terminal
  transition for the tactical nodes (DESIGN, PRD, BRIEF) in-process by calling the
  existing public `run_transition`, emitting a typed JSON report. It stops at a
  ROADMAP or VISION node, handing that path back to the caller. `run-cascade.sh`
  shrinks to git orchestration plus the unchanged roadmap handler.
rationale: |
  The transition engine is already public-exported (`run_transition`, `detect_format`,
  `transition_spec`, `Outcome`, `TransitionError`), and `Outcome::to_json()` owns
  serialization, so in-process reuse needs no new engine surface and avoids
  subprocess/JSON-scraping. Keeping git and the external-state roadmap handler in bash
  honors the CLI's no-git boundary and the PRD's scope.
upstream: docs/prds/PRD-finalize-chain.md
---

# DESIGN: finalize-chain

## Status

Planned

## Context and Problem Statement

The post-implementation completion cascade lives in `skills/work-on/scripts/run-cascade.sh`.
Its behavior was established by `docs/designs/current/DESIGN-completion-cascade.md` and
extended to handle BRIEF nodes. The cascade walks a finished PLAN's `upstream`
frontmatter chain and brings each node to its terminal lifecycle state: the PLAN is
deleted (`git rm`), a DESIGN has its stale `## Implementation Issues` section stripped
and moves to its Current state, and a PRD and a BRIEF move to Done. It then updates a
ROADMAP feature's status and, when every feature is Done and every referenced issue is
closed, transitions the ROADMAP itself.

To do the tactical-node work, the script re-implements logic the Rust transition engine
already owns:

- An inline awk frontmatter reader (`get_frontmatter_field`, lines 70-87) reads each
  node's `upstream` field -- a second frontmatter parser beside the engine's.
- Two filename-prefix `case` blocks (the validation-error block at lines 591-597 and the
  main dispatch at lines 618-653) mirror the engine's own format detection.
- Each handler hardcodes the legal target status for its type (`handle_design` to
  Current, `handle_prd`/`handle_brief` to Done) -- the decision the engine's transition
  spec table already encodes.

Two copies of the same lifecycle knowledge, in two languages, drift. The drift is
observable: every handler captures `head -1` of the engine's output as its failure
detail (lines 267, 301, 330, 449), and because the engine reports rejections as JSON,
that first line is a bare `{`. The cascade emits a brace as its error message, with no
awareness of why the transition was refused. The engine holds that knowledge; the bash
glue structurally cannot.

This design moves the tactical chain walk, per-node type resolution, and the per-type
terminal-transition decision into a `shirabe finalize-chain` subcommand backed by the
existing engine, while leaving git operations and the external-state ROADMAP handler in
the script. The PRD (`docs/prds/PRD-finalize-chain.md`) fixes the requirements; this
design picks the mechanism.

## Decision Drivers

- **Single authority.** The lifecycle decisions must have exactly one home (the engine),
  so the bash copy cannot drift from it (PRD R1, R2, R9).
- **No new engine surface if avoidable.** Reuse what `shirabe-validate` already exports
  rather than widening the public API.
- **The single-document `transition` contract is frozen.** The PRD's Out of Scope reuses
  `transition` unchanged; this design must not alter its behavior or output.
- **The CLI does not own git.** Remove/move/stage/commit/push stay in the caller
  (PRD R4, R9).
- **Preserve the cascade's external contract.** `run-cascade.sh` must keep emitting the
  same `cascade_status` and `steps[]` the work-on workflow consumes (PRD R8, R10).
- **Type-aware errors.** A refused transition must explain itself (PRD R6, R7).

## Considered Options

### Decision 1 -- How finalize-chain reuses the engine

- **Option A: Call `run_transition` in-process per node (chosen).** `shirabe-validate`
  re-exports `run_transition(file, target_status, &Flags) -> Result<Outcome, TransitionError>`,
  `detect_format`, `transition_spec`, `Outcome`, and `TransitionError`. `Outcome::to_json()`
  owns serialization. finalize-chain lives in the same binary and calls these directly.
- **Option B: Shell out to the `transition` CLI per node.** Rejected: re-parses JSON,
  re-spawns the process per node, and re-derives paths the engine already returns; gives
  no type-safety advantage over a direct call within the same binary.
- **Option C: Extract a new shared "finalize" library entry point.** Rejected as
  premature: the existing public surface is sufficient; a new abstraction would be
  speculative until a second consumer needs it.

### Decision 2 -- Where the `## Implementation Issues` strip lands

- **Option A: finalize-chain strips it as a DESIGN-node step, before calling
  `run_transition` (chosen).** Porting `strip_implementation_issues` (awk, lines 182-200)
  into the subcommand removes it from bash and keeps it deterministic and local, without
  touching the single-document `transition`.
- **Option B: Fold the strip into the engine's design->Current transition.** Rejected: it
  would change the single-document `transition` behavior, which the PRD freezes. A caller
  transitioning a design mid-flight would not expect its issues table silently removed --
  the strip is a finalization concern, not a generic-transition concern.
- **Option C: Keep the strip as a bash pre-step.** Rejected: leaves design-specific
  content logic in the script, undercutting the goal of removing per-type logic from bash.

### Decision 3 -- How the slimmed script preserves its output contract

- **Option A: finalize-chain emits a typed report; the script translates it into the
  existing `steps[]`/`cascade_status` and drives git (chosen).** The subcommand returns
  per-node entries (type, action, old/new status, new_path); the script maps each entry
  to a `steps[]` object with the existing action names, aggregates `cascade_status`,
  `git add`s the reported paths, and keeps ownership of the PLAN `git rm`, the commit,
  and the push.
- **Option B: Replace the script's stdout with finalize-chain's richer output.**
  Rejected: the work-on workflow parses `.cascade_status`; changing the contract ripples
  downstream for no user benefit (PRD Decision, R8).

### Decision 4 -- How the ROADMAP node is handled

- **Option A: finalize-chain stops at a ROADMAP/VISION node and reports it; bash keeps
  its existing roadmap handler (chosen).** ROADMAP work is awk body-surgery on a feature
  block plus a `gh`-issue completion guard -- external-state-dependent, not a deterministic
  local transition -- so it stays in bash per the PRD's Out of Scope. finalize-chain
  reports the roadmap path it stopped at so bash knows to run its handler.
- **Option B: Move roadmap handling into finalize-chain too.** Rejected: it needs network
  (`gh`) and body-prose surgery, violating the subcommand's deterministic-local constraint
  (PRD R11) and exceeding scope.

## Decision Outcome

`shirabe finalize-chain <plan>` walks the PLAN's `upstream` chain in-process. For each
node it calls `detect_format` to resolve the format, then dispatches on the resolved
format name (`Design`, `Prd`, `Brief`, `Roadmap`, `Vision`, `Plan`). A format that
carries no `transition_spec` entry -- `Plan` -- has no terminal transition to apply and
routes to the delete/handoff path rather than a transition. The dispatch is:

- **DESIGN:** strip `## Implementation Issues`, then `run_transition(path, "Current")`;
  report `transition_design` with the returned `new_path` and `moved`.
- **PRD:** `run_transition(path, "Done")`; report `transition_prd`.
- **BRIEF:** `run_transition(path, "Done")`; report `transition_brief`.
- **ROADMAP / VISION:** stop the walk; report the node as a handoff (no transition).
- **Unknown prefix:** stop with a typed error.

It treats the input PLAN as a delete node -- the PLAN filename resolves to the `Plan`
format, which carries no `transition_spec`, so there is no terminal transition to apply
-- and reports it for deletion without removing it. On success it prints a JSON report
following the `Outcome` envelope style; on a refused transition it prints a structured
error naming the node, its type, the attempted transition, and the engine's reason, and
exits with the engine's level codes (1 tool error, 2 lifecycle violation, 3 I/O),
reserving 0 for clean success.

One version-control action does occur within the subcommand: relocating a DESIGN to the
`current/` directory, which `run_transition` performs today via `git mv` (falling back to
plain `mv`). That is `transition`'s existing, frozen behavior, inherited by reuse -- not
new git logic. finalize-chain adds no new git operations; the caller still owns the PLAN
`git rm`, staging the transitioned files, the commit, and the push.

`run-cascade.sh` shrinks to: `git rm` the PLAN, invoke `finalize-chain`, translate the
report into the existing `steps[]`/`cascade_status` contract, `git add` the reported
paths (using `new_path` for a moved design), run its unchanged roadmap handler on any
reported roadmap node, then commit and push. The single-document `transition` is
untouched. There is no longer any tactical-type `case` block or frontmatter parser in the
script; the one type-specific branch that remains is the ROADMAP handler, which is
explicitly out of scope.

## Solution Architecture

### Components

1. **`finalize-chain` subcommand** (`crates/shirabe/src/main.rs`): a new variant in the
   `Commands` enum beside `Transition`, taking a single `plan: String` argument. Its
   command handler calls into the library and maps the library `Result` to process exit
   codes exactly as `run_transition_cmd` does today (0 / `err.code`).

2. **Chain-walk + finalize logic** (`crates/shirabe-validate`, a new module, e.g.
   `finalize.rs`): the orchestration that reads the chain, resolves each type, applies
   the tactical transitions, and builds the report. It depends only on already-public
   pieces: `parse_doc` (reading the upstream link from `fields.get("upstream").value`),
   `detect_format`, and `run_transition`. A small ported `strip_implementation_issues`
   helper handles the DESIGN body edit.

3. **The report type**: a serializable struct enumerating an ordered list of node
   results, each carrying `path`, resolved `type`, `action`
   (`delete_plan` | `transition_design` | `transition_prd` | `transition_brief` |
   `roadmap_handoff` | `stop`), `old_status`/`new_status` (when transitioned),
   `new_path`/`moved` (for the design move), and a per-node `status`/`detail` for
   failures. Serialization mirrors the `Outcome::to_json()` envelope style.

### Data flow

```
run-cascade.sh
  git rm PLAN
  finalize-chain PLAN  ──►  parse_doc(PLAN).upstream
                            loop: parse_doc(node) → detect_format → dispatch
                              DESIGN: strip → run_transition(Current) → new_path
                              PRD:    run_transition(Done)
                              BRIEF:  run_transition(Done)
                              ROADMAP/VISION: report handoff, stop
                            emit JSON report
  ◄── report
  for each node entry: git add reported path (new_path if moved)
  if report has a roadmap handoff: run existing roadmap handler (awk + gh guard),
    using the report's DESIGN new_path for the Downstream rewrite → git add
  translate entries → steps[] + cascade_status (preserved contract)
  git commit && git push
```

### Interfaces

- **Input:** the PLAN path (one positional argument), same surface `transition` uses for
  its file argument.
- **Output (success):** JSON report as above, 2-space indented like `transition`.
- **Output (failure):** `{ "success": false, "error": "<node-and-type-aware message>",
  "code": <1|2|3> }`, aggregating the offending node's `TransitionError` with its path and
  resolved type woven into the message.
- **Path safety:** each upstream path is validated (within repo root, regular file,
  tracked) before use; a value that looks like a cross-repo `owner/repo:path` reference
  (unimplemented today) is treated as out-of-scope and stops the walk rather than being
  resolved.

## Implementation Approach

1. **Chain walk + report, read-only first.** Add the subcommand and the `finalize` module
   that walks `upstream`, resolves each node's type, decides the terminal status from the
   spec, and emits the typed report **without** mutating -- a dry-run shape. Unit-test the
   walk, type resolution, the ROADMAP/VISION stop, unknown-prefix error, and the
   no-upstream case.
2. **Apply transitions.** Wire `run_transition` per tactical node and the ported
   `strip_implementation_issues` for DESIGN; populate `new_path`/`moved` in the report.
   Unit-test against fixture chains.
3. **Typed errors + exit codes.** Aggregate `TransitionError` into the node-aware error
   message and map to exit codes 1/2/3; reserve 0 for success. Test each level.
4. **Refactor `run-cascade.sh`.** Remove the tactical `case` blocks and the frontmatter
   reader; invoke `finalize-chain`; translate its report into the preserved
   `steps[]`/`cascade_status`; drive `git add`/rm and keep the roadmap handler. Keep the
   PLAN `git rm`, commit, and push in the script.
5. **Parity.** Keep the seven `run-cascade_test.sh` scenarios green (the test stub already
   emits the per-node JSON each node type expects; only the integration point changes),
   updating only where output deliberately changes, and add subcommand-level tests. This
   is a single-PR change, with step 5 gating: the script refactor (step 4) lands only
   after the subcommand (steps 1-3) is green.

## Security Considerations

- **Path traversal on the chain walk.** A node's `upstream` value is untrusted input. Each
  resolved path must be confined to the repository root and required to be a regular
  tracked file (not a symlink), mirroring the existing `validate_upstream_path` guard
  (lines 97-126) before any read or transition. `run_transition` additionally performs its
  own path validation (exit code 1), giving defense in depth.
- **Cross-repo references.** The `owner/repo:path` upstream syntax is unimplemented; rather
  than attempt resolution (which could reach outside the repo), finalize-chain treats such
  a value as out-of-scope and stops the walk with a clear report entry.
- **No new external surface.** The subcommand performs no network access and spawns no
  subprocess (the `gh` calls stay in the bash roadmap handler, out of this subcommand's
  scope), so it adds no new injection or network-trust surface. Git remains in the caller.
- **No secrets.** The subcommand handles only local document frontmatter and bodies; it
  reads and writes no credentials.

## Consequences

**Positive:**

- One authority for the tactical cascade's lifecycle decisions; the bash copy is gone, so
  it cannot drift from the engine.
- A refused transition explains itself (node, type, attempted transition, reason) instead
  of emitting a bare brace.
- The script shrinks to git orchestration plus the out-of-scope roadmap handler, making it
  far easier to read and audit.
- The single-document `transition` contract and the cascade's external output are both
  untouched, so nothing downstream re-wires.

**Negative / trade-offs:**

- `strip_implementation_issues` is ported from awk to Rust, a small duplication of intent
  until (if ever) the engine grows a general "finalize a design" notion. It is unit-tested
  against the bash behavior.
- One type-specific branch (the ROADMAP handler) remains in bash. This is the documented
  exception to "no per-type dispatch in the script": roadmap handling is external-state
  dependent and explicitly out of scope. A future effort that brings external-state checks
  under the engine could absorb it.
- finalize-chain mutates several documents in one invocation, whereas `transition` mutates
  one. This is intended: `transition` keeps its single-document shape and finalize-chain
  orchestrates it across the chain.

**Mitigations:**

- The parity test scenarios and new subcommand tests pin both the preserved external
  contract and the new behavior, so the refactor's "invisible downstream" claim is
  enforced, not assumed.
- The read-only-walk-first build order (step 1) lets the walk and type resolution be
  validated before any mutation is wired in.
