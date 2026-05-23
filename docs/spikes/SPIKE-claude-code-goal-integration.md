---
status: Complete
question: |
  How does Claude Code's new /goal command fit with shirabe's workflow
  skills? Where does it compose, and where is it not a fit?
timebox: "1 session"
---

# SPIKE: Claude Code /goal integration

## Status

Complete

## Question

Claude Code v2.1.139 introduced a `/goal` slash command. At what layer does
it operate relative to shirabe's workflow skills, and where are the
highest-value composition opportunities?

## Context

shirabe's value proposition is durable, multi-phase workflows that produce
artifacts (VISION, PRD, DESIGN, PLAN) and drive end-to-end implementation
through `work-on`, `implement`, and `release`. Several skills include autonomous
modes (`--auto`) with their own "keep going" logic.

In May 2026, Claude Code shipped `/goal`: a built-in slash command that sets a
natural-language completion condition and loops Claude across turns until a
model evaluator verifies the condition holds. On its surface, this looks like
it could touch shirabe's autonomous workflow features. The spike maps where
the two actually meet and where /goal could compose into existing workflows.

The investigation answers three questions:
1. What exactly is /goal (primitive type, behavior, gating)?
2. Where does it meet shirabe's surface?
3. What are the realistic composition opportunities?

## Approach

Three parallel research agents investigated independently:

1. **Official source.** Searched Anthropic docs, the Claude Code changelog,
   GitHub releases, and recent community write-ups for the definition and
   behavior of `/goal`.
2. **Local install.** Swept `~/.claude/` (plugins, marketplaces, sessions,
   settings), the Claude Code binary install under
   `~/.local/share/claude/versions/`, and the on-disk changelog to verify
   what is actually present on a current machine and at what version.
3. **shirabe surface.** Cataloged every shirabe skill — trigger phrases,
   input/output, workflow shape, and stated relationships — to map the
   surface that `/goal` might overlap.

Findings from all three were converged into a single recommendation. No code
was modified during the spike. No prototype of `/goal` composition was
attempted; that's design work that follows from this recommendation.

## Findings

### /goal is a built-in command, not a skill

- **Primitive type:** Built-in slash command at the same level as `/loop`,
  `/clear`, `/compact`. Compiled into the Claude Code binary. Not a skill, not
  a plugin, not an MCP tool.
- **Source visibility:** Internal to Claude Code. The evaluator's system prompt
  is not part of the public surface — it does not appear under
  `~/.claude/plugins/` or elsewhere on disk.
- **Version availability:** Introduced in v2.1.139 (released 2026-05-11). This
  workspace runs v2.1.148, so `/goal` is live now.
- **Gating:** Requires hooks enabled (`disableAllHooks` and
  `allowManagedHooksOnly` both off) and an accepted trust dialog.

### Behavior

`/goal <condition>` sets a natural-language completion condition (up to 4,000
characters). After every Claude turn, a small fast model (Haiku by default)
reads the condition and the conversation transcript, returns yes/no with a
short reason. "No" → reason becomes guidance for the next turn. "Yes" → goal
clears, control returns to the user.

- State is **session-local**. Resume restores the condition; turn count, timer,
  and token-spend baseline reset.
- Conditions must be **verifiable from transcript output** ("all tests pass,"
  "git status clean"). Fuzzy conditions ("code quality is good") don't work.
- Internally it's a wrapper around prompt-based Stop hooks with dedicated UI:
  status-line indicator and overlay showing elapsed time, turn count, and token
  usage.

### Comparison with shirabe

| Dimension | shirabe | /goal |
|-----------|---------|-------|
| Layer | Workflow / artifact production | Session-level execution shell |
| Produces | VISION, PRD, DESIGN, PLAN, issues, PRs | Nothing durable |
| Loop unit | Phases (scope → discover → converge → draft → validate) | Turns |
| Verifier | Jury reviews, structured frontmatter, CI | Single LLM evaluator |
| Persistence | wip/ + committed artifacts | Session only |
| Customization | Editable skills | Built-in binary feature |

The two cover non-overlapping surface area and operate at orthogonal layers:

```
  shirabe:work-on    │  ← workflow / artifact production
  shirabe:implement  │
  shirabe:plan       │
  shirabe:design     │
  shirabe:prd        │
─────────────────────┼─────────────────────────────────────
  /goal              │  ← session-level execution shell
  /loop              │     (autonomous turn-driving)
  Stop hooks         │
─────────────────────┼─────────────────────────────────────
  Claude Code core   │  ← turn execution, tools, memory
```

### Where apparent overlap dissolves on closer look

| Apparent overlap | Closer look |
|------------------|-------------|
| `explore --auto` vs `/goal` autonomous loop | Different granularity. `explore --auto` loops over research rounds with documented decisions; `/goal` loops over turns with a one-shot LLM verdict. |
| `work-on` koto loop vs `/goal` | `work-on` has structured phases (analysis → code → tests → PR → CI); `/goal` is one loop with one verifier. `work-on` could invoke `/goal`; composition doesn't run the other way. |
| `decision` skill vs `/goal` | Decision is jury-based research with adversarial agents producing a YAML artifact. `/goal` is a session-local verifier. The two address different problems. |

### Composition opportunities (deferred to per-opportunity design)

These are entry points where /goal could plausibly augment shirabe. None are
acted on by this spike; each needs its own design doc.

1. **Wrap `work-on` with /goal as a safety net.** Set `/goal "PR for issue #N
   merged and CI green"` around the koto loop. Adds a model-verified backstop
   on top of structured phases.

2. **Use /goal as a top-level checkpoint for `implement-doc`.** Long-running
   doc implementations span many issues; `/goal "all ready issues from
   DESIGN-X.md merged"` provides a clear "done" condition.

3. **Replace `--auto` mode internals with /goal.** Several shirabe skills have
   their own autonomous-mode logic. /goal could take over the "keep going"
   half while shirabe keeps the "what to do next" half.

4. **Simplify CI-waiting in `release` and `ci` skills.** Currently polled in
   custom code; `/goal "release workflow R succeeded"` is shorter but loses
   structured progress reporting.

5. **Documentation framing.** shirabe's README and per-skill docs should
   acknowledge `/goal` and locate it on the layer diagram, so users see how
   the two compose.

### Where /goal is **not** a fit

- **Deterministic verification.** /goal's evaluator is an LLM; for "tests
  exited zero" or "file exists" use real Stop hooks with shell scripts.
- **Artifact production.** /goal produces nothing durable. shirabe's primary
  job is artifacts; /goal can't help there.
- **Multi-session workflows.** PRDs reviewed over days, plans implemented
  across sessions — shirabe carries state via `wip/` and committed artifacts.
  /goal is session-local.

### Open questions

1. **Configurability of the evaluator.** Whether we can ever supply our own
   evaluator prompt (vs. the default Haiku evaluator) shapes how
   ambitiously shirabe should lean on /goal.
2. **Nested autonomy cost.** If `work-on` invokes /goal *and* inner phases
   use auto-mode, two layers of "keep going" stack. Cancellation and runaway
   protection need thinking through.
3. **Provider support.** Documented for the main Anthropic API; unconfirmed
   for Bedrock/Vertex AI deployments.
4. **niwa-mesh interaction.** Coordinator/worker sessions are separate; how
   /goal behaves across delegated tasks is unmapped.

## Recommendation

**No-go on framing /goal as a shirabe replacement.** shirabe and /goal sit at
orthogonal layers: shirabe owns durable artifact-producing workflows, /goal
owns session-level autonomous looping. Neither subsumes the other.

**Go on framing /goal as a composition partner**, conditional on per-opportunity
design before any code changes. Specifically:

- **Land this spike** as the canonical reference for "where does /goal fit
  with shirabe?" so the question doesn't re-litigate.
- **Update shirabe's README** with a short "Relationship to Claude Code core
  primitives" section that names /goal and locates it on the layer diagram.
  Lightweight, no design doc needed.
- **Defer the five composition opportunities** to individual design docs when
  any becomes load-bearing. Don't preemptively integrate.
- **Resolve the configurability question first.** Whether we can supply a
  custom evaluator prompt is the single fact that most changes how heavily
  shirabe should depend on /goal. Worth a follow-up spike if Anthropic
  documentation doesn't clarify within the next release or two.

### Next steps if any composition is picked up

For any of the five opportunities, the right path is `/shirabe:design <topic>`
producing a DESIGN doc that:
- Maps the current skill's autonomous behavior in detail.
- Specifies the exact /goal condition and bounding clause.
- Addresses nested-autonomy cancellation and runaway protection.
- States the failure mode if /goal is unavailable (hooks disabled / older
  Claude Code).

---

## References

- [Keep Claude working toward a goal](https://code.claude.com/docs/en/goal) — Official Claude Code docs
- [Claude Code Changelog](https://code.claude.com/docs/en/changelog) — Release notes (v2.1.139 entry)
