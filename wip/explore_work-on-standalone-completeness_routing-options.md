# Routing options: where the finishing logic should live

Prepared for the routing decision. Three directions, the evidence for each, and
what each costs. All line numbers against `main` at `9f84fa7`.

## First, a correction to my own earlier claim

I reported that finding "folding is not circular" undercuts the structural
argument for keeping `/work-on` standalone. On closer reading that overstates it.
The claim needs splitting into two, and only one of them holds:

- **Runtime recursion: genuinely absent.** `/execute` does not call a `/work-on`
  slash command. `execute.md:302-305` points koto's `materialize_children` at
  `../../work-on/koto-templates/work-on.md`, and koto materializes one child
  session per issue against that template. There is no slash-command loop.
- **Dependency direction: unchanged, and it points the way the coordinator
  said.** `/execute` depends on `/work-on`'s engine and says so in its own prose
  -- "delegates each single issue to `/work-on`'s single-issue engine"
  (`skills/execute/SKILL.md:26`), "lifting `/work-on`'s plan-orchestrator
  template (now `execute.md`)" (`:30-31`), and `assert-child-template.sh` exists
  solely to fail the run if that cross-skill path does not resolve.

So the coordinator's reasoning survives: shared machinery belongs in the
depended-upon component, which is `/work-on`. What my evidence changes is not the
direction that principle points but **how much work it implies** -- which is what
separates Direction B from Direction C below.

One clarification that matters for Direction A: `work-on.md` survives under every
direction. It is the per-issue engine `/execute` runs. "Folding" removes
`/work-on` as a user-facing entry point; it does not delete the engine.

---

## Direction A -- fold `/work-on` into `/execute`

`/work-on` stops being an entry point. `/execute` grows an issue mode.
`work-on.md` stays as `/execute`'s internal per-issue engine.

**For it.** One path from an issue to a merged change, so there is no second
place for finishing logic to be missing from. The finishing logic already lives
in `/execute`, so nothing moves.

**Against it.**

- It inverts an instruction written deliberately and in as many words.
  `skills/explore/references/phases/phase-5-produce-file-an-issue.md:31-32`:
  "`/work-on` is the skill that accepts an issue number. Do not name `/execute`
  here: it takes a PLAN path and has no issue mode." `/execute`'s own SKILL.md
  (`:44-50`) confirms it accepts only a PLAN path or nothing.
- It reverses a recorded decision. `DESIGN-execute-skill.md` rejected
  hard-removing `/work-on`'s PLAN input because it "breaks existing invocations
  and `/work-on`'s own evals". The same argument applies in reverse, at larger
  scale, to removing the entry point entirely.
- multi-pr PLANs route to `/work-on` by design (`execute.md` SKILL:48-49,
  "out of scope for `/execute` ... Direct the user to `/work-on`") and would need
  rehoming.
- It retires a CI-tested cross-skill contract (`assert-child-template.sh` plus
  its test).
- It removes the entry point people use today, to solve a problem that is
  narrower than the change.

## Direction B -- keep `/work-on` standalone, migrate `/execute`'s finishing logic into it

`/execute` keeps multi-issue orchestration; the finishing states move to
`/work-on`.

**For it.** Dependency direction, as above. The depended-upon component should
not be the incomplete one.

**Against it.**

- `/execute`'s finishing states are shaped for **one shared PR aggregating N
  children**, not for one change. `pr_finalization` exists to assemble N
  children's outcomes into a single conformant title and body
  (`execute.md:640`). Moved wholesale, `/execute` loses what its own shared PR
  needs -- so the logic ends up in both places anyway.
- A shared library for exactly this machinery, between exactly these two skills,
  was already proposed and rejected in `DESIGN-execute-skill.md` on legibility
  grounds. koto templates have no include or inherit mechanism, so a shared
  component could only be a script or a prose reference regardless.
- For multi-pr it is new construction, not relocation -- see the shared cost below.
- Largest file surface of the three: roughly 15-20 files of routing prose, evals
  and CI contracts.

## Direction C -- raise the enforcement altitude inside `/work-on`, add cascade behind the existing fork

Move `/work-on`'s already-written finishing obligations out of skippable prose
into koto states with evidence gates, and add cascade states **after**
`ci_monitor`. Leave `/execute`'s plan-level cascade where it is.

**For it.**

- It targets the diagnosis the code actually supports. `/work-on` is not missing
  four of the five things #361 lists -- it has them as prose in
  `references/phases/phase-6-pr.md` and the shared
  `references/pr-body-conformance.md`. What it lacks is enforcement, and that is
  exactly what would let three separate workers skip steps that were written
  down.
- The double-cascade problem is already solved by a fork that exists and works.
  `work-on.md:752-775`: `pr_creation` accepts `pr_status: shared` and routes
  **straight to `done`**, bypassing `ci_monitor`. `/execute`'s single-pr children
  are dispatched with `SHARED_BRANCH` and take that route. Anything added after
  `ci_monitor` is therefore skipped for children automatically -- no
  `children-complete` re-derivation, no "is this the last issue" machinery.
- The two cases with no cascade at all today -- standalone runs and multi-pr --
  are both `/work-on`'s.
- It does not re-propose the rejected shared library, does not invert the
  documented prohibition, and does not reverse a recorded decision.

**Against it.**

- Cascade logic would exist in two places, kept in step by a drift check rather
  than by true sharing. That is a precedented pattern here -- `work-on.md` and
  `execute.md` already duplicate the CI-gate expression on purpose, guarded by
  `validate-template-mermaid.sh` check 4, and the template comment at
  `work-on.md:764-765` says "kept identical to execute.md" -- but it is still
  duplication.
- It leaves two entry points, so it does not deliver Direction A's "one path".
- For multi-pr it is still new construction.

## The cost every direction shares

multi-pr PLANs have **no cascade wiring at all**. `run-cascade.sh` is invoked
only from `execute.md:706`; `/work-on`'s template has zero cascade references.
Yet `references/plan-doc-structure.md:95` and `skills/roadmap/SKILL.md:350` both
state that the work-completing PR runs the cascade. Whichever direction is
chosen, multi-pr finalization is built for the first time, and two committed
documents currently describe a capability that does not exist.

## Out of this change

Three defects were reported alongside this one and are not this one:

- **The `cannot_verify` definition-of-done gate** -- a per-repo configuration
  gap. MEASURED: of the five repos in this workspace only shirabe ships
  `.claude/shirabe-extensions/work-on.md` with a `## Verification map`; the other
  four ship a generated `work-on.local.md` with no map. The gate fails closed
  exactly as `verification-map.md` specifies. Both entry points run the same
  shared template state (`execute.md:305`), so no boundary change alters anyone's
  exposure.
- **`check-staleness.sh`** -- `/work-on`'s `staleness_check` gate
  (`work-on.md:325`) calls a script this repo does not ship.
  `PLAN-work-on-friction-fixes.md:81` already records the open question.
- **Issue #87**, filed 2026-04-28 -- the same PLAN-deletion / DESIGN-transition
  gap for plan-backed `/work-on` runs, still open. #361 is its recurrence.

**#360** (terminal `koto next` without `--no-cleanup`) goes to a separate worker:
cheap, boundary-independent, already solved transferably by `/scope` at
`skills/scope/references/phases/phase-4-cleanup.md:119-124`, and destroying
context records today.

**#352** (no gate can observe whether a review panel ran) is deferred here on
purpose. Its shape depends on which skill ends up owning `/work-on`'s three
panels (scrutiny, review, qa), so settling the boundary first avoids doing the
work twice. Worth recording: the `/prd` and `/design` instances of the same
defect sit outside both skills and no boundary redraw can reach them.
