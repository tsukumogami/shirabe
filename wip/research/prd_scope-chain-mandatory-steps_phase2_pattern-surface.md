# Pattern-Surface Edit Map — `scope-chain-mandatory-steps`

Research output for `/prd` Phase 2 discovery. Every quotation below is verbatim
with line numbers against the worktree at
`/home/dgazineu/dev/niwaw/tsuku/tsuku+shirabe_inconsistencies-03b57366/public/shirabe/.claude/worktrees/scope-chain`.

Files read in full: `references/parent-skill-pattern.md` (771 lines),
`references/parent-skill-state-schema.md` (263 lines). Also read to ground the
per-parent claims: `skills/scope/references/phases/phase-1-discovery.md`,
`skills/scope/references/phases/phase-2-chain-orchestration.md`,
`skills/scope/references/state-schema.md`, `skills/scope/SKILL.md`,
`skills/charter/references/phases/phase-1-discovery.md`,
`skills/charter/references/phases/phase-2-chain-orchestration.md`,
`skills/charter/references/phases/phase-state-management.md`,
`skills/charter/references/phases/phase-finalization.md`,
`skills/execute/SKILL.md`, the four `skills/scope/references/decision-record-*.md`
templates, the two `skills/charter/references/templates/decision-record-*.md`
templates, and both parents' `evals/evals.json`.

Everything marked **DRAFT** is proposed wording for the PRD/DESIGN to refine, not
a finished edit.

---

## 1. Where the model statement goes

### 1.1 Confirming the absence

`grep -niE "consolidat|absorb|fold|worth|earn"` against
`references/parent-skill-pattern.md` returns four lines, none of which is a
statement of the model:

```
191:had no examples left and was folded into Mandatory-with-auto-skip's
254:prompt without learning that the parent that invoked it.   [substring "earn" in "learning"]
476:   `status:` value to learn the child's terminal exit (Accepted,
764:  `triggering_teammate:` field; the parent learns about it via the
```

Line 191 is the EITHER-signal retirement note using "folded" in the
vocabulary-consolidation sense, not the artifact sense. Lines 254/476/764 are
substring hits on "learn". `consolidat` and `worth` have **zero** matches. The
same grep against `references/parent-skill-state-schema.md` returns one line:

```
221:exit is a violation surface, not silently absorbed.
```

— the R9 preamble, about silent absorption of a finalization failure, unrelated.

**Confirmed: neither shared parent-skill reference contains any statement that
chain steps are mandatory, that reduction happens after artifacts exist, or that
a parent may not judge an unwritten artifact's worth.** The entire model
currently lives only in `/scope`'s own files
(`skills/scope/SKILL.md:455-508`, `skills/scope/references/phases/phase-1-discovery.md:11-43`
and `266-288`, `skills/scope/references/phases/phase-2-chain-orchestration.md:488-502`
and `728-748`) — which is precisely the defect: the shared pattern both other
parents inherit from is silent, so `/charter` and `/execute` inherit nothing.

### 1.2 The insertion point

**Recommended location: the head of `## Gate Vocabulary`, between line 112 and
the existing preamble at lines 115-119.** The surrounding text, verbatim:

```
111  disciplined conversation has a durable home, even when production is the
112  wrong outcome.
113
114  ## Gate Vocabulary
115
116  Parents invoke children behind named gates. The pattern recognizes
117  three gate shapes; every child-invocation gate in every parent SHALL
118  be one of these three. Naming the shapes pattern-side keeps reviewers
119  from inventing per-parent vocabulary when a parent's chain shape
120  introduces a category the existing shapes already cover.
```

The new subsection goes immediately after line 114 (`## Gate Vocabulary`) and
before line 116 (`Parents invoke children behind named gates.`).

Why here and not elsewhere:

- The Gate Vocabulary is the only section that says what a gate is permitted to
  *do*. The model statement constrains what a gate is permitted to be *about*.
  A reviewer checking a new parent's gate against the three shapes needs both
  constraints in the same read.
- **Rejected: a new `I-8` under `## Semantic Invariants` (lines 40-76).** The
  seven invariants are all resume/state/termination properties and the section
  is described at line 42 as "The pattern names seven invariants"; adding an
  eighth changes a count that recurs and turns a one-paragraph insertion into a
  renumbering. The model is also not substrate-agnostic in the way I-1..I-7 are
  — it is a rule about gating semantics, which is Gate Vocabulary's subject.
- **Rejected: `## Three Exit Paths` (lines 78-111).** That section is about how
  a run terminates, not about which children run inside it. Its closing
  paragraph (the discipline-vs-artifact decoupling thesis, lines 101-111) is
  adjacent in spirit and is why the new subsection reads naturally right after
  it, but the statement is not an exit-path property.

### 1.3 DRAFT — the model statement

Verified against all three parents before drafting (see 1.4 for the per-parent
check). Six sentences:

> **Chain steps are mandatory; reduction is post-hoc.**
>
> Every child in a parent's chain is invoked unless one of the three gate shapes
> below closes it, and no gate shape licenses a parent to decide, before an
> artifact exists, that the artifact would not have been worth producing. The
> shapes admit exactly three grounds for a child not running: its durable
> artifact is already settled on disk (Mandatory-with-auto-skip), the author
> supplied it or declined it in so many words (an ALWAYS child's author
> declination), or a conditional feeder's three-condition gate never opened. A
> judgment about whether one document holds anything its successor does not is
> only answerable against two documents that exist, so a parent that reduces its
> artifact set SHALL do so after the artifacts land, through a single named
> mechanism its own SKILL.md defines — `/scope`'s Phase 2 consolidation judgment
> is the only such mechanism in v1, and a parent that defines none (`/charter`,
> `/execute`) ends every full run with the artifacts its chain produced.
> Reduction is a service to the reader, never a way for the parent to save
> itself work: the party that would benefit from skipping a step is never the
> party allowed to judge the step unnecessary. A parent SHALL NOT carry two
> reduction mechanisms firing at different times, because then neither reads as
> the rule.

### 1.4 Per-parent check behind the draft

Each clause was checked against the three parents as they exist. The draft is
worded to be true of all three; the checks are what forced the "a parent that
defines none" clause and the deliberate avoidance of asserting that every parent
*has* post-hoc reduction.

**`/scope` — true, and it is the source.**
`skills/scope/references/phases/phase-1-discovery.md:13-16`:

```
13  Phase 1 decides **nothing about the size of the artifact set.**
14  `planned_chain:` is `[brief, prd, design, plan]` on every run.
15  There is no starting altitude to choose and no child that Phase 1
16  can decide is not worth invoking.
```

and `:416-417`: "That list is a constant. Phase 1 has no input that can shorten
it and no field that records a different shape." Post-hoc reduction is the
Phase 2 Consolidation Judgment (`phase-2-chain-orchestration.md:488-767`), and
`skills/scope/SKILL.md:476-481` states the single-mechanism rule: "One mechanism
follows from that, and only one. **The consolidation judgment** (Phase 2)
reduces the set after the fact. […] Nothing else in a `/scope` run removes a
document."

**`/charter` — true of the mandatory half, and it has no post-hoc reduction at
all.** `/charter`'s three removal grounds are all inside the model:
`/vision` auto-skips against a settled artifact or a supplied upstream
(`phase-2-chain-orchestration.md:26-65`), `/roadmap` is removed only by author
declination (`:281-413`, with `:285-290` "No property of the just-produced
STRATEGY feeds the decision: `/charter` does NOT count Building Blocks […]"),
and `/comp` is a conditional feeder whose gate is visibility plus
skill-on-disk (`:95-111`). There is no consolidation judgment anywhere in
`/charter`. **This is why the draft says a parent MAY define such a mechanism
rather than SHALL** — asserting post-hoc reduction as a requirement would make
`/charter` non-conforming on landing.

**`/execute` — the mandatory half holds; the chain half does not apply.**
`skills/execute/SKILL.md:426-430`:

```
426  The `/execute` run is a homogeneous execution loop rather than a heterogeneous
427  authoring chain, so the chain-tracking triad (`planned_chain` / `chain_ran` /
428  `chain_skipped`) and the authoring discriminators (`boundary:`,
429  `decision_record_sub_shape:`, `plan_execution_mode:`) are omitted; their omission
430  satisfies I-5 the same way `/scope` omitting an inapplicable field does.
```

`/execute` has no `planned_chain`, so "every child in a parent's chain" is
vacuously satisfied. Its steps are the PLAN's issues, and it does not drop them
by judgment either — `:338` "(R21), never silently skipped" and `:231`
"escalation on blocked/skipped" put a blocked issue on an escalation path, not
a skip path. `/execute` also carries the downstream half of `/scope`'s
reduction: `:591-598` handles "A finalized chain that folded every artifact
away" via `docs/folds.md`. So the statement is true of `/execute`, but the PRD
should be aware it binds `/execute` only weakly.

---

## 2. Gate Vocabulary and the ALWAYS declination clause

### 2.1 The Gate Vocabulary section, verbatim (lines 113-195)

```
113
114  ## Gate Vocabulary
115
116  Parents invoke children behind named gates. The pattern recognizes
117  three gate shapes; every child-invocation gate in every parent SHALL
118  be one of these three. Naming the shapes pattern-side keeps reviewers
119  from inventing per-parent vocabulary when a parent's chain shape
120  introduces a category the existing shapes already cover.
121
122  - **ALWAYS** — the child is invoked unconditionally on every chain
123    run; no gate exists. Canonical example: `/charter`'s `/strategy`
124    invocation, which is the main-chain spine and runs whether or not
125    upstream VISION or ROADMAP exists. `/charter`'s `/roadmap`
126    invocation is ALWAYS as well: the parent inspects nothing in the
127    upstream STRATEGY to decide. A parent MAY additionally offer the
128    author an explicit declination for an ALWAYS child (`/charter`
129    does, for `/roadmap`); that is author-supplied input, not a
130    predicate the parent computes, and unlike an exit-path
131    intervention such as Bail it leaves the chain on its normal exit
132    with the skip recorded in `chain_skipped`. A parent MAY read the
133    upstream artifact to inform what it tells the author at that
134    declination prompt — reading for the prompt is not reading for
135    the gate, and the gate stays ALWAYS as long as no reading can
136    change the pre-selected answer or skip the child on its own.
137    Offering a declination is per-parent and optional — `/scope`'s
138    `/plan` is ALWAYS with no declination surface.
139
140  - **shape-dependent** — the child invocation's *form* (which sub-
141    shape of the child fires, with how many peers, against which set
142    of inputs) is determined by an upstream-recorded predicate on the
143    chain. The gate is not whether-to-invoke but how-to-invoke.
144    Canonical example: `/scope`'s `/design` invocation, whose
145    decision-roster shape is determined by the R6 predicates
146    (architectural-alternatives count, new-component references,
147    Complex classification) recorded during Phase 1 discovery.
148
149  - **Mandatory-with-auto-skip** — the child SHALL be invoked unless
150    its durable artifact already exists at the published-Accepted
151    status at the canonical path, in which case the child is recorded
152    in `chain_skipped` and the chain proceeds to the next gate. A
153    parent MAY additionally define a signal that overrides the skip
154    and invokes the child anyway. The override is optional per-parent:
155    a gate that defines none is still this shape. A parent whose
156    child's lifecycle carries a further settled status MAY name it in
157    its own binding (`/charter` skips against an Active VISION as well
158    as an Accepted one); the shape requires only that the settled set
159    be fixed before the run.
160    Canonical example without an override: `/scope`'s `/prd`
161    invocation, where an Accepted PRD at `docs/prds/PRD-<topic>.md`
162    causes the gate to auto-skip and the chain continues to
163    `/design`; absent that artifact, `/prd` runs. Canonical example
164    with an override: `/charter`'s `/vision` invocation, which skips
165    against an Accepted or Active VISION at
166    `docs/visions/VISION-<topic>.md` and runs anyway when Phase 1
167    discovery surfaces a thesis shift. `/scope`'s `/brief` is the
168    same shape with a framing-shift override.
169
170  The three shapes are stable across parents. Each shape's
171  canonical example fixes the meaning against an existing parent's
172  SKILL.md so a reviewer can grep the example to confirm the shape
173  identifier matches the binding.
174
175  An override is not a second route into the child. It can only fire
176  in the case the auto-skip would otherwise have closed the gate — a
177  settled artifact already on disk — so a cold start fires the child
178  whatever the signal says. A parent MAY still surface the override
179  question on every run for the framing it gives the conversation; it
180  just cannot change the outcome when there is nothing to skip.
181
182  *EITHER-signal retired 2026-08-08.* An earlier revision named a
183  fourth shape, EITHER-signal: "the child is invoked when a
184  parent-defined signal fires OR an upstream condition holds, with
185  either signal sufficient to open the gate," with `/charter`'s
186  `/vision` as its canonical example. Once each gate carrying that
187  label was written out as its own rule, every one of them
188  (`/charter`'s `/vision`, `/scope`'s `/brief`) turned out to be an
189  auto-skip gate with an override: the artifact state decides, and the
190  signal matters only when a settled artifact is already on disk. No
191  gate in any parent invoked its child on a signal alone, so the shape
192  had no examples left and was folded into Mandatory-with-auto-skip's
193  optional-override clause. Skill files and durable docs written before
194  that date may still call these gates EITHER-signal; read the label as
195  this shape. No gate's behavior changed — the same children fire on
196  the same runs.
```

(Line 196 above is the section's last line before `## Conditional Feeder
Invocation Shape` at 197.)

### 2.2 The ALWAYS declination clause, exactly

Lines 127-138, the three sentences inside the ALWAYS bullet:

```
127                                              A parent MAY additionally offer the
128    author an explicit declination for an ALWAYS child (`/charter`
129    does, for `/roadmap`); that is author-supplied input, not a
130    predicate the parent computes, and unlike an exit-path
131    intervention such as Bail it leaves the chain on its normal exit
132    with the skip recorded in `chain_skipped`. A parent MAY read the
133    upstream artifact to inform what it tells the author at that
134    declination prompt — reading for the prompt is not reading for
135    the gate, and the gate stays ALWAYS as long as no reading can
136    change the pre-selected answer or skip the child on its own.
137    Offering a declination is per-parent and optional — `/scope`'s
138    `/plan` is ALWAYS with no declination surface.
```

The clause already draws the right distinction ("author-supplied input, not a
predicate the parent computes"), but it draws it in one subordinate phrase and
never says what makes the distinction hold. It is also positioned as a
concession — "A parent MAY additionally…" — which is what makes it read as an
exception to the ALWAYS shape rather than as an instance of the model.

### 2.3 DRAFT — replacement wording for lines 127-138

> A parent MAY additionally offer the author an explicit declination for an
> ALWAYS child (`/charter` does, for `/roadmap`). A declination is an instance
> of the mandatory-steps model, not an exception to it: the parent still plans
> the child, still invokes it by default, and the only thing that removes it is
> an answer the author gives. Three properties separate an author declination
> from a parent-computed worth gate, and a conforming declination has all three.
> It is **author-supplied** — the input is the author's answer, no predicate the
> parent evaluates can produce the skip on its own, and in a non-interactive
> mode where no author answers, the child runs. It is **formed against a
> document that exists** — the prompt fires after the upstream artifact is on
> disk, so the author is answering about something they can read rather than
> about an unwritten document's hypothetical worth. And it is **recorded** — the
> child stays in `planned_chain`, the skip lands in `chain_skipped` with its
> reason, and unlike an exit-path intervention such as Bail the chain stays on
> its normal exit.
>
> A parent MAY read the upstream artifact to inform what it tells the author at
> that declination prompt — reading for the prompt is not reading for the gate,
> and the gate stays ALWAYS as long as no reading can change the pre-selected
> answer or skip the child on its own. What the prompt SHALL NOT ask is whether
> the child's artifact is worth producing. `/charter`'s roadmap prompt is the
> worked example: it asks whether the STRATEGY is headed for execution at all,
> and refuses size or shape as a ground. Offering a declination is per-parent
> and optional — `/scope`'s `/plan` is ALWAYS with no declination surface.

Each of the three properties is verifiable against `/charter` as it exists:

- author-supplied, and the child runs when nobody answers —
  `skills/charter/references/phases/phase-2-chain-orchestration.md:379-382`:
  "In `--auto` mode the prompt does not fire at all and `/roadmap` always runs
  — there is no roadmap-specific `--auto` special case, and no observation the
  walk can produce creates one. The declination is an interactive choice, never
  an inference."
- formed against a document that exists — `:303-306`: "Immediately before the
  invocation — after `/strategy` has completed and the Draft STRATEGY is on disk
  — `/charter` reads that STRATEGY, says what it observed, and asks."
- recorded, with the child staying in `planned_chain` — `:385-393`: "A
  declination is recorded in the state file's `chain_skipped:` list as a
  `{child, reason}` entry. `roadmap` stays in `planned_chain` — the plan was to
  run it; the author declined — and is absent from `chain_ran`".
- the not-worth-producing prohibition — `:309-313`: "The question the prompt
  asks is NOT 'is this strategy big enough to sequence.' Size never disqualifies
  a ROADMAP." and `:399-402`: "The declination is how an author marks a STRATEGY
  **non-actionable** […] It is not a judgment about the STRATEGY being too small
  or too simple to sequence."

### 2.4 The retired-EITHER-signal note's shape, and whether to reuse it

The note (lines 182-196) has six moving parts, in order:

1. An italicised dated headline: `*EITHER-signal retired 2026-08-08.*`
2. What the retired thing claimed, quoted verbatim from the earlier revision,
   with its canonical example named.
3. The finding that dissolved it (every gate carrying the label turned out to
   be a different shape once written out).
4. Where it went (folded into Mandatory-with-auto-skip's optional-override
   clause).
5. A read-old-docs instruction: "Skill files and durable docs written before
   that date may still call these gates EITHER-signal; read the label as this
   shape."
6. A no-behavior-change assurance: "No gate's behavior changed — the same
   children fire on the same runs."

**Recommendation: do not use the full shape here; borrow parts 3 and 6 only.**

The dated-retirement shape exists to solve a specific problem — a *name* went
away, and durable documents on disk still carry the dead name, so a reader
needs a translation rule. That problem does not arise for this edit. Nothing is
being retired: no gate shape is removed, `/charter`'s roadmap declination is
KEPT (per the decision taken), the gate stays ALWAYS, and the same children fire
on the same runs. Adding parts 1, 2, 4 and 5 would advertise a vocabulary change
that did not happen, and a future reader grepping for "retired" would find a
note with nothing to translate.

What is worth borrowing:

- **Part 6, the no-behavior-change assurance**, belongs in the edit — one
  sentence, because a reader encountering a substantially longer clause about
  `/roadmap`'s declination will otherwise assume the behavior was tightened.
  DRAFT: *"`/charter`'s roadmap declination is unchanged by this wording; the
  same runs skip `/roadmap` as before, and what is new is only the statement of
  why that is the model rather than an exception to it."*
- **Part 3, the finding-that-dissolved-it move** — stating the reasoning rather
  than only the conclusion — is the house style throughout both parents' phase
  files and should be kept in the replacement prose. The three-property list in
  2.3 is that move applied here.

One caveat for the PRD: if the change also touches wording elsewhere in the
corpus that *did* use worth-producing framing, those sites need the full dated
shape. `/scope` already carries two undated in-file versions of it
(`phase-1-discovery.md:136-140` "An earlier revision of this file recorded the
same behaviour under a rationale that read as reader economy; the reason it
gives now is the reason it always had", and `:266-288`). The pattern doc's own
convention is dated; `/scope`'s is not. Worth deciding once.

---

## 3. The chain-proposal prompt contract

### 3.1 The section, verbatim

It sits at the end of `## Required SKILL.md Structural Elements`, lines 575-607:

```
575
576  The default-option wording at status-aware re-entry prompts is part of
577  the contract surface, not a UX detail; each parent specifies it as
578  literal-substring requirements in ACs (e.g., the "Re-evaluate / Revise /
579  Bail" triad against an Accepted upstream artifact), so the eval surface
580  can grep-check the prompt vocabulary and downstream parents inherit the
581  discipline.
582
583  **Which literal form to require.** Specify an option triad as ONE
584  contiguous literal (separator ` / ` exactly) where the contract
585  requires the options be **co-equal with no default**; specify it as
586  independent per-token substrings everywhere else. Contiguity is not a
587  style preference — it is the mechanical proxy for co-equality, because
588  a single option line cannot rank or bury its options while prose can,
589  and per-token checking cannot tell a co-equal menu from three words
590  buried in a leading question.
591
592  The rule classifies the existing triads without exemptions:
593
594  | Prompt | Co-equal, no default? | Form |
595  |--------|----------------------|------|
596  | Status-aware re-entry (`Re-evaluate / Revise / Bail`) | yes — the parent PRDs make co-equality contractual | contiguous |
597  | Chain proposal (`Proceed` / `Adjust` / `Bail`) | no — Proceed is the expected path, and a parent MAY render an interstitial label such as "Adjust chain" | per-token |
598  | Per-child confirmation prompts carrying an explicit default | no — the default marker is the point | per-token |
599  | Drift detection (`Re-run` / `Accept` / `Proceed without`) | no | per-token |
600
601  Do NOT generalize contiguity to a triad in the per-token rows: a
602  parent whose chain-proposal prompt renders "Adjust chain" would fail a
603  contiguous check against its own canonical example.
604
605  Note that the SHALL-NOT constraints naming this triad (the
606  refuse-and-redirect rows) are **conceptual**, not byte-literal — they
607  forbid *offering* the triad, however rendered — so they neither depend
608  on nor are weakened by the positive form chosen here.
```

**The row at issue is line 597.**

### 3.2 Verifying the two Adjust claims

**`/scope`'s Adjust cannot change its chain — verified.**
`skills/scope/references/phases/phase-1-discovery.md:460-472`:

```
460  ## Three-Way Adjust Path
461
462  When the author selects Adjust, Phase 1 re-enters at the
463  discovery prompt with the author's adjustment input merged in —
464  a re-framed topic, a corrected framing-shift answer, a different
465  read on the problem. Adjust does not change which children run,
466  because that list is fixed. Re-entry re-runs the R6 predicates
467  and re-emits the chain proposal;
468  the loop continues until the author selects Proceed or Bail.
```

Corroborated at `skills/scope/SKILL.md:440-442`: "…re-emit the proposal after
re-running the R6 predicates against the adjusted scope. Adjust refines the
topic and the framing, not the list of children."

**`/charter`'s Adjust genuinely can — verified.**
`skills/charter/references/phases/phase-1-discovery.md:383-391`:

```
383  - **Adjust** — the author wants a different chain shape. The
384    prompt routes the author back to Phase 1 discovery for chain-
385    shape redirection BEFORE any child fires. The redirected
386    discovery may force a previously-skipped child on (e.g., "force
387    `/vision` on, even though an Accepted VISION exists"), opt out
388    of a child that would otherwise fire, or reframe the topic
389    entirely. After the redirection, the chain proposal re-fires
390    against the new discovery outputs; the prompt cycle repeats
391    until the author Proceeds or Bails.
```

One boundary on `/charter`'s "can": Adjust cannot drop `/roadmap` —
`phase-2-chain-orchestration.md:404-413` — "Phase 1's 'Adjust' option re-shapes
the chain before any child fires, but it cannot drop `/roadmap`: `/roadmap` has
no Phase 1 gate to adjust". So `/charter`'s Adjust reaches `/vision` and (in
principle) the feeder, not the whole roster.

Also worth flagging for the PRD: `/charter`'s Adjust can "opt out of a child
that would otherwise fire" (line 387-388). Read literally, that is a chain-shape
reduction decided at Phase 1, before any artifact exists — which is exactly what
the model statement in section 1 prohibits for a *parent-computed* gate. It is
author-supplied, so it survives the model, but it is an author declination
happening at the wrong time (before the document exists), and it is not covered
by the three-property test drafted in 2.3. **The PRD needs to decide whether
`/charter`'s Adjust-opt-out is a fourth legitimate removal ground or wording
that should be narrowed.** This is the sharpest unresolved conflict I found.

### 3.3 The three options, weighed

**(a) Both parents keep the triad.**

What breaks: nothing mechanically. `/scope`'s Adjust is a live option even
though it cannot change chain membership — it re-enters discovery with a
re-framed topic or a corrected framing-shift answer, which re-runs the R6
predicates (resizing `/design`'s roster) and can flip the framing-shift answer
that overrides `/brief`'s auto-skip. The three literal substrings are already
graded in `skills/scope/evals/evals.json` (AC9) and
`skills/charter/evals/evals.json:242`.

What it costs: the same token means two different things across parents.
`/charter`'s Adjust can add or drop a child; `/scope`'s cannot. An author who
learns Adjust from one parent gets a different capability under the same word in
the other, and the pattern-level table says nothing about the divergence — line
597's justification is entirely about *default-ness* ("Proceed is the expected
path"), never about what Adjust reaches. The cost is one unstated per-parent
variation, which is the class of defect this whole PRD is about.

**(b) The pattern permits a constant-chain parent to emit an announcement with
no options block.**

What breaks: `/scope`'s Bail loses its only pre-child surface. Bail at the chain
proposal is the documented route into R8 bail-handling before any child fires —
`skills/scope/references/phases/phase-1-discovery.md:326-328`: "**Bail** — route
to R8 bail-handling per the parent's own bail-handling rule (force-materialize
if any wip state exists for the topic; clean-cancel otherwise)", and
`skills/scope/SKILL.md:443-448`. Removing the options block deletes the author's
only chance to stop the run before `/brief` writes, and it deletes a graded
literal-substring contract (`phase-1-discovery.md:296-297`: "The output's
options block contains the literal substrings `Proceed`, `Adjust`, and `Bail`
(case-sensitive, exact spelling per AC9)"). It also breaks `/charter`'s framing
of the prompt as "the stable contract between Phase 1 and Phase 2"
(`charter/.../phase-1-discovery.md:399-408`).

What it costs: an eval rewrite in both parents, an AC deletion in `/scope`, and
a real capability loss for the author. **Not viable.**

**(c) The pattern replaces the triad with a two-option confirmation.**

What breaks: `/scope`'s Adjust does real work that Proceed/Bail cannot reach.
Per `phase-1-discovery.md:462-467`, Adjust is the only in-prompt way to correct
a wrong framing-shift answer before `/brief` fires — and that answer is the
override that fires `/brief` against a settled BRIEF (`:64-66`). Dropping Adjust
means an author who realises mid-proposal that the framing *has* shifted must
Bail and re-invoke.

What it costs: the option count diverges across parents rather than the option
meaning, which is strictly worse for the eval surface — a per-token grep for
three tokens would have to fork per parent, where today one rule covers both.
It also inverts the section's own stated purpose ("so the eval surface can
grep-check the prompt vocabulary and downstream parents inherit the
discipline", lines 579-581).

### 3.4 Recommendation

**Take (a), and amend line 597's row plus the surrounding rule so the pattern
states what Adjust is guaranteed to reach and what is per-parent.**

Reasons: it is the only option that keeps a live capability in both parents,
keeps the three-token eval surface uniform across parents (and across the third
parent when `/execute` gets a proposal surface, if it ever does), and fixes the
actual defect — which is not that the triad is wrong but that the pattern
implies a uniform Adjust semantics it never states. The parent-side cost is
zero: both parents already carry the sentence that says which kind of Adjust
they have (`scope/.../phase-1-discovery.md:465-466` and
`charter/.../phase-1-discovery.md:385-389`), so only the pattern doc changes.

DRAFT amendment — replace line 597 and add one sentence after line 603:

> | Chain proposal (`Proceed` / `Adjust` / `Bail`) | no — Proceed is the expected path, and a parent MAY render an interstitial label such as "Adjust chain" | per-token |
>
> **What Adjust reaches is per-parent.** Adjust SHALL re-enter the parent's
> discovery with the author's input and re-emit the proposal; whether that
> re-entry can change chain *membership* is a per-parent property, and each
> parent SHALL state which it has in its own chain-proposal section. `/scope`'s
> cannot — its `planned_chain` is a constant, so Adjust refines the topic and
> the framing and resizes `/design`'s roster. `/charter`'s can — its `/vision`
> gate is adjustable, so Adjust may force a previously-skipped child on. Both
> satisfy the triad; neither may use Adjust to reach a child whose artifact the
> parent judged not worth producing, because no parent makes that judgment.

---

## 4. `chain_skipped[].reason` vocabulary

### 4.1 The current pattern-level definition

`references/parent-skill-state-schema.md:139-146`:

```
139  Parents whose run invokes a sequence of children record the chain
140  explicitly using three fields:
141
142  - **`planned_chain`** — the children the parent intended to invoke at the
143    start of the chain.
144  - **`chain_ran`** — the children whose invocations completed.
145  - **`chain_skipped`** — children the chain decided to skip, with free-text
146    reasons.
```

That is the whole of it: "with free-text reasons," and no constraint of any
kind. `/charter` restates the freedom more emphatically —
`skills/charter/references/phases/phase-state-management.md:143-146`:

```
143  - **`chain_skipped`** — list of `{child, reason}` entries. The
144    child name plus the free-text human-readable reason the chain
145    skipped the child. The reasons are NOT parsed by tooling — they
146    are durable evidence for human readers reviewing the chain.
```

`/scope` is the one that already constrains it —
`skills/scope/references/state-schema.md:81-91`:

```
81  - **`chain_skipped`** — list of `{name, reason}` entries for
82    children held back by re-entry protection (e.g. `/prd` when an
83    Accepted PRD already exists at the canonical path, per the
84    Mandatory-with-auto-skip gate from `parent-skill-pattern.md`).
85    Phase 1 writes exactly one reason,
86    `settled-artifact-at-canonical-path-reentry-protection`; a
87    child is never recorded here because the chain judged its
88    artifact not worth producing, since `/scope` makes no such
89    judgment before an artifact exists. Phase 2 writes one further
90    reason when a Reject at a settled-upstream boundary ends the
91    chain and the remaining children never run.
```

Note also `charter/.../phase-state-management.md:443-444`, which flags the field
as a leak surface: "**`chain_skipped[].reason`** — free-text reasons for
skipping children. Durable on the feature branch pre-merge; public."

### 4.2 Every reason string the two parents write today (exhaustive)

Searched `skills/scope/` and `skills/charter/` in full, including phase files,
SKILL.md, state schemas, `evals/evals.json`, and every decision-record template
under `skills/scope/references/` and `skills/charter/references/templates/`.

| # | Reason string as written | Parent / phase | Sites |
|---|---|---|---|
| 1 | `settled-artifact-at-canonical-path-reentry-protection` | `/scope` Phase 1, re-entry protection | `scope/.../phase-1-discovery.md:113`, `:424`; `scope/.../state-schema.md:85-86`; `scope/evals/evals.json:111`, `:116`, `:391` |
| 2 | `"PRD-boundary rejection"` | `/scope` Phase 2, records `/design` and `/plan` after a `/prd` Phase-4 Reject | `scope/references/decision-record-prd-rejection.md:74-76`; `scope/evals/evals.json:166`, `:176` |
| 3 | `"DESIGN-boundary rejection"` | `/scope` Phase 2, records `/plan` after a `/design` Phase-6 Reject | `scope/references/decision-record-design-rejection.md:72-74` |
| 4 | `author declined the roadmap at the confirmation prompt` | `/charter` Phase 2, roadmap declination | `charter/.../phase-2-chain-orchestration.md:390-393`; `charter/evals/evals.json:188`, `:193`; `charter/.../phase-finalization.md:85-87` (as `reason: <the author's declination>`) |
| 5 | *unfixed* — "a reason naming the supplied upstream" for `/vision` | `/charter` Phase 2, `consumed_upstream` auto-skip | `charter/.../phase-2-chain-orchestration.md:44-47`; `charter/evals/evals.json:262` |
| 6 | *unfixed* — `/vision` skipped because a settled VISION exists and no thesis shift | `/charter` Phase 2 | `charter/.../phase-2-chain-orchestration.md:63-65` ("no signal leaves the existing VISION in place and the chain skips the child, recording it in `chain_skipped`") |

Two negatives that matter:

- **`/comp` is never recorded.** `charter/.../phase-2-chain-orchestration.md:139-146`
  is explicit: "no `chain_skipped:` entry for `comp`, and `comp` is absent from
  `planned_chain`. […] `chain_skipped[].reason` is free text that lands in the
  repo. A child whose gate never opened was never planned, so there is nothing to
  record". The pattern doc says the same at lines 221-225.
- **The `/scope` decision-record templates are the only sites for strings 2 and
  3** — they are prose in a template's Consequences section, not a schema entry,
  so a bounded vocabulary must reach the templates too.

**Key-name inconsistency, in passing:** `/scope` writes `{name, reason}`
(`scope/.../state-schema.md:81`, `phase-1-discovery.md:422-424`), `/charter`
writes `{child, reason}` (`charter/.../phase-state-management.md:143`, `:257-259`).
The pattern doc specifies neither. Whatever the PRD does with the reason
vocabulary should fix the key at the same time — see 6.4.

### 4.3 DRAFT — bounded vocabulary

Five identifiers. Each admits at least one current use; none can express a
worth judgment.

| Identifier | Means | Admits |
|---|---|---|
| `settled-artifact-at-canonical-path-reentry-protection` | the child's durable artifact is already at a settled status at the canonical path | #1; #6 |
| `upstream-supplied-by-author` | the author supplied the artifact via `--upstream` and Phase 0 recorded it | #5 |
| `author-declined-at-confirmation-prompt` | the author declined an ALWAYS child at its named declination prompt | #4 |
| `<boundary>-boundary-rejection` | a Reject at a settled-upstream boundary ended the chain; the remaining children never ran. `<boundary>` is drawn from the parent's `boundary:` enum | #2 (`prd-boundary-rejection`), #3 (`design-boundary-rejection`) |
| `chain-terminated-before-invocation` | the chain exited (bail, abandonment-forced) before the child's turn | *no current writer* — see note |

Entry shape, with the free text demoted to a non-load-bearing sibling:

```yaml
chain_skipped:
  - child: vision
    reason: upstream-supplied-by-author
    detail: docs/visions/VISION-platform.md
```

`reason:` is the graded enum member. `detail:` is optional free text carrying
the specifics a human reader wants (which path was supplied, which prompt the
author answered) and is never the reason. This is what lets `/charter`'s current
"a reason naming the supplied upstream" survive intact: the naming moves to
`detail:`, the ground moves to `reason:`.

The fifth identifier has no writer today and I am not asserting one exists — I
found no documented behaviour that records remaining children on an
abandonment-forced exit. **The PRD should either confirm a writer or drop the
row**; shipping an enum member nothing writes is the kind of dead slot the
corpus already argues against (`scope/evals/evals.json:284`).

### 4.4 Closed enum or open list — recommendation

**Closed enum at the pattern layer, with a stated extension path: a parent that
needs a new identifier adds it to the pattern doc's list and to its own state
schema in the same PR.**

Why not an open list with a stated prohibition ("reasons SHALL NOT express a
judgment that the artifact was not worth producing"): the prohibition is the
entire point of the field's redesign, and free text is exactly what makes it
unenforceable. A grep-based eval can assert membership in a closed set; it
cannot assert the *absence* of a worth judgment from arbitrary prose. A
prohibition nothing can check is a comment, and the corpus already has one — the
sentence at `scope/.../state-schema.md:86-89` is a prohibition on free text that
holds only because `/scope` happens to write one string.

Why not a hard-closed enum with no extension path: it fails the moment a fourth
parent lands with a legitimate new ground, and the pattern's own convention
(`parent-skill-child-inspection.md:64-66`: "The table grows as new parents land
children with new shapes. Each parent that invokes a new child shape adds a row;
new rows go through the parent's own PR review") already establishes the
grow-by-PR-review pattern for exactly this situation. Reuse it verbatim rather
than inventing a second extension discipline.

Second reason the enum is right, independent of enforceability: the field is
**durably public from feature-branch push time**
(`charter/.../phase-state-management.md:443-444`), and free text is the surface
through which a private artifact type could be named from a public repo's
committed state file. That is the argument `/charter` already makes for keeping
`/comp` out of the field entirely. A closed enum makes the leak structurally
impossible for every future feeder, not just `/comp`.

---

## 5. Parent-roster staleness

### 5.1 Every stale statement, with line numbers

`grep -n "seven\|v1 parent\|both parent\|Both v1\|two parent" references/parent-skill-pattern.md`
plus a manual read. Five stale sites, plus two that are fine:

| Line(s) | Text | Verdict |
|---|---|---|
| 381-384 | "The contract applies symmetrically to both v1 parents (`/scope`, `/charter`) and all seven children (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`); no parent or child gets a per-binding override slot in v1." | stale, and **not** a one-line fix |
| 543-546 | "v1 has no per-parent override slot — the contract applies verbatim to both parents and all seven children." | stale; one-line fix once 381 is settled |
| 741-742 | "Both v1 parents (`/scope` and `/charter`) bind the discipline at the child layer, not at the dispatch boundary." | stale; one-line fix |
| 750-754 | "**At the parent-itself layer:** the binding is vacuous in v1. Both parents run as single-agent skills (see each parent's SKILL.md Team Shape section); no peers are dispatched at the parent-itself layer, so the loop has zero dispatched tasks to drive." | stale wording, claim happens to hold — see below |
| 768-771 | The `\| Parent \| Children invoked \|` table, with rows for `/scope` and `/charter` only | stale; a one-row addition |

Two that are **not** roster staleness and should be left alone: line 42 ("The
pattern names seven invariants") and lines 550/572-573 ("seven structural
elements"). Both are counts of pattern-internal things, unaffected by a third
parent. A find-and-replace on "seven" would corrupt them.

Also worth noting: `/execute` **claims conformance to this document** —
`skills/execute/SKILL.md:763` lists it under Reference Files as "conformance —
the seven required SKILL.md structural elements, the three exit names,
substitution surfaces", and `:501` cites it in Exit Paths. The name `execute`
appears **zero times** in `references/parent-skill-pattern.md`,
`parent-skill-state-schema.md`, `parent-skill-child-inspection.md`,
`parent-skill-resume-ladder-template.md`, and `parent-skill-security.md`. The
citation runs one way only.

### 5.2 Is fixing them one-line-each?

**Three of the five are.** Lines 543, 741, and the table at 768-771 are
mechanical once the roster is decided: change "both" to "the three", add
`/execute`, add a table row (`| /execute | /work-on |`).

**Line 750-754 is one line of wording plus one verification, and the
verification passes.** `skills/execute/SKILL.md:738-742` reads: "Single-agent
parent — no team is spawned at the `/execute` layer." So "Both parents run as
single-agent skills" becomes "All three parents run as single-agent skills" and
stays true. No substantive change.

**Line 381-384 is not a one-line fix, for three separate reasons.**

1. **The child roster needs a decision, not a count bump.** `/execute`'s child
   is `/work-on`, which is not in the seven. `/charter`'s `/comp` is a child it
   invokes and is also not in the seven. So "all seven children" is already
   wrong today (it omits `/comp`) and becomes wrong in a second way with
   `/execute`. The PRD has to decide whether a conditional feeder counts as a
   child for dispatch-contract purposes and whether `/work-on` does, then state
   the roster. That is a paragraph, not a number.
2. **The dispatch mechanism claim does not hold verbatim for `/execute`.**
   Lines 379-380 say "It is a contract — every parent SHALL satisfy every
   element verbatim and every child SHALL participate identically. The mechanism
   in v1 is the Skill tool, invoked inline by the parent." `/execute`'s single-pr
   path does not dispatch that way: `skills/execute/SKILL.md:740-744` — "In
   single-pr, the per-issue children are koto-materialized `/work-on`
   single-issue workflows on the shared branch […] In coordinated, each
   unblocked PR node dispatches a `/work-on` single-issue run per repo on that
   repo's own branch, driven by the plain durable-state loop rather than a koto
   session." Adding `/execute` to a sentence that says "the mechanism in v1 is
   the Skill tool" makes the pattern doc assert something false. Either the
   Dispatch Contract grows a second mechanism binding, or `/execute` is named as
   a stated variance. Both are design work.
3. **The Child Team-Shape Declaration glob marker.** Pre-Dispatch State element
   4 (lines 435-438) requires `skills/<name>/team.yaml` to exist for every
   child. `ls skills/execute/` shows no `team.yaml`, and neither `/scope` nor
   `/charter` has one either — so this is a pre-existing gap the roster fix
   would newly implicate. Flagging it; out of scope for this lead but the PRD
   should know the glob marker has no instances.

So: **four mechanical edits and one that needs a decision.** The decision is
whether the Dispatch Contract's "verbatim, every parent, every child" framing
survives `/execute`, or whether `/execute` is admitted with a named variance.
Recommend the latter — a stated variance is cheaper than re-opening a contract
that both authoring parents satisfy, and the pattern already has a house form
for it (the I-6 "named-but-unsatisfied" framing at lines 68-76).

---

## 6. State-schema edits

### 6.1 What the triad contract says

`references/parent-skill-state-schema.md:137-163`, the `### Chain-tracking`
subsection, quoted at 4.1 above for lines 139-146. The rest:

```
147  The three chain-tracking fields are conditional on chain-shaped parents.
148  Non-chain-shaped parents (e.g., an implementation-loop parent that runs a
149  single recurring inner phase rather than a sequence of distinct children)
150  MAY omit them. When omitted, invariant I-5 (conditional fields absent when
151  ungated) is satisfied; when present, the dual-check and resume-ladder
152  machinery consumes them.
```

Plus Extension Discipline rule 3, lines 207-209:

```
207  3. **Chain-tracking fields stay together.** A parent that uses
208     `planned_chain` SHALL also use `chain_ran` and `chain_skipped`
209     (they form a unit). A parent that omits chain-tracking omits all three;
210     no half-set.
```

Line 148's parenthetical — "an implementation-loop parent that runs a single
recurring inner phase rather than a sequence of distinct children" — is a
description of `/execute` written without naming it. `/execute` takes the
omission and cites I-5 by the same reasoning (`skills/execute/SKILL.md:426-430`,
quoted at 1.4). So the schema already accommodates `/execute` correctly; that
half needs no edit.

### 6.2 Constant or variable?

**Neither.** Line 142-143 says only: "**`planned_chain`** — the children the
parent intended to invoke at the start of the chain." Silence on whether the
list is the same across runs.

There is in fact a **third** reading elsewhere in the pattern doc.
Pre-Dispatch State element 3, lines 428-432:

```
428  3. **State-file fields written before dispatch** — the parent
429     advances `planned_chain`, bumps `last_updated`, and captures
430     `pre_invocation_sha` (the HEAD commit SHA at dispatch time, used
431     by the hand-back contract's Phase-N Reject discard-commit
432     detection) BEFORE the Skill-tool call fires.
```

"advances `planned_chain`" reads as a per-dispatch mutation, which matches
neither parent: `/scope` writes it once at Phase 1 and never again
(`phase-1-discovery.md:399-417`), and `/charter` sets it at chain-proposal
acceptance and modifies it "only if the author re-proposes the chain"
(`phase-state-management.md:133-134`). Whatever the schema settles on, line 429
needs to agree with it.

**`/scope` calls it a constant.** `phase-1-discovery.md:416-417`: "That list is
a constant. Phase 1 has no input that can shorten it and no field that records a
different shape." And `:14`: "`planned_chain:` is `[brief, prd, design, plan]`
on every run."

**`/charter` calls it variable.** `phase-state-management.md:129-138`:

```
129  - **`planned_chain`** — ordered list of child-name strings naming
130    which children are in scope for this run. Values are drawn from
131    `{vision?, comp?, strategy, roadmap}` (children with `?` are
132    conditional on their Phase 1 gates; `strategy` and `roadmap` are
133    unconditional). Set at Phase 1 chain-proposal acceptance;
134    modified only if the author re-proposes the chain. `roadmap` is
135    planned on every chain even though the author may later decline
136    it at the Phase 2 roadmap confirmation prompt — a declination
137    moves `roadmap` into `chain_skipped`, it does not retract the
138    plan.
```

**One caveat that complicates the reconciliation: there is a live contradiction
inside `/charter` about `/comp`.** Line 131 above lists `comp?` as a valid
`planned_chain` member, and the state-file template at
`phase-state-management.md:255` writes it out:

```
255  planned_chain: [vision?, comp?, strategy, roadmap]
```

But `phase-2-chain-orchestration.md:139-144` says the opposite, and gives a
reason:

```
139  - `wip/charter_<topic>_state.md` — no `chain_skipped:` entry for
140    `comp`, and `comp` is absent from `planned_chain`. The state
141    file is durably public from feature-branch push time (see the
142    security discussion in
143    `skills/charter/references/phases/phase-state-management.md`),
144    and `chain_skipped[].reason` is free text that lands in the
```

**The Phase 2 rule is the one to keep** — it carries the visibility argument,
and the pattern doc's Conditional Feeder section agrees with it verbatim (lines
221-225: "no `chain_skipped:` entry — a child whose gate never opened was never
planned, so there is nothing to record"). Lines 131 and 255 of
`phase-state-management.md` are the stale ones. The PRD should fix them in the
same change; leaving them means the schema edit lands on top of a parent that
contradicts itself.

### 6.3 DRAFT — what the schema should say

Replacing lines 142-146 of `parent-skill-state-schema.md`:

> - **`planned_chain`** — the children the parent intends to invoke, in
>   invocation order. Fixed at the point the author accepts the chain proposal
>   and not mutated per dispatch. Whether the list is the same on every run is a
>   per-parent property, and each parent SHALL state which it has: `/scope`'s is
>   a constant (`[brief, prd, design, plan]` on every run — nothing at Phase 1
>   can shorten it, and a child held back by re-entry protection is recorded in
>   `chain_skipped` rather than dropped from the list), while `/charter`'s
>   varies with its Phase 1 gates (`/vision` is absent when a settled VISION
>   exists at the canonical path or the author supplied one). Both shapes
>   satisfy the same rule: membership is decided by the named gate shapes, never
>   by a parent-computed judgment about an unwritten artifact's worth.
> - **`chain_ran`** — the children whose invocations completed. An ordered
>   sub-list of `planned_chain`; appended to as each child completes, never
>   overwritten.
> - **`chain_skipped`** — children that were planned and then not invoked, as
>   `{child, reason, detail?}` entries. `reason` is drawn from the closed
>   vocabulary above; `detail` is optional free text and is never the ground.
>
> **A child whose gate never opened is a member of neither list.** A conditional
> feeder that fails any of its three gate conditions (see Conditional Feeder
> Invocation Shape in `parent-skill-pattern.md`) was never planned, so it does
> not appear in `planned_chain` and there is nothing for `chain_skipped` to
> record; the stated-skip rule puts the explanation in the conversation instead.
> The distinction is load-bearing where the state file is durably public from
> feature-branch push time and the feeder's artifact type is private-only: a
> `chain_skipped` entry naming such a child, with a reason describing why, would
> name a private artifact type from a public repo's committed state file.
> `/charter`'s `/comp` is the worked case — it is absent from `planned_chain`
> entirely and carries no `chain_skipped` entry.

That last paragraph is the answer to "so both parents conform without `/charter`
having to record a private-only child in a public repo's state file": the schema
states the never-planned case as a first-class member category rather than
leaving `/charter` to justify the omission locally. `/charter` currently carries
the whole argument in its own Phase 2 file
(`phase-2-chain-orchestration.md:131-166`), and the pattern doc carries it in
the *Conditional Feeder* section (lines 220-230) but not in the *state-schema*,
which is where a reader checking a state file looks. Putting it in both is the
edit.

### 6.4 One more thing the schema should fix while it is open

The entry key diverges: `/scope` writes `{name, reason}`, `/charter` writes
`{child, reason}`, and the pattern doc specifies neither. The draft above picks
`child:` — it reads consistently against `parent_orchestration:`'s
`invoking_child:` (pattern doc line 417, state-schema line 190), and it is the
key two of the three graded eval strings already use
(`charter/evals/evals.json:193`).

Cost of picking `child:`: `/scope` needs edits at
`skills/scope/references/state-schema.md:81`,
`skills/scope/references/phases/phase-1-discovery.md:422-424`, and the graded
eval strings at `skills/scope/evals/evals.json:111` and `:116` (both of which
spell out `{ name: prd, reason: ... }` inside `expected_output` prose). Five
sites, all mechanical. Cost of picking `name:` instead: two `/charter` sites
plus two graded eval strings. Either is small; the point is that leaving both is
how the divergence persisted this long.

---

## Summary of the recommended edit surface

`references/parent-skill-pattern.md`:

- Insert the mandatory-steps/post-hoc-reduction statement at the head of
  `## Gate Vocabulary`, after line 114.
- Replace lines 127-138 (the ALWAYS declination clause) with the three-property
  restatement, plus a one-sentence no-behavior-change note. No dated retirement
  block.
- Amend line 597's table row and add a per-parent-Adjust sentence after line 603.
- Roster: mechanical at 543, 741, 750, 768-771; **decision needed** at 381-384
  (child roster definition, and whether `/execute`'s koto dispatch is a second
  mechanism or a named variance).

`references/parent-skill-state-schema.md`:

- Replace lines 142-146 with the triad restatement (per-parent constancy stated,
  never-planned category named, `{child, reason, detail?}` shape).
- Bound `chain_skipped[].reason` to a closed enum with a grow-by-PR-review
  extension path.
- Reconcile line 429's "advances `planned_chain`" with whatever constancy the
  schema settles on.

Parent-side follow-on the PRD should scope:

- `/charter`'s internal `/comp` contradiction
  (`phase-state-management.md:131` and `:255` vs `phase-2-chain-orchestration.md:139-144`).
- `/charter`'s Adjust-opt-out at `phase-1-discovery.md:387-388`, which reduces
  the chain before any artifact exists.
- The `{name}` vs `{child}` key divergence, five or four sites depending on
  which key wins.
