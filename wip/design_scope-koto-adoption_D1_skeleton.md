---
name: scope
version: "1.0"
description: >
  Tactical-chain parent workflow. Sequences /scope's own phases: setup, discovery
  and chain proposal, four hop dispatches with a shared fold judgment between
  them, exit finalization along one of three exit paths, and per-path cleanup.
  Children (/brief, /prd, /design, /plan) are dispatched inline by the agent and
  are NOT materialized as koto children. Authoring rule for reviewers: every
  non-terminal state carries at least one when-guarded transition keyed on an
  agent evidence field, because a state whose routes resolve without the agent is
  advanced through silently and its directive is never delivered.
initial_state: setup

variables:
  TOPIC:
    description: Topic slug for this scope run
    required: true

states:

  setup:
    accepts:
      setup_result:
        type: enum
        values: [ready, blocked]
        required: true
    transitions:
      - target: discovery
        when:
          setup_result: ready
      - target: bail
        when:
          setup_result: blocked

  discovery:
    accepts:
      discovery_result:
        type: enum
        values: [proposed, blocked]
        required: true
    transitions:
      - target: chain_proposal
        when:
          discovery_result: proposed
      - target: bail
        when:
          discovery_result: blocked

  chain_proposal:
    accepts:
      author_decision:
        type: enum
        values: [proceed, adjust, bail]
        required: true
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
    gates:
      brief_complete:
        type: command
        command: "scripts/hop-complete.sh --topic '{{TOPIC}}' --hop brief"
    accepts:
      outcome:
        type: enum
        values: [landed, skipped, bail]
        required: true
    transitions:
      - target: hop_prd
        when:
          gates.brief_complete.exit_code: 0
          outcome: landed
      - target: hop_prd
        when:
          gates.brief_complete.exit_code: 1
          outcome: landed
      - target: hop_prd
        when:
          outcome: skipped
      - target: bail
        when:
          outcome: bail

  hop_prd:
    gates:
      prd_complete:
        type: command
        command: "scripts/hop-complete.sh --topic '{{TOPIC}}' --hop prd"
    accepts:
      outcome:
        type: enum
        values: [landed, skipped, bail]
        required: true
    transitions:
      - target: fold
        when:
          gates.prd_complete.exit_code: 0
          outcome: landed
      - target: fold
        when:
          gates.prd_complete.exit_code: 1
          outcome: landed
      - target: hop_design
        when:
          outcome: skipped
      - target: bail
        when:
          outcome: bail

  hop_design:
    gates:
      design_complete:
        type: command
        command: "scripts/hop-complete.sh --topic '{{TOPIC}}' --hop design"
    accepts:
      outcome:
        type: enum
        values: [landed, skipped, bail]
        required: true
    transitions:
      - target: fold
        when:
          gates.design_complete.exit_code: 0
          outcome: landed
      - target: fold
        when:
          gates.design_complete.exit_code: 1
          outcome: landed
      - target: hop_plan
        when:
          outcome: skipped
      - target: bail
        when:
          outcome: bail

  hop_plan:
    gates:
      plan_complete:
        type: command
        command: "scripts/hop-complete.sh --topic '{{TOPIC}}' --hop plan"
    accepts:
      outcome:
        type: enum
        values: [landed, skipped, bail]
        required: true
    transitions:
      - target: fold
        when:
          gates.plan_complete.exit_code: 0
          outcome: landed
      - target: fold
        when:
          gates.plan_complete.exit_code: 1
          outcome: landed
      - target: finalize
        when:
          outcome: skipped
      - target: bail
        when:
          outcome: bail

  fold:
    gates:
      plan_present:
        type: command
        command: "test -f docs/plans/PLAN-{{TOPIC}}.md"
      design_present:
        type: command
        command: "test -f docs/designs/current/DESIGN-{{TOPIC}}.md"
    accepts:
      verdict:
        type: enum
        values: [keep, absorb]
        required: true
    transitions:
      - target: finalize
        when:
          gates.plan_present.exit_code: 0
          verdict: keep
      - target: finalize
        when:
          gates.plan_present.exit_code: 0
          verdict: absorb
      - target: hop_plan
        when:
          gates.plan_present.exit_code: 1
          gates.design_present.exit_code: 0
          verdict: keep
      - target: hop_plan
        when:
          gates.plan_present.exit_code: 1
          gates.design_present.exit_code: 0
          verdict: absorb
      - target: hop_design
        when:
          gates.plan_present.exit_code: 1
          gates.design_present.exit_code: 1
          verdict: keep
      - target: hop_design
        when:
          gates.plan_present.exit_code: 1
          gates.design_present.exit_code: 1
          verdict: absorb

  finalize:
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
    gates:
      chain_complete:
        type: command
        command: "scripts/chain-complete.sh --topic '{{TOPIC}}'"
    accepts:
      exit_artifacts:
        type: string
        required: true
      plan_execution_mode:
        type: enum
        values: [single-pr, multi-pr, coordinated]
        required: true
    transitions:
      - target: cleanup_full_run
        when:
          gates.chain_complete.exit_code: 0
          evidence.exit_artifacts: present
      - target: full_run_blocked
        when:
          gates.chain_complete.exit_code: 1
          evidence.exit_artifacts: present

  full_run_blocked:
    gates:
      chain_complete:
        type: command
        command: "scripts/chain-complete.sh --topic '{{TOPIC}}'"
    accepts:
      next_move:
        type: enum
        values: [recheck, abandon]
        required: true
    transitions:
      - target: cleanup_full_run
        when:
          gates.chain_complete.exit_code: 0
          next_move: recheck
      - target: full_run_blocked
        when:
          gates.chain_complete.exit_code: 1
          next_move: recheck
      - target: exit_abandonment
        when:
          next_move: abandon

  exit_re_evaluation:
    gates:
      decision_record_present:
        type: command
        command: "scripts/decision-record.sh --topic '{{TOPIC}}'"
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
    transitions:
      - target: cleanup_re_evaluation
        when:
          gates.decision_record_present.exit_code: 0
          evidence.exit_artifacts: present
      - target: exit_re_evaluation
        when:
          gates.decision_record_present.exit_code: 1
          evidence.exit_artifacts: present

  exit_abandonment:
    gates:
      forced_artifact_present:
        type: command
        command: "scripts/forced-artifact.sh --topic '{{TOPIC}}'"
    accepts:
      triggering_child:
        type: enum
        values: [brief, prd, design, plan]
        required: true
      exit_artifacts:
        type: string
        required: true
    transitions:
      - target: cleanup_abandonment
        when:
          gates.forced_artifact_present.exit_code: 0
          evidence.exit_artifacts: present
      - target: exit_abandonment
        when:
          gates.forced_artifact_present.exit_code: 1
          evidence.exit_artifacts: present

  bail:
    gates:
      child_intermediate_present:
        type: command
        command: "scripts/child-intermediate.sh --topic '{{TOPIC}}'"
    accepts:
      bail_ack:
        type: enum
        values: [confirmed]
        required: true
    transitions:
      - target: exit_abandonment
        when:
          gates.child_intermediate_present.exit_code: 0
          bail_ack: confirmed
      - target: done_cancelled
        when:
          gates.child_intermediate_present.exit_code: 1
          bail_ack: confirmed

  cleanup_full_run:
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
    terminal: true

  done_re_evaluation:
    terminal: true

  done_abandonment:
    terminal: true

  done_cancelled:
    terminal: true
---

## setup

PLACEHOLDER Phase 0. Validate the slug, detect visibility, create or self-heal
`wip/scope_{{TOPIC}}_state.md`, record this session under R14. Submit
`{"setup_result": "ready"}`.

## discovery

PLACEHOLDER Phase 1 discovery. Discover topic-related child docs, walk the shape
predicates, build the chain proposal. Submit `{"discovery_result": "proposed"}`.

## chain_proposal

PLACEHOLDER Phase 1 proposal. Present the chain with the Proceed / Adjust / Bail
triad and submit the author's answer.

## hop_brief

PLACEHOLDER hop. Dispatch `/brief` inline, then commit the artifact.

<!-- details -->

PLACEHOLDER hop details: the eight-step per-child loop.

## hop_prd

PLACEHOLDER hop. Dispatch `/prd` inline against the nearest surviving upstream
artifact, then commit.

## hop_design

PLACEHOLDER hop. Dispatch `/design` inline against the nearest surviving upstream
artifact, then commit.

## hop_plan

PLACEHOLDER hop. Dispatch `/plan` inline against the nearest surviving upstream
artifact, then commit.

## fold

PLACEHOLDER fold directive. You are holding two documents: the one this hop
handed the child as its invocation argument, and the one that just landed. Decide
`keep` or `absorb` for that pair.

<!-- details -->

PLACEHOLDER fold details. This is where the general-form reduction argument and
the four per-type summaries live. Delivered on first visit only.

## finalize

PLACEHOLDER Phase 3. Declare the exit path.

## exit_full_run

PLACEHOLDER full-run exit. Supply `exit_artifacts` and `plan_execution_mode`.

## full_run_blocked

PLACEHOLDER blocked state. The chain-completion check refused this exit. Re-run
`scripts/chain-complete.sh --topic {{TOPIC}}`; it prints the hops with neither an
artifact nor a recorded fold.

## exit_re_evaluation

PLACEHOLDER re-evaluation exit. Supply `boundary`, `decision_record_sub_shape`
and `exit_artifacts`.

## exit_abandonment

PLACEHOLDER abandonment-forced exit. Supply `triggering_child` and
`exit_artifacts`.

## bail

PLACEHOLDER bail. Route on whether a child intermediate exists.

## cleanup_full_run

PLACEHOLDER Phase 4 cleanup for the full-run path.

## cleanup_re_evaluation

PLACEHOLDER Phase 4 cleanup for the re-evaluation path.

## cleanup_abandonment

PLACEHOLDER Phase 4 cleanup for the abandonment path.

## done_full_run

Chain complete.

## done_re_evaluation

Chain ended at a settled-upstream boundary.

## done_abandonment

Chain abandoned; the most recent child intermediate was force-materialized.

## done_cancelled

Run cancelled before any child produced anything.
