# Design Document Lifecycle and Validation

Lifecycle states, transitions, validation rules, and quality guidance for
design documents.

## Lifecycle

```
Proposed --> Accepted --> Planned --> Current
                                      |
                              (or) Superseded
```

| Status | Directory | Transition |
|--------|-----------|------------|
| Proposed | `docs/designs/` | Created by /design or /explore |
| Accepted | `docs/designs/` | Human approval |
| Planned | `docs/designs/` | /plan creates issues |
| Current | `docs/designs/current/` | All issues closed |
| Superseded | `docs/designs/archive/` | Replaced by newer design |

### Status Transition Script

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/transition-status.sh <path> <target> [superseding-doc]
```

Handles status update, file movement (`git mv`), and supersession links.

### Label Lifecycle

If your project uses GitHub labels to track design status (e.g., `needs-design`,
`tracks-plan`), the label transitions for this skill are:

- **Design accepted (Phase 6):** Remove whatever `needs-*` label the source issue
  carries. The tracking label is applied by the planning skill, not here.
- **Child design superseded:** Revert the parent issue to its pre-design label
  state and update the parent design doc accordingly.

Define your project's specific label names in CLAUDE.md under
`## Label Vocabulary`.

## Validation Rules

### During /design or /explore (drafting)
- Frontmatter has all 4 fields (status, problem, decision, rationale)
- Frontmatter status matches body Status section
- All 9 required sections present
- Status is "Proposed"

### During /plan phase-1 (before creating issues)
- Status must be "Accepted" -- if not, STOP and inform user
- All required sections present

### During /plan phase-6 (after creating issues)
- Status becomes "Planned" (update frontmatter and body)
- "Implementation Issues" section added

## Quality Guidance

### Problem Statement
- States the problem, not a solution
- Explains why this matters now
- Scopes what's in and out

### Considered Options

Organized by decision question. Each gets context, then chosen approach, then
alternatives with rejection rationale. Alternatives must be genuinely viable --
future readers need to understand the decision wasn't automatic. See
`considered-options-structure.md` for detailed templates and examples.

### Security Considerations

The Security Considerations section must not be empty. For each dimension that
applies to the design, document risks and mitigations. For dimensions that don't
apply, write a brief explicit justification ("Not applicable because this design
only produces markdown files and executes no external code").

Consumer projects should define domain-specific security dimensions in their
extension file (`@.claude/shirabe-extensions/design.md`).

### Common Pitfalls
- Too broad ("Improve the system") -- narrow to a specific capability
- Strawman options -- alternatives that exist only to justify the preferred choice
- Empty or bare "N/A" security section -- always justify non-applicability
- No consequences -- every decision has trade-offs
