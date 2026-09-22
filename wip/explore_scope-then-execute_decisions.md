# Exploration Decisions: scope-then-execute

Recorded in auto mode (background session; the author asked not to pause). Each
entry is a recommendation followed, with status noted.

## Round 1

- **Treat single-pr as the only mode one session can finish without merge
  rights** (confirmed): coordinated's merge-order loop blocks on predecessor
  merges and its coordination PR merges last, so it belongs with multi-pr for
  sessions that can't merge.
- **Redefine "done" for a no-merge-rights session as "PR ready, CI green, handed
  off for merge"** (assumed): no skill merges today and the draft/ready design
  gives merging to humans; an opt-in, permission-checked merge step stays an open
  question for the chain rather than something the exploration settles.
- **Resolve the launch-time uncertainty at `/scope`'s exit, not at launch**
  (confirmed): the mode is known once the PLAN is written, so the continuation
  branches on `execution_mode` there. Predicting the mode at launch is only a
  complement (a delivery-preference flag), not the mechanism.
- **Multi-pr fallback is a clean stop, not an in-session loop** (assumed): push
  the scoping docs PR, leave the PLAN Active with issues filed, report the
  unblocked issues. Fan-out through `niwa dispatch` is noted as a possible
  follow-on but kept out of scope until the `done_blocked` question is checked
  with a real run.
- **Leave where the continuation lives open** (confirmed): flag on `/scope`,
  thin driver skill, or goal recipe are all viable; that's the design question
  the chain should settle.
- **Keep the stale-doc fixes separate from the feature** (assumed): the Draft vs
  Active contradiction, the `/work-on` next-step advice, and the schema enum
  drift are independent corrections worth filing, though the chain may absorb
  them where they touch the same files.

## Round 1, author answers (interactive, after the author offered to take questions)

- **"Done" means merge when permitted** (confirmed by author): the continuing
  session gains an opt-in, permission-checked merge step; without merge rights
  it falls back to "ready, green, handed off". Supersedes the assumed
  "ready + handed off" entry above.
- **Coordinated vs multi-pr is a matter of caller intent** (recommended by the
  exploration, prompted by the author's hypothesis; author asked for a
  recommendation rather than a rubber stamp): the two modes differ in where the
  PLAN lives during execution (unmerged coordination PR vs Active on main) and
  whether a driver stays with the effort. Those are intent, not work shape; the
  multi-repo restriction on coordinated is incidental. Recommendation: the
  caller declares intent at `/scope` launch. Continue-into-execution resolves
  multi-PR splits to `coordinated`; stop-at-PLAN resolves them to `multi-pr`.
  `single-pr` stays preferred in both. Code still lands incrementally under
  coordinated, so Incremental Value splits keep their benefit.
- **Coordinated and multi-pr get different post-scope behavior** (confirmed by
  author): multi-pr is the only mode whose Active PLAN may merge to main, so a
  multi-pr run stops after scoping with the docs PR carrying the Active PLAN and
  hands off per-issue sessions. Coordinated continues in the same session as the
  driver, suspending on the coordination PR when it can't merge and resuming
  from it.
- **Consequence for the core question**: with intent declared up front, every
  mode a continuing run can land on is one that session can drive, so the
  launch-time uncertainty goes away rather than being predicted.

## After crystallize, author input

- **Continuation = thin driver skill + intent flag on `/scope`** (author): the
  driver calls `/scope` with the continue flag and then drives the PLAN; `/scope`
  stays directly callable with the flag or its default. Where the line between
  the flag's job and the driver's job falls is left to DESIGN.
