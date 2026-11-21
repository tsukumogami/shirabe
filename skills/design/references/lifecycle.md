# Design Document Lifecycle and Validation

Lifecycle states, transitions, validation rules, and quality guidance for
design documents.

## Lifecycle

```
Draft --> Proposed --> Accepted --> Planned --> Current
                                               |
                                       (or) Superseded
```

| Status | Directory | Transition |
|--------|-----------|------------|
| Draft | `docs/designs/` | Created by /design Phase 0; drafting is under way and the design isn't reviewable yet |
| Proposed | `docs/designs/` | Step 6.5 of /design, after the jury review (or created by /explore) |
| Accepted | `docs/designs/` | Human approval |
| Planned | `docs/designs/` | /plan creates issues |
| Current | `docs/designs/current/` | All issues closed |
| Superseded | `docs/designs/archive/` | Replaced by newer design |

### Status Transition Command

```bash
shirabe transition <path> <target> [--superseded-by <superseding-doc>]
```

Handles status update, file movement (`git mv`), and supersession links.
The `--superseded-by` flag is required when transitioning to `Superseded`.
A design moves back to `Draft` only from `Proposed` (a loop-back during
review); the command refuses `Draft` from any other status.

### Label Lifecycle

If your project uses GitHub labels to track design status (e.g., `needs-design`,
`tracks-plan`), the label transitions for this skill are:

- **Child design superseded:** Revert the parent issue to its pre-design label
  state and update the parent design doc accordingly.

Define your project's specific label names in CLAUDE.md under
`## Label Vocabulary`.

## Validation Rules

### During /plan phase-1 (before creating issues)
- Status must be "Accepted" -- if not, STOP and inform user
- All required sections present

### During /plan phase-6 (after creating issues)
- Status becomes "Planned" (update frontmatter and body)

## Quality Guidance

### Problem Statement
- States the problem, not a solution
- Explains why this matters now
- Scopes what's in and out

### Considered Options

See `considered-options-structure.md` for detailed templates and examples.

### Common Pitfalls
- Too broad ("Improve the system") -- narrow to a specific capability
- No consequences -- every decision has trade-offs
