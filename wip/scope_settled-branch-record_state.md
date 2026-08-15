---
schema: scope-state/v1
---

```yaml
topic: settled-branch-record
chain_started: 2026-08-15T18:40:10Z
last_updated: 2026-08-15T18:45:00Z
phase_pointer: phase-2
exit: UNSET
exit_artifacts: []
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
chain_ran:
  - brief
  - prd
phase_1: empty-cold-start
shape_predicates:
  P1: fires -- the adopt-path fallback behaviour is an implementation choice left
      explicitly open (path-aware fallback / verified read-back / no fallback)
  P2: does-not-fire -- no new binary, service, library, or runtime substrate; the
      work lands in existing skill templates and existing shirabe crates
  P3: does-not-fire -- no Complex classification warranted for one directive and
      its failure contract
worktree_rebases:
  - phase: brief
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-15T18:46:00Z
    notes: branch is at origin/main (7eb98ec); nothing to rebase
chain_ran_detail:
  - child: brief
    r20_artifact: docs/briefs/BRIEF-settled-branch-record.md
    validator_exit: 0
    jury: serial-self-jury (content-quality PASS, structural-format PASS)
    consolidation: skipped -- no artifact above BRIEF in this chain
  - child: prd
    r20_artifact: docs/prds/PRD-settled-branch-record.md
    validator_exit: 0
    jury: serial-self-jury (completeness PASS, clarity PASS, testability PASS)
    consolidation: keep
child_snapshots:
  brief:
    status: Accepted
    content_hash: e277487ed50bf57e6bdee4f2a067e4df2b06a0eb
    captured_at: 2026-08-15T18:42:43Z
  prd:
    status: Accepted
    content_hash: a88c85f26f1c84014816a7f7ff309161c278887c
    captured_at: 2026-08-15T18:45:14Z
consolidation_judgments:
  - hop: brief->prd
    absorbable: true
    verdict: keep
    finding: >-
      The BRIEF's User Journeys carry detail the PRD's User Stories do not. Each
      journey walks the mechanism it exercises -- journey 1 names the sequence
      (detect non-main branch with open PR, adopt, record, read back, inject as
      SHARED_BRANCH) that user story 1 compresses to the outcome alone. The PRD's
      own citation-vs-restatement rule tells it to cite rather than restate that
      framing, so the walked journeys live only in the BRIEF. Stage 2 answers
      yes; the absorb does not run.
visibility: Public
execution_mode: auto
max_rounds: 5
coordination_intent: absent
coordination_intent_reason: >-
  CLAUDE.md carries the two durable workspace headers (PR Grouping Policy,
  Reviewability Ceiling) but a coordinated effort is defined as one spanning
  more than one repository (coordination-strategy.md). This effort is confined
  to tsukumogami/shirabe, so the single-repo path applies and no coordination
  PR is created.
```
