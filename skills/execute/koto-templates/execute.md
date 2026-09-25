---
# Terminal-tick retention (#360). EVERY `koto next` in this template carries
# --no-cleanup, including the two in spawn_and_await. Without it, the tick that
# reaches a terminal disposes of the session and its ctx/.
#
# Do not restore a carve-out for a tick that looks non-terminal. An earlier
# version of this note had one, reasoning that spawn_and_await routes only to
# pr_finalization or escalate. A tick does not stop at the state it routes to:
# escalate declares required evidence and still exits unconditionally to
# done_blocked, so needs_attention chains straight there and bare it destroyed
# the record of the batch that FAILED.
#
# The rule, the measurements behind it, and the child exception that makes
# work-on.md's position the opposite of this one:
# ../../../references/koto-session-retention.md
#
# scripts/terminal-retention_test.sh pins the flag count, escalate's shape, and
# the chain itself, so a regression here fails rather than going quiet.
#
# A YAML comment, so it reaches a template editor without koto rendering it into
# any state's directive.
#
# Merge and results. After ci_monitor the run decides whether to merge, in koto
# states rather than prose: merge_readiness records a verdict (a default action
# running record-merge-verdict.sh), merge_route routes on it through
# non-overridable context-matches gates, merge_attempt is the agent-run merge
# call behind a non-overridable MERGE gate, and merge_confirm re-reads the PR.
# merge_confirm is the only state with an edge into `merged`. Every edge into a
# terminal assigns `outcome` (and `step` or `reason` only when the edge fixes
# the value as a literal); a value that comes from a script's output is written
# to context by the script, because an assignment cannot read ${context.<k>}.
# Every terminal declares the same result map, which koto writes into the
# workflow result's payload and print-exit.sh renders.
#
# Two gates were renamed on the way, and on purpose: ci_monitor's
# owned_ci_passing and owned_merge_state_clean resolve the PR through
# owned-pr.sh instead of the first `gh pr list --head` hit.
# work-on.md still carries the old commands under the old names
# (ci_passing, merge_state_clean), and scripts/validate-template-mermaid.sh
# check 4 holds one name to one command across templates.
name: execute
version: "1.0"
# koto-floor: pinned -- result maps, constrained and rebindable variables,
# transition context_assignments, and non-overridable gates need koto
# 0.13.0 or later, the floor skills/execute/requires.tsv declares. The
# v0.12.2 floor check (scripts/check-koto-floor.sh) does not cover this template.
description: >
  Plan orchestrator template. Records the run's write set, creates or adopts
  the shared branch and draft PR, spawns per-issue work-on.md children, awaits
  batch completion, finalizes the PR description, marks it ready, monitors CI,
  and decides from a recorded verdict whether the PR merges.
initial_state: write_set_record

variables:
  PLAN_DOC:
    description: Path to the PLAN.md document driving this orchestration run
    required: true
  PLAN_SLUG:
    description: >
      The PLAN's topic slug -- PLAN_DOC's basename with the PLAN- prefix and
      .md suffix stripped, matching ^[a-z0-9-]+$. Declared as a template
      variable because the settled_branch_record and drift_facts actions
      interpolate it into commands koto runs itself (each rebuilds the session
      name as execute-{{PLAN_SLUG}}), and koto resolves and compile-time-validates
      only {{KEY}} references. A shell-style ${PLAN_SLUG} there is passed to
      sh -c untouched and expands to the empty string, which is the defect this
      declaration closes. Not rebindable: it names the session.
    required: true
    pattern: '^[a-z0-9-]+$'
  PLUGIN_ROOT:
    description: >-
      Absolute path to the shirabe plugin root, passed at koto init as
      --var PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT} where the agent's own shell
      expands it. Declared as a template variable because settled_branch_record
      interpolates it into a command koto runs itself, and koto resolves only
      {{KEY}} references -- a shell-style ${CLAUDE_PLUGIN_ROOT} there reaches
      sh -c untouched and expands to the empty string, which
      scripts/check-template-interpolation.sh rejects for exactly that reason.
      A repo-relative path is not the alternative: it resolves against the
      session's execution anchor and therefore only in a checkout of shirabe
      itself. The pattern admits an absolute path with no `..` segment, the
      same literal pattern scope.md declares. Rebindable, so a resumed run
      takes this invocation's plugin root (a plugin update moves it).
    required: true
    pattern: '^/([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+|\.)?(/([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+|\.)?)*$'
    rebind: true
  PAUSE_BEFORE_FINALIZE:
    description: >
      Whether to stop at the paused_for_review terminal after pr_finalization
      assembles the PR body, BEFORE the plan_completion finalization cascade.
      Driven by /execute's execution mode (NOT a user flag): interactive sets it
      true (pause for review with the chain intact), --auto sets it false (drive
      straight through plan_completion to a ready-to-merge, green PR). Resume of a
      paused run re-enters plan_completion with PAUSE_BEFORE_FINALIZE=false.
      Rebindable: every invocation passes it from its own mode, so an attached
      session takes this invocation's value, never an earlier one's.
    required: false
    default: "false"
    values: ["true", "false"]
    rebind: true
  MERGE:
    description: >
      This invocation's merge intent, from /execute's own --merge flag (false
      without it). It is never agent evidence and never inherited: every
      invocation passes it explicitly and koto re-applies it on every accepted
      attach, so a run resumed without --merge cannot merge on an earlier
      invocation's intent, and an attach koto refuses changes nothing.
      merge_readiness hands it to the verdict as --merge, and merge_attempt's
      non-overridable merge_intent gate re-checks it on every tick that
      reaches the state.
    required: false
    default: "false"
    values: ["true", "false"]
    rebind: true

states:
  write_set_record:
    # The run's write set, fixed before anything else happens. A single-pr run
    # writes to one repository, the one it runs in, and every PR lookup and both
    # merge scripts receive it from this record as an explicit argument.
    # record-write-set.sh reads the origin remote (falling back to
    # `gh repo view`), refuses a value outside owner/repo, and refuses to change
    # a value already recorded. The gate reads the key back through koto's own
    # evaluator and is non-overridable: an override would let the agent name the
    # write set the script exists to fix.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/execute/scripts/record-write-set.sh "execute-{{PLAN_SLUG}}"'
      fallback: >-
        koto could not record the run's write set. Read the command's own output
        above: the script exits 65 when neither the origin remote nor
        `gh repo view` names an owner/repo, 66 when the value is outside the
        owner/repo pattern, 67 when a different write set is already recorded,
        and 70 when the context write failed. Fix the cause and tick again; the
        record re-runs on entry. Submit `write_set_status: blocked` with
        `detail` to stop the run if it cannot be fixed.
    gates:
      repos_recorded:
        type: context-matches
        key: repos
        pattern: '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
        overridable: false
    accepts:
      write_set_status:
        type: enum
        values: [blocked]
        description: >-
          Absent on the passing path. The state advances with no evidence when
          the gate passes, so the agent never sees it.
      detail:
        type: string
        description: Why the write set could not be recorded.
    transitions:
      - target: orchestrator_setup
        when:
          gates.repos_recorded.matches: true
      - target: done_blocked
        when:
          gates.repos_recorded.matches: false
          write_set_status: blocked
        context_assignments:
          outcome: error
          step: "execute:write_set_record"
          failure_reason: "write_set_record blocked: ${evidence.detail}"

  orchestrator_setup:
    accepts:
      status:
        type: enum
        values: [completed, override, blocked, pr_adopt, status_read]
        required: true
      detail:
        type: string
        description: Failure reason if blocked
    transitions:
      - target: settled_branch_record
        when:
          status: completed
      - target: settled_branch_record
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          outcome: error
          step: "execute:orchestrator_setup"
          failure_reason: "orchestrator_setup blocked: ${evidence.detail}"
      # adopt-or-create-pr.sh's exit codes, mapped as SKILL.md's owned-PR
      # table says: several owned PRs (or none after a create) is pr-adopt, a
      # failed read is status-read.
      - target: done_blocked
        when:
          status: pr_adopt
        context_assignments:
          outcome: error
          step: "execute:pr-adopt"
          failure_reason: "orchestrator_setup: no single owned PR to adopt: ${evidence.detail}"
      - target: done_blocked
        when:
          status: status_read
        context_assignments:
          outcome: error
          step: "execute:status-read"
          failure_reason: "orchestrator_setup: the PR lookup read failed: ${evidence.detail}"

  settled_branch_record:
    # The settled branch this state records is the ONLY thing that knows which
    # branch children commit to on the adopt path, where the branch is not
    # derivable from the PLAN's name. The gate is what makes that a guarantee
    # rather than an instruction: with the key absent or its value malformed,
    # the success transition does not resolve and the run cannot reach
    # spawn_and_await.
    #
    # Three details are not stylistic:
    #
    #   The pattern is anchored at BOTH ends. context-matches evaluates
    #   Regex::is_match, a substring test, so an unanchored [A-Za-z0-9._/-]+
    #   would pass "main; rm -rf /" because "main" matches. The anchors are
    #   what make this a validator instead of a formality.
    #
    #   The gate must be referenced in a when clause to bind. A failed gate on
    #   a state that has an `accepts` block does NOT block on its own -- it
    #   falls through to transition resolution, and a conditional transition
    #   matching on agent evidence alone still fires. Both transitions below
    #   name the gate; deleting either reference leaves a gate that is
    #   evaluated, reported, and ignored.
    #
    #   There is deliberately no `override` edge. Every other converted state
    #   in shirabe offers one, because an author who knows better than the gate
    #   should be able to proceed. Not here: the recorded branch is where every
    #   child's commits land, so a run that cannot record it must reach a
    #   terminal rather than wave the gate through.
    #
    # This state exists because the recording used to be a block of shell in
    # orchestrator_setup's directive, under five paragraphs explaining that it
    # had to run LAST -- recording before the creation script checked out
    # impl/<slug> stored `main`. A state boundary is what that ordering
    # constraint actually is, and the script the action runs refuses the
    # default branch outright, which the old block could not.
    default_action:
      # The session argument is rebuilt from {{PLAN_SLUG}} rather than written
      # as {{SESSION_NAME}}, and that is not a style choice. Through koto
      # 0.12.1 a default_action command was the one position where
      # {{SESSION_NAME}} did not resolve: a declared variable in the same
      # string resolved, and {{SESSION_NAME}} reached sh -c as the literal
      # seven-character token, so the script wrote its key into a session named
      # "{{SESSION_NAME}}" and the gate on this state then reported the real
      # session's key as absent. koto 0.12.2 fixed that (koto#223, closing
      # koto#220), so on 0.12.2 or later either form works.
      #
      # The reconstruction stays anyway. This template runs under whatever koto
      # the user has installed, and nothing in a template can require a minimum
      # version, so on 0.12.1 or earlier {{SESSION_NAME}} would still reach the
      # shell literally and misrecord the branch in a way that presents as a
      # gate that will not pass. Keeping the rebuilt name is what makes the
      # state correct on every koto that can run it.
      #
      # `execute-<plan-slug>` is the session name /execute's own SKILL.md
      # initializes, and PLAN_SLUG is the same slug it derives it from, so this
      # reconstruction is exact and is checked at compile time -- a typo in the
      # reference is a template error rather than a wrong session.
      command: '{{PLUGIN_ROOT}}/skills/execute/scripts/record-settled-branch.sh "execute-{{PLAN_SLUG}}"'
      capture_stdout_as: SETTLED_BRANCH
      fallback: >-
        koto could not record the settled branch. Read the command's own output
        above: the script refuses a detached HEAD (64), a branch name outside
        ^[A-Za-z0-9._/-]+$ (65), and the repository's default branch (66), and
        it says which one it hit. Check out the branch this run should settle
        on and tick again -- the record re-runs on entry, so nothing needs
        submitting. Submit `status: blocked` with `detail` only if it cannot be
        fixed; there is no override here, because the recorded branch is where
        every child commits.
    gates:
      settled_branch_recorded:
        type: context-matches
        key: settled_branch
        pattern: '^[A-Za-z0-9._/-]+$'
    accepts:
      status:
        type: enum
        values: [blocked]
        description: >-
          Absent on the passing path. The state advances with no evidence when
          the gate passes, so the agent never sees it.
      detail:
        type: string
        description: Why the branch could not be recorded.
    transitions:
      - target: drift_facts
        when:
          gates.settled_branch_recorded.matches: true
      # The gate is named on this edge too, and it has to be: koto rejects a
      # state whose `when` blocks share no fields, so a blocked edge keyed on
      # evidence alone beside a success edge keyed on the gate alone does not
      # compile. Naming `matches: false` is also the more accurate condition --
      # the failure exit exists for the run whose record did not land, which is
      # exactly what a false match means.
      - target: done_blocked
        when:
          gates.settled_branch_recorded.matches: false
          status: blocked
        context_assignments:
          outcome: error
          step: "execute:settled_branch_record"
          failure_reason: "settled_branch_record blocked: ${evidence.detail}"

  drift_facts:
    # Works out, from git alone, whether origin/main moved in a way the PLAN
    # could care about, BEFORE worktree_sync rebases. The order is the point:
    # for a PLAN that exists only on this branch, the base is the branch's fork
    # point, and the rebase moves the fork point to the tip of origin/main. Run
    # after the rebase, every run would read as "main hasn't advanced".
    #
    # The script fetches origin itself, so the rebase in worktree_sync uses
    # exactly the origin/main these facts describe. It writes plan_intent.md
    # first and drift_facts.json second, both capped at 8192 bytes, and prints
    # nothing. drift_facts.json is compact JSON with `route` as its first key,
    # which is what lets the gates here and in worktree_sync match it with an
    # anchored pattern rather than parse it.
    #
    # Both gates are named on the passing edge. plan_intent_recorded is implied
    # by drift_facts_recorded in practice (the script writes the intent first),
    # but it is what names plan_intent.md in a context gate, and a gate that no
    # `when` clause references is evaluated and then ignored.
    #
    # The session argument is rebuilt from {{PLAN_SLUG}} for the reason
    # settled_branch_record's comment gives.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/execute/scripts/drift-facts.sh "execute-{{PLAN_SLUG}}" "{{PLAN_DOC}}"'
      fallback: >-
        koto could not compute the upstream drift facts. Read the command's own
        output above: the script exits 64 when no base resolves (the fetch of
        origin failed, origin/main is missing, or it shares no history with the
        PLAN), 65 when the PLAN doc is missing or outside the repository, and 66
        when writing a context key failed. Fix the cause and tick again -- the
        script re-runs on entry, so nothing needs submitting. Submit
        `facts_status: override` with `detail` to continue to the rebase without
        facts (the drift question is then asked with nothing precomputed), or
        `facts_status: blocked` with `detail` to stop the run.
    gates:
      drift_facts_recorded:
        type: context-matches
        key: drift_facts.json
        pattern: '^\{"route":"(none|judge)",'
      plan_intent_recorded:
        type: context-exists
        key: plan_intent.md
    accepts:
      facts_status:
        type: enum
        values: [override, blocked]
        description: >-
          Absent on the passing path. The state advances with no evidence when
          the gates pass, so the agent never sees it.
      detail:
        type: string
        description: Why the drift facts could not be computed.
    transitions:
      - target: worktree_sync
        when:
          gates.drift_facts_recorded.matches: true
          gates.plan_intent_recorded.exists: true
      - target: worktree_sync
        when:
          gates.drift_facts_recorded.matches: false
          facts_status: override
      - target: done_blocked
        when:
          gates.drift_facts_recorded.matches: false
          facts_status: blocked
        context_assignments:
          outcome: error
          step: "execute:drift_facts"
          failure_reason: "drift_facts blocked: ${evidence.detail}"

  worktree_sync:
    # The mechanical half of the drift check: rebase the shared branch on
    # origin/main. drift_facts already fetched, and computed the facts against
    # the pre-rebase fork point; the judgment, when one is needed, is
    # worktree_discipline_check's.
    #
    # There is no fetch here on purpose. drift_facts fetched immediately
    # before, and a second fetch could move origin/main past what the facts
    # describe, so the run would rebase onto commits nobody examined.
    #
    # The rebased_on_main gate asks the question the rebase was FOR -- is
    # origin/main an ancestor of HEAD -- rather than asking whether the rebase
    # command succeeded. A rebase that exits 0 without achieving it fails the
    # gate, and a rebase that was unnecessary passes without one having run.
    # That is what makes this an independent check rather than a restatement
    # of the action's exit code.
    #
    # The two rebase-in-progress tests are not belt-and-braces. Measured: during
    # a CONFLICTED rebase the ancestor check PASSES on its own, because git has
    # already replayed part of the branch and HEAD does contain origin/main. The
    # ancestor test alone would therefore advance the run with a rebase halted
    # mid-flight and a conflicted worktree. `git rev-parse --git-path` is used
    # rather than a literal .git/ path so this holds in a worktree, where the
    # rebase state lives outside the main .git directory.
    #
    # drift_clear routes the no-drift case. It matches only when drift_facts
    # computed `route: none`, so the single edge to spawn_and_await needs both
    # a clean rebase and facts that say nothing the PLAN references moved.
    # Everything else -- facts that say judge, facts that are absent because
    # drift_facts was overridden, or a rebase the agent overrode -- goes to
    # worktree_discipline_check.
    #
    # Re-running is safe in the two ways that matter. On an already-rebased
    # branch the rebase is a no-op. Mid-conflict, git itself refuses -- "It
    # seems that there is already a rebase-merge directory" -- so the retry
    # reports the conflict again instead of compounding it.
    default_action:
      command: git rebase origin/main
      fallback: >-
        koto could not rebase the shared branch onto origin/main. Read git's own
        output above. A conflict leaves the rebase in progress: resolve it and
        run `git rebase --continue`, or run `git rebase --abort` and rebase by
        hand, then tick again -- the rebase re-runs on entry, so nothing needs
        submitting. Submit `sync_status: override` if the branch is deliberately
        not on top of main, or `blocked` with `detail` if it cannot be resolved.
    gates:
      rebased_on_main:
        type: command
        command: 'git merge-base --is-ancestor origin/main HEAD && test ! -d "$(git rev-parse --git-path rebase-merge)" && test ! -d "$(git rev-parse --git-path rebase-apply)"'
      drift_clear:
        type: context-matches
        key: drift_facts.json
        pattern: '^\{"route":"none",'
    accepts:
      sync_status:
        type: enum
        values: [override, blocked]
        description: >-
          Absent on the passing path. The state advances with no evidence when
          the gate passes, so the agent never sees it.
      detail:
        type: string
        description: Why the branch could not be brought onto main.
    transitions:
      - target: spawn_and_await
        when:
          gates.rebased_on_main.exit_code: 0
          gates.drift_clear.matches: true
      - target: worktree_discipline_check
        when:
          gates.rebased_on_main.exit_code: 0
          gates.drift_clear.matches: false
      - target: worktree_discipline_check
        when:
          gates.rebased_on_main.exit_code: 1
          sync_status: override
      - target: done_blocked
        when:
          gates.rebased_on_main.exit_code: 1
          sync_status: blocked
        context_assignments:
          outcome: error
          step: "execute:worktree_sync"
          failure_reason: "worktree_sync blocked: ${evidence.detail}"

  worktree_discipline_check:
    # The judgment half, and only reached when drift_facts could not rule drift
    # out. It carries no gates: the facts it reasons over were computed and
    # gated upstream (drift_facts.json and plan_intent.md, both written before
    # this state is reached), and a gate on a question state would keep that
    # question from ever being settled without the agent. There is no `none`
    # value either -- the script owns that answer, and worktree_sync routes it
    # straight to spawn_and_await.
    accepts:
      impact:
        type: enum
        values: [informational, intent-changing]
        required: true
        description: >-
          Whether the upstream changes listed in the drift_facts.json context key
          invalidate the PLAN's intent as plan_intent.md states it.
          `informational`: main touched paths the PLAN references, but the PLAN
          still holds as written. `intent-changing`: a file, contract, or fact
          the PLAN depends on was removed or changed so the PLAN no longer holds.
      rationale:
        type: string
        required: false
        description: Rationale required when impact is intent-changing
    transitions:
      - target: spawn_and_await
        when:
          impact: informational
      - target: escalate_upstream_drift
        when:
          impact: intent-changing
        context_assignments:
          failure_reason: "worktree_discipline_check: upstream-drift detected (intent-changing): ${evidence.rationale}"

  escalate_upstream_drift:
    accepts:
      rationale:
        type: string
        required: true
        description: Why the upstream change invalidates the chain's intent
    transitions:
      # The upstream-must-change boundary: the run's re-evaluation exit.
      - target: done_blocked
        context_assignments:
          outcome: error
          step: "execute:re-evaluation"
          failure_reason: "escalate_upstream_drift: ${evidence.rationale}"

  spawn_and_await:
    gates:
      batch_done:
        type: children-complete
    accepts:
      tasks:
        type: tasks
        required: true
    materialize_children:
      from_field: tasks
      failure_policy: skip_dependents
      default_template: ../../work-on/koto-templates/work-on.md
    transitions:
      # The batch_done gate alone routes the batch: no agent inspects children
      # or submits an outcome. The two routes are exclusive because they share
      # all_success with different values; needs_attention on the failure
      # route is what keeps koto's W4 unrouted-failure warning quiet.
      - target: pr_finalization
        when:
          gates.batch_done.all_complete: true
          gates.batch_done.all_success: true
      - target: escalate
        when:
          gates.batch_done.all_complete: true
          gates.batch_done.all_success: false
          gates.batch_done.needs_attention: true

  pr_finalization:
    accepts:
      finalization_status:
        type: enum
        values: [updated, update_failed, pr_adopt, status_read]
        required: true
      pause_decision:
        type: enum
        values: [pause, finalize]
        default: finalize
        description: >
          Mode-driven routing after the PR body is assembled. The agent reads
          the {{PAUSE_BEFORE_FINALIZE}} variable and submits `pause` when it is
          `true` (interactive mode: stop at paused_for_review with the chain
          intact) or `finalize` when it is `false` (--auto mode: drive straight
          through plan_completion). Defaults to `finalize` so a submission that
          omits it (e.g. an `update_failed` run, or a fresh non-paused run that
          leaves it unset) preserves today's default path (R7). On a resume of a
          paused run it is `finalize` because resume re-enters with
          PAUSE_BEFORE_FINALIZE=false.
    transitions:
      # Reordered for the DRAFT-vs-READY discipline (#117): the
      # cascade (plan_completion) runs BEFORE gh pr ready so the
      # chain is at its strict-mode passing state when CI re-runs on
      # the ready_for_review event. The cascade lives in
      # plan_completion; pr_finalization here only updates the PR
      # body and confirms `gh pr ready` is NOT yet invoked.
      #
      # D2 (execute-friction): the single `updated` edge is split into
      # two guarded edges driven by the mode-derived PAUSE_BEFORE_FINALIZE
      # variable, which the agent reflects into the pause_decision evidence
      # field. When pause_decision is `pause` (interactive), route to the
      # non-failure terminal paused_for_review (chain intact, PR DRAFT). When
      # `finalize` (--auto, or a resume of a paused run), route to
      # plan_completion (cascade + gh pr ready) unchanged.
      - target: paused_for_review
        when:
          finalization_status: updated
          pause_decision: pause
        context_assignments:
          outcome: paused-for-review
          resume: "/execute {{PLAN_DOC}}"
      # plan_completion fires when pause_decision is `finalize` (--auto, resume,
      # or the default when omitted), so the default path (R7) is preserved
      # byte-for-byte for a fresh non-paused run.
      - target: plan_completion
        when:
          finalization_status: updated
          pause_decision: finalize
      - target: done_blocked
        when:
          finalization_status: update_failed
        context_assignments:
          outcome: error
          step: "execute:pr_finalization"
          failure_reason: "pr_finalization failed: could not update or ready the PR"
      - target: done_blocked
        when:
          finalization_status: pr_adopt
        context_assignments:
          outcome: error
          step: "execute:pr-adopt"
          failure_reason: "pr_finalization: no single owned PR on the settled branch"
      - target: done_blocked
        when:
          finalization_status: status_read
        context_assignments:
          outcome: error
          step: "execute:status-read"
          failure_reason: "pr_finalization: the PR lookup read failed"

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
      #   semantics: scripts/ci-gate-expression_test.sh
      #
      # The PR is resolved through owned-pr.sh on the recorded repository and
      # settled branch, never the first `gh pr list --head` hit, so a fork's or
      # another author's same-named PR is never the one whose checks count. That
      # is why these two gates no longer share work-on.md's names (ci_passing,
      # merge_state_clean): validate-template-mermaid.sh check 4 holds one gate
      # name to one command, and the commands now differ.
      owned_ci_passing:
        type: command
        command: "gh pr checks \"$({{PLUGIN_ROOT}}/skills/execute/scripts/owned-pr.sh --repo \"$(koto context get execute-{{PLAN_SLUG}} repos)\" --head \"$(koto context get execute-{{PLAN_SLUG}} settled_branch)\" --state open)\" --json bucket --jq '[.[] | select(.bucket != \"pass\" and .bucket != \"skipping\")] | length == 0' | grep -q true"
      owned_merge_state_clean:
        type: command
        command: "[ \"$(gh pr view \"$({{PLUGIN_ROOT}}/skills/execute/scripts/owned-pr.sh --repo \"$(koto context get execute-{{PLAN_SLUG}} repos)\" --head \"$(koto context get execute-{{PLAN_SLUG}} settled_branch)\" --state open)\" --json mergeStateStatus --jq .mergeStateStatus)\" != \"DIRTY\" ]"
    accepts:
      ci_outcome:
        type: enum
        values: [passing, failing_fixed, pending, failing_unresolvable, dirty_merge_state, pr_adopt, status_read]
        required: true
      rationale:
        type: string
        description: What was fixed or why CI failures are unresolvable
    transitions:
      # Every way on goes through merge_readiness, which re-reads the PR and
      # owns the per-head-commit CI deadline. No edge reaches a terminal on the
      # agent's word that CI is green.
      - target: merge_readiness
        when:
          ci_outcome: passing
          gates.owned_ci_passing.exit_code: 0
          gates.owned_merge_state_clean.exit_code: 0
      # failing_fixed: agent pushed a follow-up commit to fix CI; gate may be
      # stale. merge_readiness reads the checks on the new head itself.
      - target: merge_readiness
        when:
          ci_outcome: failing_fixed
      # pending: checks are still running. merge_readiness's verdict waits on
      # them (pending:checks) up to the per-head-commit deadline, then ends
      # the run at execute:ci-timeout, so waiting is bounded there.
      - target: merge_readiness
        when:
          ci_outcome: pending
      - target: done_blocked
        when:
          ci_outcome: failing_unresolvable
        context_assignments:
          outcome: error
          step: "execute:ci"
          failure_reason: "ci_monitor: unresolvable CI failures: ${evidence.rationale}"
      - target: escalate_dirty_merge_state
        when:
          ci_outcome: dirty_merge_state
        context_assignments:
          failure_reason: "ci_monitor: PR merge state is DIRTY; checks suppressed. ${evidence.rationale}"
      - target: done_blocked
        when:
          ci_outcome: pr_adopt
        context_assignments:
          outcome: error
          step: "execute:pr-adopt"
          failure_reason: "ci_monitor: no single owned PR on the settled branch"
      - target: done_blocked
        when:
          ci_outcome: status_read
        context_assignments:
          outcome: error
          step: "execute:status-read"
          failure_reason: "ci_monitor: the PR lookup read failed"

  escalate_dirty_merge_state:
    accepts:
      rationale:
        type: string
        required: true
        description: Conflict files or rebase instructions for the operator
    transitions:
      # A conflicted PR is not an error: the run ends ready-awaiting-merge on
      # the condition that stops it, through the failure terminal it has
      # always used.
      - target: done_blocked
        context_assignments:
          outcome: ready-awaiting-merge
          reason: "merge-state:DIRTY"
          failure_reason: "escalate_dirty_merge_state: ${evidence.rationale}"

  plan_completion:
    # The completion cascade runs BEFORE gh pr ready so the chain is
    # at its strict-mode passing state when CI re-runs on the
    # ready_for_review event (#117 DRAFT-vs-READY discipline). The
    # state runs two steps: (1) run-cascade.sh, which performs the
    # atomic finalization commit and pushes -- the strict-mode
    # lifecycle checks either side of it are INSIDE the script, and
    # the agent never invokes the validator itself; (2) gh pr ready,
    # only on a completed or skipped verdict.
    #
    # expected_head_recorded makes a missing expected-head record visible.
    # run-cascade.sh --push --session records the pushed commit; this gate
    # reports whether a record exists. It routes nothing: a run that reaches
    # merge_readiness without a record passes `--expected-head none`, and the
    # verdict ends it ready-awaiting-merge naming head-moved rather than
    # merging a head the run never pushed.
    gates:
      expected_head_recorded:
        type: context-matches
        key: expected_head
        pattern: '^[0-9a-f]{40}$'
    accepts:
      cascade_status:
        type: enum
        values: [completed, partial, skipped, pr_adopt, status_read]
        required: true
      cascade_detail:
        type: string
        description: Summary of what the cascade did or why steps were skipped
    transitions:
      # Each verdict has one edge per value of the gate, both to ci_monitor:
      # the edge taken, and the gate's output in the response, are where a
      # missing record shows. Neither edge blocks the run.
      - target: ci_monitor
        when:
          cascade_status: completed
          gates.expected_head_recorded.matches: true
      - target: ci_monitor
        when:
          cascade_status: completed
          gates.expected_head_recorded.matches: false
      - target: ci_monitor
        when:
          cascade_status: partial
          gates.expected_head_recorded.matches: true
      - target: ci_monitor
        when:
          cascade_status: partial
          gates.expected_head_recorded.matches: false
      - target: ci_monitor
        when:
          cascade_status: skipped
          gates.expected_head_recorded.matches: true
      - target: ci_monitor
        when:
          cascade_status: skipped
          gates.expected_head_recorded.matches: false
      # The owned-PR lookup in front of gh pr ready, mapped as SKILL.md says.
      - target: done_blocked
        when:
          cascade_status: pr_adopt
        context_assignments:
          outcome: error
          step: "execute:pr-adopt"
          failure_reason: "plan_completion: no single owned PR to mark ready"
      - target: done_blocked
        when:
          cascade_status: status_read
        context_assignments:
          outcome: error
          step: "execute:status-read"
          failure_reason: "plan_completion: the PR lookup read failed"

  merge_readiness:
    # The verdict, recorded by koto, not by the agent. record-merge-verdict.sh
    # clears merge_verdict, home_pr, reason, step, and waiting; resolves the PR
    # through owned-pr.sh --state all on the recorded repository and settled
    # branch; runs merge-verdict.sh with this invocation's MERGE and the
    # recorded expected head (or `none`); and writes the verdict line, plus its
    # condition as `reason` or its step as `step`, only when each matches its
    # pattern. It reads GitHub and writes koto context, nothing else.
    #
    # koto substitutes declared variables into a default_action command, never
    # context keys, so the repository and branch are read inside the command
    # with `koto context get`. scripts/execute-template-structure_test.sh fails
    # on any ${context. in a default_action command.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/execute/scripts/record-merge-verdict.sh --session "execute-{{PLAN_SLUG}}" --merge "{{MERGE}}" --repo "$(koto context get execute-{{PLAN_SLUG}} repos)" --head-branch "$(koto context get execute-{{PLAN_SLUG}} settled_branch)"'
      fallback: >-
        koto could not record the merge verdict. Read the command's own output
        above: exit 1 means merge-verdict.sh failed or printed something
        outside its grammar, 64 a missing or invalid repository or branch in
        context, 70 a context write, and a timeout means the reads took longer
        than koto allows. Nothing stale was left behind: the script clears its
        keys first. Tick again to re-run it. If it keeps failing, submit
        `readiness_status: blocked` with `detail` to end the run at
        execute:status-read.
    gates:
      verdict_recorded:
        type: context-exists
        key: merge_verdict
        overridable: false
    accepts:
      readiness_status:
        type: enum
        values: [blocked]
        description: >-
          Absent on the passing path. The state advances to merge_route with no
          evidence once a verdict is recorded.
      detail:
        type: string
        description: Why no verdict could be recorded.
    transitions:
      - target: merge_route
        when:
          gates.verdict_recorded.exists: true
      - target: done_blocked
        when:
          gates.verdict_recorded.exists: false
          readiness_status: blocked
        context_assignments:
          outcome: error
          step: "execute:status-read"
          failure_reason: "merge_readiness: no merge verdict could be recorded: ${evidence.detail}"

  merge_route:
    # Routes only on the recorded verdict, through anchored context-matches
    # gates that no override can stand in for. Each edge names every gate, so
    # the arms are exclusive by construction. A pending verdict, or none at all
    # (the key was cleared and the action never rewrote it), goes back to
    # merge_readiness only through agent evidence `recheck: waited`, so one
    # tick never revisits a state in a loop the engine would refuse.
    gates:
      verdict_merged:
        type: context-matches
        key: merge_verdict
        pattern: '^merged$'
        overridable: false
      verdict_mergeable:
        type: context-matches
        key: merge_verdict
        pattern: '^mergeable:(squash|merge|rebase):[0-9a-f]{40}$'
        overridable: false
      verdict_awaiting:
        type: context-matches
        key: merge_verdict
        pattern: '^awaiting:(merge-not-requested|head-moved|no-checks|base-unprotected|review|workflow-change|merge-method-unresolved|merge-state:[A-Z_]+(:review=(REVIEW_REQUIRED|CHANGES_REQUESTED))?)$'
        overridable: false
      verdict_error:
        type: context-matches
        key: merge_verdict
        pattern: '^error:execute:(pr-closed|ready|ci|ci-timeout|status-read|pr-adopt)$'
        overridable: false
      verdict_pending:
        type: context-matches
        key: merge_verdict
        pattern: '^pending:(checks|merge-state)$'
        overridable: false
      # Any recorded verdict at all. A cleared key is removed, not emptied, so
      # an absent verdict fails this and a present one has a character to match.
      verdict_present:
        type: context-matches
        key: merge_verdict
        pattern: '.'
        overridable: false
    accepts:
      recheck:
        type: enum
        values: [waited]
        description: >-
          Submitted only on a pending or absent verdict, after waiting, to
          recompute it. Every other verdict routes with no evidence.
    transitions:
      - target: merge_confirm
        when:
          gates.verdict_merged.matches: true
          gates.verdict_mergeable.matches: false
          gates.verdict_awaiting.matches: false
          gates.verdict_error.matches: false
          gates.verdict_pending.matches: false
      - target: merge_attempt
        when:
          gates.verdict_merged.matches: false
          gates.verdict_mergeable.matches: true
          gates.verdict_awaiting.matches: false
          gates.verdict_error.matches: false
          gates.verdict_pending.matches: false
      # The condition reaches the result through the `reason` key the record
      # script wrote; this edge assigns no reason of its own.
      - target: ready_awaiting_merge
        when:
          gates.verdict_merged.matches: false
          gates.verdict_mergeable.matches: false
          gates.verdict_awaiting.matches: true
          gates.verdict_error.matches: false
          gates.verdict_pending.matches: false
        context_assignments:
          outcome: ready-awaiting-merge
      # The step reaches the result through the `step` key the record script
      # wrote; this edge assigns no step of its own.
      - target: done_blocked
        when:
          gates.verdict_merged.matches: false
          gates.verdict_mergeable.matches: false
          gates.verdict_awaiting.matches: false
          gates.verdict_error.matches: true
          gates.verdict_pending.matches: false
        context_assignments:
          outcome: error
          failure_reason: "merge_route: the merge verdict is an error"
      - target: merge_readiness
        when:
          gates.verdict_merged.matches: false
          gates.verdict_mergeable.matches: false
          gates.verdict_awaiting.matches: false
          gates.verdict_error.matches: false
          gates.verdict_pending.matches: true
          recheck: waited
      - target: merge_readiness
        when:
          gates.verdict_present.matches: false
          gates.verdict_merged.matches: false
          gates.verdict_mergeable.matches: false
          gates.verdict_awaiting.matches: false
          gates.verdict_error.matches: false
          gates.verdict_pending.matches: false
          recheck: waited
      # A verdict is present and matches none of the patterns: something other
      # than the record script wrote it. It is never read as progress.
      - target: done_blocked
        when:
          gates.verdict_present.matches: true
          gates.verdict_merged.matches: false
          gates.verdict_mergeable.matches: false
          gates.verdict_awaiting.matches: false
          gates.verdict_error.matches: false
          gates.verdict_pending.matches: false
        context_assignments:
          outcome: error
          step: "execute:status-read"
          failure_reason: "merge_route: the recorded merge verdict is outside the verdict grammar"

  merge_attempt:
    # Agent-run on purpose: a successful `gh pr merge` is the externally
    # visible event itself, so it is never a default action. The merge_intent
    # gate re-checks this invocation's MERGE on every tick that reaches the
    # state and cannot be overridden. Its failure edge fires before any
    # evidence is asked for, so a run stopped here with a recorded mergeable
    # verdict and resumed without --merge (which rebinds MERGE to false) never
    # presents the state that runs merge-exec.sh.
    gates:
      merge_intent:
        type: command
        command: 'test "{{MERGE}}" = true'
        overridable: false
    accepts:
      merge_exec:
        type: enum
        values: [called, refused]
        description: >-
          Which line merge-exec.sh printed: `merge-called:<method>:<sha>` is
          `called`, `merge-refused:<...>` is `refused`.
      merge_line:
        type: string
        description: The line merge-exec.sh printed, for the log. Never read.
    transitions:
      - target: ready_awaiting_merge
        when:
          gates.merge_intent.exit_code: 1
        context_assignments:
          outcome: ready-awaiting-merge
          reason: merge-not-requested
      # merge-called is never read as merged: merge_confirm re-reads the PR.
      - target: merge_confirm
        when:
          gates.merge_intent.exit_code: 0
          merge_exec: called
      - target: ready_awaiting_merge
        when:
          gates.merge_intent.exit_code: 0
          merge_exec: refused
        context_assignments:
          outcome: ready-awaiting-merge
          reason: merge-call-failed

  merge_confirm:
    # The confirm read runs as a default action, never as a command gate:
    # merge-verdict.sh --confirm exits 0 on both outcomes, so a gate routing on
    # its exit code would always pass. record-merge-verdict.sh --confirm clears
    # confirm_verdict, re-resolves the owned PR itself (never from agent
    # evidence), and writes the confirm line only when it matches
    # ^(merged|not-merged:merge-not-observed)$. This is the only state with an
    # edge into `merged`, and row 1's already-merged verdict passes through it
    # too.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/execute/scripts/record-merge-verdict.sh --confirm --session "execute-{{PLAN_SLUG}}" --merge "{{MERGE}}" --repo "$(koto context get execute-{{PLAN_SLUG}} repos)" --head-branch "$(koto context get execute-{{PLAN_SLUG}} settled_branch)"'
      fallback: >-
        koto could not record the confirm read. Read the command's own output
        above: exit 1 means no single owned PR was found or the read printed
        something outside its grammar, 64 a missing repository or branch in
        context, 70 a context write. Tick again to re-run it. If it keeps
        failing, submit `confirm_status: unreadable`: with nothing confirmed,
        the run ends ready-awaiting-merge naming merge-not-observed, never
        merged.
    gates:
      confirmed_merged:
        type: context-matches
        key: confirm_verdict
        pattern: '^merged$'
        overridable: false
    accepts:
      confirm_status:
        type: enum
        values: [unreadable]
        description: >-
          Absent on every normal path. Submitted only when the confirm read
          keeps failing; it re-evaluates the gate without re-running the read,
          and a cleared key can only route to ready_awaiting_merge.
    transitions:
      - target: merged
        when:
          gates.confirmed_merged.matches: true
        context_assignments:
          outcome: merged
          waiting: ""
      - target: ready_awaiting_merge
        when:
          gates.confirmed_merged.matches: false
        context_assignments:
          outcome: ready-awaiting-merge
          reason: merge-not-observed

  escalate:
    accepts:
      failure_reason:
        type: string
        required: true
        description: Summary of which children failed and why, for the batch view
    transitions:
      - target: done_blocked
        context_assignments:
          outcome: error
          step: "execute:escalate"
          failure_reason: "${evidence.failure_reason}"

  paused_for_review:
    # D2 (execute-friction): a non-failure terminal reached in interactive mode
    # after pr_finalization assembles the PR body but BEFORE the plan_completion
    # cascade. The chain is INTACT at this point: the PLAN is still present and
    # BRIEF/PRD/DESIGN are un-transitioned, and the PR is still DRAFT (gh pr
    # ready has NOT fired — it lives in plan_completion). `failure:` is absent —
    # this is a successful, solicited stop, not a block. It is a SUSPENSION, not
    # a termination: at the /execute SKILL layer `exit:` stays UNSET with a
    # resumable paused_for_review marker, so the parent-skill R9
    # hard-finalization check (which fires only at terminal exits) is not
    # tripped. Resume is a fresh invocation: koto-open.sh's --replace-terminal
    # replaces this retained terminal, and the new run adopts the still-open
    # DRAFT PR with PAUSE_BEFORE_FINALIZE=false.
    terminal: true
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.home_pr}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"

  merged:
    # Reached only from merge_confirm, on a live read of MERGED.
    terminal: true
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.home_pr}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"

  ready_awaiting_merge:
    # The PR is ready and green as far as the run could take it, and a human
    # (or a later /execute --merge) merges it. The `reason` names the
    # condition: merge not requested, a review, a protection rule, a moved
    # head, a merge call that failed, or a merge not yet observed.
    terminal: true
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.home_pr}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"

  done:
    # Legacy. No transition reaches it any more; it stays declared so a
    # session started from an earlier version of this template, standing at
    # `done`, still resolves. Its outcome is the literal that state meant: the
    # PR was left ready, never merged by the run.
    terminal: true
    result:
      outcome: ready-awaiting-merge
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.home_pr}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"

  done_blocked:
    terminal: true
    failure: true
    accepts:
      failure_reason:
        type: string
        description: Reason for blocking failure (populated via context_assignments)
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.home_pr}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"
---

## orchestrator_setup

Find the home PR this run owns, or create one. The PLAN slug is already available as `{{PLAN_SLUG}}` -- a declared, compile-time-validated template variable -- so do not re-derive it. The run's write set, the one repository it may write to, was recorded by `write_set_record` before this state; every lookup below takes it from there.

Every PR lookup goes through `adopt-or-create-pr.sh`, which finds PRs with `owned-pr.sh`: only a PR whose head is in this repository (not a fork), whose author is you, whose base is the default branch, and whose head is the branch named. A same-named PR from a fork or from another author is never adopted, edited, readied, or merged, and several owned PRs are never picked among. The script records the home PR's URL as `home_pr` itself; you never write it.

**1. The current branch.** If you are on a branch other than the default branch and `impl/{{PLAN_SLUG}}`, check whether you own a PR on it:

```bash
REPO=$(koto context get {{SESSION_NAME}} repos)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
{{PLUGIN_ROOT}}/skills/execute/scripts/adopt-or-create-pr.sh \
  --session {{SESSION_NAME}} --repo "$REPO" --head "$BRANCH"
echo "exit=$?"
```

Exit 0 means you own exactly one open PR there. That PR (including a `docs/<topic>` scoping PR, or the topic branch `/scope --intent=continue` pushed) is **ADOPTED** as the home PR and the branch you stay on is the **settled branch**: `/execute` opens no second PR, cuts no `impl/<slug>`, and pushes nothing here. Submit `status: override`. Exit 4 means you own no PR on this branch (a fork's or another author's PR there doesn't count): go on to step 2. Exit 3 (several owned PRs) submits `status: pr_adopt`; exit 2 (a failed read) submits `status: status_read`.

**2. The shared branch.** Otherwise create the shared branch and its draft PR. This runs once before children are spawned:

```bash
REPO=$(koto context get {{SESSION_NAME}} repos)
git checkout impl/{{PLAN_SLUG}} 2>/dev/null || git checkout -b impl/{{PLAN_SLUG}}
{{PLUGIN_ROOT}}/skills/execute/scripts/push-and-record.sh {{SESSION_NAME}}
{{PLUGIN_ROOT}}/skills/execute/scripts/adopt-or-create-pr.sh \
  --session {{SESSION_NAME}} --repo "$REPO" --head impl/{{PLAN_SLUG}} \
  --create --plan-slug {{PLAN_SLUG}} --plan-doc {{PLAN_DOC}}
echo "exit=$?"
```

`push-and-record.sh` pushes with an explicit `HEAD:refs/heads/<branch>` refspec and no force option, refuses the default branch and a detached HEAD, and records the pushed commit as `expected_head` only after the push succeeds. Every push this run makes goes through it (or through `run-cascade.sh --push --session`); nothing else writes `expected_head`, and you never write it yourself.

`adopt-or-create-pr.sh --create` reuses an owned PR if one is already there (after a crash and re-run) and otherwise makes exactly one `gh pr create --draft`, then resolves the PR again and records it. Exit 0 submits `status: completed`. Exit 3 (several owned PRs, or still none after the create) submits `status: pr_adopt`; exit 2 submits `status: status_read`; exit 5 (the create failed) submits `status: blocked` with `detail`.

`gh pr create` stays here rather than moving into an action, permanently: its successful exit is the externally visible event. Reviewers are notified, a number is allocated, and subscribed automation reacts, and closing the pull request afterwards undoes its state and not the notifications. The same holds for the push. See `references/default-action-conversion.md`.

**You do not record the settled branch.** That is `settled_branch_record`, the next state, which koto drives itself. Submit `status: completed` after the branch and draft PR exist, `status: override` if you adopted an owned PR on the current branch, `status: pr_adopt` or `status: status_read` as the exit codes above say, or `status: blocked` with `detail` if a step fails for any other reason.

## write_set_record

Recording the run's write set. koto runs the script itself on entry; you only see this state if it could not.

<!-- details -->

The command is `skills/execute/scripts/record-write-set.sh`. It reads the `origin` remote's configured URL and reduces it to `owner/repo` (falling back to `gh repo view` when the URL names none), refuses a value outside `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`, and writes it to the `repos` context key. A value already recorded is never changed. The `repos_recorded` gate reads the key back and cannot be overridden: the write set is what every PR lookup and both merge scripts receive, so an agent must not be able to name it.

You are here because the script failed, and the response above carries its exit code and its own stderr. Fix the cause (usually an `origin` remote that names no GitHub repository) and tick again; the record re-runs on entry. `write_set_status: blocked` with `detail` stops the run at `done_blocked` with `step=execute:write_set_record`.

Evidence schema (optional; the passing path submits neither):
- `write_set_status`: `blocked`
- `detail`: why the write set could not be recorded

## settled_branch_record

Recording the branch this run settled on, so `spawn_and_await` can route every child to it. koto runs the script itself on entry; you only see this state if it could not.

<!-- details -->

The command is `skills/execute/scripts/record-settled-branch.sh`, which reads HEAD, refuses a detached HEAD, refuses a name outside `^[A-Za-z0-9._/-]+$`, refuses the repository's default branch, writes the value to the `settled_branch` context key, and prints it. The `settled_branch_recorded` gate then reads that key back through koto's own evaluator — a check the action cannot influence — and the captured name is delivered to `spawn_and_await` under the name
`SETTLED_BRANCH`.

That name is written without braces here on purpose. A `{{...}}` reference is
substituted wherever it appears, including in this state's own text, and on the
failure path the capture does not exist yet -- so a braced mention in the prose
of the state that produces it stops the tick with `capture_unset` instead of
showing you the failure you came here to read. Only `spawn_and_await`, which
every path reaches through this state, references it with braces.

On the passing path the run advances to `drift_facts` with no evidence and you never read this.

You are here because the script failed, and the response above carries its exit code and its own stderr. Exit 64 is a detached HEAD, 65 a branch name the pattern rejects, 66 the default branch. Fix the branch and tick again; the record re-runs on entry.

`status: blocked` with `detail` is the only evidence this state takes, and it routes to `done_blocked`. There is no override, and that asymmetry is deliberate: every child of this run commits to whatever is recorded here, so a run that cannot record its branch must stop rather than proceed on an unrecorded one.

The default-branch refusal is the interesting one. This used to be a block of shell in `orchestrator_setup` under a paragraph explaining that `main` was "the one wrong value neither the pattern nor the read-back can catch, because nothing about it is malformed; the ordering is the only thing that prevents it." The ordering is now a state boundary, and the script refuses the value outright.

Evidence schema (optional; the passing path submits neither):
- `status`: `blocked`
- `detail`: why the branch could not be recorded

## drift_facts

Computing what `origin/main` changed since this PLAN's base, before the rebase. koto runs the script itself on entry; you only see this state if it could not.

<!-- details -->

The command is `skills/execute/scripts/drift-facts.sh`. It fetches `origin`, takes the base as the merge-base of the last commit that touched the PLAN (or HEAD, for a PLAN git doesn't track yet) and `origin/main`, collects the paths the PLAN references (its `upstream:`, its `**Files**:` lines, and backticked path tokens), and diffs the base against `origin/main`. It writes two context keys and prints nothing: `plan_intent.md` (the PLAN's title, upstreams, Scope Summary, and outline goals) and then `drift_facts.json` (compact JSON, `route` first, schema `drift-facts/v1`). The facts hold paths, statuses, and line counts only, never commit subjects or diff text.

`route` is `none` when main didn't move, or moved only in paths the PLAN doesn't reference, and `judge` otherwise: an overlap, a deleted reference, a payload cut to fit 8192 bytes, or a PLAN that references nothing beyond itself and its upstreams. `worktree_sync` routes on it after the rebase.

This runs before the rebase because the rebase moves a branch-only PLAN's fork point to the tip of `origin/main`, after which every run would read as "main hasn't advanced". For the same reason, a `koto rewind` into this state after `worktree_sync` has run computes against the already rebased branch and reports no drift.

On the passing path the run advances to `worktree_sync` with no evidence and you never read this.

You are here because the script failed, and the response above carries its exit code and its own stderr. Exit 64 means no base resolved (the fetch failed, `origin/main` is missing, or it shares no history with the PLAN), 65 the PLAN doc is missing or outside the repository, 66 a context write failed. Fix the cause and tick again; the script re-runs on entry.

`facts_status: override` with `detail` continues to the rebase without facts. The drift question in `worktree_discipline_check` is then asked with no `drift_facts.json` to read, so you'd have to answer it from git yourself. `facts_status: blocked` with `detail` stops the run.

Evidence schema (optional; the passing path submits neither):
- `facts_status`: `override` or `blocked`
- `detail`: why the facts could not be computed

## worktree_sync

Bringing the shared branch onto the current `origin/main`. koto rebases itself on entry; you only see this state if it could not.

<!-- details -->

The command is `git rebase origin/main`, with no fetch: `drift_facts` fetched immediately before, so the rebase lands on exactly the `origin/main` the facts describe. The `rebased_on_main` gate beside it asks the question the rebase existed to answer -- is `origin/main` an ancestor of HEAD -- independently of whether the rebase command succeeded, and additionally requires that no rebase is in progress.

That second half is load-bearing. During a conflicted rebase the ancestor check passes on its own, because git has already replayed part of the branch, so HEAD genuinely does contain `origin/main`. Without the in-progress tests the gate would wave a halted rebase and a conflicted worktree straight through.

The `drift_clear` gate reads `drift_facts.json` and matches only when its `route` is `none`. A clean rebase with `drift_clear` passing advances straight to `spawn_and_await`, with no evidence and no drift question. A clean rebase with any other facts advances to `worktree_discipline_check`. A branch already on top of main passes without a rebase having done anything.

You are here because the rebase failed, and the response above carries git's own output. A conflict is the usual cause and it leaves the rebase in progress: resolve it and `git rebase --continue`, or `git rebase --abort` and rebase by hand, then tick again. Re-entering re-runs the rebase, and git refuses to start a second rebase while one is in progress, so a retry reports the conflict rather than compounding it.

`sync_status: override` proceeds to `worktree_discipline_check` without the rebase, for the deliberate case where the shared branch should not be on top of main. `blocked` with `detail` stops the run.

This state does not classify anything. Judging what the upstream changes mean for the PLAN is `worktree_discipline_check`'s job, and only when the facts couldn't rule drift out.

## worktree_discipline_check

Upstream drift check, once per run. `origin/main` changed something this PLAN references, or the facts couldn't rule that out, so decide whether the change invalidates the PLAN's intent. The fetch, the rebase, and the fact-finding already happened; you don't fetch or rebase here, and there's no file to write.

Read the two context keys `drift_facts` wrote:

```bash
koto context get {{SESSION_NAME}} drift_facts.json
koto context get {{SESSION_NAME}} plan_intent.md
```

`drift_facts.json` says why you're being asked (`reasons`), which referenced paths main changed (`overlap`, each with `status`, `added`, `removed`), and which it deleted (`deleted_referenced_paths`). `plan_intent.md` holds the PLAN's title, upstreams, Scope Summary, and outline goals. Read `${CLAUDE_PLUGIN_ROOT}/skills/work-on/references/phases/phase-2.5-worktree-discipline.md` for the full instruction, and `${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md` for the classification rule.

Submit `impact` as one of:

- `informational` — main touched paths the PLAN references, but the PLAN's intent still holds (e.g., docs edits, unrelated tests, a reformat). Routes to `spawn_and_await`.
- `intent-changing` — main changed something the PLAN depends on so it no longer holds (e.g., a referenced file was deleted, a contract the PLAN relies on changed). Routes to `escalate_upstream_drift` with `rationale` (required).

## escalate_upstream_drift

A worktree-discipline check classified the upstream impact as `intent-changing` — the PLAN's foundation has changed and the operator needs to decide how to proceed (rebase the PLAN against the new main, abandon, or rescope). The terminal state routes to `done_blocked` carrying the `failure_reason` for batch-view visibility.

## spawn_and_await

Spawn and coordinate per-issue work-on children from the PLAN document.

**Autonomy at every tick.** When the run is authorized autonomous (the `--auto` flag
or a clear author instruction, per the SKILL's **Autonomy** section), drive this state
to its terminal continuously: do NOT pause between children to advise a checkpoint,
seek confirmation or reassurance, or stop because issues remain, the work is large, or
out of concern for context budget. The coordinator stays thin by delegating each issue
to a fresh `work-on.md` child and reading only status, so its context lasts the whole
run. Stop ONLY on a genuine blocker (a child that fails/blocks needing human judgment
and cannot be isolated by skip-dependents, an upstream-must-change boundary, a merge
conflict or dirty state, or a destructive action needing confirmation) and emit the
forced-stop operator summary. A decision with a reasonable default is NOT a blocker:
take the default, record it in the decision log, continue. In interactive mode the
existing approval behavior is unchanged.

**Tick 1 — spawn**: run `plan-to-tasks.sh`, inject the shared branch into each task's vars, then submit `tasks`:

```bash
TMP=$(mktemp)
TASKS=$(${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh {{PLAN_DOC}})
# The settled branch arrives as a capture from settled_branch_record, which
# every path into this state passes through, and whose gate has already
# verified the stored value against ^[A-Za-z0-9._/-]+$. There is nothing to
# read back, no exit status to branch on, and no impl/<slug> fallback: the
# fallback existed because the key might be absent, and the gate is what
# makes it present.
SETTLED_BRANCH="{{SETTLED_BRANCH}}"
# PLUGIN_ROOT is required by work-on.md and is not part of plan-to-tasks.sh's
# contract, so it is injected here the same way SHARED_BRANCH is: a child koto
# materializes receives only the variables its task entry lists, and a child
# missing this one fails to spawn with a variable-resolution error in the
# batch's errored ledger.
TASKS_WITH_BRANCH=$(echo "$TASKS" | jq --arg b "$SETTLED_BRANCH" --arg p "${CLAUDE_PLUGIN_ROOT}" '[.[] | .vars.SHARED_BRANCH = $b | .vars.PLUGIN_ROOT = $p]')
echo "{\"tasks\": $TASKS_WITH_BRANCH}" > "$TMP"
koto next {{SESSION_NAME}} --with-data @"$TMP" --no-cleanup
rm -f "$TMP"
```

koto materializes one child per task using `work-on.md` with `failure_policy: skip_dependents`. Children receive `SHARED_BRANCH` and commit directly to it without creating their own branches. After each child completes and before dispatching the next, run the context assembly step in `references/cross-issue-context.md` so each child sees what prior children found, decided, or changed.

**Tick 2 — complete**: once all children reach terminal states, the `batch_done` gate unblocks and routes the batch itself. Do not inspect children or choose an outcome, and submit no evidence: the gate sends the batch to `pr_finalization` when every child succeeded, and to `escalate` when any child failed or was skipped (its `needs_attention` field is true). Advance with a bare tick:

```bash
koto next {{SESSION_NAME}} --no-cleanup
```

Check progress at any time with `koto status {{SESSION_NAME}}`. If the tick returns the gate still blocked, children are still running; tick again once they reach terminal states.

## pr_finalization

Author a template-conformant PR — a conventional-commit **title** and the project's **two-part body** — and apply it in the single `gh pr edit` this state already runs, so a clean run is conformant in one pass, with no separate repair step (DESIGN R4 / D6). Do **not** mark the PR ready in this state — the DRAFT-vs-READY discipline (#117) requires the chain to be at its strict-mode passing state BEFORE `gh pr ready` fires, and the cascade in `plan_completion` performs that finalization. This state confines itself to title + body assembly.

The **mechanical** title/body rule is single-sourced in `references/pr-body-conformance.md` (conventional `<type>[scope]: <description>` title with no issue-number scope; a two-part body with exactly one `---` separator where Part 1 becomes the squash commit body and everything from `---` down is deleted at merge; no AI-attribution footer). That rule is what `shirabe validate --pr-body` enforces in CI, so authoring to it here means a clean run is conformant in one pass. Apply it inline — an autonomous `/execute` run authors its own conformant PR rather than producing a malformed one and repairing it afterward, and does **not** shell out to another plugin's skill at runtime. (Subjective Part 2 section selection is reasoning-based; for `/execute` Part 2 is the per-child outcome table below.)

**1. Build the conventional title.** Derive `<description>` from the **validated PLAN slug** `{{PLAN_SLUG}}`, which koto validates against the template's `variables:` block at compile time and which already matches `^[a-z0-9-]+$`. NEVER interpolate raw PLAN prose (title text, body) into the title or the emitted shell — PLAN-body text is data (Security Considerations point 6); the title is built only from the validated slug.

   - `<type>` defaults to **`feat`** (a PLAN normally lands feature work). Use `fix` only when the PLAN is purely remediation, or `docs`/`chore` when every child change is docs/chore. A reasonable default is not a blocker — take `feat` and move on.
   - `<scope>` is optional: omit unless an obvious subsystem applies; NEVER an issue-number scope (`references/pr-body-conformance.md`, PB1).
   - The result, e.g. `feat: execute-friction`, **replaces** the non-conventional `impl: {{PLAN_SLUG}}` title set at creation.

**2. Assemble the two-part body.** Read `koto context get {{SESSION_NAME}} batch_final_view` for per-child outcome data, then build:

   - **Part 1 — factual change paragraph** (becomes the squash commit body): a concise paragraph of what the PLAN's PR changed in the codebase, derived from the PLAN's own validated framing plus the child-outcome metadata. `/execute` is metadata-only (R14/R15) — do NOT read child PR bodies or diffs. No `Fixes #N` here.
   - A `---` separator.
   - **Part 2 — reviewer context** (deleted at merge): the per-child outcome table — for each child `name`, `outcome` (`success`/`failure`/`skipped`), `reason`, `reason_source`, `skipped_because_chain`. Append `Fixes #<N>` lines **only** when the children are GitHub issues (`ISSUE_SOURCE` is a real issue, not `plan_outline`); for single-pr outline children there is no issue to close, so omit `Fixes #N` entirely.

**3. Apply via `--body-file`/stdin, never inline interpolation.** Write the assembled body to a temp file (or heredoc to stdin) and pass it with `--body-file`, so prose is never spliced into the shell command line:

```bash
# The owned PR on the settled branch, never the first `gh pr list --head` hit.
# Empty output or exit 3 submits finalization_status: pr_adopt; exit 2 submits
# finalization_status: status_read. Either way, edit nothing.
PR_NUMBER=$({{PLUGIN_ROOT}}/skills/execute/scripts/owned-pr.sh \
  --repo "$(koto context get {{SESSION_NAME}} repos)" \
  --head "$(koto context get {{SESSION_NAME}} settled_branch)" --state open)
BODY_FILE=$(mktemp)
cat > "$BODY_FILE" <<'BODY'
<Part 1: factual change paragraph>

---

<Part 2: per-child outcome table; Fixes #N only for GitHub-issue children>
BODY
gh pr edit "$PR_NUMBER" --title "feat: {{PLAN_SLUG}}" --body-file "$BODY_FILE"
rm -f "$BODY_FILE"
```

Run this title+body edit **unconditionally** on every finalization (clean and attention runs) — a zero-issue or all-skipped run still yields a conformant title, so R4's no-fix-up guarantee holds.

`PR_NUMBER` holds the owned PR's URL, which `gh pr edit` accepts as the PR argument. Submit `finalization_status: updated` after the PR title and body are updated, or `finalization_status: update_failed` if the edit step fails. When the lookup finds no single owned PR, submit `finalization_status: pr_adopt`, and when its read fails, `finalization_status: status_read`. The `update_failed`→`done_blocked` route and the DRAFT-before-READY ordering (no `gh pr ready` here — that stays in `plan_completion`) are unchanged.

**4. Submit the mode-driven `pause_decision` (D2).** Alongside `finalization_status: updated`, set `pause_decision` from the `{{PAUSE_BEFORE_FINALIZE}}` variable, which `/execute` resolves from the execution mode at `koto init` time (interactive → `true`; `--auto` → `false`). It is NOT a separate user flag.

- If `{{PAUSE_BEFORE_FINALIZE}}` is `true`, submit `pause_decision: pause`. The PR body is now assembled but the chain is intact (PLAN present, BRIEF/PRD/DESIGN un-transitioned) and the PR is still DRAFT. The workflow routes to the non-failure terminal `paused_for_review` and stops — the operator reviews the DRAFT PR and resumes to finalize.
- If `{{PAUSE_BEFORE_FINALIZE}}` is `false` (the `--auto` path, and the default), submit `pause_decision: finalize` (or omit it — the fallback edge finalizes). The workflow routes to `plan_completion`, which runs the cascade and then `gh pr ready`, driving straight through to a ready-to-merge, green PR -- unless the cascade reports `partial`, which halts there instead.

On a resume of a paused run, `/execute` re-enters with `PAUSE_BEFORE_FINALIZE=false` (resume is a finalize invocation), so this step submits `pause_decision: finalize` and the run advances into `plan_completion`. The PR body is already assembled, so this re-assert is cheap.

## ci_monitor

Monitor CI on the shared branch until all checks pass AND merge state is clean.

Read `${CLAUDE_PLUGIN_ROOT}/skills/work-on/references/phases/phase-6-pr.md` for CI monitoring guidance.

Both gates read the PR this run owns on its settled branch, resolved through `owned-pr.sh` on the recorded repository: `owned_ci_passing` is the `ci_passing` check (every check in the `pass` or `skipping` bucket) and `owned_merge_state_clean` is the `merge_state_clean` check (the merge state is not `DIRTY`). To read the PR yourself, resolve it the same way:

```bash
PR=$({{PLUGIN_ROOT}}/skills/execute/scripts/owned-pr.sh \
  --repo "$(koto context get {{SESSION_NAME}} repos)" \
  --head "$(koto context get {{SESSION_NAME}} settled_branch)" --state open)
```

Empty output or exit 3 means no single owned PR: submit `ci_outcome: pr_adopt`. Exit 2 means the read failed: submit `ci_outcome: status_read`.

If the gate fails because a check failed, fix what you can, push the fix, and submit `ci_outcome: failing_fixed`. **Every fix push goes through `push-and-record.sh`**, which records the pushed commit as the run's expected head. A bare `git push` would leave the record behind the PR's head, and the merge step would then refuse to merge (`head-moved`):

```bash
{{PLUGIN_ROOT}}/skills/execute/scripts/push-and-record.sh {{SESSION_NAME}}
```

If failures are unresolvable, submit `ci_outcome: failing_unresolvable` with rationale.

**Waiting on CI is bounded, and not here.** If checks are still pending, don't loop in this state: submit `ci_outcome: pending`. `merge_readiness` reads the checks itself and waits on them against a per-head-commit deadline (1800 s from the head commit's date, `EXECUTE_CI_WAIT_LIMIT_SECS`), after which the run ends at `step=execute:ci-timeout`. `passing` (with both gates green), `failing_fixed`, and `pending` all go to `merge_readiness`; nothing here ends the run as green on your word.

**DIRTY-handling (#162).** If `gh pr view "$PR" --json mergeStateStatus --jq .mergeStateStatus` returns `DIRTY`, the PR has merge conflicts and GitHub will not create new check-runs. The `owned_ci_passing` gate command (the `ci_passing` check) evaluates `length == 0`, which is true (passing) when zero check-runs exist — the same gate fires for an actually-green PR and a DIRTY-suppressed PR. Do NOT loop on `ci_passing` when the merge state is DIRTY: the second gate, `owned_merge_state_clean` (the `merge_state_clean` check), distinguishes the two cases.

When `mergeStateStatus` is `DIRTY`, submit `ci_outcome: dirty_merge_state` with `rationale` naming the conflict files. The workflow routes to `escalate_dirty_merge_state` → `done_blocked` with the DIRTY-specific failure reason. The operator's recovery is to rebase the shared branch and resolve conflicts before re-running CI; the koto state machine does not retry automatically because the rebase requires judgment about which conflict resolution preserves the PLAN's intent.

## escalate_dirty_merge_state

The PR's merge state is DIRTY (conflicts with the target branch); GitHub has suppressed new check-runs. Submit `rationale` naming the conflict files; the workflow routes to `done_blocked` with the DIRTY-specific failure reason. The run's result is `outcome=ready-awaiting-merge` with `reason=merge-state:DIRTY`: nothing errored, and the PR waits on a human to resolve the conflict.

## plan_completion

Run the completion cascade that pulls the chain to its strict-mode passing state, then mark the PR ready -- unless the cascade reports `partial`, which halts the run instead (see below). The DRAFT-vs-READY discipline (#117) requires this ordering: cascade BEFORE `gh pr ready` so the CI re-run on the `ready_for_review` event sees the chain at its terminal.

The state runs two steps. The cascade script is the load-bearing element for the lifecycle verification — it invokes `shirabe validate --lifecycle-chain <seed> --mode=ready` internally at the pre-cascade probe and post-cascade verification points, parses exit codes deterministically, and fails fast on unexpected outcomes. The agent does not invoke the validator directly. The two probes seed on different documents and that is deliberate: the pre-probe seeds on `{{PLAN_DOC}}`, which is still on disk, and the post-probe seeds on a chain document that survived the finalization commit, because by then the PLAN has been `git rm`'d. Seeding the post-probe on the deleted PLAN returns an L05 that looks like a real failure and is not.

**Step 1: Run the cascade.** `run-cascade.sh --push` runs the pre-cascade probe (expects a strict-mode failure naming the present PLAN), performs the atomic finalization commit (PLAN deletion + BRIEF/PRD/DESIGN transitions), pushes, and runs the post-cascade verification (expects a clean pass). All three points are inside the script. The cascade also runs `handle_roadmap_deletion` which transitions the ROADMAP Active -> Done and `git rm`s the file in the same atomic finalization commit, gated by all-features-Done AND all-referenced-issues-closed.

```bash
RESULT=$(${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/run-cascade.sh --push --session {{SESSION_NAME}} {{PLAN_DOC}})
CASCADE_STATUS=$(echo "$RESULT" | jq -r '.cascade_status // empty')
```

`--session` makes the cascade's push record the pushed commit as the run's `expected_head`, exactly as `push-and-record.sh` does, and only after the push succeeds. The merge step compares the PR's head with that record; the `expected_head_recorded` gate on this state reports whether one exists. With no record the verdict names `head-moved` and the run ends ready-awaiting-merge rather than merging.

If the pre-probe sees a clean pass — the chain is already at its strict-mode terminal — the script emits `cascade_status: skipped` with a single `lifecycle_pre_probe` step recording the no-op, exits 0, and the cascade proceeds directly to step 2 without performing any transitions. If the post-verify sees a failure, the script logs the validator's output and emits `cascade_status: partial`; halt and surface the failure.

**A `partial` verdict halts the run. Do not proceed to step 2.** `partial` means at least one step failed, and the verdict alone does not say which shape you have -- some leave the chain unfinalized or never pushed, and marking such a PR ready puts it in review against a chain CI will reject. The halt is not free: a walk that stopped on an unrecognized node still commits, pushes and verifies the part it did walk, and a PR in that shape stalls for a human who reads the steps array and clears it.

Match on the verdict captured in step 1, and surface every failed step:

```bash
case "$CASCADE_STATUS" in
    completed|skipped)
        : # the finalization is published; continue to step 2
        ;;
    *)
        echo "$RESULT" | jq -r '.steps[]? | select(.status == "failed") | "\(.action): \(.detail)"'
        exit 1  # partial, or no parseable verdict: stop, do NOT run step 2
        ;;
esac
```

Match the two good verdicts rather than testing for `partial`. The script exits non-zero on a setup or precondition failure with its JSON on stderr, so `$CASCADE_STATUS` can be the empty string -- which is not `partial`, and is certainly not a reason to mark a PR ready.

Checking for a failed `commit` or `push` step is NOT sufficient either, because the most damaging shape emits neither. When the chain walk is refused outright, the script deliberately declines to commit anything -- the report carries a refused `transition_*` step, no `commit` step and no `push` step, and the remote is untouched. A check that looked only for failed publish steps would read that as success.

Surface the failing step's `detail` and stop. The shapes differ in what recovery means, so name which one you hit:

- A failed `push`: the finalization commit is in local history and the fix is to push it.
- A failed `commit`: nothing landed, and the transitions are still staged in the working tree. Read the step's `detail` for what git refused, fix that, and re-run the cascade from a restored tree (`git reset --hard HEAD`) -- the PLAN has already been removed from the working tree, so the script will not start again without it.
- A refused `transition_*` with NO `commit` step: the cascade published nothing on purpose. The full chain is still in HEAD, so `git reset --hard HEAD` restores the tree; fix the node that was refused and run the cascade again.
- A refused `transition_*` WITH `commit` and `push` at `ok`: the walk stopped partway and published what it had reached. The remote already carries that commit, so recovery is a follow-up commit or a revert, not a reset.
- A failed `lifecycle_post_verify`: the finalization was published but the chain did not reach its terminal state. Surface the validator findings in the step's `detail` rather than guessing at a cause -- it is often a cascade bug, but a node the retirement guard declined to transition because a live sibling still references it produces the same failure and is not one.

**Step 2: Mark the PR ready for review.**

```bash
# The owned PR on the settled branch. Empty output or exit 3 submits
# cascade_status: pr_adopt; exit 2 submits cascade_status: status_read.
PR=$({{PLUGIN_ROOT}}/skills/execute/scripts/owned-pr.sh \
  --repo "$(koto context get {{SESSION_NAME}} repos)" \
  --head "$(koto context get {{SESSION_NAME}} settled_branch)" --state open)
gh pr ready "$PR"
```

The CI workflow re-runs on the `ready_for_review` event with strict mode set, and the check should pass on the now-finalized chain. If `gh pr ready` fails, carry on and submit the cascade's verdict: the PR stays a draft, and `merge_readiness`'s verdict ends the run at `step=execute:ready` without merging.

On a `completed` or `skipped` verdict, submit `cascade_status` from the JSON output and a brief `cascade_detail` summarising what ran (which transitions, which paths, post-cascade verification outcome). On a `partial`, submit nothing: the verdict routes to `ci_monitor` like the other two, whose gates can evaluate clean on a still-DRAFT PR and reach a non-failure terminal, so submitting would report a failed cascade as a successful run.

- `cascade_status: completed` — pre-probe saw the expected mid-PR failure, all applicable transitions ran successfully, post-verify saw the expected clean pass
- `cascade_status: partial` — some steps ran but at least one failed (a transition was refused, an upstream was missing, the finalization commit or push failed, or the post-verify failed); halt and inspect the `steps` array for the failure detail. Do not mark the PR ready on a `partial`.
- `cascade_status: skipped` — pre-probe saw a clean pass (chain already terminal) or the PLAN doc had no `upstream` field; no transitions were performed. Note that the second of those still commits and pushes: the PLAN's own deletion is part of the finalization, so a no-upstream chain publishes that one change and reports `skipped` about the chain walk it did not have to do.

- `cascade_status: pr_adopt` / `status_read` — the owned-PR lookup in front of `gh pr ready` found no single owned PR, or its read failed. Both end the run at `done_blocked` (`execute:pr-adopt`, `execute:status-read`) without marking anything ready.

The three cascade values route to `ci_monitor` in the state machine, which waits for the strict-mode CI run to land green on the now-ready PR. There is no separate terminal for `partial`, so the halt is the agent's to observe rather than the machine's to enforce; rerouting it would be a behavioural change to this workflow with its own design. On a `partial`, the thing that must not happen is `gh pr ready` -- surface the failed steps to the human and stop there.

## escalate

One or more children reached `done_blocked` or were skipped due to dependency failure. Inspect `batch_final_view` to understand which children failed and why.

Read `koto context get {{SESSION_NAME}} batch_final_view` to get the full per-child data. Summarize:
- Which children failed (name + `reason` field)
- Which children were skipped (name + `skipped_because_chain`)
- What the user should do to resolve the blockers

Submit `failure_reason` with this summary. The workflow routes to `done_blocked` and the `failure_reason` is written to context for the batch view.

## merge_readiness

Recording the merge verdict. koto runs the record script itself on entry; you only see this state if it could not.

<!-- details -->

The command is `skills/execute/scripts/record-merge-verdict.sh`. It clears `merge_verdict`, `home_pr`, `reason`, `step`, and `waiting`; resolves the PR with `owned-pr.sh --state all` on the recorded repository and the settled branch (so a PR that already merged is still found); runs `merge-verdict.sh` with this invocation's merge intent (`{{MERGE}}`) and the recorded `expected_head`, or `none` when there is no record; and writes the verdict line, plus its condition as `reason` or its step as `step`, only when each matches its pattern. It reads GitHub and writes koto context, nothing else: no push, no merge, no GitHub write.

On the passing path the run advances to `merge_route` with no evidence and you never read this.

You are here because the script failed, and the response above carries its exit code and its own stderr. Tick again to re-run it; the keys it owns were cleared first, so nothing stale can be read as current. If it keeps failing, submit `readiness_status: blocked` with `detail`, which ends the run at `done_blocked` with `step=execute:status-read`.

Evidence schema (optional; the passing path submits neither):
- `readiness_status`: `blocked`
- `detail`: why no verdict could be recorded

## merge_route

The merge verdict is recorded, and it says to wait.

`merge_route` routes on the recorded verdict alone, through gates no override can stand in for: `merged` goes to `merge_confirm`, `mergeable:<method>:<sha>` to `merge_attempt`, `awaiting:<condition>` to `ready_awaiting_merge`, and `error:execute:<step>` to `done_blocked`. You see this state only when the verdict is `pending:checks` or `pending:merge-state` (checks are still running, or GitHub has not computed the merge state yet), or when no verdict is recorded at all.

Read it with `koto context get {{SESSION_NAME}} merge_verdict`. Wait a minute or two, then submit `recheck: waited`; `merge_readiness` recomputes the verdict. You don't need to track the time yourself: the verdict measures the CI deadline from the head commit's date, so a check still pending past it comes back as `error:execute:ci-timeout` and ends the run. Don't write `merge_verdict` yourself; a value outside the verdict grammar ends the run at `step=execute:status-read`.

Evidence schema:
- `recheck`: `waited`

## merge_attempt

The verdict is `mergeable`, and this invocation asked to merge (`--merge`). Run the merge call exactly once:

```bash
REPO=$(koto context get {{SESSION_NAME}} repos)
HOME_PR=$(koto context get {{SESSION_NAME}} home_pr)
EXPECTED=$(koto context get {{SESSION_NAME}} expected_head)
LINE=$({{PLUGIN_ROOT}}/skills/execute/scripts/merge-exec.sh "$REPO" "${HOME_PR##*/}" "$EXPECTED")
echo "$LINE"
```

The repository is the write set recorded at start, the PR is the one `record-merge-verdict.sh` recorded from the ownership-filtered lookup, and the expected head is the commit this run's own push recorded. Take none of them from anywhere else. `merge-exec.sh` recomputes the verdict itself immediately before the call and merges only when it is still `mergeable` at that expected head, with the one fixed call `gh pr merge <pr> --repo <repo> --<method> --match-head-commit <sha>`: no `--admin`, no `--auto`, no retry with another method.

Submit `merge_exec: called` when it printed `merge-called:<method>:<sha>`, or `merge_exec: refused` when it printed `merge-refused:<...>`, with the line as `merge_line`. `called` is not merged: `merge_confirm` re-reads the PR, and only a live `MERGED` read ends the run merged. `refused` ends it ready-awaiting-merge with `reason=merge-call-failed`.

This state is presented only when this invocation's `MERGE` is `true`. The `merge_intent` gate re-checks it on every tick that reaches the state and cannot be overridden; when it is `false` (a run resumed without `--merge`), the state routes straight to `ready_awaiting_merge` with `reason=merge-not-requested` before asking for anything, and `merge-exec.sh` never runs.

Evidence schema:
- `merge_exec`: `called` or `refused`
- `merge_line`: the line `merge-exec.sh` printed

## merge_confirm

Confirming the merge. koto runs the confirm read itself on entry; you only see this state if it could not.

<!-- details -->

The command is `record-merge-verdict.sh --confirm`. It clears `confirm_verdict`, resolves the owned PR again on the recorded repository and settled branch (never from anything submitted at `merge_attempt`), runs `merge-verdict.sh --confirm` on it, which re-reads the PR's state for up to 20 seconds, and records `merged` or `not-merged:merge-not-observed`. A recorded `merged` goes to `merged`; anything else, an absent record included, goes to `ready_awaiting_merge` with `reason=merge-not-observed`. This is the only way into `merged`.

You are here because the script failed; the response above carries its exit code and stderr. Tick again to re-run it. If it keeps failing, submit `confirm_status: unreadable`, which re-evaluates the gate on the cleared key and ends the run ready-awaiting-merge naming merge-not-observed, never merged.

Evidence schema (optional; the passing path submits neither):
- `confirm_status`: `unreadable`

## merged

The PR merged, and a live read confirmed it. Render the exit lines from the terminal result; don't compose them yourself:

```bash
koto status {{SESSION_NAME}} | {{PLUGIN_ROOT}}/skills/execute/scripts/print-exit.sh
```

## ready_awaiting_merge

The PR is ready, and the run did not merge it. The result's `reason` names why: the merge wasn't requested, a review or protection rule stands in the way, the head moved, the merge call failed, or a merge wasn't observed yet (the PR may still be queued and may merge later). Render the exit lines from the terminal result; don't compose them yourself:

```bash
koto status {{SESSION_NAME}} | {{PLUGIN_ROOT}}/skills/execute/scripts/print-exit.sh
```

## paused_for_review

The run is **paused for review** (D2, interactive mode). `pr_finalization` assembled a template-conformant DRAFT PR, and `PAUSE_BEFORE_FINALIZE` was `true`, so the run stopped here BEFORE the `plan_completion` finalization cascade. This is a **solicited suspension**, not a failure and not a completion: the chain is intact and resumable.

Render the operator hand-back from the terminal result; it carries the DRAFT PR, the write set, and the resume command:

```bash
koto status {{SESSION_NAME}} | {{PLUGIN_ROOT}}/skills/execute/scripts/print-exit.sh
```

- **Confirmation the chain is intact** — the PLAN is still present on disk and BRIEF/PRD/DESIGN/ROADMAP are un-transitioned; `gh pr ready` has NOT fired, so the PR is still DRAFT.
- **The resume instruction** — re-invoke `/execute <plan>` on the same topic to finalize. The retained paused session is replaced (`--replace-terminal`), the new run adopts the still-open DRAFT PR on its branch with `PAUSE_BEFORE_FINALIZE=false`, and it advances through `pr_finalization` into `plan_completion`, which runs the cascade DRAFT-before-READY, flips `gh pr ready` on a `completed` or `skipped` verdict, and monitors CI.

At the `/execute` SKILL layer this terminal maps to a suspension: `exit:` stays UNSET with a resumable `paused_for_review` state marker, so the R9 hard-finalization check — which fires only at one of the three terminal exits — is not tripped. See `skills/execute/SKILL.md` (**Exit Paths**, suspension semantics).

## done

A session started from an earlier version of this template stopped here. No transition reaches this state any more; it stays so such a session still resolves. Its result reports `outcome=ready-awaiting-merge`: the run left the PR ready and did not merge it.

## done_blocked

Plan orchestration reached a blocking condition. One of: the write set or setup could not be recorded, no single owned PR could be found, some children failed and could not be resolved, the PR could not be finalized, CI failures are unresolvable, the merge verdict is an error, or the PR's merge state is DIRTY.

The result carries `outcome` and, on an error, the `step`; the DIRTY route carries `outcome=ready-awaiting-merge` with `reason=merge-state:DIRTY`. Render the exit lines from it:

```bash
koto status {{SESSION_NAME}} | {{PLUGIN_ROOT}}/skills/execute/scripts/print-exit.sh
```

The `failure_reason` context key contains the details. Use `koto context get {{SESSION_NAME}} failure_reason` to read it.
