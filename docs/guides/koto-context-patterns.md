# Koto Context Patterns

Rules for when to write, read, and skip reading koto context in workflows
that delegate work to sub-agents.

## Writes

Every artifact produced during the workflow gets stored in koto context via
`koto context add <WF> <key> --from-file <path>`. This is non-negotiable --
koto owns the artifact lifecycle, and content-aware gates depend on keys
existing.

## Reads

Not every stored artifact needs to be read back. The rule:

**Only read from koto context when the content is not already available to
the agent that needs it.**

### When to read

- **Sub-agent needs artifacts from earlier phases.** A freshly spawned agent
  has no conversation history. Pass the workflow name and let the sub-agent
  read what it needs directly from koto.
- **Main agent needs artifacts written by a sub-agent.** The sub-agent
  returns a summary, not the full content. If the main agent needs the
  complete artifact (e.g., reading the full plan to execute it), it must
  read from koto.
- **Resuming an interrupted session.** A new session has no conversation
  history. Read from koto to recover state.

### When not to read

- **Main agent already saw the content.** If the main agent ran a script
  that printed the full content to stdout, or wrote the content itself in
  an earlier phase, it already has it in context. Don't re-read from koto.
- **Sub-agent returns a sufficient summary.** If the summary carries enough
  information for the main agent's next decision, don't read the full
  artifact. The summary exists precisely to avoid this.
- **Passing artifacts between main agent phases in a single session.** The
  main agent's conversation context carries forward. Reading from koto
  duplicates what's already there.

## Sub-agent delegation pattern

When delegating to a sub-agent that needs to read or write koto context:

1. Pass the **workflow name** (`<WF>`) to the sub-agent.
2. The sub-agent reads what it needs directly from koto -- the main agent
   does not pre-read and relay.
3. The sub-agent writes its output to koto and returns a **summary** to the
   main agent.
4. The main agent uses the summary to proceed. It reads the full artifact
   from koto only if a later phase requires the complete content (e.g.,
   executing a plan step-by-step).

This keeps the main agent's context lean and avoids double-reading artifacts
that only the sub-agent needs.
