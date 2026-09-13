# Explore Scope: cascade-verdict-residue

## Visibility

Public

## Core Question

shirabe#354 asked for `cascade_status: partial` when the completion cascade can't
find the ROADMAP feature it was asked to update. PR #353 (merged as 7cd13d1)
delivered that verdict by recording the step as `failed` rather than `skipped`.
Two of #354's three acceptance criteria are written against a `skipped` step and
against a worked example in `DESIGN-completion-cascade.md` that shows `skipped`
with `partial`. What is the residue, really: a document to amend, criteria that
were wrong, or a behavioural gap nobody has named?

## Context

- Facts are taken from 7cd13d1 (main's head), not 9f84fa7, which #354, #355, #356
  and #358 were written against.
- On 7cd13d1, `run-cascade.sh` records both not-found arms of `handle_roadmap` as
  `failed` and sets `ANY_FAILED` (`:509-512`, `:520-523`); the verdict is
  `partial` iff `ANY_FAILED` (`:1150-1156`).
- The design's "Error message contract" table (`:296-304`) includes a "ROADMAP
  feature not found" row. The code comment and the PR #353 body both cite that row
  as the design's classification of the case as a failure.
- The same design renders the case as a `skipped` step in four other places:
  the worked example (`:340-356`), the ROADMAP-substitution prose (`:390`), the
  `handle_roadmap` step list (`:409`), and the Mitigations (`:573`). Its
  Consequences section (`:564`) says the update is "silently skipped", which
  contradicts the Mitigations directly.
- `execute.md` (`:754`, read-only for this worker) now defines `partial` as "at
  least one failed", which is consistent with the code.
- The coordinator's brief asks whether `failed` is even the right vocabulary for
  "the thing we were asked to do didn't happen", since the verdict is `partial`
  either way.

## In Scope

- What `DESIGN-completion-cascade.md` says about the not-found case, read whole
- The step-status vocabulary (`ok`/`skipped`/`failed`) as the script practises it,
  and whether a consistent rule exists
- Whether any not-found or not-finalized shape still reports the wrong verdict on
  7cd13d1, and what the tests pin
- Who consumes step `status` as opposed to `cascade_status`
- A disposition for each of #354's three criteria, and how the answer lands against
  #358

## Out of Scope

- Editing `skills/work-on/koto-templates/work-on.md` or
  `skills/execute/koto-templates/execute.md` (another worker owns them; reading is
  fine)
- #355, #356, #357 and the wider #358 architecture rewrite
- Reopening #353's `failed` choice as a code change (arguable as a finding only)
- Filing issues (proposals go to the coordinator)
- Any repo other than tsukumogami/shirabe

## Research Leads

1. **What does `DESIGN-completion-cascade.md` actually say about a ROADMAP feature
   that can't be found, read as a whole document?** (lead-design-reading)
   The brief frames it as two halves, a Failures table versus a worked example. The
   table may be a message contract for both skipped and failed steps rather than a
   classification, and four other passages side with the example. Which reading
   holds decides whether the code "satisfies one half" or departs from the design's
   whole model.

2. **What rule does the cascade's step-status vocabulary follow in practice, and
   where does "ROADMAP feature not found" fall under it?** (lead-status-vocabulary)
   Every `skipped` and `failed` arm in `run-cascade.sh`, whether it sets
   `ANY_FAILED`, and what the sibling docs (post-verify-seed PRD, lifecycle-check
   design, finalize-chain PRD) say a `skipped` step means. If `partial` iff some
   step `failed` is the rule, the worked example breaks it; if not, the code does.

3. **Does any shape still report the wrong verdict on 7cd13d1, and which shapes do
   the tests pin?** (lead-behaviour-gaps)
   The second not-found arm (a `Downstream:` line with no enclosing `###` heading),
   a ROADMAP whose feature names a different slug, the open-issue `delete_roadmap`
   skip that reports `completed`, and a ROADMAP reached through a DESIGN, PRD or
   BRIEF rather than directly. A named gap here changes the routing.

4. **Who reads step `status`, as distinct from `cascade_status`, and what would each
   possible resolution touch?** (lead-consumers-and-landing)
   Execute template, evals, other skills, and docs. It also covers how an amendment
   interacts with #358's third criterion ("worked examples remain the contract") and
   whether any resolution needs the two files this worker may not edit.
</content>
</invoke>
