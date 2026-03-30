# Explore Scope: explore-auto-continue

## Visibility

Public

## Core Question

How should explore's Phase 5 hand off to downstream skills (/design, /prd, /plan)
after the user confirms a crystallize decision? The current behavior stops and tells
the user to run a separate command. The desired behavior is automatic continuation.

## Context

Issue #22 reports a UX failure: after the user confirms "yes, create a design doc"
during crystallize, the workflow stops instead of continuing into /design. The user
already expressed intent — asking them to re-invoke is unnecessary friction.
The /design resume logic already supports picking up from explore's handoff artifacts.
Same issue likely applies to /prd.

## In Scope

- Phase 5 produce files that hand off to downstream skills
- The routing stub (phase-5-produce.md) that dispatches to produce files
- Resume/handoff contract between explore and downstream skills

## Out of Scope

- Changes to downstream skills themselves (/design, /prd, /plan internals)
- Explore phases 0-4
- The crystallize framework scoring logic

## Research Leads

1. **What does each Phase 5 produce file currently do at the handoff point?**
   Need to read all phase-5-produce-*.md files to understand the current pattern
   and identify which ones stop vs continue.

2. **What context does the downstream skill need from explore's output?**
   The handoff needs to pass accumulated findings, scope, and crystallize decision.
   Need to understand what each downstream skill expects on resume.

3. **What are the resume implications if explore auto-invokes downstream skills?**
   If /design fails mid-way after being auto-invoked from explore, can the user
   resume cleanly? Is the explore session still active or already terminated?
