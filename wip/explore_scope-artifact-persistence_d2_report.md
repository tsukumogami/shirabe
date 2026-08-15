<!-- decision:start id="fold-verdict-backstop" status="assumed" -->
### Decision: Whether the fold verdict gets a structural backstop

**Context**

Under the contribution model, `/scope`'s consolidation judgment stops being a
schema comparison and collapses into one content question per hop: does this
upstream hold anything beyond its contribution that compression would lose? A
home can always be written, so Stage 1's structural test very nearly dissolves
and the verdict rests on an agent reading two real bodies. Static validation can
assert that a contribution section is present; it can never assert that the
section is faithful. That gap is what raised the question of a backstop.

The question was framed around an asymmetry: folds into a durable survivor look
bounded, while a fold into the PLAN looked irreversible, because
`run-cascade.sh:860` deletes the PLAN at execution. **Research falsified the
framing on both halves.** Nothing here is reversible — an absorbed BRIEF's
original bytes are as unrecoverable from a clone as a folded-away DESIGN's,
because both are created and `git rm`-ed on one branch that squash-merges and is
deleted; only one chain-document deletion exists in all of `main`'s history, and
it is a stray-file cleanup. And nothing is wholly lost either: `refs/pull/<N>/head`
survives branch deletion, and a `git clone --mirror` captures all 141 of them, so
a deleted 288-line PLAN is recoverable byte-exact offline. (The research first
reported the mirror capturing zero; that was a `for-each-ref 'refs/pull/*'` glob
artifact — `*` does not cross `/` — which I re-ran and corrected mid-decision.)

What actually differs between hops is where the *distillate* lands: a fold into a
durable survivor converts an artifact into a section of another artifact, while a
fold into the PLAN converts an artifact into nothing on `main`. So the real
question is not whether the verdict can be trusted but whether the operation
leaves a trace.

Three constraints shaped the answer. Nothing may be judged before the artifact it
is about exists. Only one mechanism may reduce the artifact set — though every
statement of that rule is scoped by a removal verb ("the single mechanism that
**removes** a document"), so a thing that can only force `keep` sits outside it,
and the design already tolerates four such things and calls it a virtue. And a
backstop that always fires reinstates the floor #280 exists to remove, while one
that never fires is theatre.

**Assumptions**

- **The author's "some with none" enumerates the four typed chain artifacts, not
  the filesystem.** Two of three statements of the direction name BRIEF, PRD,
  DESIGN and PLAN and then quantify over that set. Three validators ruled this way
  independently and none argued the broad reading. The dispositive support is that
  `/scope` **already ships an exit whose only durable output is a decision record
  and no chain artifact** — `phase-4-cleanup.md:49-56` gives `exit: re-evaluation`
  a `docs/decisions/DECISION-*.md` terminal artifact, with the writer at
  `phase-3-exit-finalization.md:79-84`. On the zero-bytes reading the author's own
  shipped exit would already violate his stated target. *If wrong* — if the author
  meant zero durable files from `/scope` on the fold path — the durable record
  below must be dropped rather than tuned, and the answer reduces to the carry
  check alone.
- **`refs/pull` retention is best-effort with no documented guarantee**, and a
  fork gets its own PR namespace. *If wrong in the generous direction*, the
  recovery story strengthens; it still cannot be the primary answer because
  nobody runs a mirror.
- **Nine chain-document deletions with no recovery ever attempted is weaker
  evidence than it first appears.** Classified under cross-examination: five are
  gentle retirements whose upstream survived, one is a stray-file cleanup, one is
  a manual fold, and **two are genuinely the hard shape** — the ROADMAPs deleted
  in `d432f13`, 705 lines, with no surviving upstream. Separately, nothing in the
  repo documents `refs/pull/<N>/head` as a recovery surface (every committed
  mention is `refs/pull/<N>/merge` as a CI env-var format), so "no recovery
  attempted" measures the absence of a documented route, not the absence of need.
  *If wrong* — if a route existed and nobody used it — this would be stronger
  evidence for adding nothing at all.
- **The worth judgment ships ungraded and ungradeable.** A fixture eval can grade
  whether content was lost, because the fixture retains both bodies. It cannot
  grade whether reasoning deserved to persist — no fixture holds that ground
  truth, and after the fold the comparison object is gone.

**Chosen: No gate on the verdict; a structural backstop on the operation**

The fold verdict is the judging agent's call, at every hop including the terminal
one. No independent reviewer, no human confirmation, in any mode. What gets a
structural backstop is the *operation*, in two parts.

**1. The carry check, hardened — this is the backstop that already exists.**
Stage 3 is reordered so the contribution section is authored first and the carry
table is built against authored text, making the verdict the mechanical
consequence of the table rather than a prediction the table is later fitted to.
The check becomes per-contribution and runs at every hop including the terminal
one; any contribution that does not carry aborts to `keep`. Step 4's post-absorb
re-validation widens from the survivor alone to the survivor plus every referrer
of the absorbed artifact.

That last repair is urgent independently of this decision. `validate-docs.yml:83-97`
computes its file set with `git diff`, and a document stranded by an absorb is not
a changed file — its bytes are untouched, only the file it points at disappeared.
So R6 can never fire on it, in CI or in the pre-commit hook. Fold time is the only
catchable point in the system, and sixteen documents already point at two
nonexistent paths. `lifecycle::build_referrer_map` is the guard this needs; it is
wired to `finalize-chain` and simply unreachable from the absorb path.

**2. A bounded, durable record of the operation.** Each completed fold leaves a
short entry on `main` recording what folded into what, on what verdict, with the
finding and the per-contribution carry table, plus a content-addressed (blob SHA)
pointer to the pre-fold original. It persists no contributions — it records that
a judgment happened and about what, not what the judgment concluded about the
subject matter.

This is a check on the operation, not on the prose: presence at a canonical path
is exactly what static validation can assert, and it fails in the established
direction — no record, no fold.

The surface is left to the DESIGN, with the trade-offs documented. The leading
candidate is a single shared append-only index — one `docs/deletions.md` for the
repo, created on first append, one row per deletion — because it is the only
shape that is not a per-run artifact and so cannot read as a floor. Note there
are **three deletion sites, not one**: the BRIEF-to-PRD fold has a durable
survivor and can record `absorbed: [{path, blob, pr}]` in the surviving PRD's
frontmatter (schema-compatible today — neither `frontmatter.rs` nor `formats.rs`
rejects unknown fields), while `/execute`'s cascade deletion and the terminal
fold have no survivor and need the shared file. The rejected surfaces: a new
`docs/decisions/` shape costs an amendment to the closed write-target set (the
enumerated entry is constrained to `{prd|design}` x `{re-evaluation|rejection}`,
and Phase 2 has a deletion target and no creation target); the absorb commit's
message verifiably does not reach `main`; the Phase 3 PR-body copy is already
specified at `phase-3:64-76` and never implemented, is cheaper than a new file,
but must survive `/execute`'s full `--body-file` replacement.

The row is written mechanically — `git hash-object` and a `printf` — which
matters, because it is the one part of this design that cannot fail by
misjudgement. An agent-authored record would insert another unverifiable content
judgment at the moment of maximum consequence.

**Rationale**

The verdict half was settled by the author, not by the bakeoff. The convergence
record says: *"Agents are trusted to make the terminal-fold call. The
determination of whether the accumulated sections are worth persisting is an
agent judgment against the real bodies, consistent with #260's principle that
nothing is decided before the artifact it is about exists."* The validator
arguing for human confirmation found that line, judged its own position
self-refuting against it — it cannot claim the author owns the worth decision
while overriding the author's decision about who owns it — and withdrew
unconditionally. The validator arguing for a reviewer agent withdrew too. A
5-of-5 convergence in which two advocates abandon their own alternatives is the
strongest signal this process produced.

The reviewer alternative also failed on a structural bar rather than on cost.
Under `team_primitive: single-team-per-leader-no-nested` the parent "owns no team
at its own layer," `skills/scope/` contains zero sub-agent spawn sites across all
seven files, and the dispatch binding table has no `/scope` row. A reviewer
spawned in Phase 2 asks for a capability the v1 contract states the parent does
not have; degraded, it collapses to the same process wearing a different rubric,
which is precisely what Decision 5 deferred over. And its best argument — that
the reviewer judges an artifact while the judge judged a prediction — is fully
discharged by the Stage 3 reorder, at zero agents. Its own advocate concluded
that a degraded reviewer after the reorder "is pure ceremony."

Human confirmation failed on its own sub-variants. Under `--auto` the
recommendation auto-applies, so the gate is absent in exactly the mode #280's
complaint originates from; forbidding the fold under `--auto` reinstates the floor
by flag; and a gate that survives `--auto` hangs in dispatched contexts with no
answerer. The reframe that `--auto` is authorization granted in advance rather
than a hole is real but thin — the repo's own precedent, `/prd`'s Reject,
insisted on confirming the *particular* act by surfacing the commit subject that
would land, not the class.

The record half is where the constraints bite hardest, and the resolution runs
along a line drawn by the author's own text. A record that *receives the
contributions* contradicts the verdict that produced it: the fold means these
contributions do not warrant a separate artifact, and a `DECISION-` file
receiving them is a separate artifact persisting them. A record *of the
operation* persists no contributions and so asserts nothing the fold denies. It
is also the thing the author asked for: record-survival is in scope
(`scope.md:76-77`), and Research Lead 3 names the failure mode as the run's
provenance "quietly disappear[ing]" — not a neutral question. `phase-3:74-76`
already states the harm in the repo's own words: *"a reviewer cannot tell an
artifact that was absorbed from one that was never produced. The two look
identical on disk and mean opposite things."*

There is a second, structural reason the record must not receive the
contributions, and it is the sharpest argument produced in the whole bakeoff: a
destination that preserves the distillate **must assert, every time it fires,
that the verdict was partly wrong**. The fold's own meaning is that this work did
not merit a durable artifact; a mechanism that then durably preserves what the
fold kept contradicts the judgment it is backing up. Answering that on line
counts addresses degree when the objection is structural. The residue — that a
judgment happened, about what, with what carried — is the only thing whose
preservation asserts nothing the fold denies.

That also answers constraint 3. A ledger entry is not a floor: the floor is three
typed lifecycle documents with status machines, `upstream:` edges, validator
formats and a place in the finalization walk, running 227 to 460 lines each. An
entry recording that a judgment occurred is not an artifact of the chain and is
not what the 366-DESIGN corpus is a complaint about — and if the record is a
single shared append-only index rather than a file per run, it is not a per-run
artifact at all.

The alternative — accepting that `main` holds no trace a fold ever happened —
was argued well, on the ground that demand for post-merge archaeology measures
zero across nine deletions. Cross-examination weakened that inference twice over:
two of the nine are the hard shape rather than gentle retirements, and no
documented recovery route ever existed for anyone to use. The same commit that
supplies the two hard cases supplies the author's own remedy for them: `d432f13`
relocated both ROADMAPs to the private vision repo "as historical reference" and
then removed the now-dangling `upstream:` frontmatter from the five PRDs that
pointed at them. Preserve the content, delete the linkage. With `6e1a22d` beside
it — 730 lines into code comments, no pointer left behind — that is twice, and it
is precisely the failure a content-addressed pointer on `main` prevents.

**Alternatives Considered**

- **No backstop at all beyond the hardened carry check.** The strongest rival, and
  most of it is adopted. Rejected only in its final form, where it accepts that a
  completed fold leaves nothing on `main` distinguishing an absorbed artifact from
  one never produced. Its own escape route — putting the record in the absorb
  commit's message — was verified not to work: `origin/main` carries zero commits
  with the cascade's fixed message despite six PLAN deletions, because every
  commit on `main` is a squash commit.
- **A veto-only independent reviewer at the terminal fold, or at every fold.**
  Rejected because `/scope` owns no team at its own layer and has never spawned a
  sub-agent in any phase, so its independence is unavailable rather than merely
  expensive — and the Stage 3 reorder supplies its one real contribution for free.
  Withdrawn by its own advocate.
- **Human confirmation for the terminal fold.** Rejected because the author has
  already ruled that the agent makes this call, and because all three `--auto`
  sub-variants fail differently — absent where the risk is, a floor by flag, or a
  hung run. Withdrawn by its own advocate.
- **Recoverability instead of a gate.** Not rejected so much as relabelled by its
  own advocate as "a hedging argument, not a harm argument" and split: the
  provenance pointer is adopted into the record above; the retained-mirror half is
  declined because it is an ongoing operational commitment nobody has made. It was
  never a backstop — it fires never and changes no verdict. Note the adopted half
  is the only proposal here **not contingent on the terminal fold shipping**:
  `/execute` deletes a PLAN on every run, nine already, zero folds.
- **A durable destination that receives the distillate.** Rejected on the author's
  framing rather than on cost: the fold's meaning is that these contributions do
  not warrant a separate artifact. Its advocate conceded it could bound but not
  dissolve that sentence, withdrew its claim to be restoring an existing
  invariant, and shrank its proposal under pressure — which is the direction of
  travel toward the bounded record adopted here.

**Consequences**

The verdict is unfalsifiable in production and will stay that way. The fixture
eval that should be built before this ships — tier 1 plus `fixture_dir`, no
harness change, the shape `/explore` evals 9 and 10 already use — grades whether
content was lost, never whether it deserved to persist. After a fold the
comparison object is gone, so the worth half cannot be graded then either. This
belongs in the DESIGN's Consequences so nobody mistakes a green eval for a check
on the whole judgment.

Content is lost permanently, by design, and the record does not undo that. What
the record buys is that a reader of `main` can tell a fold happened, see which
contributions were claimed to have carried, and resolve the pointer to the
original where the escrow or a mirror survives.

Three things become obligations rather than options. The step-4 referrer
re-validation must ship regardless of anything else here, because nothing else in
the system can catch the failure it fixes. `lifecycle::build_referrer_map` needs
a path reachable from the absorb. And eval 18 must be rewritten under every
alternative, because its `expected_output` asserts "no hop above BRIEF-to-PRD is
absorbable" — the sentence #280 exists to falsify — and grounds its refusal to add
a guard on a condition that #280 flips.

Whichever surface the record lands on costs an amendment to an enumerated
security surface, and that amendment should be explicit rather than a quiet
widening: Phase 2's write-target set today names one deletion target and no
creation target.

Two things get harder. Every fold now has a write that can fail, so the absorb
gains a failure mode it did not have — it fails toward `keep`, consistent with
the existing direction, but it is one more path. And the decision leaves the
record's surface open, which is deliberate but means the DESIGN must settle a
question this decision only bounded.
<!-- decision:end -->
