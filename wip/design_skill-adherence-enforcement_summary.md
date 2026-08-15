# Design Summary: skill-adherence-enforcement

## Input Context (Phase 0)

**Source:** /explore handoff

**Problem:** Agents with shirabe's skills available fail to run plan-scale work
under the sanctioned workflow — either never invoking the skill, or invoking it
and skipping the koto loop mid-run on a precedence conflict. Both produce no
visibility and no record that validation steps happened.

**Constraints:**
- Must catch both failure modes; a check keyed on invocation is disqualified
- Predicate must not be satisfiable by one honest command
- Must carve out `coordinated` plans, which have no koto session by design
- `ask` is unusable under `bypassPermissions`; gates resolve allow-or-deny
- A gate without a sanctioned bypass manufactures silent failure
- The ordering statement narrows interpretation, never claims precedence over
  session instructions
- `PreToolUse` hooks must fail open on ambiguity
- Prefer guidance staged toward enforcement, per P5
- niwa declares and distributes; shirabe decides

**Open questions carried in:**
- Do skill-registered hooks fire inside subagents? Blocks implementation, since
  `/work-on` children legitimately write source and must be exempted
- Trailer versus run-report emit for off-machine publishing, and the R9 amendment
- Where the ordering statement binds so it holds at every tick
- `koto init` sequencing, given `plan-to-tasks.sh` is called twice per run
- Composition with niwa's existing injected hooks without double-registering

## Current Status

**Phase:** 0 — Setup (Explore Handoff)
**Last Updated:** 2026-08-15
**Scope:** spans shirabe and koto; per coarsest-legal grouping, one PR per repo.
The design doc itself lives in shirabe, which owns the skills and the binary.
