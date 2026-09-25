---
name: scope
version: "1.0"
# koto-floor: pinned -- constrained variables, a default action writing context
# behind non-overridable gates, and result maps need the koto release
# .tsuku.toml pins, the floor skills/scope/requires.tsv declares. The v0.12.2
# floor check (scripts/check-koto-floor.sh) does not cover this template.
description: >
  Tactical-chain orchestrator for /scope. Forty states across five phases:
  setup (intake, the branch check, resume routing and its five ladder
  prompts, setup), discovery and the chain proposal, four hop states, the
  shared fold state and the hop selector a resume enters the chain through,
  six exit states, three publish states, three cleanup states, the two intent
  shortcuts and the record state behind one of them, and eight terminals,
  each declaring its result. Each hop delivers its own directive on
  entry and carries a command gate that decides completion from the artifact
  tree through skills/scope/scripts/hop-complete.sh; the full-run exit re-runs
  that predicate for every hop and refuses unless each one has either its
  artifact or a declared fold.

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

  The routing states are the deliberate exceptions, and each is meant to
  resolve without the agent. `intake`, `executed_report` and
  `republish_record` take no evidence at all: a default action's script writes
  a verdict to context and non-overridable context-matches gates route on it,
  so no agent answer can stand in for the check. `resume_route` and
  `hop_select` route on non-overridable gates alone, because where a run
  resumes is read from the tree, never asserted. `branch_check` advances on
  its gate alone on the passing path and asks for evidence only when the gate
  fails.

  Every terminal declares a `result:` map, and every edge into one assigns
  `outcome` (and `step` on the error edges) as a literal through
  `context_assignments`. A value that comes from the repository -- the PLAN's
  path and mode, the next command, the owned PR -- is written to context by a
  record script run as a default action and read by the map as
  `${context.<key>}`, because an assignment cannot read context and a command
  gate carries nothing but an exit code. skills/scope/scripts/print-scope-exit.sh
  renders the printed exit block from that result.

  On intent runs each exit passes through a publish state before its cleanup:
  the exit states carry an `intent_declared` gate, every edge into a cleanup
  state requires it to fail (no intent), and a parallel edge on success goes
  to the publish state, so no intent run reaches cleanup unpublished and a
  no-intent run makes no gh call.

  Each state also carries a `# phase: N` comment naming the /scope phase it
  belongs to, so a run can report its phase from its position. koto rejects an
  undeclared state field, so the map is a comment rather than a `phase:` key.

  Arguments are checked by koto, not by prose. scripts/scope-open.sh maps each
  flag occurrence to one variable pair and passes them with --vars-file, so a
  value outside a variable's constraint, or a repeated flag, is refused at
  `koto init` with exit 2 and no session, and under --koto-leg the refusal is
  recorded on the leg. Every gate command quotes each {{VAR}} it uses.
initial_state: intake

variables:
  TOPIC:
    description: >
      The run's topic slug. Pattern ^[a-z0-9][a-z0-9-]*$: the pattern-level
      slug regex ^[a-z0-9-]+$ with no leading `-`, so a slug can never be read
      as an option. Required and not rebindable: it is the session's identity,
      and the session name scope-<topic> is composed from it. koto refuses any
      other value at `koto init` (exit 2, no session), and every gate command
      below interpolates it quoted.
    pattern: '^[a-z0-9][a-z0-9-]*$'
    required: true
  PLUGIN_ROOT:
    description: >-
      Absolute path to the shirabe plugin root, with no `..` segment (the same
      literal pattern /execute's template declares). scope-open.sh passes the
      plugin root the agent's own shell expanded once. Every gate below invokes
      a script that ships in the plugin, and koto runs a gate command with the
      working directory of the `koto next` process -- for /scope that is the
      repository being scoped, not this checkout. A repo-relative path therefore
      resolves only when /scope runs against shirabe itself; anywhere else the
      shell exits 127, and koto reports a failed command gate as an exit code
      with the command's own output discarded. Declared as a template variable
      rather than written as a shell-style ${CLAUDE_PLUGIN_ROOT} because koto
      resolves only {{KEY}} references. Rebindable: a later invocation, from
      another plugin install, re-applies its own value on attach. Whether the
      root lies inside the work tree is a fact a pattern cannot see, so it is
      carried by PLUGIN_ROOT_PLACEMENT below rather than refused by a script.
    pattern: '^/([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+|\.)?(/([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+|\.)?)*$'
    required: true
    rebind: true
  PLUGIN_ROOT_PLACEMENT:
    description: >-
      Where PLUGIN_ROOT lies relative to the repository being scoped, computed
      by scope-open.sh on every invocation from the resolved PLUGIN_ROOT and
      `git rev-parse --show-toplevel`, symlinks followed: `outside`, or
      `inside-worktree`. The pattern admits only `outside`, so koto refuses a
      plugin root inside the work tree at `koto init` (exit 2, no session;
      under --koto-leg, `invalid-var:PLUGIN_ROOT_PLACEMENT` on the leg). A
      plugin inside the work tree could be edited by the run its gates check.
      Required and rebindable, recomputed with PLUGIN_ROOT.
    pattern: '^outside$'
    required: true
    rebind: true
  INTENT_FLAG:
    description: >-
      The caller's `--intent` token, unmodified: `continue`, `stop`, or empty
      when the flag was not given (scope-open.sh leaves the variable out, and a
      lone explicitly empty `--intent=` is treated the same way). Pattern
      ^(continue|stop)?$, so koto itself refuses every other token --
      `none`, `unset`, `absent`, a bare `--intent` -- at `koto init`, and a
      repeated --intent is a duplicate it refuses too. Not rebindable: on a
      live session a differing explicit value is refused as var_mismatch,
      while an omitted one is not compared. This is not the effective intent:
      `intake` derives RUN_INTENT (continue|stop|none) from it and the state
      file's recorded `intent:`, and every later intent check keys on that.
    pattern: '^(continue|stop)?$'
    default: ""
  COORDINATION:
    description: >-
      The coordination flag the caller passed: `coordinated` for
      --coordinated, `no-coordinated` for --no-coordinated, `none` when
      neither was given. Both flags together are a duplicate koto refuses.
      Not rebindable. A CLAUDE.md coordination header never sets it: the
      /plan hop forwards only what the caller passed.
    values: [none, coordinated, no-coordinated]
    default: none
  EXEC_MODE:
    description: >-
      This invocation's execution mode: `auto` for --auto, `interactive` for
      --interactive; `interactive` when neither was given, and `default` is
      admitted as a synonym a caller may pass for that. Both flags together
      are a duplicate koto refuses. Rebindable, so a run picked up by a later
      invocation takes that invocation's mode rather than inheriting one.
    values: [auto, interactive, default]
    default: interactive
    rebind: true
  MAX_ROUNDS:
    description: >-
      The --max-rounds cap on re-evaluation re-entries: an integer from 1 to
      50, or empty for the default of 5. Rebindable, so a run picked up with a
      different value resumes rather than refusing.
    pattern: '^([1-9]|[1-4][0-9]|50)?$'
    default: ""
    rebind: true
  UPSTREAM:
    description: >-
      The --upstream value: empty, a repository-relative
      docs/roadmaps/.../ROADMAP-*.md path, or `owner/repo:` followed by such a
      path, with no `..` segment anywhere. A bare --upstream reaches koto as
      the literal token and fails the pattern. The checks that need the
      working tree (under wip/, tracked by git, confined after symlinks,
      basename) run in `intake`. Not rebindable.
    pattern: '^(([A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*:)?docs/roadmaps/(([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+)/)*ROADMAP-[^/]*\.md)?$'
    default: ""

states:
  intake:
    # phase: 0
    # The checks koto's variable constraints cannot express, because they need
    # the working tree: the --upstream battery, and an explicit --intent that
    # differs from the intent an unfinished run whose session is gone already
    # recorded. It also resolves the effective intent, RUN_INTENT, which every
    # later intent check keys on and which is delivered to every later state.
    #
    # Script output reaches routing only through context. A command gate
    # exposes an exit code and nothing else, so a refusal's reason and the
    # recorded intent would never reach the terminal's result through one.
    # run-intake.sh clears intake_verdict, reason and recorded, runs the
    # checks, and writes the verdict with `koto context add`; the gates below
    # read it. They are overridable: false, so no `koto overrides record` can
    # stand in for the script's answer, and the state takes no evidence.
    #
    # An absent verdict (a run interrupted before the write) matches neither
    # gate and routes to done_error, never to branch_check. The session name is
    # rebuilt from {{TOPIC}}, which is exactly the name scope-open.sh opens.
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/run-intake.sh" --session "scope-{{TOPIC}}" --topic "{{TOPIC}}" --intent-flag "{{INTENT_FLAG}}" --upstream "{{UPSTREAM}}"'
      capture_stdout_as: RUN_INTENT
      fallback: >-
        koto could not record the intake verdict. Read the command's own output
        above: exit 66 means a `koto context` call failed, and exit 64 a usage
        error in the command itself. There is no evidence to submit here -- the
        verdict is the script's to write, and its gates refuse overrides -- so
        fix the cause and tick again; the checks re-run on entry. If it keeps
        failing, stop and report the output: the run cannot start.
    gates:
      intake_ok:
        type: context-matches
        key: intake_verdict
        pattern: '^ok$'
        overridable: false
      intake_refused:
        type: context-matches
        key: intake_verdict
        pattern: '^refused$'
        overridable: false
    transitions:
      - target: branch_check
        when:
          gates.intake_ok.matches: true
      # The refusal. Only literals and a variable are assigned here: an
      # assignment cannot read context, so `reason` and `recorded`, which the
      # script wrote, are read by done_refused's result map instead.
      - target: done_refused
        when:
          gates.intake_ok.matches: false
          gates.intake_refused.matches: true
        context_assignments:
          outcome: refused
          step: "scope:refused"
          requested: "{{INTENT_FLAG}}"
          failure_reason: "intake: the invocation was refused; the result's reason names the check"
      # `error`, or no verdict at all.
      - target: done_error
        when:
          gates.intake_ok.matches: false
          gates.intake_refused.matches: false
        context_assignments:
          outcome: error
          step: "scope:intake"
          requested: "{{INTENT_FLAG}}"
          failure_reason: "intake: a check could not read what it needs, or no verdict was recorded"

  branch_check:
    # phase: 0
    # The branch this run commits its hops to, read once and delivered to every
    # later state. `setup` used to ask the agent, in prose, to "confirm HEAD is
    # on a named branch that is not the repository's default", and nothing
    # enforced it -- the state declared no gates at all, and the same check was
    # restated as a shell block in the per-hop commit procedure. The gate below
    # is that check, made structural.
    #
    # `main` and `master` are named literally alongside the emptiness test.
    # Resolving the real default would be better, but
    # `refs/remotes/origin/HEAD` is absent in a clone that never fetched it, and
    # a fallback resolving to nothing leaves the check satisfied by every
    # branch. The repo's own per-hop commit procedure makes the same trade.
    #
    # The emptiness test is not redundant: on a detached HEAD `git symbolic-ref
    # --quiet` prints nothing and exits 1, and a `grep -v` form of this check
    # passes on empty input.
    default_action:
      command: git symbolic-ref --quiet --short HEAD
      capture_stdout_as: BRANCH
      fallback: >-
        koto could not read a branch name, which usually means HEAD is
        detached. Read the command's own output above, then run `git
        symbolic-ref --quiet --short HEAD` yourself. Check out a named branch
        that is not the repository's default and tick again -- the check re-runs
        on entry. Submit `branch_status: blocked` with `detail` only if you
        cannot get onto one.
    gates:
      on_named_non_default_branch:
        type: command
        command: 'test -n "$(git symbolic-ref --quiet --short HEAD)" && test "$(git symbolic-ref --quiet --short HEAD)" != "main" && test "$(git symbolic-ref --quiet --short HEAD)" != "master"'
    accepts:
      branch_status:
        type: enum
        values: [override, blocked]
        description: >-
          Absent on the passing path. The state advances with no evidence when
          the gate passes, so the agent never sees it.
      detail:
        type: string
        description: Why the branch could not be settled, when blocked.
    transitions:
      - target: resume_route
        when:
          gates.on_named_non_default_branch.exit_code: 0
      - target: resume_route
        when:
          gates.on_named_non_default_branch.exit_code: 1
          branch_status: override
      - target: bail
        when:
          gates.on_named_non_default_branch.exit_code: 1
          branch_status: blocked

  resume_route:
    # phase: 0
    # The resume ladder, as one read-only probe. resume-probe.sh reads the
    # artifact tree, the state file, the child partials and the /explore
    # handoff, and exits with the row code; each arm below sends one code to
    # the state skills/scope/references/phases/phase-resume.md names for that
    # row. The ladder used to run as agent prose, which let a run decide where
    # it stood by saying so.
    #
    # The probe makes no write. The default action beside it writes the PLAN
    # facts (plan_path, plan_execution_mode, next, startable) to context, so
    # row 41's refusal can name the next command by the PLAN's mode (R23) --
    # an assignment cannot read the PLAN, and the probe must not write.
    #
    # The gate refuses overrides: an override could send the run anywhere,
    # and where it resumes is a fact of the tree. A code no arm names (a
    # missing script's 127, say) holds the run with the gate reported.
    #
    # `resume_hop` is the hop a partial, a draft or a boundary Revise re-enters
    # at; `setup` routes on it. Arms into `setup` that start fresh clear it.
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/record-scope-exit.sh" --session "scope-{{TOPIC}}" --topic "{{TOPIC}}" --intent "{{RUN_INTENT}}" --stage resume'
      fallback: >-
        koto could not record the PLAN facts resume routing reads. Read the
        command's own output above: exit 66 means a `koto context` call
        failed, and exit 64 a usage error in the command itself. There is no
        evidence to submit here; fix the cause and tick again.
    gates:
      ladder:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/resume-probe.sh" --topic "{{TOPIC}}" --intent "{{RUN_INTENT}}"'
        overridable: false
    transitions:
      # 10, 11: nothing on disk. 12: the /explore handoff, consumed in
      # discovery. 49: an Accepted BRIEF, the chain's anchor.
      - target: setup
        when:
          gates.ladder.exit_code: 10
        context_assignments:
          resume_hop: ""
      - target: setup
        when:
          gates.ladder.exit_code: 11
        context_assignments:
          resume_hop: ""
      - target: setup
        when:
          gates.ladder.exit_code: 12
        context_assignments:
          resume_hop: ""
      - target: setup
        when:
          gates.ladder.exit_code: 49
        context_assignments:
          resume_hop: ""
      # 20-22: a fresh state file, resumed at its pointer.
      - target: discovery
        when:
          gates.ladder.exit_code: 20
      - target: hop_select
        when:
          gates.ladder.exit_code: 21
        context_assignments:
          resume_hop: ""
      - target: finalize
        when:
          gates.ladder.exit_code: 22
      - target: resume_stale
        when:
          gates.ladder.exit_code: 24
      - target: resume_malformed
        when:
          gates.ladder.exit_code: 25
      - target: resume_exit_set
        when:
          gates.ladder.exit_code: 26
      # 27-29: an exit recorded with a failed publish; the retry.
      - target: publish_full_run
        when:
          gates.ladder.exit_code: 27
        context_assignments:
          exit: full-run
      - target: publish_re_evaluation
        when:
          gates.ladder.exit_code: 28
        context_assignments:
          exit: re-evaluation
      - target: publish_abandonment
        when:
          gates.ladder.exit_code: 29
        context_assignments:
          exit: abandonment-forced
      # 40-44: the PLAN's own lifecycle, and the two intent shortcuts.
      - target: republish
        when:
          gates.ladder.exit_code: 40
        context_assignments:
          exit: full-run
      - target: done_refused
        when:
          gates.ladder.exit_code: 41
        context_assignments:
          outcome: refused
          reason: plan-active
          step: "scope:refused"
          requested: "{{INTENT_FLAG}}"
          failure_reason: "resume_route: the PLAN is Active and owned by its executor; no intent was given"
      - target: done_refused
        when:
          gates.ladder.exit_code: 42
        context_assignments:
          outcome: refused
          reason: plan-done
          step: "scope:refused"
          next: "/release {{TOPIC}}"
          requested: "{{INTENT_FLAG}}"
          failure_reason: "resume_route: the PLAN is Done and owned by /release"
      - target: resume_draft
        when:
          gates.ladder.exit_code: 43
        context_assignments:
          resume_hop: plan
      - target: executed_report
        when:
          gates.ladder.exit_code: 44
      # 45-50: the settled boundaries and the drafts below the PLAN.
      - target: resume_boundary
        when:
          gates.ladder.exit_code: 45
        context_assignments:
          resume_hop: design
          boundary: design
      - target: resume_draft
        when:
          gates.ladder.exit_code: 46
        context_assignments:
          resume_hop: design
      - target: resume_boundary
        when:
          gates.ladder.exit_code: 47
        context_assignments:
          resume_hop: prd
          boundary: prd
      - target: resume_draft
        when:
          gates.ladder.exit_code: 48
        context_assignments:
          resume_hop: prd
      - target: resume_draft
        when:
          gates.ladder.exit_code: 50
        context_assignments:
          resume_hop: brief
      # 60-63: a child partial. setup runs, then hop_select enters its hop.
      - target: setup
        when:
          gates.ladder.exit_code: 60
        context_assignments:
          resume_hop: plan
      - target: setup
        when:
          gates.ladder.exit_code: 61
        context_assignments:
          resume_hop: design
      - target: setup
        when:
          gates.ladder.exit_code: 62
        context_assignments:
          resume_hop: prd
      - target: setup
        when:
          gates.ladder.exit_code: 63
        context_assignments:
          resume_hop: brief
      # 2: the probe could not tell.
      - target: done_error
        when:
          gates.ladder.exit_code: 2
        context_assignments:
          outcome: error
          step: "scope:resume-probe"
          requested: "{{INTENT_FLAG}}"
          failure_reason: "resume_route: the resume probe could not read what it needs (exit 2)"

  resume_stale:
    # phase: 0
    # Ladder row 4. The pointer gate re-runs the probe with --ignore-stale, so
    # Resume goes where a fresh state file would.
    gates:
      pointer:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/resume-probe.sh" --topic "{{TOPIC}}" --intent "{{RUN_INTENT}}" --ignore-stale'
        overridable: false
    accepts:
      stale_choice:
        type: enum
        values: [resume, force_materialize, discard]
        required: true
      detail:
        type: string
        description: What the author chose, and under --auto the announcement made.
    transitions:
      - target: discovery
        when:
          stale_choice: resume
          gates.pointer.exit_code: 20
      - target: hop_select
        when:
          stale_choice: resume
          gates.pointer.exit_code: 21
        context_assignments:
          resume_hop: ""
      - target: finalize
        when:
          stale_choice: resume
          gates.pointer.exit_code: 22
      - target: exit_abandonment
        when:
          stale_choice: force_materialize
      - target: setup
        when:
          stale_choice: discard
        context_assignments:
          resume_hop: ""

  resume_malformed:
    # phase: 0
    # Ladder row 1: a hard surface, never a fall-through.
    accepts:
      malformed_choice:
        type: enum
        values: [discard, stop]
        required: true
      detail:
        type: string
        description: The malformation, named.
    transitions:
      - target: setup
        when:
          malformed_choice: discard
        context_assignments:
          resume_hop: ""
      - target: done_cancelled
        when:
          malformed_choice: stop
        context_assignments:
          outcome: cancelled
          via: resume_malformed

  resume_exit_set:
    # phase: 0
    # Ladder row 2: the run already recorded an exit and has nothing left to
    # publish.
    accepts:
      exit_set_choice:
        type: enum
        values: [revise, start_fresh, bail]
        required: true
      detail:
        type: string
        description: What the author chose.
    transitions:
      - target: finalize
        when:
          exit_set_choice: revise
      - target: setup
        when:
          exit_set_choice: start_fresh
        context_assignments:
          resume_hop: ""
      - target: done_cancelled
        when:
          exit_set_choice: bail
        context_assignments:
          outcome: cancelled
          via: resume_exit_set

  resume_draft:
    # phase: 0
    # Ladder rows 5.3, 5.5, 5.7 and 5.9: a draft this chain owns. resume_route
    # set resume_hop to the draft's hop.
    accepts:
      draft_choice:
        type: enum
        values: [continue, discard, bail]
        required: true
      detail:
        type: string
        description: What the author chose.
    transitions:
      - target: setup
        when:
          draft_choice: continue
      - target: setup
        when:
          draft_choice: discard
        context_assignments:
          resume_hop: ""
      - target: done_cancelled
        when:
          draft_choice: bail
        context_assignments:
          outcome: cancelled
          via: resume_draft

  resume_boundary:
    # phase: 0
    # Ladder rows 5.4 and 5.6: a settled upstream. resume_route set boundary
    # and resume_hop to the boundary's own hop.
    accepts:
      boundary_choice:
        type: enum
        values: [re_evaluate, revise, bail]
        required: true
      detail:
        type: string
        description: What the author chose.
    transitions:
      - target: exit_re_evaluation
        when:
          boundary_choice: re_evaluate
      - target: setup
        when:
          boundary_choice: revise
      - target: done_cancelled
        when:
          boundary_choice: bail
        context_assignments:
          outcome: cancelled
          via: resume_boundary

  setup:
    # phase: 0
    # A resume that names a hop (a partial, a draft's Continue, a boundary's
    # Revise) goes through hop_select to that hop once setup is done; every
    # other run goes to discovery.
    gates:
      resume_hop_set:
        type: context-matches
        key: resume_hop
        pattern: '^(brief|prd|design|plan)$'
        overridable: false
    accepts:
      setup_result:
        type: enum
        values: [ready, blocked]
        required: true
      detail:
        type: string
        description: What blocked setup, when blocked.
    transitions:
      - target: hop_select
        when:
          setup_result: ready
          gates.resume_hop_set.matches: true
      - target: discovery
        when:
          setup_result: ready
          gates.resume_hop_set.matches: false
      - target: bail
        when:
          setup_result: blocked

  hop_select:
    # phase: 2
    # Where a resumed chain re-enters. A named hop (resume_hop) wins;
    # otherwise the first hop whose artifact the shared predicate does not
    # find, or finalize when every hop has one. A hop the predicate cannot
    # decide counts as not found, the fold's rule: the run goes to the hop
    # rather than past it.
    gates:
      sel_brief:
        type: context-matches
        key: resume_hop
        pattern: '^brief$'
        overridable: false
      sel_prd:
        type: context-matches
        key: resume_hop
        pattern: '^prd$'
        overridable: false
      sel_design:
        type: context-matches
        key: resume_hop
        pattern: '^design$'
        overridable: false
      sel_plan:
        type: context-matches
        key: resume_hop
        pattern: '^plan$'
        overridable: false
      first_open:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop brief --topic "{{TOPIC}}" >/dev/null 2>&1 || exit 11; "{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop prd --topic "{{TOPIC}}" >/dev/null 2>&1 || exit 12; "{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop design --topic "{{TOPIC}}" >/dev/null 2>&1 || exit 13; "{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop plan --topic "{{TOPIC}}" >/dev/null 2>&1 || exit 14; exit 0'
        overridable: false
    transitions:
      - target: hop_brief
        when:
          gates.sel_brief.matches: true
      - target: hop_prd
        when:
          gates.sel_brief.matches: false
          gates.sel_prd.matches: true
      - target: hop_design
        when:
          gates.sel_brief.matches: false
          gates.sel_prd.matches: false
          gates.sel_design.matches: true
      - target: hop_plan
        when:
          gates.sel_brief.matches: false
          gates.sel_prd.matches: false
          gates.sel_design.matches: false
          gates.sel_plan.matches: true
      - target: hop_brief
        when:
          gates.sel_brief.matches: false
          gates.sel_prd.matches: false
          gates.sel_design.matches: false
          gates.sel_plan.matches: false
          gates.first_open.exit_code: 11
      - target: hop_prd
        when:
          gates.sel_brief.matches: false
          gates.sel_prd.matches: false
          gates.sel_design.matches: false
          gates.sel_plan.matches: false
          gates.first_open.exit_code: 12
      - target: hop_design
        when:
          gates.sel_brief.matches: false
          gates.sel_prd.matches: false
          gates.sel_design.matches: false
          gates.sel_plan.matches: false
          gates.first_open.exit_code: 13
      - target: hop_plan
        when:
          gates.sel_brief.matches: false
          gates.sel_prd.matches: false
          gates.sel_design.matches: false
          gates.sel_plan.matches: false
          gates.first_open.exit_code: 14
      - target: finalize
        when:
          gates.sel_brief.matches: false
          gates.sel_prd.matches: false
          gates.sel_design.matches: false
          gates.sel_plan.matches: false
          gates.first_open.exit_code: 0

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
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop brief --topic "{{TOPIC}}"'
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
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop prd --topic "{{TOPIC}}"'
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
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop design --topic "{{TOPIC}}"'
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
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop plan --topic "{{TOPIC}}"'
      # koto cannot see the Skill call, only what it produced. This re-runs
      # /plan's own resolve-split-mode.sh over the PLAN's split verdict, the
      # forwarded intent and coordination flag, and the CLAUDE.md headers, and
      # compares the answer with the PLAN's execution_mode and
      # split_mode_source. A hop that dropped or invented a flag resolves
      # differently and routes to bail. It exits 0 at once when RUN_INTENT is
      # none: a no-intent hop sends today's argument string. Exit 2 is
      # cannot-tell (an unreadable PLAN, a missing resolver) and no arm names
      # it, so the run holds with the gate reported. Not overridable: nothing
      # after this hop re-checks the mode against what the caller asked for.
      plan_mode_consistent:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/check-plan-mode.sh" --plan "docs/plans/PLAN-{{TOPIC}}.md" --intent "{{RUN_INTENT}}" --coordination "{{COORDINATION}}"'
        overridable: false
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
          gates.plan_mode_consistent.exit_code: 0
      - target: bail
        when:
          outcome: landed
          gates.plan_complete.exit_code: 0
          gates.plan_mode_consistent.exit_code: 1
        context_assignments:
          failure_reason: "hop_plan: the PLAN's execution_mode or split_mode_source differs from what the forwarded intent and coordination flag resolve to (plan_mode_consistent exit 1)"
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
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop plan --topic "{{TOPIC}}"'
      design_present:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop design --topic "{{TOPIC}}"'
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
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop brief --topic "{{TOPIC}}" && "{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop prd --topic "{{TOPIC}}" && "{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop design --topic "{{TOPIC}}" && "{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop plan --topic "{{TOPIC}}"'
      # Whether this run publishes. RUN_INTENT is intake's resolution of the
      # flag and the recorded intent; none is a run with no intent (D2).
      intent_declared:
        type: command
        command: 'test "{{RUN_INTENT}}" != none'
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
      # An intent run publishes before cleanup; a no-intent run goes straight
      # to cleanup and makes no gh call. The pair splits on intent_declared,
      # and the cleanup arm requires it to fail.
      - target: publish_full_run
        when:
          evidence.exit_artifacts: present
          gates.chain_complete.exit_code: 0
          gates.intent_declared.exit_code: 0
        context_assignments:
          exit: full-run
      - target: cleanup_full_run
        when:
          evidence.exit_artifacts: present
          gates.chain_complete.exit_code: 0
          gates.intent_declared.exit_code: 1
        context_assignments:
          exit: full-run
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
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop brief --topic "{{TOPIC}}" && "{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop prd --topic "{{TOPIC}}" && "{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop design --topic "{{TOPIC}}" && "{{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh" --hop plan --topic "{{TOPIC}}"'
      intent_declared:
        type: command
        command: 'test "{{RUN_INTENT}}" != none'
    accepts:
      next_move:
        type: enum
        values: [recheck, abandon]
        required: true
      detail:
        type: string
        description: What was produced or declared since the last check.
    transitions:
      - target: publish_full_run
        when:
          next_move: recheck
          gates.chain_complete.exit_code: 0
          gates.intent_declared.exit_code: 0
        context_assignments:
          exit: full-run
      - target: cleanup_full_run
        when:
          next_move: recheck
          gates.chain_complete.exit_code: 0
          gates.intent_declared.exit_code: 1
        context_assignments:
          exit: full-run
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
      intent_declared:
        type: command
        command: 'test "{{RUN_INTENT}}" != none'
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
      - target: publish_re_evaluation
        when:
          retry_or_abandon: retry
          gates.decision_record_present.exit_code: 0
          gates.intent_declared.exit_code: 0
        context_assignments:
          exit: re-evaluation
          boundary: "${evidence.boundary}"
      - target: cleanup_re_evaluation
        when:
          retry_or_abandon: retry
          gates.decision_record_present.exit_code: 0
          gates.intent_declared.exit_code: 1
        context_assignments:
          exit: re-evaluation
          boundary: "${evidence.boundary}"
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
        command: 'grep -lF -- "scope-status-block: abandonment-forced" "docs/briefs/BRIEF-{{TOPIC}}.md" "docs/prds/PRD-{{TOPIC}}.md" "docs/designs/DESIGN-{{TOPIC}}.md" "docs/designs/current/DESIGN-{{TOPIC}}.md" "docs/plans/PLAN-{{TOPIC}}.md" 2>/dev/null | grep -q .'
      intent_declared:
        type: command
        command: 'test "{{RUN_INTENT}}" != none'
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
      - target: publish_abandonment
        when:
          retry_or_cancel: retry
          gates.forced_artifact_present.exit_code: 0
          gates.intent_declared.exit_code: 0
        context_assignments:
          exit: abandonment-forced
      - target: cleanup_abandonment
        when:
          retry_or_cancel: retry
          gates.forced_artifact_present.exit_code: 0
          gates.intent_declared.exit_code: 1
        context_assignments:
          exit: abandonment-forced
      - target: exit_abandonment
        when:
          retry_or_cancel: retry
          gates.forced_artifact_present.exit_code: 1
      # The escape, for the same reason exit_re_evaluation has one.
      - target: done_cancelled
        when:
          retry_or_cancel: cancel
        context_assignments:
          outcome: cancelled
          via: exit_abandonment

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
      # `find | grep -q` can exit non-zero for a reason that is neither "found"
      # nor "not found" -- an unreadable directory, say. Without this arm that
      # status matches nothing, and the run stalls in a state whose details are
      # never redelivered. force_materialize routes to abandonment on ANY gate
      # outcome by design: the author already chose it, and the gate only
      # informs how much there is to materialize.
      - target: exit_abandonment
        when:
          bail_ack: force_materialize
          gates.child_intermediate_present.exit_code: 2
      - target: done_cancelled
        when:
          bail_ack: cancel
        context_assignments:
          outcome: cancelled
          via: bail

  publish_full_run:
    # phase: 3
    # The publish step of an intent run, between the recorded exit and its
    # cleanup (Decision 5). Agent-run: a push and `gh pr create` are
    # externally visible, so they are never a default action. The agent runs
    # publish-scoping-pr.sh; the `published` gate re-checks the result with the
    # script's read-only --verify, so a run cannot claim a PR it did not open.
    #
    # A failure ends at done_error, before cleanup, so the state file keeps
    # `exit:` and its fields (R12) and the next invocation's resume_route
    # routes straight back here. Which step failed is read from context key
    # publish_step, which the script clears when it starts and writes when it
    # fails, through a non-overridable context-matches gate: never from a
    # command gate's output, which carries only an exit code. The push arm
    # assigns the literal scope:push; every other failure arm, a missing
    # publish_step included, assigns scope:pr-create.
    gates:
      published:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/publish-scoping-pr.sh" --topic "{{TOPIC}}" --verify --expect-intent "{{RUN_INTENT}}"'
      publish_push:
        type: context-matches
        key: publish_step
        pattern: '^scope:push$'
        overridable: false
    accepts:
      publish_result:
        type: enum
        values: [attempted]
        required: true
      detail:
        type: string
        description: The script's step= line, when it failed.
    transitions:
      - target: cleanup_full_run
        when:
          publish_result: attempted
          gates.published.exit_code: 0
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 1
          gates.publish_push.matches: true
        context_assignments:
          outcome: error
          step: "scope:push"
          failure_reason: "publish_full_run: the publish did not verify (scope:push)"
          exit: full-run
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 1
          gates.publish_push.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "publish_full_run: the publish did not verify (scope:pr-create)"
          exit: full-run
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 2
          gates.publish_push.matches: true
        context_assignments:
          outcome: error
          step: "scope:push"
          failure_reason: "publish_full_run: the publish did not verify (scope:push)"
          exit: full-run
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 2
          gates.publish_push.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "publish_full_run: the publish did not verify (scope:pr-create)"
          exit: full-run

  publish_re_evaluation:
    # phase: 3
    # The same step for a re-evaluation exit: a draft PR with what was
    # committed (R9).
    gates:
      published:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/publish-scoping-pr.sh" --topic "{{TOPIC}}" --verify --expect-intent "{{RUN_INTENT}}"'
      publish_push:
        type: context-matches
        key: publish_step
        pattern: '^scope:push$'
        overridable: false
    accepts:
      publish_result:
        type: enum
        values: [attempted]
        required: true
      detail:
        type: string
        description: The script's step= line, when it failed.
    transitions:
      - target: cleanup_re_evaluation
        when:
          publish_result: attempted
          gates.published.exit_code: 0
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 1
          gates.publish_push.matches: true
        context_assignments:
          outcome: error
          step: "scope:push"
          failure_reason: "publish_re_evaluation: the publish did not verify (scope:push)"
          exit: re-evaluation
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 1
          gates.publish_push.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "publish_re_evaluation: the publish did not verify (scope:pr-create)"
          exit: re-evaluation
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 2
          gates.publish_push.matches: true
        context_assignments:
          outcome: error
          step: "scope:push"
          failure_reason: "publish_re_evaluation: the publish did not verify (scope:push)"
          exit: re-evaluation
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 2
          gates.publish_push.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "publish_re_evaluation: the publish did not verify (scope:pr-create)"
          exit: re-evaluation

  publish_abandonment:
    # phase: 3
    # The same step for an abandonment-forced exit: a draft PR with the
    # force-materialized artifact (R9).
    gates:
      published:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/publish-scoping-pr.sh" --topic "{{TOPIC}}" --verify --expect-intent "{{RUN_INTENT}}"'
      publish_push:
        type: context-matches
        key: publish_step
        pattern: '^scope:push$'
        overridable: false
    accepts:
      publish_result:
        type: enum
        values: [attempted]
        required: true
      detail:
        type: string
        description: The script's step= line, when it failed.
    transitions:
      - target: cleanup_abandonment
        when:
          publish_result: attempted
          gates.published.exit_code: 0
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 1
          gates.publish_push.matches: true
        context_assignments:
          outcome: error
          step: "scope:push"
          failure_reason: "publish_abandonment: the publish did not verify (scope:push)"
          exit: abandonment-forced
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 1
          gates.publish_push.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "publish_abandonment: the publish did not verify (scope:pr-create)"
          exit: abandonment-forced
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 2
          gates.publish_push.matches: true
        context_assignments:
          outcome: error
          step: "scope:push"
          failure_reason: "publish_abandonment: the publish did not verify (scope:push)"
          exit: abandonment-forced
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 2
          gates.publish_push.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "publish_abandonment: the publish did not verify (scope:pr-create)"
          exit: abandonment-forced

  republish:
    # phase: 3
    # The `--intent` shortcut for a topic whose PLAN already exists (ladder
    # row 40). Agent-run, never a default action: it re-runs
    # publish-scoping-pr.sh for the PLAN's mode, which reuses or opens the
    # owned PR and rewrites the body's intent= field to this run's intent. No
    # child runs and no BRIEF, PRD or DESIGN commit is made. A finished run
    # whose PR records intent=stop, re-invoked with --intent=continue, is not a
    # mismatch: the rewrite is what makes the verify below pass.
    gates:
      published:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/publish-scoping-pr.sh" --topic "{{TOPIC}}" --verify --expect-intent "{{RUN_INTENT}}"'
      publish_push:
        type: context-matches
        key: publish_step
        pattern: '^scope:push$'
        overridable: false
    accepts:
      publish_result:
        type: enum
        values: [attempted]
        required: true
      detail:
        type: string
        description: The script's step= line, when it failed.
    transitions:
      - target: republish_record
        when:
          publish_result: attempted
          gates.published.exit_code: 0
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 1
          gates.publish_push.matches: true
        context_assignments:
          outcome: error
          step: "scope:push"
          failure_reason: "republish: the republish did not verify (scope:push)"
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 1
          gates.publish_push.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "republish: the republish did not verify (scope:pr-create)"
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 2
          gates.publish_push.matches: true
        context_assignments:
          outcome: error
          step: "scope:push"
          failure_reason: "republish: the republish did not verify (scope:push)"
      - target: done_error
        when:
          publish_result: attempted
          gates.published.exit_code: 2
          gates.publish_push.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "republish: the republish did not verify (scope:pr-create)"

  republish_record:
    # phase: 4
    # Records what done_republished reports: the PLAN's path and mode, the next
    # command, the startable items, and the owned PR. The outcome follows the
    # PLAN's mode, read from its frontmatter by the script.
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/record-scope-exit.sh" --session "scope-{{TOPIC}}" --topic "{{TOPIC}}" --intent "{{RUN_INTENT}}" --stage exit'
      fallback: >-
        koto could not record the republished result. Read the command's own
        output above: exit 66 means a `koto context` call failed. There is no
        evidence to submit here; fix the cause and tick again.
    gates:
      exit_recorded:
        type: context-matches
        key: exit_record
        pattern: '^ok$'
        overridable: false
      mode_multi:
        type: context-matches
        key: plan_execution_mode
        pattern: '^multi-pr$'
        overridable: false
    transitions:
      - target: done_republished
        when:
          gates.exit_recorded.matches: true
          gates.mode_multi.matches: true
        context_assignments:
          outcome: handed-off-multi-pr
          exit: full-run
      - target: done_republished
        when:
          gates.exit_recorded.matches: true
          gates.mode_multi.matches: false
        context_assignments:
          outcome: scoped
          exit: full-run
      - target: done_error
        when:
          gates.exit_recorded.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "republish_record: the owned PR could not be recorded (scope:pr-create)"
          exit: full-run

  executed_report:
    # phase: 4
    # The `--intent` shortcut for an executed topic (ladder row 44): the
    # cascade deleted the PLAN and moved the DESIGN under current/. The
    # default action finds the branch's owned PR through the shared
    # owned-pr.sh --state all and writes executed_verdict, executed_pr and
    # executed_pr_state; the gates below route on them and refuse overrides.
    # There is nothing to create here, so zero, several, a failed read, a
    # closed PR, or no verdict at all end at done_error with scope:pr-create.
    # No foreign PR's URL can reach the result: the script writes only the
    # one survivor of the ownership filter.
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/record-executed-report.sh" --session "scope-{{TOPIC}}" --topic "{{TOPIC}}"'
      fallback: >-
        koto could not record the executed topic's pull request. Read the
        command's own output above: exit 66 means a `koto context` call
        failed. There is no evidence to submit here -- the gates refuse
        overrides -- so fix the cause and tick again.
    gates:
      executed_one:
        type: context-matches
        key: executed_verdict
        pattern: '^one$'
        overridable: false
      executed_live:
        type: context-matches
        key: executed_pr_state
        pattern: '^(merged|open)$'
        overridable: false
    transitions:
      - target: done_executed
        when:
          gates.executed_one.matches: true
          gates.executed_live.matches: true
        context_assignments:
          outcome: executed
      - target: done_error
        when:
          gates.executed_one.matches: true
          gates.executed_live.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "executed_report: no single owned merged or open PR was found (scope:pr-create)"
      - target: done_error
        when:
          gates.executed_one.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "executed_report: no single owned merged or open PR was found (scope:pr-create)"

  cleanup_full_run:
    # phase: 4
    # Cleanup is a pre-terminal state because a terminal's directive never
    # crosses the wire: the phase has to be instructed somewhere the agent still
    # ticks.
    #
    # The default action records what the terminal reports (the PLAN facts,
    # and on an intent run the owned PR) before the agent cleans up; the
    # outcome follows the PLAN's mode. exit_record is error only when an intent
    # run's PR lookup could not name exactly one owned PR.
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/record-scope-exit.sh" --session "scope-{{TOPIC}}" --topic "{{TOPIC}}" --intent "{{RUN_INTENT}}" --stage exit'
      fallback: >-
        koto could not record the exit's result. Read the command's own output
        above: exit 66 means a `koto context` call failed. Fix the cause, then
        submit the evidence below; the record re-runs on the next entry.
    gates:
      exit_recorded:
        type: context-matches
        key: exit_record
        pattern: '^ok$'
        overridable: false
      mode_multi:
        type: context-matches
        key: plan_execution_mode
        pattern: '^multi-pr$'
        overridable: false
    accepts:
      cleanup_result:
        type: enum
        values: [done]
        required: true
    transitions:
      - target: done_full_run
        when:
          cleanup_result: done
          gates.exit_recorded.matches: true
          gates.mode_multi.matches: true
        context_assignments:
          outcome: handed-off-multi-pr
      - target: done_full_run
        when:
          cleanup_result: done
          gates.exit_recorded.matches: true
          gates.mode_multi.matches: false
        context_assignments:
          outcome: scoped
      - target: done_error
        when:
          cleanup_result: done
          gates.exit_recorded.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "cleanup_full_run: the owned PR could not be recorded (scope:pr-create)"

  cleanup_re_evaluation:
    # phase: 4
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/record-scope-exit.sh" --session "scope-{{TOPIC}}" --topic "{{TOPIC}}" --intent "{{RUN_INTENT}}" --stage exit'
      fallback: >-
        koto could not record the exit's result. Read the command's own output
        above: exit 66 means a `koto context` call failed. Fix the cause, then
        submit the evidence below; the record re-runs on the next entry.
    gates:
      exit_recorded:
        type: context-matches
        key: exit_record
        pattern: '^ok$'
        overridable: false
    accepts:
      cleanup_result:
        type: enum
        values: [done]
        required: true
    transitions:
      - target: done_re_evaluation
        when:
          cleanup_result: done
          gates.exit_recorded.matches: true
        context_assignments:
          outcome: re-evaluation
      - target: done_error
        when:
          cleanup_result: done
          gates.exit_recorded.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "cleanup_re_evaluation: the owned PR could not be recorded (scope:pr-create)"

  cleanup_abandonment:
    # phase: 4
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/scope/scripts/record-scope-exit.sh" --session "scope-{{TOPIC}}" --topic "{{TOPIC}}" --intent "{{RUN_INTENT}}" --stage exit'
      fallback: >-
        koto could not record the exit's result. Read the command's own output
        above: exit 66 means a `koto context` call failed. Fix the cause, then
        submit the evidence below; the record re-runs on the next entry.
    gates:
      exit_recorded:
        type: context-matches
        key: exit_record
        pattern: '^ok$'
        overridable: false
    accepts:
      cleanup_result:
        type: enum
        values: [done]
        required: true
    transitions:
      - target: done_abandonment
        when:
          cleanup_result: done
          gates.exit_recorded.matches: true
        context_assignments:
          outcome: abandonment
      - target: done_error
        when:
          cleanup_result: done
          gates.exit_recorded.matches: false
        context_assignments:
          outcome: error
          step: "scope:pr-create"
          failure_reason: "cleanup_abandonment: the owned PR could not be recorded (scope:pr-create)"

  # The terminals. Every one declares a result map; this is what a coordinator
  # reads on a koto request leg and what print-scope-exit.sh renders. The
  # pattern is the one done_refused and done_error set: `outcome`, `step`,
  # `exit`, `reason`, `boundary` and `via` are written by the edge that lands
  # here, as literals or a variable; the PLAN facts, `pr`, `wip_paths` and the
  # executed PR are written by a script with `koto context add` and read here
  # as ${context.<key>}, because an assignment cannot read context. No agent
  # evidence supplies any of them. `intent` is the effective intent intake
  # resolved.
  done_full_run:
    # phase: 4
    terminal: true
    result:
      outcome: "${context.outcome}"
      exit: "${context.exit}"
      intent: "{{RUN_INTENT}}"
      next: "${context.next}"
      pr: "${context.pr}"
      plan_path: "${context.plan_path}"
      plan_execution_mode: "${context.plan_execution_mode}"
      wip_paths: "${context.wip_paths}"
      startable: "${context.startable}"

  done_republished:
    # phase: 4
    terminal: true
    result:
      outcome: "${context.outcome}"
      exit: "${context.exit}"
      intent: "{{RUN_INTENT}}"
      next: "${context.next}"
      pr: "${context.pr}"
      plan_path: "${context.plan_path}"
      plan_execution_mode: "${context.plan_execution_mode}"
      wip_paths: "${context.wip_paths}"
      startable: "${context.startable}"

  done_executed:
    # phase: 4
    terminal: true
    result:
      outcome: "${context.outcome}"
      intent: "{{RUN_INTENT}}"
      pr: "${context.executed_pr}"
      pr_state: "${context.executed_pr_state}"

  done_re_evaluation:
    # phase: 4
    terminal: true
    result:
      outcome: "${context.outcome}"
      exit: "${context.exit}"
      intent: "{{RUN_INTENT}}"
      boundary: "${context.boundary}"
      pr: "${context.pr}"
      wip_paths: "${context.wip_paths}"

  done_abandonment:
    # phase: 4
    terminal: true
    result:
      outcome: "${context.outcome}"
      exit: "${context.exit}"
      intent: "{{RUN_INTENT}}"
      pr: "${context.pr}"
      wip_paths: "${context.wip_paths}"

  done_cancelled:
    # phase: 4
    terminal: true
    result:
      outcome: "${context.outcome}"
      intent: "{{RUN_INTENT}}"
      via: "${context.via}"

  # The two failure terminals. `outcome: refused` is a result-payload value
  # only: the printed exit line for done_refused is `outcome=error` with
  # `step=scope:refused`. A refusal from resume_route (plan-active,
  # plan-done) also carries `next`, the command the topic belongs to now, and
  # the PLAN's path and mode; an error from a publish carries the `exit` the
  # state file still records.
  done_refused:
    # phase: 4
    terminal: true
    failure: true
    result:
      outcome: "${context.outcome}"
      reason: "${context.reason}"
      step: "${context.step}"
      intent: "{{RUN_INTENT}}"
      recorded: "${context.recorded}"
      requested: "${context.requested}"
      next: "${context.next}"
      plan_path: "${context.plan_path}"
      plan_execution_mode: "${context.plan_execution_mode}"

  done_error:
    # phase: 4
    terminal: true
    failure: true
    result:
      outcome: "${context.outcome}"
      reason: "${context.reason}"
      step: "${context.step}"
      intent: "{{RUN_INTENT}}"
      recorded: "${context.recorded}"
      requested: "${context.requested}"
      exit: "${context.exit}"
      wip_paths: "${context.wip_paths}"
---

## intake

Checking the invocation against the working tree. koto runs the checks itself
on entry and routes on their verdict; you only see this state if the checks
could not record one.

<!-- details -->

koto already refused, at `koto init`, every argument a variable's constraint
can express. What runs here needs the working tree: the `--upstream` battery
(not under `wip/`, tracked by git, confined to `docs/roadmaps/` after symlinks,
a `ROADMAP-` basename), and an explicit `--intent` that differs from the intent
an unfinished run already recorded in its state file. The script also resolves
the run's effective intent, which later states receive.

The verdict routes the run without you: `ok` to the branch check, `refused` to
the refused terminal with the check's reason, anything else to the error
terminal. The gates refuse overrides and this state takes no evidence, so there
is nothing to submit. If the response above shows the action failed, read its
output, fix the cause, and tick again.

## branch_check

Confirming the run is on a branch it can commit hops to. koto reads the branch
name itself on entry; you only see this state if it could not.

<!-- details -->

The command is `git symbolic-ref --quiet --short HEAD`, and the gate beside it
requires a named branch that is neither `main` nor `master`. On the passing
path the run advances to `resume_route` with no evidence and you never read
this.

You are here because one of the two failed. Either HEAD is detached and the
command itself failed -- in which case the response above carries git's own
output -- or HEAD is on the default branch and the gate did. Check out a named
non-default branch and tick again; the check re-runs on entry, so nothing needs
submitting.

Two escapes exist and neither is the normal path. `branch_status: override`
proceeds anyway, for the author who knows the branch is right and the gate is
wrong about this repository. `branch_status: blocked` with `detail` stops the
run. Do not create a branch on the author's behalf: choosing one mid-chain is a
bigger surprise than refusing, which is the same reason the per-hop commit
refuses rather than repairs.

The branch name this state reads is delivered to every later state as
`{{BRANCH}}`, so nothing downstream recovers it again.

Evidence schema (both optional; the passing path submits neither):
- `branch_status`: `override` or `blocked`
- `detail`: why the branch could not be settled

## resume_route

Deciding where this topic stopped. koto runs the resume probe itself on entry
and routes on its answer; you only see this state if it could not.

<!-- details -->

`resume-probe.sh` is the resume ladder in
`skills/scope/references/phases/phase-resume.md`, as one read-only probe over
the artifact tree, the state file, the child partials and the `/explore`
handoff. Each row's exit code routes to a state: a fresh start to `setup`, a
fresh state file to its phase, a stale, malformed or finished state file to
the prompt for that row, a failed publish back to its publish state, a PLAN
under way to a refusal or, on an intent run, to `republish`, an executed topic
on an intent run to `executed_report`, a draft or a settled boundary to its
prompt, and a child partial to `setup` and then that hop.

The gate refuses overrides, and this state takes no evidence. If the response
shows the probe's exit code with no route, the probe itself could not run: read
the blocking condition, fix the environment, and tick again. Exit 2 is the
probe's own "cannot tell", which ends the run with `step=scope:resume-probe`.

## resume_stale

The state file for this topic was last updated 7 days ago or more. Offer the
author **Resume / Force-materialize / Discard**. Under `--auto` (this run's
mode is `{{EXEC_MODE}}`), take Resume and announce that you did.

<!-- details -->

- **Resume** (`stale_choice: resume`) continues at the recorded
  `phase_pointer`: the gate re-reads it and routes to discovery, into the
  chain, or to finalization.
- **Force-materialize** (`stale_choice: force_materialize`) routes to the
  `abandonment-forced` exit.
- **Discard** (`stale_choice: discard`) removes the state file
  `wip/scope_{{TOPIC}}_state.md` -- that one path -- and restarts at Phase 0.
  Remove it before submitting.

Announcing the auto default is the load-bearing half under `--auto`: the run
output says Resume was taken whether or not anyone is watching.

Evidence schema:
- `stale_choice`: `resume`, `force_materialize`, or `discard`
- `detail`: what the author chose, or the announcement under `--auto`

## resume_malformed

The state file for this topic is malformed. Name the specific malformation
and offer **Discard** as the recovery. There is no silent fall-through: either
the author discards, or the run stops.

<!-- details -->

The probe's reason is in the response above (its stderr names the field). Say
exactly what is wrong -- a missing field, a value outside its enum, a duplicate
line -- and offer Discard. **Discard** (`malformed_choice: discard`) removes
`wip/scope_{{TOPIC}}_state.md` and restarts the chain at Phase 0; remove the
file before submitting. `malformed_choice: stop` ends the run at the cancelled
terminal with nothing changed. The author confirms Discard; it is never
automatic, under `--auto` included.

Evidence schema:
- `malformed_choice`: `discard` or `stop`
- `detail`: the malformation, named

## resume_exit_set

This topic's state file already records an exit, and nothing is left to
publish. Offer the revise-equivalent flow for that exit, or a fresh chain.

<!-- details -->

- `exit_set_choice: revise` re-opens finalization, so the exit is recorded
  again from the artifacts as they stand -- the revise-equivalent of a
  recorded exit.
- `exit_set_choice: start_fresh` is Discard + restart: remove
  `wip/scope_{{TOPIC}}_state.md` before submitting, and the chain starts at
  Phase 0.
- `exit_set_choice: bail` stops with nothing changed.

Evidence schema:
- `exit_set_choice`: `revise`, `start_fresh`, or `bail`
- `detail`: what the author chose

## resume_draft

A Draft artifact this chain owns exists for the topic. Offer the
**Continue / Discard / Bail** prompt against the draft.

<!-- details -->

The probe's row names the draft (a Draft PLAN, a Proposed DESIGN, a Draft PRD,
or a Draft BRIEF). If a router handoff exists at
`wip/scope_{{TOPIC}}_handoff.md`, say that it exists and was not consumed, and
offer its problem statement as context for the choice.

- `draft_choice: continue` runs setup and re-enters the chain at the draft's
  own hop, where the child resumes against its own draft.
- `draft_choice: discard` starts the chain fresh from discovery. The draft is
  not deleted here: the child at its hop replaces it, through that child's own
  re-entry handling.
- `draft_choice: bail` stops with nothing changed.

Evidence schema:
- `draft_choice`: `continue`, `discard`, or `bail`
- `detail`: what the author chose

## resume_boundary

A settled upstream artifact exists for the topic -- the DESIGN-boundary or the
PRD-boundary. Offer the **Re-evaluate / Revise / Bail** triad and name the
boundary.

<!-- details -->

The boundary is the DESIGN-boundary when an Accepted DESIGN exists, and the
PRD-boundary when only an Accepted PRD does; the most-downstream boundary wins.
A topic whose PLAN was executed and removed also lands here when no intent was
given. This prompt never offers "Continue / Start fresh": that vocabulary
belongs to a child's own resume ladder.

- `boundary_choice: re_evaluate` goes to the re-evaluation exit, where the
  Decision Record attaches at the boundary named above.
- `boundary_choice: revise` runs setup and re-enters the chain at the
  boundary's own hop.
- `boundary_choice: bail` stops with nothing changed.

Evidence schema:
- `boundary_choice`: `re_evaluate`, `revise`, or `bail`
- `detail`: what the author chose

## setup

Establish the run: write the state file, recording `intent: {{RUN_INTENT}}`,
and confirm the worktree is the one this run owns. The arguments were checked
at `koto init` and in `intake`; the branch is settled as `{{BRANCH}}`. Submit
`setup_result: ready`, or `blocked` with `detail`.

<!-- details -->

A run resumed at a child partial, a draft's Continue or a boundary's Revise
goes on from here to that hop rather than to discovery; koto decides that from
what `resume_route` recorded, so submit `ready` either way.

Procedure: `skills/scope/references/phases/phase-0-setup.md`. The fields the
state file carries: `skills/scope/references/state-schema.md`. Read them now;
the rest of this run assumes setup happened as they describe.

**The argument checks ran before this state.** koto refused, at `koto init`,
every value its variables do not admit -- the topic slug, `--intent`,
`--max-rounds`, the `--upstream` shape, and any repeated or conflicting flag --
and `intake` ran the `--upstream` checks that need the working tree and the
recorded-intent check. Do not re-validate them here. This run's settings are
the session's variables: execution mode `{{EXEC_MODE}}`, coordination flag
`{{COORDINATION}}`, re-evaluation cap `{{MAX_ROUNDS}}` (empty means the
default of 5), and upstream `{{UPSTREAM}}` (empty means none was given; the
visibility check in the Phase 0 reference still decides whether it is
recorded).

**Record the effective intent.** Write `intent: {{RUN_INTENT}}` into the state
file, on the initial write and on every later write that rewrites the file.
The value is `continue`, `stop`, or `none`, always present, never empty:
`intake` resolved it from the invocation's `--intent`, else the intent the
state file already recorded, else `none`.

**The branch check ran before this state.** `branch_check` reads HEAD and gates
on a named non-default branch, so a run that reaches `setup` is already on a
branch it can commit to, and the name is available as `{{BRANCH}}`. The check
used to live here as an instruction with nothing enforcing it, which meant a
run that started on the default branch did `/brief`'s whole hop and then could
not keep it -- the first commit happens after a document exists.

`blocked` here covers neither the branch nor the arguments. It covers a state
file that cannot be written. Anything else, fix and submit `ready`.

Ignore koto's discovery warnings about sessions other than this run's —
`migration skipped`, and `state file corrupted`, which reads as an invitation
to tidy up. Never run a cleanup or cancel verb against a session this run did
not open. The rule and its reasoning are in `skills/scope/SKILL.md` under
Running the Workflow, and in `phase-0-setup.md`; both are durable, which this
block is not.

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

Put the proposed chain to the author and record their answer: `proceed` starts
the chain at `/brief`, `adjust` returns to discovery to re-propose, `bail`
stops.

<!-- details -->

The format the proposal takes is in the Chain-Proposal Output section of
`skills/scope/references/phases/phase-1-discovery.md`, including the worked
skeleton and the three literal choices the output must offer.

This is the one state where the author is thinking rather than you. Ticking
back here while they deliberate is normal and is not an arrival, so this block
comes once — read it before you put the proposal.

`adjust` refines the topic and the framing. It does not shorten the chain: the
proposal never offers a shorter one, because Phase 1 has no artifact to decide
against.

Evidence schema:
- `author_decision`: `proceed`, `adjust`, or `bail`
- `detail`: what the author asked to adjust, or why they bailed

## hop_brief

Run the BRIEF hop: put the feature's problem and intended outcome on disk, so
everything downstream answers a stated problem rather than an assumed one.

**Order at every hop: child returns, then gate, then commit.** The gate reads
the artifact tree and never git state, so a failed gate never produces a commit
claiming the hop landed. Commit only after it passes, staging the one canonical
path with `git add --` and naming the hop.

<!-- details -->

The ordering above is in the directive, and repeated at every hop, because you
need it when the child returns — a whole inline child invocation after you
arrived here, far enough that this block is no longer in easy reach. Its
preconditions and branch checks are in the Per-Hop Commit section of
`skills/scope/references/phases/phase-2-chain-orchestration.md`; that section
is deliberately not one of the eight steps below.

Run the eight-step per-child loop from
`skills/scope/references/phases/phase-2-chain-orchestration.md` in order:
the worktree-staleness check, the `parent_orchestration:` sentinel write, the
child invocation, the R20 structural file-existence check, the sentinel
cleanup, the child-snapshot capture, and the validator pass-through. The eighth
step, the consolidation judgment, does not run at this hop: it compares two
documents and only one exists.

Invoke `/brief` inline via the Skill tool with the topic slug — and, when the
state file carries `consumed_upstream:`, with `--upstream <that path>` as well.
Phase 0 validated that value and recorded it precisely so this invocation can
pass it; dropping it here discards the roadmap the chain was told to consume.
Quote it and pass it after `--`: validation is not the guarantee, the argument
boundary is.

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

Run the PRD hop: state the requirements the feature must meet and the criteria
that decide it is done, in terms an implementer can be held to.

**Child returns, then gate, then commit.** A failed gate never produces a
commit claiming the hop landed. Stage the one canonical path with `git add --`
and name the hop.

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

Run the DESIGN hop: settle how the feature is built — the approach taken, the
alternatives weighed against it, and the reason this one won.

**Child returns, then gate, then commit.** A failed gate never produces a
commit claiming the hop landed. Stage the one canonical path with `git add --`
and name the hop.

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

Run the PLAN hop: decompose the settled approach into implementable units, in
the order the work happens and with each unit's dependencies stated.

**Child returns, then gate, then commit.** A failed gate never produces a
commit claiming the hop landed. Stage the one canonical path with `git add --`
and name the hop.

<!-- details -->

Run the eight-step per-child loop from
`skills/scope/references/phases/phase-2-chain-orchestration.md` in order.
Invoke `/plan` inline via the Skill tool, passing the nearest produced upstream
artifact's path — and, when the state file carries `consumed_upstream:`, also
`--upstream <that path>`. `/plan` is the child that records the roadmap itself,
because a ROADMAP is deleted when its features land and the PLAN the cascade
deletes first is the only document whose link cannot outlive its target. Quote
it and pass it after `--`. Keep the artifact path for the fold state.

**Forward the run's intent and the caller's coordination flag.** This run's
effective intent is `{{RUN_INTENT}}` and the caller's coordination flag is
`{{COORDINATION}}`. When the intent is `continue` or `stop`, the `/plan`
arguments carry, all before the `--` that precedes the artifact path:

- `--intent={{RUN_INTENT}}`;
- `--coordinated` when the coordination flag is `coordinated`, or
  `--no-coordinated` when it is `no-coordinated`, and neither when it is
  `none`. Never forward a `--coordinated` derived from a CLAUDE.md header:
  `/plan` reads the headers itself, and a header-derived flag would outrank the
  intent;
- this run's own mode flag: `--auto` when the execution mode is `auto`,
  `--interactive` otherwise.

When the intent is `none`, send exactly today's argument string: no `--intent`,
no coordination flag, no mode flag.

The `plan_mode_consistent` gate re-runs `/plan`'s split-mode resolver over the
PLAN it produced and the flags above. A PLAN whose `execution_mode` or
`split_mode_source` does not match what the forwarded flags resolve to routes
the run to `bail` rather than on: the hop dropped or invented a flag. Exit 2
means the check could not read the PLAN or run the resolver; the run holds with
the gate reported.

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

## hop_select

Choosing the hop a resumed chain re-enters at. koto decides it on entry; you
only see this state if its gates could not.

<!-- details -->

A resume that named a hop -- a child partial, a draft's Continue, a boundary's
Revise -- enters that hop. Otherwise the run enters the first hop whose
artifact the shared completion predicate does not find, or finalization when
every hop has one. A hop the predicate cannot decide counts as not found, so
the run goes to the hop rather than past it. There is no evidence to submit
here; if the response shows a gate that could not run, fix the environment and
tick again.

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

The full-run exit did not go through. Read
`blocking_conditions[].output.exit_code` first: the gate is three-valued and
each value asks for something different.

- **1 — refused.** Some hop has neither its artifact nor a declared fold. Fix
  the chain.
- **2 — undecided.** The predicate reached no verdict. Fix the environment;
  the artifacts are not the problem.

Record which of the two happened in the state file — that is this state's
durable output, and a `recheck` that changes nothing returns you here.

<!-- details -->

The distinction above is the whole job of this state, which is why it is in the
directive rather than here: you will pass through this state more than once,
and a self-loop is not an arrival, so this block is delivered on the first lap
only. The code can also change between laps — a validator breaking mid-run
turns a 1 into a 2 — and the required action changes with it.

Why the state file and not just the session: the engine records the exit code
in the session, but the session does not travel with the branch. A reader
holding only the state file cannot otherwise tell a chain that was refused from
one that was never decided — and "undecided" recorded as "refused" sends the
next person to the artifacts when the problem is the environment.

The gate's output is an exit code and nothing else -- koto does not surface a
command gate's stdout or stderr -- so it cannot say *which* hop failed. Run the
predicate once per hop yourself to get that:

```bash
for HOP in brief prd design plan; do
  {{PLUGIN_ROOT}}/skills/scope/scripts/hop-complete.sh --hop "$HOP" --topic "<topic>"
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
force-materialized from its intermediate. Advance with `--no-cleanup` on the
tick that reaches the terminal.

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

**On a coordinated run, close the coordination PR without merging** — `gh pr
close`, the same `gh` surface that authored and posted its body. Abandonment
never merges that PR and never leaves it open: an open coordination PR is
merge-eligible, and merging it would land a plan the run just abandoned. The
closed PR's durable body and the force-materialized Draft together record the
partial state for a reviewer to audit. Skip this on a single-repo run, where
there is no coordination PR to close. Skip it too on an intent run -- this run's
intent is `{{RUN_INTENT}}`, and anything but `none` is one: an intent run never
creates a coordination PR up front, so none exists before exit, and there is
nothing to close.

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
and a force-materialization. On the cancel route, advance with `--no-cleanup`
on the tick that reaches the terminal.

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

## publish_full_run

Publish this intent run's full-run exit: push the branch and open (or reuse)
its one pull request. Run the publish script, then submit
`publish_result: attempted`.

```bash
"{{PLUGIN_ROOT}}/skills/scope/scripts/publish-scoping-pr.sh" --topic "{{TOPIC}}" --exit full-run --intent "{{RUN_INTENT}}" --session "scope-{{TOPIC}}"
```

<!-- details -->

The script reads the PLAN's mode from its frontmatter and opens a draft for a
`single-pr` or `coordinated` PLAN and a ready PR for a `multi-pr` one. It
untracks this topic's own `wip/` (the files stay on disk for cleanup), reports
any `wip/` in unpushed history as `wip_paths=`, runs the public-content check
over those files, pushes with a plain `HEAD:refs/heads/<branch>` refspec, and
finds the PR through the shared ownership filter: it reuses the one owned PR,
opens one when there is none, and stops on several. Do not push, create, or
edit a PR any other way.

**When it fails** it prints `step=scope:push` or `step=scope:pr-create`.
Write that value into the state file as `publish_error: <step>` before you
submit; the run then ends at the error terminal without cleanup, the state
file keeps `exit:` and its fields, and the next `/scope {{TOPIC}}` routes
straight back here to retry. **When it succeeds**, remove any `publish_error:`
line from the state file.

Submit `publish_result: attempted` either way. The `published` gate re-checks
with the script's read-only `--verify` -- origin's branch equals `HEAD`, exactly
one owned open PR exists, and its body records `intent={{RUN_INTENT}}` -- and
that decides whether the run goes to cleanup or to the error terminal.

Evidence schema:
- `publish_result`: `attempted`
- `detail`: the script's `step=` line, when it failed

## publish_re_evaluation

Publish this intent run's re-evaluation exit: push the branch and open a draft
pull request with the Decision Record. Run the publish script, then submit
`publish_result: attempted`.

```bash
"{{PLUGIN_ROOT}}/skills/scope/scripts/publish-scoping-pr.sh" --topic "{{TOPIC}}" --exit re-evaluation --intent "{{RUN_INTENT}}" --session "scope-{{TOPIC}}"
```

<!-- details -->

Everything in `publish_full_run` applies: on a `step=` failure write
`publish_error: <step>` to the state file before submitting, and on success
remove it. The PR is always a draft on this exit.

Evidence schema:
- `publish_result`: `attempted`
- `detail`: the script's `step=` line, when it failed

## publish_abandonment

Publish this intent run's abandonment-forced exit: push the branch and open a
draft pull request with the force-materialized artifact. Run the publish
script, then submit `publish_result: attempted`.

```bash
"{{PLUGIN_ROOT}}/skills/scope/scripts/publish-scoping-pr.sh" --topic "{{TOPIC}}" --exit abandonment-forced --intent "{{RUN_INTENT}}" --session "scope-{{TOPIC}}"
```

<!-- details -->

Everything in `publish_full_run` applies: on a `step=` failure write
`publish_error: <step>` to the state file before submitting, and on success
remove it. The PR is always a draft on this exit.

Evidence schema:
- `publish_result`: `attempted`
- `detail`: the script's `step=` line, when it failed

## republish

This topic's PLAN already exists and the run has an intent. Re-publish it --
no child runs, and no BRIEF, PRD or DESIGN is committed. Run the publish
script for the PLAN's mode, then submit `publish_result: attempted`.

```bash
"{{PLUGIN_ROOT}}/skills/scope/scripts/publish-scoping-pr.sh" --topic "{{TOPIC}}" --exit full-run --intent "{{RUN_INTENT}}" --session "scope-{{TOPIC}}"
```

<!-- details -->

The script reuses the owned PR on this branch, or opens it when there is none,
and rewrites the PR body's `intent=` field to `{{RUN_INTENT}}` when it records
something else. A finished run whose PR says `intent=stop`, re-invoked with
`--intent=continue`, is not a mismatch: the rewrite is the point. The
`published` gate verifies the push, the one owned PR, and the `intent=` field.
There is no state file to update on this path.

Evidence schema:
- `publish_result`: `attempted`
- `detail`: the script's `step=` line, when it failed

## republish_record

Recording what the republished run reports. koto runs the record itself and
routes on it; you only see this state if the record could not be written.

<!-- details -->

`record-scope-exit.sh` writes the PLAN's path and mode, the next command, the
startable items, and the owned PR to the session's context, where the
terminal's result reads them. If the response shows the action failed, read
its output, fix the cause, and tick again.

## executed_report

Reporting the executed topic's pull request. koto reads it itself on entry and
routes on what it found; you only see this state if the read could not be
recorded.

<!-- details -->

The PLAN was executed and removed, so the result names the pull request that
carried the work: `record-executed-report.sh` finds the one PR this user owns
on the branch through the shared ownership filter (`--state all`), reads its
state, and writes both to context. A merged or open PR ends the run at
`done_executed`; no owned PR, several, a closed one, or a failed read ends it
at the error terminal with `step=scope:pr-create`. The gates refuse overrides
and this state takes no evidence.

## cleanup_full_run

Run Phase 4 cleanup for a full-run exit, then submit `cleanup_result: done`.
Advance with `--no-cleanup`, and print the exit block from the terminal result
(below).

<!-- details -->

Procedure: `skills/scope/references/phases/phase-4-cleanup.md`. Remove the run's
`wip/` intermediates, including the state file, and confirm no committed
artifact references a `wip/` path.

`--no-cleanup` on the `koto next` that reaches the terminal is not optional
here. Without it the per-hop record is destroyed with the session at the exact
moment the run finishes and an author would go looking for it. The record is
read where it lives; it is never copied into a committed artifact or a
pull-request body.

koto already recorded, on entry here, what the terminal reports: the PLAN's
path and mode, the next command, the startable items, and on an intent run the
owned PR. Compose no exit line yourself. Once the tick has reached the
terminal, print what this prints, verbatim:

```bash
"{{PLUGIN_ROOT}}/skills/scope/scripts/print-scope-exit.sh" --topic "{{TOPIC}}" --session "scope-{{TOPIC}}"
```

Evidence schema:
- `cleanup_result`: `done`

## cleanup_re_evaluation

Run Phase 4 cleanup for a re-evaluation exit, then submit `cleanup_result:
done`. Advance with `--no-cleanup`, and print the exit block from the terminal
result.

<!-- details -->

Procedure: `skills/scope/references/phases/phase-4-cleanup.md`. Remove the run's
`wip/` intermediates, including the state file, and confirm no committed
artifact -- the Decision Record in particular -- references a `wip/` path.

`--no-cleanup` for the reason it carries at every cleanup state: the per-hop
record does not survive the session otherwise. Once the tick has reached the
terminal, print the output of `print-scope-exit.sh --topic "{{TOPIC}}"
--session "scope-{{TOPIC}}"` verbatim.

Evidence schema:
- `cleanup_result`: `done`

## cleanup_abandonment

Run Phase 4 cleanup for an abandonment-forced exit, then submit
`cleanup_result: done`. Advance with `--no-cleanup`, and print the exit block
from the terminal result.

<!-- details -->

Procedure: `skills/scope/references/phases/phase-4-cleanup.md`. Remove the run's
`wip/` intermediates, including the state file, and confirm no committed
artifact references a `wip/` path.

The force-materialized artifact keeps its marker; cleanup does not touch it.
`--no-cleanup` for the reason it carries at every cleanup state. Once the tick
has reached the terminal, print the output of `print-scope-exit.sh --topic
"{{TOPIC}}" --session "scope-{{TOPIC}}"` verbatim.

Evidence schema:
- `cleanup_result`: `done`

## done_full_run

The chain completed through `/plan` and the chain-wide gate credited every hop
with either its artifact or a declared fold. The result carries the outcome by
the PLAN's mode, the next command, and on an intent run the scoping PR.

## done_republished

An existing PLAN was re-published on an intent run: the owned PR exists and
records this run's intent. No child ran.

## done_executed

The topic's PLAN was executed and removed. The result names the owned pull
request that carried the work and whether it is merged or open.

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

## done_refused

The invocation was refused before any work. The result names the check in
`reason`, and for an intent mismatch the recorded and requested intents; a PLAN
under way names the command it belongs to now in `next`. The state file, if
one exists, is unchanged. The printed exit line is `outcome=error` with
`step=scope:refused`; `refused` is only a result value.

## done_error

The run stopped on an error it could not resolve. The result's `step` names
where. After a failed publish the state file still records the exit and
`publish_error:`, and the next invocation retries the publish.
