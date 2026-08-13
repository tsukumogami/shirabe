# Decision 3 — multi-chain status conflict: detection, reporting, supersession, severity pinning

Research for `/design` on PRD-chain-cardinality (R9, R10, R11, R23, R24, R25). Every claim
is either a line citation into `crates/shirabe-validate` on branch
`docs/charter-scope-parity` or a measurement from a working prototype built outside the
repository at `/home/dgazineu/.claude/jobs/0489d65c/tmp/proto`. The repository was not
modified.

## Question

How should a multi-chain status conflict be detected, reported, superseded, and pinned to
the severity of what it replaces?

## Corrections to the premises

**`PassingState` does derive `PartialEq, Eq`** (`lifecycle.rs:175`). That gives R6's
required-set dedup key for free — no two distinct variants denote the same set — but it is
useless for R9. Conflict is disjointness, not inequality: `{Planned, Current}` and
`{Current}` are unequal and intersect, which is the DESIGN case R11 exists to protect. Any
rule that reads "the chains want different things" as "conflict" fires on every shared
DESIGN.

**The required sets depend on `--mode`.** Both entry points re-target `SinglePrMidPR` to
`SinglePrAtMerge` under ready posture before calling `compute_passing_state` (`:857-862`,
`:1118-1123`). Measured on a BRIEF shared by a single-pr in-flight PLAN and a multi-pr
completing PLAN:

```
--mode=draft   {Accepted} vs {Done}   -> conflict
--mode=ready   {Done}     vs {Done}   -> no conflict; one L01 after R6 dedup
```

A conflict computed from `chain.posture` instead of the effective posture reports a ready-
mode conflict that ready mode does not have. R25's "under the same modes" is per-mode, not
"in both modes".

## The ROADMAP finding, verified and refined

Decision 2 reports that a ROADMAP reached by walking up from a PLAN is a member of that
PLAN's chain *and* roots a one-member chain of its own, so it carries two obligations with
no fan-out involved. **Both halves check out.** `discover_chains` pushes the node before
breaking at `Brief | Roadmap` (`:511-517` then `:539`), so the ROADMAP is a member; and it
is separately a root because the outer loop admits `"Roadmap"` (`:465-469`). The
asymmetric cell is real: `(Roadmap, SinglePrAtMerge) => Status("Active")` (`:668`) against
`(Roadmap, MultiPrWorkCompleting) => Deleted` (`:637`) and `(Roadmap, MultiPrAtMerge) =>
Deleted` (`:645`). Every other role has its two completing rows agree.

Two refinements, both measured.

**The enabling edge is narrower than "the ordinary corpus shape".** The chain walk breaks
*at* a BRIEF, so a BRIEF whose `upstream:` names a ROADMAP — the shape `/scope` actually
produces — never puts that ROADMAP into the PLAN's chain. Only a PRD, DESIGN, or PLAN
whose frontmatter `upstream:` names a ROADMAP does. Scanning all four corpora
(`shirabe` worktree, `tsuku`, `koto`, `niwa`) for `^upstream:.*ROADMAP` returns exactly one
hit, and it is a template line inside a DESIGN's body, not frontmatter. The three tsuku
DESIGNs that mention `ROADMAP-auto-update` do so in prose; their frontmatter upstream is
`docs/prds/PRD-auto-update.md`. So the shape needs no fan-out and no multi-valued
upstream — correct — but it is **not live in any of the four corpora today**, which the
prototype confirms independently by emitting zero conflict findings across all four in both
modes.

**The asymmetry is a bug, and the obvious repair runs backwards.** Measured against the
shipped binary on two fixtures:

```
F8  ROADMAP Active, DESIGN Current, multi-pr PLAN Done   (the normal completion path)
    [L01] ROADMAP at status 'Active' (expected DELETED ... for multi-pr work-completing)

F7  ROADMAP Done, DESIGN Planned, multi-pr PLAN Active   (roadmap retired above live work)
    [L01] ROADMAP at status 'Done' (expected DELETED ... for multi-pr work-completing)
    [L01] ROADMAP at status 'Done' (expected status 'Active' for multi-pr in-flight)
```

F8 is a false positive that exists today: one feature finishing under a live roadmap makes
the validator demand the roadmap be deleted. F7 is a genuine author error, and today it
produces the contradictory pair on one document — the exact defect this PRD is about,
occurring on a ROADMAP, with no fan-out.

The cause is not the odd cell. It is that `compute_passing_state(role, posture)` cannot
tell whether the posture it was handed came from the document's *own* chain or from a
feature chain the document merely sits above. `(Roadmap, MultiPrWorkCompleting) => Deleted`
is right for the first reading (the ROADMAP's own completion — the forcing function that
fires on `ROADMAP-auto-update` in tsuku today) and wrong for the second. The
`SinglePrAtMerge` cell is the one that already encodes the correct member semantics: a
sibling PLAN finishing says nothing about the roadmap. **Normalising the odd cell to match
the other two would spread the false positive rather than remove it.** The repair
generalises the odd cell's semantics to the others, conditioned on position.

**So: table bug, fixed at source — not a conflict to report.** Reporting F8 as a lineage
conflict would tell an author to fix lineage that is correct and documented. The fix is one
branch in the obligation builder: a ROADMAP that is not the root of the chain in question
is required present. Measured with that in place — F8 reports only the PLAN's finding and
the ROADMAP is clean; F7 reports one L08 naming both chains and both requirements,
superseding the contradictory pair; all four corpora stay byte-identical in both modes; all
50 lifecycle tests pass.

## Drivers

1. **R25 is the hard constraint.** Supersession may not reduce what is reported or when —
   both the condition and the severity need a mechanism, not an intention.
2. **R10 scopes supersession narrowly**: status-lifecycle findings from the conflicting
   chains only. L02/L04/L07 survive on the same document.
3. **R11 must not become collateral damage.** The shared DESIGN is satisfiable and stays
   silent.
4. **A conflict finding accuses the author.** Any shape where the tool is at fault must be
   fixed at source before the check can be trusted.
5. **R23 forbids any change to the current corpus's result.**
6. **R8 forces both entry points.** A conflict visible only in whole-tree mode leaves the
   `/execute` cascade gate (`run-cascade.sh:297`, chain-targeted) blind.
7. **No mechanism suppresses a lifecycle finding today.** `--mode=draft` demotes L02/L06/L07
   to notices (`validate.rs:110-115`) and re-targets one posture row. That is all.

## What the code offers

**Registration is opt-in and the default is the strict one.** `posture_class` is
`match code { "L02" | "L06" | "L07" => DraftTolerable, _ => AlwaysEnforced }`
(`validate.rs:110-115`); `is_intrinsic_notice` (`:83-98`) is an explicit allowlist. An
unregistered code resolves to `Error` in both postures — exactly L01's resolution. Measured
end to end: an `L08` with zero registration renders `::error` under both modes, exits 2, and
carries `"severity": "error"` in the JSON envelope.

`is_known_check_code` (`:150-176`) excludes the whole L-family (it gates the per-file
`--check` selector), so nothing to register there. `advisory::remedy_for` has a `_ =>` arm
and is only reached for draft-tolerable findings. The remaining surface is documentation
and tests: the module doc-comment list (`lifecycle.rs:9-36`),
`docs/guides/lifecycle-posture.md:72-84`, and four hardcoded code lists in `validate.rs`
tests, which only need an entry if the code joins the draft-tolerable set.

**The parity gate is not exposed.** `crates/shirabe/tests/parity.rs` and
`.github/workflows/parity-check.yml` both drive per-file `shirabe validate <file>`, which
never reaches the lifecycle traversal. No L-code appears in any golden baseline.

**`Deleted` is not the empty set, and treating it as one is a live trap.**
`PassingState::Deleted`'s `matches` returns `false` for every status (`:211`), so its
admissible set is empty. Defining conflict as "empty intersection" or "pairwise disjoint"
makes it fire when two chains *agree* the document should be gone. Measured on a ROADMAP
that is a member of a completing PLAN's chain and the root of its own completing chain —
both obligations `Deleted`:

```
[L01] ROADMAP at status 'Done' (expected DELETED (absent from tree) for multi-pr work-completing posture)
```

One correct finding (the two messages are byte-identical, so `errors.dedup()` at `:923`
already collapses them). A naive disjointness rule replaces it with a bogus conflict and,
under R10, suppresses it — the exact R25 regression, produced by the guard meant to prevent
it. The requirement domain must be `Option<BTreeSet<&'static str>>` with `None` meaning
*must be absent*: all-`None` is agreement, mixed is conflict, all-`Some` is conflict iff
the intersection is empty.

## Options

### (a) New check code alongside the existing loop, per-chain findings filtered at emission

This splits into two sub-shapes the brief's phrasing runs together, and only one satisfies
R25 structurally.

**(a1) Post-hoc filter.** Emit L01s per chain as today, compute conflicts separately, then
`errors.retain(...)`. Two predicates — "should this L01 fire" and "should it be removed" —
that must agree forever, written in different places over different inputs. They drift
silently. R25 becomes a hope.

**(a2) Single branch at the emission site.** Restructure emission from
chains-outer/members-inner to one pass over a member-keyed obligation map:
`if conflict { emit L08; continue } else { emit one L01 per distinct unsatisfied
PassingState }`. One predicate, one input, mutually exclusive arms. Supersession cannot
diverge from emission because it *is* emission.

Requirements on `PassingState`: an `admissible(&self) -> Option<BTreeSet<&'static str>>`
conversion (one arm per variant) plus a `describe_set()` for the message. No new variant,
no change to `compute_passing_state`'s signature, no change to `matches` or `describe`.

**Measured** (prototype, six synthetic fixtures plus the four real corpora):

- Conflicted BRIEF and PRD: one L08 each, zero L01 (R9 + R10).
- Shared DESIGN at `Current` under an in-flight and a completing chain: no finding (R11).
- Two chains requiring `Deleted` on one ROADMAP: no L08, L01 preserved.
- ROADMAP retired above live work (F7): one L08 replacing two contradictory L01s.
- ROADMAP live above a completing feature (F8): clean, once the root/member fix is in.
- Two chains, same required set, different postures: one L01, not two (R6).
- Chain-targeted on a shared BRIEF, run twice with one PLAN renamed: identical findings
  modulo the renamed path (R7, R8). The shipped binary gives 0 findings and then 3.
- **All four corpora, both modes: byte-identical stdout and exit codes** (R23). This needs
  the posture name kept in the L01 message; dropping it changed three strings in `tsuku`.
  When several chains collapse to one required set, the message names them all
  ("for multi-pr work-completing and single-pr at-merge posture" — needs pluralising).
- `cargo test`: all 50 lifecycle tests pass. Three failures elsewhere are copy artifacts —
  `resolve_doc_visibility` (`visibility.rs:70-95`) infers from path components and the copy
  sits outside `public/`, and `check_upstream_resolves_tracked_file_returns_empty`
  (`checks.rs:3679`) needs a git-tracked file. All three pass in the repository.

### (b) Compute the conflict inside the passing-state evaluation

`compute_passing_state(role, posture)` is a pure function of two enums and cannot see
another chain. Passing it the obligation set makes it the per-document grouping of (a2)
under a different name. The one genuinely distinct version — widen `PassingState` to carry
a set and return the *intersection* — discards which chain wanted what, and R9 requires the
message to name each chain and each required set. You would have to keep the per-chain list
alongside the intersection to render the message, which is the grouping again, plus a
widened enum every call site reads.

The salvageable idea in (b) is real and is what (a2) does: the contradictory pair is never
*constructed*, not constructed-then-filtered.

### (c) A distinct severity or a new class

`Severity` has exactly two variants (`validate.rs:44-48`) driving both the envelope's
per-finding `severity` and the exit-code roll-up through one resolution point. A third level
changes the `shirabe-validate/v1` value domain and every consumer of it. Moving the other
way — making L08 draft-tolerable — fails R25 outright: an error-level L01 becomes a notice
under `--mode=draft`, the run goes exit 2 → exit 0, and the ready-posture finalization guard
(`.github/workflows/lifecycle.yml`) stops firing on corpora it fires on today. The correct
severity is the one the default already gives it.

### (d) Detect but do not supersede

The honest case, stated before it is set aside:

- **R25 is satisfied vacuously.** Nothing is removed, so nothing can be under-reported. The
  whole pinning problem — the hardest part of this decision — disappears, along with any
  risk that a later edit to the conflict rule silently swallows an L01.
- **It is monotone**: every corpus that fails today fails identically plus one finding, so
  R23 exposure is provably zero without measurement.
- **It is the smallest change**: ~25 lines, two call sites, no restructuring, no
  `admissible()`, no R6 interaction.
- **The author gets both layers** — diagnosis and the per-chain data underneath it.
- **Nothing suppressed is false.** Each L01 is a true statement about one chain.

Three things defeat it.

First, **R10 says otherwise in SHALL language**, and an accepted acceptance criterion says
the conflicted BRIEF "does not additionally produce the two per-chain findings it replaces".
Choosing (d) is a PRD amendment and would have to be proposed as one.

Second, **the pair is the harm, not the noise.** Measured by sweeping the shared BRIEF's
status under `--mode=draft`:

```
Accepted  -> [L01] expected 'Done' for multi-pr work-completing
Done      -> [L01] expected 'Accepted' for single-pr mid-PR
Draft     -> both
```

An author who acts on the first message makes the second fire. That loop is the user story
verbatim. The measured F7 ROADMAP case shows the same pair on one document with no fan-out
at all. Under (d) both instructions stay on screen and the explanation is added beside them.

Third — and co-location does not fix this — **the rendering separates them.** Findings sort
by `(file, code, message)` (`:917-922`), so `L01` prints before `L08` on the same document,
and in annotation format each becomes an independent GitHub annotation. The "the
explanation is right there" defence assumes a reader who consumes the list top to bottom;
the Files tab does not give you that reader.

What makes (d) attractive is recoverable inside (a2), and it is what makes supersession
safe: **a disjoint obligation set guarantees at least one superseded finding.** If no status
satisfies all chains, the document's status satisfies at most one, so at least one L01
fired. Supersession is always 1-for-N with N ≥ 1 — never 1-for-0, never 0-for-N. The F7
ROADMAP case is the N = 2 instance; the `{Active}`-versus-absent case is the N = 1 boundary.

### (e) Reuse L01 rather than adding a code

Worth naming: if the conflict *is* an L01 with a merged message, severity is pinned by
identity, there is no registration to get wrong, no doc row, and every consumer that greps
`[L01]` keeps working. Rejected because the L-family exists to name kinds — the module
doc-comment defines L01 as "state-vs-posture mismatch", which a lineage conflict is not —
and because a merged code is unsplittable later.

## Recommendation

**(a2), plus the root/member fix as a required companion.** Concretely:

1. Fix the conflation first. In the obligation builder, a ROADMAP that is not the root of
   the chain being walked is required present (`Status("Active")`); only its own
   ROADMAP-rooted chain can require it absent. This removes the F8 false positive, keeps the
   F7 genuine error, and is measurably byte-identical on all four corpora. Do **not**
   normalise `(Roadmap, SinglePrAtMerge)` to `Deleted` — that is the cell that is already
   right.
2. Add `PassingState::admissible() -> Option<BTreeSet<&'static str>>`, `None` for `Deleted`,
   plus `describe_set()`. Leave `matches`, `describe`, and `compute_passing_state`'s
   signature alone.
3. Build the member-keyed obligation map once from the chains in scope, each entry carrying
   the chain root and the **effective** posture. The root is `chain.members.last()` —
   members are pushed root-first (`:511-517`) then reversed (`:550`), and empty chains are
   skipped (`:545`), so `last()` is total.
4. Satisfiability: all-`None` → satisfiable; mixed → conflict; all-`Some` → conflict iff the
   intersection is empty. Conflict requires at least two obligations.
5. Emit in one function over the map, with the conflict branch and the L01 branch mutually
   exclusive. The `continue` is the supersession — there is no filter.
6. `run_lifecycle_chain_check` changes `.find()` to `.filter().collect()` and calls the same
   function over that subset.
7. Keep the posture name in the L01 message, joining names when several obligations collapse
   to one required set. This is what preserves byte-identical output today.

**Composition with Decision 2.** This is the same structure Decision 2 recommends, reached
independently: a member-keyed obligation map built once, emission as a single function over
a scope set, and finding identity as the map key rather than message text. Three notes on
fitting them together. The map's value must carry the chain **root** as well as the posture
and passing state, because R9's message names chains and a chain is identified by its root;
Decision 2 does not need the root, so this is an additive field. The scope set is the only
difference between the two entry points — all chains, or the chains containing the seed —
which is what makes R8 fall out rather than be asserted. And the conflict finding needs no
dedup: one pass over the map emits at most one L08 per document by construction, so its
identity is just `(code, path)`.

**How R25 is guaranteed rather than hoped**, in decreasing strength:

- *Structural, for the condition*: supersession and emission are the two arms of one `if`
  over one input. There is no second predicate to drift. This is the reason to reject (a1).
- *Structural, for the arithmetic*: disjointness implies at least one superseded finding, so
  the replacement is never 1-for-0.
- *Tested, for the severity*: assert `effective_severity("L08", p) ==
  effective_severity("L01", p)` for both postures — pinned to L01 by reference, not to the
  literal `Error`, so it tracks L01 if L01 ever moves. Comment at `posture_class` recording
  that L08's absence is deliberate.
- *Exhaustive, for both*: the domain is finite and small — 5 roles × 4 reachable postures ×
  4 reachable postures × ~6 statuses × 2 review postures. A table-driven test over the whole
  cross-product can assert that whenever the new rule emits an L08, the old rule emitted at
  least one error-level finding on that document at the same severity. No fixtures, no
  filesystem, because `compute_passing_state` and `effective_severity` are pure. That is the
  closest thing to a proof available here.

**Message shape.** Role, status, count, then one clause per chain — `<root> requires 'a' or
'b'` / `requires absent from the tree` — sorted by root path and deduped. Naming all of the
document's chains rather than only the conflicting subset is a superset of R9 and simpler to
specify; say so explicitly.

## Rejected alternatives

- **(a1) post-hoc filtering** — two predicates that must agree forever. Rejected on the
  mechanism, not the output, which is identical today.
- **(b) intersection inside the passing-state evaluation** — collapses into (a2), or in its
  distinct form discards the per-chain detail R9 needs while widening an enum every call
  site reads.
- **(c) distinct severity or class** — no third severity exists; adding one changes the
  envelope's value domain. Demoting to draft-tolerable violates R25 and silences the
  ready-posture finalization guard.
- **(d) detect without superseding** — genuinely safer on R25 and genuinely smaller; revisit
  if the supersession branch proves hard to get right. Rejected because it keeps the
  contradictory pair that is the defect, because sort order and annotation rendering separate
  the explanation from the contradiction, and because it contradicts R10 and an accepted AC.
- **(e) reuse L01** — cheapest severity pin available, but conflates two kinds of defect
  under one code forever.
- **Reporting the ROADMAP asymmetry as a conflict** — it is the tool's error, not the
  author's, and firing on the normal completion path would make the check untrustworthy on
  first contact.

## Open risks

1. **The root/member fix is a semantic change the PRD does not name.** It is required for
   the conflict check to be honest, it changes nothing on the measured corpora, and it needs
   its own acceptance criterion. If the design would rather not carry it, the alternative is
   a narrow suppression inside the conflict rule — which leaves the false L01 of F8 firing
   and is strictly worse.
2. **`MultiPrAtMerge` is dead but its rows are live in the table.** Nothing constructs it
   (`:574-608`), so its rows at `:641-645` never execute. Harmless to the obligation logic,
   but an exhaustive test over `Posture` must skip it or the design must delete it —
   deleting is out of scope under R23, skipping needs a comment.
3. **A chain root can also be a member of another chain**, so the message names the document
   itself as one of "the chains" (measured: `docs/roadmaps/ROADMAP-r.md requires absent from
   the tree` on a finding whose file *is* that ROADMAP). Accurate, reads oddly; special-case
   the phrasing or accept it explicitly.
4. **Message length scales with fan-out.** `PRD-auto-update` has nine children; nine live
   PLANs in mixed phases give a nine-clause single-line annotation. Consider capping.
5. **R7 versus naming chains by path.** The message on a BRIEF quotes its PLANs' paths, so
   renaming a PLAN changes a finding's text on a different document. The AC's "differing only
   where a finding names the renamed path itself" covers it, and R6 defines finding identity
   as (code, path, required set) rather than rendered bytes — the design should say R7 is
   checked at that identity level, or a byte-comparing rename test will fail on a correct
   implementation.
6. **The conflict set is mode-dependent for BRIEF/PRD and mode-invariant for ROADMAP.** Under
   ready posture only `MultiPrInFlight` paired with another posture conflicts on a BRIEF,
   because the re-target collapses the other three; the ROADMAP cases conflict in both modes.
   A test asserting "the conflict appears in both modes" encodes a false invariant.
7. **`skills/execute/SKILL.md:530` and `docs/guides/execute-friction.md:111` document exit 2
   as "`L01`…".** A conflicted chain now exits 2 on L08. The ellipsis arguably covers it.
8. **Decisions 2 and 3 share the obligation map and the `.find()` → `.filter()` change.** If
   planned as separate issues, whichever lands first owns the structure and the other depends
   on it.

## Sources

- `crates/shirabe-validate/src/lifecycle.rs` — `:9-53`, `:82-114`, `:157-172`, `:175-218`,
  `:460-561` (`:511-517` member push, `:539` walk break, `:542` `.first()`, `:545`, `:550`),
  `:574-608`, `:620-670` (`:637`, `:645`, `:668` the ROADMAP rows), `:686-768`, `:784-808`,
  `:831-925` (`:857-862`, `:917-923`), `:1020-1166` (`:1113-1123`).
- `crates/shirabe-validate/src/validate.rs:44-67`, `:83-98`, `:110-135`, `:150-176`.
- `crates/shirabe-validate/src/advisory.rs:104-113`; `visibility.rs:70-95`;
  `checks.rs:3679`.
- `crates/shirabe/src/main.rs:1008-1078`, `:527`.
- `crates/shirabe/tests/parity.rs`; `.github/workflows/parity-check.yml`;
  `.github/workflows/lifecycle.yml:105-140`.
- Prototype, fixtures, and scans:
  `/home/dgazineu/.claude/jobs/0489d65c/tmp/{proto,fx,run*.sh,corpus.sh,corpuscan.sh,upscan.sh}`.
- Prior research: `wip/research/prd_chain-cardinality_phase2_posture-model.md`.
