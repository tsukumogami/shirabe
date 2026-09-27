---
schema: brief/v1
status: Draft
problem: |
  /work-on's staleness_check gate calls a script shirabe doesn't ship, by a
  bare name and an argument form nothing on a shirabe-only host provides. The
  gate fails on every issue-backed run before it assesses anything, so every
  run overrides it by hand and the gate checks nothing.
outcome: |
  An unattended issue-backed /work-on run on a shirabe-only install gets past
  staleness_check without anyone overriding it: either the check runs and
  decides, or the run records, in its own evidence, that the check could not
  run and why.
motivating_context: |
  The gap was first logged as a portability concern. Two live runs since then
  showed it is worse: on a host without the script the gate can never pass,
  and on a host where a separately installed plugin provides a script of the
  same name, that script rejects the argument form the gate passes.
---

# BRIEF: staleness-check portability

## Status

Draft

Framing for the staleness_check gate in `/work-on`. The downstream PRD owns
what the gate must do; the DESIGN owns which of the four approaches the issue
names gets built.

## Problem Statement

`/work-on` has a state, `staleness_check`, that sits between setup and
analysis on every issue-backed run. Its job is to catch the case where an
issue was filed against a codebase that has since moved on: the issue is old,
its milestone siblings have closed, or the files it names have changed. When
that happens the run should re-read the issue against current code before
planning an implementation, rather than implementing a plan the codebase has
already overtaken.

The gate that is supposed to make that call runs a command, `check-staleness.sh
--issue <N>`, found by bare name on `PATH`. shirabe doesn't ship that script.
On a host where only shirabe is installed the command isn't found, the pipe
into `jq` gets nothing, and the gate fails with an exit code that means "could
not run", which the state then treats the same way it treats "stale". A host
that also has a separately installed plugin carrying a script of the same name
is no better off: that script takes the issue number as a positional argument
and rejects `--issue`, so the gate still fails before any signal is read.

The ways past a failed gate don't fit an unattended run. The state offers
`override`, documented for "the user says to skip the staleness check", which
no user said, and `blocked`, which ends the run. In practice every issue-backed
run takes `override`. That has two costs. The gate checks nothing, so an
overtaken issue goes straight to implementation. And agents learn that
overriding a gate is the routine way through, which is the habit every other
gate in the workflow depends on them not having.

## User Outcome

The person affected is whoever runs `/work-on <issue>` on a host that has
shirabe and nothing else, most often an unattended agent run where no human is
there to approve an override. Once this lands, that run reaches analysis
without a hand override at `staleness_check`. When the check can run, its
verdict decides the route: fresh goes on to analysis, stale goes to
introspection. When it can't run, the run records that as its own named
outcome, with the reason, in the run's evidence, where a reviewer reading the
session afterwards can see that staleness was not assessed and why. `override`
goes back to meaning what it says: someone chose to skip the check.

The second person affected is the shirabe maintainer who owns the gate. Today
the definition of "stale" lives outside shirabe, so they can't read it, tune
it, or tell whether it drifted. Once this lands, what the gate measures is
written down inside shirabe, where they can compare it with the check teams
used before.

## User Journeys

### Unattended run on a fresh issue

An agent dispatched to implement a recently filed issue runs `/work-on 123` on
a shirabe-only install. The gate runs the staleness check, the check finds no
staleness signal, and the workflow advances to analysis on its own. Nothing in
the run's evidence mentions an override.

### Unattended run on an overtaken issue

The same agent picks up an issue filed two months ago whose milestone siblings
have since closed and whose referenced files have been edited. The check
reports it stale, and the agent submits the stale signal and moves to
introspection, where it re-reads the issue against current code before
analysis.

### A host where the check cannot run

A contributor runs `/work-on` where the check can't complete: the plugin root
wasn't passed to the session, or `gh` can't reach GitHub. The gate fails in a
way the directive distinguishes from staleness, the agent submits the
"unavailable" outcome with the reason, and the run proceeds to analysis. A
reviewer reading the session later finds that outcome and its reason recorded
rather than an `override` with a made-up justification.

### Maintainer comparing the check with its predecessor

A shirabe maintainer wants to know whether the gate's notion of "stale" still
matches the check teams used before, and what it would take to tune it. They
read one place in shirabe that states what the check measures and the
thresholds it applies, without needing access to any other plugin.

## Scope Boundary

**In:**

- The `staleness_check` gate in `skills/work-on/koto-templates/work-on.md`: what
  it runs, where the thing it runs is found, and its argument form.
- A named outcome for "the check could not run", distinct from `override` and
  `blocked`, offered by the state's directive and recorded in evidence.
- Whatever the chosen approach needs to exist inside shirabe so the gate works
  with only shirabe's declared dependencies installed.
- A statement, inside shirabe, of what the check measures and the thresholds
  it applies.
- Tests showing the gate passes on a fresh issue, fails on a stale one, and
  takes the degraded path on a host where the check can't run.

**Out:**

- Changing or depending on the script a separately installed plugin provides.
  Its argument form is not shirabe's to rely on.
- Building staleness logic into koto. If the design prefers that direction, it
  lands as a proposal to the koto project; this work does not build it.
- The `introspection` state's own procedure. The gate decides whether a run
  goes there; what introspection does once there is unchanged.
- The other gates in the work-on template, including the ones whose
  commands also assume tools on `PATH`.
- Plan-backed and free-form `/work-on` runs, which don't pass through
  `staleness_check`.
