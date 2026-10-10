# Phase 0: Context and Framing

Accept the decision question, extract constraints, and create the context artifact.

## Resume Check

If key `<key_dir>/context.md` exists in `<session>` (the names SKILL.md's
Session and Keys defines), skip to Phase 1. A direct run opens its session in
0.1 before this check can read anything.

## Steps

### 0.1 Determine Input Source

**Standalone invocation** (`/decision <question>`):
- Parse `$ARGUMENTS` as the decision question
- If empty and interactive: ask what needs to be decided
- If empty and --auto: infer from branch name, recent issues, or error
- Derive `<topic>` from the question and open the session, as SKILL.md's
  Session and Keys says (`skill-session.sh open decision <topic>`, then
  `skill-session.sh adopt decision <topic>`); `<session>` is
  `decision-<topic>`, `<key_dir>` is `work`, `<report_key>` is
  `work/report.md`

**Sub-operation invocation** (from parent skill via agent):
- Read the `decision_context` from the agent prompt
- Extract: question, session, key_dir, report_key, options (if pre-identified), constraints, background, complexity
- Open, adopt and close nothing: the parent owns the session

### 0.2 Build Context

From the input, derive:
- **Decision question**: one clear sentence
- **Decision drivers**: constraints and priorities from the parent or from research
- **Known options**: pre-identified alternatives (may be empty)
- **Background**: relevant context from the parent's domain
- **Complexity**: standard (fast path) or critical (full path)

If invoked standalone, read the codebase and recent issues to build background context.

### 0.3 Write Context Artifact

Write key `<key_dir>/context.md` in `<session>` (`koto context add <session>
<key_dir>/context.md`, the content on stdin):

```markdown
# Decision Context: <question>

## Question
<one sentence>

## Complexity
<standard | critical>

## Constraints
- <constraint 1>
- <constraint 2>

## Known Options
- <option 1> (if any pre-identified)

## Background
<relevant context>
```

## Quality Checklist

- [ ] Decision question is a clear, answerable sentence
- [ ] Complexity is assigned (determines fast path vs full path)
- [ ] Context key written to `<session>`

## Next Phase

Proceed to Phase 1: Research (`phase-1-research.md`)
