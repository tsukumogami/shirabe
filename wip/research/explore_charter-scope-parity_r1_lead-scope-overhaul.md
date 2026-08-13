# Lead: What exactly did PR #260 change about how /scope runs?

## Findings

FULL REPORT — the `/scope` overhaul (commit 3f702b6, PR #260, merged 2026-08-10)

Repo root for every path below:
/home/dgazineu/dev/niwaw/tsuku/tsuku+overhaul_charter-0c5beaa5/public/shirabe/.claude/worktrees/charter-scope-parity

Current tree == post-PR state: `git diff --stat 3f702b6 HEAD -- skills/scope skills/brief references` is empty. The only commits after it are `00dba51` (v0.16.0) and `2e60e46` (0.16.1-dev). The relevant precursor is `70cd921 feat(charter): always produce a ROADMAP, and let one feature be enough (#252)`.

Headline: the overhaul is not merely "always run the steps." It is three coupled moves — (1) the chain always walks all four children, (2) each child is invoked with its UPSTREAM ARTIFACT'S PATH instead of the bare topic slug so it consumes rather than re-derives, and (3) a consolidation judgment at the end of each per-child loop iteration may absorb the upstream into the artifact that just landed. (2) is what makes (3) viable; the PR body states the two "ship together": consumption alone leaves two documents saying the same thing, and consolidation alone would try to absorb a BRIEF into a PRD written without reading it, so the carry check would fail most of the time.

### 1. What the old behavior was

Phase 1 evaluated FOUR produce-or-skip gates during discovery, each firing before its artifact existed, and wrote only the surviving children into `planned_chain:`. From `git show 3f702b6^:skills/scope/references/phases/phase-1-discovery.md`:

- R4 for `/brief` — Mandatory-with-auto-skip. An Accepted BRIEF at `docs/briefs/BRIEF-<topic>.md` skipped `/brief`, recorded in `chain_skipped:` with reason `accepted-brief-at-canonical-path-with-no-framing-shift`, unless the author's framing-shift answer overrode it.
- R5 for `/prd` — skip when `docs/prds/PRD-<topic>.md` was Accepted, reason `accepted-prd-at-canonical-path`.
- R6/R7 for `/design` — the three shape predicates (P1 architectural-alternatives count, P2 new-component references, P3 Complex classification) were read as a PRODUCE-OR-SKIP gate. Old text verbatim: "When zero R6 predicates fire, `/design` is recorded in `chain_skipped:` with the per-predicate verdicts as the skip reason (e.g., 'P1: does-not-fire (zero alternatives); P2: does-not-fire (no new components); P3: does-not-fire (complexity: Simple)')."
- `/plan` — ALWAYS.

Phase 2 then invoked every child as `/<child-name> <topic-slug>` — every child's COLD-START mode. The DESIGN's problem statement names the consequence (docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:53-64): `/prd` read the slug as Input Mode 3, which "does NOT invoke shirabe transition because there is no BRIEF path to transition", so "a PRD written moments after a BRIEF in the same chain neither records it as `upstream:`, nor advances it, nor reads it. `/design` and `/plan` are invoked the same way and consume their upstreams the same amount, which is not at all. Every artifact in a `/scope` chain is independently re-derived from the parent's conversation. That is the engine producing the repetition the skip logic was meant to relieve."

Separately, `/brief` carried a FOLD-INTO-PRD branch at its Phase 0.5, deciding before any brief existed whether to write a standalone BRIEF or "fold the framing into the downstream PRD/design" and exit with a `/prd` recommendation. That branch held the only written reader-economy rationale in the system, and `/scope`'s slug-mode invocation made it unreachable from a `/scope` run while `/prd` had no absorb step to receive what it folded. DESIGN:66-70: "The path names what should move and moves nothing."

The rationale mismatch is the third old-state fact (DESIGN:72-78): the skip rationale recorded at `/scope`'s own gate layer was clobber-protection ("the parent MUST NOT silently overwrite an Accepted durable artifact") — "correct, necessary, and not a statement about what a reader has to read. So the reader-facing reason for reducing the artifact set is documented nowhere in the skill that implements the reduction."

### 2A. New behavior — how "always run" is enforced

Enforcement is by making `planned_chain:` a CONSTANT, not by a check.

skills/scope/references/phases/phase-1-discovery.md:13-16 — "Phase 1 decides **nothing about the size of the artifact set.** `planned_chain:` is `[brief, prd, design, plan]` on every run. There is no starting altitude to choose and no child that Phase 1 can decide is not worth invoking."

phase-1-discovery.md:340 — "That list is a constant. Phase 1 has no input that can shorten it and no field that records a different shape."

skills/scope/references/state-schema.md:30-35 — `planned_chain` is "the whole tactical chain (`brief`, `prd`, `design`, `plan`) in order, minus any child held back by re-entry protection… There is no field recording where the chain starts, because it always starts at `brief`."

phase-2-chain-orchestration.md:539-543 — the security counterpart: `planned_chain:` needs no state-file enum re-validation because "`planned_chain:` is a constant, the child names are fixed, and each child's argument path is composed from the validated topic slug rather than from state — so a tampered state file cannot redirect an invocation to an unexpected child or an unexpected path."

The ONLY thing that removes a child from the chain is RE-ENTRY PROTECTION — a settled artifact already on disk that re-running would clobber (phase-1-discovery.md:107-147). Single reason string: `settled-artifact-at-canonical-path-reentry-protection`. Settled-status table at :117-122 — `/brief`: Accepted, Done · `/prd`: Accepted, In Progress, Done · `/design`: Accepted, Planned, Current (two paths) · `/plan`: Active, Done. `/brief` keeps a framing-shift override (:123-131), and the prose notes the override "can only ever fire in the case the auto-skip would otherwise have closed, so a cold start fires `/brief` whatever the answer says."

The disambiguation is stated explicitly, phase-1-discovery.md:133-140: "**This is not a worth-producing judgment.** The skip means 'a settled document is already here, and re-running would clobber it.' It does not mean 'this artifact would not have been worth writing.' Nothing at Phase 1 is in a position to make the second claim, because the artifact it would be about does not exist. An earlier revision of this file recorded the same behaviour under a rationale that read as reader economy; the reason it gives now is the reason it always had."

R6 predicates survive with exactly one consumer — sizing `/design`'s decision roster (phase-1-discovery.md:148-167 and 250-264): "The predicates do **not** decide whether `/design` is invoked. `/design` runs on every chain. R7 previously read these verdicts as a produce-or-skip gate; that reading is retired, and 'shape-dependent' now means what it says in the Gate Vocabulary — the gate governs *how* a child is invoked, not whether." And :253-259: "All-negative verdicts still invoke `/design`; they size it down to the minimum roster, and the resulting DESIGN records the one live option and why no alternative was live. That is a shorter document than a contested design, and it is a better audit trail than the silence it replaces."

Also relevant: the post-`/prd` re-evaluation gate (phase-1-discovery.md:90-106) now "changes `/design`'s roster size, never whether `/design` runs. `planned_chain:` is the whole chain on every run and is not revised here." And Adjust was re-scoped — SKILL.md:357-359: "Adjust refines the topic and the framing, not the list of children."

The chain proposal is forbidden from offering a shorter chain — SKILL.md:348-350: "The proposal never offers a shorter chain, because `/scope` has no way to produce one. An author who wants to start above `/brief` invokes `/design` or `/plan` directly."

### 2B. New behavior — the exact absorption mechanism

WHO decides: `/scope` itself, in Phase 2, as step 8 of an eight-step per-child loop. No sub-agent, no author prompt, no CLI subcommand. phase-2-chain-orchestration.md:38-72 lists the loop:

1. worktree-staleness check
2. write `parent_orchestration:` sentinel
3. child invocation (CHANGED: upstream-path mode)
4. R20 structural file-existence check
5. clear sentinel
6. child-snapshot capture
7. validator pass-through
8. consolidation judgment vs nearest survivor (NEW)

WHEN: after the validator pass-through clears, and "only when this chain produced a durable artifact above the one that just landed" (:381-383, and :64-66 "Skipped when this chain produced no artifact above the current one"). So the judgment is per-hop and local, immediately next to the conversation that produced the artifact.

CRITERIA — three stages (phase-2-chain-orchestration.md:379-480):

Stage 1 — Absorbability (:395-416). A mapping table decides whether the hop is absorbable at all: "Absorption is available only where the downstream type's required sections provide a home for **every** required section of the upstream type, so an absorb never has to discard content or invent somewhere to put it."

| Hop | Mapping | Absorbable |
|---|---|---|
| BRIEF to PRD | Problem Statement→Problem Statement; User Outcome→Goals; User Journeys→User Stories; Scope Boundary→Requirements (in-list) and Out of Scope (out-list) | Yes |
| PRD to DESIGN | Problem Statement→Context and Problem Statement; Goals, User Stories, Requirements, Acceptance Criteria and Out of Scope have no home | No |
| DESIGN to PLAN | Decision Drivers, Considered Options, Decision Outcome, Solution Architecture, Security Considerations and Consequences have no home | No |

:409-411 — "The verdicts are derived from the per-type required-section contracts in `crates/shirabe-validate/src/formats.rs`, not enumerated by hand. If a format ever grows a section, re-derive the table rather than trusting this snapshot." Non-total mapping ⇒ only verdict is `keep`, recorded with a reason naming the unmapped sections (:414-416).

Stage 2 — Judgment (:418-434). "Read both bodies. The question is whether the upstream artifact does work the downstream does not: does any required section of the upstream carry content, detail, or framing the downstream does not also carry?" No ⇒ `absorb`; Yes ⇒ `keep` with a finding naming what the upstream holds that the survivor does not. A stated prior for the one live hop (:427-434): "four of the BRIEF's five required sections are renamed PRD sections with equivalent content rules, so a BRIEF that fed one PRD and did no independent framing work is a redundant document rather than a redundant paragraph. A BRIEF whose journeys drove the requirement set, or whose framing settled something contested, has earned its own document and keeps it."

Stage 3 — Carry check and absorb (:436-480). "On `absorb`, walk the upstream's required sections one at a time and record where each landed. This is the receiving mechanism: an absorb that is not itemized is a recommendation, and a recommendation with nothing confirming the transfer is how content goes missing."

Recorded shape (:444-456):

```yaml
consolidation_judgments:
  - hop: brief->prd
    absorbable: true
    carry_check:
      Problem Statement: {target: Problem Statement, carried: true}
      User Outcome:      {target: Goals, carried: true}
      User Journeys:     {target: User Stories, carried: true}
      Scope Boundary:    {target: Requirements + Out of Scope, carried: true}
    verdict: absorb
    absorbed: docs/briefs/BRIEF-<topic>.md
    into: docs/prds/PRD-<topic>.md
```

Abort path (:458-462): "Any `carried: false` **aborts the absorb**: the verdict is downgraded to `keep`, the finding names the section that did not arrive, and both artifacts stay on disk. Nothing is deleted on a failed carry check."

WHAT HAPPENS TO THE ABSORBED ARTIFACT — it is DELETED from the repo. Four steps (:464-479):

1. Read the absorbed artifact's own `upstream:` value.
2. Set the survivor's `upstream:` to that value, or remove the field when the absorbed artifact had none. "This is the settled nearest-produced rule from `${CLAUDE_PLUGIN_ROOT}/references/pipeline-model.md`, not a new convention."
3. `git rm` the absorbed artifact.
4. Re-run `shirabe validate` on the survivor. "A non-zero exit reverts the absorb (restore the artifact, restore the `upstream:` value) and routes to R8 bail-handling."

:477-479 — "Step 4 is load-bearing: the validator's `R6` check requires an `upstream:` value to resolve to a tracked file, so a survivor whose re-point was missed fails validation and the absorb does not land."

Not left in wip/, not moved to a superseded status: DESIGN Decision 6 Option C rejected keeping it on disk (DESIGN:291-295) — "BRIEF's valid statuses are Draft, Accepted, and Done — there is no superseded state to move it to — and leaving it on disk leaves the reader the second document they were meant to stop reading."

No cascade (:481-487): "`absorb` means the upstream's content is *in* the survivor, not annotated as living elsewhere, so a later hop judging that survivor is judging a body that already includes everything absorbed into it. Nothing rides along separately and there is no chain of pointers to follow." Consistent with :178-180: a later child whose upstream was absorbed is invoked with the SURVIVOR's path — "that is what 'nearest artifact this chain produced' resolves to once an absorb has happened."

Manual-fallback boundary (:489-497): "Step 8 lives here and nowhere else. A child invoked directly, outside `/scope`, runs no consolidation judgment and writes no `/scope` state — not because a code path is suppressed, but because there is no consolidation code path inside a child."

Durable record of the verdict: `consolidation_judgments:` is scratch in wip/, so Phase 3 copies it into the PR body before Phase 4 deletes the state file. phase-3-exit-finalization.md:64-77 — "Phase 3 writes it into the run's pull-request body: every artifact in `chain_ran:`, every entry in `chain_skipped:` with its re-entry-protection reason, and every entry in `consolidation_judgments:` with its verdict, its finding, and — on a completed absorb — what was absorbed into what. Without it, a reviewer reading the PR cannot tell an artifact that was absorbed from one that was never produced. The two look identical on disk and mean opposite things." Same rule at state-schema.md:139-143.

`exit_artifacts:` also reflects survivors, not just the PLAN — phase-3-exit-finalization.md:54-57: "a chain that produced a BRIEF, a PRD, and a DESIGN records all three alongside it, and one whose BRIEF was absorbed records the surviving PRD without it."

THE OTHER HALF — UPSTREAM-PATH INVOCATION (phase-2-chain-orchestration.md:158-203):

- `/brief` — invoked with the topic slug; "It is the head of the chain, so there is nothing above it to hand it."
- `/prd` ← `docs/briefs/BRIEF-<topic>.md` · `/design` ← `docs/prds/PRD-<topic>.md` · `/plan` ← `docs/designs/DESIGN-<topic>.md`

:182-187 — "These are input modes each child already ships: `/prd`'s Input Mode 2 takes a BRIEF path and transitions it Draft to Accepted, `/design`'s PRD mode reads the accepted PRD and bumps it to In Progress, `/plan` accepts a DESIGN path. Passing the path is choosing among a child's shipped modes, not extending its input surface." R14 isolation preserved (:189-196) — `/scope` reads only the child's frontmatter `status:` and the artifact's git blob hash; no flags, no env vars, no new parse branch.

:198-203 — "Invoking every child in its cold-start mode was the mechanical cause of the duplication this skill's consolidation judgment now reduces: a child handed a bare slug re-derives the framing its upstream already settled, and records no `upstream:` link back to it."

WHAT THE AUTHOR IS ASKED / SHOWN: nothing about absorption is prompted — the judgment is autonomous. The author sees it twice. First in the Phase 1 chain proposal, whose skeleton (phase-1-discovery.md:299-309) now reads:

> Planned chain (the full tactical chain, as always):
>   /brief — runs (no settled artifact at the canonical path)
>   /prd — runs (no settled artifact at the canonical path)
>   /design — runs; roster shape from P1 fires, P2 does-not-fire, P3 fires
>   /plan — runs (ALWAYS)
>
> Any artifact that turns out to be redundant is absorbed after it and its successor both exist, not skipped now.
>
> Proceed / Adjust / Bail?

Second, afterwards, in the PR body's produced/absorbed/finding record. The only Phase 1 decision point remains Proceed / Adjust / Bail (literal substrings graded by evals).

### 3. Exact mechanism surface (files / sections / phases / state)

skills/scope/SKILL.md

- :372-422 NEW section "## Why the Artifact Set Shrinks" — the reader-facing rationale, now stated in `/scope`'s own words.
- :424-453 NEW section "## Consolidation Judgment" — the two verdicts, the absorbability rule, the carry check, and a pointer to the Phase 2 reference for the mechanism/table/schema/re-point rule.
- :335-370 "## Chain-Proposal Output" — always the whole chain; :348-350 never offers a shorter one; :357-359 Adjust re-scoped.
- :216 phase table row for Phase 2 now ends "…validator pass-through; consolidation judgment"; :291-300 Phase Execution entry for Phase 2 names "invoke child with its upstream artifact's path" and the consolidation judgment.
- :38-44 the SKILL's own self-description of its asymmetries now includes "a post-hoc consolidation judgment that is the only thing reducing the artifact set and runs only after the artifacts exist".
- :666-685 Security Considerations — the closed write-target set gains "the consolidation judgment's deletion of an absorbed artifact under `docs/briefs/`", plus "The absorbed artifact's path is composed from the validated topic slug, never from author-supplied text, so the write-target set stays closed and enumerable."

skills/scope/references/phases/phase-1-discovery.md

- :11-43 NEW "## What Phase 1 Decides, and What It Does Not".
- :107-147 "## Re-Entry Protection (R4, R5)" — replaces the old R4/R5 gate sections; settled-status table; not-a-worth-judgment paragraph.
- :148-264 R6 predicate walk + "## R7 Shape-Dependent Evaluation for `/design`" retargeted to roster size.
- :266-287 NEW "## The Durable-Artifact Floor".
- :288-321 chain-proposal output.
- :322-360 "## `planned_chain:` Population" — the constant, the single skip reason.

skills/scope/references/phases/phase-2-chain-orchestration.md

- :15-20 framing: "Two things make this phase different from the one it replaces. Children are invoked with the artifact this chain produced above them rather than with the bare topic slug… And the artifact set is reduced *here*, after the artifacts exist, rather than at Phase 1 before any of them do."
- :38-72 eight-step loop.
- :158-203 "## Child Invocation" — argument table, shipped-input-mode argument, R14 note.
- :205-234 R20 file-existence check (now names BOTH DESIGN paths).
- :379-497 "## Consolidation Judgment" — stages 1/2/3, mapping table, carry-check YAML, absorb procedure, cascade note, manual-fallback boundary.
- :499-518 "## Per-Child Gates from `planned_chain:`, Not Re-Walked" — describes `planned_chain:`/`chain_skipped:`/`child_snapshots:` as the cached chain shape.
- :550-576 References — now cites `pipeline-model.md` and `crates/shirabe-validate/src/formats.rs`.

skills/scope/references/state-schema.md

- :49-70 NEW `consolidation_judgments` — conditional list, one entry per hop judged, appended in chain order, "Absent when the chain produced fewer than two durable artifacts." Fields: `hop`, `absorbable`, `verdict` (`absorb|keep`), `carry_check` (present only on absorb), `absorbed`/`into` (on a completed absorb), `finding` (why keep, or which section failed to carry). And: "An aborted absorb is recorded as `verdict: keep` with the carry check that failed, so the abort is auditable rather than indistinguishable from a judgment that never considered absorbing."
- :23-29 NEW `visibility` field (`Public|Private`) — previously read back by Phase 2's validator pass-through but never defined.
- :30-35 `planned_chain` redefined; :36-48 `chain_skipped` reason semantics.
- :139-143 the PR-body copy-out rule.
- Also reconciled here: `chain_completed` scoped to every exit rather than `full-run` alone (:17-23); `plan_execution_mode` enum gains `coordinated` (:81-88); `partial_phase_reached` redefined as `/scope`'s own Phase 2 loop position, "NOT a phase read out of the child's internals… Reading the child's internal phase would breach the R14 isolation rule" (:101-109).

skills/scope/references/phases/phase-3-exit-finalization.md

- :64-77 NEW "#### Durable record of what the chain produced".
- :54-57 exit_artifacts semantics under absorb.
- :293-297 closed write-target set: "Phase 2's consolidation judgment adds one deletion target, `docs/briefs/BRIEF-<topic>.md`, on a completed absorb… Phase 3 does not delete; it records the deletion the judgment already performed."

skills/brief/ (the retired fold branch)

- skills/brief/SKILL.md:217-223 — "**Always produces a brief:** there is no branch that declines to write one. A brief whose framing turns out to be fully carried by its downstream PRD is removed by `/scope`'s consolidation judgment, which reads both documents and checks section by section that the content arrived. That check cannot run before the brief exists, which is why `/brief` no longer tries to make the call at Phase 0."
- skills/brief/SKILL.md — Phase 0 purpose row drops "artifact decision"; the next-steps table now says `/prd <brief-path>` rather than `/prd`.
- skills/brief/references/phases/phase-0-setup.md:143+ — "## 0.5 Record the Artifact Decision": "`/brief` always produces a standalone BRIEF. There is no branch here that declines to write one." The context-file key survives with one value (`produce`). The "What changed and why" paragraph names the two defects: "It fired before any brief existed, so nothing it read could tell whether the brief would have carried something the PRD would not — the question it was trying to answer was not answerable yet. And nothing received what it folded: the path recommended `/prd` and named the content to carry forward, but `/prd` had no absorb step and no input mode for folded framing, so a fold left the framing in the ephemeral source it was supposed to be rescued from." Phase 0's exit branch is deleted: "Phase 0 has no exit branch — every `/brief` run that reaches the end of this phase goes on to write a brief."
- skills/brief/references/phases/phase-1-discover.md:98-104 — an author unsure whether a brief is right is now pointed at `/prd <topic>` or `/explore`; "`/brief` itself has no branch that declines to write a brief; a brief that turns out to be fully carried by its PRD is removed by `/scope`'s consolidation judgment after both exist, not skipped before either does."

skills/prd/ and skills/design/ (the consumption half)

- skills/prd/references/phases/phase-3-draft.md — NEW block "**When an upstream BRIEF exists (Input Mode 2), read it first.**" with the same four-row mapping table, plus: "Re-deriving framing the brief already wrote is what makes a BRIEF and its PRD read as two documents saying one thing — and it leaves the two documents disagreeing whenever the re-derivation drifts." And explicitly: "Carrying the framing forward properly is also what makes the downstream consolidation judgment usable… a PRD written without reading its brief fails that check, and both documents stay." Each drafting guideline (Problem Statement, Goals, User Stories, Out of Scope) now reads "Draw from the BRIEF's … when one exists, otherwise …".
- skills/prd/references/prd-format.md — NEW "## Citation vs Restatement" section scoping standalone-readability to the Problem Statement: "Everything else the upstream already says is **cited, not restated**."
- skills/design/references/design-format.md:266+ — the same scoping added to the DESIGN's standalone rule: "Standing alone is scoped to **this section**… A DESIGN that opens by citing its PRD's requirement numbers loses nothing; one that re-narrates the PRD in full costs its reader a second read of a document they can open. Both shapes exist in this repo and both passed review, because until now no rule distinguished them."

crates/shirabe-validate (the mechanical backstop)

- checks.rs:784 — `check_plan_upstream` renamed `check_upstream_resolves`; new private `is_cross_repo_reference()` skips `owner/repo:path` values (discriminator: a `:` whose prefix contains a `/`). Doc comment: "The check runs for every format, not just Plan. A dangling `upstream:` is wrong however it arose -- a typo, a renamed artifact, or a `/scope` consolidation whose re-point was missed -- so the resolution guarantee belongs to every doc type that can carry the field."
- validate.rs:217 — call site moved out of the `Some("Plan")` match arm into the common per-doc path. Check code stays `R6`; messages unchanged; `is_known_check_code` needs no new entry. Four new unit tests (absent field clean, missing file → R6, untracked file → R6, cross-repo skipped).

Evals (skills/scope/evals/evals.json) — six scenarios encode the mechanism: `chain-shape-is-constant`, `durable-artifact-floor-is-structural`, `consolidation-absorb-brief-into-prd`, `consolidation-keep-at-unmapped-hop`, `consolidation-carry-check-failure-aborts-absorb`, `upstream-path-invocation-preserves-child-isolation`. The first two replaced the withdrawn entry-altitude pair. Notable expected_output, `chain-shape-is-constant` (prompt: author says problem and requirements are settled, they only want to talk architecture): "The chain still runs /brief, /prd, /design and /plan. /scope has no altitude selection: an author who says the framing and requirements are settled is not offered a shorter chain, because deciding that an unwritten BRIEF is not worth writing is the exact judgment this skill removed." Also updated: skills/brief/evals/evals.json (incl. `rich-issue-still-produces-a-brief`) and skills/prd/evals/evals.json (incl. `brief-upstream-drives-drafting`, `problem-restated-everything-else-cited`).

### 4. Generic parent-skill machinery vs. BRIEF/PRD/DESIGN/PLAN-specific

SCOPE-SPECIFIC (inherently about the tactical artifact types):

- The mapping table itself and its three verdicts — derived from concrete per-type required-section contracts in `crates/shirabe-validate/src/formats.rs`.
- The four carry-check keys (Problem Statement / User Outcome / User Journeys / Scope Boundary) and their PRD targets.
- The `docs/briefs/BRIEF-<topic>.md` delete target added to the closed write-target set.
- The R6 predicates P1/P2/P3 and their single consumer, `/design`'s decision roster.
- The child-argument table (`/prd`←BRIEF path, `/design`←PRD path, `/plan`←DESIGN path) and the settled-status table per child.
- The fact that exactly ONE hop is absorbable today, and the durable-artifact-floor arithmetic that falls out of it.

GENERIC "parent walks a chain of children" machinery — the shape is type-agnostic:

- `planned_chain:` as a constant; the rule that the only legitimate hold-back is re-entry protection against clobbering a settled artifact, recorded under its own reason string.
- The rule that reduction runs AFTER each artifact lands, per hop, rather than at planning time — and the argument for it ("a judgment about whether a document would have carried anything is only answerable against a document that exists").
- The three-stage absorbability → judgment → carry-check structure, including the abort-toward-keeping failure direction ("Every new failure mode fails toward keeping artifacts", DESIGN:735-738).
- The absorbability CRITERION itself is stated generically — "a total mapping from the upstream type's required sections into the downstream type's" — and the DESIGN deliberately states the rule rather than the answer (Decision 4 Option D rejected hard-coding "BRIEF folds into PRD": "Correct today by accident. A reader cannot tell whether the other hops were considered, and the rule silently becomes wrong if a format gains a section." DESIGN:234-237, 248-251).
- "Invoke each child through the upstream-path input mode it already ships" — this rests on the pattern-level R14 child-isolation boundary (D3), not on anything about PRDs.
- The re-point rule (survivor inherits the absorbed artifact's own `upstream:`, or omits it) — this is the pattern-level nearest-produced rule from references/pipeline-model.md:121-133, not a new convention.
- The requirement that the per-hop record survive into the PR body because wip/ is deleted.
- The generalized validator check (`upstream:` must resolve on every doc type).

IMPORTANT: NOTHING GENERIC WAS EXTRACTED INTO THE SHARED PATTERN. `references/parent-skill-pattern.md` was NOT touched by this PR (it is absent from the diffstat). Its Gate Vocabulary (references/parent-skill-pattern.md:113-172) still names exactly three shapes — ALWAYS, shape-dependent, Mandatory-with-auto-skip — and Mandatory-with-auto-skip still reads as an auto-skip against a settled artifact, which is precisely what re-entry protection now is. PRD R18 forbade introducing a fourth gate shape (docs/prds/PRD-scope-consolidation-over-skipping.md:215-216). Grepping `references/` for `absorb|consolidat` returns only unrelated hits: decision-block-format.md:98, decision-protocol.md:91-100, parent-skill-state-schema.md:221 ("silently absorbed", about violations). `consolidation_judgments` is defined only in skills/scope/references/state-schema.md, not in the pattern-level schema.

The generic test was already run against `/charter` and returned zero. DESIGN Decision 9 (:353-372): "`/charter` has already taken the run-every-child half of this: PR #252 made `/roadmap` an ALWAYS child with an author declination rather than a threshold the parent computed, which is the same move Decision 1 makes for `/design`. The consolidation half does not generalize… STRATEGY's required sections have no home for a VISION's Audience, Value Proposition, Org Fit, or Success Criteria; ROADMAP's have no home for a STRATEGY's Defensibility Thesis, Building Blocks, or Bet-Specific Falsifiability. Zero strategic hops are absorbable, so porting the judgment would install a rule that can only ever return `keep`. The model is intended to generalize; generalizing it today changes nothing, which is the reason not to." Charter's current gate bindings, per skills/charter/SKILL.md:223: `/vision` is Mandatory-with-auto-skip plus a thesis-shift override; `/strategy` and `/roadmap` are ALWAYS. The pattern doc's ALWAYS entry (parent-skill-pattern.md:121-137) already sanctions an optional author declination for an ALWAYS child and notes "`/scope`'s `/plan` is ALWAYS with no declination surface."

### 5. Shared references outside skills/scope/

There is a top-level `references/` directory (addressed in skill prose as `${CLAUDE_PLUGIN_ROOT}/references/`). `/scope` binds to, per SKILL.md:317-333 and the phase files' References sections:

- references/parent-skill-pattern.md — contract surface, invariants, Gate Vocabulary (:113-172), three exit paths, L13 `parent_orchestration:` sentinel, Dispatch Contract, invariant I-7 Team-Lead Operating Discipline, Named Substitution Surfaces.
- references/parent-skill-state-schema.md — 5-field minimum, the `planned_chain`/`chain_ran`/`chain_skipped` triad (:141-144), conditional-field gating (I-5), R9 hard-finalization spec Parts 1-3.
- references/parent-skill-resume-ladder-template.md — meta-ladder rows 1-4 and 8-9.
- references/parent-skill-child-inspection.md — R14 widened isolation rule, per-parent inspection surface table.
- references/parent-skill-security.md — the six security surfaces (slug re-validation on resume, closed write-target set, enum re-validation, self-heal, visibility, no untrusted-input interpolation).
- references/worktree-discipline.md — the Rebase / Impact-analysis / Escalation flow and `worktree_rebases:` / `worktree_divergences:` schemas.
- references/pipeline-model.md — the settled `upstream:` rule (:106-133) the absorb's re-point applies.
- references/coordination-strategy.md and references/cross-repo-references.md — the coordination-PR path.

Non-`references/` shared surfaces Phase 2 cites directly: `crates/shirabe-validate/src/formats.rs` (source of the mapping table) and `docs/guides/multi-consumer-cli-contract.md` (the JSON envelope + multi-level exit-code contract shared with `transition` and `finalize-chain`).

Chain-level artifacts for this change: docs/briefs/BRIEF-scope-consolidation-over-skipping.md, docs/prds/PRD-scope-consolidation-over-skipping.md (21 requirements, 23 ACs), docs/designs/current/DESIGN-scope-consolidation-over-skipping.md (9 decisions).

### 6. Rationale for abandoning the skip-based approach

Commit message / PR body, opening: "`/scope` decided per hop, before each artifact existed, whether the child was worth invoking. Nothing it read could tell it what was being lost, and the party making the call was the one that benefited from not doing the work. The reader-economy reason those gates were meant to serve was documented only inside `/brief`, behind a branch `/scope` could not reach, with nothing on the other side to receive what it folded."

DESIGN Decision Drivers (:88-116):

- D1 "Judge written content, not future content. Any decision that reduces the artifact set must read a body that exists. A decision that cannot read a body must be about something other than whether a document would have been worth writing."
- D2 "Reachability is the first-order failure. The intended mechanism already exists once and is inert because `/scope` cannot reach it."
- D5 "Content that moves must be received and verified. A recommendation that content be carried forward is what already failed."

SKILL.md:372-398 states the same in `/scope`'s own voice: "Three documents that restate one problem at three altitudes cost a reader three reads for one idea, and an obvious concept articulated three times reads as ceremony. Sparing the reader that is worth doing, and it is the only reason `/scope` ever ends a run with fewer documents than the chain has altitudes. It is not a way to save the chain work. That distinction decides *when* the reduction can happen… An earlier revision of this skill decided per hop, before each artifact existed, whether the child was worth invoking; the party making that call was the one that benefited from not doing the work, and nothing it read could tell it what was being lost."

Two alternatives were considered and rejected, and both matter:

- END-OF-RUN SWEEP (DESIGN Decision 3 Option B / Decision 1 Option D): "Every downstream artifact has already cited a document that is about to disappear, so the re-pointing cascades across the whole set at once, and the author sees the reduction long after the conversation that justified it."
- ENTRY ALTITUDE CHOSEN ONCE IN PHASE 1 — this actually SHIPPED in an intermediate revision of this same PR and was then WITHDRAWN. SKILL.md:400-407: "A briefly-shipped revision of this skill also let Phase 1 choose an entry altitude for the chain. It was withdrawn. The question it asked the author was more answerable than the per-hop gates it replaced — which conversation are you having, rather than what would an unwritten document have said — but it was still a decision that shrank the artifact set before any artifact existed, and having two reduction mechanisms fire at different times meant neither read as the rule." Same account at phase-1-discovery.md:22-26 and DESIGN Decision 1 Option B.

Two consequences are stated deliberately rather than left implicit:

- SKILL.md:409-417 — "**A shorter chain is reached by invoking a child directly.** `/design <topic>` and `/plan <topic>` enter the tactical chain above `/brief`, which is what CLAUDE.md already tells authors to do when they know the altitude they want. `/scope` means 'walk the whole chain.' The consequence is that a `/scope` run ends with either all four artifacts or the chain minus an absorbed BRIEF, since no hop above BRIEF-to-PRD is absorbable."
- The durable-artifact floor is structural, with an explicit instruction against defensive code — phase-1-discovery.md:284-287: "Do not add a guard for this. Its condition cannot hold, and a check that can never fire teaches the next maintainer that the case is possible."

And SKILL.md:419-422 closes the loop on naming: "Anything held back for any other reason is re-entry protection — a settled artifact is already on disk and re-running would clobber it — and it is recorded under its own name so the two never blur again."

Recorded costs (DESIGN Consequences :759-776): the carry check is performed by the same agent that wrote both documents ("not an independent review"); two of the four artifact-set outcomes are unreachable through `/scope`; absorption has exactly one reachable hop; a DESIGN is now produced for every feature scoped at or above the design altitude, "including features with one live option"; and retiring `/brief`'s fold path removes a behavior direct-invocation users may have relied on.

### 7. Two facts from the PR body worth carrying into a design decision

(a) The PR DOGFOODED itself through `/scope` and `/execute`. On the brief→prd hop the mapping was total and stage 2 reached absorb, but the CARRY CHECK FAILED on User Journeys — "the PRD's six one-line user stories do not carry the four narrative journeys, each of which walks through the judgment's behaviour. The absorb aborted and both artifacts stayed. This is the abort path working, not a hop that was never considered." Both documents are on disk today. So the one reachable absorb hop has never actually completed in this repo. Verification reported: `cargo test --workspace` 555+25 pass; `shirabe validate docs --visibility=public` clean; scope evals 122/122 across 22 scenarios (baseline 61/122), brief 67/67, prd 74/74.

(b) ONE KNOWN GAP IS LEFT OPEN DELIBERATELY. The consolidation judgment fires when a hop's DOWNSTREAM artifact lands in this chain, and re-entry protection can prevent that: on a topic whose PRD is already settled, `/prd` is held back, so no PRD lands, so the brief→prd hop is never judged — while `/brief` still runs (no settled BRIEF on disk) and writes a fresh BRIEF whose framing the settled PRD already carries, with nothing to absorb it. The author's candidate fix is to widen `/brief`'s re-entry protection to also hold when a settled PRD exists at the canonical path, "not a judgment about an unwritten document, but the observation that a document which exists already holds the framing durably… It is a small change to one table plus a sentence, and it generalizes re-entry protection to 'a settled artifact already holds this content, so do not write it again.'" And the reason it was not made: "it adds a condition under which a child does not run, and that is the shape this branch just spent its effort removing. It wants a deliberate decision rather than my inference."

Also flagged open in the PR body: SKILL.md names `--no-coordinated` but not the per-default R18 override flag names, "so a coordinated run has to invent flag names."

## Implications

The overhaul is portable in shape but not in content. Everything that makes it work as a *pattern* — a constant `planned_chain:`, re-entry protection as the sole hold-back, reduction only after artifacts exist, the three-stage absorbability/judgment/carry-check, abort-toward-keeping, the PR-body durable record, upstream-path child invocation — is expressed without reference to BRIEF/PRD/DESIGN/PLAN. What is *not* portable is the payload: the absorbability table is derived from per-type required-section contracts, and the same derivation applied to VISION → STRATEGY → ROADMAP yields zero absorbable hops, which the DESIGN already computed and recorded (Decision 9).

That splits any parity work into two independent questions. The "always walk the chain, and name the only skip re-entry protection" half is directly applicable to `/charter` and is already half-done there (#252 made `/roadmap` ALWAYS with an author declination). The consolidation half would, today, install a mechanism whose only reachable verdict is `keep` — the DESIGN's stated reason not to port it.

The upstream-path invocation change is the sleeper. It is not framed as part of the consolidation story in the skill prose, but the DESIGN treats it as the first-order defect fix: children invoked in cold-start mode never recorded `upstream:` and re-derived their framing, which is *both* the cause of the repetition and the reason a carry check would fail. Whether `/charter`'s children are invoked with the artifact above them, or with a bare slug, is a question this research did not answer and which is orthogonal to consolidation.

Finally, the reduction mechanism is autonomous. Nothing about absorption is prompted; the author's only decision point is still Proceed / Adjust / Bail, and the entire audit trail rests on `consolidation_judgments:` being copied into the PR body before Phase 4 deletes the state file. Any parity design inherits that dependency: without the PR-body write, "absorbed" and "never produced" are indistinguishable on disk.

## Surprises

**(a) The one reachable absorb hop has never actually completed in this repo.** The PR dogfooded itself through `/scope`, reached `absorb` at stage 2 on the brief→prd hop, and then the per-section carry check FAILED on User Journeys — "the PRD's six one-line user stories do not carry the four narrative journeys, each of which walks through the judgment's behaviour." The absorb aborted and both artifacts stayed; `docs/briefs/BRIEF-scope-consolidation-over-skipping.md` and `docs/prds/PRD-scope-consolidation-over-skipping.md` are both on disk today. So the entire absorb-and-delete path — re-point `upstream:`, `git rm`, re-validate — has, as far as this repo's history shows, only ever been exercised as an abort. The PR body frames this positively ("This is the abort path working, not a hop that was never considered"), but it means the delete path is unproven in practice, and it is a live data point about how often a real PRD carries a real BRIEF's journeys.

**(b) Nothing generic was extracted into `references/parent-skill-pattern.md`.** That file is absent from the PR's diffstat entirely. Its Gate Vocabulary (references/parent-skill-pattern.md:113-172) still names exactly three shapes — ALWAYS, shape-dependent, Mandatory-with-auto-skip — and Mandatory-with-auto-skip is still described in terms of a child being skipped when "its durable artifact already exists at the published-Accepted status at the canonical path." The pattern layer therefore has NO NAME for re-entry protection as a thing distinct from a worth-judgment: the entire distinction that this overhaul exists to draw lives only in `/scope`'s own prose (phase-1-discovery.md:133-140, SKILL.md:419-422), not in the vocabulary every parent skill reads. PRD R18 explicitly forbade adding a fourth gate shape, so this was a deliberate constraint rather than an oversight — but the consequence is that another parent adopting the pattern inherits the old, ambiguous vocabulary and none of the disambiguation. The word "consolidation" and the field `consolidation_judgments` likewise appear nowhere under `references/`; a grep for `absorb|consolidat` there returns only unrelated hits.

Third, smaller: the SKILL.md prose narrates its own withdrawn revision. An entry-altitude selection shipped in an intermediate state of PR #260 and was withdrawn within the same PR, and the skill now carries a paragraph explaining why (SKILL.md:400-407) rather than simply not mentioning it. The reason given is that the withdrawn option was in some ways *better* than what it replaced ("the question it asked the author was more answerable than the per-hop gates it replaced") and was still rejected on the principle that no reduction may precede the artifacts — which makes the paragraph an unusually explicit guard against re-proposing it.

## Open Questions

1. Does `/charter` invoke its children with the upstream artifact's path or with a bare topic slug? The consumption half of this change is independent of consolidation and may be a live defect on the strategic chain; nothing in this research established which mode `/charter` uses.
2. Does `/charter` write a durable per-run record into its PR body the way `/scope` Phase 3 now does (produced / skipped-with-reason / absorbed-into-what)? Even with zero absorbable hops, the produced-vs-held-back record has value and may be absent.
3. Is `/charter`'s `/vision` auto-skip documented as re-entry protection or as a worth-judgment? Its Gate Vocabulary binding (skills/charter/SKILL.md:223) is Mandatory-with-auto-skip plus a thesis-shift override — the same shape `/scope` kept — but whether its surrounding prose makes the same disambiguation is unverified.
4. Should the generic half be lifted into `references/parent-skill-pattern.md` (a named "re-entry protection" concept, and a post-hoc-reduction slot), given PRD R18's prohibition was specifically on adding a fourth *gate shape* rather than on naming things?
5. What is the plan for the deliberately-open settled-PRD gap? The candidate fix — widening `/brief`'s re-entry protection to hold when a settled PRD exists — was left for a deliberate decision, and it is exactly the kind of change a parity effort might otherwise make casually.
6. The mapping table is a snapshot with an instruction to re-derive it from `crates/shirabe-validate/src/formats.rs` if any format changes. Nothing mechanically enforces that re-derivation. Is that acceptable, or does it want a test?
7. Two eval-harness defects the PR reported and did not fix: the pure-absence assertions pass in every baseline arm, and both consolidation scenarios hand over their own premise in the prompt so they tie at 100% in both arms. Any parity work that copies these scenario shapes inherits the weakness.

## Summary

PR #260 replaced `/scope`'s four produce-or-skip gates with a constant `planned_chain: [brief, prd, design, plan]`, leaving re-entry protection against clobbering a settled on-disk artifact as the only reason a child is ever held back, and retargeting the R6 predicates to size `/design`'s decision roster rather than decide whether it runs. Reduction moved to Phase 2 step 8, a per-hop consolidation judgment that reads the artifact that just landed and the nearest survivor above it, may absorb only where the downstream type's required sections have a home for every one of the upstream's (today BRIEF→PRD alone, derived from `formats.rs`), and completes an absorb only after a per-section carry check — any missing section aborts back to `keep`, and a completed absorb re-points `upstream:`, `git rm`s the file, and re-validates, with a validator failure reverting the whole thing. The enabling change is that children are now invoked with their upstream artifact's path instead of the bare topic slug, using input modes each child already ships, which is what makes a PRD actually consume its BRIEF and is why the reduction can be verified rather than merely recommended.
