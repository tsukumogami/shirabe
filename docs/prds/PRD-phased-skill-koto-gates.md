---
schema: prd/v1
status: Draft
problem: |
  Nine of shirabe's ten phased skills run their koto session on a store
  template with one working state, so koto can't report which phase a run is
  in and refuses no skipped phase; only the agent's reading of the
  instructions keeps a run in order. A host with neither koto nor tsuku is
  told koto is missing but not how to get it.
goals: |
  For each of the ten skills, koto names the phase a run is in, refuses a move
  past a phase whose evidence is missing and says what is missing, and a host
  without koto is stopped before any work with a working install route. The
  change builds on the shipped session convention and work-on's template and
  is verified by scripts, not by a model.
upstream: docs/briefs/BRIEF-phased-skill-koto-gates.md
---

# PRD: Phased skills that can't skip a phase

## Status

Draft

## Problem Statement

shirabe's phased skills are written as ordered phases, and each phase asks
for something before the next starts: research findings, a review verdict, a
confirmation. Ten skills work this way: explore, prd, design, plan, work-on,
decision, review-plan, roadmap, vision and release.

work-on runs on a koto template of its own whose states are its phases, and
koto won't let it leave its final states without the evidence they need. The
other nine keep their working state as keys in a koto session, but that
session runs on the shared store template, whose only working state is
`open`. So koto reports `open` at the first phase and at the last. A person
checking a run can't see how far it got, a parent chain resuming an
interrupted child guesses the phase from which keys exist, and an agent that
jumps to the final phase without the research or review before it meets no
refusal.

A host without koto gets a dead end of a different kind. Every one of the ten
skills stops before it does work, but the message names an install command
only when tsuku is present. Without tsuku it says to install koto "by whatever
means this host supports", and work-on's path prints a different message
from the other nine.

This matters now because shirabe's adoption designs already moved the nine
skills' state into koto and named per-skill phase workflows as the next step;
until that step lands, the session holds what a run wrote but not where it
stands.

## Goals

- A run of any of the ten skills has a koto state that names its current
  phase, readable with one status call.
- Leaving a phase without its declared evidence is refused by koto, with the
  missing evidence named, whether the run asks for the next phase or jumps
  straight to the last one.
- A host without koto is stopped before any work and told how to install
  koto, with a route that works when tsuku is absent.
- Parent chains, the session convention and work-on keep working as they do
  today, and the whole change is checked by scripts that run in CI without a
  model.

## User Stories

- As a reviewer checking a run in a fresh repository, I want koto's status
  for the run to name the phase it's in, so that I can tell how far it got
  without reading its keys.
- As the author of a run, I want koto to refuse my agent's attempt to jump to
  the final phase when the current phase's evidence isn't there, so that a
  document never ships without the research or review its skill promises.
- As an author whose chain was interrupted, I want the resumed run to pick up
  in the phase it was in, so that nothing is redone or skipped.
- As a first-time user without koto, I want the skill to stop and tell me how
  to install koto on my host, so that I'm not left guessing.
- As a maintainer of a parent chain (`/scope`, `/charter`), I want children
  on per-phase workflows to accept my dispatch and my close at exit exactly
  as before, so that the chains need no rework beyond what this feature
  states.

## Requirements

### Functional

- **R1. A phase state per run.** Every run of explore, prd, design, plan,
  work-on, decision, review-plan, roadmap, vision and release has a koto
  session whose current state names the phase the run is in, using the phase
  names that skill documents. The state changes as the run moves between
  phases.
- **R2. Declared evidence per phase.** Each phase of each of the ten skills
  declares the evidence that completes it: a submitted field, a session key
  the phase writes, or a check koto runs. koto, not the agent, decides
  whether it is present.
- **R3. Refusal of a skipped phase.** A move out of a phase whose declared
  evidence is missing is refused by koto. This holds for an ordinary advance
  and for a directed jump to any later phase, the last one included. The
  refusal names the missing evidence field, key or check. The checks that
  guard entry to a skill's final phase can't be waived by an override.
- **R4. Nested runs.** A decision run started inside a design run, and a plan
  review started inside a plan run, have a phase that a status call can
  read, either from a session of their own or from a state of the host
  session that names the nested phase.
- **R5. Resume from the recorded phase.** A resumed run of any of the nine
  skills, direct or under a parent chain, continues from the phase koto
  records rather than from a phase inferred from which keys exist.
- **R6. koto-absent stop.** On a host where koto isn't on PATH, or is below
  shirabe's floor version, each of the ten skills stops before its first
  phase, writes nothing to the repository and no session, and prints one
  message that says koto is required, the floor version, and an install
  route.
- **R7. Install route without tsuku.** The R6 message names a concrete
  install route on every host: the tsuku command when tsuku is present, and
  otherwise a public route that needs no tsuku, such as koto's release
  downloads or its install instructions.
- **R8. Parent chains unchanged.** `/scope` and `/charter` dispatch a child,
  read its result and close it at their exit with the calls they make today,
  and a child run on a per-phase workflow accepts that close from any phase.
  Child sessions stay roots linked to their parent by the dispatched-by
  link, never koto parent-child lineage.
- **R9. Session convention kept.** The key names in the session convention's
  per-skill table, the dispatch key and the store template's file name stay
  as they are, so readers of those keys and sessions opened from the store
  template keep working. A skill that moves to its own workflow says how a
  session opened on the store template before the change is finished or
  replaced; it never leaves such a session unable to attach without saying
  why.

### Non-functional

- **R10. Script-graded verification.** Each requirement from R1 to R9 has a
  check that runs as a script, in CI, with no model call, drives the
  workflow through koto directly, and fails when the requirement is broken.
- **R11. No new koto dependency.** The feature works with the koto release
  shirabe's floor already requires, or names the koto change it needs as a
  separate request; it doesn't assume an unreleased koto behaviour.
- **R12. Bounded cost per phase.** Each phase boundary a run crosses costs
  exactly one koto call that changes the current state, so a run's state
  changes grow with its phase count and not with its key writes.

## Acceptance Criteria

Every criterion below is checked by a script that drives the skill's koto
workflow directly in a temporary repository: it opens the session the way the
skill does and submits each phase's evidence itself, with no agent and no
model. "The ten skills" means explore, prd, design, plan, work-on, decision,
review-plan, roadmap, vision and release.

Phase state (R1, R5):

- [ ] For each of the ten skills, right after the session opens, `koto
      status` reports a current state whose name is the skill's first
      documented phase; after the script submits that phase's evidence, it
      reports the second phase.
- [ ] For each of the ten skills, a script walks every phase in order to the
      terminal state, and each `koto status` along the way names the phase
      the walk has reached.
- [ ] A session left in each of its non-terminal phases, then reopened the way
      a resumed run reopens it, reports the same phase before and after, both
      for a direct run and for a run opened under a `/scope` dispatch key.

Refusals (R2, R3):

- [ ] A script that reads each of the ten skills' workflows lists every
      non-terminal phase state with the evidence field, required key or gate
      that completes it, and fails when any phase state has none.
- [ ] For each of the ten skills, from a phase whose evidence is absent: an
      ordinary advance, and a directed move to the skill's last phase, each
      exit non-zero, leave the current state unchanged, and print the name of
      the missing evidence field, key or gate.
- [ ] For each of the ten skills, evidence submitted with a required field
      missing or of the wrong type is refused, and the refusal names the
      field.
- [ ] For each of the ten skills, recording an override on the gate that
      guards entry to the last phase and then attempting the directed move is
      still refused; an override on a gate the workflow declares overridable
      is accepted.

Nested runs (R4):

- [ ] A decision run inside a design run, and a plan review inside a plan run,
      each report their current phase name through one `koto status` call on
      a session the script can name from the host's topic.

koto absent (R6, R7):

- [ ] With koto removed from PATH, and again with a koto below the floor
      version on PATH, starting each of the ten skills exits non-zero before
      its first phase, prints a message containing "koto is required", the
      floor version and an install route, and leaves `git status` clean and
      no session behind.
- [ ] With both koto and tsuku removed from PATH, that message names an
      install route that doesn't use tsuku.

Compatibility (R8, R9, R11):

- [ ] For each of the nine skills that a parent chain dispatches, a child
      session left in each of its non-terminal phases is closed by the parent
      chain's close call and ends in a terminal state; the child session is a
      root whose dispatched-by link names the parent.
- [ ] The key names in the session convention's per-skill table, the
      dispatch key's name and fields, and the store template's file name are
      unchanged by the feature.
- [ ] Attaching to a session opened from the store template before the change
      either succeeds and the run finishes on it, or is refused with a message
      that names the session and the step to take.
- [ ] The workflows compile and every script above passes with the koto
      version shirabe's floor names, with no newer koto installed.

Cost and verification (R10, R12):

- [ ] In each skill's full scripted walk, the number of koto calls that change
      the current state equals the number of phase boundaries the walk
      crosses.
- [ ] Every script named in these criteria runs in CI, and none of them calls
      a model.

## Out of Scope

- Keeping delegated agents' work in koto while it runs. That covers a
  different skill set (it adds brief, comp and strategy and leaves out
  work-on and release) and a different property, a fan-out that survives a
  crash. It needs the per-phase states this feature creates to hang its
  records on, so it is a follow-on sequenced after this one.
- Skills outside the ten. brief and strategy share the phase shape of prd and
  vision and can follow later; scope, charter, deliver, execute and
  coordinate already run on templates of their own.
- Changes to koto. If the feature needs one, it is requested from koto
  separately (R11).
- Judging the quality of a phase's evidence. The feature checks that the
  evidence exists and has its declared shape; whether a review was good stays
  with the review seats.
- Testing phase-skip behaviour with a model as judge. Verification is by
  script (R10).

## Decisions and Trade-offs

- **Delegated agents' state is a follow-on, not folded in.** Folding it in
  would add three skills and a choice about how koto records a running
  delegate, and it needs per-phase states to exist first. Keeping it separate
  lets this feature land on the ten skills it names.
- **work-on stays in the list.** It already meets R1 to R3; it is listed so
  every check runs against all ten, and it shares the R6 and R7 message.
- **The BRIEF's open questions go to the design.** Whether each skill carries
  its own template or the skills share one, how each phase's evidence is
  encoded, and where a nested run keeps its phase are how-questions. This
  PRD fixes what each answer must satisfy (R1 to R4, R8, R9) and leaves the
  choice to the design.
- **Final-phase checks can't be overridden; others may be.** Overrides exist
  so a stuck run can be moved deliberately. Making every gate unwaivable
  would strand runs on an environment fault, so R3 binds only the checks that
  guard a skill's final phase, which is the move the feature exists to stop.

## References

- `references/skill-session-convention.md`: session and key rules the nine
  skills follow.
- `koto-templates/skill-session.md`: the shared store template.
- `skills/work-on/koto-templates/work-on.md`: the existing per-phase
  template.
- `docs/designs/current/DESIGN-scope-koto-adoption.md` and
  `docs/designs/current/DESIGN-koto-default-action-adoption.md`: the
  adoption designs this feature continues.
