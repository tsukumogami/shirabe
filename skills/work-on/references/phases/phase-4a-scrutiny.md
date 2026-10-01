# Phase 4a: Scrutiny

Run three parallel scrutiny reviewers before code review. Each reviewer checks the implementation from a different angle. All three must pass for the workflow to advance to the review panel.

## Reviewers

Spawn the seats this round needs simultaneously using the Task tool -- all three on the first round, and on a retry only those `scrutiny_scope.json` doesn't keep (see Which Seats Run):

- **Completeness reviewer**: Does every acceptance criterion have a corresponding implementation? Are evidence claims verifiable from the diff?
- **Justification reviewer**: Are deviations genuinely explained? Do reasons reflect real trade-offs, not shortcuts?
- **Intent reviewer**: Does the implementation match the design doc's described behavior, not just the literal AC text? Does it provide a sufficient foundation for downstream issues?

## Which Seats Run

koto decides this before you spawn anything. On entering `scrutiny` it runs `scripts/panel-scope.sh --plan scrutiny`, which writes `scrutiny_scope.json` with one decision per seat:

| Decision | What you spawn |
|----------|----------------|
| `full` | The seat's normal full review. Every seat is `full` on the first round. |
| `recheck` | The seat that raised a blocking finding last round. It gets only its `findings` and the fix diff (`git diff <fix_diff_from> HEAD`), and answers whether each finding is fixed. It does not review anything else. |
| `rerun` | A seat that passed, but whose cited scope the fix touched. A fresh full review. |
| `keep` | Nothing. The seat's earlier pass carries, and the scope says why. |

```bash
koto context get <WF> scrutiny_scope.json
```

Commit the fix before the run re-enters a panel. The scope is computed from committed history, so on a working tree with uncommitted changes (untracked files included) the script keeps nothing and every passed seat re-runs; commit and tick again to get the narrow round. This holds for every panel, not only this one.

When every seat is `keep` you never see this phase: the script writes a carried `scrutiny_results.json`, the `scrutiny_carried` gate passes, and koto moves on to `review` by itself. The visit is still in koto's log, so the round is counted either way.

Spawn only the seats whose decision isn't `keep`. The decisions are the script's, made from git: don't add a seat because the fix looks risky, and don't drop one because it looks safe. If you think a kept seat should run anyway, that's a finding for whichever seat is running, not a reason to override the scope.

## Evidence Format

Each reviewer writes full findings to a `mktemp`-produced file outside the repository and returns a compact JSON summary:

```json
{
  "focus": "completeness",
  "blocking_count": 0,
  "advisory_count": 1,
  "summary": "<1-3 paragraphs>",
  "cited": [{"path": "src/a.sh", "lines": "10-24"}, {"path": "README.md"}],
  "findings": [{"summary": "<one line>", "path": "src/a.sh", "lines": "12"}],
  "detail_file": "<the reviewer's mktemp path>"
}
```

`cited` is what the verdict rests on: the paths the seat judged and, where it can say, the line ranges in HEAD's numbering. It decides whether a later fix re-runs this seat, so cite precisely: a seat that cites nothing is treated as having judged every path in the diff, and re-runs whenever a fix touches any of them. `findings` lists each blocking finding with its location; a re-check round gets them back verbatim.

Delete the detail files once the round is aggregated; anything worth keeping goes into `scrutiny_results.json`.

## Aggregation

After every spawned seat returns, record the round in the verdict ledger, passed and blocking seats alike. Build the round file from the seats' summaries (`seat`, `blocking_count`, `cited`, `findings`) in a `mktemp` file outside the repository:

```bash
ROUND=$(mktemp)
# write the JSON array of spawned seats to "$ROUND"
"${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/panel-scope.sh" --record scrutiny <WF> "$ROUND" && rm -f "$ROUND"
```

`--record` stamps each verdict with the commit it was given at and the acceptance criteria it was judged against; that is what the next round's scope is computed from. A seat that wasn't spawned is left as it was. If `--record` fails, fix the cause its exit code names (65 a malformed round file, 66 a context write) and run it again before submitting anything. Don't go on without it: the ledger would still hold the seat's previous verdict, and a seat that just blocked could be carried as passed next round. If it can't be fixed, submit `scrutiny_outcome: blocking_escalate`. This step is prose rather than a gate because nothing a gate could check distinguishes "recorded" from "this round had nothing new to record" without re-deriving the round from the seats' own output, which only the agent holds.

Then:

- If any `blocking_count > 0`: collect blocking findings and submit `scrutiny_outcome: blocking_retry` via the Retry Loop below. That routes to `implementation`, where the coder agent takes the combined feedback; the run then walks forward and re-enters this phase. It does not self-loop.
- If all `blocking_count: 0`: write `scrutiny_results.json` to koto context and submit `scrutiny_outcome: passed`. Seats that were `keep` count as passed.

```bash
koto context add <WF> scrutiny_results.json <<EOF
{"passed": true, "round": <N>, "blocking_count": 0}
EOF
koto next <WF> --with-data '{"scrutiny_outcome": "passed"}' --no-cleanup
```

`<N>` is the number of the scrutiny round that just ran: 1 the first time through, incremented on each pass through the retry loop below.

## Retry Loop

When a blocking finding sends the work back, clear every artifact the return trip invalidates before submitting the retry. Run this instead of a bare `koto next`:

```bash
OUTCOME_FIELD=scrutiny_outcome
for KEY in scrutiny_results.json review_results.json qa_results.json summary.md; do
  koto context remove <WF> "$KEY" >/dev/null 2>&1
  REMOVE_STATUS=$?
  if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then
    echo "$KEY was not confirmed cleared from context."
    echo "The stale artifact may still be in place, and its gate may accept it."
    echo "Do NOT submit $OUTCOME_FIELD: passed on the next pass."
    echo "To stop the run, submit $OUTCOME_FIELD: blocking_escalate with a failure_reason."
    exit 1
  fi
done
koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"blocking_retry\"}" --no-cleanup
```

Why removal rather than leaving the old verdict to be overwritten: the `scrutiny_results` gate is `context-exists`, so it asks whether the key is present and nothing else. A verdict left in context satisfies it on the next pass, and the panel can advance on a review of code the coder agent has since changed. Removing the key makes the gate demand this round's artifact — the refusal is the state machine's, not a matter of remembering to submit the right outcome.

All four keys go, not only this panel's. A `blocking_retry` returns to `implementation` and the run walks forward from there through every panel, `verification` and `finalization`, and none of those gates may pass on a verdict written before the fix. Clearing a panel's verdict no longer means re-running its seats, though. `verdict_ledger.json` is deliberately not in the list: it holds each seat's last verdict, the commit it judged, and what it cited, and on re-entry `panel-scope.sh` uses it to decide which seats the fix actually touched. A panel whose every seat is untouched gets a fresh, carried `<panel>_results.json` written by the script, so the gate still demands this round's artifact, and the artifact says why no seat ran.

`summary.md` is in the list as belt and braces rather than because a panel retry normally finds one: the only route from `finalization` back to a panel is the `issues_found` edge, which clears it there. It stays because removal is idempotent and costs nothing, and because it catches the case where the finalization step was skipped. `plan.md` is deliberately NOT in the list — a code change does not invalidate the plan, and clearing it would strand a run that later re-enters `analysis`.

The block stops if **either** signal fires — `koto context remove` reporting failure, or `koto context exists` still reporting the key present — because neither alone is enough. `exists` catches a removal that returns success without the key going away, which `remove`'s status cannot: it deletes the content file, then the lock, then the manifest, so it can report failure after the gate-relevant effect already landed. `remove`'s status catches the reverse: `ctx_exists` reports absent for a store it cannot READ as well as for a key that is not there, so on an unreadable store `exists` says the key is gone while it is still on disk.

That second case is why this is not caution for its own sake. The gate makes the same blind read, so the advancing outcome is refused when you submit it — but koto re-evaluates that buffered evidence, and the moment the permission problem clears the run advances on the surviving artifact with no further submission. The gate agreeing with `exists` is a delay, not a defence.

The rule that falls out, and the reason there is no `exists` guard *before* the removal: `koto context exists` may be used to detect a key that is present, never to conclude one is absent.

The run then returns to `implementation`, and when it walks forward into this phase again, read `scrutiny_scope.json` and spawn what it says (see Which Seats Run). This panel's seat that raised the finding re-checks it; the other two re-run only if the fix touched what they cited. When that round comes back with every `blocking_count: 0`, record it and run the Aggregation command above with `<N>` set to this round's number. If it still finds blocking findings, run this block again, or escalate as described below.

## Escalation

If a blocking finding cannot be resolved, or the retry cap in the state's directive is spent, submit `scrutiny_outcome: blocking_escalate` with a clear `failure_reason`. The workflow routes to `done_blocked`.
