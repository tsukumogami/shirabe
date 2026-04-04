# DESIGN: Roadmap Creation Skill

## Status

Proposed

## Context and Problem Statement

The roadmap artifact type has a format-reference skill (private plugin) that
defines structure, lifecycle, and validation rules, but no creation workflow.
Users must manually author roadmaps or rely on /explore's inline production
handler (which writes a bare template without guided scoping, research, or
review). Every other major artifact type (PRD, Design Doc, VISION) has a
dedicated creation skill with a multi-phase workflow. Per the strategic
pipeline roadmap's cross-cutting decision, each doc type should have its own
skill that owns format spec, creation workflow, lifecycle management, and
validation.

This design adds a `/roadmap` creation skill to shirabe, following the
pattern established by /vision (the most recently built skill).

## Decision Drivers

- Must follow the cross-cutting decisions from ROADMAP-strategic-pipeline.md:
  dedicated skill per doc type, script-driven transitions, completion
  lifecycle cascades, draft-merge prevention
- Must work both standalone (`/roadmap <topic>`) and via /explore handoff
  (auto-continue from crystallize)
- Must follow the /vision skill pattern (SKILL.md with embedded workflow,
  references/ for format spec and phase files, scripts/ for transitions)
- The private plugin's roadmap SKILL.md defines the format spec -- the new
  skill should adopt it rather than reinventing
- Roadmaps have a simpler lifecycle than VISIONs (Draft -> Active -> Done)
  with no directory movement
- Roadmaps need at least 2 features (single-feature work doesn't need a
  roadmap -- use a PRD)
- /plan already consumes roadmaps (feature-by-feature decomposition with
  needs-* labels) -- the creation skill must produce output that /plan
  can consume
