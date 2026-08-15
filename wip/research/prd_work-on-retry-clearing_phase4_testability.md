# Testability Review — PRD-work-on-retry-clearing

Reviewer: testability juror, /prd Phase 4. The PRD was revised mid-review
(R2 broadened to invalidate all three panel artifacts on any retry, R1 made
mechanism-neutral, R6 tightened, and "Traversal" ACs added); this report is
against the current text on disk.

## Method

Read `docs/prds/PRD-work-on-retry-clearing.md` against
`skills/prd/references/prd-format.md` Quality Guidance (Requirements,
Acceptance Criteria). Verified claims against the actual repo state:

- `git diff main -- skills/work-on/` is empty on this branch (only the PRD
  and a wip state file changed), so everything read under `skills/work-on/`
  below is `main`'s current text.
- `koto context --help` -> subcommands are exactly `add|get|exists|list`.
  `koto context remove --help` exits **2** ("unrecognized subcommand"), not
  0 — confirms AC1's mechanical check ("`koto context V --help` exits 0")
  correctly fails for `remove` today.
- `koto context add` overwrites an existing key silently and exits 0
  whether or not the key existed before; `koto context exists` on a missing
  key exits 1 cleanly (not an error). Together these confirm the "not an
  error" edge case in R2/AC5 (invalidating a key that hasn't been written
  yet) is achievable today with the existing four verbs — the requirements
  aren't asking for something koto can't currently do.
- `skills/work-on/references/phases/phase-4a-scrutiny.md` still contains,
  verbatim, "Delete the stale artifact from context before re-running:
  `koto context remove <WF> scrutiny_results.json`" on `main` today.
  `phase-4b-review.md` / `phase-4c-qa.md` have no invalidation step at all.
  `review-panel-orchestration.md` says nothing about invalidation. All
  confirm the Problem Statement's factual claims and give every
  `main`-state-dependent AC below real discriminating power.
- `koto-templates/work-on.md`: all three phases declare one
  `context-exists` gate on the round's results key, and only the `passed`
  transition's `when` clause references it; `blocking_retry` /
  `blocking_escalate` fire on the outcome value alone, unconditional on
  gate state.
- Built and compiled a scratch template using `type: context-matches` (key
  + `pattern`) — confirmed this gate type exists and compiles, so the
  "replacement with a value the gate rejects" mechanism named in R2 is a
  real, available primitive.
- `koto context get <wf> <missing-key>` writes a JSON error to **stdout**
  and exits 3 — confirms R5's claim precisely.
- `koto next <wf> --with-data ...` on a failing gate returns JSON with
  `"advanced": false` and a `blocking_conditions[]` entry naming the gate
  by name and `"status": "failed"` — confirms AC3's "koto's response names
  the phase's gate as the failing condition" is real, machine-parseable
  behavior.
- `koto template compile skills/work-on/koto-templates/work-on.md` today
  emits exactly one warning (W3, on `skipped_due_to_dep_failure`).
  `spawn_and_await` (the state the PRD's Out-of-Scope W4 note names)
  doesn't exist in `work-on.md` — it's an `execute.md` state. The
  Out-of-Scope bullet mislabels the file for a note attached to
  R11/the compile AC, which is scoped to `work-on.md`. Doesn't affect the
  AC's own mechanics (it's a self-contained before/after diff) but could
  mislead someone establishing the "before" baseline by hand.

## Per-AC assessment (current AC list)

1. **For every verb `V` in a `koto context V` instruction under `skills/`,
   `koto context V --help` exits 0.** Mechanical and confirmed to
   discriminate (`remove --help` exits 2 today). The PRD itself flags the
   one soft spot: "Prose citing a verb to describe a defect is excluded,
   which is a judgment the reviewer makes against each hit rather than a
   property of the grep" — this is honest about being a bounded judgment
   call, not a hidden gap. Advisory only.
2. **`phase-4a-scrutiny.md` contains no instruction to run `koto context
   remove` unless that subcommand exists.** Mechanical (grep + version
   check), largely redundant with #1 but harmless.
3. **Invalidated artifact -> `passed` doesn't advance, gate names itself
   as the failing condition.** Confirmed mechanical (JSON field check).
   Previously this AC was ambiguous about whether "invalidated" had to be
   produced via the phase's real invalidation step — **that gap is now
   closed by AC6** (below), which requires the invalidation to be
   extracted from the shipped block and shown to run on the same path as
   the `blocking_retry` submission.
4. **Traversal.** After `blocking_retry` raised in `qa_validation`, neither
   `scrutiny` nor `review` advances on `passed` until each has a fresh
   artifact, exercised as a real sequence. This is the AC that operationalizes
   the broadened R2 (invalidate all three, not just the raising phase's own)
   and is the strongest evidence against my initial concern that R6
   ("same contract") had no discriminating test — a retry entering at the
   deepest phase and correctly re-blocking the two phases that didn't raise
   it, and did pass, is a real end-to-end exercise of all three phases'
   invalidation behavior at once. Mechanical, and clearly fails on `main`
   today (no invalidation exists for `review`/`qa_validation` at all).
5. **Traversal, upward.** After `blocking_retry` raised in `scrutiny`,
   before `review`/`qa_validation` have ever run, the invalidation step
   exits 0 rather than erroring on the two keys that don't exist yet.
   Mechanical, tests the edge case R2 calls out explicitly. Confirmed
   achievable with existing koto verbs (see `exists`/`add` behavior above).
6. **The invalidation step runs on the same path as the `blocking_retry`
   submission** — extracted-block check that submission and invalidation
   are co-located. Mechanical, and this is what makes #3's precondition
   well-defined rather than a test-harness backdoor.
7. **Well-formed artifact -> `passed` advances (each phase).** True on
   `main` today already (R8 is an explicit non-regression requirement).
   Non-discriminating by design — a regression guard, not a defect probe;
   named per the review brief, not a flaw.
8. **Gate failing -> `blocking_retry`/`blocking_escalate` still reachable.**
   Confirmed via template read: these transitions don't reference the gate
   today, so this already holds, unconditional on gate state. Also a
   deliberate regression guard (R4), non-discriminating by design.
9. **Invalidation block against a broken context store exits non-zero,
   diagnostic with the key name on stdout, stderr to `/dev/null`.**
   Mechanical and discriminating — no such block exists for two of the
   three phases today, and scrutiny's errors for the wrong reason
   (unrecognized subcommand) regardless of store health.
10. **Diagnostic names the outcome to submit instead of success.**
    Mechanical (grep the diagnostic string), bounded.
11. **Test extracts the invalidation block + gate defs from the shipped
    files at run time.** Mechanical, directly enforces R9/R10.
12. **Retry passage states the true causality; no surviving false claim.**
    The forbidden claim ("stale artifact...will fail the gate") exists
    verbatim in `phase-4a-scrutiny.md` today, so the negative half is a
    clean grep. The positive half ("states that invalidation is what makes
    the gate fail") is closer to reading comprehension than a command —
    bounded to three short paragraphs, verifiable reliably by a reviewer,
    but the AC in the set closest to "checkable only by reading prose and
    agreeing with it." Advisory.
13. **`review-panel-orchestration.md` states the retry-clearing contract.**
    Same character as #12 — confirmed the file says nothing about
    invalidation today (discriminating), verification method is still
    prose reading. Advisory.
14. **`koto template compile` exits 0, no new warning vs. `main`.** Fully
    mechanical diff of warning sets; baseline confirmed as exactly one
    warning (W3) today.
15. **`cargo test --workspace` passes, no pre-existing test modified.**
    Mechanical (`git diff main` on test files + a test run). Confirmed the
    repo has a real Cargo workspace at the root.
16. **`scripts/run-evals.sh work-on` run and reported.** Confirmed the
    script and eval suite exist. This is a completion/audit criterion
    (was it run, is the result reported) rather than a correctness
    predicate by itself — legitimate as an AC type, weaker than the
    others. Advisory, not a defect.
17. **`shirabe validate --lifecycle . --mode=ready` exits 0.** Standard,
    mechanical, exit-code check.

## Goal coverage

1. "A `passed` submission carried by the previous round's artifact does not
   advance." — covered (AC3 + AC6).
2. "Invalidation runs a command koto has, distinguishable failure on
   stdout." — covered (AC1/2, AC9/10).
3. "The guarantee does not rest on prose; the workflow enforces it." —
   covered (AC3's gate-named-as-failing-condition, AC11's transition-reference
   extraction).
4. "`scrutiny`, `review`, and `qa_validation` carry the same contract,
   stated the same way." — covered behaviorally by AC4 (traversal from the
   deepest raising phase, which exercises all three phases' invalidation
   at once) and AC5 (edge case from the shallowest raising phase). One gap
   remains: no AC exercises a retry raised in `review` (the middle phase,
   which re-enters `scrutiny` then `review` but not `qa_validation`), and
   no AC directly diffs the three phase files' invalidation blocks against
   each other to catch textual drift (e.g., phase-4b's block edited
   correctly, phase-4c's forgotten) independent of a full traversal run.
   Given R6's stronger current wording — the invalidation is "not merely
   parallel... it is the same step" because R2 requires every entry point
   to invalidate all three artifacts — this is a minor coverage gap, not a
   missing-test problem: AC4 already forces the same three-artifact
   invalidation logic to run and be checked end-to-end. Advisory.
5. "Phase files and panel-orchestration summary describe the mechanics
   they actually have." — covered (AC12/13), with the prose-verification
   caveat noted above.

## Verdict rationale

No genuine untestability found. Every AC either resolves to a command,
exit code, or grep/diff, or — for the two prose-accuracy ACs (12, 13) — to
a bounded, specific reading-comprehension check a reviewer can apply
reliably (not an open-ended subjective judgment). The two "well-formed
artifact still advances" / "escape hatches still reachable" ACs are
already true on `main` today; that's intentional (R8, R4 are explicit
non-regression requirements), not a flaw, and is noted rather than flagged.
The traversal ACs (4, 5) are what make R2's broadened scope and R6's
"same contract" claim actually checkable by a machine rather than by
review opinion — this is the part of the PRD that most directly answers
the discriminating-AC rubric, and it does so credibly. Remaining items
(AC1/2's judgment caveat, AC12/13's prose nature, the missing
review-raised traversal case, the Out-of-Scope W3/W4 file mislabel,
AC16's audit-not-predicate shape) are all advisory.
