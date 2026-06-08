---
schema: brief/v1
status: Done
problem: |
  The work-on cascade performs the atomic finalization commit at the
  draft -> ready transition — deletes the PLAN, transitions BRIEF/PRD
  to Done, promotes DESIGN to Current — but does not verify that the
  PLAN's outline acceptance criteria are ticked. An author can flip
  a PR ready-for-review with unticked outline ACs; the cascade still
  deletes the PLAN; the squash-merge erases the staleness from history.
outcome: |
  An author finishing a multi-pr plan knows the cascade refuses to
  delete the PLAN until every outline AC box is ticked off. The
  discipline the checkbox encodes — "the thing this AC names has been
  done" — is enforced at the moment of finalization, not silently lost.
upstream: docs/plans/PLAN-roadmap-plan-standardization.md
---

# BRIEF: cascade-outline-ac-completeness

## Status

Done

This brief frames a leaf feature on the parent PLAN
`PLAN-roadmap-plan-standardization.md` (the last open row, #177).
Two upstream gaps are already closed on the same discipline axis:
PR #117 added a whole-tree `--lifecycle` mode + CI gate, and PR #175
(consolidated with #117 in PR #176) baked a chain-targeted lifecycle
check into the work-on cascade. This brief frames the third gap on
that axis: an author can satisfy every chain-posture rule and still
ship work whose own promised acceptance criteria were never ticked.

The downstream PRD (`PRD-cascade-outline-ac-completeness.md`) owns the
requirements; the design after it owns the implementation specifics —
the exact Lnn check code number, the parser's tolerance for AC
formatting variants, and which of the two candidate shapes the work
takes (pure-doc check vs diff-aware verification).

## Problem Statement

The work-on cascade
(`skills/work-on/scripts/run-cascade.sh`) performs the atomic
finalization commit at the draft -> ready transition: it deletes the
PLAN, transitions the BRIEF/PRD to Done, and promotes the DESIGN to
Current. At its pre-probe and post-verify points it invokes
`shirabe validate --lifecycle-chain <PLAN-DOC> --strict` to gate the
transition on chain posture. What the cascade does NOT check is that
the work the PLAN actually promised has been done.

A PLAN's `## Implementation Issues` section enumerates per-issue
acceptance criteria as `- [ ]` checkboxes. The cascade today reads
none of them. An author can flip a PR from draft to ready with
outline ACs unticked. The cascade still passes pre-probe (every
chain-posture rule is satisfied), still deletes the PLAN, still
transitions the BRIEF/PRD/DESIGN, and the squash-merge then erases
the staleness from history. The discipline the AC checkboxes are
supposed to encode is silently lost at exactly the moment it should
be enforced.

The gap is concretely observable on PR #176 itself: both of that
PR's PLANs (`PLAN-lifecycle-draft-ready-discipline.md` and
`PLAN-skill-cascade-lifecycle-check.md`) carried 58 unticked outline
AC boxes at ready-for-review time. In that case every outline's
implementation IS committed on the branch — the boxes were stale
documentation. The cascade did not notice either way. The same blind
spot fires identically when the work is genuinely incomplete.

Two prior issues closed the two prior gaps on the same discipline
axis. #117 closed the gap where there was no whole-tree lifecycle
check at all. #175 (consolidated into PR #176) closed the gap where
a workflow author could simply skip running the check from the agent
prose. This is the third gap: an author can run the check, satisfy
every chain-posture rule, and still ship work whose promised
acceptance criteria were never ticked off. Without an AC-completeness
gate the cascade does the deletion mechanics correctly but performs
no verification of the work itself — it is a posture-only validator,
not a completeness validator.

## User Outcome

An author finishing a multi-pr plan trusts that the cascade will not
let the PLAN be deleted unless every outline AC checkbox is ticked.
When the boxes are stale documentation the author updates the
checkboxes before the cascade runs; when the boxes are unticked
because the work is genuinely incomplete the cascade refuses, names
the specific PLAN path and the specific outline-and-AC-text
combinations still open, and the author either implements the
remaining work or descopes the AC explicitly.

A reviewer reading a chain-completion PR sees the cascade's pre-probe
output and reads it as evidence the AC checklist was respected —
either every box was ticked, or the author used the explicit escape
hatch and the use of that hatch is part of the PR's reviewable
surface. The cascade's pre/post symmetry already established by
PR #176 extends to AC completeness: the post-cascade verification
also re-runs the AC check defensively.

The lifecycle-check family's `Lnn` namespace gains one more code
naming the AC-completeness failure mode. The cascade's behavior
remains a single source of truth for pre/post verification (the
contract from `DECISION-cascade-trigger-mechanism-2026-06-06.md`).
Repos that depend on the shirabe plugin's `/work-on` cascade get
deterministic AC-completeness enforcement on every cascade run, the
same way they got deterministic lifecycle enforcement from #175.

## User Journeys

Four journeys exercise the AC-completeness check from different entry
points. Each names the author, the trigger, and the outcome shape.

### Journey 1: Stale checkboxes, work actually done

An author finishes a multi-pr plan. The implementation for every
outline AC IS committed on the branch, but the author neglected to
tick the boxes in the PLAN. They flip the PR to ready-for-review.
The cascade's pre-probe runs the AC-completeness check, finds the
unticked boxes, and refuses to proceed. The error names the specific
PLAN path and lists the specific outline-and-AC-text combinations
that remain unticked. The author ticks the boxes in a single commit,
pushes, and the cascade now proceeds.

This journey validates that the check catches the most common form
of the gap — stale documentation drift — without false negatives.

### Journey 2: Genuinely incomplete work

An author flips a PR to ready-for-review while one or more outline
ACs are unticked because the corresponding work isn't done yet. The
cascade refuses; the error names the open AC text. The author either
implements the remaining work and ticks the boxes (resuming as
Journey 1), or explicitly descopes the AC by editing the PLAN to
remove it (with the edit visible in the diff and reviewable).

This journey validates that the check is a real discipline-forcing
function, not just a documentation-hygiene check. The cascade's
refusal is what makes the author either finish or descope rather
than silently ship incomplete work.

### Journey 3: Legitimately out-of-scope AC

An author finishes work where one of the PLAN's outline ACs is
satisfied by upstream work not in this PR (a dependency landed
earlier; an AC verifies behavior the chain inherits). The author
invokes the cascade with an explicit escape-hatch flag whose name
the PRD/DESIGN settles. The flag's use suppresses the AC-completeness
gate but still runs every other lifecycle and content check. The
escape's use is visible in the PR's reviewable surface (cascade
invocation in the workflow or commit history), so a reviewer can
challenge the use.

This journey validates that the check has a documented escape that
does not bypass the rest of the cascade and that the escape's use
is itself a reviewable signal.

### Journey 4: Post-verify defensive re-run

After the cascade's body executes (PLAN deleted, BRIEF/PRD
transitioned, DESIGN promoted), the post-verify hook re-runs the
AC-completeness check defensively as part of the existing post-
verify symmetry. Mirrors the existing lifecycle-posture pre/post
shape established by PR #176. A divergence between pre-probe and
post-verify outcomes signals a state-corruption defect to debug
rather than a quiet pass.

This journey validates that AC-completeness is treated as a load-
bearing chain property the post-verify also asserts, not a pre-
gate the cascade body can drift past.

## Scope Boundary

This brief, and the downstream PRD it points at, cover wiring AC-
completeness verification into the work-on cascade and the chain-
targeted lifecycle CLI mode the cascade already invokes. The scope
holds the following inside:

- **AC-completeness check at the cascade pre-probe and post-verify
  points.** Parses the PLAN's `## Implementation Issues` section,
  enumerates every `- [ ]` checkbox under each outline, and refuses
  to proceed past pre-probe if any remain unticked. Post-verify
  re-runs the check defensively per the existing pre/post symmetry.
  The exact Lnn check code number, error-message wording, and
  parser tolerance for formatting variants are the downstream
  PRD/DESIGN's.
- **An escape-hatch flag.** A documented opt-out for legitimate cases
  where an AC is satisfied by upstream work not in this PR. The
  flag's name, exact semantics, and whether it is per-PLAN or per-
  cascade-invocation are the PRD's.
- **Test coverage spanning the permutations.** All-ticked passes;
  any-unticked fails with the new code; the escape hatch overrides;
  mixed-chain PLANs (one chain clean, one chain dirty) report on
  both.

The scope explicitly excludes:

- **The implementation shape choice.** Two candidate shapes are
  named in #177 — a pure-doc AC-completeness check (textual; counts
  unticked boxes) and a diff-aware AC verification (parses ACs that
  name files or symbols, reads the diff between the chain's base
  and HEAD, and verifies the named entities are actually touched).
  Which shape the work takes is the DESIGN's call to make against
  the cost/value trade-off the issue body names; the brief frames
  the goal, not the mechanism.
- **Changing the lifecycle posture model.** The check is layered
  ON TOP of the existing posture-detection in #117/#175/#176, not a
  replacement. The chain-targeted `--lifecycle-chain` mode and the
  cascade's pre/post hooks are the primitives this brief extends.
- **Validator-level changes to FCnn content checks.** AC-completeness
  is a cascade-side property, not a content-validation property.
  Although the parser may live in the validator crate for code
  reuse, the firing surface is the cascade, not `shirabe validate`'s
  per-doc changed-files mode. The DESIGN settles where the parser
  lives.
- **Network-dependent verification.** Verifying that ACs match
  GitHub-tracked sub-issue state, that PR comments mention each AC,
  or that any external review surface has been engaged is OUT.
  The cascade is local to the working tree.

## Open Questions

These surface for the downstream PRD to resolve. None block this
brief.

1. **Which of the two candidate shapes the work takes.** The pure-
   doc check is a discipline-forcing function — it makes the author
   stand behind their own checklist. The diff-aware check is real-
   correctness verification — it ties the checklist to the diff. The
   PRD weighs whether the marginal value of (2) justifies the
   implementation cost, given that (1) already closes the gap this
   brief names. The DESIGN finalizes the chosen shape's parser.

2. **The exact Lnn check code number.** `L01` through `L05` are
   taken (upstream cycles, missing chain members, defensive parsing
   fallbacks). The next free code in the family — `L06` is the
   plausible default — needs confirmation against PR #176's surface
   at design time.

3. **The escape-hatch flag name and semantics.** `--allow-untracked-
   acs` is the working name from #177. Whether the flag accepts a
   list of AC identifiers to skip, accepts none and globally skips,
   or requires a reason string, is the PRD's call.

4. **Parser tolerance for AC formatting variants.** Indented
   continuation lines, nested checkboxes, ACs written as bare
   sentences without `- [ ]` syntax — the parser's permissiveness
   versus strictness is the DESIGN's settle. A strict parser
   forces authors to use the canonical shape; a permissive parser
   accepts the variants already in the corpus.

## Downstream Artifacts

- **`PRD-cascade-outline-ac-completeness.md`** — requirements
  articulation: the AC-completeness firing surface, the escape-
  hatch's semantics, the parser scope, the Lnn code's family
  membership. Lives in `docs/prds/`. (planned)
- **`DESIGN-cascade-outline-ac-completeness.md`** — implementation
  shape: which candidate shape the work takes, the parser's
  location and tolerance, the exact Lnn code number, the cascade
  script integration points. Lives in `docs/designs/`. (planned)

## References

- Parent PLAN: `docs/plans/PLAN-roadmap-plan-standardization.md` —
  carries #177 as the last open row, names the discipline gap this
  brief addresses.
- Parent PRD R17/R18: `docs/prds/PRD-roadmap-plan-standardization.md`
  — R17 defines the `Lnn` lifecycle check-code family the new code
  joins; R18 names verified-deletion as a human act CI never
  performs but demands indirectly. AC-completeness extends R18's
  posture to the work-completeness dimension.
- Parent DESIGN Decision 5:
  `docs/designs/DESIGN-roadmap-plan-standardization.md` — the
  whole-tree `--lifecycle` mode and the cascade pre/post hooks the
  AC check plugs into.
- Cascade contract decision:
  `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md`
  — the cascade script is the single source of truth for pre/post
  verification; AC check lands there.
- Chain-targeted CLI shape decision:
  `docs/decisions/DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06.md`
  — defines the `--lifecycle-chain` flag the AC check plugs into.
- Issues #117 and #175 — the prior two gaps on the same discipline
  axis this brief closes.
- `skills/work-on/scripts/run-cascade.sh` — the file the AC check
  lands in.
- Brief structural precedent:
  `docs/briefs/BRIEF-single-pr-plan-validation.md`.
- Brief format reference: `skills/brief/references/brief-format.md`.
