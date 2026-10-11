# wip/ Hygiene

Rules for how shirabe-driven workflows treat the `wip/` directory and what
counts as a durable reference.

## What `wip/` is

`wip/` (Work In Progress) was a per-branch scratch space for intermediate
artifacts from multi-phase workflows. shirabe's skills no longer write there:
they keep intermediate state in koto sessions, under
[`skill-session-convention.md`](skill-session-convention.md). A file that does
sit under `wip/` on a branch is non-durable, and no workflow step writes,
sweeps or gates on it.

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
that says "a staging file is not a durable reference" is rule-statement
prose. A line that says "see `wip/PR-foo.md` for the draft" is a path-shaped
reference and a hard fail.

## Why

`wip/` content is not part of merged history. A reference to a `wip/...`
path resolves to nothing once the branch merges. The reader of the merged
artifact is left with a broken link to a file that never reached main.

When a `wip/...` path also crosses a visibility boundary -- for example, a
coordinator stages a private-repo PRD into a public repo's `wip/` as a
handoff, and a design agent then writes `upstream: wip/PRD-<topic>.md` into
public frontmatter -- the failure compounds. The reference is simultaneously
non-durable AND a public->private link (forbidden per
[`cross-repo-references.md`](cross-repo-references.md)).

## Where this rule is enforced

Phase scripts hard-stop on violations. Workflows that produce a durable
artifact include an explicit grep step before the artifact lands:

| Skill | Phase step | Surface checked |
|-------|-----------|-----------------|
| `skills/design` | [Phase 0 step 0.4a](../skills/design/references/phases/phase-0-setup-prd.md) | The `upstream:` value before the design doc skeleton is written |
| `skills/design` | [Phase 6 step 6.4](../skills/design/references/phases/phase-6-final-review.md) | The full design doc body and frontmatter before commit |
| `skills/plan`   | [Phase 7 step 7.4b](../skills/plan/references/phases/phase-7-creation.md) | The full PLAN doc body and frontmatter before status transition |
| `skills/prd`    | [Phase 3 step 3.1](../skills/prd/references/phases/phase-3-draft.md) | The `--upstream` value before the PRD draft is written |
| `skills/roadmap` | [Phase 3 step 3.1](../skills/roadmap/references/phases/phase-3-draft.md) | The `--upstream` value before the ROADMAP draft is written |
| `skills/charter` | [Phase 0 step 0.4](../skills/charter/references/phases/phase-0-setup.md) | The `--upstream` value before it is recorded in `consumed_upstream:` and handed to `/strategy` |
| `skills/scope`  | [Phase 0 Upstream Validation](../skills/scope/references/phases/phase-0-setup.md) | The `--upstream` value before it is recorded in `consumed_upstream:` and handed to `/brief` |
| `skills/strategy` | [Phase 0 step 0.3](../skills/strategy/references/phases/phase-0-setup.md) | The `--upstream` value before the STRATEGY draft is written |
| `skills/brief`  | [Phase 0 step 0.3](../skills/brief/references/phases/phase-0-setup.md) | The `--upstream` value before the BRIEF draft is written |

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
