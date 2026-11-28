```mermaid
stateDiagram-v2
    direction LR
    [*] --> entry
    analysis --> offload_canary : gates.plan_artifact.exists: true, plan_outcome: plan_ready
    analysis --> done_already_complete : plan_outcome: already_complete
    analysis --> analysis : plan_outcome: scope_changed_retry
    analysis --> decide_first : plan_outcome: scope_changed_escalate
    analysis --> decide_first : plan_outcome: blocked_missing_context
    cascade_entry --> cascade_run : gates.anchor_present.exit_code: 0
    cascade_entry --> done : gates.anchor_present.exit_code: 1
    cascade_entry --> done_blocked : gates.anchor_present.exit_code: 2
    cascade_run --> done_blocked : cascade_status: partial
    cascade_run --> done : cascade_status: completed, post_state: verified
    cascade_run --> done : cascade_status: skipped, post_state: verified
    cascade_run --> done_blocked : cascade_status: completed, post_state: plan_present
    cascade_run --> done_blocked : cascade_status: completed, post_state: no_commit
    cascade_run --> done_blocked : cascade_status: completed, post_state: wrong_status
    cascade_run --> done_blocked : cascade_status: completed, post_state: not_in_commit
    cascade_run --> done_blocked : cascade_status: completed, post_state: undecided
    cascade_run --> done_blocked : cascade_status: skipped, post_state: plan_present
    cascade_run --> done_blocked : cascade_status: skipped, post_state: no_commit
    cascade_run --> done_blocked : cascade_status: skipped, post_state: wrong_status
    cascade_run --> done_blocked : cascade_status: skipped, post_state: not_in_commit
    cascade_run --> done_blocked : cascade_status: skipped, post_state: undecided
    changed_paths_record --> issue_type_routing : gates.changed_paths_recorded.exists: true
    changed_paths_record --> issue_type_routing : gates.changed_paths_recorded.exists: false, paths_status: override
    changed_paths_record --> done_blocked : gates.changed_paths_recorded.exists: false, paths_status: blocked
    check_exit --> done_blocked
    ci_monitor --> ci_pass_counting : gates.ci_passing.exit_code: 0, gates.hosted_settled.exit_code: 0, gates.hosted_twins.exit_code: 0, gates.merge_state_clean.exit_code: 0, gates.probe_value_absent.exit_code: 0
    ci_monitor --> verification : gates.ci_passing.exit_code: 0, gates.hosted_settled.exit_code: 0, gates.hosted_twins.exit_code: 1, gates.merge_state_clean.exit_code: 0, gates.probe_value_absent.exit_code: 0
    ci_monitor --> hosted_record : gates.ci_passing.exit_code: 0, gates.hosted_settled.exit_code: 1, gates.merge_state_clean.exit_code: 0, gates.probe_value_absent.exit_code: 0
    ci_monitor --> done_blocked : gates.ci_passing.exit_code: 0, gates.merge_state_clean.exit_code: 1
    ci_monitor --> done_blocked : gates.ci_passing.exit_code: 1, gates.merge_state_clean.exit_code: 1
    ci_monitor --> ci_monitor : ci_outcome: failing_fixed, gates.ci_passing.exit_code: 1, gates.merge_state_clean.exit_code: 0
    ci_monitor --> done_blocked : ci_outcome: failing_unresolvable, gates.ci_passing.exit_code: 1, gates.merge_state_clean.exit_code: 0
    ci_pass_counting --> cascade_entry : gates.fix_green.exit_code: 0, gates.is_root.exit_code: 0, gates.tests_counted.exit_code: 0
    ci_pass_counting --> done : gates.fix_green.exit_code: 0, gates.is_root.exit_code: 1, gates.tests_counted.exit_code: 0
    ci_pass_counting --> done_blocked : gates.tests_counted.exit_code: 3
    ci_pass_counting --> ci_monitor : counting_status: green_failed, gates.fix_green.exit_code: 1, gates.tests_counted.exit_code: 0
    ci_pass_counting --> ci_monitor : counting_status: green_failed, gates.fix_green.exit_code: 1, gates.tests_counted.exit_code: 1
    ci_pass_counting --> ci_monitor : counting_status: declined, gates.tests_counted.exit_code: 1
    ci_pass_counting --> implementation : counting_status: test_gap, gates.tests_counted.exit_code: 1
    ci_pass_counting --> implementation : counting_status: test_gap, gates.fix_green.exit_code: 1, gates.tests_counted.exit_code: 0
    ci_pass_counting --> done_blocked : counting_status: blocked, gates.fix_green.exit_code: 1, gates.tests_counted.exit_code: 0
    ci_pass_counting --> done_blocked : counting_status: blocked, gates.fix_green.exit_code: 2, gates.tests_counted.exit_code: 0
    ci_pass_counting --> done_blocked : counting_status: blocked, gates.tests_counted.exit_code: 1
    ci_pass_counting --> done_blocked : counting_status: blocked, gates.tests_counted.exit_code: 2
    context_injection --> setup_issue_backed : gates.await_removals.exit_code: 0, gates.context_artifact.exists: true, status: completed
    context_injection --> setup_issue_backed : gates.await_removals.exit_code: 0, status: override
    context_injection --> done_blocked : status: blocked
    decide_first --> waiting_record : decide_outcome: raised, gates.attempt_recorded.exit_code: 3
    decide_first --> analysis : decide_outcome: decided, decided_next: resume, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 10, gates.decide_laps.exit_code: 0
    decide_first --> implementation : decide_outcome: decided, decided_next: resume, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 11, gates.decide_laps.exit_code: 0
    decide_first --> introspection : decide_outcome: decided, decided_next: resume, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 12, gates.decide_laps.exit_code: 0
    decide_first --> task_validation : decide_outcome: decided, decided_next: resume, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 13, gates.decide_laps.exit_code: 0
    decide_first --> post_research_validation : decide_outcome: decided, decided_next: resume, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 14, gates.decide_laps.exit_code: 0
    decide_first --> plan_validation : decide_outcome: decided, decided_next: resume, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 15, gates.decide_laps.exit_code: 0
    decide_first --> deferral_approval : decide_outcome: decided, decided_next: resume, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 16, gates.decide_laps.exit_code: 0
    decide_first --> done_blocked : decide_outcome: decided, decided_next: stop, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 10
    decide_first --> done_blocked : decide_outcome: decided, decided_next: stop, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 11
    decide_first --> done_blocked : decide_outcome: decided, decided_next: stop, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 12
    decide_first --> validation_exit : decide_outcome: decided, decided_next: stop, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 13
    decide_first --> validation_exit : decide_outcome: decided, decided_next: stop, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 14
    decide_first --> validation_exit : decide_outcome: decided, decided_next: stop, gates.attempt_recorded.exit_code: 0, gates.decide_from.exit_code: 15
    deferral_approval --> pr_precheck : approval_decision: approved, cleanup_done: removed, design_diagram: updated, gates.answer_cited.exit_code: 0, gates.cleanup_referent.exit_code: 0, gates.commit_convention.exit_code: 0, gates.diagram_referent.exit_code: 0, gates.summary_exists.exists: true, gates.summary_shape.matches: true
    deferral_approval --> pr_precheck : approval_decision: approved, cleanup_done: removed, design_diagram: not_applicable, gates.answer_cited.exit_code: 0, gates.cleanup_referent.exit_code: 0, gates.commit_convention.exit_code: 0, gates.diagram_referent.exit_code: 0, gates.summary_exists.exists: true, gates.summary_shape.matches: true
    deferral_approval --> pr_precheck : approval_decision: approved, cleanup_done: none_found, design_diagram: updated, gates.answer_cited.exit_code: 0, gates.cleanup_referent.exit_code: 0, gates.commit_convention.exit_code: 0, gates.diagram_referent.exit_code: 0, gates.summary_exists.exists: true, gates.summary_shape.matches: true
    deferral_approval --> pr_precheck : approval_decision: approved, cleanup_done: none_found, design_diagram: not_applicable, gates.answer_cited.exit_code: 0, gates.cleanup_referent.exit_code: 0, gates.commit_convention.exit_code: 0, gates.diagram_referent.exit_code: 0, gates.summary_exists.exists: true, gates.summary_shape.matches: true
    deferral_approval --> done_blocked : approval_decision: rejected, gates.answer_cited.exit_code: 0
    deferral_approval --> decide_first : approval_decision: needs_answer
    entry --> context_injection : gates.continues_waiting.exists: false, mode: issue_backed
    entry --> task_validation : gates.continues_waiting.exists: false, mode: free_form
    entry --> plan_context_injection : gates.continues_waiting.exists: false, mode: plan_backed
    entry --> skipped_due_to_dep_failure : gates.continues_waiting.exists: false, mode: skipped
    entry --> resume_waiting : gates.continues_waiting.exists: true
    finalization --> implementation : finalization_status: issues_found
    finalization --> check_exit : finalization_status: check_unsatisfiable, gates.commit_convention.exit_code: 1
    finalization --> pr_precheck : cleanup_done: removed, design_diagram: updated, finalization_status: ready_for_pr, gates.cleanup_referent.exit_code: 0, gates.commit_convention.exit_code: 0, gates.diagram_referent.exit_code: 0, gates.summary_exists.exists: true, gates.summary_shape.matches: true
    finalization --> pr_precheck : cleanup_done: removed, design_diagram: not_applicable, finalization_status: ready_for_pr, gates.cleanup_referent.exit_code: 0, gates.commit_convention.exit_code: 0, gates.diagram_referent.exit_code: 0, gates.summary_exists.exists: true, gates.summary_shape.matches: true
    finalization --> pr_precheck : cleanup_done: none_found, design_diagram: updated, finalization_status: ready_for_pr, gates.cleanup_referent.exit_code: 0, gates.commit_convention.exit_code: 0, gates.diagram_referent.exit_code: 0, gates.summary_exists.exists: true, gates.summary_shape.matches: true
    finalization --> pr_precheck : cleanup_done: none_found, design_diagram: not_applicable, finalization_status: ready_for_pr, gates.cleanup_referent.exit_code: 0, gates.commit_convention.exit_code: 0, gates.diagram_referent.exit_code: 0, gates.summary_exists.exists: true, gates.summary_shape.matches: true
    finalization --> deferral_approval : finalization_status: deferral_requested
    fix_determination --> implementation : gates.kind_route.exit_code: 0
    fix_determination --> reproduce : gates.kind_route.exit_code: 3
    fix_determination --> done_blocked : gates.kind_route.exit_code: 1, gates.kind_unchanged.exit_code: 1, kind_status: blocked
    fix_determination --> done_blocked : gates.kind_route.exit_code: 4, gates.kind_unchanged.exit_code: 1, kind_status: blocked
    fix_determination --> done_blocked : gates.kind_route.exit_code: 66, gates.kind_unchanged.exit_code: 1, kind_status: blocked
    fix_determination --> done_blocked : gates.kind_route.exit_code: 2, gates.kind_unchanged.exit_code: 2, kind_status: blocked
    hosted_record --> ci_monitor : gates.hosted_read.exit_code: 0, gates.hosted_ready.exit_code: 0
    hosted_record --> verification : gates.hosted_read.exit_code: 1, vars.VERIFICATION: local
    hosted_record --> verification_deferred : gates.hosted_read.exit_code: 1, vars.VERIFICATION: hosted-ci
    hosted_record --> verification_plan : gates.hosted_read.exit_code: 1, vars.VERIFICATION: auto
    hosted_record --> done_blocked : gates.hosted_read.exit_code: 3
    hosted_record --> done_blocked : gates.hosted_read.exit_code: 75, hosted_status: blocked
    hosted_record --> done_blocked : gates.hosted_read.exit_code: 2, hosted_status: blocked
    hosted_record --> done_blocked : gates.hosted_read.exit_code: -1, hosted_status: blocked
    implementation --> changed_paths_record : gates.on_feature_branch_impl.exit_code: 0, implementation_status: complete
    implementation --> changed_paths_record : gates.on_feature_branch_impl.exit_code: 0, implementation_status: verification_rerun
    implementation --> implementation : implementation_status: partial_tests_failing_retry
    implementation --> analysis : implementation_status: scope_expanded_retry
    implementation --> decide_first : implementation_status: partial_tests_failing_escalate
    implementation --> decide_first : implementation_status: blocked
    introspection --> decide_first : introspection_outcome: issue_superseded
    introspection --> analysis : gates.introspection_artifact.exists: true, introspection_outcome: approach_unchanged
    introspection --> analysis : gates.introspection_artifact.exists: true, introspection_outcome: approach_updated
    introspection --> analysis
    issue_type_routing --> review_level_check : gates.code_route.exit_code: 0
    issue_type_routing --> review_level_check : gates.code_route.exit_code: 1, issue_type: code
    issue_type_routing --> verification : gates.code_route.exit_code: 1, gates.has_commits.exit_code: 0, issue_type: docs, vars.VERIFICATION: local
    issue_type_routing --> verification_deferred : gates.code_route.exit_code: 1, gates.has_commits.exit_code: 0, issue_type: docs, vars.VERIFICATION: hosted-ci
    issue_type_routing --> verification_plan : gates.code_route.exit_code: 1, gates.has_commits.exit_code: 0, issue_type: docs, vars.VERIFICATION: auto
    issue_type_routing --> verification : gates.code_route.exit_code: 1, issue_type: task, vars.VERIFICATION: local
    issue_type_routing --> verification_deferred : gates.code_route.exit_code: 1, issue_type: task, vars.VERIFICATION: hosted-ci
    issue_type_routing --> verification_plan : gates.code_route.exit_code: 1, issue_type: task, vars.VERIFICATION: auto
    light_review --> verification : gates.audited.exit_code: 1, gates.level_unchanged.exit_code: 0, gates.light_carried.exit_code: 0, gates.light_escalate.exit_code: 1, gates.light_level.exit_code: 11, vars.VERIFICATION: local
    light_review --> verification_deferred : gates.audited.exit_code: 1, gates.level_unchanged.exit_code: 0, gates.light_carried.exit_code: 0, gates.light_escalate.exit_code: 1, gates.light_level.exit_code: 11, vars.VERIFICATION: hosted-ci
    light_review --> verification_plan : gates.audited.exit_code: 1, gates.level_unchanged.exit_code: 0, gates.light_carried.exit_code: 0, gates.light_escalate.exit_code: 1, gates.light_level.exit_code: 11, vars.VERIFICATION: auto
    light_review --> verification : gates.audited.exit_code: 1, gates.has_commits.exit_code: 0, gates.level_unchanged.exit_code: 0, gates.light_carried.exit_code: 1, gates.light_escalate.exit_code: 1, gates.light_level.exit_code: 11, gates.light_recorded.exit_code: 0, gates.light_verdict.exit_code: 0, vars.VERIFICATION: local
    light_review --> verification_deferred : gates.audited.exit_code: 1, gates.has_commits.exit_code: 0, gates.level_unchanged.exit_code: 0, gates.light_carried.exit_code: 1, gates.light_escalate.exit_code: 1, gates.light_level.exit_code: 11, gates.light_recorded.exit_code: 0, gates.light_verdict.exit_code: 0, vars.VERIFICATION: hosted-ci
    light_review --> verification_plan : gates.audited.exit_code: 1, gates.has_commits.exit_code: 0, gates.level_unchanged.exit_code: 0, gates.light_carried.exit_code: 1, gates.light_escalate.exit_code: 1, gates.light_level.exit_code: 11, gates.light_recorded.exit_code: 0, gates.light_verdict.exit_code: 0, vars.VERIFICATION: auto
    light_review --> scrutiny : gates.audited.exit_code: 0, gates.level_unchanged.exit_code: 0, gates.light_carried.exit_code: 0, gates.light_escalate.exit_code: 1, gates.light_level.exit_code: 11
    light_review --> scrutiny : gates.audited.exit_code: 0, gates.has_commits.exit_code: 0, gates.level_unchanged.exit_code: 0, gates.light_carried.exit_code: 1, gates.light_escalate.exit_code: 1, gates.light_level.exit_code: 11, gates.light_recorded.exit_code: 0, gates.light_verdict.exit_code: 0
    light_review --> review_level_check : gates.light_level.exit_code: 12, light_outcome: escalate
    light_review --> review_level_check : gates.light_level.exit_code: 13, light_outcome: escalate
    light_review --> implementation : gates.light_carried.exit_code: 1, gates.light_recorded.exit_code: 0, gates.light_verdict.exit_code: 1, light_outcome: blocking_retry
    light_review --> done_blocked : gates.light_carried.exit_code: 1, gates.light_verdict.exit_code: 1, light_outcome: blocking_escalate
    light_review --> done_blocked : gates.light_carried.exit_code: 1, gates.light_verdict.exit_code: 2, light_outcome: blocking_escalate
    offload_arm_preloaded --> probe_draw
    offload_arm_withheld --> probe_draw
    offload_canary --> offload_arm_withheld : gates.offload_arm.exit_code: 0
    offload_canary --> offload_arm_preloaded : gates.offload_arm.exit_code: 1
    offload_canary --> probe_draw : gates.offload_arm.exit_code: 3
    pass_counting --> finalization : gates.fix_green.exit_code: 0, gates.tests_counted.exit_code: 0
    pass_counting --> done_blocked : gates.tests_counted.exit_code: 3
    pass_counting --> implementation : counting_status: green_failed, gates.fix_green.exit_code: 1, gates.tests_counted.exit_code: 0
    pass_counting --> implementation : counting_status: green_failed, gates.fix_green.exit_code: 1, gates.tests_counted.exit_code: 1
    pass_counting --> implementation : counting_status: declined, gates.tests_counted.exit_code: 1
    pass_counting --> implementation : counting_status: test_gap, gates.tests_counted.exit_code: 1
    pass_counting --> implementation : counting_status: test_gap, gates.fix_green.exit_code: 1, gates.tests_counted.exit_code: 0
    pass_counting --> done_blocked : counting_status: blocked, gates.fix_green.exit_code: 1, gates.tests_counted.exit_code: 0
    pass_counting --> done_blocked : counting_status: blocked, gates.fix_green.exit_code: 2, gates.tests_counted.exit_code: 0
    pass_counting --> done_blocked : counting_status: blocked, gates.tests_counted.exit_code: 1
    pass_counting --> done_blocked : counting_status: blocked, gates.tests_counted.exit_code: 2
    plan_context_injection --> setup_plan_backed : gates.await_removals.exit_code: 0, gates.context_artifact.exists: true, issue_source: github, status: completed
    plan_context_injection --> plan_validation : gates.await_removals.exit_code: 0, gates.context_artifact.exists: true, issue_source: plan_outline, status: completed
    plan_context_injection --> setup_plan_backed : gates.await_removals.exit_code: 0, status: override
    plan_context_injection --> done_blocked : status: blocked
    plan_validation --> setup_plan_backed : gates.step_detail.exit_code: 0, verdict: proceed
    plan_validation --> decide_first : verdict: exit
    post_research_validation --> setup_free_form : gates.await_removals.exit_code: 0, verdict: ready
    post_research_validation --> decide_first : verdict: needs_design
    post_research_validation --> decide_first : verdict: exit
    pr_creation --> check_exit : gates.pr_body_conformant.exit_code: 1, pr_status: check_unsatisfiable
    pr_creation --> ci_monitor : gates.closing_keyword.exit_code: 0, gates.hosted_record_line.exit_code: 0, gates.pr_body_conformant.exit_code: 0, gates.probe_ack.exit_code: 0, gates.probe_value_absent.exit_code: 0, gates.verification_deferral_recorded.exit_code: 0, gates.verification_rerun_recorded.exit_code: 0, pr_status: created
    pr_creation --> ci_monitor : gates.closing_keyword.exit_code: 0, gates.hosted_record_line.exit_code: 0, gates.pr_body_conformant.exit_code: 0, gates.probe_ack.exit_code: 4, gates.probe_value_absent.exit_code: 0, gates.verification_deferral_recorded.exit_code: 0, gates.verification_rerun_recorded.exit_code: 0, pr_status: created
    pr_creation --> ci_monitor : gates.closing_keyword.exit_code: 0, gates.hosted_record_line.exit_code: 0, gates.pr_body_conformant.exit_code: 0, gates.probe_ack.exit_code: 5, gates.probe_value_absent.exit_code: 0, gates.verification_deferral_recorded.exit_code: 0, gates.verification_rerun_recorded.exit_code: 0, pr_status: created
    pr_creation --> ci_monitor : gates.closing_keyword.exit_code: 0, gates.hosted_record_line.exit_code: 0, gates.pr_body_conformant.exit_code: 0, gates.probe_ack.exit_code: 6, gates.probe_value_absent.exit_code: 0, gates.verification_deferral_recorded.exit_code: 0, gates.verification_rerun_recorded.exit_code: 0, pr_status: created
    pr_creation --> done_blocked : gates.closing_keyword.exit_code: 1, pr_status: created
    pr_creation --> done : pr_status: shared, vars.SHARED_BRANCH: {"is_set":true}
    pr_creation --> pr_creation : pr_status: creation_failed_retry
    pr_creation --> done_blocked : pr_status: creation_failed_escalate
    pr_precheck --> check_exit : gates.branch_docs_visibility.exit_code: 1, precheck_status: check_unsatisfiable
    pr_precheck --> probe_near : gates.branch_docs_visibility.exit_code: 0, gates.on_feature_branch_pr.exit_code: 0, gates.probe_value_absent.exit_code: 0, gates.tests_still_counted.exit_code: 0
    pr_precheck --> probe_near : gates.branch_docs_visibility.exit_code: 0, gates.on_feature_branch_pr.exit_code: 1, gates.probe_value_absent.exit_code: 0, gates.tests_still_counted.exit_code: 0, precheck_status: override
    pr_precheck --> pass_counting : gates.tests_still_counted.exit_code: 1, precheck_status: recount
    pr_precheck --> pass_counting : gates.tests_still_counted.exit_code: 3, precheck_status: recount
    pr_precheck --> done_blocked : gates.on_feature_branch_pr.exit_code: 1, precheck_status: blocked
    probe_arm_far --> fix_determination
    probe_arm_far_redeliver --> fix_determination
    probe_arm_near --> fix_determination
    probe_draw --> probe_arm_near : gates.probe_arm.exit_code: 0
    probe_draw --> probe_arm_far : gates.probe_arm.exit_code: 1
    probe_draw --> probe_arm_far_redeliver : gates.probe_arm.exit_code: 4
    probe_draw --> fix_determination : gates.probe_arm.exit_code: 3
    probe_near --> pr_creation
    qa_validation --> verification : gates.qa_carried.exit_code: 0, vars.VERIFICATION: local
    qa_validation --> verification_deferred : gates.qa_carried.exit_code: 0, vars.VERIFICATION: hosted-ci
    qa_validation --> verification_plan : gates.qa_carried.exit_code: 0, vars.VERIFICATION: auto
    qa_validation --> verification : gates.qa_carried.exit_code: 1, gates.qa_recorded.exit_code: 0, gates.qa_verdict.exit_code: 0, vars.VERIFICATION: local
    qa_validation --> verification_deferred : gates.qa_carried.exit_code: 1, gates.qa_recorded.exit_code: 0, gates.qa_verdict.exit_code: 0, vars.VERIFICATION: hosted-ci
    qa_validation --> verification_plan : gates.qa_carried.exit_code: 1, gates.qa_recorded.exit_code: 0, gates.qa_verdict.exit_code: 0, vars.VERIFICATION: auto
    qa_validation --> implementation : gates.qa_carried.exit_code: 1, gates.qa_recorded.exit_code: 0, gates.qa_verdict.exit_code: 1, qa_outcome: blocking_retry
    qa_validation --> done_blocked : gates.qa_carried.exit_code: 1, gates.qa_verdict.exit_code: 1, qa_outcome: blocking_escalate
    qa_validation --> done_blocked : gates.qa_carried.exit_code: 1, gates.qa_verdict.exit_code: 2, qa_outcome: blocking_escalate
    reproduce --> implementation : gates.red_recorded.exit_code: 0
    reproduce --> done_blocked : gates.red_recorded.exit_code: 1, reproduce_status: blocked
    reproduce --> done_blocked : gates.red_recorded.exit_code: 2, reproduce_status: blocked
    research --> post_research_validation
    resume_waiting --> analysis : gates.decide_resume.exit_code: 10
    resume_waiting --> implementation : gates.decide_resume.exit_code: 11
    resume_waiting --> introspection : gates.decide_resume.exit_code: 12
    resume_waiting --> task_validation : gates.decide_resume.exit_code: 13
    resume_waiting --> post_research_validation : gates.decide_resume.exit_code: 14
    resume_waiting --> plan_validation : gates.decide_resume.exit_code: 15
    resume_waiting --> deferral_approval : gates.decide_resume.exit_code: 16
    review --> verification : gates.level_unchanged.exit_code: 0, gates.review_carried.exit_code: 0, vars.REVIEW_LEVEL: standard, vars.VERIFICATION: local
    review --> verification_deferred : gates.level_unchanged.exit_code: 0, gates.review_carried.exit_code: 0, vars.REVIEW_LEVEL: standard, vars.VERIFICATION: hosted-ci
    review --> verification_plan : gates.level_unchanged.exit_code: 0, gates.review_carried.exit_code: 0, vars.REVIEW_LEVEL: standard, vars.VERIFICATION: auto
    review --> qa_validation : gates.level_unchanged.exit_code: 0, gates.review_carried.exit_code: 0, vars.REVIEW_LEVEL: full
    review --> qa_validation : gates.level_unchanged.exit_code: 0, gates.review_carried.exit_code: 0, vars.REVIEW_LEVEL: light
    review --> qa_validation : gates.level_unchanged.exit_code: 0, gates.review_carried.exit_code: 0, vars.REVIEW_LEVEL: {"is_set":false}
    review --> verification : gates.level_unchanged.exit_code: 0, gates.review_carried.exit_code: 1, gates.review_recorded.exit_code: 0, gates.review_verdict.exit_code: 0, vars.REVIEW_LEVEL: standard, vars.VERIFICATION: local
    review --> verification_deferred : gates.level_unchanged.exit_code: 0, gates.review_carried.exit_code: 1, gates.review_recorded.exit_code: 0, gates.review_verdict.exit_code: 0, vars.REVIEW_LEVEL: standard, vars.VERIFICATION: hosted-ci
    review --> verification_plan : gates.level_unchanged.exit_code: 0, gates.review_carried.exit_code: 1, gates.review_recorded.exit_code: 0, gates.review_verdict.exit_code: 0, vars.REVIEW_LEVEL: standard, vars.VERIFICATION: auto
    review --> qa_validation : gates.level_unchanged.exit_code: 0, gates.review_carried.exit_code: 1, gates.review_recorded.exit_code: 0, gates.review_verdict.exit_code: 0, vars.REVIEW_LEVEL: full
    review --> qa_validation : gates.level_unchanged.exit_code: 0, gates.review_carried.exit_code: 1, gates.review_recorded.exit_code: 0, gates.review_verdict.exit_code: 0, vars.REVIEW_LEVEL: light
    review --> qa_validation : gates.level_unchanged.exit_code: 0, gates.review_carried.exit_code: 1, gates.review_recorded.exit_code: 0, gates.review_verdict.exit_code: 0, vars.REVIEW_LEVEL: {"is_set":false}
    review --> implementation : gates.review_carried.exit_code: 1, gates.review_recorded.exit_code: 0, gates.review_verdict.exit_code: 1, review_outcome: blocking_retry
    review --> done_blocked : gates.review_carried.exit_code: 1, gates.review_verdict.exit_code: 1, review_outcome: blocking_escalate
    review --> done_blocked : gates.review_carried.exit_code: 1, gates.review_verdict.exit_code: 2, review_outcome: blocking_escalate
    review_level_check --> light_review : gates.level_floor.exit_code: 0, gates.level_route.exit_code: 11
    review_level_check --> scrutiny : gates.level_floor.exit_code: 0, gates.level_route.exit_code: 12
    review_level_check --> scrutiny : gates.level_floor.exit_code: 0, gates.level_route.exit_code: 13
    review_level_check --> done_blocked : gates.level_floor.exit_code: 1, level_status: blocked
    scrutiny --> review : gates.scrutiny_carried.exit_code: 0
    scrutiny --> review : gates.has_commits.exit_code: 0, gates.scrutiny_carried.exit_code: 1, gates.scrutiny_recorded.exit_code: 0, gates.scrutiny_verdict.exit_code: 0
    scrutiny --> implementation : gates.scrutiny_carried.exit_code: 1, gates.scrutiny_recorded.exit_code: 0, gates.scrutiny_verdict.exit_code: 1, scrutiny_outcome: blocking_retry
    scrutiny --> done_blocked : gates.scrutiny_carried.exit_code: 1, gates.scrutiny_verdict.exit_code: 1, scrutiny_outcome: blocking_escalate
    scrutiny --> done_blocked : gates.scrutiny_carried.exit_code: 1, gates.scrutiny_verdict.exit_code: 2, scrutiny_outcome: blocking_escalate
    setup_free_form --> analysis : gates.baseline_exists.exists: true, gates.on_feature_branch.exit_code: 0, status: completed
    setup_free_form --> analysis : status: override
    setup_free_form --> done_blocked : status: blocked
    setup_free_form --> analysis
    setup_issue_backed --> staleness_check : gates.baseline_exists.exists: true, gates.on_feature_branch.exit_code: 0, status: completed
    setup_issue_backed --> staleness_check : status: override
    setup_issue_backed --> done_blocked : status: blocked
    setup_issue_backed --> staleness_check
    setup_plan_backed --> analysis : vars.SHARED_BRANCH: {"is_set":true}
    setup_plan_backed --> analysis : gates.baseline_exists.exists: true, gates.on_feature_branch.exit_code: 0, status: completed, vars.SHARED_BRANCH: {"is_set":false}
    setup_plan_backed --> analysis : gates.baseline_exists.exists: true, status: override, vars.SHARED_BRANCH: {"is_set":false}
    setup_plan_backed --> done_blocked : status: blocked, vars.SHARED_BRANCH: {"is_set":false}
    staleness_check --> analysis : gates.staleness_fresh.exit_code: 0
    staleness_check --> introspection : gates.staleness_fresh.exit_code: 1
    staleness_check --> analysis : gates.staleness_fresh.exit_code: 3
    staleness_check --> analysis : gates.staleness_fresh.exit_code: -1
    staleness_check --> analysis : gates.staleness_fresh.exit_code: 2, staleness_signal: override
    staleness_check --> done_blocked : gates.staleness_fresh.exit_code: 2, staleness_signal: blocked
    task_validation --> research : verdict: proceed
    task_validation --> decide_first : verdict: exit
    verification --> pass_counting : gates.verification_verdict.exit_code: 0
    verification --> implementation : gates.verification_verdict.exit_code: 1
    verification --> done_blocked : gates.verification_verdict.exit_code: 3
    verification --> done_blocked : gates.verification_verdict.exit_code: 4
    verification --> verification_hosted : gates.route_reason_given.exit_code: 0, gates.verification_route.exit_code: 0, gates.verification_verdict.exit_code: 5, verification_status: hosted_of_record
    verification --> implementation : gates.verification_verdict.exit_code: 5, verification_status: fix
    verification --> done_blocked : gates.verification_verdict.exit_code: 5, verification_status: blocked
    verification --> verification : gates.route_reason_given.exit_code: 0, gates.verification_verdict.exit_code: 5, verification_status: rerun
    verification --> done_blocked : gates.verification_verdict.exit_code: 75, verification_status: blocked
    verification --> verification : gates.route_reason_given.exit_code: 0, gates.verification_verdict.exit_code: 75, verification_status: rerun
    verification --> done_blocked : gates.verification_verdict.exit_code: 2, verification_status: blocked
    verification --> done_blocked : gates.verification_verdict.exit_code: -1, verification_status: blocked
    verification_deferred --> pass_counting : vars.VERIFICATION: hosted-ci, vars.VERIFICATION_DEFERRAL_REASON: {"is_set":true}
    verification_deferred --> done_blocked : vars.VERIFICATION: hosted-ci, vars.VERIFICATION_DEFERRAL_REASON: {"is_set":false}
    verification_deferred --> pass_counting : vars.VERIFICATION: auto
    verification_hosted --> pass_counting : gates.hosted_record_valid.exit_code: 0
    verification_hosted --> verification : gates.hosted_record_valid.exit_code: 1, vars.VERIFICATION: local
    verification_hosted --> verification_deferred : gates.hosted_record_valid.exit_code: 1, vars.VERIFICATION: hosted-ci
    verification_hosted --> verification_plan : gates.hosted_record_valid.exit_code: 1, vars.VERIFICATION: auto
    verification_hosted --> done_blocked : gates.hosted_record_valid.exit_code: 2, hosted_status: blocked
    verification_hosted --> done_blocked : gates.hosted_record_valid.exit_code: -1, hosted_status: blocked
    verification_plan --> verification_deferred : gates.verification_route_plan.exit_code: 0
    verification_plan --> verification : gates.verification_route_plan.exit_code: 1
    verification_plan --> verification : gates.verification_route_plan.exit_code: 2
    verification_plan --> verification : gates.verification_route_plan.exit_code: -1
    waiting_record --> done_waiting : gates.question_recorded.exit_code: 0
    waiting_record --> decide_first : gates.question_recorded.exit_code: 1
    done --> [*]
    done_already_complete --> [*]
    done_blocked --> [*]
    done_waiting --> [*]
    skipped_due_to_dep_failure --> [*]
    validation_exit --> [*]
    note left of analysis
        gate: plan_artifact
    end note
    note left of cascade_entry
        gate: anchor_present
    end note
    note left of changed_paths_record
        gate: changed_paths_recorded
    end note
    note left of ci_monitor
        gate: ci_passing
    end note
    note left of ci_monitor
        gate: hosted_settled
    end note
    note left of ci_monitor
        gate: hosted_twins
    end note
    note left of ci_monitor
        gate: merge_state_clean
    end note
    note left of ci_monitor
        gate: probe_value_absent
    end note
    note left of ci_pass_counting
        gate: fix_green
    end note
    note left of ci_pass_counting
        gate: is_root
    end note
    note left of ci_pass_counting
        gate: tests_counted
    end note
    note left of context_injection
        gate: await_removals
    end note
    note left of context_injection
        gate: context_artifact
    end note
    note left of decide_first
        gate: attempt_recorded
    end note
    note left of decide_first
        gate: decide_from
    end note
    note left of decide_first
        gate: decide_laps
    end note
    note left of deferral_approval
        gate: answer_cited
    end note
    note left of deferral_approval
        gate: cleanup_referent
    end note
    note left of deferral_approval
        gate: commit_convention
    end note
    note left of deferral_approval
        gate: diagram_referent
    end note
    note left of deferral_approval
        gate: summary_exists
    end note
    note left of deferral_approval
        gate: summary_shape
    end note
    note left of entry
        gate: continues_waiting
    end note
    note left of finalization
        gate: cleanup_referent
    end note
    note left of finalization
        gate: commit_convention
    end note
    note left of finalization
        gate: diagram_referent
    end note
    note left of finalization
        gate: summary_exists
    end note
    note left of finalization
        gate: summary_shape
    end note
    note left of fix_determination
        gate: kind_route
    end note
    note left of fix_determination
        gate: kind_unchanged
    end note
    note left of hosted_record
        gate: hosted_read
    end note
    note left of hosted_record
        gate: hosted_ready
    end note
    note left of implementation
        gate: on_feature_branch_impl
    end note
    note left of introspection
        gate: introspection_artifact
    end note
    note left of issue_type_routing
        gate: code_route
    end note
    note left of issue_type_routing
        gate: has_commits
    end note
    note left of light_review
        gate: audited
    end note
    note left of light_review
        gate: has_commits
    end note
    note left of light_review
        gate: level_unchanged
    end note
    note left of light_review
        gate: light_carried
    end note
    note left of light_review
        gate: light_escalate
    end note
    note left of light_review
        gate: light_level
    end note
    note left of light_review
        gate: light_recorded
    end note
    note left of light_review
        gate: light_verdict
    end note
    note left of offload_canary
        gate: offload_arm
    end note
    note left of pass_counting
        gate: fix_green
    end note
    note left of pass_counting
        gate: tests_counted
    end note
    note left of plan_context_injection
        gate: await_removals
    end note
    note left of plan_context_injection
        gate: context_artifact
    end note
    note left of plan_validation
        gate: step_detail
    end note
    note left of post_research_validation
        gate: await_removals
    end note
    note left of pr_creation
        gate: closing_keyword
    end note
    note left of pr_creation
        gate: hosted_record_line
    end note
    note left of pr_creation
        gate: pr_body_conformant
    end note
    note left of pr_creation
        gate: probe_ack
    end note
    note left of pr_creation
        gate: probe_value_absent
    end note
    note left of pr_creation
        gate: verification_deferral_recorded
    end note
    note left of pr_creation
        gate: verification_rerun_recorded
    end note
    note left of pr_precheck
        gate: branch_docs_visibility
    end note
    note left of pr_precheck
        gate: on_feature_branch_pr
    end note
    note left of pr_precheck
        gate: probe_value_absent
    end note
    note left of pr_precheck
        gate: tests_still_counted
    end note
    note left of probe_draw
        gate: probe_arm
    end note
    note left of qa_validation
        gate: qa_carried
    end note
    note left of qa_validation
        gate: qa_recorded
    end note
    note left of qa_validation
        gate: qa_verdict
    end note
    note left of reproduce
        gate: red_recorded
    end note
    note left of resume_waiting
        gate: decide_resume
    end note
    note left of review
        gate: level_unchanged
    end note
    note left of review
        gate: review_carried
    end note
    note left of review
        gate: review_recorded
    end note
    note left of review
        gate: review_verdict
    end note
    note left of review_level_check
        gate: level_fits_facts
    end note
    note left of review_level_check
        gate: level_floor
    end note
    note left of review_level_check
        gate: level_route
    end note
    note left of scrutiny
        gate: has_commits
    end note
    note left of scrutiny
        gate: scrutiny_carried
    end note
    note left of scrutiny
        gate: scrutiny_decider
    end note
    note left of scrutiny
        gate: scrutiny_recorded
    end note
    note left of scrutiny
        gate: scrutiny_verdict
    end note
    note left of setup_free_form
        gate: baseline_exists
    end note
    note left of setup_free_form
        gate: on_feature_branch
    end note
    note left of setup_issue_backed
        gate: baseline_exists
    end note
    note left of setup_issue_backed
        gate: on_feature_branch
    end note
    note left of setup_plan_backed
        gate: baseline_exists
    end note
    note left of setup_plan_backed
        gate: on_feature_branch
    end note
    note left of staleness_check
        gate: staleness_fresh
    end note
    note left of verification
        gate: route_reason_given
    end note
    note left of verification
        gate: verification_route
    end note
    note left of verification
        gate: verification_verdict
    end note
    note left of verification_hosted
        gate: hosted_record_valid
    end note
    note left of verification_plan
        gate: verification_route_plan
    end note
    note left of waiting_record
        gate: question_recorded
    end note
```
