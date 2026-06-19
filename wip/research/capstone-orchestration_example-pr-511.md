# Analysis: capstone PR #511 (fresh capstone, abstracted)

All proprietary product/customer/repo names abstracted. The pattern below is the
structural mechanics only. Generic placeholders: the effort is a roadmap feature
"F-x"; repos are "repo A" (public framework core), "repo B" (public SDK), "repo C"
(private enterprise), "repo D" (private showcase/consumer app), "repo E" (public docs
catalog), and "the docs repo" (where this capstone PR lives).

## Reconstructed Structure

**PR metadata**
- State: OPEN, **isDraft: true**.
- Base branch: `main`. Head branch: `session/<hash>` (an opaque session-id slug, NOT
  `feature/<slug>`).
- Title: `docs(<feature-id>): <effort> capstone — PRD/DESIGN/PLAN + <key-decision>`.
  Uses the `docs(<scope>):` conventional-commit prefix and the word "capstone" inline,
  but encodes the feature-id and names the load-bearing decision rather than a bare
  `(capstone)` tag.
- Size: ~2076 additions / ~295 deletions. 100% markdown/docs. 18 commits.
- No labels.

**PR body sections (in order)**
1. `## Summary` — opens by declaring the PR the planning **capstone** for the feature,
   states it's the contract root of the broader roadmap, says "**This PR is docs-only**;
   the *code* lands as separate per-repo PRs (see Implementation)", and ends with "This
   branch is the **capstone that merges last**."
2. `## What's in here` — bulleted inventory of every artifact touched: the roadmap edit
   (a feature split + dependency re-pointing + a roadmap-wide Definition of Done), the
   three new tactical artifacts (PRD/DESIGN/PLAN) created via the `/scope` chain, the
   load-bearing design decision narrated in prose, and a list of "doc reconciliations"
   (cross-references updated in other existing docs + a "superseded-in-part" marker on a
   prior design).
3. `## Relationship to #<prior PR>` — explains an add/add overlap with an already-merged
   PR and states this PR's artifact is the superset that absorbed the other's content.
4. `## Implementation (separate PRs — not in this one)` — prose merge-order narrative:
   "PR-1 (repo A + repo B) → publish gate → PR-2 (repo C) and PR-3 (repo D) → this
   capstone merges last; PR-4 (repo E) doc-only, independent." This is the PR-index /
   merge-order, expressed as a sentence, not a table.
5. `## Pending — NOT in this PR yet` — flags follow-up edits (positioning/marketing copy)
   awaiting human sign-off, to land as a commit before merge.
6. `## Notes` — explains *why* it's a draft (merges last + pending sign-off) and notes the
   pre-push code-regression gate is a no-op because the branch is docs-only.

**Files changed** — 4 new/edited tactical artifacts under `docs/{prds,designs,plans}/`,
plus 1 roadmap edit and ~6 "reconciliation" edits to pre-existing reference/vision/prd/
design docs. No code files.

**Artifact frontmatter (YAML)** — consistent schema across artifacts:
- `schema: <type>/v1` (e.g. `prd/v1`, `design/v1`, `plan/v1`, `roadmap/v1`).
- `status:` with a lifecycle vocabulary: roadmap `Active`, PRD `In Progress`, DESIGN
  `Accepted`, PLAN `Draft`.
- `upstream:` pointer forming an explicit chain: PLAN.upstream → DESIGN; DESIGN.upstream →
  PRD; PRD.upstream → ROADMAP; ROADMAP.upstream → STRATEGY. The PLAN additionally carries
  redundant `prd:` and `roadmap:` back-pointers plus `feature:`, `milestone:`,
  `issue_count:`, `execution_mode: single-pr`, and a `repos:` list naming all six repos.

**Where the merge-order/PR-index actually lives** — primarily inside the **PLAN doc**, not
the PR body:
- A `## Decomposition Strategy` describing "repo-vertical decomposition with a publish gate".
- A `### Per-Repo PR Breakdown` with one `### PR-N — <title> (<repo>, public|private)` section
  per PR, each listing tasks, **Depends on:**, and **Verification gates**.
- A hard `### PUBLISH GATE` section between framework PRs and consumer PRs.
- A `## Implementation Sequence` containing BOTH an ASCII dependency block (ending
  `PR-5 (docs repo capstone) ... <-- MERGES LAST`) AND a Mermaid dependency graph.
- A `## Verification Gates — Summary by Repo` table.
- A `## Public-Repo Hygiene` section flagging which PRs are public (leak-guard rules) vs
  private, with neutral-phrasing guidance.

**Commit cadence** — the 18 commits trace the full `/scope` artifact chain as it was
authored, then reconciliation, then merge-resolution. Roughly: roadmap split → PRD
(scope→draft→accept→cleanup) → DESIGN (init→decisions→security-review→accept+wip-cleanup)
→ a decision-sharpening commit → PLAN (draft→schema-conform) → cross-doc reconciliation →
PRD graft of the prior PR's content → merge main → wip scratch cleanup → a deferred-
open-question flag. Several commits are explicit `chore(wip): remove ... scratch` /
"clean up wip artifacts" — wip-hygiene is visibly enforced mid-session.

## Match Against Our Prescribed Shape

| Element | Ours (shirabe#196) | #511 | Verdict |
|---|---|---|---|
| Capstone declaration | Bold "This PR is the **capstone** of <effort>" | "Planning **capstone** for <feature>" in Summary, bold | **Match** |
| Merge-LAST rule | Bold "**Merge it LAST**" | "the **capstone that merges last**" + "MERGES LAST" in PLAN | **Match** |
| Docs-only / impl-elsewhere note | Explicit note | "This PR is **docs-only**; the *code* lands as separate per-repo PRs" | **Match** |
| Artifact-chain checklist | Exploration→BRIEF→PRD→DESIGN→PLAN, each `docs/<type>/<TYPE>-<slug>.md`, PLAN "terminal" | Chain present (STRATEGY→ROADMAP→PRD→DESIGN→PLAN) but rendered as a prose inventory in "What's in here", NOT a checklist; paths in frontmatter `upstream:` not body | **Partial** |
| PR-index table (PR\|Repo\|Contributes\|State) | Table, capstone row "merges LAST" | Per-PR breakdown exists but lives in the **PLAN doc** as prose sections + a by-repo verification table; PR body has prose only, no PR×state grid | **Partial / relocated** |
| Fenced merge-order block | Fenced dependency order ending "← THIS capstone, merged LAST" | ASCII sequence block + Mermaid graph in PLAN, ending "<-- MERGES LAST"; PR body has the sentence form | **Partial / relocated** |
| Status section | "Status" describing what's in flight | "Pending — NOT in this PR yet" + "Notes" (why draft) cover the same ground under different headers | **Partial** |
| Branch naming | `feature/<slug>` | `session/<hash>` (opaque session id) | **Differ** |
| Title convention | `docs(<type>): <effort> (capstone)` | `docs(<feature-id>): <effort> capstone — <decision>` | **Partial** |
| Docs layout `docs/<type>/*.md` | Yes | Yes — `docs/{prds,designs,plans,roadmaps,...}/` | **Match** |
| YAML status frontmatter + `upstream:` chain | Yes | Yes, plus `schema: <type>/v1` and extra back-pointers | **Match (richer)** |
| Done = all per-repo PRs merged + cascade flips statuses + DELETE spent PLAN | Yes | Cascade is *described* in PLAN (publish gate, DoD = consumer migration, sunset task); but the explicit "flip statuses to terminal + delete PLAN" done-signal is not spelled out in #511's visible text | **Partial (can't confirm delete-PLAN)** |

## Fresh-Capstone Seeding (no downstream PRs yet)

This is the most useful part, since #511 is a capstone created before any implementation
PR exists. How it handles "nothing to point at yet":

- **The PR-index points at PLANNED PRs, not live ones.** There are no open PR numbers for
  PR-1..PR-4. Instead the capstone enumerates the *intended* PRs by repo + role
  ("PR-1 (repo A + repo B)", "PR-2 (repo C)", ...) and sequences them by **dependency and
  a publish gate**, not by linking real PR URLs. The index is a forward-declaration.
- **It's a DRAFT, deliberately.** The body states two reasons: (1) it merges last, so it
  must not be mergeable yet; (2) some edits are pending human sign-off. Draft status is the
  "not ready / don't merge" signal that substitutes for a merge-order gate when downstream
  PRs don't exist to block on.
- **Artifacts present at creation time:** the full tactical chain (PRD Accepted-adjacent /
  In Progress, DESIGN **Accepted**, PLAN **Draft**) plus the roadmap edit and all cross-doc
  reconciliations. So at seeding, the *planning* artifacts are essentially complete and the
  design decision is already resolved — the capstone is created AFTER the `/scope` chain
  finishes, not as an empty shell at the very start.
- **Statuses encode readiness asymmetry:** DESIGN is Accepted (decision locked) but PLAN is
  still Draft (execution not begun) — exactly the state of a fresh capstone: decided, not
  yet executed.
- **The merge-order block already names the capstone's own terminal position** even though
  no other PR exists yet ("PR-5 ... <-- MERGES LAST"). The seed reserves the capstone's slot
  at the end of a sequence whose other slots are still empty.
- **Commit history shows the seeding path:** the chain was authored linearly in this one
  branch (roadmap → PRD → DESIGN → PLAN → reconciliation), so the capstone branch IS the
  `/scope` working branch, promoted to a capstone PR once the chain completed.

## What #511 Does That We Didn't Prescribe

- **`schema: <type>/v1` frontmatter** — versioned artifact-type tag beyond just `status:`.
- **A publish gate as a first-class merge-order node** — a non-PR serialization point
  ("publish packages, then downstream PRs may start") sitting between framework and consumer
  PRs. Our merge-order block has no notion of a non-PR gate.
- **Mermaid dependency graph** in addition to the ASCII/fenced block — dual representation.
- **A by-repo Verification-Gates table** — per-repo CI/exit criteria, separate from the
  PR-index.
- **A Public-Repo Hygiene / leak-guard section** — explicitly marks which planned PRs are
  public vs private and gives neutral-phrasing rules (relevant because the effort spans
  public-MIT and private-enterprise repos).
- **A `## Relationship to #<prior PR>` section** — reconciling an add/add overlap with an
  already-merged PR (superset-absorption narrative).
- **A `## Pending — NOT in this PR yet` section** — explicit carve-out of follow-up commits
  awaiting sign-off, with the rationale folded into the draft justification.
- **`repos:` list + `feature:`/`milestone:`/`issue_count:` in PLAN frontmatter** — machine-
  readable scope of the multi-repo blast radius.
- **An explicit Definition of Done tied to a real downstream consumer migration** ("the
  feature is Done only once the showcase consumer adopts it through the public surface") —
  the DoD is a behavioral proof, not a status flip.
- **A "superseded-in-part" marker** applied to a prior design whose seam this effort
  replaces — lifecycle bookkeeping on neighbor docs.

## What We Prescribed That #511 Lacks

- **No tabular PR-index in the PR body.** The PR×state grid we seed is absent; #511 keeps
  the index in the PLAN as prose + a by-repo table. The PR body relies on a single
  merge-order sentence.
- **No fenced merge-order block in the PR body.** The fenced/ASCII + Mermaid blocks live in
  the PLAN doc, not the capstone description. A reader of the PR alone gets prose only.
- **No artifact-chain *checklist*.** The chain exists via frontmatter pointers and the
  "What's in here" inventory, but there's no checkbox list with explicit `docs/<type>/...`
  paths and a "terminal; consumed before merge" PLAN marker rendered in the body.
- **No explicit "delete the spent PLAN" done-signal.** The completion cascade (publish gate,
  consumer-migration DoD, route sunset) is described, but the terminal "flip statuses +
  DELETE PLAN" step our pattern prescribes is not visible in #511's text.
- **Branch is not `feature/<slug>`** — it's an opaque `session/<hash>`, so the branch name
  carries no human-readable effort identity.

## Learnings / What To Borrow

1. **Adopt the publish/release gate as a merge-order primitive.** Real multi-repo efforts
   have non-PR serialization points (package publish, schema release). Our fenced merge-order
   block should allow non-PR gate nodes between PR rows, not just PR→PR edges.
2. **Draft status is the fresh-capstone "don't merge yet" mechanism.** When seeded before any
   downstream PR exists, mark the capstone a DRAFT and state the two reasons (merges-last +
   pending edits). This is cleaner than relying solely on a merge-order rule with empty rows.
3. **Forward-declare the PR-index by repo+role, not by live PR link.** A fresh capstone can
   fully populate its index with planned PRs (repo, contributes, depends-on, state=planned)
   and backfill real PR numbers as they open. We should make "planned" a valid State value
   and treat the capstone's own row as a reserved terminal slot from creation.
4. **Keep the canonical merge-order in the PLAN, mirror a summary in the PR body.** #511's
   split (rich breakdown in PLAN, prose sentence in PR) avoids drift but costs PR-only
   readers. Borrow the rich PLAN representation (per-PR depends-on + verification gates +
   Mermaid) while still seeding our body table/fence so the PR is self-describing.
5. **Add `schema: <type>/v1` to frontmatter** for machine-validatable artifact typing, and
   carry a `repos:` blast-radius list in the PLAN.
6. **Make the DoD a behavioral proof, not a status flip** — "Done when the real consumer uses
   the public surface" is stronger than "Done when statuses are terminal".
7. **Add a Public-Repo Hygiene / leak-guard section** to any capstone that spans public and
   private repos — mark each planned PR's visibility and give phrasing rules. Directly
   relevant to our public/private workspace split.
8. **Add a "Relationship to #<prior PR>" section convention** for when a capstone overlaps
   prior merged work (superset-absorption note prevents reviewer confusion).
9. **We should keep our explicit delete-PLAN done-signal** — #511 lacks it, and that's a gap
   in #511, not in us; our cascade is more disciplined there.

## Summary

Capstone PR #511 strongly matches our prescribed shape on the load-bearing signals — a bold
docs-only "capstone that merges last" declaration, a `docs/<type>/*.md` artifact chain linked
by `upstream:` frontmatter, and a full PRD→DESIGN→PLAN set authored up front — but it
relocates the PR-index and merge-order representation into the PLAN doc (as per-PR breakdown
sections + an ASCII/Mermaid sequence + a by-repo verification table) rather than seeding a
table and fenced block in the PR body, and it uses an opaque `session/<hash>` branch instead
of `feature/<slug>`. As a fresh capstone with no downstream PRs, it solves "nothing to point
at" by being a deliberate DRAFT (justified by merges-last + pending sign-off) and by
forward-declaring its PRs by repo+role with a reserved terminal slot, while its statuses
encode readiness asymmetry (DESIGN Accepted, PLAN Draft). The most borrowable additions are a
publish/release gate as a first-class merge-order node, draft-as-not-ready signaling, a
behavioral Definition of Done tied to real-consumer adoption, and a public/private leak-guard
section; the one place our pattern is stronger is the explicit "flip statuses + delete the
spent PLAN" done-signal, which #511 does not spell out.
