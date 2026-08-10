---
schema: brief/v1
status: Done
problem: |
  `shirabe roadmap populate` creates GitHub issues when invoked with no mode
  flag, so the failure mode of a mistake is unwanted issues on a shared remote.
  Separately, `/roadmap` never populates at all: the workflow ends at the
  Phase 4 jury and the reserved sections stay empty skeletons that validate at
  every lifecycle state, so a roadmap can be created, activated, and worked to
  completion with both sections blank and nothing complaining.
outcome: |
  Running the subcommand without naming a mode does nothing to a remote. A
  `/roadmap` run ends with both reserved sections filled from feature context
  and no issues created. Filing issues becomes a deliberate act taken after the
  roadmap is approved, and it is the only path that touches GitHub.
motivating_context: |
  Dispatched as a maintainer decision, not a bug report. A recommendation to
  leave the CLI default alone and fix this only at the skill layer was raised
  and overruled: the reasoning is blast radius, not ergonomics. This
  deliberately supersedes decision driver D5 of
  docs/designs/current/DESIGN-roadmap-issueless-preference.md, which required
  the default to stay `required` for backward compatibility.
---

# BRIEF: Populate issueless by default

## Status

Done

Framing for a coupled pair of changes: which mode `shirabe roadmap populate`
picks when nobody says, and when the reserved sections get filled at all. The
downstream PRD owns the requirements; the four choices this brief leaves open
are named in Open Questions and resolve in the DESIGN.

## Problem Statement

Two problems share a cause, and fixing either alone leaves the other in place.

The first is the CLI default. `shirabe roadmap populate <path>` with no mode
flag creates one GitHub issue per feature. A twenty-one-feature roadmap
populated by someone who meant to preview it files twenty-one issues on a
shared repository. Nothing local went wrong, so nothing local can undo it —
someone has to go close them by hand. The issueless path already exists behind
`--no-issues` and makes no `gh` call at all, so the safe behaviour is already
built; it just isn't what you get by default. The asymmetry is the whole
argument. Guessing wrong toward issueless leaves you with an unpopulated file
you re-run in a second. Guessing wrong toward issue-creating leaves a side
effect on state other people share.

The second problem is bigger than the default, and it's the one that makes this
worth doing now. The `/roadmap` creation workflow ends at Phase 4, the jury
review. Populate is reachable only through input mode 3, `/roadmap populate
<path>`, which a human has to remember to type. FC16 — the check that guards
the reserved sections — is shape-gated rather than status-gated, so an empty
skeleton passes at every lifecycle state. Put those together and a roadmap can
be drafted, jury-reviewed, activated, merged, and worked to completion with its
Implementation Issues table and Dependency Graph still empty, and no check
anywhere says a word. The sections are reserved for a tool that never runs.

The two compound in an unhelpful direction. Because populate is a separate
manual step, the people who do remember to run it are running the command whose
unflagged default files issues. The step that's easy to skip is guarded by the
default that's expensive to get wrong.

## User Outcome

An author finishes a `/roadmap` run and has a complete roadmap. Both reserved
sections carry real content derived from the features they just wrote, they did
not type a second command to get it, and nothing was created on GitHub while it
happened. What they review before approving is what the document will look like
after it merges.

Someone who types `shirabe roadmap populate <path>` at a shell, having read
neither the skill nor this brief, changes a local file and nothing else. If
they wanted issues, they say so, and the command that says so is the one that
files them.

An author who wants issues files them deliberately, after the roadmap is
approved rather than before, and the approval gate they already know still
stands in front of that step. The table they end up with carries the issue
links, because filing regenerates it.

## User Journeys

### Creating a roadmap end to end

A maintainer runs `/roadmap` on a new initiative. Scoping, research, drafting,
and the jury all run as they do today. Before the approval walkthrough, the
reserved sections fill in from the features — a table keyed on each feature's
label, a dependency graph — with no GitHub call. The maintainer reads a
complete document, approves it, and it activates. At no point did they type
`populate`, and at no point were they asked to approve issue creation, because
none happened.

### Filing issues after approval

The same maintainer decides a week later that this roadmap's features should be
tracked as issues. They invoke the issue-filing action explicitly. The approval
gate presents the features that will become issues, the count, and the
milestone. They approve. The issues are created and both reserved sections are
regenerated so the table now carries issue links instead of labels.

### Reaching for the command directly

A contributor debugging a rendering problem runs `shirabe roadmap populate
docs/roadmaps/ROADMAP-thing.md` to see what comes out. They get a populated
file and a clean exit. Their repository's issue list is untouched. They did not
have to know that `--no-issues` existed to avoid filing twenty issues.

### Getting the flags wrong

Someone types both `--issues` and `--no-issues`, either by editing a saved
command or by pasting two half-remembered forms together. The command refuses
and says why. It does not pick one silently, so the person never finds out
later which half of their command line was ignored.

## Scope Boundary

**In:**

- Which mode `shirabe roadmap populate` selects when invoked with no mode flag,
  and the `--issues` spelling that selects the issue-creating path explicitly.
- What happens when both mode flags are passed.
- Filling the two reserved sections as part of a normal `/roadmap` run, and
  where in that run it happens.
- The shape of the separate, explicitly-invoked issue-filing action, and its
  relationship to the approval gate that already guards issue creation.
- How the mode resolves across the per-invocation flag, the `## Roadmap Issues:`
  CLAUDE.md header, and the default.
- Updating every in-repo caller — skill prose, docs, and tests — so none of them
  depends on what the default happens to be.
- A decision record superseding D5, and a release note naming the breaking
  change for anyone invoking the CLI directly.

**Out:**

- Dropping `--no-issues`. Both spellings stay, and both stay explicit.
- The issueless table's rendering, which shipped in #262.
- Issue #263, the FC06 `F<n>` index alias.
- What the `Issues` column carries in issueless mode. Carrying a `needs-*`
  label in a column the shared spec describes as an issue fan-out is a known
  divergence, seen and deliberately left alone.
- Any change to the validator's checks. This is a CLI-default and
  skill-workflow change; FC16 staying shape-gated is a constraint here, not a
  target.
- Moving the approval gate into the subcommand. It stays in the calling skill.

## Open Questions

1. **Where does the automatic populate run?** At the end of the Phase 4 jury,
   on the `Draft -> Active` transition, or both. The feature list locks when
   the roadmap leaves Draft, and populate is idempotent, so re-running costs
   nothing — which makes "both" cheap if the two points cover different entry
   paths.
2. **What does the separate issue-filing action look like?** A new input mode,
   or the existing `/roadmap populate <path>` retained and given the `--issues`
   flag. Adding a mode next to one that already does almost the same thing has
   a cost the DESIGN should weigh against the clarity of a distinct verb.
3. **How does the mode resolve?** The repo already runs `flag >
   CLAUDE.md-header > default` for PR Grouping Policy and Reviewability
   Ceiling. Putting issue-creation on that same stack is the obvious move, but
   it has to be confirmed against the code — and the header's fail-closed
   direction inverts when the default flips.
4. **What does `--issues --no-issues` do?** A clear error or last-wins. The
   recommendation is an error; either way it gets decided rather than inherited
   from whatever clap does.

## References

- `docs/designs/current/DESIGN-roadmap-issueless-preference.md` — introduced
  issueless mode; its decision driver D5 is what this work supersedes.
- `docs/briefs/BRIEF-roadmap-issueless-table-rendering.md` — the sibling brief
  that framed what the issueless table renders, shipped as #262.
- `skills/roadmap/references/roadmap-format.md` — the Reserved Sections section
  and the FC16 shape-gating that lets an empty skeleton validate everywhere.
- `references/fixes/claude-md-conventions.md` — the `## Roadmap Issues:` header
  and the convention-header format the resolution stack would use.
