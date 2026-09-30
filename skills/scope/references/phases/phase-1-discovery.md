# Phase 1 — Discovery and Chain Proposal

Phase 1 turns the topic slug into a planned chain. It runs the
discovery prompt to surface a framing-shift signal, evaluates
the re-entry protection each child carries, captures
initial child-snapshots for any pre-existing durable artifacts,
and emits a chain-proposal output the author confirms (Proceed /
Adjust / Bail).

## What Phase 1 Decides, and What It Does Not

Phase 1 decides **nothing about the size of the artifact set.**
`planned_chain:` is `[brief, prd, design, plan]` on every run.
There is no starting altitude to choose and no child that Phase 1
can decide is not worth invoking.

The only thing that stops a child from running is that its durable
artifact is already on disk at a settled status, which is
re-entry protection against overwriting settled work — not a
verdict on the artifact's worth. See "Re-Entry Protection" below.

Reducing the artifact set is Phase 2's job, after the artifacts
exist, and the consolidation judgment there is the only mechanism
that does it. See the Consolidation Judgment section of
`skills/scope/references/phases/phase-2-chain-orchestration.md`.

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
discovery walk, and the chain proceeds with `/brief` at its head
as always (the framing-shift answer is deferred to the BRIEF
authoring conversation).

## Entering Phase 1 With an `/explore` Handoff

When the resume ladder's Slot 7 clause fired, Phase 1 runs with the
handoff at `wip/scope_<topic>_handoff.md` pre-loaded as discovery
input. Two things change and nothing else does: the framing-shift
question is put as a confirmation of the answer the handoff carries
rather than as a fresh ask, and the author's response is what gets
recorded; and the cold-start projection above is suppressed, because
a handoff run is not a cold start. The child-doc globs run as always
— they are filesystem reads, and the handoff carries no filesystem
state.

The full clause, including what the handoff carries and what happens
when it is malformed, is in
`skills/scope/references/phases/phase-resume.md` (Slot 7).

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

## Chain-Proposal Output

After the re-entry protections evaluate, Phase 1 emits a
chain-proposal output naming the planned children, the re-entry
verdict for each, and the offered options. The output's options block
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
>   /design — runs (no settled artifact at the canonical path)
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
returns a proposal over the same four. Re-entry re-runs the
re-entry protections and re-emits the chain proposal; the loop continues
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
