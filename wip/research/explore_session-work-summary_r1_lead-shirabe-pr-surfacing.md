# Lead: How do shirabe skills currently surface PR links and status, and where do they fall short?

## Findings

### /work-on — PR URL is koto evidence, not a chat convention

Source: `public/shirabe/skills/work-on/SKILL.md`, `skills/work-on/references/phases/phase-6-pr.md`, `skills/work-on/references/phases/phase-5-finalization.md`, `skills/work-on/koto-templates/work-on.md`.

- The skill's only user-facing completion instruction is in the execution loop: "If `action: 'done'` — report the outcome and stop" (SKILL.md, Execution Loop step 4). The Output section says only: "A merged PR with passing CI, referenced back to the source issue." Neither specifies a format, requires the PR URL, or defines a template.
- The PR URL is captured as *koto evidence*, not surfaced to the user: `phase-6-pr.md` Evidence section lists `pr_status: created` + `pr_url`. The URL lands in koto's state machine (recoverable via `koto context get`), but nothing instructs the agent to print it in chat.
- The "summary" in `phase-5-finalization.md` is an implementation summary (What Was Implemented / Changes Made / Key Decisions / Requirements Mapping table) piped into koto context under key `summary.md` and committed. It is produced *before* the PR exists, so it cannot carry a PR link — and it is skipped entirely for `docs`, `config`, `chore`, `validation:simple` labels.
- Multi-PR exposure: milestone mode (`/work-on M3`) selects one issue per run; the PLAN `multi-pr` dispatcher runs "one issue at a time... each landing its own PR" with "no cross-issue carry-forward." Nothing in the skill maintains a session-level ledger of PRs already created — each run reports (or doesn't) its own PR once, and earlier links scroll away.

### /execute — one explicit URL hand-back, at one state, in one mode

Source: `public/shirabe/skills/execute/SKILL.md`, `skills/execute/koto-templates/execute.md`.

- The **only place in the entire shirabe corpus that explicitly requires emitting a PR URL to the operator in chat** is the `paused_for_review` terminal (koto-templates/execute.md): "Emit the operator hand-back: **The DRAFT PR URL** — the assembled review surface (`pr_url` from `pr_finalization`). **Confirmation the chain is intact**... **The resume instruction** — re-invoke `/execute <plan>`..." This fires only in interactive mode, only once, at the pause boundary. Under `--auto` this state "is never reached."
- The `done` terminal says only: "Plan orchestration is complete. All per-issue children succeeded, the PR description has been updated, and CI is green." No URL requirement.
- The forced-stop path requires an operator summary but again without link format: "/execute records the operator-facing forced-stop summary (PRD R13): what completed, what remains, and why it stopped" (SKILL.md, Exit Paths).
- Rich per-PR status **exists but lives on GitHub, not in chat**. Two examples:
  - The single-pr PR body Part 2 carries "the per-child outcome table — for each child `name`, `outcome` (`success`/`failure`/`skipped`), `reason`..." (execute.md, `pr_finalization`) — and is *deleted at squash-merge*.
  - The coordinated path maintains a **PR Index** in the coordination PR body: one line per node in the form `<node-id> | <owner/repo:path#number> | <merge-state>` (`references/coordination-strategy.md`, Coordination PR Body Template), re-authored from live `gh` reads on every loop pass. This is the closest thing to a standardized "work in flight" table anywhere in shirabe — multiple PRs, their identities, and their merge states — but the user must find the coordination PR to see it.
- Design intent is explicit that the chat is NOT the record: "The state file is a **reconstructable per-session projection**, not the source of truth. The durable source of truth is the **home pull request**" (SKILL.md, State). The `wip/execute_<topic>_state.md` projection carries `child_snapshots:` (per-child durable status + content fingerprint) — machine state that could feed a summary but has no chat-rendering convention.
- Single-pr mode structurally *mitigates* the multi-PR problem by collapsing a whole plan into one home PR. The unmitigated cases are coordinated mode (N per-repo PRs + 1 coordination PR) and sequential `/work-on` multi-pr runs.

### /plan — links live in artifacts, not chat

Source: `public/shirabe/skills/plan/SKILL.md`, `public/shirabe/references/issues-table.md`.

- Multi-pr output is a "issue table with links" — the canonical Implementation Issues table (`[#N: <title>](<url>)` key column, Dependencies, Complexity, plus a milestone heading linking the milestone URL). This is a standardized, validator-enforced (FC05-FC09) link table — but it is committed into the PLAN/roadmap document, not presented as a chat convention, and it tracks issues, not PRs.
- `issues-table.md` is a strong precedent for how shirabe standardizes a link-bearing status table: one shared reference file, two altitude profiles, machine-validated. A "work-in-flight" table convention would fit the same mold.

### /release — the only skill that says "print in chat"

Source: `public/shirabe/skills/release/SKILL.md`.

- Release is the most chat-explicit skill: Phase 3 step 5: "**Print the notes in chat** so the user can read them." Skill-only fallback prints "`Draft release with notes: <url>`". Phase 6 monitoring: on success "Print release URL"; on timeout "Print run URL: 'Workflow still running -- monitor at <url>'".
- These are ad-hoc one-time prints with per-phase wording — no shared template, no re-surfacing.

### Workspace pr-creation convention — body format only, zero chat surfacing

Source: installed tsukumogami plugin, `~/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/skills/pr-creation/SKILL.md` (the PR-creation skill work-on's extension hook invokes).

- Entirely about PR *content* (two-part squash-merge body, conventional-commit titles, anti-filler heuristics) and CI discipline ("A PR is NOT complete until ALL CI checks pass"; "report the failure and ask for guidance"). There is no instruction anywhere about presenting the created PR's number or URL to the user in chat.
- Its `wait-for-checks.sh` JSON output includes per-failure `link` fields — link data flows through the tooling but stops before the user.

### Cross-cutting observations

1. **No recurring/cadence convention exists anywhere.** Every link surfacing is a one-shot print at an event boundary (PR pause, release URL, failure escalation). No skill or reference instructs re-surfacing links later in a session.
2. **No standard chat template exists.** The formats that do exist (PR Index lines, issues-table, per-child outcome table, forced-stop summary) are all committed-artifact or PR-body formats.
3. **The data is already captured.** `pr_url` is mandatory koto evidence in both work-on and execute templates; `child_snapshots:` carries per-child status; the coordinated loop reads live merge state via `gh` every pass. A summary renderer would be a projection over data that already exists, not new collection.
4. **Workspace hooks exist as an injection point.** The workspace `.claude/hooks/` directory already carries `pre_tool_use` and `stop` hooks, so a hook-based cadence mechanism (e.g., Stop-hook injection) is already an established pattern in this workspace.

## Implications

- The gap is precisely the **chat-visibility layer**: shirabe deliberately makes GitHub (the home PR, the coordination PR-Index) the durable source of truth, and treats chat output as ephemeral. A "work in flight" summary convention would not need new state — it needs (a) a standardized render template and (b) a trigger/cadence rule.
- **Natural template home**: a shared reference file in `public/shirabe/references/` (sibling to `issues-table.md` and `coordination-strategy.md`), which skills bind to by reference — exactly how the PR-Index and issues-table conventions are already distributed. Skills already have natural emit points to bind it into: `/execute`'s `paused_for_review` hand-back (extend to `done`, `done_blocked`, and loop-pass boundaries), `/work-on`'s `done`/`ci_monitor` states, `/release` Phase 6.
- **Cadence cannot come from the skills alone**: skills only run while invoked; a long session spanning several skill invocations has no skill-level place to re-surface earlier PRs. That pushes the recurring mechanism toward a harness feature (Stop/turn-based hook) or a niwa-injected instruction, with shirabe owning only the template + event-boundary emissions.
- The coordinated-mode PR Index shows shirabe's preferred answer to "where do multiple in-flight PRs live": a re-authored durable table keyed to live `gh` state. A chat summary could be defined as "render the PR Index / home-PR status into chat at defined boundaries" rather than inventing a parallel structure.
- One caution from `/execute`'s Security Considerations: its writes are a **closed target set**, and D5 explicitly deferred an automated run-report emit because "it would add a remote write target outside that closed set." A chat-only summary avoids that problem entirely (chat output is not a write target), which argues for chat rendering over, say, posting summary comments to PRs.

## Surprises

- Only one instruction in all of shirabe explicitly requires handing a PR URL to the user (`paused_for_review` in execute's koto template) — and it only fires in interactive single-pr mode. The `done` terminals require nothing.
- `/release` is the only skill that uses the words "print ... in chat," confirming there is no shared vocabulary for chat surfacing.
- The implementation summary artifact (`summary.md`) — the thing named "Summary" in work-on — is created *before* the PR exists and can never contain the PR link.
- The per-child outcome table that best describes a multi-issue run is deliberately deleted at merge (Part 2 of the two-part PR body), so even the durable record of "what was in flight" is transient by design.
- Multi-PR pressure is partially designed away: `/plan` defaults to single-pr ("Default: single-pr. Reach for one PR"), so the many-PRs-in-one-session pain concentrates in coordinated mode and repeated independent `/work-on` runs — a narrower surface than it first appears.

## Open Questions

- Can a Claude Code hook (Stop/turn-count) cheaply reconstruct in-flight PR state — via `koto context get`, `wip/execute_<topic>_state.md`, or `gh pr list` — without slowing every turn? Which of those is readable from a hook's context, and what is the cost budget?
- Should the summary convention be event-based (bound to koto state transitions: PR created, CI green, paused, blocked) rather than time/turn-based? Skills can own event boundaries natively; cadence needs the harness.
- If niwa injects the instruction (workspace-level), how does it avoid double-emission when a shirabe skill also emits at its event boundaries? Who owns the template if both layers participate?
- Does the summary need to aggregate across *sessions* (multiple dispatched niwa workers each owning PRs) or only within one chat session? The niwa mesh's progress-reporting tools (`niwa_report_progress`) are a separate role-to-role channel that this exploration hasn't examined in depth.
- Should the template subsume the coordination PR-Index line format (`<node-id> | <owner/repo:path#number> | <merge-state>`) for consistency, or use a friendlier chat rendering?

## Summary

Shirabe captures PR URLs rigorously as koto evidence (`pr_url` is mandatory in both work-on and execute templates) and maintains rich multi-PR status tables on GitHub (the coordinated PR-Index, the per-child outcome table), but exactly one instruction in the whole corpus requires showing a PR URL to the user in chat — execute's interactive `paused_for_review` hand-back — and no skill ever re-surfaces links or defines a standard chat summary template. The implication is that a "work in flight" convention needs no new data collection, only a shared render template (natural home: a `references/` file like `issues-table.md`, bound into skills' existing terminal/hand-back states) plus a cadence mechanism that skills cannot provide alone, pointing at a hook or niwa-injected instruction for the recurring part. The biggest open question is whether a harness hook can cheaply read the already-captured state (koto context, wip state files, `gh`) to drive periodic re-surfacing without per-turn overhead or double-emission against skill-level event boundaries.
