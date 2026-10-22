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
the run's own `ISSUE_REPO`, and no bare `Fixes #<N>`. A bare `#<N>` in this
pull request names this repository's issue `<N>`, which merging would close,
so the gate fails a body that carries one even beside the qualified
reference, and a qualified reference to any other repository doesn't count.

If `deferral_approval` approved a deferral, name the deferred criterion and the
recorded approval in Part 2.

### Verification deferred to hosted CI

A run started with `VERIFICATION=hosted-ci` passed through
`verification_deferred` instead of `verification`: the verification map never
ran on this host, and the reason it gave is in context as
`verification_deferral`. Record that in Part 2 with this section, the reason
copied verbatim:

```markdown
## Verification

Local verification did not run: it was deferred to hosted CI.
Reason: <the verification_deferral value>
Hosted CI is the build of record for this change.
```

`pr_creation`'s `verification_deferral_recorded` gate reads the body GitHub has
(`check-pr-output.sh --deferral-record`) and holds `pr_status: created` until it
finds all three: a line saying local verification did not run, the reason
verbatim, and a line saying hosted CI is the build of record. The wording is
matched without regard to case; the reason is matched exactly. A run that
didn't defer passes the gate without the section. On a deferred run, don't
re-run tests locally after merging main either: the push is what CI checks.

## CI Monitoring

If checks fail:
1. Review failure logs
2. Fix locally (test failure, lint, build, flaky test, environment)
3. Push the fix
4. Re-check

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
DIRTY, koto routes the run itself, a root to the cascade and a child to `done`
(the `is_root` gate). That includes a pull request GitHub reports MERGED whose
only non-green checks are cancelled runs of the repo's macOS floor workflows:
the gate passes it, and `ci_cancelled_after_merge.txt` in context names the
cancelled checks for the final report. A failed or pending check, and a cancel
on an open pull request, still fail it. While `ci_passing` fails:

- `ci_outcome: failing_fixed`
- `ci_outcome: failing_unresolvable` + `rationale`
