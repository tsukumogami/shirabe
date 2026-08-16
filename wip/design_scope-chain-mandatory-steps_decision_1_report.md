# Decision 1 — What replaces `/explore`'s ten-type crystallize framework

Topic: `scope-chain-mandatory-steps`. Repo root:
`/home/dgazineu/dev/niwaw/tsuku/tsuku+shirabe_inconsistencies-03b57366/public/shirabe/.claude/worktrees/scope-chain`.
All line references are to files as they exist in that worktree.

## Question

`/explore`'s Phase 4 scores ten artifact types against one another in a single
pass, using ten signal/anti-signal tables, a demotion rule, seven pairwise
tiebreakers, six disambiguation rules, and an insufficient-signal fallback
(`skills/explore/references/quality/crystallize-framework.md`). R10 replaces the
outcome set: the router now decides first whether the exploration reached a chain
or one of four terminal outcomes no chain owns, and then, for a chain outcome,
which of four entry points to hand to. The ten per-artifact-type tables go; the
scoring procedure, the demotion rule, the discriminating tiebreakers, and the
fallback stay. What shape do the replacement tables and the procedure around them
take?

The outcome set the router must reach, drawn from R10, R13, and R14:

| Kind | Outcome | Destination | Old type it replaces |
|---|---|---|---|
| Terminal | Competitive analysis | route to `/comp` | Competitive Analysis |
| Terminal | Decision | route to `/decision` | Decision Record |
| Terminal | Spike report | authored by `/explore` | Spike Report |
| Terminal | Rejection record | authored by `/explore` | Rejection Record |
| Entry point | File an issue | author runs `/work-on <N>` | No Artifact (and Prototype) |
| Entry point | `/charter` | `/charter <topic> [--upstream VISION]` | VISION, Roadmap |
| Entry point | `/scope` | `/scope <topic> [--upstream ROADMAP]` | PRD, Design Doc, most of Plan |
| Entry point | `/execute` | `/execute <PLAN path>` | the residue of Plan |

Eight outcomes, not ten, and the collapse is uneven: four of the ten survive
almost intact as terminals, one (No Artifact) is renamed and re-pointed, and five
(PRD, Design Doc, Plan, VISION, Roadmap) are destroyed and their material
redistributed across two entry points. That asymmetry is the shape of the
problem. Three of the five that die — PRD, Design Doc, and most of Plan — collapse
onto a *single* destination, so the signals those tables existed to discriminate
between stop discriminating anything.

## Decision Drivers

**R10 is prescriptive about sequence, not about mechanism.** It says the two
things are scored "in sequence" and that the demotion rule, tiebreakers, and
fallback survive. It does not say whether the sequence is two scoring passes, one
pass over a partitioned set, or a gate followed by a pass. All three alternatives
below satisfy the literal text; the choice is about which one keeps the
framework's guarantees intact.

**No scoring category may name a chain-internal child** (R10, final sentence).
All three options satisfy this trivially, because the outcome set above contains
no `/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, or `/roadmap`.
This is not a discriminator between the options and should not be used as one.

**The framework is a prompt, not code.** An agent reads it top to bottom in
Phase 4 and walks it with accumulated findings in context. Table count matters
less than how many tables get walked per run and whether two questions at
different altitudes end up competing on one scoreboard.

**Two facts in the outcome set are filesystem facts, not judgments.** Whether a
qualifying PLAN exists on disk decides whether `/execute` can receive anything
(R13); whether the repo is public decides whether `/comp` can produce anything
(`skills/comp/SKILL.md`, and the current refusal at
`phase-5-produce-deferred.md:111-126`). Everything else in the set is a judgment
about findings.

**Two facts that look binary are not.** Whether the exploration reached "an active
rejection conclusion (not lead exhaustion — there's positive rejection evidence)"
is the single hardest call in the current framework and gets a five-row signal
table plus a matching anti-signal to keep it apart from No Artifact
(`crystallize-framework.md:76-82`). Whether the exploration's subject was one
choice or a feature is likewise a judgment. Any design that treats these as
predicates loses a guard the current framework earns.

**Migration cost is concentrated, not spread.** Per the eval inventory, eleven
scenarios pin `/explore` routing to a chain-internal child (explore 3, 4, 5, 8,
12, 13, 14; roadmap 7; vision 8; decision 5 — with decision 5 explicitly excluded
by R35), plus explore 15 and 16 which R15/R16 remove with the triage they grade.
Four of the explore scenarios carry `expected_output` only and need assertion
arrays introduced (R39). This cost is roughly constant across the three options;
what varies is how many *new* scenarios each option demands.

**The current framework's real failure mode is cross-altitude contamination.**
"Exploration compared specific alternatives with trade-offs" is a Decision Record
signal (`:130`). "Exploration surfaced multiple viable implementation paths" is a
Design Doc signal (`:45`). Comparing alternatives is what exploration *does*, so
these co-fire constantly, and today they compete directly on one scoreboard where
the margin is noise. Any replacement that keeps them on one board inherits the
defect.

## Considered Options

### A. Two-stage scoring

**How it works.** Phase 4 runs two scoring passes.

Stage 1 scores five categories: the four terminal outcomes plus a fifth,
"a chain". Each gets a signal/anti-signal table. The demotion rule and the
insufficient-signal fallback apply within the stage. If a terminal wins, Phase 4
records it and stops — stage 2 never runs, and Phase 5 routes to the terminal
handler.

Stage 2 runs only when stage 1 returns "a chain". It scores four entry points —
file an issue, `/charter`, `/scope`, `/execute` — with the demotion rule and
tiebreakers applying within the stage. Two preconditions run before the pass and
govern *candidacy* rather than score: `/execute` is a candidate only when a PLAN
exists at `docs/plans/PLAN-*.md` (or any `.md` with `schema: plan/v1`) whose
`execution_mode` is `single-pr` or `coordinated`; `/comp` — a stage-1 candidate —
only in a private repo. A non-candidate is absent from the ranking and absent
from the AskUserQuestion options.

**The tables.** Nine total: five at stage 1, four at stage 2. Four of stage 1's
five come almost verbatim from the current ten. Competitive Analysis
(`:136-141`) keeps its three signals and loses its "Repo is public" anti-signal to
the precondition. Decision Record (`:127-130`) survives unchanged. Spike Report
(`:116-119`) survives unchanged. Rejection Record (`:78-82`) survives unchanged,
including the lead-exhaustion anti-signal that keeps it apart from what is now the
file-an-issue arm. Only the fifth, "a chain", is new — signals along the lines of
*something needs building or changing and the work exceeds answering one
question*, *the exploration produced a scope boundary rather than an answer*,
*decisions were made that a downstream document must carry*; anti-signals *the
conclusion is that nothing should be built*, *the whole subject was one choice
between named options*, *the findings are about external products*.

Stage 2's four are written fresh, but not from nothing. File an issue inherits
most of No Artifact (`:64-70`) — "simple enough to act on directly", "one person
can implement without coordination", "short exploration with high user
confidence" all carry. No Artifact's anti-signals invert into `/scope` signals:
"others need documentation to build from", "multiple people will work on this",
"any architectural, dependency, or structural decisions were made during
exploration". `/scope` also absorbs PRD's "single coherent feature emerged" and
Design Doc's "exploration surfaced multiple viable implementation paths".
`/charter` absorbs VISION's project-doesn't-exist-yet and thesis-validation rows
and Roadmap's multiple-features-need-ordering row. `/execute`'s table is short by
construction, because its precondition carries most of the discrimination: its
signals are about whether the exploration *confirmed* the existing PLAN rather
than invalidating it.

**Survival count from the current ten:** four survive nearly verbatim, one
survives re-pointed and renamed, five are dissolved.

**Tiebreakers.** Four of the seven survive re-pointed, two die, one survives with
an inverted answer, and four new ones are needed. Detail in the Recommendation.

**Demotion rule.** Applies within each stage independently and unchanged in form.
Stage 1 needs "a chain" to carry anti-signals for the rule to be symmetric —
without them, "a chain" can never be demoted below a clean terminal, which would
silently privilege it.

**Insufficient-signal fallback.** Fires at stage 1 in its current form: nothing
scores above 0 after demotion, so the findings cannot say whether anything should
be built at all, and the run returns to Phase 2 with targeted leads. A stage-2
form is also needed, and it should not be the same: by the time stage 1 has
returned "a chain", the exploration has established that something should be
built, and sending the author back to Phase 2 after they already chose to
crystallize is expensive for a question that is coarse. Present all surviving
candidates in the AskUserQuestion with their evidence and let the author pick;
the existing "None of these" option (`phase-4-crystallize.md:151-158`) still
routes back to Phase 2 for the author who wants it.

**What breaks in the eval suite.** The eleven Bucket-C scenarios, as under any
option. Two specific casualties are worth naming: explore 4
(`crystallize-to-design-doc`) and explore 5 (`crystallize-to-prd`) exist to
discriminate PRD from Design Doc, and under any of these options they now assert
the same outcome, making one redundant. Under A they re-purpose cleanly, because
the two stages give two distinct things to grade — 4 becomes `/scope` vs file an
issue, 5 becomes `/scope` vs `/charter`. Explore 3 (`routing-advisor-prd-vs-design`)
loses its premise entirely and has to be rewritten as parent-vs-parent advice or
removed. A also creates a *new* eval requirement the other options do not: stage 1
must be gradeable independently, so at least two scenarios reaching a terminal
without an entry point, plus one where stage 1 returns "a chain" and stage 2 does
the discriminating. Call it three new scenarios.

**Pros.** Each stage asks one question at one altitude, which is exactly the fix
for the contamination driver: "the exploration compared alternatives" counts for
Decision at stage 1 only if comparison was the exploration's *subject*, and never
competes with `/scope`'s implementation-paths signal, because they are never on
the same board. Terminal outcomes stop being four rows buried among ten and get a
pass of their own — R14 keeps them reachable, and this is the shape that makes
"reachable" mean something. Per-run cost drops below today's: five tables then
four, versus ten today, and terminal runs walk five and stop. Four tables survive
nearly verbatim, so the diff is much smaller than "replace ten tables" suggests.
Preconditions make R13's "only when a PLAN already exists" structurally
unviolatable rather than a weight that can be outvoted.

**Cons.** A stage-1 error is unrecoverable at stage 2: if stage 1 wrongly returns
a terminal, the four entry points are never scored and the author is never offered
them. The Phase 4 file grows a control-flow branch. The crystallize artifact
(`wip/explore_<topic>_crystallize.md`) needs a two-part shape so a Phase 5 resume
knows which stage produced the verdict. Three new eval scenarios rather than
zero.

### B. Flat scoring over a combined outcome set

**How it works.** One table set covering all eight outcomes, scored in a single
pass, with the existing four-step procedure at `crystallize-framework.md:159-223`
kept verbatim: score each, rank and demote, apply tiebreakers, fall back if
nothing clears 0. Phase 4's step structure is untouched except for the type list
in 4.3 and the tiebreaker list in 4.5. The two filesystem facts become
anti-signals in the flat set — "no PLAN exists on disk" as an `/execute`
anti-signal, "repo is public" retained as the competitive-analysis anti-signal it
already is.

**The tables.** Eight, all walked every run. Four terminal tables survive as in A.
Four entry-point tables written the same way as in A. The only structural
difference from A is that the fifth stage-1 table ("a chain") does not exist,
because there is no stage to hold it.

**Survival count:** identical to A — four verbatim, one re-pointed, five
dissolved. B and A differ in procedure, not in table content.

**Tiebreakers.** The same four survivors and four new ones as A, plus a fifth new
one A does not need: terminal-vs-entry-point pairs now appear adjacent in the
ranking and need explicit rules. Decision-vs-`/scope` and spike-vs-`/scope` in
particular will tie often, for the contamination reason above. So B needs *more*
tiebreakers than A, not fewer.

**Demotion rule.** Unchanged, one application, zero new machinery. This is B's
genuine advantage and it is not small — the rule is the framework's main guard
against a high-raw-score outcome with a disqualifying counter-indication, and B
inherits it with no adaptation and no risk of getting the adaptation wrong.

**Insufficient-signal fallback.** Unchanged, one application. But B has a real
defect here: flattening eight outcomes onto one board means the broadest category
absorbs vagueness. `/scope`'s signal set is necessarily wide — it covers
everything PRD, Design Doc, and Plan used to cover — so a vague exploration can
score `/scope` at 1 on breadth alone and never reach the fallback. Under A the
same exploration shows up at stage 1 with everything at 0, because stage 1's
question is narrow.

**What breaks in the eval suite.** The same eleven Bucket-C scenarios. B needs no
new scenarios for procedure, since there is one pass to grade; but explore 4 and
5 have nowhere useful to go, because B gives no second thing to grade — both end
up asserting "scores `/scope` highest", and one is redundant on any honest
reading. So B is cheaper in new scenarios and more wasteful in existing ones.

**Pros.** The smallest possible change to the procedure: R10's survival list is
satisfied by doing nothing to the four things it names. One reader path, no
branch, no stage bookkeeping in the crystallize artifact. Nothing new can be got
wrong, because nothing new exists. The ranked output is a single list, which is
exactly what step 4.7's AskUserQuestion wants — recommended type, alternatives,
"None of these" — with no need to decide how to present a two-stage result.

**Cons.** It reproduces the contamination defect at larger scale. Today ten types
compete on one board and PRD-vs-Design-Doc needs a dedicated tiebreaker to
resolve; under B, eight outcomes at two different altitudes compete, and the pairs
that need resolving are worse — Decision-vs-`/scope` is a question about whether
the exploration's *subject* was one choice, which no amount of signal-counting
answers, because the signals co-fire. It also reads badly: an agent walking eight
tables is asked to hold "is this a competitive landscape write-up?" and "should
the tactical parent run?" in the same comparison, and those are not comparable
quantities. And it does not satisfy R10's "in sequence" in spirit — the sequence
becomes a presentational ordering of the table list rather than a property of the
procedure, which a Phase 6 reviewer will notice.

**Where B is genuinely stronger than the recommendation:** if the two stages turn
out to disagree in practice — stage 1 saying terminal where a chain was right —
B has no such failure mode, because every outcome is always in contention. That is
not a hypothetical; it is A's named con.

### C. Gate-then-score

**How it works.** A small set of hard predicates runs first, in a fixed order.
Candidates: does a qualifying PLAN exist on disk? Is the repo public? Is the
exploration's conclusion a rejection? Are the findings about external products?
Each firing gate produces a terminal route directly. Whatever survives the gates
goes to a scored pass over the residual entry points — realistically file an
issue, `/charter`, `/scope` — with the demotion rule, tiebreakers, and fallback
applying only there.

**The tables.** Three or four, plus two to four predicates. This is by far the
smallest surface.

**Survival count:** the four terminal tables mostly *die*, replaced by predicates;
No Artifact survives re-pointed; five dissolve as in A and B. So C destroys more
of the current framework than either alternative, which is worth stating plainly
rather than counting as economy.

**Tiebreakers.** Only the entry-point ones are needed — the four survivors from
the seven, minus the ones that discriminated terminals. Roughly three.

**Demotion rule.** Does not apply to gated outcomes at all. Any outcome behind a
gate is never demoted, which means the rule's guard — a high-raw-score outcome
with a disqualifying counter-indication ranks below a clean low-scorer — is
simply absent for four of the eight outcomes. R10 says the demotion rule
survives; under C it survives for half the outcome set.

**Insufficient-signal fallback.** Reachable only in the residual pass. A run where
a gate fires never reaches it, so an exploration with thin findings that happens
to trip the rejection gate gets routed confidently on evidence the current
framework would have sent back to Phase 2.

**What breaks in the eval suite.** The same eleven, plus a new class: gate
*ordering* becomes gradeable, because "PLAN exists" and "conclusion is a
rejection" can both be true (an exploration that invalidated an existing PLAN),
and which fires first is a behavioral commitment. That is more new eval surface
than A's three scenarios, not less.

**Pros.** The shortest reader path by a wide margin, and it puts the two facts
that genuinely *are* facts — PLAN existence, repo visibility — where facts belong,
ahead of judgment. It is honest about `/execute`: a scored `/execute` signal that
can be outvoted is a router that will eventually hand `/execute` something it
rejects, and C makes that structurally impossible. Both of those insights are
correct and both survive into the recommendation.

**Cons.** Two of its four candidate gates are not predicates. "Is the conclusion
a rejection?" is the judgment the current framework works hardest to get right,
distinguishing an active rejection with citable blockers from leads merely running
out (`crystallize-framework.md:78`) — collapsing it to a gate reintroduces exactly
the error the anti-signal exists to prevent. "Are the findings about external
products?" is similarly a reading of the findings, not a fact about the
repository. So C's economy is bought by demoting two judgments to predicates, and
the two it demotes are the two with the highest cost of error: a wrong rejection
gate writes a permanent `docs/decisions/REJECTED-<topic>.md` and closes an issue.
Gates also produce no ranked alternatives, so step 4.7's AskUserQuestion loses its
alternatives list and the crystallize artifact loses its "Alternatives Considered"
section for gated runs — the author sees a verdict with no visible runner-up.

**Where C is genuinely stronger than the recommendation:** for the two real
predicates it is simply right, and the recommendation adopts that. C's failure is
one of extent, not of kind.

## Recommendation

**Take A — two-stage scoring — with C's predicate insight adopted as candidacy
preconditions rather than as gates.**

The decisive argument is that the two questions R10 asks are not comparable
quantities, and a single scoreboard is a claim that they are. Asking "did this
exploration produce a competitive landscape write-up, a feasibility answer, a
single decision, a rejection, or work?" is a question about what the exploration
*is*. Asking "which parent should receive the work?" is a question about the
work's altitude and what already exists on disk. The current framework's worst
behavior comes from mixing altitudes on one board — comparing alternatives is
what every exploration does, so the Decision Record signal fires on nearly all of
them and competes with Design Doc's on raw counts. B does not fix that; it makes
the board wider. A fixes it by construction, because the alternative-comparison
signal only counts toward Decision if comparison was the exploration's subject,
and at stage 2 it does not appear at all.

The second argument is that A is cheaper per run than what it replaces, which
inverts the obvious objection. Today's procedure walks ten tables every time. A
walks five, and only continues to four more when stage 1 returns a chain — so a
rejection-record run walks five tables and stops, against ten today. Nine tables
exist; nine are never walked in one pass.

The third is that A makes R14 mean something structurally. R14 says four terminal
outcomes stay reachable. Under B they stay reachable in the sense that they are
four rows out of eight competing against four entry points whose signals are
broader. Under A they get their own pass, and the question of whether the
exploration reached one of them is asked before anything else — which is the
sequence R10 describes and the only reading under which "reached a chain at all"
is a real question rather than a default.

On the preconditions: C is right that `/execute` must not be reachable by score.
R13 says the arm is reachable "only when a PLAN already exists", and "only when"
is a precondition, not a weight — a scored `/execute` signal loses to a two-point
`/scope` margin, and the router hands `/execute` a topic it cannot parse. But C
generalizes the insight past where it holds. The fix is to let preconditions
govern *candidacy* and leave selection to scoring: a qualifying PLAN's existence
makes `/execute` a candidate, and stage 2 then decides between `/execute` and
`/scope`, because a PLAN existing does not mean the exploration concluded "run
it" — an exploration that invalidated the PLAN's assumptions routes to `/scope`.
Two preconditions qualify and no more: a PLAN at `docs/plans/PLAN-*.md` or any
`.md` with `schema: plan/v1` whose `execution_mode` is `single-pr` or
`coordinated` (a `multi-pr` PLAN is explicitly out of scope for `/execute`,
`skills/execute/SKILL.md:35-45`), and repo visibility for `/comp`. Both are
`ls`-and-read facts. Neither rejection-vs-exhaustion nor
findings-are-about-external-products qualifies, and both stay scored.

Moving the competitive-analysis visibility check from anti-signal to precondition
also fixes a live UX defect rather than just relocating a check: today a public
repo can score Competitive Analysis highest, present it to the author as the
recommendation, and then refuse at produce time
(`phase-5-produce-deferred.md:111-126`). As a precondition it never becomes a
candidate and never gets offered.

### The four terminal outcomes get signal tables (Q1)

Yes, at stage 1, and four of them come nearly verbatim from the current ten. This
is the answer even though terminals are not entry points, because each of the four
is a judgment call with a real error cost and no mechanical detector. Rejection
versus lead exhaustion is the hardest call in the framework and already carries a
dedicated anti-signal. Spike versus decision is "can we?" against "which one?",
which is a reading of the exploration's core question. Competitive analysis is a
judgment about whether findings centre on external products. Reaching any of these
by predicate — C's proposal — trades the guard for brevity on the four outcomes
where a wrong answer writes a permanent document under `docs/`.

The fifth stage-1 category, "a chain", is scored rather than left as the residual.
Making it a scored category with its own anti-signals is what lets the demotion
rule apply symmetrically; as a residual it could never be demoted below a clean
terminal, which quietly privileges it on every run.

### The seven tiebreakers (Q2)

| Current tiebreaker | Fate |
|---|---|
| PRD vs Design Doc | **Dies.** Both collapse to `/scope`; the requirements-identified-vs-given distinction no longer changes the destination. It has an afterlife as *handoff content* — whether the handoff pre-supplies the framing-shift answer — but not as a router rule. It is also the entire premise of explore eval 3. |
| PRD vs No artifact | **Survives, re-pointed** to `/scope` vs file an issue. Its distinguishing question ("can one person act on this without a written contract?") transfers verbatim. This becomes the highest-traffic tiebreaker in the new set. |
| Design Doc vs Plan | **Survives in shape, with the answer inverted.** Its question — does an upstream artifact already exist? — still matters, but the consequent changes: a PLAN on disk unlocks `/execute`; a PRD or DESIGN on disk unlocks *nothing*, because the chain runs whole and consolidation reduces afterward. Re-pointing this rule naively is the single most likely way to reintroduce entry-altitude selection through the back door, and the replacement must say so. |
| VISION vs PRD | **Survives, re-pointed** to `/charter` vs `/scope`. "Does the project exist yet?" remains the cleanest single discriminator between the two parents. |
| VISION vs Roadmap | **Dies.** Both are `/charter`. |
| VISION vs Rejection Record | **Survives, promoted to stage 1** as chain-vs-rejection. It stops being a pairwise tiebreaker and becomes the stage's central discrimination. |
| VISION vs No Artifact | **Survives, re-pointed** to `/charter` vs file an issue. |

Four new ones are needed, none of which the old set had an analogue for:
`/charter` vs `/scope` at the "multi-feature initiative inside an existing
project" boundary (does the work need a bet stated and features sequenced before
any one feature can be specified?); spike vs decision at stage 1 ("can we?"
against "which one?", currently implicit in the two tables' anti-signals and worth
promoting); rejection vs file-an-issue for the leads-ran-out case (keep it inside
the rejection table where it already lives, and cross-reference it from the
fallback); and `/execute` vs `/scope`, which the precondition mostly resolves —
what remains is whether the exploration confirmed or invalidated the PLAN it
found. Net: seven becomes seven, redistributed, with three of the four survivors
landing at stage 2 and one moving to stage 1.

The six disambiguation rules (`:259-293`) fare similarly. "Requirement gaps AND
technical questions → favour PRD" **dies** — its whole content was ordering PRD
before Design, which the chain now does by construction, and it is the clearest
single illustration that the chain absorbed a job the router used to do.
"Plan signals present but no upstream artifact exists" **dies** for the same
reason. "Deep exploration but the user wants to act fast" **survives re-pointed**
and gets stronger: urgency does not override capture, the chain still runs, and
consolidation compresses the artifact set afterward — which is the mandatory-steps
model stated in the router's own voice. "Strategic justification AND feature
requirements → VISION first" **survives re-pointed** as `/charter` before
`/scope`, and also gets stronger, because the handover is now typed: `/charter`
produces the ROADMAP that `/scope` takes as `--upstream`. "Findings contradict
across rounds → weight later rounds" **survives verbatim** and is stage-agnostic.
"Multiple deferred types match" depends on the Prototype call below.

### `--strategic` does not survive as a crystallize input (Q3)

The flag survives; its thumb on the scale does not.

Today `--strategic` does four things: sets the scope value logged in Phase 0,
governs what content is appropriate, biases crystallize toward VISION and Roadmap
through the VISION table's "Scope is tactical (override or repo default)"
anti-signal (`:96`), and appears in SKILL.md's routing table as the thing to run
for strategic work. The third of those is incompatible with an entry-point
router. Stage 2's principal job is choosing between `/charter` and `/scope`; a
flag that pre-answers it makes the pass decorative. Worse, the flag is not only a
flag — it is read from CLAUDE.md as `## Default Scope: Strategic`, so a repo
default would pre-answer the router for every exploration in that repo. That is
the same shape the PRD removes elsewhere: a classification made at entry deciding
what runs later.

Two concrete cases make it a live problem rather than a purity argument. An
exploration in a Strategic-default repo that converges on one well-bounded feature
should reach `/scope`, and under a biasing flag it cannot. An exploration launched
`--tactical` that discovers the project needs a thesis before any feature can be
specified should reach `/charter`, and under a biasing flag it cannot.

So: `--strategic` keeps its Phase 0 role and its content-governance role, is
recorded in the scope file, and is available to stage 2 as evidence like any other
finding — but no signal or anti-signal names it, and the VISION table's
scope-anti-signal row is not carried into `/charter`'s table. R12 reaches this
directly, since that row names chain-internal children, and R10's "no scoring
category shall name a chain-internal child" reaches it too.

Consequences to carry: SKILL.md's routing-table row "I need to justify this
project… → `/explore --strategic <topic>`" re-points to `/explore <topic>` (the
router reaches `/charter`) or `/charter <topic>` for an author who already knows.
Explore eval 14 (`strategic-classification`) currently asserts "recommends
`/explore --strategic` or starting with a VISION document" and becomes "recommends
`/charter`", dropping the flag half. Retiring the flag *entirely* is a larger
change than R12 requires and is left alone.

### Complexity survives as an advisory surface, not as a router input (Q4)

Two different things are named "complexity" in `skills/explore/SKILL.md` and they
have different fates.

The complexity table and detection algorithm (`:59-96`) belong to the skill's
passive routing-advisor role — the half that answers "which command should I run?"
from a one-line request, before any exploration exists. They survive with
re-pointed destinations, and R12 forces the re-pointing. What emerges is smaller
than five levels: Trivial and Simple both land on file an issue (differing only in
whether an issue is filed at all), Medium lands on `/scope`, Complex means "run
`/explore` and let the router decide", Strategic lands on `/charter`. Medium's
reason for existing — "you need design but not requirements", i.e. the `/design`
then `/plan` path — evaporates, which is precisely R12's "where a row's
distinction only mattered while PRD and DESIGN were separately choosable, the row
SHALL be removed rather than re-pointed". The detection algorithm's step 3 goes
with it, since Medium and Complex now differ only in whether exploration is needed
first, not in destination. The algorithm's remaining job is cleaner: is this one
issue's worth of work, one feature, or a strategic bet — and do you need to
explore before answering.

As a *crystallize* input, complexity does not survive. Crystallize runs on
accumulated findings from every round; a five-level label derived from a
one-sentence request adds nothing those findings do not already carry, and
importing it would put a second classification vocabulary inside the one routing
surface R16 exists to guarantee. The one place complexity-like reasoning stays
inside the router is the decision arm's existing "Complexity Signal" field in the
decision brief (`phase-5-produce-decision.md:29-31`), which is a parameter passed
to `/decision`, not a routing input.

### `/execute` versus `/scope` is a filesystem fact checked first, then scored (Q5)

Checked first, as a candidacy precondition, then scored — neither a pure gate nor
a pure signal.

The precondition: a PLAN exists at `docs/plans/PLAN-*.md`, or at any `.md` whose
frontmatter carries `schema: plan/v1`, and its `execution_mode` is `single-pr` or
`coordinated`. A `multi-pr` PLAN does not unlock the arm — `/execute` directs
those to `/work-on` against the repo-persisted PLAN
(`skills/execute/SKILL.md:35-45`) — so a multi-pr PLAN unlocks the file-an-issue
arm instead. If no qualifying PLAN exists, `/execute` is not a candidate: absent
from the ranking, absent from the AskUserQuestion, and unmentionable in the
recommendation prose. That is what R13's "only when" buys, and a scored signal
cannot buy it, because any signal can be outvoted at margin 1 and the result is a
router handing `/execute` an input it rejects.

The scoring: when a qualifying PLAN does exist, `/execute` and `/scope` are both
candidates and stage 2 decides. The discriminating question is whether the
exploration confirmed the PLAN or undercut it. An exploration that found the PLAN
and validated its sequencing routes to `/execute`. An exploration that found the
PLAN and invalidated the assumptions it rests on routes to `/scope`, and the chain
runs again — which is the mandatory-steps model applied to the router's own
output. Making the PLAN's existence *decide* rather than *qualify* would rule out
the second case entirely.

## Consequences

**Positive.** The reader walks five tables and often stops, against ten today —
the framework gets cheaper per run while gaining a stage. Each stage asks a
question at one altitude, which removes the cross-altitude contamination that
makes today's Decision-vs-Design-Doc margin noise. Four of the ten tables survive
nearly verbatim, so the real diff is "five tables dissolved into four new ones,
four kept, one renamed" rather than "ten replaced" — a materially smaller and more
reviewable change than R10's wording implies. R14's four terminal outcomes get a
pass of their own instead of four rows among eight. The two genuine filesystem
facts move ahead of judgment, so R13 becomes structurally enforced rather than
weighted, and the public-repo competitive-analysis refusal stops being a
recommend-then-refuse. Explore evals 4 and 5, which would be redundant under B,
re-purpose into two distinct discriminations.

**Negative, with mitigations.**

*A stage-1 error is unrecoverable at stage 2.* If stage 1 wrongly returns a
terminal, the four entry points are never scored and never offered. Mitigation:
when stage 1's margin between "a chain" and the top terminal is within 1 — the
same threshold step 4.5 already uses — run stage 2 anyway and present both
results, so the author sees the entry-point arm they would otherwise never be
shown. Step 4.7's "None of these" option stays as the general escape.

*Phase 4 grows a control-flow branch and the crystallize artifact grows a shape.*
`wip/explore_<topic>_crystallize.md` needs to record the stage-1 verdict and, when
applicable, the stage-2 verdict, so that a Phase 5 resume knows which handler to
load. Mitigation: this is a template edit to `phase-4-crystallize.md:162-185` and
a row-set change to `phase-5-produce.md:38-48`, both of which are being edited
anyway.

*Three new eval scenarios.* Stage 1 needs independent grading. Mitigation: two of
the three can be built from existing fixtures — the adversarial-absent-demand
fixture set (explore eval 10) already produces exactly the findings a
rejection-record stage-1 scenario needs, and R35/R36 leave those scenarios
untouched, so they can be reused rather than re-authored.

*Behaviour changes for Strategic-default repos.* An exploration in the `vision`
repo that used to be nudged toward VISION is now scored on its findings.
Mitigation: state the flag's narrowed role explicitly in SKILL.md where the flag
is documented, so the change is visible to an author who relied on the old
behaviour rather than surprising them at Phase 4.

*The `Design Doc vs Plan` tiebreaker's inverted answer is a trap.* Anyone
re-pointing it mechanically will write "a PRD or DESIGN already exists → enter
above `/brief`", which is entry-altitude selection reintroduced through the
router. Mitigation: the replacement rule should carry an explicit sentence saying
that an existing PRD or DESIGN unlocks nothing, and `/scope`'s eval 17
(`chain-shape-is-constant`) is the corpus's existing guard against exactly this.

## Open Sub-Questions

1. **Does the SKILL.md complexity table count as a second routing surface?** The
   PRD's acceptance criterion says `skills/explore/` must contain "exactly one
   routing surface: no step outside the crystallize phase reaches a terminal route
   on its own." The complexity table is advisory and runs when no exploration is
   in progress, so on my reading it is the passive advisor role and exempt — but a
   literal reading deletes the table. This needs an explicit ruling before anyone
   edits `SKILL.md:59-96`, because the two readings differ by whether the table
   survives at all.

2. **Does `--strategic` keep its non-routing roles, or retire entirely?** The
   recommendation is keep-but-defang: Phase 0 logging and content governance stay,
   crystallize influence goes. Retiring it outright would also require deciding
   what `## Default Scope:` in CLAUDE.md governs afterward, which reaches
   `/strategy` and `/vision` as well and is a wider change than R12 asks for.

3. **Is "file an issue" one arm or two?** R13 names one arm with `/work-on` as its
   next step, but the current Trivial row says "no issue needed" and the No
   Artifact handler suggests either `/issue` or direct `/work-on`. If it stays one
   arm, its handler must state when an issue gets filed and when it does not.

4. **What happens to the Prototype deferred type?** Its stated alternative is
   already "no artifact — start building directly with `/work-on`", which is now a
   first-class arm, so folding it into file-an-issue and deleting the Deferred
   Types section (`crystallize-framework.md:143-157`) is clean. That also decides
   the fate of the "multiple deferred types match" disambiguation rule, which
   exists only to handle spike-plus-prototype.

5. **Is "a chain" a scored stage-1 category or the residual?** The recommendation
   is scored, for demotion-rule symmetry. The residual form is defensible, is one
   fewer table, and changes what the stage-1 insufficient-signal fallback means.
   Worth a Phase 6 look.

6. **Where does the `/execute` precondition physically run?** Phase 4 keeps the
   single-routing-surface property; Phase 0 would make the finding available to
   the exploration itself (an exploration that knows a PLAN exists asks different
   leads). The recommendation is Phase 4, but the trade is real.

7. **Does the two-stage verdict change the handoff artifact's shape?** R19-R21
   specify one handoff carrying conversation. `/charter` and `/scope` take
   structurally different handoffs today (`wip/vision_<topic>_scope.md` versus
   `wip/prd_<topic>_scope.md` templates), and stage 2 is where the choice between
   them is made. Whether that is one artifact with a parent field or two templates
   belongs to the handoff decision, not this one, but the stage-2 output is its
   input.
