---
schema: brief/v1
status: Accepted
problem: |
  Two implementations decide whether a PLAN may be built from, and they give
  opposite answers on two of the four statuses a DESIGN can hold. Both run on
  the same pull request, so which verdict an author gets depends on which one
  speaks up first.
outcome: |
  One implementation answers "may a PLAN name this upstream", and when it
  reports success it means the document was checked. An author who reads
  "validation passed" can tell that apart from "I could not tell what this
  was, so I skipped it".
motivating_context: |
  Retiring the bash script is the obvious move and, done first, it opens a
  hole: the script is currently the only thing failing a PLAN whose `schema:`
  is missing or wrong, precisely because the CLI validator goes quiet on
  exactly those inputs. The silence has to be fixed before the duplicate can
  be removed.
---

# BRIEF: One validator for whether a PLAN may be built from

## Status

Accepted

Framing for issues #276 and #285. The downstream PRD owns the requirements;
this brief stops at the problem, the outcome, the journeys that exercise it,
and where the boundary sits.

Two framing details are deferred to the PRD's Decisions and Trade-offs section
rather than settled here: which surface carries the "declined to check" signal
— a distinct exit code, a field in the JSON envelope, or a strictness flag
callers opt into, constrained by having to reach a caller that reads only the
exit code — and whether the two script-only refusals survive by extending the
existing upstream-resolution check or are recorded as a deliberate removal.
Both were carried as Open Questions through the Draft and are recorded here
because Accepted status forbids that section.

## Problem Statement

Before work starts on a PLAN, two things check it, and neither knows about the
other.

`skills/plan/scripts/validate-plan.sh` is a 298-line bash pre-flight validator.
`shirabe validate` is the Rust validator whose own design document names that
script as the thing it was replacing. Almost everything the script checks, the
CLI already checks: frontmatter fields, whether the `upstream:` target exists on
disk, whether git tracks it. The script is not even a consistent second opinion
there — it misses `status` and `milestone`, which the CLI catches.

On the one rule that matters they disagree, in both directions. Setting a PLAN's
upstream DESIGN to each status in turn, with the PLAN itself unchanged:

| DESIGN status | `validate-plan.sh` | `shirabe validate --lifecycle-chain` |
|---|---|---|
| Accepted | passes | fails — expected `Planned` or `Current` |
| Planned | passes | passes |
| Current | fails — expected `Accepted` or `Planned` | passes |
| Proposed | fails | fails |

The script accepts `Accepted` and rejects `Current`; the lifecycle check does
exactly the reverse. The script predates the lifecycle posture model and encodes
the rule as it stood then; nothing reconciled the two when the model landed. Both
are reachable in CI on the same pull request — `check-plan-docs.yml` runs the
script over every changed PLAN, and `lifecycle.yml` runs the lifecycle check over
the tree — so an author's verdict depends on which check happens to fire.

Separately, and this is what makes the ordering load-bearing: `shirabe validate`
reports success for documents it never examined. Hand it a directory under
`--lifecycle` and it indexes zero files and exits 0. Hand it a `PLAN-*.md` whose
`schema:` field is missing, or holds `plan/v2`, and it emits a notice and exits 0.
The notice is not the problem — the exit code is, because the exit code is what
CI and every calling skill branch on. "Validation passed" currently means either
"checked and fine" or "could not tell what this was, so I skipped it", and
nothing an automated caller reads distinguishes them.

Those two defects are joined at the hip. The script is the only thing today that
fails a PLAN whose `schema:` is missing or wrong, and it is the only thing
catching that *because* the CLI goes quiet on exactly those inputs. Removing the
script before the silence is fixed subtracts the only gate.

## User Outcome

An author who runs the pre-flight on a PLAN gets one verdict from one place, and
that verdict answers the question it appears to answer. When the tool reports
success, the document was read and checked. When the tool declined to check
something — because the input named no artifact it could route, or because the
document did not say what it was — the author is told so by a signal a script can
branch on, not by a line of output that scrolls past.

A reviewer reading a pull request sees one pre-flight result rather than two that
can contradict each other, and the rule behind that result is written down with
the reasoning that chose it, so the next person to meet a surprising verdict can
find out why it is the rule.

## User Journeys

### An author's PLAN names an upstream that is not ready

A planning author finishes a PLAN whose upstream DESIGN is still sitting at
`Accepted` because the transition that should have moved it never ran. They push.
Today the answer depends on which check reports first: the script passes it and
the lifecycle check fails it, and the two messages name different expected
statuses. After this work there is one answer, one message, and the message names
the status the document should be at and why.

The journey's outcome shape is a single unambiguous verdict, not a faster one.

### A PLAN forgets to say what it is

An author writes a PLAN and omits the `schema:` line, or carries a stale
`plan/v2` from an older template. Today `shirabe validate` prints a notice and
exits 0, and only the bash script fails the document. After the script is gone,
that gate has to still be there — the author is told the document was not
checked, through the exit code, before anything downstream consumes it.

The journey exists to pin the ordering. It is the reason the silence is fixed
first and the duplicate removed second, rather than the other way round.

### An operator points the validator at the wrong thing

Someone runs the whole-tree lifecycle check against a docs directory instead of
the repository root. The tool joins `docs/briefs` beneath what it was given,
finds nothing, indexes zero documents, and reports clean. Two baseline
measurements in an earlier investigation were false negatives for exactly this
reason, and were caught only because a later run with an explicit file list
disagreed with them. After this work, a run that indexed nothing says so instead
of reporting a clean tree.

### A maintainer meets a verdict they did not expect

Someone reads a failing pre-flight that says their upstream DESIGN should be at
`Planned` and wonders whether that is a rule or an accident, since the script
that used to run here said `Accepted` was fine. They open the design document
that chose between the two rules and find the reasoning, the corpus effect it
was measured to have, and the date. The journey's outcome is that the decision is
recoverable, not that it is agreeable.

## Scope Boundary

**In:**

- Making `shirabe validate` report a result an automated caller can distinguish
  from a clean pass, for the two inputs it currently declines to check: an
  argument that resolves to nothing it can route, and a document whose `schema:`
  is missing or out of range.
- Choosing between the script's upstream-status rule and the lifecycle model's,
  recording the reasoning, and naming the corpus effect of the choice before the
  diff is taken.
- Deleting `skills/plan/scripts/validate-plan.sh` and its test suite, and
  re-pointing `check-plan-docs.yml` and `/plan`'s phase 7 at the surviving
  implementation.
- Preserving the two refusals only the script has — an `upstream:` that is a
  symlink, and one that resolves outside the repository — or recording their
  removal as a decision rather than dropping them silently.

**Out:**

- Repairing the corpus documents that the schema change would newly surface
  findings against. Thirty-two committed documents carry no `schema:` field
  today, and giving them one exposes content defects underneath. That is a
  documented consequence of this work, not part of it.
- Widening the CLI's upstream checks beyond what is needed to absorb the script.
  The script's own surface is the ceiling.
- Rewriting any other shell script, in bash or in another language.
  `plan-to-tasks.sh` in particular is untouched; it already moved off its own
  copy of the outline parse.
- Fixing the tooling defects this work has to route around. Working around a
  known-open defect is in; closing it is not.
