# Lead

How does the parent-skill pattern v1 shape a parent skill's REQUIREMENTS, so the
PRD's requirements align with the pattern? Using `/charter` and `/scope` as
precedent, this note extracts the pattern-conformance surface every parent SHALL
bind, then maps it onto `/execute` — a parent that (a) operates at
implementation altitude rather than authoring altitude, (b) delegates to
`/work-on` (a koto-driven child) rather than to authoring children, and (c)
consumes an on-PR coordination DAG as its substrate rather than wip-yaml.

Sources (all in worktree `shirabe-execute-skill`):
- `references/parent-skill-pattern.md`
- `references/parent-skill-state-schema.md`
- `references/parent-skill-resume-ladder-template.md`
- `references/parent-skill-child-inspection.md`
- `references/parent-skill-security.md`
- `skills/charter/SKILL.md`, `skills/scope/SKILL.md`

# Findings

## 1. The seven required SKILL.md structural elements

`references/parent-skill-pattern.md` (Required SKILL.md Structural Elements,
lines 474-506) names seven elements every parent's `skills/<name>/SKILL.md`
SHALL contain. The list is pattern-level; the content slotted in is
parent-specific. Both precedents align section-by-section:

1. **Input Modes** — parent-specific input shapes (topic-slug argument,
   optional flags, optional named files). `/scope` SKILL.md lines 68-92,
   `/charter` lines 47-79: empty → cold-start prompt naming trigger phrases;
   non-empty → validate `$ARGUMENTS` AS PROVIDED against the regex; paths to
   durable artifacts are REJECTED (slashes/dots/uppercase break the regex),
   never treated as upstream pointers.
2. **Execution-mode flag parsing** — `--auto` / `--interactive`,
   `--max-rounds=N`, plus any parent-specific flags. `/scope` lines 94-112
   (default `--max-rounds=5`), `/charter` lines 81-97 (default unbounded). Both
   state that `--auto` does NOT suppress R9 hard-finalization.
3. **Topic-slug constraint** statement citing the schema reference for regex
   `^[a-z0-9-]+$`. `/scope` lines 178-197, `/charter` lines 99-110.
4. **Workflow Phases** diagram — readable phase ordering. `/scope` lines
   199-235 (Setup→Discover→Chain→Finalize→Cleanup), `/charter` lines 112-138
   (Setup→Discover→Chain→Finalize).
5. **Resume Logic** ladder — body slots filled per chain shape, meta-ladder
   rows cited from the resume-ladder template. `/scope` lines 236-272,
   `/charter` lines 140-170.
6. **Phase Execution** list — one phase reference per phase, pointing at
   `skills/<name>/references/phases/<phase>.md`. `/scope` 274-309, `/charter`
   172-193.
7. **Reference Files** table — the four pattern-level references plus
   parent-specific ones. `/scope` 311-327, `/charter` 195-210.

Parents add sections beyond the seven (e.g. `/scope`'s Coordination Intent,
Chain-Proposal Output, Three Exit Paths, Validator Pass-Through); the seven are
the floor. The pattern also flags (lines 501-506) that default-option wording
at status-aware re-entry prompts is **contract surface, not UX detail** — each
parent SHALL specify it as literal-substring ACs so the eval surface can
grep-check the prompt vocabulary.

**Becomes PRD requirements:** every one of the seven is a structural-conformance
requirement for `/execute`'s SKILL.md. The PRD must require all seven present
and must require the literal-substring prompt vocabulary for `/execute`'s
re-entry / proposal prompts (so the eval surface can grade them).

## 2. State schema (5-field minimum + conditional fields + substitution surface)

`references/parent-skill-state-schema.md` (Minimum Required Fields, lines 16-37)
names the **5-field minimum** every parent's state file SHALL carry:

- `topic` — string matching `^[a-z0-9-]+$`; the state's key (invariant I-4).
- `last_updated` — ISO-8601, written on every modification; drives the
  resume-ladder stale-session check.
- `phase_pointer` — parent-phase enum string; consumed by resume.
- `exit` — enum from `{full-run, re-evaluation, abandonment-forced}`; UNSET
  in-progress, SET at finalization; R9 fires if unset/invalid at termination.
- `exit_artifacts` — list of `{path, status}` entries for durable files
  produced.

**Conditional fields** (lines 70-101) gated by invariant I-5 (absent when
ungated — never null/empty/placeholder): `boundary:` (gated on
`exit: re-evaluation`, values `prd|design`), `plan_execution_mode:` (gated on
`/plan` in `chain_ran`, values `single-pr|multi-pr`). Plus the chain-tracking
triad `planned_chain` / `chain_ran` / `chain_skipped` (lines 137-163) which
travel as a unit — a chain-shaped parent uses all three or none. The schema
also enforces four invariants (lines 102-194): per-child snapshot dual-check
(`{status, content_hash, commit_sha}`), conditional-field gating (I-5),
chain-tracking, status-aware re-entry control via the `parent_orchestration:`
block. R9 hard-finalization (lines 215-255) has three parts: exit valid,
sub-shape valid when applicable, conditional fields absent when ungated.

**Substitution surface** (`parent-skill-pattern.md` lines 209-248). Two named
variables, each with a fixed v1 value and a stable name:

- **`storage_substrate`** — v1 value `wip-yaml-md` (state at
  `wip/<parent>_<topic>_state.md`, YAML body in a `.md` file). Does NOT satisfy
  I-6 (cross-branch resume); alternate values are the amplifier-layer mandate.
- **`team_primitive`** — v1 value `single-team-per-leader-no-nested` (single
  team per leader, no nested teams, no sub-agent spawning sub-agents; three
  consequences: inline-decision walks, file-handoff between parents, upfront
  upper-bound roster).

Both precedents bind both variables explicitly: `/scope` Binding Notes lines
588-609, `/charter` inherits them in prose. The substitution variable (not its
v1 value) is the freeze line — this is exactly where `/execute` diverges (see
section 6).

**Becomes PRD requirements:** `/execute` SHALL carry the 5-field minimum; SHALL
declare its conditional fields (its own exit-discriminators, chain-membership
gating); SHALL satisfy R9 three-part; SHALL declare its `storage_substrate` and
`team_primitive` bindings in a Binding Notes section. The dual-check fingerprint
binding is parent-specific for non-doc children (the per-parent surface table)
— load-bearing for `/execute` (section 5 and 6).

## 3. Resume ladder (meta-ladder rows + parent-specific body slots)

`references/parent-skill-resume-ladder-template.md` (Ladder Shape, lines 17-35)
fixes a 9-row, first-match-wins ladder. Rows 1-4 and 8-9 are the **meta-ladder**
(pattern-level fixed):

1. state file malformed → Error + offer Discard (hard surface, no silent
   fall-through; lines 38-48, 170-189).
2. state file has exit set → offer revise-equivalent / start fresh.
3. state fresh (`last_updated` < threshold) → resume at `phase_pointer`, no
   prompt.
4. state stale (`last_updated` >= threshold) → offer Resume / Force-materialize
   / Discard.
8. on-topic branch → resume at parent Phase 1.
9. main/unrelated branch → start at parent Phase 0.

Rows 5-7 are **parent-specific body slots**:

- **Slot 5 — status-aware re-entry** (lines 105-137): parent decides upfront
  whether re-entry is parent-resume or fresh chain; typically a
  **Re-evaluate / Revise / Bail** triad against an Accepted upstream. Special
  case: when the terminal artifact has lifecycle states OWNED BY a downstream
  skill (e.g. `/scope`'s PLAN has an Active state owned by `/work-on`, a Done
  state owned by `/release`), the Slot 5 entry SHALL **refuse re-entry and emit
  a redirect** containing the literal substring `redirect to /<skill-name>` and
  SHALL NOT contain the Re-evaluate/Revise/Bail triad. **This is directly
  relevant to `/execute`** — `/execute` sits exactly at the boundary `/scope`
  redirects TO.
- **Slot 6 — partial-child-run** (lines 139-153): resume into the partial child
  rather than re-running from scratch.
- **Slot 7 — feeder-doc-detected** (lines 154-168): parent-specific Phase 1
  entry behavior. Vacuous in both `/scope` and `/charter`.

Stale-session threshold is parametric (lines 192-209); both precedents pick
7 days.

**Becomes PRD requirements:** `/execute` SHALL implement the 9-row meta-ladder
with the same fixed rows; SHALL fill Slots 5-7 against its own child set
(`/work-on`); SHALL pick a stale-session threshold (likely longer than 7 days,
since execution spans CI/PR cycles — agent judgment). The malformed-state hard
surface and slug re-validation on resume are mandatory.

## 4. Three exit paths and how they map to an EXECUTION chain

`references/parent-skill-pattern.md` (Three Exit Paths, lines 79-111). Three
stable names:

- **full-run** — chain reaches its terminal artifact; `exit: full-run`;
  `exit_artifacts:` lists produced files.
- **re-evaluation** — re-entry on a topic with an existing terminal artifact
  concludes WITHOUT re-authoring; writes a Decision Record; `exit:
  re-evaluation`.
- **abandonment-forced** — chain cannot complete; force-materializes a
  schema-compliant partial; records `exit: abandonment-forced` + triggering
  child + phase reached.

The contract operationalizes the discipline-vs-artifact decoupling thesis: a
disciplined conversation always has a durable home even when production is the
wrong outcome.

**Mapping to `/execute` (execution, not authoring).** The three names are
stable across parents, but their *bindings* must be re-shaped for execution
because the terminal artifact of an execution chain is not an authored `docs/`
doc — it is **merged code / a completed PR coordination DAG**, plus the
state-of-the-plan (issues closed, milestone complete). Candidate bindings:

- **full-run** — the plan executes to completion: every constituent
  issue/`/work-on` run reaches a merged-and-green PR, the coordination DAG
  reaches its merge-last node, and `/execute` records `exit: full-run` with
  `exit_artifacts:` pointing at the merged PRs / closed milestone (the durable
  "externally-visible status surface" for PR-shaped children, per child
  inspection). The PLAN doc's lifecycle flips Active → Done.
- **re-evaluation** — a re-entry against a PLAN that is already executed
  (Done) or partially executed where the author concludes no further execution
  is warranted: `/execute` records the disciplined judgment in a Decision
  Record WITHOUT re-running `/work-on`. This is the execution analog of
  "disciplined without re-producing."
- **abandonment-forced** — the plan cannot complete (a `/work-on` child
  ESCALATEs, CI cannot be made green, a coordination node is blocked):
  `/execute` force-materializes the partial state — the in-flight PR is left in
  a schema-compliant partial-marker state, the coordination DAG records the
  abandonment, `triggering_child:` names the `/work-on` run, and the partial
  phase is recorded. (Mirrors `/scope`'s Coordinated Abandonment R20, SKILL.md
  lines 545-569: abandonment closes the coordination PR unmerged and documents
  partial state rather than orphaning it.)

The exit shapes that "make sense" for execution: full-run and
abandonment-forced are the load-bearing pair (execution either completes or is
forced to stop with a durable partial). re-evaluation is the lighter path — it
mostly fires when `/execute` is re-invoked against an already-terminal plan and
the author wants a recorded judgment rather than a re-run. The
`storage_substrate` shift (section 6) changes WHERE these exits are recorded
(on the PR DAG, not just wip-yaml), but not their NAMES — the names are the
freeze line.

## 5. Child inspection (R14 metadata-only) + the six security surfaces

**R14 widened isolation** (`references/parent-skill-child-inspection.md`).
A parent SHALL read only the child's *durable externally-visible status
surface*; never internals (lines 24-52). The per-parent surface table
(lines 54-80) has two rows:

| Child shape | Status surface |
|---|---|
| doc-emitting | frontmatter `status:` + git blob hash (content fingerprint) |
| issue or PR (no doc) | issue/PR state + labels + CI check rollup |

**This second row is the one `/execute` binds** — `/work-on` produces a PR, not
a `docs/` doc. The dual/multi-check (lines 82-101): drift fires when state
flipped OR label set differs OR CI check rollup differs. CI check rollup is the
externally-visible terminal verdict; individual check logs are internals
(lines 132-156). Manual-fallback non-interference (lines 110-130): a `/work-on`
invoked directly outside `/execute` leaves the same externally-visible surface,
so the resume ladder inspects identical signals regardless of invocation path.

**Six security surfaces** (`references/parent-skill-security.md`), all bound by
both precedents (`/scope` Security Considerations lines 571-586):

1. **Slug re-validation on resume** (lines 20-40) — recovered slug re-validated
   against `^[a-z0-9-]+$` BEFORE interpolation into any shell command / write
   path; closes path-traversal.
2. **Closed write-target set** (lines 42-65) — writes confined to an enumerated
   set declared in SKILL.md; writes outside fail R9.
3. **State-file enum re-validation** (lines 68-86) — every enum-typed field
   re-validated against its enum on resume before constructing write paths /
   shell commands; closes state-file tampering.
4. **Stale `parent_orchestration:` self-heal** (lines 88-108) — Phase 0
   unconditionally clears any `parent_orchestration:` block found at session
   start; no prompt, no warning.
5. **Visibility boundary** (lines 110-123) — declare repo-visibility set in
   SKILL.md; cross-visibility extension re-states placement discipline with
   governance review.
6. **No untrusted-input interpolation** (lines 125-146) — parent prose MUST NOT
   interpolate author-supplied content into `-m "<string>"` shell args; the
   parent consumes only metadata reads (frontmatter `status:`, git blob hashes,
   discard-commit metadata via `git log`). For `/execute` the metadata-read
   surface is PR state + labels + CI rollup — still metadata-only, no untrusted
   interpolation.

**Becomes PRD requirements:** `/execute` SHALL bind R14 to the issue/PR surface
row (PR state + labels + CI rollup; logs are internals), SHALL define its
dual/multi-check drift on those fields, and SHALL bind all six security
surfaces — with the closed write-target set re-shaped for an execution chain
(see section 6: the write targets include the on-PR DAG and PLAN lifecycle
flip, not new `docs/` authoring).

## 6. KEY: how the execution chain fits/stretches the pattern

`/execute` delegates to `/work-on` (koto-driven) and consumes an **on-PR
coordination DAG** as its substrate (not wip-yaml). Three structural shifts,
each with a requirement implication.

**(a) `storage_substrate` = on-PR DAG, not `wip-yaml-md`.** The pattern names
`storage_substrate` as a substitution variable whose *v1 value* is `wip-yaml-md`
but whose *variable* is the freeze line (pattern lines 209-226; "the variable
itself is the freeze line, not the v1 value"). `/execute` is the first parent to
bind a non-`wip-yaml-md` value: the coordination DAG persisted on the PR. The
pattern explicitly anticipates "context-store-backed persistence" as an
alternate; an on-PR DAG is in the same family (durable, externally-visible,
survives across branches). Notably this binding may **satisfy I-6 (cross-branch
resume)** that `wip-yaml-md` cannot — the on-PR DAG lives on the PR, not on a
feature branch, so resume from a different branch can recover it. This is a
genuine stretch: the pattern frames I-6 as the amplifier-layer mandate
(lines 68-76), and `/execute` may be the first parent to close part of that gap
at the substrate level. **Requirement implication:** the PRD SHALL declare
`storage_substrate: <on-PR-DAG identifier>` in Binding Notes, SHALL re-state how
the 5-field minimum + conditional fields serialize onto the DAG (the schema is
substrate-bound, lines 9-14), and SHALL state explicitly whether/how it
satisfies I-6 (the pattern requires honesty about which invariants a binding
satisfies — I-6 is "load-bearing as an unsatisfied invariant," so claiming to
satisfy it is a contract statement, not an aside).

**(b) child = `/work-on`, an issue/PR-shaped (non-doc) child.** `/work-on`
emits a PR, not a `docs/` doc, so `/execute` binds the **issue-or-PR row** of
the child-inspection surface table (PR state + labels + CI rollup), not the
doc-emitting row. The dual-check fingerprint for `/work-on` is parent-specific
(schema lines 109-117: "for non-doc children the fingerprint binding is
parent-specific") — candidate: the PR head SHA + CI rollup. The Team-Lead
Operating Discipline (pattern lines 508-647) is directly load-bearing here:
`/work-on` runs include CI waits, so `/execute` binds the **External wait (CI,
network)** task class (60s window, unlimited patience) AND the
`ci_outcome` semantics (`passing` vs `failing_fixed`, lines 619-636) — the first
parent for which `ci_outcome` is central rather than incidental, because
execution IS driving PRs to green. **Requirement implication:** the PRD SHALL
add a child-inspection surface-table row binding for `/work-on` (if not already
the issue/PR row), SHALL define the non-doc fingerprint, SHALL bind the External
wait task class and `ci_outcome` tracking, and SHALL bind the Active
Orchestration invariant I-7 (the team-lead actively polls PR/CI evidence under
the sleep-check-nudge loop and never passively waits while a `/work-on` is in
flight).

**(c) `/execute` IS the downstream-owning skill `/scope` redirects to.** The
resume-ladder Slot 5 special case (template lines 125-137) says a parent whose
terminal artifact has a downstream-owned lifecycle state SHALL refuse re-entry
and `redirect to /<skill-name>`. `/scope`'s PLAN has an **Active state owned by
`/work-on`** (and `/execute` orchestrates `/work-on` over a whole plan). So
`/execute` is the OWNER of the PLAN-Active lifecycle state — the consumer of
`/scope`'s redirect. **Requirement implication:** the PRD SHALL state that
`/execute` accepts a PLAN doc (likely at `docs/plans/PLAN-<topic>.md`, status
Active or ready-to-activate) as its input and OWNS the Active→Done lifecycle
transition; its own Slot 5 governs re-entry against an in-flight or
already-executed plan. This makes `/execute`'s **input mode** asymmetric to
`/charter`/`/scope`: those reject path inputs and detect upstream during Phase 1
discovery, but `/execute`'s natural input is "a plan to execute" — the PRD must
resolve whether `/execute` takes a topic-slug (then discovers the PLAN) or a
PLAN path (then validates the path-derived slug against the regex per the
security surface). Topic-slug-with-discovery keeps it pattern-aligned; a PLAN
path would be a documented input-mode divergence requiring its own justification
and slug-re-validation discipline.

**Net:** `/execute` conforms to the pattern's semantic invariants (I-1..I-7),
the seven structural elements, the three exit NAMES, R14 isolation, R9
hard-finalization, and the six security surfaces — but it exercises the
substitution surface (`storage_substrate`) and the non-doc child-inspection row
harder than any prior parent, and it may be the first to satisfy I-6. That is
*using* the pattern's designed flexibility, not breaking it: the pattern was
built two-layer precisely so a new parent can re-bind substrate and child shape
while holding the Layer-1 invariants frozen.

# PRD requirement candidates (the pattern-conformance requirements)

These are the requirements `/execute`'s PRD SHALL carry to conform to the
parent-skill pattern. Each cites where the pattern mandates it.

- **PC-1 — Seven structural elements.** `/execute`'s SKILL.md SHALL contain all
  seven (Input Modes, execution-mode flags, topic-slug constraint, Workflow
  Phases diagram, Resume Logic ladder, Phase Execution list, Reference Files
  table). [pattern 474-506]
- **PC-2 — Literal-substring prompt vocabulary.** Status-aware re-entry and
  chain-proposal prompts SHALL specify their option vocabulary as
  literal-substring ACs (e.g. Re-evaluate/Revise/Bail, or the
  `redirect to /<skill>` substring for downstream-owned states) so the eval
  surface can grep-check. [pattern 501-506; resume-ladder 125-137]
- **PC-3 — Five-field minimum state.** State SHALL carry `topic`,
  `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`. [schema 16-37]
- **PC-4 — Conditional fields satisfy I-5.** All exit-/chain-gated fields ABSENT
  when ungated (never null/empty/placeholder); chain-tracking triad travels as a
  unit. [schema 102-163, 196-213]
- **PC-5 — R9 hard-finalization (three parts).** exit valid; sub-shape valid
  when applicable; conditional fields absent when ungated; `--auto` does NOT
  suppress it. [schema 215-255]
- **PC-6 — Per-child snapshot dual/multi-check.** Capture child's durable
  status AND content fingerprint; drift fires when EITHER changes. For
  `/work-on` (non-doc) the fingerprint binding is parent-specific (candidate: PR
  head SHA + CI rollup). [schema 109-122; child-inspection 82-101]
- **PC-7 — 9-row resume ladder.** Meta-ladder rows 1-4, 8-9 fixed; Slots 5-7
  filled against `/work-on`; malformed-state is a hard surface (Discard, no
  silent fall-through); pick a stale-session threshold. [resume-ladder 17-209]
- **PC-8 — Three exit paths, execution-bound.** Bind full-run (plan executed:
  merged PRs / Done milestone, PLAN Active→Done), re-evaluation (recorded
  judgment without re-running `/work-on`), abandonment-forced (force-materialize
  partial PR/DAG state + `triggering_child` + phase reached). Names are the
  freeze line. [pattern 79-111]
- **PC-9 — R14 issue/PR isolation.** Read only PR state + labels + CI rollup;
  CI logs, comment threads, child wip/, `/work-on` internal state are off-limits.
  [child-inspection 24-156]
- **PC-10 — Six security surfaces.** Slug re-validation on resume, closed
  write-target set (re-shaped for execution: PLAN lifecycle flip + on-PR DAG
  writes, not new `docs/` authoring), enum re-validation, stale
  `parent_orchestration:` self-heal, visibility boundary, no untrusted-input
  interpolation. [security all]
- **PC-11 — Active Orchestration (I-7) + Team-Lead Discipline.** The team-lead
  actively polls PR/CI evidence under the sleep-check-nudge loop; bind the
  External wait task class (60s/unlimited) and `ci_outcome` (`passing` vs
  `failing_fixed`); each `/work-on` dispatch drives to PASS/FAIL/ESCALATE.
  [pattern 508-647]
- **PC-12 — Binding Notes declaring both substitution variables.**
  `storage_substrate: <on-PR-DAG>` (and an explicit statement on I-6
  satisfaction) and `team_primitive` binding. [pattern 209-248; schema 9-14]
- **PC-13 — Dispatch / hand-back contract.** Write `parent_orchestration:`
  sentinel pre-dispatch, capture `pre_invocation_sha`, run hand-back steps
  (R20 existence check via PR presence, status read via PR state, fingerprint
  capture, discard-commit detection, validator pass-through, sentinel cleanup,
  child snapshot). [pattern 301-472]
- **PC-14 — Topic-slug regex + input mode.** Bind `^[a-z0-9-]+$`; resolve
  whether input is topic-slug (discover PLAN in Phase 1, pattern-aligned) or
  PLAN path (documented divergence requiring slug-re-validation). [schema
  257-263; pattern 480-489; security 20-40]

# How execution-chain differs from authoring-chain

| Dimension | Authoring (`/charter`, `/scope`) | Execution (`/execute`) |
|---|---|---|
| Children | authoring skills (`/brief`,`/prd`,`/design`,`/plan`; `/vision`,`/strategy`,`/roadmap`) | `/work-on` (koto-driven), one per issue/plan-segment |
| Child status surface | doc frontmatter `status:` + git blob hash | PR state + labels + CI check rollup |
| Terminal artifact | a `docs/<type>/<TYPE>-<topic>.md` authored doc | merged PRs / completed coordination DAG / PLAN Active→Done |
| `storage_substrate` | `wip-yaml-md` (no I-6) | on-PR coordination DAG (may satisfy I-6) |
| Dominant exit pair | full-run (produce doc) vs re-evaluation | full-run (plan executed) vs abandonment-forced (forced stop) |
| CI relevance | incidental | central — `ci_outcome` + External-wait task class are load-bearing |
| Position vs PLAN-Active | `/scope` REDIRECTS to the owner | `/execute` IS the owner of PLAN-Active→Done |
| Input mode | topic-slug; reject paths; discover upstream Phase 1 | topic-slug-or-PLAN; `/execute` consumes a plan as its driving input |
| Author-supplied content | rejection rationale committed by child via stdin | same discipline; `/execute` reads only PR/CI metadata |

The pattern absorbs all of these through its designed flexibility: the
substitution surface re-binds the substrate, the per-parent surface table
re-binds the child shape, the three exit NAMES stay frozen while their bindings
re-shape, and the Team-Lead Discipline already names the External-wait task
class and `ci_outcome` semantics that execution makes central. `/execute` is the
pattern's first non-authoring, non-`wip-yaml`, PR-shaped-child consumer — a
stress test of the freeze line, not a violation of it.

# Summary

The parent-skill pattern v1 hands `/execute`'s PRD a fixed conformance floor:
the seven SKILL.md structural elements, the 5-field state minimum plus
I-5-gated conditional fields under R9 three-part finalization, the 9-row resume
ladder with parent-filled Slots 5-7, the three frozen exit NAMES, R14
metadata-only child isolation, and the six security surfaces — every one of
which becomes a PC-numbered PRD requirement. `/execute` exercises the pattern's
two designed substitution surfaces harder than any prior parent: it binds
`storage_substrate` to an on-PR coordination DAG instead of `wip-yaml-md` (and
may be the first parent to satisfy the I-6 cross-branch-resume invariant the
pattern frames as the amplifier-layer mandate), and it binds the issue/PR
child-inspection row to `/work-on`, making the Team-Lead Discipline's
External-wait task class and `ci_outcome` semantics central rather than
incidental. It is also the downstream owner of the PLAN-Active→Done lifecycle
that `/scope` redirects to, so its exit bindings re-shape full-run /
abandonment-forced around merged-PR / forced-stop outcomes while keeping the
exit names — the pattern's freeze line — intact.
