# Phase 3: Cross-Validation

Five decisions ran independently. This pass checks their assumptions against each
other and records the interfaces that only exist because two decisions met.

## Conflicts found: none fatal, three interfaces created

### Interface 1 (new, blocking): the determination needs the arming component as a liveness witness

**Raised by decision 1, owned jointly with decision 2.**

Decision 1 established, against real machine state, that **absence of a koto
registration record is not evidence of non-registration**. The completed
eight-child run `execute-feature-23-google-cli-access` has no `/workflows` record
at all: koto defaulted `workflows.native` on in a commit dated 2026-07-18, but the
record only began appearing in that workspace on 2026-08-04, so the run predates
the binary upgrade. A checker treating absence as failure would report a fully
delegated run as `non-conforming`, which is precisely what R9 exists to prevent.

Decision 1's first attempt at a corroborator ("does any koto session for this plan
exist") was tested and failed: with an unrelated session present, an inline run
that never registered came back `indeterminate` instead of the `non-conforming`
that AC2 and AC3 require.

The resolution crosses decisions. The arming component from decision 2 observes
the session's tool calls in band, so its own log entry proves the enforcement
stack, and therefore koto's recording path, was live while the session ran.

**Interface requirement:** decision 2's component SHALL write a durable per-session
entry whenever it evaluates a tool call, whether or not it arms. Decision 1's
determination SHALL treat the absence of that entry as `indeterminate` rather than
`non-conforming`. Neither decision satisfies this alone, and neither surfaced it
alone.

### Interface 2 (new): the determination must read the conflict store

**Between decisions 1 and 4.**

R2 makes an unrecorded departure non-conforming and AC22 tests it. So the
determination cannot be computed from koto surfaces alone: a run that dropped an
issue *with* a recorded conflict is legitimate, and one that dropped it silently
is not. Decision 1 reaches the same conclusion in its dropped-issue analysis.

Decision 4 puts the durable record at
`$XDG_STATE_HOME/shirabe/conflicts/<session-id>.jsonl`, keyed by session id.
Decision 1's determination is also session-keyed, so the join is direct.

**Interface requirement:** the determination SHALL read decision 4's conflict store
for the session under evaluation, and SHALL treat a delegation shortfall covered by
a matching conflict record as conforming rather than as a shortfall.

**Unresolved detail the DESIGN must carry:** decision 4 writes the local record
keyed by the *session that recorded the conflict*. For a koto-delegated child,
that is the child's session id, not the orchestrator's, because decision 1
established children carry their own ids. The join therefore has to walk children,
not just look up the parent. Neither decision states this.

### Interface 3: the arming predicate and the write-target contract share a source

**Between decisions 2 and 3.**

Decision 2's clause C and decision 3's hook both need `/execute`'s declared closed
write-target set. Decision 3 ships it via `${CLAUDE_PLUGIN_ROOT}`, which is
available to the hook process. Compatible, with one requirement: the set must be a
readable artifact rather than prose in `SKILL.md`, or both components end up
parsing English. Decision 3's sketch already passes `--contract
"${CLAUDE_PLUGIN_ROOT}"`, so the DESIGN owes a declaration format.

## Assumptions checked and found consistent

**Registration lifetime versus arming.** Decision 3 makes hook registration
unconditional and session-long, deciding arming per tool call. Decision 2's
predicate is a pure function of hook input plus disk. These compose: R4's
prohibition on invocation-as-trigger is satisfied because registration is not the
arming act, and R8's fail-open becomes the default branch rather than an
exception. Had decision 3 chosen skill-frontmatter registration, decision 2's
predicate would have been unreachable for the case it exists to catch.

**Orchestrator-role discrimination.** I briefed decision 2 to use "absent
`agent_type`" as the role test. It declined, correctly, citing the limits section
of my own probe: absence is an open-world assumption. It uses `agent_id` only to
select which transcript to read, and puts the role test on the unit of work named
in the agent's own inbound brief. Decision 1 independently identifies children by
`parent_workflow` and `template_name` rather than by session relationship. The two
are consistent and neither depends on my discarded framing.

**Admissibility scope.** Decision 2 notes R1 constrains the determination, not the
arming: arming reads the agent's inbound instructions, which the agent under
evaluation did not author. Decision 1 applies R1 to the determination's evidence
and excludes script output. No conflict.

**Coordinated carve-out.** Decision 2 stands the arming down when `execution_mode`
is `coordinated`; decision 1 reports the distinct `coordinated` outcome. Both
implement R7 from their own side and agree on the trigger.

## Corrections to my own briefings, carried for the record

Two briefings I sent the researchers were wrong, both by generalizing a probe past
what it measured. Recorded because the reasoning is visible in the artifacts.

1. I told decisions 1 and 2 that orchestrator and delegated child share a session
   id. True for Agent-tool subagents, false for koto-delegated children, which
   carry their own ids plus `parent_workflow`. Decision 1's evidence is stronger
   than my briefing implied.
2. I told decision 3 the plugin-hooks placement was "directly adverse" because a
   `--plugin-dir` probe showed zero invocations. That is a fact about the
   dev-loading path. Installed plugins do fire their hooks, as superpowers does in
   this session. Decision 3 chose the plugin route regardless.

Both corrections are written into
`wip/design_skill-adherence-enforcement_probe_subagent_hooks.md` and
`wip/design_skill-adherence-enforcement_probe_session_identity.md`.

## Open questions promoted to the DESIGN

1. **Plugin `PreToolUse` startup ordering.** Whether registration completes before
   the first tool call in a `-p` session whose opening move is a write. The
   superpowers evidence is a `SessionStart` hook and does not settle it. Decision
   3 names the one-command probe; it blocks implementation, not the design shape.
2. **The delegated-child conflict join** (interface 2's unresolved detail).
3. **Session-local escape from the refusal.** Decision 2 states the tension
   plainly: any session-local escape is session-produced, so the refusal is a
   speed bump plus an audit trail rather than a sandbox. Defensible given R2's
   teeth, but the DESIGN must claim it rather than let a reader discover it.
4. **The R15 switch's durable form**, CLAUDE.md header versus a workspace-manager
   boolean. Decision 3 recommends the header and names its cost.
5. **Double registration.** The workspace manager's existing dedup greps installed
   hook scripts and does not inspect a plugin's `hooks.json`, so if it later
   injects the same subcommand both fire.

## Verdict

The five decisions compose. Two interfaces exist that no single decision could
have produced, and both are load-bearing rather than cosmetic: without interface
1 the determination misreports old runs, and without interface 2 it misreports
legitimate conflict-covered departures. Proceed to architecture.
