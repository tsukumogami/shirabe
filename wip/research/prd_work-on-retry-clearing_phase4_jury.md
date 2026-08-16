# Phase 4 Jury: PRD-work-on-retry-clearing

Document: docs/prds/PRD-work-on-retry-clearing.md
Upstream: docs/briefs/BRIEF-work-on-retry-clearing.md
Rubric: skills/prd/references/prd-format.md

## Fact-check log

1. Twelve context-exists gates in work-on.md, of which six are re-entrant
   and six are sound (single-entry). Traced the full transition graph in
   skills/work-on/koto-templates/work-on.md:
   - Sound (6): context_injection (context.md), plan_context_injection
     (context.md), setup_issue_backed (baseline.md), setup_free_form
     (baseline.md), setup_plan_backed (baseline.md), introspection
     (introspection.md). Each has exactly one incoming transition path.
   - Re-entrant (6): scrutiny (scrutiny_results.json, re-entered via any of
     the three panels' blocking_retry -> implementation -> scrutiny, since
     implementation forwards unconditionally to scrutiny on
     complete+issue_type:code), review (review_results.json, re-entered
     whenever the retry originated at review or qa_validation, since both
     route back through scrutiny -> review), qa_validation
     (qa_results.json, re-entered only by its own blocking_retry), analysis
     (plan.md, re-entered via implementation's scope_expanded_retry ->
     analysis transition, distinct from analysis's own scope_changed_retry
     self-loop), finalization (summary.md, re-entered via its own
     issues_found -> implementation -> ... -> verification -> finalization
     cycle), deferral_approval (summary.md, single incoming transition from
     finalization, but finalization sits on the same cycle so the one entry
     can carry a stale summary.md from an earlier round of that cycle).
   VERIFIED — matches the PRD's table and the BRIEF's journeys exactly.

2. `koto context exists` (src/cli/context.rs `handle_exists`) and the
   `context-exists` gate evaluator (src/gate.rs
   `evaluate_context_exists_gate`) both call `store.ctx_exists(session,
   key)`, and the local backend's `ctx_exists` (src/session/local.rs:578)
   is a single `content_path(session, key).exists()` filesystem check.
   VERIFIED — same predicate, same underlying check.

3. Failed removal on an unwritable store leaves the key present and the
   gate satisfied. Empirically probed with a real koto binary (the one
   pinned on PATH, ~/.tsuku/tools/current/koto): created a session, added
   a context key, chmod 555'd the session's ctx directory, ran `koto
   context remove` (exit 3, "failed to remove content file"), then ran
   `koto context exists` on the same key (exit 0 — still present). Content
   file was confirmed still on disk afterward.
   VERIFIED — directly reproduces the PRD's R3 justification. Also
   confirmed by code reading that `remove` deletes the content file first,
   then the (best-effort) per-key lock file, then updates the manifest
   under lock (src/session/local.rs ~585-621) — consistent with the
   Decisions and Trade-offs claim about ordering, though the narrower
   "content already gone but exit code still non-zero via manifest
   failure" sub-case wasn't independently forced (would require
   interleaving that chmod can't isolate); it's a plausible corollary of
   the code path, not directly counter-tested.

4. `koto context remove` on a key that was never written exits 0
   (idempotent) — matches `--help`'s "idempotent: succeeds if already
   absent" and was reproduced directly (exit=0, followed by `exists`
   exit=1).
   VERIFIED.

5. The two block-quoted passages in the BRIEF, both attributed to
   phase-4a-scrutiny.md:
   - "Do not try to delete it. `koto context` advertises `add`, `get`,
     `exists`, and `list` — koto has no verb that removes a key." — exact
     substring of phase-4a-scrutiny.md line 48.
   - "what keeps an earlier pass from advancing the workflow is the
     `scrutiny_outcome` you submit, which must always describe the round
     that just ran." — exact substring of phase-4a-scrutiny.md line 52.
   VERIFIED — both verbatim.

6. `grep -c "koto has no verb that removes a key" skills/` today returns 1
   (only in phase-4a-scrutiny.md). The AC expecting 0 would fail today and
   pass only once that sentence is corrected. VERIFIED — meaningful AC.

7. The other five phase files named in R8/R9 (phase-4b-review.md,
   phase-4c-qa.md, phase-3-analysis.md, phase-5-finalization.md,
   review-panel-orchestration.md) currently contain no clearing/retry
   prose at all. VERIFIED — matches "the other five gates have no such
   prose."

8. `.tsuku.toml` pins `"tsukumogami/koto" = "latest"`. VERIFIED.

9. koto on PATH exposes `context remove` with help text "idempotent:
   succeeds if already absent," and `koto template compile` exists as a
   subcommand. VERIFIED (installed binary; version string unlabeled but
   command surface matches the PRD's description).

No factual claims were found to be wrong. 9/9 checked claims verified
(one, #3, verified for its primary assertion with a narrower corollary
left as code-inspection-only rather than independently forced).

## Role 1 — Completeness

Required sections present and in canonical order: Status, Problem
Statement, Goals, User Stories, Requirements, Acceptance Criteria, Out of
Scope, then optional Known Limitations and Decisions and Trade-offs. All
BRIEF journeys and Scope-Boundary items map onto a requirement or an
explicit Out-of-Scope entry (checked line by line against the BRIEF).

Gap found: **R6 has no acceptance criterion that would catch its
violation.** R6 says the failure exits (blocking_retry, blocking_escalate,
and "the equivalent exits at analysis and finalization") must stay
reachable when the context store is broken. The AC list covers the
clearing step's own failure behavior (exits non-zero, stdout diagnostic,
names the outcome not to submit) but nothing exercises whether the
*workflow's escape hatches* still function once clearing has failed — e.g.
an implementation that made clearing a hard precondition for calling `koto
next` at all would violate R6 (bricking the run) without failing any listed
AC. This is a real hole given R6 exists specifically to prevent a bricked
run.

Minor: two ACs (`cargo test --workspace` passes with no existing test
modified; `shirabe validate --lifecycle`) are general process/regression
bars rather than traceable to a specific R-number — standard boilerplate
in this shop's PRDs, not a defect.

No DESIGN-level architecture or task breakdown found in Requirements or
Acceptance Criteria. The Decisions and Trade-offs section does describe
koto's internal removal ordering (content file, then lock, then manifest)
to justify R3's verification choice — this is citing a dependency's
existing behavior to justify a requirement, not prescribing this PRD's own
implementation, so it's within bounds, if close to the line.

Problem Statement stands alone: a cold reader gets the twelve-gate count,
the six re-entrant cases with their re-entry paths, the phase-4a-scrutiny
quotes, and why the koto capability claim is now false, without needing
the BRIEF.

**Verdict: FAIL** (one blocking gap: R6 untested by any AC).

## Role 2 — Clarity

Goals are outcome-shaped ("the refusal becomes structural," "every gate...
is cleared," not implementation steps). R1/R2 split is clear: R1 names
which keys are removed on which transition; R2 states the covering
principle (clear every key the re-entry will re-read, not just the raising
phase's). User Stories use real, distinct roles and each maps to a
different requirement cluster.

Two clarity issues:

1. **R6's "equivalent exits at analysis and finalization" is unnamed.**
   Analysis's failure exits are `scope_changed_escalate` and
   `blocked_missing_context` (both to done_blocked) — plausible candidates,
   but not stated. Finalization has no direct panel-style escalate at all
   (only `issues_found` looping back, and the human gate at
   deferral_approval) — it's genuinely unclear which finalization
   transition R6 means. Two competent implementers could reach different
   conclusions about what R6 requires to remain reachable at finalization.
   Combined with the completeness gap above (no AC), this requirement is
   the document's weakest spot.

2. **The BRIEF's "review or below" framing survives into the PRD's table
   only implicitly.** The table's "Re-entered via" column for
   `review_results` says "a retry raised at `review` or below" — "below"
   means downstream in the panel sequence (i.e., qa_validation), which is
   correct once traced against the template but reads ambiguously in
   isolation (could be misread as "escalation severity" rather than
   pipeline position). Not likely to cause an implementation error since
   R1/R2 spell out the concrete removal behavior elsewhere, but it's a
   readability friction point.

Prose vocabulary and formatting checked against
skills/writing-style/rules.yaml: no banned words/phrases found (robust,
leverage, comprehensive, holistic, facilitate, utilize, seamless, delve,
showcase, boast — none present). Em dash count is 6 across ~2,196 words
(~2.7 per thousand), well under the 10-per-thousand density threshold, so
no formatting-tell violation despite the document using em dashes
routinely. Contractions and varied sentence/paragraph length are present
throughout. `tier`/`journey`/`underscore` (shirabe's declared terms of
art) do not appear in this document, so the declaration is moot here.

**Verdict: FAIL** (R6's unnamed "equivalent exits" is a genuine two-reader
divergence risk, not just a style nit).

## Role 3 — Testability

Per-AC mechanical check and fail-on-main verification:

- Six gates, key removed -> doesn't advance, gate named in koto's response:
  checkable via `koto next <WF> --with-data ...` after `koto context
  remove`, asserting non-zero/blocked and inspecting koto's structured
  gate output. FAILS on main today (no removal step exists anywhere in the
  phase files, so nothing ever removes the key — the scenario as stated
  can't even be set up without a hand-run `koto context remove`, and once
  set up, main's gate behavior is exactly what's being tested as wrong).
  Meaningful.
- Six gates, key present -> advances (first-pass unchanged): this AC
  encodes R7 ("first-pass behaviour is unchanged"), and by construction it
  already holds on today's main — main's gates already advance when the
  key is present. It does not discriminate old vs. new behavior; it's a
  non-regression guard, which is the correct AC shape for a "nothing
  changes here" requirement, but reviewers should not expect it to fail
  pre-fix.
- Traversal ACs (qa_validation retry clears all three panels; same from
  review and scrutiny; scope_expanded_retry clears plan.md; finalization
  issues_found clears summary.md): all FAIL on main (nothing removes
  anything today) and would PASS only once R1/R2 are implemented.
  Mechanically checkable by scripting the koto session through each path
  and asserting `koto context exists` per key at each checkpoint.
  Meaningful.
- Clearing step exits 0 on a never-written key: FAILS on main (no clearing
  step exists to run). Confirmed independently that koto's own `remove` is
  idempotent (exit 0 on absent key, verified by direct probe), so the
  underlying primitive supports this AC; the AC is about the phase files'
  shell block, not koto itself.
- Unwritable store -> clearing step exits non-zero, stdout diagnostic
  naming the key, stderr redirected to /dev/null, names the outcome not to
  submit: FAILS on main (no clearing step exists). Directly reproduced the
  underlying koto behavior this AC depends on (unwritable ctx dir -> `koto
  context remove` exit 3, diagnostic on stdout as JSON error, `koto
  context exists` still reports the key present) — the AC's premise is
  real and the mechanism to build the check on top of is confirmed
  present.
- Verification is `context exists`, not removal's exit status, checked by
  extracting the shipped block: mechanically checkable (grep/parse the
  phase file's clearing block for `koto context exists` rather than
  branching only on the remove command's `$?`). FAILS on main (no block to
  extract).
- `grep -c "koto has no verb that removes a key" skills/` returns 0:
  returns 1 today (verified). FAILS on main, PASSES after. Meaningful,
  trivially mechanical.
- Phase files state the re-entry contract (five named files): checkable by
  grep/manual read for each file; all five currently have no such prose
  (verified). FAILS on main.
- review-panel-orchestration.md states retry removes all three panel
  artifacts: verified absent today. FAILS on main.
- `git diff` shows no change to work-on.md: **judgment call requested.**
  This AC can't fail against literal "today's main" in the framework's
  sense, because before any implementation commits exist there is no diff
  at all to inspect — the check is vacuously true at t=0 for lack of a
  subject, not because the property it's guarding is already satisfied
  under load. It becomes meaningful only once the implementation branch
  exists: it is a real constraint on that diff (it will fail if the
  branch touches work-on.md, pass if it doesn't), directly enforcing R5.
  So: not vacuous as a merge-time gate, but it doesn't fit "fails on main,
  passes after" — it's a boundary check on the PR's own diff, evaluated
  once, not a before/after regression test. Also under-specified: the AC
  doesn't name the diff base (`git diff main -- skills/work-on/koto-templates/work-on.md`
  vs. bare `git diff` in a dirty working tree) — two implementers could
  run different commands and both call themselves compliant.
- `koto template compile ... exits 0 with no new warning relative to
  main`: mechanically checkable (compile on main, compile on branch,
  diff warning output). Since R5 keeps work-on.md untouched, this should
  already exit 0 with the same output on both — reasonable as a
  regression guard tied to R5, same category as the `git diff` AC above
  (verifies "unchanged," so it doesn't discriminate pre/post either, by
  design).
- Test extracts clearing block from shipped phase files at runtime; a
  broken block fails the test: FAILS on main (no such test, no such
  block). Meaningful and directly maps to R11's anti-drift intent.
- `cargo test --workspace` passes, no existing test modified: standard
  regression bar, mechanically checkable, not itself specific to this
  PRD's behavior.
- `scripts/run-evals.sh work-on` run and reported: confirmed the script
  exists (scripts/run-evals.sh, skills/work-on/evals/evals.json present).
  Process AC, mechanically checkable (command exists, exit code +
  transcript reportable).
- `shirabe validate --lifecycle . --mode=ready` exits 0: standard
  finalization gate, mechanically checkable.

Summary: the great majority of ACs are correctly discriminating (fail
today, pass only after the fix) and each names or clearly implies its
verification command. Two categories of AC are "unchanged" guards (key
present -> advances; template compile has no new warning; git diff shows
no change) that by design already hold or vacuously hold on main — that's
appropriate given they encode R5/R7, not a flaw, but they don't
discriminate pre/post and shouldn't be read as evidence the fix works.
The `git diff` AC additionally needs its diff base named to be
unambiguously mechanical.

**Verdict: PASS** (advisory notes on the "unchanged" ACs and the git diff
base; nothing here blocks — the discriminating ACs that matter for R1-R4
and R8-R11 are all real and correctly fail on main today).

## Summary counts

- Fact-check: 9 claims checked, 9 verified, 0 wrong.
- Completeness: FAIL (R6 has no AC).
- Clarity: FAIL (R6's "equivalent exits" unnamed; minor "review or below"
  ambiguity).
- Testability: PASS (advisory notes only).
