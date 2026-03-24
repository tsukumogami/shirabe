# Issue 18 Summary

## What Changed

Rewrote `skills/work-on/SKILL.md` to use koto orchestration instead of managing
state directly. The ~55-line orchestration wrapper (resume logic + phase dispatch)
was replaced with:

- **Koto Orchestration** section: init, execution loop, evidence submission, resume
- **State-to-Phase Mapping** table: 17 koto states linked to phase reference files
- **Decision Capture** section: mid-state decision recording via `koto decisions`
- **Prerequisites**: koto >= 0.2.1 requirement documented

## Acceptance Criteria Status

- [x] Template file in shirabe's koto-templates directory (PR #20)
- [x] /work-on skill updated to: init koto, loop koto next, submit evidence
- [x] Three input modes: issue-backed, free-form, plan-backed
- [x] Phase injection via State-to-Phase Mapping table
- [x] Session resume via koto workflows + koto next
- [x] Orchestration wrapper eliminated
- [x] koto dependency version pinned (>= 0.2.1 prerequisite)

## Files Modified

- `skills/work-on/SKILL.md` — rewritten (124 insertions, 53 deletions)

## Files Not Modified

- Phase reference files (all 8) — unchanged, koto directives reference them
- Template (`koto-templates/work-on.md`) — already on branch from PR #20
- Extension files — unchanged

## Deferred Items

None. All acceptance criteria addressed.
