# Research Artifact Template

This template defines the standard format for agent research outputs persisted to `wip/research/`.

## Naming Convention

```
wip/research/<command>_<phase>_<role>.md
```

**Components:**
- `<command>`: The slash command (explore, plan, issue, triage, workon)
- `<phase>`: Phase identifier (phase4, phase8, jury, etc.)
- `<role>`: Agent role in kebab-case (review, architecture-review, security-review, architect, implementer, scope, user, maintainer)

**Examples:**
- `explore_phase4_review.md` - /explore Phase 4 review agent
- `explore_phase8_architecture-review.md` - /explore Phase 8 architecture reviewer
- `explore_phase8_security-review.md` - /explore Phase 8 security reviewer
- `triage_jury_architect.md` - /triage jury architect perspective
- `triage_jury_implementer.md` - /triage jury implementer perspective
- `triage_jury_scope.md` - /triage jury scope analyst
- `issue_phase1_user.md` - /issue Phase 1 user perspective
- `issue_phase3_maintainer.md` - /issue Phase 3 maintainer perspective
- `plan_phase5_review.md` - /plan Phase 5 review agent

## Template Structure

When writing research output, use this format:

```markdown
# Research: <Title>

## Metadata
- **Command**: <command name, e.g., /explore>
- **Phase**: <phase number and name, e.g., Phase 8 - Final Review>
- **Agent Role**: <role description, e.g., Architecture Reviewer>
- **Timestamp**: <ISO 8601 timestamp>

## Questions Addressed

1. <Question from phase instructions>
2. <Question from phase instructions>
3. ...

## Findings

<Full research output, organized by question or topic>

### <Topic or Question 1>

<Detailed findings>

### <Topic or Question 2>

<Detailed findings>

## Key Takeaways

<Concise summary of main findings and recommendations>

- <Key point 1>
- <Key point 2>
- <Key point 3>
```

## Usage Instructions

When a phase instructs an agent to write research output:

1. **Agent receives**: Output file path and template reference in prompt
2. **Agent writes**: Full research to the specified file using this template
3. **Agent returns**: Only a summary (key takeaways) to the main conversation

This pattern keeps the main context window focused on summaries while preserving full research details for later reference.

## Example Agent Prompt Addition

Phase files should include this instruction pattern:

```markdown
**Output file**: Write your full research to `wip/research/<command>_<phase>_<role>.md`
using the research artifact template. Return only a summary (key findings and
recommendations) to this conversation.
```
