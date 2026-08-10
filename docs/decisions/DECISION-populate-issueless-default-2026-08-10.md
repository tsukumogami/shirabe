---
status: Accepted
decision: |
  `shirabe roadmap populate` defaults to the issueless render path. The
  issue-creating path is reached only by an explicit `--issues`; `--no-issues`
  is retained as an explicit opt-out and the two are mutually exclusive. This
  supersedes decision driver D5 of
  docs/designs/current/DESIGN-roadmap-issueless-preference.md, which required
  the default to remain `required` for backward compatibility.
rationale: |
  Blast radius, not ergonomics. The new default's failure mode is "no issues
  created" -- local, immediately visible, and recoverable by re-running with a
  flag. The old default's failure mode is "unwanted issues created on a shared
  remote" -- a side effect on state other people see, which someone has to
  close by hand. Both mistakes are equally easy to make; only one leaves a mess
  outside the working tree. D5's backward-compatibility argument was correct
  when issueless mode was new and unproven, and defaulting to it would have
  changed behaviour for every existing user in exchange for an unrequested
  benefit. Issueless mode has since shipped, had its rendering fixed, and
  become the mode the /roadmap workflow uses on every automatic run, so its
  correctness is no longer the open question. What remains is the asymmetry,
  and it points the other way.
---

# DECISION: populate defaults to issueless

## Status

Accepted

## Context

`shirabe roadmap populate <path>` read its mode from a single boolean flag,
`--no-issues`, defaulting to false. An invocation naming no mode ran the
issue-creating path: one `gh issue create` per feature, plus a `gh repo view`
to resolve issue links. The issueless path was already complete and fully
hermetic -- it constructs no `Command` at all -- but you reached it only by
knowing the flag existed.

`docs/designs/current/DESIGN-roadmap-issueless-preference.md`, which
introduced issueless mode, recorded this as a deliberate constraint. Its
decision driver D5 reads:

> **D5 -- Backward compatibility.** Repos with no new header must behave
> exactly as today (issue-creating populate, "Do not fill manually" in force).
> The default must be `required`.

That design shipped the `## Roadmap Issues:` CLAUDE.md header as an opt-in,
with the header resolving to `required` when absent -- explicitly fail-closed
toward the issue-creating, human-gated path.

Two things changed since.

Issueless mode stopped being speculative. It shipped, and its rendering
defects were fixed (the `F<n>` keying and unbounded description cells, in
#262). It is no longer a new path whose output nobody has read.

And the coupled change landing alongside this decision makes issueless the
mode the tooling itself uses. `/roadmap` now populates its reserved sections
automatically during a normal run, issuelessly, closing a hole where a roadmap
could be created, activated, merged, and worked to completion with both
reserved sections still empty skeletons -- FC16 is shape-gated, so nothing
complained. Once the workflow's own population is issueless on every run,
"issue-creating is what you get by default" describes only the case where a
human types the command by hand, which is exactly the case where the
expensive mistake is easiest to make.

## Decision

Invert the default.

- `shirabe roadmap populate <path>` with no mode flag runs the issueless
  render path. No issues are created and no `gh` call of any kind is made,
  including the `gh repo view` fallback.
- `--issues` selects the issue-creating path, with behaviour identical to
  what the unflagged invocation used to do, including the milestone and
  mapping flags.
- `--no-issues` is retained, not deprecated, and still means issueless. Both
  spellings are explicit.
- The two flags are mutually exclusive, enforced by clap's `conflicts_with`.
  A conflicting invocation is rejected during argument parsing, so no roadmap
  mutation and no `gh` call can occur.
- The mode resolves on `flag > ## Roadmap Issues: header > issueless default`.
  The header now defaults to `optional` when absent, and governs only what a
  human-invoked `/roadmap populate <path>` does with no flag. It never affects
  the automatic population.
- Every caller inside this repository names its mode explicitly. The CLI
  default is a backstop for a human at a shell; no workflow depends on it.

D5 is superseded. The reasoning it encoded is recorded above and is not
disowned -- it was right for the change it governed.

## Options Considered

**Flip the default (chosen).** Puts the harmless outcome on the path you reach
by accident. Costs a breaking change for direct CLI callers with unflagged
invocations, who silently get no issues; the release note names it, and the
failure is recoverable by adding `--issues` and re-running.

**Leave the CLI default alone and fix this only at the skill layer.** Raised
and overruled by the maintainer. It would have made the workflow safe while
leaving the dangerous default in the position a human reaches by typing the
command directly -- which, once the skill always passes an explicit flag, is
the only position where the default is ever consulted. Fixing the layer that
no longer uses the default, and not the one that does, gets the priority
backwards.

**Drop `--no-issues` and keep one flag.** Rejected. It would break every
existing explicit issueless invocation for no gain, and it removes the ability
to name the safe mode -- which the skill relies on, since the safety property
is that callers say what they want rather than inheriting it.

**Resolve `--issues --no-issues` last-wins instead of erroring.** Rejected.
The two outcomes differ by whether issues get filed on a remote, so silently
discarding half a command line is exactly the class of mistake this decision
exists to prevent.

## Consequences

A mistaken invocation now costs a re-run instead of a cleanup. A `/roadmap`
run produces a complete roadmap without a second command. Reading any in-repo
invocation tells you what it does without knowing the default.

Direct CLI callers with saved unflagged invocations get a behaviour change
with no error: they will get a populated roadmap and no issues. The summary
JSON's empty `mapping` object signals the issueless run, but nothing fails
loudly. This is the accepted cost, and the release note for the shipping
version names it.

The `## Roadmap Issues:` header's semantics invert. A reader who learned the
old fail-closed direction has to relearn it. The skill prose and the
conventions reference change to match; notes kept outside this repo may not.

FC16 stays shape-gated, so an empty reserved-section skeleton still validates
at every lifecycle state. Automatic population makes that state much rarer but
does not make it detectable. Closing it properly -- rejecting an empty
skeleton on a non-Draft roadmap -- is a validator-surface change, deliberately
out of scope here, and worth taking up separately.

## References

- `docs/designs/current/DESIGN-roadmap-issueless-preference.md` -- the design
  carrying the superseded D5.
- `docs/designs/current/DESIGN-populate-issueless-default.md` -- the design
  this decision is drawn from; its Decision Drivers section carries the full
  argument.
- `docs/prds/PRD-populate-issueless-default.md` -- R15 is the requirement this
  record satisfies.
- `docs/designs/current/DESIGN-roadmap-issueless-table-rendering.md` -- the
  rendering fixes that made issueless mode proven rather than speculative.
