# Decision 5 — The Parent Upstream Contract

Design research for PRD-chain-cardinality, R15–R20 and R23–R24. The mechanism
(flag inbound plus durable recording) is settled upstream; this report designs it.

## Question

How should a parent accept, record, hand off, and resume an upstream it did not
produce, and how should it surface that possibility before authoring at the chain
head?

## Drivers

**D1 — Both parents, one contract.** R20 binds the strategic VISION→STRATEGY hop
and the tactical ROADMAP→BRIEF hop. The two parents already share four pattern
references; a divergent flag name or a divergent state field would make the
contract un-citable at the pattern layer and force each parent to document its
own, which is exactly the drift the pattern documents exist to prevent.

**D2 — The positional contract is untouchable.** Both parents hard-reject artifact
paths in `$ARGUMENTS` (`skills/charter/references/phases/phase-0-setup.md:83-102`,
`skills/scope/references/phases/phase-0-setup.md:39-44`), and R16 preserves that.
Whatever carries the upstream must live outside the positional slot.

**D3 — Every path a parent derives comes from one validated slug.** State-file
path, terminal artifact path, child wip/ paths, the closed write-target set. A
supplied upstream is the first value in either parent that is *not* slug-derived,
so it needs its own storage, its own validation, and its own re-validation on
resume.

**D4 — The parent may not extend a child's input surface.**
`skills/scope/references/phases/phase-2-chain-orchestration.md:189-196` states it
flatly: `/scope` "does NOT extend the child's `$ARGUMENTS` parser, does NOT add
env-var consumption, does NOT add flags or arguments." Any hand-off must use a
mode the child already ships, or the child's own contract must be amended in its
own file.

**D5 — R15 must not become a prompt.** The rejected discovery scan was rejected
for adding a blocking prompt on every run with no safe `--auto` default. A notice
that blocks, or that fires as its own decision point, re-imports the cost the
rejection was avoiding.

**D6 — Nothing in the corpus may change.** R23. Every run without the flag must
behave byte-for-byte as it does today, including the two chain-proposal prompts
whose option lines evals assert against
(`skills/charter/references/phases/phase-1-discovery.md:288-291`;
`skills/scope/SKILL.md:335-346`).

**D7 — The parents' security envelope assumes no author-supplied input.**
`references/parent-skill-security.md:125-146` binds parents to a metadata-read-only
surface and requires that "Future parents adding direct author-input handling
SHALL re-state the interpolation contract explicitly rather than silently
broadening the surface." The flag is precisely that addition.

---

## 1. The flag surface

### 1.1 The name is `--upstream <path>`, identical on both parents

Three children already own the name with exactly this meaning — the artifact one
level up, recorded into the produced document's `upstream:` frontmatter:
`skills/prd/SKILL.md:81-86`, `skills/roadmap/SKILL.md:165-174`,
`skills/comp/SKILL.md:115-117`. `/charter` already *emits* it
(`skills/charter/references/phases/phase-2-chain-orchestration.md:363-368`, and
again on the resume path at `phase-resume.md:256`). Adopting the same token
inbound costs no new vocabulary; inventing a second one (`--from`,
`--upstream-vision`) would give one workspace two words for one relationship.

Identical across parents, for D1. Both parents' Execution-Mode Flags sections
already sit at the same position in their SKILL.md and already share `--auto`,
`--interactive`, and `--max-rounds`; `--upstream` joins that list in both.

**Inbound symmetry is natural, with one deliberate asymmetry to state out loud.**
The outbound contract to `/roadmap` "accepts the path with no basename
enforcement" (`phase-2-chain-orchestration.md:365-368`) — `/charter` is handing
over an artifact it just produced and whose type it therefore knows. The inbound
flag is the opposite situation: the parent is choosing which child mode to route
into on the strength of a string the author typed, and a wrong type silently
mis-frames the chain head. So inbound `--upstream` **does** enforce the basename,
and the design must say why the two directions differ rather than leaving a reader
to infer that symmetry means identical validation.

### 1.2 Parse position

`--upstream <path>` is parsed at Phase 0 alongside the existing execution-mode
flags, **before** the positional slug is validated. `/charter`'s rejection table
already reserves `--` for flag parsing and already contemplates "empty string
after flag-stripping" (`phase-0-setup.md:96-97`), so the ordering is established,
not new. Two consequences to pin in contract text:

- The token following `--upstream` is consumed as the flag's argument and is
  **never** tested against `^[a-z0-9-]+$`. This is what keeps R16's "without
  changing its positional argument contract" true: the path never enters the slot
  that rejects paths.
- A bare `--upstream` with no following value is a Phase 0 rejection naming the
  missing argument. Phase 0 stops, no state file is created — the same
  reject-and-stop discipline as a bad slug (`phase-0-setup.md:64-67`).

Contract form is `--upstream <path>` (space-separated), matching all three
existing consumers; `--upstream=<path>` is accepted as an alias.

### 1.3 Validation, per parent

Five checks, in order, all hard-stops at Phase 0. No state file is created on
failure, so a rejected run leaves nothing behind.

| # | Check | Failure | Precedent |
|---|---|---|---|
| 1 | Value is not under `wip/` | Reject; name the wip-hygiene rule | `skills/prd/references/phases/phase-3-draft.md:36-39`; `references/wip-hygiene.md:73` |
| 2 | Canonicalize (resolve symlinks); canonical path is inside the working tree | Reject; name the path | `skills/strategy/SKILL.md:138-142`; `skills/brief/references/phases/phase-0-setup.md:92-99` |
| 3 | File exists and is tracked (`git ls-files <path>` non-empty) | Reject; an untracked upstream becomes a dangling `upstream:` the moment the branch is shared | `skills/prd/references/phases/phase-3-draft.md:40-42` |
| 4 | Basename matches the parent's one accepted type | Reject, naming the expected type | `skills/brief/references/phases/phase-0-setup.md:100-113` |
| 5 | Frontmatter `status:` is settled for that type | Reject, naming the observed status | see below |

**Check 4, per parent.** `/charter` accepts `docs/visions/VISION-*.md` and nothing
else. `/scope` accepts `docs/roadmaps/ROADMAP-*.md` and nothing else. Each parent
has exactly one head-altitude upstream type, so the check is a single basename
test, not a table. `/brief`'s PRD-specific rejection prose
(`skills/brief/references/phases/phase-0-setup.md:114-127`) is the model for a
rejection that explains the chain direction rather than just refusing; `/scope`
should reuse it near-verbatim for a PRD path handed to `--upstream`, and
`/charter` should reject a STRATEGY path with the reason already written at
`phase-2-chain-orchestration.md:220-225` (a STRATEGY path is `/strategy`'s
lifecycle-verb mode, not an upstream).

**Check 5, per parent.** `/charter` requires `Accepted` or `Active` — the same
settled set its published-path gate already skips against
(`phase-2-chain-orchestration.md:30`). A Draft VISION is not a settled thesis, and
accepting one would let the flag do something the gate refuses to do for the
identical artifact sitting at the published path. `/scope` requires `Active`, which
the roadmap format already states as the precondition for serving as upstream
context (`skills/roadmap/references/roadmap-format.md:346-349`).

**Check 3 has a cross-repo tail.** `/prd` handles an out-of-repo canonical upstream
by detecting visibility and *omitting* the field
(`phase-3-draft.md:43-51`). A parent should **reject** instead: the flag is an
explicit author request, and silently recording nothing would leave the author
believing the link landed. Reject with the reason and the pointer to
`references/cross-repo-references.md`.

### 1.4 What the flag changes in each parent's chain — and where the two differ

This is the load-bearing asymmetry of R20, and forcing a false symmetry here would
produce wrong contract text.

**`/charter`: the flag skips a child.** The head-altitude artifact (VISION) is one
`/charter` would otherwise write. So R4's gate gains a second way to be satisfied:

> `/charter` invokes `/vision` unless an Accepted or Active VISION already exists
> at the published path **or a valid `--upstream` VISION was supplied**.

The sentence at `phase-2-chain-orchestration.md:36-38` — "A cold start is
therefore always a `/vision` run … nothing the author *says* about the thesis
changes that" — must be narrowed rather than deleted. It stays true of what the
author *says* (the thesis-shift classification still cannot conjure an upstream);
it stops being true of what the author *supplies*. `vision` then leaves
`planned_chain` and gains a `chain_skipped` entry with the reason
`upstream VISION supplied by flag`. The `/strategy` invocation takes shape 2 (VISION
path) as it does today — the shape already exists, the path simply comes from the
flag instead of from slug derivation.

**`/scope`: the flag skips nothing.** The ROADMAP is above `/scope`'s chain
entirely; no `/scope` run ever writes one. `planned_chain` stays
`[brief, prd, design, plan]` on every run, which preserves the invariant Phase 1
is built around (`skills/scope/references/phases/phase-1-discovery.md:11-36`).
The only change is that `/brief`'s invocation carries the upstream, so the BRIEF
records a link instead of being written with none.

R20's parity is at the requirement level. The mechanisms differ because the chains
differ, and the design should state that in one sentence rather than inventing a
shared abstraction over two genuinely different shapes.

---

## 2. The recording

### 2.1 Field, gate, write time

One field, same name in both parents:

```yaml
supplied_upstream: docs/visions/VISION-<name>.md    # /charter
supplied_upstream: docs/roadmaps/ROADMAP-<name>.md  # /scope
```

**Why a new name rather than reusing the existing path-valued fields.** Both
parents already carry a conditional, path-valued, non-slug-derived state field —
`referenced_strategy:` in `/charter`
(`skills/charter/references/phases/phase-state-management.md:186-191`) and
`referenced_artifact:` in `/scope` (`skills/scope/references/state-schema.md:89-91`).
Both are gated on `exit: re-evaluation` and both name the artifact a Decision
Record re-evaluates. Overloading either would collapse two unrelated conditions
onto one field and break R9 Part 3's absence check, which is defined per gate.
`supplied_upstream:` also reads correctly: it records what the run was *given*, as
distinct from what it produced or what it re-evaluated. The Extension Discipline
permits it (`references/parent-skill-state-schema.md:195-213`): it shadows no
pattern-level name and satisfies I-5.

**Gate:** present iff the run was invoked with `--upstream` and the value passed
all five Phase 0 checks. Absent on every run without the flag — which is R17's
"absent when nothing was consumed," since no flag means nothing to consume.

**Write time: Phase 0, immediately after validation.** This is what satisfies
R17's "durable enough to survive an interrupted run." Gating the field on the head
child having actually consumed it would push the write to Phase 2 and lose the
value to any interruption before then — the precise failure R17 names. The gate
must be a condition Phase 0 can evaluate and Phase 0 can write.

### 2.2 What this costs in the two schema documents

- `/charter`'s `phase-state-management.md:95-98` states "17 fields total: 11
  always-present, plus 6 conditional." That becomes 18 and 7. The new field gets a
  "Required iff `--upstream` was supplied and validated; MUST be absent otherwise"
  entry alongside the existing six, and R9 failure mode 3 (conditional field
  present when ungated) extends to it unchanged.
- `/scope`'s `references/state-schema.md` gains the same entry. Its R9 Part 3
  binding (`references/parent-skill-state-schema.md:245-250`) already covers
  chain-position-gated fields; this one is invocation-gated, which is the same
  shape as `plan_execution_mode:` and needs no new machinery.

### 2.3 The head-child-skipped edge, stated rather than engineered

On `/scope`, `/brief` can be held back by re-entry protection
(`phase-1-discovery.md:107-120`) — an Accepted BRIEF already exists at the
canonical path. A supplied upstream then has nowhere to land, because the artifact
that would carry it is not being written. The parent should **state** this in the
chain proposal and continue: the supplied upstream will not be recorded in any
artifact this run produces, because `/brief` is held back, and the link would have
to be added to the existing BRIEF's own `upstream:`. `supplied_upstream:` still
records what the run was given. This is a stated fact in the existing proposal
output, not a new prompt — the same discipline as `/charter`'s stated-skip rule
(`phase-2-chain-orchestration.md:96-111`).

---

## 3. The hand-off — and the defect it exposes

R18 requires the produced artifact to carry the link in its own frontmatter.
Both child modes the PRD assumes exist do exist. **Neither is usable as-is.**

### 3.1 The finding

Both head children derive their own topic slug from the basename of the positional
path they are handed:

- `skills/strategy/references/phases/phase-0-setup.md:98-103` — "If `$ARGUMENTS`
  is a path argument, take the basename, strip the `VISION-` or `PRD-` prefix and
  `.md` suffix, and use the remainder."
- `skills/brief/references/phases/phase-0-setup.md:78-82` — the same rule for
  `ROADMAP-`.

So handing the supplied upstream positionally renames the produced artifact after
the upstream:

- `/charter platform-bet --upstream docs/visions/VISION-developer-trust.md` →
  `/strategy docs/visions/VISION-developer-trust.md` →
  `docs/strategies/STRATEGY-developer-trust.md`, while `/charter` expects
  `STRATEGY-platform-bet.md` in `exit_artifacts`, `child_snapshots`, and the R14
  permitted-source list (`phase-resume.md:441-444`).
- `/scope chain-cardinality --upstream docs/roadmaps/ROADMAP-shirabe-workflows.md`
  → `/brief docs/roadmaps/ROADMAP-shirabe-workflows.md` →
  `docs/briefs/BRIEF-shirabe-workflows.md`, which fails `/scope`'s R20 structural
  file-existence check (`phase-2-chain-orchestration.md:205-235`) and routes the
  run to a STALE bail.

This works today only because the two slugs coincide by construction: `/charter`
shape 2 passes `docs/visions/VISION-<topic>.md`, derived from the same slug the
run is keyed on. The coincidence is the whole reason the defect has never fired,
and the reuse case is defined by the coincidence not holding.

A second failure hides behind the first on the tactical side: a ROADMAP sequences
many features, and `/brief`'s upstream mode has to "find the feature this brief
frames" (`skills/brief/references/phases/phase-1-discover.md:41-50`). Handed only
a path, it must guess or ask. Handed the slug *and* the path, it has the feature
name.

### 3.2 Recommended hand-off — `<slug> --upstream <path>` to the head child

Give `/strategy` and `/brief` an `--upstream <path>` flag, matching `/prd`,
`/roadmap`, and `/comp`. Both parents then invoke:

- `/strategy <topic-slug> --upstream docs/visions/VISION-<name>.md`
- `/brief <topic-slug> --upstream docs/roadmaps/ROADMAP-<name>.md`

The slug stays the parent's, the upstream is decoupled from it, and both children
already have the frontmatter write: `/strategy` Mode 3 records the path as the
draft's `upstream:` (`skills/strategy/SKILL.md:113-116`), and `/brief`'s draft
phase writes `upstream: <path to upstream ROADMAP…>` from whatever Phase 0
recorded (`skills/brief/references/phases/phase-2-draft.md:75,84`). Only the input
route needs adding; the recording half is shipped.

**On D4.** The constraint forbids a *parent* extending a child's parser. This is a
change authored in each child's own contract — SKILL.md Input Modes, Phase 0
detection, evals — and it is equally usable by direct invocation, which is the
test that separates a genuine child capability from a parent-only side door. It is
also the change that removes a real defect the other three children never had:
`/strategy` and `/brief` are the only doc-emitting children that conflate "where
the upstream is" with "what this document is called." The design should defend
this reading explicitly rather than let it pass as obvious.

**Consequence worth taking.** Once `/strategy` accepts the flag, `/charter` should
pass `<slug> --upstream <vision-path>` in *both* cases — the VISION this chain just
produced and the VISION supplied by flag — which removes the dependence on slug
coincidence entirely instead of leaving one code path relying on it. Shape 2 in
`phase-2-chain-orchestration.md:206-209` becomes the flag form; shapes 1 and 3 are
untouched.

---

## 4. Resume

### 4.1 Where the check belongs

Immediately after the state file parses well-formed and before the ladder's silent
resume row. On `/charter` that is between row 1/row 2 and **row 3**, which resumes
at the recorded `phase_pointer` "without any intervention prompt"
(`skills/charter/references/phases/phase-resume.md:119-128`) — row 3 is exactly
the silent continuation R19 forbids. `/scope` inherits the same universal rows 1-4
(`skills/scope/SKILL.md:252-258`), so the check sits at the identical position.

### 4.2 The rule to mirror already exists — twice

`references/parent-skill-security.md` contains two instances of one principle:
re-validate what you recovered from disk before you use it. Slug re-validation on
resume (`:20-39`) covers slugs recovered from artifact paths; state-file enum
re-validation (`:67-86`) covers enum-typed fields, "BEFORE being used to construct
write paths or interpolate into shell commands." A recorded path is the third
instance and belongs in the same document so both parents cite one source.

**Placement recommendation with its cost stated.** Add it as a subsection under
the existing slug/enum family rather than as a seventh surface. Both parents'
SKILL.md and Reference Files tables say "six pattern-level security contract
surfaces" (`skills/charter/SKILL.md:228`, `skills/scope/SKILL.md:326,668-673`); a
seventh is a text change in both parents plus their eval baselines, for no
semantic gain. The alternative is defensible but costs more than it buys.

### 4.3 Two failure shapes, two outcomes

**Shape A — the recorded path no longer resolves or is no longer tracked.** The
parent cannot tell "moved" from "deleted" and should not pretend to; it knows only
that the path does not resolve. Surface a three-option prompt:

- **Re-supply** — the author names the corrected path; `supplied_upstream:` is
  rewritten (after the same five Phase 0 checks) and the run continues.
- **Continue without** — `supplied_upstream:` is removed and the run continues with
  no upstream. If the head artifact is already on disk, its stale `upstream:` is
  named to the author, since the parent does not edit child artifacts.
- **Bail** — routes to the parent's bail-handling rule (R8 for `/scope`; the
  exit-path orchestration for `/charter`).

In `--auto`, the default is **Bail**. This is the one place the recommendation
diverges from the drift prompt's `--auto` default of `Re-run`
(`skills/scope/references/phases/phase-resume.md:107-111`): drift means a known
artifact changed, while a vanished upstream means the run's stated lineage is gone,
and continuing non-interactively would produce an artifact whose `upstream:` the
author never agreed to drop.

**Shape B — the recorded path resolves but fails re-validation** (outside the
working tree, wrong type, no longer tracked, under `wip/`). This is the
state-file-tampering surface, and it **fails closed** with no prompt, matching
"Out-of-enum values fail the resume ladder and route to the parent's bail-handling
rule" (`parent-skill-security.md:85-86`). Distinguishing A from B matters: A is an
author-facing fact about the corpus, B is a contract violation.

---

## 5. The pre-authoring notice (R15)

### 5.1 A notice is not a prompt

The distinction is what makes R15 satisfiable at all. A prompt has options, a
default, and an answer that changes control flow; the run cannot proceed until it
is answered. A notice has none of those: it states a fact, changes nothing, and
the only way to act on it is to re-invoke with the flag. The workspace already has
two of these, and both are the model here:

- The stated-skip rule (`skills/charter/references/phases/phase-2-chain-orchestration.md:96-111`)
  — a sentence the author is owed, in the conversation only, recorded nowhere.
- The slug-prefix mismatch recommendation
  (`skills/scope/references/phases/phase-0-setup.md:64-70`) — "surfaces the CLI
  output verbatim as an informational prompt … The recommendation does not block
  the run."

### 5.2 Where it fires

Inside the chain-proposal output that already fires on every run, as part of the
head child's entry — `/vision`'s in `/charter`
(`phase-1-discovery.md:216-273`), `/brief`'s in `/scope` (`skills/scope/SKILL.md:335-346`).

This placement clears all four constraints at once:

- **Before authoring.** The chain proposal is emitted before any child fires
  (`phase-1-discovery.md:288-291`: "Once the author Proceeds, Phase 2's chain
  orchestration runs the children").
- **No directory scan.** The notice names no candidate. It says a head artifact is
  about to be written and how to attach to an existing one instead. It does not
  need to know whether one exists — which is exactly why it is cheap where the
  scan was not.
- **Defined in `--auto`.** The chain proposal is emitted in `--auto` and
  auto-Proceeds; the notice rides along as output and the run continues. Nothing
  blocks, so there is no default to get wrong.
- **Not a prompt on every run.** It adds no decision point. The proposal's option
  line — the byte-for-byte-asserted `Proceed` / `Adjust` / `Bail` — is untouched;
  the notice text sits in the entry list above it.

### 5.3 Gate

Fires iff **the head child will author a new head-altitude artifact** AND
**`--upstream` was not supplied**. Both conditions are known at chain-proposal
time from `planned_chain`, with no filesystem work beyond the globs Phase 1
already runs.

- `/charter`: fires when `vision` is in `planned_chain` and not skipped. An
  Accepted/Active VISION at the published path already skips `/vision`, so the
  notice does not fire on the runs where the duplicate is impossible.
- `/scope`: fires when `brief` is in `planned_chain` and not held back by re-entry
  protection.

### 5.4 Proposed wording

Contract text — evals will grep it, so it needs pinning verbatim in the design.

`/charter`, on the `/vision` "run" entry:

> run `/vision` — no VISION exists at `docs/visions/VISION-<topic>.md`, so this
> chain writes a new thesis. If a thesis this bet sits under already exists at
> another name, re-invoke as `/charter <topic> --upstream docs/visions/VISION-<name>.md`
> to build on it instead; `/vision` is then skipped and the STRATEGY records that
> VISION as its upstream. Proceeding writes a new VISION.

`/scope`, on the `/brief` entry:

> run `/brief` — this chain writes the feature's framing from the topic alone. If
> this feature is already sequenced in a ROADMAP, re-invoke as
> `/scope <topic> --upstream docs/roadmaps/ROADMAP-<name>.md`; the BRIEF then
> records that ROADMAP as its upstream instead of re-deriving framing the roadmap
> already settled. Proceeding writes a BRIEF with no upstream link.

The `/scope` wording deliberately echoes the skill's own condemnation of the
bare-slug head hop — "a child handed a bare slug re-derives the framing its
upstream already settled, and records no `upstream:` link back to it"
(`phase-2-chain-orchestration.md:198-203`). The notice is that sentence turned
outward to the author.

---

## 6. R16 and the security envelope

The flag is the first author-supplied input either parent has ever taken, so
`parent-skill-security.md:141-146` requires each parent to re-state the
interpolation contract explicitly rather than let the surface broaden silently.
Five statements, one per surface the flag touches:

1. **Interpolation.** The `--upstream` value is never interpolated into a
   `-m "<string>"` shell argument. It reaches `git ls-files` and any canonical-path
   resolution as a separate argv element, and lands in the state file as a YAML
   scalar. This preserves the surface the pattern assigns to parents
   (`:125-140`).
2. **Canonicalization.** Resolve symlinks and confine to the working tree at Phase
   0, before any read — the rule `/strategy` (`SKILL.md:138-142`) and `/brief`
   (`phase-0-setup.md:92-99`) already carry, imported verbatim so the two parents
   and the two children state one rule.
3. **Write-target set unchanged.** The upstream is a **read** target. Neither
   parent writes to it, and the closed write-target set
   (`parent-skill-security.md:41-65`) gains nothing. This is worth stating
   explicitly because a reader scanning the change will reasonably expect the
   enumeration to move, and it does not.
4. **Re-validation on resume.** Section 4.2 above. A recorded path recovered from
   the state file is re-validated before it is read or handed to a child, closing
   the tampering surface enum re-validation closes for enums.
5. **Visibility.** A public-repo run rejects a supplied upstream whose canonical
   location is a private repo, per `references/cross-repo-references.md`. This is
   the parent's binding of the visibility surface (`:109-123`) to its first
   author-supplied path.

One further note: `/charter`'s R14 permitted-source list is declared exhaustive
and names three slug-derived paths (`phase-resume.md:435-449`). Reading a supplied
VISION at a foreign path widens it to four. That is a one-line change in scope but
it costs the property that the read surface is finite by slug derivation; the list
stays finite and nameable — "the published path, the recorded
`supplied_upstream:` path, the git blob hash of either, and the state file" — which
is the property actually worth keeping.

---

## Recommendation

1. **Flag.** `--upstream <path>` on both parents, parsed at Phase 0 before the
   positional slug check, validated by five hard-stop checks (not under `wip/`;
   canonical and in-tree; tracked; correct basename for the parent's one accepted
   type; settled status — Accepted/Active for VISION, Active for ROADMAP). The
   positional slot and its rejection are untouched. Inbound enforces the basename
   even though outbound does not, and the design says why.
2. **Recording.** `supplied_upstream:` in both state files, gated on the flag
   having been supplied and validated, written at Phase 0 so it survives
   interruption, absent otherwise under I-5 and R9 Part 3. `/charter`'s field count
   goes 17→18 and 6→7 conditional.
3. **Hand-off.** Add `--upstream <path>` to `/strategy` and `/brief`, matching
   `/prd`, `/roadmap`, and `/comp`, and invoke the head child as
   `<slug> --upstream <path>`. The positional path modes cannot be used: both
   children derive their slug from the path's basename, which renames the produced
   artifact after the upstream and, on `/scope`, trips the R20 structural check into
   a STALE bail. Both children already write `upstream:` into frontmatter; only the
   input route is missing. `/charter` should then use the flag for the
   produced-in-chain VISION too, retiring the slug-coincidence dependency.
4. **Resume.** A recorded-path re-validation step after the malformed-state row and
   before the silent-resume row on both ladders, documented once in
   `parent-skill-security.md` under the existing recovered-value family (not as a
   seventh surface). Vanished → Re-supply / Continue without / Bail, defaulting to
   Bail in `--auto`. Invalid → fail closed to bail-handling, no prompt.
5. **Notice.** A non-blocking sentence inside the existing chain-proposal entry for
   the head child, gated on "a new head artifact will be authored AND no
   `--upstream` was supplied." No scan, no new decision point, no change to the
   asserted option line, emitted identically in `--auto`.

**Mechanism differs across the two chains and the design should say so.** On
`/charter` the flag skips `/vision` and amends R4's gate; on `/scope` it skips
nothing and only enriches `/brief`'s invocation. R20's parity is at the requirement
level, not the mechanism level.

---

## Rejected alternatives

**Positional path to the head child (existing Input Mode 3), as R18's wording
invites.** Rejected on the slug-derivation evidence in §3.1: it renames the
produced artifact after the upstream and breaks the parent's slug-keyed
derivations on both chains. This is the option a reader of R18 will assume was
taken, so the design owes it an explicit rejection with the two file citations.

**Handoff-file pre-population, mirroring `wip/roadmap_<topic>_scope.md`.** The
parent writes the upstream into the head child's own context file
(`wip/brief_<topic>_context.md`, `wip/strategy_<topic>_discover.md`) and invokes
with a bare slug. Genuine precedent — `/charter` already pre-populates a seven-field
handoff for `/roadmap` (`phase-2-chain-orchestration.md:361-396`). Rejected because
it makes the parent an author of the child's internal Phase 0 schema, a far deeper
coupling than a flag and one the child-inspection rule works to prevent in the read
direction. The precedent also argues against itself: even in the roadmap handoff,
lineage travels by `--upstream` flag and the handoff file carries only content.

**A parent-specific flag name (`--upstream-vision` / `--upstream-roadmap`).**
Self-documenting at the point of use, and it makes the type check redundant with
the flag name. Rejected on D1: two names for one relationship makes the contract
un-citable at the pattern layer, and the type is already unambiguous from which
parent was invoked.

**Reusing `referenced_strategy:` / `referenced_artifact:` for the recording.** Zero
new fields. Rejected because both are gated on `exit: re-evaluation` and R9's
absence check is defined per gate; two conditions on one field cannot both be
enforced.

**Gating `supplied_upstream:` on the head child having consumed it.** A tighter
reading of R17's "consumed." Rejected because it forces the write to Phase 2 and
loses the value to exactly the interruption R17 names.

**A seventh security surface for recorded-path re-validation.** Cleaner taxonomy.
Rejected on cost: both parents' SKILL.md and eval baselines say "six," and the rule
is the same principle as the two surfaces already there.

**A notice that names candidates.** More useful to the author. Rejected — it is the
scan the PRD already rejected, wearing different clothes.

---

## Open risks

**R1 — The child-side change is the crux and the constraint is a judgment call.**
Everything else here is parent-local. Adding `--upstream` to `/strategy` and
`/brief` touches two child SKILL.md files, two Phase 0 detection steps, and their
eval baselines. If the design decides D4 forbids it, the only remaining route is
the handoff-file pre-population rejected above, and R18 gets satisfied at a much
higher coupling cost. This is the one place the decision could reasonably go the
other way, and it should be argued rather than assumed.

**R2 — R18's wording presumes a mode that does not work.** "the child whose input
mode accepts it" reads as though the positional modes suffice. They do not. The
design should note the discrepancy rather than silently satisfying R18 by a route
its wording did not anticipate.

**R3 — VISION Accepted→Active is unowned.** `Active` means "at least one STRATEGY
references this VISION as its upstream"
(`skills/vision/references/vision-format.md:133,145`). A reuse run makes that true
for a VISION that was `Accepted`, and `/charter` never invokes `/vision`, so
nothing drives the transition. R24 forbids new statuses but not new transitions;
this is a small gap the design should either assign or explicitly defer.

**R4 — This is the change that makes the conflict finding live.** The PRD says so
directly and puts the ordering guard in the plan's issue graph, not in the
requirements. Worth restating in the design: the flag makes concurrent chains under
one upstream easy, and on the strategic chain no diagnosis exists at all because
the strategic directories are not indexed.

**R5 — Eval surface.** `/charter`'s five canonical slug-rejection rows are the
shared eval baseline (`phase-0-setup.md:99-102`), and both chain-proposal option
lines are asserted byte-for-byte. The notice text and the new flag-rejection
messages need their own fixtures, and the design should say which existing
fixtures are untouched so R23's "no test modified or removed" stays checkable.

**R6 — `/scope` never looks in `docs/roadmaps/`.** Phase 1's globs cover briefs,
prds, designs, plans only (`phase-1-discovery.md:55-62`), and
`slug-prefix-detect`'s sampler excludes roadmaps as well. Nothing here requires
changing that — the flag is how the roadmap arrives — but a reader will ask, and
the design should state that the directory stays unscanned by choice, which is the
same choice that rejected the discovery scan.
