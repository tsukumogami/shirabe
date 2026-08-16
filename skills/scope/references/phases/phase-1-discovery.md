# Phase 1 — Discovery and Chain Proposal

Phase 1 turns the topic slug into a planned chain. It runs the
discovery prompt to surface a framing-shift signal, walks the R6
shape-predicates inline to size `/design`'s decision roster,
evaluates the re-entry protection each child carries, captures
initial child-snapshots for any pre-existing durable artifacts,
and emits a chain-proposal output the author confirms (Proceed /
Adjust / Bail).

## What Phase 1 Decides, and What It Does Not

Phase 1 decides **nothing about the size of the artifact set.**
`planned_chain:` is `[brief, prd, design, plan]` on every run.
There is no starting altitude to choose and no child that Phase 1
can decide is not worth invoking.

That is the point of this phase's shape. A judgment about whether
a document would have carried anything can only be made against a
document that exists, and at Phase 1 none of them do — so Phase 1
does not make one, in any form. An earlier revision let Phase 1
choose an entry altitude for the chain; it was removed for exactly
this reason, even though the question it asked the author (which
conversation are you having?) was more answerable than the per-hop
gates it replaced. It still shrank the artifact set before any
artifact existed.

The only thing that stops a child from running is that its durable
artifact is already on disk at a settled status, which is
re-entry protection against overwriting settled work — not a
verdict on the artifact's worth. See "Re-Entry Protection" below.

Reducing the artifact set is Phase 2's job, after the artifacts
exist, and the consolidation judgment there is the only mechanism
that does it. See the Consolidation Judgment section of
`skills/scope/references/phases/phase-2-chain-orchestration.md`.

**An author who wants a shorter conversation reaches for a child
skill directly.** `/design <topic>` and `/plan <topic>` are the
documented ways to enter the tactical chain above `/brief`, and
that choice is theirs and visible in what they typed. It is
supported and stays supported.

What it does not buy is a smaller artifact set. Those are two
rules, not one: a direct invocation shortens the conversation, and
the artifact set is decided afterwards by the consolidation
judgment, per hop, against documents that exist. `/scope` means
"walk the whole chain"; it does not guess that an altitude is not
worth writing down.

## Discovery Prompt Structure

The discovery prompt opens with the framing-shift question (R4):

> Has the framing of this topic shifted since the upstream
> artifacts were last accepted? Specifically, has the problem
> shape, target audience, scope boundary, or core success
> criterion changed in a way that would invalidate an existing
> BRIEF, PRD, or DESIGN you might find on disk?

The prompt continues with topic-related child-doc discovery —
file globs against `docs/briefs/BRIEF-<topic>.md`,
`docs/prds/PRD-<topic>.md`, `docs/designs/DESIGN-<topic>.md`,
`docs/designs/current/DESIGN-<topic>.md`, and
`docs/plans/PLAN-<topic>.md`. Any artifact found is named back
to the author with its frontmatter `status:` value, so the
author's framing-shift answer is informed by the current state
of the chain on disk.

The framing-shift answer feeds R4's override for `/brief`. A
positive answer fires `/brief` even when an Accepted BRIEF exists
at the canonical path — the framing shift overrides the auto-skip.
The full literal prompt text is captured here for eval-grep
checking against the contract.

## Cold-Start Projected-PRD Evaluation

On a cold-start invocation (no `wip/scope_<topic>_state.md` and
no on-disk artifacts at the canonical paths), Phase 1 projects
what the downstream PRD's shape will likely be from the
$ARGUMENTS topic-slug alone. The projection is keyword-driven:
inspect the slug for the projection keywords (`feature`, `fix`,
`migration`, `rollout`, `consolidation`) and emit a one-line
projection naming the most likely PRD-altitude work shape. The
projection feeds the discovery-prompt framing (it does NOT
override the author's answer).

When the cold-start discovery yields empty results — no on-disk
artifacts AND the author answers the framing-shift question with
"no signal yet" — Phase 1 short-circuits the rest of the
discovery walk. The state file records `phase-1: empty-cold-start`
and the chain proceeds with `/brief` at its head as always (the
framing-shift answer is deferred to the BRIEF authoring
conversation).

## Post-`/prd` Re-evaluation Gate

After `/prd` returns Accepted, Phase 1 re-evaluates the R6 shape
predicates against the real PRD body rather than the pre-PRD
projection. If any P1/P2/P3 verdict changed, the gate re-narrates
`/design`'s roster shape to the author and the chain proceeds.

The re-narration is a notice, not a prompt. It adds no option, no
default, and no decision point, and it follows the shape of the
pre-authoring upstream notice below rather than the shape of the
chain proposal. Phase 1 offers exactly one options block, the
chain proposal's `Proceed / Adjust / Bail`, and this gate does not
open a second one. An author who wants to act on what the
re-narration says has the route they always had: re-invoke and
answer the chain proposal differently.

When the post-PRD predicates match the pre-PRD projection, nothing
is narrated and the chain proceeds unchanged.

The gate records nothing in the state file. No verdict here is
one a resume needs, because the predicates are re-derivable from
the PRD on disk, and a field this gate wrote would have no reader
in `skills/scope/references/state-schema.md` to name. An earlier
revision did write a chain-revision flag here. Nothing read it, the
schema never carried it, and the behavior it was named for is the
produce-or-skip reading this file retires.

The re-evaluation changes `/design`'s roster size, never whether
`/design` runs. `planned_chain:` is the whole chain on every run
and is not revised here.

## Re-Entry Protection (R4, R5)

Every child in `planned_chain:` carries the same protection: the
parent MUST NOT silently overwrite a settled durable artifact. A
child whose artifact already exists at a settled status at the
canonical path is skipped and recorded in `chain_skipped:` with
reason `settled-artifact-at-canonical-path-reentry-protection`.

The settled statuses per child:

| Child | Canonical path | Settled at |
|---|---|---|
| `/brief` | `docs/briefs/BRIEF-<topic>.md` | Accepted, Done |
| `/prd` | `docs/prds/PRD-<topic>.md` | Accepted, In Progress, Done |
| `/design` | `docs/designs/DESIGN-<topic>.md`, `docs/designs/current/DESIGN-<topic>.md` | Accepted, Planned, Current |
| `/plan` | `docs/plans/PLAN-<topic>.md` | Active, Done |

The gate shape is Mandatory-with-auto-skip per the Gate
Vocabulary in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`.
`/brief` carries the framing-shift override: an Accepted BRIEF on
disk plus an author answer indicating the topic's framing has
shifted fires `/brief` anyway. The override can only ever fire in
the case the auto-skip would otherwise have closed, so a cold
start fires `/brief` whatever the answer says.

**This is not a worth-producing judgment.** The skip means "a
settled document is already here, and re-running would clobber
it." It does not mean "this artifact would not have been worth
writing." Nothing at Phase 1 is in a position to make the second
claim, because the artifact it would be about does not exist. An
earlier revision of this file recorded the same behaviour under
a rationale that read as reader economy; the reason it gives now
is the reason it always had.

An earlier revision also called `/brief`'s gate EITHER-signal, on
the reading that the artifact state and the framing shift were
independent routes into the child. They are not; the shape name
changed 2026-08-08 and the gate fires on exactly the same runs it
always did.

## R6 Shape-Predicate Walk

R6 walks three predicates inline. Each predicate emits a
`fires` or `does-not-fire` verdict and a one-line reason. The
verdicts have exactly one consumer: `/design`'s decision-roster
shape — which decision-researcher roster fires, against which
inputs.

The predicates do **not** decide whether `/design` is invoked.
`/design` runs on every chain. R7 previously read these verdicts
as a produce-or-skip gate; that reading is retired, and
"shape-dependent" now means what it says in the Gate Vocabulary —
the gate governs *how* a child is invoked, not whether.

At Phase 1 the PRD does not exist yet, so the predicates are
evaluated against the projected PRD shape from the cold-start
projection and the discovery conversation, then re-evaluated
against the real PRD by the post-`/prd` gate above. That
re-evaluation is why a Phase-1 estimate is safe here and would not
be safe as a gate: it resizes a roster, and a wrong estimate is
corrected the moment the PRD lands.

### P1 — Architectural-Alternatives Count

P1 fires when the PRD names at least one architectural
alternative left open for the DESIGN to settle. Inspection
walks the PRD's named requirements; any requirement that names
multiple acceptable implementations (or leaves an
implementation choice explicitly open) increments the count.

Worked examples:

- **Positive (P1 fires):** the PRD requirement reads "The PRD
  SHALL use TLS for transport; cipher suite to be decided." →
  1 architectural alternative left open (cipher suite). P1
  fires.
- **Positive (P1 fires):** "The system SHALL persist user
  preferences across sessions; the storage backend may be
  filesystem, SQLite, or remote KV." → 3 architectural
  alternatives. P1 fires.
- **Positive (P1 fires):** "Authentication may use either
  OAuth2 or a self-hosted token service." → 2 architectural
  alternatives. P1 fires.
- **Negative (P1 does not fire):** "The PRD SHALL log to stderr
  at INFO level." → 0 architectural alternatives left open. P1
  does not fire.
- **Negative (P1 does not fire):** "The CLI SHALL accept `--help`
  and exit 0 with the help text." → 0 architectural alternatives.
  P1 does not fire.

### P2 — New-Component References

P2 fires when the PRD names a new component (a binary, service,
library, or runtime substrate) not already present in the repo.
Inspection cross-references the PRD's component mentions against
the repo's existing directory structure plus the components
documented in upstream STRATEGY or VISION artifacts.

Worked examples:

- **Positive (P2 fires):** PRD mentions "a new ingest worker
  binary at `cmd/ingestd/`" and the repo has no `cmd/ingestd/`
  directory. → New component. P2 fires.
- **Positive (P2 fires):** PRD mentions "a worker pool
  substrate" and the upstream STRATEGY does not name a worker
  pool. → New substrate. P2 fires.
- **Positive (P2 fires):** PRD references "the message broker"
  but no broker is documented anywhere upstream. → New
  component implied. P2 fires.
- **Negative (P2 does not fire):** PRD mentions "the existing
  `internal/validate` package" and the package exists in the
  repo. → Existing component, not new. P2 does not fire.
- **Negative (P2 does not fire):** PRD names "the shirabe CLI"
  and `cmd/shirabe/` is in the repo. → Existing component. P2
  does not fire.

### P3 — Complex Classification

P3 fires when the PRD carries the explicit `complexity:
Complex` (or analogous) frontmatter classification, or when the
PRD's prose explicitly names architectural complexity warranting
a DESIGN doc (e.g., "this requires a DESIGN per the project's
complexity policy").

Worked examples:

- **Positive (P3 fires):** PRD frontmatter has
  `complexity: Complex`. → Explicit classification. P3 fires.
- **Positive (P3 fires):** PRD body contains "the
  architectural shape of this feature warrants a DESIGN doc
  before implementation". → Explicit prose. P3 fires.
- **Positive (P3 fires):** PRD body contains "see the upcoming
  DESIGN-<topic> for the chosen approach". → Forward reference
  presupposing a DESIGN. P3 fires.
- **Negative (P3 does not fire):** PRD frontmatter has
  `complexity: Simple` or omits the field entirely, AND the
  prose makes no architectural-complexity claim. → No
  classification. P3 does not fire.
- **Negative (P3 does not fire):** PRD body says "implementation
  is mechanical given the requirements". → Explicit not-complex
  statement. P3 does not fire.

## R7 Shape-Dependent Evaluation for `/design`

R7 sizes `/design`'s decision roster from the R6 per-predicate
verdicts: which decision-researcher roster fires, with how many
peers, against which inputs. All-negative verdicts still invoke
`/design`; they size it down to the minimum roster, and the
resulting DESIGN records the one live option and why no
alternative was live. That is a shorter document than a
contested design, and it is a better audit trail than the
silence it replaces.

The shape-dependent identifier is the Gate Vocabulary entry
from `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`;
the predicate verdicts feed both the chain-proposal narration
and `/design`'s decision roster cardinality.

## What Phase 1 Does Not Decide About the Artifact Set

Nothing here bounds how many artifacts a run ends with. That is
Phase 2's, decided per hop against two documents that exist.

This section previously stated a durable-artifact floor: that the
smallest set a run could end with was a PRD, a DESIGN and a PLAN,
because no hop above BRIEF-to-PRD was absorbable. It also told
maintainers not to guard the zero-artifact case, on the ground
that its condition could not hold, and redirected an author who
wanted no durable record to invoke `/plan` directly.

All three of those rested on the type-level absorbability test,
which is gone. Every hop is now decidable and a run can absorb its
way down to nothing, so the no-durable-record redirect went with
them: it pointed at an escape hatch from a floor that is no longer
there.

The prohibition on guarding the zero-artifact case survives, with
a corrected reason, and lives beside the judgment in
`phase-2-chain-orchestration.md` — because that is where the
temptation now is. The Phase 1 form of the same temptation, an
entry-altitude shortcut, is forbidden elsewhere and graded by
eval 17.

What survives with the redirect gone is direct invocation itself,
narrowed. It is still how an author reaches the altitude they
want, and what it buys is a shorter conversation rather than a
smaller artifact set, per the head of this file.

## Chain-Proposal Output

After the re-entry protections evaluate, Phase 1 emits a
chain-proposal output naming the planned children, the re-entry
verdict for each, the R6 per-predicate verdicts behind `/design`'s
roster size, and the offered options. The output's options block
contains the literal substrings `Proceed`, `Adjust`, and `Bail`
(case-sensitive, exact spelling per AC9).

Example output skeleton:

> Planned chain (the full tactical chain, as always):
>   /brief — runs (no settled artifact at the canonical path)
>     A new BRIEF will be written for this topic, with no ROADMAP
>     behind it. If one already sequences this feature, re-invoke as
>     `/scope <topic> --upstream <path-to-the-ROADMAP>` and this
>     chain will ground the BRIEF in it and record it on the PLAN. No
>     candidate has been looked for; this is a notice, not a question,
>     and the chain proceeds as proposed.
>   /prd — runs (no settled artifact at the canonical path)
>   /design — runs; roster shape from P1 fires, P2 does-not-fire,
>     P3 fires
>   /plan — runs (ALWAYS)
>
> Any artifact that turns out to be redundant is absorbed after
> it and its successor both exist, not skipped now.
>
> Proceed / Adjust / Bail?

The three branch behaviors:

- **Proceed** — confirm the proposed chain; advance to Phase 2
  and begin invoking children in order.
- **Adjust** — return to Phase 1 discovery with the author's
  adjustment input; re-emit the proposal after re-running the
  gates against the adjusted scope. `/scope`'s Adjust refines the
  topic and the framing; it cannot change chain membership,
  because the planned chain is the same four children on every
  run. A corrected framing-shift answer can still un-skip
  `/brief`, because that answer is a gate input the re-run
  re-evaluates, not an instruction about who is in the chain.
  Whether Adjust reaches membership is a per-parent property
  each parent declares for itself
  (`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`,
  What Adjust reaches); this is `/scope`'s declaration.
- **Bail** — route to R8 bail-handling per the parent's own
  bail-handling rule: force-materialize when a child intermediate
  (`wip/{brief,prd,design,plan}_<topic>_*`) or research scratch
  (`wip/research/{prd,design}_<topic>_*`) exists for the topic;
  clean-cancel otherwise. Nothing under the parent's own
  `wip/scope_<topic>_*` prefix counts toward the first branch, so
  a bail here — where Phase 0 has written the state file and no
  child has run — reaches the clean cancel, and the bail handler
  disposes of that state file.

### The Pre-Authoring Upstream Notice

The `/brief` entry in the skeleton above carries a notice. When
`/brief` runs, `/scope` is about to have a new BRIEF written for a
feature that a ROADMAP somewhere in the corpus may already
sequence. The notice says so, inside the entry list, above the
option line.

The wording is fixed. Emit it verbatim:

> *"A new BRIEF will be written for this topic, with no ROADMAP
> behind it. If one already sequences this feature, re-invoke as
> `/scope <topic> --upstream <path-to-the-ROADMAP>` and this chain
> will ground the BRIEF in it and record it on the PLAN. No candidate
> has been looked for; this is a notice, not a question, and the chain
> proceeds as proposed."*

Substitute the run's validated topic slug for `<topic>`. Leave
`<path-to-the-ROADMAP>` as written — it is a shape, not a
candidate.

#### When It Fires

Both conditions, and nothing else:

1. `/brief` will actually fire — it is in `planned_chain:` and NOT
   in `chain_skipped:`, so the head child will author a NEW
   head-altitude artifact on this run. Membership alone is not the
   test: `planned_chain:` now carries every child on every run, so
   a held-back `/brief` appears there too and the notice would fire
   against an artifact this run will not write.
2. Phase 0's Upstream Validation recorded no `consumed_upstream:` —
   no upstream was supplied.

Both are known at chain-proposal time from what Phase 0 and the
re-entry protections have already established; the notice adds no
filesystem work beyond the globs Phase 1 already runs.

It does NOT fire when the author supplied `--upstream` and Phase 0
recorded it — the author already did the thing the notice describes
— and it does NOT fire when re-entry protection held `/brief` back
because a settled BRIEF sits at the canonical path. In that second
case nothing is about to be written, and telling an author how to
attach an upstream to an artifact this run will not author is
noise.

#### A Notice Is Not a Prompt

The notice states a fact and changes nothing. It adds no option, no
default, and no decision point; the only way to act on it is to
re-invoke with the flag. It follows the shape of the slug-prefix
recommendation in
`skills/scope/references/phases/phase-0-setup.md` — surfaced
informationally, explicitly non-blocking — rather than the shape of
a prompt.

Four properties follow from where it sits, and the wording above
keeps each of them true:

- **It precedes the authoring.** The chain proposal is emitted
  before any child fires, so an author reads it before a BRIEF is
  written rather than after.
- **It scans no directory.** The notice names no candidate. It does
  not need to know whether a ROADMAP exists, which is exactly why
  it is cheap where a discovery scan would not be.
- **It is defined in `--auto` mode.** The proposal is emitted and
  the run auto-proceeds; the notice rides along as output and the
  chain continues. Nothing blocks, so there is no default to get
  wrong.
- **It is not a prompt on every run.** The `Proceed / Adjust /
  Bail?` line below it is unchanged, and the author still answers
  exactly one question here.

## `planned_chain:` Population

Phase 1 writes `planned_chain:` in the state file as the whole
tactical chain, in order. A child held back by re-entry protection
stays in the list and is *also* recorded in `chain_skipped:` with
its reason, because the plan was to run it — the artifact already
on disk is why it did not, not a decision that it was never
planned. `chain_ran:` is what separates the two afterwards. The
three lists together cover the full Phase 1 verdict surface.

This is the same rule `/charter` states for a declined `/roadmap`:
a skip moves a child into `chain_skipped:`, it does not retract the
plan. The one case that is genuinely absent from `planned_chain:`
is a conditional feeder whose gate never opened — `/scope` has no
feeder in v1, so the case does not arise here.

```yaml
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
```

That list is a constant, and now literally so: it is
`[brief, prd, design, plan]` on every run, and re-entry protection
no longer subtracts from it. Phase 1 has no input that can shorten
it and no field that records a different shape.

When re-entry protection holds a child back, the entry shape is:

```yaml
chain_skipped:
  - child: prd
    reason: settled-artifact-at-canonical-path-reentry-protection
```

`child` is the pattern-level entry key and `reason` is a member of
the closed vocabulary in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`;
neither is `/scope`'s to choose. That member is the only reason
Phase 1 ever writes. A child is never recorded there because
Phase 1 judged its artifact not worth producing; Phase 1 makes no
such judgment. (Phase 2 writes `prd-boundary-rejection` or
`design-boundary-rejection`, when a Reject at a settled-upstream
boundary ends the chain and the children below it never run — see
the decision-record templates under `skills/scope/references/`.)

Phase 2 reads `planned_chain:` and invokes the listed children in
order, skipping any that `chain_skipped:` already names; it does
NOT re-walk Phase 1's evaluations per child. Phase 1's verdicts are
the cached chain-shape, carried across the two lists together, and
Phase 2 consumes them.

## Initial `child_snapshots:` Capture

For each pre-existing durable artifact discovered during the
discovery prompt (`docs/briefs/BRIEF-<topic>.md`,
`docs/prds/PRD-<topic>.md`,
`docs/designs/current/DESIGN-<topic>.md`,
`docs/plans/PLAN-<topic>.md`), Phase 1 captures an initial
snapshot per R10:

```yaml
child_snapshots:
  prd:
    status: Accepted
    content_hash: <git-blob-hash>
    captured_at: <ISO-8601 timestamp>
```

The dual-check pair (status + content-hash) catches both kinds
of drift on subsequent `/scope` resumes: a status flip and a
body edit at the same status.

## Three-Way Adjust Path

When the author selects Adjust, Phase 1 re-enters at the
discovery prompt with the author's adjustment input merged in —
a re-framed topic, a corrected framing-shift answer, a different
read on the problem. Adjust does not change chain membership,
per the declaration in the Adjust option above: the planned chain
is the same four children on every run, and a re-framed topic
returns a proposal over the same four. Re-entry re-runs the R6
predicates and re-emits the chain proposal; the loop continues
until the author selects Proceed or Bail.
There is no implicit limit on Adjust iterations; the
`--max-rounds=N` flag governs re-evaluation iterations across
chain instances, not Phase 1 Adjust iterations within a single
chain run.

## References

- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` —
  Gate Vocabulary (ALWAYS, shape-dependent,
  Mandatory-with-auto-skip), Conditional Feeder Invocation Shape.
- `skills/scope/references/phases/phase-2-chain-orchestration.md`
  — the Consolidation Judgment that reduces the artifact set
  after the artifacts exist.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
  — `planned_chain:` / `chain_ran:` / `chain_skipped:` triad,
  per-child snapshot dual-check.
