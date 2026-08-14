# Decision 4: `/brief`'s roadmap input surface after R13

**Question.** R13 settles that `/brief` records no `upstream:` while keeping both
roadmap input routes. What remains is how to express that so a reader
understands why a flag exists that writes nothing, and so `/brief`'s own
contract does not read as self-contradictory.

**Recommendation: Option A**, with three consequential edits the option implies
and that the other options were the only way of avoiding: the flag's basename
rule is re-based onto a reason that survives, one of the three ordered checks is
dropped, and one is subsumed.

---

## 1. What the input actually delivers (unchanged under every option)

`skills/brief/references/phases/phase-1-discover.md:40-59`, "Mode: Upstream
ROADMAP":

> The user invoked `/brief <path>` where `<path>` resolves to a
> `docs/roadmaps/ROADMAP-*.md` file inside the repo. This is the common entry:
> the roadmap named the feature, and the brief frames it before requirements
> start.
>
> 1. Load the upstream ROADMAP and find the feature this brief frames. Read its
>    line-item description and any sequencing rationale around it.
> 2. Draft a problem candidate: what problem does this feature solve for a user?
>    A roadmap line item names *what* gets built; the brief names *why it matters
>    to a user*. Pull the why out of the roadmap framing and state it as a
>    problem.
> 3. Draft an outcome candidate: what should a user be able to do, or stop having
>    to do, once the feature ships? [...]
> 4. Note the journeys the feature plausibly serves [...]
>
> Present the problem and outcome candidates to the user in a single message.
> [...] **Do not prompt through every dimension — the roadmap carries the naming
> load.**

Phase 1 also persists the reading as a first-class output
(`phase-1-discover.md:146-147`): `## Grounding Anchor` / `<upstream ROADMAP path,
OR "conversation only">`. And Phase 2 re-reads the roadmap directly
(`phase-2-draft.md:33`, "The upstream ROADMAP if Phase 0 recorded one").

The value is therefore substantial and entirely on the read side: the roadmap
supplies the problem/outcome candidate that is otherwise extracted by
interrogating the author, and the difference between the two entry modes at
Phase 1 is "the roadmap carries the naming load" versus a four-step directed
conversation. R13 removes nothing from this. That is the single most important
fact for the write-up: the input's whole value was always the Phase 1 grounding,
and the `upstream:` write was a side effect of it, not its purpose.

## 2. The `/strategy` precedent — the model Option A follows

`skills/strategy/references/phases/phase-0-setup.md:110-134`, the section titled
**"Reading a document vs. recording it as `upstream`"**:

> Both path modes read the file they are handed. Only one of them ever writes
> that path into the draft's `upstream:` frontmatter field, and the two acts are
> not the same act.
>
> - A **VISION is read and recorded.** `upstream:` names the strategy's
>   immediate neighbour one level up the strategic chain (VISION -> STRATEGY ->
>   ROADMAP), and a VISION is exactly that. It reaches Phase 0 either as a
>   positional path (Input Mode 3) or as the `--upstream` flag's value; both
>   routes are validated identically and both land in `## Recorded Upstream`.
> - A **PRD is read only.** It grounds the Phase 1 conversation and informs the
>   bet, and there it stops. [...] Record it as the strategy's parent and a
>   reader who follows `upstream:` looking for the altitude above lands below
>   where they started instead [...]
>
> Grounding a strategy in a PRD stays supported -- an author holding a feature
> PRD who wants the medium-term bet behind it has a real strategy to write. What
> the PRD never becomes is the recorded parent. When a PRD grounds the bet and no
> VISION sits above it, the draft omits `upstream:` entirely and names the PRD in
> Strategic Context prose, which is where the grounding is legible to a reader
> anyway.

**Does `/strategy` accept the grounding PRD positionally or by flag? Positionally,
and never by flag.** Stated three times:

- `phase-0-setup.md:77-80`: "`--upstream` never carries a grounding PRD. The
  flag's value is what Phase 2 writes into `upstream:`, and a PRD is never
  recorded there [...] A PRD grounds the bet by being passed positionally, as
  Input Mode 4."
- `phase-0-setup.md:184-188`: "A `--upstream` value runs the same five steps with
  one difference: its basename MUST start with `VISION-`. `PRD-` is not accepted
  on the flag, because the flag records and a PRD is never recorded; an author
  holding a PRD passes it positionally instead."
- `phase-0-setup.md:91`, the entry-mode table row: **Grounding PRD** | `$ARGUMENTS`
  resolves to an existing file under `docs/prds/` | Phase 1 derives the bet
  candidate from the PRD's content.

The write site, `skills/strategy/references/phases/phase-2-draft.md:82-94`:

> `upstream:` takes a VISION and nothing else. [...] Read `## Recorded Upstream`
> from `wip/strategy_<topic>_context.md` and write that value: Phase 0 already
> resolved it, and it is `none` in every mode but upstream-VISION.
>
> When Phase 0 recorded a grounding PRD instead, omit the field. Do not
> substitute the PRD path — the PRD grounded the bet and belongs in Strategic
> Context prose, but as an `upstream:` value it would point a chain walk down into
> the tactical chain rather than up. **Omitting is the correct shape, not a gap:**
> the field is optional precisely so a strategy grounded in something other than a
> VISION has a right answer available.

And the mechanism that makes it legible to the *author at runtime* rather than
only to a reader of the skill — `phase-0-setup.md:302-315`, step 0.6:

> In grounding-PRD mode the two lines differ, and that is worth saying out loud
> rather than letting the author discover it in the frontmatter later:
>
> > Grounding: `docs/prds/PRD-<name>.md`. Recorded upstream: none -- the PRD
> > grounds the bet but `upstream:` takes a VISION, so the draft omits it.

Backed by two state keys that exist solely to hold the distinction
(`phase-0-setup.md:267-272`): `## Grounding Path` and `## Recorded Upstream`,
with the disambiguating note at `:291-296` — "The two keys differing is what
distinguishes a grounding PRD (grounding set, upstream `none`) from a
flag-supplied VISION (both set to the same path)."

### How closely `/brief` can mirror it

Very closely on structure, with **one exact inversion that must be stated, not
smoothed over**.

Mirrors directly:
- The named section. `/brief` Phase 0 gets its own "Reading a document vs.
  recording it as `upstream`" section in the same position (end of 0.1), stating
  that both routes read and neither records.
- The state-file shape. `/brief`'s context file today carries a single
  `## Upstream Path` key (`phase-0-setup.md:264-265`), described at `:159` as
  what "Phase 2 writes into the BRIEF's frontmatter." Rename it `## Grounding
  Path`. **Do not add a `## Recorded Upstream` key set permanently to `none`** —
  `/strategy` needs two keys because it has two outcomes; `/brief` has one
  outcome and a second key would be dead weight that invites a future
  implementer to fill it.
- The 0.6 announcement. `/brief`'s 0.7 confirm-setup message
  (`phase-0-setup.md:293-299`) already prints `Upstream: <path or "none">`.
  Re-word to `Grounding: <path>. Recorded upstream: none — the roadmap grounds
  the framing, but a BRIEF heads its own lineage, so the brief records no
  upstream.` This line is also where R12's announcement obligation is discharged
  (see §7).

The inversion: **`/strategy`'s distinction is per-input-type, `/brief`'s is
per-artifact-type.** `/strategy` reads-and-records a VISION and reads-only a PRD,
so the flag can mean "record this" and the positional slot can mean "read this,"
and the basename rule can police the boundary. `/brief` reads-only *everything*,
so both routes carry the same meaning and the flag/positional split carries no
semantic load at all — it is purely about slug independence (§4). The write-up
should say this plainly: *`/brief`'s upstream field is empty because of what a
BRIEF is, not because of what it was handed.* That framing also makes R5's empty
legal-parent set for BRIEF the reason, which is checkable, rather than leaving
the reader to infer a per-input rule that does not exist.

## 3. The `/comp` precedent, and the reported missing reason

`/comp` accepts `--upstream` (`skills/comp/SKILL.md:17` argument-hint,
`SKILL.md:115-117` Input Mode 3), reads it, and records nothing. The read site,
`skills/comp/references/phases/phase-1-scope.md:29-33`, "## 1.4 Upstream
Injection":

> If Phase 0 recorded an upstream path (from `--upstream` or the parent
> sentinel), read it now and let it sharpen the competitive question and the
> slice. **Do not copy upstream content into the COMP; use it to frame.**

**Verified: the non-recording has no stated reason anywhere.** Exhaustive grep
over `skills/comp/` returns nine hits total, all listed here:

| Location | Text |
|---|---|
| `SKILL.md:17` | `argument-hint: <topic-slug> [--upstream <path>]` |
| `SKILL.md:115` | "treat the named artifact as the upstream for the new COMP; derive the competitive question candidate from it during Phase 1" |
| `SKILL.md:131` | "Phase 0 reads it (optionally) for upstream injection and resume context" |
| `phase-0-setup.md:17` | "**`--upstream <path>`** — record the upstream artifact path for Phase 1." |
| `phase-0-setup.md:95` | "an upstream artifact path **to record in the COMP frontmatter's context**," |
| `phase-0-setup.md:118` | "Phase 0 produces: the validated topic slug, the resolved visibility, the optional upstream path [...]" |
| `phase-1-scope.md:31,33,39` | the injection step quoted above, plus "and any upstream framing" in the wip/ output |

Not one of them says why nothing is written, and `references/comp-format.md`
never mentions `upstream` at all. The format is unambiguous
(`comp-format.md:12-26`):

> ```yaml
> schema: comp/v1
> status: Draft
> problem: | ...
> scope: | ...
> ```
> Required fields: `status`, `problem`, `scope`. **There are no optional
> frontmatter fields.**

So `/comp` is a second read-only-`--upstream` precedent, but a weaker one than
`/strategy`: it is read-only *by omission* rather than by decision. And
`phase-0-setup.md:95` is worse than silent — it is **wrong**. "an upstream
artifact path to record in the COMP frontmatter's context" asserts a frontmatter
record that the format forbids twice over (no `upstream` field; no optional
fields at all). `phase-0-setup.md:17`'s "record the upstream artifact path for
Phase 1" is the same confusion in milder form: it means "retain in `wip/` state,"
but reads as "record in the artifact."

**Should this design supply the missing reason for `/comp`?** Partly. Split it:

- **Do fix `phase-0-setup.md:95` and `:17`.** These are not a missing rationale,
  they are a false statement about a committed field, and it is precisely the
  read-versus-record confusion this design exists to eliminate. One clause each.
  Cost is two lines; leaving it means shipping a design whose whole thesis is
  "reading and recording are different acts" alongside a sibling skill that says
  a read is a record.
- **Do not write `/comp` a "Reading a document vs. recording it" section.**
  `/comp` produces no illegal link (it produces no link), R11-R13 do not reach
  it, and COMP's legal-parent set is empty in R5 for a structural reason — the
  type has no upstream field to be legal or illegal. The reason it records
  nothing is one sentence long and belongs in `comp-format.md` beside the field
  list, not in a phase file: *COMP has no `upstream:` field — a competitive
  survey is not a chain member — so a supplied `--upstream` grounds the
  competitive question and is not recorded.*

If the design's scope discipline says even that is out of bounds, the fallback is
to say so explicitly in Alternatives ("`/comp`'s unstated reason is a known gap;
it produces no illegal link, so it is left"). Silence is the one disposition to
avoid, because a reviewer who finds `/comp` after reading this design will
reasonably assume it was missed.

## 4. The `PRD-` rejection message

`skills/brief/references/phases/phase-0-setup.md:160-175`:

> **A `PRD-` basename gets its own rejection.** A PRD is not a wrong-artifact
> accident the way a DESIGN or a PLAN path is — it is the artifact directly
> downstream of the brief, and pointing `/brief` at it inverts the chain. Reject
> with:
>
> > `<path>` is downstream of a BRIEF, not upstream of it. The tactical chain
> > runs ROADMAP → BRIEF → PRD: a PRD's requirements are written from the brief's
> > problem, outcome, journeys, and scope boundary, so deriving that framing back
> > out of the PRD inverts the chain. Write the brief from the feature topic
> > (`/brief <topic>`) or from the ROADMAP entry that names it (`/brief
> > docs/roadmaps/ROADMAP-<name>.md`), then point the PRD at the brief.
>
> Stop there. Do not offer to proceed with the PRD as upstream anyway. **The same
> rejection fires when the `PRD-` basename arrives as the `--upstream` value: the
> flag records, and a recorded PRD inverts the chain whichever route it took to
> get there.**

Duplicated verbatim at `skills/brief/SKILL.md:120-128`, and the surrounding
prose at `SKILL.md:143-146` carries the same justification: "The value must name
a ROADMAP: the same basename rule Input Mode 3 enforces applies to the flag, PRD
rejection included, **because both feed the same recorded `upstream:` field.**"

**Does the message survive? Yes — the *message* is untouched, but two sentences
of *surrounding justification* are now false and must change.**

The message's own reasoning is chain inversion at the level of derivation: "a
PRD's requirements are written from the brief's problem, outcome, journeys, and
scope boundary, so deriving that framing back out of the PRD inverts the chain."
That is an argument about what Phase 1 would be asked to do — reverse-engineer
framing from requirements — and it is entirely independent of what gets written
to frontmatter. Under R13 it gets *stronger*, not weaker: recording was never the
harm the message described, and now nothing distracts from the derivation
argument. Every clause of the quoted rejection remains accurate, including the
closing "then point the PRD at the brief," which R5 confirms (PRD's legal parents
are `{BRIEF}`).

Two changes are required:

1. `phase-0-setup.md:173-175`: "the flag records, and a recorded PRD inverts the
   chain whichever route it took to get there" — the premise is now false. Replace
   with the derivation reason: *both routes feed the same Phase 1 derivation, and
   a PRD inverts it whichever route it took to get there.*
2. `SKILL.md:145-146`: "because both feed the same recorded `upstream:` field" —
   same fix: *because both feed the same Phase 1 derivation.*

One watch item on the message body. AC line: "No file under `references/` or
`skills/*/references/` documents a ROADMAP as a legal upstream for a BRIEF, a
PRD, or a DESIGN." The rejection contains "The tactical chain runs ROADMAP →
BRIEF → PRD". That is a claim about authoring order, not about the `upstream:`
field, and it stays true — R5.2 removes the *link*, not the *sequence*, and
`/brief` still takes a roadmap as input. It should survive a careful reviewer.
A literal grep for `ROADMAP` near `BRIEF` will hit it, so the design should say
in advance that this line is intentionally retained and why. If a reviewer
objects, the loss-free reword is "a PRD is written from a brief's framing, not
the other way round," which drops the arrow and keeps the whole argument.

Note also `references/pipeline-model.md:137-139` — "The Roadmap is where the
strategic chain hands off to the tactical one; **`/brief` crosses that boundary
by taking a Roadmap as its upstream**, and no strategic document reaches past
the Roadmap" — which R5.2 requires rewriting regardless (D3's territory, flagged
here because the sentence is the canonical source of the framing this decision
is re-expressing). Its replacement is R5.2's own words: the crossing is recorded
on the PLAN alone.

## 5. The `ROADMAP-` basename enforcement — does its reason still hold?

The rule, `skills/brief/references/phases/phase-0-setup.md:152-154`, step 5 of
canonicalization:

> Verify the basename starts with `ROADMAP-`. **Other prefixes indicate the user
> pointed at the wrong artifact type and the problem/outcome derivation will
> misfire.**

The reason cited in the question comes from the parent skills.
`skills/scope/references/phases/phase-0-setup.md:155-165`:

> **Enforce the basename.** The canonical path's basename MUST start with
> `ROADMAP-` [...] Inbound validation enforces the basename even though an
> outbound hand-off does not, and the asymmetry is deliberate: outbound, the
> parent hands over an artifact it just watched a child produce and whose type it
> therefore knows; inbound, it is routing on a string the author typed. **A wrong
> type inbound is caught nowhere downstream — `/brief` would record a PRD or a
> DESIGN as the feature's upstream, inverting the chain it sits in, and nothing
> would say so.**

`skills/charter/references/phases/phase-0-setup.md:226-241` is the same paragraph
for `VISION-`/`/strategy`, ending "`/strategy` would record a ROADMAP or a PLAN
as the strategy's parent, the chain head would be framed against the wrong
altitude, and nothing would say so."

**Answer: enforcement survives, and the reason for it gets stronger — but the
sentence stating that reason in `/scope` is now false and must be rewritten.**

Three parts:

**(a) The *stated* reason dies at `/scope`.** "`/brief` would record a PRD or a
DESIGN as the feature's upstream" names a consequence R13 makes impossible.
Leaving that sentence in place is exactly the self-contradiction this decision
question exists to prevent, and it sits in the *parent* skill, where a reader
tracing why the flag is policed will land first. `/charter`'s twin is unaffected
— it is about `/strategy` and `VISION-`, and `/strategy` does still record.

**(b) `/brief`'s own reason never depended on recording, and it is the one to
promote.** `phase-0-setup.md:153-154` predates the linking argument and says
nothing about frontmatter: a wrong prefix means "the problem/outcome derivation
will misfire." Under R13 that is the *entire* remaining function of the input
(§1), so the misfire reason now covers 100% of the input's value rather than
part of it. `/scope`'s sentence becomes: *a wrong type inbound is caught nowhere
downstream — `/brief` would derive the feature's problem and outcome from a PRD's
requirements or a DESIGN's decisions, and nothing would say so.*

**(c) The subtle part: the failure mode gets worse, so the check gets more
important, not less.** Under today's behaviour a wrong-type input leaves a
visible artifact — `upstream: docs/designs/DESIGN-x.md` in committed frontmatter,
which a reviewer can see, `git log` can find, and (after this very PRD) R6's
direction check will flag as an error. Under R13 a wrong-type input leaves **no
trace at all**. The roadmap path never reaches the BRIEF; it appears only in
`wip/brief_<topic>_discover.md`'s `## Grounding Anchor`, which wip-hygiene
deletes before the PR can merge. The only evidence that a brief was framed off a
DESIGN would be the framing itself reading oddly, which is a Phase 4 content
judgment, not a check.

So R13 converts the wrong-type input from *a defect the validator catches* into
*a silent defect nothing catches*, and the Phase 0 basename rule goes from being
one of two guards to being the only guard. That is the direct answer: the rule's
justification does not merely survive the removal of recording — it is
load-bearing in a way it was not before, and the design should say so in one
sentence rather than let a reader assume the rule is vestigial.

**Corollary.** The same argument means Input Mode 3's basename rule and the
flag's basename rule must stay aligned. They already are
(`SKILL.md:143-146`); only the justification clause changes.

## 6. The three ordered checks

`skills/brief/references/phases/phase-0-setup.md:177-197`:

> Two further checks apply to a `--upstream` value, in this order, **before it is
> recorded**:
>
> - **Not under `wip/`.** Reject. `wip/` artifacts are non-durable — the
>   wip-hygiene cleanup deletes them before the PR can merge — so **the recorded
>   `upstream:` would point at a file that disappears.** Name the canonical
>   location in the rejection.
> - **Tracked by git.** Run `git ls-files -- <path>`. An empty result on a path
>   inside the working tree means the file is not committed; reject, naming the
>   untracked path.
>
> A cross-repo value in the `owner/repo:path` form [...] skips canonicalization
> and the tracked-by-git check, keeps the `ROADMAP-` basename rule on its file
> component, **and is governed by the visibility rule Phase 2 applies when writing
> frontmatter (a public BRIEF omits a private upstream rather than naming it).**

`/brief` states two; the third (private-upstream omit) lives at the write site,
`phase-2-draft.md:80-90`. The canonical three-check statement is
`skills/scope/references/phases/phase-0-setup.md:167-207`, and the source it
cites is `skills/prd/references/phases/phase-3-draft.md:37-52`, whose preamble
is decisive for this question:

> **Validate upstream:** If a path was detected, run these checks in order
> **before storing it. These are hard-stops -- do not write a failing value into
> frontmatter**

**Every one of the three is framed by its own source as a record-time check.**
That is the fact to reason from, and it means none of them can be carried over
unexamined.

Note also the asymmetry that already exists inside `/brief` today: the two checks
apply "to a `--upstream` value," so `/brief`'s **positional** Input Mode 3 has
never run them. A positional roadmap gets canonicalization, existence, and the
`ROADMAP-` basename, and nothing else. `/strategy` is identical — its grounding
PRD, the read-only input, runs the five canonicalization steps and neither of the
two further checks (`strategy/phase-0-setup.md:166-199`). **The corpus already
encodes the rule this decision needs: read-only inputs get path-safety checks;
recorded inputs additionally get durability checks.** Under R13 the flag becomes
a read-only input, so it should converge on the positional route's check set —
not the other way round.

### Check 1 — under `wip/`: **keep, on a re-based reason**

Stated reason ("the recorded `upstream:` would point at a file that disappears")
is dead: nothing is recorded, and the grounding path is written only to
`wip/brief_<topic>_discover.md`'s `## Grounding Anchor`, itself deleted by
wip-hygiene cleanup. No committed artifact ever references it, so the
workspace-wide wip-hygiene rule has no purchase here either.

Keep it anyway, for a reason that is real and independent: **a ROADMAP never
legitimately lives under `wip/`.** `wip/` holds workflow intermediates —
`wip/brief_<topic>_context.md`, `wip/scope_<topic>_state.md`, research verdicts.
A path matching `wip/**/ROADMAP-*.md` is therefore in the same family as a
wrong-*type* input: it is a mis-pointed argument the author can fix by naming the
canonical path, and grounding a durable brief's problem statement in a scratch
draft that will not exist by review time makes the framing's provenance
unreproducible. The check costs nothing because it rejects no legitimate input.

Re-word to: *`wip/` holds workflow intermediates, not artifacts. A ROADMAP under
`wip/` is a mis-pointed path; name the canonical location.* Drop the "the
recorded `upstream:` would point at a file that disappears" clause.

### Check 2 — tracked by git: **drop**

This is the one genuine behavioural change the decision should make, and it is
where the question's hint lands. The stated reason —
`scope/phase-0-setup.md:181-182`, "An untracked upstream is durable to nobody but
this working copy" — is a durability argument about a *recorded link*, and it has
no referent once no link is recorded. There is no independent reason underneath
it the way there is for check 1.

The cost of keeping it is concrete and paid by a normal workflow. An author who
has just written `docs/roadmaps/ROADMAP-x.md` and has not committed it yet —
walking the chain forward in one sitting, precisely the sitting `/scope` and
`/charter` exist to support — is hard-rejected from grounding a brief in a file
that is sitting on disk, correctly located, and perfectly readable. Under the old
rule that rejection was right: the link would have resolved for nobody but them.
Under the new rule the file is only being *read*, and what survives into the
commit is the brief's own prose. The PRD's own reasoning closes this: "'Absorb
the context' is the self-containment each format already requires" — the brief's
Problem Statement "must let a cold reader grasp the gap 'without having to open
the upstream roadmap'." If the framing is absorbed, the input's durability stops
mattering.

Precedent confirms the shape rather than merely permitting it: `/strategy`'s
grounding PRD — its read-only input — runs no tracked-by-git check, and neither
does `/brief`'s own positional Input Mode 3. Dropping check 2 from the flag makes
`/brief`'s two routes validate identically, which is the correct end state once
R13 makes them mean the same thing, and removes an inconsistency that exists
today.

**Cost to name honestly.** `scope/phase-0-setup.md:167-170` promises the three
checks "are reused rather than reinvented, so an author sees one behavior from
the flag whichever skill they hand it to." That promise narrows. Two mitigations,
both real: (i) the rule remains stateable in one line — *the durability checks are
record-time checks; a skill that only reads its `--upstream` runs the path-safety
checks and not the durability checks* — so a reader gets a principle, not an
exception list; and (ii) under R14 `/scope` hands the roadmap to `/plan`, which
**does** record it, so `/scope`'s own three checks stay live and unchanged, and
every chain-driven `/brief` invocation is still fed a pre-validated path. The
relaxation is observable only on a standalone `/brief --upstream` against an
uncommitted roadmap — exactly the case it is meant to unblock.

Update `scope/phase-0-setup.md:167-170` to say the checks are shared *wherever
the flag records*, and update `/brief`'s Phase 0 quality checklist
(`phase-0-setup.md:313-315`), which currently asserts "is not under `wip/` and is
tracked by git."

### Check 3 — public document naming a private upstream: **subsumed, not deleted**

`scope/phase-0-setup.md:183-188` and `brief/phase-2-draft.md:80-90`. Its action
is "STOP recording: do not write the field, tell the author it is being omitted
and why." Under R13 the field is omitted on every run, so the check's action is
unconditionally already taken. There is no branch left to take.

It is subsumed rather than dropped, and the distinction matters for the write-up:
its *obligation* migrates rather than vanishing. Two pieces survive elsewhere and
neither should be touched:

- **The leak risk**, which was always adjacent to the link rather than identical
  to it, is owned by `brief/phase-2-draft.md:43-58` (step 2.2, the
  private-upstream sanitization warning: "Phase 2 will paraphrase rather than
  quote when carrying content forward") and by the Phase 4 structural-format
  reviewer. Reading a private roadmap into a public brief's prose is still a live
  hazard under R13 — arguably *more* live, since the prose now carries the whole
  load. Step 2.2 stays exactly as written.
- **The announcement**, which R12 requires. Today it fires only in the private
  case; under R13 it becomes unconditional (§7).

`/scope`'s check 3 stays as-is and stays load-bearing, because `/scope` now hands
the roadmap to `/plan` and a PLAN records it.

### Summary

| Check | Stated reason | Under R13 | Disposition |
|---|---|---|---|
| 1. Under `wip/` | recorded field would dangle after cleanup | dead as stated | **Keep**, re-based: `wip/` holds intermediates, not artifacts; rejects no legitimate input |
| 2. Tracked by git | "durable to nobody but this working copy" | dead, nothing underneath | **Drop** — matches the read-only precedent (`/strategy`'s grounding PRD, `/brief`'s own Input Mode 3) and unblocks the same-sitting chain |
| 3. Public naming private | stop recording, announce | action unconditionally taken | **Subsumed**; leak risk stays with Phase 2 step 2.2, announcement generalizes per R12 |

## 7. Where R12's announcement lands

R12 requires the producing skill to "read it for context, omit the field, and
announce the omission and its reason in its run output," graded by the eval
suite. The `/strategy` precedent puts it in the Phase 0 confirm-setup message
(`strategy/phase-0-setup.md:310-315`), which is the right home for `/brief` too:
it fires before drafting, so the author can correct course, and `/brief` already
prints an `Upstream:` line there (`phase-0-setup.md:293-299`).

Shape:

> Setting up `/brief` for topic `<topic>`.
> Entry mode: `<mode>`. Visibility: `<visibility>`.
> Grounding: `docs/roadmaps/ROADMAP-<name>.md`. Recorded upstream: none — the
> roadmap grounds the framing, but a BRIEF heads its own tactical lineage, so the
> brief records no upstream.

One consequence to state: under R13 the announcement fires on **every** run with
a roadmap, not only the private-upstream one. That is what makes it gradeable by
the eval suite as R22 requires — `upstream-roadmap-grounding` and `upstream-flag`
are both rewritten to assert the grounding happened and the announcement fired
(their current fifth expectations, `evals.json:37` "Plan declares the ROADMAP
path as the BRIEF frontmatter upstream field" and `:186` "records the path as
`## Upstream Path` and writes it into the BRIEF frontmatter's `upstream:` field",
are the two lines R22 disposes of).

## 8. Options B, C, D

R13 settles that both routes survive, so these are counterfactuals. They are
evaluated to show the recommendation is not merely inherited.

### Option B — remove `--upstream`, keep only positional Input Mode 3

**Fails mechanically, independent of R13.** `/scope` hands the roadmap down as
`/brief <topic-slug> --upstream <roadmap-path>`
(`scope/phase-2-chain-orchestration.md:170`,
`scope/SKILL.md:141`). With no flag, `/scope` must pass the roadmap positionally,
which derives the slug from the roadmap's basename
(`brief/phase-0-setup.md:120-124`, derivation rule 1). `scope/evals/evals.json:345`
states the consequence outright:

> Passing the ROADMAP positionally would have named the brief after the roadmap
> and broken the R20 file-existence check, which looks for
> `docs/briefs/BRIEF-inline-diff.md`.

And the flag exists precisely because the two names normally differ —
`brief/SKILL.md:136-139`: "Input Mode 3 is the special case where they do [...]
which only works while the feature's topic and the roadmap's filename coincide. A
roadmap normally sequences several features, so they usually do not." Option B
would leave a roadmap groundable only when it sequences exactly one feature named
after it. Rejected.

### Option C — remove Input Mode 3, keep only the flag

Mechanically coherent: `/scope`'s hand-down is untouched, slug independence is
preserved by construction, and it has a superficial tidiness — one route for one
meaning.

Rejected on three counts. It contradicts R13's settled text ("its roadmap input
mode and its `--upstream` flag are unchanged as *inputs*"). It removes a working
convenience for zero gain — the mode's cost is one row in an entry-mode table and
one branch in Phase 1's router, and nothing about it is made incorrect by R13,
since it was never the route that recorded anything special. And it points the
wrong way: the positional mode is the route that *already* behaves the way R13
wants (read-only, no durability checks), so it is the model, not the casualty.
Option A converges the flag onto Input Mode 3's behaviour; Option C deletes the
exemplar.

### Option D — remove both, paste roadmap context into the Phase 1 conversation

Rejected. It discards the value in §1 wholesale: Phase 1's Upstream ROADMAP mode
loads the roadmap, finds the feature's line item, reads the sequencing rationale
around it, and derives the problem/outcome candidate, so that "the roadmap
carries the naming load." Pasting substitutes a lossy human summary for a file
read, at the exact moment the skill is trying to avoid a smuggled solution
(`phase-1-discover.md:106-118`, the problem-vs-solution check) — and a pasted
paraphrase is where a solution gets smuggled in. It also breaks `/scope`'s
hand-down entirely, since a parent skill has no conversation to paste into. And
it inverts the PRD's own diagnosis: R13's problem is that the brief *recorded* a
roadmap, never that it *read* one.

## 9. Recommendation, consolidated

Option A, expressed as follows.

1. **`/brief` Phase 0 gains a "Reading a document vs. recording it as
   `upstream`" section**, modelled on `strategy/phase-0-setup.md:110-134`, stating
   that both routes read, neither records, and that the reason is what a BRIEF is
   (R5's empty legal-parent set) rather than what it was handed.
2. **`## Upstream Path` is renamed `## Grounding Path`** in the context file. No
   `## Recorded Upstream` key is added.
3. **Step 0.7's confirm message announces the omission and its reason** on every
   grounded run — discharging R12, gradeable per R22.
4. **`ROADMAP-` basename enforcement is kept on both routes**, re-based onto the
   derivation-misfire reason `/brief` already states, with the observation that
   the check is now the *only* guard against a wrong-type input, since nothing
   reaches frontmatter for a reviewer or the validator to catch.
5. **Check 1 (`wip/`) kept and re-worded; check 2 (git-tracked) dropped; check 3
   subsumed**, with Phase 2 step 2.2's private-upstream sanitization warning
   explicitly retained.
6. **Phase 2's step 2.3 write site** loses the conditional `upstream:` line and
   the private-omission paragraph, and states instead that a BRIEF carries no
   `upstream:` field, citing R5's empty parent set.
7. **Consequential edits outside `/brief`:** `scope/phase-0-setup.md:162-165`
   (the "would record a PRD or a DESIGN" justification) and `:167-170` (the "one
   behavior from the flag" promise); `brief/SKILL.md:145-146` and
   `brief/phase-0-setup.md:173-175` (the "because both feed the same recorded
   field" clauses); `brief/phase-0-setup.md:313-315` (quality checklist).
   `/charter`'s twin paragraph is untouched.
8. **`/comp`:** correct `phase-0-setup.md:95` and `:17`, and add one sentence to
   `comp-format.md`'s field list. Do not give `/comp` a read-vs-record section.
