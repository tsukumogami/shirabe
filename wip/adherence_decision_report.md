<!-- decision:start id="skill-adherence-enforcement" status="assumed" -->
### Decision: How shirabe makes its sanctioned workflow the path an agent actually takes

**Context**

Two field incidents produced the same loss. In the first, an agent told to
execute a plan never invoked `shirabe:execute`; it built its own task list and
hand-implemented 22 plan outlines. In the second, the agent *did* invoke the
skill, ran its preflight, and ran `plan-to-tasks.sh` producing a valid koto
payload with all six `waits_on` edges -- then never submitted it, and implemented
six issues inline. Its reason was a precedence conflict: the session instruction
"Do not call the AgentTool unless the user requested it" collided with
`spawn_and_await`, which spawns one `/work-on` child per issue, and it resolved
against the skill. Under the documented rule that user and session instructions
outrank skills, it was not wrong by the letter.

The exploration's opening theory -- that shirabe's skills are hard to reach --
is dead. A live probe confirmed bare `/execute` resolves to `shirabe:execute` on
v2.1.233; a plugin skill gets a bare alias unless another command claims the name,
and nothing claims `execute`. Both agents had the skill available and, when asked,
could name exactly what they should have done. **The cause is not missing
knowledge**, which disqualifies every mechanism whose only effect is to supply
knowledge.

Two structural facts bound the whole solution space. Injected `additionalContext`
-- the mechanism behind SessionStart banners -- is delivered as "a system reminder
that Claude reads as plain text," which sits *below* a session instruction in the
same precedence order that already beat the skill. So no amount of louder prose
can win that conflict. Conversely a `PreToolUse` hook returning `deny` fires
before every permission-mode check and holds even under `bypassPermissions`
(which this workspace runs) -- because a hook block is outside the ordering the
model arbitrates at all.

**Assumptions**

- Skill-frontmatter hooks persist for the session once the skill is invoked.
  **Verified against the 2.1.233 binary**, not documentation: it emits
  `Registered ${i} hooks from skill '${n}'` and `Removing one-shot hook for event
  ${s} in skill '${n}'`; the one-shot removal path is the proof that the default
  persists.
- The PreToolUse hook input carries `session_id` (confirmed in
  `crates/shirabe/src/pr_body_hook.rs`) and koto's workflow record at
  `~/.claude/projects/<encoded-cwd>/<session-id>/workflows/koto-<uuid>.json` is
  keyed by that same id. The join has no inferred link.
- Koto's guarantees are **bookkeeping, not enforcement**. The substrate-spawn
  primitive is a logging stub (`src/engine/respawn.rs:165-180`); review gates and
  CI monitoring are directive text koto never verifies. No mechanism in this
  decision can deliver "the adversarial reviews definitely ran." The achievable
  goal is that a run is recorded and visible.
- `SubagentStart.additionalContext` remains doc-only and untested. It is the only
  surface reaching `spawn_and_await` children, so anything depending on it must
  be verified empirically first.
- All six validators reported. Two arrived after the first synthesis draft and
  changed it materially -- the primary predicate below is theirs, not the
  decider's.
- **Open, and load-bearing for implementation:** whether skill-registered hooks
  fire inside subagents. Tool hooks from settings and plugins demonstrably do, but
  the skill-frontmatter case is unverified. It matters because `/work-on` children
  legitimately write source files, so a write-target gate registered by the parent
  must exempt them -- the hook input carries `agent_id`/`agent_type`, so the
  exemption is expressible, but the behavior must be tested before the gate ships.

**Chosen: A staged portfolio -- detect locally, publish off-machine, narrow the
ambiguity; defer the gate and the policy surface**

*Ship now.* Four components, each independently justified and none requiring a
new configuration system:

1. **An ordering statement at the conflict point.** Placed at `spawn_and_await`,
   where the agent is provably already asking the question. It must be written as
   **interpretation-narrowing, never precedence-claiming**: "requesting `/execute`
   requests its children" is defensible; "skills outrank session instructions" is
   not, and shipping that would be a worse outcome than either incident. Cheapest
   change in the field, and the only one testable with shirabe's existing eval
   format today.
2. **Two complementary checks, both delivered from `shirabe:execute`'s own
   frontmatter** -- no niwa change, no policy surface, no org-owner action.

   *The primary predicate is R9 write-target conformance, enforced at write time.*
   `/execute` already declares a **closed write-target set** (Security
   Considerations point 2): its state file and scratch under
   `wip/execute_<topic>_*`, the skill's own files, the home PR or coordination body
   via `gh`, the finalization cascade's chain transitions under `docs/`, and
   Decision Records on `re-evaluation`. Today a write outside that set "fails the
   R9 hard-finalization check" -- which is self-administered, and only at the end.
   Move it to a skill-scoped `PreToolUse` hook that denies `Edit`/`Write` outside
   the declared set, with `permissionDecisionReason` naming the sanctioned move.

   This predicate is strictly better than the koto-session one it replaces. It is
   **not gameable** -- there is no equivalent of running `koto init` to buy
   permission, because the check is on the write itself. It needs **no
   coordinated-plan carve-out**, because the write-target set governs both
   execution paths identically. It rests on a contract the skill **already
   declares**, so it enforces an existing invariant rather than inventing one.
   And both incidents fail it directly: hand-editing 22 (or six) issues' source
   files is precisely a write outside the closed set.

   *The secondary check is a delegation detector at `Stop`*, asserting a
   `scheduler_ran` event with `spawned_count >= 1` -- delegation, not mere
   registration. It reports rather than blocks; `Stop`'s `additionalContext` is
   delivered as non-error feedback with the conversation continuing, so the agent
   gets a steerable correction. This is where the coordinated-plan carve-out
   applies, since that path has no koto session by design.
3. **`execute` description repair plus trigger evals.** The description is
   defective by shirabe's own published standard -- ~40 words of internal
   vocabulary, no trigger phrases -- while ten sibling skills follow the house
   pattern. Trigger evals via `skill-creator`'s `run_loop` are the only instrument
   that can measure the rate this decision is being sized against; all 18 existing
   suites presuppose invocation.
4. **Move `koto init` ahead of the first decision point** in the execute template,
   leaving expensive side effects in `orchestrator_setup`, so the artifact the
   detector reads exists before the step an agent might skip.

*Also cheap, ship advisory-first.* Two items from the outcome-gating advocate's
final position, both buildable today with no R9 amendment and no koto change:
the **per-child outcome row check** (the finalized PR body's Part 2 should carry
one outcome row per plan outline), documented explicitly as a heuristic defeated
by imitation rather than as adherence enforcement; and **closing the payload
seam** so `plan-to-tasks.sh` cannot emit a payload it is unable to register.
The seam is the exact place incident 2 walked through. Note the script takes no
session argument today, is shared with `/plan`, and is called twice per run with
different evidence, so this is a design task rather than a patch.

*Ship next, needs design.* **Publish the run record off-machine** -- a
`Koto-Session:` PR trailer or run-report emit, requiring an explicit R9 amendment
to `/execute`'s closed write-target set. This is what resolves the self-grading
problem below, and it is the precondition for any future CI-side verification.
Alongside it, define the plan-derived-PR completion property in the
single-authority form of `references/pr-body-conformance.md`.

*Defer.* The `[claude.skills]` policy surface in niwa. Validator 6 put the case
against it plainly while arguing for its own delivery mechanism: Alternative 3's
diagnosis is right, but its vehicle "is a new `[claude.skills]` policy system in
niwa, which is the most machinery in the field" and collides with the
`[workspace]` tombstone reasoning. Skill-frontmatter delivery gets the same
enforcement grade with none of that, and reaches every shirabe adopter whether or
not they use niwa. Revisit only if evidence shows per-repo policy variation is
actually needed.

*Two constraints bind every component.* A **coordinated-plan carve-out** is
mandatory: `skills/execute/SKILL.md:242-246` establishes that a coordinated
multi-repo plan has no koto session by design, so an uncarved predicate would flag
the newest sanctioned execution path as a failure. And the pre-session
conflict-record vehicle must be the `shirabe work-summary` hook path -- already
session-keyed, already distributed default-on by niwa, already rendering a
user-visible `systemMessage` -- because `koto overrides` was tested and exits 1
with "workflow not found" when no session exists, which is precisely incident 2's
case.

**Rationale**

The decision turns on two findings that together define the problem, both produced
by a validator arguing against its own position.

*The discriminating state exists only on the machine.* Shirabe's shipped
path-independent checks (L01, L06, PB1-PB4) were live during both incidents and
**certified them both**: incident 2's agent ticked acceptance criteria, ran the
finalization cascade, and opened a conformant PR. Every candidate off-machine
property -- per-issue commit structure, acceptance criteria, cascade completion,
PR body -- passes both incidents, because a competent inline implementation
satisfies all of them. That falsifies outcome gating as the primary mechanism on
evidence rather than argument.

*But the machine is the party that failed.* Every client-side mechanism asks the
session that just erred to evaluate itself again, only earlier or louder. That is
the defect shared by the salience stack, the graded policy, the structural
constraint, and the conflict protocol alike.

Neither side can be chosen outright, which is why the portfolio detects locally
(the only place discrimination is possible) and publishes off-machine (which is
what removes self-grading). The publishing half is available because koto's traces
are weak "because koto deletes them and publishes nothing, not because process is
intrinsically untraceable" -- a bounded, fixable property of one tool.

The staging follows the stated preference for guidance over enforcement without
foreclosing enforcement, and matches `P5: Strictness tracks blast radius`, which
already licenses shipping as a notice and promoting once the corpus conforms. It
also respects the gaming finding: a gate keyed on session existence would teach an
agent the one command that buys permission and leave behind a record falsely
attesting the loop ran -- worse than the failure it replaces, since that record is
the artifact the design proposes to trust.

**Alternatives Considered**

- **Salience stack (guidance only)** -- description repair, trigger evals,
  SessionStart injection, dispatch prefix, brief-template slot. Its cheap
  components are adopted; its enforcement leg is rejected. Injected context is
  delivered as a plain-text system reminder ranking *below* the session
  instruction that already beat the skill, so it cannot win a precedence conflict
  by construction. It also does nothing for incident 2, where the agent was
  already inside the skill reading its prose.
- **Path-independent outcome gating** -- rejected as primary, falsified by its own
  advocate: the shipped gate certified both incidents, and every enumerated
  off-machine property passes both. Its definitional half is adopted, and its
  central insight (verification by a party other than the one that failed) is what
  the off-machine publishing component exists to satisfy.
- **Graded workspace policy over a koto predicate** -- the provisional
  recommendation, substantially withdrawn. Its own advocate recommended removing
  the policy surface and the `gate` rung from the first release, conceding that
  `remind` restates knowledge the agent already has and so fails the disqualifying
  test. Its predicate survives, strengthened to assert delegation; its
  configuration system is deferred as unjustified until data exists.
- **Restricted-tool orchestrator** -- its *principle* is adopted and became the
  primary predicate; its *vehicle* is rejected. Its advocate reached the same
  split independently: an agent-definition tool list "misses the interactive path,
  carries no reason string, and under a spawn-forbidding session degrades into the
  silent Bash bypass rather than an honest stall." The substitution -- a
  skill-scoped `PreToolUse` hook denying writes outside the R9 closed set, with a
  reason naming the sanctioned move -- keeps the "remove the capability to
  implement inline" insight while fixing coverage (it reaches the human path),
  observability (it explains itself), and the deadlock (the reason can name the
  recorded-override route). This is the single largest improvement the adversarial
  round produced over the provisional recommendation.
- **Conflict-surfacing protocol** -- adopted as a component, not as the mechanism.
  Its diagnosis is confirmed structurally and its cheapest piece (the ordering
  statement) has the best value-per-token in the field. It cannot stand alone: it
  does nothing for incident 1, and in prose form it sits at the same losing
  altitude as the instruction it governs.

**Consequences**

Easier: adherence becomes measurable for the first time, by a check that needs no
agent cooperation and roughly 25 lines of bash. The visibility the user lost
becomes available -- `koto dashboard` already existed and was empty precisely
because nothing was registered. The ambiguity that produced incident 2 becomes
specified rather than left to a coin flip, and it becomes gradeable by shirabe's
existing eval harness.

Harder: publishing the run record off-machine widens `/execute`'s closed
write-target set and needs a deliberate R9 amendment. The detector's predicate now
has to track koto's internal event shape (`scheduler_ran`, `spawned_count`), which
is a coupling that will need maintenance. And the coordinated path needs a
parallel signal read from the coordination PR, since it has no koto session by
design.

Unresolved, and deliberately so: whether the org owner ultimately gets a
configuration surface at all. The user asked for one; niwa's `[workspace]`
tombstone reasoning exists specifically to stop a private layer from changing what
a contributor's run does, and a workflow mandate is arguably that class. Deferring
the policy surface defers this collision rather than settling it. If it is
revisited, note that `disableAllHooks` in a project settings file defeats every
non-managed hook, so genuinely non-defeatable org policy would have to live in
managed settings -- which removes the escape hatch that Finding D says a gate
cannot safely ship without.
<!-- decision:end -->
