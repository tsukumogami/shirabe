# Decision D3: the Option D amendment

## The objection and the two-part answer

`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:839-847`, inside
the existing `## Amendment — 2026-08-15` section:

> Option D — "make DESIGN absorbable into PLAN so the shortest outcome
> stays reachable" — was rejected here on the ground that the PLAN is
> deleted, so the move "trades a durable audit trail for a shorter run and
> loses the record of why the work happened." That objection was answered
> rather than overruled. The record of *why* belongs in the code, kept
> current as the code changes, which is now a standing instruction in
> `/work-on` and independent of what any chain decided. And the record of
> *what happened* is `docs/folds.md`, which survives on the default branch
> whether or not any chain artifact does.

Note the two verbs. The objection was **answered**, not overruled — so the
amendment cannot simply say the answer stopped working; it has to say what
answers it now. That is exactly what R10a
(`docs/prds/PRD-fold-record-removal.md:205-212`) requires and what AC16
(`:329-332`) checks for in two locatable parts.

Surrounding context, same section, `:849-856`: Option B (an explicit guard
refusing to reduce below one durable artifact) is *still forbidden*, on the
ground that it would decide a fold from the artifact set rather than from the
two documents at the hop. Any new amendment prose that gestures at "we should
keep at least one artifact" collides with a live prohibition, not just with
Option D.

## Does half one still hold?

Yes, and it is stronger than the amendment's one-line summary suggests.

`skills/work-on/references/phases/phase-4-implementation.md:32-34`, in the
implementation cycle's "Write Code" step:

> - **Record why the code is shaped this way, next to the code** — the
>   decision the diff cannot show, and keep it current when the code
>   changes

And at `:43-48`, the paragraph that makes it unconditional:

> This holds regardless of what documents the work leaves behind. A chain
> may fold its scoping artifacts away and leave the code as the record; it
> may keep all four. Either way this instruction is the same, because the
> code is the thing that outlives every other artifact and the thing the
> next person reads first.

That paragraph was written *for* this exact case. It is the shipped discharge
of `PRD-scope-artifact-persistence.md` R23 (`:271-275`), which also requires the
instruction be enforced "by naming it in the maintainer reviewer's existing
blocking brief rather than by a new gate." Half one is present, unconditional,
and load-bearing. Nothing in this chain touches it — R14 of the removal PRD
protects the survivor-side trace, and nothing proposes editing `/work-on`.

## What half two uniquely asserted

Walking the DESIGN-into-PLAN sequence against the actual procedure:

1. **The fold.** `skills/scope/references/phases/phase-2-chain-orchestration.md:644-679`
   — step 5 writes the survivor (`upstream:` splice, `absorbed:` declaration,
   the pinned `## Status` line `Absorbed [<name>](<path>); carried in <Heading>.`,
   the contribution section); step 6 appends the `docs/folds.md` row and stages it
   *before* anything is deleted; step 7 `git rm`s the absorbed DESIGN.
2. **The survivor is the PLAN.** `phase-3-exit-finalization.md:369-374`: "The PLAN
   is never a deletion target of a fold… `docs/plans/` is included because the PLAN
   is the survivor at the terminal hop." So immediately post-fold, the PLAN carries
   the full trace, and `absorbed:` accumulates — a PLAN that ate a DESIGN that ate a
   PRD that ate a BRIEF names all three (`phase-2:755-758`).
3. **The cascade deletes the survivor.** `skills/execute/scripts/run-cascade.sh:859-878`
   — step 3 `git rm -f "$PLAN_DOC"`. `skills/execute/SKILL.md:585-589` states it
   plainly: "Post-finalization the PLAN is **GONE** (the cascade `git rm`s it)."
   The cascade writes no fold row; only `/scope`'s judgment ever writes one.
4. **Squash-merge erases the branch.** `docs/folds.md:14-19` and the PRD's own
   amendment (`PRD-scope-consolidation-over-skipping.md:407-413`) — a document
   created and folded away inside one chain never existed on the default branch,
   "and when `/execute` adopts the scoping PR, the same is true of the PLAN."

So half two uniquely asserted exactly one thing: **for the terminal hop, and only
the terminal hop, a default-branch trace that outlives the survivor.** At every
other hop the row is redundant with `absorbed:` + the `## Status` line + the
contribution section, all three enforced at error level — which is precisely the
removal PRD's central finding (`PRD-fold-record-removal.md:52-60`: "For every fold
whose survivor stays on disk, that is false. The exception is real and is treated
as this PRD's central residual").

**What partially replaces it, and what does not.** R8 requires the roadmap
downstream cell to keep the folded-versus-never-ran distinction without the
pointer (`run-cascade.sh:465` today emits `_none (chain folded; see docs/folds.md)_`).
That is a weak carrier and the PRD says so: it only exists where the chain has a
roadmap feature entry, `BRIEF-fold-record-removal.md:34-35` notes "No roadmap
carries that text today," and `run-cascade.sh:502-576` `git rm`s the ROADMAP itself
once all features are Done. So for the DESIGN-into-PLAN hop the honest answer is:
nothing on the default branch. AC17's rejection list (survivor frontmatter alone,
commit trailer, git notes, per-chain file, forge metadata, rotation, per-fold file)
means the design has already committed to *not* naming a substitute carrier — an
amendment that invents one contradicts its sibling document.

## Amendment convention in this corpus

Two exemplars: `PRD-scope-consolidation-over-skipping.md:394` and this design's
`:822`.

- **Heading, exact characters:** `## Amendment — 2026-08-15`. The separator is
  U+2014 EM DASH (`hexdump`: `M-bM-^@M-^T`), space on both sides. Not a hyphen,
  not an en dash. Date is bare ISO-8601, no brackets. Blank line above and below.
- **Pinned opening formula:** one sentence naming the superseding document by
  **bare backticked filename** (no `docs/` prefix — both use
  `` `PRD-scope-artifact-persistence.md` `` / `` `DESIGN-scope-artifact-persistence.md` ``),
  optionally with a relative clause saying what it changed, immediately followed
  by the fixed sentence: *"The original text above is left unedited; this section
  records what no longer holds."* The design variant appends **"and why."**
- **Body unit:** a bolded lead-in naming the affected unit and its fate, in one
  of two observed shapes — `**Decision 8 (the durable-artifact floor) — the
  conclusion is falsified, and the option it rejected is the one now adopted.**`
  or `**R14 (the durable-artifact floor) is superseded.**` or, for a prose claim,
  `**"The commit history is the recovery path" is false as written.**` Then one to
  three short paragraphs.
- **Register:** declarative present tense, no hedging, no "we". Original text is
  quoted in double quotes and left intact. Italics carry the *why* / *what
  happened* distinction. Paths and doc names in backticks. Requirement IDs used
  bare (R14, R20). No bullet lists inside the amendment body — the existing two
  are pure prose.
- **Length:** PRD amendment = 22 lines, two bolded units. Design amendment = 48
  lines, three bolded units. Per unit: 6–14 lines. A single-unit amendment lands
  naturally at 12–18 lines.
- **Withdrawals vs consequences — decisive for D3:** both existing amendments do
  more than withdraw. The PRD's says "The successor's R20 replaces the assumption
  with a mechanism"; this design's says "The conclusion survives on grounds that
  do not depend on it." **Affirmative restatement is already the house style.**
  R10a is asking the new amendment to obey the corpus norm, not to make an
  exception to it.
- **Two hard constraints from the ACs:** the text under the heading must contain
  the literal string `folds.md` (AC15), and `status: Current` must be unchanged
  (AC15). The document will end up with two `## Amendment —` sections, which the
  PRD's Known Limitations already concedes "reads oddly on first encounter."

## Options

Every option below is drafted with the heading and opening formula fixed; only
the body differs. All four contain the string `folds.md` and the italicized
phrase "the record of *why*".

---

### Option 1 — Narrowed carrier, stated as an accepted narrowing

```markdown
## Amendment — 2026-08-16

Superseded in part by `PRD-fold-record-removal.md`, which removes
`docs/folds.md`. The original text above is left unedited; this section
records what no longer holds and why.

**The Option D answer — one half stands, the other is withdrawn, and what
replaces it does not reach every hop.**

The objection was that absorbing a DESIGN into a PLAN "trades a durable
audit trail for a shorter run and loses the record of why the work
happened," and the answer above had two halves.

The first stands unchanged. The record of *why* belongs in the code, kept
current as the code changes, and that is a standing instruction in
`/work-on`'s implementation phase — unconditional, and explicitly the same
whether a chain folds its scoping artifacts away or keeps all four.

The second is withdrawn with the file. What now carries the record of
*what happened* is the survivor: an absorbing document declares the
absorbed path in `absorbed:`, names it in its pinned `## Status`
absorption line, and carries its content in a contribution section — three
error-level checks rather than one unverified row — and the declaration
accumulates, so the last document in a chain names every ancestor folded
into it.

That answers the objection at every hop whose survivor stays on the
default branch, and it does not answer it at the DESIGN-to-PLAN hop, where
the survivor is the PLAN and `/execute`'s cascade deletes it. For that fold
nothing on the default branch records that the DESIGN existed or that the
chain ran at all. That is an accepted cost, argued in
`DESIGN-fold-record-removal.md` rather than discovered; Option D's reversal
stands and the hop stays absorbable.
```

- **Reopens Option D?** No. The closing sentence affirms the reversal and names
  where the reasoning lives.
- **AC16 part 1?** Yes — "The record of *why* belongs in the code… standing
  instruction in `/work-on`'s implementation phase."
- **AC16 part 2?** Yes — names the survivor trace as the carrier and states
  plainly that nothing carries it at the DESIGN-to-PLAN hop.
- **Convention fit:** high. 18 lines of body prose, one bolded unit, pure prose,
  quotes the original. The one deviation: the opening names a PRD where both
  exemplars name the successor artifact type that superseded them — defensible
  since the PRD is the binding document, but naming `DESIGN-fold-record-removal.md`
  would match the design-amends-design precedent better.

---

### Option 2 — The objection re-evaluated as weaker than it looked

```markdown
## Amendment — 2026-08-16

Superseded in part by `PRD-fold-record-removal.md`, which removes
`docs/folds.md`. The original text above is left unedited; this section
records what no longer holds and why.

**The Option D answer overstated what the second half was doing.**

The answer above gave `docs/folds.md` equal weight with the code comment,
as though the audit trail the objection asked for lived there. It did not.
Wherever a fold leaves a survivor, that survivor already declares the
absorbed path in `absorbed:`, names it in its `## Status` absorption line
and carries its content in a contribution section, all three under
error-level enforcement — so the row duplicated a trace that was already
mandatory, and the one row the record ever held duplicated exactly that.

The half that was doing the work is the first, and it is untouched. The
record of *why* belongs in the code, kept current as the code changes, a
standing instruction in `/work-on`'s implementation phase independent of
any chain.

What the record uniquely held was narrower than the answer implied: a
default-branch trace for the one fold whose survivor is itself later
deleted, the DESIGN-to-PLAN hop the cascade cleans up. Nothing carries that
now. The objection was answered on the strength of the code and the
survivor's own declaration; the row was never carrying it.
```

- **Reopens Option D?** No.
- **AC16 part 1?** Yes.
- **AC16 part 2?** Yes, but weakly — "nothing carries that now" is present, and
  the survivor is named as carrier, but the ordering buries both under a
  self-critique.
- **Risk:** the closing move — "the row was never carrying it" — sits close to
  contradicting the removal PRD's own Known Limitations, which calls the
  exception "real" and "the accepted cost of the removal." An amendment that
  reads as minimizing a residual its sibling PRD deliberately conceded creates
  a corpus disagreement. It is also the only option that criticizes the original
  text rather than recording what changed, which cuts against "the original text
  above is left unedited" — the convention records supersession, not authorial
  regret.

---

### Option 3 — Re-justified on different ground: the verdict's own meaning

The named ground: an `absorb` verdict asserts the absorbed content did not
warrant a separate durable artifact, so a durable record of it is in tension
with the verdict that produced it.

```markdown
## Amendment — 2026-08-16

Superseded in part by `PRD-fold-record-removal.md`, which removes
`docs/folds.md`. The original text above is left unedited; this section
records what no longer holds and why.

**The Option D answer's second half is withdrawn, and the reversal rests
on the ground under it rather than on the record.**

The record of *why* belongs in the code, kept current as the code changes:
that half is a standing instruction in `/work-on`'s implementation phase
and is unchanged.

The record of *what happened* was `docs/folds.md`, and it is gone. The
ground the reversal actually stood on is narrower and does not need it: an
`absorb` verdict is the finding that a document's content did not warrant
a durable artifact of its own. A chain that reaches that finding at every
hop has said something about the work, and demanding it leave a durable
row anyway asks the artifact set to contradict the judgment that reduced
it.

What remains true of the record of *what happened* is what the survivor
says. Where a survivor stays on the default branch it declares the
absorbed path in `absorbed:`, names it in its `## Status` line and carries
its content in a contribution section. Where the survivor is the PLAN and
the cascade deletes it, nothing does, and Option D stays reversed on the
ground above rather than on a trace that is no longer there.
```

- **Reopens Option D?** No — it re-anchors the reversal.
- **AC16 part 1?** Yes.
- **AC16 part 2?** Yes.
- **Risk:** the argument slides. `docs/folds.md:21-26` is explicit that the
  record is "of the *operation*, never of the content," precisely so that
  recording a fold does not assert the verdict was partly wrong. Option 3
  borrows that reasoning and applies it to the operation record too, which the
  original text says it does not reach. A reader who knows the file will spot
  it. Also: it is the only option that changes the *justification* for a shipped
  decision, which is a larger claim than R10a asks for.

---

### Option 4 — Split the objection by reader, then answer each (alternative framing)

The objection conflates two readers: one holding a dead path, one asking whether
a chain ran. They have different carriers and different failure modes, and
separating them is what lets the amendment be affirmative about one and honest
about the other.

```markdown
## Amendment — 2026-08-16

Superseded in part by `PRD-fold-record-removal.md`, which removes
`docs/folds.md`. The original text above is left unedited; this section
records what no longer holds and why.

**The Option D answer — the half naming the record is withdrawn; what
replaces it answers one reader and not the other.**

The half that stands: the record of *why* belongs in the code, kept
current as the code changes, a standing instruction in `/work-on`'s
implementation phase that holds whether a chain folds everything away or
keeps all four documents.

The half that is withdrawn named `docs/folds.md` as the record of *what
happened*. That record served two readers who need different things. A
reader holding a path that no longer exists is answered by the document
that absorbed it: the `absorbed:` declaration, the pinned `## Status`
absorption line and the contribution section, all three enforced at error
level and accumulating across hops. That answer is better than the row it
replaces, because it is enforced and sits where the reader already is.

A reader asking whether a chain ran at all is answered only while an
artifact survives. At the DESIGN-to-PLAN hop the survivor is the PLAN, and
`/execute`'s cascade deletes it; the roadmap's downstream cell says the
chain folded where a feature entry exists, and the cascade eventually
deletes the roadmap too. After that, nothing on the default branch records
that the chain ran. Option D's reversal stands — the hop remains absorbable
— and this is its known cost, argued in `DESIGN-fold-record-removal.md`.
```

- **Reopens Option D?** No.
- **AC16 part 1?** Yes.
- **AC16 part 2?** Yes, and most precisely of the four — it distinguishes the
  case that is fully answered from the case that is not, and names the roadmap
  cell's partial coverage and its expiry rather than overclaiming it.
- **Risk:** longest of the four (~24 body lines) and introduces a two-readers
  frame the original text does not use, which is a small amount of new
  conceptual apparatus in a document that is otherwise frozen. The roadmap-cell
  sentence also creates a coupling: if R8's final wording for that cell changes,
  this amendment goes stale.

## Traps

- **The "no longer holds" trap (fails R10a).** Any body reducible to "the second
  half cited `docs/folds.md`, which no longer exists" fails, because the design
  records the objection as *answered rather than overruled*. Withdraw the answer
  without restating one and the sentence at `:842` becomes false about its own
  document. None of the four options above falls into this, but it is the
  cheapest draft to reach for and the default failure mode.
- **The reopening trap (exceeds scope).** Three shapes count as reopening, and
  the third is easy to miss: (a) saying the objection now stands; (b) suggesting
  the DESIGN-to-PLAN hop be re-examined; (c) implying a floor should be restored
  so the terminal fold leaves something. Shape (c) collides with the *live*
  prohibition at `:849-856` against a keep-only guard, not merely with Option D.
  Watch also for the softer version — "for that hop, an author may prefer to
  keep" — which reads as guidance and is functionally a floor.
- **The invented-carrier trap.** Naming a substitute for the DESIGN-to-PLAN gap
  (commit trailer, git notes, forge metadata, the PR itself) contradicts AC17,
  which requires the sibling design to record each of those as *evaluated and
  rejected*. The PR is the most tempting: it does persist, and it is forge
  metadata, which is on the rejection list. Option 3 comes nearest to this by
  substituting an argument for a carrier; Options 1 and 4 stay clear.
- **Overclaiming the roadmap cell.** It is real but conditional — no feature
  entry, no cell (`BRIEF-fold-record-removal.md:34-35`: no roadmap carries the
  text today), and `run-cascade.sh:502-576` deletes the roadmap once all features
  are Done. Only Option 4 mentions it, and it mentions the expiry in the same
  breath, which is the safe way to include it.
- **Mechanical misses that fail AC15 silently.** Hyphen instead of U+2014 in the
  heading; a date before the landing date; and dropping the literal string
  `folds.md` from the body while paraphrasing "the fold record."

## Recommendation input

The real choice is between **restating the answer with a narrowed carrier**
(Options 1 and 4) and **re-arguing the objection** (Options 2 and 3). Only the
first pair does what R10a's verb asks — "state affirmatively what now answers
the objection" — without also editing the strength of a shipped decision's
justification. Options 2 and 3 both change the standing of an argument the
design already settled, which is more than an amendment section is for and
creates a second thing for a reviewer to check.

Between 1 and 4: Option 1 is the literal read of R10a and closest in length and
shape to the two existing amendments. Option 4 is more accurate about what is
actually lost — it separates the dead-path reader (fully answered, and better
than before) from the did-this-chain-run reader (answered only until the cascade)
— at the cost of six extra lines and one new frame. If the design wants the
amendment to be checkable against Known Limitations without a reader having to
reconcile them, Option 4 is the closer match to what the PRD concedes at
`:441-447`. If it wants minimum new surface in a frozen document, Option 1.

Two smaller calls the design should make explicitly rather than inherit:

1. **Which document the opening formula names.** Both existing amendments name
   the artifact that superseded them (`PRD-…-persistence.md` in the PRD,
   `DESIGN-…-persistence.md` in the design). By that precedent the design's new
   amendment should open on `DESIGN-fold-record-removal.md`, not the PRD — but
   that document does not exist in the working tree yet, and R11 leaves open
   whether it survives its own chain's DESIGN-to-PLAN hop. If it folds, the
   opening formula points at a path that will not exist. Naming
   `PRD-fold-record-removal.md` is the safe choice; naming both is the accurate
   one.
2. **Whether the amendment names the roadmap cell at all.** Including it is more
   complete and creates a coupling to R8's final wording; omitting it makes the
   "nothing does" statement cleaner and slightly overstated. This is the only
   substantive content difference between Options 1 and 4.
