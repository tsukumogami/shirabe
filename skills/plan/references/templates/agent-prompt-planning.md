# Agent: Planning Issue Body Generation

You are generating the body for a **planning issue** as part of the `/plan` command when processing a roadmap.

Planning issues track the creation of upstream artifacts (PRDs, designs, spikes, decisions) rather than code-level implementation. They are always `simple` complexity.

## Your Task

Generate a complete planning issue body. The issue must clearly define what artifact needs to be produced, its expected format, and how to verify completion.

## Context

### Source Document

The roadmap that this planning issue is derived from:

Roadmap: `{{DESIGN_DOC_PATH}}`

```
{{DESIGN_DOC_CONTENT}}
```

### This Issue

**Internal ID**: {{ISSUE_ID}}
**Title**: {{ISSUE_TITLE}}
**Dependencies**: {{ISSUE_DEPENDENCIES}}
**Feature**: This issue plans the following feature from the roadmap:

```
{{ISSUE_SECTION}}
```

**needs_label**: {{NEEDS_LABEL}}

### Downstream Dependents

These issues depend on THIS issue. Your deliverables must enable them to proceed:

{{DOWNSTREAM_DEPENDENTS}}

If no downstream dependents are listed, this is a leaf node -- focus on delivering the required artifact.

### Temporary ID Format

**Important**: GitHub issue numbers don't exist yet. Use the placeholder format `<<ISSUE:N>>` for all issue references, where N is the internal ID.

**Standard format**: `<<ISSUE:N>>`
- Regex pattern: `<<ISSUE:\d+>>`
- Example: `<<ISSUE:1>>`, `<<ISSUE:2>>`, `<<ISSUE:12>>`

**Usage in body:**
- Dependencies section: `Blocked by <<ISSUE:1>>, <<ISSUE:2>>`
- Downstream deliverables: `(required by <<ISSUE:5>>)`
- Anywhere an issue number would appear: `<<ISSUE:N>>`

Phase 7 will substitute these placeholders with actual GitHub issue numbers (e.g., `#291`) when creating issues.

### Execution Mode

{{EXECUTION_MODE}}

**If execution_mode is "single-pr":**
- Produce a lighter structured outline instead of a full issue body
- Focus on: goal, acceptance criteria, and dependencies
- Complexity is always `simple` for planning issues

**If execution_mode is "multi-pr":**
- Produce the full planning issue body with all sections
- Complexity is always `simple` for planning issues

## Complexity

Planning issues are always classified as `simple`. They produce artifacts (documents), not code. No validation scripts or security checklists are needed.

## Acceptance Criteria Style

Planning issue AC must be **artifact-oriented**. Each criterion should verify one of:

1. **Exists** -- the artifact file exists at the expected path
2. **Status** -- the artifact has the correct lifecycle status
3. **Format** -- the artifact follows its schema or template

**Example AC for a needs-design issue:**
```markdown
- [ ] `docs/designs/DESIGN-<feature>.md` exists
- [ ] Design doc status is "Proposed" (ready for review)
- [ ] Design doc follows the design-doc skill schema
- [ ] Design doc references this issue as `spawned_from`
```

**Example AC for a needs-prd issue:**
```markdown
- [ ] `docs/prds/PRD-<feature>.md` exists
- [ ] PRD status is "Proposed" (ready for review)
- [ ] PRD follows the prd skill schema
- [ ] PRD references this issue as `spawned_from`
```

**Example AC for a needs-spike issue:**
```markdown
- [ ] `docs/spikes/SPIKE-<feature>.md` exists
- [ ] Spike report includes findings and recommendation
- [ ] Spike report references this issue as `spawned_from`
```

**Example AC for a needs-decision issue:**
```markdown
- [ ] `docs/decisions/ADR-<feature>.md` exists
- [ ] Decision record status is "Accepted"
- [ ] Decision record references this issue as `spawned_from`
```

Do NOT include code-level AC like "tests pass" or "CI green" -- planning issues produce documents, not code.

## Output Requirements

### File/Chat Separation

Write the complete issue body to: `wip/plan_{{TOPIC}}_issue_{{ISSUE_ID}}_body.md`

After writing the file, return ONLY the structured summary below. Do NOT include any part of the issue body in your response. The orchestrator reads the file directly -- repeating the body in chat wastes context and risks truncation.

**Structured summary format (return ONLY this):**
```
Status: PASS | VALIDATION_FAILED | ERROR
Complexity: simple
File: wip/plan_{{TOPIC}}_issue_{{ISSUE_ID}}_body.md
Sections: <comma-separated list of sections present>
Dependencies: <issue IDs or "none">
```

### Required Sections (written to file)

The file must include these sections in order:

1. **Goal** -- One sentence stating what artifact this issue produces
2. **Context** -- Why this feature needs this type of artifact. Must include:
   - `Roadmap: \`<path>\`` with the parent roadmap path (from `{{DESIGN_DOC_PATH}}` above)
   - `Feature: <feature-name>` identifying which roadmap feature this issue plans
3. **Acceptance Criteria** -- Artifact-oriented checkboxes (exists, status, format)
4. **Dependencies** -- List blocking issues (or "None")
5. **Downstream Dependencies** -- What dependents need from this issue

### Downstream Deliverables

For each downstream dependent, your AC section MUST include an explicit deliverable:

```markdown
- [ ] Must deliver: <specific artifact> (required by <<ISSUE:N>>)
```

If you cannot determine what a downstream dependent needs, add:
```markdown
- [ ] Must unblock <<ISSUE:N>> -- review dependent's requirements before marking complete
```

## Output Format

Output the issue body markdown with a YAML front matter block.

Start with the front matter, then the issue body:
```
---
complexity: simple
complexity_rationale: Planning issue producing an upstream artifact, not code
---

## Goal

<goal statement>
```

The front matter will be parsed and removed before the issue is created.
