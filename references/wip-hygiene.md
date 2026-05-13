# wip/ Hygiene

Rules for how shirabe-driven workflows treat the `wip/` directory and what
counts as a durable reference.

## What `wip/` is

`wip/` (Work In Progress) is a per-branch scratch space for intermediate
artifacts produced during multi-phase workflows. Phase scripts in
`skills/design`, `skills/plan`, `skills/prd`, and `skills/explore` write
summaries, research notes, manifests, and coordination state into
`wip/<skill>_<topic>_*.md` and `wip/research/<skill>_<topic>_*.md`.

`wip/` is committed to feature branches so that workflows survive resume.
It is NOT included in merged history: workflows clean it up before the PR
opens, and squash-merge keeps the cleanup out of the main branch trail.

## The rule

`wip/` paths must not appear in any durable reference. The durable surfaces
are:

- Frontmatter fields on committed docs (`upstream:`, `references:`, `source:`,
  any path-shaped value)
- Body prose on committed docs under `docs/` (designs, PRDs, plans,
  roadmaps, guides)
- README files, CLAUDE.md files, and other repo-root markdown
- PR descriptions and issue bodies

Quoted statements of this rule (and of wip/'s purpose) are allowed. A line
that says "wip/ artifacts are tolerated on the branch but must be cleaned
before the PR opens" is rule-statement prose. A line that says "see
`wip/PR-foo.md` for the draft" is a path-shaped reference and a hard fail.

## Why

`wip/` is deleted before merge. A reference to a `wip/...` path resolves
to nothing the moment the cleanup commit lands. The reader of the merged
artifact is left with a broken link to a file the workspace's own cleanup
removed.

When a `wip/...` path also crosses a visibility boundary -- for example, a
coordinator stages a private-repo PRD into a public repo's `wip/` as a
handoff, and a design agent then writes `upstream: wip/PRD-<topic>.md` into
public frontmatter -- the failure compounds. The reference is simultaneously
non-durable AND a public->private link (forbidden per
[`cross-repo-references.md`](cross-repo-references.md)).

## Cleanup is two operations

Cleaning up `wip/` before merge means BOTH:

1. **Delete the wip/ files** (mechanical -- usually a single `rm` or
   `git rm` command per phase script).
2. **Remove every reference to wip/ paths from committed prose** (semantic
   -- requires `git grep -nE 'wip/'` from the repo root, with a manual
   review of each match to distinguish rule-statement prose from
   path-shaped references).

Doing only (1) leaves the references as orphans. Doing only (2) leaves the
files committed.

## Where this rule is enforced

Phase scripts hard-stop on violations. Workflows that produce a durable
artifact include an explicit grep step before the artifact lands:

| Skill | Phase step | Surface checked |
|-------|-----------|-----------------|
| `skills/design` | [Phase 0 step 0.4a](../skills/design/references/phases/phase-0-setup-prd.md) | The `upstream:` value before the design doc skeleton is written |
| `skills/design` | [Phase 6 step 6.4](../skills/design/references/phases/phase-6-final-review.md) | The full design doc body and frontmatter before commit |
| `skills/plan`   | [Phase 7 step 7.4b](../skills/plan/references/phases/phase-7-creation.md) | The full PLAN doc body and frontmatter before status transition |
| `skills/prd`    | [Phase 3 step 3.1](../skills/prd/references/phases/phase-3-draft.md) | The `--upstream` value before the PRD draft is written |

## Verification commands

Run from the repo root before opening any PR that touches `docs/`:

```bash
# Any wip/ path in committed prose under docs/ is a violation.
git grep -nE 'wip/' -- 'docs/**/*.md'

# Any frontmatter upstream/source pointing at wip/ is a violation.
git ls-files 'docs/**/*.md' | xargs -I{} head -20 {} | grep -nE '^(upstream|source|references):.*wip/'
```

Empty output means clean. Any match should be reviewed; rule-statement prose
is acceptable, path-shaped references are not.
