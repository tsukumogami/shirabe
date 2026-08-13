# Reuse Mechanisms: How a Parent Could Consume an Upstream It Did Not Produce

Research for PRD-chain-cardinality, Phase 2. Options presented neutrally with
costs; no recommendation.

## The structural fact that shapes every option

The parent-to-child edge already carries a path. `/charter` hands `/strategy`
one of three shapes, and shape 2 is "VISION path" — `/strategy` reads it as its
Input Mode 3 upstream (`skills/charter/references/phases/phase-2-chain-orchestration.md:206-209`,
consuming `skills/strategy/SKILL.md:113-116`). `/charter` also hands `/roadmap`
an explicit `--upstream <strategy-path>` flag, and that contract "accepts the
path with no basename enforcement"
(`skills/charter/references/phases/phase-2-chain-orchestration.md:365-368`).

So the outbound interface is already path-shaped and already slug-agnostic. What
is slug-locked is where the path *comes from*: R6 shape 2 fires when a VISION is
"already Accepted/Active at the published path", and the published path is
`docs/visions/VISION-<topic>.md` derived from the one validated slug
(`phase-2-chain-orchestration.md:32-38`). Discovery probes exactly that one path
(`phase-1-discovery.md:151-155`), and the R14 permitted-source list names it
literally (`phase-resume.md:441-444`).

Every option below is a different answer to one question: how does a path whose
basename slug differs from the run's topic slug get into the value R6 shape 2
already knows how to pass? None of them changes what `/strategy` receives.

A second structural fact: the VISION is *not* a write target in the reuse case.
`/charter` skips `/vision` and the closed write-target set
(`references/parent-skill-security.md:41-66`) is unaffected — reuse adds a read
target, not a write target. That lowers the cost of (a), (b), (c) and (e1)
substantially relative to what the security envelope might suggest.

## (a) A VISION-path input mode on `/charter`, mirroring `/strategy` Mode 3

**Mechanism.** Add a third input mode: `$ARGUMENTS` matching
`docs/visions/VISION-*.md` is treated as the upstream VISION; the run's own
topic slug is then asked for (or derived), and R6 shape 2 passes the given path
through unchanged.

**Does it conflict with the path-rejection requirement?** The requirement's
actual wording, at `docs/prds/PRD-shirabe-charter-skill.md:280-282`:

> `/charter` MUST NOT accept paths to durable artifacts as input
> (unlike `/strategy`'s Input Modes 2-3). The chain produces multiple
> artifacts; an upstream-path input mode does not compose.

The rationale is a claim about composition, not about the argument slot. It sits
directly under R2, whose two bullets are both about the positional `$ARGUMENTS`
slot, and the SKILL.md restatement is explicitly about the regex check:
"A `$ARGUMENTS` value that looks like a path fails the regex … and is rejected at
Phase 0" (`skills/charter/SKILL.md:81-88`). The stated reason for the rejection
is that the slug is needed for many derived paths, and a path argument supplies
only one of them — "the chain produces multiple artifacts" is a statement that
one path cannot stand in for the slug, not that the parent may never read an
upstream at a foreign path. Read that way, the requirement is aimed at the slot,
and (a) reopens it head-on while (b), (c) and (e1) do not.

Read the other way — as a flat prohibition on path input in any form — (a) is a
direct amendment of R2 and its AC. Either reading needs the PRD to say which.

**Files/contracts that change.** `docs/prds/PRD-shirabe-charter-skill.md:271-282`
(R2 and its rationale); `docs/prds/PRD-shirabe-charter-skill.md:830-833` (AC4);
`skills/charter/SKILL.md:61-93` (Input Modes, including the "Path-as-upstream is
the wrong shape" paragraph); `skills/charter/references/phases/phase-0-setup.md:95`
(the canonical rejection-table row that names `docs/visions/VISION-foo.md`) and
`:99` (the five rows are the shared eval baseline, so eval fixtures change);
`phase-2-chain-orchestration.md:32-47` (the `/vision` gate now has a second way
to be satisfied). A path-canonicalization rule must be added — `/strategy` already
has the wording to copy (`skills/strategy/SKILL.md:138-142`: reject when the
canonical path resolves outside the working tree). `/scope` carries the identical
rejection prose (`skills/scope/SKILL.md:89-94`, `skills/scope/references/phases/phase-0-setup.md:42-45`),
so leaving it alone makes the two parents diverge on their entry contract.

**What breaks.** The slug still has to come from somewhere — a VISION path alone
does not tell `/charter` what to name the STRATEGY. So (a) is really a two-input
mode (path + slug) wearing a one-input costume, and either it prompts for the
slug (adding a Phase 0 interaction the cold-start path deliberately does not
have — `phase-0-setup.md:43-44`: "does not auto-retry, does not loop, and does not
derive a slug") or it derives the slug from the path, which is exactly the
normalization `phase-0-setup.md:55-59` forbids. Also: `references/parent-skill-security.md:141-146`
requires a parent that adds direct author-input handling to re-state the
interpolation contract explicitly rather than silently broaden the surface.

**What it does not solve.** Nothing about `/scope`'s head hop; nothing about the
validator half (posture-per-chain, `upstream:` list handling, the first-upstream
chain walk); nothing about absorb-with-siblings. It also does not help the author
who does not know the VISION's path — it converts the problem into a lookup the
author performs by hand.

## (b) Decouple the slug: one slug for own artifacts, a separate upstream reference

**Mechanism.** The run keeps its topic slug for everything it writes and gains a
separate, explicitly-recorded upstream reference that need not share that slug.
Discovery (however it obtains the path — prompt, scan, flag) resolves an upstream
VISION; the state file records it; R6 shape 2 reads the recorded value instead of
re-deriving `docs/visions/VISION-<topic>.md`.

**State fields.** The 5-field floor (`references/parent-skill-state-schema.md:16-37`)
is untouched. This is a parent-specific extension under the Extension Discipline
(`:195-213`), which permits additional top-level keys provided they do not shadow
pattern-level names and satisfy I-5 conditional gating. A field such as
`upstream_vision: <path>` gated on "the chain skipped `/vision` because it reused
an existing one" is well-formed under those rules, and R9 Part 3
(`:245-250`) then requires it absent when the gate does not hold. Precedent for
exactly this shape exists: `referenced_strategy: <path>` is already a
conditional, path-valued, non-slug-derived state field, set on the
re-evaluation exit (`docs/prds/PRD-shirabe-charter-skill.md:537`).

**Canonical-path derivations that change.** Exactly one read derivation:
`docs/visions/VISION-<topic>.md` at `phase-2-chain-orchestration.md:32-38`,
`phase-1-discovery.md:151-155`, and permitted-source 1 of the R14 list
(`phase-resume.md:441-444`) — which must be widened from "the published path" to
"the published path or the recorded upstream path", or drift detection on the
reused VISION silently reads the wrong file (or nothing) on resume. The STRATEGY
and ROADMAP derivations, `exit_artifacts`, the wip/ paths, and the whole closed
write-target set stay slug-derived and unchanged.

**What breaks.** Resume acquires a new consistency question the ladder does not
currently have: the recorded upstream path may have moved, been sunset, or been
deleted between resumes. Row 6's status-aware re-entry and the child-snapshot
dual-check both assume the artifact is findable by slug
(`phase-resume.md:441-444`); a recorded path that no longer resolves needs a new
ladder outcome. Slug re-validation on resume (`references/parent-skill-security.md:20-39`)
covers slugs recovered from paths but says nothing about a recorded path field —
`/scope` already has the analogous rule for glob-recovered slugs
(`skills/scope/references/phases/phase-0-setup.md:88-100`) and would be the model.

**What it does not solve.** It is a mechanism, not a policy: (b) says where the
path is stored, not how the author supplies it. It composes with (a), (c) or
(e1) rather than replacing any of them. Same non-coverage as (a) on the validator
half and on `/scope`.

## (c) Discovery-time scan of `docs/visions/` with a "which thesis?" prompt

**Mechanism.** Phase 1 stops probing one path and instead enumerates
`docs/visions/VISION-*.md`, filters to Accepted/Active, and — when one or more
exist — asks the author which thesis this bet sits under (with "none of these,
write a new one" as an option). The chosen path feeds R6 shape 2. Needs (b)'s
storage to survive a resume.

**Does a directory scan breach R14?** No, on the rule as written.
`references/parent-skill-child-inspection.md:23-27` confines the parent to the
child's "durable externally-visible status surface"; a committed VISION's
frontmatter `status:` is precisely that surface
(`parent-skill-child-inspection.md:60-73`), and the negative-examples list
(`:132-155`) is entirely about internals — wip/research, CI logs, comment threads,
child phase pointers. A published VISION is on the permitted side of every line
the document draws.

The friction is with `/charter`'s own *narrower* restatement, not with R14.
`phase-resume.md:435-444` says the ladder's permitted sources "are exhaustive"
and names the three paths literally, each slug-derived. A scan reads documents
outside that enumeration. That is a `/charter`-local list that would need
widening — a one-line change in scope, but it is the sentence that currently
makes the enumeration checkable, so widening it costs the property that the
read surface is finite and nameable. Note the scan reads *sibling* documents,
not the invoked child's internals: R14's actual concern (coupling to a child's
implementation detail) is not engaged.

**Precedent that makes this cheaper than it looks.** `/scope` Phase 0 already
samples a docs directory — `shirabe slug-prefix-detect <slug> --docs-root docs`
walks `docs/{briefs,prds,designs,plans}/`
(`skills/scope/references/phases/phase-0-setup.md:47-76`, CLI at
`crates/shirabe/src/main.rs:150-159`). The lazy-load principle stated there
("Phase 0 does NOT duplicate the docs-directory walk … in SKILL prose",
`phase-0-setup.md:73-76`) suggests the scan belongs in the CLI rather than in
skill prose — see (e3).

**What breaks.** A new blocking prompt in Phase 1 that fires on every run in a
repo with any Accepted VISION, including runs where the author is doing exactly
what they do today. `--auto` needs a defined answer (the existing `--auto`
contract picks "the recommended default based on context",
`skills/charter/SKILL.md:99-101` — for this prompt the default is not obvious and
picking wrong silently attaches a bet to the wrong thesis, which is a worse
failure than today's duplicate VISION because it is invisible). The chain-proposal
prompt's stability contract (`phase-1-discovery.md:286-291`, `Proceed`/`Adjust`/`Bail`
asserted byte-for-byte by evals) constrains where a new prompt can sit.

**What it does not solve.** Same validator-half non-coverage. Also does not help
when the right VISION lives in another repo — cross-repo `upstream:` is a
documented shape (`skills/strategy/references/strategy-format.md:53`) that a
local directory scan cannot see.

## (d) Do nothing in the parent; sanction direct `/strategy`

**Mechanism.** Keep the parent slug-locked. State that a second bet under an
existing thesis is reached by invoking `/strategy docs/visions/VISION-<thesis>.md`
directly.

**What would have to change for it to be honest rather than a gap.** More than
it first appears, because the pieces that would make it honest are half-present
and one of them currently says the opposite.

1. The cold-start rule would have to stop being absolute-and-silent.
   `phase-2-chain-orchestration.md:32-38` states that a cold start is always a
   `/vision` run and "nothing the author says about the thesis changes that."
   For (d) to be honest, that rule needs a stated escape: when no VISION exists
   at this slug's path but the author says one exists elsewhere, `/charter` must
   say so and name the direct-`/strategy` route rather than writing a second
   thesis. That is a real behavior change — it needs the thesis-shift
   classification (`phase-1-discovery.md:157-197`) to gain a fourth outcome
   ("existing thesis, different slug") that today collapses into no-signal.
2. The direct route needs to be documented as a first-class capability for
   *this* case. R13 non-interference already makes direct invocation first-class
   in general (`phase-1-discovery.md:73-88`, `parent-skill-child-inspection.md:109-124`),
   and US-4 documents it for the reviewer-redirect case
   (`docs/prds/PRD-shirabe-charter-skill.md:226-249`). Neither names the
   second-bet case; the outcome section of the upstream brief explicitly rejects
   leaving "the author to discover that reaching past the parent to a child skill
   was the only way to get what they wanted"
   (`docs/briefs/BRIEF-chain-cardinality.md:86-90`), so (d) has to argue against
   a written outcome, not merely fill a documentation hole.
3. `/charter`'s own description would need to stop promising the altitude range
   it does. `skills/charter/SKILL.md:3-13` says "Do NOT use when the author
   already knows which artifact altitude they want" — under (d), an author who
   wants the full strategic chain for a second bet must use the child anyway,
   which is the case that trigger phrasing was written to route *into* the parent.

**Cost.** Cheapest to implement, and it is the only option that requires no
change to the parent's read surface, state schema, or security envelope. It
buys that by making the parent's coverage explicitly partial — the shape the
formats describe (`skills/strategy/references/strategy-format.md:279`, multiple
STRATEGYs under one VISION) remains unreachable through the parent by design
rather than by accident.

**What it does not solve.** Everything the others do not, plus the author-facing
half of the brief's stated outcome.

## (e) Others the codebase suggests

### (e1) `--upstream <vision-path>` as an execution-mode-style flag

`/charter` already parses flags out of `$ARGUMENTS`
(`skills/charter/SKILL.md:96-111`) and already *passes* `--upstream` to
`/roadmap` with the explicit "no basename enforcement" contract
(`phase-2-chain-orchestration.md:365-368`). Accepting the symmetric flag on the
way in leaves the positional slug slot untouched, so R2's two bullets and the
whole Phase 0 rejection table (`phase-0-setup.md:85-99`) stand unamended — the
prohibition is on the *input mode*, and a flag is not one. Needs (b) for
storage, and needs the canonicalization rule from `skills/strategy/SKILL.md:138-142`
plus the explicit interpolation re-statement from
`references/parent-skill-security.md:141-146`.

Cost: it is a distinction the PRD would have to defend — "paths are not accepted
as input, except by flag" is either a clean separation of the slug slot from
upstream resolution or a workaround around R2's plain meaning, depending on
which reading of `PRD-shirabe-charter-skill.md:280-282` the PRD adopts. It also
requires the author to know the path, same as (a).

### (e2) Push the resolution down into `/strategy`

`/charter` changes nothing except its skip rule: on a cold start where the
author indicates an existing thesis, it skips `/vision` and passes the freeform
topic (R6 shape 1, `phase-2-chain-orchestration.md:202-205`). `/strategy`'s own
Phase 1 already does upstream grounding and already records `upstream:` from a
path it was given; it would gain the job of *finding* the VISION conversationally.

Cost: R14 is untouched, the state schema is untouched, the write-target set is
untouched — this is the smallest parent-side change of any option that actually
reaches the shape. Against it: it moves a chain-level concern into a child that
must then do it for both invocation paths, and `/charter` loses any record of
which thesis the bet attached to (its state file would show a skipped `/vision`
with no upstream), which weakens resume drift-detection and the audit trail the
brief's maintainer journey asks for
(`docs/briefs/BRIEF-chain-cardinality.md:114-120`).

### (e3) Put the scan in the CLI

Extend `shirabe slug-prefix-detect`'s sampler, or add a sibling subcommand, to
enumerate upstream candidates under `docs/visions/` (and `docs/roadmaps/` for
the tactical side). The sampler today covers only
`docs/{briefs,prds,designs,plans}/` (`crates/shirabe/src/main.rs:154-159`) —
the strategic directories are excluded there exactly as they are excluded from
the lifecycle document index (`docs/briefs/BRIEF-chain-cardinality.md:79-82`).
This is (c)'s mechanism with deterministic logic in Rust rather than in prose,
per the lazy-load principle `/scope` Phase 0 already states
(`skills/scope/references/phases/phase-0-setup.md:73-76`).

Cost: a Rust change plus tests on top of whichever skill-side option it serves;
does not by itself decide the prompt or the storage.

### (e4) A slug convention instead of a mechanism

Require a second bet's slug to extend its thesis's slug
(`<vision-slug>-<bet-name>`), so the VISION lookup becomes a longest-prefix walk
over one derived family rather than a single exact probe. Every path stays
slug-derived; no new state field, no new input, no scan of arbitrary documents.
The workspace already has prefix-convention machinery and a >50%-majority
detector to build on (`skills/scope/references/phases/phase-0-setup.md:56-72`).

Cost: it is a naming rule enforced by convention, so it fails open — an author
who picks an unrelated slug lands back in today's behavior with no signal. It
also constrains STRATEGY filenames for the benefit of a lookup, which inverts
the usual direction (`strategy-format.md` treats the slug as the bet's name,
not as a lineage encoding), and it cannot express a bet whose thesis is in
another repo.

## What none of the options address

Every option above touches the first bullet of the brief's scope boundary
("whether and how a parent skill can consume an upstream it did not produce",
`docs/briefs/BRIEF-chain-cardinality.md:143-145`) and none touches the rest:
posture-per-chain vs per-edge, the `upstream:` list handling end to end, the
chain walk that keeps only the first upstream, filename-dependent chain
selection, the absorbability test's blindness to consumer count, or whether the
strategic directories enter the lifecycle index. A parent that can reuse a
VISION makes the fan-out shape reachable — and therefore makes the validator
problems, which are currently theoretical on the strategic side precisely
because the directories are excluded from the index
(`docs/briefs/BRIEF-chain-cardinality.md:79-82`), start firing.

## An inconsistency any option must reconcile

AC4 and the shipped skill disagree about what a path argument does today.

`docs/prds/PRD-shirabe-charter-skill.md:830-833`:

> **AC4** Invoking `/charter docs/visions/VISION-foo.md` (path as `$ARGUMENTS`)
> is treated as a freeform topic **after slug derivation**; not interpreted as an
> upstream path.

`skills/charter/SKILL.md:84-88` and the canonical rejection row at
`skills/charter/references/phases/phase-0-setup.md:95` say the same input is
*rejected* at the regex check and Phase 0 stops without creating a state file —
"No normalization, no derivation, no 'best effort' massaging"
(`skills/charter/SKILL.md:77-79`). AC4's "after slug derivation" describes a
behavior the skill was subsequently written not to have. Options (a) and (e1)
rewrite AC4 anyway; options (b), (c), (d) and (e2) leave a stale AC in place
unless the PRD fixes it deliberately.

## Does `/scope` have the same latent problem?

Yes — the same structural gap, at the same position in the chain, with a
different and quieter consequence. The tactical chain's head is not solving what
the strategic chain's head cannot; it has the identical hole and PR #260 closed
every hop except that one.

**The gap.** `/scope` invokes `/brief` with the bare topic slug, and the reason
given is that "It is the head of the chain, so there is nothing above it to hand
it" (`skills/scope/references/phases/phase-2-chain-orchestration.md:164-167`;
the loop step at `:49-51` says the same). Every later child gets a path
(`:171-175`). But there *is* something above `/brief`: the ROADMAP, which
`/brief` Input Mode 3 accepts and which `/brief`'s format records as `upstream:`
(`skills/brief/SKILL.md:110-113`, `skills/brief/references/brief-format.md:31,52`).
`/scope` never passes it. `/scope` never even looks for it: Phase 1's discovery
globs are `docs/briefs/`, `docs/prds/`, `docs/designs/`, `docs/designs/current/`,
`docs/plans/` at `<topic>` (`skills/scope/references/phases/phase-1-discovery.md:56-59`)
— no `docs/roadmaps/` glob appears anywhere in `/scope`, and `slug-prefix-detect`'s
sampler excludes it too (`crates/shirabe/src/main.rs:154-159`).

**Why it is the same shape.** A ROADMAP sequences many features; each feature is
its own `/scope <feature-slug>` run; `docs/roadmaps/ROADMAP-<feature-slug>.md`
does not exist and should not. Slug-derivation cannot reach the upstream, exactly
as on the strategic side.

**Why the consequence is quieter.** `/scope`'s chain does not include `/roadmap`,
so there is no cold-start rule to fire and no duplicate artifact is written. The
BRIEF is simply created with no `upstream:` — and `upstream:` is optional in the
format (`skills/brief/references/brief-format.md:31`), so nothing fails. The
fan-out edge is not mis-recorded; it is never recorded. Silent lineage loss,
where `/charter` produces a visible spurious document.

**Why this is sharper than it looks.** `/scope`'s own stated justification for
passing paths condemns the exception:

> a child handed a bare slug re-derives the framing its upstream already
> settled, and records no `upstream:` link back to it. The paths above are what
> let each artifact cite the one above it instead of repeating it.
> (`skills/scope/references/phases/phase-2-chain-orchestration.md:200-207`)

That is a verbatim description of what `/scope` still does at the ROADMAP →
BRIEF hop. The head-hop exemption is correct only if "head of the chain" means
"head of the artifacts this run produces"; it is false if it means "nothing
upstream exists."

**And it is the cross-parent seam.** The ROADMAP is the one artifact produced by
one parent and consumed by another — `/charter` writes it (R7,
`phase-2-chain-orchestration.md:231-236`), and `/brief` takes it as upstream,
never a STRATEGY (`phase-2-chain-orchestration.md:416-421`). Neither parent
carries the handoff across the seam: `/charter` ends at the ROADMAP and `/scope`
starts below it without looking up. Any option chosen for `/charter`'s
VISION → STRATEGY hop has a direct analogue at `/scope`'s ROADMAP → BRIEF hop,
and the two are worth deciding together — the brief scopes both chains
(`docs/briefs/BRIEF-chain-cardinality.md:141-145`).
