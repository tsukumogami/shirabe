```mermaid
stateDiagram-v2
    direction LR
    [*] --> start
    ask_up --> wait : asked: sent
    classify_report --> verify : classification: done, gates.report_pr.exit_code: 0
    classify_report --> wait : classification: done, gates.report_pr.exit_code: 1
    classify_report --> surface : classification: blocked
    classify_report --> rebrief : classification: needs_fix
    decision_answer --> decision_next : answered: recorded
    decision_answer --> decision_apply : answered: reversal
    decision_apply --> record : change: reversal
    decision_apply --> record : change: deferral
    decision_apply --> pick_facts : change: none
    decision_carry --> decision_next : carried: carried
    decision_evidence --> decision_next : recorded: recorded
    decision_next --> decision_carry : gates.decision_next_verdict.exit_code: 150
    decision_next --> decision_open : gates.decision_next_verdict.exit_code: 151
    decision_next --> decision_answer : gates.decision_next_verdict.exit_code: 152
    decision_next --> decision_evidence : gates.decision_next_verdict.exit_code: 153
    decision_next --> decision_raise : gates.decision_next_verdict.exit_code: 154
    decision_next --> decision_withdraw : gates.decision_next_verdict.exit_code: 155
    decision_next --> decision_reply : gates.decision_next_verdict.exit_code: 156
    decision_next --> decision_redirect : gates.decision_next_verdict.exit_code: 157
    decision_next --> escalate : gates.decision_next_verdict.exit_code: 158
    decision_next --> decision_take : gates.decision_next_verdict.exit_code: 159
    decision_next --> decision_verdict : gates.decision_input.exists: true, gates.decision_next_verdict.exit_code: 160
    decision_next --> pick_facts : gates.decision_next_verdict.exit_code: 161
    decision_next --> classify_report : gates.decision_next_verdict.exit_code: 162
    decision_next --> record_conflict : gates.decision_next_verdict.exit_code: 163
    decision_open --> decision_next : opened: opened
    decision_raise --> decision_next : raised: raised
    decision_redirect --> decision_redirect_send : gates.decision_redirect_verdict.exit_code: 180
    decision_redirect --> record_conflict : gates.decision_redirect_verdict.exit_code: 62
    decision_redirect_send --> decision_next : sent: sent
    decision_reply --> decision_reply_send : gates.decision_reply_verdict.exit_code: 180
    decision_reply --> record_conflict : gates.decision_reply_verdict.exit_code: 62
    decision_reply_send --> decision_next : sent: sent
    decision_take --> decision_next : taken: taken
    decision_verdict --> decision_next : verdict: settle
    decision_verdict --> decision_next : verdict: escalate
    decision_verdict --> decision_next : verdict: hold
    decision_withdraw --> decision_withdraw_send : gates.decision_withdraw_verdict.exit_code: 180
    decision_withdraw --> record_conflict : gates.decision_withdraw_verdict.exit_code: 62
    decision_withdraw_send --> decision_next : sent: sent
    deferral_dispose --> dispatch_check : rewritten: rewritten
    destroy --> record : destroyed: destroyed
    destroy --> record : destroyed: handed_over
    destroy --> surface : destroyed: refused
    dispatch --> record : dispatched: sent, gates.holding_recorded.exit_code: 0
    dispatch --> failure : dispatched: failed
    dispatch_check --> dispatch : gates.dispatch_check_verdict.exit_code: 40
    dispatch_check --> deferral_dispose : gates.dispatch_check_verdict.exit_code: 41
    dispatch_check --> record_find : gates.dispatch_check_verdict.exit_code: 42
    dispatch_check --> wait : gates.dispatch_check_verdict.exit_code: 43
    dispatch_check --> pick_facts : gates.dispatch_check_verdict.exit_code: 44
    dispatch_check --> decision_next : gates.dispatch_check_verdict.exit_code: 45
    dispatch_check --> pick_facts : gates.dispatch_check_verdict.exit_code: 46
    dispatch_check --> failure : gates.dispatch_check_verdict.exit_code: 47
    escalate --> escalate_send : gates.escalate_verdict.exit_code: 180
    escalate --> record_conflict : gates.escalate_verdict.exit_code: 62
    escalate_send --> decision_next : sent: sent
    escalate_send --> decision_answer : evidence.decision: present, evidence.round: present, sent: answered
    failure --> dispatch_check : move: redispatch
    failure --> decision_raise : move: escalate
    goal_fit --> land_merge : fit: fits, gates.goal_fit_land.exit_code: 80
    goal_fit --> surface : fit: fits, gates.goal_fit_land.exit_code: 81
    goal_fit --> surface : fit: fits, gates.goal_fit_land.exit_code: 82
    goal_fit --> land_merge : fit: fits_with_follow_ups, gates.goal_fit_land.exit_code: 80
    goal_fit --> surface : fit: fits_with_follow_ups, gates.goal_fit_land.exit_code: 81
    goal_fit --> surface : fit: fits_with_follow_ups, gates.goal_fit_land.exit_code: 82
    goal_fit --> rebrief : fit: gap
    land --> goal_fit : gates.land_verdict.exit_code: 80
    land --> goal_fit : gates.land_verdict.exit_code: 81
    land --> goal_fit : gates.land_verdict.exit_code: 82
    land --> rebrief : gates.land_verdict.exit_code: 83
    land --> verify : gates.land_verdict.exit_code: 53
    land --> failure : gates.land_verdict.exit_code: 84
    land_merge --> merge_confirm : merge: attempted
    land_merge --> failure : merge: failed
    land_merge --> surface : merge: held
    leg_pick --> wait_leg : gates.leg_target.matches: true
    leg_pick --> wait : gates.leg_target.matches: false
    leg_spent --> record : move: replaced
    leg_spent --> surface : move: surface
    merge_confirm --> record : gates.merge_confirm_verdict.exit_code: 90
    merge_confirm --> record : gates.merge_confirm_verdict.exit_code: 91
    merged_facts --> record : gates.merged_facts_verdict.exit_code: 90
    merged_facts --> record : gates.merged_facts_verdict.exit_code: 91
    merged_facts --> wait : gates.merged_facts_verdict.exit_code: 92
    merged_facts --> wait : gates.merged_facts_verdict.exit_code: 46
    pick --> dispatch_check : choice: dispatch
    pick --> dispatch_check : choice: scope_ahead
    pick --> dispatch_check : choice: send_execution
    pick --> ask_up : choice: ask_up
    pick --> wait : choice: hold
    pick_facts --> pick : gates.pick_facts_verdict.exit_code: 30, gates.pick_input.exists: true
    pick_facts --> roadmap_close : gates.pick_facts_verdict.exit_code: 31
    pick_facts --> rotation_close : gates.pick_facts_verdict.exit_code: 32
    pick_facts --> decision_next : gates.pick_facts_verdict.exit_code: 136
    posture_ask --> record : merge: permitted
    posture_ask --> record : merge: reserved
    predecessor_close --> predecessor_step : gates.predecessor_close_verdict.exit_code: 120
    predecessor_close --> predecessor_step : gates.predecessor_close_verdict.exit_code: 122
    predecessor_close --> predecessor_done : gates.predecessor_close_verdict.exit_code: 90
    predecessor_close --> record_conflict : gates.predecessor_close_verdict.exit_code: 125
    predecessor_done --> record_find : recheck: recheck
    predecessor_handed_over --> record_find : recheck: recheck
    predecessor_handoff --> predecessor_close : gates.predecessor_handoff_verdict.exit_code: 110
    predecessor_handoff --> record_conflict : gates.predecessor_handoff_verdict.exit_code: 111
    predecessor_step --> predecessor_close : step_result: done
    predecessor_step --> predecessor_handed_over : step_result: handed_over
    promote --> teardown_inventory : promoted: promoted
    promote --> surface : promoted: escalate
    quiet_check --> wait : gates.quiet_check_verdict.exit_code: 100
    quiet_check --> status_message : gates.quiet_check_verdict.exit_code: 101
    quiet_check --> failure : gates.quiet_check_verdict.exit_code: 102
    rebrief --> wait : sent: sent
    rebrief --> pick_facts : sent: worker_gone
    reconcile --> pick_facts : gates.reconcile_posture.exit_code: 25, gates.reconcile_report.exit_code: 0, reconciled: reported
    reconcile --> posture_ask : gates.reconcile_posture.exit_code: 26, gates.reconcile_report.exit_code: 0, reconciled: reported
    reconcile_pass --> reconcile : gates.reconcile_pass_verdict.exit_code: 140
    record --> pick_facts : gates.record_verdict.exit_code: 50
    record --> record_conflict : gates.record_verdict.exit_code: 52
    record --> record_conflict : gates.record_verdict.exit_code: 54
    record_conflict --> record_find : resolution: recheck
    record_conflict --> done_stopped : resolution: stop
    record_find --> reconcile_pass : gates.record_find_verdict.exit_code: 10
    record_find --> record_open : gates.record_find_verdict.exit_code: 11
    record_find --> record_open : gates.record_find_verdict.exit_code: 12
    record_find --> record_open : gates.record_find_verdict.exit_code: 13
    record_find --> record_conflict : gates.record_find_verdict.exit_code: 14
    record_find --> record_conflict : gates.record_find_verdict.exit_code: 15
    record_find --> record_conflict : gates.record_find_verdict.exit_code: 16
    record_find --> record_conflict : gates.record_find_verdict.exit_code: 17
    record_find --> predecessor_handoff : gates.record_find_verdict.exit_code: 18
    record_open --> record_find : opened: opened
    report_facts --> report_questions : gates.report_facts_verdict.exit_code: 60, gates.report_input.exists: true
    report_facts --> report_questions : gates.report_facts_verdict.exit_code: 61
    report_facts --> report_questions : gates.report_facts_verdict.exit_code: 62
    report_facts --> report_link : gates.report_facts_verdict.exit_code: 63
    report_facts --> report_questions : gates.report_facts_verdict.exit_code: 64
    report_link --> report_facts : linked: written
    report_link --> surface : linked: refused
    report_questions --> decision_open : gates.report_questions_verdict.exit_code: 170
    report_questions --> classify_report : gates.report_holding.exit_code: 60, gates.report_questions_verdict.exit_code: 11
    report_questions --> wait : gates.report_holding.exit_code: 61, gates.report_questions_verdict.exit_code: 11
    report_questions --> wait : gates.report_holding.exit_code: 62, gates.report_questions_verdict.exit_code: 11
    report_questions --> wait : gates.report_holding.exit_code: 64, gates.report_questions_verdict.exit_code: 11
    report_questions --> rebrief : gates.report_holding.exit_code: 60, gates.report_questions_verdict.exit_code: 171
    report_questions --> rebrief : gates.report_holding.exit_code: 61, gates.report_questions_verdict.exit_code: 171
    report_questions --> rebrief : gates.report_holding.exit_code: 62, gates.report_questions_verdict.exit_code: 171
    report_questions --> wait : gates.report_holding.exit_code: 64, gates.report_questions_verdict.exit_code: 171
    report_questions --> surface : gates.report_questions_verdict.exit_code: 172
    roadmap_blocked --> wait : noted: noted
    roadmap_close --> roadmap_close_step : gates.roadmap_close_verdict.exit_code: 130
    roadmap_close --> roadmap_blocked : gates.roadmap_close_verdict.exit_code: 131
    roadmap_close --> roadmap_blocked : gates.roadmap_close_verdict.exit_code: 132
    roadmap_close --> roadmap_blocked : gates.roadmap_close_verdict.exit_code: 133
    roadmap_close --> roadmap_blocked : gates.roadmap_close_verdict.exit_code: 134
    roadmap_close --> roadmap_blocked : gates.roadmap_close_verdict.exit_code: 136
    roadmap_close --> done : gates.roadmap_close_verdict.exit_code: 135
    roadmap_close_step --> roadmap_close : step: closed
    roadmap_close_step --> done_handed_over : step: handed_over
    rotation_close --> rotation_step : gates.rotation_close_verdict.exit_code: 120
    rotation_close --> rotation_step : gates.rotation_close_verdict.exit_code: 121
    rotation_close --> rotation_step : gates.rotation_close_verdict.exit_code: 122
    rotation_close --> rotation_done : gates.rotation_close_verdict.exit_code: 90
    rotation_close --> record_conflict : gates.rotation_close_verdict.exit_code: 125
    rotation_done --> done : deleted: deleted
    rotation_step --> rotation_close : step_result: done
    rotation_step --> done_handed_over : step_result: handed_over
    start --> start_posture : gates.start_verdict.exit_code: 20
    start --> start_posture : gates.start_verdict.exit_code: 21
    start --> done_not_active : gates.start_verdict.exit_code: 22
    start_posture --> record_find : gates.start_posture_verdict.exit_code: 25
    start_posture --> record_find : gates.start_posture_verdict.exit_code: 26
    status_message --> wait : sent: sent
    surface --> record : surfaced: merge_table
    surface --> surface_check : surfaced: blocker
    surface --> decision_raise : surfaced: decision
    surface_check --> wait : gates.need_verdict.exit_code: 190
    surface_check --> surface : gates.need_verdict.exit_code: 62
    take_report --> report_facts : gates.report_present.matches: true, gates.report_source_ok.exit_code: 0
    take_report --> wait : gates.report_source_ok.exit_code: 1
    take_report --> wait : gates.report_present.matches: false, gates.report_source_ok.exit_code: 0, withdrawn: withdrawn
    take_report --> surface : gates.report_source_ok.exit_code: 3
    take_report --> wait : gates.report_source_ok.exit_code: 2, withdrawn: withdrawn
    take_report --> surface : gates.report_source_ok.exit_code: 2, withdrawn: unreadable
    teardown --> teardown_inventory : teardown: stopped
    teardown --> record : teardown: kept
    teardown_inventory --> destroy : gates.inventory_durable.exit_code: 0
    teardown_inventory --> promote : gates.inventory_durable.exit_code: 1
    teardown_inventory --> surface : gates.inventory_durable.exit_code: 2
    teardown_inventory --> surface : gates.inventory_durable.exit_code: 3
    verified_confirm --> land : gates.verified_confirm_verdict.exit_code: 50
    verified_confirm --> record_conflict : gates.verified_confirm_verdict.exit_code: 52
    verified_confirm --> verify : gates.verified_confirm_verdict.exit_code: 53
    verified_confirm --> record_conflict : gates.verified_confirm_verdict.exit_code: 54
    verify --> verify_board : predicted: recorded
    verify_board --> verified_confirm : gates.verify_board_verdict.exit_code: 70
    verify_board --> failure : gates.verify_board_verdict.exit_code: 71
    verify_board --> wait : gates.verify_board_verdict.exit_code: 72
    verify_board --> wait : gates.verify_board_verdict.exit_code: 73
    verify_board --> wait : gates.verify_board_verdict.exit_code: 78
    verify_board --> rebrief : gates.verify_board_verdict.exit_code: 79
    verify_board --> surface : gates.verify_board_verdict.exit_code: 74
    verify_board --> surface : gates.verify_board_verdict.exit_code: 75
    verify_board --> surface : gates.verify_board_verdict.exit_code: 76
    verify_board --> wait : gates.verify_board_verdict.exit_code: 77
    wait --> take_report : event: report
    wait --> take_report : event: progress
    wait --> leg_pick : event: leg
    wait --> quiet_check : event: quiet
    wait --> decision_apply : event: decision
    wait --> decision_apply : event: deferral
    wait --> merged_facts : event: merged
    wait --> teardown : event: retire
    wait --> decision_answer : event: answer, evidence.decision: present, evidence.round: present
    wait --> decision_evidence : event: evidence, evidence.decision: present
    wait --> decision_raise : event: raise
    wait --> rotation_close : event: end, vars.DISCIPLINE: {"is_set":true}
    wait --> done_stopped : event: end, vars.DISCIPLINE: {"is_set":false}
    wait_leg --> take_report : gates.leg_result.disposition: resolved, gates.leg_result.source: promoted
    wait_leg --> leg_spent : gates.leg_result.disposition: resolved, gates.leg_result.source: explicit
    wait_leg --> leg_spent : gates.leg_result.disposition: resolved, gates.leg_result.source: refused
    wait_leg --> leg_spent : gates.leg_result.disposition: abandoned
    wait_leg --> leg_spent : gates.leg_result.disposition: missing
    wait_leg --> leg_pick : gates.leg_result.disposition: open, watch: rescan
    wait_leg --> wait : gates.leg_result.disposition: open, watch: back
    done --> [*]
    done_handed_over --> [*]
    done_not_active --> [*]
    done_stopped --> [*]
    note left of classify_report
        gate: report_pr
    end note
    note left of decision_next
        gate: decision_input
    end note
    note left of decision_next
        gate: decision_next_verdict
    end note
    note left of decision_redirect
        gate: decision_redirect_verdict
    end note
    note left of decision_reply
        gate: decision_reply_verdict
    end note
    note left of decision_withdraw
        gate: decision_withdraw_verdict
    end note
    note left of dispatch
        gate: holding_recorded
    end note
    note left of dispatch_check
        gate: dispatch_check_verdict
    end note
    note left of escalate
        gate: escalate_verdict
    end note
    note left of goal_fit
        gate: goal_fit_land
    end note
    note left of land
        gate: land_verdict
    end note
    note left of leg_pick
        gate: leg_target
    end note
    note left of merge_confirm
        gate: merge_confirm_verdict
    end note
    note left of merged_facts
        gate: merged_facts_verdict
    end note
    note left of pick_facts
        gate: pick_facts_verdict
    end note
    note left of pick_facts
        gate: pick_input
    end note
    note left of predecessor_close
        gate: predecessor_close_verdict
    end note
    note left of predecessor_handoff
        gate: predecessor_handoff_verdict
    end note
    note left of quiet_check
        gate: quiet_check_verdict
    end note
    note left of reconcile
        gate: reconcile_posture
    end note
    note left of reconcile
        gate: reconcile_report
    end note
    note left of reconcile_pass
        gate: reconcile_pass_verdict
    end note
    note left of record
        gate: record_verdict
    end note
    note left of record_find
        gate: record_find_verdict
    end note
    note left of report_facts
        gate: report_facts_verdict
    end note
    note left of report_facts
        gate: report_input
    end note
    note left of report_questions
        gate: report_holding
    end note
    note left of report_questions
        gate: report_questions_verdict
    end note
    note left of roadmap_close
        gate: roadmap_close_verdict
    end note
    note left of rotation_close
        gate: rotation_close_verdict
    end note
    note left of start
        gate: start_verdict
    end note
    note left of start_posture
        gate: start_posture_verdict
    end note
    note left of surface_check
        gate: need_verdict
    end note
    note left of take_report
        gate: report_present
    end note
    note left of take_report
        gate: report_source_ok
    end note
    note left of teardown_inventory
        gate: inventory_durable
    end note
    note left of verified_confirm
        gate: verified_confirm_verdict
    end note
    note left of verify_board
        gate: verify_board_verdict
    end note
    note left of wait_leg
        gate: leg_result
    end note
```
