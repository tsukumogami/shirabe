# Exploration Decisions: session-work-summary

## Round 1 (setup/scoping)
- Host exploration in public/shirabe: the core question is a workflow-convention question (shirabe's domain); niwa injection is one delivery mechanism under evaluation. If crystallize routes the artifact to niwa, the handoff will say so.
- Work in a session worktree (branch docs/session-work-summary) because this background session must isolate edits from the shared checkout.
- Skip conversational scoping loop: session runs autonomously and the user's brief already covers intent, constraints (no per-message summaries), candidate homes, and cadence preferences. Leads derived directly from the brief.
- Adversarial demand lead not fired: concrete problem statement exists (PR links hard to find in long multi-PR chats), so topic is not classified as directional (only one of three signals present).

## Round 1 (convergence)
- Cadence: event-gated push (PR set changes) + return-after-absence reminder, with shared dedupe state. Timer/turn-count rejected — user accepted the research recommendation (no prior art for timed digests; turn-count fires at the worst moments; UserPromptSubmit dead in -p sessions).
- Placement boundary: shirabe stays hook-free. Verified in repo: shirabe's plugin.json declares only `skills` — no hooks.json, no hook scripts. Hook wiring is niwa's established responsibility (dot-niwa .niwa/hooks/ + materializer). shirabe owns the summary template + skill emission rules; niwa/dot-niwa owns cadence hook delivery.
- Explore further (round 2): validate the mechanics and the layer contract rather than re-litigate direction — layer coordination without double emission, empirical hook-injection behavior, background/dispatched session surfacing, concrete template format.

## Round 2 (convergence)
- Byproduct bugs (duplicate-hook materialization, dead workflow-continue glob, inverted stop_hook_active guard, stale mesh docs): not filed as issues for now, per user — recorded in findings only.
- Direction pivot: maximize determinism. User challenged the instruction-heavy design; new preferred shape is "hooks ARE the summarizer": PostToolUse hook extracts PR URLs from tool output mechanically, a render script produces the block from gh queries, and `systemMessage` displays it user-visibly with zero model involvement — paired with a lightweight additionalContext echo so the model stays aware. Instructions remain only where scripts can't reach (dispatched-worker final message, conversational /status).
- Explore further (round 3): empirically validate the deterministic pipeline before crystallizing — systemMessage rendering/persistence semantics, a working capture+render prototype, and the re-cut shirabe/dot-niwa division of labor.
