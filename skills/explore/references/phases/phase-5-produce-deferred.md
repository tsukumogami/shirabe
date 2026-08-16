# Phase 5: Deferred Type (Prototype)

Prototype is the one type the crystallize framework recognizes and `/explore`
does not produce. Prototypes are working code rather than a document, so they
don't fit the produce pattern at all — no arm here writes one, and the step's job
is to route the author to the closest thing that helps.

Present the decision using AskUserQuestion following the pattern in
`${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`.

**Description field:** Explain that Prototype fit the findings best, but
prototype production isn't available through `/explore` — a prototype is code
that needs hands-on development, not a document.

**Recommendation heuristic:** If the exploration focused on one narrow
feasibility question, recommend the spike report — it records the question and
the timebox before anyone spends the day. If the question is "does this work in
our codebase" and the answer comes from trying, recommend filing an issue and
building.

**Options (order by recommendation heuristic):**
1. "File an issue and start building (Recommended)" or "Create a spike report
   (Recommended)"
2. The other option, with the reason it ranks lower
3. "Stop here -- research is saved in wip/"

If the user picks the spike report, follow `phase-5-produce-spike-report.md`.
If the user picks filing an issue, follow `phase-5-produce-file-an-issue.md`.

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- Whatever the chosen option produces, which is nothing on option 3
