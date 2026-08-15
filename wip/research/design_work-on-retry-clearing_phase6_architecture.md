# Phase 6 Architecture Review — DESIGN-work-on-retry-clearing

Reviewer: architecture juror. Method: read DESIGN + PRD + all touched koto-template/phase
files verbatim, then verified every checkable factual claim against real koto (installed
binary `/home/dgazineu/.tsuku/tools/current/koto`) and against koto's own Rust source
(`public/koto`, commit referenced by a fork agent as `16dbd34`), not against the document's
say-so.

## Strawman check

All three named rejected alternatives are presented at genuine strength, not caricatured.

- **`koto context remove`**: called "the strongest rival" and conceded nearly everything —
  `ContextStore::remove` really is a complete, uncalled trait method in both backends
  (verified: `src/session/context.rs:35`, impls in `local.rs:514` and `cloud.rs:861`/`920`,
  dispatch in `mod.rs:545`, zero callers outside its own definitions and unit tests). The
  design admits it would need no gate change and would leave shirabe's fixtures untouched.
  It loses purely on CI installing a *released* koto binary while local is `0.11.5-dev` —
  an ordering argument, not a quality one. Genuinely weighed.

- **Restructuring so no invalidation is needed**: labelled "unreachable, not merely
  unattractive" and backed with verified mechanics — a gate's `key:` is never
  variable-substituted at runtime (confirmed: only `g.command` is rewritten,
  `src/cli/mod.rs:3830-3840`), and koto's runtime variable set is a hardcoded two-entry list
  (confirmed: `RESERVED_VARIABLE_NAMES = ["SESSION_DIR","SESSION_NAME"]`,
  `src/cli/vars.rs:12`). This is a correct, checkable dismissal, not a strawman.

- **A `command` gate computing freshness**: explicitly called "the technically strongest
  mechanism on the table," and the design goes out of its way to retract its own earlier,
  weaker rejection reason ("that reason was wrong and is corrected here"). Its `ContextAdded`
  event / `docs/workspace-layout.md` / `docs/STABILITY.md` claims all verified true. It is
  rejected only because it leaves PRD requirements vacuous — an explicit trade-off the design
  says is the PRD author's call, not something it assumes for itself. This is the opposite of
  a strawman.

All three read as real losses on real grounds, not manufactured weaknesses.

## R1–R12 walk

Every requirement has a concrete architectural element behind it; none is vacuous.

- R1 (only real subcommands): mechanism uses only `add`/`get`/`exists` — all confirmed real;
  `remove` confirmed absent (`error: unrecognized subcommand 'remove'`, exit 2).
- R2 (invalidate all three re-entered artifacts): the identical retry block, looped over all
  three keys, lands on each phase's `blocking_retry` path.
- R3 (workflow enforces it): gate conversion referenced from the `passed` transition's `when`
  clause — koto-evaluated, not prose. (Residual: `koto overrides record` bypass, explicitly
  named by the design itself, not hidden.)
- R4 (failure exits stay reachable): `blocking_retry`/`blocking_escalate` transitions carry no
  gate reference in the current template today, and the design leaves them untouched.
- R5 (stdout diagnostic via read-back, not exit code): justified and verified — `koto context
  get` on a missing key really does exit 3 with a JSON error on stdout, and `koto context add`
  overwriting an existing key really can exit 3 *after the write has landed* (reproduced
  below). Exit-status branching would misreport a successful write as a failure.
- R6 (one contract, checkable by diff): byte-identical block across three phase files, one
  shared pattern in the template.
- R7 (true causality in prose): phase-4a-scrutiny.md today literally says "the gate will fail,
  prompting a fresh run" (line 44) — backwards, exactly as the design describes — and the
  design commits to rewriting it.
- R8 (first-pass behaviour frozen): keying on `"passed": true` rather than `"round"` is the
  only choice that accepts both shipped payload shapes unedited — confirmed against the actual
  heredocs (`scrutiny`/`review` write `round`; `qa_validation` does not).
- R9–R10 (real koto, shipped-text extraction): test plan follows the `/execute` precedent's
  extraction pattern, adapted correctly for the fact both blocks in each phase file now contain
  `koto context add` (marker changed to `blocking_retry`, correctly reasoned).
- R11 (clean compile): verified directly — compiling the template with all three gates
  converted to `context-matches` (both `type:` and the `when` key) still exits 0 with exactly
  one warning, W3, the same baseline `main` has today.
- R12 (evals updated and run): a `scrutiny-blocking-retry-entry` eval fixture already exists
  under `skills/work-on/evals/fixtures/scenarios/`, consistent with the design's plan to update
  it.

## Internal consistency — one confirmed defect

**The Implementation Approach's ordering justification is factually wrong**, though its
conclusion (steps 1 and 2 must land together) is still correct for a different reason.

The text claims: *"step 1 without step 2 gates on a value nothing writes."* I built the
actual partial state — the template with `scrutiny`'s gate converted to `context-matches`
with the anchored pattern and the `when` key changed to `gates.scrutiny_results.matches:
true`, but **no clearing step anywhere** (i.e., exactly "step 1 without step 2") — and drove
it through a real koto session on a real git repo:

1. First pass: wrote `scrutiny_results.json = {"passed": true, "round": 1, "blocking_count":
   0}`, submitted `passed` → advanced scrutiny → review correctly (R8 intact).
2. Simulated a `review` blocking finding: submitted `review_outcome: blocking_retry` with no
   `review_results.json` ever written (matches the phase files' actual "only write on a
   passing round" behaviour) → routed to `implementation`.
3. Advanced `implementation` → `scrutiny` again (second entry), touching nothing in context.
4. Read back `scrutiny_results.json`: still the untouched round-1 value.
5. Submitted `scrutiny_outcome: passed` **with no new write** → **the state advanced to
   `review`** — koto reported `advanced: true`, no blocking condition.

So step 1 alone does not starve on "a value nothing writes." It reproduces the *exact* bug
this design exists to fix: the stale round-1 artifact already contains `"passed": true`, so
it already satisfies the new anchored `context-matches` pattern, and a retry sails through
exactly as it does today — just via `matches: true` instead of `exists: true`. That is a
fail-*open* partial-deploy failure (silent, looks identical to success), not the fail-*closed*
one ("gates on a value nothing writes," implying everyone gets stuck) the sentence describes.
In a document whose entire thesis is the difference between fail-open and fail-closed
behaviour, getting this backwards for the one paragraph that argues for atomic landing is a
real defect, not a nitpick — though the fix is one corrected sentence, not a redesign, and it
does not change the recommendation to land both steps together (if anything it strengthens
it: the risk of splitting is silent bug-reproduction, not a loud block).

Everything else about the ordering claim holds. "Step 2 without step 1" (clearing sentinel
added, gate left as `context-exists`) genuinely does degrade to a prose-only guarantee: the
old `context-exists` gate only asks presence, and the sentinel is present too, so nothing
distinguishes a cleared-and-not-yet-rerun state from a passing one at gate-evaluation time.
That half of the claim is correct.

## The chosen mechanism, checked against real koto

- `context-matches` evaluates unanchored `Regex::is_match` (confirmed: `src/gate.rs:183`, no
  `^`/`$` applied by koto itself) — so the design's own `^...$` anchoring is exactly the
  load-bearing detail it claims to be, not decoration.
- The overwrite-and-read-back design for R5 is empirically justified, not just argued: I
  wrote a key, `chmod a-w` on the *ctx directory* (the `/execute` precedent's injection
  method), and overwrote the *same* key — the write landed (`get` returned the new value)
  despite `koto context add` reporting exit 3 (`"failed to create temp file in: .../ctx"`).
  Locking the *directory* does not block an overwrite of an *existing* file. I then
  `chmod 0444` on the key *file* itself — that genuinely blocked the overwrite (value stayed
  at the old content, same exit 3). This exactly and precisely confirms the design's claim
  that the test's injection must be `chmod 0444` on the key file, not a directory lock as the
  `/execute` precedent used, and confirms the R5 rationale that exit-status branching would
  misreport writes that landed.
- `agent_actionable: true` and the gate-name-in-response behaviour that `override_default`
  supposedly buys nothing extra for under `context-matches` — confirmed directly: my test
  template dropped `override_default` entirely from the converted `scrutiny` gate, and the
  blocked-gate response still carried `"agent_actionable":true` and named the gate, matching
  the design's claim that `built_in_default` already supplies this for `context-matches`.
- **Gate soundness taxonomy** ("six sound, six unsound," 12 `context-exists` gates total):
  independently reconstructed from the transition graph (all `target:` lines in
  `work-on.md`). The six claimed sound (`context_injection`, `setup_issue_backed`,
  `setup_free_form`, `plan_context_injection`, `setup_plan_backed`, `introspection`) are each
  reachable only from strictly upstream, acyclic paths — verified state by state. The six
  unsound (the three converted here, plus `plan_artifact` on `analysis` — reachable from
  itself via `scope_changed_retry` and from `implementation` via `scope_expanded_retry`;
  `summary_exists` on `finalization` — reachable in a cycle through `implementation` →
  `verification` back to `finalization`; and `summary_exists` on `deferral_approval`) all
  check out.
- **`deferral_approval`'s subtler instance**: verified precisely. Exactly one transition
  targets it (from `finalization` on `deferral_requested`), and nothing routes back into it —
  so the *state* is entered at most once per run, exactly as claimed. But `finalization`
  itself sits on a cycle (`finalization` → `implementation` → … → `verification` →
  `finalization`), and nothing forces `summary.md` to be rewritten between visits before a
  later visit routes to `deferral_approval`. `deferral_approval`'s own gate
  (`work-on.md:672`, `summary_exists`) only checks presence, so a `summary.md` from an earlier
  finalization pass silently satisfies it on the human-approval exit even if the
  code changed since. This is a real, correctly-reasoned edge case, and matches the design's
  claim about "the case that forced the separating rule to be about the key rather than the
  state."
- `plan_artifact` at `work-on.md:387` and `summary_exists` at `:633` — both line citations
  land on the `type: context-exists` line of the respective gate, consistent with the design's
  own citation style elsewhere.

## koto behaviour checks

- No `koto context remove`: confirmed, `error: unrecognized subcommand 'remove'`, exit 2.
- `koto template compile skills/work-on/koto-templates/work-on.md`: confirmed exactly one
  warning today — W3 (`skipped_due_to_dep_failure` looks like a failure state) — exit 0.
  Matches the PRD's stated baseline precisely.
- `scripts/check-template-interpolation.sh` exists in the **shirabe** repo (not koto, where a
  fork agent looked and correctly reported nothing found by that name) and behaves exactly as
  the design describes: it scans only `command:`/`working_dir:` fields, strips `{{KEY}}`
  refs, and flags bare `$NAME`/`${NAME}` while explicitly allowing `$(...)`. Confirmed by
  reading the script.
- The "two JSON shapes" residual-risk claim in Consequences is precisely accurate:
  `phase-4c-qa.md`'s tester-return JSON (`scenarios_run`/`scenarios_passed`/`scenarios_failed`,
  no `passed` key) versus its context-write heredoc (`passed: true` plus
  `scenarios_run`/`scenarios_passed`) are genuinely two different shapes in the shipped file
  today.
- `context_assignments:` really is a silent no-op: `Transition` (`src/template/types.rs:135-
  140`) carries only `target`/`when`; the nested transition parser doesn't deny unknown keys,
  so a `context_assignments:` block is dropped by serde before it ever reaches the compiled
  struct. Confirmed by source, not assumed.

## Blast radius

The PRD scopes to three retry-bearing phases plus the shared orchestration summary; the
design's change set doesn't reach further than that. The "six files change" framing in
Solution Architecture is a slight undercount if read literally: by my count the template, the
three phase files, `review-panel-orchestration.md`, and the regenerated
`work-on.mermaid.md` are six *modified* files, but `scripts/check-bash-floor.sh` also gets a
new suite registered (a seventh modified file) alongside two genuinely new files
(`retry-clearing_test.sh`, `check-work-on-scripts.yml`). This is a minor imprecision in a
summary count, not a scope problem — every touched file maps directly onto a PRD requirement
(R6/R7 → phase files and orchestration doc; R9–R11 → template and mermaid; R9/R10/R12's test
demands → the new test script and its CI wiring). The three other latent instances of the same
defect class (`plan_artifact`, `summary_exists` ×2) and the `context_assignments` no-op are
explicitly named and explicitly deferred, which is scope discipline, not scope creep.

## Verdict basis

One confirmed, non-trivial factual error (the ordering-justification sentence in
Implementation Approach mischaracterizes step-1-alone as fail-closed when it is empirically
fail-open) in a document that otherwise verifies almost perfectly against real koto behaviour
and real koto source across a large number of independently checked claims. The error doesn't
change the architecture, the file list, or the recommendation to land both steps together —
but it is exactly the kind of claim this document's own credibility model depends on getting
right, and the rubric explicitly asked this claim be checked. Blocking, with a one-sentence
fix.
