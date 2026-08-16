# Content-Quality Verdict: BRIEF-fold-record-removal

## Verdict

FAIL

Three blocking issues, all surgical. The brief's framing is genuinely strong —
the journeys are distinct and concrete, the OUT list is the best section in the
document, and the growth argument the author excluded stays excluded. What
fails it is one internal contradiction between the Scope IN list and Open
Questions, one altitude slip inside the IN list, and one User Outcome claim
that overshoots its own frontmatter into something the exploration does not
support.

## Rubric findings

### 1. Problem Statement states a problem, not a smuggled solution — PASS

The section opens on the gap, not the change:

> "That deletion creates a reader problem the judgment itself cannot solve: a
> document that was absorbed and a document that was never produced look
> identical on disk, and they mean opposite things."

That is the pre-feature gap, stated without reference to what gets deleted.
The three bolded sub-arguments then frame *why the current arrangement is
wrong* rather than *what will be removed*: "It was never argued for," "Most of
what it records is recorded twice," "What it costs is contention, not size."
None of the three says "we should delete `docs/folds.md`." The closing line —
"machinery ... protecting a file that has never held a row" — implies the
conclusion without stating a solution, which is the correct altitude.

The subtle risk the review brief flagged is real but the draft stays on the
right side of it. The one place it comes close is the closing enumeration:

> "a merge driver, an append-only assertion, a cleanup carve-out, a
> citation-search exclusion, and four documents of rationale"

That list maps close to 1:1 onto the Scope IN list. But it is presented as the
*cost surface* ("The result is machinery ... protecting"), not as a deletion
plan, and for a removal feature the cost surface and the deletion surface are
necessarily the same set. Framed as cost, it reads as problem. No change
required.

**Growth check (the author's explicit constraint): clean.** The brief does not
smuggle a growth argument back in. It actively forecloses one — the third
sub-argument is titled "**What it costs is contention, not size**," and the
frontmatter `problem` says "a contention point and an adopter obligation,"
never a size claim. The "machinery" enumeration is a complexity cost, which is
a different claim from file growth and is independently supported by the
findings. This is handled correctly.

### 2. Problem Statement stands alone — PASS

A cold reviewer gets, in order and without opening anything: what a fold is
("`/scope`'s consolidation judgment deletes a chain document when a downstream
artifact already carries everything it held"), why deletion is ambiguous, why
history does not rescue it ("This repository squash-merges a whole chain, so a
document created and folded away inside one chain never appears on the default
branch at all"), what the current answer is, and three specific defects in it.
The References section is a courtesy, not a prerequisite. That satisfies the
stand-alone rule.

One phrase leans on context a cold reader lacks: "All six underlying decisions
were made without author confirmation." Six of what is never established — the
number is meaningful only if you have read the upstream design's decision
list. The sentence still lands ("decisions were made without author
confirmation"), so this is a polish note, not a blocker. Listed under Optional.

### 3. User Outcome is outcome-shaped and names its user — PASS

Three paragraphs, three named users, no feature list anywhere:

> "An author running `/scope` alongside other agents on the same repository
> finishes a fold without touching any file another chain is also writing."

> "A reader who lands on a path that no longer exists still learns what
> happened to it, from the document that absorbed it."

> "A maintainer of a repository that adopts shirabe's shared validation
> workflow no longer inherits an obligation their repository was never given
> the means to meet."

Each names a person and says what is different for them. Nothing enumerates
what got removed — notably, the word `docs/folds.md` does not appear in the
section at all, which is the right discipline for a removal brief. The second
paragraph describes a *preserved* rather than changed outcome, but says so
honestly ("still learns"), and preservation of the guarantee is precisely what
this feature must claim. Shape is correct.

### 4. User Outcome matches the `outcome` frontmatter — FAIL (blocking, drift)

Content maps cleanly, clause for clause — frontmatter's contention / adopter /
reader against prose paragraphs 1 / 3 / 2. Order differs, which is fine.

The drift is in precision, and it runs the wrong way. The frontmatter is
narrow and defensible:

> "Parallel `/scope` runs no longer contend on a **shared bookkeeping file**"

The prose widens that to an absolute:

> "finishes a fold **without touching any file another chain is also writing**.
> Nothing about the run contends"

and Journey 1 repeats it: "neither branch touches a file the other wrote."

The exploration establishes that `docs/folds.md` is *the* shared write point
for the fold record. It does not establish — and the brief cannot claim — that
two parallel `/scope` chains share no other file. The brief's own Scope IN list
gestures at another shared surface: "the line the implementation cascade writes
into a roadmap when a chain folds to nothing." The narrow frontmatter claim is
the true one; the prose overshoots into an unsupported absolute. Since the
frontmatter and prose are contracted to carry the same content, this is drift,
and it is drift toward a claim the brief cannot back.

### 5. Each journey names a user, a trigger, and an outcome shape — PASS

All four carry all three.

| Journey | User | Trigger | Outcome shape |
|---|---|---|---|
| Two chains fold in parallel | two agents running `/scope` on the same repository | "both folds complete and both branches open pull requests" | "both merge in either order with no rebase, no conflict marker, and no red check on a correct record" |
| A reader holds a path that no longer exists | "a contributor reading a design document" | "the grep for that path returns one hit" | reader resolves absorbed-vs-never-written "in the working tree without consulting history, a forge, or a central index" |
| An adopting repository runs the shared validation workflow | "a maintainer of another repository" | "their first chain folds a document and opens a pull request" | "the workflow checks what their repository can actually satisfy" |
| A future contributor notices folds leave no central trace | "a contributor auditing the corpus" | "they consider adding one" | "they find a durable record of why that was tried, what it cost, and which alternatives were measured and rejected" |

Concrete throughout — "the grep for that path returns one hit," "no red check
on a correct record." Nothing here is "users interact with the system."

Minor craft note, non-blocking: in journeys 1 and 2 the labeled **Trigger:**
sits mid-path rather than at the start. Journey 2's real trigger is "follows a
citation to a PRD path and finds nothing there"; the labeled trigger is the
grep that follows it. The three elements are all present, so the rule is met.

### 6. Journeys are distinct — PASS, and this is the draft's strongest section

Four genuinely different entry points, not one journey told four ways:

- **Concurrency / parallel execution** — two chains racing on the same repo.
- **Consumer tracing upstream** — a reader landing on a dangling path.
- **Downstream adopter** — a different repository inheriting the CI check.
- **Future re-litigation** — a contributor considering re-adding the mechanism.

The fourth is the one that earns its place hardest and does earn it: it is the
only journey whose user is not served by the removal itself but by the record
*of* the removal, and it names the failure mode if that record is missing
("Without that record the removal reads as an oversight and invites the
mechanism back"). Different user, different trigger, different outcome from
every other journey.

### 7. Scope Boundary has real IN and OUT lists — PASS on OUT, see item 9 on IN

Both lists exist and are substantive. The OUT list is exemplary — every one of
the six items is something a downstream PRD author could plausibly have
assumed was inside the boundary:

- "**The consolidation judgment itself.** ... This work changes what a fold
  *records*, never what it *does*." — the single most likely over-reach.
- "**The survivor-side trace.** ... They are the carrier the removal relies on,
  not collateral." — a naive implementer deleting fold bookkeeping could
  absolutely take `absorbed:` with it.
- "**Re-deciding whether a design may be absorbed into a plan.**" — sharp, and
  correctly identifies the subtle case: "the argument loses its premise while
  the decision does not."
- "**Building a replacement carrier.**" — the obvious downstream drift.
- "**Fixing the defects in the fold-record check as standalone work.**"
- "**A migration path for existing rows.** The record has never held one."

No filler. The last item is one line, but a one-line answer to a question every
downstream author will ask is efficiency, not emptiness. Nothing here is "not
building a time machine."

### 8. Open Questions defer framing details rather than blocking — FAIL (blocking, contradiction)

Neither question is a blocker that should have stopped the brief — correct on
that axis. Question 2 is a clean deferral: "What the roadmap's downstream cell
says when a chain folds to nothing," with the useful note that "No roadmap
carries that text today, so the choice is unconstrained by existing content."
The IN list commits that the line gets replaced; the question defers what it
says. Compatible.

Question 1 contradicts the Scope Boundary. Open Questions says:

> "Whether the merge attribute is deleted outright or left in place and inert."

The IN list has already decided it:

> "Removing the merge attribute that exists only to serve the record."

A downstream PRD author reading both gets contradictory instruction: the scope
says removal is in the boundary, the open question says removal is undecided.
One of the two is wrong, and the brief does not say which. This is a coherence
defect in the framing, not a formatting nit — the Scope Boundary's entire job
is telling a PRD author where the feature ends, and here it disagrees with the
document it sits in.

Note also that Open Questions must be empty before `Draft -> Accepted`, so this
has to be resolved regardless; resolving it will force a decision about which
of the two statements survives.

### 9. No drift into requirements, architecture, or implementation — FAIL (blocking, IN list)

Judged strictly, as instructed. Most of the IN list is defensible: for a
removal feature, "what the feature holds in" is unavoidably a set of removals,
so verb-phrasing alone is not the tell. Items naming a surface — the record
file, the CI verification step, the merge attribute, the two prose claims — name
what the boundary contains and stay at brief altitude.

Two places cross the line.

**(a) A test case is a PLAN-altitude atom.**

> "Removing the citation-search exclusion that exists only to stop the record
> from poisoning the fold guard, **along with its test case**."

The format reference's Content Boundaries put "Implementation tasks" in a PLAN.
Naming an individual test case in a brief's scope boundary is a file-level work
item, not a boundary. The exclusion belongs in the IN list; its test does not.

**(b) The amendment mechanism is prescribed, not just scoped.**

> "Amending the four shipped documents whose requirements and decisions the
> record discharges, **in place, following the dated-amendment shape this
> corpus already uses**."

"In place" and "the dated-amendment shape" are a decision about *how* the
change is made. The exploration records that amendment-in-place is forced by
the toolchain (`prd/v1` has no `Superseded` status), so the decision is
uncontested — but an uncontested decision is still a decision, and it belongs
in the downstream PRD's record, not in the brief's boundary. The brief's job
here is "the four shipped documents that cite the record are inside the
boundary"; the shape of the amendment is downstream.

Everything else in the document stays at altitude. There are no acceptance
criteria, no interface shapes, no file-by-file breakdown of the removal, and
the Problem Statement never names a line number or a function.

## Required changes

1. **Scope Boundary IN + Open Questions — resolve the merge-attribute
   contradiction.** The IN list says "Removing the merge attribute that exists
   only to serve the record"; Open Questions asks "Whether the merge attribute
   is deleted outright or left in place and inert." Pick one. Either drop the IN
   bullet and let the question own the decision, or drop the question and let
   the IN bullet stand — but the brief cannot assert both. If the IN bullet
   stays, the question's real residue (that three documents cite the attribute
   as providing a guarantee it does not provide) is already covered by the
   existing IN item on replacing prose claims, so the question can go entirely.

2. **User Outcome, first paragraph — narrow the contention claim to match the
   frontmatter.** Replace "finishes a fold without touching any file another
   chain is also writing. Nothing about the run contends" with a claim scoped to
   the shared bookkeeping file, as the `outcome` frontmatter already correctly
   states ("no longer contend on a shared bookkeeping file"). The absolute
   version claims parallel chains share no write surface at all, which the
   exploration does not establish and which the brief's own IN list works
   against by naming a roadmap line the cascade writes. Apply the same narrowing
   to Journey 1's "neither branch touches a file the other wrote."

3. **Scope Boundary IN — trim two implementation prescriptions.** (a) Delete
   "along with its test case" from the citation-search-exclusion bullet; a test
   case is PLAN altitude. (b) Delete "in place, following the dated-amendment
   shape this corpus already uses" from the amendment bullet, leaving the
   boundary claim ("Amending the four shipped documents whose requirements and
   decisions the record discharges") and letting the downstream PRD record the
   amendment mechanism.

## Optional improvements

- **Problem Statement ordering.** The three sub-arguments run
  provenance → redundancy → cost. The first ("It was never argued for") is a
  claim about how the decision was made rather than about what a user
  experiences, and it is the weakest of the three as a *problem*. Leading with
  the two user-facing costs and closing on provenance would put the strongest
  material first without changing any content.

- **"All six underlying decisions."** Six of what is never established for a
  cold reader. Either name the decision set briefly or drop the count — "the
  underlying decisions were made without author confirmation" loses nothing.

- **"A hosted forge resolves merges without consulting a repository's merge
  drivers."** The exploration verified this on GitHub specifically (with the
  Kubernetes precedent, kubernetes/kubernetes#70576). Generalizing to "a hosted
  forge" claims slightly more than was measured. "The forge this repository
  merges on" would be exact and costs nothing.

- **Trigger placement in Journeys 1 and 2.** Both label a mid-path event as the
  **Trigger:** — Journey 2's actual trigger is following a citation and finding
  nothing, not the grep that follows. Moving the label to the initiating event
  would sharpen both, though all three required elements are present as written.

- **"Four documents of rationale"** in the Problem Statement's closing line
  reads as though it matches the four entries in References, but one of those
  entries (`skills/scope/references/phases/phase-2-chain-orchestration.md`) is a
  procedure reference rather than a rationale document. If the two fours are
  meant to be the same set, they are not; if they are different sets, the
  coincidence invites a misread.
