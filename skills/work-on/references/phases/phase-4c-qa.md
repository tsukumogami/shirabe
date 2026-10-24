# Phase 4c: QA Validation

Run QA validation after code review passes. The tester agent validates that the implementation functions correctly from a user perspective, not just that unit tests pass.

## Tester Agent

**Seat commissioning** (per `${CLAUDE_PLUGIN_ROOT}/references/review-seat-commissioning.md`): the tester runs on `model: "sonnet"` with a 30-call budget, larger than the other code seats because it runs the implementation. Packet: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" code --session <WF> --issue <N> --issue-repo "<ISSUE_REPO>"`, where `<ISSUE_REPO>` is the value the state's directive gives, empty for an issue in this repository, passed exactly as given; with `--criteria <file>` in place of `--issue <N>` and its `--issue-repo` when the run has no GitHub issue: a plan-outline child, whose `<N>` numbers an item in its PLAN, writes its outline's acceptance criteria to the file. Add `--panel qa --seat <seat>` for each `full` seat, which lists that seat's own unclosed findings by id, the ones it answers this round; one packet per seat when more than one seat has findings of its own. The panel's re-verifier, the one run a retry round plans, gets its own packet instead, built from the due failures and the fix diff: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" recheck --session <WF> --panel qa --seat reverifier`.

Spawn the tester agent using the Task tool. The tester:
1. Reads the implementation's acceptance criteria from the packet
2. Reads any project test plan
3. Exercises the implementation against the acceptance criteria
4. Reports pass/fail per AC with evidence
5. Judges each test the packet's `## Test changes` section lists as edited: `corrects` when the edit fixes a test that checked the wrong thing, `weakens` when it checks less than before or something easier to pass, running the test against the change where that settles it

The tester returns one `test_edits` item per edited test, with its path, judgment and a one-line reason, in the entry `phase-4a-scrutiny.md` shows. `--record` refuses a round in which it skipped an edited test, and records a `weakens` as a blocking finding the tester raised (`../review-panel-orchestration.md`, "Edited tests"). A test the section lists as added needs no judgment.

## Whether the Tester Runs

On entering `qa_validation`, koto runs `scripts/panel-scope.sh --plan qa` and writes `qa_scope.json`. In a full round (the first, or one a full-round trigger fires on, as `phase-4a-scrutiny.md` lists) the tester's decision is `full`: a full validation against every acceptance criterion, answering its own unclosed failures by id. Any other round keeps the tester and plans at most one run, the re-verifier (seat `reverifier`, decision `recheck`): it runs each due failing scenario again and answers it by id with `holds` or `reverified`, from the `recheck` packet on the commissioning line above and the re-check prompt in `review-seat-commissioning.md`. A failed scenario is usually a finding with no location, so it is due on every retry until it is re-verified. When nothing runs and no failure is unclosed, koto writes a carried `qa_results.json` and moves on to `verification` without stopping here.

```bash
koto context get <WF> qa_scope.json
```

A QA failure therefore routes narrowly. The retry returns to `implementation`, and the run walks forward through `scrutiny` and `review` as always. The first of them with a non-empty fix diff runs one re-verifier carrying the fix-diff review, which judges the fix against every panel's criteria; once it is recorded the later panels see an empty fix diff, spawn nothing and carry, and the run reaches this phase's re-verification. A fix over the size threshold in `panel-scope.sh` makes each panel's round full instead.

## Evidence Format

The tester writes full results to a `mktemp`-produced file outside the repository and returns:

```json
{
  "scenarios_run": 3,
  "scenarios_passed": 3,
  "scenarios_failed": 0,
  "cited": [{"path": "src/a.sh", "lines": "10-24"}],
  "findings": [{"severity": "blocking", "summary": "<the failing scenario>", "path": "tests/a_test.sh"}],
  "test_edits": [{"path": "tests/a_test.sh", "judgment": "corrects", "reason": "<one line>"}],
  "detail_file": "<the tester's mktemp path>"
}
```

`cited` is the code the scenarios exercised, kept for the readers of seat entries. `findings` lists each failing scenario with `severity: blocking`, which a re-check round gets back; anything else worth noting that is not a failure goes in as `severity: advisory`. Every finding carries one of the two: the severity is the verdict, and a finding without one makes `--record` refuse the round.

Delete the detail file once the round is aggregated; anything worth keeping goes into `qa_results.json`.

## Aggregation

After the run returns, record it, as `phase-4a-scrutiny.md` describes, with `qa` as the panel: the tester with one `severity: blocking` finding per failed scenario, or the re-verifier answering each due scenario by id with `holds` (it still fails) or `reverified` (it passes now, with a reason):

```bash
ROUND=$(mktemp)
# write [{"seat": "tester", "run": "qa-r1-tester", "cited": [...], "findings": [{"severity": "blocking", ...}]}]
# or [{"seat": "reverifier", "run": "qa-r2-reverifier", "answers": [{"id": "...", "record": "reverified", "reason": "..."}]}]
# to "$ROUND"
"${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/panel-scope.sh" --record qa <WF> "$ROUND" && rm -f "$ROUND"
```

If `--record` fails, fix it and run it again before submitting anything; if it can't be fixed, submit `qa_outcome: blocking_escalate`.

Then tick koto with nothing submitted. The `qa_verdict` gate reads the ledger (`panel-scope.sh --verdict qa`) and decides, as at scrutiny:

- Exit 0, every run recorded and no failed scenario unclosed: koto advances to `verification`. Optionally write `qa_results.json` first, as the round's summary for a reader; no gate reads it.
- Exit 1, a failed scenario is unclosed: the gate prints one finding per unclosed failed scenario, under the active rule it cites or under `panel/open-finding`. Submit `qa_outcome: blocking_retry` via the Retry Loop below, once the retry budget in the state's directive grants it (otherwise escalate). That routes to `implementation`, where the coder agent fixes the failing scenarios; the run then walks forward through `scrutiny` and `review` before re-entering this phase. It does not self-loop, which is why the retry clears those two panels' summaries as well as this one's.
- Exit 2, the round isn't recorded or the ledger can't be read: record the round and tick again.

```bash
# Optional: the round's summary for a reader. No gate reads it; skip
# straight to `koto next` if you don't write one.
koto context add <WF> qa_results.json < /dev/stdin <<EOF
{"round": <N>, "scenarios_run": 3, "scenarios_passed": 3}
EOF
koto next <WF> --no-cleanup
```

`<N>` is the number of the QA round that just ran: 1 the first time through, incremented on each pass through the retry loop below.

## Retry Loop

Run this only once the retry budget in the state's directive has granted the retry. The retry budget is `"${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/panel-retry-budget.sh" <WF> qa_validation`, with no count: it reads the panel's unclosed blocking findings from the ledger itself. Exit 0 grants the retry; any other exit refuses it, and you escalate with the reason it printed. When a defect sends the work back, clear every artifact the return trip invalidates before submitting the retry. Run this instead of a bare `koto next`:

```bash
OUTCOME_FIELD=qa_outcome
for KEY in scrutiny_results.json review_results.json qa_results.json light_results.json summary.md; do
  koto context remove <WF> "$KEY" >/dev/null 2>&1
  REMOVE_STATUS=$?
  if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then
    echo "$KEY was not confirmed cleared from context."
    echo "The stale artifact may still be in place, and a later gate may accept it."
    echo "Do NOT submit $OUTCOME_FIELD: blocking_retry by hand."
    echo "To stop the run, submit $OUTCOME_FIELD: blocking_escalate with a failure_reason."
    exit 1
  fi
done
EV=$(mktemp -d) || exit 1
printf '{"%s": "blocking_retry"}\n' "$OUTCOME_FIELD" > "$EV/evidence.json"
koto next <WF> --with-data @"$EV/evidence.json" --no-cleanup
NEXT_STATUS=$?
rm -rf "$EV"
exit "$NEXT_STATUS"
```

No gate reads `qa_results.json` for the pass any more, but a summary left in context would read as this round's on the next pass, about a test run against code the coder agent has since changed.

Every key in the list goes, not only this panel's. A retry raised here is the widest case: the run returns to `implementation` and walks forward through `scrutiny` and `review` before reaching this phase again, so both of those panels are re-entered holding summaries about code that no longer exists. Clearing them doesn't re-run them: `panel-scope.sh` writes a fresh carried summary for any panel the fix didn't touch, and the verdict ledger, not the summary, is what each panel's `<panel>_verdict` gate reads. `summary.md` goes too, since the traversal continues through `verification` into `finalization`. Why the block checks both signals is in `phase-4a-scrutiny.md`.

## Escalation

If a defect cannot be resolved, or the retry budget in the state's directive refuses the retry, submit `qa_outcome: blocking_escalate` with `failure_reason`. The workflow routes to `done_blocked`. Include a `failure_reason` string — without it, the context_assignments block cannot propagate the reason to koto context.
