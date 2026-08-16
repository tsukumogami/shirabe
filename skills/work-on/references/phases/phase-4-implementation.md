# Implementation

Retrieve the plan from koto context and execute it:

```bash
koto context get <WF> plan.md
```

The analysis agent wrote this plan and returned only a summary. The full plan
content is needed here to execute the implementation steps.

## Design Context

If you need to revisit design rationale during implementation:

```bash
koto context get <WF> context.md
```

You saw this content during phase 0. Only re-read from koto if you need to
refresh your understanding or if resuming from an interrupted session.

## Implementation Cycle

For each step in the plan:

### A. Write Code

- One logical unit at a time
- Follow project conventions
- Keep changes focused and atomic
- **Record why the code is shaped this way, next to the code** — the
  decision the diff cannot show, and keep it current when the code
  changes

On that last point, because it is the one that gets skipped: a comment
explaining *what* the code does is usually redundant with the code. A
comment explaining *why* it is this way and not the obvious
alternative is not recoverable from anywhere else. When you rejected an
approach, when a constraint forced a shape, when an ordering is
load-bearing — that reasoning exists only in your head at the moment you
write it, and nothing downstream captures it.

This holds regardless of what documents the work leaves behind. A chain
may fold its scoping artifacts away and leave the code as the record; it
may keep all four. Either way this instruction is the same, because the
code is the thing that outlives every other artifact and the thing the
next person reads first.

### B. Validate

Run the project's validation commands (from CLAUDE.md or language skill):
- Linting/formatting, type checking, unit tests

If tests fail:
- **Simple fix**: fix and re-run
- **Test bug**: update test
- **Design issue**: update plan, possibly return to analysis
- **Unclear**: launch testing agent

### C. Functional Testing

- Verify the change works as intended
- Test edge cases
- Check for regressions

### D. Write/Update Tests

- Add tests for new functionality
- Update existing tests if behavior changed

### Commit

Mark step complete in the plan: `- [x] <step>`. Commit format:
`<type>(scope): <description>`

## Coverage Tracking

If the project tracks coverage:
- Overall coverage drop: max 1%
- Per-function coverage drop: max 10%

## Re-confirm Acceptance Criteria Mid-Implementation

After the main implementation commits land and before you run
Implementation Review, re-read the issue body once more against what
actually shipped. The goal is to catch AC drift that end-of-phase
self-review misses because by then you've stopped thinking about the
original wording.

Do this:

1. `gh issue view <N>` (or re-read the plan outline in plan-backed mode)
   — don't rely on what's still in your conversation context; issues and
   outlines change.
2. Walk each acceptance criterion in order. For each, point at the
   commit or file that satisfies it.
3. For any AC that's only partially satisfied or that you interpreted
   differently than written, decide: revise the code, or note a
   documented deviation in the summary.

If an AC is literally under-specified or contradicts reality (e.g., an
AC references `rule.config.pattern` but the rest of the system uses
`rule.tools`), implement what makes sense for the system and record a
decision via `koto decisions record` — don't ship a contorted
implementation to transcribe the AC verbatim.

This step is cheap (usually < 2 minutes) and has caught real AC
deviations in practice where the first read glossed over specifics.

## Acceptance Criteria Validation Scripts

Some issue bodies include a shell validation script (for example,
`grep -qE "pattern" path/to/file`). Treat these as **advisory, not
authoritative**. Verify the AC's intent against the code; do not rewrite the
implementation to make a literal script pass. Issue authors can introduce
regex bugs or pattern drift that cause a script to fail even when the AC is
satisfied, and a cosmetic script pass does not prove the behaviour is
correct. If a script fails but the AC is met, note the divergence in the
summary; if the script succeeds but the AC is not met, the script is wrong.

## Implementation Review

**Self-review (always):** `git diff main...HEAD`, then re-read acceptance
criteria and verify each is satisfied.

**Agent review (non-trivial implementations):** Launch specialized agents as
needed: security, performance, testing, architecture. Check for scope shrinkage
and design intent drift.

## Evidence

- `implementation_status: complete` — all steps done, tests pass
- `implementation_status: partial_tests_failing_retry` — fixing failures (up to 3)
- `implementation_status: partial_tests_failing_escalate` — cannot fix
- `implementation_status: scope_expanded_retry` — scope grew beyond the plan mid-implementation; route back to `analysis` to rewrite the plan rather than proceeding with stale decisions
- `implementation_status: blocked` — external blocker

Use `scope_expanded_retry` when the user or the code reveals new scope during
implementation — e.g., the user asks to configure behaviour that was previously
hard-coded, or a referenced file turns out to need parallel changes. Explain
the change in `rationale`; the transition rewinds to `analysis` so the plan can
absorb it cleanly.

## Retry Loop: scope_expanded_retry

The rewind lands on `analysis`, whose `plan_artifact` gate holds the `plan.md` the rewind exists to replace. Clear it before submitting:

```bash
koto context remove <WF> plan.md >/dev/null 2>&1
REMOVE_STATUS=$?
if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> plan.md >/dev/null 2>&1; then
  echo "plan.md was not confirmed cleared from context."
  echo "The superseded plan may still be in place, and the plan_artifact gate may accept it."
  echo "Do NOT submit plan_outcome: plan_ready from analysis on the next pass."
  echo "To stop the run, submit implementation_status: partial_tests_failing_escalate."
  exit 1
fi
koto next <WF> --with-data '{"implementation_status": "scope_expanded_retry", "rationale": "<why the scope grew>"}'
```

The gate is `context-exists`: it asks whether `plan.md` is present, not whether it accounts for the scope that just appeared. Left in place, `analysis` can pass straight back through on the old plan — which is the outcome the rewind was meant to prevent.

The block stops if **either** signal fires — `koto context remove` reporting failure, or `koto context exists` still reporting the key present — because neither alone is enough. `exists` catches a removal that returns success without the key going away, which `remove`'s status cannot: it deletes the content file, then the lock, then the manifest, so it can report failure after the gate-relevant effect already landed. `remove`'s status catches the reverse: `ctx_exists` reports absent for a store it cannot READ as well as for a key that is not there, so on an unreadable store `exists` says the key is gone while it is still on disk.

That second case is why this is not caution for its own sake. The gate makes the same blind read, so the advancing outcome is refused when you submit it — but koto re-evaluates that buffered evidence, and the moment the permission problem clears the run advances on the surviving artifact with no further submission. The gate agreeing with `exists` is a delay, not a defence.

The rule that falls out, and the reason there is no `exists` guard *before* the removal: `koto context exists` may be used to detect a key that is present, never to conclude one is absent.

`analysis` clears the same key on its own `scope_changed_retry` self-loop; see `phase-3-analysis.md`. Two edges, one gate, and each needs its own clearing step.
