# Lead

Articulate, precisely, the decomposition rule for capstone execution — "group related work
within a repo into one PR to minimize churn; the hard breaking points are repo boundaries and
the cross-repo merge order" — then stress-test it, surface the edge cases the author hasn't
seen yet, and define when a repo legitimately gets more than one PR.

The author's working hypothesis: not rigidly one-PR-per-repo; group a repo's related work into
one PR to minimize churn; break across PRs only at repo boundaries + merge-order seams; a repo
MAY carry >1 PR when its work is genuinely unrelated / independently mergeable.

## Findings

### 1. The rule, stated precisely

The capstone is a single-PR PLAN that cannot be one literal PR because it spans repos. The
decomposition operates on two axes, and they are not symmetric:

- **Hard axis (forced cuts) — repo boundaries.** A PR lives in exactly one repo and merges into
  exactly one repo's default branch. So every repo boundary is a mandatory PR boundary. This is
  not a choice; it's a property of how git remotes and PRs work. N repos with work ⇒ at least N
  PRs. This axis is the source of the "hard breaking points" in the hypothesis.

- **Hard axis (forced ordering) — the cross-repo merge order.** Where repo X's work must land
  before repo Y's (Y depends on X's merged artifact: a published package, a released schema, a
  merged API), the merge order is a forced serialization. It does not add PRs, but it constrains
  the sequence in which the already-forced per-repo PRs may merge. Note this axis includes
  **non-PR gates** (package publish, schema release) — see #511's publish gate — which sit
  *between* PR nodes and are not themselves PRs.

- **Soft axis (discretionary cuts) — granularity within a repo.** Once a repo is fixed, how much
  of that repo's work goes in one PR is a judgment call. The default is **one grouped PR per
  repo** (all of that repo's capstone work, together). The exception is to split into >1 PR.

Precise statement:

> **Default:** each repo touched by the capstone gets exactly one PR carrying all of that repo's
> related capstone work. The capstone (coordinating) PR merges last.
>
> **Forced boundaries (never optional):** (a) one PR per repo — repo boundaries are PR
> boundaries; (b) merge order — any cross-repo dependency (including non-PR publish/release
> gates) forces a merge sequence over those PRs.
>
> **Exception (split a repo into >1 PR) — permitted only when ALL hold:** the two bodies of work
> in that repo are (i) independently mergeable (neither's correctness depends on the other being
> merged), (ii) independently reviewable/rollback-able as distinct units, and (iii) splitting
> does not introduce a cross-repo cycle (see Finding 3). A repo SHOULD split when keeping the
> work together would produce a PR too large to review as one coherent change, or would couple an
> urgent/low-risk change to a slow/high-risk one.

The asymmetry is the key insight the framing already half-captures but worth sharpening:
**boundaries between repos are discovered (they exist in the world); boundaries within a repo are
designed (the author chooses them to optimize review and rollback).** The rule's whole job is to
stop the author from manufacturing within-repo boundaries that the world didn't force.

### 2. Decision criteria: "related vs unrelated" within a repo

Two pieces of work in the same repo belong in the **same** PR when they share enough of the
following that separating them creates coordination cost without buying isolation. The four tests,
in priority order:

1. **Shared mergeability (dependency).** Does piece B compile/pass-tests/behave correctly only if
   piece A is also present? If yes → same PR. Splitting dependent work means the first PR merges
   the tree into a broken or dead-code state. This is the strongest bind: dependent work is *not
   optional* to group, it is *required* to group (or to be explicitly ordered as a stacked PR,
   which is a heavier mechanism — see trade-off below).

2. **Atomic rollback.** If a regression is found post-merge, do you want to revert both pieces or
   just one? If reverting one without the other leaves the repo coherent and useful, that's a
   signal they *can* be separate. If reverting one alone breaks the other, they must be one PR.
   Rollback granularity is the mirror image of merge granularity — you can only roll back at PR
   boundaries.

3. **Shared review surface.** Do the two pieces touch the same files / the same subsystem / the
   same reviewer's mental model? Work that a reviewer must hold in their head simultaneously to
   judge correctness belongs together. Work that a reviewer would review in two disconnected
   passes (a parser change and a CHANGELOG edit) is a candidate to split — though shared review
   surface alone is the *weakest* criterion and usually yields to size pressure rather than
   forcing a split.

4. **Independent value / cadence.** Can one piece ship and deliver value while the other is still
   in progress? If piece A is a hotfix the team wants now and piece B is a multi-day refactor in
   the same repo, coupling them holds the hotfix hostage. Divergent urgency is a legitimate
   reason to split even when the pieces are topically related.

The default tilts toward grouping: **when criteria conflict, dependency and atomic-rollback win
over review-surface and cadence.** You group unless there is a positive reason (independent
rollback desired, divergent cadence, or unreviewable size) to split. "They're different topics"
is not, by itself, sufficient — topical difference only matters if it coincides with independent
mergeability.

### 3. Interaction with the merge-order DAG (the subtle part)

`/plan` emits an **issue-level** dependency graph (`waits_on` edges). The capstone needs a
**PR-level** graph. Collapsing issues into per-repo PRs is a graph contraction: you merge all
nodes (issues) tagged with the same repo into one super-node (the repo's PR). **Graph contraction
can create cycles that did not exist at the issue level.** This is the failure mode the author
hasn't seen.

Concrete cycle:

```
issue-1 (repo X) ──▶ issue-2 (repo Y) ──▶ issue-3 (repo X)
```

At the issue level this is a clean DAG (X then Y then X again — fine, three sequential steps).
Contract by repo (group all repo-X issues into PR-X, all repo-Y into PR-Y):

```
PR-X ──▶ PR-Y ──▶ PR-X      ⇒  PR-X ⇄ PR-Y   (a 2-cycle: deadlock)
```

PR-X now both precedes and follows PR-Y. Neither can merge first. The grouping is **illegal** —
it has destroyed the topological orderability that `/plan` guaranteed at the issue level.

**When grouping is legal.** Grouping repo X's issues into one PR is legal iff the contraction
preserves acyclicity — equivalently, iff the set of repo-X issues forms a "convex" slice of the
DAG: there is no path that *leaves* repo X and *returns* to repo X. Formally: for any two repo-X
issues a and b, every dependency path between work outside X that connects to X must not thread
*through* a non-X repo and back. The clean case (all of X's work depends only on things outside X
that are themselves upstream, and everything downstream of X stays downstream) contracts safely.

**What to do when intra-repo grouping would violate cross-repo order.** Three options, in order
of preference:

- **Split the repo at the cycle seam.** The cycle `issue-1(X) → issue-2(Y) → issue-3(X)` resolves
  cleanly if repo X carries TWO PRs: `PR-X1` (issue-1) merges before PR-Y, `PR-X2` (issue-3)
  merges after. The DAG becomes `PR-X1 → PR-Y → PR-X2` — acyclic. **This is a case where a repo
  legitimately gets >1 PR for reasons that have nothing to do with the work being "unrelated."**
  The author's exception list (split when unrelated/independently-mergeable/too-big) is
  *incomplete*: there is a fourth, structural trigger — **split to break a contraction cycle
  imposed by the cross-repo merge order.** The two PRs may be tightly related; they're split
  purely because the global ordering threads through another repo between them.

- **Re-sequence to eliminate the back-edge.** Sometimes issue-3(X) only depends on issue-2(Y) by
  accident of how the plan was written; if the real dependency is weaker, reorder so all of X's
  work precedes (or follows) all of Y's. This is a `/plan`-level fix, not a capstone-level one —
  it argues for the capstone decomposition feeding *back* into plan refinement rather than being a
  pure downstream consumer.

- **Stacked PRs within the repo.** If the two X-pieces are genuinely dependent (can't split
  cleanly) but ordering forces a Y-merge between them, stack them: PR-X2 is opened on top of
  PR-X1's branch. This preserves dependency while allowing the Y-merge in the gap. Heavier
  (rebase coordination), so it's the last resort.

The deep point: **per-repo grouping is a lossy contraction of a graph that was validated acyclic
at a finer grain. The capstone must re-validate acyclicity *after* contraction, and when
contraction fails, the resolution is almost always "this repo gets more than one PR" — driven by
topology, not by relatedness.** Any tool that auto-groups issues into per-repo PRs MUST run a
cycle check on the contracted graph and refuse/split when it finds one.

### 4. Churn vs atomicity trade-off

"Churn" in this context is not lines-of-code churn. It is **coordination churn** — the human and
mechanical overhead of having more merge units:

- number of PRs to open, describe, and get reviewed;
- number of review round-trips (each PR is a separate review thread);
- rebase overhead (each open PR must be kept current against its base as siblings merge — and in
  a stacked configuration, against its parent PR);
- merge-coordination steps (each merge-order edge is a "wait for X, then merge Y" the author or
  tool must track — exactly the hand-updated index table the findings flag as the unsolved part);
- capstone-body maintenance: every extra PR is another row in the PR-index / merge-order block
  that must be kept in sync as states change.

So "minimize churn" = minimize the number of merge units and ordering edges, subject to the forced
boundaries. Grouping reduces churn directly.

**Cost of grouping too coarsely:**
- A single repo PR so large no reviewer can hold it ⇒ shallow review, bugs slip.
- All-or-nothing rollback: a regression in one slice forces reverting unrelated good work in the
  same PR.
- Hostage coupling: a fast/low-risk change waits on a slow/high-risk one because they share a PR.
- Hidden ordering violations: coarse grouping is exactly what creates the contraction cycles in
  Finding 3.

**Cost of grouping too finely:**
- Many PRs ⇒ many reviews, many rebases, a large merge-order DAG with many edges.
- More cross-repo state to track (the genuinely-unsolved automation problem) — every PR is
  another thing whose merge state the capstone must learn.
- Dead-code / broken-intermediate-state merges if dependent work is split without stacking.
- Reviewer fatigue and context-switching across many small disconnected PRs.

**The optimum** is the coarsest grouping that still (a) stays reviewable, (b) keeps independently-
rollback-able things separate, (c) doesn't couple divergent cadences, and (d) doesn't create a
contraction cycle. (d) is a hard constraint (correctness); (a)–(c) are soft optimizations. The
rule's "minimize churn" instinct is correct but must be read as "minimize churn *subject to the
acyclicity constraint and the reviewability floor*," not "minimize churn unconditionally."

### 5. Edge cases

- **One repo, framework change + unrelated docs change.** Textbook split candidate: independently
  mergeable, independent rollback, divergent review surface, divergent cadence. Two PRs. BUT — if
  the docs *document the framework change*, they're no longer unrelated: the docs are only correct
  once the framework lands, so they share mergeability ⇒ one PR (or docs stacked on framework).
  The test is not "is it docs vs code" but "is the docs change correct independent of the code
  change." This is the case that most tempts a wrong split.

- **Non-PR gate between repos (package publish).** #511's publish gate. A serialization point that
  is not a PR: repo A's PR merges → CI publishes package → repo B's PR (which depends on the
  published package) may now merge. The merge-order DAG must support **non-PR gate nodes** between
  PR nodes. This does not change the per-repo grouping rule, but it means the ordering axis is
  richer than "PR → PR": it's "PR → gate → PR." A tool modeling only PR→PR edges cannot express
  this and will let repo B merge against an unpublished package. The gate is also a place where
  the capstone genuinely cannot proceed autonomously (publish may need a human or a release job),
  so it's a natural pause/resume seam.

- **A change that must span two repos atomically.** The framing should treat this as a **red
  flag** first and a **real constraint** second. Because PRs are per-repo, "atomic across two
  repos" is *impossible* with plain PRs — there is always a window where one repo is merged and the
  other is not. If the system is correct only when both are merged simultaneously, the design has a
  cross-repo coupling that the repo split cannot honor. Usually this is a **design smell**: the
  seam between the two repos is in the wrong place, or a compatibility shim is missing. The right
  fix is to make the change **backward/forward compatible across the merge window** — repo A ships
  a change that tolerates both old and new repo-B behavior (expand/contract / two-phase), so the
  intermediate state (A merged, B not) is valid. Then it's two ordered PRs, not an atomic pair.
  The *real-constraint* residue (rare): when the two repos are released as a single versioned unit
  (e.g. a monorepo split that hasn't happened, or a lockstep-versioned pair), the "atomicity" is
  actually achieved downstream at *release/publish* time, not at *merge* time — which converts the
  problem back into a publish-gate ordering (merge both, then publish both together). So even the
  legitimate case reduces to ordering + a gate, not true merge-atomicity. The rule should
  explicitly say: **the capstone cannot make two PRs atomic; it can only order them and gate the
  release. Work requiring cross-repo atomicity must be reshaped into a compatible-intermediate
  sequence before it can be decomposed at all.**

## Implications

- The exception list for "a repo gets >1 PR" needs a **fourth trigger** beyond the author's three
  (unrelated / independently mergeable / too big to review): **structural — split to break a
  merge-order contraction cycle.** This trigger produces splits between *related* work, which the
  current framing would wrongly forbid.

- Any tool that contracts the issue DAG into a per-repo PR DAG MUST re-run a cycle check on the
  contracted graph. Acyclicity at the issue level does NOT survive contraction. This is a
  load-bearing correctness check, not a nicety. When it fails, the resolution is split-at-seam,
  re-sequence, or stack — in that preference order.

- The merge-order representation must be a DAG with **two node types** (PR nodes and non-PR gate
  nodes), not a list and not a PR-only graph. #511's publish gate is the existence proof.

- "Minimize churn" must be encoded as "coarsest legal grouping," where *legal* = acyclic-after-
  contraction AND below the reviewability size ceiling AND not coupling independent-rollback or
  divergent-cadence work. Churn minimization is an objective subject to constraints, never the
  top constraint itself.

- Cross-repo atomicity is out of scope by construction. The decomposition skill should *detect*
  an atomicity requirement and refuse to decompose until the work is reshaped into a
  compatible-intermediate sequence — surfacing it as a design problem upstream, not papering over
  it downstream.

## Surprises

- The forced/discretionary split maps onto a discovered/designed distinction: inter-repo
  boundaries exist in the world; intra-repo boundaries are authored. The rule's real purpose is to
  prevent inventing world-boundaries that aren't there.

- Per-repo grouping is **graph contraction**, and contraction is exactly the operation that can
  manufacture cycles from an acyclic graph. The author's "group to minimize churn" instinct,
  applied naively, is precisely the operation most likely to break the merge order it's supposed to
  respect. The optimization and the correctness constraint pull against each other through the same
  mechanism.

- The most-related-looking split (the same repo, twice) is sometimes the *most necessary* one —
  driven entirely by another repo's position in the global order, with zero relation to whether
  the two X-PRs are topically connected. "Relatedness" turns out to be the wrong frame for that
  case entirely.

- True cross-repo merge-atomicity doesn't exist with plain PRs, and even the legitimate "must ship
  together" case collapses into ordering-plus-a-release-gate rather than atomic merge — so the
  scary edge case dissolves into the publish-gate machinery already needed for the mundane case.

## Open Questions

- Should the capstone tool *auto-split* a repo when it detects a contraction cycle, or refuse and
  hand the cycle back to `/plan` for re-sequencing? (Correctness says it must do *something*;
  ergonomics says auto-split; plan-integrity says feed back.)

- Where does the reviewability size ceiling live — a hard line count, a heuristic, or human
  judgment announced-and-overridable like the other capstone conventions?

- For the compatible-intermediate reshaping of would-be-atomic cross-repo work: is that the
  capstone's job to enforce, or `/design`'s job to have already solved before planning? (Likely
  `/design`, but the capstone needs a detector to refuse if it wasn't done.)

- Does breaking the contraction cycle via stacked PRs (vs split-at-seam) need first-class support,
  or is it rare enough to leave manual?

## Summary

The capstone decomposition has two forced axes (one PR per repo, because repo boundaries are PR
boundaries; and a merge order, because cross-repo dependencies and non-PR publish gates serialize
the per-repo PRs) and one discretionary axis (granularity within a repo), whose default is one
grouped PR per repo and whose exception is to split — when the pieces are independently
mergeable/rollback-able, when one PR would be too large to review, or, critically and unlisted by
the author, when per-repo grouping would create a merge-order cycle. The subtle failure is that
collapsing the issue-level DAG into a per-repo PR DAG is a graph contraction that can manufacture
cycles a clean issue graph never had, so any grouping must re-validate acyclicity after
contraction and split-at-seam (or re-sequence, or stack) when it fails — meaning the most
"related" split, the same repo twice, is sometimes the most necessary one, forced by another
repo's position in the global order. "Minimize churn" is correct only as "coarsest *legal*
grouping," where legality is acyclicity-after-contraction plus a reviewability ceiling; and true
cross-repo merge-atomicity is impossible with plain PRs, so work that seems to need it must be
reshaped into a compatible-intermediate sequence (or deferred to a release gate) before it can be
decomposed at all.
