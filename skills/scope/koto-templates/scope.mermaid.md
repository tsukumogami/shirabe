```mermaid
stateDiagram-v2
    direction LR
    [*] --> intake
    bail --> exit_abandonment : bail_ack: force_materialize, gates.child_intermediate_present.exit_code: 0
    bail --> exit_abandonment : bail_ack: force_materialize, gates.child_intermediate_present.exit_code: 1
    bail --> exit_abandonment : bail_ack: force_materialize, gates.child_intermediate_present.exit_code: 2
    bail --> done_cancelled : bail_ack: cancel
    branch_check --> resume_route : gates.on_named_non_default_branch.exit_code: 0
    branch_check --> resume_route : branch_status: override, gates.on_named_non_default_branch.exit_code: 1
    branch_check --> bail : branch_status: blocked, gates.on_named_non_default_branch.exit_code: 1
    chain_proposal --> hop_brief : author_decision: proceed
    chain_proposal --> discovery : author_decision: adjust
    chain_proposal --> bail : author_decision: bail
    cleanup_abandonment --> done_abandonment : cleanup_result: done, gates.exit_recorded.matches: true
    cleanup_abandonment --> done_error : cleanup_result: done, gates.exit_recorded.matches: false
    cleanup_full_run --> done_full_run : cleanup_result: done, gates.exit_recorded.matches: true, gates.mode_multi.matches: true
    cleanup_full_run --> done_full_run : cleanup_result: done, gates.exit_recorded.matches: true, gates.mode_multi.matches: false
    cleanup_full_run --> done_error : cleanup_result: done, gates.exit_recorded.matches: false
    cleanup_re_evaluation --> done_re_evaluation : cleanup_result: done, gates.exit_recorded.matches: true
    cleanup_re_evaluation --> done_error : cleanup_result: done, gates.exit_recorded.matches: false
    discovery --> chain_proposal : discovery_result: proposed
    discovery --> bail : discovery_result: blocked
    executed_report --> done_executed : gates.executed_live.matches: true, gates.executed_one.matches: true
    executed_report --> done_error : gates.executed_live.matches: false, gates.executed_one.matches: true
    executed_report --> done_error : gates.executed_one.matches: false
    exit_abandonment --> publish_abandonment : gates.forced_artifact_present.exit_code: 0, gates.intent_declared.exit_code: 0, retry_or_cancel: retry
    exit_abandonment --> cleanup_abandonment : gates.forced_artifact_present.exit_code: 0, gates.intent_declared.exit_code: 1, retry_or_cancel: retry
    exit_abandonment --> exit_abandonment : gates.forced_artifact_present.exit_code: 1, retry_or_cancel: retry
    exit_abandonment --> done_cancelled : retry_or_cancel: cancel
    exit_full_run --> publish_full_run : evidence.exit_artifacts: present, gates.chain_complete.exit_code: 0, gates.intent_declared.exit_code: 0
    exit_full_run --> cleanup_full_run : evidence.exit_artifacts: present, gates.chain_complete.exit_code: 0, gates.intent_declared.exit_code: 1
    exit_full_run --> full_run_blocked : evidence.exit_artifacts: present, gates.chain_complete.exit_code: 1
    exit_full_run --> full_run_blocked : evidence.exit_artifacts: present, gates.chain_complete.exit_code: 2
    exit_re_evaluation --> publish_re_evaluation : gates.decision_record_present.exit_code: 0, gates.intent_declared.exit_code: 0, retry_or_abandon: retry
    exit_re_evaluation --> cleanup_re_evaluation : gates.decision_record_present.exit_code: 0, gates.intent_declared.exit_code: 1, retry_or_abandon: retry
    exit_re_evaluation --> exit_re_evaluation : gates.decision_record_present.exit_code: 1, retry_or_abandon: retry
    exit_re_evaluation --> exit_abandonment : retry_or_abandon: abandon
    finalize --> exit_full_run : exit: full-run
    finalize --> exit_re_evaluation : exit: re-evaluation
    finalize --> exit_abandonment : exit: abandonment-forced
    fold --> finalize : gates.plan_present.exit_code: 0, verdict: keep
    fold --> finalize : gates.plan_present.exit_code: 0, verdict: absorb
    fold --> hop_plan : gates.design_present.exit_code: 0, gates.plan_present.exit_code: 1, verdict: keep
    fold --> hop_plan : gates.design_present.exit_code: 0, gates.plan_present.exit_code: 1, verdict: absorb
    fold --> hop_design : gates.design_present.exit_code: 1, gates.plan_present.exit_code: 1, verdict: keep
    fold --> hop_design : gates.design_present.exit_code: 1, gates.plan_present.exit_code: 1, verdict: absorb
    fold --> hop_design : gates.design_present.exit_code: 2, gates.plan_present.exit_code: 1, verdict: keep
    fold --> hop_design : gates.design_present.exit_code: 2, gates.plan_present.exit_code: 1, verdict: absorb
    fold --> hop_plan : gates.design_present.exit_code: 0, gates.plan_present.exit_code: 2, verdict: keep
    fold --> hop_plan : gates.design_present.exit_code: 0, gates.plan_present.exit_code: 2, verdict: absorb
    fold --> hop_design : gates.design_present.exit_code: 1, gates.plan_present.exit_code: 2, verdict: keep
    fold --> hop_design : gates.design_present.exit_code: 1, gates.plan_present.exit_code: 2, verdict: absorb
    fold --> hop_design : gates.design_present.exit_code: 2, gates.plan_present.exit_code: 2, verdict: keep
    fold --> hop_design : gates.design_present.exit_code: 2, gates.plan_present.exit_code: 2, verdict: absorb
    full_run_blocked --> publish_full_run : gates.chain_complete.exit_code: 0, gates.intent_declared.exit_code: 0, next_move: recheck
    full_run_blocked --> cleanup_full_run : gates.chain_complete.exit_code: 0, gates.intent_declared.exit_code: 1, next_move: recheck
    full_run_blocked --> full_run_blocked : gates.chain_complete.exit_code: 1, next_move: recheck
    full_run_blocked --> full_run_blocked : gates.chain_complete.exit_code: 2, next_move: recheck
    full_run_blocked --> exit_abandonment : next_move: abandon
    hop_brief --> hop_prd : gates.brief_complete.exit_code: 0, outcome: landed
    hop_brief --> hop_prd : outcome: skipped
    hop_brief --> bail : outcome: bail
    hop_design --> fold : gates.design_complete.exit_code: 0, outcome: landed
    hop_design --> hop_plan : outcome: skipped
    hop_design --> exit_re_evaluation : outcome: rejected
    hop_design --> bail : outcome: bail
    hop_plan --> fold : gates.plan_complete.exit_code: 0, gates.plan_mode_consistent.exit_code: 0, outcome: landed
    hop_plan --> bail : gates.plan_complete.exit_code: 0, gates.plan_mode_consistent.exit_code: 1, outcome: landed
    hop_plan --> finalize : outcome: skipped
    hop_plan --> bail : outcome: bail
    hop_prd --> fold : gates.prd_complete.exit_code: 0, outcome: landed
    hop_prd --> hop_design : outcome: skipped
    hop_prd --> exit_re_evaluation : outcome: rejected
    hop_prd --> bail : outcome: bail
    hop_select --> hop_brief : gates.sel_brief.matches: true
    hop_select --> hop_prd : gates.sel_brief.matches: false, gates.sel_prd.matches: true
    hop_select --> hop_design : gates.sel_brief.matches: false, gates.sel_design.matches: true, gates.sel_prd.matches: false
    hop_select --> hop_plan : gates.sel_brief.matches: false, gates.sel_design.matches: false, gates.sel_plan.matches: true, gates.sel_prd.matches: false
    hop_select --> hop_brief : gates.first_open.exit_code: 11, gates.sel_brief.matches: false, gates.sel_design.matches: false, gates.sel_plan.matches: false, gates.sel_prd.matches: false
    hop_select --> hop_prd : gates.first_open.exit_code: 12, gates.sel_brief.matches: false, gates.sel_design.matches: false, gates.sel_plan.matches: false, gates.sel_prd.matches: false
    hop_select --> hop_design : gates.first_open.exit_code: 13, gates.sel_brief.matches: false, gates.sel_design.matches: false, gates.sel_plan.matches: false, gates.sel_prd.matches: false
    hop_select --> hop_plan : gates.first_open.exit_code: 14, gates.sel_brief.matches: false, gates.sel_design.matches: false, gates.sel_plan.matches: false, gates.sel_prd.matches: false
    hop_select --> finalize : gates.first_open.exit_code: 0, gates.sel_brief.matches: false, gates.sel_design.matches: false, gates.sel_plan.matches: false, gates.sel_prd.matches: false
    intake --> branch_check : gates.intake_ok.matches: true
    intake --> done_refused : gates.intake_ok.matches: false, gates.intake_refused.matches: true
    intake --> done_error : gates.intake_ok.matches: false, gates.intake_refused.matches: false
    publish_abandonment --> cleanup_abandonment : gates.published.exit_code: 0, publish_result: attempted
    publish_abandonment --> done_error : gates.publish_push.matches: true, gates.published.exit_code: 1, publish_result: attempted
    publish_abandonment --> done_error : gates.publish_push.matches: false, gates.published.exit_code: 1, publish_result: attempted
    publish_abandonment --> done_error : gates.publish_push.matches: true, gates.published.exit_code: 2, publish_result: attempted
    publish_abandonment --> done_error : gates.publish_push.matches: false, gates.published.exit_code: 2, publish_result: attempted
    publish_full_run --> cleanup_full_run : gates.published.exit_code: 0, publish_result: attempted
    publish_full_run --> done_error : gates.publish_push.matches: true, gates.published.exit_code: 1, publish_result: attempted
    publish_full_run --> done_error : gates.publish_push.matches: false, gates.published.exit_code: 1, publish_result: attempted
    publish_full_run --> done_error : gates.publish_push.matches: true, gates.published.exit_code: 2, publish_result: attempted
    publish_full_run --> done_error : gates.publish_push.matches: false, gates.published.exit_code: 2, publish_result: attempted
    publish_re_evaluation --> cleanup_re_evaluation : gates.published.exit_code: 0, publish_result: attempted
    publish_re_evaluation --> done_error : gates.publish_push.matches: true, gates.published.exit_code: 1, publish_result: attempted
    publish_re_evaluation --> done_error : gates.publish_push.matches: false, gates.published.exit_code: 1, publish_result: attempted
    publish_re_evaluation --> done_error : gates.publish_push.matches: true, gates.published.exit_code: 2, publish_result: attempted
    publish_re_evaluation --> done_error : gates.publish_push.matches: false, gates.published.exit_code: 2, publish_result: attempted
    republish --> republish_record : gates.published.exit_code: 0, publish_result: attempted
    republish --> done_error : gates.publish_push.matches: true, gates.published.exit_code: 1, publish_result: attempted
    republish --> done_error : gates.publish_push.matches: false, gates.published.exit_code: 1, publish_result: attempted
    republish --> done_error : gates.publish_push.matches: true, gates.published.exit_code: 2, publish_result: attempted
    republish --> done_error : gates.publish_push.matches: false, gates.published.exit_code: 2, publish_result: attempted
    republish_record --> done_republished : gates.exit_recorded.matches: true, gates.mode_multi.matches: true
    republish_record --> done_republished : gates.exit_recorded.matches: true, gates.mode_multi.matches: false
    republish_record --> done_error : gates.exit_recorded.matches: false
    resume_boundary --> exit_re_evaluation : boundary_choice: re_evaluate
    resume_boundary --> setup : boundary_choice: revise
    resume_boundary --> done_cancelled : boundary_choice: bail
    resume_draft --> setup : draft_choice: continue
    resume_draft --> setup : draft_choice: discard
    resume_draft --> done_cancelled : draft_choice: bail
    resume_exit_set --> finalize : exit_set_choice: revise
    resume_exit_set --> setup : exit_set_choice: start_fresh
    resume_exit_set --> done_cancelled : exit_set_choice: bail
    resume_malformed --> setup : malformed_choice: discard
    resume_malformed --> done_cancelled : malformed_choice: stop
    resume_route --> setup : gates.ladder.exit_code: 10
    resume_route --> setup : gates.ladder.exit_code: 11
    resume_route --> setup : gates.ladder.exit_code: 12
    resume_route --> setup : gates.ladder.exit_code: 49
    resume_route --> discovery : gates.ladder.exit_code: 20
    resume_route --> hop_select : gates.ladder.exit_code: 21
    resume_route --> finalize : gates.ladder.exit_code: 22
    resume_route --> resume_stale : gates.ladder.exit_code: 24
    resume_route --> resume_malformed : gates.ladder.exit_code: 25
    resume_route --> resume_exit_set : gates.ladder.exit_code: 26
    resume_route --> publish_full_run : gates.ladder.exit_code: 27
    resume_route --> publish_re_evaluation : gates.ladder.exit_code: 28
    resume_route --> publish_abandonment : gates.ladder.exit_code: 29
    resume_route --> republish : gates.ladder.exit_code: 40
    resume_route --> done_refused : gates.ladder.exit_code: 41
    resume_route --> done_refused : gates.ladder.exit_code: 42
    resume_route --> resume_draft : gates.ladder.exit_code: 43
    resume_route --> executed_report : gates.ladder.exit_code: 44
    resume_route --> resume_boundary : gates.ladder.exit_code: 45
    resume_route --> resume_draft : gates.ladder.exit_code: 46
    resume_route --> resume_boundary : gates.ladder.exit_code: 47
    resume_route --> resume_draft : gates.ladder.exit_code: 48
    resume_route --> resume_draft : gates.ladder.exit_code: 50
    resume_route --> setup : gates.ladder.exit_code: 60
    resume_route --> setup : gates.ladder.exit_code: 61
    resume_route --> setup : gates.ladder.exit_code: 62
    resume_route --> setup : gates.ladder.exit_code: 63
    resume_route --> done_error : gates.ladder.exit_code: 2
    resume_stale --> discovery : gates.pointer.exit_code: 20, stale_choice: resume
    resume_stale --> hop_select : gates.pointer.exit_code: 21, stale_choice: resume
    resume_stale --> finalize : gates.pointer.exit_code: 22, stale_choice: resume
    resume_stale --> exit_abandonment : stale_choice: force_materialize
    resume_stale --> setup : stale_choice: discard
    setup --> hop_select : gates.resume_hop_set.matches: true, setup_result: ready
    setup --> discovery : gates.resume_hop_set.matches: false, setup_result: ready
    setup --> bail : setup_result: blocked
    done_abandonment --> [*]
    done_cancelled --> [*]
    done_error --> [*]
    done_executed --> [*]
    done_full_run --> [*]
    done_re_evaluation --> [*]
    done_refused --> [*]
    done_republished --> [*]
    note left of bail
        gate: child_intermediate_present
    end note
    note left of branch_check
        gate: on_named_non_default_branch
    end note
    note left of cleanup_abandonment
        gate: exit_recorded
    end note
    note left of cleanup_full_run
        gate: exit_recorded
    end note
    note left of cleanup_full_run
        gate: mode_multi
    end note
    note left of cleanup_re_evaluation
        gate: exit_recorded
    end note
    note left of executed_report
        gate: executed_live
    end note
    note left of executed_report
        gate: executed_one
    end note
    note left of exit_abandonment
        gate: forced_artifact_present
    end note
    note left of exit_abandonment
        gate: intent_declared
    end note
    note left of exit_full_run
        gate: chain_complete
    end note
    note left of exit_full_run
        gate: intent_declared
    end note
    note left of exit_re_evaluation
        gate: decision_record_present
    end note
    note left of exit_re_evaluation
        gate: intent_declared
    end note
    note left of fold
        gate: design_present
    end note
    note left of fold
        gate: plan_present
    end note
    note left of full_run_blocked
        gate: chain_complete
    end note
    note left of full_run_blocked
        gate: intent_declared
    end note
    note left of hop_brief
        gate: brief_complete
    end note
    note left of hop_design
        gate: design_complete
    end note
    note left of hop_plan
        gate: plan_complete
    end note
    note left of hop_plan
        gate: plan_mode_consistent
    end note
    note left of hop_prd
        gate: prd_complete
    end note
    note left of hop_select
        gate: first_open
    end note
    note left of hop_select
        gate: sel_brief
    end note
    note left of hop_select
        gate: sel_design
    end note
    note left of hop_select
        gate: sel_plan
    end note
    note left of hop_select
        gate: sel_prd
    end note
    note left of intake
        gate: intake_ok
    end note
    note left of intake
        gate: intake_refused
    end note
    note left of publish_abandonment
        gate: publish_push
    end note
    note left of publish_abandonment
        gate: published
    end note
    note left of publish_full_run
        gate: publish_push
    end note
    note left of publish_full_run
        gate: published
    end note
    note left of publish_re_evaluation
        gate: publish_push
    end note
    note left of publish_re_evaluation
        gate: published
    end note
    note left of republish
        gate: publish_push
    end note
    note left of republish
        gate: published
    end note
    note left of republish_record
        gate: exit_recorded
    end note
    note left of republish_record
        gate: mode_multi
    end note
    note left of resume_route
        gate: ladder
    end note
    note left of resume_stale
        gate: pointer
    end note
    note left of setup
        gate: resume_hop_set
    end note
```
