# Phase 1: Research

Spawn a research agent to build context and identify critical unknowns.

## Resume Check

If key `<key_dir>/research.md` exists in `<session>`, skip to Phase 2.

## Steps

### 1.1 Identify Critical Unknowns

Read the context artifact. Determine what information would change the outcome
if answered differently. Focus on unknowns that differentiate between alternatives,
not background knowledge.

### 1.2 Spawn Research Agent

Allocate a private directory outside the work tree for the agent's findings and
keep the path it prints, `<research-dir>`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch
```

Launch a disposable research agent via the Agent tool. It never calls koto:

```
Agent tool:
  prompt: |
    You are researching a decision: <question>

    Context: <from context artifact>
    Constraints: <constraints>
    Known options: <if any>

    Identify the critical unknowns -- things that would change the outcome
    if answered differently. Research the codebase, documentation, and any
    available resources to answer them.

    For unknowns you can't resolve:
    - In interactive mode: note them for user clarification
    - In non-interactive mode: make a reasonable assumption and document it
      explicitly ("Assumed: <X>. If wrong: <consequence>")

    Write your findings to <research-dir>/research.md, and nowhere else,
    with sections:
    - Research conducted (what you looked at)
    - Findings (what you learned)
    - Assumptions made (if any, with consequences)
    - Clean summary of the problem and critical unknowns

    Return a 3-5 line summary.
```

### 1.3 Collect Results

Turn the findings file into key `<key_dir>/research.md` (`ingest` removes the
directory):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" ingest <session> <key_dir> <research-dir>
```

Read the research summary. If the agent made assumptions (non-interactive mode),
these will propagate into the decision report's Assumptions field.

## Quality Checklist

- [ ] Critical unknowns identified and investigated
- [ ] Research stored as key `<key_dir>/research.md`
- [ ] Assumptions documented if information gaps remain

## Next Phase

Proceed to Phase 2: Alternative Presentation (`phase-2-alternatives.md`)
