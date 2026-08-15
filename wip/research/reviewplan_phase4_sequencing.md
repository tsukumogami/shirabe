# Category D: PASS

## Dependency graph re-derived from the outlines' current `**Dependencies**:` lines

```
1 -> 2 -> 3 -> 4 -> 8
5 -> 6
5 -> 7
```

Two roots now (1 and 5), acyclic, all 8 issues accounted for. This matches
the design's Batch 3 claim that the tracking-level batch "depends on Batch 1
for nothing" — the earlier false 1→5 edge is gone and the plan's prose
("Issue 5 has no dependencies at all... can start immediately, alongside
Issue 1") is now accurate, including the corrected Parallel Opportunity
paragraph.

## Item 1: lifecycle.rs overlap between Issue 3, Issue 4, and Issue 6

Real file overlap, not a real ordering constraint. Issue 3 adds the `L09`
check itself (new code) to `lifecycle.rs`; Issue 4 extends that same check's
departure branch (also functional, and already correctly ordered after 3 via
the declared 3→4 edge); Issue 6 only touches `lifecycle.rs`'s module doc
comment, and its own goal text is explicit that this edit is "comment-only;
no behaviour changes there." Issue 6's ACs never reference `L09`,
`split_rationale`, or anything Issue 3/4 produce — they're entirely about the
tracking-level-keyed approval gate. The two edits land in disjoint regions of
the same file (a new/extended check function vs. a module-level doc comment)
with no content dependency either direction, so this is a same-file
coincidence to sequence consciously while implementing on one shared branch
(to avoid a diff conflict), not a blocker the graph is missing. No edge
needed between 3/4 and 6.

## Item 2: Issue 3's new fixture AC (constructs `## Delivery Preference: atomic`)

Confirmed: not a real edge to Issue 4. The fixture calls
`resolve_claude_md_header`, which the design states is pre-existing, shipped
infrastructure ("Six `## <Noun Phrase>: <value>` headers already carry
repository-scoped scalar preferences, with a documented registry and a
tested Rust parser" — D1; "`resolve_claude_md_header`... the same walker
`resolve_doc_visibility`... already share[s]"). It is a generic literal-text
matcher, indifferent to whether a given header is registered in
`claude-md-conventions.md`. Issue 4's job is to *document* the header in the
registry and *wire step 3.6* to consult it for mode recommendations — neither
of which `L09`'s own check depends on, since `L09` calls the resolver
directly. Issue 3's fixture can author a throwaway CLAUDE.md with the literal
string and exercise both branches before Issue 4 exists, exactly as the AC's
own justification states. No missing 4→3 (or 3-before-4-blocked-by-4) edge.

## Everything else re-confirmed on the current text

- All declared edges (1→2, 2→3, 3→4, 4→8, 5→6, 5→7) check out against each
  downstream issue's ACs, including the two new ones inspected above.
- Issue 7 correctly depends only on Issue 5 (not Issue 6) at the issue level
  even though the design describes Batch 4 as depending on "Batch 3" (5+6)
  as a whole — extraction only needs the `tracking_level` field Issue 5
  writes, not Issue 6's approval-gate prose re-key, so the plan's finer
  granularity is a legitimate refinement of the design's coarser batch
  dependency, not a contradiction.
- Natural stopping point after Issue 3, and riskiest-issue-last (Issue 7)
  placement, are unchanged from the prior pass and still hold: nothing in
  1-3 depends on 4-8, no issue depends on 7, and the critical path 1→2→3→4→8
  completes without it — a stall in 7 cannot strand the rest, and since the
  plan lands as one PR no broken intermediate state is ever published.
