# Lead: What did the original design consider and reject before choosing a shared append-only file, and were the growth and concurrency concerns evaluated at the time?

## Findings

### 1. The requirement being discharged

The requirement is **not** in `PRD-scope-consolidation-over-skipping.md`. That
PRD's line 414 is an *Amendment* section added on 2026-08-15 that points forward
to the successor. The record's actual requirement lives in
`docs/prds/PRD-scope-artifact-persistence.md`.

**The weaker, original requirement** (`docs/prds/PRD-scope-consolidation-over-skipping.md:189-191`):

> **R13.** `/scope` SHALL record, for each hop, which artifacts were produced,
> which were absorbed, into what, and the finding the verdict rested on. The
> record SHALL survive into the run's durable output, not only into `wip/`.

and its acceptance criterion (`:271-273`):

> - [ ] AC17. The run's durable output names every artifact produced and every
>   artifact absorbed, so a reviewer reading only the PR can tell the
>   difference between "not produced" and "absorbed."

That is precisely the "distinguishable" formulation, and it was satisfied by the
run's PR-facing output, not by a file. No shared log was implied by it.

**What broke it** (`docs/prds/PRD-scope-consolidation-over-skipping.md:400-406`,
the 2026-08-15 amendment):

> **"The commit history is the recovery path" is false as written.** Out of
> Scope stated that an absorbed document remains recoverable from history. That
> holds only while the feature branch lives. This repository squash-merges and
> deletes branches, so a document created and folded away inside one chain never
> existed on the default branch at all — and when `/execute` adopts the scoping
> PR, the same is true of the PLAN.

**The strengthened requirement** (`docs/prds/PRD-scope-artifact-persistence.md:241-244`):

> **R20.** A fold SHALL NOT land unless a record was written to the default branch
> naming what folded into what, on what verdict, with the per-contribution carry
> result and a content hash of the pre-fold original. The record SHALL be produced
> mechanically and SHALL NOT carry the absorbed document's contributions.

And the gloss immediately after (`:246-255`), which is the load-bearing part:

> "Written to the default branch" means the record **remains** on the default
> branch — present in a checkout, greppable — not merely that it was written to
> some commit later removed. The terminal fold decides this: a record carried in
> the PLAN reaches `main` and is then deleted by the implementation cascade, so
> under the weaker reading the one fold that leaves nothing else behind also
> leaves no record of itself. That is the case the record exists for. It also
> follows from the beneficiary R21 names: a reader holding a dead path who greps
> for it needs the record in the working tree, not in history they have no reason
> to search.

**So the gap the lead asked about is real and is one requirement wide.** R20 says
"record every fold," in a location that survives on the default branch, keyed by
a content hash. That is strictly stronger than "distinguishable." Two distinct
motivations are fused inside R20:

1. **The terminal-fold case** — a DESIGN-to-PLAN fold where the PLAN is later
   deleted by the cascade, so no survivor exists to carry the trace. This is the
   case that genuinely forces a destination outside the chain documents.
2. **The dead-path grep case** — a reader holding a path from some third
   document, wanting to know whether the target was absorbed or never existed.
   This is the "distinguishable" requirement, and it is *also* served by R21's
   survivor-side trace at every hop that has a survivor.

R21 (`docs/prds/PRD-scope-artifact-persistence.md:256-262`) already mandates the
survivor-side carrier:

> **R21.** A surviving document SHALL record what it absorbed in both a
> machine-readable frontmatter field and one line in its `## Status` section
> naming the absorbed artifact and which contribution section now carries it.

**Crucially, the decision to have a durable record at all was fixed at BRIEF
altitude, not at DESIGN altitude.** `docs/briefs/BRIEF-scope-artifact-persistence.md:140-142`
puts it directly in the In-scope list:

> - A durable record, on the default branch, of what folded into what and on what
>   verdict.
> - A trace on the surviving document recording what it absorbed.

Both carriers were in scope from the framing step. Nothing downstream ever
re-asked whether the durable record earned its place; only *which surface*
carried it was left open.

### 2. Alternatives weighed

The PRD explicitly deferred the surface question
(`docs/prds/PRD-scope-artifact-persistence.md:628-632`, Open Questions):

> - What surface carries R20's record? A single shared append-only index is the
>   leading candidate because it is not a per-run artifact and so cannot read as a
>   floor, but a survivor's frontmatter serves the one hop that has a survivor, and
>   there are three deletion sites rather than one. The criteria for R20, and the
>   surface named in the failure findings of R14 and R15, all inherit this answer.

The DESIGN answered it. `docs/designs/current/DESIGN-scope-artifact-persistence.md:164-173`,
under Considered Options, is the whole surviving record of the alternatives:

> **What surface carries the fold record.** *The survivor's frontmatter*, alone or
> hybridized with an index, is genuinely immune to the cross-hop citation problem
> and was the closest loser. It fails because the record dies with the document at
> the next hop, and because the terminal fold has no survivor at all — so a hybrid
> builds the index anyway and is therefore the index plus a second producer, format
> and reader location for one requirement. *The PR body's durable half* was not
> killed by the three obvious objections, which its advocate explicitly declined to
> kill it on, but by fidelity: byte-comparing five real merged PRs, one silently
> lost 184 of 622 bytes through the human-editable merge dialog, and the lost
> paragraph was a tree-state attestation — exactly this record's genre.

So the named-and-rejected destinations are exactly three:

| Destination | Why rejected |
|---|---|
| Survivor's frontmatter (alone) | Dies with the document at the next hop; terminal fold has no survivor |
| Survivor's frontmatter + index (hybrid) | Builds the index anyway, so it is the index plus a second producer/format/reader location |
| PR body's durable half | Measured fidelity failure: 1 of 5 sampled merged PRs silently lost 184/622 bytes through the merge dialog, and the lost text was a tree-state attestation |

The design's frontmatter `rationale:` (`:22-27`) states the general disqualifier:

> Every other placement of the record was disqualified by the ruling that it must
> persist on the default branch, because this repository merges a whole chain as
> one squash and any record living inside a chain document leaves with it.

**On the "any destination preserving absorbed content" argument.** The full text
is `docs/prds/PRD-scope-artifact-persistence.md:549-556`:

> **A durable record of the operation, not of the distillate.** Any destination
> preserving the absorbed content must assert, every time it fires, that the
> verdict was partly wrong, since the fold's meaning is that the content did not
> warrant a durable artifact. That argument closes the whole class, including an
> archive directory and a per-run decision record. A record that a judgment
> happened, about what, with what carried, asserts nothing the fold denies. It is
> written mechanically because an agent-authored record inserts another
> unverifiable content judgment at the moment of maximum consequence.

Restated more tersely in the DESIGN at `:326-328`:

> The record is of the operation, never the distillate. Any destination preserving
> absorbed content must assert, every time it fires, that the verdict was partly
> wrong.

**This argument is about the content only.** Read literally, it eliminates
destinations that *preserve the absorbed document's prose* — an archive
directory, a per-run decision record that quotes the folded text. It says nothing
against a non-log carrier of the *operation*. It does not rule out a frontmatter
key, a git note, a commit trailer, a tag, or a per-fold stub carrying only "what
folded into what on what verdict." The design does not claim it does; the
content argument and the surface argument are kept separate, and the surface
question is decided on the persist-on-default-branch ruling instead. So the
question "could the fold *operation* live somewhere other than a shared log" was
answered against exactly three candidates, and the class-closing argument does
not extend to it.

One rejected relative is worth naming: a **tombstone stub** was rejected, but for
a corpus-size reason rather than the content reason
(`docs/prds/PRD-scope-artifact-persistence.md:563-566`):

> A tombstone stub was stronger on the merits and was rejected because it leaves
> one durable file per fold in the corpus that motivated this work.

That is the *only* place in the whole chain where the volume of folds enters the
reasoning — and it argues that per-fold durable output is a cost. The shared log
was then chosen without applying the same lens to itself.

### 3. Were growth, context cost, or merge contention raised?

**Merge contention: yes, explicitly, and it is the residual the design flags.**
`docs/designs/current/DESIGN-scope-artifact-persistence.md:330-336`:

> `docs/folds.md` is this repository's **first** shared append-only durable file and
> its merge driver is the repository's first. There is no precedent to inherit, and
> union-merge resolves a concurrent duplicate row silently rather than raising a
> conflict. Rows are keyed by the pre-fold blob hash, so a cross-branch duplicate is
> a duplicate of an identical fact, and the checker flags it — but this is a
> residual, not a solved problem, and it is the one genuinely new mechanism in this
> design.

Repeated in Consequences (`:682-685`) as "Negative, and accepted": "The record
file is a new mechanism with no precedent in this repository and a silent
duplicate-row case under union merge." So the concurrency shape that *was*
considered is: two branches append, union merge keeps both, duplicates are
possible, duplicates of an identical fact are harmless, checker flags them. Merge
*conflict* was designed away with `merge=union`. The `.gitattributes` comment says
the same:

> The fold record is append-only and written by /scope's consolidation
> judgment, so two branches each recording a fold would otherwise conflict on
> every concurrent chain. Union merge keeps both rows.

**File growth: no. Not discussed anywhere.** I grepped
`DESIGN-scope-artifact-persistence.md`, `PRD-scope-artifact-persistence.md`, and
`BRIEF-scope-artifact-persistence.md` for `grow|growth|unbounded|thousands|file
size|context cost|context budget|scale|scaling|rotat|prune|archiv|contention`.
Three hits total, none about the record:

- `BRIEF-scope-artifact-persistence.md:59` — "the corpus grows monotonically",
  about the *document corpus*, which is the problem the feature exists to fix.
- `PRD-scope-artifact-persistence.md:483` — "archive rather than deletion as its
  disposal", about a different mechanism.
- `PRD-scope-artifact-persistence.md:553` — the archive-directory rejection
  quoted above.

There is no row-count estimate, no expected fold rate, no size ceiling, no
rotation or pruning plan, no discussion of what the file costs an agent that
reads it, and no statement that unbounded growth was considered and accepted. The
Known Limitations sections of both the PRD (eight entries) and the DESIGN
(Consequences, five paragraphs) are unusually thorough about every other residual
— gaming vectors, ungradeable judgments, unverified cross-repo halves, a 3-2
contested vote — and growth appears in none of them. **This reads as not reached
rather than considered-and-accepted.**

**Context cost: no.** Nothing reads `docs/folds.md` into an agent's context
today. Its current consumers are: the reusable CI workflow (which `git show`s it
and greps), `skills/scope/scripts/check-citations.sh` (which *excludes* it from
the citation search, `:56` and `:69`), and prose pointers in
`skills/execute/SKILL.md:597-600` and
`skills/execute/scripts/run-cascade.sh:465`. `/execute` is explicit that it does
not read it: "The record is the evidence; it is not a seed, and nothing here
reads it to make a lifecycle decision." So the context-cost question was never
posed because no reader path exists yet.

**The record is currently empty.** `docs/folds.md` is 63 lines, all header and
column documentation; the Record table at line 62-63 has a header row and no data
rows. Zero folds have been recorded.

### 4. Git and PR history

Everything landed in **one commit, one PR**.

- `83d29e1` — `feat(scope): decide absorbability from the documents, not the types (#302)`.
  This single squash commit introduced `docs/folds.md`, the `docs/folds.md
  merge=union` line in `.gitattributes`, the "Verify the fold record" step in
  `.github/workflows/validate-docs.yml`, and both the PRD and DESIGN for this
  feature. Merged 2026-08-15T19:34:58Z. 34 files, +3886/-209.
- `.gitattributes` has exactly one prior commit, `414ecf9` (`ci: adopt koto
  template freshness checks (#27)`), which created the file with the
  `*.mermaid.md text eol=lf` line. Unrelated.

`gh pr view 302 --json comments,reviews` returns **zero comments and zero
reviews**. The PR was authored and merged by the same person with no review
discussion, so there are no reviewer objections and no accepted trade-offs
recorded there. The PR body is substantial and self-reviewing — it names four
"known limitations, stated rather than discovered" — but none concerns the record
file's growth.

The commit message describes the record in one clause: "every completed fold
appends a mechanically-written row to `docs/folds.md` before anything is
deleted." No justification beyond that.

**The decision reports are gone.** `DESIGN-scope-artifact-persistence.md:38-45`
says so explicitly:

> Six decision questions were evaluated before this document was written; two ran
> the full adversarial path with five persistent validators each, and all six were
> decided in `--auto` mode without author confirmation. Their reports were working
> artifacts and do not survive this chain; the reasoning that survived them is
> carried in Considered Options and Decision Outcome below[.]

So the full alternative set for "what surface carries the fold record" — which the
design says each report carried — is not recoverable. The three sentences quoted
in section 2 above are the complete surviving record. Note also that all six
decisions were made **in `--auto` mode without author confirmation**: no human
signed off on the shared-log choice at decision time.

### 5. Design status

| Document | Status | Terminal? |
|---|---|---|
| `docs/briefs/BRIEF-scope-artifact-persistence.md` | `Done` | Yes (brief/v1: Draft, Accepted, Done) |
| `docs/prds/PRD-scope-artifact-persistence.md` | `Done` | Yes (prd/v1: Draft, Accepted, Done) |
| `docs/designs/current/DESIGN-scope-artifact-persistence.md` | `Current` | Effectively — next state is `Superseded` |
| `docs/prds/PRD-scope-consolidation-over-skipping.md` | `Done` | Yes |
| `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` | `Current` | Effectively |

Status vocabularies from `crates/shirabe-validate/src/formats.rs:271` (prd/v1:
Draft, Accepted, Done) and `:302` (design/v1: Proposed, Accepted, Planned,
Current, Superseded).

**But amendment-in-place is the established precedent here, and it does not
require a lifecycle move.** The immediately preceding chain was amended exactly
this way, three months of process notwithstanding: `PRD-scope-consolidation-over-
skipping.md:394` gained a `## Amendment — 2026-08-15` section while staying at
`Done`, and `DESIGN-scope-consolidation-over-skipping.md:822` gained one while
staying at `Current`. Both amendments say "The original text above is left
unedited; this section records what no longer holds." The consolidation DESIGN's
amendment goes as far as declaring a shipped decision *falsified* and adopting
the option it had rejected — all without a status transition.

The heavier route exists: `shirabe transition` takes `--superseded-by` for a
design supersession (`crates/shirabe/src/main.rs:133-135`). Supersession was
itself weighed for the previous chain and rejected
(`DESIGN-scope-artifact-persistence.md:199-203`):

> *Superseding them* via the lifecycle overcorrects, discarding real unaffected
> content across a document whose other decisions are sound.

So reversing or narrowing the fold-record decision is an **amendment**, not a
supersession, unless it takes the whole design with it. That is a cheap move on
this repo's own precedent, established one day ago by this very chain.

## Implications

**The question "is the log useful at all" was never asked at design altitude.**
The BRIEF put "a durable record, on the default branch, of what folded into what
and on what verdict" in scope, and everything downstream inherited it as a given.
The DESIGN's Considered Options section evaluates *surfaces for a record*, not
*whether a record*. So the exploration should not expect to find a defended
cost/benefit for the log; there isn't one to overturn. What there is, is a
defended argument for one narrow case — the terminal fold, where no survivor
exists — and R21's survivor-side trace already covering every other hop.

**The strongest surviving justification is narrower than the mechanism.** Two
motivations sit inside R20: the terminal fold with no survivor, and the reader
grepping a dead path. The second is fully served by R21 at every hop with a
survivor. If the exploration wants to shrink the log, the terminal-fold case is
the load-bearing one and needs a replacement carrier; the rest is redundant with
the survivor trace.

**The "content" argument does not defend the log's shape.** "Any destination
preserving absorbed content must assert the verdict was partly wrong" closes the
archive-directory and per-run-decision-record class. It has nothing to say about
alternative carriers of the *operation* — git notes, commit trailers, a
frontmatter key, a tombstone stub. Anyone citing that sentence as the reason a
shared log was necessary is over-reading it. The actual surface argument is the
persist-on-default-branch ruling plus the terminal fold's missing survivor.

**Growth is an oversight, not an accepted trade-off — and the exploration can say
so with confidence.** The negative-consequences enumeration in both documents is
long and candid; unbounded row accumulation appears in neither. The one place
volume-of-folds enters the reasoning is the tombstone-stub rejection, which
argues *against* per-fold durable output and was not turned back on the log.

**Reversing or narrowing this is an edit, not a supersession.** The amendment
pattern is established in this exact chain, one day old, and was used to falsify
a shipped decision without a status transition. That makes this a low-ceremony
change on the documents; the mechanical cost sits in the `/scope` phase file,
the CI step, and `.gitattributes`.

**The blast radius is small right now.** Zero rows exist, one day after merge, no
fold has ever executed, and nothing reads the file into agent context. Whatever
convergence decides, the migration cost is approximately zero today and grows
with every fold.

## Surprises

**The record's own decision reports were not preserved.** The DESIGN says the six
decision reports "were working artifacts and do not survive this chain." So the
full alternative set for the record-surface question — the thing this lead was
asked to recover — was itself folded away, and the mechanism designed to make
absorbed artifacts traceable did not exist yet to record its own genesis. Three
sentences in Considered Options are the entire durable trace of that decision.

**All six decisions were made in `--auto` mode without author confirmation.** The
shared-log choice was never human-confirmed at decision time. That is stated
plainly in the design's `## Status`, and it substantially changes what "we decided
this" means for this particular choice.

**No review at all on PR #302.** 34 files, +3886/-209, zero comments, zero
reviews. The PR body is a careful self-review with four stated limitations, but no
second reader ever looked at the record's design.

**The tombstone stub was rejected precisely on a corpus-growth argument** — "it
leaves one durable file per fold in the corpus that motivated this work" — and the
same lens was never turned on the shared log, which leaves one durable *row* per
fold in a file that lives in `docs/` forever. The reasoning to catch the growth
problem was present in the chain and was applied to exactly one candidate.

**`docs/folds.md` needed an explicit carve-out to survive `/scope`'s own
cleanup** (`skills/scope/references/phases/phase-4-cleanup.md:101-110`), because
being enumerated in the write-target set would otherwise make a sweep look
authorized. That is a small sign the file does not sit naturally in any existing
category.

## Open Questions

- What replaces the record for the **terminal fold** (DESIGN-to-PLAN, PLAN later
  deleted by the cascade)? This is the only case R21's survivor trace cannot
  cover, and it is the case R20's gloss says "the record exists for." Any proposal
  to shrink or remove the log needs an answer here. (Overlaps `lead-alternative-carriers`.)
- Was the union-merge duplicate case ever exercised? No fold has run, so the
  merge driver has never fired. Whether `merge=union` behaves as documented under
  the repo's actual squash-merge flow is untested.
- What is the expected fold rate? Nothing in the chain estimates it. Without it,
  "the file grows unboundedly" is directionally true but unquantified.
  (Overlaps `lead-growth-contention`.)
- Does any planned consumer read the file into agent context, or is CI the only
  reader by design? Today CI is the only mechanical reader and `/execute`
  explicitly declines to read it. (Overlaps `lead-consumers`.)
- The additions-only CI assertion is scoped to a PR diff against its base. Does it
  survive a deliberate future compaction (rotation, archival, pruning)? Any
  growth remedy has to reckon with a check that forbids removing rows.

## Summary

The decision to keep a durable fold record was fixed at BRIEF altitude and never
re-examined; the DESIGN only chose among three surfaces for it (survivor
frontmatter, a hybrid, the PR body), rejecting them on a persist-on-the-default-
branch ruling driven by the terminal fold that has no survivor — and the
often-cited "any destination preserving absorbed content asserts the verdict was
partly wrong" argument is about *content*, so it never ruled out non-log carriers
of the operation. Merge contention was considered and consciously accepted as a
residual, but file growth and context cost were never mentioned anywhere in the
BRIEF, PRD, DESIGN, commit message, or PR — and PR #302 has zero reviews, with all
six underlying decisions made in `--auto` mode and their reports not preserved,
so this is an oversight rather than an accepted trade-off. Reversal is an
amendment rather than a supersession on this chain's own one-day-old precedent;
the biggest open question is what carries the terminal fold's record if the shared
log goes away.
