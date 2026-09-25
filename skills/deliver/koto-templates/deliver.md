---
name: deliver
version: "1.0"
# koto-floor: pinned -- constrained variables, request-leg gates, transition
# context_assignments reading leg payloads, non-overridable gates, default
# actions writing context, and result maps need koto 0.13.0 or
# later, the floor skills/deliver/requires.tsv declares. The v0.12.2 floor
# check (scripts/check-koto-floor.sh) does not cover this template.
description: >
  /deliver's driver: /scope then /execute in one session, each reached as a
  root child through a per-run koto request leg and read only through a
  request-leg gate. Checks the repository binding, opens this run's request
  (superseding any earlier one for the topic), runs /scope --intent=continue
  on the scope leg, re-checks the PLAN and the owned scoping PR, routes on the
  PLAN's mode, asks one confirmation when interactive, runs /execute on the
  execute leg, re-checks the merge against GitHub, and ends in a
  result-declaring terminal that deliver-report.sh renders.

  A child's word never moves the run forward on its own. Every progress arm
  needs a promoted, valid result on its leg, and each is re-checked against
  durable state before the next step: scoped_check (the PLAN tracked, the
  owned PR recording intent=continue), mode_route (the PLAN's mode),
  executed_check and merged_check (the owned PR, re-read). The re-checks find
  the PR themselves through the shared ownership filter and never trust a
  leg's `pr`.

  Script output reaches routing only through context. A command gate exposes
  an exit code and nothing else, so each re-check runs deliver-probe.sh as a
  default action that clears its keys, then writes its verdict and the PR it
  verified (as `checked_pr` and as the result key `pr`) with `koto context
  add`, and the state routes on context-matches gates over those keys. A
  transition's context_assignments cannot read ${context.<key>}, so edges
  assign only literals, {{VAR}} values, and ${gates.<leg gate>.payload.*}
  paths, and every terminal's result map reads its keys as ${context.<key>}.

  The leg gates and every re-check gate are overridable: false, so no
  `koto overrides record`, with or without --with-data, can manufacture
  progress or a report. So are the preflight, mode_route and confirm gates:
  an override there would run /deliver in a private repository, send a
  multi-pr PLAN to /execute, or skip the interactive confirmation.

  No state pushes, merges, or writes to GitHub as a default action. The
  default actions are open_request, scope_absent and execute_absent, which
  touch only koto's request store, and the three re-checks, which only read
  git and GitHub and write only this session's own context keys. Every
  repository write happens inside /scope and /execute.

  Arguments are checked by koto, not by prose: deliver-open.sh maps each flag
  occurrence to one variable pair and passes them with --vars-file, so a value
  outside a variable's constraint, or a repeated flag, is refused at
  `koto init` with exit 2 and no session. Every gate and action command quotes
  each {{VAR}} it uses.
initial_state: preflight

variables:
  TOPIC:
    description: >
      The topic slug. Pattern ^[a-z0-9][a-z0-9-]*$, the same as scope.md's,
      so a slug can never be read as an option. Required and not rebindable:
      it names this session (deliver-<topic>), the request's coordinator, and
      both children's sessions (scope-<topic>, execute-<topic>).
    pattern: '^[a-z0-9][a-z0-9-]*$'
    required: true
  PLUGIN_ROOT:
    description: >-
      Absolute path to the shirabe plugin root, with no `..` segment (the same
      literal pattern scope.md and execute.md declare). Every gate and default
      action below runs a script that ships in the plugin, and koto runs them
      in the repository being delivered, so a relative path would not resolve.
      Rebindable, as in scope.md.
    pattern: '^/([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+|\.)?(/([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+|\.)?)*$'
    required: true
    rebind: true
  COORDINATION:
    description: >-
      The coordination flag the caller passed, forwarded to /scope unchanged:
      `coordinated` for --coordinated, `no-coordinated` for --no-coordinated,
      `none` when neither was given. Both together are a duplicate koto
      refuses. Not rebindable.
    values: [none, coordinated, no-coordinated]
    default: none
  MAX_ROUNDS:
    description: >-
      The --max-rounds value forwarded to /scope: an integer from 1 to 50, or
      empty for /scope's default. Rebindable, as in scope.md.
    pattern: '^([1-9]|[1-4][0-9]|50)?$'
    default: ""
    rebind: true
  UPSTREAM:
    description: >-
      The --upstream value forwarded to /scope: empty, a repository-relative
      docs/roadmaps/.../ROADMAP-*.md path, or `owner/repo:` followed by such a
      path, with no `..` segment anywhere (scope.md's pattern). Not
      rebindable.
    pattern: '^(([A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*:)?docs/roadmaps/(([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+)/)*ROADMAP-[^/]*\.md)?$'
    default: ""
  MODE:
    description: >-
      This invocation's execution mode, resolved once by deliver-open.sh from
      --auto / --interactive or the repository's `## Execution Mode:` header,
      and passed to both children. `interactive` asks one confirmation before
      /execute starts; `auto` asks nothing. Both flags together are a
      duplicate koto refuses.
    values: [auto, interactive]
    default: interactive
    rebind: true
  MERGE:
    description: >-
      Whether /execute is run with --merge: `true` unless the invocation
      passed --no-merge, which deliver-open.sh maps to `false`. Per
      invocation: every /deliver run is a fresh session, so an earlier run's
      setting is never remembered.
    values: ["true", "false"]
    default: "false"
    rebind: true

states:
  preflight:
    # /deliver inherits /scope's repository binding: public-repo tactical
    # chains only, with the visibility read the way /scope reads it. Gate-only;
    # a private or unknown repository ends here, before any request is written.
    # Not overridable: an override would run /deliver where it must not run.
    gates:
      public_repo:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/deliver/scripts/deliver-preflight.sh"'
        overridable: false
    transitions:
      - target: open_request
        when:
          gates.public_repo.exit_code: 0
      - target: done_refused
        when:
          gates.public_repo.exit_code: 1
        context_assignments:
          outcome: refused
          reason: private-repo
          step: "deliver:refused"
          failure_reason: "/deliver stopped: deliver:refused"
      - target: done_refused
        when:
          gates.public_repo.exit_code: 2
        context_assignments:
          outcome: refused
          reason: private-repo
          step: "deliver:refused"
          failure_reason: "/deliver stopped: deliver:refused"

  open_request:
    # A default action touching only koto's request store, and safe to re-run:
    # it abandons every request still open under this run's coordinator
    # (deliver-<topic>) and creates this run's, with the scope and execute
    # legs. The id is captured as REQ, which both leg gates and both child
    # directives read. Abandoning first is the stale-run fence: a late result
    # from an earlier run is refused at promotion.
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/deliver/scripts/deliver-open-request.sh" --topic "{{TOPIC}}"'
      capture_stdout_as: REQ
      fallback: >-
        koto could not open this run's request. Read the command's own output
        above: exit 1 means a `koto request` call failed or printed no usable
        id, 64 a usage error. Nothing else was written. Fix the cause and tick
        again; the action re-runs on entry, abandoning any request an earlier
        attempt created.
    transitions:
      - target: scope_run

  scope_run:
    # Agent-run: the agent runs /scope on the scope leg; its session attaches
    # to the leg itself (--koto-leg), and its terminal result, or koto's
    # refusal of its arguments or attach, arrives on the leg. An open leg is a
    # temporal block: the stop is the wait, so there is no arm for it.
    #
    # Two gates read the one leg. scope_leg's `expect` is /scope's whole
    # outcome set, `refused` included, so `valid` is false for any outcome
    # /scope doesn't declare. scope_intent's `expect` is the two intent
    # refusal reasons, so its `valid` separates an intent mismatch from every
    # other refusal without enumerating them.
    #
    # Routing keys on the result's source before its outcome: only a promoted
    # result can move the run forward. An explicit result (a hand-made
    # `koto request resolve`, or scope_absent's fixed record) reaches only
    # deliver:child-absent, whatever outcome it claims, and its payload is not
    # copied: that arm clears the leg-derived keys instead, so a forged `pr`
    # never reaches the result. Every other arm copies the leg's payload keys
    # into context (K2); /scope's `outcome` lands in `scope_outcome`, because
    # `outcome` is this run's own result key.
    gates:
      scope_leg:
        type: request-leg
        request: "{{REQ}}"
        leg: scope
        expect:
          outcome: [scoped, handed-off-multi-pr, executed, re-evaluation, abandonment, cancelled, refused, error]
        overridable: false
      scope_intent:
        type: request-leg
        request: "{{REQ}}"
        leg: scope
        expect:
          reason: [intent-mismatch, "var-mismatch:INTENT_FLAG"]
        overridable: false
    accepts:
      child_returned:
        type: enum
        values: ["yes"]
        description: >-
          Submit only when the /scope Skill call has returned and the leg is
          still open: the child never recorded a result. It reaches only an
          error. Never submit it while /scope is still running.
    transitions:
      # Promoted and valid: progress, each re-checked before the next step.
      - target: scoped_check
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: promoted
          gates.scope_leg.valid: true
          gates.scope_leg.payload.outcome: scoped
        context_assignments:
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      - target: scoped_check
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: promoted
          gates.scope_leg.valid: true
          gates.scope_leg.payload.outcome: handed-off-multi-pr
        context_assignments:
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      - target: executed_check
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: promoted
          gates.scope_leg.valid: true
          gates.scope_leg.payload.outcome: executed
        context_assignments:
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      # /scope stopped before a PLAN: scope-ended-early, naming which.
      - target: done_stopped
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: promoted
          gates.scope_leg.valid: true
          gates.scope_leg.payload.outcome: re-evaluation
        context_assignments:
          outcome: scope-ended-early
          reason: re-evaluation
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      - target: done_stopped
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: promoted
          gates.scope_leg.valid: true
          gates.scope_leg.payload.outcome: abandonment
        context_assignments:
          outcome: scope-ended-early
          reason: abandonment
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      - target: done_stopped
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: promoted
          gates.scope_leg.valid: true
          gates.scope_leg.payload.outcome: cancelled
        context_assignments:
          outcome: scope-ended-early
          reason: cancelled
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      # /scope's own error, carrying its step (deliver-report.sh checks it).
      - target: done_error
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: promoted
          gates.scope_leg.valid: true
          gates.scope_leg.payload.outcome: error
        context_assignments:
          outcome: error
          step: "${gates.scope_leg.payload.step}"
          failure_reason: "/deliver stopped: ${gates.scope_leg.payload.step}"
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      # /scope's own refusal (its done_refused terminal).
      - target: done_error
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: promoted
          gates.scope_leg.valid: true
          gates.scope_leg.payload.outcome: refused
          gates.scope_intent.valid: true
        context_assignments:
          outcome: error
          step: "deliver:intent-mismatch"
          failure_reason: "/deliver stopped: deliver:intent-mismatch"
          reason: "${gates.scope_leg.payload.reason}"
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      - target: done_error
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: promoted
          gates.scope_leg.valid: true
          gates.scope_leg.payload.outcome: refused
          gates.scope_intent.valid: false
        context_assignments:
          outcome: error
          step: "scope:refused"
          failure_reason: "/deliver stopped: scope:refused"
          reason: "${gates.scope_leg.payload.reason}"
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      # A promoted result /deliver does not recognise.
      - target: done_error
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: promoted
          gates.scope_leg.valid: false
        context_assignments:
          outcome: error
          step: "deliver:child-outcome"
          failure_reason: "/deliver stopped: deliver:child-outcome"
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      # koto refused /scope's arguments or its attach and recorded it on the
      # leg: var-mismatch:INTENT_FLAG is a live run with another intent.
      - target: done_error
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: refused
          gates.scope_intent.valid: true
        context_assignments:
          outcome: error
          step: "deliver:intent-mismatch"
          failure_reason: "/deliver stopped: deliver:intent-mismatch"
          reason: "${gates.scope_leg.payload.reason}"
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      - target: done_error
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: refused
          gates.scope_intent.valid: false
        context_assignments:
          outcome: error
          step: "scope:refused"
          failure_reason: "/deliver stopped: scope:refused"
          reason: "${gates.scope_leg.payload.reason}"
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      # Explicit: resolved by hand or by scope_absent. Only an error, and the
      # payload is not copied.
      - target: done_error
        when:
          gates.scope_leg.disposition: resolved
          gates.scope_leg.source: explicit
        context_assignments:
          outcome: error
          step: "deliver:child-absent"
          failure_reason: "/deliver stopped: deliver:child-absent"
          scope_outcome: ""
          plan_path: ""
          plan_execution_mode: ""
          pr: ""
          pr_state: ""
          startable: ""
          wip_paths: ""
          next: ""
      # This run's own request was abandoned (or closed) under it.
      - target: done_error
        when:
          gates.scope_leg.disposition: abandoned
        context_assignments:
          outcome: error
          step: "deliver:request-abandoned"
          failure_reason: "/deliver stopped: deliver:request-abandoned"
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      - target: done_error
        when:
          gates.scope_leg.disposition: missing
        context_assignments:
          outcome: error
          step: "deliver:request-abandoned"
          failure_reason: "/deliver stopped: deliver:request-abandoned"
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"
      # The Skill returned and nothing ever bound or answered the leg.
      - target: scope_absent
        when:
          child_returned: "yes"
          gates.scope_leg.disposition: open
          gates.scope_leg.bound: false
        context_assignments:
          scope_outcome: "${gates.scope_leg.payload.outcome}"
          plan_path: "${gates.scope_leg.payload.plan_path}"
          plan_execution_mode: "${gates.scope_leg.payload.plan_execution_mode}"
          pr: "${gates.scope_leg.payload.pr}"
          pr_state: "${gates.scope_leg.payload.pr_state}"
          startable: "${gates.scope_leg.payload.startable}"
          wip_paths: "${gates.scope_leg.payload.wip_paths}"
          next: "${gates.scope_leg.payload.next}"

  scope_absent:
    # Resolves the scope leg with the one fixed value /deliver writes,
    # {outcome: error, step: deliver:child-absent}, and returns to scope_run,
    # whose explicit arm ends the run. If /scope bound the leg in the
    # meantime, koto refuses the resolve (a self-attached leg answers only by
    # promotion), the action still succeeds, and scope_run keeps waiting.
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/deliver/scripts/deliver-absent.sh" --request "{{REQ}}" --leg scope'
      fallback: >-
        koto could not record that /scope returned without a result. Read the
        command's own output above: exit 1 means the scope leg is still open
        and unbound after the attempt, or could not be read. Tick again to
        re-run it; there is no evidence to submit here.
    transitions:
      - target: scope_run

  scoped_check:
    # The durable re-check behind a scoped or handed-off-multi-pr result:
    # the PLAN tracked and unchanged at HEAD, the owned scoping PR verified
    # with intent=continue, found through owned-pr.sh. deliver-probe.sh clears
    # scoped_verdict, checked_pr and pr, then writes the verdict and, on pass,
    # the verified PR as checked_pr and pr, replacing the leg's copy. An
    # absent verdict matches no pass arm.
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/deliver/scripts/deliver-probe.sh" scoped --topic "{{TOPIC}}" --session "deliver-{{TOPIC}}"'
      fallback: >-
        koto could not record the scoping re-check. Read the command's own
        output above: exit 66 means a `koto context` call failed, 64 a usage
        error. The keys were cleared first, so nothing stale is read as
        current. Fix the cause and tick again; there is no evidence to submit
        and no override.
    gates:
      scoped_pass:
        type: context-matches
        key: scoped_verdict
        pattern: '^pass$'
        overridable: false
      scoped_pr:
        type: context-matches
        key: checked_pr
        pattern: '^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'
        overridable: false
    transitions:
      - target: mode_route
        when:
          gates.scoped_pass.matches: true
          gates.scoped_pr.matches: true
      - target: done_error
        when:
          gates.scoped_pass.matches: false
        context_assignments:
          outcome: error
          step: "deliver:child-outcome"
          failure_reason: "/deliver stopped: deliver:child-outcome"
      - target: done_error
        when:
          gates.scoped_pass.matches: true
          gates.scoped_pr.matches: false
        context_assignments:
          outcome: error
          step: "deliver:child-outcome"
          failure_reason: "/deliver stopped: deliver:child-outcome"

  mode_route:
    # Gate-only over plan-mode.sh: single-pr and coordinated go on toward
    # /execute; a multi-pr PLAN is handed off without starting /execute, with
    # the startable list scope_run copied; a PLAN without a valid mode stops.
    gates:
      plan_mode:
        type: command
        command: '"{{PLUGIN_ROOT}}/scripts/plan-mode.sh" "docs/plans/PLAN-{{TOPIC}}.md"'
        overridable: false
    transitions:
      - target: confirm
        when:
          gates.plan_mode.exit_code: 0
      - target: confirm
        when:
          gates.plan_mode.exit_code: 10
      - target: done_stopped
        when:
          gates.plan_mode.exit_code: 20
        context_assignments:
          outcome: handed-off-multi-pr
      - target: done_error
        when:
          gates.plan_mode.exit_code: 4
        context_assignments:
          outcome: error
          step: "deliver:child-outcome"
          failure_reason: "/deliver stopped: deliver:child-outcome"

  confirm:
    # One confirmation, interactive only. With MODE auto the gate passes and
    # the run goes on to /execute with no question, ignoring any stray
    # evidence; interactively the agent names the PLAN's mode and asks once.
    gates:
      mode_auto:
        type: command
        command: 'test "{{MODE}}" = auto'
        overridable: false
    accepts:
      decision:
        type: enum
        values: [proceed, stop]
        description: >-
          The author's answer to the one confirmation. Asked only when MODE is
          interactive.
    transitions:
      - target: execute_run
        when:
          gates.mode_auto.exit_code: 0
      - target: execute_run
        when:
          gates.mode_auto.exit_code: 1
          decision: proceed
      - target: done_stopped
        when:
          gates.mode_auto.exit_code: 1
          decision: stop
        context_assignments:
          outcome: scoped
          next: "/deliver {{TOPIC}}"

  execute_run:
    # Agent-run: the agent runs /execute on the execute leg. Same shape as
    # scope_run: the leg is read only through exec_leg, an open leg waits,
    # only a promoted valid result moves the run, an explicit result reaches
    # only deliver:child-absent with its payload not copied, and every other
    # arm copies pr, repos, resume and waiting (and reason) from the payload.
    # `next` is cleared: /scope's next command no longer applies once
    # /execute ran.
    gates:
      exec_leg:
        type: request-leg
        request: "{{REQ}}"
        leg: execute
        expect:
          outcome: [merged, ready-awaiting-merge, paused-for-review, paused-awaiting-merges, error]
        overridable: false
    accepts:
      child_returned:
        type: enum
        values: ["yes"]
        description: >-
          Submit only when the /execute Skill call has returned and the leg is
          still open: the child never recorded a result. It reaches only an
          error. Never submit it while /execute is still running.
    transitions:
      # A merged claim is re-read against GitHub before it is reported.
      - target: merged_check
        when:
          gates.exec_leg.disposition: resolved
          gates.exec_leg.source: promoted
          gates.exec_leg.valid: true
          gates.exec_leg.payload.outcome: merged
        context_assignments:
          pr: "${gates.exec_leg.payload.pr}"
          repos: "${gates.exec_leg.payload.repos}"
          resume: "${gates.exec_leg.payload.resume}"
          waiting: "${gates.exec_leg.payload.waiting}"
          reason: "${gates.exec_leg.payload.reason}"
          next: ""
      - target: done
        when:
          gates.exec_leg.disposition: resolved
          gates.exec_leg.source: promoted
          gates.exec_leg.valid: true
          gates.exec_leg.payload.outcome: ready-awaiting-merge
        context_assignments:
          outcome: ready-awaiting-merge
          pr: "${gates.exec_leg.payload.pr}"
          repos: "${gates.exec_leg.payload.repos}"
          resume: "${gates.exec_leg.payload.resume}"
          waiting: "${gates.exec_leg.payload.waiting}"
          reason: "${gates.exec_leg.payload.reason}"
          next: ""
      - target: done_stopped
        when:
          gates.exec_leg.disposition: resolved
          gates.exec_leg.source: promoted
          gates.exec_leg.valid: true
          gates.exec_leg.payload.outcome: paused-for-review
        context_assignments:
          outcome: paused-for-review
          pr: "${gates.exec_leg.payload.pr}"
          repos: "${gates.exec_leg.payload.repos}"
          resume: "${gates.exec_leg.payload.resume}"
          waiting: "${gates.exec_leg.payload.waiting}"
          reason: "${gates.exec_leg.payload.reason}"
          next: ""
      - target: done_stopped
        when:
          gates.exec_leg.disposition: resolved
          gates.exec_leg.source: promoted
          gates.exec_leg.valid: true
          gates.exec_leg.payload.outcome: paused-awaiting-merges
        context_assignments:
          outcome: paused-awaiting-merges
          pr: "${gates.exec_leg.payload.pr}"
          repos: "${gates.exec_leg.payload.repos}"
          resume: "${gates.exec_leg.payload.resume}"
          waiting: "${gates.exec_leg.payload.waiting}"
          reason: "${gates.exec_leg.payload.reason}"
          next: ""
      - target: done_error
        when:
          gates.exec_leg.disposition: resolved
          gates.exec_leg.source: promoted
          gates.exec_leg.valid: true
          gates.exec_leg.payload.outcome: error
        context_assignments:
          outcome: error
          step: "${gates.exec_leg.payload.step}"
          failure_reason: "/deliver stopped: ${gates.exec_leg.payload.step}"
          pr: "${gates.exec_leg.payload.pr}"
          repos: "${gates.exec_leg.payload.repos}"
          resume: "${gates.exec_leg.payload.resume}"
          waiting: "${gates.exec_leg.payload.waiting}"
          reason: "${gates.exec_leg.payload.reason}"
          next: ""
      - target: done_error
        when:
          gates.exec_leg.disposition: resolved
          gates.exec_leg.source: promoted
          gates.exec_leg.valid: false
        context_assignments:
          outcome: error
          step: "deliver:child-outcome"
          failure_reason: "/deliver stopped: deliver:child-outcome"
          pr: "${gates.exec_leg.payload.pr}"
          repos: "${gates.exec_leg.payload.repos}"
          resume: "${gates.exec_leg.payload.resume}"
          waiting: "${gates.exec_leg.payload.waiting}"
          reason: "${gates.exec_leg.payload.reason}"
          next: ""
      # koto refused /execute's arguments or its attach (another template,
      # another worktree, a stale leg) and recorded it on the leg.
      - target: done_error
        when:
          gates.exec_leg.disposition: resolved
          gates.exec_leg.source: refused
        context_assignments:
          outcome: error
          step: "execute:refused"
          failure_reason: "/deliver stopped: execute:refused"
          pr: "${gates.exec_leg.payload.pr}"
          repos: "${gates.exec_leg.payload.repos}"
          resume: "${gates.exec_leg.payload.resume}"
          waiting: "${gates.exec_leg.payload.waiting}"
          reason: "${gates.exec_leg.payload.reason}"
          next: ""
      - target: done_error
        when:
          gates.exec_leg.disposition: resolved
          gates.exec_leg.source: explicit
        context_assignments:
          outcome: error
          step: "deliver:child-absent"
          failure_reason: "/deliver stopped: deliver:child-absent"
          pr: ""
          repos: ""
          resume: ""
          waiting: ""
          reason: ""
          next: ""
      - target: done_error
        when:
          gates.exec_leg.disposition: abandoned
        context_assignments:
          outcome: error
          step: "deliver:request-abandoned"
          failure_reason: "/deliver stopped: deliver:request-abandoned"
          pr: "${gates.exec_leg.payload.pr}"
          repos: "${gates.exec_leg.payload.repos}"
          resume: "${gates.exec_leg.payload.resume}"
          waiting: "${gates.exec_leg.payload.waiting}"
          reason: "${gates.exec_leg.payload.reason}"
          next: ""
      - target: done_error
        when:
          gates.exec_leg.disposition: missing
        context_assignments:
          outcome: error
          step: "deliver:request-abandoned"
          failure_reason: "/deliver stopped: deliver:request-abandoned"
          pr: "${gates.exec_leg.payload.pr}"
          repos: "${gates.exec_leg.payload.repos}"
          resume: "${gates.exec_leg.payload.resume}"
          waiting: "${gates.exec_leg.payload.waiting}"
          reason: "${gates.exec_leg.payload.reason}"
          next: ""
      - target: execute_absent
        when:
          child_returned: "yes"
          gates.exec_leg.disposition: open
          gates.exec_leg.bound: false
        context_assignments:
          pr: "${gates.exec_leg.payload.pr}"
          repos: "${gates.exec_leg.payload.repos}"
          resume: "${gates.exec_leg.payload.resume}"
          waiting: "${gates.exec_leg.payload.waiting}"
          reason: "${gates.exec_leg.payload.reason}"
          next: ""

  execute_absent:
    # As scope_absent, for the execute leg.
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/deliver/scripts/deliver-absent.sh" --request "{{REQ}}" --leg execute'
      fallback: >-
        koto could not record that /execute returned without a result. Read
        the command's own output above: exit 1 means the execute leg is still
        open and unbound after the attempt, or could not be read. Tick again
        to re-run it; there is no evidence to submit here.
    transitions:
      - target: execute_run

  executed_check:
    # The durable re-check behind /scope's `executed` shortcut: no PLAN, the
    # DESIGN under docs/designs/current/, and one owned PR on the topic branch
    # found with owned-pr.sh --state all, its state read live.
    # deliver-probe.sh clears executed_verdict, checked_pr, pr and pr_state,
    # then writes the verdict and, on merged or open, the PR as checked_pr and
    # pr and its state as pr_state. /execute does not run.
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/deliver/scripts/deliver-probe.sh" executed --topic "{{TOPIC}}" --session "deliver-{{TOPIC}}"'
      fallback: >-
        koto could not record the executed-topic re-check. Read the command's
        own output above: exit 66 means a `koto context` call failed, 64 a
        usage error. The keys were cleared first. Fix the cause and tick
        again; there is no evidence to submit and no override.
    gates:
      executed_merged:
        type: context-matches
        key: executed_verdict
        pattern: '^merged$'
        overridable: false
      executed_open:
        type: context-matches
        key: executed_verdict
        pattern: '^open$'
        overridable: false
      executed_pr:
        type: context-matches
        key: checked_pr
        pattern: '^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'
        overridable: false
    transitions:
      - target: done
        when:
          gates.executed_merged.matches: true
          gates.executed_open.matches: false
          gates.executed_pr.matches: true
        context_assignments:
          outcome: merged
      - target: done
        when:
          gates.executed_merged.matches: false
          gates.executed_open.matches: true
          gates.executed_pr.matches: true
        context_assignments:
          outcome: ready-awaiting-merge
      - target: done_error
        when:
          gates.executed_merged.matches: false
          gates.executed_open.matches: false
        context_assignments:
          outcome: error
          step: "deliver:child-outcome"
          failure_reason: "/deliver stopped: deliver:child-outcome"
      - target: done_error
        when:
          gates.executed_merged.matches: true
          gates.executed_open.matches: false
          gates.executed_pr.matches: false
        context_assignments:
          outcome: error
          step: "deliver:child-outcome"
          failure_reason: "/deliver stopped: deliver:child-outcome"
      - target: done_error
        when:
          gates.executed_merged.matches: false
          gates.executed_open.matches: true
          gates.executed_pr.matches: false
        context_assignments:
          outcome: error
          step: "deliver:child-outcome"
          failure_reason: "/deliver stopped: deliver:child-outcome"

  merged_check:
    # /execute said merged; GitHub has to agree. deliver-probe.sh finds the
    # PR itself with owned-pr.sh --state all on the topic branch (never the
    # leg's pr), clears merged_verdict, checked_pr and pr, runs
    # merge-verdict.sh --confirm on it, and writes the verdict and that PR as
    # checked_pr and pr whichever the verdict. A failed or ambiguous lookup
    # writes not-merged and no PR. Anything but a confirmed merge can only
    # downgrade, to ready-awaiting-merge; no arm here upgrades.
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/deliver/scripts/deliver-probe.sh" merged --topic "{{TOPIC}}" --session "deliver-{{TOPIC}}"'
      fallback: >-
        koto could not record the merge re-check. Read the command's own
        output above: exit 66 means a `koto context` call failed, 64 a usage
        error. The keys were cleared first. Fix the cause and tick again; there
        is no evidence to submit and no override.
    gates:
      merged_confirmed:
        type: context-matches
        key: merged_verdict
        pattern: '^merged$'
        overridable: false
      merged_pr:
        type: context-matches
        key: checked_pr
        pattern: '^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'
        overridable: false
    transitions:
      - target: done
        when:
          gates.merged_confirmed.matches: true
          gates.merged_pr.matches: true
        context_assignments:
          outcome: merged
      - target: done
        when:
          gates.merged_confirmed.matches: false
        context_assignments:
          outcome: ready-awaiting-merge
      - target: done
        when:
          gates.merged_confirmed.matches: true
          gates.merged_pr.matches: false
        context_assignments:
          outcome: ready-awaiting-merge

  # The four terminals. Each declares the same result map; every key is read
  # from context. `outcome` and, where literal, `step` and `reason` were
  # assigned on the edge in; leg-derived keys were copied from the leg's
  # payload; `pr` (and `pr_state`) was written by deliver-probe.sh wherever a
  # re-check ran, replacing the leg's copy. `outcome: refused` is a payload
  # value only: deliver-report.sh prints it as outcome=error.
  done:
    terminal: true
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.pr}"
      pr_state: "${context.pr_state}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"
      next: "${context.next}"
      startable: "${context.startable}"
      wip_paths: "${context.wip_paths}"

  done_stopped:
    terminal: true
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.pr}"
      pr_state: "${context.pr_state}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"
      next: "${context.next}"
      startable: "${context.startable}"
      wip_paths: "${context.wip_paths}"

  done_error:
    terminal: true
    failure: true
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.pr}"
      pr_state: "${context.pr_state}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"
      next: "${context.next}"
      startable: "${context.startable}"
      wip_paths: "${context.wip_paths}"

  done_refused:
    terminal: true
    failure: true
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.pr}"
      pr_state: "${context.pr_state}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"
      next: "${context.next}"
      startable: "${context.startable}"
      wip_paths: "${context.wip_paths}"
---

## preflight

Checking that this repository is one /deliver runs in. koto reads the
repository's `## Repo Visibility:` header itself and routes on it; you only see
this state if the check could not run.

<!-- details -->

/deliver runs public-repo tactical chains only, the binding /scope has. The
check reads `## Repo Visibility:` in the repository's CLAUDE.md (or
CLAUDE.local.md): `Public` goes on, `Private` or no header ends the run refused
with `reason=private-repo`. The gate refuses overrides and there is nothing to
submit. If the gate reports another exit code, the script itself could not run:
read its output, fix the cause, and tick again.

## open_request

Opening this run's koto request. koto runs this itself; you only see it if the
action failed.

<!-- details -->

The action abandons every request still open under this topic's coordinator,
`deliver-{{TOPIC}}` -- an earlier /deliver run's -- and creates this run's, with
a `scope` leg and an `execute` leg. Nothing outside koto's local request store
is touched. Read the output above, fix the cause, and tick again.

## scope_run

Run `/scope` on this run's `scope` leg. Invoke the Skill tool with skill `scope`
and these arguments, built exactly as written:

`{{TOPIC}} --intent=continue --{{MODE}} --koto-leg={{REQ}}:scope`

followed by, from this run's forwarded settings:

- `--upstream {{UPSTREAM}}`, only when that value after `--upstream` is not
  empty;
- `--max-rounds={{MAX_ROUNDS}}`, only when that value after `=` is not empty;
- `--coordinated` when the coordination setting `{{COORDINATION}}` reads
  `coordinated`, `--no-coordinated` when it reads `no-coordinated`, and neither
  when it reads `none`.

Pass nothing else. Run /scope to its end exactly as its own directives say --
it opens or resumes `scope-{{TOPIC}}`, asks its own questions, and prints its
own exit block -- then call `koto next {{SESSION_NAME}} --no-cleanup` with no
evidence.

<!-- details -->

/scope reports to this run only through the leg: its session attaches to it
with `--koto-leg`, and its terminal result -- or koto's refusal of its
arguments or its attach -- is recorded there. This state reads the leg itself.
Never relay what /scope printed, and never submit an outcome: no evidence here
can carry one.

If `koto next` answers that it is still waiting on the leg, /scope has not
finished. Continue it; do not start it again.

Submit `child_returned: yes` only when the /scope Skill call has returned and
`koto next` still reports the leg open: /scope ended without ever recording a
result (a `--koto-leg` that named no open leg, or a /scope too old to know the
flag). That reaches only an error, `deliver:child-absent`. Never submit it
while /scope is still running.

Evidence schema:
- `child_returned`: `yes`, only in the case above

## scope_absent

Recording that /scope returned without a result. koto does this itself; you
only see this state if the action failed.

<!-- details -->

The action resolves the `scope` leg with the fixed record
`{outcome: error, step: deliver:child-absent}`. If /scope bound the leg in the
meantime, koto refuses the resolve and the run goes back to waiting on it. Read
the output above and tick again.

## scoped_check

Re-checking /scope's result against the repository. koto runs the check itself
and routes on its verdict; you only see this state if the check could not
record one.

<!-- details -->

The check confirms that `docs/plans/PLAN-{{TOPIC}}.md` is tracked and unchanged
at HEAD, that the branch is pushed at HEAD with one owned open PR recording
`intent=continue`, and it finds that PR itself through the ownership filter.
The PR it verified replaces the one the leg reported. The gates refuse
overrides and there is nothing to submit. Read the action's output, fix the
cause, and tick again.

## mode_route

Routing on the PLAN's mode. koto reads `execution_mode:` from
`docs/plans/PLAN-{{TOPIC}}.md` itself; you only see this state if that read
could not run.

<!-- details -->

`single-pr` and `coordinated` go on toward /execute. `multi-pr` ends the run
`handed-off-multi-pr` with the startable items /scope listed, and /execute is
never started. A PLAN with no valid mode ends the run in an error. The gate
refuses overrides; read its output, fix the cause, and tick again.

## confirm

Ask the author one question before /execute starts. First show the PLAN's mode:
run `"{{PLUGIN_ROOT}}/scripts/plan-mode.sh" docs/plans/PLAN-{{TOPIC}}.md`, which
prints `single-pr` or `coordinated`. Then ask, naming that mode, whether to run
/execute on `docs/plans/PLAN-{{TOPIC}}.md` now. Submit `decision: proceed` to
continue or `decision: stop` to end here.

<!-- details -->

This is the only question /deliver itself asks, and only when the run is
interactive; with `--auto` koto moves past this state without showing it. A
stop ends the run `scoped` with `next=/deliver {{TOPIC}}`: the PLAN and its
scoping PR stay as they are, and the next `/deliver {{TOPIC}}` picks the topic
up through /scope.

Evidence schema:
- `decision`: `proceed` or `stop`

## execute_run

Run `/execute` on this run's `execute` leg. Invoke the Skill tool with skill
`execute` and these arguments, built exactly as written:

`docs/plans/PLAN-{{TOPIC}}.md --{{MODE}} --koto-leg={{REQ}}:execute`

and then the merge flag. This run's merge setting is `{{MERGE}}`: when it reads
`true`, append `--merge`; when it reads `false`, append nothing -- never
`--merge=false`, never `--no-merge`.

Run /execute to its end exactly as its own directives say, then call
`koto next {{SESSION_NAME}} --no-cleanup` with no evidence.

<!-- details -->

/execute reports to this run only through the leg, the same way /scope did. On
a /deliver run it adopts the PR /scope published on this branch. Never relay
what /execute printed, and never submit an outcome.

If `koto next` answers that it is still waiting on the leg, /execute has not
finished; continue it. Submit `child_returned: yes` only when the /execute
Skill call has returned and the leg is still open. That reaches only an error,
`deliver:child-absent`.

Evidence schema:
- `child_returned`: `yes`, only in the case above

## execute_absent

Recording that /execute returned without a result. koto does this itself; you
only see this state if the action failed.

<!-- details -->

The action resolves the `execute` leg with the fixed record
`{outcome: error, step: deliver:child-absent}`. If /execute bound the leg in
the meantime, koto refuses the resolve and the run goes back to waiting on it.
Read the output above and tick again.

## executed_check

Re-checking an already-executed topic against GitHub. koto runs the check
itself and routes on its verdict; you only see this state if the check could
not record one.

<!-- details -->

/scope reported that the PLAN was already executed. The check confirms the
PLAN is gone and the DESIGN sits under `docs/designs/current/`, finds the one
owned PR on this branch itself, and reads whether it is merged or open. The
run then ends `merged` or `ready-awaiting-merge` without running /execute. The
gates refuse overrides; read the action's output, fix the cause, and tick
again.

## merged_check

Confirming the merge with GitHub. koto runs the read itself and routes on it;
you only see this state if the read could not record a verdict.

<!-- details -->

/execute reported `merged`. The check finds the owned PR on this branch itself,
never from /execute's result, and reads its state live. Only a confirmed merge
ends the run `merged`; anything else ends it `ready-awaiting-merge`. The gates
refuse overrides; read the action's output, fix the cause, and tick again.

## done

The run finished. Print its report, verbatim, and compose no line of your own:

```bash
koto status {{SESSION_NAME}} | "{{PLUGIN_ROOT}}/skills/deliver/scripts/deliver-report.sh"
```

## done_stopped

The run stopped at a named point: a confirmation declined, a multi-pr PLAN
handed off, /scope ending early, or /execute pausing. Print its report,
verbatim:

```bash
koto status {{SESSION_NAME}} | "{{PLUGIN_ROOT}}/skills/deliver/scripts/deliver-report.sh"
```

## done_error

The run stopped on an error; the report names the step. Print it, verbatim:

```bash
koto status {{SESSION_NAME}} | "{{PLUGIN_ROOT}}/skills/deliver/scripts/deliver-report.sh"
```

## done_refused

/deliver does not run in this repository. Print the report, verbatim:

```bash
koto status {{SESSION_NAME}} | "{{PLUGIN_ROOT}}/skills/deliver/scripts/deliver-report.sh"
```
