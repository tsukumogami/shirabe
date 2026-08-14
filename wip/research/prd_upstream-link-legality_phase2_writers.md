# Inventory: what writes `upstream:` into a produced document

Research for the upstream-link-legality PRD. Every citation is
`path:line` relative to the shirabe repo root, against the worktree at
`.claude/worktrees/upstream-link-legality`.

---

## 1. The complete writer set

Ten skills touch the field. Seven write it, two only read it, one
(`/vision`) declares it in its format reference but has no phase step
that populates it.

| # | Skill | Phase file / line | Produces | Records as `upstream:` | Where the value comes from |
|---|---|---|---|---|---|
| 1 | `/vision` | `skills/vision/references/vision-format.md:28`; guidance only at `skills/vision/references/phases/phase-3-draft.md:44` | VISION | parent VISION (project-level only) | Author judgment. No `--upstream` flag, no Phase 0 detection, no positional parent mode. The only unspecified writer. |
| 2 | `/strategy` | `skills/strategy/references/phases/phase-2-draft.md:78` (write); `phase-0-setup.md:116-120` (resolution) | STRATEGY | VISION, and nothing else | Positional VISION path (Input Mode 3) **or** `--upstream` flag. Both land in `## Recorded Upstream` in `wip/strategy_<topic>_context.md`; Phase 2 reads that key. |
| 3 | `/roadmap` | `skills/roadmap/references/phases/phase-3-draft.md:32-38` (detect+validate), `:70-71` (write) | ROADMAP | STRATEGY | `--upstream` flag only. `/charter` passes it on every chain; a standalone author passes it when a STRATEGY exists. |
| 4 | `/brief` | `skills/brief/references/phases/phase-2-draft.md:75` (write); `phase-0-setup.md:141-197` (resolution) | BRIEF | ROADMAP | Positional ROADMAP path (Input Mode 3) **or** `--upstream` flag. Stored as `## Upstream Path` in the context file. |
| 5 | `/prd` | `skills/prd/references/phases/phase-3-draft.md:31-35` (detect), `:37-52` (validate), `:110-112` (write) | PRD | ROADMAP (via flag) or BRIEF (via positional Input Mode 2) | `--upstream` flag, **or** the positional BRIEF path: "When the positional argument is itself a BRIEF path (Input Mode 2), that path is used as the upstream and `--upstream` is not required." (`skills/prd/SKILL.md:85-86`) |
| 6 | `/design` | `skills/design/references/phases/phase-0-setup-prd.md:100-153` (validate), `:163` (skeleton); re-checked at `skills/design/references/phases/phase-6-final-review.md:169` | DESIGN | PRD | The positional PRD path the doc was loaded from in step 0.2. No flag: "**The path the PRD was loaded from (in step 0.2) is the candidate `upstream:` value.**" (`phase-0-setup-prd.md:106-107`) |
| 7 | `/plan` | `skills/plan/references/phases/phase-7-creation.md:162` (multi-pr), `:247` (single-pr); hygiene re-check `:287-315` | PLAN | DESIGN, PRD, or ROADMAP — "`upstream: <source-doc-path>   # design doc, PRD, or roadmap path`" | The positional source-document path, classified into `input_type` at `skills/plan/SKILL.md:237-242`. Direct-topic mode (`input_type: topic`) requires no upstream document. |
| 8 | `/charter` | *(parent — records nothing itself)* `skills/charter/references/phases/phase-0-setup.md:199-289` (validate), `:310` (`consumed_upstream:`) | — (produces STRATEGY + ROADMAP via children) | — | `--upstream` flag, validated then handed to `/strategy` as `/strategy <topic-slug> --upstream <vision-path>` (`phase-2-chain-orchestration.md:229`). Also hands `/roadmap` `--upstream <strategy-path>` for the STRATEGY it just watched a child produce (`phase-2-chain-orchestration.md:419-422`). |
| 9 | `/scope` | *(parent — records nothing itself)* `skills/scope/references/phases/phase-0-setup.md:132-207` (validate), `:262` (`consumed_upstream:`) | — (produces BRIEF→PRD→DESIGN→PLAN via children) | — | `--upstream` flag, validated then handed to `/brief` as `/brief <topic-slug> --upstream <roadmap-path>` (`phase-2-chain-orchestration.md:170`). Also performs the **absorb re-point** (section 4 below). |
| 10 | `/comp` | `skills/comp/references/phases/phase-1-scope.md:24-27` | COMP | **nothing** | Accepts `--upstream` and reads the file, but COMP has no `upstream` frontmatter field at all: "Required fields: `status`, `problem`, `scope`. There are no optional frontmatter fields." (`skills/comp/references/comp-format.md:26-27`) |

`/explore` is a pass-through, not a writer: `skills/explore/references/phases/phase-5-produce-roadmap.md:43-49` detects a VISION in the crystallize artifact and passes it as `--upstream` to `/roadmap`. Its PRD/design/plan handoffs pass no upstream at all (`phase-5-produce-plan.md` has no `--upstream` mention). `/work-on`, `/execute`, and `/inflight` write no `upstream:` field anywhere.

---

## 2. The `--upstream` flag surface, skill by skill

Seven skills accept the flag. The canonical statement of who owns it is
`references/parent-skill-pattern.md:262-265`:

> "`--upstream <path>` is the worked example: `/brief`, `/strategy`,
> `/prd`, `/roadmap`, and `/comp` each own the flag in their own
> contracts, and a parent passing it is using that surface rather than
> extending it. The test separating the two is whether the flag works
> when the parent is absent."

That list names the five children. The two parents (`/charter`,
`/scope`) accept the same token inbound, making seven total.

| Skill | Accepts? | Declared at | Expected basename | What it does with the value |
|---|---|---|---|---|
| `/charter` | yes | `skills/charter/SKILL.md:14` (`argument-hint`), `:120` | `VISION-` (`phase-0-setup.md:228`) | Validates, records in state as `consumed_upstream:`, skips `/vision`, hands to `/strategy` in the flag slot. Never writes a document itself. |
| `/scope` | yes | `skills/scope/SKILL.md:13`, `:122` | `ROADMAP-` (`phase-0-setup.md:155-157`) | Validates, records `consumed_upstream:`, hands to `/brief` in the flag slot. |
| `/strategy` | yes | `skills/strategy/SKILL.md:18`, `:123-141` | `VISION-` only; `PRD-` **rejected on the flag** (`phase-0-setup.md:184-188`) | Stores in `## Recorded Upstream`; Phase 2 writes it to STRATEGY frontmatter. |
| `/brief` | yes | `skills/brief/SKILL.md:19`, `:130-146` | `ROADMAP-` only; `PRD-` rejected with the chain-inversion message (`phase-0-setup.md:160-175`) | Stores in `## Upstream Path`; Phase 2 writes it to BRIEF frontmatter. |
| `/prd` | yes | `skills/prd/SKILL.md:81-86` | none enforced | Stores, validates in Phase 3 step 3.1, writes to PRD frontmatter. |
| `/roadmap` | yes | `skills/roadmap/SKILL.md:165-173` | none enforced (`/charter` notes "the contract accepts the path with no basename enforcement", `charter/.../phase-2-chain-orchestration.md:422`) | Stores, validates in Phase 3 step 3.1, writes to ROADMAP frontmatter. |
| `/comp` | yes | `skills/comp/SKILL.md:17`, `:115-117` | none | **Reads only.** Phase 1.4: "read it now and let it sharpen the competitive question and the slice. Do not copy upstream content into the COMP; use it to frame." (`comp/.../phase-1-scope.md:26-27`) |
| `/vision` | **no** | `skills/vision/SKILL.md:79-87` lists three input modes, none a flag | — | — |
| `/design` | **no** | — | — | Uses the positional PRD path. |
| `/plan` | **no** | — | — | Uses the positional source-doc path. |

**Uniform flag semantics.** Every accepting skill parses the flag
*before* classifying the positional argument, rejects a bare
`--upstream`, rejects a second occurrence, and never derives the topic
slug from the flag's value. `/strategy`'s phrasing
(`phase-0-setup.md:52-55`) is representative:

> "Consume the flag and the token following it BEFORE classifying the
> remainder: the flag's value is never tested as a topic string, never
> tested as a path argument in the entry-mode table below, and never
> used to derive the topic slug."

The reason is the slug-collision failure, stated most concretely at
`skills/scope/references/phases/phase-2-chain-orchestration.md:195-207`:
handing `/brief` a ROADMAP positionally would name the produced brief
after the roadmap — "a brief for `payment-retries` under a
`ROADMAP-billing.md` upstream would land at `docs/briefs/BRIEF-billing.md`".

**Uniform validation.** Both parents state that they run the same three
ordered checks `/prd`'s draft phase runs, "reused rather than
reinvented, so an author sees one behavior from the flag whichever skill
they hand it to" (`charter/.../phase-0-setup.md:245-247`; identical
wording at `scope/.../phase-0-setup.md:167-170`). The three checks:
`wip/` → reject; not git-tracked → reject; public repo naming private
upstream → omit and continue.

---

## 3. Precedent A — read but do not record

Two independent instances.

### 3.1 `/strategy`'s grounding PRD (the canonical statement)

`skills/strategy/references/phases/phase-0-setup.md:110-133`, under the
heading **"Reading a document vs. recording it as `upstream`"**:

> "Both path modes read the file they are handed. Only one of them ever
> writes that path into the draft's `upstream:` frontmatter field, and
> the two acts are not the same act.
>
> - A **VISION is read and recorded.** `upstream:` names the strategy's
>   immediate neighbour one level up the strategic chain (VISION ->
>   STRATEGY -> ROADMAP), and a VISION is exactly that. […]
> - A **PRD is read only.** It grounds the Phase 1 conversation and
>   informs the bet, and there it stops. A PRD sits two altitudes below
>   a STRATEGY and on the tactical chain rather than the strategic one.
>   Record it as the strategy's parent and a reader who follows
>   `upstream:` looking for the altitude above lands below where they
>   started instead, in the chain the STRATEGY is meant to feed rather
>   than descend from.
>
> Grounding a strategy in a PRD stays supported […] What the PRD never
> becomes is the recorded parent. When a PRD grounds the bet and no
> VISION sits above it, the draft omits `upstream:` entirely and names
> the PRD in Strategic Context prose, which is where the grounding is
> legible to a reader anyway."

**Stated reason:** direction. A recorded PRD points a chain walk *down*
into the tactical chain instead of up.

Consequences of the rule elsewhere:

- `phase-0-setup.md:184-188` — "`PRD-` is not accepted on the flag,
  because the flag records and a PRD is never recorded; an author
  holding a PRD passes it positionally instead."
- `phase-2-draft.md:89-94` (the write site) — "When Phase 0 recorded a
  grounding PRD instead, omit the field. Do not substitute the PRD path
  — the PRD grounded the bet and belongs in Strategic Context prose,
  but as an `upstream:` value it would point a chain walk down into the
  tactical chain rather than up. Omitting is the correct shape, not a
  gap: the field is optional precisely so a strategy grounded in
  something other than a VISION has a right answer available."
- `phase-0-setup.md:238-241` — even the *scope default* derived from the
  PRD is fenced: "The PRD informs the scope default the same way it
  informs the bet, and -- like the bet -- that reading never turns into
  an `upstream:` value."
- Surfaced to the author at `phase-0-setup.md:313-314` — "Grounding:
  `docs/prds/PRD-<name>.md`. Recorded upstream: none -- the PRD grounds
  the bet but `upstream:` takes a VISION, so the draft omits it."
- `/charter` mirrors it when routing:
  `charter/.../phase-2-chain-orchestration.md:236-240` — "A grounding
  PRD never travels in `--upstream`, because that flag's value is what
  `/strategy` records in `upstream:` frontmatter and a PRD is never
  recorded".
- Open issue: the *input* half is unresolved.
  `strategy/.../phase-0-setup.md:93-100` — "PR #252 closed the
  structural half — a grounding PRD is never recorded in `upstream:` —
  but left the input path open. Resolving it either removes this mode or
  writes down why reading across altitudes is legitimate where linking
  across them is not." (issue #257)

### 3.2 `/comp` — the flag exists but the field does not

`/comp` accepts `--upstream` (`skills/comp/SKILL.md:115-117`: "treat the
named artifact as the upstream for the new COMP; derive the competitive
question candidate from it during Phase 1"), records it at Phase 0
(`comp/.../phase-0-setup.md:17`), and consumes it at Phase 1.4:

> "If Phase 0 recorded an upstream path (from `--upstream` or the parent
> sentinel), read it now and let it sharpen the competitive question and
> the slice. Do not copy upstream content into the COMP; use it to
> frame." (`skills/comp/references/phases/phase-1-scope.md:24-27`)

The COMP format has no field to record it into
(`skills/comp/references/comp-format.md:26-27`). This is a
read-but-do-not-record case with **no stated reason** — the format
reference simply omits the field and Phase 1 simply doesn't write one.
That silence is a gap worth naming in the PRD: `/comp` is the one
`--upstream` acceptor whose non-recording is unexplained.

### 3.3 A related asymmetry: inbound basename enforced, outbound not

Both parents state it identically. `charter/.../phase-0-setup.md:233-241`:

> "Inbound validation enforces the basename even though the outbound
> contract — the `--upstream` `/charter` hands `/roadmap` at Phase 2 —
> does not, and the asymmetry is deliberate. Outbound, `/charter` hands
> over an artifact it just watched a child produce and whose type it
> therefore knows. Inbound, it is routing on a string the author typed.
> A wrong type inbound is not caught anywhere downstream: `/strategy`
> would record a ROADMAP or a PLAN as the strategy's parent, the chain
> head would be framed against the wrong altitude, and nothing would
> say so."

Same at `scope/.../phase-0-setup.md:158-165`.

---

## 4. Precedent B — the private-upstream omission rule

Nine places state it. All nine share the same shape: **public document +
private upstream → omit the field, say so out loud, continue.** The
reason splits into two halves that different files emphasize.

### 4.1 `skills/scope/references/phases/phase-0-setup.md:183-207`

> "3. **Would a public document name a private upstream?** Using the
>    visibility detected above, when this repo is Public AND the
>    upstream lives in a private repo, STOP recording: do not write
>    `consumed_upstream:`, do not pass the flag to any child, and tell
>    the author the field is being omitted and why. The chain then runs
>    exactly as it would have with no `--upstream` at all.
>
> The third check is the load-bearing one, because the flag's value
> reaches a committed `upstream:` field in the produced BRIEF. Public
> documents must not reference private ones […] and that rule is
> enforced by content governance rather than by tooling: `shirabe
> validate`'s resolution check returns nothing for a cross-repo value,
> so a public document carrying a private cross-repo upstream validates
> clean today and always will. `/scope` owns the check the validator
> cannot make."

And the reject-vs-omit distinction, `:201-207`:

> "Checks 1 and 2 reject the run while check 3 omits the field and
> continues, and the difference is not an inconsistency. A `wip/` or
> untracked path is malformed input the author can fix by re-invoking
> with the canonical path; continuing without an upstream would hide the
> mistake. A private upstream in a public repo is a legitimate value
> that this repo cannot record — the feature is still worth scoping, so
> the chain proceeds and the link is what gets dropped."

State-file consequence, `:276-281`: "A run whose upstream was dropped by
the visibility check is indistinguishable in state from a run that
supplied no upstream, which is the intended shape — nothing records a
private path in a public repo, including the state file, which is itself
durable on the pushed feature branch."

### 4.2 `skills/charter/SKILL.md:308-320`

Under **"The flag's value reaches a committed field"**:

> "Nothing about a flag suggests its value ends up in a committed file,
> and this one does: `/strategy` writes it into the produced STRATEGY's
> `upstream:` frontmatter, and that document is committed. Public
> documents must not reference private ones, and no tooling enforces
> that rule for a cross-repo value — `shirabe validate`'s resolution
> check returns nothing for one, so a public STRATEGY carrying a private
> cross-repo upstream validates clean and always will."

The `/scope` twin is `skills/scope/SKILL.md:753-761` with `/brief` and
BRIEF substituted.

### 4.3 `skills/charter/references/phases/phase-0-setup.md:260-289`

Same three ordered checks, plus one clause the `/scope` copy lacks
(`:287-289`): "When the field is omitted, the author may still describe
the source context in the produced document's prose, without naming a
private path or repo." It also notes at `:260-263` that this is "the one
Phase 0 use of a value Phase 1 otherwise owns; the check has to run
before the value is recorded, and Phase 1 is after that."

### 4.4 `skills/brief/references/phases/phase-0-setup.md:188-197` + `:209-213`

Phase 0 defers the decision to Phase 2:

> "A cross-repo value in the `owner/repo:path` form […] is not a
> working-tree path: it skips canonicalization and the tracked-by-git
> check, keeps the `ROADMAP-` basename rule on its file component, and
> is governed by the visibility rule Phase 2 applies when writing
> frontmatter (a public BRIEF omits a private upstream rather than
> naming it)."

And `:209-213`: "BRIEF has no visibility-gated section, so `shirabe
validate` runs no custom check for the type. The recorded value still
matters at Phase 4: a public BRIEF must not reference private paths,
repos, filenames, or issue numbers, and its `upstream:` field must not
point at a private artifact. Phase 4's structural-format reviewer checks
this".

The Phase 4 reviewer criterion is at
`skills/brief/references/phases/phase-4-validate.md:228`.

### 4.5 `skills/brief/references/phases/phase-2-draft.md:84-90` (the write site)

> "Omit the `upstream` field entirely when the upstream is a private
> artifact a public brief cannot name. Nothing downstream will catch it
> if you do not: `shirabe validate` resolves nothing for a cross-repo
> value, so a public BRIEF naming a private ROADMAP validates clean. Say
> so in the run output rather than dropping the link quietly."

### 4.6 `skills/strategy/references/phases/phase-0-setup.md:201-206`

> "A cross-repo value […] skips canonicalization and the tracked-by-git
> check, keeps the `VISION-` basename rule on its file component, and is
> governed by the visibility rule Phase 2 applies when writing
> frontmatter (a public STRATEGY omits a private upstream rather than
> naming it)."

### 4.7 `skills/strategy/references/phases/phase-2-draft.md:96-104` (the write site)

> "Omit the field as well when the recorded upstream is a private
> artifact and this repo is public. Public documents must not reference
> private ones, and nothing downstream will catch it: `shirabe validate`
> resolves nothing for a cross-repo value, so a public STRATEGY naming a
> private VISION validates clean. Say so in the run output rather than
> dropping the link quietly, and describe the source context in
> Strategic Context prose without naming the private path or repo."

### 4.8 `/prd` and `/roadmap` — check 3 of the draft-phase triple

`skills/prd/references/phases/phase-3-draft.md:46-56`:

> "3. **Path is out-of-repo?** Detect this repo's visibility from
>    CLAUDE.md (`## Repo Visibility:`). If public AND the canonical
>    upstream lives in a private repo, STOP and OMIT the `upstream:`
>    field. Public artifacts must not reference private resources. […]
>
> When omitting the field, optionally describe the source-context in
> prose in the PRD body's Problem Statement section, without naming a
> private path or repo."

`skills/roadmap/references/phases/phase-3-draft.md:49-61` is the same
text plus the no-tooling half spelled out — "and no tooling enforces it:
`shirabe validate` resolves nothing for a cross-repo value, so a public
ROADMAP naming a private STRATEGY validates clean" — and makes the
announcement mandatory rather than optional: "When omitting the field,
say so in the run output".

### 4.9 `/design` — the worked example

`skills/design/references/phases/phase-0-setup-prd.md:128-134`:

> "3. **Public repo referencing an out-of-repo PRD?** If the repo is
>    public AND the PRD is not tracked here AND the canonical location
>    is private, STOP. This is a visibility violation: external readers
>    can't reach private resources, so the link breaks for them.
>    Resolution: OMIT the `upstream:` field entirely. Add a one-line
>    prose note in the design body's "Context and Problem Statement"
>    section explaining that the source PRD lives in a private tracker
>    (without naming the private path or repo)."

The worked example at `:144-153` is the fullest narrative of the failure
mode in the repo: a coordinator stages a private PRD into a public
repo's `wip/`, `/design` writes `upstream: wip/PRD-<topic>.md`, cleanup
deletes the file, "The frontmatter is now a public reference to a
private resource AND an orphaned path."

`/plan` carries the visibility half only as a hygiene re-check
(`phase-7-creation.md:308-312`), not as a Phase-0 decision.

### 4.10 Reasons given, summarized

Two distinct justifications recur:

1. **Reader-reachability.** "external readers can't reach private
   resources, so the link breaks for them" (`design/.../phase-0-setup-prd.md:130-131`).
2. **The validator cannot see it.** Every parent and both draft-phase
   writers state that `shirabe validate` resolves nothing for a
   cross-repo value, so the violation validates clean — "`/scope` owns
   the check the validator cannot make"
   (`scope/.../phase-0-setup.md:198-199`).

And one procedural rule attached to all of them: **announce the
omission.** `/roadmap`, `/brief`, `/strategy`, `/charter`, and `/scope`
all require the run to say the field is being dropped and why.

---

## 5. Precedent C — `/scope`'s consolidation absorb re-point

`skills/scope/references/phases/phase-2-chain-orchestration.md:485-501`,
the "Stage 3 — Carry check and absorb" step, fired only after every
required section of the absorbed artifact is confirmed carried:

> "When every section is carried, complete the absorb:
>
> 1. Read the absorbed artifact's own `upstream:` value.
> 2. Set the survivor's `upstream:` to that value, or remove the field
>    when the absorbed artifact had none. This is the settled
>    nearest-produced rule from
>    `${CLAUDE_PLUGIN_ROOT}/references/pipeline-model.md`, not a new
>    convention.
> 3. `git rm` the absorbed artifact.
> 4. Re-run `shirabe validate` on the survivor. A non-zero exit reverts
>    the absorb (restore the artifact, restore the `upstream:` value)
>    and routes to R8 bail-handling.
>
> Step 4 is load-bearing: the validator's `R6` check requires an
> `upstream:` value to resolve to a tracked file, so a survivor whose
> re-point was missed fails validation and the absorb does not land."

**What it produces when the absorbed BRIEF's upstream was a ROADMAP.**
The only hop `/scope` currently absorbs is brief→prd
(`carry_check` schema at `:466-478`). Before the absorb the chain reads
`ROADMAP ← BRIEF ← PRD`; the PRD's `upstream:` is
`docs/briefs/BRIEF-<topic>.md`. Step 1 reads the BRIEF's own
`upstream:` — the ROADMAP path. Step 2 overwrites the PRD's
`upstream:` with it. Step 3 deletes the BRIEF. The result is

```yaml
# docs/prds/PRD-<topic>.md
upstream: docs/roadmaps/ROADMAP-<name>.md
```

— **a PRD pointing directly at a ROADMAP, one altitude skipped**, with
no record anywhere in the frontmatter that a BRIEF ever sat between
them. If the absorbed BRIEF had no `upstream:` (a standalone brief,
private-omitted upstream, or a `--upstream`-less run), the survivor's
field is *removed*, and the PRD ends up with no upstream at all.

**Why that is legal.** `references/pipeline-model.md:120-135`:

> "The diagram above is the full chain, not a mandatory one. Each
> artifact's `upstream` field points to the nearest artifact actually
> produced above it, and the field is omitted when nothing was.
>
> The strategic chain (VISION -> Strategy -> Roadmap) is strict in both
> directions […] Skipping an altitude there would leave the reasoning at
> the skipped altitude unreachable from the path a reader walks.
>
> The tactical chain is not strict, because its steps are not all
> mandatory. A feature framed directly in its PRD has no BRIEF, so that
> PRD's upstream is the Roadmap; a feature that needs no architectural
> decision has no DESIGN, so the PLAN's upstream is whatever preceded
> it. The field records the chain that was actually walked. What no
> artifact does is point downward or sideways -- a BRIEF never points at
> a PRD, which is written from the brief's framing."

So the re-point makes the frontmatter tell the truth *after* the
absorb: the BRIEF no longer exists, the ROADMAP is now the nearest
artifact above the PRD, and the PRD says so. The rule is asymmetric by
design — the same skip would be illegal on the strategic chain.

Cross-references: `phase-2-chain-orchestration.md:591-592` cites
pipeline-model as "the settled `upstream:` rule the absorb's re-point
applies"; `skills/brief/references/phases/phase-0-setup.md:236-240`
explains that the consolidation judgment is where the reader-economy
goal moved to after `/brief`'s own fold-into-PRD branch was removed.

---

## 6. Direct answers to the two yes/no questions

**Does `/roadmap` record a STRATEGY upstream?** Yes, and only a
STRATEGY. `skills/roadmap/references/phases/phase-3-draft.md:32-37`:

> "The upstream path points to the STRATEGY this roadmap sequences --
> passed by `/charter` on every chain, or by the user in standalone
> invocation. If `--upstream` is not provided, omit the field from
> frontmatter; **do not substitute a VISION path, which would skip a
> level of the chain.**"

`skills/roadmap/SKILL.md:165-173` repeats it: "When no STRATEGY exists,
omit the flag rather than reaching past the neighbour to a VISION".

**Does `/plan` record a DESIGN upstream?** Yes — and also a PRD or a
ROADMAP, depending on which input mode fired.
`skills/plan/references/phases/phase-7-creation.md:162` (multi-pr):
`upstream: <source-doc-path>   # design doc, PRD, or roadmap path`;
`:247` (single-pr): `upstream: <design-doc-path>`.
`skills/plan/SKILL.md:237-242` classifies the positional argument into
`input_type` ∈ {design, prd, roadmap, topic}; the topic mode records no
upstream. `skills/plan/SKILL.md:55-56` calls the field "Optional
`upstream` links to the source document (design doc, PRD, or roadmap)."

---

## 7. Contradictions and gaps the PRD should decide

1. **`/explore` hands `/roadmap` a VISION in the `--upstream` slot.**
   `skills/explore/references/phases/phase-5-produce-roadmap.md:43-49`:
   "**Detect upstream VISION.** […] If the exploration identified a
   specific VISION (e.g., `docs/visions/VISION-<name>.md`), pass it as
   `--upstream` in the invocation. […] With VISION:
   `/shirabe:roadmap <topic> --upstream <vision-path>`". `/roadmap`'s own
   Phase 3 forbids exactly that value
   (`roadmap/.../phase-3-draft.md:35-37`, quoted above) and `/roadmap`
   enforces no basename on the flag, so the VISION path is written
   straight into the ROADMAP's frontmatter. This is a live, un-caught
   altitude skip on the strict half of the chain. The design doc that
   introduced it (`docs/designs/current/DESIGN-artifact-traceability.md:266-267`)
   predates the STRATEGY altitude.

2. **`/comp` accepts `--upstream` and records nothing, with no stated
   reason.** Unlike `/strategy`'s grounding PRD, which has a
   direction-based justification and an author-facing announcement,
   `/comp`'s non-recording is only visible by noticing that
   `comp-format.md` has no such field.

3. **`/vision`'s `upstream:` has no writer.** The format reference
   defines it (`vision-format.md:28`, `:37-40`) and Phase 3 mentions it
   in one clause ("Include `upstream` only for project-level VISIONs
   with a parent", `phase-3-draft.md:44-45`), but no phase detects,
   validates, or resolves the parent path — and `/vision` runs none of
   the `wip/`, git-tracked, or public/private checks the other seven
   writers run.

4. **Basename enforcement is uneven among the children.** `/strategy`
   and `/brief` enforce it on the flag and reject the downstream type
   with a chain-inversion message; `/prd` and `/roadmap` enforce
   nothing, which is what lets gap 1 land.

5. **The absorb re-point can silently clear a field.** Step 2's "or
   remove the field when the absorbed artifact had none" produces a PRD
   with no upstream where the pre-absorb PRD had one (pointing at the
   now-deleted BRIEF). Nothing in the step requires announcing that to
   the author, unlike every private-omission site, which does.

6. **`/design` and `/plan` accept no flag.** A DESIGN whose PRD is not
   the positional argument, or a PLAN produced in direct-topic mode,
   has no route to record an upstream at all.
