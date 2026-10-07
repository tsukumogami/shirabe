# performance handoff, 2026-10-07

Rotation from 2026-10-06 to 2026-10-07. Host repository: tsukumogami/shirabe. Record: https://github.com/tsukumogami/shirabe/pull/608, kept on coordinate/discipline-performance.

## Holdings

None.

## Deferrals

None.

## Side effects in flight

None.

## Reversals

| Date | Reversed | Now | Reason | From |
|---|---|---|---|---|
| 2026-10-06T21:31Z | The run opened with the decisions text saying #593 and #602 are not dispatched this rotation without the human's say, and the coordinator held the free slot after #591 landed | Pick keeps the cap full in issue-number order, unblocked first: #592 stays held on the human's decider-trust ruling, #593 is blocked by the eval harness defect (shirabe#612), #602 is dispatched | The human ruled on 2026-10-06 that the coordinator fills every slot without asking; the hold was the coordinator's own wording, not a human decision | the human, 2026-10-06 |

## Decisions

Next decision: 9

None.

## Reasoning for the next rotation

This rotation ran from the afternoon of 2026-10-06 to the morning of 2026-10-07 at a cap of one and landed every performance-labelled issue that was dispatchable: shirabe#591 with #521 (#609), #602 (#619), #592's shadow half (#622), and #593 (#624, #625), plus the prerequisites and config changes they forced (#611, dot-niwa-overlay#12, dot-niwa#25) and the first release under the new gate, v0.24.0. The one issue left, #629, is the per-site flip from shadow to trust; it can't be worked until the overlay binds a decider key (dot-niwa-overlay#13) and the shadow ledger holds about fifteen out-of-sample pull requests per site, so the next rotation's first read is that ledger, not the issue list.

What the tables can't say. The cost of a unit here is wall-clock in the worker's test suites, not in the panels: scrutiny, review and QA together were about a sixth of each work-on child, and they passed first time. Where the panels cost is tokens, and the three changes that landed (declared seat packets and a light level, recheck packets of findings plus fix diff, decider shadow for closed criteria) attack exactly that; none of it reaches a dispatched worker until the plugin pin actually applies (dot-niwa#26), which it didn't once during this rotation. The coordinator's own waste was idle wakes: timer watches that expired with no event, re-armed by habit; worker messages are the only wake that pays, and the single silent wait is the fallback (vision#668 records the counts). Teardown is the coordinator session's job through a persistent local agent, one named target per pass, and it worked while the loop itself was blocked (vision Feature 10); the loop's own inventory and reconcile reads can't finish an eleven-clone instance inside their budgets (shirabe#618), so a restart with a live worker stalls until that's fixed. Two more skill gaps shaped the run: an issue assigned outside the roadmap can't be dispatched at roadmap scope (#607), and a leg-bound worker's checkpoint messages, with their questions, are refused at the report gate (#610), so questions were answered by message and recorded as decision entries by hand. The merge gate's exemption names one instance; a new coordinator instance needs the overlay value changed before its first merge.
