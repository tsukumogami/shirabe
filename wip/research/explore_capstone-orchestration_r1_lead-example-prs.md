# Lead: Reverse-engineer the capstone-PR pattern's mechanics from two real example PRs

## Findings

Two real PRs follow the "capstone" pattern. Below is the reconstructed mechanics, fully abstracted (no proprietary product/customer/business detail).

### 1. What a capstone PR *is*

A capstone PR is a **single docs-only PR** that sits at the top of a multi-PR, often multi-repo effort. It is not where the code lands. It is the durable record + index of the whole effort, and it is deliberately **merged LAST**. Both example PRs:

- Are titled with a `docs(...)` conventional-commit prefix and an explicit `(capstone)` suffix, e.g. `docs(design): <effort> (capstone)`.
- Open with a body that literally starts "This PR is the **capstone** of …" or "Capstone for …".
- Target `main` from a long-lived `feature/<effort-slug>` branch.
- State the merge-last rule in bold in the first paragraph ("**Merge it LAST** — it's the record the rest of the work is validated against").
- Describe themselves as docs-only and call out that normal app/integration pre-merge gates were intentionally not run because there's no app surface to exercise (a "pre-push gate" note explaining why CI smoke was skipped).

### 2. What artifacts live in it, and the directory structure

The capstone holds the **upstream artifact chain** as committed markdown under a `docs/` tree, organized by artifact type:

```
docs/briefs/BRIEF-<slug>.md
docs/prds/PRD-<slug>.md
docs/designs/current/DESIGN-<slug>.md      # "current/" = accepted/active designs
docs/roadmaps/ROADMAP-<slug>.md
docs/plans/PLAN-<slug>.md                  # transient — removed by completion cascade
```

Observed combinations differed by effort:
- One capstone carried **brief + PRD + design (+ a second related design it amended)**.
- The other carried **design + roadmap** (its PLAN had already been consumed/removed by the time it merged).

So the *set* of artifacts is effort-dependent, but they always come from the same fixed vocabulary (brief → PRD → design → roadmap → plan) and the same `docs/<type>/` layout. The design lives specifically under `docs/designs/current/`, signalling an accepted (not draft) design.

Each artifact carries **YAML frontmatter** with a consistent schema:
```yaml
schema: brief/v1          # artifact-type + version
status: Done | Current    # lifecycle state (the done-signal, see §5)
updated: <date>
visibility: Private
problem: | ...            # type-specific structured fields
outcome / decision / rationale: | ...
upstream: docs/roadmaps/ROADMAP-<slug>.md   # pointer up the artifact chain
motivating_context: | ...
```
The `upstream:` field links each artifact to its parent artifact, forming a navigable chain (brief → roadmap; design → roadmap; etc.).

### 3. How the capstone is created and seeded

The capstone is created **up front** as the first commit on the feature branch (commit 1 seeds the design + tracker / the findings + plan). It is then **updated continuously through the work session** rather than written once at the end.

### 4. How it's updated over the session (commit cadence)

This is the strongest signal that it's a living orchestration document, not a final write-up. Commit histories show **10–11 commits spanning a full working session** (one ran 02:20 → 21:44 the same day; the other spanned ~2 calendar days). The commit messages narrate the effort's progression, e.g.:

- seed the artifact(s)
- trim/adjust the definition-of-done; add a roadmap feature the effort surfaced
- reformat to the standard DESIGN template; add security considerations
- "accept" the design; move it to the active/current design folder
- add the single-PR PLAN; apply review fixes
- "reconcile capstone design + roadmap with the [live-validation] outcome" — i.e. fold real findings discovered while doing the implementation work back into the capstone
- track a newly-surfaced architectural finding as a roadmap feature
- final: `chore(cascade): post-implementation artifact transitions` / `finalize … chain to terminal states`

So the capstone absorbs everything the implementation PRs surface: new roadmap features, architectural findings (recorded, not forced), status transitions. It is the integration point for learnings.

### 5. The done-signal (when it can merge)

"Done" is expressed two ways that must both be true:

1. **All upstream implementation PRs are merged.** The body carries a PR index table and an explicit merge-order block (see §6) that has to show every dependency `MERGED` before the capstone goes in.
2. **A completion cascade has run** — the artifacts have been transitioned to terminal lifecycle states via frontmatter `status:` edits, and the **spent PLAN has been removed** ("the completion cascade has removed the spent PLAN"). The final commit is explicitly a cascade/finalize commit (`chore(cascade): post-implementation artifact transitions`, `finalize … chain to terminal states`). Designs end as `status: Current`; briefs/PRDs/plans end as `status: Done`; the PLAN file is deleted.

When both hold, the capstone is "the record the rest of the work is validated against" and is merged last.

### 6. How merge order is expressed

Two mechanisms, both **in the PR body** (no reliance on GitHub's native dependency features):

- **A PR-index table**: columns `PR | Repo | Contributes | State`, one row per related PR across all repos, with the capstone row marked "(this PR)" / "merging last". Cross-repo links are full `https://github.com/<org>/<other-repo>/pull/N` URLs. Related *issues* (non-PRs) are listed separately and tied to roadmap features.
- **A fenced merge-order block** listing each upstream PR with its MERGED status in dependency order, with ASCII annotations marking gates (e.g. a divider line: "the two above were the 'proven it works' gate for the docs"), ending with `← THIS capstone, merged LAST`.

### 7. How per-repo implementation work relates to the capstone

The implementation work is **split into ordinary single-purpose PRs** (one per concern, possibly in different repos — a backend/enterprise repo and the web repo). Each does one slice: the provider implementation + the runtime capability it needed; the UI/test-spec proof; the contributor-docs tree; the landing page. The capstone holds **none of the code** — only the design/plan/roadmap that those PRs were built against. The capstone's body explains, per PR, what it contributed and how it validates the design ("proves the web surface", "the core of the live validation").

The conceptual model from the body: an "upstream" artifact effort generalizes a **single-PR PLAN to a multi-repo org** — the capstone is created up front, holds the overarching plan + all upstream artifacts, is updated as work proceeds, merged last as the completion signal, and is fully consumed (PLAN removed, statuses terminal) before merge.

## Implications (for a shirabe tool)

A tool could automate the capstone lifecycle as:

1. **Create**: at effort start, open a docs-only capstone PR on a `feature/<slug>` branch; seed the chosen upstream artifacts under `docs/<type>/` with frontmatter (`schema`, `status`, `upstream`); title `docs(<type>): <effort> (capstone)`; inject a templated body with a PR-index table and a merge-order block.
2. **Update**: as each implementation PR is opened/merged, append/refresh its row in the index table and flip its state; fold surfaced findings into the design/roadmap (new features get `needs-design` rows).
3. **Gate**: block the capstone merge until every index-table row is MERGED.
4. **Cascade/Finish**: run a completion cascade that transitions artifact `status:` fields to terminal states and deletes the spent PLAN, then allow merge-last.

This maps cleanly onto shirabe's existing artifact lifecycle vocabulary (BRIEF/PRD/DESIGN/ROADMAP/PLAN, status frontmatter, `docs/designs/current/`, conventional-commit doc prefixes, the PLAN Draft→Active→Done→DELETED lifecycle).

## Surprises

- The capstone is **docs-only** and explicitly carries a documented reason for skipping the normal pre-merge CI smoke ("no surface to exercise"). The tool will need to handle "this PR legitimately skips integration gates."
- Merge ordering is expressed **entirely in prose/markdown** (table + fenced block + bold "merge LAST"), not via any GitHub dependency mechanism — so it's human/agent-enforced, which is exactly the gap a tool would fill.
- The two PRs are **not identical in artifact set** (brief+PRD+design vs design+roadmap). The pattern is the *role* (top-of-effort index + record, merged last, cascade-finalized), not a fixed file list.
- Findings discovered *during* implementation are reconciled back into the capstone mid-session (a dedicated "reconcile capstone with live-validation outcome" commit), confirming it's a living document.
- The PLAN is **deliberately deleted** by the cascade before merge — the absence of the PLAN is itself part of the done-signal.

## Open Questions

- What exactly triggers the completion cascade (manual command vs. detecting all PRs merged)? The commits suggest a discrete `chore(cascade)` step but not what invokes it.
- How is the capstone branch kept from going stale relative to `main` over a multi-day session — rebase cadence? (Not visible from PR metadata.)
- When implementation PRs live in *other* repos, how does the capstone in repo A learn their merge state to update its table — manual edit, or automation? Both examples show manual table edits.
- Is there a canonical body *template* the author reuses, or is each body hand-written? The two bodies share structure (capstone declaration, PR index table, merge-order block, pre-push-gate note) but differ in wording.

## Summary

A capstone PR is a single docs-only, merged-last PR opened up front on a `feature/<slug>` branch that holds the effort's upstream artifact chain (brief/PRD/design/roadmap/plan as `docs/<type>/*.md` with status frontmatter) and serves as the index + durable record the implementation PRs are validated against. It is a living document, updated across a full work session (10+ narrating commits) to absorb findings and status transitions, with merge order expressed purely in the body via a cross-repo PR-index table and a fenced merge-order block. It becomes mergeable only when every upstream PR is MERGED and a completion cascade has transitioned artifacts to terminal states and deleted the spent PLAN — that consumed-and-finalized state is the done-signal.
