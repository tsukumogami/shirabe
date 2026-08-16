# Decision 5 — The `chain_skipped[].reason` Vocabulary and Entry Key

Design Phase 2 decision report for `scope-chain-mandatory-steps`. Governing
requirements: R4, R5, R6 of `docs/prds/PRD-scope-chain-mandatory-steps.md`.

Every line reference below was re-derived against the worktree at
`/home/dgazineu/dev/niwaw/tsuku/tsuku+shirabe_inconsistencies-03b57366/public/shirabe/.claude/worktrees/scope-chain`,
not taken from prior research. Where the prior research
(`wip/research/prd_scope-chain-mandatory-steps_phase2_pattern-surface.md` §4, §6)
and this report differ, the difference is called out.

## Question

What shape does the bounded `chain_skipped[].reason` vocabulary take, which
entry key survives, and where does the vocabulary live so that both parents and
a future third inherit it without copying?

## Verified Reason Inventory

Method: `grep -rn 'chain_skipped' skills/ references/` (46 hits, all read),
plus `grep -rn 'reason:'` across both parents, plus a full read of all four
`skills/scope/references/decision-record-*.md` templates and all three
`skills/charter/references/templates/*.md`, plus a structural walk of both
`evals.json` files. The two `/scope` re-evaluation templates and all three
`/charter` templates contain no occurrence of `skip` in any casing and write no
reason — the prior research's implicit claim that only the two rejection
templates carry reason strings is confirmed.

| # | Ground | Reason as written today | Fixed string or free prose | Writer | Sites |
|---|---|---|---|---|---|
| 1 | Child's durable artifact already settled at the canonical path (re-entry protection) | `settled-artifact-at-canonical-path-reentry-protection` | **fixed** | `/scope` Phase 1 | `skills/scope/references/phases/phase-1-discovery.md:112`, `:424`; `skills/scope/references/state-schema.md:85-86`; `skills/scope/references/phases/phase-2-chain-orchestration.md:781-783`; graded at `skills/scope/evals/evals.json:111`, `:116`, `:391` |
| 2 | A Reject at the PRD boundary ended the chain; `/design` and `/plan` never ran | `"PRD-boundary rejection"` | **free prose** (title-cased, spaced, quoted inside template prose) | `/scope` Phase 2, via template | `skills/scope/references/decision-record-prd-rejection.md:74-76`; graded at `skills/scope/evals/evals.json:176` |
| 3 | A Reject at the DESIGN boundary ended the chain; `/plan` never ran | `"DESIGN-boundary rejection"` | **free prose**, same shape as #2 | `/scope` Phase 2, via template | `skills/scope/references/decision-record-design-rejection.md:72-74`. **No eval grades this string.** |
| 4 | Author declined an ALWAYS child at its named confirmation prompt | `author declined the roadmap at the confirmation prompt` | **free prose**, and at finalization it is a *placeholder for the author's own words*: `reason: <the author's declination>` | `/charter` Phase 2 | `skills/charter/references/phases/phase-2-chain-orchestration.md:384-393`; `skills/charter/references/phases/phase-finalization.md:85-87`; graded at `skills/charter/evals/evals.json:188`, `:193` — **both elide the value as `<declination>` / `...`** |
| 5 | The author supplied the upstream artifact via `--upstream`, so the auto-skip fired on that value rather than the canonical path | *unfixed* — "a reason naming the supplied upstream" | **free prose, unspecified** | `/charter` Phase 2 | `skills/charter/references/phases/phase-2-chain-orchestration.md:44-47`; graded at `skills/charter/evals/evals.json:262` |
| 6 | A settled VISION exists and the thesis-shift override did not fire | *unfixed* — no reason named at all | **free prose, unspecified** | `/charter` Phase 2 | `skills/charter/references/phases/phase-2-chain-orchestration.md:62-65` ("no signal leaves the existing VISION in place and the chain skips the child, recording it in `chain_skipped`") |

Six grounds; two fixed strings (both `/scope`'s, and only one of them a real
identifier), four free prose, two of the four not even specified. That
distribution is the defect: the one parent that closed the field closed it to a
single identifier, and the other declared the freedom load-bearing
(`skills/charter/references/phases/phase-state-management.md:143-146`: "the
free-text human-readable reason … The reasons are NOT parsed by tooling").

Two negatives, both verified:

- **`/comp` is never recorded**, by explicit rule, in the parent
  (`skills/charter/references/phases/phase-2-chain-orchestration.md:136-146`)
  and in the pattern (`references/parent-skill-pattern.md:221-225`).
- **No ground exists for a chain that terminated before a child's turn**
  outside the boundary-rejection case. `grep -riE 'remaining children|never
  run|unrun|not reached'` across `skills/scope/`, `skills/charter/` and
  `references/` returns exactly two hits
  (`skills/scope/references/state-schema.md:91`,
  `skills/scope/references/phases/phase-1-discovery.md:431`), both describing
  the boundary rejection. `/scope`'s abandonment-forced exit
  (`skills/scope/references/phases/phase-3-exit-finalization.md:135-210`) writes
  `triggering_child:` and `partial_phase_reached:` and touches `chain_skipped`
  nowhere.

### R4's "a member with no writer SHALL NOT ship" — the fifth member is refuted

The prior research proposed `chain-terminated-before-invocation` for the bail
and abandonment-forced exits and flagged that it found no writer. **Refuted, and
dropped.** There is no such writer, and there is no latent one either: the only
case where children are recorded because the chain ended early is the
settled-upstream Reject, which ground #4 of the proposed vocabulary
(`<boundary>-boundary-rejection`) already names. A bail at the chain proposal
fires before `planned_chain` has anything to skip; an abandonment-forced exit
records the *triggering* child, not the unreached ones. Shipping the member
would create exactly the dead slot `skills/scope/evals/evals.json:284` argues
against.

## Decision Drivers

**Enforceability is the stated purpose.** R4's operative clause is "SHALL NOT be
able to express a worth judgment" — a capability constraint on the field, not a
behavioral constraint on writers. Only membership in a fixed set delivers that.

**The corpus already ran the open-list experiment and it failed.**
`skills/scope/references/state-schema.md:86-89` is a stated prohibition on
exactly this ("a child is never recorded here because the chain judged its
artifact not worth producing, since `/scope` makes no such judgment"). It held
for `/scope` and did not propagate: `/charter`, reading the same pattern-level
"free-text reasons", wrote four unbounded grounds, two of them unspecified. One
open field, two parents, incompatible closures — that is the observed failure
mode, not a hypothetical one.

**The field is durably public and the child name travels with the reason.**
`skills/charter/references/phases/phase-state-management.md:435-455` puts
`chain_skipped[].reason` on the explicit leak-surface list: "Durable on the
feature branch pre-merge; public." Free text in a public committed file is the
surface through which a private-only artifact type gets named. This argument is
independent of enforceability and would survive even if a review gate were
reliable.

**Migration must not collide with R37.** R37 requires `/charter`'s four
roadmap-declination scenarios (`skills/charter/evals/evals.json`, evals 12-15,
`r7-*`) to survive byte-identical, and `/scope`'s `chain-shape-is-constant`
(eval 17) to keep three of four expectations verbatim. Any vocabulary or key
choice that forces an edit inside those scenarios puts two requirements of the
same PRD in conflict. This constrains the key choice decisively (see
Recommendation).

**Extension must not be a second discipline.** R4 names
`references/parent-skill-child-inspection.md:65-67` — "The table grows as new
parents land children with new shapes. Each parent that invokes a new child
shape adds a row; new rows go through the parent's own PR review" — as the
discipline to reuse. The AC requires the schema to *cite* it, not paraphrase it.

## Considered Options

### A. Closed enum at the pattern layer, with `detail:` sibling and grow-by-PR-review

**Enforceability.** A grep can check the whole property. Membership is a regex
over a fixed set: `^(settled-artifact-at-canonical-path-reentry-protection|upstream-supplied-by-author|author-declined-at-confirmation-prompt|(prd|design)-boundary-rejection)$`.
An eval can assert it per scenario ("the recorded reason is a member of the
vocabulary"), and a corpus check can assert it statically over the writer sites
— `grep -rn 'reason:' skills/*/references/` yields a finite set of literals that
either are members or are not. What a grep still cannot check is whether
`detail:` carries a worth judgment. That is acceptable because `detail:` is
declared never to be the ground: a skip has to be licensed by a member first,
and prose in `detail:` is commentary on a licensed skip rather than the licence
itself. The unenforceable residue is decoration, not authorization.

**Extensibility when a fourth parent lands.** The parent adds a member to the
pattern vocabulary and to its own state schema in the same PR, and the addition
goes through that parent's own PR review. Identical to how the child-shape table
already grows. The cost of a wrong addition is one review, and the addition is
visible as a diff to a shared reference file — which is the property the open
list lacks, where a new ground appears only as prose inside one parent's phase
file.

**Migration.** 18 sites (enumerated below): 2 pattern-layer, 7 in `/scope`, 9 in
`/charter`. Four of the 18 are graded eval strings. Crucially, **zero R37-protected
strings are touched**: `/charter` eval 12 elides the reason as `<declination>` /
`...` at both `:188` and `:193`, so the enum change passes through it
byte-identically, and `/scope` eval 17 does not mention `chain_skipped` at all.
`/scope`'s one written identifier (#1) is adopted verbatim as a member, so its
three graded occurrences (`:111`, `:116`, `:391`) need no reason edit.

**Public surface.** Closes the reason side structurally, for every future parent
rather than for the two that exist. It does not close the child-name side — see
question 4.

### B. Open list with a stated prohibition, enforced by review

**Enforceability.** None, for the property that matters. A grep can find a
string; it cannot decide whether "the strategy was too thin to warrant
sequencing" is a worth judgment. The prohibition would be a comment. Reviewers
do catch things, and the prohibition would be stated in a shared reference file
rather than only in `/scope`'s local schema, which is a genuine improvement over
today — but it is an improvement in *reach*, not in *checkability*, and R4 asks
for checkability.

**Extensibility.** Free, trivially. This is B's only real advantage: a fourth
parent writes whatever ground it has and nobody adds a row anywhere.

**Migration.** Near zero. Only the pattern-level sentence changes, plus a
prohibition clause. The key decision (R6) would still have to be made
separately.

**Public surface.** Unaddressed. Free text is exactly the leak vector
`/charter`'s own security discussion names, and B keeps it. B also cannot be
reconciled with R4 as written: the requirement says the vocabulary "SHALL NOT be
able to express a worth judgment", and an open list can. B fails the requirement
on its face rather than on a judgment call.

**Preserved value worth naming.** `/charter` states a real purpose for the free
text — "durable evidence for human readers reviewing the chain"
(`phase-state-management.md:145-146`) — and `phase-finalization.md:85-87`
deliberately carries the author's own declination words. Option A preserves both
by moving them to `detail:` rather than deleting them; B is not needed for it.

### C. Structured reason — small enum of grounds plus a required typed qualifier

Shape: `{ground: reentry-protection, artifact: docs/prds/PRD-x.md}`.

**Enforceability.** Strictly the best on paper. The ground is a member and the
qualifier is typed, so a check can assert both membership *and* the qualifier's
shape (`^docs/.*\.md$` for a path, a member of `{prd, design}` for a boundary).
With no free-text field at all, the public-surface argument closes completely
rather than mostly.

**Where it breaks.** The six grounds do not share a qualifier type. Re-entry
protection's qualifier is a path plus a settled status. The author declination's
qualifier is a prompt identifier — and `/charter` currently wants the author's
own prose in that slot (`phase-finalization.md:85-87`), which a typed qualifier
forbids outright, so C either loses that information or admits a free-text
qualifier and becomes A with more ceremony. The boundary rejection's qualifier
is the boundary, which the member name already encodes. So C forces either a
per-ground discriminated union — three qualifier schemas gated on the ground
value, inside a list entry, which drags invariant I-5's conditional-field gating
(`references/parent-skill-state-schema.md:125-134`, R9 Part 3 at `:245-250`)
down into a nested structure it was never written for — or an optional
qualifier, which is A.

**Extensibility.** Worst of the three. A fourth parent adds a ground *and* a
qualifier type, and the qualifier type is precisely the part a PR reviewer is
least equipped to evaluate in isolation.

**Migration.** Heaviest. C renames `reason:` to `ground:`, so every one of the
18 sites changes plus every site that merely names the field — including
`skills/charter/references/phases/phase-state-management.md:443`'s leak-surface
entry and `references/parent-skill-pattern.md:131`. It also collides with R4's
own wording, which says "free text SHALL move to an optional sibling field",
naming a sibling rather than a replacement. And it would put a second key
decision (`reason:` vs `ground:`) alongside R6's, in a decision whose whole point
is that unresolved key divergence is what let this drift.

## Recommendation

**Take A.** Closed enum at the pattern layer, four members, optional `detail:`
sibling, extension by the grow-by-PR-review discipline cited from
`references/parent-skill-child-inspection.md`.

A is the only option that satisfies R4 as written. B cannot express the
constraint, and C expresses it at a structural cost the corpus's own
conditional-field gating rules would have to absorb inside a list entry. A also
absorbs C's best idea without its cost: the discriminating information C would
have put in a typed qualifier is carried in the member name itself
(`<boundary>-boundary-rejection` encodes the boundary; `upstream-supplied-by-author`
encodes that the observation was the flag rather than the path), leaving
`detail:` to carry only what a human reader wants and no checker needs.

**The entry key SHALL be `child:`.** Three reasons, in decreasing weight:

1. **Choosing `name:` would violate R37.** `/charter` eval 12
   (`r7-roadmap-declined-non-actionable`) spells the key twice — at
   `skills/charter/evals/evals.json:188` inside `expected_output`
   ("chain_skipped carries a { child: roadmap, reason: <declination> } entry")
   and at `:193` inside an expectation ("records the declination in
   chain_skipped as a { child: roadmap, reason: ... } entry"). R37 requires
   `/charter`'s four roadmap-declination scenarios to survive **byte-identical**.
   `name:` forces two edits inside a scenario another requirement of the same
   PRD freezes. `child:` leaves both strings untouched.
2. **Edit-site count, counted for real.** Choosing `child:` costs **three**
   sites, all in `/scope`: `skills/scope/references/state-schema.md:81`
   (`{name, reason}`), `skills/scope/references/phases/phase-1-discovery.md:423`
   (`- name: prd`), and `skills/scope/evals/evals.json:111` (`{ name: prd,
   reason: … }`). Choosing `name:` costs **seven**: `/charter`'s
   `phase-state-management.md:143` and `:258`,
   `phase-2-chain-orchestration.md:385` and `:391`, `phase-finalization.md:85`,
   and the two eval strings above. *Correction to prior research:* §6.4 of
   `prd_..._phase2_pattern-surface.md` reports five `/scope` sites, counting
   `skills/scope/evals/evals.json:116` as spelling out `{ name: prd, … }`. It
   does not — `:116` reads "records /prd in chain_skipped: with reason
   'settled-artifact-…'", with no key. Only `:111` carries the key. The
   direction of the recommendation is unchanged; the margin is 3 vs 7 rather
   than 5 vs 4, which makes it wider, not narrower.
3. **Semantic alignment.** `child:` matches `parent_orchestration:`'s
   `invoking_child:` (`references/parent-skill-state-schema.md:189`,
   `references/parent-skill-pattern.md:417`), and both `planned_chain` and
   `chain_ran` are lists of child names, so `child:` reads as the same thing the
   sibling fields hold. `name:` reads as a generic entry label and is the odd
   one out against every neighbouring field.

## Proposed Vocabulary

Four members. Every one has at least one writer in `skills/scope/` or
`skills/charter/` today, satisfying R4's no-orphan-member rule and its AC.

| Member | Means | Current writers |
|---|---|---|
| `settled-artifact-at-canonical-path-reentry-protection` | The child's durable artifact already sits at a settled status at the child's canonical path, so invoking the child would overwrite a settled document. The settled set is fixed before the run. | `/scope` Phase 1 (inventory #1, all children); `/charter` Phase 2 `/vision` against an Accepted or Active VISION with no thesis shift (#6) |
| `upstream-supplied-by-author` | The author supplied the child's artifact with `--upstream`, and the value passed the parent's Phase 0 validation, so the auto-skip fired on the supplied value rather than on the canonical path. | `/charter` Phase 2 `/vision` under `consumed_upstream:` (#5) |
| `author-declined-at-confirmation-prompt` | The author declined an ALWAYS child at that child's named declination prompt, after the upstream artifact was on disk. The parent computed nothing. | `/charter` Phase 2 roadmap declination (#4) |
| `<boundary>-boundary-rejection` | A Reject at a settled-upstream boundary ended the chain and the children after that boundary never ran. `<boundary>` is drawn from the pattern-level `boundary:` enum (`prd \| design`, `references/parent-skill-state-schema.md:78-87`), so the closed set is `prd-boundary-rejection` and `design-boundary-rejection`. | `/scope` Phase 2, both rejection templates (#2, #3) |

**Not shipped:** `chain-terminated-before-invocation`. No writer, and none
latent — see the Verified Reason Inventory.

**Entry shape:**

```yaml
chain_skipped:
  - child: vision
    reason: upstream-supplied-by-author
    detail: docs/visions/VISION-platform.md
```

`child:` is the child-name string, drawn from the same vocabulary as
`planned_chain`. `reason:` is a member of the closed vocabulary and is the
ground. `detail:` is optional free text carrying the specifics a human reader
wants — which path was supplied, what the author actually said at the prompt —
and is **never** the ground. A `detail:` that reads as a worth judgment does not
license the skip; the member did.

**Where it lives:** `references/parent-skill-state-schema.md`, in the
`### Chain-tracking` subsection under `## Pattern-Level Invariants`, as a new
`#### chain_skipped[].reason vocabulary` block inserted immediately after the
three-field bullet list (currently lines 141-145) and before the
conditional-on-chain-shaped-parents paragraph at line 147.

That location, and not the `## Extension Discipline` section, because
Chain-tracking is where a reader checking a state file's `chain_skipped` entry
arrives, and because Extension Discipline's three rules are about *field* names
and gating, not about a field's value domain. The extension path is stated
inside the vocabulary block as a citation:

> The vocabulary grows the way the per-parent child-shape table in
> [`parent-skill-child-inspection.md`](parent-skill-child-inspection.md) grows.
> A parent that lands a genuinely new ground adds the member here and to its own
> state schema in the same PR, and the addition goes through that parent's own
> PR review. No parent may write a reason outside this list; a ground that is
> not here is not yet a ground.

**How both parents and a future third inherit it without copying:** by the
cite-don't-re-derive discipline the corpus already uses for the 5-field minimum,
the four invariants, and the topic-slug regex.
`skills/charter/references/phases/phase-state-management.md:53-74` states the
mechanism in so many words — the minimum "is **cited**, not re-derived, from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`" — and
`skills/scope/references/state-schema.md:3-11` does the same by reference. Each
parent's own schema therefore states only two things: that `reason:` is drawn
from the pattern vocabulary, cited by path, and **which members that parent
writes**. `/scope` writes three (`settled-artifact-…`, `prd-boundary-rejection`,
`design-boundary-rejection`); `/charter` writes three (`settled-artifact-…`,
`upstream-supplied-by-author`, `author-declined-at-confirmation-prompt`). A
third chain-shaped parent inherits the list by citing the same file; `/execute`
inherits vacuously, since it omits the triad under I-5
(`skills/execute/SKILL.md:426-430`).

## Migration Sites

18 sites. `/scope`'s written identifier is adopted verbatim as a member, so
three of `/scope`'s graded eval strings need no reason edit.

| # | file:line | Today | Change |
|---|---|---|---|
| 1 | `references/parent-skill-state-schema.md:144-145` | "**`chain_skipped`** — children the chain decided to skip, with free-text reasons." | Entry shape `{child, reason, detail?}`; reason drawn from the vocabulary below |
| 2 | `references/parent-skill-state-schema.md:` (new block after `:145`) | — | The four-member vocabulary table, the `detail:` rule, and the grow-by-PR-review citation to `parent-skill-child-inspection.md` |
| 3 | `skills/scope/references/state-schema.md:81` | `list of {name, reason} entries` | `list of {child, reason, detail?} entries` (**key**) |
| 4 | `skills/scope/references/state-schema.md:85-91` | "Phase 1 writes exactly one reason … Phase 2 writes one further reason" | Cite the pattern vocabulary; enumerate the three members `/scope` writes. Also satisfies R32, which corrects the "one further reason" count — Phase 2 writes two |
| 5 | `skills/scope/references/phases/phase-1-discovery.md:423` | `- name: prd` | `- child: prd` (**key**) |
| 6 | `skills/scope/references/phases/phase-1-discovery.md:428-432` | "That is the only reason Phase 1 ever writes … (Phase 2 writes one other reason …)" | Same count correction as #4, phrased against the vocabulary |
| 7 | `skills/scope/references/decision-record-prd-rejection.md:74-76` | `chain_skipped:` records them with reason `"PRD-boundary rejection"` | `prd-boundary-rejection` |
| 8 | `skills/scope/references/decision-record-design-rejection.md:72-74` | `chain_skipped:` records it with reason `"DESIGN-boundary rejection"` | `design-boundary-rejection` |
| 9 | `skills/scope/evals/evals.json:111` (eval 8, `us-2-prd-auto-skip`) | `chain_skipped contains { name: prd, reason: settled-artifact-… }` | `{ child: prd, reason: settled-artifact-… }` (**key only**; reason unchanged) |
| 10 | `skills/scope/evals/evals.json:176` (eval 11, `us-4-prd-rejection-sub-shape`) | `chain_skipped records /design and /plan with reason 'PRD-boundary rejection'` | `'prd-boundary-rejection'` |
| 11 | `skills/charter/references/phases/phase-state-management.md:143-146` | "`{child, reason}` … the free-text human-readable reason … The reasons are NOT parsed by tooling" | Cite the pattern vocabulary; name the three members `/charter` writes; state that `detail:` carries the human-readable prose. The "NOT parsed by tooling" sentence is the one that most directly contradicts the enum and must go |
| 12 | `skills/charter/references/phases/phase-state-management.md:258-259` | `- child: <name>` / `reason: <free text>` | `reason: <vocabulary member>`, optional `detail:` line |
| 13 | `skills/charter/references/phases/phase-state-management.md:443-444` | Leak-surface list: "**`chain_skipped[].reason`** — free-text reasons for skipping children. Durable on the feature branch pre-merge; public." | Re-ground on `chain_skipped[].detail`. Leaving it names a free-text field that no longer exists |
| 14 | `skills/charter/references/phases/phase-2-chain-orchestration.md:44-47` | "records `/vision` in `chain_skipped` with a reason naming the supplied upstream" | `reason: upstream-supplied-by-author`, with the path in `detail:` |
| 15 | `skills/charter/references/phases/phase-2-chain-orchestration.md:62-65` | "the chain skips the child, recording it in `chain_skipped`" — no reason named | Name `settled-artifact-at-canonical-path-reentry-protection`. This closes inventory ground #6, which is unspecified today |
| 16 | `skills/charter/references/phases/phase-2-chain-orchestration.md:141-143` | The `/comp` argument's premise: "`chain_skipped[].reason` is free text that lands in the repo" | Re-ground on the child-name leak (see Open Sub-Questions / question 4). The premise becomes false the moment the enum lands |
| 17 | `skills/charter/references/phases/phase-2-chain-orchestration.md:392` | `reason: author declined the roadmap at the confirmation prompt` | `reason: author-declined-at-confirmation-prompt`, with the author's words in `detail:` |
| 18 | `skills/charter/references/phases/phase-finalization.md:85-87` | `{child: roadmap, reason: <the author's declination>}` | `reason: author-declined-at-confirmation-prompt`, `detail: <the author's declination>` |
| 19 | `skills/charter/evals/evals.json:262` (eval 17, `upstream-flag-consumed`) | "Plan skips /vision and records the skip with a reason naming the supplied upstream" | Member plus `detail:`. Not protected by R37 |

**Explicitly untouched, and verified so:**

- `skills/charter/evals/evals.json:188` and `:193` (eval 12,
  `r7-roadmap-declined-non-actionable`) — both already spell `child:` and both
  elide the reason value (`<declination>`, `...`). R37's byte-identical
  requirement is satisfied without exception.
- `skills/charter/evals/evals.json:101`, `:105`, `:223`, `:235` — all assert the
  *absence* of entries.
- `skills/scope/evals/evals.json:116` and `:391` — both name the reason as the
  bare identifier with no key, and the identifier is a member.
- `skills/scope/evals/evals.json` eval 17 (`chain-shape-is-constant`) — does not
  mention `chain_skipped`. R37's verbatim expectations are untouched by this
  decision.

## Consequences

**A grep-checkable AC becomes available.** The PRD's AC "every reason string
either parent writes today maps to exactly one member" is satisfiable
statically: `grep -rn 'reason:' skills/scope/ skills/charter/` yields a finite
literal set, and each literal is a member or it is not. The companion AC
"`grep -rn 'chain_skipped' skills/scope/ skills/charter/` shows one entry key,
not two" is satisfied by the three `/scope` edits.

**`/charter`'s security discussion loses its stated foundation and gains a
better one.** Two `/charter` passages argue from "`chain_skipped[].reason` is
free text that lands in the repo" — `phase-2-chain-orchestration.md:141-143`
(the `/comp` argument) and `phase-state-management.md:443-444` (the leak-surface
list). Both premises go false when the enum lands. Neither conclusion changes,
but leaving the prose would leave two arguments resting on a fact the same PR
deleted. Sites 13 and 16 are not cosmetic.

**The author's own words survive, in a field that is not the ground.**
`/charter`'s finalization deliberately records the author's declination prose.
Under the enum that prose moves to `detail:`, which keeps the human-readable
evidence `phase-state-management.md:145-146` says the field exists for while
removing its authority.

**Two currently-unspecified grounds get specified.** Inventory grounds #5 and #6
have no fixed reason today; the vocabulary gives them one. That is a small
behavioral tightening of `/charter` beyond the mechanical migration, and it
should be stated as such rather than smuggled in as a rewording.

**A fourth ground now costs a shared-file diff.** That is the intended cost. The
failure this decision addresses is that a new ground could previously appear as
prose inside one parent's phase file with nothing to reconcile it against.

## Open Sub-Questions

**1. Does a closed enum let `/comp` be recorded safely? No — the never-planned
category still has to exist.** The enum bounds the *reason*; it does nothing to
the *child name*. A `chain_skipped` entry for `/comp` in a public repo's
committed state file would carry `child: comp`, naming a private-only artifact
type, regardless of how bounded the reason is. Recording it would also require
`comp` in `planned_chain` — `chain_skipped` is for children that were planned
and then dropped
(`skills/charter/references/phases/phase-2-chain-orchestration.md:143-144`) —
so the disclosure would land in two fields, not one. And the structural half of
the argument is untouched by any vocabulary: a conditional feeder whose
three-condition gate never opened was never planned, so there is nothing to
record, which is what `references/parent-skill-pattern.md:221-225` already says.

So the enum changes the calculus in one direction only, and it is the direction
that makes the enum's own public-surface argument work: it closes the reason
leak for every *planned* child in every future parent, rather than leaving the
corpus to rely on `/charter` having noticed the problem for one feeder. R5's
never-planned category is doing different work — protecting the child name — and
still needs to be first-class. The concrete follow-on is site 16: `/charter`'s
`/comp` rule must be re-grounded on the child-name argument before its current
free-text premise stops being true.

**2. Should `settled-artifact-at-canonical-path-reentry-protection` and
`upstream-supplied-by-author` collapse into one member?** Both are the
Mandatory-with-auto-skip gate; they differ only in what the parent observed. A
single member with the observation in `detail:` would be defensible and would
make the vocabulary three members. Recommended against, and flagged rather than
closed: the reader consequence differs materially — under re-entry protection an
artifact for this topic slug exists at the canonical path, and under a supplied
upstream no artifact under this slug exists at all. Collapsing puts that
distinction in the field explicitly declared never to be load-bearing. Worth one
line of confirmation from whoever owns the state-schema edit.

**3. `/scope`'s `planned_chain` and re-entry protection interact in a way this
decision does not settle, and Decision 2's draft may have it backwards.**
`skills/scope/references/phases/phase-1-discovery.md:400-404` and
`phase-2-chain-orchestration.md:776-779` both say `planned_chain` is the chain
"minus any child held back by re-entry protection" — held-back children appear
in `chain_skipped` and *not* in `planned_chain`. The prior research's draft
schema wording
(`prd_scope-chain-mandatory-steps_phase2_pattern-surface.md` §6.3) asserts the
opposite for `/scope`: "a child held back by re-entry protection is recorded in
`chain_skipped` rather than dropped from the list." That contradicts both
`/scope` sites, and it also puts `/scope` at odds with the rule that
`chain_skipped` holds only children that were planned. This is R5 territory
rather than R4's, but the vocabulary block sits three lines from the triad
contract and the two edits will land in the same PR, so it needs resolving
before either is written.

**4. Do the two `/scope` rejection templates need the vocabulary cited, or only
the identifier used?** Sites 7 and 8 currently name the reason inside
Consequences prose in a template a human fills in. Substituting the identifier
is mechanical, but the template is the only place either string exists, and a
template is a weaker guarantee than a schema clause. Whether the two boundary
members also need a schema-side statement in
`skills/scope/references/state-schema.md` naming the templates as their writers
is a small call for the implementer; site 4 is where it would go.
