# Draft designs

`/design` now writes its document at `Draft` from Phase 0 and moves it to
`Proposed` only at step 6.5, once the review has passed. Every commit it
makes along the way is one a validating pre-commit hook accepts, so a repo
with `shirabe install-hooks` no longer refuses the Phase 0 skeleton or the
Phase 5 and Phase 6 commits. This needs shirabe v0.47.0 or later.

## What changed

**Phase 0 writes a complete Draft design.** The skeleton's frontmatter holds
`status: Draft` and `problem`, its body Status reads `Draft`, and all nine
required sections are there from the first commit. A section `/design` hasn't
reached yet holds one stub marker line as its whole body; the line is defined
in `skills/design/references/design-format.md`, The stub marker. Each later
phase replaces the marker in the section it writes, and step 6.4 checks that
none is left.

**Only step 6.5 writes `Proposed`.** It adds `decision` and `rationale` and
moves the design to `Proposed` with `shirabe transition`, which changes the
frontmatter and the body Status together. Looping back at 6.2, or choosing
Continue revising at 6.7, sets the design back to `Draft`, and the next pass
through Phase 6 reviews it again. Revisions after 6.6 go to the same branch
and pull request.

**An older shirabe stops `/design` at Phase 0.** When the `shirabe` on `PATH`
refuses a design at `Draft`, `/design` stops before it writes or commits
anything and says it needs shirabe v0.47.0 or later.

**`/scope` and `/plan` read `Draft` as unfinished.** `/scope` doesn't count a
design hop as complete while its design is at `Draft`, and resuming `/scope`
on a `Draft` design goes back to the design step, the way a `Proposed` design
already did. `/plan` stops in Phase 1 on a `Draft` design and says it has to
be finished and reviewed first.

**Resuming reads the committed status first.** A section that still holds
the stub marker counts as not written, so a run stopped before Solution
Architecture resumes at Phase 4. The commits a resume makes on its own name
only the design file, so anything else you've staged stays staged.

**Older documents.** A design with no frontmatter `status` (the old
skeleton) is rewritten to the Draft shape when `/design` resumes it. Nothing
else needs changing.

## Migrating a design that reads Proposed too early

`/design` sets an early `Proposed` back to `Draft` only when it resumes in
the same live session with no Phase 6 review on record (without asking under
`--auto`, after asking otherwise); anywhere else it takes `Proposed` to mean
the review already happened. If a design of yours reads `Proposed` but never
went through the Phase 6 review and its session is gone, set it back to
`Draft` with
`shirabe transition docs/designs/DESIGN-<topic>.md Draft` and resume with
`/design <topic>`.

## References

- `skills/design/references/design-format.md`: the Draft status, the stub
  marker and the status transitions.
- `skills/design/references/lifecycle.md`: where each status is set.
- `references/doc-check-steps.md`: the rule every `/design` commit follows.
