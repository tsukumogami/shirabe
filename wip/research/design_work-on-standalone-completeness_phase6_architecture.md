# Architecture Review: DESIGN-work-on-standalone-completeness

## Verdict

FAIL

## Strawman check, per decision

### Decision 1 — where the shared cascade machinery lives

Fair. The design's four rejected alternatives (leave-and-call-across, root
`scripts/`, CI-drift duplication, `shirabe` subcommand) each get a real,
specific reason tied to evidence in the report
(`wip/research/design_work-on-standalone-completeness_decision_1_report.md`):
the root-`scripts/` rejection correctly cites that directory's inhabitants as
"skill-agnostic parameterized tools" versus this being "the first non-generic
git-mutating domain script there"; the drift-check rejection correctly cites
the 1-line-vs-1,157-line size mismatch; the `shirabe` subcommand rejection
correctly notes it is "out of this PRD's scope." One overstatement: the design
says the root-`scripts/` option was "disproved," but the report treats it as "a
real cost, not a fatal one" and states Option 3 "satisfies R5a's literal
acceptance criterion just as cleanly as Option 2." The design's word choice is
stronger than the report's finding, though the substantive reasoning
(dependency-direction precedent, not cost) is carried over correctly. Minor,
not a strawman.

Verified against code: `skills/execute/koto-templates/execute.md:598,618,709`
show `/execute` reaching `skills/plan/scripts/plan-to-tasks.sh` and (today)
`skills/execute/scripts/run-cascade.sh` by `${CLAUDE_PLUGIN_ROOT}` path, and
`skills/execute/scripts/assert-child-template.sh:1-29` is the real, existing
guard for the `/execute` → `/work-on` template path. Neither `/work-on` nor
`/plan` references anything under `skills/execute/`. The "chosen twice already"
claim is accurate.

### Decision 2 — anchor detection and the no-chain path

Fair. The design states three rejected alternatives (caller-supplied path,
issue-body `Plan:` field, caching from `context_injection`) each with the
report's actual reason: the caller-supplied path is correctly kept as a "fast
path" rather than dismissed outright (matching the report's "valid
short-circuit to keep... cannot stand alone"); the issue-body field is
correctly described as "silent for the population that surfaced the defect"
(matching the report almost verbatim); the caching option's staleness argument
matches the report's parallel to `staleness_check`. No option is described only
in terms of why it loses — the caller-supplied path's genuine value (kept, not
rejected) survives into the design.

### Decision 3 — which obligations become gates, and where they live

**This is the weakest of the five.** All three rejected alternatives (batching
state, one-state-per-obligation, extend-everything-in-place) are described in
the design purely by their cost, with none of the "what it buys" content the
report gave each of them:

- **Option A (batching state).** The report's actual objection is a sequencing
  problem — "a single state cannot sit both before `pr_creation` and after it
  in the same linear walk" — plus combinatorial branch bloat. The design
  instead says the option "re-derives invariants `execute.md` already
  settled" (`docs/designs/DESIGN-work-on-standalone-completeness.md:153-154`).
  That reasoning does not appear anywhere in the report's Option A discussion;
  it is closer to language the report uses when arguing against re-deriving
  `execute.md`'s precedent for the *two already-precedented* obligations
  (merge cleanliness, closing keyword), a different point entirely. The
  design has substituted a reason the source material does not support for
  the option's real, stated weakness, and dropped the option's real stated
  benefit ("a reviewer auditing R8's classification table has exactly one
  place to look... state count stays small").
- **Option B (one state per obligation).** Design: "multiplies states and
  agent turns for checks cheap to co-locate" (line 154). The report gives this
  option a substantive upside the design omits entirely: "Maximum clarity per
  obligation... trivial to audit: one state, one gate, one row... isolates
  blast radius." An option the researcher found genuinely competitive on
  auditability is reduced in the design to a pure cost statement.
- **Option C (extend everything in place).** Design: "would pile five more
  required fields onto `finalization`... coupling review of unrelated things"
  (matches the report's stated cost fairly well) — but again omits the
  report's explicit benefit: "Lowest diff risk... directly reuses the one
  piece of precedent that's an exact match... Turn count stays the same as
  today."

Individually each rejection reason is not fabricated from nothing, but Option
A's stated reason does not track the report, and all three are presented with
no acknowledgment that the researcher treated them as real contenders with
genuine advantages. This is the "described only in terms of why it loses"
pattern the task calls out.

### Decision 4 — one root/child discriminator or two

Fair, and the best-represented of the five. "Computing it once and caching it
into koto context" is correctly rejected for assuming "the two code paths
coincide, which they do not" — this tracks the report's central finding almost
exactly ("R19's own scoping note... shows they do not," and several terminal
ticks "never touch the capturing state"). "Two independent mechanisms" is
correctly rejected for reproducing "the textual-rather-than-runtime defect R19
was written to rule out" — this is the report's own framing verbatim in
substance. Option D (a native koto primitive) is omitted, but the report
itself says Option D "collapses to Option A... not a fifth path," so omitting
it is not a strawman — it correctly wasn't a live alternative.

### Decision 5 — the multi-pr migration's shape

Mostly fair, with one fabricated supporting fact. The "new committed file"
rejection ("invents an artifact type for a one-off") matches the report's
Option 2 reasoning closely. The refusal mechanism's two rejected alternatives
(koto gate, new terminal state) are correctly summarized as failing because
"no session should exist for a plan that is refused," which is the report's
actual reasoning (a session record for a refused plan is itself "a confusing
partial result").

The PR-body rejection is where the design goes wrong: "PR-body text (deleted
by the squash-merge, **which is how material has been lost here three times in
two days**)" (`docs/designs/DESIGN-work-on-standalone-completeness.md:196-198`).
The report's actual reason is narrower and correct on its own — R16a requires
the inventory to survive the squash-merge and Part 2 does not
(`wip/research/design_work-on-standalone-completeness_decision_5_report.md:295-305`).
But "three times in two days" is the PRD's phrase for the three *dispatched
worker sessions that skipped finishing obligations*
(`docs/prds/PRD-work-on-standalone-completeness.md:9,39,66`) — an entirely
different incident, with no connection to PR-body material loss anywhere in
the corpus. I grepped every `wip/` and `docs/` file in this chain for
"squash"/"lost"/"three times" and found no other source for this claim
(`design_work-on-standalone-completeness_decision_5_report.md` is the only
report mentioning squash-merge, and it says nothing about repeated loss). The
design invents a causal link between two unrelated facts to make a fine
rejection reason sound like it is backed by a repeated, documented incident.
This is not a strawman against the alternative — the alternative is still
fairly rejected — but it is a fabricated citation-shaped claim, which is worse
for a document whose whole purpose is to be a trustworthy record of what was
actually found.

## Structural fit

The three structural claims hold up against the code:

- **Cross-skill dependency direction, chosen twice already.** Verified:
  `skills/execute/koto-templates/execute.md:598,618` (`plan-to-tasks.sh`) and
  `skills/execute/scripts/assert-child-template.sh:1-29` (guard for the
  `work-on.md` child-template path). Both existing cross-skill script/template
  references run `/execute` → `/work-on` or `/execute` → `/plan`, never the
  reverse. The design's claim that relocating `run-cascade.sh` under
  `/work-on` is "the third instance" is accurate.
- **Gate-only, zero-evidence transition pattern.** Verified against
  `skills/work-on/koto-templates/work-on.md:695-750` (`pr_precheck`): the
  passing-path transition to `pr_creation` requires only
  `gates.on_feature_branch_pr.exit_code: 0`, with `precheck_status` absent on
  that path ("Absent on the passing path... the agent never sees it," line
  ~726). This is a real, exact precedent for the no-anchor path the design
  proposes for `cascade_entry`.
- **Verbatim-copied gate.** Verified: `merge_state_clean` exists today only in
  `skills/execute/koto-templates/execute.md:385-401`, not in `work-on.md`.
  `scripts/validate-template-mermaid.sh` (check 4, line ~154) requires a gate
  name shared across templates to carry an identical command, which is a real,
  mechanical constraint forcing the verbatim copy the design describes.

One gap: the design's Security Considerations section asserts "the existing
cross-skill guard pattern extends to" the relocated script
(`docs/designs/DESIGN-work-on-standalone-completeness.md:328,358`), implying a
new `assert-child-template.sh`-equivalent guard will exist for the `/execute`
→ relocated-script path. But the Solution Architecture component table lists
no such guard as a deliverable, and Decision 1's own report flagged this
explicitly as an open question left to "a design/plan-hop judgment call."
The design asserts the guard pattern "extends" without deciding whether a new
guard script is actually built, or without following the existing
`plan-to-tasks.sh` precedent of having no guard at all. This is a real,
if narrow, gap between a security claim and a concrete architectural
commitment.

## Requirement coverage

Walking the PRD's numbered requirements against the design:

R1–R4, R6–R13, R14–R22 all have a traceable home in the design (cascade
guard ordering for R1–R3, R4 preserved by construction per Decision 2, R6–R10
addressed by Decision 3's classification and state placement, R11–R13 by the
`session_role` field on `ci_monitor`, R14–R22 by the Decision 5 section and
the PR-2 row of the Solution Architecture table).

**R5 is not addressed anywhere in the design.** R5 requires: "Both failure
shapes the cascade can report — nothing published, and partially
published-and-pushed — SHALL be handled by the single-issue caller identically
to how the plan entry point handles them today, including the same recovery
guidance" (`docs/prds/PRD-work-on-standalone-completeness.md:194-198`), and it
has its own named acceptance criterion (PRD line 371-373). I grepped the whole
design document for "halt," "escalat," "blocked," "failure," "partial," and
"recovery" in connection with the cascade and found nothing: the data-flow
diagram
(`docs/designs/DESIGN-work-on-standalone-completeness.md:262-281`) shows
`cascade_run` routing unconditionally to `done`, with no branch for a
`partial` or unpublished cascade result. Compare
`skills/execute/koto-templates/execute.md:700-757`, which is the actual
precedent R5 says must be matched: a `partial` verdict "halts the run,"
distinguishes five named recovery shapes (failed push, failed commit, refused
transition with/without a commit, failed post-verify), and explicitly notes
"There is no separate terminal for `partial`, so the halt is the agent's to
observe rather than the machine's to enforce." None of this is carried into
the new design's `cascade_run` state, its data-flow diagram, its Solution
Architecture table, or its Implementation Approach. This is a named PRD
requirement with a named acceptance criterion, left completely unaddressed.

## Internal coherence

The design is internally inconsistent about how many states it adds.
Every place that enumerates new states names exactly three: "one narrow new
state between `finalization` and `pr_precheck`"
(line 150), and `cascade_entry` and `cascade_run` (lines 267-281, 297). But
Consequences states flatly: "`work-on.md` grows four states, in a template
that already declares twenty-eight" (line 351). No fourth state is named,
diagrammed, or described anywhere in the document. Given the R5 gap found
above, the most likely explanation is that the missing cascade-failure/halt
state (the design's analogue of `execute.md`'s implicit "the halt is the
agent's to observe" path, or an explicit escalation state) is the fourth
state the author had in mind but never wrote down — which would make this
inconsistency and the R5 gap the same underlying hole. Either way, an
implementer following this design literally builds three states and then
finds the document's own accounting doesn't match its own diagram.

Apart from that, the state graph as diagrammed does work: `ci_monitor`
deciding `session_role` before the anchor gate is the right order (matches
the cross-validation note that reversing it "would search on every child run
and then discard the answer"), and the `cascade_entry` gate-only routing is
mechanically consistent with the `pr_precheck` precedent verified above.

## Layering and dependency direction

Holds under direct testing against the code, as detailed under Structural fit.
`/execute` has two pre-existing cross-skill dependencies on `/work-on`/`/plan`
directories, and zero dependencies run the other way. Moving `run-cascade.sh`
under `skills/work-on/scripts/` and having `/execute` reach it by
`${CLAUDE_PLUGIN_ROOT}` path is a third instance of an already-established
shape, not an inversion. This central claim is correct and well-supported.

## Anything the design defers

Both named deferrals are legitimate and honestly stated. The six
self-reporting defects in `run-cascade.sh` (two awk rewrites under one
unconditional `ok`, four `git add ... || true` sites) are verified present at
`skills/execute/scripts/run-cascade.sh:531-588` (awk block, one `ok` at the
end) and at lines 603, 903, 910, 916 (all four `git add ... || true` sites,
each followed by an unconditional `STAGED_FILES+=(...)`) — the design's line
citations and count are accurate. The evidence-over-report design (checking
the finalization commit's own paths, verified against `resolve_anchor()` at
`run-cascade.sh:317-339`, which does select from files still present on disk)
is a genuine, verified fix for the blind spot described, and the design is
honest that hardening the six sites themselves is left to another issue.

The dependency on the not-yet-landed root/child mechanism (R19b,
`session-role.sh`) is flagged explicitly as an assumption with an escalation
path, matching Decision 4's own caveat that the script "is not present on this
branch." This deferral is handled correctly and is the one place in the
document that models good practice for stating an assumption's blast radius.

## Required changes

1. Add explicit handling for R5: the cascade's `partial`/unpublished failure
   shapes must route somewhere and be described with recovery guidance
   matching `execute.md:700-757`, in the data-flow diagram, the Solution
   Architecture, and the Implementation Approach — not left implicit.
2. Resolve the "four states" vs. three-states-named inconsistency
   (`docs/designs/DESIGN-work-on-standalone-completeness.md:351` vs.
   150/267-281/297) — most likely by naming the missing failure/escalation
   state that (1) requires.
3. Rewrite Decision 3's Considered Options to state each rejected option's
   real trade-off rather than only its cost — in particular, replace the
   Option A rejection reason ("re-derives invariants `execute.md` already
   settled") with the report's actual reasoning (the pre-PR/post-PR
   sequencing problem), and acknowledge Option B's real auditability
   advantage even while rejecting it on turn-count/legibility grounds.
4. Remove the fabricated causal claim at
   `docs/designs/DESIGN-work-on-standalone-completeness.md:196-198`
   ("deleted by the squash-merge, which is how material has been lost here
   three times in two days") — the squash-merge argument alone is sufficient
   and correct; the "three times in two days" reference belongs to an
   unrelated incident and should not be attached here.
5. Either commit to a new cross-skill guard for the relocated
   `run-cascade.sh` path (naming it as a Solution Architecture component) or
   state explicitly that none is added, matching `plan-to-tasks.sh`'s
   unguarded precedent — the current "the existing... guard pattern extends
   to it" line asserts an outcome without deciding it.

## Observations

- Decisions 1, 2, and 4 are well-represented against their source reports;
  the strawman risk is concentrated in Decision 3 and, to a lesser extent,
  the one fabricated fact in Decision 5.
- The document's Context and Security Considerations sections are unusually
  well-verified against the actual `run-cascade.sh` source — every line
  citation I checked (531-588, 603, 903-919, 377-381, 1093-1100) was accurate,
  which makes the two Decision-3/Decision-5 fidelity lapses more notable by
  contrast rather than less.
- The frontmatter and body both pass the mechanical checks: all nine required
  sections present and in order, frontmatter has `status`/`problem`/
  `decision`/`rationale`, and `## Status` (Proposed) matches the frontmatter.
