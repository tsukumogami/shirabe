---
schema: design/v1
status: Current
upstream: docs/prds/PRD-plan-preflight-one-validator.md
problem: |
  Two implementations answer "may a PLAN be built from this" and contradict
  each other on upstream status, and the surviving one exits 0 for inputs it
  never examined. The silence is what keeps the duplicate alive: the bash
  script is the only thing failing a PLAN with a missing or wrong `schema:`,
  and it holds that job because the CLI declines those inputs quietly.
decision: |
  `shirabe validate` gains a fourth run outcome, Incomplete, at exit code 4,
  ranked below violations and above clean, emitted when an input was routed to
  a format but not structurally checked. The SCHEMA finding's own severity does
  not change, so annotation bytes and the notice classification stay as they
  are. A `--lifecycle` root with no artifact directory beneath it becomes a
  tool error. R6 absorbs the script's symlink and tree-containment refusals.
  The script and its suite are then deleted and their callers re-pointed at the
  CLI, with the lifecycle model's upstream-status rule surviving.
rationale: |
  The exit code is the only surface every consumer reads — `validate-docs.yml`
  says so in its own comments — so a JSON field alone cannot carry the signal
  and a strictness flag would leave the default silent, which is the defect.
  Reporting the skip as an incomplete run rather than as a violation says the
  true thing about 32 committed documents: they were not checked, which is not
  the same claim as that they are defective, and it keeps a 22-error corpus
  repair out of this change.
motivating_context: |
  A prose-reference-staleness chain is planned against the same
  `crates/shirabe-validate` files and nothing is implementing it yet. This
  change is sized to land inside that window.
---

# DESIGN: One validator for whether a PLAN may be built from

## Status

Current

Technical approach for issues #276 and #285, written from
`docs/prds/PRD-plan-preflight-one-validator.md`.

## Context and Problem Statement

`skills/plan/scripts/validate-plan.sh` is a 298-line bash pre-flight validator
for PLAN documents. `docs/designs/current/DESIGN-gha-doc-validation.md` — the
design that built the CLI validator — names it as the thing being replaced, and
then scopes one job out of v1:

> **`checkPlanUpstream` scope (v1):** This check verifies (1) the `upstream`
> file exists on disk and (2) is tracked by `git ls-files HEAD` in the caller's
> repo. It does not check the upstream document's status... The existing
> `validate-plan.sh` performs that third check; it is intentionally out of scope
> for v1.

The gap was later filled from the other side, by the lifecycle posture model's
L01 check, and nobody returned to retire the script. So two implementations now
answer the same question and give opposite answers on two of the four statuses a
DESIGN can hold.

The mechanics of the disagreement are in the code. The script's non-ROADMAP
branch accepts `Accepted` and `Planned` and rejects everything else. The
lifecycle model resolves `(Design, SinglePrMidPR)` to `DesignPlannedOrCurrent`
in `compute_passing_state`, which accepts `Planned` and `Current` and rejects
everything else. The overlap is `Planned`; the two ends diverge.

The second defect is in `validate_structural`. When `check_schema` fires, the
function returns the single SCHEMA finding and runs nothing else. `SCHEMA` is in
`is_intrinsic_notice`, so `is_notice` resolves it to a notice under either
posture, and the exit-code roll-up in `main.rs` only merges `Violations` for
non-notice findings. The result is exit 0 for a document that was routed to a
format and then not checked against it. The mirror case is in
`build_doc_index`, which walks six fixed subdirectories beneath the
`--lifecycle` root and silently skips each one that does not exist — so a root
with no `docs/` under it produces an empty index and a clean report.

The two are joined. The script's `schema` gate is the only thing failing a PLAN
whose `schema:` is missing or holds `plan/v2` — verified: the script exits 2 for
both, `shirabe validate` exits 0 for both. It holds that job precisely because
the CLI declines those inputs silently. Removing the script first opens a hole
rather than closing one.

## Decision Drivers

**D1.** The declined-input signal has to reach a consumer that reads only the
exit code. `validate-docs.yml` documents that contract in its own comments:
it "reads the exit code as a zero/non-zero pass-fail gate".

**D2.** Exit codes 0, 1, 2 and 3 are already allocated, and the allocation is a
contract shared with `transition` and `finalize-chain`
(`docs/guides/multi-consumer-cli-contract.md`). Code 3 is I/O; the
`ValidateOutcome::Io` variant exists and is deliberately unused by `validate`
"to complete the shared contract". A new outcome cannot reuse a taken code.

**D3.** The change must not assert that 32 committed documents are defective.
What is known about them is that they were never checked. Adding their `schema:`
field surfaces 22 further errors — measured, tree goes from 7 to 29 — and
repairing those is a different project.

**D4.** No existing test may be modified. Where that cannot hold, the exception
is reported rather than absorbed.

**D5.** The scope ceiling is the script's own surface. The script checked
existence, git tracking, symlink-ness, tree containment, and status. Nothing
beyond that set is added to the CLI.

**D6.** The ordering is fixed by the hole: close the silence, then remove the
duplicate.

## Considered Options

### Option 1: Promote the SCHEMA finding to error severity

Remove `SCHEMA` from `is_intrinsic_notice`. A schema-less document then produces
an error-severity finding and the run exits 2.

This is the smallest diff and it satisfies D1 directly. It fails D3: it says 32
committed documents are defective, which is a claim about their content that the
tool has not earned — it never read them. It also changes the annotation output
for those documents from `::notice` to `::error`, which moves three golden
parity baselines' stdout as well as their exit, widening the test exception
under D4 rather than narrowing it.

The deeper objection is that it collapses two different facts into one signal. A
document with a wrong `## Status` body is defective. A document the tool could
not route is unexamined. Both would report identically.

### Option 2: Carry the signal in the JSON envelope only

Add a `skipped` array to the `shirabe-validate/v1` envelope naming each declined
input, and leave the exit code alone.

Rejected on D1. The consumer that most needs the signal — the reusable
validation workflow — does not parse the envelope at all; it uses the default
annotation format and branches on zero versus non-zero. A signal that requires
a JSON parse to observe is invisible to it, and adding a parse step to every
consumer to carry one bit is a worse contract than a fourth exit value.

The envelope field is worth having, and it is kept. It is kept as diagnosis
alongside the exit code, not instead of it.

### Option 3: A strictness flag callers opt into

Add `--require-schema` (or similar). Callers that care — the PLAN pre-flight in
`check-plan-docs.yml`, `/plan`'s phase 7 — pass it; the corpus-wide run does not.

This has a genuine advantage: the corpus effect is exactly zero, because nothing
existing opts in. It is rejected anyway, on two grounds.

First, it leaves the default behavior silent, and the default behavior is the
defect. #276 is not "the PLAN pre-flight cannot detect a bad schema"; it is
"`shirabe validate` reports success for work it did not do". A flag makes the
report honest only for callers who already suspected it was not.

Second, it makes correctness conditional on every future caller remembering to
opt in. The failure mode it introduces is the one this whole change exists to
remove: a checking surface that looks like it checked.

### Option 4: A fourth run outcome, Incomplete, at exit code 4 (chosen)

`ValidateOutcome` gains an `Incomplete` variant. Its severity rank sits between
`Clean` and `Violations`; its exit code is 4, the first unallocated value. A run
is Incomplete when at least one input was routed to a format and then not
checked against it, and nothing more severe happened.

The SCHEMA finding itself is untouched: same code, same message, same notice
severity, same position in the output. What changes is the run's roll-up. That
containment is what keeps the blast radius to three `.exit` files rather than
three `.stdout` files as well, and it is why this option scores better than
Option 1 on D4 despite being a larger conceptual change.

It satisfies D3 by saying the accurate thing. `incomplete` is not a claim about
document quality.

Its cost is a fourth value in an exit-code ladder that had four allocated
already, and every consumer documenting the ladder learns it. Consumers that
treat non-zero as failure are unaffected, which is the documented majority case.

## Decision Outcome

Option 4, in two batches ordered by D6.

**Batch 1 closes the silence (#276).** `ValidateOutcome` gains `Incomplete`
(exit 4), ranked `Clean < Incomplete < Violations < ToolError < Io`. The
per-file loop in `main.rs` marks the run Incomplete when a retained finding
carries code `SCHEMA` — retained meaning it survived `--check` selection, so
selection continues to drive the outcome as the contract says. The JSON envelope
gains a `skipped` array naming each such input and the reason, additive under
`shirabe-validate/v1`. A `--lifecycle` root beneath which none of the six
artifact directories exists becomes a tool error naming the root and what was
expected. The exit-code table in `docs/guides/multi-consumer-cli-contract.md`
gains the row, and the skills that document the exit ladder learn the value.

**Batch 2 removes the duplicate (#285).** R6 absorbs the two refusals only the
script had: an `upstream:` entry whose resolved target is a symlink, and one
whose canonical path escapes the working tree. `validate-plan.sh` and
`validate-plan_test.sh` are deleted, `check-plan-docs.yml` is re-pointed at
`shirabe validate` plus `shirabe validate --lifecycle-chain`,
`check-plan-scripts.yml` and `scripts/check-bash-floor.sh` drop their
references, and `/plan`'s phase 7 prose is rewritten to describe what the CLI
checks. The lifecycle model's upstream-status rule is what survives.

### Why the lifecycle model's status rule and not the script's

`/plan` transitions the upstream DESIGN from `Accepted` to `Planned` as part of
authoring the PLAN. A committed PLAN naming a DESIGN still at `Accepted` is
therefore evidence that the transition did not run — the chain is in a state it
should not be in — and the script was passing it. In the other direction, the
script's refusal of `Current` reflects a model that no longer exists: promotion
to `Current` postdates the script, and a single-pr chain mid-PR legitimately
holds its DESIGN at `Planned` or at `Current`.

**Corpus effect, named before the diff.** One PLAN exists in the tree,
`docs/plans/PLAN-work-on-friction-fixes.md`, and it carries no `upstream:` field
at all. No committed document changes verdict. The before/after whole-tree diff
shows nothing attributable to this decision, and the behavior change lands only
on PLANs authored after it — including the one this chain produces, whose
upstream DESIGN sits at `Planned` and passes under both rules.

An empty measured effect is the argument for making the change now rather than
an argument that it does not matter.

### Why the two script-only refusals go into R6

The value reaches a committed frontmatter field. A symlinked upstream resolves
differently for different readers; one resolving outside the tree names
something no other clone has. The script guarded both for that reason and no CLI
check does.

They land in `check_upstream_resolves` rather than in a new check because that
function already resolves the entry, already receives every written shape of the
field through the one normalizer in `upstream.rs`, and already reports under one
code. A second check would give the same entry two places to be refused from,
which is the shape this whole change is removing.

**Corpus effect, named before the diff.** No file under `docs/` is a symlink and
no `upstream:` entry resolves outside the working tree, so this decision also
contributes nothing to the diff. Every golden-corpus fixture carrying an
`upstream:` names a target that does not exist relative to the fixture working
directory, so each returns at the existing `does not exist on disk` finding and
never reaches the new code.

### Why the lifecycle root check tests for directories, not for an empty index

The obvious condition is "indexed zero documents". It is the wrong one: a
repository whose corpus is genuinely empty would fail, and that is a legitimate
state, not a mistyped argument.

The condition is instead that none of the six artifact directories exists
beneath the root. That is precisely the mistyped-argument case #276 reports —
`--lifecycle docs` looks for `docs/docs/briefs` — and it leaves an empty but
correctly-rooted tree reporting clean, which is the honest answer for it.

## Solution Architecture

**`crates/shirabe/src/main.rs`.** `ValidateOutcome` gains `Incomplete`.
`severity_rank` renumbers to `Clean 0, Incomplete 1, Violations 2, ToolError 3,
Io 4` so the existing "higher rank wins" merge keeps working unchanged;
`exit_code` maps `Incomplete` to 4 and leaves every existing mapping alone;
`label` returns `"incomplete"`. The per-file loop merges `Incomplete` where it
already merges `Violations`, on the retained-finding branch, so `--check`
selection governs both identically. `run_lifecycle` calls the new
directory-presence predicate before `run_lifecycle_check` and returns a tool
error when it reports absence.

**`crates/shirabe-validate/src/lifecycle.rs`.** The six-entry directory list
inside `build_doc_index` is lifted to a module-level constant and a small public
predicate answers whether any of them exists beneath a root. Lifting the list
keeps one source for what an artifact directory is; the predicate is what
`main.rs` calls.

**`crates/shirabe-validate/src/report.rs`.** The JSON renderer gains the
`skipped` array. It is derived from the same finding vector the envelope already
renders — an entry per retained `SCHEMA` finding, carrying the file and the
finding's message as the reason — so the array and the findings list cannot
disagree about what was skipped.

**`crates/shirabe-validate/src/checks.rs`.** `check_upstream_resolves` gains two
refusals after its existing `exists()` branch and before the git-tracking
branch: a `symlink_metadata` test for a symlinked target, and a canonicalization
test for containment within the working tree. Both report under `R6`, both name
the offending entry, and both `continue` rather than falling through, so a
refused entry produces one finding rather than two.

**Callers.** `check-plan-docs.yml` runs `shirabe validate` over each changed
PLAN and `shirabe validate --lifecycle-chain` over it for the status rule.
`check-plan-scripts.yml` loses its two `validate-plan` steps.
`scripts/check-bash-floor.sh` loses the suite from the `plan` group.
`skills/plan/references/phases/phase-7-creation.md` step 7.4b is rewritten
around the CLI.

### Exit-code table after the change

| Code | Meaning |
|------|---------|
| `0` | Clean: no error-level violations, and nothing was declined. |
| `1` | Tool error: the run could not complete. |
| `2` | Violations: at least one error-level result. |
| `3` | I/O error. |
| `4` | Incomplete: at least one input was accepted and then not checked. |

Severity ordering is unchanged in spirit and gains one rung: a tool error
outranks violations, which outrank an incomplete run, which outranks clean. As
already documented for codes 1 and 2, severity order and integer order differ on
purpose.

## Implementation Approach

**Batch 1: the CLI stops reporting success for work it did not do.** The
`Incomplete` outcome, the schema roll-up, the lifecycle root check, the envelope
array, and the contract-document updates. Batch 1 is independently shippable and
leaves the bash script in place, so at no point is the schema gate unmanned.

**Batch 2: R6 absorbs the script's remaining refusals.** Symlink and
containment. Batch 2 depends on nothing in Batch 1 but is sequenced after it so
that the deletion in Batch 3 is purely subtractive.

**Batch 3: the duplicate goes.** Delete the script and its suite, re-point
`check-plan-docs.yml`, clean `check-plan-scripts.yml` and the floor runner,
rewrite `/plan` phase 7. Batch 3 depends on Batches 1 and 2: it may not land
before the CLI holds every gate the script held.

**Batch 4: verification.** Re-run the whole-tree capture taken before Batch 1
and diff it, confirming every difference is one named above. Run the remaining
bash suites on Linux and under the 3.2 floor.

The decomposition is by capability rather than by file because the ordering
constraint is a capability constraint: the script may not be removed until the
CLI holds its gates, and no file boundary expresses that.

## Security Considerations

The change adds two refusals and removes none, so its net effect on the security
surface is subtractive of risk rather than additive.

**Symlinked and out-of-tree upstreams.** The refusals moved into R6 are the
reason this section is not "not applicable". An `upstream:` value reaches a
committed frontmatter field, and a symlink there resolves to different content
for different readers — the value a reviewer sees is not necessarily the value a
consumer resolves. A path escaping the working tree names something no other
clone has. Both were guarded by the script and by nothing else; after this
change both are guarded by the check that every reader of the field goes
through.

**Canonicalization boundary.** The containment test canonicalizes both the
entry's resolved path and the working tree before comparing, so a `../`-shaped
path and a symlink hop are both resolved before the comparison rather than
pattern-matched in their written form. Comparison happens on canonical paths;
nothing is decided by inspecting the written string.

**Argument boundary at the deleted call site.** The script passed every path
after `--` so a value beginning with a dash was a pathspec rather than an
option. The CLI's git invocation in `check_upstream_resolves` already does the
same — `["ls-files", "--error-unmatch", "--", path]` — so the property survives
the deletion rather than depending on it.

**No new input surface.** The `Incomplete` outcome and the lifecycle root check
read inputs the tool already read. No new argument is parsed, no new file is
opened, and no value from a document reaches a command line.

**Residual risk.** A cross-repo `owner/repo:path` upstream is skipped by the
containment and symlink checks as it is skipped by the existing resolution
check, because there is no local path to resolve. That gap is pre-existing,
belongs to content governance rather than tooling, and is not closed here.

## Consequences

### Positive

- One implementation answers the upstream question. A contradiction reachable on
  a single pull request stops being reachable.
- A green validation result becomes evidence that something was checked. The
  claim the tool makes and the work it did line up.
- Roughly 300 lines of bash and its 200-line suite leave the tree, along with two
  CI steps and a macOS matrix leg that existed to keep them portable.
- The status rule that survives is written down with its reasoning, so the next
  person to meet a surprising verdict can find out why rather than re-deriving.

### Negative

- **32 documents move from a green validation run to a red one.** Any pull
  request whose changed-file set includes one of the schema-less documents now
  exits 4 where it exited 0. This is the forcing function the change exists to
  create, and it is the single largest consequence of shipping it. The documents
  are unvalidated today and were unvalidated before; what changes is that the
  tool says so.
- **Three golden parity baselines change.** `real/PRD-roadmap-skill.md.exit`,
  `real/DESIGN-gha-doc-validation.md.exit` and
  `synthetic/DESIGN-missing-frontmatter.md.exit` hold `0` and must hold `4`.
  Their `.stdout` and `.stderr` are byte-unchanged, because the SCHEMA finding's
  severity and message are untouched. This is a modification to existing test
  data and is reported as a finding rather than absorbed: see Known Exceptions
  below.
- A fourth exit value is a compatibility surface for any consumer outside this
  repository that switches on specific codes rather than on zero-versus-non-zero.

### Mitigations

- The corpus consequence is bounded and enumerable: the 32 documents are listed
  by the before-capture, and the follow-up that gives them their `schema:` field
  has a measured size (22 further errors) rather than an unknown one.
- The golden-baseline exception is confined to the `.exit` files, which is the
  narrowest possible expression of "the exit code changed and nothing else did".
  Option 1 would have moved `.stdout` as well.
- Consumers that branch on zero-versus-non-zero — the documented majority, and
  every consumer inside this repository — need no change at all.

### Known Exceptions to "no existing test modified"

One, stated in full so it is not discovered in review:

**Three `.exit` files under `crates/shirabe/tests/fixtures/golden/expected/`
change from `0` to `4`.** The parity suite asserts stdout, stderr and exit code
byte-for-byte against a frozen baseline, and the exit code for a schema-skipped
document is exactly what this change alters. No `.rs` test file is edited, no
assertion is weakened or deleted, and no `#[ignore]` is added. The three
`.stdout` files are byte-identical before and after, which is the check that the
change did what it claimed and nothing more.
