# Decision Research: fold verdict backstop

Two research agents ran. Full evidence in
`wip/explore_scope-artifact-persistence_d2_research_a.md` (what happens to the
bytes) and `_d2_research_b.md` (existing gating machinery and prior art). Both
are deleted at cleanup; the load-bearing findings are reproduced here.

## The framing correction that changes the decision

**Nothing in this system is reversible, including the folds the brief calls
"bounded."** An absorbed BRIEF's original text is as unrecoverable from a clone
as a folded-away DESIGN's. Both are created and `git rm`-ed on the same branch;
that branch squash-merges to a single commit whose tree contains neither, and
the branch is deleted. A fresh clone of the repo finds no trace under
`git log --all`. Checked directly against the one merged `/scope`+`/execute`
run: `docs/plans/PLAN-chain-cardinality.md` (PR #271, deleted in `6b68712`) is
absent from `origin/main`, and both the branch tip `bd2495b` and the deleting
commit are "Not a valid object name" in a fresh clone.

Only one deletion of a chain document exists in all of `main`'s history
(`2ebd974`, a stray-file cleanup), so in practice every document a `/scope` run
absorbs is born and buried inside one PR branch and never touches `main` at all.

**The real asymmetry is where the distillate lands, not what happens to the
original.** In every fold the original is equally gone; what differs is the fate
of the compact contribution section the absorb writes:

- Durable survivor: the distillate lands at a stable path on `main`, in every
  clone, addressable by `upstream:`, editable and correctable later, findable by
  someone who does not know the PR number.
- PLAN survivor: the distillate lands in a file `run-cascade.sh:860` deletes in
  the same PR. Nothing on `main` ever holds it.

Stated precisely: **a fold into a durable survivor converts an artifact into a
section of another artifact; a fold into the PLAN converts an artifact into
nothing.** That is a difference in what the repository ends up holding, not a
difference in reversibility.

Corollary, and it is decisive for one of the alternatives: a recoverability
mechanism aimed at the *deleted original* addresses the wrong half. What the
PLAN case lacks is a **durable destination**.

## The escrow that already exists (and its limits)

`refs/pull/<N>/head` survives branch deletion on GitHub. Verified:

```
$ git ls-remote origin 'refs/pull/271/*'
bd2495b462eb42655f6e21ca263b67c6be4aac81	refs/pull/271/head
```

From a fresh clone that had none of those objects, `git fetch origin
refs/pull/271/head` then `git show 6b68712^:docs/plans/PLAN-chain-cardinality.md`
prints the full 288-line PLAN byte-exact. **Recovery cost is one command, given
the PR number**, and bulk enumeration works (`git ls-remote origin 'refs/pull/*'`
lists 142 heads), so discoverability is not the weak link.

Three limits, all verified or structural:

- `git clone --mirror` captures **zero** `refs/pull` refs. The surface survives
  no mirror, no fork, no migration off GitHub.
- It is GitHub-server-side only, not part of the git object model the repo owns,
  not in the archive tarball, with no documented retention guarantee.
- Portability and retention are the weak links.

Best description: **a convenience escrow, not an archive.**

## Branch and PR topology

`/scope` never pushes and never opens a PR on the ordinary path (zero `git push`
in `skills/scope/`; the only `gh pr create` is the coordination PR for
`execution_mode: coordinated`). It commits to whatever branch HEAD is on and
stops. `/execute` **adopts** the branch and open PR it finds, including a
`docs/<topic>` scoping PR, and opens no second one
(`skills/execute/koto-templates/execute.md:297`). Confirmed on two independent
runs (PR #271, PR #278).

Two consequences:

1. **At fold time there may be no PR at all.** Decision 5's stated justification
   for the chosen carry check — "the recorded table is what makes the transfer
   auditable by a human reading the PR" — rests on a surface that need not exist
   when the fold happens, and on a PR-body record that has no implementation.
2. `/scope`'s state is branch-local `wip/` only; it explicitly does not satisfy
   invariant I-6, so resume on a different branch starts a fresh chain.

## The premise is prospective, not live

`phase-2-chain-orchestration.md:424` still marks PRD->DESIGN and DESIGN->PLAN as
**No**, and Stage 1 is a hard gate. So the only absorb reachable today is
BRIEF->PRD, whose survivor is durable. There is no accumulated damage to
remediate; the question is purely what to build alongside the new hop.

Worth noting: the author's own hand-rolled workaround (`6e1a22d`) was *not* a
fold into the PLAN. It moved the reasoning into **code comments** — a durable
surface — and deleted the artifacts separately.

## The single-mechanism constraint is scoped by removal verbs

Every statement of it is about shrinking, never about judging:

- "the consolidation judgment is the **single mechanism that removes a
  document**" (DESIGN:27)
- "it leaves exactly **one mechanism that reduces the artifact set**"
  (DESIGN:148)
- "**Nothing else in a `/scope` run removes a document.**" (SKILL.md:439-440)
- Goals bullet: "**Reducing the artifact set** is the only mechanism that ends a
  run with fewer documents than the chain has altitudes" (PRD:86-88)

The two mechanisms the objection actually named were the withdrawn Phase 1 entry
altitude and the Phase 2 judgment — both of which shrink the set, at different
times.

Three further pieces of evidence that a check inside the judgment is not counted:

1. **The carry check already is a second judgment**, made at a different moment
   from the verdict, and can overturn it. Decision 5 (adopting it) and Decision 1
   (declaring exactly one mechanism) sit in the same document, unreconciled
   because there is nothing to reconcile.
2. **Four things already force `keep`** — unmapped hop, failed carry check,
   post-absorb validation revert, R8 bail — and the DESIGN states this as a
   virtue: "**Every new failure mode fails toward keeping artifacts** ... No path
   deletes an artifact on an error" (DESIGN:735-738).
3. The constraint's stated purpose is **legibility of the rule**, not uniqueness
   of the judge ("meant neither read as the rule").

**Clean asymmetric read: veto-only is outside the constraint; a reviewer that can
flip `keep` to `absorb` is inside it.**

## Decision 5 Option D was deferred, not rejected

Verbatim (DESIGN:253-277):

> **Option D (rejected): an independent reviewer agent per absorb.** Buys
> independence the other options lack, at a per-run cost on the most common hop,
> for a check whose inputs are two documents in front of the same agent.
> Deferred; the recorded table is what makes a later reviewer possible.

The heading says rejected, the body says Deferred, and two other places treat it
as live: "**Decision 5 Option D stays available without rework**" (DESIGN:780-782)
and the Consequences entry recording the carry check's non-independence
(DESIGN:761-763).

The three deferral reasons rank unevenly. Cost is the weakest — a full `/scope`
run already spawns 20+ sub-agents across its children (`/brief` 2 jury, `/prd`
2-3 research + 3 jury, `/design` N deciders + 1 security + 3 review, `/plan` N
generators + 4 review-plan categories), so one reviewer per hop is a rounding
error. **"A check whose inputs are two documents in front of the same agent" is
the real one.**

## Juries in this repo are advisory, never blocking, never deleting

Inventory: `/brief` 2, `/prd` 3, `/strategy` 3, `/design` 3 + 1 security, all
spawned in parallel with `run_in_background: true`, no model or effort specified,
all writing a pinned verdict file with a literal `PASS | FAIL` marker.

No aggregation table row terminates a workflow; a FAIL routes to a fix or to the
human. The settling instructions are identical in `/prd` (phase-4:210-212) and
`/design` (phase-6:196-199): "**the user's verdict is the gate.**" `/brief` and
`/strategy` say the artifact ends "jury-cleared and ready for explicit human
ratification."

**No jury anywhere causes a deletion.** The only deletions in the chain are the
human Reject branches (double-confirmed before `git rm` — `/prd`
phase-4-validate.md:263-267), the absorb, and `/execute`'s cascade. So the repo
already treats "delete a durable artifact" as deserving a second human
confirmation, but only on a path a human initiated.

The exception that proves the rule: `/work-on` Phase 4b code review is genuinely
blocking (`blocking_count > 0` re-enters the coder loop; unresolvable escalates
to `done_blocked`).

**The degradation that matters most.** `references/fixes/sub-agent-dispatch.md:53-61`,
fallback shape 1: "**Serial-self-jury.** When the child's normal flow spawns a
multi-reviewer jury in parallel ... and the dispatch context does not support
parallel sub-agent spawns, the child runs each reviewer **serially within the
same process**, preserving the rubric set but losing parallelism." Bound to
`/design` Phase 6, `/prd` Phase 4, `/strategy` Phase 6. So an "independent
reviewer agent" inside a `/scope` run may in practice be the same process wearing
a different rubric — **precisely the condition Decision 5 Option D was deferred
over.**

## `/scope` blocks on humans routinely; it has no autonomy mandate

At least five blocking points: the Phase 0 cold-start prompt, the 7-day stale
session ladder, the **Phase 1 Proceed/Adjust/Bail confirmation the author always
answers**, the Phase 2 worktree intent-changing escalation, and the resume-ladder
Re-supply/Re-evaluate rows. Plus multi-pr PLAN Draft->Active requiring human
approval in `/plan`, and the parent-delegated-approval contract that hands every
child's ratification prompt up to the parent — though `/scope` Phase 2 never
implements presenting it.

`/scope` has **no** autonomy mandate; `/execute` is the only skill in the repo
with one. What `/scope` has is a mode flag (SKILL.md:99-118): `--auto` means
"decisions follow the recommended default based on context; the run does not
block on user input." And R20: "Every author-facing decision point ... SHALL
reach a conclusion and mark one option recommended, grounded in stated findings,
**with the human able to override outside `--auto`**."

**So a human confirmation at the terminal fold is ordinary. A gate that survives
`--auto` would be unprecedented.**

## The repo's own tier rule already classifies this

`references/decision-protocol.md:56-68`, escalation signals in override order:
"1. **Reversibility**: is the decision practically irreversible? -> Tier 4." And
every Tier 3+ decision "should escalate to the decision skill rather than
completing the micro-protocol." A fold into a soon-to-be-deleted PLAN is Tier 4
by the reversibility signal alone.

## "Trust the agent" is currently unfalsifiable

All 26 `/scope` eval scenarios are tier 1 (`ev.get("tier", 1)` in
`run-evals.sh:307-322`), which is `plan_only`: "describe the exact sequence of
commands you would run. **Do NOT execute any commands.**" Every expectation reads
"Plan states/runs/notes X". All 26 carry `"files": []`, so **the agent never reads
two real bodies and never actually makes the content judgment.** The scenario
prompts stipulate the answer in their parenthetical setup.

The harness can tell whether the agent follows the procedure. It cannot tell
whether the agent gets the worth call right. The "4/4 with skill vs 1/4 baseline"
numbers measure procedural conformance.

Building a verdict-quality eval is buildable but new ground: fixture machinery
exists (`skills/brief/evals/fixtures/`, `skills/explore/evals/fixtures/`,
`has_fixtures` at `run-evals.sh:358`) and `references/fixes/eval-fixture-frontmatter.md`
addresses the frontmatter-leak hazard, but no skill currently runs a tier-2 eval
that grades a *judgment*.

One reliability data point in the other direction: the single time the carry check
ran for real (#260's dogfood), it **failed** — it detected that the PRD's User
Stories did not carry the BRIEF's User Journeys, aborted the absorb, and shipped
all four artifacts. The same-agent check caught a non-carry rather than
rubber-stamping. One data point, and it favours the non-independent check.

## Durable surfaces available without new infrastructure

| Surface | In every clone? | Survives squash-merge? | Written automatically today? |
|---|---|---|---|
| A surviving chain doc | Yes | Yes | Yes — this is what an absorb produces |
| Squash commit message Part 1 | Yes | Yes, by definition | Yes, but human-trimmed |
| Code/config comments | Yes | Yes | **No** — but the author did it by hand on `6e1a22d` |
| `docs/decisions/DECISION-*.md` | Yes | Yes | **Yes, but only on rejection/re-evaluation exits** |
| Git notes | n/a | n/a | Not used at all (`refs/notes/*` empty) |
| Commit trailers | Yes | Only if in Part 1 | No convention beyond PB3's prohibition |
| `koto decisions record` | **No** | n/a | Yes, by `/work-on` — writes to `~/.koto/sessions` |
| `refs/pull/<N>/head` | **No** | n/a | Automatic, by GitHub |

**`docs/decisions/` is the closest existing fit.** Six files on disk with
`status:`/`decision:`/`rationale:` frontmatter. `/scope` Phase 3 **already writes
there automatically**, at the canonical path
`docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md`
(`phase-3-exit-finalization.md:84`) — but only on the re-evaluation and rejection
exits, and none of the six on-disk files match that naming, so the
`/scope`-automatic path has apparently never fired. Same directory, same
frontmatter shape, same skill already writes there, in every clone, survives
squash-merge, editable and linkable by path afterward.

## PR body Part 1 as a destination: capped by PB4, and frozen

No length limit exists anywhere (`.github/workflows/pr-body.yml` and
`references/pr-body-conformance.md` gate only PB1-PB4, all structural). But
**PB4 forbids markdown ATX headings in Part 1** — it must be prose, no
`## Decision Drivers`, no `### Rejected Alternatives`. Practical ceiling is where
prose-without-headings stops being readable: **40-60 lines**, hard-capped by
structure rather than by any check. PR #271's Part 1 is 29 lines of dense
four-paragraph prose and reads well; 120 lines would not.

Confirmed: Part 1 lands on `main` verbatim modulo GitHub's re-wrapping; Part 2 is
trimmed. **The trim is a human in the merge dialog** — no `gh pr merge` exists
anywhere in the repo, and the committer on `9f45603` is `GitHub
<noreply@github.com>`, the web merge button. With `squash_message: PR_BODY`
GitHub pre-fills the *entire* body, so if the human forgets, Part 2 lands too.
Part 2 is a *sometimes*-durable surface — one you cannot rely on either way.

Deeper problem with Part 1: it is **append-only history**. Once merged it cannot
be edited, corrected, superseded, or linked to by path. Durable but frozen and
unaddressable.

## Assumptions carried forward

- **Assumed:** `refs/pull/<N>/head` retention is best-effort with no documented
  guarantee and can be garbage-collected. *If wrong* (GitHub guarantees it
  indefinitely): the escrow becomes more attractive, but the mirror test still
  shows it is unportable, so it still cannot be the primary answer.
- **Assumed:** Decision 5's heading word "rejected" for Option D is a template
  artifact and "Deferred" in the body is operative. *If wrong:* reopening the
  reviewer is a reversal rather than a resumption — but "stays available without
  rework" makes that reading hard to sustain.
- **Assumed:** the parent-delegated-approval prompt is genuinely unimplemented in
  `/scope` Phase 2. *If wrong:* `/scope` blocks on a human once per child, which
  strengthens the "human confirmation is ordinary" reading considerably.
- **Assumed:** PR #271 and #278 are representative of run topology. *If wrong:*
  the same-branch finding weakens to "the two most recent runs did this", though
  both skill files independently state the adopt-don't-create rule.
- **Assumed:** all 26 `/scope` eval scenarios are tier 1 per `ev.get("tier", 1)`.
  *If wrong:* some might execute, but the empty `files` arrays still mean no real
  document pair is ever judged.

## Critical unknowns that remain

- **Whether a veto-only reviewer stays veto-only in practice.** A reviewer that
  reads both bodies and says "this fold loses X" is one edit away from being
  asked "then what should have folded?" Nothing in the repo constrains a
  reviewer's authority.
- **What "independent" can mean under serial-self-jury.** Whether the current
  dispatch context supports parallel spawns from a child is not stated anywhere.
- **Cost is entirely unmeasured.** The eval harness produces `timing.json` but
  its `workspace/` is gitignored, so no number is committed.
- **Whether a "compact contribution section" can honestly represent** Decision
  Drivers, Considered Options, Decision Outcome, Solution Architecture, Security
  Considerations and Consequences. The carry check's own rule — any
  `carried: false` aborts — suggests it cannot.
- **GitHub's actual retention policy for `refs/pull/<N>/head`**, and what happens
  on repo transfer between orgs.
