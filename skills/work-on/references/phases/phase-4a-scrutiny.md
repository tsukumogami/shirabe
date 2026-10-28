# Phase 4a: Scrutiny

Run three parallel scrutiny reviewers before code review. Each reviewer checks the implementation from a different angle. All three must pass for the workflow to advance to the review panel.

## Reviewers

**Seat commissioning** (per `${CLAUDE_PLUGIN_ROOT}/references/review-seat-commissioning.md`): Completeness, Justification and Intent run on `model: "sonnet"` with a 15-call budget. Packet: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" code --session <WF> --issue <N> --issue-repo "<ISSUE_REPO>" --scratch <scratch>`, where `<scratch>` is the run's scratch directory (the one its evidence files go in) and `<ISSUE_REPO>` is the value the state's directive gives, empty for an issue in this repository, passed exactly as given; with `--criteria <file>` in place of `--issue <N>` and its `--issue-repo` when the run has no GitHub issue: a plan-outline child, whose `<N>` numbers an item in its PLAN, writes its outline's acceptance criteria to the file. Add `--panel scrutiny --seat <seat>` for each `full` seat, which lists that seat's own unclosed findings by id, the ones it answers this round; one packet per seat when more than one seat has findings of its own. The panel's re-verifier, the one run a retry round plans, gets its own packet instead, built from the due findings and the fix diff: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" recheck --session <WF> --panel scrutiny --seat reverifier --scratch <scratch>`.

Spawn all three simultaneously using the Task tool:

- **Completeness reviewer**: Does every acceptance criterion have a corresponding implementation? Are evidence claims verifiable from the diff?
- **Justification reviewer**: Are deviations genuinely explained? Do reasons reflect real trade-offs, not shortcuts?
- **Intent reviewer**: Does the implementation match the design doc's described behavior, not just the literal AC text? Does it provide a sufficient foundation for downstream issues?

Every seat also judges each test the packet's `## Test changes` section lists as edited: does the edit correct a test that checked the wrong thing (`corrects`), or does it check less than before, or something easier to pass (`weakens`)? It returns one `test_edits` item per edited test, `{"path": "<test>", "judgment": "corrects|weakens", "reason": "<one line>"}`. `--record` refuses a round in which a seat skipped an edited test, and records each `weakens` as a blocking finding raised by that seat (`../review-panel-orchestration.md`, "Edited tests"). A test the section lists as added needs no judgment.

## Which Seats Run

koto decides this before you spawn anything. On entering `scrutiny` it runs `scripts/panel-scope.sh --plan scrutiny`, which reads the findings ledger and writes `scrutiny_scope.json`. The panel's findings, not its seats, decide what runs:

| Decision | What you spawn |
|----------|----------------|
| `full` | The seat's normal full review. Every seat is `full` in a full round: the panel's first; one where the ledger predates finding records, the criteria or plan changed, the history was rewritten, the tree is dirty, or there are no commits; one whose seats last judged no commit since `impl_base`; one where the fix since the panel's own newest record is over the size threshold; or one where nothing recorded can bound a fix diff. The decision also hands the seat its own unclosed blocking findings, which it answers by id: `holds`, `reverified`, or `dismissed` with a reason. A full round is the one place a seat may dismiss its own finding. |
| `recheck` | Only seat `reverifier`, the panel's re-verifier. Any round that isn't full keeps every real seat and plans at most this one run. Its decision lists every due blocking finding by id: one the fix touched, one marked fixed, one a decider couldn't verify, a closed one the fix touched again. It answers each by id with `holds` or `reverified`, giving a reason for each `reverified`. When the decision carries `fix_review`, it also reviews the fix diff from `review_from` against every panel's criteria and returns what it finds as new findings. Its packet is the `recheck` kind on the commissioning line above, and its prompt the re-check prompt in `review-seat-commissioning.md`. A full round plans one too, for unclosed findings no seat raised. |
| `keep` | Nothing. Outside a full round no real seat re-runs, whatever the fix touched: the fix-diff review is what sees new defects. At aggregation a kept seat counts as recorded. |

```bash
koto context get <WF> scrutiny_scope.json
```

Commit the fix before the run re-enters a panel. The scope is computed from committed history, so a working tree with uncommitted changes (untracked files included) makes the round full; commit and tick again to get the narrow round. This holds for every panel, not only this one.

When nothing runs and no blocking finding of the panel is unclosed, you never see this phase: the script writes a carried `scrutiny_results.json`, the `scrutiny_carried` gate passes, and koto moves on to `review` by itself. The visit is still in koto's log, so the round is counted either way. When nothing runs but a blocking finding the fix didn't touch is still unclosed, the `scrutiny_verdict` gate blocks the panel without a run.

Spawn only the decisions that aren't `keep`. This holds for every round after a retry, whatever the Reviewers section above and the Retry Loop below say about spawning all three. The decisions are the script's, made from the ledger and git: don't add a seat because the fix looks risky, and don't drop one because it looks safe. If you think a kept seat should run anyway, that's a finding for whichever run is running, not a reason to override the scope.

## Decider Batch

The batch runs beside the seats for a user whose decider is on: the state's `scrutiny_decider` check asks Jev whether every decision the run recorded in `analysis` and `implementation` gives, in its reason, why the choice was made. Its slice is `scripts/decision-reasons.sh slice` over koto's session log, each decision as a `- choice:` and a `  reason:` line. It replaces no seat. Its findings are advisory while the criterion is untrusted: it runs in shadow, so no answer fails the panel or changes its route. When the check is `pending` with `work-on/scrutiny-decision-reasons` under its output's `awaiting` list, the decider gave no verdict: read the decisions with that slice command, judge each reason, and answer with `koto decider answer {{SESSION_NAME}} --gate scrutiny_decider --criterion work-on/scrutiny-decision-reasons --answer <pass|fail|unclear>`, the session's name in place of `{{SESSION_NAME}}`, then tick again with nothing submitted. This can hold a carried round too, when no seat runs. Answer only a criterion listed under `awaiting`, and never record an override to get past it. `panel-scope.sh --record` reads the batch's verdicts from koto's log itself, so the round file never names them: a shadow fail lands in the ledger as an advisory finding, and a shadow non-verdict adds nothing. The criterion's contract and figures are in `references/jev-criteria.md`.

## Evidence Format

Each reviewer writes full findings to a `mktemp`-produced file outside the repository and returns a compact JSON summary:

```json
{
  "focus": "completeness",
  "summary": "<1-3 paragraphs>",
  "cited": [{"path": "src/a.sh", "lines": "10-24"}, {"path": "README.md"}],
  "findings": [{"severity": "blocking", "summary": "<one line>", "path": "src/a.sh", "lines": "12"},
               {"severity": "advisory", "summary": "<one line>", "path": "README.md"}],
  "test_edits": [{"path": "tests/a_test.sh", "judgment": "corrects", "reason": "<one line>"}],
  "detail_file": "<the reviewer's mktemp path>"
}
```

`cited` is what the verdict rests on: the paths the seat judged and, where it can say, the line ranges in HEAD's numbering. It is kept in the ledger for the readers of seat entries; it no longer decides whether a seat re-runs. `findings` lists every finding with its location, and each carries a `severity`: `blocking` for a defect that must be fixed before the panel can pass, `advisory` for anything else worth saying. A finding's location (path, and lines where it can say) is what decides whether a later fix makes it due for re-verification, so give one wherever there is one.

Delete the detail files once the round is aggregated; anything worth keeping goes into `scrutiny_results.json`.

## Aggregation

After every spawned run returns, record the round in the verdict ledger, passed and blocking alike. Build the round file from the runs' summaries in a `mktemp` file outside the repository, one entry per run, each naming the `run` its decision in `scrutiny_scope.json` was given:

```json
[{"seat": "completeness", "run": "scrutiny-r1-completeness",
  "cited": [{"path": "src/a.sh", "lines": "10-24"}],
  "findings": [{"severity": "blocking", "summary": "<one line>", "path": "src/a.sh", "lines": "12"}],
  "answers": [{"id": "<finding id>", "record": "holds|reverified|dismissed", "reason": "<one line>"}],
  "test_edits": [{"path": "tests/a_test.sh", "judgment": "corrects|weakens", "reason": "<one line>"}]},
 {"seat": "reverifier", "run": "scrutiny-r2-reverifier",
  "answers": [{"id": "<finding id>", "record": "reverified", "reason": "<what in the fix diff resolves it>"}],
  "findings": [{"severity": "blocking", "summary": "<a defect the fix introduced>", "path": "src/b.sh", "lines": "3"}]}]
```

`answers` answer the findings the decision handed the run, by id, and no others. A `full` seat may answer its own findings `holds`, `reverified` or `dismissed`, and a dismissal needs a reason. The re-verifier may answer only `holds` or `reverified`, with a reason on each `reverified`, and may carry `findings` only when its decision planned the fix-diff review; those are raised by reviewer `fix-review`. A due finding left unanswered keeps its status and stays due. Every real seat's entry carries its `test_edits`, one item for each test the packet lists as edited; `--record` refuses (65, rule `review/test-edit-judgment`) a round in which one is missing, and records a `weakens` as a blocking finding the seat raised, under rule `review/test-edit-weakens`. The re-verifier carries none. `--record` refuses (65) a run the scope didn't mint, a run recorded twice, an answer for an id the decision didn't plan, and two findings of one run with the same id, and the ledger is left as it was.

```bash
ROUND=$(mktemp)
# write the JSON array of runs to "$ROUND"
"${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/panel-scope.sh" --record scrutiny <WF> "$ROUND" && rm -f "$ROUND"
```

A seat's verdict is its findings' severity: `--record` records the seat as blocking exactly when one of its findings is `severity: blocking`, and as passed otherwise. A finding with no `severity`, or one other than `blocking` or `advisory`, makes `--record` refuse the whole round (exit 65), so a seat is never recorded as passing because the field was left out. A `blocking_count` or `passed` field in the round file is ignored.

A blocking finding stays open until a verdict record closes it: a `reverified` or `dismissed` record written by a reviewer or a check, or by a decider on a finding that decider raised, naming the run that wrote it. Your own claim that a finding is fixed is a `fixed` record, which asks for re-verification and never closes anything, and the panel passes only when no blocking finding of the panel is open.

`--record` stamps each verdict with the commit it was given at and the acceptance criteria it was judged against; that is what the next round's scope is computed from. A seat that wasn't spawned is left as it was. If `--record` fails, fix the cause its exit code names (65 a malformed round file or a missing severity, 66 a koto call that failed (a context write, or the `koto session dir` that finds the session log), 68 a commit made since the round was planned: tick koto without evidence to re-plan, and run the round again) and run it again before submitting anything. Don't go on without it: the ledger would still hold the seat's previous verdict, and a seat that just blocked could be carried as passed next round. If it can't be fixed, submit `scrutiny_outcome: blocking_escalate`. The `scrutiny_verdict` gate holds the state (exit 2) while any run this round planned is not recorded, so a skipped record stops the run here rather than surfacing next round; the `scrutiny_recorded` gate holds the same edges until it is.

Then tick koto with nothing submitted. The `scrutiny_verdict` gate reads the ledger (`panel-scope.sh --verdict scrutiny`) and decides:

- Exit 0, every run recorded and every blocking finding closed: koto advances to `review`. Optionally write `scrutiny_results.json` first, as the round's summary for a reader; no gate reads it.
- Exit 1, a blocking finding is unclosed: the gate prints one finding per unclosed blocking finding, under the active rule it cites or under `panel/open-finding`. Collect them and submit `scrutiny_outcome: blocking_retry` via the Retry Loop below, once the retry budget in the state's directive grants it (otherwise escalate). That routes to `implementation`, where the coder agent takes the combined feedback; the run then walks forward and re-enters this phase. It does not self-loop.
- Exit 2, the round isn't fully recorded or the ledger can't be read: record the round and tick again.

```bash
# Optional: the round's summary for a reader. No gate reads it; skip
# straight to `koto next` if you don't write one.
koto context add <WF> scrutiny_results.json <<EOF
{"round": <N>, "summary": "<one line per seat>"}
EOF
koto next <WF> --no-cleanup
```

`<N>` is the number of the scrutiny round that just ran: 1 the first time through, incremented on each pass through the retry loop below. There is no `passed` value to submit: the verdict is koto's, from what the seats recorded.

## Retry Loop

Run this only once the retry budget in the state's directive has granted the retry. The retry budget is `"${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/panel-retry-budget.sh" <WF> scrutiny`, with no count: it reads the panel's unclosed blocking findings from the ledger itself. Exit 0 grants the retry; any other exit refuses it, and you escalate with the reason it printed. When a blocking finding sends the work back, clear every artifact the return trip invalidates before submitting the retry. Run this instead of a bare `koto next`:

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
EV=$(mktemp -d) || exit 1
printf '{"%s": "blocking_retry"}\n' "$OUTCOME_FIELD" > "$EV/evidence.json"
koto next <WF> --with-data @"$EV/evidence.json" --no-cleanup
NEXT_STATUS=$?
rm -rf "$EV"
exit "$NEXT_STATUS"
```

Why removal rather than leaving the old summary to be overwritten: a summary left in context reads as this round's on the next pass, though it describes code the coder agent has since changed. No panel gate reads the `<panel>_results.json` keys any more (each panel's pass is its `<panel>_verdict` gate, over the verdict ledger), but `finalization`'s `summary_exists` gate is still `context-exists`: it asks whether `summary.md` is present and nothing else, and a summary written before the fix would satisfy it. Removing the keys keeps every artifact the return trip reads to this round's.

Every key in the list goes, not only this panel's. A `blocking_retry` returns to `implementation` and the run walks forward from there through every panel, `verification` and `finalization`, and none of them may be read on an artifact written before the fix. `light_results.json` is in the list because the review-level check on the way back can change which panels the run reaches. Clearing a panel's summary does not re-run its seats, and it is not what stops a stale pass: that is the verdict ledger's job. `review_level.jsonl`, the review-level ledger, is never in the list: it is the run's record of its level. `verdict_ledger.json` is deliberately not in the list: it holds every finding the panels raised, with the records written about each and the commits they were judged at; on re-entry `panel-scope.sh` uses it to decide which findings the fix made due, and `<panel>_verdict` holds the panel until every run the round planned is recorded and every blocking finding is closed. A panel with nothing to run and nothing open gets a fresh, carried `<panel>_results.json` written by the script, and the artifact says why nothing ran.

`summary.md` is in the list as belt and braces rather than because a panel retry normally finds one: the only route from `finalization` back to a panel is the `issues_found` edge, which clears it there. It stays because removal is idempotent and costs nothing, and because it catches the case where the finalization step was skipped. `plan.md` is deliberately NOT in the list — a code change does not invalidate the plan, and clearing it would strand a run that later re-enters `analysis`.

The block stops if **either** signal fires — `koto context remove` reporting failure, or `koto context exists` still reporting the key present — because neither alone is enough. `exists` catches a removal that returns success without the key going away, which `remove`'s status cannot: it deletes the content file, then the lock, then the manifest, so it can report failure after the gate-relevant effect already landed. `remove`'s status catches the reverse: `ctx_exists` reports absent for a store it cannot READ as well as for a key that is not there, so on an unreadable store `exists` says the key is gone while it is still on disk.

That second case is why this is not caution for its own sake. A `context-exists` gate such as `summary_exists`, on `finalization` and `deferral_approval`, makes the same blind read, so the advancing outcome is refused when you submit it — but koto re-evaluates that buffered evidence, and the moment the permission problem clears the run advances on the surviving artifact with no further submission. The gate agreeing with `exists` is a delay, not a defence.

The rule that falls out, and the reason there is no `exists` guard *before* the removal: `koto context exists` may be used to detect a key that is present, never to conclude one is absent.

The run then returns to `implementation`, and when it walks forward into this phase again, spawn the seats the new scope names, as **Which Seats Run** says. Record that round as the Aggregation section says, with `<N>` set to this round's number, and tick: when no seat records a blocking finding, koto advances. If `scrutiny_verdict` still exits 1, run the retry budget again and then this block, or escalate as described below.

## Escalation

If a blocking finding cannot be resolved, or the retry budget in the state's directive refuses the retry, submit `scrutiny_outcome: blocking_escalate` with a clear `failure_reason`. The workflow routes to `done_blocked`.
