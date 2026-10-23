# Review Panel Orchestration

After implementation completes, a code change passes `review_level_check` and then the
panel states its review level names (`references/review-levels.md`):

1. **scrutiny** — three parallel reviewers (completeness, justification, intent). Reference:
   `references/phases/phase-4a-scrutiny.md`. Output: `scrutiny_results.json`.
2. **review** — three parallel reviewers (pragmatic, architect, maintainer). Reference:
   `references/phases/phase-4b-review.md`. Output: `review_results.json`.
3. **qa_validation** — QA validation panel. Reference: `references/phases/phase-4c-qa.md`.
   Output: `qa_results.json`.
4. **light_review** — one reviewer seat covering correctness against the acceptance
   criteria and maintainability. Reference: `references/phases/phase-4d-light.md`.
   Output: `light_results.json`.

| Level | Panels | Seats per round |
|-------|--------|-----------------|
| `light` | light_review | 1 |
| `standard` | scrutiny, review | 6 |
| `full` | scrutiny, review, qa_validation | 7 |
| unset (a session from an earlier template) | scrutiny, review, qa_validation | 7 |

`review_level_check` routes `light` to `light_review` and every other level to
`scrutiny`; a passing `review` goes to `verification` at `standard` and to
`qa_validation` otherwise. The check holds the run while the level is below the floor
the facts of the change set, so a level raised on a later lap moves the run onto the
longer path.

A panel's pass is koto's, not the agent's. Every finding a seat returns carries
`severity: blocking` or `severity: advisory`; `panel-scope.sh --record` records a seat as
blocking exactly when one of its findings is `blocking`, and refuses a round with a finding
that has neither. Each panel state's `<panel>_verdict` gate runs `panel-scope.sh --verdict
<panel>` over the ledger: exit 0 (every run recorded, every blocking finding closed) advances with no
evidence, exit 1 (a blocking finding is unclosed) prints one finding per unclosed
blocking finding, under the rule it cites or `panel/open-finding`, and accepts `blocking_retry` or `blocking_escalate`, and exit 2 (the round
isn't fully recorded, or the ledger can't be read) holds the state, accepting only
`blocking_escalate`. A `blocking_retry` returns to `implementation`; `blocking_escalate`
routes to `done_blocked` with `failure_reason` written to context. There is no `passed`
value. The verdict gates carry `override_default` so a person's override is the only way
past one, auditable via `koto overrides list`. The retry cap is stated in each panel
state's directive.

Every retry clearing step removes all four panels' results keys
(`scrutiny_results.json`, `review_results.json`, `qa_results.json`,
`light_results.json`) and `summary.md`, never `verdict_ledger.json` or the review-level
ledger `review_level.jsonl`. The results keys are each round's summary for a reader; no
gate reads them for a panel's pass.

Findings are what survive a retry. `verdict_ledger.json` keeps every finding a panel
raised, under a content id, with the records written about it since. On entering each
panel state koto runs `scripts/panel-scope.sh --plan <panel>`, which plans the round from
those findings and writes `<panel>_scope.json`. A full round (the panel's first, or one
where the criteria or plan changed, the history was rewritten, the tree is dirty, or the
fix crosses the size threshold) spawns every seat as `full`, each handed its own unclosed
findings by id. Any other round keeps every seat and plans at most one run, the panel's
re-verifier (seat `reverifier`, decision `recheck`): it answers each finding the fix made
due by id, from a `scripts/review-packet.sh recheck` packet built from that scope, and,
at the first panel a retry enters with a non-empty fix diff, reviews that diff against
every panel's criteria. A panel with nothing to run and no unclosed blocking finding is
carried: the script writes its results key, the `<panel>_carried` gate passes, and koto
advances with no evidence. One with nothing to run but an unclosed blocking finding the
fix didn't touch blocks at `<panel>_verdict` without a run. The panel state is still
entered, so koto's state log counts every round. After each round, the agent records
every run with `panel-scope.sh --record`; the `<panel>_verdict` and `<panel>_recorded`
gates hold the passing and `blocking_retry` edges until it has. The ledger's `history`
keeps each round's decisions, reasons, the finding ids each run carried, and its spawn
count.

## Edited tests

An edited test is reviewed differently from an added one. The shared classifier,
`scripts/lib/test-classify.sh`, calls a test file edited when its diff removes or changes
a line, when it was deleted or renamed with a change, when it is a binary file that
changed, and, for a fix, when a reproducing test changed after its red; a new test file,
or one that only gained lines, is added. The same classifier decides three things, so
they never disagree:

- `review-level.sh facts` records `tests_edited`, and the rule `full tests_edited` floors
  the change at `full`, so the QA seat reviews it too. An added-only change floors at
  `standard`, as any change to a test does.
- The code packet's `## Test changes` section, between the changed paths and the diff,
  lists the added tests by path and the edited tests by path, then each edited test's
  hunks. It says `none` when the change touches no test file.
- Every seat of the panel that runs judges each edited test.

Every seat judges every edited test in the packet as `corrects` or `weakens`.
A seat's entry in the round file carries one `test_edits` item per edited test:

```json
{"seat": "intent", "run": "<run id>", "findings": [], "answers": [],
 "test_edits": [{"path": "tests/greet_test.sh", "judgment": "corrects",
                 "reason": "<optional: what the edit fixes or loses>"}]}
```

`corrects` means the edit fixes a test that checked the wrong thing; `weakens` means it
checks less than before, or checks something easier to pass. `panel-scope.sh --record`
refuses the whole round (exit 65, rule `review/test-edit-judgment`) when a seat of the
panel has no `corrects` or `weakens` item for an edited test, and records each `weakens`
as a blocking finding raised by that seat, under rule `review/test-edit-weakens`, with the
reason in its summary. That finding blocks the panel like any other until the seat
answers it by id. A round with every edited test judged `corrects` records as before.
The re-verifier answers findings by id and judges no test edit; a test edited during a
retry is still held at `pass_counting` until an acceptance seat accepts it.

`blocking_escalate` requires a `failure_reason`
field; omitting it prevents koto context_assignments from propagating the reason downstream.
