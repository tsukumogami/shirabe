# Review Panel Orchestration

After implementation completes, the workflow passes through three panel states before
finalization:

1. **scrutiny** — three parallel reviewers (completeness, justification, intent). Reference:
   `references/phases/phase-4a-scrutiny.md`. Output: `scrutiny_results.json`.
2. **review** — three parallel reviewers (pragmatic, architect, maintainer). Reference:
   `references/phases/phase-4b-review.md`. Output: `review_results.json`.
3. **qa_validation** — QA validation panel. Reference: `references/phases/phase-4c-qa.md`.
   Output: `qa_results.json`.

Each panel state accepts `passed`, `blocking_retry`, or `blocking_escalate`. A `blocking_retry`
returns to `implementation`; `blocking_escalate` routes to `done_blocked` with `failure_reason`
written to context. Panel states carry `override_default` so skipping is auditable via
`koto overrides list`. The retry cap is stated in each panel state's directive.

Verdicts are sticky across retries. On entering each panel state koto runs
`scripts/panel-scope.sh --plan <panel>`, which compares every seat's last verdict in
`verdict_ledger.json` with the fix diff and writes `<panel>_scope.json`: `full` on a
seat's first round, `recheck` for a seat that raised a blocking finding (it gets the
finding plus the fix diff and checks only that), `rerun` for a passed seat whose cited
files or line ranges the fix touched (or when the acceptance criteria changed, or the
fix crosses the size threshold), and `keep` otherwise. Only seats that aren't `keep`
are spawned. A panel whose every seat is `keep` is carried: the script writes its
results key, the `<panel>_carried` gate passes, and koto advances with no evidence. The
panel state is still entered, so koto's state log counts every round. After each
round, the agent records the spawned seats with `panel-scope.sh --record`. The ledger's
`history` keeps each round's decisions, reasons, and spawn count.

`blocking_escalate` requires a `failure_reason`
field; omitting it prevents koto context_assignments from propagating the reason downstream.
