---
topic: work-on-standalone-completeness
session: scope-work-on-standalone-completeness
visibility: Public
chain_started: 2026-09-13T00:00:00Z
last_updated: 2026-09-13T00:00:00Z
phase_pointer: phase-3
exit: UNSET
exit_artifacts: []
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
chain_ran:
  - child: brief
    started_at: 2026-09-13T00:00:00Z
  - child: prd
    started_at: 2026-09-13T00:00:00Z
  - child: design
    started_at: 2026-09-13T00:00:00Z
  - child: plan
    started_at: 2026-09-13T00:00:00Z
consolidation_judgments:
  - edge: prd->design
    verdict: keep
    preflight_exit: 0
    finding: >-
      The PRD holds the numbered requirements and the acceptance criteria, and
      the DESIGN holds neither. The DESIGN cites eleven requirements by number
      (R3, R5, R5a, R6, R9, R10, R13, R16b, R19, R19b, R22) and deliberately
      does not restate them - citation rather than restatement is the format's
      own rule. Absorbing the PRD would dangle every one of those citations and
      delete the contract an implementation is held to, which is the whole of
      what the acceptance criteria are for. Nothing in the DESIGN carries them.
    decided_at: 2026-09-13T00:00:00Z
  - edge: brief->prd
    verdict: absorb
    preflight_exit: 0
    finding: >-
      No content in the BRIEF is absent from the PRD. Its Problem Statement is
      restated in full (the PRD format requires a PRD to state its own problem),
      its User Outcome is carried by Goals, all four User Journeys map onto user
      stories plus R1/R2/R3/R11/R13/R15, and both halves of its Scope Boundary
      were verified covered by the completeness reviewer across four rounds. The
      one argument for keeping it - that BRIEFs are durable by type - is a type
      rule, which this judgment's input restriction forbids as an input. Carry
      check at wip/scope_work-on-standalone-completeness_carry-check.md recorded
      no carried:false.
    decided_at: 2026-09-13T00:00:00Z
child_snapshots:
  brief:
    status: Accepted
    content_hash: 55bc4d5432c769175a1590548b7cec9c4d14b5b3
    captured_at: 2026-09-13T00:00:00Z
  prd:
    status: Accepted
    content_hash: ca4f8a073f6afde09b8d0385f37df8fe8c17cbaa
    captured_at: 2026-09-13T00:00:00Z
  design:
    status: Planned
    content_hash: 4d06a199cbebcc0ea5d2b2deee78d6df181d8f23
    captured_at: 2026-09-13T00:00:00Z
  plan:
    status: Active
    content_hash: bd29bc51c4eafa2029b437d5afd7f5904b8dfe7e
    captured_at: 2026-09-13T00:00:00Z
worktree_rebases:
  - phase: brief
    upstream_commits: [7cd13d1]
    impact: informational
    rebased_at: 2026-09-13T00:00:00Z
    notes: >-
      PR #353 changed skills/execute/koto-templates/execute.md (56 lines) and
      skills/execute/scripts/run-cascade.sh (206 lines), both cited by this
      chain. Re-verified after rebase: execute.md:706 still the run-cascade
      invocation, :640 still pr_finalization's do-not-mark-ready, :305 still the
      materialize_children default_template; skills/work-on/ still has exactly
      one cascade/lifecycle mention (SKILL.md:183), zero --draft, and one
      Fixes # (references/phases/phase-6-pr.md:35). No fact the chain committed
      to was altered. The commit strengthens this chain's no-chain-skip-path
      requirement rather than contradicting it - it fixed the case of a PLAN
      with no resolvable upstream, which is the thin-chain shape the design hop
      has to handle.
---

# /scope state: work-on-standalone-completeness

Setup established. Slug validated against `^[a-z0-9-]+$` as provided.
Visibility read from `CLAUDE.md` (`## Repo Visibility: Public`). No
`--upstream` supplied and no ROADMAP exists in this repo, so
`consumed_upstream:` is absent. No stale `parent_orchestration:` block was
present at session start.

Entered from an `/explore` handoff at
`wip/scope_work-on-standalone-completeness_handoff.md`.

## Phase 1 discovery

Entered via the `/explore` handoff (Slot 7), so the cold-start projection is
suppressed and the framing-shift question was put as a confirmation of the
answer the handoff carries.

**Framing-shift answer: yes, the framing shifted.** Confirmed from the handoff.
The tracking issue frames the problem as five capabilities living in the wrong
skill; the exploration established from the code that two of those are not gaps
at all, and that the remainder is one missing capability plus a difference in
enforcement altitude. The acceptance criteria in the tracking issue rest on the
superseded framing.

**Child-doc globs:** no artifact exists at any canonical path for this topic, so
no child is held back by re-entry protection and `child_snapshots:` is absent.

**R6 predicate verdicts** (P1 and P3 accepted from the handoff with its stated
reasons; P2 recomputed against the tree):

- **P1 fires** — three architectural alternatives are left open by the handoff:
  where the shared cascade script lives, whether `/work-on` retains, refuses or
  drops multi-pr support, and the shape of the per-child "do not cascade"
  signal.
- **P2 does-not-fire** — recomputed against the worktree. The shared-script
  relocation needs no new component: a repo-root `scripts/` already exists and
  already hosts cross-skill machinery, including `scripts/lib/` and
  `scripts/ci-gate-expression_test.sh`, which tests the very CI-gate expression
  `work-on.md` and `execute.md` duplicate on purpose. The likely home for a
  shared cascade script is an existing directory, not a new substrate.
- **P3 fires** — the handoff names architectural complexity directly: a 16-plus
  place routing surface across five skills and two eval suites, a two-PR
  decomposition whose order is load-bearing, and two accepted documents
  (`PRD-execute-skill.md` D5 and `DESIGN-execute-skill.md` Decision 2 R1) that
  must be superseded rather than contradicted.

## Scope decision: shirabe#360 (2026-09-13)

Question put by the coordinator: fold #360 into this chain's first PR, or keep
it separate and sequence it after.

**Verdict: separate, and sequenced BEFORE this chain's first PR** — a third
option, recommended on the merits below rather than either offered one. This
chain's PLAN carries an explicit follow-through issue so the new states cannot
miss the pattern.

Measured overlap:

- `skills/work-on/requires.tsv:37` reads `koto  next  --with-data  always`.
  #360 changes that single line to add `--no-cleanup`. This chain does not
  otherwise need to touch it. One-line add/add at worst.
- `skills/work-on/koto-templates/work-on.md` has five terminal states
  (`:123`, `:821`, `:824`, `:827`, `:837`). #360 annotates the ticks reaching
  them; this chain inserts cascade states immediately before them. Same region
  of the same file.

Why separate rather than folded:

- #360 is destroying worker context records today, and this chain's first PR
  does not exist yet — the PLAN is not written. Holding a small, urgent,
  independently valuable fix behind a large feature PR is the wrong trade, and
  "it touches the same file" is a merge concern rather than a reason to couple
  two changes that are separately testable.
- The fix is well precedented and does not need this chain's findings: `/scope`
  already solved it and recorded why
  (`skills/scope/requires.tsv:37`, `skills/scope/koto-templates/scope.md`
  terminal prose, `references/phases/phase-4-cleanup.md:121`). Nothing this
  chain is establishing changes what #360's fix should be.
- Folding would put a defect fix with its own filed issue inside a PR whose
  thesis is a different change, which makes both harder to review and to revert
  independently.

Why before rather than after:

- The decisive point against "after" is that this chain **reshapes the thing
  #360 annotates**. After this chain lands, the tick that reaches `done` comes
  out of a cascade state rather than out of `ci_monitor`. A #360 fix written
  afterwards would have to be re-derived against a terminal path that had just
  changed shape.
- Landing #360 first establishes the pattern, and this chain then applies it to
  the states it adds — following a documented convention rather than
  rediscovering it. The conflict reduces to one rebase plus a one-line
  `requires.tsv` merge.
- "After" also means this chain knowingly ships new terminal-adjacent states
  carrying a defect that is already filed.

Obligation this creates on the PLAN: an explicit issue requiring every terminal
tick this chain introduces to pass `--no-cleanup`, with the acceptance criterion
stated against the new states rather than against today's. Without that issue
the risk "before" carries — new states silently missing the pattern — is real.

## Correction to the #360 obligation (2026-09-13)

The #360 fix is root-only. Passing `--no-cleanup` on a koto CHILD's terminal
tick suppresses both sources the parent's `children-complete` gate reads
(`finish_terminal_tick` returns before `append_terminal_index_for_session` and
`append_child_completed_to_parent` under the flag, and sets `has_result` false),
wedging the parent at `converge_blocked`. The flag is structurally inert
off-terminal: both call sites are gated on `NextResponse::Terminal`.

**The obligation this chain recorded is superseded.** It was "every terminal
tick this chain introduces passes `--no-cleanup`". It is now:

- every terminal tick a ROOT session runs passes `--no-cleanup`; and
- no child session ever passes it.

**The trap.** `skills/work-on/koto-templates/work-on.md` IS the child template.
An unconditional edit there hands the flag to every child and wedges
convergence. The cascade states this chain adds are subject to the same
root-only-at-runtime discipline, and the PLAN must carry a test asserting a
child does not receive the flag, so a later tidy-up cannot reintroduce it.

**Not designable around.** The child half cannot be fixed caller-side, because
the flag fuses record retention with notification suppression. That is going to
koto#240; this chain must not assume a child-side fix arrives.

**Consequence for this chain.** PRD R19 as drafted says "every terminal tick
this feature introduces SHALL retain its workflow context record", which is now
incomplete and, read naively, actively harmful. It needs the root-only split
plus the no-child prohibition and the regression test. The PRD is mid-jury, so
the correction lands after the in-flight verdicts return and the jury re-runs
against the corrected text rather than being accepted on text no reviewer saw.

**A second observation worth carrying to the design hop.** `work-on.md` now has
TWO behaviours that must differ between a root run and a child run: whether the
cascade fires (R11, R12) and whether the terminal tick retains its record. Those
are the same shape of problem and may want the same discriminator rather than
two independent ones.

## The root/child discriminator, as settled (2026-09-13)

Shape, from the #360 worker: `skills/work-on/scripts/session-role.sh`, printing
`root` or `child`, reading koto's own `parent_workflow` field rather than a
naming convention. A dot-based heuristic was vetoed as unsound in both
directions — legacy non-composed children carry no dot and would read as root,
and a user-chosen root name may contain one, silently dropping retention. The
field is readable via `koto session list` (emits `parent_workflow` per session,
keyed by id). `koto workflows` also emits it but is scoped to the current
directory, so a session anchored elsewhere falls through; `koto status` emits
nothing.

Consequences for this chain:

- **No merge conflict.** Their fix leaves `work-on.md` and `execute.md`
  untouched; the rule is consumed from `skills/work-on/SKILL.md`. The seam this
  chain's cascade states need is the script, and it will exist.
- **Use it, do not invent a second one.** PRD R19b requires exactly this, and
  the referent is now concrete.
- **`/execute` is always root**, backed by a test that goes red if `/execute`
  ever becomes spawnable, rather than by an assertion.

**Trap the design hop must not walk into: their placement does not transfer to
our obligations.** Their rule is consumed from `SKILL.md`, which a materialized
child never loads. That is safe *for their rule specifically*, because its
failure mode is omission and omission is the correct child behaviour — a child
that never learns to request retention thereby does the right thing.

Our cascade obligations invert that. For us, omission IS the failure: a child
that never learns the obligation simply skips it, silently, which is the defect
this whole feature exists to remove. So PRD R10 still binds unchanged — every
obligation this chain introduces must be reachable from `work-on.md` and must
not live only in `SKILL.md` — even though we call a script whose own rule is
consumed from exactly there.

Stated plainly because copying the neighbouring pattern is the obvious move and
would be wrong here.

## Process deviation: the PRD hop's sentinel never landed (2026-09-13)

Recorded rather than quietly corrected, because a reader auditing this run
would otherwise find a hop that ran with no sentinel and no explanation.

**What happened.** Phase 2 step 2 writes the `parent_orchestration:` block to
this state file immediately before invoking each child. For the `/prd` hop that
write silently failed: the edit was a text substitution whose pattern did not
match (it assumed the brief's snapshot was the last frontmatter key, but
`worktree_rebases:` follows it), and the script reported success regardless.
So `/prd` ran with no sentinel present, and step 5's cleanup had nothing to
clear.

**Consequence.** `/prd`'s Resume Logic consults the sentinel to detect that it
is running under a parent; absent it, the skill's documented behaviour is that
of a direct invocation. The produced artifact is unaffected — `/prd` was driven
through its own phases and its jury ran at full width across seven rounds — but
the contract was not honoured for that hop, and the run should not claim
otherwise.

**Same root cause as a second failure.** An identical silent no-op dropped a
correction to the PRD's R16a exclusion clause; the clarity reviewer caught it by
reading the file rather than trusting the claim that it had been applied. Both
came from using a substitution that does nothing when its pattern misses, paired
with an unconditional success message.

**Corrected practice for the rest of this run.** Every state-file and artifact
edit either uses a tool that fails loudly on a non-match, or asserts the
substring exists before replacing and asserts the result changed. The assertion
is what surfaced this deviation, one hop after the one it should have caught.

**Not re-run.** Re-invoking `/prd` with the sentinel present would re-author an
accepted artifact that three reviewers have passed, to change a detection flag
whose only effect is on resume routing that this run did not use. The deviation
is recorded instead.

## PLAN obligations accumulated during the DESIGN hop

Recorded here so the PLAN hop carries them rather than rediscovering them.

1. **The `--no-cleanup` issue, written against the new states.** Every terminal
   tick this chain introduces that a ROOT session runs passes `--no-cleanup`;
   no child session ever does. The criterion is written against the states this
   chain adds, not against today's. The trap it guards:
   `skills/work-on/koto-templates/work-on.md` IS the child template, so an
   unconditional edit hands the flag to every child and wedges its parent at
   `converge_blocked`. A regression test must fail if the behaviour is made
   unconditional.

2. **A test that fails when a document is transitioned on disk but missing from
   the finalization commit.** That is the exact state the cascade's staging
   defect produces — a failed `git add` leaves the document transitioned in the
   tree while the bogus `STAGED_FILES` entry keeps the commit block running, and
   the tree-reading post-verify passes. It is therefore the case this chain's
   evidence must be able to see. If it cannot be constructed in a test harness,
   the PLAN says so explicitly and names what stands in its place rather than
   leaving the gap implicit.

Both are issues in their own right in the PLAN, not acceptance criteria folded
into someone else's issue.

## Recurring defect in this run: the missing `schema:` field

Twice now — the PRD and the DESIGN — an artifact was authored without its
`schema:` frontmatter field, and in both cases `shirabe validate` did not report
a violation. It reported `outcome: incomplete` with a SCHEMA notice and **skipped
the file entirely**, so none of its mechanical checks ran.

That is the dangerous half and the reason this is recorded rather than just
fixed. A missing schema field does not produce a failing check; it produces an
absence of checking that reads as a notice. An author glancing at "0 errors"
would conclude the document passed, when in fact nothing was examined. It is the
same shape as the defects this whole feature exists to remove: a report that
looks like success without being evidence of it.

Both were caught by a reviewer running the validator and reading its `outcome`
field rather than its error count.

**Obligation for the PLAN hop:** the PLAN needs `schema: plan/v1`, and its
validation must be read for `outcome`, not for `errors: 0`.

3. **The anchor gate's search pattern must be anchored, and nothing mechanical
   enforces it.** An unanchored match could find an issue number as a substring
   of another and cascade the wrong document chain — a correctness defect with a
   security-shaped consequence, since the cascade transitions documents and
   pushes. `check-template-interpolation.sh` does not cover this. The PLAN
   carries it as an explicit review obligation on whichever issue writes that
   gate, rather than leaving it to be noticed.

4. **A stated count that disagrees with its own enumeration is a findable
   defect, and a jury should not be the thing that finds it.** This design
   claimed four new states while naming three, and the missing one was exactly
   the requirement left unaddressed. The document carried the evidence of its own
   gap and nothing mechanical looked.

   The PLAN carries a review criterion for this class: where an artifact states
   a cardinality ("four states", "six operations", "three deferrals", "the two
   documents"), the enumeration it refers to is checked against it. Cheap to
   apply by eye at review time; worth asking during implementation whether it is
   cheap to assert mechanically for the documents this repository validates,
   since `shirabe validate` already parses their structure. If it is not cheap,
   the criterion stays a review obligation rather than becoming a new check —
   this feature is not the place to grow the validator.

   Noted as a general lesson rather than a one-off correction: the same shape
   produced the `schema:` field defect (an absence of checking that reads as a
   notice) and the two silent edit no-ops earlier in this run. All four are
   reports or counts that look like evidence without being it, which is the
   theme this feature exists to address one level up.

5. **At least one criterion written against a chain rather than a state.** koto
   advances in a loop, so a single tick can traverse several states; a
   wrongly-unconditional transition passes state-by-state review and only shows
   up when a whole tick is exercised. The PLAN carries a criterion that drives a
   tick from `ci_monitor` through to a terminal and asserts what that one
   invocation did — in particular that a root run's terminal tick retained its
   record and a child's did not, and that `cascade_run` was not passed through
   without stopping.

   **Corrected after measurement.** An earlier version of this obligation said
   the criterion must fail if `cascade_run`'s evidence block were removed. That
   is the wrong trigger. Two measured variants of the same state settled it: with
   a required evidence field and a single unconditional transition, a bare tick
   two states upstream chains through to the terminal and the agent never sees
   the directive; with a required evidence field plus one conditional transition
   and an unconditional fallback, the tick stops and the record survives.

   So the guard is **at least one conditional transition**, not the evidence
   block. `cascade_run` is protected because it routes on `cascade_status` —
   `completed` and `skipped` one way, `partial` another.

   The criterion must therefore **fail when `cascade_run`'s transitions become
   all-unconditional**, not when its evidence block is removed. That is the
   harder regression to see: collapsing three edges into one is a tempting
   simplification because two of them share a target, it leaves the `accepts:`
   block untouched, and a reviewer asking "does this state still require
   evidence?" sees nothing wrong. Only a driven tick catches it.
