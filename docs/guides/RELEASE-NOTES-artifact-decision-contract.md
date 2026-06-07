# Artifact Lifecycle Contract — Adopter Migration Guide

This release ships the per-skill artifact lifecycle contract for shirabe.
Every producer-skill now declares whether its artifact is durable or
working, in its own SKILL.md, using a uniform prose template. ROADMAP
flips from durable to working, and the work-on cascade grows a new step
that deletes a finished ROADMAP alongside the existing PLAN deletion.

This guide is for skill authors writing new producer-skills and for
adopters who want to know what changed. If you don't author skills and
don't track skill internals, the practical effect is small: a ROADMAP
whose features are all Done and whose issues are all closed will be
removed from `docs/roadmaps/` the next time the cascade runs over its
chain.

## What changed

Three things land together as one PR:

- A new `## Artifact Lifecycle` H2 section in each of the eight
  producer-skill SKILL.md files (BRIEF, PRD, DESIGN, PLAN, ROADMAP,
  VISION, STRATEGY, COMP). The section names the artifact's lifecycle
  in a uniform prose template so the rule is visible where authors
  already read.
- ROADMAP is now a working artifact. Its lifecycle becomes
  `Draft -> Active -> Done -> DELETED`, mirroring PLAN's shape. When the
  cascade walks a chain and finds a ROADMAP whose features are all Done
  and whose referenced GitHub issues are all closed, it transitions the
  ROADMAP Active -> Done and `git rm`s the file in the same atomic
  finalization commit.
- A new convention header in CLAUDE.md (`## Artifact Lifecycle:
  per-skill`) names the three-rule model at the project level and points
  readers at the per-skill SKILL.md sections as authoritative.

The cascade extension is a shell function added to the existing
`skills/work-on/scripts/run-cascade.sh`; no new script, no new state in
the koto graph. The function is named `handle_roadmap_deletion` and is
greppable.

## The three-rule model

Every shirabe artifact follows one of three rules:

1. **Durable.** The artifact stays in `docs/<dir>/` after completion as
   part of the project's audit trail. BRIEF, PRD, DESIGN, VISION,
   STRATEGY, and COMP are durable.
2. **Working with a documented completion condition.** The artifact
   retires when a deterministic condition holds, deleted by the work-on
   cascade in the same finalization commit. PLAN and ROADMAP are working.
3. **Per-skill prose is authoritative.** The CLAUDE.md convention header
   names the model at the project level. The producer-skill's
   `## Artifact Lifecycle` section is the source of truth for the
   per-artifact rule, including the completion condition for working
   artifacts.

## Per-skill prose template

Every producer-skill's `## Artifact Lifecycle` section instantiates one
of two templates. The template is prose, not YAML or a table — it sits
among the skill's other H2 sections and reads naturally. The shape is
uniform so a reviewer can pattern-match across all eight skills.

### For durable artifacts

```markdown
## Artifact Lifecycle

**Lifecycle:** Durable. Stays in `docs/<dir>/` after completion as part
of the project's audit trail.

<one-paragraph rationale tying to audit-trail durability for this
artifact type>
```

Substitute `<dir>` with the artifact's directory: `briefs/`, `prds/`,
`designs/`, `visions/`, `strategies/`, or `competitive/`.

### For working artifacts

```markdown
## Artifact Lifecycle

**Lifecycle:** Working. Completion condition: <condition>. Deleted by:
<cascade-step>.

<one-paragraph rationale and lifecycle reference; cite
`docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md` as the
lifecycle template source>
```

The completion condition must be deterministic — phrased so the cascade
can evaluate it without prompting a human. For PLAN, the condition is
the chain's terminal state verified by the cascade. For ROADMAP, the
condition is all features at status Done AND all referenced GitHub
issues closed.

## ROADMAP doctrine flip

Before this change, ROADMAPs stayed in `docs/roadmaps/` indefinitely.
A ROADMAP whose features were all Done sat alongside in-flight
initiatives, and reviewers learned to skim past finished work.

After this change, ROADMAP is a working artifact. Its lifecycle states
mirror PLAN's: `Draft -> Active -> Done -> DELETED`. The Draft -> Active
gate keeps its existing human-approval semantic (features lock at
activation). The Active -> Done flip is the ephemeral in-process marker
the cascade applies immediately before deletion. The Done -> DELETED
transition is cascade-only — there's no `/roadmap` verb form for it.

Deletion is triggered by the work-on cascade, not by the author and not
on a timer. The cascade evaluates two conditions:

1. Every feature row under `## Features` in the ROADMAP is at status
   `Done`.
2. Every referenced GitHub issue URL is at state `CLOSED`.

Both must hold. If either fails, the function is a no-op and the
ROADMAP stays. The check is idempotent — running the cascade twice on
the same chain state produces the same outcome.

## Cascade extension

The cascade lives in `skills/work-on/scripts/run-cascade.sh`. The
finalization commit (the one before `gh pr ready` fires) already runs a
PLAN deletion step. The new function, `handle_roadmap_deletion`, runs
alongside it in the same window.

The function:

- Looks up the ROADMAP path via the chain's upstream walk (it's a no-op
  if the chain has no ROADMAP).
- Re-checks all features are Done and all issues are closed (idempotent
  on direct re-invocation).
- Calls `shirabe transition <path> Done` to mark the in-process
  Active -> Done flip.
- Calls `git rm -f <path>` to remove the file from the working tree.
- Stages the deletion as part of the same finalization commit set the
  PLAN deletion uses.

The function reuses the script's existing helpers (`check_issue_closed`,
`add_step`, `log_warn`) and the same path/issue plumbing the PLAN
deletion path already uses. There's no new state in the koto graph; the
state machine still pauses at `plan_completion` and runs the cascade
script, which now does the extra ROADMAP work when appropriate.

A future third working artifact would add a parallel
`handle_<artifact>_deletion()` function alongside this one. The pattern
is the contract.

## CLAUDE.md convention header

The project-level convention header lands in CLAUDE.md among the
existing `## Repo Visibility:` and `## Planning Context:` headers. The
shape:

```markdown
## Artifact Lifecycle: per-skill

shirabe artifacts are durable or working. Durable artifacts stay in
`docs/<dir>/` after completion as part of the project's audit trail.
Working artifacts retire when their completion condition holds, deleted
by the work-on cascade. Each producer-skill's SKILL.md names its
artifact's lifecycle in a `## Artifact Lifecycle` section — the
per-skill prose is authoritative. PLAN and ROADMAP are working; BRIEF,
PRD, DESIGN, VISION, STRATEGY, and COMP are durable.
```

The header points at the per-skill prose rather than restating each
artifact's rule. That keeps the eager-load surface in CLAUDE.md bounded
to one paragraph and keeps the per-skill prose the single source of
truth.

## Migration posture

Migration is lazy. There's no bulk-migration commit, no one-time script,
and no author intervention required.

A ROADMAP already in `docs/roadmaps/` keeps its current state. The
cascade's deletion check runs against it on the next /work-on cycle that
traverses its chain. If every feature is Done and every referenced issue
is closed at that moment, the cascade retires the ROADMAP in the same
finalization commit it would have created anyway. If not, the ROADMAP
stays and the next cycle will check again.

Older ROADMAPs predating the lifecycle schema may lack a status field.
The cascade treats a missing status as `Active` for the purpose of the
completion check — they participate in the same deterministic check
without any re-stamping.

The posture is intentional. Bulk-migration would touch files unrelated
to the PR's intent, expand the diff, and risk breaking in-flight work
that references the ROADMAPs. The cascade is idempotent (by design), so
the lazy approach converges on the same end state without the
collateral.

## What this does NOT add

This change is prose and bash. It explicitly does not introduce:

- **No new shirabe CLI subcommand.** The cascade extension is a shell
  function in the existing `run-cascade.sh`, not a new `shirabe`
  subcommand. Authors don't gain a new verb to invoke.
- **No new validator check.** The validator surface is untouched.
  `shirabe validate --lifecycle-chain <plan-path> --strict` runs
  unchanged against PLAN-rooted chains. There's no validator pass that
  reads the `## Artifact Lifecycle` sections.
- **No new schema field.** Frontmatter schemas are unchanged. The
  contract lives in skill prose, not in a `schema: skill/v1` field.

A future amplifier-layer extension could add validator surface (for
example, a check that every producer-skill has the section). That work
is deferred and is outside this release. The first contract is prose;
tooling enforcement is the next layer.

## References

- PRD: `docs/prds/PRD-shirabe-artifact-decision-contract.md`
- DESIGN: `docs/designs/DESIGN-shirabe-artifact-decision-contract.md`
- PLAN: `docs/plans/PLAN-shirabe-artifact-decision-contract.md`
- PLAN lifecycle template source:
  `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`
- Cascade script: `skills/work-on/scripts/run-cascade.sh`
- ROADMAP format reference: `skills/roadmap/references/roadmap-format.md`
