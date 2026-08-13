# Demand validation: applying the /scope overhaul to /charter

Round 1, lead-adversarial-demand. Repo: tsukumogami/shirabe (public).
Sources: all 130+ open and closed issues, all 60+ PRs (bodies and review
threads), the committed doc corpus under `docs/`, the skill sources under
`skills/`, the validator format specs, and git history including deleted
paths.

## Standing fact that conditions every answer

**shirabe is a single-author repo.** Every one of the 130+ issues, open and
closed, is authored by `dangazineu`. Neither PR #252 nor PR #260 has a single
review comment (`gh api .../pulls/{252,260}/comments` both return empty). The
confidence vocabulary's "multiple independent sources" and "distinct issue
reporters" tests cannot be satisfied by this repo for any topic whatsoever.
That is a property of the corpus, not a verdict on this topic. Where I report
Medium below, Medium is the ceiling available.

**The strategic chain has no artifacts in this repo, and by decision never
will.** `docs/visions/`, `docs/strategies/`, and `docs/roadmaps/` do not
exist. `git log --all --diff-filter=A` over `docs/visions/*` and
`docs/strategies/*` returns nothing: **no VISION and no STRATEGY has ever
existed in this repository.** The two ROADMAPs that did exist
(`ROADMAP-strategic-pipeline.md`, `ROADMAP-koto-adoption.md`) were deleted in
commit `d432f13` by PR #242, whose body states: "Strategic (charter-altitude)
documents no longer live in public repos... Both are relocated to the private
vision repo under docs/roadmaps/done/."

So `/charter`'s output lands in a private repo I must not read into this
public-visibility artifact. Usage evidence for the strategic chain is
structurally out of reach here. Any "Absent" below carries that caveat.

---

## Q1. Is demand real?

**Confidence: Absent** for the transplant as such. **Medium (positive
rejection)** for the consolidation half specifically.

Searched all issues open and closed for `charter`, `consolidation`, `parity`,
`cardinality`, `fan-out`, `strategic chain`. The `charter` search returns
#254, #255, #256, #257, #258 and a set of closed 2025-era build issues (#98,
#99, #104-110, #150). None of them asks for the `/scope` overhaul to be
applied to `/charter`. `consolidation` and `parity` return nothing on point —
`parity` hits are golden-fixture and eval-alignment issues (#133, #205, #206,
#209).

The one charter-adjacent request that exists at all is #254 item 2, and it is
a *naming* parity item, not a mechanism one: `chain_skipped` entries are
`{child, reason}` in `/charter` and `{name, reason}` in `/scope`. #254 frames
all three of its items as "machinery guarding decisions that cost less than
the guard" — the same instinct behind PR #260 — but never proposes porting
the consolidation judgment.

Against that, there is explicit maintainer-authored rejection of the
consolidation half. `DESIGN-scope-consolidation-over-skipping.md` Decision 9
(lines 353-372) chose Option A and rejected Option B by name, and PR #260's
body repeats it in a section titled "Answering the open question about
`/charter`": "Nothing in `/charter` changes here."

## Q2. What do people do today instead?

**Confidence: High** — direct child invocation is documented as first-class
in three durable artifacts, not as a workaround.

- `skills/charter/SKILL.md:13` — "Do NOT use when the author already knows
  which artifact altitude they want (reach for `/vision`, `/strategy`, or
  `/roadmap` directly)." It is in the skill description, so it fires on every
  routing decision.
- `CLAUDE.md:135` — "The child skills `/vision`, `/strategy`, and `/roadmap`
  remain directly invocable on their own for authors who already know which
  altitude they want." The tactical mirror sits at `CLAUDE.md:155`.
- `docs/prds/PRD-shirabe-charter-skill.md` US-4, "Reviewer redirect via
  manual fallback" (lines 226-249) — an author tightening a Draft STRATEGY
  invokes `/strategy <path>` outside `/charter`, "so that manual fallback is
  first-class steady-state capability rather than a workaround." `/charter`'s
  resume ladder detects the out-of-chain edit and warns without acting.
- `skills/charter/references/phases/phase-2-chain-orchestration.md` (tail,
  ~line 455) — a declined `/roadmap` "can always be produced later by running
  `/roadmap` directly."

This is the same escape hatch `/scope` leans on. `DESIGN-scope-consolidation-over-skipping.md`
lines 154-161 makes it load-bearing for the tactical chain: the shorter
outcomes "are reached by invoking `/design` or `/plan` directly. That is not a
workaround... The difference is that the choice now lives in what the author
typed rather than in a judgment `/scope` makes on their behalf."

The escape hatch is why the reduction problem is less pressing on the
strategic side: an author who wants only a STRATEGY types `/strategy`.

## Q3. Who specifically asked?

**Confidence: Absent.**

Nobody asked for this. There is no issue, no PR comment, and no doc prose
requesting that `/charter` take the consolidation half or that its chain walk
change. The only human in the record is `dangazineu`, and what he wrote about
it is the *decision not to do it* (Decision 9, PR #260's body). The nearest
thing to a request is #254 item 2 — his own, about key names.

## Q4. What behavior change counts as success?

**Confidence: Absent** for the transplant. **High** for the two neighbouring
items that do carry criteria.

No acceptance criteria anywhere describe a post-transplant `/charter`. What
does exist, and is worth not confusing with it:

- **PR #252's success criteria, already met.** "`/roadmap` runs on every
  full-run chain, and the only thing that skips it is the author saying this
  strategy is not headed for execution at all." Regression guard:
  `r7-negative-reading-still-invokes-roadmap`, reported 5/5. Charter eval
  suite 91/91 across 16 scenarios.
- **#254 item 2's criterion**, stated: pick one key name; the cost is "changing
  the other parent's schema doc, its phase files, and its eval assertions."
- **#255's criterion**: the `/scope` R6 predicates get graded assertions on the
  `/plan` value-confirmation-guard model — assert the verdict, assert the
  reasoning independently of the verdict, include a negative control.

#255 also flags the hazard most relevant to any transplant: "a verdict
assertion can encode the *author's* wrong answer. PR #252 hit this — an
assertion claimed a cold start does not invoke `/vision` when the rule says it
does, and the fix was to the assertion."

## Q5. Is it already built?

**Confidence: High.** Both halves of PR #260 that are applicable to the
strategic chain are already in `/charter`, and the third was evaluated and
declined.

**Half one — always walk the whole chain: already there.** Reading
`skills/charter/references/phases/phase-2-chain-orchestration.md`:

| Child | Gate today | Equivalent in post-#260 `/scope` |
|---|---|---|
| `/vision` | Mandatory-with-auto-skip against an Accepted or Active VISION, with an author override | exactly `/scope`'s surviving re-entry protection |
| `/comp` | runs iff repo visibility is private and the skill is installed | structural, no `/scope` analogue |
| `/strategy` | ALWAYS (R6). "There is no condition under which `/charter` skips `/strategy`" | matches `/prd` |
| `/roadmap` | ALWAYS (R7), author declination only. "`/charter` does NOT count Building Blocks, does NOT test the Coordination Dependencies section" | matches the `/design` move in Decision 1 |

There is no altitude selection and no computed threshold left to remove. The
one thing #260 deleted that `/charter` still has is the *narration* of skips
in the chain proposal (`phase-1-discovery.md` lines 228-284), and those skips
are re-entry protection and a visibility gate — both of which `/scope` kept.

**Half two — invoke children through their upstream-path input mode: already
there.** #260 Decision 2 was the change that made `/prd` actually read its
BRIEF. `/charter` R6 already does this: shape 2 is "VISION path... `/charter`
passes the VISION path; `/strategy` reads it as its Input Mode 3 upstream."
The consumption side is stronger than the tactical chain's was — STRATEGY's
required "Strategic Context" section is *defined* as "carry-forward of the
essential framing from the upstream VISION" plus a stand-alone property
(`skills/strategy/references/strategy-format.md`, per-section content rules).
The tactical chain had no such contract before #260 and had to add one.

**Half three — the consolidation judgment: evaluated and declined.** Decision
9, verbatim (`DESIGN-scope-consolidation-over-skipping.md:353-372`):

> - **Option A (chosen): state in prose that the consolidation model is a
>   no-op on the strategic chain, and change nothing.**
> - **Option B (rejected): implement the same model in `/charter` now.** Out
>   of scope per the PRD, and the consolidation half would add machinery that
>   can never fire.
> - **Option C (rejected): say nothing.** The PRD asks for the answer.
>
> `/charter` has already taken the run-every-child half of this: PR #252 made
> `/roadmap` an ALWAYS child with an author declination rather than a threshold
> the parent computed, which is the same move Decision 1 makes for `/design`.
> The consolidation half does not generalize, and the mapping test from
> Decision 4 says why. STRATEGY's required sections have no home for a VISION's
> Audience, Value Proposition, Org Fit, or Success Criteria; ROADMAP's have no
> home for a STRATEGY's Defensibility Thesis, Building Blocks, or Bet-Specific
> Falsifiability. Zero strategic hops are absorbable, so porting the judgment
> would install a rule that can only ever return `keep`. The model is intended
> to generalize; generalizing it today changes nothing, which is the reason not
> to.

**What it committed to:** state the answer in prose; change no strategic-chain
behavior. Both the PRD and the BRIEF put `/charter` under Out of Scope with
the same wording — "The DESIGN states in prose whether the model is intended
to generalize... no strategic-chain behavior changes here"
(`PRD-scope-consolidation-over-skipping.md:299`,
`BRIEF-scope-consolidation-over-skipping.md:170`).

**What it left open:** two things, both narrow.

1. The rejection of Option B is dated and conditional, not permanent. "Out of
   scope per the PRD" is a scoping reason; "can never fire" is a claim about
   *today's* required-section schemas. Decision 4 derives absorbability from
   `crates/shirabe-validate/src/formats.rs` precisely so it "stays correct if a
   format changes." If a strategic format ever changes, the answer is
   re-derived, not re-litigated. The model is "intended to generalize."
2. Nothing was said about the *cardinality* question at all. Decision 9 is a
   mapping-totality argument; 1:N never comes up.

**I verified the mapping claim independently** against
`crates/shirabe-validate/src/formats.rs:145-220`. It holds:

- VISION requires Status, Thesis, Audience, Value Proposition, Org Fit,
  Success Criteria, Non-Goals. STRATEGY requires Status, Strategic Context,
  Defensibility Thesis, Building Blocks, Coordination Dependencies,
  Bet-Specific Falsifiability, Non-Goals, Downstream Artifacts. Audience,
  Value Proposition, Org Fit and Success Criteria have no destination. Not
  total.
- ROADMAP requires Status, Theme, Features, Sequencing Rationale, Progress,
  Implementation Issues, Dependency Graph. Defensibility Thesis,
  Bet-Specific Falsifiability, Non-Goals and Downstream Artifacts have no
  destination. Not total.

Zero absorbable hops. Decision 9's factual premise is correct as of this
commit.

## Q6. Is it already planned?

**Confidence: High that it is not planned. Medium that the sequencing
question is unanswerable from this repo.**

Read #254, #255, #257 in full. None plans this work:

- **#254** — three unresolved parent-chain items from PR #252's scope
  overflow: `/execute`'s undefined blocking-label outcome, the
  `chain_skipped` key divergence, and a resume-ladder reachability audit
  ("`/charter`'s ladder is ten rows... rows 7-8 in particular both require no
  artifact at the published path"). All three are audits or naming fixes.
- **#255** — eval coverage for judgment gates in `/scope`, `/explore`,
  `/design`. Bears on the transplant only as a precondition: the gate the
  transplant would copy is itself unasserted today.
- **#257** — a STRATEGY can still be *grounded* in a tactical-chain PRD. Names
  three options and picks none. Explicitly a chain-hygiene bug, not a
  consolidation one. PR #260 notes "#257, the strategic-side analogue, is
  untouched."

Also open and charter-adjacent: **#253** (upstream link legality is
unenforceable — "every rule above can be violated freely"), **#265** (FC16
shape-gating), **#258** (the eval suite cannot be run within a Max quota,
which is why nine of PR #252's suites are "reviewed, not verified").

**There is no ROADMAP or STRATEGY in this repo to sequence further
parent-skill work.** None exists and none ever has; per PR #242 they live in
the private vision repo by decision. So I cannot report whether the strategic
pipeline sequences a charter follow-up — that record is not in scope for a
public-visibility artifact. What I can say is that the public planning
surface (issues) contains no such item.

---

## The cardinality question specifically

**Confidence: Medium that 1:N is a documented, sanctioned shape. Absent that
it has ever occurred in real use.**

The 1:N shape is written into the format contracts:

- `skills/strategy/references/strategy-format.md:278` — "One Active STRATEGY
  per bet at a time. **Multiple STRATEGYs may operate under one upstream
  VISION when they make distinct bets.**" That is an explicit, maintainer-
  authored 1:N rule for VISION -> STRATEGY.
- `skills/vision/references/vision-format.md:170` — "One Active VISION per
  project at a time." The constraint binds the top of the chain only.
- `skills/vision/references/vision-format.md:122` — Downstream Artifacts
  "lists STRATEGY documents", plural.
- `skills/roadmap/references/roadmap-format.md:81` — "a STRATEGY's Downstream
  Artifacts list ROADMAPs, and a ROADMAP's upstream is that STRATEGY".
  `strategy-format.md:80` defines the section as "typed link list of the
  ROADMAP documents that sequence this strategy's work" — plural, and
  `:425` says it is "populated as downstream ROADMAPs land", again plural.
- PR #252's body states the invariant as "A VISION lists STRATEGYs, a STRATEGY
  lists ROADMAPs" — plural on both.

So the 1:N shape is not a hypothetical; it is the specified shape. The
contrast with the tactical chain is sharp: `/scope`'s hops are 1:1 by
construction, which is what makes a per-hop absorb well-defined at all.

**Real-use evidence: none found.** No VISION or STRATEGY has ever been
committed to this repo. The two ROADMAPs that existed were both `status:
Active` simultaneously, but I checked their frontmatter at `d432f13^` and
**neither carries an `upstream:` field** — they predate the STRATEGY layer
entirely. Two concurrent Active roadmaps under *no* strategy is not evidence
of one strategy with two roadmaps.

Nothing in the strategic design corpus discusses fan-out either.
`PRD-shirabe-strategy-skill.md`'s "downstream-fanout" (Decision 3, lines
510-539) is a *granularity heuristic for Building Blocks* — "1-2 design docs
per block minimum" — measuring blocks against design docs, not strategies
against roadmaps. It is not the signal.

One structural note bearing on whether cardinality makes the transplant
ill-defined: `/charter` invokes `/strategy` exactly once and `/roadmap` exactly
once per run, so a single chain never produces the fan-out. The 1:N shape
arises across *repeated* `/charter` runs or direct `/strategy` invocations on
the same VISION. A per-hop judgment comparing "the artifact just written"
against "the nearest surviving durable artifact above it" is well-defined
within one run; what is undefined is what a *second* STRATEGY's hop should
compare against when the VISION above it already has a sibling. Nobody has hit
that, because nobody has written a second STRATEGY here.

Related and worth flagging: `PRD-shirabe-charter-skill.md` R2 already forbids
`/charter` from taking artifact paths as input — "The chain produces multiple
artifacts; an upstream-path input mode does not compose" (line 281). That is
a fan-out-adjacent constraint the maintainer already reasoned about, from the
input side rather than the consolidation side.

---

## Calibration

The two states must not be merged here, because this topic sits in both at
once depending on which half you ask about.

### Demand validated as absent — the consolidation half

This is positive rejection evidence, not silence. A maintainer-authored design
document evaluated the exact proposal, named it as Option B, rejected it, and
gave a mechanical reason that I verified independently against the validator's
format specs and found correct. The rejection is restated in the merged PR's
body and the de-scoping is recorded in all three upstream artifacts (BRIEF,
PRD, DESIGN). That clears the bar the brief sets: "design docs that de-scoped
the feature."

Two qualifications on the strength of that finding. First, the rejection is
schema-conditional by construction — Decision 4 derives absorbability from
`formats.rs` so the answer re-derives if a format changes, and the design says
outright that "the model is intended to generalize." A future strategic-format
change reopens it mechanically. Second, "already taken the run-every-child
half" is a claim I confirmed rather than accepted: `/charter`'s phase-2 file
shows `/strategy` and `/roadmap` as ALWAYS children and `/vision` on the same
Mandatory-with-auto-skip shape `/scope` kept.

The other half of the transplant — the upstream-path invocation mode — is
already shipped in `/charter` R6, and the corresponding consumption contract
is stronger on the strategic side than it was on the tactical side.

### Demand not validated — the cardinality half

No evidence either way. The 1:N shape is documented and sanctioned in three
format references and PR #252's body, so it is real as a *specification*. Not
one instance of it exists in the corpus, no issue reports friction from it, no
PR discusses it, and no design doc raises it. Nobody has said it makes
anything ill-defined; nobody has said it doesn't.

Flag the gap honestly: this repo cannot answer the cardinality question, and
the reason is structural rather than incidental. PR #242 moved every
strategic artifact to a private repo, so real-world `/charter` usage leaves no
trace on the public surface I am allowed to read into this artifact. If the
1:N case has ever been hit, the evidence is in the private vision repo or in
the user's head. User clarification — "have you ever written a second STRATEGY
under one VISION?" — would settle in one sentence what no amount of further
searching here can.

### Not a demand finding, but adjacent and real

If a next round wants a charter-side topic with actual issue backing, three
exist and none is this one: #254's `chain_skipped` key divergence between the
two parents (a genuine cross-parent parity defect, cheap, with the cost
already itemized), #257's grounding-PRD level violation (options enumerated,
decision pending), and #253's unenforceable upstream link legality (which PR
#252's body calls "cheaper to fix than it looks").
