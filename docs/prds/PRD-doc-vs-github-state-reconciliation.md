---
schema: prd/v1
status: Done
problem: |
  shirabe's validator reconciles plan and roadmap docs along two axes today --
  intra-document (FC07 table-vs-diagram, FC08 Legend-vs-classDef) and
  cross-document (R6 upstream existence) -- but neither axis reaches outside
  the docs. A plan or roadmap can be perfectly self-consistent and still lie
  about external reality: the doc claims a row done while GitHub shows the
  issue open, or the doc still classes a node ready long after a parallel PR
  closed the issue, or a PR's `Closes #N` line disagrees with what the doc
  shows as done. The validator runs offline-only today, so this third drift
  surface fires no signal. Every plan and roadmap in the corpus is one
  parallel PR away from a defect no check catches.
goals: |
  A doc author who edits a plan or roadmap sees the validator surface a
  specific notice the moment the doc's claim about an issue diverges from
  GitHub's actual issue state, or the moment a PR's `Closes #N` lines
  disagree with what the doc shows as done. The validator becomes the third
  pillar of consistency alongside FC07/FC08 (intra-document) and R6
  (cross-document); the check ships behind the same notice-then-error
  staging the FC07/FC08 rollout uses, and the same one-line `is_notice`
  membership flip promotes it to error once the corpus is reconciled.
  Local-dev workflows without credentials still work because the check
  self-disables with a single notice rather than failing the build, and the
  bounded-behavior guarantee holds against arbitrary external input.
upstream: docs/briefs/BRIEF-doc-vs-github-state-reconciliation.md
---

# PRD: doc-vs-github-state-reconciliation

## Status

Done

This PRD picks up the requirements work scoped by
`docs/briefs/BRIEF-doc-vs-github-state-reconciliation.md`. It owns the
contract-level requirements for the FC09 validator check -- the three
sub-checks reconciling doc claims against GitHub issue state and the
current PR body, the GitHub client surface as a trait with no
transport binding, the four self-disable paths, the notice-level
rollout via the existing `is_notice` membership, the promotion-to-error
seam, the bounded-behavior guarantee over arbitrary external input,
and the public-cleanliness invariant. Implementation specifics -- the
transport choice (`gh` subprocess vs raw HTTP), the exact notice message
strings, the specific timeout values, the test fixture mechanism, and
the module layout -- land in a downstream DESIGN doc and its plan.

The PRD inherits and sharpens the parent
`PRD-roadmap-plan-standardization.md` invariants -- R8 staged
reconciliation, R20 no-day-one-breakage, and R22 public-cleanliness --
without re-litigating them. The BRIEF settles every framing question
(three sub-checks under one `check_fc09`, client surface as an
abstraction, defensive parsing of all external input, notice-then-error
staging); this PRD binds those settlements as numbered requirements
with binary acceptance criteria.

## Problem Statement

The shirabe validator runs offline today. The plan and roadmap arms
already dispatch FC05 (schema conformance), FC06 (cross-reference
existence), and FC07 (table-vs-diagram reconciliation across node set,
edge set, and class-versus-Status). FC08 (Legend-vs-classDef
reconciliation) is a sibling notice-level increment. R6 (upstream
existence) is the cross-document axis. Together these checks catch
drift that lives inside the docs the validator can read.

None of them reaches outside the docs. The validator binary has no
network surface, no GitHub API, and no PR context. A plan or roadmap
that has been perfectly reconciled along both existing axes -- table
strikethrough agrees with diagram class, Legend agrees with classDef
set, every upstream resolves -- can still lie about the world. The doc
claims an issue is closed and the diagram paints its node `done`, but
the actual GitHub issue is still open because the closing PR never
landed. The symmetric case is more common: an issue was closed weeks
ago by an adjacent PR, the row should be struck through and the diagram
node should be `done`, but no one updated the doc and FC07 sees the
still-coherent stale state. And a PR can land with `Closes #N` in its
body while the doc still shows the same row as `ready` in the diagram,
because the validator never reads the PR body either.

The drift is not hypothetical. The same milestone that motivated FC07
already saw a hand-fix to a plan because an issue's state had moved out
from under the doc; FC07 caught some of that drift after the fact by
checking the intra-document class-versus-Status, but only because the
table strikethrough happened to have been updated. The cases where the
table is not updated, or where the issue closes through a different
repo's PR, or where a fresh PR body says one thing and the doc says
another, remain entirely uncaught. The longer the corpus accumulates
this third kind of drift before any check exists, the more expensive a
later one-shot reconciliation becomes -- which is precisely why this
third axis is shaped as a staged increment behind a notice-then-error
rollout rather than a strict-from-day-one error check.

The gap has the same shape FC07 closed for the intra-document axis but
at a different altitude. A reader who trusts the diagram as a faithful
render of reality is led to the wrong picture of which work is done,
which is in flight, and which is unstarted. The friction the gap
exposes is not "build a GitHub client from scratch." Workspace
conventions for GitHub API integration already cover the cli + auth
surface this check would consume, and a graceful-degradation posture
for optional substrates already shapes how other cross-layer
dependencies behave when their substrate is missing. The unmet need is
a check whose contract crosses the offline boundary cleanly --
engaging on the doc's state claims when credentials and PR context are
available, and ceding that ground without breaking the rest of the
validator when they are not.

## Goals

1. **One reconciliation check covers three sub-dimensions.** FC09
   reconciles each plan or roadmap doc's claims about issue state
   against GitHub's actual issue state and against the current PR
   body's `Closes` lines in a single pass, structured as three
   sub-checks (doc-claims-done vs GitHub, doc-claims-open vs GitHub,
   PR `Closes` vs doc), dispatched in the plan and roadmap arms
   alongside FC05, FC06, FC07, and FC08.

2. **The check ships at notice level.** CI stays green on the present
   committed corpus while the corpus reconciles row by row, and a
   one-line change at the `is_notice` membership site promotes the
   check to error once the corpus is clean. The seam shape mirrors
   FC07 and FC08.

3. **Local-dev workflows do not break.** When credentials are absent,
   when the validator is invoked outside a PR context, when the
   running token exhausts its rate-limit budget, or when a cross-repo
   reference is inaccessible to the running token, FC09 self-disables
   the affected sub-surface with one targeted skip notice and the
   rest of the validator -- FC01 through FC08 -- proceeds normally.

4. **Per-defect messages name the specific fix site.** Each notice
   names the row, the diagram node, the claimed state, the observed
   state, and where applicable the PR body line that disagrees, in
   the FC05/FC06/FC07 voice the existing checks already use.

5. **Bounded behavior over arbitrary external input.** The check
   produces a result for any GitHub response without panicking on
   malformed JSON, missing fields, unexpected schemas, or unexpected
   status codes; the check produces a result without unbounded
   retries and without hangs; the credentials it consumes are never
   logged or echoed to its output.

6. **No new binary or parallel pipeline.** The check extends the
   existing `shirabe-validate` crate and runs through the existing
   CLI and reusable CI workflow alongside FC05, FC06, FC07, and FC08.

## User Stories

**As a plan author who marks a row done while GitHub still shows the
issue open**, I want the validator to surface a notice naming the row,
the diagram node, and GitHub's observed state, so that I see the
forward-direction defect on my PR before merge rather than after
someone else reads the wrong picture.

**As a maintainer who finds a row still classed `ready` for an issue
that closed weeks ago via a parallel PR**, I want the validator to
surface a notice naming the row, the node, the observed closed state,
and the expected `done` class, so that the stale-plan drift FC07
cannot see -- because FC07 only reconciles intra-document state and a
perfectly self-consistent stale doc passes its checks -- gets caught
the next time anyone edits the doc.

**As a PR author whose `Closes` line disagrees with the doc the PR
touches**, I want the validator to surface a notice naming the issue,
the PR body line, and the doc's claim, in either direction (the PR
under-claims a closure the doc anticipates, or the PR over-claims a
closure the doc still shows as ready), so that the PR-body-versus-doc
gap that neither pure issue-state sub-check catches on its own closes
before merge.

**As a doc author running the validator locally without
`GITHUB_TOKEN` and without `gh auth` configured**, I want FC09 to
self-disable with a single skip notice explaining the missing
credentials, and I want FC01 through FC08 to keep running normally, so
that my local edit cycle keeps working without forcing a `gh auth`
setup as a prerequisite for editing a plan.

**As a maintainer who watches the FC09 notice volume drop to zero
across the committed corpus**, I want a single-point seam at the
`is_notice` membership where flipping one line promotes FC09 from
notice to error in the same PR that finishes the cleanup, so that the
notice-then-error rollout has an executable end state and the corpus
gets a reliable contract once the cleanup is done.

**As a CI runner whose token has run out of rate-limit budget**, I
want FC09 to self-disable with one rate-limit skip notice after a
single retry with back-off rather than fail the build, so that a
transient throttle does not redden CI on docs whose actual content is
fine.

**As a doc author whose plan references an issue in a repo my running
token cannot read (a cross-repo `owner/repo#N` dependency)**, I want
FC09 to surface one per-row skip notice naming the inaccessible
reference and continue checking the rest of the doc, so that one
restricted cross-org dependency does not blank the whole check.

## Requirements

### Functional Requirements

**R1: Three sub-checks in one check.** FC09 reconciles each plan or
roadmap doc against external state in a single pass over the parsed
Table and the extracted Diagram, structured as three sub-checks:

- **Sub-check A (doc-claims-done vs GitHub).** For every diagram node
  assigned `done` whose corresponding table row is in a terminal
  state (strikethrough applied in the plan profile, or Status `Done`
  in the roadmap profile), FC09 fetches the issue's current state
  from GitHub and emits a notice when GitHub shows the issue still
  open.
- **Sub-check B (doc-claims-open vs GitHub).** For every diagram node
  assigned a non-`done` Status class (`ready` or `blocked`) whose
  corresponding table row is not in a terminal state, FC09 fetches
  the issue's current state and emits a notice when GitHub shows the
  issue closed.
- **Sub-check C (PR `Closes` vs doc).** When running in a PR context,
  FC09 fetches the PR body once, extracts every `Closes #N` line, and
  reconciles those lines against the doc's claims. A `Closes` line
  whose issue the doc still shows non-`done` fires a notice (PR
  over-claims). A `done`-claimed row whose issue is open on GitHub and
  whose number is not named in any `Closes` line on the current PR
  fires a notice (doc anticipates a closure no PR delivers).

The check is dispatched in the plan and roadmap arms of the validator's
file dispatcher, behind the same schema gate that gates FC05, FC06, and
FC07, and produces zero, one, or many notices per file depending on the
defects found.

**R2: Reconciling subset and class binding.** FC09 reconciles only
Status-bearing classes (`done`, `ready`, `blocked`) and only diagram
nodes whose id matches `^I[0-9]+$`. The pipeline-stage classes
(`needsDesign`, `needsPrd`, `needsSpike`, `needsDecision`,
`needsPlanning`, `needsExplore`, `tracksDesign`, `tracksPlan`) and the
custom-mnemonic external-node form (any id not matching `^I[0-9]+$`)
are excluded, matching FC07's reconciling subset. A roadmap-profile
row whose Issues cell is `None` contributes no expected node and
therefore no FC09 reconciliation. A doc whose Diagram or Table is
malformed enough that FC07 emits structural notices is reconciled by
FC09 only over the subset FC07 successfully extracted.

**R3: GitHub client surface as a trait.** The check consumes a stable
client surface that names the operations FC09 needs -- fetching the
state of a single issue identified by `(owner, repo, number)`, and
fetching the body of a single pull request identified by
`(owner, repo, number)` -- without binding the implementation to a
specific transport. The trait lives in its own module under
`crates/shirabe-validate/src/`, isolated from the check function, and
the check accepts it polymorphically. The choice between a `gh` CLI
subprocess and a raw HTTP client is deferred to the downstream
sub-DESIGN; this PRD binds the surface, not the transport.

**R4: Authentication via `GITHUB_TOKEN` or `gh auth status`.** FC09
authenticates GitHub requests via the `GITHUB_TOKEN` environment
variable when present. When the environment variable is absent but the
running shell has `gh auth status` configured, FC09 uses the
gh-configured token. When neither is available, the missing-credentials
self-disable path (R6) fires. The token is consumed by the client
surface only and is never logged, echoed to stdout, echoed to stderr,
or written to any notice body.

**R5: PR-context detection from environment.** FC09 detects PR context
from the environment that GitHub Actions sets on `pull_request` events:
`GITHUB_REPOSITORY` names the running repo, and `GITHUB_REF` of the
form `refs/pull/<N>/merge` carries the PR number. A dedicated
`SHIRABE_PR_NUMBER` override is also accepted for invocations outside
GitHub Actions. When PR context is detected, Sub-check C engages;
otherwise the missing-PR-context self-disable path (R7) fires for
Sub-check C only.

**R6: Self-disable -- missing credentials.** When no `GITHUB_TOKEN` is
set and no `gh` CLI is configured, FC09 self-disables in full and emits
a single skip notice naming the missing-credentials condition. FC01
through FC08 continue running. The check does not return an error and
does not contribute to a non-zero exit code; the validator's overall
behavior outside FC09 is unchanged.

**R7: Self-disable -- missing PR context.** When credentials are
present but PR context is not, Sub-check C self-disables and emits a
single skip notice naming the missing-PR-context condition. Sub-checks
A and B continue running (they are pure issue-state checks that do not
require a PR). A and B emit their own notices on real defects.

**R8: Self-disable -- rate-limit exhausted.** When the running token
exhausts its rate-limit budget, FC09 retries each affected request
once with a back-off, and on a second rate-limit response self-disables
the remainder of the check and emits a single skip notice naming the
rate-limit-exhausted condition. The notices already emitted for
defects found before the exhaustion remain in the output; the check
does not retroactively suppress them.

**R9: Self-disable -- cross-repo access denied.** When a Dependencies
cell carries a cross-repo `owner/repo#N` reference and the running
token returns 403 or 404 for that repo, FC09 emits one per-row skip
notice identifying the inaccessible cross-repo reference and
continues. Other rows in the same doc are reconciled normally. The
check does not attempt to discover or inject additional tokens for
cross-org access; the per-row skip is the contract.

**R10: Notice-level shipping via the existing `is_notice` membership.**
FC09 ships at notice level for v1: its code (`FC09`) is added to the
existing `is_notice` notice-membership function in the validator (the
same `matches!` arm-shaped match that holds `SCHEMA` and `FC07`).
Notice-level surfaced items do not contribute to the process exit
code, so a doc with FC09 defects produces output but exits 0. CI stays
green on the present committed corpus while the corpus reconciles row
by row.

**R11: Promotion-to-error seam at a single point of change.** The
promotion of FC09 from notice to error is a one-line change at the
`is_notice` membership site: removing the `FC09` arm from the
membership flips every FC09 surfaced item from notice to error. The
PRD's scope ships the seam -- the change site is real and locatable
in the source -- and excludes the flip itself, which lands in a
separate cleanup PR once the committed corpus is reconciled.

**R12: Per-defect notice messages in the FC05/FC06/FC07 voice.** Every
notice FC09 emits names the specific defect site the author has to
revisit. The form mirrors the existing FC05/FC06/FC07 notice voice:
prefix `[FC09]`, a description naming the entity (row key, diagram
node id, issue number, PR body line where applicable), and the
observed and expected state. Notices identify nodes by their diagram
id, not by a URL or external identifier. The four self-disable paths
each carry a per-path notice form so that maintainers reading CI
output can tell from the message which gap fired (missing credentials
versus missing PR context versus rate-limit exhaustion versus
per-row cross-repo access denial).

**R13: Sub-check C asymmetry.** Sub-check C fires in both directions
and the two directions emit distinct notice forms:

- **PR over-claims.** A `Closes #N` line in the current PR body whose
  issue the doc still shows non-`done` fires a notice naming the
  issue, the PR body line, and the doc's claim (the diagram class and
  the table state).
- **Doc anticipates a closure no PR delivers.** A `done`-claimed row
  whose issue is observed open on GitHub and whose number is not
  named in any `Closes` line on the current PR fires a notice naming
  the row, the diagram node, the observed open state, and the
  absence of the corresponding `Closes` line.

Both directions are emitted by Sub-check C and both are subject to
its missing-PR-context self-disable (R7).

**R14: Reconciling-subset behavior on inaccessible rows.** A row whose
issue cannot be fetched for a reason other than rate-limit exhaustion
or cross-repo denial -- for example, an unexpected HTTP 5xx response
or a malformed payload -- contributes no FC09 notice for that row and
the check proceeds with the remaining rows. The bounded-behavior
guarantee (R15) carries the totality contract for these cases.

### Non-Functional Requirements

**R15: Bounded behavior over arbitrary external input (SECURITY).**
FC09 and its client surface are total over arbitrary GitHub responses
and arbitrary environment-derived inputs. The check produces a result
for any input -- well-formed, malformed, or empty -- without index
panics, panics on UTF-8 boundaries, or unbounded loops. The
implementation introduces no nested loops over external response
content, no unbounded recursion, and no unbounded retries: every
external operation has an explicit timeout and a single retry on
recoverable failure, and the rate-limit self-disable (R8) bounds the
retry surface. The token is consumed by the client surface only; it
is never logged, echoed to stdout, echoed to stderr, or written to any
notice body.

**R16: Reuse of existing validation infrastructure.** FC09 extends
the existing `shirabe-validate` crate. It introduces no new binary, no
parallel pipeline, and no validation surface outside the existing
`shirabe validate` CLI and the existing reusable CI workflow. The
GitHub client surface is the only net-new module; the check function
joins `checks.rs` alongside FC05, FC06, FC07, and FC08, and the
`is_notice` extension is the only change to `validate.rs`. The choice
of transport-side dependencies (subprocess versus an HTTP client
crate) is the sub-DESIGN's; this requirement binds only that the
implementation lives inside the existing crate and runs through the
existing pipelines.

**R17: Public-visibility cleanliness of surfaced rules and messages.**
Every notice FC09 surfaces and every shared rule the check binds to
is public-repo clean: no private repo names, paths, filenames,
external issue numbers, or pre-announcement features appear in
notice bodies or rule prose. The four self-disable notice strings and
the per-defect reconciliation strings are written so that they
identify the defect by content (row key, diagram id, issue number
inferred from the doc, PR body line) without leaking environment
state. This re-states the parent PRD's R22 specifically scoped to
FC09.

## Acceptance Criteria

- [ ] Running `shirabe validate` on a plan or roadmap doc whose
  diagram has a node assigned `done` and whose corresponding table row
  is in a terminal state, when the actual GitHub issue is observed
  open, surfaces a single FC09 notice naming the row, the diagram
  node, and the observed open state (R1, R2).
- [ ] Running `shirabe validate` on a plan or roadmap doc whose
  diagram has a node assigned `done` and whose corresponding table row
  is in a terminal state, when the actual GitHub issue is observed
  closed, produces no FC09 notice for that row (R1, R2).
- [ ] Running `shirabe validate` on a plan or roadmap doc whose
  diagram has a node assigned `ready` or `blocked` and whose
  corresponding table row is open, when the actual GitHub issue is
  observed closed, surfaces a single FC09 notice naming the row, the
  diagram node, the observed closed state, and the expected `done`
  class (R1, R2).
- [ ] Running `shirabe validate` on a plan or roadmap doc whose
  diagram has a node assigned `ready` or `blocked` and whose
  corresponding table row is open, when the actual GitHub issue is
  observed open, produces no FC09 notice for that row (R1, R2).
- [ ] Running `shirabe validate` in a PR context where the PR body
  contains a `Closes` line for an issue the doc shows non-`done`
  surfaces a single FC09 notice naming the issue, the PR body line,
  and the doc's claim (R1, R13).
- [ ] Running `shirabe validate` in a PR context where the doc shows
  a row `done` whose issue is observed open and whose number is not
  named in any `Closes` line on the current PR surfaces a single FC09
  notice naming the row, the diagram node, the observed open state,
  and the absence of the corresponding `Closes` line (R1, R13).
- [ ] Running `shirabe validate` in a PR context where a `Closes`
  line names an issue the doc shows `done` and the actual GitHub
  issue is observed closed produces no Sub-check C notice for that
  row (R1, R13).
- [ ] A doc whose diagram has a node assigned a pipeline-stage class
  (`needsDesign`, `needsPrd`, `needsSpike`, `needsDecision`,
  `needsPlanning`, `needsExplore`, `tracksDesign`, `tracksPlan`)
  produces no FC09 notice for that node; FC09 reconciles only
  Status-bearing classes (R2).
- [ ] A doc whose diagram has a node whose id does not match
  `^I[0-9]+$` (a custom-mnemonic external reference) produces no FC09
  notice for that node; FC09 follows the same reconciling-subset rule
  as FC07 (R2).
- [ ] A roadmap-profile row whose Issues cell is `None` contributes
  no FC09 notice; FC09 has no expected GitHub state for rows that
  have not been decomposed into issues (R2).
- [ ] The GitHub client surface is declared as a trait in its own
  module under `crates/shirabe-validate/src/`; the check function
  accepts the trait polymorphically and contains no transport-specific
  code (R3).
- [ ] FC09 authenticates GitHub requests using `GITHUB_TOKEN` when
  set, falls back to a `gh auth status`-configured token when the
  environment variable is absent, and self-disables (R6) when neither
  is available (R4).
- [ ] FC09 detects PR context from `GITHUB_REPOSITORY` plus either
  `GITHUB_REF` (in the form `refs/pull/<N>/merge`) or a dedicated
  `SHIRABE_PR_NUMBER` override; when PR context is absent, only
  Sub-check C self-disables and Sub-checks A and B continue running
  (R5, R7).
- [ ] Running `shirabe validate` without `GITHUB_TOKEN` and without a
  configured `gh` CLI surfaces a single FC09 skip notice naming the
  missing-credentials condition; the process exits 0 and FC01 through
  FC08 produce their normal output (R6).
- [ ] Running `shirabe validate` with credentials but outside a PR
  context surfaces a single FC09 skip notice naming the
  missing-PR-context condition (Sub-check C only); Sub-checks A and B
  emit any reconciliation notices they find on real defects (R7).
- [ ] When the running token receives a rate-limit response, FC09
  retries the request once with a back-off; on a second rate-limit
  response FC09 self-disables the remainder of the check and emits a
  single skip notice naming the rate-limit-exhausted condition;
  notices already emitted before exhaustion remain in the output (R8).
- [ ] When a Dependencies cell carries a cross-repo `owner/repo#N`
  reference and the running token returns 403 or 404, FC09 emits one
  per-row skip notice naming the inaccessible cross-repo reference;
  other rows in the same doc are reconciled normally (R9).
- [ ] FC09's code (`FC09`) appears in the validator's `is_notice`
  notice-membership function; running `shirabe validate` against a
  doc with FC09 defects exits 0 (R10).
- [ ] The `is_notice` membership site contains exactly one point of
  change that flips FC09 from notice to error (removing the `FC09`
  arm from the membership), and that change is independently
  reviewable as a single-line diff (R11).
- [ ] Every FC09 notice begins with the prefix `[FC09]` and names
  the specific row key, diagram node id, issue number, or PR body
  line the defect applies to; the voice matches the existing
  FC05/FC06/FC07 notice form (R12).
- [ ] The four self-disable paths each emit a distinct,
  identifiable notice string (missing credentials, missing PR
  context, rate-limit exhausted, per-row cross-repo access denied)
  so that maintainers reading CI output can tell which gap fired
  (R12).
- [ ] Sub-check C emits a notice in the PR-over-claims direction
  when a `Closes` line names an issue the doc still shows non-`done`,
  and emits a distinct notice in the doc-anticipates-closure-no-PR
  direction when a `done`-claimed row has no matching `Closes` line
  and its issue is observed open (R13).
- [ ] A row whose issue cannot be fetched for a reason other than
  rate-limit exhaustion or cross-repo denial (for example an
  unexpected HTTP 5xx response or a malformed payload) contributes
  no FC09 notice for that row and the check proceeds with the
  remaining rows (R14).
- [ ] Running FC09 against arbitrary malformed GitHub responses
  (responses with missing fields, unexpected schemas, unexpected
  status codes, malformed JSON, or non-UTF-8 bodies) produces a
  result without an index panic, a UTF-8-boundary panic, or an
  unbounded loop (R15).
- [ ] Running FC09 with credentials present produces a result for any
  combination of inputs without unbounded retries; every external
  operation has an explicit timeout and at most a single retry on
  recoverable failure (R15).
- [ ] A scan of FC09's notice messages, the validator's process
  output (stdout and stderr), and any log surface produces no
  occurrence of the GitHub token value, with credentials present
  during the run (R15).
- [ ] FC09 ships as additions to the existing `shirabe-validate`
  crate -- one new module for the client surface, one new check
  function in `checks.rs`, and a one-line extension of `is_notice` in
  `validate.rs` -- with no new binary and no parallel pipeline (R16).
- [ ] A scan of FC09's notice message bodies and the surfaced FC09
  rule prose finds no private repo names, paths, filenames, external
  issue numbers, or pre-announcement features (R17).

## Out of Scope

This PRD scopes the FC09 reconciliation check and its GitHub client
surface. It explicitly excludes:

- **The actual promotion of FC09 to error-level.** Promotion is a
  one-line change at the `is_notice` membership site (R11), landed in
  a separate cleanup PR once the committed corpus is reconciled.
  This PRD ships the seam, not the flip. Same staging shape FC07 and
  FC08 ship behind.
- **A retrofit of the committed corpus.** The notice-then-error
  rollout exists precisely so the corpus reconciles incrementally
  after FC09 ships. Bulk-fixing the current corpus is out; an author
  who hits a notice fixes it in their own PR.
- **The choice between a `gh` CLI subprocess and a raw HTTP client.**
  Both transports are viable. The PRD binds the contract (auth,
  offline behavior, rate-limit tolerance, defensive parsing, no
  panics, token never logged, trait-shaped client surface) without
  pre-committing the transport. The downstream sub-DESIGN settles
  the choice with the trade-off analysis appropriate to a HOW
  decision; pulling that into the PRD would mix altitudes.
- **A general GitHub-API mock framework for the workspace.** The
  test-side mocking lives in-crate alongside FC09's own tests,
  matching the inline-string fixture pattern Decision 4 of the FC07
  sub-DESIGN settled. A future check needing a GitHub client surface
  can reuse the trait; promoting the test mocks to a shared utility
  is a separate decision a later increment owns.
- **Pipeline-stage class reconciliation against GitHub.** FC09 fires
  only on Status-bearing classes (`done`, `ready`, `blocked`). The
  pipeline-stage classes encode pre-binding upstream-artifact
  prerequisites with no corresponding GitHub issue-state semantics.
  FC09 ignores them, matching FC07's Decision 1 in the sub-DESIGN.
- **Cross-repo refs that the running token cannot access beyond a
  per-row skip.** When a Dependencies cell carries an `owner/repo#N`
  reference and the running token returns 403 or 404, FC09 emits one
  per-row skip notice and continues (R9). The scope does not extend
  to discovering or injecting additional tokens for cross-org access;
  that is an infrastructure decision outside this check's contract.
- **A general PR-context plumbing layer for the validator.** FC09
  reads the env vars it needs and detects PR context from them.
  Generalizing PR context into a shared validator runtime layer that
  future checks could consume is downstream work; FC09 is the first
  check to need any of this and its surface stays local until a
  second consumer appears.
- **Network-dependent behavior anywhere outside FC09.** FC01 through
  FC08 remain pure offline checks. The validator's default posture
  stays offline-first; FC09 is the singular network-dependent
  surface and self-disables cleanly when credentials or context are
  missing so the offline-first guarantee continues to hold for every
  other check.
- **An issue-tracker integration outside GitHub.** The check binds to
  GitHub. Other trackers (Jira, Linear) are not in scope; a future
  check could extend the trait to a multi-provider surface, but FC09
  is GitHub-only.

## Known Limitations

- **The first run after FC09 lands produces notice volume proportional
  to the corpus drift.** While the committed corpus carries
  unreconciled doc-versus-GitHub state, FC09 notices appear on every
  PR that touches a plan or roadmap. The signal degrades if authors
  learn to skim past FC09 output without reading it. The forcing
  function is the maintainer's cleanup PR; until then, FC09's value
  depends on authors treating notices as actionable signal rather
  than noise. Same posture FC07 ships with.

- **A rate-limit-exhausted run leaves the doc under-reconciled.**
  When FC09 self-disables on rate-limit exhaustion (R8), the rows
  not yet checked are not reconciled in that run. A subsequent run
  with a fresh budget catches the drift. This is a deliberate
  consequence of the bounded-retry posture; a more aggressive retry
  schedule would risk runaway budget consumption on CI.

- **A token without access to a cross-repo reference produces one
  per-row skip but no signal on whether the dependency's actual
  state is consistent.** R9's per-row skip notice tells the author
  the cross-repo reference is inaccessible, but it does not surface
  whether the doc's claim about that issue is correct or stale.
  Closing this gap would require infrastructure for cross-org access
  outside FC09's contract.

- **PR-context detection rests on environment variables CI sets.**
  When the validator runs in an environment that does not set the
  expected variables (a local invocation outside `pull_request`
  context, or a CI environment whose workflow does not expose
  `GITHUB_REF`), Sub-check C self-disables. A future increment could
  extend the detection surface (for example, parsing `git config
  branch.<current>.merge` for a local PR association), but the v1
  contract is the env-var surface only.

- **Sub-check C's `Closes` parser binds to the conventional form.**
  GitHub recognizes several closing-keyword forms (`closes`,
  `fixes`, `resolves`, with optional `#`-prefixed issue numbers and
  optional cross-repo `owner/repo#N` qualifiers). FC09 normalizes
  these to the same set FC07 already binds for the corpus subset.
  An unconventional closing form (for example a fully-qualified URL
  without one of the recognized keywords) is invisible to Sub-check
  C; this is the same posture the GitHub UI itself takes.

## Decisions and Trade-offs

### Decision 1: Three sub-checks in one check, not three checks

**Decision.** FC09 is a single check that produces zero, one, or many
notices across all three sub-dimensions in one pass (R1). The
implementation does not split into FC09/FC10/FC11 by sub-check.

**Alternatives considered.**

- *Split into one check per sub-dimension (FC09 doc-claims-done, FC10
  doc-claims-open, FC11 PR-Closes).* Rejected: every sub-check
  consumes the same client surface, every sub-check targets the same
  reconciling subset (R2 applies to all three), and every sub-check
  ships at the same notice level with the same promotion seam
  (R10/R11). Splitting would multiply dispatcher entries without
  separating concerns the BRIEF already proved are coupled.
- *Defer Sub-check C to a later increment.* Rejected: Sub-check C is
  the PR-body-versus-doc gap that neither A nor B catches on its own
  (a doc claim and a GH issue state can both be coherent while the
  current PR body disagrees with the doc, or vice versa). Shipping
  FC09 without C would leave the third gap the BRIEF names uncaught
  and force a second increment to cover the same client surface.

**Rationale.** One check, three sub-dimensions, one notice
membership, one promotion seam. The sub-checks are coupled by the
client surface (Sub-check C reuses the issue-state fetcher to verify
the open-on-GitHub side of the no-matching-Closes notice) and by the
reconciling-subset rule; coupling them in the dispatch matches the
implementation reality.

### Decision 2: Notice-level via existing `is_notice` membership, not a new staging mechanism

**Decision.** FC09 ships at notice level by joining the existing
`is_notice` membership the schema gate and FC07 already use (R10). The
promotion seam is removing `FC09` from that membership (R11).

**Alternatives considered.**

- *Introduce a new severity level between notice and error.*
  Rejected: the existing two-level system (notice/error) already
  supports the staged-rollout shape the parent PRD's R8/R20
  prescribe and that FC07 and FC08 already ride. Adding a third level
  would require dispatcher, message-format, and CI-exit-code changes
  for no functional gain on a check whose rollout shape is identical
  to its siblings.
- *Hard-gate FC09 behind a runtime flag that defaults off.* Rejected:
  a flag-gated check is invisible to PR authors and provides no
  forcing function for the cleanup phase. The notice-then-error
  rollout depends on FC09 being visible from day one so the corpus
  reconciles incrementally.

**Rationale.** The schema-gate / FC07 precedent is the right reuse:
it already implements the notice-then-promote pattern the parent PRD
sanctions, and FC09's mechanics are identical (membership in,
membership out). One seam, one mechanism. The seam is independently
reviewable as a one-line diff.

### Decision 3: Graceful self-disable on missing substrate, not hard-fail

**Decision.** Each of the four substrate-missing conditions
(no credentials, no PR context, rate-limit exhausted, per-row
cross-repo denied) self-disables the affected surface with one
targeted skip notice rather than failing the build or aborting the
remainder of FC01 through FC08 (R6 through R9).

**Alternatives considered.**

- *Fail the validator when no credentials are available.* Rejected:
  forcing every doc author to set up `gh auth` before editing a plan
  would block the local-dev workflow the BRIEF explicitly preserves.
  A check that breaks local-only work to gain external-truth signal
  has the cost-benefit inverted; the graceful self-disable surfaces
  the gap (the skip notice tells the author what's missing) without
  punishing the rest of the validator.
- *Pre-flight every external dependency at validator startup and
  refuse to engage FC09 unless every substrate is available.*
  Rejected: this collapses the four sub-surfaces into one all-or-
  nothing posture and prevents the partial-engagement cases the BRIEF
  names (credentials present but no PR context -- Subs A and B still
  catch real defects).

**Rationale.** The four self-disable paths are independent failure
modes with distinct fix paths (set a token, run inside a PR, wait for
the rate-limit window, request cross-org access). Per-path skip
notices give authors the signal to act on; per-surface self-disable
keeps the rest of the validator working. This matches the workspace's
established graceful-degradation posture for optional substrates.

### Decision 4: Client surface as a trait, transport deferred to sub-DESIGN

**Decision.** The GitHub client surface is declared as a trait whose
operations FC09 needs (`fetch_issue_state`, `fetch_pr_body`) without
binding the implementation (R3). The choice between a `gh` CLI
subprocess and a raw HTTP client is the sub-DESIGN's call.

**Alternatives considered.**

- *Pre-commit `gh` subprocess in the PRD.* Rejected: the BRIEF
  explicitly leaves the transport open and the issue body names
  both options as viable. Pre-committing in the PRD pulls a HOW
  decision into a WHAT-and-WHY altitude and forecloses the
  trade-off analysis the sub-DESIGN owes.
- *Pre-commit a raw HTTP client in the PRD.* Rejected for the same
  reason. Both transports satisfy R4 (auth via env or gh) and R15
  (bounded behavior); the deciding factors (runtime dependency on
  `gh`, dependency-tree size for the HTTP client, subprocess
  overhead) are sub-DESIGN concerns.

**Rationale.** The trait pins the surface FC09 needs and makes the
test-side mock straightforward (the implementation that returns canned
responses satisfies the same trait). Deferring transport gives the
sub-DESIGN the room to weigh the runtime-dependency / dependency-tree
trade-off against the testability question without re-litigating the
contract.

### Decision 5: Public-cleanliness re-stated as an FC09-scoped NFR

**Decision.** R17 re-states the parent PRD's R22 public-cleanliness
invariant specifically for FC09's notice messages and surfaced rules,
rather than relying solely on the parent's blanket clause.

**Alternatives considered.**

- *Rely on the parent PRD's R22 alone.* Rejected: notice messages
  and rule prose for FC09 will be written and edited by downstream
  implementers who may not consult the parent PRD. The four
  self-disable notices and the per-defect reconciliation strings are
  exactly the surface where environment state could leak (a
  malformed token-bearing URL accidentally echoed into a skip
  notice, for example). Re-stating the constraint at the
  FC09-specific layer makes the binding explicit at the layer where
  messages are authored.
- *Skip the public-cleanliness requirement entirely.* Rejected: the
  notice messages are visible in CI logs that may be world-readable.
  The constraint is real and needs a testable surface; an explicit
  NFR with an AC scan satisfies that.

**Rationale.** R17 is a small re-statement that costs nothing and
prevents a class of defect that would otherwise depend on the
implementer remembering the parent's R22. The AC scan over notice
bodies and the token-leak AC over the validator's process output
are the testable surfaces.

### Decision 6: Bounded behavior across the four self-disable paths binds totality, not best-effort

**Decision.** R15 binds FC09 and its client surface as total over
arbitrary GitHub responses and environment-derived inputs. The check
produces a result for every input without panics or unbounded loops;
every external operation has an explicit timeout and at most a
single retry on recoverable failure; the rate-limit self-disable
bounds the retry surface.

**Alternatives considered.**

- *Allow an unbounded retry schedule on transient failures.*
  Rejected: an unbounded retry surface is incompatible with CI's
  job-timeout budget and risks runaway token consumption when the
  remote returns a sticky 5xx. The single-retry-then-self-disable
  shape gives transient flakes one chance to resolve and then
  surfaces the gap.
- *Catch every panic at the check boundary and convert to a skip
  notice.* Rejected: panic catching is a foot-gun in Rust and would
  let defensive-parsing bugs hide. Total-by-construction parsing
  (R15) is the contract; the panic-free guarantee is verified by
  the AC scan over arbitrary malformed input, not by a panic-catch
  shield.

**Rationale.** Totality is what makes FC09 safe to ship as a notice
that runs on every PR. A check that crashed the validator on a
malformed GitHub response would be worse than no check at all; the
total-by-construction posture is the precondition for the
notice-level rollout to land without destabilizing the existing
checks.

## Downstream Artifacts

Forthcoming work flowing from this PRD:

- **A sub-DESIGN** that refines the parent
  `DESIGN-roadmap-plan-standardization.md` Decision 3 in light of the
  FC09 scope. The sub-DESIGN owns the transport choice (`gh`
  subprocess versus raw HTTP), the exact notice message strings, the
  specific timeout values, the test fixture mechanism (trait-mock
  versus recorded fixtures), the GitHub client module layout
  (`crates/shirabe-validate/src/gh.rs` or similar), and the
  `is_notice` extension wording.
- **A sub-PLAN** decomposing the FC09 increment into implementation
  issues -- the client module, the check function, the `is_notice`
  membership change, the four self-disable notices, the per-defect
  notice messages, the PR-context detection, and the test fixtures
  the design specifies.

## Related

- **Upstream brief:** `docs/briefs/BRIEF-doc-vs-github-state-reconciliation.md`.
- **Parent PRD** (R8 staged reconciliation, R20 no-day-one-breakage,
  R22 public-cleanliness): `docs/prds/PRD-roadmap-plan-standardization.md`.
- **Parent DESIGN** (Decision 3 staging the reconciliation increment
  behind a spike and a notice rollout):
  `docs/designs/DESIGN-roadmap-plan-standardization.md`.
- **Parent PLAN** (the row that schedules this increment):
  `docs/plans/PLAN-roadmap-plan-standardization.md`.
- **FC07 sub-PRD** (the requirements precedent FC09 mirrors in shape
  and AC density): `docs/prds/PRD-table-diagram-reconciliation.md`.
- **FC07 sub-DESIGN** (the architectural precedent for the
  class-versus-Status pass FC09 extends with `observed_state` from a
  GitHub client instead of `row.terminal`):
  `docs/designs/current/DESIGN-table-diagram-reconciliation.md`.
- **Canonical issues-table conventions** (the Status column for the
  roadmap profile, strikethrough-on-done for the plan profile, the
  cross-repo `owner/repo#N` form for Dependencies cells):
  `references/issues-table.md`.
- **Canonical dependency-diagram conventions** (the Status-class
  palette FC09 binds to, the pipeline-stage classes FC09 ignores, the
  custom-mnemonic external-node exclusion):
  `references/dependency-diagram.md`.
- **Validation precedents:** `crates/shirabe-validate/src/checks.rs`
  (FC05, FC06, FC07), `crates/shirabe-validate/src/validate.rs`
  (the dispatcher and the `is_notice` membership the FC09 code joins
  for v1).
