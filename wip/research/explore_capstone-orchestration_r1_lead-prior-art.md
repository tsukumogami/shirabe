# Lead: What prior art exists for "one coordinating PR + per-repo implementation PRs + an explicit merge order" in multi-repo / monorepo-of-repos workflows? What's transferable to a "capstone PR" pattern vs overkill for a single-author workspace?

## Findings

The exploration target ("capstone PR") combines three distinct mechanics that the prior art tends to keep separate: (1) a **durable coordinating artifact** that holds the plan, (2) a **set of per-unit changes** linked into one logical change, and (3) an **explicit merge order**. No single mainstream tool ships all three as a "PR that merges last." Below, each tool is broken down by: how it represents the coordination unit, how it orders merges, and how it knows the whole change is done.

### Stacked-PR tools (Graphite, ghstack, Sapling, spr)

- **Coordination unit:** an ordered *chain*. Each PR/diff targets the branch below it rather than `main` (Graphite, ghstack), or each commit in a stack becomes one PR (Sapling `sl pr submit --stack`). The stack itself is implicit in the branch-base topology, not a separate artifact.
- **Merge order:** strictly **bottom-up**. Graphite adds a CI check that blocks merging a PR while its downstream (lower) PRs are unmerged; after each merge the remaining PRs are auto-rebased onto the new base. ghstack forbids merging via the GitHub UI (bases aren't `main`) and requires `ghstack land <PR>`.
- **Done signal:** the stack is done when the *top* (head) PR lands — there's nothing left above it. There is no separate "the whole thing is complete" object; doneness is "stack is empty."
- **Key transferable mechanic:** the **dependency-aware merge gate** (a CI check that refuses to merge until prerequisites have merged) and **automatic restacking/rebasing** after each merge.
- Sources: https://www.graphite.com/docs/merge-stack-prs-github , https://graphite.com/blog/the-first-stack-aware-merge-queue , https://github.com/ezyang/ghstack , https://sapling-scm.com/docs/git/sapling-stack/

Note: stacks order *bottom-up* (foundation first, capstone-equivalent = top merges last). This is the opposite framing from "capstone merges last while being created first." A stack's top PR is created last and merged last; a capstone is created first and merged last. So stacking gives the *merge-last* mechanic but not the *create-first durable plan* mechanic.

### Ordered/serialized merge (GitHub merge queue, bors/bors-NG, Mergify, GitLab merge trains)

- **Coordination unit:** a transient **queue/train** of independent PRs. No durable artifact — the queue exists only until it drains.
- **Merge order:** FIFO with speculative testing. Each candidate is tested against base + all earlier queued changes (a "pretend merge"). bors-NG pioneered "test the merge result before merging"; GitHub batches up to N and bisects on failure; GitLab runs cumulative pipelines (base+A, base+A+B, ...); Mergify offers serial/parallel/isolated modes plus priority lanes.
- **Done signal:** per-PR, not per-change-set — each PR is "done" when its speculative merge passes. There is no concept of "this group of PRs forms one change that is now complete."
- **Key transferable mechanic:** **merge skew prevention** — the insight that PRs passing CI independently can break when combined, so the final state must be tested before the last merge. For a capstone, this maps to "validate the integrated workspace before the capstone lands."
- **Overkill for single author:** the entire queue/batching/bisection machinery exists to *serialize concurrent contributors*. A single-author workspace has no contention, so speculative batching is pure overhead.
- Sources: https://mergify.com/blog/the-origin-story-of-merge-queues , https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue , https://docs.gitlab.com/ci/pipelines/merge_trains/ , https://docs.mergify.com/merge-queue/

### Cross-repo coordination (Gerrit topics, Android `repo`, GitLab cross-repo, Google)

- **Gerrit topics — the closest prior art to a capstone.** Coordination unit = a **topic string** shared by changes across multiple repos. Merge order: Gerrit's "Submitted Together" submits all changes in a topic atomically — *none* merge until *all* are submittable (approved, CI-passing, cleanly mergeable). Done signal: the topic becomes submittable only when every member change is ready, then they land together. This is "all-or-nothing across repos," keyed by a lightweight shared label rather than a heavyweight artifact.
- **Android `repo` tool:** coordination unit = an XML **manifest** pinning each repo to a revision. It's a *checkout/orchestration* layer (run a command across all repos, ensure consistent revisions), not a merge coordinator. Transferable idea: a **manifest-as-source-of-truth** listing the repos and their target states — a capstone PR's plan can play this role.
- **Done signal across repos:** Gerrit = topic submittable; `repo` = manifest revisions all present.
- **Key transferable mechanic:** the **shared coordination key** (topic) that links changes across repos without each change knowing about the others, plus **all-ready-before-any-merge** gating.
- Sources: https://gerrit-review.googlesource.com/Documentation/cross-repository-changes.html , https://gerrit.googlesource.com/git-repo/+/master/docs/manifest-format.md , https://source.android.com/docs/setup/reference/repo

### Change-set coordinators (Changesets, Nx release, Lerna, Rush)

- **Changesets (npm) — the closest prior art to a durable plan artifact.** Coordination unit = **markdown files in `.changeset/`**, each declaring "intent to release packages X,Y at bump types A,B with this summary." Committed alongside code. The `version` command consumes all accumulated changesets, bumps versions, updates changelogs, and **propagates to internal dependents**; `publish` releases and tags. Done signal: changesets are *consumed* (deleted) when versioning runs — their presence/absence tracks "pending vs released."
- **Lerna / Nx release / Rush:** dependency-graph-aware versioning and publishing across packages; Rush adds `rush change` (a change-file workflow like Changesets) plus controlled publish/deploy. All operate inside one repo on a known dependency graph.
- **Key transferable mechanic:** the **committed intent file** (a durable, in-repo artifact that declares what should happen, accumulates over the work, and is consumed on completion) and **dependency-graph-driven propagation/ordering**. This is the single best analogue for "a coordinating artifact that holds the plan."
- **Overkill:** semver computation, changelog generation, and registry publishing are package-distribution concerns irrelevant to a workspace-coordination PR.
- Sources: https://github.com/changesets/changesets , https://changesets-docs.vercel.app/ , https://lerna.js.org/docs/lerna-and-nx

### Multi-repo orchestration (meta, mu-repo, gita, mani)

- **Coordination unit:** a **registry/config file** listing repos (`.meta` for meta; registered repo lists for mu-repo/gita; `mani` YAML). meta explicitly frames itself as "many repos as one meta repo."
- **Merge order:** none. These are **fan-out command runners** (`meta git status`, `mu sh make`, `gita pull`) — they execute the same command across N repos. They have zero notion of merge ordering, change-completion, or atomic landing.
- **Done signal:** none — they're stateless executors.
- **Key transferable mechanic:** the **workspace manifest** (a single file enumerating the member repos) — exactly what niwa already has. Useful as the *substrate* a capstone iterates over, not as a coordination mechanism.
- Sources: https://github.com/mateodelnorte/meta , https://fabioz.github.io/mu-repo/ , https://github.com/nosarthur/gita

## Implications

For a single-author, agent-driven workspace, the transferable core is small and specific:

1. **From Changesets — the durable in-repo intent artifact.** A capstone PR should hold the plan as a committed file that accumulates per-repo work references and is *consumed/closed* (capstone merges) when complete. This is the strongest, cleanest mapping and aligns with the workspace's existing single-PR-plan convention generalized across repos.
2. **From Gerrit topics — a shared coordination key + all-ready-before-merge gating.** A capstone needs a lightweight link between itself and the per-repo PRs (a topic-like reference or a checklist in the capstone body), and the rule "capstone merges only when every linked PR has merged."
3. **From stacked PRs — the merge gate + merge-last position.** The mechanic of a CI/process check that *refuses* to merge the coordinating artifact until prerequisites are done is directly transferable and lightweight (it's just a gate, not a queue).
4. **From `repo`/meta — manifest-as-substrate.** The workspace manifest niwa already maintains is the list the capstone iterates over; no new tooling needed there.

What's overkill for one author: speculative merge batching, bisection, priority lanes, merge trains, parallel cumulative-state CI (all solve *concurrent-contributor contention*); semver/changelog/publish automation (package-distribution, not coordination); auto-restacking across repos (single author can rebase deliberately).

The capstone's distinctive twist vs all prior art: it is **created first** (to hold the plan up front) and **merged last** (to close the change). Stacks merge their last-created PR last; Gerrit topics land everything simultaneously; Changesets are created during work and consumed at the end. The "create-first-as-plan, merge-last-as-completion" lifecycle is a genuine recombination, not a copy of any one tool.

## Surprises

- **No mainstream tool unifies "plan artifact" + "cross-repo linkage" + "ordered merge" in one object.** The capstone idea sits in a real gap: Changesets has the artifact but no cross-repo merge ordering; Gerrit topics has cross-repo atomic merge but no durable plan; stacks have ordering but no plan and are single-repo.
- **Gerrit topics use atomic (simultaneous) submission, not "last."** The closest cross-repo prior art doesn't order one element last — it lands all at once. A "capstone merges last" is arguably *simpler* than Gerrit (sequential gate vs atomic multi-repo transaction) and avoids needing cross-repo atomic-merge infrastructure that plain GitHub lacks.
- **Stacks order bottom-up, which inverts the capstone's mental model.** In a stack the *foundation* merges first and the conceptual top merges last; a capstone is conceptually the *top-level plan* yet must merge last — so it behaves like the head of a stack whose body lives in *other repos*.
- **The merge-queue family is almost entirely irrelevant** to a single-author workspace despite being the most prominent "ordered merge" prior art — its complexity is 100% contention management.

## Open Questions

- Does GitHub offer any native cross-repo linkage a capstone could ride on (e.g., cross-repo PR references, GraphQL `closingIssuesReferences`), or must the capstone track per-repo PR state itself via a checklist/manifest in its body?
- Should the capstone's merge gate be enforced (a CI check that fails if any linked PR is open) or advisory (a checklist the author confirms)? For one author, advisory may be sufficient; prior art (Graphite) chose enforced because of teams.
- Should per-repo PRs reference the capstone (topic-style back-link) or should the capstone reference them (manifest-style forward-list), or both? Changesets is forward (artifact lists packages); Gerrit is a shared key (neither owns the link).
- How does the capstone get *consumed* — does merging it delete the plan artifact (Changesets-style), or does the plan persist as a durable design doc? This interacts with the workspace's wip/ hygiene and design-doc lifecycle rules.

## Summary

Prior art splits the capstone's three mechanics across separate tools: Changesets contributes the durable, committed, consumed-on-completion intent artifact; Gerrit topics contribute the shared cross-repo coordination key with all-ready-before-merge gating; stacked-PR tools contribute the dependency-aware merge gate and merge-last position; `repo`/meta contribute the workspace manifest as substrate. The entire merge-queue/train family (GitHub, bors, Mergify, GitLab) is overkill for a single author because its machinery exists solely to serialize concurrent contributors. The capstone's "created first as the plan, merged last as completion" lifecycle is a genuine recombination that no single tool ships, and is notably simpler than Gerrit's atomic cross-repo submission since a sequential merge-last gate needs no cross-repo transaction support.
