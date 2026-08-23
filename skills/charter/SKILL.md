---
name: charter
description: >-
  Work out whether a body of work is worth doing and what order it happens in,
  ending with the bet written down and a sequenced set of features under it:
  why this should exist, what we are actually betting on, and what gets built
  first. Use it when the question is bigger than one feature and nothing above
  it is written down -- "should we build a plugin system at all?", "we have
  five things we could do next quarter, which ones and in what order?",
  "what's our story for the next year on X", "I need to pitch this to the
  team", or a request for a rollout order where nobody has said why the work
  matters, which otherwise produces a sequence with no bet behind it. Do NOT
  use it for one feature whose requirements need working out; that is
  `/scope`. `/vision`, `/strategy`, and `/roadmap` each run alone when you
  want only the thesis, only the bet, or only the sequence -- but reaching for
  one of them because a conversation "sounds strategic" usually lands you here
  instead.
argument-hint: '<topic-slug or freeform topic> [--upstream <path>]'
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh charter 2>&1 || true`

# Charter

`/charter` is the first parent skill in the shirabe parent-skill
pattern. It walks an author through the strategic chain
(VISION → STRATEGY → ROADMAP), holding state across child boundaries,
enforcing pattern-level invariants (state schema, resume ladder,
exit paths, child inspection), and producing a STRATEGY as the
durable terminal artifact.

A full run also produces a ROADMAP, which `/roadmap` writes on every
chain unless the author declines it (R7). STRATEGY is still the
*durable* terminal artifact even though `/roadmap` runs after
`/strategy`: the ROADMAP is a working artifact that drives work
rather than recording it, while the STRATEGY stays in
`docs/strategies/` as the audit trail. Both appear in
`exit_artifacts:`.

A working artifact is not a self-disposing one. `/roadmap`'s own
`## Artifact Lifecycle` section owns the completion condition, and
the cascade only retires a ROADMAP through a finished downstream
PLAN — a ROADMAP nobody plans against persists until someone
removes it.

The pattern-level contract surface is documented in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` and its
three companion references. `/charter` is the first concrete
consumer; the seven SKILL.md structural elements below align
section-by-section with the pattern's required structural elements.

## Team Shape

`/charter` runs as a single-agent skill in the v1 core layer — no
team is spawned. The parent-of-the-parent (the agent invoking the
skill) calls `/charter` directly; there are no peer roles to
materialize at team-creation time.

The team-shape declarator is prose per Decision 8's v1 form (see
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` — Team-
Shape Declarator section). When the amplifier-layer substrate ships,
team-emitting parents declare their roster as structured metadata;
single-agent parents like `/charter` keep the prose form.

See [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) Dispatch Contract section for the mechanism that carries each child invocation.

## Input Modes

From `$ARGUMENTS`:

Flags are parsed and removed first (see Execution-Mode Flags and
Upstream Flag below); the input modes classify what remains.

1. **Empty** — surface a cold-start prompt asking the author what
   strategic conversation they want to have. The cold-start prompt
   names the three trigger phrases from CLAUDE.md ("start a strategic
   conversation about X", "open a charter for Y", "I need to think
   through the bet on Z") and asks the author to re-invoke
   `/charter <topic-slug>` with a slug that matches the topic-slug
   regex. Phase 0 then stops; there is no auto-retry loop.
2. **Non-empty `$ARGUMENTS`** — treated as a freeform topic string
   that MUST already conform to the topic-slug regex. Phase 0
   validates `$ARGUMENTS` AS PROVIDED (byte-for-byte against the
   regex); on match, the value becomes the topic slug verbatim; on
   mismatch, Phase 0 rejects with a clear error naming the violated
   pattern and stops. No normalization, no derivation, no "best
   effort" massaging — the slug the author typed IS the slug Phase 0
   validates and records.

`/charter` MUST NOT accept paths to durable artifacts as an input
mode. A `$ARGUMENTS` value that looks like a path fails the regex
(slashes, dots, and any uppercase letters from typical artifact
prefixes break the match) and is rejected at Phase 0. Concrete
example: `/charter docs/visions/VISION-foo.md` is rejected at the
regex check (slashes, dots, and uppercase letters all violate
`^[a-z0-9-]+$`); it is NOT treated as a pointer to the VISION at
that path, and Phase 0 stops without creating any state file.

Path-as-upstream is the wrong shape for `/charter`'s entry mode.
An upstream the chain should consume is named with `--upstream
<path>` (below); an upstream the chain can find for itself is
detected during Phase 1 discovery by inspecting the topic-related
child docs that exist in the repo. Neither route parses a path out
of the positional slot.

## Execution-Mode Flags

`/charter` parses three execution-mode flags from `$ARGUMENTS`:

- `--auto` — non-interactive mode. Decisions follow the recommended
  default based on context; the run does not block on user input.
- `--interactive` (default) — the run blocks on user-input prompts at
  decision points.
- `--max-rounds=N` — caps the number of re-evaluation re-entries
  allowed against the same topic. Default is unbounded; setting `N`
  causes the (N+1)th re-evaluation to be rejected with a clear error
  naming the cap.

The execution mode applies to all phases. `--auto` mode does not
suppress R9's hard-finalization check; an `--auto` run that cannot
record a valid exit still fails finalization rather than silently
absorbing the violation.

## Upstream Flag

`/charter` accepts `--upstream <path>`, naming an existing VISION
this chain consumes rather than produces. It is the same flag token,
with the same meaning, that `/prd`, `/roadmap`, and `/comp` already
carry, that `/scope` carries on the tactical side, and that
`/charter` itself already EMITS when it invokes `/roadmap`.

The flag is parsed at Phase 0 alongside the execution-mode flags,
BEFORE the positional slug is read. The token following it is
consumed as the flag's argument and is never tested against the
topic-slug regex, which is what leaves the positional contract
untouched: a path in the positional slot is still rejected.
`--upstream` with no value is a Phase 0 rejection naming the
missing argument, and it stops before any state file is written.

A supplied upstream is validated inbound — canonicalized and
bounds-checked, its basename required to start with `VISION-`, and
run through three ordered checks (not under `wip/`, tracked by git,
and not a private artifact named from a public repo). It is then
recorded in the state file's conditional `consumed_upstream:`
field, re-validated on every resume, and handed to `/strategy` as
`/strategy <topic-slug> --upstream <path>` — the slug stays the
parent's, the upstream travels separately.

An author who supplies no upstream is told the flag exists before a
VISION is written for them. The chain proposal carries a fixed,
non-blocking notice with the `/vision` run entry, naming no
candidate and scanning no directory; its verbatim wording and its
two firing conditions are in
`skills/charter/references/phases/phase-1-discovery.md` under The
Pre-Authoring Upstream Notice.

Basename enforcement is deliberately inbound-only: the `--upstream`
`/charter` emits to `/roadmap` carries no such check, because there
the parent is handing over an artifact it just watched a child
produce. Inbound it is routing on a string the author typed, and a
wrong type silently mis-frames the chain head. The full procedure
is `skills/charter/references/phases/phase-0-setup.md` steps 0.1
and 0.4.

## Topic-Slug Constraint

The topic slug appears in the state-file path
(`wip/charter_<topic>_state.md`), the terminal artifact filename
(`docs/strategies/STRATEGY-<topic>.md`), and downstream child wip/
paths. The slug MUST match the regex `^[a-z0-9-]+$` — the
pattern-level constraint canonical in
[`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md)
(Topic-Slug Regex section), including the validation discipline
(AS PROVIDED, no normalization) and the resume-time re-validation
rule. Phase 0's slug-handling procedure lives at
`skills/charter/references/phases/phase-0-setup.md`.

## Workflow Phases

```
Phase 0: SETUP --> Phase 1: DISCOVER --> Phase 2: CHAIN --> Phase N: FINALIZE
(slug validation +  (visibility detect +   (orchestrate     (record exit +
 state-file create)  chain proposal)        child skills)    write artifacts)
```

| Phase | Purpose | Reference |
|-------|---------|-----------|
| 0. Setup | Slug validation, state-file creation | `skills/charter/references/phases/phase-0-setup.md` |
| 1. Discover | Repository visibility detection, topic-related child-doc discovery, chain proposal | `skills/charter/references/phases/phase-1-discovery.md` |
| 2. Chain | Sequenced child-skill invocations (`/vision`, `/strategy`, `/roadmap`) | `skills/charter/references/phases/phase-2-chain-orchestration.md` |
| N. Finalize | Record exit path, write `exit_artifacts:`, run R9 hard-finalization check | `skills/charter/references/phases/phase-finalization.md` |

The per-phase bodies are authored by downstream issues in the
PLAN-shirabe-charter-skill plan. This section is the diagram and
phase-list shape; downstream phase files plug in here.

Phase 2 chain orchestration runs each child invocation (`/vision`,
`/strategy`, `/roadmap`) as a dispatch under the Team-Lead Operating
Discipline documented in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` (invariant
I-7). The discipline binds the sleep-check-nudge loop, the
filesystem-evidence-first priority ordering, and the PASS / FAIL /
ESCALATE terminal exits; the implementation-pass task class (120s
window / 10-cycle patience budget) applies to each child invocation.

## Resume Logic

`/charter` maintains state at `wip/charter_<topic>_state.md` (one
file per topic, keyed by the topic slug). The full state-file
schema, conditional-field gating discipline, and R9 hard
finalization check spec are documented in
`skills/charter/references/phases/phase-state-management.md`. On
re-entry, the resume ladder consults the state file, the per-child
snapshots recorded in state, and the current branch context to
decide where to re-enter.

The ladder shape follows the universal meta-ladder template at
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`:
universal rows 1-4 (malformed → exit set → fresh resume → stale-
session) and rows 9-10 (on-topic branch → main fallback) are the
pattern-level meta-ladder; rows 5-8.5 are parent-specific body slots
`/charter` fills against its child set (`/vision`, `/strategy`,
`/roadmap`). Slot 5 (status-aware re-entry) expands into rows 5-6
for Accepted/Active vs Draft STRATEGY; slot 6 (partial-child-run)
expands into rows 7-8 for `/strategy` vs `/vision`; slot 7
(feeder-doc-detected) is row 8.5, matching the `/explore` handoff at
`wip/charter_<topic>_handoff.md`. The fractional number keeps rows 9
and 10 — the shared meta-ladder tail `/scope` uses too — at their
existing ordinals; the template licenses a body slot to expand this
way.

Because `/roadmap` runs on every full-run chain, an interrupted
chain commonly leaves a Draft STRATEGY on disk with `/roadmap`
still in flight. Row 6 carries the mid-roadmap disambiguation:
"Continue draft" resumes into `/roadmap` when the handoff file
`wip/roadmap_<topic>_scope.md` exists and no published ROADMAP
does, and into `/strategy` otherwise.

`/charter`'s stale-session threshold is 7 days: state with
`last_updated` ≥ 7 days old surfaces the Resume / Force-materialize
/ Discard prompt; fresher state silently resumes.

The ladder body (rows 1 through 10, row 8.5 included, with the
prompt vocabulary for each row,
dual-check drift detection, status-aware re-entry suppression, and
R14 child-internals isolation discipline) lives in
`skills/charter/references/phases/phase-resume.md`.

## Phase Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup** — slug validation, state-file creation.
   - Instructions: `skills/charter/references/phases/phase-0-setup.md`

1. **Discover** — repository visibility detection, topic-related
   child-doc discovery, chain-proposal output.
   - Instructions: `skills/charter/references/phases/phase-1-discovery.md`

2. **Chain orchestration** — invoke the planned chain
   (`/vision` → `/strategy` → `/roadmap`, skipping per the chain
   plan), surface the roadmap confirmation prompt before
   `/roadmap` fires — reading the Draft STRATEGY first and stating
   what that reading says about whether the strategy is headed for
   execution, with proceed as the default either way — inspect
   child durable artifacts after each step per the widened R14
   rule, advance the `phase_pointer` after each child completes.
   - Instructions: `skills/charter/references/phases/phase-2-chain-orchestration.md`

N. **Finalization** — set the `exit:` field to one of `full-run`,
   `re-evaluation`, or `abandonment-forced`; write the
   `exit_artifacts:` list; run the R9 hard-finalization check.
   - Instructions: `skills/charter/references/phases/phase-finalization.md`

## Reference Files

| File | When to load |
|------|-------------|
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` | All phases — contract surface, invariants, exit paths, Gate Vocabulary (Mandatory-with-auto-skip plus thesis-shift override on `/vision`; ALWAYS on `/strategy` and `/roadmap`), substitution surfaces |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md` | Phase 0 (slug regex), Phase 2 (state writes), Phase N (R9 check) |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md` | Resume Logic — meta-ladder rows 1-4 and 9-10 |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md` | Phase 2 — child-doc inspection (R14 widened rule, dual-check drift detection) |
| `${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md` | Phase 2 — per-child worktree-staleness check (Rebase / Proceed anyway / Bail prompt, divergence recording) |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md` | All phases — six pattern-level security contract surfaces (slug re-validation, closed write-target set, enum re-validation, self-heal, visibility, no-untrusted-input-interpolation) |
| `skills/charter/references/phases/phase-0-setup.md` | Phase 0 |
| `skills/charter/references/phases/phase-1-discovery.md` | Phase 1 |
| `skills/charter/references/phases/phase-2-chain-orchestration.md` | Phase 2 |
| `skills/charter/references/phases/phase-state-management.md` | All phases — state-file schema, conditional-field gating, R9 hard finalization check spec |
| `skills/charter/references/phases/phase-resume.md` | All phases — 10-row resume ladder, dual-check drift detection, R14 child-internals isolation |
| `skills/charter/references/phases/phase-finalization.md` | Phase N |

## Security Considerations

`/charter`'s security envelope binds the six pattern-level contract
surfaces enumerated in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md` — slug
re-validation on resume, closed write-target set, state-file enum
re-validation, stale `parent_orchestration:` self-heal, visibility
boundary, and no untrusted-input interpolation. Two of the six need
`/charter`-specific statements, because `--upstream` is the first
author-supplied value this skill accepts that is not derived from a
validated slug.

**Interpolation discipline.** The pattern reference binds parents
to a metadata-read surface and requires that a parent adding direct
author-input handling re-state the interpolation contract
explicitly rather than silently broaden the surface. Stated in this
repository's own terms: the `--upstream` value is canonicalized to
an absolute path and rejected if it resolves outside the working
tree, then quoted and passed after `--` in every command
`/charter` emits with it (`git ls-files -- <path>`) and in the
`/strategy <topic-slug> --upstream <path>` invocation it feeds. So
neither a leading dash nor a shell metacharacter in a filename can
change what runs. Validation alone is not the guarantee — the
argument boundary is. The same discipline binds the re-validation
the resume ladder performs against `consumed_upstream:`, which is a
second interpolation site rather than a repeat of the first (see
`skills/charter/references/phases/phase-resume.md`).

**The flag's value reaches a committed field.** Nothing about a
flag suggests its value ends up in a committed file, and this one
does: `/strategy` writes it into the produced STRATEGY's
`upstream:` frontmatter, and that document is committed. Public
documents must not reference private ones, and no tooling enforces
that rule for a cross-repo value — `shirabe validate`'s resolution
check returns nothing for one, so a public STRATEGY carrying a
private cross-repo upstream validates clean and always will. The
three ordered checks in
`skills/charter/references/phases/phase-0-setup.md` step 0.4 are
where that gap is closed: reject a path into the non-durable `wip/`
directory, confirm the target is tracked by git, and — when this
repo is Public and the upstream is private — stop and omit the
field rather than write it. Cross-repo values are accepted rather
than rejected outright, which is what makes the third check
mandatory rather than advisory: rejecting them would be safe and
would also make the flag unable to express the one case that
motivates it, since the strategic corpus commonly lives outside the
repo the chain runs in.

**Closed write-target set.** `/charter` writes to exactly six
places: the state file at `wip/charter_<topic>_state.md`, the
`/roadmap` handoff at `wip/roadmap_<topic>_scope.md`, Decision
Records under `docs/decisions/`, the force-materialized partial
artifact its abandonment path produces under `docs/strategies/`
(plus the `git rm` of a rejected Draft at the same path), the
removal of the `/explore` handoff at
`wip/charter_<topic>_handoff.md` once a run has consumed it, and the
`wip/` cleanup its finalization performs. Every one of those paths
is composed from the validated topic slug, never from
author-supplied text. The `/explore` handoff is a read target that
becomes a delete target, and it is named here for the same reason
the rest are: the set is a closed list of concrete paths, so a path
`/charter` touches and the list omits is outside the set. The `--upstream` value does not widen the
set: it is a read target only — validated, recorded, handed to a
child — and is never written to.
