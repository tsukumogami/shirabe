---
schema: brief/v1
status: Draft
problem: |
  shirabe's rules that guard an irreversible action are checked after the
  action: a koto gate reads the pull request GitHub already has, CI reads
  the pushed commits. The one deny that stops an agent beforehand reaches
  only hosts a workspace manager wired it into, and it speaks in its own
  words rather than the rule's.
outcome: |
  Anyone who installs the shirabe plugin has an agent stopped before it
  opens a non-conforming pull request or pushes a commit that breaks a
  guarded rule, told which rule and where its full text is, so it fixes
  and retries in the same turn. Nothing it doesn't guard is ever stopped.
motivating_context: |
  shirabe wants to stop preloading every rule into an agent's context and
  deliver a rule at the moment it applies instead. For a rule whose harm
  can't be undone, that is safe only when something still blocks the
  action itself, before it happens. This feature builds that block; it
  withholds no rule.
---

## Status

Draft

## Problem Statement

shirabe states a set of rules whose breach can't be taken back once it
happens. A pull request opened with a malformed body is public the
moment `gh pr create` returns. A commit carrying an AI-attribution
trailer is in the remote's history the moment `git push` returns. The
rule registry (`references/rule-registry.json`) marks each such rule
with what it guards: `pr-create`, `push`, `merge`.

Almost all of those rules are checked after the action they guard. The
/work-on PR-body gate reads the pull request that GitHub already has;
the commit checks run at finalization, after the branch has usually
been pushed; CI runs on what was pushed. Those checks are real, and
they stop a bad change from merging, but by the time they speak the
irreversible part has already happened.

There is one exception. `shirabe pr-body-hook` is a Claude Code
PreToolUse adapter that denies a `gh pr create` or `gh pr edit` whose
title or body breaks the PR-body rules, before the command runs. It
works, and three things limit it:

1. **A plugin user can't rely on it.** It runs only where something
   outside the plugin wires it into the host's settings, which today is
   niwa, the workspace manager. A user who installs the shirabe plugin
   on its own gets the rules in prose and no deny at all.
2. **It speaks in its own words.** Its deny reason lists the
   validator's findings, phrased by the validator. It doesn't carry the
   rule's registered summary or say where the rule's full text is, so
   an agent that is told no isn't told the rule, and a reader of the
   event can't join it to the registry.
3. **A check that can't run lets the action through.** When it can't decide (an unreadable `--body-file`,
   a command it can't tokenize, a missing binary) it allows, on the
   grounds that CI is the backstop. That was the right trade for a hook
   whose only job was early feedback. It is the wrong one for a hook
   meant to be the thing that still blocks the action.

And the hook covers pull-request bodies only. Nothing stops a push of a
commit that breaks a commit rule the registry says guards `push`.

## User Outcome

An agent running under the shirabe plugin, on any host, is stopped
before it takes an irreversible action that would break a rule guarding
it. The stop names the rule in the registry's own words, its summary,
and says where its full text is, so the agent learns the rule at the
moment it needs it, fixes what it was about to do, and retries in the
same turn. A person reading the transcript or the event log sees which
registered rule fired.

When the hook can't check, because its binary is missing or its inputs
or the registry can't be read, the guarded action is stopped and the
reason says why and how to recover. Every command the hook doesn't
guard runs exactly as it would without the plugin, whatever state the
hook is in.

A maintainer whose workspace already wires the pr-body hook another
way sees nothing change for the worse when they upgrade: each deny
arrives once, not twice. A maintainer who opted a host into the live
offload canary sees the canary behave as it did before.

## User Journeys

### A plugin-only user opens a pull request

A developer installed the shirabe plugin and nothing else. Their agent
runs `gh pr create` with a body that has no `---` separator. Before the
command runs, the hook denies it with the PB2 rule's summary and a
pointer to its text in `references/pr-body-conformance.md`. The agent
adds the separator and re-runs the command, which goes through.

### An agent pushes a commit that breaks a commit rule

An agent finishing a change runs `git push`. One of the commits being
pushed carries a `Co-Authored-By:` trailer naming an AI model. The push
is denied with the registered summary of the commit-trailer rule,
naming the commit. The agent rewords the commit and pushes; nothing
with the trailer ever reached the remote.

### A workspace maintainer upgrades a host that already wires the hook

A workspace maintainer's niwa host has injected `shirabe pr-body-hook` into its settings for
months. It upgrades to a shirabe release whose plugin declares its own
hook. A malformed `gh pr create` is denied once, with the registered
rule, not once by each hook. Removing niwa's injection is not
required for that.

### A user whose shirabe binary is missing

Unlike the first journey, the rule here is never evaluated: the check
itself can't run. A user installed the plugin's files but not the
`shirabe` binary. Their agent's `ls`, `cargo test` and `git status` run untouched. Their
`gh pr create` is denied with a reason saying the check couldn't run
because the binary isn't installed, and how to install it or turn the
hook off.

### A maintainer running the offload canary

A maintainer opted their host into the live offload canary, which
measures what leaving one rule out of context costs. On that host a
`gh pr create` whose body
has a heading in Part 1 (PB4) goes through, as it does today, so the
/work-on gate can count the violation. The same command with a missing
separator is denied.

## Scope Boundary

### In

- A PreToolUse hook the shirabe plugin itself declares, so installing
  the plugin is enough to get it.
- Denying the irreversible actions whose guarding rule can be decided
  from the command and the local repository alone: creating or editing
  a pull request (the PR-body rules, today's pr-body hook), and pushing
  (the commit rules the registry says guard `push`).
- Deny reasons built from the registry: each rule's summary, with a
  pointer to its full text.
- Failing closed on guarded actions when the hook can't read its inputs,
  its binary or the registry, with the reason; never touching a command
  it doesn't guard.
- Keeping today's pr-body hook entry point working for hosts that wire
  it, without a second deny where both are present.
- Keeping the canary's PB4 exception on opted-in hosts.
- Linking each guarded rule in the registry to the hook as a check, so
  the registry says what blocks the action.

### Out

- Withholding any rule from an agent's default context. The deny is the
  precondition for that, not the change itself; no rule becomes
  eligible here.
- Rules whose check needs GitHub's state or a run's koto record (panel
  findings, verification verdicts, a pull request's live body at merge
  time). They stay at their gates.
- A deny on `gh pr merge` unless a rule guarding `merge` can be decided
  locally; merges stay behind required CI checks and the review pause.
- Linter check states and validate-and-return on koto gates, which are
  separate features.
- Changing niwa's own hook wiring, beyond what avoiding a double deny
  needs.
- Hosts other than Claude Code. The hook is a Claude Code plugin hook.

## References

- `crates/shirabe/src/pr_body_hook.rs` -- today's PreToolUse adapter.
- `references/rule-registry.md` -- the registry's fields, including
  `guards`, `withhold` and `backstop`.
- `docs/guides/offload-live-canary.md` -- the PB4 exception on opted-in
  hosts.
- `references/pr-body-conformance.md` -- the PR-body rules PB1 to PB4.
