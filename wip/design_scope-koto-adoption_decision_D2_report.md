# Decision D2: Hop completion construct

**Resolved inline.** The delegated evaluation for this decision died on a
session limit mid-run. Per `references/fixes/sub-agent-dispatch.md`, the
decision-bypass-with-inline-resolution shape applies: the decision is resolved
within the design's own Phase 2 and recorded here, and the design's frontmatter
carries `decision_provenance: inline-resolved`. The empirical verification below
was run directly rather than lost.

## Options Considered

**A `command` gate reading the artifact tree.** Chosen. koto runs the command,
records a `GateEvaluated` event the run does not author, and that event is what
reaches the surviving per-hop record. Costs a shell invocation per hop.

**An agent-submitted evidence field plus a validator.** Rejected. It satisfies
PRD R8's first clause — completion could still be computed from the filesystem —
but loses the second: evidence values do not reach the per-hop record, only gate
outcomes do. A reviewer would see the run's claim rather than the engine's
finding, which is the property this work exists to remove.

**A `context-exists` gate.** Rejected. The context store is written by the run,
so gating on it re-admits exactly the self-report R8 forbids.

## The Gate Predicate

One script, `hop-complete.sh --hop <name> --topic <slug>`, exit 0 when complete.
It implements PRD R7's two limbs and reads nothing else:

- **Limb (a)** — the hop's own artifact exists at its canonical path. `design`
  checks both `docs/designs/` and `docs/designs/current/`.
- **Limb (b)** — a downstream survivor names this hop's artifact in its
  `absorbed:` frontmatter. The scan is frontmatter-only: it stops at the closing
  `---`, so a prose mention in the body cannot satisfy the gate.

It reads no path under `wip/`, so PRD R26's static check has nothing to catch and
AC12 holds by construction.

**Cascading folds need no recursion.** `/scope`'s own contract has a survivor
carry every absorbed ancestor's contribution and declare each one, so after
brief folds into prd and prd folds into design, the design declares both. A flat
scan over downstream survivors therefore finds a twice-folded ancestor.

## Per-Hop vs Chain-Wide

**One script, two invocations.** The per-hop `<hop>_complete` gate calls it for
that hop. The chain-wide `chain_complete` gate on `exit_full_run` calls it once
per hop in `planned_chain:` and fails naming every hop that returned 1. Sharing
the predicate is what makes AC8's refusal name the same hops a per-hop gate would
have flagged, and keeps one definition of "complete" rather than two that drift.

## D1's Deferred Questions

**(b) Block at the hop, or advance and refuse at the exit?** D1's graph advances,
recording the failure. **Upheld.** A per-hop block costs four retry states and a
route back to the right hop, and buys an earlier refusal for a run that is going
to be refused anyway. The argument the other way is real — an author learns
sooner — but a hop's gate can fail for a legitimate reason mid-chain, namely that
the hop is genuinely being folded rather than skipped, and blocking there would
refuse the fold path the PRD's Problem Statement exists to protect. The exit is
the only place where "every hop is accounted for" is answerable.

**(c) Does `outcome` need a fourth value for an in-chain Phase-N reject?** No.
`/scope` observes a child's reject through a discard commit in
`git log <pre_invocation_sha>..HEAD` and routes it to a re-evaluation exit with a
Decision Record, which is a different exit path rather than a different hop
outcome. Routing it through `bail` as D1's graph does reaches
`exit_abandonment`, which is wrong for a reject — the correct terminal is
`done_re_evaluation`. **This is a correction to D1's graph:** `bail` needs a
second forward route, or the hop states need a `rejected` outcome routing
directly to `exit_re_evaluation`. The second is cleaner and is what this decision
adopts, because a reject is not a bail and carrying it through the bail state
would make `triggering_child` meaningful for a run that did not abandon.

## FC18 Verification

Read at `crates/shirabe-validate/src/checks.rs:400-421`. Six clauses, gated
entirely on `absorbed:` being present. Clause 4 requires the implied contribution
sections to appear contiguously and immediately after `## Status` in chain order;
clause 5 requires a well-formed Status absorption line per entry.

So the pairing PRD R7's limb (b) relies on is real, with one bound worth stating:
FC18 is silent when `absorbed:` is absent, so it does not catch a fold that was
never declared. That is not a gap for R7, because limb (b) requires the
declaration to exist before it looks at anything. What FC18 buys is that a
*forged* declaration is expensive — writing `absorbed:` without the contribution
section fails validation, and `/scope`'s Phase 2 validator pass-through halts the
chain on violations. Forging a fold costs most of the work of performing one,
which is the property the PRD's R8 rationale claims.

## Empirical Results

Five fixture cases, verbatim:

```
1 artifact present                    hop=brief  exit=0  complete: artifact present at docs/briefs/BRIEF-demo.md
2 folded into PRD                     hop=brief  exit=0  complete: absorbed into docs/prds/PRD-demo.md
3 incident: PLAN only, prose claim    hop=brief  exit=1  incomplete: no artifact at docs/briefs/BRIEF-demo.md, and no downstream absorbed: entry names it
3 incident: PLAN only, prose claim    hop=prd    exit=1  incomplete: no artifact at docs/prds/PRD-demo.md, and no downstream absorbed: entry names it
3 incident: PLAN only, prose claim    hop=design exit=1  incomplete: no artifact at docs/designs/DESIGN-demo.md, and no downstream absorbed: entry names it
3 incident: PLAN only, prose claim    hop=plan   exit=0  complete: artifact present at docs/plans/PLAN-demo.md
4 cascade: brief+prd into DESIGN      hop=brief  exit=0  complete: absorbed into docs/designs/DESIGN-demo.md
4 cascade: brief+prd into DESIGN      hop=prd    exit=0  complete: absorbed into docs/designs/DESIGN-demo.md
5 body mention only (must fail)       hop=brief  exit=1  incomplete: no artifact at docs/briefs/BRIEF-demo.md, and no downstream absorbed: entry names it
```

Case 3 is the reported incident reduced to a machine check: a PLAN on disk, the
three upstream hops asserted away in a Status sentence, no `absorbed:` anywhere.
Three hops return 1, so `chain_complete` fails and PRD AC8's refusal names them.
Case 5 is the same claim moved into the body, and it also fails — which matters,
because prose is exactly the form the incident's claim took.

Also verified against the live repository: `--hop brief --topic
scope-koto-adoption` returns 0 on this branch, where the BRIEF is on disk.

## Consequences

**Positive.** One definition of hop completion, shared by the per-hop and
chain-wide gates. The incident shape is refused by a shell predicate with no
model in the loop, which is what makes PRD AC30 buildable. Nothing reads the
state file, so AC12 is structural rather than a reviewer's diligence.

**Negative.** The predicate hard-codes the four canonical path shapes, so a
fifth artifact type or a moved directory edits this script. Mitigated by it being
one file with one job, named in the PLAN's test coverage.

**Negative.** Limb (b) trusts a declaration the run writes. Mitigated, not
removed, by FC18 making the declaration expensive to forge and by the validator
pass-through halting on violations. The honest claim stays the PRD's: a skip
leaves a mark, not a skip is impossible.

## Summary

Hop completion is decided by a single `command` gate running one shared
predicate that implements R7's two limbs — artifact at the canonical path, or a
downstream survivor declaring the hop in `absorbed:` frontmatter, scanned
frontmatter-only so a prose claim cannot satisfy it — and it reads nothing under
`wip/`, so AC12 holds by construction. Five fixture cases were run directly: the
reported incident returns exit 1 for brief, prd and design and exit 0 only for
plan, which is R7 refusing the full-run claim and naming three hops, and the
same claim written as body prose also fails. FC18 was read in source and does
enforce `absorbed:` and the contribution section as a pair, so limb (b) rests on
something real, bounded by FC18's silence when no declaration exists. One
correction to D1's graph falls out: an in-chain Phase-N reject is not a bail and
needs a `rejected` outcome routing to the re-evaluation exit rather than through
`bail` to abandonment.
