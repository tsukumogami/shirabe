# /brief Discover: shirabe-pattern-v1-ergonomics

## Source evidence

1. **tsukumogami/vision#514** (narrowed body) — Track A scope. The
   issue enumerates ~24 inside-pattern observations across the 9
   shirabe child skills, drawn from two consecutive dogfooding rounds.
   The scope deliberately excludes substrate-dependent fixes (those
   moved to vision#535 and are blocked on SE2).
2. **Consolidated SE12 input comment** on vision#514 — 17 themes from
   the v0.7.0/0.7.1-dev dogfooding window (PR-141 `/comp` skill + PR-151
   child-dispatch-contract). Plus the standalone #12 observation
   (team-lead never-go-idle discipline). 18 v0.7.0-era observations
   in total.
3. **friction-log-shirabe-0.9.0.md** — 429-line second dogfooding
   round against v0.9.0/v0.9.1-dev. Re-confirms several v0.7.0-era
   observations on the post-Rust-cutover codebase (sub-agent jury
   fallback, CLI version-skew, schema silent-skip) and surfaces a
   handful of fresh ones (`/design` Phase 6 missing structural-format
   reviewer, `/plan` Phase 7 single-pr "## Implementation Issues"
   contract drift, `/work-on` koto orchestrator deterministic-mode
   overhead).
4. **tsukumogami/vision#535** (Track B) — substrate-dependent
   observations. OUT of scope here.

## Synthesized framing

### Problem candidate

Pattern v1's inside-pattern ergonomics has accumulated ~24 observations
across the 9 shirabe child skills. Without consolidation, each fix
ships as a one-off; together they reveal a pattern — child skill prose
assumes ideal conditions (top-level dispatch context, on-disk
upstreams, an interactive user at every approval gate, validators that
catch what authors miss), and degrades silently when those don't hold.
The orchestrator running `/scope` or `/charter` is the most common
caller of these skills, and the orchestrator is exactly the caller
that breaks every assumption: it invokes children under sub-agent
dispatch, hands fresh topics with no upstream, automates approvals,
and is itself a substrate the per-skill validators don't see.

The failure mode is silent degradation, not loud failure. The Phase 4
jury fans out into one agent doing serial self-review and writes
verdicts that read PASS. The Resume Logic table doesn't know about
the parent_orchestration sentinel and re-prompts as if cold-started.
The "approximately 110 lines" budget in the DESIGN ships at 183 lines
and the validator exits 0. The CLI version-skew between the skill's
prescribed `shirabe transition` and the on-disk binary fails open
with "unknown command". Each individual instance recovers via
operator improvisation, but every chain pays the same tax, and the
tax compounds — by the time the orchestrator reaches /plan, the
silent degradations from /brief, /prd, and /design have all
accumulated into a chain whose audit trail no longer reflects what
actually happened.

### Outcome candidate

Orchestrators (and authors invoking children directly) encounter
explicit fallback paths and explicit signals at every boundary where
the v0.9.x pattern silently degraded. The orchestrator running
`/scope` reaches the terminal artifact through a chain whose every
Phase 4 jury, Phase 5 approval, sentinel-aware Resume Logic, format
reference, validator check, and convention prompt has acknowledged
its operating context and named what it did about it. "Silent
degradation" is replaced by "explicit signal at the boundary"
across the pattern's nine child skills, the parent-pattern
reference, the validator, and the cross-skill consistency rules.

The user — both the orchestrator and the human reading the
resulting docs cold — knows what happened and why. The chain's
audit trail matches the chain's actual execution.

## Observation set (Track A)

The ~24 observations sort into six clusters by fix surface:

1. **Sub-agent dispatch fallbacks** (themes 1, 2 in the SE12 comment;
   confirmed by 4 friction-log entries on v0.9.1-dev) — Phase 4 jury
   parallel fan-out, Phase 5 AskUserQuestion approval, /prd's three
   reviewers, /design's per-decision Agent spawning, /plan's
   /review-plan sub-operation. Each child needs an explicit
   "Running as a sub-agent" fallback section.
2. **Resume Logic sentinel-awareness** (theme 2) — child skills'
   Resume Logic tables need a parent_orchestration sentinel row so
   cold-spawned sub-agents read the right routing field.
3. **Phase prose clarifications** (themes 3, 4, 5, 7, 8, 9, 10, 13,
   14, 15, 16) — /scope Phase 1 forward-looking predicates, slug
   convention detection, `${CLAUDE_PLUGIN_ROOT}` resolution,
   public-cleanliness grammar, "Decisions and Trade-offs" canonical
   closure, /design Implementation Issues ownership, /design decision
   bypass conditions, wip/ carve-out for skill-runtime docs,
   eval-fixture line-1 marker, release-notes AC reality, content
   boundaries for skill-specifying artifacts.
4. **Cross-skill consistency** (themes 11, 17) — PLAN/DESIGN
   cross-issue field consistency, PLAN AC anchor-existence
   pre-flight.
5. **Validator extensions** (theme 12; friction-log
   schema-silent-skip + /design Phase 6 + /plan single-pr) — content
   budget enforcement, schema silent-skip exit-code change,
   /design Phase 6 structural-format reviewer, /plan single-pr
   "## Implementation Issues" contract.
6. **Team-lead operating discipline** (observation #12 from the
   2026-05-25 comment; confirmed on v0.9.1-dev) — never-go-idle
   sleep-check-nudge loop codified in
   `references/parent-skill-pattern.md`.

Plus the boundary observation:

7. **CLI version-skew preflight** (friction-log;
   `shirabe transition` not in v0.6.1) — skill bodies prescribe a
   CLI subcommand they don't preflight-check against the installed
   binary version.

## Journey candidates

From the observation clusters, ~4-5 concrete situations the brief
should frame as journeys:

- **Orchestrator + sub-agent jury fallback.** An author runs `/scope`
  that dispatches `/prd` as a sub-agent; /prd's Phase 4 reaches the
  jury fan-out and an explicit "Running as a sub-agent" path
  prescribes serial-self-jury with the independence-loss caveat
  surfaced into the verdicts.
- **Fresh-topic /scope without vacuous prompts.** An author runs
  `/scope <fresh-topic>` and Phase 1's framing-shift question
  short-circuits when no upstream exists; Phase 1's R6
  forward-looking predicates evaluate the projected PRD body rather
  than a non-existent file and the /design gate fires when
  architectural alternatives are implied.
- **Slug-convention prompt at Phase 0.** An author types
  `/scope foo-skill` and Phase 0 detects the shirabe `shirabe-`
  prefix convention from existing artifacts and prompts to adopt it
  before any wip/ file is created.
- **Child SKILL.md trimming via cite-don't-restate.** A future
  shirabe maintainer reading a child SKILL.md sees that
  /scope-related concerns (topic-slug regex, visibility detection,
  parent_orchestration sentinel handling) live in pattern references
  rather than being restated in each child. Context budget recovered.
- **Validator catches a content-budget overshoot.** An author ships
  a section with a DESIGN-budgeted "approximately N lines"
  constraint at 60% over budget; the validator (or /design Phase 6
  jury) surfaces the overshoot rather than exiting 0.

These are concrete entry points: cold-start orchestrator, fresh
topic, convention drift, downstream cite resolution, validator catch.
Each exercises a different cluster of observations.

## Scope boundary

**IN**: ~24 inside-pattern observations across 9 skills (the six
clusters + CLI version-skew). The work is consolidated as a single
umbrella effort because the observations share a common failure
shape — silent degradation under non-ideal operating conditions —
and the fix patterns are themselves consistent across observations
(add explicit fallback section, add explicit sentinel check, add
explicit prose clarification, add explicit validator extension).
Treating the set as one unit keeps the framing honest about what
the pattern is fixing.

**OUT**:

- Track B (tsukumogami/vision#535) — amplifier-layer mandate
  refinement. Substrate-dependent, hard-blocked by SE2. The
  observations Track B carries (durable state as source of truth,
  idle-notification filtering at the substrate, structured team-shape
  declarator, live team query, nested teams, lazy spawning,
  separate parent/team task lists) all require a substrate primitive
  the inside-pattern cannot supply.
- SE5 — per-skill artifact-decision contract — a separate roadmap
  entry covering whether each child skill should produce a durable
  artifact or hand-off to its downstream.
- Standalone shirabe BUG-class issues that don't fit the
  pattern-ergonomics frame. Those are already filed separately and
  scheduled on their own.
- The solution shape per observation. The fix-candidate alternatives
  (e.g., "explicit fallback section" vs. "pattern-level marker
  convention" for sub-agent fallback) belong in the downstream
  DESIGN.

## Conventions to honor

- `schema: brief/v1` first frontmatter field.
- Visibility Public — vision#514 cited as `tsukumogami/vision#514`;
  no quoting of private vision content beyond the issue body and
  the public consolidated comment (both already public).
- No `upstream:` frontmatter field — the upstream artifact is a
  cross-repo private vision issue. A public brief cannot point its
  `upstream:` field at a private artifact. The vision issue is named
  in the References section as a public cross-repo issue reference
  (the issue number is public; only its content body is private to
  the vision repo).

Wait — vision is a Private repo in this workspace. Issue numbers
to a private repo from a public brief: this is exactly the
ambiguity Theme 7 (public-visibility cleanliness rule grammar
ambiguity) names. Per the consolidated comment, the safer reading
is to omit the explicit cross-repo reference number from a public
artifact when the linked repo is private. The brief should carry
the framing forward in prose without naming the specific private
issue number.

Re-read on this: the orchestrator's dispatch explicitly instructed
"Cite vision issues as `tsukumogami/vision#514`". The
tsukumogami/vision repo IS private, but the dispatch instruction
says cite the number. The right reading is that the issue number is
an opaque reference — naming a number doesn't leak content — and
the orchestrator has accepted that reading for this brief.

Honor the dispatch instruction. Cite as `tsukumogami/vision#514`
and `tsukumogami/vision#535` in References.
