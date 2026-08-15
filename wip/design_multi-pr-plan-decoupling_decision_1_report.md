<!-- decision:start id="header-naming" status="confirmed" -->
### Decision: The two new CLAUDE.md convention headers -- names and value vocabulary

**Context**

R1-R9 of PRD-multi-pr-plan-decoupling.md need two new repo-level settings,
resolved through the existing `flag > CLAUDE.md-header > default` precedence
chain that `## Roadmap Issues:` and `## PR Grouping Policy:` already use:

- a **delivery-shape preference**, values `consolidated|atomic` (R2), that a
  repo states once so plans stop re-arguing whether to split (R1, R4)
- a **tracking level**, values `none|issues|issues-and-milestone` (R8), that a
  repo states independently of delivery shape (R7)

R3 forbids naming the first `Execution Mode` -- that name is taken by the
autonomy header (`auto|interactive`) and by the PLAN frontmatter field of the
same name. R17 requires both to be documented in
`references/fixes/claude-md-conventions.md` alongside the existing six-header
registry. The nine headers actually in play (six documented in the registry's
cross-reference list, plus three more shipped in shirabe's own `CLAUDE.md`
but not yet mirrored into the registry) are: `Repo Visibility`,
`Planning Context`, `Default Scope`, `Execution Mode`, `Roadmap Issues`,
`Release Notes Convention`, `PR Grouping Policy`, `Reviewability Ceiling`,
`Artifact Lifecycle`.

**Assumptions**

- The registry gap (PR Grouping Policy, Reviewability Ceiling, and Artifact
  Lifecycle live in shirabe's `CLAUDE.md` but not in the registry's
  cross-reference list) is pre-existing and out of this decision's scope; R17
  only obligates documenting the *two new* headers, not backfilling the three
  already-missing ones.
- "Survives the feature growing a threshold later" means: if a numeric
  reviewability ceiling for plan-altitude splits is added later (Known
  Limitations flags this as unresolved, Out of Scope explicitly declines to
  define it now), the chosen header name should not need to change to
  accommodate that.

**Chosen: `## Delivery Preference: consolidated|atomic` and `## Tracking Level: none|issues|issues-and-milestone`**

**Rationale**

Both names are lifted directly from the PRD's own Definitions section rather
than invented fresh:

- Definitions: *"Consolidated / atomic -- the two delivery preferences."*
  &rarr; `## Delivery Preference:`
- Definitions: *"Tracking level -- which GitHub artifacts a plan's work items
  get: `none`, `issues`, or `issues-and-milestone`."* &rarr;
  `## Tracking Level:`

This matters for more than tidiness. The PRD's Definitions section
deliberately distinguishes **delivery shape** (the *outcome* --
`single-pr`/`multi-pr`, i.e. which `execution_mode` value results) from
**delivery preference** (the *input* -- `consolidated`/`atomic`, the setting a
repo states). R1/R2 call the resolved setting a "delivery-shape preference,"
which reads as ambiguous shorthand for the same input/output pair. A header
literally named `Delivery Shape` would invite a reader to expect it holds
`single-pr`/`multi-pr` -- the outcome vocabulary R4 already produces and
writes to `execution_mode` -- not `consolidated`/`atomic`. Naming the header
after the *preference* half of that pair, matching the Definitions entry that
already carries the values verbatim, removes that ambiguity: the header is
unambiguously the knob, not the readout.

Neither name collides with the nine existing headers:

- `Delivery Preference` shares no word with any of them. The nearest
  neighbor by topic is `PR Grouping Policy` (also governs how many pull
  requests result from a plan), but that header is scoped to coordinated
  multi-repo efforts and the coarsest-legal-grouping rule
  (`references/coordination-strategy.md`), while the new header is scoped to
  a single-repo plan's `execution_mode` resolution (R1-R6). Sharing "PR" in
  the name (candidates considered and rejected below) would actively invite
  a reader to wonder whether the two headers are the same setting at
  different altitudes; "Delivery Preference" avoids the word entirely and
  keeps the altitude distinction clean without help from prose.
- `Tracking Level` shares no word with any of them, including `Roadmap
  Issues` (a different altitude -- roadmap-populate issue-per-feature
  filing, not plan-level work-item tracking) and `PR Grouping Policy` /
  `Reviewability Ceiling` (coordination-altitude, not tracking).

A reader scanning shirabe's `CLAUDE.md` top-to-bottom, having already read
`## PR Grouping Policy: coarsest-legal` and `## Reviewability Ceiling:
default`, hits `## Delivery Preference: atomic` immediately after and reads
it correctly as "the single-repo-plan analog of the grouping policy above,"
without needing the cross-reference table to explain it. `## Tracking Level:
issues` is self-explanatory purely from its value vocabulary.

Both names survive a later reviewability-threshold addition. A numeric
ceiling for plan-altitude splits, if added, would most naturally extend
`Reviewability Ceiling` itself (already the ceiling header, already
`flag > header > default`-resolved) or attach as a value suffix on
`atomic`, not require renaming `Delivery Preference`. `Tracking Level` is
already a closed three-value enum with room to grow a fourth value without
a name change.

**Alternatives Considered**

- **`PR Shape: consolidated|atomic` / `Issue Tracking: none|issues|issues-and-milestone`.**
  Rejected: "PR Shape" reintroduces the word "PR," which sits one header away
  from `PR Grouping Policy` in shirabe's own `CLAUDE.md` -- both would read as
  governing "how many PRs," and only prose (not the names) would tell a
  reader that one is single-repo-plan-altitude (R1-R6) and the other is
  coordinated-multi-repo-altitude (`coordination-strategy.md`). "Issue
  Tracking" collides in spirit with `Roadmap Issues` (also uses "Issues"),
  inviting the question of whether `Issue Tracking: issues` and `Roadmap
  Issues: required` are the same knob at different altitudes -- they are not
  (R10 explicitly exempts coordinated plans, and roadmap issue-filing is
  Out of Scope per the PRD's own boundary).

- **`Work Delivery: consolidated|atomic` / `Work Tracking: none|issues|issues-and-milestone`.**
  Rejected on traceability grounds, not collision. Both are collision-free
  and internally parallel (shared "Work" prefix), but neither matches a term
  the PRD's Definitions section actually defines -- a reader connecting R1's
  "delivery-shape preference" or R7's "tracking level" prose to the header
  name has to bridge an extra hop ("Work Delivery" means "delivery-shape
  preference"?) that `Delivery Preference` / `Tracking Level` don't require.
  "Work Tracking" is also generic enough to be misread as an umbrella
  project-tracking setting unrelated to R7-R12's specific
  none/issues/issues-and-milestone enum.

- **`Split Preference: consolidated|atomic` / `Milestone Tracking: none|issues|issues-and-milestone`.**
  Rejected on a real semantic-mismatch ground, not a strawman. `consolidated`
  is defined as "prefer the fewest pull requests the work permits" -- it is
  not the *absence* of a splitting preference, it is a legitimate preference
  in its own right (this is the PRD's own point in Decisions and
  Trade-offs: "the maintainer who wants the fewest possible pull requests
  and the team that wants the smallest reviewable increments are both
  right"). Naming the header after splitting specifically frames
  `consolidated` as the null case, which contradicts R2's parity between the
  two values. "Milestone Tracking" actively misdescribes the `issues`
  (no-milestone) middle value of R8's three-value enum -- a repo stating
  `issues` gets issues with no milestone, so a header named after the
  milestone alone reads backwards for exactly the case R9's default-vs-flag
  distinction exists to preserve.

**Consequences**

- `references/fixes/claude-md-conventions.md`'s cross-reference list gains
  two new rows using these exact header strings; R17's acceptance criterion
  ("the delivery-shape header's name is not `Execution Mode`, and it and the
  autonomy header appear as separate rows") is satisfied structurally, not
  just by avoiding the literal banned string.
- Because both names are pulled verbatim from the PRD's Definitions section,
  no follow-on rewording of the Definitions section is needed to keep
  prose and header vocabulary in sync -- they already match.
- The registry gap noted under Assumptions (PR Grouping Policy, Reviewability
  Ceiling, Artifact Lifecycle absent from the cross-reference list) remains
  open after this change; it is pre-existing and not created or worsened by
  it, but a future pass documenting those three would make the registry
  fully self-consistent.
<!-- decision:end -->

<!-- decision:start id="header-value-spelling" status="confirmed" -->
### Decision: Should the PRD's value spellings survive as-written?

**Context**

R2 fixes delivery-preference values as `consolidated|atomic`; R8 fixes
tracking-level values as `none|issues|issues-and-milestone`. The question is
whether either spelling should change to match the existing header corpus's
conventions before being written into `references/fixes/claude-md-conventions.md`.

**Assumptions**

None beyond what's stated in the PRD and the registry.

**Chosen: Keep both value spellings exactly as R2 and R8 fix them -- no change.**

**Rationale**

The existing corpus splits into two casing families:

- Capitalized, single-word-per-value: `Public|Private` (Repo Visibility),
  `Strategic|Tactical` (Planning Context).
- Lowercase, kebab-case for multi-word values: `auto|interactive` (Execution
  Mode), `optional|required` (Roadmap Issues), `coarsest-legal` (PR Grouping
  Policy), `default` (Reviewability Ceiling).

The lowercase family is the more recently established one -- it covers every
header that, like the two new ones, resolves through the explicit
`flag > CLAUDE.md-header > default` precedence chain documented in prose
(Roadmap Issues and PR Grouping Policy both say so verbatim; Reviewability
Ceiling says so too). The capitalized family (Repo Visibility, Planning
Context) predates that documented precedence pattern and reads more like a
category label than a resolved preference. Since R1 and R7 explicitly place
both new headers on the `flag > header > default` chain, they belong with the
lowercase family by precedent, and `consolidated`, `atomic`, `none`,
`issues`, `issues-and-milestone` are already lowercase and already
kebab-case where multi-word (`issues-and-milestone` matches the shape of
`coarsest-legal`). No respelling is needed or justified.

**Alternatives Considered**

- **Capitalize to match Repo Visibility / Planning Context** (`Consolidated|Atomic`,
  `None|Issues|Issues-And-Milestone`). Rejected: this would make the new
  headers the odd ones out relative to their closer siblings by function
  (PR Grouping Policy, Reviewability Ceiling, Roadmap Issues, Execution
  Mode -- all lowercase, all precedence-chain-resolved), not their siblings
  by superficial header position in the file.

**Consequences**

- The `claude-md-conventions.md` entries for both headers can copy R2's and
  R8's value strings verbatim with no transformation step, and no PRD
  acceptance criterion needs to change.
<!-- decision:end -->

<!-- decision:start id="reviewability-ceiling-scope" status="assumed" -->
### Decision: Should `## Reviewability Ceiling:` widen to plan altitude, or stay coordination-only?

**Context**

`## Reviewability Ceiling: default` currently reads, in shirabe's own
`CLAUDE.md`: "The configured reviewability ceiling for **a coordinated
effort**... defers to the ceiling defined in
`references/coordination-strategy.md`." Its threshold governs when a
coordinated multi-repo grouping splits a per-repo PR. The new
`Delivery Preference: atomic` setting introduces a second place where
reviewability motivates a split -- this time at plan altitude, within a
single repo (R4: "Under `atomic`, the workflow SHALL produce a multi-PR
shape whenever the decomposition permits one"). Nothing in R1-R20 makes
`atomic` consume a numeric threshold; it is a binary posture. Known
Limitations states this explicitly: "the delivery preference is a posture
rather than a threshold" until the ceiling "has one" -- and Out of Scope
separately excludes "Defining a concrete reviewability threshold" entirely,
independent of which header would hold it.

**Assumptions**

Widening a header's declared scope in prose, with no corresponding
consuming mechanism, is worse than leaving the scope unchanged -- it invites
a repo to set a value expecting an effect that does not exist. This decision
assumes the team would rather ship an honest gap (flagged in Known
Limitations, as the PRD already does) than a header whose documented
applicability outruns its implementation.

**Chosen: Leave `## Reviewability Ceiling:` coordination-only. Do not widen its declared scope in this change.**

**Rationale**

Three constraints point the same direction:

1. **No consuming mechanism exists.** R6 is explicit that the
   value-confirmation guard "SHALL continue to run, unchanged" under
   `atomic` -- it is a per-unit *value* check, not a size/reviewability
   check. Nothing in R1-R20 reads `Reviewability Ceiling` for plan-altitude
   decomposition. Widening the header's prose to claim plan-altitude
   relevance would describe a capability this PRD does not build.
2. **The PRD already scoped this out by name.** Out of Scope: "Defining a
   concrete reviewability threshold... This work does not supply one."
   Widening `Reviewability Ceiling`'s declared applicability is the same
   move as defining what it would mean at plan altitude -- it is the
   surface form of the thing already excluded, not a separate, cheaper
   documentation-only step.
3. **R17's obligation is narrow.** R17 requires documenting the *two new*
   headers "alongside the existing headers" -- it does not ask for edits to
   `Reviewability Ceiling`'s own text, and the acceptance criteria never
   mention it.

The PRD's Known Limitations section already carries the honest version of
this gap ("Until it has one, the delivery preference is a posture rather
than a threshold, and a repository cannot say *how* small it wants
increments"), which is the right place for it: visible to a reader, not
silently implied by a header whose prose reaches further than its
enforcement.

**Alternatives Considered**

- **Widen `Reviewability Ceiling` now to cover both altitudes, still with no
  numeric default.** Rejected: this is the option Known Limitations and Out
  of Scope both already argue against for the reasons above -- it would be
  documentation promising behavior (`atomic` respecting a configured
  ceiling) that R1-R20 do not implement, and the PRD's own author flagged
  exactly this gap as a cost carried forward rather than closed.
- **Introduce a separate plan-altitude ceiling header now, distinct from the
  coordination one.** Rejected: doubles the header surface for a threshold
  concept that, per Out of Scope, isn't being defined at all in this change
  -- there is no value to attach to either header yet, so adding a second
  empty one has no benefit over the single existing gap.

**Consequences**

- A follow-on that defines a concrete reviewability threshold (already
  gestured at by Known Limitations) will need to decide, at that time,
  whether it's one ceiling shared across both altitudes or two -- this
  decision leaves that question open rather than pre-committing it, since
  pre-committing now would require guessing at a threshold model this PRD
  deliberately doesn't build.
- No changes to `Reviewability Ceiling`'s existing prose in shirabe's
  `CLAUDE.md` or to its (currently missing) entry in
  `claude-md-conventions.md` are required by this PRD.
<!-- decision:end -->
