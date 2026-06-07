---
schema: prd/v1
status: Accepted
problem: |
  The work-on cascade transitions BRIEF/PRD/DESIGN and deletes the
  PLAN at the atomic finalization commit, but does not verify the
  PLAN's outline acceptance-criteria checkboxes. Authors can flip a
  PR ready-for-review with unticked outline ACs; the cascade still
  deletes the PLAN; the squash-merge erases the staleness from
  history. The checkbox discipline silently fails at the moment it
  should be enforced.
goals: |
  Wire AC-completeness verification into the work-on cascade so the
  PLAN cannot be deleted while any outline AC remains unticked. The
  check uses the lifecycle Lnn check-code family established by R17,
  surfaces error messages naming the specific PLAN path and open ACs,
  fires at both pre-probe and post-verify for symmetry, and provides
  a documented escape hatch (default off) for legitimately out-of-
  scope ACs.
upstream: docs/briefs/BRIEF-cascade-outline-ac-completeness.md
source_issue: 177
---

# PRD: cascade-outline-ac-completeness

## Status

Accepted

This PRD captures requirements for the third gap on the cascade-
discipline axis. The upstream BRIEF
(`BRIEF-cascade-outline-ac-completeness.md`) frames the feature; this
PRD pins the requirements contract; the downstream DESIGN settles the
implementation shape — specifically the pure-doc vs diff-aware
candidate-shape decision named in BRIEF Open Question 1.

## Problem Statement

The work-on cascade (`skills/work-on/scripts/run-cascade.sh`)
performs the atomic finalization commit at the draft -> ready
transition. At its pre-probe and post-verify points the cascade
invokes `shirabe validate --lifecycle-chain <PLAN-DOC> --strict` to
gate chain transitions on posture rules from R17. The lifecycle Lnn
family currently covers status-vs-posture mismatch (L01), orphan
docs (L02), upstream cycles (L03), missing chain members (L04), and
defensive parsing fallbacks (L05).

The lifecycle scan never reads the PLAN's per-outline acceptance
criteria. A PLAN's `## Implementation Issues` section enumerates per-
issue ACs as `- [ ]` checkboxes. An author flipping a PR to ready-
for-review with unticked outline ACs satisfies every chain-posture
rule and the cascade still deletes the PLAN, transitions BRIEF/PRD/
DESIGN to their terminal states, and the squash-merge erases the
staleness from history.

Concretely observed on PR #176: both `PLAN-lifecycle-draft-ready-
discipline.md` and `PLAN-skill-cascade-lifecycle-check.md` carried 58
unticked outline AC boxes at ready-for-review time. The work for
every outline IS committed on the branch — the boxes were stale
documentation. The cascade did not notice either way. The same blind
spot fires identically when the work is genuinely incomplete.

Two prior issues closed the two prior gaps on the same axis. #117
closed the gap where there was no whole-tree lifecycle check at all.
#175 (consolidated into PR #176) closed the gap where an author
could simply skip running the check from the agent prose. This PRD's
requirements close the third gap: the cascade satisfies every chain-
posture rule and still ships work whose promised ACs were never
ticked.

## Goals

Four goals frame the requirement set.

1. **Enforce outline-AC completeness at the cascade.** The cascade
   refuses the finalization commit while any outline AC checkbox
   remains unticked. The check is local to the working tree (no
   network dependencies); it operates on the PLAN doc the cascade
   already loads.

2. **Surface specific failure context.** Refusal messages name the
   specific PLAN path and each open AC's outline + text so the
   author knows exactly what to tick or descope. Aggregate failures
   list every offending AC, not just the first.

3. **Preserve pre/post symmetry.** The check fires at both the
   pre-probe and post-verify points, matching the existing lifecycle-
   posture pre/post symmetry from #117/#175. Divergence between the
   two points surfaces state-corruption rather than passing
   silently.

4. **Provide a documented escape hatch.** Legitimate cases (an AC
   satisfied by upstream work, an AC verifying inherited behavior)
   route through an explicit opt-out flag rather than degraded
   default strictness. The flag's use is visible to reviewers; the
   escape preserves author agency without weakening the default.

## User Stories

- **As a multi-pr plan author**, I want the cascade to refuse PLAN
  deletion when my outline ACs are unticked, so my own checklist
  becomes a forcing function rather than aspirational documentation.

- **As a reviewer of a chain-completion PR**, I want the cascade's
  output to evidence that the AC checklist was respected (every
  box ticked, or the escape hatch invoked with a reviewable
  signal), so I can challenge gaps quickly instead of auditing
  every PLAN manually.

- **As an author with an AC satisfied by upstream work**, I want a
  documented escape hatch so I can finalize the chain without
  bypassing the lifecycle-posture checks the rest of the cascade
  performs.

- **As a maintainer of the cascade discipline**, I want post-verify
  to re-run the AC check defensively so silent drift between pre-
  probe and the cascade body is caught rather than absorbed.

- **As a maintainer of the lifecycle check-code family**, I want
  the new failure to share the Lnn namespace established by R17 so
  downstream consumers grep one prefix instead of two.

## Requirements

### Functional Requirements

**R1: AC-completeness check at the cascade pre-probe.** The cascade
pre-probe loads the chain's PLAN, parses the `## Implementation
Issues` section, enumerates every `- [ ]` checkbox under each
outline, and refuses to proceed past pre-probe if any checkbox
remains unticked. The check runs after the existing chain-posture
check (L01) and before the cascade body.

**R2: Specific failure context in error output.** When R1 fires, the
error output names (a) the specific PLAN path; (b) each open AC's
outline identifier (the `### Issue N` heading or equivalent
canonical identifier); (c) the AC's checkbox-line text verbatim.
Aggregate failures list every offending AC in a single output, not
a first-failure-only halt.

**R3: AC-completeness check at the cascade post-verify.** The
cascade's post-verify hook re-runs the AC-completeness check
defensively after the cascade body executes. Divergence between
pre-probe outcome and post-verify outcome surfaces as a distinct
error class indicating state corruption, not a silent absorption.

**R4: Escape-hatch flag (default off).** A documented opt-out flag
suppresses the AC-completeness gate but runs every other lifecycle
and content check. The flag's default is OFF; the author opts in
explicitly per invocation. The flag's exact name and scoping (per-
PLAN vs per-cascade-invocation, with-reason-string vs flag-only) is
settled by the DESIGN.

**R5: Lnn check code in the existing lifecycle family.** The new
check fires under a code in the `Lnn` namespace established by R17
of `PRD-roadmap-plan-standardization.md`. The DESIGN confirms the
next free code (L06 is the plausible default; L01-L05 are claimed by
upstream cycles, missing chain members, and defensive parsing
fallbacks).

**R6: Test coverage spans the permutations.** Tests cover (a) all-
ticked PLANs pass; (b) any-unticked PLAN fails with the new Lnn
code; (c) the escape-hatch flag overrides the gate while leaving
every other check active; (d) mixed-PLAN trees report on every
offending PLAN, not just the first.

**R7: Implementation shape — open between two candidates.** Two
candidate shapes are real alternatives. (a) **Pure-doc AC-
completeness check**: parse the PLAN's checkbox lines, count
unticked ones, refuse on any. Strictly textual; no diff inspection;
no symbol parsing. Simple, sufficient as a discipline-forcing
function. (b) **Diff-aware AC verification**: parse ACs that name
files or symbols, read the diff between the chain's base and HEAD,
and verify the named entities are touched by the PR. Stronger
because it ties the box-tick to evidence in the diff; heavier
because it requires symbol-naming conventions and a parser
resolving "the `parse_outlines` function in
`crates/shirabe-validate/src/table.rs`" to a diff hunk. The DESIGN
picks one against the cost/value trade-off and the parser tolerance
question (R8).

**R8: Parser tolerance for AC formatting variants.** The DESIGN
settles tolerance for indented continuation lines, nested
checkboxes, ACs written as bare sentences without `- [ ]` syntax,
and ACs spanning multiple paragraphs. A strict parser forces
authors to use the canonical shape; a permissive parser accepts
the variants already in the corpus.

### Non-Functional Requirements

**R9: No new external dependencies.** The check reuses the existing
cascade surface (bash + `shirabe validate` binary). No new
language runtime, no new library, no new subprocess beyond what the
cascade already invokes. If the parser lives in the validator crate
for code reuse, the DESIGN confirms.

**R10: Bounded wall-clock cost.** The check runs in the existing
pre-probe budget without significantly extending wall-clock time.
The parser is doc-local; reading and parsing a single PLAN is O(n)
in its line count.

**R11: Preserves the cascade contract.** The cascade script remains
the single source of truth for pre/post verification, per
`DECISION-cascade-trigger-mechanism-2026-06-06.md`. The AC check
lands there, not in a parallel script or external CI step.

**R12: Public-visibility content.** This is a public-repo feature.
The PRD, BRIEF, DESIGN, and PLAN never reference private repos,
private paths, or pre-announcement features.

## Acceptance Criteria

- [ ] The cascade's pre-probe step parses the PLAN's
  `## Implementation Issues` section and refuses the finalization
  commit when any `- [ ]` checkbox remains unticked.
- [ ] Error output from R1's refusal names the specific PLAN path
  and every open AC's outline identifier + verbatim checkbox text.
- [ ] The cascade's post-verify step re-runs the AC-completeness
  check; a pre-probe pass + post-verify fail produces a distinct
  state-corruption-class error.
- [ ] The escape-hatch flag (name set by DESIGN) suppresses the AC-
  completeness gate when explicitly invoked; all other lifecycle
  and content checks remain active under the flag.
- [ ] The new check fires under a code in the `Lnn` namespace; the
  code number is confirmed against the live validator surface at
  DESIGN time.
- [ ] Tests cover: all-ticked passes; any-unticked fails with the
  new code; the escape hatch overrides; mixed-chain trees report
  per-PLAN.
- [ ] The check runs without any new external dependency beyond the
  existing cascade surface.
- [ ] No private-repo references appear anywhere in the BRIEF,
  PRD, DESIGN, or PLAN.

## Out of Scope

- **Validator-level FCnn content changes.** AC-completeness is a
  cascade-side property. Although the parser may live in the
  validator crate for code reuse, the firing surface is the
  cascade script, not `shirabe validate`'s per-doc changed-files
  mode.
- **Changes to the lifecycle posture-detection model.** The check
  layers on top of #117/#175/#176, not a replacement. The chain-
  targeted `--lifecycle-chain` mode and the cascade's pre/post
  hooks are the primitives this PRD extends.
- **Network-dependent verification.** Verifying that ACs match
  GitHub-tracked sub-issue state, PR-comment mentions, or any
  external review surface is OUT. The check is local to the
  working tree.
- **AC quality verification.** The check verifies AC checkboxes
  are ticked, not that the ACs themselves are well-formed. ACs
  missing from the PLAN are not surfaced by this check; that is
  a separate concern owned by upstream BRIEF/PRD/DESIGN
  discipline.
- **The candidate-shape decision (R7).** Deferred to DESIGN per
  the BRIEF's Open Question 1. The PRD names the alternatives but
  does not pick.

## Known Limitations

- **The escape hatch is a documented bypass.** It preserves author
  agency at the cost of creating a surface a reviewer must police.
  Without reviewer discipline an author can use the hatch
  routinely and reduce the check to advisory. The PRD accepts this
  trade-off; the alternative (no hatch) would block legitimate
  cases where ACs verify inherited behavior.

- **Pure-doc shape (R7a) has a false-negative dimension.** An AC
  checkbox can be ticked without the corresponding work being in
  the diff — the box-tick is the author's claim, not evidence. The
  diff-aware shape (R7b) closes this gap but at heavier
  implementation cost. The DESIGN weighs the cost against the
  marginal value.

- **Parser tolerance is a tradeoff axis.** A strict parser breaks
  on already-committed PLANs whose ACs use minor format variants;
  a permissive parser absorbs noise and may silently pass an AC
  the strict parser would reject. The DESIGN picks the balance.

## Decisions and Trade-offs

### Decision 1: AC-completeness lives in the cascade script

**Decision.** The AC-completeness check fires from the cascade
script (`skills/work-on/scripts/run-cascade.sh`), not from a
parallel validator-only CI job or an external pre-merge hook.

**Why.** `DECISION-cascade-trigger-mechanism-2026-06-06.md`
establishes the cascade script as the single source of truth for
pre/post verification. AC-completeness extends the cascade's
discipline, not a separate surface.

**Trade-off.** A validator-only firing surface would let
`shirabe validate --strict` produce the same error in agent and CI
contexts. The cascade-script choice means the check fires only
when the cascade runs (which is by design — AC-completeness is a
chain-finalization concern, not a content-validation concern).

### Decision 2: Candidate-shape choice deferred to DESIGN

**Decision.** The pure-doc vs diff-aware shape decision is
explicitly deferred to the downstream DESIGN doc.

**Why.** The trade-off is implementation-cost vs verification-
strength. The two shapes have different parser surfaces, different
test surfaces, and different failure modes. The DESIGN walks the
trade-off with a decision researcher's eye (per the parent
skill's R6 P1 firing).

**Trade-off.** Pinning the shape at PRD time would close the
DESIGN gate before the implementation cost is well-understood.
Deferring means the PRD's R7 stays open as an alternative until
DESIGN settles.

### Decision 3: New Lnn code, not a new namespace

**Decision.** The new check joins the existing `Lnn` lifecycle
check-code family established by R17 of
`PRD-roadmap-plan-standardization.md`.

**Why.** AC-completeness is a lifecycle property (the cascade is
the lifecycle's discipline-bearing surface). Adding a new
namespace would force downstream consumers to grep two prefixes
where one suffices.

**Trade-off.** The Lnn family currently covers chain-posture
checks; AC-completeness is the first work-completeness check in
the family. The DESIGN confirms the code number stays in the L01-
Lnn range without colliding (L06 is the plausible default).

## Downstream Artifacts

- **`DESIGN-cascade-outline-ac-completeness.md`** — implementation
  shape: which of R7's two candidates the work takes, the
  parser's location (validator crate vs cascade-script-local) and
  tolerance, the exact Lnn code number, the escape-hatch flag's
  name and scoping, the cascade script integration points. Lives
  in `docs/designs/`. (planned)
- **`PLAN-cascade-outline-ac-completeness.md`** — implementation
  issues decomposing the DESIGN into atomic work items. Lives in
  `docs/plans/`. (planned)

## Related

- `docs/briefs/BRIEF-cascade-outline-ac-completeness.md` —
  upstream brief.
- `docs/plans/PLAN-roadmap-plan-standardization.md` — parent
  PLAN with this work as the last open row (#177).
- `docs/prds/PRD-roadmap-plan-standardization.md` R17/R18 — the
  `Lnn` family and verified-deletion-as-human-act framing this
  PRD extends.
- `docs/designs/DESIGN-roadmap-plan-standardization.md` Decision
  5 — the cascade pre/post hooks the AC check plugs into.
- `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md`
  — single-source-of-truth cascade contract.
- `docs/decisions/DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06.md`
  — the `--lifecycle-chain` flag.
- Issues #117, #175, and the consolidated PR #176 — the prior two
  gaps this PRD's work closes the third of.
