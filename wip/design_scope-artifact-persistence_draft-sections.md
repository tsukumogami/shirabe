# Draft sections for DESIGN-scope-artifact-persistence

Scratch. Assembled into the DESIGN once decisions 1 and 4 land.

## Context and Problem Statement

`/scope`'s consolidation judgment is the only thing in the tactical chain that
reduces the artifact set, and it runs as three stages at each hop after a child
lands. Stage 1 asks whether absorption is possible, Stage 2 whether it is
warranted, Stage 3 performs the move and verifies it.

Stage 1 is a comparison between two type schemas. It looks the hop up in a
hand-maintained table in `phase-2-chain-orchestration.md` and asks whether the
downstream *type's* required sections have a home for every required section of
the upstream *type*. Neither document is opened. Against the section lists in
`formats.rs` the answer is yes for BRIEF-to-PRD and no everywhere else, on every
run, forever — a DESIGN has no home for a PRD's Goals, User Stories,
Requirements, Acceptance Criteria or Out of Scope, and a single-pr PLAN has no
home for any of a DESIGN's reasoning sections.

The consequence is that Stage 2 — the only stage that reads the documents, and
so the only one whose answer can vary — never runs above the first hop. The
verdict is `keep`, decided before either document exists, regardless of whether
the DESIGN in question carries contested architecture or restates what the PLAN
already encodes.

Three things make this worse than a missing capability.

The procedure below the verdict has never completed a run. All PRDs with an
`upstream:` in this repository point at their same-topic BRIEF and no BRIEF has
ever been deleted. The one absorbable hop has been reached twice — on #260's own
dogfood run and on this chain — and refused both times, on the same section.
Every code path under the verdict is therefore untested, and four defects in it
are visible by reading.

The enumerated write-target set is wrong in three ways, and one of them encodes
the defect. It scopes the consolidation judgment's deletion to `docs/briefs/`
alone — the type-level floor, written into the security surface — so an absorb
that removed a PRD or a DESIGN would fail the hard-finalization check for a
reason that has nothing to do with safety. It omits the survivor entirely, even
though the existing `upstream:` re-point already writes it, so the set
understates the parent's reach today, before this change adds to it. And
`SKILL.md` and the Phase 3 reference disagree about whether the PLAN is a Phase
3 write target at all.

A field this work depends on is specified, consumed, and never written.
`chain_ran:` is defined in `state-schema.md` and read in three places by Phase 3
— R9's chain-membership-gated extension gates on it, the PR-body record copies
"every artifact in `chain_ran:`", and `plan_execution_mode:` is required present
if and only if `/plan` appears in it. Phase 2 records `child_snapshots:` and
clears its sentinel, but no instruction anywhere appends to `chain_ran:`. So the
hard-finalization check gates on a field nobody populates. That matters here
because the scoping this work needs — the judgment fires only at a hop where
*this run* produced both documents — is exactly what `chain_ran:` is for, and
because telling an absorbed artifact from one that was never produced is the
thing the fold record exists to make possible.

The chain and its implementation land in one squash merge. `/execute` adopts an
existing `docs/<topic>` scoping PR as its home PR rather than opening a second
one, so the documents a chain produces, the code implementing them, and the
cascade's deletion of the PLAN are all one merge. The PLAN therefore never
reaches the default branch in any commit — not deleted from it later, never on
it. Anything carried in the PLAN is unrecoverable from a clone by construction,
which is why the fold record cannot live there.

And the failure mode the absorb can cause is invisible to CI by construction.
`validate-docs.yml` computes its file set with `git diff`, so a document
stranded by a deletion is not a changed file — its bytes are untouched, only its
target vanished. The reference check can never fire on it. Fold time is the only
point in the system at which that breakage is catchable.

## Decision Drivers

- **Nothing may judge an artifact before that artifact exists.** This killed a
  previously-shipped feature and is the constraint every alternative here is
  measured against first.
- **One reduction mechanism, not two.** The consolidation judgment must remain
  the only thing that removes a document. A mechanism whose sole possible effect
  is to force `keep` does not count as a second one — that distinction is what
  admits the guard and the carry check.
- **Fail toward `keep` at every added decision point.** A wrong `keep` costs a
  document that stayed; a wrong `absorb` costs content with no recovery path
  from a clone, because squash-merge with branch deletion means an absorbed
  document never existed on the default branch.
- **Existing documents are not this change's business.** The added checks must
  be silent on documents that declare no absorption. Where an existing document
  carries a defect this work happens to surface, the finding stands and the
  cleanup is sequenced follow-on work — pre-existing breakage is not a reason to
  narrow a check that is otherwise correct.
- **Prefer the seam that exists.** `required_sections_for` is already the single
  function both the presence and order checks consult; the abort path already
  downgrades a verdict to `keep` and deletes nothing; `shirabe transition`
  already writes a lineage key and splices a `## Status` line. Each of those is a
  pattern to extend rather than a mechanism to invent.
- **The verdict is the agent's; the operation is the machine's.** What an agent
  decides — whether content is worth keeping — gets no gate. What a machine can
  decide — whether a section is present, whether a citation exists, whether a
  record was written — is checked mechanically and fails closed.

## Solution Architecture (partial — decisions 1 and 4 pending)

### The declaration and its enforcement

A survivor records what it absorbed in a new optional frontmatter key,
`absorbed:`, holding a scalar or sequence of repo-relative paths in the same
shape `upstream:` already accepts and read through the same normalizer, so it
inherits trim, blank-drop and placeholder-skip semantics without new parsing.
The absorbed *type* is derived from the basename prefix by the longest-prefix
rule format detection already uses, so nothing declares the type twice.

The list is flat and complete rather than nested — a survivor's list is its
ancestor's list plus the ancestor. Two reasons. The frontmatter parser cannot
hold structure: a mapping value is discarded unrecoverably and a sequence of
mappings survives only as a count with empty text, so anything richer means
changing the parser that sits upstream of every check and both parity
harnesses. And flat is what keeps transitive accumulation linear instead of
combinatorial.

Enforcement extends the seam that exists. `required_sections_for` is the single
function both the presence and order checks consult, and it already branches on
a frontmatter key for one profile. It gains a second branch that splices the
implied contribution headings in immediately after `Status` — well-defined for
every profile, because every format's required-section list begins with
`Status`. A document with no `absorbed:` key gets the base list unchanged, which
is every document on disk today.

One new error-level check owns what the order check structurally cannot say.
The existing order check compares only *relative* order and explicitly permits
unrequired sections in between, so it cannot express "immediately after Status";
it is also notice-level behind a promotion seam waiting on a corpus cleanup, so
it cannot fail. The new check is gated entirely on `absorbed:` being present and
covers four things: the field yields a usable entry at all, every entry names a
known type and is not cross-repo, every entry sits strictly above the carrying
document in the chain, and the implied sections appear contiguously and in chain
order.

The headings come from one table keyed by filename prefix, declared beside the
required-section lists so the format references and the validator have a single
thing to agree with.

### Who writes the contribution section

The parent composes it at fold time, sourced from the **survivor's own body**
rather than from the document about to be deleted, with each child below an
absorbable hop carrying the instruction that puts the material into the survivor
in the first place.

The child cannot author it. The judgment is the last step of the invocation
loop, so a child does not know the verdict when it drafts, and every `keep` run
would leave an orphan section nothing sanctions — the validator has no
per-section optionality primitive to express a conditional one.

Sourcing from the survivor rather than the original is what makes single-site
authoring tolerable: the material was already reviewed when it landed in the
survivor's ordinary sections, and an under-distillation leaves the omitted
content still visible in the survivor rather than gone at the delete.

### The pre-deletion guard

A tested script performs the search and the procedure keeps the routing. It runs
*first* in the absorb, before the contribution is composed and before the
`upstream:` re-point, so a refusal is a clean abort with nothing to undo.

The exclusion set is the load-bearing part and the reason this is a script
rather than prose. The survivor always cites the absorbed artifact through its
own `upstream:`, so a naive search refuses every fold; excluding the survivor as
a whole file is what makes folding possible at all, and excluding only its
`upstream:` line is insufficient because most survivors cite the path more than
once. That is a set of rules with a measurable right answer, which prose cannot
pin and a test can.

Two consequences the design states rather than discovers later. The guard bites
hard on today's corpus — a substantial share of candidate pairs carry a genuine
third-party citation and will fold to `keep`. And `/scope` can block itself,
because its own decision-record templates write durable files citing artifact
paths verbatim into a tracked directory. Both are correct under the
fail-toward-keep rule, and both are designed outcomes rather than accidents.

### Prior artifacts

The two shipped documents this work contradicts get appended dated amendment
sections rather than in-place edits or lifecycle transitions, following the one
existing precedent in this repository's history, which chose append-only for the
audit trail. Original prose stays. The amendment covers three things: a decision
whose reasoning is falsified but whose conclusion survives on other grounds, a
decision whose conclusion is falsified outright and whose *rejected* option is
the one this work adopts, and a requirement that mandates the floor this work
removes.
