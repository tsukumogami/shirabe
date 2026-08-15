# Testability review — PRD-scope-artifact-persistence

## Round 2 verdict

FAIL

One blocking finding, and it is narrow: R16 and R28 are not jointly
satisfiable against the corpus on disk today, and the regression criterion is
the instrument that will decide it in the failing direction. Everything else
below is finish-work — specific, cheap, and none of it structural.

This is much closer to pass than round 1. The [mech]/[judg] tagging with a
named instrument per criterion, and Known Limitation 2 admitting the central
behaviour is graded rather than gated, changed what the document is rather
than papering over what it lacked. Round 1's F1, F2, F3, F4, F6, F7, F8, F10,
F11, F12 and the R18 revert gap are all properly closed. Verified below where
I could check the claims empirically.

---

## Blocking

### B1 — R16 fails 77 documents that are on disk today, and three criteria disagree about it

R16: "`shirabe validate` SHALL fail when an `R<n>` requirement citation in a
document resolves neither within that document nor within its surviving
upstream."

R28: "Documents already on disk SHALL validate unchanged."

Regression criterion: "A corpus-wide test walks every document under `docs/`,
runs `shirabe validate`, and asserts exit 0 with no new check code emitted."

Plus: "`git diff --exit-code docs/` is clean in the same job, proving no
existing document was edited to make the corpus pass."

These cannot all hold. Measured against this worktree:

- **77 format-prefixed documents** — the ones `shirabe validate` actually
  opens — cite an `R<n>` they do not themselves define. Heaviest are
  `DESIGN-shirabe-pattern-v1-ergonomics.md` (28), `DESIGN-shirabe-scope-skill.md`
  (22), `PRD-shirabe-scope-skill.md` (22), `PRD-roadmap-plan-standardization.md`
  (22).
- Many resolve legitimately upstream — a DESIGN citing its PRD's R7 is the
  normal chain pattern and R16 permits it. But not all do, and two classes
  provably do not:
  - **A PRD citing R-numbers at all.** A PRD's upstream is a BRIEF, and
    BRIEFs carry no requirement numbers. `PRD-shirabe-scope-skill.md` carries
    22 such citations with nowhere upstream for them to resolve.
  - **Cross-chain citation by path.**
    `docs/briefs/BRIEF-lifecycle-passing-state-validation.md:177` reads
    "`docs/prds/PRD-roadmap-plan-standardization.md` (R17 and R18)" — a
    *different chain's* PRD, named explicitly, from a BRIEF whose own upstream
    is a ROADMAP. Neither local nor upstream. Status `Done`, untouched by this
    work. R16 as written fails it.

The Out of Scope section already states the reading that would resolve this —
"R16 is narrower and distinct: it fires on requirement numbers orphaned by
this work's own absorbs" — but **R16's own text carries no such scoping**, and
a requirement is what the requirement says. A DESIGN reading R16 will
implement the broad check, the corpus walk will go red on documents nobody
touched, and the only way to green is to edit them, which the `git diff
--exit-code` criterion exists to forbid.

Worth noting the two `docs/guides/` files that also cite undefined R-numbers
(`doc-validation.md` cites R6-R9, `multi-consumer-cli-contract.md` cites
R6/R7/R9) are *not* exposure: neither has a format-prefixed basename, so the
validator silently skips them. The corpus walk is safe there.

**To fix:** scope R16 in R16. Something like "…SHALL fail when an `R<n>`
citation whose target document this run absorbed resolves neither within the
surviving document nor within its spliced upstream" — tying the check to the
absorb event rather than to citation resolution generally. Then add the
fixture the criterion already implies (a DESIGN citing `R7` into a PRD this
run absorbed) and R28's guarantee holds by construction.

---

## Finish-work

### N1 — AC-J2 is tagged [mech] but its operative clause is [judg]

"The two fixtures … share section set, Decision count, `status`, `upstream`
and topic slug — **differing only in whether a recorded alternative remains
live**."

Everything before the dash a machine decides. The clause after it is the exact
property the paired eval exists to test — deciding an alternative is "live"
is a reading of the document. A criterion cannot be mechanically verified by
asserting the judgment it is a control for.

Also: "hold their line count within a stated band of each other" does not
state the band, and does not say where the band is stated. A verifier cannot
decide it.

**To fix:** state the band numerically (±10% reads right for these fixtures),
keep the structural equalities as [mech], and move "differing only in whether
a recorded alternative remains live" into the fixture description under
AC-J1 where it belongs as a construction instruction rather than a check.

### N2 — The write-target criterion is tagged [mech] and then says "Verified by inspection"

"**[mech]** Every path the absorb procedure writes or deletes appears in
`/scope`'s enumerated write-target set. Verified by inspection."

The preamble defines [mech] as "a criterion a machine decides." Inspection is
not a machine. The criterion contradicts the taxonomy in its own last
sentence, and the taxonomy is this draft's central structural claim — an
internal violation costs more here than the criterion is worth.

The verification is real: the write-target set is prose in
`skills/scope/SKILL.md:714-726` referencing
`references/parent-skill-security.md`, with no machine-readable enumeration to
diff against. So inspection is genuinely the method.

**To fix:** either add a third tag (**[insp]**) and use it here, or retag
[judg] and let the preamble note that a small number of [judg] criteria are
settled by inspection rather than by an eval.

### N3 — Five requirements have no criterion, one of them inside R29's own enumeration

- **R3** (each type declares exactly one contribution) — the foundation R4-R9
  stand on, and "exactly one, per type, named in the format reference" is a
  one-line mechanical check. Missing.
- **R5** (fixed heading derived from the absorbed type) — added in response to
  round 1's F5, and the thing that makes R8's check implementable at all, but
  no criterion asserts the headings are fixed and named. The section criteria
  presuppose it silently.
- **R13** (carry check evaluated against text that exists, never a prediction)
  — checkable by inspecting the procedure's step order: does the authoring
  step precede the carry-table step. Cheap, and it is the requirement that
  buys back the independent reviewer the Decisions section declined.
- **R14's itemization half** — "SHALL additionally itemize each contribution
  the ancestor carries — its own and any it inherited." The abort behaviour has
  a criterion; the transitive itemization does not. This is the case where a
  survivor absorbs a document already carrying two contributions and must
  confirm three things carry, and it is the path most likely to be
  under-implemented.
- **R29's first decision point** — R29 enumerates five ("the replaced first
  stage, the carry check, the citation check, post-absorb re-validation, and
  record production"). Four have criteria. **The replaced first stage does
  not.** AC-J1's `keep` result is stage 2 working correctly, not stage 1
  failing safe. An enumeration whose members are unequally covered invites the
  reader to assume they all are.

### N4 — R28's cross-repo clause has no criterion

R28 requires the added checks to emit nothing "including against the frozen
cross-repo parity baseline, so downstream callers pinning a shirabe tag do not
break." The regression criteria cover `parity.rs`'s in-repo captured baselines
via `cargo test --workspace` — but the cross-repo baseline is
`parity-check.yml`, which compares against a Go binary built at SHA `20fb8ed`
and which **shirabe still does not self-call** (no
`uses: ./.github/workflows/parity-check.yml` anywhere in `.github/`). Nothing
in the criteria set exercises it, so the clause R28 added in response to round
1's F9 is asserted and unverified.

**To fix:** either add a criterion that shirabe self-calls `parity-check.yml`
over its own `docs/**/*.md`, or say plainly in Known Limitations that the
cross-repo half is unverified and rests on the in-repo corpus walk as a proxy.

### N5 — "each affected format reference" leaves the target list unnamed

Two criteria say "each affected format reference." Which are they? BRIEF, PRD,
DESIGN and PLAN formats, presumably — but a verifier should not have to
presume. This is the same defect the draft fixed everywhere else by naming
targets: the eval criterion names scenarios 18, 19 and 20; the cascade
criterion names the file, the scenario and the failing line. The rigor is
inconsistent, in the two places it would be cheapest to apply.

### N6 — The preamble's definition of [judg] is wrong for one criterion, in the conservative direction

"[judg] … which in this repository means a `/scope` eval." One [judg]
criterion — "A finalized chain with no surviving durable artifact passes
`/execute`'s finalization guard" — is an `/execute` eval, not a `/scope` one.
That matters in the document's favour: `/execute` **is** the skill with the
isolated-clone tier-2 mechanism (`scripts/run-evals.sh`, `setup_tier2_isolation`),
so that criterion can be graded against an executed run rather than a stated
plan. The preamble currently under-claims it.

### N7 — AC-J3 asserts a filesystem state the named instrument cannot observe

"**[judg]** On the `absorb` verdict, the DESIGN is removed from disk and the
PLAN carries a contribution section for it." A plan-graded eval never executes
the fold, so "removed from disk" is not observable by the instrument grading
it. The preamble does the honest work globally ("plan-graded"), so a careful
reader translates correctly, and I would not block on this. But if one
criterion is going to be reworded to match the instrument exactly, this is the
one: "the plan states the DESIGN is removed and the PLAN carries a
contribution section for it."

---

## Pushback on the R26/R27 decision

You asked. I think you are right on one and wrong on the other.

**R27 should have a criterion.** It is not awkward to assert, and the
instrument already exists and already passes. Scenario 17
`chain-shape-is-constant` in `skills/scope/evals/evals.json` grades exactly
R27's content: "/scope has no altitude selection: an author who says the
framing and requirements are settled is not offered a shorter chain, because
deciding that an unwritten BRIEF is not worth writing is the exact judgment
this skill removed." Its expectations survive this work unchanged — I checked;
it carries no type-level mapping language, which is why it is correctly absent
from the 18/19/20 rewrite list.

The reason to add the criterion is not completeness, it is regression. R27's
real risk is that implementing R1 makes an entry-altitude flag look reasonable
to a later maintainer — "hops are absorbable now, so why not let the author
start at the DESIGN?" — and scenario 17 is the tripwire that catches it.
R24 requires the consolidation family's scenario count not to decrease but
says nothing about scenario 17, so nothing currently protects the tripwire.
One line: "**[judg]** Scenario 17 `chain-shape-is-constant` still passes: an
author declaring the framing settled is not offered a shorter chain."

**R26 I would leave alone, with one cheap extension.** "The only mechanism
that reduces the artifact set" quantifies over mechanisms that do not exist,
and proving that negative over an implementation is not something a criterion
can do. But the assertable core of it rides free on a criterion you already
have: extend the write-target criterion to "…and every deletion in that set is
reached only through the consolidation judgment's abort-or-absorb path." Same
inspection, same pass, no new instrument, and it captures the actual risk —
a second deletion site appearing somewhere in the absorb procedure.

---

## Verified claims

Checks I ran against this worktree rather than taking on the document's word:

- **The 18/19/20 list is complete.** Scanning all 26 scenarios in
  `skills/scope/evals/evals.json` for type-level-mapping language, exactly
  three match: 18 (`durable-artifact-floor-is-structural`), 19
  (`consolidation-absorb-brief-into-prd`), 20
  (`consolidation-keep-at-unmapped-hop`). No fourth scenario references it, so
  naming the three is equivalent to R24's property rather than weaker than it.
  Round 1's F11 is fully closed.
- **"Re-entry protection" is a real, precise term**, not a gesture — it is
  named in `skills/scope/references/state-schema.md:47-57`,
  `phases/phase-1-discovery.md:6`, `phases/phase-2-chain-orchestration.md:525-533`,
  and carries a `chain_skipped:` state field. AC-J4 is constructible as
  written.
- **The cascade criterion's failure claim is accurate.**
  `skills/execute/scripts/run-cascade.sh:439-457`: `design_ref` is set to `""`
  when `CASCADE_DESIGN_PATH` is unset and the awk branch falls through to bare
  `print`, leaving the pre-existing `**Downstream:**` line exactly as it was.
  The criterion will fail against current code, as it says.
- **`docs/guides/` is not corpus-walk exposure.** `doc-validation.md` has no
  frontmatter at all and no format-prefixed basename; the validator skips it.

## What round 2 got right

Recording this because the FAIL is one scoping sentence, not a posture problem.

- The [mech]/[judg] split with a named instrument per criterion is the change
  that matters, and it holds across 30-odd criteria with the two exceptions in
  N1 and N2.
- Known Limitation 2 is the honest admission round 1 was missing: the central
  behaviour is graded, not gated, every [judg] criterion inherits it, and the
  upgrade is named and scoped out rather than left implicit. Pairing it with
  the Out of Scope entry for the isolated-clone mechanism is the right
  treatment.
- The R18 revert criterion enumerates all five parts of the rollback. That was
  round 1's headline gap and it is now the most specific criterion in the
  document.
- The cascade criterion naming the file, the scenario shape, the roadmap line
  and the current failure is the model the rest of the document should follow —
  an implementer can write that test without rediscovering anything.
- R20's content hash evaluated on the branch resolves the contradiction with
  the squash-merge limitation cleanly, and the limitation now explains why.
- The Open Questions entry saying R14 and R15's failure surfaces inherit R20's
  answer closes the dangling-surface problem without pretending to settle it.
