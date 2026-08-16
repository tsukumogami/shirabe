# Decision 2 — Where the `/explore` handoff artifact lives, and what its schema is

Topic: `scope-chain-mandatory-steps`. Governing requirements: R19, R21,
R25 in `docs/prds/PRD-scope-chain-mandatory-steps.md`, with R14, R20,
R22, R23, R24, R26 and R28 as binding neighbours. All line numbers refer
to the worktree at
`/home/dgazineu/dev/niwaw/tsuku/tsuku+shirabe_inconsistencies-03b57366/public/shirabe/.claude/worktrees/scope-chain`.

## Question

`/explore` stops routing to chain-internal children and starts routing to
parents. It still needs to hand the parent what the exploration
established. Three things have to be settled together, because each
constrains the others:

1. **Where the file lives.** R19 requires a parent-namespaced path that
   collides with no existing resume-ladder match condition in either
   parent, and that is distinguishable from `/charter`'s own
   pre-populated `wip/roadmap_<topic>_scope.md` handoff to `/roadmap`.
2. **What it carries.** R21 restricts it to conversation and forbids
   filesystem state — artifact existence, frontmatter status, content
   hashes, visibility, upstream validation.
3. **What travels beside it.** R25 requires each router arm to state what
   it passes, and to say what becomes of the `--upstream <STRATEGY>`
   value the current roadmap handler passes to `/roadmap`.

The question is not only "which filename". A filename choice decides
which ladder rows can match it, whether the parent's bounded read surface
has to widen, whether the file is swept by an existing cleanup rule or
needs a new one, and whether the three other readers of the same path
(`/scope`'s Slot 6 globs, `/charter`'s row 8, `/charter`'s abandonment
tie-break) can still tell a feeder doc from a child's abandoned scratch.

## Decision Drivers

**D1 — Zero collisions, checkable by reading the ladders.** R19's bar is
"collides with no existing resume-ladder match condition in either
parent". This is verifiable: `/scope` has 9 Slot 5 rows against `docs/`
paths, 4 Slot 6 globs against `wip/{brief,prd,design,plan}_<topic>_*`
(`phase-resume.md:68-72`), and meta rows keyed on the exact filename
`wip/scope_<topic>_state.md`. `/charter` has rows 5-6 against
`docs/strategies/`, row 7 against `wip/strategy_<topic>_discover.md`, row
8 against `wip/vision_<topic>_scope.md` (`phase-resume.md:57-58`), and
meta rows keyed on the exact filename `wip/charter_<topic>_state.md`. A
grep for `wip/charter_` and `wip/scope_` across `skills/` and
`references/` returns only exact `_state.md` filenames — neither parent
globs its own prefix anywhere.

**D2 — The parent's bounded read surface must not widen.** `/charter`'s
R14 isolation rule (`phase-resume.md:496-511`) forbids reading "any other
child `wip/` intermediate beyond the partial-run detection patterns
explicitly listed in rows 7-8", and the security section calls adding a
permitted source without revising the prose "itself a violation"
(`:594-602`). `/scope` carries the same rule by reference through
`parent-skill-child-inspection.md`. A handoff path inside a child's
namespace forces that list to grow; a path inside the parent's own
namespace does not touch it at all.

**D3 — Something must sweep the file, and the sweeper already exists or
does not.** `/explore` explicitly declines to clean up:
`phase-5-produce.md:56-58` — "Cleanup happens when the target workflow
completes." `/scope` Phase 4 sweeps `wip/scope_<topic>_*` on **every**
exit path and the child prefixes on `full-run`/`re-evaluation` only
(`phase-4-cleanup.md:27-46`), and Phase 4 reads back a **closed
write-target set** that an implementation may not exceed (`:88-120`).
`/charter` states its own closed write-target set as exactly five places
(`SKILL.md:333-344`). A prefix already inside those sets costs nothing; a
new prefix costs an amendment to both parents' closed-set prose, and
leaving it unswept is a wip-hygiene violation that blocks PR merge.

**D4 — Feeder and partial-run must stay distinguishable by path alone.**
Three separate mechanisms currently read child wip filenames and mean
different things by them: `/scope` Slot 6 ("a child was interrupted,
re-invoke it"), `/charter` row 8 (same), and `/charter`'s
abandonment-forced tie-break step 2, which force-materializes a partial
artifact for "the first `planned_chain` entry with a non-empty wip/
intermediate" (`phase-finalization.md:513-523`). A handoff sitting at one
of those paths is read by all three as evidence of work that never
happened.

**D5 — R21's conversation/filesystem line has to be mechanically
checkable.** The rule already exists in both parents in a stronger form:
"the re-validation re-runs the whole battery … against the worktree as it
is NOW, not as it was when the value was recorded. A file tracked last
week can be deleted or moved this week"
(`skills/scope/references/phases/phase-resume.md:91-98`, and verbatim in
`/charter`'s). The schema should make the forbidden categories
unwritable rather than merely prohibited — a section that does not exist
cannot carry a content hash.

**D6 — The two parents ask different questions.** `/scope` Phase 1 opens
on the framing-shift question (`phase-1-discovery.md:47-53`) and runs the
R6 P1/P2/P3 walk to size `/design`'s roster (`:148-248`). `/charter`
Phase 1 opens on the thesis-shift question
(`phase-1-discovery.md:143`) and classifies the answer into three
positive-signal categories (`:157-178`). Neither question is a rephrasing
of the other, and `/charter` has no predicate walk at all.

**D7 — Blast radius on the existing corpus.** Every option costs edits.
The measure is how many *contracts* change versus how many *strings*
change, and whether any eval's graded literal has to be rewritten.

## Considered Options

### A. One parent-namespaced file per parent

`wip/scope_<topic>_handoff.md` and `wip/charter_<topic>_handoff.md`,
matching the existing `wip/scope_<topic>_state.md` /
`wip/charter_<topic>_state.md` convention. `/explore`'s `/scope` arm
writes the first; its `/charter` arm writes the second. The two files are
the same skeleton with one parent-specific block each.

**Collision surface, row by row.**

| Parent | Row / slot | Match condition | Matches `wip/<parent>_<topic>_handoff.md`? |
|---|---|---|---|
| `/scope` | meta 1-4 | exact `wip/scope_<topic>_state.md` | No — exact filename, not a glob |
| `/scope` | 5.1-5.9 | `docs/{briefs,prds,designs,designs/current,plans}/…` | No — different directory |
| `/scope` | 6.1-6.4 | `wip/{plan,design,prd,brief}_<topic>_*` | No — prefix is `scope_` |
| `/scope` | 7 | vacuous today | **Yes — intended** |
| `/scope` | 8-9 | branch-related / main | Unreachable once 7 matches |
| `/charter` | 1-4 | exact `wip/charter_<topic>_state.md` | No |
| `/charter` | 5-6 | `docs/strategies/STRATEGY-<topic>.md` status | No |
| `/charter` | 7 | `wip/strategy_<topic>_discover.md` | No |
| `/charter` | 8 | `wip/vision_<topic>_scope.md` | No |
| `/charter` | 9-10 | branch-related / main | Unreachable once the new clause matches |

Also unaffected: `/charter` row 6's mid-roadmap disambiguation, which
keys on `wip/roadmap_<topic>_scope.md` and is gated on a Draft STRATEGY
existing (`phase-resume.md:253-261`); and `/charter`'s abandonment
tie-break step 2, which inspects "the documented partial-run filenames
per child" (`phase-finalization.md:515-518`) — a parent-prefixed file is
not one.

**What the detection clause has to match.** An exact filename composed
from the validated topic slug. No content inspection, no glob, no
disambiguation logic. That is the cheapest possible clause and the one
that keeps D2 intact: the parent reads the *existence* of one path in its
own namespace, plus that file's body once it has decided to consume it —
and the body is a file the parent is entitled to read because the
namespace is the parent's.

**Running the other parent.** `/charter <topic>` after an exploration
that wrote `wip/scope_<topic>_handoff.md` finds nothing at its own path
and starts cold at row 10. That is correct behaviour but silent, and
silence is this option's one real weakness: the author explored, got
routed to `/scope`, typed `/charter` instead, and the exploration's
content is on disk and invisible. The fix is cheap and matches the
pattern's existing stated-skip discipline
(`parent-skill-pattern.md:215-219`): each parent checks the *sibling*
handoff path and, when it exists and its own does not, emits one line
naming the file and the parent it is addressed to, then proceeds cold.
The sibling path is another parent's namespace, not a child's, so R14 is
untouched.

**Resume.** The ladder is first-match-wins. Once Phase 0 has written
`wip/scope_<topic>_state.md`, meta rows 3-4 match before Slot 7 is
consulted, so a surviving handoff is inert on every subsequent
invocation. No consumed-marker, no mutation of the router's artifact, no
double-consumption path. The same holds in `/charter`, whose rows 3-4
precede any slot-7 placement.

**Phase 4 sweep.** `wip/scope_<topic>_handoff.md` falls inside
`wip/scope_<topic>_*`, which Phase 4 removes on **all three** exit paths
with zero edits to the removal matrix or the closed write-target set. On
`abandonment-forced` the parent prefix is removed while child prefixes
are preserved (`phase-4-cleanup.md:37-46`) — the handoff goes with the
state file, which is right: its content was absorbed into Phase 1 and, on
that path, into the force-materialized Draft.

**The one thing this option breaks.** `/scope`'s Phase-1 Bail routes
"force-materialize if any wip state exists for the topic; clean-cancel
otherwise" (`phase-1-discovery.md:326-328`). R28 already narrows that
test to exclude the parent's own state file — because today the state
file is the *only* member of `wip/scope_<topic>_*` (a grep confirms: the
prefix has exactly one filename). Adding a handoff makes the prefix
non-singular, so R28's exclusion must be widened from "the parent's own
state file" to "the parent's own prefix", or an author who explores,
routes to `/scope`, and bails at the chain proposal lands in
abandonment-forced with nothing to materialize — reproducing exactly the
defect R28 exists to fix. This is a one-sentence widening of a clause
that is already being rewritten in this PRD, but it must be written down
or the option regresses R28.

### B. One router-namespaced file, with a `parent:` field

`wip/explore_<topic>_handoff.md` regardless of destination, carrying a
frontmatter or first-section field naming the intended parent. Both
parents detect the same path and check the field before consuming.

**Collision surface.** Identical to A on the parent side: nothing in
either ladder matches `wip/explore_<topic>_*`. On the router side it sits
alongside `/explore`'s own `wip/explore_<topic>_scope.md`,
`_decisions.md`, and `_crystallize.md`, which is a coherent namespace and
an honest description of who wrote the file. Neither parent globs the
`explore_` prefix.

**What the detection clause has to match.** An exact path **plus a field
read**. The clause is "the file exists AND its `parent:` value is mine".
That is two conditions where A has one, and the second is a value read
from a hand-editable file. Both parents' security sections already treat
state files this way — "a state file is a file on disk that a hand-edit
can change between sessions, so the value read back is treated as
untrusted input" (`/charter phase-resume.md:604-615`) — so the field
would need the same re-validation discipline as any other recovered
value, against a closed two-member enum. That is not hard, but it is a
new validation site that A does not have, and the failure mode is a
routing decision rather than a path interpolation.

**Running the other parent.** This is B's genuine advantage, and it is
real. The mis-addressed case becomes legible instead of silent: `/charter
<topic>` finds the file, reads `parent: scope`, and can say so
precisely — "this exploration routed to `/scope`; `/charter` is not
consuming its handoff" — with no sibling-path convention invented for the
purpose. B gets for free what A has to bolt on.

**Resume.** Same as A: the state-file rows precede any slot-7 placement,
so the file is inert once a chain is in flight.

**Phase 4 sweep — where B fails.** `wip/explore_<topic>_*` is outside
`/scope`'s closed write-target set (`phase-4-cleanup.md:88-99`, and
`SKILL.md` L670-674) and outside `/charter`'s five-place enumeration
(`SKILL.md:333-344`). `/explore` will not sweep it — its cleanup rule
defers to "the target workflow". So either the file is never removed,
which is a wip-hygiene violation blocking PR merge, or both parents'
closed write-target sets grow a sixth entry naming a namespace neither
parent writes. The closed-set invariant is specifically an anti-drift
device — "an implementation that removes anything outside this set …
fails the closed-set invariant" — and widening it so a parent may delete
another skill's artifacts weakens the exact property it was built to
hold. This is the cost that decides against B, and it is a contract cost,
not a string cost.

**Second-order.** One writer and one template is simpler for `/explore`,
which is a real ergonomic gain: the router writes one file and sets one
field rather than branching on the arm. But the router already branches
on the arm to decide which `--upstream` flag to pass, so the branch
exists regardless and the saving is smaller than it looks.

### C. Keep the existing per-child convention, narrow the colliding rows

`/explore` keeps writing `wip/prd_<topic>_scope.md`,
`wip/vision_<topic>_scope.md`, `wip/roadmap_<topic>_scope.md`, and R22's
narrowing of `/scope` Slot 6.3 and `/charter` row 8 carries the whole
load.

**Collision surface.** By construction, maximal.
`wip/prd_<topic>_scope.md` matches Slot 6.3's glob `wip/prd_<topic>_*`
exactly; `wip/vision_<topic>_scope.md` *is* `/charter` row 8's match
condition verbatim. R19 explicitly rejects this option's premise —
"R22's narrowing of the colliding match conditions is defense in depth,
not the whole fix" — but the option deserves a fair hearing on its
merits, because it is the only one with zero migration cost on the
`/prd`, `/vision`, `/roadmap` side.

**What the detection clause has to match — and why it cannot.** Narrowing
requires distinguishing "`/explore` wrote this as a feeder" from "`/prd`
wrote this and was interrupted" at the *same path*. Path cannot do it, so
the narrowing has to be a content test: read the file and look for a
marker. That converts both parents' read surface from "the existence of
two named filenames" into "the body of four globbed child-namespace
files", which is precisely what R14's bounded-read-surface prose
forbids, and which the security section says cannot be extended without
being revised. Alternatively the narrowing could be a mtime or
git-provenance test, which is filesystem state used to make a routing
decision and is fragile across a rebase.

**Running the other parent.** Worse than either alternative and not
fixable. `wip/vision_<topic>_scope.md` has three readers with three
meanings: `/charter` row 8 (partial `/vision` run → resume into
`/vision`), `/charter`'s abandonment tie-break step 2 (a `planned_chain`
entry with a non-empty intermediate → force-materialize a VISION
partial), and `/vision`'s own startup clause (`SKILL.md:96-101`, skip
Phase 1). A feeder doc dropped there is read by all three. The
abandonment path is the sharpest: an author who explores, runs
`/charter`, and bails would force-materialize a VISION partial attributed
to a child that never ran.

**Phase 4 sweep.** `/scope` removes `wip/{brief,prd,design,plan}_<topic>_*`
on `full-run` and `re-evaluation` but **preserves** them on
`abandonment-forced`, "so a future session that resumes the abandoned
chain has the child's intermediate state to read back"
(`phase-4-cleanup.md:37-46`). A handoff surviving that carve-out is
re-detected on the next invocation — as a `/prd` partial run under
today's rules, or, under a content-marker narrowing, as a live handoff
that re-pre-loads Phase 1 with an exploration the author already
abandoned. The carve-out is correct for child scratch and wrong for a
feeder, and one path cannot have both dispositions.

**Its genuine merit.** C is the only option under which `/prd`,
`/vision`, and `/roadmap` need no change at all beyond prose: their
detection clauses keep a live producer, and an author who explores and
then invokes a child directly still gets a pre-filled Phase 1. Under A
and B those clauses lose their `/explore` producer entirely, which is
what R24 is for — and R24 re-grounds them on "the parent", which is only
true today for `/charter` → `/roadmap`. C avoids creating that gap. It is
a real cost of A and B, recorded below and in the open sub-questions, and
it is not enough to save C: the cost is one clause per child needing an
honest producer statement, against C's cost of permanently fusing two
meanings onto one path in three separate mechanisms.

## Recommendation

**Adopt Option A.** Two files, `wip/scope_<topic>_handoff.md` and
`wip/charter_<topic>_handoff.md`, one skeleton with one parent-specific
block, plus the sibling-path notice that recovers B's legibility
advantage.

The decisive argument is D3 combined with D2. A is the only option where
the file is swept by a rule that already exists, in a namespace the
parent already owns, detected by a clause that reads one path and nothing
else. B is clean on collisions and better on the mis-addressed case, but
pays for it by widening two closed write-target sets so that a parent may
delete a third skill's artifacts — a contract weakening in exchange for a
convenience that A can buy with one line of prose. C is rejected on R19's
own terms and, independently, because no narrowing exists that does not
either read child file bodies or depend on filesystem provenance.

The two secondary answers follow from the path choice:

**One skeleton, two bindings, not two templates** (Q2). The shared spine
is Provenance, Problem/Theme Statement, Scope Boundary, Decisions Already
Settled, Coverage Notes, Upstream Observations — six sections carrying
material both parents need in the same shape. Exactly one section
differs, because exactly one question differs: `## Framing-Shift Answer`
for `/scope`, `## Thesis-Shift Answer` for `/charter`. `/scope` carries
one additional section (`## Shape Signals`) that `/charter` has no
analogue for, because `/charter` runs no predicate walk. Two templates
would duplicate six sections to vary one; one template with a
parent-specific block keeps the divergence where the divergence actually
is, and makes it obvious to a reader of either file which half is
generic.

**The handoff carries predicate *inputs*, never verdicts** (Q3). R21
permits "a shape estimate the parent re-derives later", and P1 and P3 are
pre-suppliable — but a verdict word in the file invites a parent to copy
it. The template therefore carries the evidence P1 and P3 are computed
*from*: the architectural alternatives the exploration left open, and the
complexity signals it surfaced. It carries **no P2 material at all**,
because P2 cross-references the repo's directory structure
(`phase-1-discovery.md:200-202`) and is a filesystem fact R21 bars. The
parent knows this is an estimate three ways, and the first is
structural: the walk it can read is missing a third of its inputs by
construction, so Phase 1 must run the walk regardless. The section
heading says `(signals, not verdicts — Phase 1 runs the walk)`, and the
consuming clause states that Phase 1 emits its own `fires` /
`does-not-fire` verdict with its own one-line reason for all three
predicates, and that the handoff's signals are inputs to that walk and
never a substitute for it. This is consistent with the walk's own
standing: even Phase 1's verdicts are estimates the post-`/prd` gate
re-derives against the real PRD (`:161-167`).

## Proposed Template

Written by `/explore`'s `/scope` arm to `wip/scope_<topic>_handoff.md`.
The `/charter` variant is identical except for the two marked blocks.

```markdown
# /explore handoff: <topic> → /scope

Produced by /explore for /scope. This file carries conversation, not
filesystem state. Every artifact path, status, and upstream link named
below is an observation from the exploration session and is re-read by
the parent on every run; nothing here is authoritative about the
worktree.

## Provenance

- Explored: <ISO-8601 date of the exploration session>
- Router verdict: <the crystallize outcome, e.g. "chain — tactical entry">
- Source: <issue #N | freeform request | prior artifact path>, one line
- Session artifacts: wip/explore_<topic>_scope.md,
  wip/explore_<topic>_decisions.md, wip/explore_<topic>_crystallize.md
  (named for a reader following the trail; the parent does not read them)

## Problem Statement

<2-3 sentences synthesized from the exploration. State the problem, not
the solution. /charter variant: "## Theme Statement" — what the strategic
bet is about.>

## Scope Boundary

### In Scope
- <item established during exploration>

### Out of Scope
- <item, with the reason it was excluded>

<!-- PARENT-SPECIFIC BLOCK — /scope -->
## Framing-Shift Answer

**Answer:** <Yes | No | Unclear>

**Evidence:** <2-4 sentences. Which of problem shape, target audience,
scope boundary, or core success criterion the exploration found had
changed, and what in the exploration established it.>

This is the author's answer as the exploration recorded it, offered to
Phase 1 for confirmation rather than re-derivation. Phase 1 still asks
the question; the author confirms or corrects.
<!-- END PARENT-SPECIFIC BLOCK -->

<!-- PARENT-SPECIFIC BLOCK — /charter (replaces the above) -->
## Thesis-Shift Answer

**Answer:** <the author's response, in their words>

**Suggested classification:** <thesis-change | new-frame |
VISION-rejection | no-signal>

**Evidence:** <2-4 sentences from the exploration supporting the
classification.>

This is the author's answer as the exploration recorded it. Phase 1 still
surfaces the question verbatim — it is asked "for the framing it gives
the conversation" even where the classification cannot change the
outcome — and classification remains agent judgment at Phase 1.
<!-- END PARENT-SPECIFIC BLOCK -->

## Decisions Already Settled

<Scope narrowings, option eliminations, and priority choices the
exploration closed. One line each, with the reason. The chain treats
these as settled input, not as findings to re-litigate. Omit the section
if the exploration settled nothing.>

- <decision>: <reason>

<!-- /scope ONLY -->
## Shape Signals (signals, not verdicts — Phase 1 runs the walk)

Inputs the exploration gathered for the R6 predicate walk. Phase 1 emits
its own verdict for P1, P2, and P3 with its own reason; these lines are
evidence for that walk, never a result of it. P2 is deliberately absent:
it is a filesystem fact and cannot be pre-supplied.

**Architectural alternatives left open (P1 input):**
- <alternative the exploration surfaced and did not close>

**Complexity signals (P3 input):**
- <signal, e.g. "the author described this as touching three subsystems">

<Write "none surfaced" under either heading rather than omitting it —
an absent heading reads as an omission, an explicit "none surfaced" is a
finding.>
<!-- END /scope ONLY -->

## Upstream Observations

<Documents the exploration found that may bear on the chain, as prose
with paths. These are observations, not links: the parent validates any
upstream it is given through its own Phase 0 battery, and a path named
here is never consumed as an upstream. See "What travels out of band"
below.>

- <path>: <what it is and why it might matter>

## Coverage Notes

<What the exploration did NOT answer that the parent's chain should.
Gaps, unresolved tensions, questions the discover-converge loop opened
and left open.>
```

**What the file may never contain**, stated in the clause that consumes
it as well as here: frontmatter `status:` values for any document; git
blob hashes or any content fingerprint; the repo's visibility; a claim
that an artifact exists at a canonical path; a validated `--upstream`
value; a P2 verdict; or any parent state field (`planned_chain`,
`chain_skipped`, `exit`, `child_snapshots`). Each is a filesystem or
git read the parent performs itself on every run.

**What travels out of band, and why** (Q5):

- **The topic slug** — positional argument. Both parents validate it at
  Phase 0 and re-validate slugs recovered from on-disk paths per R23,
  which this decision extends to the Slot 7 match.
- **`--upstream <docs/roadmaps/ROADMAP-*.md>`** on the `/scope` arm and
  **`--upstream <docs/visions/VISION-*.md>`** on the `/charter` arm. A
  path inside the handoff would enter the run through a route with no
  validation site; the flag enters through Phase 0's battery —
  canonicalize and bounds-check, basename enforcement, reject under
  `wip/`, require git-tracked, and the public-repo-to-private-upstream
  visibility check — and is re-validated on every subsequent resume. The
  flag is the only legal way in.
- **The retired `--upstream <STRATEGY>` value.** `/explore`'s current
  roadmap handler passes a discovered STRATEGY to `/roadmap`
  (`phase-5-produce-roadmap.md:43-59`). Once that arm routes to
  `/charter`, the value has no receiver: `/charter` enforces a `VISION-`
  basename, and a `/charter` chain produces its own STRATEGY and
  pre-populates `/roadmap`'s upstream from it
  (`phase-2-chain-orchestration.md:416-421`) — an externally-discovered
  STRATEGY would compete with the one the chain is about to write. The
  value is therefore **retired as a flag and demoted to prose** in
  `## Upstream Observations`. This is the same move the roadmap handler
  already makes one altitude down: "When the exploration found a VISION
  but no STRATEGY, omit the flag and name the VISION in the handoff
  artifact's prose instead" (`:56-57`).
- **Nothing else.** `--parent-orchestrated` is a parent-to-child
  suppression flag (`/charter phase-resume.md:458-477`) and is not the
  router's to pass.

**Who deletes it, and when** (Q4). Nobody deletes it explicitly; the
existing sweep does, and until then it is inert.

- `/explore` does not delete it — its cleanup rule already defers to the
  target workflow (`phase-5-produce.md:56-58`).
- The parent does not delete it on consumption. It is not mutated, not
  marked, not moved. Double-consumption is prevented structurally: the
  ladder is first-match-wins and the state-file rows (`/scope` meta 1-4,
  `/charter` rows 1-4) sit above Slot 7, so once Phase 0 has written the
  state file the handoff is never consulted again.
- **A run that bails at Phase 3 keeps it.** Phase 4 runs only after
  Phase 3's R9 hard-finalization check returns success
  (`phase-4-cleanup.md:16-20`); a run that fails R9 stops at Phase 3 with
  everything on disk. The next invocation matches on the state file and
  resumes at `phase_pointer` — the handoff is not re-read, but it is
  there for a reader reconstructing the chain.
- **Phase 4 sweeps it on every exit path**, as a member of
  `wip/scope_<topic>_*`, including `abandonment-forced` where the child
  prefixes are preserved. That asymmetry is correct: child scratch is
  preserved because a resumed session needs the child's in-flight state;
  the handoff has already been absorbed into Phase 1 and, on that path,
  into the force-materialized Draft.
- **Recommended, optional:** the parent records `consumed_handoff: <path>`
  in its state file when Slot 7 fires, under the same conditional-field
  discipline as `consumed_upstream:` (present when and only when the
  trigger fired, absent otherwise — never `none`, never null). It is not
  needed to prevent re-consumption; it is needed so a reader of the state
  file can tell that Phase 1's discovery input was pre-loaded rather than
  author-supplied, which is exactly the provenance question the
  framing-shift answer raises.

## Consequences

**What gets cheaper.** The `/scope` clause is the minimum possible: match
one exact path, read it, enter Phase 1 with it pre-loaded. No glob, no
content test, no disambiguation, no widening of R14's permitted sources.
Phase 4 needs no edit. `/charter`'s closed write-target set needs no
edit — the parent still writes exactly five places, and the handoff is a
read target.

**R26 is partly resolved as a side effect.** `/explore` Phase 0 creates a
`docs/<topic>` branch, and both parents have a branch-matching row that
resumes at Phase 1 while skipping Phase 0 — on what the author
experiences as a first invocation. Slot 7 sits above those rows in both
ladders, so on the routed path the handoff match wins and the branch row
never fires. What remains for R26 is the no-handoff-but-branch-exists
case: a terminal arm that created a branch, or a routed run reached after
the handoff was swept.

**R28's exclusion must widen.** `wip/scope_<topic>_*` currently contains
exactly one filename. The Phase-1 Bail test "force-materialize if any wip
state exists for the topic" must exclude the parent's whole prefix, not
just the state file, or an explore-then-bail run lands in
abandonment-forced with nothing to materialize. One sentence, in a clause
this PRD is already rewriting — but it must be written.

**Slot 7 stops being vacuous, in four places for `/scope`.**
`phase-resume.md:80-84` (the slot body), `SKILL.md:358` ("Slot 7 is
vacuous in v1"), `SKILL.md:415` (the reference table's "Slot 7
(vacuous)"), and the slug re-validation enumeration, which names Slot 5
and Slot 6 only in three places (`phase-0-setup.md:233-244`,
`SKILL.md:278-283`, `phase-resume.md:74-78`) and must name Slot 7 per
R23. For `/charter`, `SKILL.md:222-224` ("slot 7 … is unfilled because
`/charter` has no feeder-doc case") becomes false.

**`/charter`'s placement gets easier, and row 8's narrowing gets
smaller.** With a distinct filename, row 8 no longer needs to tell a
handoff from a `/vision` partial run — it needs only a note that it does
not match handoff artifacts, which is R22's defense-in-depth half. The
structurally-correct slot-7 placement (a row 8.5, avoiding the shared
meta-ladder renumbering the file explicitly warns against at
`phase-resume.md:264-269`) becomes viable rather than being forced into
row 8 as the lower-risk edit. Placement is Decision 3's to settle; this
decision removes the constraint that was pushing it toward row 8.

**The child-level clauses lose their producer, which R24 must handle
honestly.** `/prd`, `/vision`, and `/roadmap` each detect
`wip/<child>_<topic>_scope.md` and skip their own scoping phase. Under
A, `/explore` stops writing those files. The only surviving producer is
`/charter` → `/roadmap` (`phase-2-chain-orchestration.md:416-421`);
`/scope` pre-populates nothing today. R24 re-grounds the clauses on "the
parent", and for `/prd`, `/design`, and `/brief` that parent does not
currently produce anything — so R24's edit is either a producer statement
that is true only for `/roadmap`, or it comes with a decision that
`/scope` starts pre-populating. This is the largest downstream
consequence of the recommendation and it is called out again below.

**One line of prose recovers B's advantage.** The sibling-path notice —
each parent checking the other's handoff path and naming it when found —
costs one clause per parent and converts a silent miss into a stated one.
Without it, A is strictly worse than B on the mis-addressed case.

**Two files means the router branches.** `/explore` must choose the
filename per arm. It already branches per arm to choose the `--upstream`
flag, so this adds a filename to an existing branch rather than creating
one.

## Open Sub-Questions

1. **Does `/scope` pre-populate child handoffs from the parent handoff?**
   The consequence above is the live question: with `/explore` out of the
   `wip/prd_<topic>_scope.md` business, either `/scope` Phase 2 writes
   child handoffs the way `/charter` writes `/roadmap`'s, or the
   handoff's content reaches `/prd` through the BRIEF the chain
   produces. The second is cleaner — the chain's own artifact carries it
   forward, and no parent reaches into a child's namespace — but it
   leaves `/prd`'s detection clause with no producer on the `/scope`
   path, which R24's wording has to state plainly rather than paper
   over. Belongs to whichever decision owns R24.

2. **Is `consumed_handoff:` worth a state-schema field?** Recommended
   above as an audit affordance, not a mechanism. It costs an entry in
   both parents' state schemas plus the conditional-field gating
   discipline (`/charter phase-state-management.md`), and the ladder
   ordering already prevents the failure it might look like it prevents.
   A reviewer could reasonably cut it.

3. **Does the sibling-path notice belong in the ladder or in Phase 0?**
   It is not a resume decision — it fires on a cold start, when no row
   matches — so the ladder is an awkward home. Phase 0's context
   resolution is the better one, but that puts a handoff-aware check
   outside the clause R20 asks for. A drafting question, not a
   contract one.

4. **Should `## Upstream Observations` name paths at all in a public
   repo?** The section is prose naming documents the exploration found.
   The workspace visibility rule governs document references, and a
   handoff lives in `wip/` and is deleted before merge — but it is on a
   feature branch and visible during PR review, which is the same
   exposure `/charter`'s state-file security note reasons about
   (`phase-resume.md:646-654`). If an exploration in a public repo found
   a private-repo STRATEGY, naming its path here is the same class of
   leak the `--upstream` visibility check exists to prevent. Probably
   resolved by applying the existing check to the section; needs
   someone to say so.

5. **Does `/execute` need anything?** No, and it should be stated rather
   than left inferred: `/execute` takes only a PLAN path
   (`SKILL.md:35-45`), its input is a durable committed document, and the
   router writes nothing for that arm. Confirmed by the Phase 2 research;
   recorded here so a later reader does not go looking for a third
   handoff file.
