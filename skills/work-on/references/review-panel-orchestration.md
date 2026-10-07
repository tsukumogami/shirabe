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
`scrutiny`; `review`'s `passed` goes to `verification` at `standard` and to
`qa_validation` otherwise. The check holds the run while the level is below the floor
the facts of the change set, so a level raised on a later lap moves the run onto the
longer path.

Each panel state accepts `passed`, `blocking_retry`, or `blocking_escalate`. A `blocking_retry`
returns to `implementation`; `blocking_escalate` routes to `done_blocked` with `failure_reason`
written to context. Panel states carry `override_default` so skipping is auditable via
`koto overrides list`. The retry cap is stated in each panel state's directive.

Every retry clearing step removes all four panels' results keys
(`scrutiny_results.json`, `review_results.json`, `qa_results.json`,
`light_results.json`) and `summary.md`, never `verdict_ledger.json` or the review-level
ledger `review_level.jsonl`.

Verdicts are sticky across retries. On entering each panel state koto runs
`scripts/panel-scope.sh --plan <panel>`, which compares every seat's last verdict in
`verdict_ledger.json` with the fix diff and writes `<panel>_scope.json`: `full` on a
seat's first round, `recheck` for a seat that raised a blocking finding (it gets the
finding plus the fix diff, in a `scripts/review-packet.sh recheck` packet built from
that scope, and checks only that), `rerun` for a passed seat whose cited
files or line ranges the fix touched (or when the acceptance criteria changed, or the
fix crosses the size threshold), and `keep` otherwise. Only seats that aren't `keep`
are spawned. A panel whose every seat is `keep` is carried: the script writes its
results key, the `<panel>_carried` gate passes, and koto advances with no evidence. The
panel state is still entered, so koto's state log counts every round. After each
round, the agent records the spawned seats with `panel-scope.sh --record`; the
`<panel>_recorded` gate holds the `passed` and `blocking_retry` edges until it has. The ledger's
`history` keeps each round's decisions, reasons, and spawn count.

`blocking_escalate` requires a `failure_reason`
field; omitting it prevents koto context_assignments from propagating the reason downstream.
