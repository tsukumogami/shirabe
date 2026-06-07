---
schema: brief/v1
status: Done
problem: |
  About two dozen inside-pattern ergonomics observations have accumulated
  across the nine shirabe child skills, each surfaced when the skill ran
  under non-ideal operating conditions — sub-agent dispatch, cold-start
  topics, automated approval, validators that miss what authors miss. The
  observations share a failure shape (silent degradation rather than loud
  failure), and treating them as one-offs lets the tax recur on every
  chain.
outcome: |
  An orchestrator running `/scope` or `/charter`, and an author invoking
  any child skill directly, encounters explicit fallback paths and
  explicit signals at every boundary where pattern v1 silently degraded.
  The chain's audit trail matches the chain's actual execution rather
  than the chain the prose assumed.
---

## Status

Done

Phase 4 jury returned all-PASS as serial-self-jury under sub-agent
dispatch from /scope; the independence-loss caveat is recorded in
both verdict files. The downstream PRD picks up the per-observation
disposition (skill-prose fix, reference-content fix, validator
extension, or deferred-indefinitely) and the inside-pattern
sequencing that accounts for skill-coupling.

## Problem Statement

Shirabe's parent-skill pattern v1 — the contract that lets `/scope`,
`/charter`, and the workflow children compose into chain workflows —
has been dogfooded twice now. The v0.7.0/0.7.1-dev round (during the
`/comp` skill authoring and the child-dispatch-contract work) surfaced
seventeen distinct ergonomics themes plus a load-bearing team-lead
operating discipline observation. The v0.9.0/v0.9.1-dev round (during
this very chain's authoring) re-confirmed several themes against the
Rust-cutover codebase and added a handful of fresh observations the
new substrate exposed. Across the two rounds, about two dozen
inside-pattern observations now sit against the nine child skills,
the parent-pattern reference, the format references, and the
validator.

Read individually, the observations look like a backlog of unrelated
nits. Read together, they reveal a pattern. The child skills' prose
was written for the ideal conditions a top-level author invocation
presents — the Agent tool is available, the user is at the terminal
to answer `AskUserQuestion`, the `wip/` directory was empty before
this run, the `shirabe` CLI on disk matches the version the skill
prescribes, and the validator catches what authors miss. Every one
of those assumptions is broken when an orchestrator (the most common
caller of the children today) is dispatching them. The orchestrator
invokes children as sub-agents, hands them fresh topics with no
upstream, automates approval, runs against whatever shirabe binary
the workspace happens to have installed, and is itself a substrate
the per-skill validators don't see. The pattern's prose silently
degrades to "whatever the dispatched sub-agent improvises in the
moment."

The failure mode is silent degradation, not loud failure. The Phase
4 jury that nominally fans out into three independent reviewers
collapses to one agent doing serial self-review and the verdicts
read PASS. The Resume Logic table doesn't know about the
`parent_orchestration` sentinel and re-prompts as if the run were
cold-started. The "approximately 110 lines" budget written into a
DESIGN ships at 183 lines and the validator exits 0. The CLI
version-skew between the skill's prescribed `shirabe transition`
and the on-disk binary fails open with "unknown command". Each
individual failure recovers via operator improvisation, but every
chain pays the same tax, and the tax compounds — by the time the
orchestrator reaches `/plan`, the silent degradations from
`/brief`, `/prd`, and `/design` have all accumulated into a chain
whose audit trail no longer reflects what actually happened.

The observations cluster into six fix surfaces:

- **Sub-agent dispatch fallbacks** across `/brief`, `/prd`,
  `/design`, and `/plan` — each Phase 4/5/jury/AskUserQuestion site
  needs an explicit "Running as a sub-agent" path naming the
  serial-self-jury, parent-delegated-approval, or inline-substitute
  variant.
- **Resume Logic sentinel-awareness** in child skills — the tables
  enumerate `wip/`-file conditions but not the
  `parent_orchestration` sentinel a cold-spawned sub-agent reads its
  routing context from.
- **Phase prose clarifications** for forward-looking gate
  evaluation, slug-convention detection, plugin-path resolution,
  public-cleanliness grammar, the canonical Open-Questions closure
  surface, `/design` Implementation Issues ownership, decision-skill
  bypass conditions, `wip/` carve-out for skill-runtime
  documentation, eval-fixture line-1 marker constraints, the actual
  release-notes mechanism the workspace ships, and content
  boundaries for skill-specifying artifacts.
- **Cross-skill consistency** for PLAN/DESIGN field contracts
  across sibling issues and PLAN AC anchor-existence pre-flight.
- **Validator extensions** for content-budget enforcement, the
  schema silent-skip exit-code, `/design` Phase 6's missing
  structural-format reviewer, and `/plan`'s single-pr
  `## Implementation Issues` contract drift.
- **Team-lead operating discipline** — the never-go-idle
  sleep-check-nudge loop the orchestrator must run after every
  dispatch.

Plus the boundary observation: skill bodies prescribe `shirabe
transition` without preflight-checking the installed CLI version
against the version the subcommand was added in.

The common shape across the six clusters is "the skill prose
assumed ideal conditions; the operating conditions weren't ideal;
the assumption silently degraded." Treating these as one unit
keeps the framing honest about what's being fixed — not twenty-four
unrelated nits, but a pattern's response to the conditions its
callers actually present.

## User Outcome

An orchestrator running `/scope` reaches the terminal PLAN through
a chain whose every Phase 4 jury, Phase 5 approval site, Resume
Logic table, format reference, validator check, and convention
prompt has acknowledged its operating context and named what it
did about that context. Silent degradation is replaced by explicit
signal at the boundary.

The author reading the resulting docs cold — whether to review the
chain or to author downstream work against it — finds an audit
trail that matches the chain's actual execution. The Phase 4
verdict file says "serial-self-jury under sub-agent dispatch;
independence loss caveat noted" rather than appearing to be a
parallel jury that wasn't. The DESIGN's Implementation Issues
table doesn't drift between what `/design` prescribes and what
`/plan` consumes. The validator's exit-0 means what the operator
thinks it means — that the artifact's structure was checked, not
that the validator quietly skipped a check because the schema
field was missing.

An author invoking a child skill directly — outside the
orchestrator path — also benefits. The Resume Logic table accounts
for the routing field a future caller might set; the
slug-convention prompt fires when the author's first guess didn't
match the repo's precedent; the CLI version-skew preflight catches
the install-skew before the skill body's prescribed subcommand
fails. The child skills compose cleanly under the parent pattern
they were built for, but they also stand alone for authors who
need to enter the chain partway up.

The center of gravity is operator trust. Today, a shirabe operator
running `/scope` knows from experience that some Phase 4 verdicts
are self-reviews, some convention prompts are missing, some
validator checks silently skipped, and the resulting docs may not
say so. After this work, an operator reads the chain's outputs
and trusts that what the docs say is what happened.

## User Journeys

### Orchestrator dispatches a child whose Phase 4 jury can't fan out

A shirabe maintainer runs `/scope <topic>` and the parent
orchestrator dispatches `/prd` as a sub-agent. `/prd` reaches
Phase 4 — the three-reviewer jury (completeness, clarity,
testability) is prescribed to fan out via the Agent tool with
`run_in_background: true`, but the sub-agent context the
orchestrator runs `/prd` in does not surface that tool. The
skill's Phase 4 reference now has an explicit "Running as a
sub-agent" section that prescribes serial-self-jury against the
same three rubrics, names the independence-loss caveat that the
verdict files must surface, and tells the sub-agent to record
the operating context in the verdict's preamble. The orchestrator
sees the verdicts as PASS-with-caveat and proceeds without
operator intervention. The chain's audit trail says what
happened.

### Author runs /scope on a fresh topic with no upstream

A shirabe maintainer types `/scope shirabe-pattern-v1-ergonomics`
to start a new chain — no existing BRIEF, PRD, DESIGN, or PLAN at
the topic, no roadmap entry, nothing for Phase 1 to shift framing
FROM. The opener no longer poses a vacuous "what shifts the
framing" question; Phase 1 detects the cold-start condition and
short-circuits the framing-shift opener. The R6 forward-looking
predicates that inspect a PRD body now evaluate the projected
PRD's expected content shape rather than reading from a file that
doesn't exist; `/design` fires tentatively when the topic implies
architectural alternatives, with a re-evaluation gate after `/prd`
lands.

### Author types a slug that drifts from the repo's convention

A shirabe maintainer types `/scope brief-skill-update` in a repo
whose existing artifacts use the `shirabe-` prefix
(`BRIEF-shirabe-brief-skill.md`, `PRD-shirabe-scope-skill.md`,
etc.). Phase 0 samples the existing artifacts, detects the
prefix convention, and prompts the author: "Existing artifacts
use the `shirabe-` prefix. Use `shirabe-brief-skill-update`
instead?" The author accepts; the slug is corrected before any
`wip/` file or BRIEF draft commits to the wrong name. A
downstream reader landing on the resulting BRIEF sees the
convention honored.

### Downstream author traces an upstream framing without re-reading every parent reference

A shirabe maintainer reads a child SKILL.md to understand a
single phase. The SKILL.md no longer restates the topic-slug
regex, the visibility detection algorithm, and the
`parent_orchestration` sentinel-handling rules verbatim from
the pattern-level references — it cites them by path and trusts
the reader to follow the citation when they need the detail.
Context budget is preserved. Cross-skill consistency is
preserved because the canonical statement lives in one place.

### Validator catches a content-budget overshoot

A shirabe maintainer ships a DESIGN section whose spec wrote
"approximately 110 lines" and the section ships at 183 lines
(60% over). `shirabe validate` (or the `/design` Phase 6 jury,
depending on which surface the disposition lands on) surfaces
the overshoot — either as a soft-warning lane finding or as a
structural-format reviewer flag — rather than exiting 0. The
operator knows to revise before the DESIGN is consumed by
`/plan`.

## Scope Boundary

**IN scope:**

- The ~24 inside-pattern observations consolidated from the two
  dogfooding rounds, across the nine shirabe child skills, the
  parent-pattern reference, the format references, and the
  validator.
- The six fix-surface clusters (sub-agent dispatch fallbacks,
  Resume Logic sentinel-awareness, phase prose clarifications,
  cross-skill consistency, validator extensions, team-lead
  operating discipline) plus the CLI version-skew preflight.
- Sequencing concerns inherent to the cluster set — for
  example, the parent-pattern reference edits land before the
  per-skill consumers that inherit from them, and validator
  extensions land alongside or after the prose changes that
  reference them.
- Treating the observations as a coordinated single umbrella
  effort because the failure shape (silent degradation under
  non-ideal operating conditions) is shared across the set.

**OUT of scope:**

- The amplifier-layer mandate refinement work tracked in
  `tsukumogami/vision#535`. Those observations require
  substrate primitives (durable team state as source of truth,
  idle-notification filtering at the substrate level, structured
  team-shape declarator, live team query, nested teams,
  coordinator-side lazy spawning, separate parent/team task lists,
  message-ordering guarantees) that the inside-pattern cannot
  supply. Hard-blocked on the koto composability extensions work.
- The per-skill artifact-decision contract — whether each child
  skill should produce a durable artifact or hand-off to its
  downstream consumer. That work is tracked separately on the
  shirabe roadmap and overlaps the BRIEF altitude only
  incidentally.
- Standalone shirabe BUG-class issues that don't fit the
  pattern-ergonomics frame. The dogfooding window also surfaced
  ~7 standalone bugs (some already filed:
  `tsukumogami/shirabe#155`, `#157`, `#158`, `#160`, `#161`,
  `#163`, `#164`). Each stays open as its own work stream and
  is not coordinated by this brief.
- The solution shape per observation. The fix-candidate
  alternatives for each observation (for sub-agent dispatch
  fallbacks: an explicit `Running as a sub-agent` section in
  each child vs. a pattern-level marker convention vs. a shared
  parent-pattern fallback site that all four tactical skills
  inherit; for validator content budgets: a `/design` Phase 6
  jury extension vs. a validator soft-warning lane vs. removing
  the budget ACs entirely) are downstream DESIGN territory. The
  brief commits to fixing the failure shape, not to a mechanism
  per observation.
- Refactoring of any child skill, the parent-pattern reference,
  or the validator beyond what the observation set actually
  requires. The brief frames an umbrella; it doesn't sneak in a
  rewrite under that umbrella.

## References

- `tsukumogami/vision#514` — narrowed Track A scope: the
  consolidated set of ~24 inside-pattern observations, the
  17-theme dogfooding comment, and the original SE12 framing.
- `tsukumogami/vision#535` — Track B: amplifier-layer mandate
  refinement, explicitly out of scope here.
- `friction-log-shirabe-0.9.0.md` — workspace-level friction
  log from the v0.9.0/v0.9.1-dev dogfooding round that confirmed
  the v0.7.0-era observations on the post-Rust-cutover codebase
  and added the fresh surfaces (`/design` Phase 6 missing
  structural-format reviewer, `/plan` Phase 7 single-pr
  `## Implementation Issues` contract drift, `/work-on` koto
  orchestrator deterministic-mode overhead).
- `docs/briefs/BRIEF-shirabe-pattern-v1-workflow-friction.md` —
  prior brief in the same workspace that named the three-bug
  silent-by-default failure shape; precedent for the
  "umbrella over multiple observations sharing a failure
  shape" framing this brief inherits.
