# Category D: FAIL

## Dependency graph derived from the outlines' own `**Dependencies**:` lines

```
1 -> 2 -> 3 -> 4 -> 8
1 -> 5 -> 6
1 -> 5 -> 7
```

Acyclic, all 8 issues accounted for. Critical path (1-2-3-4-8) is five deep;
5-6 and 5-7 are each three deep, consistent with the plan's own claim about
the critical path length.

## Finding 1 (dependency ordering error, affected_issue_ids: [1, 5]) — false edge, over-serializes

Issue 5's stated dependency, "Issue 1 only, for vocabulary consistency," is
not real. Issue 5's files (`claude-md-conventions.md`,
`phase-7-creation.md`) and ACs (Tracking Level header, `tracking_level`
frontmatter, Phase 7 gating on the six mode/level combinations) never touch
`split-triggers.md`'s branch vocabulary (Hard Constraint / Incremental
Value / Stated Preference) — that vocabulary is what Issue 2's
`split_rationale` field names, not what Issue 5 produces or consumes.
Nothing in Issue 5's AC references Issue 1's output.

This contradicts the design doc directly. DESIGN-multi-pr-plan-decoupling.md's
Batch 3 (Delivery header + registry + Phase 7 gating + gate re-key, i.e.
Issues 5-6) states explicitly: "it depends on Batch 1 for nothing and could
equally precede Batch 2" (docs/designs/DESIGN-multi-pr-plan-decoupling.md:489).
The plan's own outline disagrees with the design it implements on this exact
edge.

Effect: the plan's "Parallel opportunity" narrative undersells the real
parallelism — Issue 5 could start immediately alongside Issue 1, not merely
"alongside 2 → 3 → 4" as currently written, and 6/7 could complete before 4
is even reached.

Correction: drop the 1→5 edge; Issue 5's Dependencies line should read
"None." Loop target 5 (Dependencies) per phase-4-sequencing.md, since this
is a graph-edge correction, not a decomposition/QA reclassification.

## Everything else checked out

- Real edges confirmed: 1→2 (branch vocabulary must exist to be named),
  2→3 (field must be specified before a check enforces it, matches L09's
  own AC), 3→4 (Issue 4's AC "L09 fires on a single-pr plan in an atomic
  repository" requires L09 to already exist), 4→8 (Issue 8 amends a
  decision to depend on the Delivery Preference header Issue 4 creates),
  5→6 and 5→7 (both genuinely need `tracking_level`, which only Issue 5
  writes).
- Issue 5's independence from Issues 2-4 (the delivery-preference spine)
  holds: `tracking_level`'s default reads whatever `execution_mode`
  resolves to, not how Issue 4's header logic produced it, and Issue 5's
  AC never touches `split_rationale`/L09.
- Natural stopping point after Issue 3 is real: 1-3 form the head of the
  chain (nothing in 1-3 depends on 4-8), and Issue 3's own text notes the
  atomic-departure branch is deliberately inert until Issue 4 — consistent
  with the design, not a bug. The multi-pr branch of L09 is live and
  testable with just 1-3.
- Riskiest-issue placement (Issue 7 last) is sound, not deprioritized
  verification: no issue depends on 7, so its failure cannot strand 4 or 8
  (the critical path terminates at 8 without touching 7), and the design
  explicitly rules out walking-skeleton because risk here is concentrated
  in one issue rather than spread across a pipeline. Since the plan lands
  as one PR, a stalled Issue 7 can be dropped or fixed without publishing a
  broken intermediate state.
- No broken-intermediate-state risk beyond the ordinary single-PR working
  window: the one theoretical gap (tracking_level=none selectable after
  Issue 5 but plan-to-tasks.sh not yet updated until Issue 7) is never
  exercised by Issue 5's own AC (which checks Phase 7 artifact creation,
  not task extraction), and per the task framing this window is never
  published.
