---
complexity: simple
complexity_rationale: Planning issue that produces a DESIGN doc; no code changes; simple per the planning-issue convention.
---

## Goal

Produce a DESIGN doc deciding the cache key scheme and storage
location for `extract-context.sh` findings so sibling issues on the
same branch skip redundant remote-branch lookups.

## Context

In the friction-log multi-issue run, `extract-context.sh` warned
"Design doc not found - using issue body only" four separate times
across four sibling issues on one branch. Each invocation
re-investigated the same dead end (the design doc lives in a sibling
repo, not this one). With the resolution strategy from #1 in place,
each lookup may also become more expensive (remote ref scanning), so
caching is doubly motivated.

This depends on #1 being Accepted because the cache key composition
depends on what the resolver actually looks for. If #1 chooses
"explicit `Design: <path> @ <repo>` annotation," the cache key is the
annotated path. If #1 chooses "scan `origin/*` refs," the cache key
must include the ref prefix and the issue's design-doc filename.

Options to evaluate:
- koto context key (`design-doc-resolution.<branch>`)
- tmp file under the per-session tmp directory
- git-branch-scoped state file (e.g., `.git/shirabe/branch-cache.json`)

The DESIGN must spell out the cache invalidation policy: when does the
cache go stale? When the branch changes? When a sibling repo's HEAD
moves?

## Acceptance Criteria

- [ ] `docs/designs/DESIGN-extract-context-cache.md` exists at status
  `Accepted` with all required sections, including an `Alternatives`
  section
- [ ] Design references the resolution strategy from #1
- [ ] Cache invalidation policy is spelled out
- [ ] Decision is concrete enough that `/plan` can decompose it into
  implementation issues
- [ ] Tests pass (run project's test command)
- [ ] CI green

## Dependencies

Blocked by <<ISSUE:1>>.

## Downstream Dependencies

None
