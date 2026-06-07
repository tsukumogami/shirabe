---
status: Accepted
decision: |
  The chain-targeted lifecycle mode is exposed as a new
  `--lifecycle-chain <DOC-PATH>` flag on the validate subcommand,
  mutually exclusive with `--lifecycle <ROOT>` and with positional file
  arguments. Default off. The flag accepts a single doc-path (PLAN,
  DESIGN, PRD, or BRIEF inside the indexed doc directories); the
  validator walks the chain containing that doc via the existing
  chain-walker and validates only that chain. The whole-tree
  `--lifecycle <ROOT>` contract is unchanged.
rationale: |
  Mirrors the existing `--lifecycle` flag's shape — same verb, same
  noun, explicit scope qualifier on the new flag. Mirrors the
  `--strict` flag pattern landed in the prior increment ("new flag,
  default off, surfaces in `--help`"). Keeps the reusable CI workflow's
  `--lifecycle .` whole-tree invocation contract unchanged. Avoids the
  behavioral ambiguity an overloaded `--lifecycle` flag would introduce
  (directory-or-doc-path at runtime) and the misleading verb a new
  `validate-chain` subcommand would carry.
---

# DECISION: chain-targeted lifecycle CLI shape

## Status

Accepted

## Context

The chain-aware passing-state lifecycle check landed in the previous
increment is exposed as `shirabe validate --lifecycle <ROOT>` — the
validator walks the whole tree under `<ROOT>`, discovers every artifact
chain, and validates each member's posture. The mode is the right shape
for CI: the reusable workflow runs against the repo root and surfaces
every drifted chain on every PR.

What CI does NOT cover is repos that use the shirabe plugin's
`/work-on` skill without adopting the reusable CI workflow. For those
repos, the discipline ships with the plugin's cascade script
(`skills/work-on/scripts/run-cascade.sh`), which finalizes the chain
atomically. The cascade today invokes the lifecycle check from
agent-directed prose in `skills/work-on/SKILL.md` — the agent reads the
prose, runs `shirabe validate --lifecycle . --strict`, and parses the
output. The verification is not deterministic.

The fix is to bake the check into the cascade script directly. The
script knows the PLAN doc path (it walks the chain from there). It can
invoke the check at the pre-cascade probe and post-cascade verification
points without agent involvement. But the whole-tree mode is the wrong
scope for the script: it would scan every chain in the repo on every
cascade run, surfacing unrelated drift as noise.

What the cascade script needs is a chain-targeted mode: take a doc-in-
a-chain, walk only that chain, validate only that chain. The CLI shape
for that mode is the present decision.

## Options Considered

### Option A: new `--lifecycle-chain <DOC-PATH>` flag

A new flag on the validate subcommand, mutually exclusive with the
existing `--lifecycle <ROOT>` flag and with positional file arguments.
The two flags live side-by-side; each has one clear scope.

```
shirabe validate --lifecycle .                         # whole-tree (CI)
shirabe validate --lifecycle-chain docs/plans/PLAN-foo.md --strict  # one chain (cascade)
```

Pros:
- Mirrors the existing `--lifecycle` shape (same verb, same noun).
- Mirrors the `--strict` flag pattern from the prior increment (new
  flag, default off, surfaces in `--help`).
- Keeps the whole-tree `--lifecycle .` contract unchanged.
- Error messages are clear ("expected a doc-path; got a directory" vs
  "expected a directory; got a doc-path").

Cons:
- Two flags on the validate subcommand where one might suffice.

### Option B: overload `--lifecycle` to accept either a directory or a doc-path

Reshape the existing flag to accept either a directory (current
behavior) or a doc-path (new behavior). Detect at runtime which mode
applies.

```
shirabe validate --lifecycle .                         # whole-tree
shirabe validate --lifecycle docs/plans/PLAN-foo.md    # one chain
```

Pros:
- One flag, fewer surfaces.

Cons:
- The flag's name ("lifecycle") describes neither scope unambiguously.
- A user pointing the flag at a doc-path expects whole-tree behavior
  gets chain-only silently — a behavior shift on a typo.
- Error messages become ambiguous ("expected a directory or a
  doc-path; got ...") and less actionable than the explicit-flag
  alternative.
- Breaks the "one flag, one purpose" clap idiom that `--visibility`,
  `--strict`, and the existing `--lifecycle` follow.

### Option C: new `validate-chain <DOC-PATH>` subcommand

A separate verb at the top-level. The new subcommand carries only the
chain-targeted mode; `validate --lifecycle <ROOT>` keeps the whole-tree
mode.

```
shirabe validate --lifecycle .                # whole-tree
shirabe validate-chain docs/plans/PLAN-foo.md --strict  # one chain
```

Pros:
- Very clear separation between the two modes.

Cons:
- The verb name misleads: `validate-chain` still does lifecycle
  validation; it does not validate the chain in any other sense.
- Doubles the top-level help surface.
- More code wiring (new clap struct, new dispatch arm) than a new
  flag for an equivalent surface.
- Inconsistent with the existing pattern where mode toggles on
  validate are flags (`--lifecycle`, `--visibility`, `--strict`,
  `--custom-statuses`).

## Decision

Option A: a new `--lifecycle-chain <DOC-PATH>` flag on the validate
subcommand, mutually exclusive with `--lifecycle <ROOT>` and with
positional file arguments. Default off. Works with `--strict`. The
chain-targeted mode reuses the existing `discover_chains` walker by
filtering to the chain containing the input doc-path.

## Consequences

**Positive:**
- The CLI's whole-tree mode contract is unchanged. The reusable CI
  workflow and any external caller of `--lifecycle .` is unaffected.
- The cascade script's invocation is explicit: `shirabe validate
  --lifecycle-chain <plan-doc> --strict`. No mode-detection logic on
  the script side.
- Both modes appear in `--help` with their own descriptions.
- The pattern is consistent with the existing codebase idiom for
  validate-subcommand modes (per
  `DECISION-lifecycle-strict-mode-interface-2026-06-06`).

**Negative:**
- The validate subcommand grows from one mode flag (`--lifecycle`)
  to two (`--lifecycle` and `--lifecycle-chain`). Mitigated by the
  two flags being mutually exclusive at validation time and by both
  following the same `--strict` toggle behavior.
