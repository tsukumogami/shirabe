# Phase 5: ROADMAP Handoff

Write `wip/roadmap_<topic>_scope.md` matching /roadmap Phase 1's output format.
Synthesize content from the exploration findings -- don't just copy raw
research output.

```markdown
# /roadmap Scope: <topic>

## Theme Statement
<2-3 sentences synthesized from exploration. Describe the initiative being
sequenced and why coordination across features matters, grounded in what the
exploration discovered.>

## Initial Scope
### This Roadmap Covers
- <feature area from exploration findings>
- <feature area>

### This Roadmap Does NOT Cover
- <excluded area with reasoning>

## Candidate Features
1. <feature>: <rationale from exploration>
2. <feature>: <rationale>

## Coverage Notes
<Gaps or uncertainties to resolve during roadmap creation. What did the
exploration NOT answer about sequencing, dependencies, or feature boundaries?
Note any coverage dimensions that lack even surface coverage: feature
completeness, dependency mapping, sequencing rationale, scope boundaries.>

## Decisions from Exploration
<If wip/explore_<topic>_decisions.md exists, include accumulated decisions
here. These are scope narrowing, option eliminations, and priority choices
already made during exploration that the roadmap should treat as settled.
If the decisions file doesn't exist, omit this section.>
```

After writing, hand off to /roadmap:

1. Commit: `docs(explore): hand off <topic> to /roadmap`
2. **Detect an upstream STRATEGY.** Check the crystallize artifact
   (`wip/explore_<topic>_crystallize.md`) and findings for a STRATEGY
   document path. If the exploration identified a specific STRATEGY
   (e.g., `docs/strategies/STRATEGY-<name>.md`), pass it as `--upstream`
   in the invocation. If none was identified, omit the flag.

   **Do not pass a VISION.** A ROADMAP's only legal upstream is the
   STRATEGY it sequences, and `/roadmap`'s own contract already says a
   VISION must not be substituted for one — it would skip an altitude and
   leave the strategic reasoning at that altitude unreachable from the
   path a reader walks. `/roadmap` enforces no basename on the flag, so
   nothing downstream catches the substitution; `shirabe validate` reports
   it as an `R10` direction violation once the roadmap is written. When
   the exploration found a VISION but no STRATEGY, omit the flag and name
   the VISION in the handoff artifact's prose instead.
3. Invoke the roadmap skill:
   - With STRATEGY: `/shirabe:roadmap <topic> --upstream <strategy-path>`
   - Without: `/shirabe:roadmap <topic>`
4. The roadmap skill detects the handoff artifact and resumes at Phase 2
   (Discover). Phase 1 (Scope) is already done -- the handoff artifact
   fills that role.

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- `wip/roadmap_<topic>_scope.md` (new)
- Session continues in /roadmap at Phase 2
