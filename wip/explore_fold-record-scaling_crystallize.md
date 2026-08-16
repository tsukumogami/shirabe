# Crystallize Decision: fold-record-scaling

## Chosen Type

Design Doc

## Rationale

The direction is settled — remove `docs/folds.md` — so this is not a
requirements question. What remains is entirely a set of coupled technical
decisions about *how* the removal lands without leaving the corpus asserting
things that are no longer true.

Four of those decisions are genuinely open and interact with each other:

1. **What answers Decision 8's objection.**
   `DESIGN-scope-consolidation-over-skipping.md:838-846` rejected making DESIGN
   absorbable into PLAN because it "trades a durable audit trail for a shorter
   run," then recorded that the objection was "answered rather than overruled" —
   and the answer was this record. Removing the record withdraws the answer while
   the decision it rescued stays shipped. The amendment has to say something
   substantive, and what it says is a design decision.
2. **What `/execute` says instead.** `skills/execute/SKILL.md:596-600` names the
   record as how a reader tells a fully-folded chain from an unfinalized one.
   Either the survivor's accumulated `absorbed:` declaration is deemed sufficient
   (it is, right up until the cascade deletes the PLAN), or the cascade's existing
   ROADMAP marker at `run-cascade.sh:465` is promoted to carry that weight, or the
   question is declared not worth answering.
3. **The disposition of the CI step and the merge driver.** The whole
   `Verify the fold record` step deletes with the record. `merge=union` becomes
   inert — but the findings showed it makes a false promise in three documents and
   does not work server-side on GitHub anyway, so whether to remove the attribute
   or keep it silent is a live call with a precedent (Kubernetes removed theirs).
4. **What R20 is amended to.** `PRD-scope-artifact-persistence.md` is at `Done`
   and `prd/v1` has no `Superseded` status, so amendment-in-place is the only
   mechanism the toolchain offers. Whether R20 is struck entirely or narrowed to
   R21's survivor-side trace changes what the remaining checks must enforce.

Beyond the open decisions, the exploration itself **made** decisions that must
survive the branch. Eight carrier alternatives were evaluated with empirical
evidence — git notes verified not fetched by `git clone`, commit trailers verified
unverifiable pre-merge, union merge verified to deduplicate identical rows and to
preserve no row order, per-fold files identified as structurally conflict-free.
Without a durable home, the next contributor who notices that folds leave no trace
re-proposes a fold log and re-runs this entire investigation. `wip/` is cleaned
before merge, so these findings are lost by default.

## Signal Evidence

### Signals Present

- **Technical decisions need to be made between approaches**: eight carrier
  options were compared (nothing, survivor frontmatter, commit trailer, git notes,
  per-chain file, PR metadata, rotation, per-fold file) with a cost table.
- **Exploration surfaced multiple viable implementation paths**: per-fold files
  scored structurally strongest on every axis except readability and were ruled
  out by the author's direction rather than on their merits — exactly the kind of
  near-miss that needs recording.
- **Architectural decisions were made during exploration that should be on
  record**: the elimination reasoning for all eight carriers, the measurement that
  growth costs ~1% of what a fold reclaims, and the finding that `absorbed:`
  accumulates transitively (which falsifies the original design's stated reason
  for choosing a shared file).
- **Architecture and integration questions remain**: the four coupled decisions
  above, spanning `/scope`, `/execute`, the reusable CI workflow, and four
  terminal documents.
- **The core question is "how should we build this?"**: the *whether* is
  answered; every remaining question is mechanism.

### Anti-Signals Checked

- *What to build is still unclear*: **not present**. The author selected removal
  from four costed options.
- *No meaningful technical risk or trade-offs*: **not present**. Removal reopens a
  settled design decision and changes a reusable workflow that three external
  repositories pin.
- *Problem is operational, not architectural*: **not present**. The four CI
  defects are operational, but they are evidence rather than the subject; the
  subject is which durable carrier holds a guarantee, which is architectural.

## Alternatives Considered

- **Decision Record** — the closest runner-up, and a genuinely defensible choice.
  It matches "a single decision with clear options was evaluated," "which option
  and why," and "future contributors need to understand why." It ranked below
  Design Doc on the anti-signal *multiple interrelated decisions need a design
  doc*: there are four coupled decisions here, not one, and three of them touch
  different skills. If the author prefers a lighter artifact, this is the option
  to take.
- **Plan** — an upstream artifact arguably exists (`DESIGN-scope-artifact-persistence.md`
  covers the record), but it *mandates* the record rather than covering its
  removal, and the Decision 8 answer is an open architectural question. Demoted on
  the anti-signal *open architectural decisions need to be made first*.
- **No Artifact** — demoted hard on two anti-signals: *others need documentation
  to build from* (three adopter repos pin the affected workflow) and *architectural
  decisions were made during exploration*. The eight-carrier elimination reasoning
  would be lost with `wip/`, and the re-proposal risk is high precisely because the
  original decision was never argued.
- **PRD** — the requirement question is not open; R20 exists and is being amended.
  Scored low with the anti-signal *requirements were provided as input*.
- **Rejection Record** — near-fit in spirit (it would durably record "do not
  re-add a fold log"), but the type is built for rejecting a proposed feature on
  demand-validation evidence, not for retiring a shipped mechanism. The
  re-proposal-risk signal it matches is better served by the Design Doc's
  Considered Options section.
- **VISION, Roadmap, Spike Report** — no signals. Not a project-inception,
  multi-feature-sequencing, or feasibility question.
- **Competitive Analysis** — disqualified outright; the repo is public and the
  type is private-only.

## Deferred Types

None scored. Prototype is not applicable — nothing here needs a proof of concept.
