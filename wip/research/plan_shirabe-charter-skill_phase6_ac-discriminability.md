# Phase 6 Review — Category C: AC Discriminability

## Reviewer

`reviewer-ac-discriminability` (Phase 6 fast-path, single reviewer)

## Inputs Read

- `wip/plan_shirabe-charter-skill_issue_1_body.md` through `_issue_10_body.md` (all 10 issue bodies)
- `docs/designs/DESIGN-shirabe-progression-authoring.md`
- `docs/prds/PRD-shirabe-charter-skill.md`
- `wip/plan_shirabe-charter-skill_analysis.md`
- `wip/plan_shirabe-charter-skill_manifest.json`
- `public/shirabe/skills/review-plan/references/phases/phase-3-ac-discriminability.md`

## Category

C — AC discriminability

## Verdict

**PASS**

Across all 10 issue bodies, the acceptance criteria are sufficient to discriminate between correct and plausibly-wrong implementations. The pattern pass (Patterns 1, 3, 7) produces no findings. The adversarial pass (Patterns 2, 4, 5, 6) produces no findings. Critical-complexity issues (5, 6, 7) ship substantive Security Checklists rather than single-line boilerplate.

## Pass 1 — Pattern Pass

### Pattern 1 — Fixture-anchored

No matches. Issue 9 uses scenario pre-population for eval scenarios (us-2, us-4), but the same file contains explicit clean-state scenarios (`baseline-slug-rejection`, `baseline-malformed-state`, `us-1-cold-standalone-full-run` invokes against a fresh worktree with no artifacts), satisfying the clean-state requirement. No flag.

### Pattern 3 — Happy-path only (per-issue check)

Each issue body except Issue 10 contains at least one failure/error/edge-case AC:

- Issue 1: documents "I-6 as the v1 core-layer implementation explicitly does NOT satisfy" (negative space invariant); "malformed-state-file error mode named for the shared eval baseline" AC; documents what counts as "internals" (negative examples).
- Issue 2: "rejected at Phase 0 with a clear error", "violated pattern", "MUST NOT proceed silently when the slug is invalid", three concrete rejection examples (`MyTopic`, `my_topic`, `my.topic`, `Hello World`).
- Issue 3: "MUST NOT detect, warn against, or otherwise interfere"; visibility-default warning; literal failure-language about missing `## Repo Visibility:` header.
- Issue 4: "silently skip", "byte-identical", "MUST NOT be passed a STRATEGY path", `/comp` substring absence checks, skip-listing discipline.
- Issue 5: full R9 hard finalization check with four enumerated failure modes; "MUST be absent" gating; malformed-state hard-error framing.
- Issue 6: malformed-state hard error + Discard recovery; "MUST NOT silently fall through to Phase 0" (AC20c); drift detection; staleness three-option prompt; "MUST NOT contain `Continue / Start fresh`" negative substring.
- Issue 7: clean-cancel fallthrough (step 3 of tie-break); "MUST be ABSENT for abandonment-forced"; R9 conditional-field gating; Reject-vs-Bail distinction; AC18b non-retroactivity.
- Issue 8: "MUST NOT introduce a new required section" (validator preservation); validator error surfacing; public-repo content gating.
- Issue 9: `baseline-malformed-state`, `baseline-slug-rejection`, `baseline-child-internals-isolation`, manual-fallback non-interference scenarios.

**Issue 10**: This is a CLAUDE.md docs-only surfacing where every AC is a literal-substring presence check (`mentions /charter`, `contains "start a strategic conversation"`, etc.). The failure mode for a presence-check AC is "substring absent" — the AC itself IS the discriminating test (a grep that fails the negation). The issue body lacks explicit failure-keyword language because the issue has no behavioral surface beyond substring presence in a single markdown file. Per the Phase 3 spec's ambiguity guard ("uncertain matches produce no finding"), this is not a Category C defect: the implementation surface admits exactly one failure mode (substring absent) and the ACs cover it. No finding.

### Pattern 7 — Existence-without-correctness

No matches. Every "exists" AC in every issue is immediately paired with content-verification ACs:

- Issue 1: each `references/parent-skill-*.md exists` line is followed by section-name + named-content ACs (e.g., "documents I-1 through I-6 by name", "names all three exit paths", "contains a `Conditional Feeder Invocation Shape` section that names the three-condition gate").
- Issue 2: each `SKILL.md exists` / `phase-0-setup.md exists` is followed by frontmatter-field, section-header, literal-regex, and literal-substring ACs.
- Issue 5: each field name in the schema is enumerated with type, semantics, and gating condition.
- Issue 8: each template-file existence AC is paired with named-section, named-alternative, literal-substring ACs.
- All other issues follow the same discipline.

No bare existence claims without content assertions.

## Pass 2 — Adversarial Pass

### Pattern 2 — Mock-swallowed

No matches. The only dependency-test surface is Issue 9's `scripts/run-evals.sh charter` eval-runner pass requirement. The runner executes against real shipped state (real files, real `/charter` invocations); there are no mocked dependencies in the contract. The eval scenarios themselves construct concrete fixtures (Accepted STRATEGY file, malformed state file, ≥7d-old `last_updated`) and assert against the real artifacts produced.

### Pattern 4 — State-without-transition

No matches.

- Issue 5's R9 finalization check ACs name the transition (finalization-time procedure) AND the resulting state assertions. The check is explicitly bound to the transition that produces the state.
- Issue 7's abandonment-forced ACs enumerate the four triggering conditions (the transitions) and the state-field assignments. Not a state-only AC set.
- Issue 9's us-3b scenario "mock `last_updated` to be `≥ 7d` old" sets initial state then drives the resume-ladder transition (Force-materialize selection) and asserts the produced state. Transition is in the assertion set.

### Pattern 5 — Integration scope gap (with false-positive guard)

No matches.

- Issue 4 AC for `/comp` byte-identical Public-vs-private-without-`/comp` chain proposal output: the prose-level AC asks the file not to leak `/comp` substrings in prompt-output prose; the runtime byte-identical assertion lives in Issue 9's evals (us-1 covers Public, and the baseline scenarios cover absence). Each layer has the right scope.
- Issue 6 AC20 (status-aware re-entry suppression, manual-review for prompt-vocabulary) and AC20b (R14 child-internals isolation, manual-review for code-path inspection) are explicitly typed as manual-review against the prose. The ACs name the discipline ("prose enumerates the three permitted sources... and the prohibited sources") in observable terms (`grep` plus reviewer inspection of enumerated lists). Not flaggable.
- Issue 7 AC11a/AC11b (full-run exit-artifact entry counts) are asserted both in Issue 7 prose (state-field assignments) and Issue 9 eval (us-1) runtime. Integration coverage matches scope.

### Pattern 6 — Interface name drift

No matches. Cross-checked names that appear in ACs against the design and PRD:

- `parent-skill-pattern.md`, `parent-skill-state-schema.md`, `parent-skill-resume-ladder-template.md`, `parent-skill-child-inspection.md` — match design Component 1 and PRD.
- State-file field names (`topic`, `chain_started`, `chain_completed`, `last_updated`, `planned_chain`, `chain_ran`, `chain_skipped`, `exit`, `decision_record_sub_shape`, `exit_artifacts`, `child_snapshots`, `referenced_strategy`, `discard_commit_sha`, `rejection_rationale`, `triggering_child`, `partial_phase_reached`) — match PRD R10 verbatim.
- Exit values (`full-run`, `re-evaluation`, `abandonment-forced`) and sub-shapes (`re-evaluation`, `rejection`) — match PRD R8.
- Substitution surfaces (`storage_substrate`=`wip-yaml-md`, `team_primitive`=`single-team-per-leader-no-nested`) — match design Decision 2.
- Resume-ladder vocabulary (`Re-evaluate`, `Revise`, `Bail`, `Continue / Start fresh` negative, `Re-run`, `Accept`, `Proceed without`, `Resume / Force-materialize / Discard`, `Proceed / Adjust / Bail`) — match PRD R7.5, R11, AC18, AC19, AC17.
- Phase-reference filenames cited across issues (`phase-0-setup.md`, `phase-1-discovery.md`, `phase-2-chain-orchestration.md`, `phase-resume.md`, `phase-state-management.md`, `phase-finalization.md`) — internally consistent and referenced symmetrically from SKILL.md (Issue 2) and the citing phase files.

No drift detected.

## Coordinator's Special-Attention Items

### Issue 1 (~30 ACs across 4 reference files)

Verdict: discriminating. Each content AC names a specific section, term, or invariant — no bare "contains all required content" framings. Examples of well-discriminated ACs:

- "documents I-6 as a pattern invariant the v1 core-layer implementation explicitly does NOT satisfy" — grep-verifiable against I-6 paired with "not satisfy" / "unsatisfied" language.
- "contains a `Conditional Feeder Invocation Shape` section that names the three-condition gate: (1) parent-defined Phase 1 discovery signal fires, (2) the feeder skill exists on disk, (3) parent-defined visibility gate passes" — three-part content assertion.
- "names both substitution surfaces: `storage_substrate` (with v1 value `wip-yaml-md`) and `team_primitive` (with v1 value `single-team-per-leader-no-nested`)" — literal-value assertions.

### Issue 4 (chain-proposal literals + /comp Public-repo silence)

Verdict: discriminating, with the runtime byte-identical guarantee delegated to Issue 9's eval. The prose-level ACs in Issue 4 are grep-verifiable for the positive case (Proceed/Adjust/Bail substrings present) and the negative case (no `/comp` substring in `phase-1-discovery.md`; chain-orchestration prose may name `/comp` for internal logic only). The fuzzy boundary between "logic doc that names /comp" and "prompt-output prose that emits /comp" is handled by routing the runtime byte-identical check to Issue 9 (`baseline-visibility-default` and `us-1-cold-standalone-full-run` cover Public-repo invocations). This is the right scope decomposition.

### Issue 6 (resume-ladder negative space)

Verdict: discriminating. The negative-space AC "Row 5 prose MUST NOT contain the substring 'Continue / Start fresh' inside the row-5 prose block" is paired with a file-level grep enforcement in the Validation script (`if grep -qE 'Continue / Start fresh' ...; then exit 1`). The AC framing pairs the positive substrings (Re-evaluate, Revise, Bail) with the negative (Continue / Start fresh). A plausible wrong implementation that lets `/strategy`'s vocabulary leak into Row 5 prose would fail the grep.

### Issue 7 (Reject-vs-Bail distinction)

Verdict: discriminating. AC18b context is documented in prose ("the file states that outside a `/charter` chain... `/charter` does NOT retroactively produce a rejection Decision Record"). The state-field assignments differ per exit (rejection sub-shape requires `discard_commit_sha`, `rejection_rationale`; abandonment-forced requires `triggering_child`, `partial_phase_reached`; full-run requires neither). A mis-routing implementation that collapses Reject into Bail would produce wrong state-field assignments and fail the AC for the conflated path. Issue 9's `us-3a-rejection-sub-shape` and `us-3b-abandonment-forced` evals exercise the runtime distinction. The Issue 7 ACs additionally require a dedicated section heading distinguishing the two paths, which a grep can verify.

### Issue 8 (Decision Record body content rules per sub-shape)

Verdict: discriminating. Each body-content rule is named as a literal substring requirement:

- Re-evaluation: "the `## Options Considered` section's placeholder names both `revise the STRATEGY` AND `force-abandon and rewrite` as rejected alternatives (each MUST be present as a literal substring in the template)" — directly grep-verifiable.
- Rejection: "the `## Options Considered` section's placeholder names both `accept the Draft` AND `revise instead of reject` as rejected alternatives".
- Re-evaluation Context cites `referenced_strategy:` (grep target).
- Rejection Context cites `discard_commit_sha:` (grep target).

The Validation block in Issue 8 has explicit `grep -qF "revise the STRATEGY"`, `grep -qF "force-abandon and rewrite"`, `grep -qF "accept the Draft"`, `grep -qF "revise instead of reject"`, `grep -qF "discard_commit_sha"`, `grep -qF "rejection_rationale"` checks. A wrong implementation that omits one named alternative would fail.

## Security Checklist Substantiveness (Critical Issues 5, 6, 7)

All three critical issues ship substantive Security Checklists rather than single boilerplate items.

- **Issue 5** (8 items beyond `Security review completed`): durable-evidence warning for public-repo `wip/` exposure; secret/customer-context prohibition in free-text fields; R9 fail-closed for missing/invalid `exit:`; topic-slug regex validation (no path traversal); conditional-field absence-when-not-applicable (schema confusion prevention); no third-party deps; documentation-only file scope.
- **Issue 6** (9 items): READ-ONLY `git hash-object`; ladder source enumeration (R14 isolation); malformed-state fail-closed; status-aware re-entry suppression; no third-party deps; state-file metadata-not-content (no body leakage); 7-day stale-session bounding; R14 child-internals isolation (AC20b); US-3a manual-fallback non-retroactivity.
- **Issue 7** (9 items): three-exits invariant; tie-break clean-cancel fallthrough preventing incomplete state writes; Reject-vs-Bail distinction; read-only `git log` (no `/charter` git writes); `rejection_rationale` opaque-text handling; AC18b enforcement; R9 conditional-field gating; no third-party deps; public-repo durable-evidence surface for state-file content.

No boilerplate single-line checklists detected.

## Findings

`critical_findings: []`

No Category C findings. The plan is discriminating.

## Loop-Back Target

N/A (verdict is PASS).
