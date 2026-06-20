# Lead

What PLAN docs exist today across the workspace, what shapes they take, and
how they are executed — so the `/execute` PRD can require that `/execute` (and
the narrowed `/work-on`) keep every existing PLAN doc flowing end-to-end
without rewriting it.

Scope of search: shirabe, tsuku, koto repos plus the `shirabe-execute-skill`
worktree (which holds the live `skills/plan`, `skills/work-on`, the
`plan-format.md` reference, and the Rust validator).

Key terminology correction: the lead referred to the frontmatter field as
`plan_execution_mode`. The actual frontmatter key is **`execution_mode`**
(see `skills/plan/references/plan-format.md` line 27 and every real PLAN doc).
There is no `plan_execution_mode` key anywhere in the codebase. Any PRD prose
must name the field `execution_mode` to avoid a phantom-field migration.

# PLAN inventory

Real (non-fixture) PLAN docs in the workspace, with declared `execution_mode`:

| Path | status | execution_mode | issue_count | upstream |
|------|--------|----------------|-------------|----------|
| `public/shirabe/docs/plans/PLAN-work-on-friction-fixes.md` | Active | **multi-pr** | 6 | (none) |
| `public/tsuku/docs/plans/PLAN-curated-recipes.md` | Active | **multi-pr** | 42 | `docs/designs/DESIGN-curated-recipes.md` |
| `public/tsuku/docs/plans/PLAN-install-ux-v2.md` | Draft | **single-pr** | 5 | `docs/designs/DESIGN-install-ux-v2.md` |

(The worktree carries an identical copy of `PLAN-work-on-friction-fixes.md`.)

**koto has NO PLAN docs.** `public/koto/docs/` contains briefs, designs, prds,
guides, reference, testing — no `docs/plans/` directory and no `PLAN-*.md`
anywhere. So the "keep koto PLANs flowing" part of the lead has no live
subjects today; koto's relevance is as the orchestration *engine* (koto
templates / `koto init|next|context`), not as a PLAN producer.

**No `coordinated` PLAN exists yet.** Despite `coordinated` being a fully
supported `execution_mode` value in the validator and the plan-to-tasks
contract, every real PLAN on disk is `single-pr` or `multi-pr`. `coordinated`
is forward-looking surface added by the coordination work; `/execute` must
support it but there is no legacy `coordinated` doc to preserve.

Fixture PLANs (not durable artifacts, but they exercise the execution path and
must keep validating): `skills/work-on/evals/fixtures/plans/PLAN-cascade-test-full.md`,
`PLAN-cascade-test-short.md`, `PLAN-diamond-test.md`, plus the Rust golden
corpus under `crates/shirabe/tests/fixtures/golden/...` and
`absorption-golden/...`. These are the regression net for any format change.

# Format + execution-mode fields

Source of truth: `skills/plan/references/plan-format.md`.

**Frontmatter fields that drive execution:**

- `schema: plan/v1` — pins the artifact-type contract. Mode detection in
  `/work-on` keys on this: "any `.md` file whose frontmatter contains
  `schema: plan/v1`" routes to plan orchestrator mode
  (`skills/work-on/SKILL.md` line 145).
- `status` — `Draft | Active | Done`. `single-pr` skips `Active` (Draft→Done);
  `multi-pr` uses `Active` while issues are open (Draft→Active→Done). (Note:
  the friction-fixes and curated PLANs are `Active`; install-ux-v2 is `Draft`.)
- `execution_mode` — **the field that fans out execution shape**:
  - `single-pr` — table holds local anchors to in-doc issue outlines; no
    GitHub issues materialized; one branch, one PR; the agent walks outlines
    in dependency order.
  - `multi-pr` — table holds `#N` GitHub-issue links materialized at PLAN
    finalization; a milestone groups them. (Both modes share an identical
    table shape and validator contract — plan-format.md line 140.)
  - `coordinated` — multi-repo generalization of `multi-pr`. Confirmed a
    first-class value in the validator (`crates/shirabe-validate/src/formats.rs`
    lines 34, 46, 51-55, 76-79: `plan_execution_mode_sections()` registers
    `single-pr`, `multi-pr`, `coordinated` keys; `coordinated` shares
    `multi-pr`'s required-section list) and in
    `skills/plan/references/plan-to-tasks-contract.md` (line 62 "coordinated
    vars", emits one task per merge-order *node* not per issue).
- `milestone` — human-readable; GitHub milestone title in multi-pr, prose-only
  in single-pr.
- `issue_count` — must equal the Implementation Issues table row count.
- `upstream` (optional) — DESIGN path (repo-relative or `owner/repo:path`),
  drives the completion cascade chain. May be absent (friction-fixes has none).

**Required sections** (FC04, now branched per execution_mode in the validator):
Status, Scope Summary, Decomposition Strategy, Implementation Issues,
Dependency Graph, Implementation Sequence. The Implementation Issues table is
the canonical three-column shape (`Issue | Dependencies | Complexity`), two
rows per issue (link row + italic-summary row). A legacy four-column shape
(`Issue | Title | Dependencies | Complexity`) still exists in the wild and is
handled by FC05 with a migration hint — relevant to backward-compat.

# Backward-compat requirements for /execute

What MUST keep working when plan-level execution moves to `/execute`:

1. **Same-file, no-rewrite contract.** All three real PLAN docs (and the
   fixtures) must run through `/execute` exactly as authored. The
   `execution_mode` field, the `schema: plan/v1` trigger, the three-column
   table shape, and the `upstream`-driven cascade are the load-bearing inputs.
   No frontmatter migration should be required to move a doc from `/work-on`
   to `/execute`.

2. **The orchestration mechanics that `/execute` inherits from today's
   `/work-on` plan mode** (`skills/work-on/SKILL.md`, "Plan Mode"):
   - **Mode detection**: arg is a path matching `docs/plans/PLAN-*.md` OR any
     `.md` with `schema: plan/v1` frontmatter → plan orchestrator mode (checked
     before issue-backed mode). `/execute` must reproduce this entry contract.
   - **Plan-backed child mode** (`-- plan-backed` prefix): the orchestrator
     spawns per-issue children carrying `ISSUE_SOURCE` (`github` |
     `plan_outline`), `ISSUE_NUMBER`, `PLAN_DOC`, `ISSUE_TYPE`, and a shared
     `SHARED_BRANCH`. Children commit to `SHARED_BRANCH` and submit
     `pr_status: shared` (skip PR creation); the orchestrator owns the PR.
   - **Single shared branch / single PR**: branch `impl/<slug>` where `<slug>`
     derives from the PLAN filename (`PLAN-foo-bar.md` → `plan-foo-bar`). One
     draft PR for the whole plan; `pr_finalization` assembles the combined PR
     body table from `batch_final_view`.
   - **koto machine**: `koto init <plan-slug> --template
     .../skills/work-on/koto-templates/work-on-plan.md --var PLAN_DOC=<path>`,
     then `plan-to-tasks.sh` (in `spawn_and_await`) converts the PLAN doc to a
     JSON task array, injecting `SHARED_BRANCH` into each task's vars.
   - **Completion cascade** (`plan_completion`):
     `skills/work-on/scripts/run-cascade.sh --push {{PLAN_DOC}}` runs the
     `shirabe validate --lifecycle-chain --mode=ready` pre-probe and
     post-verify, performs the atomic finalization (PLAN deletion +
     DESIGN→Current, PRD→Done, BRIEF→Done, ROADMAP feature update), pushes, and
     marks the PR ready. This walks the `upstream` chain — so a PLAN's
     `upstream` field must keep resolving.

3. **Branch-reuse / override semantics** (Branch Context Evaluation): if
   already on `impl/<slug>` with an open PR, the orchestrator submits
   `status: override` instead of re-creating. `/execute` must keep this so a
   PLAN that produced a branch in its authoring session resumes cleanly.

4. **Coordination is additive (R3)** — must not regress single/multi-pr.
   `/work-on` today states that when coordination intent is absent (every
   `single-pr` and `multi-pr` PLAN) it behaves "exactly as documented
   everywhere else": one shared branch, one PR, no cross-repo gate. `/execute`
   must preserve this default-quiet behavior so the two existing multi-pr and
   one single-pr docs see no coordination machinery.

**Migration risk / divergence to flag for the PRD:**

- **Doc-vs-validator drift on `coordinated`.** `plan-format.md` (the
  human-facing reference) still describes `execution_mode` as "one of
  `single-pr` or `multi-pr`" (lines 40-43) and never mentions `coordinated`,
  while the validator and the plan-to-tasks contract already treat
  `coordinated` as first-class. The PRD should require `/execute` to accept all
  three values and should flag that `plan-format.md` lags the implementation
  (a docs-fix, not a code migration).
- **Legacy four-column table shape** still exists and is only migration-hinted
  (FC05), not rejected. `/execute` must parse legacy-shape PLANs (or the PRD
  must require migrating them) so an older PLAN doesn't fail at execution time.
- **Phantom field name.** Ensure the PRD says `execution_mode`, never
  `plan_execution_mode` — the latter does not exist and would imply a migration
  that isn't real.

# Multi-pr single-repo PLANs (stay one-issue-at-a-time via /work-on)

Per the lead's recall: single-repo `multi-pr` PLANs are NOT orchestrated as a
coordinated multi-PR effort by `/execute` — each issue ships its own PR,
one-at-a-time, the same way `/work-on` drives them today. Examples to flag:

- `public/shirabe/docs/plans/PLAN-work-on-friction-fixes.md` — `multi-pr`,
  single-repo (shirabe), 6 design issues under milestone 4. Each `#N` issue is
  its own PR; #84 waits on #79. This is the canonical "multi-pr stays
  per-issue, not coordinated" case.
- `public/tsuku/docs/plans/PLAN-curated-recipes.md` — `multi-pr`, single-repo
  (tsuku), 42 issues under milestone 113. Per-issue PRs.

`single-pr` example (`PLAN-install-ux-v2.md`) is the one-branch/one-PR path
that the plan orchestrator's shared-branch machinery drives directly.

`coordinated` (multi-repo) is the only mode where `/execute` orchestrates
cross-repo PR sequencing + a coordination PR — and no such doc exists yet, so
that path has no backward-compat subject, only forward support.

# Summary

Three real PLAN docs exist (two `multi-pr`: shirabe's `PLAN-work-on-friction-fixes`
and tsuku's `PLAN-curated-recipes`; one `single-pr`: tsuku's `PLAN-install-ux-v2`),
koto has none, and no `coordinated` PLAN exists yet — so `/execute`'s
backward-compat burden is the `single-pr`/`multi-pr` execution paths exactly as
`/work-on` plan mode drives them today (schema:`plan/v1` detection →
`koto init` with `work-on-plan.md` template → `plan-to-tasks.sh` →
`impl/<slug>` shared branch + single draft PR + plan-backed children →
`run-cascade.sh` walking the `upstream` chain). The contract is same-file,
no-rewrite: the `execution_mode`, `schema`, three-column table, and `upstream`
fields must keep resolving unchanged, coordination must stay additive (absent
on every existing doc), and single-repo `multi-pr` PLANs must keep shipping
one PR per issue rather than being pulled into coordinated orchestration. Two
migration risks to flag: the human-facing `plan-format.md` reference lags the
validator by omitting the already-supported `coordinated` value, and the legacy
four-column table shape is only hint-migrated (FC05) not rejected — and the PRD
must use the real field name `execution_mode`, never the phantom
`plan_execution_mode`.
