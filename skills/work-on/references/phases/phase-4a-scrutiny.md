# Phase 4a: Scrutiny

Run three parallel scrutiny reviewers before code review. Each reviewer checks the implementation from a different angle. All three must pass for the workflow to advance to the review panel.

## Reviewers

**Seat commissioning** (per `${CLAUDE_PLUGIN_ROOT}/references/review-seat-commissioning.md`): Completeness, Justification and Intent run on `model: "sonnet"` with a 15-call budget. Packet: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" code --session <WF> --issue <N>`, with `--criteria <file>` in place of `--issue <N>` when the run has no GitHub issue: a plan-outline child, whose `<N>` numbers an item in its PLAN, writes its outline's acceptance criteria to the file. A seat the scope marks `recheck` gets its own packet instead, built from its findings and the fix diff: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" recheck --session <WF> --panel scrutiny --seat <seat>`.

Spawn all three simultaneously using the Task tool:

- **Completeness reviewer**: Does every acceptance criterion have a corresponding implementation? Are evidence claims verifiable from the diff?
- **Justification reviewer**: Are deviations genuinely explained? Do reasons reflect real trade-offs, not shortcuts?
- **Intent reviewer**: Does the implementation match the design doc's described behavior, not just the literal AC text? Does it provide a sufficient foundation for downstream issues?

## Which Seats Run

koto decides this before you spawn anything. On entering `scrutiny` it runs `scripts/panel-scope.sh --plan scrutiny`, which writes `scrutiny_scope.json` with one decision per seat:

| Decision | What you spawn |
|----------|----------------|
| `full` | The seat's normal full review. Every seat is `full` on the first round. |
| `recheck` | The seat that raised a blocking finding last round. Its packet is the `recheck` kind on the commissioning line above, holding only its `findings` and the fix diff (`git diff <fix_diff_from> HEAD`), and it answers whether each finding is fixed, prompted with the re-check prompt in `review-seat-commissioning.md` rather than its role above. It does not re-review the rest of the implementation, but it must read the whole fix diff and block on any defect the fix itself introduces: a passing re-check records the seat as passed at HEAD. A blocking seat is only offered this when the checks that would re-run a passed seat (a dirty tree, changed criteria or plan, a rewritten history, a fix over the size threshold) don't apply; otherwise it gets `rerun`. |
| `rerun` | A seat that passed, but whose cited scope the fix touched. A fresh full review. |
| `keep` | Nothing. The seat's earlier pass carries, and the scope says why. At aggregation it counts as passed. |

```bash
koto context get <WF> scrutiny_scope.json
```

Commit the fix before the run re-enters a panel. The scope is computed from committed history, so on a working tree with uncommitted changes (untracked files included) the script keeps nothing and every passed seat re-runs; commit and tick again to get the narrow round. This holds for every panel, not only this one.

When every seat is `keep` you never see this phase: the script writes a carried `scrutiny_results.json`, the `scrutiny_carried` gate passes, and koto moves on to `review` by itself. The visit is still in koto's log, so the round is counted either way.

Spawn only the seats whose decision isn't `keep`. This holds for every round after a retry, whatever the Reviewers section above and the Retry Loop below say about spawning all three: the seat that raised a finding re-checks it, and the others re-run only if the fix touched what they cited. The decisions are the script's, made from git: don't add a seat because the fix looks risky, and don't drop one because it looks safe. If you think a kept seat should run anyway, that's a finding for whichever seat is running, not a reason to override the scope.

## Evidence Format

Each reviewer writes full findings to a `mktemp`-produced file outside the repository and returns a compact JSON summary:

```json
{
  "focus": "completeness",
  "summary": "<1-3 paragraphs>",
  "cited": [{"path": "src/a.sh", "lines": "10-24"}, {"path": "README.md"}],
  "findings": [{"severity": "blocking", "summary": "<one line>", "path": "src/a.sh", "lines": "12"},
               {"severity": "advisory", "summary": "<one line>", "path": "README.md"}],
  "detail_file": "<the reviewer's mktemp path>"
}
```

`cited` is what the verdict rests on: the paths the seat judged and, where it can say, the line ranges in HEAD's numbering. It decides whether a later fix re-runs this seat, so cite precisely: a seat that cites nothing is treated as having judged every path in the diff, and re-runs whenever a fix touches any of them. `findings` lists every finding with its location, and each carries a `severity`: `blocking` for a defect that must be fixed before the panel can pass, `advisory` for anything else worth saying. A re-check round gets the blocking ones back verbatim.

Delete the detail files once the round is aggregated; anything worth keeping goes into `scrutiny_results.json`.

## Aggregation

After every spawned seat returns, record the round in the verdict ledger, passed and blocking seats alike. Build the round file from the seats' summaries (`seat`, `cited`, `findings`, every finding with its `severity`) in a `mktemp` file outside the repository:

```bash
ROUND=$(mktemp)
# write the JSON array of spawned seats to "$ROUND"
"${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/panel-scope.sh" --record scrutiny <WF> "$ROUND" && rm -f "$ROUND"
```

A seat's verdict is its findings' severity: `--record` records the seat as blocking exactly when one of its findings is `severity: blocking`, and as passed otherwise. A finding with no `severity`, or one other than `blocking` or `advisory`, makes `--record` refuse the whole round (exit 65), so a seat is never recorded as passing because the field was left out. A `blocking_count` or `passed` field in the round file is ignored.

`--record` stamps each verdict with the commit it was given at and the acceptance criteria it was judged against; that is what the next round's scope is computed from. A seat that wasn't spawned is left as it was. If `--record` fails, fix the cause its exit code names (65 a malformed round file or a missing severity, 66 a context write, 68 a commit made since the round was planned: tick koto without evidence to re-plan, and run the round again) and run it again before submitting anything. Don't go on without it: the ledger would still hold the seat's previous verdict, and a seat that just blocked could be carried as passed next round. If it can't be fixed, submit `scrutiny_outcome: blocking_escalate`. The `scrutiny_verdict` gate holds the state (exit 2) while any seat this round spawned has no verdict recorded since the round was planned, so a skipped record stops the run here rather than surfacing next round; the `scrutiny_recorded` gate holds the same edges while a spawned seat's verdict is older than the round.

Then tick koto with nothing submitted. The `scrutiny_verdict` gate reads the ledger (`panel-scope.sh --verdict scrutiny`) and decides:

- Exit 0, every seat recorded and none blocking: koto advances to `review`. Optionally write `scrutiny_results.json` first, as the round's summary for a reader; no gate reads it.
- Exit 1, a seat is blocking: the gate prints one `panel/blocking-finding` finding per blocking finding. Collect them and submit `scrutiny_outcome: blocking_retry` via the Retry Loop below, once the retry budget in the state's directive grants it (otherwise escalate). That routes to `implementation`, where the coder agent takes the combined feedback; the run then walks forward and re-enters this phase. It does not self-loop.
- Exit 2, the round isn't fully recorded or the ledger can't be read: record the round and tick again.

```bash
koto context add <WF> scrutiny_results.json <<EOF
{"round": <N>, "summary": "<one line per seat>"}
EOF
koto next <WF> --no-cleanup
```

`<N>` is the number of the scrutiny round that just ran: 1 the first time through, incremented on each pass through the retry loop below. There is no `passed` value to submit: the verdict is koto's, from what the seats recorded.

## Retry Loop

Run this only once the retry budget in the state's directive has granted the retry. When a blocking finding sends the work back, clear every artifact the return trip invalidates before submitting the retry. Run this instead of a bare `koto next`:

```bash
OUTCOME_FIELD=scrutiny_outcome
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
koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"blocking_retry\"}" --no-cleanup
```

Why removal rather than leaving the old summary to be overwritten: a summary left in context reads as this round's on the next pass, though it describes code the coder agent has since changed. No panel gate reads the `<panel>_results.json` keys any more (each panel's pass is its `<panel>_verdict` gate, over the verdict ledger), but `finalization`'s `summary_exists` gate is still `context-exists`: it asks whether `summary.md` is present and nothing else, and a summary written before the fix would satisfy it. Removing the keys keeps every artifact the return trip reads to this round's.

Every key in the list goes, not only this panel's. A `blocking_retry` returns to `implementation` and the run walks forward from there through every panel, `verification` and `finalization`, and none of them may be read on an artifact written before the fix. `light_results.json` is in the list because the review-level check on the way back can change which panels the run reaches. Clearing a panel's summary does not re-run its seats, and it is not what stops a stale pass: that is the verdict ledger's job. `review_level.jsonl`, the review-level ledger, is never in the list: it is the run's record of its level. `verdict_ledger.json` is deliberately not in the list: it holds each seat's last verdict, the commit it judged, and what it cited; on re-entry `panel-scope.sh` uses it to decide which seats the fix actually touched, and `<panel>_verdict` holds the panel until every seat it re-runs is recorded again. A panel whose every seat is untouched gets a fresh, carried `<panel>_results.json` written by the script, and the artifact says why no seat ran.

`summary.md` is in the list as belt and braces rather than because a panel retry normally finds one: the only route from `finalization` back to a panel is the `issues_found` edge, which clears it there. It stays because removal is idempotent and costs nothing, and because it catches the case where the finalization step was skipped. `plan.md` is deliberately NOT in the list — a code change does not invalidate the plan, and clearing it would strand a run that later re-enters `analysis`.

The block stops if **either** signal fires — `koto context remove` reporting failure, or `koto context exists` still reporting the key present — because neither alone is enough. `exists` catches a removal that returns success without the key going away, which `remove`'s status cannot: it deletes the content file, then the lock, then the manifest, so it can report failure after the gate-relevant effect already landed. `remove`'s status catches the reverse: `ctx_exists` reports absent for a store it cannot READ as well as for a key that is not there, so on an unreadable store `exists` says the key is gone while it is still on disk.

That second case is why this is not caution for its own sake. A `context-exists` gate such as `summary_exists` makes the same blind read, so the advancing outcome is refused when you submit it — but koto re-evaluates that buffered evidence, and the moment the permission problem clears the run advances on the surviving artifact with no further submission. The gate agreeing with `exists` is a delay, not a defence.

The rule that falls out, and the reason there is no `exists` guard *before* the removal: `koto context exists` may be used to detect a key that is present, never to conclude one is absent.

The run then returns to `implementation`, and when it walks forward into this phase again, spawn the seats the new scope names, as **Which Seats Run** says. Record that round as the Aggregation section says, with `<N>` set to this round's number, and tick: when no seat records a blocking finding, koto advances. If `scrutiny_verdict` still exits 1, run the retry budget again and then this block, or escalate as described below.

## Escalation

If a blocking finding cannot be resolved, or the retry budget in the state's directive refuses the retry, submit `scrutiny_outcome: blocking_escalate` with a clear `failure_reason`. The workflow routes to `done_blocked`.
