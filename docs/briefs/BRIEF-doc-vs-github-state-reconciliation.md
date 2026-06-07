---
schema: brief/v1
status: Done
problem: |
  A shirabe plan or roadmap can be perfectly self-consistent -- the table
  strikethrough agrees with the diagram class, the Legend agrees with the
  classDef set, and the validator emits no FC07 or FC08 notices -- and still
  lie about external reality. The doc claims an issue is closed while GitHub
  shows it still open, or the doc still classes a node `ready` long after a
  parallel PR closed the issue. The validator runs offline-only today, so the
  drift between what the doc asserts and what the world actually shows never
  fires any signal.
outcome: |
  A doc author who edits a plan or roadmap sees the validator surface a
  specific notice the moment the doc's claim about an issue diverges from
  GitHub's actual issue state, or the moment a PR's `Closes #N` lines
  disagree with what the doc shows as done. The validator becomes the third
  reconciliation surface, alongside intra-document and cross-document checks;
  local-dev workflows without credentials still work because the check
  self-disables with one notice rather than failing the build.
---

# BRIEF: doc-vs-github-state-reconciliation

## Status

Done

## Problem Statement

shirabe's validator reconciles plan and roadmap docs along two axes today
and stops there. The intra-document axis is FC07 (the parsed Implementation
Issues table against the extracted Dependency Graph, across node set, edge
set, and class-versus-Status) and the forthcoming FC08 (the Legend prose
against the classDef set). The cross-document axis is R6 -- a doc's
`upstream:` reference must resolve to an existing file. Together these two
axes catch the drift that lives inside the docs the validator can read.

Neither axis reaches outside the docs. The validator binary runs offline:
no network, no GitHub API, no PR context. A plan or roadmap that has been
perfectly reconciled along both axes -- table strikethrough agrees with
diagram class, Legend agrees with classDef set, every upstream resolves --
can still lie about the world. The doc claims an issue is closed and the
diagram paints its node `done`, but the actual GitHub issue is still open
because the PR meant to close it never landed. The symmetric case is more
common: an issue was closed weeks ago by an adjacent PR, the row should be
struck through and the diagram node should be `done`, but no one updated
the doc and FC07 sees the still-coherent stale state. And a PR can land
with `Closes #N` in its body while the doc still shows the same row as
`ready` in the diagram, because the validator never reads the PR body
either.

The drift is not hypothetical. The same milestone that motivated FC07
already saw a hand-fix to a plan because an issue's state had moved out
from under the doc; FC07 caught some of that drift after the fact by
checking the intra-document class-versus-Status, but only because the
table strikethrough happened to have been updated. The cases where the
table is not updated, or where the issue closes through a different repo's
PR, or where a fresh PR body says one thing and the doc says another,
remain entirely uncaught. Every plan and roadmap in the corpus is one
parallel PR away from a defect no check fires on.

A second illustrative shape: a PR body that says `Closes #N` for an
issue the doc still shows as `ready` is undetectable today, in either
direction. The PR can land with the inconsistency intact, and the next
reader of the merged doc sees a `ready` class for an issue the merge
just closed.

The gap has the same shape FC07 closed for the intra-document axis but at
a different altitude. A reader who trusts the diagram as a faithful render
of reality is led to the wrong picture of which work is done, which is in
flight, and which is unstarted. The longer the corpus accumulates this
third kind of drift before any check exists, the more expensive a later
one-shot reconciliation becomes -- which is precisely why this third axis
is shaped as a staged increment behind a notice-then-error rollout rather
than a strict-from-day-one error check.

The friction the gap exposes is not "build a GitHub client from scratch."
Workspace conventions for GitHub API integration already cover the cli +
auth surface this check would consume, and a graceful-degradation posture
for optional substrates already shapes how other cross-layer dependencies
behave when their substrate is missing. The unmet need is a check whose
contract crosses the offline boundary cleanly -- engaging on the doc's
state claims when credentials and PR context are available, and ceding
that ground without breaking the rest of the validator when they are
not.

## User Outcome

A doc author edits a plan or roadmap and the validator surfaces a specific
notice the moment a claim about issue state diverges from reality. A row
marked done while the issue is open fires a notice naming the row, the
diagram node, and GitHub's observed state. A row still classed `ready` for
an issue GitHub already closed fires a notice naming the row, the node,
the observed state, and the expected one. A PR body's `Closes #N` line
that disagrees with what the doc shows fires a notice naming the issue,
the body line, and the doc's claim -- in either direction, whether the PR
under-claims (the doc says done but no `Closes` line exists for it) or
over-claims (the PR says `Closes #N` but the doc still shows that issue
as ready).
The notices match the FC05/FC06/FC07 voice, name the specific defect site,
and the fix path is mechanical.

Local-dev workflows do not break. The check follows the workspace's
established graceful-degradation posture: when its substrate is missing
the dependent surface continues with a reduced capability rather than
failing. A doc author running the validator without `GITHUB_TOKEN` and
without the `gh` CLI sees a single skip notice explaining the check
disabled itself; FC01 through FC08 still run, and nothing about the
offline experience changes. The same posture applies to a CI environment
whose token has run out of rate-limit budget or whose token has no access
to a cross-repo issue the doc references -- each case emits a specific
skip notice and the rest of the check proceeds. The validator never
panics on a malformed GitHub response, and the credentials it consumes
are never logged or echoed to its output.

The author no longer has to manually compare the doc against issue state
in their head. The validator does the reconciliation across all three
sub-dimensions -- doc-claims-done versus GitHub, doc-claims-open versus
GitHub, and PR `Closes` versus doc -- and the doc becomes a trustworthy
render of real-world state by construction.

Because the check ships as a notice rather than an error, CI stays green
while the existing committed corpus reconciles row by row as authors touch
each plan and roadmap. The volume of notices drops as the corpus is cleaned
up, and a maintainer flips the one-line `is_notice` membership in the same
PR that finishes the cleanup to promote the check to error-level. The
shipping path does not force a one-shot retrofit and does not block
local-dev work, and the corpus gets a reliable contract once the cleanup is
done.

A downstream sub-DESIGN author landing on this brief cold picks up the
three sub-check shape, the self-disable behavior across the four
credentials/PR/rate-limit/cross-repo gaps, and the notice-then-error
staging without re-reading the FC07 sub-DESIGN or the parent PRD. The
framing this brief settles -- three sub-checks under one `check_fc09`,
client surface as an abstraction not pre-committed to subprocess versus
HTTP, defensive parsing of all external input -- is recorded here as the
boundary the sub-DESIGN refines, not content the sub-DESIGN has to
re-derive.

## User Journeys

The feature is exercised from five entry points. Each names the user, the
trigger that brings them to the check, and the outcome the validator
surfaces.

### Journey 1: Doc author marks a row done that GitHub still shows open

A plan author updates the Implementation Issues table -- a strikethrough
applied, the matching diagram node re-classed `done` -- intending to mark
work complete. The closing PR hasn't actually landed yet, or the closing
PR closed a different issue, or the author misremembered which issue was
which. The validator runs `check_fc09` in the plan or roadmap arm
alongside the existing checks; Sub-check A (doc-claims-done vs GitHub)
fetches the named issue's state, observes that GitHub still shows it
`open`, and fires a notice naming the row, the diagram node, and the
observed state. The notice is non-blocking, so CI exits 0, but the PR
carries a visible signal the author can act on before merge.

This journey validates that Sub-check A fires on the most common
forward-direction defect (the author got ahead of reality) and that the
notice level is honored.

### Journey 2: Doc author leaves a row open after a parallel PR closed it

A maintainer surveys their plan and finds a row still classed `ready` for
an issue that closed three weeks ago via a PR in an adjacent slice. No
one updated the doc after the parallel closure because no one was paying
attention to that row. The validator runs `check_fc09`; Sub-check B
(doc-claims-open vs GitHub) fetches the named issue's state, observes
that GitHub shows it `closed`, and fires a notice naming the row, the
node, the observed `closed` state, and the expected `done` class. The
maintainer updates the table strikethrough and the diagram class, and the
next run is clean.

This journey validates that Sub-check B catches the stale-plan case --
the exact failure mode FC07 cannot see, because FC07 only reconciles
intra-document state and a perfectly self-consistent stale doc passes its
node-set, edge, and class-versus-Status checks.

### Journey 3: PR author writes a `Closes` line that disagrees with the doc

A PR author writes a `Closes #N` line in their PR body for an issue,
intending to ship that issue's work along with the rest of the PR. The
doc the PR touches still shows that issue as `ready` in the diagram --
a separate update that should have happened in the same PR but didn't,
or a doc the author thought was already updated. When the validator runs
in PR context (the workflow exposes `GITHUB_PR_NUMBER` and the token has
access to the PR body), Sub-check C extracts every `Closes #N` from the
body and compares against doc claims; the body line disagrees with the
doc's `ready` class, and a notice fires naming the issue, the body line,
and the doc's claim.
Sub-check C fires in the other direction too: a row the doc shows `done`
whose issue is still open on GitHub but is not named in any
`Closes #N` line on this PR fires a notice flagging that the doc
anticipates closure no PR is delivering.

This journey validates that Sub-check C closes the third gap -- the
PR-body-versus-doc disagreement that neither Sub A nor Sub B catches on
its own, because the PR body is invisible to a pure issue-state
reconciliation.

### Journey 4: Doc author runs the validator locally without credentials

A doc author working on a plan invokes `shirabe validate
--visibility=public docs/plans/PLAN-foo.md` from a shell with no
`GITHUB_TOKEN` set and no `gh auth login` configured. The validator
detects the missing credentials, FC09 self-disables with a single
`[FC09] skipped: no GitHub credentials available` notice, and the rest of
the validation -- FC01 through FC08 -- proceeds normally. The author
sees the skip notice, finishes their local edit cycle, and pushes; CI
runs the same validator with credentials and the FC09 check engages
properly there.

This journey validates that the offline self-disable path keeps the
existing local-dev workflow viable. A check that fails the validator on
a missing token would block every author who isn't running a configured
shell and would force `gh auth` setup as a prerequisite for editing a
plan -- the opposite of the staged-rollout posture.

### Journey 5: Maintainer reconciles the corpus and promotes the check

A maintainer surveys the existing committed plans and roadmaps after FC09
has been running on every PR for a release cycle. They see the FC09
notice volume drop to zero across the corpus as authors fix issues on
their own PRs, and they open a cleanup PR that fixes the last remaining
disagreements. In the same PR they remove the `FC09` arm from the single
`is_notice` site (a one-line change). They ship the PR; from the next CI
run forward, the maintainer holds a reliable contract -- a fresh
doc-versus-GitHub disagreement reddens CI rather than emitting a quiet
notice, and they can rely on that contract holding when the next plan or
roadmap lands.

This journey validates that the staged-rollout shape FC07 and FC08 used
applies cleanly to a network-dependent check too -- the promotion seam
is identical, and the one-line `is_notice` flip remains the executable
end state.

## Scope Boundary

This brief frames a single validator check, `check_fc09`, that reconciles
each plan or roadmap doc's claims about issue state against GitHub's
actual issue state, and against the current PR body's `Closes #N` lines
when running in PR context. It is the third pillar of consistency
alongside FC07/FC08 (intra-document) and R6 (cross-document); it ships
behind the same notice-then-error staging the FC07/FC08 rollout uses.

The scope holds the following inside:

- The `check_fc09` reconciliation check dispatched in the plan and roadmap
  arms of `validate_file` alongside FC05, FC06, FC07, and FC08, structured
  as three sub-checks running in a single pass over the parsed Table and
  the extracted Diagram. Sub-check A reconciles doc-claims-done against
  GitHub's issue state; Sub-check B reconciles doc-claims-open against
  GitHub; Sub-check C reconciles the PR body's `Closes #N` lines against
  doc claims when running in PR context.
- A GitHub issue-state client surface, isolated to its own module under
  `crates/shirabe-validate/src/`, that the check consumes via a stable
  trait. The trait names the operations the check needs
  (fetch issue state, fetch PR body) without binding the implementation
  to a specific transport; the test surface mocks it with canned
  responses. Authentication via `GITHUB_TOKEN` or `gh auth status`;
  defensive parsing of every external response; the token never logged or
  echoed to stdout or stderr.
- Self-disable behavior across four distinct gaps, each emitting one
  targeted skip notice and letting the rest of the check proceed:
  missing credentials (no `GITHUB_TOKEN` and no `gh` CLI),
  missing PR context (Sub-check C skips, A and B still run),
  rate-limit exhaustion after a single retry with back-off, and
  per-row cross-repo access-denied where the running token lacks read
  access to a `owner/repo#N` dependency.
- Per-defect notice messages in the FC05/FC06/FC07 voice, naming the
  specific row, diagram node, claimed state, observed state, and where
  applicable the PR body line that disagrees. The same per-defect voice
  applies to the four self-disable notices so that maintainers can tell
  from CI output which gap fired.
- Notice-level shipping via the existing `is_notice` membership, the same
  one FC07 and FC08 share, with the same one-line promotion seam.
  Promotion to error is a single-arm membership change.
- Bounded behavior over arbitrary external input: the check produces a
  result for any GitHub response without panicking on malformed JSON,
  missing fields, unexpected schemas, or unexpected status codes; the
  check produces a result without unbounded retries (single retry then
  self-disable) and without hangs (every network call has an explicit
  timeout); the implementation introduces no unbounded loops.
- A downstream sub-DESIGN that picks up the requirements, settles the
  implementation path the BRIEF deliberately leaves open
  (the transport, the test-fixture mechanism, the specific notice
  strings, the timeout values), and tracks against the parent
  `DESIGN-roadmap-plan-standardization.md` Decision 3 staging the same
  way the FC07 sub-DESIGN does.

The scope explicitly excludes:

- **The actual promotion of `check_fc09` to error-level.** Promotion
  happens after the committed corpus is reconciled (zero notice volume),
  in a separate cleanup PR that flips the one-line `is_notice`
  membership. This brief ships the seam, not the flip. Same staging shape
  the FC07 and FC08 rollouts use.
- **A retrofit of the committed corpus.** The notice-then-error rollout
  exists precisely so corpus reconciliation happens incrementally after
  the check ships. Bulk-fixing the current corpus is out; an author who
  hits a notice fixes it in their own PR.
- **The choice between `gh` CLI subprocess and a raw HTTP client.** The
  issue body and the implementation handoff doc both name these as
  viable paths; the BRIEF binds the requirements (auth, offline behavior,
  rate-limit tolerance, defensive parsing, no panics, token never
  logged) without pre-committing the transport. The downstream
  sub-DESIGN settles the choice with the trade-off analysis appropriate
  to a HOW decision; pulling that into the brief would mix altitudes.
- **A general GitHub-API mock framework for the workspace.** The
  test-side mocking lives in-crate alongside FC09's own tests, matching
  the inline-string fixture pattern Decision 4 of the FC07 sub-DESIGN
  settled. A future check needing a GitHub client surface can reuse the
  trait; promoting the test mocks to a shared utility is a separate
  decision a later increment owns.
- **Pipeline-stage class reconciliation against GitHub.** FC09 fires only
  on Status-bearing classes (`done`, `ready`, `blocked`) and on
  strikethrough rows. The pipeline-stage classes (`needsDesign`,
  `needsPrd`, `needsSpike`, `needsDecision`, `needsPlanning`,
  `needsExplore`, `tracksDesign`, `tracksPlan`) encode pre-binding
  upstream-artifact prerequisites with no corresponding GitHub
  issue-state semantics. FC09 ignores them, matching FC07's Decision 1
  in the parent sub-DESIGN.
- **Cross-repo refs that the running token cannot access.** When a
  Dependencies cell carries an `owner/repo#N` reference and the running
  token returns 403 or 404, FC09 emits one per-row skip notice
  identifying the inaccessible cross-repo reference and continues. The
  scope does not extend to discovering or injecting additional tokens
  for cross-org access; that is an infrastructure decision outside this
  check's contract.
- **A general PR-context plumbing layer for the validator.** FC09 reads
  the env vars it needs (`GITHUB_TOKEN`, `GITHUB_REPOSITORY`,
  `GITHUB_REF` or a dedicated `SHIRABE_PR_NUMBER`) and detects PR context
  from them. Generalizing PR context into a shared validator runtime
  layer that future checks could consume is downstream work; FC09 is the
  first check to need any of this and its surface stays local until a
  second consumer appears.
- **Network-dependent behavior anywhere outside `check_fc09`.** FC01
  through FC08 remain pure offline checks. The validator's default
  posture stays offline-first; FC09 is the singular network-dependent
  surface and self-disables cleanly when credentials or context are
  missing so the offline-first guarantee continues to hold for every
  other check.

## References

- Parent PRD (R8 staged reconciliation, R20 notice-then-error contract):
  `docs/prds/PRD-roadmap-plan-standardization.md`.
- Parent DESIGN (Decision 3 staging the reconciliation increment behind a
  spike and a notice rollout):
  `docs/designs/current/DESIGN-roadmap-plan-standardization.md`.
- Parent PLAN (the row that schedules this increment alongside FC08 and
  the Slice D lifecycle work):
  `docs/plans/PLAN-roadmap-plan-standardization.md`.
- FC07 sub-DESIGN (the architectural precedent for the class-versus-Status
  pass FC09 extends with `observed_state` from a GitHub client instead
  of `row.terminal`):
  `docs/designs/current/DESIGN-table-diagram-reconciliation.md`.
- FC07 BRIEF (the tone and shape this brief mirrors):
  `docs/briefs/BRIEF-table-diagram-reconciliation.md`.
- Canonical issues-table conventions (the Status column for the roadmap
  profile, strikethrough-on-done for the plan profile, the cross-repo
  `owner/repo#N` form for Dependencies cells):
  `references/issues-table.md`.
- Canonical dependency-diagram conventions (the Status-class palette FC09
  binds to, the pipeline-stage classes FC09 ignores, the custom-mnemonic
  external-node exclusion):
  `references/dependency-diagram.md`.
