# Phase 5 security review — DESIGN-scope-artifact-persistence

> **Re-review at `61592e7` appended at the end of this file.** The five blocking
> findings below are closed. One new blocking finding (B6) and five residuals
> remain. Read the re-review section for current status; the original findings
> are kept for the audit trail.

Audited against the six pattern-level contracts in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md`, plus the six
questions in the review brief. Sources read: the DESIGN, `PRD-scope-artifact-persistence.md`,
all six decision reports, `skills/scope/SKILL.md`,
`skills/scope/references/phases/phase-{0,2,3,4}-*.md`,
`skills/scope/references/state-schema.md`, `.github/workflows/validate-docs.yml`.

**Verdict: 5 blocking, 6 non-blocking.**

The design's security posture is broadly right and its central structural claim —
step 6 before step 7, so a failed record aborts with nothing lost — is sound and
worth keeping exactly as stated. The problems are all of one kind: the design
states a conclusion the underlying mechanism does not yet reach. Three of the five
blocking findings are cases where the design *claims* a surface is closed and the
enumeration it points at does not close it.

---

## BLOCKING

### B1. The amended write-target set is not declared where the pattern says it lives

**Location.** `## Solution Architecture` → Components table; `## Security
Considerations` ¶1-2.

The pattern contract is explicit: "A parent's filesystem writes are confined to an
enumerated set **declared in the parent's SKILL.md**"
(`parent-skill-security.md`, Closed Write-Target Set). That declaration is
`skills/scope/SKILL.md:717-728`. It currently reads "the consolidation judgment's
deletion of an absorbed artifact under `docs/briefs/`" — the exact defect the
design sets out to correct.

`skills/scope/SKILL.md` does not appear anywhere in the Components table. The
table lists `phase-3-exit-finalization.md` with "Write-target set amended and its
three defects corrected" and stops there. Decision 1 was explicit that the
amendment "adds one bullet at `phase-3-exit-finalization.md:283-297` **and one at
`skills/scope/SKILL.md:719-723`**"; the design dropped the second.

The consequence is not cosmetic. The design's own third pre-existing defect is
"`SKILL.md` and the Phase 3 reference disagree." Amending only Phase 3 reproduces
that defect with a wider gap than before, and leaves the authoritative
declaration naming a narrower deletion set than the code performs — which is what
the R9 membership check reads.

**Required change.** Add `skills/scope/SKILL.md` to the Components table with the
same amendment (deletion set, append target, survivor mutation, Phase 4
carve-out) and its Security Considerations paragraph. State that the two sites
are kept in sync and which one is authoritative.

### B2. The terminal fold mutates the PLAN, and the design's correction removes `docs/plans/` from the set

**Location.** `## Context and Problem Statement`, fifth bulleted defect;
`## Security Considerations` ¶2.

The design names the SKILL.md-vs-Phase-3 disagreement about the PLAN as a defect
to correct, and Phase 3 currently resolves it in the direction of "Phase 3 does
not write the PLAN" (`phase-3-exit-finalization.md:299-302`). But R11 makes
DESIGN→PLAN absorbable, and at that hop the **PLAN is the survivor**. The absorb
writes four things into it: the `upstream:` splice, the `absorbed:` declaration,
the `## Status` line, and the contribution section (design steps 3, 5).

So `docs/plans/PLAN-<topic>.md` becomes a genuine mutation target of Phase 2's
absorb. If the "correction" is to strike `docs/plans/` from the enumeration on the
grounds that Phase 3 does not write it, the terminal fold's survivor mutation
lands outside the closed set — reproducing defect (b) (the survivor mutation
already outside the set) at precisely the hop this feature exists to open. The
design says "one corrected deletion target" and never enumerates the survivor
mutation's paths.

**Required change.** Enumerate the amended set explicitly in the design rather
than describing it. Concretely:

- Deletions (Phase 2 absorb): `docs/briefs/BRIEF-<topic>.md`,
  `docs/prds/PRD-<topic>.md`, `docs/designs/DESIGN-<topic>.md`. Three paths, not
  "a corrected deletion target". The PLAN is never a deletion target of a fold.
- Mutations (Phase 2 absorb): `docs/{prds,designs,plans}/{PRD,DESIGN,PLAN}-<topic>.md`
  — the survivor, at whichever hop. This is where the widened when-clause must
  land, and it must include `docs/plans/`.
- Append (Phase 2 absorb): `docs/folds.md`, fixed constant.
- The Phase-3 force-materialization and Decision-Record entries unchanged.

State that Phase 3 still does not *write* the PLAN and that Phase 2's absorb does
— the two claims are compatible once the phase is named, and the current wording
is what makes them look contradictory.

### B3. The `git grep` exit-code scheme inverts the tool's convention, and unknown statuses are unmapped

**Location.** `## Decision Outcome` → Stage 1; `## Security Considerations` ¶3;
Decision 6, "Tiers and exit codes".

The chosen scheme is 0 = clean, 1 = path-exact hits, 2 = bare-name hits only.
`git grep` exits **0 when a match is found** and **1 when none is found**. A
script that propagates the search's status — the obvious implementation of a "16ms
one-liner" — inverts the two most important outcomes: a found path citation
(git grep 0) is read as *clean* and the fold proceeds, and a clean repo (git grep 1)
is read as *path hits* and the fold is refused. The first of those is a
fail-toward-`absorb`, and it is the only one in the design.

Second, and independent: `git grep` exits >1 on error (128 for a bad pathspec,
not-a-repository, or an unreadable object). The scheme reserves no code for "the
search did not complete". The design's fail-safe sentence — "abort to `keep` when
the search cannot complete, which is observable rather than inferred" — has
nothing to observe, because status 128 falls outside the three enumerated
meanings and the routing prose says nothing about what to do with it. That is an
error swallowed by omission, and the routing agent's most likely reading of an
unmapped nonzero is "not 0, so not clean" only by luck.

**Required change.** Three clauses in the design, all cheap:

1. The script SHALL translate `git grep`'s status explicitly; its own exit codes
   are its contract and are not `git grep`'s.
2. Reserve a distinct code (e.g. 3) for "search did not complete", and pin a test
   fixture for it alongside the five Decision 6 already names.
3. State the routing default explicitly in Stage 1 prose: **any exit status other
   than 0 or 2 routes to `keep`**, including statuses the script does not define.
   Default-deny, not enumerate-and-hope.

### B4. `chain_ran:` now gates a deletion and is not in the enum re-validation list — and the existing justification for its absence is falsified

**Location.** `## Decision Outcome` → Firing condition; Components table row for
`state-schema.md`.

The firing condition reads `chain_ran:` membership, and it is the *only* thing
standing between the judgment and a document the run did not produce. A state file
whose `chain_ran:` is tampered to include a child that never ran makes the
judgment fire on a hop with a pre-existing document as its upstream — and Stage 2
can return `absorb`, which is a `git rm` of a document that predates the run. The
firing condition is the mechanism Decision 4 relies on to close R15's coverage
gap ("R15 protects deletion targets that pre-existed the run and structurally
cannot protect deletion targets the run created"). Tampering `chain_ran:` puts a
pre-existing document on the deletion path with *neither* guard covering it.

Phase 2's re-validation section explicitly declines to cover chain-shape fields:
"The chain shape itself needs no re-validation entry. `planned_chain:` is a
constant, the child names are fixed, and each child's argument path is composed
from the validated topic slug rather than from state — so a tampered state file
cannot redirect an invocation to an unexpected child or an unexpected path"
(`phase-2-chain-orchestration.md:561-565`). Every word of that reasoning is about
*invocation redirection*. This work gives the same family of fields a second job —
gating a destructive operation — and the stated justification does not extend to
it. Leaving the paragraph as written is worse than silence: it reads as a
considered exemption.

**Required change.** Add `chain_ran:` entry names to the pre-interpolation
re-validation list, validated against `{brief, prd, design, plan}`, with an
explicit note that the field's promotion from bookkeeping to deletion gate is why
the existing "chain shape needs no entry" paragraph must be rewritten rather than
left standing. An out-of-enum or unparseable entry fails the firing condition
closed — no judgment, no verdict, `keep`.

### B5. The absorb's ordered procedure omits post-absorb re-validation and the revert, and has no failure direction for the commit

**Location.** `## Solution Architecture` → "The absorb, in order", steps 1-8.

The eight-step list is the design's authoritative ordering — it is what the PLAN
will decompose and what the `[insp]` criterion reads. It contains no
post-absorb `shirabe validate` step and no revert step. Yet:

- R18 requires post-absorb re-validation covering the survivor, with revert-in-full
  on failure.
- R30 names post-absorb re-validation as one of the four decision points that must
  fail toward `keep`.
- The design's own Consequences section discusses whether a reverted absorb removes
  its record row, and reasons that "the row is uncommitted at that point" — which
  presupposes re-validation runs between step 7 and step 8, a placement the
  procedure never states.
- Today's shipped Stage 3 step 4 does exactly this
  (`phase-2-chain-orchestration.md:494-501`), so the design silently drops a
  shipped safety step.

Separately, step 8 (the commit, new under R19a) has no stated failure direction.
A commit that fails after step 7 leaves a deleted document, a mutated survivor and
an appended row in the working tree with no defined recovery. The commit is not
one of R30's four decision points, so nothing else covers it.

**Required change.** Insert the re-validation between steps 7 and 8, state that
its failure routes to R18's revert-in-full (restore the absorbed file, undo the
splice, remove the declaration, the `## Status` line and the contribution section,
un-append the row) and that the revert lands before any commit so the row is never
committed. Then state that a failed commit takes the same revert path. Finally,
state the corollary the CI check depends on: **because reverts happen pre-commit,
`docs/folds.md` is append-only at commit granularity** (see N4).

---

## NON-BLOCKING

### N1. The visibility boundary is crossed at the `upstream:` splice, not at the record

The design's claim about `docs/folds.md` is **true, but for a weaker reason than
it gives**. "It holds section names and outcomes but never section text" is not
what makes it safe — a section name could in principle be author-influenced. What
actually makes it safe is that every column is composed from a closed vocabulary:
the date, the verdict enum, the `hop:` enum, the blob hash, and two paths composed
as `docs/<type>/<TYPE>-<topic>.md` from the slug already validated against
`^[a-z0-9-]+$`. No cross-repo value and no author prose has a column to occupy. I
tried to find a channel and could not: the state file's `finding: <free text>`
stays in `wip/`, and the record's field list excludes it.

The exposure is one hop away. R17's splice copies the absorbed document's
`upstream:` into the survivor "preserving sibling and cross-repo parents". Phase
0's third check — public repo + private cross-repo upstream → omit the field, do
not pass it to a child, tell the author — fires **only on the `--upstream` flag
path** (`phase-0-setup.md:183-199`). The splice is a second write site for a
cross-repo value into a committed public field, and nothing re-checks it.

Within a single clean run the value is safe by transitivity: the firing condition
requires both endpoints run-produced, so the only externally sourced `upstream:`
in the chain is the validated ROADMAP. But `/scope` ships a drift-detection path
with a `Proceed-without` resolution that continues against a document changed
mid-chain. An author who edits the BRIEF's `upstream:` to a private cross-repo
ROADMAP between hops, and acknowledges the drift, gets that value spliced into the
surviving PRD — past the only check that exists, into a committed public
document. `shirabe validate` returns nothing for cross-repo values and always
will, which is the exact gap Phase 0's third check was written to close.

**Change.** Two sentences in the design's Security Considerations: (1) the
record's columns are a closed vocabulary and carry no free-text field — say this
instead of, or alongside, "never section text"; (2) the splice re-runs Phase 0's
third check on any cross-repo entry it copies forward, omitting the entry and
telling the author when this repo is Public and the parent is private.

### N2. What the record checker proves, and what it appears to prove

The checker is deletion-driven, gated on a fold signature (a chain-document
deletion plus an `absorbed:` declaration added in the same diff naming that path),
lives in the reusable `validate-docs.yml`, and other repositories pin it.

What it actually proves, for a PR whose diff carries a fold signature: a row exists
in `docs/folds.md` for that deletion, and — because `fetch-depth: 0` lets it run
`git rev-parse BASE:<path>` — the row's blob hash matches the bytes actually
deleted. That is a real guarantee and worth having.

What it does not prove, and a reader of the design would assume it does:

- **That the verdict, survivor and carry results are true.** Those exist only in
  the `wip/` state file Phase 4 deletes. A forged row with a truthful hash (the
  hash is recoverable from BASE by anyone) passes.
- **That the contribution actually landed.** Static validation buys presence of a
  section; nothing ties the row's carry column to it.
- **That an undeclared fold was recorded.** The trigger is the fold signature, and
  the signature is what the folding party controls. Delete the document and omit
  the `absorbed:` declaration — or land the declaration in a different commit — and
  the checker never fires. The design records this coupling under "A coupling the
  plan inherits" and frames it as housekeeping tolerance; it is also the evasion
  path, and it should be named as one.
- **Anything at all outside a PR.** `validate-docs.yml:35` skips when
  `github.base_ref` is empty. A fold landing by direct push to the default branch
  is unchecked, and the design's own Consequences call the branch-time checker
  "load-bearing rather than optional" because the absorbed bytes are unreachable
  from `main` after squash. So the one instrument that makes the record honest is
  absent in exactly the landings that bypass review.

**Change.** State the three limits plainly in the design (forgeable non-hash
fields, signature-controlled trigger, PR-context only) rather than describing the
record as an attestation. Then add the one cross-field assertion that is free,
because the signature computation already has both halves: **the row's survivor
column MUST equal the document whose `absorbed:` frontmatter names the absorbed
path in the same diff.** That turns the trigger into a consistency check at no
extra cost.

### N3. The preflight script's two path arguments are the real injection surface, and the design's claim about them is a caller convention

The design says the deletion target's path "is derived from the validated topic
slug rather than from author input". I verified every hop and the claim holds
today:

1. `$ARGUMENTS` validated against `^[a-z0-9-]+$` at Phase 0
   (`phase-0-setup.md:62-84`), with paths explicitly rejected.
2. Resume-recovered slugs re-validated before interpolation
   (`phase-0-setup.md:209-220`).
3. Child invocation arguments are hard-composed from `<topic>`
   (`phase-2-chain-orchestration.md:175-180`) — the table, not the prose.
4. Cross-repo `--upstream` values reach `consumed_upstream:` only, are ROADMAP-only
   by basename enforcement, and are never a fold endpoint.

But the script takes the absorbed path and the survivor path **as arguments**
(Decision 6), and both are interpolated into `git grep` pathspecs as `:!<path>`
exclusions and into `-F` search patterns. `-F` neutralizes regex; it does **not**
neutralize pathspec globbing. An exclusion argument of `docs/*` or `*` would blind
the search across the whole tree and the script would exit 0 — clean — and the
fold would proceed. That is a fail-toward-`absorb` reachable by a wrong argument
rather than a wrong repository state.

Nothing structural prevents it: the script is a general-purpose tested artifact
under `skills/scope/scripts/`, and the contract that its arguments are
slug-composed lives only in `/scope`'s prose. The design's claim is therefore
about the current caller, not about the surface.

**Change.** The script SHALL validate both arguments against
`^docs/(briefs|prds|designs|plans)/(BRIEF|PRD|DESIGN|PLAN)-[a-z0-9-]+\.md$` and
exit with the "did not complete" code (B3) otherwise. That makes "composed from
the validated slug" a property of the surface instead of a property of one caller,
and it closes the glob-widening case in the same line. Pin it as a test fixture.

Two smaller notes on the same surface. The design's prose enumerates the exclusion
set as "`wip/`, the survivor of this fold, and `docs/folds.md`" and omits
`:!*tests/fixtures/*` and `:!*evals/fixtures/*`, which Decision 6 pinned and
`validate-docs.yml:90` already uses. Every entry in that set is a deliberate blind
spot, so the design's enumeration should be complete or should explicitly defer to
the script. And the design should say which entries are pinned constants (`wip/`,
the fixture pair, `docs/folds.md`) and which are runtime arguments (the two paths)
— they have different threat models and the word "pinned" currently covers both.

### N4. Enum re-validation: the two named fields are correct and insufficient

Confirmed current list — four fields, identical in both places
(`phase-2-chain-orchestration.md:542-559`, `phase-3-exit-finalization.md:310-330`):
`boundary:`, `decision_record_sub_shape:`, `triggering_child:`,
`plan_execution_mode:`.

Adding `hop:` and `verdict:` is right, and the design should give the reason
rather than listing them: both now reach a **durable tracked file** as columns of
`docs/folds.md`, which is a stronger obligation than the state-file-to-shell path
the list was written for. Four gaps remain:

- **`stage:`** — the new `preflight | judgment | carry` discriminator replacing
  `absorbable:`. Retiring one enum and introducing another without adding it to
  the list is the same omission `verdict:` already has today.
- **`chain_ran:`** — see B4.
- **`visibility:`** — pre-existing, and the design's list amendment is the natural
  place to fix it. It is an enum (`Public | Private`), it is read back from the
  state file, and it is interpolated into an emitted command:
  `shirabe validate --format json --visibility=<value>`
  (`phase-2-chain-orchestration.md:609`, `phase-0-setup.md:124-126`). A tampered
  value both routes the validator's governance rules and lands in a command line,
  which is precisely the pair of harms the two contracts describe. The design's
  claim that "no untrusted input reaches an emitted command" is not true of the
  state file today.
- **The `absorbed:` basename prefix** — a new discriminator that is not in the
  state file at all. The design says "the absorbed type is derived from the
  basename prefix" and never says what happens when the prefix is not one of
  `BRIEF|PRD|DESIGN|PLAN`. That value selects a contribution heading, is spliced
  into `required_sections_for`'s output, and is serialized into a `docs/folds.md`
  column — and unlike the state file it lives in a tracked, hand-editable,
  default-branch document. It needs the same enum treatment, failing closed
  (unknown prefix → the new error-level check fails; the fold does not proceed).

### N5. The record's row serialization should forbid `|` and newlines

Minor, but this is the audit record of a destructive operation and the file is a
markdown table. Every value is currently drawn from a closed vocabulary or a
slug-composed path, so nothing can break a row today — but that safety is
inherited from N4's validations rather than stated. One sentence: the serializer
rejects (rather than escapes) any value containing `|` or a newline, and such a
value routes to `keep`. Without it, closing the `absorbed:` prefix gap in N4 is
load-bearing for row integrity in a way nobody will notice.

`merge=union` reinforces this: it resolves silently with no conflict marker, so a
semantically odd file merges clean. Combined with N2's missing append-only
assertion, rows are mutable in practice. Recommend the checker also assert that
the `docs/folds.md` hunk in a PR diff is **additions only** — B5's pre-commit
revert ordering is what makes that assertion sound.

### N6. Two duties the design dropped from its sources

Neither is a security hole on its own; both leave the absorb's write set
incompletely described, which is what B1/B2 are about.

- **The survivor's dead prose citations.** Decision 6 measured 22 of 36 survivors
  citing the absorbed path in prose beyond the `upstream:` line, and assigned the
  rewrite "to the absorb procedure next to the `upstream:` splice". Design step 5
  splices `upstream:` and writes the declaration and `## Status` line, and says
  nothing about the prose. Those citations point at a deleted file after the fold;
  the diff-scoped `R6` check only resolves `upstream:`, and the next hop's
  preflight excludes the survivor — so nothing catches them, ever. This is also an
  unenumerated mutation of the survivor's body.
- **Resuming a partial absorb.** The absorb now has a durable, staged write (step
  6) before the deletion (step 7). The design never says what a resume does when it
  finds a chain interrupted between them. The natural implementation reads
  `absorbed:` and `into:` back from `consolidation_judgments:` — state-file-sourced
  paths reaching a `git rm`, which is exactly the surface the enum re-validation
  contract exists to close. State instead that a partial absorb is never resumed:
  the row is un-appended, nothing is deleted, and the hop is re-derived from
  scratch or left at `keep`. Decision 1 already flags the resume ladder's `Re-run`
  path as the only route to a double append and asks for a one-line guard; this is
  the same guard stated as a rule.

---

## Where the design is right

- **Step 6 before step 7.** Making fail-toward-`keep` structural at the record
  rather than procedural is the correct call and is stated correctly.
- **The preflight's ceiling.** A refusal path with no override, incapable of any
  outcome stronger than `keep`, is the right shape for a new mechanism inside a
  destructive procedure — and siting the input restriction at the head of the
  *content* stage too, because that is the stage that can return `absorb`, is the
  right paranoia.
- **The fixed-constant record path.** "Stronger against injection than the
  slug-composed paths already in the set" is accurate.
- **Naming the amendment rather than widening quietly.** The design does the thing
  the pattern asks for — it declares the surface change explicitly. B1 and B2 are
  failures of enumeration, not of candour.
- **Cross-repo absorbed paths rejected rather than resolved.** Correct direction.
  N4's last bullet asks for the same treatment of the prefix that names the type.

---

# Re-review at `61592e7`

**Verdict: 1 blocking, 5 residual.**

## The five original blocking findings are closed

- **B1** — `skills/scope/SKILL.md` is in the Components table, named authoritative,
  with the Phase 3 reference kept in sync. Closed.
- **B2** — The set is enumerated in three groups. Deletions are the three upstream
  types with "The PLAN is never a deletion target of a fold"; mutations are
  `docs/{prds,designs,plans}/` with the terminal-hop reason stated; the append is
  the fixed constant. The Phase-3-does-not-write-the-PLAN reconciliation is
  explicit. Closed, and correctly.
- **B3** — "The preflight script's contract" states the codes are the script's own,
  names the `git grep` inversion, reserves `3`, and writes the routing default as
  any status other than 0 or 2 → `keep`, with a fixture. Closed.
- **B4** — `chain_ran:` entry names join the pre-interpolation list against the four
  child names, failing the firing condition closed, with the rewrite-not-leave
  instruction for the Phase 2 exemption paragraph. Closed.
- **B5** — Re-validation is step 8, commit is step 9, and the rollback table covers
  steps 5-9 including the un-append and the recorded revert. The in-memory
  composition note at step 3 is a genuine improvement over what I asked for: it
  makes the step-4 abort structurally free rather than a rollback. Closed.

## BLOCKING

### B6. `absorbed:` is promoted three times over, is validated nowhere, and one of its failure modes fails toward `absorb`

**Location.** `### Declaration and enforcement`; `### The absorb, in order` step 4;
`### The record checker's trigger`.

This is the direct answer to the category question and the sharpest member of the
class. `absorbed:` starts as a declaration for a reader and this design gives it
three load-bearing jobs:

1. **Validator input.** Its basename prefix selects a contribution heading spliced
   into `required_sections_for`'s output — it decides what the validator requires
   of a document.
2. **Gate input.** Step 4: the carry check itemizes "each contribution the ancestor
   carries — its own and any it inherited, **read from the ancestor's `absorbed:`
   list**". The itemization set is derived from the field.
3. **CI trigger.** The fold signature is "an absorption declaration added in the
   same diff naming that path" — the field decides whether the record checker
   fires at all.

Nothing validates it at any of the three. Two failure modes follow, and the first
is the one that matters:

**Fail-toward-`absorb`.** An `absorbed:` list that is short — truncated, mis-parsed,
or hand-edited — makes the carry check itemize *fewer* contributions and therefore
**pass more easily**. Under-declaration weakens the gate. That is the failure
direction the design's own driver forbids and the one B3 was blocking for, reached
here through a field the design explicitly declares may be "a scalar **or**
sequence" — a parse ambiguity this design introduces, on a hand-editable
frontmatter key of a tracked document that survives Phase 4 and merges to `main`.
It needs no adversary: an author correcting a declaration by hand, or a scalar
where a sequence was meant, produces it.

**Undefined prefix.** "The absorbed type is derived from the basename prefix" has
no stated behaviour when the prefix is not one of the four. That value reaches a
required-section splice and a `docs/folds.md` column.

**Required change.** Validate each `absorbed:` entry against
`^docs/(briefs|prds|designs)/(BRIEF|PRD|DESIGN)-[a-z0-9-]+\.md$` at every read:
in the absorb (unparseable or unknown-prefix → the carry check fails closed to
`keep`, never skips the item) and in the new error-level check (a sixth clause).
State the general rule behind it — a gate reading a list fails closed on a list it
cannot fully parse, because a partially-parsed list silently weakens the gate.

## The category, closed rather than patched — answer to N4

You asked for the whole class, not the next instance. The class is: *a field that
previously only recorded, and that this work makes decide something.* Six members,
in severity order. `chain_ran:` (taken) is the first.

**1. `absorbed:`** — see B6. The only member with a fail-toward-`absorb` path.

**2. `hop:`, `verdict:`, and the `carry_check:` map.** Promoted by a different
route than `chain_ran:` — not from record to gate, but from *wip-scratch that
Phase 4 deletes* into *columns of a durable file on the default branch*. Same
shape: a field whose consequences used to end with the run now outlives it. Note a
regression: **the previous draft carried the line that `hop:` and `verdict:` join
the enum re-validation list, from Decision 4's Consequences, and `61592e7` does
not.** The only re-validation amendment in the current text is `chain_ran:`;
`hop:`, `verdict:` and `stage:` appear nowhere in that context. Decision 4 is
explicit that the list "today covers four fields and omits `verdict:` despite the
schema declaring it an enum". The separator/newline rejection covers the
mechanical forgery hazard but not the value domains: `verdict:` against
`{absorb, keep}`, `hop:` against the composed type-pair form, and `carry_check:`
outcomes against `{true, false}` with keys drawn from the ancestor's
required-section list plus its contribution headings.

**3. `consolidation_judgments[].absorbed:` and `.into:`.** Latent today and real
the moment anyone specifies cross-session resume of a partial absorb — which the
design still does not, and which is now reachable because steps 5-9 leave the tree
mutated. A recovery that reads those two path fields back out of the state file
turns state-file strings into `git rm` and restore targets, which is the exact
surface the re-validation contract exists to close. The cheap close is a
prohibition rather than a validation: **a partial absorb is never resumed across
sessions** — the row is un-appended, the survivor restored, nothing deleted, the
hop left at `keep` — and **no path is ever read back from
`consolidation_judgments:` for interpolation**. One sentence now; a rollback path
later.

**4. `exit_artifacts:`.** R22 promotes it across a skill boundary: it stops being
a record of what the chain left and becomes the seed `/execute`'s finalization
guard reads. The Components table books the contract statement; the design should
also state the fact that makes it safe, because a reader cannot derive it. R9 Part
2 fails finalization on an empty `exit_artifacts:` on all three exit paths, and a
"fully folded chain" never reaches zero at `/scope` finalization — the terminal
fold absorbs the DESIGN *into* the PLAN, so the PLAN always survives; the
fold-to-nothing case is `/execute`'s later cascade, outside `/scope`. So R22's
contract and R9 Part 2 do not collide. One sentence, and it forecloses the
misreading in which the fully-folded contract is an empty list.

**5. `visibility:`.** Not promoted by this work — pre-existing — but it is the
counterexample to a blanket claim the design makes, and the list is open anyway.
It is an enum (`Public | Private`), read back from the state file, and
interpolated into an emitted command: `shirabe validate --format json
--visibility=<value>` (`phase-2-chain-orchestration.md:609`). It also routes the
validator's governance rules, so a tampered value crosses the visibility surface
and the interpolation surface at once. The design's closing "no untrusted input
reaches an emitted command" is not true of the state file while this field is
outside the list.

**6. `stage:`.** New enum replacing `absorbable:`, deferred to Phase C. Not a gate
— it records where a verdict settled — but retiring one enum and introducing
another without listing it repeats exactly the omission `verdict:` already
represents.

**The rule that closes the category permanently.** Each of the six had to be argued
individually because the list's scope sentence is "before constructing any write
path that interpolates a state-file field". That framing catches path interpolation
and nothing else, which is why a gate use (`chain_ran:`) and a durable-column use
(`hop:`, `verdict:`) each needed their own argument. Rewrite the scope sentence
instead of appending fields:

> Every enum-typed or closed-domain field is re-validated against its domain at
> the read that precedes its use, where a use is: interpolation into an emitted
> command, construction of a write or delete path, a decision that gates a
> destructive operation, or serialization into a durable artifact.

One sentence, subsumes all six, and it is what stops the next field needing a
seventh argument.

## Residual, non-blocking

**R1. `--` does not neutralize a pathspec, and the design now cites it as if it
does.** The claim is that the two script arguments are "composed from the validated
topic slug rather than from author input, and both passed after `--`". The `--`
protects against a leading-dash argument being read as an option. It does **not**
disable pathspec globbing, and the arguments are interpolated into `git grep`
exclusions as `:!<path>`. An exclusion of `docs/*` blinds the search across the
tree; the script exits 0 (clean) and the fold proceeds. `-F` neutralizes regex in
the *pattern*, not globbing in the *pathspec*. The mitigation named is not the
mitigation needed.

The caller is correct today — I re-verified all four hops (Phase 0 slug regex,
resume re-validation, the hard-composed child-invocation table, ROADMAP-only
`--upstream`) — so this stays non-blocking. But the safety is a property of the
caller, not of the surface, and the script now has a merge gate
(`check-scope-scripts.yml`), which makes the fix nearly free: assert both arguments
against `^docs/(briefs|prds|designs|plans)/(BRIEF|PRD|DESIGN|PLAN)-[a-z0-9-]+\.md$`
inside the script, exiting `3` otherwise. Same fixture file, one more case.

**R2. The visibility hole is documented but not closed.** The design now says the
boundary is crossed at the splice, names the exposure correctly, and says the
`--upstream` check "is the precedent for the rule that must apply" — but never
states the rule, and step 5's splice does not run it. As written the design
identifies a vulnerability and books neither a fix nor an accepted-residual
rationale. Either put it in step 5 (on a cross-repo parent, when this repo is
Public and the parent is private, omit the entry and tell the author — Phase 0's
third check verbatim) or state plainly that within a run the value is validated by
transitivity and the residual is the drift `Proceed-without` path. The second is a
defensible answer; silence is not.

**R3. Two free checker assertions still unbooked.** The trigger computation already
has both halves of each: (a) the row's survivor column must equal the document
whose `absorbed:` names the absorbed path in the same diff; (b) the `docs/folds.md`
hunk must be additions-only. B5's pre-commit revert ordering is what makes (b)
sound, so it is now available where it was not before. Neither closes forgery, but
(a) converts the trigger into a consistency check at zero cost and (b) is the only
thing that would make a hand-edited row visible.

**R4. The checker does not run outside a PR.** `validate-docs.yml:35` skips when
`github.base_ref` is empty. The design calls the branch-time checker load-bearing
because the absorbed bytes are unreachable from `main` after squash — so the one
instrument that makes the record honest is absent in exactly the landings that
bypass review. One clause beside the existing "what the checker proves" paragraph.

**R5. The exclusion set enumeration is still partial.** Design prose names `wip/`,
the survivor and `docs/folds.md`; Decision 6 also pinned `:!*tests/fixtures/*` and
`:!*evals/fixtures/*`, which `validate-docs.yml:90` already uses. Every entry is a
deliberate blind spot, so the design should either enumerate completely or defer
explicitly to the script — and distinguish the pinned constants from the two
runtime arguments, which have different threat models and are currently both
covered by the word "pinned".

## Credit where the rewrite improved on what was asked

- **Step 3 composes in memory.** I asked for re-validation to be placed; the design
  additionally made the step-4 abort structurally free rather than a rollback, and
  tied it to R13. Better than the fix requested.
- **The preflight coverage bound.** The paragraph distinguishing live same-run
  coverage from the retroactive 15-of-36 measurement is an honest correction of a
  number that would otherwise have been read as a forecast.
- **The blob hash is recomputed rather than promoted from `child_snapshots:`.**
  The category question answered correctly *before* it was asked — a bookkeeping
  field deliberately not promoted into a durable attestation, with the reason given.
- **Step 5's prose-citation rewrite** picks up the duty Decision 6 assigned and the
  earlier draft dropped, and names why the preflight cannot catch it.

---

# Final verdict at `72361a8`

**No blocking findings. Cleared from a security standpoint.**

B6 is closed with the validation at every read, the fail-closed carry check, and
the sixth clause. R1 is closed and the mitigation claim corrected — the design now
states that `--` does not disable pathspec globbing and asserts both arguments
inside the script. R2 is closed by running the `--upstream` check's third condition
at step 5 rather than naming it as a precedent. The promoted-field category is
closed by the rewritten scope sentence rather than by enumeration, which is the
form that survives the next field.

## On the triplicated `absorbed:` validation

The lead asked whether three validation sites are the mirrored-constant problem one
level down, and whether the design should name one owner. Short answer: keep the
three, name one owner for the *string*, and rank the sites. It is not the same
problem as the contribution table.

**The three sites answer three different questions.** The absorb validates to
decide whether a destructive act proceeds; it is the only site that can stop the
deletion, and it runs at fold time against on-disk frontmatter in an agent. The
error-level check validates document conformance; it fires on documents nobody is
folding, including a document hand-edited long after the fold, and it cannot see
the fold at all. The record checker's fold signature does not validate shape in any
meaningful sense — it pattern-matches a diff to decide whether to demand a row, in
a workflow other repositories pin. None substitutes for another, and collapsing
them would lose coverage rather than duplication.

**The drift consequences are bounded, and one is already backstopped.** The right
test is what a divergence produces. A stricter absorb than validator: some
documents validate but cannot be folded — fails toward `keep`, harmless. A looser
absorb than validator: the fold proceeds on a list the validator rejects, the
survivor is written, and **step 8's post-absorb re-validation catches it and
triggers the revert**. That containment already exists for other reasons and is
the reason the duplication is tolerable; the design should say so in one sentence,
because it is currently an accident of the ordering rather than a stated property.
A drift in the checker's trigger produces a demanded row for a non-fold or a missed
row — both already documented as trigger-only behaviour that does not prove
legitimacy. Contrast the contribution table, where a drift produces a check failure
at fold time *after* the mutations, which the design correctly flags as unfixed.

**Rank the sites, because they are not equal.** The absorb is the gate; the check
is the backstop; the signature is the trigger. Saying that in the design stops a
future maintainer relaxing the absorb's validation to match the validator's
without realizing they are relaxing the only site that can prevent a deletion.

**Name one owner for the string, not one owner for the behaviour.** Declare the
path shape as a named constant beside the contribution table in `formats.rs`, have
the skill prose and the workflow cite it by name rather than re-typing it, and add
a grep-based CI assertion that the literal in each site matches the constant. That
is strictly better than the contribution table's position, which cannot have such a
test because a table of headings is not a single string. Do **not** build a CLI
surface to share the behaviour: Decision 6 already priced that for the stronger
citation-check case and rejected it, because a new subcommand enters
`docs/guides/multi-consumer-cli-contract.md` — a versioned interface with
cross-repo consumers pinning tags — which is a heavy price for a regex.

**Closed at `f44a79b`.** All four points above are in the design: the three sites
ranked as gate / backstop / trigger with the reason stated, drift containment via
step 8 stated as a property rather than left as an accident of ordering, one owner
for the string with a grep-based CI assertion and no CLI surface, and the splice
branch sharing the check's parse. **Phase 5 security review closes with no blocking
findings.** The single unfixed item is the contribution table's mirrored
constants, which the design flags explicitly with its reason and which is house
pattern rather than a regression from this work.

**One concrete detail worth pinning while this is open.** There is a fourth reader
inside the same crate: `required_sections_for`'s contribution branch also reads
`absorbed:`, to derive headings. If the splice runs against an unvalidated entry
the author gets two diagnostics for one cause, and the misleading one — a missing
required section — is the louder. The splice branch and the new check should share
one parse, and an invalid entry should produce only the entry diagnostic.
