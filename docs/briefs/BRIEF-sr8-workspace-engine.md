---
schema: brief/v1
status: Draft
problem: |
  A contributor to the tsukumogami workspace meets shirabe's doc checks only in
  CI. The README doesn't tell them to install the binary through tsuku, and no
  setup step puts the validation hook in their clones, so a malformed document
  surfaces after a push instead of at commit time.
outcome: |
  A contributor reads one install line, runs `niwa apply`, and finds shirabe's
  pre-commit hook in every product repository clone, with any hook of their own
  left alone. Without shirabe on PATH, setup says how to install it, and the
  next apply finishes the job.
motivating_context: |
  SR8 is the last step of moving the workspace onto the shirabe engine. CI
  workflows, the skills and tsuku's own recipe already use it; the contributor's
  machine is the one consumer the CLI contract names that still doesn't.
---

# BRIEF: sr8-workspace-engine

## Status

Draft

## Problem Statement

shirabe's CLI contract (`docs/guides/multi-consumer-cli-contract.md`) names
three consumers of `shirabe validate`: CI workflows, the skills, and a local
pre-commit hook. Across the workspace's product repositories the first two are
in place: the repositories call shirabe's reusable workflows, and the skills
read the `shirabe-validate/v1` report. The
third consumer exists as a command, `shirabe install-hooks`, but nothing puts
it in front of a contributor.

Two gaps keep it there. First, the README's install guidance points only at a
curl script, though tsuku can already install shirabe from shirabe's own recipe
with `tsuku install tsukumogami/shirabe`, the route every other workspace tool
takes. Second, a contributor who provisions a workspace instance with niwa gets
clones with no doc hook at all. To get one they'd have to know the command
exists and run it in each clone by hand, and almost nobody does.

The result is a slow loop. A document with a bad status line or a missing
section passes the commit, gets pushed, and fails in CI minutes later. The
check that would have caught it in a second is already written.

## User Outcome

A contributor setting up the workspace installs shirabe the same way they
install every other tool, from one line in shirabe's README. They create or
apply a niwa instance and start working. When they commit a document change in
any product repository, the hook validates the staged documents before the
commit lands, in the same terms CI would use.

Their own setup is respected. A pre-commit hook they already had stays in
place, and apply says so rather than replacing it. Re-running apply changes
nothing that is already right.

When shirabe isn't installed yet, setup doesn't fail silently or break the
apply. It names what is missing and the line that installs it, and the next
apply puts the hook in place.

## User Journeys

### A new contributor with tsuku

They follow the README, run
`tsuku install tsukumogami/shirabe`, then `niwa create` for the workspace. Every
product repository clone in the new instance has shirabe's pre-commit hook.
Their first commit touching a design doc runs `shirabe validate` on it.

### A contributor who hasn't installed shirabe

They run `niwa create` first.
Apply finishes, and for each product repository it prints a short notice that
shirabe isn't on PATH, with the install line. They install shirabe, run
`niwa apply` again, and the hooks appear.

### A contributor with a hook of their own

One clone already has a
pre-commit hook, say a formatter hook a repository offers as an opt-in. Apply
leaves that file as it is and reports that shirabe's hook wasn't installed
there. Nothing they set up is lost.

### A contributor working in worktrees

They open a worktree of a clone for a
side task and commit a doc change there. The commit runs the same validation as
in the clone, because the hook installed for the clone covers its worktrees,
and they never ran a setup step for the worktree.

## Scope Boundary

**In:**

- The README line that tells a contributor to install shirabe with
  `tsuku install tsukumogami/shirabe`, and the Requirements section pointing at
  it.
- Getting `shirabe install-hooks` run in each product repository clone (shirabe,
  tsuku, koto, niwa, and any repository the workspace's private overlay adds)
  during `niwa apply` and `niwa create`.
- What setup does when shirabe is absent, when a pre-commit hook already exists,
  on re-apply, and in worktrees.
- Showing the result with a real or isolated `niwa create` or `niwa apply` run.

**Out:**

- Changes to the hook's contents or to `shirabe install-hooks` itself. The hook
  already skips with a message when shirabe is missing at commit time.
- A niwa release. Nothing here may depend on a niwa binary that hasn't shipped.
- CI workflow changes in any repository.
- The mermaid diagram check and publishing a shirabe library crate.
- Chaining shirabe's hook with an existing hook. An existing hook is preserved
  and reported, not merged.

## Downstream Artifacts

None yet.

## References

- `docs/guides/multi-consumer-cli-contract.md`, the consumer table and
  "Installing the local hook".
- `README.md`, the "Requirements" and "Local install" sections.
