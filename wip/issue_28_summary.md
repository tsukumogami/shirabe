# Summary

## What Was Implemented

Migrated the work-on skill from direct `wip/` filesystem access to koto's content
ownership API (`koto context add/get/exists`). Template gates now use `context-exists`
type instead of `test -f wip/` commands. Phase files, agent instructions, and
extract-context.sh all route through koto's content store.

## Changes Made

- `skills/work-on/koto-templates/work-on.md` - Replaced 6 `test -f wip/` command gates
  with `context-exists` gates; split combined branch+file gates into separate gates
- `skills/work-on/SKILL.md` - Updated decisions reference to use koto decisions record;
  bumped minimum koto version to 0.3.3
- `skills/work-on/references/phases/phase-0-context-injection.md` - Use extract-context.sh
  with --session flag; retrieve/update via koto context get/add
- `skills/work-on/references/phases/phase-1-setup.md` - Store baseline via koto context add
- `skills/work-on/references/phases/phase-2-introspection.md` - Store introspection via
  koto context add
- `skills/work-on/references/phases/phase-3-analysis.md` - Read baseline/context from koto;
  store plan via koto context add
- `skills/work-on/references/phases/phase-4-implementation.md` - Retrieve plan and context
  from koto context
- `skills/work-on/references/phases/phase-5-finalization.md` - Store summary via koto
  context add; removed manual rm -rf wip/ cleanup
- `skills/work-on/references/agent-instructions/phase-3-analysis.md` - Updated all wip/
  references to koto context API
- `skills/work-on/references/scripts/extract-context.sh` - Added --session flag for direct
  koto context storage with wip/ fallback
- `skills/work-on/evals/evals.json` - Updated expected output for auto-mode-flag eval

## Key Decisions

- Split combined gates (branch check + file check) into separate named gates rather than
  keeping a single compound command gate
- Keep wip/ fallback in extract-context.sh for backward compatibility when --session is
  not provided
- Template gates use simple key names (context.md, baseline.md, plan.md) rather than
  prefixed names, since koto sessions are already namespaced

## Requirements Mapping

| AC | Status | Evidence |
|----|--------|----------|
| Phase files use koto context API | Implemented | phases 0-5 updated |
| Resume logic uses context exists | Implemented | template gates use context-exists type |
| No wip/ references in skill files | Implemented | Only fallback path in extract-context.sh |
| Skill works end-to-end | Needs eval run | Template compiles; evals not yet re-run |
