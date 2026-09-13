# Lead: Does this repository already have a pattern for machinery shared between two skills, and what do its own authoring conventions say about where shared logic belongs?

## Findings

### 1. Shared prose references at the repo root (`references/`)

shirabe's actual sharing mechanism for cross-skill *contracts* is a set of
repo-root reference files, read on demand by multiple SKILL.md files via
`${CLAUDE_PLUGIN_ROOT}/references/<name>.md`. These share prose rules and
invariants, never executable logic or runtime state:

- `references/parent-skill-pattern.md` — read by `/scope` (`skills/scope/SKILL.md:519`),
  `/charter` (`skills/charter/SKILL.md:299`), and `/execute`
  (`skills/execute/SKILL.md:518`, which calls itself "the third parent skill in
  the trio," `skills/execute/SKILL.md:23`).
- `references/parent-skill-state-schema.md`, `references/parent-skill-security.md`,
  `references/parent-skill-resume-ladder-template.md`,
  `references/parent-skill-child-inspection.md`, `references/worktree-discipline.md`
  — same three consumers, same pattern.
- `references/coordination-strategy.md` — read by `/scope`, `/execute`, and
  `/plan` (grep confirms all three `SKILL.md` files cite it) for the
  coarsest-legal-grouping rule, merge-order DAG, and F1/F2/F4 rules, single-sourced
  rather than restated per skill.
- `references/fixes/sub-agent-dispatch.md` — read by seven authoring children
  (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`) **and
  by `/work-on`** (named explicitly at `references/fixes/sub-agent-dispatch.md:4`
  and given its own binding row at line 129: `/work-on | Phase 0 detection only`).
- `references/default-action-conversion.md` — the shirabe-specific policy layer
  on top of koto's own authoring guide for when a template step may run as a
  `default_action` vs. stay agent-run prose (`references/default-action-conversion.md:1-58`).

What this mechanism **can** share: prose contracts, invariants, vocabulary,
enumerations, security rules — anything a skill's author needs to read and then
implement in its own words. What it **cannot** share: it is not included,
inherited, or executed; each consuming SKILL.md restates the binding in its own
terms and the reference is loaded lazily ("read it when the directive tells you
to," `skills/scope/SKILL.md:294-297`). It shares understanding, not code, and
not runtime state.

### 2. Shared scripts

A second, distinct mechanism: literal shared shell scripts invoked identically
from multiple skills' `allowed-tools`/preflight lines, e.g.
`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh` (invoked at the top of
`skills/scope/SKILL.md:19,22`, `skills/work-on/SKILL.md:19`, and others) and
`${CLAUDE_PLUGIN_ROOT}/scripts/validate-template-mermaid.sh`. This is genuine
code sharing, but only for generic, skill-agnostic mechanics (preflight checks,
template linting) — not for a skill's own domain logic (PR finalization, CI
choreography). No shared script currently implements anything specific to
`/work-on` or `/execute`'s domain.

### 3. koto templates cannot compose

Checked koto's own canonical template-format reference
(`public/koto/plugins/koto-skills/skills/koto-author/references/template-format.md`)
and its archived format design
(`public/koto/docs/designs/archive/DESIGN-koto-template-format.md`): neither
documents an include, extends, inherit, or import mechanism for `.md` templates.
Each koto template is a single self-contained YAML `states:` document. This is
confirmed negatively by shirabe's own tooling: `scripts/validate-template-mermaid.sh`
"Check 4" (`scripts/validate-template-mermaid.sh:154-163`) exists *because*
templates cannot share a gate definition — instead, when two templates need the
same CI-gate command, they duplicate the YAML text, and a CI script mechanically
diffs the duplicated command strings across templates to catch drift. The
script's own comment names the origin: "That is how issue #244 got two templates
gating CI on the same wrong expression. This check makes the duplication
mechanical rather than a matter of remembering" (`scripts/validate-template-mermaid.sh:157-159`).
`work-on.md`'s own `ci_passing` gate carries an inline comment, "kept identical
to execute.md" (`skills/work-on/koto-templates/work-on.md:790`), naming the
counterpart template it must stay byte-identical with. **Templates cannot
compose — the repo's answer to needing the same logic in two templates today is
duplicate-and-mechanically-verify, not share.**

### 4. The parent-skill pattern: how a child knows it's under a parent, and who finalizes

This is the closest existing answer to "how does a standalone child behave
differently under a parent, without becoming non-standalone." The mechanism is
narrow and precise:

- **Signal.** The *only* permitted parent→child channel is a fixed-shape
  sentinel block the parent writes into *its own* state file (not the child's):
  `parent_orchestration: {invoking_child, suppress_status_aware_prompt, rationale}`
  (schema at `references/fixes/sub-agent-dispatch.md:19-24`, invariant stated at
  `references/parent-skill-pattern.md:329-335`). Children glob for it
  (`wip/*_<topic>_state.md`, forward-compatible across parent names — see
  `skills/plan/evals/evals.json:319`) at their own Phase 0.
- **What it is explicitly forbidden to be:** "Parents do not extend children's
  input surfaces with parent-specific flags or arguments... The per-parent
  prohibition still holds — a parent SHALL NOT add flags or arguments to a
  child's `$ARGUMENTS` parser, and SHALL NOT extend the child's
  environment-variable surface" (`references/parent-skill-pattern.md:328-341`).
  The sentinel is "the one named exception, and only because it is
  pattern-defined" (`references/parent-skill-pattern.md:352-353`).
- **Who owns the terminal artifact / who finalizes: the child, always.** The
  parent's *entire* observability surface into an in-flight child is "strictly
  limited to" the child's durable artifact path, `git log` since a captured SHA,
  and the parent's own `wip/` — explicitly **not** the child's `wip/` state, its
  team, or its inbox (`references/parent-skill-pattern.md:576-596`, R14
  child-isolation). The Hand-Back Contract the parent runs after the child
  returns is read-only: file-existence check, frontmatter `status:` read, blob
  hash capture, git-log scan, validator pass-through, sentinel cleanup, snapshot
  capture (`references/parent-skill-pattern.md:610-636`) — the parent never
  authors or finalizes the child's document. Concretely, `/brief` under a parent
  chain still runs its own Phase 5 Finalize; the only accommodation is the
  "Parent-delegated-approval" fallback shape, where the child *writes its draft
  in a non-Accepted state* and the parent's own separate prompt triggers the
  Accepted transition (`references/fixes/sub-agent-dispatch.md:64-74`) — the
  child still does the writing and the transition call; the parent only owns
  *when* to ask the human.

### 5. `/work-on` is already the fourth binding in this pattern, and it already breaks the mold

`/work-on` is explicitly listed alongside the seven authoring children as a
sub-agent-dispatch participant, but with a reduced binding: "`/work-on` carries
only the Phase 0 detection line (R9 scopes the seven authoring children for the
Resume Logic row). When `/work-on` runs under a parent chain, it inherits the
parent's branch and PR context but otherwise operates normally"
(`references/fixes/sub-agent-dispatch.md:129-132`). And `/execute` names itself
"the third parent skill in the trio" (`skills/execute/SKILL.md:23`) and cites
`parent-skill-pattern.md` for its own exit-path semantics
(`skills/execute/SKILL.md:518`).

But `/execute`'s relationship to `/work-on` is *not* the read-only,
child-finalizes-itself shape described in (4) above. `/execute` owns a
`plan_completion` state that runs "the finalization cascade" — DRAFT-before-READY,
then `gh pr ready`, then CI-to-green — via a script it owns exclusively,
`skills/execute/scripts/run-cascade.sh` (`skills/execute/SKILL.md:786`,
`:256-259`). `/work-on` run standalone terminates at `done`, defined in its own
koto template as: "The workflow is complete. The PR has been created and CI is
passing" (`skills/work-on/koto-templates/work-on.md:1200-1201`) — no merge, no
`gh pr ready`. There is no `ci_monitor → merge` edge in `work-on.md`
(`skills/work-on/koto-templates/work-on.md:777-820`). So the gap named in the
Exploration Context is real and already visible in the code: `/execute` finalizes
plans (turns PR into merged code); `/work-on` alone does not, and this is not an
oversight but the documented current design (see Finding 6).

### 6. Prior art: this exact "shared component" option was already considered and rejected

`docs/designs/current/DESIGN-execute-skill.md` — the design that created
`/execute` by narrowing `/work-on` — directly confronted this question under
"Decision 2 — Orchestrator extraction and PLAN routing"
(`docs/designs/current/DESIGN-execute-skill.md:96-109`):

> "**Extraction — shared library both skills reference.** Rejected: a neutral or
> plan-hosted template muddies the single-issue legibility the narrowing is meant
> to buy."
>
> "**Extraction — move into /execute (chosen, E3).** Move `work-on-plan.md`, the
> orchestrator prose, and `run-cascade.sh` ... into /execute; keep `work-on.md` in
> /work-on as the canonical single-issue engine /execute spawns by cross-skill
> path."

The rejected alternative is structurally identical to this exploration's Option
2's "shared component" variant: a component neither skill fully owns, referenced
by both. The stated reason for rejection was not technical infeasibility (koto
templates genuinely cannot be shared mechanically either way) but legibility:
putting orchestration machinery in a shared, neither-owned location was judged
to blur what `/work-on` is for. The chosen alternative was full extraction into
the parent (`/execute`), leaving the child (`/work-on`) narrowed rather than
augmented. `/execute` then reaches the child skill only "by cross-skill path" —
i.e., it points at `${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md`
directly (`skills/execute/SKILL.md:174,756,795`) and spawns it via the Skill
tool, the same "invoke the whole other skill" mechanism `/scope` and `/charter`
use for their children — not a shared library extraction.

### 7. The CLAUDE.md CLI-surface rule and what it forecloses

CLAUDE.md's "CLI Surface: author with skills, check with `validate`" section
(`CLAUDE.md`, "CLI Surface" heading) states the binding rule precisely:

> "**Artifacts are authored by skills**, not by CLI subcommands. The agent writes
> the doc from the skill's prose and templates. There is no `create`/`render`
> subcommand for any artifact type... **`shirabe validate` is the
> feedback/correctness engine.** ... **Anti-pattern (do not repeat):** do NOT add
> a CLI subcommand that renders or creates an artifact body."

The worked cautionary example is a removed `shirabe coordination create/status/sync`
subcommand that rendered a PR body; it was replaced by a skill-authored body
(from `references/coordination-strategy.md`) checked by `shirabe validate`.

This rule specifically forbids **compiled-CLI-as-shared-authoring-logic**: a Rust
subcommand that renders or creates any part of an artifact body (a PR
description, a finalization summary, a merge decision) on either skill's behalf.
It does **not** forbid: (a) a shared prose reference file read by both skills'
authors (mechanism 1 above); (b) a shared deterministic *check* invoked by both
(`shirabe validate` itself, or a new `--flag`/mode on it, is explicitly
encouraged as the place new correctness rules belong); (c) one skill invoking
another skill wholesale via the Skill tool (mechanism used throughout the parent-
skill pattern); (d) a shared shell script that performs mechanical, non-authoring
work (git operations, CI polling) the way `run-cascade.sh` and
`skill-preflight.sh` already do. The rule draws its line at *authoring an
artifact body* (or, by the coordination-PR precedent, an artifact's durable
narrative content) from compiled/shared non-skill code — the finalization
cascade itself (branch/PR mechanics) is not "authoring a body" in this sense and
already lives in a shared script (`run-cascade.sh`), but it is owned by exactly
one skill (`/execute`), not jointly referenced by two.

### 8. `references/default-action-conversion.md`: when koto runs a step itself

Not about sharing, but read per the lead's instructions
(`references/default-action-conversion.md:1-58`). The rule: keep a mechanical
template step as agent-run prose whenever its *successful* completion is itself
an irreversible, externally-visible event (creating/publishing/closing a PR,
posting a comment, marking a draft ready) — reversibility of the *local artifact*
doesn't matter, only whether an externally-visible notification already fired.
Convert to `default_action` only when the command fails non-zero on failure and
leaves a trace some other command/gate can check independently of its own exit
code. This bears on the candidate directions only indirectly: whichever skill
ends up owning "mark ready" / "merge" logic, that step is squarely on the
prose/agent-run side of this rule, not a candidate for a bare mechanical
`default_action`, regardless of which skill hosts it.

## Implications

- The repo has a real, working, precedented pattern for a child that must
  remain independently invocable while behaving differently under a parent: the
  `parent_orchestration:` sentinel plus the "child always finalizes its own
  terminal artifact" invariant. `/work-on` already participates in this pattern
  at a reduced binding (Phase-0 detection only, no Resume Logic row).
- The one time this repo faced almost exactly the current question — "put
  plan-level finalization machinery in a shared place both `/work-on` and a new
  parent skill reference" — it explicitly rejected the shared-component shape
  and instead moved the logic wholesale into the parent, narrowing the child.
  That decision was reasoned on legibility grounds, not on any technical
  inability to share (though templates in fact cannot be shared mechanically
  either).
- Because koto templates cannot include or inherit from one another, any
  "shared component" for turning a PR into a merged one would have to be either
  (a) a shared *script* (technically supported, precedented by
  `run-cascade.sh`/`skill-preflight.sh`, but scripts do mechanical work, not
  agent judgment or artifact authoring) or (b) a shared *prose reference*
  (precedented, but only shares understanding an author re-implements per
  skill, and explicitly cannot substitute for a skill's own authored logic) —
  never a shared *koto template fragment*, which does not exist as a concept in
  this codebase.
- The CLAUDE.md CLI-surface rule does not block moving finalization logic
  into a shared *skill-authored* location; it blocks moving it into a *compiled
  CLI subcommand* that would render/create the artifact body on either skill's
  behalf. A shared skill-owned component is a CLAUDE.md question about
  legibility and ownership (per Finding 6), not a validate-vs-render violation
  per se — unless the shared component were implemented as new `shirabe`
  subcommand logic that authors PR/merge content, which the rule forecloses
  outright.

## Surprises

- `/work-on` was not a hypothetical third case to design from scratch — it is
  *already* a registered participant in the parent-skill / sub-agent-dispatch
  machinery, with its own binding row, predating this exploration.
- The repo already has a design record
  (`docs/designs/current/DESIGN-execute-skill.md`) that considered and rejected,
  by name, an option structurally identical to this exploration's "shared
  component" variant, for the same two skills, for the same kind of logic
  (plan-level finalization). This is closer to precedent than analogy.
- `/work-on`'s own koto template already defines "done" as PR-created-and-CI-green,
  never merged — the standalone gap the exploration describes is not implicit
  behavior to infer, it is a literal terminal-state docstring
  (`skills/work-on/koto-templates/work-on.md:1200-1201`).
- Two koto templates (`work-on.md`, `execute.md`) already duplicate a CI-gate
  expression on purpose, with a dedicated CI check (`validate-template-mermaid.sh`
  Check 4, backed by `scripts/lib/koto-gates.sh`) whose sole job is catching
  drift between the copies — direct evidence that "keep duplicate logic in sync
  by mechanical verification" is an accepted, precedented pattern here when true
  sharing (template composition) is unavailable.

## Open Questions

- `DESIGN-execute-skill.md`'s rejection of "shared library" was argued on
  legibility grounds specific to *koto templates/orchestrator prose*. It does not
  settle whether a narrower shared component — e.g., a shared *reference file*
  describing the finalization-cascade steps, each skill still authoring its own
  koto states against it (mechanism 1 above) — would face the same objection, or
  whether that distinction (shared prose contract vs. shared executable
  orchestrator) is exactly what makes it acceptable. This lead did not find a
  design doc addressing that narrower version directly.
- Whether `shirabe validate` could grow a mode that checks "is this PR
  actually mergeable" (in the spirit of `--merge-gate`) as the shared
  *correctness* surface, while the *action* of finalizing stays skill-owned in
  whichever skill ends up responsible — this would fit the CLI-surface rule
  cleanly but wasn't explored here since it's a design proposal, not a
  precedent search finding.

## Summary
The repo has a working, precedented answer for a child that must stay standalone under a parent: a single narrow `parent_orchestration:` sentinel signals context, and the child always authors and finalizes its own terminal artifact — the parent only reads status back. Separately, `docs/designs/current/DESIGN-execute-skill.md` already considered and explicitly rejected a "shared library both skills reference" for this exact machinery (plan-level finalization between `/work-on` and `/execute`), choosing full extraction into the parent instead, and koto templates have no include/inherit mechanism at all, so any future "shared component" can only be a shared script or a shared prose reference, never a shared template fragment. The biggest open question is whether a narrower shared *reference contract* (as opposed to shared orchestrator code) would escape the legibility objection that sank the prior shared-library option.
