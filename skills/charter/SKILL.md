---
name: charter
description: >-
  Parent skill for the strategic chain. Walks an author through
  VISION → STRATEGY → ROADMAP as a single conversation, holding state
  across child boundaries and producing a STRATEGY as the terminal
  artifact. Use when an author needs strategic framing decided in one
  sitting rather than reached for one child skill at a time. Triggers
  on "start a strategic conversation about X", "open a charter for
  Y", "I need to think through the bet on Z", or direct
  `/charter <topic>` invocations. Do NOT use when the author already
  knows which artifact altitude they want (reach for `/vision`,
  `/strategy`, or `/roadmap` directly).
argument-hint: '<topic-slug or freeform topic>'
---

# Charter

`/charter` is the first parent skill in the shirabe parent-skill
pattern. It walks an author through the strategic chain
(VISION → STRATEGY → ROADMAP), holding state across child boundaries,
enforcing pattern-level invariants (state schema, resume ladder,
exit paths, child inspection), and producing a STRATEGY as the
terminal artifact.

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

Path-as-upstream is the wrong shape for `/charter`'s entry mode —
upstream artifact references are detected during Phase 1 discovery
by inspecting the topic-related child docs that exist in the repo,
not by parsing them out of `$ARGUMENTS`.

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
pattern-level meta-ladder; rows 5-8 are parent-specific body slots
`/charter` fills against its child set (`/vision`, `/strategy`,
`/roadmap`). Slot 5 (status-aware re-entry) expands into rows 5-6
for Accepted/Active vs Draft STRATEGY; slot 6 (partial-child-run)
expands into rows 7-8 for `/strategy` vs `/vision`; slot 7
(feeder-doc-detected) is unfilled because `/charter` has no
feeder-doc case.

`/charter`'s stale-session threshold is 7 days: state with
`last_updated` ≥ 7 days old surfaces the Resume / Force-materialize
/ Discard prompt; fresher state silently resumes.

The ladder body (rows 1-10 with the prompt vocabulary for each row,
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
   plan), inspect child durable artifacts after each step per the
   widened R14 rule, advance the `phase_pointer` after each child
   completes.
   - Instructions: `skills/charter/references/phases/phase-2-chain-orchestration.md`

N. **Finalization** — set the `exit:` field to one of `full-run`,
   `re-evaluation`, or `abandonment-forced`; write the
   `exit_artifacts:` list; run the R9 hard-finalization check.
   - Instructions: `skills/charter/references/phases/phase-finalization.md`

## Reference Files

| File | When to load |
|------|-------------|
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` | All phases — contract surface, invariants, exit paths, substitution surfaces |
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
