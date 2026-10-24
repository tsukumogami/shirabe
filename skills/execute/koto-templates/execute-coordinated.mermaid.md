```mermaid
stateDiagram-v2
    direction LR
    [*] --> coord_setup
    coord_loop --> coord_verdict : loop_exit: done
    coord_loop --> coord_verdict : loop_exit: pause
    coord_loop --> coord_verdict : loop_exit: error
    coord_merge_confirm --> record_keep : gates.confirmed_merged.matches: true
    coord_merge_confirm --> record_keep : gates.confirmed_merged.matches: false
    coord_setup --> coord_loop : gates.coord_branch_recorded.matches: true, gates.home_repo_recorded.matches: true, gates.repos_recorded.matches: true
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: blocked
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: store-mismatch
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: coordination-pr-missing
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: coordination-pr-ambiguous
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: coordination-pr-mismatch
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: coordination-pr-closed
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: session-absent
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: recovery-unproven
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: recovery-plan-gone
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: coordination-index-missing
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: coordination-body-full
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: adopt-run-refused
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: follow-up-node
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: follow-up-repo
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: follow-up-base
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: follow-up-author
    coord_setup --> done_error : gates.repos_recorded.matches: false, setup_status: follow-up-closed
    coord_verdict --> coord_merge_confirm : gates.verdict_dirty.matches: false, gates.verdict_error.matches: false, gates.verdict_merged.matches: true, gates.verdict_paused.matches: false, gates.verdict_ready.matches: false
    coord_verdict --> record_keep : gates.verdict_dirty.matches: false, gates.verdict_error.matches: false, gates.verdict_merged.matches: false, gates.verdict_paused.matches: false, gates.verdict_ready.matches: true
    coord_verdict --> paused_awaiting_merges : gates.verdict_dirty.matches: false, gates.verdict_error.matches: false, gates.verdict_merged.matches: false, gates.verdict_paused.matches: true, gates.verdict_ready.matches: false
    coord_verdict --> done_blocked : gates.verdict_dirty.matches: true, gates.verdict_error.matches: false, gates.verdict_merged.matches: false, gates.verdict_paused.matches: false, gates.verdict_ready.matches: false
    coord_verdict --> done_blocked : gates.verdict_dirty.matches: false, gates.verdict_error.matches: true, gates.verdict_merged.matches: false, gates.verdict_paused.matches: false, gates.verdict_ready.matches: false
    coord_verdict --> done_blocked : gates.verdict_dirty.matches: false, gates.verdict_error.matches: false, gates.verdict_merged.matches: false, gates.verdict_paused.matches: false, gates.verdict_ready.matches: false
    record_keep --> merged : gates.confirmed_merged.matches: true
    record_keep --> ready_awaiting_merge : gates.confirmed_merged.matches: false
    done_blocked --> [*]
    done_error --> [*]
    merged --> [*]
    paused_awaiting_merges --> [*]
    ready_awaiting_merge --> [*]
    note left of coord_merge_confirm
        gate: confirmed_merged
    end note
    note left of coord_setup
        gate: coord_branch_recorded
    end note
    note left of coord_setup
        gate: home_repo_recorded
    end note
    note left of coord_setup
        gate: repos_recorded
    end note
    note left of coord_verdict
        gate: verdict_dirty
    end note
    note left of coord_verdict
        gate: verdict_error
    end note
    note left of coord_verdict
        gate: verdict_merged
    end note
    note left of coord_verdict
        gate: verdict_paused
    end note
    note left of coord_verdict
        gate: verdict_ready
    end note
    note left of record_keep
        gate: confirmed_merged
    end note
```
