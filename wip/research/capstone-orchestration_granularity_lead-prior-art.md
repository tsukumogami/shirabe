# Lead

How do real-world multi-repo and monorepo change-coordination tools decide the GRANULARITY of a change/PR, and what rules do they give for when to split vs group? Extract the transferable principle for "what is one PR's worth of work" — to inform how a capstone effort (one coordinating PR holding plan + artifacts, merging last) decomposes its implementation into PRs across several repos in one single-author, AI-agent-driven workspace.

Working hypothesis under test: don't make it rigidly "one PR per repo"; group related work within a repo into one PR to minimize churn, and treat repo boundaries + cross-repo merge order as the hard breaking points (a repo MAY have >1 PR only when its work is genuinely unrelated / independently mergeable).

# Findings

## 1. Stacked-PR / one-logical-change cultures (Graphite, ghstack, Sapling, Gerrit, Phabricator)

These tools share one definition of the unit: **one self-contained logical change**, not "one repo" and not "one file."

- **Gerrit.** "The cardinal rule for creating good commits is to ensure there is only one 'logical change' per commit." Guidance: "Separate logical features into separate changes... when adding a new ability, make separate changes for the UI and the ssh commands if possible." And: "Do only what the commit message describes" — even trivial unrelated edits (a typo fix, externalizing a string) belong in a separate change, to keep `git blame` and `git revert` useful. Bias: "when in doubt, err on the smaller side." Source: Gerrit "Crafting Changes" / OpenStack GitCommitMessages.
- **Graphite.** "1 logical change per PR, which makes it easy to review and easy to revert." Split by "identifying logical split points... looking for boundaries in functionality or file changes." Each PR must be "self-contained and reviewable on its own." Concrete sizing heuristic: bug fixes <100 lines = single PR; features 200-500 lines = 2-3 stacked PRs; 500+ = always stacked. Separately, Graphite's data piece argues "the ideal PR is 50 lines long."
- **Sapling / ghstack / Phabricator (Meta lineage).** "One commit per diff." Each commit becomes its own PR/diff in a dependent chain (Diff 2 depends on Diff 1). The whole stack is the feature; each diff is one reviewable logical step. Sapling ships a `split` command precisely so an author can carve one commit into several logical commits by selecting hunks.

The unit here is **logical change**, and the explicit rationale for keeping it small is review speed + clean revert. Crucially, these are *single-repo* cultures: stacking solves "one big change is hard to review" by ordering small dependent changes, not by spanning repos. The breaking point is logical boundary + dependency order, which is the same shape as the hypothesis's "merge order" axis but applied within a repo.

## 2. Coordinated multi-package release tools (Changesets, Nx, Lerna, Rush)

These decouple the *change* unit from the *release/version* unit, and the dominant model is **per-package, change-driven, only-what-changed**.

- **Changesets (npm).** A changeset is "an intent to release stored as data" — the developer declares per-package impact (major/minor/patch) per change. "Only the packages with actual changes are version-bumped." Multiple changesets to the same package collapse to the single highest bump (two minors do not become two bumps). Inter-package dependents are bumped automatically. So the authored unit is the *change* (a changeset), but the released unit is *per affected package*, computed, not hand-grouped.
- **Nx.** Core primitive is the project graph + "affected" detection: a change implies the set of projects it touches; CI rebuilds/tests/releases exactly that affected set. Granularity is derived from the dependency graph, not declared per PR.
- **Lerna (v7+).** Runs on Nx under the hood for affected/caching; its center of gravity is publishing many packages with independent versioning — again, only changed packages publish.
- **Rush (Microsoft).** First-class change-file + changelog management for large numbers of packages; same per-package, change-file-driven model.

Transferable point: the unit of *work declaration* is the logical change; the unit of *coordination* is "the set of packages this change actually affects," computed from the dependency graph. Nobody mandates one PR per package. They group by what a single coherent change touches and let the graph define blast radius. This directly supports "group related work, don't split per package/repo by default."

## 3. Cross-repo grouping mechanisms (Gerrit topics, GitLab merge trains, Android `repo`)

This is where the multi-repo merge-order question is answered directly.

- **Gerrit topics.** The unit stays the per-repo *change*; a *topic* is a label that groups changes across repos so they "submit together." Critical atomicity asymmetry: "Topics that span only a single repository are guaranteed to be submitted together," but "topics that span multiple repositories simply triggers submission of all changes. No other guarantees are given... you could get a partial topic submission." So Gerrit gives you grouping intent across repos but **no atomic cross-repo merge** — partial landing is a real outcome. `Depends-On:` commit-message tags are the alternative for declaring cross-repo dependency/order. Practical guidance even warns to namespace topic strings (`username-`) to avoid accidentally grouping unrelated changes.
- **GitLab merge trains.** Unit is the merge request; a train is an *ordered queue* into one target branch. It validates each MR against the cumulative result of those ahead of it (A; A+B; A+B+C), and on failure ejects the bad MR and re-sequences the rest. This is an explicit machine for "merge order matters and is enforced," but it operates within a single target branch, not across repos.
- **Android `repo`.** Orchestrates many separate git repos via a manifest; coordination is a tooling/manifest concern layered over independent per-repo changes (commonly used with Gerrit topics for grouping). It does not redefine the change unit — the repo stays the boundary and the change stays per-repo.

Transferable point: across all three, the **repo (or target branch) is the hard atomic boundary**, and cross-repo coordination is achieved by an ordering/grouping label layered on top — never by merging atomically across repos. Real systems accept that cross-repo landing is sequenced, not transactional, and design for partial-landing safety. This is strong evidence for treating repo boundaries + an explicit cross-repo merge order as the hard breaking points.

## 4. PR-size / atomic-PR research and principles

- **Size vs review cost.** Convergent empirical findings: review quality degrades sharply above ~200 changed lines (Google); 50-line changes merge ~40% faster than 250-line; capping near 200 LOC gives a ~90% chance of an under-hour review; PRs >1000 lines have ~70% lower defect-detection. Smaller PRs review faster, catch more bugs, and roll back more cleanly.
- **Batch-size economics.** Framed as transaction cost (cost of preparing/shipping a change) vs holding cost (cost of *not* shipping). Optimal batch size balances the two; bigger PRs raise holding cost and review cost. "Churn" is what you minimize by not re-touching the same area across many PRs and by keeping each PR's diff focused.
- **Atomicity trade-off (the counterweight).** Atomic-commit/PR guidance says one change per unit so revert is clean and side-effect-free. But practitioners flag the over-granularity failure mode: too many tiny commits/PRs become "hard to follow and reason about," raise overhead (committing, pushing, opening/reviewing many PRs), and make *feature-level* rollback harder when one feature is scattered across many units. So the goal is the *right-sized* logical change — small enough to review and revert, large enough to be coherent and to revert *as a feature*.

Transferable point: the size literature optimizes within a PR (keep diffs focused, minimize churn), while the atomicity literature warns against splitting so far that a coherent unit fragments. Together they argue for "group related work into one coherent, reviewable PR" — neither maximally split nor monolithic.

# Implications

- **Map for the hypothesis: largely confirmed, with one refinement.** Every family agrees the unit is the *logical change*, not the repo and not the package. Repo/branch boundaries are the hard atomic limit (Gerrit, merge trains, repo). Cross-repo coordination is universally an ordering/grouping label over per-repo units, with no atomic cross-repo merge — so "break at repo + merge-order boundaries" matches how production systems actually behave.
- **"Group related work within a repo into one PR" is well-supported** by the per-package "only-what-changed" tools (Changesets/Nx) and by the churn/batch-size economics. Don't pre-split a repo's coherent work.
- **"A repo MAY have >1 PR when work is genuinely unrelated/independently mergeable" is also well-supported** — but the stronger, more operational signal from Gerrit/Graphite/Sapling is that the right reason to split *within a repo* is a **logical boundary or a dependency-order boundary**, not merely "unrelated." A repo can legitimately host a *stack* of ordered PRs for one feature when the change is too large to review atomically. So the rule should read: split within a repo when (a) work is independent/unrelated, OR (b) a single logical change is too large to review cleanly and has a natural dependency order (stack it). Both are "logical boundary" cases.
- **Repo is the atomicity unit; merge order is a first-class artifact.** Since no tool offers atomic cross-repo merge, the capstone design should make the cross-repo merge order explicit and tolerate sequenced (not transactional) landing — the capstone PR merging last is exactly the "topic that holds it together and lands when the parts are in" pattern, analogous to a Gerrit topic / merge-train tail.
- **Single-author AI-agent context shifts the trade-off slightly.** The dominant cost in the size literature is *human review*; an agent-driven workspace lowers per-PR human transaction cost less than it lowers authoring cost. Reviewability and clean revert still favor focused PRs, but the over-granularity overhead (many tiny PRs to open/track) argues against reflexive splitting. Net: bias toward one coherent PR per repo, split only on a real logical/order/independence boundary.

# Surprises

- **Cross-repo atomicity does not exist even in the tool built for it.** Gerrit, the canonical multi-repo review system, explicitly only guarantees atomic submission *within a single repo*; cross-repo topics "simply trigger submission" and can land partially. The industry has decided the repo is the atomic unit and cross-repo is best-effort ordering — strongly validating "repo boundary = hard breaking point."
- **The monorepo tools deliberately decouple change-unit from release-unit.** Changesets authors per-change but releases per-affected-package, computed from the graph. The grouping is derived, not declared — a different mental model from "decide your PRs up front."
- **The pure stacked-diff cultures are more aggressive than the hypothesis.** "One commit per diff/PR" (Sapling, ghstack) splits *more* finely than "group related work into one PR." The reconciler is review-size: stacking exists to keep each reviewable unit small while preserving order — i.e., splitting *within* a repo along dependency order is normal and good when a change is large.

# Open Questions

- For a single-author AI workspace where human review is the scarce resource but authoring is cheap, where is the real size sweet spot — closer to the 50-200 LOC review-optimal, or larger because one reviewer batches context? This sets how aggressively the capstone should stack within a repo.
- Should the capstone enforce an explicit, validated cross-repo merge order (merge-train style) or rely on the human/agent to sequence (Gerrit-topic style)? The atomicity findings suggest the order must be a durable artifact regardless.
- When a single logical change genuinely spans repos (e.g., a schema change in repo A consumed in repo B), the right unit is "one topic, two ordered PRs." Does the capstone model name this case distinctly from "unrelated work in two repos," since both produce >1 PR but for opposite reasons?

# Summary

Across stacked-PR cultures, monorepo release tools, and cross-repo coordinators, the unit of work is consistently the *self-contained logical change* — never "one repo" and never "one package" — sized small enough for fast review and clean revert (research converges around 50-200 changed lines) but not so small it fragments a coherent feature. The repo (or target branch) is treated as the hard atomic boundary by every cross-repo system; coordination across repos is always an ordering/grouping label (Gerrit topics, merge trains, the capstone's last-merging PR) with no atomic cross-repo merge, so merge order must be an explicit, partial-landing-tolerant artifact. This confirms the hypothesis with one refinement: group related work in a repo into one PR, break at repo + merge-order boundaries, and allow >1 PR per repo not only when work is unrelated but also when a single large change has a natural review/dependency-order split worth stacking.
