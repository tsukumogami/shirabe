# Successor brief: the plugin lane handover

This brief hands the plugin lane to the next coordinator.
It was written by hand when the outgoing session rotated.

## Holdings

- Worker alder holds Feature 3 on branch impl-feature-3.
- Worker birch holds Feature 4 on branch impl-feature-4.
- Worker cedar holds Feature 5 on branch impl-feature-5.
- Worker dogwood holds Feature 6 on branch impl-feature-6.
- Worker elm holds Feature 7 on branch impl-feature-7.
- Worker fir holds Feature 8 on branch impl-feature-8.
- Worker ginkgo holds Feature 9 on branch impl-feature-9.
- Worker hazel holds Feature 10 on branch impl-feature-10.
- Worker ivy holds Feature 11 on branch impl-feature-11.
- Worker juniper holds Feature 12 on branch impl-feature-12.
- Worker kauri holds Feature 13 on branch impl-feature-13.
- Worker larch holds Feature 14 on branch impl-feature-14.
- Worker maple holds Feature 15 on branch impl-feature-15.
- Worker nutmeg holds Feature 16 on branch impl-feature-16.
- Worker oak holds Feature 17 on branch impl-feature-17.
- Worker pine holds Feature 18 on branch impl-feature-18.
- Worker quince holds Feature 19 on branch impl-feature-19.
- Worker rowan holds Feature 20 on branch impl-feature-20.
- Worker spruce holds Feature 21 on branch impl-feature-21.
- Worker teak holds Feature 22 on branch impl-feature-22.
- Worker umbrella holds Feature 23 on branch impl-feature-23.
- Worker walnut holds Feature 24 on branch impl-feature-24.
- Worker willow holds Feature 25 on branch impl-feature-25.
- Worker yew holds Feature 26 on branch impl-feature-26.
- Worker zelkova holds Feature 27 on branch impl-feature-27.
- The review of Feature 2 is waiting on its second seat.
- The release candidate for Feature 1 is built and not yet tagged.
- The flaky lint job on the main branch was retried twice this morning.
- The pull request for Feature 3 carries one open review thread.

## Takeover steps

1. Read the record before any dispatch.
2. Confirm each worker named under Holdings still answers.
3. Tell every worker the new coordinator's address.
4. Re-run the reconcile pass once the workers answer.
5. Record the go-ahead for the carried state.
6. Check that the Feature 2 review has both seats assigned.
7. Ask the release owner whether Feature 1 may be tagged today.
8. Close the handover thread once the go-ahead is recorded.
9. Move the stale Feature 0 notes into the archive section.
10. Re-read the roadmap for any feature marked blocked overnight.
11. Note the time the takeover finished in the record.
12. Clear the old coordinator's keep-alive timer.
13. Restart the progress report at the usual hour.
14. Drop the duplicate dispatch for Feature 9 that the rotation left behind.
15. Rebase the Feature 6 branch once its base lands.
16. Re-request the reviewer for Feature 4 if nobody has looked by noon.
17. Confirm the lint retry policy with the outgoing session's notes.
18. Ping worker umbrella about its overdue status line.
19. File the rotation summary as the first entry of the new record.
20. Report the takeover as finished to the person who started the run.

## Where the work stands

- Features 1 and 2 are nearly done.
- Features 3 through 8 are in review or close to it.
- Features 9 through 20 are being built.
- Features 21 through 27 started this week.
- Nothing in the lane is blocked on another team today.
- The release train leaves on Thursday.
- The last progress report went out at nine.
- The rotation happened because the outgoing session hit its context limit.

## Standing rules

- Never merge a pull request whose checks are not green.
- Keep one worker per feature.
- Ask the owner before cutting a release.
- Hold every dispatch while a release is being tagged.
- Read a failing check's log before asking for a retry.
- Report progress every two hours while workers are active.
- Never reassign a held feature without telling its worker first.
- Treat a reviewer's changes-requested as blocking until it is resolved.

## Decisions already made

- The plugin lane ships features in roadmap order.
- Feature 27 waits for the release after next.

## Out of scope

- The website redesign belongs to another lane.
