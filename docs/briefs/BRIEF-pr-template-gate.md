---
schema: brief/v1
status: Done
problem: |
  PR-template conformance — a Conventional Commits title plus the two-part
  squash-merge body — is enforced only on the automated skill path. A PR
  opened any other way (manual `gh pr create`, a dispatched worker) has
  nothing that states or checks the template, so a malformed body reaches
  merge and pollutes history, caught only if a human notices.
outcome: |
  A PR opened by any path — skill, manual, or dispatched — has its
  mechanical PR-body conformance checked by a path-independent CI gate, and
  the mechanical rule lives in one shirabe-owned authority the skills cite
  instead of restating. A malformed body fails CI rather than depending on
  a human to run a repair skill; subjective section choice stays advisory.
motivating_context: |
  Surfaced while filing the DRAFT-vs-READY discipline work (#220), whose PR
  was itself opened malformed by a dispatched worker — a generic body with
  no `---` separator — and fixed only because a human ran the repair skill
  afterward. The PR-template convention has the same "enforced only on the
  happy path" defect that #220 fixed for the lifecycle discipline.
---

# BRIEF: pr-template-gate

## Status

Done

The framing carries the same structural correction #220 applied to the
DRAFT-vs-READY discipline, now aimed at PR-template conformance: move the
mechanical rule off the automated happy path and behind a path-independent
gate. The downstream PRD owns the requirements articulation — which checks
are mechanical, the validator mode's interface, the CI trigger — and the
downstream DESIGN owns where the mechanical/advisory boundary is drawn.

## Problem Statement

The tsukumogami org squash-merges every PR, so a PR body is really two
documents joined by a `---` separator: Part 1 above the separator becomes
the commit body that lands on `main`, and everything from `---` down is
reviewer context deleted at merge. The title must be Conventional Commits
so the squashed commit reads cleanly. This convention is real and
load-bearing — a malformed Part 1 pollutes `main`'s permanent history.

The convention is enforced only where an automated skill authors the PR.
The rule lives inline in `/execute`'s `pr_finalization` state and
`/work-on`'s PR-creation phase, and the canonical wording lives in a
separate PR-creation skill shipped by the downstream consumer plugin, not
in shirabe itself. Three consequences follow, and they compound:

- **A PR opened off that path has no signal.** A contributor running
  `gh pr create` by hand, or a dispatched worker handed a bare "open a PR"
  instruction, gets no statement of the template and nothing that checks
  it. The convention is invisible to exactly the paths most likely to miss
  it.
- **It already broke in production.** The PR for #220 was opened by a
  dispatched worker with a generic `## What / ## Changes / ## Scope` body
  and no `---` separator. The gap surfaced only because a human noticed and
  ran a repair skill afterward. Relying on a human to catch it is the same
  happy-path fragility the repo already rejected for the lifecycle
  discipline.
- **The rule is duplicated and single-sourced by neither.** The mechanical
  shape is stated once inline in `/execute`, again in the downstream
  PR-creation skill, and referenced loosely by `/work-on`. shirabe even
  carries a dangling pointer to a `skills/pr-creation/SKILL.md` that does
  not exist in the shirabe repo. Two statements of the same rule drift.

The result is a convention that reads as enforced but holds only when a
skill happens to be the thing opening the PR. The property the repo wants —
a well-formed squash commit body regardless of who opened the PR — is not
defended.

## User Outcome

A contributor opens a pull request against a shirabe repository. It does
not matter whether a skill authored the body, they typed `gh pr create`
themselves, or a dispatched worker opened it: CI checks the mechanical,
objective parts of the PR body and fails the check when the title is not
Conventional Commits, when the body is missing its single `---` separator
or has an empty Part 1, or when the body carries an AI-attribution or
co-author footer. The contributor sees the failure at the PR, reads a
message that names what is wrong, fixes the body, and the check passes.

The mechanical rule the gate enforces lives in one place that shirabe
owns. The automated skill paths that author PRs cite that single authority
rather than each restating the checks, so the statement a contributor is
gated against and the statement a skill authors from cannot drift apart.

Subjective judgment stays with the author. Which Part 2 sections a given
change needs — a test plan, an implementation note, a "what this enables"
— is reasoning the gate never touches. The contributor is caught on the
things a machine can decide and left free on the things it cannot.

## User Journeys

### A contributor opens a PR by hand

A contributor finishes a change, writes a body in their editor, and runs
`gh pr create` directly without invoking any skill. They forget the `---`
separator and write a title of `Update the validator`. CI runs the
conformance check against the PR and fails: the title is not Conventional
Commits and the body has no separator. The contributor reads the two
findings at the PR, adds a `feat:` prefix and a `---` before the reviewer
context, pushes an edit, and the check goes green. No human reviewer had
to notice the malformed body first.

### A dispatched worker opens a PR

A dispatched worker is handed a task brief and opens a PR when its work is
done. Without the gate, it produces the same generic no-separator body
that #220 shipped with. With the gate, CI fails the moment the PR opens,
the failure is visible on the PR itself, and the malformed body is caught
before a maintainer spends attention on it — the exact regression that
motivated this work is stopped at the door rather than after the fact.

### A skill authors a conformant PR

A contributor runs `/work-on` or `/execute`. The skill authors the title
and two-part body by citing shirabe's single conformance authority instead
of an inline restatement. Because the authored body satisfies the same
rule the gate enforces, CI passes on the first run, and there is no
separate repair pass. The skill path and the gate agree by construction
because they read the same source.

### A contributor opens a legitimate docs-only PR

A contributor fixes a typo in a guide and opens a PR with a one-line
Part 1, a `---`, and a minimal Part 2 that is just `Fixes #NN`. The change
needs no test plan and no implementation notes. CI passes: the mechanical
check confirms a Conventional Commits `docs:` title, exactly one separator,
a non-empty Part 1, and no attribution footer, and it never second-guesses
the sparse Part 2. A correct minimal PR is not a false positive.

### A contributor is stopped before opening a malformed PR

A contributor — or a dispatched worker — runs `gh pr create` by hand with a
body that has no `---` separator and a title of `Update the validator`. Before
the command runs, an authoring-time check reads the title and body, finds the
same mechanical violations the CI gate would, and stops the command with a
message naming them. The contributor fixes the title and adds the separator,
re-runs the command, and the PR opens clean on the first try. The malformed PR
never reaches GitHub, so no CI run and no reviewer attention is spent on a
defect a machine could name at the keystroke. This authoring-time surface
reuses the same rule the CI gate enforces; it is a faster feedback path, not a
different standard.

### A maintainer reads a failing check

A maintainer looks at a red conformance check on someone else's PR. The
annotation names the specific violation — "body has no `---` separator" or
"title is not Conventional Commits" — in plain terms, without pointing at
an out-of-band spec the maintainer has to go read. They can tell at a
glance what the author needs to change, and whether the failure is
mechanical (fix the body) rather than a judgment call.

## Scope Boundary

### IN scope

- Framing PR-template conformance as a property enforced independent of
  which code path opened the PR, mirroring how the DRAFT-vs-READY
  discipline was moved behind a path-independent gate in #220.
- Establishing a single shirabe-owned authority for the mechanical,
  objective PR-body rule — the rule the gate checks and the rule the
  skills author from are the same source, inside shirabe.
- The distinction between what is gated and what stays advisory: the
  mechanical, machine-decidable parts of the convention are enforced; the
  subjective Part 2 section selection is not. Drawing the exact line is
  the core question the downstream DESIGN settles.
- Path-independence as the acceptance property: the gate must catch a
  manual or dispatched PR, not only a skill-authored one, and must not
  fail a legitimate minimal PR.
- A second, authoring-time enforcement surface — a client-side hook that runs
  the same mechanical rule against a `gh pr create` / `gh pr edit` command
  before it executes — so the defect is caught in any checkout, even one with
  no CI wired. This was originally deferred (see below) and is now committed as
  a follow-on increment; the downstream PRD and DESIGN own its exact shape.

### OUT of scope

- Changing the PR template itself. The two-part body and the Conventional
  Commits title stay exactly as they are; this work enforces the existing
  convention, it does not redesign it.
- Gating Part 2 section selection. Which reviewer-context sections a change
  needs stays reasoning-based, never a checked rule.
- Modifying the downstream consumer's PR-creation skill. The mechanical
  logic is migrated into shirabe so shirabe is self-authoritative; the
  downstream skill is left untouched rather than extended with new checks.
- The local pre-PR hook was originally deferred here as a secondary
  mechanism; it is now committed (see IN scope) and specified by the
  downstream PRD (R13–R16) and DESIGN. Closing the dispatch gap — routing
  dispatched PR-opening work through a template-applying skill — remains out
  of scope: it is an orthogonal workflow-authoring change, not part of this
  enforcement work.
- Requirements articulation and interface shape — the precise check set,
  the validator mode's flags, the CI trigger events — belong to the
  downstream PRD and DESIGN, one altitude down from this framing.

## References

- `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` — the sibling
  framing for #220, whose PR reproduced the malformed-body defect this
  work generalizes; the same "move the rule off the happy path" correction
  applies to PR-template conformance.
- `references/coordination-strategy.md` — the coordination-PR body is the
  worked precedent for a skill-authored body checked statically by
  `shirabe validate` (`--coordination-body`) and live by `--merge-gate`;
  the mechanical PR-body check follows the same static-authoring-feedback
  shape.
