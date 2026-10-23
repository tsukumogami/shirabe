# Phase 4d: Light Review

The one panel of the `light` review level (`../review-levels.md`): a single reviewer seat in place of scrutiny, review and QA. A run reaches it from the review-level check only when its level is `light` and the facts of the change didn't raise it. The seat must pass for the workflow to advance to verification.

## Reviewer

**Seat commissioning** (per `${CLAUDE_PLUGIN_ROOT}/references/review-seat-commissioning.md`): Reviewer runs on `model: "sonnet"` with a 15-call budget. Packet: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" code --session <WF> --issue <N> --issue-repo "<ISSUE_REPO>"`, where `<ISSUE_REPO>` is the value the state's directive gives, empty for an issue in this repository, passed exactly as given; with `--criteria <file>` in place of `--issue <N>` and its `--issue-repo` when the run has no GitHub issue: a plan-outline child, whose `<N>` numbers an item in its PLAN, writes its outline's acceptance criteria to the file. Add `--panel light --seat <seat>` for each `full` seat, which lists that seat's own unclosed findings by id, the ones it answers this round; one packet per seat when more than one seat has findings of its own. The panel's re-verifier, the one run a retry round plans, gets its own packet instead, built from the due findings and the fix diff: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" recheck --session <WF> --panel light --seat reverifier`.

Spawn the one seat with the Task tool. After the seat preamble, its prompt:

```
You are the only reviewer of this change. No scrutiny, code review or QA panel
runs after you, so judge the whole change on three questions.

1. Correctness against the acceptance criteria. Does every criterion in the
   packet have an implementation in the diff that would make it true? Does
   the change do what the criteria say, including the error and edge cases
   they name? Does it break anything the diff touches that the criteria don't
   mention?
2. Maintainability. Can the next developer understand and modify this code?
   Are names, implicit contracts and context clear? Where a non-obvious
   decision was made, does a comment record why, and is it still true of the
   code beside it?
3. Edited tests. For each test the packet's "Test changes" section lists as
   edited, does the edit correct a test that checked the wrong thing
   (corrects), or does it check less than before, or something easier to
   pass (weakens)? Return one test_edits item per edited test, with its path,
   its judgment and a one-line reason. A test listed as added needs none.

A blocking finding is one that would make a criterion false, break existing
behaviour, or leave the next developer likely to break it: the same bar a
code-review seat applies. Everything else is advisory.
```

## Which Seat Runs

On entering `light_review`, koto runs `scripts/panel-scope.sh --plan light` and writes `light_scope.json`. The decisions mean what they mean in `phase-4a-scrutiny.md`: in a full round the seat is `full` and answers its own unclosed findings by id; any other round keeps it and plans at most one run, the re-verifier (seat `reverifier`, decision `recheck`), which answers each due finding by id and, when its decision carries `fix_review`, reviews the fix diff. It gets the `recheck` packet on the commissioning line above and the re-check prompt in `review-seat-commissioning.md` in place of the prompt above. When nothing runs and no blocking finding is unclosed, koto writes a carried `light_results.json` and moves on to `verification` without stopping here.

```bash
koto context get <WF> light_scope.json
```

## Evidence Format

The seat writes full findings to a `mktemp`-produced file outside the repository and returns a compact JSON summary:

```json
{
  "focus": "light",
  "summary": "<1-3 paragraphs>",
  "cited": [{"path": "src/a.sh", "lines": "10-24"}],
  "findings": [{"severity": "advisory", "summary": "<one line>", "path": "src/a.sh", "lines": "12"}],
  "test_edits": [{"path": "tests/a_test.sh", "judgment": "corrects", "reason": "<one line>"}],
  "detail_file": "<the reviewer's mktemp path>"
}
```

`cited` and `findings` mean what they mean in `phase-4a-scrutiny.md`, and every finding carries a `severity` of `blocking` or `advisory`: the seat is blocking exactly when one finding is `blocking`, and a finding without a severity makes `--record` refuse the round. Delete the detail file once the round is aggregated; anything worth keeping goes into `light_results.json`.

## Aggregation

Record the round, passed or blocking, as `phase-4a-scrutiny.md` describes, with `light` as the panel: the `reviewer` seat in a full round, or the re-verifier answering each due finding by id with `holds` or `reverified`, a reason on each `reverified` (it may not dismiss one):

```bash
ROUND=$(mktemp)
# write the JSON array with the one run, {"seat": "reviewer", "run": "light-r1-reviewer", ...}
# or {"seat": "reverifier", "run": "light-r2-reverifier", "answers": [...]}, to "$ROUND"
"${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/panel-scope.sh" --record light <WF> "$ROUND" && rm -f "$ROUND"
```

If `--record` fails, fix it and run it again before submitting anything; if it can't be fixed, submit `light_outcome: blocking_escalate`.

Then tick koto with nothing submitted. The `light_verdict` gate reads the ledger (`panel-scope.sh --verdict light`) and decides, as at scrutiny:

- Exit 0, every run recorded and every blocking finding closed: koto advances to `verification`. Optionally write `light_results.json` first, as the round's summary for a reader; no gate reads it.
- Exit 1, a blocking finding is unclosed: the gate prints one finding per unclosed blocking finding, under the active rule it cites or under `panel/open-finding`. Submit `light_outcome: blocking_retry` via the Retry Loop below, once the retry budget in the state's directive grants it (otherwise escalate). That routes to `implementation`, where the coder agent takes the findings; the run then walks forward through the review-level check, which gathers the facts again and may hold the run until the level is raised (a fix that grows the change can take it past a threshold), and re-enters this phase only if the level is still `light`.
- Exit 2, the round isn't recorded or the ledger can't be read: record the round and tick again.

```bash
# Optional: the round's summary for a reader. No gate reads it; skip
# straight to `koto next` if you don't write one.
koto context add <WF> light_results.json <<EOF
{"round": <N>, "summary": "<one line>"}
EOF
koto next <WF> --no-cleanup
```

`<N>` is the number of the light round that just ran: 1 the first time through, incremented on each pass through the retry loop below.

## Retry Loop

Run this only once the retry budget in the state's directive has granted the retry. The retry budget is `"${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/panel-retry-budget.sh" <WF> light_review`, with no count: it reads the panel's unclosed blocking findings from the ledger itself. Exit 0 grants the retry; any other exit refuses it, and you escalate with the reason it printed. When a blocking finding sends the work back, clear every artifact the return trip invalidates before submitting the retry. Run this instead of a bare `koto next`:

```bash
OUTCOME_FIELD=light_outcome
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

Every panel's key goes, not only this one's: if the level is raised on the way back, the run enters scrutiny and review, and neither may be read on a summary written before the fix; their verdicts come from the ledger. `phase-4a-scrutiny.md` explains the removal and the two checks. The verdict ledger and the review-level ledger stay.

## Escalation

If a blocking finding cannot be resolved, or the retry budget in the state's directive refuses the retry, submit `light_outcome: blocking_escalate` with `failure_reason`. The workflow routes to `done_blocked`.
