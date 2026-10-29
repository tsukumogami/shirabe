---
# Terminal-tick retention (#360). Every `koto next` a /work-on run makes
# carries --no-cleanup, whether the run is a root or a child that /execute
# materialized from this template: on a child the flag only keeps the session,
# and its result still reaches the parent. The rule lives in ../SKILL.md's
# Execution Loop, and the command lines in the phase files carry the flag.
# Why every tick: ../../../references/koto-session-retention.md
#
# A YAML comment, so it reaches a template editor without koto rendering it into
# any state's directive.
name: work-on
version: "1.0"
description: >
  Implementation workflow for issue-backed, free-form, and plan-backed tasks. Split topology:
  issue-backed mode routes through context_injection, setup, and staleness_check;
  free-form mode routes through task_validation, research, and post_research_validation;
  plan-backed mode routes through plan_context_injection, optional plan_validation, and
  setup_plan_backed, skipping staleness. All paths converge at analysis and share all
  subsequent states. Requires two variables: ISSUE_NUMBER (issue-backed only) and
  ARTIFACT_PREFIX (always). Self-loops use conditional when blocks (scope_changed_retry,
  partial_tests_failing_retry, creation_failed_retry) to avoid triggering cycle detection.
initial_state: entry

variables:
  ISSUE_NUMBER:
    description: GitHub issue number for issue-backed workflows
    required: false
  ISSUE_REPO:
    description: >-
      The repository an issue-backed run's issue lives in, as owner/repo, set
      at init only when the issue reference (a URL or owner/repo#N) names a
      repository other than the one being worked in. Empty is a
      same-repository run, and every reader keeps its old behaviour on empty.
      The directives hand it to extract-context.sh and review-packet.sh as
      `--issue-repo`, which pass it to `gh issue view --repo`; neither reads
      it back from the session. pr_creation's closing_keyword gate then asks
      for `Fixes owner/repo#N` and refuses any closing reference to issue N
      of this repository, which merging would close. The pattern is GitHub's owner/repo
      character set, so only a plain name reaches a gate command. Not
      rebindable: the issue doesn't move partway through a run.
    required: false
    pattern: ^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?$
  ISSUE_TYPE:
    description: >
      Issue type hint supplied by the plan orchestrator (code, docs, or task).
      A starting point only. The type is asked once, at issue_type_routing,
      after implementation, where the agent confirms or overrides this hint
      with changed_paths.txt in context. It is not submitted at analysis or
      implementation.
    required: false
    default: code
  ARTIFACT_PREFIX:
    description: >
      Prefix for context keys and branch names. Set at koto init time:
      issue_<N> for issue-backed, task_<slug> for free-form.
    required: true
  ISSUE_SOURCE:
    description: Source of issue data for plan-backed mode (github or plan_outline)
    required: false
  PLAN_DOC:
    description: Path to the PLAN document for plan-backed mode
    required: false
  PLAN_DOC_MOVED:
    description: >-
      Where a plan-backed child's PLAN is now, set only when the checkout that
      held PLAN_DOC moved after the child was opened. PLAN_DOC isn't
      rebindable, so a child opened before the move keeps the old path; the
      coordinated step agent (../../execute/references/step-agent-handoff.md)
      attaches such a child with every recorded variable unchanged and this
      one set to the run's current PLAN, before the child has passed
      plan_validation. plan_context_injection's directive and plan_validation's
      step_detail gate read this path when it is set and PLAN_DOC otherwise.
      Rebindable, so an attach that leaves it out blanks it; that is harmless,
      since no state after plan_validation reads it, and a later attach
      (review-level.sh set, fix-kind.sh) comes only after the child has
      passed. Empty on every root run and on a child that never moved.
    required: false
    rebind: true
  SHARED_BRANCH:
    description: >
      Shared branch name provided by the plan orchestrator. When set, skip branch
      creation in setup states and commit directly to this branch.
    required: false
  PLUGIN_ROOT:
    description: >-
      Absolute path to the shirabe plugin root, passed at koto init as
      --var PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT} where the agent's own shell
      expands it once. cascade_entry's gate invokes find-anchor-plan.sh, which
      ships in the plugin, and koto runs a gate command with the working
      directory of the `koto next` process -- here the repository being worked,
      not this checkout. A repo-relative path therefore resolves only when
      /work-on runs against shirabe itself. Declared as a template variable
      rather than written as a shell-style ${CLAUDE_PLUGIN_ROOT} because koto
      resolves only {{KEY}} references: the shell form reaches sh -c untouched
      and expands to nothing, and scripts/check-template-interpolation.sh
      rejects it for that reason.

      Required, but required is not the guarantee. koto accepts an empty value
      for a required variable (VALUE_PATTERN ends in `*`), so an init run in a
      shell where CLAUDE_PLUGIN_ROOT is unset passes --var PLUGIN_ROOT= and
      sails through. cascade_entry's gate therefore tests that the finder is
      executable at the resolved path and exits 2 if it is not, which routes to
      done_blocked. Without that test the failure is exit 127, whose output koto
      discards, and the run holds with no diagnostic.

      staleness_check's gate reaches check-staleness.sh the same way and guards
      it the same way, except that it exits 3: an absent check is the
      "unavailable" outcome that state routes to analysis, not a blocked run.

      Unlike /scope and /execute, this template is both initialized directly and
      materialized as a child, so it has more than one kind of init site. Every
      one of them passes this variable; check-init-site-vars.sh is what keeps
      that true.

      Rebindable, as in execute.md: a plugin update moves the path, and a
      resume under --koto-leg attaches through `koto init --attach-live`, which
      refuses a changed non-rebind variable.
    required: true
    rebind: true
  REVIEW_LEVEL:
    description: >-
      The run's review level: light, standard or full
      (../references/review-levels.md). Chosen at review_level_choice and
      routed on at review_level_check and at review's passed edges. Only
      scripts/review-level.sh set changes it: it rebinds the variable through
      `koto init --attach-live` and appends to the review_level.jsonl ledger in
      the same call. Empty on a session from an earlier template, which takes
      the full path. The pattern admits the empty value an unset optional
      variable resolves to, and koto applies it at init and on every rebind,
      so only the three names or nothing reach a gate command.
    required: false
    pattern: ^(light|standard|full)?$
    rebind: true
  REVIEW_FLOOR:
    description: >-
      The lowest review level a coordinator allows, from --review-floor.
      review-level.sh init records it once, at review_level_choice. Not
      rebindable: a bound doesn't move inside a run.
    required: false
    pattern: ^(light|standard|full)?$
  REVIEW_CEILING:
    description: >-
      The highest review level a coordinator allows, from --review-ceiling. A
      raise past it needs a recorded reason, except a raise to the facts
      floor. Recorded with REVIEW_FLOOR.
    required: false
    pattern: ^(light|standard|full)?$
  OFFLOAD_CANARY:
    description: >-
      The live offload canary's switch (docs/guides/offload-live-canary.md).
      With `on`, a run on a host that opted in, while the rule registry marks
      pr-body/no-heading-in-part1 withhold: eligible, is assigned to the
      withheld or the preloaded group at offload_canary. Its default is the one
      change that turns the canary off for every later run. Not rebindable: a
      run never changes group partway through.
    required: false
    default: "on"
    values: ["on", "off"]
  VERIFICATION:
    description: >-
      Where the definition-of-done gate runs. `local` (the default) enters the
      verification state, which runs the repository's verification map on this
      host. `hosted-ci` defers verification to the pull request's hosted CI:
      every edge into verification goes to verification_deferred instead, so
      the map is never launched, and the run still finalizes and opens its
      pull request. A deferral needs VERIFICATION_DEFERRAL_REASON, and
      pr_creation holds until the pull request body records it. Set at init
      (`--var VERIFICATION=hosted-ci`, or `--verification=hosted-ci` through
      work-on-open.sh) and not rebindable: a run never changes where its
      verification runs partway through, and an attach that leaves it out
      keeps the value the run started with.
    required: false
    default: local
    values: [local, hosted-ci]
  VERIFICATION_DEFERRAL_REASON:
    description: >-
      Why verification is deferred to hosted CI, in one line: the stated reason
      a VERIFICATION=hosted-ci run carries into context
      (verification_deferral) and into its pull request body, where
      pr_creation's verification_deferral_recorded gate looks for it verbatim.
      Ignored when VERIFICATION is local. A hosted-ci run without it ends at
      done_blocked rather than running the map or skipping it silently. The
      pattern refuses a value that does not start with a letter or digit, so a
      bare flag can't pass for a reason. koto accepts only letters, digits,
      spaces and . _ / : @ + - in any variable value
      (^[a-zA-Z0-9._/:@+ \-]*$), so a reason with an apostrophe or a comma is
      refused as invalid_var; write it without them, for example "host is in a
      measurement window until 02:40Z". Not rebindable, like VERIFICATION.
    required: false
    pattern: ^([a-zA-Z0-9].*)?$
  UNIT_KIND:
    description: >-
      Whether the unit is a fix (../references/red-first.md): `change` or
      `fix`. Bound at fix_determination by scripts/fix-kind.sh, the only thing
      that changes it: it rebinds the variable through `koto init
      --attach-live` and appends to the fix_kind.jsonl ledger in the same call,
      and it never turns a fix back into a change. fix_determination routes on
      it, and its kind_unchanged gate holds when the variable and the ledger
      disagree, so a hand rebind can't skip the red. Empty until the first
      determination, and again after an attach that didn't pass it (an attach
      resets every rebind variable it leaves out); fix-kind.sh resolve
      restores it from the ledger on the way through fix_determination. No
      state after fix_determination reads it: the gates there read the ledger.
    required: false
    pattern: ^(change|fix)?$
    rebind: true
  FIX_REPORT:
    description: >-
      A plan step's `**Fixes**:` line, the report of the fix the step declares
      (../references/red-first.md). skills/plan/scripts/plan-to-tasks.sh
      forwards it from a step plan, and /execute passes it to the child
      unchanged; it is empty for every other run. Non-empty makes the unit a
      fix with source `step`, and the text is the report a red's passage must
      be found in, ahead of any issue body. koto accepts only letters, digits,
      spaces and . _ / : @ + - in a variable value, and plan-to-tasks.sh
      refuses a Fixes line outside that set before the run starts. Not
      rebindable: the report doesn't change partway through a run.
    required: false

states:
  entry:
    skip_if:
      vars.ISSUE_SOURCE: plan_outline
      mode: plan_backed
    accepts:
      mode:
        type: enum
        values: [issue_backed, free_form, plan_backed, skipped]
        required: true
      issue_number:
        type: string
        description: GitHub issue number (required for issue_backed mode)
      task_description:
        type: string
        description: Task description (required for free_form mode)
      issue_source:
        type: enum
        values: [github, plan_outline]
        description: Source of issue data (plan-backed mode only)
    transitions:
      - target: context_injection
        when:
          mode: issue_backed
      - target: task_validation
        when:
          mode: free_form
      - target: plan_context_injection
        when:
          mode: plan_backed
      - target: skipped_due_to_dep_failure
        when:
          mode: skipped

  context_injection:
    gates:
      context_artifact:
        type: context-exists
        key: context.md
    accepts:
      status:
        type: enum
        values: [completed, override, blocked]
        required: true
      detail:
        type: string
        description: Override type or failure reason
    transitions:
      - target: setup_issue_backed
        when:
          status: completed
          gates.context_artifact.exists: true
      - target: setup_issue_backed
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "context_injection blocked: ${evidence.detail}"
      - target: setup_issue_backed

  task_validation:
    accepts:
      verdict:
        type: enum
        values: [proceed, exit]
        required: true
      rationale:
        type: string
        description: Reasoning behind the validation verdict
    transitions:
      - target: research
        when:
          verdict: proceed
      - target: validation_exit
        when:
          verdict: exit

  validation_exit:
    terminal: true

  research:
    accepts:
      context_summary:
        type: string
        description: Summary of research findings and codebase observations
    transitions:
      - target: post_research_validation

  post_research_validation:
    accepts:
      verdict:
        type: enum
        values: [ready, needs_design, exit]
        required: true
      rationale:
        type: string
        description: Reasoning behind the validation verdict
      revised_scope:
        type: string
        description: Narrowed scope when task can proceed with adjustments
    transitions:
      - target: setup_free_form
        when:
          verdict: ready
      - target: validation_exit
        when:
          verdict: needs_design
      - target: validation_exit
        when:
          verdict: exit

  # The setup_issue_backed and setup_free_form directives in the body below are
  # word-for-word twins; an edit to one belongs in the other.
  setup_issue_backed:
    gates:
      on_feature_branch:
        type: command
        command: "test \"$(git rev-parse --abbrev-ref HEAD)\" != \"main\""
      baseline_exists:
        type: context-exists
        key: baseline.md
    accepts:
      status:
        type: enum
        values: [completed, override, blocked]
        required: true
      detail:
        type: string
        description: Override type or failure reason
    transitions:
      - target: staleness_check
        when:
          status: completed
          gates.on_feature_branch.exit_code: 0
          gates.baseline_exists.exists: true
      - target: staleness_check
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "setup_issue_backed blocked: ${evidence.detail}"
      - target: staleness_check

  setup_free_form:
    gates:
      on_feature_branch:
        type: command
        command: "test \"$(git rev-parse --abbrev-ref HEAD)\" != \"main\""
      baseline_exists:
        type: context-exists
        key: baseline.md
    accepts:
      status:
        type: enum
        values: [completed, override, blocked]
        required: true
      detail:
        type: string
        description: Override type or failure reason
    transitions:
      - target: analysis
        when:
          status: completed
          gates.on_feature_branch.exit_code: 0
          gates.baseline_exists.exists: true
      - target: analysis
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "setup_free_form blocked: ${evidence.detail}"
      - target: analysis

  plan_context_injection:
    gates:
      context_artifact:
        type: context-exists
        key: context.md
        override_default:
          exists: true
          error: ""
    accepts:
      status:
        type: enum
        values: [completed, override, blocked]
        required: true
      issue_source:
        type: enum
        values: [github, plan_outline]
        description: >
          Source of issue data. github routes directly to setup; plan_outline routes
          through plan_validation first since the outline item needs validation before setup.
      detail:
        type: string
        description: Override type or failure reason
    transitions:
      # github path: context injected from GitHub issue, proceed to setup directly
      - target: setup_plan_backed
        when:
          status: completed
          issue_source: github
          gates.context_artifact.exists: true
      # plan_outline path: outline extracted from PLAN doc, validate before setup
      - target: plan_validation
        when:
          status: completed
          issue_source: plan_outline
          gates.context_artifact.exists: true
      - target: setup_plan_backed
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "plan_context_injection blocked: ${evidence.detail}"
      - target: setup_plan_backed

  plan_validation:
    # verdict is decider-eligible. The decider block lives inside the field,
    # and a user without a decider sees this state exactly as before. `proceed`
    # is shadow and `exit` is never: exit
    # routes to the validation_exit terminal, which no answer may take on a
    # model's word. Golden fixtures sit beside this template as
    # work-on.plan_validation.verdict.decider.jsonl, and
    # scripts/check-decider-declarations.sh holds the modes to
    # scripts/decider-declarations.tsv.
    #
    # step_detail stops a plan/v2 step that is still a one-line outline before
    # any implementation. plan-to-tasks.sh names every plan/v2 task step-<N>,
    # and the check reads that step from the PLAN as committed now, through
    # `shirabe plan outlines`: exit 0 detailed, 1 an outline (its stderr line,
    # which koto shows as the gate's finding, names the step), 2 refused. The
    # PLAN is PLAN_DOC_MOVED when it is set (a child whose checkout moved) and
    # PLAN_DOC otherwise. A plan/v1 task's name is never step-<N>, so the
    # check passes it at once without reading anything. proceed needs exit 0;
    # exit is open whatever the check said. Not overridable: an override would
    # start work on a step that has no detail to build from.
    gates:
      step_detail:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/step-detail-check.sh" || exit 2; "{{PLUGIN_ROOT}}/skills/work-on/scripts/step-detail-check.sh" --task "{{ARTIFACT_PREFIX}}" "$(if [ -n "{{PLAN_DOC_MOVED}}" ]; then printf %s "{{PLAN_DOC_MOVED}}"; else printf %s "{{PLAN_DOC}}"; fi)"'
        overridable: false
    accepts:
      verdict:
        type: enum
        values: [proceed, exit]
        required: true
        description: Is the plan outline item clear and scoped enough to implement?
        decider:
          answers:
            proceed: {description: "Names a concrete change with checkable criteria."}
            exit:    {description: "Vague, contradictory, or needs design first.", mode: never}
          escape:  {value: unclear, description: "Missing, truncated, or unjudgeable."}
          inputs:
            - {context: context.md, label: outline_item, max_bytes: 12000}
            # PLAN_DOC, not PLAN_DOC_MOVED: koto sends a var input as its text
            # and never opens it, so a moved PLAN can't change the verdict,
            # and a changed input would reset this declaration's evidence.
            - {var: PLAN_DOC, label: plan_path}
      rationale:
        type: string
        description: Reasoning behind the validation verdict
    transitions:
      - target: setup_plan_backed
        when:
          verdict: proceed
          gates.step_detail.exit_code: 0
      - target: validation_exit
        when:
          verdict: exit

  setup_plan_backed:
    skip_if:
      vars.SHARED_BRANCH:
        is_set: true
      status: override
    gates:
      on_feature_branch:
        type: command
        command: "test \"$(git rev-parse --abbrev-ref HEAD)\" != \"main\""
      baseline_exists:
        type: context-exists
        key: baseline.md
    accepts:
      status:
        type: enum
        values: [completed, override, blocked]
        required: true
      detail:
        type: string
        description: Override type or failure reason
    transitions:
      - target: analysis
        when:
          status: completed
          gates.on_feature_branch.exit_code: 0
          gates.baseline_exists.exists: true
      - target: analysis
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "setup_plan_backed blocked: ${evidence.detail}"
      - target: analysis

  staleness_check:
    gates:
      # shirabe's own check, reached through PLUGIN_ROOT because koto runs the
      # gate from the repository being worked. Its exit status is the verdict:
      # 0 fresh, 1 stale, 3 unavailable, 2 usage. The test -x guard turns an
      # empty or wrong PLUGIN_ROOT into 3 rather than 127. No pipe, so koto
      # running gates without pipefail can't mask the script's status.
      #
      # An issue in another repository (ISSUE_REPO set) is also 3: the check
      # reads the issue and its milestone from the current repository, where
      # issue N is a different issue or none, so a verdict there would be on
      # the wrong issue. Reading it from ISSUE_REPO is shirabe#1033. With
      # ISSUE_REPO empty the command runs as before.
      staleness_fresh:
        type: command
        command: 'test -z "{{ISSUE_REPO}}" || exit 3; test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-staleness.sh" || exit 3; "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-staleness.sh" --issue "{{ISSUE_NUMBER}}"'
        override_default:
          exit_code: 0
          error: ""
    accepts:
      staleness_signal:
        type: enum
        values: [override, blocked]
        description: >-
          Absent on every answered path: koto routes on the check's exit status
          itself. Accepted only on exit 2, the one status no edge routes.
      detail:
        type: string
        description: The override reason, or the blocking detail
    # A routing gate (DESIGN-output-gates Decision 9): its non-zero exits are
    # answers, not violations, and it prints no finding. The run advances on
    # the exit status with no evidence: 0 fresh and 3 unavailable go to
    # analysis, as does -1 (koto could not run the check to completion), and 1
    # stale goes to introspection. Only exit 2, a usage error and so a
    # template defect, holds, and only there does the agent submit anything.
    # Every edge names the gate, which is what lets koto prove them exclusive.
    transitions:
      - target: analysis
        when:
          gates.staleness_fresh.exit_code: 0
      - target: introspection
        when:
          gates.staleness_fresh.exit_code: 1
      - target: analysis
        when:
          gates.staleness_fresh.exit_code: 3
      - target: analysis
        when:
          gates.staleness_fresh.exit_code: -1
      - target: analysis
        when:
          gates.staleness_fresh.exit_code: 2
          staleness_signal: override
      - target: done_blocked
        when:
          gates.staleness_fresh.exit_code: 2
          staleness_signal: blocked
        context_assignments:
          failure_reason: "staleness_check blocked: ${evidence.detail}"

  introspection:
    gates:
      introspection_artifact:
        type: context-exists
        key: introspection.md
    accepts:
      introspection_outcome:
        type: enum
        values: [approach_unchanged, approach_updated, issue_superseded]
        required: true
      rationale:
        type: string
        description: What changed or why the issue is superseded
    transitions:
      - target: done_blocked
        when:
          introspection_outcome: issue_superseded
        context_assignments:
          failure_reason: "issue superseded: ${evidence.rationale}"
      - target: analysis
        when:
          introspection_outcome: approach_unchanged
          gates.introspection_artifact.exists: true
      - target: analysis
        when:
          introspection_outcome: approach_updated
          gates.introspection_artifact.exists: true
      - target: analysis

  analysis:
    # Records impl_base, the commit this issue's work starts from, so
    # changed_paths_record can later diff exactly this run's commits. All three
    # entry modes converge here, which is why the base is taken here and not in
    # a mode's own setup state: every run passes through it, and every run
    # passes through it before implementation commits anything.
    #
    # The script writes the key once and leaves it alone on every later entry.
    # analysis is re-entered on scope_changed_retry and on implementation's
    # scope_expanded_retry, both after commits may exist, and the action re-runs
    # on each of those entries; a base that moved forward there would drop the
    # earlier commits from the record. On a SHARED_BRANCH, the base is also what
    # keeps the commits siblings made before this run out of it.
    #
    # The action's failure stops the tick with the fallback below. The run can
    # go on once impl_base is recorded, by a re-run or by the agent; without it
    # changed_paths_record falls back to a merge-base, but has_commits fails
    # (it guards routes that must not be taken without commits), so the
    # fallback asks for the key before the analysis evidence.
    #
    # {{SESSION_NAME}} rather than a name rebuilt from a variable: this template
    # is both initialized directly and materialized as a child, so no declared
    # variable carries the session's name. koto substitutes it inside a
    # default_action command.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/work-on/scripts/record-changed-paths.sh --base "{{SESSION_NAME}}"'
      fallback: >-
        koto could not record impl_base, the commit this issue's work starts
        from. Read the command's own output above: the script exits 64 when
        HEAD names no commit or this is not a git repository, 66 when writing
        the context key failed, and 127 or 126 when PLUGIN_ROOT does not reach
        the plugin. Fix the cause and tick again -- the action re-runs on entry
        and never overwrites a base it already recorded. If it can't be fixed,
        record the base yourself before committing anything:
        `git rev-parse HEAD | koto context add <session> impl_base`, with
        this workflow's session name for <session>.
        Then do the analysis and submit `plan_outcome` as usual, which skips
        the action. Don't go on without impl_base: the has_commits gate on the
        docs and scrutiny routes fails until it is recorded.
    gates:
      plan_artifact:
        type: context-exists
        key: plan.md
    accepts:
      plan_outcome:
        type: enum
        values: [plan_ready, already_complete, blocked_missing_context, scope_changed_retry, scope_changed_escalate]
        required: true
      approach_summary:
        type: string
        description: Summary of the implementation approach
    transitions:
      # The live offload canary assigns the run's group next, then the
      # review level is chosen, before anything is implemented.
      - target: offload_canary
        when:
          plan_outcome: plan_ready
          gates.plan_artifact.exists: true
      - target: done_already_complete
        when:
          plan_outcome: already_complete
      - target: analysis
        when:
          plan_outcome: scope_changed_retry
      - target: done_blocked
        when:
          plan_outcome: scope_changed_escalate
        context_assignments:
          failure_reason: "scope changed: escalation required: ${evidence.approach_summary}"
      - target: done_blocked
        when:
          plan_outcome: blocked_missing_context
        context_assignments:
          failure_reason: "analysis blocked: missing context: ${evidence.approach_summary}"

  # The live offload canary (DESIGN-offload-live-canary.md). The
  # draw records the run's group in the session directory and prints the
  # PR-body conformance text this run reads, captured as PR_BODY_RULES for the
  # pr_creation directive. The gate reads the recorded group back: 0 withheld,
  # 1 preloaded, 3 neither (canary off, a shared branch, a host that hasn't
  # opted in, the rule not eligible, or any failure). The action's command ends
  # in a fallback because a failing default action would hold the run here, and
  # the gate maps every exit but 0 and 1 to 3 so a broken or missing script has
  # an edge too. Both restate offload-canary.sh's own contract (its header): a
  # change to draw's output or arm's exit codes changes these two commands.
  offload_canary:
    default_action:
      command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/offload-canary.sh" && "{{PLUGIN_ROOT}}/skills/work-on/scripts/offload-canary.sh" draw "{{OFFLOAD_CANARY}}" "{{SHARED_BRANCH}}" "{{SESSION_DIR}}" "{{PLUGIN_ROOT}}" || echo "{{PLUGIN_ROOT}}/references/pr-body-conformance.md"'
      capture_stdout_as: PR_BODY_RULES
    gates:
      offload_arm:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/offload-canary.sh" || exit 3; "{{PLUGIN_ROOT}}/skills/work-on/scripts/offload-canary.sh" arm "{{SESSION_DIR}}" || { test $? -eq 1 && exit 1; exit 3; }'
    transitions:
      - target: offload_arm_withheld
        when:
          gates.offload_arm.exit_code: 0
      - target: offload_arm_preloaded
        when:
          gates.offload_arm.exit_code: 1
      - target: review_level_choice
        when:
          gates.offload_arm.exit_code: 3

  # The two marker states pass straight through to review_level_choice. Their
  # names are what carries a run's group to an exporter such as Datadog:
  # koto's state_entered event has the state name in koto.state, and no
  # variable value is ever exported.
  offload_arm_withheld:
    transitions:
      - target: review_level_choice

  offload_arm_preloaded:
    transitions:
      - target: review_level_choice

  review_level_choice:
    # The run commits to a review level here, after analysis has read the code
    # and before anything is implemented (references/review-levels.md). The
    # only way forward is REVIEW_LEVEL being set, and the only way it is set is
    # review-level.sh set, which also writes the ledger. koto can't route on a
    # context key, so the level lives in a rebindable variable.
    #
    # The action records the coordinator's bound, the acceptance-criteria copy
    # the facts compare against, and the rules copy they classify with. It
    # writes once: a re-entry (analysis re-runs on scope_expanded_retry) finds
    # the bound line and changes nothing, and a level already set advances
    # straight on. `set` before the bound is recorded is refused, so the
    # choice can't skip the bound.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/work-on/scripts/review-level.sh init "{{SESSION_NAME}}" "{{REVIEW_FLOOR}}" "{{REVIEW_CEILING}}"'
      fallback: >-
        koto could not record the review-level bound. Read the command's own
        output above: review-level.sh exits 64 when the rules file is
        malformed or a bound value is not a level name, 66 when a koto context
        read or write failed, and 127 or 126 when PLUGIN_ROOT does not reach
        the plugin. Fix the cause and tick again; the action re-runs on entry
        and writes nothing once the bound is recorded. Until it is, `set`
        refuses. If it can't be fixed, submit `level_status: blocked` with
        `detail`.
    accepts:
      level_status:
        type: enum
        values: [blocked]
        description: >-
          Submitted only to stop the run when no level can be recorded. The
          passing path submits nothing: once review-level.sh set has bound
          REVIEW_LEVEL, the next tick advances.
      detail:
        type: string
        description: Why no review level could be recorded.
    transitions:
      - target: fix_determination
        when:
          vars.REVIEW_LEVEL:
            is_set: true
      - target: done_blocked
        when:
          vars.REVIEW_LEVEL:
            is_set: false
          level_status: blocked
        context_assignments:
          failure_reason: "review level not chosen: ${evidence.detail}"

  fix_determination:
    # Is the unit a fix (../references/red-first.md)? Decided here, before
    # anything is implemented, and on every return through analysis. koto
    # can't route on a context key, so the kind lives in the rebindable
    # UNIT_KIND, which only fix-kind.sh binds, mirrored by the fix_kind.jsonl
    # ledger, as REVIEW_LEVEL is by review-level.sh.
    #
    # The action records the determination: from the issue's labels against
    # the repository's `## Fix Labels:` (read at impl_base), and from
    # FIX_REPORT, a plan step's Fixes line. It adds a fix over a recorded
    # change and never the reverse. It also stores the unit's report
    # (fix_report.txt) once; the free-form task text comes from the session's
    # event log. The variable it rebinds is seen from the next tick on (koto
    # 0.21.0 resolves this tick's routes with the value the tick started
    # with), so a fresh determination advances on the second tick, as
    # review_level_choice does after `set`.
    #
    # The action never overwrites a non-empty UNIT_KIND, only restores an
    # empty one. A hand rebind away from the ledger therefore fails
    # kind_unchanged (fix-kind.sh agree) and holds the run here; no route
    # leaves without it.
    #
    # Before that, the action writes the test-change ledger's header
    # (test-change.sh init --entry): the author, impl_base and the work tree
    # every later acceptance is judged against. It runs here, after
    # review_level_choice stored the rules copy the classifier reads, and
    # writes once; a later entry finds the header and changes nothing.
    default_action:
      command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/test-change.sh" || exit 2; test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/fix-kind.sh" || exit 2; "{{PLUGIN_ROOT}}/skills/work-on/scripts/test-change.sh" init "{{SESSION_NAME}}" --entry --shared-branch "{{SHARED_BRANCH}}" && "{{PLUGIN_ROOT}}/skills/work-on/scripts/fix-kind.sh" resolve "{{SESSION_NAME}}" --current "{{UNIT_KIND}}" --issue "{{ISSUE_NUMBER}}" --issue-repo "{{ISSUE_REPO}}" --fix-report "{{FIX_REPORT}}" --task-log "{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl"'
      fallback: >-
        koto could not record whether this unit is a fix, or could not write
        the test-change ledger's header. Read the command's own output above.
        test-change.sh exits 1 when impl_base is not where the unit started
        (or the ledger holds lines but no header), 2 when impl_base, the rules
        copy or the work tree can't be read or koto is below shirabe's minimum, 66
        when a koto context write failed, and 75 when another writer holds the
        ledger's lock (tick again). fix-kind.sh exits 66 when the issue can't
        be read with gh or a koto call failed, 64 when CLAUDE.md at the base
        declares `## Fix Labels:` more than once, and the test -x guards exit
        2 when PLUGIN_ROOT does not reach the plugin. Fix the cause and tick
        again; the action re-runs on entry. If it can't be fixed, submit
        `kind_status: blocked` with `detail`.
    gates:
      kind_unchanged:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/fix-kind.sh" || exit 2; "{{PLUGIN_ROOT}}/skills/work-on/scripts/fix-kind.sh" agree "{{SESSION_NAME}}" "{{UNIT_KIND}}"'
    accepts:
      kind_status:
        type: enum
        values: [blocked]
        description: >-
          Submitted only to stop the run when no determination can be
          recorded. The passing path submits nothing: once UNIT_KIND agrees
          with the ledger, the next tick advances.
      detail:
        type: string
        description: Why no determination could be recorded.
    transitions:
      - target: implementation
        when:
          gates.kind_unchanged.exit_code: 0
          vars.UNIT_KIND: change
      - target: reproduce
        when:
          gates.kind_unchanged.exit_code: 0
          vars.UNIT_KIND: fix
      - target: done_blocked
        when:
          gates.kind_unchanged.exit_code: 1
          kind_status: blocked
        context_assignments:
          failure_reason: "fix determination blocked: ${evidence.detail}"
      - target: done_blocked
        when:
          gates.kind_unchanged.exit_code: 2
          kind_status: blocked
        context_assignments:
          failure_reason: "fix determination blocked: ${evidence.detail}"

  reproduce:
    # A fix records its red here, before implementation: the check run on
    # the base code with the unit's committed tests applied, failing, with a
    # marker found in both the report and the output (red-first.sh red). A
    # bug no check can reproduce records a before-observation instead. The
    # agent writes and commits the reproducing test and runs the script; the
    # gate reads the record, so the only way on is a red or an observation.
    # The red always runs on the base, so a fix declared on a return to
    # analysis, after code changed, still proves the failure without it.
    #
    # red-first.sh check-red exits 0 for a red or a before-observation (and
    # for a unit that isn't a fix), 1 holding with finding red-first/no-red,
    # and 2 when it can't decide.
    gates:
      red_recorded:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/red-first.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=red_recorded "{{PLUGIN_ROOT}}/skills/work-on/scripts/red-first.sh" check-red "{{SESSION_NAME}}"'
    accepts:
      reproduce_status:
        type: enum
        values: [blocked]
        description: >-
          Absent on the passing path: koto advances once red_recorded passes.
          Submit `blocked` only when neither a red nor an observation can be
          recorded.
      detail:
        type: string
        description: Why the red could not be recorded.
    transitions:
      - target: implementation
        when:
          gates.red_recorded.exit_code: 0
      - target: done_blocked
        when:
          gates.red_recorded.exit_code: 1
          reproduce_status: blocked
        context_assignments:
          failure_reason: "reproduce blocked: ${evidence.detail}"
      - target: done_blocked
        when:
          gates.red_recorded.exit_code: 2
          reproduce_status: blocked
        context_assignments:
          failure_reason: "reproduce blocked: ${evidence.detail}"

  implementation:
    # Every return here means the code is about to change, so a verdict about
    # the code as it was is stale: the panels' results and the summary. The
    # panel retry blocks and finalization's issues_found block already clear
    # them before routing back, and confirm it; verification's exit 1 is koto's
    # own edge, with no agent step before it, so koto clears them on entry. The
    # session's first entry clears nothing.
    #
    # The four panels' <panel>_scope.json go too. A scope names the HEAD it was
    # planned at, and panel-scope.sh --record refuses (exit 68) a round whose
    # scope names another HEAD. On the --plan fallback path no new scope is
    # written, so a scope left from before the fix would refuse every round;
    # with none, --record has nothing to compare and records. The verdict
    # ledger is never cleared: it is what a retry keeps.
    clear_on_entry: [scrutiny_results.json, review_results.json, qa_results.json, light_results.json, summary.md, scrutiny_scope.json, review_scope.json, qa_scope.json, light_scope.json]
    gates:
      on_feature_branch_impl:
        type: command
        command: "test \"$(git rev-parse --abbrev-ref HEAD)\" != \"main\""
      # has_commits used to sit here and gate the code and docs routes. It
      # moved when the issue-type question moved out of this state: the code
      # route now checks it at scrutiny's passed edge, the docs route at
      # issue_type_routing, and the task route never did.
      #
      # A `tests_passing` gate used to sit here, running `go test ./...` before
      # the review panels. It was removed (#376) pending a safer design, not
      # because the idea was wrong: a machine-checked proof that the change works,
      # taken before three panels spend effort on it, is worth having.
      #
      # This instance could not serve that purpose. It did nothing in seven of the
      # nine repositories it ran in, including shirabe, which ships it; it ran a
      # command one repository's own verification map documents as the wrong way
      # to verify it; and in one repository it executed a suite that spawned copies
      # of itself, unattended, until the host reached a load average in the
      # thousands. koto's 30-second bound killed the gate's process group, which is
      # a defence against a hang and not against something that multiplies first.
      #
      # Nothing replaces it here yet. Verification of the change still happens at
      # the `verification` state, against the repository's own map, and still
      # fails closed when nothing can verify. A replacement is expected; the
      # constraints it has to meet are tracked in #384.
    accepts:
      implementation_status:
        type: enum
        values: [complete, partial_tests_failing_retry, partial_tests_failing_escalate, scope_expanded_retry, blocked]
        required: true
      rationale:
        type: string
        description: What was accomplished or what is blocking progress
    transitions:
      # One edge for a finished implementation, whatever the issue's type.
      # The type is asked once, at issue_type_routing, after
      # changed_paths_record has put the changed paths in context.
      - target: changed_paths_record
        when:
          implementation_status: complete
          gates.on_feature_branch_impl.exit_code: 0
      - target: implementation
        when:
          implementation_status: partial_tests_failing_retry
      # scope expanded mid-implementation: rewrite the plan in analysis
      - target: analysis
        when:
          implementation_status: scope_expanded_retry
      - target: done_blocked
        when:
          implementation_status: partial_tests_failing_escalate
        context_assignments:
          failure_reason: "implementation blocked: ${evidence.rationale}"
      - target: done_blocked
        when:
          implementation_status: blocked
        context_assignments:
          failure_reason: "implementation blocked: ${evidence.rationale}"

  changed_paths_record:
    # Mechanical, and normally invisible. The action writes changed_paths.txt
    # -- the base, the commit count, and one `git diff --name-status -M` line
    # per changed path, capped at 200 lines and 8192 bytes -- and the gate
    # passes on the key, so the state advances with no evidence.
    #
    # It sits apart from issue_type_routing so the question state stays a
    # single field with no gate on its code route. The file is facts only: the
    # script never names a type, and the question is still asked.
    #
    # The action re-runs on every entry without evidence, which includes each
    # lap back through implementation, so the record describes the latest
    # commits rather than the first round's. When it cannot resolve a base it
    # removes the previous lap's key before failing, so the gate below never
    # passes on a stale record.
    #
    # Every transition names the gate, per
    # references/default-action-conversion.md: the passing path needs none of
    # the optional evidence, and the failing path gets the full schema.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/work-on/scripts/record-changed-paths.sh --write "{{SESSION_NAME}}"'
      fallback: >-
        koto could not record the paths this implementation changed. Read the
        command's own output above: the script exits 64 when no base resolves
        (impl_base is unset and HEAD shares no history with the default branch
        or local main), 66 when writing the context key failed, and 127 or 126
        when PLUGIN_ROOT does not reach the plugin. Fix the cause and tick
        again -- the action re-runs on entry, so nothing needs submitting.
        Submit `paths_status: override` to go on to the issue-type question
        without the record, or `paths_status: blocked` with `detail` to stop
        the run.
    gates:
      changed_paths_recorded:
        type: context-exists
        key: changed_paths.txt
    accepts:
      paths_status:
        type: enum
        values: [override, blocked]
        description: >-
          Absent on the passing path. The state advances with no evidence when
          the gate passes, so the agent never sees it.
      detail:
        type: string
        description: Why the changed paths could not be recorded.
    transitions:
      - target: issue_type_routing
        when:
          gates.changed_paths_recorded.exists: true
      - target: issue_type_routing
        when:
          gates.changed_paths_recorded.exists: false
          paths_status: override
      - target: done_blocked
        when:
          gates.changed_paths_recorded.exists: false
          paths_status: blocked
        context_assignments:
          failure_reason: "changed_paths_record blocked: ${evidence.detail}"

  issue_type_routing:
    # The one place /work-on asks for the issue's type. A single field, so the
    # answer is not bundled with a generative one, and no gate on the code or
    # task route: code's commit check moved to scrutiny's passed edge, and task
    # never had one. Only docs keeps has_commits here, because docs goes
    # straight to verification with no later state that would notice a branch
    # carrying no commits.
    #
    # has_commits is byte-identical to scrutiny's copy. It counts the commits
    # since impl_base, the commit analysis recorded as this run's start, so
    # it needs no local branch named main and ignores commits the run didn't
    # make; an unrecorded impl_base fails it (scripts/has-commits.sh).
    #
    # issue_type is decider-eligible: `code` is shadow, and `docs` and `task`
    # are never. The code route tests no gate, so promoting `code` later clears
    # koto's floor; the docs route's gate is one reason docs stays never. The
    # inputs are the two keys the directive already points the agent at, both
    # gated upstream. Fixtures: work-on.issue_type_routing.issue_type.decider.jsonl.
    gates:
      has_commits:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/has-commits.sh" "{{SESSION_NAME}}"'
    accepts:
      issue_type:
        type: enum
        values: [code, docs, task]
        required: true
        description: >-
          What kind of change this issue turned out to be, judged from the
          changed paths in changed_paths.txt, the issue's context in
          context.md, and the ISSUE_TYPE hint. code: behaviour changes that
          run through the review panels the run's review level names. docs: writing or
          structural documentation changes that skip the panels. task:
          operational work with no reviewable change set. Use code when
          unsure; it is the route that checks the most.
        decider:
          answers:
            code: {description: "Changes behaviour: source, tests, build or CI logic, or a skill or koto template that drives a workflow, even when every changed path ends in .md."}
            docs: {description: "Changes only writing or structural documentation that no workflow executes, such as READMEs, guides, and design or planning docs.", mode: never}
            task: {description: "Operational work, such as running scripts or commands, that left no reviewable change set.", mode: never}
          escape: {value: unclear, description: "The issue context or the changed paths are missing, truncated, or contradict each other too much to judge."}
          inputs:
            - {context: context.md, label: issue_context}
            - {context: changed_paths.txt, label: changed_paths}
    transitions:
      # A code change passes the review-level check before its first panel.
      - target: review_level_check
        when:
          issue_type: code
      # Every edge into verification has a twin into verification_deferred,
      # split on VERIFICATION; see that state's comment.
      - target: verification
        when:
          issue_type: docs
          gates.has_commits.exit_code: 0
          vars.VERIFICATION: local
      - target: verification_deferred
        when:
          issue_type: docs
          gates.has_commits.exit_code: 0
          vars.VERIFICATION: hosted-ci
      - target: verification
        when:
          issue_type: task
          vars.VERIFICATION: local
      - target: verification_deferred
        when:
          issue_type: task
          vars.VERIFICATION: hosted-ci

  review_level_check:
    # Between the issue-type question and the first panel of a code change, on
    # every lap. The action gathers the facts of the change (lines, files, path
    # classes, whether tests or the acceptance criteria changed) into
    # review_facts.json and derives a floor from the rules copy
    # review_level_choice stored, so a diff that edits the rules can't lower
    # its own floor. koto runs the action again on every tick that reaches the
    # state without evidence, so after a hold and a raise the next tick writes
    # the ledger's `check` line at the raised level.
    #
    # On a SHARED_BRANCH the action measures impl_base alone: the merge-base
    # diff there holds every earlier sibling's commits, so a late step would
    # floor on work that isn't its own. An unset SHARED_BRANCH arrives as ""
    # and keeps the larger-diff rule.
    #
    # level_floor is the guarantee, for every user: exit 0 at or above the
    # floor, inside the bound (or past the ceiling with a breach recorded),
    # matching the ledger, with facts gathered at HEAD; exit 1 holds with a
    # `hold:` line; exit 3 is an unset level, a session from an earlier
    # template, which keeps the full path. koto's override record is the only
    # way past a hold without a raise.
    #
    # level_fits_facts is a veto-mode decider check, active only for a user
    # whose decider mode is auto; for anyone else koto treats it as not
    # declared. Its slice is a fixed projection of the facts and the level,
    # with the level definitions rendered from the stored rules copy, never a
    # path, a reason or issue text. A fail blocks the state like a
    # hold; no route reads it, so a wrong answer can hold the run but never
    # route it or lower the level.
    #
    # A criterion the decider can't answer falls back to the agent (koto
    # 0.20.0): the check is pending, with level_fits_facts under its
    # output.awaiting, until `koto decider answer` records the agent's answer.
    # That holds a shadow user here too, where an older koto passed the
    # criterion unjudged, so the directive gives the command. The answer is
    # the agent's, never a decider verdict: koto writes it as
    # decider_check_answered, not as decider_checked or a ledger line, and the
    # raise an agent fail calls for is a plain `set`, since a `veto` ledger
    # line records only a raise the decider asked for.
    #
    # The blocked route carries the gate's exit 1: an evidence-only route
    # shares no field with the gate routes and fails koto's exclusivity check.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/work-on/scripts/review-level.sh facts "{{SESSION_NAME}}" "{{REVIEW_LEVEL}}" --shared-branch "{{SHARED_BRANCH}}"'
      fallback: >-
        koto could not gather the facts of this change. Read the command's own
        output above: review-level.sh exits 64 when no base resolves or the
        stored rules copy is malformed. No base resolves when impl_base is
        unset and HEAD shares no history with the default branch or main, or
        when impl_base is unset on a shared branch, where it is the only base.
        It exits 66 when a koto context read or write failed, and 127 or 126
        when PLUGIN_ROOT does not reach the plugin. Fix the cause and tick again; the action re-runs on entry.
        The level_floor gate holds until the facts are recorded at HEAD. If
        it can't be fixed, submit `level_status: blocked` with `detail`.
    gates:
      level_floor:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/review-level.sh" check "{{SESSION_NAME}}" "{{REVIEW_LEVEL}}"'
      level_fits_facts:
        type: decider-check
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/review-level.sh" slice "{{SESSION_NAME}}" "{{REVIEW_LEVEL}}"'
        max_bytes: 2048
        label: review_facts
        criteria:
          level_fits_facts:
            rule_ref: "https://github.com/tsukumogami/shirabe/blob/main/skills/work-on/references/review-levels.md"
            question: "Given these facts about a change and the review level definitions, is the chosen level too light?"
            pass: "The chosen level is at least as thorough as these facts call for under the level definitions."
            fail: "The facts call for a more thorough level than the one chosen: the chosen level is too light."
            escape: "The facts are missing or empty, or don't say enough to judge the level."
            mode: veto
    accepts:
      level_status:
        type: enum
        values: [blocked]
        description: >-
          Submitted only to stop a run the level check holds and that can't be
          raised or overridden. The passing path submits nothing.
      detail:
        type: string
        description: Why the run can't pass the level check.
    transitions:
      - target: light_review
        when:
          gates.level_floor.exit_code: 0
          vars.REVIEW_LEVEL: light
      - target: scrutiny
        when:
          gates.level_floor.exit_code: 0
          vars.REVIEW_LEVEL: standard
      - target: scrutiny
        when:
          gates.level_floor.exit_code: 0
          vars.REVIEW_LEVEL: full
      # No level: a session from an earlier template keeps today's full path,
      # and the action has written an `unset` line.
      - target: scrutiny
        when:
          gates.level_floor.exit_code: 3
          vars.REVIEW_LEVEL:
            is_set: false
      - target: done_blocked
        when:
          gates.level_floor.exit_code: 1
          level_status: blocked
        context_assignments:
          failure_reason: "review level check blocked: ${evidence.detail}"

  scrutiny:
    # Decides, before anything is spawned, what this round runs (#590).
    # panel-scope.sh reads the findings ledger and the fix diff and writes
    # scrutiny_scope.json. A full round (the first, or one a full-round
    # trigger fires on) spawns every seat, each handed its own unclosed
    # findings. Any other round keeps every seat and plans at most one run,
    # the panel's re-verifier: the findings the fix made due, by id, and the
    # fix-diff review when it lands here. With nothing to run and no unclosed
    # blocking finding it also writes scrutiny_results.json marked carried,
    # and the scrutiny_carried gate below advances the state with no spawn and
    # no evidence. The state is still entered, so koto's visit and attempt
    # counts record the round either way.
    #
    # Every transition names scrutiny_carried, per
    # references/default-action-conversion.md: exit 0 is the carried edge,
    # exit 1 every other. The script never exits anything else from
    # --carried, so the state can't hold on an unrouted exit.
    #
    # The panel's pass is koto's, not the agent's (DESIGN-output-gates
    # Decision 4, gate 6). scrutiny_verdict reads the verdict ledger, where
    # --record derived each seat's verdict from its findings' severity: exit 0
    # advances with no evidence, 1 (a seat is blocking) takes the agent's
    # blocking_retry or blocking_escalate, 2 (the round isn't fully recorded,
    # or the ledger can't be read) holds. Escalation is also taken at 2: it
    # ends the run, so it can't skip the panel, and a run whose round can't be
    # recorded must still have a way to stop.
    #
    # The decider batch: scrutiny_decider, a `decider-check` gate in
    # `mode: shadow`, asks Jev one closed question about the decisions this
    # run recorded in analysis and implementation
    # (work-on/scrutiny-decision-reasons, references/jev-criteria.md). Its
    # slice is decision-reasons.sh's projection of koto's own session log,
    # never a context key the agent writes. It runs beside the seats, which
    # are all still spawned: the other scrutiny questions don't fit a
    # 2,560-byte slice, and their contracts in the registry say so. koto lets
    # no `when`, `skip_if` or context assignment read a decider check, and a
    # shadow check is never failed, so the gate can't change which transition
    # this state takes. It can hold the state, though: a criterion the
    # decider can't answer is pending until the agent answers it with
    # `koto decider answer` (koto 0.20.0), in shadow as in veto and on a
    # carried round as on a full one, so the directive gives that command, as
    # review_level_check's does. Any answer then lets the check through: a
    # shadow fail, the agent's or the decider's, is only recorded. A run with
    # no recorded decision has an empty slice, which koto records as
    # not_graded without asking. Fixtures:
    # scripts/jev-criteria/fixtures/work-on-scrutiny-decision-reasons.jsonl.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh --plan scrutiny "{{SESSION_NAME}}"'
      fallback: >-
        koto could not decide what this round runs. Read the command's
        own output above: panel-scope.sh exits 64 when HEAD names no commit,
        65 when the ledger could not be updated, 66 when a context write
        failed, 127 when jq is missing, and 127 or 126 also when PLUGIN_ROOT
        does not reach the plugin. Run every seat of the panel
        as a full round and record it with panel-scope.sh --record as usual;
        with no scope, scrutiny_verdict reads the ledger's findings and every seat's verdict,
        and the scrutiny_carried gate reads exit 1, so the round routes on
        the verdict as any other.
    gates:
      scrutiny_carried:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh" --carried scrutiny "{{SESSION_NAME}}"'
      # Holds the passed and blocking_retry edges until the round's spawned
      # seats are recorded (panel-scope.sh --record): a skipped record leaves
      # a seat's previous verdict in the ledger, and it would be read as
      # current next round.
      scrutiny_recorded:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh" --recorded scrutiny "{{SESSION_NAME}}"'
      # The panel's pass, from the ledger (gate 6). A person's override is the
      # only way past it, listed by `koto overrides list`.
      scrutiny_verdict:
        type: command
        command: 'SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=scrutiny_verdict SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" "{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh" --verdict scrutiny "{{SESSION_NAME}}"'
        override_default:
          exit_code: 0
          error: ""
      # Moved here from implementation with the issue-type question, so the
      # code route out of issue_type_routing carries no gate. It still stands
      # between a code-typed issue and the panels after this one: a run with
      # no commits since impl_base cannot pass scrutiny, whatever the panel
      # reported. Identical to issue_type_routing's copy.
      has_commits:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/has-commits.sh" "{{SESSION_NAME}}"'
      scrutiny_decider:
        type: decider-check
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/decision-reasons.sh" slice "{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl"'
        max_bytes: 2560
        label: decisions
        criteria:
          work-on/scrutiny-decision-reasons:
            rule_ref: "https://github.com/tsukumogami/shirabe/blob/main/references/jev-criteria.md"
            question: "Does every decision listed here give, in its reason, why the choice was made: a constraint, a fact about the code or the system, or an alternative it rules out, rather than a restatement of the choice?"
            pass: "Each decision's reason says why the choice was made, in terms other than the choice itself."
            fail: "At least one decision's reason only restates or paraphrases its choice, or gives no reason at all."
            escape: "The list can't be read as decisions, so it can't be judged."
            mode: shadow
    accepts:
      scrutiny_outcome:
        type: enum
        values: [blocking_retry, blocking_escalate]
        description: >-
          Absent when the panel passes: koto advances on scrutiny_verdict.
          Submit a value only while scrutiny_verdict exits 1 (a seat is
          blocking), or blocking_escalate while it exits 2.
      failure_reason:
        type: string
        description: Reason for blocking escalation (required when scrutiny_outcome is blocking_escalate)
    transitions:
      # Every seat kept its verdict: nothing to spawn, so koto advances.
      # has_commits can't be repeated here: with it failing, a carried scope
      # would match no edge and the state would hold. panel-scope.sh enforces
      # it instead -- --plan keeps no seat while there are no commits since
      # impl_base, so the scope is never carried without them.
      - target: review
        when:
          gates.scrutiny_carried.exit_code: 0
      # The round is recorded and no seat is blocking: koto advances.
      - target: review
        when:
          gates.scrutiny_carried.exit_code: 1
          gates.scrutiny_verdict.exit_code: 0
          gates.scrutiny_recorded.exit_code: 0
          gates.has_commits.exit_code: 0
      - target: implementation
        when:
          gates.scrutiny_carried.exit_code: 1
          gates.scrutiny_verdict.exit_code: 1
          scrutiny_outcome: blocking_retry
          gates.scrutiny_recorded.exit_code: 0
      - target: done_blocked
        when:
          gates.scrutiny_carried.exit_code: 1
          gates.scrutiny_verdict.exit_code: 1
          scrutiny_outcome: blocking_escalate
        context_assignments:
          failure_reason: ${evidence.failure_reason}
      - target: done_blocked
        when:
          gates.scrutiny_carried.exit_code: 1
          gates.scrutiny_verdict.exit_code: 2
          scrutiny_outcome: blocking_escalate
        context_assignments:
          failure_reason: ${evidence.failure_reason}

  review:
    # The same seat decision as scrutiny's, for this panel, and the same
    # verdict gate: see the comments there. review_carried exit 0 advances
    # with no spawn. No decider batch is declared here: none of this panel's
    # questions has a contract that fits the budget, and a later one would go
    # on as scrutiny_decider did, with the same pending-answer directive.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh --plan review "{{SESSION_NAME}}"'
      fallback: >-
        koto could not decide what this round runs. Read the command's
        own output above: panel-scope.sh exits 64 when HEAD names no commit,
        65 when the ledger could not be updated, 66 when a context write
        failed, 127 when jq is missing, and 127 or 126 also when PLUGIN_ROOT
        does not reach the plugin. Run every seat of the panel
        as a full round and record it with panel-scope.sh --record as usual;
        with no scope, review_verdict reads the ledger's findings and every seat's verdict,
        and the review_carried gate reads exit 1, so the round routes on the
        verdict as any other.
    gates:
      review_carried:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh" --carried review "{{SESSION_NAME}}"'
      # Holds the passed and blocking_retry edges until the round's spawned
      # seats are recorded (panel-scope.sh --record): a skipped record leaves
      # a seat's previous verdict in the ledger, and it would be read as
      # current next round.
      review_recorded:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh" --recorded review "{{SESSION_NAME}}"'
      # The panel's pass, from the ledger (gate 6), as on scrutiny.
      review_verdict:
        type: command
        command: 'SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=review_verdict SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" "{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh" --verdict review "{{SESSION_NAME}}"'
        override_default:
          exit_code: 0
          error: ""
      # The level was checked against the facts at review_level_check, and
      # every passed route below routes on it. level_unchanged holds those
      # routes when REVIEW_LEVEL no longer matches the ledger's last level: a
      # hand rebind (`koto init --attach-live --var REVIEW_LEVEL=...`) made
      # while the run sits here would otherwise pick the route, skipping QA
      # with the ledger untouched. review-level.sh agree exits 0 when the two
      # match (both empty is the unset route) and 1 otherwise.
      level_unchanged:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/review-level.sh" agree "{{SESSION_NAME}}" "{{REVIEW_LEVEL}}"'
    accepts:
      review_outcome:
        type: enum
        values: [blocking_retry, blocking_escalate]
        description: >-
          Absent when the panel passes: koto advances on review_verdict.
          Submit a value only while review_verdict exits 1 (a seat is
          blocking), or blocking_escalate while it exits 2.
      failure_reason:
        type: string
        description: Reason for blocking escalation
    transitions:
      # Where a passed review goes depends on the review level: `standard`
      # stops before QA, `full` and an unset level (a session from an earlier
      # template) go on to it. `light` never reaches this state. A hand
      # rebind while the run sits here fails level_unchanged, so no passed
      # route matches and the state holds until review-level.sh set puts the
      # level back to the ledger's.
      #
      # Every seat kept its verdict: nothing to spawn, so koto advances.
      - target: verification
        when:
          gates.review_carried.exit_code: 0
          gates.level_unchanged.exit_code: 0
          vars.REVIEW_LEVEL: standard
          vars.VERIFICATION: local
      - target: verification_deferred
        when:
          gates.review_carried.exit_code: 0
          gates.level_unchanged.exit_code: 0
          vars.REVIEW_LEVEL: standard
          vars.VERIFICATION: hosted-ci
      - target: qa_validation
        when:
          gates.review_carried.exit_code: 0
          gates.level_unchanged.exit_code: 0
          vars.REVIEW_LEVEL: full
      - target: qa_validation
        when:
          gates.review_carried.exit_code: 0
          gates.level_unchanged.exit_code: 0
          vars.REVIEW_LEVEL:
            is_set: false
      # The round is recorded and no seat is blocking: koto advances.
      - target: verification
        when:
          gates.review_carried.exit_code: 1
          gates.review_verdict.exit_code: 0
          gates.review_recorded.exit_code: 0
          gates.level_unchanged.exit_code: 0
          vars.REVIEW_LEVEL: standard
          vars.VERIFICATION: local
      - target: verification_deferred
        when:
          gates.review_carried.exit_code: 1
          gates.review_verdict.exit_code: 0
          gates.review_recorded.exit_code: 0
          gates.level_unchanged.exit_code: 0
          vars.REVIEW_LEVEL: standard
          vars.VERIFICATION: hosted-ci
      - target: qa_validation
        when:
          gates.review_carried.exit_code: 1
          gates.review_verdict.exit_code: 0
          gates.review_recorded.exit_code: 0
          gates.level_unchanged.exit_code: 0
          vars.REVIEW_LEVEL: full
      - target: qa_validation
        when:
          gates.review_carried.exit_code: 1
          gates.review_verdict.exit_code: 0
          gates.review_recorded.exit_code: 0
          gates.level_unchanged.exit_code: 0
          vars.REVIEW_LEVEL:
            is_set: false
      - target: implementation
        when:
          gates.review_carried.exit_code: 1
          gates.review_verdict.exit_code: 1
          review_outcome: blocking_retry
          gates.review_recorded.exit_code: 0
      - target: done_blocked
        when:
          gates.review_carried.exit_code: 1
          gates.review_verdict.exit_code: 1
          review_outcome: blocking_escalate
        context_assignments:
          failure_reason: ${evidence.failure_reason}
      - target: done_blocked
        when:
          gates.review_carried.exit_code: 1
          gates.review_verdict.exit_code: 2
          review_outcome: blocking_escalate
        context_assignments:
          failure_reason: ${evidence.failure_reason}

  qa_validation:
    # The same seat decision as scrutiny's, for this panel, and the same
    # verdict gate: see the comments there. qa_carried exit 0 advances with
    # no spawn. No decider batch is declared here: the tester runs the
    # change, which no closed question over a slice can do.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh --plan qa "{{SESSION_NAME}}"'
      fallback: >-
        koto could not decide what this round runs. Read the command's
        own output above: panel-scope.sh exits 64 when HEAD names no commit,
        65 when the ledger could not be updated, 66 when a context write
        failed, 127 when jq is missing, and 127 or 126 also when PLUGIN_ROOT
        does not reach the plugin. Run every seat of the panel
        as a full round and record it with panel-scope.sh --record as usual;
        with no scope, qa_verdict reads the ledger's findings and every seat's verdict, and
        the qa_carried gate reads exit 1, so the round routes on the verdict
        as any other.
    gates:
      qa_carried:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh" --carried qa "{{SESSION_NAME}}"'
      # Holds the passed and blocking_retry edges until the round's spawned
      # seats are recorded (panel-scope.sh --record): a skipped record leaves
      # a seat's previous verdict in the ledger, and it would be read as
      # current next round.
      qa_recorded:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh" --recorded qa "{{SESSION_NAME}}"'
      # The panel's pass, from the ledger (gate 6), as on scrutiny.
      qa_verdict:
        type: command
        command: 'SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=qa_verdict SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" "{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh" --verdict qa "{{SESSION_NAME}}"'
        override_default:
          exit_code: 0
          error: ""
    accepts:
      qa_outcome:
        type: enum
        values: [blocking_retry, blocking_escalate]
        description: >-
          Absent when the panel passes: koto advances on qa_verdict. Submit a
          value only while qa_verdict exits 1 (a scenario failed), or
          blocking_escalate while it exits 2.
      failure_reason:
        type: string
        description: Reason for blocking escalation
    transitions:
      # Every seat kept its verdict: nothing to spawn, so koto advances.
      - target: verification
        when:
          gates.qa_carried.exit_code: 0
          vars.VERIFICATION: local
      - target: verification_deferred
        when:
          gates.qa_carried.exit_code: 0
          vars.VERIFICATION: hosted-ci
      # The round is recorded and the tester is not blocking: koto advances.
      - target: verification
        when:
          gates.qa_carried.exit_code: 1
          gates.qa_verdict.exit_code: 0
          gates.qa_recorded.exit_code: 0
          vars.VERIFICATION: local
      - target: verification_deferred
        when:
          gates.qa_carried.exit_code: 1
          gates.qa_verdict.exit_code: 0
          gates.qa_recorded.exit_code: 0
          vars.VERIFICATION: hosted-ci
      - target: implementation
        when:
          gates.qa_carried.exit_code: 1
          gates.qa_verdict.exit_code: 1
          qa_outcome: blocking_retry
          gates.qa_recorded.exit_code: 0
      - target: done_blocked
        when:
          gates.qa_carried.exit_code: 1
          gates.qa_verdict.exit_code: 1
          qa_outcome: blocking_escalate
        context_assignments:
          failure_reason: ${evidence.failure_reason}
      - target: done_blocked
        when:
          gates.qa_carried.exit_code: 1
          gates.qa_verdict.exit_code: 2
          qa_outcome: blocking_escalate
        context_assignments:
          failure_reason: ${evidence.failure_reason}

  light_review:
    # The `light` review level's one panel: a single reviewer seat, in place of
    # scrutiny, review and QA. It is a fourth panel to panel-scope.sh, so its
    # retries are planned from the findings ledger exactly like the other
    # panels': see the comment on scrutiny. light_carried exit 0 advances with no spawn,
    # and the verdict gate is scrutiny's too. No decider batch is declared
    # here: a `light` run never reaches scrutiny, so its decisions go
    # ungraded.
    #
    # The verdict route also carries scrutiny's has_commits gate: at `light`
    # scrutiny never runs, and that gate is what stops a code run with no
    # commits since impl_base from reaching verification. The carried route
    # can't repeat it (a carried scope with it failing would match no edge);
    # panel-scope.sh --plan keeps no seat while there are no commits, so the
    # scope is never carried without them.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh --plan light "{{SESSION_NAME}}"'
      fallback: >-
        koto could not decide whether the light seat runs this round. Read the
        command's own output above: panel-scope.sh exits 64 when HEAD names no
        commit, 65 when the ledger could not be updated, 66 when a context
        write failed, 127 when jq is missing, and 127 or 126 also when
        PLUGIN_ROOT does not reach the plugin. Run the seat as a full round
        and record it with panel-scope.sh --record as usual; with no scope,
        light_verdict reads the seat's recorded verdict, and the
        light_carried gate reads exit 1, so the round routes on the verdict
        as any other.
    gates:
      light_carried:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh" --carried light "{{SESSION_NAME}}"'
      # Holds the passed and blocking_retry edges until the round's seat is
      # recorded (panel-scope.sh --record), as on the other panels.
      light_recorded:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh" --recorded light "{{SESSION_NAME}}"'
      # The panel's pass, from the ledger (gate 6), as on scrutiny.
      light_verdict:
        type: command
        command: 'SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=light_verdict SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" "{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-scope.sh" --verdict light "{{SESSION_NAME}}"'
        override_default:
          exit_code: 0
          error: ""
      # Identical to scrutiny's copy.
      has_commits:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/has-commits.sh" "{{SESSION_NAME}}"'
      # Identical to review's copy: holds the passed routes when REVIEW_LEVEL
      # no longer matches the ledger's last level.
      level_unchanged:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/review-level.sh" agree "{{SESSION_NAME}}" "{{REVIEW_LEVEL}}"'
    accepts:
      light_outcome:
        type: enum
        values: [blocking_retry, blocking_escalate]
        description: >-
          Absent when the panel passes: koto advances on light_verdict. Submit
          a value only while light_verdict exits 1 (the seat is blocking), or
          blocking_escalate while it exits 2.
      failure_reason:
        type: string
        description: Reason for blocking escalation
    transitions:
      # The seat kept its verdict: nothing to spawn, so koto advances.
      - target: verification
        when:
          gates.light_carried.exit_code: 0
          gates.level_unchanged.exit_code: 0
          vars.VERIFICATION: local
      - target: verification_deferred
        when:
          gates.light_carried.exit_code: 0
          gates.level_unchanged.exit_code: 0
          vars.VERIFICATION: hosted-ci
      # The round is recorded and the seat is not blocking: koto advances.
      - target: verification
        when:
          gates.light_carried.exit_code: 1
          gates.light_verdict.exit_code: 0
          gates.light_recorded.exit_code: 0
          gates.has_commits.exit_code: 0
          gates.level_unchanged.exit_code: 0
          vars.VERIFICATION: local
      - target: verification_deferred
        when:
          gates.light_carried.exit_code: 1
          gates.light_verdict.exit_code: 0
          gates.light_recorded.exit_code: 0
          gates.has_commits.exit_code: 0
          gates.level_unchanged.exit_code: 0
          vars.VERIFICATION: hosted-ci
      - target: implementation
        when:
          gates.light_carried.exit_code: 1
          gates.light_verdict.exit_code: 1
          light_outcome: blocking_retry
          gates.light_recorded.exit_code: 0
      - target: done_blocked
        when:
          gates.light_carried.exit_code: 1
          gates.light_verdict.exit_code: 1
          light_outcome: blocking_escalate
        context_assignments:
          failure_reason: ${evidence.failure_reason}
      - target: done_blocked
        when:
          gates.light_carried.exit_code: 1
          gates.light_verdict.exit_code: 2
          light_outcome: blocking_escalate
        context_assignments:
          failure_reason: ${evidence.failure_reason}

  verification:
    # The definition-of-done gate, run by koto rather than reported by the
    # agent (DESIGN-output-gates Decision 2). koto gives one command 30
    # seconds and a test suite takes minutes, so the work is split in two:
    #
    #   default_action  run-verification.sh --start. Returns within a second:
    #                   either a result for this head is already on disk, or
    #                   it starts a detached, bounded supervisor that runs the
    #                   verification map's commands (read at the merge-base)
    #                   and writes the result. It never calls koto.
    #   verification_verdict  check-verification.sh --verdict, a poll: gate.
    #                   Exit 75 while there is no result for this head, which
    #                   koto reports as a temporal, non-actionable wait and
    #                   re-runs every 15 seconds for up to 480 seconds of one
    #                   tick, under what an agent's tool call can wait; the
    #                   agent ticks again and the wait goes on, up to two hours.
    #
    # Both scripts take the same arguments (no --base-ref), so they agree on
    # the head, the merge-base and the result file. The test -x guards turn an
    # empty or wrong PLUGIN_ROOT into exit 2 rather than 127: the action then
    # stops the tick with its fallback, and the gate holds.
    #
    # The verdict routes:
    #   0  every selected command passed          pass_counting
    #   1  a command failed                       implementation
    #   3  no map, a map that does not parse, or one that selects nothing
    #                                             done_blocked (fail closed)
    #   4  a command needs a person, timed out, grew past max_procs, could
    #      not start, or the tree was dirty       done_blocked
    #   75 no result yet                          waits
    #   2  the result could not be read           holds
    # Each violation exit prints `::koto-finding::` lines whose rule_id is a
    # verification/ rule from references/rule-registry.json, so the event log names the cause.
    #
    # The one evidence left is `verification_status: blocked`, for a run that
    # can't settle: a launcher that can't start (the wait is then pending and,
    # past its deadline, timed out, both exit 75), a result that can't be
    # read (2), or a gate run koto killed or could not start (-1). Each edge names the gate value, which is what lets koto prove
    # it exclusive of the routed ones.
    #
    # How koto 0.15.0 reports the gate when it is not one of the exits above:
    #   - Still pending at the poll deadline (timeout_secs): the gate's outcome
    #     becomes timed_out, but its routable output is unchanged, so
    #     gates.verification_verdict.exit_code is still 75 (koto's
    #     src/engine/poll.rs leaves the output as the last run left it). The
    #     75 + blocked edge is the way out, as for a launcher that never starts.
    #   - One run killed by the gate's own per-run timeout, or a run koto
    #     could not spawn: exit_code -1 with a failure_kind. That is not the
    #     pending code, so koto does not wait on it, and no settled edge names
    #     it: the -1 + blocked edge below is its way out, so the state can't
    #     trap the run.
    #
    # The return to implementation on exit 1 used to be the agent's, which
    # cleared the panel and summary keys first. koto now takes the edge
    # itself, so those keys are implementation's clear_on_entry.
    #
    # Only a VERIFICATION=local run enters this state. A hosted-ci run goes to
    # verification_deferred on every edge that would lead here, so the action
    # below never runs for it.
    default_action:
      command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/run-verification.sh" || exit 2; "{{PLUGIN_ROOT}}/skills/work-on/scripts/run-verification.sh" --start --session "{{SESSION_NAME}}"'
      fallback: >-
        koto could not start the verification run. Read the command's own
        output above: run-verification.sh exits 2 when HEAD or the merge-base
        with the default branch does not resolve, the state directory can't be
        created, or a tool it needs (git, jq) is missing, and the test -x guard
        exits 2 when PLUGIN_ROOT does not reach the plugin. Fix the cause and
        tick again -- the launcher re-runs on entry and on every tick until it
        succeeds. If it can't be fixed, submit `verification_status: blocked`
        with the reason in `detail`.
    gates:
      verification_verdict:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-verification.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=verification_verdict SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-verification.sh" --verdict --session "{{SESSION_NAME}}"'
        poll:
          interval_secs: 15
          timeout_secs: 7200
          hold_secs: 480
    accepts:
      verification_status:
        type: enum
        values: [blocked]
        description: >-
          Absent on every settled path: koto routes on the verdict. Submit
          `blocked` only when the run can't settle -- the launcher can't
          start, the wait timed out, the result can't be read, or koto
          could not run the check (exit -1).
      detail:
        type: string
        description: Why verification could not run or be read.
    transitions:
      - target: pass_counting
        when:
          gates.verification_verdict.exit_code: 0
      - target: implementation
        when:
          gates.verification_verdict.exit_code: 1
      - target: done_blocked
        when:
          gates.verification_verdict.exit_code: 3
        context_assignments:
          failure_reason: "verification: no verification map at the merge-base, a map that does not parse, or a map that selects nothing for this change (fail closed). The finding names which; the result is in context as verification_results.json."
      - target: done_blocked
        when:
          gates.verification_verdict.exit_code: 4
        context_assignments:
          failure_reason: "verification: a command needs a person, timed out, grew past max_procs, could not start, or the tree had uncommitted changes to tracked files (fail closed). The finding names which; the result is in context as verification_results.json."
      - target: done_blocked
        when:
          gates.verification_verdict.exit_code: 75
          verification_status: blocked
        context_assignments:
          failure_reason: "verification blocked: ${evidence.detail}"
      - target: done_blocked
        when:
          gates.verification_verdict.exit_code: 2
          verification_status: blocked
        context_assignments:
          failure_reason: "verification blocked: ${evidence.detail}"
      - target: done_blocked
        when:
          gates.verification_verdict.exit_code: -1
          verification_status: blocked
        context_assignments:
          failure_reason: "verification blocked: ${evidence.detail}"

  verification_deferred:
    # Where a VERIFICATION=hosted-ci run goes instead of verification (#1012).
    # Every edge into verification has a twin here, split on the variable's
    # value, so a `local` run (the default) takes exactly the routes it took
    # before the twins existed.
    #
    # The split sits on the edges, not inside verification, because koto runs
    # a state's default_action before its skip_if and its transitions: once a
    # run enters verification, run-verification.sh --start has already
    # launched the map, in a detached supervisor or in line. Never entering it
    # is the only way the map never starts. This state has no action and no
    # gates, so nothing here runs a command.
    #
    # The deferral is explicit and leaves three records: VERIFICATION and its
    # reason are fixed at init (neither is rebindable), the edge in records
    # `vars_matched: VERIFICATION=hosted-ci` on its transition event, and the
    # edge out writes the reason to context as verification_deferral. It is
    # never silent either: in a repository that opts in to workflow content
    # (scripts/pr-workflow-content.sh), pr_creation's
    # verification_deferral_recorded gate holds the created edge until the pull
    # request body says local verification did not run, gives this reason, and
    # names hosted CI as the build of record; by default the context key is
    # the record and the body says in plain terms that hosted CI verified the
    # change. ci_monitor then requires that CI green as always.
    #
    # A hosted-ci run with no reason stops at done_blocked. It does not fall
    # back to running the map, which is what the run chose not to do, and it
    # does not go on, which would be a deferral nobody explained. The reason
    # can't be added to a live session, since the variable is fixed at init.
    #
    # A deferral counts as a passing check here, so the run goes through
    # pass_counting like a local pass does.
    transitions:
      - target: pass_counting
        when:
          vars.VERIFICATION_DEFERRAL_REASON:
            is_set: true
        context_assignments:
          verification_deferral: "{{VERIFICATION_DEFERRAL_REASON}}"
      - target: done_blocked
        when:
          vars.VERIFICATION_DEFERRAL_REASON:
            is_set: false
        context_assignments:
          failure_reason: "verification_deferred: VERIFICATION=hosted-ci was chosen without VERIFICATION_DEFERRAL_REASON. A deferral to hosted CI needs a stated reason, and the variable is fixed at init: start the run again with both, or without the deferral."

  pass_counting:
    # Entered only after a check passed: verification's exit 0, or a
    # deferral to hosted CI. A pass is counted here before the run finalizes
    # (../references/red-first.md), and only when both gates pass:
    #
    #   fix_green      red-first.sh check-green. Passes for a unit that isn't a
    #                  fix; a fix needs a green, the red's command re-run at
    #                  HEAD with exit 0, which the agent records with
    #                  red-first.sh green, or an observation pair a live
    #                  acceptance covers. Every hold prints finding
    #                  red-first/no-green.
    #   tests_counted  test-change.sh status. Classifies the test files the
    #                  unit's committed diff touched since impl_base: an edited
    #                  test (a line removed, deleted, renamed with a change) or
    #                  an observation holds the unit until the session ledger
    #                  test_change_ledger.jsonl shows a live acceptance by
    #                  someone other than the run, under the interim rule in
    #                  scripts/lib/acceptance-rule.sh. Exit 1 holds (finding
    #                  test-change/held), 2 can't decide, 3 means one set of
    #                  paths was declined three times.
    #
    # A held run in a repository that isn't person-required mints a seat
    # (test-change.sh seat) and commissions it with the brief the script
    # prints; the seat accepts or declines under its minted identity, and the
    # next tick re-reads the ledger. In a repository that declares
    # `## Test Change Acceptance: person` no seat can accept: the run stops
    # here, status prints the command a person runs at a terminal, and the
    # resumed run's next tick finds the person's acceptance.
    #
    # A green that failed, or a decline, sends the run back to implementation,
    # whose clear_on_entry drops the panels' stale results; check-green
    # compares the green's head with HEAD, and status compares every
    # acceptance's digests with HEAD's, so a later commit holds again. The
    # third decline of one path set goes to done_blocked with no evidence.
    gates:
      fix_green:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/red-first.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=fix_green "{{PLUGIN_ROOT}}/skills/work-on/scripts/red-first.sh" check-green "{{SESSION_NAME}}"'
      tests_counted:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/test-change.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=tests_counted "{{PLUGIN_ROOT}}/skills/work-on/scripts/test-change.sh" status "{{SESSION_NAME}}"'
    accepts:
      counting_status:
        type: enum
        values: [green_failed, declined, blocked]
        description: >-
          Absent on the passing path: koto advances once fix_green and
          tests_counted pass. `green_failed` returns to implementation after a
          green that exited non-zero; `declined` returns to implementation
          after the acceptance seat declined a test edit; `blocked` stops the
          run when a hold can't be cleared.
      detail:
        type: string
        description: Why the run can't be counted.
    transitions:
      - target: finalization
        when:
          gates.fix_green.exit_code: 0
          gates.tests_counted.exit_code: 0
      - target: done_blocked
        when:
          gates.tests_counted.exit_code: 3
        context_assignments:
          failure_reason: "pass_counting: the acceptance seats declined the same test edits three times. The ledger is in context as test_change_ledger.jsonl."
      - target: implementation
        when:
          gates.tests_counted.exit_code: 0
          gates.fix_green.exit_code: 1
          counting_status: green_failed
      - target: implementation
        when:
          gates.tests_counted.exit_code: 1
          gates.fix_green.exit_code: 1
          counting_status: green_failed
      - target: implementation
        when:
          gates.tests_counted.exit_code: 1
          counting_status: declined
      - target: done_blocked
        when:
          gates.tests_counted.exit_code: 0
          gates.fix_green.exit_code: 1
          counting_status: blocked
        context_assignments:
          failure_reason: "pass_counting blocked: ${evidence.detail}"
      - target: done_blocked
        when:
          gates.tests_counted.exit_code: 0
          gates.fix_green.exit_code: 2
          counting_status: blocked
        context_assignments:
          failure_reason: "pass_counting blocked: ${evidence.detail}"
      - target: done_blocked
        when:
          gates.tests_counted.exit_code: 1
          counting_status: blocked
        context_assignments:
          failure_reason: "pass_counting blocked: ${evidence.detail}"
      - target: done_blocked
        when:
          gates.tests_counted.exit_code: 2
          counting_status: blocked
        context_assignments:
          failure_reason: "pass_counting blocked: ${evidence.detail}"

  finalization:
    gates:
      summary_exists:
        type: context-exists
        key: summary.md
      # The checks pre_pr_evidence makes, made again here where summary.md and
      # pre_pr.md are written. They gate the advancing edge only and no edge
      # routes their failure anywhere, so a malformed artifact, or a referent
      # that names nothing, holds the run in this state with the failing gate
      # named, and the agent fixes it in place. At pre_pr_evidence the same
      # failure ends the run at done_blocked, which has to be re-entered to fix
      # one artifact -- the gates there stay as the backstop, and these keep a
      # run from reaching them with a record it could still have fixed in place.
      # The gate definitions must stay identical to
      # pre_pr_evidence's; finalization-shape_test.sh checks that they do.
      #
      # The two referent gates run check-pre-pr-referents.sh, which requires
      # cleanup_commit to name a commit that is HEAD or an ancestor of it, and a
      # design_diagram path to name a file in HEAD's tree. A pattern alone passed
      # any hex string (shirabe#422). The script answers 0 or 1 only, and the
      # test -x guard turns an empty or wrong PLUGIN_ROOT into 1 rather than
      # 127. Here any failure holds; the contract matters at pre_pr_evidence,
      # whose ladder names exactly 0 and 1, so a gate that cannot run stops the
      # run at done_blocked instead of matching no edge. koto
      # discards a failed gate's output, so the directive tells the agent to
      # run the script itself for the reason.
      summary_shape:
        type: context-matches
        key: summary.md
        pattern: "## Changes Made"
      cleanup_referent:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" || exit 1; "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" --cleanup "{{SESSION_NAME}}"'
      diagram_referent:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" || exit 1; "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" --diagram "{{SESSION_NAME}}"'
      # Every non-merge commit this run made (impl_base..HEAD), not only the
      # tip: a Conventional Commits subject and no AI-attribution trailer.
      # check-branch-output.sh exits 0 pass, 1 a violation (one
      # ::koto-finding:: line each, rule commit/conventional-subject or
      # commit/no-ai-trailer), 2 could not decide; the test -x guard makes an
      # unusable PLUGIN_ROOT a 2. Here 1 and 2 both hold, like the checks
      # above; pre_pr_evidence runs the same gate as its backstop.
      commit_convention:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-branch-output.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=commit_convention SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-branch-output.sh" --commits --session "{{SESSION_NAME}}"'
    accepts:
      finalization_status:
        type: enum
        # ready_for_pr: every acceptance criterion is met. Reaching this state at all
        #   means the verification_verdict gate exited 0 and pass_counting counted
        #   the pass (verification goes to pass_counting only on that exit, and
        #   pass_counting to finalization only on fix_green 0), so ready_for_pr is
        #   backed by run verification evidence -- there is no clean finalization without it.
        #   The one other way in is verification_deferred, for a run that chose
        #   VERIFICATION=hosted-ci with a reason: its evidence is the pull
        #   request's hosted CI, which pr_creation makes the body record and
        #   ci_monitor requires green.
        # deferral_requested: an acceptance criterion is unmet/deferred. There is NO clean
        #   self-reported deferral terminal here (the old deferred_items_noted loophole is
        #   removed). This routes to the blocking deferral_approval human gate instead.
        # issues_found: defects need more implementation; return to implementation.
        # check_unsatisfiable: the named exit (DESIGN-validate-and-return.md) for a
        #   commit rule the run can't satisfy; accepted only while commit_convention
        #   fails on a rule, and it stops the run at done_blocked, never past the gate.
        values: [ready_for_pr, deferral_requested, issues_found, check_unsatisfiable]
        required: true
      check_exit_reason:
        type: string
        description: >-
          With check_unsatisfiable: one sentence saying why the failing check can't
          be satisfied. It becomes part of failure_reason.
    transitions:
      - target: implementation
        when:
          finalization_status: issues_found
      - target: check_exit
        when:
          finalization_status: check_unsatisfiable
          gates.commit_convention.exit_code: 1
        context_assignments:
          failure_reason: "check_exit at finalization: commit_convention could not be satisfied: ${evidence.check_exit_reason}"
      # ready_for_pr requires the summary artifact AND (implicitly) that verification
      # passed, since finalization is only reachable through pass_counting, after
      # verification_verdict exit 0 or a deferral to hosted CI with a reason
      # (verification_deferred).
      # It also requires both artifacts to pass the checks pre_pr_evidence makes.
      - target: pre_pr_evidence
        when:
          finalization_status: ready_for_pr
          gates.summary_exists.exists: true
          gates.summary_shape.matches: true
          gates.cleanup_referent.exit_code: 0
          gates.diagram_referent.exit_code: 0
          gates.commit_convention.exit_code: 0
      # deferral must be a surfaced human decision, never a clean self-report (Decision E).
      - target: deferral_approval
        when:
          finalization_status: deferral_requested

  deferral_approval:
    # Blocking human-approval gate for a deferred acceptance criterion (Decision E,
    # PRD R4/R5). The agent halts here and surfaces the unmet criterion to the human.
    # The human's decision is the evidence:
    #   approved -> record the deferral via `koto decisions record`, then proceed to PR
    #               with the deferral recorded in the audit trail (and PR body).
    #   rejected -> the issue is not done; route to the non-clean done_blocked terminal.
    gates:
      summary_exists:
        type: context-exists
        key: summary.md
      # The same early checks as finalization, for the same reason: this edge
      # also leads to pre_pr_evidence, and a failure there is a terminal. The
      # rejected edge stays ungated.
      summary_shape:
        type: context-matches
        key: summary.md
        pattern: "## Changes Made"
      cleanup_referent:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" || exit 1; "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" --cleanup "{{SESSION_NAME}}"'
      diagram_referent:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" || exit 1; "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" --diagram "{{SESSION_NAME}}"'
      # The commit walk finalization runs, on the approved edge for the same
      # reason as the checks above.
      commit_convention:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-branch-output.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=commit_convention SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-branch-output.sh" --commits --session "{{SESSION_NAME}}"'
    accepts:
      approval_decision:
        type: enum
        values: [approved, rejected]
        required: true
      deferral_detail:
        type: string
        description: >
          The unmet acceptance criterion and the human's rationale. On approved, this is
          the deferral recorded via `koto decisions record`; the PR body says in plain
          terms what is left undone.
    transitions:
      - target: pre_pr_evidence
        when:
          approval_decision: approved
          gates.summary_exists.exists: true
          gates.summary_shape.matches: true
          gates.cleanup_referent.exit_code: 0
          gates.diagram_referent.exit_code: 0
          gates.commit_convention.exit_code: 0
      - target: done_blocked
        when:
          approval_decision: rejected
        context_assignments:
          failure_reason: "deferral rejected by human: ${evidence.deferral_detail}"

  pre_pr_evidence:
    # The finishing obligations that are decidable BEFORE a pull request exists.
    # The ones that need a pull request to query -- the closing keyword, merge
    # cleanliness -- live on pr_creation and ci_monitor instead, which is why
    # this state is narrow rather than a single batching state for everything.
    #
    # Why gates rather than four required string fields: koto's evidence schema
    # has type, required, values and description, and nothing that constrains a
    # string's shape. A `type: string` field is satisfied by "done", which makes
    # an obligation unenforced in substance while looking enforced in the record
    # (PRD R7a). So the judgment calls are enums, which are closed sets a
    # placeholder cannot satisfy, and the concrete referents live in a context
    # artifact whose referents a gate checks exist.
    gates:
      # The summary exists by the time this state is reached -- both edges into
      # it require it -- so this checks its SHAPE, not its presence. Both edges
      # also check this shape and the two referents below, holding in place on a
      # failure, so here the three are the backstop.
      summary_shape:
        type: context-matches
        key: summary.md
        pattern: "## Changes Made"
      # Conventional Commits on every commit this run made, and no
      # AI-attribution trailer on any of them. Observable from git, so it is
      # gated rather than asked for (PRD R6). The same gate finalization and
      # deferral_approval hold on; here, as the backstop, its 1 (a violation)
      # and its 2 (could not decide) both end the run.
      commit_convention:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-branch-output.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=commit_convention SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-branch-output.sh" --commits --session "{{SESSION_NAME}}"'
      # The concrete referents, in an artifact the run writes, checked for
      # existence and not only for shape (check-pre-pr-referents.sh):
      # "cleanup_commit: done" is not a sha, a sha that names no commit or a
      # commit outside HEAD's history is not the reviewed commit, "design_diagram: yes"
      # is neither a path nor the explicit not-applicable form with a reason
      # after it, and a docs/ path that is not a file in HEAD's tree names no
      # diagram. Exit 0 or 1 only, which the ladder below routes on.
      cleanup_referent:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" || exit 1; "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" --cleanup "{{SESSION_NAME}}"'
      diagram_referent:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" || exit 1; "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" --diagram "{{SESSION_NAME}}"'
    accepts:
      pre_pr_status:
        type: enum
        values: [recorded, blocked]
        required: true
      cleanup_done:
        type: enum
        values: [removed, none_found]
        required: true
        description: >-
          Whether the cleanup pass removed anything. An enum rather than prose,
          because a free-text field here is satisfied by "cleaned up" and the
          obligation is then unenforced in substance. The commit it was judged
          against goes in pre_pr.md, where a gate checks it is HEAD or an
          ancestor of it.
      design_diagram:
        type: enum
        values: [updated, not_applicable]
        required: true
        description: >-
          PRD R9's first limb: the diagram obligation is brought within one hop
          of the template and given a field, rather than left two reference-hops
          away with a contract permitting a silent skip. The path updated, or the
          reason it does not apply, goes in pre_pr.md.
    transitions:
      # The ladder is ordered, and every edge names the field the edge above it
      # named, because koto refuses transitions to one target it cannot prove
      # exclusive. Each rung is a distinct cause, which is what keeps them
      # distinguishable in the record.
      - target: pr_precheck
        when:
          pre_pr_status: recorded
          gates.summary_shape.matches: true
          gates.commit_convention.exit_code: 0
          gates.cleanup_referent.exit_code: 0
          gates.diagram_referent.exit_code: 0
      - target: done_blocked
        when:
          pre_pr_status: recorded
          gates.summary_shape.matches: false
        context_assignments:
          failure_reason: "pre_pr_evidence: the summary does not have the shape the finalization step requires (no '## Changes Made' section)."
      - target: done_blocked
        when:
          pre_pr_status: recorded
          gates.summary_shape.matches: true
          gates.commit_convention.exit_code: 1
        context_assignments:
          failure_reason: "pre_pr_evidence: a commit this run made has a subject that is not a Conventional Commits subject, or carries an AI-attribution trailer. The gate's findings name the commit and the rule."
      - target: done_blocked
        when:
          pre_pr_status: recorded
          gates.summary_shape.matches: true
          gates.commit_convention.exit_code: 2
        context_assignments:
          failure_reason: "pre_pr_evidence: the commit check could not decide (impl_base unreadable, a range that does not resolve, or check-branch-output.sh unreachable through PLUGIN_ROOT). Run check-branch-output.sh --commits --session <session> for the reason."
      - target: done_blocked
        when:
          pre_pr_status: recorded
          gates.summary_shape.matches: true
          gates.commit_convention.exit_code: 0
          gates.cleanup_referent.exit_code: 1
        context_assignments:
          failure_reason: "pre_pr_evidence: pre_pr.md does not record a cleanup_commit that names HEAD or an ancestor of it, or the check could not run. A word like 'done', or a sha that names no commit, is not a referent: name the commit whose diff was reviewed. Run check-pre-pr-referents.sh --cleanup for the reason."
      - target: done_blocked
        when:
          pre_pr_status: recorded
          gates.summary_shape.matches: true
          gates.commit_convention.exit_code: 0
          gates.cleanup_referent.exit_code: 0
          gates.diagram_referent.exit_code: 1
        context_assignments:
          failure_reason: "pre_pr_evidence: pre_pr.md does not record a design_diagram as a docs/ path that is a file in HEAD's tree, or as 'not-applicable: <reason>', or the check could not run. Run check-pre-pr-referents.sh --diagram for the reason."
      - target: done_blocked
        when:
          pre_pr_status: blocked
        context_assignments:
          failure_reason: "pre_pr_evidence: the run could not satisfy a pre-PR obligation and stopped rather than opening a pull request."

  pr_precheck:
    # The single edge into pr_creation, so the branch is read once here instead
    # of being recovered by command substitution in the prose of the state that
    # opens the pull request. Both predecessors -- finalization and
    # deferral_approval -- route through this state, which is also what makes
    # {{BRANCH}} safe to read in pr_creation and ci_monitor: every path into
    # them passes through this one.
    #
    # The gate is the template's only structural guarantee that a pull request
    # is not opened from the default branch, at the point where opening one
    # happens. `implementation` checks the same thing earlier, but a task-typed
    # issue reaches finalization through verification without re-checking, and
    # nothing re-checks after a rewind.
    #
    # The name differs from `on_feature_branch` deliberately.
    # scripts/validate-template-mermaid.sh check 4 requires a gate name shared
    # across templates to carry an identical command, and reusing a name inside
    # one template for a check with a different job is what that check exists to
    # notice.
    default_action:
      command: git rev-parse --abbrev-ref HEAD
      capture_stdout_as: BRANCH
      fallback: >-
        koto could not read the branch name. Read the command's own output
        above, then run `git rev-parse --abbrev-ref HEAD` yourself and carry on
        with what it prints. Check out the feature branch this work belongs on
        and tick again -- the read re-runs on entry. Submit
        `precheck_status: blocked` with `detail` only if you cannot.
    gates:
      on_feature_branch_pr:
        type: command
        command: "test \"$(git rev-parse --abbrev-ref HEAD)\" != \"main\""
      # What the branch carries, checked before a pull request shows it to
      # anyone. It runs check-branch-output.sh (0 pass, 1 a violation with a
      # ::koto-finding:: line each, 2 could not decide), and holds on 1 or 2:
      # neither pull request edge below fires until it passes.
      #
      # On /execute's shared branch the child opens no pull request of its
      # own (pr_status: shared), so it passes at once; /execute checks the
      # shared branch once, before it finalizes the pull request it owns.
      #
      # branch_docs_visibility: the docs this run changed, through shirabe
      # validate at the repository's declared visibility, counting only the
      # visibility rules (docs/private-only-type, docs/visibility-vision-sections,
      # docs/visibility-strategy-sections).
      branch_docs_visibility:
        type: command
        command: 'test -n "{{SHARED_BRANCH}}" || { test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-branch-output.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=branch_docs_visibility SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-branch-output.sh" --docs-visibility --session "{{SESSION_NAME}}"; }'
      # The pass counted at pass_counting, counted again before a pull
      # request shows it (../references/red-first.md): test-change.sh status
      # re-reads the committed diff, so a commit made after counting that
      # edits a test, or changes an accepted one, holds here. Exit 1 holds;
      # `precheck_status: recount` sends the run back to pass_counting,
      # where the acceptance is given. Every pull request edge needs 0.
      tests_still_counted:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/test-change.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=tests_still_counted "{{PLUGIN_ROOT}}/skills/work-on/scripts/test-change.sh" status "{{SESSION_NAME}}"'
    accepts:
      precheck_status:
        type: enum
        values: [override, blocked, check_unsatisfiable, recount]
        description: >-
          Absent on the passing path. The state advances with no evidence when
          the gates pass, so the agent never sees it. check_unsatisfiable is the
          named exit for a documents rule branch_docs_visibility keeps failing on.
          recount returns the run to pass_counting while tests_still_counted
          holds.
      detail:
        type: string
        description: Why the branch could not be settled.
      check_exit_reason:
        type: string
        description: >-
          With check_unsatisfiable: one sentence saying why the failing check can't
          be satisfied. It becomes part of failure_reason.
    transitions:
      - target: check_exit
        when:
          precheck_status: check_unsatisfiable
          gates.branch_docs_visibility.exit_code: 1
        context_assignments:
          failure_reason: "check_exit at pr_precheck: branch_docs_visibility could not be satisfied: ${evidence.check_exit_reason}"
      - target: pr_creation
        when:
          gates.on_feature_branch_pr.exit_code: 0
          gates.branch_docs_visibility.exit_code: 0
          gates.tests_still_counted.exit_code: 0
      - target: pr_creation
        when:
          gates.on_feature_branch_pr.exit_code: 1
          precheck_status: override
          gates.branch_docs_visibility.exit_code: 0
          gates.tests_still_counted.exit_code: 0
      - target: pass_counting
        when:
          precheck_status: recount
          gates.tests_still_counted.exit_code: 1
      # The decline limit (status exit 3) recounts too: pass_counting's own
      # exit-3 edge then ends the run at done_blocked with its reason.
      - target: pass_counting
        when:
          precheck_status: recount
          gates.tests_still_counted.exit_code: 3
      - target: done_blocked
        when:
          gates.on_feature_branch_pr.exit_code: 1
          precheck_status: blocked
        context_assignments:
          failure_reason: "pr_precheck blocked: ${evidence.detail}"

  pr_creation:
    gates:
      # Reads the pull request GitHub actually has, not the body the agent
      # believes it wrote. An issue that stays open after its fix merges is the
      # failure this prevents, and prose asking for the keyword cannot detect
      # its absence.
      #
      # Free-form work has no issue to close, so an empty ISSUE_NUMBER passes
      # rather than blocking: the obligation does not exist for that mode. The
      # trailing character class stops `#12` matching in `#123`. GitHub lets a
      # colon follow the keyword (`Fixes: #42`), so the expression takes one.
      #
      # An issue in another repository (ISSUE_REPO set) is closed only by
      # `Fixes owner/repo#N`, and `#N`, `GH-N`, this repository's
      # `owner/repo#N` or its issue URL there, the markdown link to it, or any
      # of them under the repository's old name, would close this repository's
      # issue N, so
      # check-closing-keyword.sh decides that case: it exits 0 closed, 1 not
      # closed, closing the wrong issue too, or unreadable (done_blocked, like
      # the expression here), 2 usage (holds), 3 a repository lookup it needed
      # failed or ran out of time (holds; tick again). With ISSUE_REPO empty the
      # expression runs and the script is never started.
      closing_keyword:
        type: command
        command: 'test -z "{{ISSUE_NUMBER}}" || if test -z "{{ISSUE_REPO}}"; then gh pr view --json body --jq .body | grep -qiE "(close[sd]?|fix(es|ed)?|resolve[sd]?):?[[:space:]]+#{{ISSUE_NUMBER}}([^0-9]|$)"; else test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-closing-keyword.sh" || exit 2; "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-closing-keyword.sh" --issue "{{ISSUE_NUMBER}}" --repo "{{ISSUE_REPO}}"; fi'
      # The pull request's title and body against the PR-body conformance
      # rules (references/pr-body-conformance.md, PB1 to PB4) and the banned
      # words of skills/writing-style/rules.yaml (PB5, pr-body/banned-word),
      # read from GitHub and checked by `shirabe validate --pr-body
      # --writing-style` with the plugin's own rules file. PB5 runs only at
      # this gate and /execute's; CI's PR-body check doesn't pass the flag.
      # check-pr-output.sh exits 0 conformant, 1 a violation (one
      # ::koto-finding:: line each, rules pr-body/*), 2 could not decide. It
      # gates the created edge only, so 1 and 2 hold here: fix the body with
      # `gh pr edit` and submit again. gh reads GH_TOKEN, which is on koto's
      # default pass-through list, so the template declares no pass_env.
      pr_body_conformant:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pr-output.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=pr_body_conformant SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pr-output.sh" --pr-body'
      # A run that deferred verification to hosted CI (VERIFICATION=hosted-ci,
      # verification_deferred) records the deferral where a reviewer reads it.
      # In a repository that doesn't opt in to workflow content
      # (scripts/pr-workflow-content.sh prints omit) the script exits 0 with no
      # GitHub read: verification_deferral in context is the record. Otherwise
      # check-pr-output.sh --deferral-record reads the pull request body from
      # GitHub and exits 0 when it says local verification did not run, has
      # the line `Reason: <reason>`, and names hosted CI as the build of record; 1
      # when any of the three is missing; 2 when it could not decide. It gates
      # the created edge only, so 1 and 2 hold here, like pr_body_conformant:
      # fix the body with `gh pr edit` and submit again. A local run never
      # starts the script: the test short-circuits to 0, with no process and
      # no GitHub read.
      verification_deferral_recorded:
        type: command
        command: 'test "{{VERIFICATION}}" != hosted-ci || { test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pr-output.sh" || exit 2; "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pr-output.sh" --deferral-record --reason "{{VERIFICATION_DEFERRAL_REASON}}"; }'
    accepts:
      pr_status:
        type: enum
        values: [created, shared, creation_failed_retry, creation_failed_escalate, check_unsatisfiable]
        required: true
      pr_url:
        type: string
        description: URL of the created pull request
      check_exit_reason:
        type: string
        description: >-
          With check_unsatisfiable: one sentence saying why the failing check can't
          be satisfied. It becomes part of failure_reason.
    transitions:
      # The named exit (DESIGN-validate-and-return.md): accepted only while
      # pr_body_conformant fails on a rule, and it stops the run at done_blocked
      # through check_exit, never past the gate.
      - target: check_exit
        when:
          pr_status: check_unsatisfiable
          gates.pr_body_conformant.exit_code: 1
        context_assignments:
          failure_reason: "check_exit at pr_creation: pr_body_conformant could not be satisfied: ${evidence.check_exit_reason}"
      # The run's one record of its pull request: done's and
      # done_already_complete's result maps read pr_url, and koto carries it
      # to a caller's leg as `pr` (#995). A `created` sent without pr_url
      # writes an empty value, which a caller reads as naming no pull request.
      - target: ci_monitor
        when:
          pr_status: created
          gates.closing_keyword.exit_code: 0
          gates.pr_body_conformant.exit_code: 0
          gates.verification_deferral_recorded.exit_code: 0
        context_assignments:
          pr_url: "${evidence.pr_url}"
      # A body without the keyword stops here. Fail-closed: the gate also exits
      # non-zero when it cannot read the pull request at all, and both readings
      # are named in the reason, because the exit code cannot tell them apart.
      - target: done_blocked
        when:
          pr_status: created
          gates.closing_keyword.exit_code: 1
        context_assignments:
          failure_reason: "pr_creation: the pull request body does not close issue {{ISSUE_REPO}}#{{ISSUE_NUMBER}} — add a closing keyword (Fixes {{ISSUE_REPO}}#{{ISSUE_NUMBER}}) so the issue closes when this merges. An issue in another repository also fails on a bare #{{ISSUE_NUMBER}}, which names this repository's issue. If the body does carry it, the gate could not read the pull request."
      # Only a run on /execute's shared branch opens no pull request of its
      # own, so the edge also needs SHARED_BRANCH set: a root run that
      # submitted `shared` would otherwise end at done past the closing-keyword
      # and PR-body gates. With it unset, `shared` matches no edge and the
      # state holds.
      - target: done
        when:
          pr_status: shared
          vars.SHARED_BRANCH:
            is_set: true
      - target: pr_creation
        when:
          pr_status: creation_failed_retry
      - target: done_blocked
        when:
          pr_status: creation_failed_escalate
        context_assignments:
          failure_reason: "pr_creation failed after retries: ${evidence.pr_url}"

  # The named exit's marker state. It passes straight through to done_blocked;
  # its name is what carries a run that took the exit to an exporter such as
  # Datadog (koto's state_entered event has it in koto.state, and no evidence
  # value is ever exported). failure_reason is set on the edge into this state,
  # so koto's W5 warning that this edge writes none is expected: an assignment
  # here would resolve to an empty value and overwrite it.
  check_exit:
    transitions:
      - target: done_blocked

  ci_monitor:
    gates:
      # Gate on `bucket`, not `state`: gh folds check states into
      # pass / skipping / fail / cancel / pending, and buckets any state it
      # doesn't recognize as `pending`, so this survives GitHub adding one.
      # `skipping` covers SKIPPED and NEUTRAL -- a repo with conditional jobs
      # skips checks on every PR, and the old state filter counted each one as
      # a failure (#244). Pending and cancel gate on purpose: a check that's
      # still running isn't green, and a cancelled one returned no verdict.
      # Don't rewrite this as "nothing is in the fail bucket" -- that would let
      # an all-queued PR report green.
      #
      # Zero checks is not green (#1018): the filter asks for at least one
      # check before it asks that none is outside pass and skipping. No checks
      # yet is the window just after a push, before Actions creates the check
      # suites, and a list that stays empty is CI that never ran. gh answers an
      # empty rollup with a `no checks reported` error and no JSON, which fails
      # the grep the same way; `length > 0` holds the line if a gh release
      # starts printing `[]` instead. The state holds as it does on a running
      # check, and the directive bounds the wait.
      #
      # One cancel is resolved: when the filter says not green,
      # ci-cancel-after-merge.sh passes the gate if GitHub reports the PR MERGED
      # and every non-green check is a cancelled run of a workflow
      # scripts/check-macos-floor-setup.sh --workflows lists, the runs
      # cancel-closed-pr-macos-runs.yml cancels when a PR closes (#952). It
      # records those checks in context as ci_cancelled_after_merge.txt. A
      # repo without that script, an open PR, a failed or pending check, and
      # a cancel outside those workflows all still fail.
      #
      # The checks are read through pr-checks.sh, which is `gh pr checks`
      # unchanged wherever the token can read checks. Where GitHub refuses the
      # check read (a fine-grained token on some repositories, #1132), it
      # builds the same list from the Actions jobs at the head and the
      # commit's statuses, and lists a required check neither answers with the
      # bucket `unreadable`, which this filter counts as not green.
      #
      # A repository with genuinely no hosted CI is the one way zero checks
      # passes, and it is stated, never inferred from an empty list:
      # ci-none-declared.sh, the last fallback, passes a PR with no checks
      # only when the default branch's .claude/shirabe-extensions/hosted-ci.json
      # says "hosted_ci": "none" with a reason, and the PR body records that
      # reason. It records ci_none_declared.txt in context. The default branch
      # is out of the PR's reach, so no PR can declare itself out of CI. The
      # trailing `|| exit 1` keeps the gate at 0 or 1, the only codes the
      # edges match, even when neither script can run.
      #   semantics: scripts/ci-gate-expression_test.sh,
      #              skills/work-on/scripts/ci-cancel-after-merge_test.sh,
      #              skills/work-on/scripts/ci-none-declared_test.sh
      #   execute.md's counterpart is owned_ci_passing: the same filter over the
      #   PR its ownership filter resolves, under its own name because
      #   scripts/validate-template-mermaid.sh check 4 holds one gate name to one
      #   command across templates
      ci_passing:
        type: command
        command: "\"{{PLUGIN_ROOT}}/skills/work-on/scripts/pr-checks.sh\" $(gh pr list --head $(git rev-parse --abbrev-ref HEAD) --json number --jq '.[0].number // empty') --json bucket --jq 'length > 0 and ([.[] | select(.bucket != \"pass\" and .bucket != \"skipping\")] | length == 0)' | grep -q true || \"{{PLUGIN_ROOT}}/skills/work-on/scripts/ci-cancel-after-merge.sh\" \"{{SESSION_NAME}}\" || \"{{PLUGIN_ROOT}}/skills/work-on/scripts/ci-none-declared.sh\" \"{{SESSION_NAME}}\" || exit 1"
      # A DIRTY pull request has merge conflicts, and GitHub creates no new
      # check-runs for one, so its CI gate says nothing about the change: it
      # can read green on checks from an earlier head, or red on zero checks
      # (#1018). This gate is what stops it, whatever ci_passing says (#162):
      # a DIRTY edge exists for each ci_passing answer, and the evidence edges
      # need a clean merge state. execute.md carries the same check as
      # owned_merge_state_clean, over the PR its ownership filter resolves; the
      # name differs because validate-template-mermaid.sh check 4 holds a gate
      # name shared across templates to one command.
      merge_state_clean:
        type: command
        command: "[ \"$(gh pr view --json mergeStateStatus --jq .mergeStateStatus)\" != \"DIRTY\" ]"
    accepts:
      ci_outcome:
        type: enum
        values: [failing_fixed, failing_unresolvable]
        description: >-
          Absent on the green path: koto routes green CI on the gates. Submit
          a value only while ci_passing fails.
      rationale:
        type: string
        description: What was fixed or why CI failures are unresolvable
    transitions:
      # Green CI routes with no evidence, to ci_pass_counting: a pass is
      # counted there before the run goes on, since a commit that fixed CI
      # may have edited a test. The root-or-child split that sends a root to
      # the cascade and a child to done is ci_pass_counting's.
      - target: ci_pass_counting
        when:
          gates.ci_passing.exit_code: 0
          gates.merge_state_clean.exit_code: 0
      # A DIRTY pull request stops, and stops explicitly, with a reason that
      # names the merge conflicts, whatever the CI gate reads: GitHub runs no
      # checks on one, so ci_passing can read green on an earlier head's
      # checks, or red on none at all. One edge per ci_passing answer keeps
      # every edge naming the CI gate; without the red one, a DIRTY PR whose
      # new head has no checks would hold here instead of stopping.
      - target: done_blocked
        when:
          gates.ci_passing.exit_code: 0
          gates.merge_state_clean.exit_code: 1
        context_assignments:
          failure_reason: "ci_monitor: the pull request is DIRTY — it has merge conflicts, and GitHub creates no check-runs for one, so its CI gate means nothing here. Resolve the conflicts and re-run."
      - target: done_blocked
        when:
          gates.ci_passing.exit_code: 1
          gates.merge_state_clean.exit_code: 1
        context_assignments:
          failure_reason: "ci_monitor: the pull request is DIRTY — it has merge conflicts, and GitHub creates no check-runs for one, so its CI gate means nothing here. Resolve the conflicts and re-run."
      # failing_fixed: the agent pushed a fix. The run comes back here rather
      # than finishing, so the gates poll CI on the new push before anything
      # can reach done: the skill promises a pull request with passing CI,
      # and a fix nobody re-checked does not keep that promise. The directive's
      # retry cap bounds the loop. Both evidence edges name ci_passing's
      # failure and a clean merge state, which is when they apply and what
      # lets koto prove them exclusive of the green and DIRTY ones.
      - target: ci_monitor
        when:
          gates.ci_passing.exit_code: 1
          gates.merge_state_clean.exit_code: 0
          ci_outcome: failing_fixed
      - target: done_blocked
        when:
          gates.ci_passing.exit_code: 1
          gates.merge_state_clean.exit_code: 0
          ci_outcome: failing_unresolvable
        context_assignments:
          failure_reason: "ci_monitor: unresolvable CI failures: ${evidence.rationale}"

  ci_pass_counting:
    # Entered only when CI passed on the open pull request (ci_monitor's
    # green edge). The pass is counted again here, with pass_counting's two
    # gates under the same names and commands (../references/red-first.md),
    # because a commit that fixed CI may have edited a test or moved HEAD
    # past a fix's green. A held run is accepted here as at pass_counting; a
    # decline or a failed green returns it to ci_monitor, where the edit is
    # reworked and pushed. A separate state rather than a shared one with a
    # variable naming where it came from: a hand rebind of that variable
    # could send a post-CI hold to finalization.
    gates:
      fix_green:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/red-first.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=fix_green "{{PLUGIN_ROOT}}/skills/work-on/scripts/red-first.sh" check-green "{{SESSION_NAME}}"'
      tests_counted:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/test-change.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=tests_counted "{{PLUGIN_ROOT}}/skills/work-on/scripts/test-change.sh" status "{{SESSION_NAME}}"'
      # A routing gate (DESIGN-output-gates Decision 9): is this run the
      # root, or a child /execute materialized? session-role.sh reads koto's
      # own parent_workflow and prints `root` or `child`. Exit 0 is root and
      # exit 1 is child; a lookup that can't decide (koto or jq missing, the
      # session not listed) prints `child` and says why on stderr, the safe
      # direction the script documents. Its exit 1 is an answer, not a
      # violation, so it prints no finding.
      #
      # Exit 2 is a role nobody decided: an unreachable PLUGIN_ROOT (the
      # test -x guard), or session-role.sh printing neither word (it prints
      # nothing on a usage error).
      # No edge names it, so the state holds: an undecided role must neither
      # run the cascade nor skip it. The script's stderr is left to koto, so
      # the hold carries the reason.
      is_root:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/session-role.sh" || exit 2; case "$("{{PLUGIN_ROOT}}/skills/work-on/scripts/session-role.sh" "{{SESSION_NAME}}")" in root) exit 0 ;; child) exit 1 ;; *) exit 2 ;; esac'
    accepts:
      counting_status:
        type: enum
        values: [green_failed, declined, blocked]
        description: >-
          Absent on the passing path: koto routes once fix_green and
          tests_counted pass. `green_failed` and `declined` return to
          ci_monitor; `blocked` stops the run when a hold can't be cleared.
      detail:
        type: string
        description: Why the run can't be counted.
    transitions:
      # The cascade belongs to the run that owns the PLAN, and that is the root.
      # A child materialized by /execute lands its own pull request and must not
      # cascade: the chain is finalized once per plan, not once per issue in it,
      # and a child that cascaded would race its siblings to delete the PLAN
      # they are still working from. A counted pass routes with no evidence.
      - target: cascade_entry
        when:
          gates.fix_green.exit_code: 0
          gates.tests_counted.exit_code: 0
          gates.is_root.exit_code: 0
      # A child stops here, and stops silently. It never reaches cascade_entry,
      # so it never runs the anchor search and never sees a cascade directive.
      - target: done
        when:
          gates.fix_green.exit_code: 0
          gates.tests_counted.exit_code: 0
          gates.is_root.exit_code: 1
      - target: done_blocked
        when:
          gates.tests_counted.exit_code: 3
        context_assignments:
          failure_reason: "ci_pass_counting: the acceptance seats declined the same test edits three times. The ledger is in context as test_change_ledger.jsonl."
      - target: ci_monitor
        when:
          gates.tests_counted.exit_code: 0
          gates.fix_green.exit_code: 1
          counting_status: green_failed
      - target: ci_monitor
        when:
          gates.tests_counted.exit_code: 1
          gates.fix_green.exit_code: 1
          counting_status: green_failed
      - target: ci_monitor
        when:
          gates.tests_counted.exit_code: 1
          counting_status: declined
      - target: done_blocked
        when:
          gates.tests_counted.exit_code: 0
          gates.fix_green.exit_code: 1
          counting_status: blocked
        context_assignments:
          failure_reason: "ci_pass_counting blocked: ${evidence.detail}"
      - target: done_blocked
        when:
          gates.tests_counted.exit_code: 0
          gates.fix_green.exit_code: 2
          counting_status: blocked
        context_assignments:
          failure_reason: "ci_pass_counting blocked: ${evidence.detail}"
      - target: done_blocked
        when:
          gates.tests_counted.exit_code: 1
          counting_status: blocked
        context_assignments:
          failure_reason: "ci_pass_counting blocked: ${evidence.detail}"
      - target: done_blocked
        when:
          gates.tests_counted.exit_code: 2
          counting_status: blocked
        context_assignments:
          failure_reason: "ci_pass_counting blocked: ${evidence.detail}"

  cascade_entry:
    # Decides whether this run has a document chain to finalize, and routes past
    # the cascade entirely when it does not. Every edge fires with NO evidence:
    # an ordinary bug fix with nothing behind it must never learn that a cascade
    # step exists (PRD R3).
    #
    # The `accepts:` block below is load-bearing despite every field being
    # optional, and removing it breaks R3 rather than tidying the state. A
    # failed gate on a state with NO accepts block returns GateBlocked; with one,
    # it falls through to transition resolution, which is what lets the
    # no-anchor edge fire silently. The rule is stated in execute.md's
    # settled_branch_record (:87-91), which also carries the warning repeated
    # here:
    #
    #   EVERY transition must name the gate in its `when:` clause. A gate not
    #   referenced by any transition is evaluated, reported, and ignored -- an
    #   anchor check that runs and decides nothing. An unconditional edge added
    #   here would also chain the state through, since koto's advance loop keys
    #   on having a conditional transition rather than on required evidence.
    #
    # The decision is delegated to find-anchor-plan.sh rather than inlined here,
    # and the three exit codes are the reason. A gate command can express a
    # two-way test in one line; this decision has three outcomes, because "could
    # not decide" must not collapse into "no anchor" -- exit 1 routes past the
    # cascade in silence, so an unreadable tree or an issue named by two PLANs
    # arriving as 1 would skip a cascade that was owed and tell nobody. The
    # script's search is also anchored on the colon after the issue number, which
    # is what stops issue 12 matching a row for issue 123 and cascading the wrong
    # chain; its test suite covers that case and five other wrong
    # implementations. Nothing mechanical enforces the anchoring, in the script
    # or here -- check-template-interpolation.sh reads shell-style references,
    # not regex correctness.
    #
    # The `test -x` prefix is not defensive clutter. PLUGIN_ROOT is required and
    # koto still accepts an empty value for it, so an unset CLAUDE_PLUGIN_ROOT at
    # init reaches this line as an absolute path to nothing. Without the test the
    # finder is simply not found, the gate exits 127, koto discards its output,
    # and the run holds with no diagnostic. With it, a plugin root that does not
    # resolve fails closed to exit 2 and stops loudly at done_blocked.
    gates:
      anchor_present:
        type: command
        command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/find-anchor-plan.sh" || exit 2; "{{PLUGIN_ROOT}}/skills/work-on/scripts/find-anchor-plan.sh" "{{ISSUE_NUMBER}}" "{{PLAN_DOC}}"'
    accepts:
      anchor_note:
        type: string
        description: >-
          Absent on both normal paths. The state advances with no evidence
          whichever way the gate resolves, so the agent never sees this field;
          it exists so a failed gate falls through to transition resolution
          instead of blocking.
    transitions:
      - target: cascade_run
        when:
          gates.anchor_present.exit_code: 0
      - target: done
        when:
          gates.anchor_present.exit_code: 1
      - target: done_blocked
        when:
          gates.anchor_present.exit_code: 2
        context_assignments:
          failure_reason: >-
            cascade_entry: could not determine whether this issue has a PLAN
            behind it. Either the anchor finder could not decide (a
            non-numeric issue number, an unreadable docs/plans, or two PLANs
            naming the same issue) or it was not reachable at PLUGIN_ROOT.
            Run skills/work-on/scripts/find-anchor-plan.sh against the issue
            number to see which. Not skipped: a cascade may be owed.

  cascade_run:
    # Runs the document-chain cascade and records what it actually did.
    #
    # The three conditional transitions below are load-bearing beyond their
    # routing. koto's advance loop chains through a state whose transitions are
    # ALL unconditional, even when the state declares required evidence -- the
    # guard is keyed on having a conditional transition, not on having an
    # `accepts:` block (advance.rs:571-575, :1229-1234). execute.md's `escalate`
    # (:457-466) is the worked counter-example: required evidence, one
    # unconditional edge, chained straight through.
    #
    # So collapsing these three edges into one unconditional transition -- a
    # tempting simplification, since two of them share a target -- would let a
    # tick run the cascade and land on a terminal in the same invocation, with
    # the agent never seeing this state's directive. The `accepts:` block would
    # still be here and would not save it.
    #
    # The evidence below is the OBSERVED post-state, not the script's account of
    # itself. `cascade_status` is what the cascade said; `post_state` is what the
    # repository shows, and a `completed` claim cannot route to `done` without a
    # `verified` observation to go with it. That split is the point of the state:
    # several of the script's operations report step-level `ok` having changed
    # nothing, and its own post-cascade verification reads the working tree, so a
    # document transitioned on disk but never staged satisfies everything it
    # checks.
    #
    # `post_state` carries five failure values rather than one, and each has its
    # own edge and its own failure_reason. koto discards a failed gate's output
    # and a terminal state records what it was given, so collapsing them would
    # make "the PLAN was never deleted", "nothing was committed" and "a document
    # was transitioned but not staged" arrive identically in the record -- the
    # shape that makes a catastrophe and a timeout indistinguishable
    # (tsukumogami/shirabe#376). The distinction has to survive in the routing,
    # because there is nowhere else for it to survive.
    accepts:
      cascade_status:
        type: enum
        values: [completed, partial, skipped]
        required: true
      post_state:
        type: enum
        values: [verified, plan_present, no_commit, wrong_status, not_in_commit, undecided]
        required: true
        description: >-
          The exit of verify-cascade-commit.sh, which reads the third fact from
          the finalization commit's own paths: 0 verified, 2 plan_present,
          3 no_commit, 4 wrong_status, 5 not_in_commit, 6 undecided.
      anchor_plan:
        type: string
        description: The PLAN path that was cascaded. A path, not a description.
      finalization_commit:
        type: string
        description: The sha whose paths were read. A sha, not "the last commit".
      cascade_detail:
        type: string
        description: What the cascade did, or why steps were skipped.
    transitions:
      # koto requires transitions to one target to be provably exclusive, and
      # two edges keyed on different fields are not: it refuses to compile a
      # `cascade_status` edge alongside a `post_state` edge to the same terminal
      # because both could match one submission. So every edge below names BOTH
      # fields, and the table is their cross product. It is mechanical, and it
      # grows multiplicatively if either dimension gains a value.
      - target: done_blocked
        when:
          cascade_status: partial
        context_assignments:
          failure_reason: "cascade_run: cascade reported partial: ${evidence.cascade_detail}"
      - target: done
        when:
          cascade_status: completed
          post_state: verified
      - target: done
        when:
          cascade_status: skipped
          post_state: verified
      - target: done_blocked
        when:
          cascade_status: completed
          post_state: plan_present
        context_assignments:
          failure_reason: "cascade_run: the PLAN is still on disk (${evidence.anchor_plan}). The cascade did not delete its anchor, whatever it reported."
      - target: done_blocked
        when:
          cascade_status: completed
          post_state: no_commit
        context_assignments:
          failure_reason: "cascade_run: the PLAN is gone from the tree but no commit deletes it. Nothing was finalized; the work is uncommitted, not lost."
      - target: done_blocked
        when:
          cascade_status: completed
          post_state: wrong_status
        context_assignments:
          failure_reason: "cascade_run: a chain document is not at its terminal posture. Re-run verify-cascade-commit.sh against ${evidence.anchor_plan} to see which."
      - target: done_blocked
        when:
          cascade_status: completed
          post_state: not_in_commit
        context_assignments:
          failure_reason: "cascade_run: a chain document is terminal on disk but ABSENT from commit ${evidence.finalization_commit}. It was transitioned in the working tree and never staged, so the tree looks finished and the commit is not."
      - target: done_blocked
        when:
          cascade_status: completed
          post_state: undecided
        context_assignments:
          failure_reason: "cascade_run: the post-state could not be determined. Not treated as success: re-run verify-cascade-commit.sh against ${evidence.anchor_plan} and read its diagnostics."
      - target: done_blocked
        when:
          cascade_status: skipped
          post_state: plan_present
        context_assignments:
          failure_reason: "cascade_run: the PLAN is still on disk (${evidence.anchor_plan}). The cascade did not delete its anchor, whatever it reported."
      - target: done_blocked
        when:
          cascade_status: skipped
          post_state: no_commit
        context_assignments:
          failure_reason: "cascade_run: the PLAN is gone from the tree but no commit deletes it. Nothing was finalized; the work is uncommitted, not lost."
      - target: done_blocked
        when:
          cascade_status: skipped
          post_state: wrong_status
        context_assignments:
          failure_reason: "cascade_run: a chain document is not at its terminal posture. Re-run verify-cascade-commit.sh against ${evidence.anchor_plan} to see which."
      - target: done_blocked
        when:
          cascade_status: skipped
          post_state: not_in_commit
        context_assignments:
          failure_reason: "cascade_run: a chain document is terminal on disk but ABSENT from commit ${evidence.finalization_commit}. It was transitioned in the working tree and never staged, so the tree looks finished and the commit is not."
      - target: done_blocked
        when:
          cascade_status: skipped
          post_state: undecided
        context_assignments:
          failure_reason: "cascade_run: the post-state could not be determined. Not treated as success: re-run verify-cascade-commit.sh against ${evidence.anchor_plan} and read its diagnostics."

  # The success terminals' result is the payload koto promotes onto a caller's
  # leg (--koto-leg), so a coordinator reads the pull request from koto's
  # record instead of asking the worker for it (#995). pr_url is written on
  # pr_creation's created edge. A run that opened none (a child on
  # /execute's shared branch, or an already-complete issue) resolves pr to ""
  # and koto lists it under `missing`. There is no head: nothing on the run's
  # path records one after a CI fix is pushed, so it would go stale, and a
  # coordinator's verify reads the head from GitHub. done_blocked declares no
  # map, so its payload stays koto's own.
  done:
    terminal: true
    result:
      pr: "${context.pr_url}"

  done_already_complete:
    terminal: true
    result:
      pr: "${context.pr_url}"

  done_blocked:
    terminal: true
    failure: true
    accepts:
      failure_reason:
        type: string
        description: >
          Reason for the blocking failure. Written to context via context_assignments
          on incoming transitions so koto can populate the batch view's reason field.

  skipped_due_to_dep_failure:
    terminal: true
    skipped_marker: true
---

## entry

Determine the workflow mode and provide the initial context for this task.

**Issue-backed mode**: you have a GitHub issue number. Submit evidence with
`mode: issue_backed` and include the `issue_number` field.

**Free-form mode**: you have a task description but no issue. Submit evidence with
`mode: free_form` and include the `task_description` field.

**Plan-backed mode**: you have an issue from a koto parent workflow (spawned via
plan orchestrator). Submit with `mode: plan_backed` and include `issue_source`
(either `github` or `plan_outline`).

Evidence schema:
- `mode`: `issue_backed`, `free_form`, `plan_backed`, or `skipped`
- `issue_number`: GitHub issue number (issue-backed only)
- `task_description`: what to build (free-form only)
- `issue_source`: `github` or `plan_outline` (plan-backed only)

## context_injection

Read `references/phases/phase-0-context-injection.md` for detailed steps. Run
the extraction with this command as written, the `--issue-repo` value
included even when it is empty (an issue in this repository):

```bash
"{{PLUGIN_ROOT}}/skills/work-on/references/scripts/extract-context.sh" {{ISSUE_NUMBER}} --session {{SESSION_NAME}} --issue-repo "{{ISSUE_REPO}}"
```

If the gate fails (artifact missing), submit `status: completed` after creating
the artifact, `status: override` if providing context differently, or
`status: blocked` if the issue cannot be reached.

## task_validation

Assess whether this free-form task description is clear enough and appropriately
scoped for direct implementation.

Read the task description provided at entry. Check for:
- Ambiguous or missing requirements that would make implementation guesswork
- Scope that clearly exceeds a single implementation session
- Requests that need a design document before code can be written

If the task is clear and reasonably scoped, submit `verdict: proceed` with your
rationale. If the task is not ready, submit `verdict: exit` with rationale
explaining what the user should do instead (narrow the scope, create an issue,
write a design doc).

Evidence schema:
- `verdict`: `proceed` or `exit`
- `rationale`: reasoning behind your assessment

## validation_exit

The task was not ready for direct implementation. Communicate the verdict and
rationale to the user. Suggest concrete next steps: create a GitHub issue with
clearer requirements, write a design document, narrow the scope to a single
change, or split into smaller tasks. If the verdict was `needs_design`, explain
which aspects need design work before implementation can proceed.

## research

Gather context about the codebase relevant to this free-form task. Read code,
check existing patterns, understand the architecture around the area you will
modify. Focus on:
- Files and packages that will be touched
- Existing patterns and conventions to follow
- Dependencies and interfaces that constrain the approach
- Tests that cover the affected area

Submit a `context_summary` describing what you found. The summary carries
forward to inform the post-research validation and subsequent analysis. Whether
what you found is enough to proceed is post_research_validation's question, not
this state's.

Evidence schema:
- `context_summary`: description of findings and relevant codebase observations

## post_research_validation

Reassess the task against what research revealed about the current codebase.

With the codebase context from research, evaluate whether the task is still
appropriate for direct implementation. Check for:
- Misconceptions in the original task description now visible with codebase context
- Dependencies or prerequisites not apparent from the task description alone
- Scope that research reveals to be larger than initially expected
- Existing code that already solves the problem or conflicts with the approach

Submit `verdict: ready` to proceed, `verdict: needs_design` if a design doc is
needed first (routes to validation_exit), or `verdict: exit` if the task should
not proceed (routes to validation_exit). Include `revised_scope` when the task
can proceed with a narrowed scope.

Evidence schema:
- `verdict`: `ready`, `needs_design`, or `exit`
- `rationale`: reasoning informed by research findings
- `revised_scope`: (optional) narrowed scope description

## setup_issue_backed

Read `references/phases/phase-1-setup.md` for branch naming and baseline format.

If the gate fails, submit `status: completed` after creating the branch and baseline,
`status: override` if reusing an existing branch, or `status: blocked`. Reuse the
current branch, and submit `status: override`, when the user asked you to continue on
it or it is this work's branch from a previous session; otherwise create a new one.

## setup_free_form

Read `references/phases/phase-1-setup.md` for branch naming and baseline format.

If the gate fails, submit `status: completed` after creating the branch and baseline,
`status: override` if reusing an existing branch, or `status: blocked`. Reuse the
current branch, and submit `status: override`, when the user asked you to continue on
it or it is this work's branch from a previous session; otherwise create a new one.

## plan_context_injection

Obtain the issue context for a plan-backed task. Behavior differs by ISSUE_SOURCE:

- If ISSUE_SOURCE is `github`: read the GitHub issue with `gh issue view $ISSUE_NUMBER`
  and write it to koto context as `context.md`. Then proceed to setup_plan_backed.
- If ISSUE_SOURCE is `plan_outline`: the PLAN doc is already available via the
  PLAN_DOC variable. When PLAN_DOC_MOVED is set, the PLAN's checkout moved after
  this child was opened and PLAN_DOC_MOVED is where the PLAN is now: read the
  PLAN at `{{PLAN_DOC_MOVED}}` when that is non-empty, and at `{{PLAN_DOC}}`
  otherwise. Extract the specific issue outline from that PLAN doc and write it
  as `context.md`, then proceed to plan_validation.
- A `plan/v2` PLAN (frontmatter `schema: plan/v2`) holds steps, not issues: the
  task name {{ARTIFACT_PREFIX}} is `step-<N>`, and the context is the
  `### Step <N>:` block under `## Steps`, from that heading up to the next
  `### ` or `## ` heading. Read it from the PLAN as committed now, not from an
  earlier copy: the plan's owner details a step in its own commit, and a rerun
  after that commit has to build from the detailed text. Write the block as
  `context.md` unchanged. A step that is still a one-line outline is written
  as it stands; plan_validation is where it stops.

Submit `status: completed` with `issue_source` set to match the source used,
`status: override` if context is provided differently, or `status: blocked` if context cannot be obtained.

Evidence schema:
- `status`: `completed`, `override`, or `blocked`
- `issue_source`: `github` or `plan_outline` (required when status is completed; determines next state)

## plan_validation

Validate that the plan outline item (ISSUE_SOURCE=plan_outline path) is clear
enough for direct implementation. Check that acceptance criteria exist and are
specific enough to code against.

koto runs the `step_detail` gate on entry:
`{{PLUGIN_ROOT}}/skills/work-on/scripts/step-detail-check.sh` reads a `plan/v2`
step from the PLAN as committed now, at PLAN_DOC_MOVED when that is set and at
PLAN_DOC otherwise. On a `plan/v1` task it passes without
reading anything. When the step is still a one-line outline the gate fails and
its finding reads `step <N> is an outline; the plan's owner details it before
its work starts`; any other failure is a refusal that names its reason (a
missing shirabe, a plan it cannot read). Either way the step's work does not
start here: `proceed` is refused while the gate fails, so submit
`verdict: exit` with `rationale` set to the finding's message, word for word.
Don't detail the step yourself; the plan's owner does that in a commit of its
own, and running this child again after that commit passes the gate.

Submit `verdict: proceed` to continue to setup_plan_backed, or `verdict: exit`
with rationale to route to validation_exit.

Evidence schema:
- `verdict`: `proceed` or `exit`
- `rationale`: reasoning behind the validation verdict

## setup_plan_backed

Read `references/phases/phase-1-setup.md` for branch naming and baseline format.
For plan-backed tasks, use ARTIFACT_PREFIX as the baseline key.

Submit `status: completed` after creating the branch and baseline, `status: override`
if reusing an existing branch, or `status: blocked`. When `SHARED_BRANCH` is set, koto
skips this state through `skip_if` and you submit nothing here.

## staleness_check

This state assesses whether the codebase has moved on since the issue was opened.
The gate runs shirabe's own staleness check against issue {{ISSUE_NUMBER}}, and
the check's exit status is its verdict. What it measures, and the thresholds, are
in `references/staleness-signals.md`. koto routes on that verdict itself, so on
every answered path you submit nothing and the run has already moved on by the
time you read this:

- **exit 0**: fresh. The run goes to `analysis`.
- **exit 1**: stale. The run goes to `introspection`, which re-reads the issue
  against current code.
- **exit 3, or -1 (koto could not run the gate to completion: it timed out or
  failed to start)**: unavailable. The check could not reach a verdict: the
  plugin root was not passed, `gh` is unauthenticated or unreachable, a read
  failed, or the run's issue is in another repository (`ISSUE_REPO` is set),
  which the check can't read yet. The run goes to `analysis` with staleness
  not assessed. This is not an override; nobody chose to skip the check.

You only see this state on **exit 2**: the gate passed the check a bad argument,
which is a template defect. Submit `staleness_signal: blocked` with the detail,
or `staleness_signal: override` only when the user explicitly said to skip the
staleness check. An instruction to skip it can't take effect on any other exit:
koto has already routed the run by the time you would answer.

For the check's reasons (the signals it measured, or why it was unavailable),
run it yourself and read its JSON report:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/check-staleness.sh" --issue {{ISSUE_NUMBER}}
```

Evidence schema (exit 2 only):
- `staleness_signal`: `override` or `blocked`
- `detail`: the override reason, or the blocking detail

## introspection

Read `references/phases/phase-2-introspection.md` for steps and evidence options.

The gate checks for context key `introspection.md`. On resume, if the
artifact already exists in koto context, the gate auto-advances.

## analysis

Read `references/phases/phase-3-analysis.md` for plan structure and agent
delegation patterns. Output: koto context key `plan.md`. A child of `/execute`
first reads its earlier siblings' `summary.md` through `koto context get`, once
per sibling; its "Earlier Children's Summaries" section says how.

**Already-complete detection**: during analysis, check whether the issue goal is
already fully satisfied by current code. If all acceptance criteria are already met,
submit `plan_outcome: already_complete` — no implementation needed. Routes to
`done_already_complete` (a non-failure terminal).

koto records `impl_base`, the commit this work starts from, as it enters this
state. You don't submit it, and you don't classify the issue's type here: that
question is asked once, at `issue_type_routing`, after implementation.

Retry cap: self-loop with `scope_changed_retry` up to 3 times. After 3,
use `scope_changed_escalate`. The cap lives here until koto enforces it from its
attempt counts, with the same number. Submit `blocked_missing_context` if stuck.
Record non-obvious decisions with `koto decisions record {{SESSION_NAME}}`.

## offload_canary

koto runs this state itself and moves on to `review_level_choice` without
stopping. It assigns the run to the live offload canary's groups when the
canary applies; there is nothing to submit. If it ever holds here, tick again with
`koto next {{SESSION_NAME}} --no-cleanup`.

## offload_arm_withheld

koto passes through this state to `review_level_choice` without stopping.
There is nothing to submit.

## offload_arm_preloaded

koto passes through this state to `review_level_choice` without stopping.
There is nothing to submit.

## review_level_choice

Choose this run's review level now, before implementing anything. The level
decides which review panels a code change goes through
(`references/review-levels.md` defines them):

- `light` -- one panel of one reviewer seat. For a small, contained change
  outside the risky path classes.
- `standard` -- scrutiny (three seats), then review (three seats). No QA.
- `full` -- scrutiny, review, then QA (seven seats).

Choose from the issue and the analysis plan in `plan.md`: how much the change
touches and how much could go wrong. After implementation the facts of the
change set a floor the level can't sit below, so a level that turns out too
light is raised then, never lowered. koto has already recorded the
coordinator's bound, if any, as it entered this state; the choice must fall
inside it.

Record the choice:

```bash
"{{PLUGIN_ROOT}}/skills/work-on/scripts/review-level.sh" set "{{SESSION_NAME}}" <level>
```

It rebinds `REVIEW_LEVEL` and writes the ledger together; then tick again with
nothing submitted (`koto next {{SESSION_NAME}} --no-cleanup`) and the run goes on to
fix_determination. A bound alone never picks the level, even one whose floor
equals its ceiling: the choice is always a `set`. Exit 1 prints a `refused:` line naming the rule (outside the
bound, or no bound recorded yet: tick again so the action records it). Exit 66
means the rebind or a koto context read or write failed and nothing changed;
read its message and run it again. If no level can be recorded, submit
`level_status: blocked` with `detail`.

## fix_determination

koto has decided whether this unit is a fix, before anything is implemented
(`references/red-first.md`). On entry it ran `fix-kind.sh resolve`, which records
a fix when the issue carries one of the repository's fix labels (`## Fix Labels:`
in CLAUDE.md, `bug` by default) or the plan step has a `**Fixes**:` line, and a
change otherwise, and binds `UNIT_KIND` to match. Before that it started the
test-change ledger (`test-change.sh init`), which an edited test is judged against
at `pass_counting`. See what it recorded:

```bash
"{{PLUGIN_ROOT}}/skills/work-on/scripts/fix-kind.sh" kind "{{SESSION_NAME}}"
```

If the unit is recorded as a change but its report describes existing behaviour
as wrong (something worked before, or is documented to work, and doesn't), declare
it a fix yourself:

```bash
"{{PLUGIN_ROOT}}/skills/work-on/scripts/fix-kind.sh" declare "{{SESSION_NAME}}" --reason "<why the report says this is a defect>"
```

A fix can't be taken back: `fix-kind.sh` refuses to make one a change, and the run
owes a red before implementation. Then tick with nothing submitted
(`koto next {{SESSION_NAME}} --no-cleanup`). koto routes on `UNIT_KIND` from the tick
after it was bound, so a fresh determination holds `kind_unchanged` once, saying to
tick again. A change goes to `implementation`, a fix to `reproduce`.

`kind_unchanged` also holds when `UNIT_KIND` was rebound by hand away from the
ledger; its `hold:` line names both, and `fix-kind.sh declare` puts a fix back. If
the action failed (its fallback is shown above) and the cause can't be fixed, submit
`kind_status: blocked` with `detail`.

## reproduce

This unit is a fix, so it starts red: before changing any code, record a check that
fails on the code as it is, for the reason the report gives
(`references/red-first.md`).

1. Write the test that reproduces the report and commit it. Commit only the test:
   the red copies the unit's committed test files onto the base code, so it would
   show the failure even with a correcting change committed, but the order of the
   work is part of what a reviewer reads.
2. Choose the failure marker, a literal string of at least 8 characters that the
   report states and the failing check prints, and a passage of at least 20
   characters copied verbatim from the report that contains it. The report is the
   plan step's Fixes line, the issue body, or the task text, as
   `koto context get {{SESSION_NAME}} fix_report.txt` shows it.
3. Record the red with the command that runs the check:

```bash
"{{PLUGIN_ROOT}}/skills/work-on/scripts/red-first.sh" red "{{SESSION_NAME}}" --marker '<marker>' --passage-file <file holding the passage> -- <command> [<arg>...]
```

It exits 0 when the red is recorded and 1 with a `refused:` line naming the
condition that failed: the check passed, its output lacks the marker (a check that
fails for some other reason, such as a compile error), the marker or passage is too
short, the marker isn't in the passage, or the passage isn't in the report. Fix the
test or the inputs and run it again. Name an existing test that already reproduces
the bug with `--tests <path>...`.

When no automated check can reproduce the bug, record a before-observation instead
(`red-first.sh observe {{SESSION_NAME}} --phase before --file <observation.md>`;
`references/red-first.md` lists its sections). An observation pair counts only once
an acceptance seat accepts it, at `pass_counting`.

Then tick with nothing submitted. The `red_recorded` gate passes once a red or a
before-observation is recorded, and the run goes on to `implementation`. If neither
can be recorded, submit `reproduce_status: blocked` with `detail`.

## implementation

Read `references/phases/phase-4-implementation.md` for the implementation cycle,
code review guidance, and commit patterns. An agent review's
`review-packet.sh code --issue` packet takes `--issue-repo "{{ISSUE_REPO}}"`,
as written here, empty or not.

Submit `implementation_status: complete` when the work is committed. The issue's
type is not part of this submission: koto records the changed paths next and then
asks for the type once, at `issue_type_routing`.

Retry cap: self-loop with `partial_tests_failing_retry` up to 3 times. After 3,
use `partial_tests_failing_escalate`. The cap lives here until koto enforces it
from its attempt counts, with the same number. Submit `blocked` for external
blockers.
Record non-obvious judgment calls with `koto decisions record {{SESSION_NAME}}`.

## changed_paths_record

Recording the paths this implementation changed. koto runs the record itself on
entry and advances on its own; you only see this state if it could not.

The record is `changed_paths.txt`: the base commit, the number of commits since
it, and one `git diff --name-status -M` line per changed path. It lists paths
and statuses only and never names a type.

Submit `paths_status: override` to go on to the issue-type question without the
record, or `paths_status: blocked` with `detail` to stop. On the passing path
submit nothing -- the run advances on its own.

## issue_type_routing

Say what kind of change this issue turned out to be. This is the only place the
workflow asks, and it routes what happens next.

Read `changed_paths.txt` for what the implementation actually touched, alongside
the issue context in `context.md`:

```bash
koto context get {{SESSION_NAME}} changed_paths.txt
```

The first two lines are the base commit and the number of commits since it; each
line after that is one `git diff --name-status -M` entry, and a final
`... N more paths` line means the list was cut. The plan's hint is `{{ISSUE_TYPE}}`; treat it as
a starting point and override it when the changed paths say otherwise.

- `code` -- behaviour changes: source, tests, build or CI logic, templates that
  drive a workflow. Passes the review-level check, then goes through the
  panels its review level names: `light` one seat, `standard` scrutiny and
  review, `full` scrutiny, review and QA. No panel passes while this run has
  no commits since `impl_base`.
- `docs` -- writing or structural documentation changes. Skips the panels and
  goes to verification. Needs at least one commit since `impl_base`:
  submitted with none, the state holds; commit the work, then submit it again.
  If the work is already committed and the state still holds, `impl_base`
  is missing or was recorded after the work (compare
  `koto context get {{SESSION_NAME}} impl_base` with `git log`): record
  the commit the run started from, the parent of its first commit, with
  `git rev-parse <commit> | koto context add {{SESSION_NAME}} impl_base`, and submit again.
- `task` -- operational work (running scripts or commands) with no reviewable
  change set. Skips the panels, goes to verification, and needs no commits.

Use `code` when unsure; it's the route that checks the most.

Evidence schema:
- `issue_type`: `code`, `docs`, or `task`

## review_level_check

The review-level check stands between a code change and its first panel, on
every lap. koto gathered the facts of the change as it entered this state
(`review_facts.json`: changed lines and files, the path classes touched,
whether tests or the acceptance criteria changed, and the floor those facts
set) and checks the run's review level against them. When it
passes, koto goes on by itself: `light` to the one-seat light panel,
`standard` and `full` to scrutiny. You only see this state when it holds.

Read the `hold:` line in the `level_floor` gate's output. It names why:

- **below the facts floor** (it names the rule): raise the level to the floor,
  `"{{PLUGIN_ROOT}}/skills/work-on/scripts/review-level.sh" set "{{SESSION_NAME}}" <floor>`.
  A raise to the floor needs no reason, even past a ceiling.
- **REVIEW_LEVEL differs from the ledger** (both levels named): the variable
  was changed by hand. Run `set` with the level the run should be at.
- **below the bound's floor, or above its ceiling with no breach**: `set` a
  level inside the bound, or past the ceiling with `--reason`.
- **the facts were gathered at another commit**: commits landed while the
  state held. Tick again; the action re-gathers them.

When the `level_fits_facts` check fails on the decider's verdict, the decider
judged the level too light for these facts. Raise it with
`set ... <level> --cause veto:level_fits_facts`, or, when you're sure the
verdict is wrong, record why with
`koto overrides record {{SESSION_NAME}} --gate level_fits_facts --rationale "<why>"`.
A fail on your own answer (the criterion is under the output's
`agent_answered`) is different; see below.

When the `level_fits_facts` check is `pending` with `level_fits_facts` under
its output's `awaiting` list, answer it yourself: the decider gave no verdict,
so the question falls back to you. Judge the level against the facts in
`review_facts.json` and the definitions in `references/review-levels.md`,
record your answer, and tick again with nothing submitted:

```bash
koto decider answer {{SESSION_NAME}} --gate level_fits_facts --criterion level_fits_facts --answer <pass|fail|unclear>
```

The check's warning finding gives the reason the decider couldn't answer (an
error or timeout, an unreadable answer, an over-budget slice, a spent per-call
cap, or another tick holding the lock), the question, and what each answer
means. This happens when the decider runs in shadow too, so the check can hold
the run here even though a shadow check never fails it.

`pass` (the level is thorough enough) and `unclear` (the facts don't say
enough) let the check through. On `fail` (the level is too light), raise the
level with a plain `set ... <level>`, without `--cause`, before you tick again.
Raise first whichever mode the check runs in, since the response doesn't say:
in veto your `fail` holds the run until the level changes, but in shadow it's
only recorded and the next tick moves on. No `--cause`, because a `veto` line
in the ledger means the decider asked for the raise, and this one is yours.
The tick after the raise asks the decider about the raised level and falls
back to you again if it still can't answer. Your answer is recorded as yours, never as the
decider's verdict. Don't record an override to get past a waiting check, and
answer only a criterion the response lists under `awaiting`.

After a raise, tick again with nothing submitted: the action records a `check`
line at the new level and the gate passes. `koto overrides record` on
`level_floor` is the only way past a hold without a raise, and the ledger
reader counts it. If the run can't go on, submit `level_status: blocked` with
`detail`.

## scrutiny

Run the scrutiny panel (three parallel reviewers: completeness, justification, intent). Read `references/phases/phase-4a-scrutiny.md` for detailed steps and reviewer prompts. Its `review-packet.sh code --issue` packet takes `--issue-repo "{{ISSUE_REPO}}"`, as written here, empty or not. The round's record is the verdict ledger, written by `panel-scope.sh --record scrutiny`; `scrutiny_results.json` is optional, the round's summary for a reader, and no gate reads it.

koto decides whether the panel passed, from the ledger: the `scrutiny_verdict` gate runs `panel-scope.sh --verdict scrutiny`. Every finding a seat returns carries `severity: blocking` or `severity: advisory`, `--record` refuses a round with a finding that has neither, and a seat is blocking exactly when one of its findings is `blocking`. Exit 0 (every seat recorded, every blocking finding closed by a record its writer may write) advances to `review` with nothing submitted: record the round and tick again. Exit 1 (a blocking finding is unclosed) prints one finding per unclosed blocking finding, under the rule it cites or `panel/open-finding`, and waits for `scrutiny_outcome`. Exit 2 holds: a run the round planned is not recorded, a seat has no verdict, or the ledger can't be read; record the round and tick again.

The `has_commits` gate also has to pass: the panel does not advance while this run has no commits since `impl_base`. If the work really has none, that is a blocking finding: record it with `severity: blocking`, retry it through the budget below, which reads its count of 1 from the ledger, and commit the work in implementation. It is recorded like any scrutiny round, so past the second retry a later scrutiny round is compared against that 1 and escalates unless it finds nothing; the rule errs toward stopping there on purpose. If it is committed and the panel still holds on `has_commits`, `impl_base` is missing or was recorded after the work (compare `koto context get {{SESSION_NAME}} impl_base` with `git log`): record the commit the run started from, the parent of its first commit, with `git rev-parse <commit> | koto context add {{SESSION_NAME}} impl_base`, and tick again.

koto has already decided what this round runs: read `scrutiny_scope.json` and spawn only the decisions that aren't `keep`. In a full round every seat is `full` and is handed its own unclosed findings, which it answers by id. Any other round keeps every seat and plans at most one run, the panel's re-verifier (seat `reverifier`): it answers each due finding by id with `holds` or `reverified` and, when its decision carries `fix_review`, reviews the fix diff against every panel's criteria. It reads the `review-packet.sh recheck --seat reverifier` packet the phase file's commissioning line gives. After the round, record every run with `panel-scope.sh --record scrutiny` (the phase file has the command). When nothing runs and no blocking finding is unclosed, koto carries the verdict and advances without stopping here; a carried panel submits nothing, so it neither spends nor resets the retry count below, and koto's log still records its visit. When nothing runs but a blocking finding the fix didn't touch is still unclosed, `scrutiny_verdict` blocks the panel with no run spent. The `scrutiny_recorded` gate also holds the passing route and `blocking_retry` until the round is recorded.

The decider batch runs beside the seats for a user whose decider is on: the `scrutiny_decider` check asks Jev whether every decision this run recorded in `analysis` and `implementation` gives, in its reason, why the choice was made. It replaces no seat, so spawn the seats as the scope says. Its findings are advisory while the criterion is untrusted: the check runs in shadow, so neither its verdict nor yours can fail the panel or change where it goes. When the `scrutiny_decider` check is `pending` with `work-on/scrutiny-decision-reasons` under its output's `awaiting` list, the decider gave no verdict and the question falls back to you. The check's warning finding gives the reason and the question; read the decisions it asked about with `"{{PLUGIN_ROOT}}/skills/work-on/scripts/decision-reasons.sh" slice "{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl"` (`koto decisions list` shows only this state's), judge each reason, record your answer, and tick again with nothing submitted:

```bash
koto decider answer {{SESSION_NAME}} --gate scrutiny_decider --criterion work-on/scrutiny-decision-reasons --answer <pass|fail|unclear>
```

`pass` means every reason says why its choice was made, `fail` that one only restates its choice or gives none, and `unclear` that the list can't be judged; any of them lets the check through. This can hold a carried round too, where no seat runs, so answer it there the same way. Answer only a criterion the response lists under `awaiting`, and don't record an override to get past a waiting check. A run that recorded no decision has nothing to grade, and the check passes without asking.

Submit nothing when the panel passes. While `scrutiny_verdict` exits 1, submit `scrutiny_outcome: blocking_retry` when the findings are correctable (it routes to `implementation`, where the coder agent addresses them), or `blocking_escalate` when the work cannot proceed without escalation. `blocking_escalate` is also taken while the gate exits 2, for a round that can't be recorded at all. Include `failure_reason` for `blocking_escalate`. Neither value is accepted while the gate exits 0, and no value advances the panel: only the recorded verdicts do, or a person's override of `scrutiny_verdict`.

Retry cap: the blocking retries in a run are shared by scrutiny, review, qa_validation and light_review and follow progress. The first 2 are granted whatever the counts. A third is granted only when this panel's count of blocking findings is lower than on its own previous blocking round in this run, and no run gets more than 3. `panel-retry-budget.sh` applies the rule and records each retry it grants in the context key `panel_retries`, so before running the retry loop, run `"{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-retry-budget.sh" "{{SESSION_NAME}}" scrutiny` once for the round. It takes no count: it reads the panel's unclosed blocking findings from the ledger itself (`panel-scope.sh --open-count`), the same set `scrutiny_verdict` printed, so the count it compares is never the agent's. Exit 0 grants the retry: run the retry loop, which submits `blocking_retry`. Any other exit refuses it: submit `blocking_escalate` with the reason it printed as `failure_reason`, which ends the run at `done_blocked`. The rule is docs/decisions/DECISION-work-on-panel-retry-progress-cap-2026-10-01.md. The cap lives here until koto can count defects per round and enforce it, with the same rule.

## review

Run the code review panel (three parallel reviewers: pragmatic, architect, maintainer). Read `references/phases/phase-4b-review.md` for detailed steps and reviewer prompts. Its `review-packet.sh code --issue` packet takes `--issue-repo "{{ISSUE_REPO}}"`, as written here, empty or not. The round's record is the verdict ledger, written by `panel-scope.sh --record review`; `review_results.json` is optional, the round's summary for a reader, and no gate reads it.

koto decides whether the panel passed, from the ledger, as at scrutiny: the `review_verdict` gate runs `panel-scope.sh --verdict review`, and each finding's `severity` decides its seat's verdict. Exit 0 advances with nothing submitted, exit 1 (a blocking finding is unclosed) prints one finding per unclosed blocking finding, under the rule it cites or `panel/open-finding`, and waits for `review_outcome`, and exit 2 holds until the round is recorded.

Read `review_scope.json` and spawn only the decisions that aren't `keep`, as at scrutiny. In a full round every seat is `full` and is handed its own unclosed findings, which it answers by id. Any other round keeps every seat and plans at most one run, the panel's re-verifier (seat `reverifier`): it answers each due finding by id with `holds` or `reverified` and, when its decision carries `fix_review`, reviews the fix diff against every panel's criteria. It reads the `review-packet.sh recheck --seat reverifier` packet the phase file's commissioning line gives. Record every run with `panel-scope.sh --record review` after the round; `review_recorded` holds the passing routes and `blocking_retry` until you have. A carried panel submits nothing and neither spends nor resets the retry count below.

Submit nothing when the panel passes. While `review_verdict` exits 1, submit `review_outcome: blocking_retry` when the findings are correctable (it routes to `implementation`, where the coder agent addresses them), or `blocking_escalate` when the work cannot proceed without escalation; `blocking_escalate` is also taken while the gate exits 2. Include `failure_reason` for `blocking_escalate`. Neither value is accepted while the gate exits 0.
Where a passing panel goes depends on the run's review level: at `standard` it goes to `verification` with no QA panel; at `full`, or with no level recorded, to `qa_validation`.

The `level_unchanged` gate holds every passing route, the carried one included, when `REVIEW_LEVEL` no longer matches the level ledger's last level: the variable was changed by hand after the review-level check. Its `hold:` line names both levels. Put the variable back with `"{{PLUGIN_ROOT}}/skills/work-on/scripts/review-level.sh" set "{{SESSION_NAME}}" <the ledger's level>` and tick again. A level change goes through `set`, which records it in the ledger; a hand rebind never moves the run.

Retry cap: the blocking retries in a run are shared by scrutiny, review, qa_validation and light_review and follow progress. The first 2 are granted whatever the counts. A third is granted only when this panel's count of blocking findings is lower than on its own previous blocking round in this run, and no run gets more than 3. `panel-retry-budget.sh` applies the rule and records each retry it grants in the context key `panel_retries`, so before running the retry loop, run `"{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-retry-budget.sh" "{{SESSION_NAME}}" review` once for the round. It takes no count: it reads the panel's unclosed blocking findings from the ledger itself (`panel-scope.sh --open-count`), the same set `review_verdict` printed, so the count it compares is never the agent's. Exit 0 grants the retry: run the retry loop, which submits `blocking_retry`. Any other exit refuses it: submit `blocking_escalate` with the reason it printed as `failure_reason`, which ends the run at `done_blocked`. The rule is docs/decisions/DECISION-work-on-panel-retry-progress-cap-2026-10-01.md. The cap lives here until koto can count defects per round and enforce it, with the same rule.

## qa_validation

Run the QA validation panel. Read `references/phases/phase-4c-qa.md` for detailed steps. Its `review-packet.sh code --issue` packet takes `--issue-repo "{{ISSUE_REPO}}"`, as written here, empty or not. The round's record is the verdict ledger, written by `panel-scope.sh --record qa`; `qa_results.json` is optional, the round's summary for a reader, and no gate reads it.

koto decides whether the panel passed, from the ledger, as at scrutiny: the `qa_verdict` gate runs `panel-scope.sh --verdict qa`. Each failed scenario is a finding marked `severity: blocking`. Exit 0 advances to `verification` with nothing submitted, exit 1 (a failed scenario is unclosed) prints one finding per unclosed failed scenario, under the rule it cites or `panel/open-finding`, and waits for `qa_outcome`, and exit 2 holds until the round is recorded.

Read `qa_scope.json` for what runs: in a full round the tester runs a full validation and answers its own unclosed failures by id; any other round keeps the tester and plans at most one run, the panel's re-verifier, which runs each due failing scenario again and answers it by id with `holds` or `reverified`, reading the `review-packet.sh recheck --seat reverifier` packet the phase file's commissioning line gives. Record every run with `panel-scope.sh --record qa` after the round; `qa_recorded` holds the passing route and `blocking_retry` until you have. A carried panel submits nothing and neither spends nor resets the retry count below.

Submit nothing when QA passes. While `qa_verdict` exits 1, submit `qa_outcome: blocking_retry` when the defects are correctable, or `blocking_escalate` when they cannot be resolved without escalation; `blocking_escalate` is also taken while the gate exits 2. Include `failure_reason` for `blocking_escalate`. Neither value is accepted while the gate exits 0.

Retry cap: the blocking retries in a run are shared by scrutiny, review, qa_validation and light_review and follow progress. The first 2 are granted whatever the counts. A third is granted only when this panel's count of failed scenarios is lower than on its own previous blocking round in this run, and no run gets more than 3. `panel-retry-budget.sh` applies the rule and records each retry it grants in the context key `panel_retries`, so before running the retry loop, run `"{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-retry-budget.sh" "{{SESSION_NAME}}" qa_validation` once for the round. It takes no count: it reads the panel's unclosed blocking findings from the ledger itself (`panel-scope.sh --open-count`), the same set `qa_verdict` printed, so the count it compares is never the agent's. Exit 0 grants the retry: run the retry loop, which submits `blocking_retry`. Any other exit refuses it: submit `blocking_escalate` with the reason it printed as `failure_reason`, which ends the run at `done_blocked`. The rule is docs/decisions/DECISION-work-on-panel-retry-progress-cap-2026-10-01.md. The cap lives here until koto can count defects per round and enforce it, with the same rule.

## light_review

Run the light panel, the one panel of the `light` review level: a single reviewer seat in place of scrutiny, review and QA. Read `references/phases/phase-4d-light.md` for the seat's commissioning and prompt. Its `review-packet.sh code --issue` packet takes `--issue-repo "{{ISSUE_REPO}}"`, as written here, empty or not. The round's record is the verdict ledger, written by `panel-scope.sh --record light`; `light_results.json` is optional, the round's summary for a reader, and no gate reads it.

koto decides whether the panel passed, from the ledger, as at scrutiny: the `light_verdict` gate runs `panel-scope.sh --verdict light`, and each finding's `severity` decides the seat's verdict. Exit 0 advances to `verification` with nothing submitted, exit 1 (a blocking finding is unclosed) prints one finding per unclosed blocking finding, under the rule it cites or `panel/open-finding`, and waits for `light_outcome`, and exit 2 holds until the round is recorded.

The `has_commits` gate also has to pass: the panel does not advance while this run has no commits since `impl_base`. If it is committed and the panel still holds on `has_commits`, `impl_base` is missing or was recorded after the work (compare `koto context get {{SESSION_NAME}} impl_base` with `git log`): record the commit the run started from, the parent of its first commit, with `git rev-parse <commit> | koto context add {{SESSION_NAME}} impl_base`, and tick again.

Read `light_scope.json` and spawn only the decisions that aren't `keep`, as at scrutiny. In a full round every seat is `full` and is handed its own unclosed findings, which it answers by id. Any other round keeps every seat and plans at most one run, the panel's re-verifier (seat `reverifier`): it answers each due finding by id with `holds` or `reverified` and, when its decision carries `fix_review`, reviews the fix diff against every panel's criteria. It reads the `review-packet.sh recheck --seat reverifier` packet the phase file's commissioning line gives. Record every run with `panel-scope.sh --record light` after the round; `light_recorded` holds the passing route and `blocking_retry` until you have. When nothing runs and no blocking finding is unclosed, koto carries the verdict and advances without stopping here.

The `level_unchanged` gate holds both passing routes, the carried one included, when `REVIEW_LEVEL` no longer matches the level ledger's last level (`light`): the variable was changed by hand after the review-level check. Put it back with `"{{PLUGIN_ROOT}}/skills/work-on/scripts/review-level.sh" set "{{SESSION_NAME}}" light` and tick again. A level change goes through `set`, which records it in the ledger; a hand rebind never moves the run.

Submit nothing when the seat passes (the run goes to `verification`). While `light_verdict` exits 1, submit `light_outcome: blocking_retry` when the findings are correctable (it routes to `implementation`, and the run comes back through the review-level check, which may raise the level), or `blocking_escalate` when the work cannot proceed without escalation; `blocking_escalate` is also taken while the gate exits 2. Include `failure_reason` for `blocking_escalate`. Neither value is accepted while the gate exits 0.

Retry cap: retries from this panel share the run's blocking retries with scrutiny, review and qa_validation, under the rule the scrutiny directive states: the first 2 are granted whatever the counts, a third only when this panel's count of blocking findings is lower than on its own previous blocking round in this run, and no run gets more than 3. Before running the retry loop, run `"{{PLUGIN_ROOT}}/skills/work-on/scripts/panel-retry-budget.sh" "{{SESSION_NAME}}" light_review` once for the round. It takes no count: it reads the panel's unclosed blocking findings from the ledger itself (`panel-scope.sh --open-count`), the same set `light_verdict` printed, so the count it compares is never the agent's. Exit 0 grants the retry: run the retry loop, which submits `blocking_retry`. Any other exit refuses it: submit `blocking_escalate` with the reason it printed as `failure_reason`. The rule is docs/decisions/DECISION-work-on-panel-retry-progress-cap-2026-10-01.md. The cap lives here until koto can count defects per round and enforce it, with the same rule.

## verification

koto runs this state itself; don't run the commands yourself. What it runs is the
definition-of-done gate, and koto follows the `## Definition of Done` section of SKILL.md
for the full procedure: read the project's verification map, classify the issue's
changed files against it, run each matched command (or the default test command when
nothing matches), and require every run to pass.

On entry koto starts it with `run-verification.sh --start`, which reads the
verification map committed at the merge-base with the default branch, selects the
commands for this branch's changed files, and starts them in a bounded, detached
supervisor. The `verification_verdict` gate runs `check-verification.sh --verdict`
on the result and koto routes on it, with no evidence from you:

- **exit 0**: every selected command ran and passed. The run goes to `pass_counting`.
- **exit 1**: a command ran and did not pass. The run returns to `implementation`
  to fix the failure, and koto clears the panel results and `summary.md` as it
  enters there, so the panels judge the fixed code.
- **exit 3**: no verification map at the merge-base, a map that does not parse, or
  a map that selects nothing for this change. Fails closed at `done_blocked`.
- **exit 4**: a command needs a person (`unattended: false`), timed out, grew past
  its `max_procs`, could not start, or tracked files had uncommitted changes.
  Fails closed at `done_blocked`.
- **exit 75**: no result for this head yet. The gate is pending: koto re-checks it
  every 15 seconds for up to eight minutes of one tick, and the response says when
  to tick again (`poll.retry_after_secs`). Tick again with
  `koto next {{SESSION_NAME}} --no-cleanup`, submitting nothing; the wait lasts up to
  two hours.
- **exit 2**: the result could not be read. The state holds.
- **exit -1**: koto killed the check at its own per-run timeout or could not start
  it. The state holds; tick again, and submit `verification_status: blocked` if it
  keeps happening.

If the two-hour wait passes with no result, the gate reports `timed_out` and still
reads exit 75; nothing more will arrive, so submit `verification_status: blocked`.
The run itself stops at two hours too: a command still running then is killed and
reported as `verification/timed-out` (exit 4).

Commit everything before ticking into this state: a tracked file with uncommitted
changes is exit 4, since the paths selected and the code tested would differ.

Announce which commands ran and their results.
They are in the result koto records as `verification_results.json` (`koto context get {{SESSION_NAME}} verification_results.json`):
each command's id, argv, exit status, duration, and whether it timed out or was
killed for runaway growth. Each command's log is beside it, under
`${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/verification/{{SESSION_NAME}}/<head>/`.

If koto could not start the run (the action's fallback is shown above), the wait
timed out, or the gate holds on exit 2 or -1 and the cause can't be fixed, submit `verification_status: blocked`
with the reason in `detail`. The run stops at `done_blocked`.

Evidence schema (only when the run can't settle):
- `verification_status`: `blocked`
- `detail`: why verification could not run or be read

## verification_deferred

koto passes through this state without stopping, and nothing here runs a
command. The run was started with `VERIFICATION=hosted-ci`, so it came here
instead of `verification`: local verification did not run, and the verification
map was never launched. The stated reason, `VERIFICATION_DEFERRAL_REASON`, is in
context as `verification_deferral`
(`koto context get {{SESSION_NAME}} verification_deferral`).

The run goes on to `pass_counting`, then `finalization`. The pull request's hosted
CI is the build of record: `pr_creation` holds until the pull request body records
the deferral, and `ci_monitor` requires that CI green. A run that chose the deferral
without a reason stops at `done_blocked` instead; start it again with both
variables, or without the deferral.

## pass_counting

A check passed, and koto counts the pass here before the run finalizes
(`references/red-first.md`). Two gates must pass.

`fix_green` passes at once for a unit that isn't a fix. A fix needs its green: the
red's command re-run at HEAD, exiting 0. Record it:

```bash
"{{PLUGIN_ROOT}}/skills/work-on/scripts/red-first.sh" green "{{SESSION_NAME}}"
```

It runs the command in a temporary worktree of the committed HEAD, records the
result, and exits 0 when the check passed. A green recorded before a later commit
no longer counts; record it again. When the green exits non-zero (`failed:`), the
fix doesn't pass its own check: submit `counting_status: green_failed` and the run
returns to `implementation`.

`tests_counted` passes when no test file in the unit's committed diff was edited
(only added tests, or none) and no observation is recorded. An edited test (a line
removed, a file deleted, a rename with a change) or an observation holds the unit,
one `held:` line each:

```bash
"{{PLUGIN_ROOT}}/skills/work-on/scripts/test-change.sh" status "{{SESSION_NAME}}"
```

`held: unaccepted <path>`, `held: changed since acceptance <path>` and
`held: overruled <path> by <identity>` need an acceptance from someone other than
this run. You can't give it: the rule refuses the run's own identity
(`agent:{{SESSION_NAME}}`) and any reviewer name the run didn't mint. An overruled
edit needs an acceptance at or above the overruling's authority, which a seat
can't give: stop and report it.

**A repository that requires a person.** When `status` prints a
`person-required:` line, the repository declares `## Test Change Acceptance:
person`, and no agent can accept: `seat` refuses, and an agent's accept is
refused `person-required`. Commission nothing. Stop here and report the held
files and the exact command `status` printed, which a person runs in their own
terminal; it shows them the edited hunks and a code to type back. The run stays
at `pass_counting`; once the person has accepted, resuming it ticks the gate and
goes on to `finalization`.

Otherwise, mint one acceptance seat and print its brief:

```bash
"{{PLUGIN_ROOT}}/skills/work-on/scripts/test-change.sh" seat "{{SESSION_NAME}}"
```

The first line is the seat's identity (`agent:{{SESSION_NAME}}/accept-<n>`); the rest
is the brief. Spawn one seat with the Agent tool on the same commissioning as the
`light` panel's seat (`model: "sonnet"`, per
`${CLAUDE_PLUGIN_ROOT}/references/review-seat-commissioning.md`), and give it the
brief exactly as printed, with nothing added: the script fixes its text, and the
seat treats everything inside its data markers as data. The seat runs
`test-change.sh accept` or `decline` itself, under its minted identity. Then tick
with nothing submitted. An accepted unit goes on to `finalization` with no stop
for a person. `pr_precheck` runs the same status again before a pull request
opens, so a commit made after this count that edits a test sends the run back
here (`precheck_status: recount`).

When the seat declines (`held: declined <path> by <seat>`), submit
`counting_status: declined`: the run returns to `implementation`, where the edit is
reworked or reverted. The third decline of the same set of paths ends the run at
`done_blocked` on the next tick. A commit after an acceptance holds the changed
file again (`changed since acceptance`); mint a new seat for it. `held: uncommitted
changes` means the work tree has changes the gate can't classify: commit them.
`held: no header` means the ledger `test_change_ledger.jsonl` was never started at
`fix_determination`; that can't be fixed here.

A fix recorded by observations is held by both gates until a seat accepts the pair:
the brief lists the observations, and `check-green` passes once the acceptance
covers both digests.

Submit `counting_status: blocked` with `detail` to stop the run when a hold can't be
cleared.

## finalization

Read `references/phases/phase-5-finalization.md` for cleanup steps and summary
format. Output: koto context keys `summary.md` and `pre_pr.md`, both written here,
before you submit `ready_for_pr` or `deferral_requested`. The deferral edge
doesn't check them, but an approved deferral does, so writing them first keeps
the human's approval from stopping on an edit.

Two records are required, and `ready_for_pr` does not advance without them:

- `summary.md` must contain a `## Changes Made` heading, spelled exactly that way.
- `pre_pr.md` must contain exactly one line `cleanup_commit: <sha>` (7 to 40
  lowercase hex characters) naming a commit that is `HEAD` or an ancestor of it,
  and exactly one line `design_diagram: docs/<path>.md`, naming a file committed
  in `HEAD`'s tree, or `design_diagram: not-applicable: <reason>`. Each line
  starts at the beginning of the line and carries nothing after the value. The
  not-applicable form is hyphenated and carries a reason; the evidence enum
  `not_applicable` at `pre_pr_evidence` is a different thing and does not
  satisfy it. When the issue body carries a `Design:` reference, update that
  diagram now (phase-5 says how), commit it, and record its path.

```bash
cat <<EOF | koto context add {{SESSION_NAME}} pre_pr.md
cleanup_commit: $(git rev-parse HEAD)
design_diagram: not-applicable: no design document is touched
EOF
```

The same checks run again at `pre_pr_evidence`, where a failure ends the
run at `done_blocked`. Here a failure only holds: the submission matches no edge,
the state stays `finalization`, and `blocking_conditions` names the failing gate.
Fix that one artifact with `koto context add` and submit `ready_for_pr` again:

- `summary_exists` or `summary_shape` failed: write `summary.md` with a
  `## Changes Made` section.
- `cleanup_referent` failed: write `cleanup_commit: <sha>` in `pre_pr.md`, the
  sha `git rev-parse HEAD` prints, not a word such as `done` and not a sha typed
  by hand.
- `diagram_referent` failed: write `design_diagram: docs/<path>.md` for a file
  committed in `HEAD`'s tree, or `design_diagram: not-applicable: <reason>`, in
  `pre_pr.md`.
- `commit_convention` failed: a commit this run made (`impl_base..HEAD`, merge
  commits skipped) has a subject that is not a Conventional Commits subject, or
  carries an AI-attribution trailer. Its findings name the commit and the rule
  (`commit/conventional-subject` or `commit/no-ai-trailer`); reword that commit
  and submit again. Rewording rewrites the shas from that commit on, so
  rewrite `pre_pr.md` with the new `git rev-parse HEAD` as `cleanup_commit`
  before you submit. An exit 2 means the check could not decide; run
  `"{{PLUGIN_ROOT}}/skills/work-on/scripts/check-branch-output.sh" --commits --session "{{SESSION_NAME}}"`
  for the reason.

`koto context add` replaces the whole key, so rewrite `pre_pr.md` with both
lines, not just the one that failed.

**`commit_convention`'s output escalates.** The first time a rule fails here,
its finding carries the rule's summary. From the second failed evaluation of
the same rule, the gate's output also carries the rule's full text, or, where
that text can't be printed, the file and line range to read; from the third, a
`::shirabe-check-exit::` line says this state's exit is open. koto's own count
decides each step, not anything you submit. When a commit rule can't
be satisfied, take the exit rather than looping: submit
`finalization_status: check_unsatisfiable` with `check_exit_reason` set to one
sentence saying why. It is accepted only while `commit_convention` fails on a
rule (exit 1), and it ends the run at `done_blocked` through `check_exit`; it
never moves the run past the gate.

koto keeps only a referent gate's exit status, not what it printed. To see why
one failed, run its check yourself; it prints the reason on stderr:

```bash
"{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" --cleanup "{{SESSION_NAME}}"
"{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" --diagram "{{SESSION_NAME}}"
```

If the shell can't run it ("No such file" or "Permission denied"), `PLUGIN_ROOT`
doesn't point at a usable plugin checkout and no edit to `pre_pr.md` will help:
stop and report it rather than rewriting the record. The same applies when the
check passes by hand and the gate still holds: report it rather than editing a
record the check accepts.

Submit `finalization_status: ready_for_pr` only when every acceptance criterion is met.
Submit `issues_found` to return to implementation. If an acceptance criterion is unmet
and you want to defer it, submit `deferral_requested` — this does NOT finalize the issue;
it routes to the `deferral_approval` human gate. There is no self-reported clean deferral
terminal: a deferral is only legitimate once a human approves it.

Evidence schema:
- `finalization_status`: `ready_for_pr`, `deferral_requested`, or `issues_found`

## deferral_approval

A blocking human-approval gate for a deferred acceptance criterion. You arrive here
because finalization reported `deferral_requested` — an acceptance criterion is unmet.
Halt and surface the specific unmet criterion to the human as an explicit decision.

- If the human **approves** the deferral: record it as their decision. Write
  `{"choice": "...", "rationale": "...", "alternatives_considered": ["..."]}` to
  `decision.json` in the run's scratch directory and run
  `koto decisions record <WF> --with-data @<scratch>/decision.json` (the file
  form, as SKILL.md's execution loop says; remove the file after),
  then submit `approval_decision: approved`. The recorded deferral is the audit trail and
  must be surfaced in the PR body (see `references/phases/phase-6-pr.md`).
  By default the body says in plain terms what the change leaves undone; the
  recorded approval goes in it only when the repository opts in to workflow content.
  `approved` holds here, naming the failing gate, when `summary.md` or `pre_pr.md`
  lacks the required shape or names a referent that does not exist. Fix that
  artifact with `koto context add` and submit again: `summary_exists` and
  `summary_shape` need a `summary.md` with a `## Changes Made` heading;
  `cleanup_referent` needs `cleanup_commit: <sha>` in `pre_pr.md`, naming a
  commit that is `HEAD` or an ancestor of it;
  `diagram_referent` needs `design_diagram: docs/<path>.md` for a file in
  `HEAD`'s tree, or `design_diagram: not-applicable: <reason>`, in `pre_pr.md`;
  `commit_convention` needs every commit this run made to carry a Conventional
  Commits subject and no AI-attribution trailer, as the `finalization` section says.
  For why a referent gate failed, run its check by hand as the `finalization`
  section says; the same stop rule applies when the check itself can't run.
- If the human **rejects** the deferral: the issue is not done. Submit
  `approval_decision: rejected` with `deferral_detail` — this routes to `done_blocked`.

Evidence schema:
- `approval_decision`: `approved` or `rejected`
- `deferral_detail`: the unmet criterion and the human's rationale

## pre_pr_evidence

The finishing obligations that can be decided before a pull request exists.
`pre_pr.md` was written and checked at `finalization`; don't rewrite it here.
The one exception is history rewritten since then (an amend of the reviewed
commit; catching up with main is a merge, which rewrites nothing): its old sha
is no longer in `HEAD`'s history and the gate fails. A failure here ends the run rather than holding it, so if you rewrote
history, run
`"{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pre-pr-referents.sh" --cleanup "{{SESSION_NAME}}"`
before submitting, and on a failure rewrite `pre_pr.md` with the reviewed
commit's new sha, keeping its `design_diagram` line (`koto context add`
replaces the whole key). If the check can't run at all, stop and report it, as
the `finalization` section says, rather than submitting.

The two lines of `pre_pr.md` are the referents:

`cleanup_commit` is the commit whose diff you reviewed for debug statements,
commented-out code, addressed TODOs and unused imports. `design_diagram` is the
path of the diagram you updated, or `not-applicable: <reason>` when the change
touches no design document. Both are checked for existence: the commit must be
`HEAD` or an ancestor of it and the path a file in `HEAD`'s tree, so a word, or a sha or path
that names nothing, fails the state rather than satisfying it — that is the
point of asking for them rather than for a claim that the work was done.

Submit `pre_pr_status: recorded` with `cleanup_done` (`removed` or
`none_found`) and `design_diagram` (`updated` or `not_applicable`). The
evidence value is the underscored enum; the `pre_pr.md` line is the hyphenated
form with a reason. They are different fields and neither accepts the other's
spelling.

If an obligation cannot be met, submit `pre_pr_status: blocked` instead of
recording a referent you cannot stand behind.

The gates check the summary's shape, every commit's subject (`commit_convention`, through `check-branch-output.sh --commits`) against
Conventional Commits, and the two referents. A failing one stops the run before
the pull request is opened, with the reason naming which. The shape, commit and referent
checks already held at `finalization`, so here they are the backstop. The tip
moving after finalization doesn't invalidate `cleanup_commit`: a commit that was
`HEAD` then is an ancestor of `HEAD` now.

## pr_precheck

Reading the branch this work is on, before the pull request is opened. koto runs the read itself on entry; you only see this state if it could not, or if a gate below holds.

The gate beside it refuses the default branch. It is the last check before a pull request exists, and the only one at that point.

One more gate checks what the branch carries, and holds the state until it passes, naming itself with a `::koto-finding::` per violation:

- `branch_docs_visibility` runs `check-branch-output.sh --docs-visibility --session {{SESSION_NAME}}`: every `docs/` document this run changed passes `shirabe validate` at the repository's declared visibility (`docs/private-only-type`, `docs/visibility-vision-sections`, `docs/visibility-strategy-sections`). Fix the document, commit, and tick again.

An exit 2 means the check could not decide (a missing `shirabe` or `jq`, an unreadable range); run the command by hand, through `{{PLUGIN_ROOT}}/skills/work-on/scripts/check-branch-output.sh`, for the reason. On `SHARED_BRANCH` it passes at once: this child opens no pull request, and `/execute` checks the shared branch before it finalizes its own.

`tests_still_counted` re-runs `"{{PLUGIN_ROOT}}/skills/work-on/scripts/test-change.sh" status "{{SESSION_NAME}}"`, the gate `pass_counting` passed. A commit made since then that edits a test, or changes one that was accepted, holds here (`held:` lines name the file). Submit `precheck_status: recount` to go back to `pass_counting`, where it is accepted as before; nothing else moves the run past this gate while it holds. `held: decline-limit` (the gate exits 3) also takes `recount`, and `pass_counting` then ends the run at `done_blocked`.

The branch name is delivered to `pr_creation` and `ci_monitor` as `BRANCH`, so neither recovers it again.

Submit `precheck_status: override` to proceed from the default branch anyway, or `blocked` with `detail` to stop. `override` still needs `branch_docs_visibility` to pass. On the passing path submit nothing -- the run advances on its own.

`branch_docs_visibility`'s output escalates. The first time a rule fails here, its finding carries the rule's summary. From the second failed evaluation of the same rule, the gate's output also carries the rule's full text, or, where that text can't be printed, the file and line range to read; from the third, a `::shirabe-check-exit::` line says this state's exit is open. koto's own count decides each step. When a documents rule can't be satisfied, take the exit rather than looping: submit `precheck_status: check_unsatisfiable` with `check_exit_reason` set to one sentence saying why. It is accepted only while `branch_docs_visibility` fails on a rule (exit 1), and it ends the run at `done_blocked` through `check_exit`; it never moves the run past the gate.

## pr_creation

If `SHARED_BRANCH` is set, this child is running on the orchestrator's shared
branch and the orchestrator owns the PR. Submit `pr_status: shared` — no PR
creation step is needed here. `shared` advances only when `SHARED_BRANCH` is set;
a run without it opens its own pull request.

Otherwise, read `references/phases/phase-6-pr.md` for PR format, pre-PR
verification, and push instructions.

Author the title and body to the mechanical rule in `{{PR_BODY_RULES}}`, which
`shirabe validate --pr-body` enforces in CI, and in the prose of both write to
`skills/writing-style`: the gate below also holds on a banned word from its
rules (`pr-body/banned-word`), a check that runs here, not in CI.

Check if a PR already exists: `gh pr list --head {{BRANCH}}`

Push with `git push -u origin {{BRANCH}}`. `pr_precheck` read the branch and it is already interpolated above; do not recover it again.

`gh pr create` stays with you, permanently: its successful exit is the externally visible event -- reviewers notified, a number allocated, automation triggered -- and closing the pull request afterwards undoes its state and not the notifications.

The body closes the issue in Part 2, and the `closing_keyword` gate reads it from
GitHub: `Fixes #<N>` for an issue in this repository, or, for a run initialized with
`ISSUE_REPO` (an issue in another repository), `Fixes <owner/repo>#<N>` with that
repository and no other closing reference to `<N>`: a bare `#<N>`, `GH-<N>`, this
repository's `owner/repo#<N>` or its issue URL, the markdown link
`[#<N>](<its issue URL>)`, or any of them under a name this repository had before a
rename would close this repository's issue `<N>`. When the gate holds because a lookup
of another repository failed or ran out of time (its script exits 3), submit
`pr_status: created` again; if that repository keeps failing, turn the reference the
message names into plain text, and close that issue by hand if it should close.
`references/phases/phase-6-pr.md` has the rule.

Submit `pr_url`, the pull request's URL, with every `pr_status: created`. koto
records it, and when this run answers a caller's leg it is the `pr` the caller
reads from the run's result.

`pr_status: created` advances only when the `pr_body_conformant` gate passes. It
runs `check-pr-output.sh --pr-body`, which reads the pull request's title and body
from GitHub and checks them with `shirabe validate --pr-body` against the PR-body
conformance rules and the writing-style banned words. On a violation the state
holds and each finding names the rule it breaks; a banned word is
`pr-body/banned-word`, with the word, its line or the title, and what to use
instead. Fix the title or body with `gh pr edit` and submit `pr_status: created`
again. An exit 2 means the check could not decide (no pull
request for the branch, `gh` or `shirabe` missing); run
`"{{PLUGIN_ROOT}}/skills/work-on/scripts/check-pr-output.sh" --pr-body` for the reason.

Write the body about the change and how it was verified, in terms a reader of
this repository understands. By default that means no review panel table, no
override or deferral notes, no session, state or ledger names, no pointers to
PLAN or ROADMAP files: those records stay in this run's session. The repository
can opt in to them:
`"{{PLUGIN_ROOT}}/scripts/pr-workflow-content.sh"` prints `include` when it
declares `## PR Workflow Content: include`, and `omit`, the default, otherwise.
Under `omit` the `pr_body_conformant` gate also holds on a `## Review panel`
heading or table, a `Plan:` or `Roadmap:` line, or an `Implements` line naming a
PLAN or ROADMAP file (`pr-body/workflow-content`); `references/phases/phase-6-pr.md`
says what goes where under each.

A run that deferred verification to hosted CI (it passed through
`verification_deferred`, and `verification_deferral` is in context) says so in
plain terms under `omit`: the body's Verification section says hosted CI verified
the change, and the reason stays in context. Under `include` it records the
deferral in Part 2, under a `Verification` heading, with the three lines
`references/phases/phase-6-pr.md` gives: that local verification did not run,
`Reason: ` followed by the `verification_deferral` value verbatim, and that
hosted CI is the build of record for this change.

`pr_status: created` also needs the `verification_deferral_recorded` gate to
pass. It runs `check-pr-output.sh --deferral-record --reason <reason>`. Under
`omit` it passes without reading GitHub. Under `include` it reads the body from
GitHub and holds the state until it says local verification did not run, has the
line `Reason: <reason>` exactly and whole (the reason anywhere else in the body
doesn't count), and says hosted CI is the build of record. Fix the body with
`gh pr edit` and submit `pr_status: created` again. On a run that didn't defer
the gate passes without running anything.

The gate's output escalates. The first time a rule fails here, its finding
carries the rule's summary. From the second failed evaluation of the same
rule, the output also carries the rule's full text, or, where that text can't
be printed, the file and line range to read; from the third, a
`::shirabe-check-exit::` line says this state's exit is open. koto's own count
decides each step. When a title or body rule can't be satisfied, take the exit
rather than looping: first mark the pull request draft
(`gh pr ready --undo`) so nobody reads it as finished, then submit
`pr_status: check_unsatisfiable` with `check_exit_reason` set to one sentence
saying why. It is accepted only while `pr_body_conformant` fails on a rule
(exit 1), and it ends the run at `done_blocked` through `check_exit`; it never
moves the run past the gate.

Retry cap: self-loop with `creation_failed_retry` up to 3 times. After 3, use
`creation_failed_escalate`. The cap lives here until koto enforces it from its
attempt counts, with the same number.

`koto rewind` doesn't reopen a round. From `done` it steps back to this state
only, and the next submission returns to `done`, so rewinding again and again
just flips between the two. A fix that review or CI asks for after the run
reaches `done` is a fix round, started from `done` with
`"{{PLUGIN_ROOT}}/skills/work-on/scripts/fix-round.sh" start --from` and this
run's session name; the `done` directive says how.

## check_exit

koto passes through this state to `done_blocked` without stopping. There is
nothing to submit: the run took a check's named exit, and `failure_reason`
already says which state, which gate and why.

## ci_monitor

Read `references/phases/phase-6-pr.md` for CI monitoring.

koto routes green CI itself, so on the passing path you submit nothing. With
every check on the current head green and the pull request not DIRTY, the run
goes on to `ci_pass_counting`, which counts the pass and then decides whether the
run is the root (the cascade) or a child (`done`). A DIRTY pull request stops at
`done_blocked` whatever its CI reads, since GitHub runs no checks on one.

A repository that cancels a closed pull request's unfinished macOS floor runs
(it has `scripts/check-macos-floor-setup.sh`, as shirabe does) can leave a
MERGED pull request with cancelled checks that nothing failed. `ci_passing`
passes once GitHub reports the pull request MERGED and every check that isn't
green is a cancelled run of one of the workflows that script's `--workflows`
lists. The run then routes as green, and `ci_cancelled_after_merge.txt` in
context names those checks: mention them in your final report. A cancel on an
open pull request, a failed or pending check, and a cancel outside those
workflows still fail the gate.

A pull request with no checks at all is not green. Just after a push, before
GitHub creates the check suites, `gh pr checks` answers `no checks reported`:
that is pending, and the state holds on `ci_passing` exactly as it does while a
check runs. If no check has appeared 10 minutes after the push, CI is not
running for this pull request: submit `ci_outcome: failing_unresolvable` with a
rationale saying no checks were reported on the head and since when. The one
exception is a repository that has no hosted CI and says so: its default
branch carries `.claude/shirabe-extensions/hosted-ci.json` with
`"hosted_ci": "none"` and a one-line `"reason"`. Then the gate passes a pull
request with no checks once its body records the exception (a line saying the
repository declares no hosted CI, and the line `Reason: <reason>` with the
reason verbatim), and
`ci_none_declared.txt` in context names it: mention it in your final report.
The gate's stderr says what the body is missing. Never add or edit that file to
get past this gate; a pull request can't declare itself, since the gate reads
the default branch.

Read the checks yourself the way the gate does, with
`"{{PLUGIN_ROOT}}/skills/work-on/scripts/pr-checks.sh"` in place of
`gh pr checks` (the same arguments). Where the token can read checks it is
`gh pr checks`. Where GitHub refuses the check read, it says so on stderr and
lists the Actions jobs at the head and the commit's statuses instead; a
required check it lists as `unreadable` is one neither answers, which may be a
check run the token can't see. That never passes the gate: if every other
check is green, submit `ci_outcome: failing_unresolvable` naming the
unreadable check, since a person who can see it, or a token that can read
checks, is what settles it. Never strip or swap the token to read checks.

While checks are still running the state holds on `ci_passing`; tick again once
they finish. If the gate fails, fix what you can, push, and submit
`ci_outcome: failing_fixed`: the run comes back to this state, and the gates
re-check CI on the new push.
If unresolvable, submit `ci_outcome: failing_unresolvable` with rationale.
Both values are accepted only while `ci_passing` fails on a pull request that
isn't DIRTY.

Retry cap: 3 fix pushes. When CI is still failing after the third, submit
`ci_outcome: failing_unresolvable` with rationale, which ends the run at
`done_blocked`. In an unattended run, don't ask the user instead: nobody is
there to answer. The cap lives here until koto enforces it from its attempt counts, with
the same number.

## ci_pass_counting

CI passed on the open pull request, and the pass is counted again before the run
goes on (`references/red-first.md`): a commit that fixed CI may have edited a
test, or moved HEAD past a fix's green. The two gates are `pass_counting`'s, and
on the passing path you submit nothing.

- `fix_green`: a fix whose green ran at an earlier HEAD holds. Record it again
  with `"{{PLUGIN_ROOT}}/skills/work-on/scripts/red-first.sh" green "{{SESSION_NAME}}"`
  and tick; a green that exits non-zero is `counting_status: green_failed`, which
  returns the run to `ci_monitor` to fix and push.
- `tests_counted`: `"{{PLUGIN_ROOT}}/skills/work-on/scripts/test-change.sh" status "{{SESSION_NAME}}"`.
  An edited test held here is accepted exactly as at `pass_counting`: mint a seat
  with `test-change.sh seat` and commission it with the brief, or, in a
  repository that requires a person, stop and report the command `status`
  prints. A decline is `counting_status: declined`, back to `ci_monitor`, where
  the edit is reworked or reverted and pushed; the third decline of the same
  paths ends at `done_blocked`.

Once both pass, the `is_root` gate decides where the run goes: it runs
`"{{PLUGIN_ROOT}}/skills/work-on/scripts/session-role.sh" {{SESSION_NAME}}`, which
reads koto's own `parent_workflow`, and passes only when it prints exactly `root`.
A root goes on to `cascade_entry`; a child, or a lookup the script could not
complete (it then answers `child`), goes to `done`. That is the safe direction: a
child that wrongly stops has landed its pull request and left the chain for the run
that owns it, while a child that wrongly cascades deletes a PLAN its siblings are
still working from. When the gate exits 2 the role was never decided (PLUGIN_ROOT
does not reach the script, or the script failed): the state holds rather than
choosing either way. Read the gate's stderr, fix the cause, and tick again.

Submit `counting_status: blocked` with `detail` to stop the run when a hold can't
be cleared.

## cascade_entry

No action. This state decides whether the issue has a PLAN behind it and routes
accordingly; every outcome advances without evidence, so you will normally not
see this state at all.

There is a third outcome, and it does not stop here: the finder exits 2 when it
cannot decide, and the run ends at done_blocked with the reason. Uncertainty is
never treated as absence, because the absence edge is the silent one — skipping
a cascade that was owed would tell nobody.

## cascade_run

Run the document-chain cascade for the PLAN that sequences this issue, then
report what it did.

```bash
PLAN=$(${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/find-anchor-plan.sh "{{ISSUE_NUMBER}}" "{{PLAN_DOC}}")
RESULT=$(${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/run-cascade.sh --push "$PLAN")
```

Take the PLAN path from the finder, never from a search of your own.

Then observe what the repository actually shows:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/verify-cascade-commit.sh "$PLAN"
```

Submit `cascade_status` from the script's own verdict, and `post_state` from the
verifier's exit code: 0 `verified`, 2 `plan_present`, 3 `no_commit`, 4
`wrong_status`, 5 `not_in_commit`, 6 `undecided`. Add `anchor_plan` (the PLAN
path) and `finalization_commit` (the sha the verifier read), and `cascade_detail`
summarising which transitions ran.

**Do not treat the script's step-level `ok` as evidence that the chain moved.**
Several of its operations report `ok` having changed nothing, and its own
post-cascade verification reads the working tree rather than the commit, so a
document transitioned on disk but missing from the finalization commit satisfies
every check it makes. That is what the verifier is for: it establishes the PLAN
absent from disk, each upstream document at its terminal posture, and the
finalization commit CONTAINING each of those documents — the last read from the
commit's own path list, never from the tree. Read its stderr if it fails; koto
keeps the exit code, not the diagnostics.

A `partial` verdict halts the run. The two shapes differ in what recovery means,
and `/execute`'s `plan_completion` directive is the authority for both — read it
there rather than reasoning from here, so two callers of one script cannot come
to disagree about what a partial result means. A refused transition *without*
`commit` and `push` at `ok` published nothing, so recovery is local. One *with*
them published what it reached: the remote carries that commit, and recovery is
a follow-up commit or a revert rather than a reset. Inspect the `steps` array to
tell which shape you have; the verdict alone does not say.

## done

The workflow is complete. The PR has been created and CI is passing.

If `koto context exists {{SESSION_NAME}} ci_cancelled_after_merge.txt` succeeds,
CI passed on a MERGED pull request with cancelled macOS floor checks: read it
with `koto context get` and name those checks in your final report.

**A fix after `done`.** When review or CI asks for a change to this branch after
the run got here, don't use `koto rewind`: it doesn't reopen a round. From `done`
it reaches `pr_creation` only, and the next submission comes straight back here.
Take a fix round instead, from the branch this run worked on:

```bash
"{{PLUGIN_ROOT}}/skills/work-on/scripts/fix-round.sh" start --from {{SESSION_NAME}}
```

It starts `{{SESSION_NAME}}-fix-<n>`, a new work-on session with this run's
variables and parent (a child stays a child, so it never cascades), and records
the round in both sessions' context: `fix_round.json` in the round, a line in
`fix_rounds.jsonl` here. Drive the round from `entry` with the entry evidence
this run was given, and commit the fix in the round's `implementation`, not
before: the round's `analysis` records HEAD as its `impl_base`, so its review
panels and changed paths cover the fix commits only and its verification runs
at the fix head, while a fix committed earlier falls before the base and out of
the round's review. The script refuses (`refused=<reason>`,
exit 1) while an earlier round is still open (`round-open`), after three
rounds (`cap`; a fourth is a person's call), and from a branch other than
this run's `SHARED_BRANCH` (`wrong-branch`).

The round is a unit like any other. An issue with a fix label makes it a fix
again, so it owes a red at `reproduce`; a review change or a CI repair with no
check that fails on the base records a before-observation there instead
(`references/red-first.md`). Under a parent the round counts in the parent's
children-complete gate while it runs, so a round that ends at `done_blocked` is
the parent's failure too.

A coordinator reads the review round from this session, not the round's. Once
the round's panels pass at the fix head, record it here too with
`"{{PLUGIN_ROOT}}/skills/coordinate/scripts/review-round.sh" record --session {{SESSION_NAME}} <round.json>`,
`reviewed_head` set to the fix head.

## done_already_complete

Analysis confirmed the issue goal is already satisfied by current code. All
acceptance criteria were met before any implementation was needed. No commits
were required. This is a successful terminal state — it is not a failure.

## done_blocked

If the blocker has been resolved externally, use `koto rewind <name>` to walk
back to the originating state. `koto rewind` rewinds one step per call; call
it repeatedly to reach a non-adjacent origin state. For example, if blocked
from ci_monitor, one rewind reaches pr_creation; from analysis, one rewind
reaches the previous state in the path.

## skipped_due_to_dep_failure

This task was skipped because a dependency failed. The parent orchestrator set
`mode: skipped` at entry. No action needed — this terminal state records that the
task was intentionally bypassed due to an upstream failure.
