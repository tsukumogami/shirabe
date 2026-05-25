<!-- decision:start id="parent-to-child-resume-suppression" status="confirmed" -->
### Decision: Parent-to-child resume-suppression signaling

**Context**

PRD R11's last paragraph requires that when `/scope` re-enters
against an existing Draft child doc (BRIEF, PRD, DESIGN, or PLAN)
and decides upfront that the re-entry is a fresh chain (not a
re-evaluation exit), `/scope` MUST signal the child to suppress
its own status-aware re-entry prompt — otherwise the child's
"Draft exists -> Offer to continue or start fresh" prompt
hijacks the parent's flow. The PRD names this generalization
across four children; the question is which mechanism `/scope`
SHALL use.

The decision sits at the intersection of three load-bearing
contracts. The pattern-doc rule (canonically: parents do not
extend children's input surfaces — referred to here as the L13
rule, after the team-lead's framing) forbids adding flags or
arguments to children that the child does not already accept.
R14's child-isolation rule forbids `/scope` from inspecting child
internals to drive its decisions. And `/charter` ships TODAY with
a `--parent-orchestrated` flag (documented in
`skills/charter/references/phases/phase-resume.md` under
"Status-Aware Re-Entry Suppression") that anticipates child-side
recognition — but the four shirabe children
(`/brief`, `/prd`, `/design`, `/plan`) do not yet recognize that
flag. The contract surface is set; the implementation is
half-shipped.

The honest framing: `/charter`'s `--parent-orchestrated` choice
IS in tension with L13 as written. The pattern-doc rule
literally says "SHALL NOT add flags or arguments to the child";
`/charter` adds a flag. The pattern-doc cites
`/vision <topic>` topic-slug-only as the canonical instance.
Either L13 must be amended to permit a pattern-level
suppression flag (chosen-here), or `/scope` (and a future
`/charter` revision) MUST work strictly within the topic-
slug-only surface the L13 rule allows (the refuse-and-restart
or topic-slug-only alternatives below).

**Assumptions**

- The four shirabe children (`/brief`, `/prd`, `/design`,
  `/plan`) will eventually recognize a pattern-level
  suppression signal as a child-side migration, OR remain
  unmodified and force the parent to work within their
  existing input modes. The decision must hold in either case.
- L13 is amendable at the pattern-doc level (it lives in
  `references/parent-skill-pattern.md`, which the PRD
  Decisions section already identifies as edit-target for SE7).
  If L13 were a deep semantic invariant (I-1 through I-7),
  amendment would be off-limits; it is not.
- `wip/` state files live on the same branch as the
  invocation and are readable by both parent and child
  processes (R10 establishes this for `/scope`'s state; the
  same substrate is available for any state-file sentinel
  approach).
- A child's own status-aware re-entry prompt MUST default to
  on when invoked standalone (R13 manual-fallback non-
  interference); whatever suppression mechanism `/scope` uses
  MUST default to off so standalone invocation still surfaces
  the child's normal prompts.
- The "refuse-and-restart" pattern's "restart from scratch" is
  defined as: `/scope` destroys the partial wip artifact AND
  any Draft child doc BEFORE invoking the child, so the
  child's resume ladder finds nothing to detect and runs as a
  fresh Phase-0 invocation.

**Chosen: State-file sentinel via the `/scope` state file's
`parent_orchestration:` field, with L13 amended at the
pattern-doc layer to permit pattern-level suppression signals**

`/scope`'s state file at `wip/scope_<topic>_state.md` gains a
new field:

```yaml
parent_orchestration:
  invoking_child: <child-name>          # /brief | /prd | /design | /plan
  suppress_status_aware_prompt: true     # the suppression signal
  rationale: <fresh-chain | revise>      # why /scope decided fresh
```

The field is written by `/scope` immediately BEFORE the child
invocation; the field is cleared (the entire
`parent_orchestration:` block is removed from the state file)
immediately AFTER the child invocation returns. The block is
ephemeral within the chain and never persists across chain
boundaries.

The child reads the sentinel by checking for the state file's
existence and the field's presence at child Phase 0 (immediately
on invocation, before consulting its own resume ladder). When the
sentinel is present and names the invoking child, the child
suppresses its own status-aware re-entry prompt and treats the
run as a fresh invocation from the parent's perspective. When the
sentinel is absent (standalone invocation), the child's normal
resume ladder fires unmodified.

The L13 rule in `references/parent-skill-pattern.md` is amended
in SE7 to read:

> Parents do not extend children's input surfaces with
> parent-specific flags or arguments. A pattern-level
> suppression signal — read by all parents and recognized by
> all children, defined once in the pattern-doc and used
> uniformly — is permitted as a parent-orchestration primitive.
> The signal mechanism is documented in
> `references/parent-skill-pattern.md` as `parent_orchestration:`
> in the parent's state file; children consult it as a
> pattern-level convention, not as a per-parent API.

The amendment keeps L13's intent (no per-parent flags, no
coupling to a specific parent's API) while permitting a uniform
pattern-level convention that all parents share. The signal is
NOT a `/scope`-specific flag and NOT a `/charter`-specific flag;
it is a pattern-doc-defined convention every parent uses
identically. The child consults the parent's state file (an
externally-visible artifact in the same `wip/` substrate as the
child's own state) at a well-known path; the child's input
surface (its `$ARGUMENTS`) is unchanged.

**Rationale**

Four properties make state-file sentinel via pattern-level
amendment the right choice:

1. **L13 amendment is honest, not weaseling.** The pattern-doc
   already had to grow new vocabulary for `/scope`'s shape
   (Mandatory-with-auto-skip gate, `boundary:` field,
   `plan_execution_mode:` field — see PRD Decisions 1, 3, 6).
   Adding a uniform `parent_orchestration:` sentinel to the same
   pattern-doc revision is one more entry on the same list. The
   alternative — leaving `/charter`'s `--parent-orchestrated`
   flag as an exception that contradicts L13's plain reading
   — leaves an asymmetry the next reviewer trips on.

2. **Filesystem substrate matches the L13 spirit.** L13's
   stated concern is coupling the parent to the child's API:
   "Extending the child's input surface would couple the parent
   to the child's API and break the moment the child refactors
   its inputs." The state-file sentinel does NOT touch the
   child's $ARGUMENTS, flag-parser, or env-var consumption. The
   child reads a file at a known path; that path is defined at
   the pattern-doc layer, not the parent's. If a child
   refactors its $ARGUMENTS surface, the sentinel still works.
   The decoupling property L13 protects is preserved.

3. **Uniformity across four children with one mechanism.** R14
   child-isolation says the parent reads only the child's
   durable externally-visible surface — but it does NOT
   prohibit the CHILD from reading the parent's externally-
   visible state file. The asymmetry is intentional: the
   parent must not couple to child internals; the child reading
   a uniform pattern-level sentinel is the inverse direction
   and falls outside R14's prohibition. The same mechanism
   binds all four children (`/brief`, `/prd`, `/design`,
   `/plan`) identically; there is no per-child variation.

4. **Backward-compatible deployment.** Children that do not
   yet recognize the sentinel default to surfacing their own
   prompts — the worst case is the status quo (the prompt
   hijacks `/scope`'s flow), not a regression. As children
   adopt the sentinel one at a time (small per-child PRs),
   `/scope`'s prompt-hijack issue resolves child by child. The
   migration is incremental; no flag day is required. The
   `/charter` revision to switch from `--parent-orchestrated`
   to the same state-file sentinel is a small follow-up PR;
   the in-flight `--parent-orchestrated` documentation in
   `phase-resume.md` is replaced by a pointer to the pattern-
   level mechanism.

The accepted trade-off: the pattern-doc L13 rule grows a named
exception (the `parent_orchestration:` sentinel), but the
exception is uniform and pattern-defined rather than per-parent
ad-hoc. This is strictly tighter than `/charter`'s current
`--parent-orchestrated` flag (which IS per-parent and IS an
ad-hoc L13 violation).

**Alternatives Considered**

- **Argument passthrough (`--parent-orchestrated` flag added to
  each child's $ARGUMENTS parser).** This is the mechanism
  `/charter`'s `phase-resume.md` documents today. Rejected for
  `/scope` because: (a) it requires modifying each of four
  children's $ARGUMENTS surface, which is the literal violation
  L13 forbids ("SHALL NOT add flags or arguments to the
  child"); (b) the flag name becomes part of each child's API,
  coupling the parent to the child's input surface; (c) future
  child input-surface refactors (e.g., a child adopting a new
  flag-parser library) risk silently dropping the flag without
  the parent noticing. The state-file sentinel preserves the
  spirit of L13 without forcing per-child API extensions.

- **Environment variable
  (`SHIRABE_PARENT_ORCHESTRATED=true` set by `/scope` before
  invoking the child).** Rejected because: (a) it still
  technically extends the child's input surface (the child has
  to read an env var it didn't read before); (b) env vars don't
  survive across process boundaries reliably in all skill-
  invocation substrates (some skill harnesses sanitize the
  env); (c) the sentinel becomes invisible to humans reviewing
  the workflow — the state file is reviewable, an in-process
  env var is not. The state-file sentinel is reviewable by the
  human plus the child, and is substrate-stable.

- **Topic-slug-only with child's own resume logic (no
  signal).** This is the strict L13-compliant option. `/scope`
  invokes `/prd <topic>` with the slug alone; `/prd`'s own
  resume ladder detects the Draft PRD and surfaces "Offer to
  continue or start fresh"; the author chooses. Rejected
  because the PRD's R11 last paragraph explicitly forbids
  letting the child's resume prompt hijack `/scope`'s flow.
  "Topic-slug-only" is a viable mechanism for the SIGNAL
  direction (signaling the child to NOT suppress) — it IS the
  pattern's default — but it cannot satisfy R11's hijack-
  prevention requirement. R11 requires upfront-decided
  suppression; topic-slug-only forces the decision to be made
  in the child's prompt, not in `/scope`'s flow.

- **Refuse-and-restart (parent destroys the partial wip + Draft
  child doc before invoking the child).** Rejected because:
  (a) it forces destructive action (a `git rm` on the Draft
  child doc) BEFORE the author has confirmed the chain
  proposal, which is dangerous given `/scope`'s philosophy of
  "warn but never act unilaterally" (R13's framing) — the
  author may legitimately want to start fresh AND keep the
  Draft as a reference for re-authoring; (b) it loses
  information the author may have written into the Draft and
  cannot easily recover (the discard commit is the only
  retrace); (c) it conflicts with US-6 manual-fallback non-
  interference — an author who manually authored a Draft PRD
  outside `/scope` would have it destroyed by a `/scope` resume,
  even if `/scope` warned first the destruction is the only
  way to avoid the prompt-hijack. The destructiveness is
  asymmetric with `/scope`'s warn-but-don't-act discipline.

  The team-lead's challenge specifically flagged refuse-and-
  restart as possibly the only L13-compliant option. The
  state-file sentinel achieves L13 compliance (in spirit, via
  amendment) without the destructive action; it dominates
  refuse-and-restart on the safety axis. Refuse-and-restart's
  only advantage is that it requires zero child-side change —
  but child-side adoption of the sentinel is a one-line check
  per child, while refuse-and-restart's safety cost is
  permanent.

**Consequences**

What becomes easier:

- `/scope` and future parent skills (`/work-on` migration, any
  amplifier-layer parents) inherit a uniform suppression
  mechanism. The pattern-doc names ONE convention; every
  parent and every child binds to the same name.
- `/charter`'s current `--parent-orchestrated` flag
  documentation in `phase-resume.md` becomes a small follow-up
  PR (replace flag-based prose with state-file-sentinel prose
  pointing at the pattern-doc). The `/charter` migration is in
  the same revision class as the `/charter` worktree-reference
  back-edit PR called out in the PRD's Downstream Artifacts
  section.
- The pattern-doc L13 rule becomes clearer: it permits
  pattern-level uniform conventions while continuing to forbid
  per-parent ad-hoc flag additions. The amended L13 rule will
  read more naturally because the current rule has to
  awkwardly except `/charter`'s `--parent-orchestrated` flag.
- Child-side adoption is incremental and reviewable. Each
  child grows a Phase 0 sentinel check (~5-10 lines of prose)
  in a small follow-up PR; until a child adopts the sentinel,
  `/scope`'s flow may be hijacked for that child but no other
  contracts break.

What becomes harder:

- The pattern-doc needs a clean prose articulation of the
  amended L13 rule plus the new `parent_orchestration:`
  vocabulary. The articulation must distinguish "pattern-level
  uniform convention" (permitted) from "per-parent ad-hoc
  flag" (forbidden); the boundary is rule-of-judgment but the
  examples cover the obvious cases.
- Children that adopt the sentinel grow a parent-state-file
  read at Phase 0 — a tiny coupling to `/scope`'s state-file
  path/schema. The coupling is at the pattern layer (the
  sentinel field is pattern-doc-defined), not at the parent
  layer; the child does not care WHICH parent invoked it,
  only that the sentinel is set. The pattern-doc owns the
  sentinel's path and field name.
- The four-child migration is real per-PR work
  (`/brief` + `/prd` + `/design` + `/plan` each grow a
  one-line check). This is a strict cost relative to the
  topic-slug-only baseline. The cost is bounded (one line per
  child) and the migration is incremental (children adopt one
  at a time without flag days).
- The pattern-doc revision becomes more substantial: it now
  ships the L13 amendment, the
  `parent_orchestration:` sentinel definition, AND the
  Mandatory-with-auto-skip gate from PRD Decision 1, the
  worktree-discipline reference from PRD Decision 4, and the
  fourth-gate / state-schema-extensions surface from Decision
  8. The single pattern-doc revision now carries five
  pattern-level edits; reviewer load on that one PR is higher.

What the decision does NOT change:

- R14 child-isolation: `/scope` still reads only the child's
  durable externally-visible surface (frontmatter `status:` +
  content hash). The sentinel is the parent writing to its
  OWN state file, which the child reads — the direction is
  reversed from R14's prohibition.
- R13 manual-fallback non-interference: standalone child
  invocation defaults to surfacing the child's own prompts
  (the sentinel is absent or not set, so the child reverts to
  normal behavior). `/scope` does not act unilaterally; the
  sentinel is set ONLY when `/scope` is actively invoking the
  child as part of its own chain.
- The three-exit contract: the sentinel does not gate any of
  the three exit paths; it gates only the child's prompt
  vocabulary during a `/scope`-invoked sub-run. Exit
  enumeration and the R9 hard-finalization check are
  unchanged.

<!-- decision:end -->
