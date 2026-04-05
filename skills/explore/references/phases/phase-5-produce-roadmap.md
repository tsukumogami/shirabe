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
2. **Detect upstream VISION.** Check the crystallize artifact
   (`wip/explore_<topic>_crystallize.md`) and findings for a VISION
   document path. If the exploration identified a specific VISION (e.g.,
   `docs/visions/VISION-<name>.md`), pass it as `--upstream` in the
   invocation. If no VISION was identified, omit the flag.
3. Invoke the roadmap skill:
   - With VISION: `/shirabe:roadmap <topic> --upstream <vision-path>`
   - Without VISION: `/shirabe:roadmap <topic>`
4. The roadmap skill detects the handoff artifact and resumes at Phase 2
   (Discover). Phase 1 (Scope) is already done -- the handoff artifact
   fills that role.

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- `wip/roadmap_<topic>_scope.md` (new)
- Session continues in /roadmap at Phase 2
