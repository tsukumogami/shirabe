> This is a **coordinator record** for ROADMAP-plugin-system.

Written: 2026-10-08T10:00:00Z

## Holdings

| Unit | Entry point | Mode | Phase | Dispatch status | Return path | Worker | Repo | Branch | Verified head | Dispatched | Pull request |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Feature 2 | /shirabe:deliver | --auto | executing | dispatched | message | plugin-registry | acme/widgets | feat/x | 0123456789abcdef0123456789abcdef01234567 | 2026-09-26 | [#12](https://github.com/acme/widgets/pull/12) |
| Feature 2 | /shirabe:deliver | --auto | scoping-ahead | dispatching | leg req-1:execute | sandbox | acme/widgets |  |  | 2026-09-26 |  |

## Deferrals

| Deferral | Reason | Raised | Disposition |
|---|---|---|---|
| flaky test | not now \| later | 2026-09-25T10:00Z |  |

## Side effects in flight

| Action | Target | Verified head | Attempted | How to confirm |
|---|---|---|---|---|
| merge | #12 | 0123456789abcdef0123456789abcdef01234567 | 2026-09-26T11:02Z | compare blobs on main |

## Reversals

| Date | Reversed | Now | Reason | From |
|---|---|---|---|---|
| 2026-09-26T09:15Z | merge on green | hold for release | release freeze | the human |

## Holds

| Hold | On | Until | Set by | Set | Lifted |
|---|---|---|---|---|---|
| go | acme/widgets#14 | lifted | the human | 2026-09-26T09:10Z |  |

## Run

| Key | Value | Set by | Set |
|---|---|---|---|
| coordinator | lane_owner | the human | 2026-10-08T10:00Z |
| store | github | the human | 2026-10-08T10:00Z |

## Standing

| Standing | Kind | On | Until | What | Owner | Relayed by | Set |
|---|---|---|---|---|---|---|---|
| s1 | pause | Feature 2 | lifted | wait for the review | the human |  | 2026-10-01T19:37Z |

## Work

| Item | Kind | Who | Next step | Wakes | Updated |
|---|---|---|---|---|---|
| Feature 2 | holding | plugin-registry | verify the pushed head | 0 | 2026-10-08T10:00Z |

## Decisions

Next decision: 6

Archived: 1-3 (settled; each kept verbatim in a decisions entry on this record)

| Decision | Round | Question | Options | State | Source | Verdict | Recommendation | Reason | Context | Problem | Grounds | Target | Owed | Asked | Evidence | Outcome | Decided by | Updated |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 4 | 0 | Ship with the mixed check result? | keep option d and ship<br>switch to option c | proposed | worker ci-pin [20260927T233505Z report 40.1] |  |  |  |  |  |  |  |  |  |  |  |  | 2026-09-27T23:40Z |
| 5 | 0 | Ship with the mixed check result? | keep option d and ship<br>switch to option c | coordinator-verdict | worker ci-pin [20260927T233505Z report 40.1] | hold |  | waiting on the cache benchmark |  |  |  |  |  |  |  |  |  | 2026-09-27T23:40Z |
