# Decision D1: /execute's fully-folded-chain disambiguation

## Current rule

The passage sits inside the **Finalization-Not-Done Guard (R5)** section of
`skills/execute/SKILL.md`, as the third bullet of the "Seed-doc rule
(load-bearing)" list. `skills/execute/SKILL.md:591-600`:

> - **A finalized chain that folded every artifact away.** `/scope`'s consolidation
>   judgment can absorb at any hop, so a chain can end with no durable artifact at all:
>   the DESIGN folded into the PLAN, and the cascade then deleted the PLAN. There is no
>   anchor to seed on, and that is **completion, not a missing seed**. Treat it as
>   complete rather than reporting `L05`.
>
>   Distinguishing it from a genuinely unfinalized chain is what `docs/folds.md` is for:
>   a chain that folded away leaves a row naming what was absorbed into what, and a
>   chain that never ran leaves nothing. The record is the evidence; it is not a seed,
>   and nothing here reads it to make a lifecycle decision.

### What the surrounding text is actually deciding

The guard is not new machinery. It is the existing
`shirabe validate --lifecycle-chain <seed-doc> --mode=ready` invocation
(`skills/execute/SKILL.md:547-575`), whose exit code is the whole signal:
`0` = finalization complete, `2` = violations (`L01`…) so the guard fires,
`1` = tool-error/inconclusive.

`--lifecycle-chain` **seeds on a path that must exist**. A missing seed is not a
distinct outcome — it produces `L05` and exit 2, indistinguishable at the exit-code
level from a genuine `L01` finalization failure. `L05` is the walker's defensive
"could not index this document" error (`crates/shirabe-validate/src/lifecycle.rs:408,
417, 446, 456` — uncanonicalizable path, escaped root, frontmatter parse failure,
undetectable format). So the entire seed-doc rule exists to stop an agent pointing the
guard at a path that is gone and reading the resulting exit 2 as "finalization did not
complete."

The three bullets are three seeds for three situations:

1. **Suspected mid-run** → seed the still-present `docs/plans/PLAN-<slug>.md`; ready
   posture fails `L01`; the guard correctly fires.
2. **A finalized chain** → the PLAN is gone (`run-cascade.sh:874` `git rm -f "$PLAN_DOC"`),
   so seed a surviving durable anchor: `docs/designs/current/DESIGN-<slug>.md`, or the
   BRIEF/PRD at Done.
3. **A fully-folded chain** → there is no anchor. Any seed you could name is gone.

The reason bullet 3 says "completion, not a missing seed" is that the guard's *decision*
in that case is genuinely correct in both directions: there is nothing in the tree for
ready-posture `--lifecycle-chain` to fail on, and there is nothing for a never-ran chain
either. The CI wiring makes this explicit — CI does not run `--lifecycle-chain` per chain
at all; it runs the whole-tree `shirabe validate --lifecycle . --mode=ready` gated on
`draft == false` (`skills/execute/SKILL.md:614-622`), which a fully-folded chain passes
trivially by contributing no documents. **The lifecycle machinery already treats the two
cases identically and is right to.** The consumer of the distinction is a human
investigator holding a topic slug or a dead citation, asking "did a chain ever run for
this?" — exactly as the passage itself concedes when it says "nothing here reads it to
make a lifecycle decision."

That framing matters for the options below: this is not a gate that needs a new input.
It is a pointer telling an agent where to look before it reports a missing seed.

## What survives a fully-folded chain

### The concrete sequence

`/scope` runs BRIEF → PRD → DESIGN → PLAN and judges each hop against the two documents
that exist (`phase-2-chain-orchestration.md:510+`; there is explicitly "no
durable-artifact floor", `phase-2-chain-orchestration.md:729+`). Maximal fold: BRIEF
absorbed into PRD, PRD into DESIGN, DESIGN into PLAN. Only the PLAN reaches Phase 3.
`/execute` then **adopts the `docs/<topic>` scoping PR as its home PR** — no second PR
is opened, the run stays on that settled branch (`skills/execute/SKILL.md:213-223`).
At `plan_completion` the cascade runs: `shirabe finalize-chain` walks the upstream chain
(nothing to walk), the PLAN flips Active → Done, `git rm -f` deletes it, everything is
committed as `chore(cascade): post-implementation artifact transitions`
(`run-cascade.sh:885`), and the whole branch is squash-merged.

**A file created and deleted inside one branch appears in neither endpoint of the
squash.** So for a fully-folded chain with no ROADMAP, the merge commit's diff contains
**zero changes under `docs/`**. Surviving path patterns naming the topic on the default
branch: none. What survives is the code the implementation issues produced, plus the
squash commit's title and Part 1 body.

I verified the branch-erasure claim empirically against the repository's only real fold
(`#316`, commit `39b0981`): the squash commit body — 73 lines — mentions "absorb",
"fold" and "folds" only as *subject matter of the change*, and contains no
`BRIEF-scope-chain-mandatory-steps` string, no absorbed-path line, and no consolidation
record. `git log --grep=<slug>` would not have found it.

### Candidate surfaces

| Candidate surface | Durable on default branch? | In a plain clone? | Exists without a ROADMAP? | What it says |
|---|---|---|---|---|
| **ROADMAP feature's `**Downstream:**` cell** (`run-cascade.sh:459-470`) | Only until the roadmap is deleted — `handle_roadmap` calls `handle_roadmap_deletion` as soon as every feature is Done and every referenced issue closed (`run-cascade.sh:474-489`), which `git rm`s the file | Yes, while it exists | **No** — written only when a feature's `Downstream:` field references the plan slug; otherwise `update_roadmap_feature` records `skipped` (`run-cascade.sh:403-407`) | Today: `**Downstream:** _none (chain folded; see docs/folds.md)_`. R8/AC12 require the pointer dropped while keeping the folded-vs-never-ran distinction |
| **Merged PR body — Part 2** (reviewer context) | Not on the branch at all; `---` and below is deleted at merge (`references/pr-body-conformance.md:29`). Remains readable on the PR page forever | **No** | Yes | Where `/scope` Phase 3 writes the run's durable record: every artifact in `chain_ran`, every `chain_skipped` entry, and every `consolidation_judgments` entry with verdict, finding, and what was absorbed into what (`phase-3-exit-finalization.md:68-80`, `state-schema.md:234-236`). Richer than a fold row |
| **Merged PR body — Part 1 / the squash commit message** | **Yes** — Part 1 becomes the commit body on `main` (`pr-body-conformance.md:27-28`); verified present in `git log` for `39b0981` | **Yes** | Yes | Free prose describing the change. Nothing binds it to name folded artifacts, and empirically it does not (see `#316` above). PB4 additionally forbids markdown headings in Part 1, so a structured block would have to be prose |
| **Survivor's `absorbed:` frontmatter / `## Status` line / contribution section** | Yes, when a survivor exists | Yes | Yes | The PRD's central carrier (R14) — but by definition absent in the fully-folded case, since the last survivor is the PLAN the cascade deleted |
| **`docs/decisions/DECISION-*.md`** | Yes | Yes | Yes | Written only on `re-evaluation` / `rejection` exits (`phase-3-exit-finalization.md:96-110`). A `full-run` — which is the case here — writes none |
| **`/scope` state file `exit_artifacts:`** | No | No | Yes | Phase 4 removes the state file; its contents are moved into the PR body first. Not an independent surface |
| **Closed GitHub issues** | No (forge) | No | Yes | Only exists for `multi-pr` / `coordinated` plans. A single-pr PLAN is self-contained and files none |
| **The code itself** | Yes | Yes | Yes | R10a's surviving half of the Option D answer: the record of *why* lives in the code as a standing `/work-on` instruction. It records that work happened, never that a document was folded, and it is absent for a docs-only chain |
| **Cascade commit `chore(cascade): post-implementation artifact transitions`** | No — squashed away with the rest of the branch | No | Yes | Generic; names no topic even before the squash |

### One unverified link, load-bearing for the PR-body options

`/scope` Phase 3 writes the consolidation record into "the run's pull-request body"
(`phase-3-exit-finalization.md:73`) and **does not say which part**. `/execute` then
adopts that same PR and, at `pr_finalization`, "assemble[s] the template-conformant PR
(title + two-part body)" (`skills/execute/SKILL.md:232`). I searched
`skills/execute/SKILL.md` for any clause preserving, merging, or reading the existing
body — there is none. So on the current corpus it is undetermined whether `/scope`'s
record survives `/execute`'s body re-authoring, and undetermined whether it lands above
or below the separator (i.e. whether it reaches `main` at all). Any option that names
the PR body as the evidence surface is either asserting something the corpus does not
guarantee, or is implicitly adding a binding on `/execute` — which is arguably past R8's
"replace the prose claim" scope.

## Options

### Option A — Name the merged pull request as the evidence surface

**The rule as it would be written:**

> Distinguishing it from a chain that never ran is not something the tree can do: both
> leave nothing under `docs/`. The evidence is the **merged pull request for the topic**
> — the same PR, since `/execute` adopts `/scope`'s scoping PR as its home PR rather
> than opening a second one. Its body carries the run's consolidation judgments: which
> hops folded, on what verdict, and what was absorbed into what. Find it with
> `gh pr list --state merged --search "<topic> in:title"`. A chain that never ran has no
> such PR. Where the forge is unreachable — a plain clone, an air-gapped checkout, a
> repository with no PR history — the reader observes nothing naming the topic at all,
> and the correct reading is still completion, not a missing seed.

**Consults:** the merged PR body (forge metadata).
**Observes when absent:** nothing; treat the chain as complete.

**Pros.** The record genuinely exists and is strictly richer than a fold row — per-hop
verdicts, findings, and carry tables rather than one line. It is written by machinery
that already runs, requiring no new write. One lookup covers both scope and execution
because the PR is shared. `gh` is already a declared host prerequisite of both skills,
so the dependency is not new.

**Cons.** Forge-only: invisible in a plain clone, which cuts directly against the PRD's
own fairness argument about adopting repositories being asked only for what they can
satisfy. Worse, the link is unverified (see above): if `/scope` wrote the record below
the `---` it never reaches `main`, and if `/execute` re-authors the body wholesale it may
not survive to the merge at all. Naming it would either need the design to bind
`/execute` to preserve it, or accept pointing an agent at something that might not be
there.

### Option B — Name the ROADMAP feature's downstream cell

**The rule as it would be written:**

> Distinguishing it from a chain that never ran depends on where the chain came from.
> A chain seeded by a ROADMAP feature leaves that feature's `**Downstream:**` cell
> rewritten by the finalization cascade: it reads `_none (chain folded)_` for a chain
> that folded to nothing, and names a surviving DESIGN for one that did not. A feature
> that was never planned against keeps whatever it said before. That cell is the only
> in-tree signal, and it is narrower than it looks — a chain that entered without a
> ROADMAP feature never had one, and the same cascade deletes the ROADMAP once every
> feature on it is Done and every issue it references is closed. When there is no cell
> to read, the reader observes nothing under `docs/` naming the topic, and that is
> completion, not a missing seed.

**Consults:** `docs/roadmaps/ROADMAP-<name>.md`, the seeding feature's `Downstream:` cell.
**Observes when absent:** nothing under `docs/`; treat as complete.

**Pros.** In-tree and in a plain clone. It is the exact sibling of the replacement R8/AC12
already mandates for the cell's own text, so the two prose sites say one thing instead of
two. It cites something the cascade writes today, verified at `run-cascade.sh:459-470`.

**Cons.** The narrowest surface by a wide margin, and self-deleting: `handle_roadmap`
calls `handle_roadmap_deletion` in the same run when this was the last feature
(`run-cascade.sh:474-489`), so for a single-feature roadmap the cell can be created and
destroyed inside the same cascade. Naming a file the same script deletes as "the artifact
a reader consults" is honest only if the absent case is stated prominently — which
AC11 forces anyway, so the option is at least self-consistent. It also says nothing about
*what* folded into what, only that something did.

### Option C — Assert nothing; state the indistinguishability and that both readings are the same

**The rule as it would be written:**

> There is nothing to seed on, and nothing distinguishes this from a chain that never
> ran: both leave the same tree. This rule does not pretend otherwise. What matters is
> that the correct behavior is identical in both cases — ready-posture
> `--lifecycle-chain` has no document to fail, so an agent reports neither `L05` nor a
> missing seed and treats the chain as complete. That is also what CI already does: the
> whole-tree `--lifecycle . --mode=ready` scan passes a chain that left nothing, without
> asking whether one ran. A reader who needs to know which happened looks off the default
> branch, at the merged pull request for the topic; a reader without forge access cannot
> answer the question, and treats the chain as complete.

**Consults:** the guard's own exit code first; the merged PR as the named off-branch signal.
**Observes when absent:** the two cases are the same on disk; complete either way.

**Pros.** The only option whose every claim is true on today's corpus without new
machinery. It matches what the lifecycle validator and the CI wiring already do
behaviorally, so the prose stops overstating the mechanism. It is the most actionable
form for an agent, because it states the decision (`treat as complete`) rather than a
lookup whose result the agent then has to interpret. It also honestly reproduces the
PRD's Known Limitations rather than papering over them.

**Cons.** AC11 requires the passage to "name a concrete artifact or signal a reader
consults" — this option names one (the merged PR) but demotes it to a secondary, and a
strict AC11 reading could find that thin. It also risks reading as a shrug to a future
contributor, which is precisely the re-proposal risk R11's DESIGN exists to absorb; the
passage should probably point at that DESIGN so the shrug is backed by an argument.

### Option D — Layered evidence, ordered by durability, with an explicit floor (hybrid)

**The rule as it would be written:**

> There is no anchor to seed on, and no single artifact settles it. In descending order
> of durability, a reader consults: the seeding ROADMAP feature's `**Downstream:**` cell,
> which the cascade rewrites to `_none (chain folded)_` — present only for a
> roadmap-seeded chain, and only until the cascade deletes the ROADMAP; then the merged
> pull request for the topic, whose body records which hops folded and what was absorbed
> into what — the same PR, since `/execute` adopts `/scope`'s. Where the chain had no
> ROADMAP feature and the forge is out of reach, nothing on the default branch names the
> topic: a chain that folded every artifact away and a chain that never ran leave the
> same tree. In that case the reader observes nothing, and the correct reading is
> completion, not a missing seed. `docs/designs/current/DESIGN-fold-record-removal.md`
> records why no central ledger closes this gap.

**Consults:** the ROADMAP cell, then the merged PR.
**Observes when absent:** nothing on the default branch; treat as complete; the reasoning
is in the removal DESIGN.

**Pros.** Satisfies all three AC11 clauses without strain: no record cited, two concrete
surfaces named, and the absent observation stated in the same passage. Keeps `/execute`'s
prose and the cell's own replacement text (R8's first two bullets, AC11 and AC12)
mutually consistent. Ordering by durability tells an agent what to try first instead of
handing it an unordered set. The pointer to the removal DESIGN discharges the re-proposal
risk that Option C leaves open.

**Cons.** By far the longest — a three-rung ladder replacing one sentence, in a skill file
already dense. It inherits Option A's unverified PR-body link, and hedging that inline
("where `/execute` has not re-authored it") would be unreadable; the design would have to
either bind the preservation or accept the imprecision. Two of the three rungs are
conditional, which is arguably more machinery than a rule nothing gates deserves.

### Option E — Name the squash commit / `git log` (considered and weak)

**The rule as it would be written:** "...consult the default branch's history for the
topic: `git log --grep=<topic>`; the chain's whole branch landed as one squash commit
whose Part 1 body describes the change. A chain that never ran left no commit."

**Consults:** `git log` on the default branch.
**Observes when absent:** no commit; but see below — absence is not informative.

I include this because the brief named it, and because it is the only candidate that is
both on the default branch and unconditional. It fails on verification: nothing binds
Part 1 to name the topic slug or the folded artifacts, PB4 forbids the heading structure a
machine-written block would use, and the one real case falsifies it —
`git log -1 --format=%B 39b0981` contains no reference to the artifact that was absorbed,
so `git log --grep` against that chain's slug returns nothing even though the chain ran
and folded. Making this work would mean adding a requirement on `/work-on`/`/execute` PR
authoring, which is new machinery of exactly the kind the PRD is removing. Listed for
completeness, not as a live candidate.

## The residual

**No option eliminates it. Every one of them narrows it, and Option C narrows it by
zero — it just describes it accurately.**

The residual is structural, not a gap in surface choice. It follows from three facts that
none of these options touch: (1) `/scope` has no durable-artifact floor, so a chain can
fold to a PLAN; (2) the cascade `git rm`s the PLAN; (3) the org squash-merges, so a file
created and deleted inside one branch never appears in either endpoint. Given those,
*any* on-branch carrier must be a file the chain wrote **outside** its own fold set —
which is exactly what `docs/folds.md` was, and exactly what R1 removes. An option that
claimed to eliminate the residual would have to reintroduce that shape under another name.

What each option actually buys:

- **Option B** narrows it to chains with no ROADMAP feature — and, because the same
  cascade deletes the roadmap once its last feature closes, further narrows to a window
  rather than a permanent record. The PRD states this precisely in Known Limitations and
  under Decisions and Trade-offs; my reading of `run-cascade.sh` confirms it, and the
  single-feature-roadmap case is sharper than the PRD's wording suggests (created and
  destroyed in one cascade run).
- **Option A** narrows it to readers without forge access — a much larger narrowing in
  practice, but it moves the evidence off the artifact the repository controls, and rests
  on a link the corpus does not currently guarantee.
- **Option D** narrows it to the intersection: no ROADMAP feature *and* no forge access.
  Smallest residual of the four, at the cost of the most prose and the same unverified
  link.
- **Option C** narrows nothing and says so.

The PRD's Known Limitations claim — "Where a chain folds down to a single surviving
artifact and the implementation cascade later deletes it, nothing on the default branch
records that the chain ran" — is correct as written, and correct in the strong sense:
I could not find any on-branch surface that survives, and the empirical check against
`#316` closes the one plausible escape (the squash commit body).

## Recommendation input

Four things the design should weigh.

**AC11's third clause is the binding constraint, and it is cheap to satisfy in every
option.** All four candidates state the absent case in the same passage — that is forced
by the criterion. So AC11 does not discriminate between them, and the design should not
pretend it does. What discriminates is whether the named surface is one the repository
controls and can be verified to exist.

**The consumer is a human, and the passage says so today.** The current text already
concedes "nothing here reads it to make a lifecycle decision." An agent reaching this
bullet has already decided what to do — treat the chain as complete — before it consults
anything. Whatever replaces the record is a courtesy pointer for an investigator, not an
input to the guard. That argues for weighting brevity and truthfulness over coverage, and
against a three-rung ladder in a skill file where every line competes for an agent's
attention.

**The PR-body link needs resolving before Option A or D can be written honestly.**
`/scope` Phase 3 writes the record into an unspecified part of the body; Part 2 is deleted
at merge; `/execute` re-authors the body at `pr_finalization` with no preservation clause.
The design should either establish that the record survives (and where), or avoid naming
the PR body as the primary surface. If the design does want Option A or D, the minimal
honest fix is to have `/scope` Phase 3 name Part 1 explicitly and `/execute` preserve
it — which is a real change to two skills, beyond "replace the prose claim," and should
be a conscious call rather than a side effect.

**Option B is already half-decided by AC12.** The roadmap cell's own text must change
regardless, and it must keep the folded-versus-never-ran distinction. If `/execute`'s rule
names a different surface than the cell does, the corpus carries two answers to one
question — which is the failure mode R8 exists to prevent. Whatever the design picks for
D1, it should pick the same thing for the cell, or state why the two sites legitimately
differ.

Cross-cutting note: whichever option is chosen, the passage should point at
`docs/designs/current/DESIGN-fold-record-removal.md`. The residual is real and accepted;
a reader who finds an honest "nothing records this" with no adjacent reasoning is exactly
the reader R11 was written for.
