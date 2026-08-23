---
name: scope
version: "1.0"
description: >
  Tactical-chain orchestrator for /scope. Twenty-one states across five phases:
  setup, discovery and the chain proposal, four hop states plus one shared fold
  state, six exit states, three cleanup states and four terminals. Each hop
  delivers its own directive on entry and carries a command gate that decides
  completion from the artifact tree through skills/scope/scripts/hop-complete.sh;
  the full-run exit re-runs that predicate for every hop and refuses unless each
  one has either its artifact or a declared fold.

  Two authoring rules bind every state here, and a reviewer should check both
  before reading the states. First, every non-terminal state carries at least one
  transition with a when clause keyed on an agent evidence field: koto fires a
  state's unconditional transition on entry unless the state has a conditional
  one, so a state with an accepts block and no guarded transition is advanced
  through silently and never delivers its directive. Second, every gate is
  co-routed with an evidence field in the same when clause: a guard referencing
  gate output alone resolves without the agent, which delivers no directive
  either, and a gate no when clause references is evaluated, reported and
  ignored.

  Each state also carries a `# phase: N` comment naming the /scope phase it
  belongs to, so a run can report its phase from its position. koto rejects an
  undeclared state field, so the map is a comment rather than a `phase:` key.
initial_state: setup

variables:
  TOPIC:
    description: >
      The run's topic slug, matching ^[a-z0-9-]+$. Declared as a template
      variable because every gate command below interpolates it into a command
      koto runs itself, and koto resolves and compile-time-validates only
      {{KEY}} references -- a shell-style ${TOPIC} is passed to sh -c untouched
      and expands to the empty string. koto's own --var allowlist is not a
      second line of defence here: it rejects shell metacharacters but permits
      dots and slashes, so the slug is validated at Phase 0, re-validated on
      resume, and re-asserted by the predicate before it composes any path.
    required: true

states:
  setup:
    # phase: 0
    accepts:
      setup_result:
        type: enum
        values: [ready, blocked]
        required: true
      detail:
        type: string
        description: What blocked setup, when blocked.
    transitions:
      - target: discovery
        when:
          setup_result: ready
      - target: bail
        when:
          setup_result: blocked

  discovery:
    # phase: 1
    accepts:
      discovery_result:
        type: enum
        values: [proposed, blocked]
        required: true
      detail:
        type: string
        description: What blocked discovery, when blocked.
    transitions:
      - target: chain_proposal
        when:
          discovery_result: proposed
      - target: bail
        when:
          discovery_result: blocked

  chain_proposal:
    # phase: 1
    accepts:
      author_decision:
        type: enum
        values: [proceed, adjust, bail]
        required: true
      detail:
        type: string
        description: What the author asked to adjust, or why they bailed.
    transitions:
      - target: hop_brief
        when:
          author_decision: proceed
      - target: discovery
        when:
          author_decision: adjust
      - target: bail
        when:
          author_decision: bail

  hop_brief:
    # phase: 2
    gates:
      # The predicate reads the artifact tree and nothing else. It never opens
      # the parent's own state file: a gate reading the file the run writes
      # about itself asks the run whether the run finished, which is the
      # self-report the whole arrangement exists to remove.
      #
      # Exit 2 is "cannot tell" -- a missing validator, or a validation that
      # reached no verdict -- and no transition below enumerates it, so the run
      # holds position and the gate is reported in this state's blocking
      # conditions with its exit code. That is deliberately not exit 1, which
      # would advance the hop with a recorded failure and conflate "this hop is
      # not done" with "I cannot tell whether it is done".
      brief_complete:
        type: command
        command: 'skills/scope/scripts/hop-complete.sh --hop brief --topic "{{TOPIC}}"'
    accepts:
      outcome:
        type: enum
        # `rejected` is absent here on purpose: /brief has no Phase-N reject, and
        # a reject sets a re-evaluation exit whose `boundary` enum has no legal
        # value for this hop.
        values: [landed, skipped, bail]
        required: true
      detail:
        type: string
        description: The child's outcome, or the vocabulary reason for a skip.
    transitions:
      - target: hop_prd
        when:
          outcome: landed
          gates.brief_complete.exit_code: 0
      - target: hop_prd
        when:
          outcome: skipped
      - target: bail
        when:
          outcome: bail

  hop_prd:
    # phase: 2
    gates:
      prd_complete:
        type: command
        command: 'skills/scope/scripts/hop-complete.sh --hop prd --topic "{{TOPIC}}"'
    accepts:
      outcome:
        type: enum
        values: [landed, skipped, rejected, bail]
        required: true
      detail:
        type: string
        description: The child's outcome, the skip reason, or the reject rationale.
    transitions:
      - target: fold
        when:
          outcome: landed
          gates.prd_complete.exit_code: 0
      - target: hop_design
        when:
          outcome: skipped
      - target: exit_re_evaluation
        when:
          outcome: rejected
      - target: bail
        when:
          outcome: bail

  hop_design:
    # phase: 2
    gates:
      # Both DESIGN locations are canonical, and the predicate reads the pair.
      # Testing only docs/designs/current/ makes this gate false on every run --
      # that path is reached by a lifecycle transition long after a /scope run
      # ends -- which livelocks hop_design against fold and leaves hop_plan
      # unreachable.
      design_complete:
        type: command
        command: 'skills/scope/scripts/hop-complete.sh --hop design --topic "{{TOPIC}}"'
    accepts:
      outcome:
        type: enum
        values: [landed, skipped, rejected, bail]
        required: true
      detail:
        type: string
        description: The child's outcome, the skip reason, or the reject rationale.
    transitions:
      - target: fold
        when:
          outcome: landed
          gates.design_complete.exit_code: 0
      - target: hop_plan
        when:
          outcome: skipped
      - target: exit_re_evaluation
        when:
          outcome: rejected
      - target: bail
        when:
          outcome: bail

  hop_plan:
    # phase: 2
    gates:
      plan_complete:
        type: command
        command: 'skills/scope/scripts/hop-complete.sh --hop plan --topic "{{TOPIC}}"'
    accepts:
      outcome:
        type: enum
        values: [landed, skipped, bail]
        required: true
      detail:
        type: string
        description: The child's outcome, or the vocabulary reason for a skip.
    transitions:
      - target: fold
        when:
          outcome: landed
          gates.plan_complete.exit_code: 0
      - target: finalize
        when:
          outcome: skipped
      - target: bail
        when:
          outcome: bail

  fold:
    # phase: 2
    gates:
      # These two decide which hop has not run yet, so the fold routes forward
      # without asking the run where it thinks it is. Both read the same shared
      # predicate the hop gates read, which is what keeps two gates in one graph
      # from disagreeing about the same file -- and design_present therefore
      # reads both canonical DESIGN locations for the same reason
      # design_complete does.
      plan_present:
        type: command
        command: 'skills/scope/scripts/hop-complete.sh --hop plan --topic "{{TOPIC}}"'
      design_present:
        type: command
        command: 'skills/scope/scripts/hop-complete.sh --hop design --topic "{{TOPIC}}"'
    accepts:
      verdict:
        type: enum
        values: [keep, absorb]
        required: true
      finding:
        type: string
        description: >
          On keep, what the upstream holds that the survivor would not. On
          absorb, what the carry check confirmed arrived.
    transitions:
      # Nothing remains: the plan hop is satisfied, so the chain is at its end.
      - target: finalize
        when:
          verdict: keep
          gates.plan_present.exit_code: 0
      - target: finalize
        when:
          verdict: absorb
          gates.plan_present.exit_code: 0
      # The design hop is satisfied and the plan hop is not: the plan is next.
      - target: hop_plan
        when:
          verdict: keep
          gates.plan_present.exit_code: 1
          gates.design_present.exit_code: 0
      - target: hop_plan
        when:
          verdict: absorb
          gates.plan_present.exit_code: 1
          gates.design_present.exit_code: 0
      # Neither is satisfied: the design is next.
      - target: hop_design
        when:
          verdict: keep
          gates.plan_present.exit_code: 1
          gates.design_present.exit_code: 1
      - target: hop_design
        when:
          verdict: absorb
          gates.plan_present.exit_code: 1
          gates.design_present.exit_code: 1
      # Cannot-tell arms. A gate returning 2 routes exactly where that gate
      # returning 1 routes, which is the only reading that satisfies both halves
      # of the rule: a hop the predicate could not decide is never treated as
      # satisfied (routing a plan_present 2 to finalize would credit an
      # undecided plan hop), and it never leaves the fold with no matching
      # transition. Where it lands, the hop's own gate re-runs and the author
      # still has `skipped` and `bail`, neither of which names a gate.
      - target: hop_design
        when:
          verdict: keep
          gates.plan_present.exit_code: 1
          gates.design_present.exit_code: 2
        context_assignments:
          failure_reason: "fold: the design hop could not be decided (design_present exit 2). Routed as not-yet-run; no hop was found incomplete."
      - target: hop_design
        when:
          verdict: absorb
          gates.plan_present.exit_code: 1
          gates.design_present.exit_code: 2
        context_assignments:
          failure_reason: "fold: the design hop could not be decided (design_present exit 2). Routed as not-yet-run; no hop was found incomplete."
      - target: hop_plan
        when:
          verdict: keep
          gates.plan_present.exit_code: 2
          gates.design_present.exit_code: 0
        context_assignments:
          failure_reason: "fold: the plan hop could not be decided (plan_present exit 2). Routed as not-yet-run; no hop was found incomplete."
      - target: hop_plan
        when:
          verdict: absorb
          gates.plan_present.exit_code: 2
          gates.design_present.exit_code: 0
        context_assignments:
          failure_reason: "fold: the plan hop could not be decided (plan_present exit 2). Routed as not-yet-run; no hop was found incomplete."
      - target: hop_design
        when:
          verdict: keep
          gates.plan_present.exit_code: 2
          gates.design_present.exit_code: 1
        context_assignments:
          failure_reason: "fold: the plan hop could not be decided (plan_present exit 2). Routed as not-yet-run; no hop was found incomplete."
      - target: hop_design
        when:
          verdict: absorb
          gates.plan_present.exit_code: 2
          gates.design_present.exit_code: 1
        context_assignments:
          failure_reason: "fold: the plan hop could not be decided (plan_present exit 2). Routed as not-yet-run; no hop was found incomplete."
      - target: hop_design
        when:
          verdict: keep
          gates.plan_present.exit_code: 2
          gates.design_present.exit_code: 2
        context_assignments:
          failure_reason: "fold: neither the design nor the plan hop could be decided (both gates exit 2). Routed as not-yet-run; no hop was found incomplete."
      - target: hop_design
        when:
          verdict: absorb
          gates.plan_present.exit_code: 2
          gates.design_present.exit_code: 2
        context_assignments:
          failure_reason: "fold: neither the design nor the plan hop could be decided (both gates exit 2). Routed as not-yet-run; no hop was found incomplete."

  finalize:
    # phase: 3
    # No gates and no required exit-path fields here. Each exit path's required
    # fields live on that path's own state, so a field belonging to another path
    # is an unknown field here and koto refuses it at submission, before any
    # write.
    accepts:
      exit:
        type: enum
        values: [full-run, re-evaluation, abandonment-forced]
        required: true
    transitions:
      - target: exit_full_run
        when:
          exit: full-run
      - target: exit_re_evaluation
        when:
          exit: re-evaluation
      - target: exit_abandonment
        when:
          exit: abandonment-forced

  exit_full_run:
    # phase: 3
    gates:
      # The chain-wide refusal. One invocation of the shared predicate per hop,
      # chained with && so the first hop that is not satisfied is the one named
      # in this gate's output and the run stops there.
      #
      # && rather than an aggregating loop for two reasons. It needs no shell
      # variable, so nothing here can silently expand to the empty string. And
      # it propagates exit 2 unchanged: a hop the predicate cannot decide must
      # not be reported as a hop that is not done. A loop collapsing both into 1
      # would lose that.
      #
      # The four hops are literal rather than read from a run-supplied chain
      # variable. A chain the run declares for itself is the self-report this
      # gate exists to replace: a run could otherwise name a two-hop chain and
      # be credited for walking it.
      chain_complete:
        type: command
        command: 'skills/scope/scripts/hop-complete.sh --hop brief --topic "{{TOPIC}}" && skills/scope/scripts/hop-complete.sh --hop prd --topic "{{TOPIC}}" && skills/scope/scripts/hop-complete.sh --hop design --topic "{{TOPIC}}" && skills/scope/scripts/hop-complete.sh --hop plan --topic "{{TOPIC}}"'
    accepts:
      exit_artifacts:
        type: string
        required: true
        description: >
          Every durable artifact this run leaves behind, as the YAML the state
          file records: one path/status pair per artifact, not the PLAN alone.
      plan_execution_mode:
        type: enum
        values: [single-pr, multi-pr, coordinated]
        required: true
    transitions:
      - target: cleanup_full_run
        when:
          evidence.exit_artifacts: present
          gates.chain_complete.exit_code: 0
      - target: full_run_blocked
        when:
          evidence.exit_artifacts: present
          gates.chain_complete.exit_code: 1
      # Exit 2 is cannot-tell, and it goes where the refusal goes. It must not
      # route as complete, and it must not stall here: a broken or absent
      # validator is exactly the situation where an author most needs the
      # abandon option full_run_blocked offers, and a state with no matching
      # transition offers nothing. The failure_reason distinguishes the two --
      # the chain was not DECIDED, which is not the same finding as a hop being
      # incomplete, and the state file is where an author reads which happened.
      - target: full_run_blocked
        when:
          evidence.exit_artifacts: present
          gates.chain_complete.exit_code: 2
        context_assignments:
          failure_reason: "exit_full_run: chain completion could not be decided (chain_complete exit 2). No hop was found incomplete; the predicate reached no verdict."

  full_run_blocked:
    # phase: 3
    gates:
      # Re-declared here, identically, so this state's own blocking conditions
      # name the failing check. A self-loop back into exit_full_run would
      # re-evaluate the same gate and report nothing about why it failed; the
      # refusal is this state's whole reason to exist, so it carries the gate.
      chain_complete:
        type: command
        command: 'skills/scope/scripts/hop-complete.sh --hop brief --topic "{{TOPIC}}" && skills/scope/scripts/hop-complete.sh --hop prd --topic "{{TOPIC}}" && skills/scope/scripts/hop-complete.sh --hop design --topic "{{TOPIC}}" && skills/scope/scripts/hop-complete.sh --hop plan --topic "{{TOPIC}}"'
    accepts:
      next_move:
        type: enum
        values: [recheck, abandon]
        required: true
      detail:
        type: string
        description: What was produced or declared since the last check.
    transitions:
      - target: cleanup_full_run
        when:
          next_move: recheck
          gates.chain_complete.exit_code: 0
      - target: full_run_blocked
        when:
          next_move: recheck
          gates.chain_complete.exit_code: 1
      # A recheck that cannot be decided goes where the refused recheck goes,
      # rather than leaving the recheck with no arm at all. Same rule as at
      # exit_full_run, same reason: the state offering `abandon` is the one an
      # author needs to be standing in when the predicate stops answering.
      - target: full_run_blocked
        when:
          next_move: recheck
          gates.chain_complete.exit_code: 2
        context_assignments:
          failure_reason: "full_run_blocked: recheck could not be decided (chain_complete exit 2). No hop was found incomplete; the predicate reached no verdict."
      # The escape. An agent that cannot satisfy the chain-wide gate is not
      # stuck here permanently, and it is reachable on every gate outcome
      # because it names no gate.
      - target: exit_abandonment
        when:
          next_move: abandon

  exit_re_evaluation:
    # phase: 3
    gates:
      decision_record_present:
        type: command
        command: 'find docs/decisions -maxdepth 1 -type f -size +0 -name "DECISION-*-{{TOPIC}}-*.md" -print 2>/dev/null | grep -q .'
    accepts:
      boundary:
        type: enum
        values: [prd, design]
        required: true
      decision_record_sub_shape:
        type: enum
        values: [re-evaluation, rejection]
        required: true
      exit_artifacts:
        type: string
        required: true
        description: The Decision Record's path and status, as the state file records them.
      retry_or_abandon:
        type: enum
        values: [retry, abandon]
        required: true
    transitions:
      # Every arm carries retry_or_abandon, including the passing one. koto
      # rejects transitions out of a state that share no field, so the
      # discriminating value has to appear on the arm that succeeds and not only
      # on the escapes.
      - target: cleanup_re_evaluation
        when:
          retry_or_abandon: retry
          gates.decision_record_present.exit_code: 0
      - target: exit_re_evaluation
        when:
          retry_or_abandon: retry
          gates.decision_record_present.exit_code: 1
      - target: exit_abandonment
        when:
          retry_or_abandon: abandon

  exit_abandonment:
    # phase: 3
    gates:
      # The force-materialized artifact is identified by the marker Phase 3
      # appends to its Status section, not by mere existence at a canonical
      # path: an artifact that was produced normally sits at the same path and
      # means something else. Both DESIGN locations are listed for the same
      # reason the design hop's gate reads the pair.
      forced_artifact_present:
        type: command
        command: 'grep -lF -- "scope-status-block: abandonment-forced" docs/briefs/BRIEF-{{TOPIC}}.md docs/prds/PRD-{{TOPIC}}.md docs/designs/DESIGN-{{TOPIC}}.md docs/designs/current/DESIGN-{{TOPIC}}.md docs/plans/PLAN-{{TOPIC}}.md 2>/dev/null | grep -q .'
    accepts:
      triggering_child:
        type: enum
        values: [brief, prd, design, plan]
        required: true
      exit_artifacts:
        type: string
        required: true
        description: The force-materialized artifact's path and status, as the state file records them.
      retry_or_cancel:
        type: enum
        values: [retry, cancel]
        required: true
    transitions:
      - target: cleanup_abandonment
        when:
          retry_or_cancel: retry
          gates.forced_artifact_present.exit_code: 0
      - target: exit_abandonment
        when:
          retry_or_cancel: retry
          gates.forced_artifact_present.exit_code: 1
      # The escape, for the same reason exit_re_evaluation has one.
      - target: done_cancelled
        when:
          retry_or_cancel: cancel

  bail:
    # phase: 3
    gates:
      # Child-intermediate prefixes only. The parent's own prefix, the state
      # file included, is not a child's output and is deliberately not part of
      # this test, which is why the patterns name the children rather than
      # excluding one file.
      child_intermediate_present:
        type: command
        command: 'find wip -maxdepth 2 \( -name "brief_{{TOPIC}}_*" -o -name "prd_{{TOPIC}}_*" -o -name "design_{{TOPIC}}_*" -o -name "plan_{{TOPIC}}_*" \) -print 2>/dev/null | grep -q .'
    accepts:
      bail_ack:
        type: enum
        # A two-value choice rather than an acknowledgement. The resume ladder
        # offers Force-materialize, and that option needs a destination that
        # does not depend on unrelated files -- an earlier shape let the same
        # author choice silently cancel or force-materialize depending on what
        # the gate found.
        values: [cancel, force_materialize]
        required: true
      detail:
        type: string
        description: What the author chose and why.
    transitions:
      # force_materialize names the gate on both outcomes rather than routing
      # past it: a state whose evidence ignores its own gate is rejected at
      # compile time, and the destination is the same either way on purpose.
      - target: exit_abandonment
        when:
          bail_ack: force_materialize
          gates.child_intermediate_present.exit_code: 0
      - target: exit_abandonment
        when:
          bail_ack: force_materialize
          gates.child_intermediate_present.exit_code: 1
      - target: done_cancelled
        when:
          bail_ack: cancel

  cleanup_full_run:
    # phase: 4
    # Cleanup is a pre-terminal state because a terminal's directive never
    # crosses the wire: the phase has to be instructed somewhere the agent still
    # ticks.
    accepts:
      cleanup_result:
        type: enum
        values: [done]
        required: true
    transitions:
      - target: done_full_run
        when:
          cleanup_result: done

  cleanup_re_evaluation:
    # phase: 4
    accepts:
      cleanup_result:
        type: enum
        values: [done]
        required: true
    transitions:
      - target: done_re_evaluation
        when:
          cleanup_result: done

  cleanup_abandonment:
    # phase: 4
    accepts:
      cleanup_result:
        type: enum
        values: [done]
        required: true
    transitions:
      - target: done_abandonment
        when:
          cleanup_result: done

  done_full_run:
    # phase: 4
    terminal: true

  done_re_evaluation:
    # phase: 4
    terminal: true

  done_abandonment:
    # phase: 4
    terminal: true

  done_cancelled:
    # phase: 4
    terminal: true
---

## setup

Establish the run: validate the topic slug, write the state file, confirm the
worktree is the one this run owns. Submit `setup_result: ready`, or `blocked`
with `detail`.

<!-- details -->

Procedure: `skills/scope/references/phases/phase-0-setup.md`. The fields the
state file carries: `skills/scope/references/state-schema.md`. Read them now;
the rest of this run assumes setup happened as they describe.

`blocked` is for a slug that fails its pattern, a state file that cannot be
written, or a session collision reported against another worktree. Anything
else, fix and submit `ready`.

**Ignore koto's discovery warnings about other sessions, on this tick and every
later one.** koto reports `migration skipped` and `state file corrupted` for
sessions unrelated to this run, on every tick and whatever store is configured.
"State file corrupted" reads as an invitation to tidy up, and acting on it would
destroy another run's session. Nothing in this workflow ever runs a cleanup or
cancel verb against a session it did not open -- not to clear a warning, not on
a collision, not when koto's own text recommends it.

Evidence schema:
- `setup_result`: `ready` or `blocked`
- `detail`: what blocked setup

## discovery

Establish what the author wants scoped and propose the chain that would scope
it. Submit `discovery_result: proposed`, or `blocked` with `detail`.

<!-- details -->

Procedure: `skills/scope/references/phases/phase-1-discovery.md`.

Discovery decides which hops the run proposes and in what order. It decides
nothing about whether any artifact is worth producing: that question has no
answer here, because none of the documents exist yet.

Evidence schema:
- `discovery_result`: `proposed` or `blocked`
- `detail`: what blocked discovery

## chain_proposal

Put the proposed chain to the author and record their answer.

Read the Chain-Proposal Output section of
`skills/scope/references/phases/phase-1-discovery.md` for the format the
proposal takes.

Submit `author_decision: proceed` to start the chain at `/brief`,
`author_decision: adjust` to return to discovery and re-propose, or
`author_decision: bail` to stop.

Evidence schema:
- `author_decision`: `proceed`, `adjust`, or `bail`
- `detail`: what the author asked to adjust, or why they bailed

## hop_brief

Run the BRIEF hop.

This hop's job is to put the feature's problem and its intended outcome on
disk, so that everything downstream has a stated problem to answer to rather
than an assumed one. That is what this hop is for, and it is the only thing to
decide here.

<!-- details -->

Run the eight-step per-child loop from
`skills/scope/references/phases/phase-2-chain-orchestration.md` in order:
the worktree-staleness check, the `parent_orchestration:` sentinel write, the
child invocation, the R20 structural file-existence check, the sentinel
cleanup, the child-snapshot capture, and the validator pass-through. The eighth
step, the consolidation judgment, does not run at this hop: it compares two
documents and only one exists.

Invoke `/brief` inline via the Skill tool with the topic slug.

The `brief_complete` gate runs after the child returns and before the artifact
is committed, so its result is independent of git state and a failed gate never
produces a commit claiming the hop landed. Commit the artifact to the run's
branch after the gate passes, staging the one canonical path with `git add --`
and naming the hop in the message.

Submit `outcome: landed` when the child produced the artifact, `outcome:
skipped` with the vocabulary reason in `detail` when the hop is held back, or
`outcome: bail` when the run stops here.

If you submit `landed` and nothing advances, the gate did not pass: read the
blocking conditions on the response. Exit code 1 means neither the artifact nor
a declared fold was found. Exit code 2 means the predicate could not decide --
a missing validator, or a validation that reached no verdict -- and the fix is
to the environment, not to the evidence.

Evidence schema:
- `outcome`: `landed`, `skipped`, or `bail`
- `detail`: the child's outcome, the skip reason, or the bail reason

## hop_prd

Run the PRD hop.

This hop's job is to state the requirements the feature must meet and the
criteria that decide it is done, in terms an implementer can be held to. That
is what this hop is for, and it is the only thing to decide here.

<!-- details -->

Run the eight-step per-child loop from
`skills/scope/references/phases/phase-2-chain-orchestration.md` in order.
Invoke `/prd` inline via the Skill tool, passing the nearest produced upstream
artifact's path as the invocation argument. Keep that path: the fold state asks
about the pair, and the upstream half of the pair is the argument you passed
here.

The `prd_complete` gate runs after the child returns and before the commit, for
the same reason it does at every hop.

`/prd` has a Phase-N reject. A reject is not a bail: submit `outcome: rejected`
and the run routes to the re-evaluation exit, where the boundary is `prd`.

Submit `outcome: landed` when the child produced the artifact, `skipped` with
the vocabulary reason, `rejected` on a Phase-N reject with the rationale in
`detail`, or `bail` when the run stops here.

Evidence schema:
- `outcome`: `landed`, `skipped`, `rejected`, or `bail`
- `detail`: the child's outcome, the skip reason, or the reject rationale

## hop_design

Run the DESIGN hop.

This hop's job is to settle how the feature is built -- the approach taken, the
alternatives weighed against it, and the reason this one won. That is what this
hop is for, and it is the only thing to decide here.

<!-- details -->

Run the eight-step per-child loop from
`skills/scope/references/phases/phase-2-chain-orchestration.md` in order.
Invoke `/design` inline via the Skill tool, passing the nearest produced
upstream artifact's path. Keep that path for the fold state.

The `design_complete` gate reads both canonical DESIGN locations,
`docs/designs/DESIGN-<topic>.md` and `docs/designs/current/DESIGN-<topic>.md`.
Either satisfies it. Do not move the artifact into `current/` to satisfy the
gate: that path is reached by a lifecycle transition long after this run ends.

`/design` has a Phase-N reject. Submit `outcome: rejected` to route to the
re-evaluation exit, where the boundary is `design`.

Evidence schema:
- `outcome`: `landed`, `skipped`, `rejected`, or `bail`
- `detail`: the child's outcome, the skip reason, or the reject rationale

## hop_plan

Run the PLAN hop.

This hop's job is to decompose the settled approach into implementable units,
in the order the work happens and with each unit's dependencies stated. That is
what this hop is for, and it is the only thing to decide here.

<!-- details -->

Run the eight-step per-child loop from
`skills/scope/references/phases/phase-2-chain-orchestration.md` in order.
Invoke `/plan` inline via the Skill tool, passing the nearest produced upstream
artifact's path. Keep that path for the fold state.

Record the execution mode `/plan` settled on -- `single-pr`, `multi-pr`, or
`coordinated`. The full-run exit requires it.

Submit `outcome: landed` when the child produced the PLAN, `skipped` with the
vocabulary reason, or `bail` when the run stops here.

Evidence schema:
- `outcome`: `landed`, `skipped`, or `bail`
- `detail`: the child's outcome, the skip reason, or the bail reason

## fold

Reach a `keep` or `absorb` verdict on the two documents this hop joined, then
run the stages that verdict requires.

<!-- details -->

You are holding two documents: the one that just landed, and the one this hop
handed the child as its invocation argument. What follows is about those two
and about nothing else.

Two documents that restate one problem at two altitudes cost a reader two reads
for one idea, and an obvious point articulated twice reads as ceremony. Sparing
the reader that is worth doing, and it is the only thing that ever removes a
document from a `/scope` run. It is worth doing here, about the pair in your
hands. It is not a reason to want fewer documents in general, and it decides
nothing about a document nobody has written.

Applying it needs what each of your two documents declares it contributes. Each
type declares one contribution, quoted here from that type's own format
reference:

- **BRIEF** — WHY: the problem the feature solves and the outcome a user should
  experience.
- **PRD** — WHAT: the requirements the feature must meet and the criteria that
  decide it is done.
- **DESIGN** — HOW: the technical approach, the alternatives weighed, and why
  this one.
- **PLAN** — WHEN: the order the work happens in, and what each unit depends on.

Find the two rows that describe your edge. The other two are not your question.
Read the upstream you are holding against its own row and ask one thing: does it
hold anything beyond that contribution which compression into a single section
would lose?

If it does, the verdict is `keep`, with a finding naming what the upstream holds
that the survivor would not. If it does not, the verdict is `absorb`, and the
carry check has to confirm every concern arrived before anything is deleted.

The judgment fires only when both endpoints of the edge this run drew were
produced by this run. The mechanics -- the firing condition, the citation
preflight, the compose-verify-move-re-validate sequence, the rollback, and the
judgment entry the state file records -- are in the Consolidation Judgment
section of `skills/scope/references/phases/phase-2-chain-orchestration.md`.
No check in this judgment may read either type's required-section list or
compare the two types' section sets.

On `absorb`, the survivor declares what it absorbed in its `absorbed:`
frontmatter and carries the contribution section each entry implies. That
declaration is what the exit gate reads: a hop with no artifact and no
declaration satisfies neither limb, and a hop marked skipped satisfies neither
either.

This state routes itself. Its two gates decide which hop has not run yet, so
submit the verdict and the engine goes to the next hop, or to finalization when
none remains. A gate that cannot decide a hop routes as though that hop has not
run: the run goes to the hop rather than past it, and never to finalization on
an undecided plan hop.

Evidence schema:
- `verdict`: `keep` or `absorb`
- `finding`: what the upstream holds that the survivor would not, or what the
  carry check confirmed arrived

## finalize

Choose the exit path this run takes. Submit the exit value alone -- each path's
required fields belong to that path's own state and are refused here.

<!-- details -->

Procedure: `skills/scope/references/phases/phase-3-exit-finalization.md`.

- `full-run` -- the chain completed through `/plan`.
- `re-evaluation` -- the chain ended at a settled-upstream boundary and a
  Decision Record records it.
- `abandonment-forced` -- the chain cannot complete its terminal artifact and a
  child's intermediate is force-materialized instead.

The fields each path needs are declared on its own state, so submitting them
here is an unknown-field error rather than a shortcut. That separation is what
stops one path's evidence satisfying another's.

Evidence schema:
- `exit`: `full-run`, `re-evaluation`, or `abandonment-forced`

## exit_full_run

Record the full-run exit: every durable artifact the run leaves behind, and the
execution mode `/plan` settled on.

<!-- details -->

The `chain_complete` gate runs the completion predicate once per hop. It passes
only when every hop has either its artifact at a canonical path or a declared
fold in a surviving downstream document. A hop marked skipped satisfies neither
limb, and a hop asserted away in prose satisfies neither.

`exit_artifacts` is every durable artifact, not the PLAN alone: a chain that
produced a BRIEF, a PRD and a DESIGN records all three alongside it, and one
whose BRIEF was absorbed records the surviving PRD without it.

`plan_execution_mode` is the mode `/plan` settled on. Submit it with the
artifacts; both are required here.

The gate has three outcomes, not two, and the run goes to `full_run_blocked` on
either non-zero one. Exit 1 is a finding: some hop has neither an artifact nor a
declared fold. Exit 2 is the absence of a finding: the predicate could not reach
a verdict, because the validator is missing or a validation returned no verdict.
Nothing about the chain was established in that case, and the two must not be
recorded as the same thing.

Evidence schema:
- `exit_artifacts`: the path/status pairs the state file records
- `plan_execution_mode`: `single-pr`, `multi-pr`, or `coordinated`

## full_run_blocked

The full-run exit did not go through. This state carries the same gate, so its
blocking conditions name the failing check and carry its exit code.

<!-- details -->

**Read the gate's exit code before anything else, and record which of the two
things happened.** `blocking_conditions[].output.exit_code` on the response
carries it.

- **Exit 1 — refused.** At least one hop has neither its artifact at a canonical
  path nor a declared fold in a surviving downstream document. This is a finding
  about the chain.
- **Exit 2 — undecided.** The predicate could not answer: the validator is
  absent, or a validation reached no verdict. Nothing was found incomplete. The
  fix is to the environment, not to the artifacts, and recording this as a
  refusal would send the next reader to the wrong place.

Write the distinction into the state file. The engine records the exit code in
the session, but the session does not travel with the branch, and a reader who
has only the state file cannot otherwise tell a chain that was refused from one
that was never decided.

The gate's output is an exit code and nothing else -- koto does not surface a
command gate's stdout or stderr -- so it cannot say *which* hop failed. Run the
predicate once per hop yourself to get that:

```bash
for HOP in brief prd design plan; do
  skills/scope/scripts/hop-complete.sh --hop "$HOP" --topic "<topic>"
done
```

Each invocation prints its own verdict, and the same three exit codes apply per
hop. A 2 on any hop is not a 1 on that hop.

Two moves are available.

`next_move: recheck` re-evaluates the gate. Take it after producing a missing
artifact, after a survivor declares the fold in its `absorbed:` frontmatter and
carries the contribution section that declaration implies, or after repairing
the environment that made the predicate undecidable. Do not take it having only
re-read the tree: the gate will find what it found before and the run returns
here. A recheck that comes back undecided returns here too, rather than
advancing or stalling.

`next_move: abandon` leaves the full-run path for the abandonment exit. Take it
when the missing hop cannot be produced.

There is no third move, and in particular there is no move that records the
chain as complete without the gate passing.

Evidence schema:
- `next_move`: `recheck` or `abandon`
- `detail`: what was produced or declared since the last check

## exit_re_evaluation

Record the re-evaluation exit: the boundary the chain ended at, the Decision
Record's sub-shape, and the artifacts the run leaves behind.

<!-- details -->

Write the Decision Record at its canonical path before submitting:

```
docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md
```

The four boundary and sub-shape combinations bind to the four templates in
`skills/scope/references/decision-record-{prd|design}-{re-evaluation|rejection}.md`.
Commit it with `git commit -F`: author-supplied prose, including a rejection
rationale, goes through stdin or a tempfile and is never interpolated into a
`-m` message.

The `decision_record_present` gate looks for a non-empty regular file matching
`docs/decisions/DECISION-*-<topic>-*.md`.

`retry_or_abandon: retry` is the ordinary submission: with the record written,
the gate passes and the run advances to cleanup; without it, the run returns
here with the gate reported. `retry_or_abandon: abandon` leaves for the
abandonment exit, so an agent that cannot produce the record is not stuck here.

Evidence schema:
- `boundary`: `prd` or `design`
- `decision_record_sub_shape`: `re-evaluation` or `rejection`
- `exit_artifacts`: the Decision Record's path and status
- `retry_or_abandon`: `retry` or `abandon`

## exit_abandonment

Record the abandonment-forced exit: which child was running, and the artifact
force-materialized from its intermediate.

<!-- details -->

Force-materialize the most-recently-running child's intermediate as a Draft
artifact at its canonical durable path, and append the marker to the END of that
artifact's existing Status section, on one line, with the field order shown:

```
<!-- scope-status-block: abandonment-forced; triggering-child: <name>; partial-phase-reached: <phase>; chain-started: <ISO-8601 timestamp> -->
```

`triggering_child` is resolved by the R8 tie-break in
`skills/scope/references/phases/phase-3-exit-finalization.md`: the child whose
Phase 2 invocation began most recently, ties broken by position in the planned
chain, later winning. The tie-break is mechanical and prompts nobody.

The `forced_artifact_present` gate looks for that marker in the five canonical
artifact paths, both DESIGN locations included. It is the marker rather than the
file that identifies a force-materialized artifact: a normally produced artifact
sits at the same path and means something else.

`retry_or_cancel: retry` is the ordinary submission. `retry_or_cancel: cancel`
ends the run at the cancelled terminal, so an agent that cannot materialize the
artifact is not stuck here. Advance with `--no-cleanup` on that tick as well:
the route to the cancelled terminal retains the per-hop record for the same
reason the cleanup states do.

Evidence schema:
- `triggering_child`: `brief`, `prd`, `design`, or `plan`
- `exit_artifacts`: the force-materialized artifact's path and status
- `retry_or_cancel`: `retry` or `cancel`

## bail

The run is stopping before its terminal artifact. Decide between a clean cancel
and a force-materialization.

<!-- details -->

Read the R8 Bail Route section of
`skills/scope/references/phases/phase-3-exit-finalization.md`.

The `child_intermediate_present` gate looks for a child's intermediate under
`wip/{brief,prd,design,plan}_<topic>_*` or research scratch under
`wip/research/{prd,design}_<topic>_*`. Nothing under the parent's own
`wip/scope_<topic>_*` prefix counts toward it: nothing under that prefix is a
child's output.

`bail_ack: force_materialize` routes to the abandonment exit whatever the gate
found. That is deliberate -- the resume ladder offers Force-materialize as an
author choice, and an author choice whose destination depends on unrelated files
is not a choice. The gate's finding tells you what there is to materialize; it
does not decide where the run goes.

`bail_ack: cancel` is the clean cancel: no terminal artifact, no `exit:` value,
no `triggering_child:`, and one deletion -- `wip/scope_<topic>_state.md`. The
deletion is that single path, not the prefix: `wip/scope_<topic>_handoff.md`
belongs to the router and is left in place so a later invocation can resume
against it.

Advance with `--no-cleanup` on the `koto next` that reaches the terminal. This
applies to the cancel route as much as to the three cleanup states: a cancelled
run is the one whose per-hop record a reader is most likely to want, because
the question after a cancel is what the run had done before it stopped.

Evidence schema:
- `bail_ack`: `cancel` or `force_materialize`
- `detail`: what the author chose and why

## cleanup_full_run

Run Phase 4 cleanup for a full-run exit, then submit `cleanup_result: done`.
Advance with `--no-cleanup`.

<!-- details -->

Procedure: `skills/scope/references/phases/phase-4-cleanup.md`. Remove the run's
`wip/` intermediates, including the state file, and confirm no committed
artifact references a `wip/` path.

`--no-cleanup` on the `koto next` that reaches the terminal is not optional
here. Without it the per-hop record is destroyed with the session at the exact
moment the run finishes and an author would go looking for it. The record is
read where it lives; it is never copied into a committed artifact or a
pull-request body.

Evidence schema:
- `cleanup_result`: `done`

## cleanup_re_evaluation

Run Phase 4 cleanup for a re-evaluation exit, then submit `cleanup_result:
done`. Advance with `--no-cleanup`.

<!-- details -->

Procedure: `skills/scope/references/phases/phase-4-cleanup.md`. Remove the run's
`wip/` intermediates, including the state file, and confirm no committed
artifact -- the Decision Record in particular -- references a `wip/` path.

`--no-cleanup` for the reason it carries at every cleanup state: the per-hop
record does not survive the session otherwise.

Evidence schema:
- `cleanup_result`: `done`

## cleanup_abandonment

Run Phase 4 cleanup for an abandonment-forced exit, then submit
`cleanup_result: done`. Advance with `--no-cleanup`.

<!-- details -->

Procedure: `skills/scope/references/phases/phase-4-cleanup.md`. Remove the run's
`wip/` intermediates, including the state file, and confirm no committed
artifact references a `wip/` path.

The force-materialized artifact keeps its marker; cleanup does not touch it.
`--no-cleanup` for the reason it carries at every cleanup state.

Evidence schema:
- `cleanup_result`: `done`

## done_full_run

The chain completed through `/plan` and the chain-wide gate credited every hop
with either its artifact or a declared fold.

## done_re_evaluation

The chain ended at a settled-upstream boundary. The Decision Record at
`docs/decisions/` is the durable record of that ending.

## done_abandonment

The chain could not complete its terminal artifact. A child's intermediate was
force-materialized as a Draft artifact carrying the abandonment marker in its
Status section.

## done_cancelled

The run was cancelled. Nothing was force-materialized and no exit was recorded:
a cancel finalizes nothing.
