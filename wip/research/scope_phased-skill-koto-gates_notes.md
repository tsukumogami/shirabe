# Research notes: phased-skill-koto-gates

Working notes gathered while the /scope session waited on koto. Read by the
brief and requirements hops; deleted before the pull request is ready.

## The feature, in public words

A user running any phased-workflow skill can't skip a phase or leave one
without the evidence it asks for. Ten skills are named: explore, prd, design,
plan, work-on, decision, review-plan, roadmap, vision, release.

Three checks a reviewer runs (each must map to an acceptance criterion):

1. Fresh repository with koto installed: for each of the ten skills, a koto
   session for the run exists whose state names the skill's current phase.
2. Mid-run, asking the skill to jump to its last phase without the current
   phase's evidence: koto refuses the move and names what is missing.
3. Host without koto: invoking one of these skills says koto is required and
   how to install it.

Open questions to settle or defer with a reason:

- the per-skill template format
- how evidence gates encode each phase
- whether skills share one store template or each carry their own

## What is shipped today (read from main at 4444fa32)

- work-on runs on its own template, `skills/work-on/koto-templates/work-on.md`
  (about 50 states, non-overridable gates at its exit). It already meets
  checks 1 and 2.
- The other nine moved their working state from repository scratch files to
  koto session keys under the skill-session convention
  (`references/skill-session-convention.md`, Per-skill keys table). So the
  phrase "state in scratch files" is out of date: the state is in koto, but
  the session sits on the one-state store template
  `koto-templates/skill-session.md` (state `open`, accepts `close:
  done|abandoned`). The session exists; its state never names a phase. That
  is the real gap for checks 1 and 2.
- Phase position for those nine is inferred, not recorded: each SKILL.md has a
  Resume Logic table that reads which keys and document sections exist
  (e.g. design: `research/phase5_security.md` -> Phase 6; prd:
  `work/scope.md` -> Phase 2).
- Chain signal: `/scope` and `/charter` write `chain/dispatch` in the parent
  session (`skill-session.sh dispatch write`); children read it
  (`dispatch read`). `close-children` closes each child by submitting `close`
  evidence, which assumes the child's current state accepts `close`. A
  per-skill template must keep that working: an amendment point.
- `skill-session.md`'s file name is part of the contract: `koto init
  --attach-live` compares the live session's template by file name. A skill
  that moves to its own template makes a live session opened from the store
  template refuse to attach; the move needs a migration story (finish or
  close live sessions first, or a replace).
- Session sets: `/decision` run by `/design` keeps keys
  `work/decision-<N>/...` inside `design-<topic>`; `/review-plan` keeps
  `work/review.md` inside `plan-<topic>`. So an inline /decision or
  /review-plan has no session of its own today. Check 1 is about a run of
  each skill; for a nested run the phase must be recorded somewhere a reviewer
  can find (its own session, or a key in the host session). Design question.
- Convention's Limits: no chain may rest on koto parent-child lineage, since
  an import neither carries children nor accepts a child as its source. So
  per-skill sessions stay roots linked by `dispatched-by`, not koto children.
- Phase sets (from `skills/<s>/references/phases/`):
  - explore: 0 setup, 1 scope, 2 discover, 3 converge, 4 crystallize,
    5 produce (eight produce variants)
  - prd: 1 scope, 2 discover, 3 draft, 4 validate
  - design: 0 setup (freeform | prd), 1 decomposition, 2 execution,
    3 cross-validation, 4 architecture, 5 security, 6 final review
  - plan: 1 analysis, 2 milestone, 3 decomposition, 4 agent generation,
    5 dependencies, 6 review, 7 creation
  - decision: 0 context, 1 research, 2 alternatives, 3 bakeoff, 4 revision,
    5 examination, 6 synthesis
  - review-plan: 0 setup, 1 scope gate, 2 design fidelity, 3 AC
    discriminability, 4 sequencing, 4b functional shape, 5 verdict,
    6 loop-back
  - roadmap: 1 scope, 2 discover, 3 draft, 4 validate (+ sharpen)
  - vision: 1 scope, 2 discover, 3 draft, 4 validate
  - release: phases inline in SKILL.md: 1 version analysis, 2 preconditions,
    3 notes and confirmation, 4 draft release, 5 workflow dispatch,
    6 monitoring, 7 after release
- Four of the nine (prd, roadmap, vision, and brief/strategy outside the ten)
  share the same scope/discover/draft/validate shape.

## koto facts that decide the encoding (koto docs, public repo)

- `koto next --to <target>` requires the target to be a declared transition
  from the current state; jumping to a state with no edge is refused.
- `--to` skips gates except a gate declared `overridable: false` that the edge
  to the target depends on: then it exits 1 with `gate_blocked` and names the
  gate (cli-usage.md, "Directed transitions and non-overridable gates"). An
  evidence-conditioned edge in a state with `accepts` does not depend on a
  gate, so evidence alone does not stop `--to`; a non-overridable gate does.
- Evidence missing a required field or of the wrong type is refused with
  `invalid_submission`, "evidence validation failed", and field-level
  `details` (koto integration test
  `next_with_invalid_evidence_returns_structured_error`). That names what is
  missing.
- `context-exists` gates check a session key is present; they replace older
  `test -f` command gates.
- Engine traps already noted in DESIGN-scope-koto-adoption: a non-terminal
  state with an evidence block and no guarded transition is advanced through
  silently; `context_assignments:` was once discarded without a diagnostic.
- Prior design said: "Gates are bypassable and the design must not pretend
  otherwise" (overrides inject a synthetic pass). Non-overridable gates are
  the answer to check 2; the documents should say which gates are
  non-overridable and why.

## koto absent (check 3)

- `scripts/assert-koto-floor.sh` prints "koto is not on PATH; shirabe needs
  koto <floor> or later" (exit 127) and "below the floor ...; upgrade koto"
  (exit 69). Neither says how to install koto. No SKILL.md or reference says
  how either. So check 3 is a real gap: the message needs an install line
  (e.g. `tsuku install koto`, or koto's own install doc) in one place, and
  every one of the ten skills must hit that check before doing work.
- All nine store-template skills reach the floor check through
  `skill-session.sh open` (measured: nine SKILL.md files name it). work-on's
  SKILL.md doesn't call `assert-koto-floor.sh` directly (measured); it goes
  through its own open path, which still has to be traced.
- Skill-load preflight already covers most of check 3. Every skill's SKILL.md
  runs `scripts/skill-preflight.sh <skill>` at load (via `!` injection), and
  each `skills/<s>/requires.tsv` declares koto. Measured: with koto off PATH,
  `skill-preflight.sh prd` prints "koto is not installed on this host ... /prd
  declares koto. Every call to it will fail as written." The install route
  comes from `preflight_render_route` (scripts/lib/preflight-report.sh), which
  only offers a command when tsuku resolves. With no tsuku it says "No install
  route is available on this host ... Install koto by whatever means this host
  supports." So the remaining gap is a fallback route that names a real way to
  install koto with no tsuku (koto's own install doc or release download),
  plus confirming each of the ten skills stops rather than continuing after
  the report (the preflight's `|| true` means load never fails; the stop comes
  from `skill-session.sh open` exiting 127).

## Issue 1436 (public, open)

"skills: keep delegated agents' state in koto in the eleven skills that fan
work out": explore, prd, design, plan, decision, review-plan, roadmap,
vision, brief, comp, strategy. Agents write to a `skill-session.sh scratch`
directory; the orchestrator ingests into keys only after they finish; no koto
record of a delegate while it runs, so a resumed run redoes the fan-out. Its
done-criteria: a koto record per delegate, results attached; /decision resume
recovers finished agents; skill-authoring guidance says so. Out of scope:
work-on, execute, deliver, scope, coordinate, release.

Relation to this feature: different list (brief, comp, strategy in; work-on
and release out), different property (delegate durability vs phase order).
But phase gates and delegate records touch the same states (a discover or
validate phase is where fan-out happens). Recommendation to weigh: name it a
separate follow-on, sequenced after the per-skill templates exist, because a
delegate record needs a state to hang on, and folding it in widens the change
to three more skills and a koto primitive choice the feature doesn't need.

## Existing documents to build on, and amend

- `koto-templates/skill-session.md` (store template) and
  `references/skill-session-convention.md` (key names, dispatch key, close,
  session sets, koto absence).
- `docs/designs/current/DESIGN-resume-convention.md` (decisions behind the
  convention).
- `docs/designs/current/DESIGN-scope-koto-adoption.md`: its "Direction: a
  chain with no filesystem state" says the four children ship no template and
  per-hop child workflows are the follow-on. This feature is that follow-on
  for the children's phases.
- `docs/designs/current/DESIGN-koto-default-action-adoption.md`: rules for
  turning a deterministic step into `default_action` (shape, isolation, where
  the command body lives, plugin-root naming). Phase templates should reuse
  those rules rather than invent new ones.
- `docs/designs/current/DESIGN-work-on-koto-unification.md`: work-on's own
  template precedent.
- coordinate ships `coordinate.compat.json` (live-session compatibility table
  across template versions, checked in CI): a model for changing a template
  under live sessions.

## Constraints from the brief

- Docs-only PR; no code, script, test, template or eval change.
- PLAN names each implementation change as its own shirabe issue, no private
  detail; propose issues, file none.
- No design whose verification needs a paid model eval; script-graded checks
  only.
