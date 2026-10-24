# Pull Request and CI

Create the PR and monitor CI until all checks pass.

## Pre-PR Verification

If the branch is behind main, merge the latest main into it (`git fetch origin`,
then `git merge --no-edit origin/main`, which takes the default message
rather than opening an editor). Never rebase: a merge keeps every reviewed commit
in the branch's history, so the commit `pre_pr.md` names stays an ancestor of
`HEAD`. Resolve conflicts and re-run tests on the merged tip.

Review the diff against the remote's default branch: `git diff
origin/main...HEAD` when it is `main` (`git symbolic-ref
refs/remotes/origin/HEAD` names it). That is what the PR will show, and it
needs no local `main`. Diffing from `impl_base` here would also show whatever
the merge pulled in. No unintended changes.

### Design Document Status

Don't update the design diagram here. When the issue body contains
`Design: \`<path>\``, finalization updated it and `pre_pr.md`'s
`design_diagram` line names its path. Confirm that path appears in
that diff. If it doesn't, the record and the diff disagree: go
back through `finalization` rather than updating the diagram at this point.

## Push Branch

```bash
git push -u origin <branch>
```

Push plainly, never with a force option. A merge from main only adds commits,
so a plain push is always enough.

## Create PR

Author the title and body to the **mechanical** rule in the conformance text
the `pr_creation` directive names, which `shirabe validate --pr-body`
enforces in CI. `pr_creation`'s `pr_body_conformant` gate runs the same check
on the pull request GitHub has before the run moves on, plus one CI doesn't
run: the banned words in `skills/writing-style/rules.yaml`, in the title and
both parts of the body (`pr-body/banned-word`, PB5). Write that prose to
`skills/writing-style`. A violation holds the state with a finding naming the
rule: fix it with `gh pr edit` and submit `pr_status: created` again. For the **subjective**
Part 2 section selection (which reviewer-context sections this change needs),
apply the reasoning framework from your project's PR creation skill. Include
`Fixes #<N>` in Part 2 — `pr_creation`'s `closing_keyword` gate reads the pull
request GitHub actually has and blocks the run when the body does not close the
issue, so this is an obligation the workflow enforces rather than a convention
it asks for. Free-form work has no issue to close and the gate passes without
consulting the body.

An issue in another repository (the run was initialized with `ISSUE_REPO`) is
closed only by its qualified reference: write `Fixes <owner/repo>#<N>`, with
the run's own `ISSUE_REPO`, and no other closing reference to `<N>`. A bare
`#<N>`, `GH-<N>`, this repository's `owner/repo#<N>` or its issue URL after a
closing keyword names this repository's issue `<N>`, which merging would
close, so the gate fails a body that carries one even beside the qualified
reference. So does the markdown link `[#<N>](<this repository's issue URL>)`,
and any of these under a name this repository had before a rename, which
GitHub still resolves. Those are the spellings measured to close; others
GitHub may read the same way (`owner#<N>`, an issue path without a host,
other links to the issue) aren't refused yet, but don't write them either.
A qualified reference to any other repository doesn't count, and
`[<owner/repo>#<N>](<its issue URL>)` passes like the plain reference. The
gate looks up each other repository the body closes `<N>` in, at most five
of them, to rule out an old name; more than five fails the gate. When a
lookup fails (a rate limit, the network) or runs out of time, the gate exits
3 and the state holds, so submit `pr_status: created` again once GitHub
answers. If the same repository keeps failing (a 403 from an organization's
SSO, say), the hold ends when the body stops closing `<N>` there: turn the
reference its message names into plain text, with `gh pr edit`, and submit
again. That issue then won't close on merge, so close it by hand if it
should. A colon
after the keyword (`Fixes: #<N>`) closes the issue too, and the gate reads
it that way.

### Workflow content: what the body leaves out

The title, the body and every commit message describe the change and how it was
verified, in terms a reader of this repository understands. By default they carry
none of the workflow's own records:

- no review panel table, and no seat, run or reviewed-head lists;
- no override notes and no verification-deferral notes;
- no session, state, gate or ledger names, and no run records;
- no `Plan:` or `Roadmap:` lines and no other pointers to PLAN or ROADMAP files,
  which are deleted when the work completes.

Those records already live in this run's session. A repository opts in to them
with `## PR Workflow Content: include` in its `CLAUDE.local.md` or `CLAUDE.md`.
Ask the one reader rather than reading the header yourself:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/pr-workflow-content.sh
```

It prints `include` or `omit` (the default). Under `omit`, `pr_body_conformant`
also holds on a `## Review panel` heading or table, a `Plan:` or `Roadmap:` line, or
an `Implements` line naming a PLAN or ROADMAP file, each a `pr-body/workflow-content`
finding; move the record out and submit again. Under `include` every section
below is written as it says, and nothing is refused for carrying a record.

A Verification section, when the change needs one, says what ran and what it
showed, in plain terms: "the coordinate script suites pass", "hosted CI built and
tested the change", never a state or gate name.

If `deferral_approval` approved a deferral, say in Part 2, in plain terms, which
acceptance criterion the change leaves undone and where it is tracked. Under
`include`, also name the recorded approval.

### Verification deferred to hosted CI

A run started with `VERIFICATION=hosted-ci` passed through
`verification_deferred` instead of `verification`: the verification map never
ran on this host, and the reason it gave is in context as
`verification_deferral`. Under `omit` that context key is the record: the body's
Verification section says hosted CI verified the change, the reason stays out,
and `verification_deferral_recorded` passes without reading the body. Under
`include`, record it in Part 2 with this section, the reason copied verbatim:

```markdown
## Verification

Local verification did not run: it was deferred to hosted CI.
Reason: <the verification_deferral value>
Hosted CI is the build of record for this change.
```

Under `include`, `pr_creation`'s `verification_deferral_recorded` gate reads the
body GitHub has (`check-pr-output.sh --deferral-record`) and holds `pr_status: created` until it
finds all three: a line saying local verification did not run, the line
`Reason: <reason>`, and a line saying hosted CI is the build of record. The
wording is matched without regard to case. The reason line is matched exactly
and whole: the reason showing up elsewhere in the body, inside the
build-of-record line or a longer reason's line, doesn't count, nor does a
`Reason:` line with a list marker, extra spaces or a trailing period. A run that
didn't defer passes the gate without the section. On a deferred run, don't
re-run tests locally after merging main either: the push is what CI checks.

### A repository with no hosted CI

A pull request with no checks never passes `ci_passing` on its own: zero checks
is pending, not green. A repository that genuinely has no hosted CI says so on
its default branch, in `.claude/shirabe-extensions/hosted-ci.json`:

```json
{"hosted_ci": "none", "reason": "<one line saying why nothing builds or tests here>"}
```

When the default branch carries that file, record the exception in Part 2, the
reason copied verbatim:

```markdown
## Hosted CI

This repository declares no hosted CI.
Reason: <the declaration's reason>
```

`ci_passing` passes a pull request with no checks only when the declaration is
on the default branch and the body has both: a line saying the repository
declares no hosted CI (matched without regard to case) and the line
`Reason: <reason>` with the reason exactly.
A repository without the file needs no section. The change that adds a
workflow to such a repository deletes the file too: a stale declaration would
let a pull request with no checks yet pass in the window just after a push.
Never add the file on the
branch you're working on to get past the gate: the gate reads the default
branch, so the declaration is a change someone reviews and merges first.

## CI Monitoring

If checks fail:
1. Review failure logs
2. Fix locally (test failure, lint, build, flaky test, environment)
3. Push the fix
4. Re-check

Fix a failing test by fixing the code it tests. A test edit holds the unit until
someone other than you accepts it: an edited test (a line removed or changed, the
file deleted or renamed with a change) is held at `ci_pass_counting` once CI
passes, and the run goes no further until an acceptance seat, or a person where
the repository requires one, accepts the edit. When the test itself is wrong,
edit it and record why with `test-change.sh note`, as
`phase-4-implementation.md` describes; never edit or skip a test only to turn a
check green.

A check you cannot fix, or one still red when `ci_monitor`'s retry cap is
spent, ends the run as `failing_unresolvable`; the state's directive carries
the cap. An unattended run never asks the user instead.

## Evidence (pr_creation)

- `pr_status: created` + `pr_url` — always send `pr_url`: it is the `pr` a
  caller's leg reads from this run's result
- `pr_status: shared` — set when running as a plan-backed child with `SHARED_BRANCH`
  set. No PR is created or monitored; the phase routes directly to done. Using
  `created` instead would enter `ci_monitor` and monitor the orchestrator's PR,
  not this child's work.
- `pr_status: creation_failed_retry` (the state's directive carries the cap)
- `pr_status: creation_failed_escalate`

## Evidence (ci_monitor)

None on the green path: once every check passes and the pull request is not
DIRTY, koto routes the run itself: `ci_pass_counting` counts the pass (a test
edited while fixing CI is held there until accepted, as at `pass_counting`),
then sends a root to the cascade and a child to `done` (the `is_root` gate).
That includes a pull request GitHub reports MERGED whose
only non-green checks are cancelled runs of the repo's macOS floor workflows:
the gate passes it, and `ci_cancelled_after_merge.txt` in context names the
cancelled checks for the final report. A failed or pending check, and a cancel
on an open pull request, still fail it.

A pull request with no checks at all fails it too. Just after a push, before
GitHub creates the check suites, `gh pr checks` answers `no checks reported`:
tick again, as for a running check. If no check has appeared 10 minutes after
the push, submit `ci_outcome: failing_unresolvable` saying no checks were
reported on the head. A repository that declares no hosted CI (see **A
repository with no hosted CI** above) passes instead, once the body records
it, and `ci_none_declared.txt` in context names it for the final report. A
DIRTY pull request ends at `done_blocked` whatever its CI reads.

The gate reads the checks through `scripts/pr-checks.sh`, and so do you: it
takes `gh pr checks`'s arguments and is `gh pr checks` wherever the token can
read checks. Where GitHub refuses the check read, it lists the Actions jobs
and the commit's statuses instead, and a required check neither answers comes
back `unreadable`: it may be a check run the token can't see, so it never
passes. With every other check green, submit `ci_outcome: failing_unresolvable`
naming it. Never strip or swap the token to read checks. While
`ci_passing` fails on a pull request that isn't DIRTY:

- `ci_outcome: failing_fixed`
- `ci_outcome: failing_unresolvable` + `rationale`
