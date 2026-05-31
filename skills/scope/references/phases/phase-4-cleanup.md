# Phase 4 — wip Cleanup

Phase 4 removes the topic's wip/ scratch artifacts after Phase
3's R9 hard-finalization check has passed. Scope of removal
depends on the `exit:` value: `full-run` and `re-evaluation`
sweep the parent's `wip/scope_<topic>_*` plus the child-prefixed
`wip/{brief,prd,design,plan}_<topic>_*` and
`wip/research/{prd,design}_<topic>_*`; `abandonment-forced`
removes only the parent's prefix and preserves child wip for
session resumability. The terminal artifact (PLAN, Decision
Record, or force-materialized child doc) remains on disk on
every exit path.

## Trigger

Phase 4 runs ONLY after Phase 3's R9 hard-finalization check
returns success. A run that failed R9 stops at Phase 3 with the
violation surfaced; Phase 4 does NOT run against an unfinalized
state. The dependency is one-way: Phase 3's success gate is
the Phase 4 trigger.

## wip Removal Scope on Each Exit Path

Phase 4's removal scope depends on the `exit:` value Phase 3
finalized. The exit-path matrix:

- **`exit: full-run`** — remove `wip/scope_<topic>_*` AND
  `wip/{brief,prd,design,plan}_<topic>_*` AND
  `wip/research/{prd,design}_<topic>_*`. The chain finished its
  planned terminal artifact; no resumable state remains.
- **`exit: re-evaluation`** — remove `wip/scope_<topic>_*` AND
  `wip/{brief,prd,design,plan}_<topic>_*` AND
  `wip/research/{prd,design}_<topic>_*`. The chain settled at a
  re-evaluation boundary; the Decision Record at
  `docs/decisions/...` is the durable record and no resumable
  state remains.
- **`exit: abandonment-forced`** — remove `wip/scope_<topic>_*`
  only. The child-prefixed wip files
  (`wip/{brief,prd,design,plan}_<topic>_*` and
  `wip/research/{prd,design}_<topic>_*`) are PRESERVED so a
  future session that resumes the abandoned chain has the
  child's intermediate state to read back. The force-
  materialized Draft artifact at
  `docs/{briefs|prds|designs|plans}/<TYPE>-<topic>.md` carries
  the abandonment marker; the preserved wip files carry the
  child's in-flight scratch the next session needs.

The terminal artifact always remains on disk and Phase 4 does
not touch it:

- `exit: full-run` → `docs/plans/PLAN-<topic>.md`.
- `exit: re-evaluation` →
  `docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md`.
- `exit: abandonment-forced` →
  `docs/{briefs|prds|designs|plans}/<TYPE>-<topic>.md` (Draft,
  marker in Status section).

### Why Phase 4 Owns Child-Prefixed Removals

The workspace-level wip-hygiene rule (workspace `CLAUDE.md`,
"Temporary Artifacts (wip/)" section) requires that files under
`wip/` MUST be removed from the branch before a PR can merge.
The rule applies workspace-wide regardless of repo visibility,
and it covers every `wip/` prefix the chain touched — not just
the parent's `wip/scope_<topic>_*` prefix. On `full-run` and
`re-evaluation` exits, where no resumable state survives,
leaving child-prefixed wip files in place would violate the
hygiene rule and block PR merge.

The child skills (`/brief`, `/prd`, `/design`, `/plan`) remove
their own `wip/` scratch on their own terminal exits when run
standalone. When run through `/scope`, the parent observes
each child's exit and Phase 4 sweeps the topic's full wip
surface once at chain-end. The split is by invocation context:
standalone child cleans its own; chain-driven child has its
wip swept by the parent's Phase 4. Either way, every
topic-prefixed wip file disappears before PR merge per the
hygiene rule.

The abandonment-forced carve-out is intentional and narrow:
the next session needs the child's last-known intermediate to
resume. The hygiene rule still applies — the wip files MUST be
removed before any PR lands — but cleanup is deferred to the
resumed session's eventual full-run or re-evaluation exit, not
the abandoned session's Phase 4. The abandonment-forced state
is, by construction, not a mergeable state.

## Read-Back of Phase 3's Closed Write-Target Set

The Phase 4 removal set reads back the closed write-target
enumeration documented in `phase-3-exit-finalization.md` and in
SKILL.md's Closed Write-Target Set section (L670-674), which
names both removal scopes:

- `wip/scope_<topic>_*` — removed on every exit path.
- `wip/{brief,prd,design,plan}_<topic>_*` and
  `wip/research/{prd,design}_<topic>_*` — removed on `full-run`
  and `re-evaluation` exits; preserved on `abandonment-forced`
  exit for resumability.

The read-back is documentation discipline: Phase 4's removals
land inside Phase 3's enumerated set per the exit-path matrix
above; an implementation that removes anything outside this
set, or that omits a required removal on `full-run` or
`re-evaluation`, fails the closed-set invariant. Reviewers
checking that the invariant holds find the enumeration in
Phase 3, the matched scope in SKILL.md (L333-337 substrate
description and L670-674 closed-set list), and the
exit-path-aware read-back here.

## Success Summary

Phase 4 emits a single-line success summary naming the terminal
artifact path and the `exit:` value:

```
/scope finished: exit=<full-run|re-evaluation|abandonment-forced>; artifact=<terminal-artifact-path>
```

Example summaries:

- `/scope finished: exit=full-run; artifact=docs/plans/PLAN-my-topic.md`
- `/scope finished: exit=re-evaluation; artifact=docs/decisions/DECISION-prd-my-topic-re-evaluation-2026-05-31.md`
- `/scope finished: exit=abandonment-forced; artifact=docs/prds/PRD-my-topic.md`

The summary closes the chain. After Phase 4 returns, `/scope`
has no remaining state on disk under `wip/scope_<topic>_*`; a
future `/scope` invocation against the same topic starts fresh
unless the terminal artifact's lifecycle has advanced (e.g.,
the PLAN moved Draft → Active under `/work-on`, which routes
through Slot 5's refuse-and-redirect on the next `/scope` run).

## References

- `skills/scope/references/phases/phase-3-exit-finalization.md`
  — the R9 hard-finalization check whose success is Phase 4's
  trigger; the closed write-target set Phase 4 reads back.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
  — `exit:` enum the success summary names.
